#import "WPUnifiedDock122Checks.h"
#import "WPCommon.h"
#import "WPOverlay.h"
#import "WPMessageBarrage.h"
#import "WPMessageBarrageSource.h"
#import "WPUnreadDockState.h"
#import "WPUnreadAvatarControl.h"
#import "WPQuickChat.h"
#import "WPQuickChatModel.h"
#import "WPPartnerContact.h"
#import "WPResizableChat.h"
#import "WPChatPresentationState.h"
#import "WPPetRenderer.h"
#import "WPCoupleHistory.h"
#import "WPRadialMenu.h"
#import <QuartzCore/QuartzCore.h>
#import <math.h>

@interface UIViewController (WPUnifiedDock122Testing)
- (void)applySettings;
- (void)updateUnreadDot;
- (void)refreshBarrageState;
- (void)toggleQuickChat;
- (void)closeQuickChat;
- (void)hold:(UILongPressGestureRecognizer *)gesture;
- (void)resetIdle;
- (void)layoutBadge;
- (CGRect)safeArea;
- (CGRect)barrageSafeArea;
- (BOOL)canPeek;
- (void)releaseTransientViews;
@end
@interface WPMessageBarrageController (WPUnifiedDock122Testing)
- (void)finishBubble:(id)bubble sequence:(NSUInteger)sequence motion:(NSUInteger)motion finished:(BOOL)finished;
- (void)finishFlightSequence:(NSUInteger)sequence motion:(NSUInteger)motion finished:(BOOL)finished;
@end
@interface WPUD122Hold : UILongPressGestureRecognizer
@property(nonatomic) UIGestureRecognizerState fixtureState;
@property(nonatomic) CGPoint fixturePoint;
@end
@implementation WPUD122Hold
- (UIGestureRecognizerState)state{return self.fixtureState;}
- (CGPoint)locationInView:(UIView *)view{return self.fixturePoint;}
@end

static NSArray *WPUD122Live(WPMessageBarrageController *engine){
    NSMutableArray *live=[NSMutableArray new];for(id control in [engine valueForKey:@"bubbles"])if([control valueForKey:@"record"])[live addObject:control];return live;
}
static NSUInteger WPUD122AvatarCount(UIView *view){
    NSUInteger count=[view isKindOfClass:WPUnreadAvatarControl.class]?1:0;for(UIView *child in view.subviews)count+=WPUD122AvatarCount(child);return count;
}
static void WPUD122PauseLayers(WPMessageBarrageController *engine,BOOL pause){
    for(UIView *view in [engine valueForKey:@"bubbles"])view.layer.speed=pause?0:1;

}
static WPBarrageMessage *WPUD122Message(NSString *username,NSString *identifier){
    WPBarrageMessage *message=[WPBarrageMessage new];message.conversationUsername=username;message.senderUsername=username;
    message.identifier=identifier;message.text=@"收到新消息后，点击桌宠上方头像打开聊天。";message.createdAt=NSDate.date;return message;
}
static void WPUD122FinishCapsules(WPMessageBarrageController *engine){
    for(NSUInteger safety=0;safety<16;safety++){
        id control=WPUD122Live(engine).firstObject;if(!control)break;id record=[control valueForKey:@"record"];
        [engine finishBubble:control sequence:[[record valueForKey:@"sequence"] unsignedIntegerValue] motion:[[control valueForKey:@"motionSerial"] unsignedIntegerValue] finished:YES];
    }
}
static void WPUD122FinishFlight(WPMessageBarrageController *engine){
    id flight=[engine valueForKey:@"flight"],record=[flight valueForKey:@"record"];
    if(record)[engine finishFlightSequence:[[record valueForKey:@"sequence"] unsignedIntegerValue] motion:[[flight valueForKey:@"motionSerial"] unsignedIntegerValue] finished:YES];
}

