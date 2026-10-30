#import "WPQuickChat121Checks.h"
#import "WPQuickChatBar.h"
#import "WPQuickChatPreferences.h"
#import "WPQuickChatModel.h"
#import "WPBarragePreferences.h"
#import "WPMessageBarrageSource.h"
#import "WPCaptureProtectedView.h"
#import "WPTapActions.h"
#import "WPComfortPreferences.h"
#import "WPPetRenderer.h"
#import "WPCommon.h"
#import "WPRadialMenu.h"

@interface WPQuickChatBar (WPQuickChat121Testing)
- (void)settingsChanged:(NSNotification *)note;
- (void)holdAvatar:(UILongPressGestureRecognizer *)gesture;
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path;
@end
@interface UIViewController (WPQuickChat121OverlayTesting)
- (void)applySettings;
- (CGRect)quickBarFrame;
- (CGRect)safeArea;
- (void)performTapAction:(WPTapAction)action;
- (void)releaseTransientViews;
- (void)refreshBarrageState;
- (BOOL)accessibilityMenu;
- (void)quickChatChanged:(NSNotification *)note;
@end
@interface WPQC121Hold : UILongPressGestureRecognizer
@property(nonatomic) CGPoint fixturePoint;
@end
@implementation WPQC121Hold
- (UIGestureRecognizerState)state{return UIGestureRecognizerStateBegan;}
- (CGPoint)locationInView:(UIView *)view{return self.fixturePoint;}
@end
@interface WPQC121NoCanvas : WPCaptureProtectedView @end
@implementation WPQC121NoCanvas
- (UIView *)findCanvas:(UIView *)view{return nil;}
@end
static void WPQC121Set(NSString *key,id value){[WPPreferences() setObject:value forKey:[@"quickChat." stringByAppendingString:key]];}
static WPQuickChatSession *WPQC121Session(NSString *username,NSUInteger unread,BOOL muted){
    return [WPQuickChatSession sessionWithUsername:username unread:unread muted:muted pinned:NO time:1700000000+unread];
}
static void WPQC121Layout(WPQuickChatBar *bar){[bar setNeedsLayout];[bar layoutIfNeeded];UITableView *table=[bar valueForKey:@"table"];[table layoutIfNeeded];for(UITableViewCell *cell in table.visibleCells){[cell setNeedsLayout];[cell layoutIfNeeded];}}
static BOOL WPQC121Contains(NSArray<WPQuickChatSession *> *rows,NSString *username){for(WPQuickChatSession *row in rows)if([row.username isEqual:username])return YES;return NO;}
static NSInteger WPQC121Index(NSArray<WPQuickChatSession *> *rows,NSString *username){for(NSUInteger i=0;i<rows.count;i++)if([rows[i].username isEqual:username])return (NSInteger)i;return NSNotFound;}
static BOOL WPQC121FiniteRect(CGRect rect){return isfinite(rect.origin.x)&&isfinite(rect.origin.y)&&isfinite(rect.size.width)&&isfinite(rect.size.height)&&rect.size.width>0&&rect.size.height>0;}

