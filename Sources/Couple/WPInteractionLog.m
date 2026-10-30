#import "WPInteractionLog.h"
#import "WPCoupleHistory.h"
#import "WPMenuIcons.h"
#import "WPTheme.h"
#import "WPOverlay.h"

NSString *WPInteractionStatusText(NSDictionary *row){
    if([row[@"direction"] isEqual:@"incoming"]){
        if([row[@"needs_response"] boolValue])return @"待回应";
        if([row[@"resolve_type"] isEqual:@"reply"])return @"已回应";
        if([row[@"resolve_type"] isEqual:@"manual_clear"])return @"手动清除";
        return @"已接收";
    }
    NSString *state=@{@"waiting":@"等待发送",@"queued":@"已发出 · 等 TA 回到微信",@"online":@"已发出",@"failed":@"暂未送达，会自动重试",
        @"delivered":@"已送达",@"expired":@"未送达（已过期）"}[row[@"state"]]?:@"等待确认";
    NSUInteger pendingReply=[row[@"resolves"] count],resolved=[row[@"resolved_count"] unsignedIntegerValue];
    if(pendingReply)return [state stringByAppendingFormat:@" · 回应 %lu 条，送出后生效",(unsigned long)pendingReply];
    if(resolved)return [state stringByAppendingFormat:@" · 回应了 %lu 条",(unsigned long)resolved];
    return state;
}

static NSString *WPBubbleTime(NSDate *date){
    static NSDateFormatter *today,*year,*full;static dispatch_once_t once;dispatch_once(&once,^{
        today=[NSDateFormatter new];today.dateFormat=@"HH:mm";year=[NSDateFormatter new];year.dateFormat=@"MM-dd HH:mm";full=[NSDateFormatter new];full.dateFormat=@"yyyy-MM-dd HH:mm";
    });
    NSCalendar *calendar=NSCalendar.currentCalendar;
    if([calendar isDateInToday:date])return [today stringFromDate:date];
    if([calendar component:NSCalendarUnitYear fromDate:date]==[calendar component:NSCalendarUnitYear fromDate:NSDate.date])return [year stringFromDate:date];
    return [full stringFromDate:date];
}

