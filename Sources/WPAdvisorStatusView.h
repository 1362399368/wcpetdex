#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
/// Transient, pass-through overlay for advisor progress and the pet's unread badge.
/// Input items contain identifier, displayName and state strings only. No chat
/// contents are needed or retained. All methods and callbacks run on the main thread.
@interface WPAdvisorStatusView : UIView
@property(nonatomic,readonly) NSUInteger unreadCount;
@property(nonatomic,copy,nullable) void (^onCancelTask)(NSString *identifier);
@property(nonatomic,copy,nullable) void (^onShowTasks)(void);
@property(nonatomic,copy,nullable) void (^onOpenUnread)(void);
- (void)updateActiveTasks:(NSArray<NSDictionary<NSString *,id> *> *)tasks;
- (void)updateUnreadCount:(NSUInteger)count;
/// Set the visible latest-unread avatar's frame (in this view's coordinates),
/// or CGRectNull while it is hidden. The badge avoids its 44-point touch area.
- (void)setUnreadAvatarFrame:(CGRect)frame;
/// Coordinates are relative to this view. Safe bounds exclude system UI.
- (void)layoutInBounds:(CGRect)safeBounds petFrame:(CGRect)petFrame petVisible:(BOOL)visible;
@end

/// Generic task or history list; selection is identified by the stable task ID.
/// Records may contain identifier, displayName, detail, createdAt and unread.
@interface WPAdvisorHistoryController : UITableViewController
@property(nonatomic,copy,nullable) void (^onSelect)(NSString *identifier);
@property(nonatomic,copy,nullable) void (^onClear)(void);
- (instancetype)initWithTitle:(NSString *)title records:(NSArray<NSDictionary<NSString *,id> *> *)records allowsClear:(BOOL)allowsClear;
- (void)updateRecords:(NSArray<NSDictionary<NSString *,id> *> *)records;
@end
NS_ASSUME_NONNULL_END
