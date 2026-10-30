#import "WPBarrageChecks.h"
#import "WPMessageBarrage.h"
#import "WPBarragePreferences.h"
#import "WPCommon.h"
#import <QuartzCore/QuartzCore.h>
extern UIImage *WPBarragePreviewSmallImage(UIImage *image);

@interface WPMessageBarrageController (WPBarrageTesting)
- (void)finishBubble:(id)bubble sequence:(NSUInteger)sequence motion:(NSUInteger)motion finished:(BOOL)finished;
- (void)finishFlightSequence:(NSUInteger)sequence motion:(NSUInteger)motion finished:(BOOL)finished;
- (void)suspend:(NSNotification *)note;
- (void)resume:(NSNotification *)note;
- (void)pump;
- (void)acceptAvatar:(UIImage *)image username:(NSString *)username generation:(NSUInteger)generation;
@end
@interface UIControl (WPBarrageVisualTesting)
- (CGRect)visualFrame;
@end

static WPBarrageMessage *WPBarrageFixture(NSString *chat, NSString *text, NSUInteger sequence) {
    WPBarrageMessage *message=[WPBarrageMessage new];message.conversationUsername=chat;message.senderUsername=chat;
    message.identifier=[NSString stringWithFormat:@"barrage-fixture-%lu",(unsigned long)sequence];message.text=text;return message;
}
static NSArray<UIControl *> *WPBarrageLive(WPMessageBarrageController *controller) {
    NSMutableArray *result=[NSMutableArray new];
    for(UIControl *control in [controller valueForKey:@"bubbles"])if([control valueForKey:@"record"])[result addObject:control];
    return result;
}
static void WPBarrageFinish(WPMessageBarrageController *controller, UIControl *bubble, BOOL finished) {
    id record=[bubble valueForKey:@"record"];
    [controller finishBubble:bubble sequence:[[record valueForKey:@"sequence"] unsignedIntegerValue] motion:[[bubble valueForKey:@"motionSerial"] unsignedIntegerValue] finished:finished];
}
static void WPBarrageFinishFlight(WPMessageBarrageController *controller, BOOL finished) {
    UIControl *flight=[controller valueForKey:@"flight"];id record=[flight valueForKey:@"record"];
    [controller finishFlightSequence:[[record valueForKey:@"sequence"] unsignedIntegerValue] motion:[[flight valueForKey:@"motionSerial"] unsignedIntegerValue] finished:finished];
}
static BOOL WPBarrageBodiesEmpty(WPMessageBarrageController *controller) {
    for(id record in [controller valueForKey:@"pending"])if([[record valueForKey:@"body"] length])return NO;
    for(UIControl *bubble in [controller valueForKey:@"bubbles"]) {
        if([[[bubble valueForKey:@"record"] valueForKey:@"body"] length])return NO;
        if(((UILabel *)[bubble valueForKey:@"bodyLabel"]).text.length)return NO;
        if([bubble.accessibilityLabel containsString:@"secret"]||[bubble.accessibilityValue containsString:@"secret"])return NO;
    }
    return ![[[[controller valueForKey:@"flight"] valueForKey:@"record"] valueForKey:@"body"] length];
}

