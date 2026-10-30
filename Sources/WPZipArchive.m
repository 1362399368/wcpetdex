#import "WPZipArchive.h"
#import <zlib.h>
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>
#import <sys/stat.h>

static NSError *WPZipError(NSString *message){return [NSError errorWithDomain:@"WeChatPet.Import" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];}
static uint16_t WP16(const uint8_t *p){return (uint16_t)p[0]|((uint16_t)p[1]<<8);}
static uint32_t WP32(const uint8_t *p){return (uint32_t)p[0]|((uint32_t)p[1]<<8)|((uint32_t)p[2]<<16)|((uint32_t)p[3]<<24);}
static BOOL WPRange(NSUInteger offset,NSUInteger length,NSUInteger size){return offset<=size && length<=size-offset;}

// Validate all names and bounds before creating a file. Both APIs share the
// same checks, including archives which use a trailing data descriptor.
static NSArray<NSDictionary *> *WPZipEntries(NSData *data,NSError **error){
    NSString *failure=nil;NSMutableArray *files=[NSMutableArray new];NSMutableSet *names=[NSMutableSet new];
    const uint8_t *p=data.bytes;NSUInteger size=data.length;
    if(size<22 || size>32*1024*1024){failure=@"桌宠 ZIP 需要在 32 MB 以内，且文件完整。";goto failed;}
    NSUInteger end=NSNotFound;
    for(NSInteger pos=(NSInteger)size-22;pos>=MAX(0,(NSInteger)size-65557);pos--){
        if(WP32(p+pos)==0x06054b50 && (NSUInteger)pos+22+WP16(p+pos+20)==size){end=(NSUInteger)pos;break;}
    }
    if(end==NSNotFound){failure=@"无法读取 ZIP 目录，请使用标准 ZIP 格式重新打包。";goto failed;}
    if(WP16(p+end+4) || WP16(p+end+6) || WP16(p+end+8)!=WP16(p+end+10)){failure=@"不支持分卷 ZIP。";goto failed;}
    NSUInteger entries=WP16(p+end+10),centralSize=WP32(p+end+12),offset=WP32(p+end+16),total=0,central=offset;
    if(!entries || entries>64 || !WPRange(offset,centralSize,end) || offset+centralSize!=end){failure=@"ZIP 目录不受支持，最多允许 64 个文件或文件夹。";goto failed;}
    for(NSUInteger i=0;i<entries;i++){
        if(!WPRange(offset,46,end) || WP32(p+offset)!=0x02014b50){failure=@"ZIP 文件目录损坏。";goto failed;}
        uint16_t flags=WP16(p+offset+8),method=WP16(p+offset+10),nameLength=WP16(p+offset+28),extra=WP16(p+offset+30),comment=WP16(p+offset+32);
        uint32_t expectedCRC=WP32(p+offset+16),compressed=WP32(p+offset+20),uncompressed=WP32(p+offset+24),attributes=WP32(p+offset+38),local=WP32(p+offset+42);
        NSUInteger entryLength=46+(NSUInteger)nameLength+extra+comment;
        if((flags&(1|0x40|0x2000)) || (method!=0 && method!=8) || WP16(p+offset+34) || compressed==UINT32_MAX || uncompressed==UINT32_MAX || local==UINT32_MAX){failure=@"仅支持未加密、非 ZIP64 的普通 ZIP（存储或 Deflate 压缩）。";goto failed;}
        if(!WPRange(offset,entryLength,end) || !nameLength || uncompressed>32*1024*1024 || total>64*1024*1024-uncompressed){failure=@"ZIP 文件过大或目录损坏。";goto failed;}
        NSString *name=[[NSString alloc] initWithBytes:p+offset+46 length:nameLength encoding:NSUTF8StringEncoding];
        if(!name || [name hasPrefix:@"/"] || [name containsString:@"\\"] || [name containsString:@"\0"] || ((attributes>>16)&0170000)==0120000){failure=@"桌宠包包含无效路径或符号链接。";goto failed;}
        BOOL directory=[name hasSuffix:@"/"];NSString *canonical=directory?[name substringToIndex:name.length-1]:name;
        for(NSString *component in [canonical componentsSeparatedByString:@"/"])if(!component.length || [component isEqual:@".."] || [component isEqual:@"."] || [component isEqual:@"~"]){failure=@"桌宠包不能包含上级目录或歧义路径。";goto failed;}
        if([names containsObject:canonical]){failure=@"桌宠包包含重复文件名。";goto failed;}[names addObject:canonical];
        offset+=entryLength;total+=uncompressed;
        if(!WPRange(local,30,central) || WP32(p+local)!=0x04034b50 || WP16(p+local+8)!=method || WP16(p+local+6)!=flags){failure=@"ZIP 文件头不匹配。";goto failed;}
        NSUInteger localName=WP16(p+local+26),localExtra=WP16(p+local+28),body=(NSUInteger)local+30+localName+localExtra;
        if(!WPRange(local+30,localName,central) || localName!=nameLength || memcmp(p+local+30,[name dataUsingEncoding:NSUTF8StringEncoding].bytes,localName) || !WPRange(body,compressed,central)){failure=@"ZIP 文件范围不正确。";goto failed;}
        if(!(flags&8) && (WP32(p+local+14)!=expectedCRC || WP32(p+local+18)!=compressed || WP32(p+local+22)!=uncompressed)){failure=@"ZIP 文件长度或校验头不匹配。";goto failed;}
        if(directory){if(uncompressed){failure=@"ZIP 文件夹含有无效内容。";goto failed;}continue;}
        if([name hasPrefix:@"__MACOSX/"] || [name.lastPathComponent isEqualToString:@".DS_Store"])continue;
        [files addObject:@{@"name":name,@"body":@(body),@"compressed":@(compressed),@"size":@(uncompressed),@"method":@(method),@"crc":@(expectedCRC)}];
    }
    if(offset!=end){failure=@"ZIP 目录长度不匹配。";goto failed;}
    return files;
failed:
    if(error)*error=WPZipError(failure ?: @"桌宠 ZIP 读取失败。");return nil;
}

