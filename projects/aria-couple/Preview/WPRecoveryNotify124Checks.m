#import "WPRecoveryNotify124Checks.h"
#import "WPQuickChat.h"
#import "WPCommon.h"
#import <objc/runtime.h>
@interface WPQuickChatMonitor (WPRecoveryNotify124)
- (void)performTick;
- (void)schedulePoll;
@end
@interface WPNotify124Source : NSObject
@property(nonatomic,readonly) NSString *route;
@property(nonatomic,readonly) NSUInteger count,lastReadEnd;
@property(nonatomic,readonly) BOOL nativeOrder;
@property(nonatomic,readonly) NSSet *homeNames,*lastReadUsernames;
@property(nonatomic,readonly) NSDictionary *lastReadRanks;
- (NSArray *)sessionsInRange:(NSRange)range;
- (id)objectAtIndex:(NSUInteger)index;
@end
@implementation WPNotify124Source
- (NSString *)route{return @"recovery-fixture";}
- (NSUInteger)count{return 1;}
- (NSUInteger)lastReadEnd{return 1;}
- (BOOL)nativeOrder{return YES;}
- (NSSet *)homeNames{return [NSSet setWithObject:@"recovery_fixture"];}
- (NSSet *)lastReadUsernames{return self.homeNames;}
- (NSDictionary *)lastReadRanks{return @{@"recovery_fixture":@0};}
- (id)objectAtIndex:(NSUInteger)index{return index?nil:[self sessionsInRange:NSMakeRange(0,1)].firstObject;}
- (NSArray *)sessionsInRange:(NSRange)range {return range.location?@[]:@[[WPQuickChatSession sessionWithUsername:@"recovery_fixture" unread:1 muted:NO pinned:NO time:NSDate.date.timeIntervalSince1970]];}
@end
void WPRecoveryNotify124RunPreviewChecks(void (^completion)(NSDictionary<NSString *,NSNumber *> *)){
    NSCAssert(NSThread.isMainThread,@"Recovery fixture starts on main");
    WPQuickChatMonitor *monitor=WPQuickChatMonitor.sharedMonitor;
    BOOL wasActive=[[monitor valueForKey:@"active"] boolValue],wasForeground=[[monitor valueForKey:@"foregroundAvailable"] boolValue];
    NSArray *fields=@[@"tracker",@"observedUnread",@"observedRanks",@"latestObservedUnreadUsername",@"latestArrivalUsername",@"latestPublishedUnreadTime",@"latestPublishedUnreadCount",@"state"];
    NSMutableDictionary *saved=[NSMutableDictionary new];for(NSString *key in fields){id value=[monitor valueForKey:key];saved[key]=[value conformsToProtocol:@protocol(NSCopying)]?[value copy]:(value?:NSNull.null);}
    NSArray *keys=@[@"barrageEnabled",@"unreadAvatarEnabled",@"quickChatEnabled"];
    NSMutableDictionary *preferences=[NSMutableDictionary new];for(NSString *key in keys)preferences[key]=[WPPreferences() objectForKey:key]?:NSNull.null;
    NSMutableDictionary *checks=[NSMutableDictionary new];
    [monitor setActive:NO];WPQuickChatSetForegroundAvailable(YES);
    [WPPreferences() setBool:NO forKey:@"barrageEnabled"];[WPPreferences() setBool:YES forKey:@"unreadAvatarEnabled"];[WPPreferences() setBool:NO forKey:@"quickChatEnabled"];
    [monitor setActive:YES];checks[@"RN124InitialTickDefersNativeWork"]=@([[monitor valueForKey:@"initialTickPending"] boolValue]);
    NSUInteger before=[monitor.diagnostics[@"nativeRefreshGate"][@"submitted"] unsignedIntegerValue];
    dispatch_apply(1000,dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^(__unused size_t i){WPQuickChatNotifyNativeMessage();});
    NSDictionary *burst=monitor.diagnostics[@"nativeRefreshGate"];
    checks[@"RN124ThousandNativeSignalsQueueAtMostOneMainRefresh"]=@([burst[@"pending"] unsignedIntegerValue]==1 && [burst[@"submitted"] unsignedIntegerValue]<=before+1);
    NSUInteger delivered=[burst[@"delivered"] unsignedIntegerValue];
    id oldSignal=[monitor valueForKey:@"lastNativeSignal"];[WPPreferences() setBool:YES forKey:@"barrageEnabled"];[monitor setValue:@(NSProcessInfo.processInfo.systemUptime) forKey:@"lastNativeSignal"];[monitor schedulePoll];
    checks[@"RN125NativeCallbackCannotDisableFastBarrageSafetyPoll"]=@([monitor.diagnostics[@"pollInterval"] doubleValue]==2);
    [WPPreferences() setBool:NO forKey:@"barrageEnabled"];[monitor setValue:oldSignal forKey:@"lastNativeSignal"];
    WPQuickChatSetForegroundAvailable(NO);
    NSUInteger suspendedGeneration=[monitor.diagnostics[@"activationGeneration"] unsignedIntegerValue];
    WPQuickChatSetForegroundAvailable(NO);
    checks[@"RN124ForegroundTransitionIsFiniteAndIdempotent"]=@(![[monitor valueForKey:@"foregroundAvailable"] boolValue] && [monitor.diagnostics[@"activationGeneration"] unsignedIntegerValue]==suspendedGeneration);
    NSUInteger rejected=[monitor.diagnostics[@"nativeRefreshGate"][@"rejected"] unsignedIntegerValue];
    dispatch_apply(150,dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^(__unused size_t i){WPQuickChatNotifyNativeMessage();});
    checks[@"RN124Background150NotificationsRejectedBeforeMainQueue"]=@([monitor.diagnostics[@"nativeRefreshGate"][@"rejected"] unsignedIntegerValue]>=rejected+150);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,250*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        checks[@"RN124OldGenerationDoesNotDeliverAfterSuspend"]=@([monitor.diagnostics[@"nativeRefreshGate"][@"delivered"] unsignedIntegerValue]==delivered);
        WPQuickChatSetForegroundAvailable(YES);WPQuickChatNotifyNativeMessage();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,350*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
            checks[@"RN124UnreadOnlyModeStillAcceptsNativeRefresh"]=@([monitor.diagnostics[@"nativeRefreshGate"][@"delivered"] unsignedIntegerValue]>delivered && ![[monitor valueForKey:@"initialTickPending"] boolValue]);
            Class source=NSClassFromString(@"WPQuickChatSource");Method method=class_getClassMethod(source,NSSelectorFromString(@"current"));
            if(method){
                IMP original=method_getImplementation(method);IMP unavailable=imp_implementationWithBlock(^id(__unused id cls){return nil;});
                [monitor setValue:[@{@"recovery_fixture":[WPQuickChatSession sessionWithUsername:@"recovery_fixture" unread:1 muted:NO pinned:NO time:1]} mutableCopy] forKey:@"observedUnread"];
                method_setImplementation(method,unavailable);[monitor performTick];
                checks[@"RN124UnavailableServiceKeepsUnreadSnapshot"]=@(monitor.hasAlertableUnread && [monitor.diagnostics[@"state"] isEqual:@"waiting-for-session-service"]);
                WPNotify124Source *fixture=[WPNotify124Source new];IMP available=imp_implementationWithBlock(^id(__unused id cls){return fixture;});
                method_setImplementation(method,available);[monitor performTick];
                checks[@"RN124ServiceCanRecoverWithinSameActivation"]=@(monitor.hasAlertableUnread && [monitor.latestObservedUnreadUsername isEqual:@"recovery_fixture"] && [monitor.diagnostics[@"state"] isEqual:@"active"]);
                method_setImplementation(method,original);imp_removeBlock(unavailable);imp_removeBlock(available);
            }else checks[@"RN124SourceFixtureAvailable"]=@NO;
            [monitor setActive:NO];WPQuickChatSetForegroundAvailable(wasForeground);if(wasActive)[monitor setActive:YES];
            for(NSString *key in fields){id value=saved[key];if(value==NSNull.null)value=nil;if([key isEqual:@"observedUnread"]||[key isEqual:@"observedRanks"]||[key isEqual:@"state"])value=[value mutableCopy];[monitor setValue:value forKey:key];}
            for(NSString *key in keys){id value=preferences[key];if(value==NSNull.null)[WPPreferences() removeObjectForKey:key];else [WPPreferences() setObject:value forKey:key];}
            completion(checks);
        });
    });
}
