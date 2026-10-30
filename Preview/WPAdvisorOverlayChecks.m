#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "WPCommon.h"
#import "WPComfortPreferences.h"
#import "WPOverlay.h"
#import "WPAdvisorStatusView.h"
#import "WPAdvisorTaskCenter.h"
#import "WPAdvisorReplyAction.h"
#import "WPChatPresentationState.h"
#import "WPAdvisorContinuousCoordinator.h"
#import "WPPartnerContact.h"
#import "WPUnreadDockState.h"
#import "WPQuickChatModel.h"
#import "WPSessionEligibility.h"

@interface UIViewController (WPAdvisorOverlayChecks)
- (BOOL)canPeek;
- (CGRect)safeArea;
- (void)openAdvisorTask:(WPAdvisorTask *)task fullScreen:(BOOL)fullScreen;
- (void)applyAdvisorReply:(NSString *)reply send:(BOOL)send;
@end

@interface WPAdvisorOverlayCheckChat : UIViewController
@property(nonatomic,copy) NSString *username;
@property(nonatomic,strong) UITextView *input;
@property(nonatomic) NSUInteger sent;
@end
@implementation WPAdvisorOverlayCheckChat
- (NSString *)getCurrentChatName{return self.username;}
- (void)viewDidLoad {[super viewDidLoad];self.view.backgroundColor=UIColor.whiteColor;
    self.input=[[UITextView alloc] initWithFrame:CGRectMake(20,500,200,50)];[self.view addSubview:self.input];
    UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];button.frame=CGRectMake(240,500,80,50);[button setTitle:@"发送" forState:UIControlStateNormal];
    [button addTarget:self action:@selector(pressed) forControlEvents:UIControlEventTouchUpInside];[self.view addSubview:button];}
- (void)pressed {self.sent++;self.input.text=@"";}
@end

static NSInteger WPAdvisorCheckRoute=-1;
static BOOL WPAdvisorCheckCompleteRoute=NO;
static void WPAdvisorRouteStub(__unused id cls,__unused SEL sel,__unused NSString *username,__unused UIWindow *window,NSInteger mode,void (^completion)(BOOL,NSString *)){WPAdvisorCheckRoute=mode;if(WPAdvisorCheckCompleteRoute)completion(YES,@"opened");}
static UIWindow *WPAdvisorHostStub(__unused id manager,__unused SEL sel,UIWindow *window){return window;}
static BOOL WPAdvisorReadyStub(__unused id manager,__unused SEL sel){return YES;}

