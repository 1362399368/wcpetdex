#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSDictionary *WPBackendConfiguration(void);
FOUNDATION_EXPORT NSString *WPDefaultCoupleURLString(void);
FOUNDATION_EXPORT NSString *WPMigratedCoupleURLString(NSString * _Nullable savedURL);
FOUNDATION_EXPORT NSString *WPTokenIdentityDigest(NSString *token);
FOUNDATION_EXPORT BOOL WPCoupleTokenChangeRequiresExpiry(NSString * _Nullable currentToken, NSString * _Nullable savedDigest, NSString *nextToken, NSUInteger pendingCount);
FOUNDATION_EXPORT BOOL WPIsValidCoupleURL(NSURL * _Nullable url);
FOUNDATION_EXPORT NSURL * _Nullable WPCoupleHealthURL(NSURL * _Nullable url);
FOUNDATION_EXPORT NSTimeInterval WPCoupleConnectTimeout(void);
FOUNDATION_EXPORT NSString *WPCoupleConnectionFailureMessage(NSError * _Nullable error, NSInteger statusCode);
NS_ASSUME_NONNULL_END
