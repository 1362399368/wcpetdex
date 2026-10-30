#import "WPPetImporter.h"
#import "WPZipArchive.h"
#import "WPPagedPet.h"
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>
#import <math.h>

static NSError *WPImportError(NSString *text){return [NSError errorWithDomain:@"WeChatPet.Import" code:2 userInfo:@{NSLocalizedDescriptionKey:text}];}
static NSArray *WPImportedFrameCounts(CGImageRef image,size_t width,size_t height,size_t columns){
    // Scan one 208-pixel row at a time instead of retaining an extra alpha
    // bitmap for the complete (up to 29-row) legacy atlas.
    size_t rows=height/208;NSMutableArray *counts=[NSMutableArray arrayWithCapacity:rows];
    BOOL transparent=NO,painted=NO;
    for(size_t row=0;row<rows;row++){
        size_t count=width*208;unsigned char *alpha=calloc(count,1);
        CGContextRef context=alpha?CGBitmapContextCreate(alpha,width,208,8,width,NULL,(CGBitmapInfo)kCGImageAlphaOnly):NULL;
        CGImageRef strip=context?CGImageCreateWithImageInRect(image,CGRectMake(0,row*208,width,208)):NULL;
        if(!context || !strip){if(context)CGContextRelease(context);if(strip)CGImageRelease(strip);free(alpha);return nil;}
        CGContextDrawImage(context,CGRectMake(0,0,width,208),strip);CGImageRelease(strip);CGContextRelease(context);
        NSUInteger last=0;
        for(size_t index=0;index<count;index++){
            unsigned char value=alpha[index];if(value<250)transparent=YES;
            if(value>12){painted=YES;size_t column=(index%width)/192;if(column<columns)last=MAX(last,column+1);}
        }
        free(alpha);[counts addObject:@(MAX(1,last))];
    }
    return transparent && painted ? counts : nil;
}

