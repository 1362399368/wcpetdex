#import <UIKit/UIKit.h>
#import "WPQuickChat.h"
@class WPBarrageMessage, WPQuickChatSession;

NS_ASSUME_NONNULL_BEGIN
/// The one message indicator above the pet. All access is on the main queue.
/// Stores bounded identifiers and counters; never keeps a message or its text.
@interface WPUnreadDockState : NSObject
@property(nonatomic,copy,readonly,nullable) NSString *conversationUsername;
@property(nonatomic,copy,readonly,nullable) NSString *senderUsername;
@property(nonatomic,strong,readonly,nullable) UIImage *image;
@property(nonatomic,copy,readonly,nullable) NSString *revision;
@property(nonatomic,readonly,getter=isVisible) BOOL visible;
@property(nonatomic,getter=isPlaybackPending) BOOL playbackPending;
/// A poll is a snapshot. genuineArrival means the monitor observed a new message,
/// rather than rediscovering an existing unread conversation after navigation.
- (void)observeUnreadSession:(nullable WPQuickChatSession *)session genuineArrival:(BOOL)genuineArrival;
/// Reconcile a specific contact from typed native metadata. Unknown never clears
/// a receipt; an incoming hook receives a short grace for unread propagation.
- (void)reconcileConversationUsername:(NSString *)username unreadState:(WPQuickChatUnreadState)state;
/// Register a validated receive before starting its capsule. Returned receipt is
/// independent of the wrapper's lifetime and its message text.
- (nullable NSString *)markBarrageMessageReceived:(WPBarrageMessage *)message;
- (BOOL)shouldDockMessage:(WPBarrageMessage *)message;
- (BOOL)dockMessage:(WPBarrageMessage *)message image:(nullable UIImage *)image;
/// Confirm the revision captured when opening chat. A later revision survives.
/// The return value says whether the currently visible indicator was cleared.
- (BOOL)consumeRevision:(NSString *)revision;
/// A user initiated clear acknowledges the current message, just like opening it.
- (void)clear;
/// Lifecycle cleanup can release pixels without forgetting confirmations/routes.
- (void)releaseImageKeepingIdentity;
- (void)resetVisibleOnly;
/// Counts only, suitable for diagnostics and fixture assertions.
- (NSDictionary<NSString *,NSNumber *> *)diagnostics;
@end
NS_ASSUME_NONNULL_END
