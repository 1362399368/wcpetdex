#import <UIKit/UIKit.h>
#import <objc/message.h>
#import "WPCommon.h"
#import "WPQuickChat.h"
#import "WPQuickChatBar.h"
#import "WPTapActions.h"
#import "WPRadialMenu.h"
#import "WPIndicatorSettings.h"
#import "WPPetRenderer.h"
#import "WPOverlay.h"
#import "WPUnreadAvatarControl.h"
#import "WPComfortPreferences.h"
#import "WPQuickChatPreferences.h"
#import "WPResizableChat.h"
#import "WPChatPresentationState.h"
#import "WPSharedChatAvatar.h"
extern void WPPreviewResetSharedAvatarState(void);
extern NSDictionary *WPPreviewSharedAvatarState(void);
@interface QuickReplyMsgMgr : NSObject
@property(nonatomic) NSUInteger routeCalls;
+ (instancetype)sharedManager;
@end

#if defined(WP_PREVIEW_HOST)

// Simulator-only stand-ins for WeChat's session services. Linked together with
// WPContactMocks.m by Tests/run-quickchat-preview.sh, never into the dylib.
@interface CContact : NSObject
@property (nonatomic, copy) NSString *m_nsUsrName;
@property (nonatomic, copy) NSString *m_nsNickName;
@property (nonatomic, copy) NSString *m_nsRemark;
@property (nonatomic, copy) NSString *m_nsHeadImgUrl;
@end
@interface CContactMgr : NSObject
@property (nonatomic, strong) NSDictionary<NSString *, CContact *> *fixtureContacts;
+ (instancetype)sharedManager;
@end
@interface MMMsgLogicManager : NSObject
@property (nonatomic) NSUInteger routeCalls;
@property (nonatomic, strong) CContact *lastContact;
+ (id)sharedManager;
@end

@interface MMSessionInfo : NSObject
@property (nonatomic, copy) NSString *m_nsUserName;
@property (nonatomic) unsigned int m_uUnReadCount;
@property (nonatomic) BOOL m_bShowUnReadAsRedDot;
@property (nonatomic) unsigned int m_uLastTime;
@property (nonatomic) BOOL m_isFolding;
@property (nonatomic, getter=isHidden) BOOL hidden;
@property (nonatomic, getter=isInChatBox) BOOL inChatBox;
@end
@implementation MMSessionInfo
@end

@interface MMNewSessionMgr : NSObject
@property (nonatomic, strong) NSMutableArray<MMSessionInfo *> *rows;
@property (nonatomic, copy) NSArray<NSString *> *homeNames;
@property (nonatomic) NSUInteger indexReads;
@property (nonatomic) BOOL corruptCount;
- (unsigned int)GetSessionCount;
- (MMSessionInfo *)GetSessionAtIndex:(unsigned int)index;
- (NSArray<NSString *> *)GetUserNamesOnSessionList;
@end
@implementation MMNewSessionMgr
- (unsigned int)GetSessionCount { return self.corruptCount?UINT_MAX:(unsigned int)self.rows.count; }
- (MMSessionInfo *)GetSessionAtIndex:(unsigned int)index { self.indexReads++; return index < self.rows.count ? self.rows[index] : nil; }
- (NSArray<NSString *> *)GetUserNamesOnSessionList { return self.homeNames; }
- (MMSessionInfo *)row:(NSString *)name { for (MMSessionInfo *row in self.rows) if ([row.m_nsUserName isEqual:name]) return row; return nil; }
@end

static NSMutableSet<NSString *> *WPQCMockDelayedHeads;
// The supplied WeChat 8.0.79 diagnostics contain no MMHeadImageMgr class.
// This protocol exercises the contact-URL route without using the network.
@interface WPQCAvatarURLProtocol : NSURLProtocol
@property (nonatomic) BOOL stopped;
- (void)deliverWhenReady;
@end
@implementation WPQCAvatarURLProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request {return [request.URL.host isEqualToString:@"avatar.wechatpet.test"];}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {return request;}
- (void)startLoading {dispatch_async(dispatch_get_main_queue(),^{[self deliverWhenReady];});}
- (void)deliverWhenReady {
    if(self.stopped)return;
    NSString *username=self.request.URL.lastPathComponent;
    if([WPQCMockDelayedHeads containsObject:username]){
        __weak typeof(self) weakSelf=self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[weakSelf deliverWhenReady];});return;
    }
    UIColor *color=[username hasSuffix:@"chatroom"]?UIColor.systemOrangeColor:([username isEqual:@"wxid_qc_pinned"]?UIColor.systemPinkColor:UIColor.systemTealColor);
    UIImage *image=[[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(80,80)] imageWithActions:^(__unused UIGraphicsImageRendererContext *context){
        [color setFill]; UIRectFill(CGRectMake(0, 0, 80, 80));
        [UIColor.whiteColor setFill]; [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(24, 14, 32, 32)] fill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(12, 50, 56, 50)] fill];
    }];
    NSData *bytes=UIImagePNGRepresentation(image);
    NSURLResponse *response=[[NSURLResponse alloc] initWithURL:self.request.URL MIMEType:@"image/png" expectedContentLength:bytes.length textEncodingName:nil];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:bytes];
    [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {self.stopped=YES;}
@end

static MMNewSessionMgr *WPQCMockSessions;
@interface MMServiceCenter : NSObject
+ (instancetype)defaultCenter;
- (id)getService:(Class)service;
@end
@implementation MMServiceCenter
+ (instancetype)defaultCenter { static MMServiceCenter *center; static dispatch_once_t once; dispatch_once(&once, ^{ center = [self new]; }); return center; }
- (id)getService:(Class)service {
    if (service == MMNewSessionMgr.class) return WPQCMockSessions;
    if ([service respondsToSelector:NSSelectorFromString(@"sharedManager")]) return ((id (*)(id, SEL))objc_msgSend)(service, NSSelectorFromString(@"sharedManager"));
    return nil;
}
@end

static MMSessionInfo *WPQCRow(NSString *name, unsigned int unread, BOOL muted) {
    MMSessionInfo *row = [MMSessionInfo new]; row.m_nsUserName = name; row.m_uUnReadCount = unread; row.m_bShowUnReadAsRedDot = muted; return row;
}
static void WPQCAddContact(NSString *username, NSString *name) {
    CContactMgr *manager = [CContactMgr sharedManager];
    NSMutableDictionary *contacts = [manager.fixtureContacts mutableCopy];
    CContact *contact = [CContact new]; contact.m_nsUsrName = username; contact.m_nsNickName = name;
    contact.m_nsHeadImgUrl=[@"https://avatar.wechatpet.test/" stringByAppendingString:username];contacts[username] = contact;
    manager.fixtureContacts = contacts;
}
/// Fills the mock list the way WeChat draws it: pinned, then most recent.
void WPQuickChatInstallPreviewSessions(void) {
    WPQCMockSessions = [MMNewSessionMgr new];
    // This head image appears only after the bar opens, as in WeChat's async cache.
    WPQCMockDelayedHeads = [NSMutableSet setWithObject:@"wxid_qc_pinned"];
    NSMutableArray *rows = [@[WPQCRow(@"wxid_qc_pinned", 0, NO), WPQCRow(@"qc_family@chatroom", 3, YES), WPQCRow(@"brandsessionholder", 5, YES),
                              WPQCRow(@"wxid_qc_friend", 1, NO)] mutableCopy];
    ((MMSessionInfo *)rows[0]).m_uLastTime = 100;
    ((MMSessionInfo *)rows[1]).m_uLastTime = 200;
    ((MMSessionInfo *)rows[3]).m_uLastTime = 300;
    MMSessionInfo *folded = WPQCRow(@"qc_folded@chatroom", 9, NO); folded.m_isFolding = YES; folded.m_uLastTime = 999;
    MMSessionInfo *hidden = WPQCRow(@"wxid_qc_hidden", 8, NO); hidden.hidden = YES; hidden.m_uLastTime = 998;
    MMSessionInfo *inBox = WPQCRow(@"wxid_qc_inbox", 7, NO); inBox.inChatBox = YES; inBox.m_uLastTime = 997;
    MMSessionInfo *offHome = WPQCRow(@"wxid_qc_offhome", 6, NO); offHome.m_uLastTime = 996;
    [rows addObjectsFromArray:@[folded, hidden, inBox, offHome]];
    WPQCAddContact(@"wxid_qc_pinned", @"置顶好友"); WPQCAddContact(@"qc_family@chatroom", @"相亲相爱一家人"); WPQCAddContact(@"wxid_qc_friend", @"周游");
    NSArray *names = @[@"许友兴", @"三口一皖周", @"生活用品", @"BearUp", @"东寨司飞水", @"Chainsawman备考答疑2026三月群", @"小王", @"苹果越狱交流"];
    for (NSUInteger i = 0; i < 36; i++) {
        NSString *username = [NSString stringWithFormat:@"wxid_qc_fill%02lu", (unsigned long)i];
        [rows addObject:WPQCRow(username, 0, NO)]; WPQCAddContact(username, names[i % names.count]);
    }
    WPQCMockSessions.rows = rows;
    NSMutableArray *homeNames = [NSMutableArray new]; for (MMSessionInfo *row in rows) if (![row.m_nsUserName isEqual:@"wxid_qc_offhome"]) [homeNames addObject:row.m_nsUserName];
    WPQCMockSessions.homeNames = homeNames;
}

static void WPQCAfter(NSTimeInterval seconds, dispatch_block_t block) { dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), block); }
static void WPQCWaitUntil(BOOL (^predicate)(void),CFTimeInterval deadline,void (^completion)(BOOL)){
    if(predicate()){completion(YES);return;}
    if(CACurrentMediaTime()>=deadline){completion(NO);return;}
    WPQCAfter(.05,^{WPQCWaitUntil(predicate,deadline,completion);});
}
static void WPQCSnapshot(UIView *view, NSString *name) {
    UIImage *image = [[[UIGraphicsImageRenderer alloc] initWithBounds:view.bounds] imageWithActions:^(__unused UIGraphicsImageRendererContext *context) {
        NSArray<UIWindow *> *windows=view.window.windowScene?view.window.windowScene.windows:UIApplication.sharedApplication.windows;
        for (UIWindow *window in windows) if (!window.hidden) [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:YES];
    }];
    [UIImagePNGRepresentation(image) writeToFile:[WPDataDirectory() stringByAppendingPathComponent:[name stringByAppendingString:@".png"]] atomically:YES];
}
@protocol WPQCOverlay <NSObject>
- (void)tap;
- (void)doubleTap;
- (void)execute:(NSString *)action;
@end
@interface WPQuickChatMonitor (WPPreviewPolling)
- (void)tick;
@end

