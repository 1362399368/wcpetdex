#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
/// Thread-safe, body-free admission before a native callback reaches a UI queue.
/// A queued or running delivery occupies the sole slot across lifecycle changes.
@interface WPNativeRefreshGate : NSObject
- (instancetype)initWithQueue:(dispatch_queue_t)queue delay:(NSTimeInterval)delay delivery:(void (^)(NSUInteger generation))delivery;
- (void)setEnabled:(BOOL)enabled foreground:(BOOL)foreground;
- (void)signal;
- (NSDictionary<NSString *,NSNumber *> *)diagnostics;
@end
NS_ASSUME_NONNULL_END
