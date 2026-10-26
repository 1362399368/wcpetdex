#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
/// A subscriber to the shared local-first, 160px avatar request. Cancelling a
/// subscriber never cancels another visible consumer of the same username.
@interface WPSharedChatAvatarRequest : NSObject
- (void)cancel;
@end
FOUNDATION_EXPORT WPSharedChatAvatarRequest *WPRequestSharedChatAvatar(NSString *username, void (^completion)(UIImage * _Nullable image));
/// Main-thread lookup only. Cache is bounded to 16 images / 1.5 MiB and expires
/// after 60 seconds so a changed WeChat head image is picked up on the next use.
FOUNDATION_EXPORT UIImage * _Nullable WPCachedSharedChatAvatar(NSString *username);
FOUNDATION_EXPORT void WPPurgeSharedChatAvatars(void);
NS_ASSUME_NONNULL_END
