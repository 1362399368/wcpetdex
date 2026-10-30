#import <Foundation/Foundation.h>

/// Installs the native WeChat Settings row when its runtime classes are available.
/// Safe to call repeatedly; installation is limited to the WeChat process.
void WPInstallWeChatSettingsEntry(void);
