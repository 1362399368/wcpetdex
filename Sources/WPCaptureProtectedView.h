#import <UIKit/UIKit.h>
/// A runtime-checked secure text canvas, following the local WCRefine design.
/// The fallback still hides during active recording; it never captures content.
@interface WPCaptureProtectedView : UIView
@property(nonatomic,readonly) BOOL protectionAvailable;
- (void)refreshProtection;
@end
