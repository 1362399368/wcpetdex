#import "WPSettings.h"
#import "WPCommon.h"
#import "WPOverlay.h"
#import "WPPetCatalog.h"
#import "WPPartnerContact.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "WPPetImporter.h"
#import "WPActionAdapter.h"
#import "WPCatalogController.h"
#import "WPMenuIcons.h"
#import "WPShakeDetector.h"
#import "WPTheme.h"
#import "WPEdition.h"
#import "WPQuickChat.h"
#import "WPTapActions.h"
#import "WPIndicatorSettings.h"
#import "WPComfortPreferences.h"
#import "WPBarrageSettingsController.h"
#import "WPQuickChatSettingsController.h"
#import "WPQuickChatPreferences.h"
#import "WPChatAdvisor.h"
#import "WPChatAdvisorSettingsController.h"
#import "WPHomePresentation.h"
#import "WPMenuConfiguration.h"
#import "WPChoiceSheet.h"
#if WP_EDITION_COUPLE
#import "WPInteractionLog.h"
#import "WPBackendConfiguration.h"
#import "WPCoupleHistory.h"
#if WP_FEATURE_WORK_CHECKIN
#import "WPWorkCheckinReminder.h"
#endif

static NSString * const WPConnectionStatusChangedNotification=@"WeChatPet.ConnectionStatusChanged";
#endif

#pragma mark - Secondary pages

static void WPOpenTelegramGroup(WPCardPageController *controller) {
    NSURL *url=[NSURL URLWithString:@"https://t.me/+TdjkYED5H4Q3ZTdh"];
    __weak WPCardPageController *weakController=controller;
    [UIApplication.sharedApplication openURL:url options:@{} completionHandler:^(BOOL success){
        if(!success)dispatch_async(dispatch_get_main_queue(), ^{[weakController alert:@"无法打开 Telegram 群链接，请稍后重试。"];});
    }];
}

#if WP_EDITION_COUPLE
/// Closes the plugin panel first so the action happens in WeChat below it.
static void WPPerformAfterClosingPanel(UIViewController *controller,NSString *name,id object){
    UIViewController *root=controller.navigationController.viewControllers.firstObject;
    void (^close)(void)=[root isKindOfClass:WPSettingsController.class]?((WPSettingsController *)root).onClose:nil;
    if(close)close();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,450*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[NSNotificationCenter.defaultCenter postNotificationName:name object:object];});
}
static void WPPerformLocalPreview(UIViewController *controller,NSString *kind){
    if(!controller)return;
    if(![WPPreferences() boolForKey:@"enabled"]){
        if(controller.presentedViewController)return;
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"桌宠已隐藏" message:@"请先在设置首页关闭「隐藏桌宠」，再预览动作。" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
        [controller presentViewController:alert animated:YES completion:nil];
        return;
    }
    WPPerformAfterClosingPanel(controller,@"WeChatPet.PreviewMissYou",kind);
}

@interface WPCoupleSettingsController : WPCardPageController
@end
@implementation WPCoupleSettingsController
- (void)viewDidLoad{self.title=@"情侣互动";[super viewDidLoad];}
- (void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];[self reloadCards];}
- (void)buildCards{
    __weak typeof(self) weakSelf=self;
    UIStackView *partner=[self addCard];
    [partner addArrangedSubview:[self rowWithTitle:@"我的对象" detail:[WPPreferences() stringForKey:@"partnerUsername"].length?@"宝宝":@"尚未选择" actionTitle:@"选择" handler:^{
        [weakSelf.navigationController pushViewController:[[WPPartnerPickerController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];}]];
    [partner addArrangedSubview:[self rowWithTitle:@"打开 TA 的聊天" detail:@"桌宠点击动作可在快捷设置中设置" actionTitle:@"测试" handler:^{
        WPPerformAfterClosingPanel(weakSelf,@"WeChatPet.OpenPartner",nil);}]];
#if WP_FEATURE_WORK_CHECKIN
    [self addSectionTitle:@"上班打卡提醒"];
    UIStackView *checkin=[self addCard];
    [checkin addArrangedSubview:[self switchRowWithTitle:@"工作日自动提醒 TA" detail:@"北京时间周一至周五 08:50–08:55 随机选一个时间；每天最多调用一次微信发送接口" on:[WPWorkCheckinReminder isEnabled] handler:^(BOOL on){
        [WPPreferences() setBool:on forKey:@"workCheckinEnabled"];
        [NSNotificationCenter.defaultCenter postNotificationName:WPSettingsDidChangeNotification object:nil];
    }]];
    [checkin addArrangedSubview:[self rowWithTitle:@"提醒文案" detail:[WPPreferences() stringForKey:@"workCheckinMessage"]?:[WPWorkCheckinReminder defaultMessage] actionTitle:@"编辑" handler:^{
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"上班打卡提醒" message:@"发送到已选择对象的微信聊天，最多 500 字。" preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *field){field.text=[WPPreferences() stringForKey:@"workCheckinMessage"]?:[WPWorkCheckinReminder defaultMessage];field.clearButtonMode=UITextFieldViewModeWhileEditing;}];
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){
            NSString *value=[alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if(value.length && value.length<=500){[WPPreferences() setObject:value forKey:@"workCheckinMessage"];[weakSelf reloadCards];}
            else [weakSelf alert:@"提醒文案须为 1–500 字。"];
        }]];
        [weakSelf presentViewController:alert animated:YES completion:nil];
    }]];
    NSString *last=[WPPreferences() stringForKey:@"workCheckinSentDay"];
    NSString *status=[WPPreferences() stringForKey:@"workCheckinLastStatus"];
    [checkin addArrangedSubview:[self rowWithTitle:@"最近执行" detail:last.length?[NSString stringWithFormat:@"%@ · %@",last,status?:@"已调用发送接口"]:(status?:@"尚未执行") actionTitle:nil handler:nil]];
    [self addNote:@"仅在本机微信运行于前台时尝试发送；若微信在选定时间后台运行，回到前台且仍在 08:55 前会补发。发送时会打开 TA 的聊天。微信关闭或锁屏时不会准时发送，实际送达请在微信聊天中确认。"];
#endif
    [self addSectionTitle:@"预览动作"];
    UIStackView *preview=[self addCard];
    UIStackView *buttons=[UIStackView new];buttons.axis=UILayoutConstraintAxisHorizontal;buttons.spacing=12;buttons.distribution=UIStackViewDistributionFillEqually;
    UIButton *miss=[self buttonWithTitle:@"想你了" primary:NO handler:^{WPPerformLocalPreview(weakSelf,@"miss");}];
    miss.accessibilityIdentifier=@"WPLocalPreviewMiss";[buttons addArrangedSubview:miss];
    UIButton *anger=[self buttonWithTitle:@"生气了" primary:NO handler:^{WPPerformLocalPreview(weakSelf,@"anger");}];
    anger.accessibilityIdentifier=@"WPLocalPreviewAnger";[buttons addArrangedSubview:anger];
    [preview addArrangedSubview:buttons];
    [preview addArrangedSubview:WPThemeLabel(@"预览收到互动时的动作，只在本机播放，不会发给 TA。",12,UIFontWeightRegular,WPThemeSecondaryText())];
    [self addSectionTitle:@"提醒规则"];
    UIStackView *rules=[self addCard];
    for(NSArray *item in @[@[@"想你了",@"5 分钟内收到只播放动画；超过 5 分钟才收到会补播一次，并留下红点等你回应。"],
                           @[@"生气了",@"收到后留下红点，回应前保持生气；互动记录和待回应提醒超过 3 天自动清除。"],
                           @[@"回应",@"想你了回应普通超时提醒；摸摸头回应一条生气和已有的全部普通超时提醒。"],
                           @[@"记录入口",@"摇晃桌宠默认打开互动记录，可在快捷设置中更改；长按后在桌宠附近来回抚摸可发送摸摸头。"]])
        [rules addArrangedSubview:[self rowWithTitle:item[0] detail:item[1] actionTitle:nil handler:nil]];
    UIStackView *log=[self addCard];
    [log addArrangedSubview:[self rowWithTitle:@"互动记录" detail:@"查看我们之间的互动" actionTitle:nil handler:^{[[WPOverlayManager sharedManager] openInteractions];}]];
}
@end

