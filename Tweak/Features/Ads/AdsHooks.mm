#import "../../YTKACE.h"
#import "../../Runtime/Hooking.h"
#import "../../Runtime/Preferences.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <os/lock.h>

static IMP OriginalShouldBlockUpgradeDialog;
static IMP OriginalAdShieldSignals;
static IMP OriginalAdShieldSignalsWithoutIDFA;
static IMP OriginalDataSignals;
static IMP OriginalDataSignalsWithoutIDFA;
static IMP OriginalAdsDecorateContext;
static IMP OriginalAccountAdsDecorateContext;
static IMP OriginalPlayerAdsArray;
static IMP OriginalAdSlotsArray;
static IMP OriginalAdPlacementsArray;
static IMP OriginalAdBreakParams;
static IMP OriginalAdNextParams;
static IMP OriginalAdParams;
static IMP OriginalEnableSkippableAd;
static IMP OriginalMDXSessionImplAdPlaying;
static IMP OriginalMDXSessionAdPlaying;
static IMP OriginalIsPlayingAd;
static IMP OriginalIsPlayingAdSurvey;
static IMP OriginalIsPlayingAdIntro;
static IMP OriginalCreateAdsPlaybackCoordinator;
static IMP OriginalReelContentModel;
static IMP OriginalInfiniteReelContentModel;
static IMP OriginalReelShouldDisplay;
static IMP OriginalCompanionAd;
static IMP OriginalHasCompanionAdRenderer;
static IMP OriginalHasAppPromoCompanionAdRenderer;
static IMP OriginalHasShoppingCompanionAdRenderer;
static IMP OriginalElementContentsArray;
static IMP OriginalItemSectionContentsArray;
static const void *YTKACEAdMatchAssociation = &YTKACEAdMatchAssociation;
static const void *YTKACEAdEmptyAssociation = &YTKACEAdEmptyAssociation;

static os_unfair_lock YTKACEAdClassLock = OS_UNFAIR_LOCK_INIT;
static CFMutableDictionaryRef YTKACEAdClassCache = NULL;

static id YTKACECallObjectGetter(IMP implementation, id receiver, SEL selector) {
    return implementation == NULL
        ? nil
        : ((id (*)(id, SEL))implementation)(receiver, selector);
}

static BOOL YTKACECallBooleanGetter(IMP implementation, id receiver, SEL selector) {
    return implementation != NULL &&
        ((BOOL (*)(id, SEL))implementation)(receiver, selector);
}

static BOOL YTKACEShouldBlockUpgradeDialog(id receiver, SEL selector) {
    return YTKACEFeatureEnabled(YTKACENoAdsKey)
        ? YES
        : YTKACECallBooleanGetter(OriginalShouldBlockUpgradeDialog, receiver, selector);
}

static id YTKACEEmptyDictionary(IMP original, id receiver, SEL selector) {
    return YTKACEFeatureEnabled(YTKACENoAdsKey)
        ? @{}
        : YTKACECallObjectGetter(original, receiver, selector);
}

static id YTKACEAdShieldSignals(id receiver, SEL selector) {
    return YTKACEEmptyDictionary(OriginalAdShieldSignals, receiver, selector);
}

static id YTKACEAdShieldSignalsWithoutIDFA(id receiver, SEL selector) {
    return YTKACEEmptyDictionary(OriginalAdShieldSignalsWithoutIDFA, receiver, selector);
}

static id YTKACEDataSignals(id receiver, SEL selector) {
    return YTKACEEmptyDictionary(OriginalDataSignals, receiver, selector);
}

static id YTKACEDataSignalsWithoutIDFA(id receiver, SEL selector) {
    return YTKACEEmptyDictionary(OriginalDataSignalsWithoutIDFA, receiver, selector);
}

static void YTKACEAdsDecorateContext(id receiver, SEL selector, id context) {
    if (!YTKACEFeatureEnabled(YTKACENoAdsKey) && OriginalAdsDecorateContext != NULL) {
        ((void (*)(id, SEL, id))OriginalAdsDecorateContext)(receiver, selector, context);
    }
}

