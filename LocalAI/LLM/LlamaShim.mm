#import "LlamaShim.h"
#include "llama.h"

#include <atomic>
#include <string>
#include <vector>

// 关掉 llama.cpp 往控制台刷的大量日志，避免拖慢主线程
static void localai_log_cb(enum ggml_log_level level, const char * text, void * user_data) {
    (void)level;
    (void)text;
    (void)user_data;
}

static bool localai_abort_cb(void * data) {
    if (data == nullptr) { return false; }
    return ((std::atomic<bool> *) data)->load();
}

@implementation LlamaBridge {
    llama_model * _model;
    llama_context * _ctx;
    const llama_vocab * _vocab;
    std::atomic<bool> _cancelled;
    std::atomic<bool> _busy;
}

- (nullable instancetype)initWithModelPath:(NSString *)path
                             contextLength:(NSInteger)contextLength
                                 threadCount:(NSInteger)threadCount
                                 errorText:(NSString *_Nullable *_Nullable)errorText {
    self = [super init];
    if (!self) { return nil; }

    static std::atomic<bool> backendReady(false);
    bool expected = false;
    if (backendReady.compare_exchange_strong(expected, true)) {
        llama_log_set(localai_log_cb, nullptr);
        llama_backend_init();
    }

    llama_model_params mp = llama_model_default_params();
    // 负数表示把能放到 GPU（iPhone 上是 Metal）的层全部放上去
    mp.n_gpu_layers = -1;

    _model = llama_model_load_from_file(path.UTF8String, mp);
    if (_model == nullptr) {
        _model = llama_model_load_from_file(path.fileSystemRepresentation, mp);
    }
    if (_model == nullptr) {
        if (errorText) { *errorText = @"模型文件读取失败：文件可能不完整，或者不是 GGUF 格式。"; }
        return nil;
    }

    _vocab = llama_model_get_vocab(_model);
    if (_vocab == nullptr) {
        llama_model_free(_model);
        _model = nullptr;
        if (errorText) { *errorText = @"模型词表读取失败。"; }
        return nil;
    }

    llama_context_params cp = llama_context_default_params();
    cp.n_ctx = (uint32_t) MAX(512, contextLength);
    cp.n_batch = 512;
    cp.n_ubatch = 512;
    cp.n_threads = (int32_t) MAX(2, threadCount);
    cp.n_threads_batch = (int32_t) MAX(2, threadCount);
    cp.abort_callback = localai_abort_cb;
    cp.abort_callback_data = &_cancelled;
    cp.no_perf = true;

    _ctx = llama_init_from_model(_model, cp);
    if (_ctx == nullptr) {
        llama_model_free(_model);
        _model = nullptr;
        if (errorText) { *errorText = @"上下文创建失败：内存不足，试试换更小的模型或降低上下文长度。"; }
        return nil;
    }

    _cancelled.store(false);
    _busy.store(false);
    return self;
}

- (void)dealloc {
    if (_ctx) { llama_free(_ctx); _ctx = nullptr; }
    if (_model) { llama_model_free(_model); _model = nullptr; }
}

- (void)cancel {
    _cancelled.store(true);
}

#pragma mark - 提示词拼装

// 把消息数组套上模型自己的聊天模板；模型没带模板时退化成 ChatML。
- (std::string)buildPromptWithMessages:(NSArray<NSDictionary<NSString *, NSString *> *> *)messages {
    std::vector<std::string> roles;
    std::vector<std::string> contents;
    roles.reserve(messages.count);
    contents.reserve(messages.count);

    for (NSDictionary<NSString *, NSString *> * raw in messages) {
        NSString * role = raw[@"role"] ?: @"user";
        NSString * content = raw[@"content"] ?: @"";
        roles.push_back(std::string(role.UTF8String ?: "user"));
        contents.push_back(std::string(content.UTF8String ?: ""));
    }

    std::vector<llama_chat_message> chat;
    chat.reserve(roles.size());
    for (size_t i = 0; i < roles.size(); i++) {
        llama_chat_message msg;
        msg.role = roles[i].c_str();
        msg.content = contents[i].c_str();
        chat.push_back(msg);
    }

    const char * tmpl = _model ? llama_model_chat_template(_model, nullptr) : nullptr;

    if (tmpl != nullptr) {
        int32_t need = llama_chat_apply_template(tmpl, chat.data(), chat.size(), true, nullptr, 0);
        if (need > 0) {
            std::vector<char> buf((size_t) need + 8, '\0');
            int32_t written = llama_chat_apply_template(tmpl, chat.data(), chat.size(), true, buf.data(), (int32_t) buf.size());
            if (written > 0) {
                return std::string(buf.data(), (size_t) written);
            }
        }
    }

    // 兜底：ChatML
    std::string out;
    for (size_t i = 0; i < roles.size(); i++) {
        out += "<|im_start|>" + roles[i] + "\n" + contents[i] + "<|im_end|>\n";
    }
    out += "<|im_start|>assistant\n";
    return out;
}

- (std::vector<llama_token>)tokenize:(const std::string &)text addSpecial:(bool)addSpecial {
    std::vector<llama_token> tokens;
    if (!_vocab) { return tokens; }
    // 一个字节最多对应一个 token，按字节数开缓冲区绝对够用
    tokens.resize(text.size() + 64);
    int32_t n = llama_tokenize(_vocab, text.c_str(), (int32_t) text.size(),
                              tokens.data(), (int32_t) tokens.size(), addSpecial, true);
    if (n < 0) {
        tokens.clear();
        return tokens;
    }
    tokens.resize((size_t) n);
    return tokens;
}

