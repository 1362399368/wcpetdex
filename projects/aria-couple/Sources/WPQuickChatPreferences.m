#import "WPQuickChatPreferences.h"
#import "WPCommon.h"
static NSDictionary *WPQCDefaults(void){
    static NSDictionary *defaults;static dispatch_once_t once;dispatch_once(&once,^{defaults=@{
        @"buttonEnabled":@NO,@"buttonSize":@52,@"buttonOpacity":@.95,@"buttonIcon":@"message.fill",
        @"hideCapture":@NO,@"arrivalAvatar":@YES,@"arrivalDuration":@3,@"arrivalTap":@YES,@"openMode":@0,
        @"buttonBadge":@NO,@"autoDock":@YES,@"linkPet":@YES,@"side":@0,@"style":@0,
        @"width":@76,@"height":@0,@"vertical":@0,@"radius":@28,@"opacity":@.92,@"background":@0,
        @"avatarSize":@44,@"showNames":@YES,@"nameGap":@4,@"sessionGap":@6,
        @"customMode":@NO,@"filter":@0,@"tapMode":@0,@"holdMode":@1,@"separate":@NO,
        @"unreadFirst":@YES,@"pinnedAlways":@NO,@"limit":@0,@"showRedDot":@YES,@"numericBadge":@YES,
        @"showMuted":@NO,@"showFolded":@NO,@"showService":@NO,@"showOfficial":@NO,@"edgeTapActions":@NO};});return defaults;
}
static NSString *WPQCKey(NSString *key){return [@"quickChat." stringByAppendingString:key];}
static id WPQCValue(NSString *key){return [WPPreferences() objectForKey:WPQCKey(key)]?:WPQCDefaults()[key];}
static NSDictionary<NSString *,NSArray<NSNumber *> *> *WPQCRanges(void){
    static NSDictionary *ranges;static dispatch_once_t once;dispatch_once(&once,^{ranges=@{
        @"buttonSize":@[@36,@76],@"buttonOpacity":@[@.25,@1],@"arrivalDuration":@[@1,@15],
        @"openMode":@[@0,@1],@"side":@[@0,@1],@"style":@[@0,@1],@"width":@[@60,@180],@"height":@[@0,@900],
        @"vertical":@[@0,@1],@"radius":@[@0,@44],@"opacity":@[@.25,@1],@"background":@[@0,@3],
        @"avatarSize":@[@28,@72],@"nameGap":@[@0,@16],@"sessionGap":@[@0,@24],@"filter":@[@0,@2],
        @"tapMode":@[@0,@2],@"holdMode":@[@0,@2],@"limit":@[@0,@500]};});return ranges;
}
static CGFloat WPQCClampedNumber(NSString *key,CGFloat value){NSArray *range=WPQCRanges()[key];return range?MAX([range[0] doubleValue],MIN([range[1] doubleValue],value)):value;}
BOOL WPQuickChatOptionBool(NSString *key){id value=WPQCValue(key);return [value isKindOfClass:NSNumber.class] && isfinite([value doubleValue]) && [value boolValue];}
CGFloat WPQuickChatOptionNumber(NSString *key){id value=WPQCValue(key);CGFloat number=[value isKindOfClass:NSNumber.class] && isfinite([value doubleValue])?[value doubleValue]:[WPQCDefaults()[key] doubleValue];return WPQCClampedNumber(key,number);}
NSString *WPQuickChatOptionString(NSString *key){id value=WPQCValue(key);return [value isKindOfClass:NSString.class]?value:@"";}
void WPQuickChatSetOption(NSString *key,id value){
    id fallback=WPQCDefaults()[key];if(!fallback)return;
    if([fallback isKindOfClass:NSString.class]){
        if(![value isKindOfClass:NSString.class] || ![@[@"message.fill",@"bubble.left.and.bubble.right.fill",@"heart.fill",@"person.2.fill"] containsObject:value])return;
    }else{
        if(![value isKindOfClass:NSNumber.class] || !isfinite([value doubleValue]))return;
        value=WPQCRanges()[key]?@(WPQCClampedNumber(key,[value doubleValue])):@([value boolValue]);
    }
    [WPPreferences() setObject:value forKey:WPQCKey(key)];
    void (^post)(void)=^{[NSNotificationCenter.defaultCenter postNotificationName:WPSettingsDidChangeNotification object:nil];};
    if(NSThread.isMainThread)post();else dispatch_async(dispatch_get_main_queue(),post);
}
NSArray<NSString *> *WPQuickChatRemovedUsernames(void){id raw=[WPPreferences() arrayForKey:WPQCKey(@"removed")];NSMutableArray *valid=[NSMutableArray new];for(id name in raw)if([name isKindOfClass:NSString.class] && [name length] && [name length]<=256){[valid addObject:name];if(valid.count>=500)break;}return valid;}
void WPQuickChatRemoveUsername(NSString *username){if(!username.length || username.length>256)return;NSMutableOrderedSet *names=[NSMutableOrderedSet orderedSetWithArray:WPQuickChatRemovedUsernames()];[names addObject:username];while(names.count>500)[names removeObjectAtIndex:0];[WPPreferences() setObject:names.array forKey:WPQCKey(@"removed")];[NSNotificationCenter.defaultCenter postNotificationName:WPSettingsDidChangeNotification object:nil];}
void WPQuickChatRestoreRemoved(void){[WPPreferences() removeObjectForKey:WPQCKey(@"removed")];[NSNotificationCenter.defaultCenter postNotificationName:WPSettingsDidChangeNotification object:nil];}
NSArray<WPQuickChatSession *> *WPQuickChatApplyDisplayPolicy(NSArray<WPQuickChatSession *> *sessions){
    NSSet *removed=[NSSet setWithArray:WPQuickChatRemovedUsernames()];NSInteger filter=WPQuickChatOptionNumber(@"filter");
    NSMutableArray *result=[NSMutableArray new];for(WPQuickChatSession *row in sessions){
        BOOL group=[row.username.lowercaseString hasSuffix:@"@chatroom"] || [row.username.lowercaseString hasSuffix:@"@im.chatroom"];
        if([removed containsObject:row.username] || (row.muted&&!WPQuickChatOptionBool(@"showMuted")) || (filter==1&&group) || (filter==2&&!group))continue;
        [result addObject:row];
    }
    BOOL custom=WPQuickChatOptionBool(@"customMode"),unreadFirst=WPQuickChatOptionBool(@"unreadFirst"),separate=WPQuickChatOptionBool(@"separate"),pinnedAlways=WPQuickChatOptionBool(@"pinnedAlways");
    if(custom || unreadFirst || separate || pinnedAlways){
        [result sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(WPQuickChatSession *a,WPQuickChatSession *b){
            if(pinnedAlways && a.pinned!=b.pinned)return a.pinned?NSOrderedAscending:NSOrderedDescending;
            if(separate){
                BOOL ag=[a.username.lowercaseString hasSuffix:@"chatroom"],bg=[b.username.lowercaseString hasSuffix:@"chatroom"];
                if(ag!=bg)return ag?NSOrderedDescending:NSOrderedAscending;
            }
            if(unreadFirst && (a.unread>0)!=(b.unread>0))return a.unread?NSOrderedAscending:NSOrderedDescending;
            // Following WeChat preserves its relative order within each chosen
            // priority group. Custom mode orders that group by message time.
            NSTimeInterval at=isfinite(a.time)?a.time:0,bt=isfinite(b.time)?b.time:0;
            if(custom && at!=bt)return at>bt?NSOrderedAscending:NSOrderedDescending;
            return NSOrderedSame;
        }];
    }
    NSUInteger limit=(NSUInteger)WPQuickChatOptionNumber(@"limit");
    if(limit && result.count>limit){
        NSArray *tail=[result subarrayWithRange:NSMakeRange(limit,result.count-limit)];[result removeObjectsInRange:NSMakeRange(limit,result.count-limit)];
        if(WPQuickChatOptionBool(@"pinnedAlways"))for(WPQuickChatSession *row in tail)if(row.pinned)[result addObject:row];
    }
    return result;
}
UIColor *WPQuickChatBackgroundColor(UITraitCollection *traits){
    NSInteger mode=WPQuickChatOptionNumber(@"background");UIColor *color;
    if(mode==3){NSArray *rgba=[WPPreferences() arrayForKey:WPQCKey(@"backgroundRGBA")];if(rgba.count==4){BOOL valid=YES;for(id n in rgba)if(![n isKindOfClass:NSNumber.class] || !isfinite([n doubleValue]))valid=NO;if(valid)color=[UIColor colorWithRed:MAX(0,MIN(1,[rgba[0] doubleValue])) green:MAX(0,MIN(1,[rgba[1] doubleValue])) blue:MAX(0,MIN(1,[rgba[2] doubleValue])) alpha:1];}}
    if(!color)color=mode==1?UIColor.whiteColor:(mode==2?[UIColor colorWithWhite:.08 alpha:1]:[UIColor.secondarySystemBackgroundColor resolvedColorWithTraitCollection:traits]);
    return [color colorWithAlphaComponent:WPQuickChatOptionNumber(@"opacity")];
}
