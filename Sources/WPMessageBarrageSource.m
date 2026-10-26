#import "WPMessageBarrageSource.h"
#import "WPChatPresentationState.h"
#import "WPMessageBarrage.h"
#import "WPBarragePreferences.h"
#import "WPCommon.h"
#import "WPQuickChat.h"
#import "WPComfortPreferences.h"
#import "WPSessionEligibility.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <math.h>

NSString * const WPMessageBarrageDidReceiveNotification = @"WeChatPet.MessageBarrageDidReceive";
NSString * const WPMessageBarrageSourceStatusDidChangeNotification = @"WeChatPet.BarrageSourceStatusDidChange";
static const NSUInteger WPBSInboxLimit=12, WPBSDedupLimit=96, WPBSTextLimit=80;
static const NSTimeInterval WPBSMaximumAge=15;
static const NSTimeInterval WPBSMetadataWait=6;

// Selector/field evidence: the local historical WeChatRobotForExample headers
// and Tweak.xm declare CMessageWrap fields and void AsyncOnAddMsg:MsgWrap:.
// Installed builds still have every runtime ABI checked before access.
static const char *WPBSType(const char *type) {while(type && *type && strchr("rnNoORV",*type))type++;return type ?: "";}
static BOOL WPBSObjectType(const char *type) {type=WPBSType(type);return type[0]=='@' && type[1]!='?';}
static NSMethodSignature *WPBSSignature(id object,NSString *selector,NSUInteger count) {
    if(!object)return nil;
    @try {NSMethodSignature *s=[object methodSignatureForSelector:NSSelectorFromString(selector)];return s.numberOfArguments==count+2?s:nil;}
    @catch(__unused NSException *exception) {return nil;}
}
static id WPBSObject(id object,NSString *selector,id argument,BOOL hasArgument) {
    NSMethodSignature *s=WPBSSignature(object,selector,hasArgument?1:0);
    if(!s || !WPBSObjectType(s.methodReturnType) || (hasArgument && !WPBSObjectType([s getArgumentTypeAtIndex:2])))return nil;
    @try {
        NSInvocation *call=[NSInvocation invocationWithMethodSignature:s];call.target=object;call.selector=NSSelectorFromString(selector);
        if(hasArgument){__unsafe_unretained id value=argument;[call setArgument:&value atIndex:2];}
        [call invoke];__unsafe_unretained id value=nil;[call getReturnValue:&value];return value;
    } @catch(__unused NSException *exception) {return nil;}
}
static NSNumber *WPBSInteger(id object,NSString *selector) {return WPSEReadNumber(object,@[selector]);}
static NSString *WPBSIdentifierValue(id object,NSString *key) {
    id value=WPSEReadObject(object,@[key]);
    // Never copy an oversized or non-string identifier into a queued object.
    return [value isKindOfClass:NSString.class] && [value length]>0 && [value length]<=256?[value copy]:nil;
}
static NSString *WPBSText(NSString *value,NSUInteger start) {
    if(![value isKindOfClass:NSString.class] || start>=value.length)return @"";
    NSMutableString *text=[NSMutableString new];__block NSUInteger count=0;__block BOOL truncated=NO;
    // Stop enumeration at the character limit; never construct an unbounded
    // components array or clone a long original body just to trim it later.
    [value enumerateSubstringsInRange:NSMakeRange(start,MIN((NSUInteger)2048,value.length-start)) options:NSStringEnumerationByComposedCharacterSequences|NSStringEnumerationSubstringNotRequired usingBlock:^(NSString *ignored,NSRange range,NSRange enclosing,BOOL *stop){
        // Reaching the 81st whole character proves text was omitted. Keep the
        // first 80 intact, including emoji, and make the shortening visible.
        if(count>=WPBSTextLimit || range.length>512){truncated=YES;*stop=YES;return;}
        NSString *part=[value substringWithRange:range];
        if([part rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location!=NSNotFound || [part isEqual:@"\t"])part=@" ";
        [text appendString:part];count++;
    }];
    if(start+MIN((NSUInteger)2048,value.length-start)<value.length)truncated=YES;
    NSString *result=[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return truncated?[result stringByAppendingString:@"…"]:result;
}
static BOOL WPBSHookABI(Method method) {
    if(!method || method_getNumberOfArguments(method)!=4)return NO;
    char *result=method_copyReturnType(method),*first=method_copyArgumentType(method,2),*second=method_copyArgumentType(method,3);
    BOOL valid=!strcmp(WPBSType(result),"v") && WPBSObjectType(first) && WPBSObjectType(second);
    free(result);free(first);free(second);return valid;
}

static BOOL WPBSHookNotifyABI(Method method) {
    if(!method || method_getNumberOfArguments(method)!=5)return NO;
    char *result=method_copyReturnType(method),*first=method_copyArgumentType(method,2),*second=method_copyArgumentType(method,3),*notify=method_copyArgumentType(method,4);
    BOOL valid=!strcmp(WPBSType(result),"v") && WPBSObjectType(first) && WPBSObjectType(second) && !strcmp(WPBSType(notify),"B");
    free(result);free(first);free(second);free(notify);return valid;
}
static BOOL WPBSIndexABI(id manager) {
    NSMethodSignature *signature=WPBSSignature(manager,@"GetSessionAtIndex:",1);
    const char *argument=signature?WPBSType([signature getArgumentTypeAtIndex:2]):"";
    return signature && WPBSObjectType(signature.methodReturnType) && argument[0] && !argument[1] && strchr("iIlLqQ",argument[0]);
}
static id WPBSIndexedSession(id manager,NSUInteger index) {
    NSMethodSignature *signature=WPBSSignature(manager,@"GetSessionAtIndex:",1);if(!signature || !WPBSIndexABI(manager))return nil;
    @try {
        NSInvocation *call=[NSInvocation invocationWithMethodSignature:signature];call.target=manager;call.selector=NSSelectorFromString(@"GetSessionAtIndex:");
        switch(WPBSType([signature getArgumentTypeAtIndex:2])[0]){
#define WPBS_INDEX(c,t) case c:{t value=(t)index;[call setArgument:&value atIndex:2];break;}
            WPBS_INDEX('i',int) WPBS_INDEX('I',unsigned int) WPBS_INDEX('l',long) WPBS_INDEX('L',unsigned long) WPBS_INDEX('q',long long) WPBS_INDEX('Q',unsigned long long)
#undef WPBS_INDEX
            default:return nil;
        }
        [call invoke];__unsafe_unretained id result=nil;[call getReturnValue:&result];return result;
    } @catch(__unused NSException *exception){return nil;}
}
static NSString *WPBSSessionUsername(id session) {
    id value=WPSEReadObject(session,@[@"m_nsUserName",@"m_nsUsrName",@"userName",@"username"]);
    return [value isKindOfClass:NSString.class] && [value length]<=256?value:nil;
}

@interface WPMessageBarrageSource ()
@property(nonatomic,strong) NSLock *stateLock;
@property(nonatomic,strong) NSMutableArray<WPBarrageMessage *> *inbox;
@property(nonatomic,strong) NSMutableOrderedSet<NSString *> *seen;
@property(nonatomic) BOOL active;
@property(nonatomic) BOOL foreground;
@property(nonatomic) BOOL wantsActive;
@property(nonatomic) BOOL healthRefreshPending;
@property(nonatomic) BOOL healthStarting;
@property(nonatomic) BOOL scheduled;
@property(atomic) BOOL hooked;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) NSTimeInterval activeSince;
@property(nonatomic) NSUInteger acceptedCount;
@property(nonatomic) NSUInteger droppedCount;
@property(nonatomic) NSUInteger mutedUnknownCount;
@property(atomic,copy) NSString *hookState;
@property(nonatomic) NSTimer *healthTimer;
@property(nonatomic) NSUInteger nativeCallbacks;
@property(nonatomic) NSTimeInterval lastNativeCallbackAt;
@property(nonatomic) NSTimeInterval lastNativeReceiveAt;
@property(nonatomic) NSMutableDictionary<NSString*,NSNumber*> *rejections;
@property(nonatomic) NSMutableDictionary<NSString*,NSNumber*> *eligibilityRetries;
@property(nonatomic) BOOL eligibilityTransient;
@property(nonatomic) BOOL publishedPolling;
@property(nonatomic,strong) NSMutableDictionary<NSString *,NSNumber *> *seenReceivedAt;
@property(nonatomic,strong) NSMutableDictionary<NSString *,NSNumber *> *fallbackPending;
@property(nonatomic) BOOL fallbackScheduled;
@property(nonatomic,weak) id sessionLookupManager;
@property(nonatomic,strong) NSMapTable<NSString *,id> *sessionLookupFound;
@property(nonatomic,strong) NSMutableDictionary<NSString *,NSNumber *> *sessionLookupRanks;
@property(nonatomic,strong) NSMutableSet<NSString *> *sessionLookupWanted;
@property(nonatomic,strong) NSArray *sessionLookupList;
@property(nonatomic) NSUInteger sessionLookupGeneration,sessionLookupIndex,sessionLookupCount,sessionLookupMaxBatch;
@property(nonatomic) BOOL sessionLookupScheduled,sessionLookupIndexRoute;
@property(nonatomic) NSTimeInterval sessionLookupAt;
- (void)publishHealth;
- (void)noteNativeWrap:(id)wrap;
- (void)reject:(NSString*)reason;
- (NSSet*)homeNamesForConversations;
- (void)captureIncomingWrap:(id)wrap;
- (void)drainGeneration:(NSUInteger)generation;
- (BOOL)allowsConversation:(NSString *)username;
- (WPBarrageConversationEligibility)eligibilityForConversation:(NSString *)username;
- (id)nativeSessionForConversation:(NSString *)username;
- (id)nativeSessionManager;
- (void)resetSessionLookup;
- (void)stepSessionLookup:(NSUInteger)generation;
- (void)drainFallbackGeneration:(NSUInteger)generation;
- (void)scheduleFallbackAfter:(NSTimeInterval)delay;
@end

WPBarrageConversationEligibility WPMessageBarrageConversationEligibility(NSString *username) {
    return NSThread.isMainThread?[[WPMessageBarrageSource sharedSource] eligibilityForConversation:username]:WPBarrageConversationEligibilityUnknown;
}
BOOL WPMessageBarrageConversationAllowed(NSString *username){return WPMessageBarrageConversationEligibility(username)==WPBarrageConversationEligibilityAllowed;}
static NSLock *WPBSHookLock;static NSMutableDictionary<NSString*,NSValue*> *WPBSOriginals;
static void WPBSAddMessage(id object,SEL selector,id username,id wrap) {
    [WPBSHookLock lock];IMP original=[WPBSOriginals[NSStringFromSelector(selector)] pointerValue];[WPBSHookLock unlock];
    // Each adapter calls its predecessor once. Nested native routes are deduped
    // by stable message ID, including when other injected hooks sit in the chain.
    if(original)((void(*)(id,SEL,id,id))original)(object,selector,username,wrap);
    @try {WPMessageBarrageSource *source=[WPMessageBarrageSource sharedSource];[source noteNativeWrap:wrap];[source captureIncomingWrap:wrap];}
    @catch(__unused NSException *exception) {}
}

static void WPBSAddMessageNotify(id object,SEL selector,id username,id wrap,BOOL notify) {
    [WPBSHookLock lock];IMP original=[WPBSOriginals[NSStringFromSelector(selector)] pointerValue];[WPBSHookLock unlock];
    // Observed WeChat 8.0.79 ABI: v36@0:8@16@24B32. Forward the real flag
    // unchanged, including NO, and never route through a two-object function.
    if(original)((void(*)(id,SEL,id,id,BOOL))original)(object,selector,username,wrap,notify);
    @try {WPMessageBarrageSource *source=[WPMessageBarrageSource sharedSource];[source noteNativeWrap:wrap];[source captureIncomingWrap:wrap];}
    @catch(__unused NSException *exception) {}
}

@implementation WPMessageBarrageSource
+ (instancetype)sharedSource {static WPMessageBarrageSource *source;static dispatch_once_t once;dispatch_once(&once,^{source=[self new];});return source;}
- (instancetype)init {
    if(!(self=[super init]))return nil;
    _stateLock=[NSLock new];_rejections=[NSMutableDictionary new];_eligibilityRetries=[NSMutableDictionary new];_publishedPolling=YES;_inbox=[NSMutableArray new];_seen=[NSMutableOrderedSet new];_hookState=@"not-attempted";
    _seenReceivedAt=[NSMutableDictionary new];_fallbackPending=[NSMutableDictionary new];_sessionLookupFound=[NSMapTable strongToWeakObjectsMapTable];_sessionLookupRanks=[NSMutableDictionary new];_sessionLookupWanted=[NSMutableSet new];
    NSNotificationCenter *center=NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(becameInactive:) name:UIApplicationWillResignActiveNotification object:nil];
    [center addObserver:self selector:@selector(becameInactive:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [center addObserver:self selector:@selector(becameActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [center addObserver:self selector:@selector(settingsChanged:) name:WPSettingsDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(quickChatChanged:) name:WPQuickChatDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(memoryWarning:) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    return self;
}
- (void)dealloc {[self.healthTimer invalidate];[NSNotificationCenter.defaultCenter removeObserver:self];}
- (BOOL)enabledNow {return WPBarrageEnabled() && !WPBarrageIsPaused() && [WPPreferences() boolForKey:@"enabled"];}
- (BOOL)requiresSessionPolling {
    // One working callback proves only that route worked for one message.
    // Keep the monitor's already-observed fresh-arrival safety path available;
    // stable IDs deduplicate it with receive hooks without scanning history.
    return YES;
}
- (void)publishHealth {
    if(!NSThread.isMainThread){
        [self.stateLock lock];if(_healthRefreshPending){[self.stateLock unlock];return;}_healthRefreshPending=YES;[self.stateLock unlock];
        dispatch_async(dispatch_get_main_queue(),^{[self.stateLock lock];self.healthRefreshPending=NO;[self.stateLock unlock];[self publishHealth];});return;
    }
    BOOL polling=self.requiresSessionPolling;[self.stateLock lock];BOOL changed=_publishedPolling!=polling;_publishedPolling=polling;[self.stateLock unlock];
    if(changed)[NSNotificationCenter.defaultCenter postNotificationName:WPMessageBarrageSourceStatusDidChangeNotification object:self];
}
- (void)reject:(NSString*)reason {[self.stateLock lock];_rejections[reason]=@([_rejections[reason] unsignedIntegerValue]+1);[self.stateLock unlock];}
- (void)noteNativeWrap:(id)wrap {
    [self.stateLock lock];_nativeCallbacks++;_lastNativeCallbackAt=NSDate.date.timeIntervalSince1970;BOOL active=_active&&_foreground;[self.stateLock unlock];
    if(!active||![self enabledNow])return;
    NSNumber*status=WPBSInteger(wrap,@"m_uiStatus"),*created=WPBSInteger(wrap,@"m_uiCreateTime");NSTimeInterval now=NSDate.date.timeIntervalSince1970;
    BOOL incoming=status.unsignedIntegerValue==3 && created.doubleValue>0 && now-created.doubleValue<=15 && created.doubleValue<=now+2;
    if(incoming){[self.stateLock lock];_lastNativeReceiveAt=now;[self.stateLock unlock];[self publishHealth];}
}
- (void)installHook {
    NSAssert(NSThread.isMainThread,@"Install the receive adapter on main");
    if(self.hooked)return;
    static dispatch_once_t once;dispatch_once(&once,^{WPBSHookLock=[NSLock new];WPBSOriginals=[NSMutableDictionary new];});
    Class cls=NSClassFromString(@"CMessageMgr");NSUInteger installed=0;
    // These selectors occur in the supplied WCRefine binary's native adapter.
    // Installed two-object / void routes and the observed two-object / BOOL
    // route are changed only when every runtime argument matches. Unsupported
    // variants keep the session-arrival fallback active.
    for(NSString *name in @[@"AsyncOnAddMsg:MsgWrap:",@"AsyncOnAddMsgForSession:MsgWrap:",@"OnAddMsg:MsgWrap:",@"AddMsg:MsgWrap:",@"AsyncOnAddMsgForSession:MsgWrap:NewMsgArriveNotify:"]){
        SEL selector=NSSelectorFromString(name);Method method=cls?class_getInstanceMethod(cls,selector):NULL;
        BOOL notify=[name isEqual:@"AsyncOnAddMsgForSession:MsgWrap:NewMsgArriveNotify:"];
        if(!(notify?WPBSHookNotifyABI(method):WPBSHookABI(method)))continue;
        IMP hook=notify?(IMP)WPBSAddMessageNotify:(IMP)WPBSAddMessage;
        IMP implementation=method_getImplementation(method);if(implementation!=hook){[WPBSHookLock lock];WPBSOriginals[name]=[NSValue valueWithPointer:implementation];[WPBSHookLock unlock];if(!class_addMethod(cls,selector,hook,method_getTypeEncoding(method)))class_replaceMethod(cls,selector,hook,method_getTypeEncoding(method));}installed++;
    }
    self.hooked=installed>0;self.hookState=installed?[NSString stringWithFormat:@"installed-%lu",(unsigned long)installed]:@"unavailable";[self publishHealth];
}
- (void)setActive:(BOOL)active {
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{[self setActive:active];});return;}
    self.wantsActive=active;
    active=active && [self enabledNow] && UIApplication.sharedApplication.applicationState!=UIApplicationStateBackground;
    [self.stateLock lock];
    BOOL changed=_active!=active;
    _foreground=active && UIApplication.sharedApplication.applicationState==UIApplicationStateActive;
    _active=active;
    if(changed){if(active)_lastNativeReceiveAt=0;_generation++;_scheduled=NO;_fallbackScheduled=NO;[_inbox removeAllObjects];[_seen removeAllObjects];[_seenReceivedAt removeAllObjects];[_eligibilityRetries removeAllObjects];[_fallbackPending removeAllObjects];_activeSince=active?NSDate.date.timeIntervalSince1970:0;}
    [self.stateLock unlock];
    if(changed)[self resetSessionLookup];
    if(changed||!active){[self.healthTimer invalidate];self.healthTimer=nil;}
    if(active && !self.healthTimer && !self.healthStarting){
        self.healthStarting=YES;
        @try{[self installHook];if(self.active){__weak typeof(self) weakSelf=self;self.healthTimer=[NSTimer scheduledTimerWithTimeInterval:30 repeats:YES block:^(__unused NSTimer *timer){[weakSelf publishHealth];}];self.healthTimer.tolerance=5;}}
        @finally{self.healthStarting=NO;}
    }
}
- (void)setForegroundAvailable:(BOOL)available {
    if(!NSThread.isMainThread)return;
    WPSESetForegroundAvailable(available);
    [self.stateLock lock];BOOL changed=_foreground!=available;_foreground=available;
    BOOL schedule=available && _active && _inbox.count && !_scheduled;
    NSUInteger generation=_generation;if(schedule)_scheduled=YES;
    [self.stateLock unlock];
    if(schedule)dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[self drainGeneration:generation];});
    if(changed && available)[self scheduleFallbackAfter:.1];
    if(changed && available)[self publishHealth];
}
- (void)becameActive:(NSNotification *)notification {WPSESetForegroundAvailable(YES);[self setForegroundAvailable:YES];}
- (void)becameInactive:(NSNotification *)notification {
    [self setForegroundAvailable:NO];
    if([notification.name isEqual:UIApplicationDidEnterBackgroundNotification]){
        [self setActive:NO];WPSESetForegroundAvailable(NO);WPSEInvalidateHomeNames();
    }
}
- (void)settingsChanged:(NSNotification *)notification {
    if(![self enabledNow]){[self setActive:NO];return;}
    if(!WPBarrageShowsDetails()){
        // A worker may already have read the previous preference and body.
        // Invalidate that generation even if the switch is immediately turned
        // back on; only later arrivals may reveal text again.
        [self.stateLock lock];_generation++;_scheduled=NO;
        for(WPBarrageMessage *message in _inbox)message.text=@"";
        [_inbox removeAllObjects];[_eligibilityRetries removeAllObjects];[_fallbackPending removeAllObjects];_fallbackScheduled=NO;[self.stateLock unlock];
    }
}
- (void)memoryWarning:(NSNotification *)notification {
    [self.stateLock lock];_generation++;_scheduled=NO;_fallbackScheduled=NO;[_inbox removeAllObjects];[_seen removeAllObjects];[_seenReceivedAt removeAllObjects];[_eligibilityRetries removeAllObjects];[_fallbackPending removeAllObjects];[self.stateLock unlock];[self resetSessionLookup];
}
- (WPBarrageMessage *)messageFromWrap:(id)wrap activeSince:(NSTimeInterval)activeSince {
    NSNumber *status=WPBSInteger(wrap,@"m_uiStatus"),*type=WPBSInteger(wrap,@"m_uiMessageType"),*date=WPBSInteger(wrap,@"m_uiCreateTime");
    // 3 is the documented receive state. Sent (1/2/5), system (4), unknown,
    // history and backfilled wrappers are deliberately rejected.
    NSTimeInterval now=NSDate.date.timeIntervalSince1970,created=date.doubleValue;
    if(!status||!type||!date){[self reject:@"wrap-metadata-unavailable"];return nil;}if(status.unsignedLongLongValue!=3){[self reject:@"not-received"];return nil;}if(!isfinite(created)||created<=0||created<activeSince-1||created>now+2||now-created>WPBSMaximumAge){[self reject:@"stale-or-future"];return nil;}
    NSUInteger kind=type.unsignedIntegerValue;
    if(kind!=1 && kind!=3 && kind!=34 && kind!=43 && kind!=47 && kind!=48 && kind!=49 && kind!=62){[self reject:@"unsupported-message-type"];return nil;}
    NSString *conversation=WPBSIdentifierValue(wrap,@"m_nsFromUsr");
    if(!WPQuickChatIsOpenableUsername(conversation) || !WPBarrageReminderAllowsUsername(conversation,NSDate.date)){[self reject:@"rule-or-identifier"];return nil;}
    NSString *sender=[conversation hasSuffix:@"@chatroom"]?WPBSIdentifierValue(wrap,@"m_nsRealChatUsr"):conversation;
    NSNumber *serverID=WPBSInteger(wrap,@"m_n64MesSvrID"),*localID=WPBSInteger(wrap,@"m_uiMesLocalID");
    // Stable IDs are required so callbacks and session fallback cannot replay a
    // message. Nothing hashes or stores a body to invent an identity.
    if(!serverID.unsignedLongLongValue && !localID.unsignedLongLongValue){[self reject:@"missing-message-id"];return nil;}
    NSString *identifier=serverID.unsignedLongLongValue?[NSString stringWithFormat:@"%@:s%llu",conversation,serverID.unsignedLongLongValue]:[NSString stringWithFormat:@"%@:l%llu:t%.0f",conversation,localID.unsignedLongLongValue,created];
    NSString *text=@"";
    if(WPBarrageShowsDetails()) {
        if(kind==1){
            id body=WPSEReadObject(wrap,@[@"m_nsContent"]);
            if(![body isKindOfClass:NSString.class]){[self reject:@"body-unavailable"];return nil;}
            NSString *content=body;NSUInteger start=0;
            if([conversation hasSuffix:@"@chatroom"]){
                // Raw group bodies may begin memberID + ":\n". Inspect only a
                // bounded prefix and never show that sender ID as message text.
                NSRange separator=[content rangeOfString:@":\n" options:0 range:NSMakeRange(0,MIN((NSUInteger)258,content.length))];
                if(separator.location!=NSNotFound && separator.location>0 && separator.location<=256){
                    NSString *prefix=[content substringToIndex:separator.location];
                    if(!sender.length || [prefix isEqual:sender]) {
                        sender=sender ?: prefix;
                        start=NSMaxRange(separator);
                    }
                }
            }
            text=WPBSText(content,start);if(!text.length){[self reject:@"empty-text"];return nil;}
        } else {
            switch(kind){case 3:text=@"[图片]";break;case 34:text=@"[语音]";break;case 43:case 62:text=@"[视频]";break;case 47:text=@"[表情]";break;case 48:text=@"[位置]";break;case 49:text=@"[文件/分享]";break;default:break;}
        }
    }
    WPBarrageMessage *message=[WPBarrageMessage new];message.conversationUsername=conversation;message.senderUsername=sender ?: conversation;
    message.text=text;message.identifier=identifier;message.createdAt=[NSDate dateWithTimeIntervalSince1970:created];return message;
}
- (void)captureIncomingWrap:(id)wrap {
    WPQuickChatNotifyNativeMessage();
    [self.stateLock lock];BOOL gated=_active && _foreground;NSUInteger generation=_generation;NSTimeInterval since=_activeSince;[self.stateLock unlock];
    // The gate is checked before accessing any wrapper property, even its type.
    if(!gated || ![self enabledNow])return;
    WPBarrageMessage *message=nil;
    @try {message=[self messageFromWrap:wrap activeSince:since];} @catch(__unused NSException *exception) {[self reject:@"wrapper-exception"];return;}
    if(!message)return;
    BOOL schedule=NO;
    [self.stateLock lock];
    if(_active && _foreground && generation==_generation && ![_seen containsObject:message.identifier]){
        if(!WPBarrageShowsDetails())message.text=@"";
        [_seen addObject:message.identifier];_seenReceivedAt[message.identifier]=@(NSDate.date.timeIntervalSince1970);if(_seen.count>WPBSDedupLimit){NSString *expired=_seen.firstObject;[_seen removeObjectAtIndex:0];[_seenReceivedAt removeObjectForKey:expired];}
        if(_inbox.count>=WPBSInboxLimit){[_inbox removeObjectAtIndex:0];_droppedCount++;}
        [_inbox addObject:message];
        if(!_scheduled){_scheduled=YES;schedule=YES;}
    }
    [self.stateLock unlock];
    // One outstanding main-queue drain captures no wrapper or message body.
    if(schedule)dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[self drainGeneration:generation];});
}
- (BOOL)isCurrentConversation:(NSString *)username {return WPChatConversationIsVisible(username);}
- (NSSet*)homeNamesForConversations {return WPSEHomeNames(WPWeChatService(@"MMNewSessionMgr"));}
- (BOOL)allowsConversation:(NSString *)username {
    NSAssert(NSThread.isMainThread,@"Read WeChat session services on main");self.eligibilityTransient=NO;
    if(!WPQuickChatIsOpenableUsername(username)||!WPBarrageReminderAllowsUsername(username,NSDate.date)){[self reject:@"rule"];return NO;}
    if([self isCurrentConversation:username]){[self reject:@"current-conversation"];return NO;}
    id contacts=WPWeChatService(@"CContactMgr"),selfContact=WPBSObject(contacts,@"getSelfContact",nil,NO);
    if([WPBSIdentifierValue(selfContact,@"m_nsUsrName") isEqual:username]){[self reject:@"self"];return NO;}
    id session=[self nativeSessionForConversation:username];if(!session){self.eligibilityTransient=YES;[self reject:@"session-pending"];return NO;}
    if(WPSESessionHiddenOrFolded(session)){[self reject:@"hidden-folded"];return NO;}
    NSNumber *muted=WPSESessionMuted(session,username);
    if(muted.boolValue){[self reject:@"muted"];return NO;}
    NSSet *home=[self homeNamesForConversations];if(!home||![home containsObject:username]){self.eligibilityTransient=YES;[self reject:home?@"off-home":@"home-unavailable"];return NO;}
    if(!muted){self.eligibilityTransient=YES;[self.stateLock lock];_mutedUnknownCount++;[self.stateLock unlock];[self reject:@"mute-unavailable"];return NO;}return YES;
}
- (WPBarrageConversationEligibility)eligibilityForConversation:(NSString *)username {
    // Exceptions and native cache reconstruction are unavailable metadata,
    // never evidence that the user changed a privacy rule. Explicit rules,
    // current chat, hidden/folded and mute flags are still immediate denials.
    self.eligibilityTransient=NO;
    @try {
        if([self allowsConversation:username])return WPBarrageConversationEligibilityAllowed;
        return self.eligibilityTransient?WPBarrageConversationEligibilityUnknown:WPBarrageConversationEligibilityDenied;
    } @catch(__unused NSException *exception) {
        self.eligibilityTransient=YES;[self reject:@"eligibility-unavailable"];
        return WPBarrageConversationEligibilityUnknown;
    }
}
- (id)nativeSessionManager {return WPWeChatService(@"MMNewSessionMgr");}
- (void)resetSessionLookup {
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{[self resetSessionLookup];});return;}
    self.sessionLookupGeneration++;self.sessionLookupScheduled=NO;self.sessionLookupManager=nil;
    self.sessionLookupList=nil;self.sessionLookupIndex=self.sessionLookupCount=0;self.sessionLookupAt=0;
    [self.sessionLookupFound removeAllObjects];[self.sessionLookupRanks removeAllObjects];[self.sessionLookupWanted removeAllObjects];
}
- (void)scheduleSessionLookup {
    if(self.sessionLookupScheduled || !self.sessionLookupWanted.count || self.sessionLookupIndex>=self.sessionLookupCount)return;
    self.sessionLookupScheduled=YES;NSUInteger generation=self.sessionLookupGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,8*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        if(generation!=self.sessionLookupGeneration)return;self.sessionLookupScheduled=NO;[self stepSessionLookup:generation];
    });
}
- (void)stepSessionLookup:(NSUInteger)generation {
    [self.stateLock lock];BOOL foreground=_foreground;[self.stateLock unlock];
    if(generation!=self.sessionLookupGeneration || !foreground || !self.sessionLookupManager || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive)return;
    NSUInteger end=MIN(self.sessionLookupCount,self.sessionLookupIndex+150),visited=0;NSTimeInterval began=CACurrentMediaTime();
    while(self.sessionLookupIndex<end && self.sessionLookupWanted.count){@autoreleasepool{
        NSUInteger index=self.sessionLookupIndex++;id session=self.sessionLookupIndexRoute?WPBSIndexedSession(self.sessionLookupManager,index):self.sessionLookupList[index];visited++;
        NSString *name=WPBSSessionUsername(session);
        if(name.length && [self.sessionLookupWanted containsObject:name]){
            if(self.sessionLookupRanks.count>=24){NSString *oldest=self.sessionLookupRanks.allKeys.firstObject;[self.sessionLookupFound removeObjectForKey:oldest];[self.sessionLookupRanks removeObjectForKey:oldest];}
            [self.sessionLookupFound setObject:session forKey:name];[self.sessionLookupWanted removeObject:name];
            self.sessionLookupRanks[name]=@(index);
        }
        if(CACurrentMediaTime()-began>.003)break;
    }}
    [self.stateLock lock];_sessionLookupMaxBatch=MAX(_sessionLookupMaxBatch,visited);[self.stateLock unlock];
    if(self.sessionLookupIndex>=self.sessionLookupCount || !self.sessionLookupWanted.count){self.sessionLookupList=nil;self.sessionLookupAt=CACurrentMediaTime();return;}
    [self scheduleSessionLookup];
}
- (id)nativeSessionForConversation:(NSString *)username {
    NSAssert(NSThread.isMainThread,@"Native session lookups run on main");
    id manager=[self nativeSessionManager];id direct=WPBSObject(manager,@"GetSessionByUserName:",username,YES);
    if(direct){NSString *actual=WPBSSessionUsername(direct);if(!actual.length || [actual isEqual:username])return direct;}
    if(!manager || !username.length)return nil;
    if(self.sessionLookupManager!=manager){[self resetSessionLookup];self.sessionLookupManager=manager;}
    NSNumber *rank=self.sessionLookupRanks[username];
    if(rank){
        // Re-read the current native object at the observed rank; retaining a
        // formerly unmuted snapshot could miss an immediate privacy change.
        id cached=nil;
        if(self.sessionLookupIndexRoute)cached=WPBSIndexedSession(manager,rank.unsignedIntegerValue);
        else {id list=WPBSObject(manager,@"GetSessionInfoList",nil,NO);if([list isKindOfClass:NSArray.class] && rank.unsignedIntegerValue<[list count])cached=list[rank.unsignedIntegerValue];}
        if([WPBSSessionUsername(cached) isEqual:username])return cached;
        [self.sessionLookupRanks removeObjectForKey:username];[self.sessionLookupFound removeObjectForKey:username];
    }
    // These are the same typed index/list routes already supported by quick
    // chat. A build without GetSessionByUserName must not reject all barrages.
    if([self.sessionLookupWanted containsObject:username]){
        if(self.sessionLookupIndex<self.sessionLookupCount){[self scheduleSessionLookup];return nil;}
        if(self.sessionLookupScheduled)return nil;
        [self.sessionLookupWanted removeObject:username];
    }
    if(self.sessionLookupWanted.count>=WPBSInboxLimit)return nil;
    [self.sessionLookupWanted addObject:username];
    NSNumber *count=WPBSIndexABI(manager)?WPBSInteger(manager,@"GetSessionCount"):nil;
    if(count && count.longLongValue>=0){self.sessionLookupIndexRoute=YES;self.sessionLookupCount=MIN(count.unsignedIntegerValue,(NSUInteger)10000);self.sessionLookupList=nil;}
    else {
        id list=WPBSObject(manager,@"GetSessionInfoList",nil,NO);
        if(![list isKindOfClass:NSArray.class]){[self.sessionLookupWanted removeObject:username];return nil;}
        self.sessionLookupIndexRoute=NO;self.sessionLookupCount=MIN([list count],(NSUInteger)10000);self.sessionLookupList=list;
    }
    // A newly arrived conversation can move to the first row during a scan.
    // Restart only when a new target joins; duplicate retries share one scan.
    self.sessionLookupIndex=0;self.sessionLookupAt=CACurrentMediaTime();[self stepSessionLookup:self.sessionLookupGeneration];
    return [self.sessionLookupFound objectForKey:username];
}
- (void)drainGeneration:(NSUInteger)generation {
    NSAssert(NSThread.isMainThread,@"Deliver message capsules on main");
    [self.stateLock lock];
    if(generation!=_generation){[self.stateLock unlock];return;}
    if(!_foreground){_scheduled=NO;[self.stateLock unlock];return;}
    NSArray<WPBarrageMessage *> *batch=[_inbox copy];[_inbox removeAllObjects];_scheduled=NO;
    BOOL active=_active && _foreground;[self.stateLock unlock];
    if(!active || ![self enabledNow] || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive)return;
    for(WPBarrageMessage *message in batch){
        [self.stateLock lock];BOOL current=_active && _foreground && generation==_generation;[self.stateLock unlock];
        if(!current || ![self enabledNow])break;
        if(-message.createdAt.timeIntervalSinceNow>WPBSMaximumAge){[self reject:@"expired-before-delivery"];continue;}
        self.eligibilityTransient=NO;
        if([self eligibilityForConversation:message.conversationUsername]!=WPBarrageConversationEligibilityAllowed){
            // The receive hook often runs before WeChat updates its home row.
            // Wait for native metadata to settle, with a strict finite retry;
            // folded, hidden, muted and reminder-policy decisions never retry.
            if(self.eligibilityTransient){
                BOOL schedule=NO;
                [self.stateLock lock];
                NSUInteger attempts=[_eligibilityRetries[message.identifier] unsignedIntegerValue];
                NSTimeInterval receivedAt=[_seenReceivedAt[message.identifier] doubleValue];
                if(attempts<16 && NSDate.date.timeIntervalSince1970-receivedAt<WPBSMetadataWait && _active && generation==_generation && _inbox.count<WPBSInboxLimit){
                    if(_eligibilityRetries.count>=12 && !_eligibilityRetries[message.identifier])[_eligibilityRetries removeObjectForKey:_eligibilityRetries.allKeys.firstObject];
                    _eligibilityRetries[message.identifier]=@(attempts+1);
                    [_inbox addObject:message];
                    if(!_scheduled){_scheduled=YES;schedule=YES;}
                }else{
                    // An older metadata retry must not displace a fresh arrival.
                    [_eligibilityRetries removeObjectForKey:message.identifier];
                }
                [self.stateLock unlock];
                if(schedule)dispatch_after(dispatch_time(DISPATCH_TIME_NOW,350*NSEC_PER_MSEC),dispatch_get_main_queue(),^{WPSEInvalidateHomeNames();[self drainGeneration:generation];});
            }
            continue;
        }
        [self.stateLock lock];[_eligibilityRetries removeObjectForKey:message.identifier];[self.stateLock unlock];
        if(!WPBarrageShowsDetails())message.text=@"";
        [self.stateLock lock];_acceptedCount++;[self.stateLock unlock];
        message.sourceEligibilityConfirmed=YES;
        [NSNotificationCenter.defaultCenter postNotificationName:WPMessageBarrageDidReceiveNotification object:self userInfo:@{@"message":message}];
    }
}
- (void)scheduleFallbackAfter:(NSTimeInterval)delay {
    [self.stateLock lock];BOOL schedule=_active && _foreground && _fallbackPending.count && !_fallbackScheduled;
    NSUInteger generation=_generation;if(schedule)_fallbackScheduled=YES;[self.stateLock unlock];
    if(schedule)dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay*NSEC_PER_SEC)),dispatch_get_main_queue(),^{[self drainFallbackGeneration:generation];});
}
- (void)drainFallbackGeneration:(NSUInteger)generation {
    NSAssert(NSThread.isMainThread,@"Fresh arrival lookup runs on main");
    [self.stateLock lock];if(generation!=_generation){[self.stateLock unlock];return;}
    _fallbackScheduled=NO;BOOL active=_active && _foreground;NSDictionary *names=[_fallbackPending copy];NSTimeInterval activeSince=_activeSince;[self.stateLock unlock];
    if(!active || ![self enabledNow] || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive)return;
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;
    for(NSString *name in names){
        NSTimeInterval observed=[names[name] doubleValue];BOOL remove=now-observed>WPBSMetadataWait;
        if(!remove && [self eligibilityForConversation:name]==WPBarrageConversationEligibilityDenied)remove=YES;
        if(!remove){
            id wrap=WPSEReadObject([self nativeSessionForConversation:name],@[@"m_msgWrap"]);
            NSNumber *status=WPBSInteger(wrap,@"m_uiStatus"),*date=WPBSInteger(wrap,@"m_uiCreateTime");
            NSString *conversation=WPBSIdentifierValue(wrap,@"m_nsFromUsr");
            // Inspect only metadata until WeChat publishes a fresh latest wrap.
            // A monitor notification may precede that update by several turns.
            if(status.unsignedIntegerValue==3 && [conversation isEqual:name] && date.doubleValue>=activeSince-1 && date.doubleValue<=now+2 && now-date.doubleValue<=WPBSMaximumAge){
                NSNumber *server=WPBSInteger(wrap,@"m_n64MesSvrID"),*local=WPBSInteger(wrap,@"m_uiMesLocalID");NSString *identifier=nil;
                if(server.unsignedLongLongValue)identifier=[NSString stringWithFormat:@"%@:s%llu",name,server.unsignedLongLongValue];
                else if(local.unsignedLongLongValue)identifier=[NSString stringWithFormat:@"%@:l%llu:t%.0f",name,local.unsignedLongLongValue,date.doubleValue];
                if(identifier){
                    [self.stateLock lock];BOOL seen=[_seen containsObject:identifier];NSTimeInterval received=[_seenReceivedAt[identifier] doubleValue];[self.stateLock unlock];
                    if(!seen){[self captureIncomingWrap:wrap];[self.stateLock lock];remove=[_seen containsObject:identifier];[self.stateLock unlock];}
                    else if(received>=observed-.25)remove=YES;
                }
            }
        }
        if(remove){[self.stateLock lock];if([_fallbackPending[name] isEqual:names[name]])[_fallbackPending removeObjectForKey:name];[self.stateLock unlock];}
    }
    [self scheduleFallbackAfter:.35];
}
- (void)quickChatChanged:(NSNotification *)notification {
    if(!NSThread.isMainThread || ![self enabledNow])return;
    [self.stateLock lock];BOOL active=_active && _foreground;[self.stateLock unlock];if(!active || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive)return;
    // This consumes only new arrivals already identified by the monitor. Its
    // foreground baseline is not replayed and no message history is queried.
    id names=notification.userInfo[@"arrivals"];if(![names isKindOfClass:NSArray.class])return;
    NSUInteger visited=0;NSTimeInterval now=NSDate.date.timeIntervalSince1970;
    for(id name in names){
        if(visited++>=WPBSInboxLimit)break;
        if(![name isKindOfClass:NSString.class] || ![name length] || [name length]>256 || !WPQuickChatIsOpenableUsername(name) || !WPBarrageReminderAllowsUsername(name,NSDate.date))continue;
        [self.stateLock lock];
        if(_fallbackPending.count>=WPBSInboxLimit && !_fallbackPending[name]){NSString *oldest=nil;NSTimeInterval time=DBL_MAX;for(NSString *key in _fallbackPending)if([_fallbackPending[key] doubleValue]<time){oldest=key;time=[_fallbackPending[key] doubleValue];}if(oldest)[_fallbackPending removeObjectForKey:oldest];}
        _fallbackPending[name]=@(now);[self.stateLock unlock];
    }
    // Try once immediately when the native snapshot is ready, otherwise keep
    // one bounded retry chain containing names/timestamps only, never wraps.
    [self.stateLock lock];BOOL pending=_fallbackScheduled;NSUInteger generation=_generation;[self.stateLock unlock];
    if(!pending)[self drainFallbackGeneration:generation];
}
- (NSDictionary<NSString *,id> *)diagnostics {
    BOOL hooked=self.hooked,polling=self.requiresSessionPolling;NSString *hookState=self.hookState;
    [self.stateLock lock];NSDictionary *state=@{@"state":_active?@"active":@"inactive",@"route":hooked?@"receive-hook+fresh-arrival-safety":@"session-arrival-fallback",@"requiresSessionPolling":@(polling),@"installed":@(hooked),@"nativeCallbacks":@(_nativeCallbacks),@"lastCallbackAt":@(_lastNativeCallbackAt),@"lastNativeReceiveAt":@(_lastNativeReceiveAt),@"rejections":[_rejections copy],@"hook":hookState ?: @"unavailable",@"pending":@(_inbox.count),@"pendingArrivals":@(_fallbackPending.count),@"arrivalRetryScheduled":@(_fallbackScheduled),@"sessionLookupMaximumBatch":@(_sessionLookupMaxBatch),@"sessionLookupCacheLimit":@24,@"sessionLookupTargetLimit":@(WPBSInboxLimit),@"dedup":@(_seen.count),@"accepted":@(_acceptedCount),@"dropped":@(_droppedCount),@"muteUnknown":@(_mutedUnknownCount),@"queueLimit":@(WPBSInboxLimit),@"dedupLimit":@(WPBSDedupLimit),@"metadataWaitSeconds":@(WPBSMetadataWait)};[self.stateLock unlock];return state;
}
@end
