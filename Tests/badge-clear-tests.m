#import <Foundation/Foundation.h>
#import "WPCoupleHistory.h"

// 0.3.3 badge contract: only unprocessed incoming interactions count. These
// tests use isolated JSON files and Foundation; no phone, socket, or keychain.
static NSMutableDictionary<NSString *, NSNumber *> *WPBadgeResults;
static void WPBadgeCheck(NSString *name, BOOL passed) {
    WPBadgeResults[name] = @(passed);
    if (!passed) fprintf(stderr, "FAIL: %s\n", name.UTF8String);
}
static NSString *WPBadgeID(void) { return NSUUID.UUID.UUIDString; }
static NSDictionary *WPBadgeRow(WPCoupleHistory *history, NSString *identifier) {
    for (NSDictionary *row in history.recentInteractions) if ([row[@"id"] isEqual:identifier]) return row;
    return nil;
}
static NSData *WPBadgeSnapshot(WPCoupleHistory *history) {
    return [NSJSONSerialization dataWithJSONObject:history.recentInteractions options:NSJSONWritingSortedKeys error:NULL];
}
static BOOL WPBadgeBlockFile(NSURL *url, NSURL **backup) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *saved = [url URLByAppendingPathExtension:@"saved"];
    if (![fm moveItemAtURL:url toURL:saved error:NULL]) return NO;
    if (![fm createDirectoryAtURL:url withIntermediateDirectories:NO attributes:nil error:NULL]) {
        [fm moveItemAtURL:saved toURL:url error:NULL]; return NO;
    }
    [@"sentinel" writeToURL:[url URLByAppendingPathComponent:@"sentinel"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    *backup = saved; return YES;
}
static BOOL WPBadgeRestoreFile(NSURL *url, NSURL *backup) {
    NSFileManager *fm = NSFileManager.defaultManager;
    return [fm removeItemAtURL:url error:NULL] && [fm moveItemAtURL:backup toURL:url error:NULL];
}

static void WPBadgeTestIncomingOnly(NSURL *root) {
    NSURL *url = [root URLByAppendingPathComponent:@"incoming-only.json"];
    WPCoupleHistory *history = [[WPCoupleHistory alloc] initWithURL:url];
    NSString *outgoing = WPBadgeID(), *incomingMiss = WPBadgeID(), *incomingAnger = WPBadgeID();
    BOOL setup = [history enqueueKind:@"anger" identifier:outgoing at:NSDate.date];
    setup &= [history updateIdentifier:outgoing state:@"queued" serverTime:nil];
    BOOL isNew = NO;
    setup &= [history receiveKind:@"miss" identifier:incomingMiss at:[NSDate dateWithTimeIntervalSinceNow:-600] isNew:&isNew] && isNew;
    setup &= [history receiveKind:@"anger" identifier:incomingAnger at:NSDate.date isNew:&isNew] && isNew;
    WPBadgeCheck(@"outgoingDoesNotCountButIncomingUnreadDoes", setup && history.badgeCount == 2 && history.pendingIncoming.count == 2);
    WPBadgeCheck(@"openingHistoryHasNoImplicitReadSideEffect", history.badgeCount == 2);
    WPBadgeCheck(@"unknownReadIdentifierIsIdempotent", [history manuallyClearIncomingIdentifiers:@[WPBadgeID()]] && history.badgeCount == 2);
    WPBadgeCheck(@"markReadChangesOnlySelectedIncomingState", [history manuallyClearIncomingIdentifiers:@[incomingMiss]] && history.badgeCount == 1 && ![WPBadgeRow(history, incomingMiss)[@"unread"] boolValue] && [WPBadgeRow(history, incomingAnger)[@"unread"] boolValue]);
    NSString *later = WPBadgeID();
    [history receiveKind:@"miss" identifier:later at:[NSDate dateWithTimeIntervalSinceNow:-600] isNew:&isNew];
    WPBadgeCheck(@"incomingAfterReadSnapshotRemainsUnread", history.badgeCount == 2 && [WPBadgeRow(history, later)[@"unread"] boolValue]);
    WPBadgeCheck(@"readDoesNotAffectOutgoingQueueOrTransport", history.pendingCount == 1 && [WPBadgeRow(history, outgoing)[@"state"] isEqual:@"queued"]);
    history = [[WPCoupleHistory alloc] initWithURL:url];
    WPBadgeCheck(@"incomingReadStateSurvivesReconstruction", history.badgeCount == 2 && ![WPBadgeRow(history, incomingMiss)[@"unread"] boolValue]);
}

static void WPBadgeTestMissAtomicClear(NSURL *root) {
    NSURL *url = [root URLByAppendingPathComponent:@"miss-atomic.json"];
    WPCoupleHistory *history = [[WPCoupleHistory alloc] initWithURL:url];
    NSString *first = WPBadgeID(), *second = WPBadgeID(); BOOL isNew = NO;
    [history receiveKind:@"anger" identifier:first at:NSDate.date isNew:&isNew];
    [history receiveKind:@"miss" identifier:second at:[NSDate dateWithTimeIntervalSinceNow:-600] isNew:&isNew];
    NSString *reply = WPBadgeID();
    BOOL queuedReply = [history enqueueKind:@"miss" identifier:reply at:NSDate.date resolvingIncomingIdentifiers:@[first, second]];
    WPBadgeCheck(@"savedReplyKeepsBadgeBeforeServerAccepts", queuedReply && history.badgeCount == 2 && history.pendingCount == 1);
    WPBadgeCheck(@"savedMissClearsOnlyOrdinaryIncoming", [history updateIdentifier:reply state:@"online" serverTime:nil] && history.badgeCount == 1 && history.hasPendingAnger && history.pendingCount == 1);
    WPBadgeCheck(@"atomicMissDoesNotChangeOtherTransportRows", [WPBadgeRow(history, reply)[@"state"] isEqual:@"online"] && [WPBadgeRow(history, first)[@"kind"] isEqual:@"anger"]);
    NSString *later = WPBadgeID();
    [history receiveKind:@"anger" identifier:later at:NSDate.date isNew:&isNew];
    WPBadgeCheck(@"laterIncomingSurvivesEarlierMissBoundary", history.badgeCount == 2 && [WPBadgeRow(history, later)[@"unread"] boolValue]);
    NSString *angerReply=WPBadgeID();
    BOOL angerSaved=[history enqueueKind:@"anger" identifier:angerReply at:NSDate.date resolvingIncomingIdentifiers:@[later]] && [history updateIdentifier:angerReply state:@"queued" serverTime:nil];
    WPBadgeCheck(@"angerWithSnapshotStillDoesNotClearIncoming", angerSaved && history.badgeCount==2 && [WPBadgeRow(history,later)[@"unread"] boolValue]);
}

static void WPBadgeTestMigrationAndPersistentDedup(NSURL *root) {
    NSURL *url=[root URLByAppendingPathComponent:@"migration.json"];
    NSString *old=WPBadgeID(),*outgoing=WPBadgeID();NSNumber *stamp=@(NSDate.date.timeIntervalSince1970);
    NSDictionary *oldRow=@{@"id":old,@"kind":@"anger",@"sent_at":stamp,@"unread":@YES};
    NSDictionary *v1=@{@"version":@1,@"incoming":@[oldRow,oldRow],@"outgoing":@[@{@"id":outgoing,@"kind":@"miss",@"sent_at":stamp,@"state":@"queued"}]};
    [[NSJSONSerialization dataWithJSONObject:v1 options:0 error:NULL] writeToURL:url atomically:YES];
    WPCoupleHistory *history=[[WPCoupleHistory alloc] initWithURL:url];
    WPBadgeCheck(@"v1MigrationDoesNotTurnOldIncomingRed", history.badgeCount==0 && history.pendingCount==1 && history.recentInteractions.count==2);
    BOOL isNew=YES;
    WPBadgeCheck(@"v1DuplicateReplayStaysRead", [history receiveKind:@"anger" identifier:old at:NSDate.date isNew:&isNew] && !isNew && history.badgeCount==0);
    NSString *fresh=WPBadgeID();isNew=NO;
    WPBadgeCheck(@"newIncomingAfterV1MigrationIsUnread", [history receiveKind:@"miss" identifier:fresh at:[NSDate dateWithTimeIntervalSinceNow:-600] isNew:&isNew] && isNew && history.badgeCount==1);
    NSDictionary *saved=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:url] options:0 error:NULL];
    WPBadgeCheck(@"migrationPersistsV2ReadMarkers", [saved[@"version"] integerValue]>=2 && ![WPBadgeRow(history,old)[@"unread"] boolValue] && [WPBadgeRow(history,fresh)[@"unread"] boolValue]);
    history=[[WPCoupleHistory alloc] initWithURL:url];isNew=YES;
    WPBadgeCheck(@"v2RestartAndReplayPreserveOneUnread", [history receiveKind:@"miss" identifier:fresh at:[NSDate dateWithTimeIntervalSinceNow:-600] isNew:&isNew] && !isNew && history.badgeCount==1 && history.recentInteractions.count==3);
    [history manuallyClearIncomingIdentifiers:@[fresh]];history=[[WPCoupleHistory alloc] initWithURL:url];isNew=YES;
    WPBadgeCheck(@"v2ReadIncomingDoesNotBecomeUnreadOnReplay", [history receiveKind:@"miss" identifier:fresh at:[NSDate dateWithTimeIntervalSinceNow:-600] isNew:&isNew] && !isNew && history.badgeCount==0);
}

