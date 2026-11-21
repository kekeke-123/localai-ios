#import "MtmdShim.h"
#include "llama.h"
#include "mtmd.h"
#include "mtmd-helper.h"

#include <atomic>
#include <string>
#include <vector>

static void mtmd_quiet_log(enum ggml_log_level level, const char * text, void * user_data) {
    (void) level;
    (void) text;
    (void) user_data;
}

static bool mtmd_abort_cb(void * data) {
    if (data == nullptr) { return false; }
    return ((std::atomic<bool> *) data)->load();
}

@implementation MtmdBridge {
    llama_model * _model;
    llama_context * _ctx;
    const llama_vocab * _vocab;
    mtmd_context * _mctx;
    std::atomic<bool> _cancel;
    std::atomic<bool> _busy;
}

- (nullable instancetype)initWithModelPath:(NSString *)modelPath
                                mmprojPath:(NSString *)mmprojPath
                             contextLength:(NSInteger)contextLength
                               threadCount:(NSInteger)threadCount
                                 errorText:(NSString *_Nullable *_Nullable)errorText {
    self = [super init];
    if (!self) { return nil; }

    static std::atomic<bool> ready(false);
    bool expected = false;
    if (ready.compare_exchange_strong(expected, true)) {
        llama_log_set(mtmd_quiet_log, nullptr);
        mtmd_log_set(mtmd_quiet_log, nullptr);
        llama_backend_init();
    }

    llama_model_params mp = llama_model_default_params();
    mp.n_gpu_layers = -1;
    _model = llama_model_load_from_file(modelPath.UTF8String, mp);
    if (!_model) {
        _model = llama_model_load_from_file(modelPath.fileSystemRepresentation, mp);
    }
    if (!_model) {
        if (errorText) { *errorText = @"视觉模型文件读不出来（可能还没下载完，或者不是 GGUF）。"; }
        return nil;
    }

    _vocab = llama_model_get_vocab(_model);

    llama_context_params cp = llama_context_default_params();
    cp.n_ctx = (uint32_t) MAX(1024, contextLength);
    cp.n_batch = 512;
    cp.n_ubatch = 512;
    cp.n_threads = (int32_t) MAX(2, threadCount);
    cp.n_threads_batch = (int32_t) MAX(2, threadCount);
    cp.abort_callback = mtmd_abort_cb;
    cp.abort_callback_data = &_cancel;
    cp.no_perf = true;

    _ctx = llama_init_from_model(_model, cp);
    if (!_ctx) {
        llama_model_free(_model);
        _model = nullptr;
        if (errorText) { *errorText = @"文本部分加载失败：内存不够。"; }
        return nil;
    }

    mtmd_context_params tp = mtmd_context_params_default();
    tp.use_gpu = true;
    tp.print_timings = false;
    tp.n_threads = (int32_t) MAX(2, threadCount);
    tp.media_marker = mtmd_default_marker();

    _mctx = mtmd_init_from_file(mmprojPath.UTF8String, _model, tp);
    if (!_mctx) {
        _mctx = mtmd_init_from_file(mmprojPath.fileSystemRepresentation, _model, tp);
    }
    if (!_mctx) {
        llama_free(_ctx);
        llama_model_free(_model);
        _ctx = nullptr;
        _model = nullptr;
        if (errorText) { *errorText = @"视觉投影文件（mmproj）加载失败，检查配套文件是否放对了。"; }
        return nil;
    }

    _cancel.store(false);
    _busy.store(false);
    return self;
}

- (void)dealloc {
    if (_mctx) { mtmd_free(_mctx); _mctx = nullptr; }
    if (_ctx) { llama_free(_ctx); _ctx = nullptr; }
    if (_model) { llama_model_free(_model); _model = nullptr; }
}

- (void)cancel {
    _cancel.store(true);
}

- (std::string)buildPromptWithQuestion:(const std::string &)question {
    std::string marker = mtmd_default_marker();
    std::string user = marker + "\n" + question;

    const char * tmpl = llama_model_chat_template(_model, nullptr);
    if (tmpl != nullptr) {
        std::string system = "你是一个看图说话的中文助手。直接描述画面，简短、具体，不要瞎猜。";
        llama_chat_message msgs[2];
        msgs[0].role = "system";
        msgs[0].content = system.c_str();
        msgs[1].role = "user";
        msgs[1].content = user.c_str();

        int32_t need = llama_chat_apply_template(tmpl, msgs, 2, true, nullptr, 0);
        if (need > 0) {
            std::vector<char> buf((size_t) need + 8, '\0');
            int32_t written = llama_chat_apply_template(tmpl, msgs, 2, true, buf.data(), (int32_t) buf.size());
            if (written > 0) {
                return std::string(buf.data(), (size_t) written);
            }
        }
    }
    return "User:" + user + "\nAssistant:";
}

