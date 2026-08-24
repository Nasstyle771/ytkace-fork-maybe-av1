#import "../../YTKACE.h"
#import "../../Runtime/Hooking.h"
#import "../../Runtime/Preferences.h"
#import "../Interface/NavigationVisibility.h"

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static NSMutableDictionary<NSString *, NSValue *> *YTKACEOLEDOriginals;
static IMP OriginalQualitySheetDidAppear;
static IMP OriginalAppTraitChanged;
static IMP OriginalAppStatusBarStyle;

static NSValue *YTKACEOLEDValue(IMP implementation) {
    return [NSValue value:&implementation withObjCType:@encode(IMP)];
}

static IMP YTKACEOLEDImplementation(NSValue *value) {
    IMP implementation = NULL;
    [value getValue:&implementation];
    return implementation;
}

static NSString *YTKACEOLEDOriginalKey(id receiver, SEL selector) {
    BOOL classMethod = object_isClass(receiver);
    Class cls = classMethod ? receiver : [receiver class];
    return [NSString stringWithFormat:@"%@|%@|%@",
            classMethod ? @"+" : @"-",
            NSStringFromClass(cls),
            NSStringFromSelector(selector)];
}

static NSMutableDictionary<NSString *, UIColor *> *s_dynamicColorCache = nil;
static NSRegularExpression *s_qualityPattern = nil;
static dispatch_once_t s_qualityPatternOnceToken;

static BOOL YTKACEIsSurfaceSelector(SEL selector) {
    const char *name = sel_getName(selector);
    if (name == NULL) return NO;
    return (strstr(name, "menu") != NULL ||
            strstr(name, "dialog") != NULL ||
            strstr(name, "elevated") != NULL ||
            strstr(name, "raised") != NULL ||
            strstr(name, "Surface") != NULL ||
            strstr(name, "Container") != NULL ||
            strstr(name, "chip") != NULL ||
            strstr(name, "overlay") != NULL ||
            strstr(name, "Secondary") != NULL ||
            strstr(name, "background2") != NULL ||
            strstr(name, "background3") != NULL);
}

static UIColor *YTKACEOLEDColor(id receiver, SEL selector) {
    IMP original = YTKACEOLEDImplementation(
        YTKACEOLEDOriginals[YTKACEOLEDOriginalKey(receiver, selector)]
    );
    UIColor *base = original == NULL
        ? nil
        : ((id (*)(id, SEL))original)(receiver, selector);
    NSInteger preset = [NSUserDefaults.standardUserDefaults integerForKey:YTKACEThemePresetKey];
    BOOL oledEnabled = YTKACEFeatureEnabled(YTKACEOLEDKey);
    if (!oledEnabled && preset == 0) return base;

    const char *selName = sel_getName(selector) ?: "";
    NSString *cacheKey = [NSString stringWithFormat:@"%s|%ld|%d", selName, (long)preset, oledEnabled];
    if (s_dynamicColorCache == nil) {
        s_dynamicColorCache = [NSMutableDictionary dictionary];
    }
    UIColor *cached = s_dynamicColorCache[cacheKey];
    if (cached != nil) return cached;

    BOOL isSurface = YTKACEIsSurfaceSelector(selector);
    UIColor *dynamicColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        if (YTKACEOLEDActive(traits)) {
            return isSurface ? YTKACEThemeSurfaceColor(traits) : YTKACEThemeBackgroundColor(traits);
        }
        return base ?: UIColor.blackColor;
    }];
    s_dynamicColorCache[cacheKey] = dynamicColor;
    return dynamicColor;
}

static void YTKACERefreshStatusBars(UIViewController *controller) {
    if (controller == nil) return;
    [controller setNeedsStatusBarAppearanceUpdate];
    if ([controller isKindOfClass:UINavigationController.class]) {
        YTKACERefreshStatusBars(((UINavigationController *)controller).visibleViewController);
    } else if ([controller isKindOfClass:UITabBarController.class]) {
        YTKACERefreshStatusBars(((UITabBarController *)controller).selectedViewController);
    }
    YTKACERefreshStatusBars(controller.presentedViewController);
}

static NSInteger YTKACEAppStatusBarStyle(UIViewController *receiver,
                                         SEL selector) {
    NSInteger original = OriginalAppStatusBarStyle == NULL
        ? UIStatusBarStyleDefault
        : ((NSInteger (*)(id, SEL))OriginalAppStatusBarStyle)(receiver, selector);
    if (!YTKACEFeatureEnabled(YTKACEOLEDKey)) return original;
    UIUserInterfaceStyle style = receiver.traitCollection.userInterfaceStyle;
    NSInteger result = style == UIUserInterfaceStyleDark
        ? UIStatusBarStyleLightContent
        : UIStatusBarStyleDarkContent;
    return result;
}

