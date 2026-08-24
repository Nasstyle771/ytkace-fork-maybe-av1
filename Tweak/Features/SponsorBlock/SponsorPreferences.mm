#import "SponsorPreferences.h"
#import "../../Runtime/Preferences.h"
#import "../../Runtime/Localization.h"
#import <os/lock.h>

static os_unfair_lock sSponsorPrefLock = OS_UNFAIR_LOCK_INIT;
static NSMutableDictionary<NSString *, NSNumber *> *sBehaviorCache = nil;
static NSMutableDictionary<NSString *, UIColor *> *sColorCache = nil;
static NSArray<NSString *> *sEnabledCategoriesCache = nil;
static NSInteger sNotificationModeCache = -1;
static NSTimeInterval sSkipAlertDurationCache = -1.0;
static NSTimeInterval sUnskipAlertDurationCache = -1.0;

static void YTKACESponsorFlushPreferenceCaches(void) {
    os_unfair_lock_lock(&sSponsorPrefLock);
    [sBehaviorCache removeAllObjects];
    [sColorCache removeAllObjects];
    sEnabledCategoriesCache = nil;
    sNotificationModeCache = -1;
    sSkipAlertDurationCache = -1.0;
    sUnskipAlertDurationCache = -1.0;
    os_unfair_lock_unlock(&sSponsorPrefLock);
}

static void YTKACESponsorEnsurePrefObserver(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sBehaviorCache = [NSMutableDictionary dictionary];
        sColorCache = [NSMutableDictionary dictionary];
        [NSNotificationCenter.defaultCenter
            addObserverForName:YTKACEPreferencesDidChangeNotification
                        object:nil
                         queue:nil
                    usingBlock:^(__unused NSNotification *note) {
            YTKACESponsorFlushPreferenceCaches();
        }];
    });
}

NSArray<NSDictionary<NSString *, NSString *> *> *YTKACESponsorCategoryDefinitions(void) {
    static NSArray *definitions;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        definitions = @[
            @{@"id": @"sponsor", @"title": YTKACELocalized(@"Sponsor"), @"color": @"#00D400"},
            @{@"id": @"selfpromo", @"title": YTKACELocalized(@"Self Promotion"), @"color": @"#FFFF00"},
            @{@"id": @"interaction", @"title": YTKACELocalized(@"Interaction Reminder"), @"color": @"#CC00FF"},
            @{@"id": @"intro", @"title": YTKACELocalized(@"Intermission / Intro"), @"color": @"#00FFFF"},
            @{@"id": @"outro", @"title": YTKACELocalized(@"Endcards / Credits"), @"color": @"#0202ED"},
            @{@"id": @"preview", @"title": YTKACELocalized(@"Preview / Recap"), @"color": @"#008FD6"},
            @{@"id": @"music_offtopic", @"title": YTKACELocalized(@"Non-Music Section"), @"color": @"#FF9900"},
            @{@"id": @"filler", @"title": YTKACELocalized(@"Filler"), @"color": @"#7300FF"},
            @{@"id": @"poi_highlight", @"title": YTKACELocalized(@"Highlight"), @"color": @"#FF1684"}
        ];
    });
    return definitions;
}

NSString *YTKACESponsorBehaviorKey(NSString *category) {
    return [@"YTKACE.Preference.SponsorBlock.Behavior."
        stringByAppendingString:category ?: @""];
}

NSString *YTKACESponsorColorKey(NSString *category) {
    return [@"YTKACE.Preference.SponsorBlock.Color."
        stringByAppendingString:category ?: @""];
}

static NSDictionary<NSString *, NSString *> *YTKACESponsorDefinition(NSString *category) {
    for (NSDictionary *definition in YTKACESponsorCategoryDefinitions()) {
        if ([definition[@"id"] isEqualToString:category]) return definition;
    }
    return nil;
}

NSInteger YTKACESponsorCategoryBehavior(NSString *category) {
    if (category.length == 0) return 2;
    YTKACESponsorEnsurePrefObserver();
    
    os_unfair_lock_lock(&sSponsorPrefLock);
    NSNumber *cached = sBehaviorCache[category];
    os_unfair_lock_unlock(&sSponsorPrefLock);
    if (cached != nil) {
        return cached.integerValue;
    }

    id stored = YTKACEPreferenceObject(YTKACESponsorBehaviorKey(category));
    NSInteger result = 2;
    if ([stored respondsToSelector:@selector(integerValue)]) {
        result = MAX(0, MIN([stored integerValue], 3));
    } else if ([category isEqualToString:@"sponsor"]) {
        id legacy = YTKACEPreferenceObject(@"YTKACE.Preference.SponsorBlock.Mode");
        result = [legacy respondsToSelector:@selector(integerValue)] &&
            [legacy integerValue] == 1 ? 1 : 0;
    }

    os_unfair_lock_lock(&sSponsorPrefLock);
    sBehaviorCache[category] = @(result);
    os_unfair_lock_unlock(&sSponsorPrefLock);
    return result;
}

