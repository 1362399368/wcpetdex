#import "WPQuickChat.h"
#import "WPCommon.h"
#import "WPActionAdapter.h"
#import "WPSessionEligibility.h"
#import "WPQuickChatPreferences.h"
#import "WPMessageBarrageSource.h"
#import "WPBarragePreferences.h"
#import "WPChatPresentationState.h"
#import "WPNativeRefreshGate.h"
#import <os/lock.h>
#import <ImageIO/ImageIO.h>
#import <objc/runtime.h>
#import <math.h>

// Read-only session access. Selector names follow the public historical
// WeChat headers already cited in WPPartnerContact.m; every call checks the
// installed build's runtime signature first and degrades instead of guessing.
NSString * const WPQuickChatDidChangeNotification=@"WeChatPet.QuickChatDidChange";
BOOL WPQuickChatEnabled(void){return [WPPreferences() boolForKey:@"quickChatEnabled"];}
BOOL WPQuickChatFlashEnabled(void){return [WPPreferences() boolForKey:@"quickChatFlash"];}

static const NSUInteger WPQCWindow=60;      // top rows checked every poll
static const NSUInteger WPQCScanBatch=150;  // rows per main-queue turn in a full scan
static const NSTimeInterval WPQCInterval=2; // seconds between polls
static const NSTimeInterval WPQCIdleInterval=8;
static const NSTimeInterval WPQCFullScanInterval=30;
static os_unfair_lock WPQCMonitorPublicationLock=OS_UNFAIR_LOCK_INIT;
static WPNativeRefreshGate *WPQCNativeGate;
static __weak WPQuickChatMonitor *WPQCExistingMonitor;

static const char *WPQCUnqualified(const char *type){while(type && *type && strchr("rnNoORV",*type))type++;return type;}
static BOOL WPQCScalar(const char *type){const char *v=WPQCUnqualified(type);return v && v[0] && strchr("BcCsSiIlLqQ",v[0]) && v[1]=='\0';}
static BOOL WPQCObjectType(const char *type){const char *value=WPQCUnqualified(type);return value && value[0]=='@';}
static const NSUInteger WPQCMaximumSessionRows=10000;
static NSArray *WPQCCollectionSnapshot(id value){
    @try{
        if([value isKindOfClass:NSArray.class])return [value copy];
        if([value isKindOfClass:NSOrderedSet.class])return [[value array] copy];
        if([value isKindOfClass:NSSet.class])return [[value allObjects] copy];
    }@catch(__unused NSException *exception){}
    return nil;
}
static NSMethodSignature *WPQCSignature(id target,NSString *name,NSUInteger arguments){
    if(!target)return nil;NSMethodSignature *signature=nil;
    // Service proxies forward methods they do not define themselves.
    @try{signature=[target methodSignatureForSelector:NSSelectorFromString(name)];}@catch(__unused NSException *exception){return nil;}
    return signature.numberOfArguments==arguments+2?signature:nil;
}
static id WPQCObject(id target,NSString *name){
    NSMethodSignature *signature=WPQCSignature(target,name,0);
    if(!signature || WPQCUnqualified(signature.methodReturnType)[0]!='@')return nil;
    @try{NSInvocation *call=[NSInvocation invocationWithMethodSignature:signature];call.target=target;call.selector=NSSelectorFromString(name);[call invoke];
        __unsafe_unretained id result=nil;[call getReturnValue:&result];return result;}@catch(__unused NSException *exception){return nil;}
}
static NSNumber *WPQCScalarReturn(NSInvocation *call,NSMethodSignature *signature){
    switch(WPQCUnqualified(signature.methodReturnType)[0]){
#define WPQC_CASE(code,type) case code:{type value=0;[call getReturnValue:&value];return @(value);}
        WPQC_CASE('B',bool) WPQC_CASE('c',signed char) WPQC_CASE('C',unsigned char) WPQC_CASE('s',short) WPQC_CASE('S',unsigned short)
        WPQC_CASE('i',int) WPQC_CASE('I',unsigned int) WPQC_CASE('l',long) WPQC_CASE('L',unsigned long) WPQC_CASE('q',long long) WPQC_CASE('Q',unsigned long long)
#undef WPQC_CASE
    }
    return nil;
}
static BOOL WPQCKVCEvidence(id object,NSString *key,BOOL scalar){
    Class cls=object_getClass(object);
    objc_property_t property=cls?class_getProperty(cls,key.UTF8String):NULL;
    if(property){char *type=property_copyAttributeValue(property,"T");BOOL ok=type && (scalar?WPQCScalar(type):type[0]=='@');free(type);if(ok)return YES;}
    for(NSString *name in @[key,[@"_" stringByAppendingString:key]]){
        Ivar ivar=cls?class_getInstanceVariable(cls,name.UTF8String):NULL;
        const char *type=ivar?ivar_getTypeEncoding(ivar):NULL;
        if(type && (scalar?WPQCScalar(type):type[0]=='@'))return YES;
    }
    return NO;
}
/// First readable scalar among keys: a typed getter, else KVC on a typed property/ivar.
static NSNumber *WPQCNumber(id object,NSArray<NSString *> *keys){
    if(!object)return nil;
    for(NSString *key in keys){
        NSMethodSignature *signature=WPQCSignature(object,key,0);
        if(signature && WPQCScalar(signature.methodReturnType)){
            @try{NSInvocation *call=[NSInvocation invocationWithMethodSignature:signature];call.target=object;call.selector=NSSelectorFromString(key);[call invoke];
                NSNumber *value=WPQCScalarReturn(call,signature);if(value)return value;}@catch(__unused NSException *exception){}
        }
        if(WPQCKVCEvidence(object,key,YES)){
            @try{id value=[object valueForKey:key];if([value isKindOfClass:NSNumber.class])return value;}@catch(__unused NSException *exception){}
        }
    }
    return nil;
}
static id WPQCValue(id object,NSArray<NSString *> *keys,Class kind){
    if(!object)return nil;
    for(NSString *key in keys){
        id value=WPQCObject(object,key);
        if(!value && WPQCKVCEvidence(object,key,NO)){@try{value=[object valueForKey:key];}@catch(__unused NSException *exception){value=nil;}}
        if(!kind || [value isKindOfClass:kind])return value;
    }
    return nil;
}
static id WPQCObjectArgument(id target,NSString *name,id argument){
    NSMethodSignature *signature=WPQCSignature(target,name,1);
    if(!signature || WPQCUnqualified(signature.methodReturnType)[0]!='@' || WPQCUnqualified([signature getArgumentTypeAtIndex:2])[0]!='@')return nil;
    @try{NSInvocation *call=[NSInvocation invocationWithMethodSignature:signature];call.target=target;call.selector=NSSelectorFromString(name);
        __unsafe_unretained id value=argument;[call setArgument:&value atIndex:2];[call invoke];
        __unsafe_unretained id result=nil;[call getReturnValue:&result];return result;}@catch(__unused NSException *exception){return nil;}
}
/// Sets an unsigned integer argument at its declared width.
static BOOL WPQCSetInteger(NSInvocation *call,NSMethodSignature *signature,NSUInteger index,uint64_t value){
    switch(WPQCUnqualified([signature getArgumentTypeAtIndex:index])[0]){
        case 'i':case 'I':{uint32_t v=(uint32_t)value;[call setArgument:&v atIndex:index];return YES;}
        case 'l':case 'L':{unsigned long v=(unsigned long)value;[call setArgument:&v atIndex:index];return YES;}
        case 'q':case 'Q':{uint64_t v=value;[call setArgument:&v atIndex:index];return YES;}
    }
    return NO;
}