NSDictionary<NSString *,NSNumber *> *WPQuickChat121PreviewChecks(UIWindow *window){
    NSMutableDictionary *checks=[NSMutableDictionary new];
    NSArray *options=@[@"hideCapture",@"width",@"height",@"side",@"style",@"vertical",@"radius",@"opacity",@"background",@"backgroundRGBA",@"avatarSize",@"showNames",@"nameGap",@"sessionGap",@"tapMode",@"holdMode",@"filter",@"showMuted",@"removed",@"unreadFirst",@"customMode",@"separate",@"pinnedAlways",@"limit",@"showRedDot",@"numericBadge",@"edgeTapActions"];
    NSMutableArray *keys=[NSMutableArray new];for(NSString *option in options)[keys addObject:[@"quickChat." stringByAppendingString:option]];
    [keys addObjectsFromArray:@[@"quickChat.arrivalAvatar",@"quickChatFlash",@"reminderIntensity"]];
    [keys addObjectsFromArray:@[@"enabled",@"quickChatEnabled",@"autoPeek",@"positionLocked",@"barrageEnabled",@"barragePauseUntil",@"barrageQuietEnabled",@"barrageQuietStart",@"barrageQuietEnd",@"barrageContactsOnly",@"barrageContactUsernames",@"barrageAllowPrivate",@"barrageAllowGroup",@"barrageAdaptiveSaving",@"quietTimeEnabled",@"quietStartMinute",@"quietEndMinute",@"reminderContactsOnly",@"reminderContactUsernames"]];
    NSMutableDictionary *saved=[NSMutableDictionary new];for(NSString *key in keys)saved[key]=[WPPreferences() objectForKey:key]?:NSNull.null;
    UIViewController *overlay=window.rootViewController;WPQuickChatBar *bar=nil;WPCaptureProtectedView *protected=nil;WPCaptureProtectedView *fallback=nil;UIWindow *fixtureWindow=nil;
    BOOL animationsEnabled=UIView.areAnimationsEnabled;
    @try {
        [UIView setAnimationsEnabled:NO];
        [WPPreferences() setBool:YES forKey:@"enabled"];[WPPreferences() setBool:YES forKey:@"quickChatEnabled"];[WPPreferences() setBool:NO forKey:@"autoPeek"];
        [WPPreferences() setBool:NO forKey:@"barrageEnabled"];[WPPreferences() removeObjectForKey:@"barragePauseUntil"];
        for(NSString *option in @[@"showNames",@"unreadFirst",@"showRedDot",@"numericBadge"])WPQC121Set(option,@YES);
        for(NSString *option in @[@"showMuted",@"customMode",@"separate",@"pinnedAlways",@"edgeTapActions",@"hideCapture"])WPQC121Set(option,@NO);
        WPQC121Set(@"avatarSize",@44);WPQC121Set(@"sessionGap",@6);WPQC121Set(@"nameGap",@4);WPQC121Set(@"radius",@28);WPQC121Set(@"opacity",@.67);WPQC121Set(@"background",@0);WPQC121Set(@"filter",@0);WPQC121Set(@"limit",@0);WPQC121Set(@"removed",@[]);
        fixtureWindow=[[UIWindow alloc] initWithFrame:CGRectMake(0,0,393,852)];fixtureWindow.windowLevel=-200;fixtureWindow.rootViewController=[UIViewController new];fixtureWindow.hidden=NO;
        bar=[[WPQuickChatBar alloc] initWithFrame:CGRectMake(6,100,76,400)];[fixtureWindow.rootViewController.view addSubview:bar];
        NSArray *sessions=@[WPQC121Session(@"wxid_qc121_alice",8,NO),WPQC121Session(@"qc121_team@chatroom",2,NO),WPQC121Session(@"wxid_qc121_muted",9,YES),WPQC121Session(@"wxid_qc121_bob",0,NO)];
        [bar reloadWithSessions:sessions];WPQC121Layout(bar);UITableView *table=[bar valueForKey:@"table"];
        UITableViewCell *cell=[table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
        UIImageView *avatar=[cell valueForKey:@"avatar"];UILabel *name=[cell valueForKey:@"name"];UILabel *badge=[cell valueForKey:@"dot"];
        checks[@"QC12101_circleAvatarAndFineCenteredNickname"]=@(avatar.bounds.size.width==44&&fabs(avatar.layer.cornerRadius-22)<.1&&avatar.clipsToBounds&&name.font.pointSize==11&&name.textAlignment==NSTextAlignmentCenter);
        checks[@"QC12102_semitransparentRoundedIslandDoesNotFadeAvatar"]=@(fabs(CGColorGetAlpha(bar.backgroundColor.CGColor)-.67)<.01&&bar.layer.cornerRadius==28&&bar.alpha==1&&avatar.alpha==1&&name.alpha==1);
        checks[@"QC12103_numericUnreadBadgeAndMutedDefaultHidden"]=@([badge.text isEqual:@"8"]&&!badge.hidden&&!WPQC121Contains(bar.sessions,@"wxid_qc121_muted"));
        CGFloat namedHeight=table.rowHeight;
        WPQC121Set(@"showNames",@NO);[bar settingsChanged:nil];WPQC121Layout(bar);
        cell=[table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];name=[cell valueForKey:@"name"];
        checks[@"QC12104_hideNamesReclaimsNameAndGapHeight"]=@(name.hidden&&fabs(namedHeight-table.rowHeight-19)<.1);
        WPQC121Set(@"showNames",@YES);WPQC121Set(@"avatarSize",@60);WPQC121Set(@"sessionGap",@12);WPQC121Set(@"nameGap",@8);WPQC121Set(@"radius",@36);bar.frame=CGRectMake(6,100,100,400);[bar settingsChanged:nil];WPQC121Layout(bar);
        cell=[table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];avatar=[cell valueForKey:@"avatar"];name=[cell valueForKey:@"name"];
        checks[@"QC12105_liveSizeGapsAndRadiusUseExistingCells"]=@(avatar.bounds.size.width==60&&avatar.layer.cornerRadius==30&&fabs(CGRectGetMinY(name.frame)-CGRectGetMaxY(avatar.frame)-8)<.1&&table.rowHeight==103&&bar.layer.cornerRadius==36);
        __block NSString *selected=nil;__block NSInteger selectedMode=-1;__block NSUInteger selections=0;
        bar.onSelectWithMode=^(NSString *username,NSInteger mode){selected=username;selectedMode=mode;selections++;};
        NSInteger alice=WPQC121Index(bar.sessions,@"wxid_qc121_alice");
        for(NSInteger mode=0;mode<3;mode++){WPQC121Set(@"tapMode",@(mode));[bar tableView:table didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:alice inSection:0]];checks[[NSString stringWithFormat:@"QC12106_tapMode%ldKeepsMatchingRoute",(long)mode]]=@([selected isEqual:@"wxid_qc121_alice"]&&selectedMode==mode);}
        NSInteger team=WPQC121Index(bar.sessions,@"qc121_team@chatroom");CGRect teamRect=[table rectForRowAtIndexPath:[NSIndexPath indexPathForRow:team inSection:0]];WPQC121Hold *hold=[WPQC121Hold new];hold.fixturePoint=CGPointMake(CGRectGetMidX(teamRect),CGRectGetMidY(teamRect));
        for(NSInteger mode=0;mode<3;mode++){WPQC121Set(@"holdMode",@(mode));[bar holdAvatar:hold];checks[[NSString stringWithFormat:@"QC12107_holdMode%ldKeepsGroupRoute",(long)mode]]=@([selected isEqual:@"qc121_team@chatroom"]&&selectedMode==mode);}
        NSUInteger selectionBefore=selections;hold.fixturePoint=CGPointMake(-50,-50);[bar holdAvatar:hold];[bar tableView:table didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:500 inSection:0]];
        checks[@"QC12108_invalidHoldOrRowNeverOpensAnotherChat"]=@(selections==selectionBefore);
        WPQuickChatRemoveUsername(@"wxid_qc121_alice");
        checks[@"QC12109_removeRefreshesVisibleRowsAndKeepsOtherChats"]=@(!WPQC121Contains(bar.sessions,@"wxid_qc121_alice")&&WPQC121Contains(bar.sessions,@"qc121_team@chatroom"));
        WPQuickChatRestoreRemoved();checks[@"QC12110_restoreUsesOriginalSessionSnapshot"]=@(WPQC121Contains(bar.sessions,@"wxid_qc121_alice"));
        WPQC121Set(@"filter",@1);[bar settingsChanged:nil];checks[@"QC12111_privateDisplayFilterExcludesGroups"]=@(!WPQC121Contains(bar.sessions,@"qc121_team@chatroom"));
        WPQC121Set(@"filter",@2);WPQC121Set(@"showMuted",@YES);[bar settingsChanged:nil];checks[@"QC12112_groupDisplayFilterExcludesPrivateAndMutedPrivate"]=@(bar.sessions.count==1&&[bar.sessions.firstObject.username isEqual:@"qc121_team@chatroom"]);
        [WPPreferences() setBool:NO forKey:@"barrageQuietEnabled"];[WPPreferences() setBool:NO forKey:@"barrageContactsOnly"];[WPPreferences() setBool:YES forKey:@"barrageAllowPrivate"];[WPPreferences() setBool:YES forKey:@"barrageAllowGroup"];
        checks[@"QC12113_quickChatDisplayFilterDoesNotChangeBarrageReminderPolicy"]=@(WPBarrageReminderAllowsUsername(@"wxid_qc121_alice",NSDate.date));
        checks[@"QC12114_showMutedDisplayCannotAuthorizeUnknownNativeBarrageChat"]=@(!WPMessageBarrageConversationAllowed(@"wxid_qc121_never_native_contact"));
        WPQC121Set(@"filter",@0);[bar settingsChanged:nil];checks[@"QC12115_showMutedIsOnlyAppliedToDisplayRows"]=@(WPQC121Contains(bar.sessions,@"wxid_qc121_muted"));
        WPQuickChatSession *older=[WPQuickChatSession sessionWithUsername:@"wxid_order_old" unread:1 muted:NO pinned:YES time:100];
        WPQuickChatSession *newer=[WPQuickChatSession sessionWithUsername:@"wxid_order_new" unread:1 muted:NO pinned:NO time:200];
        NSArray *order=@[older,newer];
        checks[@"QC12139_followModePreservesNativeOrderWithinUnreadGroup"]=@(WPQuickChatApplyDisplayPolicy(order).firstObject==older);
        WPQC121Set(@"customMode",@YES);
        checks[@"QC12140_customModeOrdersEqualPriorityByMessageTime"]=@(WPQuickChatApplyDisplayPolicy(order).firstObject==newer);
        WPQC121Set(@"pinnedAlways",@YES);
        checks[@"QC12141_pinnedPriorityStillOverridesCustomTimeOrder"]=@(WPQuickChatApplyDisplayPolicy(order).firstObject==older);
        WPQC121Set(@"customMode",@NO);WPQC121Set(@"pinnedAlways",@NO);
        WPQC121Set(@"showRedDot",@NO);[bar settingsChanged:nil];WPQC121Layout(bar);cell=[table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];badge=[cell valueForKey:@"dot"];checks[@"QC12116_hideBadgeKeepsAvatarAndRows"]=@(badge.hidden&&bar.sessions.count==4);

        bar.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;WPQC121Set(@"background",@1);[bar settingsChanged:nil];WPQC121Layout(bar);
        cell=[table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];name=[cell valueForKey:@"name"];CGFloat inkRed=1,inkGreen=1,inkBlue=1,inkAlpha=0;
        [[name.textColor resolvedColorWithTraitCollection:bar.traitCollection] getRed:&inkRed green:&inkGreen blue:&inkBlue alpha:&inkAlpha];
        checks[@"QC12132_whiteIslandKeepsDarkInkInSystemDarkMode"]=@(inkRed<.01&&inkGreen<.01&&inkBlue<.01&&inkAlpha>.99);
        WPQC121Set(@"background",@3);WPQC121Set(@"backgroundRGBA",@[@.02,@.02,@.02,@1]);[bar settingsChanged:nil];WPQC121Layout(bar);
        cell=[table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];name=[cell valueForKey:@"name"];
        [[name.textColor resolvedColorWithTraitCollection:bar.traitCollection] getRed:&inkRed green:&inkGreen blue:&inkBlue alpha:&inkAlpha];
        checks[@"QC12133_customDarkIslandSelectsLightReadableInk"]=@(inkRed>.99&&inkGreen>.99&&inkBlue>.99&&inkAlpha>.99);
        WPQC121Set(@"width",@-100);WPQC121Set(@"height",@100000);WPQC121Set(@"avatarSize",@100000);WPQC121Set(@"opacity",@8);WPQC121Set(@"side",@9);
        checks[@"QC12134_legacyNumericValuesClampOnReadBeforeLayout"]=@(WPQuickChatOptionNumber(@"width")==60&&WPQuickChatOptionNumber(@"height")==900&&WPQuickChatOptionNumber(@"avatarSize")==72&&WPQuickChatOptionNumber(@"opacity")==1&&WPQuickChatOptionNumber(@"side")==1);
        WPQC121Set(@"avatarSize",@"invalid-number");checks[@"QC12135_invalidNumericTypeUsesDocumentedDefault"]=@(WPQuickChatOptionNumber(@"avatarSize")==44);
        WPQC121Set(@"background",@0);WPQC121Set(@"opacity",@.67);WPQC121Set(@"avatarSize",@44);WPQC121Set(@"side",@0);
        [overlay applySettings];[overlay.view layoutIfNeeded];
        WPQC121Set(@"width",@100);WPQC121Set(@"height",@250);WPQC121Set(@"vertical",@1);WPQC121Set(@"style",@0);
        CGPoint oldCenter=[[overlay valueForKey:@"fullCenter"] CGPointValue];BOOL oldPeek=[[overlay valueForKey:@"peeking"] boolValue];id oldLock=[WPPreferences() objectForKey:@"positionLocked"];
        CGRect safe=[overlay safeArea];WPPetRenderer *livePet=[overlay valueForKey:@"pet"];
        CGPoint leftInterior=CGPointMake(CGRectGetMinX(safe)+safe.size.width*.30,CGRectGetMidY(safe));
        CGPoint rightInterior=CGPointMake(CGRectGetMinX(safe)+safe.size.width*.70,CGRectGetMidY(safe));
        [overlay setValue:[NSValue valueWithCGPoint:leftInterior] forKey:@"fullCenter"];[overlay setValue:@NO forKey:@"peeking"];[WPPreferences() setBool:NO forKey:@"positionLocked"];
        WPQC121Set(@"side",@1);CGRect left=[overlay quickBarFrame];
        [overlay setValue:@YES forKey:@"peeking"];CGRect right=[overlay quickBarFrame];
        checks[@"QC12117_automaticSidesAndDimensionsStayInsideOverlay"]=@(WPQC121FiniteRect(left)&&WPQC121FiniteRect(right)&&left.size.width==100&&left.size.height==250&&right.size.width==100&&right.size.height==250&&CGRectGetMinX(left)<CGRectGetMinX(right)&&CGRectContainsRect(overlay.view.bounds,left)&&CGRectContainsRect(overlay.view.bounds,right));
        [overlay setValue:@NO forKey:@"peeking"];[WPPreferences() setBool:YES forKey:@"positionLocked"];CGRect lockedLeft=[overlay quickBarFrame];
        [overlay setValue:[NSValue valueWithCGPoint:rightInterior] forKey:@"fullCenter"];CGRect lockedRight=[overlay quickBarFrame];
        [WPPreferences() setBool:NO forKey:@"positionLocked"];[overlay setValue:[NSValue valueWithCGPoint:CGPointMake(CGRectGetMinX(safe)+livePet.bounds.size.width/2,CGRectGetMidY(safe))] forKey:@"fullCenter"];CGRect attached=[overlay quickBarFrame];
        checks[@"QC12420LeftLockedOrAttachedUsesRightAndRightLockedUsesLeft"]=@(fabs(lockedLeft.origin.x-right.origin.x)<.1&&fabs(attached.origin.x-right.origin.x)<.1&&fabs(lockedRight.origin.x-left.origin.x)<.1);
        [overlay setValue:@YES forKey:@"peeking"];WPQC121Set(@"vertical",@0);CGRect middle=[overlay quickBarFrame];WPQC121Set(@"style",@1);CGRect edge=[overlay quickBarFrame];
        checks[@"QC12118_verticalCenterAndEdgeAttachmentRespectGeometry"]=@(middle.origin.y>=right.origin.y&&fabs(CGRectGetMaxX(edge)-CGRectGetMaxX(right)-6)<.1);
        [overlay setValue:[NSValue valueWithCGPoint:oldCenter] forKey:@"fullCenter"];[overlay setValue:@(oldPeek) forKey:@"peeking"];if(oldLock)[WPPreferences() setObject:oldLock forKey:@"positionLocked"];else [WPPreferences() removeObjectForKey:@"positionLocked"];
        WPQC121Set(@"height",@900);CGRect bounded=[overlay quickBarFrame];checks[@"QC12119_overTallCustomHeightClampsToAvailableScreen"]=@(CGRectContainsRect(overlay.view.bounds,bounded)&&bounded.size.height<=overlay.view.bounds.size.height);
        WPQuickChatBar *overlayBar=[overlay valueForKey:@"quickBar"];[overlayBar setHidden:YES];
        [overlay setValue:@YES forKey:@"peeking"];WPQC121Set(@"edgeTapActions",@NO);[overlay performTapAction:WPTapActionQuickChat];
        checks[@"QC12120_defaultEdgeTapOnlyRevealsPet"]=@(![[overlay valueForKey:@"peeking"] boolValue]&&overlayBar.hidden);
        [overlay setValue:@YES forKey:@"peeking"];WPQC121Set(@"edgeTapActions",@YES);[overlay performTapAction:WPTapActionQuickChat];
        checks[@"QC12121_enabledEdgeTapAlsoRunsConfiguredQuickChat"]=@(![[overlay valueForKey:@"peeking"] boolValue]&&!overlayBar.hidden);
        [overlay releaseTransientViews];
        WPBarrageSetEnabled(YES);WPBarragePauseForInterval(600);[overlay refreshBarrageState];[overlay accessibilityMenu];WPRadialMenuView *menu=[overlay valueForKey:@"menu"];
        checks[@"QC12122_pauseKeepsMasterAndOnlyFourPetActions"]=@(WPBarrageEnabled()&&WPBarrageIsPaused()&&menu.accessibilityElements.count==4&&![[overlay valueForKey:@"barrage"] isActive]);[menu cancel];WPBarrageResume();
        [WPPreferences() setBool:NO forKey:@"quietTimeEnabled"];[WPPreferences() setBool:NO forKey:@"reminderContactsOnly"];
        WPBarrageSetReminderValue(@"barrageQuietEnabled",@YES);WPBarrageSetReminderValue(@"barrageQuietStart",@0);WPBarrageSetReminderValue(@"barrageQuietEnd",@0);
        checks[@"QC12123_independentBarrageQuietDoesNotMutateCoupleQuiet"]=@(WPBarrageQuietTimeAtDate(NSDate.date)&&![WPPreferences() boolForKey:@"quietTimeEnabled"]&&!WPBarrageReminderAllowsUsername(@"wxid_qc121_alice",NSDate.date));
        WPBarrageSetReminderValue(@"barrageQuietEnabled",@NO);WPBarrageSetReminderValue(@"barrageContactsOnly",@YES);WPBarrageSetReminderValue(@"barrageContactUsernames",@[@"wxid_qc121_alice"]);
        checks[@"QC12124_independentContactListHasExactMembership"]=@(WPBarrageReminderAllowsUsername(@"wxid_qc121_alice",NSDate.date)&&!WPBarrageReminderAllowsUsername(@"wxid_qc121_bob",NSDate.date)&&![WPPreferences() boolForKey:@"reminderContactsOnly"]);
        WPBarrageSetReminderValue(@"barrageContactsOnly",@NO);WPBarrageSetReminderValue(@"barrageAllowGroup",@NO);
        checks[@"QC12125_disableGroupBarrageKeepsPrivateEnabled"]=@(!WPBarrageReminderAllowsUsername(@"qc121_team@chatroom",NSDate.date)&&WPBarrageReminderAllowsUsername(@"wxid_qc121_alice",NSDate.date));

        // Exercise native UIKit reparenting and hit testing. This confirms the
        // safe canvas lifecycle, not real-device screenshot/recording secrecy.
        protected=[[WPCaptureProtectedView alloc] initWithFrame:CGRectMake(150,400,200,200)];[fixtureWindow.rootViewController.view addSubview:protected];
        UIControl *button=[[UIControl alloc] initWithFrame:CGRectMake(40,40,44,44)];button.backgroundColor=[UIColor.systemBlueColor colorWithAlphaComponent:.4];button.alpha=.73;[protected addSubview:button];
        UIView *decoration=[[UIView alloc] initWithFrame:CGRectMake(120,120,20,20)];decoration.userInteractionEnabled=NO;[protected addSubview:decoration];
        WPQC121Set(@"hideCapture",@NO);[protected refreshProtection];[protected layoutIfNeeded];UIView *originalParent=button.superview;
        checks[@"QC12126_captureOffKeepsInteractiveProductView"]=@([protected hitTest:CGPointMake(50,50) withEvent:nil]==button&&originalParent==protected);
        WPQC121Set(@"hideCapture",@YES);[protected refreshProtection];[protected layoutIfNeeded];
        BOOL hasCanvas=protected.protectionAvailable;
        checks[@"QC12127_captureOnKeepsViewsInKnownContainer"]=@(hasCanvas?(button.superview!=protected&&[[protected valueForKey:@"secureField"] isSecureTextEntry]):button.superview==protected);
        checks[@"QC12128_captureTogglePreservesChildOpacityGeometryAndTap"]=@(fabs(button.alpha-.73)<.001&&fabs(CGColorGetAlpha(button.backgroundColor.CGColor)-.4)<.01&&CGRectEqualToRect(button.frame,CGRectMake(40,40,44,44))&&[protected hitTest:CGPointMake(50,50) withEvent:nil]==button);
        UIView *emptyHit=[protected hitTest:CGPointMake(10,10) withEvent:nil];checks[@"QC12129_secureCanvasDoesNotIntroduceInvisibleTouchBlocker"]=@(emptyHit==nil||emptyHit==protected);
        WPQC121Set(@"hideCapture",@NO);[protected refreshProtection];[protected layoutIfNeeded];
        checks[@"QC12130_captureOffRestoresSameViewsInSameOrder"]=@(button.superview==protected&&decoration.superview==protected&&[protected.subviews indexOfObject:button]<[protected.subviews indexOfObject:decoration]&&![protected valueForKey:@"secureField"]);
        WPQC121Set(@"hideCapture",@YES);[protected refreshProtection];[protected layoutIfNeeded];
        checks[@"QC12131_secureTextContainerCannotTakeKeyboardFocus"]=@(![[protected valueForKey:@"secureField"] canBecomeFirstResponder]);
        BOOL stableChildren=YES;
        for(NSUInteger iteration=0;iteration<10;iteration++){
            WPQC121Set(@"hideCapture",@NO);[protected refreshProtection];[protected layoutIfNeeded];
            stableChildren&=protected.subviews.count==2&&button.superview==protected&&decoration.superview==protected;
            WPQC121Set(@"hideCapture",@YES);[protected refreshProtection];[protected layoutIfNeeded];
        }
        checks[@"QC12136_repeatedCaptureTogglesNeverAdoptUIKitInternalViews"]=@(stableChildren);
        fallback=[[WPQC121NoCanvas alloc] initWithFrame:CGRectMake(150,610,100,100)];[fixtureWindow.rootViewController.view addSubview:fallback];
        UIControl *fallbackButton=[[UIControl alloc] initWithFrame:CGRectMake(10,10,44,44)];[fallback addSubview:fallbackButton];[fallback refreshProtection];[fallback layoutIfNeeded];
        checks[@"QC12137_missingCanvasFallbackPreservesBoundsAndTapWithoutField"]=@(!fallback.protectionAvailable&&fallbackButton.superview==fallback&&CGRectEqualToRect(fallbackButton.frame,CGRectMake(10,10,44,44))&&![fallback valueForKey:@"secureField"]&&[fallback hitTest:CGPointMake(20,20) withEvent:nil]==fallbackButton);
        [overlay releaseTransientViews];[WPPreferences() setBool:NO forKey:@"barrageEnabled"];[WPPreferences() setBool:YES forKey:@"quickChatEnabled"];
        [WPPreferences() setBool:NO forKey:@"quickChatFlash"];[WPPreferences() setInteger:2 forKey:@"reminderIntensity"];
        [WPPreferences() setBool:NO forKey:@"quietTimeEnabled"];[WPPreferences() setBool:NO forKey:@"reminderContactsOnly"];WPQC121Set(@"arrivalAvatar",@YES);
        [overlay quickChatChanged:[NSNotification notificationWithName:@"test" object:nil userInfo:@{@"arrivals":@[@"wxid_arrival_option_fixture"]}]];
        UIView *heads=[overlay valueForKey:@"arrivals"];UIView *pet=[overlay valueForKey:@"pet"];
        checks[@"QC12138_arrivalAvatarWorksIndependentlyOfFlashSwitch"]=@(!heads.hidden && heads.subviews.count==1 && [pet.layer animationForKey:@"quickChatPulse"]==nil && [pet.layer animationForKey:@"quickChatFlash"]==nil);
        checks[@"QC12199_checksCompletedWithoutException"]=@YES;
    } @catch(NSException *exception){checks[@"QC12199_checksCompletedWithoutException"]=@NO;NSLog(@"QuickChat121 checks: %@ %@",exception.name,exception.reason);}
    @finally {
        [overlay releaseTransientViews];bar.hidden=YES;[bar removeFromSuperview];[protected removeFromSuperview];[fallback removeFromSuperview];fixtureWindow.hidden=YES;
        for(NSString *key in keys){id value=saved[key];if(value==NSNull.null)[WPPreferences() removeObjectForKey:key];else [WPPreferences() setObject:value forKey:key];}
        [UIView setAnimationsEnabled:animationsEnabled];[overlay applySettings];
    }
    return checks;
}
