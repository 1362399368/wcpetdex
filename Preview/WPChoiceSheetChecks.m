#import <UIKit/UIKit.h>
#import "WPChoiceSheet.h"

@interface WPChoiceTestController : WPChoiceSheetController
@property(nonatomic) NSUInteger dismissCount;
@property(nonatomic) NSUInteger presentCount;
@end
@implementation WPChoiceTestController
- (void)dismissViewControllerAnimated:(BOOL)animated completion:(void (^)(void))completion {self.dismissCount++;if(completion)completion();}
- (void)presentViewController:(UIViewController *)controller animated:(BOOL)animated completion:(void (^)(void))completion {self.presentCount++;if(completion)completion();}
@end

static UIView *WPChoiceFind(UIView *view,NSString *identifier){
    if([view.accessibilityIdentifier isEqualToString:identifier])return view;
    for(UIView *child in view.subviews){UIView *found=WPChoiceFind(child,identifier);if(found)return found;}return nil;
}
static UIScrollView *WPChoiceScroll(UIView *view){
    if([view isKindOfClass:UIScrollView.class])return (UIScrollView *)view;
    for(UIView *child in view.subviews){UIScrollView *found=WPChoiceScroll(child);if(found)return found;}return nil;
}
static void WPChoiceLayout(UIViewController *controller,CGSize size){controller.view.frame=(CGRect){CGPointZero,size};[controller.view setNeedsLayout];[controller.view layoutIfNeeded];[controller.view setNeedsLayout];[controller.view layoutIfNeeded];}

NSDictionary<NSString *,NSNumber *> *WPChoiceSheetPreviewChecks(void){
    __block NSUInteger invoked=0;
    WPChoiceItem *a=[WPChoiceItem itemWithTitle:@"朋友闲聊" icon:@"person.2" destructive:NO handler:^{invoked++;}];
    WPChoiceItem *b=[WPChoiceItem itemWithTitle:@"恋爱聊天" icon:@"heart" destructive:NO handler:^{invoked+=10;}];
    WPChoiceTestController *sheet=[[WPChoiceTestController alloc] initWithTitle:@"选择聊天场景" items:@[a,b]];
    UIWindow *window=[[UIWindow alloc] initWithFrame:CGRectMake(0,0,390,844)];window.rootViewController=sheet;window.hidden=NO;
    WPChoiceLayout(sheet,window.bounds.size);
    UIButton *first=(id)WPChoiceFind(sheet.view,@"WPChoiceOption.0"),*second=(id)WPChoiceFind(sheet.view,@"WPChoiceOption.1"),*cancel=(id)WPChoiceFind(sheet.view,@"WPChoiceCancel");
    BOOL labels=[first.accessibilityLabel isEqual:@"朋友闲聊"] && [second.accessibilityLabel isEqual:@"恋爱聊天"] && [cancel.accessibilityLabel isEqual:@"取消"];
    CGPoint point=[first convertPoint:CGPointMake(CGRectGetMidX(first.bounds),CGRectGetMidY(first.bounds)) toView:sheet.view];
    BOOL hit=[sheet.view hitTest:point withEvent:nil]==first;
    BOOL capsule=first.layer.cornerRadius>=25 && first.clipsToBounds && first.bounds.size.height>=44;
    BOOL safe=CGRectGetMaxY([cancel convertRect:cancel.bounds toView:sheet.view])<=CGRectGetMaxY(sheet.view.bounds)-sheet.view.safeAreaInsets.bottom;
    WPPresentChoiceSheet(sheet,@"重复选择",@[a]);BOOL noStack=sheet.presentCount==0;
    if(hit)[first sendActionsForControlEvents:UIControlEventTouchUpInside];[first sendActionsForControlEvents:UIControlEventTouchUpInside];
    BOOL once=sheet.dismissCount==1 && invoked==1;
    WPChoiceTestController *cancelSheet=[[WPChoiceTestController alloc] initWithTitle:nil items:@[a]];
    window.rootViewController=cancelSheet;WPChoiceLayout(cancelSheet,window.bounds.size);
    [(UIButton *)WPChoiceFind(cancelSheet.view,@"WPChoiceCancel") sendActionsForControlEvents:UIControlEventTouchUpInside];
    BOOL noSelection=cancelSheet.dismissCount==1 && invoked==1;
    NSMutableArray *many=[NSMutableArray new];for(NSUInteger i=0;i<20;i++)[many addObject:a];
    WPChoiceTestController *shortSheet=[[WPChoiceTestController alloc] initWithTitle:@"选项" items:many];
    window.frame=CGRectMake(0,0,320,568);window.rootViewController=shortSheet;WPChoiceLayout(shortSheet,window.bounds.size);
    UIScrollView *scroll=WPChoiceScroll(shortSheet.view);[scroll layoutIfNeeded];
    BOOL scrolls=scroll && scroll.contentSize.height>scroll.bounds.size.height && scroll.bounds.size.height>0;
    BOOL smallCancel=CGRectContainsRect(shortSheet.view.bounds,[(UIView *)WPChoiceFind(shortSheet.view,@"WPChoiceCancel") convertRect:WPChoiceFind(shortSheet.view,@"WPChoiceCancel").bounds toView:shortSheet.view]);
    window.hidden=YES;window.rootViewController=nil;
    return @{@"choiceSheetAccessibleLabels":@(labels),@"choiceSheetActualHit":@(hit),@"choiceSheetCapsuleAndSafeArea":@(capsule&&safe),@"choiceSheetRejectsDuplicate":@(noStack),@"choiceSheetSelectsOnlyOnce":@(once),@"choiceSheetCancelDoesNotSelect":@(noSelection),@"choiceSheetManyOptionsScroll":@(scrolls),@"choiceSheetSmallScreenCancelVisible":@(smallCancel)};
}
