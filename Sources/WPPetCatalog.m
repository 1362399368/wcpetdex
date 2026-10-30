#import "WPPetCatalog.h"
#import "WPCommon.h"
#import <ImageIO/ImageIO.h>

static NSString * const WPCatalogErrorDomain = @"WePet.Petdex";
static const NSUInteger WPMaximumAssetBytes = 32 * 1024 * 1024;

static NSError *WPError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:WPCatalogErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: message}];
}
static void WPDeliver(dispatch_block_t block) { dispatch_async(dispatch_get_main_queue(), block); }
static NSString *WPString(id value) { return [value isKindOfClass:NSString.class] ? value : nil; }

/// Animation rows have trailing empty atlas cells. Return the last nonempty frame per row.
static NSArray<NSNumber *> *WPFrameCounts(CGImageSourceRef source, NSUInteger width, NSUInteger height) {
    CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    if (!image) return nil;
    if (!width || !height || width > SIZE_MAX / height) { CGImageRelease(image); return nil; }
    // Only opacity is needed here. A full RGBA scratch image was four times
    // larger, on top of ImageIO's decoded image and the renderer's own atlas.
    void *pixels = calloc(height, width);
    CGContextRef context = pixels ? CGBitmapContextCreate(pixels, width, height, 8, width, NULL, (CGBitmapInfo)kCGImageAlphaOnly) : NULL;
    if (!context) { free(pixels); CGImageRelease(image); return nil; }
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
    NSMutableArray *counts = [NSMutableArray array];
    const unsigned char *bytes = pixels;
    BOOL anyPainted = NO;
    BOOL hasTransparency = NO;
    for (NSUInteger pixel = 0; pixel < width * height; pixel++) {
        if (bytes[pixel] < 250) { hasTransparency = YES; break; }
    }
    for (NSUInteger row = 0; row < height / 208; row++) {
        NSUInteger lastFrame = 0;
        for (NSUInteger frame = 0; frame < 8; frame++) {
            BOOL painted = NO;
            for (NSUInteger y = row * 208; y < (row + 1) * 208 && !painted; y++) {
                for (NSUInteger x = frame * 192; x < (frame + 1) * 192; x++) {
                    if (bytes[y * width + x] > 12) { painted = YES; break; }
                }
            }
            if (painted) { lastFrame = frame + 1; anyPainted = YES; }
        }
        [counts addObject:@(MAX(lastFrame, 1))];
    }
    CGContextRelease(context);
    free(pixels);
    CGImageRelease(image);
    return anyPainted && hasTransparency ? counts : nil;
}

/// Only official asset hosts are accepted. Historical Petdex hosts are rewritten to the live CDN.
static NSURL *WPAssetURL(NSString *value, NSString *base) {
    if (!value.length) return nil;
    NSURL *url = [NSURL URLWithString:value relativeToURL:base.length ? [NSURL URLWithString:[base stringByAppendingString:@"/"]] : nil].absoluteURL;
    if (![url.scheme.lowercaseString isEqualToString:@"https"] || url.user.length || url.password.length) return nil;
    NSSet *hosts = [NSSet setWithArray:@[@"assets.petdex.dev", @"petdex-assets.raillyhugo.workers.dev", @"pub-94495283df974cfea5e98d6a9e3fa462.r2.dev"]];
    if (![hosts containsObject:url.host.lowercaseString]) return nil;
    NSURLComponents *parts = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:YES];
    parts.host = @"assets.petdex.dev";
    parts.port = nil;
    return parts.URL;
}

