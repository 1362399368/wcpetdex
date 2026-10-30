#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Only presentation preferences are persisted; message contents stay in memory.
FOUNDATION_EXPORT BOOL WPBarrageEnabled(void);
FOUNDATION_EXPORT BOOL WPBarrageShowsDetails(void);
FOUNDATION_EXPORT BOOL WPBarrageShowsName(void);
FOUNDATION_EXPORT BOOL WPBarrageNameUsesRemark(void);
/// 0: bounce, 1: avatar flight, 2: fade, 3: no completion animation.
FOUNDATION_EXPORT NSInteger WPBarrageCompletionAnimation(void);
FOUNDATION_EXPORT void WPBarrageSetShowsName(BOOL enabled);
FOUNDATION_EXPORT void WPBarrageSetNameUsesRemark(BOOL enabled);
FOUNDATION_EXPORT void WPBarrageSetCompletionAnimation(NSInteger animation);
FOUNDATION_EXPORT BOOL WPBarrageFullScreen(void);
FOUNDATION_EXPORT BOOL WPBarrageReactionsEnabled(void);
FOUNDATION_EXPORT CGFloat WPBarrageSpeed(void);
FOUNDATION_EXPORT CGFloat WPBarrageBackgroundOpacity(void);
/// The range selector sets the half/full-screen baseline. Region height scales
/// that baseline, and vertical position moves it only within the safe screen.
FOUNDATION_EXPORT CGFloat WPBarrageVerticalPosition(void);
FOUNDATION_EXPORT CGFloat WPBarrageRegionHeight(void);
FOUNDATION_EXPORT CGRect WPBarrageDisplayArea(CGRect safeRect);
FOUNDATION_EXPORT void WPBarrageSetVerticalPosition(CGFloat position);
FOUNDATION_EXPORT void WPBarrageSetRegionHeight(CGFloat fraction);
FOUNDATION_EXPORT BOOL WPBarrageIsPaused(void);
FOUNDATION_EXPORT NSTimeInterval WPBarragePauseRemaining(void);
FOUNDATION_EXPORT void WPBarragePauseForInterval(NSTimeInterval seconds);
FOUNDATION_EXPORT void WPBarrageResume(void);
FOUNDATION_EXPORT BOOL WPBarrageAdaptiveSavingEnabled(void);
FOUNDATION_EXPORT void WPBarrageSetAdaptiveSavingEnabled(BOOL enabled);
FOUNDATION_EXPORT BOOL WPBarrageResourceSavingActive(void);
FOUNDATION_EXPORT void WPBarrageStartEnvironmentMonitor(void);
FOUNDATION_EXPORT BOOL WPBarrageQuietTimeEnabled(void);
FOUNDATION_EXPORT NSInteger WPBarrageQuietMinute(BOOL start);
FOUNDATION_EXPORT BOOL WPBarrageQuietTimeAtDate(NSDate *date);
FOUNDATION_EXPORT BOOL WPBarrageContactsOnly(void);
FOUNDATION_EXPORT NSArray<NSString *> *WPBarrageContactUsernames(void);
FOUNDATION_EXPORT BOOL WPBarrageAllowsPrivateChats(void);
FOUNDATION_EXPORT BOOL WPBarrageAllowsGroupChats(void);
FOUNDATION_EXPORT BOOL WPBarrageReminderAllowsUsername(NSString * _Nullable username, NSDate *date);
/// Accepts only the documented barrage reminder keys and bounded values.
FOUNDATION_EXPORT void WPBarrageSetReminderValue(NSString *key, id value);

/// Settings notifications are delivered on the main thread. Turning details off
/// lets the overlay immediately discard visible and pending message text.
FOUNDATION_EXPORT void WPBarrageSetEnabled(BOOL enabled);
FOUNDATION_EXPORT void WPBarrageSetShowsDetails(BOOL showsDetails);
FOUNDATION_EXPORT void WPBarrageSetFullScreen(BOOL fullScreen);
FOUNDATION_EXPORT void WPBarrageSetReactionsEnabled(BOOL enabled);
FOUNDATION_EXPORT void WPBarrageSetSpeed(CGFloat speed);
FOUNDATION_EXPORT void WPBarrageSetBackgroundOpacity(CGFloat opacity);

/// Clears the retained barrage avatar; it does not alter WeChat's read state.
FOUNDATION_EXPORT NSString * const WPBarrageClearDockNotification;
FOUNDATION_EXPORT NSString * const WPBarragePreviewNotification;

NS_ASSUME_NONNULL_END
