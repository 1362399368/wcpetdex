#import "WPAdvisorTaskCenter.h"
#import "WPCommon.h"
#import "WPSessionEligibility.h"
#import <objc/runtime.h>

@interface WPTaskCheckRequest : WPChatAdvisorRequest
@property(nonatomic) BOOL didCancel;
@end
@implementation WPTaskCheckRequest
- (void)cancel {self.didCancel=YES;}
@end
@interface WPTaskCheckCenter : WPAdvisorTaskCenter @end
@interface WPAdvisorTaskCenter (WPExpiryCheck)
- (void)onForeground:(NSNotification *)notification;
@end
static NSString *WPTaskCheckPath;
@implementation WPTaskCheckCenter
- (NSString *)historyPath {return WPTaskCheckPath;}
@end
static NSMutableArray *WPTaskCheckCallbacks,*WPTaskCheckTokens;
static WPChatAdvisorRequest *WPTaskStub(__unused id cls,__unused SEL command,__unused NSArray *lines,__unused BOOL group,void (^completion)(WPChatAdvice *,NSString *)){
    WPTaskCheckRequest *token=[WPTaskCheckRequest new];[WPTaskCheckTokens addObject:token];[WPTaskCheckCallbacks addObject:[completion copy]];return token;
}
static void WPTaskCheckSpin(void){[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.03]];}
static NSArray *WPTaskCheckReadRecords(void){NSData *data=[NSData dataWithContentsOfFile:WPTaskCheckPath];id value=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;return [value isKindOfClass:NSArray.class]?value:@[];}
static BOOL WPTaskCheckContainsID(NSArray *records,NSString *identifier){for(id item in records)if([item isKindOfClass:NSDictionary.class] && [item[@"id"] isEqual:identifier])return YES;return NO;}
static WPChatAdvice *WPTaskCheckAdvice(void){
    WPChatAdvice *a=[WPChatAdvice new];a.summary=@"测试建议";a.strategy=@"";a.riskLabel=@"";a.replyTiming=@"";a.riskLevel=0;
    a.intents=@[];a.actions=@[];a.replies=@[@"好的"];return a;
}

