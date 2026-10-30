#import "WPBarrageIntegrationChecks.h"
#import "WPBarragePreferences.h"
#import "WPMessageBarrage.h"
#import "WPMessageBarrageSource.h"
#import "WPCommon.h"
#import "WPUnreadAvatarControl.h"
#import "WPRadialMenu.h"
#import "WPUnreadDockState.h"
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>

@interface UIViewController (WPBarrageIntegrationAccess)
- (void)applySettings;
- (void)resetIdle;
- (void)refreshBarrageState;
- (void)releaseTransientViews;
- (BOOL)accessibilityMenu;
- (void)bounceMessageAvatar;
@end
static BOOL WPIAlwaysPeek(__unused id receiver,__unused SEL selector){return YES;}
static BOOL WPIContainsText(UIView *view,NSString *text){
    if([view isKindOfClass:UILabel.class] && [((UILabel *)view).text containsString:text])return YES;
    if([view.accessibilityLabel containsString:text])return YES;
    for(UIView *child in view.subviews)if(WPIContainsText(child,text))return YES;
    return NO;
}

NSDictionary<NSString *, NSNumber *> *WPBarrageIntegrationPreviewChecks(UIWindow *window){
    NSMutableDictionary *r=[NSMutableDictionary new];
    NSArray *keys=@[@"enabled",@"autoPeek",@"quickChatEnabled",@"unreadAvatarEnabled",@"barrageEnabled",@"barrageShowsDetails",@"barrageReactionsEnabled",@"barrageFullScreen",@"barrageSpeed",@"barrageBackgroundOpacity",@"quietTimeEnabled",@"reminderContactsOnly",@"barrageQuietEnabled",@"barrageContactsOnly",@"barragePauseUntil",@"barrageCompletionAnimation",@"barrageAdaptiveSaving"];
    NSMutableDictionary *saved=[NSMutableDictionary new];for(NSString *key in keys)saved[key]=[WPPreferences() objectForKey:key]?:NSNull.null;
    UIViewController *root=window.rootViewController;
    @try {
        [WPPreferences() setBool:YES forKey:@"enabled"];[WPPreferences() setBool:NO forKey:@"autoPeek"];
        [WPPreferences() setBool:NO forKey:@"quickChatEnabled"];[WPPreferences() setBool:NO forKey:@"unreadAvatarEnabled"];
        [WPPreferences() setBool:NO forKey:@"quietTimeEnabled"];[WPPreferences() setBool:NO forKey:@"reminderContactsOnly"];
        [WPPreferences() setBool:NO forKey:@"barrageQuietEnabled"];[WPPreferences() setBool:NO forKey:@"barrageContactsOnly"];[WPPreferences() removeObjectForKey:@"barragePauseUntil"];
        WPBarrageSetEnabled(YES);WPBarrageSetShowsDetails(YES);[root applySettings];[root.view layoutIfNeeded];[root refreshBarrageState];
        WPMessageBarrageController *engine=[root valueForKey:@"barrage"];
        [engine setValue:@YES forKey:@"previewSkipNativePolicy"];
        // Source checks use the real notification center. Start this fixture
        // after discarding their messages, not during an unrelated old flight.
        [engine purgeForMemoryPressure];
        WPUnreadAvatarControl *dock=[root valueForKey:@"unreadDot"];
        r[@"BI01_independentOfQuickchatAndUnreadSwitches"]=@(engine!=nil && engine.active);
        UIImage *image=[[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(20,20)] imageWithActions:^(UIGraphicsImageRendererContext *context){[UIColor.systemGreenColor setFill];UIRectFill(CGRectMake(0,0,20,20));}];
        WPBarrageMessage *initial=[WPBarrageMessage new];initial.conversationUsername=@"preview_group@chatroom";initial.senderUsername=@"preview_member";initial.identifier=NSUUID.UUID.UUIDString;initial.createdAt=NSDate.date;
        [[root valueForKey:@"messageDock"] markBarrageMessageReceived:initial];
        if(engine.onBatchCompleted)engine.onBatchCompleted(initial,image);
        r[@"BI02_reusesExistingSingleDock"]=@([root valueForKey:@"unreadDot"]==dock && !dock.hidden);
        r[@"BI03_groupDockKeepsGroupRoute"]=@([dock.username isEqualToString:@"preview_group@chatroom"]);
        r[@"BI04_groupDockUsesSenderAvatar"]=@([[dock valueForKey:@"avatarUsername"] isEqualToString:@"preview_member"]);
        [WPPreferences() setBool:NO forKey:@"barrageAdaptiveSaving"];
        NSString *animationIdentity=[dock.username copy];
        for(NSInteger style=0;style<4;style++){
            [WPPreferences() setInteger:style forKey:@"barrageCompletionAnimation"];[root bounceMessageAvatar];
            CAAnimation *motion=[dock.layer animationForKey:@"WPMessageHeadPop123"];
            BOOL reduced=UIAccessibilityIsReduceMotionEnabled()||WPBarrageResourceSavingActive();BOOL matches=NO;
            if(style==3 || reduced)matches=motion==nil;
            else if(style==0)matches=[motion isKindOfClass:CAAnimationGroup.class]&&((CAAnimationGroup *)motion).animations.count==2;
            else if(style==1){CABasicAnimation *flight=[motion isKindOfClass:CABasicAnimation.class]?(id)motion:nil;CGPoint to=[flight.toValue CGPointValue],from=[flight.fromValue CGPointValue];matches=[flight.keyPath isEqual:@"position"]&&fabs(to.x-dock.center.x)<.1&&fabs(to.y-dock.center.y)<.1&&from.x<0&&flight.duration<1;}
            else if(style==2){CABasicAnimation *fade=[motion isKindOfClass:CABasicAnimation.class]?(id)motion:nil;matches=[fade.keyPath isEqual:@"opacity"]&&[fade.fromValue doubleValue]==0&&[fade.toValue doubleValue]==1;}
            r[[NSString stringWithFormat:@"BI124CompletionStyle%ldRetainsSameUnreadIdentity",(long)style]]=@(matches&&!dock.hidden&&[dock.username isEqual:animationIdentity]);
        }
        [dock.layer removeAnimationForKey:@"WPMessageHeadPop123"];
        WPBarrageMessage *message=[WPBarrageMessage new];message.conversationUsername=@"preview_next";message.senderUsername=@"preview_next";message.identifier=@"integration-1";message.createdAt=NSDate.date;message.text=@"INTEGRATION_PRIVATE_BODY";
        [NSNotificationCenter.defaultCenter postNotificationName:WPMessageBarrageDidReceiveNotification object:nil userInfo:@{@"message":message}];
        r[@"BI05_notificationStartsRealOverlayAnimation"]=@(engine.isDisplaying);
        r[@"BI06_oldDockRemainsWhileNextMoves"]=@([dock.username isEqualToString:@"preview_group@chatroom"]);
        WPBarrageSetShowsDetails(NO);
        r[@"BI07_privacyChangeImmediatelyScrubsOverlay"]=@(!WPIContainsText(engine.view,@"INTEGRATION_PRIVATE_BODY"));
        [root accessibilityMenu];
        WPRadialMenuView *menu=[root valueForKey:@"menu"];
        r[@"BI08_menuKeepsBarrageFloating"]=@(engine.active && engine.isDisplaying);
        r[@"BI09_onlyFourPetActionsRemain"]=@(menu.accessibilityElements.count==4);
        [menu cancel];[root resetIdle];r[@"BI10_afterMenuCanReceiveAgain"]=@(engine.active);
        [NSNotificationCenter.defaultCenter postNotificationName:WPBarrageClearDockNotification object:nil];
        r[@"BI11_clearRemovesHostRouteAndAvatar"]=@([[root valueForKey:@"barrageDockConversation"] length]==0 && dock.hidden && dock.username==nil);
        initial.identifier=NSUUID.UUID.UUIDString;initial.createdAt=NSDate.date;
        [[root valueForKey:@"messageDock"] markBarrageMessageReceived:initial];
        if(engine.onBatchCompleted)engine.onBatchCompleted(initial,image);
        [root releaseTransientViews];
        r[@"BI12_backgroundReleasesBarrageAndHostImage"]=@(!engine.active && !engine.isDisplaying && [root valueForKey:@"barrageDockImage"]==nil);
        r[@"BI13_backgroundRetainsOnlyDockIdentity"]=@([[root valueForKey:@"barrageDockConversation"] isEqualToString:@"preview_group@chatroom"]);
        [root refreshBarrageState];
        WPBarrageSetEnabled(NO);[root applySettings];
        r[@"BI14_disablePurgesAndRestoresUnreadPolicy"]=@(!engine.active && !engine.isDisplaying && dock.hidden && [root valueForKey:@"barrageDockConversation"]==nil);
        // Force eligibility only; the actual scheduling method remains untouched.
        Method method=class_getInstanceMethod(root.class,@selector(canPeek));IMP original=method_setImplementation(method,(IMP)WPIAlwaysPeek);
        @try {
            [root setValue:@NO forKey:@"peeking"];
            [root resetIdle];NSTimer *first=[root valueForKey:@"idleTimer"];
            for(NSUInteger i=0;i<200;i++)[root resetIdle];
            r[@"BI15_layoutBurstKeepsOneIdleTimer"]=@(first!=nil && first==[root valueForKey:@"idleTimer"] && first.isValid);
            [root releaseTransientViews];r[@"BI16_backgroundInvalidatesIdleTimer"]=@(!first.isValid && [root valueForKey:@"idleTimer"]==nil);
        } @finally {method_setImplementation(method,original);}
    } @catch(__unused NSException *exception){r[@"BI99_completedWithoutException"]=@NO;}
    @finally {
        for(NSString *key in keys){id value=saved[key];if(value==NSNull.null)[WPPreferences() removeObjectForKey:key];else [WPPreferences() setObject:value forKey:key];}
        [root applySettings];
    }
    return r;
}
