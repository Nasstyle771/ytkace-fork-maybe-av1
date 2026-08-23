#import "YTKACE.h"
#import "Features/Appearance/DisplayRateHooks.h"
#import "Features/Downloads/DownloadLog.h"
#import "Features/SponsorBlock/DeArrow.h"
#import "Runtime/Preferences.h"

#import <UIKit/UIKit.h>

#ifndef YTKACE_COMBINED_SABR
#define YTKACE_COMBINED_SABR 0
#endif

NSString * const YTKACEVersion = @"0.9.0";

static void YTKACEInstallModules(void) {
    YTKACEInstallDisplayRateHooks();
    YTKACEInstallSideloadCompatibilityHooks();
    YTKACEInstallCastCompatibilityHooks();
    YTKACEInstallAdsHooks();
    YTKACEInstallPromoHooks();
    YTKACEInstallSponsorBlockHooks();
    YTKACEInstallDeArrow();
    YTKACEInstallOLEDHooks();
    YTKACEInstallStartupHooks();
    YTKACEInstallPremiumLogoHooks();
    YTKACEInstallBackgroundPlaybackHooks();
    YTKACEInstallSpeedHooks();
    YTKACEInstallLoopHooks();
    YTKACEInstallSleepTimerHooks();
    YTKACEInstallPiPHooks();
    YTKACEInstallDownloadHooks();
    YTKACEInstallGlobalDownloadMiniPlayer();
    YTKACEInstallDoubleTapHooks();
    YTKACEInstallPlaybackRecoveryHooks();
    YTKACEInstallProgressBarHooks();
    YTKACEInstallStreamingHooks();
    YTKACEInstallShortsHooks();
    YTKACEInstallTabBarHooks();
    YTKACEInstallNavigationBehaviorHooks();
    YTKACEInstallPlayerGestureHooks();
    YTKACEInstallOverlayVisibilityHooks();
    YTKACEInstallContentVisibilityHooks();
    YTKACEInstallNavigationVisibilityHooks();
    YTKACEInstallMiscellaneousHooks();
    YTKACEInstallCopyCommentHooks();
    YTKACEInstallProfilePictureHooks();
    YTKACEInstallNativeShareHooks();
    YTKACEInstallSettingsEntryHooks();
    YTKACEInstallNativeSettingsHooks();
}

__attribute__((constructor))
static void YTKACEEntryPoint(void) {
    @autoreleasepool {
        YTKACEClearDownloadLog();
        YTKACERegisterDefaults();
        YTKACEScheduleFirstLaunch();
        YTKACEInstallModules();
    }
}
