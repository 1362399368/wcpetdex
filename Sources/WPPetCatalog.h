#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^WPPetCatalogCompletion)(NSArray<NSDictionary *> *pets, NSError * _Nullable error);
typedef void (^WPPetCatalogPageCompletion)(NSArray<NSDictionary *> *pets, NSUInteger total, NSError * _Nullable error);
typedef void (^WPPetDownloadCompletion)(NSURL * _Nullable localDirectory, NSError * _Nullable error);

/// Petdex v1/v2 catalog. Downloaded pets stay in Application Support; only
/// network preview thumbnails for pets not yet downloaded use disposable cache.
/// All completion blocks run on the main queue.
/// Entries use slug/displayName/kind/submittedBy/spritesheetUrl/petJsonUrl/spriteVersionNumber.
/// A nonempty result plus an error means the last cached catalog is being shown offline.
@interface WPPetCatalog : NSObject
+ (instancetype)sharedCatalog;
+ (NSURL *)cacheRootDirectory;
- (void)loadPetsWithCompletion:(WPPetCatalogCompletion)completion;
/// page is zero-based. Search matches display name, slug and credited author.
- (void)loadPetsMatchingQuery:(nullable NSString *)query
                        page:(NSUInteger)page
                    pageSize:(NSUInteger)pageSize
                  completion:(WPPetCatalogPageCompletion)completion;
/// Returns a directory containing pet.json, a transparent spritesheet and catalog-entry.json.
- (void)downloadPet:(NSDictionary *)pet completion:(WPPetDownloadCompletion)completion;
@end

NS_ASSUME_NONNULL_END
