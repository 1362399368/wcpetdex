#import "WPQuickChatBar.h"
#import "WPQuickChat.h"
#import "WPPartnerContact.h"
#import "WPChatAvatarDownload.h"
#import "WPQuickChatPreferences.h"
#import "WPCommon.h"
#import "WPSharedChatAvatar.h"
#import <ImageIO/ImageIO.h>

static const CGFloat WPQCBarAvatar=50;
static const NSUInteger WPQCMaxAvatarAttempts=8;
static const NSUInteger WPQCMaxAvatarBytes=5*1024*1024;
static const size_t WPQCMaxAvatarPixels=160;

static UIColor *WPQCNameColor(UITraitCollection *traits){
    NSInteger mode=(NSInteger)WPQuickChatOptionNumber(@"background");
    if(mode==0)return UIColor.labelColor;
    if(mode==1)return UIColor.blackColor;
    if(mode==2)return UIColor.whiteColor;
    UIColor *background=[WPQuickChatBackgroundColor(traits) resolvedColorWithTraitCollection:traits];
    CGFloat red=0,green=0,blue=0,alpha=1;
    if(![background getRed:&red green:&green blue:&blue alpha:&alpha])return UIColor.labelColor;
    CGFloat (^linear)(CGFloat)=^CGFloat(CGFloat value){return value<=.04045?value/12.92:pow((value+.055)/1.055,2.4);};
    CGFloat luminance=.2126*linear(red)+.7152*linear(green)+.0722*linear(blue);
    return (luminance+.05)/.05>=1.05/(luminance+.05)?UIColor.blackColor:UIColor.whiteColor;
}

static NSUInteger WPQCAvatarCost(UIImage *image) {
    CGImageRef cg=image.CGImage;
    return cg ? CGImageGetBytesPerRow(cg)*CGImageGetHeight(cg) : 0;
}
static UIImage *WPQCDecodeAvatar(NSData *data, NSUInteger maximumPixels) {
    CGImageSourceRef source=CGImageSourceCreateWithData((__bridge CFDataRef)data,(__bridge CFDictionaryRef)@{(id)kCGImageSourceShouldCache:@NO});
    if(!source)return nil;
    NSDictionary *properties=CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source,0,NULL));
    double width=[properties[(id)kCGImagePropertyPixelWidth] doubleValue],height=[properties[(id)kCGImagePropertyPixelHeight] doubleValue];
    if(!isfinite(width) || !isfinite(height) || width<1 || height<1 || width>8192 || height>8192 || width*height>16*1024*1024){CFRelease(source);return nil;}
    CGImageRef thumbnail=CGImageSourceCreateThumbnailAtIndex(source,0,(__bridge CFDictionaryRef)@{
        (id)kCGImageSourceCreateThumbnailFromImageAlways:@YES,
        (id)kCGImageSourceCreateThumbnailWithTransform:@YES,
        (id)kCGImageSourceThumbnailMaxPixelSize:@(maximumPixels),
        (id)kCGImageSourceShouldCacheImmediately:@YES});
    CFRelease(source);
    UIImage *image=thumbnail?[UIImage imageWithCGImage:thumbnail]:nil;
    if(thumbnail)CGImageRelease(thumbnail);
    return image;
}

