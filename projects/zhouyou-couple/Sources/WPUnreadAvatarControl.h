#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
/// Displays one latest unread contact without retaining a chat-list cache.
@interface WPUnreadAvatarControl : UIControl
@property(nonatomic,copy,readonly,nullable) NSString *username;
- (void)showUsername:(NSString *)username title:(NSString *)title;
/// Reuses the same top-of-pet control for the barrage's retained message.
/// Group members supply the image, while the route remains the original group.
- (void)showConversationUsername:(NSString *)conversation senderUsername:(NSString *)sender image:(nullable UIImage *)image;
- (void)clearAvatar;
/// The overlay supplies foreground/feature visibility. Pausing cancels work.
- (void)setActive:(BOOL)active;
@end
NS_ASSUME_NONNULL_END
