#import "WPComfortChecks.h"
#import "WPComfortPreferences.h"
#import "WPCommon.h"
#import "WPTheme.h"
#import "WPPartnerContact.h"
#import "WPPetRenderer.h"
#import "WPOverlay.h"
#import <QuartzCore/QuartzCore.h>

@interface UIViewController (WPComfortTesting)
- (void)keyboard:(NSNotification *)note;
- (void)drag:(UIPanGestureRecognizer *)gesture;
- (void)showArrivals:(NSArray<NSString *> *)usernames;
- (void)applySettings;
@end
@interface WPOverlayManager (WPComfortTesting)
- (NSArray<UIViewController *> *)controllers;
@end
@interface WPComfortPan : UIPanGestureRecognizer
@property(nonatomic) UIGestureRecognizerState testState;
@property(nonatomic) CGPoint testPoint;
@property(nonatomic) CGPoint testTranslation;
@end
@implementation WPComfortPan
- (UIGestureRecognizerState)state{return self.testState;}
- (CGPoint)locationInView:(UIView *)view{return self.testPoint;}
- (CGPoint)translationInView:(UIView *)view{return self.testTranslation;}
@end
static UIView *WPComfortFind(UIView *view,NSString *identifier){
    if([view.accessibilityIdentifier isEqual:identifier])return view;
    for(UIView *child in view.subviews){UIView *found=WPComfortFind(child,identifier);if(found)return found;}
    return nil;
}
static UIView *WPComfortFindClass(UIView *view,Class kind){
    if([view isKindOfClass:kind])return view;
    for(UIView *child in view.subviews){UIView *found=WPComfortFindClass(child,kind);if(found)return found;}
    return nil;
}
static NSDate *WPComfortDate(NSInteger hour,NSInteger minute){return [NSCalendar.currentCalendar dateBySettingHour:hour minute:minute second:0 ofDate:NSDate.date options:0];}
static BOOL WPComfortNear(CGPoint a,CGPoint b){return fabs(a.x-b.x)<.01&&fabs(a.y-b.y)<.01;}
static void WPComfortKeyboard(UIViewController *controller,BOOL show){
    [controller keyboard:[NSNotification notificationWithName:show?UIKeyboardWillChangeFrameNotification:UIKeyboardWillHideNotification object:nil userInfo:@{UIKeyboardFrameEndUserInfoKey:[NSValue valueWithCGRect:show?CGRectMake(0,500,390,344):CGRectMake(0,844,390,0)],UIKeyboardAnimationDurationUserInfoKey:@0}]];
}
static BOOL WPComfortSnapshot(WPCardPageController *page,UIWindow *window,NSString *filename,NSString *scrollIdentifier){
    UINavigationController *navigation=[[WPAdaptiveNavigationController alloc] initWithRootViewController:page];
    window.rootViewController=navigation;[window makeKeyAndVisible];[navigation.view setNeedsLayout];[navigation.view layoutIfNeeded];[page.view layoutIfNeeded];[page.scrollView layoutIfNeeded];
    if(scrollIdentifier.length){UIView *target=WPComfortFind(page.view,scrollIdentifier);if(target){CGRect rect=[target convertRect:target.bounds toView:page.scrollView];rect.origin.y=MAX(0,rect.origin.y-200);rect.size.height=MIN(page.scrollView.bounds.size.height-24,rect.size.height+240);[page.scrollView scrollRectToVisible:rect animated:NO];}}
    UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat defaultFormat];format.scale=1;
    UIImage *image=[[[UIGraphicsImageRenderer alloc] initWithBounds:window.bounds format:format] imageWithActions:^(UIGraphicsImageRendererContext *context){[window drawViewHierarchyInRect:window.bounds afterScreenUpdates:YES];}];
    return [UIImagePNGRepresentation(image) writeToFile:[WPDataDirectory() stringByAppendingPathComponent:filename] atomically:YES];
}
NSDictionary<NSString *,NSNumber *> *WPComfortPreviewChecks(void){
    NSCAssert(NSThread.isMainThread,@"Preview checks run on main thread");
    NSMutableDictionary<NSString *,NSNumber *> *results=[NSMutableDictionary new];
    NSArray *keys=@[@"enabled",@"autoPeek",@"petSize",@"petOpacity",@"positionX",@"positionY",@"positionPortraitX",@"positionPortraitY",@"positionLandscapeX",@"positionLandscapeY",@"positionLocked",@"allowUnreadPeek",@"reminderIntensity",@"quietTimeEnabled",@"quietStartMinute",@"quietEndMinute",@"reminderContactsOnly",@"reminderContactUsernames"];
    NSDictionary *persistent=[WPPreferences() persistentDomainForName:@"dev.zhour.wechatpet"]?:@{};
    NSMutableDictionary *saved=[NSMutableDictionary new];for(NSString *key in keys)saved[key]=persistent[key]?:NSNull.null;
    UIWindow *priorKey=nil;for(UIWindow *candidate in UIApplication.sharedApplication.windows)if(candidate.isKeyWindow)priorKey=candidate;
    UIWindow *screenshotWindow=nil;UIViewController *controller=nil;
    // The settings controls post their real change notification. Preserve the
    // live preview overlays as well as persistent defaults while exercising it.
    NSMutableArray<NSDictionary *> *overlayStates=[NSMutableArray new];
    for(UIViewController *live in [[WPOverlayManager sharedManager] controllers]){
        WPPetRenderer *livePet=[live valueForKey:@"pet"];
        [overlayStates addObject:@{@"controller":live,@"anchor":[live valueForKey:@"userAnchor"],@"bounds":[live valueForKey:@"anchorBounds"],@"positioned":[live valueForKey:@"positioned"],@"center":[NSValue valueWithCGPoint:livePet.center],@"fullCenter":[live valueForKey:@"fullCenter"],@"peeking":[live valueForKey:@"peeking"]}];
    }
    @try{
        for(NSString *key in keys)[WPPreferences() removeObjectForKey:key];
        results[@"comfortUpgradeDefaultsKeepOriginalBehavior"]=@(!WPPositionLocked()&&!WPAllowUnreadPeek()&&WPConfiguredReminderIntensity()==WPReminderIntensityFull&&!WPQuietTimeAtDate(NSDate.date)&&WPReminderAllowsUsername(@"anyone",NSDate.date));
        [WPPreferences() setBool:YES forKey:@"enabled"];[WPPreferences() setBool:NO forKey:@"autoPeek"];[WPPreferences() setDouble:88 forKey:@"petSize"];[WPPreferences() setDouble:1 forKey:@"petOpacity"];
        WPStorePositionAnchor(CGPointMake(.81,.78),CGSizeMake(390,844));WPStorePositionAnchor(CGPointMake(.22,.41),CGSizeMake(844,390));
        results[@"comfortPortraitLandscapeAnchorsIndependent"]=@(WPComfortNear(WPPositionAnchorForBounds(CGSizeMake(390,844)),CGPointMake(.81,.78))&&WPComfortNear(WPPositionAnchorForBounds(CGSizeMake(844,390)),CGPointMake(.22,.41)));
        controller=[NSClassFromString(@"WPOverlayController") new];[controller loadViewIfNeeded];controller.view.frame=CGRectMake(0,0,390,844);[controller viewDidLayoutSubviews];
        WPPetRenderer *pet=[controller valueForKey:@"pet"];CGPoint original=pet.center;CGPoint originalAnchor=[[controller valueForKey:@"userAnchor"] CGPointValue];
        WPComfortKeyboard(controller,YES);BOOL avoids=CGRectGetMaxY(pet.frame)<=492.01;
        BOOL returns=YES;for(NSUInteger index=0;index<12;index++){WPComfortKeyboard(controller,YES);WPComfortKeyboard(controller,NO);[controller viewDidLayoutSubviews];returns&=WPComfortNear(pet.center,original);}
        results[@"comfortKeyboardAvoidsAndRestoresWithoutDrift"]=@(avoids&&returns&&WPComfortNear([[controller valueForKey:@"userAnchor"] CGPointValue],originalAnchor)&&WPComfortNear(WPPositionAnchorForBounds(CGSizeMake(390,844)),originalAnchor));
        controller.view.frame=CGRectMake(0,0,844,390);[controller viewDidLayoutSubviews];results[@"comfortRealOverlayLoadsLandscapeAnchor"]=@(WPComfortNear([[controller valueForKey:@"userAnchor"] CGPointValue],CGPointMake(.22,.41)));
        controller.view.frame=CGRectMake(0,0,390,844);[controller viewDidLayoutSubviews];results[@"comfortRealOverlayReturnsToPortraitAnchor"]=@(WPComfortNear(pet.center,original));
        [WPPreferences() setBool:YES forKey:@"positionLocked"];WPComfortPan *pan=[WPComfortPan new];pan.testState=UIGestureRecognizerStateBegan;pan.testPoint=pet.center;[controller drag:pan];pan.testState=UIGestureRecognizerStateChanged;pan.testTranslation=CGPointMake(-90,-80);pan.testPoint=CGPointMake(original.x-20,original.y-12);[controller drag:pan];pan.testState=UIGestureRecognizerStateEnded;[controller drag:pan];
        results[@"comfortPositionLockPreventsActualDragAndPreferenceWrite"]=@(WPComfortNear(pet.center,original)&&WPComfortNear(WPPositionAnchorForBounds(CGSizeMake(390,844)),originalAnchor)&&![[controller valueForKey:@"gestureActive"] boolValue]);
        [WPPreferences() setBool:NO forKey:@"positionLocked"];pan.testState=UIGestureRecognizerStateBegan;pan.testTranslation=CGPointZero;pan.testPoint=pet.center;[controller drag:pan];pan.testState=UIGestureRecognizerStateChanged;pan.testTranslation=CGPointMake(0,-100);pan.testPoint=CGPointMake(original.x,original.y-100);[controller drag:pan];pan.testState=UIGestureRecognizerStateEnded;[controller drag:pan];
        CGPoint moved=pet.center;results[@"comfortUnlockedDragStillMovesAndSavesAnchor"]=@(fabs(moved.y-original.y)>50&&fabs(WPPositionAnchorForBounds(CGSizeMake(390,844)).y-moved.y/844)<.001);
        CGPoint movedAnchor=WPPositionAnchorForBounds(CGSizeMake(390,844));
        pan.testState=UIGestureRecognizerStateBegan;pan.testTranslation=CGPointZero;pan.testPoint=moved;[controller drag:pan];pan.testState=UIGestureRecognizerStateChanged;pan.testTranslation=CGPointMake(0,-40);pan.testPoint=CGPointMake(moved.x,moved.y-40);[controller drag:pan];pan.testState=UIGestureRecognizerStateCancelled;[controller drag:pan];
        results[@"comfortCancelledDragRestoresSavedAnchor"]=@(WPComfortNear(pet.center,moved)&&WPComfortNear(WPPositionAnchorForBounds(CGSizeMake(390,844)),movedAnchor));
        pan.testState=UIGestureRecognizerStateBegan;pan.testTranslation=CGPointZero;pan.testPoint=moved;[controller drag:pan];WPComfortKeyboard(controller,YES);pan.testState=UIGestureRecognizerStateEnded;pan.testTranslation=CGPointMake(0,-200);[controller drag:pan];WPComfortKeyboard(controller,NO);
        results[@"comfortInterruptedPanCannotOverwriteSavedAnchor"]=@(WPComfortNear(pet.center,moved)&&WPComfortNear(WPPositionAnchorForBounds(CGSizeMake(390,844)),movedAnchor));
        [WPPreferences() setBool:YES forKey:@"quietTimeEnabled"];[WPPreferences() setInteger:22*60 forKey:@"quietStartMinute"];[WPPreferences() setInteger:8*60 forKey:@"quietEndMinute"];
        results[@"comfortQuietTimeCrossesMidnightAndExcludesEnd"]=@(WPQuietTimeAtDate(WPComfortDate(22,0))&&WPQuietTimeAtDate(WPComfortDate(0,30))&&WPQuietTimeAtDate(WPComfortDate(7,59))&&!WPQuietTimeAtDate(WPComfortDate(8,0))&&!WPQuietTimeAtDate(WPComfortDate(21,59)));
        [WPPreferences() setInteger:9*60 forKey:@"quietStartMinute"];[WPPreferences() setInteger:17*60 forKey:@"quietEndMinute"];results[@"comfortQuietTimeSameDayBoundaries"]=@(WPQuietTimeAtDate(WPComfortDate(9,0))&&!WPQuietTimeAtDate(WPComfortDate(17,0))&&!WPQuietTimeAtDate(WPComfortDate(8,59)));
        [WPPreferences() setInteger:9*60 forKey:@"quietEndMinute"];results[@"comfortEqualQuietTimesMeansAllDay"]=@(WPQuietTimeAtDate(WPComfortDate(1,0))&&WPQuietTimeAtDate(WPComfortDate(18,0)));
        UIView *arrivals=[controller valueForKey:@"arrivals"];[pet.layer removeAllAnimations];[WPPreferences() setInteger:WPReminderIntensityFull forKey:@"reminderIntensity"];[controller showArrivals:@[@"wxid_comfort_friend"]];
        results[@"comfortQuietTimeSuppressesActualArrivalFlash"]=@(arrivals.hidden&&[pet.layer animationForKey:@"quickChatPulse"]==nil&&[pet.layer animationForKey:@"quickChatFlash"]==nil);
        [WPPreferences() setBool:NO forKey:@"quietTimeEnabled"];[WPPreferences() setBool:YES forKey:@"reminderContactsOnly"];[WPPreferences() setObject:@"wxid_friend， wxid_friend\nwxid_second" forKey:@"reminderContactUsernames"];
        results[@"comfortContactFilterDeduplicatesAndMatchesExactly"]=@(WPReminderContactUsernames().count==2&&WPReminderAllowsUsername(@"wxid_friend",NSDate.date)&&!WPReminderAllowsUsername(@"friend",NSDate.date)&&!WPReminderAllowsUsername(nil,NSDate.date));
        [controller showArrivals:@[@"wxid_other"]];results[@"comfortContactFilterSuppressesUnlistedActualArrival"]=@(arrivals.hidden&&[pet.layer animationForKey:@"quickChatPulse"]==nil);
        NSString *partnerBefore=[WPPreferences() stringForKey:@"partnerUsername"],*partnerNameBefore=[WPPreferences() stringForKey:@"partnerDisplayName"];
        WPPartnerPickerController *picker=[[WPPartnerPickerController alloc] initWithStyle:UITableViewStyleInsetGrouped];picker.pickerTitle=@"选择提醒联系人";__block NSString *picked=nil;
        picker.selectionHandler=^(NSString *username,__unused NSString *displayName){picked=username;};[picker loadViewIfNeeded];
        [picker setValue:@[@{@"username":@"wxid_comfort_selected",@"name":@"提醒好友",@"search":@"提醒好友"}] forKey:@"filtered"];
        [picker tableView:picker.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
        results[@"comfortReusedContactPickerDoesNotChangePairedPartner"]=@([picked isEqual:@"wxid_comfort_selected"]&&((partnerBefore==nil&&[WPPreferences() stringForKey:@"partnerUsername"]==nil)||[partnerBefore isEqual:[WPPreferences() stringForKey:@"partnerUsername"]])&&((partnerNameBefore==nil&&[WPPreferences() stringForKey:@"partnerDisplayName"]==nil)||[partnerNameBefore isEqual:[WPPreferences() stringForKey:@"partnerDisplayName"]]));
        [WPPreferences() setBool:NO forKey:@"reminderContactsOnly"];[WPPreferences() setInteger:WPReminderIntensityAvatarOnly forKey:@"reminderIntensity"];[controller showArrivals:@[@"wxid_friend"]];results[@"comfortAvatarOnlySuppressesActualArrivalDecoration"]=@(arrivals.hidden&&[pet.layer animationForKey:@"quickChatPulse"]==nil);
        [WPPreferences() setInteger:WPReminderIntensityLight forKey:@"reminderIntensity"];[controller showArrivals:@[@"wxid_friend"]];results[@"comfortLightModeAvoidsScaleFlashAndTransientHeads"]=@(arrivals.hidden&&[pet.layer animationForKey:@"quickChatPulse"]==nil&&[pet.layer animationForKey:@"quickChatFlash"]==nil);
        [WPPreferences() setInteger:WPReminderIntensityFull forKey:@"reminderIntensity"];[controller showArrivals:@[@"wxid_friend"]];results[@"comfortFullModePreservesActualArrivalDecoration"]=@(!arrivals.hidden&&[pet.layer animationForKey:@"quickChatPulse"]!=nil&&[pet.layer animationForKey:@"quickChatFlash"]!=nil);
        [WPPreferences() setInteger:WPReminderIntensityAvatarOnly forKey:@"reminderIntensity"];[controller applySettings];results[@"comfortChangingModeImmediatelyClearsExistingArrivalDecoration"]=@(arrivals.hidden&&arrivals.subviews.count==0&&[pet.layer animationForKey:@"quickChatPulse"]==nil&&[pet.layer animationForKey:@"quickChatFlash"]==nil);
        [WPPreferences() setBool:YES forKey:@"positionLocked"];[WPPreferences() setBool:YES forKey:@"quietTimeEnabled"];[WPPreferences() setBool:YES forKey:@"reminderContactsOnly"];
        [WPPreferences() setInteger:22*60 forKey:@"quietStartMinute"];[WPPreferences() setInteger:8*60 forKey:@"quietEndMinute"];
        screenshotWindow=priorKey.windowScene?[[UIWindow alloc] initWithWindowScene:priorKey.windowScene]:[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];screenshotWindow.frame=UIScreen.mainScreen.bounds;screenshotWindow.windowLevel=UIWindowLevelAlert+4;
        WPCardPageController *petPage=[NSClassFromString(@"WPPetSettingsController") new];BOOL petShot=WPComfortSnapshot(petPage,screenshotWindow,@"comfort-settings-v110.png",@"WPPositionLockSwitch");UISwitch *lock=(id)WPComfortFind(petPage.view,@"WPPositionLockSwitch");results[@"comfortActualPositionLockSettingRenders"]=@(lock!=nil&&lock.on&&petShot);
        [lock setOn:NO];[lock sendActionsForControlEvents:UIControlEventValueChanged];results[@"comfortActualPositionLockSwitchWritesPreference"]=@(!WPPositionLocked());
        WPCardPageController *reminderPage=[NSClassFromString(@"WPReminderSettingsController") new];BOOL reminderShot=WPComfortSnapshot(reminderPage,screenshotWindow,@"comfort-reminders-v110.png",nil);results[@"comfortActualReminderSettingsRender"]=@(WPComfortFind(reminderPage.view,@"WPReminderIntensity")!=nil&&WPComfortFind(reminderPage.view,@"WPQuietStartTime")!=nil&&reminderShot);
        UISegmentedControl *mode=(id)WPComfortFindClass(WPComfortFind(reminderPage.view,@"WPReminderIntensity"),UISegmentedControl.class);mode.selectedSegmentIndex=WPReminderIntensityLight;[mode sendActionsForControlEvents:UIControlEventValueChanged];results[@"comfortActualIntensityControlWritesPreference"]=@(mode!=nil&&WPConfiguredReminderIntensity()==WPReminderIntensityLight);
        UIDatePicker *start=(id)WPComfortFind(reminderPage.view,@"WPQuietStartTime");start.date=WPComfortDate(21,15);[start sendActionsForControlEvents:UIControlEventValueChanged];results[@"comfortActualQuietTimeControlWritesPreference"]=@(start!=nil&&WPQuietMinute(YES)==21*60+15);
        UIButton *add=(id)WPComfortFind(reminderPage.view,@"WPAddReminderContact");[add sendActionsForControlEvents:UIControlEventTouchUpInside];WPPartnerPickerController *actualPicker=(id)reminderPage.navigationController.topViewController;
        BOOL actualPickerOpened=[actualPicker isKindOfClass:WPPartnerPickerController.class];
        if(actualPickerOpened){[actualPicker loadViewIfNeeded];[actualPicker setValue:@[@{@"username":@"wxid_comfort_actual",@"name":@"测试提醒好友",@"search":@"测试提醒好友"}] forKey:@"filtered"];[actualPicker tableView:actualPicker.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];}
        results[@"comfortActualAddContactButtonSavesReminderWithoutChangingPartner"]=@(actualPickerOpened&&[WPReminderContactUsernames() containsObject:@"wxid_comfort_actual"]&&((partnerBefore==nil&&[WPPreferences() stringForKey:@"partnerUsername"]==nil)||[partnerBefore isEqual:[WPPreferences() stringForKey:@"partnerUsername"]])&&((partnerNameBefore==nil&&[WPPreferences() stringForKey:@"partnerDisplayName"]==nil)||[partnerNameBefore isEqual:[WPPreferences() stringForKey:@"partnerDisplayName"]]));
    }@catch(NSException *exception){results[@"comfortNoUnexpectedException"]=@NO;NSLog(@"Comfort preview exception: %@",exception.name);}
    @finally{
        [NSNotificationCenter.defaultCenter removeObserver:controller];[controller setValue:@YES forKey:@"gestureInterrupted"];[controller setValue:@NO forKey:@"gestureActive"];[controller setValue:@YES forKey:@"peeking"];[(WPPetRenderer *)[controller valueForKey:@"pet"] setAnimationActive:NO];
        screenshotWindow.hidden=YES;screenshotWindow.rootViewController=nil;[priorKey makeKeyWindow];
        for(NSString *key in keys){id value=saved[key];if(value==NSNull.null)[WPPreferences() removeObjectForKey:key];else [WPPreferences() setObject:value forKey:key];}
        [NSNotificationCenter.defaultCenter postNotificationName:WPSettingsDidChangeNotification object:nil];
        for(NSDictionary *state in overlayStates){
            UIViewController *live=state[@"controller"];WPPetRenderer *livePet=[live valueForKey:@"pet"];
            [livePet.layer removeAllAnimations];[live setValue:state[@"anchor"] forKey:@"userAnchor"];[live setValue:state[@"bounds"] forKey:@"anchorBounds"];[live setValue:state[@"positioned"] forKey:@"positioned"];[live setValue:state[@"fullCenter"] forKey:@"fullCenter"];[live setValue:state[@"peeking"] forKey:@"peeking"];[live setValue:@NO forKey:@"edgeTransitioning"];livePet.center=[state[@"center"] CGPointValue];
            if([state[@"peeking"] boolValue])[livePet holdPeekOnLeft:[state[@"fullCenter"] CGPointValue].x<CGRectGetMidX(live.view.bounds)];else [livePet endPeek];
        }
    }
    return results;
}
