#import "../../YTKACE.h"
#import "../../Runtime/Hooking.h"
#import "../../Runtime/Preferences.h"

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <math.h>
#import <objc/message.h>
#import <objc/runtime.h>

static NSString * const YTKACEProgressStyleKey = @"YTKACE.Preference.Progress.Style";
static NSString * const YTKACEProgressMainColorKey = @"YTKACE.Preference.Progress.MainColor";
static NSString * const YTKACEProgressGradientColorKey = @"YTKACE.Preference.Progress.HighlightColor";
static NSString * const YTKACEProgressScrubberColorKey = @"YTKACE.Preference.Progress.ScrubberColor";

static IMP OriginalDecorationViewColor;
static IMP OriginalDecorationControllerColor;
static IMP OriginalContainerQuietColor;
static IMP OriginalScrubberDotColorV1;
static IMP OriginalScrubberDotColorV2;
static IMP OriginalSetScrubberDotColor;
static IMP OriginalSetScrubberDotColorV1;
static IMP OriginalSetScrubberDotColorV2;

static UIColor *YTKACEProgressColorFromHex(NSString *hex, UIColor *fallback) {
    if (![hex isKindOfClass:NSString.class]) return fallback;
    NSString *value = [[hex stringByTrimmingCharactersInSet:
        NSCharacterSet.whitespaceAndNewlineCharacterSet]
        stringByReplacingOccurrencesOfString:@"#" withString:@""];
    if (value.length != 6) return fallback;
    unsigned int rgb = 0;
    if (![[NSScanner scannerWithString:value] scanHexInt:&rgb]) return fallback;
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0
                           alpha:1.0];
}

static NSInteger YTKACEStyleCache = -1;
static NSMutableDictionary<NSString *, UIColor *> *YTKACEPatternCache = nil;
static NSMutableDictionary<NSString *, UIImage *> *YTKACEStripCache = nil;
static NSMutableDictionary<NSString *, UIColor *> *YTKACEColorCache = nil;
static NSUInteger YTKACEProgressGeneration = 0;
static NSUInteger YTKACECachedGeneration = NSUIntegerMax;

static void YTKACERelayoutBars(UIView *view, NSUInteger depth) {
    if (view == nil || depth > 14) return;
    NSString *name = NSStringFromClass(view.class);
    if ([name containsString:@"PlayerBar"] ||
        [name containsString:@"MiniplayerProgressBar"] ||
        [name isEqualToString:@"YTBrandGradientView"] ||
        [name isEqualToString:@"YTGridVideoCell"]) {
        [view setNeedsLayout];
        [view setNeedsDisplay];
    }
    for (UIView *subview in view.subviews) {
        YTKACERelayoutBars(subview, depth + 1);
    }
}

static void YTKACEProgressSyncGeneration(void) {
    static dispatch_once_t observerToken;
    dispatch_once(&observerToken, ^{
        [NSNotificationCenter.defaultCenter
            addObserverForName:YTKACEPreferencesDidChangeNotification
                        object:nil
                         queue:NSOperationQueue.mainQueue
                    usingBlock:^(NSNotification *note) {
            NSString *key = note.userInfo[@"key"];
            if (![key hasPrefix:@"YTKACE.Preference.Progress."]) return;
            YTKACEProgressGeneration++;
            for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
                if (![scene isKindOfClass:UIWindowScene.class]) continue;
                for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                    YTKACERelayoutBars(window, 0);
                }
            }
        }];
    });
    if (YTKACECachedGeneration == YTKACEProgressGeneration) return;
    YTKACECachedGeneration = YTKACEProgressGeneration;
    YTKACEStyleCache = -1;
    YTKACEColorCache = nil;
    YTKACEPatternCache = nil;
    YTKACEStripCache = nil;
}

