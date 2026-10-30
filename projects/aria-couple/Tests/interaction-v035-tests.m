#import <Foundation/Foundation.h>
#import "WPCoupleHistory.h"
#import "WPShakeDetector.h"

// 0.3.5 acceptance A01–A18 on the real persistence layer (isolated JSON files)
// and A20/A21 on the shake detector with synthetic touch samples.
static NSMutableDictionary<NSString *, NSNumber *> *WPResults;
static void WPCheck(NSString *name, BOOL passed) {
    WPResults[name] = @(passed);
    if (!passed) fprintf(stderr, "FAIL: %s\n", name.UTF8String);
}
static NSString *WPID(void) { return NSUUID.UUID.UUIDString; }
static NSDate *WPAgo(NSTimeInterval seconds) { return [NSDate dateWithTimeIntervalSinceNow:-seconds]; }
static NSDictionary *WPRow(WPCoupleHistory *history, NSString *identifier) {
    for (NSDictionary *row in history.recentInteractions) if ([row[@"id"] isEqual:identifier] && [row[@"direction"] isEqual:@"incoming"]) return row;
    for (NSDictionary *row in history.recentInteractions) if ([row[@"id"] isEqual:identifier]) return row;
    return nil;
}
static NSUInteger WPIncomingCount(WPCoupleHistory *history) {
    NSUInteger count = 0; for (NSDictionary *row in history.recentInteractions) if ([row[@"direction"] isEqual:@"incoming"]) count++; return count;
}
static WPCoupleHistory *WPFresh(NSURL *root, NSString *name) {
    NSURL *url = [root URLByAppendingPathComponent:name];
    [NSFileManager.defaultManager removeItemAtURL:url error:NULL];
    return [[WPCoupleHistory alloc] initWithURL:url];
}
static BOOL WPReceive(WPCoupleHistory *history, NSString *kind, NSString *identifier, NSTimeInterval age) {
    BOOL isNew = NO; return [history receiveKind:kind identifier:identifier at:WPAgo(age) receivedAt:NSDate.date isNew:&isNew] && isNew;
}

static void WPTestMissWindow(NSURL *root) {
    WPCoupleHistory *b = WPFresh(root, @"a01.json"); NSString *live = WPID();
    WPCheck(@"A01_onlineMissStoredWithoutBadge", WPReceive(b, @"miss", live, 0) && b.badgeCount == 0 && WPIncomingCount(b) == 1 &&
        ![WPRow(b, live)[@"needs_response"] boolValue] && ![WPRow(b, live)[@"animation_played"] boolValue] && WPRow(b, live)[@"received_at"]);
    WPCheck(@"A01_onlineMissIsNotPendingOrAngry", b.pendingIncoming.count == 0 && !b.hasPendingAnger);
    NSString *threeMinutes = WPID();
    WPCheck(@"A02_missBackWithin5MinutesNoBadge", WPReceive(b, @"miss", threeMinutes, 180) && b.badgeCount == 0);
    NSString *boundary = WPID();
    WPCheck(@"A02_exactly5MinutesIsStillWithin", WPReceive(b, @"miss", boundary, WPMissResponseWindow - .5) && b.badgeCount == 0);
    NSString *tenMinutes = WPID();
    WPCheck(@"A03_missAfter10MinutesAddsOneBadge", WPReceive(b, @"miss", tenMinutes, 600) && b.badgeCount == 1 && [WPRow(b, tenMinutes)[@"needs_response"] boolValue]);
    WPCheck(@"A03_lateMissDoesNotMakePetAngry", !b.hasPendingAnger);

    WPCoupleHistory *batch = WPFresh(root, @"a04.json"); NSMutableArray *ids = [NSMutableArray new]; BOOL all = YES;
    for (NSUInteger i = 0; i < 10; i++) { NSString *identifier = WPID(); [ids addObject:identifier]; all &= WPReceive(batch, @"miss", identifier, 400 + i * 60); }
    WPCheck(@"A04_tenLateMissesTenBadgesTenRows", all && batch.badgeCount == 10 && WPIncomingCount(batch) == 10);
    WPCheck(@"A04_playingCoalescedAnimationKeepsTenBadges", [batch markAnimationPlayedIdentifiers:ids] && batch.badgeCount == 10 && [WPRow(batch, ids[3])[@"animation_played"] boolValue]);
    WPCoupleHistory *mixed = WPFresh(root, @"a04-mixed.json"); BOOL mixedSaved = YES;
    for (NSNumber *age in @[@30, @200, @290, @320, @900, @3600]) mixedSaved &= WPReceive(mixed, @"miss", WPID(), age.doubleValue);
    WPCheck(@"A04_mixedBatchDecidesEachRowSeparately", mixedSaved && mixed.badgeCount == 3 && WPIncomingCount(mixed) == 6);
}