NSArray<NSString *> *YTKACESponsorEnabledCategories(void) {
    YTKACESponsorEnsurePrefObserver();
    os_unfair_lock_lock(&sSponsorPrefLock);
    NSArray *cached = sEnabledCategoriesCache;
    os_unfair_lock_unlock(&sSponsorPrefLock);
    if (cached != nil) return cached;

    NSMutableArray *categories = [NSMutableArray array];
    for (NSDictionary *definition in YTKACESponsorCategoryDefinitions()) {
        NSString *category = definition[@"id"];
        if (YTKACESponsorCategoryBehavior(category) != 2) {
            [categories addObject:category];
        }
    }
    NSArray *result = [categories copy];
    os_unfair_lock_lock(&sSponsorPrefLock);
    sEnabledCategoriesCache = result;
    os_unfair_lock_unlock(&sSponsorPrefLock);
    return result;
}

static UIColor *YTKACEColorFromHex(NSString *hex) {
    NSString *value = [[hex ?: @"" stringByReplacingOccurrencesOfString:@"#"
                                                              withString:@""] uppercaseString];
    if (value.length != 6) return UIColor.systemGreenColor;
    unsigned int rgb = 0;
    [[NSScanner scannerWithString:value] scanHexInt:&rgb];
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0
                           alpha:1.0];
}

UIColor *YTKACESponsorCategoryColor(NSString *category) {
    if (category.length == 0) return UIColor.systemGreenColor;
    YTKACESponsorEnsurePrefObserver();

    os_unfair_lock_lock(&sSponsorPrefLock);
    UIColor *cached = sColorCache[category];
    os_unfair_lock_unlock(&sSponsorPrefLock);
    if (cached != nil) return cached;

    NSDictionary *definition = YTKACESponsorDefinition(category);
    NSString *stored = YTKACEPreferenceObject(YTKACESponsorColorKey(category));
    NSString *hex = [stored isKindOfClass:NSString.class] && stored.length != 0
        ? stored : definition[@"color"];
    UIColor *color = YTKACEColorFromHex(hex);

    os_unfair_lock_lock(&sSponsorPrefLock);
    if (color != nil) sColorCache[category] = color;
    os_unfair_lock_unlock(&sSponsorPrefLock);
    return color ?: UIColor.systemGreenColor;
}

NSInteger YTKACESponsorNotificationMode(void) {
    YTKACESponsorEnsurePrefObserver();
    if (sNotificationModeCache >= 0) return sNotificationModeCache;
    id stored = YTKACEPreferenceObject(@"YTKACE.Preference.SponsorBlock.NotificationMode");
    NSInteger mode = [stored respondsToSelector:@selector(integerValue)]
        ? MAX(0, MIN([stored integerValue], 2)) : 0;
    sNotificationModeCache = mode;
    return mode;
}

static NSTimeInterval YTKACESponsorDuration(NSString *key) {
    id stored = YTKACEPreferenceObject(key);
    double value = [stored respondsToSelector:@selector(doubleValue)]
        ? [stored doubleValue] : 4.0;
    return MAX(1.0, MIN(value, 10.0));
}

NSTimeInterval YTKACESponsorSkipAlertDuration(void) {
    if (sSkipAlertDurationCache >= 0.0) return sSkipAlertDurationCache;
    sSkipAlertDurationCache = YTKACESponsorDuration(@"YTKACE.Preference.SponsorBlock.SkipAlertSeconds");
    return sSkipAlertDurationCache;
}

NSTimeInterval YTKACESponsorUnskipAlertDuration(void) {
    if (sUnskipAlertDurationCache >= 0.0) return sUnskipAlertDurationCache;
    sUnskipAlertDurationCache = YTKACESponsorDuration(@"YTKACE.Preference.SponsorBlock.UnskipAlertSeconds");
    return sUnskipAlertDurationCache;
}
