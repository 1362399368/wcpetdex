#import "WPStabilityChecks.h"
#import "WPPetRenderer.h"
#import "WPQuickChatBar.h"
#import "WPCommon.h"
#import "WPCoupleClient.h"
#import "WPAssetCorrections.h"
#import "WPZipArchive.h"
#import <mach/mach.h>

extern UIImage *WPCatalogPreviewThumbnailForData(NSData *data);
@interface WPCoupleClient (WPStabilityProtocol)
- (void)handle:(NSDictionary *)event generation:(NSUInteger)generation;
@end

@interface WPPetRenderer (WPStabilityRendererTesting)
- (void)showFrame;
- (void)tick:(id)link;
- (NSInteger)countForRow:(NSInteger)row;
@end
@interface WPStabilityTestClock : NSObject
@property(nonatomic) CFTimeInterval timestamp;
@end
@implementation WPStabilityTestClock
@end

static uint64_t WPFootprint(void) {
    task_vm_info_data_t info={0};mach_msg_type_number_t count=TASK_VM_INFO_COUNT;
    return task_info(mach_task_self(),TASK_VM_INFO,(task_info_t)&info,&count)==KERN_SUCCESS?info.phys_footprint:0;
}

static NSDictionary *WPAtlasCorrectionPreviewChecks(void) {
    NSMutableDictionary *checks=[NSMutableDictionary new];
    NSURL *archive=[WPResourceBundle() URLForResource:@"AtlasCorrectionFixture" withExtension:@"zip"];
    NSURL *newYue2=[WPResourceBundle() URLForResource:@"Yue2Pet" withExtension:@"zip"];
    checks[@"zhouyouKnownOldAssetFixtureAvailable"]=@(archive && newYue2);
    if(!archive || !newYue2)return checks;
    NSString *previousDirectory=WPSelectedPetDirectory(),*previousReference=WPSelectedPetReference();
    NSURL *parent=[NSURL fileURLWithPath:[WPDataDirectory() stringByAppendingPathComponent:@"ImportedPets"] isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:parent withIntermediateDirectories:YES attributes:nil error:nil];
    NSURL *fixture=[parent URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
    NSURL *v4=[parent URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
    NSURL *v5=[parent URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
    WPPetRenderer *pet=nil;
    @try {
        NSError *error=nil;
        NSDictionary *files=WPExtractPetZip([NSData dataWithContentsOfURL:archive options:NSDataReadingMappedIfSafe error:nil],fixture,&error);
        checks[@"zhouyouKnownOldAssetFixtureExtracts"]=@(files.count==7 && error==nil);
        if(!files) return checks;
        NSDictionary *v4meta=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:files[@"v4/pet.json"]] options:0 error:nil];
        NSData *oldAtlas=[NSData dataWithContentsOfURL:files[@"v4/spritesheet.png"]];
        [NSFileManager.defaultManager createDirectoryAtURL:v4 withIntermediateDirectories:NO attributes:nil error:nil];
        NSURL *v4atlas=[v4 URLByAppendingPathComponent:@"spritesheet.png"];
        [oldAtlas writeToURL:v4atlas atomically:YES];
        [[NSData dataWithContentsOfURL:files[@"v4/pet.json"]] writeToURL:[v4 URLByAppendingPathComponent:@"pet.json"] atomically:YES];
        checks[@"zhouyouKnownImportedV4HashMatchesOnlyKnownImage"]=@(WPKnownAtlasCorrections(v4.path,v4meta).count==1);
        BOOL selected=WPSelectPetDirectory(v4);NSString *v4reference=WPSelectedPetReference();
        @autoreleasepool {pet=[[WPPetRenderer alloc] initWithFrame:CGRectMake(0,0,192,208)];}
        UIImage *atlas=[pet valueForKey:@"atlas"];
        checks[@"zhouyouKnownImportedV4UsesCorrectedOneRowWithoutChangingSelection"]=@(selected && [WPSelectedPetReference() isEqual:v4reference] &&
            [WPSelectedPetDirectory() isEqual:v4.path] && [[pet valueForKey:@"assetDirectory"] isEqual:WPDefaultPetDirectory()] &&
            [[pet valueForKey:@"rowAtlasPaths"] count]==29 && CGImageGetWidth(atlas.CGImage)==[[pet valueForKey:@"rowColumnCounts"][0] unsignedIntegerValue]*192 && CGImageGetHeight(atlas.CGImage)==208 &&
            [pet.petName isEqual:v4meta[@"displayName"]]);
        [pet setValue:@20 forKey:@"animationRow"];[pet setValue:@0 forKey:@"frameIndex"];[pet showFrame];
        checks[@"zhouyouKnownImportedV4AngerUsesCorrectedPage"]=@([[pet valueForKey:@"loadedAtlasRow"] integerValue]==20 && CGImageGetHeight(((UIImage *)[pet valueForKey:@"atlas"]).CGImage)==208);
        checks[@"zhouyouKnownImportedV4OriginalFileIsNeverRewritten"]=@([oldAtlas isEqual:[NSData dataWithContentsOfURL:v4atlas]]);
        [pet setAnimationActive:NO];pet=nil;atlas=nil;
        NSMutableData *changed=[oldAtlas mutableCopy];unsigned char marker=0;[changed appendBytes:&marker length:1];
        [changed writeToURL:v4atlas atomically:YES];
        checks[@"zhouyouUnknownImportedV4HashIsNeverOverridden"]=@(WPKnownAtlasCorrections(v4.path,v4meta).count==0);
        [oldAtlas writeToURL:v4atlas atomically:YES];
        NSMutableDictionary *custom=[v4meta mutableCopy];custom[@"id"]=@"user-custom-model";
        BOOL customSafe=WPKnownAtlasCorrections(v4.path,custom).count==0;
        custom=[v4meta mutableCopy];custom[@"assetRevision"]=@"custom";
        checks[@"zhouyouDifferentImportedV4IdOrRevisionIsNeverOverridden"]=@(customSafe && WPKnownAtlasCorrections(v4.path,custom).count==0);

        // Assemble a complete valid imported v5 with four byte-identical old
        // rows; other rows come from the actual package used in this preview.
        NSDictionary *v5files=WPExtractPetZip([NSData dataWithContentsOfURL:newYue2 options:NSDataReadingMappedIfSafe error:nil],v5,&error);
        NSArray *names=@[@"row-08.png",@"row-18.png",@"row-20.png",@"row-21.png"];
        NSMutableDictionary *original=[NSMutableDictionary new];
        for(NSString *name in [names arrayByAddingObject:@"pet.json"]){
            NSData *data=[NSData dataWithContentsOfURL:files[[@"v5/" stringByAppendingString:name]]];
            if(data){[data writeToURL:[v5 URLByAppendingPathComponent:name] atomically:YES];original[name]=data;}
        }
        NSDictionary *v5meta=[NSJSONSerialization JSONObjectWithData:original[@"pet.json"] options:0 error:nil];
        checks[@"zhouyouKnownImportedV5FourRowHashesMatch"]=@(v5files.count==30 && WPKnownAtlasCorrections(v5.path,v5meta).count==4);
        selected=WPSelectPetDirectory(v5);NSString *v5reference=WPSelectedPetReference();
        @autoreleasepool {pet=[[WPPetRenderer alloc] initWithFrame:CGRectMake(0,0,192,208)];}
        BOOL rows=YES,unchanged=YES;
        for(NSString *name in names){
            NSInteger row=[[name substringWithRange:NSMakeRange(4,2)] integerValue];
            [pet setValue:@(row) forKey:@"animationRow"];[pet setValue:@0 forKey:@"frameIndex"];[pet showFrame];
            NSString *expected=[WPResourceBundle().resourcePath stringByAppendingPathComponent:[@"PetCorrections/yue2-" stringByAppendingString:name]];
            rows&=[[pet valueForKey:@"atlasCorrections"][name] isEqual:expected] && [[pet valueForKey:@"loadedAtlasRow"] integerValue]==row &&
                CGImageGetWidth(((UIImage *)[pet valueForKey:@"atlas"]).CGImage)==3840 && CGImageGetHeight(((UIImage *)[pet valueForKey:@"atlas"]).CGImage)==208;
            unchanged&=[original[name] isEqual:[NSData dataWithContentsOfURL:[v5 URLByAppendingPathComponent:name]]];
        }
        checks[@"zhouyouKnownImportedV5UsesFourCorrectedRowsAndRetainsSelection"]=@(selected && rows && [WPSelectedPetReference() isEqual:v5reference] && [WPSelectedPetDirectory() isEqual:v5.path]);
        checks[@"zhouyouKnownImportedV5OriginalFilesAreNeverRewritten"]=@(unchanged && [original[@"pet.json"] isEqual:[NSData dataWithContentsOfURL:[v5 URLByAppendingPathComponent:@"pet.json"]]]);
        changed=[original[@"row-20.png"] mutableCopy];[changed appendBytes:&marker length:1];[changed writeToURL:[v5 URLByAppendingPathComponent:@"row-20.png"] atomically:YES];
        NSDictionary *remaining=WPKnownAtlasCorrections(v5.path,v5meta);[pet reloadPet];
        checks[@"zhouyouModifiedV5RowRetainsItsOwnArtwork"]=@(remaining.count==3 && remaining[@"row-20.png"]==nil && [pet valueForKey:@"atlasCorrections"][@"row-20.png"]==nil && [WPSelectedPetReference() isEqual:v5reference]);
        custom=[v5meta mutableCopy];custom[@"id"]=@"user-custom-model";customSafe=WPKnownAtlasCorrections(v5.path,custom).count==0;
        custom=[v5meta mutableCopy];custom[@"assetRevision"]=@"custom";
        checks[@"zhouyouDifferentImportedV5IdOrRevisionIsNeverOverridden"]=@(customSafe && WPKnownAtlasCorrections(v5.path,custom).count==0);
    } @catch(__unused NSException *exception){checks[@"zhouyouKnownAssetCorrectionHasNoExceptions"]=@NO;}
    @finally {
        [pet setAnimationActive:NO];
        if(previousDirectory.length)WPSelectPetDirectory([NSURL fileURLWithPath:previousDirectory isDirectory:YES]);else WPResetSelectedPet();
        [NSFileManager.defaultManager removeItemAtURL:fixture error:nil];
        [NSFileManager.defaultManager removeItemAtURL:v4 error:nil];
        [NSFileManager.defaultManager removeItemAtURL:v5 error:nil];
    }
    checks[@"zhouyouAssetCorrectionChecksRestoreOriginalSelectedReference"]=@(previousReference.length?[WPSelectedPetReference() isEqual:previousReference]:WPSelectedPetReference()==nil);
    return checks;
}

NSDictionary<NSString *,id> *WPStabilityPreviewChecks(WPPetRenderer *renderer, WPQuickChatBar *quickChat) {
    NSMutableDictionary *checks=[NSMutableDictionary new],*memory=[NSMutableDictionary new];
    @autoreleasepool {
        UIImage *atlas=[renderer valueForKey:@"atlas"];
        size_t width=CGImageGetWidth(atlas.CGImage),height=CGImageGetHeight(atlas.CGImage),count=width*height;
        NSInteger columns=[[renderer valueForKey:@"columns"] integerValue];
        NSInteger logicalRow=[[renderer valueForKey:@"animationRow"] integerValue];
        NSInteger physicalRow=[[renderer valueForKey:@"rowAtlasPaths"] count]?0:logicalRow;
        NSInteger frame=[[renderer valueForKey:@"displayedAtlasFrame"] integerValue];
        size_t cellWidth=[[renderer valueForKey:@"atlasWidth"] unsignedLongLongValue];
        size_t cellHeight=[[renderer valueForKey:@"atlasHeight"] unsignedLongLongValue];
        [renderer pointInside:CGPointMake(CGRectGetMidX(renderer.bounds),CGRectGetMidY(renderer.bounds)) withEvent:nil];
        NSData *mask=[renderer valueForKey:@"alphaMask"];
        size_t cellPixels=cellWidth*cellHeight;
        checks[@"ariaCurrentFrameMaskIsBounded"]=@(cellPixels==192*208 && mask.length==(cellPixels+7)/8);
        checks[@"ariaPackedMaskUsesOneEighthMemory"]=@(cellPixels>0 && mask.length==(cellPixels+7)/8);
        memory[@"legacyAlphaBytes"]=@(count);memory[@"packedAlphaBytes"]=@(mask.length);
        memory[@"alphaBytesSaved"]=@(count-mask.length);
        memory[@"atlasDecodedPixelBytes"]=@(CGImageGetBytesPerRow(atlas.CGImage)*height);
        CGImageRef cell=CGImageCreateWithImageInRect(atlas.CGImage,CGRectMake(frame*cellWidth,physicalRow*cellHeight,cellWidth,cellHeight));
        unsigned char *alpha=calloc(cellPixels,1);
        CGContextRef context=alpha?CGBitmapContextCreate(alpha,cellWidth,cellHeight,8,cellWidth,NULL,(CGBitmapInfo)kCGImageAlphaOnly):NULL;
        BOOL equal=context!=NULL && mask.length==(cellPixels+7)/8;
        if(context){
            CGContextDrawImage(context,CGRectMake(0,0,cellWidth,cellHeight),cell);
            const unsigned char *bits=mask.bytes;
            for(size_t index=0;equal && index<cellPixels;index++)equal=((bits[index>>3]>>(index&7))&1)==(alpha[index]>12);
            CGContextRelease(context);
        }
        if(cell)CGImageRelease(cell);
        free(alpha);checks[@"ariaPackedMaskPreservesEveryPixelThreshold"]=@(equal);
        checks[@"zhouyouDefaultUsesOneCompactStripWithOriginalLogicalColumns"]=@(columns==10 && width<=1920 && width%192==0 && height==208 && [[renderer valueForKey:@"rowAtlasPaths"] count]==29);
    }
    // Isolate animation regressions from the primary overlay's current state.
    @autoreleasepool {
        WPPetRenderer *pet=nil;
        @autoreleasepool {pet=[[WPPetRenderer alloc] initWithFrame:CGRectMake(0,0,192,208)];[pet setAnimationActive:YES];}
        checks[@"zhouyouDefaultHitMaskIsLazyBeforeTouch"]=@([pet valueForKey:@"alphaMask"]==nil);
        BOOL rows=YES,counts=YES,hits=YES,released=YES;NSUInteger total=0;
        for(NSInteger row=0;row<29;row++){
            __weak UIImage *oldImage;
            @autoreleasepool {
                NSInteger prior=[[pet valueForKey:@"loadedAtlasRow"] integerValue];oldImage=[pet valueForKey:@"atlas"];
                NSInteger count=[pet countForRow:row];total+=count;counts&=count==((row==9 || row==10)?8:10);
                [pet setValue:@(row) forKey:@"animationRow"];[pet setValue:@(count-1) forKey:@"frameIndex"];[pet showFrame];
                UIImage *atlas=[pet valueForKey:@"atlas"];CALayer *layer=[pet valueForKey:@"spriteLayer"];
                rows&=CGImageGetWidth(atlas.CGImage)==[[pet valueForKey:@"rowColumnCounts"][row] unsignedIntegerValue]*192 && CGImageGetHeight(atlas.CGImage)==208 && [[pet valueForKey:@"loadedAtlasRow"] integerValue]==row && layer.contents!=nil;
                if(prior==row)oldImage=nil;
                CGImageRef cell=CGImageCreateWithImageInRect(atlas.CGImage,CGRectMake([[pet valueForKey:@"displayedAtlasFrame"] integerValue]*192,0,192,208));
                unsigned char *alpha=calloc(192*208,1);
                CGContextRef ctx=alpha?CGBitmapContextCreate(alpha,192,208,8,192,NULL,(CGBitmapInfo)kCGImageAlphaOnly):NULL;
                if(ctx){
                    CGContextDrawImage(ctx,CGRectMake(0,0,192,208),cell);
                    for(NSUInteger y=0;y<208;y++)for(NSUInteger x=0;x<192;x++)
                        hits&=[pet pointInside:CGPointMake(x+.5,y+.5) withEvent:nil]==(alpha[y*192+x]>12);
                    CGContextRelease(ctx);
                }else hits=NO;
                free(alpha);if(cell)CGImageRelease(cell);
            }
            [CATransaction flush];released&=oldImage==nil;
        }
        checks[@"zhouyouAll29RowsAnd286FramesRemainAvailable"]=@(rows && counts && total==286);
        checks[@"zhouyouAll29VisibleCellHitMasksMatchRaster"]=@(hits);
        checks[@"zhouyouPriorRowImagesAreReleased"]=@(released);
        [pet holdPeekOnLeft:YES];[pet playSemanticAction:@"reveal"];
        CALayer *layer=[pet valueForKey:@"spriteLayer"];UIImage *atlas=[pet valueForKey:@"atlas"];
        CGImageRef cell=CGImageCreateWithImageInRect(atlas.CGImage,CGRectMake(0,0,192,208));
        unsigned char *alpha=calloc(192*208,1);CGContextRef ctx=alpha?CGBitmapContextCreate(alpha,192,208,8,192,NULL,(CGBitmapInfo)kCGImageAlphaOnly):NULL;
        BOOL mirror=ctx && layer.transform.m11<0;
        if(ctx){CGContextDrawImage(ctx,CGRectMake(0,0,192,208),cell);
            for(NSUInteger y=0;y<208;y++)for(NSUInteger x=0;x<192;x++)mirror&=[pet pointInside:CGPointMake(x+.5,y+.5) withEvent:nil]==(alpha[y*192+191-x]>12);
            CGContextRelease(ctx);}
        free(alpha);if(cell)CGImageRelease(cell);
        checks[@"zhouyouMirroredEdgeHitMaskMatchesVisibleRaster"]=@(mirror);
        [pet endPeek];[pet beginDragAnimation];[pet endDragAnimation];
        BOOL shortActions=YES;
        for(NSString *action in @[@"tap",@"longPress",@"petting",@"land"]){
            [pet setValue:nil forKey:@"reactionKind"];[pet setValue:@0 forKey:@"greetingUntil"];
            [pet playSemanticAction:action];
            CFTimeInterval start=[[pet valueForKey:@"animationStartedAt"] doubleValue],until=[[pet valueForKey:@"greetingUntil"] doubleValue];
            NSInteger count=[[pet valueForKey:@"frameCount"] integerValue],rate=[[pet valueForKey:@"frameRate"] integerValue];
            shortActions&=fabs((until-start)-(double)count/rate)<.005;
            WPStabilityTestClock *clock=[WPStabilityTestClock new];clock.timestamp=until+.01;[pet tick:clock];
            shortActions&=[pet valueForKey:@"reactionKind"]==nil && [[pet valueForKey:@"animationRow"] integerValue]==0;
        }
        checks[@"zhouyouShortFeedbackCompletesOneCycleThenReturnsIdle"]=@(shortActions);
        [pet setAnimationActive:NO];
    }
    @autoreleasepool {
        NSData *data=[NSData dataWithContentsOfFile:[WPDefaultPetDirectory() stringByAppendingPathComponent:@"spritesheet.png"] options:NSDataReadingMappedIfSafe error:nil];
        UIImage *thumbnail=WPCatalogPreviewThumbnailForData(data);
        CGImageRef cg=thumbnail.CGImage;
        CFDataRef pixels=cg?CGDataProviderCopyData(CGImageGetDataProvider(cg)):NULL;
        size_t bytes=pixels?(size_t)CFDataGetLength(pixels):0;
        checks[@"ariaV4ThumbnailOwnsOnlySmallPixelBuffer"]=@(cg && CGImageGetWidth(cg)==192 && CGImageGetHeight(cg)==208 && bytes>=192*208*4 && bytes<=256*208*4);
        memory[@"thumbnailPixelBytes"]=@(bytes);if(pixels)CFRelease(pixels);
    }
    if(quickChat){
    NSCache *avatars=[quickChat valueForKey:@"avatars"];
    UIImage *avatar=[avatars objectForKey:@"wxid_aria_friend"];
    checks[@"ariaAvatarCacheHasByteAndCountLimits"]=@(avatars.totalCostLimit==2*1024*1024 && avatars.countLimit==24);
    checks[@"ariaAvatarDecodeIsAtMost160Pixels"]=@(avatar.CGImage && MAX(CGImageGetWidth(avatar.CGImage),CGImageGetHeight(avatar.CGImage))<=160);
    quickChat.hidden=YES;
    checks[@"ariaHiddenChatCancelsDownloadsAndTimer"]=@([[quickChat valueForKey:@"avatarDownloads"] count]==0 && [quickChat valueForKey:@"avatarRefreshTimer"]==nil);
    // A visible table may retain a few displayed images; its recoverable cache
    // must be cleared when the application receives memory pressure.
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    checks[@"ariaAvatarMemoryWarningPurgesRecoverableCache"]=@([avatars objectForKey:@"wxid_aria_friend"]==nil);
    }

    @autoreleasepool {
        WPCoupleClient *client=[WPCoupleClient new];BOOL safe=YES;
        @try {
            for(id protocol in @[NSNull.null,@"3",@[],@{},@(-1),@(3.5)])[client handle:@{@"type":@"ready",@"protocol":protocol} generation:0];
            [client handle:@{@"type":@"ready",@"protocol":@3,@"hidden_applied":NSNull.null} generation:0];
        } @catch(__unused NSException *exception){safe=NO;}
        checks[@"ariaMalformedReadyCannotCrashOrConnect"]=@(safe && !client.connected);
        [client handle:@{@"type":@"ready",@"protocol":@3} generation:1];
        checks[@"ariaStaleReadyCannotConnect"]=@(!client.connected);
        __block NSUInteger statuses=0;client.onStatusChange=^(__unused NSString *status){statuses++;};
        [client handle:@{@"type":@"ready",@"protocol":@3} generation:0];
        [client handle:@{@"type":@"ready",@"protocol":@3} generation:0];
        checks[@"ariaRepeatedReadyStartsOnlyOneConnection"]=@(client.connected && statuses==1);
        [client disconnect];
    }
    memory[@"footprintBeforeInactiveRelease"]=@(WPFootprint());
    [renderer setAnimationActive:NO];[CATransaction flush];
    checks[@"ariaInactiveRendererReleasesAtlasMaskAndLayer"]=@([renderer valueForKey:@"atlas"]==nil && [renderer valueForKey:@"alphaMask"]==nil && ((CALayer *)[renderer valueForKey:@"spriteLayer"]).contents==nil && [renderer valueForKey:@"displayLink"]==nil);
    memory[@"footprintAfterInactiveRelease"]=@(WPFootprint());
    [renderer setAnimationActive:YES];
    checks[@"ariaRendererResumesWithRestoredAtlas"]=@([renderer valueForKey:@"atlas"]!=nil && [renderer valueForKey:@"alphaMask"]==nil && [renderer valueForKey:@"displayLink"]!=nil);
    BOOL restored=YES;
    for(NSUInteger index=0;index<4;index++){@autoreleasepool{[renderer setAnimationActive:NO];[renderer setAnimationActive:YES];restored&=[renderer valueForKey:@"atlas"]!=nil;}}
    checks[@"ariaRepeatedPauseResumeKeepsWorking"]=@(restored);
    __weak WPPetRenderer *weakRenderer;
    @autoreleasepool {
        WPPetRenderer *temporary=[[WPPetRenderer alloc] initWithFrame:CGRectMake(0,0,88,96)];
        [temporary setAnimationActive:YES];weakRenderer=temporary;
    }
    checks[@"ariaDisplayLinkDoesNotRetainDiscardedRenderer"]=@(weakRenderer==nil);

    // Malformed local metadata is a real disk-boundary case. Use a temporary
    // imported selection and restore the previous selection in all paths.
    NSString *previous=WPSelectedPetDirectory();
    NSURL *fixture=[NSURL fileURLWithPath:[[WPDataDirectory() stringByAppendingPathComponent:@"ImportedPets"] stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
    BOOL metadataSafe=YES,customSelectionSafe=YES;
    @try {
        [NSFileManager.defaultManager createDirectoryAtURL:fixture withIntermediateDirectories:YES attributes:nil error:nil];
        UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat defaultFormat];format.scale=1;
        UIImage *image=[[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(32,32) format:format] imageWithActions:^(__unused UIGraphicsImageRendererContext *context){[UIColor.redColor setFill];UIRectFill(CGRectMake(0,0,16,16));}];
        [UIImagePNGRepresentation(image) writeToURL:[fixture URLByAppendingPathComponent:@"spritesheet.png"] atomically:YES];
        // A user-edited v4 pet can retain the default ID and private paging
        // key. Only the actual bundle path may use the bundled strip layout.
        NSDictionary *custom=@{@"id":@"yue-zhour-20261021",@"displayName":@"用户自定义角色",@"spriteVersionNumber":@4,
            @"columns":@1,@"rows":@1,@"frameWidth":@32,@"frameHeight":@32,@"frameRate":@15,
            @"wpBundledRowAtlasPaths":@[@"missing-private-row.png"]};
        [[NSJSONSerialization dataWithJSONObject:custom options:0 error:nil] writeToURL:[fixture URLByAppendingPathComponent:@"pet.json"] atomically:YES];
        customSelectionSafe=WPSelectPetDirectory(fixture);[renderer reloadPet];
        UIImage *customAtlas=[renderer valueForKey:@"atlas"];
        customSelectionSafe&=[renderer.petName isEqual:@"用户自定义角色"] && [renderer valueForKey:@"rowAtlasPaths"]==nil &&
            CGImageGetWidth(customAtlas.CGImage)==32 && CGImageGetHeight(customAtlas.CGImage)==32 &&
            [WPSelectedPetDirectory() isEqual:fixture.path];
        NSDictionary *bad=@{@"columns":NSNull.null,@"rows":@1,@"frameWidth":@32,@"frameHeight":@32,@"frameRate":@[]};
        [[NSJSONSerialization dataWithJSONObject:bad options:0 error:nil] writeToURL:[fixture URLByAppendingPathComponent:@"pet.json"] atomically:YES];
        metadataSafe=WPSelectPetDirectory(fixture);[renderer reloadPet];
        metadataSafe&=[[[WPPreferences() dictionaryForKey:@"selectedPetLastLoad"] objectForKey:@"loadedDirectoryName"] isEqual:@"DefaultPet"];
    } @catch(__unused NSException *exception){metadataSafe=NO;customSelectionSafe=NO;}
    @finally {
        if(previous.length)WPSelectPetDirectory([NSURL fileURLWithPath:previous isDirectory:YES]);else WPResetSelectedPet();
        [NSFileManager.defaultManager removeItemAtURL:fixture error:nil];[renderer reloadPet];
    }
    checks[@"ariaMalformedLocalMetadataFallsBackSafely"]=@(metadataSafe);
    checks[@"zhouyouUserEditedV4SelectionIsPreserved"]=@(customSelectionSafe);
    [checks addEntriesFromDictionary:WPAtlasCorrectionPreviewChecks()];[renderer reloadPet];
    memory[@"footprintAfterResumeStress"]=@(WPFootprint());
    [[NSJSONSerialization dataWithJSONObject:memory options:NSJSONWritingPrettyPrinted error:nil] writeToFile:[WPDataDirectory() stringByAppendingPathComponent:@"memory-report.json"] atomically:YES];
    return checks;
}
