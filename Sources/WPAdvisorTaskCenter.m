#import "WPAdvisorTaskCenter.h"
#import "WPCommon.h"
#import "WPSessionEligibility.h"
#import <CommonCrypto/CommonDigest.h>

NSNotificationName const WPAdvisorTasksDidChangeNotification=@"WPAdvisorTasksDidChange";
static const NSUInteger WPAdvisorMaxConcurrent=2, WPAdvisorMaxWaiting=12, WPAdvisorMaxHistory=100;
static const NSTimeInterval WPAdvisorHistoryLifetime=3*24*60*60;

static NSString *WPAdvisorSHA256(NSData *data){
    if(!data.length || data.length>UINT32_MAX)return nil;
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,digest);
    NSMutableString *value=[NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH*2];
    for(NSUInteger i=0;i<CC_SHA256_DIGEST_LENGTH;i++)[value appendFormat:@"%02x",digest[i]];return value;
}
NSString *WPAdvisorCurrentAccountFingerprint(void){
    if(!NSThread.isMainThread)return nil;
    id contact=WPSEReadObject(WPWeChatService(@"CContactMgr"),@[@"getSelfContact"]);
    id username=WPSEReadObject(contact,@[@"m_nsUsrName",@"m_nsUserName",@"username",@"userName"]);
    if(![username isKindOfClass:NSString.class] || ![username length] || [username length]>256)return nil;
    return WPAdvisorSHA256([username dataUsingEncoding:NSUTF8StringEncoding]);
}

@interface WPAdvisorTask ()
@property(nonatomic,copy,readwrite) NSString *identifier,*username,*displayName;
@property(nonatomic,readwrite) WPAdvisorTaskState state;
@property(nonatomic,readwrite) NSUInteger lineCount;
@property(nonatomic,strong,readwrite) NSDate *createdAt;
@property(nonatomic,strong,readwrite) WPChatAdvice *advice;
@property(nonatomic,copy,readwrite) NSString *error;
@property(nonatomic,readwrite) BOOL unread,stale;
@property(nonatomic,copy) NSArray<WPChatLine *> *pendingLines;
@property(nonatomic) BOOL group;
@property(nonatomic,strong) WPChatAdvisorRequest *request;
@property(nonatomic,copy) NSString *accountFingerprint,*contextFingerprint;
@end
@implementation WPAdvisorTask @end

static NSString *WPAdvisorContextFingerprint(NSArray<WPChatLine *> *lines,NSUInteger count){
    if(![lines isKindOfClass:NSArray.class] || !count || count>40 || lines.count<count)return nil;
    NSMutableArray *values=[NSMutableArray new];NSUInteger start=lines.count-count;
    for(NSUInteger i=start;i<lines.count;i++){
        id line=lines[i];if(![line isKindOfClass:WPChatLine.class] || ![[line text] isKindOfClass:NSString.class] || ![[line text] length] || ![[line date] isKindOfClass:NSDate.class])return nil;
        NSTimeInterval seconds=[[line date] timeIntervalSince1970];if(!isfinite(seconds) || seconds<=0 || seconds>4102444800)return nil;
        NSString *text=[line text];if(text.length>300)text=[text substringWithRange:[text rangeOfComposedCharacterSequencesForRange:NSMakeRange(0,300)]];
        [values addObject:@[@([line fromMe]),@((long long)floor(seconds)),text]];
    }
    NSData *json=[NSJSONSerialization dataWithJSONObject:values options:0 error:nil];return json?WPAdvisorSHA256(json):nil;
}
BOOL WPAdvisorTaskBelongsToCurrentAccount(WPAdvisorTask *task){
    NSString *current=WPAdvisorCurrentAccountFingerprint();return current.length && task.accountFingerprint.length && [task.accountFingerprint isEqualToString:current];
}
BOOL WPAdvisorTaskMatchesLines(WPAdvisorTask *task,NSArray<WPChatLine *> *lines){
    if(!WPAdvisorTaskBelongsToCurrentAccount(task) || !task.contextFingerprint.length)return NO;
    NSString *current=WPAdvisorContextFingerprint(lines,task.lineCount);return current.length && [current isEqualToString:task.contextFingerprint];
}

