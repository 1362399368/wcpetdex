#import "WPLocalAvatarPreparationChecks.h"
#import "WPQuickChat.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
extern id WPPreviewContactHeadCache(id manager,NSString *username);
@interface WPAvatar125DBCache : NSObject
@property(nonatomic,strong) id fixtureContact;
@property(nonatomic) NSUInteger reads;
- (id)getContactByName:(NSString *)username;
- (id)getContactByNameFromDB:(NSString *)username;
@end
@implementation WPAvatar125DBCache
- (id)getContactByName:(NSString *)username{return nil;}
- (id)getContactByNameFromDB:(NSString *)username{self.reads++;return self.fixtureContact;}
@end
extern NSDictionary *WPPreviewLocalAvatarPreparationState(void);
extern void WPPreviewSetLocalAvatarNativeReadObserver(void(^observer)(BOOL));
void WPLocalAvatarPreparationRunPreviewChecks(void(^completion)(NSDictionary<NSString*,NSNumber*>*)){
    NSCAssert(NSThread.isMainThread,@"Run the local-avatar resource contract on main");
    NSMutableDictionary *checks=[NSMutableDictionary new];
    __block NSUInteger nativeReads=0,cancelledCallbacks=0,backgroundCallbacks=0;__block BOOL mainNativeReads=YES,mainCallbacks=YES;
    WPPreviewSetLocalAvatarNativeReadObserver(^(BOOL main){nativeReads++;mainNativeReads &= main;});
    NSMutableArray<WPQuickChatAvatarPreparation*> *tokens=[NSMutableArray new];
    for(NSUInteger i=0;i<20;i++)[tokens addObject:WPQuickChatPrepareAvatar([NSString stringWithFormat:@"wxid_local_head_bound_%lu",(unsigned long)i],96,^(UIImage*image){cancelledCallbacks++;})];
    NSDictionary *busy=WPPreviewLocalAvatarPreparationState();
    checks[@"LA01_twentyRequestsKeepAtMostTwelveWaiting"] = @([busy[@"waiting"]unsignedIntegerValue]==12);
    checks[@"LA02_waitingRequestsRetainNoNativePhotos"] = @([busy[@"waitingNativeInputs"]unsignedIntegerValue]==0);
    checks[@"LA03_onlyActiveWorkerQueriesNativeCache"] = @(nativeReads==1 && mainNativeReads);
    for(WPQuickChatAvatarPreparation*t in tokens)[t cancel];
    checks[@"LA04_cancelImmediatelyReleasesAllWaitingTokens"] = @([WPPreviewLocalAvatarPreparationState()[@"waiting"]unsignedIntegerValue]==0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        (void)WPQuickChatPrepareAvatar(@"wxid_background_head_request",96,^(UIImage*image){backgroundCallbacks++;mainCallbacks &= NSThread.isMainThread;});
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        checks[@"LA05_cancelSuppressesAlreadyQueuedCallbacks"] = @(cancelledCallbacks==0 && backgroundCallbacks==1);
        checks[@"LA06_workerCallerStillReadsNativeCacheOnMain"] = @(nativeReads==2 && mainNativeReads);
        checks[@"LA07_backgroundRequestCompletesOnMain"] = @(mainCallbacks && backgroundCallbacks==1);
        NSDictionary*idle=WPPreviewLocalAvatarPreparationState();
        checks[@"LA08_completedWorkLeavesNoPendingNativeInput"] = @([idle[@"waiting"]unsignedIntegerValue]==0 && [idle[@"waitingNativeInputs"]unsignedIntegerValue]==0 && ![idle[@"working"]boolValue]);
        Class managerClass=NSClassFromString(@"CContactMgr");
        if([managerClass respondsToSelector:NSSelectorFromString(@"sharedManager")]){
            id manager=((id(*)(id,SEL))objc_msgSend)(managerClass,NSSelectorFromString(@"sharedManager"));
            id contact=((id(*)(id,SEL,id))objc_msgSend)(manager,NSSelectorFromString(@"getContactByName:"),@"wxid_contract_aria");
            if([contact respondsToSelector:NSSelectorFromString(@"setWpFixtureHeadImage:")]){
                UIImage *image=[[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(64,64)] imageWithActions:^(__unused UIGraphicsImageRendererContext *context){[UIColor.systemTealColor setFill];UIRectFill(CGRectMake(0,0,64,64));}];
                [contact setValue:image forKey:@"wpFixtureHeadImage"];
                checks[@"LA09_contactCacheWorksWithoutLegacyHeadManager"]=@(NSClassFromString(@"MMHeadImageMgr")==nil && WPQuickChatAvatar(@"wxid_contract_aria")==image);
                checks[@"LA10_nativeCacheFastPathDoesNotQueueDecode"]=@(![WPPreviewLocalAvatarPreparationState()[@"working"] boolValue]);
                WPAvatar125DBCache *database=[WPAvatar125DBCache new];database.fixtureContact=contact;
                checks[@"LA125DatabaseContactCacheSuppliesNativeHeadImage"]=@(WPPreviewContactHeadCache(database,@"wxid_contract_aria")==image && database.reads==1);
                checks[@"LA125DatabaseContactCacheRejectsMismatchedIdentity"]=@(WPPreviewContactHeadCache(database,@"wxid_wrong_avatar")==nil);
                [contact setValue:nil forKey:@"wpFixtureHeadImage"];
            }
        }
        WPPreviewSetLocalAvatarNativeReadObserver(nil);completion(checks);
    });
}
