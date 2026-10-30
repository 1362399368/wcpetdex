#import "WPAria520AssetChecks.h"
#import "WPCommon.h"
#import "WPPetRenderer.h"
#import <QuartzCore/QuartzCore.h>

@interface WPPetRenderer (WPAria520Testing)
- (void)showFrame;
@end
static NSData *WPAria520Pixels(CGImageRef image,CGRect crop){
    if(!image)return nil;CGImageRef frame=CGImageCreateWithImageInRect(image,crop);
    CGColorSpaceRef color=CGColorSpaceCreateDeviceRGB();
    CGContextRef context=frame?CGBitmapContextCreate(NULL,192,208,8,192*4,color,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big):NULL;
    CGColorSpaceRelease(color);NSData *data=nil;
    if(context){CGContextDrawImage(context,CGRectMake(0,0,192,208),frame);data=[NSData dataWithBytes:CGBitmapContextGetData(context) length:192*208*4];CGContextRelease(context);}
    if(frame)CGImageRelease(frame);return data;
}
NSDictionary<NSString *,NSNumber *> *WPAria520AssetPreviewChecks(void){
    NSMutableDictionary *checks=[NSMutableDictionary new];NSString *previous=WPSelectedPetDirectory();
    WPPetRenderer *pet=nil;NSString *fixture=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"Aria520-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    @try {
        WPResetSelectedPet();NSString *root=[WPResourceBundle().resourcePath stringByAppendingPathComponent:@"AriaPet"];
        NSDictionary *metadata=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:@"pet.json"]] options:0 error:nil];
        pet=[[WPPetRenderer alloc]initWithFrame:CGRectMake(0,0,192,208)];[pet setValue:root forKey:@"previewBundledDirectory"];[pet reloadPet];[pet setAnimationActive:YES];
        checks[@"aria520AssetLoadsExclusiveCharacterFromBoundedRows"]=@([[pet valueForKey:@"bundledAria"] boolValue] && [[pet valueForKey:@"rows"] integerValue]==29 && [[pet valueForKey:@"frameRate"] integerValue]==15 && [pet.petName isEqual:@"Aria专属桌宠"]);
        BOOL exact=YES,bounded=YES;NSUInteger count=0;
        for(NSUInteger row=0;row<29;row++){
            NSString *name=metadata[@"wpBundledCompactRowAtlasPaths"][row];UIImage *reference=[UIImage imageWithContentsOfFile:[root stringByAppendingPathComponent:name]];NSArray *map=metadata[@"wpBundledCompactFrameMaps"][row];
            for(NSUInteger frame=0;frame<[metadata[@"frameCounts"][row] unsignedIntegerValue];frame++)@autoreleasepool{
                [pet setValue:@(row) forKey:@"animationRow"];[pet setValue:@(frame) forKey:@"frameIndex"];[pet showFrame];
                UIImage *loaded=[pet valueForKey:@"atlas"];CALayer *sprite=[pet valueForKey:@"spriteLayer"];CGRect rect=sprite.contentsRect;
                NSData *actual=WPAria520Pixels(loaded.CGImage,CGRectMake(lround(rect.origin.x*CGImageGetWidth(loaded.CGImage)),lround(rect.origin.y*CGImageGetHeight(loaded.CGImage)),192,208));
                NSData *expected=WPAria520Pixels(reference.CGImage,CGRectMake([map[frame] integerValue]*192,0,192,208));
                exact&=actual && [actual isEqual:expected];bounded&=loaded.CGImage && CGImageGetHeight(loaded.CGImage)==208 && CGImageGetBytesPerRow(loaded.CGImage)*CGImageGetHeight(loaded.CGImage)<=1920*208*4;count++;
            }
        }
        checks[@"aria520AssetAll286RuntimeFramesFollowExactPackedMaps"]=@(exact && count==286);
        checks[@"aria520AssetEveryActionKeepsOneBoundedDecodedStrip"]=@(bounded);
        [pet setValue:nil forKey:@"reactionKind"];[pet setValue:@0 forKey:@"greetingUntil"];
        CFTimeInterval before=CACurrentMediaTime();[pet playSemanticAction:@"receiveMiss"];
        CFTimeInterval duration=[[pet valueForKey:@"greetingUntil"] doubleValue]-before;
        checks[@"aria520AssetReceivedReactionRunsOneOriginalCycle"]=@([[pet valueForKey:@"animationRow"] integerValue]==17 && duration>=.65 && duration<.75);
        [pet beginDragAnimation];[pet updateDragDirectionLeft:YES];CALayer *sprite=[pet valueForKey:@"spriteLayer"];
        checks[@"aria520AssetDragRetainsDedicatedRowAndMirrorsFacing"]=@([[pet valueForKey:@"animationRow"] integerValue]==22 && sprite.transform.m11<0);
        [pet endDragAnimation];[pet holdPeekOnLeft:YES];
        checks[@"aria520AssetLeftPeekRetainsDedicatedPose"]=@([[pet valueForKey:@"animationRow"] integerValue]==25);
        [pet endPeek];[pet playSemanticAction:@"reveal"];
        checks[@"aria520AssetRevealUsesOriginalRowAndMirrorsLeft"]=@([[pet valueForKey:@"animationRow"] integerValue]==27 && sprite.transform.m11<0);
        [NSFileManager.defaultManager createDirectoryAtPath:fixture withIntermediateDirectories:YES attributes:nil error:nil];
        for(NSString *name in @[@"pet.json",@"pet.png"])[NSFileManager.defaultManager copyItemAtPath:[root stringByAppendingPathComponent:name] toPath:[fixture stringByAppendingPathComponent:name] error:nil];
        [pet setValue:fixture forKey:@"previewBundledDirectory"];[pet reloadPet];UIImage *fallback=[pet valueForKey:@"atlas"],*original=[UIImage imageWithContentsOfFile:[root stringByAppendingPathComponent:@"pet.png"]];
        checks[@"aria520AssetDamagedIdleKeepsOriginalAriaStaticFallback"]=@(CGImageGetWidth(fallback.CGImage)==192 && CGImageGetHeight(fallback.CGImage)==208 && [WPAria520Pixels(fallback.CGImage,CGRectMake(0,0,192,208)) isEqual:WPAria520Pixels(original.CGImage,CGRectMake(0,0,192,208))]);
    }@catch(__unused NSException *error){checks[@"aria520AssetNoUnexpectedException"]=@NO;}
    @finally {[pet setAnimationActive:NO];[NSFileManager.defaultManager removeItemAtPath:fixture error:nil];if(previous.length)WPSelectPetDirectory([NSURL fileURLWithPath:previous isDirectory:YES]);else WPResetSelectedPet();}
    return checks;
}
