#import "YTKACESettingsSearch.h"
#import "YTKACESettingsPages.h"
#import "../Runtime/Localization.h"
#import "../Runtime/Preferences.h"
#import "../UI/Assets.h"

#import <objc/message.h>
#import <objc/runtime.h>
#import <os/lock.h>

@interface YTKACESearchRecord : NSObject
@property(nonatomic, copy) NSString *pageID;
@property(nonatomic, copy) NSString *pageTitle;
@property(nonatomic, copy) NSString *header;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *subtitle;
@property(nonatomic, assign) NSInteger section;
@property(nonatomic, assign) NSInteger row;
@property(nonatomic, copy) NSString *normTitle;
@property(nonatomic, copy) NSString *normSubtitle;
@property(nonatomic, copy) NSString *normHeader;
@property(nonatomic, copy) NSString *normPageTitle;
@property(nonatomic, copy) NSArray<NSString *> *titleTokens;
@end

@implementation YTKACESearchRecord
@end

static os_unfair_lock s_searchIndexLock = OS_UNFAIR_LOCK_INIT;
static NSArray<YTKACESearchRecord *> *s_searchCatalog = nil;

static NSString *YTKACENormalizeString(NSString *input) {
    if (input.length == 0) return @"";
    NSMutableString *str = [input mutableCopy];
    CFStringTransform((__bridge CFMutableStringRef)str, NULL, kCFStringTransformStripCombiningMarks, NO);
    return [str.lowercaseString stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static UIViewController *YTKACEControllerForPageID(NSString *pageID) {
    static NSDictionary<NSString *, UIViewController *(^)(void)> *builders;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        builders = @{
            @"sponsorblock": ^UIViewController *{ return YTKACEMakeSponsorBlockController(); },
            @"player": ^UIViewController *{ return YTKACEMakePlayerControlsController(); },
            @"overlay": ^UIViewController *{ return YTKACEMakeOverlayOptionsController(); },
            @"playback": ^UIViewController *{ return YTKACEMakeStreamingOptionsController(); },
            @"navigation": ^UIViewController *{ return YTKACEMakeNavigationOptionsController(); },
            @"shorts": ^UIViewController *{ return YTKACEMakeShortsOptionsController(); },
            @"other": ^UIViewController *{ return YTKACEMakeMiscOptionsController(); },
            @"gestures": ^UIViewController *{ return YTKACEMakeGestureOptionsController(); }
        };
    });
    UIViewController *(^builder)(void) = builders[pageID ?: @""];
    return builder != nil ? builder() : nil;
}

static void YTKACEInvalidateSearchIndex(void) {
    os_unfair_lock_lock(&s_searchIndexLock);
    s_searchCatalog = nil;
    os_unfair_lock_unlock(&s_searchIndexLock);
}

static NSArray<YTKACESearchRecord *> *YTKACEGetSearchCatalog(void) {
    os_unfair_lock_lock(&s_searchIndexLock);
    if (s_searchCatalog != nil) {
        NSArray<YTKACESearchRecord *> *cached = s_searchCatalog;
        os_unfair_lock_unlock(&s_searchIndexLock);
        return cached;
    }
    os_unfair_lock_unlock(&s_searchIndexLock);

    static dispatch_once_t observerOnce;
    dispatch_once(&observerOnce, ^{
        [NSNotificationCenter.defaultCenter
            addObserverForName:YTKACEPreferencesDidChangeNotification
                        object:nil
                         queue:NSOperationQueue.mainQueue
                    usingBlock:^(NSNotification * _Nonnull note) {
            NSString *key = note.userInfo[@"key"];
            if ([key isEqualToString:@"YTKACE.Preference.Language"]) {
                YTKACEInvalidateSearchIndex();
            }
        }];
    });

    NSMutableArray<YTKACESearchRecord *> *records = [NSMutableArray arrayWithCapacity:128];
    for (NSDictionary *page in YTKACEAllPageDefinitions()) {
        NSArray *sections = page[@"sections"];
        NSArray *headers = page[@"headers"];
        NSString *rawPageTitle = page[@"title"];
        NSString *pageTitle = YTKACELocalized(rawPageTitle);
        NSString *normPageTitle = YTKACENormalizeString(pageTitle);
        NSString *pageID = page[@"id"];

        for (NSUInteger section = 0; section < sections.count; section++) {
            NSArray *items = sections[section];
            NSString *rawHeader = section < headers.count ? headers[section] : @"";
            NSString *header = rawHeader.length != 0 ? YTKACELocalized(rawHeader) : @"";
            NSString *normHeader = YTKACENormalizeString(header);

            for (NSUInteger row = 0; row < items.count; row++) {
                NSDictionary *item = items[row];
                NSString *title = item[@"title"];
                if (![title isKindOfClass:NSString.class] || title.length == 0) continue;
                if ([item[@"type"] isEqualToString:@"text"]) continue;

                NSString *subtitle = [item[@"subtitle"] isKindOfClass:NSString.class]
                    ? item[@"subtitle"] : @"";

                YTKACESearchRecord *rec = [YTKACESearchRecord new];
                rec.pageID = pageID;
                rec.pageTitle = pageTitle;
                rec.header = header;
                rec.title = title;
                rec.subtitle = subtitle;
                rec.section = (NSInteger)section;
                rec.row = (NSInteger)row;
                rec.normTitle = YTKACENormalizeString(title);
                rec.normSubtitle = YTKACENormalizeString(subtitle);
                rec.normHeader = normHeader;
                rec.normPageTitle = normPageTitle;
                rec.titleTokens = [rec.normTitle componentsSeparatedByCharactersInSet:
                    NSCharacterSet.whitespaceCharacterSet];
                [records addObject:rec];
            }
        }
    }

    os_unfair_lock_lock(&s_searchIndexLock);
    s_searchCatalog = records;
    os_unfair_lock_unlock(&s_searchIndexLock);

    return records;
}

