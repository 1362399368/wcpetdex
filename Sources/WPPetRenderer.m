#import "WPPetRenderer.h"
#import "WPCommon.h"
#import "WPPagedPet.h"
#import <ImageIO/ImageIO.h>

static NSInteger WPAtlasInteger(id value) {
    return [value isKindOfClass:NSNumber.class] ? [value integerValue] : 0;
}

static NSSet<NSString *> *WPOneShotActions(void) {
    static NSSet<NSString *> *actions;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ actions = [NSSet setWithArray:@[@"reveal", @"retract", @"land", @"tap", @"longPress"]]; });
    return actions;
}

static BOOL WPAtlasExactInteger(id value,NSInteger minimum,NSInteger maximum) {
    if(![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value)==CFBooleanGetTypeID())return NO;
    double number=[value doubleValue];
    return isfinite(number) && floor(number)==number && number>=minimum && number<=maximum;
}
static BOOL WPAtlasRowName(id value) {
    if(![value isKindOfClass:NSString.class])return NO;
    NSString *name=value;
    return name.length>4 && name.length<=120 && [name isEqual:name.lastPathComponent] &&
        ![name containsString:@"\\"] && ![name containsString:@":"] && ![name containsString:@"\0"] &&
        [name.pathExtension.lowercaseString isEqual:@"png"];
}
static NSArray<NSString *> *WPAtlasRows(NSDictionary *metadata) {
    BOOL local=WPIsLocalPagedMetadata(metadata);
    NSInteger columns=local?[metadata[@"columns"] integerValue]:20,version=5;
    NSInteger rowCount=local?[metadata[@"rows"] integerValue]:29;
    if(!WPAtlasExactInteger(metadata[@"spriteVersionNumber"],version,version) ||
       !WPAtlasExactInteger(metadata[@"columns"],columns,columns) || !WPAtlasExactInteger(metadata[@"rows"],rowCount,rowCount) ||
       !WPAtlasExactInteger(metadata[@"frameWidth"],192,192) || !WPAtlasExactInteger(metadata[@"frameHeight"],208,208) ||
       !WPAtlasExactInteger(metadata[@"frameRate"],6,30))return nil;
    NSString *key=@"rowAtlasPaths";
    NSArray *paths=[metadata[key] isKindOfClass:NSArray.class]?metadata[key]:nil;
    NSArray *counts=[metadata[@"frameCounts"] isKindOfClass:NSArray.class]?metadata[@"frameCounts"]:nil;
    if(paths.count!=(NSUInteger)rowCount || counts.count!=(NSUInteger)rowCount || ![metadata[@"spritesheetPath"] isKindOfClass:NSString.class] ||
       ![metadata[@"spritesheetPath"] isEqual:paths.firstObject])return nil;
    NSMutableSet *seen=[NSMutableSet new];
    for(NSUInteger row=0;row<(NSUInteger)rowCount;row++){
        if(!WPAtlasRowName(paths[row]) || [seen containsObject:paths[row]] || !WPAtlasExactInteger(counts[row],1,columns))return nil;
        [seen addObject:paths[row]];
    }
    NSDictionary *mapping=[metadata[@"semanticRows"] isKindOfClass:NSDictionary.class]?metadata[@"semanticRows"]:nil;
    if(!local && !mapping)return nil;
    if(!local){
        for(id value in mapping.allValues)if(!WPAtlasExactInteger(value,0,rowCount-1))return nil;
        if(metadata[@"onlinePhoneRow"] && !WPAtlasExactInteger(metadata[@"onlinePhoneRow"],0,rowCount-1))return nil;
    }
    return paths;
}
// A row is checked and decoded from the same ImageIO source. Validating all
// other headers at selection time avoids discarding an imported pet later
// just because an action has not been played yet.
static CGImageSourceRef WPAtlasSource(NSString *path,NSUInteger expectedWidth,NSUInteger expectedHeight) {
    NSDictionary *attributes=[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
    if(![attributes[NSFileType] isEqual:NSFileTypeRegular] || [attributes[NSFileSize] unsignedLongLongValue]>32*1024*1024)return NULL;
    NSDictionary *options=@{(__bridge id)kCGImageSourceShouldCache:@NO};
    CGImageSourceRef source=CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path],(__bridge CFDictionaryRef)options);
    if(!source)return NULL;
    NSDictionary *properties=CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source,0,NULL));
    NSUInteger width=MAX(0,WPAtlasInteger(properties[(__bridge id)kCGImagePropertyPixelWidth]));
    NSUInteger height=MAX(0,WPAtlasInteger(properties[(__bridge id)kCGImagePropertyPixelHeight]));
    BOOL valid=width>0 && height>0 && width<=8192 && height<=16384 && width<=24*1024*1024/height;
    if(expectedWidth || expectedHeight)valid=valid && width==expectedWidth && height==expectedHeight &&
        [properties[(__bridge id)kCGImagePropertyHasAlpha] boolValue];
    if(!valid){CFRelease(source);return NULL;}
    return source;
}
static BOOL WPAtlasRowHeader(NSString *path,NSUInteger expectedWidth) {
    CGImageSourceRef source=WPAtlasSource(path,expectedWidth,208);
    if(source)CFRelease(source);
    return source!=NULL;
}
static UIImage *WPLoadBoundedAtlas(NSString *path,NSUInteger expectedWidth,NSUInteger expectedHeight) {
    CGImageSourceRef source=WPAtlasSource(path,expectedWidth,expectedHeight);
    if(!source)return nil;
    // Decode before replacing the visible row, keeping frame transitions atomic.
    NSDictionary *options=@{(__bridge id)kCGImageSourceShouldCache:@YES,
        (__bridge id)kCGImageSourceShouldCacheImmediately:@YES};
    CGImageRef image=CGImageSourceCreateImageAtIndex(source,0,(__bridge CFDictionaryRef)options);
    UIImage *result=image?[UIImage imageWithCGImage:image scale:1 orientation:UIImageOrientationUp]:nil;
    if(image)CGImageRelease(image);
    CFRelease(source);
    return result;
}

