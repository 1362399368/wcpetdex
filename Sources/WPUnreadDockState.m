#import "WPUnreadDockState.h"
#import "WPQuickChatModel.h"
#import "WPMessageBarrage.h"
#import <CommonCrypto/CommonDigest.h>
#import <math.h>

static NSUInteger const WPDockHistoryLimit=128;
static NSString *WPDockName(id value) {
    return [value isKindOfClass:NSString.class] && [value length]>0 && [value length]<=256 ? [value copy] : nil;
}
static NSString *WPDockDigest(NSString *value) {
    NSData *data=[value dataUsingEncoding:NSUTF8StringEncoding];unsigned char bytes[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes,(CC_LONG)data.length,bytes);NSMutableString *result=[NSMutableString stringWithCapacity:64];
    for(NSUInteger i=0;i<CC_SHA256_DIGEST_LENGTH;i++)[result appendFormat:@"%02x",bytes[i]];
    return result;
}
static NSString *WPDockMessageKey(WPBarrageMessage *message) {
    NSString *name=WPDockName(message.conversationUsername),*identifier=message.identifier;
    if(!name || ![identifier isKindOfClass:NSString.class] || !identifier.length || identifier.length>320 || message.localPreview)return nil;
    return WPDockDigest([NSString stringWithFormat:@"%lu:%@%@",(unsigned long)name.length,name,identifier]);
}

@interface WPDockReceipt : NSObject
@property(nonatomic,copy) NSString *conversation;
@property(nonatomic,copy) NSString *sender;
@property(nonatomic,copy) NSString *revision;
@property(nonatomic) NSUInteger order;
@property(nonatomic) NSUInteger confirmationOrder;
@property(nonatomic) BOOL nativeMessage;
@property(nonatomic) BOOL accepted;
@property(nonatomic) NSTimeInterval messageTime;
@property(nonatomic) CFTimeInterval receivedAt;
@property(nonatomic) NSTimeInterval pollTime;
@property(nonatomic) NSUInteger pollCount;
@property(nonatomic) BOOL pollBound;
@property(nonatomic) BOOL wasDocked;
@property(nonatomic) CFTimeInterval dockTime;
@end
@implementation WPDockReceipt @end

@interface WPDockLedger : NSObject
@property(nonatomic) BOOL hasPoll;
@property(nonatomic) NSTimeInterval pollTime;
@property(nonatomic) NSUInteger pollCount;
@property(nonatomic) NSUInteger revivalOrder;
@property(nonatomic,copy) NSString *pollRevision;
@property(nonatomic) NSTimeInterval acknowledgedPollTime;
@property(nonatomic) NSUInteger acknowledgedPollCount;
@property(nonatomic) WPDockReceipt *latestNative;
@end
@implementation WPDockLedger @end

@interface WPUnreadDockState ()
@property(nonatomic,copy,readwrite) NSString *conversationUsername;
@property(nonatomic,copy,readwrite) NSString *senderUsername;
@property(nonatomic,strong,readwrite) UIImage *image;
@property(nonatomic,copy,readwrite) NSString *revision;
@property(nonatomic) WPDockReceipt *current;
@property(nonatomic) NSMutableDictionary<NSString *,WPDockReceipt *> *receipts;
@property(nonatomic) NSMutableDictionary<NSString *,WPDockReceipt *> *revisions;
@property(nonatomic) NSMutableArray<NSString *> *receiptOrder;
@property(nonatomic) NSMutableArray<NSString *> *revisionOrder;
@property(nonatomic) NSMutableDictionary<NSString *,WPDockLedger *> *ledgers;
@property(nonatomic) NSMutableArray<NSString *> *ledgerOrder;
@property(nonatomic) NSUInteger sequence;
@property(nonatomic) NSUInteger acknowledgedOrder;
@property(nonatomic) NSTimeInterval acknowledgedClock;
@end

