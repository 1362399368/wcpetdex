#import "WPCatalogController.h"
#import "WPPetCatalog.h"
#import "WPPetImporter.h"
#import "WPPagedPet.h"
#import "WPCommon.h"
#import <ImageIO/ImageIO.h>
#import <CommonCrypto/CommonDigest.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>

static const NSUInteger WPCMaxPreviewBytes=32*1024*1024;

static NSString * const WPCatalogUsageKey = @"catalogLocalUsageCounts";
static NSString *WPCString(id value) { return [value isKindOfClass:NSString.class] ? value : @""; }
static NSDictionary *WPCReadJSON(NSString *path) {
    NSDictionary *attrs=[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
    if (!attrs || [attrs[NSFileSize] unsignedLongLongValue] > 128*1024) return nil;
    NSData *data=[NSData dataWithContentsOfFile:path];
    id result=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
    return [result isKindOfClass:NSDictionary.class]?result:nil;
}
static NSString *WPCLocalSpritePath(NSString *directory,NSDictionary *metadata) {
    NSString *name=WPCString(metadata[@"spritesheetPath"]);
    if([directory.stringByStandardizingPath isEqual:WPDefaultPetDirectory().stringByStandardizingPath]){
        NSString *compact=[directory stringByAppendingPathComponent:@"compact-row-00.png"];
        if([NSFileManager.defaultManager fileExistsAtPath:compact])return compact;
    }
    NSString *paged=[directory stringByAppendingPathComponent:@".wp-paged-v121"];
    NSDictionary *local=WPCReadJSON([paged stringByAppendingPathComponent:@"pet.json"]);
    NSString *first=WPIsLocalPagedMetadata(local)?WPCString(local[@"rowAtlasPaths"][0]):nil;
    if(first.length && [first isEqual:first.lastPathComponent]){
        NSString *path=[paged stringByAppendingPathComponent:first];if([NSFileManager.defaultManager fileExistsAtPath:path])return path;
    }
    if(!name.length || ![name isEqual:name.lastPathComponent])return nil;
    NSString *path=[directory stringByAppendingPathComponent:name];return [NSFileManager.defaultManager fileExistsAtPath:path]?path:nil;
}
#ifdef WP_PREVIEW_HOST
NSString *WPCatalogPreviewLocalSpritePath(NSString *directory){return WPCLocalSpritePath(directory,WPCReadJSON([directory stringByAppendingPathComponent:@"pet.json"]));}
#endif
static NSString *WPCKeyForDirectory(NSURL *directory,NSDictionary *metadata) {
    if ([WPCString(metadata[@"source"]) isEqualToString:@"local-import"])
        return [@"import:" stringByAppendingString:directory.lastPathComponent];
    NSDictionary *entry=WPCReadJSON([directory.path stringByAppendingPathComponent:@"catalog-entry.json"]);
    NSString *slug=WPCString(entry[@"slug"]);
    if (!slug.length) slug=WPCString(metadata[@"id"]);
    return slug.length?[@"petdex:" stringByAppendingString:slug]:[@"local:" stringByAppendingString:directory.path];
}
void WPCatalogRecordUsageForDirectory(NSURL *directory) {
    if (!directory) return;
    NSDictionary *metadata=WPCReadJSON([directory.path stringByAppendingPathComponent:@"pet.json"]);
    if (!metadata) return;
    NSString *key=WPCKeyForDirectory(directory,metadata);
    @synchronized (WPPreferences()) {
        NSMutableDictionary *counts=[[WPPreferences() dictionaryForKey:WPCatalogUsageKey] mutableCopy] ?: [NSMutableDictionary new];
        NSUInteger old=[counts[key] unsignedIntegerValue];
        counts[key]=@(MIN(old,(NSUInteger)1000000000)+1);
        [WPPreferences() setObject:counts forKey:WPCatalogUsageKey];
    }
}

static UIImage *WPCCropFirstFrame(NSData *data) {
    if (!data.length || data.length>32*1024*1024) return nil;
    CGImageSourceRef source=CGImageSourceCreateWithData((__bridge CFDataRef)data,(__bridge CFDictionaryRef)@{(__bridge NSString *)kCGImageSourceShouldCache:@NO});
    if (!source) return nil;
    NSDictionary *properties=CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source,0,NULL));
    size_t width=[properties[(__bridge NSString *)kCGImagePropertyPixelWidth] unsignedLongLongValue];
    size_t height=[properties[(__bridge NSString *)kCGImagePropertyPixelHeight] unsignedLongLongValue];
    BOOL validSize=(width==1536 && (height==1872 || height==2288 || height==6032)) || (width==1920 && height==6032) || (height==208 && width>=192 && width<=3840 && width%192==0);
    CGImageRef atlas=validSize?CGImageSourceCreateImageAtIndex(source,0,(__bridge CFDictionaryRef)@{(__bridge NSString *)kCGImageSourceShouldCache:@NO}):NULL;
    CGImageRef frame=atlas?CGImageCreateWithImageInRect(atlas,CGRectMake(0,0,192,208)):NULL;
    // A CGImage crop retains its source. Draw into a small independent bitmap
    // so one cached thumbnail cannot keep a decoded full atlas alive.
    CGColorSpaceRef colorSpace=CGColorSpaceCreateDeviceRGB();
    CGContextRef context=frame?CGBitmapContextCreate(NULL,192,208,8,192*4,colorSpace,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big):NULL;
    if(colorSpace)CGColorSpaceRelease(colorSpace);
    if(context)CGContextDrawImage(context,CGRectMake(0,0,192,208),frame);
    CGImageRef thumbnail=context?CGBitmapContextCreateImage(context):NULL;
    UIImage *result=thumbnail?[UIImage imageWithCGImage:thumbnail scale:1 orientation:UIImageOrientationUp]:nil;
    if(thumbnail)CGImageRelease(thumbnail);if(context)CGContextRelease(context);
    if(frame)CGImageRelease(frame);if(atlas)CGImageRelease(atlas);CFRelease(source);
    return result;
}
#if defined(WP_PREVIEW_HOST)
UIImage *WPCatalogPreviewThumbnailForData(NSData *data){return WPCCropFirstFrame(data);}
#endif
static NSString *WPCDigest(NSString *text) {
    NSData *data=[text dataUsingEncoding:NSUTF8StringEncoding];unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes,(CC_LONG)data.length,digest);NSMutableString *result=[NSMutableString new];
    for(NSUInteger i=0;i<sizeof(digest);i++)[result appendFormat:@"%02x",digest[i]];
    return result;
}