// CContact keeps the same head-image URL used by WeChat. On the user's WeChat
// 8.0.79 build MMHeadImageMgr does not exist, so fetch that URL off the UI
// thread. Each transfer is capped before buffering the response in memory.
@interface WPQCAvatarDownload () <NSURLSessionDataDelegate, NSURLSessionTaskDelegate>
@property(nonatomic,strong) NSURL *url;
@property(nonatomic,strong) NSURLSession *session;
@property(nonatomic,strong) NSURLSessionDataTask *task;
@property(nonatomic,strong) NSMutableData *bytes;
@property(nonatomic,strong) NSData *decodeData;
@property(nonatomic,copy) void (^completion)(UIImage *image);
@property(nonatomic) BOOL finished;
@property(nonatomic) BOOL cancelled;
@property(nonatomic) BOOL started;
@property(nonatomic) BOOL decoding;
@property(nonatomic) NSUInteger maximumBytes;
@property(nonatomic) NSUInteger maximumPixels;
- (instancetype)initWithURL:(NSURL *)url completion:(void (^)(UIImage *))completion;
- (void)start;
- (void)cancel;
@end
@implementation WPQCAvatarDownload
- (instancetype)initWithURL:(NSURL *)url completion:(void (^)(UIImage *))completion {
    return [self initWithURL:url maximumBytes:WPQCMaxAvatarBytes maximumPixels:WPQCMaxAvatarPixels completion:completion];
}
- (instancetype)initWithURL:(NSURL *)url maximumBytes:(NSUInteger)maximumBytes maximumPixels:(CGFloat)maximumPixels completion:(void (^)(UIImage *))completion {
    if((self=[super init])) {
        _url=url;_completion=[completion copy];
        _maximumBytes=maximumBytes?MIN(maximumBytes,WPQCMaxAvatarBytes):WPQCMaxAvatarBytes;
        _maximumPixels=isfinite(maximumPixels)&&maximumPixels>0?(NSUInteger)MAX(1,MIN(WPQCMaxAvatarPixels,floor(maximumPixels))):WPQCMaxAvatarPixels;
    }
    return self;
}
- (void)start {
    @synchronized(self) {
    if(self.started || self.finished || self.cancelled)return;
    self.started=YES;
    NSURLSessionConfiguration *config=NSURLSessionConfiguration.ephemeralSessionConfiguration;
    config.timeoutIntervalForRequest=10;config.timeoutIntervalForResource=15;config.HTTPMaximumConnectionsPerHost=2;
    config.URLCache=nil;config.HTTPCookieStorage=nil;config.requestCachePolicy=NSURLRequestReloadIgnoringLocalCacheData;
#if defined(WP_PREVIEW_HOST)
    Class preview=NSClassFromString(@"WPQCAvatarURLProtocol");if(preview)config.protocolClasses=@[preview];
#endif
    // Transfer buffers are protected by the existing lock; keep chunk handling
    // off the UI queue as well as image preparation.
    NSOperationQueue *delegateQueue=[NSOperationQueue new];delegateQueue.maxConcurrentOperationCount=1;delegateQueue.qualityOfService=NSQualityOfServiceUtility;
    self.session=[NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:delegateQueue];
    self.task=[self.session dataTaskWithURL:self.url];[self.task resume];
    }
}
- (void)finish:(UIImage *)image {
    NSURLSession *session=nil;BOOL deliver=NO;
    @synchronized(self) {
        if(self.finished)return;self.finished=YES;
        self.bytes=nil;self.decodeData=nil;
        session=self.session;self.session=nil;self.task=nil;
        deliver=self.completion!=nil && !self.cancelled;
    }
    [session invalidateAndCancel];
    if(deliver)dispatch_async(dispatch_get_main_queue(),^{
        void (^completion)(UIImage *)=nil;
        @synchronized(self) {
            if(!self.cancelled)completion=self.completion;
            self.completion=nil;
        }
        if(completion)completion(image);
    });
}
- (void)cancel {
    NSURLSession *session=nil;
    @synchronized(self) {
        // Clear even after finish has scheduled a callback. Its main-queue
        // handoff checks cancellation rather than retaining the callback.
        self.cancelled=YES;self.finished=YES;self.completion=nil;
        self.bytes=nil;self.decodeData=nil;
        session=self.session;self.session=nil;self.task=nil;
    }
    [session invalidateAndCancel];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completionHandler {
    completionHandler([request.URL.scheme.lowercaseString isEqualToString:@"https"]?request:nil);
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    NSInteger status=[response isKindOfClass:NSHTTPURLResponse.class]?[(NSHTTPURLResponse *)response statusCode]:0;
    BOOL valid;
    @synchronized(self) { valid=!self.finished && (!status || (status>=200 && status<300)) &&
        (response.expectedContentLength<0 || response.expectedContentLength<=(int64_t)self.maximumBytes); }
    completionHandler(valid?NSURLSessionResponseAllow:NSURLSessionResponseCancel);
    if(!valid)[self finish:nil];
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    BOOL oversized=NO;
    @synchronized(self) {
        if(self.finished || self.decoding)return;
        oversized=self.bytes.length>self.maximumBytes || data.length>self.maximumBytes-self.bytes.length;
        if(!oversized && data.length) {
            if(!self.bytes)self.bytes=[NSMutableData new];
            [self.bytes appendData:data];
        }
    }
    if(oversized)[self finish:nil];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    BOOL failed=NO;
    @synchronized(self) {
        if(self.finished || self.decoding)return;
        failed=error!=nil || !self.bytes.length;
        if(!failed){self.decoding=YES;self.decodeData=self.bytes;self.bytes=nil;}
    }
    if(failed){[self finish:nil];return;}
    __weak typeof(self) weakSelf=self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        @autoreleasepool {
            WPQCAvatarDownload *download=weakSelf;
            NSData *data=nil;NSUInteger pixels=0;
            @synchronized(download) {
                if(!download || download.finished || download.cancelled)return;
                data=download.decodeData;download.decodeData=nil;pixels=download.maximumPixels;
            }
            // Queued work does not capture the response data. Cancelling before
            // decoding starts releases it immediately; an active ImageIO call
            // owns only its local input until that bounded decode returns.
            UIImage *image=WPQCDecodeAvatar(data,pixels);
            dispatch_async(dispatch_get_main_queue(),^{[weakSelf finish:image];});
        }
    });
}
@end