static NSInteger YTKACEProgressStyle(void) {
    YTKACEProgressSyncGeneration();
    if (YTKACEStyleCache >= 0) return YTKACEStyleCache;
    id value = YTKACEPreferenceObject(YTKACEProgressStyleKey);
    YTKACEStyleCache =
        [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : 0;
    return YTKACEStyleCache;
}

static UIColor *YTKACEStoredColor(NSString *key, UIColor *fallback) {
    YTKACEProgressSyncGeneration();
    UIColor *hit = YTKACEColorCache[key];
    if (hit != nil) return hit;
    UIColor *value = YTKACEProgressColorFromHex(YTKACEPreferenceObject(key), fallback);
    if (YTKACEColorCache == nil) YTKACEColorCache = [NSMutableDictionary dictionary];
    if (value != nil) YTKACEColorCache[key] = value;
    return value;
}

static UIColor *YTKACEMainColor(void) {
    return YTKACEStoredColor(YTKACEProgressMainColorKey, UIColor.systemRedColor);
}

static UIColor *YTKACEPlayedColor(void) {
    UIColor *main = YTKACEMainColor();
    if (YTKACEProgressStyle() != 2) return main;
    UIColor *highlight = YTKACEStoredColor(YTKACEProgressGradientColorKey, main);
    static UIImage *cached = nil;
    static NSString *cachedKey = nil;
    NSString *key = [NSString stringWithFormat:@"%@|%@", main, highlight];
    if (cached == nil || ![key isEqualToString:cachedKey]) {
        CGSize size = CGSizeMake(CGRectGetWidth(UIScreen.mainScreen.bounds), 6.0);
        UIGraphicsImageRenderer *renderer =
            [[UIGraphicsImageRenderer alloc] initWithSize:size];
        cached = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
            CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
            NSArray *colors = @[(id)main.CGColor, (id)highlight.CGColor];
            CGFloat locations[] = {0.0, 1.0};
            CGGradientRef gradient = CGGradientCreateWithColors(
                space, (__bridge CFArrayRef)colors, locations);
            CGContextDrawLinearGradient(context.CGContext, gradient,
                                        CGPointZero, CGPointMake(size.width, 0.0), 0);
            CGGradientRelease(gradient);
            CGColorSpaceRelease(space);
        }];
        cachedKey = key;
    }
    return [UIColor colorWithPatternImage:cached];
}

static UIImage *YTKACEGradientStrip(CGFloat width, CGFloat height) {
    UIColor *main = YTKACEMainColor();
    UIColor *highlight = YTKACEStoredColor(YTKACEProgressGradientColorKey, main);
    NSString *stripKey = [NSString stringWithFormat:@"%.0f|%.0f|%@|%@",
                          width, height, main, highlight];
    UIImage *cachedStrip = YTKACEStripCache[stripKey];
    if (cachedStrip != nil) return cachedStrip;
    CGSize size = CGSizeMake(MAX(width, 1.0), MAX(height, 1.0));
    UIGraphicsImageRenderer *renderer =
        [[UIGraphicsImageRenderer alloc] initWithSize:size];
    UIImage *strip = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        NSArray *colors = @[(id)main.CGColor, (id)highlight.CGColor];
        CGFloat locations[] = {0.0, 1.0};
        CGGradientRef gradient = CGGradientCreateWithColors(
            space, (__bridge CFArrayRef)colors, locations);
        CGContextDrawLinearGradient(context.CGContext, gradient,
                                    CGPointZero, CGPointMake(size.width, 0.0), 0);
        CGGradientRelease(gradient);
        CGColorSpaceRelease(space);
    }];
    if (YTKACEStripCache == nil) YTKACEStripCache = [NSMutableDictionary dictionary];
    if (YTKACEStripCache.count > 24) [YTKACEStripCache removeAllObjects];
    YTKACEStripCache[stripKey] = strip;
    return strip;
}

