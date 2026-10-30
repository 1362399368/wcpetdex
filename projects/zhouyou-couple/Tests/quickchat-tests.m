#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "WPQuickChatModel.h"

// 0.4.0 quick chat: session ordering, arrival detection and blue-dot state on
// the Foundation model, plus the radial menu geometry with 4 and 5 items.
static NSMutableDictionary<NSString *, NSNumber *> *WPResults;
static void WPCheck(NSString *name, BOOL passed) {
    WPResults[name] = @(passed);
    if (!passed) fprintf(stderr, "FAIL: %s\n", name.UTF8String);
}
static WPQuickChatSession *WPRow(NSString *name, NSUInteger unread, BOOL muted, BOOL pinned, NSTimeInterval time) {
    return [WPQuickChatSession sessionWithUsername:name unread:unread muted:muted pinned:pinned time:time];
}
static NSArray<NSString *> *WPNames(NSArray<WPQuickChatSession *> *rows) { return [rows valueForKey:@"username"]; }

static void WPTestOrdering(void) {
    NSArray *native = @[WPRow(@"top_a", 0, NO, YES, 10), WPRow(@"brandsessionholder", 3, NO, NO, 99), WPRow(@"recent", 1, NO, NO, 50),
                        WPRow(@"group@chatroom", 2, YES, NO, 40), WPRow(@"recent", 1, NO, NO, 50), WPRow(@"older", 0, NO, NO, 5)];
    WPCheck(@"Q01_nativeOrderKeptAsWeChatDrawsIt", [WPNames(WPQuickChatOrdered(native, YES)) isEqual:(@[@"top_a", @"recent", @"group@chatroom", @"older"])]);
    WPCheck(@"Q02_aggregateHoldersAndDuplicatesRemoved", ![WPNames(WPQuickChatOrdered(native, YES)) containsObject:@"brandsessionholder"]);
    NSArray *unordered = @[WPRow(@"old", 0, NO, NO, 1), WPRow(@"pin_old", 0, NO, YES, 2), WPRow(@"new", 0, NO, NO, 9), WPRow(@"pin_new", 0, NO, YES, 8), WPRow(@"same_a", 0, NO, NO, 5), WPRow(@"same_b", 0, NO, NO, 5)];
    WPCheck(@"Q03_fallbackPinnedFirstThenNewest", [WPNames(WPQuickChatOrdered(unordered, NO)) isEqual:(@[@"pin_new", @"pin_old", @"new", @"same_a", @"same_b", @"old"])]);
    BOOL filtered = YES;
    for (NSString *name in @[@"brandservicesessionholder", @"@placeholder_foldgroup", @"notifymessage", @"fmessage", @"", @"@opencustomerservicemsg"]) filtered &= !WPQuickChatIsOpenableUsername(name);
    for (NSString *name in @[@"wxid_friend", @"123@chatroom", @"filehelper", @"gh_public"]) filtered &= WPQuickChatIsOpenableUsername(name);
    WPCheck(@"Q04_openableUsernameFilter", filtered);
}