@interface WPConnectionSettingsController : WPCardPageController
@property(nonatomic) UITextField *urlField;
@property(nonatomic) UITextField *tokenField;
@property(nonatomic) UILabel *statusDetail;
@end
@implementation WPConnectionSettingsController
- (void)viewDidLoad{
    self.title=@"配对与连接";
    self.urlField=[UITextField new];self.urlField.placeholder=@"wss://你的服务/v1/ws";self.urlField.keyboardType=UIKeyboardTypeURL;self.urlField.autocapitalizationType=UITextAutocapitalizationTypeNone;self.urlField.autocorrectionType=UITextAutocorrectionTypeNo;self.urlField.text=[WPPreferences() stringForKey:@"coupleURL"];
    self.tokenField=[UITextField new];self.tokenField.secureTextEntry=YES;self.tokenField.autocapitalizationType=UITextAutocapitalizationTypeNone;self.tokenField.autocorrectionType=UITextAutocorrectionTypeNo;
    [super viewDidLoad];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(connectionChanged) name:WPConnectionStatusChangedNotification object:nil];
}
- (void)connectionChanged{self.statusDetail.text=[[WPOverlayManager sharedManager] connectionStatus];}
- (void)buildCards{
    __weak typeof(self) weakSelf=self;
    self.tokenField.placeholder=[[WPOverlayManager sharedManager] hasSavedCoupleToken]?@"令牌已保存，留空可保留":@"输入属于这台手机的配对令牌";
    UIStackView *status=[self addCard];
    UIView *row=[self rowWithTitle:@"连接状态" detail:[[WPOverlayManager sharedManager] connectionStatus] actionTitle:nil handler:nil];
    for(UIView *view in ((UIStackView *)row).arrangedSubviews)if([view isKindOfClass:UIStackView.class]){UIStackView *column=(id)view;if(column.arrangedSubviews.count>1)self.statusDetail=(id)column.arrangedSubviews[1];}
    [status addArrangedSubview:row];
#if WP_FEATURE_STEALTH
    [status addArrangedSubview:[self switchRowWithTitle:@"隐身" detail:[[WPOverlayManager sharedManager] stealthStatusText] on:[[WPOverlayManager sharedManager] stealthEnabled] handler:^(BOOL enabled){[[WPOverlayManager sharedManager] setStealthEnabled:enabled];[weakSelf reloadCards];}]];
#endif
    UIStackView *form=[self addCard];
    [form addArrangedSubview:[self fieldRowWithTitle:@"服务地址" field:self.urlField]];
    [form addArrangedSubview:[self fieldRowWithTitle:@"本机令牌" field:self.tokenField]];
    [form addArrangedSubview:[self buttonWithTitle:@"保存并连接" primary:YES handler:^{[weakSelf save];}]];
    [self addNote:@"每台手机只填自己的令牌。令牌保存在钥匙串，不会放进地址。更换服务入口时保留原令牌和待送达记录。"];
}
- (void)save{
    [self.view endEditing:YES];
    NSURL *url=[NSURL URLWithString:[self.urlField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]];
    if(!WPIsValidCoupleURL(url)){[self alert:@"请填写完整的 wss://域名/v1/ws 服务地址，不要包含令牌、用户名或查询参数。"];return;}
    if(![[WPOverlayManager sharedManager] configureCoupleURL:url token:self.tokenField.text ?: @""]){[self alert:[WPPreferences() stringForKey:@"connectionStatus"] ?: @"连接配置未更新，请稍后重试。"];return;}
    self.tokenField.text=@"";[self reloadCards];[self alert:@"连接配置已更新，请查看连接状态。"];
}
@end
#endif

@interface WPPluginIntroductionController : WPCardPageController
@end
@implementation WPPluginIntroductionController
- (void)viewDidLoad{self.title=@"插件介绍";[super viewDidLoad];}
- (void)buildCards{
    UIStackView *intro=[self addCard];
    [intro addArrangedSubview:WPThemeLabel(WPEditionName(),20,UIFontWeightSemibold,WPThemePrimaryText())];
    NSString *summary=WP_EDITION_COUPLE?@"两台手机配对的微信双人桌宠。默认形象是%@，可在桌宠库选择或导入喜欢的形象。":@"一只陪你聊天的微信桌宠。默认形象是%@，可在桌宠库选择或导入喜欢的形象。";
    [intro addArrangedSubview:WPThemeLabel([NSString stringWithFormat:summary,WPEditionDefaultPetName()],14,UIFontWeightRegular,WPThemeSecondaryText())];
    [self addSectionTitle:@"主要功能"];
    UIStackView *features=[self addCard];
#if WP_EDITION_COUPLE
    [features addArrangedSubview:[self rowWithTitle:@"双人互动" detail:@"想你了、生气了和摸摸头会同步到对方桌宠，需要自建配对服务。" actionTitle:nil handler:nil]];
#endif
    [features addArrangedSubview:[self rowWithTitle:@"快捷聊天" detail:@"点击桌宠打开聊天列表，快速进入会话。" actionTitle:nil handler:nil]];
    [features addArrangedSubview:[self rowWithTitle:@"消息弹幕" detail:@"在微信中查看新消息提醒，显示方式可在设置中调整。" actionTitle:nil handler:nil]];
    [features addArrangedSubview:[self rowWithTitle:@"桌宠与手势" detail:@"调整大小、位置和外观，自定义长按与摇晃的功能。" actionTitle:nil handler:nil]];
    [features addArrangedSubview:[self rowWithTitle:@"聊天参谋" detail:@"配置模型服务后，可在聊天中获取分析和回复建议。" actionTitle:nil handler:nil]];
    [self addNote:@"使用聊天参谋时，选取的聊天内容会发送给你配置的模型服务。"];

}
@end

