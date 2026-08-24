#import "DisplayRateHooks.h"
#import "../../YTKACE.h"
#import "../../Runtime/Hooking.h"
#import "../../Runtime/Preferences.h"

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>

static IMP OriginalObjectForInfoDictionaryKey;
static IMP OriginalInfoDictionary;
static IMP OriginalDisplayLinkSetPreferredFrameRateRange;
static IMP OriginalDisplayLinkSetPreferredFramesPerSecond;
static IMP OriginalLayerSetPreferredFrameRateRange;
static IMP OriginalAnimationSetPreferredFrameRateRange;

static id YTKACEObjectForInfoDictionaryKey(NSBundle *receiver, SEL selector, NSString *key) {
    if ([key isEqualToString:@"CADisableMinimumFrameDurationOnPhone"] ||
        [key isEqualToString:@"CADisableMinimumFrameDuration"]) {
        return @YES;
    }
    if (OriginalObjectForInfoDictionaryKey != NULL) {
        return ((id (*)(id, SEL, id))OriginalObjectForInfoDictionaryKey)(receiver, selector, key);
    }
    return nil;
}

static NSDictionary *YTKACEInfoDictionary(NSBundle *receiver, SEL selector) {
    NSDictionary *dict = OriginalInfoDictionary == NULL
        ? nil
        : ((id (*)(id, SEL))OriginalInfoDictionary)(receiver, selector);
    if (dict == nil) return @{@"CADisableMinimumFrameDurationOnPhone": @YES};
    if (dict[@"CADisableMinimumFrameDurationOnPhone"] == nil) {
        NSMutableDictionary *mutableDict = [dict mutableCopy];
        mutableDict[@"CADisableMinimumFrameDurationOnPhone"] = @YES;
        return mutableDict;
    }
    return dict;
}

static void YTKACEDisplayLinkSetPreferredFrameRateRange(CADisplayLink *receiver,
                                                       SEL selector,
                                                       CAFrameRateRange range) {
    if (YTKACEFeatureEnabled(YTKACEForce120HzKey)) {
        if (range.maximum >= 59.0f || range.preferred >= 59.0f) {
            range = CAFrameRateRangeMake(80.0f, 120.0f, 120.0f);
        }
    }
    if (OriginalDisplayLinkSetPreferredFrameRateRange != NULL) {
        ((void (*)(id, SEL, CAFrameRateRange))OriginalDisplayLinkSetPreferredFrameRateRange)(
            receiver, selector, range);
    }
}

static void YTKACEDisplayLinkSetPreferredFramesPerSecond(CADisplayLink *receiver,
                                                         SEL selector,
                                                         NSInteger fps) {
    if (YTKACEFeatureEnabled(YTKACEForce120HzKey) && fps >= 59) {
        fps = 120;
    }
    if (OriginalDisplayLinkSetPreferredFramesPerSecond != NULL) {
        ((void (*)(id, SEL, NSInteger))OriginalDisplayLinkSetPreferredFramesPerSecond)(
            receiver, selector, fps);
    }
}

static Class s_avPlayerLayerClass = Nil;
static Class s_avSampleBufferClass = Nil;
static dispatch_once_t s_videoClassOnceToken;

static void YTKACELayerSetPreferredFrameRateRange(CALayer *receiver,
                                                 SEL selector,
                                                 CAFrameRateRange range) {
    if (YTKACEFeatureEnabled(YTKACEForce120HzKey)) {
        dispatch_once(&s_videoClassOnceToken, ^{
            s_avPlayerLayerClass = objc_getClass("AVPlayerLayer");
            s_avSampleBufferClass = objc_getClass("AVSampleBufferDisplayLayer");
        });
        BOOL isVideoLayer = (s_avPlayerLayerClass != Nil && [receiver isKindOfClass:s_avPlayerLayerClass]) ||
                            (s_avSampleBufferClass != Nil && [receiver isKindOfClass:s_avSampleBufferClass]);
        if (!isVideoLayer) {
            if (range.maximum >= 59.0f || range.preferred >= 59.0f) {
                range = CAFrameRateRangeMake(80.0f, 120.0f, 120.0f);
            }
        }
    }
    if (OriginalLayerSetPreferredFrameRateRange != NULL) {
        ((void (*)(id, SEL, CAFrameRateRange))OriginalLayerSetPreferredFrameRateRange)(
            receiver, selector, range);
    }
}

