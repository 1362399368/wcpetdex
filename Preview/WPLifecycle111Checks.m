#import "WPLifecycle111Checks.h"
#import "WPCommon.h"
#import "WPQuickChatBar.h"
#import "WPQuickChatModel.h"
#import "WPPetRenderer.h"
#import "WPCoupleHistory.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

@interface UIViewController (WPLifecycle111Testing)
- (void)releaseTransientViews;
@end
NSDictionary<NSString *,NSNumber *> *WPLifecycle111PreviewChecks(void) {
    NSMutableDictionary *checks=[NSMutableDictionary new];
    NSArray *keys=@[@"enabled",@"petSize",@"petOpacity"];
    NSDictionary *domain=[WPPreferences() persistentDomainForName:@"dev.zhour.wechatpet"]?:@{};
    NSData *historyBefore=[NSJSONSerialization dataWithJSONObject:WPCoupleHistory.sharedHistory.recentInteractions options:NSJSONWritingSortedKeys error:nil];
    UIViewController *controller=nil;
    @try {
        [WPPreferences() setBool:YES forKey:@"enabled"];[WPPreferences() setDouble:88 forKey:@"petSize"];[WPPreferences() setDouble:1 forKey:@"petOpacity"];
        controller=[NSClassFromString(@"WPOverlayController") new];[controller loadViewIfNeeded];
        WPPetRenderer *pet=[controller valueForKey:@"pet"];
        checks[@"lifecycle111FirstLoadKeepsSizeBeforeWindowBounds"]=@(fabs(pet.bounds.size.width-88)<.01);
        controller.view.frame=CGRectMake(0,0,393,852);[controller viewDidLayoutSubviews];
        WPQuickChatBar *bar=[controller valueForKey:@"quickBar"];bar.hidden=NO;
        WPQuickChatSession *row=[WPQuickChatSession new];row.username=@"wxid_lifecycle111_fixture";[bar reloadWithSessions:@[row]];
        UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat defaultFormat];format.scale=1;
        UIImage *avatar=[[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(160,160) format:format] imageWithActions:^(__unused UIGraphicsImageRendererContext *context){[UIColor.systemGreenColor setFill];UIRectFill(CGRectMake(0,0,160,160));}];
        NSCache *avatars=[bar valueForKey:@"avatars"],*placeholders=[bar valueForKey:@"placeholders"];
        [avatars setObject:avatar forKey:@"lifecycle"];[placeholders setObject:avatar forKey:@"lifecycle"];
        UIView *arrivals=[controller valueForKey:@"arrivals"];[arrivals addSubview:[[UIImageView alloc] initWithImage:avatar]];arrivals.hidden=NO;
        UILabel *bubble=[controller valueForKey:@"bubble"];bubble.text=@"temporary notification";bubble.hidden=NO;
        [controller releaseTransientViews];
        checks[@"lifecycle111BackgroundPurgesChatRowsAndImagesSynchronously"]=@(bar.hidden&&!bar.sessions.count&&[avatars objectForKey:@"lifecycle"]==nil&&[placeholders objectForKey:@"lifecycle"]==nil);
        checks[@"lifecycle111BackgroundCancelsChatTimerAndDownloads"]=@([bar valueForKey:@"avatarRefreshTimer"]==nil&&![[bar valueForKey:@"avatarDownloads"] count]);
        checks[@"lifecycle111BackgroundDropsTransientAvatarViewsAndCaption"]=@(arrivals.hidden&&!arrivals.subviews.count&&bubble.hidden&&bubble.text==nil&&[[controller valueForKey:@"quickDismiss"] isHidden]);
        [pet setAnimationActive:NO];
        checks[@"lifecycle111BackgroundDropsDecodedAtlasAndClock"]=@([pet valueForKey:@"atlas"]==nil&&[pet valueForKey:@"alphaMask"]==nil&&[pet valueForKey:@"displayLink"]==nil&&((CALayer *)[pet valueForKey:@"spriteLayer"]).contents==nil);
        [pet setAnimationActive:YES];bar.hidden=NO;[bar reloadWithSessions:@[row]];
        checks[@"lifecycle111FreshForegroundCanRebuildPetAndChat"]=@([pet valueForKey:@"atlas"]!=nil&&[pet valueForKey:@"displayLink"]!=nil&&bar.sessions.count==1);
        NSData *historyAfter=[NSJSONSerialization dataWithJSONObject:WPCoupleHistory.sharedHistory.recentInteractions options:NSJSONWritingSortedKeys error:nil];
        checks[@"lifecycle111CleanupKeepsInteractionHistoryUnchanged"]=@([historyBefore isEqual:historyAfter]);
    } @catch(NSException *exception) {checks[@"lifecycle111NoUnexpectedException"]=@NO;NSLog(@"Lifecycle111: %@",exception.name);}
    @finally {
        [NSNotificationCenter.defaultCenter removeObserver:controller];[controller releaseTransientViews];[(WPPetRenderer *)[controller valueForKey:@"pet"] setAnimationActive:NO];
        for(NSString *key in keys){id value=domain[key];if(value)[WPPreferences() setObject:value forKey:key];else [WPPreferences() removeObjectForKey:key];}
    }
    return checks;
}
