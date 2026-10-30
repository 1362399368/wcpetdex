#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
typedef NS_ENUM(NSUInteger, WPRecoveryState) {
    WPRecoveryStateInactive, WPRecoveryStateHostReady, WPRecoveryStateWarming,
    WPRecoveryStateReady, WPRecoveryStateDegraded
};
/// Main-thread, single-flight foreground restoration. No private service is
/// called by this coordinator; stages execute only through the owner's blocks.
@interface WPRecoveryCoordinator : NSObject
@property(nonatomic,copy) BOOL (^calibrateHost)(void);
@property(nonatomic,copy) void (^captureMessages)(void);
@property(nonatomic,copy) void (^restoreRenderer)(void);
@property(nonatomic,copy) void (^restoreMonitoring)(void);
@property(nonatomic,copy) void (^restoreMaintenance)(void);
@property(nonatomic,copy,nullable) void (^phaseFailed)(NSString *phase);
@property(nonatomic,readonly) WPRecoveryState state;
@property(nonatomic,readonly) NSUInteger generation;
@property(nonatomic,readonly) BOOL foreground;
@property(nonatomic,readonly) BOOL temporarilySuspended;
- (void)beginForeground;
- (void)endForeground;
- (void)setTemporarilySuspended:(BOOL)suspended;
- (void)requestCalibration;
- (void)retry;
/// Counts/timing/phase names only; never receives user or message values.
- (NSDictionary<NSString *,id> *)diagnostics;
@end
NS_ASSUME_NONNULL_END
