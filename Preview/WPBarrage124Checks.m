#import "WPBarrage124Checks.h"
#import "WPUnreadAvatarControl.h"
#import "WPCommon.h"
#import <QuartzCore/QuartzCore.h>

@interface UIViewController (WPB124OverlayTesting)
- (void)releaseTransientViews;
@end
@interface WPUnreadAvatarControl (WPB124VisualTesting)
- (CGRect)visualFrame;
@end
@interface WPB124OverlayRun : NSObject
@property(nonatomic,strong) UIWindow *window;
@property(nonatomic,strong) UIViewController *root;
@property(nonatomic,strong) WPUnreadAvatarControl *avatar;
@property(nonatomic,strong) NSMutableDictionary *checks;
@property(nonatomic,strong) id oldEnabled;
@property(nonatomic,copy) void (^completion)(NSDictionary *);
@end
@implementation WPB124OverlayRun
- (void)finish {
    [self.avatar.layer removeAllAnimations];[self.root releaseTransientViews];self.window.hidden=YES;self.window.rootViewController=nil;
    if(self.oldEnabled)[WPPreferences() setObject:self.oldEnabled forKey:@"enabled"];else [WPPreferences() removeObjectForKey:@"enabled"];
    void (^done)(NSDictionary *)=self.completion;self.completion=nil;if(done)done(self.checks);
}
- (void)start {
    self.checks=[NSMutableDictionary new];self.oldEnabled=[WPPreferences() objectForKey:@"enabled"];[WPPreferences() setBool:YES forKey:@"enabled"];
    self.window=[[UIWindow alloc] initWithFrame:CGRectMake(0,0,393,852)];self.window.windowLevel=-100;
    self.root=[NSClassFromString(@"WPOverlayController") new];self.window.rootViewController=self.root;self.window.hidden=NO;[self.root loadViewIfNeeded];self.root.view.frame=self.window.bounds;[self.root.view layoutIfNeeded];
    self.avatar=[self.root valueForKey:@"unreadDot"];
    UIImage *image=[[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(20,20)] imageWithActions:^(__unused UIGraphicsImageRendererContext *context){[UIColor.systemBlueColor setFill];UIRectFill(CGRectMake(0,0,20,20));}];
    [self.avatar setActive:NO];self.avatar.hidden=NO;[self.avatar showConversationUsername:@"wp124_motion_fixture" senderUsername:@"wp124_motion_sender" image:image];
    self.avatar.bounds=CGRectMake(0,0,36,36);self.avatar.center=CGPointMake(300,240);
    if(![self.avatar respondsToSelector:@selector(visualFrame)]){self.checks[@"B12407AvatarExposesPresentationGeometry"]=@NO;[self finish];return;}
    CABasicAnimation *flight=[CABasicAnimation animationWithKeyPath:@"position"];flight.fromValue=[NSValue valueWithCGPoint:CGPointMake(-36,240)];flight.toValue=[NSValue valueWithCGPoint:self.avatar.center];flight.duration=1.2;
    [self.avatar.layer addAnimation:flight forKey:@"WPMessageHeadPop123"];[CATransaction flush];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,180*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        @try{
            CGRect visual=[self.avatar visualFrame];CGPoint visible=CGPointMake(CGRectGetMidX(visual),CGRectGetMidY(visual));
            CGPoint visibleLocal=[self.avatar convertPoint:visible fromView:self.avatar.superview];
            CGPoint modelLocal=[self.avatar convertPoint:self.avatar.center fromView:self.avatar.superview];
            BOOL separated=fabs(visible.x-self.avatar.center.x)>50;
            self.checks[@"B12407AvatarFlightGeometryHasDistinctPresentationPosition"]=@(separated&&self.avatar.layer.presentationLayer!=nil);
            self.checks[@"B12408FlyingAvatarAcceptsTouchAtVisiblePixels"]=@(separated&&[self.avatar pointInside:visibleLocal withEvent:nil]);
            self.checks[@"B12409OldModelPositionDoesNotOpenInvisibleAvatar"]=@(separated&&![self.avatar pointInside:modelLocal withEvent:nil]);
            CGPoint rootPoint=[self.avatar.superview convertPoint:visible toView:self.root.view];UIView *hit=[self.root.view hitTest:rootPoint withEvent:nil];
            self.checks[@"B12410ActualOverlayHitTestReachesFlyingAvatar"]=@(hit==self.avatar);
            [self.avatar.layer removeAnimationForKey:@"WPMessageHeadPop123"];
            self.checks[@"B12411EndingFlightKeepsRouteAndRestoresModelHitArea"]=@([self.avatar.username isEqual:@"wp124_motion_fixture"]&&CGRectEqualToRect([self.avatar visualFrame],self.avatar.frame)&&[self.avatar pointInside:CGPointMake(18,18) withEvent:nil]);
        }@catch(__unused NSException *error){self.checks[@"B124OverlayMotionCompletedWithoutException"]=@NO;}
        [self finish];
    });
}
@end
void WPBarrage124RunOverlayPreviewChecks(void (^completion)(NSDictionary<NSString *,NSNumber *> *checks)) {
    WPB124OverlayRun *run=[WPB124OverlayRun new];run.completion=completion;[run start];
}
