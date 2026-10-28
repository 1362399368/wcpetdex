#import "WPWeChatSettingsEntry.h"
#import "WPOverlay.h"
#import "WPSettings.h"
#import "WPEdition.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <stdlib.h>
#include <string.h>

// Use WeChat's own section and cell models. This is the same kind of Settings
// entry that plugin collectors can move into their consolidated list.
static const void *kWPSettingsSectionKey = &kWPSettingsSectionKey;
static const void *kWPSettingsInsertionKey = &kWPSettingsInsertionKey;
static void (*sOriginalReloadTableData)(id, SEL);
static BOOL sSettingsHookInstalled;
static __weak id sRegisteredCollector;
static BOOL sCollectorRegistrationInProgress;

// WCPluginsMgr's published API accepts a controller *class name*. The child
// navigation keeps our existing panel-close actions scoped to our own root.
@interface WPZhouyouPluginSettingsController : UIViewController
@property(nonatomic,strong) UINavigationController *settingsNavigation;
@property(nonatomic) BOOL savedNavigationBarHidden;
@property(nonatomic) BOOL savedNavigationBarState;
@end

@implementation WPZhouyouPluginSettingsController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=@"SinglePet-zhour";
    WPSettingsController *settings=[WPSettingsController new];
    __weak typeof(self) weakSelf=self;
    settings.onClose=^{ [weakSelf closeSettings]; };
    self.settingsNavigation=[[UINavigationController alloc] initWithRootViewController:settings];
    [self addChildViewController:self.settingsNavigation];
    self.settingsNavigation.view.frame=self.view.bounds;
    self.settingsNavigation.view.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.settingsNavigation.view];
    [self.settingsNavigation didMoveToParentViewController:self];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if(self.navigationController&&!self.savedNavigationBarState){
        self.savedNavigationBarHidden=self.navigationController.navigationBarHidden;
        self.savedNavigationBarState=YES;
    }
    [self.navigationController setNavigationBarHidden:YES animated:animated];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if(self.savedNavigationBarState)
        [self.navigationController setNavigationBarHidden:self.savedNavigationBarHidden animated:animated];
}
- (void)closeSettings {
    [self.view endEditing:YES];
    UINavigationController *navigation=self.navigationController;
    NSUInteger index=[navigation.viewControllers indexOfObjectIdenticalTo:self];
    if(navigation&&index!=NSNotFound&&index>0){
        [navigation popToViewController:navigation.viewControllers[index-1] animated:self.viewIfLoaded.window!=nil];
    } else if(self.presentingViewController) {
        [self dismissViewControllerAnimated:self.viewIfLoaded.window!=nil completion:nil];
    }
}
- (UIViewController *)childViewControllerForStatusBarStyle{return self.settingsNavigation;}
- (UIViewController *)childViewControllerForStatusBarHidden{return self.settingsNavigation;}
@end

static BOOL WPMethodMatches(Method method, unsigned int argumentCount, char returnType) {
    if (!method || method_getNumberOfArguments(method) != argumentCount) return NO;
    char type[8] = {0};
    method_getReturnType(method, type, sizeof(type));
    return type[0] == returnType;
}

static BOOL WPArgumentMatches(Method method, unsigned int index, const char *allowedTypes) {
    if (!method || index >= method_getNumberOfArguments(method)) return NO;
    char type[16] = {0};
    method_getArgumentType(method, index, type, sizeof(type));
    const char *cursor = type;
    while (*cursor && strchr("rnNoORV", *cursor)) cursor++;
    return *cursor && strchr(allowedTypes, *cursor) != NULL;
}

static NSString *WPCollectorControllerName(void) {
    return NSStringFromClass(WPZhouyouPluginSettingsController.class);
}

static BOOL WPRegisterCollectorClass(Class collectorClass) {
    if(!collectorClass||sCollectorRegistrationInProgress)return NO;
    SEL shared=NSSelectorFromString(@"sharedInstance");
    Method factory=class_getClassMethod(collectorClass,shared);
    if(!WPMethodMatches(factory,2,'@'))return NO;
    @try {
        id manager=((id(*)(id,SEL))objc_msgSend)(collectorClass,shared);
        if(!manager)return NO;
        if(manager==sRegisteredCollector)return YES;
        SEL registration=NSSelectorFromString(@"registerControllerWithTitle:version:controller:");
        Method method=class_getInstanceMethod(object_getClass(manager),registration);
        if(!WPMethodMatches(method,5,'v')||!WPArgumentMatches(method,2,"@")||
           !WPArgumentMatches(method,3,"@")||!WPArgumentMatches(method,4,"@"))return NO;
        sCollectorRegistrationInProgress=YES;
        @try {
            ((void(*)(id,SEL,id,id,id))objc_msgSend)(manager,registration,
                @"SinglePet-zhour",WPPluginVersion(),WPCollectorControllerName());
        } @finally {sCollectorRegistrationInProgress=NO;}
        // A void registration returning normally is the published success
        // contract. Class presence or a singleton alone never hides our row.
        sRegisteredCollector=manager;
        return YES;
    } @catch(__unused NSException *exception) {
        return NO;
    }
}

