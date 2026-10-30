#import "WPActionAdapter.h"
#import "WPCommon.h"
#import <objc/runtime.h>

static NSMethodSignature *WPASignature(id target,NSString *name,NSUInteger arguments){
    SEL selector=NSSelectorFromString(name);if(!target)return nil;
    NSMethodSignature *signature=nil;
    @try{signature=[target methodSignatureForSelector:selector];}@catch(__unused NSException *exception){return nil;}
    if(!signature)return nil;
    return signature.numberOfArguments==arguments+2?signature:nil;
}
static id WPAObject(id target,NSString *name,id argument,BOOL hasArgument){
    NSMethodSignature *signature=WPASignature(target,name,hasArgument?1:0);
    if(!signature || signature.methodReturnType[0]!='@')return nil;
    if(hasArgument && !strchr("@#",[signature getArgumentTypeAtIndex:2][0]))return nil;
    @try{NSInvocation *call=[NSInvocation invocationWithMethodSignature:signature];call.target=target;call.selector=NSSelectorFromString(name);__unsafe_unretained id value=argument;if(hasArgument)[call setArgument:&value atIndex:2];[call invoke];__unsafe_unretained id result=nil;[call getReturnValue:&result];return result;}@catch(__unused NSException *exception){return nil;}
}
static id WPASessions(void){return WPWeChatService(@"MMNewSessionMgr");}
static const char *WPAUnqualified(const char *type) {
    while (type && *type && strchr("rnNoORV", *type)) type++;
    return type;
}
static BOOL WPAIntegerType(const char *type) {
    const char *value=WPAUnqualified(type);
    return value && value[0] && strchr("cCsSiIlLqQ",value[0]) && value[1]=='\0';
}
static NSNumber *WPAIntegerReturn(NSInvocation *call, NSMethodSignature *signature) {
    const char *type=WPAUnqualified(signature.methodReturnType);
    if(!WPAIntegerType(type))return nil;
    switch(type[0]) {
#define WPA_SIGNED_CASE(code, scalar) case code: { scalar value=0;[call getReturnValue:&value];return value<0?nil:@((uint64_t)value); }
#define WPA_UNSIGNED_CASE(code, scalar) case code: { scalar value=0;[call getReturnValue:&value];return @((uint64_t)value); }
        WPA_SIGNED_CASE('c',signed char)
        WPA_UNSIGNED_CASE('C',unsigned char)
        WPA_SIGNED_CASE('s',short)
        WPA_UNSIGNED_CASE('S',unsigned short)
        WPA_SIGNED_CASE('i',int)
        WPA_UNSIGNED_CASE('I',unsigned int)
        WPA_SIGNED_CASE('l',long)
        WPA_UNSIGNED_CASE('L',unsigned long)
        WPA_SIGNED_CASE('q',long long)
        WPA_UNSIGNED_CASE('Q',unsigned long long)
#undef WPA_SIGNED_CASE
#undef WPA_UNSIGNED_CASE
    }
    return nil;
}
static BOOL WPAIntegerKVCEvidence(id session, NSString *key) {
    Class cls=object_getClass(session);
    objc_property_t property=cls?class_getProperty(cls,key.UTF8String):NULL;
    if(property) {
        char *type=property_copyAttributeValue(property,"T");
        BOOL integer=type && WPAIntegerType(type);free(type);if(integer)return YES;
    }
    for(NSString *ivarName in @[key,[@"_" stringByAppendingString:key]]) {
        Ivar ivar=cls?class_getInstanceVariable(cls,ivarName.UTF8String):NULL;
        if(ivar && WPAIntegerType(ivar_getTypeEncoding(ivar)))return YES;
    }
    return NO;
}
static NSNumber *WPAUnread(id session) {
    if(!session)return nil;
    for(NSString *name in @[@"m_uUnReadCount",@"m_uiUnReadCount"]) {
        NSMethodSignature *signature=WPASignature(session,name,0);
        if(signature && WPAIntegerType(signature.methodReturnType)) {
            @try {
                NSInvocation *call=[NSInvocation invocationWithMethodSignature:signature];
                call.target=session;call.selector=NSSelectorFromString(name);[call invoke];
                NSNumber *value=WPAIntegerReturn(call,signature);if(value)return value;
            } @catch(__unused NSException *exception){}
        }
        // KVC is allowed only when this exact property/ivar has numeric runtime
        // evidence. Unknown keys never turn an unreadable count into zero.
        if(WPAIntegerKVCEvidence(session,name)) {
            @try {
                id value=[session valueForKey:name];
                if([value isKindOfClass:NSNumber.class] && WPAIntegerType([value objCType]) && [value compare:@0]!=NSOrderedAscending)
                    return @([value unsignedLongLongValue]);
            } @catch(__unused NSException *exception){}
        }
    }
    return nil;
}
NSNumber *WPSessionUnreadCount(id session){return WPAUnread(session);}
// Verified from the user-supplied WCRefine 2.1-9 binary's call site at
// 0x183848–0x183aec: CMessageMgr ClearUnRead:FromID:ToID:, username,
// uint32_t 0, uint32_t UINT32_MAX. This is an independent adapter to WeChat's
// own implementation. This native fallback does not depend on WCRefine.
static BOOL WPAClearSignature(id messages) {
    NSMethodSignature *signature=WPASignature(messages,@"ClearUnRead:FromID:ToID:",3);
    return signature && !strcmp(WPAUnqualified(signature.methodReturnType),"v") &&
        !strcmp(WPAUnqualified([signature getArgumentTypeAtIndex:2]),"@") &&
        !strcmp(WPAUnqualified([signature getArgumentTypeAtIndex:3]),"I") &&
        !strcmp(WPAUnqualified([signature getArgumentTypeAtIndex:4]),"I");
}
static BOOL WPAReadSignatures(id manager) {
    NSMethodSignature *names=WPASignature(manager,@"GetUserNamesOnSessionList",0);
    NSMethodSignature *session=WPASignature(manager,@"GetSessionByUserName:",1);
    return names && WPAUnqualified(names.methodReturnType)[0]=='@' && session &&
        WPAUnqualified(session.methodReturnType)[0]=='@' &&
        !strcmp(WPAUnqualified([session getArgumentTypeAtIndex:2]),"@");
}
static BOOL WPARefreshSessions(id manager) {
    // The inspected entry calls recountUnReadCount after native message clears.
    for(NSString *name in @[@"recountUnReadCount",@"recountUnReadCountAndFireExtension"]) {
        NSMethodSignature *signature=WPASignature(manager,name,0);
        if(!signature || strcmp(WPAUnqualified(signature.methodReturnType),"v"))continue;
        @try {
            NSInvocation *call=[NSInvocation invocationWithMethodSignature:signature];
            call.target=manager;call.selector=NSSelectorFromString(name);[call invoke];return YES;
        } @catch(__unused NSException *exception){return NO;}
    }
    return NO;
}
static NSArray<NSString *> *WPASessionNames(id manager, NSUInteger *invalid) {
    id raw=WPAObject(manager,@"GetUserNamesOnSessionList",nil,NO);
    if(![raw isKindOfClass:NSArray.class] && ![raw isKindOfClass:NSSet.class])return nil;
    NSMutableOrderedSet *names=[NSMutableOrderedSet new];
    for(id value in raw) {
        if([value isKindOfClass:NSString.class] && [value length])[names addObject:value];
        else if(invalid)(*invalid)++;
    }
    return names.array;
}
static BOOL WPAClearUnread(id messages, NSString *username) {
    if(!username.length || !WPAClearSignature(messages))return NO;
    @try {
        NSMethodSignature *signature=WPASignature(messages,@"ClearUnRead:FromID:ToID:",3);
        NSInvocation *call=[NSInvocation invocationWithMethodSignature:signature];
        call.target=messages;call.selector=NSSelectorFromString(@"ClearUnRead:FromID:ToID:");
        __unsafe_unretained id name=username;
        unsigned int from=0,to=UINT32_MAX;
        [call setArgument:&name atIndex:2];[call setArgument:&from atIndex:3];[call setArgument:&to atIndex:4];
        [call invoke];
        return YES;
    } @catch(__unused NSException *exception){return NO;}
}

