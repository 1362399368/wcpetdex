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
UIControl *WPBuildHomeFeature(NSString *title,UIImage *image,UIColor *tint,dispatch_block_t handler){
    UIControl *control=[UIControl new];control.isAccessibilityElement=YES;control.accessibilityLabel=title;control.accessibilityTraits=UIAccessibilityTraitButton;
    UIView *circle=[UIView new];circle.backgroundColor=[tint colorWithAlphaComponent:.15];circle.layer.cornerRadius=30;
    circle.layer.borderColor=[tint colorWithAlphaComponent:.18].CGColor;circle.layer.borderWidth=.7;circle.translatesAutoresizingMaskIntoConstraints=NO;
    UIImageView *icon=[[UIImageView alloc] initWithImage:image];icon.tintColor=tint;icon.contentMode=UIViewContentModeScaleAspectFit;icon.translatesAutoresizingMaskIntoConstraints=NO;
    [circle addSubview:icon];[control addSubview:circle];
    UILabel *label=WPThemeLabel(title,13,UIFontWeightSemibold,WPThemePrimaryText());label.textAlignment=NSTextAlignmentCenter;
    label.numberOfLines=2;label.lineBreakMode=NSLineBreakByTruncatingTail;label.translatesAutoresizingMaskIntoConstraints=NO;[control addSubview:label];
    [NSLayoutConstraint activateConstraints:@[[control.heightAnchor constraintGreaterThanOrEqualToConstant:104],
        [circle.widthAnchor constraintEqualToConstant:60],[circle.heightAnchor constraintEqualToConstant:60],
        [circle.topAnchor constraintEqualToAnchor:control.topAnchor constant:8],[circle.centerXAnchor constraintEqualToAnchor:control.centerXAnchor],
        [icon.widthAnchor constraintEqualToConstant:29],[icon.heightAnchor constraintEqualToConstant:29],
        [icon.centerXAnchor constraintEqualToAnchor:circle.centerXAnchor],[icon.centerYAnchor constraintEqualToAnchor:circle.centerYAnchor],
        [label.topAnchor constraintEqualToAnchor:circle.bottomAnchor constant:9],[label.leadingAnchor constraintEqualToAnchor:control.leadingAnchor],
        [label.trailingAnchor constraintEqualToAnchor:control.trailingAnchor],[label.bottomAnchor constraintLessThanOrEqualToAnchor:control.bottomAnchor constant:-5]]];
    if(handler)[control addAction:[UIAction actionWithHandler:^(__unused UIAction *action){handler();}] forControlEvents:UIControlEventTouchUpInside];
    return control;
}
