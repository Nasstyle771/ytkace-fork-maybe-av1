#import "Preferences.h"
#import "Localization.h"
#import "../Features/Downloads/SABRDownloader.h"

#import <UIKit/UIKit.h>
#import <os/lock.h>

static NSMutableDictionary<NSString *, id> *s_prefCache = nil;
static os_unfair_lock s_prefLock = OS_UNFAIR_LOCK_INIT;

NSString * const YTKACEMasterEnabledKey = @"YTKACE.Preference.Enabled";
NSString * const YTKACEOLEDKey = @"YTKACE.Preference.Appearance.OLED";
NSString * const YTKACENoAdsKey = @"YTKACE.Preference.Ads.Blocking";
NSString * const YTKACESponsorBlockKey = @"YTKACE.Preference.SponsorBlock.Enabled";
NSString * const YTKACEDownloadKey = @"YTKACE.Preference.Downloads.Enabled";
NSString * const YTKACEBackgroundPlaybackKey = @"YTKACE.Preference.Playback.BackgroundAudio";
NSString * const YTKACEPiPKey = @"YTKACE.Preference.Player.PiP";
NSString * const YTKACESpeedKey = @"YTKACE.Preference.Player.SpeedControls";
NSString * const YTKACELoopKey = @"YTKACE.Preference.Player.Loop";
NSString * const YTKACESleepTimerKey = @"YTKACE.Preference.Player.SleepTimer";
NSString * const YTKACEAccentPresetKey = @"YTKACE.Preference.Appearance.AccentPreset";
NSString * const YTKACEAccentHexKey = @"YTKACE.Preference.Appearance.CustomAccentHex";
NSString * const YTKACEThemePresetKey = @"YTKACE.Preference.Appearance.ThemePreset";
NSString * const YTKACEThemeTopHexKey = @"YTKACE.Preference.Appearance.ThemeTopHex";
NSString * const YTKACEThemeBottomHexKey = @"YTKACE.Preference.Appearance.ThemeBottomHex";
NSString * const YTKACEForce120HzKey = @"YTKACE.Preference.Appearance.Force120Hz";
NSString * const YTKACELockAV1Key = @"YTKACE.Preference.Downloads.LockAV1";
NSString * const YTKACEPreferredCodecKey = @"YTKACE.Preference.Downloads.PreferredCodec";
NSString * const YTKACEPreferencesDidChangeNotification =
    @"YTKACEPreferencesDidChangeNotification";

static NSUserDefaults *YTKACEDefaults(void) {
    return NSUserDefaults.standardUserDefaults;
}

static void YTKACEAnnouncePreferenceChange(NSString *key) {
    if (key.length == 0) return;
    if ([key isEqualToString:@"YTKACE.Preference.Language"]) {
        YTKACEResetLocalizationCache();
    }
    void (^post)(void) = ^{
        [NSNotificationCenter.defaultCenter
            postNotificationName:YTKACEPreferencesDidChangeNotification
                          object:nil
                        userInfo:@{@"key": key}];
    };
    if (NSThread.isMainThread) {
        post();
    } else {
        dispatch_async(dispatch_get_main_queue(), post);
    }
}

