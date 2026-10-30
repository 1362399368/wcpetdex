#import "WPCompact111Checks.h"
#import "WPPetRenderer.h"
#import "WPCommon.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <ImageIO/ImageIO.h>

@interface WPPetRenderer (WPCompact111Testing)
- (void)showFrame;
@end
static NSData *WPCompact111Pixels(CGImageRef image,CGRect crop) {
    CGImageRef frame=image?CGImageCreateWithImageInRect(image,crop):NULL;
    CGColorSpaceRef color=CGColorSpaceCreateDeviceRGB();
    CGContextRef context=frame?CGBitmapContextCreate(NULL,192,208,8,192*4,color,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big):NULL;
    CGColorSpaceRelease(color);
    NSData *bytes=nil;
    if(context){CGContextDrawImage(context,CGRectMake(0,0,192,208),frame);bytes=[NSData dataWithBytes:CGBitmapContextGetData(context) length:192*208*4];CGContextRelease(context);}
    if(frame)CGImageRelease(frame);return bytes;
}
NSDictionary<NSString *,NSNumber *> *WPCompact111PreviewChecks(void) {
    NSMutableDictionary *checks=[NSMutableDictionary new],*memory=[NSMutableDictionary new];
    NSString *previous=WPSelectedPetDirectory();WPResetSelectedPet();
    WPPetRenderer *pet=nil;NSURL *fixture=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[@"WPCompact111-" stringByAppendingString:NSUUID.UUID.UUIDString]] isDirectory:YES];
    NSFileManager *manager=NSFileManager.defaultManager;
    @try {
        NSString *root=WPDefaultPetDirectory();NSDictionary *metadata=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:@"pet.json"]] options:0 error:nil];
        UIImage *reference=[UIImage imageWithContentsOfFile:[root stringByAppendingPathComponent:@"spritesheet.png"]];
        pet=[[WPPetRenderer alloc] initWithFrame:CGRectMake(0,0,192,208)];[pet setAnimationActive:YES];
        BOOL exact=reference.CGImage!=NULL;NSUInteger total=0;
        for(NSInteger row=0;row<29;row++){
            for(NSInteger frame=0;frame<[metadata[@"frameCounts"][row] integerValue];frame++)@autoreleasepool {
                [pet setValue:@(row) forKey:@"animationRow"];[pet setValue:@(frame) forKey:@"frameIndex"];[pet showFrame];
                UIImage *atlas=[pet valueForKey:@"atlas"];CALayer *sprite=[pet valueForKey:@"spriteLayer"];
                CGRect rect=sprite.contentsRect;CGRect crop=CGRectMake(lround(rect.origin.x*CGImageGetWidth(atlas.CGImage)),lround(rect.origin.y*CGImageGetHeight(atlas.CGImage)),192,208);
                NSData *actual=WPCompact111Pixels(atlas.CGImage,crop),*expected=WPCompact111Pixels(reference.CGImage,CGRectMake(frame*192,row*208,192,208));
                exact&=actual!=nil&&[actual isEqual:expected];total++;
                if(frame==0 && (row==0||row==8||row==20))memory[[@{@0:@"idleDecodedPixelBytes",@8:@"onlineDecodedPixelBytes",@20:@"angerDecodedPixelBytes"} objectForKey:@(row)]]=@(CGImageGetBytesPerRow(atlas.CGImage)*CGImageGetHeight(atlas.CGImage));
            }
        }
        checks[@"compact111All286RenderedFramesMatchOriginalRGBA"]=@(exact&&total==286);
        checks[@"compact111IdleUsesSixDistinctFrames"]=@([memory[@"idleDecodedPixelBytes"] unsignedLongLongValue]==958464);
        checks[@"compact111OnlineUsesTwoDistinctFrames"]=@([memory[@"onlineDecodedPixelBytes"] unsignedLongLongValue]==319488);
        checks[@"compact111AngerUsesThreeDistinctFrames"]=@([memory[@"angerDecodedPixelBytes"] unsignedLongLongValue]==479232);
        [manager createDirectoryAtURL:fixture withIntermediateDirectories:YES attributes:nil error:nil];
        NSMutableArray *files=[metadata[@"wpBundledCompactRowAtlasPaths"] mutableCopy];[files addObjectsFromArray:@[@"pet.json",@"spritesheet.png"]];
        BOOL copied=YES;for(NSString *name in [NSOrderedSet orderedSetWithArray:files])copied&=[manager copyItemAtPath:[root stringByAppendingPathComponent:name] toPath:[fixture.path stringByAppendingPathComponent:name] error:nil];
        [pet setValue:fixture.path forKey:@"previewBundledDirectory"];[pet reloadPet];
        [manager removeItemAtPath:[fixture.path stringByAppendingPathComponent:@"compact-row-17.png"] error:nil];
        [pet playSemanticAction:@"receiveMiss"];
        checks[@"compact111MissingActionUsesHealthyIdleAndRemembersFailure"]=@(copied&&[[pet valueForKey:@"loadedAtlasRow"] integerValue]==0&&[[pet valueForKey:@"failedAtlasRows"] containsIndex:17]&&((CALayer *)[pet valueForKey:@"spriteLayer"]).contents!=nil);
        for(NSString *name in metadata[@"wpBundledCompactRowAtlasPaths"])[manager removeItemAtPath:[fixture.path stringByAppendingPathComponent:name] error:nil];
        [pet reloadPet];UIImage *fallback=[pet valueForKey:@"atlas"];
        checks[@"compact111AllMissingPagesNeverDecodeFullAtlas"]=@(CGImageGetWidth(fallback.CGImage)==192&&CGImageGetHeight(fallback.CGImage)==208&&CGImageGetBytesPerRow(fallback.CGImage)*CGImageGetHeight(fallback.CGImage)<=192*208*4&&[[pet valueForKey:@"rowAtlasPaths"] count]==0);
        memory[@"legacyDecodedRowPixelBytes"]=@1597440;memory[@"logicalFramesPreserved"]=@(total);
        [[NSJSONSerialization dataWithJSONObject:memory options:NSJSONWritingPrettyPrinted error:nil] writeToFile:[WPDataDirectory() stringByAppendingPathComponent:@"compact-memory-report.json"] atomically:YES];
    } @catch(NSException *exception){checks[@"compact111NoUnexpectedException"]=@NO;NSLog(@"Compact111: %@",exception.name);}
    @finally {
        [pet setAnimationActive:NO];[manager removeItemAtURL:fixture error:nil];
        if(previous.length)WPSelectPetDirectory([NSURL fileURLWithPath:previous isDirectory:YES]);else WPResetSelectedPet();
    }
    return checks;
}