@implementation WPUnreadDockState
- (instancetype)init {
    if((self=[super init])){
        _receipts=[NSMutableDictionary new];_revisions=[NSMutableDictionary new];_receiptOrder=[NSMutableArray new];_revisionOrder=[NSMutableArray new];
        _ledgers=[NSMutableDictionary new];_ledgerOrder=[NSMutableArray new];
    }return self;
}
- (BOOL)isVisible {return self.revision.length>0 && self.conversationUsername.length>0;}
- (WPDockLedger *)ledger:(NSString *)name {
    WPDockLedger *ledger=self.ledgers[name];
    if(!ledger){ledger=[WPDockLedger new];self.ledgers[name]=ledger;[self.ledgerOrder addObject:name];}
    else {[self.ledgerOrder removeObject:name];[self.ledgerOrder addObject:name];}
    while(self.ledgerOrder.count>WPDockHistoryLimit){NSString *old=self.ledgerOrder.firstObject;[self.ledgerOrder removeObjectAtIndex:0];[self.ledgers removeObjectForKey:old];}
    return ledger;
}
- (void)rememberRevision:(WPDockReceipt *)receipt {
    self.revisions[receipt.revision]=receipt;[self.revisionOrder addObject:receipt.revision];
    while(self.revisionOrder.count>WPDockHistoryLimit){NSString *old=self.revisionOrder.firstObject;[self.revisionOrder removeObjectAtIndex:0];[self.revisions removeObjectForKey:old];}
}
- (void)displayReceipt:(WPDockReceipt *)receipt image:(UIImage *)image {
    self.current=receipt;self.conversationUsername=receipt.conversation;self.senderUsername=receipt.sender;
    self.revision=receipt.revision;self.image=image;
}
- (void)observeUnreadSession:(WPQuickChatSession *)session genuineArrival:(BOOL)genuineArrival {
    NSAssert(NSThread.isMainThread,@"Observe the dock on main");
    // Missing latest is only absence of a row, not evidence that this contact
    // became read. The owner reconciles our exact route via native typed state.
    if(!session)return;
    NSString *name=WPDockName(session.username);if(!name)return;
    if(!session.alertable){
        if(session.unreadKnown && [name isEqual:self.conversationUsername]){
            // An explicit typed observation is stronger than a missing latest
            // row, including a chat becoming read, muted, hidden or folded.
            [self consumeRevision:self.revision];
        }
        return;
    }
    NSTimeInterval time=isfinite(session.time)?MAX(0,session.time):0;
    WPDockLedger *ledger=[self ledger:name];
    BOOL growth=ledger.hasPoll && (time>MAX(ledger.pollTime,ledger.acknowledgedPollTime) || session.unread>MAX(ledger.pollCount,ledger.acknowledgedPollCount));
    WPDockReceipt *native=ledger.latestNative;
    // The native hook can finish a short capsule before the monitor's first
    // observation of that same message. Bind that first poll to its existing
    // receipt; its arrival flag alone does not create another unread message.
    BOOL bindFirst=native && !native.pollBound && time>0 && time<=native.messageTime && (genuineArrival || growth || !ledger.hasPoll);
    if(bindFirst){
        native.pollBound=YES;native.pollTime=time;native.pollCount=session.unread;
        if(native.order<=self.acknowledgedOrder){
            ledger.acknowledgedPollTime=MAX(ledger.acknowledgedPollTime,time);
            ledger.acknowledgedPollCount=MAX(ledger.acknowledgedPollCount,session.unread);
        }
    }
    BOOL nativeEcho=native.pollBound && time<=native.pollTime && session.unread<=native.pollCount;
    BOOL fresh=(genuineArrival || growth) && !nativeEcho;
    if(fresh)ledger.revivalOrder=++self.sequence;
    ledger.hasPoll=YES;ledger.pollTime=time;ledger.pollCount=session.unread;
    // Preserve the token captured by an in-flight chat open, and preserve the
    // cleared state if that open already completed. A newer native identifier
    // replaces latestNative, and a higher known count/time remains fresh.
    if(nativeEcho && (native.wasDocked || native.order<=self.acknowledgedOrder))return;
    BOOL currentIsNew=[name isEqual:self.conversationUsername] && self.current.order>self.acknowledgedOrder;
    BOOL suppressed=self.acknowledgedClock>0 && time<=self.acknowledgedClock && !fresh && !currentIsNew && ledger.revivalOrder<=self.acknowledgedOrder;
    // Keep the prior slot stable until the final capsule reaches it. Merely
    // observing another row never wins a race with the docking animation.
    if(self.playbackPending || suppressed)return;
    if(self.current.nativeMessage && !fresh)return;
    WPDockReceipt *receipt=!fresh?self.revisions[ledger.pollRevision]:nil;
    if(receipt && (receipt.pollTime!=time || receipt.pollCount!=session.unread))receipt=nil;
    if(!receipt){
        receipt=[WPDockReceipt new];receipt.conversation=name;receipt.sender=name;receipt.order=++self.sequence;
        receipt.revision=[NSString stringWithFormat:@"u:%lu",(unsigned long)receipt.order];receipt.accepted=YES;
        receipt.pollTime=time;receipt.pollCount=session.unread;receipt.messageTime=time;
        receipt.confirmationOrder=receipt.order;
        [self rememberRevision:receipt];ledger.pollRevision=receipt.revision;
    }
    if(receipt.order<=self.acknowledgedOrder)return;
    UIImage *image=[self.revision isEqual:receipt.revision]?self.image:nil;
    [self displayReceipt:receipt image:image];
}
- (NSString *)markBarrageMessageReceived:(WPBarrageMessage *)message {
    NSAssert(NSThread.isMainThread,@"Register a dock receipt on main");
    if(![message isKindOfClass:WPBarrageMessage.class])return nil;
    NSString *key=WPDockMessageKey(message);if(!key)return nil;
    WPDockReceipt *existing=self.receipts[key];if(existing)return existing.revision;
    NSString *name=WPDockName(message.conversationUsername),*sender=WPDockName(message.senderUsername)?:name;
    NSTimeInterval time=[message.createdAt isKindOfClass:NSDate.class]?message.createdAt.timeIntervalSince1970:0;
    if(!isfinite(time)||time<=0)return nil;
    WPDockLedger *ledger=[self ledger:name];
    WPDockReceipt *receipt=[WPDockReceipt new];receipt.conversation=name;receipt.sender=sender;receipt.order=++self.sequence;
    receipt.revision=[NSString stringWithFormat:@"m:%lu",(unsigned long)receipt.order];receipt.nativeMessage=YES;receipt.messageTime=time;receipt.receivedAt=CACurrentMediaTime();
    receipt.pollTime=ledger.pollTime;receipt.pollCount=ledger.pollCount;
    // Native createTime is often integer seconds. A previously unseen ID from
    // the consumption second can genuinely be new; a known ID retains its old
    // receipt above. Earlier timestamps cannot resurrect an acknowledged slot.
    receipt.accepted=!(self.acknowledgedClock>0 && time<floor(self.acknowledgedClock) && ledger.revivalOrder<=self.acknowledgedOrder);
    if(receipt.accepted)ledger.latestNative=receipt;
    self.receipts[key]=receipt;[self.receiptOrder addObject:key];[self rememberRevision:receipt];
    while(self.receiptOrder.count>WPDockHistoryLimit){NSString *old=self.receiptOrder.firstObject;[self.receiptOrder removeObjectAtIndex:0];[self.receipts removeObjectForKey:old];}
    return receipt.revision;
}
- (void)reconcileConversationUsername:(NSString *)username unreadState:(WPQuickChatUnreadState)state {
    NSAssert(NSThread.isMainThread,@"Reconcile the dock on main");
    if(!username.length || state==WPQuickChatUnreadStateUnknown || state==WPQuickChatUnreadStateUnread)return;
    CFTimeInterval now=CACurrentMediaTime();
    for(WPDockReceipt *receipt in self.revisions.allValues){
        if(![receipt.conversation isEqual:username])continue;
        // Native callbacks can precede WeChat updating the unread count. Denial
        // is immediate; count zero is authoritative after this short handoff.
        if(state==WPQuickChatUnreadStateRead && receipt.nativeMessage && now-receipt.receivedAt<2)continue;
        receipt.accepted=NO;
    }
    if([self.conversationUsername isEqual:username] && !self.current.accepted)[self consumeRevision:self.revision];
}
- (BOOL)shouldDockMessage:(WPBarrageMessage *)message {
    if(![message isKindOfClass:WPBarrageMessage.class])return NO;
    NSString *key=WPDockMessageKey(message);WPDockReceipt *receipt=key?self.receipts[key]:nil;
    return receipt.accepted && receipt.order>self.acknowledgedOrder && (!self.current || receipt.order>=self.current.order);
}
- (BOOL)dockMessage:(WPBarrageMessage *)message image:(UIImage *)image {
    NSAssert(NSThread.isMainThread,@"Dock a message on main");
    if(![self shouldDockMessage:message])return NO;
    WPDockReceipt *receipt=self.receipts[WPDockMessageKey(message)];WPDockLedger *ledger=[self ledger:receipt.conversation];
    receipt.pollTime=ledger.pollTime;receipt.pollCount=ledger.pollCount;
    receipt.wasDocked=YES;
    receipt.dockTime=CACurrentMediaTime();
    // Polling may have reported this same arrival while its capsule was moving.
    // Confirm the observations that already existed at docking, while preserving
    // any genuinely later receive/observation during the asynchronous chat open.
    receipt.confirmationOrder=self.sequence;
    [self displayReceipt:receipt image:image];return YES;
}
- (BOOL)consumeRevision:(NSString *)revision {
    NSAssert(NSThread.isMainThread,@"Consume a dock revision on main");
    if(![revision isKindOfClass:NSString.class] || !revision.length)return NO;
    WPDockReceipt *receipt=[self.current.revision isEqual:revision]?self.current:self.revisions[revision];if(!receipt)return NO;
    self.acknowledgedOrder=MAX(self.acknowledgedOrder,MAX(receipt.order,receipt.confirmationOrder));
    self.acknowledgedClock=MAX(self.acknowledgedClock,NSDate.date.timeIntervalSince1970);
    WPDockLedger *ledger=[self ledger:receipt.conversation];
    ledger.acknowledgedPollTime=MAX(ledger.acknowledgedPollTime,receipt.pollTime);
    ledger.acknowledgedPollCount=MAX(ledger.acknowledgedPollCount,receipt.pollCount);
    BOOL clearsCurrent=[self.revision isEqual:revision];if(clearsCurrent)[self resetVisibleOnly];return clearsCurrent;
}
- (void)clear {if(self.revision.length)[self consumeRevision:self.revision];}
- (void)releaseImageKeepingIdentity {self.image=nil;}
- (void)resetVisibleOnly {self.current=nil;self.conversationUsername=nil;self.senderUsername=nil;self.image=nil;self.revision=nil;}
- (NSDictionary<NSString *,NSNumber *> *)diagnostics {
    return @{@"visible":@(self.isVisible),@"playbackPending":@(self.playbackPending),@"receipts":@(self.receipts.count),@"revisions":@(self.revisions.count),@"conversations":@(self.ledgers.count),@"limit":@(WPDockHistoryLimit)};
}
@end