static NSString *WPAdvisorString(id value,NSUInteger maximum){
    return [value isKindOfClass:NSString.class] && [value length] && [value length]<=maximum ? value : nil;
}
static NSDictionary *WPAdviceDictionary(WPChatAdvice *value) {
    return @{@"summary":value.summary?:@"",@"strategy":value.strategy?:@"",@"risk_label":value.riskLabel?:@"",
        @"risk_level":@(value.riskLevel),@"reply_timing":value.replyTiming?:@"",@"intents":value.intents?:@[],
        @"actions":value.actions?:@[],@"replies":value.replies?:@[]};
}

@interface WPAdvisorTaskCenter ()
@property(nonatomic,strong) NSMutableArray<WPAdvisorTask *> *tasks;
@property(nonatomic,strong) NSMutableDictionary<NSString *,WPAdvisorTask *> *current;
@property(nonatomic,strong) NSTimer *expiryTimer;
@property(nonatomic,copy) NSString *currentAccountFingerprint;
@end

@implementation WPAdvisorTaskCenter
+ (instancetype)sharedCenter {static WPAdvisorTaskCenter *center;static dispatch_once_t once;dispatch_once(&once,^{center=[self new];});return center;}
- (instancetype)init {
    if((self=[super init])){
        _tasks=[NSMutableArray new];_current=[NSMutableDictionary new];[self refreshAccount];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onAccountEvent:) name:@"WPChatPresentationDidChangeNotification" object:nil];
    }return self;
}
- (BOOL)refreshAccount {
    NSString *account=WPAdvisorCurrentAccountFingerprint();
    if((!account && !self.currentAccountFingerprint) || [account isEqualToString:self.currentAccountFingerprint])return NO;
    [self.expiryTimer invalidate];self.expiryTimer=nil;
    for(WPAdvisorTask *task in self.tasks){if(task.state==WPAdvisorTaskQueued || task.state==WPAdvisorTaskRunning){[task.request cancel];task.request=nil;task.pendingLines=nil;task.state=WPAdvisorTaskCancelled;}}
    [self.tasks removeAllObjects];[self.current removeAllObjects];self.currentAccountFingerprint=account;
    if(account.length)[self loadHistory];return YES;
}
- (void)onForeground:(NSNotification *)notification {
    BOOL switched=[self refreshAccount],removed=[self prune];
    // A foreign account's timer may have elapsed while iOS suspended the app.
    // Reconcile the shared file even if this account has no expired records.
    if(self.currentAccountFingerprint.length && (!switched || removed))[self save];
    if(switched || removed)[self changed];
}
- (void)onAccountEvent:(NSNotification *)notification {if([self refreshAccount])[self changed];}
- (NSString *)historyPath {return [WPDataDirectory() stringByAppendingPathComponent:@"advisor-history.json"];}
- (BOOL)prune {
    NSDate *cutoff=[NSDate dateWithTimeIntervalSinceNow:-WPAdvisorHistoryLifetime];BOOL modified=NO;
    for(WPAdvisorTask *task in self.tasks.copy){
        if(task.state==WPAdvisorTaskCompleted && [task.createdAt compare:cutoff]==NSOrderedAscending){[self.tasks removeObjectIdenticalTo:task];modified=YES;}
    }
    NSUInteger count=0;for(WPAdvisorTask *task in self.tasks.copy){
        if(task.state==WPAdvisorTaskCompleted && ++count>WPAdvisorMaxHistory){[self.tasks removeObjectIdenticalTo:task];modified=YES;}
    }return modified;
}
- (void)save {
    if(!self.currentAccountFingerprint.length)return;
    [self prune];NSMutableArray *records=[NSMutableArray new];
    NSData *oldData=[NSData dataWithContentsOfFile:self.historyPath];
    if(oldData.length>2*1024*1024)return;
    id old=oldData.length<=2*1024*1024 && oldData?[NSJSONSerialization JSONObjectWithData:oldData options:0 error:nil]:nil;
    if(oldData && ![old isKindOfClass:NSArray.class])return;
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;
    if([old isKindOfClass:NSArray.class])for(id item in old){
        if(![item isKindOfClass:NSDictionary.class])continue;
        NSString *account=WPAdvisorString(item[@"account"],64);id timestamp=item[@"created"];
        if(account.length!=64 || ![timestamp isKindOfClass:NSNumber.class])continue;
        NSTimeInterval time=[timestamp doubleValue];if(!isfinite(time) || time<=0 || time<now-WPAdvisorHistoryLifetime)continue;
        // Keep far-future entries on disk even if their date cannot safely be
        // rendered; a backwards clock adjustment must not delete other users.
        if([account isEqualToString:self.currentAccountFingerprint] && time<=4102444800)continue;
        [records addObject:item];
    }
    for(WPAdvisorTask *task in self.tasks){
        if(task.state!=WPAdvisorTaskCompleted || !task.advice)continue;
        [records addObject:@{@"id":task.identifier,@"account":self.currentAccountFingerprint,@"fingerprint":task.contextFingerprint?:@"",@"username":task.username,@"name":task.displayName,
            @"created":@(task.createdAt.timeIntervalSince1970),@"lineCount":@(task.lineCount),
            @"unread":@(task.unread),@"stale":@(task.stale),@"advice":WPAdviceDictionary(task.advice)}];
    }
    NSData *data=[NSJSONSerialization dataWithJSONObject:records options:0 error:nil];
    if(data){[data writeToFile:self.historyPath options:NSDataWritingAtomic|NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:nil];}
    [self scheduleExpiry];
}
- (void)scheduleExpiry {
    [self.expiryTimer invalidate];self.expiryTimer=nil;NSTimeInterval earliest=DBL_MAX;
    for(WPAdvisorTask *task in self.tasks)if(task.state==WPAdvisorTaskCompleted)
        earliest=MIN(earliest,[task.createdAt timeIntervalSinceNow]+WPAdvisorHistoryLifetime);
    NSData *stored=[NSData dataWithContentsOfFile:self.historyPath];
    id records=stored && stored.length<=2*1024*1024?[NSJSONSerialization JSONObjectWithData:stored options:0 error:nil]:nil;
    if([records isKindOfClass:NSArray.class])for(id item in records){
        if(![item isKindOfClass:NSDictionary.class] || ![item[@"created"] isKindOfClass:NSNumber.class])continue;
        NSTimeInterval created=[item[@"created"] doubleValue];if(!isfinite(created) || created<=0 || created>4102444800)continue;
        earliest=MIN(earliest,created+WPAdvisorHistoryLifetime-NSDate.date.timeIntervalSince1970);
    }
    if(earliest==DBL_MAX)return;
    __weak typeof(self) weakSelf=self;
    self.expiryTimer=[NSTimer scheduledTimerWithTimeInterval:MAX(.1,earliest) repeats:NO block:^(__unused NSTimer *timer){
        typeof(self) self=weakSelf;if(!self)return;
        BOOL removed=[self prune];[self save];if(removed)[self changed];
    }];
}
- (void)loadHistory {
    if(!self.currentAccountFingerprint.length)return;
    NSData *data=[NSData dataWithContentsOfFile:self.historyPath];if(data.length>2*1024*1024)return;
    id records=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
    if(![records isKindOfClass:NSArray.class])return;
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;
    for(id item in records){
        if(![item isKindOfClass:NSDictionary.class] || self.tasks.count>=WPAdvisorMaxHistory)continue;
        if(![item[@"account"] isKindOfClass:NSString.class] || ![item[@"account"] isEqualToString:self.currentAccountFingerprint])continue;
        NSString *identifier=WPAdvisorString(item[@"id"],128),*username=WPAdvisorString(item[@"username"],256),*name=WPAdvisorString(item[@"name"],128);
        id timestamp=item[@"created"],rawAdvice=item[@"advice"];
        if(!identifier || !username || ![timestamp isKindOfClass:NSNumber.class] || ![rawAdvice isKindOfClass:NSDictionary.class])continue;
        NSTimeInterval time=[timestamp doubleValue];if(!isfinite(time) || time<=0 || time>4102444800 || time<now-WPAdvisorHistoryLifetime)continue;
        NSData *json=[NSJSONSerialization dataWithJSONObject:rawAdvice options:0 error:nil];
        NSString *content=json?[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]:nil;
        WPChatAdvice *advice=content?[WPChatAdvice adviceFromModelContent:content error:nil]:nil;if(!advice)continue;
        WPAdvisorTask *task=[WPAdvisorTask new];task.identifier=identifier;task.username=username;task.displayName=name?:@"联系人";
        task.accountFingerprint=self.currentAccountFingerprint;
        NSString *fingerprint=WPAdvisorString(item[@"fingerprint"],64);task.contextFingerprint=fingerprint.length==64?fingerprint:nil;
        task.createdAt=[NSDate dateWithTimeIntervalSince1970:time];task.state=WPAdvisorTaskCompleted;task.advice=advice;
        id count=item[@"lineCount"],unread=item[@"unread"],stale=item[@"stale"];
        task.lineCount=[count isKindOfClass:NSNumber.class]?MIN(40,[count unsignedIntegerValue]):0;
        task.unread=[unread isKindOfClass:NSNumber.class] && [unread boolValue];task.stale=[stale isKindOfClass:NSNumber.class] && [stale boolValue];
        [self.tasks addObject:task];
    }
    [self save];
}
- (void)changed {[NSNotificationCenter.defaultCenter postNotificationName:WPAdvisorTasksDidChangeNotification object:self];}
- (NSArray<WPAdvisorTask *> *)activeTasks {
    [self refreshAccount];
    NSMutableArray *result=[NSMutableArray new];for(WPAdvisorTask *task in self.tasks)if(task.state==WPAdvisorTaskQueued || task.state==WPAdvisorTaskRunning)[result addObject:task];return result;
}
- (NSArray<WPAdvisorTask *> *)unreadResults {
    [self refreshAccount];
    if([self prune])[self save];NSMutableArray *result=[NSMutableArray new];NSMutableSet *seen=[NSMutableSet new];
    for(WPAdvisorTask *task in self.tasks)if(task.state==WPAdvisorTaskCompleted && task.unread && ![seen containsObject:task.username]){[result addObject:task];[seen addObject:task.username];}return result;
}
- (NSArray<WPAdvisorTask *> *)history {
    [self refreshAccount];
    if([self prune])[self save];NSMutableArray *result=[NSMutableArray new];for(WPAdvisorTask *task in self.tasks)if(task.state==WPAdvisorTaskCompleted)[result addObject:task];return result;
}
- (NSArray<WPAdvisorTask *> *)failedTasks {
    [self refreshAccount];
    NSMutableArray *result=[NSMutableArray new];for(WPAdvisorTask *task in self.tasks)if(task.state==WPAdvisorTaskFailed)[result addObject:task];return result;
}
- (WPAdvisorTask *)submitUsername:(NSString *)username displayName:(NSString *)displayName lines:(NSArray<WPChatLine *> *)lines group:(BOOL)group {
    NSAssert(NSThread.isMainThread,@"Advisor task center is main-thread only");
    [self refreshAccount];
    if(!self.currentAccountFingerprint.length || !WPAdvisorString(username,256) || ![lines isKindOfClass:NSArray.class] || !lines.count)return nil;
    NSMutableArray *snapshot=[NSMutableArray new];
    for(id item in lines.reverseObjectEnumerator){
        if(![item isKindOfClass:WPChatLine.class] || ![item text].length)continue;
        NSString *text=[item text];if(text.length>300)text=[text substringWithRange:[text rangeOfComposedCharacterSequencesForRange:NSMakeRange(0,300)]];
        [snapshot insertObject:[WPChatLine lineFromMe:[item fromMe] speaker:[item speaker]?:@"" text:text date:[item date]] atIndex:0];
        if(snapshot.count>=40)break;
    }
    if(!snapshot.count)return nil;
    WPAdvisorTask *old=self.current[username];
    NSUInteger queued=0;for(WPAdvisorTask *task in self.activeTasks)if(task.state==WPAdvisorTaskQueued && task!=old)queued++;
    if(queued>=WPAdvisorMaxWaiting)return nil;
    if(old)[self cancelTask:old];
    WPAdvisorTask *task=[WPAdvisorTask new];task.identifier=NSUUID.UUID.UUIDString;task.username=username;
    task.accountFingerprint=self.currentAccountFingerprint;task.contextFingerprint=WPAdvisorContextFingerprint(snapshot,snapshot.count);
    task.displayName=WPAdvisorString(displayName,128)?:@"联系人";task.createdAt=NSDate.date;task.pendingLines=snapshot;
    task.lineCount=snapshot.count;task.group=group;task.state=WPAdvisorTaskQueued;
    [self.tasks insertObject:task atIndex:0];self.current[username]=task;[self pump];[self changed];return task;
}
- (void)pump {
    NSUInteger running=0;for(WPAdvisorTask *task in self.tasks)if(task.state==WPAdvisorTaskRunning)running++;
    for(WPAdvisorTask *task in self.tasks.reverseObjectEnumerator){
        if(running>=WPAdvisorMaxConcurrent)break;if(task.state!=WPAdvisorTaskQueued)continue;
        task.state=WPAdvisorTaskRunning;running++;
        NSArray *lines=task.pendingLines;task.pendingLines=nil;
        __weak typeof(self) weakSelf=self;__weak WPAdvisorTask *weakTask=task;
        __block BOOL requestAssigned=NO;
        task.request=[WPChatAdvisor startAnalysisOfLines:lines group:task.group completion:^(WPChatAdvice *advice,NSString *error){
            dispatch_block_t finish=^{
                typeof(self) self=weakSelf;WPAdvisorTask *task=weakTask;if(!self || !task)return;
                if([self refreshAccount]){[self changed];return;}
                if(task.state!=WPAdvisorTaskRunning || self.current[task.username]!=task || !WPAdvisorTaskBelongsToCurrentAccount(task))return;
                task.request=nil;[self.current removeObjectForKey:task.username];
                if(advice){
                    for(WPAdvisorTask *previous in self.tasks)if(previous!=task && [previous.username isEqual:task.username])previous.unread=NO;
                    task.advice=advice;task.state=WPAdvisorTaskCompleted;task.unread=YES;[self save];
                }else{
                    task.state=WPAdvisorTaskFailed;task.error=error?:@"分析失败";
                    NSUInteger failed=0;for(WPAdvisorTask *item in self.tasks.copy)if(item.state==WPAdvisorTaskFailed && ++failed>20)[self.tasks removeObjectIdenticalTo:item];
                }
                [self pump];[self changed];
            };
            // Early validation can call back before startAnalysis returns the
            // token; defer that case until request assignment is complete.
            if(NSThread.isMainThread && requestAssigned)finish();else dispatch_async(dispatch_get_main_queue(),finish);
        }];
        requestAssigned=YES;
    }
}
- (void)cancelTask:(WPAdvisorTask *)task {
    NSAssert(NSThread.isMainThread,@"Advisor task center is main-thread only");
    [self refreshAccount];
    if(![self.tasks containsObject:task] || (task.state!=WPAdvisorTaskQueued && task.state!=WPAdvisorTaskRunning))return;
    [task.request cancel];task.request=nil;task.pendingLines=nil;task.state=WPAdvisorTaskCancelled;
    if(self.current[task.username]==task)[self.current removeObjectForKey:task.username];
    [self.tasks removeObjectIdenticalTo:task];[self pump];[self changed];
}
- (void)dismissFailedTask:(WPAdvisorTask *)task {
    [self refreshAccount];
    if(task.state==WPAdvisorTaskFailed && [self.tasks containsObject:task]){[self.tasks removeObjectIdenticalTo:task];[self changed];}
}
- (void)markResultRead:(WPAdvisorTask *)task {[self refreshAccount];if([self.tasks containsObject:task] && task.state==WPAdvisorTaskCompleted && task.unread){task.unread=NO;[self save];[self changed];}}
- (void)markStaleForUsername:(NSString *)username {
    [self refreshAccount];
    BOOL changed=NO;for(WPAdvisorTask *task in self.tasks)if([task.username isEqual:username] && !task.stale && (task.state==WPAdvisorTaskCompleted || task.state==WPAdvisorTaskRunning || task.state==WPAdvisorTaskQueued)){task.stale=YES;changed=YES;}
    if(changed){[self save];[self changed];}
}
- (void)clearHistory {
    [self refreshAccount];if(!self.currentAccountFingerprint.length)return;
    NSIndexSet *indexes=[self.tasks indexesOfObjectsPassingTest:^BOOL(WPAdvisorTask *task,NSUInteger index,BOOL *stop){return task.state==WPAdvisorTaskCompleted || task.state==WPAdvisorTaskFailed;}];
    [self.tasks removeObjectsAtIndexes:indexes];[self save];[self changed];
}
@end
