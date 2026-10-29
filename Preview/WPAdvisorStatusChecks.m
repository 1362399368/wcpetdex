#import "WPAdvisorStatusChecks.h"
#import "WPAdvisorStatusView.h"
#import <UIKit/UIKit.h>

static UIView *WPAdvisorFind(UIView *root,NSString *identifier){
    if([root.accessibilityIdentifier isEqualToString:identifier])return root;
    for(UIView *child in root.subviews){UIView *found=WPAdvisorFind(child,identifier);if(found)return found;}return nil;
}
NSDictionary<NSString *,NSNumber *> *WPAdvisorStatusPreviewChecks(void){
    NSCAssert(NSThread.isMainThread,@"Tests must run on main");
    WPAdvisorStatusView *view=[[WPAdvisorStatusView alloc] initWithFrame:CGRectMake(0,0,390,844)];
    NSArray *tasks=@[@{@"identifier":@"one",@"displayName":@"联系人甲",@"state":@"生成中"},
                     @{@"identifier":@"two",@"displayName":@"联系人乙",@"state":@"排队中"},
                     @{@"identifier":@"three",@"displayName":@"联系人丙",@"state":@"生成中"},
                     @{@"identifier":@"four",@"displayName":@"联系人丁",@"state":@"排队中"}];
    __block NSString *cancelled=nil;__block NSUInteger more=0,opened=0;
    view.onCancelTask=^(NSString *identifier){cancelled=identifier;};view.onShowTasks=^{more++;};view.onOpenUnread=^{opened++;};
    [view updateActiveTasks:tasks];[view updateUnreadCount:2];
    [view layoutInBounds:CGRectMake(0,44,390,766) petFrame:CGRectMake(260,350,90,120) petVisible:YES];[view layoutIfNeeded];
    UIControl *first=(id)WPAdvisorFind(view,@"WPAdvisorCapsule-one"),*extra=(id)WPAdvisorFind(view,@"WPAdvisorMoreTasks"),*badge=(id)WPAdvisorFind(view,@"WPAdvisorUnreadBadge");
    BOOL layout=first && !first.hidden && CGRectGetMinY(first.frame)>=44 && CGRectGetMaxY(first.frame)<=810;
    CGPoint center=CGPointMake(CGRectGetMidX(first.frame),CGRectGetMidY(first.frame));BOOL firstHit=[view hitTest:center withEvent:nil]==first;
    [first sendActionsForControlEvents:UIControlEventTouchUpInside];BOOL cancel=[cancelled isEqualToString:@"one"];
    [extra sendActionsForControlEvents:UIControlEventTouchUpInside];BOOL moreWorks=extra && more==1;
    BOOL badgeHit=[view hitTest:CGPointMake(CGRectGetMidX(badge.frame),CGRectGetMidY(badge.frame)) withEvent:nil]==badge;
    [badge sendActionsForControlEvents:UIControlEventTouchUpInside];BOOL badgeWorks=badgeHit && opened==1 && !badge.hidden;
    BOOL pass=[view hitTest:CGPointMake(15,700) withEvent:nil]==nil;
    [view updateUnreadCount:0];[view layoutIfNeeded];BOOL clears=badge.hidden;
    [view updateUnreadCount:1];[view layoutInBounds:CGRectMake(0,44,390,766) petFrame:CGRectMake(260,350,90,120) petVisible:NO];[view layoutIfNeeded];BOOL hiddenPet=badge.hidden;
    [view updateActiveTasks:@[@{},@{@"identifier":@"valid"},@{@"identifier":@42}]];[view layoutIfNeeded];
    BOOL invalid=[WPAdvisorFind(view,@"WPAdvisorCapsule-valid") isKindOfClass:UIControl.class] && !WPAdvisorFind(view,@"WPAdvisorMoreTasks");
    [view updateActiveTasks:@[@{@"identifier":@"failure",@"state":@"失败"}]];
    UIButton *failure=(id)WPAdvisorFind(view,@"WPAdvisorCapsule-failure");
    BOOL failureAction=[failure.accessibilityLabel containsString:@"点击查看"] && ![failure.currentTitle containsString:@"×"];
    // Right-edge clamping, a smaller pet and a user-offset avatar must not let
    // the new badge intercept the existing avatar's expanded touch target.
    UIView *host=[[UIView alloc] initWithFrame:CGRectMake(0,0,390,844)];
    UIButton *avatar=[UIButton buttonWithType:UIButtonTypeCustom];[host addSubview:avatar];
    WPAdvisorStatusView *overlay=[[WPAdvisorStatusView alloc] initWithFrame:host.bounds];[host addSubview:overlay];
    [overlay updateUnreadCount:2];
    NSArray<NSValue *> *pets=@[[NSValue valueWithCGRect:CGRectMake(302,350,88,100)],
                                [NSValue valueWithCGRect:CGRectMake(350,350,40,50)],
                                [NSValue valueWithCGRect:CGRectMake(302,350,88,100)]];
    NSArray<NSValue *> *avatars=@[[NSValue valueWithCGRect:CGRectMake(328,306,36,36)],
                                   [NSValue valueWithCGRect:CGRectMake(352,306,36,36)],
                                   [NSValue valueWithCGRect:CGRectMake(352,324,36,36)]];
    BOOL avoidance=YES;
    for(NSUInteger i=0;i<pets.count;i++){
        avatar.frame=avatars[i].CGRectValue;[overlay setUnreadAvatarFrame:avatar.frame];
        [overlay layoutInBounds:CGRectMake(0,44,390,766) petFrame:pets[i].CGRectValue petVisible:YES];[overlay layoutIfNeeded];
        UIControl *target=(id)WPAdvisorFind(overlay,@"WPAdvisorUnreadBadge");CGRect avatarTouch=CGRectInset(avatar.frame,-4,-4);
        CGPoint avatarCenter=CGPointMake(CGRectGetMidX(avatar.frame),CGRectGetMidY(avatar.frame));
        CGPoint badgeCenter=CGPointMake(CGRectGetMidX(target.frame),CGRectGetMidY(target.frame));
        avoidance &= !target.hidden && !CGRectIntersectsRect(target.frame,avatarTouch) && [host hitTest:avatarCenter withEvent:nil]==avatar && [host hitTest:badgeCenter withEvent:nil]==target;
    }
    // Peeked pets sit partly off-screen on either edge. Their badge must be
    // clamped on-screen and remain independently tappable beside the avatar.
    BOOL peekEdges=YES;
    for(NSNumber *side in @[@0,@1]){
        BOOL right=side.boolValue;
        CGRect pet=CGRectMake(right?355:-55,350,88,100);
        avatar.frame=CGRectMake(right?342:12,300,36,36);
        [overlay setUnreadAvatarFrame:avatar.frame];
        [overlay layoutInBounds:CGRectMake(0,44,390,766) petFrame:pet petVisible:YES];[overlay layoutIfNeeded];
        UIControl *target=(id)WPAdvisorFind(overlay,@"WPAdvisorUnreadBadge");
        CGPoint pt=CGPointMake(CGRectGetMidX(target.frame),CGRectGetMidY(target.frame));
        peekEdges &= !target.hidden && CGRectContainsRect(overlay.bounds,target.frame) && !CGRectIntersectsRect(target.frame,CGRectInset(avatar.frame,-4,-4)) && [host hitTest:pt withEvent:nil]==target;
    }
    UIView *topHost=[[UIView alloc] initWithFrame:CGRectMake(0,0,390,844)];
    WPAdvisorStatusView *topOverlay=[[WPAdvisorStatusView alloc] initWithFrame:topHost.bounds];[topHost addSubview:topOverlay];
    [topOverlay updateActiveTasks:tasks];[topOverlay updateUnreadCount:1];
    [topOverlay layoutInBounds:CGRectMake(0,44,390,766) petFrame:CGRectMake(150,50,88,100) petVisible:YES];[topOverlay layoutIfNeeded];
    UIControl *topBadge=(id)WPAdvisorFind(topOverlay,@"WPAdvisorUnreadBadge");
    BOOL topAvoidance=!topBadge.hidden && [topHost hitTest:CGPointMake(CGRectGetMidX(topBadge.frame),CGRectGetMidY(topBadge.frame)) withEvent:nil]==topBadge;
    for(NSString *identifier in @[@"WPAdvisorCapsule-one",@"WPAdvisorCapsule-two",@"WPAdvisorCapsule-three",@"WPAdvisorMoreTasks"]){
        UIControl *pill=(id)WPAdvisorFind(topOverlay,identifier);CGPoint point=CGPointMake(CGRectGetMidX(pill.frame),CGRectGetMidY(pill.frame));
        topAvoidance &= pill && !CGRectIntersectsRect(pill.frame,topBadge.frame) && [topHost hitTest:point withEvent:nil]==pill;
    }
    // A very short usable area cannot fit both controls without overlapping.
    // Keep the progress capsule available and defer the result to history.
    [topOverlay updateActiveTasks:@[tasks.firstObject]];
    [topOverlay layoutInBounds:CGRectMake(0,44,150,50) petFrame:CGRectMake(20,50,40,50) petVisible:YES];[topOverlay layoutIfNeeded];
    UIControl *shortPill=(id)WPAdvisorFind(topOverlay,@"WPAdvisorCapsule-one");
    CGPoint shortCenter=CGPointMake(CGRectGetMidX(shortPill.frame),CGRectGetMidY(shortPill.frame));
    BOOL shortArea=topBadge.hidden && [topHost hitTest:shortCenter withEvent:nil]==shortPill;
    __block NSUInteger shortMore=0;topOverlay.onShowTasks=^{shortMore++;};
    [topOverlay updateActiveTasks:tasks];[topOverlay layoutIfNeeded];
    UIControl *shortSummary=(id)WPAdvisorFind(topOverlay,@"WPAdvisorMoreTasks");
    UIControl *shortFirst=(id)WPAdvisorFind(topOverlay,@"WPAdvisorCapsule-one");
    CGPoint summaryCenter=CGPointMake(CGRectGetMidX(shortSummary.frame),CGRectGetMidY(shortSummary.frame));
    BOOL shortSummaryHit=shortSummary && !shortSummary.hidden && shortFirst.hidden && [topHost hitTest:summaryCenter withEvent:nil]==shortSummary;
    if(shortSummaryHit)[shortSummary sendActionsForControlEvents:UIControlEventTouchUpInside];
    BOOL shortSummaryWorks=shortSummaryHit && shortMore==1;
    WPAdvisorHistoryController *history=[[WPAdvisorHistoryController alloc] initWithTitle:@"参谋记录" records:@[@{@"identifier":@"entry",@"displayName":@"甲",@"unread":@YES}] allowsClear:YES];
    __block NSString *selected=nil;history.onSelect=^(NSString *identifier){selected=identifier;};(void)history.view;
    NSIndexPath *row=[NSIndexPath indexPathForRow:0 inSection:0];[history tableView:history.tableView didSelectRowAtIndexPath:row];
    BOOL historyWorks=[selected isEqualToString:@"entry"] && [history tableView:history.tableView numberOfRowsInSection:0]==1;
    [history updateRecords:@[]];BOOL empty=[history tableView:history.tableView numberOfRowsInSection:0]==1 && ![history tableView:history.tableView cellForRowAtIndexPath:row].accessoryType;
    return @{@"advisorCapsuleLayout":@(layout),@"advisorCapsuleHit":@(firstHit),@"advisorCapsuleCancellation":@(cancel),
             @"advisorTaskOverflow":@(moreWorks),@"advisorBadgeHitAndAction":@(badgeWorks),@"advisorOverlayPassThrough":@(pass),
             @"advisorBadgeClearsAndHides":@(clears&&hiddenPet),@"advisorStatusRejectsMalformedInput":@(invalid),
             @"advisorHistorySelection":@(historyWorks),@"advisorHistoryEmptyState":@(empty),@"advisorFailureUsesViewLabel":@(failureAction),
             @"advisorUnreadBadgeAvoidsLatestAvatar":@(avoidance),@"advisorPeekBadgeVisibleAndTappableAtBothEdges":@(peekEdges),@"advisorTopBadgeAvoidsCapsules":@(topAvoidance),
             @"advisorShortAreaKeepsCapsuleClickable":@(shortArea),@"advisorShortAreaShowsAllTasks":@(shortSummaryWorks)};
}
