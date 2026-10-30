#import "WPCoupleHistory.h"
#import <math.h>

NSString * const WPCoupleHistoryDidChangeNotification=@"WeChatPet.CoupleHistoryDidChange";
const NSTimeInterval WPMissResponseWindow=300;
NSString *WPInteractionTitle(NSString *kind){return [kind isEqual:@"anger"]?@"生气了":([kind isEqual:@"pet"]?@"摸摸头":@"想你了");}
static BOOL WPValidKind(id kind){return [@[@"miss",@"anger",@"pet"] containsObject:kind];}
static BOOL WPValidID(id value){return [value isKindOfClass:NSString.class] && [[NSUUID alloc] initWithUUIDString:value]!=nil;}
static BOOL WPValidStamp(id value){return [value isKindOfClass:NSNumber.class] && isfinite([value doubleValue]);}
static BOOL WPIsPending(NSDictionary *row){return ![@[@"delivered",@"expired"] containsObject:row[@"state"]];}
/// The server has persisted the outgoing row, so a reply snapshot may resolve.
static BOOL WPServerHasOutgoing(NSString *state){return [@[@"queued",@"online",@"delivered"] containsObject:state];}
static BOOL WPNeedsResponse(NSDictionary *row){return [row[@"needs_response"] boolValue];}
static NSArray *WPValidIDs(id value){
    NSMutableOrderedSet *result=[NSMutableOrderedSet new];
    if([value isKindOfClass:NSArray.class])for(id identifier in value)if(WPValidID(identifier))[result addObject:identifier];
    return result.array;
}

