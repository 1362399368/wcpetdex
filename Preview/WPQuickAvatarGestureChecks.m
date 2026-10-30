#import "WPQuickAvatarGestureChecks.h"
#import "WPQuickChatBar.h"
#import "WPQuickChatPreferences.h"
#import "WPCommon.h"

@interface WPQuickChatBar (WPQuickAvatarPreview)
- (void)tapAvatar:(UITapGestureRecognizer *)gesture;
- (void)doubleTapAvatar:(UITapGestureRecognizer *)gesture;
@end
@interface WPQuickAvatarFakeTap : UITapGestureRecognizer
@property(nonatomic) CGPoint fixturePoint;
@end
@implementation WPQuickAvatarFakeTap
- (UIGestureRecognizerState)state{return UIGestureRecognizerStateRecognized;}
- (CGPoint)locationInView:(UIView *)view{return self.fixturePoint;}
@end
NSDictionary<NSString *,NSNumber *> *WPQuickAvatarGestureChecks(void) {
    NSCAssert(NSThread.isMainThread,@"Run on main thread");
    NSUserDefaults *preferences=WPPreferences();id oldTap=[preferences objectForKey:@"quickChat.tapMode"],oldDouble=[preferences objectForKey:@"quickChat.doubleTapMode"];
    WPQuickChatSetOption(@"tapMode",@0);WPQuickChatSetOption(@"doubleTapMode",@2);
    WPQuickChatBar *bar=[[WPQuickChatBar alloc] initWithFrame:CGRectMake(0,0,120,300)];
    WPQuickChatSession *one=[WPQuickChatSession sessionWithUsername:@"fixture-person" unread:0 muted:NO pinned:NO time:1];
    [bar setValue:@[one] forKey:@"sessions"];
    UITableView *table=[bar valueForKey:@"table"];[table reloadData];[table layoutIfNeeded];
    NSMutableArray *events=[NSMutableArray new];bar.onSelectWithMode=^(NSString *username,NSInteger mode){[events addObject:@{ @"name":username,@"mode":@(mode)}];};
    WPQuickAvatarFakeTap *tap=[WPQuickAvatarFakeTap new];tap.fixturePoint=CGPointMake(30,20);
    [bar tapAvatar:tap];[bar doubleTapAvatar:tap];
    BOOL routing=events.count==2 && [events[0][@"name"] isEqualToString:@"fixture-person"] && [events[0][@"mode"] isEqual:@0] && [events[1][@"mode"] isEqual:@2];
    NSUInteger singles=0,doubles=0;
    for(UIGestureRecognizer *g in table.gestureRecognizers)if([g isKindOfClass:UITapGestureRecognizer.class]){
        UITapGestureRecognizer *t=(id)g;if(t.delaysTouchesEnded && t.numberOfTapsRequired==1)singles++;else if(t.delaysTouchesEnded && t.numberOfTapsRequired==2)doubles++;
    }
    if(oldTap)[preferences setObject:oldTap forKey:@"quickChat.tapMode"];else [preferences removeObjectForKey:@"quickChat.tapMode"];
    if(oldDouble)[preferences setObject:oldDouble forKey:@"quickChat.doubleTapMode"];else [preferences removeObjectForKey:@"quickChat.doubleTapMode"];
    return @{@"quickAvatarSingleDoubleRouteSeparately":@(routing),@"quickAvatarSingleDoubleRecognizersInstalled":@(singles>0 && doubles>0)};
}
