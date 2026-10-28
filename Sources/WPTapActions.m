#import "WPTapActions.h"
#import "WPCommon.h"

static NSString *WPTapPreferenceKey(BOOL doubleTap) {
    return doubleTap ? @"doubleTapAction" : @"singleTapAction";
}

static NSString *WPTapActionValue(WPTapAction action) {
    switch (action) {
        case WPTapActionQuickChat: return @"quickChat";
        case WPTapActionSettings: return @"settings";
        case WPTapActionChatAdvisor: return @"chatAdvisor";
    }
    return nil;
}

static void WPMigrateTapActionsIfNeeded(void) {
    NSUserDefaults *preferences=WPPreferences();
    @synchronized (preferences) {
        if (![preferences objectForKey:@"singleTapAction"])
            [preferences setObject:@"quickChat"
                           forKey:@"singleTapAction"];
        if (![preferences objectForKey:@"doubleTapAction"])
            [preferences setObject:@"settings" forKey:@"doubleTapAction"];
    }
}

WPTapAction WPConfiguredTapAction(BOOL doubleTap) {
    WPMigrateTapActionsIfNeeded();
    id value = [WPPreferences() objectForKey:WPTapPreferenceKey(doubleTap)];
    if ([value isKindOfClass:NSString.class]) {
        if ([value isEqualToString:@"quickChat"]) return WPTapActionQuickChat;
        if ([value isEqualToString:@"settings"]) return WPTapActionSettings;
        if ([value isEqualToString:@"chatAdvisor"]) return WPTapActionChatAdvisor;
    }
    return doubleTap ? WPTapActionSettings : WPTapActionQuickChat;
}

void WPSetConfiguredTapAction(BOOL doubleTap, WPTapAction action) {
    WPMigrateTapActionsIfNeeded();
    NSString *value = WPTapActionValue(action);
    if (value) [WPPreferences() setObject:value forKey:WPTapPreferenceKey(doubleTap)];
}

void WPResetQuickChatTapActions(void) {
    if (WPConfiguredTapAction(NO) == WPTapActionQuickChat)
        WPSetConfiguredTapAction(NO, WPTapActionSettings);
    if (WPConfiguredTapAction(YES) == WPTapActionQuickChat)
        WPSetConfiguredTapAction(YES, WPTapActionSettings);
    if ([WPConfiguredGestureAction(YES) isEqualToString:@"quickChat"]) WPSetConfiguredGestureAction(YES,@"menu");
    if ([WPConfiguredGestureAction(NO) isEqualToString:@"quickChat"]) WPSetConfiguredGestureAction(NO,@"none");
}

NSString *WPConfiguredGestureAction(BOOL longPress) {
    NSString *value = [WPPreferences() stringForKey:longPress ? @"longPressAction" : @"shakeAction"];
    NSArray *allowed = longPress ? @[@"none", @"menu", @"quickChat", @"settings", @"moments", @"advisor"] : @[@"none", @"quickChat", @"settings", @"moments", @"advisor"];
    return [allowed containsObject:value] ? value : (longPress ? @"menu" : @"quickChat");
}
void WPSetConfiguredGestureAction(BOOL longPress, NSString *action) {
    NSArray *allowed = longPress ? @[@"none", @"menu", @"quickChat", @"settings", @"moments", @"advisor"] : @[@"none", @"quickChat", @"settings", @"moments", @"advisor"];
    if ([allowed containsObject:action]) [WPPreferences() setObject:action forKey:longPress ? @"longPressAction" : @"shakeAction"];
}