@interface WPQuickChatCell : UITableViewCell
@property (nonatomic) UIImageView *avatar;
@property (nonatomic) UILabel *name;
@property (nonatomic) UILabel *dot;
@property (nonatomic, copy) NSString *representedUsername;
@property (nonatomic) BOOL hasPreparedAvatar;
- (void)showUnread:(NSUInteger)unread muted:(BOOL)muted;
@end
@implementation WPQuickChatCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    if(!(self=[super initWithStyle:style reuseIdentifier:identifier]))return nil;
    self.backgroundColor=UIColor.clearColor;
    UIView *selected=[UIView new];selected.backgroundColor=[UIColor.systemFillColor colorWithAlphaComponent:.5];self.selectedBackgroundView=selected;
    self.avatar=[[UIImageView alloc] initWithFrame:CGRectMake(0,0,WPQCBarAvatar,WPQCBarAvatar)];
    self.avatar.layer.cornerRadius=WPQCBarAvatar/2;self.avatar.clipsToBounds=YES;self.avatar.contentMode=UIViewContentModeScaleAspectFill;
    self.name=[UILabel new];self.name.font=[UIFont systemFontOfSize:11 weight:UIFontWeightMedium];self.name.textColor=UIColor.labelColor;
    self.name.textAlignment=NSTextAlignmentCenter;self.name.lineBreakMode=NSLineBreakByTruncatingTail;
    self.dot=[[UILabel alloc] initWithFrame:CGRectMake(0,0,10,10)];self.dot.backgroundColor=UIColor.systemRedColor;
    self.dot.textColor=UIColor.whiteColor;self.dot.font=[UIFont monospacedDigitSystemFontOfSize:10 weight:UIFontWeightBold];
    self.dot.textAlignment=NSTextAlignmentCenter;self.dot.clipsToBounds=YES;
    for(UIView *view in @[self.avatar,self.name,self.dot])[self.contentView addSubview:view];
    self.isAccessibilityElement=YES;self.accessibilityTraits=UIAccessibilityTraitButton;self.accessibilityHint=@"打开聊天";
    return self;
}
- (void)prepareForReuse {
    [super prepareForReuse];self.representedUsername=nil;self.avatar.image=nil;self.hasPreparedAvatar=NO;self.name.text=nil;self.dot.hidden=YES;
}
- (void)showUnread:(NSUInteger)unread muted:(BOOL)muted {
    self.dot.hidden=unread==0 || !WPQuickChatOptionBool(@"showRedDot");
    if(!unread)return;
    // WeChat represents unread messages from muted chats with a plain dot.
    NSString *count=muted || !WPQuickChatOptionBool(@"numericBadge")?nil:(unread>99?@"99+":[NSString stringWithFormat:@"%lu",(unsigned long)unread]);
    CGFloat width=count?MAX(18,ceil([count sizeWithAttributes:@{NSFontAttributeName:self.dot.font}].width)+8):10;
    self.dot.bounds=CGRectMake(0,0,width,count?18:10);
    self.dot.layer.cornerRadius=self.dot.bounds.size.height/2;self.dot.text=count;
    [self setNeedsLayout];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width=self.contentView.bounds.size.width;
    CGFloat side=MIN(width-12,WPQuickChatOptionNumber(@"avatarSize"));
    self.avatar.frame=CGRectMake((width-side)/2,WPQuickChatOptionNumber(@"sessionGap")/2+4,side,side);
    self.avatar.layer.cornerRadius=side/2;
    self.name.hidden=!WPQuickChatOptionBool(@"showNames");
    self.name.frame=CGRectMake(3,CGRectGetMaxY(self.avatar.frame)+WPQuickChatOptionNumber(@"nameGap"),width-6,15);
    CGFloat badgeX=MIN(width-self.dot.bounds.size.width/2-2,CGRectGetMaxX(self.avatar.frame));
    self.dot.center=CGPointMake(badgeX,CGRectGetMinY(self.avatar.frame)+4);
}
@end

