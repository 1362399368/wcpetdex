#import "WPUnreadAvatarControl.h"
#import "WPQuickChat.h"
#import "WPChatAvatarDownload.h"
#import "WPSharedChatAvatar.h"

static UIImage *WPUnreadSmallAvatar(UIImage *image,NSUInteger maximumPixels) {
    CGImageRef source=image.CGImage;
    if(!source)return nil;
    size_t width=CGImageGetWidth(source),height=CGImageGetHeight(source);
    if(!width || !height)return nil;
    if(MAX(width,height)<=maximumPixels)return image;
    CGFloat ratio=(CGFloat)maximumPixels/MAX(width,height);
    CGSize size=CGSizeMake(MAX(1,floor(width*ratio)),MAX(1,floor(height*ratio)));
    UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat defaultFormat];format.scale=1;
    return [[[UIGraphicsImageRenderer alloc] initWithSize:size format:format] imageWithActions:^(__unused UIGraphicsImageRendererContext *context){
        [image drawInRect:(CGRect){CGPointZero,size}];
    }];
}

@interface WPUnreadAvatarControl ()
@property(nonatomic,copy,readwrite) NSString *username;
@property(nonatomic,copy) NSString *avatarUsername;
@property(nonatomic,copy) NSString *contactTitle;
@property(nonatomic) UIImageView *avatarView;
@property(nonatomic) UILabel *placeholderLabel;
@property(nonatomic) WPQCAvatarDownload *download;
@property(nonatomic) WPSharedChatAvatarRequest *preparation;
@property(nonatomic) NSTimer *retryTimer;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) NSUInteger localAttempts;
@property(nonatomic) NSUInteger remoteAttempts;
@property(nonatomic) CFTimeInterval lastLocalAttempt;
@property(nonatomic) CFTimeInterval lastRemoteAttempt;
@property(nonatomic) CFTimeInterval memoryCooldownUntil;
@property(nonatomic) BOOL loadingActive;
@property(nonatomic) BOOL backgroundSuspended;
@property(nonatomic) BOOL barrageAvatarMode;
- (void)loadAvatar;
- (void)showConversation:(NSString *)username avatarUsername:(NSString *)avatarUsername title:(NSString *)title image:(nullable UIImage *)image;
@end

