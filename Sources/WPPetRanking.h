#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
/// Official Petdex most-installed top 60. Items have slug and installCount.
/// cached is YES only when using a previously fetched official ranking after
/// a network failure; an empty result and error mean ranking is unavailable.
typedef void (^WPPetRankingCompletion)(NSArray<NSDictionary *> *items, BOOL cached, NSError * _Nullable error);
@interface WPPetRanking : NSObject
+ (instancetype)sharedRanking;
- (void)loadWithCompletion:(WPPetRankingCompletion)completion;
@end
NS_ASSUME_NONNULL_END
