#import "WPBarrage122Checks.h"
#import "WPBarragePreferences.h"
#import "WPMessageBarrage.h"
#import "WPCommon.h"
#import <QuartzCore/QuartzCore.h>

@interface WPMessageBarrageController (WPBarrage122Testing)
- (void)finishBubble:(id)bubble sequence:(NSUInteger)sequence motion:(NSUInteger)motion finished:(BOOL)finished;
- (void)finishFlightSequence:(NSUInteger)sequence motion:(NSUInteger)motion finished:(BOOL)finished;
- (void)suspend:(NSNotification *)note;
- (void)resume:(NSNotification *)note;
- (void)pump;
@end
@interface UIControl (WPBarrage122VisualTesting)
- (CGRect)visualFrame;
@end
static WPBarrageMessage *WPB122Message(NSUInteger n) {
    WPBarrageMessage *message=[WPBarrageMessage new];
    message.conversationUsername=[NSString stringWithFormat:@"wxid_b122_%lu",(unsigned long)n];
    message.senderUsername=message.conversationUsername;message.identifier=[NSString stringWithFormat:@"message-b122-%lu",(unsigned long)n];
    message.text=n==1?@"这条长消息先到达，但应等它最后完成整段漂移后才归位，不能被后来较短的消息提前归位打断。":@"短消息";
    return message;
}
static NSArray<UIControl *> *WPB122Live(WPMessageBarrageController *controller) {
    NSMutableArray *live=[NSMutableArray new];
    for(UIControl *bubble in [controller valueForKey:@"bubbles"])if([bubble valueForKey:@"record"])[live addObject:bubble];
    return live;
}
static void WPB122Finish(WPMessageBarrageController *controller, UIControl *bubble) {
    id record=[bubble valueForKey:@"record"];
    [controller finishBubble:bubble sequence:[[record valueForKey:@"sequence"] unsignedIntegerValue] motion:[[bubble valueForKey:@"motionSerial"] unsignedIntegerValue] finished:YES];
}
static void WPB122FinishFlight(WPMessageBarrageController *controller) {
    UIControl *flight=[controller valueForKey:@"flight"];id record=[flight valueForKey:@"record"];
    [controller finishFlightSequence:[[record valueForKey:@"sequence"] unsignedIntegerValue] motion:[[flight valueForKey:@"motionSerial"] unsignedIntegerValue] finished:YES];
}
NSDictionary<NSString *,NSNumber *> *WPBarrage122PreviewChecks(void) {
    NSMutableDictionary *checks=[NSMutableDictionary new];
    NSArray *keys=@[@"barrageEnabled",@"barrageShowsDetails",@"barrageFullScreen",@"barrageSpeed",@"barrageBackgroundOpacity",@"barrageReactionsEnabled",@"barrageQuietEnabled",@"barrageContactsOnly",@"barragePauseUntil",@"barrageAdaptiveSaving",@"barrageAllowPrivate",@"barrageAllowGroup",@"barrageVerticalPosition",@"barrageRegionHeight"];
    NSDictionary *saved=[WPPreferences() persistentDomainForName:@"dev.zhour.wechatpet"]?:@{};
    UIWindow *window=nil;WPMessageBarrageController *controller=nil;
    @try {
        NSUserDefaults *defaults=WPPreferences();
        [defaults setBool:YES forKey:@"barrageEnabled"];[defaults setBool:YES forKey:@"barrageShowsDetails"];
        [defaults setBool:NO forKey:@"barrageFullScreen"];[defaults setBool:NO forKey:@"barrageReactionsEnabled"];
        [defaults setBool:NO forKey:@"barrageQuietEnabled"];[defaults setBool:NO forKey:@"barrageContactsOnly"];
        [defaults setBool:NO forKey:@"barrageAdaptiveSaving"];[defaults removeObjectForKey:@"barragePauseUntil"];
        [defaults setBool:YES forKey:@"barrageAllowPrivate"];[defaults setBool:YES forKey:@"barrageAllowGroup"];
        [defaults setDouble:1 forKey:@"barrageSpeed"];
        CGRect safe=CGRectMake(0,64,393,714);
        [defaults setDouble:-20 forKey:@"barrageVerticalPosition"];[defaults setDouble:20 forKey:@"barrageRegionHeight"];
        checks[@"B12201_MalformedHeightAndPositionAreClamped"]=@(WPBarrageVerticalPosition()==0&&WPBarrageRegionHeight()==1);
        [defaults setObject:@"bad" forKey:@"barrageVerticalPosition"];[defaults setObject:@"bad" forKey:@"barrageRegionHeight"];
        checks[@"B12202_NonNumericHeightUsesSafeDefaults"]=@(WPBarrageVerticalPosition()==0&&WPBarrageRegionHeight()==1);
        [defaults setDouble:1 forKey:@"barrageVerticalPosition"];[defaults setDouble:.5 forKey:@"barrageRegionHeight"];
        CGRect area=WPBarrageDisplayArea(safe);
        checks[@"B12203_BottomRegionRemainsInsideScreen"]=@(fabs(area.size.height-178.5)<.001&&CGRectContainsRect(safe,area)&&fabs(CGRectGetMaxY(area)-CGRectGetMaxY(safe))<.001);
        [defaults setBool:YES forKey:@"barrageFullScreen"];
        area=WPBarrageDisplayArea(safe);
        checks[@"B12204_FullScreenRangeScalesRegionHeight"]=@(fabs(area.size.height-357)<.001&&CGRectContainsRect(safe,area));
        [defaults setDouble:0 forKey:@"barrageVerticalPosition"];[defaults setDouble:.2 forKey:@"barrageRegionHeight"];
        area=WPBarrageDisplayArea(CGRectMake(0,10,200,70));
        checks[@"B12205_SmallRegionKeepsWholeCapsuleAndPadding"]=@(area.size.height==62&&CGRectGetMinY(area)==10);
        checks[@"B12206_InvalidGeometryDoesNotCreateTracks"]=@(CGRectIsEmpty(WPBarrageDisplayArea(CGRectMake(0,0,NAN,100)))&&CGRectIsEmpty(WPBarrageDisplayArea(CGRectNull)));
        [defaults setBool:NO forKey:@"barrageFullScreen"];[defaults setDouble:0 forKey:@"barrageVerticalPosition"];[defaults setDouble:1 forKey:@"barrageRegionHeight"];
        window=[[UIWindow alloc] initWithFrame:CGRectMake(0,0,393,852)];window.windowLevel=-100;window.rootViewController=[UIViewController new];window.hidden=NO;
        UIView *host=window.rootViewController.view;host.frame=window.bounds;
        controller=[[WPMessageBarrageController alloc] initWithHostView:host];
        [controller setValue:@YES forKey:@"previewSkipNativePolicy"];[controller setValue:@YES forKey:@"foregroundAvailable"];
        [controller setValue:[^UIImage *(__unused NSString *username){return nil;} copy] forKey:@"previewAvatarProvider"];
        controller.active=YES;[controller updateLayoutSafeRect:safe obstacles:@[] dockFrame:CGRectMake(320,560,36,36)];
        __block NSUInteger docks=0,legacyDocks=0;__block WPBarrageMessage *lastDock=nil;NSMutableArray *events=[NSMutableArray new];
        controller.onPlaybackChanged=^(BOOL playing){[events addObject:playing?@"playing":@"idle"];};
        controller.onDock=^(__unused NSString *chat,__unused NSString *sender,__unused UIImage *image){legacyDocks++;};
        controller.onBatchCompleted=^(WPBarrageMessage *message,__unused UIImage *image){docks++;lastDock=message;[events addObject:@"dock"];};
        controller.onDockMessage=^(__unused WPBarrageMessage *message,__unused UIImage *image){legacyDocks++;};
        checks[@"B12207_InitialStateHasNoFlightOrMovingMessages"]=@(!controller.hasMovingMessages&&!controller.returningToDock);
        [controller enqueueMessage:WPB122Message(1)];[controller enqueueMessage:WPB122Message(2)];[controller enqueueMessage:WPB122Message(3)];
        NSArray *live=WPB122Live(controller);UIControl *longFirst=live[0];
        checks[@"B12208_BurstMovesWithoutHoldingDockCandidate"]=@(controller.hasMovingMessages&&!controller.returningToDock&&[[controller valueForKey:@"dockCandidateSequence"] unsignedIntegerValue]==0);
        WPB122Finish(controller,live[2]);
        checks[@"B12209_NewestShortMessageDoesNotFlyBeforeOlderMessage"]=@(docks==0&&!controller.returningToDock&&controller.hasMovingMessages);
        WPB122Finish(controller,live[1]);
        checks[@"B12210_SecondCompletionStillDoesNotFly"]=@(docks==0&&!controller.returningToDock);
        WPB122Finish(controller,longFirst);
        checks[@"B12211_LastPhysicalCompletionEmitsImmediateBatchWithoutFlight"]=@(!controller.returningToDock&&!controller.hasMovingMessages&&docks==1&&[lastDock.identifier isEqual:@"message-b122-3"]);
        WPB122FinishFlight(controller);
        checks[@"B12212_BurstCommitsExactlyOneDock"]=@(docks==1&&!controller.isDisplaying);
        checks[@"B12213_PreferredDockCallbackHasNoDuplicateLegacyCall"]=@(legacyDocks==0);
        checks[@"B12230_PlaybackEmitsOnlyActualTransitionsAfterDock"]=@([events isEqual:@[@"playing",@"dock",@"idle"]]);
        [events removeAllObjects];
        checks[@"B12214_DockIdentityPreservesMessageButDiscardsBody"]=@([lastDock.identifier isEqual:@"message-b122-3"]&&[lastDock.conversationUsername isEqual:@"wxid_b122_3"]&&lastDock.createdAt&&lastDock.text.length==0);

        [controller enqueueMessage:WPB122Message(4)];WPB122Finish(controller,WPB122Live(controller).firstObject);
        UIControl *flight=[controller valueForKey:@"flight"];NSUInteger staleSequence=[[[flight valueForKey:@"record"] valueForKey:@"sequence"] unsignedIntegerValue],staleMotion=[[flight valueForKey:@"motionSerial"] unsignedIntegerValue];
        [controller enqueueMessage:WPB122Message(5)];
        checks[@"B12215_NewArrivalCancelsPreviousSingleFlight"]=@(!controller.returningToDock&&controller.hasMovingMessages);
        [controller finishFlightSequence:staleSequence motion:staleMotion finished:YES];
        checks[@"B12216_StaleAnimationCannotDuplicateAlreadyCompletedBurst"]=@(docks==2);
        checks[@"B12231_SeparateCompletedBurstsReportActualIdleBoundary"]=@([events isEqual:@[@"playing",@"dock",@"idle",@"playing"]]);
        WPB122Finish(controller,WPB122Live(controller).firstObject);WPB122FinishFlight(controller);
        checks[@"B12217_LaterBurstMayCompleteOnceNormally"]=@(docks==3&&[lastDock.identifier isEqual:@"message-b122-5"]);

        __block BOOL allow=NO;controller.onShouldDock=^BOOL(__unused WPBarrageMessage *message){return allow;};
        [controller enqueueMessage:WPB122Message(6)];WPB122Finish(controller,WPB122Live(controller).firstObject);
        checks[@"B12218_ConsumedMessageCannotEmitBatchAvatar"]=@(!controller.returningToDock&&docks==3);
        allow=YES;[controller enqueueMessage:WPB122Message(7)];WPB122Finish(controller,WPB122Live(controller).firstObject);
        allow=NO;WPB122FinishFlight(controller);
        checks[@"B12219_StaleFlightCallbackCannotReemitCompletedAvatar"]=@(docks==4&&!controller.returningToDock);
        allow=YES;

        for(NSUInteger i=20;i<28;i++)[controller enqueueMessage:WPB122Message(i)];
        NSUInteger liveBefore=WPB122Live(controller).count,pendingBefore=[[controller valueForKey:@"pending"] count];
        UIControl *existing=WPB122Live(controller).firstObject;id identity=[existing valueForKey:@"record"];
        NSUInteger serial=[[existing valueForKey:@"motionSerial"] unsignedIntegerValue];
        [controller refreshPreferences];[controller refreshPreferences];
        checks[@"B12220_UnchangedPreferencesDoNotRestartOrDiscardBurst"]=@(WPB122Live(controller).count==liveBefore&&[[controller valueForKey:@"pending"] count]==pendingBefore&&[[existing valueForKey:@"motionSerial"] unsignedIntegerValue]==serial&&[existing valueForKey:@"record"]==identity&&docks==4);
        [controller updateLayoutSafeRect:CGRectMake(0,40,393,740) obstacles:@[] dockFrame:CGRectMake(290,600,36,36)];
        checks[@"B12221_ScreenResizePreservesLiveAndQueuedMessages"]=@(WPB122Live(controller).count==liveBefore&&[[controller valueForKey:@"pending"] count]==pendingBefore&&[existing valueForKey:@"record"]==identity);
        checks[@"B12222_ScreenResizeDoesNotCommitOrCreateFlight"]=@(docks==4&&!controller.returningToDock);
        [defaults setDouble:.3 forKey:@"barrageRegionHeight"];[defaults setDouble:1 forKey:@"barrageVerticalPosition"];[controller refreshPreferences];
        CGRect screenSafe=CGRectMake(0,40,393,740);BOOL contained=YES,separated=YES;
        NSArray<UIControl *> *reflowed=WPB122Live(controller);
        for(UIControl *bubble in reflowed)contained&=CGRectGetMidY([bubble visualFrame])>=CGRectGetMinY(screenSafe)+23&&CGRectGetMidY([bubble visualFrame])<=CGRectGetMaxY(screenSafe)-23;
        for(NSUInteger i=0;i<reflowed.count;i++)for(NSUInteger j=i+1;j<reflowed.count;j++)separated&=fabs(CGRectGetMidY([reflowed[i] visualFrame])-CGRectGetMidY([reflowed[j] visualFrame]))>=53.5;
        checks[@"B12223_ShorterRegionKeepsExistingMessagesInsideScreenAndSeparated"]=@(contained&&separated&&reflowed.count==liveBefore&&[[controller valueForKey:@"pending"] count]==pendingBefore&&docks==4);
        [controller clearDock];
        NSUInteger safety=0;while(controller.hasMovingMessages&&safety++<30){NSArray *batch=WPB122Live(controller);if(!batch.count){[controller pump];break;}for(UIControl *bubble in batch)WPB122Finish(controller,bubble);}
        checks[@"B12224_ClearDockSuppressesAllAlreadyQueuedMessageFlights"]=@(!controller.isDisplaying&&docks==4);
        [controller enqueueMessage:WPB122Message(40)];WPB122Finish(controller,WPB122Live(controller).firstObject);
        checks[@"B12225_NewMessageAfterClearMayCompleteWithoutFlight"]=@(!controller.returningToDock&&docks==5);
        [controller updateLayoutSafeRect:CGRectMake(0,40,393,740) obstacles:@[] dockFrame:CGRectMake(180,440,36,36)];
        checks[@"B12226_PetMovementCannotReplayOrCreateReturnFlight"]=@(!controller.returningToDock&&[[controller valueForKey:@"flight"] valueForKey:@"record"]==nil&&docks==5);
        [controller suspend:nil];
        checks[@"B12227_BackgroundDropsFlightQueueAndText"]=@(!controller.isDisplaying&&!controller.hasMovingMessages&&!controller.returningToDock&&[[controller valueForKey:@"pending"] count]==0);
        [controller resume:nil];checks[@"B12228_ResumeDoesNotReplayOldMessage"]=@(!controller.isDisplaying&&docks==5);
        [controller enqueueMessage:WPB122Message(50)];[controller purgeForMemoryPressure];
        checks[@"B12229_MemoryPressureLeavesNoCandidateOrRetainedFlight"]=@(!controller.isDisplaying&&[[controller valueForKey:@"dockCandidateSequence"] unsignedIntegerValue]==0&&[[controller valueForKey:@"flight"] valueForKey:@"record"]==nil);
        checks[@"B12232_MemoryPressureReportsIdleToHost"]=@([events.lastObject isEqual:@"idle"]);

        [controller setValue:@YES forKey:@"previewSavingResources"];
        [defaults setBool:NO forKey:@"barrageFullScreen"];[defaults setDouble:0 forKey:@"barrageVerticalPosition"];[defaults setDouble:1 forKey:@"barrageRegionHeight"];
        [controller refreshPreferences];[controller updateLayoutSafeRect:safe obstacles:@[] dockFrame:CGRectMake(320,560,36,36)];
        for(NSUInteger i=80;i<90;i++)[controller enqueueMessage:WPB122Message(i)];
        checks[@"B12233_SavingHalfStartsTwoAndBoundsQueueToSix"]=@(WPB122Live(controller).count==2&&[[controller valueForKey:@"pending"] count]==6);
        [defaults setBool:YES forKey:@"barrageFullScreen"];[controller refreshPreferences];
        for(NSUInteger i=100;i<120;i++)[controller enqueueMessage:WPB122Message(i)];
        checks[@"B12234_SavingHalfToFullCannotExceedGlobalThreeCapsules"]=@(WPB122Live(controller).count==3&&[[controller valueForKey:@"pending"] count]==6);
        NSArray<UIControl *> *savingLive=WPB122Live(controller);BOOL savingSeparated=YES;
        for(NSUInteger i=0;i<savingLive.count;i++)for(NSUInteger j=i+1;j<savingLive.count;j++)savingSeparated&=fabs(CGRectGetMidY([savingLive[i] visualFrame])-CGRectGetMidY([savingLive[j] visualFrame]))>=53.5;
        checks[@"B12235_NewLaneCannotOverlapReflowedExistingCapsule"]=@(savingSeparated);
        [defaults setBool:NO forKey:@"barrageFullScreen"];[controller refreshPreferences];
        for(NSUInteger i=130;i<140;i++)[controller enqueueMessage:WPB122Message(i)];
        checks[@"B12236_LowerBudgetGrandfathersExistingThreeWithoutNewWork"]=@(WPB122Live(controller).count==3&&[[controller valueForKey:@"pending"] count]==6);
        WPB122Finish(controller,WPB122Live(controller).firstObject);
        checks[@"B12237_EqualToLowerBudgetDoesNotRefillFreedTrack"]=@(WPB122Live(controller).count==2&&[[controller valueForKey:@"pending"] count]==6);
        WPB122Finish(controller,WPB122Live(controller).firstObject);
        checks[@"B12238_BelowLowerBudgetResumesAtMostOneReplacement"]=@(WPB122Live(controller).count==2&&[[controller valueForKey:@"pending"] count]==5);
        savingLive=WPB122Live(controller);savingSeparated=YES;
        for(NSUInteger i=0;i<savingLive.count;i++)for(NSUInteger j=i+1;j<savingLive.count;j++)savingSeparated&=fabs(CGRectGetMidY([savingLive[i] visualFrame])-CGRectGetMidY([savingLive[j] visualFrame]))>=53.5;
        checks[@"B12239_DrainingTransitionRetainsSafeTrackSeparation"]=@(savingSeparated);

    } @catch(NSException *exception) {
        checks[[NSString stringWithFormat:@"B122_Exception_%@",exception.name]]=@NO;
    } @finally {
        controller.active=NO;[controller purgeForMemoryPressure];controller.onBatchCompleted=nil;controller.onDockMessage=nil;controller.onDock=nil;controller.onShouldDock=nil;controller.onPlaybackChanged=nil;[controller.view removeFromSuperview];window.hidden=YES;
        for(NSString *key in keys){id old=saved[key];if(old)[WPPreferences() setObject:old forKey:key];else [WPPreferences() removeObjectForKey:key];}
    }
    return checks;
}
