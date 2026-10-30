#import "WPOverlay.h"
#import "WPCommon.h"
#import "WPPetRenderer.h"
#import "WPRadialMenu.h"
#import "WPMenuConfiguration.h"
#import "WPSettings.h"
#import "WPActionAdapter.h"
#import "WPPartnerContact.h"
#import "WPShakeDetector.h"
#import "WPTheme.h"
#import "WPEdition.h"
#import "WPQuickChat.h"
#import "WPQuickChatBar.h"
#import "WPTapActions.h"
#import "WPIndicatorSettings.h"
#import "WPUnreadAvatarControl.h"
#import "WPComfortPreferences.h"
#import "WPBarragePreferences.h"
#import "WPMessageBarrage.h"
#import "WPMessageBarrageSource.h"
#import "WPQuickChatPreferences.h"
#import "WPCaptureProtectedView.h"
#import "WPUnreadDockState.h"
#import "WPSharedChatAvatar.h"
#import "WPChatPresentationState.h"
#import "WPRecoveryCoordinator.h"
#import "WPSessionEligibility.h"
#import "WPChatAdvisor.h"
#import "WPChatAdvisorPanel.h"
#import "WPAdvisorReplyAction.h"
#import "WPAdvisorTaskCenter.h"
#import "WPAdvisorStatusView.h"
#import "WPAdvisorContinuousCoordinator.h"
#import "WPAdvisorContextStore.h"
#import "WPChoiceSheet.h"

@interface WPOverlayManager (WPChatHostPreparation)
- (UIWindow *)prepareChatHost:(UIWindow *)preferred;
@end

@interface WPOverlayWindow : UIWindow
@property (nonatomic) BOOL acceptsKeyboard;
@property(nonatomic) NSUInteger touchHits;
@property(nonatomic) NSUInteger forwardedTouches;
@property(nonatomic,copy) NSString *lastHitClass;
@end
@implementation WPOverlayWindow
- (BOOL)canBecomeKeyWindow { return self.acceptsKeyboard; }
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    self.touchHits++;self.lastHitClass=hit?NSStringFromClass(hit.class):@"none";
    if (self.acceptsKeyboard) return hit;
    if (hit == self || hit == self.rootViewController.view){self.forwardedTouches++;return nil;}
    return hit;
}
@end

@interface WPOverlayUnreadAvatarControl : WPUnreadAvatarControl
- (CGRect)visualFrame;
@end
@implementation WPOverlayUnreadAvatarControl
- (CGRect)visualFrame {CALayer *presentation=[self.layer animationForKey:@"WPMessageHeadPop123"]?self.layer.presentationLayer:nil;return presentation?presentation.frame:self.frame;}
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if([self.layer animationForKey:@"WPMessageHeadPop123"] && self.layer.presentationLayer && self.superview){
        CGPoint parent=[self convertPoint:point toView:self.superview];CGRect visual=[self visualFrame];
        return CGRectContainsPoint(CGRectInset(visual,-MAX(0,(44-visual.size.width)/2),-MAX(0,(44-visual.size.height)/2)),parent);
    }
    return [super pointInside:point withEvent:event];
}
@end

static CGPoint WPIndicatorCenter(CGPoint center,CGSize size,CGRect safe) {
    CGFloat halfWidth=MAX(0,size.width/2),halfHeight=MAX(0,size.height/2);
    CGFloat x=isfinite(center.x)?center.x:CGRectGetMidX(safe);
    CGFloat y=isfinite(center.y)?center.y:CGRectGetMidY(safe);
    x=size.width>=safe.size.width?CGRectGetMidX(safe):MAX(CGRectGetMinX(safe)+halfWidth,MIN(CGRectGetMaxX(safe)-halfWidth,x));
    y=size.height>=safe.size.height?CGRectGetMidY(safe):MAX(CGRectGetMinY(safe)+halfHeight,MIN(CGRectGetMaxY(safe)-halfHeight,y));
    return CGPointMake(x,y);
}

/// Keep transient captions and sender heads clear of persistent indicators.
/// Candidate positions are finite and bounded; a short keyboard area may
/// require the last clamped fallback when no wholly separate space exists.
static CGRect WPOverlayPromptFrame(CGSize size,CGPoint preferred,CGRect safe,NSArray<NSValue *> *obstacles) {
    size.width=MAX(1,MIN(size.width,safe.size.width));size.height=MAX(1,MIN(size.height,safe.size.height));
    CGFloat x=WPIndicatorCenter(CGPointMake(preferred.x+size.width/2,CGRectGetMidY(safe)),size,safe).x-size.width/2;
    NSMutableArray<NSNumber *> *origins=[NSMutableArray arrayWithObject:@(preferred.y)];
    for(NSValue *value in obstacles)[origins addObject:@(CGRectGetMinY(value.CGRectValue)-size.height-6)];
    for(NSValue *value in obstacles)[origins addObject:@(CGRectGetMaxY(value.CGRectValue)+6)];
    [origins addObjectsFromArray:@[@(CGRectGetMinY(safe)),@(CGRectGetMaxY(safe)-size.height)]];
    for(NSNumber *origin in origins){
        CGRect candidate=CGRectMake(x,origin.doubleValue,size.width,size.height);
        if(!CGRectContainsRect(safe,candidate))continue;
        BOOL clear=YES;
        for(NSValue *value in obstacles)if(CGRectIntersectsRect(candidate,CGRectInset(value.CGRectValue,-4,-4))){clear=NO;break;}
        if(clear)return candidate;
    }
    CGPoint center=WPIndicatorCenter(CGPointMake(x+size.width/2,preferred.y+size.height/2),size,safe);
    return CGRectMake(center.x-size.width/2,center.y-size.height/2,size.width,size.height);
}

@interface WPOverlayController : UIViewController <UIGestureRecognizerDelegate>
@property (nonatomic) WPPetRenderer *pet;
@property (nonatomic) WPRadialMenuView *menu;
@property (nonatomic) UILabel *bubble;
@property (nonatomic, weak) UIWindow *hostWindow;
@property (nonatomic) CGRect keyboardRect;
@property (nonatomic) CGPoint dragStart;
@property (nonatomic) BOOL positioned;
@property (nonatomic) CGPoint userAnchor;
@property (nonatomic) CGSize anchorBounds;
@property (nonatomic) NSUInteger bubbleGeneration;
@property (nonatomic) NSUInteger menuPreviewGeneration;
@property (nonatomic) WPShakeDetector *shake;
@property (nonatomic) NSInteger shakeLevel;
@property (nonatomic) BOOL gestureActive;
@property (nonatomic) BOOL gestureInterrupted;
@property (nonatomic) BOOL peeking;
@property (nonatomic) BOOL edgeTransitioning;
@property (nonatomic) NSUInteger edgeMotionSerial;
@property (nonatomic) CGPoint fullCenter;
@property (nonatomic) NSUInteger idleGeneration;
@property (nonatomic) NSTimer *idleTimer;
@property (nonatomic) WPQuickChatBar *quickBar;
@property (nonatomic) UIControl *quickDismiss;
@property (nonatomic) WPUnreadAvatarControl *unreadDot;
@property (nonatomic) WPUnreadDockState *messageDock;
@property (nonatomic) BOOL releasingTransientViews;
@property (nonatomic) UIView *arrivals;
@property (nonatomic) NSUInteger arrivalGeneration;
@property (nonatomic) WPMessageBarrageController *barrage;
@property (nonatomic,copy) NSString *barrageDockConversation;
@property (nonatomic,copy) NSString *barrageDockSender;
@property (nonatomic) UIImage *barrageDockImage;
@property (nonatomic) BOOL barrageWasEnabled;
@property (nonatomic) CFTimeInterval lastBarrageReaction;
@property (nonatomic) NSTimer *barragePreviewTimer;
@property (nonatomic) UILabel *chatCount;
@property (nonatomic) NSMutableArray<WPQuickChatAvatarPreparation *> *arrivalAvatarJobs;
@property (nonatomic) WPChatAdvisorPanel *advisorPanel;
@property (nonatomic) WPAdvisorTask *advisorDisplayedTask;
@property (nonatomic) WPAdvisorStatusView *advisorStatus;
@property (nonatomic) NSMutableDictionary<NSString *,WPAdvisorTask *> *advisorObservedTasks;
@property (nonatomic) NSMutableSet<NSString *> *advisorAutomaticTasks;
- (void)applySettings;
- (void)closeQuickChat;
- (void)cancelActiveGesture;
- (void)releaseTransientViews;
- (void)showMessage:(NSString *)text;
- (void)updateUnreadDot;
- (void)refreshBarrageState;
- (void)layoutBarrage;
- (void)openQuickChat:(NSString *)username mode:(NSInteger)mode;
- (void)presentQuickChatMenu:(NSString *)username;
- (void)advisorTasksChanged:(nullable NSNotification *)notification;
- (void)cancelAdvisorTask:(NSString *)identifier;
- (void)showAdvisorTaskList;
- (void)showAdvisorHistory;
- (void)presentAdvisorChoices:(NSArray<WPAdvisorTask *> *)tasks title:(NSString *)title kind:(NSInteger)kind page:(NSUInteger)page;
- (void)openAdvisorUnread;
- (void)openAdvisorTask:(WPAdvisorTask *)task;
- (void)openAdvisorTask:(WPAdvisorTask *)task fullScreen:(BOOL)fullScreen;
- (void)showAdvisorTask:(WPAdvisorTask *)task;
- (void)applyAdvisorReply:(NSString *)reply send:(BOOL)send;
- (void)seedAdvisorContext;
@end