@interface WPCThumbnailJob : NSObject
@property(nonatomic,copy) NSString *key;
@property(nonatomic,copy) NSString *diskPath;
@property(nonatomic,copy) NSString *localPath;
@property(nonatomic,strong) NSURL *url;
@property(nonatomic,strong) NSURLSessionDataTask *task;
@property(nonatomic,copy) NSString *temporaryPath;
@property(nonatomic) int outputFile;
@property(nonatomic) NSUInteger receivedBytes;
@property(nonatomic,strong) NSMutableDictionary<NSString *,void (^)(UIImage *)> *callbacks;
@property(nonatomic) BOOL active;
@property(nonatomic) BOOL decoding;
@end
@implementation WPCThumbnailJob
- (instancetype)init {if((self=[super init]))_outputFile=-1;return self;}
- (void)closeOutput {if(self.outputFile>=0){close(self.outputFile);self.outputFile=-1;}}
- (void)removeTemporaryFile {[self closeOutput];if(self.temporaryPath.length)unlink(self.temporaryPath.fileSystemRepresentation);self.temporaryPath=nil;}
- (BOOL)openOutput {
    if(self.outputFile>=0)return YES;
    NSString *pattern=[NSTemporaryDirectory() stringByAppendingPathComponent:@"wechatpet-thumbnail-XXXXXX"];
    char *path=strdup(pattern.fileSystemRepresentation);if(!path)return NO;
    int descriptor=mkstemp(path);
    if(descriptor>=0){fcntl(descriptor,F_SETFD,FD_CLOEXEC);self.outputFile=descriptor;self.temporaryPath=[NSFileManager.defaultManager stringWithFileSystemRepresentation:path length:strlen(path)];}
    free(path);return descriptor>=0;
}
- (BOOL)appendBytes:(NSData *)data {
    if(data.length>WPCMaxPreviewBytes-self.receivedBytes || ![self openOutput])return NO;
    const uint8_t *bytes=data.bytes;NSUInteger remaining=data.length;
    while(remaining){ssize_t written=write(self.outputFile,bytes,remaining);if(written<0 && errno==EINTR)continue;if(written<=0)return NO;bytes+=written;remaining-=(NSUInteger)written;}
    self.receivedBytes+=data.length;return YES;
}
- (void)dealloc {[self removeTemporaryFile];}
@end