static NSArray<NSDictionary *> *WPParseManifest(NSData *data, NSError **error) {
    NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![manifest isKindOfClass:NSDictionary.class] || ![manifest[@"pets"] isKindOfClass:NSArray.class]) {
        if (error) *error = WPError(2, @"Petdex 目录格式不正确。");
        return nil;
    }
    BOOL compact = [manifest[@"v"] isKindOfClass:NSNumber.class] && [manifest[@"v"] integerValue] == 2;
    NSArray *fields = @[@"slug", @"displayName", @"kind", @"submittedBy", @"spritesheet", @"petJson", @"zip", @"spriteVersionNumber"];
    if (compact && ![manifest[@"fields"] isEqual:fields]) {
        if (error) *error = WPError(3, @"Petdex 目录版本发生变化，请更新插件。");
        return nil;
    }
    NSString *base = compact ? WPString(manifest[@"assetBase"]) : nil;
    if (compact && !WPAssetURL(base, nil)) {
        if (error) *error = WPError(4, @"Petdex 资源地址不受支持。");
        return nil;
    }
    NSArray *entries = manifest[@"pets"];
    if (manifest[@"total"] && (![manifest[@"total"] isKindOfClass:NSNumber.class] || [manifest[@"total"] unsignedIntegerValue] != entries.count)) {
        if (error) *error = WPError(5, @"Petdex 目录数量不完整。");
        return nil;
    }
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:entries.count];
    NSMutableSet *seen = [NSMutableSet set];
    for (id raw in entries) {
        NSDictionary *entry = raw;
        if (compact) {
            if (![raw isKindOfClass:NSArray.class] || [raw count] != fields.count) continue;
            entry = [NSDictionary dictionaryWithObjects:raw forKeys:fields];
        } else if (![raw isKindOfClass:NSDictionary.class]) continue;
        NSString *slug = WPString(entry[@"slug"]);
        NSString *name = WPString(entry[@"displayName"]);
        NSURL *sprite = WPAssetURL(WPString(entry[compact ? @"spritesheet" : @"spritesheetUrl"]), base);
        NSURL *json = WPAssetURL(WPString(entry[compact ? @"petJson" : @"petJsonUrl"]), base);
        if (!slug.length || !name.length || !sprite || !json || [seen containsObject:slug]) continue;
        [seen addObject:slug];
        [result addObject:@{@"slug":slug, @"displayName":name,
                            @"kind":WPString(entry[@"kind"]) ?: @"creature",
                            @"submittedBy":WPString(entry[@"submittedBy"]) ?: @"",
                            @"spritesheetUrl":sprite.absoluteString, @"petJsonUrl":json.absoluteString,
                            @"spriteVersionNumber":[entry[@"spriteVersionNumber"] isKindOfClass:NSNumber.class] ? entry[@"spriteVersionNumber"] : @1}];
    }
    if (!result.count && entries.count) {
        if (error) *error = WPError(6, @"Petdex 目录中没有可用的桌宠。");
        return nil;
    }
    return result;
}

@interface WPCatalogRequest : NSObject
@property(nonatomic,strong) NSURL *url;
@property(nonatomic,strong) NSURLSessionDownloadTask *task;
@property(nonatomic,strong) NSError *error;
@property(nonatomic,copy) void (^completion)(NSData *, NSError *);
@end
@implementation WPCatalogRequest
@end

@interface WPPetCatalog () <NSURLSessionDownloadDelegate>
@property(nonatomic, strong) NSURLSession *session;
@property(nonatomic, strong) NSOperationQueue *requestQueue;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *,WPCatalogRequest *> *activeRequests;
@property(nonatomic, strong) NSMutableArray<WPCatalogRequest *> *waitingRequests;
@property(nonatomic, copy) NSArray<NSDictionary *> *cachedPets;
@property(nonatomic, strong) NSDate *catalogDate;
@property(nonatomic, strong) NSError *catalogError;
@property(nonatomic, strong) NSMutableArray *pendingLoads;
@end

