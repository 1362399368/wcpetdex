#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface WPWorkCheckinReminder : NSObject
+ (instancetype)sharedReminder;
+ (NSString *)defaultMessage;
+ (BOOL)isEnabled;
/// Beijing-time Monday–Friday, [08:50:00, 08:55:00).
+ (BOOL)isWithinSendWindowAtDate:(NSDate *)date;
- (void)startWithSender:(void (^)(NSString *message, void (^completion)(BOOL invoked, NSString *status)))sender;
- (void)setForegroundAvailable:(BOOL)available;
@end
NS_ASSUME_NONNULL_END
