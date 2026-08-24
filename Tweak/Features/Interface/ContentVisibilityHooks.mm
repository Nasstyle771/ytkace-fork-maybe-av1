#import "../../YTKACE.h"
#import "../../Runtime/Hooking.h"
#import "../../Runtime/Preferences.h"
#import "../Downloads/DownloadLog.h"

#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

static IMP OriginalEnableSubheaderBar;
static IMP OriginalChipBarUpdate;
static IMP OriginalChipCloudSetEntry;
static IMP OriginalSubsChipFilter;
static IMP OriginalChipCloudLayout;
static IMP OriginalFeedHeaderScrollMode;
static IMP OriginalSubsSetChipFilterView;
static IMP OriginalMaximumSubheaderHeight;
static IMP OriginalMaximumSubheaderHeightGetter;
static IMP OriginalSubheaderDefaultHeight;
static IMP OriginalSetHeaderHeights;
static IMP OriginalShouldHideSubheader;
static IMP OriginalPaidContentLayout;
static IMP OriginalPaidContentDidAppear;
static IMP OriginalPaidContentPlaybackStarted;
static IMP OriginalSetPaidContentPlayerData;
static IMP OriginalSetPaidContentRenderer;
static IMP OriginalHasPaidContentOverlay;
static IMP OriginalPaidContentOverlay;
static IMP OriginalOverlayPaidContentPlayerData;
static IMP OriginalInlinePaidContentPlayerData;
static IMP OriginalDidInsertPlayerOverlay;
static IMP OriginalScrollableActionButtonsArray;
static IMP OriginalScrollableActionBarButtonsArray;
static IMP OriginalScrollableButtonsArray;
static IMP OriginalScrollableActionsArray;
static IMP OriginalActionButtonsArray;
static IMP OriginalActionBarButtonsArray;
static IMP OriginalButtonsArray;
static IMP OriginalActionsArray;
static IMP OriginalActionViewDidMove;
static IMP OriginalActionsViewDidMove;
static IMP OriginalActionCellDidMove;
static IMP OriginalCreateActionViews;
static const void *YTKACEContentHiddenAssociation = &YTKACEContentHiddenAssociation;
static const void *YTKACENormalizedDescriptionAssociation =
    &YTKACENormalizedDescriptionAssociation;

static NSString *YTKACENormalizedDescription(id object) {
    if (object == nil) return @"";
    NSString *cached = objc_getAssociatedObject(
        object, YTKACENormalizedDescriptionAssociation);
    if (cached != nil) return cached;
    NSString *value = [[[object description] lowercaseString]
        stringByReplacingOccurrencesOfString:@"." withString:@"_"];
    if (value == nil) value = @"";
    objc_setAssociatedObject(object, YTKACENormalizedDescriptionAssociation, value,
                             OBJC_ASSOCIATION_COPY_NONATOMIC);
    return value;
}

static BOOL YTKACEContentContains(NSString *token,
                                  NSArray<NSString *> *needles);
static BOOL YTKACEHideTopics(void);
static BOOL YTKACEEnsureStructuralActionHook(void);

