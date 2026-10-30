#import "WPCollectorChecks.h"
#import "WPWeChatSettingsEntry.h"
#import "WPSettings.h"
#import "WPCommon.h"
#import <objc/runtime.h>
#import <objc/message.h>

@interface WPSettingsController (WPCollectorCloseTesting)
- (void)done;
@end

extern BOOL WPPreviewRegisterCollectorClass(Class);
extern void WPPreviewResetCollectorRegistration(void);
extern NSString *WPPreviewCollectorControllerName(void);

@interface WPCollectorTestManager:NSObject
@property(nonatomic) NSUInteger calls;
@property(nonatomic) BOOL throws;
@property(nonatomic,copy) NSString *title;
@property(nonatomic,copy) NSString *version;
@property(nonatomic,copy) NSString *controller;
@end
@implementation WPCollectorTestManager
- (void)registerControllerWithTitle:(NSString *)title version:(NSString *)version controller:(NSString *)controller{
    self.calls++;
    if(self.throws)[NSException raise:@"WPCollectorTestException" format:@"Unavailable registry"];
    self.title=title;self.version=version;self.controller=controller;
}
@end
static id sWPCollectorTestSingleton;
static id sWPRefineTestSingleton;
static id WPRefineTestShared(id self,SEL cmd){return sWPRefineTestSingleton;}
static id WPCollectorTestShared(id self,SEL cmd){return sWPCollectorTestSingleton;}
static NSInteger WPCollectorTestWrongReturn(id self,SEL cmd){return 1;}
static Class WPCollectorTestClass(NSString *name,IMP shared,const char *types){
    Class cls=NSClassFromString(name);
    if(!cls){cls=objc_allocateClassPair(NSObject.class,name.UTF8String,0);
        if(shared)class_addMethod(object_getClass(cls),@selector(sharedInstance),shared,types);
        objc_registerClassPair(cls);}
    return cls;
}

@interface WPCollectorTestSection:NSObject
@property(nonatomic,strong) NSMutableArray *cells;
@end
@implementation WPCollectorTestSection
- (instancetype)init{if((self=[super init]))self.cells=[NSMutableArray array];return self;}
- (void)addCell:(id)cell{[self.cells addObject:cell];}
@end
@interface WPCollectorTestTable:NSObject
@property(nonatomic,strong) NSMutableArray *sections;
@property(nonatomic) NSUInteger reloads;
@end
@implementation WPCollectorTestTable
- (instancetype)init{if((self=[super init]))self.sections=[NSMutableArray array];return self;}
- (void)insertSection:(id)section At:(NSInteger)index{[self.sections insertObject:section atIndex:(NSUInteger)index];}
- (void)reloadTableView{self.reloads++;}
@end
static NSUInteger sWPCollectorOriginalReloads;
static id WPCollectorSectionFactory(id self,SEL cmd){return [WPCollectorTestSection new];}
static id WPCollectorCellFactory(id self,SEL cmd,SEL action,id target,NSString *title){
    return @{ @"title":title,@"target":target,@"action":NSStringFromSelector(action) };
}
static void WPCollectorOriginalReload(id self,SEL cmd){
    sWPCollectorOriginalReloads++;
    WPCollectorTestTable *table=object_getIvar(self,class_getInstanceVariable(object_getClass(self),"_m_tableViewMgr"));
    [table.sections removeAllObjects];
}
static void WPCollectorNativeMocks(void){
    Class section=NSClassFromString(@"MMTableViewSectionInfo");
    if(!section){section=objc_allocateClassPair(NSObject.class,"MMTableViewSectionInfo",0);
        class_addMethod(object_getClass(section),NSSelectorFromString(@"sectionInfoDefaut"),(IMP)WPCollectorSectionFactory,"@16@0:8");objc_registerClassPair(section);}
    Class cell=NSClassFromString(@"MMTableViewCellInfo");
    if(!cell){cell=objc_allocateClassPair(NSObject.class,"MMTableViewCellInfo",0);
        class_addMethod(object_getClass(cell),@selector(normalCellForSel:target:title:),(IMP)WPCollectorCellFactory,"@40@0:8:16@24@32");objc_registerClassPair(cell);}
    Class settings=NSClassFromString(@"NewSettingViewController");
    if(!settings){settings=objc_allocateClassPair(UIViewController.class,"NewSettingViewController",0);
        class_addIvar(settings,"_m_tableViewMgr",sizeof(id),3,"@");
        class_addMethod(settings,@selector(reloadTableData),(IMP)WPCollectorOriginalReload,"v16@0:8");objc_registerClassPair(settings);}
}

