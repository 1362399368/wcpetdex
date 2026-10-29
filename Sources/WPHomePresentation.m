#import "WPHomePresentation.h"
#import "WPCommon.h"
#import "WPTheme.h"
#import "WPSharedChatAvatar.h"

// WeChat private selectors vary between releases. Verify the object return ABI
// and fail to a neutral placeholder when a service or selector is unavailable.
static id WPHomeObject(id target, NSString *name) {
    if(!target)return nil;
    SEL selector=NSSelectorFromString(name);
    @try {
        if(![target respondsToSelector:selector])return nil;
        NSMethodSignature *signature=[target methodSignatureForSelector:selector];
        const char *type=signature.methodReturnType;
        while(type && *type && strchr("rnNoORV",*type))type++;
        if(!signature || signature.numberOfArguments!=2 || !type || *type!='@')return nil;
        NSInvocation *call=[NSInvocation invocationWithMethodSignature:signature];
        call.target=target;call.selector=selector;[call invoke];
        __unsafe_unretained id result=nil;[call getReturnValue:&result];return result;
    } @catch(__unused NSException *exception) { return nil; }
}
static NSString *WPHomeContactString(id contact,NSArray<NSString *> *keys){
    for(NSString *key in keys){
        id value=WPHomeObject(contact,key);
        if(![value isKindOfClass:NSString.class]){
            @try {value=[contact valueForKey:key];} @catch(__unused NSException *exception) {value=nil;}
        }
        if([value isKindOfClass:NSString.class]){
            NSString *trim=[value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if(trim.length && trim.length<=256)return trim;
        }
    }
    return @"";
}

@interface WPHomeHeader : UIView
@property(nonatomic,strong) UIImageView *avatar;
@property(nonatomic,strong) UILabel *nickname;
@property(nonatomic,strong) WPSharedChatAvatarRequest *avatarRequest;
@property(nonatomic,copy) NSString *username;
@property(nonatomic) BOOL loading;
- (void)addVisibilityActionHidden:(BOOL)hidden handler:(void (^)(BOOL))handler;
@end
@implementation WPHomeHeader
- (instancetype)init {
    if((self=[super initWithFrame:CGRectZero])){
        self.accessibilityIdentifier=@"WPHomeAccountHeader";
        _avatar=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"person.crop.circle.fill"]];
        _avatar.accessibilityIdentifier=@"WPHomeAccountAvatar";_avatar.contentMode=UIViewContentModeScaleAspectFill;
        _avatar.tintColor=UIColor.tertiaryLabelColor;_avatar.backgroundColor=UIColor.secondarySystemGroupedBackgroundColor;
        _avatar.layer.cornerRadius=49;_avatar.clipsToBounds=YES;_avatar.translatesAutoresizingMaskIntoConstraints=NO;
        _nickname=WPThemeLabel(@"微信用户",16,UIFontWeightMedium,WPThemePrimaryText());
        _nickname.accessibilityIdentifier=@"WPHomeAccountNickname";_nickname.textAlignment=NSTextAlignmentCenter;_nickname.numberOfLines=1;
        UILabel *brand=WPThemeLabel(@"Zhour",27,UIFontWeightBold,UIColor.systemRedColor);
        NSArray<UIColor *> *colors=@[UIColor.systemPinkColor,UIColor.systemOrangeColor,UIColor.systemTealColor,UIColor.systemBlueColor,UIColor.systemPurpleColor];
        NSMutableAttributedString *colorful=[[NSMutableAttributedString alloc] initWithString:@"Zhour" attributes:@{NSFontAttributeName:[UIFont systemFontOfSize:27 weight:UIFontWeightBold]}];
        for(NSUInteger i=0;i<colors.count;i++)[colorful addAttribute:NSForegroundColorAttributeName value:colors[i] range:NSMakeRange(i,1)];
        brand.attributedText=colorful;
        brand.accessibilityIdentifier=@"WPHomeBrand";brand.textAlignment=NSTextAlignmentCenter;
        UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:@[_avatar,_nickname,brand]];
        stack.axis=UILayoutConstraintAxisVertical;stack.alignment=UIStackViewAlignmentCenter;stack.spacing=11;stack.translatesAutoresizingMaskIntoConstraints=NO;
        [self addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:8],
            [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],
            [stack.topAnchor constraintEqualToAnchor:self.topAnchor constant:14],
            [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-8],
            [_avatar.widthAnchor constraintEqualToConstant:98],[_avatar.heightAnchor constraintEqualToConstant:98],
            [_nickname.widthAnchor constraintLessThanOrEqualToAnchor:stack.widthAnchor],
            [brand.widthAnchor constraintLessThanOrEqualToAnchor:stack.widthAnchor]]];
    }return self;
}
- (void)addVisibilityActionHidden:(BOOL)hidden handler:(void (^)(BOOL))handler {
    UIControl *button=[UIControl new];button.translatesAutoresizingMaskIntoConstraints=NO;
    button.accessibilityIdentifier=@"WPHidePetButton";button.accessibilityLabel=hidden?@"显示桌宠":@"隐藏桌宠";
    button.accessibilityHint=hidden?@"恢复显示桌宠和浮动提示":@"隐藏桌宠和浮动提示";button.accessibilityTraits=UIAccessibilityTraitButton;
    UIView *circle=[UIView new];circle.translatesAutoresizingMaskIntoConstraints=NO;circle.userInteractionEnabled=NO;
    circle.backgroundColor=[UIColor.systemPurpleColor colorWithAlphaComponent:.14];circle.layer.cornerRadius=20;
    circle.layer.borderWidth=.7;circle.layer.borderColor=[UIColor.systemPurpleColor colorWithAlphaComponent:.2].CGColor;
    UIImageView *icon=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:hidden?@"eye.fill":@"eye.slash.fill"]];
    icon.translatesAutoresizingMaskIntoConstraints=NO;icon.contentMode=UIViewContentModeScaleAspectFit;icon.tintColor=UIColor.systemPurpleColor;
    UILabel *label=WPThemeLabel(hidden?@"显示桌宠":@"隐藏桌宠",10,UIFontWeightMedium,WPThemePrimaryText());
    label.translatesAutoresizingMaskIntoConstraints=NO;label.textAlignment=NSTextAlignmentCenter;label.adjustsFontSizeToFitWidth=YES;
    [circle addSubview:icon];[button addSubview:circle];[button addSubview:label];[self addSubview:button];
    NSLayoutConstraint *beside=[button.leadingAnchor constraintEqualToAnchor:self.avatar.trailingAnchor constant:10];beside.priority=UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[beside,[button.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-4],
        [button.centerYAnchor constraintEqualToAnchor:self.avatar.centerYAnchor],
        [button.widthAnchor constraintEqualToConstant:60],[button.heightAnchor constraintEqualToConstant:62],
        [circle.widthAnchor constraintEqualToConstant:40],[circle.heightAnchor constraintEqualToConstant:40],
        [circle.topAnchor constraintEqualToAnchor:button.topAnchor],[circle.centerXAnchor constraintEqualToAnchor:button.centerXAnchor],
        [icon.centerXAnchor constraintEqualToAnchor:circle.centerXAnchor],[icon.centerYAnchor constraintEqualToAnchor:circle.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:20],[icon.heightAnchor constraintEqualToConstant:20],
        [label.topAnchor constraintEqualToAnchor:circle.bottomAnchor constant:4],[label.leadingAnchor constraintEqualToAnchor:button.leadingAnchor],
        [label.trailingAnchor constraintEqualToAnchor:button.trailingAnchor]]];
    if(handler)[button addAction:[UIAction actionWithHandler:^(__unused UIAction *action){handler(!hidden);}] forControlEvents:UIControlEventTouchUpInside];
}
- (void)didMoveToWindow {
    [super didMoveToWindow];
    if(!self.window){[self.avatarRequest cancel];self.avatarRequest=nil;self.loading=NO;return;}
    if(self.loading)return;
    id manager=WPWeChatService(@"CContactMgr");
    id contact=WPHomeObject(manager,@"getSelfContact");
    NSString *name=WPHomeContactString(contact,@[@"m_nsNickName",@"nickname",@"nickName",@"getDisplayName"]);
    NSString *username=WPHomeContactString(contact,@[@"m_nsUsrName",@"m_nsUserName",@"username",@"userName",@"getContactUserName"]);
    self.nickname.text=name.length?name:@"微信用户";
    if(![self.username isEqualToString:username]) {
        self.avatar.image=[UIImage systemImageNamed:@"person.crop.circle.fill"];
    }
    self.username=username;
    if(!username.length)return;
    // A memory-pressure cooldown may suppress new requests even when a
    // decoded local image is already cached. Reuse that image immediately.
    UIImage *cached=WPCachedSharedChatAvatar(username);
    if(cached.CGImage){self.avatar.image=cached;return;}
    self.loading=YES;__weak typeof(self) weakSelf=self;
    self.avatarRequest=WPRequestSharedChatAvatar(username,^(UIImage *image){
        typeof(self) self=weakSelf;if(!self || ![self.username isEqualToString:username])return;
        self.loading=NO;self.avatarRequest=nil;if(image.CGImage)self.avatar.image=image;
    });
}
- (void)dealloc{[self.avatarRequest cancel];}
@end