- (nullable NSString *)describeImageData:(NSData *)imageData
                                question:(NSString *)question
                               maxTokens:(NSInteger)maxTokens
                             temperature:(float)temperature
                                 onToken:(void (^ _Nullable)(NSString *piece))onToken
                               errorText:(NSString *_Nullable *_Nullable)errorText {
    if (!_mctx || !_ctx || !_model) {
        if (errorText) { *errorText = @"视觉模型还没加载好。"; }
        return nil;
    }
    bool expected = false;
    if (!_busy.compare_exchange_strong(expected, true)) {
        if (errorText) { *errorText = @"上一张图还在处理中。"; }
        return nil;
    }
    _cancel.store(false);

    if (imageData.length == 0) {
        _busy.store(false);
        if (errorText) { *errorText = @"图片数据是空的。"; }
        return nil;
    }

    mtmd_helper_init_opt opt = mtmd_helper_init_opt_default();
    struct mtmd_helper_bitmap_wrapper wrapper =
        mtmd_helper_bitmap_init_from_buf(_mctx, (const unsigned char *) imageData.bytes, imageData.length, false, opt);

    mtmd_bitmap * bitmap = wrapper.bitmap;
    if (bitmap == nullptr) {
        _busy.store(false);
        if (errorText) { *errorText = @"图片解码失败，换成 jpg/png 试试。"; }
        return nil;
    }

    std::string prompt = [self buildPromptWithQuestion:std::string(question.UTF8String ?: "")];
    mtmd_input_text itext = { prompt.c_str(), prompt.size(), true, true };

    mtmd_input_chunks * chunks = mtmd_input_chunks_init();
    const mtmd_bitmap * bitmapArray[1] = { bitmap };
    int32_t rc = mtmd_tokenize(_mctx, chunks, &itext, bitmapArray, 1);
    if (rc != 0) {
        mtmd_input_chunks_free(chunks);
        mtmd_bitmap_free(bitmap);
        _busy.store(false);
        if (errorText) { *errorText = [NSString stringWithFormat:@"图片预处理失败（错误码 %d）。", rc]; }
        return nil;
    }

    llama_memory_clear(llama_get_memory(_ctx), true);

    llama_pos n_past = 0;
    rc = mtmd_helper_eval_chunks(_mctx, _ctx, chunks, 0, 0, 512, true, &n_past);
    mtmd_input_chunks_free(chunks);
    mtmd_bitmap_free(bitmap);

    if (rc != 0) {
        _busy.store(false);
        if (errorText) { *errorText = @"视觉编码失败（可能内存不足，或被中断）。"; }
        return nil;
    }

    NSMutableString * output = [NSMutableString string];

    llama_sampler_chain_params sp = llama_sampler_chain_default_params();
    sp.no_perf = true;
    llama_sampler * chain = llama_sampler_chain_init(sp);
    llama_sampler_chain_add(chain, llama_sampler_init_penalties(llama_vocab_n_tokens(_vocab), 64, 1.1f, 0.0f, 0.0f));
    llama_sampler_chain_add(chain, llama_sampler_init_top_k(40));
    llama_sampler_chain_add(chain, llama_sampler_init_top_p(0.9f, 1));
    llama_sampler_chain_add(chain, llama_sampler_init_temp(MAX(0.01f, temperature)));
    llama_sampler_chain_add(chain, llama_sampler_init_dist((uint32_t) (llama_time_us() & 0x7fffffff)));

    llama_batch_ext * batch = llama_batch_ext_init(_ctx);
    int32_t nPredict = (int32_t) MIN(MAX(1, maxTokens), 512);
    int32_t generated = 0;
    bool failed = false;

    while (generated < nPredict) {
        if (_cancel.load()) { break; }
        llama_token id = llama_sampler_sample(chain, _ctx, -1);
        if (llama_vocab_is_eog(_vocab, id)) { break; }
        llama_sampler_accept(chain, id);

        char piece[256];
        int32_t np = llama_token_to_piece(_vocab, id, piece, (int32_t) sizeof(piece), 0, true);
        if (np > 0) {
            NSString * s = [[NSString alloc] initWithBytes:piece length:(NSUInteger) np encoding:NSUTF8StringEncoding];
            if (s) {
                [output appendString:s];
                if (onToken) { onToken(s); }
            }
        }

        llama_batch_ext_clear(batch);
        int32_t idx = llama_batch_ext_add_token(batch, 0, id);
        if (idx < 0) { failed = true; break; }
        llama_pos p = n_past;
        llama_batch_ext_set_pos(batch, idx, &p);
        n_past++;

        int32_t p_rc = llama_process(_ctx, LLAMA_PROCESS_TYPE_DECODE, batch);
        if (p_rc < 0) { failed = true; break; }
        if (p_rc == 2) { break; }
        generated++;
    }

    llama_batch_ext_free(batch);
    llama_sampler_free(chain);
    _busy.store(false);

    if (failed && output.length == 0) {
        if (errorText) { *errorText = @"生成过程中断了（可能是上下文用尽或内存不足）。"; }
        return nil;
    }
    return output;
}

@end
