// Compile only in the simulator preview/test host. Never include in the dylib.
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import "WPActionAdapter.h"

@interface WPMockUnreadSession : NSObject
@property(nonatomic) unsigned int m_uUnReadCount;
@end
@implementation WPMockUnreadSession
@end
@interface WPMockLegacyUnreadSession : NSObject
@property(nonatomic) unsigned int m_uiUnReadCount;
@end
@implementation WPMockLegacyUnreadSession
@end
@interface WPMockIvarUnreadSession : NSObject {
@public unsigned int m_uUnReadCount;
}
@end
@implementation WPMockIvarUnreadSession
@end
@interface WPMockNegativeUnreadSession : NSObject
- (long long)m_uUnReadCount;
@end
@implementation WPMockNegativeUnreadSession
- (long long)m_uUnReadCount{return -1;}
@end

@interface MMNewSessionMgr : NSObject
@property(nonatomic) NSMutableDictionary<NSString *,id> *sessions;
@property(nonatomic) NSMutableDictionary<NSString *,NSNumber *> *messageUnread;
@property(nonatomic) id names;
@property(nonatomic) NSString *mode;
@property(nonatomic) NSUInteger writes;
@property(nonatomic) NSUInteger badgeWrites;
@property(nonatomic) NSUInteger refreshes;
@property(nonatomic) BOOL wrongRange;
@property(nonatomic) BOOL offMain;
@property(nonatomic) BOOL yielded;
@property(nonatomic) BOOL reentryRejected;
- (id)GetUserNamesOnSessionList;
- (id)GetSessionByUserName:(id)name;
- (void)ChangeSessionUnReadCount:(id)name to:(unsigned int)count;
- (void)recountUnReadCount;
@end
@implementation MMNewSessionMgr
- (instancetype)init{if((self=[super init])){_sessions=[NSMutableDictionary new];_messageUnread=[NSMutableDictionary new];_names=@[];}return self;}
- (id)GetUserNamesOnSessionList{return self.names;}
- (id)GetSessionByUserName:(id)name{return self.sessions[name];}
- (void)ChangeSessionUnReadCount:(id)name to:(unsigned int)count {
    // This only changes a badge: tests must prove the adapter never uses it.
    self.badgeWrites++;id session=self.sessions[name];
    if([session isKindOfClass:WPMockUnreadSession.class])((WPMockUnreadSession *)session).m_uUnReadCount=count;
}
- (void)recountUnReadCount {
    self.refreshes++;
    if([self.mode isEqual:@"throw-refresh"])@throw [NSException exceptionWithName:@"MockRefresh" reason:nil userInfo:nil];
}
@end
static MMNewSessionMgr *WPMockActiveManager;

