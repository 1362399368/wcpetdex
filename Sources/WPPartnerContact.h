#import <UIKit/UIKit.h>
#import "WPEdition.h"

NS_ASSUME_NONNULL_BEGIN
@interface WPPartnerContact : NSObject
/// Opens any session (friend or group) through the same guarded WeChat route.
+ (void)openConversationWithUsername:(NSString *)username inWindow:(nullable UIWindow *)window
                          completion:(void (^)(BOOL success, NSString *message))completion;
/// 0 and 3 use WeChat's native page sheet: initially 75%, then the saved height.
/// 1 explicitly opens the normal full-screen conversation.
+ (void)openConversationWithUsername:(NSString *)username inWindow:(nullable UIWindow *)window
                   presentationMode:(NSInteger)mode completion:(void (^)(BOOL success, NSString *message))completion;
/// Display name from CContactMgr for any session username; empty when unknown.
+ (NSString *)displayNameForUsername:(NSString *)username;
+ (nullable UIViewController *)visibleController:(nullable UIViewController *)controller;
#if WP_EDITION_COUPLE
+ (NSString *)selectedDisplayName;
+ (void)openSelectedConversationInWindow:(nullable UIWindow *)window
                             completion:(void (^)(BOOL success, NSString *message))completion;
#endif
#if WP_FEATURE_WORK_CHECKIN
/// Opens the selected partner's native chat and invokes WeChat's text-send path.
/// Completion means the native method was invoked, not that WeChat confirmed delivery.
+ (void)sendTextToSelectedPartner:(NSString *)text inWindow:(nullable UIWindow *)window
                      completion:(void (^)(BOOL invoked, NSString *message))completion;
#endif
@end

/// Searches local WeChat friends and returns the selected contact to the caller.
/// Without a handler, couple editions save the choice as the paired partner.
@interface WPPartnerPickerController : UITableViewController
/// Invoked after choosing a contact.
@property(nonatomic,copy,nullable) void (^selectionHandler)(NSString *username, NSString *displayName);
@property(nonatomic,copy,nullable) NSString *pickerTitle;
@end
NS_ASSUME_NONNULL_END
