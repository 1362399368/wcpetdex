#import <UIKit/UIKit.h>
#import "WPCommon.h"
#import "WPOverlay.h"
#import "WPPetRenderer.h"
#import "WPEdition.h"
#import "WPRadialMenu.h"
#import "WPCoupleHistory.h"
#import "WPInteractionLog.h"
#import "WPCoupleClient.h"
#import "WPMenuIcons.h"
#import "WPPartnerContact.h"
#import "WPTapActions.h"
#import "WPStabilityChecks.h"
#import "WPYue2Checks.h"
#import "WPLocalPreviewChecks.h"
#import "WPComfortChecks.h"
#import "WPMemory110Checks.h"
#import "WPLifecycle111Checks.h"
#import "WPCache111Checks.h"
#import "WPCollectorChecks.h"
#import "WPCompact111Checks.h"
#import "WPBarrageChecks.h"
#import "WPBarrage122Checks.h"
#import "WPBarrage123Checks.h"
#import "WPUnreadDock122Checks.h"
#import "WPUnifiedDock122Checks.h"
#import "WPBarrageSourceChecks.h"
#import "WPBarrageIntegrationChecks.h"
#import "WPAvatarBudgetChecks.h"
#import "WPMessageReactionChecks.h"
#import "WPBarragePreferences.h"
#import "WPMessageBarrage.h"
#import "WPMessageBarrageSource.h"
#import "WPAsset121Checks.h"
#import "WPQuickChat121Checks.h"
#import "WPNativeChat121Checks.h"
#import "WPLocalAvatarPreparationChecks.h"
#import "WPQuickChat.h"
#import "WPCatalogController.h"
#import "WPSettings124Checks.h"
#import "WPQuickChat124Checks.h"
#import "WPQuickChat125Checks.h"
#import "WPBarrage124Checks.h"
#import "WPBarrage125Checks.h"
#import "WPBarrageSource125Checks.h"
#import "WPRecovery124Checks.h"
#import "WPCoupleRecovery124Checks.h"
#import "WPRecoveryNotify124Checks.h"
#import <dlfcn.h>
@interface WPCoupleClient (WPPreviewProtocol)
- (void)handle:(NSDictionary *)event generation:(NSUInteger)generation;
@end

@interface WPPartnerPickerController (WPPreviewSelection)
- (void)cancelLoading;
@end

@protocol WPPreviewOverlay <NSObject>
- (void)tap;
- (void)drag:(UIPanGestureRecognizer *)gesture;
- (void)showMessage:(NSString *)message;
- (void)revealPet;
- (void)peerStatusChanged;
@end
@protocol WPPreviewPetTap <WPPreviewOverlay>
@end

/// Drives the real drag handler with scripted samples (test host only).
@interface WPFakePan : UIPanGestureRecognizer
@property(nonatomic) UIGestureRecognizerState fakeState;
@property(nonatomic) CGPoint location;
@property(nonatomic) CGPoint translation;
@end
@implementation WPFakePan
- (UIGestureRecognizerState)state{return self.fakeState;}
- (CGPoint)locationInView:(UIView *)view{return self.location;}
- (CGPoint)translationInView:(UIView *)view{return self.translation;}
@end

static CGFloat WPPreviewBrightness(UIColor *color, UITraitCollection *traits){
    if(!color)return -1;
    UIColor *resolved=[color resolvedColorWithTraitCollection:traits];
    CGFloat red=0,green=0,blue=0,alpha=0;
    if(![resolved getRed:&red green:&green blue:&blue alpha:&alpha])return -1;
    return .2126*red+.7152*green+.0722*blue;
}
static UILabel *WPPreviewLabelWithText(UIView *root, NSString *text){
    if([root isKindOfClass:UILabel.class] && [((UILabel *)root).text isEqual:text])return (id)root;
    for(UIView *child in root.subviews){UILabel *label=WPPreviewLabelWithText(child,text);if(label)return label;}
    return nil;
}

@interface UIViewController (WPPreviewPeek)
- (void)applySettings;
- (void)revealPet;
- (void)resetIdle;
- (BOOL)canPeek;
@end

@interface WPPreviewController : UITableViewController
@end
@implementation WPPreviewController
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"微信桌宠 · 测试宿主";
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"桌宠设置" style:UIBarButtonItemStylePlain target:self action:@selector(settings)];
    UILabel *header=[[UILabel alloc] initWithFrame:CGRectMake(0,0,300,76)];header.text=@"此页面用于验证插件窗口\n实际安装后显示在微信内";header.textAlignment=NSTextAlignmentCenter;header.numberOfLines=0;header.font=[UIFont systemFontOfSize:14];header.textColor=UIColor.secondaryLabelColor;self.tableView.tableHeaderView=header;
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{return 12;}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.text=@[@"对象",@"朋友圈",@"设置",@"弹出页面",@"显示键盘",@"长按菜单预览",@"透明区域可正常点按",@"继续滑动列表",@"桌宠会持续显示",@"单击打开所选聊天",@"双击打开桌宠设置",@"长按后滑动到按钮"][indexPath.row];
    cell.detailTextLabel.text=@"模拟宿主页面 · 可操作验证";cell.imageView.image=[UIImage systemImageNamed:indexPath.row==0?@"heart.fill":@"message.fill"];cell.imageView.tintColor=UIColor.systemGreenColor;cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if(indexPath.row==5){[self showMenu];return;}
    UIViewController *page=[UIViewController new];page.title=[tableView cellForRowAtIndexPath:indexPath].textLabel.text;page.view.backgroundColor=UIColor.systemBackgroundColor;
    UILabel *label=[[UILabel alloc] initWithFrame:CGRectMake(30,190,330,80)];label.text=@"切换页面后，透明桌宠依然显示";label.numberOfLines=0;label.font=[UIFont systemFontOfSize:20];[page.view addSubview:label];
    if(indexPath.row==4){UITextField *field=[[UITextField alloc] initWithFrame:CGRectMake(30,300,300,50)];field.placeholder=@"输入以测试键盘";field.borderStyle=UITextBorderStyleRoundedRect;[page.view addSubview:field];[field becomeFirstResponder];}
    if(indexPath.row==3){page.modalPresentationStyle=UIModalPresentationPageSheet;[self presentViewController:page animated:YES completion:nil];}
    else [self.navigationController pushViewController:page animated:YES];
}
- (void)settings {[[WPOverlayManager sharedManager] openSettings];}
- (void)showMenu {
    for(UIWindow *window in UIApplication.sharedApplication.windows)if([NSStringFromClass(window.class) isEqualToString:@"WPOverlayWindow"]){UIViewController *controller=window.rootViewController;WPRadialMenuView *menu=[controller valueForKey:@"menu"];UIView *pet=[controller valueForKey:@"pet"];[menu showAroundPoint:pet.center inBounds:UIEdgeInsetsInsetRect(controller.view.bounds,controller.view.safeAreaInsets)];}
}
@end

