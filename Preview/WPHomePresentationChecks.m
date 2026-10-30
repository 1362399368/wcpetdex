#import "WPHomePresentationChecks.h"
#import "WPHomePresentation.h"
#import "WPCommon.h"
#import "WPSharedChatAvatar.h"
#import <UIKit/UIKit.h>

extern void WPPreviewSeedSharedAvatar(NSString *,UIImage *);

// The preview tests navigation state, not UIKit transition animations. Disable
// animations so that back-and-repeat taps can be exercised synchronously.
@interface WPHomeTestNavigationController : UINavigationController
@end
@implementation WPHomeTestNavigationController
- (void)pushViewController:(UIViewController *)controller animated:(BOOL)animated {
    [super pushViewController:controller animated:NO];
}
@end

static UIView *WPHomeFind(UIView *view,NSString *identifier) {
    if([view.accessibilityIdentifier isEqualToString:identifier])return view;
    for(UIView *child in view.subviews){UIView *found=WPHomeFind(child,identifier);if(found)return found;}
    return nil;
}
static UIControl *WPHomeControlWithLabel(UIView *view,NSString *label) {
    if([view isKindOfClass:UIControl.class] && [view.accessibilityLabel isEqualToString:label])return (UIControl *)view;
    for(UIView *child in view.subviews){UIControl *found=WPHomeControlWithLabel(child,label);if(found)return found;}
    return nil;
}
static UIScrollView *WPHomeScrollView(UIView *view) {
    if([view isKindOfClass:UIScrollView.class])return (UIScrollView *)view;
    for(UIView *child in view.subviews){UIScrollView *found=WPHomeScrollView(child);if(found)return found;}return nil;
}
static void WPHomeScrollToView(UIView *home,UIView *target) {
    UIScrollView *scroll=WPHomeScrollView(home);
    if(scroll && target){
        [home setNeedsLayout];[home layoutIfNeeded];[scroll setNeedsLayout];[scroll layoutIfNeeded];
        CGRect targetRect=[target convertRect:target.bounds toView:scroll];
        [scroll scrollRectToVisible:targetRect animated:NO];
        [scroll layoutIfNeeded];[home layoutIfNeeded];
    }
}
static NSDictionary<NSString *,NSNumber *> *WPHomeVisibilityChecks(void) {
    __block NSInteger change=-1;
    UIView *header=WPBuildHomeHeaderWithVisibility(NO,^(BOOL hidden){change=hidden?1:0;});
    header.frame=CGRectMake(0,0,390,240);[header layoutIfNeeded];
    UIControl *button=(id)WPHomeFind(header,@"WPHidePetButton");
    UIImageView *avatar=(id)WPHomeFind(header,@"WPHomeAccountAvatar");
    UILabel *brand=(id)WPHomeFind(header,@"WPHomeBrand");
    UIColor *first=[brand.attributedText attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL];
    UIColor *last=[brand.attributedText attribute:NSForegroundColorAttributeName atIndex:4 effectiveRange:NULL];
    BOOL multicolor=first && last && ![first isEqual:last];
    CGRect avatarFrame=[avatar convertRect:avatar.bounds toView:header];
    BOOL alongside=button && CGRectGetMinX(button.frame)>=CGRectGetMaxX(avatarFrame) && CGRectContainsRect(header.bounds,button.frame);
    CGPoint iconPoint=CGPointMake(CGRectGetMidX(button.bounds),20);
    BOOL hits=[header hitTest:[button convertPoint:iconPoint toView:header] withEvent:nil]==button;
    if(hits)[button sendActionsForControlEvents:UIControlEventTouchUpInside];BOOL hides=change==1;
    header.frame=CGRectMake(0,0,280,240);[header setNeedsLayout];[header layoutIfNeeded];
    avatarFrame=[avatar convertRect:avatar.bounds toView:header];
    BOOL narrow=CGRectGetMinX(button.frame)>=CGRectGetMaxX(avatarFrame) && CGRectContainsRect(header.bounds,button.frame);
    UIView *hidden=WPBuildHomeHeaderWithVisibility(YES,^(BOOL hide){change=hide?1:0;});
    UIControl *show=(id)WPHomeFind(hidden,@"WPHidePetButton");change=-1;[show sendActionsForControlEvents:UIControlEventTouchUpInside];
    return @{@"homeBrandMulticolor":@(multicolor),@"homeVisibilityNearAvatar":@(alongside&&narrow),
             @"homeVisibilityHitAndHide":@(hits&&hides),@"homeVisibilityRestoresPet":@(change==0)};
}
// Exercise the real hierarchy and hit testing. Sending actions directly to a
// control cannot detect a decorative subview intercepting a physical tap.
static NSDictionary<NSString *,NSNumber *> *WPHomeNavigationChecks(void) {
    UIWindow *window=[[UIWindow alloc] initWithFrame:CGRectMake(0,0,390,844)];
    UIViewController *home=[NSClassFromString(@"WPSettingsController") new];
    UINavigationController *navigation=[[WPHomeTestNavigationController alloc] initWithRootViewController:home];
    window.rootViewController=navigation;window.hidden=NO;
    [window layoutIfNeeded];[navigation.view layoutIfNeeded];[home.view layoutIfNeeded];
    NSArray *entries=@[@[@"快捷设置",@"WPQuickActionsController"],@[@"长按菜单",@"WPMenuSettingsController"],
                       @[@"桌宠设置",@"WPPetSettingsController"],@[@"外观设置",@"WPAppearanceSettingsController"],
                       @[@"便捷聊天",@"WPQuickChatSettingsController"],@[@"提醒方式",@"WPReminderSettingsController"],
                       @[@"聊天弹幕",@"WPBarrageSettingsController"],@[@"聊天参谋",@"WPChatAdvisorSettingsController"],
                       @[@"在线桌宠",@"WPCatalogController"],@[@"本地桌宠",@"WPCatalogController"]];
    UIControl *first=WPHomeControlWithLabel(home.view,@"快捷设置"),*second=WPHomeControlWithLabel(home.view,@"长按菜单");
    UIControl *third=WPHomeControlWithLabel(home.view,@"桌宠设置"),*fourth=WPHomeControlWithLabel(home.view,@"外观设置");
    CGRect a=[first convertRect:first.bounds toView:home.view],b=[second convertRect:second.bounds toView:home.view];
    CGRect c=[third convertRect:third.bounds toView:home.view],d=[fourth convertRect:fourth.bounds toView:home.view];
    UIView *featureCircle=WPHomeFind(first,@"WPHomeFeatureCircle");
    BOOL fourColumns=first && second && third && fourth && fabs(CGRectGetMinY(a)-CGRectGetMinY(b))<1 &&
        fabs(CGRectGetMinY(a)-CGRectGetMinY(c))<1 && fabs(CGRectGetMinY(a)-CGRectGetMinY(d))<1 &&
        CGRectGetMinX(b)>=CGRectGetMaxX(a) && CGRectGetMinX(c)>=CGRectGetMaxX(b) && CGRectGetMinX(d)>=CGRectGetMaxX(c);
    BOOL compactCircle=CGRectGetWidth(featureCircle.bounds)>=56 && CGColorGetAlpha(featureCircle.backgroundColor.CGColor)<1;
    BOOL hitPoints=YES,navigationWorks=YES,repeated=YES,catalogModes=YES;
    for(NSArray *entry in entries){
        for(NSUInteger pass=0;pass<2;pass++){
            [navigation setViewControllers:@[home] animated:NO];[home.view layoutIfNeeded];
            UIControl *control=WPHomeControlWithLabel(home.view,entry[0]);
            WPHomeScrollToView(home.view,control);
            UIView *circle=nil,*label=nil;
            for(UIView *child in control.subviews){if([child isKindOfClass:UILabel.class])label=child;else circle=child;}
            [control layoutIfNeeded];
            CGPoint points[] = {CGPointMake(CGRectGetMidX(circle.frame),CGRectGetMidY(circle.frame)),
                CGPointMake(CGRectGetMinX(circle.frame)+7,CGRectGetMidY(circle.frame)),
                CGPointMake(CGRectGetMidX(label.frame),CGRectGetMidY(label.frame))};
            BOOL hasHits=control && circle && label;
            for(NSUInteger i=0;i<3 && hasHits;i++){
                CGPoint point=[control convertPoint:points[i] toView:navigation.view];
                if([navigation.view hitTest:point withEvent:nil]!=control)hasHits=NO;
            }
            hitPoints &= hasHits;
            if(hasHits)[UIView performWithoutAnimation:^{[control sendActionsForControlEvents:UIControlEventTouchUpInside];}];
            BOOL opened=[NSStringFromClass(navigation.topViewController.class) isEqualToString:entry[1]];
            if(opened && [entry[1] isEqualToString:@"WPCatalogController"]){
                BOOL downloaded=[[navigation.topViewController valueForKey:@"startsWithDownloadedPets"] boolValue];
                catalogModes &= ([entry[0] isEqualToString:@"本地桌宠"]==downloaded);
            }
            if(pass==0)navigationWorks &= opened;else repeated &= opened;
        }
    }
    [navigation setViewControllers:@[home] animated:NO];[home.view layoutIfNeeded];
    UIControl *intro=(id)WPHomeFind(home.view,@"WPPluginIntroduction");WPHomeScrollToView(home.view,intro);
    UIScrollView *scroll=WPHomeScrollView(home.view);
    CGFloat bottom=MAX(-scroll.adjustedContentInset.top,scroll.contentSize.height-scroll.bounds.size.height+scroll.adjustedContentInset.bottom);
    [scroll setContentOffset:CGPointMake(scroll.contentOffset.x,bottom) animated:NO];[home.view layoutIfNeeded];
    UIView *introCircle=WPHomeFind(intro,@"WPHomeFeatureCircle");
    CGPoint center=[intro convertPoint:CGPointMake(CGRectGetMidX(introCircle.frame),CGRectGetMidY(introCircle.frame)) toView:navigation.view];
    BOOL introHit=intro && introCircle && [navigation.view hitTest:center withEvent:nil]==intro;
    if(introHit)[UIView performWithoutAnimation:^{[intro sendActionsForControlEvents:UIControlEventTouchUpInside];}];
    BOOL introWorks=introHit && [NSStringFromClass(navigation.topViewController.class) isEqualToString:@"WPPluginIntroductionController"];
    [navigation setViewControllers:@[home] animated:NO];[home.view layoutIfNeeded];
    UIControl *telegram=(id)WPHomeFind(home.view,@"WPHomeTelegramGroup");WPHomeScrollToView(home.view,telegram);
    UIView *telegramCircle=WPHomeFind(telegram,@"WPHomeFeatureCircle");
    CGPoint telegramCenter=[telegramCircle convertPoint:CGPointMake(CGRectGetMidX(telegramCircle.bounds),CGRectGetMidY(telegramCircle.bounds)) toView:navigation.view];
    BOOL telegramHit=telegram && telegramCircle && [navigation.view hitTest:telegramCenter withEvent:nil]==telegram;
    window.hidden=YES;window.rootViewController=nil;
    return @{@"homeIconsAndLabelsReceiveTaps":@(hitPoints),@"homeAllFeaturesOpen":@(navigationWorks),
             @"homeFeaturesReopenAfterBack":@(repeated),@"homeIntroductionOpens":@(introWorks),
             @"homeOverviewFourColumns":@(fourColumns),@"homeOverviewCirclesTranslucent":@(compactCircle),
             @"homeCatalogOnlineAndDownloadedModes":@(catalogModes),@"homeTelegramEntryHittable":@(telegramHit)};
}
static NSDictionary<NSString *,NSNumber *> *WPHomeSmallScreenChecks(void) {
    UIWindow *window=[[UIWindow alloc] initWithFrame:CGRectMake(0,0,320,568)];
    UIViewController *home=[NSClassFromString(@"WPSettingsController") new];
    UINavigationController *navigation=[[WPHomeTestNavigationController alloc] initWithRootViewController:home];
    window.rootViewController=navigation;window.hidden=NO;
    [window layoutIfNeeded];[navigation.view layoutIfNeeded];[home.view layoutIfNeeded];
    BOOL contained=YES,hittable=YES;NSMutableDictionary *detail=[NSMutableDictionary new];
    for(NSString *name in @[@"快捷设置",@"长按菜单",@"桌宠设置",@"外观设置",@"便捷聊天",@"提醒方式",@"聊天弹幕",@"聊天参谋",@"在线桌宠",@"本地桌宠",@"插件介绍",@"Telegram"]){
        UIControl *control=WPHomeControlWithLabel(home.view,name);WPHomeScrollToView(home.view,control);
        if([name isEqualToString:@"插件介绍"] || [name isEqualToString:@"Telegram"]){UIScrollView *scroll=WPHomeScrollView(home.view);
            CGFloat bottom=MAX(-scroll.adjustedContentInset.top,scroll.contentSize.height-scroll.bounds.size.height+scroll.adjustedContentInset.bottom);
            [scroll setContentOffset:CGPointMake(scroll.contentOffset.x,bottom) animated:NO];[home.view layoutIfNeeded];}
        UIView *circle=WPHomeFind(control,@"WPHomeFeatureCircle");
        CGRect icon=[circle convertRect:circle.bounds toView:control];
        contained &= control && circle && CGRectContainsRect(control.bounds,icon);
        CGPoint center=[circle convertPoint:CGPointMake(CGRectGetMidX(circle.bounds),CGRectGetMidY(circle.bounds)) toView:navigation.view];
        BOOL hit=circle && [navigation.view hitTest:center withEvent:nil]==control;
        detail[[@"homeSmallScreenHit-" stringByAppendingString:name]]=@(hit);hittable &=hit;
    }
    window.hidden=YES;window.rootViewController=nil;
    UIScrollView *scroll=WPHomeScrollView(home.view);
    detail[@"homeSmallScreenContentHasWidth"]=@(scroll && scroll.contentSize.width>=scroll.bounds.size.width-.5);
    detail[@"homeSmallScreenIconsContained"]=@(contained);detail[@"homeSmallScreenEntriesHittable"]=@(hittable);return detail;
}
static NSDictionary<NSString *,NSNumber *> *WPHomeNarrowScreenChecks(void) {
    UIWindow *window=[[UIWindow alloc] initWithFrame:CGRectMake(0,0,280,568)];
    UIViewController *home=[NSClassFromString(@"WPSettingsController") new];
    UINavigationController *navigation=[[WPHomeTestNavigationController alloc] initWithRootViewController:home];
    window.rootViewController=navigation;window.hidden=NO;[window layoutIfNeeded];[navigation.view layoutIfNeeded];[home.view layoutIfNeeded];
    NSArray *names=@[@"快捷设置",@"长按菜单",@"桌宠设置",@"外观设置",@"便捷聊天",@"提醒方式",@"聊天弹幕",@"聊天参谋",@"在线桌宠",@"本地桌宠",@"插件介绍",@"Telegram"];
    BOOL allHit=YES;for(NSString *name in names){
        UIControl *control=WPHomeControlWithLabel(home.view,name);WPHomeScrollToView(home.view,control);
        if([name isEqualToString:@"插件介绍"] || [name isEqualToString:@"Telegram"]){UIScrollView *scroll=WPHomeScrollView(home.view);
            CGFloat bottom=MAX(-scroll.adjustedContentInset.top,scroll.contentSize.height-scroll.bounds.size.height+scroll.adjustedContentInset.bottom);
            [scroll setContentOffset:CGPointMake(scroll.contentOffset.x,bottom) animated:NO];[home.view layoutIfNeeded];}
        UIView *circle=WPHomeFind(control,@"WPHomeFeatureCircle");
        CGPoint center=[circle convertPoint:CGPointMake(CGRectGetMidX(circle.bounds),CGRectGetMidY(circle.bounds)) toView:navigation.view];
        allHit &= control && circle && [navigation.view hitTest:center withEvent:nil]==control;
    }
    UIControl *first=WPHomeControlWithLabel(home.view,@"快捷设置"),*fourth=WPHomeControlWithLabel(home.view,@"外观设置");
    CGRect a=[first convertRect:first.bounds toView:home.view],d=[fourth convertRect:fourth.bounds toView:home.view];
    BOOL wraps=first && fourth && CGRectGetMinY(d)>CGRectGetMaxY(a);
    window.hidden=YES;window.rootViewController=nil;
    return @{@"homeNarrowScreenThreeColumnWrap":@(wraps),@"homeNarrowScreenAllEntriesHittable":@(allHit)};
}
static NSDictionary<NSString *,NSNumber *> *WPHomeCompactGridChecks(void) {
    NSMutableDictionary *results=[NSMutableDictionary new];
    for(NSArray<NSNumber *> *size in @[@[@320,@568],@[@390,@844],@[@430,@1200]]){
        CGFloat width=size[0].doubleValue,height=size[1].doubleValue;
        UIWindow *window=[[UIWindow alloc] initWithFrame:CGRectMake(0,0,width,height)];
        UIViewController *home=[NSClassFromString(@"WPSettingsController") new];
        UINavigationController *navigation=[[WPHomeTestNavigationController alloc] initWithRootViewController:home];
        window.rootViewController=navigation;window.hidden=NO;
        [window layoutIfNeeded];[navigation.view layoutIfNeeded];[home.view layoutIfNeeded];
        NSArray *names=@[@"快捷设置",@"长按菜单",@"桌宠设置",@"外观设置"];
        NSMutableArray<NSValue *> *frames=[NSMutableArray new];BOOL valid=YES;
        for(NSString *name in names){
            UIControl *control=WPHomeControlWithLabel(home.view,name);UIView *circle=WPHomeFind(control,@"WPHomeFeatureCircle");
            valid &= control && circle && CGRectGetWidth(circle.bounds)>=56;
            [frames addObject:[NSValue valueWithCGRect:circle?[circle convertRect:circle.bounds toView:home.view]:CGRectZero]];
        }
        CGRect a=frames[0].CGRectValue,b=frames[1].CGRectValue,c=frames[2].CGRectValue,d=frames[3].CGRectValue;
        CGFloat gap1=CGRectGetMinX(b)-CGRectGetMaxX(a),gap2=CGRectGetMinX(c)-CGRectGetMaxX(b),gap3=CGRectGetMinX(d)-CGRectGetMaxX(c);
        CGFloat center=(CGRectGetMinX(a)+CGRectGetMaxX(d))/2;
        BOOL compact=valid && gap1>=0 && gap1<=24 && gap2>=0 && gap2<=24 && gap3>=0 && gap3<=24 &&
            fabs(CGRectGetMinY(a)-CGRectGetMinY(b))<2 && fabs(CGRectGetMinY(a)-CGRectGetMinY(d))<2 && fabs(center-width/2)<2;
        UIControl *intro=WPHomeControlWithLabel(home.view,@"插件介绍");CGRect introFrame=[intro convertRect:intro.bounds toView:home.view];
        BOOL introBelow=intro && CGRectGetMinY(introFrame)>CGRectGetMaxY(c);
        NSString *key=[NSString stringWithFormat:@"homeCompactGrid-%lux%lu",(unsigned long)width,(unsigned long)height];
        results[key]=@(compact && introBelow);
        window.hidden=YES;window.rootViewController=nil;
    }return results;
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
    NSMutableDictionary *results=[@{@"homeReadsOwnWeChatNickname":@(actualName),@"homeDisplaysCachedOwnAvatar":@(cachedAvatar),
             @"homeDisplaysZhourBrand":@(title),@"homeAvatarIsCircular":@(circular),
             @"homeGridEntryInvokesAction":@(entry),@"homeUnavailableAccountUsesPlaceholder":@(placeholder)} mutableCopy];
    [results addEntriesFromDictionary:WPHomeNavigationChecks()];
    [results addEntriesFromDictionary:WPHomeSmallScreenChecks()];
    [results addEntriesFromDictionary:WPHomeNarrowScreenChecks()];
    [results addEntriesFromDictionary:WPHomeCompactGridChecks()];
    [results addEntriesFromDictionary:WPHomeVisibilityChecks()];return results;
}