// Optional compatibility with an already-installed Refine plugin. Do not load
// any third-party image: only use this exact, runtime-validated class method if
// it is present in the current WeChat process. The inspected implementation
// accepts a nil toast and performs its own native unread clearing and recount.
static id WPAInstalledRefineReadHook(void) {
    id hook=NSClassFromString(@"WCRefineClearUnreadMsgHook");
    NSMethodSignature *signature=WPASignature(hook,@"WCRefine_doClearUnreadMsgWithToast:",1);
    if(!signature || strcmp(WPAUnqualified(signature.methodReturnType),"v") ||
       strcmp(WPAUnqualified([signature getArgumentTypeAtIndex:2]),"@"))return nil;
    return hook;
}
static BOOL WPAInvokeInstalledRefineRead(id hook, BOOL *attempted) {
    if(attempted)*attempted=NO;
    NSCAssert(NSThread.isMainThread,@"Invoke installed Refine on WeChat's main queue");
    NSMethodSignature *signature=WPASignature(hook,@"WCRefine_doClearUnreadMsgWithToast:",1);
    if(!hook || hook!=WPAInstalledRefineReadHook())return NO;
    @try {
        NSInvocation *call=[NSInvocation invocationWithMethodSignature:signature];
        call.target=hook;call.selector=NSSelectorFromString(@"WCRefine_doClearUnreadMsgWithToast:");
        __unsafe_unretained id toast=nil;[call setArgument:&toast atIndex:2];
        if(attempted)*attempted=YES;
        [call invoke];return YES;
    } @catch(__unused NSException *exception){return NO;}
}