/// Only visible cells request images. Two decodes/downloads run at once; reused cells cancel.
@interface WPCThumbnailLoader : NSObject <NSURLSessionDataDelegate>
@property(nonatomic,strong) NSURLSession *session;
@property(nonatomic,strong) dispatch_queue_t decodeQueue;
@property(nonatomic,strong) NSCache<NSString *,UIImage *> *images;
@property(nonatomic,strong) NSMutableDictionary<NSString *,WPCThumbnailJob *> *jobs;
@property(nonatomic,strong) NSMutableDictionary<NSString *,NSString *> *subscriptions;
@property(nonatomic,strong) NSMutableDictionary<NSNumber *,WPCThumbnailJob *> *tasks;
@property(nonatomic,strong) NSMutableArray<WPCThumbnailJob *> *pending;
@property(nonatomic,copy) NSString *cachePath;
@property(nonatomic,copy) NSString *savedPath;
@property(nonatomic) NSUInteger activeCount;
+ (instancetype)shared;
- (NSString *)requestEntry:(NSDictionary *)entry completion:(void (^)(UIImage *))completion;
- (void)cancel:(NSString *)token;
- (void)releaseCachedWork;
@end
@implementation WPCThumbnailLoader
+ (instancetype)shared { static id loader;static dispatch_once_t once;dispatch_once(&once,^{loader=[self new];});return loader; }
- (instancetype)init {
    if((self=[super init])){
        _decodeQueue=dispatch_queue_create("WeChatPet.ThumbnailDecode",DISPATCH_QUEUE_SERIAL);
        _images=[NSCache new];_images.totalCostLimit=4*1024*1024;_images.countLimit=32;
        _jobs=[NSMutableDictionary new];_subscriptions=[NSMutableDictionary new];_tasks=[NSMutableDictionary new];_pending=[NSMutableArray new];
        _cachePath=[NSSearchPathForDirectoriesInDomains(NSCachesDirectory,NSUserDomainMask,YES).firstObject stringByAppendingPathComponent:@"WeChatPet/Thumbnails"];
        [NSFileManager.defaultManager createDirectoryAtPath:_cachePath withIntermediateDirectories:YES attributes:nil error:nil];
        _savedPath=[WPDataDirectory() stringByAppendingPathComponent:@"SavedThumbnails"];
        [NSFileManager.defaultManager createDirectoryAtPath:_savedPath withIntermediateDirectories:YES attributes:nil error:nil];
        NSURLSessionConfiguration *config=NSURLSessionConfiguration.ephemeralSessionConfiguration;
        config.timeoutIntervalForRequest=20;config.timeoutIntervalForResource=45;config.HTTPMaximumConnectionsPerHost=2;
        // The small first-frame PNG is already persisted below. Do not also
        // retain the original multi-megabyte atlas in a shared HTTP cache.
        config.URLCache=nil;config.HTTPCookieStorage=nil;config.requestCachePolicy=NSURLRequestReloadIgnoringLocalCacheData;
        config.HTTPAdditionalHeaders=@{@"User-Agent":@"WeChatPet/0.3 Petdex personal companion",@"Accept":@"image/webp,image/png"};
        _session=[NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:NSOperationQueue.mainQueue];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(releaseCachedWorkForNotification:) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(releaseCachedWorkForNotification:) name:UIApplicationDidEnterBackgroundNotification object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(releaseCachedWorkForNotification:) name:UIApplicationWillResignActiveNotification object:nil];
        // The cache stores small cropped frames, never whole atlases. Bound old disk entries.
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
            NSArray<NSURL *> *files=[NSFileManager.defaultManager contentsOfDirectoryAtURL:[NSURL fileURLWithPath:self.cachePath] includingPropertiesForKeys:@[NSURLContentModificationDateKey] options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
            if(files.count<=300)return;
            files=[files sortedArrayUsingComparator:^NSComparisonResult(NSURL *a,NSURL *b){NSDate *da=nil,*db=nil;[a getResourceValue:&da forKey:NSURLContentModificationDateKey error:nil];[b getResourceValue:&db forKey:NSURLContentModificationDateKey error:nil];return [da?:NSDate.distantPast compare:db?:NSDate.distantPast];}];
            for(NSUInteger i=0;i<files.count-240;i++)[NSFileManager.defaultManager removeItemAtURL:files[i] error:nil];
        });
    }return self;
}
- (NSString *)requestEntry:(NSDictionary *)entry completion:(void (^)(UIImage *))completion {
    NSString *directory=WPCString(entry[@"wp_directory"]),*localPath=nil;
    if(directory.length)localPath=WPCLocalSpritePath(directory,WPCReadJSON([directory stringByAppendingPathComponent:@"pet.json"]));
    NSString *remote=WPCString(entry[@"spritesheetUrl"]);
    NSString *identity=localPath.length?[NSString stringWithFormat:@"%@:%@",localPath,[NSFileManager.defaultManager attributesOfItemAtPath:localPath error:nil][NSFileModificationDate]]:remote;
    NSString *key=WPCDigest(identity),*token=NSUUID.UUID.UUIDString;UIImage *cached=[self.images objectForKey:key];
    if(cached){dispatch_async(dispatch_get_main_queue(),^{completion(cached);});return nil;}
    WPCThumbnailJob *job=self.jobs[key];
    if(!job){
        NSURL *url=[NSURL URLWithString:remote];
        if(!localPath.length && (![url.scheme.lowercaseString isEqualToString:@"https"] || ![url.host.lowercaseString isEqualToString:@"assets.petdex.dev"])) {dispatch_async(dispatch_get_main_queue(),^{completion(nil);});return nil;}
        job=[WPCThumbnailJob new];job.key=key;job.localPath=localPath;job.url=url;
        // Downloaded/imported pet previews are recoverable from their atlas but
        // should remain visible after iOS purges Caches or this loader prunes it.
        job.diskPath=[(localPath.length?self.savedPath:self.cachePath) stringByAppendingPathComponent:[key stringByAppendingString:@".png"]];
        job.callbacks=[NSMutableDictionary new];self.jobs[key]=job;[self.pending addObject:job];
    }
    job.callbacks[token]=[completion copy];self.subscriptions[token]=key;[self startPending];return token;
}
- (void)cancel:(NSString *)token {
    if(!token.length)return;NSString *key=self.subscriptions[token];[self.subscriptions removeObjectForKey:token];
    if(!key.length)return;
    WPCThumbnailJob *job=self.jobs[key];[job.callbacks removeObjectForKey:token];
    if(job && !job.callbacks.count){
        [self.pending removeObject:job];[self.jobs removeObjectForKey:key];
        if(job.active){
            [self.tasks removeObjectForKey:@(job.task.taskIdentifier)];[job.task cancel];
            [job removeTemporaryFile];job.task=nil;
            // ImageIO cannot cancel a decode already executing. Keep its slot
            // until it returns, otherwise rapid scrolling launches more decodes.
            if(!job.decoding){job.active=NO;if(self.activeCount)self.activeCount--;[self startPending];}
        }
    }
}
- (void)releaseCachedWork {
    // Remove subscriptions before cancelling, so a finishing decode cannot
    // repopulate the cache after a page closes or iOS asks for memory back.
    NSArray *jobs=self.jobs.allValues;
    [self.pending removeAllObjects];[self.jobs removeAllObjects];[self.subscriptions removeAllObjects];[self.tasks removeAllObjects];
    for(WPCThumbnailJob *job in jobs){[job.callbacks removeAllObjects];[job.task cancel];job.task=nil;[job removeTemporaryFile];if(job.active && !job.decoding){job.active=NO;if(self.activeCount)self.activeCount--;}}
    [self.images removeAllObjects];
}
- (void)releaseCachedWorkForNotification:(NSNotification *)notification {[self releaseCachedWork];}
- (BOOL)settleDecode:(WPCThumbnailJob *)job {
    job.decoding=NO;
    if(self.jobs[job.key]==job)return YES;
    if(job.active){job.active=NO;if(self.activeCount)self.activeCount--;[self startPending];}
    return NO;
}
- (void)startPending {
    while(self.activeCount<2 && self.pending.count){WPCThumbnailJob *job=self.pending.firstObject;[self.pending removeObjectAtIndex:0];if(!job.callbacks.count)continue;job.active=YES;job.decoding=YES;self.activeCount++;
        dispatch_async(self.decodeQueue,^{
            @autoreleasepool {
            UIImage *cached=[UIImage imageWithContentsOfFile:job.diskPath];
            UIImage *local=(!cached && job.localPath.length)?WPCCropFirstFrame([NSData dataWithContentsOfFile:job.localPath options:NSDataReadingMappedIfSafe error:nil]):nil;
            dispatch_async(dispatch_get_main_queue(),^{
                if(![self settleDecode:job])return;
                if(cached || job.localPath.length){[self finish:job image:cached?:local];return;}
                job.task=[self.session dataTaskWithURL:job.url];self.tasks[@(job.task.taskIdentifier)]=job;[job.task resume];
            });
            }
        });
    }
}
- (void)finish:(WPCThumbnailJob *)job image:(UIImage *)image {
    if(self.jobs[job.key]!=job)return;
    [self.jobs removeObjectForKey:job.key];[self.tasks removeObjectForKey:@(job.task.taskIdentifier)];
    [job removeTemporaryFile];job.task=nil;
    if(job.active){job.active=NO;if(self.activeCount)self.activeCount--;}
    if(image){size_t cost=image.CGImage?CGImageGetBytesPerRow(image.CGImage)*CGImageGetHeight(image.CGImage):0;[self.images setObject:image forKey:job.key cost:cost];dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{@autoreleasepool {[UIImagePNGRepresentation(image) writeToFile:job.diskPath atomically:YES];}});}
    NSArray *tokens=job.callbacks.allKeys;for(NSString *token in tokens){void(^callback)(UIImage *)=job.callbacks[token];[self.subscriptions removeObjectForKey:token];callback(image);}
    [job.callbacks removeAllObjects];[self startPending];
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    WPCThumbnailJob *job=self.tasks[@(task.taskIdentifier)];NSInteger status=[response isKindOfClass:NSHTTPURLResponse.class]?[(NSHTTPURLResponse *)response statusCode]:0;
    BOOL valid=job && status>=200 && status<300 && response.expectedContentLength<=(int64_t)WPCMaxPreviewBytes;
    completionHandler(valid?NSURLSessionResponseAllow:NSURLSessionResponseCancel);
    if(!valid && job)[self finish:job image:nil];
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    WPCThumbnailJob *job=self.tasks[@(task.taskIdentifier)];if(!job)return;
    if(![job appendBytes:data]){[task cancel];[self finish:job image:nil];}
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    WPCThumbnailJob *job=self.tasks[@(task.taskIdentifier)];if(!job)return;
    if(error || !job.receivedBytes){[self finish:job image:nil];return;}[job closeOutput];NSString *path=job.temporaryPath;job.decoding=YES;
    dispatch_async(self.decodeQueue,^{@autoreleasepool {NSData *data=[NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];UIImage *frame=WPCCropFirstFrame(data);dispatch_async(dispatch_get_main_queue(),^{[job removeTemporaryFile];if([self settleDecode:job])[self finish:job image:frame];});}});
}
@end

