#import <Foundation/Foundation.h>
#import "WPCoupleHistory.h"
int main(int argc,const char *argv[]){@autoreleasepool{
    NSURL *root=[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]] isDirectory:YES];[NSFileManager.defaultManager createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:nil];
    NSMutableArray *reports=[NSMutableArray new];NSTimeInterval now=NSDate.date.timeIntervalSince1970;
    for(NSNumber *size in @[@400,@4000,@12000]){@autoreleasepool{
        NSMutableArray *incoming=[NSMutableArray new],*outgoing=[NSMutableArray new];
        for(NSUInteger i=0;i<size.unsignedIntegerValue;i++)[incoming addObject:@{@"id":NSUUID.UUID.UUIDString,@"kind":@"miss",@"sent_at":@(now-3600-i),@"received_at":@(now-3500-i),@"needs_response":@NO,@"animation_played":@YES}];
        for(NSUInteger i=0;i<100;i++)[outgoing addObject:@{@"id":NSUUID.UUID.UUIDString,@"kind":@"miss",@"sent_at":@(now-300-i),@"state":@"waiting",@"resolves":@[incoming[incoming.count-1-i][@"id"]]}];
        NSData *fixture=[NSJSONSerialization dataWithJSONObject:@{@"version":@3,@"incoming":incoming,@"outgoing":outgoing} options:0 error:nil];
        NSURL *file=[root URLByAppendingPathComponent:[size.stringValue stringByAppendingString:@".json"]];[fixture writeToURL:file atomically:YES];
        WPCoupleHistory *history=[[WPCoupleHistory alloc] initWithURL:file];
        NSMutableDictionary *report=history.diagnostics.mutableCopy;report[@"fixtureRows"]=@(size.unsignedIntegerValue+100);[reports addObject:report];
    }}
    NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"environment":@"macOS Foundation fixture; not real WeChat",@"measurements":reports} options:NSJSONWritingPrettyPrinted error:nil];fwrite(data.bytes,1,data.length,stdout);puts("");
}return 0;}
