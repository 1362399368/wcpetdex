#import "WPRecovery124Checks.h"
#import "WPRecoveryCoordinator.h"

@interface WPRecovery124Run : NSObject
@property(nonatomic) NSMutableDictionary<NSString *,NSNumber *> *checks;
@property(nonatomic,copy) void (^completion)(NSDictionary *);
@property(nonatomic) WPRecoveryCoordinator *coordinator;
@property(nonatomic) NSMutableArray<NSString *> *phases;
@property(nonatomic) BOOL hostAvailable;
@property(nonatomic) NSUInteger capturedGeneration;
@end
@implementation WPRecovery124Run
- (void)start {
    self.checks=[NSMutableDictionary new];self.phases=[NSMutableArray new];self.hostAvailable=YES;
    self.coordinator=[WPRecoveryCoordinator new];__weak typeof(self) weakSelf=self;
    self.coordinator.calibrateHost=^BOOL{return weakSelf.hostAvailable;};
    self.coordinator.captureMessages=^{[weakSelf.phases addObject:@"capture"];};
    self.coordinator.restoreRenderer=^{[weakSelf.phases addObject:@"renderer"];};
    self.coordinator.restoreMonitoring=^{[weakSelf.phases addObject:@"monitor"];};
    self.coordinator.restoreMaintenance=^{[weakSelf.phases addObject:@"maintenance"];};
    for(NSUInteger n=0;n<20;n++){[self.coordinator beginForeground];[self.coordinator endForeground];}
    [self.coordinator beginForeground];self.capturedGeneration=self.coordinator.generation;
    for(NSUInteger n=0;n<1000;n++)[self.coordinator requestCalibration];
    NSDictionary *pending=self.coordinator.diagnostics;
    self.checks[@"R124RepeatedWindowsKeepOnePendingCalibration"]=@([pending[@"pendingCalibration"] boolValue] && ![pending[@"pendingStage"] boolValue]);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,45*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        [self.coordinator setTemporarilySuspended:YES];NSUInteger count=self.phases.count;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,160*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
            self.checks[@"R124TemporaryInterruptionPausesWithoutGenerationReset"]=@(self.phases.count==count && self.coordinator.generation==self.capturedGeneration);
            [self.coordinator setTemporarilySuspended:NO];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,850*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[self firstCycleFinished];});
        });
    });
}
- (void)firstCycleFinished {
    self.checks[@"R124TwentyCancelledCyclesNeverCommitStaleStages"]=@([self.phases isEqual:@[@"capture",@"renderer",@"monitor",@"maintenance"]]);
    self.checks[@"R124HostThenStagedRecoveryReachesReady"]=@(self.coordinator.state==WPRecoveryStateReady);
    NSUInteger finished=self.phases.count;
    for(NSUInteger n=0;n<1000;n++){[self.coordinator beginForeground];[self.coordinator requestCalibration];}
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,40*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        self.checks[@"R124ReadyWindowStormDoesNotRestartHeavyRecovery"]=@(self.phases.count==finished && self.coordinator.generation==self.capturedGeneration);
        [self.coordinator endForeground];[self.phases removeAllObjects];self.hostAvailable=NO;
        [self.coordinator beginForeground];NSUInteger generation=self.coordinator.generation;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,220*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
            self.checks[@"R124MissingHostDoesNotStartNativeServices"]=@(self.phases.count==0);
            self.hostAvailable=YES;[self.coordinator requestCalibration];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,800*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
                self.checks[@"R124HostBecomingAvailableRecoversWithinSameGeneration"]=@(self.coordinator.state==WPRecoveryStateReady && self.coordinator.generation==generation && self.phases.count==4);
                [self failureCycle];
            });
        });
    });
}
- (void)failureCycle {
    [self.coordinator endForeground];[self.phases removeAllObjects];
    self.coordinator.restoreMonitoring=^{[NSException raise:@"NativeFixtureUnavailable" format:@"test-only"];};
    [self.coordinator beginForeground];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,800*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        self.checks[@"R124OneUnavailableFeatureDoesNotBlockOtherStages"]=@([self.phases containsObject:@"maintenance"] && self.coordinator.state==WPRecoveryStateDegraded);
        NSDictionary *report=self.coordinator.diagnostics;
        self.checks[@"R124RecoveryDiagnosticsAreBoundedAndContainTiming"]=@([report[@"events"] count]<=32 && report[@"phaseP95Milliseconds"] && report[@"maxPhaseMilliseconds"] && report[@"lastCycleMilliseconds"]);
        [self.coordinator endForeground];[self.phases removeAllObjects];__weak typeof(self) weakSelf=self;
        self.coordinator.restoreMonitoring=^{[weakSelf.phases addObject:@"monitor"];};
        [self.coordinator beginForeground];[self.coordinator endForeground];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,800*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
            self.checks[@"R124BackgroundImmediatelyCancelsDeferredNativeWork"]=@(self.phases.count==0 && self.coordinator.state==WPRecoveryStateInactive && ![self.coordinator.diagnostics[@"pendingStage"] boolValue]);
            if(self.completion)self.completion(self.checks.copy);self.completion=nil;
        });
    });
}
@end
void WPRecovery124RunPreviewChecks(void (^completion)(NSDictionary<NSString *,NSNumber *> *checks)){
    WPRecovery124Run *run=[WPRecovery124Run new];run.completion=completion;[run start];
}