static BOOL WPRegisterPluginCollector(void) {
    if(!NSThread.isMainThread)return NO;
    // Standard API: https://apt.25mao.com/view/116/nohistory . The Refine
    // implementation was also checked in the user's installed binary:
    // sharedInstance @16@0:8, registration v40@0:8@16@24@32.
    if(WPRegisterCollectorClass(objc_getClass("WCRefinePluginHubManager")))return YES;
    return WPRegisterCollectorClass(objc_getClass("WCPluginsMgr"));
}

static id WPObjectIvar(id object, const char *name) {
    for (Class cls = object_getClass(object); cls; cls = class_getSuperclass(cls)) {
        Ivar ivar = class_getInstanceVariable(cls, name);
        if (!ivar) continue;
        const char *type = ivar_getTypeEncoding(ivar);
        if (!type || type[0] != '@') return nil;
        return object_getIvar(object, ivar);
    }
    return nil;
}

static id WPTableManager(id controller) {
    static const char *names[] = {
        "m_tableViewMgr", "_m_tableViewMgr", "m_tableViewManager",
        "_m_tableViewManager", "m_tableViewInfo", "_m_tableViewInfo"
    };
    for (NSUInteger index = 0; index < sizeof(names) / sizeof(names[0]); index++) {
        id candidate = WPObjectIvar(controller, names[index]);
        if (candidate && ([candidate respondsToSelector:@selector(insertSection:At:)] ||
                          [candidate respondsToSelector:@selector(addSection:)])) return candidate;
    }
    static NSString *getters[] = {@"tableViewMgr", @"tableViewManager", @"tableViewInfo"};
    for (NSUInteger index = 0; index < sizeof(getters) / sizeof(getters[0]); index++) {
        SEL selector = NSSelectorFromString(getters[index]);
        Method method = class_getInstanceMethod(object_getClass(controller), selector);
        if (!WPMethodMatches(method, 2, '@')) continue;
        id candidate = ((id (*)(id, SEL))objc_msgSend)(controller, selector);
        if (candidate && ([candidate respondsToSelector:@selector(insertSection:At:)] ||
                          [candidate respondsToSelector:@selector(addSection:)])) return candidate;
    }
    return nil;
}

static id WPCallObjectGetter(id target, SEL selector) {
    Method method = class_getInstanceMethod(object_getClass(target), selector);
    if (!WPMethodMatches(method, 2, '@')) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(target, selector);
}

typedef NS_ENUM(NSInteger, WPSectionPresence) {
    WPSectionPresenceUnknown = -1,
    WPSectionPresenceAbsent = 0,
    WPSectionPresencePresent = 1
};

