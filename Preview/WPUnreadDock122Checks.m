#import "WPUnreadDock122Checks.h"
#import "WPUnreadDockState.h"
#import "WPQuickChatModel.h"
#import "WPMessageBarrage.h"
#import <math.h>
#import <QuartzCore/QuartzCore.h>

static WPQuickChatSession *WPD122Row(NSString *name,NSUInteger unread,NSTimeInterval time) {
    return [WPQuickChatSession sessionWithUsername:name unread:unread muted:NO pinned:NO time:time];
}
static WPBarrageMessage *WPD122Message(NSString *name,NSString *identifier,NSTimeInterval time) {
    WPBarrageMessage *message=[WPBarrageMessage new];message.conversationUsername=name;message.senderUsername=[name stringByAppendingString:@"_sender"];
    message.identifier=identifier;message.createdAt=[NSDate dateWithTimeIntervalSince1970:time];message.text=@"这段正文不应被停靠状态保留";return message;
}
NSDictionary<NSString *,NSNumber *> *WPUnreadDock122PreviewChecks(void) {
    NSMutableDictionary *checks=[NSMutableDictionary new];
    @try {
        NSTimeInterval now=NSDate.date.timeIntervalSince1970;
        WPUnreadDockState *state=[WPUnreadDockState new];
        [state observeUnreadSession:WPD122Row(@"wxid_a",2,now-10) genuineArrival:NO];NSString *first=state.revision;
        checks[@"D12201_UnreadUsesTheSingleDockSlot"]=@(state.visible&&[state.conversationUsername isEqual:@"wxid_a"]&&[state.senderUsername isEqual:@"wxid_a"]&&first.length);
        [state observeUnreadSession:WPD122Row(@"wxid_a",2,now-10) genuineArrival:NO];
        checks[@"D12202_OrdinaryPollingKeepsRevisionStable"]=@([state.revision isEqual:first]);
        WPBarrageMessage *message=WPD122Message(@"wxid_b",@"native-b",now);NSString *receipt=[state markBarrageMessageReceived:message];
        state.playbackPending=YES;[state observeUnreadSession:WPD122Row(@"wxid_b",1,now) genuineArrival:YES];
        checks[@"D12203_PollingCannotStealTheSlotDuringPlayback"]=@([state.revision isEqual:first]&&receipt.length);
        UIImage *image=[UIImage systemImageNamed:@"person.fill"];
        BOOL docked=[state dockMessage:message image:image];state.playbackPending=NO;
        checks[@"D12204_NativeDockUsesSameRouteAndGroupSender"]=@(docked&&[state.revision isEqual:receipt]&&[state.conversationUsername isEqual:@"wxid_b"]&&[state.senderUsername isEqual:@"wxid_b_sender"]&&state.image==image);
        [state observeUnreadSession:nil genuineArrival:NO];
        checks[@"D12205_LaggingUnreadSnapshotCannotEraseNativeDock"]=@(state.visible&&[state.revision isEqual:receipt]);
        [state releaseImageKeepingIdentity];
        checks[@"D12206_LifecyclePixelReleaseKeepsIdentityAndRevision"]=@(!state.image&&[state.revision isEqual:receipt]&&state.visible);
        BOOL consumed=[state consumeRevision:receipt];
        checks[@"D12207_SuccessfulOpenClearsCurrentAvatar"]=@(consumed&&!state.visible&&!state.revision&&!state.conversationUsername);
        [state observeUnreadSession:WPD122Row(@"wxid_b",1,now) genuineArrival:NO];
        checks[@"D12208_PollingSameUnreadCannotResurrectConsumedAvatar"]=@(!state.visible);
        [state observeUnreadSession:WPD122Row(@"wxid_a",2,now-10) genuineArrival:NO];
        checks[@"D12209_OtherOldUnreadDoesNotImmediatelyReplaceConsumedAvatar"]=@(!state.visible);
        checks[@"D12210_AlreadyReceivedNativeMessageCannotDockAgain"]=@(![state shouldDockMessage:message]&&![state dockMessage:message image:image]);
        [state observeUnreadSession:WPD122Row(@"wxid_b",2,now) genuineArrival:NO];
        checks[@"D12211_UnreadCountGrowthRestoresTheIndicator"]=@(state.visible&&[state.conversationUsername isEqual:@"wxid_b"]);
        [state clear];[state observeUnreadSession:WPD122Row(@"wxid_b",1,now) genuineArrival:NO];[state observeUnreadSession:WPD122Row(@"wxid_b",2,now) genuineArrival:NO];
        checks[@"D12212_CountRegressionAndReturnCannotInventANewMessage"]=@(!state.visible);
        [state observeUnreadSession:WPD122Row(@"wxid_b",2,now+1) genuineArrival:NO];
        checks[@"D12213_MessageTimeGrowthRestoresTheIndicator"]=@(state.visible);
        [state clear];[state observeUnreadSession:WPD122Row(@"wxid_a",2,now-10) genuineArrival:YES];
        checks[@"D12214_ExplicitFreshArrivalRestoresEvenWithoutNativeTime"]=@(state.visible&&[state.conversationUsername isEqual:@"wxid_a"]);
        NSString *oldRevision=state.revision;
        WPBarrageMessage *later=WPD122Message(@"wxid_c",@"later-c",now+2);[state markBarrageMessageReceived:later];[state dockMessage:later image:image];NSString *laterRevision=state.revision;
        BOOL clearedNew=[state consumeRevision:oldRevision];
        checks[@"D12215_OldChatOpenCompletionCannotClearANewerAvatar"]=@(!clearedNew&&state.visible&&[state.revision isEqual:laterRevision]);
        [state observeUnreadSession:WPD122Row(@"wxid_c",1,now+2) genuineArrival:NO];
        checks[@"D12216_StaleConsumptionDoesNotSuppressNewCurrentIdentity"]=@([state.conversationUsername isEqual:@"wxid_c"]);
        NSString *beforeInvalid=state.revision;
        checks[@"D12217_UnknownConsumptionHasNoSideEffects"]=@(![state consumeRevision:@"missing-token"]&&[state.revision isEqual:beforeInvalid]);
        [state resetVisibleOnly];[state observeUnreadSession:WPD122Row(@"wxid_a",2,now-10) genuineArrival:NO];
        checks[@"D12218_VisibleResetPreservesConfirmationWatermark"]=@(!state.visible);

        WPUnreadDockState *sameSecond=[WPUnreadDockState new];
        WPBarrageMessage *one=WPD122Message(@"wxid_same",@"same-1",floor(now));[sameSecond markBarrageMessageReceived:one];[sameSecond dockMessage:one image:nil];[sameSecond clear];
        WPBarrageMessage *two=WPD122Message(@"wxid_same",@"same-2",floor(NSDate.date.timeIntervalSince1970));[sameSecond markBarrageMessageReceived:two];
        checks[@"D12219_DistinctNativeIDInTheSameSecondCanBeGenuinelyNew"]=@([sameSecond shouldDockMessage:two]&&[sameSecond dockMessage:two image:nil]);
        checks[@"D12220_KnownNativeIDRemainsAcknowledgedWithinTheSameSecond"]=@(![sameSecond shouldDockMessage:one]);
        WPBarrageMessage *older=WPD122Message(@"wxid_old",@"old-unseen",now-60);[sameSecond markBarrageMessageReceived:older];
        checks[@"D12221_UnknownOldNativeMessageCannotBypassConsumptionClock"]=@(![sameSecond shouldDockMessage:older]);
        [sameSecond clear];[sameSecond observeUnreadSession:WPD122Row(@"wxid_old",1,now-60) genuineArrival:YES];
        WPBarrageMessage *proof=WPD122Message(@"wxid_old",@"new-after-explicit-arrival",now-59);[sameSecond markBarrageMessageReceived:proof];
        checks[@"D12222_ConfirmedFreshArrivalCanRecoverFromSkewedNativeTime"]=@([sameSecond shouldDockMessage:proof]);

        WPUnreadDockState *read=[WPUnreadDockState new];[read observeUnreadSession:WPD122Row(@"wxid_read",1,now) genuineArrival:NO];
        WPQuickChatSession *unknown=WPD122Row(@"wxid_read",0,now);unknown.unreadKnown=NO;[read observeUnreadSession:unknown genuineArrival:NO];
        checks[@"D12223_UnknownMetadataDoesNotAcknowledgeAnUnreadMessage"]=@(read.visible);
        [read observeUnreadSession:WPD122Row(@"wxid_read",0,now) genuineArrival:NO];
        checks[@"D12224_ExplicitReadObservationClearsTheCurrentDock"]=@(!read.visible);
        WPUnreadDockState *plain=[WPUnreadDockState new];[plain observeUnreadSession:WPD122Row(@"wxid_plain",1,now) genuineArrival:NO];[plain observeUnreadSession:nil genuineArrival:NO];
        checks[@"D12401MissingLatestDoesNotInventAnExplicitRead"]=@(plain.visible);
        [plain reconcileConversationUsername:@"wxid_plain" unreadState:WPQuickChatUnreadStateUnknown];
        checks[@"D12402UnknownExactNativeStatePreservesUnread"]=@(plain.visible);
        [plain reconcileConversationUsername:@"wxid_plain" unreadState:WPQuickChatUnreadStateRead];
        checks[@"D12403ExplicitReadOfPollOnlyAvatarClearsIt"]=@(!plain.visible);
        WPUnreadDockState *nativeRead=[WPUnreadDockState new];WPBarrageMessage *nativeReadMessage=WPD122Message(@"wxid_native_read",@"native-read",now);
        [nativeRead markBarrageMessageReceived:nativeReadMessage];[nativeRead dockMessage:nativeReadMessage image:nil];
        [nativeRead reconcileConversationUsername:@"wxid_native_read" unreadState:WPQuickChatUnreadStateRead];
        checks[@"D12404FreshNativeReceiveHasFiniteUnreadPropagationGrace"]=@(nativeRead.visible);
        [[nativeRead valueForKey:@"current"] setValue:@(CACurrentMediaTime()-3) forKey:@"receivedAt"];
        [nativeRead reconcileConversationUsername:@"wxid_native_read" unreadState:WPQuickChatUnreadStateRead];
        checks[@"D12405ConfirmedReadAfterPropagationClearsNativeAvatarAndReceipt"]=@(!nativeRead.visible&&![nativeRead shouldDockMessage:nativeReadMessage]);
        WPBarrageMessage *deniedMessage=WPD122Message(@"wxid_native_denied",@"native-denied",now);
        [nativeRead markBarrageMessageReceived:deniedMessage];[nativeRead dockMessage:deniedMessage image:nil];[nativeRead reconcileConversationUsername:deniedMessage.conversationUsername unreadState:WPQuickChatUnreadStateDenied];
        checks[@"D12406ExplicitPrivacyDenialDoesNotWaitForUnreadGrace"]=@(!nativeRead.visible&&![nativeRead shouldDockMessage:deniedMessage]);

        WPUnreadDockState *invalid=[WPUnreadDockState new];
        WPBarrageMessage *local=WPD122Message(@"preview",@"local",now);local.localPreview=YES;
        WPBarrageMessage *malformed=WPD122Message([@"x" stringByPaddingToLength:257 withString:@"x" startingAtIndex:0],@"malformed",now);
        WPBarrageMessage *missing=WPD122Message(@"wxid_missing",@"",now);
        checks[@"D12226_LocalPreviewAndMalformedIdentifiersCreateNoReceipt"]=@(![invalid markBarrageMessageReceived:local]&&![invalid markBarrageMessageReceived:malformed]&&![invalid markBarrageMessageReceived:missing]&&[invalid diagnostics][@"receipts"].unsignedIntegerValue==0);
        __weak WPBarrageMessage *weakMessage;
        @autoreleasepool {WPBarrageMessage *temporary=WPD122Message(@"wxid_weak",@"weak-message",now);weakMessage=temporary;[invalid markBarrageMessageReceived:temporary];}
        checks[@"D12227_ReceiptNeverRetainsMessageWrapperOrItsBody"]=@(weakMessage==nil);
        NSString *duplicate=[invalid markBarrageMessageReceived:message];
        checks[@"D12228_StableNativeIdentityReusesItsLightweightReceipt"]=@([[invalid markBarrageMessageReceived:message] isEqual:duplicate]);
        for(NSUInteger i=0;i<260;i++){
            NSString *name=[NSString stringWithFormat:@"wxid_bound_%lu",(unsigned long)i];
            [invalid observeUnreadSession:WPD122Row(name,1,now+i) genuineArrival:NO];
            [invalid markBarrageMessageReceived:WPD122Message(name,[NSString stringWithFormat:@"bounded-%lu",(unsigned long)i],now+i)];
        }
        NSDictionary *counts=invalid.diagnostics;
        checks[@"D12229_ReceiptRevisionAndConversationStorageAreBounded"]=@([counts[@"receipts"] unsignedIntegerValue]<=128&&[counts[@"revisions"] unsignedIntegerValue]<=128&&[counts[@"conversations"] unsignedIntegerValue]<=128);
        NSSet *allowed=[NSSet setWithArray:@[@"visible",@"playbackPending",@"receipts",@"revisions",@"conversations",@"limit"]];
        checks[@"D12230_DiagnosticsContainCountsOnly"]=@([[NSSet setWithArray:counts.allKeys] isEqual:allowed]&&[counts.allValues filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id value,__unused NSDictionary *bindings){return ![value isKindOfClass:NSNumber.class];}]].count==0);

        WPUnreadDockState *lateBefore=[WPUnreadDockState new];
        WPBarrageMessage *lateMessage=WPD122Message(@"wxid_late_before",@"late-before",now);
        [lateBefore markBarrageMessageReceived:lateMessage];[lateBefore dockMessage:lateMessage image:nil];NSString *openingRevision=lateBefore.revision;
        [lateBefore observeUnreadSession:WPD122Row(@"wxid_late_before",1,now) genuineArrival:YES];
        checks[@"D12231_FirstPollDuringChatPresentationKeepsNativeRevision"]=@([lateBefore.revision isEqual:openingRevision]);
        [lateBefore consumeRevision:openingRevision];[lateBefore observeUnreadSession:WPD122Row(@"wxid_late_before",1,now) genuineArrival:YES];
        checks[@"D12232_LatePollBeforeCompletionCannotKeepConsumedAvatarAlive"]=@(!lateBefore.visible);

        WPUnreadDockState *lateAfter=[WPUnreadDockState new];
        WPBarrageMessage *alreadyOpened=WPD122Message(@"wxid_late_after",@"late-after",now);
        [lateAfter markBarrageMessageReceived:alreadyOpened];[lateAfter dockMessage:alreadyOpened image:nil];[lateAfter clear];
        [lateAfter observeUnreadSession:WPD122Row(@"wxid_late_after",1,now) genuineArrival:YES];
        [lateAfter observeUnreadSession:WPD122Row(@"wxid_late_after",1,now) genuineArrival:NO];
        checks[@"D12233_FirstPollAfterSuccessfulOpenCannotResurrectItsNativeMessage"]=@(!lateAfter.visible);
        WPBarrageMessage *sameSecondNew=WPD122Message(@"wxid_late_after",@"late-after-new-id",MAX(floor(NSDate.date.timeIntervalSince1970),now));
        [lateAfter markBarrageMessageReceived:sameSecondNew];
        checks[@"D12234_NewNativeIdentifierStillWinsAfterBindingLatePoll"]=@([lateAfter shouldDockMessage:sameSecondNew]&&[lateAfter dockMessage:sameSecondNew image:nil]);

        WPUnreadDockState *interleaved=[WPUnreadDockState new];
        WPBarrageMessage *oldOpen=WPD122Message(@"wxid_interleaved_old",@"interleaved-old",now),*newDuringOpen=WPD122Message(@"wxid_interleaved_new",@"interleaved-new",now);
        [interleaved markBarrageMessageReceived:oldOpen];[interleaved dockMessage:oldOpen image:nil];NSString *oldOpening=interleaved.revision;
        [interleaved markBarrageMessageReceived:newDuringOpen];interleaved.playbackPending=YES;
        [interleaved observeUnreadSession:WPD122Row(@"wxid_interleaved_old",1,now) genuineArrival:YES];
        [interleaved consumeRevision:oldOpening];BOOL newerAllowed=[interleaved shouldDockMessage:newDuringOpen];
        [interleaved dockMessage:newDuringOpen image:nil];interleaved.playbackPending=NO;
        checks[@"D12235_LateOldPollCannotAcknowledgeANewNativeReceiptDuringOpen"]=@(newerAllowed&&[interleaved.conversationUsername isEqual:@"wxid_interleaved_new"]);
        [lateBefore observeUnreadSession:WPD122Row(@"wxid_late_before",2,now) genuineArrival:NO];
        checks[@"D12236_CountGrowthAfterBoundNativeEchoStillRestoresUnread"]=@(lateBefore.visible&&[lateBefore.conversationUsername isEqual:@"wxid_late_before"]);
    } @catch(__unused NSException *exception) {checks[@"D122FixtureCompletedWithoutException"]=@NO;}
    return checks;
}