// Receive contract fixtures deliberately inherit the primary callback. The
// production adapter must add an override without changing this base method.
static NSUInteger WPMockOriginalReceiveCalls;static BOOL WPMockOriginalReceiveThrows;static BOOL WPMockOriginalNotifyFlag;
@interface WPMockReceiveBase : NSObject
- (void)AsyncOnAddMsg:(id)name MsgWrap:(id)wrap;
- (void)OnAddMsg:(id)name MsgWrap:(id)wrap;
- (void)AsyncOnAddMsgForSession:(id)name MsgWrap:(id)wrap NewMsgArriveNotify:(BOOL)notify;
@end
@implementation WPMockReceiveBase
- (void)AsyncOnAddMsg:(id)name MsgWrap:(id)wrap {WPMockOriginalReceiveCalls++;if(WPMockOriginalReceiveThrows)@throw [NSException exceptionWithName:@"NativeReceiveFixture" reason:nil userInfo:nil];}
- (void)OnAddMsg:(id)name MsgWrap:(id)wrap {WPMockOriginalReceiveCalls++;}
- (void)AsyncOnAddMsgForSession:(id)name MsgWrap:(id)wrap NewMsgArriveNotify:(BOOL)notify {WPMockOriginalReceiveCalls++;WPMockOriginalNotifyFlag=notify;}
@end
NSUInteger WPPreviewOriginalReceiveCount(void){return WPMockOriginalReceiveCalls;}
BOOL WPPreviewOriginalReceiveNotifyFlag(void){return WPMockOriginalNotifyFlag;}
void WPPreviewSendIncomingWrapWithNotify(id wrap,BOOL notify){id manager=[NSClassFromString(@"CMessageMgr")new];((void(*)(id,SEL,id,id,BOOL))objc_msgSend)(manager,NSSelectorFromString(@"AsyncOnAddMsgForSession:MsgWrap:NewMsgArriveNotify:"),@"fixture",wrap,notify);}
void WPPreviewSetNativeReceiveThrows(BOOL enabled){WPMockOriginalReceiveThrows=enabled;}
void WPPreviewSendIncomingWrap(NSString *route,id wrap){id manager=[NSClassFromString(@"CMessageMgr") new];((void(*)(id,SEL,id,id))objc_msgSend)(manager,NSSelectorFromString(route),@"fixture",wrap);}
void WPPreviewSendBaseIncomingWrap(id wrap){[[WPMockReceiveBase new]AsyncOnAddMsg:@"fixture" MsgWrap:wrap];}
@interface WPMockBarrageSession : NSObject
@property(nonatomic) BOOL m_bShowUnReadAsRedDot;
@property(nonatomic) BOOL isHidden;
@property(nonatomic) id m_msgWrap;
@property(nonatomic) NSString *m_nsUserName;
@property(nonatomic) unsigned int m_uUnReadCount;
@end
@implementation WPMockBarrageSession
@end
void WPPreviewInstallBarrageSession(NSString *name,id wrap,BOOL hidden,BOOL muted){WPMockActiveManager=[MMNewSessionMgr new];WPMockBarrageSession*s=[WPMockBarrageSession new];s.m_nsUserName=name;s.m_msgWrap=wrap;s.isHidden=hidden;s.m_bShowUnReadAsRedDot=muted;s.m_uUnReadCount=1;WPMockActiveManager.names=@[name];WPMockActiveManager.sessions[name]=s;}
@interface CMessageMgr : WPMockReceiveBase
- (void)ClearUnRead:(id)name FromID:(unsigned int)from ToID:(unsigned int)to;
@end
@implementation CMessageMgr
- (void)ClearUnRead:(id)name FromID:(unsigned int)from ToID:(unsigned int)to {
    MMNewSessionMgr *manager=WPMockActiveManager;manager.writes++;
    manager.offMain|=!NSThread.isMainThread;manager.wrongRange|=from!=0 || to!=UINT32_MAX;
    if([manager.mode isEqual:@"throw-clear"])@throw [NSException exceptionWithName:@"MockClear" reason:nil userInfo:nil];
    if([manager.mode isEqual:@"ignore-clear"])return;
    manager.messageUnread[name]=@0;
    id session=manager.sessions[name];
    NSString *key=[session respondsToSelector:@selector(m_uiUnReadCount)]?@"m_uiUnReadCount":@"m_uUnReadCount";
    @try{[session setValue:@0 forKey:key];}@catch(__unused NSException *exception){}
    if([manager.mode isEqual:@"new-message-after-clear"]){
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,30*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
            manager.messageUnread[name]=@2;@try{[session setValue:@2 forKey:key];}@catch(__unused NSException *exception){}
        });
    }
}
@end
@interface WPMockWrongMessageSignature : NSObject
- (void)ClearUnRead:(id)name FromID:(unsigned int)from ToID:(unsigned long long)to;
@end
@implementation WPMockWrongMessageSignature
- (void)ClearUnRead:(id)name FromID:(unsigned int)from ToID:(unsigned long long)to{}
@end

