#import "WPRadialMenu.h"
#import "WPCommon.h"
#import "WPMenuIcons.h"
#import "WPMenuConfiguration.h"
#import "WPSharedChatAvatar.h"
#import "WPPartnerContact.h"
#import "WPEdition.h"
#import <QuartzCore/QuartzCore.h>
#import <math.h>
#import <float.h>

@interface WPMenuActionButton : UIButton
@property (nonatomic, copy) NSString *actionIdentifier;
@property (nonatomic, copy) NSString *actionExplanation;
@property (nonatomic, strong) UIImageView *symbolView;
@property (nonatomic) BOOL menuSelected;
@property (nonatomic,strong) WPSharedChatAvatarRequest *avatarRequest;
@property (nonatomic,copy) NSString *representedUsername;
@property (nonatomic, readonly) BOOL sendDisabled;
- (instancetype)initWithAction:(NSString *)action title:(NSString *)title symbol:(NSString *)symbol;
- (void)setMenuSelected:(BOOL)selected;
@end

@implementation WPMenuActionButton
// Stealth keeps the partner from seeing activity, so sending is unavailable.
- (BOOL)sendDisabled{return WP_FEATURE_STEALTH && WPCanUsePrivateFeatures() && [WPPreferences() boolForKey:@"stealthEnabled"] && [@[@"miss",@"anger"] containsObject:self.actionIdentifier];}
- (UIColor *)restingTint{
    if(self.sendDisabled)return UIColor.blackColor;
    if([self.actionIdentifier isEqualToString:@"miss"])return UIColor.systemPinkColor;
    if([self.actionIdentifier isEqualToString:@"anger"])return UIColor.systemGrayColor;
    return nil;
}

- (instancetype)initWithAction:(NSString *)action title:(NSString *)title symbol:(NSString *)symbol {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _actionIdentifier = [action copy];
    _actionExplanation = @{@"miss":@"松手告诉对方「想你了」", @"anger":@"松手告诉对方「生气了」", @"moments":@"松手进入朋友圈", @"quickChat":@"松手打开快捷聊天", @"settings":@"松手打开设置", @"read":@"松手将所有会话标为已读", @"advisor":@"松手选择聊天场景", @"advisorDirect":@"松手使用固定预设分析", @"advisorHistory":@"松手打开参谋记录", @"contact1":@"松手打开快捷联系人 1", @"contact2":@"松手打开快捷联系人 2", @"contact3":@"松手打开快捷联系人 3"}[action] ?: title;
    self.accessibilityLabel = title;
    self.accessibilityHint = @{@"miss":@"向对方发送想你了互动", @"anger":@"向对方发送生气了互动", @"moments":@"进入朋友圈", @"quickChat":@"打开快捷聊天", @"settings":@"打开桌宠设置", @"read":@"将所有会话标为已读", @"advisor":@"分析当前聊天并给出建议回复"}[action] ?: title;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    self.isAccessibilityElement = YES;
    self.backgroundColor = UIColor.clearColor;
    self.opaque = NO;
    self.layer.shadowOpacity = 0;
    self.layer.borderWidth = 0;

    UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:23 weight:UIImageSymbolWeightSemibold];
    _symbolView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol withConfiguration:configuration]];
    if([action isEqualToString:@"moments"])_symbolView.image=WPMomentsMenuIcon();
    if([action isEqualToString:@"advisor"])_symbolView.image=WPAdvisorMenuIcon();
    if([action isEqualToString:@"anger"])_symbolView.image=WPBrokenHeartMenuIcon();
    _symbolView.tintColor = [self restingTint] ?: UIColor.labelColor;
    _symbolView.contentMode = UIViewContentModeScaleAspectFit;
    _symbolView.userInteractionEnabled = NO;
    _symbolView.isAccessibilityElement = NO;
    [self addSubview:_symbolView];

    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = CGRectGetWidth(self.bounds), height = CGRectGetHeight(self.bounds);
    CGFloat iconSize = fmin(34, fmin(width, height) - 12);
    _symbolView.frame = CGRectMake((width - iconSize) / 2, (height - iconSize) / 2, iconSize, iconSize);
    if(_symbolView.clipsToBounds)_symbolView.layer.cornerRadius=iconSize/2;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    self.layer.borderWidth = 0;
}

