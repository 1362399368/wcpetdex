#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
/// Shared bounded avatar transfer used by the chat bar and unread indicator.
/// The completion runs on main. The original initializer allows 5 MiB and
/// decodes at most 160 pixels; callers may request smaller transfer budgets.
@interface WPQCAvatarDownload : NSObject
- (instancetype)initWithURL:(NSURL *)url completion:(void (^)(UIImage * _Nullable image))completion;
/// Budgets cannot exceed 5 MiB / 160 pixels. Zero bytes or an invalid pixel
/// value uses the corresponding default. Positive pixels are rounded down.
- (instancetype)initWithURL:(NSURL *)url maximumBytes:(NSUInteger)maximumBytes
             maximumPixels:(CGFloat)maximumPixels completion:(void (^)(UIImage * _Nullable image))completion;
- (void)start;
- (void)cancel;
@end
NS_ASSUME_NONNULL_END
