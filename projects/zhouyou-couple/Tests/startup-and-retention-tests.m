#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "WPCoupleHistory.h"

static NSURL *WPFixtureSupportURL;
@interface NSFileManager (WPIsolatedHistoryTest)
- (NSArray<NSURL *> *)wp_testURLsForDirectory:(NSSearchPathDirectory)directory inDomains:(NSSearchPathDomainMask)domainMask;
@end
@implementation NSFileManager (WPIsolatedHistoryTest)
- (NSArray<NSURL *> *)wp_testURLsForDirectory:(NSSearchPathDirectory)directory inDomains:(NSSearchPathDomainMask)domainMask {
    if(directory==NSApplicationSupportDirectory && domainMask==NSUserDomainMask)return @[WPFixtureSupportURL];
    return [self wp_testURLsForDirectory:directory inDomains:domainMask];
}
@end

static void WPAssert(BOOL condition, NSString *message) {
    if(!condition){NSLog(@"FAIL: %@",message);exit(1);}
}

int main(void) {
    @autoreleasepool {
        NSString *fixture=[NSProcessInfo.processInfo.environment[@"WP_TEST_ROOT"] stringByStandardizingPath];
        WPAssert(fixture.length>0,@"An isolated fixture directory is required");
        WPFixtureSupportURL=[NSURL fileURLWithPath:[fixture stringByAppendingPathComponent:@"Application Support"] isDirectory:YES];
        Method original=class_getInstanceMethod(NSFileManager.class,@selector(URLsForDirectory:inDomains:));
        Method isolated=class_getInstanceMethod(NSFileManager.class,@selector(wp_testURLsForDirectory:inDomains:));
        WPAssert(original && isolated,@"Locate Foundation directory lookup for test isolation");
        method_exchangeImplementations(original,isolated);
        NSURL *support=[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
        WPAssert(fixture.length && [support.path hasPrefix:fixture],@"Refusing to write outside the isolated test home");
        NSURL *directory=[support URLByAppendingPathComponent:@"WeChatPet" isDirectory:YES];
        NSURL *file=[directory URLByAppendingPathComponent:@"interactions.json"];
        NSError *error=nil;
        WPAssert([NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:&error],@"Create fixture directory");
        NSString *expiredID=NSUUID.UUID.UUIDString;
        NSDictionary *fixtureRow=@{@"version":@3,@"outgoing":@[@{@"id":expiredID,@"kind":@"miss",@"sent_at":@(NSDate.date.timeIntervalSince1970-172800),@"direction":@"outgoing",@"state":@"waiting"}],@"incoming":@[]};
        NSData *data=[NSJSONSerialization dataWithJSONObject:fixtureRow options:0 error:&error];
        WPAssert(data && [data writeToURL:file options:NSDataWritingAtomic error:&error],@"Write expired outgoing fixture");

        // The overlay already observes history changes before its first read.
        // A notification from inside sharedHistory's dispatch_once initializer
        // will recursively enter sharedHistory and crash on the main thread.
        __block NSUInteger notifications=0;
        id observer=[NSNotificationCenter.defaultCenter addObserverForName:WPCoupleHistoryDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *notification){
            notifications++;
            (void)WPCoupleHistory.sharedHistory.badgeCount;
        }];
        WPCoupleHistory *history=WPCoupleHistory.sharedHistory;
        WPAssert(history.pendingCount==0,@"Expired outgoing is no longer pending on startup");
        NSArray *rows=history.recentInteractions;
        WPAssert(rows.count==1 && [rows[0][@"state"] isEqual:@"expired"],@"Expired outgoing remains in history");
        NSDictionary *stored=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:file] options:0 error:&error];
        WPAssert([stored[@"outgoing"][0][@"state"] isEqual:@"expired"],@"Startup expiration is persisted");
        [NSNotificationCenter.defaultCenter removeObserver:observer];

        // No unresolved reminder may be silently discarded just because the
        // visible history passed an ordinary display/retention threshold.
        WPCoupleHistory *many=[[WPCoupleHistory alloc] initWithURL:[directory URLByAppendingPathComponent:@"many-interactions.json"]];
        NSString *firstID=nil;
        for(NSUInteger index=0;index<401;index++){
            NSString *identifier=NSUUID.UUID.UUIDString;
            if(!firstID)firstID=identifier;
            BOOL isNew=NO;
            WPAssert([many receiveKind:@"anger" identifier:identifier at:NSDate.date isNew:&isNew] && isNew,@"Persist every incoming interaction");
        }
        WPAssert(many.badgeCount==401,@"All 401 unresolved reminders remain counted");
        WPAssert(many.pendingIncoming.count==401,@"All 401 unresolved reminders remain available to respond");
        WPAssert(many.recentInteractions.count==401,@"All 401 interactions remain in the record");
        BOOL firstRetained=NO;
        for(NSDictionary *row in many.pendingIncoming)if([row[@"id"] isEqual:firstID])firstRetained=YES;
        WPAssert(firstRetained,@"Oldest unresolved reminder is retained");
        WPCoupleHistory *reloaded=[[WPCoupleHistory alloc] initWithURL:[directory URLByAppendingPathComponent:@"many-interactions.json"]];
        WPAssert(reloaded.badgeCount==401 && reloaded.pendingIncoming.count==401,@"All unresolved reminders survive restart");

        NSArray *allIncomingIDs=[many.pendingIncoming valueForKey:@"id"];
        WPAssert([many manuallyClearIncomingIdentifiers:allIncomingIDs],@"Resolve all 401 incoming reminders");
        WPAssert(many.badgeCount==0 && many.recentInteractions.count==401,@"All resolved incoming rows remain in history");
        NSString *laterID=NSUUID.UUID.UUIDString;
        BOOL laterIsNew=NO;
        WPAssert([many receiveKind:@"anger" identifier:laterID at:NSDate.date isNew:&laterIsNew] && laterIsNew,@"Receive after 401 resolved rows");
        WPAssert(many.recentInteractions.count==402 && many.badgeCount==1,@"New event does not evict old resolved history");
        WPCoupleHistory *resolvedReloaded=[[WPCoupleHistory alloc] initWithURL:[directory URLByAppendingPathComponent:@"many-interactions.json"]];
        WPAssert(resolvedReloaded.recentInteractions.count==402 && resolvedReloaded.badgeCount==1,@"Resolved incoming history survives restart");

        NSURL *sentURL=[directory URLByAppendingPathComponent:@"delivered-outgoing.json"];
        WPCoupleHistory *sent=[[WPCoupleHistory alloc] initWithURL:sentURL];
        NSString *firstOutgoingID=nil;
        for(NSUInteger index=0;index<401;index++){
            NSString *identifier=NSUUID.UUID.UUIDString;
            if(!firstOutgoingID)firstOutgoingID=identifier;
            WPAssert([sent enqueueKind:@"miss" identifier:identifier at:NSDate.date],@"Save outgoing interaction");
            WPAssert([sent updateIdentifier:identifier state:@"delivered" serverTime:nil],@"Mark outgoing interaction delivered");
        }
        BOOL firstOutgoingRetained=NO;
        for(NSDictionary *row in sent.recentInteractions)if([row[@"id"] isEqual:firstOutgoingID])firstOutgoingRetained=YES;
        WPAssert(sent.pendingCount==0 && sent.recentInteractions.count==401 && firstOutgoingRetained,@"All 401 delivered outgoing rows remain visible");
        WPCoupleHistory *sentReloaded=[[WPCoupleHistory alloc] initWithURL:sentURL];
        WPAssert(sentReloaded.recentInteractions.count==401 && sentReloaded.pendingCount==0,@"Delivered outgoing history survives restart");

        // A locally saved reply is not yet accepted by the server. Its snapshot
        // remains pending, but a second tap must not reserve the same IDs again.
        NSURL *replyURL=[directory URLByAppendingPathComponent:@"reply-reservation.json"];
        WPCoupleHistory *reply=[[WPCoupleHistory alloc] initWithURL:replyURL];
        NSString *firstMiss=NSUUID.UUID.UUIDString,*secondMiss=NSUUID.UUID.UUIDString;
        BOOL isNew=NO;
        NSDate *overdue=[NSDate dateWithTimeIntervalSinceNow:-(WPMissResponseWindow+61)];
        WPAssert([reply receiveKind:@"miss" identifier:firstMiss at:overdue receivedAt:NSDate.date isNew:&isNew] && isNew,@"Receive first pending reminder");
        WPAssert([reply receiveKind:@"miss" identifier:secondMiss at:overdue receivedAt:NSDate.date isNew:&isNew] && isNew,@"Receive second pending reminder");
        NSArray *snapshot=reply.uncoveredPendingIncomingIdentifiers;
        WPAssert(snapshot.count==2,@"Both new reminders are uncovered");
        NSString *replyID=NSUUID.UUID.UUIDString;
        WPAssert([reply enqueueKind:@"miss" identifier:replyID at:NSDate.date resolvingIncomingIdentifiers:snapshot],@"Save offline reply snapshot");
        WPAssert(reply.badgeCount==2 && reply.uncoveredPendingIncomingIdentifiers.count==0,@"Waiting reply reserves IDs without clearing badges");
        reply=[[WPCoupleHistory alloc] initWithURL:replyURL];
        WPAssert(reply.badgeCount==2 && reply.uncoveredPendingIncomingIdentifiers.count==0,@"Reply reservation survives restart");
        NSString *newMiss=NSUUID.UUID.UUIDString;
        WPAssert([reply receiveKind:@"miss" identifier:newMiss at:overdue receivedAt:NSDate.date isNew:&isNew] && isNew,@"Receive a new reminder while reply waits");
        WPAssert([reply.uncoveredPendingIncomingIdentifiers isEqual:@[newMiss]],@"Only the later reminder remains uncovered");
        WPAssert([reply updateIdentifier:replyID state:@"queued" serverTime:nil],@"Server accepts the first reply");
        WPAssert(reply.badgeCount==1 && [reply.uncoveredPendingIncomingIdentifiers isEqual:@[newMiss]],@"Accepted reply clears only its original snapshot");
        printf("startup-and-retention: 5 passed (startup expiration, 401 unresolved, 401 resolved, 401 delivered, offline reply snapshot; notifications=%lu)\n",(unsigned long)notifications);
    }
    return 0;
}