- (void)setMenuSelected:(BOOL)selected {
    if(self.sendDisabled)selected=NO;
    _menuSelected = selected;
    self.backgroundColor = UIColor.clearColor;
    self.layer.borderWidth = 0;
    _symbolView.tintColor = [self restingTint] ?: (selected ? UIColor.systemBlueColor : UIColor.labelColor);
    _symbolView.transform = selected ? CGAffineTransformMakeScale(1.18, 1.18) : CGAffineTransformIdentity;
    self.accessibilityTraits = UIAccessibilityTraitButton | (selected ? UIAccessibilityTraitSelected : 0) | (self.sendDisabled ? UIAccessibilityTraitNotEnabled : 0);
}

@end

@interface WPRadialMenuView ()
@property (nonatomic, strong) NSArray<WPMenuActionButton *> *allButtons;
@property (nonatomic, strong) NSArray<WPMenuActionButton *> *actionButtons;
@property (nonatomic, strong, nullable) WPMenuActionButton *hoveredButton;
@property (nonatomic, readwrite, getter=isShowing) BOOL showing;
@property (nonatomic) BOOL didFire;
@property (nonatomic, strong) UILabel *hintLabel;
@property (nonatomic) CGRect menuSafeBounds;
@property (nonatomic, readwrite) CGFloat requestedRadius;
@property (nonatomic, readwrite) CGFloat effectiveRadius;
@property (nonatomic, readwrite, getter=isRadiusLimited) BOOL radiusLimited;
@property (nonatomic) NSInteger inwardSide;
@end

@implementation WPRadialMenuView
- (BOOL)hasSelection { return _hoveredButton != nil; }

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = UIColor.clearColor;
    self.opaque = NO;
    self.hidden = YES;
    self.isAccessibilityElement = NO;
    self.accessibilityViewIsModal = YES;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    NSArray *couple = WP_EDITION_COUPLE ? @[
        [[WPMenuActionButton alloc] initWithAction:@"miss" title:@"想你了" symbol:@"heart.fill"],
        [[WPMenuActionButton alloc] initWithAction:@"anger" title:@"生气了" symbol:@"heart.slash.fill"]] : @[];
    _allButtons = [couple arrayByAddingObjectsFromArray:@[
        [[WPMenuActionButton alloc] initWithAction:@"moments" title:@"朋友圈" symbol:@"camera.fill"],
        [[WPMenuActionButton alloc] initWithAction:@"quickChat" title:@"快捷聊天" symbol:@"bubble.left.and.bubble.right.fill"],
        [[WPMenuActionButton alloc] initWithAction:@"settings" title:@"设置" symbol:@"gearshape.fill"],
        [[WPMenuActionButton alloc] initWithAction:@"read" title:@"全部已读" symbol:@"checkmark.circle.fill"],
        [[WPMenuActionButton alloc] initWithAction:@"advisor" title:@"参谋聊天" symbol:@"sparkles"],
        [[WPMenuActionButton alloc] initWithAction:@"advisorDirect" title:@"直接参谋" symbol:@"bolt.fill"],
        [[WPMenuActionButton alloc] initWithAction:@"advisorHistory" title:@"参谋记录" symbol:@"clock.arrow.circlepath"],
        [[WPMenuActionButton alloc] initWithAction:@"contact1" title:@"快捷联系人 1" symbol:@"person.circle"],
        [[WPMenuActionButton alloc] initWithAction:@"contact2" title:@"快捷联系人 2" symbol:@"person.circle"],
        [[WPMenuActionButton alloc] initWithAction:@"contact3" title:@"快捷联系人 3" symbol:@"person.circle"]]
    ];
    for (WPMenuActionButton *button in _allButtons) {
        [button addTarget:self action:@selector(buttonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:button];
    }
    [self updateActionButtons];
    _hintLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _hintLabel.backgroundColor = UIColor.clearColor;
    _hintLabel.textColor = UIColor.labelColor;
    _hintLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _hintLabel.textAlignment = NSTextAlignmentCenter;
    _hintLabel.numberOfLines = 2;
    _hintLabel.userInteractionEnabled = NO;
    _hintLabel.hidden = YES;
    [self addSubview:_hintLabel];
    return self;
}

// WP_GEOMETRY_BEGIN — pure geometry, also compiled by the offline contract test.
static CGFloat WPClamp(CGFloat value, CGFloat minimum, CGFloat maximum) {
    return fmax(minimum, fmin(maximum, value));
}

