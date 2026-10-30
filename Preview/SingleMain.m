#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "WPCommon.h"
#import "WPEdition.h"
#import "WPOverlay.h"
#import "WPPetRenderer.h"
#import "WPPetCatalog.h"
#import "WPTapActions.h"
#import "WPCollectorChecks.h"
#import "WPThumbnailOptimizationChecks.h"
#import "WPRankingUIChecks.h"
#import "WPMenuConfigurationChecks.h"
#import "WPQuickAvatarGestureChecks.h"
#import "WPHomePresentationChecks.h"
#import "WPAdvisorStatusChecks.h"
#import "WPAdvisorContinuousChecks.h"
extern NSDictionary *WPAdvisorTaskCenterPreviewChecks(void);
extern NSDictionary *WPAdvisorReplyPreviewChecks(void);
extern NSDictionary *WPAdvisorContextPreviewChecks(void);
extern NSDictionary *WPAdvisorOverlayPreviewChecks(void);
extern void WPAdvisorDelayedReplyChecks(void (^completion)(NSDictionary<NSString *,NSNumber *> *));
extern NSDictionary<NSString *,NSNumber *> *WPChoiceSheetPreviewChecks(void);
extern void WPAdvisorIncomingHookChecks(void (^completion)(NSDictionary<NSString *,NSNumber *> *));
extern void WPAdvisorProviderPreviewChecks(void (^completion)(NSDictionary<NSString *,NSNumber *> *));
#if WP_EDITION_COUPLE
extern NSDictionary<NSString *,NSNumber *> *WPCoupleEditionPreviewChecks(CGRect frame);
#endif

static UIView *WPFindIdentifiedView(UIView *root, NSString *identifier) {
    if ([root.accessibilityIdentifier isEqualToString:identifier]) return root;
    for (UIView *child in root.subviews) {
        UIView *found = WPFindIdentifiedView(child, identifier);
        if (found) return found;
    }
    return nil;
}

static BOOL WPContainsText(UIView *root, NSString *fragment) {
    if ([root isKindOfClass:UILabel.class] && [((UILabel *)root).text containsString:fragment]) return YES;
    if ([root isKindOfClass:UIButton.class] && [((UIButton *)root).currentTitle containsString:fragment]) return YES;
    if ([root.accessibilityLabel containsString:fragment]) return YES;
    for (UIView *child in root.subviews) if (WPContainsText(child, fragment)) return YES;
    return NO;
}

// Exercises transient access failures using a disposable, uniquely named
// downloaded-pet fixture. Never modifies an existing downloaded pet.
static NSDictionary *WPPetRetentionPreviewChecks(void) {
    NSFileManager *fm=NSFileManager.defaultManager;
    NSString *selection=[WPDataDirectory() stringByAppendingPathComponent:@"selected-pet.json"];
    NSData *oldSelection=[NSData dataWithContentsOfFile:selection];
    NSArray *keys=@[@"selectedPetReference",@"selectedPetDirectory",@"selectedPetLastLoad"];
    NSMutableDictionary *old=[NSMutableDictionary new];
    for(NSString *key in keys)old[key]=[WPPreferences() objectForKey:key]?:NSNull.null;
    NSString *identifier=[@"preview-retention-" stringByAppendingString:NSUUID.UUID.UUIDString];
    NSURL *directory=[[WPPetCatalog cacheRootDirectory] URLByAppendingPathComponent:identifier isDirectory:YES];
    NSString *json=[directory.path stringByAppendingPathComponent:@"pet.json"];
    NSString *paused=[directory.path stringByAppendingPathComponent:@"pet.json.unavailable"];
    NSMutableDictionary *results=[NSMutableDictionary new];
    NSError *error=nil;
    // DefaultPet carries a full atlas in every edition's preview bundle; Aria's
    // bundled pet ships only its paged rows, which load from the bundle alone.
    NSString *fixtureSource=[WPResourceDirectory() stringByAppendingPathComponent:@"DefaultPet"];
    BOOL copied=[fm copyItemAtURL:[NSURL fileURLWithPath:fixtureSource isDirectory:YES] toURL:directory error:&error];
    NSMutableDictionary *metadata=copied?[[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:json] options:NSJSONReadingMutableContainers error:nil] mutableCopy]:nil;
    metadata[@"displayName"]=@"测试已下载桌宠";
    NSData *updated=metadata?[NSJSONSerialization dataWithJSONObject:metadata options:0 error:nil]:nil;
    BOOL prepared=updated && [updated writeToFile:json atomically:YES] && WPSelectPetDirectory(directory);
    results[@"downloadedPetFixtureSelected"]=@(prepared);
    if(prepared){
        WPPetRenderer *shown=[[WPPetRenderer alloc] initWithFrame:CGRectMake(0,0,120,130)];
        BOOL selected=[shown.petName isEqual:@"测试已下载桌宠"];
        BOOL unavailable=[fm moveItemAtPath:json toPath:paused error:nil];
        [shown reloadPet];
        results[@"temporaryFailureKeepsDisplayedPet"]=@(selected && unavailable && [shown.petName isEqual:@"测试已下载桌宠"] && [[shown valueForKey:@"needsReloadOnActivation"] boolValue]);
        WPPetRenderer *fallback=[[WPPetRenderer alloc] initWithFrame:CGRectMake(0,0,120,130)];
        BOOL fellBack=[fallback.petName containsString:WPEditionDefaultPetName()] && [[fallback valueForKey:@"needsReloadOnActivation"] boolValue];
        BOOL referencePreserved=[WPSelectedPetDirectory() isEqual:directory.path];
        BOOL restored=[fm moveItemAtPath:paused toPath:json error:nil];
        [fallback setAnimationActive:NO];[fallback setAnimationActive:YES];
        results[@"fallbackRetriesSelectedPetOnForeground"]=@(fellBack && referencePreserved && restored && [fallback.petName isEqual:@"测试已下载桌宠"]);
        [shown setAnimationActive:NO];[shown setAnimationActive:YES];
        results[@"retainedPetRecoversOnForeground"]=@([shown.petName isEqual:@"测试已下载桌宠"] && ![[shown valueForKey:@"needsReloadOnActivation"] boolValue]);
        [shown setAnimationActive:NO];[fallback setAnimationActive:NO];
    }
    if(oldSelection)[oldSelection writeToFile:selection atomically:YES];else [fm removeItemAtPath:selection error:nil];
    for(NSString *key in keys)if(old[key]==NSNull.null)[WPPreferences() removeObjectForKey:key];else [WPPreferences() setObject:old[key] forKey:key];
    [fm removeItemAtURL:directory error:nil];
    return results;
}