void YTKACERegisterDefaults(void) {
    id legacyBrightnessSide = [YTKACEDefaults()
        objectForKey:@"YTKACE.Preference.Gestures.BrightnessSide"];
    id legacyVolumeSide = [YTKACEDefaults()
        objectForKey:@"YTKACE.Preference.Gestures.VolumeSide"];
    BOOL hasLeftAction = [YTKACEDefaults()
        objectForKey:@"YTKACE.Preference.Gestures.LeftAction"] != nil;
    BOOL hasRightAction = [YTKACEDefaults()
        objectForKey:@"YTKACE.Preference.Gestures.RightAction"] != nil;
    NSDictionary *defaultDict = @{
        YTKACEMasterEnabledKey: @YES,
        YTKACENoAdsKey: @YES,
        YTKACEOLEDKey: @NO,
        YTKACEDownloadKey: @NO,
        YTKACEBackgroundPlaybackKey: @NO,
        YTKACEPiPKey: @NO,
        YTKACESpeedKey: @NO,
        YTKACELoopKey: @NO,
        @"YTKACE.Preference.Playback.CustomDoubleTap": @NO,
        @"YTKACE.Preference.Playback.TapToSeek": @NO,
        @"YTKACE.Preference.Sharing.NativeSheet": @NO,
        @"YTKACE.Preference.Shorts.RemixHidden": @NO,
        @"YTKACE.Preference.Shorts.ShareHidden": @NO,
        @"YTKACE.Preference.Shorts.CommentsHidden": @NO,
        @"YTKACE.Preference.Shorts.LikeHidden": @NO,
        @"YTKACE.Preference.Shorts.SoundHidden": @NO,
        @"YTKACE.Preference.Shorts.DownloadPosition": @0,
        @"YTKACE.Preference.Overlay.ProductsHidden": @NO,
        @"YTKACE.Preference.Feed.CommunityPostsHidden": @NO,
        @"YTKACE.Preference.Feed.MixesHidden": @NO,
        @"YTKACE.Preference.Feed.PlayablesHidden": @NO,
        @"YTKACE.Preference.Navigation.MessagesHidden": @NO,
        @"YTKACE.Preference.ActionBar.LikeHidden": @NO,
        @"YTKACE.Preference.ActionBar.DislikeHidden": @NO,
        @"YTKACE.Preference.ActionBar.ShareHidden": @NO,
        @"YTKACE.Preference.ActionBar.DownloadHidden": @NO,
        @"YTKACE.Preference.ActionBar.SaveHidden": @NO,
        @"YTKACE.Preference.ActionBar.ClipHidden": @NO,
        @"YTKACE.Preference.ActionBar.RemixHidden": @NO,
        @"YTKACE.Preference.ActionBar.ThanksHidden": @NO,
        @"YTKACE.Preference.ActionBar.HypeHidden": @NO,
        @"YTKACE.Preference.ActionBar.ReportHidden": @NO,
        @"YTKACE.Preference.ActionBar.AskHidden": @NO,
        @"YTKACE.Preference.Profiles.Preview": @YES,
        @"YTKACE.Preference.Appearance.LaunchAnimationDisabled": @NO,
        @"YTKACE.Preference.Player.StartRate": @0,
        @"YTKACE.Preference.Player.CustomRate": @1.5,
        @"YTKACE.Preference.Playback.DoubleTapSeconds": @10.0,
        @"YTKACE.Preference.Gestures.HoldSeekSeconds": @10.0,
        @"YTKACE.Preference.Gestures.VolumeSide": @2,
        @"YTKACE.Preference.Gestures.BrightnessSide": @2,
        @"YTKACE.Preference.Gestures.Enabled": @NO,
        @"YTKACE.Preference.Gestures.ActivationArea": @20.0,
        YTKACESleepTimerKey: @NO,
        @"YTKACE.Preference.Downloads.PreferredVideoQuality": @1080,
        @"YTKACE.Preference.Downloads.PreferredAudioQuality": @160,
        @"YTKACE.Preference.Downloads.AudioFormat": @1,
        @"YTKACE.Preference.Downloads.AlwaysAsk": @NO,
        @"YTKACE.Preference.Downloads.AutoImport": @NO,
        @"YTKACE.Preference.Playback.DefaultQuality": @1080,
        @"YTKACE.Preference.Playback.DefaultAudioQuality": @160,
        @"YTKACE.Preference.Playback.WiFiQuality": @0,
        @"YTKACE.Preference.Playback.CellularQuality": @0,
        @"YTKACE.Preference.Playback.AutoDismissPausedPrompt": @YES,
        @"YTKACE.Preference.App.HapticsEnabled": @YES,
        @"YTKACE.Preference.Gestures.HoldSpeedMultiplier": @1,
        @"YTKACE.Preference.SponsorBlock.Mode": @0,
        @"YTKACE.Preference.SponsorBlock.SkipAlertSeconds": @4.0,
        @"YTKACE.Preference.SponsorBlock.UnskipAlertSeconds": @4.0,
        @"YTKACE.Preference.Downloads.ClearOnStartup": @NO,
        YTKACEAccentPresetKey: @0,
        YTKACEAccentHexKey: @"#FF0033",
        YTKACEThemePresetKey: @0,
        YTKACEThemeTopHexKey: @"#000000",
        YTKACEThemeBottomHexKey: @"#36020A",
        YTKACEForce120HzKey: @YES,
        YTKACELockAV1Key: @NO,
        YTKACEPreferredCodecKey: @0,
        @"YTKACE.Preference.Tabs.Hidden.Create": @YES,
        @"YTKACE.Preference.Tabs.Hidden.Music": @YES,
        @"YTKACE.Preference.Tabs.Hidden.Live": @YES,
        @"YTKACE.Preference.Tabs.Hidden.Gaming": @YES,
        @"YTKACE.Preference.Tabs.Hidden.News": @YES,
        @"YTKACE.Preference.Tabs.Hidden.Sports": @YES,
        @"YTKACE.Preference.Tabs.Hidden.Learning": @YES,
        @"YTKACE.Preference.Tabs.Hidden.Fashion": @YES,
        @"YTKACE.Preference.Tabs.Hidden.Playlists": @YES,
        @"YTKACE.Preference.Tabs.Hidden.History": @YES,
        @"YTKACE.Preference.Tabs.Hidden.Notifs": @YES,
        @"YTKACE.Preference.Tabs.Hidden.WatchLater": @YES,
        @"YTKACE.Preference.Tabs.Order": @[@"home", @"shorts", @"subscriptions", @"library", @"ytkace"]
    };
    [YTKACEDefaults() registerDefaults:defaultDict];
    os_unfair_lock_lock(&s_prefLock);
    if (s_prefCache == nil) {
        s_prefCache = [defaultDict mutableCopy];
    }
    os_unfair_lock_unlock(&s_prefLock);
    if ((!hasLeftAction || !hasRightAction) &&
        (legacyBrightnessSide != nil || legacyVolumeSide != nil)) {
        NSInteger brightness = legacyBrightnessSide != nil
            ? [legacyBrightnessSide integerValue] : 2;
        NSInteger volume = legacyVolumeSide != nil
            ? [legacyVolumeSide integerValue] : 2;
        BOOL leftBrightness = brightness == 1;
        BOOL rightBrightness = brightness == 0;
        BOOL leftVolume = volume == 1 || volume == 3;
        BOOL rightVolume = volume == 0 || volume == 3;
        NSInteger leftAction = leftBrightness && leftVolume
            ? 3 : (leftVolume ? 2 : (leftBrightness ? 1 : 0));
        NSInteger rightAction = rightBrightness && rightVolume
            ? 3 : (rightVolume ? 2 : (rightBrightness ? 1 : 0));
        if (!hasLeftAction) {
            [YTKACEDefaults() setInteger:leftAction
                                  forKey:@"YTKACE.Preference.Gestures.LeftAction"];
        }
        if (!hasRightAction) {
            [YTKACEDefaults() setInteger:rightAction
                                   forKey:@"YTKACE.Preference.Gestures.RightAction"];
        }
    }
    [YTKACEDefaults() setBool:YES forKey:YTKACEMasterEnabledKey];
    if ([YTKACEDefaults() objectForKey:@"YTKACE.Preference.Shorts.ProductsHidden"] != nil) {
        if ([YTKACEDefaults() boolForKey:@"YTKACE.Preference.Shorts.ProductsHidden"]) {
            [YTKACEDefaults() setBool:YES
                               forKey:@"YTKACE.Preference.Overlay.ProductsHidden"];
        }
        [YTKACEDefaults() removeObjectForKey:@"YTKACE.Preference.Shorts.ProductsHidden"];
    }
    if ([YTKACEDefaults() boolForKey:@"YTKACE.Preference.Downloads.ClearOnStartup"]) {
        NSDate *lastClear = [YTKACEDefaults() objectForKey:@"YTKACE.Preference.Downloads.LastCacheClear"];
        if (![lastClear isKindOfClass:NSDate.class] ||
            -lastClear.timeIntervalSinceNow >= 86400.0) {
            NSURL *cache = [YTKACEApplicationSupportDirectory()
                URLByAppendingPathComponent:@"Cache"
                                isDirectory:YES];
            [NSFileManager.defaultManager removeItemAtURL:cache error:nil];
            [YTKACEDefaults() setObject:NSDate.date
                                 forKey:@"YTKACE.Preference.Downloads.LastCacheClear"];
        }
    }
    YTKACEPurgeDownloadScratch(NO);
}