static void WPTestTracker(void) {
    WPQuickChatTracker *tracker = [WPQuickChatTracker new];
    NSArray *first = @[WPRow(@"a", 2, NO, NO, 0), WPRow(@"b", 0, NO, NO, 0), WPRow(@"muted", 4, YES, NO, 0)];
    WPCheck(@"Q05_firstObservationIsBaselineWithoutArrivals", [tracker observe:first reportArrivals:YES].count == 0 && tracker.hasBaseline);
    WPCheck(@"Q06_existingUnreadLightsDotWithoutFlash", tracker.hasAlertableUnread && [tracker.alertableUsernames isEqual:[NSSet setWithObject:@"a"]]);
    NSArray *arrivals = [tracker observe:@[WPRow(@"b", 1, NO, NO, 0), WPRow(@"a", 3, NO, NO, 0), WPRow(@"muted", 6, YES, NO, 0)] reportArrivals:YES];
    WPCheck(@"Q07_risingUnreadReportsArrivalsInListOrder", [arrivals isEqual:(@[@"b", @"a"])]);
    WPCheck(@"Q08_mutedChatNeverArrives", ![arrivals containsObject:@"muted"]);
    WPCheck(@"Q09_unchangedCountsReportNothing", [tracker observe:@[WPRow(@"b", 1, NO, NO, 0), WPRow(@"a", 3, NO, NO, 0)] reportArrivals:YES].count == 0);
    WPCheck(@"Q10_newChatAfterBaselineArrives", [[tracker observe:@[WPRow(@"brand_new", 1, NO, NO, 0)] reportArrivals:YES] isEqual:@[@"brand_new"]]);
    [tracker observe:@[WPRow(@"a", 0, NO, NO, 0), WPRow(@"b", 0, NO, NO, 0), WPRow(@"brand_new", 0, NO, NO, 0)] reportArrivals:YES];
    WPCheck(@"Q11_readingAllClearsBlueDot", !tracker.hasAlertableUnread);
    WPCheck(@"Q12_onlyMutedUnreadKeepsDotOff", [tracker observe:@[WPRow(@"muted", 9, YES, NO, 0)] reportArrivals:YES].count == 0 && !tracker.hasAlertableUnread);
    WPCheck(@"Q13_backgroundScanNeverFlashesOldUnread", [tracker observe:@[WPRow(@"old_unread", 5, NO, NO, 0)] reportArrivals:NO].count == 0 && tracker.hasAlertableUnread);
    WPCheck(@"Q14_scannedRowThenRiseInWindowArrives", [[tracker observe:@[WPRow(@"old_unread", 6, NO, NO, 0)] reportArrivals:YES] isEqual:@[@"old_unread"]]);
    [tracker retainOnlyUsernames:[NSSet setWithObjects:@"a", @"b", nil]];
    WPCheck(@"Q15_deletedChatsLeaveTheDot", !tracker.hasAlertableUnread);
    WPQuickChatSession *unknown = WPRow(@"a", 7, NO, NO, 0); unknown.unreadKnown = NO;
    WPCheck(@"Q16_unreadableCountIsNeverNew", [tracker observe:@[unknown] reportArrivals:YES].count == 0 && !tracker.hasAlertableUnread);
    [tracker resetBaseline];
    WPCheck(@"Q17_foregroundReturnTakesNewBaseline", [tracker observe:@[WPRow(@"a", 9, NO, NO, 0), WPRow(@"c", 2, NO, NO, 0)] reportArrivals:YES].count == 0 && tracker.hasAlertableUnread);
    WPCheck(@"Q18_backgroundScanDoesNotTakeBaseline", ({ WPQuickChatTracker *t = [WPQuickChatTracker new]; [t observe:@[WPRow(@"x", 1, NO, NO, 0)] reportArrivals:NO]; !t.hasBaseline; }));
}

#pragma mark - Radial geometry (compiled from WPRadialMenu.m between the markers)
#include "radial-geometry.inc"

