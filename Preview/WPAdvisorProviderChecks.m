#import <UIKit/UIKit.h>
#import "WPChatAdvisor.h"
#import "WPCommon.h"

static NSMutableArray<NSURLRequest *> *WPAdvisorMockRequests;
static NSData *WPAdvisorMockLastBody;
static NSInteger WPAdvisorMockStatus=200;

@interface WPAdvisorMockURLProtocol : NSURLProtocol
@end
@implementation WPAdvisorMockURLProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    NSString *host=request.URL.host.lowercaseString;
    return [@[@"api.deepseek.com",@"api.siliconflow.cn",@"example.test"] containsObject:host];
}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {return request;}
- (void)startLoading {
    @synchronized (WPAdvisorMockRequests) {[WPAdvisorMockRequests addObject:self.request];}
    if([self.request.HTTPMethod isEqual:@"POST"]){
        WPAdvisorMockLastBody=self.request.HTTPBody;
        NSInputStream *stream=self.request.HTTPBodyStream;
        if(!WPAdvisorMockLastBody && stream){
            NSMutableData *data=[NSMutableData new];uint8_t buffer[4096];
            [stream open];NSInteger n=0;
            while((n=[stream read:buffer maxLength:sizeof(buffer)])>0)[data appendBytes:buffer length:(NSUInteger)n];
            [stream close];WPAdvisorMockLastBody=data;
        }
    }
    BOOL modelRequest=[self.request.HTTPMethod isEqual:@"GET"];
    NSDictionary *reply=WPAdvisorMockStatus==200 ? (modelRequest?@{@"data":@[@{@"id":@"deepseek-flash"},@{@"id":@"deepseek-v4-pro"}]}:
        @{@"choices":@[@{@"message":@{@"content":@"{\"summary\":\"好\",\"replies\":[\"你好\"]}"}}]}) : @{@"error":@{@"message":@"test error"}};
    NSData *data=[NSJSONSerialization dataWithJSONObject:reply options:0 error:nil];
    NSHTTPURLResponse *response=[[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:WPAdvisorMockStatus HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type":@"application/json"}];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:data];[self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end

void WPAdvisorProviderPreviewChecks(void (^completion)(NSDictionary<NSString *,NSNumber *> *)) {
    NSMutableDictionary *r=[NSMutableDictionary new];WPAdvisorMockRequests=[NSMutableArray new];
    NSUserDefaults *prefs=WPPreferences();id savedBase=[prefs objectForKey:@"chatAdvisorBaseURL"],savedModel=[prefs objectForKey:@"chatAdvisorModel"];
    [prefs setObject:@"https://platform.deepseek.com/" forKey:@"chatAdvisorBaseURL"];
    [prefs setObject:@"deepseek-ai/DeepSeek-V3" forKey:@"chatAdvisorModel"];
    r[@"consoleAddressAutoCorrectsOnUpgrade"]=@([WPChatAdvisor.baseURL isEqual:@"https://api.deepseek.com"]);
    r[@"siliconDefaultBecomesDeepSeekFlash"]=@([WPChatAdvisor.model isEqual:@"deepseek-flash"]);
    r[@"platformInputCanonicalized"]=@([WPChatAdvisor setBaseURL:@"https://platform.deepseek.com/"] && [WPChatAdvisor.baseURL isEqual:@"https://api.deepseek.com"]);
    [WPChatAdvisor setModel:@"deepseek-v4-pro"];
    r[@"explicitDeepSeekModelPreserved"]=@([WPChatAdvisor.model isEqual:@"deepseek-v4-pro"]);
    [WPChatAdvisor setBaseURL:@"https://api.siliconflow.cn/v1"];[WPChatAdvisor setModel:@"deepseek-ai/DeepSeek-V3"];
    r[@"siliconFlowModelUnchanged"]=@([WPChatAdvisor.model isEqual:@"deepseek-ai/DeepSeek-V3"]);
    [WPChatAdvisor setBaseURL:@"https://api.deepseek.com.evil.test/v1"];
    r[@"otherHostsNeverRewritten"]=@([WPChatAdvisor.baseURL isEqual:@"https://api.deepseek.com.evil.test/v1"]);
    [WPChatAdvisor setBaseURL:@"https://api.deepseek.com"];[WPChatAdvisor setModel:@""];
    r[@"deepSeekFreshDefault"]=@([WPChatAdvisor.model isEqual:@"deepseek-flash"]);
    r[@"mockKeySaved"]=@([WPChatAdvisor saveAPIKey:@"test-key-only"]);
    void (^finish)(void)=^{
        [WPChatAdvisor clearAPIKey];
        if(savedBase)[prefs setObject:savedBase forKey:@"chatAdvisorBaseURL"];else [prefs removeObjectForKey:@"chatAdvisorBaseURL"];
        if(savedModel)[prefs setObject:savedModel forKey:@"chatAdvisorModel"];else [prefs removeObjectForKey:@"chatAdvisorModel"];
        completion(r);
    };
    [WPChatAdvisor testConnection:^(BOOL ok,NSString *message){
        NSURLRequest *get=WPAdvisorMockRequests.lastObject;
        r[@"deepSeekModelListUsesOfficialPath"]=@(ok && [get.URL.absoluteString isEqual:@"https://api.deepseek.com/models"] && [message containsString:@"额度"]);
        NSArray *lines=@[[WPChatLine lineFromMe:NO speaker:@"test" text:@"你好" date:nil]];
        [WPChatAdvisor analyzeLines:lines group:NO completion:^(WPChatAdvice *advice,NSString *error){
            NSURLRequest *post=WPAdvisorMockRequests.lastObject;
            NSDictionary *body=WPAdvisorMockLastBody.length?[NSJSONSerialization JSONObjectWithData:WPAdvisorMockLastBody options:0 error:nil]:nil;
            r[@"deepSeekCompletionResponseParsed"]=@(advice.replies.count==1 && !error);
            r[@"deepSeekCompletionCorrectURL"]=@([post.URL.absoluteString isEqual:@"https://api.deepseek.com/chat/completions"]);
            r[@"deepSeekCompletionCorrectModel"]=@([body[@"model"] isEqual:@"deepseek-flash"]);
            r[@"deepSeekCompletionThinkingDisabled"]=@([body[@"thinking"][@"type"] isEqual:@"disabled"]);
            WPAdvisorMockStatus=402;
            [WPChatAdvisor analyzeLines:lines group:NO completion:^(WPChatAdvice *bad,NSString *err){
                r[@"deepSeekBalanceErrorExplained"]=@(!bad && [err containsString:@"余额"]);WPAdvisorMockStatus=200;
                [WPChatAdvisor setBaseURL:@"https://api.siliconflow.cn/v1"];
                [WPChatAdvisor fetchModels:^(__unused NSArray *models,NSString *modelError){
                    NSURLRequest *silicon=WPAdvisorMockRequests.lastObject;
                    r[@"siliconFlowFilterPreserved"]=@(!modelError && [silicon.URL.absoluteString isEqual:@"https://api.siliconflow.cn/v1/models?type=text&sub_type=chat"]);
                    [WPChatAdvisor setBaseURL:@"https://example.test/v1"];
                    [WPChatAdvisor fetchModels:^(__unused NSArray *other,NSString *otherError){
                        r[@"genericProviderUsesStandardModelPath"]=@(!otherError && [WPAdvisorMockRequests.lastObject.URL.absoluteString isEqual:@"https://example.test/v1/models"]);
                        finish();
                    }];
                }];
            }];
        }];
    }];
}
