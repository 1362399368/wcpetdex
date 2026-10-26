#import "WPBarragePreferences.h"
#import "WPCommon.h"
#import "WPComfortPreferences.h"
#import <math.h>

NSString * const WPBarrageClearDockNotification = @"WeChatPet.BarrageClearDock";
NSString * const WPBarragePreviewNotification = @"WeChatPet.BarragePreview";

@interface WPBarrageEnvironment : NSObject
@property(nonatomic) NSTimer *boundaryTimer;
@property(nonatomic) BOOL started;
- (void)scheduleBoundary;
- (void)changed:(NSNotification * _Nullable)note;
@end
static WPBarrageEnvironment *WPBarrageEnvironmentShared(void) {
    static WPBarrageEnvironment *environment;static dispatch_once_t once;
    dispatch_once(&once,^{environment=[WPBarrageEnvironment new];});return environment;
}

static NSUserDefaults *WPBarragePreferences(void) {
    NSUserDefaults *preferences = WPPreferences();
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Registration provides upgrade defaults without replacing saved values.
        [preferences registerDefaults:@{@"barrageEnabled": @NO,
            @"barrageShowsDetails": @YES, @"barrageFullScreen": @NO,
            @"barrageReactionsEnabled": @YES, @"barrageSpeed": @1.0,
            @"barrageBackgroundOpacity": @0.68,@"barrageAdaptiveSaving":@YES,
            @"barrageAllowPrivate":@YES,@"barrageAllowGroup":@YES,
            @"barrageVerticalPosition":@0,@"barrageRegionHeight":@1,
            @"barrageShowsName":@NO,@"barrageNameUsesRemark":@YES,@"barrageCompletionAnimation":@0}];
        // Preserve the existing reminder behavior once, then keep barrage rules independent.
        NSDictionary *legacy=@{@"barrageQuietEnabled":@"quietTimeEnabled",@"barrageQuietStart":@"quietStartMinute",
            @"barrageQuietEnd":@"quietEndMinute",@"barrageContactsOnly":@"reminderContactsOnly",@"barrageContactUsernames":@"reminderContactUsernames"};
        for(NSString *key in legacy)if(![preferences objectForKey:key]){
            id value=[preferences objectForKey:legacy[key]];
            if(value)[preferences setObject:value forKey:key];
        }
    });
    return preferences;
}

static BOOL WPBarrageBoolean(NSString *key, BOOL fallback) {
    id raw = [WPBarragePreferences() objectForKey:key];
    return [raw isKindOfClass:NSNumber.class] && isfinite([raw doubleValue]) ? [raw boolValue] : fallback;
}

static CGFloat WPBarrageFiniteValue(CGFloat value, CGFloat minimum, CGFloat maximum, CGFloat fallback) {
    return isfinite(value) ? MAX(minimum, MIN(maximum, value)) : fallback;
}

static CGFloat WPBarrageNumber(NSString *key, CGFloat minimum, CGFloat maximum, CGFloat fallback) {
    id raw = [WPBarragePreferences() objectForKey:key];
    CGFloat value = [raw isKindOfClass:NSNumber.class] ? [raw doubleValue] : fallback;
    return WPBarrageFiniteValue(value, minimum, maximum, fallback);
}

static void WPBarrageSettingsChanged(void) {
    void (^post)(void) = ^{
        [NSNotificationCenter.defaultCenter postNotificationName:WPSettingsDidChangeNotification object:nil];
        [WPBarrageEnvironmentShared() scheduleBoundary];
    };
    if (NSThread.isMainThread) post();
    else dispatch_async(dispatch_get_main_queue(), post);
}

static void WPBarrageStoreBoolean(NSString *key, BOOL value) {
    [WPBarragePreferences() setBool:value forKey:key];
    WPBarrageSettingsChanged();
}