static NSInteger YTKACEEvaluateMatchScore(YTKACESearchRecord *record,
                                         NSString *query,
                                         NSArray<NSString *> *tokens) {
    NSString *normTitle = record.normTitle;
    if ([normTitle isEqualToString:query]) {
        return 0; // Exact match
    }
    if ([normTitle hasPrefix:query]) {
        return 5; // Title starts with full query
    }

    // Word prefix match in title
    for (NSString *tok in record.titleTokens) {
        if ([tok hasPrefix:query]) {
            return 12;
        }
    }

    // Multi-token prefix match (e.g. "bg" "play" in "Background Playback")
    if (tokens.count > 1) {
        BOOL allTokensMatched = YES;
        for (NSString *qToken in tokens) {
            if (qToken.length == 0) continue;
            BOOL tokenFound = NO;
            for (NSString *wToken in record.titleTokens) {
                if ([wToken hasPrefix:qToken]) {
                    tokenFound = YES;
                    break;
                }
            }
            if (!tokenFound && [normTitle rangeOfString:qToken].location != NSNotFound) {
                tokenFound = YES;
            }
            if (!tokenFound) {
                allTokensMatched = NO;
                break;
            }
        }
        if (allTokensMatched) {
            return 20;
        }
    }

    // Substring match in title
    if ([normTitle rangeOfString:query].location != NSNotFound) {
        return 30;
    }

    // Subtitle matching
    NSString *normSub = record.normSubtitle;
    if (normSub.length != 0) {
        if ([normSub hasPrefix:query]) {
            return 45;
        }
        if ([normSub rangeOfString:query].location != NSNotFound) {
            return 55;
        }
        if (tokens.count > 1) {
            BOOL allInSub = YES;
            for (NSString *qTok in tokens) {
                if (qTok.length > 0 && [normSub rangeOfString:qTok].location == NSNotFound) {
                    allInSub = NO;
                    break;
                }
            }
            if (allInSub) return 60;
        }
    }

    // Header or page title matching
    if (record.normHeader.length != 0 && [record.normHeader rangeOfString:query].location != NSNotFound) {
        return 70;
    }
    if (record.normPageTitle.length != 0 && [record.normPageTitle rangeOfString:query].location != NSNotFound) {
        return 75;
    }

    // Acronym / Subsequence matching for short queries (2-4 chars)
    if (query.length >= 2 && query.length <= 4) {
        NSUInteger qIdx = 0;
        const char *qStr = query.UTF8String;
        const char *tStr = normTitle.UTF8String;
        if (qStr && tStr) {
            size_t qLen = strlen(qStr);
            size_t tLen = strlen(tStr);
            size_t tIdx = 0;
            while (qIdx < qLen && tIdx < tLen) {
                if (qStr[qIdx] == tStr[tIdx]) {
                    qIdx++;
                }
                tIdx++;
            }
            if (qIdx == qLen) {
                return 85;
            }
        }
    }

    return NSNotFound;
}

NSArray<NSDictionary *> *YTKACEFilterSettings(NSString *query) {
    NSString *normalizedQuery = YTKACENormalizeString(query);
    if (normalizedQuery.length == 0) return @[];

    NSArray<NSString *> *tokens = [normalizedQuery componentsSeparatedByCharactersInSet:
        NSCharacterSet.whitespaceCharacterSet];
    NSMutableArray<NSDictionary *> *scored = [NSMutableArray array];

    for (YTKACESearchRecord *record in YTKACEGetSearchCatalog()) {
        NSInteger score = YTKACEEvaluateMatchScore(record, normalizedQuery, tokens);
        if (score == NSNotFound) continue;

        [scored addObject:@{
            @"pageID": record.pageID,
            @"pageTitle": record.pageTitle,
            @"header": record.header,
            @"title": record.title,
            @"subtitle": record.subtitle,
            @"section": @(record.section),
            @"row": @(record.row),
            @"score": @(score)
        }];
    }

    [scored sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSComparisonResult order = [a[@"score"] compare:b[@"score"]];
        return order != NSOrderedSame ? order : [a[@"title"] localizedCaseInsensitiveCompare:b[@"title"]];
    }];

    return scored;
}

