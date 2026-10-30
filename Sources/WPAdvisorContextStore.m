#import "WPAdvisorContextStore.h"
#import "WPAdvisorTaskCenter.h"
#import <UIKit/UIKit.h>
#import <math.h>

@interface WPAdvisorContextStore ()
@property(nonatomic,strong) NSMutableDictionary<NSString *,NSMutableArray<WPChatLine *> *> *contexts;
@property(nonatomic,strong) NSMutableDictionary<NSString *,NSMutableOrderedSet<NSString *> *> *seen;
@property(nonatomic,strong) NSMutableSet<NSString *> *seeded;
@property(nonatomic,copy) NSString *accountFingerprint;
@end
@implementation WPAdvisorContextStore
+ (instancetype)sharedStore {static WPAdvisorContextStore *store;static dispatch_once_t once;dispatch_once(&once,^{store=[self new];});return store;}
- (instancetype)init {if((self=[super init])){_contexts=[NSMutableDictionary new];_seen=[NSMutableDictionary new];_seeded=[NSMutableSet new];[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(memoryWarning:) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];}return self;}
- (void)memoryWarning:(NSNotification *)note {[self clear];}
- (void)dealloc {[NSNotificationCenter.defaultCenter removeObserver:self];}
- (BOOL)valid:(NSString *)username {return [username isKindOfClass:NSString.class] && username.length && username.length<=256;}
- (BOOL)ensureAccount {
    NSString *account=WPAdvisorCurrentAccountFingerprint();
    if(![self.accountFingerprint isEqualToString:account]){[self clear];self.accountFingerprint=account;}
    return account.length>0;
}
- (void)trim:(NSMutableArray<WPChatLine *> *)lines {
    NSUInteger incoming=0,start=lines.count;
    for(NSUInteger i=lines.count;i>0;i--){WPChatLine *line=lines[i-1];start=i-1;if(!line.fromMe && ++incoming>=20)break;}
    if(start>0)[lines removeObjectsInRange:NSMakeRange(0,start)];
    while(lines.count>40)[lines removeObjectAtIndex:0];
}
- (WPChatLine *)copyLine:(WPChatLine *)line {
    NSString *text=line.text?:@"";if(text.length>300)text=[text substringWithRange:[text rangeOfComposedCharacterSequencesForRange:NSMakeRange(0,300)]];
    return [WPChatLine lineFromMe:line.fromMe speaker:@"" text:text date:line.date];
}
- (void)seedUsername:(NSString *)username visibleLines:(NSArray<WPChatLine *> *)lines {
    NSAssert(NSThread.isMainThread,@"Context store is main-thread only");
    if(![self ensureAccount] || ![self valid:username] || ![lines isKindOfClass:NSArray.class] || !lines.count)return;
    NSMutableArray *result=[NSMutableArray new];
    for(id line in lines)if([line isKindOfClass:WPChatLine.class] && [line text].length)[result addObject:[self copyLine:line]];
    if(!result.count)return;
    // Fresh native callbacks may arrive before the visible list catches up.
    for(WPChatLine *pending in self.contexts[username]?:@[]){
        BOOL present=NO;for(WPChatLine *loaded in result)if(!loaded.fromMe && [loaded.text isEqualToString:pending.text] && loaded.date && pending.date && fabs([loaded.date timeIntervalSinceDate:pending.date])<2){present=YES;break;}
        WPChatLine *last=result.lastObject;
        if(!present && !pending.fromMe && pending.date && (!last.date || [pending.date compare:last.date]!=NSOrderedAscending))[result addObject:pending];
    }
    [self trim:result];self.contexts[username]=result;[self.seeded addObject:username];
    while(self.contexts.count>8){NSString *victim=self.contexts.allKeys.firstObject;if([victim isEqual:username] && self.contexts.count>1)victim=self.contexts.allKeys.lastObject;[self removeUsername:victim];}
}
- (void)appendIncomingForUsername:(NSString *)username identifier:(NSString *)identifier text:(NSString *)text date:(NSDate *)date {
    NSAssert(NSThread.isMainThread,@"Context store is main-thread only");
    if(![self ensureAccount] || ![self valid:username] || !identifier.length || identifier.length>512 || ![text isKindOfClass:NSString.class] || !text.length || ![date isKindOfClass:NSDate.class])return;
    NSMutableOrderedSet *ids=self.seen[username];if(!ids){ids=[NSMutableOrderedSet new];self.seen[username]=ids;}if([ids containsObject:identifier])return;
    [ids addObject:identifier];while(ids.count>128)[ids removeObjectAtIndex:0];
    NSMutableArray *lines=self.contexts[username];if(!lines){lines=[NSMutableArray new];self.contexts[username]=lines;}
    WPChatLine *line=[WPChatLine lineFromMe:NO speaker:@"" text:text date:date];[lines addObject:[self copyLine:line]];[self trim:lines];
    while(self.contexts.count>8){NSString *victim=self.contexts.allKeys.firstObject;if([victim isEqual:username] && self.contexts.count>1)victim=self.contexts.allKeys.lastObject;[self removeUsername:victim];}
}
- (NSArray<WPChatLine *> *)snapshotForUsername:(NSString *)username {NSAssert(NSThread.isMainThread,@"Context store is main-thread only");if(![self ensureAccount])return nil;return [self.seeded containsObject:username]?[self.contexts[username] copy]:nil;}
- (void)removeUsername:(NSString *)username {[self.contexts removeObjectForKey:username];[self.seen removeObjectForKey:username];[self.seeded removeObject:username];}
- (void)clear {[self.contexts removeAllObjects];[self.seen removeAllObjects];[self.seeded removeAllObjects];}
@end
