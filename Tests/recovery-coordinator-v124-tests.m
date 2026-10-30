#import <Foundation/Foundation.h>
#import "WPRecovery124Checks.h"
int main(void){@autoreleasepool{
    __block BOOL finished=NO,passed=YES;
    WPRecovery124RunPreviewChecks(^(NSDictionary<NSString *,NSNumber *> *checks){
        for(NSNumber *value in checks.allValues)passed&=value.boolValue;
        NSDictionary *report=@{@"caseCount":@(checks.count),@"allPassed":@(passed),@"results":checks,@"finished":@YES};
        NSData *data=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil];
        [data writeToFile:@"Tests/recovery-coordinator-v124-report.json" atomically:YES];
        puts([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding].UTF8String);finished=YES;
    });
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:12];
    while(!finished && deadline.timeIntervalSinceNow>0)[NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.03]];
    return finished&&passed?0:1;
}}
