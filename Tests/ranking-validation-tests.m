#import <Foundation/Foundation.h>
#import "../Sources/WPPetRanking.m"

static NSData *json(id object) { return [NSJSONSerialization dataWithJSONObject:object options:0 error:nil]; }
static void require(BOOL condition, NSString *message) { if(!condition){NSLog(@"FAIL: %@",message);exit(1);} }
int main(void) {
    @autoreleasepool {
        NSDictionary *first=@{@"slug":@"boba",@"metrics":@{@"installCount":@101}};
        NSDictionary *second=@{@"slug":@"lulu-capybara-2",@"metrics":@{@"installCount":@30}};
        NSArray *items=WPRankingParse(json(@{@"pets":@[first,second]}),NO);
        require(items.count==2 && [items[0][@"slug"] isEqual:@"boba"] && [items[1][@"installCount"] isEqual:@30],@"official rank retains order and count");
        require([WPRankingParse(json(@{@"pets":items}),YES) isEqual:items],@"cached official rank round trips");
        require(!WPRankingParse(json(@{@"pets":@[second,first]}),NO),@"unordered counts rejected");
        require(!WPRankingParse(json(@{@"pets":@[first,first]}),NO),@"duplicates rejected");
        require(!WPRankingParse(json(@{@"pets":@[@{@"slug":@"../bad",@"metrics":@{@"installCount":@2}}]}),NO),@"unsafe slugs rejected");
        require(!WPRankingParse(json(@{@"pets":@[@{@"slug":@"boba",@"metrics":@{@"installCount":@YES}}]}),NO),@"boolean counts rejected");
        require(!WPRankingParse(json(@{@"pets":@[]}),NO),@"empty responses not treated as ranking");
        NSLog(@"PASS: Petdex ranking normalization, ordering, cache and malformed responses");
    }
    return 0;
}