@interface WPReminderSettingsController : WPCardPageController
@end
@implementation WPReminderSettingsController
- (void)viewDidLoad{
    self.title=@"提醒方式";
    [super viewDidLoad];
}
- (void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];[self reloadCards];}
- (UIView *)timeRow:(BOOL)start{
    UIStackView *row=[UIStackView new];row.axis=UILayoutConstraintAxisHorizontal;row.spacing=12;row.alignment=UIStackViewAlignmentCenter;
    UILabel *label=WPThemeLabel(start?@"开始时间":@"结束时间",15,UIFontWeightMedium,WPThemePrimaryText());
    [label setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];[row addArrangedSubview:label];
    UIDatePicker *picker=[UIDatePicker new];picker.datePickerMode=UIDatePickerModeTime;picker.preferredDatePickerStyle=UIDatePickerStyleCompact;
    NSInteger minute=WPQuietMinute(start);picker.date=[NSCalendar.currentCalendar dateBySettingHour:minute/60 minute:minute%60 second:0 ofDate:NSDate.date options:0];
    picker.accessibilityIdentifier=start?@"WPQuietStartTime":@"WPQuietEndTime";picker.accessibilityLabel=label.text;
    __weak UIDatePicker *weakPicker=picker;
    [picker addAction:[UIAction actionWithHandler:^(__unused UIAction *action){
        NSDateComponents *parts=[NSCalendar.currentCalendar components:NSCalendarUnitHour|NSCalendarUnitMinute fromDate:weakPicker.date];
        [WPPreferences() setInteger:parts.hour*60+parts.minute forKey:start?@"quietStartMinute":@"quietEndMinute"];
        [NSNotificationCenter.defaultCenter postNotificationName:WPSettingsDidChangeNotification object:nil];
    }] forControlEvents:UIControlEventValueChanged];
    [row addArrangedSubview:picker];return row;
}
- (void)buildCards{
    __weak typeof(self) weakSelf=self;
    void (^changed)(void)=^{[NSNotificationCenter.defaultCenter postNotificationName:WPSettingsDidChangeNotification object:nil];};
    UIStackView *intensity=[self addCard];
    UIView *mode=[self segmentedRowWithTitle:@"提醒强度" items:@[@"仅头像",@"轻动作",@"完整提醒"] selected:WPConfiguredReminderIntensity() handler:^(NSInteger index){
        [WPPreferences() setInteger:index forKey:@"reminderIntensity"];changed();
    }];mode.accessibilityIdentifier=@"WPReminderIntensity";[intensity addArrangedSubview:mode];
    [self addNote:WP_EDITION_COUPLE?@"仅头像：保留未读头像和互动红点。轻动作：收到消息或互动时播放一次轻动作。完整提醒：保留原有闪烁、气泡、互动动画与触感。手动点击和预览动作不受影响。":@"仅头像：保留未读头像。轻动作：收到消息时播放一次轻动作。完整提醒：保留闪烁、气泡和触感。"];
    [self addSectionTitle:@"安静时段"];
    UIStackView *quiet=[self addCard];
    [quiet addArrangedSubview:[self switchRowWithTitle:@"启用安静时段" detail:@"按手机本地时间暂停新消息的动作、气泡和触感；头像跳转继续可用" on:[WPPreferences() boolForKey:@"quietTimeEnabled"] handler:^(BOOL on){
        [WPPreferences() setBool:on forKey:@"quietTimeEnabled"];changed();[weakSelf reloadCards];
    }]];
    if([WPPreferences() boolForKey:@"quietTimeEnabled"]){[quiet addArrangedSubview:[self timeRow:YES]];[quiet addArrangedSubview:[self timeRow:NO]];}
    [self addNote:@"可跨午夜，例如 22:00–08:00；开始与结束相同表示全天安静。"];
    [self addSectionTitle:@"指定联系人提醒"];
    UIStackView *contacts=[self addCard];
    [contacts addArrangedSubview:[self switchRowWithTitle:@"仅指定联系人触发动作" detail:@"只限制新消息的动作提醒；未读头像和聊天入口继续保留" on:[WPPreferences() boolForKey:@"reminderContactsOnly"] handler:^(BOOL on){
        [WPPreferences() setBool:on forKey:@"reminderContactsOnly"];changed();[weakSelf reloadCards];
    }]];
    if([WPPreferences() boolForKey:@"reminderContactsOnly"]){
        for(NSString *username in WPReminderContactUsernames()){
            NSString *name=[WPPartnerContact displayNameForUsername:username];
            [contacts addArrangedSubview:[self rowWithTitle:name.length?name:username detail:nil actionTitle:@"移除" handler:^{
                NSMutableArray *names=[WPReminderContactUsernames() mutableCopy];[names removeObject:username];
                [WPPreferences() setObject:[names componentsJoinedByString:@", "] forKey:@"reminderContactUsernames"];changed();[weakSelf reloadCards];
            }]];
        }
        UIButton *add=[self buttonWithTitle:@"添加联系人" primary:NO handler:^{
            if(WPReminderContactUsernames().count>=100){[weakSelf alert:@"最多添加 100 位提醒联系人，请先移除一位再添加。"];return;}
            WPPartnerPickerController *picker=[[WPPartnerPickerController alloc] initWithStyle:UITableViewStyleInsetGrouped];picker.pickerTitle=@"选择提醒联系人";
            picker.selectionHandler=^(NSString *username,__unused NSString *displayName){
                NSMutableOrderedSet *names=[NSMutableOrderedSet orderedSetWithArray:WPReminderContactUsernames()];[names addObject:username];
                [WPPreferences() setObject:[names.array componentsJoinedByString:@", "] forKey:@"reminderContactUsernames"];changed();[weakSelf reloadCards];
            };
            [weakSelf.navigationController pushViewController:picker animated:YES];
        }];add.accessibilityIdentifier=@"WPAddReminderContact";[contacts addArrangedSubview:add];
    }
    [self addNote:@"从现有微信好友中逐个添加，最多 100 位；列表为空时暂停动作提醒。"];
}
@end

