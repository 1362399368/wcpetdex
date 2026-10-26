#import <Foundation/Foundation.h>
#import "WPBackendConfiguration.h"

NSBundle *WPResourceBundle(void) { return NSBundle.mainBundle; }

static NSMutableDictionary<NSString *, NSNumber *> *results;
static void Check(NSString *name, BOOL value) {
    results[name] = @(value);
    if (!value) fprintf(stderr, "FAIL: %s\n", name.UTF8String);
}

int main(void) {
    @autoreleasepool {
        results = [NSMutableDictionary new];
        NSString *production = WPDefaultCoupleURLString();
        NSString *oldWorker = @"wss://old.example.net/v1/ws";
        NSString *custom = @"wss://sync.example.cn/v1/ws";
        Check(@"productionLoadsFromBundle", [WPDefaultCoupleURLString() isEqualToString:production]);
        Check(@"unknownWorkerURLPreserved", [WPMigratedCoupleURLString(oldWorker) isEqualToString:oldWorker]);
        Check(@"customURLPreserved", [WPMigratedCoupleURLString(custom) isEqualToString:custom]);
        Check(@"newInstallGetsDefault", [WPMigratedCoupleURLString(nil) isEqualToString:production]);
        Check(@"validWSS", WPIsValidCoupleURL([NSURL URLWithString:production]));
        Check(@"insecureWSRejected", !WPIsValidCoupleURL([NSURL URLWithString:@"ws://sync.example.cn/v1/ws"]));
        Check(@"wrongPathRejected", !WPIsValidCoupleURL([NSURL URLWithString:@"wss://sync.example.cn/other"]));
        Check(@"queryTokenRejected", !WPIsValidCoupleURL([NSURL URLWithString:@"wss://sync.example.cn/v1/ws?token=secret"]));
        Check(@"userinfoRejected", !WPIsValidCoupleURL([NSURL URLWithString:@"wss://user:pass@sync.example.cn/v1/ws"]));
        Check(@"healthUsesSameHostAndTLS", [[WPCoupleHealthURL([NSURL URLWithString:production]) absoluteString] isEqualToString:@"https://example.invalid/health"]);
        Check(@"timeoutFromConfig", WPCoupleConnectTimeout() == 20);
        Check(@"dnsFailureExplained", [WPCoupleConnectionFailureMessage([NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCannotFindHost userInfo:nil], 0) containsString:@"解析"]);
        Check(@"timeoutExplained", [WPCoupleConnectionFailureMessage([NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil], 0) containsString:@"超时"]);
        Check(@"authRejectionExplained", [WPCoupleConnectionFailureMessage(nil, 401) containsString:@"令牌"]);
        Check(@"websocketUpgradeExplained", [WPCoupleConnectionFailureMessage(nil, 426) containsString:@"WebSocket"]);
        Check(@"serverFailureExplained", [WPCoupleConnectionFailureMessage(nil, 503) containsString:@"后端"]);
        NSString *tokenA = @"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
        NSString *tokenB = @"BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB";
        Check(@"endpointChangePreservesPendingEvenWithLegacyDigest", !WPCoupleTokenChangeRequiresExpiry(tokenA, @"legacy-URL-plus-token-digest", tokenA, 3));
        Check(@"newTokenRetiresOldPairPending", WPCoupleTokenChangeRequiresExpiry(tokenA, @"legacy-URL-plus-token-digest", tokenB, 3));
        Check(@"v2DigestRecoversWithoutKeychain", !WPCoupleTokenChangeRequiresExpiry(nil, WPTokenIdentityDigest(tokenA), tokenA, 3));
        Check(@"unknownPairWithPendingFailsSafe", WPCoupleTokenChangeRequiresExpiry(nil, nil, tokenA, 3));
        Check(@"newPairWithNoPendingAccepted", !WPCoupleTokenChangeRequiresExpiry(nil, nil, tokenA, 0));
        BOOL allPassed = YES;
        for (NSNumber *value in results.allValues) if (!value.boolValue) allPassed = NO;
        NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"caseCount":@(results.count), @"allPassed":@(allPassed), @"checks":results} options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:NULL];
        fwrite(data.bytes, 1, data.length, stdout);
        fputc('\n', stdout);
        return allPassed ? 0 : 1;
    }
}
