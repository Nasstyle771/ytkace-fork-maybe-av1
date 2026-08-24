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
static IMP OriginalScrollViewDidMoveToWindow;
static IMP OriginalCollectionViewCellDidMoveToWindow;
static IMP OriginalTableViewCellDidMoveToWindow;
static IMP OriginalASDisplayViewDidMoveToWindow;

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
            range = CAFrameRateRangeMake(24.0f, 120.0f, 120.0f);
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
                range = CAFrameRateRangeMake(24.0f, 120.0f, 120.0f);
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
            range = CAFrameRateRangeMake(24.0f, 120.0f, 120.0f);
        }
    }
    if (OriginalAnimationSetPreferredFrameRateRange != NULL) {
        ((void (*)(id, SEL, CAFrameRateRange))OriginalAnimationSetPreferredFrameRateRange)(
            receiver, selector, range);
    }
}

static BOOL s_isFeedScrolling = NO;
static IMP OriginalInlineIsPlaybackAllowed;
static IMP OriginalMutedIsPlaybackAllowed;

static BOOL YTKACEInlineIsPlaybackAllowed(id receiver, SEL selector) {
    if (s_isFeedScrolling) return NO;
    if (OriginalInlineIsPlaybackAllowed != NULL) {
        return ((BOOL (*)(id, SEL))OriginalInlineIsPlaybackAllowed)(receiver, selector);
    }
    return YES;
}

static BOOL YTKACEMutedIsPlaybackAllowed(id receiver, SEL selector) {
    if (s_isFeedScrolling) return NO;
    if (OriginalMutedIsPlaybackAllowed != NULL) {
        return ((BOOL (*)(id, SEL))OriginalMutedIsPlaybackAllowed)(receiver, selector);
    }
    return YES;
}

static void YTKACESetLayerFrameRateRange(CALayer *layer, CAFrameRateRange range) {
    if (layer == nil) return;
    static SEL setRangeSel = NSSelectorFromString(@"setPreferredFrameRateRange:");
    if ([layer respondsToSelector:setRangeSel]) {
        ((void (*)(id, SEL, CAFrameRateRange))objc_msgSend)(layer, setRangeSel, range);
    }
}

static IMP OriginalScrollViewSetContentOffset;

static void YTKACEScrollViewSetContentOffset(UIScrollView *receiver, SEL selector, CGPoint offset) {
    if (OriginalScrollViewSetContentOffset != NULL) {
        ((void (*)(id, SEL, CGPoint))OriginalScrollViewSetContentOffset)(receiver, selector, offset);
    }
    s_isFeedScrolling = receiver.isDragging || receiver.isDecelerating;
}

static void YTKACEScrollViewDidMoveToWindow(UIScrollView *receiver, SEL selector) {
    if (OriginalScrollViewDidMoveToWindow != NULL) {
        ((void (*)(id, SEL))OriginalScrollViewDidMoveToWindow)(receiver, selector);
    }
    if (receiver.window == nil) return;

    if (YTKACEFeatureEnabled(YTKACEForce120HzKey)) {
        receiver.delaysContentTouches = NO;
        receiver.canCancelContentTouches = YES;
        if ([receiver isKindOfClass:UICollectionView.class]) {
            ((UICollectionView *)receiver).prefetchingEnabled = YES;
        }
        if (@available(iOS 15.0, *)) {
            receiver.panGestureRecognizer.allowedTouchTypes = @[@(UITouchTypeDirect)];
            YTKACESetLayerFrameRateRange(receiver.layer, CAFrameRateRangeMake(60.0f, 120.0f, 120.0f));
        }
    }
}

static void YTKACECollectionViewCellDidMoveToWindow(UICollectionViewCell *receiver, SEL selector) {
    if (OriginalCollectionViewCellDidMoveToWindow != NULL) {
        ((void (*)(id, SEL))OriginalCollectionViewCellDidMoveToWindow)(receiver, selector);
    }
    if (receiver.window == nil) return;

    if (YTKACEFeatureEnabled(YTKACEForce120HzKey)) {
        if (@available(iOS 15.0, *)) {
            YTKACESetLayerFrameRateRange(receiver.layer, CAFrameRateRangeMake(24.0f, 120.0f, 120.0f));
        }
    }
}