@implementation WPOverlayController
- (void)loadView { self.view = [[WPCaptureProtectedView alloc] init]; self.view.backgroundColor = UIColor.clearColor; self.view.opaque = NO; }
- (void)viewDidLoad {
    [super viewDidLoad];
    // Capture 0.4.x gesture behavior before the quick-chat switch can change.
    (void)WPConfiguredTapAction(NO);
    self.pet = [[WPPetRenderer alloc] initWithFrame:CGRectMake(0, 0, 88, 96)];
    [self.view addSubview:self.pet];
    // Quick chat: a tap-catching backdrop under the pet, the bar above it.
    self.quickDismiss=[[UIControl alloc] initWithFrame:self.view.bounds];self.quickDismiss.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    self.quickDismiss.hidden=YES;self.quickDismiss.accessibilityLabel=@"收起最近聊天";
    [self.quickDismiss addTarget:self action:@selector(closeQuickChat) forControlEvents:UIControlEventTouchDown];
    [self.view insertSubview:self.quickDismiss belowSubview:self.pet];
    self.quickBar=[[WPQuickChatBar alloc] initWithFrame:CGRectMake(0,0,76,200)];self.quickBar.hidden=YES;
    __weak typeof(self) weakController=self;
    self.quickBar.onSelect=^(NSString *username){[weakController openQuickChat:username];};
    self.quickBar.onSelectWithMode=^(NSString *username,NSInteger mode){[weakController openQuickChat:username mode:mode];};
    [self.view addSubview:self.quickBar];
    self.menu = [[WPRadialMenuView alloc] initWithFrame:self.view.bounds];
    self.menu.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.menu];
    __weak typeof(self) weakSelf = self;
    self.menu.actionHandler = ^(NSString *action) { [weakSelf execute:action]; };
    self.bubble = [[UILabel alloc] init];
    self.bubble.numberOfLines = 0;
    self.bubble.textAlignment = NSTextAlignmentCenter;
    self.bubble.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.bubble.backgroundColor = [UIColor.secondarySystemBackgroundColor colorWithAlphaComponent:.78];
    self.bubble.textColor = UIColor.labelColor;
    self.bubble.layer.cornerRadius = 14;
    self.bubble.layer.masksToBounds = YES;
    self.bubble.hidden = YES;
    self.bubble.userInteractionEnabled = NO;
    [self.view addSubview:self.bubble];
    // Latest unread conversation above the pet.
    self.messageDock=[WPUnreadDockState new];
    self.unreadDot=[[WPOverlayUnreadAvatarControl alloc] initWithFrame:CGRectMake(0,0,36,36)];self.unreadDot.hidden=YES;
    [self.unreadDot addTarget:self action:@selector(openLatestUnreadConversation) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.unreadDot];
    self.chatCount=WPThemeLabel(@"",10,UIFontWeightBold,UIColor.whiteColor);self.chatCount.backgroundColor=UIColor.systemRedColor;
    self.chatCount.textAlignment=NSTextAlignmentCenter;self.chatCount.layer.cornerRadius=9;self.chatCount.clipsToBounds=YES;
    self.chatCount.userInteractionEnabled=NO;self.chatCount.hidden=YES;[self.view addSubview:self.chatCount];
    self.arrivals=[UIView new];self.arrivals.userInteractionEnabled=YES;self.arrivals.hidden=YES;[self.view addSubview:self.arrivals];self.arrivalAvatarJobs=[NSMutableArray new];
    self.advisorObservedTasks=[NSMutableDictionary new];self.advisorAutomaticTasks=[NSMutableSet new];
    self.advisorStatus=[[WPAdvisorStatusView alloc] initWithFrame:self.view.bounds];
    self.advisorStatus.onCancelTask=^(NSString *identifier){[weakSelf cancelAdvisorTask:identifier];};
    self.advisorStatus.onShowTasks=^{[weakSelf showAdvisorTaskList];};
    self.advisorStatus.onOpenUnread=^{[weakSelf openAdvisorUnread];};
    [self.view addSubview:self.advisorStatus];
    UIPanGestureRecognizer *drag = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
    drag.maximumNumberOfTouches = 1;
    UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(hold:)];
    hold.minimumPressDuration = .35;
    hold.allowableMovement = 14;
    [drag requireGestureRecognizerToFail:hold];
    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(doubleTap)];
    doubleTap.numberOfTapsRequired = 2;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tap)];
    [tap requireGestureRecognizerToFail:doubleTap];
    for (UIGestureRecognizer *gesture in @[drag, hold, doubleTap, tap]) [self.pet addGestureRecognizer:gesture];
    self.pet.accessibilityCustomActions = @[
        [[UIAccessibilityCustomAction alloc] initWithName:@"打开桌宠设置" target:self selector:@selector(accessibilitySettings)],
        [[UIAccessibilityCustomAction alloc] initWithName:@"展开快捷菜单" target:self selector:@selector(accessibilityMenu)]];
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(keyboard:) name:UIKeyboardWillChangeFrameNotification object:nil];
    [center addObserver:self selector:@selector(keyboard:) name:UIKeyboardWillHideNotification object:nil];
    [center addObserver:self selector:@selector(reloadPet) name:WPSelectedPetDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(applySettings) name:WPSettingsDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(quickChatChanged:) name:WPQuickChatDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(receiveBarrage:) name:WPMessageBarrageDidReceiveNotification object:nil];
    [center addObserver:self selector:@selector(clearBarrageDock) name:WPBarrageClearDockNotification object:nil];
    [center addObserver:self selector:@selector(chatPresentationChanged:) name:WPChatPresentationDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(barrageMemoryWarning:) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    [center addObserver:self selector:@selector(advisorTasksChanged:) name:WPAdvisorTasksDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(previewBarrage:) name:WPBarragePreviewNotification object:nil];
    [self applySettings];
    [self advisorTasksChanged:nil];
    [self resetIdle];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGSize bounds=self.view.bounds.size;
    if(bounds.width<=0 || bounds.height<=0)return;
    BOOL orientationChanged=self.positioned && ((bounds.width>bounds.height)!=(self.anchorBounds.width>self.anchorBounds.height));
    if(!self.positioned || orientationChanged){
        if(orientationChanged && self.gestureActive)[self cancelActiveGesture];
        self.userAnchor=WPPositionAnchorForBounds(bounds);
        self.positioned=YES;
    }
    self.anchorBounds=bounds;
    // The intended anchor is independent of keyboard/indicator clamps. Returning to
    // a larger safe area restores the user's original position without drift.
    if(!self.gestureActive && !self.edgeTransitioning){
        self.fullCenter=[self clamp:CGPointMake(self.userAnchor.x*bounds.width,self.userAnchor.y*bounds.height)];
        self.pet.center=self.peeking?[self peekCenter]:self.fullCenter;
    }
    [self layoutIndicators];
    if(!self.quickBar.hidden)self.quickBar.frame=[self quickBarFrame];
    if(self.advisorPanel)[self.advisorPanel layoutInBounds:[self safeArea]];
    if(self.positioned && !self.peeking)[self resetIdle];
}
- (void)viewDidAppear:(BOOL)animated {[super viewDidAppear:animated];[self resetIdle];[self seedAdvisorContext];}
- (void)layoutIndicators {
    CGRect safe=[self safeArea];
    CGPoint unreadOffset=WPUnreadAvatarOffset();
    CGPoint unreadCenter=CGPointMake(self.pet.center.x+unreadOffset.x,
                                    CGRectGetMinY(self.pet.frame)-8-self.unreadDot.bounds.size.height/2+unreadOffset.y);
    self.unreadDot.center=WPIndicatorCenter(unreadCenter,self.unreadDot.bounds.size,safe);
    self.chatCount.frame=CGRectMake(CGRectGetMinX(self.pet.frame)-2,CGRectGetMinY(self.pet.frame)-8,24,18);
    [self.advisorStatus setUnreadAvatarFrame:self.unreadDot.hidden?CGRectNull:self.unreadDot.frame];
    [self.advisorStatus layoutInBounds:safe petFrame:self.pet.frame petVisible:!self.pet.hidden && !self.view.hidden];
    [self layoutBubble];
    [self layoutBarrage];
}
- (void)refreshBarrageState {
    BOOL enabled=WPBarrageEnabled();
    if(enabled && !self.barrage){
        self.barrage=[[WPMessageBarrageController alloc] initWithHostView:self.view];
        [self.view insertSubview:self.barrage.view belowSubview:self.pet];
        __weak typeof(self) weakSelf=self;
        self.barrage.onOpenConversation=^(NSString *username){
            if([username isEqual:@"__wp_barrage_preview__"]){[weakSelf showMessage:@"这是一条本机预览，没有发送消息"];return;}
            [[WPOverlayManager sharedManager] closePanel];
            [weakSelf openQuickChat:username];
        };
        self.barrage.onShouldDock=^BOOL(WPBarrageMessage *message){
            [weakSelf.messageDock reconcileConversationUsername:message.conversationUsername unreadState:WPQuickChatUnreadStateForUsername(message.conversationUsername)];
            return [weakSelf.messageDock shouldDockMessage:message];
        };
        self.barrage.onBatchCompleted=^(WPBarrageMessage *message,UIImage *image){
            WPOverlayController *self=weakSelf;
            if(!self || !WPBarrageEnabled() || message.localPreview || WPChatConversationIsVisible(message.conversationUsername))return;
            if([self.messageDock dockMessage:message image:image]){[self updateUnreadDot];[self bounceMessageAvatar];}
        };
        self.barrage.onPlaybackChanged=^(BOOL pending){
            WPOverlayController *self=weakSelf;if(!self)return;
            self.messageDock.playbackPending=pending;
            if(!self.releasingTransientViews)[self updateUnreadDot];
        };
        self.barrage.onPetReaction=^{
            WPOverlayController *strongSelf=weakSelf;
            if(!strongSelf || !WPBarrageReactionsEnabled() || WPBarrageResourceSavingActive() || strongSelf.gestureActive || strongSelf.menu.isShowing || strongSelf.pet.hidden)return;
            CFTimeInterval now=CACurrentMediaTime();
            if(now-strongSelf.lastBarrageReaction<2.5)return;
            if([strongSelf.pet playMessageAcknowledgement])strongSelf.lastBarrageReaction=now;
        };
    }
    [self.barrage refreshPreferences];
    self.barrage.active=enabled && !WPBarrageIsPaused() && !WPBarrageQuietTimeAtDate(NSDate.date) && !self.pet.hidden && !self.view.hidden && self.view.window && !self.view.window.hidden &&
        UIApplication.sharedApplication.applicationState!=UIApplicationStateBackground && !self.releasingTransientViews;
    self.barrage.temporarilySuspended=UIApplication.sharedApplication.applicationState!=UIApplicationStateActive || (self.view.window.windowScene && self.view.window.windowScene.activationState!=UISceneActivationStateForegroundActive);
    [self layoutBarrage];
}
- (void)layoutBarrage {
    if(!self.barrage)return;
    NSMutableArray *obstacles=[[self promptObstacles] mutableCopy];
    if(!self.bubble.hidden)[obstacles addObject:[NSValue valueWithCGRect:self.bubble.frame]];
    if(!self.quickBar.hidden)[obstacles addObject:[NSValue valueWithCGRect:self.quickBar.frame]];
    // Reserve the single dock even before its first avatar is visible.
    [obstacles addObject:[NSValue valueWithCGRect:self.unreadDot.frame]];
    [self.barrage updateLayoutSafeRect:[self barrageSafeArea] obstacles:obstacles dockFrame:self.unreadDot.frame];
}
- (void)receiveBarrage:(NSNotification *)note {
    if(![note.userInfo[@"message"] isKindOfClass:WPBarrageMessage.class])return;
    [WPOverlayManager.sharedManager ensureFloatingOrder];
    [self refreshBarrageState];
    if(!self.barrage.active)return;
    if(WPChatConversationIsVisible(((WPBarrageMessage *)note.userInfo[@"message"]).conversationUsername))return;
    [self clearArrivalDecoration];
    [self.messageDock markBarrageMessageReceived:note.userInfo[@"message"]];
    [self.barrage enqueueMessage:note.userInfo[@"message"]];
    [self resetIdle];
}
- (void)previewBarrage:(NSNotification *)note{
    [self.barragePreviewTimer invalidate];self.barragePreviewTimer=nil;
    if(!WPBarrageEnabled() || WPBarrageIsPaused())return;
    __weak typeof(self) weakSelf=self;
    self.barragePreviewTimer=[NSTimer timerWithTimeInterval:1.2 repeats:NO block:^(__unused NSTimer *timer){
        WPOverlayController *self=weakSelf;if(!self)return;self.barragePreviewTimer=nil;[self refreshBarrageState];
        WPBarrageMessage *message=[WPBarrageMessage new];message.conversationUsername=@"__wp_barrage_preview__";message.senderUsername=message.conversationUsername;
        message.identifier=NSUUID.UUID.UUIDString;message.createdAt=NSDate.date;message.text=@"这是一条本机测试弹幕，点击可查看预览提示";message.localPreview=YES;
        [self.barrage enqueueMessage:message];
    }];[NSRunLoop.mainRunLoop addTimer:self.barragePreviewTimer forMode:NSRunLoopCommonModes];
}
- (void)clearBarrageDock {
    [self.barrage clearDock];[self.messageDock clear];
    [self updateUnreadDot];
}
- (void)barrageMemoryWarning:(NSNotification *)note {
    [self.barrage trimForMemoryPressure];[self.messageDock releaseImageKeepingIdentity];self.barrageDockImage=nil;
    [self.quickBar.layer removeAllAnimations];
}
- (void)updateUnreadDot {
    // One retained indicator receives both native unread snapshots and the final
    // completed message burst. It never creates a second avatar.
    self.messageDock.playbackPending=self.barrage.hasMovingMessages || self.barrage.returningToDock;
    WPQuickChatSession *latest=WPQuickChatMonitor.sharedMonitor.latestObservedUnreadSession;
    NSString *retained=[self.messageDock.conversationUsername copy];
    if(WPChatConversationIsVisible(retained))[self.messageDock clear];
    else if(retained.length)[self.messageDock reconcileConversationUsername:retained unreadState:WPQuickChatUnreadStateForUsername(retained)];
    if(!latest || !WPChatConversationIsVisible(latest.username))[self.messageDock observeUnreadSession:latest genuineArrival:NO];
    NSString *username=self.messageDock.conversationUsername;
    self.barrageDockConversation=WPBarrageEnabled()?username:nil;
    self.barrageDockSender=WPBarrageEnabled()?self.messageDock.senderUsername:nil;
    self.barrageDockImage=WPBarrageEnabled()?self.messageDock.image:nil;
    BOOL visible=(WPBarrageEnabled() || WPUnreadAvatarEnabled()) && self.messageDock.visible && !self.pet.hidden &&
        UIApplication.sharedApplication.applicationState==UIApplicationStateActive && self.view.window && !self.view.window.hidden && !WPChatConversationIsVisible(username);
    self.unreadDot.hidden=!visible;
    if(visible){
        [self.unreadDot showConversationUsername:username senderUsername:self.messageDock.senderUsername?:username image:self.messageDock.image];
        [self.unreadDot setActive:YES];
        if(!WPAllowUnreadPeek())[self revealPet];else [self resetIdle];
        [self.view setNeedsLayout];
    }else{
        [self.unreadDot.layer removeAnimationForKey:@"WPMessageHeadPop123"];
        [self.unreadDot setActive:NO];[self.unreadDot clearAvatar];[self resetIdle];
    }
    [self layoutIndicators];
}
- (void)bounceMessageAvatar {
    [self.unreadDot.layer removeAnimationForKey:@"WPMessageHeadPop123"];
    NSInteger style=WPBarrageCompletionAnimation();
    if(self.unreadDot.hidden || style==3 || UIAccessibilityIsReduceMotionEnabled() || WPBarrageResourceSavingActive())return;
    if(style==1){
        CGPoint target=self.unreadDot.center;
        CABasicAnimation *flight=[CABasicAnimation animationWithKeyPath:@"position"];
        flight.fromValue=[NSValue valueWithCGPoint:CGPointMake(CGRectGetMinX([self barrageSafeArea])-self.unreadDot.bounds.size.width,target.y)];
        flight.toValue=[NSValue valueWithCGPoint:target];flight.duration=.46;
        flight.timingFunction=[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        [self.unreadDot.layer addAnimation:flight forKey:@"WPMessageHeadPop123"];return;
    }
    if(style==2){
        CABasicAnimation *fade=[CABasicAnimation animationWithKeyPath:@"opacity"];fade.fromValue=@0;fade.toValue=@1;fade.duration=.25;
        [self.unreadDot.layer addAnimation:fade forKey:@"WPMessageHeadPop123"];return;
    }
    CAKeyframeAnimation *rise=[CAKeyframeAnimation animationWithKeyPath:@"transform.translation.y"];
    rise.values=@[@18,@(-8),@3,@0];rise.keyTimes=@[@0,@.55,@.8,@1];
    CAKeyframeAnimation *scale=[CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
    scale.values=@[@.45,@1.12,@.96,@1];scale.keyTimes=rise.keyTimes;
    CAAnimationGroup *group=[CAAnimationGroup animation];group.animations=@[rise,scale];group.duration=.48;
    [self.unreadDot.layer addAnimation:group forKey:@"WPMessageHeadPop123"];
}
- (void)chatPresentationChanged:(NSNotification *)note {
    [WPAdvisorContinuousCoordinator.sharedCoordinator refreshAccountIfNeeded];
    [self refreshBarrageState];[self updateUnreadDot];
    [self seedAdvisorContext];
    [WPAdvisorContinuousCoordinator.sharedCoordinator retryPending];
    // The card belongs to one conversation; the saved result remains available.
    if(self.advisorPanel && ![WPChatPresentationActiveUsernameInWindow(self.hostWindow) isEqualToString:self.advisorPanel.conversationUsername])[self closeChatAdvisor];
}
- (void)quickChatChanged:(NSNotification *)note {
    WPQuickChatSession *latest=WPQuickChatMonitor.sharedMonitor.latestObservedUnreadSession;
    if(!latest || !WPChatConversationIsVisible(latest.username))[self.messageDock observeUnreadSession:latest genuineArrival:[note.userInfo[@"arrivals"] containsObject:latest.username?:@""]];
    [self updateUnreadDot];
    NSDictionary *state=[WPQuickChatMonitor.sharedMonitor diagnostics];NSUInteger count=[state[@"alertableUnreadCount"] unsignedIntegerValue];
    if(!count && WPQuickChatMonitor.sharedMonitor.hasAlertableUnread)count=1;
    self.chatCount.hidden=!WPQuickChatEnabled() || !WPQuickChatOptionBool(@"buttonBadge") || !count || self.pet.hidden;
    self.chatCount.text=count>99?@"99+":[NSString stringWithFormat:@"%lu",(unsigned long)count];
    NSArray<NSString *> *arrivals=note.userInfo[@"arrivals"];
    if((arrivals.count || [note.userInfo[@"sessionsUpdated"] boolValue]) && !self.quickBar.hidden)[self.quickBar reloadWithSessions:[WPQuickChatMonitor.sharedMonitor currentSessions]];
    if(arrivals.count && !WPBarrageEnabled() && WPQuickChatEnabled() && (WPQuickChatFlashEnabled() || WPQuickChatOptionBool(@"arrivalAvatar")) && !self.pet.hidden)[self showArrivals:arrivals];
}
/// New messages: come out from the edge, pulse, and show who wrote.
- (void)showArrivals:(NSArray<NSString *> *)usernames {
    if(self.pet.hidden || !usernames.count || !WPQuickChatOptionBool(@"arrivalAvatar"))return;
    NSDate *now=NSDate.date;
    NSMutableArray<NSString *> *allowed=[NSMutableArray new];
    for(NSString *username in usernames)if(WPReminderAllowsUsername(username,now))[allowed addObject:username];
    if(!allowed.count || WPConfiguredReminderIntensity()==WPReminderIntensityAvatarOnly)return;
    usernames=allowed;
    [self revealPet];self.idleGeneration++;
    if(WPConfiguredReminderIntensity()==WPReminderIntensityLight){
        // One existing action, with no extra flash, scale or transient heads.
        [self.pet playSemanticAction:@"tap"];[self resetIdle];return;
    }
    [self clearArrivalDecoration];
    NSUInteger count=MIN(3,usernames.count);CGFloat side=34,step=24;
    for(NSUInteger i=0;i<count;i++){
        NSString *username=usernames[i];UIButton *avatar=[UIButton buttonWithType:UIButtonTypeCustom];[avatar setImage:[self.quickBar avatarForUsername:username side:side] forState:UIControlStateNormal];
        avatar.frame=CGRectMake(i*step,0,side,side);avatar.layer.cornerRadius=side/2;avatar.clipsToBounds=YES;
        avatar.layer.borderWidth=2;avatar.layer.borderColor=UIColor.systemBackgroundColor.CGColor;
        avatar.enabled=WPQuickChatOptionBool(@"arrivalTap");__weak typeof(self) weakSelf=self;
        [avatar addAction:[UIAction actionWithHandler:^(__unused UIAction *action){[weakSelf openQuickChat:username mode:(NSInteger)WPQuickChatOptionNumber(@"openMode")];}] forControlEvents:UIControlEventTouchUpInside];
        [self.arrivals insertSubview:avatar atIndex:0];
        __weak UIButton *weakAvatar=avatar;NSUInteger generation=self.arrivalGeneration;
        WPQuickChatAvatarPreparation *job=WPQuickChatPrepareAvatar(username,96,^(UIImage *image){WPOverlayController *self=weakSelf;if(image && self && generation==self.arrivalGeneration && !self.arrivals.hidden)[weakAvatar setImage:image forState:UIControlStateNormal];});
        [self.arrivalAvatarJobs addObject:job];
    }
    self.arrivals.bounds=CGRectMake(0,0,side+(count-1)*step,side);self.arrivals.hidden=NO;[self layoutArrivals];
    self.arrivals.accessibilityLabel=@"收到新消息";
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification,self.arrivals.accessibilityLabel);
    if(WPQuickChatFlashEnabled() && !WPBarrageResourceSavingActive()){
        [self.pet playSemanticAction:@"tap"];
        CAKeyframeAnimation *pulse=[CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
        pulse.values=@[@1,@1.14,@1,@1.14,@1];pulse.duration=.9;
        CAKeyframeAnimation *flash=[CAKeyframeAnimation animationWithKeyPath:@"opacity"];
        flash.values=@[@1,@.45,@1,@.45,@1];flash.duration=.9;
        [self.pet.layer addAnimation:pulse forKey:@"quickChatPulse"];[self.pet.layer addAnimation:flash forKey:@"quickChatFlash"];
    }
    NSUInteger generation=self.arrivalGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(WPQuickChatOptionNumber(@"arrivalDuration")*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        if(generation!=self.arrivalGeneration)return;self.arrivals.hidden=YES;[self resetIdle];
    });
}
- (void)clearArrivalDecoration {
    self.arrivalGeneration++;
    for(WPQuickChatAvatarPreparation *job in self.arrivalAvatarJobs)[job cancel];[self.arrivalAvatarJobs removeAllObjects];
    self.arrivals.hidden=YES;
    for(UIView *avatar in self.arrivals.subviews)[avatar removeFromSuperview];
    [self.pet.layer removeAnimationForKey:@"quickChatPulse"];
    [self.pet.layer removeAnimationForKey:@"quickChatFlash"];
}
- (void)layoutArrivals {
    if(self.arrivals.hidden)return;
    CGRect safe=[self safeArea];CGSize size=self.arrivals.bounds.size;
    CGFloat y=CGRectGetMinY(self.pet.frame)-size.height-10;
    NSMutableArray *obstacles=[[self promptObstacles] mutableCopy];
    if(!self.bubble.hidden){y=CGRectGetMinY(self.bubble.frame)-size.height-6;[obstacles addObject:[NSValue valueWithCGRect:self.bubble.frame]];}
    self.arrivals.frame=WPOverlayPromptFrame(size,CGPointMake(self.pet.center.x-size.width/2,y),safe,obstacles);
}
- (BOOL)quickBarOnRight {
    CGRect safe=[self safeArea];
    BOOL left=self.fullCenter.x<CGRectGetMidX(safe);
    CGFloat leftEdge=CGRectGetMinX(safe)+self.pet.bounds.size.width/2;
    BOOL attached=fabs(self.fullCenter.x-leftEdge)<24;
    return left && (self.peeking || attached || WPPositionLocked());
}
- (CGRect)quickBarFrame {
    // Matches WeChat's list area: below the navigation bar, above the tab bar.
    UIEdgeInsets insets=self.view.safeAreaInsets;CGRect bounds=self.view.bounds;
    CGFloat top=MAX(insets.top,20)+44,bottom=CGRectGetMaxY(bounds)-insets.bottom-49;
    if(!CGRectIsEmpty(self.keyboardRect))bottom=MIN(bottom,CGRectGetMinY(self.keyboardRect)-8);
    if(bottom-top<160){top=MAX(insets.top,20);bottom=MAX(top+160,CGRectGetMaxY(bounds)-insets.bottom);}
    CGFloat available=MAX(44,bottom-top),height=WPQuickChatOptionNumber(@"height");
    if(height<1)height=available;else height=MAX(44,MIN(available,height));
    CGFloat width=MAX(60,MIN(bounds.size.width-24,WPQuickChatOptionNumber(@"width")));
    CGFloat y=WPQuickChatOptionNumber(@"vertical")==0?top+(available-height)/2:top;
    CGFloat gap=WPQuickChatOptionNumber(@"style")==0?6:0;
    CGFloat x=![self quickBarOnRight]?CGRectGetMinX(bounds)+insets.left+gap:CGRectGetMaxX(bounds)-insets.right-width-gap;
    return CGRectMake(x,y,width,height);
}
- (void)toggleQuickChat {
    if(self.pet.hidden)return;
    if(!self.quickBar.hidden){[self closeQuickChat];return;}
    [self.menu cancel];self.bubble.hidden=YES;self.arrivalGeneration++;self.arrivals.hidden=YES;self.idleGeneration++;
    [self.quickBar reloadWithSessions:[WPQuickChatMonitor.sharedMonitor currentSessions]];
    CGRect frame=[self quickBarFrame];CGFloat offset=([self quickBarOnRight]?1:-1)*(frame.size.width+12);self.quickBar.frame=CGRectOffset(frame,offset,0);
    self.quickBar.hidden=NO;self.quickDismiss.hidden=NO;
    [self refreshBarrageState];
    [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled()?0:.22 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{self.quickBar.frame=frame;} completion:nil];
    UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification,self.quickBar);
}
- (void)closeQuickChat {
    self.quickDismiss.hidden=YES;
    if(self.quickBar.hidden)return;
    CGRect frame=self.quickBar.frame;
    CGFloat offset=([self quickBarOnRight]?1:-1)*(frame.size.width+12);
    [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled()?0:.18 animations:^{self.quickBar.frame=CGRectOffset(frame,offset,0);} completion:^(__unused BOOL finished){
        if(self.quickDismiss.hidden){self.quickBar.hidden=YES;[self resetIdle];}
    }];
}
- (void)openQuickChat:(NSString *)username {
    [self openQuickChat:username mode:(NSInteger)WPQuickChatOptionNumber(@"tapMode")];
}
- (void)openQuickChat:(NSString *)username mode:(NSInteger)mode {
    if(!username.length)return;
    self.hostWindow=[[WPOverlayManager sharedManager] prepareChatHost:self.hostWindow];
    if(mode==2){[self presentQuickChatMenu:username];return;}
    [self closeQuickChat];
    [[WPOverlayManager sharedManager] closePanel];
    __weak typeof(self) weakSelf=self;
    [WPPartnerContact openConversationWithUsername:username inWindow:self.hostWindow presentationMode:(mode==1?1:3) completion:^(BOOL success,NSString *message){if(!success)[weakSelf showMessage:message];}];
}
- (void)presentQuickChatMenu:(NSString *)username{
    self.hostWindow=[[WPOverlayManager sharedManager] prepareChatHost:self.hostWindow];
    UIViewController *presenter=[WPPartnerContact visibleController:self.hostWindow.rootViewController];
    if(!presenter || presenter.transitionCoordinator)return;
    NSString *account=[WPAdvisorCurrentAccountFingerprint() copy];NSString *target=[username copy];
    if(!account.length){[self showMessage:@"无法确认当前微信账号，请稍后再试。"] ;return;}
    __weak typeof(self) weakSelf=self;
    BOOL (^sameAccount)(void)=^BOOL{
        BOOL same=[WPAdvisorCurrentAccountFingerprint() isEqualToString:account];
        if(!same)[weakSelf showMessage:@"微信账号已变化，请重新选择。"];
        return same;
    };
    NSArray *items=@[
        [WPChoiceItem itemWithTitle:@"小窗打开" icon:@"rectangle.bottomhalf.inset.filled" destructive:NO handler:^{if(sameAccount())[weakSelf openQuickChat:target mode:0];}],
        [WPChoiceItem itemWithTitle:@"全屏打开" icon:@"arrow.up.left.and.arrow.down.right" destructive:NO handler:^{if(sameAccount())[weakSelf openQuickChat:target mode:1];}],
        [WPChoiceItem itemWithTitle:@"从快捷聊天移出" icon:@"minus.circle" destructive:YES handler:^{if(sameAccount()){WPQuickChatRemoveUsername(target);[weakSelf resetIdle];}}]];
    WPPresentChoiceSheet(presenter,[self.quickBar titleForUsername:target],items);
}
- (void)openLatestUnreadConversation {
    if((!WPBarrageEnabled() && !WPUnreadAvatarEnabled()) || self.pet.hidden || self.view.hidden || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive)return;
    // Refresh a bounded native window on the actual tap, then freeze the route
    // and revision. A newer arrival during presentation cannot be consumed.
    (void)[WPQuickChatMonitor.sharedMonitor latestUnreadUsername];[self updateUnreadDot];
    NSString *username=[self.messageDock.conversationUsername copy],*revision=[self.messageDock.revision copy];
    if(!username.length || !revision.length)return;
    [self.menu cancel];[self closeQuickChat];
    [[WPOverlayManager sharedManager] closePanel];
    __weak typeof(self) weakSelf=self;
    self.hostWindow=[[WPOverlayManager sharedManager] prepareChatHost:self.hostWindow];
    [WPPartnerContact openConversationWithUsername:username inWindow:self.hostWindow presentationMode:1 completion:^(BOOL success,NSString *message){
        WPOverlayController *self=weakSelf;if(!self)return;
        if(success){[self.messageDock consumeRevision:revision];[self clearArrivalDecoration];[self updateUnreadDot];[self resetIdle];}
        else [self showMessage:message];
    }];
}