NSDictionary<NSString *,NSNumber *> *WPAdvisorOverlayPreviewChecks(void){
    NSCAssert(NSThread.isMainThread,@"main thread required");
    NSUserDefaults *prefs=WPPreferences();NSArray *keys=@[@"enabled",@"autoPeek",@"allowUnreadPeek",@"allowAdvisorPeek"];
    NSMutableDictionary *saved=[NSMutableDictionary new];for(NSString *key in keys)saved[key]=[prefs objectForKey:key]?:NSNull.null;
    NSString *account=WPAdvisorCurrentAccountFingerprint();
    NSArray *coordKeys=account.length?@[[NSString stringWithFormat:@"advisor.continuous.%@.selected",account],[NSString stringWithFormat:@"advisor.continuous.%@.usernames",account],[NSString stringWithFormat:@"advisor.continuous.%@.requireFresh",account]]:@[];
    for(NSString *key in coordKeys)saved[key]=[prefs objectForKey:key]?:NSNull.null;
    UIWindow *host=[[UIWindow alloc] initWithFrame:CGRectMake(0,0,390,844)];WPAdvisorOverlayCheckChat *chat=[WPAdvisorOverlayCheckChat new];chat.username=@"advisor-overlay-fixture";host.rootViewController=chat;host.hidden=NO;[host makeKeyAndVisible];
    UIWindow *overlayWindow=[[UIWindow alloc] initWithFrame:host.bounds];UIViewController *overlay=[NSClassFromString(@"WPOverlayController") new];overlayWindow.rootViewController=overlay;overlayWindow.hidden=NO;
    [overlay setValue:host forKey:@"hostWindow"];[overlay.view layoutIfNeeded];
    Method hostMethod=class_getInstanceMethod(WPOverlayManager.class,NSSelectorFromString(@"prepareChatHost:"));
    Method readyMethod=class_getInstanceMethod(WPOverlayManager.class,@selector(recoveryMaintenanceReady));
    Method routeMethod=class_getClassMethod(WPPartnerContact.class,@selector(openConversationWithUsername:inWindow:presentationMode:completion:));
    IMP originalHost=method_setImplementation(hostMethod,(IMP)WPAdvisorHostStub),originalReady=method_setImplementation(readyMethod,(IMP)WPAdvisorReadyStub),originalRoute=method_setImplementation(routeMethod,(IMP)WPAdvisorRouteStub);
    NSMutableDictionary *out=[NSMutableDictionary new];
    @try {
        BOOL currentSelection=WPAdvisorSelectionIsCurrent(account,chat.username,host);
        BOOL changedChat=!WPAdvisorSelectionIsCurrent(account,@"another-chat",host);
        id selfContact=WPSEReadObject(WPWeChatService(@"CContactMgr"),@[@"getSelfContact"]);
        NSString *originalAccount=[WPSEReadObject(selfContact,@[@"m_nsUsrName"]) copy];
        [selfContact setValue:@"other-selection-account" forKey:@"m_nsUsrName"];
        BOOL changedAccount=originalAccount.length && !WPAdvisorSelectionIsCurrent(account,chat.username,host);
        if(originalAccount)[selfContact setValue:originalAccount forKey:@"m_nsUsrName"];
        out[@"advisorSceneSelectionBoundToChatAndAccount"]=@(currentSelection&&changedChat&&changedAccount);
        WPChatAdvisorPreset *couple=[WPChatAdvisorPreset presetWithIdentifier:@"couple"],*flirt=[WPChatAdvisorPreset presetWithIdentifier:@"flirt"],*friend=[WPChatAdvisorPreset presetWithIdentifier:@"friend"];
        out[@"advisorDistinctLoveFlirtFriendScenes"]=@([couple.title isEqual:@"恋爱聊天"] && [flirt.title isEqual:@"暧昧聊天"] && [friend.title isEqual:@"朋友闲聊"] && ![couple.instruction isEqual:flirt.instruction]);
        [prefs setBool:YES forKey:@"enabled"];[prefs setBool:YES forKey:@"autoPeek"];
        WPAdvisorStatusView *status=[overlay valueForKey:@"advisorStatus"];UIView *pet=[overlay valueForKey:@"pet"],*avatar=[overlay valueForKey:@"unreadDot"];
        pet.hidden=NO;[overlay valueForKey:@"bubble"];((UIView *)[overlay valueForKey:@"bubble"]).hidden=YES;
        ((UIView *)[overlay valueForKey:@"quickBar"]).hidden=YES;((UIView *)[overlay valueForKey:@"arrivals"]).hidden=YES;avatar.hidden=YES;
        CGRect safe=[overlay safeArea];CGPoint anchor=CGPointMake(CGRectGetMaxX(safe)-CGRectGetWidth(pet.bounds)/2,CGRectGetMidY(safe));
        [overlay setValue:[NSValue valueWithCGPoint:anchor] forKey:@"fullCenter"];pet.center=anchor;
        [status updateUnreadCount:1];[prefs removeObjectForKey:@"allowAdvisorPeek"];
        BOOL defaultAllows=WPAllowAdvisorPeek() && [overlay canPeek];
        [prefs setBool:NO forKey:@"allowAdvisorPeek"];BOOL blocks=![overlay canPeek];
        [prefs setBool:YES forKey:@"allowAdvisorPeek"];BOOL enabled=[overlay canPeek];
        WPUnreadDockState *dock=[overlay valueForKey:@"messageDock"];
        [dock observeUnreadSession:[WPQuickChatSession sessionWithUsername:@"other" unread:1 muted:NO pinned:NO time:NSDate.date.timeIntervalSince1970] genuineArrival:YES];avatar.hidden=NO;
        [prefs setBool:NO forKey:@"allowUnreadPeek"];BOOL avatarBlocks=![overlay canPeek];
        [prefs setBool:YES forKey:@"allowUnreadPeek"];[prefs setBool:NO forKey:@"allowAdvisorPeek"];BOOL advisorBlocks=![overlay canPeek];
        [prefs setBool:YES forKey:@"allowAdvisorPeek"];BOOL bothAllow=[overlay canPeek];
        [status updateUnreadCount:0];[prefs setBool:NO forKey:@"allowAdvisorPeek"];BOOL independent=[overlay canPeek];
        out[@"advisorPeekDefaultsAllow"]=@(defaultAllows);out[@"advisorPeekSwitchControlsRedDot"]=@(blocks&&enabled);
        out[@"advisorPeekBothIndicatorsNeedPermission"]=@(avatarBlocks&&advisorBlocks&&bothAllow);out[@"advisorPeekOptionsIndependent"]=@(independent);

        WPChatAdvice *advice=[WPChatAdvice new];advice.replies=@[@"reply"];advice.actions=@[];advice.intents=@[];
        WPAdvisorTask *task=[WPAdvisorTask new];[task setValue:account forKey:@"accountFingerprint"];[task setValue:chat.username forKey:@"username"];[task setValue:advice forKey:@"advice"];[task setValue:@YES forKey:@"stale"];
        WPAdvisorCheckRoute=-1;[overlay openAdvisorTask:task fullScreen:YES];BOOL historyFull=WPAdvisorCheckRoute==1;
        [task setValue:@"different-contact" forKey:@"username"];WPAdvisorCheckRoute=-1;[overlay openAdvisorTask:task fullScreen:NO];BOOL unreadSheet=WPAdvisorCheckRoute==3;
        out[@"advisorHistoryUsesFullScreenEvenIfSameChat"]=@(historyFull);out[@"advisorUnreadKeepsNativeSheet"]=@(unreadSheet);

        [task setValue:chat.username forKey:@"username"];[overlay setValue:task forKey:@"advisorDisplayedTask"];
        WPAdvisorContinuousCoordinator *coordinator=WPAdvisorContinuousCoordinator.sharedCoordinator;
        [coordinator setLockedUsername:chat.username];[coordinator setEnabled:NO];chat.input.text=@"";
        [overlay applyAdvisorReply:@"普通旧建议" send:YES];BOOL normal=chat.sent==1;
        [overlay setValue:task forKey:@"advisorDisplayedTask"];[coordinator setEnabled:YES];[coordinator setRequiresFreshAnalysis:NO forUsername:chat.username];chat.input.text=@"";
        [overlay applyAdvisorReply:@"连续旧建议" send:YES];BOOL optionalOff=chat.sent==2;
        [overlay setValue:task forKey:@"advisorDisplayedTask"];[coordinator setRequiresFreshAnalysis:YES forUsername:chat.username];chat.input.text=@"";
        [overlay applyAdvisorReply:@"严格旧建议" send:YES];BOOL optionalOn=chat.sent==2 && chat.input.text.length==0;
        out[@"advisorOldManualSuggestionCanSend"]=@(normal);out[@"advisorContinuousFreshGuardOptional"]=@(optionalOff&&optionalOn);
        [coordinator setEnabled:NO];[overlay setValue:task forKey:@"advisorDisplayedTask"];chat.input.text=@"";
        NSUInteger before=chat.sent;WPAdvisorCheckRoute=-1;WPAdvisorCheckCompleteRoute=YES;
        [overlay applyAdvisorReply:@"点按回复" send:NO];WPAdvisorCheckCompleteRoute=NO;
        out[@"advisorTapOpensFullScreenAndFills"]=@(WPAdvisorCheckRoute==1 && [chat.input.text isEqual:@"点按回复"] && chat.sent==before);
    } @finally {
        method_setImplementation(hostMethod,originalHost);method_setImplementation(readyMethod,originalReady);method_setImplementation(routeMethod,originalRoute);
        WPAdvisorContinuousCoordinator *coordinator=WPAdvisorContinuousCoordinator.sharedCoordinator;
        [coordinator setEnabled:NO];
        for(NSString *key in saved)if(saved[key]==NSNull.null)[prefs removeObjectForKey:key];else[prefs setObject:saved[key] forKey:key];
        [coordinator setValue:nil forKey:@"accountFingerprint"];[coordinator refreshAccountIfNeeded];
        overlayWindow.hidden=YES;overlayWindow.rootViewController=nil;host.hidden=YES;host.rootViewController=nil;
    }
    return out;
}

