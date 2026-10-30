#import "WPThumbnailOptimizationChecks.h"
#import "WPCatalogController.h"
#import <UIKit/UIKit.h>

@interface WPCatalogController (WPThumbnailOptimizationTesting)
- (void)applyFilter;
@end
@interface WPCThumbnailLoader : NSObject
@property(nonatomic,strong) NSURLSession *session;
@property(nonatomic,strong) NSCache *images;
+ (instancetype)shared;
@end

@interface WPThumbnailCountingCollection : UICollectionView
@property(nonatomic) NSUInteger reloadCount;
@end
@implementation WPThumbnailCountingCollection
- (void)reloadData { self.reloadCount++; }
@end

NSDictionary<NSString *, NSNumber *> *WPThumbnailOptimizationChecks(void) {
    NSMutableDictionary *results=[NSMutableDictionary new];
    @try {
        WPCThumbnailLoader *loader=[WPCThumbnailLoader shared];
        results[@"thumbnailNetworkConcurrencyBounded"]=@(loader.session.configuration.HTTPMaximumConnectionsPerHost==4);
        results[@"thumbnailMemoryCacheStillBounded"]=@(loader.images.countLimit==32 && loader.images.totalCostLimit==4*1024*1024);
        WPCatalogController *controller=[WPCatalogController new];
        WPThumbnailCountingCollection *collection=[[WPThumbnailCountingCollection alloc] initWithFrame:CGRectZero collectionViewLayout:[UICollectionViewFlowLayout new]];
        UISegmentedControl *segments=[[UISegmentedControl alloc] initWithItems:@[@"online",@"ranking",@"local"]];segments.selectedSegmentIndex=0;
        NSMutableSet *downloads=[NSMutableSet new];
        [controller setValue:@[] forKey:@"shownPets"];
        [controller setValue:@[] forKey:@"localPets"];
        [controller setValue:@[@{@"slug":@"preview-fixture",@"displayName":@"fixture",@"spritesheetUrl":@"https://assets.petdex.dev/fixture.webp"}] forKey:@"allPets"];
        [controller setValue:downloads forKey:@"downloading"];
        [controller setValue:segments forKey:@"segments"];
        [controller setValue:[UISearchBar new] forKey:@"searchBar"];
        [controller setValue:[UILabel new] forKey:@"countLabel"];
        [controller setValue:[UILabel new] forKey:@"noteLabel"];
        [controller setValue:[UILabel new] forKey:@"emptyLabel"];
        [controller setValue:collection forKey:@"collection"];
        [controller applyFilter];NSUInteger initial=collection.reloadCount;
        [controller applyFilter];
        results[@"thumbnailUnchangedFilterKeepsInflightPreview"]=@(initial==1 && collection.reloadCount==initial);
        [downloads addObject:@"petdex:preview-fixture"];[controller applyFilter];
        results[@"thumbnailDownloadStatusStillRefreshes"]=@(collection.reloadCount==initial+1);
        [controller applyFilter];results[@"thumbnailUnchangedDownloadStatusDoesNotReload"]=@(collection.reloadCount==initial+1);
        segments.selectedSegmentIndex=2;[controller applyFilter];
        results[@"thumbnailChangingSectionStillRefreshes"]=@(collection.reloadCount==initial+2);
    } @catch(NSException *exception) {
        NSLog(@"Thumbnail optimization checks failed: %@",exception.reason);
        results[@"thumbnailOptimizationChecksDoNotThrow"]=@NO;
    }
    return results;
}
