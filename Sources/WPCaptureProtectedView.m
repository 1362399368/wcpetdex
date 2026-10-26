#import "WPCaptureProtectedView.h"
#import "WPQuickChatPreferences.h"
#import "WPCommon.h"
@interface WPNonEditingSecureField : UITextField
@end
@implementation WPNonEditingSecureField
- (BOOL)canBecomeFirstResponder{return NO;}
@end
@interface WPCaptureProtectedView ()
@property(nonatomic) UITextField *secureField;
@property(nonatomic) UIView *secureCanvas;
@property(nonatomic) BOOL rerouting;
@property(nonatomic) NSHashTable<UIView *> *managedViews;
@property(nonatomic,readwrite) BOOL protectionAvailable;
@end
@implementation WPCaptureProtectedView
- (instancetype)initWithFrame:(CGRect)frame{
    if(!(self=[super initWithFrame:frame]))return nil;
    self.backgroundColor=UIColor.clearColor;self.opaque=NO;
    self.managedViews=[NSHashTable weakObjectsHashTable];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(changed:) name:WPSettingsDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(changed:) name:UIScreenCapturedDidChangeNotification object:nil];
    return self;
}
- (UIView *)findCanvas:(UIView *)view{
    NSString *name=NSStringFromClass(view.class);
    if([name containsString:@"TextLayoutCanvas"] || [name containsString:@"TextFieldCanvas"])return view;
    for(UIView *child in view.subviews){UIView *found=[self findCanvas:child];if(found)return found;}return nil;
}
- (void)refreshProtection{
    BOOL enabled=WPQuickChatOptionBool(@"hideCapture");
    if(enabled && !self.secureField){
        UITextField *field=[[WPNonEditingSecureField alloc] initWithFrame:self.bounds];
        field.secureTextEntry=YES;field.text=@" ";field.textColor=UIColor.clearColor;field.tintColor=UIColor.clearColor;
        field.backgroundColor=UIColor.clearColor;field.borderStyle=UITextBorderStyleNone;field.font=[UIFont systemFontOfSize:1];
        field.isAccessibilityElement=NO;[field layoutIfNeeded];UIView *canvas=[self findCanvas:field];
        if(canvas){
            NSArray *children=[self.subviews copy];self.rerouting=YES;[super addSubview:field];self.rerouting=NO;
            self.secureField=field;self.secureCanvas=canvas;canvas.backgroundColor=UIColor.clearColor;canvas.userInteractionEnabled=YES;
            for(UIView *child in children){[self.managedViews addObject:child];[canvas addSubview:child];}self.protectionAvailable=YES;
        }
    }else if(!enabled && self.secureField){
        // Preserve product view order and all gesture recognizers when toggling.
        NSArray *children=[self.secureCanvas.subviews copy];self.rerouting=YES;
        for(UIView *child in children)if([self.managedViews containsObject:child])[super addSubview:child];self.rerouting=NO;
        [self.managedViews removeAllObjects];
        [self.secureField removeFromSuperview];self.secureField=nil;self.secureCanvas=nil;self.protectionAvailable=NO;
    }
    BOOL recording=self.window.screen.isCaptured;
    self.layer.opacity=enabled && recording?0:1;
    [self setNeedsLayout];
}
- (void)changed:(NSNotification *)note{[self refreshProtection];}
- (void)didMoveToWindow{[super didMoveToWindow];[self refreshProtection];}
- (void)addSubview:(UIView *)view{if(self.secureCanvas && !self.rerouting){[self.managedViews addObject:view];[self.secureCanvas addSubview:view];}else [super addSubview:view];}
- (void)insertSubview:(UIView *)view belowSubview:(UIView *)sibling{if(self.secureCanvas && sibling.superview==self.secureCanvas){[self.managedViews addObject:view];[self.secureCanvas insertSubview:view belowSubview:sibling];}else [super insertSubview:view belowSubview:sibling];}
- (void)insertSubview:(UIView *)view aboveSubview:(UIView *)sibling{if(self.secureCanvas && sibling.superview==self.secureCanvas){[self.managedViews addObject:view];[self.secureCanvas insertSubview:view aboveSubview:sibling];}else [super insertSubview:view aboveSubview:sibling];}
- (void)layoutSubviews{[super layoutSubviews];self.secureField.frame=self.bounds;[self.secureField layoutIfNeeded];self.secureCanvas.frame=self.bounds;}
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event{
    if(WPQuickChatOptionBool(@"hideCapture") && self.window.screen.isCaptured)return nil;
    UIView *hit=[super hitTest:point withEvent:event];
    if(hit==self.secureCanvas || hit==self.secureField)return nil;return hit;
}
- (void)dealloc{[NSNotificationCenter.defaultCenter removeObserver:self];}
@end