BOOL WPBarrageEnabled(void) { return WPBarrageBoolean(@"barrageEnabled", NO); }
BOOL WPBarrageShowsDetails(void) { return WPBarrageBoolean(@"barrageShowsDetails", YES); }
BOOL WPBarrageShowsName(void) { return WPBarrageBoolean(@"barrageShowsName", NO); }
BOOL WPBarrageNameUsesRemark(void) { return WPBarrageBoolean(@"barrageNameUsesRemark", YES); }
NSInteger WPBarrageCompletionAnimation(void) { return (NSInteger)WPBarrageNumber(@"barrageCompletionAnimation",0,3,0); }
void WPBarrageSetShowsName(BOOL enabled) { WPBarrageStoreBoolean(@"barrageShowsName",enabled); }
void WPBarrageSetNameUsesRemark(BOOL enabled) { WPBarrageStoreBoolean(@"barrageNameUsesRemark",enabled); }
void WPBarrageSetCompletionAnimation(NSInteger animation) {
    [WPBarragePreferences() setInteger:MAX(0,MIN(3,animation)) forKey:@"barrageCompletionAnimation"];
    WPBarrageSettingsChanged();
}
BOOL WPBarrageFullScreen(void) { return WPBarrageBoolean(@"barrageFullScreen", NO); }
BOOL WPBarrageReactionsEnabled(void) { return WPBarrageBoolean(@"barrageReactionsEnabled", YES); }
CGFloat WPBarrageSpeed(void) { return WPBarrageNumber(@"barrageSpeed", .5, 2, 1); }
CGFloat WPBarrageBackgroundOpacity(void) { return WPBarrageNumber(@"barrageBackgroundOpacity", .35, .85, .68); }

CGFloat WPBarrageVerticalPosition(void) { return WPBarrageNumber(@"barrageVerticalPosition",0,1,0); }
CGFloat WPBarrageRegionHeight(void) { return WPBarrageNumber(@"barrageRegionHeight",.2,1,1); }
CGRect WPBarrageDisplayArea(CGRect safeRect) {
    if(CGRectIsNull(safeRect)||CGRectIsInfinite(safeRect)||!isfinite(safeRect.origin.x)||!isfinite(safeRect.origin.y)||!isfinite(safeRect.size.width)||!isfinite(safeRect.size.height)||safeRect.size.width<=0||safeRect.size.height<=0)return CGRectZero;
    CGFloat baseline=WPBarrageFullScreen()?1:.5;
    // Keep at least one complete capsule and its padding on small screens.
    CGFloat height=MIN(safeRect.size.height,MAX(62,safeRect.size.height*baseline*WPBarrageRegionHeight()));
    return CGRectMake(CGRectGetMinX(safeRect),CGRectGetMinY(safeRect)+(safeRect.size.height-height)*WPBarrageVerticalPosition(),safeRect.size.width,height);
}
void WPBarrageSetVerticalPosition(CGFloat position) {
    [WPBarragePreferences() setDouble:WPBarrageFiniteValue(position,0,1,0) forKey:@"barrageVerticalPosition"];WPBarrageSettingsChanged();
}
void WPBarrageSetRegionHeight(CGFloat fraction) {
    [WPBarragePreferences() setDouble:WPBarrageFiniteValue(fraction,.2,1,1) forKey:@"barrageRegionHeight"];WPBarrageSettingsChanged();
}

void WPBarrageSetEnabled(BOOL enabled) { WPBarrageStoreBoolean(@"barrageEnabled", enabled); }
void WPBarrageSetShowsDetails(BOOL showsDetails) { WPBarrageStoreBoolean(@"barrageShowsDetails", showsDetails); }
void WPBarrageSetFullScreen(BOOL fullScreen) { WPBarrageStoreBoolean(@"barrageFullScreen", fullScreen); }
void WPBarrageSetReactionsEnabled(BOOL enabled) { WPBarrageStoreBoolean(@"barrageReactionsEnabled", enabled); }
void WPBarrageSetSpeed(CGFloat speed) {
    [WPBarragePreferences() setDouble:WPBarrageFiniteValue(speed, .5, 2, 1) forKey:@"barrageSpeed"];
    WPBarrageSettingsChanged();
}
void WPBarrageSetBackgroundOpacity(CGFloat opacity) {
    [WPBarragePreferences() setDouble:WPBarrageFiniteValue(opacity, .35, .85, .68) forKey:@"barrageBackgroundOpacity"];
    WPBarrageSettingsChanged();
}

