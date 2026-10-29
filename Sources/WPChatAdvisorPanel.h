#import <UIKit/UIKit.h>
@class WPChatAdvice;

NS_ASSUME_NONNULL_BEGIN
/// The floating analysis card above a native chat. All calls run on main.
@interface WPChatAdvisorPanel : UIView
@property(nonatomic,copy) NSString *conversationUsername;
@property(nonatomic,copy,nullable) void (^onClose)(void);
@property(nonatomic,copy,nullable) void (^onRetry)(void);
/// Tapping fills a reply; long pressing requests a direct send.
@property(nonatomic,copy,nullable) void (^onPickReply)(NSString *reply);
@property(nonatomic,copy,nullable) void (^onSendReply)(NSString *reply);
- (void)showLoadingWithLineCount:(NSUInteger)count;
- (void)showAdvice:(WPChatAdvice *)advice lineCount:(NSUInteger)count;
- (void)showError:(NSString *)message;
/// Fits the card into bounds, keeping clear of the bottom input area.
- (void)layoutInBounds:(CGRect)bounds;
@end
NS_ASSUME_NONNULL_END