static void YTKACEAccountAdsDecorateContext(id receiver, SEL selector, id context) {
    if (!YTKACEFeatureEnabled(YTKACENoAdsKey) &&
        OriginalAccountAdsDecorateContext != NULL) {
        ((void (*)(id, SEL, id))OriginalAccountAdsDecorateContext)(
            receiver,
            selector,
            context
        );
    }
}

static id YTKACEPlayerAdsArray(id receiver, SEL selector) {
    return YTKACEFeatureEnabled(YTKACENoAdsKey)
        ? [NSMutableArray array]
        : YTKACECallObjectGetter(OriginalPlayerAdsArray, receiver, selector);
}

static id YTKACEAdSlotsArray(id receiver, SEL selector) {
    return YTKACEFeatureEnabled(YTKACENoAdsKey)
        ? [NSMutableArray array]
        : YTKACECallObjectGetter(OriginalAdSlotsArray, receiver, selector);
}

static id YTKACEAdPlacementsArray(id receiver, SEL selector) {
    return YTKACEFeatureEnabled(YTKACENoAdsKey)
        ? [NSMutableArray array]
        : YTKACECallObjectGetter(OriginalAdPlacementsArray, receiver, selector);
}

static id YTKACENilParameter(IMP original, id receiver, SEL selector) {
    return YTKACEFeatureEnabled(YTKACENoAdsKey)
        ? nil
        : YTKACECallObjectGetter(original, receiver, selector);
}

static id YTKACEAdBreakParams(id receiver, SEL selector) {
    return YTKACENilParameter(OriginalAdBreakParams, receiver, selector);
}

static id YTKACEAdNextParams(id receiver, SEL selector) {
    return YTKACENilParameter(OriginalAdNextParams, receiver, selector);
}

static id YTKACEAdParams(id receiver, SEL selector) {
    return YTKACENilParameter(OriginalAdParams, receiver, selector);
}

static BOOL YTKACEEnableSkippableAd(id receiver, SEL selector) {
    return YTKACEFeatureEnabled(YTKACENoAdsKey)
        ? YES
        : YTKACECallBooleanGetter(OriginalEnableSkippableAd, receiver, selector);
}

static void YTKACEMDXSessionImplAdPlaying(id receiver,
                                          SEL selector,
                                          uintptr_t value) {
    if (!YTKACEFeatureEnabled(YTKACENoAdsKey) &&
        OriginalMDXSessionImplAdPlaying != NULL) {
        ((void (*)(id, SEL, uintptr_t))OriginalMDXSessionImplAdPlaying)(
            receiver,
            selector,
            value
        );
    }
}

static void YTKACEMDXSessionAdPlaying(id receiver,
                                      SEL selector,
                                      uintptr_t value) {
    if (!YTKACEFeatureEnabled(YTKACENoAdsKey) && OriginalMDXSessionAdPlaying != NULL) {
        ((void (*)(id, SEL, uintptr_t))OriginalMDXSessionAdPlaying)(
            receiver,
            selector,
            value
        );
    }
}

static BOOL YTKACENotPlayingAd(IMP original, id receiver, SEL selector) {
    return YTKACEFeatureEnabled(YTKACENoAdsKey)
        ? NO
        : YTKACECallBooleanGetter(original, receiver, selector);
}

static BOOL YTKACEIsPlayingAd(id receiver, SEL selector) {
    return YTKACENotPlayingAd(OriginalIsPlayingAd, receiver, selector);
}

static BOOL YTKACEIsPlayingAdSurvey(id receiver, SEL selector) {
    return YTKACENotPlayingAd(OriginalIsPlayingAdSurvey, receiver, selector);
}

static BOOL YTKACEIsPlayingAdIntro(id receiver, SEL selector) {
    return YTKACENotPlayingAd(OriginalIsPlayingAdIntro, receiver, selector);
}

