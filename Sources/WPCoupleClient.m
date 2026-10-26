#import "WPCoupleClient.h"
#import "WPCommon.h"
#import "WPBackendConfiguration.h"
#import "WPCoupleHistory.h"
#import "WPEdition.h"
#import <Security/Security.h>
#import <QuartzCore/QuartzCore.h>
#import <math.h>

static NSDictionary *WPTokenQuery(void){return @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,(__bridge id)kSecAttrService:@"dev.zhour.wechatpet.couple",(__bridge id)kSecAttrAccount:@"device"};}
static BOOL WPValidProtocolNumber(id value){
    if(![value isKindOfClass:NSNumber.class])return NO;
    double number=[value doubleValue];
    return isfinite(number) && number>=0 && number<(double)NSIntegerMax && floor(number)==number;
}
static BOOL WPValidJSONBoolean(id value){
    if(![value isKindOfClass:NSNumber.class])return NO;
    double number=[value doubleValue];return number==0 || number==1;
}
@interface WPCoupleClient () <NSURLSessionWebSocketDelegate>
@property(nonatomic) NSURL *url;
@property(nonatomic,copy) NSString *token;
@property(nonatomic) NSURLSession *session;
@property(nonatomic) NSURLSessionWebSocketTask *socket;
@property(nonatomic) NSMutableDictionary<NSString *,void (^)(BOOL,NSString *)> *callbacks;
@property(nonatomic) NSMutableSet<NSString *> *checking;
@property(nonatomic,copy) NSString *inflight;
@property(nonatomic) NSTimeInterval nextSendAt;
@property(nonatomic,readwrite,getter=isConnected) BOOL connected;
@property(nonatomic) BOOL wantsConnection;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) NSUInteger reconnectAttempt;
@property(nonatomic,readwrite) NSTimeInterval serverClockOffset;
@property(nonatomic) NSInteger protocolVersion;
@property(nonatomic,readwrite) BOOL stealthEffective;
@property(nonatomic) NSDictionary *peerSnapshot;
@property(nonatomic) CFTimeInterval peerSnapshotMonotonic;
@property(nonatomic) NSUInteger peerSnapshotSequence;
@property(nonatomic) NSInteger peerStatusVersion;
@property(nonatomic) BOOL stealthUnsupported;
- (BOOL)hasFreshPeerSnapshot;
@end
@implementation WPCoupleClient
- (instancetype)init{
    if((self=[super init])){
        _callbacks=[NSMutableDictionary new];_checking=[NSMutableSet new];
        NSString *saved=[WPPreferences() stringForKey:@"coupleURL"];
        NSString *migrated=WPMigratedCoupleURLString(saved);
        if(saved.length && migrated.length && ![saved isEqualToString:migrated])[WPPreferences() setObject:migrated forKey:@"coupleURL"];
        _url=migrated.length?[NSURL URLWithString:migrated]:nil;
        NSMutableDictionary *query=WPTokenQuery().mutableCopy;query[(__bridge id)kSecReturnData]=@YES;CFTypeRef result=NULL;
        if(SecItemCopyMatching((__bridge CFDictionaryRef)query,&result)==errSecSuccess)_token=[[NSString alloc] initWithData:CFBridgingRelease(result) encoding:NSUTF8StringEncoding];
    }return self;
}
- (void)status:(NSString *)value{if(self.onStatusChange)self.onStatusChange(value);}
- (BOOL)stealthEnabled{return WPCanUsePrivateFeatures() && [WPPreferences() boolForKey:@"stealthEnabled"];}
- (void)setStealthEnabled:(BOOL)enabled{
    if(!WPCanUsePrivateFeatures())return;
    if(self.stealthEnabled==enabled)return;
    [WPPreferences() setBool:enabled forKey:@"stealthEnabled"];
    self.stealthUnsupported=NO;
    BOOL resume=self.wantsConnection;
    [self disconnect];
    if(resume)[self connect];
    if(self.onPeerStatusChange)self.onPeerStatusChange();
}
- (NSString *)stealthStatusText{
    if(!WPCanUsePrivateFeatures())return @"";
    if(!self.stealthEnabled)return @"隐身已关闭";
    if(self.stealthUnsupported)return @"当前同步服务不支持隐身";
    if(self.stealthEffective && self.connected)return @"隐身中";
    return self.connected?@"当前服务不支持隐身":@"隐身待连接确认";
}
- (NSString *)peerStatusText{
    if(!WPCanUsePrivateFeatures())return @"";
    NSDictionary *snapshot=self.peerSnapshot;
    if(![self hasFreshPeerSnapshot])return @"状态未知";
    if([self peerIsOnline])return @"宝宝在线";
    NSNumber *last=snapshot[@"last_online"];
    NSNumber *server=snapshot[@"server_time"];
    if(![last isKindOfClass:NSNumber.class] || ![server isKindOfClass:NSNumber.class] || !isfinite(last.doubleValue) || !isfinite(server.doubleValue) || last.doubleValue<=0)return @"宝宝不在线";
    NSTimeInterval elapsed=MAX(0,server.doubleValue-last.doubleValue+CACurrentMediaTime()-self.peerSnapshotMonotonic);
    if(elapsed<60)return @"宝宝刚刚在线";
    if(elapsed<3600)return [NSString stringWithFormat:@"宝宝 %.0f分钟前在线",floor(elapsed/60)];
    if(elapsed<86400)return [NSString stringWithFormat:@"宝宝 %.0f小时前在线",floor(elapsed/3600)];
    return [NSString stringWithFormat:@"宝宝 %.0f天前在线",floor(elapsed/86400)];
}
- (BOOL)hasFreshPeerSnapshot{
    return WPCanUsePrivateFeatures() && self.connected && self.protocolVersion>=3 && self.peerSnapshot &&
        CACurrentMediaTime()-self.peerSnapshotMonotonic<=60;
}
- (BOOL)peerIsOnline{
    return [self hasFreshPeerSnapshot] && [self.peerSnapshot[@"online"] boolValue];
}
- (BOOL)hasSavedToken{return self.token.length>=32;}
- (BOOL)configureURL:(NSURL *)url pairToken:(NSString *)token{
    NSAssert(NSThread.isMainThread,@"Use couple client on main queue");
    if(!WPIsValidCoupleURL(url)){[self status:@"服务地址必须是以 /v1/ws 结尾的安全连接"];return NO;}
    NSString *nextToken=token.length?token:self.token;
    if(nextToken.length<32){[self status:@"请填写本机完整的同步令牌"];return NO;}
    NSString *oldIdentity=[WPPreferences() stringForKey:@"coupleIdentityDigest"];
    NSString *nextIdentity=WPTokenIdentityDigest(nextToken);
    // A gateway/domain change still reaches the same pair. Only changing the
    // device token can retire records belonging to a different pair. Legacy
    // URL+token digests are upgraded using the token stored in Keychain.
    BOOL identityChanged=WPCoupleTokenChangeRequiresExpiry(self.token,oldIdentity,nextToken,WPCoupleHistory.sharedHistory.pendingCount);
    [self disconnect];
    if(identityChanged && ![WPCoupleHistory.sharedHistory expireAllPending]){[self status:@"未能保存旧配对的待送达状态，连接配置未更换"];return NO;}
    self.url=url;[WPPreferences() setObject:url.absoluteString?:@"" forKey:@"coupleURL"];
    if(token.length){self.token=token;NSData *data=[token dataUsingEncoding:NSUTF8StringEncoding];OSStatus result=SecItemUpdate((__bridge CFDictionaryRef)WPTokenQuery(),(__bridge CFDictionaryRef)@{(__bridge id)kSecValueData:data});
        if(result==errSecItemNotFound){NSMutableDictionary *entry=WPTokenQuery().mutableCopy;entry[(__bridge id)kSecValueData]=data;entry[(__bridge id)kSecAttrAccessible]=(__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;result=SecItemAdd((__bridge CFDictionaryRef)entry,NULL);}
        if(result!=errSecSuccess)[self status:@"令牌未能保存，下次启动需重新填写"];
    }[WPPreferences() setObject:nextIdentity forKey:@"coupleIdentityDigest"];[WPPreferences() removeObjectForKey:@"coupleToken"];return YES;
}
- (void)clearConfiguration{[self disconnect];self.url=nil;self.token=nil;SecItemDelete((__bridge CFDictionaryRef)WPTokenQuery());[WPPreferences() removeObjectForKey:@"coupleURL"];[WPPreferences() removeObjectForKey:@"coupleToken"];}
- (BOOL)validConfiguration{
    return WPIsValidCoupleURL(self.url) && self.token.length>=32;
}
- (void)connect{
    NSAssert(NSThread.isMainThread,@"Use couple client on main queue");if(self.socket)return;
    if(![self validConfiguration]){[self status:@"尚未配置双人连接"];return;}
    self.wantsConnection=YES;NSUInteger generation=++self.generation;self.protocolVersion=0;self.peerStatusVersion=0;
    NSTimeInterval timeout=WPCoupleConnectTimeout();
    NSURLSessionConfiguration *config=NSURLSessionConfiguration.ephemeralSessionConfiguration;config.timeoutIntervalForRequest=timeout;config.URLCache=nil;
    self.session=[NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:NSOperationQueue.mainQueue];
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:self.url];[request setValue:[@"Bearer " stringByAppendingString:self.token] forHTTPHeaderField:@"Authorization"];
    [request setValue:@"3" forHTTPHeaderField:@"X-Pet-Protocol"];
    if(WPCanUsePrivateFeatures())[request setValue:self.stealthEnabled?@"1":@"0" forHTTPHeaderField:@"X-Pet-Hidden"];
    self.socket=[self.session webSocketTaskWithRequest:request];self.socket.maximumMessageSize=16384;
    [self status:@"正在连接双人桌宠…"];[self.socket resume];[self receiveForGeneration:generation];
    __weak typeof(self) weakSelf=self;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(timeout*NSEC_PER_SEC)),dispatch_get_main_queue(),^{if(weakSelf.generation==generation && weakSelf.socket && !weakSelf.connected)[weakSelf connectionFailed:generation error:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil]];});
}
- (void)failCallbacks:(NSString *)reason{
    NSDictionary *callbacks=self.callbacks.copy;[self.callbacks removeAllObjects];self.inflight=nil;[self.checking removeAllObjects];
    for(void (^callback)(BOOL,NSString *) in callbacks.allValues)callback(NO,reason);
}
- (void)disconnect{
    self.wantsConnection=NO;self.generation++;self.connected=NO;self.stealthEffective=NO;self.peerSnapshot=nil;
    if(self.onPeerStatusChange)self.onPeerStatusChange();
    [self.socket cancelWithCloseCode:NSURLSessionWebSocketCloseCodeGoingAway reason:nil];self.socket=nil;
    [self.session invalidateAndCancel];self.session=nil;[self failCallbacks:@"发送状态已保留，下次进入微信继续确认"];
}
- (void)connectionFailed:(NSUInteger)generation{
    [self connectionFailed:generation error:nil];
}
- (void)connectionFailed:(NSUInteger)generation error:(NSError *)error{
    if(generation!=self.generation||!self.socket)return;self.connected=NO;self.stealthEffective=NO;self.peerSnapshot=nil;
    if(self.onPeerStatusChange)self.onPeerStatusChange();
    NSInteger statusCode=[self.socket.response isKindOfClass:NSHTTPURLResponse.class]?((NSHTTPURLResponse *)self.socket.response).statusCode:0;
    NSMutableDictionary *diagnostic=[@{@"host":self.url.host?:@"",@"path":self.url.path?:@"",
        @"timestamp":@(NSDate.date.timeIntervalSince1970),@"httpStatus":@(statusCode)} mutableCopy];
    if(error){diagnostic[@"errorDomain"]=error.domain?:@"";diagnostic[@"errorCode"]=@(error.code);}
    [WPPreferences() setObject:diagnostic forKey:@"lastSyncConnectionFailure"];
    [self.socket cancelWithCloseCode:NSURLSessionWebSocketCloseCodeGoingAway reason:nil];self.socket=nil;
    [self.session invalidateAndCancel];self.session=nil;[self failCallbacks:@"网络断开，待送达记录已保留"];
    [self status:WPCoupleConnectionFailureMessage(error,statusCode)];
    if(!self.wantsConnection)return;NSTimeInterval delay=MIN(30,pow(2,MIN(self.reconnectAttempt++,5)));
    __weak typeof(self) weakSelf=self;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay*NSEC_PER_SEC)),dispatch_get_main_queue(),^{if(weakSelf.wantsConnection&&weakSelf.generation==generation)[weakSelf connect];});
}
- (void)sendJSON:(NSDictionary *)json generation:(NSUInteger)generation{
    NSData *data=[NSJSONSerialization dataWithJSONObject:json options:0 error:nil];if(!data||!self.socket)return;
    __weak typeof(self) weakSelf=self;[self.socket sendMessage:[[NSURLSessionWebSocketMessage alloc] initWithData:data] completionHandler:^(NSError *error){if(error)dispatch_async(dispatch_get_main_queue(),^{[weakSelf connectionFailed:generation error:error];});}];
}
- (void)receiveForGeneration:(NSUInteger)generation{
    __weak typeof(self) weakSelf=self;[self.socket receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage *message,NSError *error){dispatch_async(dispatch_get_main_queue(),^{
        WPCoupleClient *client=weakSelf;if(!client||generation!=client.generation)return;if(error){[client connectionFailed:generation error:error];return;}
        NSData *data=message.type==NSURLSessionWebSocketMessageTypeData?message.data:[message.string dataUsingEncoding:NSUTF8StringEncoding];
        id payload=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;if([payload isKindOfClass:NSDictionary.class])[client handle:payload generation:generation];[client receiveForGeneration:generation];
    });}];
}
- (NSDictionary *)outgoing:(NSString *)identifier{for(NSDictionary *row in WPCoupleHistory.sharedHistory.pendingOutgoing)if([row[@"id"] isEqual:identifier])return row;return nil;}
- (void)finishCallback:(NSString *)identifier success:(BOOL)success message:(NSString *)message{
    void (^callback)(BOOL,NSString *)=self.callbacks[identifier];[self.callbacks removeObjectForKey:identifier];if(callback)callback(success,message);
}
- (void)scheduleTransmit{
    NSUInteger generation=self.generation;NSTimeInterval delay=MAX(0,self.nextSendAt-NSDate.date.timeIntervalSince1970);
    __weak typeof(self) weakSelf=self;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay*NSEC_PER_SEC)),dispatch_get_main_queue(),^{if(weakSelf.generation==generation)[weakSelf transmitNext];});
}
- (void)transmitNext{
    if(!self.connected||self.inflight.length||self.checking.count||self.stealthEnabled)return;
    [WPCoupleHistory.sharedHistory expireOldOutgoing];
    if(NSDate.date.timeIntervalSince1970<self.nextSendAt){[self scheduleTransmit];return;}
    for(NSDictionary *row in WPCoupleHistory.sharedHistory.pendingOutgoing){
        if(![row[@"state"] isEqual:@"waiting"])continue;
        if([row[@"kind"] isEqual:@"pet"] && self.protocolVersion<3){
            [WPCoupleHistory.sharedHistory updateIdentifier:row[@"id"] state:@"failed" serverTime:nil];
            [self finishCallback:row[@"id"] success:NO message:@"当前同步服务不支持摸摸头，请先升级服务"];
            continue;
        }
        NSString *identifier=row[@"id"];self.inflight=identifier;self.nextSendAt=NSDate.date.timeIntervalSince1970+3.1;NSUInteger generation=self.generation;
        [self sendJSON:@{@"type":row[@"kind"],@"id":identifier} generation:generation];
        __weak typeof(self) weakSelf=self;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,15*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(weakSelf.generation==generation&&[weakSelf.inflight isEqual:identifier])[weakSelf connectionFailed:generation];});return;
    }
}
- (void)queryPendingStatuses:(NSArray<NSString *> *)identifiers offset:(NSUInteger)offset generation:(NSUInteger)generation{
    if(generation!=self.generation || !self.connected)return;
    NSUInteger end=MIN(identifiers.count,offset+8);
    for(NSUInteger index=offset;index<end;index++)if([self.checking containsObject:identifiers[index]])
        [self sendJSON:@{@"type":@"status",@"id":identifiers[index]} generation:generation];
    if(end<identifiers.count){
        __weak typeof(self) weakSelf=self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,16*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[weakSelf queryPendingStatuses:identifiers offset:end generation:generation];});
    }
}
- (void)handle:(NSDictionary *)event generation:(NSUInteger)generation{
    if(![event isKindOfClass:NSDictionary.class] || generation!=self.generation)return;
    NSString *type=[event[@"type"] isKindOfClass:NSString.class]?event[@"type"]:@"";
    NSString *identifier=[event[@"id"] isKindOfClass:NSString.class]?event[@"id"]:@"";
    WPCoupleHistory *history=WPCoupleHistory.sharedHistory;
    if([type isEqual:@"ready"]){
        id protocol=event[@"protocol"],hidden=event[@"hidden_applied"];
        // JSON null, arrays and strings must never reach numeric selectors.
        // A repeated ready frame must not create another heartbeat chain.
        if(!WPValidProtocolNumber(protocol) || (hidden && !WPValidJSONBoolean(hidden)))return;
        if([protocol integerValue]<2){[self status:@"同步服务需要升级到新版协议"];return;}
        if(self.connected)return;
        self.protocolVersion=[protocol integerValue];
        if(self.stealthEnabled && (self.protocolVersion<3 || ![hidden boolValue])){
            [self disconnect];self.stealthUnsupported=YES;
            [self status:@"当前同步服务不支持隐身，已停止连接以避免公开接收回执"];
            if(self.onPeerStatusChange)self.onPeerStatusChange();
            return;
        }
        self.stealthEffective=self.stealthEnabled && self.protocolVersion>=3;
        self.stealthUnsupported=NO;
        self.connected=YES;self.reconnectAttempt=0;[self updateServerClockOffset];[self status:@"双人桌宠已连接"];[history expireOldOutgoing];[self.checking removeAllObjects];
        if(self.onPeerStatusChange)self.onPeerStatusChange();
        [self scheduleHeartbeatForGeneration:generation];
        [WPPreferences() removeObjectForKey:@"lastSyncConnectionFailure"];
        NSMutableArray<NSString *> *pendingIdentifiers=[NSMutableArray new];
        for(NSDictionary *row in history.pendingOutgoing){[self.checking addObject:row[@"id"]];[pendingIdentifiers addObject:row[@"id"]];}
        [self queryPendingStatuses:pendingIdentifiers.copy offset:0 generation:generation];
        if(self.checking.count){__weak typeof(self) weakSelf=self;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,15*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(weakSelf.generation==generation && weakSelf.checking.count)[weakSelf connectionFailed:generation];});}
        if(!self.checking.count)[self transmitNext];return;
    }
    if([type isEqual:@"peer_status"] && WPCanUsePrivateFeatures()){
        NSNumber *version=event[@"version"],*server=event[@"server_time"];
        if(!WPValidProtocolNumber(version) || ![server isKindOfClass:NSNumber.class] || !isfinite(server.doubleValue) || server.doubleValue<=0 || version.integerValue<self.peerStatusVersion)return;
        if(!WPValidJSONBoolean(event[@"online"]))return;
        id last=event[@"last_online"];
        if(last!=NSNull.null && last && (![last isKindOfClass:NSNumber.class] || !isfinite([last doubleValue]) || [last doubleValue]<=0))return;
        self.peerStatusVersion=version.integerValue;self.peerSnapshot=event;self.peerSnapshotMonotonic=CACurrentMediaTime();
        NSUInteger snapshotSequence=++self.peerSnapshotSequence;
        __weak typeof(self) weakSelf=self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(60.05*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
            typeof(self) strongSelf=weakSelf;
            if(!strongSelf || strongSelf.generation!=generation || strongSelf.peerSnapshotSequence!=snapshotSequence ||
                !strongSelf.connected || !strongSelf.peerSnapshot || [strongSelf hasFreshPeerSnapshot])return;
            if(strongSelf.onPeerStatusChange)strongSelf.onPeerStatusChange();
        });
        if(self.onPeerStatusChange)self.onPeerStatusChange();return;
    }
    if(![[NSUUID alloc] initWithUUIDString:identifier])return;
    if([@[@"miss",@"anger",@"pet"] containsObject:type]){
        NSNumber *stamp=[event[@"sent_at"] isKindOfClass:NSNumber.class]?event[@"sent_at"]:nil;
        if(!stamp||!isfinite(stamp.doubleValue)||stamp.doubleValue<=0)return;
        NSDate *date=[NSDate dateWithTimeIntervalSince1970:stamp.doubleValue];BOOL isNew=NO;
        // sent_at is server time; compare it with the receive moment on the same clock.
        NSDate *receivedAt=[NSDate dateWithTimeIntervalSinceNow:self.serverClockOffset];
        if([history receiveKind:type identifier:identifier at:date receivedAt:receivedAt isNew:&isNew]){
            if(isNew&&self.onInteraction){
                BOOL needsResponse=NO;for(NSDictionary *row in history.pendingIncoming)if([row[@"id"] isEqual:identifier])needsResponse=YES;
                self.onInteraction(type,identifier,date,needsResponse);
            }
            [self sendJSON:@{@"type":@"ack",@"id":identifier} generation:generation];
        }else [self connectionFailed:generation];return;
    }
    NSDictionary *row=[self outgoing:identifier];
    if([type isEqual:@"delivered"] || ([type isEqual:@"status"]&&[event[@"state"] isEqual:@"delivered"])){
        BOOL stored=[history updateIdentifier:identifier state:@"delivered" serverTime:event[@"sent_at"]];
        if(row && !stored){[self finishCallback:identifier success:NO message:@"送达确认未能保存，稍后将重新核对发送状态"];[self connectionFailed:generation];return;}
        [self.checking removeObject:identifier];
        if([self.inflight isEqual:identifier])self.inflight=nil;
        if(stored&&row&&self.onDelivered)self.onDelivered(row[@"kind"]);
        [self finishCallback:identifier success:YES message:@"已送达对方桌宠"];[self scheduleTransmit];return;
    }
    if([type isEqual:@"status"]){
        [self.checking removeObject:identifier];
        if(row){NSString *state=[event[@"state"] isEqual:@"queued"]?@"queued":@"waiting";if(![history updateIdentifier:identifier state:state serverTime:event[@"sent_at"]]){[self connectionFailed:generation];return;}
        }
        [self scheduleTransmit];return;
    }
    if([type isEqual:@"accepted"]){
        if(row && ![history updateIdentifier:identifier state:[event[@"state"] isEqual:@"online"]?@"online":@"queued" serverTime:event[@"sent_at"]]){[self connectionFailed:generation];return;}
        if([self.inflight isEqual:identifier])self.inflight=nil;
        [self finishCallback:identifier success:YES message:[event[@"state"] isEqual:@"online"]?@"已发出，等待对方桌宠确认":@"对方暂不在线，已保留待送达"];
        [self scheduleTransmit];return;
    }
    if([type isEqual:@"error"]){
        if([self.inflight isEqual:identifier])self.inflight=nil;[self.checking removeObject:identifier];
        NSString *code=[event[@"code"] isKindOfClass:NSString.class]?event[@"code"]:@"";
        if([code isEqual:@"rate_limited"]||[code isEqual:@"service_unavailable"]){self.nextSendAt=NSDate.date.timeIntervalSince1970+3.2;[self scheduleTransmit];}
        else{if(row)[history updateIdentifier:identifier state:@"failed" serverTime:nil];[self finishCallback:identifier success:NO message:@"尚未送达，记录已保留，可在互动记录中查看"];[self scheduleTransmit];}
    }
}
- (void)sendInteraction:(NSString *)kind completion:(void (^)(BOOL,NSString *))completion{
    NSAssert(NSThread.isMainThread,@"Use couple client on main queue");
    if(![@[@"miss",@"anger",@"pet"] containsObject:kind]){completion(NO,@"互动类型不支持");return;}
    if(self.stealthEnabled){completion(NO,@"隐身中，先关闭隐身再发送互动");return;}
    if(![self validConfiguration]){completion(NO,@"请先在设置里填写本机的同步令牌");return;}
    WPCoupleHistory *history=WPCoupleHistory.sharedHistory;
    // Snapshot at the tap. It resolves only after the server accepts this
    // miss; anything received while sending belongs to a later batch.
    NSArray<NSString *> *incomingIDs=[kind isEqual:@"anger"]?@[]:[history responseIdentifiersForKind:kind];
    NSString *identifier=NSUUID.UUID.UUIDString;
    if(![history enqueueKind:kind identifier:identifier at:NSDate.date resolvingIncomingIdentifiers:incomingIDs]){completion(NO,@"未能保存互动，或待送达已达到100条");return;}
    self.callbacks[identifier]=[completion copy];
    if(self.connected)[self scheduleTransmit];
    else{[self connect];[self finishCallback:identifier success:NO message:incomingIDs.count?@"已保存在本机，连接后继续发送；送达服务器后才清除红点":@"已保存在本机，连接后继续发送"];}
}
- (void)scheduleHeartbeatForGeneration:(NSUInteger)generation{
    if(!self.connected || generation!=self.generation)return;
    [self sendJSON:@{@"type":@"heartbeat",@"id":NSUUID.UUID.UUIDString} generation:generation];
    if(WPCanUsePrivateFeatures())[self sendJSON:@{@"type":@"peer_status",@"id":NSUUID.UUID.UUIDString} generation:generation];
    __weak typeof(self) weakSelf=self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,20*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        if(weakSelf.connected && generation==weakSelf.generation)[weakSelf scheduleHeartbeatForGeneration:generation];
    });
}
- (void)updateServerClockOffset{
    NSHTTPURLResponse *response=[self.socket.response isKindOfClass:NSHTTPURLResponse.class]?(id)self.socket.response:nil;
    NSString *header=nil;
    for(NSString *key in response.allHeaderFields)if([key caseInsensitiveCompare:@"Date"]==NSOrderedSame)header=response.allHeaderFields[key];
    NSDateFormatter *format=[NSDateFormatter new];format.locale=[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    format.timeZone=[NSTimeZone timeZoneForSecondsFromGMT:0];format.dateFormat=@"EEE, dd MMM yyyy HH:mm:ss zzz";
    NSDate *server=[header isKindOfClass:NSString.class]?[format dateFromString:header]:nil;
    // Date has whole-second precision; only correct a clearly wrong phone clock.
    NSTimeInterval offset=server?server.timeIntervalSinceNow+.5:0;
    self.serverClockOffset=fabs(offset)>=5?offset:0;
}
- (void)sendMissYou:(void (^)(BOOL,NSString *))completion{[self sendInteraction:@"miss" completion:completion];}
- (void)URLSession:(NSURLSession *)session webSocketTask:(NSURLSessionWebSocketTask *)task didOpenWithProtocol:(NSString *)protocol{if(task==self.socket)[self status:@"正在确认待送达记录…"];}
- (void)URLSession:(NSURLSession *)session webSocketTask:(NSURLSessionWebSocketTask *)task didCloseWithCode:(NSURLSessionWebSocketCloseCode)code reason:(NSData *)reason{
    if(task!=self.socket)return;
    [self connectionFailed:self.generation];
    if(code==4001)[self status:@"本机令牌已在另一处连接；两台手机请使用各自的令牌"];
}
@end
