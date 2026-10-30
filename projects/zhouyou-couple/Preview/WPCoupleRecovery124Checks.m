#import "WPCoupleRecovery124Checks.h"
#import "WPCoupleClient.h"
@interface WPCoupleClient (WPCR124Testing)
- (void)queryPendingStatuses:(NSArray<NSString *> *)identifiers offset:(NSUInteger)offset generation:(NSUInteger)generation;
@end
@interface WPCR124Client : WPCoupleClient
@property(nonatomic) NSMutableArray<NSString *> *sent;
@end
@implementation WPCR124Client
- (void)sendJSON:(NSDictionary *)message generation:(NSUInteger)generation{[self.sent addObject:message[@"id"]];}
@end
void WPCoupleRecovery124RunPreviewChecks(void (^completion)(NSDictionary<NSString *,NSNumber *> *)){
    WPCR124Client *client=[WPCR124Client new];client.sent=[NSMutableArray new];
    [client setValue:@YES forKey:@"connected"];[client setValue:@1 forKey:@"generation"];
    NSMutableArray *identifiers=[NSMutableArray new];for(NSUInteger i=0;i<40;i++)[identifiers addObject:NSUUID.UUID.UUIDString];
    [client setValue:[NSMutableSet setWithArray:identifiers] forKey:@"checking"];
    [client queryPendingStatuses:identifiers offset:0 generation:1];
    NSMutableDictionary *checks=[NSMutableDictionary new];checks[@"CR124InitialReconnectSendsOnlyEightStatuses"]=@(client.sent.count==8);
    [client setValue:@2 forKey:@"generation"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,40*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        checks[@"CR124OldGenerationCannotContinueStatusQueries"]=@(client.sent.count==8);
        [client.sent removeAllObjects];[client queryPendingStatuses:identifiers offset:0 generation:2];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,160*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
            checks[@"CR124ReconnectQueriesAllStatusesAfterYielding"]=@(client.sent.count==identifiers.count && [NSSet setWithArray:client.sent].count==identifiers.count);
            [client setValue:@NO forKey:@"connected"];[client.sent removeAllObjects];[client queryPendingStatuses:identifiers offset:0 generation:2];
            checks[@"CR124DisconnectedClientDoesNotStartStatusBatch"]=@(client.sent.count==0);completion(checks);
        });
    });
}
