#import "WPChat124Checks.h"
#import "WPPartnerContact.h"
#import "WPResizableChat.h"
#import "WPChatPresentationState.h"
#import "WPCommon.h"
#import <math.h>
#import <objc/runtime.h>
#if defined(WP_PREVIEW_HOST)
@class CContact;
@interface QuickReplyMsgMgr : NSObject
@property(nonatomic) NSUInteger routeCalls;
@property(nonatomic) NSUInteger fixtureMode;
+ (instancetype)sharedManager;
@end
@interface WP124ChatContentFixture : UITableViewController
@property(nonatomic,strong) CContact *contact;
@property(nonatomic,copy) NSString *actualUsername;
@property(nonatomic) BOOL omitGetter;
@end
@implementation WP124ChatContentFixture
- (NSString *)getCurrentChatName{return self.omitGetter?nil:self.actualUsername;}
- (void)viewDidLoad{[super viewDidLoad];self.title=@"原生小窗聊天内容";[self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"m"];
    UITextField *field=[[UITextField alloc] initWithFrame:CGRectMake(0,0,200,44)];field.accessibilityIdentifier=@"WP124NativeInput";self.tableView.tableHeaderView=field;}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{return 40;}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath{UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"m" forIndexPath:indexPath];cell.textLabel.text=@"原生聊天记录";return cell;}
