#import "WPMemory110Checks.h"
#import "WPQuickChatBar.h"
#import "WPQuickChatModel.h"
#import "WPUnreadAvatarControl.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <zlib.h>

extern UIImage *WPPreviewDecodeLocalAvatarValue(id value);
extern NSURL *WPPreviewImportPetArchive(NSData *archive,NSURL *root,NSError **error);
extern void WPPreviewCleanupImportStaging(NSURL *root);

@interface WPUnreadAvatarControl (WPMemory110Testing)
- (void)memoryWarning:(NSNotification *)notification;
- (void)acceptAvatar:(UIImage *)image;
@end

static UIImage *WPMemory110Image(CGSize size) {
    UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat defaultFormat];format.scale=1;
    return [[[UIGraphicsImageRenderer alloc] initWithSize:size format:format] imageWithActions:^(__unused UIGraphicsImageRendererContext *context){
        [UIColor.systemTealColor setFill];UIRectFill((CGRect){CGPointZero,size});
        [UIColor.whiteColor setFill];UIRectFill(CGRectMake(size.width/4,size.height/4,size.width/2,size.height/2));
    }];
}
static void WPMemory110Append16(NSMutableData *data,uint16_t number) {
    uint8_t bytes[2]={(uint8_t)number,(uint8_t)(number>>8)};[data appendBytes:bytes length:sizeof(bytes)];
}
static void WPMemory110Append32(NSMutableData *data,uint32_t number) {
    uint8_t bytes[4]={(uint8_t)number,(uint8_t)(number>>8),(uint8_t)(number>>16),(uint8_t)(number>>24)};[data appendBytes:bytes length:sizeof(bytes)];
}
// Tiny stored archive exercises the real file extractor/importer without
// allocating a second large animation atlas in the preview host.
static NSData *WPMemory110InvalidPetZip(void) {
    NSMutableData *archive=[NSMutableData new],*central=[NSMutableData new];
    NSDictionary<NSString *,NSData *> *files=@{@"pet.json":[@"{\"spriteVersionNumber\":4,\"spritesheetPath\":\"spritesheet.png\"}" dataUsingEncoding:NSUTF8StringEncoding],@"spritesheet.png":UIImagePNGRepresentation(WPMemory110Image(CGSizeMake(8,8)))};
    for(NSString *path in [files.allKeys sortedArrayUsingSelector:@selector(compare:)]){
        NSData *name=[path dataUsingEncoding:NSUTF8StringEncoding],*content=files[path];
        uint32_t offset=(uint32_t)archive.length,crc=(uint32_t)crc32(0,content.bytes,(uInt)content.length),size=(uint32_t)content.length;
        WPMemory110Append32(archive,0x04034b50);WPMemory110Append16(archive,20);WPMemory110Append16(archive,0);WPMemory110Append16(archive,0);
        WPMemory110Append16(archive,0);WPMemory110Append16(archive,0);WPMemory110Append32(archive,crc);WPMemory110Append32(archive,size);WPMemory110Append32(archive,size);
        WPMemory110Append16(archive,(uint16_t)name.length);WPMemory110Append16(archive,0);[archive appendData:name];[archive appendData:content];
        WPMemory110Append32(central,0x02014b50);WPMemory110Append16(central,20);WPMemory110Append16(central,20);WPMemory110Append16(central,0);WPMemory110Append16(central,0);
        WPMemory110Append16(central,0);WPMemory110Append16(central,0);WPMemory110Append32(central,crc);WPMemory110Append32(central,size);WPMemory110Append32(central,size);
        WPMemory110Append16(central,(uint16_t)name.length);WPMemory110Append16(central,0);WPMemory110Append16(central,0);WPMemory110Append16(central,0);WPMemory110Append16(central,0);WPMemory110Append32(central,0);WPMemory110Append32(central,offset);[central appendData:name];
    }
    uint32_t centralOffset=(uint32_t)archive.length;[archive appendData:central];
    WPMemory110Append32(archive,0x06054b50);WPMemory110Append16(archive,0);WPMemory110Append16(archive,0);WPMemory110Append16(archive,(uint16_t)files.count);WPMemory110Append16(archive,(uint16_t)files.count);
    WPMemory110Append32(archive,(uint32_t)central.length);WPMemory110Append32(archive,centralOffset);WPMemory110Append16(archive,0);return archive;
}