@interface WPPreviewDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic) UIWindow *window;
@property(nonatomic) NSMutableDictionary *tests;
@end
@implementation WPPreviewDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    // Exact-frame regression fixtures opt in explicitly. The new optimization
    // scenario and normal preview use the production asynchronous asset path.
    BOOL exactFixture=NO;for(NSString *argument in NSProcessInfo.processInfo.arguments)if([argument hasSuffix:@"self-test"] && ![argument isEqual:@"--optimization-self-test"])exactFixture=YES;
    WPPreviewSetAtlasLoadingSynchronous(exactFixture);
    self.window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    WPPreviewController *home=[[WPPreviewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    self.window.rootViewController=[[UINavigationController alloc] initWithRootViewController:home];[self.window makeKeyAndVisible];
#if TARGET_OS_MACCATALYST
    // Phone-sized window so layout checks match an iPhone width.
    self.window.windowScene.sizeRestrictions.minimumSize=CGSizeMake(393,852);self.window.windowScene.sizeRestrictions.maximumSize=CGSizeMake(393,852);
#endif
    // Quick chat checks need WPQuickChatMocks.m, linked only by Tests/run-quickchat-preview.sh.
    void (*installSessions)(void)=dlsym(RTLD_DEFAULT,"WPQuickChatInstallPreviewSessions");
    void (*runQuickChat)(UIWindow *,void (^)(NSDictionary *))=dlsym(RTLD_DEFAULT,"WPQuickChatRunPreviewTests");
    void (*runUnreadAvatar)(UIWindow *,void (^)(NSDictionary *))=dlsym(RTLD_DEFAULT,"WPUnreadAvatarRunPreviewTests");
    if(installSessions)installSessions();
    WPStartPlugin();
    if([NSProcessInfo.processInfo.arguments containsObject:@"--unified-dock-self-test"])dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        WPUnifiedDock122RunPreviewChecks(self.window,[self overlay],^(NSDictionary *results){
            BOOL all=YES;for(id value in results.allValues)if([value isKindOfClass:NSNumber.class])all&=[value boolValue];
            NSDictionary *report=@{@"caseCount":@(results.count),@"allPassed":@(all),@"results":results,@"finished":@YES};
            [[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil] writeToFile:[WPDataDirectory() stringByAppendingPathComponent:@"unified-dock-report.json"] atomically:YES];
        });
    });
    if([NSProcessInfo.processInfo.arguments containsObject:@"--recovery-self-test"])dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        WPRecovery124RunPreviewChecks(^(NSDictionary *coordinator){
        WPRecoveryNotify124RunPreviewChecks(^(NSDictionary *notify){
        WPCoupleRecovery124RunPreviewChecks(^(NSDictionary *client){
            NSMutableDictionary *results=coordinator.mutableCopy;[results addEntriesFromDictionary:notify];[results addEntriesFromDictionary:client];
            BOOL all=YES;for(id value in results.allValues)all&=[value boolValue];
            NSDictionary *report=@{@"caseCount":@(results.count),@"allPassed":@(all),@"results":results,@"finished":@YES,@"build":@(WP_BUILD_VERSION)};
            [[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil] writeToFile:[WPDataDirectory() stringByAppendingPathComponent:@"recovery-report.json"] atomically:YES];
        });
        });
        });
    });
    if([NSProcessInfo.processInfo.arguments containsObject:@"--source-adapter-self-test"])dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        NSMutableDictionary *results=[WPBarrageSourcePreviewChecks() mutableCopy];
        WPNativeChat121RunPreviewChecks(self.window,^(NSDictionary *chat){
            [results addEntriesFromDictionary:chat];
            // Own the shared avatar queue for this resource contract. The
            // preceding receive fixture may have scheduled dock-avatar retries.
            id originalEnabled=[WPPreferences() objectForKey:@"enabled"];
            [WPPreferences() setBool:NO forKey:@"enabled"];
            [NSNotificationCenter.defaultCenter postNotificationName:WPSettingsDidChangeNotification object:nil];
            WPLocalAvatarPreparationRunPreviewChecks(^(NSDictionary *avatars){
                [results addEntriesFromDictionary:avatars];
                WPQuickChatMonitor *monitor=WPQuickChatMonitor.sharedMonitor;
                [monitor setValue:@[[WPQuickChatSession sessionWithUsername:@"cache-fixture" unread:0 muted:NO pinned:NO time:0]] forKey:@"cachedDisplayRows"];
                [monitor setActive:NO];results[@"cache121BackgroundReleasesCachedSessionModels"]=@([monitor valueForKey:@"cachedDisplayRows"]==nil);
                [monitor setValue:@[[WPQuickChatSession sessionWithUsername:@"cache-fixture" unread:0 muted:NO pinned:NO time:0]] forKey:@"cachedDisplayRows"];
                [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidReceiveMemoryWarningNotification object:nil];
                results[@"cache121PressureReleasesCachedSessionModels"]=@([monitor valueForKey:@"cachedDisplayRows"]==nil && ![[monitor valueForKey:@"displayScanning"] boolValue]);
                WPQuickChat124RunPreviewChecks(self.window,^(NSDictionary *quickchat124){
                [results addEntriesFromDictionary:quickchat124];
                WPQuickChat125RunPreviewChecks(self.window,^(NSDictionary *quickchat125){
                [results addEntriesFromDictionary:quickchat125];
                WPBarrageSource125RunPreviewChecks(^(NSDictionary *source125){
                [results addEntriesFromDictionary:source125];
                if(originalEnabled)[WPPreferences() setObject:originalEnabled forKey:@"enabled"];else [WPPreferences() removeObjectForKey:@"enabled"];
                [NSNotificationCenter.defaultCenter postNotificationName:WPSettingsDidChangeNotification object:nil];
                BOOL all=YES;for(id value in results.allValues)if([value isKindOfClass:NSNumber.class])all&=[value boolValue];
                NSDictionary *report=@{@"caseCount":@(results.count),@"allPassed":@(all),@"results":results,@"finished":@YES};
                [[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil] writeToFile:[WPDataDirectory() stringByAppendingPathComponent:@"source-adapter-report.json"] atomically:YES];
                });
                });
                });
            });
        });
    });
    if([NSProcessInfo.processInfo.arguments containsObject:@"--optimization-self-test"])dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        NSMutableDictionary *results=[NSMutableDictionary new];
        @try{[results addEntriesFromDictionary:WPQuickChat121PreviewChecks([self overlay])];}
        @catch(NSException *exception){results[@"newUICompletedWithoutException"]=@NO;results[@"exceptionName"]=exception.name?:@"unknown";}
        [results addEntriesFromDictionary:WPSettings124PreviewChecks()];
        WPAsset121RunPreviewChecks(^(NSDictionary *assets){
            [results addEntriesFromDictionary:assets];BOOL all=YES;for(id value in results.allValues)if([value isKindOfClass:NSNumber.class])all&=[value boolValue];
            NSDictionary *report=@{@"caseCount":@(results.count),@"allPassed":@(all),@"results":results,@"finished":@YES};
            [[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil] writeToFile:[WPDataDirectory() stringByAppendingPathComponent:@"optimization-report.json"] atomically:YES];
        });
    });
    if([NSProcessInfo.processInfo.arguments containsObject:@"--barrage-self-test"])dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        NSMutableDictionary *results=[NSMutableDictionary new];
        @try {
            [results addEntriesFromDictionary:WPBarragePreviewChecks()];
            [results addEntriesFromDictionary:WPBarrage122PreviewChecks()];
            [results addEntriesFromDictionary:WPBarrage123PreviewChecks()];
            [results addEntriesFromDictionary:WPBarrage125PreviewChecks()];
            [results addEntriesFromDictionary:WPUnreadDock122PreviewChecks()];
            [results addEntriesFromDictionary:WPBarrageSourcePreviewChecks()];
            [results addEntriesFromDictionary:WPMessageReactionPreviewChecks()];
            [results addEntriesFromDictionary:WPBarrageIntegrationPreviewChecks([self overlay])];
        } @catch(NSException *exception){results[@"barrageChecksCompletedWithoutException"]=@NO;results[@"exceptionName"]=exception.name?:@"unknown";}
        WPBarrage123RunAsyncPreviewChecks(^(NSDictionary *recovery){
        [results addEntriesFromDictionary:recovery];
        WPBarrage124RunOverlayPreviewChecks(^(NSDictionary *motion){
        [results addEntriesFromDictionary:motion];
        WPAvatarBudgetRunPreviewChecks(^(NSDictionary *budget){
            [results addEntriesFromDictionary:budget];
            BOOL all=YES;for(id value in results.allValues)if([value isKindOfClass:NSNumber.class])all&=[value boolValue];
            NSDictionary *report=@{@"caseCount":@(results.count),@"allPassed":@(all),@"results":results,@"finished":@YES};
            [[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil] writeToFile:[WPDataDirectory() stringByAppendingPathComponent:@"barrage-report.json"] atomically:YES];
        });
        });
        });
    });
    if([NSProcessInfo.processInfo.arguments containsObject:@"--barrage-demo"])dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        [WPPreferences() setBool:NO forKey:@"autoPeek"];[WPPreferences() setBool:NO forKey:@"quietTimeEnabled"];[WPPreferences() setBool:NO forKey:@"reminderContactsOnly"];
        WPBarrageSetEnabled(YES);WPBarrageSetShowsDetails(YES);WPBarrageSetSpeed(1);
        UIViewController *controller=[self overlay].rootViewController;
        [controller applySettings];
        for(NSUInteger i=0;i<2;i++)dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)((1+i*1.3)*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
            WPBarrageMessage *message=[WPBarrageMessage new];message.conversationUsername=i?@"preview_group@chatroom":@"preview_friend";message.senderUsername=i?@"preview_member":@"preview_friend";message.text=i?@"明天一起出发去看海！":@"到楼下啦，下来接我呀 ♡";message.identifier=[NSString stringWithFormat:@"barrage-demo-%lu",(unsigned long)i];
            [NSNotificationCenter.defaultCenter postNotificationName:WPMessageBarrageDidReceiveNotification object:nil userInfo:@{@"message":message}];
        });
    });
    if(runQuickChat && [NSProcessInfo.processInfo.arguments containsObject:@"--quickchat-self-test"])dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        runQuickChat([self overlay],^(NSDictionary *results){
            BOOL all=YES;for(id key in results)all&=[results[key] boolValue];
            NSDictionary *report=@{@"caseCount":@(results.count),@"allPassed":@(all),@"results":results,@"finished":@YES};
            [[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil] writeToFile:[WPDataDirectory() stringByAppendingPathComponent:@"quickchat-report.json"] atomically:YES];
        });
    });
    if(runUnreadAvatar && [NSProcessInfo.processInfo.arguments containsObject:@"--unread-avatar-self-test"])dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        runUnreadAvatar([self overlay],^(NSDictionary *results){
            BOOL all=YES;for(id value in results.allValues)all&=[value boolValue];
            NSDictionary *report=@{@"caseCount":@(results.count),@"allPassed":@(all),@"results":results,@"finished":@YES};
            [[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil] writeToFile:[WPDataDirectory() stringByAppendingPathComponent:@"unread-avatar-report.json"] atomically:YES];
        });
    });
    if([NSProcessInfo.processInfo.arguments containsObject:@"--self-test"])dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{[self runTests];});
    if([NSProcessInfo.processInfo.arguments containsObject:@"--update-self-test"])dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        NSMutableDictionary *results=[NSMutableDictionary new];
        @try {
            [results addEntriesFromDictionary:WPMemory110PreviewChecks()];
            [results addEntriesFromDictionary:WPComfortPreviewChecks()];
            [results addEntriesFromDictionary:WPLifecycle111PreviewChecks()];
            [results addEntriesFromDictionary:WPCompact111PreviewChecks()];
            [results addEntriesFromDictionary:WPCache111PreviewChecks()];
            [results addEntriesFromDictionary:WPCollectorPreviewChecks()];
        } @catch(NSException *exception) {
            results[@"updateChecksCompletedWithoutException"]=@NO;
            results[@"exceptionName"]=exception.name?:@"unknown";
            results[@"exceptionReason"]=exception.reason?:@"unknown";
        }
        BOOL all=YES;
        for(id value in results.allValues)if([value isKindOfClass:NSNumber.class])all&=[value boolValue];
        NSDictionary *report=@{@"caseCount":@(results.count),@"allPassed":@(all),@"results":results,@"finished":@YES};
        [[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil]
            writeToFile:[WPDataDirectory() stringByAppendingPathComponent:@"update-report.json"] atomically:YES];
    });
    if([NSProcessInfo.processInfo.arguments containsObject:@"--zhouyou-self-test"])dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{[self runZhouyouTests];});
    if([NSProcessInfo.processInfo.arguments containsObject:@"--yue2-self-test"])dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        WPYue2RunPreviewChecks(^(NSDictionary *results){
            BOOL all=YES;for(id value in results.allValues)all&=[value boolValue];
            NSDictionary *report=@{@"caseCount":@(results.count),@"allPassed":@(all),@"results":results,@"finished":@YES};
            [[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil] writeToFile:[WPDataDirectory() stringByAppendingPathComponent:@"yue2-report.json"] atomically:YES];
        });
    });
    if([NSProcessInfo.processInfo.arguments containsObject:@"--local-preview-self-test"])dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        WPLocalPreviewRunChecks(^(NSDictionary *results){
            BOOL all=YES;for(id value in results.allValues)all&=[value boolValue];
            NSDictionary *report=@{@"caseCount":@(results.count),@"allPassed":@(all),@"results":results,@"finished":@YES};
            [[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil] writeToFile:[WPDataDirectory() stringByAppendingPathComponent:@"local-preview-report.json"] atomically:YES];
        });
    });
    if([NSProcessInfo.processInfo.arguments containsObject:@"--show-menu"])dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{[home showMenu];});
    if([NSProcessInfo.processInfo.arguments containsObject:@"--demo-outbox"])dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{
        [WPCoupleHistory.sharedHistory expireAllPending];
        for(NSUInteger i=0;i<2;i++){NSString *identifier=NSUUID.UUID.UUIDString;[WPCoupleHistory.sharedHistory enqueueKind:i?@"anger":@"miss" identifier:identifier at:[NSDate dateWithTimeIntervalSinceNow:-(NSTimeInterval)i*60]];[WPCoupleHistory.sharedHistory updateIdentifier:identifier state:@"queued" serverTime:nil];}
        if([NSProcessInfo.processInfo.arguments containsObject:@"--show-history"])[[WPOverlayManager sharedManager] openInteractions];
    });
    return YES;
}
- (UIWindow *)overlay {for(UIWindow *w in UIApplication.sharedApplication.windows)if([NSStringFromClass(w.class) isEqualToString:@"WPOverlayWindow"])return w;return nil;}
- (void)writeZhouyouResults:(NSDictionary<NSString *,NSNumber *> *)results {
    BOOL passed=YES;
    for(NSNumber *value in results.allValues)passed&=value.boolValue;
    NSDictionary *report=@{@"caseCount":@(results.count),@"allPassed":@(passed),@"results":results,@"finished":@YES};
    NSData *json=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil];
    [json writeToFile:[WPDataDirectory() stringByAppendingPathComponent:@"zhouyou-report.json"] atomically:YES];
}
- (void)runZhouyouTests {
    NSMutableDictionary<NSString *,NSNumber *> *results=[NSMutableDictionary new];
    UIWindow *overlay=[self overlay];
    UIViewController<WPPreviewOverlay> *controller=(id)overlay.rootViewController;
    WPPetRenderer *pet=[controller valueForKey:@"pet"];
    if(!overlay || !pet){results[@"overlayCreated"]=@NO;[self writeZhouyouResults:results];return;}
    WPResetSelectedPet();
    [pet reloadPet];
    [WPPreferences() setBool:YES forKey:@"autoPeek"];
    [WPPreferences() setBool:NO forKey:@"quickChatEnabled"];
    [WPPreferences() removeObjectForKey:@"singleTapAction"];
    [WPPreferences() removeObjectForKey:@"doubleTapAction"];
    results[@"tapDefaultsKeepPartnerAndSettings"] = @(WPConfiguredTapAction(NO)==WPTapActionPartnerChat && WPConfiguredTapAction(YES)==WPTapActionSettings);
    [WPPreferences() setBool:YES forKey:@"quickChatEnabled"];
    results[@"quickChatSwitchDoesNotChangeConfiguredTap"] = @(WPConfiguredTapAction(NO)==WPTapActionPartnerChat && WPConfiguredTapAction(YES)==WPTapActionSettings);
    [WPPreferences() removeObjectForKey:@"singleTapAction"];
    [WPPreferences() removeObjectForKey:@"doubleTapAction"];
    results[@"legacyQuickChatKeepsSingleTap"] = @(WPConfiguredTapAction(NO)==WPTapActionQuickChat && WPConfiguredTapAction(YES)==WPTapActionSettings);
    WPSetConfiguredTapAction(NO,WPTapActionSettings);
    WPSetConfiguredTapAction(YES,WPTapActionPartnerChat);
    results[@"singleAndDoubleChoicesIndependent"] = @(WPConfiguredTapAction(NO)==WPTapActionSettings && WPConfiguredTapAction(YES)==WPTapActionPartnerChat);
    WPSetConfiguredTapAction(NO,WPTapActionQuickChat);
    WPSetConfiguredTapAction(YES,WPTapActionQuickChat);
    WPResetQuickChatTapActions();
    [WPPreferences() setBool:NO forKey:@"quickChatEnabled"];
    results[@"disablingQuickChatRestoresTapChoices"] = @(WPConfiguredTapAction(NO)==WPTapActionPartnerChat && WPConfiguredTapAction(YES)==WPTapActionSettings);
    [NSNotificationCenter.defaultCenter postNotificationName:WPSettingsDidChangeNotification object:nil];
    NSDictionary *metadata=[pet valueForKey:@"metadata"];
    NSDictionary *loaded=[WPPreferences() dictionaryForKey:@"selectedPetLastLoad"];
    results[@"yueBundledDefaultLoaded"]=@([loaded[@"loadedDirectoryName"] isEqualToString:@"DefaultPet"] && [pet.petName isEqualToString:@"玥"]);
    results[@"yueV4AtlasAndPhoneRow"]=@([metadata[@"id"] isEqualToString:@"yue-zhour-20261021"] &&
        [metadata[@"spriteVersionNumber"] integerValue]==4 && [metadata[@"columns"] integerValue]==10 &&
        [metadata[@"rows"] integerValue]==29 && [metadata[@"onlinePhoneRow"] integerValue]==8 &&
        [metadata[@"frameCounts"][8] integerValue]==10);

    // Move left, then right within the same pan. Both samples actually enter
    // the production drag handler and stay below the shake detector threshold.
    WPFakePan *pan=[WPFakePan new];
    CGPoint origin=pet.center;
    pan.fakeState=UIGestureRecognizerStateBegan;pan.location=origin;pan.translation=CGPointZero;
    [controller drag:pan];
    pan.fakeState=UIGestureRecognizerStateChanged;pan.location=CGPointMake(origin.x-65,origin.y);pan.translation=CGPointMake(-65,0);
    [controller drag:pan];
    results[@"dragLeftUsesLeftRunRow2"]=@([[pet valueForKey:@"animationRow"] integerValue]==2);
    pan.location=CGPointMake(origin.x-20,origin.y);pan.translation=CGPointMake(-20,0);
    [controller drag:pan];
    results[@"dragRightUsesRightRunRow1"]=@([[pet valueForKey:@"animationRow"] integerValue]==1);
    pan.fakeState=UIGestureRecognizerStateEnded;
    [controller drag:pan];

    WPOverlayManager *manager=WPOverlayManager.sharedManager;
    WPCoupleClient *couple=[manager valueForKey:@"couple"];
    [couple setValue:@YES forKey:@"connected"];
    [couple setValue:@3 forKey:@"protocolVersion"];
    NSUInteger connectionGeneration=[[couple valueForKey:@"generation"] unsignedIntegerValue];
    results[@"offlineCanAutoPeek"]=@(![manager peerIsOnline] && [controller canPeek]);
    [controller resetIdle];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3700*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        results[@"offlineReturnsToEdgePeek"]=@([[controller valueForKey:@"peeking"] boolValue]);
        NSInteger version=[[couple valueForKey:@"peerStatusVersion"] integerValue]+1;
        NSTimeInterval stamp=NSDate.date.timeIntervalSince1970;
        [couple handle:@{@"type":@"peer_status",@"version":@(version),@"server_time":@(stamp),@"online":@YES,@"last_online":NSNull.null} generation:connectionGeneration];
        results[@"onlineStatusRevealsPet"]=@([manager peerIsOnline] && pet.isPeerOnline && ![[controller valueForKey:@"peeking"] boolValue]);
        results[@"onlineDisablesEdgePeek"]=@(![controller canPeek]);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,1200*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
            results[@"onlineIdleUsesPhoneRow8"]=@([[pet valueForKey:@"animationRow"] integerValue]==8);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3300*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
                results[@"onlineRemainsFullyVisible"]=@(![[controller valueForKey:@"peeking"] boolValue] && ![controller canPeek] && [[pet valueForKey:@"animationRow"] integerValue]==8);
                [couple handle:@{@"type":@"peer_status",@"version":@(version+1),@"server_time":@(NSDate.date.timeIntervalSince1970),@"online":@NO,@"last_online":@(stamp)} generation:connectionGeneration];
                results[@"offlineRestoresOrdinaryIdle"]=@(![manager peerIsOnline] && !pet.isPeerOnline && [[pet valueForKey:@"animationRow"] integerValue]==0 && [controller canPeek]);
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3700*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
                    results[@"offlinePeekResumesAfterStatusChange"]=@([[controller valueForKey:@"peeking"] boolValue]);
                    [self writeZhouyouResults:results];
                });
            });
        });
    });
}
- (void)writeTests {
    NSString *path=[WPDataDirectory() stringByAppendingPathComponent:@"test-report.json"];
    [[NSJSONSerialization dataWithJSONObject:self.tests options:NSJSONWritingPrettyPrinted error:nil] writeToFile:path atomically:YES];
}
- (void)runTests {
    [UIImagePNGRepresentation(WPMomentsMenuIcon()) writeToFile:[WPDataDirectory() stringByAppendingPathComponent:@"moments-icon.png"] atomically:YES];
    [UIImagePNGRepresentation(WPBrokenHeartMenuIcon()) writeToFile:[WPDataDirectory() stringByAppendingPathComponent:@"broken-heart-icon.png"] atomically:YES];
    self.tests=[NSMutableDictionary new];UIWindow *overlay=[self overlay];id controller=overlay.rootViewController;WPPetRenderer *pet=[controller valueForKey:@"pet"];
    NSString *defaultName=WP_EDITION_ARIA?@"AriaPet":@"DefaultPet";
    NSDictionary *loaded=[WPPreferences() dictionaryForKey:@"selectedPetLastLoad"];
    self.tests[@"editionDefaultPetLoaded"]=@([loaded[@"loadedDirectoryName"] isEqualToString:defaultName]);
    self.tests[@"overlayCreated"]=@(overlay!=nil && !overlay.hidden);
    self.tests[@"hostRemainsKey"]=@(self.window.isKeyWindow && !overlay.isKeyWindow);
    self.tests[@"overlayAboveHost"]=@(overlay.windowLevel>self.window.windowLevel);
    self.tests[@"noBackgroundPanel"]=@(CGColorGetAlpha(pet.backgroundColor.CGColor)==0 && CGColorGetAlpha(overlay.backgroundColor.CGColor)==0);
    self.tests[@"outsideTouchPassesThrough"]=@([overlay hitTest:CGPointMake(20,180) withEvent:nil]==nil);
    BOOL opaqueHit=NO,transparentMiss=NO;
    for(NSInteger y=0;y<pet.bounds.size.height && !(opaqueHit && transparentMiss);y+=8)
        for(NSInteger x=0;x<pet.bounds.size.width && !(opaqueHit && transparentMiss);x+=8){CGPoint p=CGPointMake(x,y);UIView *hit=[overlay hitTest:[pet convertPoint:p toView:overlay] withEvent:nil];opaqueHit|=hit==pet;transparentMiss|=hit==nil;}
    self.tests[@"visiblePixelsTouchable"]=@(opaqueHit);self.tests[@"transparentPixelsPassThrough"]=@(transparentMiss);
    [WPPreferences() setDouble:120 forKey:@"petSize"];[NSNotificationCenter.defaultCenter postNotificationName:WPSettingsDidChangeNotification object:nil];
    self.tests[@"sizeSettingApplied"]=@(fabs(pet.bounds.size.width-120)<.1);
    [WPPreferences() setDouble:88 forKey:@"petSize"];[NSNotificationCenter.defaultCenter postNotificationName:WPSettingsDidChangeNotification object:nil];
    UIViewController *page=[UIViewController new];page.view.backgroundColor=UIColor.systemBackgroundColor;
    [(UINavigationController *)self.window.rootViewController pushViewController:page animated:NO];
    [self writeTests];
    // A push must finish attaching its view before that controller can present.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,200*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        self.tests[@"survivesNavigation"]=@([self overlay]==overlay && !overlay.hidden && page.view.window==self.window);
        UIViewController *modal=[UIViewController new];modal.view.backgroundColor=UIColor.systemBackgroundColor;modal.modalPresentationStyle=UIModalPresentationFullScreen;
        [self.window.rootViewController presentViewController:modal animated:NO completion:^{
            self.tests[@"survivesHostModal"]=@([self overlay]==overlay && !overlay.hidden && self.window.isKeyWindow && modal.view.window==self.window);
            [self.window.rootViewController dismissViewControllerAnimated:NO completion:^{[(UINavigationController *)self.window.rootViewController popToRootViewControllerAnimated:NO];[self testMenu:controller];}];
        }];
    });
}
- (UIButton *)menuButton:(WPRadialMenuView *)menu action:(NSString *)action {
    for(UIView *view in menu.subviews)if([view isKindOfClass:UIButton.class] && [[view valueForKey:@"actionIdentifier"] isEqual:action])return (id)view;
    return nil;
}
- (void)testMenu:(UIViewController *)controller {
    WPRadialMenuView *menu=[controller valueForKey:@"menu"];UIView *pet=[controller valueForKey:@"pet"];
    __block NSUInteger count=0;__block NSString *action=nil;
    void(^original)(NSString *)=menu.actionHandler;
    menu.actionHandler=^(NSString *key){count++;action=key;};
    [menu showAroundPoint:pet.center inBounds:CGRectInset(controller.view.bounds,15,70)];
    UIButton *target=[self menuButton:menu action:@"miss"];
    BOOL fits=YES;CGRect menuBounds=CGRectInset(controller.view.bounds,15,70);
    for(UIView *view in menu.subviews)if([view isKindOfClass:UIButton.class] && !view.hidden)fits&=CGRectContainsRect(menuBounds,view.frame);
    self.tests[@"menuFitsSafeBounds"]=@(fits);
    [menu updateFingerAtPoint:target.center];
    UILabel *hint=[menu valueForKey:@"hintLabel"];
    self.tests[@"hoverShowsConcreteTransparentHint"]=@(!hint.hidden && [hint.text containsString:@"松手"] && [hint.text containsString:@"想你了"] && CGColorGetAlpha(hint.backgroundColor.CGColor)==0);
    // Wait beyond both previous dwell thresholds. Holding must never execute.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,1100*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        self.tests[@"hoverNeverExecutesAction"]=@(count==0 && menu.isShowing && !hint.hidden);
        [menu finishTracking];
        self.tests[@"releaseExecutesSelectedAction"]=@(count==1 && [action isEqual:@"miss"] && !menu.isShowing && hint.hidden);
        [menu finishTracking];[menu updateFingerAtPoint:target.center];[target sendActionsForControlEvents:UIControlEventTouchUpInside];
        self.tests[@"oneActionPerGesture"]=@(count==1);
        [menu showAroundPoint:pet.center inBounds:menuBounds];UIButton *read=[self menuButton:menu action:@"read"];[menu updateFingerAtPoint:read.center];
        self.tests[@"readHintExplainsScope"]=@([hint.text containsString:@"所有会话标为已读"]);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,800*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
            self.tests[@"readHoverNeverExecutesAction"]=@(count==1 && menu.isShowing);
            [menu finishTracking];
            self.tests[@"readReleaseTriggers"]=@(count==2 && [action isEqual:@"read"]);
            [menu showAroundPoint:pet.center inBounds:menuBounds];[menu updateFingerAtPoint:target.center];[menu updateFingerAtPoint:CGPointMake(-100,-100)];[menu finishTracking];
            self.tests[@"releaseOutsideCancelsSelection"]=@(count==2 && !menu.isShowing && hint.hidden);
            [menu showAroundPoint:pet.center inBounds:menuBounds];[menu updateFingerAtPoint:target.center];[menu cancel];[menu finishTracking];
            self.tests[@"cancelNeverExecutesSelectedAction"]=@(count==2);
            [menu showAroundPoint:pet.center inBounds:menuBounds];[menu finishTracking];
            self.tests[@"releaseWithoutSelectionDoesNothing"]=@(count==2);
            [menu showAroundPoint:pet.center inBounds:menuBounds];UIButton *moments=[self menuButton:menu action:@"moments"],*anger=[self menuButton:menu action:@"anger"];
            [menu updateFingerAtPoint:moments.center];[menu updateFingerAtPoint:anger.center];
            self.tests[@"movingSelectionUpdatesExplanation"]=@(count==2 && [hint.text containsString:@"生气了"]);
            [menu finishTracking];
            self.tests[@"releaseUsesLatestHoveredAction"]=@(count==3 && [action isEqual:@"anger"]);
            [menu showAroundPoint:pet.center inBounds:menuBounds];[menu updateFingerAtPoint:target.center];[menu showAroundPoint:pet.center inBounds:menuBounds];[menu finishTracking];
            self.tests[@"reopeningResetsSelection"]=@(count==3);
            [menu showAroundPoint:pet.center inBounds:menuBounds];[target sendActionsForControlEvents:UIControlEventTouchUpInside];
            self.tests[@"accessibleButtonTapTriggers"]=@(count==4 && [action isEqual:@"miss"]);menu.actionHandler=original;
            [WPPreferences() setBool:NO forKey:@"enabled"];[NSNotificationCenter.defaultCenter postNotificationName:WPSettingsDidChangeNotification object:nil];[[WPOverlayManager sharedManager] refresh];
            self.tests[@"disabledStopsAnimation"]=@([pet valueForKey:@"displayLink"]==nil);
            [WPPreferences() setBool:YES forKey:@"enabled"];[NSNotificationCenter.defaultCenter postNotificationName:WPSettingsDidChangeNotification object:nil];
            [self testSettings];
        });
    });
}
- (void)testSettings {
    WPOverlayManager *manager=[WPOverlayManager sharedManager];
    [manager openSettings];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,200*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        UIWindow *panel=[manager valueForKey:@"settingsWindow"],*overlay=[self overlay];
        WPPetRenderer *pet=[overlay.rootViewController valueForKey:@"pet"];
        self.tests[@"settingsPanelCreated"]=@(panel!=nil && !panel.hidden && panel.isKeyWindow);
        self.tests[@"petVisibleAbovePluginSettings"]=@(panel.windowLevel<overlay.windowLevel && !overlay.hidden && !pet.hidden && pet.window==overlay);
        UINavigationController *navigation=(id)panel.rootViewController;
        [self testVisibilityInNavigation:navigation completion:^(UINavigationController *currentNavigation){
            [self testPartnerSearchInNavigation:currentNavigation completion:^{
                void(^close)(void)=[currentNavigation.viewControllers.firstObject valueForKey:@"onClose"];
                if(close)close();
                self.tests[@"settingsCloseRestoresHostKey"]=@(self.window.isKeyWindow && [manager valueForKey:@"settingsWindow"]==nil);
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,350*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[self testNewInteractions];});
            }];
        }];
    });
}
- (UISwitch *)hideSwitchInView:(UIView *)view {
    if([view isKindOfClass:UISwitch.class] && [view.accessibilityIdentifier isEqual:@"WPHidePetSwitch"])return (id)view;
    for(UIView *child in view.subviews){UISwitch *toggle=[self hideSwitchInView:child];if(toggle)return toggle;}
    return nil;
}
- (void)testVisibilityInNavigation:(UINavigationController *)navigation completion:(void (^)(UINavigationController *))completion {
    WPOverlayManager *manager=WPOverlayManager.sharedManager;
    UIWindow *overlay=[self overlay];UIViewController<WPPreviewOverlay> *controller=(id)overlay.rootViewController;
    WPPetRenderer *pet=[controller valueForKey:@"pet"];
    UISwitch *toggle=[self hideSwitchInView:navigation.topViewController.view];
    self.tests[@"hideSwitchPresentAndOffByDefault"]=@(toggle && !toggle.isOn);
    if(!toggle){completion(navigation);return;}
    CGFloat size=pet.bounds.size.width;CGPoint center=pet.center;
    [controller showMessage:@"隐藏前的浮动提示"];
    WPRadialMenuView *menu=[controller valueForKey:@"menu"];
    [menu showAroundPoint:pet.center inBounds:controller.view.bounds];
    [(UIView *)[controller valueForKey:@"arrivals"] setHidden:NO];
    toggle.on=YES;[toggle sendActionsForControlEvents:UIControlEventValueChanged];
    self.tests[@"hideSwitchPersistsDisabledPreference"]=@(![WPPreferences() boolForKey:@"enabled"]);
    self.tests[@"hideSwitchHidesEntireOverlayAndStopsAnimation"]=@(controller.view.hidden && pet.hidden && [pet valueForKey:@"displayLink"]==nil && [pet valueForKey:@"atlas"]==nil && [overlay hitTest:pet.center withEvent:nil]==nil);
    self.tests[@"hideSwitchDismissesMenuAndFloatingPrompts"]=@(!menu.isShowing && [(UIView *)[controller valueForKey:@"bubble"] isHidden] && [(UIView *)[controller valueForKey:@"arrivals"] isHidden] && [(UIView *)[controller valueForKey:@"quickBar"] isHidden]);
    [manager refresh];[controller showMessage:@"隐藏期间不显示"];
    [controller peerStatusChanged];[controller revealPet];
    self.tests[@"hiddenPetIgnoresForegroundRevealAndFloatingMessage"]=@(controller.view.hidden && pet.hidden && [pet valueForKey:@"displayLink"]==nil && [(UIView *)[controller valueForKey:@"bubble"] isHidden]);
    UIViewController *newController=[controller.class new];(void)newController.view;
    self.tests[@"newOverlayReadsPersistedHiddenPreference"]=@(newController.view.hidden && [(UIView *)[newController valueForKey:@"pet"] isHidden]);
    void(^close)(void)=[navigation.viewControllers.firstObject valueForKey:@"onClose"];if(close)close();
    [manager openSettings];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,200*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        UIWindow *panel=[manager valueForKey:@"settingsWindow"];UINavigationController *reopened=(id)panel.rootViewController;
        UISwitch *restore=[self hideSwitchInView:reopened.topViewController.view];
        self.tests[@"settingsCanReopenWhilePetIsHidden"]=@(panel && !panel.hidden && panel.isKeyWindow && restore.isOn && controller.view.hidden);
        [self snapshot:@"hide-pet-settings"];
        restore.on=NO;[restore sendActionsForControlEvents:UIControlEventValueChanged];
        self.tests[@"hideSwitchRestoresPetAndAnimation"]=@([WPPreferences() boolForKey:@"enabled"] && !controller.view.hidden && !pet.hidden && [pet valueForKey:@"displayLink"]!=nil && [pet valueForKey:@"atlas"]!=nil);
        self.tests[@"hideSwitchPreservesSizeAndPosition"]=@(fabs(pet.bounds.size.width-size)<.01 && hypot(pet.center.x-center.x,pet.center.y-center.y)<.1);
        [self snapshot:@"show-pet-settings"];
        completion(reopened ?: navigation);
    });
}
- (void)testPartnerSearchInNavigation:(UINavigationController *)navigation completion:(void (^)(void))completion {
    UIViewController *settings = navigation.topViewController;
    NSString *previousUsername = [WPPreferences() stringForKey:@"partnerUsername"];
    NSString *previousName = [WPPreferences() stringForKey:@"partnerDisplayName"];
    WPPartnerPickerController *picker = [[WPPartnerPickerController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    [navigation pushViewController:picker animated:NO];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,200*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        [picker cancelLoading];
        NSArray *fixture = @[@{@"username":@"preview_fixture_aria", @"name":@"Aria", @"search":@"Aria preview_fixture_aria"}];
        [picker setValue:fixture forKey:@"contacts"]; [picker setValue:fixture forKey:@"filtered"]; [picker setValue:nil forKey:@"loadError"];
        [picker.tableView reloadData];
        UISearchController *search = [picker valueForKey:@"contactSearch"];
        search.active = YES; search.searchBar.text = @"aria";
        [(id<UISearchResultsUpdating>)picker updateSearchResultsForSearchController:search];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,350*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
            search.active = NO;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,900*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
                self.tests[@"cancelPartnerSearchKeepsPicker"]=@(navigation.topViewController==picker && !search.isActive);
                self.tests[@"cancelPartnerSearchPreservesSelection"]=@(([WPPreferences() stringForKey:@"partnerUsername"]==previousUsername || [[WPPreferences() stringForKey:@"partnerUsername"] isEqual:previousUsername]) &&
                    ([WPPreferences() stringForKey:@"partnerDisplayName"]==previousName || [[WPPreferences() stringForKey:@"partnerDisplayName"] isEqual:previousName]));
                search.active = YES; search.searchBar.text = @"aria";
                [(id<UISearchResultsUpdating>)picker updateSearchResultsForSearchController:search];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,650*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
                    // Programmatic UISearchController activation is ignored by
                    // some headless simulator runs; the filtered result is the
                    // behavior this fixture can verify reliably.
                    NSArray *filtered=[picker valueForKey:@"filtered"];
                    self.tests[@"partnerFixtureSearchFiltersResults"]=@(filtered.count==1 && [filtered.firstObject[@"username"] isEqual:@"preview_fixture_aria"]);
                    self.tests[@"partnerSearchPresentation"] = search.isActive ? @"active" : @"headless-inactive";
                    __block NSUInteger saves = 0;
                    id observer = [NSNotificationCenter.defaultCenter addObserverForName:WPSettingsDidChangeNotification object:nil queue:nil usingBlock:^(__unused NSNotification *note){saves++;}];
                    NSIndexPath *row = [NSIndexPath indexPathForRow:0 inSection:0];
                    [picker tableView:picker.tableView didSelectRowAtIndexPath:row];
                    [picker tableView:picker.tableView didSelectRowAtIndexPath:row];
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,1500*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
                        self.tests[@"selectingSearchResultReturnsToSettings"]=@(navigation.topViewController==settings && !search.isActive);
                        self.tests[@"searchSelectionSavesChosenPartner"]=@([[WPPreferences() stringForKey:@"partnerUsername"] isEqual:@"preview_fixture_aria"] && [[WPPartnerContact selectedDisplayName] isEqual:@"Aria"]);
                        self.tests[@"searchSelectionSavedOnlyOnce"]=@(saves==1);
                        [NSNotificationCenter.defaultCenter removeObserver:observer];
                        if(previousUsername)[WPPreferences() setObject:previousUsername forKey:@"partnerUsername"];else [WPPreferences() removeObjectForKey:@"partnerUsername"];
                        if(previousName)[WPPreferences() setObject:previousName forKey:@"partnerDisplayName"];else [WPPreferences() removeObjectForKey:@"partnerDisplayName"];
                        [NSNotificationCenter.defaultCenter postNotificationName:WPSettingsDidChangeNotification object:nil];
                        if(navigation.topViewController!=settings)[navigation popToViewController:settings animated:NO];
                        completion();
                    });
                });
            });
        });
    });
}
- (void)snapshot:(NSString *)name {
    // Draws the plugin panel (if any) and the floating pet overlay together.
    UIWindow *panel=[[WPOverlayManager sharedManager] valueForKey:@"settingsWindow"],*overlay=[self overlay];UIWindow *base=panel?:self.window;
    UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithBounds:base.bounds];
    UIImage *image=[renderer imageWithActions:^(__unused UIGraphicsImageRendererContext *context){
        if(!panel)[self.window drawViewHierarchyInRect:self.window.bounds afterScreenUpdates:YES];
        else [panel drawViewHierarchyInRect:panel.bounds afterScreenUpdates:YES];
        [overlay drawViewHierarchyInRect:overlay.bounds afterScreenUpdates:YES];
    }];
    [UIImagePNGRepresentation(image) writeToFile:[WPDataDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"ui-%@.png",name]] atomically:YES];
    self.tests[@"lastStep"]=name;[self writeTests];
}
- (void)after:(NSTimeInterval)seconds do:(void (^)(void))block {dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(seconds*NSEC_PER_SEC)),dispatch_get_main_queue(),block);}
- (void)testAdaptivePanel:(UIWindow *)panel page:(UIViewController *)page primaryLabel:(UILabel *)primary card:(UIView *)card name:(NSString *)name completion:(void (^)(void))completion {
    UIUserInterfaceStyle systemStyle=self.window.traitCollection.userInterfaceStyle;
    self.tests[[name stringByAppendingString:@"FollowsSystem"]]=@(panel.overrideUserInterfaceStyle==UIUserInterfaceStyleUnspecified &&
        page.navigationController.overrideUserInterfaceStyle==UIUserInterfaceStyleUnspecified &&
        page.overrideUserInterfaceStyle==UIUserInterfaceStyleUnspecified &&
        page.view.traitCollection.userInterfaceStyle==systemStyle);
    // Preview-only trait override exercises a live appearance change on the
    // already-open plugin panel; production keeps the override unspecified.
    void (^check)(UIUserInterfaceStyle)=^(UIUserInterfaceStyle style){
        UITraitCollection *traits=page.view.traitCollection;
        CGFloat background=WPPreviewBrightness(page.view.backgroundColor,traits);
        CGFloat text=WPPreviewBrightness(primary.textColor,traits);
        UINavigationBarAppearance *nav=page.navigationController.navigationBar.standardAppearance;
        CGFloat navBackground=WPPreviewBrightness(nav.backgroundColor,traits);
        CGFloat navTitle=WPPreviewBrightness(nav.titleTextAttributes[NSForegroundColorAttributeName],traits);
        UILabel *renderedTitle=WPPreviewLabelWithText(page.navigationController.navigationBar,page.title);
        CGFloat renderedTitleBrightness=WPPreviewBrightness(renderedTitle.textColor,renderedTitle.traitCollection);
        CGFloat cardBrightness=card?WPPreviewBrightness(card.backgroundColor,traits):0;
        BOOL light=style==UIUserInterfaceStyleLight;
        self.tests[[name stringByAppendingString:light?@"LightMode":@"DarkMode"]]=@(traits.userInterfaceStyle==style &&
            (light?background>.72:background<.25) && (light?text<.4:text>.65) &&
            (light?navBackground>.72:navBackground<.25) && (light?navTitle<.4:navTitle>.65) &&
            renderedTitle && (light?renderedTitleBrightness<.4:renderedTitleBrightness>.65) &&
            (!card || (light?cardBrightness>.65:cardBrightness<.35)));
        [self snapshot:[NSString stringWithFormat:@"%@-%@",name,light?@"light":@"dark"]];
    };
    panel.overrideUserInterfaceStyle=UIUserInterfaceStyleLight;
    [self after:.15 do:^{
        check(UIUserInterfaceStyleLight);
        panel.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
        [self after:.15 do:^{
            check(UIUserInterfaceStyleDark);
            panel.overrideUserInterfaceStyle=UIUserInterfaceStyleUnspecified;
            [self after:.15 do:^{completion();}];
        }];
    }];
}
- (void)drag:(UIViewController *)controller from:(CGPoint)start xs:(NSArray<NSNumber *> *)xs dy:(CGFloat)dy {
    WPFakePan *pan=[WPFakePan new];pan.location=start;pan.translation=CGPointZero;pan.fakeState=UIGestureRecognizerStateBegan;
    [(id<WPPreviewOverlay>)controller drag:pan];
    NSUInteger i=0;for(NSNumber *x in xs){i++;pan.fakeState=UIGestureRecognizerStateChanged;pan.translation=CGPointMake(x.doubleValue,dy*i);pan.location=CGPointMake(start.x+x.doubleValue,start.y+dy*i);[(id<WPPreviewOverlay>)controller drag:pan];}
    pan.fakeState=UIGestureRecognizerStateEnded;[(id<WPPreviewOverlay>)controller drag:pan];
}
- (void)testNewInteractions {
    WPOverlayManager *manager=[WPOverlayManager sharedManager];UIViewController *controller=[self overlay].rootViewController;
    WPRadialMenuView *menu=[controller valueForKey:@"menu"];WPPetRenderer *pet=[controller valueForKey:@"pet"];
    double previous=[WPPreferences() doubleForKey:@"menuScale"];
    [WPPreferences() setDouble:.6 forKey:@"menuScale"];[menu showAroundPoint:pet.center inBounds:controller.view.bounds];
    CGFloat small=menu.effectiveRadius;self.tests[@"smallRadiusMatchesSetting"]=@(fabs(menu.requestedRadius-48)<.01);
    [WPPreferences() setDouble:4 forKey:@"menuScale"];[menu showAroundPoint:pet.center inBounds:controller.view.bounds];
    self.tests[@"largeRadiusMatchesSetting"]=@(fabs(menu.requestedRadius-320)<.01);
    self.tests[@"radiusAdjustmentVisiblyChangesReach"]=@(menu.effectiveRadius>small*1.5);
    self.tests[@"angerReplacesPayment"]=@([self menuButton:menu action:@"anger"]!=nil && [self menuButton:menu action:@"receive"]==nil);
    [menu cancel];[WPPreferences() setDouble:previous forKey:@"menuScale"];
    WPCoupleHistory *history=WPCoupleHistory.sharedHistory;
    [history manuallyClearIncomingIdentifiers:[history.pendingIncoming valueForKey:@"id"]];[history expireAllPending];
    NSString *anger=NSUUID.UUID.UUIDString;BOOL isNew=NO;
    BOOL saved=[history receiveKind:@"anger" identifier:anger at:NSDate.date isNew:&isNew];UIView *badge=[controller valueForKey:@"badge"];UILabel *number=[controller valueForKey:@"badgeNumber"];
    self.tests[@"A05_liveAngerShowsBadge"]=@(saved && isNew && !badge.hidden && number.text.integerValue==1);
    self.tests[@"A05_petStaysAngry"]=@(pet.isAngry && ![[pet valueForKey:@"moodIcon"] isHidden]);
    [controller.view layoutIfNeeded];CGRect badgeCircle=[number convertRect:number.bounds toView:controller.view];
    self.tests[@"badgeOutsidePetImage"]=@(!CGRectIntersectsRect(badgeCircle,pet.frame) && CGRectGetMaxY(badgeCircle)<CGRectGetMinY(pet.frame));
    UIView *badgeHit=[[self overlay] hitTest:[controller.view convertPoint:CGPointMake(CGRectGetMidX(badgeCircle),CGRectGetMidY(badgeCircle)) toView:[self overlay]] withEvent:nil];
    self.tests[@"badgeIsNotATouchTarget"]=@(badgeHit!=badge && badgeHit!=number);
    NSString *outgoing=NSUUID.UUID.UUIDString;BOOL outgoingSaved=[history enqueueKind:@"anger" identifier:outgoing at:[NSDate dateWithTimeIntervalSinceNow:-5]];
    [history updateIdentifier:outgoing state:@"delivered" serverTime:nil];
    self.tests[@"outgoingInteractionDoesNotChangeBadge"]=@(outgoingSaved && history.badgeCount==1);
    BOOL first=[pet playReaction:@"miss"],second=[pet playReaction:@"miss"];
    self.tests[@"repeatedReactionCoalesces"]=@(first && !second);
    [(id<WPPreviewOverlay>)controller tap];
    self.tests[@"badgeTapNoLongerOpensLog"]=@([manager valueForKey:@"settingsWindow"]==nil);
    [self after:2.6 do:^{
        NSDictionary *semantic=[[pet valueForKey:@"metadata"] objectForKey:@"semanticRows"];
        NSInteger angryIdle=[semantic[@"angerIdle"] isKindOfClass:NSNumber.class]?[semantic[@"angerIdle"] integerValue]:5;
        self.tests[@"A19_angryLookReturnsAfterMissAnimation"]=@(pet.isAngry && [[pet valueForKey:@"animationRow"] integerValue]==angryIdle);
        CGPoint start=pet.center;
        [self drag:controller from:start xs:@[@-10,@-25,@-40,@-60,@-80,@-100,@-120,@-140] dy:-6];
        [self after:.4 do:^{
            self.tests[@"A20_plainDragDoesNotOpenLog"]=@([manager valueForKey:@"settingsWindow"]==nil && fabs(pet.center.y-start.y)>10);
            CGPoint shakeStart=pet.center;
            [self drag:controller from:shakeStart xs:@[@-15,@-35,@-20,@0,@12,@-6,@-30,@-12,@8,@20,@-10,@-35,@-5,@20] dy:0];
            [self after:.6 do:^{
                UINavigationController *navigation=(id)((UIWindow *)[manager valueForKey:@"settingsWindow"]).rootViewController;
                self.tests[@"debugShakeTriggered"]=@([[controller valueForKeyPath:@"shake.triggered"] boolValue]);
                self.tests[@"debugTop"]=NSStringFromClass(navigation.topViewController.class)?:@"nil";
                self.tests[@"debugCount"]=@(navigation.viewControllers.count);
                self.tests[@"A21_shakeOpensBubbleLog"]=@([navigation.topViewController isKindOfClass:WPInteractionLogController.class]);
                self.tests[@"A21_oneLogPerShake"]=@(navigation.viewControllers.count==1);
                self.tests[@"A21_shakeDoesNotMovePet"]=@(hypot(pet.center.x-shakeStart.x,pet.center.y-shakeStart.y)<1);
                WPInteractionLogController *log=(id)navigation.topViewController;
                self.tests[@"A11_openingLogKeepsBadgeAndAnger"]=@(history.badgeCount==1 && pet.isAngry);
                [self testAdaptivePanel:navigation.view.window page:log primaryLabel:[log valueForKey:@"summaryLabel"] card:nil name:@"interaction" completion:^{
                    [self testBubbleLog:log completion:^{
                        void(^close)(void)=log.onClose;if(close)close();
                        [self after:.4 do:^{[self testHome];}];
                    }];
                }];
            }];
        }];
    }];
}
- (void)testBubbleLog:(WPInteractionLogController *)log completion:(void (^)(void))completion {
    WPCoupleHistory *history=WPCoupleHistory.sharedHistory;WPCoupleClient *couple=[[WPOverlayManager sharedManager] valueForKey:@"couple"];
    NSString *originalAnger=nil;for(NSDictionary *row in history.pendingIncoming)if([row[@"kind"] isEqual:@"anger"]){originalAnger=row[@"id"];break;}
    NSUInteger generation=[[couple valueForKey:@"generation"] unsignedIntegerValue];
    // End-to-end through the client: ten late misses and one fresh miss.
    NSMutableArray *late=[NSMutableArray new];
    for(NSUInteger i=0;i<10;i++){NSString *identifier=NSUUID.UUID.UUIDString;[late addObject:identifier];[couple handle:@{@"type":@"miss",@"id":identifier,@"sent_at":@(NSDate.date.timeIntervalSince1970-900-i)} generation:generation];}
    NSString *fresh=NSUUID.UUID.UUIDString;[couple handle:@{@"type":@"miss",@"id":fresh,@"sent_at":@(NSDate.date.timeIntervalSince1970-20)} generation:generation];
    [couple handle:@{@"type":@"miss",@"id":late.firstObject,@"sent_at":@(NSDate.date.timeIntervalSince1970-900)} generation:generation];
    UIViewController *overlayController=[self overlay].rootViewController;UILabel *bubble=[overlayController valueForKey:@"bubble"];WPPetRenderer *pet=[overlayController valueForKey:@"pet"];
    self.tests[@"A04_backlogBadgesEachLateMiss"]=@(history.badgeCount==11);
    self.tests[@"A16_duplicateDeliveryStoredOnce"]=@([[history.recentInteractions filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"id == %@",late.firstObject]] count]==1);
    self.tests[@"A04_backlogSummarisedInOneBubble"]=@(!bubble.hidden && [bubble.text containsString:@"11 条互动"] && [bubble.text containsString:@"10 条待回应"]);
    NSString *currentReaction=[pet valueForKey:@"reactionKind"],*queuedReaction=[pet valueForKey:@"queuedReaction"];
    self.tests[@"A04_backlogSchedulesOneMissReaction"]=@([currentReaction isEqual:@"receiveMiss"] || [queuedReaction isEqual:@"receiveMiss"]);
    [self after:.5 do:^{
        [log.view layoutIfNeeded];[log.tableView layoutIfNeeded];
        NSArray *rows=log.rows;BOOL newestFirst=YES;for(NSUInteger i=1;i<rows.count;i++)newestFirst&=[rows[i-1][@"sent_at"] doubleValue]>=[rows[i][@"sent_at"] doubleValue];
        self.tests[@"bubblesNewestFirst"]=@(rows.count>=13 && newestFirst);
        BOOL sides=YES,widths=YES;NSUInteger checked=0;CGFloat width=log.tableView.bounds.size.width;
        for(UITableViewCell *cell in log.tableView.visibleCells){
            NSIndexPath *path=[log.tableView indexPathForCell:cell];if(!path)continue;NSDictionary *row=rows[path.row];
            UIView *b=[cell valueForKey:@"bubble"];CGRect frame=[b convertRect:b.bounds toView:log.tableView];
            BOOL mine=[row[@"direction"] isEqual:@"outgoing"];
            sides&=mine?(CGRectGetMaxX(frame)>width*.6 && CGRectGetMinX(frame)>width*.2):(CGRectGetMinX(frame)<width*.4 && CGRectGetMaxX(frame)<width*.8);
            widths&=frame.size.width<=width*.72+1 && CGRectGetMinX(frame)>=0 && CGRectGetMaxX(frame)<=width;checked++;
        }
        self.tests[@"bubblesTALeftMeRight"]=@(checked>3 && sides);
        self.tests[@"bubblesWithin72PercentAndScreen"]=@(checked>3 && widths);
        NSDictionary *freshRow=nil;for(NSDictionary *row in rows)if([row[@"id"] isEqual:fresh])freshRow=row;
        self.tests[@"A01_promptMissShowsReceivedNotReplied"]=@([WPInteractionStatusText(freshRow) isEqual:@"已接收"]);
        self.tests[@"replyButtonExplainsOrdinaryReplies"]=@([[log.replyButton titleForState:UIControlStateNormal] isEqual:@"想你了 · 回应普通提醒"]);
        [self snapshot:@"log"];
        [log.tableView setContentOffset:CGPointMake(0,log.tableView.contentSize.height>log.tableView.bounds.size.height?240:0) animated:NO];[self snapshot:@"log-scrolled"];[log.tableView setContentOffset:CGPointMake(0,-log.tableView.adjustedContentInset.top) animated:NO];
        // A08: no token is configured here, so the send genuinely fails.
        NSUInteger before=history.badgeCount;[log replyAll];
        [self after:.3 do:^{
            self.tests[@"A08_failedReplyKeepsBadgeAndAnger"]=@(history.badgeCount==before && pet.isAngry && ![[log valueForKey:@"statusLabel"] isHidden]);
            // A07/A09 through the client: snapshot, a new anger while sending, then server acceptance.
            NSString *reply=NSUUID.UUID.UUIDString;NSArray *snapshot=[history.pendingIncoming valueForKey:@"id"];
            [history enqueueKind:@"miss" identifier:reply at:NSDate.date resolvingIncomingIdentifiers:snapshot];
            NSString *newAnger=NSUUID.UUID.UUIDString;[couple handle:@{@"type":@"anger",@"id":newAnger,@"sent_at":@(NSDate.date.timeIntervalSince1970)} generation:generation];
            [couple handle:@{@"type":@"accepted",@"id":reply,@"state":@"online",@"sent_at":@(NSDate.date.timeIntervalSince1970)} generation:generation];
            NSSet *expectedAngers=[NSSet setWithArray:@[originalAnger?:@"",newAnger]];
            NSMutableSet *remainingAngers=[NSMutableSet new];for(NSDictionary *row in history.pendingIncoming)if([row[@"kind"] isEqual:@"anger"])[remainingAngers addObject:row[@"id"]];
            self.tests[@"A09_acceptedMissKeepsOldAndNewAnger"]=@(history.badgeCount==2 && [remainingAngers isEqualToSet:expectedAngers] && pet.isAngry);
            [self after:.4 do:^{[self testClearOnLog:log completion:completion];}];
        }];
    }];
}
// Test-only: invoke the block of the actual presented UIAlertAction, then let
// UIKit perform the real dismiss/present lifecycle. This helper is in Preview
// only and is never compiled into the injected dylib.
- (BOOL)choosePreviewAlert:(UIAlertController *)alert title:(NSString *)title completion:(void (^)(void))completion {
    self.tests[@"lastStep"]=[NSString stringWithFormat:@"alert:%@:%@",title,alert?NSStringFromClass(alert.class):@"nil"];[self writeTests];
    if(![alert isKindOfClass:UIAlertController.class])return NO;
    for(UIAlertAction *action in alert.actions)if([action.title isEqual:title]){
        void (^handler)(UIAlertAction *)=nil;
        @try {handler=[action valueForKey:@"handler"];} @catch(__unused NSException *exception){return NO;}
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,400*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
            // Same order as UIKit: the alert goes away, then the action handler runs.
            [alert.presentingViewController dismissViewControllerAnimated:NO completion:^{
                if(handler)handler(action);
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,850*NSEC_PER_MSEC),dispatch_get_main_queue(),completion);
            }];
        });
        return YES;
    }
    return NO;
}
- (void)testClearOnLog:(WPInteractionLogController *)log completion:(void (^)(void))completion {
    WPCoupleHistory *history=WPCoupleHistory.sharedHistory;NSUInteger before=history.badgeCount,pending=history.pendingCount;
    WPPetRenderer *pet=[[self overlay].rootViewController valueForKey:@"pet"];
    self.tests[@"clearButtonNamed"]=@([[log.clearButton titleForState:UIControlStateNormal] isEqual:@"清除我的红点"] && log.clearButton.enabled);
    [log clearMyBadge];UIAlertController *first=(id)log.presentedViewController;
    self.tests[@"A13_firstConfirmationWording"]=@([first isKindOfClass:UIAlertController.class] && [first.message isEqual:@"这样可能会导致关系恶化，确定要继续清除吗？"] &&
        [[first.actions valueForKey:@"title"] isEqual:@[@"取消",@"继续清除"]]);
    [self snapshot:@"clear-confirm"];
    BOOL chose=[self choosePreviewAlert:first title:@"取消" completion:^{
        self.tests[@"A14_firstCancelChangesNothing"]=@(history.badgeCount==before && history.pendingCount==pending && !log.presentedViewController);
        [log clearMyBadge];
        BOOL firstYes=[self choosePreviewAlert:(id)log.presentedViewController title:@"继续清除" completion:^{
            UIAlertController *second=(id)log.presentedViewController;
            self.tests[@"A13_secondConfirmationShowsCount"]=@([second isKindOfClass:UIAlertController.class] && [second.message isEqual:[NSString stringWithFormat:@"确定清除这 %lu 条提醒吗？清除后仍会保留互动记录。",(unsigned long)before]] &&
                [[second.actions valueForKey:@"title"] isEqual:@[@"取消",@"确认清除"]]);
            BOOL secondNo=[self choosePreviewAlert:second title:@"取消" completion:^{
                self.tests[@"A14_secondCancelChangesNothing"]=@(history.badgeCount==before && history.pendingCount==pending);
                [log clearMyBadge];
                NSString *duringFirst=NSUUID.UUID.UUIDString;BOOL fresh=NO;[history receiveKind:@"anger" identifier:duringFirst at:NSDate.date isNew:&fresh];
                [self choosePreviewAlert:(id)log.presentedViewController title:@"继续清除" completion:^{
                    NSString *duringSecond=NSUUID.UUID.UUIDString;BOOL newSecond=NO;[history receiveKind:@"miss" identifier:duringSecond at:[NSDate dateWithTimeIntervalSinceNow:-700] isNew:&newSecond];
                    [self choosePreviewAlert:(id)log.presentedViewController title:@"确认清除" completion:^{
                        NSArray *remaining=[history.pendingIncoming valueForKey:@"id"];
                        self.tests[@"A15_onlyFirstPromptSnapshotCleared"]=@(history.badgeCount==2 && [remaining containsObject:duringFirst] && [remaining containsObject:duringSecond]);
                        self.tests[@"A13_clearSendsNothing"]=@(history.pendingCount==pending);
                        BOOL marked=NO;for(NSDictionary *row in log.rows)marked|=[WPInteractionStatusText(row) isEqual:@"手动清除"];
                        self.tests[@"A13_clearedRowsShowManualClear"]=@(marked);
                        self.tests[@"A15_newAngerKeepsAngryLook"]=@(pet.isAngry);
                        [history manuallyClearIncomingIdentifiers:@[duringFirst,duringSecond]];
                        self.tests[@"A13_lastClearRestoresNormalLook"]=@(!pet.isAngry && [[pet valueForKey:@"moodIcon"] isHidden] && history.badgeCount==0);
                        [log.tableView setContentOffset:CGPointMake(0,-log.tableView.adjustedContentInset.top) animated:NO];[self snapshot:@"log-cleared"];
                        completion();
                    }];
                }];
            }];
            if(!secondNo)completion();
        }];
        if(!firstYes)completion();
    }];
    if(!chose)completion();
}
- (void)testHome {
    WPOverlayManager *manager=[WPOverlayManager sharedManager];[manager openSettings];
    [self after:.5 do:^{
        UINavigationController *navigation=(id)((UIWindow *)[manager valueForKey:@"settingsWindow"]).rootViewController;UIViewController *home=navigation.topViewController;
        if(!home.view){self.tests[@"homeOpens"]=@NO;[self finishNewInteractions];return;}
        NSMutableArray *cards=[NSMutableArray new];NSMutableArray *queue=[NSMutableArray arrayWithObject:home.view];
        while(queue.count){UIView *view=queue.firstObject;[queue removeObjectAtIndex:0];if([NSStringFromClass(view.class) isEqual:@"WPFeatureCard"])[cards addObject:view];[queue addObjectsFromArray:view.subviews];}
        self.tests[@"homeHasSixFeatureCards"]=@(cards.count==6);
        BOOL twoColumns=cards.count==6;
        if(twoColumns){CGRect a=[cards[0] convertRect:[cards[0] bounds] toView:home.view],b=[cards[1] convertRect:[cards[1] bounds] toView:home.view];
            twoColumns=fabs(a.origin.y-b.origin.y)<1 && CGRectGetMaxX(a)<CGRectGetMinX(b) && CGRectGetMaxX(b)<=home.view.bounds.size.width;}
        self.tests[@"homeCardsInTwoColumns"]=@(twoColumns);
        UILabel *cardTitle=nil;
        if(cards.count){NSMutableArray *views=[NSMutableArray arrayWithObject:cards[0]];
            while(views.count && !cardTitle){UIView *view=views.firstObject;[views removeObjectAtIndex:0];if([view isKindOfClass:UILabel.class] && [((UILabel *)view).text isEqual:@"情侣互动"])cardTitle=(id)view;[views addObjectsFromArray:view.subviews];}}
        [self testAdaptivePanel:navigation.view.window page:home primaryLabel:cardTitle card:cards.firstObject name:@"home" completion:^{
            [self snapshot:@"home"];
            UIControl *petCard=cards.count>3?cards[3]:nil;[petCard sendActionsForControlEvents:UIControlEventTouchUpInside];
            [self after:.7 do:^{
                self.tests[@"petSettingsPageOpens"]=@([navigation.topViewController.title isEqual:@"桌宠设置"]);
                [self snapshot:@"pet-settings"];[navigation popToRootViewControllerAnimated:NO];
                UIControl *connection=cards.count>4?cards[4]:nil;[connection sendActionsForControlEvents:UIControlEventTouchUpInside];
                [self after:.7 do:^{
                    self.tests[@"connectionPageOpens"]=@([navigation.topViewController.title isEqual:@"配对与连接"]);
                    [self snapshot:@"connection"];[navigation popToRootViewControllerAnimated:NO];
                    UIControl *couple=cards.firstObject;[couple sendActionsForControlEvents:UIControlEventTouchUpInside];
                    [self after:.7 do:^{
                        [self snapshot:@"couple"];[navigation popToRootViewControllerAnimated:NO];
                        UIControl *quick=cards.count>2?cards[2]:nil;[quick sendActionsForControlEvents:UIControlEventTouchUpInside];
                        [self after:.7 do:^{
                            self.tests[@"quickActionsKeepReadAndMoments"]=@([navigation.topViewController.title isEqual:@"快捷功能"]);
                            UISegmentedControl *single=nil,*doubleTap=nil;
                            NSMutableArray<UIView *> *queue=[NSMutableArray arrayWithObject:navigation.topViewController.view];
                            while(queue.count){UIView *view=queue.firstObject;[queue removeObjectAtIndex:0];
                                if([view isKindOfClass:UISegmentedControl.class]){
                                    if([view.accessibilityIdentifier isEqual:@"WPTapActionSingle"])single=(id)view;
                                    if([view.accessibilityIdentifier isEqual:@"WPTapActionDouble"])doubleTap=(id)view;
                                }
                                [queue addObjectsFromArray:view.subviews];
                            }
                            self.tests[@"quickActionsShowIndependentTapChoices"]=@(single && doubleTap && single.numberOfSegments==3 && doubleTap.numberOfSegments==3 &&
                                single.selectedSegmentIndex==WPConfiguredTapAction(NO) && doubleTap.selectedSegmentIndex==WPConfiguredTapAction(YES));
                            [self snapshot:@"quick"];
                            void(^close)(void)=[navigation.viewControllers.firstObject valueForKey:@"onClose"];if(close)close();
                            [self after:.4 do:^{[self finishNewInteractions];}];
                        }];
                    }];
                }];
            }];
        }];
    }];
}
- (void)finishNewInteractions {
    UIViewController *controller=[self overlay].rootViewController;WPRadialMenuView *menu=[controller valueForKey:@"menu"];UIView *pet=[controller valueForKey:@"pet"];UILabel *number=[controller valueForKey:@"badgeNumber"];
    WPCoupleHistory *history=WPCoupleHistory.sharedHistory;BOOL isNew=NO;
    CGPoint previousCenter=pet.center;pet.center=CGPointMake(100,0);[controller.view setNeedsLayout];[controller.view layoutIfNeeded];
    NSString *topID=NSUUID.UUID.UUIDString;[history receiveKind:@"anger" identifier:topID at:NSDate.date isNew:&isNew];[controller.view layoutIfNeeded];
    CGRect topBadge=[number convertRect:number.bounds toView:controller.view];
    self.tests[@"topEdgeBadgeDoesNotCoverPet"]=@(CGRectContainsRect(controller.view.bounds,topBadge) && !CGRectIntersectsRect(topBadge,pet.frame));
    [history manuallyClearIncomingIdentifiers:@[topID]];pet.center=previousCenter;
    NSMutableArray *many=[NSMutableArray new];
    for(NSUInteger i=0;i<123;i++){NSString *identifier=NSUUID.UUID.UUIDString;[many addObject:identifier];[history receiveKind:@"anger" identifier:identifier at:NSDate.date isNew:&isNew];}
    [controller.view setNeedsLayout];[controller.view layoutIfNeeded];CGRect wide=[number convertRect:number.bounds toView:controller.view];
    self.tests[@"threeDigitBadgeFitsAndIsReadable"]=@([number.text isEqual:@"123"] && wide.size.width>=[number sizeThatFits:CGSizeMake(80,24)].width+8 && CGRectContainsRect(controller.view.bounds,wide));
    [self snapshot:@"badge-123"];
    [history manuallyClearIncomingIdentifiers:many];
    UIImageView *momentsImage=[[self menuButton:menu action:@"moments"] valueForKey:@"symbolView"];
    UIImageView *angryIcon=[[self menuButton:menu action:@"anger"] valueForKey:@"symbolView"];self.tests[@"angerIconStaysGray"]=@([angryIcon.tintColor isEqual:UIColor.systemGrayColor]);
    self.tests[@"momentsUsesOriginalColorAsset"]=@(momentsImage.image && !momentsImage.image.isSymbolImage && momentsImage.image.renderingMode==UIImageRenderingModeAlwaysOriginal);
    WPPetRenderer *renderer=(id)pet;[renderer playAngry];self.tests[@"angryAnimationPlays"]=@(UIAccessibilityIsReduceMotionEnabled() || [[renderer valueForKey:@"spriteLayer"] animationForKey:@"anger"]!=nil);
    if(WP_EDITION_ARIA){
        NSDictionary *meta=[renderer valueForKey:@"metadata"];
        self.tests[@"ariaV4UsesTenFramesAt15FPS"]=@([meta[@"spriteVersionNumber"] integerValue]==4 && [meta[@"columns"] integerValue]==10 && [[renderer valueForKey:@"frameRate"] integerValue]==15);
        [renderer pointInside:CGPointMake(renderer.bounds.size.width*.5,renderer.bounds.size.height*.5) withEvent:nil];
        NSData *mask=[renderer valueForKey:@"alphaMask"];
        self.tests[@"ariaTransparentHitMaskCoversAtlas"]=@(mask.length==(192*208+7)/8);
        [renderer holdPeekOnLeft:YES];
        self.tests[@"ariaPeekKeepsDedicatedPose"]=@([[renderer valueForKey:@"heldPeekRow"] integerValue]==25 && [[renderer valueForKey:@"animationRow"] integerValue]==25);
        [renderer playSemanticAction:@"reveal"];
        CALayer *sprite=[renderer valueForKey:@"spriteLayer"];
        self.tests[@"ariaRevealStartsImmediatelyAndMirrorsLeft"]=@([[renderer valueForKey:@"animationRow"] integerValue]==27 && [[renderer valueForKey:@"frameIndex"] integerValue]==0 && sprite.transform.m11<0);
        [renderer endPeek];
    }
    NSDictionary *stability=WPStabilityPreviewChecks(renderer,nil);
    for(NSString *key in stability)self.tests[[key stringByReplacingOccurrencesOfString:@"aria" withString:@"zhouyou"]]=stability[key];
    WPCatalogController *catalog=[WPCatalogController new];
    UIWindow *settingsWindow=[WPOverlayManager.sharedManager valueForKey:@"settingsWindow"];
    UINavigationController *navigation=(id)settingsWindow.rootViewController;
    if(!navigation)navigation=(id)self.window.rootViewController;
    [navigation pushViewController:catalog animated:NO];(void)catalog.view;
    UISegmentedControl *segments=[catalog valueForKey:@"segments"];segments.selectedSegmentIndex=2;
    [segments sendActionsForControlEvents:UIControlEventValueChanged];
    [self finishWithDefaultPreview:catalog remainingAttempts:40];
}
- (void)finishWithDefaultPreview:(WPCatalogController *)catalog remainingAttempts:(NSUInteger)attempts {
    NSArray *entries=[catalog valueForKey:@"shownPets"];UICollectionView *collection=[catalog valueForKey:@"collection"];
    [catalog.view setNeedsLayout];[catalog.view layoutIfNeeded];[collection layoutIfNeeded];
    BOOL listed=NO,visible=NO;
    for(NSUInteger index=0;index<entries.count;index++)if([entries[index][@"wp_directory"] isEqual:WPDefaultPetDirectory()]){
        listed=YES;NSIndexPath *path=[NSIndexPath indexPathForItem:index inSection:0];
        [collection scrollToItemAtIndexPath:path atScrollPosition:UICollectionViewScrollPositionTop animated:NO];[collection layoutIfNeeded];
        UICollectionViewCell *cell=[collection cellForItemAtIndexPath:path];UIImageView *preview=[cell valueForKey:@"preview"];
        visible=preview.image.CGImage!=NULL && !preview.hidden && preview.window!=nil;break;
    }
    if(!visible && attempts){dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[self finishWithDefaultPreview:catalog remainingAttempts:attempts-1];});return;}
    self.tests[@"zhouyouDefaultPetListedInDownloadedTab"]=@(listed);
    self.tests[@"zhouyouDefaultPetPreviewVisibleInRealCatalogCell"]=@(visible);
    [self snapshot:@"default-pet-preview"];
    BOOL all=YES;for(id key in self.tests)if([self.tests[key] isKindOfClass:NSNumber.class])all&=[self.tests[key] boolValue];
    self.tests[@"caseCount"]=@(self.tests.count);self.tests[@"allPassed"]=@(all);
    self.tests[@"finished"]=@YES;[self writeTests];
}
- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary *)options {
    NSString *command=url.host;
    WPPreviewController *home=(id)((UINavigationController *)self.window.rootViewController).viewControllers.firstObject;
    if([command isEqual:@"menu"])[home showMenu];
    else if([command isEqual:@"settings"])[[WPOverlayManager sharedManager] openSettings];
    else if([command isEqual:@"miss"])[NSNotificationCenter.defaultCenter postNotificationName:@"WeChatPet.PreviewMissYou" object:nil];
    else if([command isEqual:@"reveal"])for(UIWindow *window in UIApplication.sharedApplication.windows)if([NSStringFromClass(window.class) isEqualToString:@"WPOverlayWindow"])[window.rootViewController revealPet];
    return YES;
}
@end
int main(int argc,char *argv[]){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(WPPreviewDelegate.class));}}