/// End-to-end checks of the real overlay against the mock session services.
void WPQuickChatRunPreviewTests(UIWindow *overlay, void (^completion)(NSDictionary *results)) {
    NSMutableDictionary *r = [NSMutableDictionary new];
    UIViewController<WPQCOverlay> *controller = (id)overlay.rootViewController;
    UIView *pet = [controller valueForKey:@"pet"], *dot = [controller valueForKey:@"unreadDot"], *arrivals = [controller valueForKey:@"arrivals"];
    WPQuickChatBar *bar = [controller valueForKey:@"quickBar"]; WPRadialMenuView *menu = [controller valueForKey:@"menu"];
    UINavigationController *host = (id)UIApplication.sharedApplication.windows.firstObject.rootViewController;
    NSUserDefaults *defaults = WPPreferences();
    // Run the original compatibility contract with its explicit old presentation;
    // the new defaults and all new settings have separate QC121 coverage.
    NSDictionary *fixtureOptions=@{@"quickChat.showMuted":@YES,@"quickChat.unreadFirst":@NO,@"quickChat.style":@1,
        @"quickChat.avatarSize":@50,@"quickChat.tapMode":@1,@"quickChat.side":@0,@"quickChat.width":@76,
        @"quickChat.height":@0,@"quickChat.showNames":@YES,@"quickChat.edgeTapActions":@NO,@"barrageEnabled":@NO};
    NSMutableDictionary *savedOptions=[NSMutableDictionary new];for(NSString *key in fixtureOptions){savedOptions[key]=[defaults objectForKey:key]?:NSNull.null;[defaults setObject:fixtureOptions[key] forKey:key];}
    void (^deliver)(NSDictionary *)=^(NSDictionary *report){for(NSString *key in savedOptions){id value=savedOptions[key];if(value==NSNull.null)[defaults removeObjectForKey:key];else [defaults setObject:value forKey:key];}completion(report);};

    id originalFlash=[defaults persistentDomainForName:@"dev.zhour.wechatpet"][@"quickChatFlash"] ?: NSNull.null;
    NSMutableDictionary *scenarioDiagnostics=[@{@"originalFlashPreference":originalFlash,@"originalFlashEffective":@(WPQuickChatFlashEnabled())} mutableCopy];
    // This scenario explicitly verifies flashes, including when a previous
    // scenario correctly restored a user's persisted "flash off" preference.
    [defaults setBool:YES forKey:@"quickChatFlash"];
    scenarioDiagnostics[@"scenarioFlashEnabled"]=@(WPQuickChatFlashEnabled());
    [defaults setBool:YES forKey:@"enabled"];
    [defaults setObject:@"wxid_qc_pinned" forKey:@"partnerUsername"];
    [defaults setBool:NO forKey:@"quickChatEnabled"];
    [defaults setBool:YES forKey:@"unreadAvatarEnabled"];
    for(NSString *key in @[@"unreadAvatarOffsetX",@"unreadAvatarOffsetY",@"interactionBadgeOffsetX",@"interactionBadgeOffsetY"])[defaults removeObjectForKey:key];
    WPSetConfiguredTapAction(NO, WPTapActionPartnerChat);
    WPSetConfiguredTapAction(YES, WPTapActionSettings);
    [NSNotificationCenter.defaultCenter postNotificationName:WPSettingsDidChangeNotification object:nil];
    r[@"QC01_chatBarOffStillMonitorsUnreadAvatar"] = @([WPQuickChatMonitor.sharedMonitor.diagnostics[@"state"] isEqual:@"active"] && !dot.hidden);
    [menu showAroundPoint:pet.center inBounds:controller.view.bounds];
    NSArray *offButtons = [menu valueForKey:@"actionButtons"];
    BOOL offHasHide = NO;
    for (id button in offButtons) offHasHide |= [[button valueForKey:@"actionIdentifier"] isEqual:@"hide"];
    r[@"QC02_offMenuHasFourItemsWithoutHide"] = @(offButtons.count == 4 && !offHasHide); [menu cancel];
    [defaults setBool:YES forKey:@"quickChatEnabled"];
    [NSNotificationCenter.defaultCenter postNotificationName:WPSettingsDidChangeNotification object:nil];
    r[@"QC31_switchDoesNotChangeSelectedTap"] = @(WPConfiguredTapAction(NO)==WPTapActionPartnerChat);
    WPSetConfiguredTapAction(NO, WPTapActionQuickChat);
    NSDictionary *diagnostics = WPQuickChatMonitor.sharedMonitor.diagnostics;
    r[@"QC03_switchStartsPollingWithoutRestart"] = @([diagnostics[@"state"] isEqual:@"active"] && [diagnostics[@"route"] isEqual:@"index"]);
    WPQCAfter(.6, ^{
        r[@"QC04_existingUnreadShowsAvatarWithoutFlash"] = @(!dot.hidden && arrivals.hidden);
        r[@"QC05_unreadAvatarCenteredAbovePet"] = @(fabs(dot.center.x-pet.center.x)<.5 && CGRectGetMaxY(dot.frame)<=CGRectGetMinY(pet.frame)-6 && CGRectContainsRect(controller.view.bounds, dot.frame));
        [menu showAroundPoint:pet.center inBounds:controller.view.bounds];
        NSArray *buttons = [menu valueForKey:@"actionButtons"];
        BOOL hasHide = NO;
        for (id button in buttons) hasHide |= [[button valueForKey:@"actionIdentifier"] isEqual:@"hide"];
        r[@"QC06_onMenuHasFourItemsWithoutHide"] = @(buttons.count == 4 && !hasHide);
        BOOL apart = YES; for (UIView *a in buttons) for (UIView *b in buttons) if (a != b && CGRectIntersectsRect(a.frame, b.frame)) apart = NO;
        r[@"QC07_fourMenuItemsDoNotOverlap"] = @(apart);
        WPQCSnapshot(controller.view, @"quickchat-menu"); [menu cancel];
        if ([controller valueForKey:@"peeking"] && [[controller valueForKey:@"peeking"] boolValue]) [controller tap];
        WPQCAfter(.8, ^{
            NSUInteger routes = [MMMsgLogicManager.sharedManager routeCalls];
            [controller tap];
            NSArray *names = [bar.sessions valueForKey:@"username"];
            r[@"QC08_tapOpensBarInsteadOfPartnerChat"] = @(!bar.hidden && [MMMsgLogicManager.sharedManager routeCalls] == routes);
            // A bounded first page appears immediately; verify the complete
            // ordering after the asynchronous session scan publishes its result.
            r[@"QC10_aggregateEntryLeftOut"] = @(![names containsObject:@"brandsessionholder"]);
            r[@"QC32_foldedGroupAbsentEvenWhenInSessionList"] = @(![names containsObject:@"qc_folded@chatroom"] && [WPQCMockSessions.homeNames containsObject:@"qc_folded@chatroom"]);
            r[@"QC33_hiddenAndBoxRowsAbsent"] = @(![names containsObject:@"wxid_qc_hidden"] && ![names containsObject:@"wxid_qc_inbox"]);
            r[@"QC34_offHomeRowAbsent"] = @(![names containsObject:@"wxid_qc_offhome"] && ![WPQCMockSessions.homeNames containsObject:@"wxid_qc_offhome"]);
            WPQCAfter(.4, ^{
                UITableView *table = [bar valueForKey:@"table"];
                NSArray *completedNames=[bar.sessions valueForKey:@"username"];
                r[@"QC09_barFollowsWeChatOrderPinnedFirst"] = @(completedNames.count == 39 && [completedNames[0] isEqual:@"wxid_qc_pinned"] && [completedNames[1] isEqual:@"qc_family@chatroom"] && [completedNames[2] isEqual:@"wxid_qc_friend"]);
                UITableViewCell *family = [table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]];
                UITableViewCell *pinned = [table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
                r[@"QC11_rowsShowNamesAndRedDots"] = @([[family valueForKey:@"name"] text].length && ![[family valueForKey:@"dot"] isHidden] && [[pinned valueForKey:@"dot"] isHidden] && [[[pinned valueForKey:@"name"] text] isEqual:@"置顶好友"]);
                CGRect frame = bar.frame;
                r[@"QC12_barOnLeftEdgeBetweenBars"] = @(CGRectGetMinX(frame) <= controller.view.safeAreaInsets.left + .5 && CGRectGetMinY(frame) >= controller.view.safeAreaInsets.top + 43 && CGRectGetMaxY(frame) <= CGRectGetMaxY(controller.view.bounds) - controller.view.safeAreaInsets.bottom - 48);
                UIImageView *pinnedAvatar = [pinned valueForKey:@"avatar"];
                r[@"QC27_leftAvatarVisibleBeforeHeadLoads"] = @(pinnedAvatar.image != nil && pinnedAvatar.bounds.size.width >= 48 && CGRectContainsRect(pinned.contentView.bounds, pinnedAvatar.frame) && WPCachedSharedChatAvatar(@"wxid_qc_pinned") == nil);
                [WPQCMockDelayedHeads removeObject:@"wxid_qc_pinned"];
                WPQCSnapshot(controller.view, @"quickchat-bar-light");
                overlay.overrideUserInterfaceStyle = UIUserInterfaceStyleDark; host.view.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
                WPQCAfter(1.9, ^{
                    UIImage *loaded = WPCachedSharedChatAvatar(@"wxid_qc_pinned");
                    r[@"QC28_visibleAvatarRefreshesAfterHeadLoads"] = @(loaded != nil && pinnedAvatar.image == loaded && !bar.hidden);
                    r[@"QC38_avatarDecodeLimitedTo160Pixels"] = @(loaded.CGImage && MAX(CGImageGetWidth(loaded.CGImage),CGImageGetHeight(loaded.CGImage))<=160);
                    NSDictionary *shared=WPPreviewSharedAvatarState();
                    r[@"QC39_sharedAvatarCacheHasBoundedCostAndConcurrency"] = @([shared[@"cached"] unsignedIntegerValue]<=16 && [shared[@"bytes"] unsignedIntegerValue]<=1536*1024 && [shared[@"active"] unsignedIntegerValue]<=2);
                    WPQCSnapshot(controller.view, @"quickchat-avatar-loaded");
                    UIColor *background = [bar.backgroundColor resolvedColorWithTraitCollection:bar.traitCollection]; CGFloat white = 1, alpha = 1; [background getWhite:&white alpha:&alpha];
                    r[@"QC13_darkModeBarIsDark"] = @(white < .3);
                    WPQCSnapshot(controller.view, @"quickchat-bar-dark");
                    overlay.overrideUserInterfaceStyle = UIUserInterfaceStyleUnspecified; host.view.window.overrideUserInterfaceStyle = UIUserInterfaceStyleUnspecified;
                    NSUInteger before = [MMMsgLogicManager.sharedManager routeCalls];
                    [table.delegate tableView:table didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:2 inSection:0]];
                    WPQCAfter(.7, ^{
                        r[@"QC14_tapAvatarOpensThatChatAndCloses"] = @([MMMsgLogicManager.sharedManager routeCalls] == before + 1 && [[MMMsgLogicManager.sharedManager lastContact].m_nsUsrName isEqual:@"wxid_qc_friend"] && bar.hidden);
                        r[@"QC40_hiddenBarCancelsDownloadsAndTimer"] = @([[bar valueForKey:@"avatarDownloads"] count]==0 && [bar valueForKey:@"avatarRefreshTimer"]==nil);
                        [host popToRootViewControllerAnimated:NO];
                        [controller tap];
                        [table.delegate tableView:table didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]];
                        WPQCAfter(.7, ^{
                            r[@"QC15_groupChatOpens"] = @([[MMMsgLogicManager.sharedManager lastContact].m_nsUsrName isEqual:@"qc_family@chatroom"]);
                            [host popToRootViewControllerAnimated:NO];
                            [WPQCMockSessions row:@"wxid_qc_friend"].m_uUnReadCount = 0;
                            [WPQCMockSessions row:@"qc_family@chatroom"].m_uUnReadCount = 6;
                            WPQCAfter(2.6, ^{
                                r[@"QC16_readAllButMutedClearsUnreadAvatar"] = @(dot.hidden);
                                r[@"QC17_mutedMessageDoesNotFlash"] = @(arrivals.hidden);
                                // Wait for the pet to tuck into the edge, then a friend writes.
                                WPQCAfter(3.6, ^{
                                    BOOL wasPeeking = [[controller valueForKey:@"peeking"] boolValue];
                                    MMSessionInfo *friend = [WPQCMockSessions row:@"wxid_qc_friend"]; [WPQCMockSessions.rows removeObject:friend];
                                    friend.m_uUnReadCount = 1; [WPQCMockSessions.rows insertObject:friend atIndex:1];
                                    [WPQuickChatMonitor.sharedMonitor tick]; // the next poll, without waiting up to 2 s
                                    WPQCAfter(.1, ^{
                                        r[@"QC18_newMessageFlashesWithAvatar"] = @(!arrivals.hidden && arrivals.subviews.count == 1 && [pet.layer animationForKey:@"quickChatPulse"] != nil);
                                        scenarioDiagnostics[@"QC18"]=@{@"arrivalsVisible":@(!arrivals.hidden),@"senderAvatarCount":@(arrivals.subviews.count),@"pulsePresent":@([pet.layer animationForKey:@"quickChatPulse"]!=nil),@"flashEnabled":@(WPQuickChatFlashEnabled()),@"quickChatEnabled":@(WPQuickChatEnabled())};
                                        r[@"QC19_newMessageBringsPetOutOfEdge"] = @(wasPeeking && ![[controller valueForKey:@"peeking"] boolValue]);
                                        r[@"QC20_newMessageShowsUnreadAvatar"] = @(!dot.hidden);
                                        WPQCSnapshot(controller.view, @"quickchat-arrival");
                                        // Exercise the same persisted visibility preference as the
                                        // settings switch; hiding must not schedule an auto-return.
                                        [defaults setBool:NO forKey:@"enabled"];
                                        [NSNotificationCenter.defaultCenter postNotificationName:WPSettingsDidChangeNotification object:nil];
                                        r[@"QC21_settingsHideRemovesPetDotsAndAnimation"] = @(controller.view.hidden && pet.hidden && dot.hidden && arrivals.hidden && [pet valueForKey:@"displayLink"] == nil && [overlay hitTest:pet.center withEvent:nil] == nil);
                                        r[@"QC45_hiddenPetStopsQuickChatPolling"] = @([WPQuickChatMonitor.sharedMonitor.diagnostics[@"state"] isEqual:@"inactive"]);
                                        MMSessionInfo *pinnedRow = WPQCMockSessions.rows.firstObject; pinnedRow.m_uUnReadCount = 2;
                                        [WPQuickChatMonitor.sharedMonitor tick];
                                        WPQCAfter(10.6, ^{
                                            r[@"QC22_staysHiddenBeyondTenSeconds"] = @(controller.view.hidden && pet.hidden && [pet valueForKey:@"displayLink"] == nil);
                                            r[@"QC24_messagesWhileHiddenDoNotFlash"] = @(arrivals.hidden && [pet.layer animationForKey:@"quickChatPulse"] == nil);
                                            [defaults setBool:YES forKey:@"enabled"];
                                            [NSNotificationCenter.defaultCenter postNotificationName:WPSettingsDidChangeNotification object:nil];
                                            WPQCAfter(.6, ^{
                                                r[@"QC23_manualShowRestoresPetAndUnreadAvatar"] = @(!controller.view.hidden && !pet.hidden && !dot.hidden && [pet valueForKey:@"displayLink"] != nil);
                                                r[@"QC46_showingPetResumesQuickChatPolling"] = @([WPQuickChatMonitor.sharedMonitor.diagnostics[@"state"] isEqual:@"active"]);
                                                WPResetQuickChatTapActions();
                                                [defaults setBool:NO forKey:@"quickChatEnabled"];
                                                [NSNotificationCenter.defaultCenter postNotificationName:WPSettingsDidChangeNotification object:nil];
                                                if ([[controller valueForKey:@"peeking"] boolValue]) [controller tap];
                                                [controller tap];
                                                WPQCAfter(.7, ^{
                                                    r[@"QC25_chatBarOffRestoresNativePartnerSheetKeepsOtherUnreadAvatar"] = @(bar.hidden && !dot.hidden && [WPResizableChatController coordinatorForController:host.presentedViewController]!=nil && [WPChatPresentationActiveUsernameInWindow(host.view.window) isEqual:@"wxid_qc_pinned"]);
                                                    [host dismissViewControllerAnimated:NO completion:nil];
                                                    BOOL stillMonitoring=[WPQuickChatMonitor.sharedMonitor.diagnostics[@"state"] isEqual:@"active"];
                                                    [defaults setBool:NO forKey:@"unreadAvatarEnabled"];
                                                    [NSNotificationCenter.defaultCenter postNotificationName:WPSettingsDidChangeNotification object:nil];
                                                    r[@"QC26_bothFeaturesOffStopsPollingAndHidesAvatar"] = @(stillMonitoring && [WPQuickChatMonitor.sharedMonitor.diagnostics[@"state"] isEqual:@"inactive"] && dot.hidden);
                                                    [defaults setBool:YES forKey:@"unreadAvatarEnabled"];
                                                    [host popToRootViewControllerAnimated:NO];
                                                    [defaults setBool:YES forKey:@"quickChatEnabled"];
                                                    WPSetConfiguredTapAction(NO, WPTapActionQuickChat);
                                                    WPSetConfiguredTapAction(YES, WPTapActionPartnerChat);
                                                    [NSNotificationCenter.defaultCenter postNotificationName:WPSettingsDidChangeNotification object:nil];
                                                    if ([[controller valueForKey:@"peeking"] boolValue]) [controller tap];
                                                    NSUInteger singleRoutes = [MMMsgLogicManager.sharedManager routeCalls];
                                                    [controller tap];
                                                    r[@"QC29_configuredSingleTapOpensQuickChat"] = @(!bar.hidden && [MMMsgLogicManager.sharedManager routeCalls] == singleRoutes);
                                                    [controller tap]; // close before testing the other gesture
                                                    WPQCAfter(.3, ^{
                                                        WPSetConfiguredTapAction(NO, WPTapActionPartnerChat);
                                                        WPSetConfiguredTapAction(YES, WPTapActionQuickChat);
                                                        if ([[controller valueForKey:@"peeking"] boolValue]) [controller doubleTap];
                                                        NSUInteger doubleRoutes = [MMMsgLogicManager.sharedManager routeCalls];
                                                        [controller doubleTap];
                                                        r[@"QC30_configuredDoubleTapOpensQuickChat"] = @(!bar.hidden && [MMMsgLogicManager.sharedManager routeCalls] == doubleRoutes);
                                                        [controller doubleTap];
                                                        WPQCAfter(.3, ^{
                                                            NSString *latest=[WPQuickChatMonitor.sharedMonitor latestUnreadUsername];
                                                            r[@"QC35_latestUnreadIgnoresPinnedMutedAndFolded"] = @([latest isEqual:@"wxid_qc_friend"]);
                                                            CGPoint touch=[controller.view convertPoint:CGPointMake(dot.center.x+13,dot.center.y) toView:overlay];
                                                            r[@"QC36_unreadAvatarHasTouchableTarget"] = @(!dot.hidden && [dot isKindOfClass:UIControl.class] && [overlay hitTest:touch withEvent:nil]==dot);
                                                            NSUInteger routesBeforeDot=QuickReplyMsgMgr.sharedManager.routeCalls;
                                                            [(UIControl *)dot sendActionsForControlEvents:UIControlEventTouchUpInside];
                                                            WPQCWaitUntil(^BOOL{return [WPChatPresentationActiveUsernameInWindow([controller valueForKey:@"hostWindow"]) isEqual:@"wxid_qc_friend"] && !host.presentedViewController.isBeingPresented && [WPResizableChatController coordinatorForController:host.presentedViewController]!=nil;},CACurrentMediaTime()+2,^(BOOL opened){
                                                            r[@"QC37_unreadAvatarOpensLatestUnreadChat"] = @(opened && QuickReplyMsgMgr.sharedManager.routeCalls==routesBeforeDot+1 && [WPResizableChatController coordinatorForController:host.presentedViewController]!=nil);
                                                            scenarioDiagnostics[@"QC37"]=@{@"opened":@(opened),@"routesBefore":@(routesBeforeDot),@"routesAfter":@(QuickReplyMsgMgr.sharedManager.routeCalls),@"actual":WPChatPresentationActiveUsernameInWindow([controller valueForKey:@"hostWindow"])?:@"none",@"hasResize":@([WPResizableChatController coordinatorForController:host.presentedViewController]!=nil)};
                                                            [defaults removeObjectForKey:@"partnerUsername"];
                                                            [defaults removeObjectForKey:@"enabled"];
                                                            [defaults removeObjectForKey:@"quickChatEnabled"];
                                                            [defaults removeObjectForKey:@"unreadAvatarEnabled"];
                                                            [defaults removeObjectForKey:@"singleTapAction"];
                                                            [defaults removeObjectForKey:@"doubleTapAction"];
                                                            if(originalFlash==NSNull.null)[defaults removeObjectForKey:@"quickChatFlash"];else [defaults setObject:originalFlash forKey:@"quickChatFlash"];
                                                            id restoredFlash=[defaults persistentDomainForName:@"dev.zhour.wechatpet"][@"quickChatFlash"] ?: NSNull.null;
                                                            scenarioDiagnostics[@"restoredFlashPreference"]=restoredFlash;
                                                            scenarioDiagnostics[@"flashRestoredExactly"]=@([restoredFlash isEqual:originalFlash]);
                                                            [[NSJSONSerialization dataWithJSONObject:scenarioDiagnostics options:NSJSONWritingPrettyPrinted error:nil] writeToFile:[WPDataDirectory() stringByAppendingPathComponent:@"quickchat-regression-diagnostics.json"] atomically:YES];
                                                            [NSNotificationCenter.defaultCenter postNotificationName:WPSettingsDidChangeNotification object:nil];
                                                            WPQCMockSessions.corruptCount=YES;WPQCMockSessions.indexReads=0;
                                                            NSArray *bounded=[WPQuickChatMonitor.sharedMonitor currentSessions];
                                                            r[@"QC41_corruptSessionCountBounded"] = @(bounded.count==39 && WPQCMockSessions.indexReads<=10000);
                                                            WPQCMockSessions.corruptCount=NO;
                                                            [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidReceiveMemoryWarningNotification object:nil];
                                                            NSDictionary *trimmed=WPPreviewSharedAvatarState();
                                                            r[@"QC42_memoryWarningPurgesSharedCacheAndJobs"] = @([trimmed[@"cached"] unsignedIntegerValue]==0 && [trimmed[@"jobs"] unsignedIntegerValue]==0 && [trimmed[@"bytes"] unsignedIntegerValue]==0);
                                                            __weak WPQuickChatBar *weakBar;
                                                            @autoreleasepool {WPQuickChatBar *temporary=[[WPQuickChatBar alloc] initWithFrame:CGRectMake(0,0,76,200)];[host.view addSubview:temporary];weakBar=temporary;[temporary removeFromSuperview];}
                                                            r[@"QC43_detachedBarCanDeallocate"] = @(weakBar==nil);
                                                            dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
                                                                BOOL safe=[WPQuickChatMonitor.sharedMonitor currentSessions]==nil && WPQuickChatAvatar(@"wxid_qc_friend")==nil && WPQuickChatAvatarURL(@"wxid_qc_friend")==nil;
                                                                dispatch_async(dispatch_get_main_queue(),^{r[@"QC44_backgroundReadsFailSafely"]=@(safe);deliver(r);});
                                                            });
                                                            });
                                                        });
                                                    });
                                                });
                                            });
                                        });
                                    });
                                });
                            });
                        });
                    });
                });
            });
        });
    });
}

