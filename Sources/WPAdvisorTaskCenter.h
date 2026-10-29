#import <Foundation/Foundation.h>
#import "WPChatAdvisor.h"

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSNotificationName const WPAdvisorTasksDidChangeNotification;
/// Nil when the currently signed-in account cannot be identified.
FOUNDATION_EXPORT NSString * _Nullable WPAdvisorCurrentAccountFingerprint(void);
typedef NS_ENUM(NSInteger, WPAdvisorTaskState) {
    WPAdvisorTaskQueued, WPAdvisorTaskRunning, WPAdvisorTaskCompleted, WPAdvisorTaskFailed, WPAdvisorTaskCancelled
};

@interface WPAdvisorTask : NSObject
@property(nonatomic,copy,readonly) NSString *identifier;
@property(nonatomic,copy,readonly) NSString *username;
@property(nonatomic,copy,readonly) NSString *displayName;
@property(nonatomic,readonly) WPAdvisorTaskState state;
@property(nonatomic,readonly) NSUInteger lineCount;
/// Empty for records made before per-task scenes were stored.
@property(nonatomic,copy,readonly) NSString *presetIdentifier;
@property(nonatomic,strong,readonly) NSDate *createdAt;
@property(nonatomic,strong,readonly,nullable) WPChatAdvice *advice;
@property(nonatomic,copy,readonly,nullable) NSString *error;
@property(nonatomic,readonly) BOOL unread;
@property(nonatomic,readonly) BOOL stale;
@end

/// Both checks fail closed for missing account identity or legacy records.
FOUNDATION_EXPORT BOOL WPAdvisorTaskBelongsToCurrentAccount(WPAdvisorTask *task);
FOUNDATION_EXPORT BOOL WPAdvisorTaskMatchesLines(WPAdvisorTask *task, NSArray<WPChatLine *> *lines);
/// Selecting a scene must not follow a changed account or chat.
FOUNDATION_EXPORT BOOL WPAdvisorSelectionIsCurrent(NSString *account, NSString *username, UIWindow * _Nullable window);

/// All public methods and notifications run on the main thread. Raw messages
/// exist only in memory during analysis and are never written to disk.
@interface WPAdvisorTaskCenter : NSObject
@property(class,nonatomic,readonly) WPAdvisorTaskCenter *sharedCenter;
@property(nonatomic,copy,readonly) NSArray<WPAdvisorTask *> *activeTasks;
@property(nonatomic,copy,readonly) NSArray<WPAdvisorTask *> *unreadResults;
@property(nonatomic,copy,readonly) NSArray<WPAdvisorTask *> *history;
@property(nonatomic,copy,readonly) NSArray<WPAdvisorTask *> *failedTasks;
- (nullable WPAdvisorTask *)submitUsername:(NSString *)username displayName:(NSString *)displayName lines:(NSArray<WPChatLine *> *)lines group:(BOOL)group;
- (nullable WPAdvisorTask *)submitUsername:(NSString *)username displayName:(NSString *)displayName lines:(NSArray<WPChatLine *> *)lines group:(BOOL)group presetIdentifier:(NSString *)presetIdentifier;
- (void)cancelTask:(WPAdvisorTask *)task;
- (void)dismissFailedTask:(WPAdvisorTask *)task;
- (void)markResultRead:(WPAdvisorTask *)task;
- (void)markStaleForUsername:(NSString *)username;
- (void)clearHistory;
@end
NS_ASSUME_NONNULL_END
