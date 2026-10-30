#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSString * const WPCoupleHistoryDidChangeNotification;
FOUNDATION_EXPORT NSString *WPInteractionTitle(NSString *kind);
/// A miss received later than this after it was sent needs a response.
FOUNDATION_EXPORT const NSTimeInterval WPMissResponseWindow;

/// Only fixed pet interactions are stored; no WeChat messages or contacts.
///
/// Incoming rows keep separate facts: received_at, animation_played,
/// needs_response, resolved_at and resolve_type (reply / manual_clear).
/// The badge and the persistent angry look are derived from needs_response;
/// playing or opening anything never changes it.
@interface WPCoupleHistory : NSObject
+ (instancetype)sharedHistory;
- (instancetype)initWithURL:(NSURL *)url;
@property(nonatomic,readonly) NSArray<NSDictionary *> *pendingOutgoing;
/// All rows, newest first by sent_at.
@property(nonatomic,readonly) NSArray<NSDictionary *> *recentInteractions;
@property(nonatomic,readonly) NSUInteger pendingCount;
/// Received interactions that still need a response, newest first.
@property(nonatomic,readonly) NSArray<NSDictionary *> *pendingIncoming;
/// Pending received events not already reserved by a locally queued reply.
/// A failed or expired reply does not reserve its original snapshot.
@property(nonatomic,readonly) NSArray<NSString *> *uncoveredPendingIncomingIdentifiers;
/// The exact response snapshot for a new send. Miss covers only ordinary
/// overdue reminders; pet also reserves one oldest anger.
- (NSArray<NSString *> *)responseIdentifiersForKind:(NSString *)kind;
@property(nonatomic,readonly) NSUInteger badgeCount;
/// YES while at least one received anger still needs a response.
@property(nonatomic,readonly) BOOL hasPendingAnger;
- (BOOL)enqueueKind:(NSString *)kind identifier:(NSString *)identifier at:(NSDate *)date;
/// For miss and pet: stores this exact snapshot on the outgoing row. The snapshot
/// is resolved as "reply" once the server has accepted the miss; until then,
/// and after failure or expiry, the received rows keep needing a response.
- (BOOL)enqueueKind:(NSString *)kind identifier:(NSString *)identifier at:(NSDate *)date
    resolvingIncomingIdentifiers:(NSArray<NSString *> *)identifiers;
/// Local only, never sent to the peer. Unknown or already resolved identifiers are idempotent.
- (BOOL)manuallyClearIncomingIdentifiers:(NSArray<NSString *> *)identifiers;
- (BOOL)updateIdentifier:(NSString *)identifier state:(NSString *)state serverTime:(nullable NSNumber *)stamp;
/// receivedAt should be the receive moment on the server clock where known.
- (BOOL)receiveKind:(NSString *)kind identifier:(NSString *)identifier at:(NSDate *)date
         receivedAt:(NSDate *)receivedAt isNew:(BOOL *)isNew;
- (BOOL)receiveKind:(NSString *)kind identifier:(NSString *)identifier at:(NSDate *)date isNew:(BOOL *)isNew;
- (BOOL)markAnimationPlayedIdentifiers:(NSArray<NSString *> *)identifiers;
- (void)expireOldOutgoing;
- (BOOL)expireAllPending;
/// Automatically purges records older than 3 days (72 hours).
- (void)purgeRecordsOlderThanThreeDays;
/// Removes incoming and outgoing records at the 72-hour boundary atomically.
- (BOOL)purgeRecordsExpiredAtDate:(NSDate *)date;
/// Bounded timing/count diagnostics only; no event identities or contents.
- (NSDictionary<NSString *,NSNumber *> *)diagnostics;
/// Manually clears all stored interaction history.
- (BOOL)clearAllHistory;
@end
NS_ASSUME_NONNULL_END
