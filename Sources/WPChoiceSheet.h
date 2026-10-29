#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN

/// A single user-selected action. The action runs only after the sheet closes.
@interface WPChoiceItem : NSObject
@property(nonatomic,copy,readonly) NSString *title;
@property(nonatomic,copy,readonly,nullable) NSString *icon;
@property(nonatomic,readonly) BOOL destructive;
@property(nonatomic,copy,readonly,nullable) dispatch_block_t handler;
+ (instancetype)itemWithTitle:(NSString *)title icon:(nullable NSString *)icon destructive:(BOOL)destructive handler:(nullable dispatch_block_t)handler;
@end

/// A self-contained, passively presented sheet; no application-wide hooks.
@interface WPChoiceSheetController : UIViewController
- (instancetype)initWithTitle:(nullable NSString *)title items:(NSArray<WPChoiceItem *> *)items;
@end

/// Presents an adaptive translucent capsule sheet. Cancel is supplied automatically.
FOUNDATION_EXPORT void WPPresentChoiceSheet(UIViewController * _Nullable presenter, NSString * _Nullable title, NSArray<WPChoiceItem *> *items);
NS_ASSUME_NONNULL_END
