#import "Localization.h"
#import "Preferences.h"
#import "../UI/Assets.h"

#import <UIKit/UIKit.h>
#import <os/lock.h>

NSString * const YTKACELanguageKey = @"YTKACE.Preference.Language";

static os_unfair_lock s_localeLock = OS_UNFAIR_LOCK_INIT;
static NSDictionary<NSString *, NSString *> *s_activeStrings = nil;
static NSDictionary<NSString *, NSString *> *s_fallbackStrings = nil;
static NSString *s_activeLanguage = nil;

NSArray<NSString *> *YTKACEAvailableLanguages(void) {
    return @[@"system", @"en", @"ar", @"ckb", @"de", @"es", @"fr", @"it",
             @"ja", @"ko", @"pl", @"ru", @"tr", @"vi", @"zh-Hans", @"zh-Hant"];
}

NSString *YTKACELanguageDisplayName(NSString *code) {
    if ([code isEqualToString:@"system"]) return @"System";
    static NSDictionary<NSString *, NSString *> *names;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        names = @{
            @"en": @"English",
            @"ar": @"العربية",
            @"ckb": @"کوردی",
            @"de": @"Deutsch",
            @"es": @"Español",
            @"fr": @"Français",
            @"it": @"Italiano",
            @"ja": @"日本語",
            @"ko": @"한국어",
            @"pl": @"Polski",
            @"ru": @"Русский",
            @"tr": @"Türkçe",
            @"vi": @"Tiếng Việt",
            @"zh-Hans": @"简体中文",
            @"zh-Hant": @"繁體中文"
        };
    });
    return names[code] ?: code;
}

static NSString *YTKACEDetectSystemLanguage(void) {
    NSArray<NSString *> *available = YTKACEAvailableLanguages();
    for (NSString *preferred in NSLocale.preferredLanguages) {
        NSString *code = preferred;
        if ([code hasPrefix:@"zh-Hans"] || [code hasPrefix:@"zh-CN"] ||
            [code hasPrefix:@"zh-SG"]) {
            return @"zh-Hans";
        }
        if ([code hasPrefix:@"zh"]) return @"zh-Hant";
        NSRange separator = [code rangeOfString:@"-"];
        if (separator.location != NSNotFound) {
            code = [code substringToIndex:separator.location];
        }
        if ([available containsObject:code]) return code;
    }
    return @"en";
}

static NSString *YTKACEPreferredLanguage(void) {
    id stored = YTKACEPreferenceObject(YTKACELanguageKey);
    NSString *choice = [stored isKindOfClass:NSString.class] ? stored : @"system";
    if (![choice isEqualToString:@"system"]) return choice;
    return YTKACEDetectSystemLanguage();
}

static NSDictionary<NSString *, NSString *> *YTKACEStringsForLanguage(NSString *code) {
    if (code.length == 0) return nil;
    NSBundle *bundle = YTKACEAssetsBundle();
    if (bundle == nil) return nil;
    NSString *path = [bundle pathForResource:@"Localizable"
                                      ofType:@"strings"
                                 inDirectory:nil
                             forLocalization:code];
    if (path == nil) {
        path = [bundle.resourcePath stringByAppendingPathComponent:
            [NSString stringWithFormat:@"%@.lproj/Localizable.strings", code]];
    }
    return [NSDictionary dictionaryWithContentsOfFile:path];
}

void YTKACEResetLocalizationCache(void) {
    os_unfair_lock_lock(&s_localeLock);
    s_activeStrings = nil;
    s_fallbackStrings = nil;
    s_activeLanguage = nil;
    os_unfair_lock_unlock(&s_localeLock);
}

static void YTKACEEnsureLocalizationLoaded(void) {
    NSString *language = YTKACEPreferredLanguage();
    if (s_activeStrings != nil && [language isEqualToString:s_activeLanguage]) {
        return;
    }
    NSDictionary<NSString *, NSString *> *strings = YTKACEStringsForLanguage(language);
    NSDictionary<NSString *, NSString *> *fallback = nil;
    if (![language isEqualToString:@"en"]) {
        fallback = YTKACEStringsForLanguage(@"en");
    }
    s_activeLanguage = [language copy];
    s_activeStrings = strings ?: @{};
    s_fallbackStrings = fallback ?: @{};
}

NSString *YTKACELocalized(NSString *key) {
    if (key.length == 0) return key;

    os_unfair_lock_lock(&s_localeLock);
    if (s_activeStrings == nil) {
        YTKACEEnsureLocalizationLoaded();
    }
    NSString *value = s_activeStrings[key];
    if (value.length == 0 && s_fallbackStrings != nil) {
        value = s_fallbackStrings[key];
    }
    os_unfair_lock_unlock(&s_localeLock);

    return value.length != 0 ? value : key;
}
