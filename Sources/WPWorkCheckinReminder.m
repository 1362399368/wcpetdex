#import "WPWorkCheckinReminder.h"
#import "WPCommon.h"
#import "WPEdition.h"
#import <UIKit/UIKit.h>

static NSString *const WPCheckinSlotKey=@"workCheckinSlot";
static NSString *const WPCheckinAttemptKey=@"workCheckinAttemptedDay";
static NSString *const WPCheckinSentKey=@"workCheckinSentDay";
static NSString *const WPCheckinStatusKey=@"workCheckinLastStatus";

@interface WPWorkCheckinReminder ()
@property(nonatomic,copy) void (^sender)(NSString *,void (^)(BOOL,NSString *));
@property(nonatomic) NSTimer *timer;
@property(nonatomic) BOOL foreground;
@property(nonatomic) BOOL sending;
@end

@implementation WPWorkCheckinReminder
+ (instancetype)sharedReminder {static id value;static dispatch_once_t once;dispatch_once(&once,^{value=[self new];});return value;}
+ (NSString *)defaultMessage {return @"宝宝，记得上班打卡呀～先把卡打了再安心开工。今天也要顺顺利利的，爱你 ❤️";}
+ (BOOL)isEnabled {
    id saved=[WPPreferences() objectForKey:@"workCheckinEnabled"];
    return saved?[saved boolValue]:YES;
}
+ (BOOL)isWithinSendWindowAtDate:(NSDate *)date {
    NSCalendar *calendar=[[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    calendar.timeZone=[NSTimeZone timeZoneWithName:@"Asia/Shanghai"];
    NSInteger weekday=[calendar component:NSCalendarUnitWeekday fromDate:date];
    if(weekday==1 || weekday==7)return NO;
    NSDate *start=[calendar dateBySettingHour:8 minute:50 second:0 ofDate:date options:0];
    return [date compare:start]!=NSOrderedAscending && [date compare:[start dateByAddingTimeInterval:300]]==NSOrderedAscending;
}
- (NSCalendar *)chinaCalendar {
    NSCalendar *calendar=[[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    calendar.timeZone=[NSTimeZone timeZoneWithName:@"Asia/Shanghai"];
    return calendar;
}
- (NSString *)dayKey:(NSDate *)date calendar:(NSCalendar *)calendar {
    NSDateComponents *parts=[calendar components:NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay fromDate:date];
    return [NSString stringWithFormat:@"%04ld-%02ld-%02ld",(long)parts.year,(long)parts.month,(long)parts.day];
}
- (NSDate *)windowStart:(NSDate *)date calendar:(NSCalendar *)calendar {
    return [calendar dateBySettingHour:8 minute:50 second:0 ofDate:date options:0];
}
- (NSUInteger)secondForDay:(NSString *)day {
    NSDictionary *slot=[WPPreferences() dictionaryForKey:WPCheckinSlotKey];
    NSNumber *second=[slot[@"second"] isKindOfClass:NSNumber.class]?slot[@"second"]:nil;
    if([slot[@"day"] isEqual:day] && second && second.integerValue>=0 && second.integerValue<290)return second.unsignedIntegerValue;
    NSUInteger chosen=arc4random_uniform(290);
    [WPPreferences() setObject:@{@"day":day,@"second":@(chosen)} forKey:WPCheckinSlotKey];
    return chosen;
}
- (void)startWithSender:(void (^)(NSString *,void (^)(BOOL,NSString *)))sender {
    NSAssert(NSThread.isMainThread,@"Start reminder on the main queue");
    if(WP_EDITION_ARIA || self.sender)return;
    self.sender=[sender copy];
    NSNotificationCenter *center=NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(scheduleChanged:) name:WPSettingsDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(scheduleChanged:) name:UIApplicationSignificantTimeChangeNotification object:nil];
    self.foreground=UIApplication.sharedApplication.applicationState==UIApplicationStateActive;
    [self reschedule];
}
- (void)setForegroundAvailable:(BOOL)available {
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{[self setForegroundAvailable:available];});return;}
    self.foreground=available;[self reschedule];
}
- (void)scheduleChanged:(NSNotification *)note {
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{[self scheduleChanged:note];});return;}
    [self reschedule];
}
- (void)wake:(NSTimer *)timer {self.timer=nil;[self reschedule];}
- (void)armFor:(NSDate *)date {
    NSTimeInterval delay=MAX(.05,[date timeIntervalSinceNow]);
    self.timer=[NSTimer timerWithTimeInterval:delay target:self selector:@selector(wake:) userInfo:nil repeats:NO];
    self.timer.tolerance=MIN(.1,delay/10);
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
}
- (void)reschedule {
    [self.timer invalidate];self.timer=nil;
    if(!self.sender || !self.foreground || self.sending || ![self.class isEnabled])return;
    NSCalendar *calendar=[self chinaCalendar];NSDate *now=NSDate.date;
    for(NSInteger offset=0;offset<8;offset++){
        NSDate *day=[calendar dateByAddingUnit:NSCalendarUnitDay value:offset toDate:now options:0];
        NSInteger weekday=[calendar component:NSCalendarUnitWeekday fromDate:day];
        if(weekday==1 || weekday==7)continue;
        NSString *key=[self dayKey:day calendar:calendar];
        if([[WPPreferences() stringForKey:WPCheckinAttemptKey] isEqual:key])continue;
        NSDate *start=[self windowStart:day calendar:calendar];
        NSDate *end=[start dateByAddingTimeInterval:300];
        if([now compare:end]!=NSOrderedAscending)continue;
        NSDate *chosen=[start dateByAddingTimeInterval:[self secondForDay:key]];
        if([now compare:chosen]==NSOrderedAscending){[self armFor:chosen];return;}
        if(offset==0){[self sendForDay:key];return;}
    }
}
- (void)sendForDay:(NSString *)day {
    if(self.sending || !self.foreground)return;
    NSString *text=[WPPreferences() stringForKey:@"workCheckinMessage"];
    if(!text.length || text.length>500)text=[WPWorkCheckinReminder defaultMessage];
    self.sending=YES;
    // Persist before opening a chat. A process crash during WeChat's native
    // send path must not automatically create a second copy on restart.
    [WPPreferences() setObject:day forKey:WPCheckinAttemptKey];
    __weak typeof(self) weakSelf=self;
    self.sender(text,^(BOOL invoked,NSString *status){
        dispatch_async(dispatch_get_main_queue(),^{
            WPWorkCheckinReminder *self=weakSelf;if(!self)return;
            self.sending=NO;
            [WPPreferences() setObject:status?:@"发送状态未知" forKey:WPCheckinStatusKey];
            if(invoked)[WPPreferences() setObject:day forKey:WPCheckinSentKey];
            else if([[WPPreferences() stringForKey:WPCheckinAttemptKey] isEqual:day]){
                [WPPreferences() removeObjectForKey:WPCheckinAttemptKey];
                NSCalendar *calendar=[self chinaCalendar];NSDate *end=[[self windowStart:NSDate.date calendar:calendar] dateByAddingTimeInterval:300];
                if([NSDate.date compare:end]==NSOrderedAscending){[self armFor:[NSDate dateWithTimeIntervalSinceNow:20]];return;}
            }
            [self reschedule];
        });
    });
}
- (void)dealloc {[self.timer invalidate];[NSNotificationCenter.defaultCenter removeObserver:self];}
@end