static NSString *YTKACEActionPreference(id item) {
    if (item == nil) return nil;
    NSString *token = [[[NSString stringWithFormat:@"%s %@",
        class_getName([item class]), YTKACENormalizedDescription(item)] lowercaseString]
        stringByReplacingOccurrencesOfString:@"." withString:@"_"];
    static NSArray<NSArray<NSString *> *> *s_actionRules = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s_actionRules = @[
            @[@"YTKACE.Preference.ActionBar.DislikeHidden", @"dislike"],
            @[@"YTKACE.Preference.ActionBar.ShareHidden", @"share"],
            @[@"YTKACE.Preference.ActionBar.DownloadHidden", @"offline", @"download"],
            @[@"YTKACE.Preference.ActionBar.SaveHidden", @"save", @"add_to"],
            @[@"YTKACE.Preference.ActionBar.ClipHidden", @"clip"],
            @[@"YTKACE.Preference.ActionBar.RemixHidden", @"remix"],
            @[@"YTKACE.Preference.ActionBar.ThanksHidden", @"thanks"],
            @[@"YTKACE.Preference.ActionBar.HypeHidden", @"hype"],
            @[@"YTKACE.Preference.ActionBar.ReportHidden", @"id_player_watch_flag_button", @"report"],
            @[@"YTKACE.Preference.ActionBar.AskHidden", @"ask", @"gemini"],
            @[@"YTKACE.Preference.ActionBar.LikeHidden", @"like"]
        ];
    });
    for (NSArray<NSString *> *rule in s_actionRules) {
        for (NSUInteger index = 1; index < rule.count; index++) {
            if ([token containsString:rule[index]]) return rule.firstObject;
        }
    }
    return nil;
}

static BOOL YTKACEAnyActionPreferenceEnabled(void) {
    for (NSString *key in @[
        @"YTKACE.Preference.ActionBar.LikeHidden",
        @"YTKACE.Preference.ActionBar.DislikeHidden",
        @"YTKACE.Preference.ActionBar.ShareHidden",
        @"YTKACE.Preference.ActionBar.DownloadHidden",
        @"YTKACE.Preference.ActionBar.SaveHidden",
        @"YTKACE.Preference.ActionBar.ClipHidden",
        @"YTKACE.Preference.ActionBar.RemixHidden",
        @"YTKACE.Preference.ActionBar.ThanksHidden",
        @"YTKACE.Preference.ActionBar.HypeHidden",
        @"YTKACE.Preference.ActionBar.ReportHidden",
        @"YTKACE.Preference.ActionBar.AskHidden"
    ]) {
        if (YTKACEFeatureEnabled(key)) return YES;
    }
    return NO;
}

static void YTKACECreateActionViews(id receiver, SEL selector,
                                    NSArray *renderers) {
    NSArray *filtered = renderers;
    if ([renderers isKindOfClass:NSArray.class]) {
        static NSUInteger rendererLogged = 0;
        if (rendererLogged < 3) {
            rendererLogged++;
            NSMutableArray<NSString *> *shape = [NSMutableArray array];
            for (id renderer in renderers) {
                NSString *match = YTKACEActionPreference(renderer);
                NSMutableString *entry = [NSMutableString stringWithString:
                    NSStringFromClass([renderer class])];
                for (NSString *probe in @[@"likeButton", @"dislikeButton",
                                          @"segmentedLikeDislikeButton",
                                          @"buttonRenderer", @"targetId",
                                          @"trackingParams"]) {
                    SEL selector = NSSelectorFromString(probe);
                    if ([renderer respondsToSelector:selector]) {
                        [entry appendFormat:@" %@?", probe];
                    }
                }
                if (match.length != 0) {
                    [entry appendFormat:@" ->%@",
                        [match componentsSeparatedByString:@"."].lastObject];
                }
                [shape addObject:entry];
            }
        }
    }
    if ([renderers isKindOfClass:NSArray.class] &&
        renderers.count != 0 && YTKACEAnyActionPreferenceEnabled()) {
        NSMutableArray *kept = [NSMutableArray arrayWithCapacity:renderers.count];
        for (id renderer in renderers) {
            NSString *preference = YTKACEActionPreference(renderer);
            if (preference.length != 0 && YTKACEFeatureEnabled(preference)) {
                continue;
            }
            [kept addObject:renderer];
        }
        if (kept.count != renderers.count) filtered = kept;
    }
    if (OriginalCreateActionViews != NULL) {
        ((void (*)(id, SEL, id))OriginalCreateActionViews)(
            receiver, selector, filtered);
    }
}

