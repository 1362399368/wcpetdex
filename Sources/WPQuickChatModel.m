#import "WPQuickChatModel.h"

@implementation WPQuickChatSession
+ (instancetype)sessionWithUsername:(NSString *)username unread:(NSUInteger)unread muted:(BOOL)muted pinned:(BOOL)pinned time:(NSTimeInterval)time {
    WPQuickChatSession *session=[self new];session.username=username;session.unread=unread;session.unreadKnown=YES;
    session.muted=muted;session.pinned=pinned;session.time=time;return session;
}
- (BOOL)alertable{return self.unreadKnown && self.unread>0 && !self.muted;}
@end

BOOL WPQuickChatIsOpenableUsername(NSString *username) {
    if(!username.length || username.length>256)return NO;
    NSString *name=username.lowercaseString;
    // brandsessionholder, brandservicesessionholder, @placeholder_foldgroup …
    if([name hasSuffix:@"sessionholder"] || [name hasPrefix:@"@placeholder"] || [name hasPrefix:@"@opencustomerservice"])return NO;
    static NSSet *aggregates;static dispatch_once_t once;
    dispatch_once(&once,^{aggregates=[NSSet setWithArray:@[@"notifymessage",@"fmessage",@"floatbottle",@"newsapp",@"weixinreminder",@"notification_messages"]];});
    return ![aggregates containsObject:name];
}

NSArray<WPQuickChatSession *> *WPQuickChatOrdered(NSArray<WPQuickChatSession *> *sessions, BOOL nativeOrder) {
    NSMutableArray *result=[NSMutableArray new];NSMutableSet *seen=[NSMutableSet new];
    for(WPQuickChatSession *session in sessions){
        if(!WPQuickChatIsOpenableUsername(session.username) || [seen containsObject:session.username])continue;
        [seen addObject:session.username];[result addObject:session];
    }
    if(nativeOrder)return result;
    // Stable sort: equal keys keep the order WeChat returned them in.
    NSMutableArray *indexed=[NSMutableArray new];
    for(NSUInteger i=0;i<result.count;i++)[indexed addObject:@[result[i],@(i)]];
    [indexed sortUsingComparator:^NSComparisonResult(NSArray *a,NSArray *b){
        WPQuickChatSession *x=a[0],*y=b[0];
        if(x.pinned!=y.pinned)return x.pinned?NSOrderedAscending:NSOrderedDescending;
        if(x.time!=y.time)return x.time>y.time?NSOrderedAscending:NSOrderedDescending;
        return [a[1] compare:b[1]];
    }];
    NSMutableArray *ordered=[NSMutableArray new];for(NSArray *pair in indexed)[ordered addObject:pair[0]];
    return ordered;
}

@interface WPQuickChatTracker ()
@property (nonatomic) NSMutableDictionary<NSString *,NSNumber *> *known;
@property (nonatomic) NSMutableSet<NSString *> *alertable;
@property (nonatomic, readwrite) BOOL hasBaseline;
@end
@implementation WPQuickChatTracker
- (instancetype)init{if((self=[super init])){_known=[NSMutableDictionary new];_alertable=[NSMutableSet new];}return self;}
- (NSSet<NSString *> *)alertableUsernames{return [self.alertable copy];}
- (BOOL)hasAlertableUnread{return self.alertable.count>0;}
- (void)resetBaseline{self.hasBaseline=NO;}
- (NSArray<NSString *> *)observe:(NSArray<WPQuickChatSession *> *)sessions reportArrivals:(BOOL)reportArrivals {
    BOOL baseline=!self.hasBaseline && reportArrivals;
    NSMutableArray *arrivals=[NSMutableArray new];
    for(WPQuickChatSession *session in sessions){
        NSString *name=session.username;if(!name.length)continue;
        if(!session.unreadKnown){[self.alertable removeObject:name];continue;}
        NSNumber *previous=self.known[name];
        // A top row never seen before after the baseline is a new chat.
        BOOL rose=reportArrivals && !baseline && session.unread>(previous?previous.unsignedIntegerValue:0);
        if(rose && session.alertable && ![arrivals containsObject:name])[arrivals addObject:name];
        self.known[name]=@(session.unread);
        if(session.alertable)[self.alertable addObject:name];else [self.alertable removeObject:name];
    }
    if(baseline)self.hasBaseline=YES;
    return arrivals;
}
- (void)retainOnlyUsernames:(NSSet<NSString *> *)usernames {
    for(NSString *name in self.known.allKeys)if(![usernames containsObject:name])[self.known removeObjectForKey:name];
    [self.alertable intersectSet:usernames];
}
@end
