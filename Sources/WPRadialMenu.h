#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// A transparent menu in its superview's coordinate system. All point and bounds
/// arguments must be expressed in this view's local coordinates.
@interface WPRadialMenuView : UIView

/// Action identifiers: moments, miss, anger, read. Called on main.
@property (nonatomic, copy, nullable) void (^actionHandler)(NSString *action);
@property (nonatomic, readonly, getter=isShowing) BOOL showing;
@property (nonatomic, readonly) BOOL hasSelection;
/// Requested size is 80 * menuScale points; scale supports 0.6 through 4.0.
@property (nonatomic, readonly) CGFloat requestedRadius;
/// The radius after the screen and minimum touch spacing limits are applied.
@property (nonatomic, readonly) CGFloat effectiveRadius;
@property (nonatomic, readonly, getter=isRadiusLimited) BOOL radiusLimited;

/// Begins one interaction. Bounds should already account for safe areas.
- (void)showAroundPoint:(CGPoint)point inBounds:(CGRect)bounds;
/// Sliding onto an item selects it and shows its function without executing it.
- (void)updateFingerAtPoint:(CGPoint)point;
/// Executes the item under the last finger position once, then dismisses.
/// Call updateFingerAtPoint: with the final position before finishing. No item
/// selected means the gesture is dismissed without performing an action.
- (void)finishTracking;
/// Dismisses the interaction without performing an action.
- (void)cancel;

@end

NS_ASSUME_NONNULL_END
