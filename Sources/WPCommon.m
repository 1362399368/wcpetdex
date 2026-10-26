#import "WPCommon.h"
#import "WPQuickChat.h"
#import "WPMessageBarrageSource.h"
#import "WPActionAdapter.h"
#import "WPBackendConfiguration.h"
#import <dlfcn.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <ImageIO/ImageIO.h>
#import "WPEdition.h"

NSString * const WPSelectedPetDidChangeNotification = @"WeChatPet.SelectedPetDidChange";
NSString * const WPSettingsDidChangeNotification = @"WeChatPet.SettingsDidChange";

NSBundle *WPResourceBundle(void) {
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"WeChatPet" withExtension:@"bundle"];
    if (url) return [NSBundle bundleWithURL:url];
    Dl_info info;
    if (dladdr((const void *)&WPResourceBundle, &info) && info.dli_fname) {
        NSString *dir = [[NSString stringWithUTF8String:info.dli_fname] stringByDeletingLastPathComponent];
        for (NSString *candidate in @[[dir stringByAppendingPathComponent:@"WeChatPet.bundle"],
                                      [[dir stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"WeChatPet.bundle"]]) {
            NSBundle *bundle = [NSBundle bundleWithPath:candidate];
            if (bundle) return bundle;
        }
    }
    return [NSBundle mainBundle];
}

NSString *WPDefaultPetDirectory(void) {
    return [WPResourceBundle().resourcePath stringByAppendingPathComponent:(WP_EDITION_ARIA ? @"AriaPet" : @"DefaultPet")];
}

NSUserDefaults *WPPreferences(void) {
    static NSUserDefaults *defaults;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        defaults = [[NSUserDefaults alloc] initWithSuiteName:@"dev.zhour.wechatpet"];
        NSMutableDictionary *registered=[@{@"petSize": @88, @"petOpacity": @1.0,@"menuScale":@1.0, @"enabled": @YES, @"autoPeek": @YES, @"quickChatEnabled": @NO, @"quickChatFlash": @YES,
            @"unreadAvatarEnabled":@YES,@"unreadAvatarOffsetX":@0,@"unreadAvatarOffsetY":@0,
            @"interactionBadgeOffsetX":@0,@"interactionBadgeOffsetY":@0} mutableCopy];
        NSString *backend=WPDefaultCoupleURLString();if(backend.length)registered[@"coupleURL"]=backend;
        [defaults registerDefaults:registered];
    });
    return defaults;
}

NSString *WPDataDirectory(void) {
    NSString *path = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"WeChatPet"];
    [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    return path;
}

