#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
/// Local selections only. Petdex does not publish global popularity in its manifest.
FOUNDATION_EXPORT void WPCatalogRecordUsageForDirectory(NSURL *directory);

@interface WPCatalogController : UIViewController
/// Set before loading the view to open downloaded pets without a network scan.
@property(nonatomic) BOOL startsWithDownloadedPets;
@end
NS_ASSUME_NONNULL_END
