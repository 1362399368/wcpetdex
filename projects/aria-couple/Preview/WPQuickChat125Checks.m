#import "WPQuickChat125Checks.h"
#import "WPQuickChatBar.h"
#import "WPQuickChat.h"
#import "WPSharedChatAvatar.h"
#import "WPCommon.h"
#if defined(WP_PREVIEW_HOST)
extern NSDictionary *WPPreviewSharedAvatarState(void);
extern void WPPreviewSeedSharedAvatar(NSString *,UIImage *);
extern void WPPreviewSetSharedAvatarProvider(void(^)(NSString *,void(^)(UIImage *)));
extern void WPPreviewResetSharedAvatarState(void);
@interface WPQuickChatBar (WPQuickChat125Testing)
- (void)refreshVisibleAvatars;
- (void)tableView:(UITableView *)table didEndDisplayingCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)path;
@end
static UIImage *WPQC125Image(UIColor *color){
    UIGraphicsImageRendererFormat *format=UIGraphicsImageRendererFormat.defaultFormat;format.scale=1;
    return [[[UIGraphicsImageRenderer alloc]initWithSize:CGSizeMake(96,96) format:format] imageWithActions:^(__unused UIGraphicsImageRendererContext *context){[color setFill];UIRectFill(CGRectMake(0,0,96,96));}];
}
@interface WPQC125Run : NSObject
@property(nonatomic,strong) UIWindow *window;
@property(nonatomic,strong) WPQuickChatBar *bar;
@property(nonatomic,strong) NSMutableDictionary *checks,*saved;
@property(nonatomic,strong) NSMutableDictionary<NSString *,NSMutableArray *> *finishers;
@property(nonatomic,strong) UIImage *first,*second;
@property(nonatomic) NSUInteger starts;
@property(nonatomic,copy) void (^completion)(NSDictionary *);
@end
@implementation WPQC125Run
- (WPQuickChatSession *)row:(NSString *)name{return [WPQuickChatSession sessionWithUsername:name unread:0 muted:NO pinned:NO time:1];}
- (UITableView *)table{return [self.bar valueForKey:@"table"];}
- (UITableViewCell *)cell{return [self.table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];}
- (UIImageView *)avatar{return [self.cell valueForKey:@"avatar"];}
- (void)layout{[self.bar setNeedsLayout];[self.bar layoutIfNeeded];[self.table layoutIfNeeded];}
- (void)rows:(NSArray *)rows{[self.bar reloadWithSessions:rows];[self layout];}
- (void)start{
    self.checks=[NSMutableDictionary new];self.saved=[NSMutableDictionary new];self.finishers=[NSMutableDictionary new];
    NSDictionary *options=@{@"showNames":@YES,@"unreadFirst":@NO,@"showMuted":@YES,@"filter":@0,@"limit":@0,@"removed":@[],@"customMode":@NO,@"separate":@NO,@"pinnedAlways":@NO,@"avatarSize":@44,@"sessionGap":@6,@"nameGap":@4};
    for(NSString *key in options){NSString *name=[@"quickChat." stringByAppendingString:key];self.saved[name]=[WPPreferences() objectForKey:name]?:NSNull.null;[WPPreferences() setObject:options[key] forKey:name];}
    WPPreviewResetSharedAvatarState();self.first=WPQC125Image(UIColor.systemTealColor);self.second=WPQC125Image(UIColor.systemPurpleColor);
    __weak typeof(self) weakSelf=self;
    WPPreviewSetSharedAvatarProvider(^(NSString *name,void(^finish)(UIImage *)){
        WPQC125Run *self=weakSelf;if(!self || ![name hasPrefix:@"wxid_qc125_"]){finish(nil);return;}
        self.starts++;if(!self.finishers[name])self.finishers[name]=[NSMutableArray new];[self.finishers[name] addObject:[finish copy]];
    });
    self.bar=[[WPQuickChatBar alloc]initWithFrame:CGRectMake(0,80,80,260)];self.bar.hidden=YES;[self.window.rootViewController.view addSubview:self.bar];
    NSArray *warm=@[[self row:@"wxid_qc125_a"],[self row:@"wxid_qc125_b"]];
    WPPreviewSeedSharedAvatar(@"wxid_qc125_a",self.first);WPPreviewSeedSharedAvatar(@"wxid_qc125_b",self.second);
    [self rows:warm];
    self.checks[@"QC12501HiddenRowBindingUsesSharedWarmAvatar"]=@(self.avatar.image==self.first && self.starts==0);
    self.bar.hidden=NO;[self layout];
    UITableViewCell *visible=self.cell;NSIndexPath *path=[NSIndexPath indexPathForRow:0 inSection:0];
    [self.bar tableView:self.table didEndDisplayingCell:visible forRowAtIndexPath:path];
    self.checks[@"QC12502StaleEndCallbackDoesNotClearVisibleAvatarOrIdentity"]=@(self.avatar.image==self.first && [[visible valueForKey:@"representedUsername"] isEqual:@"wxid_qc125_a"]);
    self.avatar.image=nil;[visible setValue:@NO forKey:@"hasPreparedAvatar"];[self.bar refreshVisibleAvatars];
    self.checks[@"QC12503VisibleBlankIsRepairedFromSharedCacheWithoutRequest"]=@(self.avatar.image==self.first && self.starts==0);
    self.bar.hidden=YES;[self rows:warm];self.bar.hidden=NO;[self layout];
    self.checks[@"QC12504CloseReloadReopenKeepsActualHeadWithoutNewWorker"]=@(self.avatar.image==self.first && self.starts==0 && [[self.bar valueForKey:@"avatarPreparations"] count]==0);
    [self rows:@[warm[1],warm[0]]];visible=self.cell;
    [self.bar tableView:self.table didEndDisplayingCell:visible forRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]];
    self.checks[@"QC12505ReorderedCellIgnoresPreviousRowsEndCallback"]=@(self.avatar.image==self.second && [[visible valueForKey:@"representedUsername"] isEqual:@"wxid_qc125_b"]);
    UITableViewCell *offscreen=[[NSClassFromString(@"WPQuickChatCell") alloc]initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"fixture"];
    [offscreen setValue:@"wxid_qc125_offscreen" forKey:@"representedUsername"];[[offscreen valueForKey:@"avatar"] setImage:self.first];[offscreen setValue:@YES forKey:@"hasPreparedAvatar"];
    [self.bar tableView:self.table didEndDisplayingCell:offscreen forRowAtIndexPath:[NSIndexPath indexPathForRow:20 inSection:0]];
    self.checks[@"QC12506TrueOffscreenCellStillReleasesDecodedHead"]=@(![[offscreen valueForKey:@"avatar"] image] && ![offscreen valueForKey:@"representedUsername"] && ![[offscreen valueForKey:@"hasPreparedAvatar"] boolValue]);
    [self rows:@[[self row:@"wxid_qc125_late"]]];
    void (^oldFinish)(UIImage *)=[self.finishers[@"wxid_qc125_late"].lastObject copy];
    self.bar.hidden=YES;[self rows:@[[self row:@"wxid_qc125_late"]]];self.bar.hidden=NO;[self layout];[self.bar refreshVisibleAvatars];
    void (^newFinish)(UIImage *)=[self.finishers[@"wxid_qc125_late"].lastObject copy];
    self.checks[@"QC12507ReopenStartsNewGenerationAfterCancellation"]=@(oldFinish!=nil && newFinish!=nil && self.finishers[@"wxid_qc125_late"].count==2);
    if(oldFinish)oldFinish(self.first);
    dispatch_async(dispatch_get_main_queue(),^{
        self.checks[@"QC12508CancelledOldResultCannotPopulateReopenedHead"]=@(WPCachedSharedChatAvatar(@"wxid_qc125_late")==nil && ![[self.cell valueForKey:@"hasPreparedAvatar"] boolValue]);
        if(newFinish)newFinish(self.second);
        dispatch_async(dispatch_get_main_queue(),^{
            self.checks[@"QC12509CurrentResultUpdatesReopenedVisibleHead"]=@(self.avatar.image==self.second && [[self.cell valueForKey:@"hasPreparedAvatar"] boolValue]);
            [self retryAndEviction];
        });
    });
}
- (void)retryAndEviction{
    self.bar.hidden=YES;[self rows:@[[self row:@"wxid_qc125_retry"]]];self.bar.hidden=NO;[self layout];[self.bar refreshVisibleAvatars];
    void (^fail)(UIImage *)=self.finishers[@"wxid_qc125_retry"].lastObject;if(fail)fail(nil);
    dispatch_async(dispatch_get_main_queue(),^{
        NSMutableDictionary *attempts=[self.bar valueForKey:@"avatarAttempts"],*retry=[self.bar valueForKey:@"avatarRetryAfter"];
        self.checks[@"QC12510FailedWorkerSchedulesBoundedBackoff"]=@([attempts[@"wxid_qc125_retry"] unsignedIntegerValue]==1 && [retry[@"wxid_qc125_retry"] doubleValue]>CACurrentMediaTime() && [retry[@"wxid_qc125_retry"] doubleValue]<=CACurrentMediaTime()+60);
        attempts[@"wxid_qc125_retry"]=@8;retry[@"wxid_qc125_retry"]=@(CACurrentMediaTime()+60);
        NSUInteger starts=self.starts;[self.bar refreshVisibleAvatars];
        self.checks[@"QC12511FailureBackoffDoesNotImmediatelyStartAnotherWorker"]=@(self.starts==starts);
        retry[@"wxid_qc125_retry"]=@(CACurrentMediaTime()-1);[self.bar refreshVisibleAvatars];
        self.checks[@"QC12512EightPastFailuresDoNotPermanentlyDisableAvatar"]=@(self.starts==starts+1);
        void (^finish)(UIImage *)=self.finishers[@"wxid_qc125_retry"].lastObject;if(finish)finish(self.first);
        dispatch_async(dispatch_get_main_queue(),^{
            self.checks[@"QC12513SuccessfulRetryResetsFailureLedger"]=@(self.avatar.image==self.first && !attempts[@"wxid_qc125_retry"] && !retry[@"wxid_qc125_retry"]);
            for(NSUInteger i=0;i<40;i++)WPPreviewSeedSharedAvatar([NSString stringWithFormat:@"wxid_qc125_evict_%lu",(unsigned long)i],self.second);
            NSUInteger before=self.starts;[self.bar refreshVisibleAvatars];
            self.checks[@"QC12514VisibleHeadSurvivesSharedLRUEvictionWithoutRedownload"]=@(WPCachedSharedChatAvatar(@"wxid_qc125_retry")==nil && self.avatar.image==self.first && self.starts==before);
            NSDictionary *cache=WPPreviewSharedAvatarState();
            self.checks[@"QC12515SharedCacheAndWorkersStayBoundedAfterEviction"]=@([cache[@"cached"] unsignedIntegerValue]<=16 && [cache[@"bytes"] unsignedIntegerValue]<=1536*1024 && [cache[@"active"] unsignedIntegerValue]<=2 && [cache[@"jobs"] unsignedIntegerValue]<=24);
            self.bar.hidden=YES;[self.bar removeFromSuperview];
            for(NSString *key in self.saved){id value=self.saved[key];if(value==NSNull.null)[WPPreferences() removeObjectForKey:key];else [WPPreferences() setObject:value forKey:key];}
            WPPreviewResetSharedAvatarState();self.checks[@"QC12599Completed"]=@YES;self.completion(self.checks);
        });
    });
}
@end
void WPQuickChat125RunPreviewChecks(UIWindow *window,void (^completion)(NSDictionary<NSString *,NSNumber *> *checks)){
    WPQC125Run *run=[WPQC125Run new];run.window=window;run.completion=completion;[run start];
}
#endif