@interface WPQuickActionsController : WPCardPageController
@end
@implementation WPQuickActionsController
- (void)viewDidLoad{self.title=@"快捷设置";[super viewDidLoad];}
- (void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];[self reloadCards];}
- (UIView *)tapActionRowWithTitle:(NSString *)title doubleTap:(BOOL)doubleTap handler:(void (^)(WPTapAction))handler{
    UIStackView *column=[UIStackView new];column.axis=UILayoutConstraintAxisVertical;column.spacing=8;
    [column addArrangedSubview:WPThemeLabel(title,15,UIFontWeightMedium,WPThemePrimaryText())];
    NSArray<NSNumber *> *actions=WPAvailableTapActions();
    NSDictionary *names=@{@(WPTapActionPartnerChat):@"对象聊天",@(WPTapActionQuickChat):@"聊天浮窗",@(WPTapActionSettings):@"设置",@(WPTapActionChatAdvisor):@"参谋聊天",@(WPTapActionDirectAdvisor):@"直接参谋"};
    NSMutableArray *titles=[NSMutableArray new];for(NSNumber *action in actions)[titles addObject:names[action]];
    UISegmentedControl *choice=[[UISegmentedControl alloc] initWithItems:titles];
    choice.selectedSegmentIndex=[actions indexOfObject:@(WPConfiguredTapAction(doubleTap))];
    choice.accessibilityLabel=title;
    choice.accessibilityIdentifier=doubleTap?@"WPTapActionDouble":@"WPTapActionSingle";
    __weak UISegmentedControl *weakChoice=choice;
    [choice addAction:[UIAction actionWithHandler:^(__unused UIAction *action){
        if(weakChoice.selectedSegmentIndex>=0 && (NSUInteger)weakChoice.selectedSegmentIndex<actions.count)handler((WPTapAction)actions[weakChoice.selectedSegmentIndex].integerValue);
    }] forControlEvents:UIControlEventValueChanged];
    [column addArrangedSubview:choice];
    return column;
}
- (UIView *)gestureActionRow:(BOOL)longPress {
    NSMutableArray<NSString *> *values=[(longPress?@[@"menu",@"quickChat",@"settings",@"moments",@"advisor",@"advisorDirect",@"advisorHistory",@"none"]:@[@"quickChat",@"settings",@"moments",@"advisor",@"advisorDirect",@"advisorHistory",@"none"]) mutableCopy];
    if(WP_EDITION_COUPLE)[values insertObjects:@[@"interactions",@"partnerChat"] atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(longPress?1:0,2)]];
    NSDictionary *names=@{@"interactions":@"互动记录",@"partnerChat":@"对象聊天",@"menu":@"快捷菜单",@"quickChat":@"快捷聊天",@"settings":@"桌宠设置",@"moments":@"朋友圈",@"advisor":@"参谋聊天",@"advisorDirect":@"直接参谋",@"advisorHistory":@"参谋记录",@"none":@"不执行"};
    NSString *title=longPress?@"长按桌宠":@"摇晃桌宠";
    NSString *selected=WPConfiguredGestureAction(longPress);
    __weak typeof(self) weakSelf=self;
    return [self rowWithTitle:title detail:names[selected] actionTitle:@"选择" handler:^{
        NSMutableArray<WPChoiceItem *> *items=[NSMutableArray new];
        NSDictionary *icons=@{@"interactions":@"heart.text.square",@"partnerChat":@"heart.circle",@"menu":@"square.grid.2x2",@"quickChat":@"bubble.left.and.bubble.right",@"settings":@"gearshape",@"moments":@"camera",@"advisor":@"sparkles",@"advisorDirect":@"bolt.fill",@"advisorHistory":@"clock.arrow.circlepath",@"none":@"minus.circle"};
        for(NSString *value in values){
            [items addObject:[WPChoiceItem itemWithTitle:names[value] icon:icons[value] destructive:NO handler:^{
                WPSetConfiguredGestureAction(longPress,value);
                if([value isEqualToString:@"quickChat"])[WPPreferences() setBool:YES forKey:@"quickChatEnabled"];
                [NSNotificationCenter.defaultCenter postNotificationName:WPSettingsDidChangeNotification object:nil];
                [weakSelf reloadCards];
            }]];
        }
        WPPresentChoiceSheet(weakSelf,title,items);
    }];
}
- (void)buildCards{
    __weak typeof(self) weakSelf=self;
    void (^changed)(void)=^{[NSNotificationCenter.defaultCenter postNotificationName:WPSettingsDidChangeNotification object:nil];};
    [self addSectionTitle:@"桌宠手势"];
    UIStackView *tapActions=[self addCard];
    for(NSNumber *gesture in @[@NO,@YES]){
        BOOL doubleTap=gesture.boolValue;
        [tapActions addArrangedSubview:[self tapActionRowWithTitle:doubleTap?@"双击桌宠":@"单击桌宠" doubleTap:doubleTap handler:^(WPTapAction action){
            if(action==WPTapActionQuickChat && !WPQuickChatEnabled())
                [WPPreferences() setBool:YES forKey:@"quickChatEnabled"];
            if((action==WPTapActionChatAdvisor || action==WPTapActionDirectAdvisor) && !WPChatAdvisor.isReady)
                [weakSelf alert:@"已设为聊天参谋。还需要在设置首页的「聊天参谋」里填写 API Key 并启用。"];
            WPSetConfiguredTapAction(doubleTap,action);
            changed();[weakSelf reloadCards];
        }]];
    }
    [tapActions addArrangedSubview:[self rowWithTitle:@"直接参谋预设" detail:WPChatAdvisor.currentPreset.title actionTitle:@"选择" handler:^{
        NSMutableArray *items=[NSMutableArray new];
        for(WPChatAdvisorPreset *preset in WPChatAdvisorPreset.builtinPresets){
            [items addObject:[WPChoiceItem itemWithTitle:preset.title icon:@"sparkles" destructive:NO handler:^{[WPChatAdvisor setPresetIdentifier:preset.identifier];[weakSelf reloadCards];}]];
        }
        WPPresentChoiceSheet(weakSelf,@"选择直接参谋预设",items);
    }]];
    [self addNote:@"参谋聊天每次选择场景；直接参谋使用上方固定预设立即分析。"];
    [tapActions addArrangedSubview:[self switchRowWithTitle:@"贴边时直接执行点击动作" detail:@"单击和双击直接执行上方设置；关闭时先展开桌宠" on:WPQuickChatOptionBool(@"edgeTapActions") handler:^(BOOL on){WPQuickChatSetOption(@"edgeTapActions",@(on));}]];
    UIStackView *gesture=tapActions;
    [gesture addArrangedSubview:[self sliderRowWithTitle:@"长按菜单圆弧" value:[WPPreferences() doubleForKey:@"menuScale"] minimum:.6 maximum:4 format:^NSString *(float v){return [NSString stringWithFormat:@"%.0f 点",v*80];} handler:^(float v){
        [WPPreferences() setDouble:v forKey:@"menuScale"];changed();[[WPOverlayManager sharedManager] previewMenuRadius];}]];
    [self addNote:@"圆弧半径 48–320 点，拖动即时预览；屏幕放不下时会自动收小。"];
    UIView *longPress=[self gestureActionRow:YES]; longPress.accessibilityIdentifier=@"WPLongPressAction"; [gesture addArrangedSubview:longPress];
    [gesture addArrangedSubview:[self rowWithTitle:@"长按菜单项目" detail:@"选择显示内容并拖动排序" actionTitle:@"设置" handler:^{[weakSelf.navigationController pushViewController:[WPMenuSettingsController new] animated:YES];}]];
    UIView *shakeAction=[self gestureActionRow:NO]; shakeAction.accessibilityIdentifier=@"WPShakeAction"; [gesture addArrangedSubview:shakeAction];
    NSInteger level=WPShakeSensitivityFromPreferenceValue([WPPreferences() objectForKey:@"shakeSensitivity"]);
    [gesture addArrangedSubview:[self segmentedRowWithTitle:@"摇晃灵敏度" items:@[@"低",@"中",@"高"] selected:level handler:^(NSInteger index){[WPPreferences() setInteger:index forKey:@"shakeSensitivity"];}]];
    [gesture addArrangedSubview:WPThemeLabel(@"按住桌宠快速左右来回拖动执行所选动作；普通拖动只移动位置。灵敏度越高，摇晃幅度和次数要求越低。",12,UIFontWeightRegular,WPThemeSecondaryText())];
    UIView *lock=[self switchRowWithTitle:@"锁定桌宠位置" detail:@"防止误拖动；点击、长按和摇晃动作继续可用。键盘弹出时临时避让，收起后恢复原位。" on:WPPositionLocked() handler:^(BOOL on){[WPPreferences() setBool:on forKey:@"positionLocked"];changed();}];
    ((UIStackView *)lock).arrangedSubviews.lastObject.accessibilityIdentifier=@"WPPositionLockSwitch";[gesture addArrangedSubview:lock];
    [self addSectionTitle:@"贴边与收起"];
    UIStackView *edge=[self addCard];
    [edge addArrangedSubview:[self switchRowWithTitle:@"贴边自动收起" detail:@"靠边闲置约 3 秒后探头" on:[WPPreferences() boolForKey:@"autoPeek"] handler:^(BOOL on){[WPPreferences() setBool:on forKey:@"autoPeek"];changed();}]];
    [edge addArrangedSubview:[self switchRowWithTitle:@"有未读时也允许收起" detail:@"贴边收起后仍显示未读头像，可直接点击进入聊天" on:WPAllowUnreadPeek() handler:^(BOOL on){[WPPreferences() setBool:on forKey:@"allowUnreadPeek"];changed();}]];
    UIView *advisorPeek=[self switchRowWithTitle:@"有参谋红点时也允许收起" detail:@"收起后红点仍可点击；若同时有未读头像，还需开启上方开关" on:WPAllowAdvisorPeek() handler:^(BOOL on){[WPPreferences() setBool:on forKey:@"allowAdvisorPeek"];changed();}];
    ((UIStackView *)advisorPeek).arrangedSubviews.lastObject.accessibilityIdentifier=@"WPAllowAdvisorPeekSwitch";
    [edge addArrangedSubview:advisorPeek];
    [self addNote:@"横屏与竖屏分别记住最后一次拖动的位置；键盘避让不会覆盖保存的位置。锁定后仍可拖动手指摇晃桌宠，人物本身保持原位。"];

    [self addSectionTitle:@"便捷聊天"];
    BOOL enabled=WPQuickChatEnabled();
    UIStackView *quick=[self addCard];
    UIView *enableQuick=[self switchRowWithTitle:@"便捷聊天浮窗" detail:@"按设定的点击动作展开最近聊天，点头像进入聊天；未读头像提醒可在外观设置中单独开启" on:enabled handler:^(BOOL on){
        [WPPreferences() setBool:on forKey:@"quickChatEnabled"];changed();[weakSelf reloadCards];}];
    ((UIStackView *)enableQuick).arrangedSubviews.lastObject.accessibilityIdentifier=@"WPQuickChatEnableSwitch";
    [quick addArrangedSubview:enableQuick];
    WPAddQuickChatGestureRows(self,quick);
    UIView *flash=[self switchRowWithTitle:@"新消息闪烁提醒" detail:@"新消息到达时桌宠探出、闪烁并显示发送方头像；免打扰的聊天不提醒" on:WPQuickChatFlashEnabled() handler:^(BOOL on){
        [WPPreferences() setBool:on forKey:@"quickChatFlash"];changed();}];
    flash.userInteractionEnabled=enabled;flash.alpha=enabled?1:.4;
    [quick addArrangedSubview:flash];
    [quick addArrangedSubview:[self rowWithTitle:@"快捷聊天设置" detail:@"侧栏外观、消息提示与会话过滤" actionTitle:@"设置" handler:^{[weakSelf.navigationController pushViewController:[WPQuickChatSettingsController new] animated:YES];}]];
    [quick addArrangedSubview:[self rowWithTitle:@"提醒方式" detail:@"提醒强度、安静时段与指定联系人" actionTitle:nil handler:^{[weakSelf.navigationController pushViewController:[WPReminderSettingsController new] animated:YES];}]];
    [self addSectionTitle:@"恢复默认"];
    UIStackView *resetGestures=[self addCard];
    [resetGestures addArrangedSubview:[self rowWithTitle:@"恢复原来参数" detail:@"恢复本页手势及便捷聊天设置" actionTitle:@"恢复" handler:^{
        for(NSString *key in @[@"menuScale",@"shakeSensitivity",@"positionLocked",@"singleTapAction",@"doubleTapAction",@"longPressAction",@"shakeAction",@"autoPeek",@"allowUnreadPeek",@"allowAdvisorPeek",@"quickChatEnabled",@"quickChatFlash",@"quickChat.tapMode",@"quickChat.doubleTapMode",@"quickChat.holdMode",@"quickChat.edgeTapActions",@"quickChat.arrivalTap",@"quickChat.openMode"])[WPPreferences() removeObjectForKey:key];
        WPMenuResetActions();changed();[weakSelf reloadCards];}]];
}
@end

