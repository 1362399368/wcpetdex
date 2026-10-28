#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "WPCommon.h"
#import "WPOverlay.h"
#import "WPPetRenderer.h"
#import "WPTapActions.h"

static UIView *WPFindIdentifiedView(UIView *root, NSString *identifier) {
    if ([root.accessibilityIdentifier isEqualToString:identifier]) return root;
    for (UIView *child in root.subviews) {
        UIView *found = WPFindIdentifiedView(child, identifier);
        if (found) return found;
    }
    return nil;
}

@interface WPSinglePreviewHome : UIViewController
@end
@implementation WPSinglePreviewHome
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"zhour-single 测试";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"桌宠设置" style:UIBarButtonItemStylePlain target:self action:@selector(settings)];
}
- (void)settings { [WPOverlayManager.sharedManager openSettings]; }
@end

@interface WPSinglePreviewDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation WPSinglePreviewDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [[UINavigationController alloc] initWithRootViewController:[WPSinglePreviewHome new]];
    [self.window makeKeyAndVisible];
    WPStartPlugin();
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--single-self-test"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3*NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [self runChecks]; });
    }
    return YES;
}
- (void)runChecks {
    NSMutableDictionary *checks = [NSMutableDictionary new];
    checks[@"resourceDirectoryPresent"] = @([[NSFileManager defaultManager] fileExistsAtPath:WPResourceDirectory()]);
    checks[@"offlineCatalogPresent"] = @([[NSFileManager defaultManager] fileExistsAtPath:[WPResourceDirectory() stringByAppendingPathComponent:@"petdex-manifest-snapshot.json"]]);
    NSData *data = [NSData dataWithContentsOfFile:[WPDefaultPetDirectory() stringByAppendingPathComponent:@"pet.json"]];
    NSDictionary *metadata = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    NSString *name = metadata[@"displayName"] ?: metadata[@"name"];
    checks[@"luluMetadataPresent"] = @([name containsString:@"噜噜"]);
    WPPreviewSetAtlasLoadingSynchronous(YES);
    WPPetRenderer *renderer = [[WPPetRenderer alloc] initWithFrame:CGRectMake(0, 0, 120, 130)];
    CALayer *sprite = [renderer valueForKey:@"spriteLayer"];
    checks[@"luluLoadsAsSelectedDefault"] = @([renderer.petName containsString:@"噜噜"] && [[WPPreferences() dictionaryForKey:@"selectedPetLastLoad"][@"loadedDirectoryName"] isEqualToString:@"DefaultPet"]);
    checks[@"luluSpriteHasPixels"] = @(sprite.contents != nil && ((UIImage *)[renderer valueForKey:@"atlas"]).CGImage != NULL);
    checks[@"luluCanMove"] = @([renderer playSemanticAction:@"walkLeft"]);
    id oldLong = [WPPreferences() objectForKey:@"longPressAction"];
    id oldShake = [WPPreferences() objectForKey:@"shakeAction"];
    WPSetConfiguredGestureAction(YES, @"moments");
    WPSetConfiguredGestureAction(NO, @"settings");
    checks[@"gestureChoicesIndependent"] = @([WPConfiguredGestureAction(YES) isEqualToString:@"moments"] && [WPConfiguredGestureAction(NO) isEqualToString:@"settings"]);
    WPSetConfiguredGestureAction(NO, @"menu");
    checks[@"invalidShakeChoiceRejected"] = @([WPConfiguredGestureAction(NO) isEqualToString:@"settings"]);
    if (oldLong) [WPPreferences() setObject:oldLong forKey:@"longPressAction"]; else [WPPreferences() removeObjectForKey:@"longPressAction"];
    if (oldShake) [WPPreferences() setObject:oldShake forKey:@"shakeAction"]; else [WPPreferences() removeObjectForKey:@"shakeAction"];
    Class cls = NSClassFromString(@"WPPetSettingsController");
    UIViewController *settings = cls ? [cls new] : nil;
    settings.view.frame = self.window.bounds;
    [settings.view setNeedsLayout];
    [settings.view layoutIfNeeded];
    checks[@"longPressSettingVisible"] = @(settings && WPFindIdentifiedView(settings.view, @"WPLongPressAction") != nil);
    checks[@"shakeSettingVisible"] = @(settings && WPFindIdentifiedView(settings.view, @"WPShakeAction") != nil);
    BOOL all = YES;
    for (NSNumber *value in checks.allValues) all &= value.boolValue;
    NSDictionary *report = @{@"finished":@YES, @"allPassed":@(all), @"caseCount":@(checks.count), @"results":checks};
    NSData *out = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil];
    [out writeToFile:[WPDataDirectory() stringByAppendingPathComponent:@"single-preview-report.json"] atomically:YES];
}
@end
int main(int argc, char *argv[]) { @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(WPSinglePreviewDelegate.class)); } }