@interface WPCatalogCell : UICollectionViewCell
@property(nonatomic,strong) UIImageView *preview;
@property(nonatomic,strong) UILabel *nameLabel;
@property(nonatomic,strong) UILabel *authorLabel;
@property(nonatomic,strong) UILabel *previewHint;
@property(nonatomic,strong) UIButton *useButton;
@property(nonatomic,strong) UIActivityIndicatorView *spinner;
@property(nonatomic,copy) NSString *representedKey;
@property(nonatomic,copy) NSString *imageToken;
@property(nonatomic,copy) dispatch_block_t action;
@end
@implementation WPCatalogCell
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])){
        self.contentView.backgroundColor=UIColor.secondarySystemGroupedBackgroundColor;self.contentView.layer.cornerRadius=16;self.contentView.layer.borderWidth=1;self.contentView.layer.borderColor=UIColor.separatorColor.CGColor;self.contentView.clipsToBounds=YES;
        _preview=[UIImageView new];_preview.contentMode=UIViewContentModeScaleAspectFit;_preview.accessibilityIgnoresInvertColors=YES;[self.contentView addSubview:_preview];
        _previewHint=[UILabel new];_previewHint.text=@"加载预览…";_previewHint.textAlignment=NSTextAlignmentCenter;_previewHint.font=[UIFont systemFontOfSize:12];_previewHint.textColor=UIColor.tertiaryLabelColor;[self.contentView addSubview:_previewHint];
        _nameLabel=[UILabel new];_nameLabel.font=[UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];_nameLabel.textColor=UIColor.labelColor;_nameLabel.numberOfLines=2;[self.contentView addSubview:_nameLabel];
        _authorLabel=[UILabel new];_authorLabel.font=[UIFont systemFontOfSize:13];_authorLabel.textColor=UIColor.secondaryLabelColor;_authorLabel.lineBreakMode=NSLineBreakByTruncatingTail;[self.contentView addSubview:_authorLabel];
        _useButton=[UIButton buttonWithType:UIButtonTypeSystem];_useButton.titleLabel.font=[UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];_useButton.layer.cornerRadius=9;_useButton.backgroundColor=[UIColor.systemBlueColor colorWithAlphaComponent:.09];[_useButton addTarget:self action:@selector(use) forControlEvents:UIControlEventTouchUpInside];[self.contentView addSubview:_useButton];
        _spinner=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];_spinner.color=UIColor.systemBlueColor;_spinner.hidesWhenStopped=YES;[_useButton addSubview:_spinner];
    }return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];CGFloat width=self.contentView.bounds.size.width,height=self.contentView.bounds.size.height;
    self.preview.frame=CGRectMake(20,12,width-40,142);self.previewHint.frame=self.preview.frame;
    self.nameLabel.frame=CGRectMake(12,161,width-24,43);self.authorLabel.frame=CGRectMake(12,208,width-24,20);
    self.useButton.frame=CGRectMake(12,height-50,width-24,38);self.spinner.center=CGPointMake(18,19);
}
- (void)prepareForReuse { [super prepareForReuse];[[WPCThumbnailLoader shared] cancel:self.imageToken];self.imageToken=nil;self.representedKey=nil;self.preview.image=nil;self.previewHint.hidden=NO;self.previewHint.text=@"加载预览…";self.action=nil;[self.spinner stopAnimating]; }
- (void)use { if(self.action)self.action(); }
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {[super traitCollectionDidChange:previousTraitCollection];self.contentView.layer.borderColor=[UIColor.separatorColor resolvedColorWithTraitCollection:self.traitCollection].CGColor;}
@end

