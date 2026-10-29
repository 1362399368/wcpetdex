#import "WPChoiceSheet.h"
#import <math.h>

@interface WPChoiceItem ()
@property(nonatomic,copy,readwrite) NSString *title;
@property(nonatomic,copy,readwrite) NSString *icon;
@property(nonatomic,readwrite) BOOL destructive;
@property(nonatomic,copy,readwrite) dispatch_block_t handler;
@end
@implementation WPChoiceItem
+ (instancetype)itemWithTitle:(NSString *)title icon:(NSString *)icon destructive:(BOOL)destructive handler:(dispatch_block_t)handler {
    WPChoiceItem *item=[self new];item.title=title.length?[title copy]:@"选项";item.icon=[icon copy];item.destructive=destructive;item.handler=[handler copy];return item;
}
@end

@interface WPChoiceSheetController ()
@property(nonatomic,copy) NSString *sheetTitle;
@property(nonatomic,copy) NSArray<WPChoiceItem *> *items;
@property(nonatomic,strong) UIScrollView *scroll;
@property(nonatomic,strong) UIStackView *stack;
@property(nonatomic,strong) NSLayoutConstraint *scrollHeight;
@property(nonatomic) BOOL closing;
@end
@implementation WPChoiceSheetController
- (instancetype)initWithTitle:(NSString *)title items:(NSArray<WPChoiceItem *> *)items {
    if((self=[super initWithNibName:nil bundle:nil])){
        _sheetTitle=[title copy];NSMutableArray *valid=[NSMutableArray new];
        for(id item in items)if([item isKindOfClass:WPChoiceItem.class]){[valid addObject:item];if(valid.count==80)break;}
        _items=[valid copy];self.modalPresentationStyle=UIModalPresentationOverFullScreen;self.modalTransitionStyle=UIModalTransitionStyleCrossDissolve;
    }return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];self.view.backgroundColor=UIColor.clearColor;self.view.accessibilityViewIsModal=YES;
    UIControl *shade=[UIControl new];shade.backgroundColor=[UIColor.blackColor colorWithAlphaComponent:.26];shade.translatesAutoresizingMaskIntoConstraints=NO;
    shade.accessibilityLabel=@"关闭选择";[shade addTarget:self action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside];[self.view addSubview:shade];
    self.scroll=[UIScrollView new];self.scroll.translatesAutoresizingMaskIntoConstraints=NO;self.scroll.showsVerticalScrollIndicator=YES;[self.view addSubview:self.scroll];
    self.stack=[UIStackView new];self.stack.axis=UILayoutConstraintAxisVertical;self.stack.spacing=10;self.stack.translatesAutoresizingMaskIntoConstraints=NO;[self.scroll addSubview:self.stack];
    if(self.sheetTitle.length){
        UILabel *label=[UILabel new];label.text=self.sheetTitle;label.textColor=UIColor.whiteColor;label.font=[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        label.numberOfLines=2;label.textAlignment=NSTextAlignmentCenter;label.accessibilityIdentifier=@"WPChoiceSheetTitle";[self.stack addArrangedSubview:label];
    }
    __weak typeof(self) weakSelf=self;
    [self.items enumerateObjectsUsingBlock:^(WPChoiceItem *item,NSUInteger index,__unused BOOL *stop){
        UIButton *button=[weakSelf capsuleTitle:item.title icon:item.icon destructive:item.destructive];button.accessibilityIdentifier=[NSString stringWithFormat:@"WPChoiceOption.%lu",(unsigned long)index];
        [button addAction:[UIAction actionWithHandler:^(__unused UIAction *action){[weakSelf finish:item.handler];}] forControlEvents:UIControlEventTouchUpInside];
        [weakSelf.stack addArrangedSubview:button];
    }];
    UIButton *cancel=[self capsuleTitle:@"取消" icon:@"xmark" destructive:NO];cancel.accessibilityIdentifier=@"WPChoiceCancel";
    [cancel addTarget:self action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside];[self.view addSubview:cancel];
    UILayoutGuide *safe=self.view.safeAreaLayoutGuide;
    self.scrollHeight=[self.scroll.heightAnchor constraintEqualToConstant:0];
    [NSLayoutConstraint activateConstraints:@[[shade.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[shade.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [shade.topAnchor constraintEqualToAnchor:self.view.topAnchor],[shade.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [cancel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:24],[cancel.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-24],
        [cancel.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-14],[cancel.heightAnchor constraintEqualToConstant:56],
        [self.scroll.leadingAnchor constraintEqualToAnchor:cancel.leadingAnchor],[self.scroll.trailingAnchor constraintEqualToAnchor:cancel.trailingAnchor],
        [self.scroll.bottomAnchor constraintEqualToAnchor:cancel.topAnchor constant:-12],self.scrollHeight,
        [self.stack.leadingAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.leadingAnchor],[self.stack.trailingAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.trailingAnchor],
        [self.stack.topAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.topAnchor],[self.stack.bottomAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.bottomAnchor],
        [self.stack.widthAnchor constraintEqualToAnchor:self.scroll.frameLayoutGuide.widthAnchor]]];
}
- (UIButton *)capsuleTitle:(NSString *)title icon:(NSString *)symbol destructive:(BOOL)destructive {
    UIButton *button=[UIButton buttonWithType:UIButtonTypeCustom];button.translatesAutoresizingMaskIntoConstraints=NO;button.accessibilityLabel=title;
    button.layer.cornerRadius=28;button.layer.cornerCurve=kCACornerCurveContinuous;button.clipsToBounds=YES;
    UIBlurEffect *blur=[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];UIVisualEffectView *background=[[UIVisualEffectView alloc] initWithEffect:blur];
    background.userInteractionEnabled=NO;background.translatesAutoresizingMaskIntoConstraints=NO;[button addSubview:background];
    UILabel *label=[UILabel new];label.text=title;label.textColor=destructive?UIColor.systemRedColor:UIColor.labelColor;
    label.font=[UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];label.numberOfLines=1;label.adjustsFontSizeToFitWidth=YES;label.minimumScaleFactor=.78;
    label.textAlignment=NSTextAlignmentCenter;label.userInteractionEnabled=NO;label.translatesAutoresizingMaskIntoConstraints=NO;[button addSubview:label];
    UIImageView *image=[[UIImageView alloc] initWithImage:symbol.length?[UIImage systemImageNamed:symbol]:nil];image.tintColor=label.textColor;image.contentMode=UIViewContentModeScaleAspectFit;
    image.userInteractionEnabled=NO;image.translatesAutoresizingMaskIntoConstraints=NO;[button addSubview:image];
    [NSLayoutConstraint activateConstraints:@[[button.heightAnchor constraintEqualToConstant:56],
        [background.leadingAnchor constraintEqualToAnchor:button.leadingAnchor],[background.trailingAnchor constraintEqualToAnchor:button.trailingAnchor],
        [background.topAnchor constraintEqualToAnchor:button.topAnchor],[background.bottomAnchor constraintEqualToAnchor:button.bottomAnchor],
        [label.centerXAnchor constraintEqualToAnchor:button.centerXAnchor constant:symbol.length?12:0],[label.centerYAnchor constraintEqualToAnchor:button.centerYAnchor],
        [label.leadingAnchor constraintGreaterThanOrEqualToAnchor:button.leadingAnchor constant:symbol.length?42:12],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:button.trailingAnchor constant:-12],
        [image.trailingAnchor constraintEqualToAnchor:label.leadingAnchor constant:-10],[image.centerYAnchor constraintEqualToAnchor:button.centerYAnchor],
        [image.widthAnchor constraintEqualToConstant:symbol.length?21:0],[image.heightAnchor constraintEqualToConstant:21]]];
    return button;
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width=CGRectGetWidth(self.scroll.bounds);if(width<=0)width=MAX(1,CGRectGetWidth(self.view.bounds)-48);
    CGSize fitted=[self.stack systemLayoutSizeFittingSize:CGSizeMake(width,UILayoutFittingCompressedSize.height) withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    CGFloat available=MAX(0,CGRectGetHeight(self.view.bounds)-self.view.safeAreaInsets.top-self.view.safeAreaInsets.bottom-104);
    CGFloat target=MIN(MAX(0,fitted.height),available);if(fabs(self.scrollHeight.constant-target)>.5){self.scrollHeight.constant=target;[self.view setNeedsLayout];}
}
- (BOOL)accessibilityPerformEscape {[self cancel];return YES;}
- (void)cancel {[self finish:nil];}
- (void)finish:(dispatch_block_t)handler {
    if(self.closing)return;self.closing=YES;
    [self dismissViewControllerAnimated:YES completion:^{if(handler)handler();}];
}
@end

void WPPresentChoiceSheet(UIViewController *presenter,NSString *title,NSArray<WPChoiceItem *> *items) {
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{WPPresentChoiceSheet(presenter,title,items);});return;}
    if(!presenter || !presenter.view.window || presenter.isBeingDismissed)return;
    // A rapid repeat tap must not stack identical plugin sheets, but ordinary
    // app modals may still present their own choice sheet.
    if([presenter isKindOfClass:WPChoiceSheetController.class])return;
    while(presenter.presentedViewController && !presenter.presentedViewController.isBeingDismissed){
        presenter=presenter.presentedViewController;
        if([presenter isKindOfClass:WPChoiceSheetController.class])return;
    }
    id<UIViewControllerTransitionCoordinator> transition=presenter.transitionCoordinator;
    if(transition && transition.isAnimated){
        __weak UIViewController *weakPresenter=presenter;
        [transition animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context){
            if(!context.isCancelled)dispatch_async(dispatch_get_main_queue(),^{WPPresentChoiceSheet(weakPresenter,title,items);});
        }];return;
    }
    // The sheet occupies the bottom of the chat. Resigning the keyboard leaves
    // the draft untouched and prevents the system keyboard from covering it.
    [presenter.view endEditing:YES];
    WPChoiceSheetController *sheet=[[WPChoiceSheetController alloc] initWithTitle:title items:items];[presenter presentViewController:sheet animated:YES completion:nil];
}
