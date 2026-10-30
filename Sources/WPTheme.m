#import "WPTheme.h"

const CGFloat WPThemeCardRadius=18;
static UIColor *WPRGB(CGFloat r,CGFloat g,CGFloat b){return [UIColor colorWithRed:r/255 green:g/255 blue:b/255 alpha:1];}
UIColor *WPThemeBackground(void){return UIColor.systemGroupedBackgroundColor;}
UIColor *WPThemeCard(void){return UIColor.secondarySystemGroupedBackgroundColor;}
UIColor *WPThemeElevated(void){return UIColor.tertiarySystemGroupedBackgroundColor;}
UIColor *WPThemePrimaryText(void){return UIColor.labelColor;}
UIColor *WPThemeSecondaryText(void){return UIColor.secondaryLabelColor;}
UIColor *WPThemeOutgoingBubble(void){
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *trait){
        return trait.userInterfaceStyle==UIUserInterfaceStyleDark?WPRGB(28,51,84):WPRGB(221,236,255);
    }];
}

void WPApplyThemeToNavigation(UINavigationController *navigation){
    UINavigationBarAppearance *appearance=[UINavigationBarAppearance new];[appearance configureWithOpaqueBackground];
    // UINavigationBarAppearance caches rendered colors, so resolve them for
    // this controller and rebuild it when the appearance changes.
    appearance.backgroundColor=[WPThemeBackground() resolvedColorWithTraitCollection:navigation.traitCollection];appearance.shadowColor=UIColor.clearColor;
    appearance.titleTextAttributes=@{NSForegroundColorAttributeName:[WPThemePrimaryText() resolvedColorWithTraitCollection:navigation.traitCollection],NSFontAttributeName:[UIFont systemFontOfSize:18 weight:UIFontWeightSemibold]};
    navigation.navigationBar.standardAppearance=appearance;navigation.navigationBar.scrollEdgeAppearance=appearance;navigation.navigationBar.compactAppearance=appearance;
    navigation.navigationBar.tintColor=UIColor.systemBlueColor;
    navigation.view.backgroundColor=WPThemeBackground();
}
@implementation WPAdaptiveNavigationController
- (void)viewDidLoad{[super viewDidLoad];WPApplyThemeToNavigation(self);self.interactivePopGestureRecognizer.enabled=YES;}
- (void)pushViewController:(UIViewController *)viewController animated:(BOOL)animated {
    if(self.viewControllers.count && self.willPushChild)self.willPushChild();
    [super pushViewController:viewController animated:animated];
}
- (UIViewController *)popViewControllerAnimated:(BOOL)animated {
    UIViewController *result=[super popViewControllerAnimated:animated];
    if(result && !animated && self.didPopWithoutAnimation)self.didPopWithoutAnimation();
    return result;
}
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection{
    [super traitCollectionDidChange:previousTraitCollection];
    if(!previousTraitCollection || [self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection])WPApplyThemeToNavigation(self);
}
@end
UIView *WPThemeIconTile(UIImage *image,UIColor *tint,CGFloat side){
    UIView *tile=[UIView new];tile.backgroundColor=WPThemeElevated();tile.layer.cornerRadius=side*.3;tile.layer.cornerCurve=kCACornerCurveContinuous;
    tile.translatesAutoresizingMaskIntoConstraints=NO;
    UIImageView *icon=[[UIImageView alloc] initWithImage:image];icon.tintColor=tint;icon.contentMode=UIViewContentModeScaleAspectFit;icon.translatesAutoresizingMaskIntoConstraints=NO;
    [tile addSubview:icon];
    [NSLayoutConstraint activateConstraints:@[[tile.widthAnchor constraintEqualToConstant:side],[tile.heightAnchor constraintEqualToConstant:side],
        [icon.centerXAnchor constraintEqualToAnchor:tile.centerXAnchor],[icon.centerYAnchor constraintEqualToAnchor:tile.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:side*.5],[icon.heightAnchor constraintEqualToConstant:side*.5]]];
    return tile;
}
@interface WPPillLabel : UILabel
@end
@implementation WPPillLabel
- (CGSize)intrinsicContentSize{CGSize size=[super intrinsicContentSize];return CGSizeMake(size.width+16,MAX(24,size.height+8));}
@end
UILabel *WPThemePill(NSString *text,UIColor *color){
    UILabel *pill=[WPPillLabel new];pill.text=text;pill.textColor=WPThemePrimaryText();pill.font=[UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    pill.textAlignment=NSTextAlignmentCenter;pill.backgroundColor=[color colorWithAlphaComponent:.14];pill.layer.cornerRadius=8;pill.clipsToBounds=YES;
    [pill setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    return pill;
}
UILabel *WPThemeLabel(NSString *text,CGFloat size,UIFontWeight weight,UIColor *color){
    UILabel *label=[UILabel new];label.text=text;label.font=[UIFont systemFontOfSize:size weight:weight];label.textColor=color;label.numberOfLines=0;
    label.adjustsFontForContentSizeCategory=YES;return label;
}

@interface WPCardPageController ()
@property(nonatomic,readwrite) UIScrollView *scrollView;
@property(nonatomic,readwrite) UIStackView *stack;
@property(nonatomic) NSMutableArray *actionOwners;
@end
@implementation WPCardPageController
- (void)viewDidLoad{
    [super viewDidLoad];self.view.backgroundColor=WPThemeBackground();
    self.scrollView=[UIScrollView new];self.scrollView.translatesAutoresizingMaskIntoConstraints=NO;self.scrollView.alwaysBounceVertical=YES;
    self.scrollView.keyboardDismissMode=UIScrollViewKeyboardDismissModeInteractive;[self.view addSubview:self.scrollView];
    self.stack=[UIStackView new];self.stack.axis=UILayoutConstraintAxisVertical;self.stack.spacing=8;self.stack.translatesAutoresizingMaskIntoConstraints=NO;
    [self.scrollView addSubview:self.stack];
    UILayoutGuide *content=self.scrollView.contentLayoutGuide,*frame=self.scrollView.frameLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.topAnchor],[self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [content.widthAnchor constraintEqualToAnchor:frame.widthAnchor],
        [self.stack.topAnchor constraintEqualToAnchor:content.topAnchor constant:4],[self.stack.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-12],
        [self.stack.leadingAnchor constraintEqualToAnchor:frame.leadingAnchor constant:16],[self.stack.trailingAnchor constraintEqualToAnchor:frame.trailingAnchor constant:-16]]];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboard:) name:UIKeyboardWillChangeFrameNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboard:) name:UIKeyboardWillHideNotification object:nil];
    [self reloadCards];
}
- (void)dealloc{[NSNotificationCenter.defaultCenter removeObserver:self];}
- (void)keyboard:(NSNotification *)note{
    if(!self.view.window)return;
    CGRect frame=[note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect local=[self.view convertRect:frame fromCoordinateSpace:self.view.window.screen.coordinateSpace];
    CGFloat overlap=[note.name isEqual:UIKeyboardWillHideNotification]?0:MAX(0,CGRectGetMaxY(self.view.bounds)-CGRectGetMinY(local)-self.view.safeAreaInsets.bottom);
    UIEdgeInsets insets=self.scrollView.contentInset;insets.bottom=overlap;self.scrollView.contentInset=insets;self.scrollView.verticalScrollIndicatorInsets=insets;
}
- (void)buildCards{}
- (void)reloadCards{
    if(!self.isViewLoaded)return;
    for(UIView *view in self.stack.arrangedSubviews){[self.stack removeArrangedSubview:view];[view removeFromSuperview];}
    self.actionOwners=[NSMutableArray new];
    [self buildCards];
}
- (void)addSectionTitle:(NSString *)title{
    UILabel *label=WPThemeLabel(title,13,UIFontWeightSemibold,WPThemeSecondaryText());
    [label setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
    [label setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
    UIView *wrap=[UIView new];
    [wrap setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
    [wrap setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
    label.translatesAutoresizingMaskIntoConstraints=NO;[wrap addSubview:label];
    [NSLayoutConstraint activateConstraints:@[[label.leadingAnchor constraintEqualToAnchor:wrap.leadingAnchor constant:6],[label.trailingAnchor constraintEqualToAnchor:wrap.trailingAnchor constant:-6],
        [label.topAnchor constraintEqualToAnchor:wrap.topAnchor constant:4],[label.bottomAnchor constraintEqualToAnchor:wrap.bottomAnchor]]];
    [self.stack addArrangedSubview:wrap];[self.stack setCustomSpacing:4 afterView:wrap];
}
- (void)addNote:(NSString *)text{
    UILabel *label=WPThemeLabel(text,12,UIFontWeightRegular,WPThemeSecondaryText());
    UIView *wrap=[UIView new];label.translatesAutoresizingMaskIntoConstraints=NO;[wrap addSubview:label];
    [NSLayoutConstraint activateConstraints:@[[label.leadingAnchor constraintEqualToAnchor:wrap.leadingAnchor constant:6],[label.trailingAnchor constraintEqualToAnchor:wrap.trailingAnchor constant:-6],
        [label.topAnchor constraintEqualToAnchor:wrap.topAnchor constant:-4],[label.bottomAnchor constraintEqualToAnchor:wrap.bottomAnchor]]];
    [self.stack addArrangedSubview:wrap];
}
- (UIStackView *)addCard{
    UIStackView *card=[UIStackView new];card.axis=UILayoutConstraintAxisVertical;card.spacing=16;
    card.layoutMarginsRelativeArrangement=YES;card.directionalLayoutMargins=NSDirectionalEdgeInsetsMake(18,18,18,18);
    UIView *background=[UIView new];background.backgroundColor=WPThemeCard();background.layer.cornerRadius=WPThemeCardRadius;background.layer.cornerCurve=kCACornerCurveContinuous;
    background.translatesAutoresizingMaskIntoConstraints=NO;[card insertSubview:background atIndex:0];
    [NSLayoutConstraint activateConstraints:@[[background.topAnchor constraintEqualToAnchor:card.topAnchor],[background.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],
        [background.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],[background.trailingAnchor constraintEqualToAnchor:card.trailingAnchor]]];
    [self.stack addArrangedSubview:card];return card;
}
- (UIStackView *)textColumnWithTitle:(NSString *)title detail:(NSString *)detail{
    UIStackView *column=[UIStackView new];column.axis=UILayoutConstraintAxisVertical;column.spacing=4;
    UILabel *titleLabel=WPThemeLabel(title,16,UIFontWeightMedium,WPThemePrimaryText());[column addArrangedSubview:titleLabel];
    if(detail.length)[column addArrangedSubview:WPThemeLabel(detail,13,UIFontWeightRegular,WPThemeSecondaryText())];
    [column setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [column setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    return column;
}
- (UIStackView *)horizontalRow{
    UIStackView *row=[UIStackView new];row.axis=UILayoutConstraintAxisHorizontal;row.alignment=UIStackViewAlignmentCenter;row.spacing=12;
    [row.heightAnchor constraintGreaterThanOrEqualToConstant:30].active=YES;return row;
}
- (UIView *)rowWithTitle:(NSString *)title detail:(NSString *)detail actionTitle:(NSString *)actionTitle handler:(void (^)(void))handler{
    UIStackView *row=[self horizontalRow];[row addArrangedSubview:[self textColumnWithTitle:title detail:detail]];
    if(actionTitle.length){
        UIButton *action=[UIButton buttonWithType:UIButtonTypeSystem];[action setTitle:actionTitle forState:UIControlStateNormal];
        action.titleLabel.font=[UIFont systemFontOfSize:16 weight:UIFontWeightMedium];action.tintColor=UIColor.systemBlueColor;
        [action setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [action setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        if(handler)[action addAction:[UIAction actionWithHandler:^(__unused UIAction *a){handler();}] forControlEvents:UIControlEventTouchUpInside];
        action.accessibilityLabel=[NSString stringWithFormat:@"%@，%@",title,actionTitle];
        [row addArrangedSubview:action];
    } else if(handler){
        // Whole-row tap without a visible action word.
        UIButton *cover=[UIButton buttonWithType:UIButtonTypeCustom];cover.translatesAutoresizingMaskIntoConstraints=NO;cover.accessibilityLabel=title;
        [cover addAction:[UIAction actionWithHandler:^(__unused UIAction *a){handler();}] forControlEvents:UIControlEventTouchUpInside];
        UIImageView *chevron=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];chevron.tintColor=WPThemeSecondaryText();
        [chevron setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [row addArrangedSubview:chevron];[row addSubview:cover];
        [NSLayoutConstraint activateConstraints:@[[cover.topAnchor constraintEqualToAnchor:row.topAnchor],[cover.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
            [cover.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],[cover.trailingAnchor constraintEqualToAnchor:row.trailingAnchor]]];
    }
    return row;
}
- (UIView *)switchRowWithTitle:(NSString *)title detail:(NSString *)detail on:(BOOL)on handler:(void (^)(BOOL))handler{
    UIStackView *row=[self horizontalRow];[row addArrangedSubview:[self textColumnWithTitle:title detail:detail]];
    UISwitch *toggle=[UISwitch new];toggle.on=on;toggle.onTintColor=UIColor.systemGreenColor;toggle.accessibilityLabel=title;
    __weak UISwitch *weakToggle=toggle;[toggle addAction:[UIAction actionWithHandler:^(__unused UIAction *a){handler(weakToggle.isOn);}] forControlEvents:UIControlEventValueChanged];
    [row addArrangedSubview:toggle];return row;
}
- (UIView *)sliderRowWithTitle:(NSString *)title value:(float)value minimum:(float)minimum maximum:(float)maximum format:(NSString *(^)(float))format handler:(void (^)(float))handler{
    UIStackView *column=[UIStackView new];column.axis=UILayoutConstraintAxisVertical;column.spacing=10;
    UIStackView *top=[self horizontalRow];[top addArrangedSubview:[self textColumnWithTitle:title detail:nil]];
    UILabel *valueLabel=WPThemeLabel(format(value),15,UIFontWeightRegular,WPThemeSecondaryText());valueLabel.numberOfLines=1;
    [valueLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];[top addArrangedSubview:valueLabel];
    UISlider *slider=[UISlider new];slider.minimumValue=minimum;slider.maximumValue=maximum;slider.value=value;slider.accessibilityLabel=title;slider.accessibilityValue=format(value);
    __weak UISlider *weakSlider=slider;
    [slider addAction:[UIAction actionWithHandler:^(__unused UIAction *a){valueLabel.text=format(weakSlider.value);weakSlider.accessibilityValue=valueLabel.text;handler(weakSlider.value);}] forControlEvents:UIControlEventValueChanged];
    [column addArrangedSubview:top];[column addArrangedSubview:slider];return column;
}
- (UIView *)segmentedRowWithTitle:(NSString *)title items:(NSArray<NSString *> *)items selected:(NSInteger)selected handler:(void (^)(NSInteger))handler{
    UIStackView *row=[self horizontalRow];[row addArrangedSubview:[self textColumnWithTitle:title detail:nil]];
    UISegmentedControl *control=[[UISegmentedControl alloc] initWithItems:items];control.selectedSegmentIndex=selected;control.accessibilityLabel=title;
    [control setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [control.widthAnchor constraintGreaterThanOrEqualToConstant:MIN(240,items.count*64)].active=YES;
    __weak UISegmentedControl *weakControl=control;[control addAction:[UIAction actionWithHandler:^(__unused UIAction *a){handler(weakControl.selectedSegmentIndex);}] forControlEvents:UIControlEventValueChanged];
    [row addArrangedSubview:control];return row;
}
- (UIView *)fieldRowWithTitle:(NSString *)title field:(UITextField *)field{
    UIStackView *column=[UIStackView new];column.axis=UILayoutConstraintAxisVertical;column.spacing=8;
    [column addArrangedSubview:WPThemeLabel(title,13,UIFontWeightRegular,WPThemeSecondaryText())];
    field.backgroundColor=WPThemeElevated();field.textColor=WPThemePrimaryText();field.font=[UIFont systemFontOfSize:16];field.layer.cornerRadius=12;field.layer.cornerCurve=kCACornerCurveContinuous;
    field.leftView=[[UIView alloc] initWithFrame:CGRectMake(0,0,14,10)];field.leftViewMode=UITextFieldViewModeAlways;field.clearButtonMode=UITextFieldViewModeWhileEditing;
    if(field.placeholder)field.attributedPlaceholder=[[NSAttributedString alloc] initWithString:field.placeholder attributes:@{NSForegroundColorAttributeName:[WPThemeSecondaryText() colorWithAlphaComponent:.8]}];
    field.accessibilityLabel=title;[field.heightAnchor constraintEqualToConstant:48].active=YES;
    [column addArrangedSubview:field];return column;
}
- (UIButton *)buttonWithTitle:(NSString *)title primary:(BOOL)primary handler:(void (^)(void))handler{
    UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];[button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font=[UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];button.titleLabel.numberOfLines=0;button.titleLabel.textAlignment=NSTextAlignmentCenter;
    button.backgroundColor=primary?UIColor.systemBlueColor:WPThemeElevated();button.tintColor=primary?UIColor.whiteColor:WPThemePrimaryText();
    button.layer.cornerRadius=14;button.layer.cornerCurve=kCACornerCurveContinuous;button.contentEdgeInsets=UIEdgeInsetsMake(12,14,12,14);
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:50].active=YES;
    [button addAction:[UIAction actionWithHandler:^(__unused UIAction *a){handler();}] forControlEvents:UIControlEventTouchUpInside];
    return button;
}
- (void)alert:(NSString *)message{
    if(self.presentedViewController)return;
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"Zhour" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:alert animated:YES completion:nil];
}
@end