#pragma mark - Session rows

static NSString *WPQCUsername(id session){
    NSString *name=WPQCValue(session,@[@"m_nsUserName",@"m_nsUsrName",@"userName",@"username"],NSString.class);
    return [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
}
/// A session can remain in MMNewSessionMgr after WeChat moves it into a
/// folded group, a chat box, or a hidden container. Only top-level home rows
/// belong in the quick-chat list and its unread indicator.
static BOOL WPQCIsHomeSession(id session,NSString *username,NSSet<NSString *> *homeNames){
    if(!session || !username.length || (homeNames && ![homeNames containsObject:username]))return NO;
    if(WPSESessionHiddenOrFolded(session))return NO;
    return YES;
}
static WPQuickChatSession *WPQCSession(id session,NSString *knownName){
    NSString *username=knownName ?: WPQCUsername(session);if(!username.length || !session)return nil;
    WPQuickChatSession *row=[WPQuickChatSession new];row.username=username;
    NSNumber *unread=WPSessionUnreadCount(session);row.unreadKnown=unread!=nil;row.unread=unread.unsignedIntegerValue;
    // A muted chat shows its unread as a plain red dot in WeChat's own list.
    NSNumber *muted=WPSESessionMuted(session,username);row.muted=muted?muted.boolValue:YES;
    row.pinned=[WPQCNumber(session,@[@"m_bIsTop",@"isTop",@"m_isTop"]) boolValue];
    NSNumber *time=WPQCNumber(session,@[@"m_uLastTime",@"m_uiLastTime",@"m_lastTime"]);
    if(!time)time=WPQCNumber(WPQCValue(session,@[@"m_msgWrap"],nil),@[@"m_uiCreateTime"]);
    row.time=time.doubleValue;
    return row;
}

static NSMutableDictionary<NSString *,NSDictionary *> *WPQCUnreadSnapshots;
static void WPQCInvalidateUnreadSnapshots(void){[WPQCUnreadSnapshots removeAllObjects];}
static WPQuickChatUnreadState WPQCUnreadStateFromSession(id session,NSString *username,id manager){
    if(!session)return WPQuickChatUnreadStateUnknown;
    NSString *actual=WPQCUsername(session);
    if(actual.length && ![actual isEqual:username])return WPQuickChatUnreadStateUnknown;
    if(WPSESessionHiddenOrFolded(session))return WPQuickChatUnreadStateDenied;
    NSNumber *muted=WPSESessionMuted(session,username);
    if(muted.boolValue)return WPQuickChatUnreadStateDenied;
    NSNumber *count=WPSessionUnreadCount(session);
    if(count && count.unsignedLongLongValue==0)return WPQuickChatUnreadStateRead;
    NSSet *home=WPSEHomeNames(manager);
    // Missing membership during cache rebuilding cannot consume an unread.
    if(count && muted && !muted.boolValue && home && [home containsObject:username])return WPQuickChatUnreadStateUnread;
    return WPQuickChatUnreadStateUnknown;
}

/// One snapshot of how this WeChat build exposes its session list.
@interface WPQuickChatSource : NSObject
@property(nonatomic,strong) id manager;
@property(nonatomic,copy) NSString *route;
@property(nonatomic) NSUInteger count;
@property(nonatomic,copy) NSArray *items;
@property(nonatomic,copy) NSSet<NSString *> *homeNames;
@property(nonatomic) BOOL nativeOrder;
@property(nonatomic) BOOL displayOptions;
@property(nonatomic) NSUInteger lastReadEnd;
/// Names actually visited, including rows rejected by the home/folding filter.
/// They make an observed unread row disappear as soon as it becomes ineligible.
@property(nonatomic,copy) NSSet<NSString *> *lastReadUsernames;
@property(nonatomic,copy) NSDictionary<NSString *,NSNumber *> *lastReadRanks;
@end

@implementation WPQuickChatSource
+ (instancetype)current {
    id manager=WPWeChatService(@"MMNewSessionMgr");if(!manager)return nil;
    WPQuickChatSource *source=[self new];source.manager=manager;
    // WeChat's own session-list membership excludes conversations that are no
    // longer on the home tab. Keep it even when index access supplies order.
    source.homeNames=WPSEHomeNames(manager);
    // GetSessionAtIndex: walks the main list as drawn: pinned rows, then recent.
    NSMethodSignature *count=WPQCSignature(manager,@"GetSessionCount",0),*index=WPQCSignature(manager,@"GetSessionAtIndex:",1);
    if(count && index && WPQCScalar(count.methodReturnType) && WPQCUnqualified(index.methodReturnType)[0]=='@' && strchr("iIlLqQ",WPQCUnqualified([index getArgumentTypeAtIndex:2])[0])){
        NSNumber *value=WPQCNumber(manager,@[@"GetSessionCount"]);
        if(value && value.longLongValue>=0){source.route=@"index";source.count=MIN(value.unsignedIntegerValue,WPQCMaximumSessionRows);source.nativeOrder=YES;return source;}
    }
    id list=WPQCObject(manager,@"GetSessionInfoList");
    // GetSessionInfoList may include cached, folded, and hidden rows. It is
    // usable only with a separate home-list membership signal.
    if([list isKindOfClass:NSArray.class] && source.homeNames){source.route=@"list";source.items=list;source.count=MIN(source.items.count,WPQCMaximumSessionRows);return source;}
    NSArray *names=WPQCCollectionSnapshot(source.homeNames);
    if(names){source.route=@"names";source.items=names;source.count=MIN(names.count,WPQCMaximumSessionRows);return source;}
    return nil;
}
- (id)objectAtIndex:(NSUInteger)index {
    if([self.route isEqual:@"index"]){
        NSMethodSignature *signature=WPQCSignature(self.manager,@"GetSessionAtIndex:",1);if(!signature || !WPQCObjectType(signature.methodReturnType))return nil;
        @try{NSInvocation *call=[NSInvocation invocationWithMethodSignature:signature];call.target=self.manager;call.selector=NSSelectorFromString(@"GetSessionAtIndex:");
            if(!WPQCSetInteger(call,signature,2,index))return nil;[call invoke];__unsafe_unretained id result=nil;[call getReturnValue:&result];return result;}
        @catch(__unused NSException *exception){return nil;}
    }
    if(index>=self.items.count)return nil;
    if([self.route isEqual:@"list"])return self.items[index];
    return WPQCObjectArgument(self.manager,@"GetSessionByUserName:",self.items[index]);
}
- (NSArray<WPQuickChatSession *> *)sessionsInRange:(NSRange)range {
    NSMutableArray *rows=[NSMutableArray new];
    NSMutableSet *visited=[NSMutableSet new];NSMutableDictionary *ranks=[NSMutableDictionary new];
    NSUInteger start=MIN(range.location,self.count),length=MIN(MIN(range.length,(NSUInteger)150),self.count-start);self.lastReadEnd=start;NSTimeInterval began=CACurrentMediaTime();
    for(NSUInteger i=start;i<start+length;i++){@autoreleasepool{
        self.lastReadEnd=i+1;NSString *name=[self.route isEqual:@"names"]?self.items[i]:nil;
        if(name && (![name isKindOfClass:NSString.class]||name.length>256))continue;
        if(name.length && name.length<=256)[visited addObject:name];
        // Aggregate holders cannot be opened from the bar, so they neither flash nor light the dot.
        if(name && !WPQuickChatIsOpenableUsername(name))continue;
        id session=[self objectAtIndex:i];if(!session)continue;
        name=name ?: WPQCUsername(session);
        if(name.length && name.length<=256)[visited addObject:name];
        BOOL home=WPQCIsHomeSession(session,name,self.homeNames);
        if(!WPQuickChatIsOpenableUsername(name))continue;
        if(!home){BOOL explicitHidden=NO;for(NSString*k in @[@"isHidden",@"m_bIsHidden",@"hidden"])explicitHidden |= WPSEReadNumber(session,@[k]).boolValue;BOOL folded=WPSESessionHiddenOrFolded(session)&&!explicitHidden;if(!self.displayOptions || !WPQuickChatOptionBool(@"showFolded") || !folded)continue;}
        if(self.displayOptions){id contact=WPSEReadObject(session,@[@"m_contact",@"contact"]);if(!contact)contact=WPQCObjectArgument(WPWeChatService(@"CContactMgr"),@"getContactByName:",name);BOOL service=WPSEReadNumber(contact,@[@"isServiceAppContact",@"isServiceContact"]).boolValue;BOOL official=[name hasPrefix:@"gh_"]||WPSEReadNumber(contact,@[@"isBrandContact"]).boolValue;if((service&&!WPQuickChatOptionBool(@"showService"))||(!service&&official&&!WPQuickChatOptionBool(@"showOfficial")))continue;}
        WPQuickChatSession *row=WPQCSession(session,name);if(row){[rows addObject:row];ranks[name]=@(i);}
        if(CACurrentMediaTime()-began>.003)break;
    }}
    self.lastReadUsernames=visited;self.lastReadRanks=ranks;
    return rows;
}
@end

static UIImage *WPQCHeadImage(id value){
    if([value isKindOfClass:UIImage.class]){
        CGImageRef image=((UIImage *)value).CGImage;
        if(!image)return nil;
        size_t width=CGImageGetWidth(image),height=CGImageGetHeight(image),rowBytes=CGImageGetBytesPerRow(image);
        // A huge UIImage has no encoded source to pass to ImageIO's bounded
        // decoder. Let callers fetch the contact URL as a thumbnail instead
        // of forcing a multi-megabyte bitmap into the host's memory.
        return width && height && width<=1024 && height<=1024 &&
            width*height<=1024*1024 && rowBytes<=8*1024*1024/height ? value : nil;
    }
    if([value isKindOfClass:NSData.class] && [value length] && [value length] <= 5*1024*1024){
        // WeChat can supply an encoded original photo here. imageWithData:
        // would leave that full-resolution image available for later decode;
        // the floating avatar only needs a 160-pixel thumbnail.
        CGImageSourceRef source=CGImageSourceCreateWithData((__bridge CFDataRef)value,
            (__bridge CFDictionaryRef)@{(id)kCGImageSourceShouldCache:@NO});
        if(!source)return nil;
        NSDictionary *properties=CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source,0,NULL));
        double width=[properties[(id)kCGImagePropertyPixelWidth] doubleValue];
        double height=[properties[(id)kCGImagePropertyPixelHeight] doubleValue];
        if(width<1 || height<1 || width>8192 || height>8192 || width*height>16*1024*1024){CFRelease(source);return nil;}
        CGImageRef thumbnail=CGImageSourceCreateThumbnailAtIndex(source,0,
            (__bridge CFDictionaryRef)@{(id)kCGImageSourceCreateThumbnailFromImageAlways:@YES,
                (id)kCGImageSourceCreateThumbnailWithTransform:@YES,
                (id)kCGImageSourceThumbnailMaxPixelSize:@160,
                (id)kCGImageSourceShouldCacheImmediately:@YES});
        CFRelease(source);
        UIImage *image=thumbnail?[UIImage imageWithCGImage:thumbnail]:nil;
        if(thumbnail)CGImageRelease(thumbnail);
        return image;
    }
    return nil;
}
#if defined(WP_PREVIEW_HOST)
UIImage *WPPreviewDecodeLocalAvatarValue(id value){return WPQCHeadImage(value);}
#endif
static id WPQCContactHeadValueForManager(id manager,NSString *username){
    id contact=WPQCObjectArgument(manager,@"getContactByName:",username);
    if(!contact)contact=WPQCObjectArgument(manager,@"getContactByNameFromDB:",username);
    NSString *actual=WPQCValue(contact,@[@"m_nsUsrName",@"m_nsUserName"],NSString.class);
    if(![actual isEqual:username])return nil;
    // This native cache getter is also referenced in the supplied WCRefine
    // binary. It works independently of the legacy MMHeadImageMgr class.
    return WPQCObject(contact,@"getContactHeadImage");
}
static id WPQCContactHeadValue(NSString *username){return WPQCContactHeadValueForManager(WPWeChatService(@"CContactMgr"),username);}
#if defined(WP_PREVIEW_HOST)
id WPPreviewContactHeadCache(id manager,NSString *username){return WPQCContactHeadValueForManager(manager,username);}
#endif
UIImage *WPQuickChatAvatar(NSString *username){
    if(!NSThread.isMainThread)return nil;
    if(!username.length || username.length>256)return nil;
    id manager=WPWeChatService(@"MMHeadImageMgr");
    for(NSString *name in @[@"getHeadImage:withCategory:",@"getHeadImageByUserName:withCategory:"]){
        NSMethodSignature *signature=WPQCSignature(manager,name,2);
        if(!signature || WPQCUnqualified(signature.methodReturnType)[0]!='@' || WPQCUnqualified([signature getArgumentTypeAtIndex:2])[0]!='@')continue;
        @try{NSInvocation *call=[NSInvocation invocationWithMethodSignature:signature];call.target=manager;call.selector=NSSelectorFromString(name);
            __unsafe_unretained id value=username;[call setArgument:&value atIndex:2];
            if(!WPQCSetInteger(call,signature,3,0))continue;[call invoke];
            __unsafe_unretained id result=nil;[call getReturnValue:&result];
            UIImage *image=[result isKindOfClass:UIImage.class]?WPQCHeadImage(result):nil;if(image)return image;}@catch(__unused NSException *exception){}
    }
    // Some WeChat builds expose the cached image with a single username argument.
    for(NSString *name in @[@"getHeadImage:",@"getHeadImageByUserName:"]){
        id value=WPQCObjectArgument(manager,name,username);UIImage *image=[value isKindOfClass:UIImage.class]?WPQCHeadImage(value):nil;if(image)return image;
    }
    id contactHead=WPQCContactHeadValue(username);
    return [contactHead isKindOfClass:UIImage.class]?WPQCHeadImage(contactHead):nil;
}
// The native cache and native on-disk thumbnail paths also occur in the
// supplied WCRefine binary. They are independent WeChat service calls; this
// implementation neither loads nor calls WCRefine.
#if defined(WP_PREVIEW_HOST)
static void(^WPQCLocalAvatarReadObserver)(BOOL);
void WPPreviewSetLocalAvatarNativeReadObserver(void(^observer)(BOOL)){WPQCLocalAvatarReadObserver=[observer copy];}
#endif
static id WPQCAvatarInput(NSString *username) {
#if defined(WP_PREVIEW_HOST)
    if(WPQCLocalAvatarReadObserver)WPQCLocalAvatarReadObserver(NSThread.isMainThread);
#endif
    UIImage *cached=WPQuickChatAvatar(username);if(cached)return cached;
    id manager=WPWeChatService(@"MMHeadImageMgr");
    for(NSString *name in @[@"getHeadImage:withCategory:",@"getHeadImageByUserName:withCategory:"]){@try{NSMethodSignature*sig=WPQCSignature(manager,name,2);if(!sig||!WPQCObjectType(sig.methodReturnType)||!WPQCObjectType([sig getArgumentTypeAtIndex:2]))continue;NSInvocation*call=[NSInvocation invocationWithMethodSignature:sig];call.target=manager;call.selector=NSSelectorFromString(name);__unsafe_unretained id arg=username;[call setArgument:&arg atIndex:2];if(!WPQCSetInteger(call,sig,3,0))continue;[call invoke];__unsafe_unretained id value=nil;[call getReturnValue:&value];if([value isKindOfClass:UIImage.class]){UIImage*safe=WPQCHeadImage(value);if(safe)return safe;}else if([value isKindOfClass:NSData.class]&&[value length]<=1024*1024)return value;}@catch(__unused NSException*e){}}
    for(NSString *name in @[@"getHeadImage:",@"getHeadImageByUserName:",@"imageForUsr:"]){id value=WPQCObjectArgument(manager,name,username);if([value isKindOfClass:UIImage.class]){UIImage*safe=WPQCHeadImage(value);if(safe)return safe;}else if([value isKindOfClass:NSData.class]&&[value length]<=1024*1024)return value;}
    id cacher=WPWeChatService(@"MMHeadImageCacher");
    if(!cacher)cacher=WPSEReadObject(manager,@[@"m_headImageCacher",@"headImageCacher",@"m_headImgCacher"]);
    id image=WPQCObjectArgument(cacher,@"imageForUsr:",username);if([image isKindOfClass:UIImage.class]){UIImage*safe=WPQCHeadImage(image);if(safe)return safe;}
    for(NSString *name in @[@"getHeadImgPathForNewVersionForLoadImage:forCategory:isHD:",@"getHeadImgPathForNewVersion:forCategory:isHD:",@"getHeadImgPathForOldVersion:isHD:"]){
        @try{NSMethodSignature *signature=WPQCSignature(manager,name,[name hasSuffix:@"forCategory:isHD:"]?3:2);if(!signature||!WPQCObjectType(signature.methodReturnType)||!WPQCObjectType([signature getArgumentTypeAtIndex:2]))continue;NSInvocation *call=[NSInvocation invocationWithMethodSignature:signature];call.target=manager;call.selector=NSSelectorFromString(name);__unsafe_unretained id value=username;[call setArgument:&value atIndex:2];BOOL valid=YES;for(NSUInteger i=3;i<signature.numberOfArguments;i++){const char*t=WPQCUnqualified([signature getArgumentTypeAtIndex:i]);if(t[0]=='B'){bool b=false;[call setArgument:&b atIndex:i];}else if(t[0]=='c'){signed char b=0;[call setArgument:&b atIndex:i];}else valid &= WPQCSetInteger(call,signature,i,0);}if(!valid)continue;[call invoke];value=nil;[call getReturnValue:&value];if([value isKindOfClass:NSString.class]&&[value isAbsolutePath]&&[value length]<4096)return [value copy];}@catch(__unused NSException *exception){}
    }
    id contactHead=WPQCContactHeadValue(username);
    if([contactHead isKindOfClass:UIImage.class])return WPQCHeadImage(contactHead);
    return [contactHead isKindOfClass:NSData.class] && [contactHead length]<=1024*1024?contactHead:nil;
}
@interface WPQuickChatAvatarPreparation ()
@property(nonatomic,strong) id input;
@property(nonatomic,copy) NSString *username;
@property(nonatomic,copy) void(^completion)(UIImage*);
@property(nonatomic) CGFloat pixels;
@property(atomic) BOOL cancelled;
@end
static NSMutableArray<WPQuickChatAvatarPreparation*> *WPQCAvatarWaiting;static BOOL WPQCAvatarWorking;static dispatch_queue_t WPQCAvatarQueue;
static void WPQCAvatarPump(void);
@implementation WPQuickChatAvatarPreparation
- (void)cancel {@synchronized(self){self.cancelled=YES;self.input=nil;self.username=nil;self.completion=nil;}if(NSThread.isMainThread)[WPQCAvatarWaiting removeObjectIdenticalTo:self];else dispatch_async(dispatch_get_main_queue(),^{[WPQCAvatarWaiting removeObjectIdenticalTo:self];});}
@end
static UIImage *WPQCPrepareInput(id input,CGFloat pixels){
    if([input isKindOfClass:NSString.class]){NSDictionary*a=[NSFileManager.defaultManager attributesOfItemAtPath:input error:nil];if([a[NSFileSize] unsignedLongLongValue]>5*1024*1024)return nil;input=[NSData dataWithContentsOfFile:input options:NSDataReadingMappedIfSafe error:nil];}
    UIImage *image=WPQCHeadImage(input);if(!image)return nil;CGSize size=image.size;CGFloat width=MIN(pixels,MAX(size.width,size.height)*image.scale);if(!isfinite(width)||width<1)return nil;CGFloat ratio=width/MAX(size.width,size.height);CGSize target=CGSizeMake(MAX(1,round(size.width*ratio)),MAX(1,round(size.height*ratio)));UIGraphicsImageRendererFormat*f=[UIGraphicsImageRendererFormat defaultFormat];f.scale=1;f.opaque=NO;return [[[UIGraphicsImageRenderer alloc]initWithSize:target format:f]imageWithActions:^(UIGraphicsImageRendererContext*c){[image drawInRect:(CGRect){CGPointZero,target}];}];
}
static void WPQCAvatarPump(void){if(WPQCAvatarWorking||!WPQCAvatarWaiting.count)return;WPQuickChatAvatarPreparation*t=WPQCAvatarWaiting.firstObject;[WPQCAvatarWaiting removeObjectAtIndex:0];if(t.cancelled){WPQCAvatarPump();return;}WPQCAvatarWorking=YES;
    // Waiting tokens retain only their short identifier. Query native image
    // caches on main only as this sole worker becomes available.
    id preparedInput=t.username.length?WPQCAvatarInput(t.username):nil;
    @synchronized(t){if(!t.cancelled)t.input=preparedInput;t.username=nil;}preparedInput=nil;
    dispatch_async(WPQCAvatarQueue,^{@autoreleasepool{id input=nil;@synchronized(t){if(!t.cancelled){input=t.input;t.input=nil;}}UIImage*image=input?WPQCPrepareInput(input,t.pixels):nil;input=nil;dispatch_async(dispatch_get_main_queue(),^{void(^completion)(UIImage*)=nil;@synchronized(t){if(!t.cancelled)completion=t.completion;t.completion=nil;t.input=nil;}if(completion)completion(image);WPQCAvatarWorking=NO;WPQCAvatarPump();});}});}
