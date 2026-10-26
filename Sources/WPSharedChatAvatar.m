#import "WPSharedChatAvatar.h"
#import "WPQuickChat.h"
#import "WPChatAvatarDownload.h"

static const NSUInteger WPAvatarCacheLimit=16, WPAvatarCacheBytes=1536*1024, WPAvatarJobLimit=24, WPAvatarConcurrency=2;
@class WPSharedAvatarStore;
@interface WPSharedChatAvatarRequest ()
@property(atomic) BOOL cancelled;
@property(nonatomic,copy) void (^completion)(UIImage *);
@property(nonatomic,copy) void (^cancelWork)(void);
@end
@implementation WPSharedChatAvatarRequest
- (void)cancel {
    void (^cancelWork)(void)=nil;
    @synchronized(self){self.cancelled=YES;self.completion=nil;cancelWork=self.cancelWork;self.cancelWork=nil;}
    if(cancelWork){if(NSThread.isMainThread)cancelWork();else dispatch_async(dispatch_get_main_queue(),cancelWork);}
}
@end
@interface WPSharedAvatarEntry : NSObject
@property(nonatomic,strong) UIImage *image;
@property(nonatomic) NSUInteger bytes;
@property(nonatomic) NSTimeInterval created,used;
@end
@implementation WPSharedAvatarEntry @end
@interface WPSharedAvatarJob : NSObject
@property(nonatomic,copy) NSString *username;
@property(nonatomic,strong) NSMutableArray<WPSharedChatAvatarRequest *> *subscribers;
@property(nonatomic,strong) WPQuickChatAvatarPreparation *preparation;
@property(nonatomic,strong) WPQCAvatarDownload *download;
@property(nonatomic) BOOL started,cancelled;
@end
@implementation WPSharedAvatarJob @end
@interface WPSharedAvatarStore : NSObject
@property(nonatomic,strong) NSMutableDictionary<NSString *,WPSharedAvatarEntry *> *cache;
@property(nonatomic,strong) NSMutableDictionary<NSString *,WPSharedAvatarJob *> *jobs;
@property(nonatomic,strong) NSMutableArray<WPSharedAvatarJob *> *waiting;
@property(nonatomic) NSUInteger bytes,active,completed,coalesced;
@property(nonatomic) CFTimeInterval cooldownUntil;
@property(nonatomic) BOOL backgroundSuspended;
+ (instancetype)shared;
- (void)pump;
- (void)finish:(WPSharedAvatarJob *)job image:(UIImage *)image;
- (void)purge;
@end
static void WPDeliverAvatar(WPSharedChatAvatarRequest *request,UIImage *image){
    dispatch_async(dispatch_get_main_queue(),^{
        void (^completion)(UIImage *)=nil;
        @synchronized(request){if(!request.cancelled)completion=request.completion;request.completion=nil;request.cancelWork=nil;}
        if(completion)completion(image);
    });
}
#if defined(WP_PREVIEW_HOST)
static void (^WPSharedAvatarFixtureProvider)(NSString *,void(^)(UIImage *));
#endif
@implementation WPSharedAvatarStore
+ (instancetype)shared{static WPSharedAvatarStore *store;static dispatch_once_t once;dispatch_once(&once,^{store=[self new];});return store;}
- (instancetype)init{if((self=[super init])){_cache=[NSMutableDictionary new];_jobs=[NSMutableDictionary new];_waiting=[NSMutableArray new];NSNotificationCenter *center=NSNotificationCenter.defaultCenter;[center addObserver:self selector:@selector(purgeNotification:) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];[center addObserver:self selector:@selector(purgeNotification:) name:UIApplicationDidEnterBackgroundNotification object:nil];[center addObserver:self selector:@selector(foreground:) name:UIApplicationWillEnterForegroundNotification object:nil];}return self;}
- (void)purgeNotification:(NSNotification *)note{
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{[self purgeNotification:note];});return;}
    if([note.name isEqual:UIApplicationDidEnterBackgroundNotification])self.backgroundSuspended=YES;
    else self.cooldownUntil=CACurrentMediaTime()+8;
    [self purge];
}
- (void)foreground:(NSNotification *)note{if(NSThread.isMainThread)self.backgroundSuspended=NO;else dispatch_async(dispatch_get_main_queue(),^{self.backgroundSuspended=NO;});}
- (void)removeCache:(NSString *)name{WPSharedAvatarEntry *entry=self.cache[name];if(entry){self.bytes-=entry.bytes;[self.cache removeObjectForKey:name];}}
- (UIImage *)cached:(NSString *)name{
    if(![name isKindOfClass:NSString.class] || !name.length)return nil;
    WPSharedAvatarEntry *entry=self.cache[name];if(!entry)return nil;
    NSTimeInterval now=CACurrentMediaTime();if(now-entry.created>=60){[self removeCache:name];return nil;}entry.used=now;return entry.image;
}
- (void)store:(UIImage *)image username:(NSString *)name{
    CGImageRef cg=image.CGImage;if(!cg || !name.length || CGImageGetWidth(cg)>160 || CGImageGetHeight(cg)>160)return;NSUInteger bytes=CGImageGetBytesPerRow(cg)*CGImageGetHeight(cg);if(!bytes||bytes>WPAvatarCacheBytes)return;
    [self removeCache:name];
    while(self.cache.count>=WPAvatarCacheLimit || self.bytes+bytes>WPAvatarCacheBytes){
        NSString *oldest=nil;NSTimeInterval at=DBL_MAX;for(NSString *key in self.cache){if(self.cache[key].used<at){at=self.cache[key].used;oldest=key;}}if(!oldest)break;[self removeCache:oldest];
    }
    WPSharedAvatarEntry *entry=[WPSharedAvatarEntry new];entry.image=image;entry.bytes=bytes;entry.created=entry.used=CACurrentMediaTime();self.cache[name]=entry;self.bytes+=bytes;
}
- (void)cancelSubscriber:(WPSharedChatAvatarRequest *)request job:(WPSharedAvatarJob *)job{
    if(!request || !job)return;
    [job.subscribers removeObjectIdenticalTo:request];request.cancelWork=nil;
    if(job.subscribers.count || self.jobs[job.username]!=job)return;
    job.cancelled=YES;[job.preparation cancel];[job.download cancel];job.preparation=nil;job.download=nil;[self.waiting removeObjectIdenticalTo:job];[self.jobs removeObjectForKey:job.username];if(job.started&&self.active)self.active--;[self pump];
}
- (void)request:(WPSharedChatAvatarRequest *)request username:(NSString *)name{
    if(request.cancelled)return;
    if(![name isKindOfClass:NSString.class] || !name.length || name.length>256 || self.backgroundSuspended || UIApplication.sharedApplication.applicationState==UIApplicationStateBackground || CACurrentMediaTime()<self.cooldownUntil){WPDeliverAvatar(request,nil);return;}
    UIImage *image=[self cached:name];if(image){WPDeliverAvatar(request,image);return;}
    WPSharedAvatarJob *job=self.jobs[name];
    if(!job){if(self.jobs.count>=WPAvatarJobLimit){WPDeliverAvatar(request,nil);return;}job=[WPSharedAvatarJob new];job.username=name;job.subscribers=[NSMutableArray new];self.jobs[name]=job;[self.waiting addObject:job];}else self.coalesced++;
    [job.subscribers addObject:request];
    __weak WPSharedChatAvatarRequest *weakRequest=request;__weak WPSharedAvatarJob *weakJob=job;
    @synchronized(request){if(!request.cancelled)request.cancelWork=^{[self cancelSubscriber:weakRequest job:weakJob];};}
    if(request.cancelled)[self cancelSubscriber:request job:job];else [self pump];
}
- (void)pump{
    if(self.backgroundSuspended || CACurrentMediaTime()<self.cooldownUntil)return;
    while(self.active<WPAvatarConcurrency && self.waiting.count){
        WPSharedAvatarJob *job=self.waiting.firstObject;[self.waiting removeObjectAtIndex:0];if(job.cancelled)continue;job.started=YES;self.active++;
        __weak WPSharedAvatarJob *weakJob=job;
#if defined(WP_PREVIEW_HOST)
        if(WPSharedAvatarFixtureProvider){WPSharedAvatarFixtureProvider(job.username,^(UIImage *image){WPSharedAvatarJob *current=weakJob;if(current)[self finish:current image:image];});continue;}
#endif
        job.preparation=WPQuickChatPrepareAvatar(job.username,160,^(UIImage *image){
            WPSharedAvatarJob *current=weakJob;if(!current||current.cancelled||self.jobs[current.username]!=current)return;current.preparation=nil;
            if(image){[self finish:current image:image];return;}
            NSURL *url=WPQuickChatAvatarURL(current.username);if(![url.scheme.lowercaseString isEqual:@"https"]){[self finish:current image:nil];return;}
            current.download=[[WPQCAvatarDownload alloc]initWithURL:url maximumBytes:1024*1024 maximumPixels:160 completion:^(UIImage *downloaded){WPSharedAvatarJob *finished=weakJob;if(finished)[self finish:finished image:downloaded];}];[current.download start];
        });
    }
}
- (void)finish:(WPSharedAvatarJob *)job image:(UIImage *)image{
    if(job.cancelled || self.jobs[job.username]!=job)return;
    job.preparation=nil;job.download=nil;[self.jobs removeObjectForKey:job.username];if(self.active)self.active--;self.completed++;
    if(image)[self store:image username:job.username];
    NSArray *subscribers=[job.subscribers copy];[job.subscribers removeAllObjects];for(WPSharedChatAvatarRequest *request in subscribers)WPDeliverAvatar(request,image);[self pump];
}
- (void)purge{
    for(WPSharedAvatarJob *job in self.jobs.allValues){job.cancelled=YES;[job.preparation cancel];[job.download cancel];for(WPSharedChatAvatarRequest *request in job.subscribers){request.cancelWork=nil;WPDeliverAvatar(request,nil);}[job.subscribers removeAllObjects];job.preparation=nil;job.download=nil;}
    [self.jobs removeAllObjects];[self.waiting removeAllObjects];[self.cache removeAllObjects];self.bytes=0;self.active=0;
}
@end
WPSharedChatAvatarRequest *WPRequestSharedChatAvatar(NSString *username,void(^completion)(UIImage *)){
    WPSharedChatAvatarRequest *request=[WPSharedChatAvatarRequest new];request.completion=completion;NSString *name=[username isKindOfClass:NSString.class]?[username copy]:nil;
    void(^start)(void)=^{[[WPSharedAvatarStore shared]request:request username:name];};if(NSThread.isMainThread)start();else dispatch_async(dispatch_get_main_queue(),start);return request;
}
UIImage *WPCachedSharedChatAvatar(NSString *username){return NSThread.isMainThread?[[WPSharedAvatarStore shared]cached:username]:nil;}
void WPPurgeSharedChatAvatars(void){if(NSThread.isMainThread)[[WPSharedAvatarStore shared]purge];else dispatch_async(dispatch_get_main_queue(),^{[[WPSharedAvatarStore shared]purge];});}
#if defined(WP_PREVIEW_HOST)
NSDictionary *WPPreviewSharedAvatarState(void){WPSharedAvatarStore *s=WPSharedAvatarStore.shared;return @{@"cached":@(s.cache.count),@"bytes":@(s.bytes),@"jobs":@(s.jobs.count),@"active":@(s.active),@"waiting":@(s.waiting.count),@"completed":@(s.completed),@"coalesced":@(s.coalesced),@"cooldown":@(MAX(0,s.cooldownUntil-CACurrentMediaTime())),@"backgroundSuspended":@(s.backgroundSuspended)};}
void WPPreviewSeedSharedAvatar(NSString *username,UIImage *image){[[WPSharedAvatarStore shared]store:image username:username];}
void WPPreviewSetSharedAvatarProvider(void(^provider)(NSString *,void(^)(UIImage *))){WPSharedAvatarFixtureProvider=[provider copy];}
void WPPreviewSharedAvatarMemoryPressure(void){[[WPSharedAvatarStore shared]purgeNotification:[NSNotification notificationWithName:UIApplicationDidReceiveMemoryWarningNotification object:nil]];}
void WPPreviewResetSharedAvatarState(void){WPSharedAvatarStore *s=WPSharedAvatarStore.shared;[s purge];s.cooldownUntil=0;s.backgroundSuspended=NO;WPSharedAvatarFixtureProvider=nil;}
#endif