static BOOL WPImportInteger(id value,NSInteger minimum,NSInteger maximum){
    if(![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value)==CFBooleanGetTypeID())return NO;
    double number=[value doubleValue];
    return isfinite(number) && floor(number)==number && number>=minimum && number<=maximum;
}
static BOOL WPImportRowName(id value){
    if(![value isKindOfClass:NSString.class])return NO;
    NSString *name=value;
    return name.length>4 && name.length<=120 && [name isEqualToString:name.lastPathComponent] &&
        ![name containsString:@"\\"] && ![name containsString:@":"] && ![name containsString:@"\0"] &&
        [name.pathExtension.lowercaseString isEqual:@"png"];
}
/// A v5 file is exactly one 20-cell row, never a second full decoded atlas.
static BOOL WPValidateImportRow(NSURL *file,NSUInteger expected){
    NSDictionary *options=@{(__bridge id)kCGImageSourceShouldCache:@NO};
    CGImageSourceRef source=file?CGImageSourceCreateWithURL((__bridge CFURLRef)file,(__bridge CFDictionaryRef)options):NULL;
    NSDictionary *props=source?CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source,0,NULL)):nil;
    BOOL valid=[props[(__bridge id)kCGImagePropertyPixelWidth] unsignedLongValue]==3840 &&
        [props[(__bridge id)kCGImagePropertyPixelHeight] unsignedLongValue]==208 &&
        [props[(__bridge id)kCGImagePropertyHasAlpha] boolValue];
    CGImageRef image=valid?CGImageSourceCreateImageAtIndex(source,0,(__bridge CFDictionaryRef)options):NULL;
    if(source)CFRelease(source);
    if(!image)return NO;
    size_t width=3840,height=208,count=width*height;
    unsigned char *alpha=calloc(count,1);
    CGContextRef context=alpha?CGBitmapContextCreate(alpha,width,height,8,width,NULL,(CGBitmapInfo)kCGImageAlphaOnly):NULL;
    if(context)CGContextDrawImage(context,CGRectMake(0,0,width,height),image);
    CGImageRelease(image);
    if(!context){free(alpha);return NO;}
    CGContextRelease(context);
    BOOL cells[20]={0},transparent=NO;
    for(size_t index=0;index<count;index++){
        unsigned char value=alpha[index];
        if(value<250)transparent=YES;
        if(value>12)cells[(index%width)/192]=YES;
    }
    free(alpha);
    valid=transparent;
    for(NSUInteger column=0;column<20;column++)valid&=(cells[column]==(column<expected));
    return valid;
}
static NSURL *WPImportRows(NSDictionary *files,NSDictionary *metadata,NSString *metaPath,NSData *metaData,NSURL *root,NSError **error){
    if(!WPImportInteger(metadata[@"spriteVersionNumber"],5,5) ||
       !WPImportInteger(metadata[@"columns"],20,20) || !WPImportInteger(metadata[@"rows"],29,29) ||
       !WPImportInteger(metadata[@"frameWidth"],192,192) || !WPImportInteger(metadata[@"frameHeight"],208,208) ||
       !WPImportInteger(metadata[@"frameRate"],6,30)){
        *error=WPImportError(@"v5 桌宠需为 29 个 20 列动作条，每格 192×208，帧率 6–30。");return nil;
    }
    NSArray *paths=[metadata[@"rowAtlasPaths"] isKindOfClass:NSArray.class]?metadata[@"rowAtlasPaths"]:nil;
    NSArray *counts=[metadata[@"frameCounts"] isKindOfClass:NSArray.class]?metadata[@"frameCounts"]:nil;
    if(paths.count!=29 || counts.count!=29 || ![metadata[@"spritesheetPath"] isKindOfClass:NSString.class] ||
       ![metadata[@"spritesheetPath"] isEqual:paths.firstObject]){
        *error=WPImportError(@"v5 需列出 29 个动作文件和帧数，预览图须为第一个动作条。");return nil;
    }
    NSMutableSet *seen=[NSMutableSet new];
    for(NSUInteger row=0;row<29;row++){
        if(!WPImportRowName(paths[row]) || [seen containsObject:paths[row]] || !WPImportInteger(counts[row],1,20)){
            *error=WPImportError(@"v5 动作文件名需为同目录、无重复的 PNG，帧数需为 1–20 的整数。");return nil;
        }
        [seen addObject:paths[row]];
    }
    NSDictionary *mapping=[metadata[@"semanticRows"] isKindOfClass:NSDictionary.class]?metadata[@"semanticRows"]:nil;
    NSSet *allowed=[NSSet setWithArray:@[@"idle",@"tap",@"longPress",@"petting",@"sendPet",@"receivePet",@"sendMiss",@"receiveMiss",@"sendAnger",@"receiveAnger",@"angerIdle",@"angerResolved",@"drag",@"land",@"shake",@"peekLeft",@"peekRight",@"reveal",@"retract"]];
    if(!mapping || ![[NSSet setWithArray:mapping.allKeys] isEqualToSet:allowed]){
        *error=WPImportError(@"v5 桌宠缺少完整的语义动作映射。");return nil;
    }
    for(id value in mapping.allValues)if(!WPImportInteger(value,0,28)){
        *error=WPImportError(@"v5 semanticRows 含有无效动作行号。");return nil;
    }
    if(metadata[@"onlinePhoneRow"] && !WPImportInteger(metadata[@"onlinePhoneRow"],0,28)){
        *error=WPImportError(@"v5 在线动作行号无效。");return nil;
    }
    NSString *prefix=metaPath.stringByDeletingLastPathComponent;
    for(NSUInteger row=0;row<29;row++){
        BOOL rowValid=NO;
        @autoreleasepool {
            NSString *path=prefix.length?[prefix stringByAppendingPathComponent:paths[row]]:paths[row];
            rowValid=WPValidateImportRow(files[path],[counts[row] unsignedIntegerValue]);
        }
        if(!rowValid){
            // Retain the failure outside the row's temporary autorelease pool.
            *error=WPImportError([NSString stringWithFormat:@"第 %lu 个动作条缺失、尺寸不符、没有透明角色，或画面数量与 frameCounts 不一致。",(unsigned long)row+1]);return nil;
        }
    }
    NSMutableDictionary *local=[metadata mutableCopy];
    NSString *display=[metadata[@"displayName"] isKindOfClass:NSString.class]?metadata[@"displayName"]:nil;
    local[@"displayName"]=display.length?[display substringToIndex:MIN(display.length,80)]:@"导入的桌宠";
    local[@"source"]=@"local-import";
    NSURL *destination=[root URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
    NSFileManager *manager=NSFileManager.defaultManager;
    [manager createDirectoryAtURL:destination withIntermediateDirectories:YES attributes:nil error:error];
    for(NSString *name in paths){
        if(*error)break;
        NSString *path=prefix.length?[prefix stringByAppendingPathComponent:name]:name;
        [manager copyItemAtURL:files[path] toURL:[destination URLByAppendingPathComponent:name] error:error];
    }
    if(!*error){NSData *json=[NSJSONSerialization dataWithJSONObject:local options:NSJSONWritingPrettyPrinted error:error];if(json)[json writeToURL:[destination URLByAppendingPathComponent:@"pet.json"] options:NSDataWritingAtomic error:error];}
    if(!*error)[metaData writeToURL:[destination URLByAppendingPathComponent:@"upstream-pet.json"] options:NSDataWritingAtomic error:error];
    if(*error){[manager removeItemAtURL:destination error:nil];return nil;}
    return destination;
}

// Only stale hidden staging directories created by this importer are eligible.
// A killed import is recovered on the next import; active concurrent imports
// have fresh timestamps and are left alone.
static void WPCleanupImportStaging(NSURL *root){
    NSFileManager *manager=NSFileManager.defaultManager;
    NSArray<NSURL *> *children=[manager contentsOfDirectoryAtURL:root includingPropertiesForKeys:@[NSURLIsDirectoryKey,NSURLIsSymbolicLinkKey,NSURLContentModificationDateKey] options:0 error:nil];
    for(NSURL *child in children){
        if(![child.lastPathComponent hasPrefix:@".wp-import-"])continue;
        NSDictionary *properties=[child resourceValuesForKeys:@[NSURLIsDirectoryKey,NSURLIsSymbolicLinkKey,NSURLContentModificationDateKey] error:nil];
        NSDate *date=properties[NSURLContentModificationDateKey];
        if([properties[NSURLIsDirectoryKey] boolValue] && ![properties[NSURLIsSymbolicLinkKey] boolValue] && [date isKindOfClass:NSDate.class] && date.timeIntervalSinceNow < -24*60*60)[manager removeItemAtURL:child error:nil];
    }
}
static NSURL *WPImportArchive(NSData *archive,NSURL *root,NSError **resultError){
    NSError *error=nil;NSFileManager *manager=NSFileManager.defaultManager;
    if(![manager createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:&error]){if(resultError)*resultError=error;return nil;}
    WPCleanupImportStaging(root);
    NSURL *staging=[root URLByAppendingPathComponent:[@".wp-import-" stringByAppendingString:NSUUID.UUID.UUIDString] isDirectory:YES];
    if(![manager createDirectoryAtURL:staging withIntermediateDirectories:NO attributes:nil error:&error]){if(resultError)*resultError=error;return nil;}
    NSDictionary<NSString *,NSURL *> *files=WPExtractPetZip(archive,[staging URLByAppendingPathComponent:@"archive" isDirectory:YES],&error);NSURL *destination=nil;

        if(files){
            NSMutableArray<NSString *> *metadataPaths=[NSMutableArray new];
            for(NSString *path in files)if([path.lastPathComponent isEqualToString:@"pet.json"])[metadataPaths addObject:path];
            if(metadataPaths.count!=1)error=WPImportError(@"一个桌宠包必须包含且只能包含一个 pet.json。");
            else {
                NSString *metaPath=metadataPaths.firstObject;NSNumber *metaSize=nil;[files[metaPath] getResourceValue:&metaSize forKey:NSURLFileSizeKey error:&error];
                NSData *metaData=metaSize.unsignedLongLongValue<=128*1024?[NSData dataWithContentsOfURL:files[metaPath] options:NSDataReadingMappedIfSafe error:&error]:nil;
                id metadata=metaData.length && metaData.length<=128*1024?[NSJSONSerialization JSONObjectWithData:metaData options:0 error:&error]:nil;
                if(![metadata isKindOfClass:NSDictionary.class])error=WPImportError(@"pet.json 必须是 128 KB 以内的 JSON 对象。");
                else if([metadata[@"spriteVersionNumber"] isKindOfClass:NSNumber.class] && [metadata[@"spriteVersionNumber"] integerValue]==5){
                    destination=WPImportRows(files,metadata,metaPath,metaData,staging,&error);
                } else {
                    NSString *sprite=[metadata[@"spritesheetPath"] isKindOfClass:NSString.class]?metadata[@"spritesheetPath"]:@"spritesheet.png";
                    if(![sprite isEqualToString:sprite.lastPathComponent] || ![@[@"png",@"webp"] containsObject:sprite.pathExtension.lowercaseString])error=WPImportError(@"spritesheetPath 需指向同目录下的 PNG 或 WebP 图集。");
                    NSString *directory=metaPath.stringByDeletingLastPathComponent;
                    NSString *spritePath=directory.length?[directory stringByAppendingPathComponent:sprite]:sprite;
                    NSURL *spriteFile=files[spritePath];
                    if(!spriteFile && !metadata[@"spritesheetPath"]){sprite=@"spritesheet.webp";spritePath=directory.length?[directory stringByAppendingPathComponent:sprite]:sprite;spriteFile=files[spritePath];}
                    if(!error && !spriteFile)error=WPImportError(@"未找到与 pet.json 同目录的动画图集。");
                    CGImageSourceRef source=(!error && spriteFile)?CGImageSourceCreateWithURL((__bridge CFURLRef)spriteFile,(__bridge CFDictionaryRef)@{(id)kCGImageSourceShouldCache:@NO}):NULL;
                    NSDictionary *props=source?CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source,0,NULL)):nil;
                    size_t width=[props[(__bridge id)kCGImagePropertyPixelWidth] unsignedLongValue],height=[props[(__bridge id)kCGImagePropertyPixelHeight] unsignedLongValue];
                    NSInteger version=[metadata[@"spriteVersionNumber"] isKindOfClass:NSNumber.class]?[metadata[@"spriteVersionNumber"] integerValue]:0;
                    BOOL validSize=(width==1536 && ((version==1 && height==1872) || (version==2 && height==2288) || (version==3 && height==6032))) || (version==4 && width==1920 && height==6032);
                    if(!error && !validSize)error=WPImportError(@"图集尺寸与版本不匹配：v1 为1536×1872，v2 为1536×2288，v3 为1536×6032，v4 为1920×6032；每格192×208。");
                    if(!error && (version==3 || version==4)){
                        NSDictionary *mapping=[metadata[@"semanticRows"] isKindOfClass:NSDictionary.class]?metadata[@"semanticRows"]:nil;
                        NSSet *allowed=[NSSet setWithArray:@[@"idle",@"tap",@"longPress",@"petting",@"sendPet",@"receivePet",@"sendMiss",@"receiveMiss",@"sendAnger",@"receiveAnger",@"angerIdle",@"angerResolved",@"drag",@"land",@"shake",@"peekLeft",@"peekRight",@"reveal",@"retract"]];
                        if(!mapping || mapping.count!=allowed.count)error=WPImportError(@"v3/v4 图集缺少语义动作映射。");
                        for(id key in mapping){
                            id row=mapping[key];
                            if(![key isKindOfClass:NSString.class] || ![allowed containsObject:key] || ![row isKindOfClass:NSNumber.class] || [row integerValue]<0 || [row integerValue]>=29)
                                error=WPImportError(@"semanticRows 包含无效动作或行号。");
                        }
                    }
                    CGImageRef image=!error && source?CGImageSourceCreateImageAtIndex(source,0,(__bridge CFDictionaryRef)@{(id)kCGImageSourceShouldCache:@NO}):NULL;
                    size_t columns=version==4?10:8;
                    NSArray *counts=image?WPImportedFrameCounts(image,width,height,columns):nil;
                    if(image)CGImageRelease(image);if(source)CFRelease(source);
                    if(!error && !counts)error=WPImportError(@"图集需要真实透明背景和可见角色。请先导出透明 PNG/WebP，去掉白底、黑底或棋盘格背景。");
                    if(!error){
                        NSMutableDictionary *local=[metadata mutableCopy];
                        NSString *display=[local[@"displayName"] isKindOfClass:NSString.class]?local[@"displayName"]:nil;
                        local[@"displayName"]=display.length?[display substringToIndex:MIN(display.length,80)]:@"导入的桌宠";
                        local[@"frameWidth"]=@192;local[@"frameHeight"]=@208;local[@"columns"]=@(columns);local[@"rows"]=@(height/208);local[@"frameCounts"]=counts;
                        local[@"source"]=@"local-import";local[@"spritesheetPath"]=[@"spritesheet." stringByAppendingString:sprite.pathExtension.lowercaseString];
                        destination=[staging URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
                        NSFileManager *manager=NSFileManager.defaultManager;[manager createDirectoryAtURL:destination withIntermediateDirectories:YES attributes:nil error:&error];
                        if(!error)[manager copyItemAtURL:spriteFile toURL:[destination URLByAppendingPathComponent:local[@"spritesheetPath"]] error:&error];
                        if(!error){NSData *data=[NSJSONSerialization dataWithJSONObject:local options:NSJSONWritingPrettyPrinted error:&error];if(data)[data writeToURL:[destination URLByAppendingPathComponent:@"pet.json"] options:NSDataWritingAtomic error:&error];}
                        if(!error)[metaData writeToURL:[destination URLByAppendingPathComponent:@"upstream-pet.json"] options:NSDataWritingAtomic error:&error];
                        if(error){[manager removeItemAtURL:destination error:nil];destination=nil;}
                    }
                }
            }
        }
    if(destination && !error){
        NSString *jsonPath=[destination.path stringByAppendingPathComponent:@"pet.json"];
        NSDictionary *local=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:jsonPath] options:0 error:nil];
        NSInteger version=[local[@"spriteVersionNumber"] integerValue];
        if(version>=1 && version<=4){
            NSString *paged=WPPagedLegacyDirectory(destination.path,local,&error);
            if(paged && !error){
                NSDictionary *pageMetadata=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[paged stringByAppendingPathComponent:@"pet.json"]] options:0 error:&error];
                for(NSString *name in pageMetadata[@"rowAtlasPaths"]){if(error)break;[manager moveItemAtPath:[paged stringByAppendingPathComponent:name] toPath:[destination.path stringByAppendingPathComponent:name] error:&error];}
                if(!error)[[NSData dataWithContentsOfFile:[paged stringByAppendingPathComponent:@"pet.json"]] writeToFile:jsonPath options:NSDataWritingAtomic error:&error];
                [manager removeItemAtPath:paged error:nil];
            }else if(!error)error=WPImportError(@"旧动画包分页失败，请重新导入。");
        }
    }
    // Publication is one same-volume move, after all files and metadata pass.
    // A bad archive can never replace an existing pet or leave a visible half pet.
    if(destination && !error){
        NSURL *published=[root URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
        if([manager moveItemAtURL:destination toURL:published error:&error])destination=published;else destination=nil;
    }else destination=nil;
    [manager removeItemAtURL:staging error:nil];
    if(resultError)*resultError=error;return destination;
}
#if defined(WP_PREVIEW_HOST)
NSURL *WPPreviewImportPetArchive(NSData *archive,NSURL *root,NSError **error){return WPImportArchive(archive,root,error);}
void WPPreviewCleanupImportStaging(NSURL *root){WPCleanupImportStaging(root);}
#endif
@implementation WPPetImporter
+ (void)importZipAtURL:(NSURL *)url destinationRoot:(NSURL *)root completion:(void (^)(NSURL *,NSError *))completion {
    dispatch_async(WPPetAssetWorkQueue(),^{
      @autoreleasepool {
        // Keep security-scoped access until the mapped archive has finished
        // streaming; a mapped NSData need not fault in all pages at creation.
        BOOL scoped=[url startAccessingSecurityScopedResource];
        NSError *error=nil;NSNumber *fileSize=nil;
        [url getResourceValue:&fileSize forKey:NSURLFileSizeKey error:&error];
        NSData *archive=(!error && fileSize && fileSize.unsignedLongLongValue<=32*1024*1024)?[NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:&error]:nil;
        NSURL *destination=archive?WPImportArchive(archive,root,&error):nil;
        if(!archive && !error)error=WPImportError(@"桌宠包超过 32 MB，或文件暂时不可读取。 ");
        if(scoped)[url stopAccessingSecurityScopedResource];
        dispatch_async(dispatch_get_main_queue(),^{completion(destination,error);});
      }
    });
}
@end