UIImage *YTKACEProgressFillImage(CGFloat width, CGFloat height) {
    if (!isfinite(width) || width <= 0.0) width = 1.0;
    if (!isfinite(height) || height <= 0.0) height = 1.0;
    CGSize size = CGSizeMake(MAX(width, 1.0), MAX(height, 1.0));
    NSInteger style = YTKACEProgressStyle();
    UIColor *start = nil;
    UIColor *end = nil;
    if (style == 1) {
        start = YTKACEMainColor();
        end = start;
    } else if (style == 2) {
        start = YTKACEMainColor();
        end = YTKACEStoredColor(YTKACEProgressGradientColorKey, start);
    } else {
        start = [UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:1.0];
        end = [UIColor colorWithRed:1.0 green:0.29 blue:0.16 alpha:1.0];
    }
    NSString *key = [NSString stringWithFormat:@"fill|%.0f|%.0f|%ld|%@|%@",
                     size.width, size.height, (long)style, start, end];
    UIImage *cached = YTKACEStripCache[key];
    if (cached != nil) return cached;
    UIGraphicsImageRenderer *renderer =
        [[UIGraphicsImageRenderer alloc] initWithSize:size];
    UIImage *image = [renderer imageWithActions:
        ^(UIGraphicsImageRendererContext *context) {
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        NSArray *colors = @[(id)start.CGColor, (id)end.CGColor];
        CGFloat locations[] = {0.0, 1.0};
        CGGradientRef gradient = CGGradientCreateWithColors(
            space, (__bridge CFArrayRef)colors, locations);
        CGContextDrawLinearGradient(context.CGContext, gradient, CGPointZero,
                                    CGPointMake(size.width, 0.0), 0);
        CGGradientRelease(gradient);
        CGColorSpaceRelease(space);
    }];
    if (YTKACEStripCache == nil) YTKACEStripCache = [NSMutableDictionary dictionary];
    if (YTKACEStripCache.count > 40) [YTKACEStripCache removeAllObjects];
    YTKACEStripCache[key] = image;
    return image;
}

static UIView *YTKACEBarAncestor(UIView *view) {
    UIView *node = view;
    while (node != nil) {
        NSString *name = NSStringFromClass(node.class);
        if ([name isEqualToString:@"YTModularPlayerBarView"] ||
            [name isEqualToString:@"YTInlinePlayerBarContainerView"]) {
            return node;
        }
        node = node.superview;
    }
    return view.superview ?: view;
}

static UIColor *YTKACEPlayedColorForView(id receiver) {
    if (YTKACEProgressStyle() != 2) return YTKACEMainColor();
    if (![receiver isKindOfClass:UIView.class]) return YTKACEPlayedColor();
    UIView *view = (UIView *)receiver;
    UIView *bar = YTKACEBarAncestor(view);
    CGFloat barWidth = CGRectGetWidth(bar.bounds);
    CGFloat viewWidth = CGRectGetWidth(view.bounds);
    CGFloat height = MAX(CGRectGetHeight(view.bounds), 2.0);
    if (barWidth < 2.0 || viewWidth < 1.0) return YTKACEPlayedColor();
    CGRect inBar = [view convertRect:view.bounds toView:bar];
    CGFloat offset = CGRectGetMinX(inBar);
    if (offset < 0.0) offset = 0.0;
    if (barWidth - offset < viewWidth) barWidth = offset + viewWidth;

    NSString *patternKey = [NSString stringWithFormat:@"%.0f|%.0f|%.0f|%.0f",
                            offset, viewWidth, height, barWidth];
    UIColor *cachedPattern = YTKACEPatternCache[patternKey];
    if (cachedPattern != nil) return cachedPattern;
    CGFloat scale = UIScreen.mainScreen.scale;
    UIImage *full = YTKACEGradientStrip(barWidth, height);
    CGRect crop = CGRectMake(offset * scale, 0.0,
                             viewWidth * scale, height * scale);
    CGImageRef slice = CGImageCreateWithImageInRect(full.CGImage, crop);
    if (slice == NULL) return YTKACEPlayedColor();
    UIImage *tile = [UIImage imageWithCGImage:slice
                                        scale:scale
                                  orientation:UIImageOrientationUp];
    CGImageRelease(slice);
    UIColor *pattern = [UIColor colorWithPatternImage:tile];
    if (YTKACEPatternCache == nil) YTKACEPatternCache = [NSMutableDictionary dictionary];
    if (YTKACEPatternCache.count > 96) [YTKACEPatternCache removeAllObjects];
    YTKACEPatternCache[patternKey] = pattern;
    return pattern;
}

static UIColor *YTKACEScrubberColor(void) {
    return YTKACEStoredColor(YTKACEProgressScrubberColorKey, YTKACEMainColor());
}

