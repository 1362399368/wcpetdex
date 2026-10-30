#import <UIKit/UIKit.h>
#import "WPQuickChatModel.h"
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT BOOL WPQuickChatOptionBool(NSString *key);
FOUNDATION_EXPORT CGFloat WPQuickChatOptionNumber(NSString *key);
FOUNDATION_EXPORT NSString *WPQuickChatOptionString(NSString *key);
FOUNDATION_EXPORT void WPQuickChatSetOption(NSString *key,id value);
FOUNDATION_EXPORT NSArray<NSString *> *WPQuickChatRemovedUsernames(void);
FOUNDATION_EXPORT void WPQuickChatRemoveUsername(NSString *username);
FOUNDATION_EXPORT void WPQuickChatRestoreRemoved(void);
FOUNDATION_EXPORT NSArray<WPQuickChatSession *> *WPQuickChatApplyDisplayPolicy(NSArray<WPQuickChatSession *> *sessions);
FOUNDATION_EXPORT UIColor *WPQuickChatBackgroundColor(UITraitCollection *traits);
NS_ASSUME_NONNULL_END