NSDictionary<NSString *,NSNumber *> *WPAdvisorTaskCenterPreviewChecks(void){
    NSMutableDictionary *checks=[NSMutableDictionary new];
    WPTaskCheckPath=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"wp-advisor-test-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    WPTaskCheckCallbacks=[NSMutableArray new];WPTaskCheckTokens=[NSMutableArray new];
    Method method=class_getClassMethod(WPChatAdvisor.class,@selector(startAnalysisOfLines:group:completion:));
    IMP original=method_setImplementation(method,(IMP)WPTaskStub);
    id selfContact=WPSEReadObject(WPWeChatService(@"CContactMgr"),@[@"getSelfContact"]);
    NSString *savedSelf=[WPSEReadObject(selfContact,@[@"m_nsUsrName"]) copy];
    @try {
        WPTaskCheckCenter *center=[WPTaskCheckCenter new];
        WPChatLine *line=[WPChatLine lineFromMe:NO speaker:@"sample" text:@"RAW_MESSAGE_DO_NOT_PERSIST" date:[NSDate dateWithTimeIntervalSince1970:1700000000]];
        WPAdvisorTask *a=[center submitUsername:@"a" displayName:@"甲" lines:@[line] group:NO];
        WPAdvisorTask *b=[center submitUsername:@"b" displayName:@"乙" lines:@[line] group:NO];
        WPAdvisorTask *c=[center submitUsername:@"c" displayName:@"丙" lines:@[line] group:NO];
        checks[@"advisorTasksBoundedTwoConcurrent"]=@(a.state==WPAdvisorTaskRunning && b.state==WPAdvisorTaskRunning && c.state==WPAdvisorTaskQueued && WPTaskCheckTokens.count==2);
        [center cancelTask:b];
        checks[@"advisorCancelStartsQueued"]=@([WPTaskCheckTokens[1] didCancel] && c.state==WPAdvisorTaskRunning && WPTaskCheckTokens.count==3);
        WPAdvisorTask *replacement=[center submitUsername:@"a" displayName:@"甲" lines:@[line] group:NO];
        checks[@"advisorReplacementCancelsPrevious"]=@([WPTaskCheckTokens[0] didCancel] && a.state==WPAdvisorTaskCancelled && replacement.state==WPAdvisorTaskRunning);
        void (^oldReply)(WPChatAdvice *,NSString *)=WPTaskCheckCallbacks[0];oldReply(WPTaskCheckAdvice(),nil);WPTaskCheckSpin();
        checks[@"advisorOldResponseCannotOverwrite"]=@(a.state==WPAdvisorTaskCancelled && center.history.count==0);
        void (^replyC)(WPChatAdvice *,NSString *)=WPTaskCheckCallbacks[2];replyC(WPTaskCheckAdvice(),nil);WPTaskCheckSpin();
        checks[@"advisorCompletedResultIsUnread"]=@(c.state==WPAdvisorTaskCompleted && c.unread && center.unreadResults.count==1 && [c.username isEqual:@"c"]);
        [center markStaleForUsername:@"c"];checks[@"advisorNewArrivalMarksStale"]=@(c.stale);
        [center markResultRead:c];checks[@"advisorReadClearsBadge"]=@(!c.unread && center.unreadResults.count==0);
        NSString *disk=[NSString stringWithContentsOfFile:WPTaskCheckPath encoding:NSUTF8StringEncoding error:nil];
        checks[@"advisorHistoryDoesNotStoreRawMessages"]=@(disk.length && ![disk containsString:@"RAW_MESSAGE_DO_NOT_PERSIST"]);
        WPTaskCheckCenter *loaded=[WPTaskCheckCenter new];
        checks[@"advisorHistoryRestoresBoundResult"]=@(loaded.history.count==1 && [loaded.history.firstObject.username isEqual:@"c"] && !loaded.history.firstObject.unread);
        WPChatLine *newLine=[WPChatLine lineFromMe:NO speaker:@"sample" text:@"新消息" date:[NSDate dateWithTimeIntervalSince1970:1700000001]];
        checks[@"advisorFingerprintMatchesOnlySameContext"]=@(WPAdvisorTaskMatchesLines(c,@[line]) && !WPAdvisorTaskMatchesLines(c,@[newLine]) && WPAdvisorTaskMatchesLines(loaded.history.firstObject,@[line]));
        // Exercise the real timer with a current account having no history.
        // Copies carry synthetic account hashes and only synthetic result text.
        NSMutableArray *shared=[WPTaskCheckReadRecords() mutableCopy];NSDictionary *base=shared.firstObject;
        NSTimeInterval now=NSDate.date.timeIntervalSince1970;
        NSMutableDictionary *soon=[base mutableCopy],*fresh=[base mutableCopy],*future=[base mutableCopy];
        soon[@"account"]=[@"a" stringByPaddingToLength:64 withString:@"a" startingAtIndex:0];soon[@"id"]=@"foreign-soon";soon[@"created"]=@(now-3*24*60*60+.5);
        fresh[@"account"]=[@"b" stringByPaddingToLength:64 withString:@"b" startingAtIndex:0];fresh[@"id"]=@"foreign-fresh";fresh[@"created"]=@(now);
        future[@"account"]=[@"c" stringByPaddingToLength:64 withString:@"c" startingAtIndex:0];future[@"id"]=@"foreign-future";future[@"created"]=@(now+3600);
        [shared addObjectsFromArray:@[soon,fresh,future]];[[NSJSONSerialization dataWithJSONObject:shared options:0 error:nil] writeToFile:WPTaskCheckPath atomically:YES];
        [selfContact setValue:@"wxid_third_account_test" forKey:@"m_nsUsrName"];
        BOOL noOwn=center.history.count==0;NSTimer *expiry=[center valueForKey:@"expiryTimer"];
        NSArray *before=WPTaskCheckReadRecords();
        checks[@"advisorForeignExpiryScheduledWithoutOwnHistory"]=@(noOwn && expiry.valid && [expiry.fireDate timeIntervalSinceNow]<1 && WPTaskCheckContainsID(before,@"foreign-soon") && WPTaskCheckContainsID(before,@"foreign-fresh") && WPTaskCheckContainsID(before,@"foreign-future"));
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.8]];
        NSArray *after=WPTaskCheckReadRecords();
        checks[@"advisorForeignTimerExpiresOnlyDueRecords"]=@(!WPTaskCheckContainsID(after,@"foreign-soon") && WPTaskCheckContainsID(after,@"foreign-fresh") && WPTaskCheckContainsID(after,@"foreign-future"));
        NSMutableDictionary *past=[soon mutableCopy];past[@"id"]=@"foreign-foreground-expired";past[@"created"]=@(now-3*24*60*60-1);
        NSMutableArray *foreground=[after mutableCopy];[foreground addObject:past];[[NSJSONSerialization dataWithJSONObject:foreground options:0 error:nil] writeToFile:WPTaskCheckPath atomically:YES];
        [center onForeground:nil];NSArray *resumed=WPTaskCheckReadRecords();
        checks[@"advisorForegroundCleansForeignOnlyWhenDue"]=@(!WPTaskCheckContainsID(resumed,@"foreign-foreground-expired") && WPTaskCheckContainsID(resumed,@"foreign-fresh") && WPTaskCheckContainsID(resumed,@"foreign-future"));
        [selfContact setValue:@"wxid_other_account_test" forKey:@"m_nsUsrName"];
        checks[@"advisorDifferentAccountCannotReadOrAct"]=@(savedSelf.length && center.history.count==0 && !WPAdvisorTaskBelongsToCurrentAccount(c) && !WPAdvisorTaskMatchesLines(c,@[line]));
        [selfContact setValue:nil forKey:@"m_nsUsrName"];
        checks[@"advisorUnknownAccountFailsClosed"]=@(!WPAdvisorCurrentAccountFingerprint() && center.history.count==0 && ![center submitUsername:@"u" displayName:@"U" lines:@[line] group:NO]);
        [selfContact setValue:savedSelf forKey:@"m_nsUsrName"];
        checks[@"advisorOriginalAccountHistoryRestored"]=@(center.history.count==1 && WPAdvisorTaskMatchesLines(center.history.firstObject,@[line]));
        c=center.history.firstObject;
        [c setValue:nil forKey:@"contextFingerprint"];
        checks[@"advisorLegacyFingerprintFailsClosed"]=@(!WPAdvisorTaskMatchesLines(c,@[line]));
        [c setValue:[NSDate dateWithTimeIntervalSinceNow:-4*24*60*60] forKey:@"createdAt"];
        checks[@"advisorHistoryExpiresAfterThreeDays"]=@(center.history.count==0);
        [loaded clearHistory];checks[@"advisorHistoryCanBeCleared"]=@(loaded.history.count==0);
        [center cancelTask:replacement];
    } @finally {if(selfContact && savedSelf)[selfContact setValue:savedSelf forKey:@"m_nsUsrName"];method_setImplementation(method,original);[NSFileManager.defaultManager removeItemAtPath:WPTaskCheckPath error:nil];}
    return checks;
}