@interface WPUnifiedDock122Fixture : NSObject
@property(nonatomic,strong) UIWindow *host;
@property(nonatomic,strong) UIWindow *overlay;
@property(nonatomic,strong) UIViewController *root;
@property(nonatomic,strong) UINavigationController *navigation;
@property(nonatomic,strong) NSArray *originalStack;
@property(nonatomic,strong) NSMutableDictionary *checks;
@property(nonatomic,strong) NSMutableDictionary *savedPreferences;
@property(nonatomic,strong) NSMutableDictionary *savedRoot;
@property(nonatomic,strong) NSMutableDictionary *savedMonitor;
@property(nonatomic,strong) WPUnreadDockState *originalDock;
@property(nonatomic,strong) WPUnreadDockState *dock;
@property(nonatomic,strong) WPMessageBarrageController *originalEngine;
@property(nonatomic) BOOL originalEngineActive;
@property(nonatomic) BOOL originalEngineHidden;
@property(nonatomic,strong) WPMessageBarrageController *engine;
@property(nonatomic,strong) WPUnreadAvatarControl *avatar;
@property(nonatomic,strong) WPPetRenderer *pet;
@property(nonatomic,strong) id couple;
@property(nonatomic,strong) id originalPeer;
@property(nonatomic,strong) NSArray *originalIncoming;
@property(nonatomic,strong) NSArray *originalOutgoing;
@property(nonatomic,strong) WPBarrageMessage *firstMessage;
@property(nonatomic,strong) WPQuickChatSession *oldPoll;
@property(nonatomic) BOOL animationsEnabled;
@property(nonatomic) CGRect oldPetBounds;
@property(nonatomic) CGPoint oldPetCenter;
@property(nonatomic) BOOL finished;
@property(nonatomic,copy) void (^completion)(NSDictionary *checks);
@end
@implementation WPUnifiedDock122Fixture
- (void)record:(NSString *)key passed:(BOOL)passed{self.checks[key]=@(passed);}
- (void)receive:(WPBarrageMessage *)message{
    [NSNotificationCenter.defaultCenter postNotificationName:WPMessageBarrageDidReceiveNotification object:nil userInfo:@{@"message":message}];
}
- (BOOL)preservedPlayback{return self.engine.active && self.engine.isDisplaying && !self.engine.view.hidden && self.overlay.rootViewController==self.root && self.engine.view.window==self.overlay;}
- (void)start{
    self.checks=[NSMutableDictionary new];self.root=self.overlay.rootViewController;self.navigation=(id)self.host.rootViewController;
    if(![self.navigation isKindOfClass:UINavigationController.class] || ![self.root respondsToSelector:@selector(applySettings)]){[self record:@"UD122FixtureHasRealHostAndOverlay" passed:NO];self.finished=YES;self.completion(self.checks);return;}
    self.originalStack=[self.navigation.viewControllers copy];self.savedPreferences=[NSMutableDictionary new];
    NSArray *keys=@[@"enabled",@"quickChatEnabled",@"unreadAvatarEnabled",@"quickChatFlash",@"autoPeek",@"allowUnreadPeek",@"petSize",@"petOpacity",@"barrageEnabled",@"barragePauseUntil",@"barrageQuietEnabled",@"barrageContactsOnly",@"barrageAllowPrivate",@"barrageAllowGroup",@"barrageReactionsEnabled",@"barrageAdaptiveSaving",@"barrageVerticalPosition",@"barrageRegionHeight",@"quietTimeEnabled",@"reminderContactsOnly",@"quickChat.hideCapture",@"quickChat.arrivalAvatar",@"quickChatRememberedHeightFraction"];
    for(NSString *key in keys)self.savedPreferences[key]=[WPPreferences() objectForKey:key]?:NSNull.null;
    self.savedRoot=[NSMutableDictionary new];
    for(NSString *key in @[@"fullCenter",@"userAnchor",@"anchorBounds",@"positioned",@"peeking",@"edgeTransitioning",@"keyboardRect",@"gestureActive"]){id value=[self.root valueForKey:key];self.savedRoot[key]=value?:NSNull.null;}
    self.animationsEnabled=UIView.areAnimationsEnabled;[UIView setAnimationsEnabled:NO];
    self.pet=[self.root valueForKey:@"pet"];self.oldPetBounds=self.pet.bounds;self.oldPetCenter=self.pet.center;
    self.avatar=[self.root valueForKey:@"unreadDot"];self.originalDock=[self.root valueForKey:@"messageDock"];
    self.originalEngine=[self.root valueForKey:@"barrage"];self.originalEngineActive=self.originalEngine.active;self.originalEngineHidden=self.originalEngine.view.hidden;
    self.originalEngine.active=NO;self.originalEngine.view.hidden=YES;[self.root setValue:nil forKey:@"barrage"];
    self.dock=[WPUnreadDockState new];[self.root setValue:self.dock forKey:@"messageDock"];
    self.savedMonitor=[NSMutableDictionary new];WPQuickChatMonitor *monitor=WPQuickChatMonitor.sharedMonitor;
    for(NSString *key in @[@"active",@"tracker",@"observedUnread",@"observedRanks",@"latestObservedUnreadUsername",@"latestArrivalUsername",@"latestPublishedUnreadTime",@"latestPublishedUnreadCount",@"state"]){id value=[monitor valueForKey:key];self.savedMonitor[key]=[value conformsToProtocol:@protocol(NSCopying)]?[value copy]:(value?:NSNull.null);}
    [monitor setActive:NO];[monitor setValue:[NSMutableDictionary new] forKey:@"observedUnread"];[monitor setValue:[NSMutableDictionary new] forKey:@"observedRanks"];[monitor setValue:nil forKey:@"latestObservedUnreadUsername"];
    self.couple=[[WPOverlayManager sharedManager] valueForKey:@"couple"];self.originalPeer=[self.couple valueForKey:@"peerSnapshot"];[self.couple setValue:nil forKey:@"peerSnapshot"];
    WPCoupleHistory *history=WPCoupleHistory.sharedHistory;self.originalIncoming=[[history valueForKey:@"incoming"] copy];self.originalOutgoing=[[history valueForKey:@"outgoing"] copy];
    [history setValue:[NSMutableArray new] forKey:@"incoming"];[history setValue:[NSMutableArray new] forKey:@"outgoing"];
    for(NSString *key in @[@"enabled",@"quickChatEnabled",@"unreadAvatarEnabled",@"autoPeek",@"barrageEnabled",@"barrageAllowPrivate",@"barrageAllowGroup"])[WPPreferences() setBool:YES forKey:key];
    for(NSString *key in @[@"allowUnreadPeek",@"quickChatFlash",@"barrageQuietEnabled",@"barrageContactsOnly",@"barrageReactionsEnabled",@"barrageAdaptiveSaving",@"quietTimeEnabled",@"reminderContactsOnly",@"quickChat.hideCapture",@"quickChat.arrivalAvatar"])[WPPreferences() setBool:NO forKey:key];
    [WPPreferences() removeObjectForKey:@"barragePauseUntil"];[WPPreferences() removeObjectForKey:@"quickChatRememberedHeightFraction"];
    [WPPreferences() setDouble:88 forKey:@"petSize"];[WPPreferences() setDouble:1 forKey:@"petOpacity"];
    [self.root applySettings];[self.root.view layoutIfNeeded];self.engine=[self.root valueForKey:@"barrage"];
    [self.engine setValue:@YES forKey:@"previewSkipNativePolicy"];WPUD122PauseLayers(self.engine,YES);
    self.firstMessage=WPUD122Message(@"wxid_contract_aria",@"unified122-first");[self receive:self.firstMessage];
    [self record:@"UD122ReceiveNotificationStartsRealOverlayBarrage" passed:self.engine.active && self.engine.hasMovingMessages && WPUD122Live(self.engine).count==1];
    [self record:@"UD122OverlayIsAboveNativeWeChatPages" passed:self.overlay.windowLevel>self.host.windowLevel && self.overlay!=self.host];
    [WPPartnerContact openConversationWithUsername:@"wxid_contract_bob" inWindow:self.host presentationMode:1 completion:^(BOOL success,NSString *message){
        if(self.finished)return;
        [self record:@"UD122NativeChatPushKeepsMovingMessageAlive" passed:success && self.navigation.viewControllers.count==self.originalStack.count+1 && [self preservedPlayback] && self.engine.hasMovingMessages];
        [self.navigation setViewControllers:self.originalStack animated:NO];
        [self record:@"UD122NativeChatPopDoesNotPurgeOverlay" passed:[self preservedPlayback] && WPUD122Live(self.engine).count==1];
        UIWindow *page=self.host.windowScene?[[UIWindow alloc] initWithWindowScene:self.host.windowScene]:[[UIWindow alloc] initWithFrame:self.host.bounds];
        page.frame=self.host.bounds;page.windowLevel=UIWindowLevelAlert+50;page.rootViewController=[UIViewController new];page.rootViewController.view.backgroundColor=UIColor.systemBackgroundColor;
        [page makeKeyAndVisible];[WPOverlayManager.sharedManager refresh];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,80*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        if(self.finished)return;
        [self record:@"UD123HigherPluginPageKeepsSameNonKeyOverlayAndBarrage" passed:self.engine==[self.root valueForKey:@"barrage"] && [self preservedPlayback] && WPUD122Live(self.engine).count==1 && self.overlay.windowLevel>page.windowLevel && !self.overlay.isKeyWindow && [self.root valueForKey:@"hostWindow"]==page];
        page.hidden=YES;[self.host makeKeyAndVisible];[WPOverlayManager.sharedManager refresh];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,80*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        if(self.finished)return;
        [self record:@"UD123ReturningFromPluginPagePreservesPlaybackIdentity" passed:[self preservedPlayback] && WPUD122Live(self.engine).count==1];
        [self exerciseFloatingControls];
        });
        });
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(self.finished)return;[self record:@"UD122UnifiedDockIntegrationDoesNotHang" passed:NO];[self finish];});
}
- (void)exerciseFloatingControls{
    [self.root toggleQuickChat];[self record:@"UD122QuickChatSidebarKeepsBarrageActive" passed:!((UIView *)[self.root valueForKey:@"quickBar"]).hidden && [self preservedPlayback]];
    [self.root closeQuickChat];
    WPUD122Hold *hold=[WPUD122Hold new];hold.fixtureState=UIGestureRecognizerStateBegan;hold.fixturePoint=self.pet.center;[self.root hold:hold];
    WPRadialMenuView *menu=[self.root valueForKey:@"menu"];
    [self record:@"UD122ActualLongPressHasOnlyFourPetActions" passed:menu.isShowing && menu.accessibilityElements.count==4 && [self preservedPlayback]];
    hold.fixtureState=UIGestureRecognizerStateCancelled;[self.root hold:hold];
    WPUD122FinishCapsules(self.engine);
    [self record:@"UD123FinalCapsulePopsOneUnifiedAvatarWithoutFlight" passed:!self.engine.hasMovingMessages && !self.engine.returningToDock && !self.dock.playbackPending && self.dock.visible && !self.avatar.hidden];
    CGRect before=[self.root barrageSafeArea];CGRect screen=self.overlay.screen.bounds;
    CGRect keyboard=CGRectMake(0,screen.size.height*.62,screen.size.width,screen.size.height*.38);
    NSDictionary *info=@{UIKeyboardFrameEndUserInfoKey:[NSValue valueWithCGRect:keyboard],UIKeyboardAnimationDurationUserInfoKey:@0,UIKeyboardAnimationCurveUserInfoKey:@0};
    [NSNotificationCenter.defaultCenter postNotificationName:UIKeyboardWillChangeFrameNotification object:nil userInfo:info];
    [self record:@"UD123KeyboardShowPreservesUnifiedAvatarAndSafeArea" passed:self.engine.active && !self.engine.returningToDock && self.dock.visible && CGRectEqualToRect(before,[self.root barrageSafeArea])];
    [NSNotificationCenter.defaultCenter postNotificationName:UIKeyboardWillHideNotification object:nil userInfo:info];
    [self record:@"UD123KeyboardHideKeepsUnifiedAvatarIdentity" passed:self.engine.active && !self.engine.returningToDock && self.dock.visible && CGRectEqualToRect(before,[self.root barrageSafeArea])];
    WPUD122FinishFlight(self.engine);
    [self record:@"UD122BarrageAndUnreadUseSameSingleAvatarControl" passed:self.dock.visible && !self.avatar.hidden && [self.avatar.username isEqual:@"wxid_contract_aria"] && WPUD122AvatarCount(self.root.view)==1 && [self.root valueForKey:@"unreadDot"]==self.avatar];
    self.oldPoll=[WPQuickChatSession sessionWithUsername:@"wxid_contract_aria" unread:1 muted:NO pinned:NO time:self.firstMessage.createdAt.timeIntervalSince1970];
    [self.dock observeUnreadSession:self.oldPoll genuineArrival:NO];[self.root updateUnreadDot];
    [self record:@"UD122NativeUnreadPollDoesNotCreateSecondDock" passed:self.dock.visible && !self.avatar.hidden && WPUD122AvatarCount(self.root.view)==1];
    [UIView setAnimationsEnabled:YES];
    [self.avatar sendActionsForControlEvents:UIControlEventTouchUpInside];
    [self waitForOpenedChatUntil:NSProcessInfo.processInfo.systemUptime+2];
}
- (void)waitForOpenedChatUntil:(NSTimeInterval)deadline{
    if(self.finished)return;
    UIViewController *presentation=self.navigation.presentedViewController;
    if((presentation && [WPResizableChatController coordinatorForController:presentation]) || NSProcessInfo.processInfo.systemUptime>=deadline){[self verifyOpenedChat];return;}
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,80*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[self waitForOpenedChatUntil:deadline];});
}
- (void)verifyOpenedChat{
    UIViewController *presentation=self.navigation.presentedViewController;
    WPResizableChatController *chat=presentation?[WPResizableChatController coordinatorForController:presentation]:nil;
    [self record:@"UD123AvatarTapOpensDirectNative75PercentChatPanel" passed:chat && chat.presentedController==presentation && fabs(chat.heightFraction-.75)<.003 && [chat.chatNavigationController.topViewController respondsToSelector:NSSelectorFromString(@"getCurrentChatName")]];
    [self record:@"UD123ActuallyVisibleChatIsSuppressed" passed:WPChatConversationIsVisible(@"wxid_contract_aria") && !WPChatConversationIsVisible(@"wxid_contract_bob")];
    [self record:@"UD122SuccessfulChatOpenConsumesAvatarAfterCompletion" passed:chat && !self.dock.visible && self.avatar.hidden && self.avatar.username.length==0];
    UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:self.host.bounds.size];
    UIImage *image=[renderer imageWithActions:^(__unused UIGraphicsImageRendererContext *context){[self.host drawViewHierarchyInRect:self.host.bounds afterScreenUpdates:YES];[self.overlay drawViewHierarchyInRect:self.overlay.bounds afterScreenUpdates:YES];}];
    NSString *path=[WPDataDirectory() stringByAppendingPathComponent:@"unified-dock-chat-v123.png"];
    [self record:@"UD122NativeChatPreviewScreenshotSaved" passed:[UIImagePNGRepresentation(image) writeToFile:path atomically:YES]];
    [self.dock observeUnreadSession:self.oldPoll genuineArrival:NO];[self.root updateUnreadDot];[self receive:self.firstMessage];WPUD122FinishCapsules(self.engine);WPUD122FinishFlight(self.engine);
    [self record:@"UD122OldUnreadPollAndDuplicateReceiveCannotReviveAvatar" passed:!self.dock.visible && self.avatar.hidden];
    void (^afterDismiss)(void)=^{if(self.finished)return;[self prepareIdlePeek];};
    if(presentation)[presentation dismissViewControllerAnimated:NO completion:afterDismiss];else afterDismiss();
}
- (void)prepareIdlePeek{
    [UIView setAnimationsEnabled:NO];[self.root closeQuickChat];[(WPRadialMenuView *)[self.root valueForKey:@"menu"] cancel];
    ((UIView *)[self.root valueForKey:@"bubble"]).hidden=YES;((UIView *)[self.root valueForKey:@"arrivals"]).hidden=YES;
    [self.root setValue:@NO forKey:@"gestureActive"];[self.root setValue:@NO forKey:@"peeking"];[self.root setValue:@NO forKey:@"edgeTransitioning"];[self.pet endPeek];
    CGRect safe=[self.root safeArea];CGPoint edge=CGPointMake(CGRectGetMinX(safe)+self.pet.bounds.size.width/2,CGRectGetMidY(safe));
    [self.root setValue:[NSValue valueWithCGPoint:edge] forKey:@"fullCenter"];
    [self.root setValue:[NSValue valueWithCGPoint:CGPointMake(edge.x/MAX(1,self.root.view.bounds.size.width),edge.y/MAX(1,self.root.view.bounds.size.height))] forKey:@"userAnchor"];
    self.pet.center=edge;[self.root layoutBadge];[self.root resetIdle];
    [self record:@"UD122ConsumedAvatarRestoresActualIdlePeekEligibility" passed:[self.root canPeek] && !self.dock.visible && self.avatar.hidden && [self.root valueForKey:@"idleTimer"]!=nil];
    [UIView setAnimationsEnabled:YES];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,4250*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        if(self.finished)return;
        [self record:@"UD122ThreeSecondIdleReallyHidesPetAtScreenEdge" passed:[[self.root valueForKey:@"peeking"] boolValue] && ![[self.root valueForKey:@"edgeTransitioning"] boolValue] && self.pet.center.x<edge.x && self.avatar.hidden];
        [self verifyNewMessageAndFailure];
    });
}
- (void)verifyNewMessageAndFailure{
    WPBarrageMessage *next=WPUD122Message(@"wxid_contract_aria",@"unified122-second");[self receive:next];WPUD122FinishCapsules(self.engine);WPUD122FinishFlight(self.engine);
    [self record:@"UD122NewUniqueMessageCanDockAgainAfterConsumption" passed:self.dock.visible && !self.avatar.hidden && [self.avatar.username isEqual:@"wxid_contract_aria"]];
    WPBarrageMessage *unknown=WPUD122Message(@"wxid_unified122_unknown_contact",@"unified122-unknown");[self receive:unknown];WPUD122FinishCapsules(self.engine);WPUD122FinishFlight(self.engine);
    NSString *revision=[self.dock.revision copy];[self.avatar sendActionsForControlEvents:UIControlEventTouchUpInside];
    [self record:@"UD122UnknownContactFailurePreservesUnreadAvatar" passed:self.dock.visible && !self.avatar.hidden && [self.avatar.username isEqual:unknown.conversationUsername] && [self.dock.revision isEqual:revision] && !self.navigation.presentedViewController];
    [self finish];
}
- (void)finish{
    if(self.finished)return;self.finished=YES;
    void (^cleanup)(void)=^{
        [self.root releaseTransientViews];self.engine.active=NO;WPUD122PauseLayers(self.engine,NO);[self.engine.view removeFromSuperview];
        [self.root setValue:self.originalEngine forKey:@"barrage"];[self.root setValue:self.originalDock forKey:@"messageDock"];
        for(NSString *key in self.savedPreferences){id value=self.savedPreferences[key];if(value==NSNull.null)[WPPreferences() removeObjectForKey:key];else [WPPreferences() setObject:value forKey:key];}
        if(self.savedMonitor){WPQuickChatMonitor *monitor=WPQuickChatMonitor.sharedMonitor;[monitor setActive:NO];BOOL active=[self.savedMonitor[@"active"] boolValue];if(active)[monitor setActive:YES];for(NSString *key in self.savedMonitor){if([key isEqual:@"active"])continue;id value=self.savedMonitor[key];if(value==NSNull.null)value=nil;if([key isEqual:@"observedUnread"]||[key isEqual:@"observedRanks"]||[key isEqual:@"state"])value=[value mutableCopy];[monitor setValue:value forKey:key];}}
        if(self.originalIncoming){[WPCoupleHistory.sharedHistory setValue:[self.originalIncoming mutableCopy] forKey:@"incoming"];[WPCoupleHistory.sharedHistory setValue:[self.originalOutgoing mutableCopy] forKey:@"outgoing"];}
        [self.couple setValue:self.originalPeer forKey:@"peerSnapshot"];
        [self.navigation setViewControllers:self.originalStack animated:NO];
        for(NSString *key in self.savedRoot){id value=self.savedRoot[key];[self.root setValue:value==NSNull.null?nil:value forKey:key];}
        self.pet.bounds=self.oldPetBounds;self.pet.center=self.oldPetCenter;
        ((UIView *)[self.root valueForKey:@"bubble"]).hidden=YES;[(WPRadialMenuView *)[self.root valueForKey:@"menu"] cancel];
        if([self.root respondsToSelector:@selector(applySettings)])[self.root applySettings];
        self.originalEngine.active=self.originalEngineActive;self.originalEngine.view.hidden=self.originalEngineHidden;
        [UIView setAnimationsEnabled:self.animationsEnabled];self.completion([self.checks copy]);
    };
    if(self.navigation.presentedViewController)[self.navigation dismissViewControllerAnimated:NO completion:cleanup];else cleanup();
}
@end
void WPUnifiedDock122RunPreviewChecks(UIWindow *hostWindow,UIWindow *overlayWindow,void (^completion)(NSDictionary<NSString *,NSNumber *> *checks)){
    WPUnifiedDock122Fixture *fixture=[WPUnifiedDock122Fixture new];fixture.host=hostWindow;fixture.overlay=overlayWindow;fixture.completion=completion;[fixture start];
}
