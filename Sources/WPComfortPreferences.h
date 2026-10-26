#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
typedef NS_ENUM(NSInteger, WPReminderIntensity) {
    WPReminderIntensityAvatarOnly = 0,
    WPReminderIntensityLight = 1,
    WPReminderIntensityFull = 2,
};
FOUNDATION_EXPORT BOOL WPPositionLocked(void);
FOUNDATION_EXPORT BOOL WPAllowUnreadPeek(void);
/// Normalized user anchor; keyboard avoidance must never write this value.
FOUNDATION_EXPORT CGPoint WPPositionAnchorForBounds(CGSize bounds);
FOUNDATION_EXPORT void WPStorePositionAnchor(CGPoint normalizedAnchor, CGSize bounds);
FOUNDATION_EXPORT void WPResetPositionAnchors(void);
FOUNDATION_EXPORT WPReminderIntensity WPConfiguredReminderIntensity(void);
FOUNDATION_EXPORT NSInteger WPQuietMinute(BOOL start);
FOUNDATION_EXPORT BOOL WPQuietTimeAtDate(NSDate *date);
FOUNDATION_EXPORT NSArray<NSString *> *WPReminderContactUsernames(void);
FOUNDATION_EXPORT BOOL WPReminderAllowsUsername(NSString * _Nullable username, NSDate *date);
NS_ASSUME_NONNULL_END
