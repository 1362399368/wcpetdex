#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonCryptor.h>
#import <dlfcn.h>
#import <mach-o/getsect.h>
#import <mach-o/loader.h>
#import "WPCommon.h"

// Fixed archive format: 8-byte magic, uint32 count, then entries consisting of
// uint16 name length, uint32 byte length, SHA-256, UTF-8 path, and raw bytes.
// Both lengths and the complete whitelist are validated before any writes.
static uint32_t WPEmbeddedU32(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}
static NSString *WPEmbeddedHex(const uint8_t *bytes, size_t count) {
    NSMutableString *result=[NSMutableString stringWithCapacity:count*2];
    for(size_t i=0;i<count;i++)[result appendFormat:@"%02x",bytes[i]];
    return result;
}
static BOOL WPEmbeddedHashMatches(NSData *data, NSData *expected) {
    if(!data || data.length>4*1024*1024 || expected.length!=CC_SHA256_DIGEST_LENGTH)return NO;
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes,(CC_LONG)data.length,digest);
    return memcmp(digest,expected.bytes,sizeof(digest))==0;
}
static NSSet *WPEmbeddedNames(void) {
    NSMutableSet *names=[NSMutableSet setWithObjects:@"DefaultPet/pet.json",@"petdex-manifest-snapshot.json",nil];
    for(NSUInteger i=0;i<9;i++)[names addObject:[NSString stringWithFormat:@"DefaultPet/lulu-row-%02lu.png",(unsigned long)i]];
    return names;
}
// This is resource obfuscation only: the key is public and embedded in the
// client, so it cannot protect artwork or code from reverse engineering.
static NSData *WPEmbeddedDecrypt(const uint8_t *bytes,size_t size) {
    static const uint8_t magic[8]={'W','P','S','E','N','C','2',0};
    static const uint8_t key[32]={0x5f,0xf8,0x11,0x8c,0x7e,0x0e,0x34,0xc7,0x54,0xc6,0xf1,0x78,0xe0,0xb1,0x87,0x99,0xff,0xea,0xa2,0x12,0x7a,0x0f,0x4f,0x00,0x04,0xbb,0x6d,0xe1,0xa0,0x68,0x59,0x6a};
    if(!bytes || size<40 || size>8*1024*1024+40 || memcmp(bytes,magic,sizeof(magic))!=0)return nil;
    size_t encrypted=size-24;
    if(encrypted%kCCBlockSizeAES128)return nil;
    NSMutableData *plain=[NSMutableData dataWithLength:encrypted];
    if(!plain)return nil;
    size_t written=0;
    CCCryptorStatus status=CCCrypt(kCCDecrypt,kCCAlgorithmAES,kCCOptionPKCS7Padding,key,sizeof(key),bytes+8,
                                   bytes+24,encrypted,plain.mutableBytes,plain.length,&written);
    if(status!=kCCSuccess || written>8*1024*1024)return nil;
    plain.length=written;
    return plain;
}
static NSDictionary<NSString *,NSDictionary *> *WPEmbeddedParse(const uint8_t *bytes, size_t size) {
    static const uint8_t magic[8]={'W','P','S','R','E','S','1',0};
    if(!bytes || size<12 || size>8*1024*1024 || memcmp(bytes,magic,sizeof(magic))!=0 || WPEmbeddedU32(bytes+8)!=11)return nil;
    size_t cursor=12;NSMutableDictionary *entries=[NSMutableDictionary new];NSSet *allowed=WPEmbeddedNames();
    for(NSUInteger i=0;i<11;i++){
        if(size-cursor<38)return nil;
        uint16_t nameLength=(uint16_t)bytes[cursor] | ((uint16_t)bytes[cursor+1]<<8);
        uint32_t length=WPEmbeddedU32(bytes+cursor+2);
        if(!nameLength || nameLength>128 || !length || length>4*1024*1024)return nil;
        NSData *digest=[NSData dataWithBytes:bytes+cursor+6 length:32];cursor+=38;
        if(nameLength>size-cursor)return nil;
        NSString *name=[[NSString alloc] initWithBytes:bytes+cursor length:nameLength encoding:NSUTF8StringEncoding];cursor+=nameLength;
        if(!name || ![allowed containsObject:name] || entries[name] || length>size-cursor)return nil;
        NSData *data=[NSData dataWithBytesNoCopy:(void *)(bytes+cursor) length:length freeWhenDone:NO];cursor+=length;
        if(!WPEmbeddedHashMatches(data,digest))return nil;
        entries[name]=@{@"data":data,@"digest":digest};
    }
    if(cursor!=size || entries.count!=allowed.count)return nil;
    return entries;
}
NSString *WPEmbeddedResourceDirectory(void) {
    static NSString *directory;static dispatch_once_t once;
    dispatch_once(&once, ^{
        Dl_info info;
        if(!dladdr((const void *)&WPEmbeddedResourceDirectory,&info) || !info.dli_fbase)return;
        unsigned long size=0;
#if __LP64__
        const uint8_t *bytes=getsectiondata((const struct mach_header_64 *)info.dli_fbase,"__DATA","__wpresources",&size);
#else
        const uint8_t *bytes=getsectiondata((const struct mach_header *)info.dli_fbase,"__DATA","__wpresources",&size);
#endif
        __attribute__((objc_precise_lifetime)) NSData *plain=WPEmbeddedDecrypt(bytes,size);
        NSDictionary *entries=WPEmbeddedParse(plain.bytes,plain.length);
        if(!entries)return;
        unsigned char digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256(bytes,(CC_LONG)size,digest);
        NSString *root=[[WPDataDirectory() stringByAppendingPathComponent:@"BuiltinResources"] stringByAppendingPathComponent:WPEmbeddedHex(digest,sizeof(digest))];
        NSFileManager *fm=NSFileManager.defaultManager;NSError *error=nil;
        if(![fm createDirectoryAtPath:[root stringByAppendingPathComponent:@"DefaultPet"] withIntermediateDirectories:YES attributes:nil error:&error])return;
        // Regenerate only our own missing/corrupt hash-addressed files. Never
        // change the selected-pet preference or other cached pet libraries.
        for(NSString *name in entries){
            NSString *path=[root stringByAppendingPathComponent:name];NSDictionary *entry=entries[name];
            NSDictionary *attrs=[fm attributesOfItemAtPath:path error:nil];
            NSData *old=([attrs[NSFileType] isEqual:NSFileTypeRegular] && [attrs[NSFileSize] unsignedLongLongValue]<=4*1024*1024)?[NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil]:nil;
            if(WPEmbeddedHashMatches(old,entry[@"digest"]))continue;
            if(attrs && ![attrs[NSFileType] isEqual:NSFileTypeRegular])return;
            if(![entry[@"data"] writeToFile:path options:NSDataWritingAtomic error:&error])return;
        }
        directory=[root copy];
    });
    return directory;
}
