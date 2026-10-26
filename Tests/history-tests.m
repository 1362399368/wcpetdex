#import <Foundation/Foundation.h>
#import "WPCoupleHistory.h"

// Mac Foundation contract tests. Build with WPCoupleHistory.m; no UIKit, socket,
// phone, keychain, or sharedHistory access is involved. Every fixture is real JSON.
static NSMutableDictionary<NSString *, NSNumber *> *WPHistoryResults;
static void WPCheck(NSString *name, BOOL passed) {
    WPHistoryResults[name] = @(passed);
    if (!passed) fprintf(stderr, "FAIL: %s\n", name.UTF8String);
}
static NSString *WPID(void) { return NSUUID.UUID.UUIDString; }
static NSURL *WPURL(NSURL *root, NSString *name) { return [root URLByAppendingPathComponent:name]; }
static NSDictionary *WPRow(WPCoupleHistory *history, NSString *identifier) {
    for (NSDictionary *row in history.recentInteractions) if ([row[@"id"] isEqual:identifier]) return row;
    return nil;
}
static NSData *WPSnapshot(WPCoupleHistory *history) {
    return [NSJSONSerialization dataWithJSONObject:history.recentInteractions options:NSJSONWritingSortedKeys error:NULL];
}
static BOOL WPBlockDestination(NSURL *url, NSURL **backup) {
    NSFileManager *files = NSFileManager.defaultManager;
    NSURL *saved = [url URLByAppendingPathExtension:@"saved"];
    if (![files moveItemAtURL:url toURL:saved error:NULL]) return NO;
    if (![files createDirectoryAtURL:url withIntermediateDirectories:NO attributes:nil error:NULL]) {
        [files moveItemAtURL:saved toURL:url error:NULL];
        return NO;
    }
    [@"keep-directory-intact" writeToURL:[url URLByAppendingPathComponent:@"sentinel"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    *backup = saved;
    return YES;
}
static BOOL WPRestoreDestination(NSURL *url, NSURL *backup) {
    NSFileManager *files = NSFileManager.defaultManager;
    return [files removeItemAtURL:url error:NULL] && [files moveItemAtURL:backup toURL:url error:NULL];
}

static void WPTestPendingAndDelivery(NSURL *root) {
    NSURL *url = WPURL(root, @"pending-and-delivery.json");
    WPCoupleHistory *history = [[WPCoupleHistory alloc] initWithURL:url];
    NSString *miss = WPID(), *anger = WPID();
    NSDate *now = NSDate.date;
    WPCheck(@"mixedMissAndAngerEnqueue", [history enqueueKind:@"miss" identifier:miss at:now] && [history enqueueKind:@"anger" identifier:anger at:now]);
    WPCheck(@"outgoingKindsNeverCreateRedBadge", history.pendingCount == 2 && history.pendingOutgoing.count == 2 && history.badgeCount == 0);
    WPCheck(@"waitingHistoryActuallyWritten", [NSData dataWithContentsOfURL:url].length > 0);
    history = [[WPCoupleHistory alloc] initWithURL:url];
    WPCheck(@"reconstructedWaitingCountPersists", history.pendingCount == 2 && [WPRow(history, miss)[@"state"] isEqual:@"waiting"]);
    WPCheck(@"acceptedQueuedRemainsPending", [history updateIdentifier:miss state:@"queued" serverTime:@(now.timeIntervalSince1970)] && history.pendingCount == 2);
    WPCheck(@"acceptedOnlineRemainsPending", [history updateIdentifier:anger state:@"online" serverTime:@(now.timeIntervalSince1970)] && history.pendingCount == 2);
    history = [[WPCoupleHistory alloc] initWithURL:url];
    WPCheck(@"reconstructedAcceptedCountPersists", history.pendingCount == 2 && [WPRow(history, miss)[@"state"] isEqual:@"queued"] && [WPRow(history, anger)[@"state"] isEqual:@"online"]);
    WPCheck(@"transportAcceptedIsNotDeliveredState", ![history updateIdentifier:miss state:@"accepted" serverTime:nil] && history.pendingCount == 2);
    WPCheck(@"deliveryChangesTransportStateWithoutRedBadge", [history updateIdentifier:miss state:@"delivered" serverTime:nil] && history.pendingCount == 1 && history.badgeCount == 0 && [history.pendingOutgoing.firstObject[@"id"] isEqual:anger]);
    WPCheck(@"duplicateDeliveryIsIdempotent", [history updateIdentifier:miss state:@"delivered" serverTime:nil] && history.pendingCount == 1 && history.recentInteractions.count == 2);
    WPCheck(@"deliveredCannotRegressToQueued", [history updateIdentifier:miss state:@"queued" serverTime:nil] && history.pendingCount == 1 && [WPRow(history, miss)[@"state"] isEqual:@"delivered"]);
    WPCheck(@"deliveredCannotRegressToWaitingOrExpired", [history updateIdentifier:miss state:@"waiting" serverTime:nil] && [history updateIdentifier:miss state:@"expired" serverTime:nil] && [WPRow(history, miss)[@"state"] isEqual:@"delivered"]);
    WPCheck(@"deliveryNeverControlsIncomingBadge", [history updateIdentifier:anger state:@"delivered" serverTime:nil] && history.pendingCount == 0 && history.badgeCount == 0);
    history = [[WPCoupleHistory alloc] initWithURL:url];
    WPCheck(@"reconstructedDeliveredBadgeStaysClear", history.pendingCount == 0 && history.recentInteractions.count == 2);
    WPCheck(@"unknownDeliveryCannotCreateHistory", ![history updateIdentifier:WPID() state:@"delivered" serverTime:nil] && history.recentInteractions.count == 2);
}

static void WPTestIncomingUnreadAndSnapshot(NSURL *root) {
    NSURL *url = WPURL(root, @"incoming-unread.json");
    WPCoupleHistory *history = [[WPCoupleHistory alloc] initWithURL:url];
    NSString *outgoingMiss = WPID(), *outgoingAnger = WPID();
    BOOL queued = [history enqueueKind:@"miss" identifier:outgoingMiss at:NSDate.date] &&
        [history enqueueKind:@"anger" identifier:outgoingAnger at:NSDate.date];
    WPCheck(@"outgoingMissAndAngerDoNotCreateBadge", queued && history.badgeCount == 0);

    NSString *incomingMiss = WPID(), *incomingAnger = WPID(); BOOL isNew = NO;
    BOOL received = [history receiveKind:@"miss" identifier:incomingMiss at:[NSDate dateWithTimeIntervalSinceNow:-600] isNew:&isNew] && isNew;
    received &= [history receiveKind:@"anger" identifier:incomingAnger at:NSDate.date isNew:&isNew] && isNew;
    WPCheck(@"receivedUnreadInteractionsCreateBadge", received && history.badgeCount == 2 && history.pendingIncoming.count == 2);
    WPCheck(@"readActionCanMarkSnapshotWithoutOutgoingSend", [history manuallyClearIncomingIdentifiers:@[incomingMiss]] && history.badgeCount == 1 && history.pendingCount == 2);

    history = [[WPCoupleHistory alloc] initWithURL:url];
    WPCheck(@"unreadMarkersPersistAcrossRestart", history.badgeCount == 1 && history.pendingIncoming.count == 1 && [history.pendingIncoming.firstObject[@"id"] isEqual:incomingAnger]);
    NSArray<NSString *> *sendSnapshot = [[history.pendingIncoming valueForKey:@"id"] copy];
    NSString *arrivedDuringSave = WPID();
    BOOL laterReceived = [history receiveKind:@"miss" identifier:arrivedDuringSave at:[NSDate dateWithTimeIntervalSinceNow:-600] isNew:&isNew] && isNew;
    NSString *replyID = WPID();
    BOOL enqueued = [history enqueueKind:@"miss" identifier:replyID at:NSDate.date resolvingIncomingIdentifiers:sendSnapshot];
    // 0.3.5: a reply waiting in the local outbox has not succeeded yet.
    WPCheck(@"offlineReplyKeepsBadgeUntilServerAccepts", laterReceived && enqueued && history.badgeCount == 2 && [WPRow(history, replyID)[@"state"] isEqual:@"waiting"] && history.pendingCount == 3);
    WPCheck(@"missCannotClearAnger", [history updateIdentifier:replyID state:@"queued" serverTime:nil] && history.badgeCount == 2 && history.hasPendingAnger);

    NSArray<NSString *> *angerSnapshot = [[history.pendingIncoming valueForKey:@"id"] copy];
    NSString *angerID = WPID();
    BOOL angerQueued = [history enqueueKind:@"anger" identifier:angerID at:NSDate.date];
    WPCheck(@"angerNeverClearsReceivedUnread", angerQueued && history.badgeCount == 2 && history.hasPendingAnger);
    WPCheck(@"capturedUnreadIdentifiersAreValid", angerSnapshot.count == 2);
}

static void WPTestIncomingDeduplication(NSURL *root) {
    NSURL *url = WPURL(root, @"incoming-deduplication.json");
    WPCoupleHistory *history = [[WPCoupleHistory alloc] initWithURL:url];
    NSString *miss = WPID(), *anger = WPID();
    BOOL isNew = NO;
    WPCheck(@"firstIncomingMissIsNew", [history receiveKind:@"miss" identifier:miss at:[NSDate dateWithTimeIntervalSinceNow:-600] isNew:&isNew] && isNew);
    isNew = YES;
    WPCheck(@"repeatedIncomingMissIsNotNew", [history receiveKind:@"miss" identifier:miss at:[NSDate dateWithTimeIntervalSinceNow:-600] isNew:&isNew] && !isNew && history.recentInteractions.count == 1);
    history = [[WPCoupleHistory alloc] initWithURL:url];
    isNew = YES;
    WPCheck(@"incomingDeduplicationSurvivesReconstruction", [history receiveKind:@"miss" identifier:miss at:[NSDate dateWithTimeIntervalSinceNow:-600] isNew:&isNew] && !isNew && history.recentInteractions.count == 1);
    isNew = NO;
    WPCheck(@"incomingAngerUsesSamePersistentDeduper", [history receiveKind:@"anger" identifier:anger at:NSDate.date isNew:&isNew] && isNew && history.recentInteractions.count == 2);
    history = [[WPCoupleHistory alloc] initWithURL:url];
    isNew = YES;
    WPCheck(@"repeatedAngerAfterRestartDoesNotReplay", [history receiveKind:@"anger" identifier:anger at:NSDate.date isNew:&isNew] && !isNew && history.recentInteractions.count == 2);
    WPCheck(@"incomingEventsNeverIncreaseOutgoingBadge", history.pendingCount == 0);
    isNew = YES;
    WPCheck(@"unsupportedIncomingDoesNotSetIsNew", ![history receiveKind:@"unknown" identifier:WPID() at:NSDate.date isNew:&isNew] && !isNew);
}

static void WPTestExpiration(NSURL *root) {
    NSURL *url = WPURL(root, @"expiration.json");
    WPCoupleHistory *history = [[WPCoupleHistory alloc] initWithURL:url];
    NSDate *old = [NSDate dateWithTimeIntervalSinceNow:-86460], *fresh = [NSDate dateWithTimeIntervalSinceNow:-86340];
    NSString *waiting = WPID(), *queued = WPID(), *failed = WPID(), *delivered = WPID(), *recent = WPID();
    BOOL setup = [history enqueueKind:@"miss" identifier:waiting at:old] && [history enqueueKind:@"anger" identifier:queued at:old] &&
        [history enqueueKind:@"miss" identifier:failed at:old] && [history enqueueKind:@"anger" identifier:delivered at:old] && [history enqueueKind:@"anger" identifier:recent at:fresh];
    setup &= [history updateIdentifier:queued state:@"queued" serverTime:nil] && [history updateIdentifier:failed state:@"failed" serverTime:nil] && [history updateIdentifier:delivered state:@"delivered" serverTime:nil];
    WPCheck(@"expirationFixtureIncludesAllPendingStates", setup && history.pendingCount == 4);
    [history expireOldOutgoing];
    WPCheck(@"outgoingExpiresOnlyAfter24Hours", history.pendingCount == 1 && [history.pendingOutgoing.firstObject[@"id"] isEqual:recent]);
    WPCheck(@"waitingQueuedAndFailedOlderThan24HoursExpire", [WPRow(history, waiting)[@"state"] isEqual:@"expired"] && [WPRow(history, queued)[@"state"] isEqual:@"expired"] && [WPRow(history, failed)[@"state"] isEqual:@"expired"]);
    WPCheck(@"expirationPreservesDeliveredHistory", [WPRow(history, delivered)[@"state"] isEqual:@"delivered"]);
    history = [[WPCoupleHistory alloc] initWithURL:url];
    WPCheck(@"expiredStatePersistsAcrossReconstruction", history.pendingCount == 1 && [WPRow(history, queued)[@"state"] isEqual:@"expired"]);
    [history updateIdentifier:queued state:@"queued" serverTime:@(NSDate.date.timeIntervalSince1970)];
    WPCheck(@"lateAcceptedCannotReviveExpiredBadge", history.pendingCount == 1 && [WPRow(history, queued)[@"state"] isEqual:@"expired"]);

    NSURL *restartURL = WPURL(root, @"restart-expiration.json");
    WPCoupleHistory *beforeRestart = [[WPCoupleHistory alloc] initWithURL:restartURL];
    NSString *identifier = WPID();
    [beforeRestart enqueueKind:@"anger" identifier:identifier at:old];
    WPCoupleHistory *afterRestart = [[WPCoupleHistory alloc] initWithURL:restartURL];
    WPCheck(@"reconstructionAutomaticallyExpiresStaleOutgoing", afterRestart.pendingCount == 0 && [WPRow(afterRestart, identifier)[@"state"] isEqual:@"expired"]);
}

static void WPTestFailedWritesRollback(NSURL *root) {
    NSURL *url = WPURL(root, @"write-failure.json");
    WPCoupleHistory *history = [[WPCoupleHistory alloc] initWithURL:url];
    NSString *miss = WPID(), *old = WPID();
    [history enqueueKind:@"miss" identifier:miss at:NSDate.date];
    NSString *incomingID = WPID(); BOOL isNew = NO;
    [history receiveKind:@"anger" identifier:incomingID at:NSDate.date isNew:&isNew];
    [history enqueueKind:@"anger" identifier:old at:[NSDate dateWithTimeIntervalSinceNow:-90000]];
    NSData *snapshot = WPSnapshot(history), *persisted = [NSData dataWithContentsOfURL:url];
    NSUInteger pending = history.pendingCount;
    NSURL *backup = nil;
    BOOL blocked = WPBlockDestination(url, &backup);
    WPCheck(@"failureFixtureUsesActualFilesystemCollision", blocked);
    if (!blocked) return;
    __block NSUInteger notifications = 0;
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:WPCoupleHistoryDidChangeNotification object:history queue:nil usingBlock:^(__unused NSNotification *note) { notifications++; }];
    @try {
        BOOL saved = [history enqueueKind:@"anger" identifier:WPID() at:NSDate.date];
        WPCheck(@"failedEnqueueRollsBackMemoryAndBadge", !saved && history.pendingCount == pending && [WPSnapshot(history) isEqualToData:snapshot]);
        saved = [history updateIdentifier:miss state:@"delivered" serverTime:nil];
        WPCheck(@"failedDeliveryWritePreservesTransportAndIncomingBadge", !saved && history.pendingCount == pending && history.badgeCount == 1 && [WPRow(history, miss)[@"state"] isEqual:@"waiting"] && [WPSnapshot(history) isEqualToData:snapshot]);
        saved = [history manuallyClearIncomingIdentifiers:@[incomingID]];
        WPCheck(@"failedReadSaveRollsBackIncomingBadge", !saved && history.badgeCount == 1 && [WPSnapshot(history) isEqualToData:snapshot]);
        saved = [history enqueueKind:@"miss" identifier:WPID() at:NSDate.date resolvingIncomingIdentifiers:@[incomingID]];
        WPCheck(@"failedMissSaveRollsBackOutgoingAndIncoming", !saved && history.pendingCount == pending && history.badgeCount == 1 && [WPSnapshot(history) isEqualToData:snapshot]);
        BOOL isNew = YES;
        saved = [history receiveKind:@"miss" identifier:WPID() at:[NSDate dateWithTimeIntervalSinceNow:-600] isNew:&isNew];
        WPCheck(@"failedIncomingWriteCannotAcknowledgeOrRetainEvent", !saved && !isNew && [WPSnapshot(history) isEqualToData:snapshot]);
        [history expireOldOutgoing];
        WPCheck(@"failedExpirationWriteRollsBackStateAndBadge", history.pendingCount == pending && [WPRow(history, old)[@"state"] isEqual:@"waiting"] && [WPSnapshot(history) isEqualToData:snapshot]);
        WPCheck(@"failedWritesEmitNoChangeNotification", notifications == 0);
        WPCheck(@"failedWritesDoNotReplaceCollisionDirectory", [NSFileManager.defaultManager fileExistsAtPath:[url URLByAppendingPathComponent:@"sentinel"].path]);
    } @finally {
        [NSNotificationCenter.defaultCenter removeObserver:observer];
        WPCheck(@"filesystemFailureFixtureRestoresOriginalBytes", WPRestoreDestination(url, backup) && [[NSData dataWithContentsOfURL:url] isEqualToData:persisted]);
    }
    [history expireOldOutgoing];
    WPCoupleHistory *reloaded = [[WPCoupleHistory alloc] initWithURL:url];
    WPCheck(@"successfulRetryAfterWriteFailurePersists", reloaded.pendingCount == 1 && [WPRow(reloaded, old)[@"state"] isEqual:@"expired"]);
}

int main(int argc, char **argv) {
    @autoreleasepool {
        WPHistoryResults = [NSMutableDictionary new];
        NSString *base = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : [NSFileManager.defaultManager.currentDirectoryPath stringByAppendingPathComponent:@"work"];
        NSURL *root = [NSURL fileURLWithPath:[base stringByAppendingPathComponent:[@"history-fixtures-" stringByAppendingString:WPID()]] isDirectory:YES];
        BOOL created = [NSFileManager.defaultManager createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:NULL];
        WPCheck(@"fixtureDirectoryCreated", created);
        @try {
            if (created) { WPTestPendingAndDelivery(root); WPTestIncomingUnreadAndSnapshot(root); WPTestIncomingDeduplication(root); WPTestExpiration(root); WPTestFailedWritesRollback(root); }
            WPCheck(@"contractsCompletedWithoutException", YES);
        } @catch (NSException *exception) {
            WPCheck(@"contractsCompletedWithoutException", NO);
            fprintf(stderr, "Exception: %s\n", exception.reason.UTF8String);
        }
        BOOL all = YES;
        for (NSNumber *value in WPHistoryResults.allValues) all &= value.boolValue;
        NSMutableDictionary *report = [WPHistoryResults mutableCopy];
        report[@"caseCount"] = @(WPHistoryResults.count);
        report[@"allPassed"] = @(all);
        report[@"fixtureDirectory"] = root.path;
        NSData *json = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:NULL];
        fwrite(json.bytes, 1, json.length, stdout); puts("");
        if (all) [NSFileManager.defaultManager removeItemAtURL:root error:NULL];
        return all ? 0 : 1;
    }
}
