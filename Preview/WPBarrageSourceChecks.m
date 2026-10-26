#import "WPBarrageSourceChecks.h"
#import "WPMessageBarrageSource.h"
#import "WPMessageBarrage.h"
#import "WPBarragePreferences.h"
#import "WPCommon.h"
#import "WPQuickChat.h"
#import "WPSessionEligibility.h"
#import <objc/runtime.h>
#import <dlfcn.h>
#import <UIKit/UIKit.h>

@interface WPMessageBarrageSource (WPBarrageSourceChecks)
- (void)captureIncomingWrap:(id)wrap;
- (void)drainGeneration:(NSUInteger)generation;
- (BOOL)allowsConversation:(NSString *)username;
- (WPBarrageMessage *)messageFromWrap:(id)wrap activeSince:(NSTimeInterval)since;
- (void)settingsChanged:(NSNotification *)notification;
- (void)becameInactive:(NSNotification *)notification;
- (void)memoryWarning:(NSNotification *)notification;
- (id)nativeSessionForConversation:(NSString *)username;
- (BOOL)isCurrentConversation:(NSString *)username;
- (NSSet*)homeNamesForConversations;
@end
@interface WPBSFixtureSource : WPMessageBarrageSource
@property(nonatomic) BOOL permit;
@end
@implementation WPBSFixtureSource
- (BOOL)allowsConversation:(NSString *)username {return self.permit;}
@end
@interface WPBSFixtureEligibilitySource : WPMessageBarrageSource
@property(nonatomic,strong) id fixtureSession;
@property(nonatomic) BOOL fixtureCurrent;
@end
@implementation WPBSFixtureEligibilitySource
- (id)nativeSessionForConversation:(NSString *)username {return self.fixtureSession;}
- (BOOL)isCurrentConversation:(NSString *)username {return self.fixtureCurrent;}
- (NSSet*)homeNamesForConversations {return [NSSet setWithObject:@"wxid_eligibility_fixture_missing"];}
@end
@interface WPBSFixtureSession : NSObject
@property(nonatomic) BOOL m_bShowUnReadAsRedDot;
@property(nonatomic) BOOL isHidden;
@property(nonatomic) BOOL m_bIsHidden;
@property(nonatomic) BOOL hidden;
@property(nonatomic) BOOL isInChatBox;
@property(nonatomic) BOOL isInBrandServiceBox;
@property(nonatomic) BOOL isBrandServiceBoxSession;
@property(nonatomic) BOOL isBrandEcsMsgHolderSession;
@property(nonatomic) BOOL m_isFolding;
@property(nonatomic) BOOL m_bIsFold;
@property(nonatomic) BOOL m_bIsFolded;
@property(nonatomic) BOOL isFolded;
@end
@implementation WPBSFixtureSession
@end
@interface WPBSFixtureWrap : NSObject
@property(nonatomic) NSUInteger m_uiStatus;
@property(nonatomic) NSUInteger m_uiMessageType;
@property(nonatomic) NSUInteger m_uiCreateTime;
@property(nonatomic) NSUInteger m_uiMesLocalID;
@property(nonatomic) long long m_n64MesSvrID;
@property(nonatomic,copy) NSString *m_nsFromUsr;
@property(nonatomic,copy) NSString *m_nsRealChatUsr;
@property(nonatomic,copy) NSString *body;
@property(nonatomic) NSUInteger bodyReads;
@property(nonatomic) BOOL failOnRead;
- (NSString *)m_nsContent;
@end
@implementation WPBSFixtureWrap
- (NSString *)m_nsContent {self.bodyReads++;if(self.failOnRead)@throw [NSException exceptionWithName:@"WPBSFixtureOnly" reason:nil userInfo:nil];return self.body;}
@end
@interface WPBSFixtureBlockedWrap : WPBSFixtureWrap
@property(nonatomic,strong) dispatch_semaphore_t reachedBody;
@property(nonatomic,strong) dispatch_semaphore_t resumeBody;
@end
@implementation WPBSFixtureBlockedWrap
- (NSString *)m_nsContent {
    NSString *body=[super m_nsContent];dispatch_semaphore_signal(self.reachedBody);
    dispatch_semaphore_wait(self.resumeBody,dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC));return body;
}
@end
@interface WPBSFixtureWrongWrap : NSObject
- (NSString *)m_uiStatus;
@end
@implementation WPBSFixtureWrongWrap
- (NSString *)m_uiStatus {return @"3";}
@end
@interface WPBSIvarSession : NSObject {@public BOOL m_bShowUnReadAsRedDot;BOOL m_bIsFolded;}
@end
@implementation WPBSIvarSession
@end
@interface WPBSIvarWrap : NSObject {@public unsigned int m_uiStatus,m_uiMessageType,m_uiCreateTime,m_uiMesLocalID;long long m_n64MesSvrID;NSString *m_nsFromUsr,*m_nsContent;}
@end
@implementation WPBSIvarWrap
@end
static NSUInteger (*WPPreviewOriginalReceiveCount)(void);
static void (*WPPreviewSetNativeReceiveThrows)(BOOL);
static void (*WPPreviewSendIncomingWrap)(NSString*,id);
static void (*WPPreviewSendBaseIncomingWrap)(id);
static void (*WPPreviewInstallBarrageSession)(NSString*,id,BOOL,BOOL);
static BOOL (*WPPreviewOriginalReceiveNotifyFlag)(void);
static void (*WPPreviewSendIncomingWrapWithNotify)(id,BOOL);
@interface WPBSIndexMembershipFixture : NSObject
@property(nonatomic) NSArray<NSString*> *names;
@property(nonatomic) NSUInteger reads;
- (unsigned int)GetSessionCount;
- (NSString*)GetSessionUserNameAtIndex:(unsigned int)index;
@end
@implementation WPBSIndexMembershipFixture
- (unsigned int)GetSessionCount{return (unsigned int)self.names.count;}
- (NSString*)GetSessionUserNameAtIndex:(unsigned int)index{self.reads++;return index<self.names.count?self.names[index]:nil;}
@end
static WPBSFixtureWrap *WPBSFixture(NSUInteger token) {
    WPBSFixtureWrap *wrap=[WPBSFixtureWrap new];wrap.m_uiStatus=3;wrap.m_uiMessageType=1;wrap.m_uiCreateTime=(NSUInteger)NSDate.date.timeIntervalSince1970;
    wrap.m_nsFromUsr=@"wxid_source_fixture";wrap.body=@"今晚一起散步吧";wrap.m_n64MesSvrID=10000+token;wrap.m_uiMesLocalID=token+1;return wrap;
}
static NSUInteger WPBSGraphemes(NSString *value) {
    __block NSUInteger count=0;[value enumerateSubstringsInRange:NSMakeRange(0,value.length) options:NSStringEnumerationByComposedCharacterSequences|NSStringEnumerationSubstringNotRequired usingBlock:^(NSString *part,NSRange range,NSRange enclosing,BOOL *stop){count++;}];return count;
}
NSDictionary<NSString *,NSNumber *> *WPBarrageSourcePreviewChecks(void) {
    NSCAssert(NSThread.isMainThread,@"Barrage source checks run on main");
    NSMutableDictionary *checks=[NSMutableDictionary new];NSUserDefaults *defaults=WPPreferences();
    NSArray *keys=@[@"enabled",@"barrageEnabled",@"barrageShowsDetails",@"barrageQuietEnabled",@"barrageQuietStart",@"barrageQuietEnd",@"barrageContactsOnly",@"barrageContactUsernames",@"barragePauseUntil",@"barrageAllowPrivate",@"barrageAllowGroup"];
    NSMutableDictionary *old=[NSMutableDictionary new];NSDictionary *domain=[defaults persistentDomainForName:@"dev.zhour.wechatpet"];
    for(NSString *key in keys)old[key]=domain[key] ?: NSNull.null;
    [defaults removeObjectForKey:@"barragePauseUntil"];[defaults setBool:YES forKey:@"barrageAllowPrivate"];[defaults setBool:YES forKey:@"barrageAllowGroup"];[defaults setBool:YES forKey:@"enabled"];[defaults setBool:YES forKey:@"barrageEnabled"];[defaults setBool:YES forKey:@"barrageShowsDetails"];
    [defaults setBool:NO forKey:@"barrageQuietEnabled"];[defaults setBool:NO forKey:@"barrageContactsOnly"];
    WPBSFixtureSource *source=[WPBSFixtureSource new];source.permit=YES;[source setActive:YES];
    NSMutableArray<WPBarrageMessage *> *received=[NSMutableArray new];
    id observer=[NSNotificationCenter.defaultCenter addObserverForName:WPMessageBarrageDidReceiveNotification object:source queue:nil usingBlock:^(NSNotification *notification){[received addObject:notification.userInfo[@"message"]];}];
    void (^drain)(void)=^{[source drainGeneration:[[source valueForKey:@"generation"] unsignedIntegerValue]];};
    void (^reset)(void)=^{[source setActive:NO];[source setActive:YES];[received removeAllObjects];};
    @try {
        WPBSFixtureWrap *personal=WPBSFixture(1);[source captureIncomingWrap:personal];drain();
        checks[@"BS01_actualTextWithoutRemark"] = @(received.count==1 && [received.lastObject.text isEqual:personal.body]);
        checks[@"BS12502SourceAdmissionCarriesPositiveEligibility"] = @(received.lastObject.sourceEligibilityConfirmed);
        checks[@"BS02_personalAvatarAndChatRoute"] = @([received.lastObject.conversationUsername isEqual:personal.m_nsFromUsr] && [received.lastObject.senderUsername isEqual:personal.m_nsFromUsr]);
        [source captureIncomingWrap:personal];drain();checks[@"BS03_hookAndFallbackDedup"] = @(received.count==1);
        WPBSFixtureWrap *sameServer=WPBSFixture(2);sameServer.m_n64MesSvrID=personal.m_n64MesSvrID;[source captureIncomingWrap:sameServer];drain();
        checks[@"BS04_stableServerIdWinsOverLocalId"] = @(received.count==1);
        reset();WPBSFixtureWrap *group=WPBSFixture(3);group.m_nsFromUsr=@"source_group@chatroom";group.m_nsRealChatUsr=@"wxid_group_member";group.body=@"wxid_group_member:\n我们到了";
        [source captureIncomingWrap:group];drain();checks[@"BS05_groupBodyStripsSenderPrefix"] = @(received.count==1 && [received.lastObject.text isEqual:@"我们到了"]);
        checks[@"BS06_groupAvatarMemberButRoutesOriginalGroup"] = @([received.lastObject.senderUsername isEqual:@"wxid_group_member"] && [received.lastObject.conversationUsername isEqual:@"source_group@chatroom"]);
        reset();group=WPBSFixture(4);group.m_nsFromUsr=@"source_group@chatroom";group.body=@"wxid_parsed_member:\n无成员属性";[source captureIncomingWrap:group];drain();
        checks[@"BS07_groupBoundedPrefixFallback"] = @([received.lastObject.text isEqual:@"无成员属性"] && [received.lastObject.senderUsername isEqual:@"wxid_parsed_member"]);
        reset();for(NSNumber *status in @[@1,@2,@4,@5,@0]){WPBSFixtureWrap *sent=WPBSFixture(5+status.unsignedIntegerValue);sent.m_uiStatus=status.unsignedIntegerValue;[source captureIncomingWrap:sent];}
        drain();checks[@"BS08_sentAndSystemStatusesRejected"] = @(received.count==0);
        checks[@"BS09_wrongScalarABIRejected"] = @([source messageFromWrap:[WPBSFixtureWrongWrap new] activeSince:0]==nil);
        WPBSFixtureWrap *system=WPBSFixture(20);system.m_uiMessageType=10000;[source captureIncomingWrap:system];drain();checks[@"BS10_systemTypeRejected"] = @(received.count==0);
        WPBSFixtureWrap *stale=WPBSFixture(21);stale.m_uiCreateTime-=60;[source captureIncomingWrap:stale];drain();checks[@"BS11_historyAndBacklogRejected"] = @(received.count==0);
        WPBSFixtureWrap *future=WPBSFixture(22);future.m_uiCreateTime+=300;[source captureIncomingWrap:future];drain();checks[@"BS12_futureTimestampRejected"] = @(received.count==0);
        WPBSFixtureWrap *noId=WPBSFixture(23);noId.m_n64MesSvrID=0;noId.m_uiMesLocalID=0;[source captureIncomingWrap:noId];drain();checks[@"BS13_noStableIdentityCannotReplay"] = @(received.count==0);
        reset();WPBSFixtureWrap *longText=WPBSFixture(24);NSMutableString *emoji=[NSMutableString new];for(NSUInteger n=0;n<100;n++)[emoji appendString:@"👨‍👩‍👧‍👦"];
        longText.body=emoji;[source captureIncomingWrap:longText];drain();checks[@"BS14_eightyComposedCharactersWithoutSplit"] = @(WPBSGraphemes(received.lastObject.text)==81 && [received.lastObject.text hasSuffix:@"👨‍👩‍👧‍👦…"]);
        reset();WPBSFixtureWrap *exactlyEighty=WPBSFixture(240);exactlyEighty.body=[@"好" stringByPaddingToLength:80 withString:@"好" startingAtIndex:0];[source captureIncomingWrap:exactlyEighty];drain();
        checks[@"BS39_exactlyEightyHasNoFalseEllipsis"] = @(WPBSGraphemes(received.lastObject.text)==80 && ![received.lastObject.text hasSuffix:@"…"]);
        reset();WPBSFixtureWrap *eightyOne=WPBSFixture(241);eightyOne.body=[@"好" stringByPaddingToLength:81 withString:@"好" startingAtIndex:0];[source captureIncomingWrap:eightyOne];drain();
        checks[@"BS40_eightyFirstCharacterTriggersEllipsis"] = @(WPBSGraphemes(received.lastObject.text)==81 && [received.lastObject.text hasSuffix:@"好…"]);
        reset();WPBSFixtureWrap *line=WPBSFixture(25);line.body=@"第一行\n第二行\t第三行";[source captureIncomingWrap:line];drain();checks[@"BS15_singleLinePresentation"] = @([received.lastObject.text isEqual:@"第一行 第二行 第三行"]);
        reset();for(NSNumber *type in @[@3,@34,@43,@47,@48,@49,@62]){WPBSFixtureWrap *media=WPBSFixture(100+type.unsignedIntegerValue);media.m_uiMessageType=type.unsignedIntegerValue;media.failOnRead=YES;[source captureIncomingWrap:media];}
        drain();checks[@"BS16_mediaLabelsWithoutBodyOrMediaReads"] = @(received.count==7 && [received.firstObject.text isEqual:@"[图片]"] && [received.lastObject.text isEqual:@"[视频]"]);
        reset();[defaults setBool:NO forKey:@"barrageShowsDetails"];WPBSFixtureWrap *private=WPBSFixture(26);private.failOnRead=YES;[source captureIncomingWrap:private];drain();
        checks[@"BS17_avatarOnlyNeverReadsBody"] = @(received.count==1 && received.lastObject.text.length==0 && private.bodyReads==0);
        [defaults setBool:YES forKey:@"barrageShowsDetails"];reset();WPBSFixtureWrap *pending=WPBSFixture(27);[source captureIncomingWrap:pending];[defaults setBool:NO forKey:@"barrageShowsDetails"];
        [source settingsChanged:nil];NSArray *inbox=[source valueForKey:@"inbox"];
        checks[@"BS18_hidingDetailsPurgesPendingBody"] = @(inbox.count==0);drain();
        [source captureIncomingWrap:WPBSFixture(270)];drain();checks[@"BS19_privacyRecheckedAtDelivery"] = @(received.count==1 && received.lastObject.text.length==0);
        [defaults setBool:YES forKey:@"barrageShowsDetails"];reset();[source setActive:NO];WPBSFixtureWrap *off=WPBSFixture(28);off.failOnRead=YES;[source captureIncomingWrap:off];
        checks[@"BS20_inactiveSkipsEveryBodyRead"] = @(off.bodyReads==0 && [source.diagnostics[@"pending"] unsignedIntegerValue]==0);
        [source setActive:YES];[defaults setBool:NO forKey:@"barrageEnabled"];[source captureIncomingWrap:off];checks[@"BS21_disabledFeatureSkipsBodyRead"] = @(off.bodyReads==0);[defaults setBool:YES forKey:@"barrageEnabled"];
        reset();[defaults setBool:YES forKey:@"barrageQuietEnabled"];[defaults setInteger:0 forKey:@"barrageQuietStart"];[defaults setInteger:0 forKey:@"barrageQuietEnd"];
        WPBSFixtureWrap *quiet=WPBSFixture(29);[source captureIncomingWrap:quiet];drain();checks[@"BS22_quietTimeBeforeBodyRead"] = @(received.count==0 && quiet.bodyReads==0);[defaults setBool:NO forKey:@"barrageQuietEnabled"];
        [defaults setBool:YES forKey:@"barrageContactsOnly"];[defaults setObject:@"wxid_other" forKey:@"barrageContactUsernames"];WPBSFixtureWrap *filter=WPBSFixture(30);[source captureIncomingWrap:filter];drain();
        checks[@"BS23_contactFilterBeforeBodyRead"] = @(received.count==0 && filter.bodyReads==0);[defaults setBool:NO forKey:@"barrageContactsOnly"];
        reset();source.permit=NO;[source captureIncomingWrap:WPBSFixture(31)];drain();checks[@"BS24_mutedOrCurrentConversationSuppressed"] = @(received.count==0);source.permit=YES;
        reset();dispatch_apply(256,dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^(size_t index){@autoreleasepool{[source captureIncomingWrap:WPBSFixture(1000+index)];}});
        NSDictionary *burst=source.diagnostics;checks[@"BS25_workerBurstInboxBoundedTwelve"] = @([burst[@"pending"] unsignedIntegerValue]==12);
        checks[@"BS26_workerBurstDedupBoundedNinetySix"] = @([burst[@"dedup"] unsignedIntegerValue]==96);drain();
        checks[@"BS27_burstDeliversOnlyBoundedBatchOnMain"] = @(received.count==12 && NSThread.isMainThread);
        reset();[source captureIncomingWrap:WPBSFixture(32)];NSUInteger oldGeneration=[[source valueForKey:@"generation"] unsignedIntegerValue];[source setActive:NO];[source setActive:YES];[source drainGeneration:oldGeneration];
        checks[@"BS28_generationDropsOldForegroundHandoff"] = @(received.count==0 && [source.diagnostics[@"pending"] unsignedIntegerValue]==0);
        [source captureIncomingWrap:WPBSFixture(33)];NSUInteger transientGeneration=[[source valueForKey:@"generation"] unsignedIntegerValue];[source becameInactive:[NSNotification notificationWithName:UIApplicationWillResignActiveNotification object:nil]];drain();
        checks[@"BS29_resigningPausesQueuedBodiesWithoutNewGeneration"] = @(received.count==0 && [source.diagnostics[@"pending"] unsignedIntegerValue]==1 && [[source valueForKey:@"generation"] unsignedIntegerValue]==transientGeneration);
        [source setForegroundAvailable:YES];drain();checks[@"BS12401TransientResumeDeliversAlreadyAdmittedMessage"]=@(received.count==1);
        reset();[source becameInactive:[NSNotification notificationWithName:UIApplicationDidEnterBackgroundNotification object:nil]];
        NSMutableArray *backlog=[NSMutableArray new];for(NSUInteger i=0;i<150;i++){WPBSFixtureWrap *wrap=WPBSFixture(10000+i);wrap.failOnRead=YES;[backlog addObject:wrap];}
        dispatch_apply(backlog.count,dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^(size_t i){[source captureIncomingWrap:backlog[i]];});
        NSUInteger bodyReads=0;for(WPBSFixtureWrap *wrap in backlog)bodyReads+=wrap.bodyReads;
        checks[@"BS12402Background150CallbacksDoNotReadOrQueueBodies"]=@(bodyReads==0 && [source.diagnostics[@"pending"] unsignedIntegerValue]==0 && received.count==0);
        WPSESetForegroundAvailable(YES);[source setActive:YES];
        for(WPBSFixtureWrap *wrap in backlog){wrap.m_uiCreateTime-=60;[source captureIncomingWrap:wrap];}drain();
        checks[@"BS12403DelayedHistoryAfterForegroundDoesNotReplay"]=@(received.count==0 && [source.diagnostics[@"pending"] unsignedIntegerValue]==0);
        [source captureIncomingWrap:WPBSFixture(12000)];drain();checks[@"BS12404ForegroundFreshMessageStillDelivers"]=@(received.count==1);
        reset();[source setActive:NO];NSUInteger disabledGeneration=[[source valueForKey:@"generation"] unsignedIntegerValue];[source setActive:NO];[source setActive:NO];
        checks[@"BS12405RepeatedDisableIsIdempotent"]=@([[source valueForKey:@"generation"] unsignedIntegerValue]==disabledGeneration && [source.diagnostics[@"pending"] unsignedIntegerValue]==0);[source setActive:YES];
        [source setActive:YES];[source captureIncomingWrap:WPBSFixture(34)];[source memoryWarning:nil];drain();
        checks[@"BS30_pressurePurgesQueuedBodiesAndIds"] = @([source.diagnostics[@"pending"] unsignedIntegerValue]==0 && [source.diagnostics[@"dedup"] unsignedIntegerValue]==0);
        reset();WPBSFixtureWrap *bad=WPBSFixture(35);bad.failOnRead=YES;[source captureIncomingWrap:bad];drain();checks[@"BS31_ourGetterExceptionDoesNotCrash"] = @(received.count==0);
        NSString *diagnostics=[source.diagnostics description];checks[@"BS32_diagnosticsContainNoChatData"] = @(![diagnostics containsString:@"wxid_"] && ![diagnostics containsString:@"今晚"]);
        reset();WPBSFixtureBlockedWrap *racing=[WPBSFixtureBlockedWrap new];racing.m_uiStatus=3;racing.m_uiMessageType=1;racing.m_uiCreateTime=(NSUInteger)NSDate.date.timeIntervalSince1970;racing.m_n64MesSvrID=99999;racing.m_nsFromUsr=@"wxid_source_fixture";racing.body=@"旧正文不应恢复";
        racing.reachedBody=dispatch_semaphore_create(0);racing.resumeBody=dispatch_semaphore_create(0);
        dispatch_group_t task=dispatch_group_create();dispatch_group_async(task,dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{[source captureIncomingWrap:racing];});
        BOOL reached=dispatch_semaphore_wait(racing.reachedBody,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC))==0;
        [defaults setBool:NO forKey:@"barrageShowsDetails"];[source settingsChanged:nil];[defaults setBool:YES forKey:@"barrageShowsDetails"];[source settingsChanged:nil];
        dispatch_semaphore_signal(racing.resumeBody);BOOL finished=dispatch_group_wait(task,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC))==0;drain();
        checks[@"BS33_hideShowRaceCannotResurrectEarlierBody"] = @(reached && finished && received.count==0 && [source.diagnostics[@"pending"] unsignedIntegerValue]==0);
        WPBSFixtureEligibilitySource *eligibility=[WPBSFixtureEligibilitySource new];WPBSFixtureSession *session=[WPBSFixtureSession new];eligibility.fixtureSession=session;
        NSString *fixtureUser=@"wxid_eligibility_fixture_missing";
        checks[@"BS34_realEligibilityAllowsKnownUnmuted"] = @([eligibility allowsConversation:fixtureUser]);
        session.m_bShowUnReadAsRedDot=YES;checks[@"BS35_realEligibilityBlocksMuted"] = @(![eligibility allowsConversation:fixtureUser]);session.m_bShowUnReadAsRedDot=NO;
        BOOL allFlags=YES;for(NSString *key in @[@"isHidden",@"m_bIsHidden",@"hidden",@"isInChatBox",@"isInBrandServiceBox",@"isBrandServiceBoxSession",@"isBrandEcsMsgHolderSession",@"m_isFolding",@"m_bIsFold",@"m_bIsFolded",@"isFolded"]){[session setValue:@YES forKey:key];allFlags &= ![eligibility allowsConversation:fixtureUser];[session setValue:@NO forKey:key];}
        checks[@"BS36_realEligibilityBlocksAllExistingHomeFlags"] = @(allFlags);
        eligibility.fixtureCurrent=YES;checks[@"BS37_realEligibilitySuppressesCurrentlyVisibleChat"] = @(![eligibility allowsConversation:fixtureUser]);eligibility.fixtureCurrent=NO;
        eligibility.fixtureSession=[NSObject new];checks[@"BS38_unknownMuteMetadataFailsClosed"] = @(![eligibility allowsConversation:fixtureUser]);[eligibility setActive:NO];
        WPBSIvarSession *iv=[WPBSIvarSession new];eligibility.fixtureSession=iv;
        checks[@"BS41_typedIvarMuteMetadataAllowed"] = @([eligibility allowsConversation:fixtureUser]);iv->m_bIsFolded=YES;
        checks[@"BS42_typedIvarFoldMetadataBlocked"] = @(![eligibility allowsConversation:fixtureUser]);iv->m_bIsFolded=NO;iv->m_bShowUnReadAsRedDot=YES;
        checks[@"BS43_typedIvarMuteMetadataBlocked"] = @(![eligibility allowsConversation:fixtureUser]);
        WPBSIvarWrap *iw=[WPBSIvarWrap new];iw->m_uiStatus=3;iw->m_uiMessageType=1;iw->m_uiCreateTime=(unsigned int)NSDate.date.timeIntervalSince1970;iw->m_n64MesSvrID=12345678;iw->m_nsFromUsr=@"wxid_source_ivar";iw->m_nsContent=@"字段头像正文";
        WPBarrageMessage *im=[source messageFromWrap:iw activeSince:0];checks[@"BS44_typedIvarWrapperProducesText"] = @([im.text isEqual:@"字段头像正文"]);
        WPBSIndexMembershipFixture *indexMembership=[WPBSIndexMembershipFixture new];indexMembership.names=@[@"wxid_native_index_member"];
        NSSet *indexed=WPSEHomeNames(indexMembership);checks[@"BS57_homeMembershipUsesObservedNativeIndexFallback"] = @([indexed containsObject:@"wxid_native_index_member"] && indexMembership.reads==1);
        WPBSIndexMembershipFixture *largeMembership=[WPBSIndexMembershipFixture new];NSMutableArray*largeNames=[NSMutableArray new];for(NSUInteger i=0;i<1000;i++)[largeNames addObject:[NSString stringWithFormat:@"wxid_native_index_%lu",(unsigned long)i]];largeMembership.names=largeNames;
        NSSet *partial=WPSEHomeNames(largeMembership);checks[@"BS58_largeNativeMembershipYieldsBeforeCompletion"] = @(partial==nil && [WPSEHomeDiagnostics()[@"membershipLoading"]boolValue] && largeMembership.reads<=150);
        (void)WPSEHomeNames(indexMembership); // invalidate the queued large fixture scan
        // A dedicated preview links WPWeChatMocks.m. General visual previews have
        // no native message service, so discover these helpers at runtime.
        WPPreviewOriginalReceiveCount=dlsym(RTLD_DEFAULT,"WPPreviewOriginalReceiveCount");
        WPPreviewSetNativeReceiveThrows=dlsym(RTLD_DEFAULT,"WPPreviewSetNativeReceiveThrows");
        WPPreviewSendIncomingWrap=dlsym(RTLD_DEFAULT,"WPPreviewSendIncomingWrap");
        WPPreviewSendBaseIncomingWrap=dlsym(RTLD_DEFAULT,"WPPreviewSendBaseIncomingWrap");
        WPPreviewInstallBarrageSession=dlsym(RTLD_DEFAULT,"WPPreviewInstallBarrageSession");
        WPPreviewOriginalReceiveNotifyFlag=dlsym(RTLD_DEFAULT,"WPPreviewOriginalReceiveNotifyFlag");
        WPPreviewSendIncomingWrapWithNotify=dlsym(RTLD_DEFAULT,"WPPreviewSendIncomingWrapWithNotify");
        if(WPPreviewOriginalReceiveCount&&WPPreviewSetNativeReceiveThrows&&WPPreviewSendIncomingWrap&&WPPreviewSendBaseIncomingWrap&&WPPreviewInstallBarrageSession){
        // Actual production receive hook, inherited original and fallback path.
        WPMessageBarrageSource *real=WPMessageBarrageSource.sharedSource;[real setActive:NO];WPBSFixtureWrap *native=WPBSFixture(8001);WPPreviewInstallBarrageSession(native.m_nsFromUsr,native,NO,NO);WPSEInvalidateHomeNames();[real setActive:YES];
        NSMutableArray *nativeReceived=[NSMutableArray new];id nativeObserver=[NSNotificationCenter.defaultCenter addObserverForName:WPMessageBarrageDidReceiveNotification object:real queue:nil usingBlock:^(NSNotification*n){[nativeReceived addObject:n.userInfo[@"message"]];}];
        NSUInteger original=WPPreviewOriginalReceiveCount();WPPreviewSendIncomingWrap(@"AsyncOnAddMsg:MsgWrap:",native);[real drainGeneration:[[real valueForKey:@"generation"]unsignedIntegerValue]];
        checks[@"BS45_realInheritedReceiveHookDelivers"] = @(nativeReceived.count==1 && WPPreviewOriginalReceiveCount()==original+1);
        checks[@"BS12501WorkingNativeHookKeepsFreshArrivalSafetyPath"] = @(real.requiresSessionPolling);
        WPPreviewSendIncomingWrap(@"OnAddMsg:MsgWrap:",native);[real drainGeneration:[[real valueForKey:@"generation"]unsignedIntegerValue]];
        checks[@"BS47_nestedNativeRouteDoesNotDuplicate"] = @(nativeReceived.count==1 && WPPreviewOriginalReceiveCount()==original+2);
        WPPreviewSendBaseIncomingWrap(native);checks[@"BS48_inheritedBaseMethodUntouched"] = @(WPPreviewOriginalReceiveCount()==original+3);
        BOOL propagated=NO;WPPreviewSetNativeReceiveThrows(YES);@try{WPPreviewSendIncomingWrap(@"AsyncOnAddMsg:MsgWrap:",native);}@catch(NSException*e){propagated=[e.name isEqual:@"NativeReceiveFixture"];}WPPreviewSetNativeReceiveThrows(NO);
        checks[@"BS49_nativeOriginalExceptionPropagatesOnce"] = @(propagated && WPPreviewOriginalReceiveCount()==original+4);
        [real setValue:@(NSDate.date.timeIntervalSince1970-121) forKey:@"lastNativeReceiveAt"];
        checks[@"BS50_staleReceiveHealthReenablesFallback"] = @(real.requiresSessionPolling);
        WPBSFixtureWrap *fallback=WPBSFixture(8002);WPPreviewInstallBarrageSession(fallback.m_nsFromUsr,fallback,NO,NO);WPSEInvalidateHomeNames();
        [NSNotificationCenter.defaultCenter postNotificationName:WPQuickChatDidChangeNotification object:nil userInfo:@{@"arrivals":@[fallback.m_nsFromUsr]}];[real drainGeneration:[[real valueForKey:@"generation"]unsignedIntegerValue]];
        checks[@"BS51_actualSessionArrivalFallbackDelivers"] = @(nativeReceived.count==2 && [((WPBarrageMessage*)nativeReceived.lastObject).text isEqual:fallback.body]);
        WPPreviewInstallBarrageSession(fallback.m_nsFromUsr,fallback,YES,NO);WPSEInvalidateHomeNames();checks[@"BS52_sharedPolicyBlocksHiddenAtPresentation"] = @(!WPMessageBarrageConversationAllowed(fallback.m_nsFromUsr));
        NSString *health=real.diagnostics.description;checks[@"BS53_healthCountsDoNotExposeConversationOrText"] = @(![health containsString:@"wxid_"] && ![health containsString:@"今晚"] && [real.diagnostics[@"nativeCallbacks"] unsignedIntegerValue]>=2);
        if(WPPreviewOriginalReceiveNotifyFlag&&WPPreviewSendIncomingWrapWithNotify){
            WPBSFixtureWrap *notifyWrap=WPBSFixture(8003);WPPreviewInstallBarrageSession(notifyWrap.m_nsFromUsr,notifyWrap,NO,NO);WPSEInvalidateHomeNames();NSUInteger beforeNotify=WPPreviewOriginalReceiveCount(),beforeMessages=nativeReceived.count;
            WPPreviewSendIncomingWrapWithNotify(notifyWrap,NO);[real drainGeneration:[[real valueForKey:@"generation"]unsignedIntegerValue]];
            checks[@"BS54_observedThreeArgumentEntryAloneDelivers"] = @(nativeReceived.count==beforeMessages+1 && WPPreviewOriginalReceiveCount()==beforeNotify+1 && !WPPreviewOriginalReceiveNotifyFlag());
            WPBSFixtureWrap *notifyTrue=WPBSFixture(8004);WPPreviewInstallBarrageSession(notifyTrue.m_nsFromUsr,notifyTrue,NO,NO);WPSEInvalidateHomeNames();WPPreviewSendIncomingWrapWithNotify(notifyTrue,YES);[real drainGeneration:[[real valueForKey:@"generation"]unsignedIntegerValue]];
            checks[@"BS55_nativeNotifyBooleanForwardedBothValues"] = @(nativeReceived.count==beforeMessages+2 && WPPreviewOriginalReceiveCount()==beforeNotify+2 && WPPreviewOriginalReceiveNotifyFlag());
            WPPreviewSendIncomingWrapWithNotify(notifyTrue,NO);[real drainGeneration:[[real valueForKey:@"generation"]unsignedIntegerValue]];
            checks[@"BS56_threeArgumentDuplicateStillCallsOriginalOnce"] = @(nativeReceived.count==beforeMessages+2 && WPPreviewOriginalReceiveCount()==beforeNotify+3 && !WPPreviewOriginalReceiveNotifyFlag());
        }
        [real setActive:NO];[NSNotificationCenter.defaultCenter removeObserver:nativeObserver];
        }
    } @catch(__unused NSException *exception) {checks[@"BS_NoException"]=@NO;}
    [source setActive:NO];[NSNotificationCenter.defaultCenter removeObserver:observer];
    for(NSString *key in keys){id value=old[key];if(value==NSNull.null)[defaults removeObjectForKey:key];else [defaults setObject:value forKey:key];}
    return checks;
}