@interface WPAppearanceSettingsController : WPCardPageController <UIDocumentPickerDelegate>
@property(nonatomic) NSString *importStatus;
@end

@interface WPPetSettingsController : WPCardPageController
@end
@implementation WPPetSettingsController
- (void)viewDidLoad{self.title=@"桌宠设置";[super viewDidLoad];}
- (void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];[self reloadCards];}
- (void)buildCards{
    __weak typeof(self) weakSelf=self;
    NSString *directory=WPSelectedPetDirectory();
    NSData *petData=[NSData dataWithContentsOfFile:[(directory.length?directory:WPDefaultPetDirectory()) stringByAppendingPathComponent:@"pet.json"]];
    id metadata=petData?[NSJSONSerialization JSONObjectWithData:petData options:0 error:nil]:nil;
    NSString *name=[metadata isKindOfClass:NSDictionary.class] && [metadata[@"displayName"] isKindOfClass:NSString.class]?metadata[@"displayName"]:@"当前桌宠";
    UIStackView *current=[self addCard];
    UIView *currentRow=[self rowWithTitle:@"当前桌宠" detail:name actionTitle:nil handler:^{WPCatalogController *library=[WPCatalogController new];library.startsWithDownloadedPets=YES;[weakSelf.navigationController pushViewController:library animated:YES];}];
    currentRow.accessibilityIdentifier=@"WPCurrentPetLocalLibrary";[current addArrangedSubview:currentRow];
    [current addArrangedSubview:[self rowWithTitle:@"外观设置" detail:@"本地桌宠库、资源导入与消息头像" actionTitle:@"打开" handler:^{[weakSelf.navigationController pushViewController:[WPAppearanceSettingsController new] animated:YES];}]];
    void (^changed)(void)=^{[NSNotificationCenter.defaultCenter postNotificationName:WPSettingsDidChangeNotification object:nil];};
    UIStackView *look=[self addCard];
    [look addArrangedSubview:[self sliderRowWithTitle:@"大小" value:[WPPreferences() doubleForKey:@"petSize"] minimum:48 maximum:160 format:^NSString *(float v){return [NSString stringWithFormat:@"%.0f 点",v];} handler:^(float v){[WPPreferences() setDouble:v forKey:@"petSize"];changed();}]];
    [look addArrangedSubview:[self sliderRowWithTitle:@"不透明度" value:[WPPreferences() doubleForKey:@"petOpacity"] minimum:.25 maximum:1 format:^NSString *(float v){return [NSString stringWithFormat:@"%.0f%%",v*100];} handler:^(float v){[WPPreferences() setDouble:v forKey:@"petOpacity"];changed();}]];
    UIStackView *reset=[self addCard];
    [reset addArrangedSubview:[self rowWithTitle:@"恢复默认桌宠与位置" detail:@"恢复默认桌宠、大小、透明度和位置" actionTitle:@"恢复" handler:^{
        WPResetSelectedPet();
        WPResetPositionAnchors();
        for(NSString *key in @[@"petSize",@"petOpacity"])[WPPreferences() removeObjectForKey:key];
        [NSNotificationCenter.defaultCenter postNotificationName:WPSelectedPetDidChangeNotification object:nil];changed();[weakSelf reloadCards];}]];
    [self addSectionTitle:@"插件恢复"];
    UIStackView *recovery=[self addCard];
    UIView *pause=[self switchRowWithTitle:@"暂停插件浮层" detail:@"暂停桌宠、弹幕和快捷聊天" on:WPOverlayManager.sharedManager.recoveryPaused handler:^(BOOL paused){[WPOverlayManager.sharedManager setRecoveryPaused:paused];[weakSelf reloadCards];}];
    pause.accessibilityIdentifier=@"WPRecoveryPauseControl";[recovery addArrangedSubview:pause];
    UIView *retry=[self rowWithTitle:WPOverlayManager.sharedManager.recoveryPaused?@"恢复插件":@"重新恢复插件" detail:@"无需点击桌宠即可恢复" actionTitle:@"恢复" handler:^{if(WPOverlayManager.sharedManager.recoveryPaused)[WPOverlayManager.sharedManager setRecoveryPaused:NO];else [WPOverlayManager.sharedManager retryRecovery];[weakSelf reloadCards];}];
    retry.accessibilityIdentifier=@"WPRecoveryRetryControl";[recovery addArrangedSubview:retry];
}
@end