- (CGRect)barrageSafeArea {
    UIEdgeInsets insets=self.view.safeAreaInsets;
    insets.top=MAX(insets.top,24);insets.bottom=MAX(insets.bottom,12);
    return CGRectInset(UIEdgeInsetsInsetRect(self.view.bounds,insets),5,5);
}
- (CGRect)safeArea {
    UIEdgeInsets insets = self.view.safeAreaInsets;
    insets.top = MAX(insets.top, 24); insets.bottom = MAX(insets.bottom, 12);
    CGRect safe = UIEdgeInsetsInsetRect(self.view.bounds, insets);
    if (!CGRectIsEmpty(self.keyboardRect) && CGRectIntersectsRect(self.view.bounds, self.keyboardRect))
        safe.size.height = MAX(80, MIN(CGRectGetMaxY(safe), CGRectGetMinY(self.keyboardRect)-8)-safe.origin.y);
    return CGRectInset(safe, 5, 5);
}
- (CGPoint)clamp:(CGPoint)p {
    CGRect safe = [self safeArea];
    CGFloat halfW=self.pet.bounds.size.width/2, halfH=self.pet.bounds.size.height/2;
    CGFloat badgeSpace=0;
    if(!self.unreadDot.hidden)badgeSpace=MAX(badgeSpace,MAX(0,44-WPUnreadAvatarOffset().y));
    badgeSpace=MIN(badgeSpace,MAX(0,safe.size.height-halfH*2));
    if(safe.size.height<halfH*2)p.y=CGRectGetMidY(safe);
    else p.y=MAX(CGRectGetMinY(safe)+halfH+badgeSpace, MIN(CGRectGetMaxY(safe)-halfH,p.y));
    p.x=MAX(CGRectGetMinX(safe)+halfW, MIN(CGRectGetMaxX(safe)-halfW,p.x));
    return p;
}
- (CGPoint)peekCenter {
    CGRect safe=[self safeArea];
    // Keep the entire figure intact; the screen edge naturally occludes it.
    CGFloat visible=MAX(22,self.pet.bounds.size.width*.48);
    BOOL left=self.fullCenter.x<CGRectGetMidX(safe);
    return CGPointMake(left?CGRectGetMinX(safe)-self.pet.bounds.size.width/2+visible:CGRectGetMaxX(safe)+self.pet.bounds.size.width/2-visible,self.fullCenter.y);
}
- (BOOL)canPeek {
    if(!WPOverlayManager.sharedManager.recoveryMaintenanceReady)return NO;
    if(!WPAllowUnreadPeek() && !self.unreadDot.hidden && self.messageDock.visible)return NO;
    if(!WPAllowAdvisorPeek() && self.advisorStatus.unreadCount)return NO;
    if(![WPPreferences() boolForKey:@"autoPeek"] || self.pet.hidden || self.gestureActive || self.menu.isShowing || !self.bubble.hidden)return NO;
    if(!self.quickBar.hidden || !self.arrivals.hidden)return NO;
    if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive || !self.view.window || self.view.window.hidden)return NO;
    CGRect safe=[self safeArea];CGFloat distance=MIN(fabs(self.fullCenter.x-(CGRectGetMinX(safe)+self.pet.bounds.size.width/2)),fabs(self.fullCenter.x-(CGRectGetMaxX(safe)-self.pet.bounds.size.width/2)));
    return distance<24;
}
- (void)resetIdle {
    self.idleGeneration++;
    [self refreshBarrageState];
    if(self.peeking || ![self canPeek]){[self.idleTimer invalidate];self.idleTimer=nil;return;}
    // A single reschedulable timer replaces accumulating delayed blocks from
    // layout/keyboard/unread notifications. No timer runs while the pet is busy.
    if(self.idleTimer){self.idleTimer.fireDate=[NSDate dateWithTimeIntervalSinceNow:3];return;}
    __weak typeof(self) weakSelf=self;
    self.idleTimer=[NSTimer timerWithTimeInterval:3 repeats:NO block:^(__unused NSTimer *timer){
        WPOverlayController *self=weakSelf;if(!self)return;
        self.idleTimer=nil;
        if(![self canPeek])return;
        NSUInteger edgeSerial=++self.edgeMotionSerial;
        self.peeking=YES;
        self.edgeTransitioning=YES;
        [self.pet holdPeekOnLeft:self.fullCenter.x<CGRectGetMidX([self safeArea])];
        [self.pet playSemanticAction:@"retract"];
        [UIView animateWithDuration:.62 delay:0 options:UIViewAnimationOptionBeginFromCurrentState|UIViewAnimationOptionCurveEaseInOut animations:^{self.pet.center=[self peekCenter];[self layoutIndicators];} completion:^(__unused BOOL finished){
            if(self.peeking && edgeSerial==self.edgeMotionSerial){self.edgeTransitioning=NO;self.pet.center=[self peekCenter];}
        }];
    }];
    self.idleTimer.tolerance=.25;[NSRunLoop.mainRunLoop addTimer:self.idleTimer forMode:NSRunLoopCommonModes];
}
- (void)revealPet {
    [self.idleTimer invalidate];self.idleTimer=nil;
    if(self.pet.hidden)return;
    self.idleGeneration++;
    if(!self.peeking)return;
    self.peeking=NO;
    self.edgeTransitioning=YES;NSUInteger edgeSerial=++self.edgeMotionSerial;
    [self.pet endPeek];
    [self.pet playSemanticAction:@"reveal"];
    self.fullCenter=[self clamp:self.fullCenter];
    [UIView animateWithDuration:.62 delay:0 usingSpringWithDamping:.84 initialSpringVelocity:.4 options:UIViewAnimationOptionBeginFromCurrentState animations:^{self.pet.center=self.fullCenter;[self layoutIndicators];} completion:^(__unused BOOL finished){
        if(!self.peeking && edgeSerial==self.edgeMotionSerial){self.edgeTransitioning=NO;self.pet.center=self.fullCenter;[self resetIdle];}
    }];
}
- (void)settleEdgeMotionForGesture {
    if(!self.edgeTransitioning)return;
    self.edgeMotionSerial++;
    [self.pet.layer removeAllAnimations];
    self.pet.center=[self clamp:self.fullCenter];
    self.edgeTransitioning=NO;
}
- (void)applySettings {
    [WPAdvisorContinuousCoordinator.sharedCoordinator refreshAccountIfNeeded];
    CGFloat size = MAX(48, MIN(160, [WPPreferences() doubleForKey:@"petSize"]));
    // Window bounds can still be empty during initial view loading.
    CGFloat available=[self safeArea].size.height;
    if(self.view.bounds.size.height>0 && available>0)size=MIN(size,MAX(32,available)*192/208);
    self.pet.bounds = CGRectMake(0, 0, size, size*208/192);
    self.pet.alpha = MAX(.25, MIN(1, [WPPreferences() doubleForKey:@"petOpacity"]));
    self.pet.hidden = ![WPPreferences() boolForKey:@"enabled"];
    if(WPConfiguredReminderIntensity()!=WPReminderIntensityFull || WPQuietTimeAtDate(NSDate.date) ||
       !WPQuickChatEnabled() || !WPQuickChatFlashEnabled())[self clearArrivalDecoration];
    // Keep the transparent window available for the WeChat Settings entry;
    // hiding its content also removes every floating prompt and touch target.
    self.view.hidden = self.pet.hidden;
    if(self.pet.hidden || !WPQuickChatOptionBool(@"buttonBadge"))self.chatCount.hidden=YES;
    if(self.pet.hidden){
        [self cancelActiveGesture];
        self.bubbleGeneration++;self.arrivalGeneration++;self.menuPreviewGeneration++;
        self.bubble.hidden=YES;self.arrivals.hidden=YES;
        self.quickBar.hidden=YES;self.quickDismiss.hidden=YES;
        [self.pet.layer removeAllAnimations];
        self.edgeMotionSerial++;self.peeking=NO;self.edgeTransitioning=NO;[self.pet endPeek];
        if(self.positioned)self.pet.center=[self clamp:self.fullCenter];
    }
    if(![WPPreferences() boolForKey:@"autoPeek"])[self revealPet];
    if(!WPAllowAdvisorPeek() && self.advisorStatus.unreadCount)[self revealPet];
    [self.pet setAnimationActive:!self.pet.hidden && !WPOverlayManager.sharedManager.recoveryPaused && UIApplication.sharedApplication.applicationState == UIApplicationStateActive];
    if(!WPQuickChatEnabled() || self.pet.hidden)[self closeQuickChat];
    [self.view setNeedsLayout];
    [self refreshBarrageState];
    [self updateUnreadDot];
    [self seedAdvisorContext];
    [self resetIdle];
}
- (void)reloadPet { self.positioned=NO;[self.pet reloadPet]; [self applySettings]; }
- (void)keyboard:(NSNotification *)note {
    CGRect screen=[note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    BOOL hiding=[note.name isEqualToString:UIKeyboardWillHideNotification];
    CGRect converted=self.view.window?[self.view convertRect:screen fromCoordinateSpace:self.view.window.screen.coordinateSpace]:screen;
    self.keyboardRect=hiding || !CGRectIntersectsRect(self.view.bounds,converted)?CGRectZero:converted;
    CGFloat requested=MAX(48,MIN(160,[WPPreferences() doubleForKey:@"petSize"]));
    CGFloat available=MAX(32,[self safeArea].size.height),fitted=MIN(requested,available*192/208);
    self.pet.bounds=CGRectMake(0,0,fitted,fitted*208/192);
    self.gestureInterrupted=YES;self.gestureActive=NO;self.idleGeneration++;
    [self.pet endDragAnimation];[self.menu cancel];
    if(!self.quickBar.hidden)self.quickBar.frame=[self quickBarFrame];
    self.edgeMotionSerial++;self.edgeTransitioning=NO;
    CGSize bounds=self.view.bounds.size;
    if(!self.positioned && bounds.width>0 && bounds.height>0){
        self.userAnchor=WPPositionAnchorForBounds(bounds);self.anchorBounds=bounds;self.positioned=YES;
    }
    self.fullCenter=[self clamp:CGPointMake(self.userAnchor.x*bounds.width,self.userAnchor.y*bounds.height)];
    NSNumber *duration=note.userInfo[UIKeyboardAnimationDurationUserInfoKey];
    NSTimeInterval seconds=duration?MAX(0,MIN(1,duration.doubleValue)):.25;
    [UIView animateWithDuration:seconds delay:0 options:UIViewAnimationOptionBeginFromCurrentState|UIViewAnimationOptionCurveEaseInOut animations:^{
        self.pet.center=self.peeking?[self peekCenter]:self.fullCenter;[self layoutIndicators];
    } completion:nil];
}
- (void)beginShakeAtPoint:(CGPoint)point {
    NSInteger level=WPShakeSensitivityFromPreferenceValue([WPPreferences() objectForKey:@"shakeSensitivity"]);
    if(!self.shake || self.shakeLevel!=level){self.shake=[[WPShakeDetector alloc] initWithSensitivity:level];self.shakeLevel=level;}
    [self.shake beginAtPoint:point time:CACurrentMediaTime()];
}
- (void)performGestureAction:(NSString *)action {
    if ([action isEqualToString:@"quickChat"]) [self performTapAction:WPTapActionQuickChat];
    else if ([action isEqualToString:@"settings"]) [self settings];
    else if ([action isEqualToString:@"advisor"]) [self openChatAdvisor];
    else if ([action isEqualToString:@"advisorDirect"]) [self openDirectChatAdvisor];
    else if ([action isEqualToString:@"advisorHistory"]) [self showAdvisorHistory];
    else if ([action isEqualToString:@"moments"]) [self execute:@"moments"];
}
- (void)shakeDetected {
    NSString *action=WPConfiguredGestureAction(NO);
    if ([action isEqualToString:@"none"]) return;
    [self.pet playSemanticAction:@"shake"];
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
    [self performGestureAction:action];
}
- (void)drag:(UIPanGestureRecognizer *)gesture {
    // UIKit can deliver the old pan's final events after a keyboard frame or
    // rotation interrupted it. They must not save its stale pre-avoidance path.
    if(gesture.state==UIGestureRecognizerStateBegan)self.gestureInterrupted=NO;
    else if(self.gestureInterrupted)return;
    BOOL shakeEnabled=![WPConfiguredGestureAction(NO) isEqualToString:@"none"];
    if(WPPositionLocked()){
        if(gesture.state==UIGestureRecognizerStateBegan){
            [self revealPet];[self settleEdgeMotionForGesture];self.gestureActive=YES;self.idleGeneration++;
            [self.menu cancel];[self beginShakeAtPoint:[gesture locationInView:self.view]];
        }else if(shakeEnabled && gesture.state==UIGestureRecognizerStateChanged && !self.shake.triggered && [self.shake addPoint:[gesture locationInView:self.view] time:CACurrentMediaTime()]){
            [self shakeDetected];
        }
        if(gesture.state==UIGestureRecognizerStateEnded || gesture.state==UIGestureRecognizerStateCancelled || gesture.state==UIGestureRecognizerStateFailed){self.gestureActive=NO;[self resetIdle];}
        return;
    }
    if(gesture.state==UIGestureRecognizerStateBegan){[self revealPet];[self settleEdgeMotionForGesture];self.gestureActive=YES;self.idleGeneration++;[self.pet beginDragAnimation];}
    if (gesture.state == UIGestureRecognizerStateBegan) { self.dragStart=self.pet.center; [self.menu cancel]; [self beginShakeAtPoint:[gesture locationInView:self.view]]; }
    if (shakeEnabled && self.shake.triggered){[self.pet endDragAnimation];self.gestureActive=NO;return;}
    if (shakeEnabled && gesture.state == UIGestureRecognizerStateChanged && [self.shake addPoint:[gesture locationInView:self.view] time:CACurrentMediaTime()]) {
        // A shake is not a move: put the pet back and keep the saved position.
        gesture.enabled=NO;gesture.enabled=YES;
        [UIView animateWithDuration:.18 animations:^{self.pet.center=[self clamp:self.dragStart];[self layoutIndicators];}];
        [self.pet endDragAnimation];
        [self shakeDetected];
        self.gestureActive=NO;[self resetIdle];
        return;
    }
    CGPoint t=[gesture translationInView:self.view];
    CGFloat previousX=self.pet.center.x;
    self.pet.center=[self clamp:CGPointMake(self.dragStart.x+t.x,self.dragStart.y+t.y)];
    CGFloat movedX=self.pet.center.x-previousX;
    if(gesture.state==UIGestureRecognizerStateChanged && fabs(movedX)>.01)
        [self.pet updateDragDirectionLeft:movedX<0];
    [self layoutIndicators];
    if (gesture.state == UIGestureRecognizerStateCancelled || gesture.state == UIGestureRecognizerStateFailed) {
        [self.pet endDragAnimation];
        CGSize bounds=self.view.bounds.size;
        self.fullCenter=[self clamp:CGPointMake(self.userAnchor.x*bounds.width,self.userAnchor.y*bounds.height)];
        self.pet.center=self.fullCenter;self.gestureActive=NO;[self layoutIndicators];[self resetIdle];
        return;
    }
    if (gesture.state == UIGestureRecognizerStateEnded) {
        [self.pet endDragAnimation];
        CGPoint end=self.pet.center;
        end.x=end.x<self.view.bounds.size.width/2 ? self.pet.bounds.size.width/2+10 : self.view.bounds.size.width-self.pet.bounds.size.width/2-10;
        end=[self clamp:end];
        [UIView animateWithDuration:.2 animations:^{self.pet.center=end;[self layoutIndicators];}];
        if(self.view.bounds.size.width>0 && self.view.bounds.size.height>0){
            self.userAnchor=CGPointMake(end.x/self.view.bounds.size.width,end.y/self.view.bounds.size.height);
            WPStorePositionAnchor(self.userAnchor,self.view.bounds.size);
        }
        self.fullCenter=end;self.gestureActive=NO;[self resetIdle];
        [self.pet playSemanticAction:@"land"];
    }
}
- (void)hold:(UILongPressGestureRecognizer *)gesture {
    CGPoint p=[gesture locationInView:self.view];
    NSString *action=WPConfiguredGestureAction(YES);
    BOOL menu=[action isEqualToString:@"menu"];
    if (gesture.state==UIGestureRecognizerStateBegan) {
        if ([action isEqualToString:@"none"]) return;
        [self revealPet]; [self settleEdgeMotionForGesture]; self.gestureActive=YES; self.idleGeneration++;
        self.gestureInterrupted=NO; self.menuPreviewGeneration++;
        if (menu) {
            self.menu.userInteractionEnabled=YES; self.bubble.hidden=YES; [self closeQuickChat];
            [self.menu showAroundPoint:self.pet.center inBounds:[self safeArea]]; [self refreshBarrageState];
        }
        [self.pet playSemanticAction:@"longPress"];
        [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    } else if (gesture.state==UIGestureRecognizerStateChanged && menu && self.gestureActive) {
        [self.menu updateFingerAtPoint:p];
    } else if (gesture.state==UIGestureRecognizerStateEnded) {
        BOOL active=self.gestureActive && !self.gestureInterrupted; self.gestureActive=NO;
        if (active && menu) { [self.menu updateFingerAtPoint:p]; [self.menu finishTracking]; }
        else { [self.menu cancel]; if(active) [self performGestureAction:action]; }
        [self resetIdle];
    } else if (gesture.state==UIGestureRecognizerStateCancelled || gesture.state==UIGestureRecognizerStateFailed) {
        [self.menu cancel]; self.gestureActive=NO; [self resetIdle];
    }
}
- (void)cancelActiveGesture{self.gestureInterrupted=YES;self.gestureActive=NO;self.idleGeneration++;[self.pet endDragAnimation];[self.menu cancel];[self closeQuickChat];}
- (void)releaseTransientViews {
    self.releasingTransientViews=YES;
    [self.barragePreviewTimer invalidate];self.barragePreviewTimer=nil;
    [self.idleTimer invalidate];self.idleTimer=nil;
    self.barrage.active=NO;[self.messageDock releaseImageKeepingIdentity];self.barrageDockImage=nil;
    [self closeChatAdvisor];
    [self cancelActiveGesture];
    self.bubbleGeneration++;self.menuPreviewGeneration++;self.idleGeneration++;
    self.bubble.hidden=YES;self.bubble.text=nil;
    [self clearArrivalDecoration];
    // A background animation may not complete until foreground. Hide and purge
    // the bar synchronously so its avatars and rows are released now.
    [self.quickBar.layer removeAllAnimations];
    self.quickDismiss.hidden=YES;self.quickBar.hidden=YES;
    [self.unreadDot setActive:NO];
    self.releasingTransientViews=NO;
}
- (void)performTapAction:(WPTapAction)action {
    if(self.peeking){[self revealPet];if(!WPQuickChatOptionBool(@"edgeTapActions"))return;}
    if(action == WPTapActionSettings){[self settings];return;}
    if(action == WPTapActionChatAdvisor){[self openChatAdvisor];return;}
    if(action == WPTapActionDirectAdvisor){[self openDirectChatAdvisor];return;}
    [self.pet playSemanticAction:@"tap"];
    if(action == WPTapActionQuickChat){
        if(WPQuickChatEnabled())[self toggleQuickChat];
        else [self showMessage:@"请先在快捷设置中开启便捷聊天浮窗。"];
        return;
    }
    if(WPQuickChatEnabled())[self toggleQuickChat];
    else [self showMessage:@"请先在快捷设置中开启便捷聊天浮窗。"] ;
}
- (void)tap { [self performTapAction:WPConfiguredTapAction(NO)]; }
- (void)doubleTap { [self performTapAction:WPConfiguredTapAction(YES)]; }
- (void)settings { if(self.peeking){[self revealPet];return;}[self closeQuickChat];[[WPOverlayManager sharedManager] openSettings]; }
- (BOOL)accessibilitySettings { [self settings]; return YES; }
- (BOOL)accessibilityMenu { [self.menu showAroundPoint:self.pet.center inBounds:[self safeArea]];[self refreshBarrageState]; return YES; }
- (void)execute:(NSString *)action {
    if(![WPMenuAvailableActions() containsObject:action])return;
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
    if([@[@"contact1",@"contact2",@"contact3"] containsObject:action]){
        NSString *username=WPMenuContactUsername(action);
        if(username.length)[self openQuickChat:username mode:WPMenuContactPresentationMode()];
        else [self showMessage:@"请先在长按菜单设置中选择联系人。"];
        return;
    }
    if([action isEqualToString:@"advisor"]){[self openChatAdvisor];return;}
    if([action isEqualToString:@"advisorDirect"]){[self openDirectChatAdvisor];return;}
    if([action isEqualToString:@"advisorHistory"]){[self showAdvisorHistory];return;}
    if([action isEqualToString:@"quickChat"]){[self performTapAction:WPTapActionQuickChat];return;}
    if([action isEqualToString:@"settings"]){[self settings];return;}
    if([action isEqualToString:@"read"])[self showMessage:@"正在一键已读…"];
    __weak typeof(self) weakSelf=self;
    [WPActionAdapter performAction:action inWindow:self.hostWindow completion:^(BOOL success, NSString *message) {
        [weakSelf showMessage:message]; if([action isEqualToString:@"read"])WPSendDevelopmentDiagnostics();
    }];
}
- (UIViewController *)visibleChatController {
    UIWindow *host=self.hostWindow;
    return host && !host.hidden?WPChatPresentationVisibleChatController(host.rootViewController,host):nil;
}
- (void)seedAdvisorContext {
    if(!NSThread.isMainThread || !self.isViewLoaded)return;
    UIViewController *chat=[self visibleChatController];NSString *username=WPChatPresentationUsernameForController(chat);
    if(!username.length || ![WPAdvisorContinuousCoordinator.sharedCoordinator isEnabledForUsername:username])return;
    if(![WPChatPresentationActiveUsernameInWindow(self.hostWindow) isEqualToString:username])return;
    NSArray *lines=[WPChatAdvisor transcriptForChatController:chat username:username limit:40 route:NULL];
    if(lines.count)[WPAdvisorContextStore.sharedStore seedUsername:username visibleLines:lines];
}
- (void)submitAdvisorPreset:(NSString *)identifier account:(NSString *)account username:(NSString *)username {
    self.hostWindow=[[WPOverlayManager sharedManager] prepareChatHost:self.hostWindow];
    if(!WPAdvisorSelectionIsCurrent(account,username,self.hostWindow)){[self showMessage:@"微信账号或聊天已变化，请重新选择。"] ;return;}
    UIViewController *current=[self visibleChatController];
    NSArray<WPChatLine *> *lines=[WPChatAdvisor transcriptForChatController:current username:username limit:WPChatAdvisor.contextCount route:NULL];
    if(!lines){[self showMessage:@"当前微信版本暂时无法读取聊天记录。"] ;return;}
    if(!lines.count){[self showMessage:@"这个聊天里还没有可分析的消息。"] ;return;}
    [self closeChatAdvisor];NSString *name=[WPPartnerContact displayNameForUsername:username]?:@"联系人";
    WPAdvisorTask *task=[WPAdvisorTaskCenter.sharedCenter submitUsername:username displayName:name lines:lines group:WPChatAdvisorIsGroupUsername(username) presetIdentifier:identifier];
    if(!task)[self showMessage:@"无法创建分析任务，请检查账号并稍后再试。"] ;else [self advisorTasksChanged:nil];
}
- (void)openChatAdvisor { [self openChatAdvisorDirect:NO]; }
- (void)openDirectChatAdvisor { [self openChatAdvisorDirect:YES]; }
- (void)openChatAdvisorDirect:(BOOL)direct {
    [self closeQuickChat];
    if(!WPChatAdvisor.isReady){[self showMessage:WPChatAdvisor.hasAPIKey?@"聊天参谋未启用，可在设置首页打开。":@"请先在设置首页的「聊天参谋」里填写 API Key。"];return;}
    if(!WPAdvisorCurrentAccountFingerprint().length){[self showMessage:@"无法确认当前微信账号，暂不能分析。"] ;return;}
    self.hostWindow=[[WPOverlayManager sharedManager] prepareChatHost:self.hostWindow];
    NSString *username=[WPChatPresentationUsernameForController([self visibleChatController]) copy];
    if(!username.length){[self closeChatAdvisor];[self showMessage:@"先打开一个聊天，再让参谋分析。"];return;}
    NSString *account=[WPAdvisorCurrentAccountFingerprint() copy];
    if(direct){[self submitAdvisorPreset:WPChatAdvisor.currentPreset.identifier account:account username:username];return;}
    UIViewController *presenter=[WPPartnerContact visibleController:self.hostWindow.rootViewController];
    if(!presenter || !presenter.view.window){[self showMessage:@"暂时无法打开聊天场景选择。"] ;return;}
    NSDictionary *symbols=@{@"couple":@"heart.fill",@"flirt":@"sparkles",@"friend":@"bubble.left.and.bubble.right.fill",@"work":@"briefcase.fill",@"eq":@"hand.raised.fill",@"humor":@"face.smiling.fill",@"calm":@"leaf.fill",@"custom":@"slider.horizontal.3"};
    __weak typeof(self) weakSelf=self;NSMutableArray *items=[NSMutableArray new];
    for(WPChatAdvisorPreset *preset in WPChatAdvisorPreset.builtinPresets){
        NSString *identifier=[preset.identifier copy];
        [items addObject:[WPChoiceItem itemWithTitle:preset.title icon:symbols[identifier] destructive:NO handler:^{[weakSelf submitAdvisorPreset:identifier account:account username:username];}]];
    }
    WPPresentChoiceSheet(presenter,@"选择聊天场景",items);
}
- (void)showAdvisorTask:(WPAdvisorTask *)task {
    if(!WPAdvisorTaskBelongsToCurrentAccount(task) || !task.advice || ![WPChatPresentationActiveUsernameInWindow(self.hostWindow) isEqualToString:task.username])return;
    BOOL requiresFresh=[WPAdvisorContinuousCoordinator.sharedCoordinator requiresFreshAnalysisForUsername:task.username];
    if(requiresFresh){
        NSArray *current=[WPChatAdvisor transcriptForChatController:[self visibleChatController] username:task.username limit:task.lineCount route:NULL];
        if(!WPAdvisorTaskMatchesLines(task,current))[WPAdvisorTaskCenter.sharedCenter markStaleForUsername:task.username];
    }
    if(!self.advisorPanel){
        WPChatAdvisorPanel *panel=[[WPChatAdvisorPanel alloc] initWithFrame:CGRectZero];
        __weak typeof(self) weakSelf=self;
        panel.onClose=^{[weakSelf closeChatAdvisor];};
        panel.onRetry=^{[weakSelf openChatAdvisor];};
        panel.onPickReply=^(NSString *reply){[weakSelf applyAdvisorReply:reply send:NO];};
        panel.onSendReply=^(NSString *reply){[weakSelf applyAdvisorReply:reply send:YES];};
        [self.view insertSubview:panel belowSubview:self.pet];
        self.advisorPanel=panel;
    }
    self.advisorDisplayedTask=task;self.advisorPanel.conversationUsername=task.username;
    self.advisorPanel.taskPresetTitle=task.presetIdentifier.length?[WPChatAdvisorPreset presetWithIdentifier:task.presetIdentifier].title:nil;
    [self.advisorPanel showAdvice:task.advice lineCount:task.lineCount];[self.advisorPanel layoutInBounds:[self safeArea]];
    [WPAdvisorTaskCenter.sharedCenter markResultRead:task];
    if(requiresFresh && task.stale)[self showMessage:@"这条建议生成后又有新消息，可重新分析。"];
}
- (void)finishAdvisorReply:(NSString *)reply task:(WPAdvisorTask *)task send:(BOOL)send attempt:(NSUInteger)attempt {
    if(!WPAdvisorTaskBelongsToCurrentAccount(task)){[self closeChatAdvisor];[self showMessage:@"微信账号已变化，没有执行操作。"] ;return;}
    UIViewController *chat=[self visibleChatController];
    if(![WPChatPresentationActiveUsernameInWindow(self.hostWindow) isEqualToString:task.username]){
        if(send){[self closeChatAdvisor];[self showMessage:@"聊天已切换，没有执行操作。"] ;return;}
        if(attempt<12){__weak typeof(self) weakSelf=self;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,200*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[weakSelf finishAdvisorReply:reply task:task send:send attempt:attempt+1];});}
        else [self showMessage:@"没有找到对应聊天，未填入回复。"];return;
    }
    BOOL requiresFresh=[WPAdvisorContinuousCoordinator.sharedCoordinator requiresFreshAnalysisForUsername:task.username];
    if(send && requiresFresh){NSArray *current=[WPChatAdvisor transcriptForChatController:chat username:task.username limit:task.lineCount route:NULL];
        if(task.stale || !WPAdvisorTaskMatchesLines(task,current)){[WPAdvisorTaskCenter.sharedCenter markStaleForUsername:task.username];[self showMessage:@"有新消息，请重新分析后再发送。"] ;return;}}
    WPAdvisorReplyOutcome outcome=WPAdvisorApplyReply(reply,task.username,chat,NO);
    if(outcome==WPAdvisorReplyFilled && send){[self trySendAdvisorReply:reply task:task attempt:0];return;}
    switch(outcome){
        case WPAdvisorReplyFilled:[self closeChatAdvisor];break;
        case WPAdvisorReplyDraftPresent:[self showMessage:@"输入框有未发送的草稿，请先处理草稿。"] ;break;
        case WPAdvisorReplyWrongChat:[self closeChatAdvisor];[self showMessage:@"聊天已切换，没有执行操作。"] ;break;
        default:[self showMessage:@"当前微信版本无法识别聊天输入框。"] ;break;
    }
}
- (void)trySendAdvisorReply:(NSString *)reply task:(WPAdvisorTask *)task attempt:(NSUInteger)attempt {
    if(!WPAdvisorTaskBelongsToCurrentAccount(task)){[self closeChatAdvisor];[self showMessage:@"微信账号已变化，内容保留在输入框。"] ;return;}
    UIViewController *chat=[self visibleChatController];
    BOOL requiresFresh=[WPAdvisorContinuousCoordinator.sharedCoordinator requiresFreshAnalysisForUsername:task.username];
    if(requiresFresh){NSArray *current=[WPChatAdvisor transcriptForChatController:chat username:task.username limit:task.lineCount route:NULL];
        if(task.stale || !WPAdvisorTaskMatchesLines(task,current)){[WPAdvisorTaskCenter.sharedCenter markStaleForUsername:task.username];[self showMessage:@"聊天已更新，内容保留在输入框。"] ;return;}}
    WPAdvisorReplyOutcome outcome=WPAdvisorSendFilledReply(reply,task.username,chat);
    if(outcome==WPAdvisorReplySendUnavailable && attempt<15){__weak typeof(self) weakSelf=self;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[weakSelf trySendAdvisorReply:reply task:task attempt:attempt+1];});return;}
    [self closeChatAdvisor];
    if(outcome==WPAdvisorReplySendTriggered)[self showMessage:@"已触发发送，请留意聊天结果。"];else [self showMessage:@"未能自动发送，请检查聊天输入框。"];
}
- (void)applyAdvisorReply:(NSString *)reply send:(BOOL)send {
    WPAdvisorTask *task=self.advisorDisplayedTask;if(!task || !WPAdvisorTaskBelongsToCurrentAccount(task))return;
    if(send){[self finishAdvisorReply:reply task:task send:YES attempt:0];return;}
    WPAdvisorReplyOutcome check=WPAdvisorCheckReplyInput(task.username,[self visibleChatController]);
    if(check!=WPAdvisorReplyFilled){[self showMessage:check==WPAdvisorReplyDraftPresent?@"输入框有未发送的草稿，请先处理草稿。":@"无法确认当前聊天输入框。"] ;return;}
    [self closeChatAdvisor];[self closeQuickChat];
    __weak typeof(self) weakSelf=self;
    [WPPartnerContact openConversationWithUsername:task.username inWindow:self.hostWindow presentationMode:1 completion:^(BOOL success,NSString *message){
        if(!success){[weakSelf showMessage:message?:@"无法打开聊天，未填入回复。"] ;return;}
        [weakSelf finishAdvisorReply:reply task:task send:NO attempt:0];
    }];
}
- (void)closeChatAdvisor {
    [self.advisorPanel removeFromSuperview];self.advisorPanel=nil;self.advisorDisplayedTask=nil;
}
- (WPAdvisorTask *)advisorTaskWithIdentifier:(NSString *)identifier {
    WPAdvisorTaskCenter *center=WPAdvisorTaskCenter.sharedCenter;
    for(WPAdvisorTask *task in [center.activeTasks arrayByAddingObjectsFromArray:[center.history arrayByAddingObjectsFromArray:center.failedTasks]])
        if([task.identifier isEqualToString:identifier])return task;
    return nil;
}
- (void)advisorTasksChanged:(NSNotification *)notification {
    WPAdvisorTaskCenter *center=WPAdvisorTaskCenter.sharedCenter;
    if(self.advisorDisplayedTask && !WPAdvisorTaskBelongsToCurrentAccount(self.advisorDisplayedTask))[self closeChatAdvisor];
    NSMutableArray *items=[NSMutableArray new];
    for(WPAdvisorTask *task in center.activeTasks){
        self.advisorObservedTasks[task.identifier]=task;
        [items addObject:@{@"identifier":task.identifier,@"displayName":task.displayName,@"state":task.state==WPAdvisorTaskQueued?@"排队中":@"生成中"}];
    }
    for(WPAdvisorTask *task in center.failedTasks)
        [items addObject:@{@"identifier":task.identifier,@"displayName":task.displayName,@"state":@"失败 · 点击查看"}];
    [self.advisorStatus updateActiveTasks:items];[self.advisorStatus updateUnreadCount:center.unreadResults.count];
    [self.advisorStatus setUnreadAvatarFrame:self.unreadDot.hidden?CGRectNull:self.unreadDot.frame];
    [self.advisorStatus layoutInBounds:[self safeArea] petFrame:self.pet.frame petVisible:!self.pet.hidden && !self.view.hidden];
    if(!WPAllowAdvisorPeek() && self.advisorStatus.unreadCount)[self revealPet];else [self resetIdle];
    for(NSString *identifier in self.advisorObservedTasks.allKeys.copy){
        WPAdvisorTask *task=self.advisorObservedTasks[identifier];
        if(task.state==WPAdvisorTaskQueued || task.state==WPAdvisorTaskRunning)continue;
        BOOL automatic=[self.advisorAutomaticTasks containsObject:identifier];
        [self.advisorAutomaticTasks removeObject:identifier];[self.advisorObservedTasks removeObjectForKey:identifier];
        [WPAdvisorContinuousCoordinator.sharedCoordinator taskDidFinishForUsername:task.username];
        if(automatic && task.state==WPAdvisorTaskCompleted && [WPChatPresentationActiveUsernameInWindow(self.hostWindow) isEqualToString:task.username])
            [self showAdvisorTask:task];
    }
}
- (void)cancelAdvisorTask:(NSString *)identifier {
    WPAdvisorTask *task=[self advisorTaskWithIdentifier:identifier];if(!task)return;
    if(task.state==WPAdvisorTaskFailed){[self showMessage:task.error?:@"分析失败，请重试。"];[WPAdvisorTaskCenter.sharedCenter dismissFailedTask:task];return;}
    [WPAdvisorTaskCenter.sharedCenter cancelTask:task];
}
- (NSArray<NSDictionary *> *)advisorRecords:(NSArray<WPAdvisorTask *> *)tasks {
    NSMutableArray *records=[NSMutableArray new];
    for(WPAdvisorTask *task in tasks){
        BOOL requiresFresh=[WPAdvisorContinuousCoordinator.sharedCoordinator requiresFreshAnalysisForUsername:task.username];
        NSString *detail=task.state==WPAdvisorTaskQueued?@"排队中":task.state==WPAdvisorTaskRunning?@"生成中":task.state==WPAdvisorTaskFailed?(task.error?:@"分析失败"):((requiresFresh && task.stale)?@"有新消息，建议已过期":@"查看分析与建议");
        [records addObject:@{@"identifier":task.identifier,@"displayName":task.displayName,@"detail":detail,@"unread":@(task.unread),@"createdAt":task.createdAt}];
    }
    return records;
}
- (void)presentAdvisorList:(NSArray<WPAdvisorTask *> *)tasks title:(NSString *)title kind:(NSInteger)kind {
    self.hostWindow=[[WPOverlayManager sharedManager] prepareChatHost:self.hostWindow];
    UIViewController *presenter=[WPPartnerContact visibleController:self.hostWindow.rootViewController];
    if(!presenter || presenter.transitionCoordinator)return;
    WPAdvisorHistoryController *list=[[WPAdvisorHistoryController alloc] initWithTitle:title records:[self advisorRecords:tasks] allowsClear:kind==2];
    WPAdaptiveNavigationController *navigation=[[WPAdaptiveNavigationController alloc] initWithRootViewController:list];
    __weak typeof(self) weakSelf=self;__weak WPAdvisorHistoryController *weakList=list;
    list.onSelect=^(NSString *identifier){
        [weakList dismissViewControllerAnimated:YES completion:^{
            WPAdvisorTask *task=[weakSelf advisorTaskWithIdentifier:identifier];if(!task)return;
            if(kind==0)[weakSelf cancelAdvisorTask:identifier];
            else [weakSelf openAdvisorTask:task fullScreen:kind==2];
        }];
    };
    list.onClear=^{[WPAdvisorTaskCenter.sharedCenter clearHistory];[weakList updateRecords:@[]];};
    [presenter presentViewController:navigation animated:YES completion:nil];
}
- (void)showAdvisorTaskList {
    WPAdvisorTaskCenter *center=WPAdvisorTaskCenter.sharedCenter;
    [self presentAdvisorChoices:[center.activeTasks arrayByAddingObjectsFromArray:center.failedTasks] title:@"分析任务 · 点击取消或查看" kind:0 page:0];
}
- (void)showAdvisorHistory {
    [self closeQuickChat];[self presentAdvisorList:WPAdvisorTaskCenter.sharedCenter.history title:@"聊天参谋记录" kind:2];
}
- (void)openAdvisorUnread {
    NSArray *results=WPAdvisorTaskCenter.sharedCenter.unreadResults;
    if(results.count==1)[self openAdvisorTask:results.firstObject fullScreen:YES];
    else if(results.count)[self presentAdvisorChoices:results title:@"选择聊天参谋结果" kind:1 page:0];
}
- (void)presentAdvisorChoices:(NSArray<WPAdvisorTask *> *)tasks title:(NSString *)title kind:(NSInteger)kind page:(NSUInteger)page {
    self.hostWindow=[[WPOverlayManager sharedManager] prepareChatHost:self.hostWindow];
    UIViewController *presenter=[WPPartnerContact visibleController:self.hostWindow.rootViewController];
    if(!presenter || !tasks.count)return;
    const NSUInteger pageSize=50;NSUInteger start=MIN(page*pageSize,tasks.count),end=MIN(start+pageSize,tasks.count);
    if(start>=end)return;
    __weak typeof(self) weakSelf=self;NSMutableArray *items=[NSMutableArray new];
    for(NSUInteger i=start;i<end;i++){
        WPAdvisorTask *task=tasks[i];NSString *identifier=[task.identifier copy];
        NSString *suffix=kind==0?(task.state==WPAdvisorTaskFailed?@" · 查看失败":@" · 取消"): @"";
        NSString *label=[(task.displayName.length?task.displayName:@"联系人") stringByAppendingString:suffix];
        [items addObject:[WPChoiceItem itemWithTitle:label icon:kind==0?@"xmark.circle":@"bubble.left.fill" destructive:kind==0 && task.state!=WPAdvisorTaskFailed handler:^{
            WPAdvisorTask *current=[weakSelf advisorTaskWithIdentifier:identifier];if(!current)return;
            if(kind==0)[weakSelf cancelAdvisorTask:identifier];else [weakSelf openAdvisorTask:current fullScreen:YES];
        }]];
    }
    if(page>0)[items addObject:[WPChoiceItem itemWithTitle:@"上一页" icon:@"chevron.left" destructive:NO handler:^{[weakSelf presentAdvisorChoices:tasks title:title kind:kind page:page-1];}]];
    if(end<tasks.count)[items addObject:[WPChoiceItem itemWithTitle:@"下一页" icon:@"chevron.right" destructive:NO handler:^{[weakSelf presentAdvisorChoices:tasks title:title kind:kind page:page+1];}]];
    WPPresentChoiceSheet(presenter,title,items);
}
- (void)waitForAdvisorTask:(WPAdvisorTask *)task attempt:(NSUInteger)attempt {
    if(!WPAdvisorTaskBelongsToCurrentAccount(task) || ![WPAdvisorTaskCenter.sharedCenter.history containsObject:task])return;
    self.hostWindow=[[WPOverlayManager sharedManager] prepareChatHost:self.hostWindow];
    if([WPChatPresentationActiveUsernameInWindow(self.hostWindow) isEqualToString:task.username]){[self showAdvisorTask:task];return;}
    if(attempt>=12){[self showMessage:@"没有找到对应聊天，结果已保留。"] ;return;}
    __weak typeof(self) weakSelf=self;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,200*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[weakSelf waitForAdvisorTask:task attempt:attempt+1];});
}
- (void)openAdvisorTask:(WPAdvisorTask *)task {
    [self openAdvisorTask:task fullScreen:YES];
}
- (void)openAdvisorTask:(WPAdvisorTask *)task fullScreen:(BOOL)fullScreen {
    if(!WPAdvisorTaskBelongsToCurrentAccount(task) || !task.advice)return;
    self.hostWindow=[[WPOverlayManager sharedManager] prepareChatHost:self.hostWindow];
    // A same-conversation native sheet still needs to be dismissed when the
    // history entry explicitly requests full screen. The native full-screen
    // adapter handles both that case and an already-full-screen conversation.
    if(!fullScreen && [WPChatPresentationActiveUsernameInWindow(self.hostWindow) isEqualToString:task.username]){[self showAdvisorTask:task];return;}
    [self closeQuickChat];[[WPOverlayManager sharedManager] closePanel];
    __weak typeof(self) weakSelf=self;
    [WPPartnerContact openConversationWithUsername:task.username inWindow:self.hostWindow presentationMode:fullScreen?1:3 completion:^(BOOL success,NSString *message){
        if(!success){[weakSelf showMessage:message?:@"无法打开聊天，结果已保留。"] ;return;}
        [weakSelf waitForAdvisorTask:task attempt:0];
    }];
}
- (void)layoutBubble {
    CGRect safe=[self safeArea];CGFloat width=MAX(1,MIN(194,safe.size.width));
    CGSize measured=[self.bubble sizeThatFits:CGSizeMake(width-20,180)];
    CGFloat height=MAX(42,measured.height+18);
    CGFloat x=self.pet.center.x-width/2;
    CGFloat y=self.pet.frame.origin.y-height-8;
    self.bubble.frame=WPOverlayPromptFrame(CGSizeMake(width,height),CGPointMake(x,y),safe,[self promptObstacles]);
    [self layoutArrivals];
}
- (NSArray<NSValue *> *)promptObstacles {
    NSMutableArray *rects=[NSMutableArray arrayWithObject:[NSValue valueWithCGRect:self.pet.frame]];
    if(!self.unreadDot.hidden)[rects addObject:[NSValue valueWithCGRect:self.unreadDot.frame]];
    return rects;
}
- (void)showMessage:(NSString *)text {
    if(self.pet.hidden)return;
    [self revealPet];self.idleGeneration++;
    self.bubble.text=text; self.bubble.hidden=NO; [self layoutBubble];
    NSUInteger generation=++self.bubbleGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3*NSEC_PER_SEC),dispatch_get_main_queue(),^{ if(self.bubbleGeneration==generation){self.bubble.hidden=YES;[self resetIdle];} });
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification,text);
}
- (void)dealloc { [self.idleTimer invalidate];[self.barragePreviewTimer invalidate];[NSNotificationCenter.defaultCenter removeObserver:self]; }
@end