static BOOL YTKACEEnsureStructuralActionHook(void) {
    if (OriginalCreateActionViews != NULL) return YES;

    BOOL installed = YTKACEInstallInstanceHook(
        @"YTSlimVideoScrollableDetailsActionsView",
        @"createActionViewsFromSupportedRenderers:",
        (IMP)YTKACECreateActionViews,
        &OriginalCreateActionViews
    );
    if (installed && OriginalCreateActionViews != NULL) return YES;
    return NO;
}

static NSArray *YTKACEFilterActionButtons(id receiver, SEL selector,
                                           IMP original) {
    NSArray *items = original == NULL ? nil :
        ((id (*)(id, SEL))original)(receiver, selector);
    if (![items isKindOfClass:NSArray.class] || items.count == 0) return items;
    if (!YTKACEAnyActionPreferenceEnabled()) return items;
    NSMutableArray *filtered = [NSMutableArray arrayWithCapacity:items.count];
    for (id item in items) {
        NSString *preference = YTKACEActionPreference(item);
        if (preference.length != 0 && YTKACEFeatureEnabled(preference)) continue;
        [filtered addObject:item];
    }
    return filtered.count == items.count ? items : filtered;
}

static void YTKACEActionViewDidMove(UIView *receiver, SEL selector) {
    if (OriginalActionViewDidMove != NULL) {
        ((void (*)(id, SEL))OriginalActionViewDidMove)(receiver, selector);
    }
}

static void YTKACEActionsViewDidMove(UIView *receiver, SEL selector) {
    if (OriginalActionsViewDidMove != NULL) {
        ((void (*)(id, SEL))OriginalActionsViewDidMove)(receiver, selector);
    }
}

static void YTKACEActionCellDidMove(UIView *receiver, SEL selector) {
    if (OriginalActionCellDidMove != NULL) {
        ((void (*)(id, SEL))OriginalActionCellDidMove)(receiver, selector);
    }
}

#define YTKACE_ACTION_WRAPPER(name, storage) \
static NSArray *name(id receiver, SEL selector) { \
    return YTKACEFilterActionButtons(receiver, selector, storage); \
}

YTKACE_ACTION_WRAPPER(YTKACEScrollableActionButtonsArray, OriginalScrollableActionButtonsArray)
YTKACE_ACTION_WRAPPER(YTKACEScrollableActionBarButtonsArray, OriginalScrollableActionBarButtonsArray)
YTKACE_ACTION_WRAPPER(YTKACEScrollableButtonsArray, OriginalScrollableButtonsArray)
YTKACE_ACTION_WRAPPER(YTKACEScrollableActionsArray, OriginalScrollableActionsArray)
YTKACE_ACTION_WRAPPER(YTKACEActionButtonsArray, OriginalActionButtonsArray)
YTKACE_ACTION_WRAPPER(YTKACEActionBarButtonsArray, OriginalActionBarButtonsArray)
YTKACE_ACTION_WRAPPER(YTKACEButtonsArray, OriginalButtonsArray)
YTKACE_ACTION_WRAPPER(YTKACEActionsArray, OriginalActionsArray)