NSDictionary<NSString *,NSNumber *> *WPBarragePreviewChecks(void) {
    NSMutableDictionary *checks=[NSMutableDictionary new];
    NSArray *keys=@[@"barrageEnabled",@"barrageShowsDetails",@"barrageFullScreen",@"barrageSpeed",@"barrageBackgroundOpacity",@"barrageReactionsEnabled",@"barrageQuietEnabled",@"barrageQuietStart",@"barrageQuietEnd",@"barrageContactsOnly",@"barrageContactUsernames",@"barragePauseUntil",@"barrageAdaptiveSaving",@"barrageAllowPrivate",@"barrageAllowGroup"];
    NSDictionary *domain=[WPPreferences() persistentDomainForName:@"dev.zhour.wechatpet"]?:@{};
    UIWindow *window=nil;WPMessageBarrageController *controller=nil;
    @try {
        [WPPreferences() setBool:YES forKey:@"barrageEnabled"];[WPPreferences() setBool:YES forKey:@"barrageShowsDetails"];
        [WPPreferences() setBool:NO forKey:@"barrageFullScreen"];[WPPreferences() setDouble:1 forKey:@"barrageSpeed"];
        [WPPreferences() setDouble:.68 forKey:@"barrageBackgroundOpacity"];[WPPreferences() setBool:NO forKey:@"barrageReactionsEnabled"];
        [WPPreferences() setBool:NO forKey:@"barrageQuietEnabled"];[WPPreferences() setBool:NO forKey:@"barrageContactsOnly"];
        [WPPreferences() removeObjectForKey:@"barragePauseUntil"];[WPPreferences() setBool:NO forKey:@"barrageAdaptiveSaving"];
        [WPPreferences() setBool:YES forKey:@"barrageAllowPrivate"];[WPPreferences() setBool:YES forKey:@"barrageAllowGroup"];
        window=[[UIWindow alloc] initWithFrame:CGRectMake(0,0,393,852)];window.windowLevel=-100;
        window.rootViewController=[UIViewController new];window.hidden=NO;
        UIView *host=window.rootViewController.view;host.frame=window.bounds;
        controller=[[WPMessageBarrageController alloc] initWithHostView:host];
        [controller setValue:@YES forKey:@"previewSkipNativePolicy"];
        [controller setValue:[^UIImage *(__unused NSString *username){return nil;} copy] forKey:@"previewAvatarProvider"];
        [controller setValue:@YES forKey:@"foregroundAvailable"];controller.active=YES;
        CGRect safe=CGRectMake(0,64,393,714),dock=CGRectMake(305,560,36,36);
        [controller updateLayoutSafeRect:safe obstacles:@[] dockFrame:dock];
        __block NSString *docked=nil,*opened=nil;__block NSUInteger docks=0,reactions=0;
        controller.onDock=^(NSString *chat,__unused NSString *sender,__unused UIImage *image){docked=chat;docks++;};
        controller.onOpenConversation=^(NSString *chat){opened=chat;};controller.onPetReaction=^{reactions++;};
        checks[@"barrageFixedSixReusableControls"]=@([[controller valueForKey:@"bubbles"] count]==6&&controller.view.subviews.count==7);
        checks[@"barrageEmptySurfacePassesTouches"]=@([controller hitTest:CGPointMake(120,200) withEvent:nil]==nil);
        checks[@"barrageHalfUsesAtMostThreeSafeTracks"]=@([[controller valueForKey:@"laneYs"] count]==3);
        for(NSUInteger i=0;i<40;i++)[controller enqueueMessage:WPBarrageFixture([NSString stringWithFormat:@"wxid_barrage_stress_%lu",(unsigned long)i],@"secret burst body",i)];
        checks[@"barrageBurstUsesThreeControlsAndTwelvePending"]=@(WPBarrageLive(controller).count==3&&[[controller valueForKey:@"pending"] count]==12);
        checks[@"barrageDedupeLedgerBounded"]=@([[controller valueForKey:@"recentIdentifiers"] count]<=64);
        checks[@"barrageAvatarTransfersAndDecodeInFlightAtMostTwo"]=@([[controller valueForKey:@"avatarLoads"] count]<=2&&[[controller valueForKey:@"downloads"] count]<=2);
        checks[@"barrageAvatarCacheAtMostOneMiB"]=@(((NSCache *)[controller valueForKey:@"avatars"]).totalCostLimit==1024*1024);
        UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat defaultFormat];format.scale=1;
        UIImage *large=[[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(768,768) format:format] imageWithActions:^(__unused UIGraphicsImageRendererContext *context){[UIColor.systemBlueColor setFill];UIRectFill(CGRectMake(0,0,768,768));}];
        __block UIImage *small=nil;__block BOOL decodedOffMain=NO;
        dispatch_semaphore_t decoded=dispatch_semaphore_create(0);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{decodedOffMain=!NSThread.isMainThread;small=WPBarragePreviewSmallImage(large);dispatch_semaphore_signal(decoded);});
        dispatch_semaphore_wait(decoded,dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC));
        checks[@"barrageAvatarDecodeProducesAtMost96PixelsOffMain"]=@(decodedOffMain&&CGImageGetWidth(small.CGImage)<=96&&CGImageGetHeight(small.CGImage)<=96);
        checks[@"barrageTwentyFourDecodedAvatarsFitBelowOneMiB"]=@(CGImageGetBytesPerRow(small.CGImage)*CGImageGetHeight(small.CGImage)*24<1024*1024);
        large=nil;small=nil;
        checks[@"barrageReactionsSwitchRespected"]=@(reactions==0);
        UIControl *first=WPBarrageLive(controller).firstObject;
        checks[@"barrageSemitransparentRoundedCapsule"]=@(fabs(CGColorGetAlpha(first.backgroundColor.CGColor)-.68)<.01&&first.layer.cornerRadius==23);
        checks[@"barrageNameAndRemarkHiddenByDefault"]=@([first.subviews[0] isKindOfClass:UIImageView.class]&&[first.subviews[1] isKindOfClass:UILabel.class]&&((UILabel *)[first valueForKey:@"nameLabel"]).hidden&&!((UILabel *)[first valueForKey:@"nameLabel"]).text.length);
        checks[@"barrageMovingTapUsesRecognizerAndAccessibility"]=@(first.gestureRecognizers.count==1&&first.isAccessibilityElement&&(first.accessibilityTraits&UIAccessibilityTraitButton));
        [controller purgeForMemoryPressure];
        checks[@"barragePressureDropsAllBodiesAndMotionSynchronously"]=@(!controller.isDisplaying&&WPBarrageBodiesEmpty(controller)&&![[controller valueForKey:@"downloads"] count]&&![[controller valueForKey:@"avatarLoads"] count]);
        BOOL emptyControls=YES;for(UIControl *bubble in [controller valueForKey:@"bubbles"])emptyControls&=([bubble valueForKey:@"record"]==nil&&((UIImageView *)[bubble valueForKey:@"avatarView"]).image==nil&&bubble.layer.animationKeys.count==0);
        checks[@"barragePressureReleasesEachAvatarAndCompletedRecord"]=@(emptyControls);

        [controller enqueueMessage:WPBarrageFixture(@"wxid_barrage_old",@"old message",100)];
        UIControl *old=WPBarrageLive(controller).firstObject;id oldRecord=[old valueForKey:@"record"];
        [controller enqueueMessage:WPBarrageFixture(@"wxid_barrage_new",@"new",101)];
        UIControl *new=WPBarrageLive(controller).lastObject;
        WPBarrageFinish(controller,old,NO);
        checks[@"barrageCancelledScrollCannotDockOrFinish"]=@(docks==0&&[old valueForKey:@"record"]==oldRecord);
        WPBarrageFinish(controller,new,YES);WPBarrageFinishFlight(controller,YES);
        checks[@"barrageEarlierFinishWaitsUntilBurstEnds"]=@(docks==0);
        WPBarrageFinish(controller,old,YES);WPBarrageFinishFlight(controller,YES);
        checks[@"barrageLatestEligibleMessageOwnsSingleDockAfterLastFinish"]=@(docks==1&&[docked isEqual:@"wxid_barrage_new"]);
        checks[@"barrageFinishedBodyReleased"]=@(![[oldRecord valueForKey:@"body"] length]&&[old valueForKey:@"record"]==nil&&((UILabel *)[old valueForKey:@"bodyLabel"]).text==nil);

        [controller enqueueMessage:WPBarrageFixture(@"wxid_barrage_flight_old",@"flight old",102)];
        WPBarrageFinish(controller,WPBarrageLive(controller).firstObject,YES);
        UIControl *flight=[controller valueForKey:@"flight"];NSUInteger staleSequence=[[[flight valueForKey:@"record"] valueForKey:@"sequence"] unsignedIntegerValue],staleMotion=[[flight valueForKey:@"motionSerial"] unsignedIntegerValue];
        [controller enqueueMessage:WPBarrageFixture(@"wxid_barrage_flight_new",@"flight new",103)];
        [controller finishFlightSequence:staleSequence motion:staleMotion finished:YES];
        checks[@"barrageNewArrivalAndStaleFlightCannotDuplicateCompletedBatch"]=@(docks==2&&[flight valueForKey:@"record"]==nil);
        [controller purgeForMemoryPressure];

        for(NSUInteger i=0;i<8;i++)[controller enqueueMessage:WPBarrageFixture([NSString stringWithFormat:@"wxid_barrage_private_%lu",(unsigned long)i],@"secret private body",200+i)];
        [WPPreferences() setBool:NO forKey:@"barrageShowsDetails"];[controller refreshPreferences];
        checks[@"barrageHideScrubsActiveQueuedAndAccessibilityText"]=@(WPBarrageBodiesEmpty(controller));
        BOOL collapsed=YES;for(UIControl *bubble in WPBarrageLive(controller))collapsed&=bubble.bounds.size.width==46;
        checks[@"barrageHideCollapsesToAvatarWithoutRestartingRight"]=@(collapsed);
        [WPPreferences() setBool:YES forKey:@"barrageShowsDetails"];[controller refreshPreferences];
        checks[@"barrageRestoreNeverRevealsOldText"]=@(WPBarrageBodiesEmpty(controller));
        [controller purgeForMemoryPressure];[controller enqueueMessage:WPBarrageFixture(@"wxid_barrage_future",@"future text",220)];
        checks[@"barrageRestoreAppliesOnlyToFutureMessages"]=@([((UILabel *)[WPBarrageLive(controller).firstObject valueForKey:@"bodyLabel"]).text isEqual:@"future text"]);
        [controller purgeForMemoryPressure];

        WPBarrageMessage *coalesced=WPBarrageFixture(@"wxid_barrage_duplicate",@"same body",300);
        [controller enqueueMessage:coalesced];[controller enqueueMessage:coalesced];
        checks[@"barrageDuplicateIdentifierShowsOnce"]=@(WPBarrageLive(controller).count==1&&[[controller valueForKey:@"pending"] count]==0);
        UIControl *slow=WPBarrageLive(controller).firstObject;double firstDuration=[[slow valueForKey:@"motionDuration"] doubleValue];
        [WPPreferences() setDouble:2 forKey:@"barrageSpeed"];[controller refreshPreferences];
        checks[@"barrageSpeedChangeDoesNotRestartExistingScroll"]=@(fabs([[slow valueForKey:@"motionDuration"] doubleValue]-firstDuration)<.001&&[[slow valueForKey:@"pixelsPerSecond"] doubleValue]==80);
        [controller enqueueMessage:WPBarrageFixture(@"wxid_barrage_speed",@"same body",301)];
        UIControl *fast=WPBarrageLive(controller).lastObject;
        checks[@"barrageSpeedChangeAppliesToNextMessage"]=@([[fast valueForKey:@"pixelsPerSecond"] doubleValue]==160&&[[fast valueForKey:@"motionDuration"] doubleValue]<firstDuration*.51);
        [controller purgeForMemoryPressure];

        [WPPreferences() setBool:YES forKey:@"barrageFullScreen"];[controller refreshPreferences];
        for(NSUInteger i=0;i<9;i++)[controller enqueueMessage:WPBarrageFixture([NSString stringWithFormat:@"wxid_barrage_full_%lu",(unsigned long)i],@"full track",400+i)];
        checks[@"barrageFullUsesSixControlsAndNoExtraViews"]=@(WPBarrageLive(controller).count==6&&controller.view.subviews.count==7);
        [controller updateLayoutSafeRect:safe obstacles:@[] dockFrame:CGRectMake(270,520,36,36)];
        checks[@"barragePetMoveKeepsActiveCapsules"]=@(WPBarrageLive(controller).count==6);
        NSValue *petObstacle=[NSValue valueWithCGRect:CGRectMake(270,650,88,96)];
        [controller updateLayoutSafeRect:safe obstacles:@[petObstacle] dockFrame:CGRectMake(270,520,36,36)];
        checks[@"barragePetObstacleMovePreservesUnaffectedTracks"]=@(WPBarrageLive(controller).count==6);
        [controller updateLayoutSafeRect:safe obstacles:@[petObstacle,petObstacle] dockFrame:CGRectMake(270,520,36,36)];
        checks[@"barrageDuplicateDockObstacleDoesNotRestartMotion"]=@(WPBarrageLive(controller).count==6);
        // Geometry changes preserve messages; they never count as a completed burst.
        [controller updateLayoutSafeRect:CGRectMake(0,64,393,420) obstacles:@[] dockFrame:CGRectMake(270,380,36,36)];
        checks[@"barrageResizeKeepsTracksAndDoesNotDock"]=@(controller.isDisplaying&&WPBarrageLive(controller).count==6);
        [controller purgeForMemoryPressure];
        [controller updateLayoutSafeRect:safe obstacles:@[[NSValue valueWithCGRect:safe]] dockFrame:dock];
        [controller enqueueMessage:WPBarrageFixture(@"wxid_barrage_blocked",@"blocked",420)];
        checks[@"barrageObstaclesNeverCreateOverlappingTrack"]=@(WPBarrageLive(controller).count==0&&[[controller valueForKey:@"laneYs"] count]==0);
        [controller purgeForMemoryPressure];[controller updateLayoutSafeRect:safe obstacles:@[] dockFrame:dock];

        // Freeze the render server's actual presentation midway through the
        // track. The model remains beyond the left edge throughout.
        [controller enqueueMessage:WPBarrageFixture(@"wxid_barrage_tap",@"tap moving text",500)];
        UIControl *moving=WPBarrageLive(controller).firstObject;CALayer *layer=moving.layer;
        CAAnimation *animation=[[layer animationForKey:@"WPBarrageMove"] copy];
        animation.speed=0;animation.timeOffset=animation.duration*.5;animation.beginTime=0;
        [layer addAnimation:animation forKey:@"WPBarrageMove"];[CATransaction flush];
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.08]];
        CGRect visual=[moving visualFrame],visible=CGRectIntersection(visual,controller.view.bounds);
        CGPoint touch=CGPointMake(CGRectGetMidX(visible),CGRectGetMidY(visible));
        UIView *hit=[controller hitTest:touch withEvent:nil];
        checks[@"barrageTapFindsRenderedPositionNotOffscreenModel"]=@(visible.size.width>0&&hit==moving&&CGRectGetMaxX(moving.frame)<0);
        checks[@"barrageControlEndTrackingConvertsBackToPresentationSpace"]=@([moving pointInside:[controller.view convertPoint:touch toView:moving] withEvent:nil]);
        checks[@"barrageEmptyRegionStillPassesTouchesDuringMotion"]=@([controller hitTest:CGPointMake(200,800) withEvent:nil]==nil);
        NSUInteger currentSequence=[[[moving valueForKey:@"record"] valueForKey:@"sequence"] unsignedIntegerValue];
        [moving setValue:@(currentSequence-1) forKey:@"trackingSequence"];
        [moving sendActionsForControlEvents:UIControlEventTouchUpInside];
        checks[@"barrageReusedControlRejectsEarlierTouchSequence"]=@(opened==nil&&controller.isDisplaying);
        [moving accessibilityActivate];
        checks[@"barrageTapOpensMatchingConversationAndClearsTransientText"]=@([opened isEqual:@"wxid_barrage_tap"]&&!controller.isDisplaying&&WPBarrageBodiesEmpty(controller));

        WPBarrageMessage *group=WPBarrageFixture(@"barrage-group@chatroom",@"group body",501);group.senderUsername=@"wxid_barrage_group_sender";
        [controller enqueueMessage:group];[WPBarrageLive(controller).firstObject accessibilityActivate];
        checks[@"barrageGroupTapOpensGroupNotSenderPrivateChat"]=@([opened isEqual:@"barrage-group@chatroom"]);
        [controller setValue:@YES forKey:@"previewReducedMotion"];
        [controller enqueueMessage:WPBarrageFixture(@"wxid_barrage_reduced",@"reduced motion",600)];
        UIControl *reduced=WPBarrageLive(controller).firstObject;
        checks[@"barrageReduceMotionUsesBriefStaticCapsule"]=@(reduced.layer.animationKeys.count==0&&CGRectGetMinX(reduced.frame)>=0&&CGRectGetMaxX(reduced.frame)<=393);
        WPBarrageFinish(controller,reduced,YES);
        checks[@"barrageReduceMotionSettlesWithoutFlying"]=@([docked isEqual:@"wxid_barrage_reduced"]&&[flight valueForKey:@"record"]==nil);
        [controller setValue:@NO forKey:@"previewReducedMotion"];
        [controller enqueueMessage:WPBarrageFixture(@"wxid_barrage_suspend",@"secret background",610)];[controller suspend:nil];
        checks[@"barrageBackgroundSynchronouslyDropsBodiesAndHides"]=@(!controller.isDisplaying&&controller.view.hidden&&WPBarrageBodiesEmpty(controller));
        [controller enqueueMessage:WPBarrageFixture(@"wxid_barrage_no_background",@"must not show",611)];
        checks[@"barrageBackgroundArrivalsNeverQueueForReplay"]=@(!controller.isDisplaying);
        [controller resume:nil];
        checks[@"barrageForegroundResumesWithEmptyQueue"]=@(!controller.isDisplaying&&!controller.view.hidden);
        [controller enqueueMessage:WPBarrageFixture(@"wxid_barrage_disabled",@"secret disabled",620)];[WPPreferences() setBool:NO forKey:@"barrageEnabled"];[controller refreshPreferences];
        checks[@"barrageDisablePurgesAndPassesAllTouches"]=@(!controller.isDisplaying&&controller.view.hidden&&WPBarrageBodiesEmpty(controller)&&[controller hitTest:CGPointMake(120,200) withEvent:nil]==nil);
        [WPPreferences() setBool:YES forKey:@"barrageEnabled"];[controller refreshPreferences];
        [WPPreferences() setBool:YES forKey:@"barrageQuietEnabled"];[WPPreferences() setInteger:0 forKey:@"barrageQuietStart"];[WPPreferences() setInteger:0 forKey:@"barrageQuietEnd"];
        [controller enqueueMessage:WPBarrageFixture(@"wxid_barrage_quiet",@"quiet",630)];
        checks[@"barrageQuietHoursPolicyRespected"]=@(!controller.isDisplaying);
        [WPPreferences() setBool:NO forKey:@"barrageQuietEnabled"];[WPPreferences() setBool:YES forKey:@"barrageContactsOnly"];[WPPreferences() setObject:@"wxid_barrage_allowed" forKey:@"barrageContactUsernames"];
        [controller enqueueMessage:WPBarrageFixture(@"wxid_barrage_denied",@"deny",631)];
        checks[@"barrageReminderContactPolicyRespected"]=@(!controller.isDisplaying);
        [WPPreferences() setBool:NO forKey:@"barrageContactsOnly"];[WPPreferences() setBool:NO forKey:@"barrageQuietEnabled"];
        [controller purgeForMemoryPressure];[WPPreferences() setBool:NO forKey:@"barrageFullScreen"];[controller refreshPreferences];
        for(NSUInteger i=0;i<3;i++)[controller enqueueMessage:WPBarrageFixture([NSString stringWithFormat:@"wxid_barrage_ttl_active_%lu",(unsigned long)i],@"active",700+i)];
        WPBarrageMessage *expired=WPBarrageFixture(@"wxid_barrage_expired",@"secret expired",704);
        [controller enqueueMessage:expired];id expiring=[[controller valueForKey:@"pending"] firstObject];
        checks[@"barrage121PendingRetainsCreatedAndMonotonicArrival"]=@([[expiring valueForKey:@"createdAt"] isEqual:expired.createdAt]&&[[expiring valueForKey:@"arrivedAt"] doubleValue]>0&&[[expiring valueForKey:@"expiresAt"] doubleValue]-[[expiring valueForKey:@"arrivedAt"] doubleValue]<=12.01);
        [expiring setValue:@(CACurrentMediaTime()-1) forKey:@"expiresAt"];
        [controller enqueueMessage:WPBarrageFixture(@"wxid_barrage_fresh_after_expired",@"fresh",705)];
        WPBarrageFinish(controller,WPBarrageLive(controller).firstObject,YES);
        BOOL expiredVisible=NO,freshVisible=NO;for(UIControl *bubble in WPBarrageLive(controller)){NSString *chat=[[bubble valueForKey:@"record"] valueForKey:@"conversation"];expiredVisible|=[chat isEqual:@"wxid_barrage_expired"];freshVisible|=[chat isEqual:@"wxid_barrage_fresh_after_expired"];}
        checks[@"barrage121ExpiredQueuedBodyErasedBeforePlayback"]=@(!expiredVisible&&freshVisible&&![[expiring valueForKey:@"body"] length]);
        WPBarrageMessage *oldMessage=WPBarrageFixture(@"wxid_barrage_already_old",@"old",706);oldMessage.createdAt=[NSDate dateWithTimeIntervalSinceNow:-20];
        NSUInteger before=WPBarrageLive(controller).count+[[controller valueForKey:@"pending"] count];[controller enqueueMessage:oldMessage];
        checks[@"barrage121OldSourceTimestampCannotRestartQueueLifetime"]=@(before==WPBarrageLive(controller).count+[[controller valueForKey:@"pending"] count]);
        [controller enqueueMessage:WPBarrageFixture(@"wxid_barrage_quiet_pending",@"secret queued quiet",707)];id quietPending=[[controller valueForKey:@"pending"] firstObject];
        [WPPreferences() setBool:YES forKey:@"barrageQuietEnabled"];[WPPreferences() setInteger:0 forKey:@"barrageQuietStart"];[WPPreferences() setInteger:0 forKey:@"barrageQuietEnd"];[controller pump];
        checks[@"barrage121QuietChangeScrubsQueuedAndActiveBeforePlayback"]=@(!controller.isDisplaying&&![[quietPending valueForKey:@"body"] length]);
        [WPPreferences() setBool:NO forKey:@"barrageQuietEnabled"];[controller purgeForMemoryPressure];

        __block NSUInteger attempts=0;__block BOOL avatarSucceeds=NO;
        UIImage *tiny=[[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(32,32) format:format] imageWithActions:^(__unused UIGraphicsImageRendererContext *context){[UIColor.systemPurpleColor setFill];UIRectFill(CGRectMake(0,0,32,32));}];
        [controller setValue:[^UIImage *(__unused NSString *username){attempts++;return avatarSucceeds?tiny:nil;} copy] forKey:@"previewAvatarProvider"];
        [controller enqueueMessage:WPBarrageFixture(@"wxid_barrage_retry",@"retry avatar",710)];
        id state=[controller valueForKey:@"avatarStates"][@"wxid_barrage_retry"];
        CFTimeInterval firstDelay=[[state valueForKey:@"nextAttempt"] doubleValue]-CACurrentMediaTime();
        checks[@"barrage121AvatarFailureEntersTwoSecondCooldown"]=@(attempts==1&&[[state valueForKey:@"failures"] unsignedIntegerValue]==1&&firstDelay>1.8&&firstDelay<=2.01);
        for(NSUInteger i=0;i<10;i++)[controller pump];
        checks[@"barrage121AvatarCooldownNeverRetriesPerFrameOrPump"]=@(attempts==1&&[controller valueForKey:@"workTimer"]!=nil);
        [state setValue:@0 forKey:@"nextAttempt"];[controller pump];CFTimeInterval secondDelay=[[state valueForKey:@"nextAttempt"] doubleValue]-CACurrentMediaTime();
        [state setValue:@0 forKey:@"nextAttempt"];[controller pump];CFTimeInterval thirdDelay=[[state valueForKey:@"nextAttempt"] doubleValue]-CACurrentMediaTime();
        checks[@"barrage121AvatarRetriesBackOffFiveThenFifteenSeconds"]=@(attempts==3&&secondDelay>4.8&&secondDelay<=5.01&&thirdDelay>14.8&&thirdDelay<=15.01);
        avatarSucceeds=YES;[state setValue:@0 forKey:@"nextAttempt"];[controller pump];
        UIControl *retryBubble=WPBarrageLive(controller).firstObject;
        checks[@"barrage121AvatarFailureRecoversIntoSameVisibleBubble"]=@(attempts==4&&[retryBubble valueForKey:@"actualAvatar"]==tiny&&[[state valueForKey:@"failures"] unsignedIntegerValue]==0);
        [(NSCache *)[controller valueForKey:@"avatars"] removeAllObjects];[retryBubble setValue:nil forKey:@"actualAvatar"];[controller pump];
        checks[@"barrage121AvatarSuccessLedgerRecoversAfterCacheEviction"]=@(attempts==5&&[retryBubble valueForKey:@"actualAvatar"]==tiny);
        NSUInteger staleGeneration=[[controller valueForKey:@"generation"] unsignedIntegerValue];[controller purgeForMemoryPressure];
        [controller acceptAvatar:tiny username:@"wxid_barrage_stale" generation:staleGeneration];
        checks[@"barrage121LifecycleCancelsOnlyWorkTimerAndAllRetryState"]=@([controller valueForKey:@"workTimer"]==nil&&[[controller valueForKey:@"avatarStates"] count]==0&&[[controller valueForKey:@"avatarRequests"] count]==0&&[[controller valueForKey:@"localPreparations"] count]==0);
        checks[@"barrage121LateAvatarCannotRepopulateAfterPurge"]=@([(NSCache *)[controller valueForKey:@"avatars"] objectForKey:@"wxid_barrage_stale"]==nil);
        [controller setValue:[^UIImage *(__unused NSString *username){return nil;} copy] forKey:@"previewAvatarProvider"];

        [controller setValue:@YES forKey:@"previewSavingResources"];[WPPreferences() setBool:YES forKey:@"barrageReactionsEnabled"];[controller refreshPreferences];NSUInteger reactionsBefore=reactions;
        for(NSUInteger i=0;i<20;i++)[controller enqueueMessage:WPBarrageFixture([NSString stringWithFormat:@"wxid_barrage_saving_%lu",(unsigned long)i],@"saving",800+i)];
        checks[@"barrage121SavingHalfUsesTwoTracksSixPending"]=@(WPBarrageLive(controller).count==2&&[[controller valueForKey:@"pending"] count]==6);
        checks[@"barrage121SavingSkipsPetAcknowledgements"]=@(reactions==reactionsBefore);
        [WPPreferences() setBool:YES forKey:@"barrageFullScreen"];[controller refreshPreferences];
        for(NSUInteger i=0;i<20;i++)[controller enqueueMessage:WPBarrageFixture([NSString stringWithFormat:@"wxid_barrage_saving_full_%lu",(unsigned long)i],@"saving",830+i)];
        checks[@"barrage121SavingFullUsesThreeTracksSixPending"]=@(WPBarrageLive(controller).count==3&&[[controller valueForKey:@"pending"] count]==6);
        [controller purgeForMemoryPressure];[controller setValue:@NO forKey:@"previewSavingResources"];[controller refreshPreferences];
        [WPPreferences() setDouble:NSDate.date.timeIntervalSince1970+600 forKey:@"barragePauseUntil"];[controller refreshPreferences];[controller enqueueMessage:WPBarrageFixture(@"wxid_barrage_paused",@"paused",860)];
        checks[@"barrage121PauseKeepsMasterSwitchButBlocksAndPurges"]=@(WPBarrageEnabled()&&!controller.isDisplaying&&controller.view.hidden);
        [WPPreferences() removeObjectForKey:@"barragePauseUntil"];[controller refreshPreferences];
        [controller setValue:@NO forKey:@"previewSkipNativePolicy"];[WPPreferences() setBool:YES forKey:@"barrageContactsOnly"];[WPPreferences() setObject:@[] forKey:@"barrageContactUsernames"];
        WPBarrageMessage *preview=WPBarrageFixture(@"__wp_barrage_preview__",@"本机测试弹幕",870);preview.localPreview=YES;[controller enqueueMessage:preview];
        checks[@"barrage121ExplicitLocalPreviewWorksWithoutNativeContactOrAvatarLookup"]=@(WPBarrageLive(controller).count==1&&[[controller valueForKey:@"avatarStates"] count]==0&&[[controller valueForKey:@"localPreparations"] count]==0);
        [WPPreferences() setBool:NO forKey:@"barrageShowsDetails"];[controller refreshPreferences];
        checks[@"barrage121LocalPreviewStillRespectsDetailPrivacy"]=@(WPBarrageBodiesEmpty(controller));
        checks[@"barrageNormalExecutionHasNoUnexpectedException"]=@YES;
    } @catch(NSException *exception) {checks[@"barrageNormalExecutionHasNoUnexpectedException"]=@NO;NSLog(@"Barrage checks: %@ %@",exception.name,exception.reason);}
    @finally {
        controller.active=NO;[controller purgeForMemoryPressure];window.hidden=YES;
        for(NSString *key in keys){id value=domain[key];if(value)[WPPreferences() setObject:value forKey:key];else [WPPreferences() removeObjectForKey:key];}
    }
    return checks;
}