@interface MMServiceCenter : NSObject
+ (instancetype)defaultCenter;
- (id)getService:(Class)service;
@end
@implementation MMServiceCenter
+ (instancetype)defaultCenter{static MMServiceCenter *value;static dispatch_once_t once;dispatch_once(&once,^{value=[self new];});return value;}
- (id)getService:(Class)service {
    if(service==MMNewSessionMgr.class)return WPMockActiveManager;
    if(service==CMessageMgr.class){
        if([WPMockActiveManager.mode isEqual:@"missing-message-service"])return nil;
        if([WPMockActiveManager.mode isEqual:@"wrong-integer-signature"])return [WPMockWrongMessageSignature new];
        return [CMessageMgr new];
    }
    // Other preview contract suites own their own mock service classes.
    if([service respondsToSelector:NSSelectorFromString(@"sharedManager")])return ((id(*)(id,SEL))objc_msgSend)(service,NSSelectorFromString(@"sharedManager"));
    return service?[[service alloc] init]:nil;
}
@end

static WPMockUnreadSession *WPMockSession(unsigned int count){WPMockUnreadSession *session=[WPMockUnreadSession new];session.m_uUnReadCount=count;return session;}
static MMNewSessionMgr *WPMockSingle(NSString *mode,id session){
    MMNewSessionMgr *manager=[MMNewSessionMgr new];manager.mode=mode;manager.sessions[@"alice"]=session;manager.messageUnread[@"alice"]=@4;manager.names=@[@"alice"];return manager;
}

