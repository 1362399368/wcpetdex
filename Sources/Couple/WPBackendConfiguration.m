#import "WPBackendConfiguration.h"
#import <CommonCrypto/CommonDigest.h>
FOUNDATION_EXPORT NSBundle *WPResourceBundle(void);

NSString *WPTokenIdentityDigest(NSString *token) {
    NSData *data = [[NSString stringWithFormat:@"pair-token-v2\n%@", token ?: @""] dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *result = [@"v2:" mutableCopy];
    for (NSUInteger index = 0; index < sizeof(digest); index++) [result appendFormat:@"%02x", digest[index]];
    return result;
}
BOOL WPCoupleTokenChangeRequiresExpiry(NSString *currentToken, NSString *savedDigest, NSString *nextToken, NSUInteger pendingCount) {
    // An old digest included the URL. When Keychain still has the token, the
    // token itself is authoritative and endpoint changes preserve the queue.
    if (currentToken.length) return ![currentToken isEqualToString:nextToken];
    if (savedDigest.length) return ![savedDigest isEqualToString:WPTokenIdentityDigest(nextToken)];
    return pendingCount > 0;
}

NSDictionary *WPBackendConfiguration(void) {
    static NSDictionary *configuration; static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURL *file = [WPResourceBundle() URLForResource:@"BackendConfig" withExtension:@"json"];
        NSData *data = file ? [NSData dataWithContentsOfURL:file] : nil;
        id value = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        configuration = [value isKindOfClass:NSDictionary.class] && [value[@"schemaVersion"] integerValue] == 1 ? value : @{};
    });
    return configuration;
}
BOOL WPIsValidCoupleURL(NSURL *url) {
    if (!url || !url.host.length || url.user.length || url.password.length || url.query.length || url.fragment.length || ![url.path isEqualToString:@"/v1/ws"]) return NO;
    if ([url.scheme.lowercaseString isEqualToString:@"wss"]) return YES;
#ifdef WP_PREVIEW_HOST
    return [url.scheme.lowercaseString isEqualToString:@"ws"] && [@[@"localhost", @"127.0.0.1", @"::1", @"[::1]"] containsObject:url.host.lowercaseString];
#else
    return NO;
#endif
}
NSString *WPDefaultCoupleURLString(void) {
    NSDictionary *config = WPBackendConfiguration();
    NSString *environment = [config[@"environment"] isKindOfClass:NSString.class] ? config[@"environment"] : @"production";
#ifndef WP_PREVIEW_HOST
    environment = @"production";
#endif
    NSDictionary *endpoints = [config[@"endpoints"] isKindOfClass:NSDictionary.class] ? config[@"endpoints"] : @{};
    NSString *value = [endpoints[environment] isKindOfClass:NSString.class] ? endpoints[environment] : @"";
    return WPIsValidCoupleURL([NSURL URLWithString:value]) ? value : @"";
}
NSString *WPMigratedCoupleURLString(NSString *savedURL) {
    NSString *replacement = WPDefaultCoupleURLString();
    if (!savedURL.length) return replacement;
    NSArray *legacy = [WPBackendConfiguration()[@"migrateFrom"] isKindOfClass:NSArray.class] ? WPBackendConfiguration()[@"migrateFrom"] : @[];
    if (replacement.length && [legacy containsObject:savedURL]) return replacement;
    return savedURL;
}
NSURL *WPCoupleHealthURL(NSURL *url) {
    if (!WPIsValidCoupleURL(url)) return nil;
    NSURLComponents *parts = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    parts.scheme = [url.scheme.lowercaseString isEqualToString:@"wss"] ? @"https" : @"http";
    parts.path = @"/health"; return parts.URL;
}
NSTimeInterval WPCoupleConnectTimeout(void) {
    id value = WPBackendConfiguration()[@"connectTimeoutSeconds"];
    return [value respondsToSelector:@selector(doubleValue)] ? MAX(5, MIN(60, [value doubleValue])) : 20;
}
NSString *WPCoupleConnectionFailureMessage(NSError *error, NSInteger statusCode) {
    if (statusCode == 401 || statusCode == 403) return @"同步令牌被拒绝，请核对这台手机的令牌（401/403）";
    if (statusCode == 404) return @"同步接口不存在，请确认服务地址以 /v1/ws 结尾（404）";
    if (statusCode == 426) return @"服务器未完成 WebSocket 升级，请检查反向代理（426）";
    if (statusCode == 429) return @"服务请求过多或免费额度受限，稍后重试（429）";
    if (statusCode >= 500) return @"同步后端暂时不可用，请检查部署或免费额度（5xx）";
    if ([error.domain isEqualToString:NSURLErrorDomain]) {
        switch (error.code) {
            case NSURLErrorCannotFindHost: case NSURLErrorDNSLookupFailed: return @"同步域名解析失败，请检查当前网络或更换服务地址";
            case NSURLErrorTimedOut: return @"同步连接超时；当前网络可能无法到达这个服务域名";
            case NSURLErrorCannotConnectToHost: return @"无法连接同步服务器，请检查网络、端口或域名可达性";
            case NSURLErrorNotConnectedToInternet: case NSURLErrorNetworkConnectionLost: return @"网络已断开，互动保留在本机等待重连";
            case NSURLErrorSecureConnectionFailed: case NSURLErrorServerCertificateHasBadDate:
            case NSURLErrorServerCertificateUntrusted: case NSURLErrorServerCertificateHasUnknownRoot:
            case NSURLErrorServerCertificateNotYetValid: return @"同步 HTTPS 证书验证失败，请修复服务端证书";
        }
    }
    return @"同步连接失败，正在等待重连；请在设置中检查服务地址";
}