@interface WPSinglePreviewHome : UIViewController
@end
@implementation WPSinglePreviewHome
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = [WPEditionName() stringByAppendingString:@" 测试"];
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
    checks[@"luluMetadataPresent"] = @([name containsString:WPEditionDefaultPetName()]);
    WPPreviewSetAtlasLoadingSynchronous(YES);
    WPPetRenderer *renderer = [[WPPetRenderer alloc] initWithFrame:CGRectMake(0, 0, 120, 130)];
    CALayer *sprite = [renderer valueForKey:@"spriteLayer"];
    checks[@"luluLoadsAsSelectedDefault"] = @([renderer.petName containsString:WPEditionDefaultPetName()] && [[WPPreferences() dictionaryForKey:@"selectedPetLastLoad"][@"loadedDirectoryName"] isEqualToString:WPDefaultPetDirectory().lastPathComponent]);
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
    Class cls = NSClassFromString(@"WPQuickActionsController");
    UIViewController *settings = cls ? [cls new] : nil;
    settings.view.frame = self.window.bounds;
    [settings.view setNeedsLayout];
    [settings.view layoutIfNeeded];
    checks[@"longPressSettingVisible"] = @(settings && WPFindIdentifiedView(settings.view, @"WPLongPressAction") != nil);
    checks[@"shakeSettingVisible"] = @(settings && WPFindIdentifiedView(settings.view, @"WPShakeAction") != nil);
    checks[@"sidebarAvatarActionsVisible"] = @(WPFindIdentifiedView(settings.view, @"WPQuickChatAvatarTapAction") && WPFindIdentifiedView(settings.view, @"WPQuickChatAvatarHoldAction"));
    checks[@"quickChatEnableSwitchVisible"] = @(WPFindIdentifiedView(settings.view, @"WPQuickChatEnableSwitch") != nil);
    id previousEnabled=[WPPreferences() objectForKey:@"quickChatEnabled"];
    id previousSingle=[WPPreferences() objectForKey:@"singleTapAction"];
    id previousDouble=[WPPreferences() objectForKey:@"doubleTapAction"];
    WPSetConfiguredTapAction(NO,WPTapActionQuickChat);
    WPSetConfiguredTapAction(YES,WPTapActionChatAdvisor);
    [WPPreferences() setBool:YES forKey:@"quickChatEnabled"];
    [settings viewWillAppear:NO];
    UISwitch *enable=(UISwitch *)WPFindIdentifiedView(settings.view,@"WPQuickChatEnableSwitch");
    [enable setOn:NO];[enable sendActionsForControlEvents:UIControlEventValueChanged];
    BOOL preservedOff=enable && ![WPPreferences() boolForKey:@"quickChatEnabled"] && WPConfiguredTapAction(NO)==WPTapActionQuickChat && WPConfiguredTapAction(YES)==WPTapActionChatAdvisor;
    enable=(UISwitch *)WPFindIdentifiedView(settings.view,@"WPQuickChatEnableSwitch");
    [enable setOn:YES];[enable sendActionsForControlEvents:UIControlEventValueChanged];
    checks[@"quickChatTogglePreservesTapActions"] = @(preservedOff && enable && [WPPreferences() boolForKey:@"quickChatEnabled"] && WPConfiguredTapAction(NO)==WPTapActionQuickChat && WPConfiguredTapAction(YES)==WPTapActionChatAdvisor);
    for(NSArray *entry in @[@[@"quickChatEnabled",previousEnabled?:NSNull.null],@[@"singleTapAction",previousSingle?:NSNull.null],@[@"doubleTapAction",previousDouble?:NSNull.null]]) {
        if(entry[1]==NSNull.null)[WPPreferences() removeObjectForKey:entry[0]];else [WPPreferences() setObject:entry[1] forKey:entry[0]];
    }
    UIViewController *petSettings = [NSClassFromString(@"WPPetSettingsController") new];
    petSettings.view.frame = self.window.bounds; [petSettings.view setNeedsLayout]; [petSettings.view layoutIfNeeded];
    checks[@"gesturesNotDuplicatedInPetSettings"] = @(petSettings && !WPFindIdentifiedView(petSettings.view, @"WPLongPressAction") && !WPFindIdentifiedView(petSettings.view, @"WPShakeAction"));
    UIViewController *home = [NSClassFromString(@"WPSettingsController") new];
    home.view.frame = self.window.bounds; [home.view setNeedsLayout]; [home.view layoutIfNeeded];
    checks[@"telegramEntryVisible"] = @(home && WPFindIdentifiedView(home.view, @"WPHomeTelegramGroup"));
    checks[@"versionDiagnosticsSectionAbsent"] = @(home && !WPContainsText(home.view, @"版本与诊断") && !WPContainsText(home.view, @"导出适配诊断"));
    checks[@"personalNameVisible"] = @(home && WPContainsText(home.view, WP_EDITION_ARIA ? @"Aria专属版" : WPEditionName()));
    checks[@"introductionEntryVisible"] = @(home && WPFindIdentifiedView(home.view, @"WPPluginIntroduction"));
    UIViewController *intro=[NSClassFromString(@"WPPluginIntroductionController") new];
    intro.view.frame=self.window.bounds; [intro.view setNeedsLayout]; [intro.view layoutIfNeeded];
    checks[@"introductionDoesNotContainTelegram"] = @(intro && !WPContainsText(intro.view, @"Telegram") && !WPFindIdentifiedView(intro.view, @"WPOpenTelegramGroup"));
    checks[@"petRecoveryControlsVisible"] = @(petSettings && WPFindIdentifiedView(petSettings.view, @"WPRecoveryPauseControl") && WPFindIdentifiedView(petSettings.view, @"WPRecoveryRetryControl"));
    [checks addEntriesFromDictionary:WPPetRetentionPreviewChecks()];
    [checks addEntriesFromDictionary:WPCollectorPreviewChecks()];
    [checks addEntriesFromDictionary:WPThumbnailOptimizationChecks()];
    [checks addEntriesFromDictionary:WPRankingUIPreviewChecks()];
    [checks addEntriesFromDictionary:WPMenuConfigurationPreviewChecks()];
    [checks addEntriesFromDictionary:WPQuickAvatarGestureChecks()];
    [checks addEntriesFromDictionary:WPHomePresentationChecks()];
    [checks addEntriesFromDictionary:WPAdvisorStatusPreviewChecks()];
    [checks addEntriesFromDictionary:WPAdvisorTaskCenterPreviewChecks()];
    [checks addEntriesFromDictionary:WPAdvisorContinuousChecks()];
    [checks addEntriesFromDictionary:WPAdvisorReplyPreviewChecks()];
    [checks addEntriesFromDictionary:WPAdvisorContextPreviewChecks()];
    [checks addEntriesFromDictionary:WPAdvisorOverlayPreviewChecks()];
    [checks addEntriesFromDictionary:WPChoiceSheetPreviewChecks()];
#if WP_EDITION_COUPLE
    [checks addEntriesFromDictionary:WPCoupleEditionPreviewChecks(self.window.bounds)];
#endif
    WPAdvisorDelayedReplyChecks(^(NSDictionary<NSString *,NSNumber *> *delayedChecks){
    [checks addEntriesFromDictionary:delayedChecks];
    WPAdvisorIncomingHookChecks(^(NSDictionary<NSString *,NSNumber *> *hookChecks){
    [checks addEntriesFromDictionary:hookChecks];
    WPAdvisorProviderPreviewChecks(^(NSDictionary<NSString *,NSNumber *> *providerChecks){
        [checks addEntriesFromDictionary:providerChecks];
        BOOL all = YES;
        for (NSNumber *value in checks.allValues) all &= value.boolValue;
        NSDictionary *report = @{@"finished":@YES, @"allPassed":@(all), @"caseCount":@(checks.count), @"results":checks};
        NSData *out = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil];
        [out writeToFile:[WPDataDirectory() stringByAppendingPathComponent:@"single-preview-report.json"] atomically:YES];
    });
    });
    });
}
@end
int main(int argc, char *argv[]) { @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(WPSinglePreviewDelegate.class)); } }