static void YTKACEAppTraitChanged(UIViewController *receiver,
                                  SEL selector,
                                  UITraitCollection *previous) {
    if (OriginalAppTraitChanged != NULL) {
        ((void (*)(id, SEL, id))OriginalAppTraitChanged)(receiver, selector, previous);
    }
    if (previous != nil &&
        ![receiver.traitCollection
            hasDifferentColorAppearanceComparedToTraitCollection:previous]) return;
    if (!YTKACEFeatureEnabled(YTKACEOLEDKey)) return;
    [receiver setNeedsStatusBarAppearanceUpdate];
    [receiver.view setNeedsLayout];
    YTKACERefreshNavigationAppearance();
    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class] ||
                scene.activationState != UISceneActivationStateForegroundActive) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                YTKACERefreshStatusBars(window.rootViewController);
                [window setNeedsLayout];
            }
        }
        YTKACERefreshNavigationAppearance();
    });
}

static UIColor *YTKACEAccentColorHook(id receiver, SEL selector) {
    NSInteger preset = [NSUserDefaults.standardUserDefaults integerForKey:YTKACEAccentPresetKey];
    if (preset > 0) {
        return YTKACEAppAccentColor();
    }
    IMP original = YTKACEOLEDImplementation(
        YTKACEOLEDOriginals[YTKACEOLEDOriginalKey(receiver, selector)]
    );
    return original == NULL ? YTKACEAppAccentColor() : ((id (*)(id, SEL))original)(receiver, selector);
}

static void YTKACEInstallAccentHook(NSString *className,
                                    NSString *selectorName,
                                    BOOL classMethod) {
    IMP original = NULL;
    BOOL installed = classMethod
        ? YTKACEInstallClassHook(className,
                                selectorName,
                                (IMP)YTKACEAccentColorHook,
                                &original)
        : YTKACEInstallInstanceHook(className,
                                   selectorName,
                                   (IMP)YTKACEAccentColorHook,
                                   &original);
    if (!installed || original == NULL) {
        return;
    }
    NSString *key = [NSString stringWithFormat:@"%@|%@|%@",
                     classMethod ? @"+" : @"-",
                     className,
                     selectorName];
    if (YTKACEOLEDOriginals[key] == nil) {
        YTKACEOLEDOriginals[key] = YTKACEOLEDValue(original);
    }
}

static void YTKACEInstallColorHook(NSString *className,
                                   NSString *selectorName,
                                   BOOL classMethod) {
    IMP original = NULL;
    BOOL installed = classMethod
        ? YTKACEInstallClassHook(className,
                                selectorName,
                                (IMP)YTKACEOLEDColor,
                                &original)
        : YTKACEInstallInstanceHook(className,
                                   selectorName,
                                   (IMP)YTKACEOLEDColor,
                                   &original);
    if (!installed || original == NULL) {
        return;
    }
    NSString *key = [NSString stringWithFormat:@"%@|%@|%@",
                     classMethod ? @"+" : @"-",
                     className,
                     selectorName];
    if (YTKACEOLEDOriginals[key] == nil) {
        YTKACEOLEDOriginals[key] = YTKACEOLEDValue(original);
    }
}

static void YTKACECollectQualityLabels(UIView *view,
                                       NSMutableArray<UILabel *> *labels) {
    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label = (UILabel *)view;
        NSString *text = label.text ?: @"";
        dispatch_once(&s_qualityPatternOnceToken, ^{
            s_qualityPattern = [NSRegularExpression
                regularExpressionWithPattern:@"^\\s*\\d{3,4}p(?:60)?" options:0 error:nil];
        });
        if ([text localizedCaseInsensitiveContainsString:@"quality"] ||
            (s_qualityPattern != nil && [s_qualityPattern firstMatchInString:text options:0
                range:NSMakeRange(0, text.length)] != nil)) {
            [labels addObject:label];
        }
    }
    for (UIView *child in view.subviews) {
        YTKACECollectQualityLabels(child, labels);
    }
}

static UIView *YTKACECommonAncestor(NSArray<UIView *> *views, UIView *limit) {
    UIView *candidate = views.firstObject;
    while (candidate != nil && candidate != limit.superview) {
        BOOL containsAll = YES;
        for (UIView *view in views) {
            if (view != candidate && ![view isDescendantOfView:candidate]) {
                containsAll = NO;
                break;
            }
        }
        if (containsAll) return candidate;
        candidate = candidate.superview;
    }
    return nil;
}

static void YTKACEBlackenQualitySurface(UIView *view) {
    UIColor *surfaceColor = YTKACEThemeSurfaceColor(nil);
    if ([view isKindOfClass:UIVisualEffectView.class]) {
        UIVisualEffectView *effect = (UIVisualEffectView *)view;
        effect.effect = nil;
        effect.contentView.backgroundColor = surfaceColor;
    }
    UIColor *background = view.backgroundColor;
    CGFloat alpha = background == nil ? 0.0 : CGColorGetAlpha(background.CGColor);
    if (alpha > 0.01 || [view isKindOfClass:UITableView.class] ||
        [view isKindOfClass:UICollectionView.class]) {
        view.backgroundColor = surfaceColor;
    }
    if ([view isKindOfClass:UILabel.class]) {
        ((UILabel *)view).textColor = UIColor.whiteColor;
    }
    for (UIView *child in view.subviews) {
        YTKACEBlackenQualitySurface(child);
    }
}

