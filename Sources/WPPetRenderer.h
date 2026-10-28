#import <UIKit/UIKit.h>

@interface WPPetRenderer : UIControl
@property (nonatomic, readonly) NSString *petName;
- (void)reloadPet;
/// A quiet message acknowledgement using this pet's existing tap animation.
/// It never interrupts dragging, edge peeking or another reaction.
- (BOOL)playMessageAcknowledgement;
/// Semantic action names may be mapped by a pet's optional semanticRows map.
/// Missing rows stay within this pet's own compatible atlas.
- (BOOL)playSemanticAction:(NSString *)action;
- (void)beginDragAnimation;
- (void)updateDragDirectionLeft:(BOOL)left;
- (void)endDragAnimation;
- (void)holdPeekOnLeft:(BOOL)left;
- (void)endPeek;
- (void)setAnimationActive:(BOOL)active;
@end

#ifdef WP_PREVIEW_HOST
/// Explicit fixture mode for existing exact-frame tests. Defaults to NO; new
/// asynchronous tests run the production path with this disabled.
FOUNDATION_EXPORT void WPPreviewSetAtlasLoadingSynchronous(BOOL enabled);
#endif