static NSDictionary<NSString *,id> *WPALastReadDiagnostics;
static void WPAReadDiagnostic(NSDictionary<NSString *,id> *values) {
    @synchronized(WPActionAdapter.class) {
        NSMutableDictionary *state=[WPALastReadDiagnostics mutableCopy] ?: [NSMutableDictionary new];
        [state addEntriesFromDictionary:values];WPALastReadDiagnostics=[state copy];
    }
}

static BOOL WPAClearInProgress=NO; // Accessed only on the main queue.
@interface WPANativeReadJob : NSObject
@property(nonatomic,strong) id sessions;
@property(nonatomic,strong) id messages;
@property(nonatomic,copy) NSArray<NSString *> *names;
@property(nonatomic,copy) NSArray<NSString *> *verifyNames;
@property(nonatomic,copy) void(^completion)(BOOL,NSString *);
@property(nonatomic) NSUInteger index;
@property(nonatomic) NSUInteger invalidNames;
@property(nonatomic) NSUInteger calls;
@property(nonatomic) NSUInteger callFailures;
@property(nonatomic) NSUInteger unknown;
@property(nonatomic) NSUInteger remaining;
@property(nonatomic) NSUInteger verified;
@property(nonatomic) BOOL refreshed;
@property(nonatomic) BOOL usesInstalledRefine;
- (void)start;
- (void)startVerification;
@end
@implementation WPANativeReadJob
- (void)finish:(BOOL)success message:(NSString *)message {
    WPAClearInProgress=NO;
    WPAReadDiagnostic(@{@"state":success?@"verified":@"unverified",@"verifiedSuccess":@(success),
                        @"nativeClearCalls":@(self.calls),@"unknownCounts":@(self.unknown),
                        @"remainingUnreadSessions":@(self.remaining),@"verifiedSessions":@(self.verified)});
    void(^completion)(BOOL,NSString *)=self.completion;self.completion=nil;
    if(completion)completion(success,message);
}
- (void)start { dispatch_async(dispatch_get_main_queue(),^{[self clearNextBatch];}); }
- (void)startVerification {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,150*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[self beginVerification];});
}
- (void)clearNextBatch {
    NSAssert(NSThread.isMainThread,@"Clear WeChat unread state on its main queue");
    CFTimeInterval deadline=CFAbsoluteTimeGetCurrent()+.008;
    NSUInteger batch=0;
    while(self.index<self.names.count && batch<12) {
        @autoreleasepool {
            NSString *username=self.names[self.index++];
            if(WPAClearUnread(self.messages,username))self.calls++;
            else self.callFailures++;
        }
        batch++;
        if(CFAbsoluteTimeGetCurrent()>=deadline)break;
    }
    if(self.index<self.names.count){dispatch_async(dispatch_get_main_queue(),^{[self clearNextBatch];});return;}
    self.refreshed=self.calls && WPARefreshSessions(self.sessions);
    [self startVerification];
}
- (void)beginVerification {
    NSUInteger invalid=0;
    NSArray<NSString *> *latest=WPASessionNames(self.sessions,&invalid);
    if(!latest || !latest.count){
        NSString *message=self.usesInstalledRefine?@"已调用 Refine 的一键已读功能，请在微信首页查看红点；当前无法读取会话列表，尚未自动确认结果。":(self.calls?@"已调用微信原生已读接口，但无法重新读取会话列表，尚未确认全部成功。":@"未能处理会话，请回到微信首页后重试。");
        [self finish:NO message:message];
        return;
    }
    NSMutableOrderedSet *verify=[NSMutableOrderedSet orderedSetWithArray:latest];
    [verify addObjectsFromArray:self.names];
    self.verifyNames=verify.array;self.index=0;self.unknown=MAX(invalid,self.invalidNames);
    [self verifyNextBatch];
}
- (void)verifyNextBatch {
    CFTimeInterval deadline=CFAbsoluteTimeGetCurrent()+.008;
    NSUInteger batch=0;
    while(self.index<self.verifyNames.count && batch<24) {
        @autoreleasepool {
            NSString *username=self.verifyNames[self.index++];
            NSNumber *count=WPAUnread(WPAObject(self.sessions,@"GetSessionByUserName:",username,YES));
            if(!count)self.unknown++;
            else if(count.unsignedLongLongValue)self.remaining++;
            else self.verified++;
        }
        batch++;
        if(CFAbsoluteTimeGetCurrent()>=deadline)break;
    }
    if(self.index<self.verifyNames.count){dispatch_async(dispatch_get_main_queue(),^{[self verifyNextBatch];});return;}
    BOOL success=(self.usesInstalledRefine || (self.calls && !self.callFailures && self.refreshed)) && !self.unknown && !self.remaining;
    if(success){
        NSString *message=self.usesInstalledRefine?[NSString stringWithFormat:@"已调用 Refine 一键已读，并独立确认 %lu 个会话的未读计数归零。",(unsigned long)self.verified]:[NSString stringWithFormat:@"已通过微信原生接口处理 %lu 个会话，并确认未读计数归零。",(unsigned long)self.calls];
        [self finish:YES message:message];
        return;
    }
    NSMutableArray *parts=[NSMutableArray new];
    if(self.usesInstalledRefine)[parts addObject:@"已调用 Refine 的一键已读功能"];
    if(self.calls)[parts addObject:[NSString stringWithFormat:@"已调用微信原生已读接口处理 %lu 个会话",(unsigned long)self.calls]];
    if(self.remaining)[parts addObject:[NSString stringWithFormat:@"仍有 %lu 个会话未读，可能有新消息或尚未归零",(unsigned long)self.remaining]];
    if(self.unknown)[parts addObject:[NSString stringWithFormat:@"有 %lu 个会话无法读取未读计数，尚不能完整核验",(unsigned long)self.unknown]];
    if(self.callFailures)[parts addObject:[NSString stringWithFormat:@"有 %lu 个会话处理调用失败",(unsigned long)self.callFailures]];
    if(!self.usesInstalledRefine && !self.refreshed)[parts addObject:@"会话未读汇总刷新未完成，请返回微信首页核对"];
    [self finish:NO message:[parts componentsJoinedByString:@"；"]];
}
@end

