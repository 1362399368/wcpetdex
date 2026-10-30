#import "WPAria520EditionChecks.h"
#import "WPCommon.h"
#import "WPEdition.h"
#import "WPSettings.h"
#import "WPCoupleClient.h"
#import "WPOverlay.h"
#import "WPRadialMenu.h"
#import "WPResizableChat.h"
#import <math.h>

#if defined(WP_PREVIEW_HOST)
@interface WPCoupleClient (WPAria520Testing)
- (BOOL)validConfiguration;
- (void)handle:(NSDictionary *)event generation:(NSUInteger)generation;
- (void)sendJSON:(NSDictionary *)json generation:(NSUInteger)generation;
- (void)scheduleHeartbeatForGeneration:(NSUInteger)generation;
- (void)queryPendingStatuses:(NSArray<NSString *> *)identifiers offset:(NSUInteger)offset generation:(NSUInteger)generation;
- (void)transmitNext;
- (void)updateServerClockOffset;
@end
/// A local handshake fixture: it never connects or submits an interaction.
@interface WPAria520OfflineClient : WPCoupleClient
@property(nonatomic) NSUInteger networkStarts;
@end
@implementation WPAria520OfflineClient
- (BOOL)validConfiguration{return NO;}
- (void)connect{self.networkStarts++;}
- (void)sendJSON:(NSDictionary *)json generation:(NSUInteger)generation{}
- (void)scheduleHeartbeatForGeneration:(NSUInteger)generation{}
- (void)queryPendingStatuses:(NSArray<NSString *> *)identifiers offset:(NSUInteger)offset generation:(NSUInteger)generation{}
- (void)transmitNext{}
- (void)updateServerClockOffset{}
@end

static BOOL WPAria520ContainsText(UIView *view,NSString *text,BOOL exact){
    NSString *value=[view isKindOfClass:UILabel.class]?((UILabel *)view).text:view.accessibilityLabel;
    if(value && (exact?[value isEqual:text]:[value containsString:text]))return YES;
    for(UIView *child in view.subviews)if(WPAria520ContainsText(child,text,exact))return YES;
    return NO;
}
static UIView *WPAria520FindIdentifier(UIView *view,NSString *identifier){
    if([view.accessibilityIdentifier isEqual:identifier])return view;
    for(UIView *child in view.subviews){UIView *found=WPAria520FindIdentifier(child,identifier);if(found)return found;}
    return nil;
}

