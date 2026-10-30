#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
/// Status shown under a bubble. Incoming: 待回应 / 已回应 / 已接收 / 手动清除
/// (local only). A miss that never needed a response is 已接收, not 已回应.
FOUNDATION_EXPORT NSString *WPInteractionStatusText(NSDictionary *row);

/// Two-person bubbles: TA on the left, me on the right, newest at the top.
@interface WPInteractionLogController : UITableViewController
@property(nonatomic,copy,nullable) void (^onClose)(void);
@property(nonatomic,readonly) NSArray<NSDictionary *> *rows;
@property(nonatomic,readonly) UIButton *replyButton;
@property(nonatomic,readonly) UIButton *clearButton;
/// Sends one miss that replies to every interaction pending at this moment.
- (void)replyAll;
/// Two confirmations; the snapshot is taken before the first one.
- (void)clearMyBadge;
@end
NS_ASSUME_NONNULL_END
