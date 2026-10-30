#import "WPSessionEligibility.h"
#import "WPCommon.h"
#import <objc/runtime.h>
#import <UIKit/UIKit.h>
static const char *WPSET(const char *t){while(t&&*t&&strchr("rnNoORV",*t))t++;return t?:"";}
static BOOL WPSES(const char *t){t=WPSET(t);return t[0]&&strchr("BcCsSiIlLqQ",t[0])&&!t[1];}
static NSMethodSignature *WPSESignature(id o,NSString *k){@try{NSMethodSignature*s=[o methodSignatureForSelector:NSSelectorFromString(k)];return s.numberOfArguments==2?s:nil;}@catch(__unused NSException*e){return nil;}}
static BOOL WPSEEvidence(id o,NSString*k,BOOL scalar){Class c=object_getClass(o);objc_property_t p=class_getProperty(c,k.UTF8String);if(p){char*t=property_copyAttributeValue(p,"T");BOOL ok=scalar?WPSES(t):WPSET(t)[0]=='@';free(t);if(ok)return YES;}for(NSString*n in @[k,[@"_" stringByAppendingString:k]]){Ivar v=class_getInstanceVariable(c,n.UTF8String);const char*t=v?ivar_getTypeEncoding(v):NULL;if(t&&(scalar?WPSES(t):WPSET(t)[0]=='@'))return YES;}return NO;}
NSNumber *WPSEReadNumber(id o,NSArray<NSString*>*keys){if(!o)return nil;for(NSString*k in keys){NSMethodSignature*s=WPSESignature(o,k);if(s&&WPSES(s.methodReturnType)){@try{NSInvocation*i=[NSInvocation invocationWithMethodSignature:s];i.target=o;i.selector=NSSelectorFromString(k);[i invoke];switch(WPSET(s.methodReturnType)[0]){
#define S(c,t) case c:{t v=0;[i getReturnValue:&v];return @(v);}
S('B',bool) S('c',signed char) S('C',unsigned char) S('s',short) S('S',unsigned short) S('i',int) S('I',unsigned int) S('l',long) S('L',unsigned long) S('q',long long) S('Q',unsigned long long)
#undef S
}}@catch(__unused NSException*e){}}if(WPSEEvidence(o,k,YES)){@try{id v=[o valueForKey:k];if([v isKindOfClass:NSNumber.class])return v;}@catch(__unused NSException*e){}}}return nil;}
id WPSEReadObject(id o,NSArray<NSString*>*keys){if(!o)return nil;for(NSString*k in keys){@try{NSMethodSignature*s=WPSESignature(o,k);if(s&&WPSET(s.methodReturnType)[0]=='@'){NSInvocation*i=[NSInvocation invocationWithMethodSignature:s];i.target=o;i.selector=NSSelectorFromString(k);[i invoke];__unsafe_unretained id v=nil;[i getReturnValue:&v];if(v)return v;}if(WPSEEvidence(o,k,NO)){id v=[o valueForKey:k];if(v)return v;}}@catch(__unused NSException*e){}}return nil;}
static id WPSEArg(id o,NSString*k,id a){@try{NSMethodSignature*s=[o methodSignatureForSelector:NSSelectorFromString(k)];if(s.numberOfArguments!=3||WPSET(s.methodReturnType)[0]!='@'||WPSET([s getArgumentTypeAtIndex:2])[0]!='@')return nil;NSInvocation*i=[NSInvocation invocationWithMethodSignature:s];i.target=o;i.selector=NSSelectorFromString(k);__unsafe_unretained id v=a;[i setArgument:&v atIndex:2];[i invoke];v=nil;[i getReturnValue:&v];return v;}@catch(__unused NSException*e){return nil;}}
BOOL WPSESessionHiddenOrFolded(id s){if(!s)return YES;for(NSString*k in @[@"isHidden",@"m_bIsHidden",@"hidden",@"isInChatBox",@"isInBrandServiceBox",@"isBrandServiceBoxSession",@"isBrandEcsMsgHolderSession",@"m_isFolding",@"m_bIsFold",@"m_bIsFolded",@"isFolded"]){if(WPSEReadNumber(s,@[k]).boolValue)return YES;}return NO;}
NSNumber *WPSESessionMuted(id s,NSString*u){NSNumber*dot=WPSEReadNumber(s,@[@"m_bShowUnReadAsRedDot",@"showUnReadAsRedDot"]);if(dot)return @(dot.boolValue);id c=WPSEReadObject(s,@[@"m_contact",@"contact"]);if(!c)c=WPSEArg(WPWeChatService(@"CContactMgr"),@"getContactByName:",u);NSNumber*n=WPSEReadNumber(c,@[@"isChatStatusNotifyOpen"]);return n?@(!n.boolValue):nil;}
// One membership cache shared by the receive path and quick-chat. Native
// services are never invoked by a background decoder. Arrays are traversed in
// short turns instead of repeatedly building a set for every incoming message.
static __weak id WPSEManager;
static NSSet *WPSEMembers;
static NSArray *WPSEInput;
static NSMutableSet *WPSEBuilding;
static NSUInteger WPSEGeneration,WPSEIndex,WPSEMaxBatch,WPSEIndexCount;
static BOOL WPSEIndexRoute,WPSELoading,WPSEForeground=YES;
static NSTimeInterval WPSEBuiltAt,WPSECollectionRetryAfter,WPSEIndexRetryAfter;
static NSMutableDictionary<NSString *,NSDictionary *> *WPSETimings;
static void WPSEMeasure(NSString *route,NSTimeInterval began){
    if(!WPSETimings)WPSETimings=[NSMutableDictionary new];
    NSTimeInterval milliseconds=(CACurrentMediaTime()-began)*1000;
    NSDictionary *old=WPSETimings[route];
    WPSETimings[route]=@{@"lastMs":@(milliseconds),@"maximumMs":@(MAX(milliseconds,[old[@"maximumMs"] doubleValue])),@"calls":@([old[@"calls"] unsignedIntegerValue]+1),@"slowCalls":@([old[@"slowCalls"] unsignedIntegerValue]+(milliseconds>100?1:0))};
    if(milliseconds>100){if([route isEqual:@"home-collection"] || [route isEqual:@"home-copy"])WPSECollectionRetryAfter=CACurrentMediaTime()+60;else if([route isEqual:@"home-index"] || [route isEqual:@"home-count"])WPSEIndexRetryAfter=CACurrentMediaTime()+60;}
}
void WPSEInvalidateHomeNames(void){if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{WPSEInvalidateHomeNames();});return;}WPSEBuiltAt=0;}
void WPSESetForegroundAvailable(BOOL available){
    if(!NSThread.isMainThread)return;
    if(WPSEForeground==available)return;WPSEForeground=available;
    if(!available){WPSEGeneration++;WPSELoading=NO;WPSEInput=nil;WPSEBuilding=nil;}
    WPSEBuiltAt=0;
}
static BOOL WPSEHasIndexABI(id manager,NSString *key){
    @try{NSMethodSignature *signature=[manager methodSignatureForSelector:NSSelectorFromString(key)];const char *argument=signature.numberOfArguments==3?WPSET([signature getArgumentTypeAtIndex:2]):"";
        return signature.numberOfArguments==3 && WPSET(signature.methodReturnType)[0]=='@' && argument[0] && !argument[1] && strchr("iIlLqQ",argument[0]);
    }@catch(__unused NSException *exception){return NO;}
}
static id WPSEIndexedSessionName(id manager,NSUInteger index){
    NSTimeInterval began=CACurrentMediaTime();id result=nil;
    for(NSString*key in @[@"GetSessionUserNameAtIndex:",@"GetSessionAtIndex:"]){@try{NSMethodSignature*s=[manager methodSignatureForSelector:NSSelectorFromString(key)];if(!WPSEHasIndexABI(manager,key))continue;NSInvocation*i=[NSInvocation invocationWithMethodSignature:s];i.target=manager;i.selector=NSSelectorFromString(key);switch(WPSET([s getArgumentTypeAtIndex:2])[0]){
#define WPSE_IDX(c,t) case c:{t v=(t)index;[i setArgument:&v atIndex:2];break;}
WPSE_IDX('i',int) WPSE_IDX('I',unsigned int) WPSE_IDX('l',long) WPSE_IDX('L',unsigned long) WPSE_IDX('q',long long) WPSE_IDX('Q',unsigned long long)
#undef WPSE_IDX
        default:continue;}[i invoke];__unsafe_unretained id v=nil;[i getReturnValue:&v];if([v isKindOfClass:NSString.class]){result=v;break;}if(v){id name=WPSEReadObject(v,@[@"m_nsUserName",@"m_nsUsrName",@"userName",@"username"]);if([name isKindOfClass:NSString.class]){result=name;break;}}}@catch(__unused NSException*e){}}
    WPSEMeasure(@"home-index",began);return result;
}
static void WPSEBuildStep(NSUInteger generation){
    if(generation!=WPSEGeneration || !WPSEForeground)return;
    NSUInteger count=WPSEIndexRoute?WPSEIndexCount:WPSEInput.count,end=MIN(count,WPSEIndex+150),batch=0;
    NSTimeInterval began=CACurrentMediaTime();
    while(WPSEIndex<end){
        if(WPSEIndexRoute && CACurrentMediaTime()<WPSEIndexRetryAfter){WPSELoading=NO;WPSEInput=nil;WPSEBuilding=nil;WPSEMembers=nil;return;}
        id name=WPSEIndexRoute?WPSEIndexedSessionName(WPSEManager,WPSEIndex):WPSEInput[WPSEIndex];WPSEIndex++;
        if([name isKindOfClass:NSString.class] && [name length] && [name length]<=256)[WPSEBuilding addObject:name];batch++;
        if(CACurrentMediaTime()-began>.003)break;
    }
    WPSEMaxBatch=MAX(WPSEMaxBatch,batch);
    if(WPSEIndex<count){dispatch_after(dispatch_time(DISPATCH_TIME_NOW,8*NSEC_PER_MSEC),dispatch_get_main_queue(),^{WPSEBuildStep(generation);});return;}
    WPSEMembers=[WPSEBuilding copy];WPSEInput=nil;WPSEBuilding=nil;WPSELoading=NO;WPSEBuiltAt=NSDate.date.timeIntervalSince1970;
}
NSSet<NSString*>*WPSEHomeNames(id manager){
    if(!NSThread.isMainThread || !manager || !WPSEForeground)return nil;
    BOOL same=WPSEManager==manager;
    if(same && WPSELoading)return WPSEMembers;
    if(same && WPSEMembers && NSDate.date.timeIntervalSince1970-WPSEBuiltAt<2)return WPSEMembers;
    if(!same){WPSECollectionRetryAfter=WPSEIndexRetryAfter=0;}
    NSNumber *indexCount=nil;BOOL usernameIndex=WPSEHasIndexABI(manager,@"GetSessionUserNameAtIndex:");
    if(usernameIndex && CACurrentMediaTime()>=WPSEIndexRetryAfter){NSTimeInterval began=CACurrentMediaTime();indexCount=WPSEReadNumber(manager,@[@"GetSessionCount"]);WPSEMeasure(@"home-count",began);}
    // A typed username-index explicitly enumerates the native home list. The
    // generic GetSessionAtIndex fallback keeps its existing collection check.
    BOOL useUsernameIndex=usernameIndex && indexCount && indexCount.longLongValue>=0;
    NSArray *names=nil;BOOL collectionUnavailable=NO;
    if(!useUsernameIndex){
        if(CACurrentMediaTime()<WPSECollectionRetryAfter)return nil;
        NSTimeInterval began=CACurrentMediaTime();id raw=WPSEReadObject(manager,@[@"GetUserNamesOnSessionList"]);WPSEMeasure(@"home-collection",began);
        began=CACurrentMediaTime();
        @try{
            if([raw isKindOfClass:NSArray.class])names=[raw subarrayWithRange:NSMakeRange(0,MIN((NSUInteger)[raw count],(NSUInteger)10000))];
            else if([raw isKindOfClass:NSOrderedSet.class]){NSMutableArray *bounded=[NSMutableArray new];for(NSUInteger i=0;i<MIN((NSUInteger)[raw count],(NSUInteger)10000);i++)[bounded addObject:[raw objectAtIndex:i]];names=bounded.copy;}
            else if([raw isKindOfClass:NSSet.class]){NSMutableArray *bounded=[NSMutableArray new];for(id value in raw){[bounded addObject:value];if(bounded.count==10000)break;}names=bounded.copy;}
        }@catch(__unused NSException *exception){names=nil;}
        WPSEMeasure(@"home-copy",began);collectionUnavailable=names==nil;
    }
    WPSEManager=manager;WPSEGeneration++;WPSELoading=NO;WPSEIndexRoute=NO;WPSEIndexCount=0;
    if(useUsernameIndex || collectionUnavailable){
        if(!indexCount){NSTimeInterval began=CACurrentMediaTime();indexCount=WPSEReadNumber(manager,@[@"GetSessionCount"]);WPSEMeasure(@"home-count",began);}
        BOOL validIndex=usernameIndex || WPSEHasIndexABI(manager,@"GetSessionAtIndex:");
        if(!indexCount || indexCount.longLongValue<0 || !validIndex || CACurrentMediaTime()<WPSEIndexRetryAfter){WPSEMembers=nil;return nil;}
        WPSEIndexRoute=YES;WPSEIndexCount=MIN(indexCount.unsignedIntegerValue,(NSUInteger)10000);
    }
    WPSEMembers=nil;WPSEInput=names;WPSEBuilding=[NSMutableSet new];WPSEIndex=0;WPSELoading=YES;WPSEBuildStep(WPSEGeneration);return WPSEMembers;
}
NSDictionary *WPSEHomeDiagnostics(void){return @{@"membershipLoading":@(WPSELoading),@"membershipRoute":WPSEIndexRoute?@"native-index":@"names",@"membershipCount":@(WPSEMembers.count),@"membershipBatchMaximum":@(WPSEMaxBatch),@"nativeTimings":WPSETimings.copy?:@{},@"collectionCooling":@(CACurrentMediaTime()<WPSECollectionRetryAfter),@"indexCooling":@(CACurrentMediaTime()<WPSEIndexRetryAfter)};}