static void YTKACEAnimationSetPreferredFrameRateRange(CAAnimation *receiver,
                                                     SEL selector,
                                                     CAFrameRateRange range) {
    if (YTKACEFeatureEnabled(YTKACEForce120HzKey)) {
        if (range.maximum >= 59.0f || range.preferred >= 59.0f) {
            range = CAFrameRateRangeMake(80.0f, 120.0f, 120.0f);
        }
    }
    if (OriginalAnimationSetPreferredFrameRateRange != NULL) {
        ((void (*)(id, SEL, CAFrameRateRange))OriginalAnimationSetPreferredFrameRateRange)(
            receiver, selector, range);
    }
}

struct YTKACEASRangeTuningParams {
    CGFloat leadingBufferScreenfuls;
    CGFloat trailingBufferScreenfuls;
};

static IMP OriginalCollectionNodeRangeTuning;
static struct YTKACEASRangeTuningParams YTKACECollectionNodeRangeTuning(id receiver, SEL selector, NSInteger rangeType) {
    (void)receiver;
    (void)selector;
    struct YTKACEASRangeTuningParams params;
    // rangeType 0 = FetchData (network download) -> 4.0 screenfuls ahead
    // rangeType 1 = Display (render bitmaps/layers) -> 2.5 screenfuls ahead
    if (rangeType == 0) {
        params.leadingBufferScreenfuls = 4.0f;
        params.trailingBufferScreenfuls = 1.0f;
    } else {
        params.leadingBufferScreenfuls = 2.5f;
        params.trailingBufferScreenfuls = 0.5f;
    }
    return params;
}

static IMP OriginalCollectionViewLeadingScreens;
static CGFloat YTKACECollectionViewLeadingScreens(id receiver, SEL selector) {
    (void)receiver;
    (void)selector;
    return 4.0f; // Batch-load next page 4 screens before reaching the bottom
}

static BOOL YTKACEAlwaysYes(id receiver, SEL selector) {
    (void)receiver;
    (void)selector;
    return YES;
}

static CGFloat YTKACELeadTime(id receiver, SEL selector) {
    (void)receiver;
    (void)selector;
    return 15.0f;
}

static NSInteger YTKACEPrefetchCount(id receiver, SEL selector) {
    (void)receiver;
    (void)selector;
    return 5;
}

static CGFloat YTKACEScrollDistance(id receiver, SEL selector) {
    (void)receiver;
    (void)selector;
    return 3000.0f;
}

