#import "WPComfortPreferences.h"
#import "WPCommon.h"
#import <math.h>

BOOL WPPositionLocked(void) { return [WPPreferences() boolForKey:@"positionLocked"]; }
BOOL WPAllowUnreadPeek(void) { return [WPPreferences() boolForKey:@"allowUnreadPeek"]; }
static NSString *WPAnchorKey(CGSize bounds, BOOL horizontal) {
    return [NSString stringWithFormat:@"position%@%@",bounds.width>bounds.height?@"Landscape":@"Portrait",horizontal?@"X":@"Y"];
}
static CGFloat WPAnchorCoordinate(NSString *key, CGFloat fallback) {
    id value=[WPPreferences() objectForKey:key];
    double number=[value isKindOfClass:NSNumber.class]?[value doubleValue]:NAN;
    return isfinite(number) && number>0 && number<1?number:fallback;
}
CGPoint WPPositionAnchorForBounds(CGSize bounds) {
    CGFloat defaultX=bounds.width>0?MAX(.1,MIN(.9,(bounds.width-54)/bounds.width)):.85;
    CGFloat x=WPAnchorCoordinate(@"positionX",defaultX),y=WPAnchorCoordinate(@"positionY",.66);
    return CGPointMake(WPAnchorCoordinate(WPAnchorKey(bounds,YES),x),WPAnchorCoordinate(WPAnchorKey(bounds,NO),y));
}
void WPStorePositionAnchor(CGPoint anchor, CGSize bounds) {
    if(!isfinite(anchor.x)||!isfinite(anchor.y)||bounds.width<=0||bounds.height<=0)return;
    [WPPreferences() setDouble:MAX(.001,MIN(.999,anchor.x)) forKey:WPAnchorKey(bounds,YES)];
    [WPPreferences() setDouble:MAX(.001,MIN(.999,anchor.y)) forKey:WPAnchorKey(bounds,NO)];
}
void WPResetPositionAnchors(void) {
    for(NSString *key in @[@"positionX",@"positionY",@"positionPortraitX",@"positionPortraitY",@"positionLandscapeX",@"positionLandscapeY"])[WPPreferences() removeObjectForKey:key];
}
WPReminderIntensity WPConfiguredReminderIntensity(void) {
    id value=[WPPreferences() objectForKey:@"reminderIntensity"];
    if(![value isKindOfClass:NSNumber.class])return WPReminderIntensityFull;
    NSInteger index=[value integerValue];
    return index>=WPReminderIntensityAvatarOnly&&index<=WPReminderIntensityFull?(WPReminderIntensity)index:WPReminderIntensityFull;
}
NSInteger WPQuietMinute(BOOL start) {
    id value=[WPPreferences() objectForKey:start?@"quietStartMinute":@"quietEndMinute"];
    NSInteger fallback=start?22*60:8*60;
    if(![value isKindOfClass:NSNumber.class])return fallback;
    double number=[value doubleValue];
    return isfinite(number)&&number>=0&&number<1440?(NSInteger)number:fallback;
}
BOOL WPQuietTimeAtDate(NSDate *date) {
    if(![WPPreferences() boolForKey:@"quietTimeEnabled"])return NO;
    NSDateComponents *parts=[NSCalendar.currentCalendar components:NSCalendarUnitHour|NSCalendarUnitMinute fromDate:date];
    NSInteger minute=parts.hour*60+parts.minute,start=WPQuietMinute(YES),end=WPQuietMinute(NO);
    if(start==end)return YES;
    return start<end?(minute>=start&&minute<end):(minute>=start||minute<end);
}
NSArray<NSString *> *WPReminderContactUsernames(void) {
    id raw=[WPPreferences() objectForKey:@"reminderContactUsernames"];
    if(![raw isKindOfClass:NSString.class])return @[];
    NSMutableOrderedSet *result=[NSMutableOrderedSet new];
    NSCharacterSet *separators=[NSCharacterSet characterSetWithCharactersInString:@",，;； \n\r\t"];
    for(NSString *entry in [raw componentsSeparatedByCharactersInSet:separators]){
        if(entry.length>0 && entry.length<=256)[result addObject:entry];
        if(result.count>=100)break;
    }
    return result.array;
}
BOOL WPReminderAllowsUsername(NSString *username, NSDate *date) {
    if(WPQuietTimeAtDate(date))return NO;
    if(![WPPreferences() boolForKey:@"reminderContactsOnly"])return YES;
    return username.length>0 && [WPReminderContactUsernames() containsObject:username];
}
