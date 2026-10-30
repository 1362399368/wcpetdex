#import <Foundation/Foundation.h>
#import "WPZipArchive.h"

int main(int argc,const char *argv[]){@autoreleasepool{
    if(argc!=2)return 2;
    NSURL *root=[NSURL fileURLWithPath:@(argv[1]) isDirectory:YES];NSFileManager *manager=NSFileManager.defaultManager;
    NSArray *cases=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:[root URLByAppendingPathComponent:@"cases.json"]] options:0 error:nil];
    NSUInteger failed=0,passed=0;
    for(NSDictionary *test in cases){@autoreleasepool{
        NSString *name=test[@"name"];NSData *archive=[NSData dataWithContentsOfURL:[root URLByAppendingPathComponent:[name stringByAppendingString:@".zip"]] options:NSDataReadingMappedIfSafe error:nil];NSError *error=nil;
        NSDictionary *memory=WPReadPetZip(archive,&error);
        BOOL legacy=(memory!=nil)==[test[@"legacy"] boolValue] && (memory || error);
        NSURL *staging=[root URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];error=nil;
        NSDictionary *disk=WPExtractPetZip(archive,staging,&error);
        BOOL extracted=(disk!=nil)==[test[@"valid"] boolValue] && (disk || error);
        BOOL content=YES;
        if(disk){
            for(NSString *file in disk){NSData *value=[NSData dataWithContentsOfURL:disk[file] options:NSDataReadingMappedIfSafe error:nil];content&=[value isEqual:memory[file]];}
            // An existing staging location must be rejected without deleting it.
            NSData *sentinel=[@"untouched" dataUsingEncoding:NSUTF8StringEncoding];NSURL *marker=[staging URLByAppendingPathComponent:@"sentinel"];
            [sentinel writeToURL:marker atomically:YES];error=nil;
            content&=WPExtractPetZip(archive,staging,&error)==nil && error!=nil && [[NSData dataWithContentsOfURL:marker] isEqual:sentinel];
        }else content=![manager fileExistsAtPath:staging.path];
        BOOL ok=legacy && extracted && content;if(ok)passed++;else failed++;
        printf("%s %s (legacy=%d extract=%d contents/cleanup=%d)\n",ok?"PASS":"FAIL",name.UTF8String,legacy,extracted,content);
        [manager removeItemAtURL:staging error:nil];
    }}
    printf("%lu passed; %lu failed\n",(unsigned long)passed,(unsigned long)failed);return failed?1:0;
}}
