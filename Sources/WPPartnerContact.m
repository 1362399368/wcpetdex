#import "WPPartnerContact.h"
#import "WPCommon.h"
#import "WPResizableChat.h"
#import "WPChatPresentationState.h"
#import <objc/runtime.h>

static char WPHalfNavigationKey;
static char WPNativeChatRequestKey;
@interface WPNativeChatRequest : NSObject
@property(nonatomic,weak) UIWindow *window;
@property(nonatomic,weak) UIViewController *presenter;
@property(nonatomic,strong) UIViewController *beforeChat;
@property(nonatomic,strong) UIViewController *beforePresentation;
@property(nonatomic,strong) UIViewController *createdPresentation;
@property(nonatomic,copy) NSString *username;
@property(nonatomic,strong) NSMutableArray *completions;
@property(nonatomic) NSTimeInterval started;
@property(nonatomic) BOOL finished;
@end
@implementation WPNativeChatRequest @end

// Private APIs are version-dependent. These public, historical headers document
// the narrow read/navigation selectors supported here; actual runtime encodings
// are validated before every invocation. No database access or contact upload.
// https://github.com/Y93936543/WeChatHook/blob/master/ELWeChat/ELWeChat/Main/ELWeChatHeaderinfo/ELWeChatHeaderinfo.h
// https://github.com/iosre/WeChatRobotForExample/blob/c06f47c4172cbf6a9d40779fd17cd95051d8a72b/WeChatRobotForExample.h
// https://github.com/sherlockZ/LKMessageSwitchPod/blob/cbd0524f19f1f700532cb62caa1250aec1f4d397/LKMessageSwitchPod/header/WeChatHeader.h

