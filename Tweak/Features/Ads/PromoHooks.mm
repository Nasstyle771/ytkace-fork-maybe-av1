#import "../../YTKACE.h"
#import "../../Runtime/Hooking.h"
#import "../../Runtime/Preferences.h"

#import <Foundation/Foundation.h>
#import <stdatomic.h>

static IMP OriginalMealbarPromo;
static IMP OriginalCommerceMealbarPromo;
static IMP OriginalPromosheet;
static IMP OriginalUpgradeDialog;
static IMP OriginalOldUpgradeDialog;
static IMP OriginalShouldShowUpgrade;
static IMP OriginalShouldShowUpgradeDialog;
static IMP OriginalYouTherePrompt;
static IMP OriginalThrottleInterstitial;

static atomic_int sHidePromosCached = -1;

static inline BOOL YTKACEHidePromos(void) {
    int cached = atomic_load(&sHidePromosCached);
    if (cached >= 0) return cached != 0;
    BOOL enabled = YTKACEFeatureEnabled(@"YTKACE.Preference.Ads.PremiumPromosHidden");
    atomic_store(&sHidePromosCached, enabled ? 1 : 0);
    return enabled;
}

static void YTKACEMealbarPromo(id receiver, SEL selector, id event) {
    if (!YTKACEHidePromos() && OriginalMealbarPromo != NULL) {
        ((void (*)(id, SEL, id))OriginalMealbarPromo)(receiver, selector, event);
    }
}

static void YTKACECommerceMealbarPromo(id receiver, SEL selector, id event) {
    if (!YTKACEHidePromos() && OriginalCommerceMealbarPromo != NULL) {
        ((void (*)(id, SEL, id))OriginalCommerceMealbarPromo)(receiver, selector, event);
    }
}

static void YTKACEPromosheet(id receiver, SEL selector, id event) {
    if (!YTKACEHidePromos() && OriginalPromosheet != NULL) {
        ((void (*)(id, SEL, id))OriginalPromosheet)(receiver, selector, event);
    }
}

static void YTKACEUpgradeDialog(id receiver, SEL selector) {
    if (!YTKACEHidePromos() && OriginalUpgradeDialog != NULL) {
        ((void (*)(id, SEL))OriginalUpgradeDialog)(receiver, selector);
    }
}

static void YTKACEOldUpgradeDialog(id receiver, SEL selector) {
    if (!YTKACEHidePromos() && OriginalOldUpgradeDialog != NULL) {
        ((void (*)(id, SEL))OriginalOldUpgradeDialog)(receiver, selector);
    }
}

static BOOL YTKACEShouldShowUpgrade(id receiver, SEL selector) {
    return YTKACEHidePromos() ? NO :
        (OriginalShouldShowUpgrade != NULL &&
         ((BOOL (*)(id, SEL))OriginalShouldShowUpgrade)(receiver, selector));
}

static BOOL YTKACEShouldShowUpgradeDialog(id receiver, SEL selector) {
    return YTKACEHidePromos() ? NO :
        (OriginalShouldShowUpgradeDialog != NULL &&
         ((BOOL (*)(id, SEL))OriginalShouldShowUpgradeDialog)(receiver, selector));
}

static BOOL YTKACEShouldShowYouThere(id receiver, SEL selector) {
    return YTKACEHidePromos() ? NO :
        (OriginalYouTherePrompt != NULL &&
         ((BOOL (*)(id, SEL))OriginalYouTherePrompt)(receiver, selector));
}

static BOOL YTKACEShouldThrottleInterstitial(id receiver, SEL selector) {
    return YTKACEHidePromos() ? YES :
        (OriginalThrottleInterstitial != NULL &&
         ((BOOL (*)(id, SEL))OriginalThrottleInterstitial)(receiver, selector));
}

static BOOL YTKACENeverShow(id receiver, SEL selector) {
    (void)receiver;
    (void)selector;
    return YTKACEHidePromos() ? NO : YES;
}

void YTKACEInstallPromoHooks(void) {
    [NSNotificationCenter.defaultCenter
        addObserverForName:YTKACEPreferencesDidChangeNotification
                    object:nil
                     queue:nil
                usingBlock:^(__unused NSNotification *note) {
        atomic_store(&sHidePromosCached, -1);
    }];

    YTKACEInstallInstanceHook(@"YTMealbarPromoController",
                              @"showMealbarPromoWithEvent:",
                              (IMP)YTKACEMealbarPromo,
                              &OriginalMealbarPromo);
    YTKACEInstallInstanceHook(@"YTCommerceMealbarPromoController",
                              @"showMealbarPromoWithEvent:",
                              (IMP)YTKACECommerceMealbarPromo,
                              &OriginalCommerceMealbarPromo);
    YTKACEInstallInstanceHook(@"YTPromosheetController",
                              @"presentPromosheetWithEvent:",
                              (IMP)YTKACEPromosheet,
                              &OriginalPromosheet);
    YTKACEInstallInstanceHook(@"YTUpgradeController", @"showUpgradeDialog",
                              (IMP)YTKACEUpgradeDialog,
                              &OriginalUpgradeDialog);
    YTKACEInstallInstanceHook(@"YTUpgradeController", @"showOldUpgradeDialog",
                              (IMP)YTKACEOldUpgradeDialog,
                              &OriginalOldUpgradeDialog);
    YTKACEInstallInstanceHook(@"YTGlobalConfig", @"shouldShowUpgrade",
                              (IMP)YTKACEShouldShowUpgrade,
                              &OriginalShouldShowUpgrade);
    YTKACEInstallInstanceHook(@"YTGlobalConfig", @"shouldShowUpgradeDialog",
                              (IMP)YTKACEShouldShowUpgradeDialog,
                              &OriginalShouldShowUpgradeDialog);
    YTKACEInstallInstanceHook(@"YTYouThereControllerImpl",
                              @"shouldShowYouTherePrompt",
                              (IMP)YTKACEShouldShowYouThere,
                              &OriginalYouTherePrompt);
    YTKACEInstallInstanceHook(@"YTIShowFullscreenInterstitialCommand",
                              @"shouldThrottleInterstitial",
                              (IMP)YTKACEShouldThrottleInterstitial,
                              &OriginalThrottleInterstitial);

    for (NSString *className in @[@"YTPremiumUpsellOverlayView", @"YTPremiumUpsellView"]) {
        for (NSString *selectorName in @[@"shouldShowUpsell", @"isUpsellVisible"]) {
            YTKACEInstallInstanceHook(className, selectorName, (IMP)YTKACENeverShow, NULL);
        }
    }
}