WPQuickChatAvatarPreparation *WPQuickChatPrepareAvatar(NSString *username,CGFloat maximumPixels,void(^completion)(UIImage*)){WPQuickChatAvatarPreparation*t=[WPQuickChatAvatarPreparation new];t.pixels=isfinite(maximumPixels)?MAX(1,MIN(160,maximumPixels)):96;t.completion=completion;t.username=username.length<=256?[username copy]:nil;void(^start)(void)=^{if(t.cancelled)return;static dispatch_once_t once;dispatch_once(&once,^{WPQCAvatarWaiting=[NSMutableArray new];WPQCAvatarQueue=dispatch_queue_create("dev.zhour.wechatpet.local-avatars",DISPATCH_QUEUE_SERIAL);});if(WPQCAvatarWaiting.count>=12){void(^done)(UIImage*)=t.completion;t.completion=nil;t.username=nil;if(done)dispatch_async(dispatch_get_main_queue(),^{if(!t.cancelled)done(nil);});return;}[WPQCAvatarWaiting addObject:t];WPQCAvatarPump();};if(NSThread.isMainThread)start();else dispatch_async(dispatch_get_main_queue(),start);return t;}

#if defined(WP_PREVIEW_HOST)
NSDictionary *WPPreviewLocalAvatarPreparationState(void){if(!NSThread.isMainThread)return @{};NSUInteger inputs=0;for(WPQuickChatAvatarPreparation*t in WPQCAvatarWaiting)@synchronized(t){if(t.input)inputs++;}return @{@"waiting":@(WPQCAvatarWaiting.count),@"waitingNativeInputs":@(inputs),@"working":@(WPQCAvatarWorking),@"waitingLimit":@12};}
#endif
WPQuickChatUnreadState WPQuickChatUnreadStateForUsername(NSString *username){
    if(!NSThread.isMainThread || ![username isKindOfClass:NSString.class] || !username.length || username.length>256)return WPQuickChatUnreadStateUnknown;
    NSTimeInterval now=CACurrentMediaTime();
    NSDictionary *cached=WPQCUnreadSnapshots[username];
    if(cached && now-[cached[@"time"] doubleValue]<.25)return [cached[@"state"] integerValue];
    id manager=WPWeChatService(@"MMNewSessionMgr");
    NSMethodSignature *lookup=WPQCSignature(manager,@"GetSessionByUserName:",1);
    WPQuickChatUnreadState state=WPQuickChatUnreadStateUnknown;
    if(lookup && WPQCObjectType(lookup.methodReturnType) && WPQCObjectType([lookup getArgumentTypeAtIndex:2])){
        state=WPQCUnreadStateFromSession(WPQCObjectArgument(manager,@"GetSessionByUserName:",username),username,manager);
    }else{
        // Index-only builds inspect a bounded top window, never a full scan.
        WPQuickChatSource *source=[WPQuickChatSource current];NSTimeInterval began=CACurrentMediaTime();
        for(NSUInteger i=0;i<MIN(WPQCWindow,source.count);i++){
            id session=[source objectAtIndex:i];
            if([WPQCUsername(session) isEqual:username]){state=WPQCUnreadStateFromSession(session,username,manager);break;}
            if(CACurrentMediaTime()-began>.003)break;
        }
    }
    if(!WPQCUnreadSnapshots)WPQCUnreadSnapshots=[NSMutableDictionary new];
    if(WPQCUnreadSnapshots.count>=128 && !WPQCUnreadSnapshots[username])[WPQCUnreadSnapshots removeAllObjects];
    WPQCUnreadSnapshots[username]=@{@"time":@(now),@"state":@(state)};return state;
}
static NSString *WPQCDisplayNameForContact(id contact,NSString *username,BOOL preferRemark){
    NSString *actual=WPQCValue(contact,@[@"m_nsUsrName",@"m_nsUserName"],NSString.class);if(![actual isEqual:username])return @"";
    NSArray *keys=preferRemark?@[@"m_nsRemark",@"m_nsNickName"]:@[@"m_nsNickName"];NSString *name=@"";
    for(NSString *key in keys){NSString *value=WPQCValue(contact,@[key],NSString.class);value=[value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if(value.length){name=value;break;}}
    if(!name.length || [name isEqual:username])return @"";
    name=[[name stringByReplacingOccurrencesOfString:@"\r" withString:@" "] stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    __block NSUInteger count=0,end=0;[name enumerateSubstringsInRange:NSMakeRange(0,name.length) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(__unused NSString *part,NSRange range,__unused NSRange enclosing,BOOL *stop){if(count++>=24){*stop=YES;return;}end=NSMaxRange(range);}];
    return end<name.length?[name substringToIndex:end]:name;
}
NSString *WPQuickChatDisplayName(NSString *username,BOOL preferRemark){
    if(!NSThread.isMainThread || ![username isKindOfClass:NSString.class] || !username.length || username.length>256)return @"";
    id contacts=WPWeChatService(@"CContactMgr");id contact=WPQCObjectArgument(contacts,@"getContactByName:",username);
    if(!contact)contact=WPQCObjectArgument(contacts,@"getContactByNameFromDB:",username);
    return WPQCDisplayNameForContact(contact,username,preferRemark);
}
#if defined(WP_PREVIEW_HOST)
WPQuickChatUnreadState WPPreviewQuickChatUnreadState(id session,NSString *username,id manager){return WPQCUnreadStateFromSession(session,username,manager);}
NSString *WPPreviewQuickChatDisplayName(id contact,NSString *username,BOOL preferRemark){return WPQCDisplayNameForContact(contact,username,preferRemark);}
#endif
NSURL *WPQuickChatAvatarURL(NSString *username){
    if(!NSThread.isMainThread)return nil;
    if(!username.length)return nil;
    id contacts=WPWeChatService(@"CContactMgr");
    id contact=WPQCObjectArgument(contacts,@"getContactByName:",username);
    if(!contact)contact=WPQCObjectArgument(contacts,@"getContactByNameFromDB:",username);
    NSString *actual=WPQCValue(contact,@[@"m_nsUsrName",@"m_nsUserName"],NSString.class);
    if(![actual isEqualToString:username])return nil;
    NSString *address=WPQCValue(contact,@[@"m_nsHeadImgUrl"],NSString.class);
    if(!address.length)address=WPQCValue(contact,@[@"m_nsHeadHDImgUrl"],NSString.class);
    if(!address.length)return nil;
    NSURLComponents *parts=[NSURLComponents componentsWithString:address];
    NSString *scheme=parts.scheme.lowercaseString;
    if(!parts.host.length || !([scheme isEqualToString:@"https"] || [scheme isEqualToString:@"http"]))return nil;
    // Historical contact records often keep qpic links as HTTP; current iOS
    // transport policy can block them even when the HTTPS endpoint is available.
    if([scheme isEqualToString:@"http"] && ([parts.host.lowercaseString hasSuffix:@".qpic.cn"] || [parts.host.lowercaseString isEqualToString:@"qpic.cn"] || [parts.host.lowercaseString hasSuffix:@".qlogo.cn"] || [parts.host.lowercaseString isEqualToString:@"qlogo.cn"]))parts.scheme=@"https";
    return [parts.scheme.lowercaseString isEqualToString:@"https"] ? parts.URL : nil;
}

#pragma mark - Monitor

@interface WPQuickChatMonitor ()
@property(nonatomic) WPQuickChatTracker *tracker;
@property(nonatomic) NSTimer *timer;
@property(nonatomic) NSTimer *nativeRefreshTimer;
@property(nonatomic) NSTimeInterval lastNativeSignal;
@property(nonatomic) NSTimeInterval lastFullScan;
@property(nonatomic) BOOL active;
@property(nonatomic) BOOL foregroundAvailable;
@property(nonatomic) WPNativeRefreshGate *nativeGate;
@property(nonatomic) NSUInteger activationGeneration;
@property(nonatomic) BOOL initialTickPending;
@property(nonatomic) NSUInteger unavailableReads;
@property(nonatomic) NSTimeInterval serviceRetryAfter;
@property(nonatomic) NSUInteger ticks;
@property(nonatomic) NSUInteger scanGeneration;
@property(nonatomic) BOOL scanning;
@property(nonatomic) NSMutableDictionary *state;
@property(nonatomic,copy) NSString *latestArrivalUsername;
@property(nonatomic) NSMutableDictionary<NSString *,WPQuickChatSession *> *observedUnread;
@property(nonatomic) NSMutableDictionary<NSString *,NSNumber *> *observedRanks;
@property(nonatomic,readwrite,copy) NSString *latestObservedUnreadUsername;
@property(nonatomic) NSTimeInterval latestPublishedUnreadTime;
@property(nonatomic) NSUInteger latestPublishedUnreadCount;
@property(nonatomic,copy) NSArray<WPQuickChatSession*> *cachedDisplayRows;
@property(nonatomic) NSTimeInterval displayBuiltAt;
@property(nonatomic) NSUInteger displayGeneration;
@property(nonatomic) BOOL displayScanning;
@end
@implementation WPQuickChatMonitor
+ (instancetype)sharedMonitor{static WPQuickChatMonitor *instance;static dispatch_once_t once;dispatch_once(&once,^{instance=[self new];os_unfair_lock_lock(&WPQCMonitorPublicationLock);WPQCExistingMonitor=instance;WPQCNativeGate=instance.nativeGate;os_unfair_lock_unlock(&WPQCMonitorPublicationLock);});return instance;}
- (instancetype)init {
    if((self=[super init])){
        _tracker=[WPQuickChatTracker new];_state=[@{@"state":@"inactive"} mutableCopy];_observedUnread=[NSMutableDictionary new];_observedRanks=[NSMutableDictionary new];
        _foregroundAvailable=UIApplication.sharedApplication.applicationState==UIApplicationStateActive;
        __weak typeof(self) weakSelf=self;
        _nativeGate=[[WPNativeRefreshGate alloc] initWithQueue:dispatch_get_main_queue() delay:.15 delivery:^(__unused NSUInteger generation){[weakSelf nativeMessageArrived];}];
        NSNotificationCenter *center=NSNotificationCenter.defaultCenter;
        [center addObserver:self selector:@selector(displaySettingsChanged:) name:WPSettingsDidChangeNotification object:nil];
        [center addObserver:self selector:@selector(clearDisplayCache:) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
        [center addObserver:self selector:@selector(messageArrived:) name:WPMessageBarrageDidReceiveNotification object:nil];
        [center addObserver:self selector:@selector(pollModeChanged:) name:WPMessageBarrageSourceStatusDidChangeNotification object:nil];
        [center addObserver:self selector:@selector(chatPresentationChanged:) name:WPChatPresentationDidChangeNotification object:nil];
        [center addObserver:self selector:@selector(foregroundNotification:) name:UIApplicationDidBecomeActiveNotification object:nil];
        [center addObserver:self selector:@selector(foregroundNotification:) name:UIApplicationWillResignActiveNotification object:nil];
        [center addObserver:self selector:@selector(foregroundNotification:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    }return self;
}
- (void)dealloc{[self.nativeGate setEnabled:NO foreground:NO];[self.timer invalidate];[self.nativeRefreshTimer invalidate];[NSNotificationCenter.defaultCenter removeObserver:self];}
- (void)messageArrived:(NSNotification *)note {[self.nativeGate signal];}
- (void)nativeMessageArrived{
    if(!self.active || !self.foregroundAvailable)return;
    self.lastNativeSignal=CACurrentMediaTime();WPQCInvalidateUnreadSnapshots();
    if(!self.initialTickPending)[self tick];
}
- (void)chatPresentationChanged:(NSNotification *)note{[self.nativeGate signal];}
- (void)foregroundNotification:(NSNotification *)note {[self setForegroundAvailable:[note.name isEqual:UIApplicationDidBecomeActiveNotification]];}
- (void)setForegroundAvailable:(BOOL)available {
    if(!NSThread.isMainThread)return;
    WPSESetForegroundAvailable(available);
    if(self.foregroundAvailable==available)return;
    _foregroundAvailable=available;self.activationGeneration++;self.scanGeneration++;self.scanning=NO;self.initialTickPending=NO;
    [self.nativeGate setEnabled:self.active foreground:available];
    [self.timer invalidate];self.timer=nil;[self.nativeRefreshTimer invalidate];self.nativeRefreshTimer=nil;
    if(available && self.active)[self scheduleInitialTick];
}
- (void)scheduleInitialTick {
    if(self.initialTickPending || !self.active || !self.foregroundAvailable)return;
    self.initialTickPending=YES;NSUInteger generation=self.activationGeneration;__weak typeof(self) weakSelf=self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,120*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        WPQuickChatMonitor *self=weakSelf;
        if(!self || generation!=self.activationGeneration || !self.active || !self.foregroundAvailable)return;
        self.initialTickPending=NO;[self tick];
    });
}
- (void)pollModeChanged:(NSNotification *)note{
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{[self pollModeChanged:note];});return;}[self schedulePoll];
}
- (void)schedulePoll{
    [self.timer invalidate];self.timer=nil;if(!self.active || !self.foregroundAvailable)return;
    BOOL safetyPolling=WPBarrageEnabled() && WPMessageBarrageSource.sharedSource.requiresSessionPolling;
    // One observed native route cannot prove coverage of every receive route.
    // Keep the bounded two-second arrival safety poll while barrage is enabled.
    BOOL nativeHealthy=!safetyPolling && ((self.lastNativeSignal>0 && CACurrentMediaTime()-self.lastNativeSignal<120) || !WPMessageBarrageSource.sharedSource.requiresSessionPolling);
    NSTimeInterval interval=(nativeHealthy || self.unavailableReads>=3)?WPQCIdleInterval:WPQCInterval;
    self.state[@"pollInterval"]=@(interval);
    __weak typeof(self) weakSelf=self;
    self.timer=[NSTimer timerWithTimeInterval:interval repeats:NO block:^(__unused NSTimer *timer){WPQuickChatMonitor *self=weakSelf;if(self){self.timer=nil;[self tick];}}];
    self.timer.tolerance=interval>=8?1:.3;[NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
}
- (void)clearDisplayCache:(NSNotification *)note{
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{[self clearDisplayCache:note];});return;}
    self.cachedDisplayRows=nil;self.displayBuiltAt=0;self.displayGeneration++;self.displayScanning=NO;
    self.scanGeneration++;self.scanning=NO;
    self.lastFullScan=CACurrentMediaTime();WPQCInvalidateUnreadSnapshots();
}
- (void)displaySettingsChanged:(NSNotification*)note {self.displayBuiltAt=0;self.displayGeneration++;self.displayScanning=NO;}
- (BOOL)hasAlertableUnread{return self.observedUnread.count>0;}
- (WPQuickChatSession *)latestObservedUnreadSession{return self.latestObservedUnreadUsername.length?self.observedUnread[self.latestObservedUnreadUsername]:nil;}
- (NSDictionary<NSString *,id> *)diagnostics{NSMutableDictionary *result=self.state.mutableCopy;result[@"nativeRefreshGate"]=self.nativeGate.diagnostics;result[@"activationGeneration"]=@(self.activationGeneration);result[@"initialTickPending"]=@(self.initialTickPending);return result;}
- (void)clearObservations {
    self.tracker=[WPQuickChatTracker new];
    [self.observedUnread removeAllObjects];[self.observedRanks removeAllObjects];
    self.latestArrivalUsername=nil;
}
- (void)retainObservedUsernames:(NSSet<NSString *> *)names {
    if(!names)return;
    for(NSString *name in self.observedUnread.allKeys)if(![names containsObject:name]){
        [self.observedUnread removeObjectForKey:name];[self.observedRanks removeObjectForKey:name];
    }
}
- (void)observeRows:(NSArray<WPQuickChatSession *> *)rows source:(WPQuickChatSource *)source {
    NSMutableSet *eligible=[NSMutableSet new];NSUInteger sortedRank=0;
    for(WPQuickChatSession *row in rows){
        if(!row.alertable)continue;
        [eligible addObject:row.username];self.observedUnread[row.username]=row;
        self.observedRanks[row.username]=source.nativeOrder?(source.lastReadRanks[row.username] ?: @(NSUIntegerMax)):@(sortedRank++);
        // A changing list can briefly contain both old and new scan snapshots.
        // Keep the observation cache bounded even before the final scan purge.
        if(self.observedUnread.count>WPQCMaximumSessionRows){
            NSEnumerator *keys=self.observedUnread.keyEnumerator;NSString *victim=keys.nextObject;
            if([victim isEqual:row.username])victim=keys.nextObject;
            if(victim){[self.observedUnread removeObjectForKey:victim];[self.observedRanks removeObjectForKey:victim];}
        }
    }
    for(NSString *name in source.lastReadUsernames)if(![eligible containsObject:name]){
        [self.observedUnread removeObjectForKey:name];[self.observedRanks removeObjectForKey:name];
    }
    [self retainObservedUsernames:source.homeNames];
}
- (NSString *)latestObservedCandidate {
    NSString *latest=nil;NSTimeInterval latestTime=0;NSUInteger latestRank=NSUIntegerMax;
    for(NSString *name in self.observedUnread){
        WPQuickChatSession *row=self.observedUnread[name];
        NSTimeInterval time=isfinite(row.time)?MAX(0,row.time):0;
        NSUInteger rank=[self.observedRanks[name] unsignedIntegerValue];
        if(!latest || time>latestTime || (time==latestTime && (rank<latestRank || (rank==latestRank && [name compare:latest]==NSOrderedAscending)))){
            latest=name;latestTime=time;latestRank=rank;
        }
    }
    if(latestTime<=0 && self.latestArrivalUsername.length && self.observedUnread[self.latestArrivalUsername])return self.latestArrivalUsername;
    return latest;
}
- (void)setActive:(BOOL)active {
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{[self setActive:active];});return;}
    if(active==_active){if(!active && (self.cachedDisplayRows || self.displayScanning || self.scanning))[self clearDisplayCache:nil];return;}_active=active;self.activationGeneration++;
    [self.nativeGate setEnabled:active foreground:self.foregroundAvailable];
    [self.timer invalidate];self.timer=nil;self.scanGeneration++;self.scanning=NO;self.initialTickPending=NO;
    [self.nativeRefreshTimer invalidate];self.nativeRefreshTimer=nil;
    self.state[@"state"]=active?@"warming":@"inactive";
    BOOL hadUnread=self.hasAlertableUnread;[self clearObservations];
    if(!active){[self clearDisplayCache:nil];[self publish:@[] hadUnread:hadUnread];return;}
    self.ticks=0;self.lastNativeSignal=0;self.lastFullScan=0;self.unavailableReads=0;self.serviceRetryAfter=0;
    [self scheduleInitialTick];
}
- (void)publish:(NSArray<NSString *> *)arrivals hadUnread:(BOOL)hadUnread {
    NSString *latest=[self latestObservedCandidate];
    BOOL changed=!(self.latestObservedUnreadUsername==latest || [self.latestObservedUnreadUsername isEqual:latest]);
    WPQuickChatSession *row=self.observedUnread[latest?:@""];
    NSTimeInterval time=isfinite(row.time)?row.time:0;
    changed|=time!=self.latestPublishedUnreadTime || row.unread!=self.latestPublishedUnreadCount;
    self.latestPublishedUnreadTime=time;self.latestPublishedUnreadCount=row.unread;
    self.latestObservedUnreadUsername=latest;
    self.state[@"alertableUnread"]=@(self.hasAlertableUnread);self.state[@"alertableUnreadCount"]=@(self.observedUnread.count);
    if(!arrivals.count && hadUnread==self.hasAlertableUnread && !changed)return;
    [NSNotificationCenter.defaultCenter postNotificationName:WPQuickChatDidChangeNotification object:self userInfo:@{@"arrivals":arrivals}];
}
- (void)tick {
    if(!self.active || !self.foregroundAvailable || self.initialTickPending)return;
    NSTimeInterval now=CACurrentMediaTime();
    if(now<self.serviceRetryAfter){[self schedulePoll];return;}
    WPQCInvalidateUnreadSnapshots();[self performTick];
    NSTimeInterval milliseconds=(CACurrentMediaTime()-now)*1000;
    self.state[@"lastTickMs"]=@(milliseconds);self.state[@"maximumTickMs"]=@(MAX(milliseconds,[self.state[@"maximumTickMs"] doubleValue]));
    if(milliseconds>100){self.serviceRetryAfter=CACurrentMediaTime()+8;self.scanGeneration++;self.scanning=NO;self.state[@"state"]=@"degraded-slow-service";}
    [self schedulePoll];
}
- (void)performTick {
    if(!self.active || !self.foregroundAvailable)return;
    WPSEInvalidateHomeNames();
    WPQuickChatSource *source=[WPQuickChatSource current];
    self.state[@"route"]=source.route ?: @"unavailable";self.state[@"sessionCount"]=@(source.count);
    BOOL hadUnread=self.hasAlertableUnread;
    if(!source){self.unavailableReads++;self.state[@"unavailableReads"]=@(self.unavailableReads);self.state[@"state"]=@"waiting-for-session-service";if(self.unavailableReads>=3)self.serviceRetryAfter=CACurrentMediaTime()+8;return;}
    self.unavailableReads=0;self.state[@"state"]=@"active";
    NSArray *arrivals;
    if(source.nativeOrder){
        NSArray *top=[source sessionsInRange:NSMakeRange(0,WPQCWindow)];
        arrivals=[self.tracker observe:top reportArrivals:YES];
        [self observeRows:top source:source];
        if(!self.lastFullScan || CACurrentMediaTime()-self.lastFullScan>=WPQCFullScanInterval){
            self.lastFullScan=CACurrentMediaTime();NSUInteger generation=self.activationGeneration;__weak typeof(self) weakSelf=self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),dispatch_get_main_queue(),^{WPQuickChatMonitor *self=weakSelf;if(self && self.active && self.foregroundAvailable && generation==self.activationGeneration)[self scan:source];});
        }
        self.ticks++;
    } else {
        [self scanUnordered:source];arrivals=@[];self.ticks++;
    }
    if(arrivals.count)self.latestArrivalUsername=arrivals.firstObject;
    self.state[@"lastArrivals"]=@(arrivals.count);
    [self publish:arrivals hadUnread:hadUnread];
}
/// Older rows update the unread avatar without treating old unread as arrivals.
- (void)scan:(WPQuickChatSource *)source {
    if(self.scanning)return;self.scanning=YES;
    NSUInteger generation=++self.scanGeneration;NSMutableSet *seen=[NSMutableSet new];
    __block NSUInteger index=0;__weak typeof(self) weakSelf=self;__block void (^step)(void);
    step=^{
        WPQuickChatMonitor *monitor=weakSelf;
        if(!monitor || generation!=monitor.scanGeneration || !monitor.active || !monitor.foregroundAvailable){step=nil;return;}
        BOOL hadUnread=monitor.hasAlertableUnread;
        NSArray *rows=[source sessionsInRange:NSMakeRange(index,WPQCScanBatch)];index=source.lastReadEnd;monitor.state[@"maxRowsPerTurn"]=@150;
        [monitor.tracker observe:rows reportArrivals:NO];[seen addObjectsFromArray:[rows valueForKey:@"username"]];
        [monitor observeRows:rows source:source];
        if(index>=source.count){
            // Rows read before a reorder can show up twice or be missed; the
            // window poll keeps the top exact and the next scan settles the rest.
            [monitor.tracker retainOnlyUsernames:seen];monitor.scanning=NO;monitor.state[@"lastScanRows"]=@(seen.count);step=nil;
            [monitor retainObservedUsernames:seen];
        } else dispatch_after(dispatch_time(DISPATCH_TIME_NOW,8*NSEC_PER_MSEC),dispatch_get_main_queue(),step);
        [monitor publish:@[] hadUnread:hadUnread];
    };
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,8*NSEC_PER_MSEC),dispatch_get_main_queue(),step);
}
- (void)scanUnordered:(WPQuickChatSource*)source {
    if(self.scanning)return;self.scanning=YES;NSUInteger generation=++self.scanGeneration;NSMutableArray*all=[NSMutableArray new];__block NSUInteger index=0;__weak typeof(self)weakSelf=self;__block void(^step)(void);
    step=^{WPQuickChatMonitor*m=weakSelf;if(!m||!m.active||!m.foregroundAvailable||generation!=m.scanGeneration){step=nil;return;}[all addObjectsFromArray:[source sessionsInRange:NSMakeRange(index,150)]];index=source.lastReadEnd;m.state[@"maxRowsPerTurn"]=@150;if(index<source.count){dispatch_after(dispatch_time(DISPATCH_TIME_NOW,8*NSEC_PER_MSEC),dispatch_get_main_queue(),step);return;}step=nil;dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{NSArray*ordered=WPQuickChatOrdered(all,NO);dispatch_async(dispatch_get_main_queue(),^{if(!m.active||!m.foregroundAvailable||generation!=m.scanGeneration)return;BOOL had=m.hasAlertableUnread;NSUInteger split=MIN(60,ordered.count);NSArray*arrivals=[m.tracker observe:[ordered subarrayWithRange:NSMakeRange(0,split)] reportArrivals:YES];[m.tracker observe:[ordered subarrayWithRange:NSMakeRange(split,ordered.count-split)] reportArrivals:NO];NSSet*seen=[NSSet setWithArray:[ordered valueForKey:@"username"]];[m.tracker retainOnlyUsernames:seen];[m observeRows:ordered source:source];[m retainObservedUsernames:seen];m.scanning=NO;m.state[@"lastScanRows"]=@(ordered.count);if(arrivals.count)m.latestArrivalUsername=arrivals.firstObject;[m publish:arrivals hadUnread:had];});});};dispatch_after(dispatch_time(DISPATCH_TIME_NOW,8*NSEC_PER_MSEC),dispatch_get_main_queue(),step);
}
- (NSArray<WPQuickChatSession *> *)currentSessions {
    if(!NSThread.isMainThread)return nil;
    @try{WPQuickChatSource*source=[WPQuickChatSource current];if(!source)return nil;
        if(self.displayScanning)return self.cachedDisplayRows?:@[];
        if(self.cachedDisplayRows&&NSDate.date.timeIntervalSince1970-self.displayBuiltAt<1)return self.cachedDisplayRows;
        source.displayOptions=YES;
        if(WPQuickChatOptionBool(@"showFolded")){id list=WPQCObject(source.manager,@"GetSessionInfoList");if([list isKindOfClass:NSArray.class]&&source.homeNames){source.route=@"list";source.items=[list copy];source.count=MIN([list count],WPQCMaximumSessionRows);source.nativeOrder=NO;}}
        NSMutableArray*all=[NSMutableArray arrayWithArray:[source sessionsInRange:NSMakeRange(0,150)]];NSUInteger firstEnd=source.lastReadEnd;
        if(firstEnd>=source.count){self.cachedDisplayRows=WPQuickChatOrdered(all,source.nativeOrder);self.displayBuiltAt=NSDate.date.timeIntervalSince1970;self.state[@"barRows"]=@(self.cachedDisplayRows.count);return self.cachedDisplayRows;}
        self.displayScanning=YES;NSUInteger generation=++self.displayGeneration;__block NSUInteger index=firstEnd;__weak typeof(self)weakSelf=self;__block void(^step)(void);
        step=^{WPQuickChatMonitor*m=weakSelf;if(!m||generation!=m.displayGeneration){step=nil;return;}[all addObjectsFromArray:[source sessionsInRange:NSMakeRange(index,150)]];index=source.lastReadEnd;m.state[@"maxRowsPerTurn"]=@150;if(index<source.count){dispatch_after(dispatch_time(DISPATCH_TIME_NOW,8*NSEC_PER_MSEC),dispatch_get_main_queue(),step);return;}step=nil;dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{NSArray*ordered=WPQuickChatOrdered(all,source.nativeOrder);dispatch_async(dispatch_get_main_queue(),^{if(generation!=m.displayGeneration)return;m.cachedDisplayRows=ordered;m.displayBuiltAt=NSDate.date.timeIntervalSince1970;m.displayScanning=NO;m.state[@"barRows"]=@(ordered.count);[NSNotificationCenter.defaultCenter postNotificationName:WPQuickChatDidChangeNotification object:m userInfo:@{@"arrivals":@[],@"sessionsUpdated":@YES}];});});};dispatch_after(dispatch_time(DISPATCH_TIME_NOW,8*NSEC_PER_MSEC),dispatch_get_main_queue(),step);
        if(!self.cachedDisplayRows)self.cachedDisplayRows=WPQuickChatOrdered(all,source.nativeOrder);return self.cachedDisplayRows;
    }@catch(__unused NSException*exception){return nil;}
}
- (NSString *)latestUnreadUsername {
    if(!NSThread.isMainThread)return nil;
    // A message may arrive between polls and a tap. Refresh only the bounded
    // native top window; never turn navigation into a full session-list scan.
    WPQuickChatSource *source=[WPQuickChatSource current];
    NSArray *top=[source sessionsInRange:NSMakeRange(0,WPQCWindow)];
    BOOL hadUnread=self.hasAlertableUnread;
    [self.tracker observe:top reportArrivals:NO];
    [self observeRows:top source:source];
    [self publish:@[] hadUnread:hadUnread];
    NSString *name=self.latestObservedUnreadUsername;if(!name.length)return nil;
    id manager=WPWeChatService(@"MMNewSessionMgr"),session=WPQCObjectArgument(manager,@"GetSessionByUserName:",name);NSSet*home=WPSEHomeNames(manager);
    if(!session){for(WPQuickChatSession*row in top)if([row.username isEqual:name]&&row.alertable)return name;return nil;}
    if(!WPQCIsHomeSession(session,name,home)||!WPQCSession(session,name).alertable)return nil;return name;
}
@end

void WPQuickChatNotifyNativeMessage(void){
    os_unfair_lock_lock(&WPQCMonitorPublicationLock);WPNativeRefreshGate *gate=WPQCNativeGate;os_unfair_lock_unlock(&WPQCMonitorPublicationLock);
    [gate signal];
}
void WPQuickChatSetForegroundAvailable(BOOL available){
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{WPQuickChatSetForegroundAvailable(available);});return;}
    os_unfair_lock_lock(&WPQCMonitorPublicationLock);WPQuickChatMonitor *monitor=WPQCExistingMonitor;os_unfair_lock_unlock(&WPQCMonitorPublicationLock);
    [monitor setForegroundAvailable:available];
}