static id YTKACEDecorationViewColor(id receiver, SEL selector) {
    if (YTKACEProgressStyle() != 0) return YTKACEPlayedColorForView(receiver);
    return OriginalDecorationViewColor == NULL ? nil :
        ((id (*)(id, SEL))OriginalDecorationViewColor)(receiver, selector);
}

static id YTKACEDecorationControllerColor(id receiver, SEL selector) {
    if (YTKACEProgressStyle() != 0) return YTKACEPlayedColor();
    return OriginalDecorationControllerColor == NULL ? nil :
        ((id (*)(id, SEL))OriginalDecorationControllerColor)(receiver, selector);
}

static id YTKACEContainerQuietColor(id receiver, SEL selector) {
    if (YTKACEProgressStyle() != 0) return YTKACEPlayedColor();
    return OriginalContainerQuietColor == NULL ? nil :
        ((id (*)(id, SEL))OriginalContainerQuietColor)(receiver, selector);
}


static id YTKACEDotColorV1(id receiver, SEL selector) {
    if (YTKACEProgressStyle() != 0) return YTKACEScrubberColor();
    return OriginalScrubberDotColorV1 == NULL ? nil :
        ((id (*)(id, SEL))OriginalScrubberDotColorV1)(receiver, selector);
}

static id YTKACEDotColorV2(id receiver, SEL selector) {
    if (YTKACEProgressStyle() != 0) return YTKACEScrubberColor();
    return OriginalScrubberDotColorV2 == NULL ? nil :
        ((id (*)(id, SEL))OriginalScrubberDotColorV2)(receiver, selector);
}

static void YTKACESetDotColor(id receiver, SEL selector, id color) {
    id replacement = YTKACEProgressStyle() != 0 ? YTKACEScrubberColor() : color;
    if (OriginalSetScrubberDotColor != NULL) {
        ((void (*)(id, SEL, id))OriginalSetScrubberDotColor)(receiver, selector, replacement);
    }
}

static void YTKACESetDotColorV1(id receiver, SEL selector, id color) {
    id replacement = YTKACEProgressStyle() != 0 ? YTKACEScrubberColor() : color;
    if (OriginalSetScrubberDotColorV1 != NULL) {
        ((void (*)(id, SEL, id))OriginalSetScrubberDotColorV1)(receiver, selector, replacement);
    }
}

static void YTKACESetDotColorV2(id receiver, SEL selector, id color) {
    id replacement = YTKACEProgressStyle() != 0 ? YTKACEScrubberColor() : color;
    if (OriginalSetScrubberDotColorV2 != NULL) {
        ((void (*)(id, SEL, id))OriginalSetScrubberDotColorV2)(receiver, selector, replacement);
    }
}

static IMP OriginalModularBarLayout;
static IMP OriginalDrawProgressRectWithColor;
static IMP OriginalDecorationDrawRect;
static IMP OriginalDrawProgressRect;
static IMP OriginalDrawRectDecorationProgress;
static IMP OriginalDrawRectDecoration;
static IMP OriginalSegmentedLayout;

static BOOL YTKACEColorIsYouTubeRed(CGColorRef color) {
    if (color == NULL) return NO;
    const CGFloat *components = CGColorGetComponents(color);
    if (components == NULL || CGColorGetNumberOfComponents(color) < 3) return NO;
    return components[0] > 0.6 && components[1] < 0.4 && components[2] < 0.4;
}

static void YTKACEApplyLayerFill(CALayer *layer, UIColor *colour,
                                 CGFloat width, CGFloat height) {
    if (colour == nil) return;
    CGColorRef reference = colour.CGColor;
    if (CGColorGetPattern(reference) == NULL) {
        layer.backgroundColor = reference;
        return;
    }
    if (YTKACEProgressStyle() == 2) {
        UIImage *fill = YTKACEGradientStrip(MAX(width, 1.0), MAX(height, 1.0));
        layer.backgroundColor = YTKACEMainColor().CGColor;
        if (fill.CGImage != NULL) {
            layer.contents = (__bridge id)fill.CGImage;
            layer.contentsScale = fill.scale;
            layer.contentsGravity = kCAGravityResize;
        }
    } else {
        layer.backgroundColor = YTKACEMainColor().CGColor;
    }
}