BOOL YTKACEMasterEnabled(void) {
    return YES;
}

BOOL YTKACEFeatureEnabled(NSString *key) {
    if (!YTKACEMasterEnabled() || key.length == 0) {
        return NO;
    }
    os_unfair_lock_lock(&s_prefLock);
    NSNumber *cached = s_prefCache != nil ? s_prefCache[key] : nil;
    os_unfair_lock_unlock(&s_prefLock);
    if (cached != nil) {
        return cached.boolValue;
    }
    BOOL val = [YTKACEDefaults() boolForKey:key];
    os_unfair_lock_lock(&s_prefLock);
    if (s_prefCache == nil) s_prefCache = [NSMutableDictionary dictionary];
    s_prefCache[key] = @(val);
    os_unfair_lock_unlock(&s_prefLock);
    return val;
}

BOOL YTKACEOLEDActive(UITraitCollection *traits) {
    if (!YTKACEFeatureEnabled(YTKACEOLEDKey)) {
        return NO;
    }
    UITraitCollection *current = traits;
    if (current == nil) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class] ||
                scene.activationState != UISceneActivationStateForegroundActive) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                if (window.isKeyWindow) {
                    current = window.traitCollection;
                    break;
                }
            }
            if (current != nil) break;
        }
    }
    current = current ?: UIScreen.mainScreen.traitCollection;
    return current.userInterfaceStyle == UIUserInterfaceStyleDark;
}

