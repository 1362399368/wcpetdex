#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN
/// Sensitivity stored in preferences as "shakeSensitivity": 0 low, 1 medium, 2 high.
FOUNDATION_EXPORT NSInteger WPShakeSensitivityFromPreferenceValue(id _Nullable value);

/// Detects quick left-right shaking during one drag. An ordinary move goes
/// mostly one way and never reaches the reversal count inside the window.
@interface WPShakeDetector : NSObject
- (instancetype)initWithSensitivity:(NSInteger)sensitivity;
@property(nonatomic,readonly) CGFloat minimumSwing;
@property(nonatomic,readonly) NSUInteger requiredReversals;
@property(nonatomic,readonly) NSTimeInterval window;
/// Seconds after a trigger during which new gestures cannot trigger.
@property(nonatomic) NSTimeInterval cooldown;
- (void)beginAtPoint:(CGPoint)point time:(NSTimeInterval)time;
/// YES exactly once per gesture, on the sample completing the shake.
- (BOOL)addPoint:(CGPoint)point time:(NSTimeInterval)time;
@property(nonatomic,readonly) BOOL triggered;
@end
NS_ASSUME_NONNULL_END
