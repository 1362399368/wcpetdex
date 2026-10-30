#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface WPPetImporter : NSObject
+ (void)importZipAtURL:(NSURL *)url destinationRoot:(NSURL *)root completion:(void(^)(NSURL * _Nullable directory,NSError * _Nullable error))completion;
@end
NS_ASSUME_NONNULL_END
