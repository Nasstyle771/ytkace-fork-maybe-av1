#import "../../YTKACE.h"
#import "../../Runtime/Hooking.h"
#import "../../Runtime/Preferences.h"
#import <AVFoundation/AVFoundation.h>

static IMP OriginalPlayableInBackground;
static IMP OriginalMLPlayableInBackground;
static IMP OriginalBackgroundEnabled;
static IMP OriginalPlayerResponsePlayableInBackground;
static IMP OriginalPlaybackDataPlayableInBackground;
static IMP OriginalHAMBackgroundPlaybackAllowed;
static IMP OriginalHAMItemPlayableInBackground;

static BOOL YTKACEAlwaysTrue(id receiver, SEL selector) {
    if (YTKACEFeatureEnabled(YTKACEBackgroundPlaybackKey)) {
        return YES;
    }
    return NO;
}

static BOOL YTKACEPlayableInBackground(id receiver, SEL selector) {
    if (YTKACEFeatureEnabled(YTKACEBackgroundPlaybackKey)) {
        return YES;
    }
    return OriginalPlayableInBackground != NULL
        ? ((BOOL (*)(id, SEL))OriginalPlayableInBackground)(receiver, selector)
        : NO;
}

static BOOL YTKACEMLPlayableInBackground(id receiver, SEL selector) {
    if (YTKACEFeatureEnabled(YTKACEBackgroundPlaybackKey)) {
        return YES;
    }
    return OriginalMLPlayableInBackground != NULL
        ? ((BOOL (*)(id, SEL))OriginalMLPlayableInBackground)(receiver, selector)
        : NO;
}

static BOOL YTKACEBackgroundEnabled(id receiver, SEL selector) {
    if (YTKACEFeatureEnabled(YTKACEBackgroundPlaybackKey)) {
        return YES;
    }
    return OriginalBackgroundEnabled != NULL
        ? ((BOOL (*)(id, SEL))OriginalBackgroundEnabled)(receiver, selector)
        : NO;
}

static BOOL YTKACEPlayerResponsePlayableInBackground(id receiver, SEL selector) {
    if (YTKACEFeatureEnabled(YTKACEBackgroundPlaybackKey)) {
        return YES;
    }
    return OriginalPlayerResponsePlayableInBackground != NULL
        ? ((BOOL (*)(id, SEL))OriginalPlayerResponsePlayableInBackground)(receiver, selector)
        : NO;
}

static BOOL YTKACEPlaybackDataPlayableInBackground(id receiver, SEL selector) {
    if (YTKACEFeatureEnabled(YTKACEBackgroundPlaybackKey)) {
        return YES;
    }
    return OriginalPlaybackDataPlayableInBackground != NULL
        ? ((BOOL (*)(id, SEL))OriginalPlaybackDataPlayableInBackground)(receiver, selector)
        : NO;
}

static BOOL YTKACEHAMBackgroundPlaybackAllowed(id receiver, SEL selector) {
    if (YTKACEFeatureEnabled(YTKACEBackgroundPlaybackKey)) {
        return YES;
    }
    return OriginalHAMBackgroundPlaybackAllowed != NULL
        ? ((BOOL (*)(id, SEL))OriginalHAMBackgroundPlaybackAllowed)(receiver, selector)
        : NO;
}

static BOOL YTKACEHAMItemPlayableInBackground(id receiver, SEL selector) {
    if (YTKACEFeatureEnabled(YTKACEBackgroundPlaybackKey)) {
        return YES;
    }
    return OriginalHAMItemPlayableInBackground != NULL
        ? ((BOOL (*)(id, SEL))OriginalHAMItemPlayableInBackground)(receiver, selector)
        : NO;
}

void YTKACEInstallBackgroundPlaybackHooks(void) {
    YTKACEInstallInstanceHook(@"YTIPlayabilityStatus",
                              @"isPlayableInBackground",
                              (IMP)YTKACEPlayableInBackground,
                              &OriginalPlayableInBackground);
    YTKACEInstallInstanceHook(@"MLVideo",
                              @"playableInBackground",
                              (IMP)YTKACEMLPlayableInBackground,
                              &OriginalMLPlayableInBackground);
    if (!YTKACEInstallInstanceHook(
            @"YTIBackgroundOfflineSettingCategoryEntryRenderer",
            @"isBackgroundEnabled",
            (IMP)YTKACEBackgroundEnabled,
            &OriginalBackgroundEnabled)) {
        YTKACEAddInstanceMethod(
            @"YTIBackgroundOfflineSettingCategoryEntryRenderer",
            @"isBackgroundEnabled",
            (IMP)YTKACEBackgroundEnabled,
            "B@:"
        );
    }

    YTKACEInstallInstanceHook(@"YTIPlayerResponse",
                              @"isPlayableInBackground",
                              (IMP)YTKACEPlayerResponsePlayableInBackground,
                              &OriginalPlayerResponsePlayableInBackground);
    YTKACEInstallInstanceHook(@"YTPlaybackData",
                              @"isPlayableInBackground",
                              (IMP)YTKACEPlaybackDataPlayableInBackground,
                              &OriginalPlaybackDataPlayableInBackground);
    YTKACEInstallInstanceHook(@"HAMPlayerConfiguration",
                              @"isBackgroundPlaybackAllowed",
                              (IMP)YTKACEHAMBackgroundPlaybackAllowed,
                              &OriginalHAMBackgroundPlaybackAllowed);
    YTKACEInstallInstanceHook(@"MLHAMPlayerItem",
                              @"playableInBackground",
                              (IMP)YTKACEHAMItemPlayableInBackground,
                              &OriginalHAMItemPlayableInBackground);

    for (NSString *className in @[@"YTPlayerViewController", @"YTLocalPlaybackController", @"YTBackgroundPlaybackController"]) {
        for (NSString *selectorName in @[@"isBackgroundPlaybackAllowed", @"backgroundAudioAllowed", @"canPlayInBackground", @"shouldAllowBackgroundPlayback"]) {
            YTKACEInstallInstanceHook(className, selectorName, (IMP)YTKACEAlwaysTrue, NULL);
        }
    }
}