#define WP_MENU_MAX_ITEMS 10
typedef struct {
    CGPoint centers[WP_MENU_MAX_ITEMS];
    NSUInteger count;
    CGPoint origin;
    CGFloat targetSize;
    CGFloat requestedRadius;
    CGFloat effectiveRadius;
    CGFloat direction;
    BOOL limited;
    BOOL fan;
    BOOL valid;
} WPFanLayout;

static NSInteger WPInwardSide(CGPoint anchor, CGRect bounds, NSInteger previous) {
    CGFloat middle = CGRectGetMidX(bounds);
    CGFloat hysteresis = fmin(36, CGRectGetWidth(bounds) * .12);
    if (previous && fabs(anchor.x - middle) <= hysteresis) return previous;
    return anchor.x <= middle ? 1 : -1;
}

static CGFloat WPFanMaximumRadius(CGPoint anchor, CGRect centers, CGFloat shiftLimit, const CGPoint *unit, NSUInteger count) {
    CGFloat minX = unit[0].x, maxX = unit[0].x, minY = unit[0].y, maxY = unit[0].y;
    for (NSUInteger i = 1; i < count; i++) {
        minX = fmin(minX, unit[i].x); maxX = fmax(maxX, unit[i].x);
        minY = fmin(minY, unit[i].y); maxY = fmax(maxY, unit[i].y);
    }
    CGFloat maximum = fmin(CGRectGetWidth(centers) / (maxX - minX), CGRectGetHeight(centers) / (maxY - minY));
    if (minX < -1e-8) maximum = fmin(maximum, (anchor.x + shiftLimit - CGRectGetMinX(centers)) / -minX);
    if (maxX > 1e-8) maximum = fmin(maximum, (CGRectGetMaxX(centers) - anchor.x + shiftLimit) / maxX);
    if (minY < -1e-8) maximum = fmin(maximum, (anchor.y + shiftLimit - CGRectGetMinY(centers)) / -minY);
    if (maxY > 1e-8) maximum = fmin(maximum, (CGRectGetMaxY(centers) - anchor.y + shiftLimit) / maxY);
    return fmax(0, maximum);
}

