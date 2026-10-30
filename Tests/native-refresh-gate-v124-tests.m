#import <Foundation/Foundation.h>
#import "WPNativeRefreshGate.h"
static void check(BOOL result,NSString *name){if(!result){fprintf(stderr,"FAIL: %s\n",name.UTF8String);exit(1);}}
int main(void){@autoreleasepool{
    dispatch_queue_t delivery=dispatch_queue_create("dev.zhour.test.native-refresh",DISPATCH_QUEUE_SERIAL);
    dispatch_semaphore_t blocked=dispatch_semaphore_create(0),release=dispatch_semaphore_create(0),received=dispatch_semaphore_create(0);
    dispatch_async(delivery,^{dispatch_semaphore_signal(blocked);dispatch_semaphore_wait(release,DISPATCH_TIME_FOREVER);});
    dispatch_semaphore_wait(blocked,DISPATCH_TIME_FOREVER);
    __block NSUInteger calls=0,lastGeneration=0;
    WPNativeRefreshGate *gate=[[WPNativeRefreshGate alloc] initWithQueue:delivery delay:.01 delivery:^(NSUInteger generation){calls++;lastGeneration=generation;dispatch_semaphore_signal(received);}];
    [gate setEnabled:YES foreground:YES];
    dispatch_apply(1000,dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^(__unused size_t index){[gate signal];});
    check([gate.diagnostics[@"pending"] unsignedIntegerValue]==1 && [gate.diagnostics[@"submitted"] unsignedIntegerValue]==1,@"1000 concurrent signals queue one delivery");
    for(NSUInteger index=0;index<20;index++){[gate setEnabled:NO foreground:NO];[gate setEnabled:YES foreground:YES];[gate signal];}
    check([gate.diagnostics[@"submitted"] unsignedIntegerValue]==1,@"rapid lifecycle changes do not queue stale blocks");
    dispatch_semaphore_signal(release);
    check(dispatch_semaphore_wait(received,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC))==0,@"latest generation eventually refreshes");
    dispatch_sync(delivery,^{});
    check(calls==1 && lastGeneration==[gate.diagnostics[@"generation"] unsignedIntegerValue],@"old generations do not commit");
    [gate setEnabled:YES foreground:NO];NSUInteger before=[gate.diagnostics[@"submitted"] unsignedIntegerValue];
    dispatch_apply(150,dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^(__unused size_t index){[gate signal];});
    check([gate.diagnostics[@"pending"] unsignedIntegerValue]==0 && [gate.diagnostics[@"submitted"] unsignedIntegerValue]==before && [gate.diagnostics[@"rejected"] unsignedIntegerValue]==150,@"background backlog is rejected before the delivery queue");
    [gate setEnabled:YES foreground:YES];[gate signal];
    check(dispatch_semaphore_wait(received,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC))==0,@"foreground notification resumes after backlog");
    dispatch_sync(delivery,^{});
    check([gate.diagnostics[@"maximumPending"] unsignedIntegerValue]==1 && calls==2,@"queue remains bounded after recovery");
    puts("Native refresh gate: 7 regression groups passed");
}return 0;}