static void YTKACETableViewCellDidMoveToWindow(UITableViewCell *receiver, SEL selector) {
    if (OriginalTableViewCellDidMoveToWindow != NULL) {
        ((void (*)(id, SEL))OriginalTableViewCellDidMoveToWindow)(receiver, selector);
    }
    if (receiver.window == nil) return;

    if (YTKACEFeatureEnabled(YTKACEForce120HzKey)) {
        if (@available(iOS 15.0, *)) {
            YTKACESetLayerFrameRateRange(receiver.layer, CAFrameRateRangeMake(24.0f, 120.0f, 120.0f));
        }
    }
}

static void YTKACEASDisplayViewDidMoveToWindow(UIView *receiver, SEL selector) {
    if (OriginalASDisplayViewDidMoveToWindow != NULL) {
        ((void (*)(id, SEL))OriginalASDisplayViewDidMoveToWindow)(receiver, selector);
    }
    if (receiver.window == nil) return;

    if (YTKACEFeatureEnabled(YTKACEForce120HzKey)) {
        if (@available(iOS 15.0, *)) {
            YTKACESetLayerFrameRateRange(receiver.layer, CAFrameRateRangeMake(24.0f, 120.0f, 120.0f));
        }
    }
}

struct YTKACEASRangeTuningParams {
    CGFloat leadingBufferScreenfuls;
    CGFloat trailingBufferScreenfuls;
};

static IMP OriginalCollectionNodeRangeTuning;
static struct YTKACEASRangeTuningParams YTKACECollectionNodeRangeTuning(id receiver, SEL selector, NSInteger rangeType) {
    if (YTKACEFeatureEnabled(YTKACEForce120HzKey)) {
        struct YTKACEASRangeTuningParams params;
        params.leadingBufferScreenfuls = 2.5;
        params.trailingBufferScreenfuls = 0.5;
        return params;
    }
    if (OriginalCollectionNodeRangeTuning != NULL) {
        return ((struct YTKACEASRangeTuningParams (*)(id, SEL, NSInteger))OriginalCollectionNodeRangeTuning)(receiver, selector, rangeType);
    }
    struct YTKACEASRangeTuningParams def = { 2.0, 0.5 };
    return def;
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

    YTKACEInstallInstanceHook(@"UIScrollView",
                              @"didMoveToWindow",
                              (IMP)YTKACEScrollViewDidMoveToWindow,
                              &OriginalScrollViewDidMoveToWindow);

    YTKACEInstallInstanceHook(@"UIScrollView",
                              @"setContentOffset:",
                              (IMP)YTKACEScrollViewSetContentOffset,
                              &OriginalScrollViewSetContentOffset);

    YTKACEInstallInstanceHook(@"UICollectionViewCell",
                              @"didMoveToWindow",
                              (IMP)YTKACECollectionViewCellDidMoveToWindow,
                              &OriginalCollectionViewCellDidMoveToWindow);

    YTKACEInstallInstanceHook(@"UITableViewCell",
                              @"didMoveToWindow",
                              (IMP)YTKACETableViewCellDidMoveToWindow,
                              &OriginalTableViewCellDidMoveToWindow);

    YTKACEInstallInstanceHook(@"_ASDisplayView",
                              @"didMoveToWindow",
                              (IMP)YTKACEASDisplayViewDidMoveToWindow,
                              &OriginalASDisplayViewDidMoveToWindow);

    for (NSString *nodeClass in @[@"ASCollectionNode", @"ASTableNode"]) {
        YTKACEInstallInstanceHook(nodeClass,
                                  @"rangeTuningParametersForRangeType:",
                                  (IMP)YTKACECollectionNodeRangeTuning,
                                  &OriginalCollectionNodeRangeTuning);
    }

    for (NSString *className in @[@"YTInlinePlaybackController", @"YTElementsInlinePlaybackController"]) {
        YTKACEInstallInstanceHook(className,
                                  @"isPlaybackAllowed",
                                  (IMP)YTKACEInlineIsPlaybackAllowed,
                                  &OriginalInlineIsPlaybackAllowed);
        YTKACEInstallInstanceHook(className,
                                  @"shouldPlay",
                                  (IMP)YTKACEInlineIsPlaybackAllowed,
                                  NULL);
    }
    YTKACEInstallInstanceHook(@"YTMutedPlaybackController",
                              @"isMutedPlaybackAllowed",
                              (IMP)YTKACEMutedIsPlaybackAllowed,
                              &OriginalMutedIsPlaybackAllowed);
}