static WPFanLayout WPComputeFanLayout(CGPoint anchor, CGRect safe, CGFloat scale, NSInteger side, NSUInteger count) {
    WPFanLayout result = {0};
    count = (NSUInteger)WPClamp(count, 1, WP_MENU_MAX_ITEMS);
    result.count = count;
    result.requestedRadius = 80 * WPClamp(isfinite(scale) ? scale : 1, .6, 4);
    if (CGRectIsEmpty(safe) || !isfinite(anchor.x) || !isfinite(anchor.y)) return result;
    // Direction depends only on the pet's region, never on scale or an optimum
    // picked from competing layouts. The side has a small center hysteresis.
    CGFloat verticalBias = WPClamp((CGRectGetMidY(safe) - anchor.y) / fmax(1, CGRectGetHeight(safe) / 2), -1, 1);
    result.direction = side > 0 ? verticalBias * M_PI_4 : M_PI - verticalBias * M_PI_4;
    // A user may keep just one action. Center its touch target inside the
    // safe area rather than dividing by (count - 1) for the usual fan.
    if(count==1){
        CGFloat target=CGRectGetWidth(safe)>=52 && CGRectGetHeight(safe)>=52?52:44;
        if(CGRectGetWidth(safe)<target || CGRectGetHeight(safe)<target)return result;
        CGRect centers=CGRectInset(safe,target/2,target/2);
        CGFloat x=WPClamp(anchor.x+cos(result.direction)*result.requestedRadius,CGRectGetMinX(centers),CGRectGetMaxX(centers));
        CGFloat y=WPClamp(anchor.y+sin(result.direction)*result.requestedRadius,CGRectGetMinY(centers),CGRectGetMaxY(centers));
        result.origin=anchor;result.centers[0]=CGPointMake(x,y);result.targetSize=target;
        result.effectiveRadius=hypot(x-anchor.x,y-anchor.y);
        result.limited=fabs(result.effectiveRadius-result.requestedRadius)>.05;
        result.fan=result.valid=YES;return result;
    }
    // Items share one half circle facing inward; the fifth item narrows the
    // spacing, and the radius minimum below grows to keep targets apart.
    CGPoint unit[WP_MENU_MAX_ITEMS];
    CGFloat minimumAxisSpacing = CGFLOAT_MAX;
    for (NSUInteger i = 0; i < count; i++) {
        CGFloat angle = result.direction - M_PI_2 + i * M_PI / (count - 1);
        unit[i] = CGPointMake(cos(angle), sin(angle));
        for (NSUInteger j = 0; j < i; j++) {
            CGFloat spacing = fmax(fabs(unit[i].x - unit[j].x), fabs(unit[i].y - unit[j].y));
            minimumAxisSpacing = fmin(minimumAxisSpacing, spacing);
        }
    }
    // A single requested radius is continuously clamped. There are no radius
    // buckets, orientation searches, or enlarged corner-specific radius jumps.
    const CGFloat shiftLimit = 52;
    for (NSUInteger attempt = 0; attempt < 2; attempt++) {
        CGFloat target = attempt == 0 ? 52 : 44;
        if (CGRectGetWidth(safe) < target || CGRectGetHeight(safe) < target) continue;
        CGRect centers = CGRectInset(safe, target / 2, target / 2);
        CGFloat minimum = (target + 2) / minimumAxisSpacing;
        CGFloat maximum = WPFanMaximumRadius(anchor, centers, shiftLimit, unit, count);
        if (maximum + .001 < minimum) continue;
        CGFloat radius = WPClamp(result.requestedRadius, minimum, maximum);
        CGFloat lowX = -shiftLimit, highX = shiftLimit, lowY = -shiftLimit, highY = shiftLimit;
        for (NSUInteger i = 0; i < count; i++) {
            lowX = fmax(lowX, CGRectGetMinX(centers) - anchor.x - radius * unit[i].x);
            highX = fmin(highX, CGRectGetMaxX(centers) - anchor.x - radius * unit[i].x);
            lowY = fmax(lowY, CGRectGetMinY(centers) - anchor.y - radius * unit[i].y);
            highY = fmin(highY, CGRectGetMaxY(centers) - anchor.y - radius * unit[i].y);
        }
        CGFloat shiftX = WPClamp(0, lowX, highX), shiftY = WPClamp(0, lowY, highY);
        result.origin = CGPointMake(anchor.x + shiftX, anchor.y + shiftY);
        for (NSUInteger i = 0; i < count; i++) result.centers[i] = CGPointMake(result.origin.x + radius * unit[i].x, result.origin.y + radius * unit[i].y);
        result.targetSize = target;
        result.effectiveRadius = radius;
        result.limited = fabs(radius - result.requestedRadius) > .05;
        result.fan = result.valid = YES;
        return result;
    }
    // A very short keyboard area may only fit one row. Keep full touch targets
    // inside the supplied bounds instead of silently drawing outside the screen.
    for (NSUInteger attempt = 0; attempt < 2; attempt++) {
        CGFloat target = attempt == 0 ? 52 : 44, gap = 6;
        NSUInteger columns = 0, rows = 0, half = (count + 1) / 2;
        if (CGRectGetWidth(safe) >= target * half + gap * (half - 1) && CGRectGetHeight(safe) >= target * 2 + gap) { columns = half; rows = 2; }
        else if (CGRectGetWidth(safe) >= target * count + gap * (count - 1) && CGRectGetHeight(safe) >= target) { columns = count; rows = 1; }
        else if (CGRectGetWidth(safe) >= target && CGRectGetHeight(safe) >= target * count + gap * (count - 1)) { columns = 1; rows = count; }
        if (!columns) continue;
        CGFloat width = columns * target + (columns - 1) * gap, height = rows * target + (rows - 1) * gap;
        CGFloat left = WPClamp(anchor.x + side * (target / 2 + width / 2 + 8) - width / 2, CGRectGetMinX(safe), CGRectGetMaxX(safe) - width);
        CGFloat top = WPClamp(anchor.y - height / 2, CGRectGetMinY(safe), CGRectGetMaxY(safe) - height);
        for (NSUInteger i = 0; i < count; i++) result.centers[i] = CGPointMake(left + target / 2 + (i % columns) * (target + gap), top + target / 2 + (i / columns) * (target + gap));
        result.origin = anchor;
        result.targetSize = target;
        result.effectiveRadius = 0;
        for (NSUInteger i = 0; i < count; i++) result.effectiveRadius = fmax(result.effectiveRadius, hypot(result.centers[i].x - anchor.x, result.centers[i].y - anchor.y));
        result.limited = result.valid = YES;
        return result;
    }
    return result;
}
// WP_GEOMETRY_END

