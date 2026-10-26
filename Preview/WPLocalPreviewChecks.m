#import "WPLocalPreviewChecks.h"
#import "WPCommon.h"
#import "WPOverlay.h"
#import "WPPetImporter.h"
#import "WPPetRenderer.h"
#import "WPCoupleClient.h"
#import "WPCoupleHistory.h"
#import <QuartzCore/QuartzCore.h>

@interface WPOverlayManager (WPLocalPreviewTesting)
- (UIWindow *)activeWindow;
- (void)closePanel;
- (void)background:(NSNotification *)note;
@end
@interface UIViewController (WPLocalPreviewTesting)
- (CGPoint)peekCenter;
@end

@interface WPLocalPreviewClientSpy : WPCoupleClient
@property(nonatomic) NSUInteger sendCalls;
@end
@implementation WPLocalPreviewClientSpy
- (void)connect {}
- (void)disconnect {}
- (void)sendInteraction:(NSString *)kind completion:(void (^)(BOOL,NSString *))completion {self.sendCalls++;if(completion)completion(NO,@"preview test send intercepted");}
- (void)sendMissYou:(void (^)(BOOL,NSString *))completion {self.sendCalls++;if(completion)completion(NO,@"preview test send intercepted");}
@end

static UIButton *WPLocalButton(UIView *view,NSString *identifier) {
    if([view isKindOfClass:UIButton.class] && [view.accessibilityIdentifier isEqual:identifier])return (id)view;
    for(UIView *child in view.subviews){UIButton *button=WPLocalButton(child,identifier);if(button)return button;}
    return nil;
}
static NSData *WPLocalHistorySnapshot(void) {
    return [NSJSONSerialization dataWithJSONObject:WPCoupleHistory.sharedHistory.recentInteractions options:NSJSONWritingSortedKeys error:nil];
}

@interface WPLocalPreviewRunner : NSObject
@property(nonatomic,copy) void (^completion)(NSDictionary *);
@property(nonatomic) NSMutableDictionary *results;
@property(nonatomic) WPOverlayManager *manager;
@property(nonatomic) WPCoupleClient *originalClient;
@property(nonatomic) WPLocalPreviewClientSpy *spy;
@property(nonatomic,copy) NSString *originalSelection;
@property(nonatomic) NSDictionary *originalPreferences;
@property(nonatomic) NSData *historyBefore;
@property(nonatomic) NSUInteger badgeBefore;
@property(nonatomic) NSUInteger sendNotifications;
@property(nonatomic) NSUInteger previewNotifications;
@property(nonatomic) NSUInteger angerCaptionChecks;
@property(nonatomic) NSUInteger missCaptionChecks;
@property(nonatomic) BOOL angerCaptionsMatch;
@property(nonatomic) BOOL missCaptionsMatch;
@property(nonatomic) id sendObserver;
@property(nonatomic) id previewObserver;
@property(nonatomic) NSURL *imported;
@property(nonatomic) BOOL finished;
- (void)start;
@end

