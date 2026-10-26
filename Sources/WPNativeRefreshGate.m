#import "WPNativeRefreshGate.h"
@interface WPNativeRefreshGate ()
@property(nonatomic) NSLock *lock;
@property(nonatomic) dispatch_queue_t queue;
@property(nonatomic,copy) void (^delivery)(NSUInteger);
@property(nonatomic) NSTimeInterval delay;
@property(nonatomic) BOOL enabled,foreground,scheduled,dirty;
@property(nonatomic) NSUInteger generation,submitted,delivered,rejected,signals,maximumPending,deliveryFailures;
@end
@implementation WPNativeRefreshGate
- (instancetype)initWithQueue:(dispatch_queue_t)queue delay:(NSTimeInterval)delay delivery:(void (^)(NSUInteger))delivery {
    if((self=[super init])){_lock=[NSLock new];_queue=queue;_delay=MAX(0,delay);_delivery=[delivery copy];}return self;
}
- (void)setEnabled:(BOOL)enabled foreground:(BOOL)foreground {
    [self.lock lock];
    if(self.enabled!=enabled || self.foreground!=foreground){self.generation++;self.dirty=NO;}
    self.enabled=enabled;self.foreground=foreground;
    // scheduled remains occupied until its existing block drains. Repeated
    // deactivate/reactivate cannot enqueue one stale block per generation.
    [self.lock unlock];
}
- (void)scheduleGeneration:(NSUInteger)generation {
    __weak typeof(self) weakSelf=self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(self.delay*NSEC_PER_SEC)),self.queue,^{[weakSelf deliverGeneration:generation];});
}
- (void)signal {
    [self.lock lock];self.signals++;
    if(!self.enabled || !self.foreground){self.rejected++;[self.lock unlock];return;}
    self.dirty=YES;
    if(self.scheduled){[self.lock unlock];return;}
    self.scheduled=YES;self.maximumPending=MAX(self.maximumPending,(NSUInteger)1);self.submitted++;NSUInteger generation=self.generation;
    [self.lock unlock];[self scheduleGeneration:generation];
}
- (void)deliverGeneration:(NSUInteger)generation {
    [self.lock lock];
    BOOL valid=self.enabled && self.foreground && generation==self.generation && self.dirty;
    if(valid){self.dirty=NO;self.delivered++;}
    [self.lock unlock];
    @try{if(valid && self.delivery)self.delivery(generation);}
    @catch(__unused NSException *exception){[self.lock lock];self.deliveryFailures++;[self.lock unlock];}
    [self.lock lock];
    BOOL again=self.enabled && self.foreground && self.dirty;
    NSUInteger next=self.generation;
    if(again)self.submitted++;else self.scheduled=NO;
    [self.lock unlock];if(again)[self scheduleGeneration:next];
}
- (NSDictionary<NSString *,NSNumber *> *)diagnostics {
    [self.lock lock];NSDictionary *result=@{@"generation":@(self.generation),@"enabled":@(self.enabled),@"foreground":@(self.foreground),@"pending":@(self.scheduled?1:0),@"maximumPending":@(self.maximumPending),@"signals":@(self.signals),@"submitted":@(self.submitted),@"delivered":@(self.delivered),@"rejected":@(self.rejected),@"deliveryFailures":@(self.deliveryFailures)};[self.lock unlock];return result;
}
@end
