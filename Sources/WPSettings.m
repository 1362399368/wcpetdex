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

/// Closes the plugin panel first so the action happens in WeChat below it.
static void WPPerformAfterClosingPanel(UIViewController *controller,NSString *name,id object){
    UIViewController *root=controller.navigationController.viewControllers.firstObject;
    void (^close)(void)=[root respondsToSelector:@selector(onClose)]?[(WPSettingsController *)root onClose]:nil;
    if(close)close();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,450*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[NSNotificationCenter.defaultCenter postNotificationName:name object:object];});
}
#pragma mark - Secondary pages

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
    [self addNote:@"仅头像：保留未读头像。轻动作：收到消息时播放一次轻动作。完整提醒：保留闪烁、气泡和触感。"];
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
- (void)viewDidLoad{self.title=@"快捷功能";[super viewDidLoad];}
- (UIView *)tapActionRowWithTitle:(NSString *)title doubleTap:(BOOL)doubleTap handler:(void (^)(WPTapAction))handler{
    UIStackView *column=[UIStackView new];column.axis=UILayoutConstraintAxisVertical;column.spacing=8;
    [column addArrangedSubview:WPThemeLabel(title,15,UIFontWeightMedium,WPThemePrimaryText())];
    UISegmentedControl *choice=[[UISegmentedControl alloc] initWithItems:@[@"聊天浮窗",@"设置",@"聊天参谋"]];
    choice.selectedSegmentIndex=WPConfiguredTapAction(doubleTap)-1;
    choice.accessibilityLabel=title;
    choice.accessibilityIdentifier=doubleTap?@"WPTapActionDouble":@"WPTapActionSingle";
    __weak UISegmentedControl *weakChoice=choice;
    [choice addAction:[UIAction actionWithHandler:^(__unused UIAction *action){
        if(weakChoice.selectedSegmentIndex>=0)handler((WPTapAction)(weakChoice.selectedSegmentIndex+1));
    }] forControlEvents:UIControlEventValueChanged];
    [column addArrangedSubview:choice];
    return column;
}
- (void)buildCards{
    __weak typeof(self) weakSelf=self;
    UIStackView *card=[self addCard];
    [card addArrangedSubview:[self rowWithTitle:@"一键已读" detail:[WPActionAdapter supportsMarkAllRead]?@"已接入当前微信版本":@"当前微信版本未适配" actionTitle:@"执行" handler:^{
        WPPerformAfterClosingPanel(weakSelf,@"WeChatPet.PerformAction",@"read");}]];
    [card addArrangedSubview:[self rowWithTitle:@"一键跳转朋友圈" detail:nil actionTitle:@"打开" handler:^{
        WPPerformAfterClosingPanel(weakSelf,@"WeChatPet.PerformAction",@"moments");}]];
    [self addNote:@"也可以长按桌宠，滑到对应图标后松手。"];
    void (^changed)(void)=^{[NSNotificationCenter.defaultCenter postNotificationName:WPSettingsDidChangeNotification object:nil];};
    [self addSectionTitle:@"桌宠点击动作"];
    UIStackView *tapActions=[self addCard];
    for(NSNumber *gesture in @[@NO,@YES]){
        BOOL doubleTap=gesture.boolValue;
        [tapActions addArrangedSubview:[self tapActionRowWithTitle:doubleTap?@"双击桌宠":@"单击桌宠" doubleTap:doubleTap handler:^(WPTapAction action){
            if(action==WPTapActionQuickChat && !WPQuickChatEnabled())
                [WPPreferences() setBool:YES forKey:@"quickChatEnabled"];
            if(action==WPTapActionChatAdvisor && !WPChatAdvisor.isReady)
                [weakSelf alert:@"已设为聊天参谋。还需要在设置首页的「聊天参谋」里填写 API Key 并启用。"];
            WPSetConfiguredTapAction(doubleTap,action);
            changed();[weakSelf reloadCards];
        }]];
    }
    [tapActions addArrangedSubview:[self switchRowWithTitle:@"贴边时直接执行点击动作" detail:@"单击和双击直接执行上方设置；关闭时先展开桌宠" on:WPQuickChatOptionBool(@"edgeTapActions") handler:^(BOOL on){WPQuickChatSetOption(@"edgeTapActions",@(on));}]];
    [self addNote:@"单击和双击可分别选择动作；选择聊天浮窗时会自动开启便捷聊天；聊天参谋需要先打开一个聊天。"];
    [self addSectionTitle:@"便捷聊天"];
    BOOL enabled=WPQuickChatEnabled();
    UIStackView *quick=[self addCard];
    [quick addArrangedSubview:[self switchRowWithTitle:@"便捷聊天浮窗" detail:@"按设定的点击动作展开最近聊天，点头像进入聊天；未读头像提醒可在外观设置中单独开启" on:enabled handler:^(BOOL on){
        if(!on)WPResetQuickChatTapActions();
        [WPPreferences() setBool:on forKey:@"quickChatEnabled"];changed();[weakSelf reloadCards];}]];
    UIView *flash=[self switchRowWithTitle:@"新消息闪烁提醒" detail:@"新消息到达时桌宠探出、闪烁并显示发送方头像；免打扰的聊天不提醒" on:WPQuickChatFlashEnabled() handler:^(BOOL on){
        [WPPreferences() setBool:on forKey:@"quickChatFlash"];changed();}];
    flash.userInteractionEnabled=enabled;flash.alpha=enabled?1:.4;
    [quick addArrangedSubview:flash];
    [quick addArrangedSubview:[self rowWithTitle:@"快捷聊天设置" detail:@"侧栏外观、头像打开方式、会话过滤与贴边点击" actionTitle:@"设置" handler:^{[weakSelf.navigationController pushViewController:[WPQuickChatSettingsController new] animated:YES];}]];
    [self addNote:@"开关即时生效，不用重启微信。关闭便捷聊天时，指向它的点击动作会恢复为设置。"];
    UIStackView *reminders=[self addCard];
    [reminders addArrangedSubview:[self rowWithTitle:@"提醒方式" detail:@"提醒强度、安静时段与指定联系人" actionTitle:nil handler:^{[weakSelf.navigationController pushViewController:[WPReminderSettingsController new] animated:YES];}]];
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
- (UIView *)gestureActionRow:(BOOL)longPress {
    NSArray<NSString *> *values=longPress?@[@"menu",@"quickChat",@"settings",@"moments",@"advisor",@"none"]:@[@"quickChat",@"settings",@"moments",@"advisor",@"none"];
    NSDictionary *names=@{@"menu":@"快捷菜单",@"quickChat":@"快捷聊天",@"settings":@"桌宠设置",@"moments":@"朋友圈",@"advisor":@"聊天参谋",@"none":@"不执行"};
    NSString *title=longPress?@"长按桌宠":@"摇晃桌宠";
    NSString *selected=WPConfiguredGestureAction(longPress);
    __weak typeof(self) weakSelf=self;
    return [self rowWithTitle:title detail:names[selected] actionTitle:@"选择" handler:^{
        UIAlertController *dialog=[UIAlertController alertControllerWithTitle:title message:@"选择手势触发的功能" preferredStyle:UIAlertControllerStyleAlert];
        for(NSString *value in values){
            [dialog addAction:[UIAlertAction actionWithTitle:names[value] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){
                WPSetConfiguredGestureAction(longPress,value);
                if([value isEqualToString:@"quickChat"])[WPPreferences() setBool:YES forKey:@"quickChatEnabled"];
                [NSNotificationCenter.defaultCenter postNotificationName:WPSettingsDidChangeNotification object:nil];
                [weakSelf reloadCards];
            }]];
        }
        [dialog addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [weakSelf presentViewController:dialog animated:YES completion:nil];
    }];
}
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
    [look addArrangedSubview:[self sliderRowWithTitle:@"菜单圆弧" value:[WPPreferences() doubleForKey:@"menuScale"] minimum:.6 maximum:4 format:^NSString *(float v){return [NSString stringWithFormat:@"%.0f 点",v*80];} handler:^(float v){
        [WPPreferences() setDouble:v forKey:@"menuScale"];changed();[[WPOverlayManager sharedManager] previewMenuRadius];}]];
    [self addNote:@"圆弧半径 48–320 点，拖动即时预览；屏幕放不下时会自动收小。"];
    [self addSectionTitle:@"手势"];
    UIStackView *gesture=[self addCard];
    UIView *longPress=[self gestureActionRow:YES]; longPress.accessibilityIdentifier=@"WPLongPressAction"; [gesture addArrangedSubview:longPress];
    UIView *shakeAction=[self gestureActionRow:NO]; shakeAction.accessibilityIdentifier=@"WPShakeAction"; [gesture addArrangedSubview:shakeAction];
    NSInteger level=WPShakeSensitivityFromPreferenceValue([WPPreferences() objectForKey:@"shakeSensitivity"]);
    [gesture addArrangedSubview:[self segmentedRowWithTitle:@"摇晃灵敏度" items:@[@"低",@"中",@"高"] selected:level handler:^(NSInteger index){[WPPreferences() setInteger:index forKey:@"shakeSensitivity"];}]];
    [gesture addArrangedSubview:WPThemeLabel(@"按住桌宠快速左右来回拖动执行所选动作；普通拖动只移动位置。灵敏度越高，摇晃幅度和次数要求越低。",12,UIFontWeightRegular,WPThemeSecondaryText())];
    UIView *lock=[self switchRowWithTitle:@"锁定桌宠位置" detail:@"防止误拖动；点击、长按和摇晃动作继续可用。键盘弹出时临时避让，收起后恢复原位。" on:WPPositionLocked() handler:^(BOOL on){[WPPreferences() setBool:on forKey:@"positionLocked"];changed();}];
    ((UIStackView *)lock).arrangedSubviews.lastObject.accessibilityIdentifier=@"WPPositionLockSwitch";[gesture addArrangedSubview:lock];
    [gesture addArrangedSubview:[self switchRowWithTitle:@"贴边自动收起" detail:@"靠边闲置约 3 秒后探头" on:[WPPreferences() boolForKey:@"autoPeek"] handler:^(BOOL on){[WPPreferences() setBool:on forKey:@"autoPeek"];changed();}]];
    [gesture addArrangedSubview:[self switchRowWithTitle:@"有未读时也允许收起" detail:@"贴边收起后仍显示未读头像，可直接点击进入聊天" on:WPAllowUnreadPeek() handler:^(BOOL on){[WPPreferences() setBool:on forKey:@"allowUnreadPeek"];changed();}]];
    [self addNote:@"横屏与竖屏分别记住最后一次拖动的位置；键盘避让不会覆盖保存的位置。锁定后仍可拖动手指摇晃桌宠，人物本身保持原位。"];

    UIStackView *reset=[self addCard];
    [reset addArrangedSubview:[self rowWithTitle:@"恢复默认桌宠与位置" detail:@"大小、透明度、圆弧和位置一起恢复" actionTitle:@"恢复" handler:^{
        WPResetSelectedPet();
        WPResetPositionAnchors();
        for(NSString *key in @[@"positionLocked",@"petSize",@"petOpacity",@"menuScale",@"shakeSensitivity"])[WPPreferences() removeObjectForKey:key];
        [NSNotificationCenter.defaultCenter postNotificationName:WPSelectedPetDidChangeNotification object:nil];changed();[weakSelf reloadCards];}]];
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
    NSString *currentPet=(!selected.length || [selected isEqualToString:WPDefaultPetDirectory()])?@"默认 噜噜":selected.lastPathComponent;
    UIStackView *current=[self addCard];
    [current addArrangedSubview:[self rowWithTitle:@"当前桌宠" detail:currentPet actionTitle:nil handler:^{WPCatalogController *library=[WPCatalogController new];library.startsWithDownloadedPets=YES;[weakSelf.navigationController pushViewController:library animated:YES];}]];
    [self addSectionTitle:@"未读聊天头像"];
    BOOL unreadEnabled=WPUnreadAvatarEnabled();
    UIStackView *unread=[self addCard];
    UIView *toggleRow=[self switchRowWithTitle:@"显示最新未读头像" detail:@"在桌宠正上方显示最新未读聊天的头像，点击进入聊天；排除折叠群聊和免打扰消息。可在桌宠设置中允许有未读时贴边收起。" on:unreadEnabled handler:^(BOOL on){
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
    UIButton *resetIndicators=[self buttonWithTitle:@"恢复头像默认位置" primary:NO handler:^{
        for(NSString *key in @[@"unreadAvatarOffsetX",@"unreadAvatarOffsetY"])[WPPreferences() removeObjectForKey:key];
        [NSNotificationCenter.defaultCenter postNotificationName:WPSettingsDidChangeNotification object:nil];
        [weakSelf reloadCards];
    }];
    resetIndicators.accessibilityIdentifier=@"WPResetIndicatorPositions"; [unread addArrangedSubview:resetIndicators];
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

@interface WPFeatureCard : UIControl
@end
@implementation WPFeatureCard
+ (instancetype)cardWithTitle:(NSString *)title subtitle:(NSString *)subtitle image:(UIImage *)image tint:(UIColor *)tint{
    WPFeatureCard *card=[WPFeatureCard new];card.backgroundColor=WPThemeCard();card.layer.cornerRadius=WPThemeCardRadius;card.layer.cornerCurve=kCACornerCurveContinuous;
    UIView *tile=WPThemeIconTile(image,tint,46);tile.userInteractionEnabled=NO;
    UILabel *titleLabel=WPThemeLabel(title,16,UIFontWeightSemibold,WPThemePrimaryText());
    UILabel *subtitleLabel=WPThemeLabel(subtitle,12,UIFontWeightRegular,WPThemeSecondaryText());
    UIStackView *text=[[UIStackView alloc] initWithArrangedSubviews:@[titleLabel,subtitleLabel]];text.axis=UILayoutConstraintAxisVertical;text.spacing=3;
    UIStackView *row=[[UIStackView alloc] initWithArrangedSubviews:@[tile,text]];row.axis=UILayoutConstraintAxisHorizontal;row.spacing=12;row.alignment=UIStackViewAlignmentCenter;
    row.userInteractionEnabled=NO;row.translatesAutoresizingMaskIntoConstraints=NO;[card addSubview:row];
    [NSLayoutConstraint activateConstraints:@[[row.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],[row.trailingAnchor constraintLessThanOrEqualToAnchor:card.trailingAnchor constant:-12],
        [row.topAnchor constraintGreaterThanOrEqualToAnchor:card.topAnchor constant:14],[row.bottomAnchor constraintLessThanOrEqualToAnchor:card.bottomAnchor constant:-14],
        [row.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],[card.heightAnchor constraintGreaterThanOrEqualToConstant:84]]];
    card.isAccessibilityElement=YES;card.accessibilityLabel=title;card.accessibilityHint=subtitle;card.accessibilityTraits=UIAccessibilityTraitButton;
    return card;
}
- (void)setHighlighted:(BOOL)highlighted{[super setHighlighted:highlighted];self.backgroundColor=highlighted?WPThemeElevated():WPThemeCard();}
@end

@interface WPSettingsController ()
@property(nonatomic) CGFloat builtWidth;
@end
@implementation WPSettingsController
- (void)viewDidLoad{
    self.title=@"zhour-single";[super viewDidLoad];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"完成" style:UIBarButtonItemStyleDone target:self action:@selector(done)];
    for(NSString *name in @[WPSettingsDidChangeNotification])
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reloadCards) name:name object:nil];
}
- (void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];[self reloadCards];}
- (void)viewDidLayoutSubviews{
    [super viewDidLayoutSubviews];
    // Two columns normally, one column on very narrow widths.
    if(fabs(self.view.bounds.size.width-self.builtWidth)>1){self.builtWidth=self.view.bounds.size.width;[self reloadCards];}
}
- (void)done{[self.view endEditing:YES];if(self.navigationController.presentingViewController)[self dismissViewControllerAnimated:YES completion:self.onClose];else if(self.onClose)self.onClose();}
- (void)buildCards{
    [self.stack addArrangedSubview:[self infoCard]];
    UIStackView *visibility=[self addCard];
    UIView *hideRow=[self switchRowWithTitle:@"隐藏桌宠" detail:@"隐藏桌宠和浮动提示；可从微信设置再次进入这里，关闭开关恢复显示" on:![WPPreferences() boolForKey:@"enabled"] handler:^(BOOL hidden){
        [WPPreferences() setBool:!hidden forKey:@"enabled"];
        [NSNotificationCenter.defaultCenter postNotificationName:WPSettingsDidChangeNotification object:nil];
    }];
    for(UIView *view in hideRow.subviews)if([view isKindOfClass:UISwitch.class])view.accessibilityIdentifier=@"WPHidePetSwitch";
    [visibility addArrangedSubview:hideRow];
    __weak typeof(self) weakSelf=self;
    NSArray *features=@[
        @[@"快捷功能",@"一键已读 · 朋友圈",[UIImage systemImageNamed:@"bolt.fill"],UIColor.systemYellowColor,^{[weakSelf push:[WPQuickActionsController new]];}],
        @[@"桌宠设置",@"外观、切换桌宠与手势",[UIImage systemImageNamed:@"slider.horizontal.3"],WPThemePrimaryText(),^{[weakSelf push:[WPPetSettingsController new]];}],
        @[@"聊天弹幕",@"半透明消息 · 头像停靠",[UIImage systemImageNamed:@"text.bubble.fill"],UIColor.systemTealColor,^{[weakSelf push:[WPBarrageSettingsController new]];}],
        @[@"聊天参谋",WPChatAdvisor.isReady?@"意图分析 · 建议回复":@"接入硅基流动后使用",[UIImage systemImageNamed:@"sparkles"],UIColor.systemPurpleColor,^{[weakSelf push:[WPChatAdvisorSettingsController new]];}]];
    NSUInteger columns=self.view.bounds.size.width>0 && self.view.bounds.size.width<340?1:2;
    for(NSUInteger start=0;start<features.count;start+=columns){
        UIStackView *line=[UIStackView new];line.axis=UILayoutConstraintAxisHorizontal;line.spacing=12;line.distribution=UIStackViewDistributionFillEqually;line.alignment=UIStackViewAlignmentFill;
        for(NSUInteger i=start;i<MIN(features.count,start+columns);i++){
            NSArray *item=features[i];void (^handler)(void)=item[4];
            WPFeatureCard *card=[WPFeatureCard cardWithTitle:item[0] subtitle:item[1] image:item[2] tint:item[3]];
            [card addAction:[UIAction actionWithHandler:^(__unused UIAction *a){handler();}] forControlEvents:UIControlEventTouchUpInside];
            [line addArrangedSubview:card];
        }
        [self.stack addArrangedSubview:line];[self.stack setCustomSpacing:12 afterView:line];
    }
    [self addSectionTitle:@"版本与诊断"];
    UIStackView *about=[self addCard];
    NSString *wechat=[NSString stringWithFormat:@"%@ (%@)",[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"未知",[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"未知"];
    [about addArrangedSubview:[self rowWithTitle:@"微信版本" detail:wechat actionTitle:nil handler:nil]];
    UIView *pause=[self switchRowWithTitle:@"暂停插件浮层" detail:@"暂停桌宠、弹幕和快捷聊天，方便排查页面操作卡住的问题" on:WPOverlayManager.sharedManager.recoveryPaused handler:^(BOOL paused){[WPOverlayManager.sharedManager setRecoveryPaused:paused];[weakSelf reloadCards];}];
    pause.accessibilityIdentifier=@"WPRecoveryPauseControl";[about addArrangedSubview:pause];
    UIView *retry=[self rowWithTitle:WPOverlayManager.sharedManager.recoveryPaused?@"恢复插件":@"重新恢复插件" detail:@"从微信设置也可进入这里恢复，无需点击桌宠" actionTitle:@"恢复" handler:^{if(WPOverlayManager.sharedManager.recoveryPaused)[WPOverlayManager.sharedManager setRecoveryPaused:NO];else [WPOverlayManager.sharedManager retryRecovery];[weakSelf reloadCards];}];
    retry.accessibilityIdentifier=@"WPRecoveryRetryControl";[about addArrangedSubview:retry];
    [about addArrangedSubview:[self rowWithTitle:@"导出适配诊断" detail:@"只含接口名和类型，不含聊天与联系人" actionTitle:@"导出" handler:^{[weakSelf exportDiagnostics];}]];
    UILabel *version=WPThemeLabel([NSString stringWithFormat:@"版本 %@ · 构建 %d · %@",WPPluginVersion(),WP_BUILD_VERSION,WPEditionName()],12,UIFontWeightRegular,WPThemeSecondaryText());version.textAlignment=NSTextAlignmentCenter;
    [self.stack addArrangedSubview:version];
}
- (UIView *)infoCard{
    UIView *card=[UIView new]; card.backgroundColor=WPThemeCard(); card.layer.cornerRadius=WPThemeCardRadius; card.layer.cornerCurve=kCACornerCurveContinuous;
    UIView *tile=WPThemeIconTile([UIImage systemImageNamed:@"pawprint.fill"],UIColor.systemOrangeColor,58);
    UILabel *title=WPThemeLabel(@"zhour-single",17,UIFontWeightSemibold,WPThemePrimaryText());
    UILabel *detail=WPThemeLabel(@"噜噜陪你轻松聊天",12,UIFontWeightRegular,WPThemeSecondaryText());
    UIStackView *text=[[UIStackView alloc] initWithArrangedSubviews:@[title,detail]]; text.axis=UILayoutConstraintAxisVertical; text.spacing=7;
    UIStackView *row=[[UIStackView alloc] initWithArrangedSubviews:@[tile,text]]; row.axis=UILayoutConstraintAxisHorizontal; row.spacing=14; row.alignment=UIStackViewAlignmentCenter;
    row.translatesAutoresizingMaskIntoConstraints=NO; [card addSubview:row];
    [NSLayoutConstraint activateConstraints:@[[row.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18],[row.trailingAnchor constraintLessThanOrEqualToAnchor:card.trailingAnchor constant:-18],[row.topAnchor constraintEqualToAnchor:card.topAnchor constant:18],[row.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-18]]];
    return card;
}
- (void)push:(UIViewController *)controller{[self.navigationController pushViewController:controller animated:YES];}
- (void)exportDiagnostics {
    NSMutableDictionary *report=[WPRuntimeDiagnostics() mutableCopy];
    report[@"recovery"]=[WPOverlayManager.sharedManager recoveryDiagnostics];
    report[@"pluginBuild"]=@(WP_BUILD_VERSION);
    report[@"chatAdvisor"]=[WPChatAdvisor diagnostics];
    report[@"resourceDirectoryFound"]=@([NSFileManager.defaultManager fileExistsAtPath:[WPDefaultPetDirectory() stringByAppendingPathComponent:@"pet.json"]]);
    NSURL *url=[NSURL fileURLWithPath:[WPDataDirectory() stringByAppendingPathComponent:@"diagnostics.json"]];[[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil] writeToURL:url atomically:YES];
    UIActivityViewController *share=[[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];share.popoverPresentationController.sourceView=self.view;[self presentViewController:share animated:YES completion:nil];
}
@end
