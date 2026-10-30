#import "WPBarrageSettingsController.h"
#import "WPBarragePreferences.h"
#import "WPMessageBarrageSource.h"
#import "WPPartnerContact.h"
#import "WPQuickChat.h"

@interface WPBarrageReminderPicker : UITableViewController
@property(nonatomic,copy) NSArray<WPQuickChatSession *> *rows;
@end
@implementation WPBarrageReminderPicker
- (void)viewDidLoad{[super viewDidLoad];self.title=@"选择最近会话";self.rows=[WPQuickChatMonitor.sharedMonitor currentSessions]?:@[];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh:) name:WPQuickChatDidChangeNotification object:nil];}
- (void)refresh:(NSNotification *)note{self.rows=[WPQuickChatMonitor.sharedMonitor currentSessions]?:@[];[self.tableView reloadData];}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{return MAX(1,self.rows.count);}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path{
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    if(!self.rows.count){cell.textLabel.text=@"正在读取最近会话";cell.detailTextLabel.text=@"也可返回选择「添加微信好友」";cell.selectionStyle=UITableViewCellSelectionStyleNone;return cell;}
    WPQuickChatSession *row=self.rows[path.row];NSString *name=[WPPartnerContact displayNameForUsername:row.username];cell.textLabel.text=name.length?name:@"微信会话";
    cell.detailTextLabel.text=[row.username.lowercaseString hasSuffix:@"chatroom"]?@"群聊":@"联系人";
    cell.accessoryType=[WPBarrageContactUsernames() containsObject:row.username]?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone;return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path{
    [tableView deselectRowAtIndexPath:path animated:YES];if(path.row>=(NSInteger)self.rows.count)return;
    NSMutableOrderedSet *names=[NSMutableOrderedSet orderedSetWithArray:WPBarrageContactUsernames()];NSString *name=self.rows[path.row].username;
    if([names containsObject:name])[names removeObject:name];else if(names.count<100)[names addObject:name];
    WPBarrageSetReminderValue(@"barrageContactUsernames",names.array);[tableView reloadRowsAtIndexPaths:@[path] withRowAnimation:UITableViewRowAnimationNone];
}
- (void)dealloc{[NSNotificationCenter.defaultCenter removeObserver:self];}
@end

static void WPBarrageIdentifyControl(UIView *row, Class controlClass, NSString *identifier) {
    for (UIView *view in row.subviews) {
        if ([view isKindOfClass:controlClass]) {
            view.accessibilityIdentifier = identifier;
            // Commit a drag once. Rebuilding the covered settings home and
            // reconfiguring the overlay for every slider tick wastes work.
            if ([view isKindOfClass:UISlider.class]) ((UISlider *)view).continuous = NO;
            return;
        }
    }
    row.accessibilityIdentifier = identifier;
}

@implementation WPBarrageSettingsController
- (void)viewDidLoad {
    self.title = @"聊天弹幕";
    [super viewDidLoad];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadCards];
}
- (void)buildCards {
    __weak typeof(self) weakSelf=self;
    UIStackView *main = [self addCard];
    UIView *enabled = [self switchRowWithTitle:@"开启聊天弹幕"
        detail:@"微信前台收到新消息时，从右向左显示头像和内容；点弹幕进入对应聊天"
        on:WPBarrageEnabled() handler:^(BOOL on) { WPBarrageSetEnabled(on); }];
    WPBarrageIdentifyControl(enabled, UISwitch.class, @"WPBarrageEnabledSwitch");
    [main addArrangedSubview:enabled];
    [main addArrangedSubview:[self rowWithTitle:WPBarrageIsPaused()?@"弹幕已暂停":@"暂停弹幕 10 分钟"
        detail:WPBarrageIsPaused()?@"点击恢复即可继续接收新消息":@"到时自动恢复，暂停期间不积压消息"
        actionTitle:WPBarrageIsPaused()?@"恢复":@"暂停" handler:^{if(WPBarrageIsPaused())WPBarrageResume();else WPBarragePauseForInterval(600);[weakSelf reloadCards];}]];
    [main addArrangedSubview:[self rowWithTitle:@"本机预览弹幕" detail:@"检查弹幕画面和移动效果，不发送聊天消息" actionTitle:@"预览" handler:^{
        [NSNotificationCenter.defaultCenter postNotificationName:WPBarragePreviewNotification object:nil];
        [weakSelf alert:@"预览已触发。请查看当前页面上的弹幕；若弹幕关闭或暂停，请先开启并恢复。"];
    }]];
    [self addNote:@"弹幕可单独开启，无需打开便捷聊天或未读头像提醒。隐藏桌宠时同时隐藏弹幕；离开微信后清空待播消息，返回时不补播。"];

    [self addSectionTitle:@"显示方式"];
    UIStackView *appearance = [self addCard];
    UIView *details = [self switchRowWithTitle:@"显示消息内容"
        detail:@"关闭后立即隐藏当前和待播消息正文；昵称可在下方单独控制"
        on:WPBarrageShowsDetails() handler:^(BOOL on) { WPBarrageSetShowsDetails(on); }];
    WPBarrageIdentifyControl(details, UISwitch.class, @"WPBarrageDetailsSwitch");
    [appearance addArrangedSubview:details];
    UIView *names=[self switchRowWithTitle:@"显示对话人名称" detail:@"在头像旁显示昵称或备注；群聊显示发送成员名称" on:WPBarrageShowsName() handler:^(BOOL on){WPBarrageSetShowsName(on);[weakSelf reloadCards];}];
    WPBarrageIdentifyControl(names,UISwitch.class,@"WPBarrageNameSwitch");[appearance addArrangedSubview:names];
    if(WPBarrageShowsName()){
        UIView *nameStyle=[self segmentedRowWithTitle:@"名称来源" items:@[@"微信昵称",@"备注优先"] selected:WPBarrageNameUsesRemark()?1:0 handler:^(NSInteger index){WPBarrageSetNameUsesRemark(index==1);}];
        WPBarrageIdentifyControl(nameStyle,UISegmentedControl.class,@"WPBarrageNameSource");[appearance addArrangedSubview:nameStyle];
    }

    UIView *range = [self segmentedRowWithTitle:@"弹幕范围" items:@[@"半屏", @"全屏"]
        selected:WPBarrageFullScreen() ? 1 : 0 handler:^(NSInteger index) {
            if (index == 0 || index == 1) WPBarrageSetFullScreen(index == 1);
        }];
    WPBarrageIdentifyControl(range, UISegmentedControl.class, @"WPBarrageRangeControl");
    [appearance addArrangedSubview:range];

    UIView *height = [self sliderRowWithTitle:@"弹幕区域高度" value:WPBarrageRegionHeight() minimum:.2 maximum:1
        format:^NSString *(float value) { return [NSString stringWithFormat:@"范围的 %.0f%%", value*100]; }
        handler:^(float value) { WPBarrageSetRegionHeight(value); }];
    WPBarrageIdentifyControl(height, UISlider.class, @"WPBarrageRegionHeightSlider");
    [appearance addArrangedSubview:height];
    UIView *position = [self sliderRowWithTitle:@"弹幕纵向位置" value:WPBarrageVerticalPosition() minimum:0 maximum:1
        format:^NSString *(float value) { return value<.01?@"顶部":(value>.99?@"底部":[NSString stringWithFormat:@"%.0f%%",value*100]); }
        handler:^(float value) { WPBarrageSetVerticalPosition(value); }];
    WPBarrageIdentifyControl(position, UISlider.class, @"WPBarrageVerticalPositionSlider");
    [appearance addArrangedSubview:position];
    [self addNote:@"区域高度在半屏／全屏的基础上调节；纵向位置将整个区域上下移动，始终保留完整轨道。改变高度或切换微信页面时，正在播放的弹幕继续前进；区域缩小时，已有轨道自然退出后再使用新范围，避免挤叠。"];

    UIView *speed = [self sliderRowWithTitle:@"弹幕速度" value:WPBarrageSpeed() minimum:.5 maximum:2
        format:^NSString *(float value) { return [NSString stringWithFormat:@"%.1f 倍", value]; }
        handler:^(float value) { WPBarrageSetSpeed(value); }];
    WPBarrageIdentifyControl(speed, UISlider.class, @"WPBarrageSpeedSlider");
    [appearance addArrangedSubview:speed];

    UIView *opacity = [self sliderRowWithTitle:@"半透明底框" value:WPBarrageBackgroundOpacity() minimum:.35 maximum:.85
        format:^NSString *(float value) { return [NSString stringWithFormat:@"%.0f%%", value * 100]; }
        handler:^(float value) { WPBarrageSetBackgroundOpacity(value); }];
    WPBarrageIdentifyControl(opacity, UISlider.class, @"WPBarrageOpacitySlider");
    [appearance addArrangedSubview:opacity];
    [self addNote:@"速度调节只影响之后出现的弹幕，正在播放的弹幕保持平滑。消息使用半透明圆角底框；长文字会缩短显示，点弹幕可在聊天中查看全文。"];

    [self addSectionTitle:@"与桌宠联动"];
    UIStackView *pet = [self addCard];
    UIView *reaction = [self switchRowWithTitle:@"桌宠轻回应"
        detail:@"收到消息和头像弹出时轻轻回应；连续消息会合并动作，避免反复打断"
        on:WPBarrageReactionsEnabled() handler:^(BOOL on) { WPBarrageSetReactionsEnabled(on); }];
    WPBarrageIdentifyControl(reaction, UISwitch.class, @"WPBarrageReactionSwitch");
    [pet addArrangedSubview:reaction];
    UIView *ending=[self switchRowWithTitle:@"弹幕结束后动画" detail:@"一批消息播放结束只执行一次，头像始终对应最新有效未读" on:WPBarrageCompletionAnimation()!=3 handler:^(BOOL on){WPBarrageSetCompletionAnimation(on?0:3);[weakSelf reloadCards];}];
    WPBarrageIdentifyControl(ending,UISwitch.class,@"WPBarrageCompletionSwitch");[pet addArrangedSubview:ending];
    if(WPBarrageCompletionAnimation()!=3){
        UIView *animation=[self segmentedRowWithTitle:@"结束动画" items:@[@"头顶弹跳",@"头像飞入",@"轻柔淡入"] selected:WPBarrageCompletionAnimation() handler:^(NSInteger index){WPBarrageSetCompletionAnimation(index);}];
        WPBarrageIdentifyControl(animation,UISegmentedControl.class,@"WPBarrageCompletionStyle");[pet addArrangedSubview:animation];
    }
    [pet addArrangedSubview:[self rowWithTitle:@"清除停靠头像"
        detail:@"移除桌宠上方的未读头像，不会把消息标为已读"
        actionTitle:@"清除" handler:^{
            [NSNotificationCenter.defaultCenter postNotificationName:WPBarrageClearDockNotification object:nil];
        }]];
    [self addNote:@"一波消息结束只播放一次所选动画，与最新未读头像共用一个位置。关闭结束动画仍保留未读头像。点头像进入对应聊天后即清除；正在查看的聊天不播放该联系人的弹幕或头像。节能或减少动态效果时自动使用简化效果。"];

    [self addSectionTitle:@"弹幕提醒规则"];
    UIStackView *rules=[self addCard];
    [rules addArrangedSubview:[self switchRowWithTitle:@"显示私聊" detail:nil on:WPBarrageAllowsPrivateChats() handler:^(BOOL on){WPBarrageSetReminderValue(@"barrageAllowPrivate",@(on));}]];
    [rules addArrangedSubview:[self switchRowWithTitle:@"显示群聊" detail:@"显示发言成员头像，点击进入原群聊" on:WPBarrageAllowsGroupChats() handler:^(BOOL on){WPBarrageSetReminderValue(@"barrageAllowGroup",@(on));}]];
    [rules addArrangedSubview:[self switchRowWithTitle:@"启用安静时段" detail:@"到达开始时间立即清除弹幕文字，结束后仅显示新消息" on:WPBarrageQuietTimeEnabled() handler:^(BOOL on){WPBarrageSetReminderValue(@"barrageQuietEnabled",@(on));[weakSelf reloadCards];}]];
    if(WPBarrageQuietTimeEnabled()){[rules addArrangedSubview:[self quietTimeRow:YES]];[rules addArrangedSubview:[self quietTimeRow:NO]];}
    [rules addArrangedSubview:[self switchRowWithTitle:@"仅显示指定会话" detail:@"可选择好友或最近群聊；列表为空时不显示弹幕" on:WPBarrageContactsOnly() handler:^(BOOL on){WPBarrageSetReminderValue(@"barrageContactsOnly",@(on));[weakSelf reloadCards];}]];
    if(WPBarrageContactsOnly()){
        for(NSString *username in WPBarrageContactUsernames()){
            NSString *name=[WPPartnerContact displayNameForUsername:username];
            [rules addArrangedSubview:[self rowWithTitle:name.length?name:@"已选择的会话" detail:nil actionTitle:@"移除" handler:^{NSMutableArray *names=[WPBarrageContactUsernames() mutableCopy];[names removeObject:username];WPBarrageSetReminderValue(@"barrageContactUsernames",names);[weakSelf reloadCards];}]];
        }
        [rules addArrangedSubview:[self rowWithTitle:@"添加最近会话或群聊" detail:nil actionTitle:@"选择" handler:^{[weakSelf.navigationController pushViewController:[[WPBarrageReminderPicker alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];}]];
        [rules addArrangedSubview:[self rowWithTitle:@"添加微信好友" detail:nil actionTitle:@"选择" handler:^{
            WPPartnerPickerController *picker=[[WPPartnerPickerController alloc] initWithStyle:UITableViewStyleInsetGrouped];picker.pickerTitle=@"选择弹幕提醒好友";
            picker.selectionHandler=^(NSString *username,__unused NSString *name){NSMutableOrderedSet *names=[NSMutableOrderedSet orderedSetWithArray:WPBarrageContactUsernames()];if(names.count<100)[names addObject:username];WPBarrageSetReminderValue(@"barrageContactUsernames",names.array);[weakSelf reloadCards];};[weakSelf.navigationController pushViewController:picker animated:YES];
        }]];
    }
    [self addNote:@"这些规则独立作用于聊天弹幕。升级时首次沿用已有安静时段和联系人选择，之后可在此单独调整；免打扰、隐藏会话仍会被过滤。"];
    [self addSectionTitle:@"流畅与状态"];
    UIStackView *limits = [self addCard];
    [limits addArrangedSubview:[self switchRowWithTitle:@"自动节省资源" detail:WPBarrageResourceSavingActive()?@"当前已生效：减少同屏弹幕、等待队列和自动回应":@"低电量模式或手机明显发热时自动减少弹幕与自动回应，保持原动画画质"
        on:WPBarrageAdaptiveSavingEnabled() handler:^(BOOL on){WPBarrageSetAdaptiveSavingEnabled(on);[weakSelf reloadCards];}]];
    [limits addArrangedSubview:[self rowWithTitle:@"流畅与节省内存"
        detail:@"复用小头像与控件；等待超过 12 秒的内容不再补播，切后台清空正文与下载"
        actionTitle:nil handler:nil]];
    [limits addArrangedSubview:[self rowWithTitle:@"弹幕工作状态" detail:[self sourceStatus] actionTitle:@"刷新" handler:^{[weakSelf reloadCards];}]];
}
- (UIView *)quietTimeRow:(BOOL)start{
    UIStackView *row=[UIStackView new];row.axis=UILayoutConstraintAxisHorizontal;row.alignment=UIStackViewAlignmentCenter;row.spacing=10;
    UILabel *label=WPThemeLabel(start?@"开始时间":@"结束时间",15,UIFontWeightMedium,WPThemePrimaryText());[label setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];[row addArrangedSubview:label];
    UIDatePicker *picker=[UIDatePicker new];picker.datePickerMode=UIDatePickerModeTime;picker.preferredDatePickerStyle=UIDatePickerStyleCompact;
    NSInteger minute=WPBarrageQuietMinute(start);picker.date=[NSCalendar.currentCalendar dateBySettingHour:minute/60 minute:minute%60 second:0 ofDate:NSDate.date options:0];
    __weak UIDatePicker *weakPicker=picker;
    [picker addAction:[UIAction actionWithHandler:^(__unused UIAction *action){NSDateComponents *parts=[NSCalendar.currentCalendar components:NSCalendarUnitHour|NSCalendarUnitMinute fromDate:weakPicker.date];WPBarrageSetReminderValue(start?@"barrageQuietStart":@"barrageQuietEnd",@(parts.hour*60+parts.minute));}] forControlEvents:UIControlEventValueChanged];[row addArrangedSubview:picker];return row;
}
- (NSString *)sourceStatus{
    if(!WPBarrageEnabled())return @"尚未开启";if(WPBarrageIsPaused())return @"已暂停，可点击上方恢复";
    if(WPBarrageQuietTimeAtDate(NSDate.date))return @"当前处于安静时段";
    NSDictionary *state=[WPMessageBarrageSource.sharedSource diagnostics];
    if([state[@"accepted"] unsignedIntegerValue])return [NSString stringWithFormat:@"已收到 %lu 条有效消息；内容仅临时显示",(unsigned long)[state[@"accepted"] unsignedIntegerValue]];
    if([state[@"muteUnknown"] unsignedIntegerValue])return @"已检测消息，但当前微信的免打扰接口待适配；可导出适配诊断";
    if([state[@"nativeCallbacks"] unsignedIntegerValue])return @"已连接消息入口，等待符合提醒规则的新消息";
    return [state[@"route"] isEqual:@"receive-hook"]?@"消息入口已连接，等待微信前台新消息":@"正在使用兼容接收方式，等待微信前台新消息";
}
@end
