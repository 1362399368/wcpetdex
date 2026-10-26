#import <Foundation/Foundation.h>

#ifndef WP_EDITION_ARIA
#define WP_EDITION_ARIA 1
#endif
#if !WP_EDITION_ARIA
#error This source package builds the Aria edition only.
#endif
#ifndef WP_VERSION_STRING
#define WP_VERSION_STRING @"5.2.0"
#endif
#ifndef WP_BUILD_VERSION
#define WP_BUILD_VERSION 5200
#endif

FOUNDATION_EXPORT BOOL WPCanUsePrivateFeatures(void);
FOUNDATION_EXPORT NSString *WPEditionName(void);
FOUNDATION_EXPORT NSString *WPPluginVersion(void);
