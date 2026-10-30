#import "WPResizableChat.h"
#import "WPCommon.h"
#import "WPChatPresentationState.h"
#import <objc/runtime.h>
#import <math.h>
static NSString *const WPResizableChatLegacyHeightKey=@"quickChatRememberedHeightFraction";
static UISheetPresentationControllerDetentIdentifier const WPChatDefaultDetent=@"WPChatDefault75Percent";
static char WPResizableChatCoordinatorKey;
CGFloat WPResizableChatClampHeightFraction(CGFloat fraction){return isfinite(fraction)?MIN(1,MAX(.35,fraction)):.75;}
CGFloat WPResizableChatSavedHeightFraction(void){return .75;}
@interface WPResizableChatController ()
@property(nonatomic,weak,readwrite) UIViewController *presentedController;
@property(nonatomic,weak,readwrite) UINavigationController *chatNavigationController;
@end
@implementation WPResizableChatController
+ (instancetype)coordinatorForController:(UIViewController *)controller{return controller?objc_getAssociatedObject(controller,&WPResizableChatCoordinatorKey):nil;}
+ (instancetype)attachToPresentedController:(UIViewController *)controller navigationController:(UINavigationController *)navigation{
    // Drop the retired preference rather than applying a stale user detent.
    [WPPreferences() removeObjectForKey:WPResizableChatLegacyHeightKey];
    WPResizableChatController *coordinator=[self coordinatorForController:controller];
    if(coordinator)return coordinator;
    if(!controller.presentingViewController || !controller.sheetPresentationController)return nil;
    coordinator=[self new];coordinator.presentedController=controller;coordinator.chatNavigationController=navigation;
    objc_setAssociatedObject(controller,&WPResizableChatCoordinatorKey,coordinator,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [coordinator configureNativeSheet];return coordinator;
}
- (void)configureNativeSheet{
    UIViewController *controller=self.presentedController;
    UISheetPresentationController *sheet=controller.sheetPresentationController;
    if(!sheet)return;
    // Retain the native delegate and native gesture recognizers. A custom
    // navigation-bar pan used to compete with WeChat's own sheet/input gestures.
    sheet.prefersGrabberVisible=YES;sheet.preferredCornerRadius=26;
    sheet.prefersScrollingExpandsWhenScrolledToEdge=YES;
    sheet.widthFollowsPreferredContentSizeWhenEdgeAttached=YES;
    if(@available(iOS 16.0,*)){
        __weak UIViewController *weakController=controller;
        UISheetPresentationControllerDetent *initial=[UISheetPresentationControllerDetent customDetentWithIdentifier:WPChatDefaultDetent resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> context){
            UIViewController *controller=weakController;CGFloat height=CGRectGetHeight(controller.presentationController.containerView.bounds);
            if(!isfinite(height) || height<=0)height=CGRectGetHeight(controller.view.window.bounds);
            if(!isfinite(height) || height<=0)height=context.maximumDetentValue;
            return MIN(MAX(1,context.maximumDetentValue),MAX(1,height*.75));
        }];
        // A fixed initial size preserves the existing appearance. UIKit owns
        // expansion, collapse, dismissal, keyboard avoidance and message menus.
        sheet.detents=@[initial,UISheetPresentationControllerDetent.largeDetent];
        sheet.selectedDetentIdentifier=WPChatDefaultDetent;
    }
}
- (BOOL)fullHeight{return [self.presentedController.sheetPresentationController.selectedDetentIdentifier isEqual:UISheetPresentationControllerDetentIdentifierLarge];}
- (CGFloat)heightFraction{return self.fullHeight?1:.75;}
- (BOOL)heightHoldPending{return NO;}
- (BOOL)adjustingHeight{return NO;}
- (void)beginHeightAdjustment{}
- (void)updateHeightAdjustmentToFraction:(CGFloat)fraction{}
- (void)endHeightAdjustment{}
- (void)finishHeightAdjustmentWithVelocity:(CGFloat)velocity{}
- (void)close{
    [self.presentedController dismissViewControllerAnimated:YES completion:^{WPChatPresentationNotifyChanged();}];
}
@end
