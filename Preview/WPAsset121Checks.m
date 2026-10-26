#import "WPAsset121Checks.h"
#import "WPPagedPet.h"
#import "WPPetRenderer.h"
#import "WPCommon.h"
#import "WPZipArchive.h"
#import <ImageIO/ImageIO.h>
#import <QuartzCore/QuartzCore.h>
#import <zlib.h>
extern NSString *WPCatalogPreviewLocalSpritePath(NSString *directory);
extern NSURL *WPPreviewImportPetArchive(NSData *archive,NSURL *root,NSError **error);
@interface WPPetRenderer (WPAsset121Testing)
- (void)showFrame;
@end
static NSData *WPAsset121Pixels(CGImageRef image,CGRect rect) {
    CGImageRef part=image?CGImageCreateWithImageInRect(image,rect):NULL;size_t w=rect.size.width,h=rect.size.height;
    CGColorSpaceRef color=CGColorSpaceCreateDeviceRGB();CGContextRef context=part?CGBitmapContextCreate(NULL,w,h,8,w*4,color,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big):NULL;CGColorSpaceRelease(color);
    NSData *data=nil;if(context){CGContextDrawImage(context,CGRectMake(0,0,w,h),part);data=[NSData dataWithBytes:CGBitmapContextGetData(context) length:w*h*4];CGContextRelease(context);}if(part)CGImageRelease(part);return data;
}
static CGImageRef WPAsset121Image(NSString *file) {
    CGImageSourceRef source=CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:file],(__bridge CFDictionaryRef)@{(__bridge id)kCGImageSourceShouldCache:@NO});
    CGImageRef image=source?CGImageSourceCreateImageAtIndex(source,0,NULL):NULL;if(source)CFRelease(source);return image;
}
static NSDictionary *WPAsset121MakeLegacy(NSString *directory,NSInteger version) {
    NSInteger rows=version==1?9:(version==2?11:29),columns=version==4?10:8;
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    CGColorSpaceRef colors=CGColorSpaceCreateDeviceRGB();CGContextRef context=CGBitmapContextCreate(NULL,columns*192,rows*208,8,columns*192*4,colors,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);CGColorSpaceRelease(colors);
    for(NSInteger row=0;row<rows;row++)for(NSInteger frame=0;frame<columns;frame++){
        CGContextSetRGBFillColor(context,(row+1)/(CGFloat)(rows+1),(frame+1)/(CGFloat)(columns+1),.3,1);
        CGContextFillRect(context,CGRectMake(frame*192+32,row*208+20,128,168));
        // Antialiased translucency also catches premultiply/PNG round trips.
        CGContextSetRGBFillColor(context,.23,.61,.92,.47);CGContextFillEllipseInRect(context,CGRectMake(frame*192+30,row*208+16,132,178));
    }
    CGImageRef image=context?CGBitmapContextCreateImage(context):NULL;if(context)CGContextRelease(context);
    NSString *file=[directory stringByAppendingPathComponent:@"spritesheet.png"];CGImageDestinationRef destination=image?CGImageDestinationCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:file],CFSTR("public.png"),1,NULL):NULL;
    if(destination)CGImageDestinationAddImage(destination,image,NULL);BOOL written=destination&&CGImageDestinationFinalize(destination);if(destination)CFRelease(destination);if(image)CGImageRelease(image);if(!written)return nil;
    NSMutableArray *counts=[NSMutableArray new];for(NSInteger row=0;row<rows;row++)[counts addObject:@(columns)];
    NSDictionary *metadata=@{@"id":@"asset121-custom",@"displayName":[NSString stringWithFormat:@"Legacy %ld",(long)version],@"spriteVersionNumber":@(version),@"spritesheetPath":@"spritesheet.png",@"frameWidth":@192,@"frameHeight":@208,@"columns":@(columns),@"rows":@(rows),@"frameRate":@15,@"frameCounts":counts};
    [[NSJSONSerialization dataWithJSONObject:metadata options:0 error:nil] writeToFile:[directory stringByAppendingPathComponent:@"pet.json"] atomically:YES];return metadata;
}
@interface WPAsset121Runner : NSObject
@property(nonatomic) NSMutableDictionary *checks;
@property(nonatomic) NSString *root;
@property(nonatomic) NSString *previous;
@property(nonatomic) NSString *legacy4;
@property(nonatomic) WPPetRenderer *pet;
@property(nonatomic) UIImage *oldImage;
@property(nonatomic) NSDictionary *cachedMetadata;
@property(nonatomic,weak) WPPetRenderer *releasedPet;
@property(nonatomic,copy) void (^completion)(NSDictionary *);
@property(nonatomic) NSUInteger step;
@property(nonatomic) CFTimeInterval deadline;
@property(nonatomic) NSTimer *timer;
@end
@implementation WPAsset121Runner
- (void)finish {
    [self.timer invalidate];self.timer=nil;[self.pet setAnimationActive:NO];self.pet=nil;self.oldImage=nil;
    if(self.previous.length)WPSelectPetDirectory([NSURL fileURLWithPath:self.previous]);else WPResetSelectedPet();
    [NSFileManager.defaultManager removeItemAtPath:self.root error:nil];WPPreviewSetAtlasLoadingSynchronous(YES);
    void (^completion)(NSDictionary *)=self.completion;self.completion=nil;completion(self.checks);
}
- (BOOL)ready {
    return ![[self.pet valueForKey:@"reloadInFlight"] boolValue] && ![[self.pet valueForKey:@"rowDecodeInFlight"] boolValue] && ((UIImage *)[self.pet valueForKey:@"atlas"]).CGImage;
}
- (void)poll {
    if(CACurrentMediaTime()>self.deadline){self.checks[@"asset121AsynchronousWorkNeverHangs"]=@NO;[self finish];return;}
    switch(self.step){
    case 0:if([self ready]){
        UIImage *atlas=[self.pet valueForKey:@"atlas"];self.oldImage=atlas;self.cachedMetadata=[self.pet valueForKey:@"metadata"];
        self.checks[@"asset121CatalogUsesMigratedLegacyPageForThumbnail"]=@([[WPCatalogPreviewLocalSpritePath(self.legacy4) lastPathComponent] isEqual:@"paged-row-00.png"]);
        self.checks[@"asset121ExistingLegacyMigratesOnFirstUseWithoutSelectionChange"]=@([WPSelectedPetDirectory() isEqual:self.legacy4] && [[[self.pet valueForKey:@"assetDirectory"] lastPathComponent] isEqual:@".wp-paged-v121"] && CGImageGetHeight(atlas.CGImage)==208);
        CGPoint center=self.pet.center;[self.pet playSemanticAction:@"tap"];
        self.checks[@"asset121ActionDecodeKeepsPriorVisibleImageAndPosition"]=@([self.pet valueForKey:@"atlas"]==atlas && CGPointEqualToPoint(center,self.pet.center) && [[self.pet valueForKey:@"rowDecodeInFlight"] boolValue]);
        self.step++;
    }break;
    case 1:if([self ready] && [[self.pet valueForKey:@"loadedAtlasRow"] integerValue]==6){
        self.checks[@"asset121BackgroundActionDecodePublishesAtFirstFrame"]=@([[self.pet valueForKey:@"frameIndex"] integerValue]==0 && [[self.pet valueForKey:@"greetingUntil"] doubleValue]>CACurrentMediaTime());
        for(NSNumber *row in @[@1,@2,@5]){[self.pet setValue:row forKey:@"animationRow"];[self.pet setValue:@0 forKey:@"frameIndex"];[self.pet showFrame];}
        self.checks[@"asset121RapidActionChangesKeepOnlyLatestDesiredRow"]=@([[self.pet valueForKey:@"desiredAtlasRow"] integerValue]==5 && [[self.pet valueForKey:@"rowDecodeInFlight"] boolValue]);self.step++;
    }break;
    case 2:if([self ready] && [[self.pet valueForKey:@"loadedAtlasRow"] integerValue]==5){
        self.checks[@"asset121OldDecodedActionCannotReplaceNewestAction"]=@YES;
        [self.pet setValue:@8 forKey:@"animationRow"];[self.pet showFrame];[self.pet setAnimationActive:NO];
        self.checks[@"asset121BackgroundImmediatelyReleasesVisibleImage"]=@([self.pet valueForKey:@"atlas"]==nil && ((CALayer *)[self.pet valueForKey:@"spriteLayer"]).contents==nil);self.step++;
    }break;
    case 3:if(![[self.pet valueForKey:@"rowDecodeInFlight"] boolValue]){
        self.checks[@"asset121CanceledDecodeCannotRestoreBackgroundImage"]=@([self.pet valueForKey:@"atlas"]==nil);
        [self.pet setAnimationActive:YES];[self.pet setAnimationActive:YES];
        self.checks[@"asset121ForegroundReusesValidatedMetadataWithoutFullReload"]=@([self.pet valueForKey:@"metadata"]==self.cachedMetadata && ![[self.pet valueForKey:@"reloadInFlight"] boolValue]);self.step++;
    }break;
    case 4:if([self ready]){
        [self.pet setValue:@2 forKey:@"animationRow"];[self.pet showFrame];self.releasedPet=self.pet;self.pet=nil;self.oldImage=nil;self.cachedMetadata=nil;self.step++;
    }break;
    case 5:if(!self.releasedPet){
        self.checks[@"asset121PendingDecodeDoesNotRetainRenderer"]=@YES;self.checks[@"asset121AsynchronousWorkNeverHangs"]=@YES;[self finish];
    }break;
    }
}
- (void)start {
    self.checks=[NSMutableDictionary new];self.checks[@"asset121CatalogUsesCompactDefaultWithoutFullAtlas"]=@([[WPCatalogPreviewLocalSpritePath([WPResourceBundle().resourcePath stringByAppendingPathComponent:@"DefaultPet"]) lastPathComponent] isEqual:@"compact-row-00.png"]);self.previous=WPSelectedPetDirectory();
    self.root=[[[WPDataDirectory() stringByAppendingPathComponent:@"ImportedPets"] stringByAppendingPathComponent:NSUUID.UUID.UUIDString] copy];
    self.deadline=CACurrentMediaTime()+40;WPPreviewSetAtlasLoadingSynchronous(NO);
    dispatch_async(WPPetAssetWorkQueue(),^{@autoreleasepool {
        @try {
            for(NSInteger version=1;version<=4;version++)@autoreleasepool {
                NSString *directory=version==4?self.root:[self.root stringByAppendingPathComponent:[NSString stringWithFormat:@"legacy%ld",(long)version]];
                NSDictionary *metadata=WPAsset121MakeLegacy(directory,version);NSError *error=nil;NSString *paged=metadata?WPPagedLegacyDirectory(directory,metadata,&error):nil;
                NSDictionary *result=paged?[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[paged stringByAppendingPathComponent:@"pet.json"]] options:0 error:nil]:nil;
                CGImageRef original=WPAsset121Image([directory stringByAppendingPathComponent:@"spritesheet.png"]);BOOL exact=original!=NULL&&paged!=nil;
                for(NSUInteger row=0;row<[result[@"rowAtlasPaths"] count];row++)@autoreleasepool {
                    CGImageRef page=WPAsset121Image([paged stringByAppendingPathComponent:result[@"rowAtlasPaths"][row]]);
                    CGRect rect=CGRectMake(0,row*208,[metadata[@"columns"] integerValue]*192,208);NSData *expected=WPAsset121Pixels(original,rect);rect.origin.y=0;
                    exact&=page&&[expected isEqual:WPAsset121Pixels(page,rect)];if(page)CGImageRelease(page);
                }
                if(original)CGImageRelease(original);
                self.checks[[NSString stringWithFormat:@"asset121LegacyV%ldAllRowsPixelIdentical",(long)version]]=@(exact);
                self.checks[[NSString stringWithFormat:@"asset121LegacyV%ldPreservesGridTimingAndCounts",(long)version]]=@(WPIsLocalPagedMetadata(result)&&[result[@"columns"] isEqual:metadata[@"columns"]]&&[result[@"rows"] isEqual:metadata[@"rows"]]&&[result[@"frameCounts"] isEqual:metadata[@"frameCounts"]]&&[result[@"frameRate"] isEqual:metadata[@"frameRate"]]&&error==nil);
                NSDictionary *attributes=[NSFileManager.defaultManager attributesOfItemAtPath:[paged stringByAppendingPathComponent:@"pet.json"] error:nil];NSString *again=WPPagedLegacyDirectory(directory,metadata,nil);
                self.checks[[NSString stringWithFormat:@"asset121LegacyV%ldMigrationIsReusedWithoutReencoding",(long)version]]=@([again isEqual:paged]&&[attributes[NSFileModificationDate] isEqual:[NSFileManager.defaultManager attributesOfItemAtPath:[again stringByAppendingPathComponent:@"pet.json"] error:nil][NSFileModificationDate]]);
                if(version==4){self.legacy4=directory;[NSFileManager.defaultManager removeItemAtPath:paged error:nil];}
            }
            NSURL *fixture=[WPResourceBundle() URLForResource:@"AtlasCorrectionFixture" withExtension:@"zip"];
            NSURL *archiveRoot=[NSURL fileURLWithPath:[self.root stringByAppendingPathComponent:@"known"]];NSError *error=nil;
            NSDictionary *files=WPExtractPetZip([NSData dataWithContentsOfURL:fixture],archiveRoot,&error);
            // Assemble the known v4 import as an ordinary stored ZIP to test
            // the real import path, using existing byte-for-byte fixture art.
            NSMutableData *zip=[NSMutableData new],*central=[NSMutableData new];
            NSArray *names=@[@"pet.json",@"spritesheet.png"];
            for(NSString *name in names){NSData *body=[NSData dataWithContentsOfURL:files[[@"v4/" stringByAppendingString:name]]];NSData *nameData=[name dataUsingEncoding:NSUTF8StringEncoding];uint32_t crc=(uint32_t)crc32(0,body.bytes,(uInt)body.length),size=(uint32_t)body.length,offset=(uint32_t)zip.length;
                uint32_t local=0x04034b50;uint16_t v=20,z=0,n=(uint16_t)nameData.length;
                [zip appendBytes:&local length:4];[zip appendBytes:&v length:2];for(int i=0;i<4;i++)[zip appendBytes:&z length:2];[zip appendBytes:&crc length:4];[zip appendBytes:&size length:4];[zip appendBytes:&size length:4];[zip appendBytes:&n length:2];[zip appendBytes:&z length:2];[zip appendData:nameData];[zip appendData:body];
                uint32_t sig=0x02014b50,zero=0;[central appendBytes:&sig length:4];[central appendBytes:&v length:2];[central appendBytes:&v length:2];for(int i=0;i<4;i++)[central appendBytes:&z length:2];[central appendBytes:&crc length:4];[central appendBytes:&size length:4];[central appendBytes:&size length:4];[central appendBytes:&n length:2];for(int i=0;i<4;i++)[central appendBytes:&z length:2];[central appendBytes:&zero length:4];[central appendBytes:&offset length:4];[central appendData:nameData];}
            uint32_t start=(uint32_t)zip.length,centralSize=(uint32_t)central.length,end=0x06054b50;uint16_t zero=0,count=2;[zip appendData:central];[zip appendBytes:&end length:4];[zip appendBytes:&zero length:2];[zip appendBytes:&zero length:2];[zip appendBytes:&count length:2];[zip appendBytes:&count length:2];[zip appendBytes:&centralSize length:4];[zip appendBytes:&start length:4];[zip appendBytes:&zero length:2];
            NSURL *imported=WPPreviewImportPetArchive(zip,[NSURL fileURLWithPath:[self.root stringByAppendingPathComponent:@"imported"]],&error);
            NSDictionary *meta=imported?[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:[imported URLByAppendingPathComponent:@"pet.json"]] options:0 error:nil]:nil;
            self.checks[@"asset121NewLegacyImportPublishesPagedV5Atomically"]=@(imported&&error==nil&&WPIsLocalPagedMetadata(meta)&&[meta[@"rowAtlasPaths"] count]==29);
        }@catch(NSException *exception){self.checks[@"asset121MigrationHasNoUnexpectedException"]=@NO;NSLog(@"Asset121: %@",exception.name);}
        CFRunLoopPerformBlock(CFRunLoopGetMain(),kCFRunLoopCommonModes,^{
            if(!self.legacy4){self.checks[@"asset121AsynchronousWorkNeverHangs"]=@NO;[self finish];return;}
            WPSelectPetDirectory([NSURL fileURLWithPath:self.legacy4]);CFTimeInterval started=CACurrentMediaTime();self.pet=[[WPPetRenderer alloc] initWithFrame:CGRectMake(0,0,192,208)];
            self.checks[@"asset121ReloadReturnsBeforeBackgroundImageDecode"]=@([self.pet valueForKey:@"atlas"]==nil&&[[self.pet valueForKey:@"reloadInFlight"] boolValue]&&CACurrentMediaTime()-started<.25);
            self.timer=[NSTimer scheduledTimerWithTimeInterval:.02 target:self selector:@selector(poll) userInfo:nil repeats:YES];
        });CFRunLoopWakeUp(CFRunLoopGetMain());
    }});
}
@end
void WPAsset121RunPreviewChecks(void (^completion)(NSDictionary<NSString *,NSNumber *> *checks)) {
    WPAsset121Runner *runner=[WPAsset121Runner new];runner.completion=completion;[runner start];
}