@interface WPAtlasLoadState : NSObject
@property(nonatomic) UIImage *image;
@property(nonatomic) NSDictionary *metadata;
@property(nonatomic) NSString *loadedPath;
@property(nonatomic) NSArray *rowAtlasPaths;
@property(nonatomic) NSArray *rowFrameMaps;
@property(nonatomic) NSArray *rowColumnCounts;
@property(nonatomic) NSMutableIndexSet *failedAtlasRows;
@property(nonatomic) NSString *assetDirectory;
@property(nonatomic) NSInteger loadedAtlasRow;
@end
@implementation WPAtlasLoadState
@end

#ifdef WP_PREVIEW_HOST
static BOOL WPAtlasPreviewSynchronous=NO;
void WPPreviewSetAtlasLoadingSynchronous(BOOL enabled){WPAtlasPreviewSynchronous=enabled;}
#endif
static BOOL WPAtlasSynchronousFixture(void) {
#ifdef WP_PREVIEW_HOST
    return WPAtlasPreviewSynchronous;
#else
    return NO;
#endif
}
static void WPAtlasMain(dispatch_block_t block) {
    CFRunLoopPerformBlock(CFRunLoopGetMain(),kCFRunLoopCommonModes,block);CFRunLoopWakeUp(CFRunLoopGetMain());
}
static WPAtlasLoadState *WPLoadPetState(NSString *selected,NSString *bundled) {
    WPAtlasLoadState *state=[WPAtlasLoadState new];state.loadedAtlasRow=-1;state.failedAtlasRows=[NSMutableIndexSet new];
    NSMutableOrderedSet<NSString *> *candidates = [NSMutableOrderedSet new];
    if (selected.length) [candidates addObject:selected];
    if (bundled.length) [candidates addObject:bundled];
    UIImage *image = nil;
    NSDictionary *metadata = nil;
    NSString *loadedPath = nil;
    // An existing directory can still contain a missing or unreadable atlas.
    // Try the bundled pet before the drawn emergency fallback, and keep the
    // selected preference so a temporarily unavailable asset is not discarded.
    for (NSString *path in candidates) {
        NSString *metadataPath=[path stringByAppendingPathComponent:@"pet.json"];
        NSDictionary *attributes=[NSFileManager.defaultManager attributesOfItemAtPath:metadataPath error:nil];
        NSData *data = [attributes[NSFileSize] unsignedLongLongValue]<=128*1024 ? [NSData dataWithContentsOfFile:metadataPath] : nil;
        id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        metadata = [json isKindOfClass:NSDictionary.class] ? json : @{};
        NSString *assetPath=path;
        NSInteger legacyVersion=WPAtlasInteger(metadata[@"spriteVersionNumber"]);
        if(![assetPath.stringByStandardizingPath isEqual:bundled.stringByStandardizingPath] && legacyVersion>=1 && legacyVersion<=4){
            NSString *paged=WPPagedLegacyDirectory(assetPath,metadata,nil);
            if(paged){NSData *pageData=[NSData dataWithContentsOfFile:[paged stringByAppendingPathComponent:@"pet.json"]];
                id pageJSON=pageData?[NSJSONSerialization JSONObjectWithData:pageData options:0 error:nil]:nil;
                if([pageJSON isKindOfClass:NSDictionary.class] && WPIsLocalPagedMetadata(pageJSON)){metadata=pageJSON;assetPath=paged;}}
            // A failed migration falls back to the bundled pet. Never retain
            // the original large image just because disk space is unavailable.
            else {
                // Older hand-edited single-image pets sometimes retain a v4
                // label. Keep those small images compatible without ever
                // decoding a full failed legacy atlas as a fallback.
                NSString *file=[metadata[@"spritesheetPath"] isKindOfClass:NSString.class]?metadata[@"spritesheetPath"]:@"spritesheet.png";
                CGImageSourceRef tiny=CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:[assetPath stringByAppendingPathComponent:file]],(__bridge CFDictionaryRef)@{(__bridge id)kCGImageSourceShouldCache:@NO});
                NSDictionary *properties=tiny?CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(tiny,0,NULL)):nil;if(tiny)CFRelease(tiny);
                NSUInteger w=[properties[(__bridge id)kCGImagePropertyPixelWidth] unsignedIntegerValue],h=[properties[(__bridge id)kCGImagePropertyPixelHeight] unsignedIntegerValue];
                if(!w || !h || w>512 || h>512)continue;
            }
        }
        if(WPAtlasInteger(metadata[@"spriteVersionNumber"])==5){
            NSArray *paths=WPAtlasRows(metadata);BOOL valid=paths!=nil;
            NSUInteger width=(NSUInteger)WPAtlasInteger(metadata[@"columns"])*192;
            NSMutableArray *resolvedMaps=[NSMutableArray new],*resolvedColumns=[NSMutableArray new];
            NSMutableIndexSet *failed=[NSMutableIndexSet new];
            for(NSUInteger row=0;valid && row<paths.count;row++){
                if(!WPAtlasRowHeader([assetPath stringByAppendingPathComponent:paths[row]],width))valid=NO;
                [resolvedMaps addObject:@[]];[resolvedColumns addObject:@(width/192)];
            }
            UIImage *page=valid?WPLoadBoundedAtlas([assetPath stringByAppendingPathComponent:paths.firstObject],width,208):nil;
            if(page){
                image=page;state.rowAtlasPaths=paths;state.rowFrameMaps=resolvedMaps;state.rowColumnCounts=resolvedColumns;
                state.failedAtlasRows=failed;state.assetDirectory=assetPath;state.loadedAtlasRow=0;
                loadedPath=path;break;
            }
            continue;
        }
        // The current built-in pet is paged. Even malformed metadata must
        // not silently allocate the development-only full atlas.
        if([assetPath.stringByStandardizingPath isEqual:bundled.stringByStandardizingPath])continue;
        for (NSString *file in @[@"spritesheet.png", @"spritesheet.webp", @"pet.png"]) {
            UIImage *candidate = WPLoadBoundedAtlas([assetPath stringByAppendingPathComponent:file],0,0);
            if (candidate.CGImage && CGImageGetWidth(candidate.CGImage) && CGImageGetHeight(candidate.CGImage)) {
                image = candidate; break;
            }
        }
        if (!image) continue;
        NSInteger columns=WPAtlasInteger(metadata[@"columns"]),rows=WPAtlasInteger(metadata[@"rows"]);
        NSInteger frameWidth=WPAtlasInteger(metadata[@"frameWidth"]),frameHeight=WPAtlasInteger(metadata[@"frameHeight"]);
        size_t imageWidth=CGImageGetWidth(image.CGImage),imageHeight=CGImageGetHeight(image.CGImage);
        if(!metadata.count && imageWidth<=512 && imageHeight<=512){
            metadata=@{@"columns":@1,@"rows":@1,@"frameWidth":@(imageWidth),@"frameHeight":@(imageHeight)};
            columns=rows=1;frameWidth=imageWidth;frameHeight=imageHeight;
        }
        if(columns==0 && rows==0 && imageWidth==1536 && imageHeight%208==0){
            columns=8;rows=imageHeight/208;frameWidth=192;frameHeight=208;
            NSMutableDictionary *inferred=[metadata mutableCopy];
            inferred[@"columns"]=@(columns);inferred[@"rows"]=@(rows);
            inferred[@"frameWidth"]=@(frameWidth);inferred[@"frameHeight"]=@(frameHeight);
            metadata=inferred;
        }
        if(columns>0 && frameWidth==0 && imageWidth%(size_t)columns==0)frameWidth=imageWidth/(size_t)columns;
        if(rows>0 && frameHeight==0 && imageHeight%(size_t)rows==0)frameHeight=imageHeight/(size_t)rows;
        NSArray *counts=[metadata[@"frameCounts"] isKindOfClass:NSArray.class]?metadata[@"frameCounts"]:nil;
        BOOL valid=columns>0 && rows>0 && columns<=32 && rows<=64 && frameWidth>0 && frameHeight>0 && frameWidth<=8192 && frameHeight<=16384 &&
            (size_t)columns*(size_t)MAX(1,frameWidth)==imageWidth &&
            (size_t)rows*(size_t)MAX(1,frameHeight)==imageHeight &&
            (!counts || counts.count==(NSUInteger)rows);
        if(valid && counts)for(id count in counts)if(![count isKindOfClass:NSNumber.class] || [count integerValue]<1 || [count integerValue]>columns){valid=NO;break;}
        if(!valid){image=nil;metadata=nil;continue;}
        loadedPath=path;
        break;
    }
    state.image=image;state.metadata=metadata?:@{};state.loadedPath=loadedPath;return state;
}

