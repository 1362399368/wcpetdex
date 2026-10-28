#import "WPRankingUIChecks.h"
#import "WPCatalogController.h"
#import <UIKit/UIKit.h>

@interface WPCatalogController (WPRankingPreview)
- (void)applyFilter;
@end

NSDictionary<NSString *,NSNumber *> *WPRankingUIPreviewChecks(void) {
    NSCAssert(NSThread.isMainThread,@"Ranking UI checks require main thread");
    WPCatalogController *controller=[WPCatalogController new];
    controller.startsWithDownloadedPets=YES;
    [controller loadViewIfNeeded];
    UISegmentedControl *segments=[controller valueForKey:@"segments"];
    UISearchBar *search=[controller valueForKey:@"searchBar"];
    UILabel *note=[controller valueForKey:@"noteLabel"];
    UILabel *empty=[controller valueForKey:@"emptyLabel"];
    segments.selectedSegmentIndex=1;
    NSArray *catalog=@[@{@"slug":@"second",@"displayName":@"Second",@"submittedBy":@"author2",@"spritesheetUrl":@"https://assets.petdex.dev/2.webp"},
                       @{@"slug":@"first",@"displayName":@"First",@"submittedBy":@"author1",@"spritesheetUrl":@"https://assets.petdex.dev/1.webp"},
                       @{@"slug":@"unranked",@"displayName":@"Unranked",@"submittedBy":@"other",@"spritesheetUrl":@"https://assets.petdex.dev/3.webp"}];
    NSArray *rank=@[@{@"slug":@"first",@"installCount":@100},@{@"slug":@"missing",@"installCount":@90},@{@"slug":@"second",@"installCount":@10}];
    [controller setValue:catalog forKey:@"allPets"];
    [controller setValue:@[] forKey:@"localPets"];
    [controller setValue:rank forKey:@"rankingPets"];
    [controller setValue:@YES forKey:@"rankingLoaded"];
    [controller setValue:@NO forKey:@"rankingLoading"];
    [controller setValue:@NO forKey:@"catalogLoading"];
    [controller applyFilter];
    NSArray *shown=[controller valueForKey:@"shownPets"];
    BOOL order=shown.count==2 && [shown[0][@"slug"] isEqual:@"first"] && [shown[1][@"slug"] isEqual:@"second"] && [shown[0][@"wp_installCount"] isEqual:@100];
    BOOL missing=[note.text containsString:@"1 个桌宠未在当前目录中"];
    search.text=@"author2";[controller applyFilter];shown=[controller valueForKey:@"shownPets"];
    BOOL filter=shown.count==1 && [shown[0][@"slug"] isEqual:@"second"];
    search.text=@"unranked";[controller applyFilter];shown=[controller valueForKey:@"shownPets"];
    BOOL noLocalFallback=shown.count==0 && [empty.text containsString:@"没有找到"];
    search.text=@"";[controller setValue:@YES forKey:@"rankingCached"];
    [controller setValue:[NSError errorWithDomain:@"test" code:1 userInfo:nil] forKey:@"rankingError"];[controller applyFilter];
    BOOL cached=[note.text containsString:@"上次获取的官方安装排行"] && ((NSArray *)[controller valueForKey:@"shownPets"]).count==2;
    [controller setValue:@NO forKey:@"rankingCached"];[controller setValue:@[] forKey:@"rankingPets"];[controller applyFilter];
    BOOL failure=[note.text containsString:@"不可用"] && [empty.text containsString:@"不可用"] && ((NSArray *)[controller valueForKey:@"shownPets"]).count==0;
    return @{@"rankingUIOfficialOrderAndCounts":@(order),@"rankingUIMissingCatalogReported":@(missing),
             @"rankingUISearchFiltersRankedEntries":@(filter),@"rankingUIDoesNotSubstituteLocalOrder":@(noLocalFallback),
             @"rankingUICachedClearlyLabeled":@(cached),@"rankingUIFailureClearlyLabeled":@(failure)};
}
