#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
typedef NS_ENUM(NSInteger, WPAdvisorReplyOutcome) {
    WPAdvisorReplyFilled, WPAdvisorReplySendTriggered, WPAdvisorReplyDraftPresent,
    WPAdvisorReplyWrongChat, WPAdvisorReplyInputUnavailable, WPAdvisorReplySendUnavailable
};
/// Uses only a visible, matching native chat. Existing input is never overwritten.
FOUNDATION_EXPORT WPAdvisorReplyOutcome WPAdvisorApplyReply(NSString *reply, NSString *username, UIViewController * _Nullable chat, BOOL send);
/// Checks the current composer before a presentation change without modifying it.
FOUNDATION_EXPORT WPAdvisorReplyOutcome WPAdvisorCheckReplyInput(NSString *username, UIViewController * _Nullable chat);
/// Attempts to send only if the original text still occupies the matching chat input.
FOUNDATION_EXPORT WPAdvisorReplyOutcome WPAdvisorSendFilledReply(NSString *reply, NSString *username, UIViewController * _Nullable chat);
NS_ASSUME_NONNULL_END
