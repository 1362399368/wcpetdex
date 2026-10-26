#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, WPTapAction) {
    WPTapActionPartnerChat = 0,
    WPTapActionQuickChat = 1,
    WPTapActionSettings = 2,
};

/// Migrate the 0.4.x single-tap behavior once, then keep the gesture independent of the switch.
FOUNDATION_EXPORT WPTapAction WPConfiguredTapAction(BOOL doubleTap);
FOUNDATION_EXPORT void WPSetConfiguredTapAction(BOOL doubleTap, WPTapAction action);
FOUNDATION_EXPORT void WPResetQuickChatTapActions(void);

NS_ASSUME_NONNULL_END
