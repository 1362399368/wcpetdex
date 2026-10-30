#import <UIKit/UIKit.h>
#import "WPCommon.h"
#import "WPPartnerContact.h"

#if defined(WP_PREVIEW_HOST)

// These names deliberately match only the private classes resolved by the
// adapter. This file is linked into the simulator preview, never the dylib.
@interface CContact : NSObject
@property (nonatomic, copy) NSString *m_nsUsrName;
@property (nonatomic, copy) NSString *m_nsNickName;
@property (nonatomic, copy) NSString *m_nsRemark;
@property (nonatomic, copy) NSString *m_nsHeadImgUrl;
@property (nonatomic,strong) UIImage *wpFixtureHeadImage;
- (NSString *)getContactDisplayName;
- (UIImage *)getContactHeadImage;
@end

@implementation CContact
- (NSString *)getContactDisplayName { return self.m_nsRemark.length ? self.m_nsRemark : self.m_nsNickName; }
- (UIImage *)getContactHeadImage {return self.wpFixtureHeadImage;}
@end

@interface CContactMgr : NSObject
@property (nonatomic, strong) NSDictionary<NSString *, CContact *> *fixtureContacts;
@property (nonatomic) NSUInteger usernameOutputCalls;
@property (nonatomic) NSUInteger contactOutputCalls;
@property (nonatomic) unsigned int lastListType;
+ (instancetype)sharedManager;
- (NSArray *)getAllContactUserName;
- (NSArray *)getAllContactUserNameFromCache;
- (BOOL)getAllUserName:(NSMutableArray *)output;
- (BOOL)getAllContactList:(NSMutableArray *)output listType:(unsigned int)listType;
- (BOOL)isInContactList:(NSString *)username;
- (CContact *)getSelfContact;
- (CContact *)getContactByName:(NSString *)username;
@end

static NSString *const WPFixtureAria = @"wxid_contract_aria";
static NSString *const WPFixtureBob = @"wxid_contract_bob";
static NSString *const WPFixtureSelf = @"wxid_contract_self";
static NSString *const WPFixtureGroup = @"contract_group@chatroom";
static NSString *const WPFixturePublic = @"gh_contract_public";

@implementation CContactMgr
+ (instancetype)sharedManager {
    static CContactMgr *manager;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ manager = [self new]; });
    return manager;
}
- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    NSMutableDictionary *contacts = [NSMutableDictionary new];
    NSArray *fixtures = @[
        @[WPFixtureAria, @"Aria", @"阿里娅"],
        @[WPFixtureBob, @"Bob", @"朋友 Bob"],
        @[WPFixtureSelf, @"Myself", @"我自己"],
        @[WPFixtureGroup, @"Family", @"家庭群"],
        @[WPFixturePublic, @"News", @"公众号"]
    ];
    for (NSArray<NSString *> *row in fixtures) {
        CContact *contact = [CContact new];
        contact.m_nsUsrName = row[0];
        contact.m_nsRemark = row[1];
        contact.m_nsNickName = row[2];
        contacts[row[0]] = contact;
    }
    self.fixtureContacts = contacts;
    return self;
}
- (NSArray *)getAllContactUserName { return @[]; }
- (NSArray *)getAllContactUserNameFromCache { return @[]; }
- (BOOL)getAllUserName:(NSMutableArray *)output {
    self.usernameOutputCalls++;
    [output addObjectsFromArray:@[WPFixtureAria, WPFixtureSelf, WPFixtureGroup, WPFixturePublic, @"unresolved_contract_name"]];
    // A NO return must not discard a partially populated output collection.
    return NO;
}
- (BOOL)getAllContactList:(NSMutableArray *)output listType:(unsigned int)listType {
    self.contactOutputCalls++;
    self.lastListType = listType;
    [output addObjectsFromArray:@[self.fixtureContacts[WPFixtureBob], self.fixtureContacts[WPFixtureAria]]];
    return NO;
}
- (BOOL)isInContactList:(NSString *)username { (void)username; return NO; }
- (CContact *)getSelfContact { return self.fixtureContacts[WPFixtureSelf]; }
- (CContact *)getContactByName:(NSString *)username { return self.fixtureContacts[username]; }
@end

@interface WPFixtureChatController : UIViewController
@property (nonatomic, copy) NSString *fixtureUsername;
- (NSString *)getCurrentChatName;
@end
@implementation WPFixtureChatController
- (NSString *)getCurrentChatName { return self.fixtureUsername; }
@end