@end
@interface WP124NativeWrapper : UIViewController
@property(nonatomic,strong) UIViewController *nativeContent;
@property(nonatomic,strong) UIViewController *toolbar;
@property(nonatomic) NSTimeInterval mountDelay;
@property(nonatomic) BOOL responderOnly;
@end
@implementation WP124NativeWrapper
- (void)viewDidLoad{
    [super viewDidLoad];self.view.backgroundColor=UIColor.systemBackgroundColor;
    self.toolbar=[UIViewController new];self.toolbar.view.backgroundColor=UIColor.secondarySystemBackgroundColor;
    [self addChildViewController:self.toolbar];[self.view addSubview:self.toolbar.view];[self.toolbar didMoveToParentViewController:self];
    for(NSUInteger index=0;index<3;index++){UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];[button setTitle:@[@"关闭",@"弹出",@"全屏"][index] forState:UIControlStateNormal];button.frame=CGRectMake(8+index*70,16,64,30);[self.toolbar.view addSubview:button];}
    if(self.mountDelay>0)dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(self.mountDelay*NSEC_PER_SEC)),dispatch_get_main_queue(),^{[self mountContent];});else [self mountContent];
}
- (void)mountContent{
    if(!self.responderOnly)[self addChildViewController:self.nativeContent];
    [self.view insertSubview:self.nativeContent.view belowSubview:self.toolbar.view];
    if(!self.responderOnly)[self.nativeContent didMoveToParentViewController:self];
    [self.view setNeedsLayout];[self.view layoutIfNeeded];
}
- (void)viewDidLayoutSubviews{[super viewDidLayoutSubviews];self.toolbar.view.frame=CGRectMake(0,0,CGRectGetWidth(self.view.bounds),56);self.nativeContent.view.frame=CGRectMake(0,56,CGRectGetWidth(self.view.bounds),MAX(0,CGRectGetHeight(self.view.bounds)-56));}
@end
void WPChat124PresentFixture(id contact, UIViewController *presenter, NSUInteger mode){
    WP124ChatContentFixture *chat=[WP124ChatContentFixture new];chat.contact=contact;chat.actualUsername=mode==4?@"wxid_contract_wrong":[contact valueForKey:@"m_nsUsrName"];chat.omitGetter=mode==2;
    WP124NativeWrapper *wrapper=[WP124NativeWrapper new];wrapper.nativeContent=chat;wrapper.modalPresentationStyle=mode==5?UIModalPresentationFullScreen:UIModalPresentationPageSheet;wrapper.mountDelay=mode==3?1.35:0;wrapper.responderOnly=mode==6;
    [presenter presentViewController:wrapper animated:YES completion:nil];
}
@interface WP124ChatRun : NSObject
@property(nonatomic,strong) UIWindow *window;
@property(nonatomic,strong) UIViewController *host;
@property(nonatomic,strong) NSMutableDictionary *checks;
@property(nonatomic,copy) void (^completion)(NSDictionary *);
@property(nonatomic,strong) id oldHeight;
@property(nonatomic) NSUInteger mode;
@property(nonatomic) NSUInteger callbacks;
@property(nonatomic) NSTimeInterval began;
@end
@implementation WP124ChatRun
- (void)checkFullscreenIdentity {
    // A correctly typed native push may silently do nothing. Exercise the real
    // adapter with only its native I/O boundary replaced, then restore it.
    Class logic=NSClassFromString(@"MMMsgLogicManager");SEL selector=NSSelectorFromString(@"PushOtherBaseMsgControllerByContact:navigationController:animated:");
    Method method=class_getInstanceMethod(logic,selector);
    if(!method){self.checks[@"CH124FullscreenNoOpFixtureAvailable"]=@NO;self.completion(self.checks);return;}
    __block NSUInteger calls=0;IMP original=method_getImplementation(method);
    IMP replacement=imp_implementationWithBlock(^(__unused id target,__unused id contact,__unused UINavigationController *navigation,__unused BOOL animated){calls++;});
    method_setImplementation(method,replacement);
    UIViewController *root=[UIViewController new];root.view.backgroundColor=UIColor.systemBackgroundColor;
    UINavigationController *navigation=[[UINavigationController alloc] initWithRootViewController:root];self.window.rootViewController=navigation;[self.window makeKeyAndVisible];
    NSTimeInterval began=NSProcessInfo.processInfo.systemUptime;__block NSUInteger delivered=0;
    [WPPartnerContact openConversationWithUsername:@"wxid_contract_aria" inWindow:self.window presentationMode:1 completion:^(BOOL success,__unused NSString *message){
        delivered++;method_setImplementation(method,original);imp_removeBlock(replacement);
        self.checks[@"CH124FullscreenNoOpNeverReportsSuccess"]=@(!success && calls==1 && delivered==1 && NSProcessInfo.processInfo.systemUptime-began>=3.9);
        self.checks[@"CH124FullscreenFailureKeepsOriginalNativePage"]=@(navigation.topViewController==root && navigation.viewControllers.count==1 && !root.presentedViewController);
        [WPPartnerContact openConversationWithUsername:@"wxid_contract_aria" inWindow:self.window presentationMode:1 completion:^(BOOL opened,__unused NSString *detail){
            self.checks[@"CH124FullscreenSuccessRequiresExactVisibleTarget"]=@(opened && [WPChatPresentationActiveUsernameInWindow(self.window) isEqual:@"wxid_contract_aria"]);
            self.window.rootViewController=self.host;[self.window makeKeyAndVisible];self.completion(self.checks);
        }];
    }];
}
- (void)start{self.host=self.window.rootViewController;self.checks=[NSMutableDictionary new];self.oldHeight=[WPPreferences() objectForKey:@"quickChatRememberedHeightFraction"];[WPPreferences() setDouble:.60 forKey:@"quickChatRememberedHeightFraction"];self.mode=1;[self next];}
- (void)next{
    QuickReplyMsgMgr.sharedManager.fixtureMode=self.mode;self.callbacks=0;self.began=NSProcessInfo.processInfo.systemUptime;
    [WPPartnerContact openConversationWithUsername:@"wxid_contract_aria" inWindow:self.window presentationMode:3 completion:^(BOOL success,NSString *message){
        self.callbacks++;WP124NativeWrapper *wrapper=(id)self.host.presentedViewController;WPResizableChatController *resize=[WPResizableChatController coordinatorForController:wrapper];
        if(self.mode==1){
            self.checks[@"CH124ToolbarSiblingDoesNotHideVisibleChatIdentity"]=@([WPChatPresentationActiveUsernameInWindow(self.window) isEqual:@"wxid_contract_aria"]);
            self.checks[@"CH124NativeWrapperWithoutNavigationOpensSuccessfully"]=@(success && [wrapper isKindOfClass:WP124NativeWrapper.class] && resize!=nil && resize.chatNavigationController==nil);
            self.checks[@"CH125NativeWrapperIgnoresLegacy60PercentHeight"]=@(fabs(resize.heightFraction-.75)<.001 && ![WPPreferences() objectForKey:@"quickChatRememberedHeightFraction"]);
            wrapper.sheetPresentationController.selectedDetentIdentifier=UISheetPresentationControllerDetentIdentifierLarge;
            self.checks[@"CH125KeyboardNativeLargeDoesNotCreateRememberedHeight"]=@(resize.fullHeight && fabs(WPResizableChatSavedHeightFraction()-.75)<.001 && ![WPPreferences() objectForKey:@"quickChatRememberedHeightFraction"]);
            self.checks[@"CH125WrapperKeepsNativeSheetDelegateAndNoCustomHold"]=@(wrapper.sheetPresentationController.delegate==nil && !resize.heightHoldPending && !resize.adjustingHeight);
            UIViewController *settings=[UIViewController new];settings.view.backgroundColor=UIColor.systemBackgroundColor;[wrapper addChildViewController:settings];settings.view.frame=wrapper.view.bounds;[wrapper.view addSubview:settings.view];[settings didMoveToParentViewController:wrapper];
            self.checks[@"CH124CoveringSettingsChildDoesNotReportUnderlyingChat"]=@(WPChatPresentationActiveUsernameInWindow(self.window)==nil);
            [settings willMoveToParentViewController:nil];[settings.view removeFromSuperview];[settings removeFromParentViewController];
        }else if(self.mode==2){self.checks[@"CH124TypedContactIdentitySupportsNativeChatWithoutGetter"]=@(success && [WPChatPresentationActiveUsernameInWindow(self.window) isEqual:@"wxid_contract_aria"]);
        }else if(self.mode==3){self.checks[@"CH124NativeContentMountAfterOneSecondDoesNotReportFalseFailure"]=@(success && NSProcessInfo.processInfo.systemUptime-self.began>=1.20);
        }else if(self.mode==4){self.checks[@"CH124WrongContactFailureRestoresOriginalHost"]=@(!success && wrapper==nil && resize==nil && self.host.presentedViewController==nil && WPChatPresentationActiveUsernameInWindow(self.window)==nil);
        }else if(self.mode==5){self.checks[@"CH124NonUIKitSheetStillConfirmedWhenExactNativeChatVisible"]=@(success && resize==nil && [WPChatPresentationActiveUsernameInWindow(self.window) isEqual:@"wxid_contract_aria"]);
        }else if(self.mode==6){self.checks[@"CH124ResponderOwnedChatWithoutParentRelationshipIsRecognized"]=@(success && wrapper.nativeContent.parentViewController==nil && resize!=nil);}
        self.checks[[NSString stringWithFormat:@"CH124Mode%luCompletionDeliveredOnce",(unsigned long)self.mode]]=@(self.callbacks==1);
        void (^advance)(void)=^{
            self.mode++;if(self.mode<=6){dispatch_async(dispatch_get_main_queue(),^{[self next];});return;}
            QuickReplyMsgMgr.sharedManager.fixtureMode=0;
            if(self.oldHeight)[WPPreferences() setObject:self.oldHeight forKey:@"quickChatRememberedHeightFraction"];else [WPPreferences() removeObjectForKey:@"quickChatRememberedHeightFraction"];
            [self checkFullscreenIdentity];
        };
        if(self.host.presentedViewController)[self.host dismissViewControllerAnimated:NO completion:advance];
        else dispatch_async(dispatch_get_main_queue(),advance);
    }];
}
@end
void WPChat124RunPreviewChecks(UIWindow *window,void (^completion)(NSDictionary<NSString *,NSNumber *> *checks)){
    WP124ChatRun *run=[WP124ChatRun new];run.window=window;run.completion=completion;[run start];
}
#endif
