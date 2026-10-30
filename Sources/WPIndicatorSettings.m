#import "WPIndicatorSettings.h"
#import "WPCommon.h"
#import <math.h>

static CGFloat WPIndicatorCoordinate(NSString *key,CGFloat limit) {
    id value=[WPPreferences() objectForKey:key];
    if(![value isKindOfClass:NSNumber.class])return 0;
    double number=[value doubleValue];
    return isfinite(number)?MAX(-limit,MIN(limit,number)):0;
}
BOOL WPUnreadAvatarEnabled(void) {
    id value=[WPPreferences() objectForKey:@"unreadAvatarEnabled"];
    return [value isKindOfClass:NSNumber.class]?[value boolValue]:YES;
}
CGPoint WPUnreadAvatarOffset(void) {
    return CGPointMake(WPIndicatorCoordinate(@"unreadAvatarOffsetX",160),
                       WPIndicatorCoordinate(@"unreadAvatarOffsetY",200));
}
CGPoint WPInteractionBadgeOffset(void) {
    return CGPointMake(WPIndicatorCoordinate(@"interactionBadgeOffsetX",160),
                       WPIndicatorCoordinate(@"interactionBadgeOffsetY",200));
}