static WPSectionPresence WPSectionInModel(id manager, id section) {
    if (!section) return WPSectionPresenceAbsent;
    SEL sectionSelector = @selector(getSectionAt:);
    Method getter = class_getInstanceMethod(object_getClass(manager), sectionSelector);
    BOOL inspected = NO;
    if (WPMethodMatches(getter, 3, '@') && WPArgumentMatches(getter, 2, "qiQI")) {
        id table = WPCallObjectGetter(manager, @selector(getTableView));
        if ([table isKindOfClass:UITableView.class]) {
            UITableView *tableView = table;
            id<UITableViewDataSource> dataSource = tableView.dataSource;
            BOOL modelCountKnown = [dataSource respondsToSelector:@selector(numberOfSectionsInTableView:)];
            NSInteger count = modelCountKnown ? [dataSource numberOfSectionsInTableView:tableView]
                                              : tableView.numberOfSections;
            // A table with zero cached sections may not yet reflect the rebuilt
            // model. Only a positive data-source count can prove absence.
            if (modelCountKnown && count > 0 && count <= 64) inspected = YES;
            for (NSInteger index = 0; index < MIN(count, 64); index++) {
                @try {
                    id candidate = ((id (*)(id, SEL, NSInteger))objc_msgSend)(manager, sectionSelector, index);
                    if (candidate == section) return WPSectionPresencePresent;
                } @catch (__unused NSException *exception) { inspected = NO; break; }
            }
        }
    }

    // Some releases expose the section array as an ivar instead of a getter.
    for (Class cls = object_getClass(manager); cls; cls = class_getSuperclass(cls)) {
        unsigned int count = 0;
        Ivar *ivars = class_copyIvarList(cls, &count);
        for (unsigned int index = 0; index < count; index++) {
            const char *name = ivar_getName(ivars[index]);
            const char *type = ivar_getTypeEncoding(ivars[index]);
            if (!name || !strstr(name, "ection") || !type || type[0] != '@') continue;
            id value = object_getIvar(manager, ivars[index]);
            if ([value isKindOfClass:NSArray.class]) {
                inspected = YES;
                if ([value containsObject:section]) {
                    free(ivars);
                    return WPSectionPresencePresent;
                }
            }
        }
        free(ivars);
    }
    return inspected ? WPSectionPresenceAbsent : WPSectionPresenceUnknown;
}

static id WPNewCell(Class cellClass, id controller) {
    if (!cellClass) return nil;
    SEL action = NSSelectorFromString(@"wp_zhouyouOpenSettings");
    SEL selector = @selector(normalCellForSel:target:title:);
    Method method = class_getClassMethod(cellClass, selector);
    if (WPMethodMatches(method, 5, '@') && WPArgumentMatches(method, 2, ":") &&
        WPArgumentMatches(method, 3, "@") && WPArgumentMatches(method, 4, "@")) {
        return ((id (*)(id, SEL, SEL, id, id))objc_msgSend)(cellClass, selector,
            action, controller, @"SinglePet-zhour");
    }
    selector = @selector(normalCellForSel:target:title:accessoryType:);
    method = class_getClassMethod(cellClass, selector);
    if (WPMethodMatches(method, 6, '@') && WPArgumentMatches(method, 2, ":") &&
        WPArgumentMatches(method, 3, "@") && WPArgumentMatches(method, 4, "@") &&
        WPArgumentMatches(method, 5, "qiQI")) {
        return ((id (*)(id, SEL, SEL, id, id, NSInteger))objc_msgSend)(cellClass, selector,
            action, controller, @"SinglePet-zhour", UITableViewCellAccessoryDisclosureIndicator);
    }
    return nil;
}

static id WPNewSection(Class sectionClass, id cell) {
    if (!sectionClass || !cell) return nil;
    SEL factory = NSSelectorFromString(@"sectionInfoDefaut");
    Method method = class_getClassMethod(sectionClass, factory);
    if (!WPMethodMatches(method, 2, '@')) {
        factory = NSSelectorFromString(@"sectionInfoDefault");
        method = class_getClassMethod(sectionClass, factory);
    }
    if (!WPMethodMatches(method, 2, '@')) return nil;
    id section = ((id (*)(id, SEL))objc_msgSend)(sectionClass, factory);
    SEL addCell = @selector(addCell:);
    Method addMethod = section ? class_getInstanceMethod(object_getClass(section), addCell) : NULL;
    if (!WPMethodMatches(addMethod, 3, 'v') || !WPArgumentMatches(addMethod, 2, "@")) return nil;
    ((void (*)(id, SEL, id))objc_msgSend)(section, addCell, cell);
    return section;
}

