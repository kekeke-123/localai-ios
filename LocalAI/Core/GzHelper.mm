#import "GzHelper.h"
#include <zlib.h>
#include <stdio.h>

@implementation GzHelper

+ (BOOL)gunzipFileAtPath:(NSString *)sourcePath
                  toPath:(NSString *)destinationPath
                progress:(void (^)(double))progress
               errorText:(NSString **)errorText {
    gzFile in = gzopen(sourcePath.fileSystemRepresentation, "rb");
    if (in == NULL) {
        if (errorText) { *errorText = @"打不开压缩文件。"; }
        return NO;
    }

    FILE * out = fopen(destinationPath.fileSystemRepresentation, "wb");
    if (out == NULL) {
        gzclose(in);
        if (errorText) { *errorText = @"写不了目标文件（空间不够？）。"; }
        return NO;
    }

    long long total = 0;
    NSDictionary * attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:sourcePath error:nil];
    if (attrs) { total = (long long) [[attrs objectForKey:NSFileSize] longLongValue]; }

    const int chunk = 64 * 1024;
    char * buffer = (char *) malloc(chunk);
    if (buffer == NULL) {
        fclose(out);
        gzclose(in);
        if (errorText) { *errorText = @"内存不足。"; }
        return NO;
    }

    gzrewind(in);
    long long written = 0;
    int n = 0;
    BOOL ok = YES;
    double lastReport = -1;

    while ((n = gzread(in, buffer, chunk)) > 0) {
        if (fwrite(buffer, 1, (size_t) n, out) != (size_t) n) {
            ok = NO;
            break;
        }
        written += n;
        if (progress && total > 0) {
            double fraction = (double) written / (double) total;
            if (fraction - lastReport > 0.02) {
                lastReport = fraction;
                progress(fraction > 0.99 ? 0.99 : fraction);
            }
        }
    }

    if (n < 0) { ok = NO; }

    free(buffer);
    fclose(out);
    gzclose(in);

    if (!ok) {
        [[NSFileManager defaultManager] removeItemAtPath:destinationPath error:nil];
        if (errorText) { *errorText = @"解压失败，文件可能没下完。"; }
        return NO;
    }

    if (progress) { progress(1.0); }
    return YES;
}

@end