static NSString *WPSelectionFile(void){return [WPDataDirectory() stringByAppendingPathComponent:@"selected-pet.json"];}
static NSString *WPDownloadedRoot(void){
    NSString *support=NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,NSUserDomainMask,YES).firstObject;
    return [support stringByAppendingPathComponent:@"WePet/Pets"];
}
static NSString *WPReferenceForPath(NSString *path){
    if(!path.length)return nil;
    NSString *clean=path.stringByStandardizingPath;
    NSString *download=WPDownloadedRoot().stringByStandardizingPath;
    NSString *import=[WPDataDirectory() stringByAppendingPathComponent:@"ImportedPets"].stringByStandardizingPath;
    if([clean hasPrefix:[download stringByAppendingString:@"/"]])return [@"downloaded:" stringByAppendingString:clean.lastPathComponent];
    if([clean hasPrefix:[import stringByAppendingString:@"/"]])return [@"imported:" stringByAppendingString:clean.lastPathComponent];
    if([clean.lastPathComponent isEqual:@"DefaultPet"])return @"bundle:DefaultPet";
    if([clean.lastPathComponent isEqual:@"AriaPet"])return @"bundle:AriaPet";
    // A saved absolute path from an older app container can be rebased by
    // its stable asset directory without changing the user's selection.
    if([clean containsString:@"/WePet/Pets/"])return [@"downloaded:" stringByAppendingString:clean.lastPathComponent];
    if([clean containsString:@"/ImportedPets/"])return [@"imported:" stringByAppendingString:clean.lastPathComponent];
    return nil;
}
NSString *WPSelectedPetReference(void){
    NSData *data=[NSData dataWithContentsOfFile:WPSelectionFile()];
    id record=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
    NSString *reference=[record isKindOfClass:NSDictionary.class] && [record[@"reference"] isKindOfClass:NSString.class]?record[@"reference"]:nil;
    if(!reference.length)reference=[WPPreferences() stringForKey:@"selectedPetReference"];
    if(reference.length)return reference;
    NSString *legacy=[WPPreferences() stringForKey:@"selectedPetDirectory"];
    reference=WPReferenceForPath(legacy);
    if(reference.length)[WPPreferences() setObject:reference forKey:@"selectedPetReference"];
    return reference;
}
NSString *WPSelectedPetDirectory(void){
    NSString *reference=WPSelectedPetReference();
    NSArray *parts=[reference componentsSeparatedByString:@":"];
    if(parts.count==2 && [parts[1] isEqual:((NSString *)parts[1]).lastPathComponent] && [parts[1] length]){
        if([parts[0] isEqual:@"downloaded"])return [WPDownloadedRoot() stringByAppendingPathComponent:parts[1]];
        if([parts[0] isEqual:@"imported"])return [[WPDataDirectory() stringByAppendingPathComponent:@"ImportedPets"] stringByAppendingPathComponent:parts[1]];
        if([parts[0] isEqual:@"bundle"] && ([@"DefaultPet" isEqual:parts[1]] || [@"AriaPet" isEqual:parts[1]]))return [WPResourceBundle().resourcePath stringByAppendingPathComponent:parts[1]];
    }
    return [WPPreferences() stringForKey:@"selectedPetDirectory"];
}
BOOL WPSelectPetDirectory(NSURL *directory){
    NSString *reference=WPReferenceForPath(directory.path);
    if(!reference.length)return NO;
    NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"version":@1,@"reference":reference} options:0 error:nil];
    if(![data writeToFile:WPSelectionFile() options:NSDataWritingAtomic error:nil])return NO;
    [WPPreferences() setObject:reference forKey:@"selectedPetReference"];
    [WPPreferences() setObject:directory.path forKey:@"selectedPetDirectory"];
    return YES;
}
void WPResetSelectedPet(void){
    [[NSFileManager defaultManager] removeItemAtPath:WPSelectionFile() error:nil];
    [WPPreferences() removeObjectForKey:@"selectedPetReference"];
    [WPPreferences() removeObjectForKey:@"selectedPetDirectory"];
}

