#import "WPEdition.h"

BOOL WPCanUsePrivateFeatures(void) { return YES; }
NSString *WPPluginVersion(void) { return WP_VERSION_STRING; }

#if WP_EDITION_ID == 0
NSString *WPEditionName(void) { return @"Zhour"; }
NSString *WPEditionDefaultPetName(void) { return @"噜噜"; }
NSString *WPEditionPreferencesSuite(void) { return @"dev.zhour.wechatpet.single"; }
NSString *WPEditionDataDirectoryName(void) { return @"WeChatPetSingle"; }
NSString *WPEditionKeychainPrefix(void) { return @"dev.zhour.wechatpet.single"; }
NSArray<NSString *> *WPEditionResourceBundleNames(void) { return @[@"Zhour", @"SinglePet-zhour", @"zhour-single"]; }
#else
NSString *WPEditionName(void) { return WP_EDITION_ARIA ? @"Aria专属（游定制最终版）" : @"周游专属包"; }
NSString *WPEditionDefaultPetName(void) { return WP_EDITION_ARIA ? @"Aria" : @"玥"; }
NSString *WPEditionPreferencesSuite(void) { return @"dev.zhour.wechatpet"; }
NSString *WPEditionDataDirectoryName(void) { return @"WeChatPet"; }
NSString *WPEditionKeychainPrefix(void) { return @"dev.zhour.wechatpet"; }
NSArray<NSString *> *WPEditionResourceBundleNames(void) { return @[@"WeChatPet"]; }
#endif