@implementation WPActionAdapter
+ (BOOL)supportsMarkAllRead {
    return WPAInstalledRefineReadHook()!=nil || (WPAClearSignature(WPWeChatService(@"CMessageMgr")) && WPAReadSignatures(WPASessions()));
}
+ (NSDictionary<NSString *,id> *)lastMarkAllReadDiagnostics {
    @synchronized(WPActionAdapter.class){return [WPALastReadDiagnostics copy] ?: @{@"state":@"not_requested"};}
}
+ (void)markAllRead:(void(^)(BOOL,NSString *))completion {
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{[self markAllRead:completion];});return;}
    if(WPAClearInProgress){completion(NO,@"正在处理全部已读，请稍候。");return;}
    id sessions=WPASessions(),messages=WPWeChatService(@"CMessageMgr");
    BOOL nativeReady=WPAClearSignature(messages) && WPAReadSignatures(sessions);
    NSUInteger invalid=0;
    NSArray<NSString *> *names=nativeReady?WPASessionNames(sessions,&invalid):nil;
    id refine=WPAInstalledRefineReadHook();
    // Prefer independently verified native services in the active user context.
    // Use the installed plugin only if no usable native session list is exposed.
    if(refine && (!nativeReady || !names.count)) {
        WPAClearInProgress=YES;
        @synchronized(WPActionAdapter.class){WPALastReadDiagnostics=@{@"route":@"installed_refine",@"state":@"invoking",@"invoked":@NO,@"verifiedSuccess":@NO,@"sessionListAvailable":@(names!=nil),@"requestedSessionCount":@(names.count)};}
        // Once this method is invoked, never run the independent route as well:
        // Refine may have already cleared messages even if it throws later.
        BOOL attempted=NO;
        BOOL invoked=WPAInvokeInstalledRefineRead(refine,&attempted);
        WPAReadDiagnostic(@{@"state":invoked?@"verifying":@"invocation_failed",@"invoked":@(attempted),@"invocationCompleted":@(invoked)});
        if(!invoked){WPAClearInProgress=NO;completion(NO,@"调用已安装 Refine 的一键已读入口失败，未重复调用其他接口，请从 Refine 原入口核对。");return;}
        WPANativeReadJob *job=[WPANativeReadJob new];
        job.sessions=sessions;job.names=names ?: @[];job.invalidNames=invalid;job.completion=completion;job.usesInstalledRefine=YES;
        [job startVerification];return;
    }
    @synchronized(WPActionAdapter.class){WPALastReadDiagnostics=@{@"route":@"wechat_native",@"state":@"checking",@"invoked":@NO,@"verifiedSuccess":@NO};}
    if(!nativeReady){
        WPAReadDiagnostic(@{@"state":@"unsupported"});
        completion(NO,@"当前微信版本的原生已读接口或会话服务不可用，暂未执行。");return;
    }
    WPAReadDiagnostic(@{@"sessionListAvailable":@(names!=nil),@"requestedSessionCount":@(names.count)});
    if(!names){WPAReadDiagnostic(@{@"state":@"session_list_unavailable"});completion(NO,@"无法读取当前会话列表，请回到微信首页后重试。");return;}
    if(!names.count){WPAReadDiagnostic(@{@"state":@"no_sessions"});completion(NO,invalid?@"会话标识无法识别，暂未执行已读操作。":@"当前会话列表为空，请回到微信首页等待列表加载后重试。");return;}
    WPAClearInProgress=YES;
    WPAReadDiagnostic(@{@"state":@"clearing",@"invoked":@YES});
    WPANativeReadJob *job=[WPANativeReadJob new];
    job.sessions=sessions;job.messages=messages;job.names=names;job.invalidNames=invalid;job.completion=completion;
    [job start];
}
+ (UITabBarController *)tabController:(UIViewController *)controller {
    if ([controller isKindOfClass:UITabBarController.class]) return (id)controller;
    for (UIViewController *child in controller.childViewControllers) {
        UITabBarController *tabs = [self tabController:child]; if (tabs) return tabs;
    }
    return nil;
}
+ (BOOL)view:(UIView *)view hasExactText:(NSArray<NSString *> *)labels {
    if ([view isKindOfClass:UILabel.class] && [labels containsObject:((UILabel *)view).text ?: @""]) return YES;
    if ([labels containsObject:view.accessibilityLabel ?: @""]) return YES;
    for (UIView *child in view.subviews) if ([self view:child hasExactText:labels]) return YES;
    return NO;
}
+ (BOOL)activateRowWithLabels:(NSArray<NSString *> *)labels inView:(UIView *)view {
    if (view.hidden || view.alpha < .01) return NO;
    if([view isKindOfClass:UIControl.class] && [self view:view hasExactText:labels]){
        UIControl *control=(id)view;if(control.enabled){[control sendActionsForControlEvents:UIControlEventTouchUpInside];return YES;}
    }
    if ([view isKindOfClass:UITableView.class]) {
        UITableView *table = (id)view;
        for (UITableViewCell *cell in table.visibleCells) {
            if (![self view:cell hasExactText:labels]) continue;
            NSIndexPath *path = [table indexPathForCell:cell];
            if (path && [table.delegate respondsToSelector:@selector(tableView:didSelectRowAtIndexPath:)]) {
                [table.delegate tableView:table didSelectRowAtIndexPath:path]; return YES;
            }
        }
    }
    for (UIView *child in view.subviews) if ([self activateRowWithLabels:labels inView:child]) return YES;
    return NO;
}
+ (BOOL)selectTab:(NSArray<NSString *> *)labels inWindow:(UIWindow *)window {
    UITabBarController *tabs = [self tabController:window.rootViewController];
    for (UIViewController *controller in tabs.viewControllers) {
        if (![labels containsObject:controller.tabBarItem.title ?: controller.title ?: @""]) continue;
        if ([tabs.delegate respondsToSelector:@selector(tabBarController:shouldSelectViewController:)] &&
            ![tabs.delegate tabBarController:tabs shouldSelectViewController:controller]) return NO;
        tabs.selectedViewController = controller;
        if ([tabs.delegate respondsToSelector:@selector(tabBarController:didSelectViewController:)])
            [tabs.delegate tabBarController:tabs didSelectViewController:controller];
        if ([controller isKindOfClass:UINavigationController.class]) [(UINavigationController *)controller popToRootViewControllerAnimated:NO];
        return YES;
    }
    return NO;
}
+ (void)performAction:(NSString *)action inWindow:(UIWindow *)window completion:(void (^)(BOOL, NSString *))completion {
    if ([action isEqualToString:@"read"]) {
        [self markAllRead:completion]; return;
    }
    if (!window || !window.rootViewController) { completion(NO, @"未找到微信主窗口，请先返回微信首页。"); return; }
    if ([action isEqualToString:@"moments"]) {
        if (![self selectTab:@[@"发现", @"Discover"] inWindow:window]) {
            completion(NO, @"此版本的发现入口尚未识别，请到微信首页后重试。"); return;
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 350 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            BOOL ok = [self activateRowWithLabels:@[@"朋友圈", @"Moments"] inView:window];
            completion(ok, ok ? @"已打开朋友圈" : @"此版本的朋友圈入口尚待适配。");
        }); return;
    }
    completion(NO, @"此功能暂不可用。");
}

@end
