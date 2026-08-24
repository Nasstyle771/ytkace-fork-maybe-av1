#import "DownloadLog.h"



static const NSUInteger YTKACEDownloadLogLimit = 512 * 1024;
static NSFileHandle *s_logWriteHandle = nil;
static NSUInteger s_currentLogSize = 0;

static NSURL *YTKACEDownloadLogURL(void) {
    static NSURL *cached = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray<NSNumber *> *candidates = @[@(NSDocumentDirectory),
                                            @(NSApplicationSupportDirectory),
                                            @(NSCachesDirectory)];
        for (NSNumber *candidate in candidates) {
            NSURL *base = [NSFileManager.defaultManager
                URLsForDirectory:(NSSearchPathDirectory)candidate.unsignedIntegerValue
                       inDomains:NSUserDomainMask].firstObject;
            if (base == nil) continue;
            NSURL *directory = [[base URLByAppendingPathComponent:@"YTKACE" isDirectory:YES]
                URLByAppendingPathComponent:@"Logs" isDirectory:YES];
            NSError *error = nil;
            if (![NSFileManager.defaultManager createDirectoryAtURL:directory
                                       withIntermediateDirectories:YES
                                                        attributes:nil
                                                             error:&error]) {
                continue;
            }
            NSURL *probe = [directory URLByAppendingPathComponent:@"downloads.log"];
            if (![NSFileManager.defaultManager fileExistsAtPath:probe.path]) {
                [[NSData data] writeToURL:probe atomically:YES];
            }
            cached = probe;
            break;
        }
        if (cached == nil) {
            cached = [NSURL fileURLWithPath:
                [NSTemporaryDirectory() stringByAppendingPathComponent:@"ytkace-downloads.log"]];
        }
        [NSUserDefaults.standardUserDefaults setObject:cached.path
                                                forKey:@"YTKACELogPath"];
    });
    return cached;
}

static dispatch_queue_t YTKACEDownloadLogQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.ytkace.download-log", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static void YTKACEEnsureLogHandle(void) {
    if (s_logWriteHandle != nil) return;
    NSURL *url = YTKACEDownloadLogURL();
    if (![NSFileManager.defaultManager fileExistsAtPath:url.path]) {
        [[NSData data] writeToURL:url atomically:YES];
    }
    s_logWriteHandle = [NSFileHandle fileHandleForWritingToURL:url error:nil];
    [s_logWriteHandle seekToEndOfFile];
    NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:url.path error:nil];
    s_currentLogSize = (NSUInteger)[attrs[NSFileSize] unsignedIntegerValue];
}

void YTKACEDownloadLog(NSString *identifier, NSString *format, ...) {
    if (format.length == 0) return;
    va_list arguments;
    va_start(arguments, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);
    if (message.length > 4096) message = [message substringToIndex:4096];
    NSString *line = [NSString stringWithFormat:@"%@ [%@] %@\n",
        NSDate.date, identifier.length == 0 ? @"download" : identifier, message];
    NSData *lineData = [line dataUsingEncoding:NSUTF8StringEncoding];
    if (lineData.length == 0) return;

    dispatch_async(YTKACEDownloadLogQueue(), ^{
        YTKACEEnsureLogHandle();
        if (s_logWriteHandle != nil) {
            @try {
                [s_logWriteHandle writeData:lineData];
                s_currentLogSize += lineData.length;
            } @catch (__unused NSException *e) {
                s_logWriteHandle = nil;
            }
        }

        if (s_currentLogSize > YTKACEDownloadLogLimit) {
            [s_logWriteHandle closeFile];
            s_logWriteHandle = nil;

            NSURL *URL = YTKACEDownloadLogURL();
            NSData *existing = [NSData dataWithContentsOfURL:URL];
            if (existing.length > YTKACEDownloadLogLimit) {
                NSUInteger keep = YTKACEDownloadLogLimit * 3 / 4;
                NSData *tail = [existing subdataWithRange:NSMakeRange(existing.length - keep, keep)];
                [tail writeToURL:URL atomically:YES];
                s_currentLogSize = tail.length;
            } else {
                s_currentLogSize = existing.length;
            }
            YTKACEEnsureLogHandle();
        }
    });
}

NSString *YTKACEDownloadLogContents(void) {
    __block NSString *contents = @"No download activity yet.";
    dispatch_sync(YTKACEDownloadLogQueue(), ^{
        if (s_logWriteHandle != nil) {
            [s_logWriteHandle synchronizeFile];
        }
        NSString *value = [NSString stringWithContentsOfURL:YTKACEDownloadLogURL()
            encoding:NSUTF8StringEncoding error:nil];
        if (value.length != 0) contents = value;
    });
    return contents;
}

void YTKACEClearDownloadLog(void) {
    dispatch_sync(YTKACEDownloadLogQueue(), ^{
        if (s_logWriteHandle != nil) {
            [s_logWriteHandle closeFile];
            s_logWriteHandle = nil;
        }
        s_currentLogSize = 0;
        [NSFileManager.defaultManager removeItemAtURL:YTKACEDownloadLogURL() error:nil];
    });
}