@implementation WPLocalPreviewRunner
- (void)check:(NSString *)name passed:(BOOL)passed {self.results[name]=@(passed);}
- (UIWindow *)overlay {return [self.manager activeWindow];}
- (UIViewController *)controller {return self.overlay.rootViewController;}
- (WPPetRenderer *)pet {return [self.controller valueForKey:@"pet"];}
- (void)after:(NSTimeInterval)delay do:(void (^)(void))block {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        if(self.finished)return;
        @try {block();} @catch(NSException *exception){[self check:@"localPreviewNoException" passed:NO];[self finish];}
    });
}
- (void)waitFor:(BOOL (^)(void))predicate deadline:(CFTimeInterval)deadline completion:(void (^)(BOOL))completion {
    if(predicate()){completion(YES);return;}
    if(CACurrentMediaTime()>=deadline){completion(NO);return;}
    [self after:.02 do:^{[self waitFor:predicate deadline:deadline completion:completion];}];
}
- (void)notifySettings {[NSNotificationCenter.defaultCenter postNotificationName:WPSettingsDidChangeNotification object:nil];}
- (void)postPreview:(NSString *)kind {[NSNotificationCenter.defaultCenter postNotificationName:@"WeChatPet.PreviewMissYou" object:kind];}
- (UIButton *)openButton:(NSString *)identifier {
    [self.manager openSettings];
    UIWindow *panel=[self.manager valueForKey:@"settingsWindow"];
    UINavigationController *navigation=(id)panel.rootViewController;
    UIViewController *page=[NSClassFromString(@"WPCoupleSettingsController") new];
    if(page)[navigation pushViewController:page animated:NO];
    return WPLocalButton(page.view,identifier);
}
- (void)preparePeek {
    UIViewController *controller=self.controller;WPPetRenderer *pet=self.pet;
    CGPoint center=pet.center;center.x=pet.bounds.size.width/2+10;
    [controller setValue:[NSValue valueWithCGPoint:center] forKey:@"fullCenter"];
    [controller setValue:@YES forKey:@"peeking"];[controller setValue:@NO forKey:@"edgeTransitioning"];
    [pet holdPeekOnLeft:YES];pet.center=[controller peekCenter];
}
- (BOOL)reaction:(NSString *)kind row:(NSInteger)row {
    WPPetRenderer *pet=self.pet;
    BOOL value=[[pet valueForKey:@"reactionKind"] isEqual:kind] && [[pet valueForKey:@"animationRow"] integerValue]==row;
    if([[pet valueForKey:@"metadata"][@"spriteVersionNumber"] integerValue]==5)value&=[[pet valueForKey:@"loadedAtlasRow"] integerValue]==row;
    return value && ((CALayer *)[pet valueForKey:@"spriteLayer"]).contents!=nil;
}
- (void)saveSnapshot:(NSString *)name {
    UIWindow *window=self.overlay;
    UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat defaultFormat];format.scale=1;
    UIImage *image=[[[UIGraphicsImageRenderer alloc] initWithBounds:window.bounds format:format] imageWithActions:^(UIGraphicsImageRendererContext *context){
        [UIColor.systemBackgroundColor setFill];UIRectFill(window.bounds);[window drawViewHierarchyInRect:window.bounds afterScreenUpdates:YES];
    }];
    [UIImagePNGRepresentation(image) writeToFile:[WPDataDirectory() stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"png"]] atomically:YES];
}
- (void)start {
    self.results=[NSMutableDictionary new];self.manager=WPOverlayManager.sharedManager;
    self.angerCaptionsMatch=YES;self.missCaptionsMatch=YES;
    self.originalSelection=[WPSelectedPetDirectory() copy];
    NSMutableDictionary *preferences=[NSMutableDictionary new];
    NSDictionary *persistent=[WPPreferences() persistentDomainForName:@"dev.zhour.wechatpet"];
    for(NSString *key in @[@"enabled",@"autoPeek",@"quickChatEnabled"])preferences[key]=persistent[key] ?: NSNull.null;
    self.originalPreferences=preferences;self.historyBefore=WPLocalHistorySnapshot();self.badgeBefore=WPCoupleHistory.sharedHistory.badgeCount;
    self.originalClient=[self.manager valueForKey:@"couple"];[self.originalClient disconnect];
    self.spy=[WPLocalPreviewClientSpy new];[self.manager setValue:self.spy forKey:@"couple"];
    __weak typeof(self) weakSelf=self;
    self.sendObserver=[NSNotificationCenter.defaultCenter addObserverForName:@"WeChatPet.SendInteraction" object:nil queue:nil usingBlock:^(__unused NSNotification *note){weakSelf.sendNotifications++;}];
    self.previewObserver=[NSNotificationCenter.defaultCenter addObserverForName:@"WeChatPet.PreviewMissYou" object:nil queue:nil usingBlock:^(__unused NSNotification *note){weakSelf.previewNotifications++;}];
    [WPPreferences() setBool:YES forKey:@"enabled"];[WPPreferences() setBool:NO forKey:@"autoPeek"];[WPPreferences() setBool:NO forKey:@"quickChatEnabled"];
    [self notifySettings];[self.manager closePanel];
    WPResetSelectedPet();[NSNotificationCenter.defaultCenter postNotificationName:WPSelectedPetDidChangeNotification object:nil];
    [self check:@"localPreviewV4DefaultLoaded" passed:[[self.pet valueForKey:@"metadata"][@"spriteVersionNumber"] integerValue]==4];
    [self exerciseVersion:@"v4" completion:^{[self importYue2];}];
}
- (void)exerciseVersion:(NSString *)version completion:(void (^)(void))completion {
    UIButton *miss=[self openButton:@"WPLocalPreviewMiss"];
    [self check:[version stringByAppendingString:@"RealMissButtonPresent"] passed:miss!=nil];
    if(!miss){completion();return;}
    [self preparePeek];NSUInteger notifications=self.previewNotifications;
    [miss sendActionsForControlEvents:UIControlEventTouchUpInside];
    [self check:[version stringByAppendingString:@"ButtonClosesSettingsBeforePreview"] passed:[self.manager valueForKey:@"settingsWindow"]==nil && self.previewNotifications==notifications];
    [self waitFor:^BOOL{return [self reaction:@"reveal" row:27] && [[self.pet valueForKey:@"queuedReaction"] isEqual:@"receiveMiss"];} deadline:CACurrentMediaTime()+1.2 completion:^(BOOL revealed){
        [self check:[version stringByAppendingString:@"PeekRevealFinishesBeforeQueuedMiss"] passed:revealed && ![[self.controller valueForKey:@"peeking"] boolValue]];
        UIButton *anger=[self openButton:@"WPLocalPreviewAnger"];
        [self check:[version stringByAppendingString:@"RealAngerButtonPresent"] passed:anger!=nil];
        [anger sendActionsForControlEvents:UIControlEventTouchUpInside];
        [self waitFor:^BOOL{return [[self.pet valueForKey:@"queuedReaction"] isEqual:@"receiveAnger"];} deadline:CACurrentMediaTime()+.9 completion:^(BOOL queued){
            [self check:[version stringByAppendingString:@"RapidButtonsKeepLatestPreviewDuringReveal"] passed:queued && [self reaction:@"reveal" row:27]];
            [self waitFor:^BOOL{return [self reaction:@"receiveAnger" row:19];} deadline:CACurrentMediaTime()+1 completion:^(BOOL angry){
                [self check:[version stringByAppendingString:@"ButtonRoutesToReceiveAnger19"] passed:angry && self.previewNotifications>=notifications+2];
                UILabel *angerCaption=[self.controller valueForKey:@"bubble"];
                self.angerCaptionChecks++;self.angerCaptionsMatch&=angry && !angerCaption.hidden && [angerCaption.text containsString:@"收到"] && [angerCaption.text containsString:@"生气了"];
                [self saveSnapshot:[version stringByAppendingString:@"-local-preview-anger"]];
                [self after:.12 do:^{
                    WPPetRenderer *pet=self.pet;CFTimeInterval previous=[[pet valueForKey:@"animationStartedAt"] doubleValue];
                    BOOL advanced=[[pet valueForKey:@"frameIndex"] integerValue]>0;
                    BOOL replay=[pet playLocalPreviewReaction:@"anger"];
                    [self check:[version stringByAppendingString:@"SamePreviewRestartsAtFrameZero"] passed:advanced && replay && [self reaction:@"receiveAnger" row:19] && [[pet valueForKey:@"frameIndex"] integerValue]==0 && [[pet valueForKey:@"animationStartedAt"] doubleValue]>previous];
                    [pet playLocalPreviewReaction:@"miss"];[pet playLocalPreviewReaction:@"anger"];[pet playLocalPreviewReaction:@"miss"];
                    [self check:[version stringByAppendingString:@"RapidDirectPreviewLatestWins"] passed:[self reaction:@"receiveMiss" row:17] && [pet valueForKey:@"queuedReaction"]==nil && [[pet valueForKey:@"frameIndex"] integerValue]==0];
                    CFTimeInterval started=[[pet valueForKey:@"animationStartedAt"] doubleValue];
                    BOOL duplicate=[pet playReaction:@"miss"],different=[pet playReaction:@"anger"];
                    [self check:[version stringByAppendingString:@"RealIncomingCoalescingIsUnchanged"] passed:!duplicate && !different && [[pet valueForKey:@"animationStartedAt"] doubleValue]==started && [self reaction:@"receiveMiss" row:17] && [[pet valueForKey:@"queuedReaction"] isEqual:@"receiveAnger"]];
                    // A preview screenshot must use the manager route too, so
                    // its visible caption describes the action being shown.
                    [self postPreview:@"miss"];
                    UILabel *missCaption=[self.controller valueForKey:@"bubble"];
                    self.missCaptionChecks++;self.missCaptionsMatch&=[self reaction:@"receiveMiss" row:17] && !missCaption.hidden && [missCaption.text containsString:@"收到"] && [missCaption.text containsString:@"想你了"];
                    [self saveSnapshot:[version stringByAppendingString:@"-local-preview-miss"]];
                    [self check:[version stringByAppendingString:@"LocalPreviewUsesReceiveMiss17"] passed:[self reaction:@"receiveMiss" row:17]];
                    completion();
                }];
            }];
        }];
    }];
}
- (void)importYue2 {
    NSURL *package=[WPResourceBundle() URLForResource:@"Yue2Pet" withExtension:@"zip"];
    [self check:@"localPreviewYue2TestPackagePresent" passed:package!=nil];
    if(!package){[self hiddenChecks];return;}
    NSURL *root=[NSURL fileURLWithPath:[WPDataDirectory() stringByAppendingPathComponent:@"ImportedPets"] isDirectory:YES];
    [WPPetImporter importZipAtURL:package destinationRoot:root completion:^(NSURL *directory,NSError *error){
        [self check:@"localPreviewRealYue2Import" passed:directory && !error && NSThread.isMainThread];self.imported=directory;
        if(!directory){[self hiddenChecks];return;}
        WPSelectPetDirectory(directory);[NSNotificationCenter.defaultCenter postNotificationName:WPSelectedPetDidChangeNotification object:nil];
        [self check:@"localPreviewV5ImportedPetLoaded" passed:[[self.pet valueForKey:@"metadata"][@"spriteVersionNumber"] integerValue]==5];
        [self exerciseVersion:@"v5" completion:^{[self hiddenChecks];}];
    }];
}
- (void)hiddenChecks {
    WPPetRenderer *pet=self.pet;
    [pet setAnimationActive:NO];NSString *reaction=[[pet valueForKey:@"reactionKind"] copy];
    BOOL paused=[pet playLocalPreviewReaction:@"anger"];
    [self check:@"localPreviewPausedRendererDoesNotWakeOrMutate" passed:!paused && [pet valueForKey:@"displayLink"]==nil && [pet valueForKey:@"atlas"]==nil && ((reaction==nil && [pet valueForKey:@"reactionKind"]==nil) || [reaction isEqual:[pet valueForKey:@"reactionKind"]])];
    [pet setAnimationActive:YES];
    [self.manager background:nil];[self postPreview:@"anger"];
    [self check:@"localPreviewBackgroundWindowDoesNotWake" passed:[pet valueForKey:@"displayLink"]==nil && [pet valueForKey:@"atlas"]==nil];
    [self.manager refresh];
    [WPPreferences() setBool:NO forKey:@"enabled"];[self notifySettings];
    NSUInteger notifications=self.previewNotifications;
    UIButton *button=[self openButton:@"WPLocalPreviewMiss"];
    UIWindow *panel=[self.manager valueForKey:@"settingsWindow"];UINavigationController *navigation=(id)panel.rootViewController;
    UIViewController *page=navigation.topViewController;
    [button sendActionsForControlEvents:UIControlEventTouchUpInside];
    [self after:.25 do:^{
        UIAlertController *alert=[page.presentedViewController isKindOfClass:UIAlertController.class]?(id)page.presentedViewController:nil;
        [self check:@"localPreviewHiddenButtonKeepsSettingsAndExplainsRecovery" passed:button && [self.manager valueForKey:@"settingsWindow"]==panel && navigation.topViewController==page && [alert.message containsString:@"隐藏桌宠"] && self.previewNotifications==notifications];
        [self postPreview:@"miss"];BOOL requested=[pet playLocalPreviewReaction:@"anger"];
        [self check:@"localPreviewHiddenNotificationDoesNotRevealOrAnimate" passed:!requested && pet.hidden && self.controller.view.hidden && [pet valueForKey:@"displayLink"]==nil && [pet valueForKey:@"atlas"]==nil];
        [page dismissViewControllerAnimated:NO completion:nil];
        [self check:@"localPreviewNoException" passed:YES];[self finish];
    }];
}
- (void)finish {
    if(self.finished)return;self.finished=YES;
    [self check:@"localPreviewAngerCaptionMatchesActionInV4AndV5" passed:self.angerCaptionChecks==2 && self.angerCaptionsMatch];
    [self check:@"localPreviewMissCaptionMatchesActionInV4AndV5" passed:self.missCaptionChecks==2 && self.missCaptionsMatch];
    [self check:@"localPreviewDoesNotWriteHistoryOrBadge" passed:[self.historyBefore isEqual:WPLocalHistorySnapshot()] && self.badgeBefore==WPCoupleHistory.sharedHistory.badgeCount];
    [self check:@"localPreviewDoesNotSendClientOrSendNotification" passed:self.spy.sendCalls==0 && self.sendNotifications==0];
    [NSNotificationCenter.defaultCenter removeObserver:self.sendObserver];[NSNotificationCenter.defaultCenter removeObserver:self.previewObserver];
    [self.manager closePanel];
    if(self.originalSelection.length)WPSelectPetDirectory([NSURL fileURLWithPath:self.originalSelection isDirectory:YES]);else WPResetSelectedPet();
    for(NSString *key in self.originalPreferences){id value=self.originalPreferences[key];if(value==NSNull.null)[WPPreferences() removeObjectForKey:key];else [WPPreferences() setObject:value forKey:key];}
    [self.manager setValue:self.originalClient forKey:@"couple"];
    [NSNotificationCenter.defaultCenter postNotificationName:WPSelectedPetDidChangeNotification object:nil];[self notifySettings];[self.manager refresh];
    if(self.imported)[NSFileManager.defaultManager removeItemAtURL:self.imported error:nil];
    [self check:@"localPreviewRestoresSelection" passed:self.originalSelection.length?[WPSelectedPetDirectory() isEqual:self.originalSelection]:WPSelectedPetDirectory()==nil];
    void (^completion)(NSDictionary *)=self.completion;self.completion=nil;if(completion)completion(self.results);
}
@end

void WPLocalPreviewRunChecks(void (^completion)(NSDictionary *results)) {
    NSCAssert(NSThread.isMainThread,@"Local preview checks run on main");
    WPLocalPreviewRunner *runner=[WPLocalPreviewRunner new];runner.completion=completion;[runner start];
}
