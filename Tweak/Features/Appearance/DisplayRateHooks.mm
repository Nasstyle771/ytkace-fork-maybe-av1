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

    YTKACEInstallInstanceHook(@"CAAnimation",
                              @"setPreferredFrameRateRange:",
                              (IMP)YTKACEAnimationSetPreferredFrameRateRange,
                              &OriginalAnimationSetPreferredFrameRateRange);
}
