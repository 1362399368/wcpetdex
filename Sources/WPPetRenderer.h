#import <UIKit/UIKit.h>

@interface WPPetRenderer : UIControl
@property (nonatomic, readonly) NSString *petName;
- (void)reloadPet;
- (void)playGreeting;
- (void)playAngry;
/// Coalesces: a reaction already playing is not restarted, and a different
/// one waits until the current reaction ends. Returns NO when coalesced.
- (BOOL)playReaction:(NSString *)kind;
/// A quiet message acknowledgement using this pet's existing tap animation.
/// It never interrupts anger, dragging, edge peeking or another reaction.
- (BOOL)playMessageAcknowledgement;
/// Local-only replay of a received interaction. The latest preview replaces an
/// earlier preview; an active edge reveal finishes before it starts.
- (BOOL)playLocalPreviewReaction:(NSString *)kind;
/// Semantic action names may be mapped by a pet's optional semanticRows map.
/// Missing rows stay within this pet's own compatible atlas.
- (BOOL)playSemanticAction:(NSString *)action;
- (void)beginDragAnimation;
- (void)updateDragDirectionLeft:(BOOL)left;
- (void)endDragAnimation;
- (void)holdPeekOnLeft:(BOOL)left;
- (void)endPeek;
/// Persistent look while a received anger needs a response. Reactions play
/// over it and the pet returns to it afterwards.
@property (nonatomic, getter=isAngry) BOOL angry;
/// Uses onlinePhoneRow only when the active pet explicitly declares one.
@property (nonatomic, getter=isPeerOnline) BOOL peerOnline;
- (void)setAnimationActive:(BOOL)active;
@end

#ifdef WP_PREVIEW_HOST
/// Explicit fixture mode for existing exact-frame tests. Defaults to NO; new
/// asynchronous tests run the production path with this disabled.
FOUNDATION_EXPORT void WPPreviewSetAtlasLoadingSynchronous(BOOL enabled);
#endif