static void WPTestAnger(NSURL *root) {
    WPCoupleHistory *b = WPFresh(root, @"a05.json"); NSString *anger = WPID();
    WPCheck(@"A05_onlineAngerAlwaysAddsBadge", WPReceive(b, @"anger", anger, 0) && b.badgeCount == 1 && [WPRow(b, anger)[@"needs_response"] boolValue]);
    WPCheck(@"A05_angerKeepsAngryLookAfterAnimation", [b markAnimationPlayedIdentifiers:@[anger]] && b.hasPendingAnger && b.badgeCount == 1);
    WPCoupleHistory *offline = WPFresh(root, @"a06.json");
    WPCheck(@"A06_offlineAngerAddsBadgeAndAngryLook", WPReceive(offline, @"anger", WPID(), 7200) && offline.badgeCount == 1 && offline.hasPendingAnger);
    WPCheck(@"A19_liveMissDuringAngerKeepsAngryLook", WPReceive(b, @"miss", WPID(), 0) && b.hasPendingAnger && b.badgeCount == 1);
}

static NSArray<NSString *> *WPSeedFourPending(WPCoupleHistory *history) {
    NSMutableArray *ids = [NSMutableArray new];
    for (NSUInteger i = 0; i < 3; i++) { NSString *identifier = WPID(); [ids addObject:identifier]; WPReceive(history, @"miss", identifier, 900 + i); }
    NSString *anger = WPID(); [ids addObject:anger]; WPReceive(history, @"anger", anger, 60);
    return ids;
}