@interface WPInvalidContractChatLogic : NSObject
@property (nonatomic) NSUInteger unsafeCalls;
- (void)PushOtherBaseMsgControllerByContact:(CContact *)contact navigationController:(UINavigationController *)navigation animated:(NSInteger)animated;
@end
@implementation WPInvalidContractChatLogic
- (void)PushOtherBaseMsgControllerByContact:(CContact *)contact navigationController:(UINavigationController *)navigation animated:(NSInteger)animated {
    (void)contact; (void)navigation; (void)animated;
    self.unsafeCalls++;
}
@end

static BOOL WPUseInvalidContractChatLogic = NO;
static WPInvalidContractChatLogic *WPInvalidContractChatService;

@interface MMMsgLogicManager : NSObject
@property (nonatomic) NSUInteger routeCalls;
@property (nonatomic, strong) CContact *lastContact;
@property (nonatomic, weak) UINavigationController *lastNavigation;
@property (nonatomic) BOOL lastAnimated;
+ (id)sharedManager;
- (void)PushOtherBaseMsgControllerByContact:(CContact *)contact navigationController:(UINavigationController *)navigation animated:(BOOL)animated;
@end
@implementation MMMsgLogicManager
+ (id)sharedManager {
    if (WPUseInvalidContractChatLogic) {
        if (!WPInvalidContractChatService) WPInvalidContractChatService = [WPInvalidContractChatLogic new];
        return WPInvalidContractChatService;
    }
    static MMMsgLogicManager *manager;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ manager = [self new]; });
    return manager;
}
- (void)PushOtherBaseMsgControllerByContact:(CContact *)contact navigationController:(UINavigationController *)navigation animated:(BOOL)animated {
    self.routeCalls++;
    self.lastContact = contact;
    self.lastNavigation = navigation;
    self.lastAnimated = animated;
    WPFixtureChatController *chat = [WPFixtureChatController new];
    chat.fixtureUsername = contact.m_nsUsrName;
    // The adapter's ABI contract still receives YES; avoid a transition in this
    // synchronous test so the following duplicate-route assertion is reliable.
    [navigation pushViewController:chat animated:NO];
}
@end

@interface WPPartnerPickerController (WPContactContractTests)
- (void)loadContacts;
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController;
@end

