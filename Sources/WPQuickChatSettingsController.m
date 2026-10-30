#import "WPQuickChatSettingsController.h"
#import "WPQuickChatPreferences.h"
#import "WPQuickChat.h"
#import "WPCommon.h"
#import "WPBarragePreferences.h"

void WPAddQuickChatGestureRows(WPCardPageController *page,UIStackView *card) {
    UIView *tap=[page segmentedRowWithTitle:@"单击侧栏头像" items:@[@"小窗",@"全屏",@"菜单"] selected:(NSInteger)WPQuickChatOptionNumber(@"tapMode") handler:^(NSInteger value){WPQuickChatSetOption(@"tapMode",@(value));}];
    tap.accessibilityIdentifier=@"WPQuickChatAvatarTapAction";[card addArrangedSubview:tap];
    UIView *doubleTap=[page segmentedRowWithTitle:@"双击侧栏头像" items:@[@"小窗",@"全屏",@"菜单"] selected:(NSInteger)WPQuickChatOptionNumber(@"doubleTapMode") handler:^(NSInteger value){WPQuickChatSetOption(@"doubleTapMode",@(value));}];
    doubleTap.accessibilityIdentifier=@"WPQuickChatAvatarDoubleTapAction";[card addArrangedSubview:doubleTap];
    UIView *hold=[page segmentedRowWithTitle:@"长按侧栏头像" items:@[@"小窗",@"全屏",@"菜单"] selected:(NSInteger)WPQuickChatOptionNumber(@"holdMode") handler:^(NSInteger value){WPQuickChatSetOption(@"holdMode",@(value));}];
    hold.accessibilityIdentifier=@"WPQuickChatAvatarHoldAction";[card addArrangedSubview:hold];
    if(!WPBarrageEnabled()){
        UIView *arrival=[page switchRowWithTitle:@"点临时提示头像进入会话" detail:@"只影响关闭弹幕时的新消息临时头像" on:WPQuickChatOptionBool(@"arrivalTap") handler:^(BOOL on){WPQuickChatSetOption(@"arrivalTap",@(on));}];
        arrival.accessibilityIdentifier=@"WPQuickChatArrivalAvatarTap";[card addArrangedSubview:arrival];
        UIView *mode=[page segmentedRowWithTitle:@"临时提示头像打开方式" items:@[@"小窗",@"全屏"] selected:(NSInteger)WPQuickChatOptionNumber(@"openMode") handler:^(NSInteger value){WPQuickChatSetOption(@"openMode",@(value));}];
        mode.accessibilityIdentifier=@"WPQuickChatArrivalAvatarMode";[card addArrangedSubview:mode];
    }
}

void WPAddQuickChatGestureSettings(WPCardPageController *page) {
    [page addSectionTitle:@"聊天头像操作"];
    WPAddQuickChatGestureRows(page,[page addCard]);
}