@implementation WPPetCatalog
+ (instancetype)sharedCatalog {
    static WPPetCatalog *catalog;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ catalog = [self new]; });
    return catalog;
}
+ (NSURL *)cacheRootDirectory {
    NSURL *library = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *root = [library URLByAppendingPathComponent:@"WePet/Pets" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:nil];
    // Pet atlases are user-downloaded data, not disposable cache. Clear the
    // historical backup exclusion on existing installs as well as new ones.
    [root setResourceValue:@NO forKey:NSURLIsExcludedFromBackupKey error:nil];
    return root;
}
- (instancetype)init {
    if ((self = [super init])) {
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        config.timeoutIntervalForRequest = 18;
        config.timeoutIntervalForResource = 60;
        config.HTTPMaximumConnectionsPerHost = 2;
        config.URLCache = nil;
        config.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        config.HTTPAdditionalHeaders = @{@"User-Agent":@"WePet/0.1 (Petdex personal companion)", @"Accept":@"application/json,image/webp,image/png"};
        _requestQueue = [NSOperationQueue new];
        _requestQueue.name = @"WeChatPet.CatalogRequests";
        _requestQueue.maxConcurrentOperationCount = 1;
        _requestQueue.qualityOfService = NSQualityOfServiceUtility;
        _session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:_requestQueue];
        _activeRequests = [NSMutableDictionary new];
        _waitingRequests = [NSMutableArray new];
        _pendingLoads = [NSMutableArray new];
    }
    return self;
}
- (void)requestURL:(NSURL *)url completion:(void (^)(NSData *, NSError *))completion {
    WPCatalogRequest *request = [WPCatalogRequest new];
    request.url = url;request.completion = completion;
    [self.requestQueue addOperationWithBlock:^{
        [self.waitingRequests addObject:request];
        [self startWaitingRequests];
    }];
}
- (void)startWaitingRequests {
    // Transfer bodies stay in NSURLSession's temporary files, with no more
    // than two active downloads. Decode/write completions share this serial
    // queue so opening several pets cannot decode several atlases at once.
    while (self.activeRequests.count < 2 && self.waitingRequests.count) {
        WPCatalogRequest *request = self.waitingRequests.firstObject;
        [self.waitingRequests removeObjectAtIndex:0];
        request.task = [self.session downloadTaskWithURL:request.url];
        self.activeRequests[@(request.task.taskIdentifier)] = request;
        [request.task resume];
    }
}
- (void)finishRequest:(WPCatalogRequest *)request data:(NSData *)data error:(NSError *)error {
    if (!request || !self.activeRequests[@(request.task.taskIdentifier)]) return;
    [self.activeRequests removeObjectForKey:@(request.task.taskIdentifier)];
    void (^completion)(NSData *, NSError *) = request.completion;
    request.completion = nil;request.task = nil;
    @autoreleasepool { if (completion) completion(error ? nil : data, error); }
    [self startWaitingRequests];
}
- (NSError *)errorForResponse:(NSURLResponse *)response {
    NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? [(NSHTTPURLResponse *)response statusCode] : 0;
    if (status < 200 || status >= 300) return WPError(status, [NSString stringWithFormat:@"Petdex 返回 HTTP %ld。", (long)status]);
    if (response.expectedContentLength > (int64_t)WPMaximumAssetBytes) return WPError(7, @"资源为空或超过 32 MB 限制。");
    return nil;
}
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    WPCatalogRequest *request = self.activeRequests[@(task.taskIdentifier)];
    if (!request) return;
    NSError *error = [self errorForResponse:task.response];
    if (!error && (totalBytesWritten > (int64_t)WPMaximumAssetBytes || totalBytesExpectedToWrite > (int64_t)WPMaximumAssetBytes))
        error = WPError(7, @"资源为空或超过 32 MB 限制。");
    if (error) { request.error = error;[task cancel]; }
}
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task didFinishDownloadingToURL:(NSURL *)location {
    WPCatalogRequest *request = self.activeRequests[@(task.taskIdentifier)];
    if (!request) return;
    NSError *error = request.error ?: [self errorForResponse:task.response];
    NSNumber *size = nil;
    if (!error && ![location getResourceValue:&size forKey:NSURLFileSizeKey error:&error]) size = nil;
    if (!error && (!size.unsignedLongLongValue || size.unsignedLongLongValue > WPMaximumAssetBytes))
        error = WPError(7, @"资源为空或超过 32 MB 限制。");
    NSData *data = !error ? [NSData dataWithContentsOfURL:location options:NSDataReadingMappedIfSafe error:&error] : nil;
    if (!error && !data.length) error = WPError(7, @"资源为空或超过 32 MB 限制。");
    [self finishRequest:request data:data error:error];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    WPCatalogRequest *request = self.activeRequests[@(task.taskIdentifier)];
    if (request) [self finishRequest:request data:nil error:request.error ?: error ?: WPError(7, @"未能读取下载的资源。")];
}
- (void)loadPetsWithCompletion:(WPPetCatalogCompletion)completion {
    if (!NSThread.isMainThread) { WPDeliver(^{ [self loadPetsWithCompletion:completion]; }); return; }
    NSTimeInterval lifetime = self.catalogError ? 60 : 300;
    if (self.cachedPets && self.catalogDate && -self.catalogDate.timeIntervalSinceNow < lifetime) { completion(self.cachedPets, self.catalogError); return; }
    [self.pendingLoads addObject:[completion copy]];
    if (self.pendingLoads.count > 1) return;
    NSArray *urls = @[@"https://assets.petdex.dev/manifests/petdex-v2.json", @"https://www.petdex.dev/api/manifest/v2", @"https://petdex.dev/api/manifest"];
    [self tryManifestURLs:urls index:0 lastError:nil];
}
- (void)tryManifestURLs:(NSArray<NSString *> *)urls index:(NSUInteger)index lastError:(NSError *)lastError {
    if (index >= urls.count) {
        NSURL *cache = [[WPPetCatalog cacheRootDirectory] URLByAppendingPathComponent:@"manifest.json"];
        NSData *data = [NSData dataWithContentsOfURL:cache];
        if (!data) data = [NSData dataWithContentsOfFile:[WPResourceDirectory() stringByAppendingPathComponent:@"petdex-manifest-snapshot.json"]];
        NSError *parseError;
        NSArray *pets = self.cachedPets ?: (data ? WPParseManifest(data, &parseError) : nil);
        [self finishCatalog:pets ?: @[] error:lastError ?: parseError ?: WPError(8, @"暂时无法连接 Petdex，请稍后重试。")];
        return;
    }
    [self requestURL:[NSURL URLWithString:urls[index]] completion:^(NSData *data, NSError *error) {
        NSArray *pets = error ? nil : WPParseManifest(data, &error);
        WPDeliver(^{
            if (!pets) { [self tryManifestURLs:urls index:index + 1 lastError:error]; return; }
            NSURL *cache = [[WPPetCatalog cacheRootDirectory] URLByAppendingPathComponent:@"manifest.json"];
            [data writeToURL:cache options:NSDataWritingAtomic error:nil];
            self.catalogDate = [NSDate date];
            [self finishCatalog:pets error:nil];
        });
    }];
}
- (void)finishCatalog:(NSArray<NSDictionary *> *)pets error:(NSError *)error {
    self.cachedPets = pets;
    self.catalogDate = [NSDate date];
    self.catalogError = error;
    NSArray *callbacks = [self.pendingLoads copy];
    [self.pendingLoads removeAllObjects];
    for (WPPetCatalogCompletion callback in callbacks) callback(pets, error);
}
- (void)loadPetsMatchingQuery:(NSString *)query page:(NSUInteger)page pageSize:(NSUInteger)pageSize completion:(WPPetCatalogPageCompletion)completion {
    [self loadPetsWithCompletion:^(NSArray<NSDictionary *> *pets, NSError *error) {
        NSString *needle = [query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSArray *filtered = needle.length ? [pets filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *pet, NSDictionary *bindings) {
            NSString *text = [NSString stringWithFormat:@"%@ %@ %@", pet[@"slug"], pet[@"displayName"], pet[@"submittedBy"]];
            return [text rangeOfString:needle options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location != NSNotFound;
        }]] : pets;
        NSUInteger size = MIN(MAX(pageSize, 1), 100);
        NSUInteger start = page <= NSUIntegerMax / size ? MIN(page * size, filtered.count) : filtered.count;
        completion([filtered subarrayWithRange:NSMakeRange(start, MIN(size, filtered.count - start))], filtered.count, error);
    }];
}
- (void)downloadPet:(NSDictionary *)pet completion:(WPPetDownloadCompletion)completion {
    NSString *slug = WPString(pet[@"slug"]);
    NSCharacterSet *safe = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-."];
    if (!slug.length || slug.length > 180 || [slug rangeOfCharacterFromSet:safe.invertedSet].location != NSNotFound || [slug isEqualToString:@"."] || [slug isEqualToString:@".."]) {
        WPDeliver(^{ completion(nil, WPError(9, @"桌宠标识不正确。")); }); return;
    }
    NSURL *jsonURL = WPAssetURL(WPString(pet[@"petJsonUrl"]), nil);
    NSURL *spriteURL = WPAssetURL(WPString(pet[@"spritesheetUrl"]), nil);
    if (!jsonURL || !spriteURL) { WPDeliver(^{ completion(nil, WPError(10, @"桌宠资源地址不受支持。")); }); return; }
    NSURL *destination = [[WPPetCatalog cacheRootDirectory] URLByAppendingPathComponent:slug isDirectory:YES];
    [self requestURL:jsonURL completion:^(NSData *metadataData, NSError *error) {
        if (error) { WPDeliver(^{ completion(nil, error); }); return; }
        NSDictionary *metadata = [NSJSONSerialization JSONObjectWithData:metadataData options:0 error:&error];
        if (![metadata isKindOfClass:NSDictionary.class]) { WPDeliver(^{ completion(nil, WPError(11, @"桌宠描述文件不正确。")); }); return; }
        [self requestURL:spriteURL completion:^(NSData *spriteData, NSError *assetError) {
            if (assetError) { WPDeliver(^{ completion(nil, assetError); }); return; }
            CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)spriteData, NULL);
            NSDictionary *properties = source ? CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL)) : nil;
            NSUInteger width = [properties[(__bridge NSString *)kCGImagePropertyPixelWidth] unsignedIntegerValue];
            NSUInteger height = [properties[(__bridge NSString *)kCGImagePropertyPixelHeight] unsignedIntegerValue];
            BOOL hasAlpha = [properties[(__bridge NSString *)kCGImagePropertyHasAlpha] boolValue];
            if (!hasAlpha || width != 1536 || (height != 1872 && height != 2288)) {
                if (source) CFRelease(source);
                WPDeliver(^{ completion(nil, WPError(12, @"此资源需为带透明通道的 8×9 或 8×11 Petdex 动画图集。")); }); return;
            }
            NSArray *frameCounts = WPFrameCounts(source, width, height);
            CFRelease(source);
            if (!frameCounts) { WPDeliver(^{ completion(nil, WPError(13, @"无法解码动画图集，或资源没有可用的透明桌宠画面。")); }); return; }
            NSError *saveError;
            NSURL *staging = [[WPPetCatalog cacheRootDirectory] URLByAppendingPathComponent:[@".download-" stringByAppendingString:NSUUID.UUID.UUIDString] isDirectory:YES];
            NSFileManager *fm = NSFileManager.defaultManager;
            [fm createDirectoryAtURL:staging withIntermediateDirectories:YES attributes:nil error:&saveError];
            NSString *extension = spriteURL.pathExtension.lowercaseString;
            NSString *filename = [extension isEqualToString:@"png"] ? @"spritesheet.png" : @"spritesheet.webp";
            NSMutableDictionary *localMetadata = [metadata mutableCopy];
            localMetadata[@"spritesheetPath"] = filename;
            localMetadata[@"source"] = @"Petdex";
            localMetadata[@"sourceURL"] = [@"https://petdex.dev/pets/" stringByAppendingString:slug];
            localMetadata[@"submittedBy"] = WPString(pet[@"submittedBy"]) ?: @"";
            localMetadata[@"frameWidth"] = @192;
            localMetadata[@"frameHeight"] = @208;
            localMetadata[@"columns"] = @8;
            localMetadata[@"rows"] = @(height / 208);
            localMetadata[@"frameCounts"] = frameCounts;
            localMetadata[@"spriteVersionNumber"] = height == 2288 ? @2 : @1;
            if (!saveError) [spriteData writeToURL:[staging URLByAppendingPathComponent:filename] options:NSDataWritingAtomic error:&saveError];
            NSData *localJSON = !saveError ? [NSJSONSerialization dataWithJSONObject:localMetadata options:NSJSONWritingPrettyPrinted error:&saveError] : nil;
            if (!saveError) [localJSON writeToURL:[staging URLByAppendingPathComponent:@"pet.json"] options:NSDataWritingAtomic error:&saveError];
            if (!saveError) [metadataData writeToURL:[staging URLByAppendingPathComponent:@"upstream-pet.json"] options:NSDataWritingAtomic error:&saveError];
            NSData *entryJSON = !saveError ? [NSJSONSerialization dataWithJSONObject:pet options:NSJSONWritingPrettyPrinted error:&saveError] : nil;
            if (!saveError) [entryJSON writeToURL:[staging URLByAppendingPathComponent:@"catalog-entry.json"] options:NSDataWritingAtomic error:&saveError];
            if (!saveError) {
                @synchronized (self) {
                    if ([fm fileExistsAtPath:destination.path]) {
                        [fm replaceItemAtURL:destination withItemAtURL:staging backupItemName:nil options:0 resultingItemURL:nil error:&saveError];
                    } else [fm moveItemAtURL:staging toURL:destination error:&saveError];
                }
            }
            if (saveError) [fm removeItemAtURL:staging error:nil];
            WPDeliver(^{ completion(saveError ? nil : destination, saveError); });
        }];
    }];
}
@end