static const char *WPUnqualifiedType(const char *type) {
    while (type && *type && strchr("rnNoORV", *type)) type++;
    return type;
}
static BOOL WPObjectType(const char *type) { return WPUnqualifiedType(type)[0] == '@'; }
static NSMethodSignature *WPSignature(id target, SEL selector, NSUInteger arguments) {
    if (!target || ![target respondsToSelector:selector]) return nil;
    // MMContext may return a lazy service proxy. Its forwarding signature carries
    // the real method ABI even though object_getClass lacks that method.
    NSMethodSignature *signature = nil;
    @try { signature = [target methodSignatureForSelector:selector]; }
    @catch (__unused NSException *exception) { return nil; }
    if (!signature) return nil;
    return signature.numberOfArguments == arguments + 2 ? signature : nil;
}
static id WPObjectCall(id target, NSString *name, id argument, BOOL hasArgument) {
    SEL selector = NSSelectorFromString(name);
    NSMethodSignature *signature = WPSignature(target, selector, hasArgument ? 1 : 0);
    if (!signature || !WPObjectType(signature.methodReturnType)) return nil;
    if (hasArgument) {
        const char *type = WPUnqualifiedType([signature getArgumentTypeAtIndex:2]);
        if (type[0] != '@' && type[0] != '#') return nil;
        if (type[0] == '#' && !object_isClass(argument)) return nil;
    }
    @try {
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        invocation.target = target;
        invocation.selector = selector;
        __unsafe_unretained id value = argument;
        if (hasArgument) [invocation setArgument:&value atIndex:2];
        [invocation invoke];
        __unsafe_unretained id result = nil;
        [invocation getReturnValue:&result];
        return result;
    } @catch (__unused NSException *exception) { return nil; }
}
static NSString *WPContactString(id contact, NSString *name) {
    id value = WPObjectCall(contact, name, nil, NO);
    return [value isKindOfClass:NSString.class] ? value : @"";
}
// These five exact names are observed in the supplied plugin's native session
// selection bridge. A callback can supply a username string or a contact object;
// selecting one person does not depend on enumerating the whole address book.
static NSString *WPUsernameForValue(id value) {
    if ([value isKindOfClass:NSString.class])
        return [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    for (NSString *key in @[@"m_nsUsrName", @"m_nsUserName", @"username", @"userName", @"getContactUserName"]) {
        id candidate = WPObjectCall(value, key, nil, NO);
        if (![candidate isKindOfClass:NSString.class]) {
            @try { candidate = [value valueForKey:key]; }
            @catch (__unused NSException *exception) { candidate = nil; }
        }
        if ([candidate isKindOfClass:NSString.class]) {
            NSString *name = [candidate stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (name.length) return name;
        }
    }
    return @"";
}
static id WPContactService(void) {
    return WPWeChatService(@"CContactMgr");
}
static id WPContactForUsername(id manager, NSString *username) {
    id contact = WPObjectCall(manager, @"getContactByName:", username, YES);
    if (!contact) contact = WPObjectCall(manager, @"getContactByNameFromDB:", username, YES);
    return [WPUsernameForValue(contact) isEqualToString:username] ? contact : nil;
}
static NSNumber *WPContactBoolean(id value, NSString *name) {
    NSMethodSignature *signature = WPSignature(value, NSSelectorFromString(name), 0);
    if (!signature || !strchr("Bc", WPUnqualifiedType(signature.methodReturnType)[0])) return nil;
    @try {
        NSInvocation *call = [NSInvocation invocationWithMethodSignature:signature];
        call.target = value; call.selector = NSSelectorFromString(name); [call invoke];
        unsigned char result = 0; [call getReturnValue:&result]; return @(result != 0);
    } @catch (__unused NSException *exception) { return nil; }
}
static NSString *WPContactSelectionError(NSString *username, id contact, NSString *selfName) {
    if (!username.length || username.length > 256 || [username rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound)
        return @"未能识别这个联系人，请重新选择。";
    if (([username.lowercaseString hasSuffix:@"@chatroom"] || [username.lowercaseString hasSuffix:@"@im.chatroom"]) || [username hasPrefix:@"gh_"] ||
        [WPContactBoolean(contact, @"isBrandContact") boolValue] || [WPContactBoolean(contact, @"isOfficialContact") boolValue])
        return @"请选择一位微信好友，不能选择群聊或公众号。";
    if (selfName.length && [username isEqualToString:selfName]) return @"请选择其他联系人，不能选择自己。";
    static NSSet *systemNames; static dispatch_once_t once;
    dispatch_once(&once, ^{ systemNames = [NSSet setWithArray:@[@"filehelper", @"fmessage", @"medianote", @"newsapp", @"weixin", @"qqmail", @"tmessage", @"floatbottle", @"notifymessage", @"weixinreminder", @"notification_messages"]]; });
    if ([systemNames containsObject:username.lowercaseString]) return @"请选择一位微信好友。";
    NSNumber *friend = WPContactBoolean(contact, @"isMyContact");
    if (friend && !friend.boolValue) return @"请选择已添加的微信好友。";
    return nil;
}
static NSArray *WPContactCollection(id value) {
    if([value isKindOfClass:NSArray.class])return value;
    if([value isKindOfClass:NSSet.class])return [value allObjects];
    if([value isKindOfClass:NSDictionary.class])return [value allValues];
    return nil;
}
static NSArray *WPContactList(id manager) {
    NSArray *cached=WPContactCollection(WPObjectCall(manager,@"m_dicContacts",nil,NO));
    if(cached.count)return cached;
    // Historical CContactMgr declares this read-only list query. Both integer
    // widths and the object return are checked on the installed WeChat build.
    SEL selector=NSSelectorFromString(@"getContactList:contactType:");
    NSMethodSignature *signature=WPSignature(manager,selector,2);
    if(!signature || !WPObjectType(signature.methodReturnType))return nil;
    for(NSUInteger i=2;i<4;i++)if(!strchr("iIlLqQ",WPUnqualifiedType([signature getArgumentTypeAtIndex:i])[0]))return nil;
    @try {
        NSInvocation *invocation=[NSInvocation invocationWithMethodSignature:signature];invocation.target=manager;invocation.selector=selector;
        uint64_t list=1,type=0;[invocation setArgument:&list atIndex:2];[invocation setArgument:&type atIndex:3];[invocation invoke];
        __unsafe_unretained id result=nil;[invocation getReturnValue:&result];return WPContactCollection(result);
    } @catch(__unused NSException *exception){return nil;}
}
static NSArray *WPOutputContactList(id manager, NSString *name, BOOL hasListType) {
    SEL selector=NSSelectorFromString(name);
    NSMethodSignature *signature=WPSignature(manager,selector,hasListType?2:1);
    if(!signature || !strchr("Bc",WPUnqualifiedType(signature.methodReturnType)[0]) || !WPObjectType([signature getArgumentTypeAtIndex:2]))return nil;
    if(hasListType && strcmp(WPUnqualifiedType([signature getArgumentTypeAtIndex:3]),"I"))return nil;
    NSMutableArray *output=[NSMutableArray new];
    @try {
        NSInvocation *call=[NSInvocation invocationWithMethodSignature:signature];call.target=manager;call.selector=selector;
        __unsafe_unretained id argument=output;uint32_t listType=1;
        [call setArgument:&argument atIndex:2];if(hasListType)[call setArgument:&listType atIndex:3];[call invoke];
        // Some builds return NO for a partially cached list. Actual objects are
        // still useful; each contact is independently validated below.
        return [output copy];
    }@catch(__unused NSException *exception){return nil;}
}
static NSString *WPNameForContact(id contact) {
    for (NSString *selector in @[@"getContactDisplayName", @"m_nsRemark", @"m_nsNickName"]) {
        NSString *value = WPContactString(contact, selector);
        if (value.length) return value;
    }
    return WPUsernameForValue(contact);
}

@implementation WPPartnerContact
+ (NSString *)displayNameForUsername:(NSString *)username {
    NSAssert(NSThread.isMainThread, @"Read WeChat contacts on its main queue");
    id contact = username.length ? WPContactForUsername(WPContactService(), username) : nil;
    NSString *name = contact ? WPNameForContact(contact) : @"";
    return [name isEqualToString:username] ? @"" : name;
}
+ (UIViewController *)visibleController:(UIViewController *)controller {
    for (NSUInteger count = 0; controller && count < 30; count++) {
        UIViewController *next = nil;
        if (controller.presentedViewController && !controller.presentedViewController.isBeingDismissed)
            next = controller.presentedViewController;
        else if ([controller isKindOfClass:UITabBarController.class]) next = ((UITabBarController *)controller).selectedViewController;
        else if ([controller isKindOfClass:UINavigationController.class]) next = ((UINavigationController *)controller).visibleViewController;
        else for (UIViewController *child in controller.childViewControllers.reverseObjectEnumerator) { if (child.isViewLoaded && child.view.window && !child.view.hidden && child.view.alpha > .01) { next = child; break; } }
        if (!next || next == controller) break;
        controller = next;
    }
    return controller;
}
+ (void)openConversationWithUsername:(NSString *)username inWindow:(UIWindow *)window completion:(void (^)(BOOL, NSString *))completion {
    NSAssert(NSThread.isMainThread, @"Open WeChat conversations on the main queue");
    if (!username.length) { completion(NO, @"未能识别这个会话。"); return; }
    [self openConversation:username inWindow:window completion:completion];
}
// Finds only a native page sheet opened through this plugin. It remains the
// actual presented controller created by WeChat, not a child-navigation wrapper.
+ (UIViewController *)ownedChatPresentationInWindow:(UIWindow *)window {
    UIViewController *chat=WPChatPresentationVisibleChatController(window.rootViewController,window);
    for(UIViewController *controller=chat;controller;controller=controller.parentViewController)
        if([objc_getAssociatedObject(controller,&WPHalfNavigationKey) boolValue] && !controller.isBeingDismissed)return controller;
    // Native page-sheet adapters may connect their controller by view ownership
    // before assigning parentViewController. Follow the visible responder path.
    for(UIView *view=chat.view.superview;view && view!=window;view=view.superview){
        id responder=view.nextResponder;if([responder isKindOfClass:UIViewController.class] && [objc_getAssociatedObject(responder,&WPHalfNavigationKey) boolValue])return responder;
    }
    return nil;
}
+ (UINavigationController *)nativeNavigationInPresentation:(UIViewController *)presentation {
    if([presentation isKindOfClass:UINavigationController.class])return (id)presentation;
    UIViewController *chat=WPChatPresentationVisibleChatController(presentation,presentation.view.window);
    return chat.navigationController;
}
+ (BOOL)invokeNativePageSheetForContact:(id)contact presenter:(UIViewController *)presenter {
    // WCRefine's supplied binary calls this exact native service with CContact
    // (despite the selector's Session name), preserving native keyboard/quote UI.
    Class contextClass=NSClassFromString(@"MMContext");
    id active=WPObjectCall(contextClass,@"activeUserContext",nil,NO);
    id quickReply=active?WPObjectCall(active,@"getService:",NSClassFromString(@"QuickReplyMsgMgr"),YES):nil;
    if(!quickReply)quickReply=WPWeChatService(@"QuickReplyMsgMgr");
    SEL quick=NSSelectorFromString(@"showPageSheetSession:fromViewController:");
    NSMethodSignature *signature=WPSignature(quickReply,quick,2);
    if(signature && WPUnqualifiedType(signature.methodReturnType)[0]=='v' && WPObjectType([signature getArgumentTypeAtIndex:2]) && WPObjectType([signature getArgumentTypeAtIndex:3])){
        @try{NSInvocation *call=[NSInvocation invocationWithMethodSignature:signature];call.target=quickReply;call.selector=quick;
            __unsafe_unretained id c=contact,p=presenter;[call setArgument:&c atIndex:2];[call setArgument:&p atIndex:3];[call invoke];return YES;
        }@catch(__unused NSException *exception){}
    }
    // Also observed in the user's 8.0.79 runtime: v44@0:8@16@24@32B40.
    id logic=active?WPObjectCall(active,@"getService:",NSClassFromString(@"MMMsgLogicManager"),YES):nil;
    if(!logic)logic=WPWeChatService(@"MMMsgLogicManager");
    SEL page=NSSelectorFromString(@"ShowPageSheetLogicControllerByContact:pageSheetDelegate:fromViewController:animated:");
    signature=WPSignature(logic,page,4);
    if(signature && WPUnqualifiedType(signature.methodReturnType)[0]=='v'){
        BOOL typesOk=YES;
        for(NSUInteger index=2;index<5;index++)if(!WPObjectType([signature getArgumentTypeAtIndex:index])){typesOk=NO;break;}
        if(typesOk && strchr("Bc",WPUnqualifiedType([signature getArgumentTypeAtIndex:5])[0])){
            @try{NSInvocation *call=[NSInvocation invocationWithMethodSignature:signature];call.target=logic;call.selector=page;
                __unsafe_unretained id c=contact,p=presenter,delegate=nil;unsigned char animated=1;
                [call setArgument:&c atIndex:2];[call setArgument:&delegate atIndex:3];[call setArgument:&p atIndex:4];[call setArgument:&animated atIndex:5];[call invoke];return YES;
            }@catch(__unused NSException *exception){}
        }
    }
    return NO;
}
+ (void)completeNativeChatRequest:(WPNativeChatRequest *)request success:(BOOL)success message:(NSString *)message {
    if(request.finished)return;request.finished=YES;
    if(objc_getAssociatedObject(request.window,&WPNativeChatRequestKey)==request)objc_setAssociatedObject(request.window,&WPNativeChatRequestKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSArray *callbacks=[request.completions copy];[request.completions removeAllObjects];request.beforeChat=nil;request.beforePresentation=nil;request.createdPresentation=nil;
    if(success)WPChatPresentationNotifyChanged();
    for(void (^completion)(BOOL,NSString *) in callbacks)completion(success,message);
}
+ (void)inspectFullscreenChatRequest:(WPNativeChatRequest *)request {
    if(request.finished)return;
    UIWindow *window=request.window;
    if(!window || window.hidden || !window.rootViewController){[self completeNativeChatRequest:request success:NO message:@"微信页面已关闭，请回到微信后重试。"];return;}
    UIViewController *chat=WPChatPresentationVisibleChatController(window.rootViewController,window);
    NSString *actual=WPChatPresentationUsernameForController(chat);
    if([actual isEqualToString:request.username] && !chat.isBeingPresented && !chat.isBeingDismissed && !chat.navigationController.transitionCoordinator){
        WPChatPresentationActiveUsernameInWindow(window);
        [self completeNativeChatRequest:request success:YES message:@"已打开聊天"];return;
    }
    if(NSProcessInfo.processInfo.systemUptime-request.started>=4.0){
        // Invoking a void private navigation selector is not proof of success.
        // Leave prior native presentations alone when no target became visible.
        [self completeNativeChatRequest:request success:NO message:actual.length?@"当前显示的会话与所选联系人不同，请返回微信主页后重试。":@"未能确认聊天已打开，请返回微信主页后重试。"];return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[self inspectFullscreenChatRequest:request];});
}
+ (UIViewController *)nativePresentationForChat:(UIViewController *)chat request:(WPNativeChatRequest *)request {
    UIViewController *candidate=chat;
    for(UIViewController *controller=chat;controller && controller!=request.window.rootViewController;controller=controller.parentViewController){
        if(controller==request.presenter)break;candidate=controller;
        if(controller.presentingViewController && !controller.parentViewController)return controller;
    }
    if(candidate!=chat || chat.presentingViewController)return candidate;
    for(UIView *view=chat.view.superview;view && view!=request.window;view=view.superview){
        id responder=view.nextResponder;
        if([responder isKindOfClass:UIViewController.class] && responder!=request.presenter && responder!=request.window.rootViewController){candidate=responder;if([responder presentingViewController])return candidate;}
    }
    return candidate;
}
+ (void)inspectNativeChatRequest:(WPNativeChatRequest *)request {
    if(request.finished)return;
    UIWindow *window=request.window;
    if(!window || window.hidden || !window.rootViewController){[self completeNativeChatRequest:request success:NO message:@"微信页面已关闭，请回到微信后重试。"];return;}
    UIViewController *created=request.presenter.presentedViewController?:request.presenter.navigationController.presentedViewController;
    if(!request.createdPresentation && created && created!=request.beforePresentation)request.createdPresentation=created;
    UIViewController *chat=WPChatPresentationVisibleChatController(window.rootViewController,window);
    NSString *actual=WPChatPresentationUsernameForController(chat);
    UIViewController *presentation=(chat && chat!=request.beforeChat)?[self nativePresentationForChat:chat request:request]:nil;
    if(presentation && [actual isEqualToString:request.username] && !presentation.isBeingDismissed){
        // Do not require a UINavigationController: current WeChat versions also
        // use their own page-sheet wrapper with separate native toolbar/content.
        // Recognition and height support are independent capabilities.
        if(!presentation.isBeingPresented && !chat.isBeingPresented){
            objc_setAssociatedObject(presentation,&WPHalfNavigationKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            UINavigationController *navigation=chat.navigationController;
            [WPResizableChatController attachToPresentedController:presentation navigationController:navigation];
            WPChatPresentationActiveUsernameInWindow(window);
            [self completeNativeChatRequest:request success:YES message:@"已打开微信原生聊天"];return;
        }
    }
    NSTimeInterval elapsed=NSProcessInfo.processInfo.systemUptime-request.started;
    if(elapsed>=4.0){
        // A visible native container must not be mislabeled as failure merely
        // because height adjustment is unsupported. Identity still has to match.
        if(presentation && [actual isEqualToString:request.username]){
            objc_setAssociatedObject(presentation,&WPHalfNavigationKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [self completeNativeChatRequest:request success:YES message:@"已打开微信原生聊天"];
        }else {
            NSString *failure=actual.length?@"当前显示的会话与所选联系人不同，已返回原页面，请重试。":@"未能确认原生聊天已打开，请重试或使用全屏打开。";
            UIViewController *created=request.createdPresentation;
            if(created && created!=request.beforePresentation && created.presentingViewController && !created.isBeingDismissed){
                // Roll back only the presentation first created by this request.
                // Never dismiss a modal that was present before the user tapped.
                [created dismissViewControllerAnimated:NO completion:^{WPChatPresentationNotifyChanged();[self completeNativeChatRequest:request success:NO message:failure];}];
            }else [self completeNativeChatRequest:request success:NO message:failure];
        }
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.10*NSEC_PER_SEC)),dispatch_get_main_queue(),^{[self inspectNativeChatRequest:request];});
}
+ (void)openConversationWithUsername:(NSString *)username inWindow:(UIWindow *)window presentationMode:(NSInteger)mode completion:(void (^)(BOOL,NSString *))completion {
    NSAssert(NSThread.isMainThread,@"Open native chat on main");
    if(![username isKindOfClass:NSString.class] || !username.length || username.length>256){completion(NO,@"未能识别这个会话。");return;}
    WPNativeChatRequest *pending=objc_getAssociatedObject(window,&WPNativeChatRequestKey);
    if(pending && !pending.finished){
        if([pending.username isEqualToString:username] && pending.completions.count<8){[pending.completions addObject:[completion copy]];return;}
        completion(NO,@"聊天正在打开，请稍候再切换。");return;
    }
    UIViewController *owned=[self ownedChatPresentationInWindow:window];
    if(mode!=0 && mode!=3){
        if(owned && owned.presentingViewController){[[WPResizableChatController coordinatorForController:owned] endHeightAdjustment];[owned dismissViewControllerAnimated:YES completion:^{WPChatPresentationNotifyChanged();[self openConversationWithUsername:username inWindow:window completion:completion];}];}
        else [self openConversationWithUsername:username inWindow:window completion:completion];return;
    }
    if(!window.rootViewController){completion(NO,@"未找到微信主窗口，请回到微信主页后重试。");return;}
    if(owned){
        UIViewController *current=WPChatPresentationVisibleChatController(owned,window);
        if([WPChatPresentationUsernameForController(current) isEqualToString:username]){WPChatPresentationNotifyChanged();completion(YES,@"已经在这个聊天里了");return;}
        if(!owned.presentingViewController || owned.isBeingPresented || owned.isBeingDismissed || current.presentedViewController){completion(NO,@"请先关闭当前聊天窗口后再切换。");return;}
        // Reopen through the native page-sheet API. Pushing an ordinary chat into
        // its private navigation stack bypasses native keyboard/quote setup.
        [[WPResizableChatController coordinatorForController:owned] endHeightAdjustment];
        [owned dismissViewControllerAnimated:YES completion:^{WPChatPresentationNotifyChanged();[self openConversationWithUsername:username inWindow:window presentationMode:mode completion:completion];}];return;
    }
    UIViewController *presenter=[self visibleController:window.rootViewController];
    id contact=WPContactForUsername(WPContactService(),username);Class contactClass=NSClassFromString(@"CContact");
    if(!contactClass || ![contact isKindOfClass:contactClass]){completion(NO,@"未找到这个会话的联系人，请返回微信主页后重试。");return;}
    if(!presenter || presenter.isBeingPresented || presenter.isBeingDismissed || presenter.transitionCoordinator || presenter.presentedViewController){completion(NO,@"当前页面正在切换，请稍后再打开聊天。");return;}
    WPNativeChatRequest *request=[WPNativeChatRequest new];request.window=window;request.presenter=presenter;request.username=username;request.started=NSProcessInfo.processInfo.systemUptime;
    request.beforeChat=WPChatPresentationVisibleChatController(window.rootViewController,window);request.completions=[NSMutableArray arrayWithObject:[completion copy]];
    request.beforePresentation=presenter.presentedViewController?:presenter.navigationController.presentedViewController;
    objc_setAssociatedObject(window,&WPNativeChatRequestKey,request,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if(![self invokeNativePageSheetForContact:contact presenter:presenter]){[self completeNativeChatRequest:request success:NO message:@"当前微信版本的原生小窗接口待适配，请切换全屏打开。"];return;}
    [self inspectNativeChatRequest:request];
}
+ (void)openConversation:(NSString *)username inWindow:(UIWindow *)window completion:(void (^)(BOOL, NSString *))completion {
    if (!window.rootViewController) { completion(NO, @"未找到微信主窗口，请回到微信主页后重试。"); return; }
    // Match page-sheet single-flight behavior. Only one native navigation per host window.
    WPNativeChatRequest *pending=objc_getAssociatedObject(window,&WPNativeChatRequestKey);
    if(pending && !pending.finished){
        if([pending.username isEqualToString:username] && pending.completions.count<8){[pending.completions addObject:[completion copy]];return;}
        completion(NO,@"聊天正在打开，请稍候再切换。");return;
    }
    id manager = WPContactService();
    id contact = WPContactForUsername(manager, username);
    Class contactClass = NSClassFromString(@"CContact");
    if (!contactClass || ![contact isKindOfClass:contactClass] || ![WPUsernameForValue(contact) isEqualToString:username]) {
        completion(NO, @"未找到这个会话的联系人，当前微信版本可能需要适配。"); return;
    }
    UIViewController *visible = [self visibleController:window.rootViewController];
    UINavigationController *navigation = [visible isKindOfClass:UINavigationController.class] ? (id)visible : visible.navigationController;
    // Historical WeChat builds wrap their tab/navigation stack in a custom
    // container. Accept its documented class getter only for this same window,
    // and never use it to push underneath a currently presented modal.
    if (!navigation && !window.rootViewController.presentedViewController) {
        id candidate = WPObjectCall(NSClassFromString(@"CAppViewControllerManager"), @"getCurrentNavigationController", nil, NO);
        if ([candidate isKindOfClass:UINavigationController.class] && ((UINavigationController *)candidate).view.window == window)
            navigation = candidate;
    }
    if (!navigation || navigation.view.window != window || navigation.transitionCoordinator) {
        completion(NO, @"当前页面暂不能跳转，请关闭弹窗或返回微信主页后重试。"); return;
    }
    if ([WPContactString(navigation.topViewController, @"getCurrentChatName") isEqualToString:username]) {
        WPChatPresentationNotifyChanged();completion(YES, @"已经在这个聊天里了"); return;
    }
    id logic = WPWeChatService(@"MMMsgLogicManager");
    SEL selector = NSSelectorFromString(@"PushOtherBaseMsgControllerByContact:navigationController:animated:");
    NSMethodSignature *signature = WPSignature(logic, selector, 3);
    if (!signature || WPUnqualifiedType(signature.methodReturnType)[0] != 'v' ||
        !WPObjectType([signature getArgumentTypeAtIndex:2]) || !WPObjectType([signature getArgumentTypeAtIndex:3])) {
        completion(NO, @"当前微信版本的聊天跳转接口尚待适配。"); return;
    }
    const char *boolType = WPUnqualifiedType([signature getArgumentTypeAtIndex:4]);
    if (boolType[0] != 'B' && boolType[0] != 'c') {
        completion(NO, @"当前微信版本的聊天跳转参数不兼容，暂未执行跳转。"); return;
    }
    WPNativeChatRequest *request=[WPNativeChatRequest new];request.window=window;request.username=username;request.started=NSProcessInfo.processInfo.systemUptime;
    request.completions=[NSMutableArray arrayWithObject:[completion copy]];
    objc_setAssociatedObject(window,&WPNativeChatRequestKey,request,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    @try {
        NSInvocation *invocation=[NSInvocation invocationWithMethodSignature:signature];
        invocation.target = logic; invocation.selector = selector;
        __unsafe_unretained id contactArgument = contact, navigationArgument = navigation;
        unsigned char animated = 1;
        [invocation setArgument:&contactArgument atIndex:2];
        [invocation setArgument:&navigationArgument atIndex:3];
        [invocation setArgument:&animated atIndex:4];
        [invocation invoke];
        [self inspectFullscreenChatRequest:request];
    } @catch (__unused NSException *exception) {
        [self completeNativeChatRequest:request success:NO message:@"此版本的聊天跳转未成功，请返回微信主页后重试。"];
    }
}


@end

@interface WPPartnerPickerController () <UISearchResultsUpdating, UISearchControllerDelegate>
@property (nonatomic, strong) NSArray<NSDictionary<NSString *, NSString *> *> *contacts;
@property (nonatomic, strong) NSArray<NSDictionary<NSString *, NSString *> *> *filtered;
@property (nonatomic, strong) UISearchController *contactSearch;
@property (nonatomic, copy) NSString *loadError;
@property (nonatomic) NSUInteger loadGeneration;
@property (nonatomic) NSUInteger sourceIndex;
@property (nonatomic, strong) NSArray *loadingSources;
@property (nonatomic, strong) id loadingManager;
@property (nonatomic, copy) NSString *selfUsername;
@property (nonatomic, strong) NSMutableArray<NSDictionary<NSString *, NSString *> *> *loadedContacts;
@property (nonatomic, strong) NSMutableSet<NSString *> *seenUsernames;
@property (nonatomic) BOOL selectionCommitted;
@property (nonatomic) BOOL returnAfterSearchDismissal;
@end

@implementation WPPartnerPickerController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.pickerTitle.length?self.pickerTitle:@"选择联系人";
    self.contacts = @[]; self.filtered = @[];
    self.contactSearch = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.contactSearch.obscuresBackgroundDuringPresentation = NO;
    self.contactSearch.searchResultsUpdater = self;
    self.contactSearch.delegate = self;
    self.contactSearch.searchBar.placeholder = @"搜索备注、昵称或微信标识";
    self.navigationItem.searchController = self.contactSearch;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"重新加载" style:UIBarButtonItemStylePlain target:self action:@selector(loadContacts)];
    dispatch_async(dispatch_get_main_queue(), ^{ [self loadContacts]; });
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (self.isMovingFromParentViewController || self.isBeingDismissed) [self cancelLoading];
}
- (void)cancelLoading {
    self.loadGeneration++;
    self.loadingSources = nil; self.loadingManager = nil;
    self.loadedContacts = nil; self.seenUsernames = nil;
}
- (void)loadContacts {
    NSAssert(NSThread.isMainThread, @"Read WeChat contacts on its main queue");
    if(self.selectionCommitted)return;
    [self cancelLoading];
    self.loadError = nil; self.contacts = @[]; self.filtered = @[];
    self.navigationItem.prompt = @"正在加载微信联系人…";
    [self updateSearchResultsForSearchController:self.contactSearch];
    id manager = WPContactService();
    if (!manager) {
        self.loadError = @"暂未取得当前登录账号的联系人服务。请回到微信首页后重试。";
        self.navigationItem.prompt = nil;
        [self updateSearchResultsForSearchController:self.contactSearch]; return;
    }
    NSMutableArray *sources = [NSMutableArray new];
    id cached = WPObjectCall(manager, @"getAllContactUserNameFromCache", nil, NO);
    NSArray *cachedNames = [cached isKindOfClass:NSDictionary.class] ? [cached allKeys] : WPContactCollection(cached);
    if (cachedNames.count) [sources addObjectsFromArray:cachedNames];
    id sessions = WPWeChatService(@"MMNewSessionMgr");
    NSArray *recent = WPContactCollection(WPObjectCall(sessions, @"GetUserNamesOnSessionList", nil, NO));
    if (recent.count) [sources addObjectsFromArray:recent];
    NSArray *friends = WPOutputContactList(manager, @"getAllContactList:listType:", YES);
    if (friends.count) [sources addObjectsFromArray:friends];
    if (!sources.count) {
        NSArray *list = WPContactList(manager);
        if (list.count) [sources addObjectsFromArray:list];
    }
    // The all-name API can include thousands of historical/stranger records.
    // Existing friend/cache/session sources are sufficient for normal selection.
    if (!sources.count) {
        id all = WPObjectCall(manager, @"getAllContactUserName", nil, NO);
        NSArray *allNames = [all isKindOfClass:NSDictionary.class] ? [all allKeys] : WPContactCollection(all);
        if (allNames.count) [sources addObjectsFromArray:allNames];
        if (!sources.count) {
            NSArray *output = WPOutputContactList(manager, @"getAllUserName:", NO);
            if (output.count) [sources addObjectsFromArray:output];
        }
    }
    if (!sources.count) {
        id navigation = WPObjectCall(NSClassFromString(@"CAppViewControllerManager"), @"getCurrentNavigationController", nil, NO);
        if ([navigation isKindOfClass:UINavigationController.class]) {
            NSString *current = WPContactString(((UINavigationController *)navigation).topViewController, @"getCurrentChatName");
            if (current.length) [sources addObject:current];
        }
    }
    self.loadingManager = manager;
    self.selfUsername = WPUsernameForValue(WPObjectCall(manager, @"getSelfContact", nil, NO));
    self.loadingSources = [sources copy]; self.sourceIndex = 0;
    self.loadedContacts = [NSMutableArray new]; self.seenUsernames = [NSMutableSet new];
    NSUInteger generation = self.loadGeneration;
    dispatch_async(dispatch_get_main_queue(), ^{ [self loadNextBatch:generation]; });
}
- (void)loadNextBatch:(NSUInteger)generation {
    if (generation != self.loadGeneration) return;
    NSAssert(NSThread.isMainThread, @"Read WeChat contacts on its main queue");
    CFTimeInterval deadline = CFAbsoluteTimeGetCurrent() + .008;
    NSUInteger count = 0;
    Class contactClass = NSClassFromString(@"CContact");
    while (self.sourceIndex < self.loadingSources.count && count < 40) {
        @autoreleasepool {
            id value = self.loadingSources[self.sourceIndex++]; count++;
            NSString *username = WPUsernameForValue(value);
            if (username.length && ![self.seenUsernames containsObject:username] &&
                !WPContactSelectionError(username, nil, self.selfUsername)) {
                id contact = [value isKindOfClass:contactClass] ? value : WPContactForUsername(self.loadingManager, username);
                if (contactClass && [contact isKindOfClass:contactClass] &&
                    [WPUsernameForValue(contact) isEqualToString:username] &&
                    !WPContactSelectionError(username, contact, self.selfUsername)) {
                    [self.seenUsernames addObject:username];
                    NSString *name = WPNameForContact(contact), *nickname = WPContactString(contact, @"m_nsNickName");
                    [self.loadedContacts addObject:@{@"username":username, @"name":name.length ? name : username,
                        @"search":[NSString stringWithFormat:@"%@ %@ %@", name, nickname, username]}];
                }
            }
        }
        if (CFAbsoluteTimeGetCurrent() >= deadline) break;
    }
    BOOL finished = self.sourceIndex >= self.loadingSources.count;
    self.contacts = [self.loadedContacts copy];
    if (finished) {
        self.contacts = [self.contacts sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [a[@"name"] localizedStandardCompare:b[@"name"]];
        }];
        self.navigationItem.prompt = nil;
        if (!self.contacts.count) self.loadError = @"暂未读取到微信好友。请先打开微信通讯录，再点重新加载。";
        self.loadingSources = nil; self.loadingManager = nil;
        self.loadedContacts = nil; self.seenUsernames = nil;
    }
    [self updateSearchResultsForSearchController:self.contactSearch];
    if (!finished) dispatch_async(dispatch_get_main_queue(), ^{ [self loadNextBatch:generation]; });
}
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *query = [searchController.searchBar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    self.filtered = query.length ? [self.contacts filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *contact, NSDictionary *bindings) {
        return [contact[@"search"] rangeOfString:query options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location != NSNotFound;
    }]] : self.contacts;
    UILabel *message = [UILabel new];
    message.numberOfLines = 0; message.textAlignment = NSTextAlignmentCenter;
    message.font = [UIFont systemFontOfSize:15]; message.textColor = UIColor.secondaryLabelColor;
    message.text = self.filtered.count ? nil : (self.loadError ?: (self.loadingSources ? @"正在加载微信联系人…" : @"没有匹配的联系人"));
    UIView *empty = [[UIView alloc] initWithFrame:self.tableView.bounds];
    message.frame = CGRectInset(empty.bounds, 28, 28); message.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [empty addSubview:message]; self.tableView.backgroundView = self.filtered.count ? nil : empty;
    [self.tableView reloadData];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.filtered.count; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return self.contacts.count ? @"选择联系人用于当前功能，不会发送微信消息。" : nil;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"PartnerContact"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"PartnerContact"];
    NSDictionary *contact = self.filtered[indexPath.row];
    cell.textLabel.text = contact[@"name"]; cell.detailTextLabel.text = contact[@"username"];
    cell.accessoryType = UITableViewCellAccessoryNone;
    return cell;
}
- (void)returnToSettingsAfterSelection {
    if (self.navigationController.topViewController == self)
        [self.navigationController popViewControllerAnimated:YES];
}
- (void)didDismissSearchController:(UISearchController *)searchController {
    if (searchController != self.contactSearch || !self.returnAfterSearchDismissal) return;
    self.returnAfterSearchDismissal = NO;
    [self returnToSettingsAfterSelection];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.selectionCommitted || indexPath.row < 0 || (NSUInteger)indexPath.row >= self.filtered.count) return;
    NSDictionary *contact = self.filtered[indexPath.row];
    self.selectionCommitted = YES;
    [self cancelLoading];
    if(self.selectionHandler)self.selectionHandler(contact[@"username"],contact[@"name"]);
    if (self.contactSearch.isActive) {
        // Search dismissal and navigation pop are separate UIKit transitions.
        // Wait for the former before returning to settings.
        self.returnAfterSearchDismissal = YES;
        self.contactSearch.active = NO;
    } else {
        [self returnToSettingsAfterSelection];
    }
}
@end