@interface WPOverlayManager ()
@property (nonatomic) NSMapTable<id, WPOverlayWindow *> *windows;
@property (nonatomic) WPOverlayWindow *legacyWindow;
@property (nonatomic) BOOL started;
@property (nonatomic, weak) UIWindow *previousKeyWindow;
@property (nonatomic) UIWindow *settingsWindow;
@property (nonatomic) BOOL foreground;
@property(nonatomic) WPRecoveryCoordinator *recovery;
@property(nonatomic) BOOL captureReady;
@property(nonatomic) BOOL rendererReady;
@property(nonatomic) BOOL monitorReady;
@property(nonatomic) BOOL maintenanceReady;
@property(nonatomic) NSUInteger preparedGeneration;
@property(nonatomic) NSMutableSet<NSString *> *degradedFeatures;
@property(nonatomic) NSMutableSet<NSString *> *advisorContextHints;
@end

@implementation WPOverlayManager
+ (instancetype)sharedManager { static id instance; static dispatch_once_t once; dispatch_once(&once,^{instance=[self new];}); return instance; }
- (void)start {
    if(self.started)return; self.started=YES;
    WPBarrageStartEnvironmentMonitor();
    self.windows=[NSMapTable weakToStrongObjectsMapTable];
    self.degradedFeatures=[NSMutableSet new];
    self.advisorContextHints=[NSMutableSet new];
    [self configureRecovery];
    [self configureAdvisorContinuous];
    NSNotificationCenter *center=NSNotificationCenter.defaultCenter;
    for(NSString *name in @[UIApplicationDidBecomeActiveNotification,UIApplicationWillResignActiveNotification,UIApplicationDidFinishLaunchingNotification,UISceneDidActivateNotification,UISceneWillDeactivateNotification,UIWindowDidBecomeVisibleNotification,UIWindowDidBecomeKeyNotification])
        [center addObserver:self selector:@selector(stateChanged:) name:name object:nil];
    [center addObserver:self selector:@selector(sceneDisconnected:) name:UISceneDidDisconnectNotification object:nil];
    [center addObserver:self selector:@selector(background:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [center addObserver:self selector:@selector(performAction:) name:@"WeChatPet.PerformAction" object:nil];
    [center addObserver:self selector:@selector(updateQuickChat) name:WPSettingsDidChangeNotification object:nil];
    // Source health is observational. Re-entering setActive from its synchronous
    // health notification can recursively install a missing private hook.
    [self refresh];
}
- (NSArray<WPOverlayController *> *)controllers {
    NSMutableArray *result=[NSMutableArray new];
    for(WPOverlayWindow *window in self.windows.objectEnumerator)if(window.rootViewController)[result addObject:window.rootViewController];
    if(self.legacyWindow.rootViewController)[result addObject:self.legacyWindow.rootViewController];
    return result;
}
- (void)configureAdvisorContinuous {
    WPAdvisorContinuousCoordinator *coordinator=WPAdvisorContinuousCoordinator.sharedCoordinator;
    __weak typeof(self) weakSelf=self;
    coordinator.onIncoming=^(NSString *username){[WPAdvisorTaskCenter.sharedCenter markStaleForUsername:username];};
    coordinator.onMessage=^(NSString *username,NSString *identifier,NSTimeInterval timestamp,NSString *text){
        [WPAdvisorContextStore.sharedStore appendIncomingForUsername:username identifier:identifier text:text date:[NSDate dateWithTimeIntervalSince1970:timestamp]];
    };
    coordinator.isBusy=^BOOL(NSString *username){for(WPAdvisorTask *task in WPAdvisorTaskCenter.sharedCenter.activeTasks)if([task.username isEqualToString:username])return YES;return NO;};
    coordinator.onReady=^BOOL(NSString *username){
        WPOverlayManager *self=weakSelf;if(!self || self.recoveryPaused || ![WPPreferences() boolForKey:@"enabled"] || !WPChatAdvisor.isReady)return NO;
        NSArray<WPOverlayController *> *controllers=[self controllers];if(!controllers.count)return NO;
        for(WPOverlayController *controller in controllers)if([WPChatPresentationActiveUsernameInWindow(controller.hostWindow) isEqualToString:username])[controller seedAdvisorContext];
        NSArray *lines=[WPAdvisorContextStore.sharedStore snapshotForUsername:username];
        if(!lines.count){
            if(![self.advisorContextHints containsObject:username]){[self.advisorContextHints addObject:username];[self showMessage:@"请先打开已锁定的聊天，读取上下文后会继续分析。"];}
            return NO;
        }
        [self.advisorContextHints removeObject:username];
        WPAdvisorTask *task=[WPAdvisorTaskCenter.sharedCenter submitUsername:username displayName:[WPPartnerContact displayNameForUsername:username]?:@"联系人" lines:lines group:NO];
        if(!task)return NO;
        for(WPOverlayController *controller in controllers){[controller.advisorAutomaticTasks addObject:task.identifier];[controller advisorTasksChanged:nil];}
        return YES;
    };
}
- (BOOL)applicationIsAvailable {
    if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive)return NO;
    NSSet *scenes=UIApplication.sharedApplication.connectedScenes;
    if(!scenes.count)return YES;
    for(UIScene *scene in scenes)if([scene isKindOfClass:UIWindowScene.class] && scene.activationState==UISceneActivationStateForegroundActive)return YES;
    return NO;
}
- (void)configureRecovery {
    self.recovery=[WPRecoveryCoordinator new];__weak typeof(self) weakSelf=self;
    self.recovery.calibrateHost=^BOOL{return [weakSelf calibrateExistingWindows];};
    self.recovery.captureMessages=^{
        WPOverlayManager *self=weakSelf;if(!self || self.recoveryPaused)return;
        self.captureReady=YES;[self updateQuickChat];
    };
    self.recovery.restoreRenderer=^{
        WPOverlayManager *self=weakSelf;if(!self || self.recoveryPaused)return;
        self.rendererReady=YES;[self restoreFloatingWindows];
    };
    self.recovery.restoreMonitoring=^{
        WPOverlayManager *self=weakSelf;if(!self || self.recoveryPaused)return;
        self.monitorReady=YES;[self updateQuickChat];
    };
    self.recovery.restoreMaintenance=^{
        WPOverlayManager *self=weakSelf;if(!self || self.recoveryPaused)return;
        self.maintenanceReady=YES;
        [NSNotificationCenter.defaultCenter postNotificationName:@"WeChatPet.RecoveryMaintenance" object:nil];
        for(WPOverlayController *controller in [self controllers]){[controller resetIdle];}
    };
    self.recovery.phaseFailed=^(NSString *phase){
        WPOverlayManager *self=weakSelf;if(!self)return;[self.degradedFeatures addObject:phase];
        if([phase isEqual:@"capture"]){self.captureReady=NO;[WPMessageBarrageSource.sharedSource setActive:NO];}
        else if([phase isEqual:@"monitor"]){self.monitorReady=NO;[WPQuickChatMonitor.sharedMonitor setActive:NO];}
        else if([phase isEqual:@"maintenance"]){self.maintenanceReady=NO;}
        else if([phase isEqual:@"host"] || [phase isEqual:@"renderer"]){
            self.rendererReady=NO;
            for(WPOverlayWindow *window in self.windows.objectEnumerator)window.hidden=YES;
            self.legacyWindow.hidden=YES;
        }
    };
}
- (void)stateChanged:(NSNotification *)notification {
    if([notification.object isKindOfClass:WPOverlayWindow.class])return;
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{[self stateChanged:notification];});return;}
    [WPAdvisorContinuousCoordinator.sharedCoordinator refreshAccountIfNeeded];
    BOOL transient=[notification.name isEqual:UIApplicationWillResignActiveNotification] || [notification.name isEqual:UISceneWillDeactivateNotification];
    if(transient){
        if([notification.name isEqual:UISceneWillDeactivateNotification]){
            for(UIScene *scene in UIApplication.sharedApplication.connectedScenes)if(scene!=notification.object && scene.activationState==UISceneActivationStateForegroundActive)return;
        }
        [self.recovery setTemporarilySuspended:YES];WPQuickChatSetForegroundAvailable(NO);WPSESetForegroundAvailable(NO);[WPMessageBarrageSource.sharedSource setForegroundAvailable:NO];
        for(WPOverlayController *controller in [self controllers]){controller.barrage.temporarilySuspended=YES;[controller.pet setAnimationActive:NO];}
        return;
    }
    if([self applicationIsAvailable] && !self.recoveryPaused){
        self.foreground=YES;WPQuickChatSetForegroundAvailable(YES);WPSESetForegroundAvailable(YES);[WPMessageBarrageSource.sharedSource setForegroundAvailable:YES];
        BOOL resumed=self.recovery.temporarilySuspended;
        if(!self.recovery.foreground){[self.degradedFeatures removeAllObjects];[self.recovery beginForeground];}
        else [self.recovery setTemporarilySuspended:NO];
        if(resumed && self.rendererReady)for(WPOverlayController *controller in [self controllers]){
            controller.barrage.temporarilySuspended=NO;[controller.pet setAnimationActive:!controller.pet.hidden];[controller resetIdle];
        }
        [self.recovery requestCalibration];
    }else if(UIApplication.sharedApplication.applicationState==UIApplicationStateBackground)[self background:nil];
}
- (BOOL)calibrateExistingWindows {
    if(self.recoveryPaused || ![self applicationIsAvailable])return NO;
    BOOL hostReady=NO;BOOL needsRenderer=NO;BOOL fresh=self.preparedGeneration!=self.recovery.generation;
    if(fresh)self.preparedGeneration=self.recovery.generation;
    NSSet *scenes=UIApplication.sharedApplication.connectedScenes;
    for(UIScene *scene in scenes){
        if(![scene isKindOfClass:UIWindowScene.class] || scene.activationState!=UISceneActivationStateForegroundActive)continue;
        UIWindow *host=[self hostForScene:(id)scene];hostReady|=host!=nil;
        WPOverlayWindow *window=[self.windows objectForKey:scene];
        needsRenderer|=host!=nil && (!window || window.hidden);
        if(window){
            WPOverlayController *controller=(id)window.rootViewController;if(host)controller.hostWindow=host;
            if(fresh){[controller releaseTransientViews];window.hidden=YES;}
            if(window.isKeyWindow && host)[host makeKeyWindow];
        }
    }
    if(!scenes.count){
        UIWindow *host=[self hostForScene:nil];hostReady=host!=nil;
        needsRenderer=host!=nil && (!self.legacyWindow || self.legacyWindow.hidden);
        if(self.legacyWindow){WPOverlayController *controller=(id)self.legacyWindow.rootViewController;if(host)controller.hostWindow=host;
            if(fresh){[controller releaseTransientViews];self.legacyWindow.hidden=YES;}
            if(self.legacyWindow.isKeyWindow && host)[host makeKeyWindow];}
    }else if(self.legacyWindow){self.legacyWindow.hidden=YES;self.legacyWindow=nil;}
    if(hostReady){self.preparedGeneration=self.recovery.generation;self.foreground=YES;}
    [self ensureFloatingOrder];
    if(self.rendererReady && !fresh && needsRenderer)[self restoreFloatingWindows];
    return hostReady;
}
- (CGFloat)floatingLevelForScene:(UIWindowScene *)scene {
    CGFloat level=UIWindowLevelAlert+1;
    NSArray *windows=scene?scene.windows:UIApplication.sharedApplication.windows;
    for(UIWindow *window in windows){
        if([window isKindOfClass:WPOverlayWindow.class] || window==self.settingsWindow || window.hidden || !window.rootViewController)continue;
        // Keyboard, selection and system effect windows must retain their own
        // ordering. Only normal app content/modal windows influence this level.
        NSString *name=NSStringFromClass(window.class);
        BOOL system=NO;
        for(NSString *part in @[@"Keyboard",@"TextEffects",@"StatusBar",@"Remote",@"Snapshot",@"Selection",@"Callout",@"Loupe"])
            if([name containsString:part]){system=YES;break;}
        CGFloat candidate=window.windowLevel;
        if(!system && isfinite(candidate) && candidate<100000)level=MAX(level,candidate+1);
    }
    return level;
}
- (void)ensureFloatingOrder {
    for(WPOverlayWindow *window in self.windows.objectEnumerator){
        CGFloat level=[self floatingLevelForScene:window.windowScene];
        if(window.windowLevel!=level)window.windowLevel=level;
        CGRect frame=window.windowScene?window.windowScene.coordinateSpace.bounds:window.screen.bounds;
        if(!CGRectIsEmpty(frame) && !CGRectEqualToRect(frame,window.frame))window.frame=frame;
    }
    if(self.legacyWindow){
        CGFloat level=[self floatingLevelForScene:nil];if(self.legacyWindow.windowLevel!=level)self.legacyWindow.windowLevel=level;
    }
}
- (UIWindow *)hostForScene:(UIWindowScene *)scene {
    UIWindow *candidate;
    NSArray *windows=scene ? scene.windows : UIApplication.sharedApplication.windows;
    for(UIWindow *window in windows){
        if([window isKindOfClass:WPOverlayWindow.class] || window==self.settingsWindow || window.hidden || !window.rootViewController)continue;
        NSString *name=NSStringFromClass(window.class);BOOL system=NO;
        for(NSString *part in @[@"Keyboard",@"TextEffects",@"StatusBar",@"Remote",@"Snapshot",@"Selection",@"Callout",@"Loupe"])
            if([name containsString:part]){system=YES;break;}
        if(system)continue;
        // A plugin can present a real page in a window above Alert. Treating
        // every such window as absent incorrectly disables message reception.
        NSString *root=NSStringFromClass(window.rootViewController.class);
        if([name containsString:@"Overlay"] || [name containsString:@"Danmaku"] || [root containsString:@"Overlay"])continue;
        if(!candidate || window.windowLevel>candidate.windowLevel || (window.windowLevel==candidate.windowLevel && window.isKeyWindow))candidate=window;
    }return candidate;
}
- (WPOverlayWindow *)makeWindow:(UIWindowScene *)scene host:(UIWindow *)host {
    WPOverlayWindow *window=scene ? [[WPOverlayWindow alloc] initWithWindowScene:scene] : [[WPOverlayWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    window.frame=scene ? scene.coordinateSpace.bounds : UIScreen.mainScreen.bounds;
    window.backgroundColor=UIColor.clearColor;window.opaque=NO;
    window.windowLevel=[self floatingLevelForScene:scene];
    WPOverlayController *controller=[WPOverlayController new];controller.hostWindow=host;
    window.rootViewController=controller;
    window.hidden=NO; // Deliberately never becomes key during normal floating operation.
    return window;
}
- (void)refresh {
    if(!self.started || self.recoveryPaused)return;
    if([self applicationIsAvailable]){self.foreground=YES;if(!self.recovery.foreground){WPSESetForegroundAvailable(YES);WPQuickChatSetForegroundAvailable(YES);[WPMessageBarrageSource.sharedSource setForegroundAvailable:YES];[self.degradedFeatures removeAllObjects];[self.recovery beginForeground];}[self.recovery requestCalibration];}
    else if(UIApplication.sharedApplication.applicationState==UIApplicationStateBackground)[self background:nil];
}
- (void)restoreFloatingWindows {
    if(!self.started || self.recoveryPaused || !self.rendererReady)return;
    BOOL any=NO;
    for(UIScene *scene in UIApplication.sharedApplication.connectedScenes){
        if(![scene isKindOfClass:UIWindowScene.class])continue;
        UIWindowScene *windowScene=(id)scene;
        BOOL active=scene.activationState==UISceneActivationStateForegroundActive;
        BOOL visible=active || scene.activationState==UISceneActivationStateForegroundInactive;
        WPOverlayWindow *overlay=[self.windows objectForKey:scene];
        UIWindow *host=[self hostForScene:windowScene];
        if(!overlay && active && host){overlay=[self makeWindow:windowScene host:host];[self.windows setObject:overlay forKey:scene];}
        BOOL wasHidden=overlay.hidden;
        if(overlay){overlay.hidden=!visible;if(host)((WPOverlayController *)overlay.rootViewController).hostWindow=host;
            if(!visible)[(WPOverlayController *)overlay.rootViewController releaseTransientViews];
            [((WPOverlayController *)overlay.rootViewController).pet setAnimationActive:active && !((WPOverlayController *)overlay.rootViewController).pet.hidden];
            [(WPOverlayController *)overlay.rootViewController updateUnreadDot];}
        if(overlay && active && wasHidden){WPOverlayController *controller=(id)overlay.rootViewController;[controller revealPet];[controller resetIdle];}
        // Window handoff during a foreground page transition can briefly have
        // no host candidate. Keep the one existing overlay and receive source.
        any|=active && (host!=nil || overlay!=nil);
    }
    if(UIApplication.sharedApplication.connectedScenes.count==0){
        UIWindow *host=[self hostForScene:nil];
        if(host && !self.legacyWindow)self.legacyWindow=[self makeWindow:nil host:host];
        BOOL active=UIApplication.sharedApplication.applicationState==UIApplicationStateActive;
        BOOL visible=UIApplication.sharedApplication.applicationState!=UIApplicationStateBackground;
        BOOL wasHidden=self.legacyWindow.hidden;self.legacyWindow.hidden=!visible;
        if(!visible)[(WPOverlayController *)self.legacyWindow.rootViewController releaseTransientViews];
        [((WPOverlayController *)self.legacyWindow.rootViewController).pet setAnimationActive:active && !((WPOverlayController *)self.legacyWindow.rootViewController).pet.hidden];any=active;
        [(WPOverlayController *)self.legacyWindow.rootViewController updateUnreadDot];
        if(active && wasHidden){WPOverlayController *controller=(id)self.legacyWindow.rootViewController;[controller revealPet];[controller resetIdle];}
    }
    self.foreground=any;[self ensureFloatingOrder];
    for(WPOverlayController *controller in [self controllers]){[controller refreshBarrageState];[controller resetIdle];}
}
- (void)updateQuickChat {
    BOOL active=self.foreground && !self.recoveryPaused && [WPPreferences() boolForKey:@"enabled"];
    BOOL messages=active && WPBarrageEnabled() && !WPBarrageIsPaused() && !WPBarrageQuietTimeAtDate(NSDate.date);
    [WPMessageBarrageSource.sharedSource setActive:self.captureReady && messages && ![self.degradedFeatures containsObject:@"capture"]];
    [WPQuickChatMonitor.sharedMonitor setActive:self.monitorReady && active && ![self.degradedFeatures containsObject:@"monitor"] && (WPQuickChatEnabled() || WPUnreadAvatarEnabled() || messages)];
    if(self.rendererReady)for(WPOverlayController *controller in [self controllers])[controller refreshBarrageState];
}
- (void)sceneDisconnected:(NSNotification *)note {
    WPOverlayWindow *window=[self.windows objectForKey:note.object];window.hidden=YES;
    [(WPOverlayController *)window.rootViewController releaseTransientViews];[((WPOverlayController *)window.rootViewController).pet setAnimationActive:NO];
    [self.windows removeObjectForKey:note.object];
    BOOL remaining=NO;for(UIScene *scene in UIApplication.sharedApplication.connectedScenes)if(scene!=note.object && scene.activationState==UISceneActivationStateForegroundActive)remaining=YES;
    if(!remaining && UIApplication.sharedApplication.connectedScenes.count)[self background:nil];else [self refresh];
}
- (void)background:(NSNotification *)note {
    [self.recovery endForeground];self.captureReady=self.rendererReady=self.monitorReady=self.maintenanceReady=NO;
    self.foreground=NO;WPQuickChatSetForegroundAvailable(NO);WPSESetForegroundAvailable(NO);[WPMessageBarrageSource.sharedSource setForegroundAvailable:NO];[self updateQuickChat];
    for(WPOverlayWindow *window in self.windows.objectEnumerator){window.hidden=YES;[(WPOverlayController *)window.rootViewController releaseTransientViews];[((WPOverlayController *)window.rootViewController).pet setAnimationActive:NO];[((WPOverlayController *)window.rootViewController).unreadDot setActive:NO];}
    self.legacyWindow.hidden=YES;[(WPOverlayController *)self.legacyWindow.rootViewController releaseTransientViews];[((WPOverlayController *)self.legacyWindow.rootViewController).pet setAnimationActive:NO];[((WPOverlayController *)self.legacyWindow.rootViewController).unreadDot setActive:NO];
}
- (BOOL)recoveryMaintenanceReady{return !self.started || self.maintenanceReady;}
- (BOOL)recoveryPaused{return [WPPreferences() boolForKey:@"recoveryPaused"];}
- (void)setRecoveryPaused:(BOOL)paused {
    if(paused==self.recoveryPaused)return;[WPPreferences() setBool:paused forKey:@"recoveryPaused"];
    if(paused)[self background:nil];else [self retryRecovery];
}
- (void)retryRecovery {
    if(self.recoveryPaused)[WPPreferences() setBool:NO forKey:@"recoveryPaused"];
    [self background:nil];[self.degradedFeatures removeAllObjects];
    if([self applicationIsAvailable]){self.foreground=YES;WPQuickChatSetForegroundAvailable(YES);WPSESetForegroundAvailable(YES);[WPMessageBarrageSource.sharedSource setForegroundAvailable:YES];[self.recovery beginForeground];}
}
- (NSDictionary<NSString *,id> *)recoveryDiagnostics {
    NSMutableDictionary *diagnostics=[self.recovery diagnostics].mutableCopy?:[NSMutableDictionary new];
    diagnostics[@"manualPause"]=@(self.recoveryPaused);diagnostics[@"degradedFeatures"]=self.degradedFeatures.allObjects?:@[];
    NSMutableArray *windows=[NSMutableArray new];
    NSMutableArray *all=self.windows.objectEnumerator.allObjects.mutableCopy?:[NSMutableArray new];if(self.legacyWindow)[all addObject:self.legacyWindow];
    for(WPOverlayWindow *window in all){if(windows.count>=8)break;
        [windows addObject:@{@"class":NSStringFromClass(window.class),@"rootClass":window.rootViewController?NSStringFromClass(window.rootViewController.class):@"none",@"key":@(window.isKeyWindow),@"hidden":@(window.hidden),@"level":@(window.windowLevel),@"sceneState":@(window.windowScene?window.windowScene.activationState:-1),@"lastHitClass":window.lastHitClass?:@"none",@"hitCount":@(window.touchHits),@"forwarded":@(window.forwardedTouches)}];
    }diagnostics[@"windows"]=windows;return diagnostics;
}
- (WPOverlayWindow *)activeWindow {
    for(WPOverlayWindow *window in self.windows.objectEnumerator)if(!window.hidden)return window;
    return self.legacyWindow;
}
- (void)showMessage:(NSString *)text { [(WPOverlayController *)[self activeWindow].rootViewController showMessage:text]; }
- (void)performAction:(NSNotification *)note {
    if(![@[@"read",@"moments"] containsObject:note.object])return;
    [(WPOverlayController *)[self activeWindow].rootViewController execute:note.object];
}
- (void)openSettings {
    if(self.settingsWindow)return;
    WPSettingsController *settings=[WPSettingsController new];
    __weak typeof(self) weakSelf=self;settings.onClose=^{[weakSelf closePanel];};[self presentPanel:settings];
}
- (void)previewMenuRadius {
    WPOverlayController *controller=(id)[self activeWindow].rootViewController;if(!controller)return;
    if(controller.pet.hidden)return;
    [controller.menu showAroundPoint:controller.pet.center inBounds:[controller safeArea]];
    controller.menu.userInteractionEnabled=NO;
    NSUInteger generation=++controller.menuPreviewGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,1400*NSEC_PER_MSEC),dispatch_get_main_queue(),^{if(controller.menuPreviewGeneration==generation){[controller.menu cancel];controller.menu.userInteractionEnabled=YES;}});
}
- (void)closePanel {
    if(!self.settingsWindow)return;
    UIWindowScene *scene=self.settingsWindow.windowScene;
    UIWindow *restore=[self hostForScene:scene];
    if(!restore && self.previousKeyWindow && !self.previousKeyWindow.hidden)restore=self.previousKeyWindow;
    [self.settingsWindow endEditing:YES];self.settingsWindow.hidden=YES;self.settingsWindow=nil;self.previousKeyWindow=nil;
    if(restore && !restore.hidden)[restore makeKeyWindow];
}
- (UIWindow *)prepareChatHost:(UIWindow *)preferred {
    UIWindow *previous=self.previousKeyWindow;
    UIWindowScene *scene=preferred.windowScene?:self.settingsWindow.windowScene;
    [self closePanel];
    UIWindow *host=[self hostForScene:scene];
    if(!host && preferred && !preferred.hidden)host=preferred;
    if(!host && previous && !previous.hidden)host=previous;
    if(host && !host.isKeyWindow)[host makeKeyWindow];
    [self ensureFloatingOrder];return host;
}
- (void)presentPanel:(UIViewController *)settings {
    WPOverlayWindow *window=[self activeWindow];
    if(self.settingsWindow)return;
    UIWindow *host=window?((WPOverlayController *)window.rootViewController).hostWindow:nil;
    if(!host){for(UIScene *scene in UIApplication.sharedApplication.connectedScenes)if([scene isKindOfClass:UIWindowScene.class] && scene.activationState==UISceneActivationStateForegroundActive){host=[self hostForScene:(id)scene];if(host)break;}}
    if(!host)host=[self hostForScene:nil];if(!host)return;
    UIWindowScene *scene=window.windowScene?:host.windowScene;
    for(UIWindow *w in (scene?scene.windows:UIApplication.sharedApplication.windows))if(w.isKeyWindow)self.previousKeyWindow=w;
    if(!self.previousKeyWindow)self.previousKeyWindow=host;
    UINavigationController *navigation=[[WPAdaptiveNavigationController alloc] initWithRootViewController:settings];
    WPApplyThemeToNavigation(navigation);
    UIWindow *panel=scene ? [[UIWindow alloc] initWithWindowScene:scene] : [[UIWindow alloc] initWithFrame:host.bounds];
    // Inherit the current system appearance; UIKit updates the panel live.
    panel.frame=scene?scene.coordinateSpace.bounds:host.frame;panel.windowLevel=UIWindowLevelAlert+.5;panel.rootViewController=navigation;
    self.settingsWindow=panel;
    [panel makeKeyAndVisible];
}
@end

void WPStartPlugin(void){dispatch_async(dispatch_get_main_queue(),^{[[WPOverlayManager sharedManager] start];static dispatch_once_t once;dispatch_once(&once,^{dispatch_after(dispatch_time(DISPATCH_TIME_NOW,8*NSEC_PER_SEC),dispatch_get_main_queue(),^{WPSendDevelopmentDiagnostics();});});});}

#ifndef WP_PREVIEW_HOST
__attribute__((constructor)) static void WPPluginEntry(void) {
    @autoreleasepool {
        // Restrict automatic injection entry to WeChat; the preview host starts explicitly.
        if(![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.tencent.xin"])return;
        WPStartPlugin();
    }
}
#endif