static void YTKACEPaintLayers(CALayer *layer, UIColor *played, UIColor *dot,
                              NSUInteger depth) {
    if (layer == nil || depth > 7) return;
    CGRect bounds = layer.bounds;
    CGFloat width = CGRectGetWidth(bounds);
    CGFloat height = CGRectGetHeight(bounds);
    if (width > 0.0 && height > 0.0 && YTKACEColorIsYouTubeRed(layer.backgroundColor)) {
        YTKACEApplyLayerFill(layer, (width <= height + 2.0) ? dot : played,
                             width, height);
    }
    for (CALayer *sublayer in layer.sublayers) {
        YTKACEPaintLayers(sublayer, played, dot, depth + 1);
    }
}

static void YTKACEModularBarLayout(UIView *receiver, SEL selector) {
    if (OriginalModularBarLayout != NULL) {
        ((void (*)(id, SEL))OriginalModularBarLayout)(receiver, selector);
    }
    if (YTKACEProgressStyle() == 0) return;
    YTKACEPaintLayers(receiver.layer, YTKACEPlayedColor(), YTKACEScrubberColor(), 0);
    UIView *node = receiver;
    while (node != nil) {
        if ([NSStringFromClass(node.class)
                isEqualToString:@"YTInlinePlayerBarContainerView"]) {
            SEL setter = NSSelectorFromString(@"setPlayedProgressBarColor:");
            if ([node respondsToSelector:setter]) {
                ((void (*)(id, SEL, id))objc_msgSend)(node, setter, YTKACEPlayedColor());
            }
            YTKACEPaintLayers(node.layer, YTKACEPlayedColor(), YTKACEScrubberColor(), 0);
            break;
        }
        node = node.superview;
    }
}

static BOOL YTKACEDrawGradientInRect(id receiver, CGRect rect) {
    if (YTKACEProgressStyle() != 2) return NO;
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (context == NULL || ![receiver isKindOfClass:UIView.class]) return NO;
    CGFloat height = CGRectGetHeight(rect);
    if (height < 0.5 || CGRectGetWidth(rect) < 0.5) return NO;

    UIView *view = (UIView *)receiver;
    UIView *bar = YTKACEBarAncestor(view);
    CGFloat track = CGRectGetWidth(bar.bounds);
    CGFloat own = CGRectGetWidth(view.bounds);
    if (track < own) track = own;
    if (track < 2.0) return NO;

    CGRect inBar = [view convertRect:view.bounds toView:bar];
    CGFloat offset = CGRectGetMinX(inBar);
    if (offset < 0.0 || offset > track) offset = 0.0;

    UIImage *strip = YTKACEGradientStrip(track, height);
    if (strip == nil) return NO;

    CGContextSaveGState(context);
    CGContextClipToRect(context, rect);
    [strip drawInRect:CGRectMake(-offset, CGRectGetMinY(rect), track, height)];
    CGContextRestoreGState(context);
    return YES;
}

static void YTKACEDrawProgressRectWithColor(id receiver, SEL selector,
                                            CGRect rect, id color) {
    if (YTKACEDrawGradientInRect(receiver, rect)) return;
    id replacement = YTKACEProgressStyle() != 0 ? YTKACEMainColor() : color;
    if (OriginalDrawProgressRectWithColor != NULL) {
        ((void (*)(id, SEL, CGRect, id))OriginalDrawProgressRectWithColor)(
            receiver, selector, rect, replacement);
    }
}

static void YTKACEForceBarColor(id receiver) {
    if (YTKACEProgressStyle() == 0) return;
    SEL setter = NSSelectorFromString(@"setPlayedProgressBarColor:");
    if (![receiver respondsToSelector:setter]) return;
    UIColor *colour = YTKACEPlayedColorForView(receiver);
    if (CGColorGetPattern(colour.CGColor) != NULL) {
        colour = YTKACEMainColor();
    }
    ((void (*)(id, SEL, id))objc_msgSend)(receiver, setter, colour);
}

static void YTKACEDecorationDrawRect(id receiver, SEL selector, CGRect rect) {
    YTKACEForceBarColor(receiver);
    if (OriginalDecorationDrawRect != NULL) {
        ((void (*)(id, SEL, CGRect))OriginalDecorationDrawRect)(receiver, selector, rect);
    }
}

