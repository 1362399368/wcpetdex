#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSNotificationName const WPChatPresentationDidChangeNotification;
/// Reads only the foremost app content controller. An overlaid settings page,
/// a different chat, or a dismissed sheet never counts as the underlying chat.
FOUNDATION_EXPORT NSString * _Nullable WPChatPresentationActiveUsernameInWindow(UIWindow * _Nullable window);
FOUNDATION_EXPORT BOOL WPChatConversationIsVisible(NSString *username);
/// Finds a visible native chat through UIKit containers and native view ownership.
/// The returned controller belongs to this window; hidden/cached chats are excluded.
FOUNDATION_EXPORT UIViewController * _Nullable WPChatPresentationVisibleChatController(UIViewController * _Nullable container, UIWindow * _Nullable window);
FOUNDATION_EXPORT NSString * _Nullable WPChatPresentationUsernameForController(UIViewController * _Nullable controller);
/// Announces changes after native presentation/navigation has actually changed.
FOUNDATION_EXPORT void WPChatPresentationNotifyChanged(void);
NS_ASSUME_NONNULL_END
