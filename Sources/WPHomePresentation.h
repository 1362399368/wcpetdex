#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
/// Header showing the current WeChat account and the product name.
FOUNDATION_EXPORT UIView *WPBuildHomeHeader(void);
/// Header with a compact pet visibility action beside the account avatar.
FOUNDATION_EXPORT UIView *WPBuildHomeHeaderWithVisibility(BOOL hidden, void (^handler)(BOOL hidden));
/// A circular, accessible entry suitable for a responsive feature grid.
FOUNDATION_EXPORT UIControl *WPBuildHomeFeature(NSString *title, UIImage * _Nullable image, UIColor *tint, dispatch_block_t handler);
NS_ASSUME_NONNULL_END
