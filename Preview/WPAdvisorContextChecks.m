#import "WPAdvisorContextStore.h"
#import "WPCommon.h"
#import "WPSessionEligibility.h"

NSDictionary *WPAdvisorContextPreviewChecks(void){
    WPAdvisorContextStore *store=[WPAdvisorContextStore new];NSDate *base=NSDate.date;
    [store appendIncomingForUsername:@"one" identifier:@"new" text:@"arrived" date:[base dateByAddingTimeInterval:50]];
    BOOL unseeded=[store snapshotForUsername:@"one"]==nil;
    NSMutableArray *lines=[NSMutableArray new];
    for(NSUInteger i=0;i<25;i++){
        [lines addObject:[WPChatLine lineFromMe:NO speaker:@"one" text:[NSString stringWithFormat:@"received%lu",(unsigned long)i] date:[base dateByAddingTimeInterval:i]]];
        if(i%5==0)[lines addObject:[WPChatLine lineFromMe:YES speaker:@"" text:@"my reply" date:[base dateByAddingTimeInterval:i+.1]]];
    }
    [store seedUsername:@"one" visibleLines:lines];NSArray<WPChatLine *> *snapshot=[store snapshotForUsername:@"one"];
    NSUInteger incoming=0;BOOL outgoing=NO;for(WPChatLine *line in snapshot){if(line.fromMe)outgoing=YES;else incoming++;}
    BOOL bounded=incoming<=20 && snapshot.count<=40 && outgoing && [snapshot.lastObject.text isEqual:@"arrived"];
    NSUInteger count=snapshot.count;[store appendIncomingForUsername:@"one" identifier:@"new" text:@"arrived" date:[base dateByAddingTimeInterval:50]];
    BOOL dedup=[store snapshotForUsername:@"one"].count==count;
    BOOL separate=[store snapshotForUsername:@"two"]==nil;
    id selfContact=WPSEReadObject(WPWeChatService(@"CContactMgr"),@[@"getSelfContact"]);
    NSString *original=[WPSEReadObject(selfContact,@[@"m_nsUsrName"]) copy];
    [selfContact setValue:@"other-account-context-test" forKey:@"m_nsUsrName"];
    BOOL isolated=original.length && [store snapshotForUsername:@"one"]==nil;
    if(original)[selfContact setValue:original forKey:@"m_nsUsrName"];
    [store clear];BOOL cleared=[store snapshotForUsername:@"one"]==nil;
    return @{@"advisorContextWaitsForSeed":@(unseeded),@"advisorContextHasRecentIncomingAndBothSides":@(bounded),@"advisorContextDeduplicates":@(dedup),@"advisorContextSeparatesChats":@(separate),@"advisorContextIsolatedAcrossAccounts":@(isolated),@"advisorContextCanReleaseMemory":@(cleared)};
}