UIColor *YTKACEColorFromHex(NSString *hex, UIColor *fallback) {
    if (hex.length == 0) return fallback ?: UIColor.blackColor;
    NSString *clean = [[hex stringByReplacingOccurrencesOfString:@"#" withString:@""] uppercaseString];
    if (clean.length == 6) {
        unsigned int rgb = 0;
        [[NSScanner scannerWithString:clean] scanHexInt:&rgb];
        return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                               green:((rgb >> 8) & 0xFF) / 255.0
                                blue:(rgb & 0xFF) / 255.0
                               alpha:1.0];
    }
    return fallback ?: UIColor.blackColor;
}

UIColor *YTKACEThemeTopColor(void) {
    NSInteger preset = [YTKACEDefaults() integerForKey:YTKACEThemePresetKey];
    switch (preset) {
        case 1: return [UIColor colorWithRed:0.02 green:0.0 blue:0.01 alpha:1.0]; // Midnight Crimson Top
        case 2: return [UIColor colorWithRed:0.02 green:0.02 blue:0.07 alpha:1.0]; // Cyberpunk Neon Top
        case 3: return [UIColor colorWithRed:0.005 green:0.04 blue:0.02 alpha:1.0]; // Emerald Abyss Top
        case 4: return [UIColor colorWithRed:0.04 green:0.02 blue:0.005 alpha:1.0]; // Sunset Ember Top
        case 5: return [UIColor colorWithRed:0.03 green:0.005 blue:0.06 alpha:1.0]; // Nebula Violet Top
        case 6: return [UIColor colorWithRed:0.005 green:0.025 blue:0.07 alpha:1.0]; // Deep Ocean Blue Top
        case 7: {
            NSString *hex = [YTKACEDefaults() stringForKey:YTKACEThemeTopHexKey];
            return YTKACEColorFromHex(hex, UIColor.blackColor);
        }
        default: return UIColor.blackColor; // OLED Pure Black
    }
}

