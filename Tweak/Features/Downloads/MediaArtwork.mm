#import "MediaArtwork.h"

#import <AVFoundation/AVFoundation.h>

NSData *YTKACEMediaArtworkData(NSURL *URL) {
    NSURL *base = URL.URLByDeletingPathExtension;
    for (NSString *extension in @[@"jpg", @"png"]) {
        NSData *data = [NSData dataWithContentsOfURL:
            [base URLByAppendingPathExtension:extension]];
        if (data.length != 0) return data;
    }
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
    });
    UIImage *cached = [s_artworkCache objectForKey:URL];
    if (cached != nil) return cached;

    NSData *data = YTKACEMediaArtworkData(URL);
    if (data.length == 0) return nil;
    UIImage *image = [UIImage imageWithData:data];
    if (image != nil) {
        [s_artworkCache setObject:image forKey:URL];
    }
    return image;
}