@interface WPWeakAnimationTarget : NSObject
@property(nonatomic,weak) WPPetRenderer *renderer;
- (void)tick:(CADisplayLink *)link;
@end

@interface WPPetRenderer ()
@property (nonatomic) CALayer *spriteLayer;
@property (nonatomic) UIImage *atlas;
@property (nonatomic) NSData *alphaMask;
@property (nonatomic) size_t atlasWidth;
@property (nonatomic) size_t atlasHeight;
@property (nonatomic) NSInteger alphaMaskRow;
@property (nonatomic) NSInteger alphaMaskFrame;
@property (nonatomic) CADisplayLink *displayLink;
@property (nonatomic) NSString *petName;
@property (nonatomic) NSInteger columns;
@property (nonatomic) NSInteger rows;
@property (nonatomic) NSInteger reactionRow;
@property (nonatomic) NSInteger animationRow;
@property (nonatomic) NSInteger frameCount;
@property (nonatomic) NSInteger frameIndex;
@property (nonatomic) NSInteger frameRate;
@property (nonatomic) NSInteger heldPeekRow;
@property (nonatomic) NSInteger dragRow;
@property (nonatomic) BOOL heldPeekLeft;
@property (nonatomic) CFTimeInterval animationStartedAt;
@property (nonatomic) CFTimeInterval greetingUntil;
@property (nonatomic) NSDictionary *metadata;
@property (nonatomic, copy) NSString *reactionKind;
@property (nonatomic, copy) NSString *queuedReaction;
@property (nonatomic,copy) NSArray<NSString *> *rowAtlasPaths;
@property (nonatomic,copy) NSString *assetDirectory;
@property (nonatomic,copy) NSArray<NSArray<NSNumber *> *> *rowFrameMaps;
@property (nonatomic,copy) NSArray<NSNumber *> *rowColumnCounts;
@property (nonatomic) NSMutableIndexSet *failedAtlasRows;
@property (nonatomic) NSInteger displayedAtlasFrame;
@property (nonatomic) NSInteger displayedAtlasRow;
@property (nonatomic) NSInteger displayedColumns;
@property (nonatomic) NSInteger displayedRows;
@property (nonatomic) NSInteger loadedAtlasRow;
@property (nonatomic) BOOL animationPaused;
@property (nonatomic) NSUInteger assetGeneration;
@property (nonatomic) BOOL reloadInFlight;
@property (nonatomic) BOOL reloadAgain;
@property (nonatomic) BOOL needsReloadOnActivation;
@property (nonatomic,copy) NSString *loadedSelectedDirectory;
@property (nonatomic,copy) NSString *requestedSelectedDirectory;
@property (nonatomic) BOOL rowDecodeInFlight;
@property (nonatomic) NSInteger desiredAtlasRow;
@property (nonatomic) NSUInteger rowDecodeToken;
#ifdef WP_PREVIEW_HOST
@property(nonatomic,copy) NSString *previewBundledDirectory;
#endif
- (void)applyLoadedState:(WPAtlasLoadState *)state selected:(NSString *)selected;
- (void)beginDesiredRowDecode;
- (NSInteger)semanticRowForAction:(NSString *)action;
- (NSInteger)passiveFrameForElapsedFrames:(NSInteger)elapsedFrames;
- (void)tick:(CADisplayLink *)link;
@end

