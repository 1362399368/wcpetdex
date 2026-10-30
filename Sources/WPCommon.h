#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSBundle *WPResourceBundle(void);
FOUNDATION_EXPORT NSString *WPResourceDirectory(void);
FOUNDATION_EXPORT NSString *WPDefaultPetDirectory(void);
FOUNDATION_EXPORT NSUserDefaults *WPPreferences(void);
FOUNDATION_EXPORT NSString *WPDataDirectory(void);
FOUNDATION_EXPORT NSString * _Nullable WPSelectedPetDirectory(void);
FOUNDATION_EXPORT NSString * _Nullable WPSelectedPetReference(void);
FOUNDATION_EXPORT BOOL WPSelectPetDirectory(NSURL *directory);
FOUNDATION_EXPORT void WPResetSelectedPet(void);
FOUNDATION_EXPORT id _Nullable WPWeChatService(NSString *className);
FOUNDATION_EXPORT void WPStartPlugin(void);
FOUNDATION_EXPORT NSDictionary *WPRuntimeDiagnostics(void);
FOUNDATION_EXPORT void WPSendDevelopmentDiagnostics(void);
FOUNDATION_EXPORT NSString * const WPSelectedPetDidChangeNotification;
FOUNDATION_EXPORT NSString * const WPSettingsDidChangeNotification;
NS_ASSUME_NONNULL_END
