#import "WPPetRanking.h"
#import <math.h>

static const NSUInteger WPRankingMaximumBytes = 1024 * 1024;
static NSError *WPRankingError(NSString *text) {
    return [NSError errorWithDomain:@"WePet.PetdexRanking" code:1 userInfo:@{NSLocalizedDescriptionKey:text}];
}
/// Validate and normalize both server responses and saved snapshots. Never
/// substitute local use counts for missing or malformed official data.
static NSArray<NSDictionary *> *WPRankingParse(NSData *data, BOOL cached) {
    if (!data.length || data.length > WPRankingMaximumBytes) return nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSArray *pets = [json isKindOfClass:NSDictionary.class] && [json[@"pets"] isKindOfClass:NSArray.class] ? json[@"pets"] : nil;
    if (!pets.count || pets.count > 60) return nil;
    NSCharacterSet *invalid = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-."] .invertedSet;
    NSMutableArray *items = [NSMutableArray arrayWithCapacity:pets.count];
    NSMutableSet *seen = [NSMutableSet new];
    double previous = INFINITY;
    for (id pet in pets) {
        if (![pet isKindOfClass:NSDictionary.class]) return nil;
        NSString *slug = [pet[@"slug"] isKindOfClass:NSString.class] ? pet[@"slug"] : nil;
        id count = cached ? pet[@"installCount"] : ([pet[@"metrics"] isKindOfClass:NSDictionary.class] ? pet[@"metrics"][@"installCount"] : nil);
        if (!slug.length || slug.length > 180 || [slug isEqualToString:@"."] || [slug isEqualToString:@".."] || [slug rangeOfCharacterFromSet:invalid].location != NSNotFound || [seen containsObject:slug]) return nil;
        if (![count isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)count) == CFBooleanGetTypeID()) return nil;
        double value = [count doubleValue];
        if (!isfinite(value) || value < 0 || value > 1000000000000.0 || floor(value) != value || value > previous) return nil;
        previous = value;
        [seen addObject:slug];
        [items addObject:@{@"slug":slug, @"installCount":count}];
    }
    return items;
}
static NSURL *WPRankingCacheURL(void) {
    NSURL *base = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
    if (!base) return nil;
    NSURL *dir = [base URLByAppendingPathComponent:@"WeChatPetRanking" isDirectory:YES];
    if (![NSFileManager.defaultManager createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil]) return nil;
    return [dir URLByAppendingPathComponent:@"petdex-most-installed.json"];
}
static NSArray<NSDictionary *> *WPRankingCached(void) {
    NSURL *url = WPRankingCacheURL();
    NSDictionary *attributes = url ? [NSFileManager.defaultManager attributesOfItemAtPath:url.path error:nil] : nil;
    if (![attributes[NSFileType] isEqual:NSFileTypeRegular] || [attributes[NSFileSize] unsignedLongLongValue] > WPRankingMaximumBytes) return nil;
    NSData *data = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:nil];
    return WPRankingParse(data, YES);
}

@interface WPPetRanking ()
@property(nonatomic,strong) NSURLSession *session;
@property(nonatomic,strong) NSMutableArray<WPPetRankingCompletion> *callbacks;
@property(nonatomic) BOOL loading;
@property(nonatomic,copy) NSArray<NSDictionary *> *recent;
@property(nonatomic,strong) NSDate *recentDate;
@end
@implementation WPPetRanking
+ (instancetype)sharedRanking {
    static WPPetRanking *ranking; static dispatch_once_t once;
    dispatch_once(&once, ^{ ranking=[self new]; }); return ranking;
}
- (instancetype)init {
    if ((self=[super init])) {
        NSURLSessionConfiguration *config=[NSURLSessionConfiguration ephemeralSessionConfiguration];
        config.timeoutIntervalForRequest=10; config.timeoutIntervalForResource=15;
        config.requestCachePolicy=NSURLRequestReloadIgnoringLocalCacheData;
        config.HTTPAdditionalHeaders=@{@"Accept":@"application/json", @"User-Agent":@"WePet/0.1 (Petdex personal companion)"};
        _session=[NSURLSession sessionWithConfiguration:config]; _callbacks=[NSMutableArray new];
    }
    return self;
}
- (void)loadWithCompletion:(WPPetRankingCompletion)completion {
    if (!completion) return;
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ [self loadWithCompletion:completion]; }); return; }
    if (self.recent.count && -self.recentDate.timeIntervalSinceNow < 300) { completion(self.recent, NO, nil); return; }
    [self.callbacks addObject:[completion copy]];
    if (self.loading) return;
    self.loading=YES;
    NSURL *url=[NSURL URLWithString:@"https://petdex.dev/api/pets/search?sort=installed&limit=60&includeMeta=0"];
    NSURLSessionDownloadTask *task=[self.session downloadTaskWithURL:url completionHandler:^(NSURL *file, NSURLResponse *response, NSError *networkError) {
        NSHTTPURLResponse *http=[response isKindOfClass:NSHTTPURLResponse.class]?(NSHTTPURLResponse *)response:nil;
        NSString *host=http.URL.host.lowercaseString;
        BOOL allowedHost=[host isEqualToString:@"petdex.dev"] || [host isEqualToString:@"www.petdex.dev"];
        NSDictionary *attributes=file?[NSFileManager.defaultManager attributesOfItemAtPath:file.path error:nil]:nil;
        BOOL validResponse=!networkError && http.statusCode>=200 && http.statusCode<300 && [http.URL.scheme.lowercaseString isEqualToString:@"https"] && allowedHost && [attributes[NSFileType] isEqual:NSFileTypeRegular] && [attributes[NSFileSize] unsignedLongLongValue]<=WPRankingMaximumBytes;
        NSData *data=validResponse?[NSData dataWithContentsOfURL:file options:NSDataReadingMappedIfSafe error:nil]:nil;
        NSArray *fresh=WPRankingParse(data, NO);
        NSArray *items=fresh ?: WPRankingCached(); BOOL cached=!fresh && items.count>0;
        if (fresh) {
            NSData *saved=[NSJSONSerialization dataWithJSONObject:@{@"pets":fresh} options:0 error:nil];
            NSURL *destination=WPRankingCacheURL();
            if (saved && destination) [saved writeToURL:destination options:NSDataWritingAtomic error:nil];
        }
        NSError *failure=fresh?nil:WPRankingError(cached?@"当前无法更新 Petdex 排行，显示上次获取的排行。":@"Petdex 排行暂时不可用，请稍后重试。");
        dispatch_async(dispatch_get_main_queue(), ^{
            self.loading=NO;
            if (fresh) { self.recent=fresh; self.recentDate=NSDate.date; }
            NSArray *callbacks=[self.callbacks copy]; [self.callbacks removeAllObjects];
            for (WPPetRankingCompletion callback in callbacks) callback(items ?: @[], cached, failure);
        });
    }];
    [task resume];
}
@end
