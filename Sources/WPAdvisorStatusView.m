#import "WPAdvisorStatusView.h"
#import "WPChoiceSheet.h"
#import "WPTheme.h"
#import <math.h>

static NSString *WPAdvisorSafeString(id value,NSUInteger limit) {
    if(![value isKindOfClass:NSString.class])return @"";
    NSString *text=[(NSString *)value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if(text.length>limit)text=[[text substringToIndex:limit] stringByAppendingString:@"…"];
    return text;
}

@interface WPAdvisorCapsuleButton : UIButton
@property(nonatomic,strong) UIView *progressFill;
@property(nonatomic,strong) UIView *progressBar;
@property(nonatomic) CGFloat progress;
@property(nonatomic) BOOL isGenerating;
@property(nonatomic,copy) NSString *taskIdentifier;
@property(nonatomic,copy) NSString *displayName;
- (void)updateProgress:(CGFloat)progress;
@end

@implementation WPAdvisorCapsuleButton
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])){
        _progressFill=[UIView new];
        _progressFill.userInteractionEnabled=NO;
        _progressFill.backgroundColor=[UIColor.systemGreenColor colorWithAlphaComponent:0.25];
        _progressFill.hidden=YES;
        [self addSubview:_progressFill];

        _progressBar=[UIView new];
        _progressBar.userInteractionEnabled=NO;
        _progressBar.backgroundColor=UIColor.systemGreenColor;
        _progressBar.layer.cornerRadius=1.5;
        _progressBar.clipsToBounds=YES;
        _progressBar.hidden=YES;
        [self addSubview:_progressBar];

        self.layer.cornerRadius=17;
        self.layer.borderWidth=0.6;
        self.layer.borderColor=[UIColor colorWithWhite:1.0 alpha:0.18].CGColor;
        self.clipsToBounds=YES;
        self.tintColor=UIColor.whiteColor;
        [self setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        self.titleLabel.font=[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        self.titleLabel.lineBreakMode=NSLineBreakByTruncatingTail;
        self.contentEdgeInsets=UIEdgeInsetsMake(0,12,0,12);

        self.backgroundColor=[UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits){
            return traits.userInterfaceStyle==UIUserInterfaceStyleDark ?
                [UIColor colorWithWhite:0.10 alpha:0.55] :
                [UIColor colorWithWhite:0.15 alpha:0.50];
        }];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    if(self.isGenerating && self.progress > 0){
        CGFloat w=self.bounds.size.width;
        CGFloat h=self.bounds.size.height;
        CGFloat fillW=MAX(0,MIN(w,w*self.progress));
        self.progressFill.frame=CGRectMake(0,0,fillW,h);
        self.progressBar.frame=CGRectMake(0,h-3,fillW,3);
        self.progressFill.hidden=NO;
        self.progressBar.hidden=NO;
    } else {
        self.progressFill.hidden=YES;
        self.progressBar.hidden=YES;
    }
    if(self.titleLabel)[self bringSubviewToFront:self.titleLabel];
}
- (void)updateProgress:(CGFloat)progress {
    self.progress=progress;
    int percent=(int)round(progress*100);
    NSString *title=[NSString stringWithFormat:@"%@ · 生成中 %d%%  ×",self.displayName?:@"联系人",percent];
    [self setTitle:title forState:UIControlStateNormal];
    self.accessibilityLabel=[NSString stringWithFormat:@"%@，生成中 %d%%，点击取消",self.displayName?:@"联系人",percent];
    [self setNeedsLayout];
}
@end

@interface WPAdvisorStatusView ()
@property(nonatomic,copy) NSArray<NSDictionary<NSString *,id> *> *tasks;
@property(nonatomic,strong) NSMutableArray<UIButton *> *capsules;
@property(nonatomic,strong) UIButton *badge;
@property(nonatomic,strong) UILabel *badgeLabel;
@property(nonatomic,strong) NSTimer *progressTimer;
@property(nonatomic,strong) NSMutableDictionary<NSString *,NSNumber *> *taskStartTimes;
@property(nonatomic) CGRect safeBounds;
@property(nonatomic) CGRect petFrame;
@property(nonatomic) CGRect unreadAvatarFrame;
@property(nonatomic) BOOL petVisible;
@property(nonatomic,readwrite) NSUInteger unreadCount;
@end

@implementation WPAdvisorStatusView
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])){
        self.backgroundColor=UIColor.clearColor;self.opaque=NO;
        self.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        _capsules=[NSMutableArray new];_unreadAvatarFrame=CGRectNull;
        _taskStartTimes=[NSMutableDictionary new];
        _badge=[UIButton buttonWithType:UIButtonTypeCustom];_badge.accessibilityIdentifier=@"WPAdvisorUnreadBadge";
        _badge.accessibilityTraits=UIAccessibilityTraitButton;
        _badge.backgroundColor=UIColor.clearColor;_badge.hidden=YES;
        UIView *disk=[UIView new];disk.userInteractionEnabled=NO;disk.backgroundColor=UIColor.systemRedColor;
        disk.layer.cornerRadius=9;disk.translatesAutoresizingMaskIntoConstraints=NO;[_badge addSubview:disk];
        _badgeLabel=[UILabel new];_badgeLabel.userInteractionEnabled=NO;_badgeLabel.textColor=UIColor.whiteColor;
        _badgeLabel.font=[UIFont systemFontOfSize:10 weight:UIFontWeightBold];_badgeLabel.textAlignment=NSTextAlignmentCenter;
        _badgeLabel.translatesAutoresizingMaskIntoConstraints=NO;[disk addSubview:_badgeLabel];
        [NSLayoutConstraint activateConstraints:@[[disk.centerXAnchor constraintEqualToAnchor:_badge.centerXAnchor],
            [disk.centerYAnchor constraintEqualToAnchor:_badge.centerYAnchor],[disk.widthAnchor constraintGreaterThanOrEqualToConstant:18],
            [disk.heightAnchor constraintEqualToConstant:18],[_badgeLabel.leadingAnchor constraintEqualToAnchor:disk.leadingAnchor constant:4],
            [_badgeLabel.trailingAnchor constraintEqualToAnchor:disk.trailingAnchor constant:-4],
            [_badgeLabel.topAnchor constraintEqualToAnchor:disk.topAnchor],[_badgeLabel.bottomAnchor constraintEqualToAnchor:disk.bottomAnchor]]];
        __weak typeof(self) weakSelf=self;
        [_badge addAction:[UIAction actionWithHandler:^(__unused UIAction *action){if(weakSelf.onOpenUnread)weakSelf.onOpenUnread();}] forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_badge];
    }return self;
}
- (void)dealloc {
    [_progressTimer invalidate];
}
- (void)tickProgress {
    BOOL anyGenerating=NO;
    CFTimeInterval now=CACurrentMediaTime();
    for(UIButton *b in self.capsules){
        if(![b isKindOfClass:WPAdvisorCapsuleButton.class])continue;
        WPAdvisorCapsuleButton *button=(WPAdvisorCapsuleButton *)b;
        if(!button.isGenerating)continue;
        anyGenerating=YES;
        NSNumber *startNum=self.taskStartTimes[button.taskIdentifier];
        CFTimeInterval start=startNum?startNum.doubleValue:now;
        CFTimeInterval elapsed=MAX(0,now-start);
        CGFloat prog=1.0 - 0.95*exp(-elapsed/3.2);
        if(prog<0.05)prog=0.05;if(prog>0.96)prog=0.96;
        [button updateProgress:prog];
    }
    if(!anyGenerating){
        [self.progressTimer invalidate];self.progressTimer=nil;
    }
}
- (void)updateActiveTasks:(NSArray<NSDictionary<NSString *,id> *> *)tasks {
    NSAssert(NSThread.isMainThread,@"Advisor status UI must update on main thread");
    NSMutableArray *items=[NSMutableArray new];
    if([tasks isKindOfClass:NSArray.class])for(id raw in tasks){
        if(![raw isKindOfClass:NSDictionary.class])continue;
        NSString *identifier=WPAdvisorSafeString(raw[@"identifier"],256);if(!identifier.length)continue;
        NSString *name=WPAdvisorSafeString(raw[@"displayName"],40),*state=WPAdvisorSafeString(raw[@"state"],30);
        BOOL viewError=[raw[@"action"] isEqual:@"view"] || [state hasPrefix:@"失败"];
        [items addObject:@{@"identifier":identifier,@"displayName":name.length?name:@"联系人",@"state":state.length?state:@"生成中",@"viewError":@(viewError)}];
        if(items.count==64)break;
    }
    self.tasks=items;
    for(UIButton *button in self.capsules)[button removeFromSuperview];[self.capsules removeAllObjects];
    NSUInteger shown=MIN((NSUInteger)3,items.count);
    BOOL anyGenerating=NO;
    CFTimeInterval now=CACurrentMediaTime();
    NSMutableSet *activeIds=[NSMutableSet new];
    for(NSUInteger i=0;i<shown;i++){
        NSDictionary *item=items[i];NSString *identifier=item[@"identifier"];
        [activeIds addObject:identifier];
        BOOL viewError=[item[@"viewError"] boolValue];
        NSString *state=item[@"state"];
        BOOL isGenerating=[state containsString:@"生成中"];
        WPAdvisorCapsuleButton *button=(WPAdvisorCapsuleButton *)[self capsule:@"" identifier:[@"WPAdvisorCapsule-" stringByAppendingString:identifier]];
        button.taskIdentifier=identifier;
        button.displayName=item[@"displayName"];
        button.isGenerating=isGenerating;
        if(isGenerating){
            anyGenerating=YES;
            if(!self.taskStartTimes[identifier])self.taskStartTimes[identifier]=@(now);
            CFTimeInterval start=[self.taskStartTimes[identifier] doubleValue];
            CFTimeInterval elapsed=MAX(0,now-start);
            CGFloat prog=1.0 - 0.95*exp(-elapsed/3.2);
            if(prog<0.05)prog=0.05;if(prog>0.96)prog=0.96;
            button.progress=prog;
            int percent=(int)round(prog*100);
            NSString *title=[NSString stringWithFormat:@"%@ · 生成中 %d%%  ×",item[@"displayName"],percent];
            [button setTitle:title forState:UIControlStateNormal];
            button.accessibilityLabel=[NSString stringWithFormat:@"%@，生成中 %d%%，点击取消",item[@"displayName"],percent];
        } else {
            button.progress=0;
            NSString *title=[NSString stringWithFormat:@"%@ · %@%@",item[@"displayName"],state,viewError?@"":@"  ×"];
            [button setTitle:title forState:UIControlStateNormal];
            button.accessibilityLabel=[NSString stringWithFormat:@"%@，%@，%@",item[@"displayName"],state,viewError?@"点击查看":@"点击取消"];
        }
        __weak typeof(self) weakSelf=self;
        [button addAction:[UIAction actionWithHandler:^(__unused UIAction *action){if(weakSelf.onCancelTask)weakSelf.onCancelTask(identifier);}] forControlEvents:UIControlEventTouchUpInside];
        [self.capsules addObject:button];[self addSubview:button];
    }
    for(NSString *key in self.taskStartTimes.allKeys.copy){
        if(![activeIds containsObject:key])[self.taskStartTimes removeObjectForKey:key];
    }
    // Keep a summary control available even when there are only two or three
    // tasks: a keyboard can reduce the usable area to a single capsule slot.
    if(items.count>1){
        UIButton *more=[self capsule:[NSString stringWithFormat:@"查看全部任务 · %lu",(unsigned long)items.count] identifier:@"WPAdvisorMoreTasks"];
        more.accessibilityLabel=[NSString stringWithFormat:@"查看全部 %lu 个分析任务",(unsigned long)items.count];
        __weak typeof(self) weakSelf=self;
        [more addAction:[UIAction actionWithHandler:^(__unused UIAction *action){if(weakSelf.onShowTasks)weakSelf.onShowTasks();}] forControlEvents:UIControlEventTouchUpInside];
        [self.capsules addObject:more];[self addSubview:more];
    }
    if(anyGenerating){
        if(!self.progressTimer.valid){
            __weak typeof(self) weakSelf=self;
            self.progressTimer=[NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(__unused NSTimer *timer){
                [weakSelf tickProgress];
            }];
        }
    } else {
        [self.progressTimer invalidate];self.progressTimer=nil;
    }
    [self setNeedsLayout];
}
- (UIButton *)capsule:(NSString *)title identifier:(NSString *)identifier {
    WPAdvisorCapsuleButton *button=[WPAdvisorCapsuleButton new];
    button.accessibilityIdentifier=identifier;
    [button setTitle:title forState:UIControlStateNormal];
    return button;
}
- (void)updateUnreadCount:(NSUInteger)count {
    NSAssert(NSThread.isMainThread,@"Advisor status UI must update on main thread");
    self.unreadCount=count;self.badgeLabel.text=count>1?(count>99?@"99+":[NSString stringWithFormat:@"%lu",(unsigned long)count]):@"";
    self.badge.accessibilityLabel=[NSString stringWithFormat:@"聊天参谋有 %lu 个新结果",(unsigned long)count];
    self.badge.accessibilityHint=@"打开分析结果";[self setNeedsLayout];
}
- (void)layoutInBounds:(CGRect)safeBounds petFrame:(CGRect)petFrame petVisible:(BOOL)visible {
    self.safeBounds=safeBounds;self.petFrame=petFrame;self.petVisible=visible;[self setNeedsLayout];
}
- (void)setUnreadAvatarFrame:(CGRect)frame {
    _unreadAvatarFrame=frame;[self setNeedsLayout];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect safe=CGRectIntersection(self.bounds,self.safeBounds);
    if(CGRectIsNull(safe) || CGRectIsEmpty(safe)){for(UIButton *c in self.capsules)c.hidden=YES;self.badge.hidden=YES;return;}
    CGFloat width=MIN(280,MAX(1,CGRectGetWidth(safe)-24)),height=34;
    CGFloat margin=CGRectGetHeight(safe)>=50?8:0,available=MAX(0,CGRectGetHeight(safe)-2*margin);
    NSUInteger slots=available>=height?(NSUInteger)floor((available+5)/(height+5)):0;
    NSUInteger direct=MIN((NSUInteger)3,self.tasks.count);
    BOOL needsMore=self.tasks.count>direct || slots<direct;
    NSUInteger visibleDirect=MIN(direct,slots);
    if(needsMore && slots && self.tasks.count>1)visibleDirect=MIN(direct,slots-1);
    CGFloat y=CGRectGetMinY(safe)+margin;
    for(NSUInteger i=0;i<self.capsules.count;i++){
        UIButton *button=self.capsules[i];BOOL summary=[button.accessibilityIdentifier isEqualToString:@"WPAdvisorMoreTasks"];
        BOOL visible=summary?(needsMore && slots>0):i<visibleDirect;
        button.hidden=!visible;if(!visible)continue;
        button.frame=CGRectMake(CGRectGetMidX(safe)-width/2,y,width,height);y+=height+5;
    }
    self.badge.hidden=!self.petVisible || !self.unreadCount || CGRectIsEmpty(self.petFrame);
    if(!self.badge.hidden){
        CGFloat preferredX=CGRectGetMaxX(self.petFrame)-22,preferredY=CGRectGetMinY(self.petFrame)-22;
        CGFloat minX=CGRectGetMinX(safe),maxX=CGRectGetMaxX(safe)-44,minY=CGRectGetMinY(safe),maxY=CGRectGetMaxY(safe)-44;
        if(maxX<minX || maxY<minY){self.badge.hidden=YES;return;}
        CGFloat x=MAX(minX,MIN(maxX,preferredX)),y=MAX(minY,MIN(maxY,preferredY));
        NSMutableArray<NSValue *> *obstacles=[NSMutableArray new];CGRect avatar=self.unreadAvatarFrame;
        if(!CGRectIsNull(avatar) && !CGRectIsEmpty(avatar) && isfinite(avatar.origin.x) && isfinite(avatar.origin.y) && isfinite(avatar.size.width) && isfinite(avatar.size.height)){
            // The avatar expands its touch area to at least 44 points. Avoid
            // that area, not just its smaller visible image.
            CGFloat dx=MAX(0,(44-avatar.size.width)/2),dy=MAX(0,(44-avatar.size.height)/2);
            [obstacles addObject:[NSValue valueWithCGRect:CGRectInset(avatar,-dx-2,-dy-2)]];
        }
        // A pet near the top can put the badge over an active progress
        // capsule. Both controls must remain independently clickable.
        for(UIButton *capsule in self.capsules)if(!capsule.hidden && !CGRectIsEmpty(capsule.frame))
            [obstacles addObject:[NSValue valueWithCGRect:CGRectInset(capsule.frame,-1,-1)]];
        if(obstacles.count){
            CGFloat xs[11]={x},ys[11]={y};NSUInteger n=1;
            for(NSValue *value in obstacles){
                if(n+1>=11)break;
                CGRect avoid=value.CGRectValue;xs[n]=CGRectGetMinX(avoid)-44;ys[n]=CGRectGetMinY(avoid)-44;n++;
                xs[n]=CGRectGetMaxX(avoid);ys[n]=CGRectGetMaxY(avoid);n++;
            }
            BOOL found=NO;CGFloat best=CGFLOAT_MAX,bestX=x,bestY=y;
            for(NSUInteger i=0;i<n;i++)for(NSUInteger j=0;j<n;j++){
                CGFloat candidateX=MAX(minX,MIN(maxX,xs[i])),candidateY=MAX(minY,MIN(maxY,ys[j]));
                CGRect candidate=CGRectMake(candidateX,candidateY,44,44);BOOL overlaps=NO;
                for(NSValue *value in obstacles)if(CGRectIntersectsRect(candidate,value.CGRectValue)){overlaps=YES;break;}
                if(overlaps)continue;
                CGFloat distance=hypot(candidateX-x,candidateY-y);
                if(!found || distance<best){found=YES;best=distance;bestX=candidateX;bestY=candidateY;}
            }
            // Preserve existing touch targets when the available area is too
            // small; the result remains accessible through advisor history.
            if(!found){self.badge.hidden=YES;return;}x=bestX;y=bestY;
        }
        self.badge.frame=CGRectMake(x,y,44,44);
        [self bringSubviewToFront:self.badge];
    }
}
/// Forward touches outside visible controls to the application underneath.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit=[super hitTest:point withEvent:event];return hit==self?nil:hit;
}
@end

