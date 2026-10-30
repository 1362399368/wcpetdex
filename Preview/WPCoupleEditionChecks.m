#import <UIKit/UIKit.h>
#import "WPCommon.h"
#import "WPEdition.h"
#import "WPOverlay.h"
#import "WPPetRenderer.h"
#import "WPTapActions.h"
#import "WPMenuConfiguration.h"
#import "WPRadialMenu.h"
#import "WPCoupleClient.h"
#import "WPCoupleHistory.h"
#import "WPBackendConfiguration.h"

// Couple-edition checks: storage identity, bundled pet, gestures, menu,
// settings entries, the interaction badge and sending through the client.
// Network sends go to a spy; the pairing endpoint is never contacted.

@interface WPOverlayManager (WPCoupleEditionTesting)
- (UIWindow *)activeWindow;
@end

@interface WPCoupleEditionClientSpy : WPCoupleClient
@property(nonatomic) NSMutableArray<NSString *> *sentKinds;
@end
@implementation WPCoupleEditionClientSpy
- (void)connect {}
- (void)disconnect {}
- (void)sendInteraction:(NSString *)kind completion:(void (^)(BOOL,NSString *))completion {
    if(!self.sentKinds)self.sentKinds=[NSMutableArray new];
    [self.sentKinds addObject:kind];if(completion)completion(NO,@"preview send intercepted");
}
@end

static UIView *WPCoupleFindView(UIView *root, NSString *identifier) {
    if ([root.accessibilityIdentifier isEqualToString:identifier]) return root;
    for (UIView *child in root.subviews) {UIView *found=WPCoupleFindView(child,identifier);if(found)return found;}
    return nil;
}
static BOOL WPCoupleContainsText(UIView *root, NSString *fragment) {
    if ([root isKindOfClass:UILabel.class] && [((UILabel *)root).text containsString:fragment]) return YES;
    if ([root isKindOfClass:UIButton.class] && [((UIButton *)root).currentTitle containsString:fragment]) return YES;
    if ([root.accessibilityLabel containsString:fragment]) return YES;
    for (UIView *child in root.subviews) if (WPCoupleContainsText(child, fragment)) return YES;
    return NO;
}
static UIViewController *WPCoupleLoaded(NSString *className, CGRect frame) {
    UIViewController *controller=[NSClassFromString(className) new];
    controller.view.frame=frame;[controller viewWillAppear:NO];[controller.view setNeedsLayout];[controller.view layoutIfNeeded];
    return controller;
}
static void WPCoupleRestore(NSDictionary *saved) {
    for(NSString *key in saved){id value=saved[key];if(value==NSNull.null)[WPPreferences() removeObjectForKey:key];else [WPPreferences() setObject:value forKey:key];}
}
static NSDictionary *WPCoupleSave(NSArray<NSString *> *keys) {
    NSMutableDictionary *saved=[NSMutableDictionary new];
    for(NSString *key in keys)saved[key]=[WPPreferences() objectForKey:key]?:NSNull.null;
    return saved;
}

