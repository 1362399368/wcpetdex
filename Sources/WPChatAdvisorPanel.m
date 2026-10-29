#import "WPChatAdvisorPanel.h"
#import "WPChatAdvisor.h"
#import "WPTheme.h"
#import <objc/runtime.h>

static const CGFloat WPCAPPadding=16,WPCAPHeader=46;

@interface WPChatAdvisorPanel ()
@property(nonatomic) UILabel *titleLabel;
@property(nonatomic) UIButton *retryButton;
@property(nonatomic) UIScrollView *scroll;
@property(nonatomic) UIStackView *stack;
@property(nonatomic) CGRect lastBounds;
@end

@implementation WPChatAdvisorPanel
- (instancetype)initWithFrame:(CGRect)frame {
    if(!(self=[super initWithFrame:frame]))return nil;
    self.backgroundColor=WPThemeCard();
    self.layer.cornerRadius=18;self.layer.cornerCurve=kCACornerCurveContinuous;
    self.layer.shadowColor=UIColor.blackColor.CGColor;self.layer.shadowOpacity=.18;self.layer.shadowRadius=14;self.layer.shadowOffset=CGSizeMake(0,4);
    self.layer.borderWidth=1/UIScreen.mainScreen.scale;self.layer.borderColor=[UIColor.separatorColor CGColor];
    self.accessibilityIdentifier=@"WPChatAdvisorPanel";
    self.titleLabel=WPThemeLabel(@"聊天参谋",15,UIFontWeightSemibold,WPThemePrimaryText());
    [self addSubview:self.titleLabel];
    self.retryButton=[self iconButton:@"arrow.clockwise" label:@"重新分析" action:@selector(retry)];
    UIButton *close=[self iconButton:@"xmark" label:@"关闭聊天参谋" action:@selector(close)];
    close.tag=1;
    self.scroll=[UIScrollView new];self.scroll.alwaysBounceVertical=NO;self.scroll.showsHorizontalScrollIndicator=NO;
    [self addSubview:self.scroll];
    self.stack=[UIStackView new];self.stack.axis=UILayoutConstraintAxisVertical;self.stack.spacing=6;self.stack.alignment=UIStackViewAlignmentFill;
    self.stack.translatesAutoresizingMaskIntoConstraints=NO;[self.scroll addSubview:self.stack];
    [NSLayoutConstraint activateConstraints:@[
        [self.stack.leadingAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.leadingAnchor constant:WPCAPPadding],
        [self.stack.trailingAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.trailingAnchor constant:-WPCAPPadding],
        [self.stack.topAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.topAnchor],
        [self.stack.bottomAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.bottomAnchor constant:-WPCAPPadding],
        [self.stack.widthAnchor constraintEqualToAnchor:self.scroll.frameLayoutGuide.widthAnchor constant:-2*WPCAPPadding]]];
    return self;
}
- (UIButton *)iconButton:(NSString *)symbol label:(NSString *)label action:(SEL)action {
    UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];
    [button setImage:[UIImage systemImageNamed:symbol withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightSemibold]] forState:UIControlStateNormal];
    button.tintColor=WPThemeSecondaryText();button.accessibilityLabel=label;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:button];return button;
}
- (void)retry {if(self.onRetry)self.onRetry();}
- (void)close {if(self.onClose)self.onClose();}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width=self.bounds.size.width;
    UIButton *close=nil;for(UIView *view in self.subviews)if(view.tag==1 && [view isKindOfClass:UIButton.class])close=(id)view;
    close.frame=CGRectMake(width-44,2,42,42);
    self.retryButton.frame=CGRectMake(width-84,2,42,42);
    self.titleLabel.frame=CGRectMake(WPCAPPadding,0,MAX(0,width-WPCAPPadding-88),WPCAPHeader);
    self.scroll.frame=CGRectMake(0,WPCAPHeader,width,MAX(0,self.bounds.size.height-WPCAPHeader));
}

#pragma mark Content