static void YTKACERecolorSegments(id receiver) {
    if (YTKACEProgressStyle() == 0) return;
    if (![receiver isKindOfClass:UIView.class]) return;
    YTKACEPaintLayers(((UIView *)receiver).layer,
                      YTKACEPlayedColor(), YTKACEScrubberColor(), 0);
    SEL segments = NSSelectorFromString(@"segmentViews");
    if (![receiver respondsToSelector:segments]) return;
    NSArray *views = ((id (*)(id, SEL))objc_msgSend)(receiver, segments);
    if (![views isKindOfClass:NSArray.class]) return;
    for (id view in views) {
        if ([view isKindOfClass:UIView.class]) {
            YTKACEPaintLayers(((UIView *)view).layer,
                              YTKACEPlayedColor(), YTKACEScrubberColor(), 0);
        }
    }
}


static void YTKACESegmentedLayout(id receiver, SEL selector) {
    if (OriginalSegmentedLayout != NULL) {
        ((void (*)(id, SEL))OriginalSegmentedLayout)(receiver, selector);
    }
    YTKACERecolorSegments(receiver);
}


static void YTKACEDrawProgressRect(id receiver, SEL selector, CGRect rect) {
    if (YTKACEDrawGradientInRect(receiver, rect)) return;
    YTKACEForceBarColor(receiver);
    if (OriginalDrawProgressRect != NULL) {
        ((void (*)(id, SEL, CGRect))OriginalDrawProgressRect)(receiver, selector, rect);
    }
}

static void YTKACEDrawRectDecorationProgress(id receiver, SEL selector, CGRect rect) {
    YTKACEForceBarColor(receiver);
    if (OriginalDrawRectDecorationProgress != NULL) {
        ((void (*)(id, SEL, CGRect))OriginalDrawRectDecorationProgress)(
            receiver, selector, rect);
    }
}

static void YTKACEDrawRectDecoration(id receiver, SEL selector, CGRect rect) {
    YTKACEForceBarColor(receiver);
    if (OriginalDrawRectDecoration != NULL) {
        ((void (*)(id, SEL, CGRect))OriginalDrawRectDecoration)(receiver, selector, rect);
    }
}

static UIView *YTKACEFindProgressView(UIView *view, NSUInteger depth) {
    if (view == nil || depth > 4) return nil;
    if ([NSStringFromClass(view.class) isEqualToString:@"YTProgressView"]) return view;
    for (UIView *subview in view.subviews) {
        UIView *found = YTKACEFindProgressView(subview, depth + 1);
        if (found != nil) return found;
    }
    return nil;
}

void YTKACEStyleProgressLayer(CALayer *layer, CGFloat trackWidth) {
    if (layer == nil) return;
    if (YTKACEProgressStyle() == 0) return;
    CGFloat width = CGRectGetWidth(layer.bounds);
    CGFloat height = CGRectGetHeight(layer.bounds);
    if (width < 1.0 || height < 1.0) return;
    (void)trackWidth;
    if (YTKACEProgressStyle() == 2) {
        UIImage *fill = YTKACEGradientStrip(MAX(width, 1.0), MAX(height, 1.0));
        layer.backgroundColor = YTKACEMainColor().CGColor;
        if (fill.CGImage != NULL) {
            layer.contents = (__bridge id)fill.CGImage;
            layer.contentsScale = fill.scale;
            layer.contentsGravity = kCAGravityResize;
        }
    } else {
        layer.contents = nil;
        layer.backgroundColor = YTKACEMainColor().CGColor;
    }
}