@implementation WPWeakAnimationTarget
- (void)tick:(CADisplayLink *)link {
    WPPetRenderer *renderer=self.renderer;
    if(renderer)[renderer tick:link];else [link invalidate];
}
@end

@implementation WPPetRenderer
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        self.opaque = NO;
        self.isAccessibilityElement = YES;
        self.accessibilityLabel = @"桌宠";
        self.accessibilityHint = @"拖动调整位置，长按或摇晃执行设定的快捷功能";
        self.accessibilityTraits = UIAccessibilityTraitButton;
        _spriteLayer = [CALayer layer];
        _spriteLayer.contentsGravity = kCAGravityResizeAspect;
        _spriteLayer.magnificationFilter = kCAFilterNearest;
        _spriteLayer.minificationFilter = kCAFilterLinear;
        [self.layer addSublayer:_spriteLayer];
        _heldPeekRow = -1;
        _dragRow = -1;
        _frameRate = 12;_columns=_rows=_frameCount=1;_loadedAtlasRow=-1;_desiredAtlasRow=-1;
        [self reloadPet];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews]; self.spriteLayer.frame = self.bounds;
 }
- (NSInteger)idleRow {
    id row=[self.metadata[@"semanticRows"] isKindOfClass:NSDictionary.class]?self.metadata[@"semanticRows"][@"idle"]:nil;
    return [row isKindOfClass:NSNumber.class]?MAX(0,MIN(self.rows-1,[row integerValue])):0;
}
- (void)reloadPet {
    if(self.animationPaused){self.needsReloadOnActivation=YES;return;}
    NSString *selected=WPSelectedPetDirectory(),*bundled=WPDefaultPetDirectory();
    self.needsReloadOnActivation=NO;self.requestedSelectedDirectory=selected?:@"";
    self.assetGeneration++;self.desiredAtlasRow=-1;
    if(self.reloadInFlight){self.reloadAgain=YES;return;}
#ifdef WP_PREVIEW_HOST
    if(self.previewBundledDirectory.length)bundled=self.previewBundledDirectory;
#endif
    if(WPAtlasSynchronousFixture()){[self applyLoadedState:WPLoadPetState(selected,bundled) selected:selected];return;}
    self.reloadInFlight=YES;self.reloadAgain=NO;NSUInteger generation=self.assetGeneration;
    __weak typeof(self) weakSelf=self;
    dispatch_async(WPPetAssetWorkQueue(),^{@autoreleasepool {
        WPAtlasLoadState *state=WPLoadPetState(selected,bundled);
        WPAtlasMain(^{typeof(self) self=weakSelf;if(!self)return;
            self.reloadInFlight=NO;
            if(self.animationPaused)return;
            if(generation!=self.assetGeneration || self.reloadAgain){self.reloadAgain=NO;[self reloadPet];return;}
            [self applyLoadedState:state selected:selected];
        });
    }});
}
- (void)applyLoadedState:(WPAtlasLoadState *)state selected:(NSString *)selected {
    self.needsReloadOnActivation=NO;self.loadedSelectedDirectory=selected?:@"";
    UIImage *image=state.image;NSDictionary *metadata=state.metadata;NSString *loadedPath=state.loadedPath;
    self.rowAtlasPaths=state.rowAtlasPaths;self.rowFrameMaps=state.rowFrameMaps;self.rowColumnCounts=state.rowColumnCounts;
    self.failedAtlasRows=state.failedAtlasRows;self.assetDirectory=state.assetDirectory;self.loadedAtlasRow=state.loadedAtlasRow;
    [WPPreferences() setObject:@{@"selectedReference":WPSelectedPetReference()?:@"",
        @"selectedDirectoryName":selected.lastPathComponent?:@"",
        @"selectedExists":@([[NSFileManager defaultManager] fileExistsAtPath:selected?:@""]),
        @"loadedDirectoryName":loadedPath.lastPathComponent?:@"",
        @"temporaryFallback":@(selected.length && ![loadedPath isEqualToString:selected]),
        @"reason":image?((selected.length && ![loadedPath isEqualToString:selected])?@"selected_asset_unavailable":@"loaded_selected"):@"atlas_decode_failed"}
        forKey:@"selectedPetLastLoad"];
    self.metadata = metadata ?: @{};
    self.reactionKind=nil;self.queuedReaction=nil;self.greetingUntil=0;self.dragRow=-1;
    NSString *name = self.metadata[@"displayName"] ?: self.metadata[@"name"];
    self.petName = [name isKindOfClass:NSString.class] ? name : @"小团子";
    self.accessibilityLabel = [@"桌宠 " stringByAppendingString:self.petName];
    if (!image) { [self installFallback]; return; }
    self.atlas = image;
    self.columns = MAX(1, WPAtlasInteger(self.metadata[@"columns"]));
    self.rows = MAX(1, WPAtlasInteger(self.metadata[@"rows"]));
    if (!self.metadata[@"columns"]) {
        self.columns = image.size.width >= 1000 ? 8 : 1;
        self.rows = self.columns == 8 ? MAX(1, (NSInteger)lround(image.size.height / 208.0)) : 1;
    }
    [self prepareAlphaMask];
    NSInteger requestedRate=WPAtlasInteger(self.metadata[@"frameRate"]);
    self.frameRate=requestedRate>=6 && requestedRate<=30 ? requestedRate : 12;
    if(self.displayLink)self.displayLink.preferredFramesPerSecond=self.frameRate;
    if (self.heldPeekRow >= 0) self.heldPeekRow = [self semanticRowForAction:self.heldPeekLeft ? @"peekLeft" : @"peekRight"];
    self.animationRow = self.heldPeekRow >= 0 ? self.heldPeekRow : [self idleRow]; self.frameIndex = 0;
    self.frameCount = [self countForRow:self.animationRow];
    self.animationStartedAt=CACurrentMediaTime();
    [self showFrame];
    self.accessibilityLabel = [@"桌宠 " stringByAppendingString:self.petName];
}
- (void)installFallback {
    self.rowAtlasPaths=nil;self.rowFrameMaps=nil;self.rowColumnCounts=nil;self.failedAtlasRows=[NSMutableIndexSet new];self.assetDirectory=nil;self.loadedAtlasRow=-1;self.metadata=@{};
    UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat defaultFormat];
    format.scale=1;format.opaque=NO;format.preferredRange=UIGraphicsImageRendererFormatRangeStandard;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(192, 208) format:format];
    self.atlas = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        UIColor *body = [UIColor colorWithRed:1 green:.76 blue:.32 alpha:1];
        [body setFill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(35, 62, 122, 121)] fill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(29, 49, 38, 49)] fill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(125, 49, 38, 49)] fill];
        [[UIColor colorWithRed:.26 green:.18 blue:.15 alpha:1] setFill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(67, 105, 9, 13)] fill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(117, 105, 9, 13)] fill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(89, 125, 15, 10)] fill];
        [[UIColor colorWithRed:1 green:.52 blue:.44 alpha:.8] setFill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(50, 123, 20, 10)] fill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(124, 123, 20, 10)] fill];
    }];
    self.columns = self.rows = self.frameCount = 1;
    self.frameRate=12;
    if(self.displayLink)self.displayLink.preferredFramesPerSecond=self.frameRate;
    if (self.heldPeekRow >= 0) self.heldPeekRow = 0;
    [self prepareAlphaMask];
    self.animationRow = self.frameIndex = 0;
    self.animationStartedAt=CACurrentMediaTime();
    [self showFrame];
}
- (BOOL)loadActionRow:(NSInteger)row {
    if(self.animationPaused)return NO;
    self.desiredAtlasRow=row;
    if(row==self.loadedAtlasRow && self.atlas.CGImage)return YES;
    if(row<0 || (NSUInteger)row>=self.rowAtlasPaths.count || [self.failedAtlasRows containsIndex:(NSUInteger)row])return NO;
    if(WPAtlasSynchronousFixture()){
        NSString *name=self.rowAtlasPaths[row];NSUInteger columns=[self.rowColumnCounts[row] unsignedIntegerValue];
        UIImage *image=WPLoadBoundedAtlas([self.assetDirectory stringByAppendingPathComponent:name],columns*192,208);
        if(!image){[self.failedAtlasRows addIndex:(NSUInteger)row];return NO;}
        self.atlas=image;self.loadedAtlasRow=row;[self prepareAlphaMask];return YES;
    }
    [self beginDesiredRowDecode];return NO;
}
- (void)beginDesiredRowDecode {
    NSInteger row=self.desiredAtlasRow;
    if(self.rowDecodeInFlight || self.reloadInFlight || self.animationPaused || row<0 || (NSUInteger)row>=self.rowAtlasPaths.count ||
       [self.failedAtlasRows containsIndex:(NSUInteger)row] || (self.loadedAtlasRow==row && self.atlas.CGImage))return;
    NSString *name=self.rowAtlasPaths[row],*path=[self.assetDirectory stringByAppendingPathComponent:name];
    NSUInteger columns=[self.rowColumnCounts[row] unsignedIntegerValue],generation=self.assetGeneration,token=++self.rowDecodeToken;
    self.rowDecodeInFlight=YES;__weak typeof(self) weakSelf=self;
    dispatch_async(WPPetAssetWorkQueue(),^{@autoreleasepool {
        UIImage *image=WPLoadBoundedAtlas(path,columns*192,208);
        WPAtlasMain(^{typeof(self) self=weakSelf;if(!self || self.rowDecodeToken!=token)return;
            self.rowDecodeInFlight=NO;
            if(!self.animationPaused && generation==self.assetGeneration){
                if(!image)[self.failedAtlasRows addIndex:(NSUInteger)row];
                if(image && self.desiredAtlasRow==row && self.animationRow==row){
                    self.atlas=image;self.loadedAtlasRow=row;[self prepareAlphaMask];
                    // Start the action at its first visible frame; disk latency
                    // never skips the beginning or shortens a one-shot action.
                    CFTimeInterval now=CACurrentMediaTime(),remaining=MAX(0,self.greetingUntil-self.animationStartedAt);
                    self.animationStartedAt=now;self.frameIndex=0;
                    if(self.reactionKind)self.greetingUntil=now+remaining;
                    [self showFrame];
                }else if(!image && self.animationRow==row){[self showFrame];}
            }
            [self beginDesiredRowDecode];
        });
    }});
}
- (void)showFrame {
    if(self.animationPaused)return;
    if(self.rowAtlasPaths.count && ![self loadActionRow:self.animationRow]){
        if(![self.failedAtlasRows containsIndex:(NSUInteger)self.animationRow])return;
        NSInteger idle=[self idleRow];
        self.reactionKind=nil;self.queuedReaction=nil;self.greetingUntil=0;
        if(self.animationRow==idle)return;
        self.animationRow=idle;self.frameIndex=0;self.frameCount=[self countForRow:idle];
        self.animationStartedAt=CACurrentMediaTime();
        if(![self loadActionRow:idle])return;
    }
    if(!self.atlas.CGImage)return;
    NSInteger physicalRow=self.rowAtlasPaths.count?0:self.animationRow;
    NSInteger physicalRows=self.rowAtlasPaths.count?1:self.rows;
    NSInteger physicalColumns=self.columns,physicalFrame=self.frameIndex;
    if(self.rowAtlasPaths.count && self.loadedAtlasRow>=0 && (NSUInteger)self.loadedAtlasRow<self.rowColumnCounts.count){
        physicalColumns=[self.rowColumnCounts[self.loadedAtlasRow] integerValue];
        NSArray *map=self.rowFrameMaps[self.loadedAtlasRow];
        if((NSUInteger)self.frameIndex<map.count)physicalFrame=[map[self.frameIndex] integerValue];
    }
    self.displayedAtlasRow=physicalRow;self.displayedAtlasFrame=physicalFrame;
    self.displayedColumns=physicalColumns;self.displayedRows=physicalRows;
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    if(self.spriteLayer.contents!=(__bridge id)self.atlas.CGImage)
        self.spriteLayer.contents=(__bridge id)self.atlas.CGImage;
    CGRect crop=CGRectMake((CGFloat)physicalFrame / physicalColumns,
        (CGFloat)physicalRow / physicalRows, 1.0 / physicalColumns, 1.0 / physicalRows);
    if(!CGRectEqualToRect(self.spriteLayer.contentsRect,crop))self.spriteLayer.contentsRect=crop;
    BOOL edgeTransition=([self.reactionKind isEqualToString:@"reveal"] || [self.reactionKind isEqualToString:@"retract"])
        && self.animationRow==self.reactionRow && CACurrentMediaTime()<self.greetingUntil;
    CATransform3D transform=edgeTransition && self.heldPeekLeft ? CATransform3DMakeScale(-1,1,1) : CATransform3DIdentity;
    if(!CATransform3DEqualToTransform(self.spriteLayer.transform,transform))self.spriteLayer.transform=transform;
    [CATransaction commit];
}
- (NSInteger)countForRow:(NSInteger)row {
    id counts = self.metadata[@"frameCounts"];
    if ([counts isKindOfClass:NSArray.class] && row >= 0 && (NSUInteger)row < [counts count]) {
        return MAX(1, MIN(self.columns, [counts[row] integerValue]));
    }
    return MAX(1,self.columns);
}
- (void)setAnimationActive:(BOOL)active {
    self.animationPaused=!active;
    NSString *expected=self.reloadInFlight?self.requestedSelectedDirectory:self.loadedSelectedDirectory;
    if(active && (self.needsReloadOnActivation || ![(WPSelectedPetDirectory()?:@"") isEqual:(expected?:@"")])){
        [self reloadPet];
    }else if(active && !self.atlas && !self.reloadInFlight){
        if(self.metadata.count && self.rowAtlasPaths.count){self.loadedAtlasRow=-1;[self showFrame];}
        else [self reloadPet];
    }
    if (active && !self.displayLink) {
        WPWeakAnimationTarget *target=[WPWeakAnimationTarget new];target.renderer=self;
        self.displayLink = [CADisplayLink displayLinkWithTarget:target selector:@selector(tick:)];
        self.displayLink.preferredFramesPerSecond = self.frameRate;
        [self.displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    } else if (!active) {
        if(self.reloadInFlight)self.needsReloadOnActivation=YES;
        self.assetGeneration++;self.desiredAtlasRow=-1;self.reloadAgain=NO;
        [self.displayLink invalidate];self.displayLink=nil;
        [CATransaction begin];[CATransaction setDisableActions:YES];
        self.spriteLayer.contents=nil;[self.spriteLayer removeAllAnimations];[CATransaction commit];
        self.atlas=nil;self.alphaMask=nil;self.atlasWidth=self.atlasHeight=0;
        self.loadedAtlasRow=-1;
    }
}
- (NSInteger)passiveFrameForElapsedFrames:(NSInteger)elapsedFrames {
    NSDictionary *all = [self.metadata[@"passiveAnimations"] isKindOfClass:NSDictionary.class]
        ? self.metadata[@"passiveAnimations"] : nil;
    if (!all) return NSNotFound;
    NSString *key = @"idle";
    if ([key isEqualToString:@"idle"] && self.animationRow != [self semanticRowForAction:@"idle"])
        return NSNotFound;
    NSDictionary *config = [all[key] isKindOfClass:NSDictionary.class] ? all[key] : nil;
    NSArray *rest = [config[@"restFrames"] isKindOfClass:NSArray.class] ? config[@"restFrames"] : nil;
    NSArray *blink = [config[@"blinkFrames"] isKindOfClass:NSArray.class] ? config[@"blinkFrames"] : nil;
    double seconds = [config[@"intervalSeconds"] isKindOfClass:NSNumber.class]
        ? [config[@"intervalSeconds"] doubleValue] : 0;
    if (!rest.count || !blink.count || !isfinite(seconds) || seconds < 1 || seconds > 30) return NSNotFound;
    NSInteger period = (NSInteger)lround(seconds * self.frameRate);
    NSInteger restDuration = period - (NSInteger)blink.count;
    if (restDuration < 1) return NSNotFound;
    NSInteger phase = elapsedFrames % period;
    NSArray *sequence = phase < restDuration ? rest : blink;
    NSInteger index = phase < restDuration ? phase % (NSInteger)rest.count : phase - restDuration;
    id frame = sequence[index];
    if (![frame isKindOfClass:NSNumber.class]) return NSNotFound;
    NSInteger number = [frame integerValue];
    return number >= 0 && number < self.frameCount ? number : NSNotFound;
}
- (void)tick:(CADisplayLink *)link {
    if(self.reloadInFlight || (self.rowAtlasPaths.count && self.desiredAtlasRow>=0 && self.loadedAtlasRow!=self.desiredAtlasRow && ![self.failedAtlasRows containsIndex:(NSUInteger)self.desiredAtlasRow]))return;
    BOOL greeting = link.timestamp < self.greetingUntil && self.reactionKind!=nil;
    BOOL endedReaction=!greeting && self.reactionKind!=nil;
    if (endedReaction) {
        self.reactionKind = nil;
        NSString *next = self.queuedReaction; self.queuedReaction = nil;
        if (next) { [self playSemanticAction:next]; greeting = YES; }
    }
    NSInteger newRow = greeting ? MIN(self.rows-1,self.reactionRow) :
        (self.dragRow >= 0 ? self.dragRow : (self.heldPeekRow >= 0 ? self.heldPeekRow : [self idleRow]));
    BOOL rowChanged=newRow!=self.animationRow;
    if (rowChanged) {
        self.animationRow = newRow; self.frameCount = [self countForRow:newRow];
        self.animationStartedAt=link.timestamp;
    }
    NSInteger elapsedFrames=MAX(0,(NSInteger)floor((link.timestamp-self.animationStartedAt)*self.frameRate+.001));
    BOOL oneShot=greeting && [WPOneShotActions() containsObject:self.reactionKind];
    NSInteger passiveFrame = !greeting && self.dragRow < 0 && self.heldPeekRow < 0
        ? [self passiveFrameForElapsedFrames:elapsedFrames] : NSNotFound;
    NSInteger frame=passiveFrame != NSNotFound ? passiveFrame :
        (oneShot ? MIN(self.frameCount-1,elapsedFrames) : elapsedFrames%self.frameCount);
    BOOL frameChanged=frame!=self.frameIndex;self.frameIndex=frame;
    if(rowChanged || frameChanged || endedReaction)[self showFrame];
}
- (BOOL)playMessageAcknowledgement {
    if(self.animationPaused || self.hidden || self.dragRow>=0 || self.heldPeekRow>=0 || self.queuedReaction)return NO;
    if(self.reactionKind && CACurrentMediaTime()<self.greetingUntil)return NO;
    return [self playSemanticAction:@"tap"];
}
- (NSInteger)semanticRowForAction:(NSString *)action {
    static NSDictionary *fallback;static dispatch_once_t once;dispatch_once(&once,^{fallback=@{@"tap":@6,@"longPress":@6,@"drag":@1,@"land":@0,@"shake":@8,@"peekLeft":@0,@"peekRight":@0,
        @"reveal":@4,@"retract":@6};});
    id custom=[self.metadata[@"semanticRows"] isKindOfClass:NSDictionary.class]?self.metadata[@"semanticRows"][action]:nil;
    NSInteger row=[custom isKindOfClass:NSNumber.class]?[custom integerValue]:[fallback[action] integerValue];
    return MAX(0,MIN(self.rows-1,row));
}
- (void)holdPeekOnLeft:(BOOL)left {
    self.dragRow=-1;
    self.heldPeekLeft=left;
    self.heldPeekRow=[self semanticRowForAction:left?@"peekLeft":@"peekRight"];
    self.reactionKind=nil;self.queuedReaction=nil;self.greetingUntil=0;
    self.animationRow=self.heldPeekRow;self.frameCount=[self countForRow:self.animationRow];self.frameIndex=0;
    self.animationStartedAt=CACurrentMediaTime();
    [self showFrame];
}
- (void)endPeek {
    self.heldPeekRow=-1;
}
- (void)beginDragAnimation {
    self.dragRow=[self semanticRowForAction:@"drag"];
    self.reactionKind=nil;self.queuedReaction=nil;self.greetingUntil=0;
    self.animationRow=self.dragRow;self.frameCount=[self countForRow:self.animationRow];self.frameIndex=0;
    self.animationStartedAt=CACurrentMediaTime();[self showFrame];
}
- (void)updateDragDirectionLeft:(BOOL)left {
    if(self.dragRow<0)return;
    NSInteger row=MIN(self.rows-1,left?2:1);
    if(row==self.dragRow)return;
    self.dragRow=row;
    if(CACurrentMediaTime()<self.greetingUntil && self.reactionKind)return;
    self.animationRow=row;self.frameCount=[self countForRow:row];self.frameIndex=0;
    self.animationStartedAt=CACurrentMediaTime();[self showFrame];
}
- (void)endDragAnimation {
    if(self.dragRow<0)return;
    self.dragRow=-1;
    if(CACurrentMediaTime()<self.greetingUntil && self.reactionKind)return;
    self.animationRow=self.heldPeekRow>=0?self.heldPeekRow:[self idleRow];
    self.frameCount=[self countForRow:self.animationRow];self.frameIndex=0;
    self.animationStartedAt=CACurrentMediaTime();[self showFrame];
}
- (BOOL)playSemanticAction:(NSString *)action {
    CFTimeInterval now=CACurrentMediaTime();
    BOOL playing=now<self.greetingUntil && self.reactionKind;
    if(playing && [self.reactionKind isEqual:action])return NO;
    BOOL urgent=[@[@"reveal",@"retract",@"drag",@"land",@"shake",@"longPress",@"tap"] containsObject:action];
    if(playing && !urgent){if(![self.queuedReaction isEqual:action])self.queuedReaction=action;return NO;}
    if(urgent)self.queuedReaction=nil;
    self.reactionKind=action;self.reactionRow=[self semanticRowForAction:action];
    self.animationRow=self.reactionRow;
    self.frameCount=[self countForRow:self.animationRow];self.frameIndex=0;
    self.animationStartedAt=now;
    BOOL oneCycle=[WPOneShotActions() containsObject:action];
    self.greetingUntil=now+(oneCycle?1:2)*(CGFloat)self.frameCount/MAX(1,self.frameRate);
    [self showFrame];
    return YES;
}
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if (![super pointInside:point withEvent:event]) return NO;
    if (!self.atlas.CGImage || CGRectIsEmpty(self.bounds) || !self.atlasWidth || !self.atlasHeight) return NO;
    // Hit data belongs to the current cell, and is prepared only when a touch
    // needs it. Switching animation frames never rasterizes an entire atlas.
    if(self.alphaMaskRow!=self.displayedAtlasRow || self.alphaMaskFrame!=self.displayedAtlasFrame || !self.alphaMask.length)
        [self prepareFrameAlphaMask];
    CGFloat localX=self.spriteLayer.transform.m11<0 ? MAX(0,self.bounds.size.width-point.x-.01) : point.x;
    // Preserve atlas-coordinate rounding before translating to this cell.
    size_t sourceWidth=CGImageGetWidth(self.atlas.CGImage),sourceHeight=CGImageGetHeight(self.atlas.CGImage);
    CGFloat fx=((CGFloat)self.displayedAtlasFrame+localX/self.bounds.size.width)/MAX(1,self.displayedColumns);
    NSInteger physicalRow=self.displayedAtlasRow;
    NSInteger physicalRows=MAX(1,self.displayedRows);
    CGFloat fy=((CGFloat)physicalRow+point.y/self.bounds.size.height)/physicalRows;
    size_t atlasX=MIN(sourceWidth-1,(size_t)floor(fx*sourceWidth));
    size_t atlasY=MIN(sourceHeight-1,(size_t)floor(fy*sourceHeight));
    size_t frameStart=(size_t)self.displayedAtlasFrame*self.atlasWidth,rowStart=(size_t)physicalRow*self.atlasHeight;
    size_t x=MIN(self.atlasWidth-1,atlasX>=frameStart?atlasX-frameStart:0);
    size_t y=MIN(self.atlasHeight-1,atlasY>=rowStart?atlasY-rowStart:0);
    if(!self.alphaMask.length)return YES;
    const unsigned char *mask=self.alphaMask.bytes;
    size_t index=y*self.atlasWidth+x;
    return (mask[index>>3] & (1u<<(index&7)))!=0;
}
- (void)prepareFrameAlphaMask {
    CGImageRef atlas=self.atlas.CGImage;
    if(!atlas || !self.atlasWidth || !self.atlasHeight || self.displayedAtlasFrame<0 || self.displayedAtlasFrame>=self.displayedColumns ||
       self.displayedAtlasRow<0 || self.displayedAtlasRow>=self.displayedRows)return;
    // Never retain a mask for a different cel if allocation fails.
    self.alphaMask=nil;self.alphaMaskRow=self.alphaMaskFrame=-1;
    NSInteger physicalRow=self.displayedAtlasRow;
    CGImageRef frame=CGImageCreateWithImageInRect(atlas,CGRectMake(self.displayedAtlasFrame*self.atlasWidth,
        physicalRow*self.atlasHeight,self.atlasWidth,self.atlasHeight));
    if(!frame)return;
    size_t count=self.atlasWidth*self.atlasHeight,packedSize=(count+7)/8;
    unsigned char *pixels=calloc(count,1);
    CGContextRef context=pixels?CGBitmapContextCreate(pixels,self.atlasWidth,self.atlasHeight,8,self.atlasWidth,NULL,(CGBitmapInfo)kCGImageAlphaOnly):NULL;
    if(!context){free(pixels);CGImageRelease(frame);return;}
    CGContextDrawImage(context,CGRectMake(0,0,self.atlasWidth,self.atlasHeight),frame);
    CGContextRelease(context);CGImageRelease(frame);
    unsigned char *packed=calloc(packedSize,1);
    if(packed)for(size_t index=0;index<count;index++)if(pixels[index]>12)packed[index>>3]|=(1u<<(index&7));
    free(pixels);
    if(!packed)return;
    self.alphaMask=[NSData dataWithBytesNoCopy:packed length:packedSize freeWhenDone:YES];
    self.alphaMaskFrame=self.displayedAtlasFrame;self.alphaMaskRow=self.displayedAtlasRow;
}
- (void)prepareAlphaMask {
    CGImageRef image=self.atlas.CGImage;
    NSInteger physicalRows=self.rowAtlasPaths.count?1:self.rows;
    NSInteger physicalColumns=self.columns;
    if(self.rowAtlasPaths.count && self.loadedAtlasRow>=0 && (NSUInteger)self.loadedAtlasRow<self.rowColumnCounts.count)
        physicalColumns=[self.rowColumnCounts[self.loadedAtlasRow] integerValue];
    self.atlasWidth=image?CGImageGetWidth(image)/MAX(1,physicalColumns):0;
    self.atlasHeight=image?CGImageGetHeight(image)/MAX(1,physicalRows):0;
    self.alphaMask=nil;self.alphaMaskFrame=self.alphaMaskRow=-1;
}
- (void)dealloc { [self.displayLink invalidate]; }
@end
