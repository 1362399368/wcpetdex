#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
// Compatibility accessors. Chat height is no longer read from preferences.
FOUNDATION_EXPORT CGFloat WPResizableChatSavedHeightFraction(void);
FOUNDATION_EXPORT CGFloat WPResizableChatClampHeightFraction(CGFloat fraction);
/// Applies the initial 75% / native-large detents to an already-native chat.
/// UIKit and WeChat retain all drag, keyboard, menu and dismissal handling.
@interface WPResizableChatController : NSObject
@property(nonatomic,weak,readonly) UIViewController *presentedController;
@property(nonatomic,weak,readonly) UINavigationController *chatNavigationController;
@property(nonatomic,readonly) CGFloat heightFraction;
@property(nonatomic,readonly) BOOL heightHoldPending;
@property(nonatomic,readonly) BOOL adjustingHeight;
@property(nonatomic,readonly) BOOL fullHeight;
+ (nullable instancetype)coordinatorForController:(nullable UIViewController *)controller;
+ (nullable instancetype)attachToPresentedController:(UIViewController *)controller navigationController:(nullable UINavigationController *)navigation;
// Kept inert for existing callers; no custom height state, gestures or saving.
- (void)beginHeightAdjustment;
- (void)updateHeightAdjustmentToFraction:(CGFloat)fraction;
- (void)endHeightAdjustment;
- (void)finishHeightAdjustmentWithVelocity:(CGFloat)verticalPointsPerSecond;
- (void)close;
@end
NS_ASSUME_NONNULL_END