void YTKACEApplyProgressStyleToBar(UIView *bar) {
    if (YTKACEProgressStyle() == 0 || ![bar isKindOfClass:UIView.class]) return;
    UIView *progress = YTKACEFindProgressView(bar, 0);
    if (progress == nil) return;

    SEL brand = NSSelectorFromString(@"setBrandGradientEnabled:");
    if ([progress respondsToSelector:brand]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(progress, brand, NO);
    }

    UIColor *color = YTKACEMainColor();
    CGFloat width = CGRectGetWidth(bar.bounds);
    CGFloat height = MAX(CGRectGetHeight(progress.bounds), 2.0);
    if (YTKACEProgressStyle() == 2 && width > 2.0) {
        color = [UIColor colorWithPatternImage:YTKACEGradientStrip(width, height)];
    }
    SEL setter = NSSelectorFromString(@"setProgressBarColor:");
    if ([progress respondsToSelector:setter]) {
        ((void (*)(id, SEL, id))objc_msgSend)(progress, setter, color);
    }
    YTKACEPaintLayers(progress.layer, color, YTKACEScrubberColor(), 0);
}



static NSUInteger YTKACEInstallProgressHookSet(void) {
    NSUInteger landed = 0;
    struct { const char *cls; const char *sel; IMP replacement; IMP *storage; } entries[] = {
        {"YTPlayerBarProgressDecorationView", "playedProgressBarColor",
         (IMP)YTKACEDecorationViewColor, &OriginalDecorationViewColor},
        {"YTPlayerBarProgressDecorationController", "playedProgressBarColor",
         (IMP)YTKACEDecorationControllerColor, &OriginalDecorationControllerColor},
        {"YTInlinePlayerBarContainerView", "quietProgressBarColor",
         (IMP)YTKACEContainerQuietColor, &OriginalContainerQuietColor},
        {"YTPlayerBarScrubberDotDecorationViewV1", "scrubberDotColor",
         (IMP)YTKACEDotColorV1, &OriginalScrubberDotColorV1},
        {"YTPlayerBarScrubberDotDecorationViewV2", "scrubberDotColor",
         (IMP)YTKACEDotColorV2, &OriginalScrubberDotColorV2},
        {"YTPlayerBarScrubberDotDecorationView", "setScrubberDotColor:",
         (IMP)YTKACESetDotColor, &OriginalSetScrubberDotColor},
        {"YTPlayerBarScrubberDotDecorationViewV1", "setScrubberDotColor:",
         (IMP)YTKACESetDotColorV1, &OriginalSetScrubberDotColorV1},
        {"YTPlayerBarScrubberDotDecorationViewV2", "setScrubberDotColor:",
         (IMP)YTKACESetDotColorV2, &OriginalSetScrubberDotColorV2},
        {"YTModularPlayerBarView", "layoutSubviews",
         (IMP)YTKACEModularBarLayout, &OriginalModularBarLayout},
        {"YTPlayerBarProgressDecorationView", "drawProgressRect:withColor:",
         (IMP)YTKACEDrawProgressRectWithColor, &OriginalDrawProgressRectWithColor},
        {"YTPlayerBarProgressDecorationView", "drawRect:",
         (IMP)YTKACEDecorationDrawRect, &OriginalDecorationDrawRect},
        {"YTPlayerBarScrubberDotDecorationViewV1", "layoutSubviews",
         (IMP)YTKACESegmentedLayout, &OriginalSegmentedLayout},
        {"YTPlayerBarProgressDecorationView", "drawProgressRect:",
         (IMP)YTKACEDrawProgressRect, &OriginalDrawProgressRect},
        {"YTPlayerBarProgressDecorationView", "drawRectangleDecorationWithProgress:",
         (IMP)YTKACEDrawRectDecorationProgress, &OriginalDrawRectDecorationProgress},
        {"YTPlayerBarProgressDecorationView", "drawRectangleDecoration:",
         (IMP)YTKACEDrawRectDecoration, &OriginalDrawRectDecoration}
    };
    for (size_t i = 0; i < sizeof(entries) / sizeof(entries[0]); i++) {
        NSString *cls = @(entries[i].cls);
        NSString *sel = @(entries[i].sel);
        BOOL ok = YTKACEInstallInstanceHook(cls, sel, entries[i].replacement,
                                            entries[i].storage);
        if (ok) landed++;
    }
    return landed;
}

void YTKACEInstallProgressBarHooks(void) {
    static NSUInteger attempt = 0;
    NSUInteger landed = YTKACEInstallProgressHookSet();
    attempt++;
    if (landed >= 10 || attempt >= 20) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        YTKACEInstallProgressBarHooks();
    });
}
