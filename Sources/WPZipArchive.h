#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
/// Reads bounded, unencrypted, single-disk ZIPs. Returns relative paths and bytes.
FOUNDATION_EXPORT NSDictionary<NSString *, NSData *> * _Nullable WPReadPetZip(NSData *data, NSError **error);
/// Extracts into a new, exclusive directory. Returns relative paths and file URLs.
/// Each file is streamed through a 64 KiB buffer; any failure removes only this
/// newly-created directory. The caller removes it after validation/publication.
FOUNDATION_EXPORT NSDictionary<NSString *, NSURL *> * _Nullable WPExtractPetZip(NSData *data, NSURL *destination, NSError **error);
NS_ASSUME_NONNULL_END
