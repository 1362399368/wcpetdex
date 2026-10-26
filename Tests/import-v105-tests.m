#import <Foundation/Foundation.h>
#import "WPPetImporter.h"
#import "WPZipArchive.h"

static NSDictionary *ReadJSON(NSURL *url){
    NSData *data=[NSData dataWithContentsOfURL:url];
    id value=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
    return [value isKindOfClass:NSDictionary.class]?value:nil;
}
static BOOL ImportCase(NSURL *archive,NSURL *root,BOOL valid,NSMutableDictionary *details){
    __block BOOL done=NO,passed=NO;
    [WPPetImporter importZipAtURL:archive destinationRoot:root completion:^(NSURL *directory,NSError *error){
        if(valid){
            NSDictionary *local=directory?ReadJSON([directory URLByAppendingPathComponent:@"pet.json"]):nil;
            NSDictionary *upstream=directory?ReadJSON([directory URLByAppendingPathComponent:@"upstream-pet.json"]):nil;
            NSDictionary *raw=WPReadPetZip([NSData dataWithContentsOfURL:archive],nil);
            NSString *metaPath=nil;
            for(NSString *name in raw)if([name.lastPathComponent isEqual:@"pet.json"]){metaPath=name;break;}
            NSData *upstreamBytes=directory?[NSData dataWithContentsOfURL:[directory URLByAppendingPathComponent:@"upstream-pet.json"]]:nil;
            BOOL filesSaved=local && [local[@"rowAtlasPaths"] count]==29;
            for(NSString *name in local[@"rowAtlasPaths"]){
                NSString *source=metaPath.stringByDeletingLastPathComponent.length?[metaPath.stringByDeletingLastPathComponent stringByAppendingPathComponent:name]:name;
                NSData *written=[NSData dataWithContentsOfURL:[directory URLByAppendingPathComponent:name]];
                filesSaved&=[written isEqualToData:raw[source]];
            }
            NSUInteger total=0;for(NSNumber *count in local[@"frameCounts"])total+=count.unsignedIntegerValue;
            passed=directory && !error && [local[@"spriteVersionNumber"] integerValue]==5 && [local[@"columns"] integerValue]==20 &&
                [local[@"rows"] integerValue]==29 && [local[@"frameRate"] integerValue]==30 && total==572 &&
                [local[@"source"] isEqual:@"local-import"] && filesSaved &&
                [upstreamBytes isEqualToData:raw[metaPath]] && [local[@"semanticRows"] isEqual:upstream[@"semanticRows"]] &&
                [local[@"passiveAnimations"] isEqual:upstream[@"passiveAnimations"]] && NSThread.isMainThread;
            details[@"savedAll29Rows"]=@(filesSaved);details[@"frameTotal"]=@(total);
            details[@"preservedUpstreamBytes"]=@([upstreamBytes isEqualToData:raw[metaPath]]);
        } else passed=!directory && error!=nil && NSThread.isMainThread;
        details[@"error"]=error.localizedDescription?:NSNull.null;
        if(directory)[NSFileManager.defaultManager removeItemAtURL:directory error:nil];
        done=YES;
    }];
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:30];
    while(!done && deadline.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    NSArray *leftovers=[NSFileManager.defaultManager contentsOfDirectoryAtURL:root includingPropertiesForKeys:nil options:0 error:nil];
    details[@"leftNoPartialDirectory"]=@(leftovers.count==0);
    return done && passed && leftovers.count==0;
}

int main(int argc,char **argv){@autoreleasepool{
    if(argc<2)return 2;
    NSURL *base=[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]] isDirectory:YES];
    NSDictionary *manifest=ReadJSON([base URLByAppendingPathComponent:@"manifest.json"]);
    NSURL *root=[base URLByAppendingPathComponent:@"imported-v5-tests" isDirectory:YES];
    [NSFileManager.defaultManager removeItemAtURL:root error:nil];
    NSMutableDictionary *results=[NSMutableDictionary new],*measurements=[NSMutableDictionary new];
    for(NSString *name in [manifest.allKeys sortedArrayUsingSelector:@selector(compare:)]){
        NSMutableDictionary *detail=[NSMutableDictionary new];
        results[name]=@(ImportCase([base URLByAppendingPathComponent:name],root,[manifest[name] boolValue],detail));
        measurements[name]=detail;
    }
    if(argc>2){
        NSString *path=[NSString stringWithUTF8String:argv[2]];NSMutableDictionary *detail=[NSMutableDictionary new];
        results[@"real-yue2-package.zip"]=@(ImportCase([NSURL fileURLWithPath:path],root,YES,detail));
        measurements[@"real-yue2-package.zip"]=detail;
    }
    BOOL all=manifest.count>0;for(NSNumber *value in results.allValues)all&=value.boolValue;
    NSDictionary *report=@{@"allPassed":@(all),@"caseCount":@(results.count),@"results":results,@"measurements":measurements,
                           @"scope":@"Foundation/ImageIO local import; no WeChat or phone"};
    puts([[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil] encoding:NSUTF8StringEncoding].UTF8String);
    [NSFileManager.defaultManager removeItemAtURL:root error:nil];
    return all?0:1;
}}
