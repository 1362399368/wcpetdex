#import <Foundation/Foundation.h>
#import "WPChatAdvisor.h"
NS_ASSUME_NONNULL_BEGIN
/// Opt-in, bounded, memory-only conversational context. Never saved to disk.
@interface WPAdvisorContextStore : NSObject
@property(class,nonatomic,readonly) WPAdvisorContextStore *sharedStore;
- (void)seedUsername:(NSString *)username visibleLines:(NSArray<WPChatLine *> *)lines;
- (void)appendIncomingForUsername:(NSString *)username identifier:(NSString *)identifier text:(NSString *)text date:(NSDate *)date;
- (nullable NSArray<WPChatLine *> *)snapshotForUsername:(NSString *)username;
- (void)removeUsername:(NSString *)username;
- (void)clear;
@end
NS_ASSUME_NONNULL_END
