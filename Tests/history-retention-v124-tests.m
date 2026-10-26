#import <Foundation/Foundation.h>
#import "WPCoupleHistory.h"
static void check(BOOL value,NSString *name){if(!value){fprintf(stderr,"FAIL: %s\n",name.UTF8String);exit(1);}}
int main(int argc,const char *argv[]){@autoreleasepool{
    NSURL *root=[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]] isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:nil];
    NSURL *file=[root URLByAppendingPathComponent:@"retention.json"];
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;
    NSString *oldID=NSUUID.UUID.UUIDString,*newID=NSUUID.UUID.UUIDString;
    NSDictionary *old=@{@"id":oldID,@"kind":@"anger",@"sent_at":@(now-259201),@"received_at":@(now-259200),@"needs_response":@YES,@"animation_played":@YES};
    NSDictionary *recent=@{@"id":newID,@"kind":@"anger",@"sent_at":@(now-259190),@"received_at":@(now-259190),@"needs_response":@YES,@"animation_played":@YES};
    NSDictionary *sent=@{@"id":NSUUID.UUID.UUIDString,@"kind":@"miss",@"sent_at":@(now-259201),@"state":@"delivered"};
    NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"version":@3,@"incoming":@[old,recent],@"outgoing":@[sent]} options:0 error:nil];
    [data writeToURL:file atomically:YES];
    WPCoupleHistory *history=[[WPCoupleHistory alloc] initWithURL:file];
    check(history.recentInteractions.count==1 && history.badgeCount==1,@"startup removes old incoming and delivered outgoing");
    WPCoupleHistory *reloaded=[[WPCoupleHistory alloc] initWithURL:file];
    check(reloaded.recentInteractions.count==1,@"startup deletion persists on disk");
    __block NSUInteger notifications=0;
    id observer=[NSNotificationCenter.defaultCenter addObserverForName:WPCoupleHistoryDidChangeNotification object:history queue:nil usingBlock:^(__unused NSNotification *note){notifications++;}];
    check([history purgeRecordsExpiredAtDate:[NSDate dateWithTimeIntervalSince1970:now+10]],@"cleanup succeeds");
    check(history.badgeCount==0 && !history.hasPendingAnger && history.recentInteractions.count==0,@"72-hour boundary also clears derived anger and badge");
    check(notifications==1,@"one change notification per purge");
    check([history purgeRecordsExpiredAtDate:[NSDate dateWithTimeIntervalSince1970:now+10]] && notifications==1,@"empty cleanup is idempotent");
    BOOL isNew=YES;
    check([history receiveKind:@"anger" identifier:oldID at:[NSDate dateWithTimeIntervalSince1970:now-259201] receivedAt:NSDate.date isNew:&isNew] && !isNew && history.recentInteractions.count==0,@"expired replay acknowledges without restoring history");
    check([history receiveKind:@"pet" identifier:NSUUID.UUID.UUIDString at:NSDate.date isNew:&isNew] && isNew,@"new interaction remains usable");
    [NSNotificationCenter.defaultCenter removeObserver:observer];
    puts("History retention: 7 regression groups passed");
}return 0;}