- (void)resetContent {
    for(UIView *view in self.stack.arrangedSubviews){[self.stack removeArrangedSubview:view];[view removeFromSuperview];}
    WPChatAdvisorPreset *preset=WPChatAdvisor.currentPreset;
    self.titleLabel.text=[NSString stringWithFormat:@"聊天参谋 · %@",preset.title];
}
- (UILabel *)addText:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color {
    UILabel *label=WPThemeLabel(text,size,weight,color);label.numberOfLines=0;[self.stack addArrangedSubview:label];return label;
}
- (void)addSection:(NSString *)title {
    UILabel *label=[self addText:title size:13 weight:UIFontWeightMedium color:WPThemeSecondaryText()];
    NSUInteger index=[self.stack.arrangedSubviews indexOfObject:label];
    if(index>0)[self.stack setCustomSpacing:14 afterView:self.stack.arrangedSubviews[index-1]];
}
- (void)showLoadingWithLineCount:(NSUInteger)count {
    [self resetContent];self.retryButton.enabled=NO;
    UIActivityIndicatorView *spinner=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];[spinner startAnimating];
    UILabel *label=WPThemeLabel([NSString stringWithFormat:@"正在分析最近 %lu 条消息…",(unsigned long)count],14,UIFontWeightRegular,WPThemeSecondaryText());label.numberOfLines=0;
    UIStackView *row=[[UIStackView alloc] initWithArrangedSubviews:@[spinner,label]];row.spacing=8;row.alignment=UIStackViewAlignmentCenter;
    [self.stack addArrangedSubview:row];[self relayout];
}
- (void)showError:(NSString *)message {
    [self resetContent];self.retryButton.enabled=YES;
    [self addText:message size:14 weight:UIFontWeightRegular color:UIColor.systemOrangeColor];
    UIButton *retry=[self replyButton:@"重新分析" index:0];
    [retry removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
    [retry addTarget:self action:@selector(retry) forControlEvents:UIControlEventTouchUpInside];
    [self.stack addArrangedSubview:retry];[self.stack setCustomSpacing:12 afterView:self.stack.arrangedSubviews[0]];
    [self relayout];
}
- (void)showAdvice:(WPChatAdvice *)advice lineCount:(NSUInteger)count {
    [self resetContent];self.retryButton.enabled=YES;
    [self addText:@"- 意图 -" size:14 weight:UIFontWeightSemibold color:WPThemePrimaryText()];
    if(advice.summary.length)[self addText:advice.summary size:15 weight:UIFontWeightMedium color:WPThemePrimaryText()];
    if(advice.strategy.length){
        UILabel *strategy=[self addText:[NSString stringWithFormat:@"本轮策略：%@",advice.strategy] size:14 weight:UIFontWeightSemibold color:UIColor.systemGreenColor];
        [self.stack setCustomSpacing:14 afterView:self.stack.arrangedSubviews[[self.stack.arrangedSubviews indexOfObject:strategy]-1]];
    }
    if(advice.intents.count){
        [self addSection:@"当前真实意图"];
        for(NSDictionary *intent in advice.intents)
            [self addText:[NSString stringWithFormat:@"· %@：%@%%",intent[@"label"],intent[@"percent"]] size:14 weight:UIFontWeightRegular color:WPThemePrimaryText()];
    }
    NSMutableArray *risk=[NSMutableArray new];
    if(advice.riskLevel>=0)[risk addObject:[NSString stringWithFormat:@"危险等级：%ld/10%@",(long)advice.riskLevel,advice.riskLabel.length?[NSString stringWithFormat:@"（%@）",advice.riskLabel]:@""]];
    if(advice.replyTiming.length)[risk addObject:[NSString stringWithFormat:@"是否立刻回复：%@",advice.replyTiming]];
    if(risk.count){
        [self addSection:risk[0]];
        if(risk.count>1)[self addText:risk[1] size:13 weight:UIFontWeightMedium color:WPThemeSecondaryText()];
    }
    if(advice.actions.count){
        [self addSection:@"最佳动作"];
        for(NSString *action in advice.actions)[self addText:[@"· " stringByAppendingString:action] size:14 weight:UIFontWeightRegular color:WPThemePrimaryText()];
    }
    [self addSection:@"建议回复"];
    [advice.replies enumerateObjectsUsingBlock:^(NSString *reply,NSUInteger index,__unused BOOL *stop){[self.stack addArrangedSubview:[self replyButton:reply index:index+1]];}];
    UILabel *footer=[self addText:[NSString stringWithFormat:@"基于最近 %lu 条消息 · 点按填入，长按直接发送",(unsigned long)count] size:11 weight:UIFontWeightRegular color:WPThemeSecondaryText()];
    [self.stack setCustomSpacing:12 afterView:self.stack.arrangedSubviews[[self.stack.arrangedSubviews indexOfObject:footer]-1]];
    [self relayout];
}
- (UIButton *)replyButton:(NSString *)reply index:(NSUInteger)index {
    UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *configuration=UIButtonConfiguration.filledButtonConfiguration;
    configuration.baseBackgroundColor=WPThemeElevated();configuration.baseForegroundColor=UIColor.systemBlueColor;
    configuration.contentInsets=NSDirectionalEdgeInsetsMake(10,12,10,12);
    configuration.titleAlignment=UIButtonConfigurationTitleAlignmentLeading;
    configuration.attributedTitle=[[NSAttributedString alloc] initWithString:index?[NSString stringWithFormat:@"%lu. %@",(unsigned long)index,reply]:reply
                                                                  attributes:@{NSFontAttributeName:[UIFont systemFontOfSize:15 weight:UIFontWeightMedium]}];
    button.configuration=configuration;
    button.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeading;
    button.titleLabel.numberOfLines=0;
    button.accessibilityIdentifier=[NSString stringWithFormat:@"WPChatAdvisorReply%lu",(unsigned long)index];
    __weak typeof(self) weakSelf=self;
    [button addAction:[UIAction actionWithHandler:^(__unused UIAction *action){if(weakSelf.onPickReply)weakSelf.onPickReply(reply);}] forControlEvents:UIControlEventTouchUpInside];
    UILongPressGestureRecognizer *press=[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(sendReply:)];
    press.cancelsTouchesInView=YES;
    [button addGestureRecognizer:press];
    objc_setAssociatedObject(press,@selector(sendReply:),reply,OBJC_ASSOCIATION_COPY_NONATOMIC);
    return button;
}
- (void)sendReply:(UILongPressGestureRecognizer *)press {
    if(press.state!=UIGestureRecognizerStateBegan)return;
    NSString *reply=objc_getAssociatedObject(press,@selector(sendReply:));
    if(!reply.length)return;
    if(self.onSendReply)self.onSendReply(reply);
}

#pragma mark Layout

- (void)relayout {if(!CGRectIsEmpty(self.lastBounds))[self layoutInBounds:self.lastBounds];}
- (void)layoutInBounds:(CGRect)bounds {
    self.lastBounds=bounds;
    CGFloat width=MIN(400,MAX(200,bounds.size.width-24));
    CGSize content=[self.stack systemLayoutSizeFittingSize:CGSizeMake(width-2*WPCAPPadding,0) withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    // Leave room for WeChat's own input bar below the card.
    CGFloat bottomGap=64,available=MAX(120,bounds.size.height-bottomGap-8);
    CGFloat height=MIN(MIN(available,bounds.size.height*.72),WPCAPHeader+content.height+WPCAPPadding);
    self.frame=CGRectMake(CGRectGetMidX(bounds)-width/2,CGRectGetMaxY(bounds)-bottomGap-height,width,height);
    [self setNeedsLayout];[self layoutIfNeeded];
    self.scroll.contentSize=CGSizeMake(width,content.height+WPCAPPadding);
}
@end