static void WPBadgeTestBothDirections(NSURL *root) {
    WPCoupleHistory *a=[[WPCoupleHistory alloc] initWithURL:[root URLByAppendingPathComponent:@"peer-a.json"]];
    WPCoupleHistory *b=[[WPCoupleHistory alloc] initWithURL:[root URLByAppendingPathComponent:@"peer-b.json"]];
    NSString *miss=WPBadgeID(),*anger=WPBadgeID();BOOL isNew=NO;
    [a enqueueKind:@"miss" identifier:miss at:NSDate.date];
    [a updateIdentifier:miss state:@"queued" serverTime:nil];
    WPBadgeCheck(@"offlineSenderHasNoLocalRedDot", a.pendingCount==1 && a.badgeCount==0 && b.badgeCount==0);
    [b receiveKind:@"miss" identifier:miss at:[NSDate dateWithTimeIntervalSinceNow:-600] isNew:&isNew];
    [a updateIdentifier:miss state:@"delivered" serverTime:nil];
    WPBadgeCheck(@"queuedDeliveryOnlyMarksRecipientUnread", isNew && a.badgeCount==0 && a.pendingCount==0 && b.badgeCount==1);
    [b enqueueKind:@"anger" identifier:anger at:NSDate.date];
    [a receiveKind:@"anger" identifier:anger at:NSDate.date isNew:&isNew];
    WPBadgeCheck(@"reverseDeliveryMarksAWithoutClearingB", isNew && a.badgeCount==1 && b.badgeCount==1);
    NSString *reply=WPBadgeID();NSArray *snapshot=[b.pendingIncoming valueForKey:@"id"];
    [b enqueueKind:@"miss" identifier:reply at:NSDate.date resolvingIncomingIdentifiers:snapshot];
    [b updateIdentifier:reply state:@"queued" serverTime:nil];
    WPBadgeCheck(@"missReplyClearsOnlyReplyingDeviceBadge", a.badgeCount==1 && b.badgeCount==0);
}