@interface WPBubbleCell : UITableViewCell
@property(nonatomic) UILabel *tagLabel;
@property(nonatomic) UIView *bubble;
@property(nonatomic) UIImageView *icon;
@property(nonatomic) UILabel *titleLabel;
@property(nonatomic) UILabel *metaLabel;
@property(nonatomic) NSArray<NSLayoutConstraint *> *leftConstraints;
@property(nonatomic) NSArray<NSLayoutConstraint *> *rightConstraints;
@property(nonatomic) BOOL anger;
@end
@implementation WPBubbleCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier{
    if((self=[super initWithStyle:style reuseIdentifier:reuseIdentifier])){
        self.backgroundColor=UIColor.clearColor;self.selectionStyle=UITableViewCellSelectionStyleNone;
        UIView *content=self.contentView;
        self.tagLabel=WPThemeLabel(nil,12,UIFontWeightSemibold,WPThemePrimaryText());self.tagLabel.numberOfLines=1;self.tagLabel.textAlignment=NSTextAlignmentCenter;
        self.tagLabel.layer.cornerRadius=15;self.tagLabel.clipsToBounds=YES;self.tagLabel.translatesAutoresizingMaskIntoConstraints=NO;self.tagLabel.isAccessibilityElement=NO;
        self.bubble=[UIView new];self.bubble.layer.cornerRadius=16;self.bubble.layer.cornerCurve=kCACornerCurveContinuous;self.bubble.translatesAutoresizingMaskIntoConstraints=NO;
        self.icon=[UIImageView new];self.icon.contentMode=UIViewContentModeScaleAspectFit;self.icon.translatesAutoresizingMaskIntoConstraints=NO;
        self.titleLabel=WPThemeLabel(nil,16,UIFontWeightSemibold,WPThemePrimaryText());self.titleLabel.translatesAutoresizingMaskIntoConstraints=NO;
        self.metaLabel=WPThemeLabel(nil,12,UIFontWeightRegular,WPThemeSecondaryText());self.metaLabel.translatesAutoresizingMaskIntoConstraints=NO;
        [content addSubview:self.tagLabel];[content addSubview:self.bubble];
        for(UIView *view in @[self.icon,self.titleLabel,self.metaLabel])[self.bubble addSubview:view];
        [NSLayoutConstraint activateConstraints:@[
            [self.tagLabel.widthAnchor constraintEqualToConstant:30],[self.tagLabel.heightAnchor constraintEqualToConstant:30],
            [self.tagLabel.topAnchor constraintEqualToAnchor:self.bubble.topAnchor],
            [self.bubble.topAnchor constraintEqualToAnchor:content.topAnchor constant:6],[self.bubble.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-6],
            // Bubbles stay within about 72% of the row and wrap long status text.
            [self.bubble.widthAnchor constraintLessThanOrEqualToAnchor:content.widthAnchor multiplier:.72],
            [self.icon.leadingAnchor constraintEqualToAnchor:self.bubble.leadingAnchor constant:14],[self.icon.widthAnchor constraintEqualToConstant:18],[self.icon.heightAnchor constraintEqualToConstant:18],
            [self.icon.centerYAnchor constraintEqualToAnchor:self.titleLabel.centerYAnchor],
            [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.icon.trailingAnchor constant:8],[self.titleLabel.trailingAnchor constraintEqualToAnchor:self.bubble.trailingAnchor constant:-14],
            [self.titleLabel.topAnchor constraintEqualToAnchor:self.bubble.topAnchor constant:11],
            [self.metaLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:4],[self.metaLabel.bottomAnchor constraintEqualToAnchor:self.bubble.bottomAnchor constant:-11],
            [self.metaLabel.leadingAnchor constraintEqualToAnchor:self.bubble.leadingAnchor constant:14],[self.metaLabel.trailingAnchor constraintEqualToAnchor:self.bubble.trailingAnchor constant:-14]]];
        self.leftConstraints=@[[self.tagLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16],
            [self.bubble.leadingAnchor constraintEqualToAnchor:self.tagLabel.trailingAnchor constant:8],
            [self.bubble.trailingAnchor constraintLessThanOrEqualToAnchor:content.trailingAnchor constant:-16]];
        self.rightConstraints=@[[self.tagLabel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16],
            [self.bubble.trailingAnchor constraintEqualToAnchor:self.tagLabel.leadingAnchor constant:-8],
            [self.bubble.leadingAnchor constraintGreaterThanOrEqualToAnchor:content.leadingAnchor constant:16]];
        self.isAccessibilityElement=YES;
    }return self;
}
- (void)configure:(NSDictionary *)row{
    BOOL mine=[row[@"direction"] isEqual:@"outgoing"],anger=[row[@"kind"] isEqual:@"anger"];
    self.anger=anger;
    [NSLayoutConstraint deactivateConstraints:mine?self.leftConstraints:self.rightConstraints];
    [NSLayoutConstraint activateConstraints:mine?self.rightConstraints:self.leftConstraints];
    self.tagLabel.text=mine?@"我":@"宝宝";
    self.tagLabel.backgroundColor=mine?[UIColor.systemBlueColor colorWithAlphaComponent:.35]:WPThemeElevated();
    // Side encodes the sender; the icon and a faint tint encode the action.
    UIColor *base=mine?WPThemeOutgoingBubble():WPThemeCard();
    self.bubble.backgroundColor=base;
    if(anger){self.bubble.layer.borderWidth=1;[self updateBorderColor];}
    else {self.bubble.layer.borderWidth=0;}
    self.icon.image=anger?WPBrokenHeartMenuIcon():[UIImage systemImageNamed:@"heart.fill"];
    self.icon.tintColor=anger?UIColor.systemGrayColor:UIColor.systemPinkColor;
    self.titleLabel.text=WPInteractionTitle(row[@"kind"]);
    NSString *status=WPInteractionStatusText(row);
    NSString *time=WPBubbleTime([NSDate dateWithTimeIntervalSince1970:[row[@"sent_at"] doubleValue]]);
    NSMutableAttributedString *meta=[[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@ · ",time] attributes:@{NSForegroundColorAttributeName:WPThemeSecondaryText()}];
    UIColor *statusColor=[status isEqual:@"待回应"]?UIColor.systemOrangeColor:WPThemeSecondaryText();
    [meta appendAttributedString:[[NSAttributedString alloc] initWithString:status attributes:@{NSForegroundColorAttributeName:statusColor}]];
    self.metaLabel.attributedText=meta;
    self.metaLabel.textAlignment=self.titleLabel.textAlignment=NSTextAlignmentNatural;
    self.accessibilityLabel=[NSString stringWithFormat:@"%@，%@，%@，%@",mine?@"我发出":@"TA 发来",self.titleLabel.text,time,status];
}
- (void)updateBorderColor{self.bubble.layer.borderColor=[UIColor.separatorColor resolvedColorWithTraitCollection:self.traitCollection].CGColor;}
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection{
    [super traitCollectionDidChange:previousTraitCollection];
    if(self.anger && (!previousTraitCollection || [self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]))[self updateBorderColor];
}
@end

@interface WPInteractionLogController ()
@property(nonatomic,readwrite) NSArray<NSDictionary *> *rows;
@property(nonatomic,readwrite) UIButton *replyButton;
@property(nonatomic) UIButton *petButton;
@property(nonatomic,readwrite) UIButton *clearButton;
@property(nonatomic) UILabel *summaryLabel;
@property(nonatomic) UILabel *detailLabel;
@property(nonatomic) UILabel *statusLabel;
@property(nonatomic) UIView *header;
@property(nonatomic) UILabel *emptyLabel;
@property(nonatomic) BOOL sendingReply;
@end
@implementation WPInteractionLogController
- (instancetype)init{return [super initWithStyle:UITableViewStylePlain];}
- (void)viewDidLoad{
    [super viewDidLoad];self.title=@"互动记录";
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"完成" style:UIBarButtonItemStyleDone target:self action:@selector(done)];
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"清空" style:UIBarButtonItemStylePlain target:self action:@selector(promptClearHistory)];
    self.tableView.backgroundColor=WPThemeBackground();self.tableView.separatorStyle=UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight=UITableViewAutomaticDimension;self.tableView.estimatedRowHeight=72;self.tableView.allowsSelection=NO;
    [self.tableView registerClass:WPBubbleCell.class forCellReuseIdentifier:@"bubble"];
    [self buildHeader];
    self.emptyLabel=WPThemeLabel(@"还没有互动记录\n长按桌宠滑到“想你了”，给 TA 发第一条吧",15,UIFontWeightRegular,WPThemeSecondaryText());
    self.emptyLabel.textAlignment=NSTextAlignmentCenter;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reload) name:WPCoupleHistoryDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reload) name:@"WeChatPet.PeerStatusChanged" object:nil];[self reload];
}
- (void)buildHeader{
    UIStackView *card=[UIStackView new];card.axis=UILayoutConstraintAxisVertical;card.spacing=12;card.translatesAutoresizingMaskIntoConstraints=NO;
    card.layoutMarginsRelativeArrangement=YES;card.directionalLayoutMargins=NSDirectionalEdgeInsetsMake(18,18,18,18);
    UIView *background=[UIView new];background.backgroundColor=WPThemeCard();background.layer.cornerRadius=WPThemeCardRadius;background.layer.cornerCurve=kCACornerCurveContinuous;
    background.translatesAutoresizingMaskIntoConstraints=NO;[card insertSubview:background atIndex:0];
    self.summaryLabel=WPThemeLabel(nil,20,UIFontWeightBold,WPThemePrimaryText());
    self.detailLabel=WPThemeLabel(nil,13,UIFontWeightRegular,WPThemeSecondaryText());
    __weak typeof(self) weakSelf=self;
    self.replyButton=[UIButton buttonWithType:UIButtonTypeCustom];self.replyButton.backgroundColor=UIColor.systemBlueColor;
    [self.replyButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];[self.replyButton setTitleColor:[UIColor colorWithWhite:1 alpha:.6] forState:UIControlStateDisabled];
    [self.replyButton setTitleColor:[UIColor colorWithWhite:1 alpha:.7] forState:UIControlStateHighlighted];
    self.replyButton.titleLabel.font=[UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];self.replyButton.layer.cornerRadius=14;self.replyButton.layer.cornerCurve=kCACornerCurveContinuous;
    [self.replyButton.heightAnchor constraintEqualToConstant:50].active=YES;
    [self.replyButton addAction:[UIAction actionWithHandler:^(__unused UIAction *a){[weakSelf replyAll];}] forControlEvents:UIControlEventTouchUpInside];
    self.petButton=[UIButton buttonWithType:UIButtonTypeSystem];
    [self.petButton setTitle:@"摸摸头" forState:UIControlStateNormal];
    self.petButton.titleLabel.font=[UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    self.petButton.backgroundColor=WPThemeElevated();self.petButton.layer.cornerRadius=14;
    [self.petButton.heightAnchor constraintEqualToConstant:48].active=YES;
    [self.petButton addAction:[UIAction actionWithHandler:^(__unused UIAction *a){[weakSelf sendPet];}] forControlEvents:UIControlEventTouchUpInside];
    self.clearButton=[UIButton buttonWithType:UIButtonTypeCustom];[self.clearButton setTitle:@"清除我的红点" forState:UIControlStateNormal];
    self.clearButton.titleLabel.font=[UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    [self.clearButton setTitleColor:WPThemePrimaryText() forState:UIControlStateNormal];[self.clearButton setTitleColor:WPThemeSecondaryText() forState:UIControlStateHighlighted];
    self.clearButton.backgroundColor=WPThemeElevated();self.clearButton.layer.cornerRadius=12;self.clearButton.layer.cornerCurve=kCACornerCurveContinuous;
    [self.clearButton.heightAnchor constraintEqualToConstant:42].active=YES;
    [self.clearButton addAction:[UIAction actionWithHandler:^(__unused UIAction *a){[weakSelf clearMyBadge];}] forControlEvents:UIControlEventTouchUpInside];
    self.statusLabel=WPThemeLabel(nil,12,UIFontWeightRegular,WPThemeSecondaryText());self.statusLabel.hidden=YES;
    for(UIView *view in @[self.summaryLabel,self.detailLabel,self.replyButton,self.petButton,self.clearButton,self.statusLabel])[card addArrangedSubview:view];
    [card setCustomSpacing:4 afterView:self.summaryLabel];[card setCustomSpacing:16 afterView:self.detailLabel];[card setCustomSpacing:10 afterView:self.replyButton];
    UIView *header=[UIView new];[header addSubview:card];
    [NSLayoutConstraint activateConstraints:@[[background.topAnchor constraintEqualToAnchor:card.topAnchor],[background.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],
        [background.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],[background.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [card.topAnchor constraintEqualToAnchor:header.topAnchor constant:12],[card.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-14],
        [card.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],[card.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16]]];
    self.header=header;
}
- (void)viewDidLayoutSubviews{
    [super viewDidLayoutSubviews];
    CGFloat width=self.tableView.bounds.size.width;if(width<=0)return;
    CGSize size=[self.header systemLayoutSizeFittingSize:CGSizeMake(width,UILayoutFittingCompressedSize.height) withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    if(self.tableView.tableHeaderView!=self.header || fabs(self.header.frame.size.height-size.height)>.5 || fabs(self.header.frame.size.width-width)>.5){
        self.header.frame=CGRectMake(0,0,width,size.height);self.tableView.tableHeaderView=self.header;
    }
}
- (void)done{if(self.onClose)self.onClose();else [self.navigationController popViewControllerAnimated:YES];}
- (void)reload{
    WPCoupleHistory *history=WPCoupleHistory.sharedHistory;
    self.rows=history.recentInteractions;
    NSUInteger pending=history.badgeCount,angry=0;for(NSDictionary *row in history.pendingIncoming)if([row[@"kind"] isEqual:@"anger"])angry++;
    self.summaryLabel.text=pending?[NSString stringWithFormat:@"%lu 条待回应",(unsigned long)pending]:@"没有待回应的互动";
    self.detailLabel.text=pending?(angry?[NSString stringWithFormat:@"其中 %lu 条生气待安抚；每次摸头安抚一条，想你了只回应普通超时提醒。",(unsigned long)angry]:@"普通互动超过 5 分钟才收到，会留下待回应红点。")
        :@"想你了和摸摸头可以独立发送；生气总会等待一次摸头安抚。";
    self.detailLabel.text=[self.detailLabel.text stringByAppendingString:@" 互动记录与待回应提醒保留最近 3 天，到期自动清理。"];
    NSUInteger ordinary=history.uncoveredPendingIncomingIdentifiers.count;
    BOOL replyWaiting=ordinary==0 && pending>angry;
    [UIView performWithoutAnimation:^{
        [self.replyButton setTitle:replyWaiting?@"普通回应等待发送中":(ordinary?@"想你了 · 回应普通提醒":@"想你了") forState:UIControlStateNormal];[self.replyButton layoutIfNeeded];
    }];
    BOOL hidden=[[WPOverlayManager sharedManager] stealthEnabled];
    self.replyButton.backgroundColor=hidden?UIColor.blackColor:UIColor.systemBlueColor;
    self.replyButton.enabled=!hidden && !replyWaiting && !self.sendingReply;
    self.replyButton.accessibilityHint=replyWaiting?@"回应已保存在本机，正在等待服务器确认":(ordinary?@"发送一次想你了，回应当前普通超时提醒":@"给宝宝发送想你了");
    self.petButton.tintColor=hidden?UIColor.blackColor:UIColor.systemBlueColor;
    self.petButton.enabled=!hidden && !self.sendingReply;
    self.clearButton.enabled=pending>0;self.clearButton.alpha=pending?1:.45;
    self.tableView.backgroundView=self.rows.count?nil:self.emptyLabel;
    [self.tableView reloadData];[self.view setNeedsLayout];
}
- (void)showStatus:(NSString *)text{self.statusLabel.text=text;self.statusLabel.hidden=!text.length;[self.view setNeedsLayout];}
- (void)replyAll{
    WPCoupleHistory *history=WPCoupleHistory.sharedHistory;
    if(self.sendingReply)return;
    if(history.badgeCount>0 && !history.uncoveredPendingIncomingIdentifiers.count && !history.hasPendingAnger){[self showStatus:@"之前的普通回应还在等待发送，请连接后再查看状态。"];return;}
    __weak typeof(self) weakSelf=self;self.sendingReply=YES;self.replyButton.enabled=NO;
    NSUInteger pending=history.uncoveredPendingIncomingIdentifiers.count;
    [[WPOverlayManager sharedManager] sendInteraction:@"miss" completion:^(BOOL accepted,NSString *message){
        weakSelf.sendingReply=NO;
        [weakSelf reload];
        [weakSelf showStatus:accepted&&pending&&!WPCoupleHistory.sharedHistory.badgeCount?[NSString stringWithFormat:@"已回应 %lu 条 · %@",(unsigned long)pending,message]:message];
    }];
}
- (void)sendPet{
    if(self.sendingReply)return;
    self.sendingReply=YES;self.petButton.enabled=NO;
    __weak typeof(self) weakSelf=self;
    [[WPOverlayManager sharedManager] sendInteraction:@"pet" completion:^(BOOL accepted,NSString *message){
        weakSelf.sendingReply=NO;[weakSelf reload];[weakSelf showStatus:message];
    }];
}
/// UIKit usually removes the alert before running an action handler; a
/// dismiss call with nothing presented may never run its completion.
- (void)afterAlertDismissal:(void (^)(void))block{
    if(self.presentedViewController)[self dismissViewControllerAnimated:YES completion:block];
    else dispatch_async(dispatch_get_main_queue(),block);
}
- (void)promptClearHistory{
    if(self.presentedViewController || !self.view.window)return;
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"清空互动记录" message:@"确定要清空全部本地互动记录吗？（超过3天的历史记录已自动清除）" preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf=self;
    [alert addAction:[UIAlertAction actionWithTitle:@"清空" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a){
        if([WPCoupleHistory.sharedHistory clearAllHistory])[weakSelf showStatus:@"已清空全部本地互动记录"];
        else [weakSelf showStatus:@"记录暂时无法保存，请稍后重试"];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)clearMyBadge{
    if(self.presentedViewController || !self.view.window)return;
    // Snapshot before the first prompt. Anything arriving during either
    // confirmation stays pending even if both are accepted.
    NSArray<NSString *> *snapshot=[[WPCoupleHistory.sharedHistory.pendingIncoming valueForKey:@"id"] copy];
    if(!snapshot.count)return;
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"清除我的红点" message:@"这样可能会导致关系恶化，确定要继续清除吗？" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf=self;
    [alert addAction:[UIAlertAction actionWithTitle:@"继续清除" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action){
        [weakSelf afterAlertDismissal:^{[weakSelf confirmClearIdentifiers:snapshot];}];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)confirmClearIdentifiers:(NSArray<NSString *> *)identifiers{
    if(self.presentedViewController || !self.view.window)return;
    NSString *message=[NSString stringWithFormat:@"确定清除这 %lu 条提醒吗？清除后仍会保留互动记录。",(unsigned long)identifiers.count];
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"再次确认" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf=self;
    [alert addAction:[UIAlertAction actionWithTitle:@"确认清除" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action){
        [weakSelf afterAlertDismissal:^{
            if(!weakSelf.view.window)return;
            // Local state only; this path never sends anything to TA.
            if(![WPCoupleHistory.sharedHistory manuallyClearIncomingIdentifiers:identifiers])[weakSelf showClearSaveFailure];
            else [weakSelf showStatus:@"已清除，记录保留；TA 不会收到通知。"];
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)showClearSaveFailure{
    if(self.presentedViewController || !self.view.window)return;
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"未能保存" message:@"互动状态暂时无法保存，红点已保留，请稍后重试。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{return self.rows.count;}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath{
    WPBubbleCell *cell=[tableView dequeueReusableCellWithIdentifier:@"bubble" forIndexPath:indexPath];[cell configure:self.rows[indexPath.row]];return cell;
}
- (void)dealloc{[NSNotificationCenter.defaultCenter removeObserver:self];}
@end