UIColor *YTKACEThemeBottomColor(void) {
    NSInteger preset = [YTKACEDefaults() integerForKey:YTKACEThemePresetKey];
    switch (preset) {
        case 1: return [UIColor colorWithRed:0.22 green:0.01 blue:0.04 alpha:1.0]; // Velvet Crimson
        case 2: return [UIColor colorWithRed:0.16 green:0.02 blue:0.25 alpha:1.0]; // Electric Purple
        case 3: return [UIColor colorWithRed:0.01 green:0.18 blue:0.08 alpha:1.0]; // Forest Emerald
        case 4: return [UIColor colorWithRed:0.23 green:0.07 blue:0.01 alpha:1.0]; // Sunset Amber
        case 5: return [UIColor colorWithRed:0.15 green:0.01 blue:0.24 alpha:1.0]; // Nebula Violet
        case 6: return [UIColor colorWithRed:0.01 green:0.12 blue:0.27 alpha:1.0]; // Abyss Navy
        case 7: {
            NSString *hex = [YTKACEDefaults() stringForKey:YTKACEThemeBottomHexKey];
            return YTKACEColorFromHex(hex, [UIColor colorWithRed:0.22 green:0.01 blue:0.04 alpha:1.0]);
        }
        default: return UIColor.blackColor; // OLED Pure Black
    }
}

UIColor *YTKACEThemeBackgroundColor(UITraitCollection *traits) {
    if (!YTKACEOLEDActive(traits)) {
        return YTKACEInterfaceBackgroundColor(traits);
    }
    NSInteger preset = [YTKACEDefaults() integerForKey:YTKACEThemePresetKey];
    switch (preset) {
        case 1: return [UIColor colorWithRed:0.07 green:0.005 blue:0.015 alpha:1.0]; // Crimson Base
        case 2: return [UIColor colorWithRed:0.04 green:0.02 blue:0.11 alpha:1.0]; // Cyberpunk Base
        case 3: return [UIColor colorWithRed:0.01 green:0.08 blue:0.04 alpha:1.0]; // Emerald Base
        case 4: return [UIColor colorWithRed:0.08 green:0.03 blue:0.01 alpha:1.0]; // Sunset Base
        case 5: return [UIColor colorWithRed:0.06 green:0.01 blue:0.10 alpha:1.0]; // Nebula Base
        case 6: return [UIColor colorWithRed:0.01 green:0.05 blue:0.12 alpha:1.0]; // Ocean Base
        case 7: {
            UIColor *top = YTKACEThemeTopColor();
            UIColor *bottom = YTKACEThemeBottomColor();
            CGFloat r1, g1, b1, a1, r2, g2, b2, a2;
            if ([top getRed:&r1 green:&g1 blue:&b1 alpha:&a1] && [bottom getRed:&r2 green:&g2 blue:&b2 alpha:&a2]) {
                return [UIColor colorWithRed:(r1 + r2) * 0.5 green:(g1 + g2) * 0.5 blue:(b1 + b2) * 0.5 alpha:1.0];
            }
            return UIColor.blackColor;
        }
        default: return UIColor.blackColor;
    }
}

UIColor *YTKACEThemeSurfaceColor(UITraitCollection *traits) {
    if (!YTKACEOLEDActive(traits)) {
        return YTKACEInterfaceSurfaceColor(traits);
    }
    NSInteger preset = [YTKACEDefaults() integerForKey:YTKACEThemePresetKey];
    switch (preset) {
        case 1: return [UIColor colorWithRed:0.15 green:0.01 blue:0.04 alpha:1.0]; // Crimson Surface
        case 2: return [UIColor colorWithRed:0.11 green:0.03 blue:0.20 alpha:1.0]; // Cyberpunk Surface
        case 3: return [UIColor colorWithRed:0.02 green:0.13 blue:0.06 alpha:1.0]; // Emerald Surface
        case 4: return [UIColor colorWithRed:0.16 green:0.05 blue:0.02 alpha:1.0]; // Sunset Surface
        case 5: return [UIColor colorWithRed:0.12 green:0.02 blue:0.18 alpha:1.0]; // Nebula Surface
        case 6: return [UIColor colorWithRed:0.02 green:0.09 blue:0.20 alpha:1.0]; // Ocean Surface
        case 7: {
            UIColor *bg = YTKACEThemeBackgroundColor(traits);
            CGFloat r, g, b, a;
            if ([bg getRed:&r green:&g blue:&b alpha:&a]) {
                return [UIColor colorWithRed:MIN(1.0, r + 0.08) green:MIN(1.0, g + 0.08) blue:MIN(1.0, b + 0.08) alpha:1.0];
            }
            return [UIColor colorWithWhite:0.10 alpha:1.0];
        }
        default: return [UIColor colorWithWhite:0.06 alpha:1.0];
    }
}

