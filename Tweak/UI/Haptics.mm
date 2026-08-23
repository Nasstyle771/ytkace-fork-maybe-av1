#import "Haptics.h"
#import "../Runtime/Preferences.h"

void YTKACEHapticImpact(UIImpactFeedbackStyle style) {
    if (!YTKACEFeatureEnabled(@"YTKACE.Preference.App.HapticsEnabled")) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:style];
        [gen prepare];
        [gen impactOccurred];
    });
}

void YTKACEHapticSelection(void) {
    if (!YTKACEFeatureEnabled(@"YTKACE.Preference.App.HapticsEnabled")) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        UISelectionFeedbackGenerator *gen = [UISelectionFeedbackGenerator new];
        [gen prepare];
        [gen selectionChanged];
    });
}

void YTKACEHapticNotification(UINotificationFeedbackType type) {
    if (!YTKACEFeatureEnabled(@"YTKACE.Preference.App.HapticsEnabled")) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        UINotificationFeedbackGenerator *gen = [UINotificationFeedbackGenerator new];
        [gen prepare];
        [gen notificationOccurred:type];
    });
}