// Output is always bounded to a 64 KiB scratch buffer. No whole entry is
// allocated by the disk extractor, even for the largest supported atlas.
static BOOL WPInflatePetEntry(NSData *data,NSDictionary *entry,BOOL(^sink)(const void *,NSUInteger),NSError **error){
    const uint8_t *input=(const uint8_t *)data.bytes+[entry[@"body"] unsignedIntegerValue];
    NSUInteger compressed=[entry[@"compressed"] unsignedIntegerValue],expected=[entry[@"size"] unsignedIntegerValue],written=0;
    uLong crc=crc32(0,NULL,0);NSString *failure=nil;
    if([entry[@"method"] unsignedIntegerValue]==0){
        if(compressed!=expected)failure=@"ZIP 存储长度不匹配。";
        while(!failure && written<expected){NSUInteger length=MIN((NSUInteger)65536,expected-written);crc=crc32(crc,input+written,(uInt)length);if(!sink(input+written,length))failure=@"无法写入桌宠临时文件，请检查可用存储空间。";written+=length;}
    }else{
        z_stream stream={0};uint8_t output[65536];stream.next_in=(Bytef *)input;stream.avail_in=(uInt)compressed;
        if(inflateInit2(&stream,-MAX_WBITS)!=Z_OK)failure=@"无法初始化 ZIP 解压。";
        else{
            int status=Z_OK;
            while(status==Z_OK){
                stream.next_out=output;stream.avail_out=sizeof(output);status=inflate(&stream,Z_NO_FLUSH);
                NSUInteger length=sizeof(output)-stream.avail_out;
                if(length>expected-written){failure=@"ZIP 解压长度超出声明范围。";break;}
                if(length){crc=crc32(crc,output,(uInt)length);if(!sink(output,length)){failure=@"无法写入桌宠临时文件，请检查可用存储空间。";break;}written+=length;}
            }
            if(!failure && (status!=Z_STREAM_END || written!=expected || stream.total_in!=compressed))failure=@"ZIP 压缩数据不完整。";
            inflateEnd(&stream);
        }
    }
    if(!failure && (uint32_t)crc!=[entry[@"crc"] unsignedIntValue])failure=@"ZIP 校验未通过，请重新下载或打包。";
    if(failure && error)*error=WPZipError(failure);return failure==nil;
}

NSDictionary<NSString *,NSData *> *WPReadPetZip(NSData *data,NSError **error){
    NSArray *entries=WPZipEntries(data,error);if(!entries)return nil;
    NSMutableDictionary *files=[NSMutableDictionary new];
    for(NSDictionary *entry in entries){
        NSMutableData *content=[NSMutableData dataWithCapacity:[entry[@"size"] unsignedIntegerValue]];
        if(!WPInflatePetEntry(data,entry,^BOOL(const void *bytes,NSUInteger length){[content appendBytes:bytes length:length];return YES;},error))return nil;
        files[entry[@"name"]]=content;
    }
    return files;
}

NSDictionary<NSString *,NSURL *> *WPExtractPetZip(NSData *data,NSURL *destination,NSError **error){
    NSArray *entries=WPZipEntries(data,error);if(!entries)return nil;
    NSFileManager *manager=NSFileManager.defaultManager;
    // Never remove or reuse a pre-existing destination, even on failure.
    if(!destination.isFileURL || mkdir(destination.fileSystemRepresentation,0700)!=0){
        if(error)*error=WPZipError(@"桌宠临时目录已存在或不可创建。");return nil;
    }
    NSMutableDictionary *files=[NSMutableDictionary new];BOOL success=YES;NSError *failure=nil;
    for(NSDictionary *entry in entries){@autoreleasepool{
        NSURL *file=[destination URLByAppendingPathComponent:entry[@"name"]];
        if(![manager createDirectoryAtURL:file.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&failure]){success=NO;break;}
        int descriptor=open(file.fileSystemRepresentation,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0600);
        if(descriptor<0){failure=WPZipError(@"无法创建桌宠临时文件。 ");success=NO;break;}
        success=WPInflatePetEntry(data,entry,^BOOL(const void *bytes,NSUInteger length){
            const uint8_t *cursor=bytes;
            while(length){ssize_t count=write(descriptor,cursor,length);if(count<0 && errno==EINTR)continue;if(count<=0)return NO;cursor+=count;length-=(NSUInteger)count;}
            return YES;
        },&failure);
        if(close(descriptor)!=0 && success){failure=WPZipError(@"无法完成桌宠临时文件写入。 ");success=NO;}
        if(!success)break;files[entry[@"name"]]=file;
    }}
    if(!success){[manager removeItemAtURL:destination error:nil];if(error)*error=failure;return nil;}
    return files;
}
