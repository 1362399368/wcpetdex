#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
/// Header showing the current WeChat account and the product name.
FOUNDATION_EXPORT UIView *WPBuildHomeHeader(void);
/// A circular, accessible entry suitable for a responsive feature grid.
FOUNDATION_EXPORT UIControl *WPBuildHomeFeature(NSString *title, UIImage * _Nullable image, UIColor *tint, dispatch_block_t handler);
NS_ASSUME_NONNULL_END