NSDictionary<NSString *,NSNumber *> *WPMemory110PreviewChecks(void) {
    NSMutableDictionary<NSString *,NSNumber *> *checks=[NSMutableDictionary new];
    @autoreleasepool {
        UIImage *large=WPMemory110Image(CGSizeMake(1024,768));NSData *encoded=UIImageJPEGRepresentation(large,.9);
        UIImage *small=WPPreviewDecodeLocalAvatarValue(encoded);CGImageRef image=small.CGImage;
        checks[@"memory110LocalEncodedAvatarDecodesAtMost160Pixels"]=@(image && CGImageGetWidth(image)==160 && CGImageGetHeight(image)==120 && CGImageGetBytesPerRow(image)*CGImageGetHeight(image)<=160*160*4);
        UIImage *alreadySmall=WPMemory110Image(CGSizeMake(80,80));
        checks[@"memory110SmallLocalImagePreservesOriginalPixels"]=@(WPPreviewDecodeLocalAvatarValue(alreadySmall)==alreadySmall);
        checks[@"memory110OversizedLocalUIImageUsesSafeFallback"]=@(WPPreviewDecodeLocalAvatarValue(WPMemory110Image(CGSizeMake(1025,4)))==nil);
        checks[@"memory110MalformedAndOversizedAvatarDataRejected"]=@(WPPreviewDecodeLocalAvatarValue([@"invalid-image" dataUsingEncoding:NSUTF8StringEncoding])==nil && WPPreviewDecodeLocalAvatarValue([NSMutableData dataWithLength:5*1024*1024+1])==nil && WPPreviewDecodeLocalAvatarValue(NSNull.null)==nil);
    }
    @autoreleasepool {
        WPQuickChatBar *bar=[[WPQuickChatBar alloc] initWithFrame:CGRectMake(0,0,76,200)];
        WPQuickChatSession *row=[WPQuickChatSession new];row.username=@"wxid_memory110_fixture";[bar reloadWithSessions:@[row]];
        NSCache *avatars=[bar valueForKey:@"avatars"],*placeholders=[bar valueForKey:@"placeholders"];
        UIImage *fixture=WPMemory110Image(CGSizeMake(80,80));[avatars setObject:fixture forKey:@"fixture"];[placeholders setObject:fixture forKey:@"fixture"];
        [[bar valueForKey:@"titles"] setObject:@"Fixture" forKey:row.username];bar.hidden=YES;
        checks[@"memory110ClosingChatClearsBothImageCachesAndRows"]=@([avatars objectForKey:@"fixture"]==nil && [placeholders objectForKey:@"fixture"]==nil && !bar.sessions.count && ![[bar valueForKey:@"titles"] count]);
        checks[@"memory110ClosingChatCancelsTimerAndDownloads"]=@([bar valueForKey:@"avatarRefreshTimer"]==nil && ![[bar valueForKey:@"avatarDownloads"] count]);
        bar.hidden=NO;[bar reloadWithSessions:@[row]];
        checks[@"memory110ClosedChatCanBeRebuiltFromFreshSessions"]=@(bar.sessions.count==1 && [bar.sessions.firstObject.username isEqual:row.username]);bar.hidden=YES;
    }
    @autoreleasepool {
        // It needs an attached window, but this private test window never
        // becomes key or visible and cannot displace the user's preview.
        UIWindow *window=[[UIWindow alloc] initWithFrame:CGRectMake(0,0,100,100)];
        WPUnreadAvatarControl *avatar=[[WPUnreadAvatarControl alloc] initWithFrame:CGRectMake(0,0,36,36)];[window addSubview:avatar];
        [avatar showUsername:@"wxid_memory110_missing_head" title:@"Fixture"];[avatar setActive:YES];[avatar acceptAvatar:WPMemory110Image(CGSizeMake(160,160))];
        UIImageView *imageView=[avatar valueForKey:@"avatarView"];UIImage *displayed=imageView.image;[avatar memoryWarning:nil];
        checks[@"memory110MemoryWarningKeepsVisibleSmallAvatar"]=@(displayed!=nil && imageView.image==displayed && [avatar valueForKey:@"download"]==nil && [avatar valueForKey:@"retryTimer"]==nil);
        [avatar clearAvatar];[avatar showUsername:@"wxid_memory110_missing_head_2" title:@"Missing"];
        NSTimer *retry=[avatar valueForKey:@"retryTimer"];NSTimeInterval wait=retry.fireDate.timeIntervalSinceNow;
        checks[@"memory110MemoryPressureDefersAvatarRetryForEightSeconds"]=@(retry!=nil && wait>=7 && wait<=8.1 && [[avatar valueForKey:@"localAttempts"] unsignedIntegerValue]==0 && [[avatar valueForKey:@"remoteAttempts"] unsignedIntegerValue]==0);
        [avatar setActive:NO];checks[@"memory110InactiveAvatarCancelsPendingPressureRetry"]=@([avatar valueForKey:@"retryTimer"]==nil && [avatar valueForKey:@"download"]==nil && imageView.image==nil);
        [avatar removeFromSuperview];
    }
    @autoreleasepool {
        NSFileManager *manager=NSFileManager.defaultManager;NSURL *root=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[@"WPMemory110-" stringByAppendingString:NSUUID.UUID.UUIDString]] isDirectory:YES];
        @try {
            [manager createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:nil];
            NSURL *existing=[root URLByAppendingPathComponent:@"existing-pet" isDirectory:YES],*old=[root URLByAppendingPathComponent:@".wp-import-stale" isDirectory:YES],*active=[root URLByAppendingPathComponent:@".wp-import-active" isDirectory:YES];
            for(NSURL *directory in @[existing,old,active])[manager createDirectoryAtURL:directory withIntermediateDirectories:NO attributes:nil error:nil];
            NSData *sentinel=[@"keep existing pet" dataUsingEncoding:NSUTF8StringEncoding];NSURL *marker=[existing URLByAppendingPathComponent:@"pet.json"];[sentinel writeToURL:marker atomically:YES];
            [manager setAttributes:@{NSFileModificationDate:[NSDate dateWithTimeIntervalSinceNow:-48*60*60]} ofItemAtPath:old.path error:nil];
            WPPreviewCleanupImportStaging(root);
            checks[@"memory110ImporterRemovesOnlyStaleOwnedStaging"]=@(![manager fileExistsAtPath:old.path] && [manager fileExistsAtPath:active.path] && [[NSData dataWithContentsOfURL:marker] isEqual:sentinel]);
            [manager removeItemAtURL:active error:nil];NSError *error=nil;NSURL *imported=WPPreviewImportPetArchive(WPMemory110InvalidPetZip(),root,&error);
            NSArray *contents=[manager contentsOfDirectoryAtPath:root.path error:nil];
            checks[@"memory110FailedImportLeavesNoExtractedFilesOrPartialPet"]=@(imported==nil && error!=nil && contents.count==1 && [contents.firstObject isEqual:@"existing-pet"] && [[NSData dataWithContentsOfURL:marker] isEqual:sentinel]);
        } @catch(NSException *exception){checks[@"memory110ImportBoundaryDoesNotThrow"]=@NO;NSLog(@"Memory110 checks: %@",exception.name);}
        @finally {[manager removeItemAtURL:root error:nil];}
    }
    return checks;
}
