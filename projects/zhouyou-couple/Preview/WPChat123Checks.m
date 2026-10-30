#import "WPChat123Checks.h"
#import "WPChat124Checks.h"
#import "WPPartnerContact.h"
#import "WPResizableChat.h"
#import "WPChatPresentationState.h"
#import "WPCommon.h"
#import <math.h>
#if defined(WP_PREVIEW_HOST)
@interface WP123MessageFixture : UITableViewController
@property(nonatomic,copy) NSString *fixtureUsername;
@property(nonatomic,strong) NSArray<NSString *> *messages;
@property(nonatomic,strong) UITextField *nativeInput;
@property(nonatomic) NSUInteger contextConfigurationCalls;
- (NSString *)getCurrentChatName;
@end
@implementation WP123MessageFixture
- (NSString *)getCurrentChatName{return self.fixtureUsername;}
- (void)viewDidLoad{
    [super viewDidLoad];self.title=@"原生聊天容器验收";NSMutableArray *model=[NSMutableArray new];for(NSUInteger i=0;i<70;i++)[model addObject:[NSString stringWithFormat:@"消息记录 %lu：键盘与引用菜单保留原生层级。",(unsigned long)i]];self.messages=model;
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"message"];self.tableView.accessibilityIdentifier=@"WP123NativeMessageTable";
    self.nativeInput=[[UITextField alloc] initWithFrame:CGRectMake(12,0,300,44)];self.nativeInput.borderStyle=UITextBorderStyleRoundedRect;self.nativeInput.placeholder=@"测试原生输入法";self.nativeInput.accessibilityIdentifier=@"WP123NativeInput";self.tableView.tableHeaderView=self.nativeInput;
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"chevron.left"] style:UIBarButtonItemStylePlain target:self action:@selector(closeNativeChat)];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis"] style:UIBarButtonItemStylePlain target:nil action:nil];
}
- (void)closeNativeChat{[self dismissViewControllerAnimated:YES completion:^{WPChatPresentationNotifyChanged();}];}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{return self.messages.count;}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath{UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"message" forIndexPath:indexPath];cell.textLabel.text=self.messages[indexPath.row];cell.textLabel.numberOfLines=2;return cell;}
- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point{
    self.contextConfigurationCalls++;return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggested){return [UIMenu menuWithTitle:@"" children:@[[UIAction actionWithTitle:@"引用（验收夹具）" image:nil identifier:nil handler:^(__unused UIAction *action){}]]];}];
}
@end
@interface WP123NativeSheetDelegate : NSObject <UISheetPresentationControllerDelegate> @end
@implementation WP123NativeSheetDelegate
- (BOOL)presentationControllerShouldDismiss:(UIPresentationController *)presentationController{return YES;}
@end
@interface WP123NativeNavigation : UINavigationController
@property(nonatomic,strong) WP123NativeSheetDelegate *nativeFixtureDelegate;
@end
@implementation WP123NativeNavigation @end
@interface QuickReplyMsgMgr : NSObject
@property(nonatomic) NSUInteger routeCalls;
@property(nonatomic) NSUInteger fixtureMode;
+ (instancetype)sharedManager;
- (void)showPageSheetSession:(id)contact fromViewController:(UIViewController *)presenter;
@end
@implementation QuickReplyMsgMgr
+ (instancetype)sharedManager{static QuickReplyMsgMgr *value;static dispatch_once_t once;dispatch_once(&once,^{value=[self new];});return value;}
- (void)showPageSheetSession:(id)contact fromViewController:(UIViewController *)presenter{
    self.routeCalls++;if(self.fixtureMode){WPChat124PresentFixture(contact,presenter,self.fixtureMode);return;}WP123MessageFixture *chat=[WP123MessageFixture new];chat.fixtureUsername=[contact valueForKey:@"m_nsUsrName"];
    WP123NativeNavigation *navigation=[[WP123NativeNavigation alloc] initWithRootViewController:chat];navigation.modalPresentationStyle=UIModalPresentationPageSheet;navigation.nativeFixtureDelegate=[WP123NativeSheetDelegate new];navigation.sheetPresentationController.delegate=navigation.nativeFixtureDelegate;[presenter presentViewController:navigation animated:YES completion:nil];
}
@end
@interface WP123ChatCheckRun : NSObject
@property(nonatomic,strong) UIWindow *window;
@property(nonatomic,strong) UINavigationController *host;
@property(nonatomic,strong) NSArray *original;
@property(nonatomic,strong) NSMutableDictionary *checks;
@property(nonatomic,copy) void (^completion)(NSDictionary *);
@property(nonatomic,strong) id oldHeight;
@property(nonatomic,strong) id oldPartner;
@property(nonatomic,strong) WP123NativeNavigation *sheet;
@property(nonatomic,strong) WPResizableChatController *panel;
@property(nonatomic,strong) WP123MessageFixture *chat;
@property(nonatomic,strong) id notificationToken;
@property(nonatomic) NSUInteger changeCount;
@property(nonatomic) BOOL finished;
@end
@implementation WP123ChatCheckRun
- (void)record:(NSString *)name pass:(BOOL)pass{self.checks[name]=@(pass);}
- (void)finish{
    if(self.finished)return;self.finished=YES;[NSNotificationCenter.defaultCenter removeObserver:self.notificationToken];
    [self.chat.nativeInput resignFirstResponder];[self.host dismissViewControllerAnimated:NO completion:nil];[self.host setViewControllers:self.original animated:NO];
    if(self.oldHeight)[WPPreferences() setObject:self.oldHeight forKey:@"quickChatRememberedHeightFraction"];else [WPPreferences() removeObjectForKey:@"quickChatRememberedHeightFraction"];
    if(self.oldPartner)[WPPreferences() setObject:self.oldPartner forKey:@"partnerUsername"];else [WPPreferences() removeObjectForKey:@"partnerUsername"];
    self.completion(self.checks);
}
- (void)start{
    self.host=(id)self.window.rootViewController;self.original=[self.host.viewControllers copy];self.checks=[NSMutableDictionary new];self.oldHeight=[WPPreferences() objectForKey:@"quickChatRememberedHeightFraction"];self.oldPartner=[WPPreferences() objectForKey:@"partnerUsername"];[WPPreferences() removeObjectForKey:@"quickChatRememberedHeightFraction"];
    __weak typeof(self) weakSelf=self;self.notificationToken=[NSNotificationCenter.defaultCenter addObserverForName:WPChatPresentationDidChangeNotification object:nil queue:nil usingBlock:^(__unused NSNotification *note){weakSelf.changeCount++;}];
    NSUInteger calls=QuickReplyMsgMgr.sharedManager.routeCalls;
    [WPPartnerContact openConversationWithUsername:@"wxid_contract_aria" inWindow:self.window presentationMode:3 completion:^(BOOL success,__unused NSString *message){
        self.sheet=[self.host.presentedViewController isKindOfClass:WP123NativeNavigation.class]?(id)self.host.presentedViewController:nil;self.panel=[WPResizableChatController coordinatorForController:self.sheet];self.chat=(id)self.sheet.topViewController;
        [self record:@"CH123UsesNativeQuickReplyCContactPageSheet" pass:success && QuickReplyMsgMgr.sharedManager.routeCalls==calls+1 && self.sheet!=nil];
        [self record:@"CH123NativeNavigationIsDirectlyPresentedWithoutChildWrapper" pass:self.sheet.presentingViewController!=nil && self.sheet.parentViewController==nil && self.panel.chatNavigationController==self.sheet];
        [self record:@"CH123KeepsNativeBackAndMoreControlsWithoutDoneOverride" pass:self.chat.navigationItem.leftBarButtonItem.image!=nil && self.chat.navigationItem.rightBarButtonItem.image!=nil && ![self.chat.navigationItem.leftBarButtonItem.title isEqual:@"Done"]];
        [self record:@"CH123HostStackUnchangedBySmallChat" pass:[self.host.viewControllers isEqual:self.original]];
        [self record:@"CH125InitialNativeChatHeightIs75Percent" pass:fabs(self.panel.heightFraction-.75)<.0001 && ![WPPreferences() objectForKey:@"quickChatRememberedHeightFraction"]];
        [self record:@"CH125NativeSheetKeepsInitial75AndLargeDetents" pass:self.sheet.sheetPresentationController.detents.count==2 && self.sheet.sheetPresentationController.preferredCornerRadius>=24];
        [self record:@"CH125NativeSheetDelegateIsUntouched" pass:self.sheet.sheetPresentationController.delegate==self.sheet.nativeFixtureDelegate];
        [self record:@"CH125NativeGrabberAndNativeScrollExpansionRemainEnabled" pass:self.sheet.sheetPresentationController.prefersGrabberVisible && self.sheet.sheetPresentationController.prefersScrollingExpandsWhenScrolledToEdge];
        [self record:@"CH123CurrentIdentityReadsActualNativeLeaf" pass:[WPChatPresentationActiveUsernameInWindow(self.window) isEqual:@"wxid_contract_aria"]];
        [self record:@"CH123NativeOpenPostsVisibilityChange" pass:self.changeCount>0];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,180*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[self keyboardChecks];});
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,9*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(!self.finished){[self record:@"CH123NativeChecksFinishWithinDeadline" pass:NO];[self finish];}});
}
- (void)keyboardChecks{
    if(self.finished)return;[self.sheet.view layoutIfNeeded];UITableView *table=self.chat.tableView;UIView *hit=[self.sheet.view hitTest:[table convertPoint:CGPointMake(CGRectGetMidX(table.bounds),CGRectGetMidY(table.bounds)) toView:self.sheet.view] withEvent:nil];
    [self record:@"CH123NativeMessageTableKeeps70RowsAndVisibleCells" pass:[table numberOfRowsInSection:0]==70 && table.visibleCells.count>0];
    [self record:@"CH123MessageBodyHitTestingReachesNativeTable" pass:hit && [hit isDescendantOfView:table]];
    BOOL hasCustomPan=NO;for(UIGestureRecognizer *g in table.gestureRecognizers)if([g.delegate isKindOfClass:WPResizableChatController.class])hasCustomPan=YES;
    for(UIGestureRecognizer *g in self.sheet.view.gestureRecognizers)if([g.delegate isKindOfClass:WPResizableChatController.class])hasCustomPan=YES;
    for(UIGestureRecognizer *g in self.sheet.navigationBar.gestureRecognizers)if([g.delegate isKindOfClass:WPResizableChatController.class])hasCustomPan=YES;
    [self record:@"CH123NoCustomResizeRecognizerInterceptsMessageBody" pass:!hasCustomPan];
    UIContextMenuConfiguration *menu=[self.chat tableView:table contextMenuConfigurationForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0] point:CGPointZero];
    [self record:@"CH123NativeTableContextMenuConfigurationSurvives" pass:menu!=nil && self.chat.contextConfigurationCalls==1];
    UIWindow *key=self.window.isKeyWindow?self.window:nil;[self.chat.nativeInput becomeFirstResponder];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,220*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        if(self.finished)return;
        [self record:@"CH123KeyboardUsesNativeFirstResponderWithoutReparenting" pass:self.chat.nativeInput.isFirstResponder && self.chat.view.window==self.window && self.chat.navigationController==self.sheet && self.sheet.parentViewController==nil];
        [self record:@"CH123KeyboardDoesNotEraseMessageModelOrTableRows" pass:self.chat.messages.count==70 && [table numberOfRowsInSection:0]==70 && table.visibleCells.count>0];
        [self record:@"CH123KeyboardDoesNotReplaceHostKeyWindow" pass:!key || key.isKeyWindow];
        [self.chat.nativeInput resignFirstResponder];CGFloat nativeHeightBefore=self.panel.heightFraction;
        NSString *nativeDetentBefore=[self.sheet.sheetPresentationController.selectedDetentIdentifier copy];
        [self.panel beginHeightAdjustment];[self.panel updateHeightAdjustmentToFraction:.60];[self.panel finishHeightAdjustmentWithVelocity:-1500];
        [self record:@"CH125RetiredHeightCallsDoNotChangeNativeDetentOrCreateHold" pass:!self.panel.adjustingHeight && !self.panel.heightHoldPending && fabs(self.panel.heightFraction-nativeHeightBefore)<.0001 && [self.sheet.sheetPresentationController.selectedDetentIdentifier isEqual:nativeDetentBefore]];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,620*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[self nativeHeightChecks];});
    });
}
- (void)nativeHeightChecks{
    if(self.finished)return;
    [self record:@"CH125HalfSecondDoesNotSaveHeightOrStartCustomState" pass:![WPPreferences() objectForKey:@"quickChatRememberedHeightFraction"] && !self.panel.heightHoldPending && !self.panel.adjustingHeight && fabs(WPResizableChatSavedHeightFraction()-.75)<.0001];
    [WPPartnerContact openConversationWithUsername:@"wxid_contract_aria" inWindow:self.window presentationMode:0 completion:^(BOOL success,__unused NSString *message){
        [self record:@"CH125LegacyHalfModeUsesSameNative75Route" pass:success && self.host.presentedViewController==self.sheet && self.sheet.viewControllers.count==1];
        UIViewController *settings=[UIViewController new];settings.view.backgroundColor=UIColor.systemBackgroundColor;settings.modalPresentationStyle=UIModalPresentationFullScreen;
        [self.chat presentViewController:settings animated:NO completion:^{
            [self record:@"CH123SettingsCoveringChatDoesNotReportUnderlyingChat" pass:WPChatPresentationActiveUsernameInWindow(self.window)==nil];
            [settings dismissViewControllerAnimated:NO completion:^{[self visibilityAndNativeSheetChecks];}];
        }];
    }];
}
- (void)visibilityAndNativeSheetChecks{
    if(self.finished)return;
    [WPPartnerContact openConversationWithUsername:@"wxid_contract_bob" inWindow:self.window presentationMode:3 completion:^(BOOL success,__unused NSString *message){
        WP123NativeNavigation *previous=self.sheet;self.sheet=(id)self.host.presentedViewController;self.panel=[WPResizableChatController coordinatorForController:self.sheet];self.chat=(id)self.sheet.topViewController;
        [self record:@"CH124DifferentContactReopensThroughNativeQuickReplyWithoutStacking" pass:success && self.sheet!=previous && self.sheet.viewControllers.count==1 && self.sheet.presentedViewController==nil];
        [self record:@"CH123BobSheetReportsBobAndNeverUnderlyingAria" pass:[WPChatPresentationActiveUsernameInWindow(self.window) isEqual:@"wxid_contract_bob"]];
        UISheetPresentationController *nativeSheet=self.sheet.sheetPresentationController;
        nativeSheet.selectedDetentIdentifier=UISheetPresentationControllerDetentIdentifierLarge;
        [self record:@"CH125NativeLargeSelectionDoesNotSaveOrCreateHeightHold" pass:self.panel.fullHeight && fabs(self.panel.heightFraction-1)<.0001 && ![WPPreferences() objectForKey:@"quickChatRememberedHeightFraction"] && !self.panel.heightHoldPending];
        nativeSheet.selectedDetentIdentifier=nativeSheet.detents.firstObject.identifier;
        [self record:@"CH125NativeCollapseRetainsDefault75WithoutRemembering" pass:fabs(self.panel.heightFraction-.75)<.0001 && !self.panel.fullHeight && ![WPPreferences() objectForKey:@"quickChatRememberedHeightFraction"]];
        [self.chat closeNativeChat];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,750*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
            [self record:@"CH125NativeBackControlDismissesWithoutCustomHeightRecognizer" pass:self.host.presentedViewController==nil && !self.panel.heightHoldPending];
            [self record:@"CH123DismissedChatIsNotReportedVisible" pass:![WPChatPresentationActiveUsernameInWindow(self.window) isEqual:@"wxid_contract_bob"]];
            [WPPreferences() setObject:@"wxid_contract_aria" forKey:@"partnerUsername"];
            [WPPartnerContact openSelectedConversationInWindow:self.window completion:^(BOOL selected,__unused NSString *message){
                UIViewController *newSheet=self.host.presentedViewController;WPResizableChatController *restored=[WPResizableChatController coordinatorForController:newSheet];
                [self record:@"CH125PetDefaultPartnerEntryUsesNativeInitialSheet" pass:selected && restored!=nil];
                [self record:@"CH125NextOpenAlwaysStarts75PercentWithoutHeightPreference" pass:fabs(restored.heightFraction-.75)<.0001 && ![WPPreferences() objectForKey:@"quickChatRememberedHeightFraction"]];
                [WPPartnerContact openConversationWithUsername:@"wxid_contract_bob" inWindow:self.window presentationMode:1 completion:^(BOOL full,__unused NSString *fullMessage){
                    [self record:@"CH123ExplicitFullModeClosesSheetAndUsesNativeHostPush" pass:full && self.host.presentedViewController==nil && self.host.viewControllers.count==self.original.count+1];[self finish];
                }];
            }];
        });
    }];
}
@end
void WPChat123RunPreviewChecks(UIWindow *window,void (^completion)(NSDictionary<NSString *,NSNumber *> *checks)){
    WP123ChatCheckRun *run=[WP123ChatCheckRun new];run.window=window;run.completion=^(NSDictionary *baseline){
        WPChat124RunPreviewChecks(window,^(NSDictionary *added){NSMutableDictionary *combined=[baseline mutableCopy];[combined addEntriesFromDictionary:added];completion(combined);});
    };[run start];
}
#endif
