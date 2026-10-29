#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
/// Supported actions in stable default order, including optional entries.
FOUNDATION_EXPORT NSArray<NSString *> *WPMenuAvailableActions(void);
FOUNDATION_EXPORT NSArray<NSString *> *WPMenuOrderedActions(void);
FOUNDATION_EXPORT NSArray<NSString *> *WPMenuEnabledActions(void);
FOUNDATION_EXPORT NSString *WPMenuActionTitle(NSString *identifier);
FOUNDATION_EXPORT void WPMenuSetOrder(NSArray<NSString *> *identifiers);
FOUNDATION_EXPORT void WPMenuSetActionEnabled(NSString *identifier, BOOL enabled);
FOUNDATION_EXPORT void WPMenuResetActions(void);
/// The three contact actions are contact1/contact2/contact3. Nil means the
/// slot is not configured; usernames stay in the plugin's local preferences.
FOUNDATION_EXPORT NSString * _Nullable WPMenuContactUsername(NSString *identifier);
FOUNDATION_EXPORT void WPMenuSetContactUsername(NSString *identifier, NSString * _Nullable username);

/// Drag rows to reorder; toggle entries to add or remove them from the menu.
@interface WPMenuSettingsController : UITableViewController
@end
NS_ASSUME_NONNULL_END