@interface WPCatalogController () <UICollectionViewDataSource,UICollectionViewDelegateFlowLayout,UISearchBarDelegate,UIDocumentPickerDelegate>
@property(nonatomic,strong) UISearchBar *searchBar;
@property(nonatomic,strong) UISegmentedControl *segments;
@property(nonatomic,strong) UILabel *countLabel;
@property(nonatomic,strong) UILabel *noteLabel;
@property(nonatomic,strong) UILabel *emptyLabel;
@property(nonatomic,strong) UIActivityIndicatorView *loading;
@property(nonatomic,strong) UICollectionView *collection;
@property(nonatomic,copy) NSArray<NSDictionary *> *allPets;
@property(nonatomic,copy) NSArray<NSDictionary *> *localPets;
@property(nonatomic,copy) NSArray<NSDictionary *> *shownPets;
@property(nonatomic,strong) NSMutableSet<NSString *> *downloading;
@property(nonatomic,strong) NSError *catalogError;
@property(nonatomic) BOOL catalogLoaded;
@property(nonatomic) NSUInteger localGeneration;
@property(nonatomic) BOOL previewsVisible;
@property(nonatomic) BOOL previewsSuspended;
@property(nonatomic) BOOL catalogLoading;
@end
@implementation WPCatalogController
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"桌宠库";self.view.backgroundColor=UIColor.systemGroupedBackgroundColor;
    self.allPets=@[];self.localPets=@[];self.shownPets=@[];self.downloading=[NSMutableSet new];
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"xmark"] style:UIBarButtonItemStylePlain target:self action:@selector(close)];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"square.and.arrow.down"] style:UIBarButtonItemStylePlain target:self action:@selector(importPackage)];self.navigationItem.rightBarButtonItem.accessibilityLabel=@"导入桌宠包";
    self.searchBar=[UISearchBar new];self.searchBar.searchBarStyle=UISearchBarStyleMinimal;self.searchBar.placeholder=@"搜索名称或作者";self.searchBar.delegate=self;[self.view addSubview:self.searchBar];
    self.segments=[[UISegmentedControl alloc] initWithItems:@[@"在线桌宠",@"使用最多",@"已下载"]];self.segments.selectedSegmentIndex=self.startsWithDownloadedPets?2:0;[self.segments addTarget:self action:@selector(filterChanged) forControlEvents:UIControlEventValueChanged];[self.view addSubview:self.segments];
    self.countLabel=[UILabel new];self.countLabel.font=[UIFont systemFontOfSize:13 weight:UIFontWeightMedium];self.countLabel.textColor=UIColor.secondaryLabelColor;[self.view addSubview:self.countLabel];
    self.noteLabel=[UILabel new];self.noteLabel.font=[UIFont systemFontOfSize:12];self.noteLabel.textColor=UIColor.secondaryLabelColor;self.noteLabel.numberOfLines=2;[self.view addSubview:self.noteLabel];
    UICollectionViewFlowLayout *layout=[UICollectionViewFlowLayout new];layout.minimumInteritemSpacing=12;layout.minimumLineSpacing=14;layout.sectionInset=UIEdgeInsetsMake(0,16,24,16);
    self.collection=[[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];self.collection.backgroundColor=UIColor.clearColor;self.collection.dataSource=self;self.collection.delegate=self;self.collection.keyboardDismissMode=UIScrollViewKeyboardDismissModeOnDrag;self.collection.alwaysBounceVertical=YES;[self.collection registerClass:WPCatalogCell.class forCellWithReuseIdentifier:@"pet"];[self.view addSubview:self.collection];
    self.emptyLabel=[UILabel new];self.emptyLabel.numberOfLines=0;self.emptyLabel.textAlignment=NSTextAlignmentCenter;self.emptyLabel.font=[UIFont systemFontOfSize:15];self.emptyLabel.textColor=UIColor.secondaryLabelColor;self.collection.backgroundView=self.emptyLabel;
    self.loading=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];[self.view addSubview:self.loading];[self.loading startAnimating];
    [self refreshLocal];[self applyFilter];
    if(self.startsWithDownloadedPets)[self.loading stopAnimating];else [self loadOnlineCatalogIfNeeded];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(petChanged:) name:WPSelectedPetDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(previewsBecameInactive:) name:UIApplicationWillResignActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(previewsBecameInactive:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(previewsBecameActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
}
- (void)dealloc {[NSNotificationCenter.defaultCenter removeObserver:self];for(WPCatalogCell *cell in self.collection.visibleCells)[[WPCThumbnailLoader shared] cancel:cell.imageToken];}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];CGFloat width=self.view.bounds.size.width,top=self.view.safeAreaInsets.top;
    self.searchBar.frame=CGRectMake(8,top+3,width-16,56);self.segments.frame=CGRectMake(16,top+65,width-32,36);self.countLabel.frame=CGRectMake(18,top+111,width-68,20);self.loading.center=CGPointMake(width-29,top+121);self.noteLabel.frame=CGRectMake(18,top+133,width-36,32);
    CGFloat start=top+175;self.collection.frame=CGRectMake(0,start,width,MAX(0,self.view.bounds.size.height-start));
    [self.collection.collectionViewLayout invalidateLayout];
}
- (void)viewWillAppear:(BOOL)animated {[super viewWillAppear:animated];self.previewsVisible=YES;self.previewsSuspended=UIApplication.sharedApplication.applicationState!=UIApplicationStateActive;[self refreshLocal];}
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    self.previewsVisible=NO;
    for(WPCatalogCell *cell in self.collection.visibleCells){[[WPCThumbnailLoader shared] cancel:cell.imageToken];cell.imageToken=nil;cell.representedKey=nil;cell.preview.image=nil;}
    // Cards are recoverable from bounded disk thumbnails when this page opens.
    // Release the singleton's decoded cache while the catalog is out of view.
    [[WPCThumbnailLoader shared] releaseCachedWork];
}
- (void)previewsBecameInactive:(NSNotification *)notification {
    self.previewsSuspended=YES;
    for(WPCatalogCell *cell in self.collection.visibleCells){[[WPCThumbnailLoader shared] cancel:cell.imageToken];cell.imageToken=nil;cell.representedKey=nil;cell.preview.image=nil;}
}
- (void)previewsBecameActive:(NSNotification *)notification {
    self.previewsSuspended=NO;
    if(self.previewsVisible && self.viewIfLoaded.window)[self.collection reloadData];
}
- (void)close { if(self.navigationController.viewControllers.count>1)[self.navigationController popViewControllerAnimated:YES];else[self dismissViewControllerAnimated:YES completion:nil]; }
- (void)petChanged:(NSNotification *)notification {[self refreshLocal];}
- (void)loadOnlineCatalogIfNeeded {
    if(self.catalogLoaded || self.catalogLoading)return;self.catalogLoading=YES;[self.loading startAnimating];
    __weak typeof(self) weakSelf=self;
    [[WPPetCatalog sharedCatalog] loadPetsWithCompletion:^(NSArray<NSDictionary *> *pets,NSError *error){typeof(self) self=weakSelf;if(!self)return;self.catalogLoading=NO;self.allPets=pets;self.catalogError=error;self.catalogLoaded=YES;[self.loading stopAnimating];[self applyFilter];}];
}
- (void)filterChanged {[self.view endEditing:YES];if(self.segments.selectedSegmentIndex!=2)[self loadOnlineCatalogIfNeeded];[self applyFilter];[self.collection setContentOffset:CGPointMake(0,-self.collection.adjustedContentInset.top) animated:NO];}
- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {[self applyFilter];}
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {[searchBar resignFirstResponder];}
- (void)refreshLocal {
    NSUInteger generation=++self.localGeneration;NSString *selected=WPSelectedPetDirectory();NSURL *defaultDirectory=[NSURL fileURLWithPath:WPDefaultPetDirectory() isDirectory:YES];NSURL *online=[WPPetCatalog cacheRootDirectory];NSURL *imports=[NSURL fileURLWithPath:[WPDataDirectory() stringByAppendingPathComponent:@"ImportedPets"] isDirectory:YES];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        NSMutableArray<NSURL *> *directories=[NSMutableArray new];if(defaultDirectory)[directories addObject:defaultDirectory];
        if(selected.length)[directories addObject:[NSURL fileURLWithPath:selected isDirectory:YES]];
        for(NSURL *root in @[online,imports]){NSArray<NSURL *> *children=[NSFileManager.defaultManager contentsOfDirectoryAtURL:root includingPropertiesForKeys:@[NSURLIsDirectoryKey] options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];for(NSURL *child in children){NSNumber *isDirectory=nil;[child getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];if(isDirectory.boolValue)[directories addObject:child];}}
        NSMutableDictionary *byKey=[NSMutableDictionary new];
        for(NSURL *directory in directories){NSDictionary *metadata=WPCReadJSON([directory.path stringByAppendingPathComponent:@"pet.json"]);if(!metadata)continue;NSString *sprite=WPCLocalSpritePath(directory.path,metadata);if(!sprite.length)continue;
            NSString *key=WPCKeyForDirectory(directory,metadata);NSMutableDictionary *entry=[WPCReadJSON([directory.path stringByAppendingPathComponent:@"catalog-entry.json"]) mutableCopy]?:[NSMutableDictionary new];
            entry[@"wp_key"]=key;entry[@"wp_directory"]=directory.path;entry[@"displayName"]=WPCString(metadata[@"displayName"]).length?metadata[@"displayName"]:@"未命名桌宠";
            entry[@"submittedBy"]=WPCString(metadata[@"submittedBy"]).length?metadata[@"submittedBy"]:WPCString(metadata[@"author"]);
            if(!WPCString(entry[@"slug"]).length)entry[@"slug"]=WPCString(metadata[@"id"]);
            entry[@"wp_localImport"]=@([WPCString(metadata[@"source"]) isEqualToString:@"local-import"]);
            // Prefer the currently selected copy, otherwise prefer an actual downloaded copy over the bundled default.
            if(!byKey[key] || [directory.path isEqualToString:selected] || ![WPCString(byKey[key][@"wp_directory"]) isEqualToString:selected])byKey[key]=entry;
        }
        NSArray *local=[byKey.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [WPCString(a[@"displayName"]) localizedStandardCompare:WPCString(b[@"displayName"])];}];
        dispatch_async(dispatch_get_main_queue(),^{if(generation!=self.localGeneration)return;self.localPets=local;[self applyFilter];});
    });
}
- (void)applyFilter {
    NSMutableDictionary *localMap=[NSMutableDictionary new];for(NSDictionary *entry in self.localPets)localMap[entry[@"wp_key"]]=entry;
    NSMutableArray *online=[NSMutableArray new];for(NSDictionary *raw in self.allPets){NSString *key=[@"petdex:" stringByAppendingString:WPCString(raw[@"slug"])];NSMutableDictionary *entry=[raw mutableCopy];entry[@"wp_key"]=key;if(localMap[key])entry[@"wp_directory"]=localMap[key][@"wp_directory"];[online addObject:entry];}
    NSInteger segment=self.segments.selectedSegmentIndex;NSArray *source=segment==2?self.localPets:online;NSDictionary *counts=[WPPreferences() dictionaryForKey:WPCatalogUsageKey]?:@{};
    if(segment==1){NSMutableDictionary *all=[NSMutableDictionary new];for(NSDictionary *entry in online)all[entry[@"wp_key"]]=entry;for(NSDictionary *entry in self.localPets)all[entry[@"wp_key"]]=entry;
        source=[[all.allValues filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *entry,NSDictionary *bindings){return [counts[entry[@"wp_key"]] unsignedIntegerValue]>0;}]] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){NSUInteger ca=[counts[a[@"wp_key"]] unsignedIntegerValue],cb=[counts[b[@"wp_key"]] unsignedIntegerValue];return ca==cb?[WPCString(a[@"displayName"]) localizedStandardCompare:WPCString(b[@"displayName"])]:ca>cb?NSOrderedAscending:NSOrderedDescending;}];
    }
    NSString *query=[self.searchBar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    self.shownPets=query.length?[source filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *entry,NSDictionary *bindings){NSString *haystack=[NSString stringWithFormat:@"%@ %@ %@",WPCString(entry[@"displayName"]),WPCString(entry[@"submittedBy"]),WPCString(entry[@"slug"])];return [haystack rangeOfString:query options:NSCaseInsensitiveSearch|NSDiacriticInsensitiveSearch].location!=NSNotFound;}]]:source;
    self.countLabel.text=[NSString stringWithFormat:@"%lu 个桌宠%@",(unsigned long)self.shownPets.count,segment==0?@" · Petdex":segment==1?@" · 本机使用记录":@" · 已保存在本机"];
    self.noteLabel.text=segment==1?@"按本机切换使用次数排序；Petdex 未提供全站人气数据。":segment==2?@"包含内置、在线下载和本地导入的桌宠包，可直接切换。":self.catalogError?@"当前显示缓存目录；可继续搜索和使用已下载桌宠。":@"选择喜欢的桌宠，下载后可离线使用。";
    self.emptyLabel.text=self.shownPets.count?@"":query.length?@"没有找到符合名称或作者的桌宠":segment==1?@"使用桌宠后，会在这里按本机次数排序":segment==2?@"还没有可用的本地桌宠\n点右上角导入桌宠包":self.catalogLoaded?@"暂时无法加载桌宠目录\n请稍后重新打开":@"正在加载 Petdex 桌宠目录…";
    [self.collection reloadData];
}
- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {return self.shownPets.count;}
- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {return CGSizeMake(floor((collectionView.bounds.size.width-44)/2),290);}
- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    WPCatalogCell *cell=[collectionView dequeueReusableCellWithReuseIdentifier:@"pet" forIndexPath:indexPath];NSDictionary *entry=self.shownPets[indexPath.item];NSString *key=entry[@"wp_key"];
    [[WPCThumbnailLoader shared] cancel:cell.imageToken];cell.imageToken=nil;cell.representedKey=key;cell.preview.image=nil;cell.previewHint.hidden=NO;cell.previewHint.text=@"加载预览…";
    cell.nameLabel.text=WPCString(entry[@"displayName"]);NSString *author=WPCString(entry[@"submittedBy"]);NSUInteger count=[[WPPreferences() dictionaryForKey:WPCatalogUsageKey][key] unsignedIntegerValue];
    cell.authorLabel.text=self.segments.selectedSegmentIndex==1?[NSString stringWithFormat:@"本机使用 %lu 次",(unsigned long)count]:author.length?author:[entry[@"wp_localImport"] boolValue]?@"本地导入":@"未署名";
    NSString *selected=WPSelectedPetDirectory();if(!selected.length)selected=[NSURL fileURLWithPath:WPDefaultPetDirectory() isDirectory:YES].path;
    BOOL active=[WPCString(entry[@"wp_directory"]) isEqualToString:selected],busy=[self.downloading containsObject:key],downloaded=WPCString(entry[@"wp_directory"]).length>0;
    [cell.useButton setTitle:busy?@"下载中…":active?@"正在使用":downloaded?@"使用":@"下载并使用" forState:UIControlStateNormal];
    [cell.useButton setImage:busy?nil:[UIImage systemImageNamed:active?@"checkmark.circle.fill":downloaded?@"play.circle":@"arrow.down.circle"] forState:UIControlStateNormal];cell.useButton.imageEdgeInsets=UIEdgeInsetsMake(0,-3,0,3);cell.useButton.enabled=!busy;
    busy?[cell.spinner startAnimating]:[cell.spinner stopAnimating];
    __weak WPCatalogCell *weakCell=cell;__weak typeof(self) weakSelf=self;
    if(self.previewsVisible && !self.previewsSuspended)cell.imageToken=[[WPCThumbnailLoader shared] requestEntry:entry completion:^(UIImage *image){WPCatalogCell *current=weakCell;if(!weakSelf.previewsVisible || weakSelf.previewsSuspended || ![current.representedKey isEqualToString:key])return;current.preview.image=image;current.previewHint.hidden=image!=nil;current.previewHint.text=@"预览暂不可用";}];
    cell.action=^{[weakSelf useEntry:entry];};return cell;
}
- (void)collectionView:(UICollectionView *)collectionView didEndDisplayingCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)indexPath {if([cell isKindOfClass:WPCatalogCell.class]){WPCatalogCell *pet=(id)cell;[[WPCThumbnailLoader shared] cancel:pet.imageToken];pet.imageToken=nil;pet.representedKey=nil;pet.preview.image=nil;}}
- (void)selectDirectory:(NSURL *)directory {
    if(!WPSelectPetDirectory(directory)){[self showError:@"桌宠选择未能保存，请稍后重试。"];return;}WPCatalogRecordUsageForDirectory(directory);
    [NSNotificationCenter.defaultCenter postNotificationName:WPSelectedPetDidChangeNotification object:nil];[self refreshLocal];
}
- (void)useEntry:(NSDictionary *)entry {
    NSString *directory=WPCString(entry[@"wp_directory"]);if(directory.length){[self selectDirectory:[NSURL fileURLWithPath:directory isDirectory:YES]];return;}
    NSString *key=entry[@"wp_key"];if([self.downloading containsObject:key])return;[self.downloading addObject:key];[self.collection reloadData];__weak typeof(self) weakSelf=self;
    [[WPPetCatalog sharedCatalog] downloadPet:entry completion:^(NSURL *localDirectory,NSError *error){typeof(self) self=weakSelf;if(!self)return;[self.downloading removeObject:key];if(localDirectory)[self selectDirectory:localDirectory];else{[self.collection reloadData];[self showError:error.localizedDescription?:@"桌宠下载失败，请稍后重试。"];}}];
}
- (void)showError:(NSString *)message {UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"桌宠库" message:message preferredStyle:UIAlertControllerStyleAlert];[alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];if(!self.presentedViewController)[self presentViewController:alert animated:YES completion:nil];}
- (void)importPackage {UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeZIP] asCopy:YES];picker.delegate=self;picker.allowsMultipleSelection=NO;[self presentViewController:picker animated:YES completion:nil];}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url=urls.firstObject;if(!url)return;self.navigationItem.rightBarButtonItem.enabled=NO;[self.loading startAnimating];
    NSURL *root=[NSURL fileURLWithPath:[WPDataDirectory() stringByAppendingPathComponent:@"ImportedPets"] isDirectory:YES];__weak typeof(self) weakSelf=self;
    [WPPetImporter importZipAtURL:url destinationRoot:root completion:^(NSURL *directory,NSError *error){typeof(self) self=weakSelf;if(!self)return;self.navigationItem.rightBarButtonItem.enabled=YES;if(self.catalogLoaded)[self.loading stopAnimating];if(directory){[self selectDirectory:directory];self.segments.selectedSegmentIndex=2;[self applyFilter];}else[self showError:error.localizedDescription?:@"桌宠包导入失败。"];}];
}
@end
