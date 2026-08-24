#import "../../YTKACE.h"
#import "../../Runtime/Hooking.h"
#import "../../Runtime/Preferences.h"

#import <UIKit/UIKit.h>

static IMP OriginalImageNamedBundleTraits;
static IMP OriginalImageNamedBundle;

static NSBundle *YTKACEInnertubeBundle(void) {
    static NSBundle *s_cachedBundle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSBundle *main = NSBundle.mainBundle;
        NSArray<NSString *> *paths = @[
            [main.resourcePath stringByAppendingPathComponent:@"Innertube_Resources.bundle"],
            [main.resourcePath stringByAppendingPathComponent:@"Frameworks/Module_Framework.framework/Innertube_Resources.bundle"]
        ];
        for (NSString *path in paths) {
            NSBundle *bundle = [NSBundle bundleWithPath:path];
            if (bundle != nil) {
                s_cachedBundle = bundle;
                break;
            }
        }
    });
    return s_cachedBundle;
}

static NSString *YTKACEPremiumName(NSString *name,
                                    UITraitCollection *traits) {
    BOOL darkName = [name rangeOfString:@"dark" options:NSCaseInsensitiveSearch].location != NSNotFound;
    BOOL darkMode = NO;
    if (@available(iOS 13.0, *)) {
        darkMode = traits.userInterfaceStyle == UIUserInterfaceStyleDark;
    }
    return darkName || darkMode
        ? @"youtube_premium_logo_white"
        : @"youtube_premium_logo";
}

static BOOL YTKACEShouldReplaceLogo(NSString *name) {
    if (![name isKindOfClass:NSString.class]) {
        return NO;
    }
    if (!YTKACEFeatureEnabled(@"YTKACE.Preference.Navigation.PremiumLogo")) {
        return NO;
    }
    return [name rangeOfString:@"youtube_logo" options:NSCaseInsensitiveSearch].location != NSNotFound &&
           [name rangeOfString:@"premium" options:NSCaseInsensitiveSearch].location == NSNotFound;
}

static UIImage *YTKACEImageNamedBundleTraits(id receiver,
                                              SEL selector,
                                              NSString *name,
                                              NSBundle *bundle,
                                              UITraitCollection *traits) {
    if (OriginalImageNamedBundleTraits == NULL) {
        return nil;
    }
    UIImage *(*original)(id, SEL, NSString *, NSBundle *, UITraitCollection *) =
        (UIImage *(*)(id, SEL, NSString *, NSBundle *, UITraitCollection *))
            OriginalImageNamedBundleTraits;
    if (YTKACEShouldReplaceLogo(name)) {
        NSBundle *resources = YTKACEInnertubeBundle() ?: bundle;
        UIImage *premium = original(
            receiver,
            selector,
            YTKACEPremiumName(name, traits),
            resources,
            traits
        );
        if (premium != nil) {
            return premium;
        }
    }
    return original(receiver, selector, name, bundle, traits);
}

static UIImage *YTKACEImageNamedBundle(id receiver,
                                       SEL selector,
                                       NSString *name,
                                       NSBundle *bundle) {
    if (OriginalImageNamedBundle == NULL) {
        return nil;
    }
    UIImage *(*original)(id, SEL, NSString *, NSBundle *) =
        (UIImage *(*)(id, SEL, NSString *, NSBundle *))OriginalImageNamedBundle;
    if (YTKACEShouldReplaceLogo(name)) {
        NSBundle *resources = YTKACEInnertubeBundle() ?: bundle;
        UIImage *premium = original(
            receiver,
            selector,
            YTKACEPremiumName(name, UIScreen.mainScreen.traitCollection),
            resources
        );
        if (premium != nil) {
            return premium;
        }
    }
    return original(receiver, selector, name, bundle);
}

void YTKACEInstallPremiumLogoHooks(void) {
    YTKACEInstallClassHook(@"UIImage",
                           @"imageNamed:inBundle:compatibleWithTraitCollection:",
                           (IMP)YTKACEImageNamedBundleTraits,
                           &OriginalImageNamedBundleTraits);
    YTKACEInstallClassHook(@"UIImage",
                           @"imageNamed:inBundle:",
                           (IMP)YTKACEImageNamedBundle,
                           &OriginalImageNamedBundle);
}
