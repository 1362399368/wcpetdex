#import "WPRecoveryCoordinator.h"
#import <math.h>

@interface WPRecoveryCoordinator ()
@property(nonatomic,readwrite) WPRecoveryState state;
@property(nonatomic,readwrite) NSUInteger generation;
@property(nonatomic,readwrite) BOOL foreground;
@property(nonatomic,readwrite) BOOL temporarilySuspended;
@property(nonatomic) BOOL calibrationPending;
@property(nonatomic) BOOL pipelineStarted;
@property(nonatomic) NSUInteger nextPhase;
@property(nonatomic) NSTimeInterval beganAt;
@property(nonatomic) NSTimer *timer;
@property(nonatomic) NSMutableArray<NSDictionary *> *events;
@property(nonatomic) NSUInteger cycles;
@property(nonatomic) NSUInteger calibrations;
@property(nonatomic) NSUInteger completedPhases;
@property(nonatomic) NSUInteger failures;
@property(nonatomic) NSTimeInterval maxPhaseMilliseconds;
@property(nonatomic) BOOL cycleFailed;
@property(nonatomic) NSTimeInterval lastCycleMilliseconds;
@end
@implementation WPRecoveryCoordinator
- (instancetype)init{if((self=[super init]))_events=[NSMutableArray new];return self;}
- (void)record:(NSString *)phase duration:(NSTimeInterval)duration error:(BOOL)error {
    NSTimeInterval ms=MAX(0,duration*1000);self.maxPhaseMilliseconds=MAX(self.maxPhaseMilliseconds,ms);
    [self.events addObject:@{@"phase":phase,@"generation":@(self.generation),@"milliseconds":@(ms),@"error":@(error)}];
    while(self.events.count>32)[self.events removeObjectAtIndex:0];
}
- (void)beginForeground {
    if(self.foreground){[self requestCalibration];return;}
    self.foreground=YES;self.temporarilySuspended=NO;self.generation++;self.cycles++;
    self.pipelineStarted=NO;self.nextPhase=0;self.cycleFailed=NO;self.state=WPRecoveryStateInactive;self.beganAt=NSProcessInfo.processInfo.systemUptime;
    [self requestCalibration];
}
- (void)endForeground {
    if(!self.foreground && self.state==WPRecoveryStateInactive)return;
    self.foreground=NO;self.temporarilySuspended=NO;self.generation++;self.pipelineStarted=NO;self.nextPhase=0;
    [self.timer invalidate];self.timer=nil;self.state=WPRecoveryStateInactive;
}
- (void)setTemporarilySuspended:(BOOL)suspended {
    if(_temporarilySuspended==suspended)return;_temporarilySuspended=suspended;
    [self.timer invalidate];self.timer=nil;
    if(!suspended && self.foreground){
        if(self.pipelineStarted && self.nextPhase<4)[self scheduleNextPhaseAfter:.016];
        else [self requestCalibration];
    }
}
- (void)requestCalibration {
    if(self.calibrationPending)return;
    self.calibrationPending=YES;__weak typeof(self) weakSelf=self;
    // One run-loop callback, rather than one main-queue task per window event.
    CFRunLoopPerformBlock(CFRunLoopGetMain(),kCFRunLoopCommonModes,^{
        WPRecoveryCoordinator *self=weakSelf;if(!self)return;self.calibrationPending=NO;
        if(!self.foreground || self.temporarilySuspended)return;
        NSTimeInterval start=NSProcessInfo.processInfo.systemUptime;BOOL host=NO;
        @try{host=self.calibrateHost?self.calibrateHost():YES;}
        @catch(__unused NSException *exception){self.failures++;self.cycleFailed=YES;if(self.phaseFailed)self.phaseFailed(@"host");}
        self.calibrations++;[self record:@"host" duration:NSProcessInfo.processInfo.systemUptime-start error:!host];
        if(host && !self.pipelineStarted){
            self.pipelineStarted=YES;self.state=WPRecoveryStateHostReady;[self scheduleNextPhaseAfter:.016];
        }else if(!host && !self.pipelineStarted){
            if(NSProcessInfo.processInfo.systemUptime-self.beganAt>=2){self.state=WPRecoveryStateDegraded;return;}
            [self.timer invalidate];NSUInteger generation=self.generation;
            self.timer=[NSTimer timerWithTimeInterval:.15 repeats:NO block:^(__unused NSTimer *timer){
                if(weakSelf.generation==generation)[weakSelf requestCalibration];
            }];[NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
        }
    });CFRunLoopWakeUp(CFRunLoopGetMain());
}
- (void)scheduleNextPhaseAfter:(NSTimeInterval)delay {
    [self.timer invalidate];self.timer=nil;
    if(!self.foreground || self.temporarilySuspended || self.nextPhase>=4)return;
    NSUInteger generation=self.generation;__weak typeof(self) weakSelf=self;
    self.timer=[NSTimer timerWithTimeInterval:delay repeats:NO block:^(__unused NSTimer *timer){
        WPRecoveryCoordinator *self=weakSelf;
        if(!self || !self.foreground || self.temporarilySuspended || self.generation!=generation)return;
        self.timer=nil;NSUInteger phase=self.nextPhase++;self.state=WPRecoveryStateWarming;
        NSString *name=@[@"capture",@"renderer",@"monitor",@"maintenance"][phase];
        NSTimeInterval start=NSProcessInfo.processInfo.systemUptime;BOOL error=NO;
        @try{
            if(phase==0 && self.captureMessages)self.captureMessages();
            else if(phase==1 && self.restoreRenderer)self.restoreRenderer();
            else if(phase==2 && self.restoreMonitoring)self.restoreMonitoring();
            else if(phase==3 && self.restoreMaintenance)self.restoreMaintenance();
        }@catch(__unused NSException *exception){error=YES;self.cycleFailed=YES;self.failures++;if(self.phaseFailed)self.phaseFailed(name);}
        self.completedPhases++;[self record:name duration:NSProcessInfo.processInfo.systemUptime-start error:error];
        if(!self.foreground || self.generation!=generation)return;
        if(self.nextPhase>=4){self.lastCycleMilliseconds=MAX(0,(NSProcessInfo.processInfo.systemUptime-self.beganAt)*1000);self.state=self.cycleFailed?WPRecoveryStateDegraded:WPRecoveryStateReady;return;}
        [self scheduleNextPhaseAfter:(phase==0?.10:(phase==1?.23:.30))];
    }];self.timer.tolerance=.005;[NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
}
- (void)retry {[self endForeground];[self beginForeground];}
- (NSDictionary<NSString *,id> *)diagnostics {
    NSMutableArray<NSNumber *> *durations=[NSMutableArray new];for(NSDictionary *event in self.events)[durations addObject:event[@"milliseconds"]];
    [durations sortUsingSelector:@selector(compare:)];NSUInteger index=durations.count?(NSUInteger)ceil(durations.count*.95)-1:0;
    return @{@"state":@[@"inactive",@"host-ready",@"warming",@"ready",@"degraded"][self.state],
        @"generation":@(self.generation),@"cycles":@(self.cycles),@"calibrations":@(self.calibrations),
        @"completedPhases":@(self.completedPhases),@"failures":@(self.failures),@"maxPhaseMilliseconds":@(self.maxPhaseMilliseconds),@"phaseP95Milliseconds":durations.count?durations[index]:@0,@"lastCycleMilliseconds":@(self.lastCycleMilliseconds),
        @"pendingCalibration":@(self.calibrationPending),@"pendingStage":@(self.timer.isValid),@"events":self.events.copy};
}
- (void)dealloc {[self.timer invalidate];}
@end