static void WPBadgeTestFailedWritesRollback(NSURL *root) {
    NSURL *url = [root URLByAppendingPathComponent:@"failed-read.json"];
    WPCoupleHistory *history = [[WPCoupleHistory alloc] initWithURL:url];
    NSString *incoming = WPBadgeID(); BOOL isNew = NO;
    [history receiveKind:@"miss" identifier:incoming at:[NSDate dateWithTimeIntervalSinceNow:-600] isNew:&isNew];
    NSData *before = WPBadgeSnapshot(history), *diskBefore = [NSData dataWithContentsOfURL:url];
    NSURL *backup = nil; BOOL blocked = WPBadgeBlockFile(url, &backup);
    WPBadgeCheck(@"readFailureFixtureBlocksAtomicWrite", blocked);
    if (!blocked) return;
    __block NSUInteger notifications = 0;
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:WPCoupleHistoryDidChangeNotification object:history queue:nil usingBlock:^(__unused NSNotification *note) { notifications++; }];
    @try {
        WPBadgeCheck(@"failedReadPreservesUnreadBadge", ![history manuallyClearIncomingIdentifiers:@[incoming]] && history.badgeCount == 1);
        WPBadgeCheck(@"failedReadRollsBackMemoryAndEmitsNoChange", [WPBadgeSnapshot(history) isEqualToData:before] && notifications == 0);
        NSString *reply = WPBadgeID();
        WPBadgeCheck(@"failedMissDoesNotClearIncomingOrQueueReply", ![history enqueueKind:@"miss" identifier:reply at:NSDate.date resolvingIncomingIdentifiers:@[incoming]] && history.badgeCount == 1 && history.pendingCount == 0);
    } @finally {
        [NSNotificationCenter.defaultCenter removeObserver:observer];
        WPBadgeCheck(@"failedReadFixtureRestored", WPBadgeRestoreFile(url, backup) && [[NSData dataWithContentsOfURL:url] isEqualToData:diskBefore]);
    }
    history = [[WPCoupleHistory alloc] initWithURL:url];
    WPBadgeCheck(@"failedReadBadgeSurvivesRestart", history.badgeCount == 1 && history.pendingCount == 0);
}

int main(int argc, char **argv) {
    @autoreleasepool {
        WPBadgeResults = [NSMutableDictionary new];
        NSString *base = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : NSFileManager.defaultManager.currentDirectoryPath;
        NSURL *root = [NSURL fileURLWithPath:[base stringByAppendingPathComponent:[@"badge-v033-fixtures-" stringByAppendingString:WPBadgeID()]] isDirectory:YES];
        BOOL created = [NSFileManager.defaultManager createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:NULL];
        WPBadgeCheck(@"fixtureDirectoryCreated", created);
        if (created) { WPBadgeTestIncomingOnly(root); WPBadgeTestMissAtomicClear(root); WPBadgeTestMigrationAndPersistentDedup(root); WPBadgeTestBothDirections(root); WPBadgeTestFailedWritesRollback(root); }
        BOOL all = YES; for (NSNumber *passed in WPBadgeResults.allValues) all &= passed.boolValue;
        NSMutableDictionary *report = [WPBadgeResults mutableCopy]; report[@"caseCount"] = @(WPBadgeResults.count); report[@"allPassed"] = @(all);
        NSData *json = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:NULL];
        fwrite(json.bytes, 1, json.length, stdout); puts("");
        if (all) [NSFileManager.defaultManager removeItemAtURL:root error:NULL];
        return all ? 0 : 1;
    }
}
