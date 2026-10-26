#import <UIKit/UIKit.h>
@interface WPOverlayManager : NSObject
+ (instancetype)sharedManager;
- (void)start;
- (void)refresh;
/// Manual pause leaves the WeChat settings entry available for recovery.
- (BOOL)recoveryPaused;
- (void)setRecoveryPaused:(BOOL)paused;
- (void)retryRecovery;
- (NSDictionary<NSString *,id> *)recoveryDiagnostics;
- (BOOL)recoveryMaintenanceReady;
/// Keep the existing non-key floating window above app-owned page windows.
- (void)ensureFloatingOrder;
- (void)showMessage:(NSString *)text;
- (void)closePanel;
- (void)openSettings;
- (void)openInteractions;
/// Sends through the pair client; a miss replies to the pending snapshot taken now.
- (void)sendInteraction:(NSString *)kind completion:(void (^)(BOOL accepted, NSString *message))completion;
/// Text for the connection pill in settings.
- (NSString *)connectionStatus;
- (void)previewMenuRadius;
- (BOOL)configureCoupleURL:(NSURL *)url token:(NSString *)token;
- (BOOL)hasSavedCoupleToken;
/// Live peer status is available in this edition.
- (NSString *)peerStatusText;
- (BOOL)peerIsOnline;
@end
