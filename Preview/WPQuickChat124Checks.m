#import "WPQuickChat124Checks.h"
#import "WPQuickChat.h"
#import "WPQuickChatBar.h"
#import "WPSharedChatAvatar.h"
#import "WPUnreadAvatarControl.h"
#import "WPCommon.h"
#import "WPSessionEligibility.h"

extern NSDictionary *WPPreviewSharedAvatarState(void);
extern void WPPreviewSeedSharedAvatar(NSString *,UIImage *);
extern void WPPreviewSetSharedAvatarProvider(void(^)(NSString *,void(^)(UIImage *)));
extern void WPPreviewSharedAvatarMemoryPressure(void);
extern void WPPreviewResetSharedAvatarState(void);
extern WPQuickChatUnreadState WPPreviewQuickChatUnreadState(id,NSString *,id);
extern NSString *WPPreviewQuickChatDisplayName(id,NSString *,BOOL);

@interface WPQC124NativeSession : NSObject
@property(nonatomic,copy) NSString *m_nsUserName;
@property(nonatomic) unsigned int m_uUnReadCount;
@property(nonatomic) BOOL m_bShowUnReadAsRedDot;
@property(nonatomic) BOOL m_isFolding;
@property(nonatomic) BOOL isHidden;
@end
@implementation WPQC124NativeSession @end
@interface WPQC124NativeManager : NSObject
@property(nonatomic,copy) NSArray *names;
@end
@implementation WPQC124NativeManager
- (NSArray *)GetUserNamesOnSessionList{return self.names;}
@end
@interface WPQC124Contact : NSObject
@property(nonatomic,copy) NSString *m_nsUsrName;
@property(nonatomic,copy) NSString *m_nsNickName;
@property(nonatomic,copy) NSString *m_nsRemark;
@end
@implementation WPQC124Contact @end

static UIImage *WPQC124Image(void){
    UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat defaultFormat];format.scale=1;format.opaque=YES;
    return [[[UIGraphicsImageRenderer alloc]initWithSize:CGSizeMake(160,160) format:format] imageWithActions:^(__unused UIGraphicsImageRendererContext *context){[UIColor.systemTealColor setFill];UIRectFill(CGRectMake(0,0,160,160));}];
}
static NSString *WPQC124TopName(WPQuickChatBar *bar,UITableView *table){
    NSIndexPath *path=[[table.indexPathsForVisibleRows sortedArrayUsingSelector:@selector(compare:)] firstObject];
    return path && path.row<(NSInteger)bar.sessions.count?bar.sessions[path.row].username:nil;
}