@interface WPCoupleHistory ()
@property(nonatomic) NSURL *url;
@property(nonatomic) NSMutableArray<NSDictionary *> *outgoing;
@property(nonatomic) NSMutableArray<NSDictionary *> *incoming;
@property(nonatomic) BOOL initializing;
@property(nonatomic) BOOL automaticRetention;
@property(nonatomic) BOOL retentionSuspended;
@property(nonatomic) NSTimer *retentionTimer;
@property(nonatomic) NSUInteger loadedBytes;
@property(nonatomic) NSTimeInterval loadMilliseconds;
@property(nonatomic) NSTimeInterval lastSaveMilliseconds;
@property(nonatomic) NSTimeInterval maxSaveMilliseconds;
@end
@implementation WPCoupleHistory
+ (instancetype)sharedHistory{
    static WPCoupleHistory *history;static dispatch_once_t once;dispatch_once(&once,^{
        NSURL *base=[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
        history=[[self alloc] initWithURL:[[base URLByAppendingPathComponent:@"WeChatPet" isDirectory:YES] URLByAppendingPathComponent:@"interactions.json"]];
        history.automaticRetention=YES;
        [NSNotificationCenter.defaultCenter addObserver:history selector:@selector(retentionWillResume:) name:@"UIApplicationDidBecomeActiveNotification" object:nil];
        [NSNotificationCenter.defaultCenter addObserver:history selector:@selector(retentionBecameActive:) name:@"WeChatPet.RecoveryMaintenance" object:nil];
        [NSNotificationCenter.defaultCenter addObserver:history selector:@selector(retentionEnteredBackground:) name:@"UIApplicationDidEnterBackgroundNotification" object:nil];
        [history scheduleRetentionCleanup];
    });return history;
}
- (instancetype)initWithURL:(NSURL *)url{
    if((self=[super init])){
        NSTimeInterval started=NSProcessInfo.processInfo.systemUptime;
        _url=url;_outgoing=[NSMutableArray new];_incoming=[NSMutableArray new];_initializing=YES;
        NSData *data=[NSData dataWithContentsOfURL:url];id saved=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
        self.loadedBytes=data.length;
        if([saved isKindOfClass:NSDictionary.class]){
            NSInteger version=[saved[@"version"] isKindOfClass:NSNumber.class]?[saved[@"version"] integerValue]:1;
            NSMutableSet *outgoingIDs=[NSMutableSet new],*incomingIDs=[NSMutableSet new];
            for(NSString *key in @[@"outgoing",@"incoming"]){
                BOOL isOutgoing=[key isEqual:@"outgoing"];
                NSArray *rows=[saved[key] isKindOfClass:NSArray.class]?saved[key]:@[];
                for(id row in rows){
                    if(![row isKindOfClass:NSDictionary.class] || !WPValidID(row[@"id"]) || !WPValidKind(row[@"kind"]) || !WPValidStamp(row[@"sent_at"]))continue;
                    NSMutableSet *seen=isOutgoing?outgoingIDs:incomingIDs;
                    if([seen containsObject:row[@"id"]])continue;
                    NSMutableDictionary *safe=[@{@"id":row[@"id"],@"kind":row[@"kind"],@"sent_at":row[@"sent_at"],@"direction":isOutgoing?@"outgoing":@"incoming"} mutableCopy];
                    if(isOutgoing){
                        if(![@[@"waiting",@"queued",@"online",@"failed",@"delivered",@"expired"] containsObject:row[@"state"]])continue;
                        safe[@"state"]=row[@"state"];
                        NSArray *resolves=WPValidIDs(row[@"resolves"]);
                        if(resolves.count && [@[@"miss",@"pet"] containsObject:row[@"kind"]])safe[@"resolves"]=resolves;
                        if([row[@"resolved_count"] isKindOfClass:NSNumber.class])safe[@"resolved_count"]=row[@"resolved_count"];
                    } else if(version>=3){
                        safe[@"received_at"]=WPValidStamp(row[@"received_at"])?row[@"received_at"]:row[@"sent_at"];
                        safe[@"needs_response"]=@([row[@"needs_response"] isKindOfClass:NSNumber.class] && [row[@"needs_response"] boolValue]);
                        safe[@"animation_played"]=@([row[@"animation_played"] isKindOfClass:NSNumber.class] && [row[@"animation_played"] boolValue]);
                        if(![safe[@"needs_response"] boolValue] && [@[@"reply",@"manual_clear"] containsObject:row[@"resolve_type"]]){
                            safe[@"resolve_type"]=row[@"resolve_type"];
                            if(WPValidStamp(row[@"resolved_at"]))safe[@"resolved_at"]=row[@"resolved_at"];
                        }
                    } else {
                        // v1 never tracked processing, so old history must not
                        // become new badges. v2 "unread" rows keep their badge.
                        BOOL unread=version>=2 && [row[@"unread"] isKindOfClass:NSNumber.class] && [row[@"unread"] boolValue];
                        safe[@"received_at"]=row[@"sent_at"];safe[@"needs_response"]=@(unread);safe[@"animation_played"]=@YES;
                    }
                    if(!isOutgoing)safe[@"unread"]=safe[@"needs_response"]; // Read by 0.3.3/0.3.4 after a downgrade.
                    [seen addObject:row[@"id"]];
                    [(isOutgoing?_outgoing:_incoming) addObject:safe];
                }
            }
        }
        // A legacy, not-yet-accepted "miss" may contain anger IDs. Keep the
        // historical result of accepted sends but narrow pending snapshots.
        NSMutableDictionary<NSString *,NSString *> *incomingKinds=[NSMutableDictionary new];
        for(NSDictionary *row in _incoming)incomingKinds[row[@"id"]]=row[@"kind"];
        for(NSUInteger i=0;i<_outgoing.count;i++){
            NSDictionary *row=_outgoing[i];
            if(![row[@"kind"] isEqual:@"miss"] || ![row[@"resolves"] count])continue;
            NSMutableArray *ordinary=[NSMutableArray new];
            for(NSString *identifier in row[@"resolves"])
                if(incomingKinds[identifier] && ![incomingKinds[identifier] isEqual:@"anger"])[ordinary addObject:identifier];
            NSMutableDictionary *updated=row.mutableCopy;
            if(ordinary.count)updated[@"resolves"]=ordinary;else [updated removeObjectForKey:@"resolves"];
            _outgoing[i]=updated;
        }
        [self expireOldOutgoing];
        [self purgeRecordsOlderThanThreeDays];
        _initializing=NO;
        self.loadMilliseconds=(NSProcessInfo.processInfo.systemUptime-started)*1000;
    }return self;
}
- (NSArray<NSDictionary *> *)pendingOutgoing{
    NSMutableArray *result=[NSMutableArray new];for(NSDictionary *row in self.outgoing)if(WPIsPending(row))[result addObject:[row copy]];return result;
}
- (NSUInteger)pendingCount{return self.pendingOutgoing.count;}
- (NSUInteger)badgeCount{NSUInteger count=0;for(NSDictionary *row in self.incoming)if(WPNeedsResponse(row))count++;return count;}
- (BOOL)hasPendingAnger{for(NSDictionary *row in self.incoming)if(WPNeedsResponse(row) && [row[@"kind"] isEqual:@"anger"])return YES;return NO;}
- (NSArray<NSDictionary *> *)pendingIncoming{
    NSMutableArray *rows=[NSMutableArray new];
    for(NSDictionary *row in self.incoming)if(WPNeedsResponse(row))[rows addObject:[row copy]];
    [rows sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [b[@"sent_at"] compare:a[@"sent_at"]];}];
    return rows;
}
- (NSArray<NSString *> *)uncoveredPendingIncomingIdentifiers{
    return [self responseIdentifiersForKind:@"miss"];
}
- (NSArray<NSString *> *)responseIdentifiersForKind:(NSString *)kind{
    NSMutableSet<NSString *> *reserved=[NSMutableSet new];
    for(NSDictionary *row in self.outgoing){
        if(![@[@"miss",@"pet"] containsObject:row[@"kind"]] || ![row[@"state"] isEqual:@"waiting"])continue;
        [reserved addObjectsFromArray:WPValidIDs(row[@"resolves"])];
    }
    NSMutableArray<NSString *> *identifiers=[NSMutableArray new];
    NSArray *oldestFirst=[self.pendingIncoming sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){
        return [a[@"sent_at"] compare:b[@"sent_at"]];
    }];
    BOOL angerSelected=NO;
    for(NSDictionary *row in oldestFirst){
        if([reserved containsObject:row[@"id"]])continue;
        if([row[@"kind"] isEqual:@"anger"]){
            if([kind isEqual:@"pet"] && !angerSelected){[identifiers addObject:row[@"id"]];angerSelected=YES;}
        }else [identifiers addObject:row[@"id"]];
    }
    return identifiers;
}
- (NSArray<NSDictionary *> *)recentInteractions{
    NSMutableArray *rows=[self.outgoing mutableCopy];[rows addObjectsFromArray:self.incoming];
    [rows sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [b[@"sent_at"] compare:a[@"sent_at"]];}];return rows;
}
- (BOOL)save{
    NSTimeInterval started=NSProcessInfo.processInfo.systemUptime;
    [NSFileManager.defaultManager createDirectoryAtURL:self.url.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"version":@3,@"outgoing":self.outgoing,@"incoming":self.incoming} options:0 error:nil];
    BOOL stored=[data writeToURL:self.url options:NSDataWritingAtomic error:nil];
    self.lastSaveMilliseconds=(NSProcessInfo.processInfo.systemUptime-started)*1000;
    self.maxSaveMilliseconds=MAX(self.maxSaveMilliseconds,self.lastSaveMilliseconds);
    if(!stored)return NO;
    // initWithURL can expire old rows while sharedHistory's dispatch_once is
    // still running. An observer reading sharedHistory here would deadlock.
    if(!self.initializing)[NSNotificationCenter.defaultCenter postNotificationName:WPCoupleHistoryDidChangeNotification object:self];
    [self scheduleRetentionCleanup];
    return YES;
}
/// Resolves only rows that still need a response, so later rows and rows
/// resolved another way keep their state.
- (NSUInteger)resolveIncomingInMemory:(NSArray<NSString *> *)identifiers type:(NSString *)type{
    NSSet *selected=[NSSet setWithArray:WPValidIDs(identifiers)];NSUInteger changed=0;
    NSNumber *now=@(NSDate.date.timeIntervalSince1970);
    for(NSUInteger i=0;i<self.incoming.count;i++){
        NSDictionary *row=self.incoming[i];
        if(!WPNeedsResponse(row) || ![selected containsObject:row[@"id"]])continue;
        NSMutableDictionary *next=[row mutableCopy];
        next[@"needs_response"]=@NO;next[@"unread"]=@NO;next[@"resolve_type"]=type;next[@"resolved_at"]=now;
        self.incoming[i]=next;changed++;
    }
    return changed;
}
- (BOOL)manuallyClearIncomingIdentifiers:(NSArray<NSString *> *)identifiers{
    NSArray *before=[self.incoming copy];
    if(![self resolveIncomingInMemory:identifiers type:@"manual_clear"])return YES;
    if([self save])return YES;self.incoming=[before mutableCopy];return NO;
}
- (BOOL)markAnimationPlayedIdentifiers:(NSArray<NSString *> *)identifiers{
    NSSet *selected=[NSSet setWithArray:WPValidIDs(identifiers)];NSArray *before=[self.incoming copy];BOOL changed=NO;
    for(NSUInteger i=0;i<self.incoming.count;i++){
        NSDictionary *row=self.incoming[i];if([row[@"animation_played"] boolValue] || ![selected containsObject:row[@"id"]])continue;
        NSMutableDictionary *next=[row mutableCopy];next[@"animation_played"]=@YES;self.incoming[i]=next;changed=YES;
    }
    if(!changed || [self save])return YES;self.incoming=[before mutableCopy];return NO;
}
- (BOOL)enqueueKind:(NSString *)kind identifier:(NSString *)identifier at:(NSDate *)date{
    return [self enqueueKind:kind identifier:identifier at:date resolvingIncomingIdentifiers:@[]];
}
- (BOOL)enqueueKind:(NSString *)kind identifier:(NSString *)identifier at:(NSDate *)date resolvingIncomingIdentifiers:(NSArray<NSString *> *)identifiers{
    if(!WPValidKind(kind) || !WPValidID(identifier) || self.pendingCount>=100)return NO;
    for(NSDictionary *row in self.outgoing)if([row[@"id"] isEqual:identifier])return YES;
    NSArray *before=[self.outgoing copy];
    NSMutableDictionary *row=[@{@"id":identifier,@"kind":kind,@"sent_at":@(date.timeIntervalSince1970),@"direction":@"outgoing",@"state":@"waiting"} mutableCopy];
    NSMutableArray *resolves=[NSMutableArray new];
    if([@[@"miss",@"pet"] containsObject:kind]){
        NSSet *requested=[NSSet setWithArray:WPValidIDs(identifiers)];
        BOOL capturedAnger=NO;
        NSArray *oldest=[self.pendingIncoming sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [a[@"sent_at"] compare:b[@"sent_at"]];}];
        for(NSDictionary *incoming in oldest){
            if(![requested containsObject:incoming[@"id"]])continue;
            if([incoming[@"kind"] isEqual:@"anger"]){
                if([kind isEqual:@"pet"] && !capturedAnger){[resolves addObject:incoming[@"id"]];capturedAnger=YES;}
            }else [resolves addObject:incoming[@"id"]];
        }
    }
    if(resolves.count)row[@"resolves"]=resolves;
    [self.outgoing addObject:row];
    // Keep the full local interaction record. Trimming acknowledged rows here
    // silently erased old chat bubbles even though the send had succeeded.
    if([self save])return YES;
    self.outgoing=[before mutableCopy];return NO;
}
- (BOOL)updateIdentifier:(NSString *)identifier state:(NSString *)state serverTime:(NSNumber *)stamp{
    if(![@[@"waiting",@"queued",@"online",@"failed",@"delivered",@"expired"] containsObject:state])return NO;
    for(NSUInteger index=0;index<self.outgoing.count;index++){
        NSDictionary *row=self.outgoing[index];if(![row[@"id"] isEqual:identifier])continue;
        if([row[@"state"] isEqual:@"delivered"] && ![state isEqual:@"delivered"])return YES;
        if([row[@"state"] isEqual:@"expired"] && ![@[@"delivered",@"expired"] containsObject:state])return YES;
        NSMutableDictionary *next=[row mutableCopy];next[@"state"]=state;
        if([stamp isKindOfClass:NSNumber.class] && isfinite(stamp.doubleValue) && stamp.doubleValue>0)next[@"sent_at"]=stamp;
        NSArray *incomingBefore=[self.incoming copy];
        if(WPServerHasOutgoing(state) && [row[@"resolves"] count]){
            // The snapshot taken when the reply was sent; newer rows stay pending.
            next[@"resolved_count"]=@([self resolveIncomingInMemory:row[@"resolves"] type:@"reply"]);
            [next removeObjectForKey:@"resolves"];
        }
        if([next isEqualToDictionary:row])return YES;
        self.outgoing[index]=next;if([self save])return YES;
        self.outgoing[index]=row;self.incoming=[incomingBefore mutableCopy];return NO;
    }return NO;
}
- (BOOL)receiveKind:(NSString *)kind identifier:(NSString *)identifier at:(NSDate *)date isNew:(BOOL *)isNew{
    return [self receiveKind:kind identifier:identifier at:date receivedAt:NSDate.date isNew:isNew];
}
- (BOOL)receiveKind:(NSString *)kind identifier:(NSString *)identifier at:(NSDate *)date receivedAt:(NSDate *)receivedAt isNew:(BOOL *)isNew{
    if(isNew)*isNew=NO;if(!WPValidKind(kind) || !WPValidID(identifier))return NO;
    if(!isfinite(date.timeIntervalSince1970) || !isfinite(receivedAt.timeIntervalSince1970))return NO;
    // A delayed replay is acknowledged without recreating an expired reminder.
    if(date.timeIntervalSince1970<=NSDate.date.timeIntervalSince1970-3.0*86400.0)return YES;
    for(NSDictionary *row in self.incoming)if([row[@"id"] isEqual:identifier])return YES;
    NSArray *before=[self.incoming copy];
    // Each row decides independently, so a coalesced animation never merges badges.
    BOOL needsResponse=[kind isEqual:@"anger"] || [receivedAt timeIntervalSinceDate:date]>WPMissResponseWindow;
    [self.incoming addObject:@{@"id":identifier,@"kind":kind,@"sent_at":@(date.timeIntervalSince1970),@"direction":@"incoming",
        @"received_at":@(receivedAt.timeIntervalSince1970),@"needs_response":@(needsResponse),@"unread":@(needsResponse),@"animation_played":@NO}];
    // Keep every received row, including processed history and pending badges.
    // A cap here could discard a late interaction before the user sees it.
    if([self save]){if(isNew)*isNew=YES;return YES;}self.incoming=[before mutableCopy];return NO;
}
- (void)expireOldOutgoing{
    NSArray *before=[self.outgoing copy];BOOL changed=NO;NSTimeInterval threshold=NSDate.date.timeIntervalSince1970-86400;
    for(NSUInteger i=0;i<self.outgoing.count;i++){NSDictionary *row=self.outgoing[i];if(WPIsPending(row) && [row[@"sent_at"] doubleValue]<threshold){NSMutableDictionary *next=[row mutableCopy];next[@"state"]=@"expired";self.outgoing[i]=next;changed=YES;}}
    if(changed && ![self save])self.outgoing=[before mutableCopy];
}
- (BOOL)expireAllPending{
    NSArray *before=[self.outgoing copy];BOOL changed=NO;
    for(NSUInteger i=0;i<self.outgoing.count;i++){NSDictionary *row=self.outgoing[i];if(WPIsPending(row)){NSMutableDictionary *next=[row mutableCopy];next[@"state"]=@"expired";self.outgoing[i]=next;changed=YES;}}
    if(!changed || [self save])return YES;self.outgoing=[before mutableCopy];return NO;
}
- (void)purgeRecordsOlderThanThreeDays{[self purgeRecordsExpiredAtDate:NSDate.date];}
- (BOOL)purgeRecordsExpiredAtDate:(NSDate *)date{
    if(![date isKindOfClass:NSDate.class] || !isfinite(date.timeIntervalSince1970))return NO;
    NSTimeInterval threshold=date.timeIntervalSince1970-(3.0*86400.0);
    NSArray *outgoingBefore=self.outgoing.copy,*incomingBefore=self.incoming.copy;
    BOOL changed=NO;
    for(NSInteger i=(NSInteger)self.outgoing.count-1;i>=0;i--){
        NSDictionary *row=self.outgoing[(NSUInteger)i];
        if([row[@"sent_at"] doubleValue]<=threshold){
            [self.outgoing removeObjectAtIndex:(NSUInteger)i];
            changed=YES;
        }
    }
    for(NSInteger i=(NSInteger)self.incoming.count-1;i>=0;i--){
        NSDictionary *row=self.incoming[(NSUInteger)i];
        if([row[@"sent_at"] doubleValue]<=threshold){
            [self.incoming removeObjectAtIndex:(NSUInteger)i];
            changed=YES;
        }
    }
    if(!changed)return YES;
    if([self save])return YES;
    self.outgoing=outgoingBefore.mutableCopy;self.incoming=incomingBefore.mutableCopy;return NO;
}
- (BOOL)clearAllHistory{
    NSArray *outgoingBefore=self.outgoing.copy,*incomingBefore=self.incoming.copy;
    [self.outgoing removeAllObjects];
    [self.incoming removeAllObjects];
    if([self save])return YES;
    self.outgoing=outgoingBefore.mutableCopy;self.incoming=incomingBefore.mutableCopy;return NO;
}
- (void)scheduleRetentionCleanup{
    [self.retentionTimer invalidate];self.retentionTimer=nil;
    if(!self.automaticRetention || self.retentionSuspended)return;
    NSTimeInterval next=DBL_MAX;
    for(NSDictionary *row in self.outgoing)next=MIN(next,[row[@"sent_at"] doubleValue]+3.0*86400.0);
    for(NSDictionary *row in self.incoming)next=MIN(next,[row[@"sent_at"] doubleValue]+3.0*86400.0);
    if(next==DBL_MAX)return;
    __weak typeof(self) weakSelf=self;
    self.retentionTimer=[NSTimer timerWithTimeInterval:MAX(1,next-NSDate.date.timeIntervalSince1970) repeats:NO block:^(__unused NSTimer *timer){
        WPCoupleHistory *self=weakSelf;if(!self)return;self.retentionTimer=nil;
        BOOL saved=[self purgeRecordsExpiredAtDate:NSDate.date];
        if(saved)[self scheduleRetentionCleanup];
        else {self.retentionTimer=[NSTimer timerWithTimeInterval:60 repeats:NO block:^(__unused NSTimer *retry){[weakSelf retentionBecameActive:nil];}];[NSRunLoop.mainRunLoop addTimer:self.retentionTimer forMode:NSRunLoopCommonModes];}
    }];self.retentionTimer.tolerance=1;[NSRunLoop.mainRunLoop addTimer:self.retentionTimer forMode:NSRunLoopCommonModes];
}
- (void)retentionWillResume:(NSNotification *)note{
    if(!self.retentionSuspended)return;self.retentionSuspended=NO;
    // The recovery coordinator normally requests maintenance earlier. This
    // fallback still enforces retention when the visible plugin is paused.
    __weak typeof(self) weakSelf=self;
    self.retentionTimer=[NSTimer timerWithTimeInterval:1 repeats:NO block:^(__unused NSTimer *timer){[weakSelf retentionBecameActive:nil];}];
    [NSRunLoop.mainRunLoop addTimer:self.retentionTimer forMode:NSRunLoopCommonModes];
}
- (void)retentionBecameActive:(NSNotification *)note{self.retentionSuspended=NO;[self.retentionTimer invalidate];self.retentionTimer=nil;[self purgeRecordsOlderThanThreeDays];[self scheduleRetentionCleanup];}
- (void)retentionEnteredBackground:(NSNotification *)note{self.retentionSuspended=YES;[self.retentionTimer invalidate];self.retentionTimer=nil;}
- (NSDictionary<NSString *,NSNumber *> *)diagnostics{return @{@"loadedBytes":@(self.loadedBytes),@"loadMilliseconds":@(self.loadMilliseconds),@"lastSaveMilliseconds":@(self.lastSaveMilliseconds),@"maxSaveMilliseconds":@(self.maxSaveMilliseconds),@"incomingCount":@(self.incoming.count),@"outgoingCount":@(self.outgoing.count)};}
- (void)dealloc{[self.retentionTimer invalidate];[NSNotificationCenter.defaultCenter removeObserver:self];}
@end
