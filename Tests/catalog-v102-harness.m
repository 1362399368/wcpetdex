#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>

static const NSUInteger WPMaximumAssetBytes = 32 * 1024 * 1024;
static NSString *const WPCatalogErrorDomain = @"WePet.Petdex";
static NSError *WPError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:WPCatalogErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey:message}];
}

// The runner inserts the actual scanner and networking implementation from
// Sources/WPPetCatalog.m. This file contains only independent fixtures/checks.
// @ACTUAL_FRAME_COUNTS@
// @ACTUAL_REQUEST_MODEL@

@interface WPPetCatalog : NSObject <NSURLSessionDownloadDelegate>
@property(nonatomic,strong) NSURLSession *session;
@property(nonatomic,strong) NSOperationQueue *requestQueue;
@property(nonatomic,strong) NSMutableDictionary *activeRequests;
@property(nonatomic,strong) NSMutableArray *waitingRequests;
@property(nonatomic,strong) NSMutableArray *pendingLoads;
@end
@implementation WPPetCatalog
// @ACTUAL_REQUEST_METHODS@
@end

// Reference behavior from 0.3.11: scan the alpha byte of an RGBA scratch image.
// Keep this independent implementation when the production scanner changes.
static NSArray<NSNumber *> *WPReferenceFrameCounts(CGImageSourceRef source, NSUInteger width, NSUInteger height) {
    CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    if (!image) return nil;
    void *pixels = calloc(height, width * 4);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = pixels ? CGBitmapContextCreate(pixels, width, height, 8, width * 4, colorSpace,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big) : NULL;
    CGColorSpaceRelease(colorSpace);
    if (!context) { free(pixels);CGImageRelease(image);return nil; }
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
    const unsigned char *bytes = pixels;
    BOOL anyPainted = NO, hasTransparency = NO;
    for (NSUInteger pixel = 0; pixel < width * height; pixel++) {
        if (bytes[pixel * 4 + 3] < 250) { hasTransparency = YES;break; }
    }
    NSMutableArray *counts = [NSMutableArray new];
    for (NSUInteger row = 0; row < height / 208; row++) {
        NSUInteger lastFrame = 0;
        for (NSUInteger frame = 0; frame < 8; frame++) {
            BOOL painted = NO;
            for (NSUInteger y = row * 208; y < (row + 1) * 208 && !painted; y++) {
                for (NSUInteger x = frame * 192; x < (frame + 1) * 192; x++) {
                    if (bytes[(y * width + x) * 4 + 3] > 12) { painted = YES;break; }
                }
            }
            if (painted) { lastFrame = frame + 1;anyPainted = YES; }
        }
        [counts addObject:@(MAX(lastFrame, 1))];
    }
    CGContextRelease(context);free(pixels);CGImageRelease(image);
    return anyPainted && hasTransparency ? counts : nil;
}

static BOOL WPWriteAlphaFixture(NSURL *url, NSString *kind) {
    const NSUInteger width=1536,height=1872;
    unsigned char *pixels=calloc(height,width*4);
    if(!pixels)return NO;
    if([kind isEqual:@"opaque"])for(NSUInteger i=0;i<width*height;i++)pixels[i*4+3]=255;
    if([kind isEqual:@"threshold"])for(NSUInteger row=0;row<9;row++){
        pixels[((row*208+80)*width+2*192+60)*4+3]=13;
        pixels[((row*208+80)*width+7*192+60)*4+3]=12;
    }
    CGColorSpaceRef color=CGColorSpaceCreateDeviceRGB();
    CGContextRef context=CGBitmapContextCreate(pixels,width,height,8,width*4,color,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(color);
    CGImageRef image=context?CGBitmapContextCreateImage(context):NULL;
    CGImageDestinationRef destination=image?CGImageDestinationCreateWithURL((__bridge CFURLRef)url,CFSTR("public.png"),1,NULL):NULL;
    if(destination)CGImageDestinationAddImage(destination,image,NULL);
    BOOL result=destination && CGImageDestinationFinalize(destination);
    if(destination)CFRelease(destination);if(image)CGImageRelease(image);if(context)CGContextRelease(context);free(pixels);
    return result;
}

static NSDictionary *WPAlphaCheck(NSString *path, NSString *name) {
    CGImageSourceRef source=CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path],NULL);
    if(!source)return @{@"name":name,@"passed":@NO};
    NSDictionary *properties=CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source,0,NULL));
    NSUInteger width=[properties[(__bridge NSString *)kCGImagePropertyPixelWidth] unsignedIntegerValue];
    NSUInteger height=[properties[(__bridge NSString *)kCGImagePropertyPixelHeight] unsignedIntegerValue];
    NSArray *reference=WPReferenceFrameCounts(source,width,height),*actual=WPFrameCountsActual(source,width,height);
    BOOL passed=(!reference && !actual) || [reference isEqual:actual];
    if([name isEqual:@"threshold"])passed=passed && actual.count==9 && [[NSSet setWithArray:actual] isEqual:[NSSet setWithObject:@3]];
    if([name isEqual:@"transparent"] || [name isEqual:@"opaque"])passed=passed && actual==nil;
    if([name isEqual:@"bundled"])passed=passed && actual.count==height/208;
    CFRelease(source);
    return @{@"name":name,@"passed":@(passed),@"frameCounts":actual?:NSNull.null,
        @"rgbaScratchBytes":@(width*height*4),@"alphaScratchBytes":@(width*height)};
}

