#import <Foundation/Foundation.h>
#import "WPCoupleHistory.h"

static int checks=0,failures=0;
static void check(NSString *name,BOOL good){checks++;if(!good){failures++;fprintf(stderr,"FAIL %s\n",name.UTF8String);}}
static NSString *uid(void){return NSUUID.UUID.UUIDString;}
static WPCoupleHistory *fresh(NSString *path){[[NSFileManager defaultManager] removeItemAtPath:path error:nil];return [[WPCoupleHistory alloc] initWithURL:[NSURL fileURLWithPath:path]];}
static NSDictionary *row(WPCoupleHistory *h,NSString *id){for(NSDictionary *r in h.recentInteractions)if([r[@"id"] isEqual:id])return r;return nil;}
static void receive(WPCoupleHistory *h,NSString *kind,NSString *id,NSTimeInterval age){BOOL isNew=NO;NSDate *now=NSDate.date;
    check(@"receive",[h receiveKind:kind identifier:id at:[now dateByAddingTimeInterval:-age] receivedAt:now isNew:&isNew]&&isNew);}
static NSArray *seed(WPCoupleHistory *h){NSMutableArray *ids=[NSMutableArray new];
    for(int i=0;i<3;i++){NSString *id=uid();[ids addObject:id];receive(h,@"anger",id,900-i);}
    for(int i=0;i<4;i++){NSString *id=uid();[ids addObject:id];receive(h,@"miss",id,900-i);}return ids;}
int main(int argc,const char **argv){@autoreleasepool{
    NSString *root=argc>1?[NSString stringWithUTF8String:argv[1]]:NSTemporaryDirectory();
    WPCoupleHistory *boundary=fresh([root stringByAppendingPathComponent:@"boundary.json"]);
    NSDate *now=NSDate.date;BOOL isNew=NO;
    [boundary receiveKind:@"pet" identifier:uid() at:[now dateByAddingTimeInterval:-300] receivedAt:now isNew:&isNew];
    check(@"R03 exact five minutes",isNew&&boundary.badgeCount==0);
    [boundary receiveKind:@"pet" identifier:uid() at:[now dateByAddingTimeInterval:-300.01] receivedAt:now isNew:&isNew];
    check(@"R03 just over five minutes",isNew&&boundary.badgeCount==1&&!boundary.hasPendingAnger);
    WPCoupleHistory *miss=fresh([root stringByAppendingPathComponent:@"miss.json"]);seed(miss);
    NSString *missID=uid();NSArray *missTargets=[miss responseIdentifiersForKind:@"miss"];
    check(@"R05 miss targets ordinary only",miss.badgeCount==7&&missTargets.count==4);
    [miss enqueueKind:@"miss" identifier:missID at:NSDate.date resolvingIncomingIdentifiers:missTargets];
    check(@"R08 local queue keeps badges",miss.badgeCount==7);
    [miss updateIdentifier:missID state:@"queued" serverTime:nil];
    check(@"R05 accepted miss leaves three anger",miss.badgeCount==3&&miss.hasPendingAnger);
    WPCoupleHistory *pet=fresh([root stringByAppendingPathComponent:@"pet.json"]);NSArray *ids=seed(pet);
    NSArray *first=[pet responseIdentifiersForKind:@"pet"];
    check(@"R06 pet targets one anger and four ordinary",first.count==5&&[first containsObject:ids[0]]);
    NSString *one=uid();[pet enqueueKind:@"pet" identifier:one at:NSDate.date resolvingIncomingIdentifiers:first];
    NSArray *second=[pet responseIdentifiersForKind:@"pet"];
    check(@"R07 second pet reserves next anger",second.count==1&&[second containsObject:ids[1]]);
    NSString *two=uid();[pet enqueueKind:@"pet" identifier:two at:NSDate.date resolvingIncomingIdentifiers:second];
    [pet updateIdentifier:one state:@"queued" serverTime:nil];
    check(@"R06 one accepted pet leaves two",pet.badgeCount==2&&pet.hasPendingAnger);
    [pet updateIdentifier:two state:@"queued" serverTime:nil];[pet updateIdentifier:two state:@"queued" serverTime:nil];
    check(@"R07 duplicate acceptance idempotent",pet.badgeCount==1&&[row(pet,two)[@"resolved_count"] integerValue]==1);
    receive(pet,@"anger",uid(),1);check(@"R09 new anger survives old snapshot",pet.badgeCount==2);
    WPCoupleHistory *failed=fresh([root stringByAppendingPathComponent:@"failed.json"]);seed(failed);
    NSString *bad=uid();[failed enqueueKind:@"pet" identifier:bad at:NSDate.date resolvingIncomingIdentifiers:[failed responseIdentifiersForKind:@"pet"]];
    [failed updateIdentifier:bad state:@"failed" serverTime:nil];
    check(@"R08 failed pet does not clear",failed.badgeCount==7&&[failed responseIdentifiersForKind:@"pet"].count==5);
    WPCoupleHistory *restored=[[WPCoupleHistory alloc] initWithURL:[NSURL fileURLWithPath:[root stringByAppendingPathComponent:@"pet.json"]]];
    check(@"R11 restore state",restored.badgeCount==2&&restored.hasPendingAnger);
    NSString *legacyPath=[root stringByAppendingPathComponent:@"legacy.json"];
    NSString *anger=uid(),*ordinary=uid(),*oldSend=uid();NSNumber *stamp=@(NSDate.date.timeIntervalSince1970);
    NSDictionary *legacy=@{@"version":@3,@"incoming":@[
        @{@"id":anger,@"kind":@"anger",@"sent_at":stamp,@"needs_response":@YES},
        @{@"id":ordinary,@"kind":@"miss",@"sent_at":stamp,@"needs_response":@YES}],
        @"outgoing":@[@{@"id":oldSend,@"kind":@"miss",@"sent_at":stamp,@"state":@"waiting",@"resolves":@[anger,ordinary]}]};
    [[NSJSONSerialization dataWithJSONObject:legacy options:0 error:nil] writeToFile:legacyPath atomically:YES];
    WPCoupleHistory *upgraded=[[WPCoupleHistory alloc] initWithURL:[NSURL fileURLWithPath:legacyPath]];
    check(@"R14 migrated unsent miss excludes anger",[row(upgraded,oldSend)[@"resolves"] isEqual:@[ordinary]]);
    [upgraded updateIdentifier:oldSend state:@"queued" serverTime:nil];
    check(@"R14 accepted old miss leaves anger",upgraded.badgeCount==1&&upgraded.hasPendingAnger);
    printf("{\"caseCount\":%d,\"failed\":%d,\"allPassed\":%s}\n",checks,failures,failures?"false":"true");
    return failures?1:0;
}}
