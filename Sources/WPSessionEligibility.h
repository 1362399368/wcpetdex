#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSNumber * _Nullable WPSEReadNumber(id _Nullable object, NSArray<NSString *> *keys);
FOUNDATION_EXPORT id _Nullable WPSEReadObject(id _Nullable object, NSArray<NSString *> *keys);
FOUNDATION_EXPORT BOOL WPSESessionHiddenOrFolded(id _Nullable session);
/// nil means notification metadata is unavailable; callers preserve privacy.
FOUNDATION_EXPORT NSNumber * _Nullable WPSESessionMuted(id _Nullable session, NSString *username);
/// Main-thread snapshot, up to 150 names per turn. nil until ready/unavailable.
FOUNDATION_EXPORT NSSet<NSString *> * _Nullable WPSEHomeNames(id _Nullable manager);
FOUNDATION_EXPORT void WPSEInvalidateHomeNames(void);
/// Lifecycle cancellation of unfinished roster slices, retaining no queued work.
FOUNDATION_EXPORT void WPSESetForegroundAvailable(BOOL available);
FOUNDATION_EXPORT NSDictionary *WPSEHomeDiagnostics(void);
NS_ASSUME_NONNULL_END