@interface WPQuickChatBar () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic) UITableView *table;
@property (nonatomic) UILabel *empty;
@property (nonatomic, readwrite) NSArray<WPQuickChatSession *> *sessions;
@property (nonatomic) NSMutableDictionary<NSString *, NSString *> *titles;
@property (nonatomic) NSCache<NSString *, UIImage *> *avatars;
@property (nonatomic) NSCache<NSString *, UIImage *> *placeholders;
@property (nonatomic) NSMutableDictionary<NSString *, NSNumber *> *avatarAttempts;
@property (nonatomic) NSMutableDictionary<NSString *, NSNumber *> *avatarRetryAfter;
@property (nonatomic) NSMutableDictionary<NSString *, NSNumber *> *avatarRemoteAttempts;
@property (nonatomic) NSMutableDictionary<NSString *, WPQCAvatarDownload *> *avatarDownloads;
@property (nonatomic) NSMutableDictionary<NSString *, WPSharedChatAvatarRequest *> *avatarPreparations;
@property (nonatomic) CFTimeInterval memoryCooldownUntil;
@property (nonatomic,copy) NSArray<WPQuickChatSession *> *rawSessions;
@property (nonatomic) NSTimer *avatarRefreshTimer;
@property (nonatomic) NSUInteger avatarGeneration;
@property (nonatomic) BOOL avatarSuspended;
@end