NSDictionary<NSString *,NSNumber *> *WPCollectorPreviewChecks(void){
    NSMutableDictionary *r=[NSMutableDictionary dictionary];
    WPPreviewResetCollectorRegistration();
    Class good=WPCollectorTestClass(@"WPCollectorValidFacade",(IMP)WPCollectorTestShared,"@16@0:8");
    Class missing=WPCollectorTestClass(@"WPCollectorMissingFacade",NULL,NULL);
    Class wrong=WPCollectorTestClass(@"WPCollectorInvalidFacade",(IMP)WPCollectorTestWrongReturn,"q16@0:8");
    r[@"collectorAbsentKeepsFallback"]=@(!WPPreviewRegisterCollectorClass(Nil));
    r[@"collectorMissingAPIDoesNotHideEntry"]=@(!WPPreviewRegisterCollectorClass(missing));
    r[@"collectorInvalidABIDoesNotCall"]=@(!WPPreviewRegisterCollectorClass(wrong));
    sWPCollectorTestSingleton=nil;
    r[@"collectorUnreadySingletonKeepsFallback"]=@(!WPPreviewRegisterCollectorClass(good));
    sWPCollectorTestSingleton=[NSObject new];
    r[@"collectorMissingRegistrationKeepsFallback"]=@(!WPPreviewRegisterCollectorClass(good));
    WPCollectorTestManager *manager=[WPCollectorTestManager new];manager.throws=YES;sWPCollectorTestSingleton=manager;
    r[@"collectorExceptionKeepsFallback"]=@(!WPPreviewRegisterCollectorClass(good));
    manager.throws=NO;NSUInteger before=manager.calls;
    r[@"collectorRetryAfterFailureRegisters"]=@(WPPreviewRegisterCollectorClass(good)&&manager.calls==before+1);
    NSUInteger successful=manager.calls;
    for(NSUInteger i=0;i<100;i++)WPPreviewRegisterCollectorClass(good);
    r[@"collectorRepeatedInstallRegistersOnlyOnce"]=@(manager.calls==successful);
    r[@"collectorReceivesTitleVersionAndClassString"]=@([manager.title isEqual:@"周游专属包"]&&manager.version.length>0&&[manager.controller isEqual:WPPreviewCollectorControllerName()]&&[NSClassFromString(manager.controller) isSubclassOfClass:UIViewController.class]);
    WPCollectorTestManager *replacement=[WPCollectorTestManager new];sWPCollectorTestSingleton=replacement;
    r[@"collectorReplacementSingletonRegistersOnce"]=@(WPPreviewRegisterCollectorClass(good)&&replacement.calls==1);

    Class wrapperClass=NSClassFromString(WPPreviewCollectorControllerName());
    UIViewController *parent=[UIViewController new],*wrapper=[wrapperClass new];
    UINavigationController *outer=[[UINavigationController alloc] initWithRootViewController:parent];
    [outer pushViewController:wrapper animated:NO];[wrapper loadViewIfNeeded];
    UINavigationController *inner=[wrapper valueForKey:@"settingsNavigation"];
    WPSettingsController *settings=(id)inner.viewControllers.firstObject;
    r[@"collectorUsesExistingSettingsAsOwnNavigationRoot"]=@([settings isKindOfClass:WPSettingsController.class]&&inner.parentViewController==wrapper&&settings.onClose!=nil);
    [settings loadViewIfNeeded];
    [settings done];
    r[@"collectorDoneReturnsToCollection"]=@(outer.topViewController==parent);
    [outer pushViewController:wrapper animated:NO];
    [inner pushViewController:[UIViewController new] animated:NO];
    settings.onClose();
    r[@"collectorSecondaryActionCloseReturnsToCollection"]=@(outer.topViewController==parent);
    [outer setNavigationBarHidden:NO animated:NO];
    [outer pushViewController:wrapper animated:NO];[wrapper viewWillAppear:NO];
    BOOL hidden=outer.navigationBarHidden;
    [wrapper viewWillDisappear:NO];
    r[@"collectorRestoresOuterNavigationBar"]=@(hidden&&!outer.navigationBarHidden);

    WPPreviewResetCollectorRegistration();sWPCollectorTestSingleton=nil;
    WPCollectorNativeMocks();
    id native=[NSClassFromString(@"NewSettingViewController") new];
    WPCollectorTestTable *table=[WPCollectorTestTable new];
    object_setIvar(native,class_getInstanceVariable(object_getClass(native),"_m_tableViewMgr"),table);
    WPInstallWeChatSettingsEntry();
    ((void(*)(id,SEL))objc_msgSend)(native,@selector(reloadTableData));
    r[@"collectorNativeFallbackKeepsOriginalReload"]=@(sWPCollectorOriginalReloads==1&&table.sections.count==1);
    ((void(*)(id,SEL))objc_msgSend)(native,@selector(reloadTableData));
    r[@"collectorNativeFallbackDoesNotDuplicate"]=@(sWPCollectorOriginalReloads==2&&table.sections.count==1);
    // Publish the actual standard class only now, emulating a later-loaded tweak.
    WPCollectorTestClass(@"WCPluginsMgr",(IMP)WPCollectorTestShared,"@16@0:8");
    WPCollectorTestManager *late=[WPCollectorTestManager new];sWPCollectorTestSingleton=late;
    WPInstallWeChatSettingsEntry();
    ((void(*)(id,SEL))objc_msgSend)(native,@selector(reloadTableData));
    r[@"collectorLateLoadMovesRowAndPreservesReload"]=@(late.calls==1&&table.sections.count==0&&sWPCollectorOriginalReloads==3);
    for(NSUInteger i=0;i<10;i++)WPInstallWeChatSettingsEntry();
    r[@"collectorActiveRetriesDoNotDuplicateRegistration"]=@(late.calls==1);
    late=nil;sWPCollectorTestSingleton=nil;WPPreviewResetCollectorRegistration();
    ((void(*)(id,SEL))objc_msgSend)(native,@selector(reloadTableData));
    r[@"collectorUnavailableAgainRestoresNativeEntry"]=@(table.sections.count==1&&sWPCollectorOriginalReloads==4);
    WPCollectorTestClass(@"WCRefinePluginHubManager",(IMP)WPRefineTestShared,"@16@0:8");
    WPCollectorTestManager *refine=[WPCollectorTestManager new],*standard=[WPCollectorTestManager new];
    sWPRefineTestSingleton=refine;sWPCollectorTestSingleton=standard;WPPreviewResetCollectorRegistration();
    WPInstallWeChatSettingsEntry();
    r[@"collectorWCRefineOwnHubHasPriority"]=@(refine.calls==1&&standard.calls==0&&[refine.title isEqual:@"周游专属包"]);
    for(NSUInteger i=0;i<10;i++)WPInstallWeChatSettingsEntry();
    r[@"collectorWCRefineHubDoesNotDuplicate"]=@(refine.calls==1);
    sWPRefineTestSingleton=nil;WPPreviewResetCollectorRegistration();WPInstallWeChatSettingsEntry();
    r[@"collectorWCRefineUnavailableUsesStandardFacade"]=@(standard.calls==1);
    sWPCollectorTestSingleton=nil;WPPreviewResetCollectorRegistration();
    return r;
}