static void WPInsertNativeSettingsRow(id controller) {
    if (![NSThread isMainThread]) return;
    if(WPRegisterPluginCollector())return;
    id manager = WPTableManager(controller);
    if (!manager) return;
    id previous = objc_getAssociatedObject(manager, kWPSettingsSectionKey);
    // Unknown layout means we keep the existing row rather than risk duplicates.
    if (previous && WPSectionInModel(manager, previous) != WPSectionPresenceAbsent) return;

    BOOL wcManager = [manager isKindOfClass:objc_getClass("WCTableViewManager")];
    Class sectionClass = objc_getClass(wcManager ? "WCTableViewSectionManager" : "MMTableViewSectionInfo");
    Class cellClass = objc_getClass(wcManager ? "WCTableViewCellManager" : "MMTableViewCellInfo");
    id section = WPNewSection(sectionClass, WPNewCell(cellClass, controller));
    if (!section) return;

    SEL insert = @selector(insertSection:At:);
    Method insertMethod = class_getInstanceMethod(object_getClass(manager), insert);
    if (WPMethodMatches(insertMethod, 4, 'v') && WPArgumentMatches(insertMethod, 2, "@") &&
        WPArgumentMatches(insertMethod, 3, "qiQI")) {
        ((void (*)(id, SEL, id, unsigned int))objc_msgSend)(manager, insert, section, 0);
    } else {
        SEL add = @selector(addSection:);
        Method addMethod = class_getInstanceMethod(object_getClass(manager), add);
        if (!WPMethodMatches(addMethod, 3, 'v') || !WPArgumentMatches(addMethod, 2, "@")) return;
        ((void (*)(id, SEL, id))objc_msgSend)(manager, add, section);
    }
    objc_setAssociatedObject(manager, kWPSettingsSectionKey, section, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    id table = WPCallObjectGetter(manager, @selector(getTableView));
    if ([table isKindOfClass:UITableView.class]) [(UITableView *)table reloadData];
    else {
        SEL reload = @selector(reloadTableView);
        Method method = class_getInstanceMethod(object_getClass(manager), reload);
        if (WPMethodMatches(method, 2, 'v'))
            ((void (*)(id, SEL))objc_msgSend)(manager, reload);
    }
}

static void WPSettingsReloadTableData(id controller, SEL selector) {
    if (sOriginalReloadTableData) sOriginalReloadTableData(controller, selector);
    if ([objc_getAssociatedObject(controller, kWPSettingsInsertionKey) boolValue]) return;
    objc_setAssociatedObject(controller, kWPSettingsInsertionKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    @try { WPInsertNativeSettingsRow(controller); }
    @catch (__unused NSException *exception) { /* A changed WeChat model should not break Settings. */ }
    @finally { objc_setAssociatedObject(controller, kWPSettingsInsertionKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
}

static void WPShowSettingsFromWeChat(id controller, SEL selector) {
    (void)controller; (void)selector;
    if ([NSThread isMainThread]) [[WPOverlayManager sharedManager] openSettings];
    else dispatch_async(dispatch_get_main_queue(), ^{ [[WPOverlayManager sharedManager] openSettings]; });
}

void WPInstallWeChatSettingsEntry(void) {
#ifndef WP_PREVIEW_HOST
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.tencent.xin"]) return;
#endif
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ WPInstallWeChatSettingsEntry(); });
        return;
    }
    WPRegisterPluginCollector();
    if (sSettingsHookInstalled) return;
    Class settingsClass = objc_getClass("NewSettingViewController");
    SEL reload = @selector(reloadTableData);
    Method method = settingsClass ? class_getInstanceMethod(settingsClass, reload) : NULL;
    if (!WPMethodMatches(method, 2, 'v')) return;

    SEL action = NSSelectorFromString(@"wp_zhouyouOpenSettings");
    if (!class_addMethod(settingsClass, action, (IMP)WPShowSettingsFromWeChat, "v@:")) return;

    sOriginalReloadTableData = (void (*)(id, SEL))method_getImplementation(method);
    const char *types = method_getTypeEncoding(method);
    if (!class_addMethod(settingsClass, reload, (IMP)WPSettingsReloadTableData, types)) {
        method_setImplementation(method, (IMP)WPSettingsReloadTableData);
    }
    sSettingsHookInstalled = YES;
}

#ifndef WP_PREVIEW_HOST
__attribute__((constructor)) static void WPSettingsEntryStart(void) {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.tencent.xin"]) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            WPInstallWeChatSettingsEntry();
            // Some injected libraries publish their facade just after launch.
            // Two bounded attempts cover that ordering without a polling timer.
            for(NSNumber *delay in @[@1,@3]){
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay.doubleValue*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
                    WPInstallWeChatSettingsEntry();
                });
            }
            [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
                    WPInstallWeChatSettingsEntry();
                }];
            [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
                    WPInstallWeChatSettingsEntry();
                }];
        });
    }
}
#endif

#ifdef WP_PREVIEW_HOST
BOOL WPPreviewRegisterCollectorClass(Class collectorClass){return WPRegisterCollectorClass(collectorClass);}
void WPPreviewResetCollectorRegistration(void){sRegisteredCollector=nil;sCollectorRegistrationInProgress=NO;}
NSString *WPPreviewCollectorControllerName(void){return WPCollectorControllerName();}
#endif
