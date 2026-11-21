#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 对 llama.cpp 的一层极简封装：加载 GGUF、按聊天消息生成回复。
/// 所有方法都是同步阻塞的，请放到后台线程调用。
@interface LlamaBridge : NSObject

/// 加载模型。失败时返回 nil，并在 errorText 里写入中文原因。
- (nullable instancetype)initWithModelPath:(NSString *)path
                             contextLength:(NSInteger)contextLength
                                 threadCount:(NSInteger)threadCount
                                 errorText:(NSString *_Nullable *_Nullable)errorText;

/// 丢掉已经算好的前缀缓存（清空对话时调用）。
- (void)resetCache;

/// 请求中断当前生成（下一个 token 前生效）。
- (void)cancel;

/// 估算一段消息会占用的 token 数，用于上下文裁剪。
- (NSInteger)countTokensForMessages:(NSArray<NSDictionary<NSString *, NSString *> *> *)messages;

/// 生成回复。onToken 会在生成过程中被频繁回调（后台线程）。
- (nullable NSString *)generateWithMessages:(NSArray<NSDictionary<NSString *, NSString *> *> *)messages
                                 maxTokens:(NSInteger)maxTokens
                               temperature:(float)temperature
                                   onToken:(void (^ _Nullable)(NSString *piece))onToken
                                 errorText:(NSString *_Nullable *_Nullable)errorText;

@end

NS_ASSUME_NONNULL_END