static void WPTestReply(NSURL *root) {
    WPCoupleHistory *b = WPFresh(root, @"a07.json"); NSArray *seeded = WPSeedFourPending(b);
    NSArray *snapshot = [b.pendingIncoming valueForKey:@"id"]; NSString *reply = WPID();
    WPCheck(@"A07_fixtureHasFourPendingAndAngry", b.badgeCount == 4 && b.hasPendingAnger && [[NSSet setWithArray:snapshot] isEqualToSet:[NSSet setWithArray:seeded]]);
    BOOL saved = [b enqueueKind:@"miss" identifier:reply at:NSDate.date resolvingIncomingIdentifiers:snapshot];
    WPCheck(@"A07_replySavedLocallyIsNotYetSuccess", saved && b.badgeCount == 4 && b.hasPendingAnger && [WPRow(b, reply)[@"resolves"] count] == 3);
    WPCheck(@"A07_acceptedMissResolvesOnlyOrdinary", [b updateIdentifier:reply state:@"online" serverTime:nil] && b.badgeCount == 1 && b.hasPendingAnger);
    BOOL allReplied = YES; for (NSUInteger i=0;i<3;i++) allReplied &= [WPRow(b, seeded[i])[@"resolve_type"] isEqual:@"reply"] && WPRow(b, seeded[i])[@"resolved_at"];
    WPCheck(@"A07_historyKeptAndMarkedReplied", allReplied && [WPRow(b, seeded[3])[@"needs_response"] boolValue] && WPIncomingCount(b) == 4 && [WPRow(b, reply)[@"resolved_count"] integerValue] == 3 && !WPRow(b, reply)[@"resolves"]);
    WPCheck(@"A07_deliveryAfterAcceptDoesNotChangeAgain", [b updateIdentifier:reply state:@"delivered" serverTime:nil] && b.badgeCount == 1 && [WPRow(b, reply)[@"resolved_count"] integerValue] == 3);

    WPCoupleHistory *failed = WPFresh(root, @"a08.json"); WPSeedFourPending(failed); NSString *failedReply = WPID();
    [failed enqueueKind:@"miss" identifier:failedReply at:NSDate.date resolvingIncomingIdentifiers:[failed.pendingIncoming valueForKey:@"id"]];
    WPCheck(@"A08_failedReplyKeepsFourAndAngry", [failed updateIdentifier:failedReply state:@"failed" serverTime:nil] && failed.badgeCount == 4 && failed.hasPendingAnger);
    WPCheck(@"A08_expiredReplyKeepsFourAndAngry", [failed expireAllPending] && failed.badgeCount == 4 && failed.hasPendingAnger);
    WPCheck(@"A08_restartedAfterFailureStillFour", [[WPCoupleHistory alloc] initWithURL:[root URLByAppendingPathComponent:@"a08.json"]].badgeCount == 4);
    NSString *retried = WPID();
    [failed enqueueKind:@"miss" identifier:retried at:NSDate.date resolvingIncomingIdentifiers:[failed.pendingIncoming valueForKey:@"id"]];
    WPCheck(@"A08_retryAfterFailureCanStillSucceed", [failed updateIdentifier:retried state:@"waiting" serverTime:nil] && failed.badgeCount == 4 &&
        [failed updateIdentifier:retried state:@"queued" serverTime:nil] && failed.badgeCount == 1 && failed.hasPendingAnger);

    WPCoupleHistory *racing = WPFresh(root, @"a09.json"); WPSeedFourPending(racing); NSString *raceReply = WPID();
    [racing enqueueKind:@"miss" identifier:raceReply at:NSDate.date resolvingIncomingIdentifiers:[racing.pendingIncoming valueForKey:@"id"]];
    NSString *newAnger = WPID(); WPReceive(racing, @"anger", newAnger, 0);
    WPCheck(@"A09_onlySnapshotResolvedNewAngerStays", [racing updateIdentifier:raceReply state:@"queued" serverTime:nil] && racing.badgeCount == 2 &&
        [racing.pendingIncoming.firstObject[@"id"] isEqual:newAnger] && racing.hasPendingAnger);

    WPCoupleHistory *angerOnly = WPFresh(root, @"a07-anger.json"); WPSeedFourPending(angerOnly); NSString *angerSend = WPID();
    [angerOnly enqueueKind:@"anger" identifier:angerSend at:NSDate.date resolvingIncomingIdentifiers:[angerOnly.pendingIncoming valueForKey:@"id"]];
    WPCheck(@"A07_sendingAngerNeverResolves", [angerOnly updateIdentifier:angerSend state:@"delivered" serverTime:nil] && angerOnly.badgeCount == 4);
}

static void WPTestSymmetricReply(NSURL *root) {
    WPCoupleHistory *a = WPFresh(root, @"a10-a.json"), *b = WPFresh(root, @"a10-b.json");
    NSString *fromA = WPID(); [a enqueueKind:@"miss" identifier:fromA at:WPAgo(1200)]; [a updateIdentifier:fromA state:@"queued" serverTime:@(WPAgo(1200).timeIntervalSince1970)];
    WPReceive(b, @"miss", fromA, 1200);
    NSString *reply = WPID(); [b enqueueKind:@"miss" identifier:reply at:WPAgo(600) resolvingIncomingIdentifiers:[b.pendingIncoming valueForKey:@"id"]];
    [b updateIdentifier:reply state:@"queued" serverTime:@(WPAgo(600).timeIntervalSince1970)];
    WPCheck(@"A10_replyClearsReplierOnly", b.badgeCount == 0 && a.badgeCount == 0);
    WPCheck(@"A10_lateReplyIsOrdinaryMissForPeer", WPReceive(a, @"miss", reply, 600) && a.badgeCount == 1);
    WPCoupleHistory *c = WPFresh(root, @"a10-c.json");
    WPCheck(@"A10_promptReplyAddsNoPeerBadge", WPReceive(c, @"miss", WPID(), 20) && c.badgeCount == 0);
}

