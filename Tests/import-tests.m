#import <Foundation/Foundation.h>
#import "WPZipArchive.h"
#import "WPPetImporter.h"
int main(int argc,char **argv){@autoreleasepool{
    NSString *base=[NSString stringWithUTF8String:argv[1]];NSMutableDictionary *report=[NSMutableDictionary new];
    for(NSString *file in @[@"valid-deflate.zip",@"valid-stored.zip",@"v3-valid.zip",@"traversal.zip",@"duplicate.zip",@"symlink.zip",@"bad-crc.zip",@"truncated.zip"]){
        NSError *error=nil;NSDictionary *files=WPReadPetZip([NSData dataWithContentsOfFile:[base stringByAppendingPathComponent:file]],&error);
        BOOL valid=[file hasPrefix:@"valid-"] || [file isEqual:@"v3-valid.zip"];report[file]=@((files!=nil)==valid && (valid?files.count==2:error!=nil));
    }
    NSURL *destination=[NSURL fileURLWithPath:[base stringByAppendingPathComponent:@"imported"] isDirectory:YES];
    for(NSString *file in @[@"valid-deflate.zip",@"v3-valid.zip",@"missing.zip",@"invalid-json.zip"]){
        __block BOOL done=NO;__block BOOL pass=NO;
        [WPPetImporter importZipAtURL:[NSURL fileURLWithPath:[base stringByAppendingPathComponent:file]] destinationRoot:destination completion:^(NSURL *directory,NSError *error){
            if([file hasPrefix:@"valid-"] || [file isEqual:@"v3-valid.zip"]){NSData *data=[NSData dataWithContentsOfURL:[directory URLByAppendingPathComponent:@"pet.json"]];NSDictionary *metadata=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
                if([file isEqual:@"v3-valid.zip"])pass=directory && !error && [metadata[@"rows"] integerValue]==29 && [metadata[@"semanticRows"][@"retract"] integerValue]==28;
                else pass=directory && !error && [metadata[@"frameCounts"][0] integerValue]==7 && [metadata[@"rows"] integerValue]==11;
            }
            else pass=!directory && error!=nil;
            done=YES;
        }];
        NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:10];while(!done && deadline.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
        report[[@"import-" stringByAppendingString:file]]=@(done && pass);
    }
    if(argc>2){
        NSString *realPath=[NSString stringWithUTF8String:argv[2]];
        __block BOOL done=NO;__block BOOL pass=NO;
        [WPPetImporter importZipAtURL:[NSURL fileURLWithPath:realPath] destinationRoot:destination completion:^(NSURL *directory,NSError *error){
            NSData *data=directory?[NSData dataWithContentsOfURL:[directory URLByAppendingPathComponent:@"pet.json"]]:nil;
            NSDictionary *metadata=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
            NSArray *frameCounts=[metadata[@"frameCounts"] isKindOfClass:NSArray.class]?metadata[@"frameCounts"]:nil;
            BOOL expectedFrames=frameCounts.count==29;
            if(expectedFrames)for(NSUInteger row=0;row<frameCounts.count;row++)
                expectedFrames &= [frameCounts[row] integerValue]==((row==9 || row==10)?8:10);
            NSDictionary *semantic=[metadata[@"semanticRows"] isKindOfClass:NSDictionary.class]?metadata[@"semanticRows"]:nil;
            pass=directory && !error && [metadata[@"spriteVersionNumber"] integerValue]==4 &&
                [metadata[@"columns"] integerValue]==10 && [metadata[@"rows"] integerValue]==29 &&
                expectedFrames && semantic.count==19 && [semantic[@"angerIdle"] integerValue]==20 &&
                [semantic[@"peekLeft"] integerValue]==25 && [semantic[@"peekRight"] integerValue]==26;
            done=YES;
        }];
        NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:20];while(!done && deadline.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
        report[@"import-v4-real-package.zip"]=@(done && pass);
    }
    BOOL all=YES;for(NSNumber *value in report.allValues)all&=value.boolValue;
    report[@"allPassed"]=@(all);NSData *json=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil];puts([[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding].UTF8String);
    [NSFileManager.defaultManager removeItemAtURL:destination error:nil];return all?0:1;
}}