NSTimeInterval WPBarragePauseRemaining(void) {
    id value=[WPBarragePreferences() objectForKey:@"barragePauseUntil"];
    double end=[value isKindOfClass:NSNumber.class]?[value doubleValue]:0;
    return isfinite(end)?MAX(0,end-NSDate.date.timeIntervalSince1970):0;
}
BOOL WPBarrageIsPaused(void){return WPBarragePauseRemaining()>0;}
void WPBarragePauseForInterval(NSTimeInterval seconds){
    if(!isfinite(seconds))return;
    // A negative interval means an explicit pause until the user resumes it.
    NSTimeInterval end=seconds<0?NSDate.distantFuture.timeIntervalSince1970:NSDate.date.timeIntervalSince1970+MIN(seconds,86400);
    [WPBarragePreferences() setDouble:end forKey:@"barragePauseUntil"];WPBarrageSettingsChanged();
}
void WPBarrageResume(void){[WPBarragePreferences() removeObjectForKey:@"barragePauseUntil"];WPBarrageSettingsChanged();}
BOOL WPBarrageAdaptiveSavingEnabled(void){return WPBarrageBoolean(@"barrageAdaptiveSaving",YES);}
void WPBarrageSetAdaptiveSavingEnabled(BOOL enabled){WPBarrageStoreBoolean(@"barrageAdaptiveSaving",enabled);}
BOOL WPBarrageResourceSavingActive(void){return WPBarrageAdaptiveSavingEnabled() &&
    (NSProcessInfo.processInfo.lowPowerModeEnabled || NSProcessInfo.processInfo.thermalState>=NSProcessInfoThermalStateSerious);}