static id WPDiagnosticObject(id target,NSString *selectorName,id argument,BOOL hasArgument){
    if(!target)return nil;SEL selector=NSSelectorFromString(selectorName);
    NSMethodSignature *signature=nil;
    @try{signature=[target methodSignatureForSelector:selector];}@catch(__unused NSException *exception){return nil;}
    if(!signature)return nil;
    if(signature.numberOfArguments!=(hasArgument?3:2) || signature.methodReturnType[0]!='@')return nil;
    if(hasArgument && !strchr("@#",[signature getArgumentTypeAtIndex:2][0]))return nil;
    @try{
        // Some compatibility plugins register a compact encoding ("@@:").
        // The verified object ABI is the same even without frame offsets.
        if(hasArgument)return ((id(*)(id,SEL,id))objc_msgSend)(target,selector,argument);
        return ((id(*)(id,SEL))objc_msgSend)(target,selector);
    }@catch(__unused NSException *exception){return nil;}
}
static NSNumber *WPContextFlag(id context,NSString *name){
    SEL selector=NSSelectorFromString(name);Method method=context?class_getInstanceMethod(object_getClass(context),selector):NULL;
    if(!method)return nil;NSMethodSignature *signature=[NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    if(signature.numberOfArguments!=2 || !strchr("Bc",signature.methodReturnType[0]))return nil;
    @try{return @(((BOOL(*)(id,SEL))objc_msgSend)(context,selector));}@catch(__unused NSException *exception){return nil;}
}
static BOOL WPUsableWeChatContext(id context){
    return context && ![WPContextFlag(context,@"isRootContext") boolValue] && ![WPContextFlag(context,@"isInvalidContext") boolValue];
}
id WPWeChatService(NSString *className){
    Class serviceClass=NSClassFromString(className);if(!serviceClass)return nil;
    Class contextClass=NSClassFromString(@"MMContext");
    id current=WPDiagnosticObject(contextClass,@"currentContext",nil,NO);
    id active=WPDiagnosticObject(contextClass,@"activeUserContext",nil,NO);
    // Overlay callbacks run outside WeChat's task-local user context. In that
    // case currentContext is the root context: getService creates empty managers
    // there, even though another context owns the logged-in account's data.
    for(id context in @[current ?: NSNull.null,active ?: NSNull.null]){
        if(context==NSNull.null || !WPUsableWeChatContext(context))continue;
        id service=WPDiagnosticObject(context,@"getService:",serviceClass,YES);if(service)return service;
        id center=WPDiagnosticObject(context,@"serviceCenter",nil,NO);
        service=WPDiagnosticObject(center,@"getService:",serviceClass,YES);if(service)return service;
    }
    id center=WPDiagnosticObject(NSClassFromString(@"MMServiceCenter"),@"defaultCenter",nil,NO);
    if(!WPUsableWeChatContext(center))return nil;
    return WPDiagnosticObject(center,@"getService:",serviceClass,YES);
}
#ifdef WP_RUNTIME_DIAGNOSTIC_URL
static NSDictionary *WPDiagnosticCollection(id value){
    NSUInteger count=0;if([value isKindOfClass:NSArray.class] || [value isKindOfClass:NSSet.class] || [value isKindOfClass:NSDictionary.class])count=[value count];
    id first=[value isKindOfClass:NSArray.class]?[value firstObject]:([value isKindOfClass:NSSet.class]?[value anyObject]:nil);
    return @{@"class":value?NSStringFromClass([value class]):@"nil",@"count":@(count),@"elementClass":first?NSStringFromClass([first class]):@"nil"};
}
#endif

NSDictionary *WPRuntimeDiagnostics(void) {
    NSMutableDictionary *result=[@{@"pluginVersion":WPPluginVersion(),@"edition":WPEditionName(),@"iOS":UIDevice.currentDevice.systemVersion,
        @"wechatVersion":[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"",
        @"wechatBuild":[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"",@"lastMarkAllRead":[WPActionAdapter lastMarkAllReadDiagnostics]} mutableCopy];
    NSDictionary *lastSyncFailure=[WPPreferences() dictionaryForKey:@"lastSyncConnectionFailure"];
    if(lastSyncFailure)result[@"lastSyncConnectionFailure"]=lastSyncFailure;
    result[@"quickChat"]=[WPQuickChatMonitor.sharedMonitor diagnostics];
    result[@"messageBarrage"]=[WPMessageBarrageSource.sharedSource diagnostics];
    result[@"selectedPet"]=[WPPreferences() dictionaryForKey:@"selectedPetLastLoad"]?:@{ @"selectedReference":WPSelectedPetReference()?:@"" };
    NSMutableArray *classNames=[@[@"CContactMgr",@"CMessageMgr",@"MMNewSessionMgr",@"MMMsgLogicManager",@"MMServiceCenter",@"MMContext",@"CAppViewControllerManager",@"CSessionInfo",@"MMSessionInfo",@"MMHeadImageMgr",@"CContact",@"SessionSelectController",@"ContactSelectViewController",@"WCRefineClearUnreadMsgHook"] mutableCopy];
#ifdef WP_RUNTIME_DIAGNOSTIC_URL
    NSString *selected=WPSelectedPetDirectory();
    result[@"petResources"]=@{@"bundleFound":@([WPResourceBundle().bundlePath.pathExtension isEqual:@"bundle"]),@"defaultExists":@([[NSFileManager defaultManager] fileExistsAtPath:[WPDefaultPetDirectory() stringByAppendingPathComponent:@"pet.json"]]),@"selectedExists":@([[NSFileManager defaultManager] fileExistsAtPath:selected?:@""])};
    NSMutableArray *imageChecks=[NSMutableArray new];
    for(NSString *directory in @[selected?:@"",WPDefaultPetDirectory()]){
        for(NSString *file in @[@"spritesheet.png",@"spritesheet.webp",@"pet.png"]){
            NSString *path=[directory stringByAppendingPathComponent:file];if(![[NSFileManager defaultManager] fileExistsAtPath:path])continue;
            CGImageSourceRef source=CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path],NULL);
            CGImageRef decoded=source?CGImageSourceCreateImageAtIndex(source,0,NULL):NULL;
            [imageChecks addObject:@{@"format":path.pathExtension,@"uiImage":@([UIImage imageWithContentsOfFile:path]!=nil),@"imageIO":@(decoded!=NULL),@"width":@(decoded?CGImageGetWidth(decoded):0)}];
            if(decoded)CGImageRelease(decoded);if(source)CFRelease(source);
        }
    }result[@"petImageDecoding"]=imageChecks;
    id context=WPDiagnosticObject(NSClassFromString(@"MMContext"),@"currentContext",nil,NO);
    result[@"currentContext"]=context?NSStringFromClass([context class]):@"nil";
    id active=WPDiagnosticObject(NSClassFromString(@"MMContext"),@"activeUserContext",nil,NO);
    result[@"contextFlags"]=@{@"currentRoot":WPContextFlag(context,@"isRootContext")?:NSNull.null,@"currentUser":WPContextFlag(context,@"isUserContext")?:NSNull.null,@"currentInvalid":WPContextFlag(context,@"isInvalidContext")?:NSNull.null,@"activeRoot":WPContextFlag(active,@"isRootContext")?:NSNull.null,@"activeUser":WPContextFlag(active,@"isUserContext")?:NSNull.null,@"activeInvalid":WPContextFlag(active,@"isInvalidContext")?:NSNull.null};
    id center=WPDiagnosticObject(NSClassFromString(@"MMServiceCenter"),@"defaultCenter",nil,NO);
    id sessions=WPWeChatService(@"MMNewSessionMgr");
    result[@"legacyServiceCenter"]=center?NSStringFromClass([center class]):@"nil";
    result[@"sessionService"]=sessions?NSStringFromClass([sessions class]):@"nil";
    id messages=WPWeChatService(@"CMessageMgr");
    result[@"messageService"]=messages?NSStringFromClass([messages class]):@"nil";
    result[@"serviceRuntimeClasses"]=@{@"sessions":sessions?NSStringFromClass(object_getClass(sessions)):@"nil",@"messages":messages?NSStringFromClass(object_getClass(messages)):@"nil"};
    NSMutableDictionary *lookup=[NSMutableDictionary new];
    for(NSString *serviceName in @[@"CContactMgr",@"CMessageMgr",@"MMNewSessionMgr"]){
        Class service=NSClassFromString(serviceName);
        id modern=WPDiagnosticObject(context,@"getService:",service,YES);
        id legacy=WPDiagnosticObject(center,@"getService:",service,YES);
        lookup[serviceName]=@{@"context":modern?NSStringFromClass([modern class]):@"nil",@"defaultCenter":legacy?NSStringFromClass([legacy class]):@"nil"};
    }result[@"serviceLookup"]=lookup;
    id names=WPDiagnosticObject(sessions,@"GetUserNamesOnSessionList",nil,NO);
    id list=WPDiagnosticObject(sessions,@"GetSessionInfoList",nil,NO);
    result[@"sessionNames"]=WPDiagnosticCollection(names);result[@"sessionList"]=WPDiagnosticCollection(list);
    id first=[list isKindOfClass:NSArray.class]?[list firstObject]:nil;
    if(!first && [names isKindOfClass:NSArray.class]) first=WPDiagnosticObject(sessions,@"GetSessionByUserName:",[names firstObject],YES);
    if(first)[classNames addObject:NSStringFromClass([first class])];
    id contacts=WPWeChatService(@"CContactMgr");
    result[@"contactService"]=contacts?NSStringFromClass([contacts class]):@"nil";
    id example=WPDiagnosticObject(contacts,@"getSelfContact",nil,NO);
    NSMutableDictionary *getters=[NSMutableDictionary new];
    for(NSString *name in @[@"m_nsUsrName",@"userName",@"m_nsRemark",@"m_nsNickName",@"getContactDisplayName"]){
        Method method=example?class_getInstanceMethod(object_getClass(example),NSSelectorFromString(name)):NULL;
        getters[name]=method?[NSString stringWithUTF8String:method_getTypeEncoding(method)]:@"missing";
    }result[@"contactGetterSignatures"]=getters;
    NSMutableDictionary *collections=[NSMutableDictionary new];
    for(NSString *name in @[@"getAllContactUserName",@"getAllContactUserNameFromCache"])
        collections[name]=WPDiagnosticCollection(WPDiagnosticObject(contacts,name,nil,NO));
    SEL outputSelector=NSSelectorFromString(@"getAllUserName:");Method outputMethod=class_getInstanceMethod(object_getClass(contacts),outputSelector);
    if(outputMethod){NSMethodSignature *signature=[NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(outputMethod)];
        if(signature.numberOfArguments==3 && signature.methodReturnType[0]=='B' && [signature getArgumentTypeAtIndex:2][0]=='@'){
            @try{NSMutableArray *output=[NSMutableArray new];NSInvocation *call=[NSInvocation invocationWithMethodSignature:signature];call.target=contacts;call.selector=outputSelector;__unsafe_unretained id value=output;[call setArgument:&value atIndex:2];[call invoke];collections[@"getAllUserName:"]=WPDiagnosticCollection(output);}@catch(__unused NSException *exception){collections[@"getAllUserName:"]=@{@"error":@"exception"};}
        }
    }result[@"contactCollections"]=collections;
#endif
    NSMutableDictionary *classes=[NSMutableDictionary new];
    for(NSString *name in classNames){
        Class type=NSClassFromString(name);if(!type)continue;NSMutableArray *entries=[NSMutableArray new];
        for(NSUInteger kind=0;kind<2;kind++){
            unsigned int count=0;Method *list=class_copyMethodList(kind?object_getClass(type):type,&count);
            for(unsigned int i=0;i<count;i++)[entries addObject:@{@"selector":NSStringFromSelector(method_getName(list[i])),@"encoding":[NSString stringWithUTF8String:method_getTypeEncoding(list[i])],@"classMethod":@(kind!=0)}];
            free(list);
        }classes[name]=entries;
    }result[@"classes"]=classes;
    return result;
}

void WPSendDevelopmentDiagnostics(void) {
#ifdef WP_RUNTIME_DIAGNOSTIC_URL
    // Development builds only. Contains API names/types, never contacts or messages.
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:WP_RUNTIME_DIAGNOSTIC_URL]];
    request.HTTPMethod=@"POST";request.timeoutInterval=10;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    request.HTTPBody=[NSJSONSerialization dataWithJSONObject:WPRuntimeDiagnostics() options:0 error:nil];
    [[NSURLSession.sharedSession dataTaskWithRequest:request] resume];
#endif
}
