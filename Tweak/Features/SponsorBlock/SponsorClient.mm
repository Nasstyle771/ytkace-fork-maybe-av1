#import "SponsorClient.h"
#import "SponsorPreferences.h"
#import <math.h>
#import <os/lock.h>

@interface YTKACESponsorClient ()
@property(nonatomic, strong) NSCache<NSString *, NSArray *> *cache;
@property(nonatomic, strong) NSURLSession *session;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<YTKACESponsorCompletion> *> *inFlight;
@end

@implementation YTKACESponsorClient {
    os_unfair_lock _lock;
}

+ (instancetype)sharedClient {
    static YTKACESponsorClient *client;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        client = [YTKACESponsorClient new];
    });
    return client;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _lock = OS_UNFAIR_LOCK_INIT;
        _cache = [NSCache new];
        _cache.countLimit = 256;
        _inFlight = [NSMutableDictionary dictionary];

        NSURLSessionConfiguration *configuration =
            NSURLSessionConfiguration.ephemeralSessionConfiguration;
        configuration.timeoutIntervalForRequest = 4.0;
        configuration.timeoutIntervalForResource = 6.0;
        configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        configuration.HTTPMaximumConnectionsPerHost = 4;
        _session = [NSURLSession sessionWithConfiguration:configuration];
    }
    return self;
}

- (void)segmentsForVideoID:(NSString *)videoID
                completion:(YTKACESponsorCompletion)completion {
    if (videoID.length == 0) {
        if (completion) completion(@[]);
        return;
    }

    NSArray<NSString *> *categories = YTKACESponsorEnabledCategories();
    if (categories.count == 0) {
        if (completion) completion(@[]);
        return;
    }
    NSString *cacheKey = [NSString stringWithFormat:@"%@|%@", videoID,
                          [categories componentsJoinedByString:@","]];

    NSArray *cached = [self.cache objectForKey:cacheKey];
    if (cached != nil) {
        if (completion) completion(cached);
        return;
    }

    os_unfair_lock_lock(&_lock);
    NSMutableArray<YTKACESponsorCompletion> *pending = self.inFlight[cacheKey];
    if (pending != nil) {
        if (completion) [pending addObject:[completion copy]];
        os_unfair_lock_unlock(&_lock);
        return;
    }
    pending = [NSMutableArray array];
    if (completion) [pending addObject:[completion copy]];
    self.inFlight[cacheKey] = pending;
    os_unfair_lock_unlock(&_lock);

    NSURLComponents *components =
        [NSURLComponents componentsWithString:@"https://sponsor.ajay.app/api/skipSegments"];
    NSData *categoryData = [NSJSONSerialization dataWithJSONObject:categories
                                                            options:0 error:nil];
    NSString *categoryJSON = categoryData == nil ? @"[]" :
        [[NSString alloc] initWithData:categoryData encoding:NSUTF8StringEncoding];
    components.queryItems = @[
        [NSURLQueryItem queryItemWithName:@"videoID" value:videoID],
        [NSURLQueryItem queryItemWithName:@"categories" value:categoryJSON]
    ];
    NSURL *url = components.URL;
    if (url == nil) {
        os_unfair_lock_lock(&_lock);
        NSArray *callbacks = [self.inFlight[cacheKey] copy];
        [self.inFlight removeObjectForKey:cacheKey];
        os_unfair_lock_unlock(&_lock);
        for (YTKACESponsorCompletion block in callbacks) {
            block(@[]);
        }
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];

    __weak YTKACESponsorClient *weakSelf = self;
    NSURLSessionDataTask *task =
        [self.session dataTaskWithRequest:request
                       completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSMutableArray<NSDictionary<NSString *, id> *> *segments =
            [NSMutableArray array];
        NSHTTPURLResponse *http =
            [response isKindOfClass:NSHTTPURLResponse.class]
                ? (NSHTTPURLResponse *)response
                : nil;

        if (error == nil && http.statusCode == 200 && data.length <= 1024 * 1024) {
            id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([json isKindOfClass:NSArray.class]) {
                for (id item in (NSArray *)json) {
                    if (![item isKindOfClass:NSDictionary.class]) {
                        continue;
                    }
                    id category = item[@"category"];
                    id values = item[@"segment"];
                    id actionType = item[@"actionType"];
                    if (![category isKindOfClass:NSString.class] ||
                        ![categories containsObject:category] ||
                        ([actionType isKindOfClass:NSString.class] &&
                         ![actionType isEqualToString:@"skip"]) ||
                        ![values isKindOfClass:NSArray.class] ||
                        [values count] != 2) {
                        continue;
                    }
                    id startValue = values[0];
                    id endValue = values[1];
                    if (![startValue isKindOfClass:NSNumber.class] ||
                        ![endValue isKindOfClass:NSNumber.class]) {
                        continue;
                    }
                    double start = [startValue doubleValue];
                    double end = [endValue doubleValue];
                    if (!isfinite(start) || !isfinite(end) || start < 0.0 || end <= start) {
                        continue;
                    }
                    [segments addObject:@{@"start": @(start), @"end": @(end),
                                          @"category": category}];
                }
            }
        }

        NSArray *result = [segments sortedArrayUsingComparator:
            ^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
                return [left[@"start"] compare:right[@"start"]];
            }];

        __strong YTKACESponsorClient *strongSelf = weakSelf;
        if (strongSelf) {
            if (result.count != 0) {
                [strongSelf.cache setObject:result forKey:cacheKey];
            }
            os_unfair_lock_lock(&strongSelf->_lock);
            NSArray *callbacks = [strongSelf.inFlight[cacheKey] copy];
            [strongSelf.inFlight removeObjectForKey:cacheKey];
            os_unfair_lock_unlock(&strongSelf->_lock);

            dispatch_async(dispatch_get_main_queue(), ^{
                for (YTKACESponsorCompletion block in callbacks) {
                    block(result);
                }
            });
        }
    }];
    [task resume];
}

@end
