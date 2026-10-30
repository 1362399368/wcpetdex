#import "WPAdvisorContinuousChecks.h"
#import "WPAdvisorContinuousCoordinator.h"
#import "WPCommon.h"
#import "WPAdvisorTaskCenter.h"

static void WPCAdvance(void){[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.05]];}
static void WPCMakeDue(WPAdvisorContinuousCoordinator *c,NSString *username,NSTimeInterval first,NSTimeInterval last){
    id batch=[c valueForKey:@"batches"][username];[batch setValue:@(first) forKey:@"firstArrival"];[batch setValue:@(last) forKey:@"lastArrival"];
}
NSDictionary<NSString *,NSNumber *> *WPAdvisorContinuousChecks(void){
    NSCAssert(NSThread.isMainThread,@"continuous checks run on main");
    NSUserDefaults *prefs=WPPreferences();NSString *account=WPAdvisorCurrentAccountFingerprint();
    NSArray *keys=@[[NSString stringWithFormat:@"advisor.continuous.%@.selected",account?:@""],[NSString stringWithFormat:@"advisor.continuous.%@.usernames",account?:@""],[NSString stringWithFormat:@"advisor.continuous.%@.requireFresh",account?:@""]];
    NSMutableArray *saved=[NSMutableArray new];for(NSString *key in keys)[saved addObject:[prefs objectForKey:key]?:NSNull.null];
    [prefs removeObjectForKey:keys[2]];[prefs removeObjectForKey:keys[1]];[prefs removeObjectForKey:keys[0]];
    WPAdvisorContinuousCoordinator *c=[WPAdvisorContinuousCoordinator new];[c setLockedUsername:@"fixture-person"];[c setEnabled:YES];c.foregroundAvailable=YES;
    BOOL freshDefault=![c requiresFreshAnalysisForUsername:@"fixture-person"];
    [c setRequiresFreshAnalysis:YES forUsername:@"fixture-person"];
    BOOL freshPerContact=[c requiresFreshAnalysisForUsername:@"fixture-person"] && ![c requiresFreshAnalysisForUsername:@"fixture-other"];
    __block NSUInteger incoming=0,submitted=0,messages=0;__block BOOL busy=NO,ready=YES;
    c.onIncoming=^(__unused NSString *username){incoming++;};c.onMessage=^(__unused NSString *username,__unused NSString *identifier,__unused NSTimeInterval timestamp,NSString *text){if([text isEqual:@"hello"])messages++;};
    c.isBusy=^BOOL(__unused NSString *username){return busy;};c.onReady=^BOOL(__unused NSString *username){if(ready)submitted++;return ready;};
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;
    [c noteIncomingUsername:@"another-person" identifier:@"a" createdAt:now text:@"hello"];
    [c noteIncomingUsername:@"fixture-person" identifier:@"old" createdAt:now-30 text:@"hello"];
    [c noteIncomingUsername:@"fixture-person" identifier:@"one" createdAt:now text:@"hello"];
    [c noteIncomingUsername:@"fixture-person" identifier:@"one" createdAt:now text:@"hello"];
    BOOL dedup=incoming==1 && messages==1;
    WPCMakeDue(c,@"fixture-person",now-91,now-2);[c retryPending];WPCAdvance();BOOL maximum=submitted==1;
    [c noteIncomingUsername:@"fixture-person" identifier:@"two" createdAt:now text:@"hello"];
    WPCMakeDue(c,@"fixture-person",now-35,now-31);busy=YES;[c retryPending];WPCAdvance();BOOL held=submitted==1;
    busy=NO;[c taskDidFinishForUsername:@"fixture-person"];WPCAdvance();BOOL coalesced=submitted==2;
    [c noteIncomingUsername:@"fixture-person" identifier:@"three" createdAt:now text:@"hello"];
    WPCMakeDue(c,@"fixture-person",now-35,now-31);ready=NO;[c retryPending];WPCAdvance();
    id batch=[c valueForKey:@"batches"][@"fixture-person"];BOOL deferred=submitted==2 && [[batch valueForKey:@"firstArrival"] doubleValue]>0;
    ready=YES;[c retryPending];WPCAdvance();BOOL retried=submitted==3;
    [c setLockedUsername:@"fixture-other"];[c setEnabled:YES];BOOL independent=[c isEnabledForUsername:@"fixture-person"] && [c isEnabledForUsername:@"fixture-other"];
    freshPerContact &= ![c requiresFreshAnalysisForUsername:@"fixture-other"];
    [c setRequiresFreshAnalysis:YES forUsername:@"fixture-other"];freshPerContact &= [c requiresFreshAnalysisForUsername:@"fixture-other"];
    NSTimeInterval otherNow=NSDate.date.timeIntervalSince1970;
    [c noteIncomingUsername:@"fixture-other" identifier:@"other" createdAt:otherNow text:@"hello"];
    WPCMakeDue(c,@"fixture-other",otherNow-35,otherNow-31);[c retryPending];WPCAdvance();independent &= submitted==4;
    [c setEnabled:NO];independent &= ![c isEnabledForUsername:@"fixture-other"] && [c isEnabledForUsername:@"fixture-person"];
    BOOL freshDisabled=![c requiresFreshAnalysisForUsername:@"fixture-other"] && [c requiresFreshAnalysisForUsername:@"fixture-person"];
    [c setEnabled:YES];freshDisabled &= [c requiresFreshAnalysisForUsername:@"fixture-other"];
    [c setEnabled:NO];
    id manager=WPWeChatService(@"CContactMgr");NSDictionary *contacts=[manager valueForKey:@"fixtureContacts"];id selfContact=contacts[@"wxid_contract_self"];
    NSString *originalUsername=[selfContact valueForKey:@"m_nsUsrName"];[selfContact setValue:@"wxid_other_account_contract" forKey:@"m_nsUsrName"];
    NSString *otherAccount=WPAdvisorCurrentAccountFingerprint();NSString *otherSelected=[NSString stringWithFormat:@"advisor.continuous.%@.selected",otherAccount?:@""];
    NSString *otherList=[NSString stringWithFormat:@"advisor.continuous.%@.usernames",otherAccount?:@""];
    NSString *otherFresh=[NSString stringWithFormat:@"advisor.continuous.%@.requireFresh",otherAccount?:@""];
    id oldOtherSelected=[prefs objectForKey:otherSelected],oldOtherList=[prefs objectForKey:otherList],oldOtherFresh=[prefs objectForKey:otherFresh];[prefs removeObjectForKey:otherSelected];[prefs removeObjectForKey:otherList];[prefs removeObjectForKey:otherFresh];
    [c refreshAccountIfNeeded];BOOL accountIsolation=otherAccount.length && ![c isEnabledForUsername:@"fixture-person"] && !c.hasEnabledContacts;
    [c setLockedUsername:@"fixture-person"];[c setEnabled:YES];BOOL freshAccountIsolation=![c requiresFreshAnalysisForUsername:@"fixture-person"];
    [c setRequiresFreshAnalysis:YES forUsername:@"fixture-person"];
    [selfContact setValue:originalUsername forKey:@"m_nsUsrName"];[c refreshAccountIfNeeded];accountIsolation &= [c isEnabledForUsername:@"fixture-person"];freshAccountIsolation &= [c requiresFreshAnalysisForUsername:@"fixture-person"];
    if(oldOtherSelected)[prefs setObject:oldOtherSelected forKey:otherSelected];else[prefs removeObjectForKey:otherSelected];
    if(oldOtherList)[prefs setObject:oldOtherList forKey:otherList];else[prefs removeObjectForKey:otherList];
    if(oldOtherFresh)[prefs setObject:oldOtherFresh forKey:otherFresh];else[prefs removeObjectForKey:otherFresh];
    c.foregroundAvailable=NO;[c noteIncomingUsername:@"fixture-person" identifier:@"background" createdAt:now text:@"hello"];WPCAdvance();BOOL foregroundOnly=incoming==4 && submitted==4;
    [c setLockedUsername:@"bad@chatroom"];BOOL groupsRejected=!c.lockedUsername.length;
    c.onReady=nil;c.isBusy=nil;c.onIncoming=nil;c.onMessage=nil;
    for(NSUInteger i=0;i<keys.count;i++){if(saved[i]==NSNull.null)[prefs removeObjectForKey:keys[i]];else[prefs setObject:saved[i] forKey:keys[i]];}
    return @{@"continuousFreshPrivateDeduplicated":@(dedup),@"continuousMaximumWait":@(maximum),@"continuousWaitsForBusyTask":@(held),@"continuousCoalescesDuringGeneration":@(coalesced),@"continuousKeepsUnavailableContext":@(deferred&&retried),@"continuousIndependentContacts":@(independent),@"continuousAccountIsolation":@(accountIsolation),@"continuousForegroundOnly":@(foregroundOnly),@"continuousRejectsGroup":@(groupsRejected),@"continuousFreshGuardDefaultsOff":@(freshDefault),@"continuousFreshGuardContactIsolation":@(freshPerContact),@"continuousFreshGuardOnlyWhileEnabled":@(freshDisabled),@"continuousFreshGuardAccountIsolation":@(freshAccountIsolation)};
}
