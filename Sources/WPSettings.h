#import <UIKit/UIKit.h>
#import "WPTheme.h"
/// Plugin home: an info card, two-column feature cards and secondary pages.
@interface WPSettingsController : WPCardPageController
@property (nonatomic, copy) void (^onClose)(void);
@end