static BOOL WPLayoutFits(WPFanLayout layout, CGRect safe, NSUInteger count) {
    if (!layout.valid || layout.count != count) return NO;
    CGFloat half = layout.targetSize / 2;
    for (NSUInteger i = 0; i < count; i++) {
        CGRect target = CGRectMake(layout.centers[i].x - half, layout.centers[i].y - half, layout.targetSize, layout.targetSize);
        if (!CGRectContainsRect(CGRectInset(safe, -.01, -.01), target)) return NO;
        for (NSUInteger j = 0; j < i; j++) {
            CGRect other = CGRectMake(layout.centers[j].x - half, layout.centers[j].y - half, layout.targetSize, layout.targetSize);
            if (CGRectIntersectsRect(CGRectInset(target, .01, .01), other)) return NO;
        }
    }
    return YES;
}
static void WPTestRadial(void) {
    // Phone safe areas after the overlay's 5 pt inset and the menu's 8 pt padding.
    NSArray<NSValue *> *screens = @[[NSValue valueWithRect:NSRectFromCGRect(CGRectMake(13, 37, 349, 609))],   // 375×667
                                    [NSValue valueWithRect:NSRectFromCGRect(CGRectMake(13, 72, 364, 725))],   // 390×844
                                    [NSValue valueWithRect:NSRectFromCGRect(CGRectMake(13, 72, 404, 813))],   // 430×932
                                    [NSValue valueWithRect:NSRectFromCGRect(CGRectMake(13, 72, 364, 230))]];  // keyboard up
    for (NSUInteger count = 4; count <= 5; count++) {
        NSUInteger layouts = 0, failures = 0, fans = 0, fullLayouts = 0;
        for (NSValue *value in screens) {
            CGRect safe = NSRectToCGRect(value.rectValue);
            BOOL full = CGRectGetHeight(safe) > 400; // keyboard-up areas may use the grid fallback
            for (CGFloat scale = .6; scale <= 4.001; scale += .2)
                for (CGFloat x = CGRectGetMinX(safe); x <= CGRectGetMaxX(safe); x += 12)
                    for (CGFloat y = CGRectGetMinY(safe); y <= CGRectGetMaxY(safe); y += 12) {
                        CGPoint anchor = CGPointMake(x, y);
                        WPFanLayout layout = WPComputeFanLayout(anchor, safe, scale, WPInwardSide(anchor, safe, 0), count);
                        layouts++; if (!WPLayoutFits(layout, safe, count)) failures++; if (full) { fullLayouts++; if (layout.fan) fans++; }
                    }
        }
        NSString *suffix = [NSString stringWithFormat:@"%luItems", (unsigned long)count];
        WPCheck([@"R01_everyLayoutInsideSafeAreaWithoutOverlap_" stringByAppendingString:suffix], failures == 0);
        WPCheck([@"R02_fanUsedForNinetyPercentOnFullScreens_" stringByAppendingString:suffix], fans * 10 >= fullLayouts * 9);
        WPResults[[@"R_layoutsChecked_" stringByAppendingString:suffix]] = @(layouts);
    }
    // The 4-item menu must keep its 0.3.10 geometry (60° steps).
    WPFanLayout four = WPComputeFanLayout(CGPointMake(300, 400), CGRectMake(13, 72, 364, 725), 1, -1, 4);
    CGFloat a0 = atan2(four.centers[0].y - four.origin.y, four.centers[0].x - four.origin.x), a1 = atan2(four.centers[1].y - four.origin.y, four.centers[1].x - four.origin.x);
    CGFloat step = fabs(remainder(a1 - a0, 2 * M_PI));
    WPCheck(@"R03_fourItemSpacingUnchanged", fabs(step - M_PI / 3) < 1e-6);
    WPFanLayout five = WPComputeFanLayout(CGPointMake(300, 400), CGRectMake(13, 72, 364, 725), 1, -1, 5);
    WPCheck(@"R04_fiveItemsKeepDefaultRadius", five.fan && fabs(five.effectiveRadius - 80) < .05);
}

int main(void) {
    @autoreleasepool {
        WPResults = [NSMutableDictionary new];
        WPTestOrdering(); WPTestTracker(); WPTestRadial();
        NSUInteger cases = 0; BOOL all = YES;
        for (NSString *key in WPResults) if (![key hasPrefix:@"R_"]) { cases++; all &= WPResults[key].boolValue; }
        NSDictionary *report = @{@"caseCount": @(cases), @"allPassed": @(all), @"results": WPResults};
        NSData *data = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
        fwrite(data.bytes, 1, data.length, stdout); fputc('\n', stdout);
        return all ? 0 : 1;
    }
}
