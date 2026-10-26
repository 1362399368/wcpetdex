#import "WPYue2Checks.h"
#import "WPCommon.h"
#import "WPPetImporter.h"
#import "WPPetRenderer.h"
#import <QuartzCore/QuartzCore.h>
#import <mach/mach.h>

extern UIImage *WPCatalogPreviewThumbnailForData(NSData *data);

@interface WPPetRenderer (WPYue2Testing)
- (void)showFrame;
- (void)tick:(id)link;
- (NSInteger)countForRow:(NSInteger)row;
@end
@interface WPYue2TestClock : NSObject
@property(nonatomic) CFTimeInterval timestamp;
@end
@implementation WPYue2TestClock
@end

static uint64_t WPYue2Footprint(void) {
    task_vm_info_data_t info={0};mach_msg_type_number_t count=TASK_VM_INFO_COUNT;
    return task_info(mach_task_self(),TASK_VM_INFO,(task_info_t)&info,&count)==KERN_SUCCESS?info.phys_footprint:0;
}
static BOOL WPYue2SingleStrip(WPPetRenderer *pet) {
    UIImage *image=[pet valueForKey:@"atlas"];
    NSData *mask=[pet valueForKey:@"alphaMask"];
    return image.CGImage && CGImageGetWidth(image.CGImage)==3840 && CGImageGetHeight(image.CGImage)==208 && (mask==nil || mask.length==4992);
}
static BOOL WPYue2Released(WPPetRenderer *pet) {
    CALayer *layer=[pet valueForKey:@"spriteLayer"];
    return [pet valueForKey:@"atlas"]==nil && [pet valueForKey:@"alphaMask"]==nil &&
        [pet valueForKey:@"displayLink"]==nil && layer.contents==nil;
}
/// Compare every local pixel to a native ImageIO/CGImage crop of the visible
/// frame. This catches a wrong semantic-row-to-physical-row conversion.
static NSDictionary *WPYue2HitPixels(WPPetRenderer *pet,NSInteger frame) {
    [pet setValue:@(frame) forKey:@"frameIndex"];[pet showFrame];
    UIImage *image=[pet valueForKey:@"atlas"];CALayer *layer=[pet valueForKey:@"spriteLayer"];
    CGImageRef crop=image.CGImage?CGImageCreateWithImageInRect(image.CGImage,CGRectMake(frame*192,0,192,208)):NULL;
    unsigned char *alpha=calloc(192*208,1);
    CGContextRef context=(crop && alpha)?CGBitmapContextCreate(alpha,192,208,8,192,NULL,(CGBitmapInfo)kCGImageAlphaOnly):NULL;
    if(context)CGContextDrawImage(context,CGRectMake(0,0,192,208),crop);
    NSUInteger errors=0,opaque=0,transparent=0;
    BOOL mirror=layer.transform.m11<0;
    if(context)for(NSUInteger y=0;y<208;y++)for(NSUInteger x=0;x<192;x++){
        BOOL expected=alpha[y*192+(mirror?191-x:x)]>12;
        BOOL actual=[pet pointInside:CGPointMake(x+.5,y+.5) withEvent:nil];
        errors+=(expected!=actual);opaque+=expected;transparent+=!expected;
    }
    if(context)CGContextRelease(context);if(crop)CGImageRelease(crop);free(alpha);
    return @{@"passed":@(context && errors==0 && opaque>1000 && transparent>1000),
             @"mismatches":@(errors),@"opaquePixels":@(opaque),@"clearPixels":@(transparent),@"mirrored":@(mirror)};
}
static BOOL WPYue2IsDefaultFallback(void) {
    return [[[WPPreferences() dictionaryForKey:@"selectedPetLastLoad"] objectForKey:@"loadedDirectoryName"] isEqual:WPDefaultPetDirectory().lastPathComponent];
}
static void WPYue2SavePreview(WPPetRenderer *pet,UIImage *thumbnail) {
    [pet setValue:@0 forKey:@"animationRow"];[pet setValue:@0 forKey:@"frameIndex"];[pet showFrame];
    [pet setNeedsLayout];[pet layoutIfNeeded];
    UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat defaultFormat];format.scale=1;
    UIImage *preview=[[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(440,260) format:format] imageWithActions:^(UIGraphicsImageRendererContext *context){
        [[UIColor colorWithRed:.91 green:.94 blue:.97 alpha:1] setFill];UIRectFill(CGRectMake(0,0,440,260));
        [@"Yue2 renderer" drawAtPoint:CGPointMake(18,12) withAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:16],NSForegroundColorAttributeName:UIColor.darkGrayColor}];
        [@"Imported preview" drawAtPoint:CGPointMake(234,12) withAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:16],NSForegroundColorAttributeName:UIColor.darkGrayColor}];
        CGContextSaveGState(context.CGContext);CGContextTranslateCTM(context.CGContext,18,38);[pet.layer renderInContext:context.CGContext];CGContextRestoreGState(context.CGContext);
        [thumbnail drawInRect:CGRectMake(234,38,192,208)];
    }];
    [UIImagePNGRepresentation(preview) writeToFile:[WPDataDirectory() stringByAppendingPathComponent:@"yue2-preview.png"] atomically:YES];
}

