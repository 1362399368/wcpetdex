#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, WPTapAction) {
    /// Couple editions only: opens the selected partner's chat.
    WPTapActionPartnerChat = 0,
    WPTapActionQuickChat = 1,
    WPTapActionSettings = 2,
    WPTapActionChatAdvisor = 3,
    WPTapActionDirectAdvisor = 4,
};

/// Migrate the 0.4.x single-tap behavior once, then keep the gesture independent of the switch.
FOUNDATION_EXPORT WPTapAction WPConfiguredTapAction(BOOL doubleTap);
FOUNDATION_EXPORT void WPSetConfiguredTapAction(BOOL doubleTap, WPTapAction action);
FOUNDATION_EXPORT void WPResetQuickChatTapActions(void);
/// Tap actions this edition offers, in settings order.
FOUNDATION_EXPORT NSArray<NSNumber *> *WPAvailableTapActions(void);
/// Gesture action identifiers: none, menu (long press only), quickChat, settings, moments, advisor, advisorDirect, advisorHistory;
/// couple editions add partnerChat and interactions (the interaction log).
FOUNDATION_EXPORT NSString *WPConfiguredGestureAction(BOOL longPress);
FOUNDATION_EXPORT void WPSetConfiguredGestureAction(BOOL longPress, NSString *action);

NS_ASSUME_NONNULL_END