static UIImage *s_cachedGradientImage = nil;
static CGSize s_cachedGradientSize = CGSizeZero;
static NSInteger s_cachedGradientPreset = -1;
static NSString *s_cachedTopHex = nil;
static NSString *s_cachedBottomHex = nil;

UIImage *YTKACEThemeGradientImage(CGSize size) {
    if (size.width <= 0 || size.height <= 0) return nil;
    NSInteger preset = [YTKACEDefaults() integerForKey:YTKACEThemePresetKey];
    if (preset == 0) return nil; // Pure black needs no gradient texture

    NSString *topHex = [YTKACEDefaults() stringForKey:YTKACEThemeTopHexKey] ?: @"";
    NSString *bottomHex = [YTKACEDefaults() stringForKey:YTKACEThemeBottomHexKey] ?: @"";

    if (s_cachedGradientImage != nil &&
        CGSizeEqualToSize(s_cachedGradientSize, size) &&
        s_cachedGradientPreset == preset &&
        [s_cachedTopHex isEqualToString:topHex] &&
        [s_cachedBottomHex isEqualToString:bottomHex]) {
        return s_cachedGradientImage;
    }

    UIColor *topColor = YTKACEThemeTopColor();
    UIColor *bottomColor = YTKACEThemeBottomColor();

    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = UIScreen.mainScreen.scale;
    format.opaque = YES;

    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull context) {
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        NSArray *colors = @[(__bridge id)topColor.CGColor, (__bridge id)bottomColor.CGColor];
        CGFloat locations[] = {0.0, 1.0};
        CGGradientRef gradient = CGGradientCreateWithColors(colorSpace, (__bridge CFArrayRef)colors, locations);

        CGContextDrawLinearGradient(context.CGContext, gradient, CGPointMake(0, 0), CGPointMake(0, size.height), 0);

        CGGradientRelease(gradient);
        CGColorSpaceRelease(colorSpace);
    }];

    s_cachedGradientImage = image;
    s_cachedGradientSize = size;
    s_cachedGradientPreset = preset;
    s_cachedTopHex = topHex;
    s_cachedBottomHex = bottomHex;

    return image;
}

UIColor *YTKACEInterfaceBackgroundColor(UITraitCollection *traits) {
    if (YTKACEOLEDActive(traits)) return YTKACEThemeBackgroundColor(traits);
    UIUserInterfaceStyle style = traits.userInterfaceStyle;
    if (style == UIUserInterfaceStyleUnspecified) {
        style = UIScreen.mainScreen.traitCollection.userInterfaceStyle;
    }
    return style == UIUserInterfaceStyleDark
        ? [UIColor colorWithWhite:0.075 alpha:1.0]
        : UIColor.whiteColor;
}

UIColor *YTKACEInterfaceSurfaceColor(UITraitCollection *traits) {
    if (YTKACEOLEDActive(traits)) {
        return YTKACEThemeSurfaceColor(traits);
    }
    UIUserInterfaceStyle style = traits.userInterfaceStyle;
    if (style == UIUserInterfaceStyleUnspecified) {
        style = UIScreen.mainScreen.traitCollection.userInterfaceStyle;
    }
    return style == UIUserInterfaceStyleDark
        ? [UIColor colorWithWhite:0.16 alpha:1.0]
        : [UIColor colorWithWhite:0.95 alpha:1.0];
}