NSDictionary *WPContactRunContractTests(void) {
    NSCAssert(NSThread.isMainThread, @"Contact contracts require the main queue");
    NSMutableDictionary<NSString *, NSNumber *> *results = [NSMutableDictionary new];
    UIWindow *routeWindow = nil;
    @try {
        CContactMgr *manager = [CContactMgr sharedManager];
        manager.usernameOutputCalls = manager.contactOutputCalls = 0;
        manager.lastListType = 0;
        WPPartnerPickerController *picker = [[WPPartnerPickerController alloc] initWithStyle:UITableViewStyleInsetGrouped];
        [picker loadViewIfNeeded];
        [picker loadContacts];
        NSArray<NSDictionary *> *contacts = [picker valueForKey:@"contacts"];
        NSSet *usernames = [NSSet setWithArray:[contacts valueForKey:@"username"]];
        results[@"contactsEmptyPrimaryListUsesOutputCollections"] = @(manager.getAllContactUserName.count == 0 && manager.usernameOutputCalls > 0 && manager.contactOutputCalls > 0);
        results[@"contactsOutputListTypeUsesUInt32One"] = @(manager.lastListType == 1);
        results[@"contactsAggregateNamesAndObjectsDespiteNOReturn"] = @([usernames containsObject:WPFixtureAria] && [usernames containsObject:WPFixtureBob]);
        results[@"contactsUnknownMembershipNOIsNotAFilter"] = @(![manager isInContactList:WPFixtureAria] && [usernames containsObject:WPFixtureAria]);
        results[@"contactsFilterSelf"] = @(![usernames containsObject:WPFixtureSelf]);
        results[@"contactsFilterChatrooms"] = @(![usernames containsObject:WPFixtureGroup]);
        results[@"contactsFilterPublicAccounts"] = @(![usernames containsObject:WPFixturePublic]);
        results[@"contactsValidateUnknownAndDeduplicate"] = @(contacts.count == 2 && ![usernames containsObject:@"unresolved_contract_name"]);
        results[@"contactsSuccessfulOutputClearsLoadError"] = @([picker valueForKey:@"loadError"] == nil);

        UISearchController *search = [picker valueForKey:@"contactSearch"];
        search.searchBar.text = @"  aria  ";
        [picker updateSearchResultsForSearchController:search];
        NSArray<NSDictionary *> *filtered = [picker valueForKey:@"filtered"];
        results[@"contactsSearchAriaCaseInsensitiveAndTrimmed"] = @(filtered.count == 1 && [filtered.firstObject[@"name"] isEqualToString:@"Aria"] && [filtered.firstObject[@"username"] isEqualToString:WPFixtureAria]);
        search.searchBar.text = @"Ária";
        [picker updateSearchResultsForSearchController:search];
        results[@"contactsSearchIgnoresDiacritics"] = @([[picker valueForKey:@"filtered"] count] == 1);
        search.searchBar.text = WPFixtureAria;
        [picker updateSearchResultsForSearchController:search];
        results[@"contactsSearchMatchesUsername"] = @([[picker valueForKey:@"filtered"] count] == 1);
        __block NSString *selectedUsername = nil, *selectedName = nil;
        picker.selectionHandler = ^(NSString *username, NSString *name) { selectedUsername = username; selectedName = name; };
        [picker tableView:picker.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
        results[@"contactsSelectionReturnsUsernameAndDisplayName"] = @([selectedUsername isEqualToString:WPFixtureAria] && [selectedName isEqualToString:@"Aria"]);

        UIWindowScene *scene = nil;
        for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
            if ([candidate isKindOfClass:UIWindowScene.class] && candidate.activationState == UISceneActivationStateForegroundActive) { scene = (id)candidate; break; }
        }
        routeWindow = scene ? [[UIWindow alloc] initWithWindowScene:scene] : [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
        routeWindow.frame = scene ? scene.coordinateSpace.bounds : UIScreen.mainScreen.bounds;
        UIViewController *home = [UIViewController new];
        UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:home];
        routeWindow.rootViewController = navigation;
        routeWindow.hidden = NO; // Never takes key status from the preview host.
        [navigation.view layoutIfNeeded];
        MMMsgLogicManager *logic = [MMMsgLogicManager sharedManager];
        logic.routeCalls = 0;
        [WPPartnerContact openConversationWithUsername:WPFixtureAria inWindow:routeWindow presentationMode:1 completion:^(__unused BOOL success, __unused NSString *message) {}];
        results[@"contactChatRouteCorrectSignatureInvoked"] = @(logic.routeCalls == 1);
        results[@"contactChatRoutePassesContactNavigationAndBOOL"] = @([logic.lastContact.m_nsUsrName isEqualToString:WPFixtureAria] && logic.lastNavigation == navigation && logic.lastAnimated);
        __block BOOL duplicateCompleted = NO, duplicateSuccess = NO;
        [WPPartnerContact openConversationWithUsername:WPFixtureAria inWindow:routeWindow presentationMode:1 completion:^(BOOL success, __unused NSString *message) { duplicateCompleted = YES; duplicateSuccess = success; }];
        results[@"contactChatAlreadyOpenSkipsDuplicateRoute"] = @(duplicateCompleted && duplicateSuccess && logic.routeCalls == 1);
        [navigation popToRootViewControllerAnimated:NO];
        WPUseInvalidContractChatLogic = YES;
        WPInvalidContractChatService = [WPInvalidContractChatLogic new];
        __block BOOL invalidCompleted = NO, invalidSuccess = YES;
        [WPPartnerContact openConversationWithUsername:WPFixtureAria inWindow:routeWindow presentationMode:1 completion:^(BOOL success, __unused NSString *message) { invalidCompleted = YES; invalidSuccess = success; }];
        results[@"contactChatRejectsIntegerInsteadOfBOOLSignature"] = @(invalidCompleted && !invalidSuccess && WPInvalidContractChatService.unsafeCalls == 0);
        results[@"contactContractsNoException"] = @YES;
    } @catch (NSException *exception) {
        results[@"contactContractsNoException"] = @NO;
        NSLog(@"Contact preview contract failed: %@", exception.reason);
    } @finally {
        routeWindow.hidden = YES;
        routeWindow.rootViewController = nil;
        WPUseInvalidContractChatLogic = NO;
        WPInvalidContractChatService = nil;
    }
    return [results copy];
}

#endif
