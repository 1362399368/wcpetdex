#import "WPTapActions.h"
#import "WPCommon.h"
#import "WPEdition.h"

static NSString *WPTapPreferenceKey(BOOL doubleTap) {
    return doubleTap ? @"doubleTapAction" : @"singleTapAction";
}

static NSString *WPTapActionValue(WPTapAction action) {
    switch (action) {
        case WPTapActionPartnerChat: return WP_EDITION_COUPLE ? @"partnerChat" : nil;
        case WPTapActionQuickChat: return @"quickChat";
        case WPTapActionSettings: return @"settings";
        case WPTapActionChatAdvisor: return @"chatAdvisor";
        case WPTapActionDirectAdvisor: return @"directAdvisor";
    }
    return nil;
}

static void WPMigrateTapActionsIfNeeded(void) {
    NSUserDefaults *preferences=WPPreferences();
    @synchronized (preferences) {
        // Couple editions keep their 1.2 migration: the partner chat unless
        // quick chat was already on.
        if (![preferences objectForKey:@"singleTapAction"])
            [preferences setObject:(!WP_EDITION_COUPLE || [preferences boolForKey:@"quickChatEnabled"]) ? @"quickChat" : @"partnerChat"
                           forKey:@"singleTapAction"];
        if (![preferences objectForKey:@"doubleTapAction"])
            [preferences setObject:@"settings" forKey:@"doubleTapAction"];
    }
}

WPTapAction WPConfiguredTapAction(BOOL doubleTap) {
    WPMigrateTapActionsIfNeeded();
    id value = [WPPreferences() objectForKey:WPTapPreferenceKey(doubleTap)];
    if ([value isKindOfClass:NSString.class]) {
        if (WP_EDITION_COUPLE && [value isEqualToString:@"partnerChat"]) return WPTapActionPartnerChat;
        if ([value isEqualToString:@"quickChat"]) return WPTapActionQuickChat;
        if ([value isEqualToString:@"settings"]) return WPTapActionSettings;
        if ([value isEqualToString:@"chatAdvisor"]) return WPTapActionChatAdvisor;
        if ([value isEqualToString:@"directAdvisor"]) return WPTapActionDirectAdvisor;
    }
    return doubleTap ? WPTapActionSettings : (WP_EDITION_COUPLE ? WPTapActionPartnerChat : WPTapActionQuickChat);
}

void WPSetConfiguredTapAction(BOOL doubleTap, WPTapAction action) {
    WPMigrateTapActionsIfNeeded();
    NSString *value = WPTapActionValue(action);
    if (value) [WPPreferences() setObject:value forKey:WPTapPreferenceKey(doubleTap)];
}

void WPResetQuickChatTapActions(void) {
    if (WPConfiguredTapAction(NO) == WPTapActionQuickChat)
        WPSetConfiguredTapAction(NO, WP_EDITION_COUPLE ? WPTapActionPartnerChat : WPTapActionSettings);
    if (WPConfiguredTapAction(YES) == WPTapActionQuickChat)
        WPSetConfiguredTapAction(YES, WPTapActionSettings);
    if ([WPConfiguredGestureAction(YES) isEqualToString:@"quickChat"]) WPSetConfiguredGestureAction(YES,@"menu");
    if ([WPConfiguredGestureAction(NO) isEqualToString:@"quickChat"]) WPSetConfiguredGestureAction(NO,@"none");
}

NSArray<NSNumber *> *WPAvailableTapActions(void) {
    NSArray *common = @[@(WPTapActionQuickChat), @(WPTapActionSettings), @(WPTapActionChatAdvisor), @(WPTapActionDirectAdvisor)];
    return WP_EDITION_COUPLE ? [@[@(WPTapActionPartnerChat)] arrayByAddingObjectsFromArray:common] : common;
}

static NSArray<NSString *> *WPAllowedGestureActions(BOOL longPress) {
    NSMutableArray *allowed = [@[@"none", @"quickChat", @"settings", @"moments", @"advisor", @"advisorDirect", @"advisorHistory"] mutableCopy];
    if (longPress) [allowed insertObject:@"menu" atIndex:1];
    if (WP_EDITION_COUPLE) [allowed addObjectsFromArray:@[@"partnerChat", @"interactions"]];
    return allowed;
}
NSString *WPConfiguredGestureAction(BOOL longPress) {
    NSString *value = [WPPreferences() stringForKey:longPress ? @"longPressAction" : @"shakeAction"];
    // Couple editions have always opened the interaction log with a shake.
    NSString *fallback = longPress ? @"menu" : (WP_EDITION_COUPLE ? @"interactions" : @"quickChat");
    return [WPAllowedGestureActions(longPress) containsObject:value] ? value : fallback;
}
void WPSetConfiguredGestureAction(BOOL longPress, NSString *action) {
    if ([WPAllowedGestureActions(longPress) containsObject:action]) [WPPreferences() setObject:action forKey:longPress ? @"longPressAction" : @"shakeAction"];
}