void WPQuickChat124RunPreviewChecks(UIWindow *window,void (^completion)(NSDictionary<NSString *,NSNumber *> *)){
    NSMutableDictionary *checks=[NSMutableDictionary new];UIImage *image=WPQC124Image();
    WPPreviewResetSharedAvatarState();
    // The same production store handles two subscribers, cancellation and
    // bounded workers. Only the native I/O boundary is delayed by this fixture.
    NSMutableDictionary<NSString *,id> *finishers=[NSMutableDictionary new];__block NSUInteger starts=0;
    WPPreviewSetSharedAvatarProvider(^(NSString *name,void(^finish)(UIImage *)){starts++;finishers[name]=[finish copy];});
    __block NSUInteger cancelledCalls=0,remainingCalls=0;
    WPSharedChatAvatarRequest *first=WPRequestSharedChatAvatar(@"wxid_qc124_shared",^(__unused UIImage *avatar){cancelledCalls++;});
    WPSharedChatAvatarRequest *second=WPRequestSharedChatAvatar(@"wxid_qc124_shared",^(UIImage *avatar){if(avatar==image)remainingCalls++;});
    checks[@"QC12401SameContactSharesOneWorker"]=@(starts==1 && [WPPreviewSharedAvatarState()[@"jobs"] unsignedIntegerValue]==1);
    [first cancel];checks[@"QC12402CancellingOneSubscriberKeepsOther"]=@([WPPreviewSharedAvatarState()[@"jobs"] unsignedIntegerValue]==1);
    void(^finish)(UIImage *)=finishers[@"wxid_qc124_shared"];finish(image);[finishers removeAllObjects];
    dispatch_async(dispatch_get_main_queue(),^{
        checks[@"QC12403OnlyUncancelledSubscriberReceivesImage"]=@(cancelledCalls==0 && remainingCalls==1 && WPCachedSharedChatAvatar(@"wxid_qc124_shared")==image);
        (void)second;
        NSMutableArray *requests=[NSMutableArray new];
        for(NSUInteger i=0;i<30;i++)[requests addObject:WPRequestSharedChatAvatar([NSString stringWithFormat:@"wxid_qc124_budget_%lu",(unsigned long)i],^(__unused UIImage *avatar) {})];
        NSDictionary *budget=WPPreviewSharedAvatarState();
        checks[@"QC12404GlobalQueueAndConcurrencyBounded"]=@([budget[@"active"] unsignedIntegerValue]==2 && [budget[@"jobs"] unsignedIntegerValue]<=24 && [budget[@"waiting"] unsignedIntegerValue]<=22);
        for(WPSharedChatAvatarRequest *request in requests)[request cancel];
        checks[@"QC12405LastSubscribersCancelAllOutstandingWorkers"]=@([WPPreviewSharedAvatarState()[@"jobs"] unsignedIntegerValue]==0 && [WPPreviewSharedAvatarState()[@"active"] unsignedIntegerValue]==0);
        for(NSUInteger i=0;i<30;i++)WPPreviewSeedSharedAvatar([NSString stringWithFormat:@"wxid_qc124_cache_%lu",(unsigned long)i],image);
        NSDictionary *cache=WPPreviewSharedAvatarState();
        checks[@"QC12406SharedCacheRespectsCountAndDecodedByteBudget"]=@([cache[@"cached"] unsignedIntegerValue]<=16 && [cache[@"bytes"] unsignedIntegerValue]<=1536*1024);
        WPPreviewSharedAvatarMemoryPressure();NSUInteger startsBefore=starts;
        WPSharedChatAvatarRequest *cooling=WPRequestSharedChatAvatar(@"wxid_qc124_cooling",^(__unused UIImage *avatar) {});
        checks[@"QC12407PressureReleasesCacheAndPreventsImmediateReload"]=@([WPPreviewSharedAvatarState()[@"cached"] unsignedIntegerValue]==0 && [WPPreviewSharedAvatarState()[@"jobs"] unsignedIntegerValue]==0 && starts==startsBefore && [WPPreviewSharedAvatarState()[@"cooldown"] doubleValue]>7);
        [cooling cancel];WPPreviewResetSharedAvatarState();

        NSArray *keys=@[@"showNames",@"unreadFirst",@"showMuted",@"filter",@"limit",@"removed",@"customMode",@"separate",@"pinnedAlways",@"avatarSize",@"sessionGap",@"nameGap"];
        NSMutableDictionary *saved=[NSMutableDictionary new];for(NSString *key in keys){NSString *name=[@"quickChat." stringByAppendingString:key];saved[name]=[WPPreferences() objectForKey:name]?:NSNull.null;}
        NSDictionary *options=@{@"showNames":@YES,@"unreadFirst":@NO,@"showMuted":@YES,@"filter":@0,@"limit":@0,@"removed":@[],@"customMode":@NO,@"separate":@NO,@"pinnedAlways":@NO,@"avatarSize":@44,@"sessionGap":@6,@"nameGap":@4};
        for(NSString *key in options)[WPPreferences() setObject:options[key] forKey:[@"quickChat." stringByAppendingString:key]];
        WPQuickChatBar *bar=[[WPQuickChatBar alloc]initWithFrame:CGRectMake(0,80,80,260)];
        [window.rootViewController.view addSubview:bar];
        WPPreviewSetSharedAvatarProvider(^(__unused NSString *name,__unused void(^callback)(UIImage *)){});
        NSMutableArray *rows=[NSMutableArray new];
        for(NSUInteger i=0;i<35;i++)[rows addObject:[WPQuickChatSession sessionWithUsername:[NSString stringWithFormat:@"wxid_qc124_row_%lu",(unsigned long)i] unread:0 muted:NO pinned:NO time:100+i]];
        [bar reloadWithSessions:rows];[bar setNeedsLayout];[bar layoutIfNeeded];UITableView *table=[bar valueForKey:@"table"];[table layoutIfNeeded];
        table.contentOffset=CGPointMake(0,table.rowHeight*15+11);[table layoutIfNeeded];
        NSString *anchor=WPQC124TopName(bar,table);CGFloat offset=table.contentOffset.y;
        NSIndexPath *visible=[[table.indexPathsForVisibleRows sortedArrayUsingSelector:@selector(compare:)] firstObject];UITableViewCell *cell=[table cellForRowAtIndexPath:visible];
        ((WPQuickChatSession *)rows[1]).unread=2;[bar reloadWithSessions:rows];[table layoutIfNeeded];
        checks[@"QC12408UnreadUpdateKeepsActualVisibleCellAndScrollOffset"]=@([anchor isEqual:WPQC124TopName(bar,table)] && fabs(offset-table.contentOffset.y)<.5 && [table cellForRowAtIndexPath:visible]==cell);
        [rows insertObject:[WPQuickChatSession sessionWithUsername:@"wxid_qc124_new" unread:1 muted:NO pinned:NO time:500] atIndex:0];
        [bar reloadWithSessions:rows];[table layoutIfNeeded];
        checks[@"QC12409NewTopConversationKeepsReadingSameContact"]=@([anchor isEqual:WPQC124TopName(bar,table)] && fabs(table.contentOffset.y-offset-table.rowHeight)<.5);
        if(![checks[@"QC12409NewTopConversationKeepsReadingSameContact"] boolValue]){
            NSDictionary *geometry=@{@"beforeOffset":@(offset),@"afterOffset":@(table.contentOffset.y),@"rowHeight":@(table.rowHeight),@"beforeAnchor":anchor?:@"none",@"afterAnchor":WPQC124TopName(bar,table)?:@"none",@"insetTop":@(table.adjustedContentInset.top),@"contentHeight":@(table.contentSize.height)};
            [[NSJSONSerialization dataWithJSONObject:geometry options:NSJSONWritingPrettyPrinted error:nil] writeToFile:[WPDataDirectory() stringByAppendingPathComponent:@"qc124-scroll-debug.json"] atomically:YES];
        }
        WPPreviewSeedSharedAvatar(anchor,image);UIImage *before=[bar avatarForUsername:anchor side:44];bar.hidden=YES;
        checks[@"QC12410ClosedBarReleasesRowsButKeepsBoundedSharedWarmImage"]=@(bar.sessions.count==0 && before==image && WPCachedSharedChatAvatar(anchor)==image && [[bar valueForKey:@"avatarPreparations"] count]==0);
        [bar removeFromSuperview];
        for(NSString *key in saved){id value=saved[key];if(value==NSNull.null)[WPPreferences() removeObjectForKey:key];else [WPPreferences() setObject:value forKey:key];}
        WPPreviewResetSharedAvatarState();

        WPQC124NativeSession *session=[WPQC124NativeSession new];session.m_nsUserName=@"wxid_qc124_state";session.m_uUnReadCount=2;
        WPQC124NativeManager *manager=[WPQC124NativeManager new];manager.names=@[session.m_nsUserName];
        checks[@"QC12411TypedUnreadRetained"]=@(WPPreviewQuickChatUnreadState(session,session.m_nsUserName,manager)==WPQuickChatUnreadStateUnread);
        session.m_uUnReadCount=0;checks[@"QC12412ExplicitZeroIsRead"]=@(WPPreviewQuickChatUnreadState(session,session.m_nsUserName,manager)==WPQuickChatUnreadStateRead);
        session.m_bShowUnReadAsRedDot=YES;checks[@"QC12413MuteDeniesImmediatelyEvenWhenCountIsZero"]=@(WPPreviewQuickChatUnreadState(session,session.m_nsUserName,manager)==WPQuickChatUnreadStateDenied);
        session.m_bShowUnReadAsRedDot=NO;session.m_uUnReadCount=3;session.isHidden=YES;
        checks[@"QC12414HiddenSessionDeniesImmediately"]=@(WPPreviewQuickChatUnreadState(session,session.m_nsUserName,manager)==WPQuickChatUnreadStateDenied);
        checks[@"QC12415MissingNativeSnapshotRemainsUnknown"]=@(WPPreviewQuickChatUnreadState(nil,session.m_nsUserName,manager)==WPQuickChatUnreadStateUnknown);
        session.isHidden=NO;checks[@"QC12416WrongNativeIdentityRemainsUnknown"]=@(WPPreviewQuickChatUnreadState(session,@"wxid_other",manager)==WPQuickChatUnreadStateUnknown);
        WPQC124Contact *contact=[WPQC124Contact new];contact.m_nsUsrName=@"wxid_qc124_name";contact.m_nsNickName=@"微信昵称";contact.m_nsRemark=@"我的备注";
        checks[@"QC12417NameSourceSelectsNicknameOrRemark"]=@([WPPreviewQuickChatDisplayName(contact,contact.m_nsUsrName,NO) isEqual:@"微信昵称"] && [WPPreviewQuickChatDisplayName(contact,contact.m_nsUsrName,YES) isEqual:@"我的备注"]);
        contact.m_nsNickName=contact.m_nsUsrName;contact.m_nsRemark=@"";
        checks[@"QC12418UnknownNameNeverLeaksRawWxid"]=@(WPPreviewQuickChatDisplayName(contact,contact.m_nsUsrName,NO).length==0);
        contact.m_nsNickName=[@"👨‍👩‍👧‍👦" stringByPaddingToLength:11*30 withString:@"👨‍👩‍👧‍👦" startingAtIndex:0];
        NSString *limited=WPPreviewQuickChatDisplayName(contact,contact.m_nsUsrName,NO);__block NSUInteger graphemes=0;
        [limited enumerateSubstringsInRange:NSMakeRange(0,limited.length) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(__unused NSString *part,__unused NSRange range,__unused NSRange enclosing,__unused BOOL *stop){graphemes++;}];
        checks[@"QC12419NameCapKeepsWholeEmojiGraphemes"]=@(graphemes==24 && ![limited hasSuffix:@"‍"]);
        WPSEInvalidateHomeNames();
        checks[@"QC12499Completed"]=@YES;completion(checks);
    });
}