static id YTKACENoAdsPlaybackCoordinator(id receiver, SEL selector) {
    id coordinator = YTKACECallObjectGetter(
        OriginalCreateAdsPlaybackCoordinator,
        receiver,
        selector
    );
    return YTKACEFeatureEnabled(YTKACENoAdsKey) ? nil : coordinator;
}

static id YTKACEFilterReelModel(IMP original,
                                id receiver,
                                SEL selector,
                                id entry) {
    if (original == NULL) {
        return nil;
    }
    id model = ((id (*)(id, SEL, id))original)(receiver, selector, entry);
    if (!YTKACEFeatureEnabled(YTKACENoAdsKey) || model == nil) {
        return model;
    }
    SEL videoTypeSelector = NSSelectorFromString(@"videoType");
    if (![model respondsToSelector:videoTypeSelector]) {
        return model;
    }
    NSInteger videoType = ((NSInteger (*)(id, SEL))objc_msgSend)(
        model,
        videoTypeSelector
    );
    return videoType == 3 ? nil : model;
}

static id YTKACEReelContentModel(id receiver, SEL selector, id entry) {
    return YTKACEFilterReelModel(
        OriginalReelContentModel,
        receiver,
        selector,
        entry
    );
}

static id YTKACEInfiniteReelContentModel(id receiver, SEL selector, id entry) {
    return YTKACEFilterReelModel(
        OriginalInfiniteReelContentModel,
        receiver,
        selector,
        entry
    );
}

