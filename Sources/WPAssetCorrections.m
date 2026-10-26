#import "WPAssetCorrections.h"
#import "WPCommon.h"
#import <CommonCrypto/CommonDigest.h>

static BOOL WPKnownAtlasBytes(NSString *path,NSString *expected) {
    NSDictionary *attributes=[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
    unsigned long long size=[attributes[NSFileSize] unsignedLongLongValue];
    if(![attributes[NSFileType] isEqual:NSFileTypeRegular] || !size || size>4*1024*1024)return NO;
    // The mapping is rebuilt only at pet reload. There is no image or hash
    // cache to keep alive, and no per-frame/per-action filesystem hashing.
    @autoreleasepool {
        NSData *data=[NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
        if(data.length!=size)return NO;
        unsigned char digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,digest);
        NSMutableString *hash=[NSMutableString stringWithCapacity:64];
        for(NSUInteger i=0;i<sizeof(digest);i++)[hash appendFormat:@"%02x",digest[i]];
        return [hash isEqual:expected];
    }
}

NSDictionary<NSString *,NSString *> *WPKnownAtlasCorrections(NSString *directory,NSDictionary *metadata) {
    if(![directory isKindOfClass:NSString.class] || !directory.length || ![metadata isKindOfClass:NSDictionary.class])return @{};
    id identifier=metadata[@"id"],revision=metadata[@"assetRevision"];
    NSDictionary<NSString *,NSString *> *known=nil;
    BOOL legacy=[identifier isEqual:@"yue-zhour-20261021"] && [revision isEqual:@"1.0.3"] && ([metadata[@"spriteVersionNumber"] isEqual:@4] || ([metadata[@"spriteVersionNumber"] isEqual:@5] && [metadata[@"wpLegacySpriteVersion"] isEqual:@4]));
    if(legacy)known=@{@"spritesheet.png":@"6c80ca328a8ac4b5c5015e4cee47958d3d8764a887b341ffabfd133f8ff2a475"};
    else if([identifier isEqual:@"yue2-zhour-20261022"] && [revision isEqual:@"2.0.0"] && [metadata[@"spriteVersionNumber"] isEqual:@5])
        known=@{@"row-08.png":@"86b548cc1672347e0d5b35538eafb0e3d0cf955278a66b14af4a2067ed2c0058",
                @"row-18.png":@"1b2a38a4ef400be21584916a3fae43d1130c9100366f7918b3e7532ae9b32ba9",
                @"row-20.png":@"d33b033ea07165cbc5aa0bb1deb07b7829a28e771b8464af9150ca417f3544b0",
                @"row-21.png":@"59531c00a8144306b4375defacdb858f2dedea16115e0739a0f551c7c56f35f1"};
    NSMutableDictionary *result=[NSMutableDictionary new];
    for(NSString *name in known){
        NSString *replacement=legacy?[WPDefaultPetDirectory() stringByAppendingPathComponent:@"compact-row-00.png"]:
            [WPResourceBundle().resourcePath stringByAppendingPathComponent:[@"PetCorrections/yue2-" stringByAppendingString:name]];
        NSString *original=[directory stringByAppendingPathComponent:name];
        if(![replacement isEqual:original] && [NSFileManager.defaultManager fileExistsAtPath:replacement] && WPKnownAtlasBytes(original,known[name]))result[name]=replacement;
    }
    return result;
}