UIView *WPBuildHomeHeader(void){return [WPHomeHeader new];}
UIView *WPBuildHomeHeaderWithVisibility(BOOL hidden,void (^handler)(BOOL)){
    WPHomeHeader *header=[WPHomeHeader new];[header addVisibilityActionHidden:hidden handler:handler];return header;
}
UIControl *WPBuildHomeFeature(NSString *title,UIImage *image,UIColor *tint,dispatch_block_t handler){
    UIControl *control=[UIControl new];control.isAccessibilityElement=YES;control.accessibilityLabel=title;control.accessibilityTraits=UIAccessibilityTraitButton;
    UIView *circle=[UIView new];circle.userInteractionEnabled=NO;circle.backgroundColor=[tint colorWithAlphaComponent:.15];circle.layer.cornerRadius=44;
    circle.accessibilityIdentifier=@"WPHomeFeatureCircle";
    circle.layer.borderColor=[tint colorWithAlphaComponent:.18].CGColor;circle.layer.borderWidth=.7;circle.translatesAutoresizingMaskIntoConstraints=NO;
    UIImageView *icon=[[UIImageView alloc] initWithImage:image];icon.userInteractionEnabled=NO;icon.tintColor=tint;icon.contentMode=UIViewContentModeScaleAspectFit;icon.translatesAutoresizingMaskIntoConstraints=NO;
    [circle addSubview:icon];[control addSubview:circle];
    UILabel *label=WPThemeLabel(title,15,UIFontWeightSemibold,WPThemePrimaryText());label.userInteractionEnabled=NO;label.textAlignment=NSTextAlignmentCenter;
    label.numberOfLines=2;label.lineBreakMode=NSLineBreakByTruncatingTail;label.translatesAutoresizingMaskIntoConstraints=NO;[control addSubview:label];
    [NSLayoutConstraint activateConstraints:@[[control.heightAnchor constraintGreaterThanOrEqualToConstant:124],
        [circle.widthAnchor constraintEqualToConstant:88],[circle.heightAnchor constraintEqualToConstant:88],
        [circle.topAnchor constraintEqualToAnchor:control.topAnchor constant:4],[circle.centerXAnchor constraintEqualToAnchor:control.centerXAnchor],
        [icon.widthAnchor constraintEqualToConstant:40],[icon.heightAnchor constraintEqualToConstant:40],
        [icon.centerXAnchor constraintEqualToAnchor:circle.centerXAnchor],[icon.centerYAnchor constraintEqualToAnchor:circle.centerYAnchor],
        [label.topAnchor constraintEqualToAnchor:circle.bottomAnchor constant:6],[label.leadingAnchor constraintEqualToAnchor:control.leadingAnchor],
        [label.trailingAnchor constraintEqualToAnchor:control.trailingAnchor],[label.bottomAnchor constraintLessThanOrEqualToAnchor:control.bottomAnchor constant:-5]]];
    if(handler)[control addAction:[UIAction actionWithHandler:^(__unused UIAction *action){handler();}] forControlEvents:UIControlEventTouchUpInside];
    return control;
}