void YTKACEInstallDisplayRateHooks(void) {
    static dispatch_once_t cacheToken;
    dispatch_once(&cacheToken, ^{
        NSURLCache *shared = [[NSURLCache alloc] initWithMemoryCapacity:256 * 1024 * 1024
                                                           diskCapacity:1024 * 1024 * 1024
                                                                diskPath:nil];
        [NSURLCache setSharedURLCache:shared];
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidReceiveMemoryWarningNotification
                                                        object:nil
                                                         queue:NSOperationQueue.mainQueue
                                                    usingBlock:^(__unused NSNotification *note) {
            [NSURLCache.sharedURLCache removeAllCachedResponses];
        }];
    });

    YTKACEInstallInstanceHook(@"NSBundle",
                              @"objectForInfoDictionaryKey:",
                              (IMP)YTKACEObjectForInfoDictionaryKey,
                              &OriginalObjectForInfoDictionaryKey);

    YTKACEInstallInstanceHook(@"NSBundle",
                              @"infoDictionary",
                              (IMP)YTKACEInfoDictionary,
                              &OriginalInfoDictionary);

    YTKACEInstallInstanceHook(@"CADisplayLink",
                              @"setPreferredFrameRateRange:",
                              (IMP)YTKACEDisplayLinkSetPreferredFrameRateRange,
                              &OriginalDisplayLinkSetPreferredFrameRateRange);

    YTKACEInstallInstanceHook(@"CADisplayLink",
                              @"setPreferredFramesPerSecond:",
                              (IMP)YTKACEDisplayLinkSetPreferredFramesPerSecond,
                              &OriginalDisplayLinkSetPreferredFramesPerSecond);

    YTKACEInstallInstanceHook(@"CALayer",
                              @"setPreferredFrameRateRange:",
                              (IMP)YTKACELayerSetPreferredFrameRateRange,
                              &OriginalLayerSetPreferredFrameRateRange);

    YTKACEInstallInstanceHook(@"CAAnimation",
                              @"setPreferredFrameRateRange:",
                              (IMP)YTKACEAnimationSetPreferredFrameRateRange,
                              &OriginalAnimationSetPreferredFrameRateRange);

    for (NSString *nodeClass in @[@"ASCollectionNode", @"ASTableNode"]) {
        YTKACEInstallInstanceHook(nodeClass,
                                  @"rangeTuningParametersForRangeType:",
                                  (IMP)YTKACECollectionNodeRangeTuning,
                                  &OriginalCollectionNodeRangeTuning);
    }

    YTKACEInstallInstanceHook(@"ASCollectionView",
                              @"leadingScreensForBatching",
                              (IMP)YTKACECollectionViewLeadingScreens,
                              &OriginalCollectionViewLeadingScreens);

    for (NSString *configClass in @[@"YTColdConfig", @"YTHotConfig", @"YTGlobalConfig"]) {
        YTKACEInstallInstanceHook(configClass, @"enableFeedPrefetch", (IMP)YTKACEAlwaysYes, NULL);
        YTKACEInstallInstanceHook(configClass, @"feedPrefetchLeadTime", (IMP)YTKACELeadTime, NULL);
        YTKACEInstallInstanceHook(configClass, @"enablePrefetchPrebuffer", (IMP)YTKACEAlwaysYes, NULL);
        YTKACEInstallInstanceHook(configClass, @"prefetchPrebufferPlaybackLeadSeconds", (IMP)YTKACELeadTime, NULL);
        YTKACEInstallInstanceHook(configClass, @"preloadPlaybackControllerEnabled", (IMP)YTKACEAlwaysYes, NULL);
        YTKACEInstallInstanceHook(configClass, @"minVideosToPrefetch", (IMP)YTKACEPrefetchCount, NULL);
        YTKACEInstallInstanceHook(configClass, @"inlineMutedPlaybackMaxPrebufferedSeconds", (IMP)YTKACELeadTime, NULL);
        YTKACEInstallInstanceHook(configClass, @"enableWatchNextPreload", (IMP)YTKACEAlwaysYes, NULL);
        YTKACEInstallInstanceHook(configClass, @"enablePrefetchOnScroll", (IMP)YTKACEAlwaysYes, NULL);
        YTKACEInstallInstanceHook(configClass, @"feedPrefetchScrollDistance", (IMP)YTKACEScrollDistance, NULL);
        YTKACEInstallInstanceHook(configClass, @"enableSectionListPrefetch", (IMP)YTKACEAlwaysYes, NULL);
        YTKACEInstallInstanceHook(configClass, @"isPrefetchEnabled", (IMP)YTKACEAlwaysYes, NULL);
    }

    for (NSString *ctrlClass in @[@"YTSectionListViewController", @"YTInnerTubeCollectionViewController"]) {
        YTKACEInstallInstanceHook(ctrlClass, @"shouldPreloadNextPage", (IMP)YTKACEAlwaysYes, NULL);
        YTKACEInstallInstanceHook(ctrlClass, @"prefetchesItemSectionControllers", (IMP)YTKACEAlwaysYes, NULL);
    }
}
