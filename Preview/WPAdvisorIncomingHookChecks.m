#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "WPAdvisorContinuousCoordinator.h"
#import "WPAdvisorTaskCenter.h"
#import "WPMessageBarrageSource.h"
#import "WPCommon.h"
#import <dlfcn.h>

@interface WPAdvisorHookFixtureWrap : NSObject
@property(nonatomic) NSUInteger m_uiStatus,m_uiMessageType,m_uiCreateTime,m_uiMesLocalID;
@property(nonatomic) long long m_n64MesSvrID;
@property(nonatomic,copy) NSString *m_nsFromUsr,*body;
@property(nonatomic) NSUInteger bodyReads;
- (NSString *)m_nsContent;
@end
@implementation WPAdvisorHookFixtureWrap
- (NSString *)m_nsContent {self.bodyReads++;return self.body;}
@end
static WPAdvisorHookFixtureWrap *WPAHFixture(NSString *username,NSUInteger number){
    WPAdvisorHookFixtureWrap *wrap=[WPAdvisorHookFixtureWrap new];wrap.m_uiStatus=3;wrap.m_uiMessageType=1;
    wrap.m_uiCreateTime=(NSUInteger)NSDate.date.timeIntervalSince1970;wrap.m_uiMesLocalID=number;
    wrap.m_n64MesSvrID=(long long)(950000+number);wrap.m_nsFromUsr=username;wrap.body=@"模拟内容";return wrap;
}
static void WPAHAfter(dispatch_block_t block){dispatch_after(dispatch_time(DISPATCH_TIME_NOW,120*NSEC_PER_MSEC),dispatch_get_main_queue(),block);}
// Async phases return control to the main GCD queue between native callbacks.
// A nested run loop cannot reliably execute blocks queued to that serial queue.
void WPAdvisorIncomingHookChecks(void (^completion)(NSDictionary<NSString *,NSNumber *> *)){
    NSCAssert(NSThread.isMainThread,@"native hook checks require main thread");
    void (*sendWrap)(NSString *,id)=dlsym(RTLD_DEFAULT,"WPPreviewSendIncomingWrap");
    NSString *account=WPAdvisorCurrentAccountFingerprint();
    if(!sendWrap || !account.length){completion(@{@"advisorHookFixtureAvailable":@NO});return;}
    NSUserDefaults *prefs=WPPreferences();NSString *selectedKey=[NSString stringWithFormat:@"advisor.continuous.%@.selected",account],*enabledKey=[NSString stringWithFormat:@"advisor.continuous.%@.usernames",account];
    id savedSelected=[prefs objectForKey:selectedKey],savedEnabled=[prefs objectForKey:enabledKey],savedBarrage=[prefs objectForKey:@"barrageEnabled"];
    WPAdvisorContinuousCoordinator *coordinator=WPAdvisorContinuousCoordinator.sharedCoordinator;[coordinator refreshAccountIfNeeded];
    NSArray *oldEnabled=coordinator.enabledUsernames;BOOL oldForeground=coordinator.foregroundAvailable;
    BOOL (^oldReady)(NSString *)=coordinator.onReady;BOOL (^oldBusy)(NSString *)=coordinator.isBusy;
    void (^oldIncoming)(NSString *)=coordinator.onIncoming;void (^oldMessage)(NSString *,NSString *,NSTimeInterval,NSString *)=coordinator.onMessage;
    WPMessageBarrageSource *source=WPMessageBarrageSource.sharedSource;BOOL oldSourceActive=[[source valueForKey:@"wantsActive"] boolValue];
    [prefs setBool:NO forKey:@"barrageEnabled"];[source setActive:NO];coordinator.foregroundAvailable=YES;
    coordinator.onReady=nil;coordinator.isBusy=nil;coordinator.onIncoming=nil;
    NSString *unique=NSUUID.UUID.UUIDString;
    NSString *user1=[@"wxid_advisor_hook_a_" stringByAppendingString:unique],*user2=[@"wxid_advisor_hook_b_" stringByAppendingString:unique];
    __block NSUInteger events=0;__block NSString *actualText=nil,*actualUser=nil;
    coordinator.onMessage=^(NSString *username,__unused NSString *identifier,__unused NSTimeInterval timestamp,NSString *text){if([username isEqual:user1]){events++;actualText=[text copy];actualUser=[username copy];}};
    if(oldEnabled.count>=8 && ![oldEnabled containsObject:user1]){
        [coordinator setLockedUsername:oldEnabled.firstObject];[coordinator setEnabled:NO];
    }
    [coordinator setLockedUsername:user1];[coordinator setEnabled:YES];BOOL enabled=[coordinator isEnabledForUsername:user1];
    WPAdvisorHookFixtureWrap *wrong=WPAHFixture(user2,1),*right=WPAHFixture(user1,2);
    sendWrap(@"AsyncOnAddMsg:MsgWrap:",wrong);
    sendWrap(@"AsyncOnAddMsg:MsgWrap:",right);sendWrap(@"OnAddMsg:MsgWrap:",right);
    NSMutableDictionary *checks=[@{@"advisorHookFixtureAvailable":@YES} mutableCopy];
    WPAHAfter(^{
        checks[@"advisorHookReceivesWithoutBarrageAndDeduplicates"]=@(enabled && events==1 && [actualUser isEqual:user1] && [actualText isEqual:@"模拟内容"]);
        checks[@"advisorHookOtherContactBodyUnread"]=@(wrong.bodyReads==0 && events==1);
        WPAdvisorHookFixtureWrap *revoked=WPAHFixture(user1,3);sendWrap(@"AsyncOnAddMsg:MsgWrap:",revoked);[coordinator setEnabled:NO];
        WPAHAfter(^{
            checks[@"advisorHookDisableDropsQueuedBody"]=@(revoked.bodyReads==0 && events==1);
            [coordinator setEnabled:YES];
            WPAdvisorHookFixtureWrap *old=WPAHFixture(user1,4);old.m_uiCreateTime=(NSUInteger)(NSDate.date.timeIntervalSince1970-60);
            WPAdvisorHookFixtureWrap *outgoing=WPAHFixture(user1,5);outgoing.m_uiStatus=2;
            sendWrap(@"AsyncOnAddMsg:MsgWrap:",old);sendWrap(@"AsyncOnAddMsg:MsgWrap:",outgoing);
            WPAHAfter(^{
                checks[@"advisorHookRejectsOldMessages"]=@(old.bodyReads==0 && events==1);
                checks[@"advisorHookRejectsOutgoing"]=@(outgoing.bodyReads==0 && events==1);
                id manager=WPWeChatService(@"CContactMgr");NSDictionary *contacts=[manager valueForKey:@"fixtureContacts"];id me=contacts[@"wxid_contract_self"];NSString *myUsername=[me valueForKey:@"m_nsUsrName"];
                WPAdvisorHookFixtureWrap *crossAccount=WPAHFixture(user1,6);sendWrap(@"AsyncOnAddMsg:MsgWrap:",crossAccount);
                [me setValue:@"wxid_other_hook_account" forKey:@"m_nsUsrName"];
                WPAHAfter(^{
                    checks[@"advisorHookDropsQueuedCrossAccountMessage"]=@(me && crossAccount.bodyReads==0 && events==1);
                    [me setValue:myUsername forKey:@"m_nsUsrName"];[coordinator refreshAccountIfNeeded];
                    if(savedSelected)[prefs setObject:savedSelected forKey:selectedKey];else[prefs removeObjectForKey:selectedKey];
                    if(savedEnabled)[prefs setObject:savedEnabled forKey:enabledKey];else[prefs removeObjectForKey:enabledKey];
                    if(savedBarrage)[prefs setObject:savedBarrage forKey:@"barrageEnabled"];else[prefs removeObjectForKey:@"barrageEnabled"];
                    [coordinator setValue:nil forKey:@"accountFingerprint"];[coordinator refreshAccountIfNeeded];
                    coordinator.onReady=oldReady;coordinator.isBusy=oldBusy;coordinator.onIncoming=oldIncoming;coordinator.onMessage=oldMessage;
                    coordinator.foregroundAvailable=oldForeground;[source setActive:oldSourceActive];
                    completion(checks);
                });
            });
        });
    });
}