UIColor *YTKACEAppAccentColor(void) {
    NSInteger preset = [YTKACEDefaults() integerForKey:YTKACEAccentPresetKey];
    switch (preset) {
        case 1: return [UIColor colorWithRed:0.0 green:0.533 blue:1.0 alpha:1.0]; // Neon Blue
        case 2: return [UIColor colorWithRed:0.60 green:0.20 blue:1.0 alpha:1.0]; // Purple
        case 3: return [UIColor colorWithRed:0.0 green:0.80 blue:0.40 alpha:1.0]; // Green
        case 4: return [UIColor colorWithRed:1.0 green:0.40 blue:0.0 alpha:1.0]; // Orange
        case 5: return [UIColor colorWithRed:1.0 green:0.20 blue:0.533 alpha:1.0]; // Pink
        case 6: return [UIColor colorWithRed:0.90 green:0.0 blue:0.0 alpha:1.0]; // Crimson
        case 7: return [UIColor colorWithWhite:0.95 alpha:1.0]; // White
        case 8: {
            NSString *hex = [YTKACEDefaults() stringForKey:YTKACEAccentHexKey];
            return YTKACEColorFromHex(hex, [UIColor colorWithRed:0.749 green:0.0 blue:0.075 alpha:1.0]);
        }
        default: break;
    }
    return [UIColor colorWithRed:0.749 green:0.0 blue:0.075 alpha:1.0];
}

BOOL YTKACESponsorBlockEnabled(void) {
    if (!YTKACEMasterEnabled()) {
        return NO;
    }

    return [YTKACEDefaults() boolForKey:YTKACESponsorBlockKey];
}

void YTKACESetPreference(NSString *key, BOOL enabled) {
    if (key.length == 0) {
        return;
    }
    os_unfair_lock_lock(&s_prefLock);
    if (s_prefCache == nil) s_prefCache = [NSMutableDictionary dictionary];
    s_prefCache[key] = @(enabled);
    os_unfair_lock_unlock(&s_prefLock);

    if ([key isEqualToString:YTKACEMasterEnabledKey]) {
        [YTKACEDefaults() setBool:YES forKey:key];
        YTKACEAnnouncePreferenceChange(key);
        return;
    }
    [YTKACEDefaults() setBool:enabled forKey:key];
    YTKACEAnnouncePreferenceChange(key);
}

id YTKACEPreferenceObject(NSString *key) {
    if (key.length == 0) {
        return nil;
    }
    os_unfair_lock_lock(&s_prefLock);
    id cached = s_prefCache != nil ? s_prefCache[key] : nil;
    os_unfair_lock_unlock(&s_prefLock);
    if (cached != nil) {
        return cached;
    }
    id val = [YTKACEDefaults() objectForKey:key];
    if (val != nil) {
        os_unfair_lock_lock(&s_prefLock);
        if (s_prefCache == nil) s_prefCache = [NSMutableDictionary dictionary];
        s_prefCache[key] = val;
        os_unfair_lock_unlock(&s_prefLock);
    }
    return val;
}

void YTKACESetPreferenceObject(NSString *key, id value) {
    if (key.length == 0) {
        return;
    }
    os_unfair_lock_lock(&s_prefLock);
    if (s_prefCache == nil) s_prefCache = [NSMutableDictionary dictionary];
    if (value == nil) {
        [s_prefCache removeObjectForKey:key];
    } else {
        s_prefCache[key] = value;
    }
    os_unfair_lock_unlock(&s_prefLock);

    if (value == nil) {
        [YTKACEDefaults() removeObjectForKey:key];
    } else {
        [YTKACEDefaults() setObject:value forKey:key];
    }
    YTKACEAnnouncePreferenceChange(key);
}

static NSString *YTKACERelativeStoragePath(NSURL *URL, NSURL *baseURL) {
    NSString *path = URL.URLByResolvingSymlinksInPath.path.stringByStandardizingPath;
    NSString *base = baseURL.URLByResolvingSymlinksInPath.path.stringByStandardizingPath;
    NSString *prefix = [base stringByAppendingString:@"/"];
    if (![path hasPrefix:prefix]) return nil;
    return [path substringFromIndex:prefix.length];
}

