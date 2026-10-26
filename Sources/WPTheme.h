#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
/// Adaptive card colors follow the effective iOS light/dark appearance.
FOUNDATION_EXPORT UIColor *WPThemeBackground(void);
FOUNDATION_EXPORT UIColor *WPThemeCard(void);
FOUNDATION_EXPORT UIColor *WPThemeElevated(void);
FOUNDATION_EXPORT UIColor *WPThemePrimaryText(void);
FOUNDATION_EXPORT UIColor *WPThemeSecondaryText(void);
FOUNDATION_EXPORT UIColor *WPThemeOutgoingBubble(void);
FOUNDATION_EXPORT const CGFloat WPThemeCardRadius;
FOUNDATION_EXPORT void WPApplyThemeToNavigation(UINavigationController *navigation);
@interface WPAdaptiveNavigationController : UINavigationController
@end
FOUNDATION_EXPORT UIView *WPThemeIconTile(UIImage *image, UIColor *tint, CGFloat side);
FOUNDATION_EXPORT UILabel *WPThemePill(NSString *text, UIColor *color);
FOUNDATION_EXPORT UILabel *WPThemeLabel(NSString *_Nullable text, CGFloat size, UIFontWeight weight, UIColor *color);

/// A scrolling page of vertical card groups. Subclasses implement buildCards
/// and call reloadCards whenever their state changes.
@interface WPCardPageController : UIViewController
@property(nonatomic,readonly) UIScrollView *scrollView;
@property(nonatomic,readonly) UIStackView *stack;
- (void)buildCards;
- (void)reloadCards;
- (void)addSectionTitle:(NSString *)title;
- (void)addNote:(NSString *)text;
/// A rounded card whose rows are separated by spacing, not lines.
- (UIStackView *)addCard;
- (UIView *)rowWithTitle:(NSString *)title detail:(nullable NSString *)detail
             actionTitle:(nullable NSString *)actionTitle handler:(nullable void (^)(void))handler;
- (UIView *)switchRowWithTitle:(NSString *)title detail:(nullable NSString *)detail on:(BOOL)on handler:(void (^)(BOOL on))handler;
- (UIView *)sliderRowWithTitle:(NSString *)title value:(float)value minimum:(float)minimum maximum:(float)maximum
                        format:(NSString *(^)(float value))format handler:(void (^)(float value))handler;
- (UIView *)segmentedRowWithTitle:(NSString *)title items:(NSArray<NSString *> *)items selected:(NSInteger)selected handler:(void (^)(NSInteger index))handler;
- (UIView *)fieldRowWithTitle:(NSString *)title field:(UITextField *)field;
- (UIButton *)buttonWithTitle:(NSString *)title primary:(BOOL)primary handler:(void (^)(void))handler;
- (void)alert:(NSString *)message;
@end
NS_ASSUME_NONNULL_END
