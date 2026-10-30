#import <Foundation/Foundation.h>
#import "WPTapActions.h"

static NSUserDefaults *preferences;
NSUserDefaults *WPPreferences(void) { return preferences; }
static void check(BOOL condition, NSString *message) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
int main(void) {
    @autoreleasepool {
        preferences = [[NSUserDefaults alloc] initWithSuiteName:@"dev.zhour.wechatpet.tests.single.gestures"];
        [preferences removePersistentDomainForName:@"dev.zhour.wechatpet.tests.single.gestures"];
        check(WPConfiguredTapAction(NO)==WPTapActionQuickChat, @"single tap default");
        check(WPConfiguredTapAction(YES)==WPTapActionSettings, @"double tap default");
        check([WPConfiguredGestureAction(YES) isEqualToString:@"menu"], @"long-press default");
        check([WPConfiguredGestureAction(NO) isEqualToString:@"quickChat"], @"shake default");
        for (NSString *action in @[@"none", @"menu", @"quickChat", @"settings", @"moments", @"advisor"]) {
            WPSetConfiguredGestureAction(YES, action);
            check([WPConfiguredGestureAction(YES) isEqualToString:action], @"long-press selection persists");
        }
        for (NSString *action in @[@"none", @"quickChat", @"settings", @"moments", @"advisor"]) {
            WPSetConfiguredGestureAction(NO, action);
            check([WPConfiguredGestureAction(NO) isEqualToString:action], @"shake selection persists");
        }
        WPSetConfiguredTapAction(NO,WPTapActionDirectAdvisor);WPSetConfiguredTapAction(YES,WPTapActionChatAdvisor);
        check(WPConfiguredTapAction(NO)==WPTapActionDirectAdvisor && WPConfiguredTapAction(YES)==WPTapActionChatAdvisor,@"direct and menu advisor taps persist independently");
        WPSetConfiguredGestureAction(YES,@"advisorDirect");
        check([WPConfiguredGestureAction(YES) isEqualToString:@"advisorDirect"],@"direct advisor long press persists");
        WPSetConfiguredTapAction(NO,WPTapActionQuickChat);
        WPSetConfiguredGestureAction(NO, @"menu");
        check([WPConfiguredGestureAction(NO) isEqualToString:@"advisor"], @"invalid shake action ignored");
        WPSetConfiguredGestureAction(YES, @"quickChat"); WPSetConfiguredGestureAction(NO, @"quickChat");
        WPResetQuickChatTapActions();
        check(WPConfiguredTapAction(NO)==WPTapActionSettings, @"disabled quick chat tap resets");
        check([WPConfiguredGestureAction(YES) isEqualToString:@"menu"] && [WPConfiguredGestureAction(NO) isEqualToString:@"none"], @"disabled quick chat gestures reset");
        [preferences removePersistentDomainForName:@"dev.zhour.wechatpet.tests.single.gestures"];
        puts("PASS: single-edition gesture preferences");
    }
    return 0;
}