@interface UIViewController (WPUnreadAvatarTesting)
- (CGRect)safeArea;
- (CGPoint)clamp:(CGPoint)point;
- (void)layoutBadge;
- (void)resetIdle;
- (BOOL)canPeek;
- (void)revealPet;
- (void)closeQuickChat;
- (void)showMessage:(NSString *)message;
- (void)showArrivals:(NSArray<NSString *> *)usernames;
@end
@interface WPOverlayManager (WPUnreadAvatarTesting)
- (void)closePanel;
@end

static UIView *WPUAFind(UIView *view,NSString *identifier) {
    if([view.accessibilityIdentifier isEqual:identifier])return view;
    for(UIView *child in view.subviews){UIView *found=WPUAFind(child,identifier);if(found)return found;}
    return nil;
}
static BOOL WPUAFiniteRect(CGRect rect) {
    return isfinite(rect.origin.x) && isfinite(rect.origin.y) && isfinite(rect.size.width) && isfinite(rect.size.height) && rect.size.width>0 && rect.size.height>0;
}

/// Uses the real overlay, real settings controls and the same mock avatar URL
/// transport as the chat-bar checks. No synthetic unread state is written into
/// the monitor: all changes enter through WeChat-style session rows.
@interface WPUnreadAvatarPreviewRunner : NSObject
@property(nonatomic,copy) void (^completion)(NSDictionary *results);
@property(nonatomic) NSMutableDictionary *results;
@property(nonatomic) UIWindow *overlay;
@property(nonatomic) UIViewController *controller;
@property(nonatomic) WPPetRenderer *pet;
@property(nonatomic) WPUnreadAvatarControl *avatar;
@property(nonatomic) NSDictionary *previousPreferences;
@property(nonatomic) id changeObserver;
@property(nonatomic) NSUInteger changes;
@property(nonatomic) NSUInteger arrivals;
@property(nonatomic) BOOL finished;
- (void)start;
@end