@interface WPAdvisorHistoryController ()
@property(nonatomic,copy) NSArray<NSDictionary<NSString *,id> *> *records;
@property(nonatomic) BOOL allowsClear;
@end
@implementation WPAdvisorHistoryController
- (instancetype)initWithTitle:(NSString *)title records:(NSArray<NSDictionary<NSString *,id> *> *)records allowsClear:(BOOL)allowsClear {
    if((self=[super initWithStyle:UITableViewStyleInsetGrouped])){self.title=title.length?title:@"聊天参谋记录";_allowsClear=allowsClear;[self updateRecords:records];}return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];self.tableView.accessibilityIdentifier=@"WPAdvisorHistoryList";
    if(self.allowsClear)self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"清除" style:UIBarButtonItemStylePlain target:self action:@selector(confirmClear)];
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(close)];
}
- (void)close {[self dismissViewControllerAnimated:YES completion:nil];}
- (void)updateRecords:(NSArray<NSDictionary<NSString *,id> *> *)records {
    NSMutableArray *validated=[NSMutableArray new];
    if([records isKindOfClass:NSArray.class])for(id raw in records){
        if(![raw isKindOfClass:NSDictionary.class])continue;
        NSString *identifier=WPAdvisorSafeString(raw[@"identifier"],256);if(!identifier.length)continue;
        NSMutableDictionary *item=[NSMutableDictionary dictionaryWithObject:identifier forKey:@"identifier"];
        NSString *name=WPAdvisorSafeString(raw[@"displayName"],80),*detail=WPAdvisorSafeString(raw[@"detail"],120);
        if(name.length)item[@"displayName"]=name;if(detail.length)item[@"detail"]=detail;
        if([raw[@"createdAt"] isKindOfClass:NSDate.class])item[@"createdAt"]=raw[@"createdAt"];
        if([raw[@"unread"] isKindOfClass:NSNumber.class])item[@"unread"]=raw[@"unread"];
        [validated addObject:item];
        if(validated.count==100)break;
    }
    self.records=validated;if(self.isViewLoaded)[self.tableView reloadData];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{return MAX((NSUInteger)1,self.records.count);}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    if(!self.records.count){cell.textLabel.text=@"暂无记录";cell.textLabel.textColor=UIColor.secondaryLabelColor;cell.selectionStyle=UITableViewCellSelectionStyleNone;return cell;}
    NSDictionary *record=self.records[(NSUInteger)indexPath.row];NSString *name=WPAdvisorSafeString(record[@"displayName"],80);
    cell.textLabel.text=name.length?name:@"联系人";NSString *detail=WPAdvisorSafeString(record[@"detail"],120);
    if(!detail.length && [record[@"createdAt"] isKindOfClass:NSDate.class])
        detail=[NSDateFormatter localizedStringFromDate:record[@"createdAt"] dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle];
    if([record[@"unread"] respondsToSelector:@selector(boolValue)] && [record[@"unread"] boolValue])detail=detail.length?[@"新结果 · " stringByAppendingString:detail]:@"新结果";
    cell.detailTextLabel.text=detail;cell.detailTextLabel.textColor=UIColor.secondaryLabelColor;cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    cell.accessibilityIdentifier=[@"WPAdvisorHistory-" stringByAppendingString:record[@"identifier"]];return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];if((NSUInteger)indexPath.row>=self.records.count)return;
    NSString *identifier=self.records[(NSUInteger)indexPath.row][@"identifier"];if(self.onSelect)self.onSelect(identifier);
}
- (void)confirmClear {
    __weak typeof(self) weakSelf=self;
    WPChoiceItem *clear=[WPChoiceItem itemWithTitle:@"确认清除记录" icon:@"trash" destructive:YES handler:^{if(weakSelf.onClear)weakSelf.onClear();}];
    WPPresentChoiceSheet(self,@"清除后无法恢复",@[clear]);
}
@end
