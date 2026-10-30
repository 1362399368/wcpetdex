#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
/// Serial work queue shared by imports, migrations and image decoding. Callers
/// coalesce requests before enqueueing; at most one large legacy conversion runs.
FOUNDATION_EXPORT dispatch_queue_t WPPetAssetWorkQueue(void);
/// Convert v1–v4 once into a hidden, atomically published page directory. The
/// original selection and original files stay intact. This API must run off UI.
FOUNDATION_EXPORT NSString * _Nullable WPPagedLegacyDirectory(NSString *directory, NSDictionary *metadata, NSError **error);
FOUNDATION_EXPORT BOOL WPIsLocalPagedMetadata(NSDictionary *metadata);
NS_ASSUME_NONNULL_END
