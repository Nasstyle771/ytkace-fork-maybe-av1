#import "MediaArtwork.h"

#import <AVFoundation/AVFoundation.h>

NSData *YTKACEMediaArtworkData(NSURL *URL) {
    if (URL == nil || URL.path.length == 0) return nil;
    NSURL *base = URL.URLByDeletingPathExtension;
    for (NSString *extension in @[@"jpg", @"jpeg", @"png"]) {
        NSString *sidecarPath = [base.path stringByAppendingPathExtension:extension];
        if ([NSFileManager.defaultManager fileExistsAtPath:sidecarPath]) {
            NSData *data = [NSData dataWithContentsOfFile:sidecarPath];
            if (data.length != 0) return data;
        }
    }
    if (![NSFileManager.defaultManager fileExistsAtPath:URL.path]) return nil;
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:URL options:nil];
    NSArray<AVMetadataItem *> *items = [AVMetadataItem
        metadataItemsFromArray:asset.commonMetadata
        filteredByIdentifier:AVMetadataCommonIdentifierArtwork];
    id value = items.firstObject.value;
    if ([value isKindOfClass:NSData.class]) return value;
    if ([value respondsToSelector:@selector(dataValue)]) return [value dataValue];
    return nil;
}

UIImage *YTKACEMediaArtworkImage(NSURL *URL) {
    if (URL == nil) return nil;
    static NSCache<NSURL *, UIImage *> *s_artworkCache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s_artworkCache = [NSCache new];
        s_artworkCache.countLimit = 64;
        s_artworkCache.totalCostLimit = 32 * 1024 * 1024;
    });
    UIImage *cached = [s_artworkCache objectForKey:URL];
    if (cached != nil) return cached;

    NSData *data = YTKACEMediaArtworkData(URL);
    if (data.length == 0) return nil;
    UIImage *image = [UIImage imageWithData:data];
    if (image != nil) {
        NSUInteger cost = (NSUInteger)(image.size.width * image.size.height * 4);
        [s_artworkCache setObject:image forKey:URL cost:cost];
    }
    return image;
}