BOOL WPBarrageQuietTimeEnabled(void){return WPBarrageBoolean(@"barrageQuietEnabled",NO);}
NSInteger WPBarrageQuietMinute(BOOL start){return (NSInteger)WPBarrageNumber(start?@"barrageQuietStart":@"barrageQuietEnd",0,1439,start?1320:480);}
BOOL WPBarrageQuietTimeAtDate(NSDate *date){
    if(!WPBarrageQuietTimeEnabled())return NO;
    NSDateComponents *parts=[NSCalendar.currentCalendar components:NSCalendarUnitHour|NSCalendarUnitMinute fromDate:date];
    NSInteger minute=parts.hour*60+parts.minute,start=WPBarrageQuietMinute(YES),end=WPBarrageQuietMinute(NO);
    return start==end || (start<end?(minute>=start && minute<end):(minute>=start || minute<end));
}
BOOL WPBarrageContactsOnly(void){return WPBarrageBoolean(@"barrageContactsOnly",NO);}
NSArray<NSString *> *WPBarrageContactUsernames(void){
    id raw=[WPBarragePreferences() objectForKey:@"barrageContactUsernames"];
    if(![raw isKindOfClass:NSArray.class]){
        if(![raw isKindOfClass:NSString.class] || [raw length]>30000)return @[];
        raw=[raw componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@",，;； \n\r\t"]];
    }
    NSMutableOrderedSet *names=[NSMutableOrderedSet new];
    for(id name in raw)if([name isKindOfClass:NSString.class] && [name length] && [name length]<=256){
        [names addObject:name];if(names.count>=100)break;
    }
    return names.array;
}
BOOL WPBarrageAllowsPrivateChats(void){return WPBarrageBoolean(@"barrageAllowPrivate",YES);}
BOOL WPBarrageAllowsGroupChats(void){return WPBarrageBoolean(@"barrageAllowGroup",YES);}
BOOL WPBarrageReminderAllowsUsername(NSString *username,NSDate *date){
    if(WPBarrageIsPaused() || WPBarrageQuietTimeAtDate(date) || !username.length)return NO;
    NSString *lower=username.lowercaseString;
    BOOL group=[lower hasSuffix:@"@chatroom"] || [lower hasSuffix:@"@im.chatroom"];
    if(group?!WPBarrageAllowsGroupChats():!WPBarrageAllowsPrivateChats())return NO;
    return !WPBarrageContactsOnly() || [WPBarrageContactUsernames() containsObject:username];
}
void WPBarrageSetReminderValue(NSString *key,id value){
    if([@[@"barrageQuietEnabled",@"barrageContactsOnly",@"barrageAllowPrivate",@"barrageAllowGroup"] containsObject:key]){
        if(![value isKindOfClass:NSNumber.class])return;[WPBarragePreferences() setBool:[value boolValue] forKey:key];
    }else if([@[@"barrageQuietStart",@"barrageQuietEnd"] containsObject:key]){
        if(![value isKindOfClass:NSNumber.class] || !isfinite([value doubleValue]))return;
        [WPBarragePreferences() setInteger:MAX(0,MIN(1439,[value integerValue])) forKey:key];
    }else if([key isEqual:@"barrageContactUsernames"]){
        if(![value isKindOfClass:NSArray.class])return;
        NSMutableOrderedSet *names=[NSMutableOrderedSet new];for(id name in value)
            if([name isKindOfClass:NSString.class] && [name length] && [name length]<=256 && [name rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location==NSNotFound){[names addObject:name];if(names.count>=100)break;}
        [WPBarragePreferences() setObject:names.array forKey:key];
    }else return;
    WPBarrageSettingsChanged();
}

@implementation WPBarrageEnvironment
- (void)changed:(NSNotification *)note{if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{[self changed:note];});return;}WPBarrageSettingsChanged();}
- (void)scheduleBoundary{
    if(!NSThread.isMainThread || !self.started)return;
    [self.boundaryTimer invalidate];self.boundaryTimer=nil;
    if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive || !WPBarrageEnabled())return;
    NSDate *next=nil;NSTimeInterval remaining=WPBarragePauseRemaining();
    if(remaining>0 && remaining<=86401)next=[NSDate dateWithTimeIntervalSinceNow:remaining+.02];
    if(WPBarrageQuietTimeEnabled())for(NSNumber *value in @[@(WPBarrageQuietMinute(YES)),@(WPBarrageQuietMinute(NO))]){
        NSDateComponents *parts=[NSDateComponents new];parts.hour=value.integerValue/60;parts.minute=value.integerValue%60;parts.second=0;
        NSDate *boundary=[NSCalendar.currentCalendar nextDateAfterDate:NSDate.date matchingComponents:parts options:NSCalendarMatchNextTime];
        if(boundary && (!next || [boundary compare:next]==NSOrderedAscending))next=boundary;
    }
    if(!next)return;
    __weak typeof(self) weakSelf=self;
    self.boundaryTimer=[NSTimer timerWithTimeInterval:MAX(.05,next.timeIntervalSinceNow) repeats:NO block:^(__unused NSTimer *timer){[weakSelf changed:nil];}];
    self.boundaryTimer.tolerance=.1;[NSRunLoop.mainRunLoop addTimer:self.boundaryTimer forMode:NSRunLoopCommonModes];
}
@end
void WPBarrageStartEnvironmentMonitor(void){
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{WPBarrageStartEnvironmentMonitor();});return;}
    WPBarrageEnvironment *environment=WPBarrageEnvironmentShared();if(environment.started)return;environment.started=YES;
    for(NSString *name in @[NSProcessInfoPowerStateDidChangeNotification,NSProcessInfoThermalStateDidChangeNotification,
        UIApplicationDidBecomeActiveNotification,UIApplicationWillResignActiveNotification,UIApplicationSignificantTimeChangeNotification,NSSystemTimeZoneDidChangeNotification])
        [NSNotificationCenter.defaultCenter addObserver:environment selector:@selector(changed:) name:name object:nil];
    [environment scheduleBoundary];
}
