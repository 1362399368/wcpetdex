#import "WPBarrage125Checks.h"
#import "WPMessageBarrage.h"
#import "WPMessageBarrageSource.h"
#import "WPCommon.h"

@interface WPMessageBarrageController (WPB125Checks)
- (void)suspend:(NSNotification *)note;
- (void)resume:(NSNotification *)note;
@end
static NSUInteger WPB125Live(WPMessageBarrageController *controller){
    NSUInteger count=0;for(id bubble in [controller valueForKey:@"bubbles"])if([bubble valueForKey:@"record"])count++;return count;
}
static WPBarrageMessage *WPB125Message(NSUInteger index,BOOL confirmed){
    WPBarrageMessage *message=[WPBarrageMessage new];message.conversationUsername=@"wxid_b125_admission";message.senderUsername=message.conversationUsername;
    message.identifier=[NSString stringWithFormat:@"b125-%lu",(unsigned long)index];message.createdAt=NSDate.date;message.text=@"新消息应完成播放";message.sourceEligibilityConfirmed=confirmed;return message;
}
NSDictionary<NSString *,NSNumber *> *WPBarrage125PreviewChecks(void){
    NSMutableDictionary *checks=[NSMutableDictionary new],*saved=[NSMutableDictionary new];
    NSDictionary *settings=@{@"barrageEnabled":@YES,@"barrageShowsDetails":@YES,@"barrageAllowPrivate":@YES,@"barrageAllowGroup":@YES,@"barrageQuietEnabled":@NO,@"barrageContactsOnly":@NO,@"barrageAdaptiveSaving":@NO,@"barrageReactionsEnabled":@NO,@"barrageFullScreen":@NO,@"barrageVerticalPosition":@0,@"barrageRegionHeight":@1,@"barragePauseUntil":@0};
    for(NSString *key in settings){saved[key]=[WPPreferences() objectForKey:key]?:NSNull.null;[WPPreferences() setObject:settings[key] forKey:key];}
    UIWindow *window=[[UIWindow alloc]initWithFrame:CGRectMake(0,0,393,852)];window.windowLevel=-100;window.rootViewController=[UIViewController new];window.hidden=NO;
    WPMessageBarrageController *controller=[[WPMessageBarrageController alloc]initWithHostView:window.rootViewController.view];
    __block WPBarrageConversationEligibility eligibility=WPBarrageConversationEligibilityUnknown;
    [controller setValue:[^WPBarrageConversationEligibility(__unused NSString *name){return eligibility;} copy] forKey:@"previewEligibilityProvider"];
    [controller setValue:[^UIImage *(__unused NSString *name){return nil;} copy] forKey:@"previewAvatarProvider"];
    [controller setValue:@YES forKey:@"foregroundAvailable"];controller.active=YES;
    CGRect safe=CGRectMake(0,64,393,714),dock=CGRectMake(305,560,36,36);
    [controller updateLayoutSafeRect:safe obstacles:@[] dockFrame:dock];
    @try{
        WPBarrageMessage *first=WPB125Message(1,NO);[controller enqueueMessage:first];
        checks[@"B12501RejectedUnknownDoesNotPoisonMessageIdentifier"]=@(![[controller valueForKey:@"recentIdentifiers"] containsObject:first.identifier] && WPB125Live(controller)==0);
        eligibility=WPBarrageConversationEligibilityAllowed;[controller enqueueMessage:first];
        checks[@"B12502SameMessageCanPlayAfterMetadataBecomesAvailable"]=@(WPB125Live(controller)==1);
        [controller enqueueMessage:first];checks[@"B12503AcceptedMessageStillDeduplicates"]=@(WPB125Live(controller)==1 && [[controller valueForKey:@"pending"] count]==0);
        [controller purgeForMemoryPressure];eligibility=WPBarrageConversationEligibilityUnknown;
        [controller enqueueMessage:WPB125Message(2,YES)];
        checks[@"B12504PositiveSourceAdmissionSurvivesImmediateMetadataGap"]=@(WPB125Live(controller)==1);
        [controller purgeForMemoryPressure];eligibility=WPBarrageConversationEligibilityDenied;
        [controller enqueueMessage:WPB125Message(3,YES)];
        checks[@"B12505ExplicitPrivacyDenialStillOverridesSourceAdmission"]=@(WPB125Live(controller)==0 && [[controller valueForKey:@"pending"] count]==0);
        eligibility=WPBarrageConversationEligibilityAllowed;
        [controller suspend:[NSNotification notificationWithName:UIApplicationWillResignActiveNotification object:nil]];
        [controller enqueueMessage:WPB125Message(4,YES)];
        checks[@"B12506TransientInterruptionQueuesFreshMessageWithoutStartingMotion"]=@(controller.temporarilySuspended && WPB125Live(controller)==0 && [[controller valueForKey:@"pending"] count]==1);
        [controller resume:[NSNotification notificationWithName:UIApplicationDidBecomeActiveNotification object:nil]];
        checks[@"B12507ResumePlaysMessageAdmittedDuringInterruption"]=@(WPB125Live(controller)==1 && [[controller valueForKey:@"pending"] count]==0);
        [controller purgeForMemoryPressure];[controller updateLayoutSafeRect:CGRectZero obstacles:@[] dockFrame:dock];
        [controller enqueueMessage:WPB125Message(5,YES)];
        checks[@"B12508TemporaryZeroLayoutKeepsBoundedPendingMessage"]=@(WPB125Live(controller)==0 && [[controller valueForKey:@"pending"] count]==1);
        [controller updateLayoutSafeRect:safe obstacles:@[] dockFrame:dock];
        checks[@"B12509RestoredLayoutPlaysPendingMessage"]=@(WPB125Live(controller)==1);
        [controller suspend:[NSNotification notificationWithName:UIApplicationDidEnterBackgroundNotification object:nil]];
        [controller enqueueMessage:WPB125Message(6,YES)];
        checks[@"B12510TrueBackgroundStillPurgesAndRejectsMessageBodies"]=@(WPB125Live(controller)==0 && [[controller valueForKey:@"pending"] count]==0);
    }@catch(NSException *exception){checks[@"B125UnexpectedException"]=@NO;NSLog(@"B125: %@",exception.name);}
    @finally{
        controller.active=NO;[controller purgeForMemoryPressure];[controller.view removeFromSuperview];window.hidden=YES;
        for(NSString *key in saved){if(saved[key]==NSNull.null)[WPPreferences() removeObjectForKey:key];else [WPPreferences() setObject:saved[key] forKey:key];}
    }
    return checks;
}