static id YTKACEContentValue(id object, NSString *key) {
    if (object == nil || key.length == 0) {
        return nil;
    }
    @try {
        SEL selector = NSSelectorFromString(key);
        if ([object respondsToSelector:selector]) {
            return ((id (*)(id, SEL))objc_msgSend)(object, selector);
        }
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}



static BOOL YTKACEContentContains(NSString *token,
                                  NSArray<NSString *> *needles) {
    for (NSString *needle in needles) {
        if ([token containsString:needle]) {
            return YES;
        }
    }
    return NO;
}

static BOOL YTKACEHideTopics(void) {
    return YTKACEFeatureEnabled(@"YTKACE.Preference.Navigation.TopicsHidden");
}

static void YTKACECollapseSubheader(id receiver) {
    SEL height = NSSelectorFromString(@"setMaximumSubheaderHeight:");
    if ([receiver respondsToSelector:height]) {
        ((void (*)(id, SEL, double))objc_msgSend)(receiver, height, 0.0);
    }
    for (NSString *name in @[@"hideSubheaderBar", @"disableSubheaderBar",
                             @"setSubheaderHeightToZero",
                             @"resetScrollViewInsetOffset"]) {
        SEL selector = NSSelectorFromString(name);
        if ([receiver respondsToSelector:selector]) {
            ((void (*)(id, SEL))objc_msgSend)(receiver, selector);
        }
    }
    SEL enabled = NSSelectorFromString(@"setSubheaderBarEnabled:");
    if ([receiver respondsToSelector:enabled]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(receiver, enabled, NO);
    }
}

static double YTKACEMaximumSubheaderHeightGetter(id receiver, SEL selector) {
    if (YTKACEHideTopics()) return 0.0;
    return OriginalMaximumSubheaderHeightGetter == NULL
        ? 0.0
        : ((double (*)(id, SEL))OriginalMaximumSubheaderHeightGetter)(
            receiver, selector);
}

static double YTKACESubheaderDefaultHeight(id receiver, SEL selector) {
    if (YTKACEHideTopics()) return 0.0;
    return OriginalSubheaderDefaultHeight == NULL
        ? 0.0
        : ((double (*)(id, SEL))OriginalSubheaderDefaultHeight)(
            receiver, selector);
}

static void YTKACEPaidContentLayout(UIView *receiver, SEL selector) {
    if (OriginalPaidContentLayout != NULL) {
        ((void (*)(id, SEL))OriginalPaidContentLayout)(receiver, selector);
    }
    BOOL hide = YTKACEFeatureEnabled(@"YTKACE.Preference.Overlay.PaidPromotionHidden");
    NSNumber *baseline = objc_getAssociatedObject(
        receiver, YTKACEContentHiddenAssociation);
    if (hide) {
        if (baseline == nil) {
            objc_setAssociatedObject(receiver,
                                     YTKACEContentHiddenAssociation,
                                     @(receiver.hidden),
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        receiver.hidden = YES;
        receiver.userInteractionEnabled = NO;
    } else if (baseline != nil) {
        receiver.hidden = baseline.boolValue;
        receiver.userInteractionEnabled = YES;
        objc_setAssociatedObject(receiver,
                                 YTKACEContentHiddenAssociation,
                                 nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void YTKACEPaidContentDidAppear(UIViewController *receiver,
                                       SEL selector,
                                       BOOL animated) {
    if (OriginalPaidContentDidAppear != NULL) {
        ((void (*)(id, SEL, BOOL))OriginalPaidContentDidAppear)(
            receiver, selector, animated);
    }
    if (!YTKACEFeatureEnabled(@"YTKACE.Preference.Overlay.PaidPromotionHidden")) return;
    receiver.view.hidden = YES;
    receiver.view.userInteractionEnabled = NO;
    for (NSString *name in @[@"hidePaidContent",
                             @"removePaidContentViewController"]) {
        SEL action = NSSelectorFromString(name);
        if ([receiver respondsToSelector:action]) {
            ((void (*)(id, SEL))objc_msgSend)(receiver, action);
        }
    }
}

static void YTKACEPaidContentPlaybackStarted(id receiver, SEL selector) {
    if (!YTKACEFeatureEnabled(@"YTKACE.Preference.Overlay.PaidPromotionHidden") &&
        OriginalPaidContentPlaybackStarted != NULL) {
        ((void (*)(id, SEL))OriginalPaidContentPlaybackStarted)(receiver, selector);
    }
}

static void YTKACESetPaidContentPlayerData(id receiver, SEL selector, id data) {
    if (!YTKACEFeatureEnabled(@"YTKACE.Preference.Overlay.PaidPromotionHidden") &&
        OriginalSetPaidContentPlayerData != NULL) {
        ((void (*)(id, SEL, id))OriginalSetPaidContentPlayerData)(
            receiver, selector, data);
    }
}

static void YTKACESetPaidContentRenderer(id receiver, SEL selector, id renderer) {
    if (OriginalSetPaidContentRenderer != NULL) {
        ((void (*)(id, SEL, id))OriginalSetPaidContentRenderer)(
            receiver, selector,
            YTKACEFeatureEnabled(@"YTKACE.Preference.Overlay.PaidPromotionHidden") ? nil : renderer);
    }
}

static BOOL YTKACEHasPaidContentOverlay(id receiver, SEL selector) {
    if (YTKACEFeatureEnabled(@"YTKACE.Preference.Overlay.PaidPromotionHidden")) return NO;
    return OriginalHasPaidContentOverlay != NULL &&
        ((BOOL (*)(id, SEL))OriginalHasPaidContentOverlay)(receiver, selector);
}

static id YTKACEPaidContentOverlay(id receiver, SEL selector) {
    if (YTKACEFeatureEnabled(@"YTKACE.Preference.Overlay.PaidPromotionHidden")) return nil;
    return OriginalPaidContentOverlay == NULL ? nil :
        ((id (*)(id, SEL))OriginalPaidContentOverlay)(receiver, selector);
}

static void YTKACEOverlayPaidContentPlayerData(id receiver, SEL selector, id data) {
    if (!YTKACEFeatureEnabled(@"YTKACE.Preference.Overlay.PaidPromotionHidden") &&
        OriginalOverlayPaidContentPlayerData != NULL) {
        ((void (*)(id, SEL, id))OriginalOverlayPaidContentPlayerData)(
            receiver, selector, data);
    }
}

static void YTKACEInlinePaidContentPlayerData(id receiver, SEL selector, id data) {
    if (!YTKACEFeatureEnabled(@"YTKACE.Preference.Overlay.PaidPromotionHidden") &&
        OriginalInlinePaidContentPlayerData != NULL) {
        ((void (*)(id, SEL, id))OriginalInlinePaidContentPlayerData)(
            receiver, selector, data);
    }
}

static void YTKACEDidInsertPlayerOverlay(id receiver, SEL selector,
                                         id provider, id overlay) {
    NSString *identifier = YTKACEContentValue(overlay, @"overlayIdentifier");
    if (YTKACEFeatureEnabled(@"YTKACE.Preference.Overlay.PaidPromotionHidden") &&
        [identifier isEqualToString:@"player_overlay_paid_content"]) {
        return;
    }
    if (YTKACEFeatureEnabled(@"YTKACE.Preference.Overlay.ProductsHidden") &&
        [identifier isEqualToString:@"player_overlay_product_in_video"]) {
        return;
    }
    if (OriginalDidInsertPlayerOverlay != NULL) {
        ((void (*)(id, SEL, id, id))OriginalDidInsertPlayerOverlay)(
            receiver, selector, provider, overlay);
    }
}

static void YTKACEEnableSubheaderBar(__unsafe_unretained id receiver, SEL selector,
                                     __unsafe_unretained id view) {
    BOOL hide = YTKACEHideTopics();
    if (hide) {
        YTKACECollapseSubheader(receiver);
        return;
    }
    if (OriginalEnableSubheaderBar != NULL) {
        ((void (*)(id, SEL, id))OriginalEnableSubheaderBar)(receiver, selector, view);
    }
}

static void YTKACEChipBarUpdate(__unsafe_unretained id receiver, SEL selector,
                                __unsafe_unretained id collectionViewController,
                                __unsafe_unretained id host,
                                __unsafe_unretained id renderer,
                                __unsafe_unretained id browseIdentifier,
                                __unsafe_unretained id sectionList) {
    BOOL hide = YTKACEHideTopics();
    if (hide) return;
    if (OriginalChipBarUpdate != NULL) {
        ((void (*)(id, SEL, id, id, id, id, id))OriginalChipBarUpdate)(
            receiver, selector, collectionViewController, host, renderer,
            browseIdentifier, sectionList);
    }
}

static void YTKACEChipCloudSetEntry(__unsafe_unretained id receiver, SEL selector,
                                    __unsafe_unretained id entry) {
    if (OriginalChipCloudSetEntry != NULL) {
        ((void (*)(id, SEL, id))OriginalChipCloudSetEntry)(receiver, selector, entry);
    }
    BOOL hide = YTKACEHideTopics();
    if (!hide) return;
    if ([receiver isKindOfClass:UIView.class]) {
        UIView *cell = (UIView *)receiver;
        cell.hidden = YES;
        cell.userInteractionEnabled = NO;
    }
}

static void YTKACEChipCloudLayout(__unsafe_unretained id receiver, SEL selector) {
    if (OriginalChipCloudLayout != NULL) {
        ((void (*)(id, SEL))OriginalChipCloudLayout)(receiver, selector);
    }
    BOOL hide = YTKACEHideTopics();
    if (!hide) return;
    if (![receiver isKindOfClass:UIView.class]) return;
    UIView *cell = (UIView *)receiver;
    cell.hidden = YES;
    cell.userInteractionEnabled = NO;
    CGRect frame = cell.frame;
    if (frame.size.height != 0.0) {
        frame.size.height = 0.0;
        cell.frame = frame;
    }
    for (UIView *subview in cell.subviews) {
        subview.hidden = YES;
    }
}

static void YTKACEFeedHeaderScrollMode(__unsafe_unretained id receiver, SEL selector,
                                       NSInteger mode) {
    if (OriginalFeedHeaderScrollMode != NULL) {
        ((void (*)(id, SEL, NSInteger))OriginalFeedHeaderScrollMode)(
            receiver, selector, mode);
    }
}

static void YTKACESubsSetChipFilterView(__unsafe_unretained id receiver, SEL selector,
                                        __unsafe_unretained id view) {
    BOOL hide = YTKACEHideTopics();
    if (hide) return;
    if (OriginalSubsSetChipFilterView != NULL) {
        ((void (*)(id, SEL, id))OriginalSubsSetChipFilterView)(receiver, selector, view);
    }
}

static void YTKACESubsChipFilter(__unsafe_unretained id receiver, SEL selector,
                                 __unsafe_unretained id model) {
    BOOL hide = YTKACEHideTopics();
    if (hide) return;
    if (OriginalSubsChipFilter != NULL) {
        ((void (*)(id, SEL, id))OriginalSubsChipFilter)(receiver, selector, model);
    }
}

static void YTKACEMaximumSubheaderHeight(__unsafe_unretained id receiver,
                                        SEL selector, double height) {
    BOOL hide = YTKACEHideTopics();
    if (hide) height = 0.0;
    if (OriginalMaximumSubheaderHeight != NULL) {
        ((void (*)(id, SEL, double))OriginalMaximumSubheaderHeight)(
            receiver, selector, height);
    }
}

static void YTKACESetHeaderHeights(id receiver, SEL selector,
                                    double headerHeight,
                                    double subheaderHeight,
                                    double topOffset,
                                    BOOL animated) {
    if (YTKACEHideTopics()) {
        subheaderHeight = 0.0;
    }
    if (OriginalSetHeaderHeights != NULL) {
        ((void (*)(id, SEL, double, double, double, BOOL))OriginalSetHeaderHeights)(
            receiver, selector, headerHeight, subheaderHeight, topOffset, animated);
    }
}

static BOOL YTKACEShouldHideSubheader(id receiver, SEL selector) {
    if (YTKACEHideTopics()) return YES;
    return OriginalShouldHideSubheader != NULL &&
        ((BOOL (*)(id, SEL))OriginalShouldHideSubheader)(receiver, selector);
}

void YTKACEInstallContentVisibilityHooks(void) {
    __unused NSArray<NSNumber *> *actionHooks = @[
        @(YTKACEInstallInstanceHook(@"YTISlimVideoScrollableActionBarRenderer",
                                    @"actionButtonsArray",
                                    (IMP)YTKACEScrollableActionButtonsArray,
                                    &OriginalScrollableActionButtonsArray)),
        @(YTKACEInstallInstanceHook(@"YTISlimVideoScrollableActionBarRenderer",
                                    @"actionBarButtonsArray",
                                    (IMP)YTKACEScrollableActionBarButtonsArray,
                                    &OriginalScrollableActionBarButtonsArray)),
        @(YTKACEInstallInstanceHook(@"YTISlimVideoScrollableActionBarRenderer",
                                    @"buttonsArray",
                                    (IMP)YTKACEScrollableButtonsArray,
                                    &OriginalScrollableButtonsArray)),
        @(YTKACEInstallInstanceHook(@"YTISlimVideoScrollableActionBarRenderer",
                                    @"actionsArray",
                                    (IMP)YTKACEScrollableActionsArray,
                                    &OriginalScrollableActionsArray)),
        @(YTKACEInstallInstanceHook(@"YTISlimVideoActionBarRenderer",
                                    @"actionButtonsArray",
                                    (IMP)YTKACEActionButtonsArray,
                                    &OriginalActionButtonsArray)),
        @(YTKACEInstallInstanceHook(@"YTISlimVideoActionBarRenderer",
                                    @"actionBarButtonsArray",
                                    (IMP)YTKACEActionBarButtonsArray,
                                    &OriginalActionBarButtonsArray)),
        @(YTKACEInstallInstanceHook(@"YTISlimVideoActionBarRenderer",
                                    @"buttonsArray",
                                    (IMP)YTKACEButtonsArray,
                                    &OriginalButtonsArray)),
        @(YTKACEInstallInstanceHook(@"YTISlimVideoActionBarRenderer",
                                    @"actionsArray",
                                    (IMP)YTKACEActionsArray,
                                    &OriginalActionsArray))
    ];
    YTKACEInstallInstanceHook(@"YTSlimVideoDetailsActionView",
                              @"didMoveToWindow",
                              (IMP)YTKACEActionViewDidMove,
                              &OriginalActionViewDidMove);
    YTKACEEnsureStructuralActionHook();
    YTKACEInstallInstanceHook(@"YTSlimVideoScrollableDetailsActionsView",
                              @"didMoveToWindow",
                              (IMP)YTKACEActionsViewDidMove,
                              &OriginalActionsViewDidMove);
    YTKACEInstallInstanceHook(@"YTSlimVideoScrollableActionBarCell",
                              @"didMoveToWindow",
                              (IMP)YTKACEActionCellDidMove,
                              &OriginalActionCellDidMove);
    YTKACEInstallInstanceHook(@"YTHeaderContentComboView",
                              @"enableSubheaderBarWithView:",
                              (IMP)YTKACEEnableSubheaderBar,
                              &OriginalEnableSubheaderBar);
    YTKACEInstallInstanceHook(@"YTFeedFilterChipBarController",
                              @"updateWithCollectionViewController:feedFilterChipBarHost:feedFilterChipBarRenderer:browseIdentifier:sectionList:",
                              (IMP)YTKACEChipBarUpdate,
                              &OriginalChipBarUpdate);
    YTKACEInstallInstanceHook(@"YTChipCloudCell",
                              @"setEntry:",
                              (IMP)YTKACEChipCloudSetEntry,
                              &OriginalChipCloudSetEntry);
    YTKACEInstallInstanceHook(@"YTMySubsFilterHeaderViewController",
                              @"loadChipFilterFromModel:",
                              (IMP)YTKACESubsChipFilter,
                              &OriginalSubsChipFilter);
    YTKACEInstallInstanceHook(@"YTChipCloudCell",
                              @"layoutSubviews",
                              (IMP)YTKACEChipCloudLayout,
                              &OriginalChipCloudLayout);
    YTKACEInstallInstanceHook(@"YTHeaderContentComboView",
                              @"setFeedHeaderScrollMode:",
                              (IMP)YTKACEFeedHeaderScrollMode,
                              &OriginalFeedHeaderScrollMode);
    YTKACEInstallInstanceHook(@"YTHeaderContentComboView",
                              @"setMaximumSubheaderHeight:",
                              (IMP)YTKACEMaximumSubheaderHeight,
                              &OriginalMaximumSubheaderHeight);
    YTKACEInstallInstanceHook(@"YTHeaderContentComboView",
                              @"maximumSubheaderHeight",
                              (IMP)YTKACEMaximumSubheaderHeightGetter,
                              &OriginalMaximumSubheaderHeightGetter);
    YTKACEInstallInstanceHook(@"YTHeaderContentComboView",
                              @"subheaderDefaultHeight",
                              (IMP)YTKACESubheaderDefaultHeight,
                              &OriginalSubheaderDefaultHeight);
    YTKACEInstallInstanceHook(@"YTHeaderContentComboView",
                              @"setHeaderHeight:subheaderHeight:topOffset:animated:",
                              (IMP)YTKACESetHeaderHeights,
                              &OriginalSetHeaderHeights);
    YTKACEInstallInstanceHook(@"YTHeaderContentComboView",
                              @"shouldHideSubHeader",
                              (IMP)YTKACEShouldHideSubheader,
                              &OriginalShouldHideSubheader);
    YTKACEInstallInstanceHook(@"YTMySubsFilterHeaderView",
                              @"setChipFilterView:",
                              (IMP)YTKACESubsSetChipFilterView,
                              &OriginalSubsSetChipFilterView);
    YTKACEInstallInstanceHook(@"YTPaidContentOverlayView",
                              @"layoutSubviews",
                              (IMP)YTKACEPaidContentLayout,
                              &OriginalPaidContentLayout);
    YTKACEInstallInstanceHook(@"YTPaidContentViewController",
                              @"viewDidAppear:",
                              (IMP)YTKACEPaidContentDidAppear,
                              &OriginalPaidContentDidAppear);
    YTKACEInstallInstanceHook(@"YTPaidContentController",
                              @"playbackDidStart",
                              (IMP)YTKACEPaidContentPlaybackStarted,
                              &OriginalPaidContentPlaybackStarted);
    YTKACEInstallInstanceHook(@"YTPaidContentController",
                              @"setPaidContentWithPlayerData:",
                              (IMP)YTKACESetPaidContentPlayerData,
                              &OriginalSetPaidContentPlayerData);
    YTKACEInstallInstanceHook(@"YTPaidContentViewController",
                              @"setPaidContentRenderer:",
                              (IMP)YTKACESetPaidContentRenderer,
                              &OriginalSetPaidContentRenderer);
    YTKACEInstallInstanceHook(@"YTIPlayerResponse",
                              @"hasPaidContentOverlay",
                              (IMP)YTKACEHasPaidContentOverlay,
                              &OriginalHasPaidContentOverlay);
    YTKACEInstallInstanceHook(@"YTIPlayerResponse",
                              @"paidContentOverlay",
                              (IMP)YTKACEPaidContentOverlay,
                              &OriginalPaidContentOverlay);
    YTKACEInstallInstanceHook(@"YTMainAppVideoPlayerOverlayViewController",
                              @"setPaidContentWithPlayerData:",
                              (IMP)YTKACEOverlayPaidContentPlayerData,
                              &OriginalOverlayPaidContentPlayerData);
    YTKACEInstallInstanceHook(@"YTInlineMutedPlaybackPlayerOverlayViewController",
                              @"setPaidContentWithPlayerData:",
                              (IMP)YTKACEInlinePaidContentPlayerData,
                              &OriginalInlinePaidContentPlayerData);
    YTKACEInstallInstanceHook(@"YTMainAppVideoPlayerOverlayViewController",
                              @"playerOverlayProvider:didInsertPlayerOverlay:",
                              (IMP)YTKACEDidInsertPlayerOverlay,
                              &OriginalDidInsertPlayerOverlay);
}