@implementation WPUnreadAvatarControl
- (instancetype)initWithFrame:(CGRect)frame {
    if(!(self=[super initWithFrame:frame]))return nil;
    self.backgroundColor=UIColor.clearColor;
    self.isAccessibilityElement=YES;self.accessibilityTraits=UIAccessibilityTraitButton;
    self.accessibilityIdentifier=@"WPLatestUnreadAvatar";
    self.accessibilityLabel=@"打开最新未读聊天";
    self.avatarView=[UIImageView new];self.avatarView.contentMode=UIViewContentModeScaleAspectFill;
    self.avatarView.clipsToBounds=YES;self.avatarView.layer.cornerRadius=9;
    self.avatarView.backgroundColor=UIColor.secondarySystemBackgroundColor;
    self.avatarView.layer.borderWidth=1.5;self.avatarView.layer.borderColor=UIColor.systemBackgroundColor.CGColor;
    self.avatarView.userInteractionEnabled=NO;[self addSubview:self.avatarView];
    self.placeholderLabel=[UILabel new];self.placeholderLabel.textAlignment=NSTextAlignmentCenter;
    self.placeholderLabel.font=[UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    self.placeholderLabel.textColor=UIColor.labelColor;self.placeholderLabel.userInteractionEnabled=NO;
    [self.avatarView addSubview:self.placeholderLabel];
    NSNotificationCenter *center=NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(background:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [center addObserver:self selector:@selector(memoryWarning:) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat side=MIN(36,MIN(self.bounds.size.width,self.bounds.size.height));
    self.avatarView.frame=CGRectMake((self.bounds.size.width-side)/2,(self.bounds.size.height-side)/2,side,side);
    self.placeholderLabel.frame=self.avatarView.bounds;
}
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    CGFloat dx=MAX(0,(44-self.bounds.size.width)/2),dy=MAX(0,(44-self.bounds.size.height)/2);
    return CGRectContainsPoint(CGRectInset(self.bounds,-dx,-dy),point);
}
- (BOOL)canLoadAvatar {
    return self.loadingActive && !self.backgroundSuspended && !self.hidden && self.window && self.username.length;
}
- (void)cancelWork {
    self.generation++;
    [self.retryTimer invalidate];self.retryTimer=nil;
    [self.download cancel];self.download=nil;
    [self.preparation cancel];self.preparation=nil;
}
- (void)releaseAvatar {
    self.avatarView.image=nil;self.placeholderLabel.hidden=NO;
}
- (void)showUsername:(NSString *)username title:(NSString *)title {
    self.barrageAvatarMode=NO;
    self.avatarView.layer.cornerRadius=9;
    [self showConversation:username avatarUsername:username title:title image:nil];
}
- (void)showConversationUsername:(NSString *)conversation senderUsername:(NSString *)sender image:(UIImage *)image {
    self.barrageAvatarMode=YES;
    self.avatarView.layer.cornerRadius=18;
    [self showConversation:conversation avatarUsername:sender.length?sender:conversation title:@"聊天" image:image];
}
- (void)showConversation:(NSString *)username avatarUsername:(NSString *)avatarUsername title:(NSString *)title image:(UIImage *)image {
    if(![username isKindOfClass:NSString.class] || !username.length || username.length>256){[self clearAvatar];return;}
    if(![avatarUsername isKindOfClass:NSString.class] || !avatarUsername.length || avatarUsername.length>256)avatarUsername=username;
    NSString *name=[title isKindOfClass:NSString.class] && title.length?title:@"聊天";
    if(![self.username isEqualToString:username] || ![self.avatarUsername isEqualToString:avatarUsername]){
        if(self.tracking)[self cancelTrackingWithEvent:nil];
        [self cancelWork];[self releaseAvatar];
        self.username=username;self.avatarUsername=avatarUsername;self.localAttempts=self.remoteAttempts=0;
        self.lastLocalAttempt=self.lastRemoteAttempt=0;
    }
    self.contactTitle=name;self.accessibilityValue=name;
    NSRange first=[name rangeOfComposedCharacterSequenceAtIndex:0];
    self.placeholderLabel.text=[[name substringWithRange:first] uppercaseString];
    if(image.CGImage)[self acceptAvatar:image];else [self loadAvatar];
}
- (void)clearAvatar {
    if(self.tracking)[self cancelTrackingWithEvent:nil];
    [self cancelWork];[self releaseAvatar];
    self.username=nil;self.avatarUsername=nil;self.contactTitle=nil;self.accessibilityValue=nil;self.placeholderLabel.text=nil;
    self.localAttempts=self.remoteAttempts=0;
    self.lastLocalAttempt=self.lastRemoteAttempt=0;
}
- (void)setActive:(BOOL)active {
    BOOL changed=self.loadingActive!=active;
    self.loadingActive=active;
    if(!active){[self cancelWork];[self releaseAvatar];return;}
    BOOL resumed=self.backgroundSuspended;self.backgroundSuspended=NO;
    if(changed || resumed){self.localAttempts=self.remoteAttempts=0;self.lastLocalAttempt=self.lastRemoteAttempt=0;}
    [self loadAvatar];
}
- (void)setHidden:(BOOL)hidden {
    BOOL changed=self.hidden!=hidden;[super setHidden:hidden];
    if(hidden){[self cancelWork];[self releaseAvatar];}
    else if(changed){self.localAttempts=self.remoteAttempts=0;self.lastLocalAttempt=self.lastRemoteAttempt=0;[self loadAvatar];}
}
- (void)didMoveToWindow {
    [super didMoveToWindow];
    if(!self.window){[self cancelWork];[self releaseAvatar];}
    else {self.localAttempts=self.remoteAttempts=0;self.lastLocalAttempt=self.lastRemoteAttempt=0;[self loadAvatar];}
}
- (void)background:(NSNotification *)note {
    self.backgroundSuspended=YES;[self cancelWork];[self releaseAvatar];
}
- (void)memoryWarning:(NSNotification *)note {
    [self cancelWork];self.localAttempts=self.remoteAttempts=0;self.lastLocalAttempt=self.lastRemoteAttempt=0;
    self.memoryCooldownUntil=CACurrentMediaTime()+8;
    // A displayed 160-pixel avatar is small. Retain it to avoid a visible
    // flash and, more importantly, a pointless immediate network/decode pass.
    if(![self canLoadAvatar])[self releaseAvatar];
    else if(!self.avatarView.image)[self scheduleRetry];
}
- (void)acceptAvatar:(UIImage *)image {
    UIImage *small=WPUnreadSmallAvatar(image,160);
    if(!small)return;
    [self cancelWork];self.avatarView.image=small;self.placeholderLabel.hidden=YES;
}
- (void)scheduleRetry {
    if(self.retryTimer || ![self canLoadAvatar] || self.avatarView.image)return;
    BOOL localPending=self.localAttempts<8;
    if(!localPending)return;
    NSUInteger generation=self.generation;__weak typeof(self) weakSelf=self;
    NSTimeInterval delay=MAX(1.5,self.memoryCooldownUntil-CACurrentMediaTime());
    self.retryTimer=[NSTimer timerWithTimeInterval:delay repeats:NO block:^(__unused NSTimer *timer){
        WPUnreadAvatarControl *strongSelf=weakSelf;
        if(!strongSelf || strongSelf.generation!=generation)return;
        strongSelf.retryTimer=nil;[strongSelf loadAvatar];
    }];
    self.retryTimer.tolerance=.3;
    [NSRunLoop.mainRunLoop addTimer:self.retryTimer forMode:NSRunLoopCommonModes];
}
- (void)loadAvatar {
    if(![self canLoadAvatar] || self.avatarView.image || self.preparation)return;
    CFTimeInterval now=CACurrentMediaTime();
    if(now<self.memoryCooldownUntil){[self scheduleRetry];return;}
    UIImage *cached=WPCachedSharedChatAvatar(self.avatarUsername);
    if(cached){[self acceptAvatar:cached];return;}
    if(self.localAttempts>=8)return;
    if(self.localAttempts && now-self.lastLocalAttempt<1.2){[self scheduleRetry];return;}
    self.localAttempts++;self.lastLocalAttempt=now;
    NSUInteger generation=self.generation;NSString *username=[self.avatarUsername copy];__weak typeof(self) weakSelf=self;
    self.preparation=WPRequestSharedChatAvatar(username,^(UIImage *image){
        WPUnreadAvatarControl *self=weakSelf;if(!self || generation!=self.generation || ![self.avatarUsername isEqualToString:username])return;
        self.preparation=nil;if(![self canLoadAvatar])return;
        if(image.CGImage)[self acceptAvatar:image];else [self scheduleRetry];
    });
}
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    self.avatarView.layer.borderColor=[UIColor.systemBackgroundColor resolvedColorWithTraitCollection:self.traitCollection].CGColor;
}
- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [self.retryTimer invalidate];[self.download cancel];[self.preparation cancel];
}
@end