static NSDictionary *WPRunAlphaChecks(NSString *bundled,NSString *temporaryDirectory) {
    NSMutableArray *checks=[NSMutableArray new];[checks addObject:WPAlphaCheck(bundled,@"bundled")];
    for(NSString *kind in @[@"threshold",@"transparent",@"opaque"]){
        NSURL *url=[NSURL fileURLWithPath:[temporaryDirectory stringByAppendingPathComponent:[kind stringByAppendingString:@".png"]]];
        if(!WPWriteAlphaFixture(url,kind)){[checks addObject:@{@"name":kind,@"passed":@NO}];continue;}
        @autoreleasepool{[checks addObject:WPAlphaCheck(url.path,kind)];}
    }
    BOOL allPassed=YES;for(NSDictionary *check in checks)allPassed=allPassed && [check[@"passed"] boolValue];
    return @{@"caseCount":@(checks.count),@"allPassed":@(allPassed),@"checks":checks};
}

static NSDictionary *WPRunNetworkChecks(NSString *port) {
    WPPetCatalog *catalog=[WPPetCatalog new];dispatch_group_t group=dispatch_group_create();
    NSMutableArray *checks=[NSMutableArray new];NSMutableArray *paths=[NSMutableArray new];
    for(NSUInteger i=0;i<8;i++)[paths addObject:[NSString stringWithFormat:@"/valid/%lu",(unsigned long)i]];
    [paths addObjectsFromArray:@[@"/oversize",@"/unknown-length",@"/http500",@"/empty"]];
    for(NSString *path in paths){
        dispatch_group_enter(group);
        NSURL *url=[NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%@%@",port,path]];
        [catalog requestURL:url completion:^(NSData *data,NSError *error){
            BOOL passed;
            if([path hasPrefix:@"/valid/"])passed=data.length==4 && !error && [data isEqual:[@"test" dataUsingEncoding:NSUTF8StringEncoding]];
            else passed=!data && [error.domain isEqual:WPCatalogErrorDomain] && error.code==([path isEqual:@"/http500"]?500:7);
            [checks addObject:@{@"path":path,@"passed":@(passed),@"bytes":@(data.length),@"errorCode":@(error.code)}];
            dispatch_group_leave(group);
        }];
    }
    BOOL timedOut=dispatch_group_wait(group,dispatch_time(DISPATCH_TIME_NOW,30*NSEC_PER_SEC))!=0;
    [catalog.session invalidateAndCancel];
    BOOL allPassed=!timedOut && checks.count==12;
    for(NSDictionary *check in checks)allPassed=allPassed && [check[@"passed"] boolValue];
    return @{@"caseCount":@(checks.count),@"allPassed":@(allPassed),@"timedOut":@(timedOut),@"checks":[checks copy]};
}

int main(int argc,char **argv){@autoreleasepool{
    if(argc!=5)return 2;
    NSDictionary *alpha=WPRunAlphaChecks([NSString stringWithUTF8String:argv[1]],[NSString stringWithUTF8String:argv[2]]);
    NSDictionary *network=WPRunNetworkChecks([NSString stringWithUTF8String:argv[3]]);
    NSDictionary *report=@{@"alpha":alpha,@"network":network};
    NSData *json=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil];
    if(![json writeToFile:[NSString stringWithUTF8String:argv[4]] atomically:YES])return 2;
    return [alpha[@"allPassed"] boolValue] && [network[@"allPassed"] boolValue]?0:1;
}}