@implementation WPAppearanceSettingsController
- (void)viewDidLoad{self.title=@"外观设置";[super viewDidLoad];}
- (void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];[self reloadCards];}
- (UIView *)indicatorOffsetRowWithTitle:(NSString *)title key:(NSString *)key value:(CGFloat)value horizontal:(BOOL)horizontal identifier:(NSString *)identifier enabled:(BOOL)enabled{
    CGFloat limit=horizontal?160:200;
    UIView *row=[self sliderRowWithTitle:title value:value minimum:-limit maximum:limit format:^NSString *(float v){
        NSInteger points=lroundf(v);
        if(!points)return @"默认位置";
        NSString *direction=horizontal?(points<0?@"左":@"右"):(points<0?@"上":@"下");
        return [NSString stringWithFormat:@"%@ %ld 点",direction,(long)labs(points)];
    } handler:^(float v){
        [WPPreferences() setDouble:v forKey:key];
        [NSNotificationCenter.defaultCenter postNotificationName:WPSettingsDidChangeNotification object:nil];
    }];
    UISlider *slider=(id)((UIStackView *)row).arrangedSubviews.lastObject;
    slider.accessibilityIdentifier=identifier;slider.enabled=enabled;
    row.userInteractionEnabled=enabled;row.alpha=enabled?1:.4;
    return row;
}
- (void)buildCards{
    __weak typeof(self) weakSelf=self;
    NSString *selected=WPSelectedPetDirectory();
    NSString *currentPet=(!selected.length || [selected isEqualToString:WPDefaultPetDirectory()])?[@"默认 " stringByAppendingString:WPEditionDefaultPetName()]:selected.lastPathComponent;
    UIStackView *current=[self addCard];
    [current addArrangedSubview:[self rowWithTitle:@"当前桌宠" detail:currentPet actionTitle:nil handler:^{WPCatalogController *library=[WPCatalogController new];library.startsWithDownloadedPets=YES;[weakSelf.navigationController pushViewController:library animated:YES];}]];
    [self addSectionTitle:@"未读聊天头像"];
    BOOL unreadEnabled=WPUnreadAvatarEnabled();
    UIStackView *unread=[self addCard];
    UIView *toggleRow=[self switchRowWithTitle:@"显示最新未读头像" detail:@"在桌宠正上方显示最新未读聊天的头像，点击进入聊天；排除折叠群聊和免打扰消息。可在快捷设置中允许有未读时贴边收起。" on:unreadEnabled handler:^(BOOL on){
        [WPPreferences() setBool:on forKey:@"unreadAvatarEnabled"];
        [NSNotificationCenter.defaultCenter postNotificationName:WPSettingsDidChangeNotification object:nil];
        [weakSelf reloadCards];
    }];
    UISwitch *unreadSwitch=(id)((UIStackView *)toggleRow).arrangedSubviews.lastObject;
    unreadSwitch.accessibilityIdentifier=@"WPLatestUnreadAvatarSwitch";
    [unread addArrangedSubview:toggleRow];
    CGPoint avatarOffset=WPUnreadAvatarOffset();
    [unread addArrangedSubview:[self indicatorOffsetRowWithTitle:@"头像左右位置" key:@"unreadAvatarOffsetX" value:avatarOffset.x horizontal:YES identifier:@"WPUnreadAvatarOffsetX" enabled:unreadEnabled]];
    [unread addArrangedSubview:[self indicatorOffsetRowWithTitle:@"头像上下位置" key:@"unreadAvatarOffsetY" value:avatarOffset.y horizontal:NO identifier:@"WPUnreadAvatarOffsetY" enabled:unreadEnabled]];
    [self addNote:@"头像提醒可单独使用，无需开启便捷聊天浮窗。头像暂未加载时显示聊天名称占位。"];
#if WP_EDITION_COUPLE
    [self addSectionTitle:@"互动红点位置"];
    UIStackView *badge=[self addCard];
    CGPoint badgeOffset=WPInteractionBadgeOffset();
    [badge addArrangedSubview:[self indicatorOffsetRowWithTitle:@"红点左右位置" key:@"interactionBadgeOffsetX" value:badgeOffset.x horizontal:YES identifier:@"WPInteractionBadgeOffsetX" enabled:YES]];
    [badge addArrangedSubview:[self indicatorOffsetRowWithTitle:@"红点上下位置" key:@"interactionBadgeOffsetY" value:badgeOffset.y horizontal:NO identifier:@"WPInteractionBadgeOffsetY" enabled:YES]];
    [self addNote:@"以默认位置为起点，左右可调 160 点、上下可调 200 点。拖动立即生效，靠近屏幕边缘时会限制在屏幕内。"];
    NSArray *indicatorKeys=@[@"unreadAvatarOffsetX",@"unreadAvatarOffsetY",@"interactionBadgeOffsetX",@"interactionBadgeOffsetY"];
    UIStackView *resetCard=badge;NSString *resetTitle=@"恢复头像与红点默认位置";
#else
    NSArray *indicatorKeys=@[@"unreadAvatarOffsetX",@"unreadAvatarOffsetY"];
    UIStackView *resetCard=unread;NSString *resetTitle=@"恢复头像默认位置";
#endif
    UIButton *resetIndicators=[self buttonWithTitle:resetTitle primary:NO handler:^{
        for(NSString *key in indicatorKeys)[WPPreferences() removeObjectForKey:key];
        [NSNotificationCenter.defaultCenter postNotificationName:WPSettingsDidChangeNotification object:nil];
        [weakSelf reloadCards];
    }];
    resetIndicators.accessibilityIdentifier=@"WPResetIndicatorPositions"; [resetCard addArrangedSubview:resetIndicators];
    [self addSectionTitle:@"桌宠资源"];
    UIStackView *card=[self addCard];
    [card addArrangedSubview:[self rowWithTitle:@"在线桌宠库" detail:@"两列预览，下载后长期保存在本机" actionTitle:nil handler:^{[weakSelf.navigationController pushViewController:[WPCatalogController new] animated:YES];}]];
    [card addArrangedSubview:[self rowWithTitle:@"从桌宠包导入" detail:self.importStatus?:@"选择 .zip 外观包" actionTitle:@"导入" handler:^{
        UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeZIP] asCopy:YES];picker.delegate=weakSelf;picker.allowsMultipleSelection=NO;
        [weakSelf presentViewController:picker animated:YES completion:nil];}]];
    [self addNote:@"外观包是 pet.json 加透明 PNG/WebP 图集，和安装插件用的 ZIP 不是一种文件。"];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls{
    NSURL *url=urls.firstObject;if(!url)return;
    self.importStatus=@"正在检查并导入桌宠包…";[self reloadCards];
    NSURL *root=[NSURL fileURLWithPath:[WPDataDirectory() stringByAppendingPathComponent:@"ImportedPets"] isDirectory:YES];
    [WPPetImporter importZipAtURL:url destinationRoot:root completion:^(NSURL *directory,NSError *error){
        self.importStatus=nil;
        if(directory){if(!WPSelectPetDirectory(directory)){[self alert:@"桌宠已导入，但选择未能保存，请稍后重试。"];return;}WPCatalogRecordUsageForDirectory(directory);[NSNotificationCenter.defaultCenter postNotificationName:WPSelectedPetDidChangeNotification object:nil];[self alert:@"桌宠包已导入并切换使用。"];}
        else [self alert:error.localizedDescription ?: @"导入未完成，请检查桌宠包格式。"];
        [self reloadCards];
    }];
}
@end

