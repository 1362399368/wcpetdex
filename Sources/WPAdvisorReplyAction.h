#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
typedef NS_ENUM(NSInteger, WPAdvisorReplyOutcome) {
    WPAdvisorReplyFilled, WPAdvisorReplySendTriggered, WPAdvisorReplyDraftPresent,
    WPAdvisorReplyWrongChat, WPAdvisorReplyInputUnavailable, WPAdvisorReplySendUnavailable
};
/// Uses only a visible, matching native chat. Existing input is never overwritten.
FOUNDATION_EXPORT WPAdvisorReplyOutcome WPAdvisorApplyReply(NSString *reply, NSString *username, UIViewController * _Nullable chat, BOOL send);
NS_ASSUME_NONNULL_END
