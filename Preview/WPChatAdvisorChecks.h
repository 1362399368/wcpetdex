#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
/// Offline transcript, prompt, parsing and input checks, then — when baseURL is
/// a loopback mock server — the real request path and the overlay card flow.
FOUNDATION_EXPORT void WPChatAdvisorRunPreviewChecks(UIWindow *window, UIWindow * _Nullable overlay, NSString * _Nullable baseURL,
                                                     void (^completion)(NSDictionary<NSString *, NSNumber *> *results));
NS_ASSUME_NONNULL_END