NSDictionary<NSString *,NSNumber *> *WPCoupleEditionPreviewChecks(CGRect frame) {
    NSMutableDictionary *checks=[NSMutableDictionary new];
    BOOL aria=WP_EDITION_ARIA;

    // Storage stays that of the earlier couple releases.
    checks[@"coupleStorageKeepsLegacyIdentity"]=@([WPEditionPreferencesSuite() isEqualToString:@"dev.zhour.wechatpet"] &&
        [WPDataDirectory().lastPathComponent isEqualToString:@"WeChatPet"] && [WPResourceBundle().bundlePath.lastPathComponent isEqualToString:@"WeChatPet.bundle"]);
    checks[@"coupleBackendConfigBundled"]=@(WPBackendConfiguration().count>0 && [[WPPreferences() stringForKey:@"coupleURL"] hasPrefix:@"wss://"]);

    // The bundled default pet loads as a paged atlas, not the fallback drawing.
    WPPetRenderer *renderer=[[WPPetRenderer alloc] initWithFrame:CGRectMake(0,0,120,130)];
    NSDictionary *metadata=[renderer valueForKey:@"metadata"];
    NSString *expectedID=aria?@"aria-exclusive-zhouyou":@"yue-zhour-20261021";
    checks[@"coupleDefaultPetLoads"]=@([metadata[@"id"] isEqual:expectedID] && [[renderer valueForKey:@"rowAtlasPaths"] count]>0 && ((UIImage *)[renderer valueForKey:@"atlas"]).CGImage!=NULL);
    checks[@"coupleAriaPlaybackMatchesEdition"]=@([[renderer valueForKey:@"bundledAria"] boolValue]==aria);
    checks[@"coupleReactionsPlay"]=@([renderer playReaction:@"miss"] || [renderer playSemanticAction:@"receiveMiss"]);
    renderer.angry=YES;BOOL angry=renderer.isAngry;renderer.angry=NO;
    checks[@"coupleAngryLookToggles"]=@(angry && !renderer.isAngry);
    [renderer setAnimationActive:NO];

    // Gestures keep the 1.2 couple defaults and offer partner actions.
    NSDictionary *gestureKeys=WPCoupleSave(@[@"singleTapAction",@"doubleTapAction",@"shakeAction",@"longPressAction",@"quickChatEnabled"]);
    for(NSString *key in gestureKeys)[WPPreferences() removeObjectForKey:key];
    [WPPreferences() setBool:NO forKey:@"quickChatEnabled"];
    checks[@"coupleSingleTapDefaultsToPartner"]=@(WPConfiguredTapAction(NO)==WPTapActionPartnerChat);
    checks[@"coupleShakeDefaultsToInteractions"]=@([WPConfiguredGestureAction(NO) isEqualToString:@"interactions"]);
    WPSetConfiguredGestureAction(YES,@"partnerChat");
    checks[@"couplePartnerGestureAccepted"]=@([WPConfiguredGestureAction(YES) isEqualToString:@"partnerChat"]);
    checks[@"coupleTapActionsListPartnerFirst"]=@([WPAvailableTapActions().firstObject integerValue]==WPTapActionPartnerChat);
    WPCoupleRestore(gestureKeys);

    // The long-press menu starts with the original couple items.
    NSDictionary *menuKeys=WPCoupleSave(@[@"radialMenuOrder",@"radialMenuEnabled"]);
    WPMenuResetActions();
    NSArray *enabled=WPMenuEnabledActions();
    checks[@"coupleMenuDefaultsIncludeInteractions"]=@(enabled.count>=3 && [[enabled subarrayWithRange:NSMakeRange(0,3)] isEqual:@[@"moments",@"miss",@"anger"]]);
    WPRadialMenuView *menu=[[WPRadialMenuView alloc] initWithFrame:frame];
    NSArray *buttons=[menu valueForKey:@"allButtons"];
    NSMutableArray *identifiers=[NSMutableArray new];for(id button in buttons)[identifiers addObject:[button valueForKey:@"actionIdentifier"]];
    checks[@"coupleMenuHasInteractionButtons"]=@([identifiers containsObject:@"miss"] && [identifiers containsObject:@"anger"]);
    // Stealth disables sending only in Zhouyou's edition.
    NSDictionary *stealthKeys=WPCoupleSave(@[@"stealthEnabled"]);
    [WPPreferences() setBool:YES forKey:@"stealthEnabled"];
    id missButton=nil;for(id button in buttons)if([[button valueForKey:@"actionIdentifier"] isEqual:@"miss"])missButton=button;
    checks[@"coupleStealthMatchesEdition"]=@([[missButton valueForKey:@"sendDisabled"] boolValue]==WP_FEATURE_STEALTH);
    WPCoupleClient *client=[WPCoupleClient new];
    checks[@"coupleClientStealthMatchesEdition"]=@(client.stealthEnabled==WP_FEATURE_STEALTH && (WP_FEATURE_STEALTH || ![WPPreferences() objectForKey:@"stealthEnabled"]));
    WPCoupleRestore(stealthKeys);
    WPCoupleRestore(menuKeys);

    // Settings show the couple section and only this edition's options.
    UIViewController *home=WPCoupleLoaded(@"WPSettingsController",frame);
    checks[@"coupleHomeStatusCardVisible"]=@(WPCoupleFindView(home.view,@"WPCoupleStatusCard")!=nil);
    checks[@"coupleHomeEntriesVisible"]=@(WPCoupleContainsText(home.view,@"情侣互动") && WPCoupleContainsText(home.view,@"互动记录") && WPCoupleContainsText(home.view,@"配对与连接"));
    checks[@"coupleHomeBrandMatchesEdition"]=@(WPCoupleContainsText(home.view,aria?@"Aria专属版":@"周游专属包"));
    UIViewController *couple=WPCoupleLoaded(@"WPCoupleSettingsController",frame);
    checks[@"coupleCheckinMatchesEdition"]=@(WPCoupleContainsText(couple.view,@"上班打卡提醒")==WP_FEATURE_WORK_CHECKIN);
    checks[@"couplePreviewButtonsVisible"]=@(WPCoupleFindView(couple.view,@"WPLocalPreviewMiss") && WPCoupleFindView(couple.view,@"WPLocalPreviewAnger"));
    UIViewController *connection=WPCoupleLoaded(@"WPConnectionSettingsController",frame);
    checks[@"coupleConnectionStealthMatchesEdition"]=@(WPCoupleContainsText(connection.view,@"隐身")==WP_FEATURE_STEALTH && WPCoupleContainsText(connection.view,@"服务地址"));
    UIViewController *appearance=WPCoupleLoaded(@"WPAppearanceSettingsController",frame);
    checks[@"coupleBadgePositionSettingsVisible"]=@(WPCoupleFindView(appearance.view,@"WPInteractionBadgeOffsetX")!=nil);
    checks[@"coupleDefaultPetNamed"]=@(WPCoupleContainsText(appearance.view,[@"默认 " stringByAppendingString:WPEditionDefaultPetName()]));
    UIViewController *quick=WPCoupleLoaded(@"WPQuickActionsController",frame);
    UISegmentedControl *single=(id)WPCoupleFindView(quick.view,@"WPTapActionSingle");
    checks[@"coupleTapSettingOffersPartnerChat"]=@([single isKindOfClass:UISegmentedControl.class] && single.numberOfSegments==5 && [[single titleForSegmentAtIndex:0] isEqualToString:@"对象聊天"]);

    // A received anger shows the badge and angry look until it is cleared.
    UIViewController *controller=[WPOverlayManager.sharedManager activeWindow].rootViewController;
    UIView *badge=[controller respondsToSelector:NSSelectorFromString(@"badge")]?[controller valueForKey:@"badge"]:nil;
    WPPetRenderer *pet=[controller valueForKey:@"pet"];
    NSString *identifier=NSUUID.UUID.UUIDString.lowercaseString;BOOL isNew=NO;
    BOOL received=[WPCoupleHistory.sharedHistory receiveKind:@"anger" identifier:identifier at:NSDate.date isNew:&isNew];
    [NSNotificationCenter.defaultCenter postNotificationName:WPCoupleHistoryDidChangeNotification object:nil];
    BOOL shown=received && badge && !badge.hidden && pet.isAngry;
    [WPCoupleHistory.sharedHistory manuallyClearIncomingIdentifiers:@[identifier]];
    [NSNotificationCenter.defaultCenter postNotificationName:WPCoupleHistoryDidChangeNotification object:nil];
    checks[@"coupleAngerBadgeShownAndCleared"]=@(shown && badge.hidden && !pet.isAngry);

    // Menu interactions reach the pairing client unless stealth blocks them.
    WPCoupleEditionClientSpy *spy=[WPCoupleEditionClientSpy new];
    id original=[WPOverlayManager.sharedManager valueForKey:@"couple"];
    [WPOverlayManager.sharedManager setValue:spy forKey:@"couple"];
    SEL execute=NSSelectorFromString(@"execute:");
    if([controller respondsToSelector:execute]){
        ((void (*)(id,SEL,id))[controller methodForSelector:execute])(controller,execute,@"miss");
        ((void (*)(id,SEL,id))[controller methodForSelector:execute])(controller,execute,@"anger");
    }
    checks[@"coupleMenuSendsInteractions"]=@([spy.sentKinds isEqual:@[@"miss",@"anger"]]);
    [WPOverlayManager.sharedManager setValue:original forKey:@"couple"];
    return checks;
}
