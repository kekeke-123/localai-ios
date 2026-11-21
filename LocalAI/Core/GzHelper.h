#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 用系统自带的 zlib 解 gzip，逐块写出，边解边报进度。
@interface GzHelper : NSObject

+ (BOOL)gunzipFileAtPath:(NSString *)sourcePath
                  toPath:(NSString *)destinationPath
                progress:(void (^ _Nullable)(double fraction))progress
               errorText:(NSString *_Nullable *_Nullable)errorText;

@end

NS_ASSUME_NONNULL_END
