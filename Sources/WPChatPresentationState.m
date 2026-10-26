#import "WPChatPresentationState.h"
#import <objc/runtime.h>

NSNotificationName const WPChatPresentationDidChangeNotification=@"WPChatPresentationDidChangeNotification";
static const char *WPChatType(const char *type){while(type && *type && strchr("rnNoORV",*type))type++;return type;}
static id WPChatReadObject(id target,NSString *name){
    SEL selector=NSSelectorFromString(name);if(![target respondsToSelector:selector])return nil;
    @try{NSMethodSignature *signature=[target methodSignatureForSelector:selector];if(signature.numberOfArguments!=2 || WPChatType(signature.methodReturnType)[0]!='@')return nil;
        NSInvocation *call=[NSInvocation invocationWithMethodSignature:signature];call.target=target;call.selector=selector;[call invoke];__unsafe_unretained id result=nil;[call getReturnValue:&result];return result;
    }@catch(__unused NSException *exception){return nil;}
}
void WPChatPresentationNotifyChanged(void){
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{WPChatPresentationNotifyChanged();});return;}
    [NSNotificationCenter.defaultCenter postNotificationName:WPChatPresentationDidChangeNotification object:nil];
}
static void WPChatObserveClass(Class cls){
    static NSMutableSet<NSString *> *observed;static dispatch_once_t once;dispatch_once(&once,^{observed=[NSMutableSet new];});
    NSString *className=NSStringFromClass(cls);if(!cls || [observed containsObject:className])return;[observed addObject:className];
    // Observe only the actual native chat class encountered on screen. Never
    // exchange UIViewController's global lifecycle or change its responder path.
    for(NSString *name in @[@"viewDidAppear:",@"viewDidDisappear:"]){
        SEL selector=NSSelectorFromString(name);Method method=class_getInstanceMethod(cls,selector);if(!method)continue;
        NSMethodSignature *signature=[NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
        if(signature.numberOfArguments!=3 || WPChatType(signature.methodReturnType)[0]!='v' || !strchr("Bc",WPChatType([signature getArgumentTypeAtIndex:2])[0]))continue;
        IMP original=method_getImplementation(method);IMP replacement=imp_implementationWithBlock(^(UIViewController *controller,BOOL animated){
            ((void(*)(id,SEL,BOOL))original)(controller,selector,animated);
            dispatch_async(dispatch_get_main_queue(),^{WPChatPresentationNotifyChanged();});
        });
        if(!class_addMethod(cls,selector,replacement,method_getTypeEncoding(method)))class_replaceMethod(cls,selector,replacement,method_getTypeEncoding(method));
    }
}
static BOOL WPChatUsableWindow(UIWindow *window){
    if(!window || window.hidden || window.alpha<.01 || !window.rootViewController || CGRectIsEmpty(window.bounds))return NO;
    NSString *name=NSStringFromClass(window.class);
    for(NSString *part in @[@"WPOverlay",@"UITextEffects",@"UIRemoteKeyboard",@"KeyboardWindow",@"TextEffects",@"SnapshotWindow",@"StatusBar",@"TextSelection",@"Callout",@"ContextMenu",@"DanmakuOverlayWindow",@"WCRQuickChatWindow",@"WCRSuperFloat",@"WCRFloating"])
        if([name containsString:part])return NO;
    return YES;
}
static BOOL WPChatVisibleView(UIView *view, UIWindow *window){
    if(!view || view.window!=window || CGRectIsEmpty(view.bounds))return NO;
    for(UIView *parent=view;parent && parent!=window;parent=parent.superview)if(parent.hidden || parent.alpha<.01)return NO;
    CGRect frame=[view convertRect:view.bounds toView:window];return CGRectIntersectsRect(frame,window.bounds);
}
NSString *WPChatPresentationUsernameForController(UIViewController *controller){
    if(!controller)return nil;
    id name=WPChatReadObject(controller,@"getCurrentChatName");
    if([name isKindOfClass:NSString.class] && [name length] && [name length]<=256)return name;
    // Some native page-sheet content classes expose their CContact rather than
    // getCurrentChatName. Read only explicitly typed contact ivars of a native
    // chat controller; a profile/settings controller must never count as chat.
    BOOL chatClass=NO;
    for(Class cls=controller.class;cls && cls!=UIViewController.class;cls=class_getSuperclass(cls)){
        NSString *n=NSStringFromClass(cls);
        if([n containsString:@"BaseMsg"] || [n containsString:@"ChatContent"] || [n containsString:@"QuickReply"]){chatClass=YES;break;}
    }
    if(!chatClass)return nil;
    Class contactClass=NSClassFromString(@"CContact");if(!contactClass)return nil;
    for(Class cls=controller.class;cls && cls!=UIViewController.class;cls=class_getSuperclass(cls)){
        unsigned count=0;Ivar *ivars=class_copyIvarList(cls,&count);NSString *found=nil;
        for(unsigned i=0;i<count && !found;i++){
            const char *type=ivar_getTypeEncoding(ivars[i]);const char *field=ivar_getName(ivars[i]);
            if(!type || !field || !strstr(type,"CContact") || ![[NSString stringWithUTF8String:field].lowercaseString containsString:@"contact"])continue;
            id contact=object_getIvar(controller,ivars[i]);if(![contact isKindOfClass:contactClass])continue;
            id value=WPChatReadObject(contact,@"m_nsUsrName");
            if([value isKindOfClass:NSString.class] && [value length] && [value length]<=256)found=value;
        }
        free(ivars);if(found)return found;
    }return nil;
}
static void WPChatCollectOwnedControllers(UIView *view,UIViewController *owner,UIWindow *window,NSMutableArray *result,NSUInteger *budget,NSUInteger depth){
    if(!view || !*budget || depth>10 || !WPChatVisibleView(view,window))return;(*budget)--;
    // UIKit can have a native content controller in the responder chain before
    // the private page-sheet adapter completes addChildViewController:.
    UIResponder *responder=view.nextResponder;
    if([responder isKindOfClass:UIViewController.class] && responder!=owner){
        UIViewController *child=(id)responder;
        if(![result containsObject:child])[result addObject:child];return;
    }
    for(UIView *child in view.subviews.reverseObjectEnumerator)WPChatCollectOwnedControllers(child,owner,window,result,budget,depth+1);
}
static UIViewController *WPChatFindVisible(UIViewController *controller,UIWindow *window,NSHashTable *visited,NSUInteger depth){
    if(!controller || depth>24 || [visited containsObject:controller] || controller.isBeingDismissed)return nil;
    [visited addObject:controller];
    // UIKit removes a full-screen presenter's view from its window. Its visible
    // presented content must be checked before rejecting the detached presenter.
    if(controller.presentedViewController && !controller.presentedViewController.isBeingDismissed)
        return WPChatFindVisible(controller.presentedViewController,window,visited,depth+1);
    if(!controller.isViewLoaded || !WPChatVisibleView(controller.view,window))return nil;
    if([controller isKindOfClass:UINavigationController.class])return WPChatFindVisible(((UINavigationController *)controller).visibleViewController,window,visited,depth+1);
    if([controller isKindOfClass:UITabBarController.class])return WPChatFindVisible(((UITabBarController *)controller).selectedViewController,window,visited,depth+1);
    if([controller isKindOfClass:UISplitViewController.class])return WPChatFindVisible(((UISplitViewController *)controller).viewControllers.lastObject,window,visited,depth+1);
    NSMutableArray<UIViewController *> *children=[NSMutableArray new];NSUInteger budget=180;
    WPChatCollectOwnedControllers(controller.view,controller,window,children,&budget,0);
    for(UIViewController *child in controller.childViewControllers.reverseObjectEnumerator)if(![children containsObject:child])[children addObject:child];
    for(UIViewController *child in children){
        if(!child.isViewLoaded || !WPChatVisibleView(child.view,window))continue;
        UIViewController *chat=WPChatFindVisible(child,window,visited,depth+1);if(chat)return chat;
        // A foreground content controller covering this container blocks an
        // older chat underneath. Small native header/toolbars do not.
        CGRect frame=[child.view convertRect:child.view.bounds toView:controller.view];
        CGRect overlap=CGRectIntersection(frame,controller.view.bounds);
        CGFloat parentArea=CGRectGetWidth(controller.view.bounds)*CGRectGetHeight(controller.view.bounds);
        if(parentArea>0 && !CGRectIsNull(overlap) && CGRectGetWidth(overlap)*CGRectGetHeight(overlap)>.80*parentArea)return nil;
    }
    return WPChatPresentationUsernameForController(controller).length?controller:nil;
}
UIViewController *WPChatPresentationVisibleChatController(UIViewController *container,UIWindow *window){
    if(!NSThread.isMainThread || !window || !container)return nil;
    return WPChatFindVisible(container,window,[NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality|NSPointerFunctionsStrongMemory],0);
}
NSString *WPChatPresentationActiveUsernameInWindow(UIWindow *window){
    if(!NSThread.isMainThread || !WPChatUsableWindow(window))return nil;
    UIViewController *controller=WPChatPresentationVisibleChatController(window.rootViewController,window);
    NSString *name=WPChatPresentationUsernameForController(controller);
    if(name.length)WPChatObserveClass(controller.class);return name;
}
BOOL WPChatConversationIsVisible(NSString *username){
    if(!NSThread.isMainThread || ![username isKindOfClass:NSString.class] || !username.length)return NO;
    UIWindow *front=nil;
    for(UIScene *scene in UIApplication.sharedApplication.connectedScenes){
        if(![scene isKindOfClass:UIWindowScene.class] || scene.activationState!=UISceneActivationStateForegroundActive)continue;
        for(UIWindow *window in ((UIWindowScene *)scene).windows){
            if(!WPChatUsableWindow(window))continue;
            if(!front || window.windowLevel>front.windowLevel || (window.windowLevel==front.windowLevel && window.isKeyWindow && !front.isKeyWindow))front=window;
        }
    }
    if(UIApplication.sharedApplication.connectedScenes.count==0 && UIApplication.sharedApplication.applicationState!=UIApplicationStateBackground){
        for(UIWindow *window in UIApplication.sharedApplication.windows){
            if(!WPChatUsableWindow(window))continue;
            if(!front || window.windowLevel>front.windowLevel || (window.windowLevel==front.windowLevel && window.isKeyWindow && !front.isKeyWindow))front=window;
        }
    }
    return [WPChatPresentationActiveUsernameInWindow(front) isEqualToString:username];
}
