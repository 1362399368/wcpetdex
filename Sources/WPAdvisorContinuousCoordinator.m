#import "WPAdvisorContinuousCoordinator.h"
#import "WPCommon.h"
#import "WPMessageBarrageSource.h"
#import "WPAdvisorTaskCenter.h"
#import <UIKit/UIKit.h>
#import <math.h>

static const NSUInteger WPContinuousMaximumContacts=8;
static BOOL WPContinuousValidUsername(id object){
    if(![object isKindOfClass:NSString.class])return NO;
    NSString *s=object;NSString *lower=s.lowercaseString;
    return s.length>0 && s.length<=256 && ![lower hasSuffix:@"chatroom"] && ![lower hasPrefix:@"gh_"] && [s rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location==NSNotFound;
}
@interface WPContinuousBatch : NSObject
@property(nonatomic) NSTimeInterval firstArrival;
@property(nonatomic) NSTimeInterval lastArrival;
@property(nonatomic) NSUInteger timerGeneration;
@property(nonatomic,strong) NSMutableOrderedSet<NSString *> *seen;
@property(nonatomic,strong) NSTimer *timer;
@end
@implementation WPContinuousBatch
- (instancetype)init{if((self=[super init]))_seen=[NSMutableOrderedSet new];return self;}
@end
@interface WPAdvisorContinuousCoordinator ()
@property(nonatomic,copy) NSString *lockedUsername;
@property(atomic,copy) NSSet<NSString *> *enabledSnapshot;
@property(atomic,copy) NSDictionary<NSString *,NSNumber *> *enabledSinceSnapshot;
@property(atomic) BOOL hookForeground;
@property(atomic) NSTimeInterval foregroundSince;
@property(nonatomic,strong) NSMutableDictionary<NSString *,WPContinuousBatch *> *batches;
@property(nonatomic,strong) NSLock *captureLock;
@property(nonatomic,copy) NSString *accountFingerprint;
@property(atomic,readwrite,copy) NSString *accountToken;
@end
@implementation WPAdvisorContinuousCoordinator
+ (instancetype)sharedCoordinator {static WPAdvisorContinuousCoordinator *value;static dispatch_once_t once;dispatch_once(&once,^{value=[self new];});return value;}
- (instancetype)init {
    if(!(self=[super init]))return nil;
    _batches=[NSMutableDictionary new];_captureLock=[NSLock new];_lockedUsername=@"";_enabledSnapshot=[NSSet set];_enabledSinceSnapshot=@{};
    _foregroundAvailable=UIApplication.sharedApplication.applicationState==UIApplicationStateActive;_hookForeground=_foregroundAvailable;_foregroundSince=NSDate.date.timeIntervalSince1970;
    NSNotificationCenter *center=NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(active:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [center addObserver:self selector:@selector(inactive:) name:UIApplicationWillResignActiveNotification object:nil];
    [self refreshAccountIfNeeded];
    return self;
}
- (void)dealloc {[NSNotificationCenter.defaultCenter removeObserver:self];}
- (NSArray<NSString *> *)enabledUsernames{return [[self.enabledSnapshot allObjects] sortedArrayUsingSelector:@selector(localizedStandardCompare:)];}
- (BOOL)hasEnabledContacts{return self.enabledSnapshot.count>0;}
- (BOOL)acceptsNativeMessages{return self.hookForeground && self.hasEnabledContacts;}
- (BOOL)isEnabled{return [self isEnabledForUsername:self.lockedUsername];}
- (BOOL)isEnabledForUsername:(NSString *)username{return username.length && [self.enabledSnapshot containsObject:username];}
- (NSString *)accountKey:(NSString *)suffix {return self.accountFingerprint.length?[NSString stringWithFormat:@"advisor.continuous.%@.%@",self.accountFingerprint,suffix]:nil;}
- (void)refreshAccountIfNeeded {
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{[self refreshAccountIfNeeded];});return;}
    NSString *account=WPAdvisorCurrentAccountFingerprint()?:@"";
    if([self.accountFingerprint isEqualToString:account])return;
    for(WPContinuousBatch *batch in self.batches.allValues){batch.timerGeneration++;[batch.timer invalidate];batch.timer=nil;}
    [self.batches removeAllObjects];_accountFingerprint=[account copy];_lockedUsername=@"";
    NSMutableSet *enabled=[NSMutableSet new];
    if(account.length){
        id selected=[WPPreferences() objectForKey:[self accountKey:@"selected"]];if(WPContinuousValidUsername(selected))_lockedUsername=[selected copy];
        id list=[WPPreferences() objectForKey:[self accountKey:@"usernames"]];
        if([list isKindOfClass:NSArray.class])for(id item in list)if(WPContinuousValidUsername(item) && enabled.count<WPContinuousMaximumContacts)[enabled addObject:item];
    }
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;NSMutableDictionary *since=[NSMutableDictionary new];for(NSString *username in enabled)since[username]=@(now);
    [self.captureLock lock];self.accountToken=account;self.enabledSnapshot=[enabled copy];self.enabledSinceSnapshot=[since copy];[self.captureLock unlock];
    if(enabled.count)dispatch_async(dispatch_get_main_queue(),^{[[WPMessageBarrageSource sharedSource] ensureContinuousReceiveHook];});
}
- (BOOL)isFreshIncomingTimestamp:(NSTimeInterval)timestamp forUsername:(NSString *)username {
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;
    NSNumber *enabledSince=self.enabledSinceSnapshot[username];
    return enabledSince && isfinite(timestamp) && timestamp>0 && timestamp>=MAX(self.foregroundSince,enabledSince.doubleValue)-1 && timestamp<=now+2 && now-timestamp<=15;
}
- (void)withNativeCaptureForUsername:(NSString *)username perform:(dispatch_block_t)capture {
    if(!capture || !username.length)return;
    [self.captureLock lock];
    @try{if(self.hookForeground && [self.enabledSnapshot containsObject:username])capture();}
    @finally{[self.captureLock unlock];}
}
- (void)active:(NSNotification *)note {[self refreshAccountIfNeeded];self.foregroundAvailable=YES;if(self.hasEnabledContacts)[[WPMessageBarrageSource sharedSource] ensureContinuousReceiveHook];}
- (void)inactive:(NSNotification *)note {self.foregroundAvailable=NO;}
- (void)setForegroundAvailable:(BOOL)available {
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{self.foregroundAvailable=available;});return;}
    BOOL resumed=available && !_foregroundAvailable;
    _foregroundAvailable=available;[self.captureLock lock];self.hookForeground=available;if(resumed)self.foregroundSince=NSDate.date.timeIntervalSince1970;[self.captureLock unlock];
    for(WPContinuousBatch *batch in self.batches.allValues){batch.timerGeneration++;[batch.timer invalidate];batch.timer=nil;}
    if(available)[self retryPending];
}
- (void)setLockedUsername:(NSString *)username {
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{[self setLockedUsername:username];});return;}
    [self refreshAccountIfNeeded];if(!self.accountFingerprint.length)return;
    NSString *value=[username isKindOfClass:NSString.class]?[username stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]:@"";
    if(!WPContinuousValidUsername(value))value=@"";
    if(!value.length && _lockedUsername.length){[self setEnabled:NO];}
    _lockedUsername=[value copy];
    if(value.length)[WPPreferences() setObject:value forKey:[self accountKey:@"selected"]];else [WPPreferences() removeObjectForKey:[self accountKey:@"selected"]];
    [NSNotificationCenter.defaultCenter postNotificationName:WPSettingsDidChangeNotification object:nil];
}
- (void)setEnabled:(BOOL)enabled {
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{[self setEnabled:enabled];});return;}
    [self refreshAccountIfNeeded];if(!self.accountFingerprint.length)return;
    NSString *username=self.lockedUsername;if(!username.length)return;
    NSMutableSet *selected=[self.enabledSnapshot mutableCopy];NSMutableDictionary *since=[self.enabledSinceSnapshot mutableCopy];
    if(enabled && (selected.count<WPContinuousMaximumContacts || [selected containsObject:username])){if(![selected containsObject:username])since[username]=@(NSDate.date.timeIntervalSince1970);[selected addObject:username];}
    else if(!enabled){[selected removeObject:username];[since removeObjectForKey:username];WPContinuousBatch *batch=self.batches[username];batch.timerGeneration++;[batch.timer invalidate];batch.timer=nil;[self.batches removeObjectForKey:username];}
    [self.captureLock lock];self.enabledSnapshot=[selected copy];self.enabledSinceSnapshot=[since copy];[self.captureLock unlock];[WPPreferences() setObject:self.enabledUsernames forKey:[self accountKey:@"usernames"]];
    if(selected.count)[[WPMessageBarrageSource sharedSource] ensureContinuousReceiveHook];
    [NSNotificationCenter.defaultCenter postNotificationName:WPSettingsDidChangeNotification object:nil];
}
- (void)noteIncomingUsername:(NSString *)username identifier:(NSString *)identifier createdAt:(NSTimeInterval)createdAt text:(NSString *)text {
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{[self noteIncomingUsername:username identifier:identifier createdAt:createdAt text:text];});return;}
    [self refreshAccountIfNeeded];
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;
    if(![self isEnabledForUsername:username] || !self.foregroundAvailable || !identifier.length || identifier.length>512 || ![self isFreshIncomingTimestamp:createdAt forUsername:username])return;
    WPContinuousBatch *batch=self.batches[username];if(!batch){batch=[WPContinuousBatch new];self.batches[username]=batch;}
    if([batch.seen containsObject:identifier])return;
    [batch.seen addObject:identifier];if(batch.seen.count>128)[batch.seen removeObjectAtIndex:0];
    if(!batch.firstArrival)batch.firstArrival=now;batch.lastArrival=now;
    if(self.onMessage)self.onMessage(username,identifier,createdAt,text?:@"");
    if(self.onIncoming)self.onIncoming(username);
    [self scheduleUsername:username];
}
- (void)scheduleUsername:(NSString *)username {
    WPContinuousBatch *batch=self.batches[username];NSUInteger generation=++batch.timerGeneration;[batch.timer invalidate];batch.timer=nil;
    if(![self isEnabledForUsername:username] || !self.foregroundAvailable || !batch.firstArrival)return;
    NSTimeInterval now=NSDate.date.timeIntervalSince1970,due=MIN(batch.lastArrival+30,batch.firstArrival+90),delay=MAX(0,due-now);
    __weak typeof(self) weakSelf=self;
    NSTimer *timer=[NSTimer timerWithTimeInterval:MAX(.001,delay) repeats:NO block:^(__unused NSTimer *timer){
        typeof(self) self=weakSelf;WPContinuousBatch *current=self.batches[username];
        if(!self || current!=batch || current.timerGeneration!=generation || ![self isEnabledForUsername:username] || !self.foregroundAvailable || !current.firstArrival)return;
        current.timer=nil;[self refreshAccountIfNeeded];if(self.batches[username]!=current)return;
        if(self.isBusy && self.isBusy(username))return;
        NSTimeInterval first=current.firstArrival,last=current.lastArrival;current.firstArrival=0;current.lastArrival=0;current.timerGeneration++;
        if(!self.onReady || !self.onReady(username)){if(!current.firstArrival){current.firstArrival=first;current.lastArrival=last;}return;}
    }];timer.tolerance=MIN(1,delay*.1);batch.timer=timer;[NSRunLoop.mainRunLoop addTimer:timer forMode:NSRunLoopCommonModes];
}
- (void)taskDidFinishForUsername:(NSString *)username {if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{[self taskDidFinishForUsername:username];});return;}if(self.batches[username].firstArrival)[self scheduleUsername:username];}
- (void)retryPending {if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{[self retryPending];});return;}for(NSString *username in self.batches.allKeys)if(self.batches[username].firstArrival)[self scheduleUsername:username];}
@end
