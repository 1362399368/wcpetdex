#import <UIKit/UIKit.h>
/// Runtime-validated unread count of a WeChat session object; nil when unreadable.
FOUNDATION_EXPORT NSNumber *WPSessionUnreadCount(id session);
@interface WPActionAdapter : NSObject
+ (BOOL)supportsMarkAllRead;
/// Metadata only: last route, invocation and verification status; no chat data.
+ (NSDictionary<NSString *, id> *)lastMarkAllReadDiagnostics;
+ (void)performAction:(NSString *)action inWindow:(UIWindow *)window completion:(void(^)(BOOL success, NSString *message))completion;
@end
