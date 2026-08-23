#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@class UIColor, UIImage, UITraitCollection;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const YTKACEMasterEnabledKey;
FOUNDATION_EXPORT NSString * const YTKACEOLEDKey;
FOUNDATION_EXPORT NSString * const YTKACENoAdsKey;
FOUNDATION_EXPORT NSString * const YTKACESponsorBlockKey;
FOUNDATION_EXPORT NSString * const YTKACEDownloadKey;
FOUNDATION_EXPORT NSString * const YTKACEBackgroundPlaybackKey;
FOUNDATION_EXPORT NSString * const YTKACEPiPKey;
FOUNDATION_EXPORT NSString * const YTKACESpeedKey;
FOUNDATION_EXPORT NSString * const YTKACELoopKey;
FOUNDATION_EXPORT NSString * const YTKACESleepTimerKey;
FOUNDATION_EXPORT NSString * const YTKACEAccentPresetKey;
FOUNDATION_EXPORT NSString * const YTKACEAccentHexKey;
FOUNDATION_EXPORT NSString * const YTKACEThemePresetKey;
FOUNDATION_EXPORT NSString * const YTKACEThemeTopHexKey;
FOUNDATION_EXPORT NSString * const YTKACEThemeBottomHexKey;
FOUNDATION_EXPORT NSString * const YTKACEForce120HzKey;
FOUNDATION_EXPORT NSString * const YTKACELockAV1Key;
FOUNDATION_EXPORT NSString * const YTKACEPreferredCodecKey;
FOUNDATION_EXPORT NSString * const YTKACEPreferencesDidChangeNotification;

FOUNDATION_EXPORT void YTKACERegisterDefaults(void);
FOUNDATION_EXPORT BOOL YTKACEMasterEnabled(void);
FOUNDATION_EXPORT BOOL YTKACEFeatureEnabled(NSString *key);
FOUNDATION_EXPORT BOOL YTKACEOLEDActive(UITraitCollection * _Nullable traits);
FOUNDATION_EXPORT UIColor *YTKACEInterfaceBackgroundColor(
    UITraitCollection * _Nullable traits);
FOUNDATION_EXPORT UIColor *YTKACEInterfaceSurfaceColor(
    UITraitCollection * _Nullable traits);
FOUNDATION_EXPORT UIColor *YTKACEThemeTopColor(void);
FOUNDATION_EXPORT UIColor *YTKACEThemeBottomColor(void);
FOUNDATION_EXPORT UIColor *YTKACEThemeBackgroundColor(
    UITraitCollection * _Nullable traits);
FOUNDATION_EXPORT UIColor *YTKACEThemeSurfaceColor(
    UITraitCollection * _Nullable traits);
FOUNDATION_EXPORT UIImage * _Nullable YTKACEThemeGradientImage(CGSize size);
FOUNDATION_EXPORT UIColor *YTKACEAppAccentColor(void);
FOUNDATION_EXPORT UIColor *YTKACEColorFromHex(NSString *hex, UIColor * _Nullable fallback);
FOUNDATION_EXPORT BOOL YTKACESponsorBlockEnabled(void);
FOUNDATION_EXPORT void YTKACESetPreference(NSString *key, BOOL enabled);
FOUNDATION_EXPORT id _Nullable YTKACEPreferenceObject(NSString *key);
FOUNDATION_EXPORT void YTKACESetPreferenceObject(NSString *key, id _Nullable value);
FOUNDATION_EXPORT NSURL *YTKACEApplicationSupportDirectory(void);

NS_ASSUME_NONNULL_END
