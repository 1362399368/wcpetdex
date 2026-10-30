#import <Foundation/Foundation.h>

/// Simulator-only integration checks of the real imported Yue2 package.
/// Completion contains boolean cases only; supporting measurements and PNG
/// previews are saved under WPDataDirectory(). Must be called on main.
FOUNDATION_EXPORT void WPYue2RunPreviewChecks(void (^completion)(NSDictionary *results));
