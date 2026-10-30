#import <Foundation/Foundation.h>

/// Resolve byte-identical known old Yue art to shipped corrected art.
/// Called once during reload; imported files and the selected reference are
/// never written. An unmatched ID, revision or file hash yields no override.
FOUNDATION_EXPORT NSDictionary<NSString *,NSString *> *WPKnownAtlasCorrections(NSString *directory,NSDictionary *metadata);