@implementation WPQuickChatBar
- (instancetype)initWithFrame:(CGRect)frame {
    if(!(self=[super initWithFrame:frame]))return nil;
    self.backgroundColor=WPQuickChatBackgroundColor(self.traitCollection);
    self.layer.cornerRadius=WPQuickChatOptionNumber(@"radius");self.layer.masksToBounds=YES;
    self.layer.shadowOpacity=0;
    self.accessibilityLabel=@"最近聊天";self.accessibilityViewIsModal=NO;
    self.table=[[UITableView alloc] initWithFrame:self.bounds style:UITableViewStylePlain];
    self.table.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    self.table.backgroundColor=UIColor.clearColor;self.table.separatorStyle=UITableViewCellSeparatorStyleNone;
    self.table.rowHeight=MAX(44,WPQuickChatOptionNumber(@"avatarSize")+WPQuickChatOptionNumber(@"sessionGap")+8+(WPQuickChatOptionBool(@"showNames")?15+WPQuickChatOptionNumber(@"nameGap"):0));self.table.showsVerticalScrollIndicator=NO;self.table.dataSource=self;self.table.delegate=self;
    // Every row has the same configured height. Estimates can change rects
    // after reload and move the contact anchor while a new row is inserted.
    self.table.estimatedRowHeight=0;
    self.table.layer.cornerRadius=self.layer.cornerRadius;
    [self.table registerClass:WPQuickChatCell.class forCellReuseIdentifier:@"chat"];
    [self addSubview:self.table];
    self.empty=[UILabel new];self.empty.numberOfLines=0;self.empty.textAlignment=NSTextAlignmentCenter;
    self.empty.font=[UIFont systemFontOfSize:12];self.empty.textColor=UIColor.secondaryLabelColor;self.empty.hidden=YES;
    [self addSubview:self.empty];
    self.titles=[NSMutableDictionary new];self.avatars=[NSCache new];self.avatars.countLimit=8;self.avatars.totalCostLimit=768*1024;
    self.placeholders=[NSCache new];self.placeholders.countLimit=24;self.placeholders.totalCostLimit=512*1024;
    self.avatarAttempts=[NSMutableDictionary new];self.avatarRetryAfter=[NSMutableDictionary new];self.avatarRemoteAttempts=[NSMutableDictionary new];self.avatarDownloads=[NSMutableDictionary new];
    self.avatarPreparations=[NSMutableDictionary new];
    self.sessions=@[];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(memoryWarning:) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(suspendAvatarWork:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(resumeAvatarWork:) name:UIApplicationWillEnterForegroundNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(settingsChanged:) name:WPSettingsDidChangeNotification object:nil];
    UILongPressGestureRecognizer *hold=[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(holdAvatar:)];hold.minimumPressDuration=.4;[self.table addGestureRecognizer:hold];
    return self;
}
- (void)dealloc {[NSNotificationCenter.defaultCenter removeObserver:self];[self.avatarRefreshTimer invalidate];for(WPQCAvatarDownload *download in self.avatarDownloads.allValues)[download cancel];for(WPSharedChatAvatarRequest *job in self.avatarPreparations.allValues)[job cancel];}
- (void)cancelAvatarWork {
    self.avatarGeneration++;
    [self.avatarRefreshTimer invalidate];self.avatarRefreshTimer=nil;
    for(WPQCAvatarDownload *download in self.avatarDownloads.allValues)[download cancel];
    [self.avatarDownloads removeAllObjects];
    for(WPSharedChatAvatarRequest *job in self.avatarPreparations.allValues)[job cancel];[self.avatarPreparations removeAllObjects];
}
- (void)suspendAvatarWork:(NSNotification *)note {self.avatarSuspended=YES;[self cancelAvatarWork];}
- (void)resumeAvatarWork:(NSNotification *)note {self.avatarSuspended=NO;[self updateAvatarRefresh];}
- (void)memoryWarning:(NSNotification *)note {
    [self cancelAvatarWork];[self.avatars removeAllObjects];[self.placeholders removeAllObjects];
    [self.avatarAttempts removeAllObjects];[self.avatarRetryAfter removeAllObjects];[self.avatarRemoteAttempts removeAllObjects];self.memoryCooldownUntil=CACurrentMediaTime()+8;
    if(self.hidden || !self.window)for(WPQuickChatCell *cell in self.table.visibleCells)cell.avatar.image=nil;
    else [self updateAvatarRefresh];
}
- (void)didMoveToWindow {[super didMoveToWindow];if(!self.window)[self cancelAvatarWork];else [self updateAvatarRefresh];}
- (void)setHidden:(BOOL)hidden {
    BOOL changed=self.hidden!=hidden;[super setHidden:hidden];
    if(changed){[self.avatarAttempts removeAllObjects];[self.avatarRetryAfter removeAllObjects];[self.avatarRemoteAttempts removeAllObjects];}
    if(changed){
        if(hidden){
            [self cancelAvatarWork];
            for(WPQuickChatCell *cell in self.table.visibleCells)cell.avatar.image=nil;
            self.sessions=@[];
            self.rawSessions=nil;
            [self.titles removeAllObjects];
            [self.avatars removeAllObjects];[self.placeholders removeAllObjects];
            [self.table reloadData];
        }else [self updateAvatarRefresh];
    }
}
- (UIImage *)loadAvatarForUsername:(NSString *)username {
    if(!username.length)return nil;
    // Rows are normally bound before their strip is made visible. A warm
    // shared image is safe to use then; only starting work requires visibility.
    UIImage *image=WPCachedSharedChatAvatar(username);
    if(image)return image;
    if(self.avatarSuspended || self.hidden || !self.window)return nil;
    if(CACurrentMediaTime()<self.memoryCooldownUntil)return nil;
    if(self.avatarPreparations[username])return nil;
    if(CACurrentMediaTime()<[self.avatarRetryAfter[username] doubleValue])return nil;
    if(self.avatarAttempts.count>=128 && !self.avatarAttempts[username]){
        for(NSString *key in self.avatarAttempts.allKeys){if(!self.avatarPreparations[key]){[self.avatarAttempts removeObjectForKey:key];[self.avatarRetryAfter removeObjectForKey:key];break;}}
    }
    NSUInteger generation=self.avatarGeneration;__weak typeof(self) weakSelf=self;
    WPSharedChatAvatarRequest *request=WPRequestSharedChatAvatar(username,^(UIImage *prepared){
        WPQuickChatBar *self=weakSelf;if(!self || generation!=self.avatarGeneration)return;
        [self.avatarPreparations removeObjectForKey:username];
        if(self.hidden || !self.window || self.avatarSuspended)return;
        if(prepared){
            [self.avatarAttempts removeObjectForKey:username];[self.avatarRetryAfter removeObjectForKey:username];
            [self updateVisibleAvatar:prepared username:username];
        }else{
            // Queue pressure and a not-yet-warmed WeChat head cache are
            // transient. Retry with a bounded backoff rather than exhausting
            // eight lifetime requests and leaving this contact blank forever.
            NSUInteger failures=MIN(WPQCMaxAvatarAttempts,[self.avatarAttempts[username] unsignedIntegerValue]+1);
            self.avatarAttempts[username]=@(failures);
            self.avatarRetryAfter[username]=@(CACurrentMediaTime()+MIN(60,pow(2,MIN(failures,(NSUInteger)6))));
        }
        [self updateAvatarRefresh];
    });
    self.avatarPreparations[username]=request;return nil;
}
- (BOOL)canRetryAvatarForUsername:(NSString *)username {
    return username.length>0;
}
- (BOOL)needsAvatarRefresh {
    NSArray<NSIndexPath *> *visible=self.table.indexPathsForVisibleRows;
    if(!visible.count)return self.sessions.count>0;
    for(NSIndexPath *path in visible){
        if(path.row>=(NSInteger)self.sessions.count)continue;
        NSString *username=self.sessions[path.row].username;
        WPQuickChatCell *cell=[self.table cellForRowAtIndexPath:path];
        UIImage *cached=WPCachedSharedChatAvatar(username);
        if(cached && (cell.avatar.image!=cached || !cell.hasPreparedAvatar))return YES;
        if(!cached && (!cell.hasPreparedAvatar || !cell.avatar.image) && [self canRetryAvatarForUsername:username])return YES;
    }
    return NO;
}
- (void)updateAvatarRefresh {
    [self.avatarRefreshTimer invalidate];self.avatarRefreshTimer=nil;
    if(self.avatarSuspended || self.hidden || !self.window || !self.sessions.count || ![self needsAvatarRefresh])return;
    __weak typeof(self) weakSelf=self;
    NSTimeInterval interval=MAX(1.5,self.memoryCooldownUntil-CACurrentMediaTime());
    self.avatarRefreshTimer=[NSTimer timerWithTimeInterval:interval repeats:YES block:^(__unused NSTimer *timer){[weakSelf refreshVisibleAvatars];}];
    self.avatarRefreshTimer.tolerance=.3;
    [NSRunLoop.mainRunLoop addTimer:self.avatarRefreshTimer forMode:NSRunLoopCommonModes];
    [self refreshVisibleAvatars];
}
- (void)refreshVisibleAvatars {
    // WeChat can return nil until a head image finishes loading. Retry only
    // visible placeholders while the strip is open, then stop when it closes.
    if(self.avatarSuspended || self.hidden || !self.window || CACurrentMediaTime()<self.memoryCooldownUntil)return;
    NSArray<NSIndexPath *> *visible=self.table.indexPathsForVisibleRows;
    BOOL pending=NO;
    for(NSIndexPath *indexPath in visible){
        if(indexPath.row>=(NSInteger)self.sessions.count)continue;
        NSString *username=self.sessions[indexPath.row].username;
        WPQuickChatCell *cell=[self.table cellForRowAtIndexPath:indexPath];
        if(![cell.representedUsername isEqualToString:username])continue;
        if(!username.length)continue;
        UIImage *image=WPCachedSharedChatAvatar(username);
        // A visible decoded head remains useful when the global LRU evicts its
        // copy; do not immediately re-download it and churn a full strip.
        if(!image && cell.hasPreparedAvatar && cell.avatar.image)continue;
        if(!image)image=[self loadAvatarForUsername:username];
        if(!image){pending|=[self canRetryAvatarForUsername:username];continue;}
        cell.hasPreparedAvatar=YES;
        if(cell.avatar.image==image)continue;
        if(UIAccessibilityIsReduceMotionEnabled())cell.avatar.image=image;
        else [UIView transitionWithView:cell.avatar duration:.18 options:UIViewAnimationOptionTransitionCrossDissolve|UIViewAnimationOptionAllowUserInteraction animations:^{cell.avatar.image=image;} completion:nil];
    }
    if(visible.count && !pending){[self.avatarRefreshTimer invalidate];self.avatarRefreshTimer=nil;}
}
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if(!self.hidden && self.window && !self.avatarRefreshTimer)[self updateAvatarRefresh];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    self.empty.frame=CGRectInset(self.bounds,6,0);
    self.layer.cornerRadius=MIN(self.bounds.size.width/2,WPQuickChatOptionNumber(@"radius"));self.table.layer.cornerRadius=self.layer.cornerRadius;
    self.table.rowHeight=MAX(44,WPQuickChatOptionNumber(@"avatarSize")+WPQuickChatOptionNumber(@"sessionGap")+8+(WPQuickChatOptionBool(@"showNames")?15+WPQuickChatOptionNumber(@"nameGap"):0));
}
- (void)reloadWithSessions:(NSArray<WPQuickChatSession *> *)sessions {
    CGPoint previousOffset=self.table.contentOffset;
    BOOL wasAtTop=previousOffset.y<=4 || !self.sessions.count;
    NSArray<NSIndexPath *> *visible=[self.table.indexPathsForVisibleRows sortedArrayUsingSelector:@selector(compare:)];
    NSIndexPath *anchor=visible.firstObject;
    NSString *anchorName=anchor && anchor.row<(NSInteger)self.sessions.count?self.sessions[anchor.row].username:nil;
    CGFloat anchorDelta=anchor?previousOffset.y-CGRectGetMinY([self.table rectForRowAtIndexPath:anchor]):0;
    NSArray<WPQuickChatSession *> *next=WPQuickChatApplyDisplayPolicy(sessions?:@[]);
    BOOL sameOrder=next.count==self.sessions.count;
    if(sameOrder)for(NSUInteger i=0;i<next.count;i++)if(![next[i].username isEqual:self.sessions[i].username]){sameOrder=NO;break;}
    self.rawSessions=[sessions copy];self.sessions=next;
    self.empty.text=sessions?@"暂无会话":@"暂时读不到会话列表，请回到微信首页后再试";
    self.empty.hidden=self.sessions.count>0;
    if(sameOrder){
        // Counts and names update in place. Keep live image requests and the
        // actual cell/scroll position while another message arrives.
        for(WPQuickChatCell *cell in self.table.visibleCells){
            NSIndexPath *path=[self.table indexPathForCell:cell];if(!path || path.row>=(NSInteger)next.count)continue;
            WPQuickChatSession *row=next[path.row];
            [cell showUnread:row.unreadKnown?row.unread:0 muted:row.muted];
            cell.name.text=[self titleForUsername:row.username];cell.name.textColor=WPQCNameColor(self.traitCollection);
            [cell setNeedsLayout];
        }
    }else{
        [self.table reloadData];[self.table layoutIfNeeded];
        CGFloat offset=wasAtTop?0:previousOffset.y;
        if(!wasAtTop && anchorName.length){
            for(NSUInteger i=0;i<next.count;i++)if([next[i].username isEqual:anchorName]){offset=CGRectGetMinY([self.table rectForRowAtIndexPath:[NSIndexPath indexPathForRow:i inSection:0]])+anchorDelta;break;}
        }
        CGFloat maximum=MAX(0,self.table.contentSize.height-CGRectGetHeight(self.table.bounds));
        self.table.contentOffset=CGPointMake(0,MAX(0,MIN(offset,maximum)));
    }
    NSMutableSet *names=[NSMutableSet new];for(WPQuickChatSession *row in next)[names addObject:row.username];
    for(NSString *name in self.avatarPreparations.allKeys)if(![names containsObject:name]){[self.avatarPreparations[name] cancel];[self.avatarPreparations removeObjectForKey:name];}
    for(NSString *name in self.avatarAttempts.allKeys)if(![names containsObject:name]){[self.avatarAttempts removeObjectForKey:name];[self.avatarRetryAfter removeObjectForKey:name];}
    [self updateAvatarRefresh];
}
- (void)settingsChanged:(NSNotification *)note{
    self.backgroundColor=WPQuickChatBackgroundColor(self.traitCollection);[self.titles removeAllObjects];[self.placeholders removeAllObjects];[self setNeedsLayout];
    if(!self.hidden){NSArray *rows=self.rawSessions;[self reloadWithSessions:rows];[self.table reloadData];}
}
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection{[super traitCollectionDidChange:previousTraitCollection];self.backgroundColor=WPQuickChatBackgroundColor(self.traitCollection);}
- (void)updateVisibleAvatar:(UIImage *)image username:(NSString *)username{
    for(WPQuickChatCell *cell in self.table.visibleCells)if([cell.representedUsername isEqual:username]){cell.avatar.image=image;cell.hasPreparedAvatar=YES;}
}
- (void)holdAvatar:(UILongPressGestureRecognizer *)gesture{
    if(gesture.state!=UIGestureRecognizerStateBegan)return;
    NSIndexPath *path=[self.table indexPathForRowAtPoint:[gesture locationInView:self.table]];
    if(!path || path.row>=(NSInteger)self.sessions.count)return;
    NSString *username=self.sessions[path.row].username;
    if(self.onSelectWithMode)self.onSelectWithMode(username,(NSInteger)WPQuickChatOptionNumber(@"holdMode"));else if(self.onSelect)self.onSelect(username);
}
- (NSString *)titleForUsername:(NSString *)username {
    if(!username.length)return @"聊天";
    NSString *title=self.titles[username];if(title)return title;
    title=[WPPartnerContact displayNameForUsername:username];
    if(!title.length)title=[username.lowercaseString hasSuffix:@"chatroom"]?@"群聊":username;
    if(self.titles.count>=64)[self.titles removeAllObjects];self.titles[username]=title;return title;
}
- (UIImage *)avatarForUsername:(NSString *)username side:(CGFloat)side {
    side=isfinite(side)?MAX(1,MIN(side,160)):WPQCBarAvatar;
    UIImage *image=[self loadAvatarForUsername:username];if(image)return image;
    NSString *key=[NSString stringWithFormat:@"%@/%.1f",username?:@"",side];
    image=[self.placeholders objectForKey:key];if(image)return image;
    // Missing head images use a placeholder; visible cells retry briefly.
    NSString *title=[self titleForUsername:username];
    NSString *letter=title.length?[title substringWithRange:[title rangeOfComposedCharacterSequenceAtIndex:0]]:@"?";
    NSArray *palette=@[UIColor.systemTealColor,UIColor.systemIndigoColor,UIColor.systemOrangeColor,UIColor.systemGreenColor,UIColor.systemPinkColor];
    UIColor *color=palette[(NSUInteger)username.hash%palette.count];
    image=[[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side,side)] imageWithActions:^(UIGraphicsImageRendererContext *context){
        [color setFill];UIRectFill(CGRectMake(0,0,side,side));
        NSDictionary *attributes=@{NSFontAttributeName:[UIFont systemFontOfSize:side*.42 weight:UIFontWeightSemibold],NSForegroundColorAttributeName:UIColor.whiteColor};
        CGSize size=[letter sizeWithAttributes:attributes];
        [letter drawAtPoint:CGPointMake((side-size.width)/2,(side-size.height)/2) withAttributes:attributes];
    }];
    [self.placeholders setObject:image forKey:key cost:WPQCAvatarCost(image)];return image;
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{return self.sessions.count;}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    WPQuickChatCell *cell=[tableView dequeueReusableCellWithIdentifier:@"chat" forIndexPath:indexPath];
    WPQuickChatSession *session=self.sessions[indexPath.row];
    NSString *title=[self titleForUsername:session.username];
    cell.representedUsername=session.username;
    cell.name.text=title;cell.name.textColor=WPQCNameColor(self.traitCollection);
    cell.avatar.image=[self avatarForUsername:session.username side:WPQuickChatOptionNumber(@"avatarSize")];
    cell.hasPreparedAvatar=cell.avatar.image==WPCachedSharedChatAvatar(session.username);
    [cell showUnread:session.unreadKnown?session.unread:0 muted:session.muted];
    NSMutableArray<NSString *> *details=[NSMutableArray arrayWithObject:title];
    if(session.muted)[details addObject:@"消息免打扰"];
    if(session.unreadKnown && session.unread)[details addObject:[NSString stringWithFormat:@"%lu 条未读消息",(unsigned long)session.unread]];
    cell.accessibilityLabel=[details componentsJoinedByString:@"，"];
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if(indexPath.row<(NSInteger)self.sessions.count){NSString *username=self.sessions[indexPath.row].username;
        if(self.onSelectWithMode)self.onSelectWithMode(username,(NSInteger)WPQuickChatOptionNumber(@"tapMode"));else if(self.onSelect)self.onSelect(username);}
}
- (void)tableView:(UITableView *)tableView didEndDisplayingCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    // UITableView keeps a reuse pool after scrolling. Its offscreen cells
    // must not retain decoded avatars independently of our bounded caches.
    // During a reload UIKit may send the old row's end callback after this
    // same cell has been rebound to another visible index path.
    NSIndexPath *current=[tableView indexPathForCell:cell];
    if(current && [tableView.indexPathsForVisibleRows containsObject:current] && [tableView cellForRowAtIndexPath:current]==cell){
        // A genuine departure can still be in UIKit's visible mapping during
        // its delegate callback. Recheck next turn so its reuse-pool image is
        // released, while a rebound visible cell remains intact.
        __weak UITableView *weakTable=tableView;__weak UITableViewCell *weakCell=cell;
        dispatch_async(dispatch_get_main_queue(),^{
            UITableView *table=weakTable;WPQuickChatCell *chat=(id)weakCell;
            if(!table || ![chat isKindOfClass:WPQuickChatCell.class])return;
            NSIndexPath *live=[table indexPathForCell:chat];
            if(live && [table.indexPathsForVisibleRows containsObject:live] && [table cellForRowAtIndexPath:live]==chat)return;
            chat.avatar.image=nil;chat.hasPreparedAvatar=NO;chat.representedUsername=nil;
        });return;
    }
    if([cell isKindOfClass:WPQuickChatCell.class]){WPQuickChatCell *chat=(id)cell;chat.avatar.image=nil;chat.hasPreparedAvatar=NO;chat.representedUsername=nil;}
}
- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if(![cell isKindOfClass:WPQuickChatCell.class] || indexPath.row>=(NSInteger)self.sessions.count)return;
    WPQuickChatCell *chat=(id)cell;NSString *username=self.sessions[indexPath.row].username;
    if(![chat.representedUsername isEqual:username]){chat.representedUsername=username;chat.hasPreparedAvatar=NO;chat.avatar.image=nil;}
    UIImage *cached=WPCachedSharedChatAvatar(username);
    if(cached){chat.avatar.image=cached;chat.hasPreparedAvatar=YES;}
    else if(!chat.hasPreparedAvatar || !chat.avatar.image){chat.avatar.image=[self avatarForUsername:username side:WPQuickChatOptionNumber(@"avatarSize")];chat.hasPreparedAvatar=chat.avatar.image==WPCachedSharedChatAvatar(username);}
    [self updateAvatarRefresh];
}
@end
