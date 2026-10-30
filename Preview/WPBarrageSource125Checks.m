#import "WPBarrageSource125Checks.h"
#import "WPMessageBarrageSource.h"
#import "WPMessageBarrage.h"
#import "WPCommon.h"
#import <UIKit/UIKit.h>

@interface WPMessageBarrageSource (WPBS125Tests)
- (id)nativeSessionManager;
- (id)nativeSessionForConversation:(NSString *)username;
- (BOOL)isCurrentConversation:(NSString *)username;
- (NSSet *)homeNamesForConversations;
- (WPBarrageConversationEligibility)eligibilityForConversation:(NSString *)username;
- (void)captureIncomingWrap:(id)wrap;
- (void)quickChatChanged:(NSNotification *)note;
- (void)drainGeneration:(NSUInteger)generation;
@end
@interface WPBS125Wrap : NSObject
@property(nonatomic) NSUInteger m_uiStatus,m_uiMessageType,m_uiCreateTime,m_uiMesLocalID;
@property(nonatomic) unsigned long long m_n64MesSvrID;
@property(nonatomic,copy) NSString *m_nsFromUsr,*m_nsContent;
@end
@implementation WPBS125Wrap @end
@interface WPBS125Session : NSObject
@property(nonatomic,copy) NSString *m_nsUserName;
@property(nonatomic,strong) id m_msgWrap;
@property(nonatomic) BOOL muted,metadataPending;
@end
@implementation WPBS125Session
- (BOOL)m_bShowUnReadAsRedDot {if(self.metadataPending)@throw [NSException exceptionWithName:@"NativeMetadataRebuilding" reason:nil userInfo:nil];return self.muted;}
@end
@interface WPBS125IndexManager : NSObject
@property(nonatomic,strong) NSMutableArray *rows;
@property(nonatomic) NSUInteger reads;
@property(nonatomic) BOOL offMain;
@end
@implementation WPBS125IndexManager
- (unsigned int)GetSessionCount{return (unsigned int)self.rows.count;}
- (id)GetSessionAtIndex:(unsigned int)index {self.reads++;self.offMain|=!NSThread.isMainThread;return index<self.rows.count?self.rows[index]:nil;}
@end
@interface WPBS125Source : WPMessageBarrageSource
@property(nonatomic,strong) WPBS125IndexManager *manager;
@property(nonatomic,strong) NSSet *homeNames;
@property(nonatomic,copy) dispatch_block_t beforeRetryProbe;
@end
@implementation WPBS125Source
- (id)nativeSessionManager{return self.manager;}
- (BOOL)isCurrentConversation:(NSString *)username{return NO;}
- (NSSet *)homeNamesForConversations{return self.homeNames;}
- (WPBarrageConversationEligibility)eligibilityForConversation:(NSString *)username{
    if(self.beforeRetryProbe){dispatch_block_t probe=self.beforeRetryProbe;self.beforeRetryProbe=nil;probe();[self setValue:@YES forKey:@"eligibilityTransient"];return WPBarrageConversationEligibilityUnknown;}
    return [super eligibilityForConversation:username];
}
@end
static WPBS125Wrap *WPBS125Message(NSUInteger token,NSString *name){
    WPBS125Wrap *wrap=[WPBS125Wrap new];wrap.m_uiStatus=3;wrap.m_uiMessageType=1;wrap.m_uiCreateTime=(NSUInteger)NSDate.date.timeIntervalSince1970;wrap.m_uiMesLocalID=token;wrap.m_n64MesSvrID=900000+token;wrap.m_nsFromUsr=name;wrap.m_nsContent=@"fresh fixture body";return wrap;
}
@interface WPBS125Run : NSObject
@property(nonatomic,strong) WPBS125Source *source;
@property(nonatomic,strong) NSMutableDictionary *checks,*saved;
@property(nonatomic,strong) NSMutableArray<WPBarrageMessage *> *received;
@property(nonatomic,strong) id observer;
@property(nonatomic,copy) void (^completion)(NSDictionary *);
@property(nonatomic) BOOL finished;
@end
@implementation WPBS125Run
- (void)after:(NSTimeInterval)delay do:(dispatch_block_t)block{dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay*NSEC_PER_SEC)),dispatch_get_main_queue(),^{if(self.finished)return;@try{block();}@catch(NSException *exception){self.checks[@"BS125NoUnexpectedException"]=@NO;[self finish];}});}
- (void)wait:(BOOL (^)(void))predicate until:(NSTimeInterval)deadline done:(void (^)(BOOL))completion{if(predicate()){completion(YES);return;}if(CACurrentMediaTime()>deadline){completion(NO);return;}[self after:.04 do:^{[self wait:predicate until:deadline done:completion];}];}
- (void)drain{[self.source drainGeneration:[[self.source valueForKey:@"generation"] unsignedIntegerValue]];}
- (void)arrival:(NSString *)name{[self.source quickChatChanged:[NSNotification notificationWithName:@"fixture" object:nil userInfo:@{@"arrivals":@[name]}]];}
- (void)start{
    self.checks=[NSMutableDictionary new];self.saved=[NSMutableDictionary new];self.received=[NSMutableArray new];
    NSDictionary *preferences=@{@"enabled":@YES,@"barrageEnabled":@YES,@"barrageShowsDetails":@YES,@"barrageQuietEnabled":@NO,@"barrageContactsOnly":@NO,@"barrageAllowPrivate":@YES,@"barrageAllowGroup":@YES,@"barragePauseUntil":@0};
    for(NSString *key in preferences){self.saved[key]=[WPPreferences() objectForKey:key]?:NSNull.null;[WPPreferences() setObject:preferences[key] forKey:key];}
    WPBS125IndexManager *manager=[WPBS125IndexManager new];manager.rows=[NSMutableArray new];NSMutableSet *names=[NSMutableSet new];
    for(NSUInteger i=0;i<430;i++){WPBS125Session *session=[WPBS125Session new];session.m_nsUserName=[NSString stringWithFormat:@"wxid_bs125_%lu",(unsigned long)i];[manager.rows addObject:session];[names addObject:session.m_nsUserName];}
    self.source=[WPBS125Source new];self.source.manager=manager;self.source.homeNames=names;[self.source setActive:YES];
    __weak typeof(self) weakSelf=self;
    self.observer=[NSNotificationCenter.defaultCenter addObserverForName:WPMessageBarrageDidReceiveNotification object:self.source queue:nil usingBlock:^(NSNotification *note){[weakSelf.received addObject:note.userInfo[@"message"]];}];
    WPBS125Session *target=manager.rows[350];id immediate=[self.source nativeSessionForConversation:target.m_nsUserName];
    self.checks[@"BS12503IndexOnlyNativeLookupYieldsBeforeDistantContact"]=@(immediate==nil && manager.reads<=150);
    [self wait:^BOOL{return [self.source nativeSessionForConversation:target.m_nsUserName]==target;} until:CACurrentMediaTime()+2 done:^(BOOL found){
        self.checks[@"BS12504IndexOnlyNativeLookupFindsContactAfterYield"]=@(found && !manager.offMain && [self.source.diagnostics[@"sessionLookupMaximumBatch"] unsignedIntegerValue]<=150);
        WPBS125Session *replacement=[WPBS125Session new];replacement.m_nsUserName=target.m_nsUserName;replacement.muted=YES;manager.rows[350]=replacement;
        self.checks[@"BS12505CachedRankReadsCurrentNativeMuteState"]=@([self.source eligibilityForConversation:replacement.m_nsUserName]==WPBarrageConversationEligibilityDenied);
        replacement.muted=NO;WPBS125Wrap *first=WPBS125Message(1,replacement.m_nsUserName);replacement.m_msgWrap=first;[self.source captureIncomingWrap:first];[self drain];
        self.checks[@"BS12506NativeIndexAdmissionPreservesPositiveEligibility"]=@(self.received.count==1 && self.received.lastObject.sourceEligibilityConfirmed);
        [self.source setValue:@(NSDate.date.timeIntervalSince1970) forKey:@"lastNativeReceiveAt"];
        WPBS125Session *fallback=manager.rows[351];fallback.m_msgWrap=WPBS125Message(2,fallback.m_nsUserName);[self arrival:fallback.m_nsUserName];
        [self wait:^BOOL{return self.received.count==2;} until:CACurrentMediaTime()+2 done:^(BOOL delivered){
            self.checks[@"BS12507HealthyHookStillAllowsUnobservedRouteFallback"]=@(delivered && [self.received.lastObject.conversationUsername isEqual:fallback.m_nsUserName]);
            [self.source captureIncomingWrap:fallback.m_msgWrap];[self drain];self.checks[@"BS12508HookAfterSafetyFallbackDoesNotDuplicate"]=@(self.received.count==2);
            [self delayedMetadata];
        }];
    }];
}
- (void)delayedMetadata{
    WPBS125Session *session=self.source.manager.rows[352];session.m_msgWrap=nil;[self arrival:session.m_nsUserName];
    [self after:1.4 do:^{
        self.checks[@"BS12509MissingLatestWrapDoesNotInventOrReplayBody"]=@(self.received.count==2);
        session.m_msgWrap=WPBS125Message(3,session.m_nsUserName);
        [self wait:^BOOL{return self.received.count==3;} until:CACurrentMediaTime()+2 done:^(BOOL delivered){
            self.checks[@"BS12510ArrivalBeforeNativeWrapUpdateRetriesAndDeliversOnce"]=@(delivered && [self.received.lastObject.conversationUsername isEqual:session.m_nsUserName]);
            WPBS125Session *late=self.source.manager.rows[353];late.metadataPending=YES;WPBS125Wrap *wrap=WPBS125Message(4,late.m_nsUserName);late.m_msgWrap=wrap;[self.source captureIncomingWrap:wrap];[self drain];
            [self after:1.4 do:^{late.metadataPending=NO;[self wait:^BOOL{return self.received.count==4;} until:CACurrentMediaTime()+2 done:^(BOOL settled){
                self.checks[@"BS12511NativeMetadataRebuildLongerThanOneSecondStillDelivers"]=@(settled && self.received.lastObject.sourceEligibilityConfirmed);
                [self retryCapacity];
                [self.source setActive:NO];self.checks[@"BS12512DisableCancelsPendingArrivalMetadataWithoutBodies"]=@([self.source.diagnostics[@"pendingArrivals"] unsignedIntegerValue]==0 && [self.source.diagnostics[@"pending"] unsignedIntegerValue]==0);
                [self finish];
            }];}];
        }];
    }];
}
- (void)retryCapacity{
    WPBS125Session *session=self.source.manager.rows[354];
    WPBS125Wrap *old=WPBS125Message(5,session.m_nsUserName);
    [self.source captureIncomingWrap:old];
    NSMutableArray<WPBarrageMessage *> *inbox=[self.source valueForKey:@"inbox"];
    self.source.beforeRetryProbe=^{
        for(NSUInteger index=0;index<12;index++){
            WPBarrageMessage *fresh=[WPBarrageMessage new];
            fresh.identifier=[NSString stringWithFormat:@"fresh-126-%lu",(unsigned long)index];
            [inbox addObject:fresh];
        }
    };
    [self drain];
    BOOL keptFresh=inbox.count==12;
    for(NSUInteger index=0;index<12 && keptFresh;index++)keptFresh&=[inbox[index].identifier isEqual:[NSString stringWithFormat:@"fresh-126-%lu",(unsigned long)index]];
    NSDictionary *retries=[self.source valueForKey:@"eligibilityRetries"];
    NSString *oldIdentifier=[NSString stringWithFormat:@"%@:s%llu",session.m_nsUserName,old.m_n64MesSvrID];
    self.checks[@"BS12601MetadataRetryDoesNotEvictFreshInbox"]=@(keptFresh && retries[oldIdentifier]==nil);
}
- (void)finish{if(self.finished)return;self.finished=YES;[self.source setActive:NO];if(self.observer)[NSNotificationCenter.defaultCenter removeObserver:self.observer];for(NSString *key in self.saved){id value=self.saved[key];if(value==NSNull.null)[WPPreferences() removeObjectForKey:key];else [WPPreferences() setObject:value forKey:key];}self.completion(self.checks);}
@end
void WPBarrageSource125RunPreviewChecks(void (^completion)(NSDictionary<NSString *,NSNumber *> *checks)){WPBS125Run *run=[WPBS125Run new];run.completion=completion;[run start];}
