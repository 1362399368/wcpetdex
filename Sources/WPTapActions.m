#import "WPTapActions.h"
#import "WPCommon.h"

static NSString *WPTapPreferenceKey(BOOL doubleTap) {
    return doubleTap ? @"doubleTapAction" : @"singleTapAction";
}

static NSString *WPTapActionValue(WPTapAction action) {
    switch (action) {
        case WPTapActionPartnerChat: return @"partnerChat";
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
            [preferences setObject:[preferences boolForKey:@"quickChatEnabled"] ? @"quickChat" : @"partnerChat"
                           forKey:@"singleTapAction"];
        if (![preferences objectForKey:@"doubleTapAction"])
            [preferences setObject:@"settings" forKey:@"doubleTapAction"];
    }
}

WPTapAction WPConfiguredTapAction(BOOL doubleTap) {
    WPMigrateTapActionsIfNeeded();
    id value = [WPPreferences() objectForKey:WPTapPreferenceKey(doubleTap)];
    if ([value isKindOfClass:NSString.class]) {
        if ([value isEqualToString:@"partnerChat"]) return WPTapActionPartnerChat;
        if ([value isEqualToString:@"quickChat"]) return WPTapActionQuickChat;
        if ([value isEqualToString:@"settings"]) return WPTapActionSettings;
        if ([value isEqualToString:@"chatAdvisor"]) return WPTapActionChatAdvisor;
    }
    return doubleTap ? WPTapActionSettings : WPTapActionPartnerChat;
}

void WPSetConfiguredTapAction(BOOL doubleTap, WPTapAction action) {
    WPMigrateTapActionsIfNeeded();
    NSString *value = WPTapActionValue(action);
    if (value) [WPPreferences() setObject:value forKey:WPTapPreferenceKey(doubleTap)];
}

void WPResetQuickChatTapActions(void) {
    if (WPConfiguredTapAction(NO) == WPTapActionQuickChat)
        WPSetConfiguredTapAction(NO, WPTapActionPartnerChat);
    if (WPConfiguredTapAction(YES) == WPTapActionQuickChat)
        WPSetConfiguredTapAction(YES, WPTapActionSettings);
}