/// Mock contract tests only: no third-party binaries, real WeChat or device access.
void WPRunWeChatMockTests(void (^completion)(NSDictionary<NSString *,NSNumber *> *)) {
    NSCAssert(NSThread.isMainThread,@"Run native WeChat contract tests on the main queue");
    NSMutableArray<NSDictionary *> *cases=[NSMutableArray new];
    void (^add)(NSString *,MMNewSessionMgr*(^)(void),BOOL(^)(BOOL,NSString *,MMNewSessionMgr *))=^(NSString *name,MMNewSessionMgr*(^setup)(void),BOOL(^check)(BOOL,NSString *,MMNewSessionMgr *)){
        [cases addObject:@{@"name":name,@"setup":[setup copy],@"check":[check copy]}];
    };
    add(@"nativeClearUsesMessageManagerAndObservedRange",^MMNewSessionMgr*{return WPMockSingle(nil,WPMockSession(4));},^BOOL(BOOL success,NSString *message,MMNewSessionMgr *m){
        return success && m.writes==1 && !m.badgeWrites && m.refreshes==1 && !m.wrongRange && !m.offMain && [m.messageUnread[@"alice"] isEqual:@0] && [message containsString:@"归零"];
    });
    add(@"nativeClearSupportsLegacyUnreadGetter",^MMNewSessionMgr*{
        WPMockLegacyUnreadSession *s=[WPMockLegacyUnreadSession new];s.m_uiUnReadCount=3;return WPMockSingle(nil,s);
    },^BOOL(BOOL success,__unused NSString *message,MMNewSessionMgr *m){return success && m.writes==1 && !m.badgeWrites && ((WPMockLegacyUnreadSession *)m.sessions[@"alice"]).m_uiUnReadCount==0;});
    add(@"nativeClearSupportsNumericIvarEvidence",^MMNewSessionMgr*{
        WPMockIvarUnreadSession *s=[WPMockIvarUnreadSession new];s->m_uUnReadCount=2;return WPMockSingle(nil,s);
    },^BOOL(BOOL success,__unused NSString *message,MMNewSessionMgr *m){return success && m.writes==1 && ((WPMockIvarUnreadSession *)m.sessions[@"alice"])->m_uUnReadCount==0;});
    add(@"nativeClearUnknownCountNeverClaimsZero",^MMNewSessionMgr*{return WPMockSingle(nil,[NSObject new]);},^BOOL(BOOL success,NSString *message,MMNewSessionMgr *m){return !success && m.writes==1 && [message containsString:@"无法读取"];});
    add(@"nativeClearNegativeCountNeverClaimsZero",^MMNewSessionMgr*{return WPMockSingle(nil,[WPMockNegativeUnreadSession new]);},^BOOL(BOOL success,NSString *message,MMNewSessionMgr *m){return !success && m.writes==1 && [message containsString:@"无法读取"];});
    add(@"nativeClearEmptyListDistinctFromNoUnread",^MMNewSessionMgr*{return [MMNewSessionMgr new];},^BOOL(BOOL success,NSString *message,MMNewSessionMgr *m){return !success && !m.writes && [message containsString:@"列表为空"];});
    add(@"nativeClearUnavailableListDistinctFromEmpty",^MMNewSessionMgr*{MMNewSessionMgr *m=[MMNewSessionMgr new];m.names=nil;return m;},^BOOL(BOOL success,NSString *message,MMNewSessionMgr *m){return !success && !m.writes && [message containsString:@"无法读取当前会话列表"];});
    add(@"nativeClearZeroBadgeStillClearsMessageState",^MMNewSessionMgr*{return WPMockSingle(nil,WPMockSession(0));},^BOOL(BOOL success,__unused NSString *message,MMNewSessionMgr *m){return success && m.writes==1 && !m.badgeWrites && [m.messageUnread[@"alice"] isEqual:@0];});
    for(NSString *mode in @[@"ignore-clear",@"new-message-after-clear",@"throw-clear",@"throw-refresh"]){
        add([@"nativeClearRejectsFalseSuccess_" stringByAppendingString:mode],^MMNewSessionMgr*{return WPMockSingle(mode,WPMockSession(3));},^BOOL(BOOL success,NSString *message,__unused MMNewSessionMgr *m){return !success && message.length;});
    }
    for(NSString *mode in @[@"wrong-integer-signature",@"missing-message-service"]){
        add([@"nativeClearRejectsUnavailableContract_" stringByAppendingString:mode],^MMNewSessionMgr*{return WPMockSingle(mode,WPMockSession(3));},^BOOL(BOOL success,NSString *message,MMNewSessionMgr *m){return !success && !m.writes && [message containsString:@"不可用"];});
    }
    add(@"nativeClearMainQueueYieldsBetweenBatches",^MMNewSessionMgr*{
        MMNewSessionMgr *m=[MMNewSessionMgr new];m.mode=@"observe-yield";NSMutableArray *names=[NSMutableArray new];
        for(NSUInteger i=0;i<37;i++){NSString *name=[NSString stringWithFormat:@"friend%lu",(unsigned long)i];[names addObject:name];m.sessions[name]=WPMockSession(2);m.messageUnread[name]=@2;}
        m.names=names;return m;
    },^BOOL(BOOL success,__unused NSString *message,MMNewSessionMgr *m){return success && m.writes==37 && !m.badgeWrites && !m.offMain && m.yielded;});
    add(@"nativeClearRejectsConcurrentGesture",^MMNewSessionMgr*{return WPMockSingle(@"observe-reentry",WPMockSession(4));},^BOOL(BOOL success,__unused NSString *message,MMNewSessionMgr *m){return success && m.writes==1 && m.reentryRejected;});
    NSMutableDictionary<NSString *,NSNumber *> *results=[NSMutableDictionary new];
    __block NSUInteger index=0;__block void (^next)(void);
    next=^{
        if(index>=cases.count){WPMockActiveManager=nil;completion([results copy]);next=nil;return;}
        NSDictionary *test=cases[index++];MMNewSessionMgr*(^setup)(void)=test[@"setup"];BOOL(^check)(BOOL,NSString *,MMNewSessionMgr *)=test[@"check"];
        WPMockActiveManager=setup();MMNewSessionMgr *current=WPMockActiveManager;
        [WPActionAdapter performAction:@"read" inWindow:nil completion:^(BOOL success,NSString *message){
            results[test[@"name"]]=@(check(success,message,current));next();
        }];
        if([current.mode isEqual:@"observe-yield"])dispatch_async(dispatch_get_main_queue(),^{current.yielded=current.writes>0 && current.writes<=12;});
        if([current.mode isEqual:@"observe-reentry"])[WPActionAdapter performAction:@"read" inWindow:nil completion:^(BOOL success,NSString *message){current.reentryRejected=!success && [message containsString:@"正在处理"]; }];
    };
    next();
}
