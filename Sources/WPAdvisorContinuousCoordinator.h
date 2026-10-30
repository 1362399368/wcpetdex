#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
/// Coordinates explicitly selected private conversations. All callbacks are
/// delivered on the main queue. Message bodies are never retained here.
@interface WPAdvisorContinuousCoordinator : NSObject
+ (instancetype)sharedCoordinator;
@property(nonatomic,copy,nullable) BOOL (^onReady)(NSString *username);
@property(nonatomic,copy,nullable) BOOL (^isBusy)(NSString *username);
@property(nonatomic,copy,nullable) void (^onIncoming)(NSString *username);
/// Bounded, ephemeral message text, delivered on main only after opt-in and deduplication.
@property(nonatomic,copy,nullable) void (^onMessage)(NSString *username,NSString *identifier,NSTimeInterval timestamp,NSString *text);
@property(nonatomic,readonly,copy) NSString *lockedUsername;
@property(nonatomic,readonly,copy) NSArray<NSString *> *enabledUsernames;
@property(nonatomic,readonly) BOOL hasEnabledContacts;
@property(nonatomic,readonly) BOOL acceptsNativeMessages;
/// Opaque account hash; read atomically to reject callbacks queued across account switches.
@property(atomic,readonly,copy) NSString *accountToken;
/// Reloads the active account's settings, clearing pending batches on switch.
- (void)refreshAccountIfNeeded;
@property(nonatomic,readonly,getter=isEnabled) BOOL enabled;
@property(nonatomic) BOOL foregroundAvailable;
- (void)setLockedUsername:(nullable NSString *)username;
- (void)setEnabled:(BOOL)enabled;
- (BOOL)isEnabledForUsername:(NSString *)username;
/// A per-contact opt-in. Effective only while that contact's continuous mode is enabled.
- (BOOL)requiresFreshAnalysisForUsername:(NSString *)username;
- (void)setRequiresFreshAnalysis:(BOOL)enabled forUsername:(NSString *)username;
- (BOOL)isFreshIncomingTimestamp:(NSTimeInterval)timestamp forUsername:(NSString *)username;
/// Runs a short native-wrapper read only while this contact is opted in and
/// foreground. Disable/background waits for any in-flight read to complete.
- (void)withNativeCaptureForUsername:(NSString *)username perform:(dispatch_block_t)capture;
/// Only pass a validated, fresh incoming private message with a stable ID.
- (void)noteIncomingUsername:(NSString *)username identifier:(NSString *)identifier createdAt:(NSTimeInterval)createdAt text:(NSString *)text;
- (void)taskDidFinishForUsername:(NSString *)username;
/// Retry an already due batch when the correct conversation becomes readable.
- (void)retryPending;
@end
NS_ASSUME_NONNULL_END