- (NSInteger)countTokensForMessages:(NSArray<NSDictionary<NSString *, NSString *> *> *)messages {
    std::string prompt = [self buildPromptWithMessages:messages];
    return (NSInteger) [self tokenize:prompt addSpecial:true].size();
}

#pragma mark - 生成

- (nullable NSString *)generateWithMessages:(NSArray<NSDictionary<NSString *, NSString *> *> *)messages
                                 maxTokens:(NSInteger)maxTokens
                               temperature:(float)temperature
                                   onToken:(void (^ _Nullable)(NSString *piece))onToken
                                 errorText:(NSString *_Nullable *_Nullable)errorText {
    if (!_ctx || !_model || !_vocab) {
        if (errorText) { *errorText = @"模型还没加载好。"; }
        return nil;
    }
    bool expected = false;
    if (!_busy.compare_exchange_strong(expected, true)) {
        if (errorText) { *errorText = @"上一个回答还没结束。"; }
        return nil;
    }

    _cancelled.store(false);

    std::string prompt = [self buildPromptWithMessages:messages];
    std::vector<llama_token> tokens = [self tokenize:prompt addSpecial:true];
    if (tokens.empty()) {
        _busy.store(false);
        if (errorText) { *errorText = @"提示词转换失败。"; }
        return nil;
    }

    // 上下文装不下时，砍掉前面一段（保留系统消息由调用方负责）
    uint32_t nCtx = llama_n_ctx(_ctx);
    if ((uint32_t) tokens.size() + 64 > nCtx) {
        size_t drop = (size_t) tokens.size() + 64 - nCtx;
        if (drop >= tokens.size()) { drop = tokens.size() / 2; }
        tokens.erase(tokens.begin(), tokens.begin() + (long) drop);
    }

    llama_memory_clear(llama_get_memory(_ctx), true);

    llama_batch_ext * batch = llama_batch_ext_init(_ctx);
    if (batch == nullptr) {
        _busy.store(false);
        if (errorText) { *errorText = @"批处理缓冲区创建失败。"; }
        return nil;
    }

    int32_t nPrompt = (int32_t) tokens.size();
    llama_pos pos = 0;
    bool failed = false;
    std::string failure;

    // 1) 逐批喂入提示词
    int32_t i = 0;
    while (i < nPrompt) {
        if (_cancelled.load()) { break; }
        llama_batch_ext_clear(batch);
        int32_t added = 0;
        while (i < nPrompt && added < 512) {
            int32_t idx = llama_batch_ext_add_token(batch, 0, tokens[(size_t) i]);
            if (idx < 0) { break; }
            llama_pos p = pos;
            llama_batch_ext_set_pos(batch, idx, &p);
            pos++;
            i++;
            added++;
        }
        if (added == 0) { failed = true; failure = "批处理装填失败。"; break; }
        int32_t rc = llama_process(_ctx, LLAMA_PROCESS_TYPE_DECODE, batch);
        if (rc == 2) { failed = true; failure = @"生成被中断。"; break; }
        if (rc < 0) { failed = true; failure = @"模型推理出错（可能是内存不足）。"; break; }
        if (_cancelled.load()) { break; }
    }

    NSMutableString * output = [NSMutableString string];

    if (!failed && !_cancelled.load()) {
        // 2) 采样循环
        llama_sampler_chain_params sp = llama_sampler_chain_default_params();
        sp.no_perf = true;
        llama_sampler * chain = llama_sampler_chain_init(sp);
        llama_sampler_chain_add(chain, llama_sampler_init_penalties(llama_vocab_n_tokens(_vocab), 64, 1.1f, 0.0f, 0.0f));
        llama_sampler_chain_add(chain, llama_sampler_init_top_k(40));
        llama_sampler_chain_add(chain, llama_sampler_init_top_p(0.9f, 1));
        llama_sampler_chain_add(chain, llama_sampler_init_temp(MAX(0.01f, temperature)));
        llama_sampler_chain_add(chain, llama_sampler_init_dist((uint32_t) (llama_time_us() & 0x7fffffff)));

        int32_t generated = 0;
        int32_t nPredict = (int32_t) MIN(MAX(1, maxTokens), (NSInteger) (nCtx / 2));

        while (generated < nPredict) {
            if (_cancelled.load()) { break; }
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
            if (idx < 0) { failed = true; failure = @"回填 token 失败。"; break; }
            llama_pos p = pos;
            llama_batch_ext_set_pos(batch, idx, &p);
            pos++;

            int32_t rc = llama_process(_ctx, LLAMA_PROCESS_TYPE_DECODE, batch);
            if (rc < 0) { failed = true; failure = @"模型推理出错（可能是上下文用尽）。"; break; }
            if (rc == 2) { break; }
            generated++;
        }
        llama_sampler_free(chain);
    }

    llama_batch_ext_free(batch);
    _busy.store(false);

    if (failed) {
        if (errorText) { *errorText = [NSString stringWithFormat:@"%@", failure.c_str()]; }
        if (output.length > 0) { return output; }
        return nil;
    }
    return output;
}

@end