void YTKACEOpenSettingsRecord(NSDictionary *record, UIViewController *presenter) {
    UIViewController *page = YTKACEControllerForPageID(record[@"pageID"]);
    if (page == nil || presenter == nil) return;
    NSIndexPath *target = [NSIndexPath indexPathForRow:[record[@"row"] integerValue]
                                             inSection:[record[@"section"] integerValue]];
    SEL push = NSSelectorFromString(@"pushViewController:");
    if ([presenter respondsToSelector:push]) {
        ((void (*)(id, SEL, id))objc_msgSend)(presenter, push, page);
    } else if (presenter.navigationController != nil) {
        [presenter.navigationController pushViewController:page animated:YES];
    } else {
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.40 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (![page isKindOfClass:UITableViewController.class]) return;
        UITableView *table = ((UITableViewController *)page).tableView;
        if (target.section >= [table numberOfSections] ||
            target.row >= [table numberOfRowsInSection:target.section]) return;
        [table scrollToRowAtIndexPath:target
                     atScrollPosition:UITableViewScrollPositionMiddle
                             animated:YES];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.30 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            UITableViewCell *cell = [table cellForRowAtIndexPath:target];
            if (cell == nil) return;
            UIColor *original = cell.contentView.backgroundColor;
            cell.contentView.backgroundColor =
                [YTKACEAccentColor() colorWithAlphaComponent:0.28];
            [UIView animateWithDuration:0.8 delay:0.3
                                options:UIViewAnimationOptionCurveEaseOut
                             animations:^{ cell.contentView.backgroundColor = original; }
                             completion:nil];
        });
    });
}

@interface YTKACESearchOverlayController : UIViewController
    <UISearchBarDelegate, UITableViewDataSource, UITableViewDelegate>
@property(nonatomic, weak) UIViewController *hostController;
@property(nonatomic, strong) UISearchBar *searchBar;
@property(nonatomic, strong) UITableView *table;
@property(nonatomic, copy) NSArray<NSDictionary *> *results;
@end

@implementation YTKACESearchOverlayController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.results = @[];
    self.view.backgroundColor = YTKACEInterfaceBackgroundColor(self.traitCollection);

    self.searchBar = [UISearchBar new];
    self.searchBar.delegate = self;
    self.searchBar.placeholder = YTKACELocalized(@"Search");
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.tintColor = YTKACEAccentColor();
    self.searchBar.searchTextField.tintColor = YTKACEAccentColor();
    self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.searchBar];

    self.table = [[UITableView alloc] initWithFrame:CGRectZero
                                              style:UITableViewStylePlain];
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.backgroundColor = UIColor.clearColor;
    self.table.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.table];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.searchBar.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.searchBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.searchBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.table.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor],
        [self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.searchBar becomeFirstResponder];
}

- (void)dismissOverlay {
    [self.searchBar resignFirstResponder];
    [self willMoveToParentViewController:nil];
    [self.view removeFromSuperview];
    [self removeFromParentViewController];
}

- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar {
    [searchBar setShowsCancelButton:YES animated:YES];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text {
    (void)searchBar;
    self.results = YTKACEFilterSettings(text);
    [self.table reloadData];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    [searchBar setShowsCancelButton:NO animated:YES];
    [self dismissOverlay];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return (NSInteger)self.results.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *const identifier = @"YTKACEOverlayRow";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:identifier];
    }
    NSDictionary *record = self.results[(NSUInteger)indexPath.row];
    NSString *header = record[@"header"];
    cell.textLabel.text = record[@"title"];
    cell.detailTextLabel.text = header.length != 0
        ? [NSString stringWithFormat:@"%@ › %@", record[@"pageTitle"], header]
        : record[@"pageTitle"];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.backgroundColor = UIColor.clearColor;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *record = self.results[(NSUInteger)indexPath.row];
    UIViewController *host = self.hostController;
    [self dismissOverlay];
    YTKACEOpenSettingsRecord(record, host);
}

@end

void YTKACEPresentSettingsSearchOverlay(UIViewController *host) {
    if (host == nil || !host.isViewLoaded) return;
    for (UIViewController *child in host.childViewControllers) {
        if ([child isKindOfClass:YTKACESearchOverlayController.class]) return;
    }
    YTKACESearchOverlayController *overlay = [YTKACESearchOverlayController new];
    overlay.hostController = host;
    [host addChildViewController:overlay];
    overlay.view.frame = host.view.bounds;
    overlay.view.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [host.view addSubview:overlay.view];
    [overlay didMoveToParentViewController:host];
}