- (void)layoutAroundPoint:(CGPoint)anchor inBounds:(CGRect)bounds {
    CGRect available = CGRectIntersection(self.bounds, bounds);
    if (CGRectIsNull(available) || CGRectIsEmpty(available)) available = self.bounds;
    CGRect padded = CGRectInset(available, 8, 8);
    if (CGRectGetWidth(padded) >= 44 && CGRectGetHeight(padded) >= 44) available = padded;
    self.menuSafeBounds = available;
    self.inwardSide = WPInwardSide(anchor, available, self.inwardSide);
    id configured = [WPPreferences() objectForKey:@"menuScale"];
    CGFloat scale = [configured isKindOfClass:NSNumber.class] ? [configured doubleValue] : 1;
    WPFanLayout layout = WPComputeFanLayout(anchor, available, scale, self.inwardSide, _actionButtons.count);
    self.requestedRadius = layout.requestedRadius;
    self.effectiveRadius = layout.effectiveRadius;
    self.radiusLimited = layout.limited;
    if (!layout.valid) { [self cancel]; return; }
    for (NSUInteger index = 0; index < _actionButtons.count; index++) {
        CGPoint center = layout.centers[index];
        _actionButtons[index].frame = CGRectMake(center.x - layout.targetSize / 2, center.y - layout.targetSize / 2, layout.targetSize, layout.targetSize);
        [_actionButtons[index] setNeedsLayout];
    }
}

- (void)updateActionButtons {
    NSMutableArray *visible=[NSMutableArray new];
    for(WPMenuActionButton *button in _allButtons)button.hidden=YES;
    for(NSString *identifier in WPMenuEnabledActions())for(WPMenuActionButton *button in _allButtons){
        if([button.actionIdentifier isEqualToString:identifier]){button.hidden=NO;[visible addObject:button];break;}
    }
    _actionButtons = visible;
    self.accessibilityElements = _actionButtons;
}

- (void)prepareContactAvatars {
    for(WPMenuActionButton *button in _actionButtons){
        if(![@[@"contact1",@"contact2",@"contact3"] containsObject:button.actionIdentifier])continue;
        [button.avatarRequest cancel];button.avatarRequest=nil;
        NSString *username=WPMenuContactUsername(button.actionIdentifier);button.representedUsername=username;
        button.symbolView.image=[UIImage systemImageNamed:@"person.circle"];
        button.symbolView.clipsToBounds=NO;button.symbolView.contentMode=UIViewContentModeScaleAspectFit;
        NSString *displayName=username.length?[WPPartnerContact displayNameForUsername:username]:nil;
        button.actionExplanation=username.length?(displayName.length?[NSString stringWithFormat:@"松手打开%@的聊天",displayName]:@"松手打开联系人聊天"):@"请先在长按菜单设置中选择联系人";
        button.accessibilityLabel=username.length?(displayName.length?displayName:WPMenuActionTitle(button.actionIdentifier)):WPMenuActionTitle(button.actionIdentifier);
        if(!username.length)continue;
        UIImage *cached=WPCachedSharedChatAvatar(username);
        if(cached){button.symbolView.image=cached;button.symbolView.clipsToBounds=YES;button.symbolView.contentMode=UIViewContentModeScaleAspectFill;[button setNeedsLayout];continue;}
        __weak typeof(self) weakSelf=self;__weak WPMenuActionButton *weakButton=button;
        button.avatarRequest=WPRequestSharedChatAvatar(username,^(UIImage *avatar){
            WPRadialMenuView *menu=weakSelf;WPMenuActionButton *current=weakButton;
            if(!menu.isShowing || !current || ![current.representedUsername isEqualToString:username])return;
            current.avatarRequest=nil;if(!avatar)return;
            current.symbolView.image=avatar;current.symbolView.clipsToBounds=YES;current.symbolView.contentMode=UIViewContentModeScaleAspectFill;[current setNeedsLayout];
        });
    }
}