static void YTKACERepairDownloads(NSURL *root) {
    NSFileManager *manager = NSFileManager.defaultManager;
    NSURL *downloads = [root URLByAppendingPathComponent:@"Downloads" isDirectory:YES];
    NSArray<NSURL *> *items = [[manager enumeratorAtURL:downloads
        includingPropertiesForKeys:@[NSURLIsDirectoryKey]
                           options:0 errorHandler:nil] allObjects];
    for (NSURL *source in items) {
        NSNumber *directory = nil;
        [source getResourceValue:&directory forKey:NSURLIsDirectoryKey error:nil];
        if (directory.boolValue) continue;
        NSString *relative = YTKACERelativeStoragePath(source, downloads);
        NSArray<NSString *> *components = relative.pathComponents;
        NSUInteger categoryIndex = NSNotFound;
        NSString *category = nil;
        for (NSUInteger index = 0; index < components.count; index++) {
            for (NSString *candidate in @[@"Video", @"Audio", @"Shorts"]) {
                if ([components[index] caseInsensitiveCompare:candidate] == NSOrderedSame) {
                    categoryIndex = index;
                    category = candidate;
                    break;
                }
            }
            if (categoryIndex != NSNotFound) break;
        }
        if (categoryIndex == NSNotFound || categoryIndex + 1 >= components.count) continue;
        NSURL *target = [downloads URLByAppendingPathComponent:category isDirectory:YES];
        for (NSUInteger index = categoryIndex + 1; index < components.count; index++) {
            target = [target URLByAppendingPathComponent:components[index]];
        }
        if ([source.URLByResolvingSymlinksInPath.path
                isEqualToString:target.URLByResolvingSymlinksInPath.path]) continue;
        [manager createDirectoryAtURL:target.URLByDeletingLastPathComponent
          withIntermediateDirectories:YES attributes:nil error:nil];
        if ([manager fileExistsAtPath:target.path]) {
            [manager removeItemAtURL:source error:nil];
        } else {
            [manager moveItemAtURL:source toURL:target error:nil];
        }
    }
    for (NSString *name in @[@"Downloads", @"ownloads"]) {
        [manager removeItemAtURL:[downloads URLByAppendingPathComponent:name isDirectory:YES]
                           error:nil];
    }
}

NSURL *YTKACEApplicationSupportDirectory(void) {
    NSFileManager *manager = NSFileManager.defaultManager;
    NSURL *documents = [manager URLsForDirectory:NSDocumentDirectory
                                        inDomains:NSUserDomainMask].firstObject;
    NSURL *directory = [documents URLByAppendingPathComponent:@"YTKACE"
                                                   isDirectory:YES];
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSURL *support = [manager URLsForDirectory:NSApplicationSupportDirectory
                                         inDomains:NSUserDomainMask].firstObject;
        NSURL *legacy = [support URLByAppendingPathComponent:@"YTKACE"
                                                  isDirectory:YES];
        BOOL targetExists = [manager fileExistsAtPath:directory.path];
        if (!targetExists && [manager fileExistsAtPath:legacy.path]) {
            [manager moveItemAtURL:legacy toURL:directory error:nil];
        }
        [manager createDirectoryAtURL:directory
          withIntermediateDirectories:YES
                           attributes:nil
                                error:nil];
        if ([manager fileExistsAtPath:legacy.path]) {
            NSDirectoryEnumerator<NSURL *> *items = [manager
                enumeratorAtURL:legacy
     includingPropertiesForKeys:@[NSURLIsDirectoryKey]
                        options:0
                   errorHandler:nil];
            for (NSURL *source in items) {
                NSString *relative = YTKACERelativeStoragePath(source, legacy);
                if (relative.length == 0) continue;
                NSURL *destination = [directory URLByAppendingPathComponent:relative];
                NSNumber *isDirectory = nil;
                [source getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
                if (isDirectory.boolValue) {
                    [manager createDirectoryAtURL:destination
                      withIntermediateDirectories:YES attributes:nil error:nil];
                } else if (![manager fileExistsAtPath:destination.path]) {
                    [manager createDirectoryAtURL:destination.URLByDeletingLastPathComponent
                      withIntermediateDirectories:YES attributes:nil error:nil];
                    [manager moveItemAtURL:source toURL:destination error:nil];
                }
            }
            [manager removeItemAtURL:legacy error:nil];
        }
        YTKACERepairDownloads(directory);
    });
    return directory;
}
