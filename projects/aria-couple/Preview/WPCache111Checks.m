#import "WPCache111Checks.h"
#import "WPCatalogController.h"
#import "WPQuickChatBar.h"
#import "WPQuickChatModel.h"
#import <UIKit/UIKit.h>

// Exercise the real private loader without starting a network transfer.
// A fake task records cancellation; all transfer bytes still go through the
// production file sink, cancellation and completion paths.
@interface WPCThumbnailJob : NSObject
@property(nonatomic,copy) NSString *key;
@property(nonatomic,copy) NSString *temporaryPath;
@property(nonatomic,strong) NSURLSessionDataTask *task;
@property(nonatomic,strong) NSMutableDictionary *callbacks;
@property(nonatomic) int outputFile;
@property(nonatomic) NSUInteger receivedBytes;
@property(nonatomic) BOOL active;
@property(nonatomic) BOOL decoding;
- (BOOL)appendBytes:(NSData *)data;
- (void)closeOutput;
- (void)removeTemporaryFile;
@end
@interface WPCThumbnailLoader : NSObject
@property(nonatomic,strong) NSURLSession *session;
@property(nonatomic,strong) NSCache *images;
@property(nonatomic,strong) NSMutableDictionary *jobs;
@property(nonatomic,strong) NSMutableDictionary *subscriptions;
@property(nonatomic,strong) NSMutableDictionary *tasks;
@property(nonatomic,strong) NSMutableArray *pending;
@property(nonatomic) NSUInteger activeCount;
+ (instancetype)shared;
- (void)cancel:(NSString *)token;
- (void)releaseCachedWork;
- (void)releaseCachedWorkForNotification:(NSNotification *)notification;
- (BOOL)settleDecode:(WPCThumbnailJob *)job;
- (void)finish:(WPCThumbnailJob *)job image:(UIImage *)image;
@end
@interface WPCatalogController (WPCache111Testing)
- (void)collectionView:(UICollectionView *)view didEndDisplayingCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)indexPath;
@end
@interface WPQuickChatBar (WPCache111Testing)
- (UITableViewCell *)tableView:(UITableView *)view cellForRowAtIndexPath:(NSIndexPath *)indexPath;
- (void)tableView:(UITableView *)view didEndDisplayingCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath;
@end
@interface WPCache111Task : NSObject
@property(nonatomic) NSUInteger taskIdentifier;
@property(nonatomic) BOOL wasCancelled;
- (void)cancel;
@end
@implementation WPCache111Task
- (void)cancel {self.wasCancelled=YES;}
@end
static UIImage *WPCache111Image(void) {
    UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat defaultFormat];format.scale=1;
    return [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(160,160) format:format] imageWithActions:^(__unused UIGraphicsImageRendererContext *context){[UIColor.systemTealColor setFill];UIRectFill(CGRectMake(0,0,160,160));}];
}
static WPCThumbnailJob *WPCache111Job(WPCThumbnailLoader *loader,NSString *key,BOOL decoding,BOOL *called) {
    WPCThumbnailJob *job=[WPCThumbnailJob new];job.key=key;job.active=YES;job.decoding=decoding;
    WPCache111Task *task=[WPCache111Task new];task.taskIdentifier=(NSUInteger)key.hash;job.task=(id)task;
    NSString *token=[key stringByAppendingString:@"-token"];
    job.callbacks=[@{token:[^(__unused UIImage *image){if(called)*called=YES;} copy]} mutableCopy];
    loader.jobs[key]=job;loader.subscriptions[token]=key;loader.tasks[@(task.taskIdentifier)]=job;loader.activeCount++;
    return job;
}
NSDictionary<NSString *,NSNumber *> *WPCache111PreviewChecks(void) {
    NSMutableDictionary<NSString *,NSNumber *> *checks=[NSMutableDictionary new];
    WPCThumbnailLoader *loader=[WPCThumbnailLoader shared];[loader releaseCachedWork];
    @try {
        @autoreleasepool {
            WPCThumbnailJob *job=[WPCThumbnailJob new];NSData *chunk=[NSMutableData dataWithLength:64*1024];BOOL wrote=YES;
            for(NSUInteger i=0;i<512;i++)if(![job appendBytes:chunk]){wrote=NO;break;}
            NSString *path=job.temporaryPath;
            checks[@"cache111Catalog32MiBTransferUsesFileSink"]=@(wrote && job.receivedBytes==32*1024*1024 && [[[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil] objectForKey:NSFileSize] unsignedLongLongValue]==32*1024*1024);
            checks[@"cache111CatalogRejectsOversizedTransferBeforeWrite"]=@(![job appendBytes:[NSData dataWithBytes:"x" length:1]] && job.receivedBytes==32*1024*1024);
            [job closeOutput];checks[@"cache111CompletedTransferClosesDescriptorBeforeDecode"]=@(job.outputFile<0 && [NSFileManager.defaultManager fileExistsAtPath:path]);
            [job removeTemporaryFile];checks[@"cache111CompletedTransferCanRemoveItsTemporaryFile"]=@(![NSFileManager.defaultManager fileExistsAtPath:path]);
        }
        @autoreleasepool {
            BOOL called=NO;WPCThumbnailJob *job=WPCache111Job(loader,@"cache111-download",NO,&called);WPCache111Task *task=(id)job.task;
            [job appendBytes:[NSData dataWithBytes:"payload" length:7]];NSString *path=job.temporaryPath;
            [loader cancel:@"cache111-download-token"];
            checks[@"cache111CancelStopsTransferAndReleasesTemporaryFile"]=@(task.wasCancelled && job.outputFile<0 && ![NSFileManager.defaultManager fileExistsAtPath:path] && !loader.activeCount && !loader.jobs.count && !loader.tasks.count && !loader.subscriptions.count && !called);
            WPCThumbnailJob *decoding=WPCache111Job(loader,@"cache111-decoding",YES,&called);
            [loader cancel:@"cache111-decoding-token"];
            checks[@"cache111CancelledDecodeKeepsConcurrencySlotUntilItReturns"]=@(loader.activeCount==1 && ![loader settleDecode:decoding] && !loader.activeCount && !called);
        }
        @autoreleasepool {
            BOOL called=NO;WPCThumbnailJob *job=WPCache111Job(loader,@"cache111-stale",NO,&called);
            [job appendBytes:[NSData dataWithBytes:"pending" length:7]];NSString *path=job.temporaryPath;
            UIImage *image=WPCache111Image();[loader.images setObject:image forKey:@"cache111-old"];
            [loader releaseCachedWorkForNotification:nil];[loader finish:job image:image];
            checks[@"cache111ClosedCatalogCannotRepopulateCacheFromLateCompletion"]=@(!loader.jobs.count && !loader.pending.count && !loader.tasks.count && !loader.subscriptions.count && !loader.activeCount && ![loader.images objectForKey:@"cache111-old"] && ![loader.images objectForKey:job.key] && ![NSFileManager.defaultManager fileExistsAtPath:path] && !called);
            NSURLSessionConfiguration *configuration=loader.session.configuration;
            checks[@"cache111CatalogDoesNotDuplicateAtlasInHTTPOrCookieCaches"]=@(configuration.URLCache==nil && configuration.HTTPCookieStorage==nil && configuration.requestCachePolicy==NSURLRequestReloadIgnoringLocalCacheData);
        }
        @autoreleasepool {
            WPCatalogController *controller=[WPCatalogController new];UICollectionViewCell *cell=[[NSClassFromString(@"WPCatalogCell") alloc] initWithFrame:CGRectMake(0,0,140,290)];UIImageView *preview=[cell valueForKey:@"preview"];
            preview.image=WPCache111Image();[cell setValue:@"cache111-offscreen" forKey:@"representedKey"];
            [controller collectionView:nil didEndDisplayingCell:cell forItemAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:0]];
            checks[@"cache111OffscreenCatalogReuseCellReleasesBitmapAndIdentity"]=@(preview.image==nil && [cell valueForKey:@"representedKey"]==nil);
            WPQuickChatBar *bar=[[WPQuickChatBar alloc] initWithFrame:CGRectMake(0,0,76,200)];WPQuickChatSession *session=[WPQuickChatSession new];session.username=@"wxid_cache111_fixture";
            [bar reloadWithSessions:@[session]];[bar setNeedsLayout];[bar layoutIfNeeded];UITableView *table=[bar valueForKey:@"table"];[table reloadData];[table layoutIfNeeded];NSIndexPath *path=[NSIndexPath indexPathForRow:0 inSection:0];UITableViewCell *chat=[table cellForRowAtIndexPath:path];UIImageView *avatar=[chat valueForKey:@"avatar"];BOOL hadImage=avatar.image!=nil;
            [bar reloadWithSessions:@[]];[table layoutIfNeeded];
            [bar tableView:table didEndDisplayingCell:chat forRowAtIndexPath:path];
            checks[@"cache111OffscreenQuickChatReuseCellReleasesAvatar"]=@(hadImage && avatar.image==nil && [chat valueForKey:@"representedUsername"]==nil);
            [bar reloadWithSessions:@[session]];[table reloadData];[table layoutIfNeeded];UITableViewCell *rebuilt=[table cellForRowAtIndexPath:path];
            checks[@"cache111QuickChatCanRebuildAvatarAfterCellRelease"]=@([[rebuilt valueForKey:@"avatar"] image]!=nil && [[rebuilt valueForKey:@"representedUsername"] isEqual:session.username]);bar.hidden=YES;
        }
    } @catch(NSException *exception){checks[@"cache111LifecycleChecksDoNotThrow"]=@NO;NSLog(@"Cache111 check exception: %@ %@",exception.name,exception.reason);checks[@"cache111ExceptionReason"]=(id)(exception.reason?:exception.name);}
    @finally {[loader releaseCachedWork];}
    return checks;
}