static void YTKACEQualitySheetDidAppear(id receiver, SEL selector, BOOL animated) {
    if (OriginalQualitySheetDidAppear != NULL) {
        ((void (*)(id, SEL, BOOL))OriginalQualitySheetDidAppear)(
            receiver, selector, animated);
    }
    if (![receiver isKindOfClass:UIViewController.class] ||
        !YTKACEOLEDActive(((UIViewController *)receiver).traitCollection)) return;
    UIView *root = ((UIViewController *)receiver).view;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSMutableArray<UILabel *> *labels = [NSMutableArray array];
        YTKACECollectQualityLabels(root, labels);
        NSUInteger qualityRows = 0;
        for (UILabel *label in labels) {
            if ([label.text rangeOfString:@"p"].location != NSNotFound) qualityRows++;
        }
        if (qualityRows < 2) return;
        UIView *surface = YTKACECommonAncestor(labels, root);
        if (surface == nil || surface == root) {
            for (UIView *child in root.subviews) {
                NSUInteger count = 0;
                for (UILabel *label in labels) {
                    if ([label isDescendantOfView:child]) count++;
                }
                if (count == labels.count) {
                    surface = child;
                    break;
                }
            }
        }
        if (surface != nil && surface != root) {
            surface.backgroundColor = UIColor.blackColor;
            YTKACEBlackenQualitySurface(surface);
        }
    });
}

void YTKACEInstallOLEDHooks(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        YTKACEOLEDOriginals = [NSMutableDictionary dictionary];
    });

    for (NSString *selector in @[@"black0", @"black1", @"black2", @"black3", @"black4"]) {
        YTKACEInstallColorHook(@"YTColor", selector, YES);
    }

    NSArray<NSString *> *paletteSelectors = @[
        @"baseBackground",
        @"brandBackgroundPrimary",
        @"brandBackgroundSecondary",
        @"brandBackgroundSolid",
        @"brandSurfaceContainer",
        @"brandSurfaceContainerHigh",
        @"brandSurfaceContainerHighest",
        @"raisedBackground",
        @"staticBrandBlack",
        @"generalBackgroundA",
        @"generalBackgroundB",
        @"generalBackgroundC",
        @"menuBackground",
        @"dialogBackgroundColor",
        @"elevatedBackgroundColor",
        @"background1",
        @"background2",
        @"background3",
        @"overlayBackgroundSolid",
        @"brandSurface",
        @"chipBackground",
        @"adBackground"
    ];
    for (NSString *selector in paletteSelectors) {
        YTKACEInstallColorHook(@"YTCommonColorPalette", selector, NO);
        YTKACEInstallColorHook(@"YTCommonColorPalette", selector, YES);
    }

    for (NSString *selector in @[@"brandRed", @"red0", @"red1", @"red2"]) {
        YTKACEInstallAccentHook(@"YTColor", selector, YES);
    }
    for (NSString *selector in @[@"brandRed", @"callToAction", @"brandButton", @"brandIconActive"]) {
        YTKACEInstallAccentHook(@"YTCommonColorPalette", selector, NO);
        YTKACEInstallAccentHook(@"YTCommonColorPalette", selector, YES);
    }

    YTKACEInstallInstanceHook(@"YTActionSheetDialogViewController",
                              @"viewDidAppear:",
                              (IMP)YTKACEQualitySheetDidAppear,
                              &OriginalQualitySheetDidAppear);
    YTKACEInstallInstanceHook(@"YTAppViewController",
                              @"traitCollectionDidChange:",
                              (IMP)YTKACEAppTraitChanged,
                              &OriginalAppTraitChanged);
    YTKACEInstallInstanceHook(@"YTAppViewController",
                              @"preferredStatusBarStyle",
                              (IMP)YTKACEAppStatusBarStyle,
                              &OriginalAppStatusBarStyle);

    static dispatch_once_t notifToken;
    dispatch_once(&notifToken, ^{
        [NSNotificationCenter.defaultCenter
            addObserverForName:YTKACEPreferencesDidChangeNotification
                        object:nil
                         queue:NSOperationQueue.mainQueue
                    usingBlock:^(__unused NSNotification *notification) {
            [s_dynamicColorCache removeAllObjects];
            for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
                if (![scene isKindOfClass:UIWindowScene.class]) continue;
                for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                    [window.rootViewController setNeedsStatusBarAppearanceUpdate];
                    [window.rootViewController.view setNeedsLayout];
                    [window setNeedsDisplay];
                }
            }
            YTKACERefreshNavigationAppearance();
        }];
    });
}