static void WPTestReadOnlyActions(NSURL *root) {
    WPCoupleHistory *b = WPFresh(root, @"a11.json"); WPSeedFourPending(b);
    NSData *before = [NSData dataWithContentsOfURL:[root URLByAppendingPathComponent:@"a11.json"]];
    (void)b.recentInteractions; (void)b.pendingIncoming; (void)b.pendingOutgoing;
    WPCheck(@"A11_openingRecordChangesNothing", b.badgeCount == 4 && b.hasPendingAnger && [[NSData dataWithContentsOfURL:[root URLByAppendingPathComponent:@"a11.json"]] isEqualToData:before]);
    WPCheck(@"A12_replayedAnimationsDoNotClear", [b markAnimationPlayedIdentifiers:[b.pendingIncoming valueForKey:@"id"]] && b.badgeCount == 4 && b.hasPendingAnger);
}

static void WPTestManualClear(NSURL *root) {
    WPCoupleHistory *a = WPFresh(root, @"a13-a.json"), *b = WPFresh(root, @"a13-b.json");
    NSString *sent = WPID(); [a enqueueKind:@"anger" identifier:sent at:NSDate.date]; [a updateIdentifier:sent state:@"delivered" serverTime:nil];
    WPReceive(b, @"anger", sent, 0); WPReceive(b, @"miss", WPID(), 900);
    NSData *peerBefore = [NSData dataWithContentsOfURL:[root URLByAppendingPathComponent:@"a13-a.json"]];
    NSArray *snapshot = [b.pendingIncoming valueForKey:@"id"]; NSUInteger outgoingBefore = b.pendingCount;
    NSString *duringConfirm = WPID(); WPReceive(b, @"miss", duringConfirm, 1000);
    WPCheck(@"A13_manualClearResolvesSnapshot", [b manuallyClearIncomingIdentifiers:snapshot] && b.badgeCount == 1 && [WPRow(b, sent)[@"resolve_type"] isEqual:@"manual_clear"]);
    WPCheck(@"A13_manualClearSendsNothingAndLeavesPeerUntouched", b.pendingCount == outgoingBefore && [[NSData dataWithContentsOfURL:[root URLByAppendingPathComponent:@"a13-a.json"]] isEqualToData:peerBefore] &&
        ![WPRow(a, sent)[@"resolve_type"] isEqual:@"manual_clear"]);
    WPCheck(@"A13_angryLookEndsWithLastAnger", !b.hasPendingAnger);
    WPCheck(@"A15_arrivalDuringConfirmationStays", [b.pendingIncoming.firstObject[@"id"] isEqual:duringConfirm] && [WPRow(b, duringConfirm)[@"needs_response"] boolValue]);
    WPCheck(@"A13_clearIsIdempotent", [b manuallyClearIncomingIdentifiers:snapshot] && b.badgeCount == 1);
    WPCheck(@"A13_recordKeptAfterClear", WPIncomingCount(b) == 3);
}

