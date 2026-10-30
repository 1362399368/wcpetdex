#import "WPPagedPet.h"
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CommonCrypto/CommonDigest.h>
#import <math.h>

dispatch_queue_t WPPetAssetWorkQueue(void) {
    static dispatch_queue_t queue; static dispatch_once_t once;
    dispatch_once(&once, ^{queue=dispatch_queue_create("dev.zhour.wechatpet.assets",dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,QOS_CLASS_UTILITY,0));});
    return queue;
}
static BOOL WPPageInteger(id n, NSInteger a, NSInteger b) {
    if(![n isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)n)==CFBooleanGetTypeID())return NO;
    double v=[n doubleValue];return isfinite(v)&&floor(v)==v&&v>=a&&v<=b;
}
BOOL WPIsLocalPagedMetadata(NSDictionary *m) {
    if(![m[@"spriteVersionNumber"] isEqual:@5] || ![m[@"wpLocalPagedVersion"] isEqual:@1] ||
       !WPPageInteger(m[@"wpLegacySpriteVersion"],1,4))return NO;
    NSInteger v=[m[@"wpLegacySpriteVersion"] integerValue],rows=v==1?9:(v==2?11:29),columns=v==4?10:8;
    NSArray *p=[m[@"rowAtlasPaths"] isKindOfClass:NSArray.class]?m[@"rowAtlasPaths"]:nil;
    return WPPageInteger(m[@"columns"],columns,columns)&&WPPageInteger(m[@"rows"],rows,rows)&&p.count==(NSUInteger)rows;
}
static NSError *WPPageError(NSString *text){return [NSError errorWithDomain:@"WeChatPet.Paging" code:1 userInfo:@{NSLocalizedDescriptionKey:text}];}
static NSString *WPPageSignature(NSDictionary *metadata,NSDictionary *attributes) {
    NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"metadata":metadata,@"size":attributes[NSFileSize]?:@0,
        @"modified":@([attributes[NSFileModificationDate] timeIntervalSince1970])} options:NSJSONWritingSortedKeys error:nil];
    if(!data)return nil;unsigned char digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,digest);
    NSMutableString *value=[NSMutableString new];for(NSUInteger i=0;i<sizeof(digest);i++)[value appendFormat:@"%02x",digest[i]];return value;
}
NSString *WPPagedLegacyDirectory(NSString *directory,NSDictionary *metadata,NSError **error) {
    NSInteger version=[metadata[@"spriteVersionNumber"] respondsToSelector:@selector(integerValue)]?[metadata[@"spriteVersionNumber"] integerValue]:0;
    if(version<1||version>4)return nil;
    NSInteger columns=version==4?10:8,rows=version==1?9:(version==2?11:29);
    NSString *name=[metadata[@"spritesheetPath"] isKindOfClass:NSString.class]?metadata[@"spritesheetPath"]:@"spritesheet.png";
    if(![name isEqual:name.lastPathComponent] || [name containsString:@"\\"] || ![@[@"png",@"webp"] containsObject:name.pathExtension.lowercaseString])return nil;
    NSString *sourcePath=[directory stringByAppendingPathComponent:name];NSFileManager *manager=NSFileManager.defaultManager;
    NSDictionary *attributes=[manager attributesOfItemAtPath:sourcePath error:error];
    if(![attributes[NSFileType] isEqual:NSFileTypeRegular] || [attributes[NSFileSize] unsignedLongLongValue]>32*1024*1024)return nil;
    NSString *signature=WPPageSignature(metadata,attributes);if(!signature)return nil;
    NSString *published=[directory stringByAppendingPathComponent:@".wp-paged-v121"];
    NSData *saved=[NSData dataWithContentsOfFile:[published stringByAppendingPathComponent:@"pet.json"]];
    NSDictionary *cached=saved?[NSJSONSerialization JSONObjectWithData:saved options:0 error:nil]:nil;
    if(WPIsLocalPagedMetadata(cached) && [cached[@"wpMigrationSignature"] isEqual:signature]) {
        BOOL exists=YES;for(NSString *file in cached[@"rowAtlasPaths"])exists&=[manager fileExistsAtPath:[published stringByAppendingPathComponent:file]];
        if(exists)return published;
    }
    NSDictionary *options=@{(__bridge id)kCGImageSourceShouldCache:@NO};
    CGImageSourceRef source=CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:sourcePath],(__bridge CFDictionaryRef)options);
    NSDictionary *properties=source?CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source,0,NULL)):nil;
    BOOL valid=[properties[(__bridge id)kCGImagePropertyPixelWidth] integerValue]==columns*192 && [properties[(__bridge id)kCGImagePropertyPixelHeight] integerValue]==rows*208 && [properties[(__bridge id)kCGImagePropertyHasAlpha] boolValue];
    CGImageRef image=valid?CGImageSourceCreateImageAtIndex(source,0,(__bridge CFDictionaryRef)options):NULL;if(source)CFRelease(source);
    if(!image){if(error)*error=WPPageError(@"旧动画图集无法分页。");return nil;}
    // Recover only our own abandoned hidden generations; published pages and
    // fresh concurrent work are never removed by cleanup.
    for(NSString *child in [manager contentsOfDirectoryAtPath:directory error:nil]){
        if(![child hasPrefix:@".wp-pages-"])continue;
        NSString *path=[directory stringByAppendingPathComponent:child];NSDictionary *old=[manager attributesOfItemAtPath:path error:nil];
        if([old[NSFileType] isEqual:NSFileTypeDirectory] && [old[NSFileModificationDate] timeIntervalSinceNow]<-86400)[manager removeItemAtPath:path error:nil];
    }
    NSString *staging=[directory stringByAppendingPathComponent:[@".wp-pages-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    NSError *local=nil;[manager createDirectoryAtPath:staging withIntermediateDirectories:NO attributes:nil error:&local];
    NSMutableArray *paths=[NSMutableArray new],*counts=[NSMutableArray new];
    NSArray *provided=[metadata[@"frameCounts"] isKindOfClass:NSArray.class]?metadata[@"frameCounts"]:nil;
    for(NSInteger row=0;row<rows&&!local;row++)@autoreleasepool {
        NSString *file=[NSString stringWithFormat:@"paged-row-%02ld.png",(long)row];
        CGImageRef page=CGImageCreateWithImageInRect(image,CGRectMake(0,row*208,columns*192,208));
        // Serialize the original crop directly, preserving its color space and
        // pixel precision. The full backing image lives only for this one-time
        // worker conversion; subsequently loaded page PNGs are independent.
        NSInteger count=provided.count==(NSUInteger)rows && WPPageInteger(provided[row],1,columns)?[provided[row] integerValue]:1;
        if(page && provided.count!=(NSUInteger)rows){
            CGContextRef alpha=CGBitmapContextCreate(NULL,columns*192,208,8,columns*192,NULL,(CGBitmapInfo)kCGImageAlphaOnly);
            if(alpha){CGContextDrawImage(alpha,CGRectMake(0,0,columns*192,208),page);unsigned char *pixels=CGBitmapContextGetData(alpha);
                for(NSInteger y=0;y<208;y++)for(NSInteger x=0;x<columns*192;x++)if(pixels[y*columns*192+x]>12)count=MAX(count,x/192+1);
                CGContextRelease(alpha);}
        }
        NSURL *url=[NSURL fileURLWithPath:[staging stringByAppendingPathComponent:file]];
        CGImageDestinationRef destination=page?CGImageDestinationCreateWithURL((__bridge CFURLRef)url,CFSTR("public.png"),1,NULL):NULL;
        if(destination)CGImageDestinationAddImage(destination,page,NULL);
        BOOL written=destination&&CGImageDestinationFinalize(destination);if(destination)CFRelease(destination);if(page)CGImageRelease(page);
        if(!written)local=WPPageError(@"动作条写入失败。");else{[paths addObject:file];[counts addObject:@(count)];}
    }
    CGImageRelease(image);
    if(!local){NSMutableDictionary *paged=[metadata mutableCopy];paged[@"spriteVersionNumber"]=@5;paged[@"wpLocalPagedVersion"]=@1;paged[@"wpLegacySpriteVersion"]=@(version);paged[@"wpMigrationSignature"]=signature;
        paged[@"wpLegacySpritePath"]=name;NSInteger rate=[metadata[@"frameRate"] respondsToSelector:@selector(integerValue)]?[metadata[@"frameRate"] integerValue]:12;paged[@"frameRate"]=@(rate>=6&&rate<=30?rate:12);paged[@"rowAtlasPaths"]=paths;paged[@"spritesheetPath"]=paths.firstObject;paged[@"columns"]=@(columns);paged[@"rows"]=@(rows);paged[@"frameWidth"]=@192;paged[@"frameHeight"]=@208;paged[@"frameCounts"]=counts;
        NSData *json=[NSJSONSerialization dataWithJSONObject:paged options:NSJSONWritingPrettyPrinted error:&local];if(json)[json writeToFile:[staging stringByAppendingPathComponent:@"pet.json"] options:NSDataWritingAtomic error:&local];}
    if(!local){
        // Rename publication never exposes partially written pages. Preserve a
        // prior valid generation until the new generation is fully present.
        if([manager fileExistsAtPath:published]){NSURL *result=nil;[manager replaceItemAtURL:[NSURL fileURLWithPath:published] withItemAtURL:[NSURL fileURLWithPath:staging] backupItemName:nil options:0 resultingItemURL:&result error:&local];}
        else[manager moveItemAtPath:staging toPath:published error:&local];
    }
    if(local){[manager removeItemAtPath:staging error:nil];if(error)*error=local;return nil;}
    return published;
}
