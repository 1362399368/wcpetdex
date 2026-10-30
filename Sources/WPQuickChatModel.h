#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
/// One row of WeChat's recent-chat list. Holds identifiers and counts only,
/// never message content. Foundation only so the offline tests can link it.
@interface WPQuickChatSession : NSObject
@property (nonatomic, copy) NSString *username;
@property (nonatomic) NSUInteger unread;
/// NO when WeChat's count is unreadable; such rows never count as new.
@property (nonatomic) BOOL unreadKnown;
@property (nonatomic) BOOL muted;
@property (nonatomic) BOOL pinned;
/// Seconds since 1970 of the latest message; 0 when unknown.
@property (nonatomic) NSTimeInterval time;
+ (instancetype)sessionWithUsername:(NSString *)username unread:(NSUInteger)unread muted:(BOOL)muted pinned:(BOOL)pinned time:(NSTimeInterval)time;
/// Unread and not muted: may flash the pet and light the blue dot.
@property (nonatomic, readonly) BOOL alertable;
@end

/// Aggregate holders (subscriptions, services, folded groups) have no single
/// contact to open, so the quick chat bar leaves them out.
FOUNDATION_EXPORT BOOL WPQuickChatIsOpenableUsername(NSString *username);
/// WeChat's own order is kept when available; otherwise pinned rows first,
/// then latest message first. Unopenable rows and duplicates are removed.
FOUNDATION_EXPORT NSArray<WPQuickChatSession *> *WPQuickChatOrdered(NSArray<WPQuickChatSession *> *sessions, BOOL nativeOrder);

/// Tracks unread counts between polls. The first observation of the list is
/// a baseline and never reports arrivals.
@interface WPQuickChatTracker : NSObject
@property (nonatomic, readonly) BOOL hasBaseline;
/// Usernames whose unread count is known and alertable.
@property (nonatomic, readonly) NSSet<NSString *> *alertableUsernames;
@property (nonatomic, readonly) BOOL hasAlertableUnread;
/// Merges an observation of some rows. With reportArrivals, returns usernames
/// whose unread count rose (alertable only), in the order given. Use it for
/// the top of the list, where a new message moves its chat; background scans
/// of older rows pass NO so long-standing unread chats are never "new".
- (NSArray<NSString *> *)observe:(NSArray<WPQuickChatSession *> *)sessions reportArrivals:(BOOL)reportArrivals;
/// After a complete scan: forgets chats that are no longer in the list.
- (void)retainOnlyUsernames:(NSSet<NSString *> *)usernames;
/// Next observation becomes a new baseline (after returning to foreground).
- (void)resetBaseline;
@end
NS_ASSUME_NONNULL_END
