#import "DisplayRateHooks.h"
#import "../../YTKACE.h"
#import "../../Runtime/Hooking.h"
#import "../../Runtime/Preferences.h"

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

static IMP OriginalObjectForInfoDictionaryKey;
static IMP OriginalInfoDictionary;
static IMP OriginalDisplayLinkSetPreferredFrameRateRange;
static IMP OriginalDisplayLinkSetPreferredFramesPerSecond;
static IMP OriginalScrollViewDidMoveToWindow;

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
        // Keep 24fps / 30fps cinema playback untouched for native cadence,
        // but lock all UI/gestures/scrolling/animations (>=60fps) to 120Hz!
        if (range.maximum >= 59.0f || range.preferred >= 59.0f) {
            range = CAFrameRateRangeMake(120.0f, 120.0f, 120.0f);
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

static void YTKACEScrollViewDidMoveToWindow(UIScrollView *receiver, SEL selector) {
    if (OriginalScrollViewDidMoveToWindow != NULL) {
        ((void (*)(id, SEL))OriginalScrollViewDidMoveToWindow)(receiver, selector);
    }
    if (!YTKACEFeatureEnabled(YTKACEForce120HzKey) || receiver.window == nil) return;

    if (@available(iOS 15.0, *)) {
        // Lock the scroll view's pan gesture and deceleration rate to full 120Hz range
        receiver.panGestureRecognizer.allowedTouchTypes = @[@(UITouchTypeDirect)];
    }
}

void YTKACEInstallDisplayRateHooks(void) {
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

    YTKACEInstallInstanceHook(@"UIScrollView",
                              @"didMoveToWindow",
                              (IMP)YTKACEScrollViewDidMoveToWindow,
                              &OriginalScrollViewDidMoveToWindow);
}
