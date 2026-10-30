#import "WPAvatarBudgetChecks.h"
#import "WPChatAvatarDownload.h"
#import <UIKit/UIKit.h>

// Delegate fixtures never create a URLSession or task. Those arguments are
// deliberately nil because the bounded adapter does not inspect them.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
static NSURLSessionResponseDisposition WPABResponse(WPQCAvatarDownload *download,NSInteger length){
    __block NSURLSessionResponseDisposition disposition=NSURLSessionResponseBecomeDownload;
    NSURLResponse *response=[[NSURLResponse alloc] initWithURL:[NSURL URLWithString:@"https://example.invalid/avatar"] MIMEType:@"image/png" expectedContentLength:length textEncodingName:nil];
    [(id<NSURLSessionDataDelegate>)download URLSession:nil dataTask:nil didReceiveResponse:response completionHandler:^(NSURLSessionResponseDisposition value){disposition=value;}];
    return disposition;
}
static void WPABFeed(WPQCAvatarDownload *download,NSData *data){[(id<NSURLSessionDataDelegate>)download URLSession:nil dataTask:nil didReceiveData:data];}
static void WPABComplete(WPQCAvatarDownload *download){[(id<NSURLSessionTaskDelegate>)download URLSession:nil task:nil didCompleteWithError:nil];}
#pragma clang diagnostic pop
void WPAvatarBudgetRunPreviewChecks(void (^completion)(NSDictionary<NSString *,NSNumber *> *)){
    NSMutableDictionary *r=[NSMutableDictionary new];NSURL *url=[NSURL URLWithString:@"https://example.invalid/avatar"];
    __block NSUInteger calls=0;__block BOOL main=NO;
    WPQCAvatarDownload *header=[[WPQCAvatarDownload alloc] initWithURL:url maximumBytes:32 maximumPixels:96 completion:^(UIImage *image){calls++;main=NSThread.isMainThread;}];
    r[@"AB01_rejectsOversizedHeaderBeforeAllocatingBody"]=@(WPABResponse(header,33)==NSURLSessionResponseCancel && [header valueForKey:@"bytes"]==nil);
    WPABComplete(header);
    __block NSUInteger streamCalls=0;
    WPQCAvatarDownload *stream=[[WPQCAvatarDownload alloc] initWithURL:url maximumBytes:32 maximumPixels:96 completion:^(__unused UIImage *image){streamCalls++;}];
    r[@"AB03_unknownLengthMayStreamWithinBudget"]=@(WPABResponse(stream,-1)==NSURLSessionResponseAllow);
    WPABFeed(stream,[NSMutableData dataWithLength:24]);WPABFeed(stream,[NSMutableData dataWithLength:9]);
    r[@"AB04_streamCrossingCapReleasesBufferSynchronously"]=@([stream valueForKey:@"bytes"]==nil);
    WPABFeed(stream,[NSMutableData dataWithLength:1]);WPABComplete(stream);

    __block NSUInteger cancelledCalls=0;
    WPQCAvatarDownload *cancelled=[[WPQCAvatarDownload alloc] initWithURL:url maximumBytes:32 maximumPixels:96 completion:^(__unused UIImage *image){cancelledCalls++;}];
    WPABResponse(cancelled,33);[cancelled cancel];
    WPQCAvatarDownload *buffered=[[WPQCAvatarDownload alloc] initWithURL:url maximumBytes:32 maximumPixels:96 completion:^(__unused UIImage *image){}];
    WPABResponse(buffered,-1);WPABFeed(buffered,[NSMutableData dataWithLength:24]);[buffered cancel];
    r[@"AB07_cancelDropsTransferAndQueuedDecodeInput"]=@([buffered valueForKey:@"bytes"]==nil && [buffered valueForKey:@"decodeData"]==nil);
    UIImage *fixture=[[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(200,200)] imageWithActions:^(__unused UIGraphicsImageRendererContext *context){[UIColor.systemBlueColor setFill];UIRectFill(CGRectMake(0,0,200,200));}];
    NSData *png=UIImagePNGRepresentation(fixture);
    __block UIImage *small=nil;__block BOOL smallDone=NO;
    WPQCAvatarDownload *bounded=[[WPQCAvatarDownload alloc] initWithURL:url maximumBytes:1024*1024 maximumPixels:96 completion:^(UIImage *image){small=image;smallDone=YES;}];
    WPABResponse(bounded,png.length);WPABFeed(bounded,png);WPABComplete(bounded);
    __block UIImage *legacy=nil;__block BOOL legacyDone=NO;
    WPQCAvatarDownload *original=[[WPQCAvatarDownload alloc] initWithURL:url completion:^(UIImage *image){legacy=image;legacyDone=YES;}];
    WPABResponse(original,png.length);WPABFeed(original,png);WPABComplete(original);
    WPQCAvatarDownload *invalid=[[WPQCAvatarDownload alloc] initWithURL:url maximumBytes:0 maximumPixels:NAN completion:^(__unused UIImage *image){}];
    r[@"AB10_invalidBudgetsUseSafeDefaults"]=@([[invalid valueForKey:@"maximumBytes"] unsignedIntegerValue]==5*1024*1024 && [[invalid valueForKey:@"maximumPixels"] unsignedIntegerValue]==160);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{
    r[@"AB02_failureCompletesExactlyOnceOnMain"]=@(calls==1 && main);
    r[@"AB05_streamOverflowDoesNotDeliverTwice"]=@(streamCalls==1);
    r[@"AB06_cancelSuppressesAlreadyScheduledCompletion"]=@(cancelledCalls==0 && [cancelled valueForKey:@"completion"]==nil);
    r[@"AB08_barrageDecodesAtMost96Pixels"]=@(smallDone && small.CGImage && CGImageGetWidth(small.CGImage)<=96 && CGImageGetHeight(small.CGImage)<=96);
    r[@"AB09_existingDefaultStillDecodes160Pixels"]=@(legacyDone && legacy.CGImage && CGImageGetWidth(legacy.CGImage)==160);
        [header cancel];[stream cancel];[original cancel];[bounded cancel];[invalid cancel];
        completion(r);
    });
}