static void WPTestDedupAndRestart(NSURL *root) {
    NSURL *url = [root URLByAppendingPathComponent:@"a16.json"]; [NSFileManager.defaultManager removeItemAtURL:url error:NULL];
    WPCoupleHistory *b = [[WPCoupleHistory alloc] initWithURL:url]; NSString *late = WPID(), *anger = WPID(), *replied = WPID(), *cleared = WPID();
    BOOL isNew = YES; WPReceive(b, @"miss", late, 900);
    WPCheck(@"A16_reconnectDuplicateStoredOnce", [b receiveKind:@"miss" identifier:late at:WPAgo(900) receivedAt:NSDate.date isNew:&isNew] && !isNew && WPIncomingCount(b) == 1 && b.badgeCount == 1);
    WPReceive(b, @"miss", replied, 800); WPReceive(b, @"miss", cleared, 700);
    NSString *reply = WPID(); [b enqueueKind:@"miss" identifier:reply at:NSDate.date resolvingIncomingIdentifiers:@[replied]]; [b updateIdentifier:reply state:@"queued" serverTime:nil];
    [b manuallyClearIncomingIdentifiers:@[cleared]]; WPReceive(b, @"anger", anger, 30);
    b = [[WPCoupleHistory alloc] initWithURL:url];
    WPCheck(@"A17_restartRestoresBadgeAndStates", b.badgeCount == 2 && [WPRow(b, late)[@"needs_response"] boolValue] && [WPRow(b, replied)[@"resolve_type"] isEqual:@"reply"] && [WPRow(b, cleared)[@"resolve_type"] isEqual:@"manual_clear"]);
    WPCheck(@"A18_restartKeepsAngryLook", b.hasPendingAnger);
    isNew = YES;
    WPCheck(@"A16_duplicateAfterRestartNotReplayed", [b receiveKind:@"anger" identifier:anger at:WPAgo(30) receivedAt:NSDate.date isNew:&isNew] && !isNew && b.badgeCount == 2);
    isNew = YES;
    WPCheck(@"A17_resolvedRowsDoNotReturnOnResync", [b receiveKind:@"miss" identifier:replied at:WPAgo(800) receivedAt:NSDate.date isNew:&isNew] && !isNew &&
        [b receiveKind:@"miss" identifier:cleared at:WPAgo(700) receivedAt:NSDate.date isNew:&isNew] && !isNew && b.badgeCount == 2);
}

static void WPTestMigration(NSURL *root) {
    NSURL *url = [root URLByAppendingPathComponent:@"v2.json"]; NSNumber *stamp = @(NSDate.date.timeIntervalSince1970 - 30);
    NSString *unread = WPID(), *read = WPID(), *anger = WPID();
    NSDictionary *v2 = @{@"version":@2, @"outgoing":@[], @"incoming":@[
        @{@"id":unread, @"kind":@"miss", @"sent_at":stamp, @"unread":@YES}, @{@"id":read, @"kind":@"miss", @"sent_at":stamp, @"unread":@NO},
        @{@"id":anger, @"kind":@"anger", @"sent_at":stamp, @"unread":@YES}]};
    [[NSJSONSerialization dataWithJSONObject:v2 options:0 error:NULL] writeToURL:url atomically:YES];
    WPCoupleHistory *history = [[WPCoupleHistory alloc] initWithURL:url];
    WPCheck(@"v2UnreadBecomesPendingWithoutReplayingAnimation", history.badgeCount == 2 && history.hasPendingAnger && [WPRow(history, unread)[@"animation_played"] boolValue]);
    WPCheck(@"v2ReadRowShowsReceivedNotReplied", ![WPRow(history, read)[@"needs_response"] boolValue] && !WPRow(history, read)[@"resolve_type"]);
    [history markAnimationPlayedIdentifiers:@[unread]]; [history manuallyClearIncomingIdentifiers:@[unread]];
    NSDictionary *saved = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:url] options:0 error:NULL];
    BOOL mirror = NO; for (NSDictionary *row in saved[@"incoming"]) if ([row[@"id"] isEqual:anger]) mirror = [row[@"unread"] boolValue];
    WPCheck(@"v3KeepsUnreadMirrorForDowngrade", [saved[@"version"] integerValue] == 3 && mirror);
}