static id YTKACEObjectValue(id object, NSString *selectorName) {
    if (object == nil) return nil;
    SEL selector = NSSelectorFromString(selectorName);
    if (![object respondsToSelector:selector]) return nil;
    @try {
        return ((id (*)(id, SEL))objc_msgSend)(object, selector);
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static BOOL YTKACEObjectBool(id object, NSString *selectorName) {
    if (object == nil) return NO;
    SEL selector = NSSelectorFromString(selectorName);
    if (![object respondsToSelector:selector]) return NO;
    @try {
        return ((BOOL (*)(id, SEL))objc_msgSend)(object, selector);
    } @catch (__unused NSException *exception) {
        return NO;
    }
}

static BOOL YTKACEReelObjectLooksLikeAd(id object, NSUInteger depth) {
    if (object == nil || depth > 3) return NO;

    NSString *className = NSStringFromClass([object class]).lowercaseString;
    if ([className containsString:@"nonvideoad"] ||
        [className containsString:@"reelad"] ||
        [className containsString:@"adselection"] ||
        [className containsString:@"miniappad"]) {
        return YES;
    }

    for (NSString *selectorName in @[
        @"isAd", @"isAdVideo", @"isVideoAd", @"hasAdLoggingData"
    ]) {
        if (YTKACEObjectBool(object, selectorName)) return YES;
    }

    SEL videoTypeSelector = NSSelectorFromString(@"videoType");
    if ([object respondsToSelector:videoTypeSelector]) {
        NSInteger videoType = ((NSInteger (*)(id, SEL))objc_msgSend)(
            object,
            videoTypeSelector
        );
        if (videoType == 3) return YES;
    }

    for (NSString *selectorName in @[
        @"adLoggingData",
        @"adSlotRenderer",
        @"reelNonVideoAdRenderer",
        @"nonVideoAdRenderer",
        @"sequenceItemAdSelectionRenderer"
    ]) {
        if (YTKACEObjectValue(object, selectorName) != nil) return YES;
    }

    for (NSString *selectorName in @[
        @"reelModel", @"command", @"watchModel", @"parentWatchModel"
    ]) {
        id child = YTKACEObjectValue(object, selectorName);
        if (child != object && YTKACEReelObjectLooksLikeAd(child, depth + 1)) {
            return YES;
        }
    }
    return NO;
}

static BOOL YTKACEReelShouldDisplay(id receiver, SEL selector) {
    BOOL shouldDisplay = OriginalReelShouldDisplay == NULL ||
        ((BOOL (*)(id, SEL))OriginalReelShouldDisplay)(receiver, selector);
    if (!shouldDisplay || !YTKACEFeatureEnabled(YTKACENoAdsKey)) {
        return shouldDisplay;
    }
    if (YTKACEObjectValue(receiver, @"nonVideoContentModel") != nil) {
        return NO;
    }
    return !YTKACEReelObjectLooksLikeAd(receiver, 0);
}

static inline BOOL YTKACEIsAdLayoutIdentifier(NSString *identifier) {
    if (![identifier isKindOfClass:NSString.class] || identifier.length < 7) return NO;
    NSString *normalized = [[identifier lowercaseString]
        stringByReplacingOccurrencesOfString:@"." withString:@"_"];
    normalized = [normalized stringByReplacingOccurrencesOfString:@"-"
                                                        withString:@"_"];
    return [normalized hasPrefix:@"eml_ad_"];
}

static BOOL YTKACEClassInherentlyAd(Class cls) {
    const char *name = class_getName(cls);
    if (name == NULL) return NO;
    char lower[128] = {0};
    size_t len = strlen(name);
    if (len >= sizeof(lower)) len = sizeof(lower) - 1;
    for (size_t i = 0; i < len; i++) {
        lower[i] = (char)tolower((unsigned char)name[i]);
    }
    lower[len] = '\0';

    if (strstr(lower, "adrenderer") != NULL ||
        (strstr(lower, "promoted") != NULL && strstr(lower, "renderer") != NULL) ||
        strstr(lower, "promorenderer") != NULL ||
        strstr(lower, "adslotrenderer") != NULL ||
        strstr(lower, "companionadrenderer") != NULL ||
        strstr(lower, "shoppingadinfocardcontentrenderer") != NULL ||
        strstr(lower, "infeedad") != NULL ||
        strstr(lower, "displayad") != NULL) {
        return YES;
    }
    return NO;
}

static BOOL YTKACEObjectLooksLikeAd(id object) {
    if (object == nil) return NO;
    if ([objc_getAssociatedObject(object, YTKACEAdMatchAssociation) boolValue]) {
        return YES;
    }

    Class cls = object_getClass(object);
    if (cls == Nil) return NO;

    os_unfair_lock_lock(&YTKACEAdClassLock);
    if (YTKACEAdClassCache == NULL) {
        YTKACEAdClassCache = CFDictionaryCreateMutable(
            kCFAllocatorDefault, 0, NULL, NULL);
    }
    uintptr_t cached = (uintptr_t)CFDictionaryGetValue(YTKACEAdClassCache, (__bridge const void *)cls);
    os_unfair_lock_unlock(&YTKACEAdClassLock);

    if (cached == 1) { // Known Ad Class
        return YES;
    }
    if (cached == 2) { // Known Non-Ad Class, check instance-level properties only
        // Fall through to fast instance check
    } else {
        if (YTKACEClassInherentlyAd(cls)) {
            os_unfair_lock_lock(&YTKACEAdClassLock);
            CFDictionarySetValue(YTKACEAdClassCache, (__bridge const void *)cls, (const void *)1);
            os_unfair_lock_unlock(&YTKACEAdClassLock);
            objc_setAssociatedObject(object, YTKACEAdMatchAssociation, @YES,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            return YES;
        } else {
            os_unfair_lock_lock(&YTKACEAdClassLock);
            CFDictionarySetValue(YTKACEAdClassCache, (__bridge const void *)cls, (const void *)2);
            os_unfair_lock_unlock(&YTKACEAdClassLock);
        }
    }

    BOOL matched = NO;
    static SEL adSelectors[] = {
        @selector(isAdRenderer), @selector(isAd),
        @selector(hasAdLoggingData), @selector(hasAdBadgeRenderer),
        @selector(hasNativeAdBadgeRenderer), @selector(hasSimpleAdBadgeRenderer),
        @selector(hasAdSlotRenderer), @selector(hasCompanionAdRenderer),
        @selector(hasCompactCompanionAdRenderer), @selector(hasMultiItemCompanionAdRenderer),
        @selector(hasAppPromoCompanionAdRenderer), @selector(hasShoppingCompanionAdRenderer),
        @selector(hasSuggestedVideosCompanionAdRenderer), @selector(hasCompactPromotedBannerRenderer),
        @selector(hasCompactPromotedItemRenderer), @selector(hasCompactPromotedVideoRenderer),
        @selector(hasGridPromotedBannerRenderer), @selector(hasGridPromotedVideoRenderer),
        @selector(hasPromoted15ClickPtTextCtdWatchRenderer), @selector(hasPromoted15ClickPtTextWatchRenderer),
        @selector(hasPromoted15ClickTextCtdWatchRenderer), @selector(hasPromoted15ClickTextWatchRenderer),
        @selector(hasPromotedAppInstallRenderer), @selector(hasPromotedDiscoveryAppPromoCompactFormRenderer),
        @selector(hasPromotedSparklesTextCtdHomeCompactFormRenderer), @selector(hasPromotedSparklesTextCtdHomeRenderer),
        @selector(hasPromotedSparklesTextCtdWatch15ClickRenderer), @selector(hasPromotedSparklesTextCtdWatchGridFormRenderer),
        @selector(hasPromotedSparklesTextCtdWatchWideFormRenderer), @selector(hasPromotedSparklesTextHomeRenderer),
        @selector(hasPromotedSparklesTextProductHomeRenderer), @selector(hasPromotedSparklesTextProductWatchRenderer),
        @selector(hasPromotedSparklesTextSearchRenderer), @selector(hasPromotedSparklesTextWatch15ClickRenderer),
        @selector(hasPromotedSparklesTextWatchGridFormRenderer), @selector(hasPromotedSparklesTextWatchWideFormRenderer),
        @selector(hasPromotedTextBannerRenderer), @selector(hasPromotedVideoInlineMutedRenderer),
        @selector(hasPromotedVideoRenderer), @selector(hasShoppingAdInfoCardContentRenderer)
    };

    for (size_t i = 0; i < sizeof(adSelectors) / sizeof(adSelectors[0]); i++) {
        SEL sel = adSelectors[i];
        if ([object respondsToSelector:sel]) {
            @try {
                if (((BOOL (*)(id, SEL))objc_msgSend)(object, sel)) {
                    matched = YES;
                    break;
                }
            } @catch (__unused NSException *e) {}
        }
    }

    if (!matched && YTKACEObjectValue(object, @"adLoggingData") != nil) {
        matched = YES;
    }
    if (!matched) {
        for (NSString *selectorName in @[
            @"adBadgeRenderer", @"nativeAdBadgeRenderer", @"simpleAdBadgeRenderer"
        ]) {
            if (YTKACEObjectValue(object, selectorName) != nil) {
                matched = YES;
                break;
            }
        }
    }
    if (!matched) {
        for (NSString *selectorName in @[
            @"identifier", @"layoutIdentifier", @"elementIdentifier",
            @"accessibilityIdentifier", @"templateIdentifier"
        ]) {
            id value = YTKACEObjectValue(object, selectorName);
            if ([value isKindOfClass:NSString.class] &&
                YTKACEIsAdLayoutIdentifier(value)) {
                matched = YES;
                break;
            }
        }
    }
    if (!matched) {
        id options = YTKACEObjectValue(object, @"compatibilityOptions");
        SEL loggingSelector = NSSelectorFromString(@"hasAdLoggingData");
        matched = [options respondsToSelector:loggingSelector] &&
            ((BOOL (*)(id, SEL))objc_msgSend)(options, loggingSelector);
    }
    if (matched) {
        objc_setAssociatedObject(object, YTKACEAdMatchAssociation, @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return matched;
}

static const void *YTKACEAdCellAssociation = &YTKACEAdCellAssociation;

void YTKACECollapseHostCell(UIView *view) {
    if (view == nil) return;
    view.hidden = YES;
    view.userInteractionEnabled = NO;
}

void YTKACEHandleAdDisplayView(UIView *view) {
    if (!YTKACEFeatureEnabled(YTKACENoAdsKey) || view == nil) return;
    if (!YTKACEIsAdLayoutIdentifier(view.accessibilityIdentifier)) return;
    view.hidden = YES;
    view.userInteractionEnabled = NO;
}

static id YTKACEElementRenderer(id object) {
    SEL selector = NSSelectorFromString(@"elementRenderer");
    return [object respondsToSelector:selector]
        ? ((id (*)(id, SEL))objc_msgSend)(object, selector)
        : nil;
}

static NSArray *YTKACEFilterAdContents(NSArray *contents, id owner) {
    if (!YTKACEFeatureEnabled(YTKACENoAdsKey) ||
        ![contents isKindOfClass:NSArray.class] || contents.count == 0) {
        return contents;
    }

    // Fast check if any element is an ad before allocating array
    BOOL hasAd = NO;
    for (id content in contents) {
        if (YTKACEObjectLooksLikeAd(content) ||
            YTKACEObjectLooksLikeAd(YTKACEElementRenderer(content))) {
            hasAd = YES;
            break;
        }
    }
    if (!hasAd) return contents;

    NSMutableArray *filtered = [NSMutableArray arrayWithCapacity:contents.count];
    for (id content in contents) {
        id renderer = YTKACEElementRenderer(content);
        BOOL contentAd = YTKACEObjectLooksLikeAd(content);
        BOOL rendererAd = YTKACEObjectLooksLikeAd(renderer);
        if (!contentAd && !rendererAd) {
            [filtered addObject:content];
        }
    }
    if (filtered.count == 0 && owner != nil) {
        objc_setAssociatedObject(owner, YTKACEAdEmptyAssociation, @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return filtered;
}

static NSArray *YTKACEElementContentsArray(id receiver, SEL selector) {
    NSArray *contents = OriginalElementContentsArray == NULL ? nil :
        ((id (*)(id, SEL))OriginalElementContentsArray)(receiver, selector);
    return YTKACEFilterAdContents(contents, receiver);
}

static NSArray *YTKACEItemSectionContentsArray(id receiver, SEL selector) {
    NSArray *contents = OriginalItemSectionContentsArray == NULL ? nil :
        ((id (*)(id, SEL))OriginalItemSectionContentsArray)(receiver, selector);
    return YTKACEFilterAdContents(contents, receiver);
}

NSArray *YTKACEFilterAdSections(NSArray *sections) {
    if (!YTKACEFeatureEnabled(YTKACENoAdsKey) ||
        ![sections isKindOfClass:NSArray.class] || sections.count == 0) {
        return sections;
    }

    BOOL needsFilter = NO;
    for (id section in sections) {
        if (YTKACEObjectLooksLikeAd(section) ||
            YTKACEObjectLooksLikeAd(YTKACEElementRenderer(section)) ||
            [objc_getAssociatedObject(section, YTKACEAdEmptyAssociation) boolValue]) {
            needsFilter = YES;
            break;
        }
    }
    if (!needsFilter) return sections;

    NSMutableArray *filtered = [NSMutableArray arrayWithCapacity:sections.count];
    for (id section in sections) {
        if (YTKACEObjectLooksLikeAd(section) ||
            YTKACEObjectLooksLikeAd(YTKACEElementRenderer(section))) {
            continue;
        }
        NSArray *contents = YTKACEObjectValue(section, @"contentsArray");
        if ([objc_getAssociatedObject(section, YTKACEAdEmptyAssociation) boolValue] ||
            ([contents isKindOfClass:NSArray.class] && contents.count != 0 &&
             YTKACEFilterAdContents(contents, section).count == 0)) {
            continue;
        }
        [filtered addObject:section];
    }
    return filtered;
}

static id YTKACENoCompanionAd(id receiver, SEL selector) {
    return YTKACEFeatureEnabled(YTKACENoAdsKey)
        ? nil
        : YTKACECallObjectGetter(OriginalCompanionAd, receiver, selector);
}

static BOOL YTKACENoCompanionFlag(IMP original, id receiver, SEL selector) {
    return YTKACEFeatureEnabled(YTKACENoAdsKey)
        ? NO
        : YTKACECallBooleanGetter(original, receiver, selector);
}

static BOOL YTKACEHasCompanionAdRenderer(id receiver, SEL selector) {
    return YTKACENoCompanionFlag(
        OriginalHasCompanionAdRenderer,
        receiver,
        selector
    );
}

static BOOL YTKACEHasAppPromoCompanionAdRenderer(id receiver, SEL selector) {
    return YTKACENoCompanionFlag(
        OriginalHasAppPromoCompanionAdRenderer,
        receiver,
        selector
    );
}

static BOOL YTKACEHasShoppingCompanionAdRenderer(id receiver, SEL selector) {
    return YTKACENoCompanionFlag(
        OriginalHasShoppingCompanionAdRenderer,
        receiver,
        selector
    );
}

static void YTKACEInstallObjectHookOrMethod(NSString *className,
                                            NSString *selectorName,
                                            IMP replacement,
                                            IMP *originalStorage) {
    if (!YTKACEInstallInstanceHook(
            className,
            selectorName,
            replacement,
            originalStorage
        )) {
        YTKACEAddInstanceMethod(className, selectorName, replacement, "@@:");
    }
}

static void YTKACEInstallBooleanHookOrMethod(NSString *className,
                                             NSString *selectorName,
                                             IMP replacement,
                                             IMP *originalStorage) {
    if (!YTKACEInstallInstanceHook(
            className,
            selectorName,
            replacement,
            originalStorage
        )) {
        YTKACEAddInstanceMethod(className, selectorName, replacement, "B@:");
    }
}

void YTKACEInstallAdsHooks(void) {
    YTKACEInstallInstanceHook(@"YTGlobalConfig",
                              @"shouldBlockUpgradeDialog",
                              (IMP)YTKACEShouldBlockUpgradeDialog,
                              &OriginalShouldBlockUpgradeDialog);
    YTKACEInstallClassHook(@"YTAdShieldUtils",
                           @"spamSignalsDictionary",
                           (IMP)YTKACEAdShieldSignals,
                           &OriginalAdShieldSignals);
    YTKACEInstallClassHook(@"YTAdShieldUtils",
                           @"spamSignalsDictionaryWithoutIDFA",
                           (IMP)YTKACEAdShieldSignalsWithoutIDFA,
                           &OriginalAdShieldSignalsWithoutIDFA);
    YTKACEInstallClassHook(@"YTDataUtils",
                           @"spamSignalsDictionary",
                           (IMP)YTKACEDataSignals,
                           &OriginalDataSignals);
    YTKACEInstallClassHook(@"YTDataUtils",
                           @"spamSignalsDictionaryWithoutIDFA",
                           (IMP)YTKACEDataSignalsWithoutIDFA,
                           &OriginalDataSignalsWithoutIDFA);
    YTKACEInstallInstanceHook(@"YTAdsInnerTubeContextDecorator",
                              @"decorateContext:",
                              (IMP)YTKACEAdsDecorateContext,
                              &OriginalAdsDecorateContext);
    YTKACEInstallInstanceHook(@"YTAccountScopedAdsInnerTubeContextDecorator",
                              @"decorateContext:",
                              (IMP)YTKACEAccountAdsDecorateContext,
                              &OriginalAccountAdsDecorateContext);

    YTKACEInstallObjectHookOrMethod(@"YTIPlayerResponse",
                                    @"playerAdsArray",
                                    (IMP)YTKACEPlayerAdsArray,
                                    &OriginalPlayerAdsArray);
    YTKACEInstallObjectHookOrMethod(@"YTIPlayerResponse",
                                    @"adSlotsArray",
                                    (IMP)YTKACEAdSlotsArray,
                                    &OriginalAdSlotsArray);
    YTKACEInstallObjectHookOrMethod(@"YTIPlayerResponse",
                                    @"adPlacementsArray",
                                    (IMP)YTKACEAdPlacementsArray,
                                    &OriginalAdPlacementsArray);
    YTKACEInstallInstanceHook(@"YTIPlayerResponse",
                              @"adBreakParams",
                              (IMP)YTKACEAdBreakParams,
                              &OriginalAdBreakParams);
    YTKACEInstallInstanceHook(@"YTIPlayerResponse",
                              @"adNextParams",
                              (IMP)YTKACEAdNextParams,
                              &OriginalAdNextParams);
    YTKACEInstallInstanceHook(@"YTIPlayerResponse",
                              @"adParams",
                              (IMP)YTKACEAdParams,
                              &OriginalAdParams);
    YTKACEInstallBooleanHookOrMethod(@"YTIClientMdxGlobalConfig",
                                     @"enableSkippableAd",
                                     (IMP)YTKACEEnableSkippableAd,
                                     &OriginalEnableSkippableAd);

    YTKACEInstallInstanceHook(@"MDXSessionImpl",
                              @"adPlaying:",
                              (IMP)YTKACEMDXSessionImplAdPlaying,
                              &OriginalMDXSessionImplAdPlaying);
    YTKACEInstallInstanceHook(@"MDXSession",
                              @"adPlaying:",
                              (IMP)YTKACEMDXSessionAdPlaying,
                              &OriginalMDXSessionAdPlaying);
    YTKACEInstallInstanceHook(@"YTLocalPlaybackController",
                              @"isPlayingAd",
                              (IMP)YTKACEIsPlayingAd,
                              &OriginalIsPlayingAd);
    YTKACEInstallInstanceHook(@"YTLocalPlaybackController",
                              @"isPlayingAdSurvey",
                              (IMP)YTKACEIsPlayingAdSurvey,
                              &OriginalIsPlayingAdSurvey);
    YTKACEInstallInstanceHook(@"YTLocalPlaybackController",
                              @"isPlayingAdIntro",
                              (IMP)YTKACEIsPlayingAdIntro,
                              &OriginalIsPlayingAdIntro);
    YTKACEInstallInstanceHook(@"YTLocalPlaybackController",
                              @"createAdsPlaybackCoordinator",
                              (IMP)YTKACENoAdsPlaybackCoordinator,
                              &OriginalCreateAdsPlaybackCoordinator);

    YTKACEInstallInstanceHook(@"YTReelDataSource",
                              @"makeContentModelForEntry:",
                              (IMP)YTKACEReelContentModel,
                              &OriginalReelContentModel);
    YTKACEInstallInstanceHook(@"YTReelInfinitePlaybackDataSource",
                              @"makeContentModelForEntry:",
                              (IMP)YTKACEInfiniteReelContentModel,
                              &OriginalInfiniteReelContentModel);
    YTKACEInstallInstanceHook(@"YTReelContentModel",
                              @"shouldDisplay",
                              (IMP)YTKACEReelShouldDisplay,
                              &OriginalReelShouldDisplay);
    YTKACEInstallInstanceHook(@"YTIElementRenderer",
                              @"companionAd",
                              (IMP)YTKACENoCompanionAd,
                              &OriginalCompanionAd);
    YTKACEInstallInstanceHook(@"YTIElementRenderer",
                              @"hasCompanionAdRenderer",
                              (IMP)YTKACEHasCompanionAdRenderer,
                              &OriginalHasCompanionAdRenderer);
    YTKACEInstallInstanceHook(@"YTIElementRenderer",
                              @"hasAppPromoCompanionAdRenderer",
                              (IMP)YTKACEHasAppPromoCompanionAdRenderer,
                              &OriginalHasAppPromoCompanionAdRenderer);
    YTKACEInstallInstanceHook(@"YTIElementRenderer",
                              @"hasShoppingCompanionAdRenderer",
                              (IMP)YTKACEHasShoppingCompanionAdRenderer,
                              &OriginalHasShoppingCompanionAdRenderer);
    YTKACEInstallInstanceHook(@"YTIElementRenderer",
                              @"contentsArray",
                              (IMP)YTKACEElementContentsArray,
                              &OriginalElementContentsArray);
    YTKACEInstallInstanceHook(@"YTIItemSectionRenderer",
                              @"contentsArray",
                              (IMP)YTKACEItemSectionContentsArray,
                              &OriginalItemSectionContentsArray);
}
