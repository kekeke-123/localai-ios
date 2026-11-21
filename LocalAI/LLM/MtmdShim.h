#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 视觉语言模型（VLM）桥接：模型 gguf + mmproj 一起加载，输入一张图 + 一句问题，输出文字。
@interface MtmdBridge : NSObject

- (nullable instancetype)initWithModelPath:(NSString *)modelPath
                                mmprojPath:(NSString *)mmprojPath
                             contextLength:(NSInteger)contextLength
                               threadCount:(NSInteger)threadCount
                                 errorText:(NSString *_Nullable *_Nullable)errorText;

- (void)cancel;

/// 让模型看图回答。imageData 是 jpg/png 原始字节。同步阻塞，请放后台线程。
- (nullable NSString *)describeImageData:(NSData *)imageData
                                question:(NSString *)question
                               maxTokens:(NSInteger)maxTokens
                             temperature:(float)temperature
                                 onToken:(void (^ _Nullable)(NSString *piece))onToken
                               errorText:(NSString *_Nullable *_Nullable)errorText;

@end

NS_ASSUME_NONNULL_END
