#import "WPBarrage123Checks.h"
#import "WPMessageBarrage.h"
#import "WPMessageBarrageSource.h"
#import "WPBarragePreferences.h"
#import "WPCommon.h"
#import <QuartzCore/QuartzCore.h>

@interface WPMessageBarrageSource (WPB123SourceChecks)
- (WPBarrageConversationEligibility)eligibilityForConversation:(NSString *)username;
- (id)nativeSessionForConversation:(NSString *)username;
- (NSSet *)homeNamesForConversations;
- (BOOL)isCurrentConversation:(NSString *)username;
@end
@interface WPB123Session : NSObject
@property(nonatomic) BOOL isHidden;
@property(nonatomic) BOOL m_bShowUnReadAsRedDot;
@end
@implementation WPB123Session @end
@interface WPB123Source : WPMessageBarrageSource
@property(nonatomic,strong) id fixtureSession;
@property(nonatomic,copy) NSSet *fixtureHome;
@property(nonatomic,copy) NSString *fixtureCurrent;
@property(nonatomic) BOOL fixtureThrows;
@end
@implementation WPB123Source
- (id)nativeSessionForConversation:(NSString *)username {
    if(self.fixtureThrows)@throw [NSException exceptionWithName:@"WPB123NativeTransient" reason:nil userInfo:nil];
    return self.fixtureSession;
}
- (NSSet *)homeNamesForConversations {return self.fixtureHome;}
- (BOOL)isCurrentConversation:(NSString *)username {return [self.fixtureCurrent isEqual:username];}
@end
@interface WPMessageBarrageController (WPB123Checks)
- (void)pump;
- (void)suspend:(NSNotification *)note;
- (void)resume:(NSNotification *)note;
- (void)finishBubble:(id)bubble sequence:(NSUInteger)sequence motion:(NSUInteger)motion finished:(BOOL)finished;
@end
static WPBarrageMessage *WPB123Message(NSUInteger sequence) {
    WPBarrageMessage *message=[WPBarrageMessage new];
    message.conversationUsername=[NSString stringWithFormat:@"wxid_b123_%lu",(unsigned long)sequence];
    message.senderUsername=message.conversationUsername;message.identifier=[NSString stringWithFormat:@"b123-message-%lu",(unsigned long)sequence];
    message.text=@"连续播放，页面变化时保留本条消息";return message;
}
static NSArray<UIControl *> *WPB123Live(WPMessageBarrageController *controller) {
    NSMutableArray *live=[NSMutableArray new];for(UIControl *bubble in [controller valueForKey:@"bubbles"])if([bubble valueForKey:@"record"])[live addObject:bubble];return live;
}
static void WPB123Finish(WPMessageBarrageController *controller,UIControl *bubble) {
    id record=[bubble valueForKey:@"record"];
    [controller finishBubble:bubble sequence:[[record valueForKey:@"sequence"] unsignedIntegerValue] motion:[[bubble valueForKey:@"motionSerial"] unsignedIntegerValue] finished:YES];
}
NSDictionary<NSString *,NSNumber *> *WPBarrage123PreviewChecks(void) {
    NSMutableDictionary *checks=[NSMutableDictionary new];
    NSArray *keys=@[@"barrageEnabled",@"barrageShowsDetails",@"barrageFullScreen",@"barrageQuietEnabled",@"barrageContactsOnly",@"barragePauseUntil",@"barrageAdaptiveSaving",@"barrageAllowPrivate",@"barrageAllowGroup",@"barrageVerticalPosition",@"barrageRegionHeight",@"barrageReactionsEnabled",@"barrageShowsName",@"barrageNameUsesRemark"];
    NSUserDefaults *defaults=WPPreferences();NSDictionary *saved=[defaults persistentDomainForName:@"dev.zhour.wechatpet"]?:@{};
    UIWindow *window=nil;WPMessageBarrageController *controller=nil;WPB123Source *source=nil;
    @try {
        [defaults setBool:YES forKey:@"barrageEnabled"];[defaults setBool:YES forKey:@"barrageShowsDetails"];
        [defaults setBool:NO forKey:@"barrageFullScreen"];[defaults setBool:NO forKey:@"barrageQuietEnabled"];
        [defaults setBool:NO forKey:@"barrageContactsOnly"];[defaults removeObjectForKey:@"barragePauseUntil"];
        [defaults setBool:NO forKey:@"barrageAdaptiveSaving"];[defaults setBool:YES forKey:@"barrageAllowPrivate"];
        [defaults setBool:YES forKey:@"barrageAllowGroup"];[defaults setBool:NO forKey:@"barrageReactionsEnabled"];
        [defaults setDouble:0 forKey:@"barrageVerticalPosition"];[defaults setDouble:1 forKey:@"barrageRegionHeight"];[defaults setBool:NO forKey:@"barrageShowsName"];
        source=[WPB123Source new];WPB123Session *session=[WPB123Session new];source.fixtureSession=session;
        NSMutableSet *home=[NSMutableSet new];for(NSUInteger i=1;i<50;i++)[home addObject:WPB123Message(i).conversationUsername];source.fixtureHome=home;
        NSString *name=WPB123Message(1).conversationUsername;
        checks[@"B12301_RealSourceAllowsTypedKnownMetadata"]=@([source eligibilityForConversation:name]==WPBarrageConversationEligibilityAllowed);
        source.fixtureHome=nil;
        checks[@"B12302_RealSourceHomeUnavailableIsUnknown"]=@([source eligibilityForConversation:name]==WPBarrageConversationEligibilityUnknown);
        source.fixtureHome=[NSSet set];
        checks[@"B12303_RealSourceTemporaryOffHomeIsUnknown"]=@([source eligibilityForConversation:name]==WPBarrageConversationEligibilityUnknown);
        source.fixtureHome=home;source.fixtureSession=nil;
        checks[@"B12304_RealSourceSessionUnavailableIsUnknown"]=@([source eligibilityForConversation:name]==WPBarrageConversationEligibilityUnknown);
        source.fixtureSession=[NSObject new];
        checks[@"B12305_RealSourceMuteUnavailableIsUnknown"]=@([source eligibilityForConversation:name]==WPBarrageConversationEligibilityUnknown);
        source.fixtureSession=session;source.fixtureThrows=YES;
        checks[@"B12306_RealSourceNativeExceptionIsUnknown"]=@([source eligibilityForConversation:name]==WPBarrageConversationEligibilityUnknown);source.fixtureThrows=NO;
        session.isHidden=YES;
        checks[@"B12307_RealSourceExplicitHiddenIsDenied"]=@([source eligibilityForConversation:name]==WPBarrageConversationEligibilityDenied);session.isHidden=NO;
        session.m_bShowUnReadAsRedDot=YES;source.fixtureHome=nil;
        checks[@"B12308_ExplicitMuteStillDeniedWhenHomeIsUnavailable"]=@([source eligibilityForConversation:name]==WPBarrageConversationEligibilityDenied);session.m_bShowUnReadAsRedDot=NO;source.fixtureHome=home;
        source.fixtureCurrent=name;
        checks[@"B12309_RealSourceCurrentVisibleChatIsDenied"]=@([source eligibilityForConversation:name]==WPBarrageConversationEligibilityDenied);source.fixtureCurrent=nil;

        window=[[UIWindow alloc] initWithFrame:CGRectMake(0,0,393,852)];window.windowLevel=-100;window.rootViewController=[UIViewController new];window.hidden=NO;
        UIView *host=window.rootViewController.view;host.frame=window.bounds;controller=[[WPMessageBarrageController alloc] initWithHostView:host];
        [controller setValue:@YES forKey:@"foregroundAvailable"];
        __weak WPB123Source *weakSource=source;
        [controller setValue:[^WPBarrageConversationEligibility(NSString *username){return [weakSource eligibilityForConversation:username];} copy] forKey:@"previewEligibilityProvider"];
        [controller setValue:[^UIImage *(__unused NSString *username){return nil;} copy] forKey:@"previewAvatarProvider"];
        controller.active=YES;[controller updateLayoutSafeRect:CGRectMake(0,64,393,714) obstacles:@[] dockFrame:CGRectMake(300,560,36,36)];
        __block NSUInteger batches=0,legacyDocks=0;__block WPBarrageMessage *lastBatch=nil;NSMutableArray *events=[NSMutableArray new];
        controller.onBatchCompleted=^(WPBarrageMessage *message,__unused UIImage *image){batches++;lastBatch=message;[events addObject:@"batch"];};
        controller.onDockMessage=^(__unused WPBarrageMessage *message,__unused UIImage *image){legacyDocks++;};
        controller.onPlaybackChanged=^(BOOL playing){[events addObject:playing?@"playing":@"idle"];};
        source.fixtureHome=nil;[controller enqueueMessage:WPB123Message(40)];
        checks[@"B12310_UnknownInitialAdmissionStillFailsClosed"]=@(!controller.isDisplaying);
        source.fixtureHome=home;[controller enqueueMessage:WPB123Message(1)];UIControl *live=WPB123Live(controller).firstObject;id record=[live valueForKey:@"record"];
        checks[@"B12311_EngineRequiresActualPositiveSourceAdmission"]=@(live!=nil&&[[record valueForKey:@"eligibilityConfirmed"] boolValue]);
        source.fixtureHome=nil;for(NSUInteger i=0;i<30;i++)[controller pump];
        checks[@"B12312_HomeCacheNilNeverErasesAdmittedVisibleBody"]=@([live valueForKey:@"record"]==record&&((UILabel *)[live valueForKey:@"bodyLabel"]).text.length>0&&!live.hidden);
        source.fixtureHome=[NSSet set];[controller pump];
        checks[@"B12313_TemporaryOffHomeNeverErasesAdmittedVisibleBody"]=@([live valueForKey:@"record"]==record);
        source.fixtureHome=home;source.fixtureSession=nil;[controller pump];
        checks[@"B12314_MissingSessionNeverErasesAdmittedVisibleBody"]=@([live valueForKey:@"record"]==record);
        source.fixtureSession=[NSObject new];[controller pump];
        checks[@"B12315_UnknownMuteNeverErasesPreviouslyVerifiedBody"]=@([live valueForKey:@"record"]==record);
        source.fixtureSession=session;source.fixtureThrows=YES;[controller pump];
        checks[@"B12316_NativeGetterExceptionNeverErasesAdmittedBody"]=@([live valueForKey:@"record"]==record);source.fixtureThrows=NO;
        [controller suspend:[NSNotification notificationWithName:UIApplicationWillResignActiveNotification object:nil]];
        checks[@"B12317_TransientResignActiveDoesNotEraseMessage"]=@([live valueForKey:@"record"]==record&&!controller.view.hidden);
        checks[@"B12331_TransientPauseFreezesAnimationAndStopsWorkTimer"]=@(controller.temporarilySuspended&&controller.view.layer.speed==0&&[controller valueForKey:@"workTimer"]==nil);
        [controller enqueueMessage:WPB123Message(41)];WPB123Finish(controller,live);
        checks[@"B12332_PauseRejectsNewWorkAndIgnoresStaleCompletion"]=@(WPB123Live(controller).count==1&&[live valueForKey:@"record"]==record&&batches==0);
        [live.layer removeAnimationForKey:@"WPBarrageMove"];
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]];
        [controller resume:nil];
        checks[@"B12333_ResumeRepairsAnimationCancelledDuringPause"]=@(!controller.temporarilySuspended&&controller.view.layer.speed==1&&[live valueForKey:@"record"]==record&&[live.layer animationForKey:@"WPBarrageMove"]!=nil);
        session.isHidden=YES;[controller pump];
        checks[@"B12318_ExplicitHiddenImmediatelyScrubsAdmittedBody"]=@([live valueForKey:@"record"]==nil&&((UILabel *)[live valueForKey:@"bodyLabel"]).text==nil&&batches==0);session.isHidden=NO;
        [controller enqueueMessage:WPB123Message(2)];live=WPB123Live(controller).firstObject;session.m_bShowUnReadAsRedDot=YES;[controller pump];
        checks[@"B12319_ExplicitMuteImmediatelyScrubsAdmittedBody"]=@([live valueForKey:@"record"]==nil&&batches==0);session.m_bShowUnReadAsRedDot=NO;
        [controller enqueueMessage:WPB123Message(3)];live=WPB123Live(controller).firstObject;source.fixtureCurrent=WPB123Message(3).conversationUsername;[controller pump];
        checks[@"B12320_OpeningMatchingChatRemovesOnlyItsLiveCapsule"]=@([live valueForKey:@"record"]==nil&&batches==0);source.fixtureCurrent=nil;

        [events removeAllObjects];[controller enqueueMessage:WPB123Message(4)];[controller enqueueMessage:WPB123Message(5)];[controller enqueueMessage:WPB123Message(6)];
        NSArray *burst=WPB123Live(controller);WPB123Finish(controller,burst[2]);WPB123Finish(controller,burst[1]);
        checks[@"B12321_BurstCannotPopAvatarBeforeFinalPhysicalCompletion"]=@(batches==0&&controller.hasMovingMessages);
        WPB123Finish(controller,burst[0]);
        checks[@"B12322_BurstEmitsExactlyOneBodyFreeCompletionWithoutReturnFlight"]=@(batches==1&&legacyDocks==0&&!controller.isDisplaying&&!controller.returningToDock&&lastBatch.text.length==0&&[lastBatch.identifier isEqual:@"b123-message-6"]);
        checks[@"B12323_CompletionPrecedesOnlyOneIdleTransition"]=@([events isEqual:@[@"playing",@"batch",@"idle"]]);
        WPB123Finish(controller,burst[0]);
        checks[@"B12324_StaleCompletionCannotDuplicateAvatarPop"]=@(batches==1);

        __block NSString *opened=nil;controller.onOpenConversation=^(NSString *username){opened=username;};
        [controller enqueueMessage:WPB123Message(7)];[controller enqueueMessage:WPB123Message(8)];NSArray *two=WPB123Live(controller);UIControl *remaining=two[1];id remainingRecord=[remaining valueForKey:@"record"];
        [two[0] accessibilityActivate];
        checks[@"B12325_TappingOneMessageDoesNotPurgeOtherConversation"]=@([opened isEqual:WPB123Message(7).conversationUsername]&&[remaining valueForKey:@"record"]==remainingRecord&&WPB123Live(controller).count==1&&batches==1);
        source.fixtureCurrent=WPB123Message(7).conversationUsername;[controller pump];
        checks[@"B12326_OtherConversationKeepsPlayingWhileChatIsOpen"]=@([remaining valueForKey:@"record"]==remainingRecord);source.fixtureCurrent=nil;
        [controller purgeForMemoryPressure];
        [controller enqueueMessage:WPB123Message(10)];[controller suspend:[NSNotification notificationWithName:UIApplicationDidEnterBackgroundNotification object:nil]];
        checks[@"B12329_RealBackgroundStillScrubsQueueBodyAndAnimations"]=@(!controller.isDisplaying&&controller.view.hidden&&WPB123Live(controller).count==0);
        [controller resume:nil];
        checks[@"B12330_ResumeNeverReplaysEarlierBody"]=@(!controller.isDisplaying&&batches==1);
        // Use the actual notification, not the explicit hard-clear API. An
        // ordinary warning must preserve already visible pixels and motion.
        for(NSUInteger i=42;i<49;i++)[controller enqueueMessage:WPB123Message(i)];
        NSArray<UIControl *> *visibleBefore=WPB123Live(controller);NSMutableArray *identities=[NSMutableArray new],*texts=[NSMutableArray new];
        for(UIControl *bubble in visibleBefore){[identities addObject:[bubble valueForKey:@"record"]];[texts addObject:((UILabel *)[bubble valueForKey:@"bodyLabel"]).text?:@""];}
        BOOL hadWaiting=[[controller valueForKey:@"pending"] count]>0;
        [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidReceiveMemoryWarningNotification object:nil];
        BOOL sameVisible=visibleBefore.count>0;
        for(NSUInteger i=0;i<visibleBefore.count;i++){UIControl *bubble=visibleBefore[i];sameVisible&=([bubble valueForKey:@"record"]==identities[i]&&!bubble.hidden&&[((UILabel *)[bubble valueForKey:@"bodyLabel"]).text isEqual:texts[i]]&&[bubble.layer animationForKey:@"WPBarrageMove"]!=nil);}
        checks[@"B12401RealMemoryWarningPreservesAdmittedVisibleBodyAndMotion"]=@(sameVisible&&WPB123Live(controller).count==visibleBefore.count);
        checks[@"B12402RealMemoryWarningDropsOnlyWaitingWorkAndCaches"]=@(hadWaiting&&[[controller valueForKey:@"pending"] count]==0&&[[controller valueForKey:@"avatarLoads"] count]==0&&[[controller valueForKey:@"avatarCacheKeys"] count]==0);
        NSUInteger beforeWarningBatch=batches;for(UIControl *bubble in visibleBefore)WPB123Finish(controller,bubble);
        checks[@"B12403TrimmedBurstStillFinishesOnceWithNewestAdmittedIdentity"]=@(batches==beforeWarningBatch+1&&!controller.isDisplaying&&[lastBatch.identifier isEqual:@"b123-message-48"]);
        __block NSString *lookedUpSender=nil;
        [controller setValue:[^NSString *(NSString *sender,BOOL remark){lookedUpSender=[sender copy];return remark?@"朋友备注":@"群成员昵称";} copy] forKey:@"previewDisplayNameProvider"];
        [defaults setBool:NO forKey:@"barrageShowsDetails"];[defaults setBool:YES forKey:@"barrageShowsName"];[defaults setBool:YES forKey:@"barrageNameUsesRemark"];[controller refreshPreferences];
        WPBarrageMessage *group=WPB123Message(49);group.conversationUsername=@"b124_group@chatroom";group.senderUsername=@"wxid_b124_member";group.text=@"群里的一条消息👨‍👩‍👧‍👦";
        [home addObject:group.conversationUsername];source.fixtureHome=home;[controller enqueueMessage:group];
        UIControl *named=WPB123Live(controller).firstObject;UILabel *nameLabel=[named valueForKey:@"nameLabel"],*bodyLabel=[named valueForKey:@"bodyLabel"];
        checks[@"B12404NameWithoutBodyUsesActualGroupSenderAndRemark"]=@(named&&!nameLabel.hidden&&[nameLabel.text isEqual:@"朋友备注"]&&bodyLabel.hidden&&bodyLabel.text.length==0&&[lookedUpSender isEqual:group.senderUsername]);
        [defaults setBool:NO forKey:@"barrageNameUsesRemark"];[controller refreshPreferences];
        checks[@"B12405NicknameSwitchChangesLiveNameWithoutReplayingBody"]=@([nameLabel.text isEqual:@"群成员昵称"]&&bodyLabel.text.length==0&&[named valueForKey:@"record"]!=nil);
        [defaults setBool:NO forKey:@"barrageShowsName"];[controller refreshPreferences];
        checks[@"B12406NameSwitchImmediatelyRemovesNameAndRestoresAvatarOnlyWidth"]=@(nameLabel.text.length==0&&nameLabel.hidden&&fabs(named.bounds.size.width-46)<.1&&bodyLabel.text.length==0);
    } @catch(NSException *exception) {checks[[NSString stringWithFormat:@"B123_Exception_%@",exception.name]]=@NO;NSLog(@"B123 checks: %@ %@",exception.name,exception.reason);}
    @finally {
        controller.onBatchCompleted=nil;controller.onDockMessage=nil;controller.onPlaybackChanged=nil;controller.onOpenConversation=nil;
        controller.active=NO;[controller purgeForMemoryPressure];[controller.view removeFromSuperview];window.hidden=YES;[source setActive:NO];
        for(NSString *key in keys){id value=saved[key];if(value)[defaults setObject:value forKey:key];else [defaults removeObjectForKey:key];}
    }
    return checks;
}

