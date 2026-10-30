#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
/// All callbacks run on the main queue; received events are persisted before ACK.
@interface WPCoupleClient : NSObject
/// Called once per newly stored event; needsResponse is the stored badge decision.
@property(nonatomic,copy,nullable) void (^onInteraction)(NSString *kind,NSString *identifier,NSDate *sentAt,BOOL needsResponse);
@property(nonatomic,copy,nullable) void (^onDelivered)(NSString *kind);
@property(nonatomic,copy,nullable) void (^onStatusChange)(NSString *status);
@property(nonatomic,copy,nullable) void (^onPeerStatusChange)(void);
@property(nonatomic,readonly,getter=isConnected) BOOL connected;
@property(nonatomic,readonly) BOOL hasSavedToken;
/// Server clock minus local clock, from the WebSocket handshake Date header.
/// Zero unless the local clock is off by at least 5 seconds.
@property(nonatomic,readonly) NSTimeInterval serverClockOffset;
- (NSString *)peerStatusText;
/// True only while a protocol 3 connection has a fresh online snapshot.
- (BOOL)peerIsOnline;
- (BOOL)configureURL:(nullable NSURL *)url pairToken:(NSString *)token;
- (void)clearConfiguration;
- (void)connect;
- (void)disconnect;
/// accepted is YES only after the server confirms persistence; an offline
/// local queue write reports NO while retaining the row for retry.
- (void)sendInteraction:(NSString *)kind completion:(void (^)(BOOL accepted,NSString *message))completion;
- (void)sendMissYou:(void (^)(BOOL accepted,NSString *message))completion;
@end
NS_ASSUME_NONNULL_END