- (void)showAroundPoint:(CGPoint)point inBounds:(CGRect)bounds {
    NSAssert(NSThread.isMainThread, @"Pet menus must run on the main thread");
    [self cancel];
    [self updateActionButtons];
    if(!_actionButtons.count)return;
    _didFire = NO;
    for(WPMenuActionButton *button in _actionButtons)[button setMenuSelected:NO];
    _showing = YES;
    [self prepareContactAvatars];
    [self layoutAroundPoint:point inBounds:bounds];
    if (!_showing) return;
    self.hidden = NO;
    self.alpha = 1;
    if (!UIAccessibilityIsReduceMotionEnabled()) {
        self.alpha = 0;
        [UIView animateWithDuration:0.15 animations:^{ self.alpha = 1; }];
    }
    if (UIAccessibilityIsVoiceOverRunning()) {
        UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, _actionButtons.firstObject);
    }
}

- (void)updateFingerAtPoint:(CGPoint)point {
    if (!_showing || _didFire) return;
    WPMenuActionButton *candidate = nil;
    CGFloat nearestDistance = CGFLOAT_MAX;
    for (WPMenuActionButton *button in _actionButtons) {
        if(button.sendDisabled)continue;
        if (CGRectContainsPoint(CGRectInset(button.frame, -4, -4), point)) {
            CGFloat distance = hypot(point.x - button.center.x, point.y - button.center.y);
            if (distance < nearestDistance) { candidate = button; nearestDistance = distance; }
        }
    }
    if(candidate) {
        self.hintLabel.text = candidate.actionExplanation;
        CGRect safe = self.menuSafeBounds;
        CGFloat maximumWidth = MIN(240, CGRectGetWidth(safe));
        CGSize size = [self.hintLabel sizeThatFits:CGSizeMake(maximumWidth,60)];
        CGFloat width = MIN(maximumWidth, MAX(84,ceil(size.width)));
        CGFloat height = MIN(CGRectGetHeight(safe), MAX(24,ceil(size.height)));
        CGFloat x = WPClamp(candidate.center.x-width/2,CGRectGetMinX(safe),CGRectGetMaxX(safe)-width);
        CGFloat y = candidate.frame.origin.y-height-6;
        if(y<CGRectGetMinY(safe))y=CGRectGetMaxY(candidate.frame)+6;
        y=WPClamp(y,CGRectGetMinY(safe),CGRectGetMaxY(safe)-height);
        self.hintLabel.frame=CGRectMake(x,y,width,height);
        self.hintLabel.hidden=NO;
    } else self.hintLabel.hidden=YES;
    if (candidate == _hoveredButton) return;
    [_hoveredButton setMenuSelected:NO];
    _hoveredButton = candidate;
    if (!candidate) return;
    [candidate setMenuSelected:YES];
    UISelectionFeedbackGenerator *feedback = [[UISelectionFeedbackGenerator alloc] init];
    [feedback selectionChanged];
}

- (void)buttonTapped:(WPMenuActionButton *)button {
    [self fireButton:button];
}

- (void)fireButton:(WPMenuActionButton *)button {
    if (!_showing || _didFire) return;
    _didFire = YES;
    NSString *action = [button.actionIdentifier copy];
    void (^handler)(NSString *) = [self.actionHandler copy];
    [self dismiss];
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [feedback impactOccurred];
    if (handler) handler(action);
}

- (void)finishTracking {
    if (_showing && !_didFire && _hoveredButton) [self fireButton:_hoveredButton];
    else [self dismiss];
}

- (void)cancel {
    [self dismiss];
}

- (void)dismiss {
    _showing = NO;
    for(WPMenuActionButton *button in _allButtons){
        [button.avatarRequest cancel];button.avatarRequest=nil;button.representedUsername=nil;
        if([@[@"contact1",@"contact2",@"contact3"] containsObject:button.actionIdentifier]){
            button.symbolView.image=[UIImage systemImageNamed:@"person.circle"];button.symbolView.clipsToBounds=NO;
            button.symbolView.contentMode=UIViewContentModeScaleAspectFit;
        }
    }
    [_hoveredButton setMenuSelected:NO];
    _hoveredButton = nil;
    self.hintLabel.hidden = YES;
    [self.layer removeAllAnimations];
    self.hidden = YES;
    self.alpha = 1;
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if (!_showing || self.hidden || self.alpha <= 0.01) return NO;
    for (WPMenuActionButton *button in _actionButtons) {
        if ([button pointInside:[self convertPoint:point toView:button] withEvent:event]) return YES;
    }
    return NO;
}

@end
