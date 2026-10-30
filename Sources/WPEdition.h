#import <Foundation/Foundation.h>

// build.sh selects one edition per build: 0 Zhour (single), 1 周游专属包, 2 Aria专属版.
// The two couple editions add pairing, interactions and their own default pet.
#ifndef WP_EDITION_ID
#define WP_EDITION_ID 0
#endif
#if WP_EDITION_ID < 0 || WP_EDITION_ID > 2
#error Unknown WP_EDITION_ID; use ./build.sh <mode> single|zhouyou|aria.
#endif
#define WP_EDITION_ARIA (WP_EDITION_ID == 2)
#define WP_EDITION_COUPLE (WP_EDITION_ID != 0)
// Zhouyou keeps stealth and the weekday check-in reminder; Aria retired both.
#define WP_FEATURE_STEALTH (WP_EDITION_ID == 1)
#define WP_FEATURE_WORK_CHECKIN (WP_EDITION_ID == 1)

#ifndef WP_VERSION_STRING
#define WP_VERSION_STRING @"1.5.3"
#endif
#ifndef WP_BUILD_VERSION
#define WP_BUILD_VERSION 1503
#endif

FOUNDATION_EXPORT BOOL WPCanUsePrivateFeatures(void);
/// Product name shown in WeChat settings, alerts and the plugin home.
FOUNDATION_EXPORT NSString *WPEditionName(void);
FOUNDATION_EXPORT NSString *WPPluginVersion(void);
/// Display name of the bundled default pet.
FOUNDATION_EXPORT NSString *WPEditionDefaultPetName(void);
/// Storage identities stay those of each edition's earlier releases, so an
/// upgrade keeps pairing, history, chosen pets and preferences.
FOUNDATION_EXPORT NSString *WPEditionPreferencesSuite(void);
FOUNDATION_EXPORT NSString *WPEditionDataDirectoryName(void);
FOUNDATION_EXPORT NSString *WPEditionKeychainPrefix(void);
/// Resource bundle names searched in order, without the .bundle extension.
FOUNDATION_EXPORT NSArray<NSString *> *WPEditionResourceBundleNames(void);