// Run on a real following main-queue turn. A nested run loop inside the
// synchronous suite cannot reenter the main serial dispatch queue that owns
// recovery, so it cannot validate a dispatch_async-based repair correctly.
void WPBarrage123RunAsyncPreviewChecks(void (^completion)(NSDictionary<NSString *,NSNumber *> *)) {
    NSUserDefaults *defaults=WPPreferences();
    NSArray *keys=@[@"barrageEnabled",@"barrageShowsDetails",@"barrageFullScreen",@"barrageQuietEnabled",@"barrageContactsOnly",@"barragePauseUntil",@"barrageAdaptiveSaving",@"barrageAllowPrivate",@"barrageAllowGroup",@"barrageVerticalPosition",@"barrageRegionHeight",@"barrageReactionsEnabled"];
    NSDictionary *saved=[defaults persistentDomainForName:@"dev.zhour.wechatpet"]?:@{};
    [defaults setBool:YES forKey:@"barrageEnabled"];[defaults setBool:YES forKey:@"barrageShowsDetails"];
    [defaults setBool:NO forKey:@"barrageFullScreen"];[defaults setBool:NO forKey:@"barrageQuietEnabled"];
    [defaults setBool:NO forKey:@"barrageContactsOnly"];[defaults removeObjectForKey:@"barragePauseUntil"];
    [defaults setBool:NO forKey:@"barrageAdaptiveSaving"];[defaults setBool:YES forKey:@"barrageAllowPrivate"];
    [defaults setBool:YES forKey:@"barrageAllowGroup"];[defaults setBool:NO forKey:@"barrageReactionsEnabled"];
    [defaults setDouble:0 forKey:@"barrageVerticalPosition"];[defaults setDouble:1 forKey:@"barrageRegionHeight"];
    UIWindow *window=[[UIWindow alloc] initWithFrame:CGRectMake(0,0,393,852)];window.windowLevel=-100;
    window.rootViewController=[UIViewController new];window.hidden=NO;UIView *host=window.rootViewController.view;host.frame=window.bounds;
    WPB123Source *source=[WPB123Source new];source.fixtureSession=[WPB123Session new];source.fixtureHome=[NSSet setWithObject:WPB123Message(9).conversationUsername];
    WPMessageBarrageController *controller=[[WPMessageBarrageController alloc] initWithHostView:host];
    [controller setValue:@YES forKey:@"foregroundAvailable"];
    [controller setValue:[^WPBarrageConversationEligibility(NSString *username){return [source eligibilityForConversation:username];} copy] forKey:@"previewEligibilityProvider"];
    [controller setValue:[^UIImage *(__unused NSString *username){return nil;} copy] forKey:@"previewAvatarProvider"];
    controller.active=YES;[controller updateLayoutSafeRect:CGRectMake(0,64,393,714) obstacles:@[] dockFrame:CGRectMake(300,560,36,36)];
    __block NSUInteger batches=0;controller.onBatchCompleted=^(__unused WPBarrageMessage *message,__unused UIImage *image){batches++;};
    [controller enqueueMessage:WPB123Message(9)];UIControl *live=WPB123Live(controller).firstObject;
    id record=[live valueForKey:@"record"];NSUInteger serial=[[live valueForKey:@"motionSerial"] unsignedIntegerValue];
    NSMutableDictionary *checks=[NSMutableDictionary new];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,50*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        [CATransaction flush];[live.layer removeAnimationForKey:@"WPBarrageMove"];
        // The layer's recovery was enqueued by the actual removal immediately
        // above. This assertion follows that repair on the real main queue.
        dispatch_async(dispatch_get_main_queue(),^{
            BOOL same=[live valueForKey:@"record"]==record,visible=!live.hidden;
            BOOL animation=[live.layer animationForKey:@"WPBarrageMove"]!=nil;
            BOOL advanced=[[live valueForKey:@"motionSerial"] unsignedIntegerValue]>serial;
            checks[@"B12327a_CancelRecoveryPreservesRecord"]=@(same);
            checks[@"B12327b_CancelRecoveryPreservesVisibility"]=@(visible);
            checks[@"B12327c_CancelRecoveryRestoresRealCAAnimation"]=@(animation);
            checks[@"B12327d_CancelRecoveryAdvancesMotionIdentity"]=@(advanced);
            checks[@"B12327e_CancelRecoveryDoesNotPrematurelyCompleteBatch"]=@(batches==0);
            checks[@"B12327_CancelledLayerAnimationRecoversSameMessageAndMotion"]=@(same&&visible&&animation&&advanced&&batches==0);
            WPB123Finish(controller,live);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,50*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
                checks[@"B12328_RecoveredAnimationCompletesExactlyOnce"]=@(batches==1&&!controller.isDisplaying);
                controller.onBatchCompleted=nil;controller.active=NO;[controller purgeForMemoryPressure];[controller.view removeFromSuperview];window.hidden=YES;[source setActive:NO];
                for(NSString *key in keys){id value=saved[key];if(value)[defaults setObject:value forKey:key];else [defaults removeObjectForKey:key];}
                if(completion)completion(checks);
            });
        });
    });
}
