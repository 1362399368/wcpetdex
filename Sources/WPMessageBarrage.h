#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
/// An ephemeral message snapshot; no chat message is persisted.
@interface WPBarrageMessage : NSObject
@property(nonatomic,copy) NSString *conversationUsername;
@property(nonatomic,copy) NSString *senderUsername;
@property(nonatomic,copy) NSString *text;
@property(nonatomic,copy) NSString *identifier;
@property(nonatomic,strong) NSDate *createdAt;
/// Explicit, local settings preview. Sources never set this flag; it avoids
/// looking up a fabricated WeChat contact or starting an avatar request.
@property(nonatomic) BOOL localPreview;
/// Positive source admission survives a transient metadata lookup gap.
/// Explicit current-chat/privacy denials still win at render time.
@property(nonatomic) BOOL sourceEligibilityConfirmed;
@end

/// All entry points run on main. The host owns the single retained avatar above
/// the pet. This controller owns only the bounded moving capsules.
@interface WPMessageBarrageController : NSObject
- (instancetype)initWithHostView:(UIView *)hostView;
@property(nonatomic,getter=isActive) BOOL active;
/// System interruptions pause existing animation/body in place. Background,
/// user disable retain their explicit purge boundary. Memory warnings trim work.
@property(nonatomic,getter=isTemporarilySuspended) BOOL temporarilySuspended;
@property(nonatomic,readonly) BOOL isDisplaying;
/// Pending/scrolling capsules.
@property(nonatomic,readonly) BOOL hasMovingMessages;
/// Compatibility status; 1.2.3 completes locally and never creates a flight.
@property(nonatomic,readonly) BOOL returningToDock;
@property(nonatomic,readonly,strong) UIView *view;
@property(nonatomic,copy,nullable) void (^onOpenConversation)(NSString *conversationUsername);
@property(nonatomic,copy,nullable) void (^onDock)(NSString *conversationUsername, NSString *senderUsername, UIImage * _Nullable image);
/// Compatibility callback with a body-free message identity. It runs only when
/// onBatchCompleted is absent; legacy onDock is the final fallback.
@property(nonatomic,copy,nullable) void (^onDockMessage)(WPBarrageMessage *message, UIImage * _Nullable image);
/// Once per completed burst, after the final capsule leaves the screen. The
/// host owns the small bounce above the pet; no avatar flies back across UI.
@property(nonatomic,copy,nullable) void (^onBatchCompleted)(WPBarrageMessage *message, UIImage * _Nullable image);
@property(nonatomic,copy,nullable) BOOL (^onShouldDock)(WPBarrageMessage *message);
/// Changes only when pending/scrolling state changes. A final batch callback
/// is delivered before the corresponding idle callback.
@property(nonatomic,copy,nullable) void (^onPlaybackChanged)(BOOL hasMovingOrReturning);
@property(nonatomic,copy,nullable) void (^onPetReaction)(void);
/// Rectangles are in hostView coordinates. Obstacles are NSValue CGRects.
- (void)updateLayoutSafeRect:(CGRect)safeRect obstacles:(NSArray<NSValue *> *)obstacles dockFrame:(CGRect)dockFrame;
- (void)enqueueMessage:(WPBarrageMessage *)message;
- (void)refreshPreferences;
/// Also used before the host disappears. Cancels work synchronously, including
/// pending bodies, displayed labels, downloads and cached decoded avatars.
- (void)purgeForMemoryPressure;
/// Memory warning: release queued bodies, requests/cache; finish visible capsules.
- (void)trimForMemoryPressure;
- (void)clearDock;
/// Uses presentation positions, so the empty full-screen container never takes
/// touches and the model's already-finished frame is not a ghost tap target.
- (nullable UIView *)hitTest:(CGPoint)hostPoint withEvent:(nullable UIEvent *)event;
@end
NS_ASSUME_NONNULL_END
