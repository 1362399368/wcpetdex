#import "WPHomePresentationChecks.h"
#import "WPHomePresentation.h"
#import "WPCommon.h"
#import "WPSharedChatAvatar.h"
#import <UIKit/UIKit.h>

extern void WPPreviewSeedSharedAvatar(NSString *,UIImage *);

static UIView *WPHomeFind(UIView *view,NSString *identifier) {
    if([view.accessibilityIdentifier isEqualToString:identifier])return view;
    for(UIView *child in view.subviews){UIView *found=WPHomeFind(child,identifier);if(found)return found;}
    return nil;
}
NSDictionary<NSString *,NSNumber *> *WPHomePresentationChecks(void) {
    NSCAssert(NSThread.isMainThread,@"Run on main thread");
    id manager=WPWeChatService(@"CContactMgr");
    NSDictionary *contacts=[manager valueForKey:@"fixtureContacts"];
    UIImage *avatar=[[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(32,32)] imageWithActions:^(__unused UIGraphicsImageRendererContext *context){
        [UIColor.systemOrangeColor setFill];UIRectFill(CGRectMake(0,0,32,32));
    }];
    WPPreviewSeedSharedAvatar(@"wxid_contract_self",avatar);
    UIWindow *window=[[UIWindow alloc] initWithFrame:CGRectMake(0,0,390,844)];
    window.rootViewController=[UIViewController new];window.hidden=NO;
    UIView *header=WPBuildHomeHeader();header.frame=CGRectMake(0,0,358,240);[window.rootViewController.view addSubview:header];
    [header setNeedsLayout];[header layoutIfNeeded];
    UILabel *name=(id)WPHomeFind(header,@"WPHomeAccountNickname");
    UILabel *brand=(id)WPHomeFind(header,@"WPHomeBrand");
    UIImageView *image=(id)WPHomeFind(header,@"WPHomeAccountAvatar");
    NSDate *until=[NSDate dateWithTimeIntervalSinceNow:.3];
    while(image.image!=avatar && [until timeIntervalSinceNow]>0)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    BOOL actualName=[name.text isEqualToString:@"我自己"];
    BOOL cachedAvatar=image.image==avatar;
    BOOL title=[brand.text isEqualToString:@"Zhour"];
    BOOL circular=image.layer.cornerRadius>0 && image.clipsToBounds;
    __block NSUInteger called=0;UIControl *feature=WPBuildHomeFeature(@"快捷设置",[UIImage systemImageNamed:@"bolt.fill"],UIColor.systemBlueColor,^{called++;});
    [feature sendActionsForControlEvents:UIControlEventTouchUpInside];
    BOOL entry=feature.isAccessibilityElement && [feature.accessibilityLabel isEqualToString:@"快捷设置"] && called==1;
    [header removeFromSuperview];
    if(manager && contacts){
        NSMutableDictionary *missing=[contacts mutableCopy];[missing removeObjectForKey:@"wxid_contract_self"];
        [manager setValue:missing forKey:@"fixtureContacts"];
    }
    UIView *fallback=WPBuildHomeHeader();[window.rootViewController.view addSubview:fallback];
    UILabel *fallbackName=(id)WPHomeFind(fallback,@"WPHomeAccountNickname");
    UIImageView *fallbackAvatar=(id)WPHomeFind(fallback,@"WPHomeAccountAvatar");
    BOOL placeholder=[fallbackName.text isEqualToString:@"微信用户"] && fallbackAvatar.image!=nil;
    [fallback removeFromSuperview];if(manager && contacts)[manager setValue:contacts forKey:@"fixtureContacts"];
    window.hidden=YES;window.rootViewController=nil;
    return @{@"homeReadsOwnWeChatNickname":@(actualName),@"homeDisplaysCachedOwnAvatar":@(cachedAvatar),
             @"homeDisplaysZhourBrand":@(title),@"homeAvatarIsCircular":@(circular),
             @"homeGridEntryInvokesAction":@(entry),@"homeUnavailableAccountUsesPlaceholder":@(placeholder)};
}