void WPAdvisorDelayedReplyChecks(void (^completion)(NSDictionary<NSString *,NSNumber *> *)) {
    UIWindow *previous=UIApplication.sharedApplication.keyWindow;
    UIWindow *host=[[UIWindow alloc] initWithFrame:CGRectMake(0,0,390,844)];
    WPAdvisorOverlayCheckChat *chat=[WPAdvisorOverlayCheckChat new];chat.username=@"advisor-delay-fixture";host.rootViewController=chat;[host makeKeyAndVisible];
    UIWindow *overlayWindow=[[UIWindow alloc] initWithFrame:host.bounds];UIViewController *overlay=[NSClassFromString(@"WPOverlayController") new];overlayWindow.rootViewController=overlay;overlayWindow.hidden=NO;
    [overlay setValue:host forKey:@"hostWindow"];[overlay.view layoutIfNeeded];
    WPAdvisorTask *task=[WPAdvisorTask new];[task setValue:WPAdvisorCurrentAccountFingerprint() forKey:@"accountFingerprint"];[task setValue:chat.username forKey:@"username"];[overlay setValue:task forKey:@"advisorDisplayedTask"];
    UIButton *button=nil;for(UIView *view in chat.view.subviews)if([view isKindOfClass:UIButton.class])button=(UIButton *)view;
    button.hidden=YES;[overlay applyAdvisorReply:@"等待按钮" send:YES];BOOL filled=[chat.input.text isEqual:@"等待按钮"] && chat.sent==0;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,250*NSEC_PER_MSEC),dispatch_get_main_queue(),^{button.hidden=NO;});
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,800*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        BOOL sent=filled && chat.sent==1 && !chat.input.text.length;
        overlayWindow.hidden=YES;overlayWindow.rootViewController=nil;host.hidden=YES;host.rootViewController=nil;if(previous && !previous.hidden)[previous makeKeyWindow];
        completion(@{@"advisorHoldWaitsForNativeButtonOnce":@(sent)});
    });
}