#pragma mark - Home

@interface WPSettingsController ()
@property(nonatomic) CGFloat builtWidth;
#if WP_EDITION_COUPLE
@property(nonatomic,weak) UILabel *peerLabel;
@property(nonatomic) NSTimer *peerTimer;
#endif
@end
@implementation WPSettingsController
- (void)viewDidLoad{
    self.title=WPEditionName();[super viewDidLoad];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"完成" style:UIBarButtonItemStyleDone target:self action:@selector(done)];
    NSArray *names=@[WPSettingsDidChangeNotification];
#if WP_EDITION_COUPLE
    names=@[WPConnectionStatusChangedNotification,WPCoupleHistoryDidChangeNotification,WPSettingsDidChangeNotification,@"WeChatPet.PeerStatusChanged"];
#endif
    for(NSString *name in names)
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reloadCards) name:name object:nil];
}
- (void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];[self reloadCards];}
#if WP_EDITION_COUPLE
- (void)viewDidAppear:(BOOL)animated{[super viewDidAppear:animated];__weak typeof(self) weakSelf=self;self.peerTimer=[NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(__unused NSTimer *timer){weakSelf.peerLabel.text=[[WPOverlayManager sharedManager] peerStatusText];}];}
- (void)viewWillDisappear:(BOOL)animated{[super viewWillDisappear:animated];[self.peerTimer invalidate];self.peerTimer=nil;}
/// Partner, connection and pending interactions, above the feature grid.
- (UIView *)coupleCard{
    UIView *card=[UIView new];card.backgroundColor=WPThemeCard();card.layer.cornerRadius=WPThemeCardRadius;card.layer.cornerCurve=kCACornerCurveContinuous;
    UIImage *coupleIcon=[UIImage imageWithContentsOfFile:[WPResourceDirectory() stringByAppendingPathComponent:@"couple-header-icon.png"]];
    UIView *tile;
    if(coupleIcon){
        tile=[UIView new];tile.backgroundColor=WPThemeElevated();tile.layer.cornerRadius=17;tile.translatesAutoresizingMaskIntoConstraints=NO;
        UIImageView *avatar=[[UIImageView alloc] initWithImage:[coupleIcon imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal]];
        avatar.contentMode=UIViewContentModeScaleAspectFit;avatar.translatesAutoresizingMaskIntoConstraints=NO;[tile addSubview:avatar];
        [NSLayoutConstraint activateConstraints:@[[tile.widthAnchor constraintEqualToConstant:58],[tile.heightAnchor constraintEqualToConstant:58],
            [avatar.centerXAnchor constraintEqualToAnchor:tile.centerXAnchor],[avatar.centerYAnchor constraintEqualToAnchor:tile.centerYAnchor],
            [avatar.widthAnchor constraintEqualToConstant:48],[avatar.heightAnchor constraintEqualToConstant:48]]];
    }else tile=WPThemeIconTile([UIImage systemImageNamed:@"heart.circle.fill"],UIColor.systemPinkColor,58);
    NSString *partner=[WPPreferences() stringForKey:@"partnerUsername"].length?@"宝宝":nil;
    UILabel *title=WPThemeLabel(partner.length?[NSString stringWithFormat:@"我和 %@",partner]:@"还没有选择对象",17,UIFontWeightSemibold,WPThemePrimaryText());
    NSString *status=[[WPOverlayManager sharedManager] connectionStatus];BOOL connected=[status containsString:@"已连接"];
    NSUInteger pending=WPCoupleHistory.sharedHistory.badgeCount;
    UIStackView *pills=[UIStackView new];pills.axis=UILayoutConstraintAxisHorizontal;pills.spacing=6;pills.alignment=UIStackViewAlignmentCenter;
    [pills addArrangedSubview:WPThemePill(connected?@"已连接":@"未连接",connected?UIColor.systemGreenColor:UIColor.systemOrangeColor)];
    if(pending)[pills addArrangedSubview:WPThemePill([NSString stringWithFormat:@"待回应 %lu",(unsigned long)pending],UIColor.systemRedColor)];
    if(WPCoupleHistory.sharedHistory.hasPendingAnger)[pills addArrangedSubview:WPThemePill(@"生气中",UIColor.systemGrayColor)];
    if(WP_FEATURE_STEALTH && [[WPOverlayManager sharedManager] stealthEnabled])[pills addArrangedSubview:WPThemePill(@"隐身",UIColor.darkGrayColor)];
    UIView *spacer=[UIView new];[spacer setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];[pills addArrangedSubview:spacer];
    UILabel *detail=WPThemeLabel(connected?@"互动会同步给宝宝":status,12,UIFontWeightRegular,WPThemeSecondaryText());
    UILabel *peer=WPThemeLabel([[WPOverlayManager sharedManager] peerStatusText],12,UIFontWeightMedium,WPThemeSecondaryText());self.peerLabel=peer;
    UIStackView *text=[[UIStackView alloc] initWithArrangedSubviews:@[title,pills,detail,peer]];text.axis=UILayoutConstraintAxisVertical;text.spacing=8;
    UIStackView *row=[[UIStackView alloc] initWithArrangedSubviews:@[tile,text]];row.axis=UILayoutConstraintAxisHorizontal;row.spacing=14;row.alignment=UIStackViewAlignmentCenter;
    row.translatesAutoresizingMaskIntoConstraints=NO;[card addSubview:row];
    UIButton *change=[UIButton buttonWithType:UIButtonTypeSystem];change.translatesAutoresizingMaskIntoConstraints=NO;
    [change setTitle:partner.length?@"更换":@"选择" forState:UIControlStateNormal];change.titleLabel.font=[UIFont systemFontOfSize:15 weight:UIFontWeightMedium];change.tintColor=UIColor.systemBlueColor;
    change.accessibilityLabel=partner.length?@"更换对象":@"选择对象";change.accessibilityIdentifier=@"WPCouplePartnerChange";
    __weak typeof(self) weakSelf=self;[change addAction:[UIAction actionWithHandler:^(__unused UIAction *a){[weakSelf push:[[WPPartnerPickerController alloc] initWithStyle:UITableViewStyleInsetGrouped]];}] forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:change];
    [NSLayoutConstraint activateConstraints:@[[row.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18],[row.trailingAnchor constraintLessThanOrEqualToAnchor:change.leadingAnchor constant:-8],
        [row.topAnchor constraintEqualToAnchor:card.topAnchor constant:18],[row.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-18],
        [change.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],[change.topAnchor constraintEqualToAnchor:card.topAnchor constant:12]]];
    [change setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    card.accessibilityIdentifier=@"WPCoupleStatusCard";
    return card;
}
#endif
- (void)viewDidLayoutSubviews{
    [super viewDidLayoutSubviews];
    // Refresh layout after rotation or a width change.
    if(fabs(self.view.bounds.size.width-self.builtWidth)>1){self.builtWidth=self.view.bounds.size.width;[self reloadCards];}
}
- (void)done{[self.view endEditing:YES];if(self.navigationController.presentingViewController)[self dismissViewControllerAnimated:YES completion:self.onClose];else if(self.onClose)self.onClose();}
- (void)buildCards{
    UIView *header=WPBuildHomeHeaderWithVisibility(![WPPreferences() boolForKey:@"enabled"],^(BOOL hidden){
        [WPPreferences() setBool:!hidden forKey:@"enabled"];
        [NSNotificationCenter.defaultCenter postNotificationName:WPSettingsDidChangeNotification object:nil];
    });
    [self.stack addArrangedSubview:header];
    __weak typeof(self) weakSelf=self;
#if WP_EDITION_COUPLE
    [self.stack addArrangedSubview:[self coupleCard]];
    NSUInteger pending=WPCoupleHistory.sharedHistory.badgeCount;
    NSArray *couple=@[
        @[@"情侣互动",@"对象、预览与提醒规则",@"heart.fill",UIColor.systemPinkColor,^{[weakSelf push:[WPCoupleSettingsController new]];}],
        @[@"互动记录",pending?[NSString stringWithFormat:@"%lu 条待回应",(unsigned long)pending]:@"查看我们之间的互动",@"heart.text.square.fill",UIColor.systemRedColor,^{[[WPOverlayManager sharedManager] openInteractions];}],
        @[@"配对与连接",WP_FEATURE_STEALTH?@"服务地址、令牌与隐身":@"服务地址与本机令牌",@"link",UIColor.systemGreenColor,^{[weakSelf push:[WPConnectionSettingsController new]];}]];
#endif
    NSArray *pet=@[
        @[@"快捷设置",@"点击、长按与摇晃",@"bolt.fill",UIColor.systemOrangeColor,^{[weakSelf push:[WPQuickActionsController new]];}],
        @[@"长按菜单",@"调整菜单项目与顺序",@"hand.tap.fill",UIColor.systemPurpleColor,^{[weakSelf push:[WPMenuSettingsController new]];}],
        @[@"桌宠设置",@"大小、位置与显示",@"slider.horizontal.3",UIColor.systemBlueColor,^{[weakSelf push:[WPPetSettingsController new]];}],
        @[@"外观设置",@"桌宠外观与未读头像",@"paintpalette.fill",UIColor.systemPinkColor,^{[weakSelf push:[WPAppearanceSettingsController new]];}]];
    NSArray *chat=@[
        @[@"便捷聊天",@"会话列表与头像",@"bubble.left.and.bubble.right.fill",UIColor.systemBlueColor,^{[weakSelf push:[WPQuickChatSettingsController new]];}],
        @[@"提醒方式",@"提醒强度与安静时段",@"bell.fill",UIColor.systemOrangeColor,^{[weakSelf push:[WPReminderSettingsController new]];}],
        @[@"聊天弹幕",@"消息弹幕与显示方式",@"text.bubble.fill",UIColor.systemTealColor,^{[weakSelf push:[WPBarrageSettingsController new]];}],
        @[@"聊天参谋",@"模型、聊天场景与连续对话",@"sparkles",UIColor.systemPurpleColor,^{[weakSelf push:[WPChatAdvisorSettingsController new]];}]];
    NSArray *more=@[
        @[@"在线桌宠",@"浏览 Petdex 桌宠库",@"globe",UIColor.systemTealColor,^{[weakSelf push:[WPCatalogController new]];}],
        @[@"本地桌宠",@"选择已下载的桌宠",@"tray.full.fill",UIColor.systemGreenColor,^{WPCatalogController *catalog=[WPCatalogController new];catalog.startsWithDownloadedPets=YES;[weakSelf push:catalog];}],
        @[@"插件介绍",@"了解桌宠功能",@"info.circle.fill",UIColor.systemBlueColor,^{[weakSelf push:[WPPluginIntroductionController new]];}],
        @[@"Telegram",@"加入群聊交流",@"paperplane.fill",UIColor.systemBlueColor,^{WPOpenTelegramGroup(weakSelf);}]];
    NSArray *sections=@[@[@"桌宠与手势",pet],@[@"聊天与提醒",chat],@[@"桌宠库与关于",more]];
#if WP_EDITION_COUPLE
    sections=[@[@[@"双人互动",couple]] arrayByAddingObjectsFromArray:sections];
#endif
    NSUInteger columns=self.view.bounds.size.width>0 && self.view.bounds.size.width<290?3:4;
    for(NSArray *section in sections){
        [self addSectionTitle:section[0]];
        NSArray *entries=section[1];
        for(NSUInteger start=0;start<entries.count;start+=columns){
            UIStackView *line=[UIStackView new];line.axis=UILayoutConstraintAxisHorizontal;line.spacing=4;line.distribution=UIStackViewDistributionFillEqually;
            UIView *wrapper=[UIView new];line.translatesAutoresizingMaskIntoConstraints=NO;[wrapper addSubview:line];
            NSLayoutConstraint *width=[line.widthAnchor constraintEqualToConstant:columns==4?320:240];width.priority=UILayoutPriorityDefaultHigh;
            [NSLayoutConstraint activateConstraints:@[width,[line.widthAnchor constraintLessThanOrEqualToAnchor:wrapper.widthAnchor],
                [line.centerXAnchor constraintEqualToAnchor:wrapper.centerXAnchor],[line.topAnchor constraintEqualToAnchor:wrapper.topAnchor],
                [line.bottomAnchor constraintEqualToAnchor:wrapper.bottomAnchor],[line.heightAnchor constraintEqualToConstant:88]]];
            for(NSUInteger col=0;col<columns;col++){
                NSUInteger index=start+col;
                if(index>=entries.count){UIView *spacer=[UIView new];spacer.userInteractionEnabled=NO;[line addArrangedSubview:spacer];continue;}
                NSArray *entry=entries[index];UIControl *card=WPBuildHomeCompactFeature(entry[0],[UIImage systemImageNamed:entry[2]],entry[3],entry[4]);
                card.accessibilityHint=entry[1];
                if([entry[0] isEqualToString:@"插件介绍"])card.accessibilityIdentifier=@"WPPluginIntroduction";
                if([entry[0] isEqualToString:@"Telegram"])card.accessibilityIdentifier=@"WPHomeTelegramGroup";
                [line addArrangedSubview:card];
            }
            [self.stack addArrangedSubview:wrapper];
        }
    }
}
- (void)push:(UIViewController *)controller{[self.navigationController pushViewController:controller animated:YES];}

@end
