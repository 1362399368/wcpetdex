#import <Foundation/Foundation.h>

#ifndef WP_EDITION_ARIA
#define WP_EDITION_ARIA 0
#endif
#if WP_EDITION_ARIA
#error This source package builds the Zhouyou personal edition only.
#endif
#ifndef WP_VERSION_STRING
#define WP_VERSION_STRING @"1.2.6"
#endif
#ifndef WP_BUILD_VERSION
#define WP_BUILD_VERSION 1207
#endif

FOUNDATION_EXPORT BOOL WPCanUsePrivateFeatures(void);
FOUNDATION_EXPORT NSString *WPEditionName(void);
FOUNDATION_EXPORT NSString *WPPluginVersion(void);
