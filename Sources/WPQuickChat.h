#import <UIKit/UIKit.h>
#import "WPQuickChatModel.h"

NS_ASSUME_NONNULL_BEGIN
/// Posted on the main queue. userInfo @"arrivals" lists usernames that just
/// received a message (alertable, newest first); it is empty when only the
/// unread state changed.
FOUNDATION_EXPORT NSString * const WPQuickChatDidChangeNotification;
FOUNDATION_EXPORT BOOL WPQuickChatEnabled(void);
FOUNDATION_EXPORT BOOL WPQuickChatFlashEnabled(void);
/// WeChat's head image for a session; nil when this build does not expose it.
FOUNDATION_EXPORT UIImage * _Nullable WPQuickChatAvatar(NSString *username);
/// Native cache/disk access is read on main; image preparation runs on a bounded
/// utility queue. Cancel immediately releases waiting inputs and suppresses callbacks.
@interface WPQuickChatAvatarPreparation : NSObject
- (void)cancel;
@end
FOUNDATION_EXPORT WPQuickChatAvatarPreparation *WPQuickChatPrepareAvatar(NSString *username, CGFloat maximumPixels, void (^completion)(UIImage * _Nullable image));
/// Contact's avatar URL when WeChat's in-memory image manager has no image yet.
FOUNDATION_EXPORT NSURL * _Nullable WPQuickChatAvatarURL(NSString *username);
/// A missing native row or incomplete metadata is Unknown, never proof of read.
typedef NS_ENUM(NSInteger, WPQuickChatUnreadState) {
    WPQuickChatUnreadStateUnknown,
    WPQuickChatUnreadStateRead,
    WPQuickChatUnreadStateUnread,
    WPQuickChatUnreadStateDenied
};
FOUNDATION_EXPORT WPQuickChatUnreadState WPQuickChatUnreadStateForUsername(NSString *username);
/// Called by the native receive adapter before its optional barrage gate.
/// Coalesces a burst into one bounded foreground refresh, carrying no body.
FOUNDATION_EXPORT void WPQuickChatNotifyNativeMessage(void);
/// Lifecycle only; never creates a monitor from a native callback.
FOUNDATION_EXPORT void WPQuickChatSetForegroundAvailable(BOOL available);
/// Main-thread contact display name, limited to 24 composed characters.
/// Missing metadata returns an empty string rather than an internal wxid.
FOUNDATION_EXPORT NSString *WPQuickChatDisplayName(NSString *username, BOOL preferRemark);

/// Polls WeChat's own session list for unread changes. It installs no hook:
/// it only reads MMNewSessionMgr on the main queue while WeChat is active.
@interface WPQuickChatMonitor : NSObject
+ (instancetype)sharedMonitor;
/// Any unread chat that is not muted, from the latest observations.
@property (nonatomic, readonly) BOOL hasAlertableUnread;
/// Latest eligible unread chat in the last observations. Reading this cached
/// value never enumerates WeChat sessions or posts a notification.
@property (nonatomic, readonly, copy, nullable) NSString *latestObservedUnreadUsername;
/// Cached row for the unified message avatar. No native scan or notification.
@property (nonatomic, readonly, nullable) WPQuickChatSession *latestObservedUnreadSession;
/// Foreground and the feature switch on. Becoming active takes a new baseline,
/// so messages that arrived in the background show an avatar but do not flash.
- (void)setActive:(BOOL)active;
/// The whole recent-chat list in WeChat's order; nil when unreadable.
- (nullable NSArray<WPQuickChatSession *> *)currentSessions;
/// Newest visible, unmuted unread conversation. Uses the latest message time
/// when WeChat exposes it, then recent arrivals or the home list order.
- (nullable NSString *)latestUnreadUsername;
/// Route and counts only, never usernames.
- (NSDictionary<NSString *, id> *)diagnostics;
@end
NS_ASSUME_NONNULL_END
