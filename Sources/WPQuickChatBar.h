#import <UIKit/UIKit.h>
#import "WPQuickChatModel.h"

NS_ASSUME_NONNULL_BEGIN
/// The left-edge column of recent chats opened by tapping the pet.
@interface WPQuickChatBar : UIView
@property (nonatomic, copy, nullable) void (^onSelect)(NSString *username);
/// 0 half screen, 1 full screen, 2 contextual menu; used by tap and hold.
@property (nonatomic, copy, nullable) void (^onSelectWithMode)(NSString *username, NSInteger mode);
/// nil shows the "cannot read" state; an empty array the "no chats" state.
- (void)reloadWithSessions:(nullable NSArray<WPQuickChatSession *> *)sessions;
@property (nonatomic, readonly) NSArray<WPQuickChatSession *> *sessions;
/// Name shown for a row (remark, nickname or group name).
- (NSString *)titleForUsername:(NSString *)username;
/// WeChat's head image, or a lettered placeholder when unavailable.
- (UIImage *)avatarForUsername:(NSString *)username side:(CGFloat)side;
@end
NS_ASSUME_NONNULL_END