void WPYue2RunPreviewChecks(void (^completion)(NSDictionary *results)) {
    NSCAssert(NSThread.isMainThread,@"Yue2 UIKit checks run on main");
    NSMutableDictionary *checks=[NSMutableDictionary new];
    NSMutableDictionary *measurements=[NSMutableDictionary new];
    NSString *previous=[WPSelectedPetDirectory() copy];
    NSURL *package=[WPResourceBundle() URLForResource:@"Yue2Pet" withExtension:@"zip"];
    checks[@"v5RealPackageBundledForTest"]=@(package!=nil);
    if(!package){completion(checks);return;}
    NSURL *destination=[NSURL fileURLWithPath:[WPDataDirectory() stringByAppendingPathComponent:@"ImportedPets"] isDirectory:YES];
    [WPPetImporter importZipAtURL:package destinationRoot:destination completion:^(NSURL *directory,NSError *error){
        checks[@"v5RealZipImportSucceedsOnMainQueue"]=@(directory && !error && NSThread.isMainThread);
        if(!directory || error){completion(checks);return;}
        WPPetRenderer *pet=nil;
        NSURL *metaURL=[directory URLByAppendingPathComponent:@"pet.json"];
        NSData *originalMetadata=[NSData dataWithContentsOfURL:metaURL];
        NSDictionary *metadata=originalMetadata?[NSJSONSerialization JSONObjectWithData:originalMetadata options:0 error:nil]:nil;
        @try {
            checks[@"v5ImportedSelectionIsAccepted"]=@(WPSelectPetDirectory(directory));
            // Drain setup temporaries before measuring later UIImage lifetimes.
            // KVC and imageWithCGImage can autorelease a setup reference even
            // when the renderer itself correctly relinquishes its ownership.
            @autoreleasepool {
            pet=[[WPPetRenderer alloc] initWithFrame:CGRectMake(0,0,192,208)];[pet setAnimationActive:YES];
            NSDictionary *loaded=[pet valueForKey:@"metadata"];
            checks[@"v5RendererLoadsImportedYue2"]=@([[pet valueForKey:@"petName"] isEqual:metadata[@"displayName"]] && [[loaded objectForKey:@"spriteVersionNumber"] integerValue]==5 &&
                [[[WPPreferences() dictionaryForKey:@"selectedPetLastLoad"] objectForKey:@"loadedDirectoryName"] isEqual:directory.lastPathComponent]);
            checks[@"v5LogicalLayoutAnd30FPS"]=@([[pet valueForKey:@"columns"] integerValue]==20 && [[pet valueForKey:@"rows"] integerValue]==29 && [[pet valueForKey:@"frameRate"] integerValue]==30 && ((CADisplayLink *)[pet valueForKey:@"displayLink"]).preferredFramesPerSecond==30);
            BOOL counts=YES;NSUInteger total=0;
            for(NSInteger row=0;row<29;row++){NSInteger count=[pet countForRow:row];counts&=count==((row==9 || row==10)?16:20);total+=count;}
            checks[@"v5All572FramesRemainAvailable"]=@(counts && total==572);
            checks[@"v5OnlyOneStripAndPackedMaskLoaded"]=@(WPYue2SingleStrip(pet));
            checks[@"v5HitMaskIsLazyBeforeTouch"]=@([pet valueForKey:@"alphaMask"]==nil);
            [pet pointInside:CGPointMake(96,104) withEvent:nil];
            checks[@"v5HitMaskUsesOneCellAfterTouch"]=@(((NSData *)[pet valueForKey:@"alphaMask"]).length==4992);
            UIImage *current=[pet valueForKey:@"atlas"];
            measurements[@"currentDecodedPixelBytes"]=@(CGImageGetBytesPerRow(current.CGImage)*CGImageGetHeight(current.CGImage));
            measurements[@"currentPackedMaskBytes"]=@(((NSData *)[pet valueForKey:@"alphaMask"]).length);
            current=nil;
            }
            BOOL allRows=YES,allRects=YES,oldImagesReleased=YES;
            measurements[@"footprintBeforeRowChanges"]=@(WPYue2Footprint());
            for(NSUInteger cycle=0;cycle<3;cycle++)for(NSInteger row=0;row<29;row++){
                __weak UIImage *oldImage;
                @autoreleasepool {
                    oldImage=[pet valueForKey:@"atlas"];
                    NSInteger prior=[[pet valueForKey:@"loadedAtlasRow"] integerValue];
                    NSInteger lastFrame=(row==9 || row==10)?15:19;
                    [pet setValue:@(row) forKey:@"animationRow"];[pet setValue:@(lastFrame) forKey:@"frameIndex"];[pet showFrame];
                    CALayer *layer=[pet valueForKey:@"spriteLayer"];
                    allRows&=[[pet valueForKey:@"loadedAtlasRow"] integerValue]==row && WPYue2SingleStrip(pet);
                    allRects&=CGRectEqualToRect(layer.contentsRect,CGRectMake((CGFloat)lastFrame/20,0,1.0/20,1)) && layer.contents!=nil;
                    if(prior==row)oldImage=nil;
                }
                [CATransaction flush];oldImagesReleased&=oldImage==nil;
            }
            checks[@"v5All29ActionStripsSwitchWithoutGrowingDimensions"]=@(allRows);
            checks[@"v5PhysicalCropAlwaysUsesOneRow"]=@(allRects);
            checks[@"v5PreviousUIImageReleasedBetweenActions"]=@(oldImagesReleased);
            measurements[@"footprintAfter87RowChanges"]=@(WPYue2Footprint());
            BOOL semantic=YES;
            for(NSString *action in metadata[@"semanticRows"]){
                [pet beginDragAnimation];[pet playSemanticAction:action];
                semantic&=[[pet valueForKey:@"loadedAtlasRow"] integerValue]==[metadata[@"semanticRows"][action] integerValue];
            }
            checks[@"v5SemanticActionsSelectTheirOwnFiles"]=@(semantic);
            [pet beginDragAnimation];[pet updateDragDirectionLeft:NO];
            checks[@"v5RightDragUsesRightRunStrip"]=@([[pet valueForKey:@"loadedAtlasRow"] integerValue]==1);
            NSDictionary *right=WPYue2HitPixels(pet,9);
            checks[@"v5RightRunEveryPixelHitMatchesVisibleFrame"]=right[@"passed"];
            [pet updateDragDirectionLeft:YES];
            checks[@"v5LeftDragUsesLeftRunStrip"]=@([[pet valueForKey:@"loadedAtlasRow"] integerValue]==2);
            NSDictionary *left=WPYue2HitPixels(pet,14);
            checks[@"v5LeftRunEveryPixelHitMatchesVisibleFrame"]=left[@"passed"];
            [pet holdPeekOnLeft:YES];[pet playSemanticAction:@"reveal"];
            [pet setValue:@(CACurrentMediaTime()+10) forKey:@"greetingUntil"];
            NSDictionary *mirror=WPYue2HitPixels(pet,7);
            checks[@"v5MirroredRevealEveryPixelHitMatchesVisibleFrame"]=@([mirror[@"passed"] boolValue] && [mirror[@"mirrored"] boolValue]);
            measurements[@"pixelHitChecks"]=@{@"right":right,@"left":left,@"mirroredReveal":mirror};
            [pet endPeek];[pet beginDragAnimation];[pet endDragAnimation];
            [pet setValue:nil forKey:@"reactionKind"];[pet setValue:@0 forKey:@"greetingUntil"];
            [pet playSemanticAction:@"land"];
            CFTimeInterval start=[[pet valueForKey:@"animationStartedAt"] doubleValue];
            CFTimeInterval until=[[pet valueForKey:@"greetingUntil"] doubleValue];
            checks[@"v5FrameIncreasePreservesLandDuration"]=@(fabs((until-start)-10.0/15)<.005);
            WPYue2TestClock *clock=[WPYue2TestClock new];BOOL visits=YES;
            for(NSInteger frame=0;frame<20;frame++){
                clock.timestamp=start+(frame+.1)/30;[pet tick:clock];visits&=[[pet valueForKey:@"frameIndex"] integerValue]==frame;
            }
            checks[@"v5PlaybackVisitsAll20Frames"]=@(visits);
            [pet setAnimationActive:NO];[CATransaction flush];
            checks[@"v5PauseReleasesStripMaskLayerAndTimer"]=@(WPYue2Released(pet));
            [pet playReaction:@"anger"];pet.peerOnline=YES;pet.angry=YES;[pet showFrame];
            checks[@"v5EventsWhilePausedDoNotReloadStrip"]=@(WPYue2Released(pet));
            pet.angry=NO;pet.peerOnline=NO;[pet setAnimationActive:YES];
            checks[@"v5ResumeRestoresOneStrip"]=@(WPYue2SingleStrip(pet) && [pet valueForKey:@"displayLink"]!=nil);
            BOOL resume=YES;
            for(NSUInteger i=0;i<5;i++){@autoreleasepool{[pet setAnimationActive:NO];[pet setAnimationActive:YES];resume&=WPYue2SingleStrip(pet);}}
            checks[@"v5RepeatedPauseResumeWorks"]=@(resume);
            NSString *first=metadata[@"spritesheetPath"];
            UIImage *thumbnail=WPCatalogPreviewThumbnailForData([NSData dataWithContentsOfURL:[directory URLByAppendingPathComponent:first]]);
            CFDataRef thumbPixels=thumbnail.CGImage?CGDataProviderCopyData(CGImageGetDataProvider(thumbnail.CGImage)):NULL;
            size_t thumbBytes=thumbPixels?(size_t)CFDataGetLength(thumbPixels):0;if(thumbPixels)CFRelease(thumbPixels);
            checks[@"v5ThumbnailVisibleWithIndependentSmallBuffer"]=@(thumbnail.CGImage && CGImageGetWidth(thumbnail.CGImage)==192 && CGImageGetHeight(thumbnail.CGImage)==208 && thumbBytes>=192*208*4 && thumbBytes<=256*208*4);
            measurements[@"thumbnailPixelBytes"]=@(thumbBytes);
            WPYue2SavePreview(pet,thumbnail);
            NSArray *paths=metadata[@"rowAtlasPaths"];
            NSURL *rowURL=[directory URLByAppendingPathComponent:paths[15]];NSData *originalRow=[NSData dataWithContentsOfURL:rowURL];
            @try {
                [NSFileManager.defaultManager removeItemAtURL:rowURL error:nil];[pet reloadPet];
                checks[@"v5MissingActionFallsBackToBundledPet"]=@(WPYue2IsDefaultFallback() && [[pet valueForKey:@"rowAtlasPaths"] count]==29 && CGImageGetWidth(((UIImage *)[pet valueForKey:@"atlas"]).CGImage)>0 && CGImageGetWidth(((UIImage *)[pet valueForKey:@"atlas"]).CGImage)<=1920);
            } @finally {[originalRow writeToURL:rowURL atomically:YES];}
            @try {
                [@"broken PNG" writeToURL:rowURL atomically:YES encoding:NSUTF8StringEncoding error:nil];[pet reloadPet];
                checks[@"v5CorruptActionFallsBackToBundledPet"]=@(WPYue2IsDefaultFallback() && [[pet valueForKey:@"rowAtlasPaths"] count]==29 && CGImageGetWidth(((UIImage *)[pet valueForKey:@"atlas"]).CGImage)>0 && CGImageGetWidth(((UIImage *)[pet valueForKey:@"atlas"]).CGImage)<=1920);
            } @finally {[originalRow writeToURL:rowURL atomically:YES];}
            @try {
                NSMutableDictionary *bad=[metadata mutableCopy];NSMutableArray *names=[paths mutableCopy];names[15]=@"../outside.png";bad[@"rowAtlasPaths"]=names;
                [[NSJSONSerialization dataWithJSONObject:bad options:0 error:nil] writeToURL:metaURL atomically:YES];[pet reloadPet];
                checks[@"v5EscapingLocalPathFallsBackSafely"]=@(WPYue2IsDefaultFallback() && [[pet valueForKey:@"rowAtlasPaths"] count]==29 && CGImageGetWidth(((UIImage *)[pet valueForKey:@"atlas"]).CGImage)>0 && CGImageGetWidth(((UIImage *)[pet valueForKey:@"atlas"]).CGImage)<=1920);
            } @finally {[originalMetadata writeToURL:metaURL atomically:YES];}
            [pet reloadPet];[pet beginDragAnimation];
            @try {
                [NSFileManager.defaultManager removeItemAtURL:rowURL error:nil];[pet playSemanticAction:@"receivePet"];
                checks[@"v5PageRemovedAfterLoadKeepsHealthyIdle"]=@([[pet valueForKey:@"rows"] integerValue]==29 && [[pet valueForKey:@"columns"] integerValue]==20 && [[pet valueForKey:@"rowAtlasPaths"] count]==29 && [[pet valueForKey:@"loadedAtlasRow"] integerValue]==0 && [[pet valueForKey:@"failedAtlasRows"] containsIndex:15] && ((UIImage *)[pet valueForKey:@"atlas"]).CGImage!=nil);
            } @finally {[originalRow writeToURL:rowURL atomically:YES];}
            [pet reloadPet];checks[@"v5SelectionRecoversAfterFilesRestored"]=@(WPYue2SingleStrip(pet) && [[pet valueForKey:@"metadata"][@"spriteVersionNumber"] integerValue]==5);
            checks[@"v5RuntimeChecksNoException"]=@YES;
        } @catch(NSException *exception) {
            checks[@"v5RuntimeChecksNoException"]=@NO;measurements[@"exception"]=exception.reason ?: @"unknown";
        } @finally {
            [pet setAnimationActive:NO];
            [originalMetadata writeToURL:metaURL atomically:YES];
            if(previous.length)WPSelectPetDirectory([NSURL fileURLWithPath:previous isDirectory:YES]);else WPResetSelectedPet();
            [NSFileManager.defaultManager removeItemAtURL:directory error:nil];
        }
        checks[@"v5TestRestoresPreviousSelection"]=@(previous.length?[WPSelectedPetDirectory() isEqual:previous]:WPSelectedPetDirectory()==nil);
        [[NSJSONSerialization dataWithJSONObject:measurements options:NSJSONWritingPrettyPrinted error:nil] writeToFile:[WPDataDirectory() stringByAppendingPathComponent:@"yue2-memory-report.json"] atomically:YES];
        completion(checks);
    }];
}