NSDictionary<NSString *,NSNumber *> *WPAria520EditionPreviewChecks(void){
    NSMutableDictionary *checks=[NSMutableDictionary new];
    id saved=[WPPreferences() objectForKey:@"stealthEnabled"];
    id savedFailure=[WPPreferences() objectForKey:@"lastSyncConnectionFailure"];
    BOOL animations=UIView.areAnimationsEnabled;[UIView setAnimationsEnabled:NO];
    @try{
        checks[@"A520EditionNameIsExact"]=@([WPEditionName() isEqual:@"Aria专属（游定制最终版）"]);
        checks[@"A520VersionAndBuildAre520"]=@([WPPluginVersion() isEqual:@"5.2.0"] && WP_BUILD_VERSION==5200 && WP_EDITION_ARIA==1);
        checks[@"A520OnlineAndPrivateFeatureSetRemainsAvailable"]=@(WPCanUsePrivateFeatures());
        checks[@"A520DefaultPetIsAriaInsteadOfZhouyou"]=@([[WPDefaultPetDirectory() lastPathComponent] isEqual:@"AriaPet"]);
        // Simulate an older installation that had the retired preference on.
        [WPPreferences() setBool:YES forKey:@"stealthEnabled"];
        WPAria520OfflineClient *client=[WPAria520OfflineClient new];
        checks[@"A520ClientRemovesRetiredPreferenceWithoutPairReset"]=@([WPPreferences() objectForKey:@"stealthEnabled"]==nil);
        [WPPreferences() setBool:YES forKey:@"stealthEnabled"];
        __block BOOL completed=NO;__block NSString *failure=nil;
        [client sendInteraction:@"miss" completion:^(BOOL accepted,NSString *message){completed=!accepted;failure=message;}];
        checks[@"A520StalePreferenceCannotBlockInteractionAdmission"]=@(completed && [failure containsString:@"令牌"] && ![failure containsString:@"隐身"] && client.networkStarts==0);
        checks[@"A520ClientHasNoStealthControlSelectors"]=@(![client respondsToSelector:NSSelectorFromString(@"stealthEnabled")] && ![client respondsToSelector:NSSelectorFromString(@"setStealthEnabled:")] && ![client respondsToSelector:NSSelectorFromString(@"stealthStatusText")]);
        checks[@"A520OverlayHasNoStealthControlSelectors"]=@(![WPOverlayManager.sharedManager respondsToSelector:NSSelectorFromString(@"setStealthEnabled:")] && ![WPOverlayManager.sharedManager respondsToSelector:NSSelectorFromString(@"stealthEnabled")]);
        NSUInteger generation=[[client valueForKey:@"generation"] unsignedIntegerValue];
        [client handle:@{@"type":@"ready",@"protocol":@3,@"hidden_applied":NSNull.null} generation:generation];
        checks[@"A520RetiredHiddenFieldCannotRejectNormalReady"]=@(client.connected && [[client valueForKey:@"protocolVersion"] integerValue]==3 && client.networkStarts==0);
        [client handle:@{@"type":@"peer_status",@"version":@1,@"server_time":@(NSDate.date.timeIntervalSince1970),@"online":@YES,@"last_online":@(NSDate.date.timeIntervalSince1970)} generation:generation];
        checks[@"A520PeerOnlineSnapshotStillWorks"]=@(client.peerIsOnline && [[client peerStatusText] containsString:@"在线"]);
        [client setValue:@NO forKey:@"connected"];
        WPSettingsController *page=[WPSettingsController new];[page loadViewIfNeeded];
        checks[@"A520SettingsContainsExactEditionBrand"]=@(WPAria520ContainsText(page.view,WPEditionName(),NO));
        checks[@"A520SettingsHasNoStealthText"]=@(!WPAria520ContainsText(page.view,@"隐身",NO));
        BOOL features=YES;for(NSString *text in @[@"情侣互动",@"互动记录",@"快捷功能",@"桌宠设置",@"配对与连接",@"聊天弹幕"]){features&=WPAria520ContainsText(page.view,text,YES);}
        checks[@"A520All125HomeFeaturesRemainVisible"]=@(features);
        checks[@"A520RecoveryPauseAndRetryRemainAvailable"]=@(WPAria520FindIdentifier(page.view,@"WPRecoveryPauseControl")!=nil && WPAria520FindIdentifier(page.view,@"WPRecoveryRetryControl")!=nil);
        WPRadialMenuView *menu=[[WPRadialMenuView alloc]initWithFrame:CGRectMake(0,0,390,844)];
        [menu showAroundPoint:CGPointMake(100,400) inBounds:menu.bounds];
        NSUInteger interactions=0;BOOL allowed=YES;
        for(UIControl *button in [menu valueForKey:@"allButtons"]){
            NSString *action=[button valueForKey:@"actionIdentifier"];
            if([@[@"miss",@"anger"] containsObject:action]){interactions++;allowed&=button.enabled && !(button.accessibilityTraits&UIAccessibilityTraitNotEnabled);}
        }
        checks[@"A520StalePreferenceDoesNotDisableInteractionMenu"]=@(interactions==2 && allowed);[menu cancel];
        checks[@"A520NativeChatRetains75PercentWithoutHeightMemory"]=@(fabs(WPResizableChatSavedHeightFraction()-.75)<.001 && ![[WPResizableChatController new] heightHoldPending]);
        checks[@"A520EditionChecksCompleted"]=@YES;
    }@catch(__unused NSException *error){checks[@"A520EditionChecksCompleted"]=@NO;}
    @finally{if(saved)[WPPreferences() setObject:saved forKey:@"stealthEnabled"];else [WPPreferences() removeObjectForKey:@"stealthEnabled"];if(savedFailure)[WPPreferences() setObject:savedFailure forKey:@"lastSyncConnectionFailure"];else [WPPreferences() removeObjectForKey:@"lastSyncConnectionFailure"];[UIView setAnimationsEnabled:animations];}
    return checks;
}
#endif