static void WPTestShake(void) {
    WPShakeDetector *detector = [[WPShakeDetector alloc] initWithSensitivity:1]; NSTimeInterval t = 1000;
    [detector beginAtPoint:CGPointMake(100, 300) time:t]; BOOL fired = NO;
    for (NSUInteger i = 1; i <= 40; i++) fired |= [detector addPoint:CGPointMake(100 + i * 6 + (i % 2 ? 4 : -4), 300 + i * 3) time:t + i * .02];
    WPCheck(@"A20_straightDragWithJitterDoesNotOpen", !fired);
    [detector beginAtPoint:CGPointMake(100, 300) time:t += 5]; fired = NO;
    for (NSNumber *x in @[@140, @100, @140, @100, @140]) { t += .9; fired |= [detector addPoint:CGPointMake(x.doubleValue, 300) time:t]; }
    WPCheck(@"A20_slowRepositioningBackAndForthDoesNotOpen", !fired);
    [detector beginAtPoint:CGPointMake(100, 300) time:t += 5]; fired = NO;
    for (NSNumber *x in @[@112, @140, @100, @108]) { t += .06; fired |= [detector addPoint:CGPointMake(x.doubleValue, 300) time:t]; }
    WPCheck(@"A20_singleReversalIsJustAMove", !fired);
    [detector beginAtPoint:CGPointMake(100, 300) time:t += 5]; NSUInteger count = 0;
    for (NSNumber *x in @[@115, @132, @118, @100, @87, @104, @130, @110, @92, @80, @110, @135, @105, @80]) { t += .045; count += [detector addPoint:CGPointMake(x.doubleValue, 302) time:t]; }
    WPCheck(@"A21_quickShakeOpensExactlyOnce", count == 1 && detector.triggered);
    [detector beginAtPoint:CGPointMake(100, 300) time:t += .3]; count = 0;
    for (NSNumber *x in @[@130, @95, @130, @95, @130]) { t += .05; count += [detector addPoint:CGPointMake(x.doubleValue, 300) time:t]; }
    WPCheck(@"A21_cooldownPreventsImmediateRetrigger", count == 0);
    [detector beginAtPoint:CGPointMake(100, 300) time:t += 2]; count = 0;
    for (NSNumber *x in @[@130, @95, @130, @95, @130]) { t += .05; count += [detector addPoint:CGPointMake(x.doubleValue, 300) time:t]; }
    WPCheck(@"A21_nextShakeAfterCooldownOpensAgain", count == 1);
    WPShakeDetector *low = [[WPShakeDetector alloc] initWithSensitivity:0]; [low beginAtPoint:CGPointMake(100, 300) time:t += 5]; count = 0;
    for (NSNumber *x in @[@125, @100, @125, @100, @125]) { t += .05; count += [low addPoint:CGPointMake(x.doubleValue, 300) time:t]; }
    WPCheck(@"lowSensitivityNeedsBiggerShake", count == 0 && low.requiredReversals > detector.requiredReversals);
    WPCheck(@"sensitivityPreferenceDefaultsToMedium", WPShakeSensitivityFromPreferenceValue(nil) == 1 && WPShakeSensitivityFromPreferenceValue(@9) == 2);
}

int main(int argc, char **argv) {
    @autoreleasepool {
        WPResults = [NSMutableDictionary new];
        NSString *base = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : NSFileManager.defaultManager.currentDirectoryPath;
        NSURL *root = [NSURL fileURLWithPath:[base stringByAppendingPathComponent:[@"interaction-v035-" stringByAppendingString:WPID()]] isDirectory:YES];
        BOOL created = [NSFileManager.defaultManager createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:NULL];
        WPCheck(@"fixtureDirectoryCreated", created);
        @try {
            if (created) { WPTestMissWindow(root); WPTestAnger(root); WPTestReply(root); WPTestSymmetricReply(root); WPTestReadOnlyActions(root);
                WPTestManualClear(root); WPTestDedupAndRestart(root); WPTestMigration(root); }
            WPTestShake();
        } @catch (NSException *exception) { WPCheck(@"completedWithoutException", NO); fprintf(stderr, "%s\n", exception.reason.UTF8String); }
        BOOL all = YES; for (NSNumber *passed in WPResults.allValues) all &= passed.boolValue;
        NSMutableDictionary *report = [WPResults mutableCopy]; report[@"caseCount"] = @(WPResults.count); report[@"allPassed"] = @(all);
        NSData *json = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:NULL];
        fwrite(json.bytes, 1, json.length, stdout); puts("");
        if (all) [NSFileManager.defaultManager removeItemAtURL:root error:NULL];
        return all ? 0 : 1;
    }
}