@interface WPQuickChatSettingsController () <UIColorPickerViewControllerDelegate>
@end
@implementation WPQuickChatSettingsController
- (void)viewDidLoad{self.title=@"快捷聊天";[super viewDidLoad];}
- (void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];[self reloadCards];}
- (UIView *)toggle:(NSString *)title key:(NSString *)key detail:(NSString *)detail{
    return [self switchRowWithTitle:title detail:detail on:WPQuickChatOptionBool(key) handler:^(BOOL on){WPQuickChatSetOption(key,@(on));}];
}
- (UIView *)slider:(NSString *)title key:(NSString *)key minimum:(float)minimum maximum:(float)maximum format:(NSString *(^)(float))format{
    UIView *row=[self sliderRowWithTitle:title value:WPQuickChatOptionNumber(key) minimum:minimum maximum:maximum format:format handler:^(float value){WPQuickChatSetOption(key,@(value));}];
    for(UIView *view in row.subviews)if([view isKindOfClass:UISlider.class])((UISlider *)view).continuous=NO;
    return row;
}
- (UIView *)choice:(NSString *)title key:(NSString *)key items:(NSArray *)items{
    return [self segmentedRowWithTitle:title items:items selected:(NSInteger)WPQuickChatOptionNumber(key) handler:^(NSInteger value){WPQuickChatSetOption(key,@(value));}];
}
- (void)buildCards{
    __weak typeof(self) weakSelf=self;
    NSString *(^pixels)(float)=^NSString *(float value){return [NSString stringWithFormat:@"%.0f",value];};
    NSString *(^percent)(float)=^NSString *(float value){return [NSString stringWithFormat:@"%.0f%%",value*100];};
    [self addSectionTitle:@"消息提示"];
    UIStackView *pet=[self addCard];
    [pet addArrangedSubview:[self toggle:@"截图与录屏隐藏" key:@"hideCapture" detail:@"保护桌宠与快捷聊天；开启后请在本机截图确认效果"]];
    if(!WPBarrageEnabled()){
    [pet addArrangedSubview:[self toggle:@"新消息头像提示" key:@"arrivalAvatar" detail:@"新消息到达时在桌宠附近短暂显示发送方头像"]];
    [pet addArrangedSubview:[self slider:@"提示头像显示时长" key:@"arrivalDuration" minimum:1 maximum:15 format:^NSString *(float value){return [NSString stringWithFormat:@"%.0f 秒",value];}]];
    }
    [pet addArrangedSubview:[self toggle:@"桌宠显示会话角标" key:@"buttonBadge" detail:@"在桌宠附近显示未读会话数量"]];

    [self addNote:WPBarrageEnabled()?@"当前开启聊天弹幕：头顶头像由弹幕与最新未读消息统一管理，结束动画可在弹幕设置中选择。":@"临时提示头像的时长只影响新消息到达时的短暂提示；头像点击方式可在快捷设置中调整。"];
    [self addSectionTitle:@"侧栏外观"];
    UIStackView *appearance=[self addCard];
    [appearance addArrangedSubview:[self rowWithTitle:@"侧栏位置" detail:@"桌宠在左侧贴边隐藏或固定时显示在右侧，其余情况显示在左侧" actionTitle:@"自动" handler:nil]];
    [appearance addArrangedSubview:[self choice:@"侧栏样式" key:@"style" items:@[@"圆角浮岛",@"贴边直栏"]]];
    [appearance addArrangedSubview:[self slider:@"侧栏宽度" key:@"width" minimum:60 maximum:180 format:pixels]];
    [appearance addArrangedSubview:[self slider:@"侧栏高度" key:@"height" minimum:0 maximum:900 format:^NSString *(float value){return value<1?@"自适应":[NSString stringWithFormat:@"%.0f",value];}]];
    [appearance addArrangedSubview:[self choice:@"垂直位置" key:@"vertical" items:@[@"居中",@"顶部固定"]]];
    [appearance addArrangedSubview:[self slider:@"侧栏圆角" key:@"radius" minimum:0 maximum:44 format:pixels]];
    [appearance addArrangedSubview:[self slider:@"侧栏透明度" key:@"opacity" minimum:.25 maximum:1 format:percent]];
    [appearance addArrangedSubview:[self choice:@"背景颜色" key:@"background" items:@[@"自动",@"浅色",@"深色",@"自定"]]];
    [appearance addArrangedSubview:[self rowWithTitle:@"自定义背景色" detail:nil actionTitle:@"选择" handler:^{UIColorPickerViewController *picker=[UIColorPickerViewController new];picker.delegate=weakSelf;picker.supportsAlpha=NO;picker.selectedColor=WPQuickChatBackgroundColor(weakSelf.traitCollection);[weakSelf presentViewController:picker animated:YES completion:nil];}]];
    [appearance addArrangedSubview:[self slider:@"头像大小" key:@"avatarSize" minimum:28 maximum:72 format:pixels]];
    [appearance addArrangedSubview:[self toggle:@"显示昵称" key:@"showNames" detail:@"控制侧栏会话名称；弹幕昵称在聊天弹幕设置中单独开启"]];
    [appearance addArrangedSubview:[self slider:@"昵称间距" key:@"nameGap" minimum:0 maximum:16 format:pixels]];
    [appearance addArrangedSubview:[self slider:@"会话间距" key:@"sessionGap" minimum:0 maximum:24 format:pixels]];

    [self addSectionTitle:@"显示方式"];
    UIStackView *display=[self addCard];
    [display addArrangedSubview:[self choice:@"会话模式" key:@"customMode" items:@[@"跟随微信",@"自定义"]]];
    [display addArrangedSubview:[self choice:@"过滤规则" key:@"filter" items:@[@"全部",@"好友",@"群聊"]]];
    [display addArrangedSubview:[self toggle:@"好友与群聊分开显示" key:@"separate" detail:nil]];
    [display addArrangedSubview:[self toggle:@"未读会话在前" key:@"unreadFirst" detail:nil]];
    [display addArrangedSubview:[self toggle:@"置顶会话常显" key:@"pinnedAlways" detail:@"限制会话数量时继续保留置顶会话"]];
    [display addArrangedSubview:[self slider:@"会话数量" key:@"limit" minimum:0 maximum:100 format:^NSString *(float value){return value<1?@"全部":[NSString stringWithFormat:@"%.0f 个",value];}]];
    [display addArrangedSubview:[self rowWithTitle:@"已移出会话" detail:@"在头像菜单中可从侧栏移出，不删除微信聊天" actionTitle:[NSString stringWithFormat:@"恢复 %lu 个",(unsigned long)WPQuickChatRemovedUsernames().count] handler:^{WPQuickChatRestoreRemoved();[weakSelf reloadCards];}]];
    [self addSectionTitle:@"角标与会话过滤"];
    UIStackView *filters=[self addCard];
    for(NSArray *item in @[@[@"显示红点",@"showRedDot"],@[@"数字角标",@"numericBadge"],@[@"显示免打扰会话",@"showMuted"],@[@"显示折叠群聊",@"showFolded"],@[@"显示服务号",@"showService"],@[@"显示公众号",@"showOfficial"]])
        [filters addArrangedSubview:[self toggle:item[0] key:item[1] detail:nil]];
    [self addNote:@"跟随微信保留会话原顺序；自定义按最新消息时间排序。置顶、好友/群聊分组和未读优先选项会先于此顺序生效。侧栏会话过滤只影响快捷聊天列表；消息弹幕仍遵守独立的提醒、免打扰和隐藏会话规则。头像优先读取微信本地缓存，缺失时进行有限重试。"];
}
- (void)colorPickerViewControllerDidSelectColor:(UIColorPickerViewController *)picker{
    CGFloat r,g,b,a;if(![picker.selectedColor getRed:&r green:&g blue:&b alpha:&a])return;
    [WPPreferences() setObject:@[@(r),@(g),@(b),@(a)] forKey:@"quickChat.backgroundRGBA"];WPQuickChatSetOption(@"background",@3);
}
@end
