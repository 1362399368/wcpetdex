#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
/// Main-queue delivery only. userInfo[@"message"] is a WPBarrageMessage.
/// The source never keeps a WeChat message wrapper, writes bodies, or downloads media.
FOUNDATION_EXPORT NSString * const WPMessageBarrageDidReceiveNotification;
FOUNDATION_EXPORT NSString * const WPMessageBarrageSourceStatusDidChangeNotification;
/// Unknown native metadata is distinct from an explicit privacy denial.
/// Initial admission requires Allowed. An already admitted capsule may retain
/// its short-lived snapshot across transient home/session/cache rebuilds.
typedef NS_ENUM(NSInteger, WPBarrageConversationEligibility) {
    WPBarrageConversationEligibilityUnknown,
    WPBarrageConversationEligibilityDenied,
    WPBarrageConversationEligibilityAllowed
};
FOUNDATION_EXPORT WPBarrageConversationEligibility WPMessageBarrageConversationEligibility(NSString *username);
FOUNDATION_EXPORT BOOL WPMessageBarrageConversationAllowed(NSString *username);

@interface WPMessageBarrageSource : NSObject
+ (instancetype)sharedSource;
@property(nonatomic,readonly) BOOL requiresSessionPolling;
/// Call from the foreground overlay lifecycle. Off immediately purges pending bodies.
- (void)setActive:(BOOL)active;
/// Transient interruption; preserves admission generation and queued identities.
- (void)setForegroundAvailable:(BOOL)available;
/// Adaptation route, bounded counts and status only; never usernames or content.
- (NSDictionary<NSString *, id> *)diagnostics;
@end
NS_ASSUME_NONNULL_END
