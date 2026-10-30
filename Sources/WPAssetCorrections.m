#import "WPAssetCorrections.h"

// The single edition ships no edition-specific replacement images.
NSDictionary<NSString *,NSString *> *WPKnownAtlasCorrections(__unused NSString *directory,__unused NSDictionary *metadata) {
    return @{};
}