@implementation WPUnreadAvatarPreviewRunner
- (void)check:(NSString *)name passed:(BOOL)passed {self.results[name]=@(passed);}
- (void)after:(NSTimeInterval)seconds do:(void (^)(void))block {
    WPQCAfter(seconds,^{if(self.finished)return;@try{block();}@catch(__unused NSException *exception){[self check:@"UA_NoException" passed:NO];[self finish];}});
}
- (void)waitFor:(BOOL (^)(void))predicate seconds:(NSTimeInterval)seconds completion:(void (^)(BOOL))completion {
    [self waitFor:predicate deadline:CACurrentMediaTime()+seconds completion:completion];
}
- (void)waitFor:(BOOL (^)(void))predicate deadline:(CFTimeInterval)deadline completion:(void (^)(BOOL))completion {
    if(predicate()){completion(YES);return;}
    if(CACurrentMediaTime()>=deadline){completion(NO);return;}
    [self after:.03 do:^{[self waitFor:predicate deadline:deadline completion:completion];}];
}
- (UIImageView *)imageView {return [self.avatar valueForKey:@"avatarView"];}
- (BOOL)cancelled {return [self.avatar valueForKey:@"preparation"]==nil && [self.avatar valueForKey:@"download"]==nil && [self.avatar valueForKey:@"retryTimer"]==nil;}
- (void)settingsChanged {[NSNotificationCenter.defaultCenter postNotificationName:WPSettingsDidChangeNotification object:nil];}
- (void)tick {[WPQuickChatMonitor.sharedMonitor tick];}
- (void)positionPet {
    [self.controller closeQuickChat];[(WPRadialMenuView *)[self.controller valueForKey:@"menu"] cancel];
    ((UILabel *)[self.controller valueForKey:@"bubble"]).hidden=YES;
    ((UIView *)[self.controller valueForKey:@"arrivals"]).hidden=YES;
    CGRect safe=[self.controller safeArea];
    CGPoint point=[self.controller clamp:CGPointMake(CGRectGetMinX(safe)+self.pet.bounds.size.width/2,CGRectGetMidY(safe))];
    // Match a real completed drag: 1.1.0 keeps the intended anchor separate
    // from its temporary keyboard/indicator clamps.
    CGPoint anchor=CGPointMake(point.x/self.controller.view.bounds.size.width,point.y/self.controller.view.bounds.size.height);
    WPStorePositionAnchor(anchor,self.controller.view.bounds.size);
    [self.controller setValue:[NSValue valueWithCGPoint:anchor] forKey:@"userAnchor"];
    self.pet.center=point;[self.controller setValue:[NSValue valueWithCGPoint:point] forKey:@"fullCenter"];
    [self.controller.view setNeedsLayout];[self.controller.view layoutIfNeeded];
}
- (void)start {
    self.results=[NSMutableDictionary new];self.controller=self.overlay.rootViewController;
    self.pet=[self.controller valueForKey:@"pet"];self.avatar=[self.controller valueForKey:@"unreadDot"];
    NSArray *keys=@[@"enabled",@"quickChatEnabled",@"quickChatFlash",@"autoPeek",@"allowUnreadPeek",@"unreadAvatarEnabled",@"unreadAvatarOffsetX",@"unreadAvatarOffsetY",@"interactionBadgeOffsetX",@"interactionBadgeOffsetY",@"petSize",@"petOpacity",@"positionX",@"positionY",@"positionPortraitX",@"positionPortraitY",@"positionLandscapeX",@"positionLandscapeY"];
    NSDictionary *persistent=[WPPreferences() persistentDomainForName:@"dev.zhour.wechatpet"];
    NSMutableDictionary *saved=[NSMutableDictionary new];for(NSString *key in keys)saved[key]=persistent[key] ?: NSNull.null;
    self.previousPreferences=saved;
    [WPPreferences() removeObjectForKey:@"unreadAvatarEnabled"];
    [self check:@"UA01_UnreadAvatarEnabledByDefault" passed:WPUnreadAvatarEnabled()];
    [WPPreferences() setBool:YES forKey:@"enabled"];[WPPreferences() setBool:NO forKey:@"quickChatEnabled"];
    [WPPreferences() setBool:NO forKey:@"quickChatFlash"];[WPPreferences() setBool:YES forKey:@"autoPeek"];
    [WPPreferences() setBool:NO forKey:@"allowUnreadPeek"];
    [WPPreferences() setDouble:88 forKey:@"petSize"];
    for(NSString *key in @[@"unreadAvatarOffsetX",@"unreadAvatarOffsetY",@"interactionBadgeOffsetX",@"interactionBadgeOffsetY"])[WPPreferences() removeObjectForKey:key];
    WPPreviewResetSharedAvatarState();[WPQCMockDelayedHeads addObject:@"wxid_qc_friend"];
    [self.avatar clearAvatar];[self settingsChanged];[self positionPet];[self tick];
    __weak typeof(self) weakSelf=self;
    self.changeObserver=[NSNotificationCenter.defaultCenter addObserverForName:WPQuickChatDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note){weakSelf.changes++;weakSelf.arrivals+=[note.userInfo[@"arrivals"] count];}];
    [self after:.15 do:^{
        [self check:@"UA02_QuickChatOffStillMonitorsUnread" passed:!WPQuickChatEnabled() && [WPQuickChatMonitor.sharedMonitor.diagnostics[@"state"] isEqual:@"active"] && !self.avatar.hidden];
        [self check:@"UA03_LatestExcludesFoldedHiddenBoxOffHomeAndMuted" passed:[WPQuickChatMonitor.sharedMonitor.latestObservedUnreadUsername isEqual:@"wxid_qc_friend"] && [self.avatar.username isEqual:@"wxid_qc_friend"]];
        [self check:@"UA04_DefaultAvatarAbovePetWith44PointTouch" passed:fabs(self.avatar.center.x-self.pet.center.x)<.5 && CGRectGetMaxY(self.avatar.frame)<=CGRectGetMinY(self.pet.frame)-6 && self.imageView.bounds.size.width==36 && [self.avatar pointInside:CGPointMake(self.avatar.bounds.size.width/2+21,self.avatar.bounds.size.height/2) withEvent:nil]];
        [self check:@"UA05_PlaceholderVisibleWhileAvatarLoads" passed:!self.imageView.image && !((UILabel *)[self.avatar valueForKey:@"placeholderLabel"]).hidden && ((UILabel *)[self.avatar valueForKey:@"placeholderLabel"]).text.length>0 && [self.avatar valueForKey:@"preparation"]!=nil];
        [self check:@"UA06_UnreadPreventsEdgeHiding" passed:![self.controller canPeek] && ![[self.controller valueForKey:@"peeking"] boolValue]];
        [WPPreferences() setBool:YES forKey:@"allowUnreadPeek"];[self settingsChanged];
        [self check:@"UA33_UnreadPeekOptionKeepsAvatarAndAllowsEdgeHiding" passed:[self.controller canPeek] && !self.avatar.hidden && [self.avatar.username isEqual:@"wxid_qc_friend"]];
        [WPPreferences() setBool:NO forKey:@"allowUnreadPeek"];[self settingsChanged];
        [WPQCMockDelayedHeads removeObject:@"wxid_qc_friend"];
        [self waitFor:^BOOL{return self.imageView.image.CGImage!=nil;} seconds:2 completion:^(BOOL loaded){
            [self check:@"UA07_AsyncAvatarReplacesPlaceholderAndIsBounded" passed:loaded && ((UILabel *)[self.avatar valueForKey:@"placeholderLabel"]).hidden && MAX(CGImageGetWidth(self.imageView.image.CGImage),CGImageGetHeight(self.imageView.image.CGImage))<=160];
            [self delayedIdentityChecks];
        }];
    }];
}
- (void)delayedIdentityChecks {
    [WPQCMockDelayedHeads addObject:@"wxid_qc_pinned"];
    MMSessionInfo *pinned=[WPQCMockSessions row:@"wxid_qc_pinned"];
    pinned.m_uUnReadCount=2;pinned.m_uLastTime=600;[self tick];
    [self check:@"UA08_PinnedUnreadCanBeNewestByMessageTime" passed:[self.avatar.username isEqual:@"wxid_qc_pinned"] && self.imageView.image==nil];
    id oldRequest=[self.avatar valueForKey:@"preparation"];
    MMSessionInfo *friend=[WPQCMockSessions row:@"wxid_qc_friend"];friend.m_uLastTime=700;[self tick];
    [self waitFor:^BOOL{return [self.avatar.username isEqual:@"wxid_qc_friend"] && self.imageView.image.CGImage!=nil;} seconds:2 completion:^(BOOL loaded){
        UIImage *latest=self.imageView.image;
        [WPQCMockDelayedHeads removeObject:@"wxid_qc_pinned"];
        [self after:.25 do:^{
            [self check:@"UA09_OldAvatarCompletionCannotReplaceNewIdentity" passed:loaded && [self.avatar.username isEqual:@"wxid_qc_friend"] && self.imageView.image==latest && oldRequest!=nil && [[oldRequest valueForKey:@"cancelled"] boolValue]];
            NSUInteger before=self.changes,arrivals=self.arrivals;
            friend.m_uUnReadCount=0;[self tick];
            [self check:@"UA10_ReadingLatestPublishesNextWithoutArrival" passed:self.changes>before && self.arrivals==arrivals && [self.avatar.username isEqual:@"wxid_qc_pinned"]];
            MMSessionInfo *family=[WPQCMockSessions row:@"qc_family@chatroom"];
            family.m_bShowUnReadAsRedDot=NO;family.m_uLastTime=800;[self tick];
            BOOL groupShown=[self.avatar.username isEqual:@"qc_family@chatroom"];
            before=self.changes;arrivals=self.arrivals;family.m_isFolding=YES;[self tick];
            [self check:@"UA11_FoldingLatestGroupPublishesNextWithoutArrival" passed:groupShown && self.changes>before && self.arrivals==arrivals && [self.avatar.username isEqual:@"wxid_qc_pinned"]];
            friend.m_uUnReadCount=1;friend.m_uLastTime=900;
            UIWindow *hostWindow=[self.controller valueForKey:@"hostWindow"];UINavigationController *host=(id)hostWindow.rootViewController;
            [self.avatar sendActionsForControlEvents:UIControlEventTouchUpInside];
            [self waitFor:^BOOL{return host.presentedViewController && !host.presentedViewController.isBeingPresented && [WPResizableChatController coordinatorForController:host.presentedViewController]!=nil;} seconds:2 completion:^(BOOL opened){
                [self check:@"UA12_AvatarTapRevalidatesLatestBeforeRouting" passed:opened && [WPChatPresentationActiveUsernameInWindow(hostWindow) isEqual:@"wxid_qc_friend"]];
                [self check:@"UA35_SuccessfulAvatarOpenClearsIndicator" passed:opened && self.avatar.hidden && self.avatar.username.length==0];
                void (^next)(void)=^{if([host isKindOfClass:UINavigationController.class])[host popToRootViewControllerAnimated:NO];[self readAllAndPeek];};
                if(host.presentedViewController)[host dismissViewControllerAnimated:NO completion:next];else next();
            }];
        }];
    }];
}
- (void)readAllAndPeek {
    for(MMSessionInfo *row in WPQCMockSessions.rows)row.m_uUnReadCount=0;
    [self tick];[self positionPet];
    [self check:@"UA13_AllReadHidesAvatarAndAllowsPeek" passed:self.avatar.hidden && !WPQuickChatMonitor.sharedMonitor.latestObservedUnreadUsername && [self.controller canPeek]];
    [self.controller resetIdle];
    [self waitFor:^BOOL{return [[self.controller valueForKey:@"peeking"] boolValue];} seconds:3.8 completion:^(BOOL peeked){
        [self check:@"UA14_AllReadRestoresActualIdlePeek" passed:peeked];
        MMSessionInfo *friend=[WPQCMockSessions row:@"wxid_qc_friend"];friend.m_uUnReadCount=1;friend.m_uLastTime=950;[self tick];
        [self after:.75 do:^{
            [self check:@"UA15_UnreadRevealsWithoutChatBarOrFlash" passed:peeked && ![[self.controller valueForKey:@"peeking"] boolValue] && !self.avatar.hidden && ![self.controller canPeek] && CGRectContainsRect(self.controller.view.bounds,self.pet.frame) && ((UIView *)[self.controller valueForKey:@"arrivals"]).hidden];
            [self settingsControlsChecks];
        }];
    }];
}
- (void)settingsControlsChecks {
    WPOverlayManager *manager=WPOverlayManager.sharedManager;[manager openSettings];
    UIWindow *panel=[manager valueForKey:@"settingsWindow"];UINavigationController *navigation=(id)panel.rootViewController;
    UIViewController *page=[NSClassFromString(@"WPAppearanceSettingsController") new];[navigation pushViewController:page animated:NO];
    UISwitch *toggle=(id)WPUAFind(page.view,@"WPLatestUnreadAvatarSwitch");
    NSArray *ids=@[@"WPUnreadAvatarOffsetX",@"WPUnreadAvatarOffsetY",@"WPInteractionBadgeOffsetX",@"WPInteractionBadgeOffsetY"];
    BOOL sliders=YES;for(NSString *name in ids)sliders&=[WPUAFind(page.view,name) isKindOfClass:UISlider.class];
    [self check:@"UA16_AppearanceContainsFeatureSwitchAndFourSliders" passed:[toggle isKindOfClass:UISwitch.class] && toggle.isOn && sliders];
    CGPoint avatarBefore=self.avatar.center;
    UILabel *badgeNumber=[self.controller valueForKey:@"badgeNumber"];UIView *badge=[self.controller valueForKey:@"badge"];
    badgeNumber.text=@"123";[self.controller layoutBadge];CGPoint badgeBefore=badge.center;
    NSArray *values=@[@55,@40,@45,@35];
    for(NSUInteger index=0;index<ids.count;index++){UISlider *slider=(id)WPUAFind(page.view,ids[index]);slider.value=[values[index] floatValue];[slider sendActionsForControlEvents:UIControlEventValueChanged];}
    badgeNumber.text=@"123";[self.controller layoutBadge];
    [self check:@"UA17_RealSlidersImmediatelyMoveAvatarAndRedBadge" passed:fabs(self.avatar.center.x-avatarBefore.x-55)<.5 && fabs(self.avatar.center.y-avatarBefore.y-40)<.5 && fabs(badge.center.x-badgeBefore.x-45)<.5 && fabs(badge.center.y-badgeBefore.y-35)<.5];
    [page.view layoutIfNeeded];WPQCSnapshot(self.controller.view,@"unread-avatar-appearance-settings");
    toggle.on=NO;[toggle sendActionsForControlEvents:UIControlEventValueChanged];
    [self check:@"UA18_OffCancelsAvatarAndBothOffStopsPolling" passed:self.avatar.hidden && [self cancelled] && [WPQuickChatMonitor.sharedMonitor.diagnostics[@"state"] isEqual:@"inactive"] && self.imageView.image==nil];
    [self check:@"UA19_OffDisablesOnlyAvatarPositionSliders" passed:!((UISlider *)WPUAFind(page.view,ids[0])).enabled && !((UISlider *)WPUAFind(page.view,ids[1])).enabled && ((UISlider *)WPUAFind(page.view,ids[2])).enabled && ((UISlider *)WPUAFind(page.view,ids[3])).enabled];
    toggle=(id)WPUAFind(page.view,@"WPLatestUnreadAvatarSwitch");toggle.on=YES;[toggle sendActionsForControlEvents:UIControlEventValueChanged];
    [self waitFor:^BOOL{return !WPQuickChatEnabled() && [WPQuickChatMonitor.sharedMonitor.diagnostics[@"state"] isEqual:@"active"] && !self.avatar.hidden;} seconds:2 completion:^(BOOL resumed){
    [self check:@"UA20_OnRestartsUnreadMonitoringWithoutQuickChat" passed:resumed];
    id partnerBefore=[WPPreferences() objectForKey:@"partnerUsername"];
    double sizeBefore=[WPPreferences() doubleForKey:@"petSize"];
    UIButton *reset=(id)WPUAFind(page.view,@"WPResetIndicatorPositions");[reset sendActionsForControlEvents:UIControlEventTouchUpInside];
    BOOL offsets=CGPointEqualToPoint(WPUnreadAvatarOffset(),CGPointZero) && CGPointEqualToPoint(WPInteractionBadgeOffset(),CGPointZero);
    id partnerAfter=[WPPreferences() objectForKey:@"partnerUsername"];
    [self check:@"UA21_ResetOnlyClearsOffsetsKeepsFeaturePetAndPartner" passed:reset && offsets && WPUnreadAvatarEnabled() && [WPPreferences() doubleForKey:@"petSize"]==sizeBefore && (partnerBefore==partnerAfter || [partnerBefore isEqual:partnerAfter])];
    [manager closePanel];
    [self geometryChecks];
    }];
}
- (void)geometryChecks {
    BOOL finite=YES,inBounds=YES;
    UILabel *number=[self.controller valueForKey:@"badgeNumber"];UIFont *previous=number.font;
    for(NSNumber *size in @[@48,@160])for(NSNumber *direction in @[@-1,@1]){
        [WPPreferences() setDouble:size.doubleValue forKey:@"petSize"];
        for(NSString *key in @[@"unreadAvatarOffsetX",@"interactionBadgeOffsetX"])[WPPreferences() setDouble:direction.doubleValue*160 forKey:key];
        for(NSString *key in @[@"unreadAvatarOffsetY",@"interactionBadgeOffsetY"])[WPPreferences() setDouble:direction.doubleValue*200 forKey:key];
        [self settingsChanged];number.text=@"9999";number.font=[UIFont monospacedDigitSystemFontOfSize:direction.doubleValue>0?20:12 weight:UIFontWeightBold];
        CGRect safe=[self.controller safeArea];self.pet.center=[self.controller clamp:CGPointMake(direction.doubleValue>0?CGRectGetMaxX(safe):CGRectGetMinX(safe),direction.doubleValue>0?CGRectGetMaxY(safe):CGRectGetMinY(safe))];
        [self.controller setValue:[NSValue valueWithCGPoint:self.pet.center] forKey:@"fullCenter"];
        [self.controller layoutBadge];
        CGRect red=[number convertRect:number.bounds toView:self.controller.view];
        finite&=WPUAFiniteRect(self.avatar.frame) && WPUAFiniteRect(red);
        inBounds&=CGRectContainsRect(self.controller.view.bounds,self.avatar.frame) && CGRectContainsRect(self.controller.view.bounds,red);
    }
    number.font=previous;
    [self check:@"UA22_IndicatorGeometryStaysFiniteAtPetSizesAndOffsets" passed:finite];
    [self check:@"UA23_IndicatorsClampInsideScreenAtEdgesAndLargeCounts" passed:inBounds];
    [WPPreferences() setDouble:NAN forKey:@"unreadAvatarOffsetX"];[WPPreferences() setDouble:INFINITY forKey:@"interactionBadgeOffsetY"];
    [self check:@"UA24_InvalidOffsetPreferencesReturnFiniteDefaults" passed:WPUnreadAvatarOffset().x==0 && WPInteractionBadgeOffset().y==0];
    for(NSString *key in @[@"unreadAvatarOffsetX",@"unreadAvatarOffsetY",@"interactionBadgeOffsetX",@"interactionBadgeOffsetY"])[WPPreferences() removeObjectForKey:key];
    [WPPreferences() setDouble:88 forKey:@"petSize"];[self settingsChanged];[self positionPet];
    [self cancellationChecks];
}
- (void)cancellationChecks {
    WPPreviewResetSharedAvatarState();
    [WPQCMockDelayedHeads addObject:@"wxid_qc_friend"];
    [self.avatar clearAvatar];[self settingsChanged];
    BOOL pending=[self.avatar valueForKey:@"download"]!=nil || [self.avatar valueForKey:@"preparation"]!=nil;
    [WPPreferences() setBool:NO forKey:@"enabled"];[self settingsChanged];
    NSUInteger routes=[MMMsgLogicManager.sharedManager routeCalls];[self.avatar sendActionsForControlEvents:UIControlEventTouchUpInside];
    [self check:@"UA25_HidingPetCancelsAvatarAndDisablesRouting" passed:pending && self.avatar.hidden && [self cancelled] && [self.avatar valueForKey:@"preparation"]==nil && !self.imageView.image && [MMMsgLogicManager.sharedManager routeCalls]==routes && [WPQuickChatMonitor.sharedMonitor.diagnostics[@"state"] isEqual:@"inactive"]];
    [WPPreferences() setBool:YES forKey:@"enabled"];[self settingsChanged];
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidEnterBackgroundNotification object:nil];
    [self check:@"UA26_BackgroundCancelsAvatarAndPolling" passed:[self cancelled] && !self.imageView.image && [WPQuickChatMonitor.sharedMonitor.diagnostics[@"state"] isEqual:@"inactive"]];
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillEnterForegroundNotification object:nil];
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
    [WPOverlayManager.sharedManager refresh];
    [WPQCMockDelayedHeads removeObject:@"wxid_qc_friend"];
    [self waitFor:^BOOL{return !self.avatar.hidden && self.imageView.image.CGImage!=nil;} seconds:2 completion:^(BOOL restored){
        [self check:@"UA27_ForegroundRestoresCurrentAvatar" passed:restored && [self.avatar.username isEqual:@"wxid_qc_friend"]];
        __weak WPUnreadAvatarControl *weakAvatar;
        @autoreleasepool {
            WPUnreadAvatarControl *temporary=[[WPUnreadAvatarControl alloc] initWithFrame:CGRectMake(0,0,36,36)];
            [self.controller.view addSubview:temporary];[temporary setActive:YES];[temporary showUsername:@"wxid_qc_friend" title:@"周游"];weakAvatar=temporary;[temporary removeFromSuperview];
        }
        [self check:@"UA28_DetachedAvatarDoesNotRetainTimerOrDownloadCycle" passed:weakAvatar==nil];
        [self memoryWarningChecks];
    }];
}
- (void)memoryWarningChecks {
    NSString *identity=[self.avatar.username copy];
    UIImage *visibleImage=self.imageView.image;
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    BOOL retained=visibleImage!=nil && self.imageView.image==visibleImage && [self.avatar valueForKey:@"download"]==nil;
    [self waitFor:^BOOL{return self.imageView.image.CGImage!=nil;} seconds:3 completion:^(BOOL visible){
        BOOL sameIdentity=[identity isEqual:self.avatar.username];
        self.avatar.hidden=YES;
        [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidReceiveMemoryWarningNotification object:nil];
        BOOL hiddenNoRetry=[self cancelled] && self.imageView.image==nil;
        [self check:@"UA29_MemoryWarningKeepsVisibleSmallAvatarAndStopsWhenHidden" passed:retained && visible && sameIdentity && hiddenNoRetry];
        self.avatar.hidden=NO;[self.avatar setActive:YES];
        [self waitFor:^BOOL{return self.imageView.image.CGImage!=nil;} seconds:9 completion:^(BOOL loaded){
            [self check:@"UA34_CurrentAvatarRecoversAfterPressureCooldown" passed:loaded && [identity isEqual:self.avatar.username]];
            UILabel *number=[self.controller valueForKey:@"badgeNumber"];UIView *badge=[self.controller valueForKey:@"badge"];
            number.text=@"2";badge.hidden=NO;[self.controller layoutBadge];
            [self.controller showMessage:@"未读头像与互动提醒位置预览"];
            UIView *bubble=[self.controller valueForKey:@"bubble"];
            CGRect avatar=[self.avatar convertRect:self.avatar.bounds toView:self.controller.view];
            [self check:@"UA30_MessageBubbleAvoidsLatestUnreadAvatar" passed:!bubble.hidden && !CGRectIntersectsRect(bubble.frame,avatar) && CGRectContainsRect(self.controller.view.bounds,bubble.frame)];
            [self.controller showArrivals:@[@"wxid_qc_pinned"]];
            UIView *arrivals=[self.controller valueForKey:@"arrivals"];
            BOOL separated=!arrivals.hidden && !CGRectIntersectsRect(arrivals.frame,avatar) && !CGRectIntersectsRect(arrivals.frame,bubble.frame);
            bubble.hidden=YES;[self.controller layoutBadge];
            separated&=!CGRectIntersectsRect(arrivals.frame,avatar) && CGRectContainsRect(self.controller.view.bounds,arrivals.frame);
            [self check:@"UA31_ArrivalAvatarsAvoidUnreadAvatarAndBubble" passed:separated];
            bubble.hidden=NO;[self.controller layoutBadge];
            WPQCSnapshot(self.controller.view,@"unread-avatar-above-pet");
            [self check:@"UA_NoException" passed:YES];[self finish];
        }];
    }];
}
- (void)finish {
    if(self.finished)return;self.finished=YES;
    [NSNotificationCenter.defaultCenter removeObserver:self.changeObserver];
    [WPOverlayManager.sharedManager closePanel];
    [WPQCMockDelayedHeads removeObject:@"wxid_qc_friend"];[WPQCMockDelayedHeads removeObject:@"wxid_qc_pinned"];
    for(NSString *key in self.previousPreferences){id value=self.previousPreferences[key];if(value==NSNull.null)[WPPreferences() removeObjectForKey:key];else [WPPreferences() setObject:value forKey:key];}
    NSDictionary *restored=[WPPreferences() persistentDomainForName:@"dev.zhour.wechatpet"];
    BOOL restoredExactly=YES;for(NSString *key in self.previousPreferences)restoredExactly&=[self.previousPreferences[key] isEqual:restored[key] ?: NSNull.null];
    NSDictionary *preferenceAudit=@{@"originalFlashPreference":self.previousPreferences[@"quickChatFlash"] ?: NSNull.null,
        @"restoredFlashPreference":restored[@"quickChatFlash"] ?: NSNull.null,@"restoredAllTrackedPreferences":@(restoredExactly)};
    [[NSJSONSerialization dataWithJSONObject:preferenceAudit options:NSJSONWritingPrettyPrinted error:nil] writeToFile:[WPDataDirectory() stringByAppendingPathComponent:@"unread-avatar-preferences.json"] atomically:YES];
    [self settingsChanged];[WPOverlayManager.sharedManager refresh];
    void (^completion)(NSDictionary *)=self.completion;self.completion=nil;if(completion)completion(self.results);
}
@end

void WPUnreadAvatarRunPreviewTests(UIWindow *overlay,void (^completion)(NSDictionary *results)) {
    NSCAssert(NSThread.isMainThread,@"Unread-avatar UIKit checks run on main");
    WPUnreadAvatarPreviewRunner *runner=[WPUnreadAvatarPreviewRunner new];runner.overlay=overlay;runner.completion=completion;[runner start];
}

#endif
