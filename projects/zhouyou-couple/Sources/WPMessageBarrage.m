#import "WPMessageBarrage.h"
#import "WPBarragePreferences.h"
#import "WPQuickChat.h"
#import "WPChatAvatarDownload.h"
#import "WPComfortPreferences.h"
#import "WPMessageBarrageSource.h"
#import "WPChatPresentationState.h"
#import "WPSharedChatAvatar.h"
#import <QuartzCore/QuartzCore.h>

static const NSUInteger WPBarragePoolSize=6;
static const NSUInteger WPBarrageQueueLimit=12;
static const CGFloat WPBarrageHeight=46;
static const NSUInteger WPBarrageAvatarBytes=1024*1024;
static const CFTimeInterval WPBarrageQueueLifetime=12;

@implementation WPBarrageMessage
- (instancetype)init {if((self=[super init])){_conversationUsername=@"";_senderUsername=@"";_text=@"";_identifier=@"";_createdAt=NSDate.date;}return self;}
@end

static BOOL WPBarrageRectValid(CGRect rect) {
    return !CGRectIsNull(rect)&&!CGRectIsInfinite(rect)&&isfinite(rect.origin.x)&&isfinite(rect.origin.y)&&isfinite(rect.size.width)&&isfinite(rect.size.height)&&rect.size.width>0&&rect.size.height>0;
}
static NSString *WPBarrageString(id value, NSUInteger maxLength) {
    if(![value isKindOfClass:NSString.class] || ![value length])return @"";
    NSString *text=value;
    return text.length<=maxLength ? [text copy] : [text substringToIndex:[text rangeOfComposedCharacterSequencesForRange:NSMakeRange(0,maxLength)].length];
}
static NSString *WPBarrageBody(id value) {
    if(![value isKindOfClass:NSString.class] || ![value length])return @"";
    // Collapse newlines so a text message never creates a second track. Keep
    // whole grapheme clusters (including emoji); the source has the same cap.
    NSString *text=[value stringByReplacingOccurrencesOfString:@"\r" withString:@" "];
    text=[text stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    __block NSUInteger count=0,last=0;__block BOOL truncated=NO;
    [text enumerateSubstringsInRange:NSMakeRange(0,text.length) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(__unused NSString *part, NSRange range, __unused NSRange enclosing, BOOL *stop){
        if(count++==80){truncated=YES;*stop=YES;return;}last=NSMaxRange(range);
    }];
    return truncated ? [[text substringToIndex:last] stringByAppendingString:@"…"] : text;
}
static NSUInteger WPBarrageImageCost(UIImage *image) {
    CGImageRef cg=image.CGImage;return cg?CGImageGetBytesPerRow(cg)*CGImageGetHeight(cg):0;
}
static UIImage *WPBarrageSmallImage(UIImage *image) {
    // Called only by the serial utility queue. Drawing also forces decode off
    // the animation/main thread, and the result cannot retain a large source.
    CGImageRef cg=image.CGImage;if(!cg)return nil;
    size_t width=CGImageGetWidth(cg),height=CGImageGetHeight(cg);
    if(!width||!height||width>8192||height>8192||width*height>16*1024*1024)return nil;
    CGFloat ratio=MIN(1,96.0/MAX(width,height));
    CGSize size=CGSizeMake(MAX(1,floor(width*ratio)),MAX(1,floor(height*ratio)));
    UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat defaultFormat];format.scale=1;format.opaque=NO;format.preferredRange=UIGraphicsImageRendererFormatRangeStandard;
    return [[[UIGraphicsImageRenderer alloc] initWithSize:size format:format] imageWithActions:^(__unused UIGraphicsImageRendererContext *context){[image drawInRect:(CGRect){CGPointZero,size}];}];
}
#if defined(WP_PREVIEW_HOST)
UIImage *WPBarragePreviewSmallImage(UIImage *image) {return WPBarrageSmallImage(image);}
#endif

@interface WPBarrageRecord : NSObject
@property(nonatomic,copy) NSString *conversation;
@property(nonatomic,copy) NSString *sender;
@property(nonatomic,copy) NSString *body;
@property(nonatomic,copy) NSString *identifier;
@property(nonatomic) NSUInteger sequence;
@property(nonatomic,strong) NSDate *createdAt;
@property(nonatomic) CFTimeInterval arrivedAt;
@property(nonatomic) CFTimeInterval expiresAt;
@property(nonatomic) BOOL localPreview;
@property(nonatomic) BOOL eligibilityConfirmed;
@property(nonatomic,copy) NSString *displayName;
@end
@implementation WPBarrageRecord @end

typedef NS_ENUM(NSUInteger, WPBarrageAvatarStatus) {
    WPBarrageAvatarWaiting, WPBarrageAvatarInFlight,
    WPBarrageAvatarReady, WPBarrageAvatarCooling
};
@interface WPBarrageAvatarState : NSObject
@property(nonatomic) WPBarrageAvatarStatus status;
@property(nonatomic) NSUInteger failures;
@property(nonatomic) NSUInteger lastAttemptSequence;
@property(nonatomic) CFTimeInterval nextAttempt;
@end
@implementation WPBarrageAvatarState @end

@interface WPBarrageDecodeJob : NSObject
@property(atomic,strong) UIImage *image;
@property(atomic) BOOL cancelled;
@property(nonatomic,copy) NSString *username;
@property(nonatomic) NSUInteger generation;
@end
@implementation WPBarrageDecodeJob @end

@interface WPBarrageAnimationEnd : NSObject <CAAnimationDelegate>
@property(nonatomic,copy) void (^completion)(BOOL finished);
@end
@implementation WPBarrageAnimationEnd
- (void)animationDidStop:(CAAnimation *)animation finished:(BOOL)finished {if(self.completion)self.completion(finished);}
@end

// Only our own capsule layers are observed. UIKit can remove an animation
// without calling its CAAnimation delegate; observing the actual removal is
// necessary to restore that capsule without a per-frame timer or global hook.
@interface WPBarrageMotionLayer : CALayer
@property(nonatomic,copy) void (^onMotionRemoved)(void);
@end
@implementation WPBarrageMotionLayer
- (void)removeAnimationForKey:(NSString *)key {
    BOOL removed=[key isEqualToString:@"WPBarrageMove"]&&[self animationForKey:key]!=nil;
    [super removeAnimationForKey:key];if(removed&&self.onMotionRemoved)self.onMotionRemoved();
}
- (void)removeAllAnimations {
    BOOL removed=[self animationForKey:@"WPBarrageMove"]!=nil;
    [super removeAllAnimations];if(removed&&self.onMotionRemoved)self.onMotionRemoved();
}
@end

@interface WPBarrageMovingControl : UIControl
@property(nonatomic,strong) WPBarrageRecord *record;
@property(nonatomic,strong) WPBarrageAnimationEnd *animationEnd;
@property(nonatomic) NSUInteger motionSerial;
@property(nonatomic) CFTimeInterval motionStart;
@property(nonatomic) CFTimeInterval motionDuration;
@property(nonatomic) CGPoint motionFrom;
@property(nonatomic) CGPoint motionTo;
@property(nonatomic) CGFloat pixelsPerSecond;
@property(nonatomic) CFTimeInterval staticDeadline;
@property(nonatomic) NSUInteger tapSequence;
@property(nonatomic) NSUInteger trackingSequence;
- (CGRect)visualFrame;
@end
@implementation WPBarrageMovingControl
+ (Class)layerClass {return WPBarrageMotionLayer.class;}
- (CGRect)visualFrame {
    CALayer *presentation=self.layer.presentationLayer;
    if(presentation)return presentation.frame;
    // Immediately after addAnimation there may be no presentation tree yet.
    // Calculate only when hit-tested, never with a per-frame timer.
    if(self.motionDuration>0) {
        CGFloat progress=MIN(1,MAX(0,(CACurrentMediaTime()-self.motionStart)/self.motionDuration));
        CGPoint point=CGPointMake(self.motionFrom.x+(self.motionTo.x-self.motionFrom.x)*progress,self.motionFrom.y+(self.motionTo.y-self.motionFrom.y)*progress);
        return CGRectMake(point.x-self.bounds.size.width/2,point.y-self.bounds.size.height/2,self.bounds.size.width,self.bounds.size.height);
    }
    return self.frame;
}
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if(self.hidden||!self.record||self.alpha<.01||!self.superview)return NO;
    CGPoint parentPoint=[self convertPoint:point toView:self.superview];
    CGRect visible=CGRectIntersection([self visualFrame],self.superview.bounds);
    return WPBarrageRectValid(visible)&&CGRectContainsPoint(visible,parentPoint);
}
- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {self.trackingSequence=self.record.sequence;return [super beginTrackingWithTouch:touch withEvent:event];}
- (BOOL)accessibilityActivate {self.trackingSequence=self.record.sequence;[self sendActionsForControlEvents:UIControlEventTouchUpInside];return YES;}
@end

@interface WPBarrageBubble : WPBarrageMovingControl
@property(nonatomic,strong) UIImageView *avatarView;
@property(nonatomic,strong) UILabel *bodyLabel;
@property(nonatomic,strong) UILabel *nameLabel;
@property(nonatomic,strong) UIImage *actualAvatar;
@property(nonatomic) NSInteger lane;
- (void)layoutContents;
@end
@implementation WPBarrageBubble
- (instancetype)initWithFrame:(CGRect)frame {
    if(!(self=[super initWithFrame:frame]))return nil;
    self.hidden=YES;self.clipsToBounds=YES;self.layer.cornerRadius=23;self.layer.borderWidth=.5;
    self.avatarView=[[UIImageView alloc] initWithFrame:CGRectMake(6,6,34,34)];
    self.avatarView.clipsToBounds=YES;self.avatarView.layer.cornerRadius=17;self.avatarView.contentMode=UIViewContentModeScaleAspectFill;
    self.avatarView.backgroundColor=UIColor.secondarySystemFillColor;self.avatarView.tintColor=UIColor.secondaryLabelColor;
    self.bodyLabel=[UILabel new];self.bodyLabel.font=[UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    self.bodyLabel.textColor=UIColor.labelColor;self.bodyLabel.numberOfLines=1;self.bodyLabel.lineBreakMode=NSLineBreakByClipping;
    self.bodyLabel.contentScaleFactor=MIN(2,UIScreen.mainScreen.scale);
    self.nameLabel=[UILabel new];self.nameLabel.font=[UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];self.nameLabel.textColor=UIColor.secondaryLabelColor;self.nameLabel.lineBreakMode=NSLineBreakByTruncatingTail;
    [self addSubview:self.avatarView];[self addSubview:self.bodyLabel];[self addSubview:self.nameLabel];
    self.isAccessibilityElement=YES;self.accessibilityTraits=UIAccessibilityTraitButton;self.accessibilityHint=@"打开对应聊天";
    return self;
}
- (void)layoutContents {
    self.avatarView.frame=CGRectMake(6,6,34,34);
    BOOL named=self.nameLabel.text.length>0;self.nameLabel.hidden=!named;
    BOOL hasBody=self.bodyLabel.text.length>0;
    self.nameLabel.frame=CGRectMake(48,hasBody?4:0,MAX(0,self.bounds.size.width-61),hasBody?15:46);
    self.bodyLabel.frame=CGRectMake(48,named?18:0,MAX(0,self.bounds.size.width-61),named?24:46);
    self.bodyLabel.hidden=!self.bodyLabel.text.length;
}
@end

@interface WPBarrageFlight : WPBarrageMovingControl
@property(nonatomic,strong) UIImageView *avatarView;
@property(nonatomic,strong) UIImage *actualAvatar;
@end
@implementation WPBarrageFlight
- (instancetype)initWithFrame:(CGRect)frame {
    if(!(self=[super initWithFrame:frame]))return nil;
    self.hidden=YES;self.bounds=CGRectMake(0,0,34,34);self.layer.cornerRadius=17;self.clipsToBounds=YES;
    self.avatarView=[[UIImageView alloc] initWithFrame:self.bounds];self.avatarView.contentMode=UIViewContentModeScaleAspectFill;
    self.avatarView.backgroundColor=UIColor.secondarySystemFillColor;self.avatarView.tintColor=UIColor.secondaryLabelColor;
    [self addSubview:self.avatarView];self.isAccessibilityElement=YES;self.accessibilityTraits=UIAccessibilityTraitButton;
    self.accessibilityLabel=@"头像";self.accessibilityHint=@"打开对应聊天";
    return self;
}
@end

@interface WPBarrageSurface : UIView @end
@implementation WPBarrageSurface
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if(self.hidden||self.alpha<.01||!self.userInteractionEnabled||!CGRectContainsPoint(self.bounds,point))return nil;
    for(UIView *child in self.subviews.reverseObjectEnumerator) {
        if(![child isKindOfClass:WPBarrageMovingControl.class])continue;
        WPBarrageMovingControl *control=(id)child;
        if([control pointInside:[self convertPoint:point toView:control] withEvent:event])return control;
    }
    return nil;
}
@end

@interface WPMessageBarrageController () <UIGestureRecognizerDelegate>
@property(nonatomic,weak) UIView *hostView;
@property(nonatomic,readwrite,strong) UIView *view;
@property(nonatomic,strong) NSArray<WPBarrageBubble *> *bubbles;
@property(nonatomic,strong) WPBarrageFlight *flight;
@property(nonatomic,strong) NSMutableArray<WPBarrageRecord *> *pending;
@property(nonatomic,strong) NSMutableArray<WPBarrageRecord *> *completedRecords;
@property(nonatomic) CFTimeInterval avatarCooldownUntil;
@property(nonatomic,strong) NSMutableOrderedSet<NSString *> *recentIdentifiers;
@property(nonatomic,strong) NSCache<NSString *,UIImage *> *avatars;
@property(nonatomic,strong) NSMutableOrderedSet<NSString *> *avatarCacheKeys;
@property(nonatomic,strong) NSMutableDictionary<NSString *,NSNumber *> *avatarCacheCosts;
@property(nonatomic) NSUInteger avatarCacheCost;
@property(nonatomic,strong) NSMutableSet<NSString *> *avatarLoads;
@property(nonatomic,strong) NSMutableOrderedSet<NSString *> *avatarRequests;
@property(nonatomic,strong) NSMutableDictionary<NSString *,WPBarrageAvatarState *> *avatarStates;
@property(nonatomic,strong) NSMutableDictionary<NSString *,WPQCAvatarDownload *> *downloads;
@property(nonatomic,strong) NSMutableDictionary<NSString *,id> *localPreparations;
@property(nonatomic,strong) NSTimer *workTimer;
@property(nonatomic,strong) dispatch_queue_t decodeQueue;
@property(nonatomic,strong) NSMutableArray<WPBarrageDecodeJob *> *decodeJobs;
@property(nonatomic,strong) WPBarrageDecodeJob *decodingJob;
@property(nonatomic,strong) NSArray<NSNumber *> *laneYs;
@property(nonatomic,strong) NSArray<NSValue *> *obstacles;
@property(nonatomic) CGRect safeRect;
@property(nonatomic) CGRect dockFrame;
@property(nonatomic) NSUInteger sequence;
@property(nonatomic) NSUInteger newestSequence;
@property(nonatomic) NSUInteger dockedSequence;
@property(nonatomic) NSUInteger dockCandidateSequence;
@property(nonatomic) NSUInteger dockCandidateArrivalSequence;
@property(nonatomic) NSUInteger dockSuppressedThroughSequence;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) BOOL foregroundAvailable;
@property(nonatomic) BOOL details;
@property(nonatomic) BOOL namesShown;
@property(nonatomic) BOOL namesUseRemark;
@property(nonatomic) BOOL fullScreen;
@property(nonatomic) BOOL savingResources;
@property(nonatomic) CGFloat verticalPosition;
@property(nonatomic) CGFloat regionHeight;
@property(nonatomic) CGRect displayArea;
@property(nonatomic) BOOL lastNotifiedPlaybackState;
@property(nonatomic) NSUInteger playbackStateDeferral;
@property(nonatomic) CFTimeInterval lastReaction;
@property(nonatomic) CFTimeInterval suspendedAt;
#if defined(WP_PREVIEW_HOST)
@property(nonatomic) BOOL previewReducedMotion;
@property(nonatomic) BOOL previewSavingResources;
@property(nonatomic,copy) UIImage *(^previewAvatarProvider)(NSString *username);
@property(nonatomic,copy) NSString *(^previewDisplayNameProvider)(NSString *username, BOOL preferRemark);
@property(nonatomic) BOOL previewSkipNativePolicy;
@property(nonatomic,copy) WPBarrageConversationEligibility (^previewEligibilityProvider)(NSString *username);
#endif
@end

@implementation WPMessageBarrageController
- (instancetype)initWithHostView:(UIView *)hostView {
    if(!(self=[super init]))return nil;
    _hostView=hostView;_view=[[WPBarrageSurface alloc] initWithFrame:hostView.bounds];
    _view.backgroundColor=UIColor.clearColor;_view.clipsToBounds=YES;_view.hidden=YES;
    _view.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    _view.accessibilityViewIsModal=NO;[hostView addSubview:_view];
    _pending=[NSMutableArray new];_completedRecords=[NSMutableArray new];_recentIdentifiers=[NSMutableOrderedSet new];
    _avatars=[NSCache new];_avatars.totalCostLimit=WPBarrageAvatarBytes;_avatars.countLimit=24;_avatarCacheKeys=[NSMutableOrderedSet new];_avatarCacheCosts=[NSMutableDictionary new];
    _avatarLoads=[NSMutableSet new];_avatarRequests=[NSMutableOrderedSet new];_avatarStates=[NSMutableDictionary new];_downloads=[NSMutableDictionary new];_localPreparations=[NSMutableDictionary new];
    _decodeQueue=dispatch_queue_create("dev.zhour.wechatpet.barrage-avatar",dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,QOS_CLASS_UTILITY,0));
    _decodeJobs=[NSMutableArray new];
    _laneYs=@[];_obstacles=@[];_details=WPBarrageShowsDetails();_namesShown=WPBarrageShowsName();_namesUseRemark=WPBarrageNameUsesRemark();_fullScreen=WPBarrageFullScreen();_savingResources=WPBarrageResourceSavingActive();_verticalPosition=WPBarrageVerticalPosition();_regionHeight=WPBarrageRegionHeight();
    _foregroundAvailable=UIApplication.sharedApplication.applicationState==UIApplicationStateActive;
    NSMutableArray *pool=[NSMutableArray new];
    for(NSUInteger i=0;i<WPBarragePoolSize;i++) {
        WPBarrageBubble *bubble=[WPBarrageBubble new];bubble.accessibilityIdentifier=[NSString stringWithFormat:@"WPBarrageBubble%lu",(unsigned long)i];
        [bubble addTarget:self action:@selector(openControl:) forControlEvents:UIControlEventTouchUpInside];[_view addSubview:bubble];[pool addObject:bubble];
        __weak typeof(self) weakOwner=self;__weak WPBarrageBubble *weakControl=bubble;
        ((WPBarrageMotionLayer *)bubble.layer).onMotionRemoved=^{
            WPMessageBarrageController *owner=weakOwner;WPBarrageBubble *control=weakControl;
            // Intended reflows and clears disable their old delegate first.
            // Only an external removal of a still-live motion needs recovery.
            if(owner&&control.record&&control.animationEnd.completion)[owner finishBubble:control sequence:control.record.sequence motion:control.motionSerial finished:NO];
        };
        UITapGestureRecognizer *tap=[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapControl:)];tap.delegate=self;tap.cancelsTouchesInView=YES;[bubble addGestureRecognizer:tap];
    }
    _bubbles=pool;_flight=[WPBarrageFlight new];_flight.accessibilityIdentifier=@"WPBarrageAvatarFlight";
    [_flight addTarget:self action:@selector(openControl:) forControlEvents:UIControlEventTouchUpInside];[_view addSubview:_flight];
    UITapGestureRecognizer *flightTap=[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapControl:)];flightTap.delegate=self;flightTap.cancelsTouchesInView=YES;[_flight addGestureRecognizer:flightTap];
    NSNotificationCenter *center=NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(suspend:) name:UIApplicationWillResignActiveNotification object:nil];
    [center addObserver:self selector:@selector(suspend:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [center addObserver:self selector:@selector(resume:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [center addObserver:self selector:@selector(memoryWarning:) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    [center addObserver:self selector:@selector(chatPresentationChanged:) name:WPChatPresentationDidChangeNotification object:nil];
    return self;
}
- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [self.workTimer invalidate];
    for(WPQCAvatarDownload *download in self.downloads.allValues)[download cancel];
    for(id preparation in self.localPreparations.allValues)[preparation cancel];
    [self.view removeFromSuperview];
}
- (BOOL)canDisplay {
    return self.active&&self.foregroundAvailable&&WPBarrageEnabled()&&!WPBarrageIsPaused()&&self.hostView.window&&!self.hostView.window.hidden;
}
- (BOOL)resourceSaving {
#if defined(WP_PREVIEW_HOST)
    if(self.previewSavingResources)return YES;
#endif
    return WPBarrageResourceSavingActive();
}
- (BOOL)recordAllowed:(WPBarrageRecord *)record date:(NSDate *)date {
    if(!record)return NO;
    if(record.localPreview)return YES;
    if(!WPBarrageReminderAllowsUsername(record.conversation,date))return NO;
#if defined(WP_PREVIEW_HOST)
    if(self.previewSkipNativePolicy)return YES;
#endif
    WPBarrageConversationEligibility eligibility;
#if defined(WP_PREVIEW_HOST)
    if(self.previewEligibilityProvider)eligibility=self.previewEligibilityProvider(record.conversation);
    else
#endif
    eligibility=WPMessageBarrageConversationEligibility(record.conversation);
    if(eligibility==WPBarrageConversationEligibilityDenied)return NO;
    if(eligibility==WPBarrageConversationEligibilityAllowed)record.eligibilityConfirmed=YES;
    // Admission requires an actual positive native snapshot. After admission,
    // a short-lived home cache or session getter gap is not a delete command.
    // Explicit privacy/current-chat denials above remain effective immediately.
    return record.eligibilityConfirmed;
}
- (BOOL)reduceMotion {
#if defined(WP_PREVIEW_HOST)
    if(self.previewReducedMotion)return YES;
#endif
    return UIAccessibilityIsReduceMotionEnabled();
}
- (void)setActive:(BOOL)active {
    _active=active;
    if(![self canDisplay]){[self purgeForMemoryPressure];self.view.hidden=YES;}
    else {self.view.hidden=NO;[self pump];}
}
- (void)setTemporarilySuspended:(BOOL)suspended {
    if(_temporarilySuspended==suspended)return;
    _temporarilySuspended=suspended;CALayer *layer=self.view.layer;
    if(suspended){
        self.suspendedAt=CACurrentMediaTime();
        CFTimeInterval local=[layer convertTime:self.suspendedAt fromLayer:nil];
        layer.speed=0;layer.timeOffset=local;
        [self.workTimer invalidate];self.workTimer=nil;
    }else{
        CFTimeInterval now=CACurrentMediaTime(),paused=layer.timeOffset;
        layer.speed=1;layer.timeOffset=0;layer.beginTime=0;
        layer.beginTime=[layer convertTime:now fromLayer:nil]-paused;
        for(WPBarrageBubble *bubble in self.bubbles)if(bubble.record){
            CFTimeInterval delta=MAX(0,now-MAX(self.suspendedAt,bubble.motionStart));
            if(bubble.motionDuration>0)bubble.motionStart+=delta;
            if(bubble.staticDeadline>0)bubble.staticDeadline+=MAX(0,now-self.suspendedAt);
        }
        self.suspendedAt=0;
        // UIKit can cancel animations while a transient panel is visible. A
        // paused deadline alone cannot restore a missing render-server track.
        for(WPBarrageBubble *bubble in self.bubbles)if(bubble.record&&bubble.motionDuration>0&&![bubble.layer animationForKey:@"WPBarrageMove"]){
            CGFloat progress=MIN(1,MAX(0,(now-bubble.motionStart)/bubble.motionDuration));
            CGFloat x=bubble.motionFrom.x+(bubble.motionTo.x-bubble.motionFrom.x)*progress;
            [self animateBubble:bubble fromX:x];
        }
        if([self canDisplay])[self pump];
    }
}
- (BOOL)hasMovingMessages {
    if(self.pending.count)return YES;
    for(WPBarrageBubble *bubble in self.bubbles)if(bubble.record)return YES;
    return NO;
}
- (BOOL)returningToDock {return self.flight.record!=nil;}
- (BOOL)isDisplaying {return self.hasMovingMessages||self.returningToDock;}
- (void)notifyPlaybackState {
    if(self.playbackStateDeferral)return;
    BOOL playing=self.isDisplaying;
    if(playing==self.lastNotifiedPlaybackState)return;
    self.lastNotifiedPlaybackState=playing;
    if(self.onPlaybackChanged)self.onPlaybackChanged(playing);
}
- (WPBarrageMessage *)identityForRecord:(WPBarrageRecord *)record {
    WPBarrageMessage *message=[WPBarrageMessage new];
    message.conversationUsername=record.conversation?:@"";message.senderUsername=record.sender?:@"";
    message.identifier=record.identifier?:@"";message.createdAt=record.createdAt?:NSDate.date;
    message.localPreview=record.localPreview;message.text=@"";return message;
}
- (BOOL)hostAllowsDock:(WPBarrageRecord *)record {
    return !self.onShouldDock||self.onShouldDock([self identityForRecord:record]);
}
- (void)suspend:(NSNotification *)note {
    // UIKit also resigns active for transient system panels and interruptions.
    // A page/keyboard/overlay transition must never erase an admitted message.
    // The did-enter-background notification remains the hard privacy boundary.
    if([note.name isEqual:UIApplicationWillResignActiveNotification]&&UIApplication.sharedApplication.applicationState!=UIApplicationStateBackground){
        self.temporarilySuspended=YES;return;
    }
    self.foregroundAvailable=NO;[self purgeForMemoryPressure];self.view.hidden=YES;
}
- (void)resume:(NSNotification *)note {self.foregroundAvailable=YES;self.temporarilySuspended=NO;self.view.hidden=![self canDisplay];if([self canDisplay])[self pump];}
- (void)memoryWarning:(NSNotification *)note {[self trimForMemoryPressure];}
- (void)chatPresentationChanged:(NSNotification *)note {if(NSThread.isMainThread)[self pump];else dispatch_async(dispatch_get_main_queue(),^{[self pump];});}
- (void)clearControl:(WPBarrageMovingControl *)control {
    control.motionSerial++;control.motionDuration=0;control.staticDeadline=0;control.record.body=@"";control.record=nil;
    control.animationEnd.completion=nil;control.animationEnd=nil;[control.layer removeAllAnimations];
    [control cancelTrackingWithEvent:nil];for(UIGestureRecognizer *gesture in control.gestureRecognizers){gesture.enabled=NO;gesture.enabled=YES;}
    control.hidden=YES;control.accessibilityLabel=nil;control.accessibilityValue=nil;
    if([control isKindOfClass:WPBarrageBubble.class]) {
        WPBarrageBubble *bubble=(id)control;bubble.bodyLabel.text=nil;bubble.nameLabel.text=nil;bubble.avatarView.image=nil;bubble.actualAvatar=nil;
    } else {
        WPBarrageFlight *flight=(id)control;flight.avatarView.image=nil;flight.actualAvatar=nil;
    }
}
- (void)cancelFlight {[self clearControl:self.flight];self.dockCandidateSequence=0;self.dockCandidateArrivalSequence=0;}
- (void)clearDock {
    [self.completedRecords removeAllObjects];self.newestSequence=++self.sequence;self.dockedSequence=0;self.dockSuppressedThroughSequence=self.sequence;[self cancelFlight];[self notifyPlaybackState];
}
- (void)releaseAvatarWorkAndCache {
    self.generation++;[self.workTimer invalidate];self.workTimer=nil;
    self.decodingJob.cancelled=YES;self.decodingJob.image=nil;
    for(WPBarrageDecodeJob *job in self.decodeJobs){job.cancelled=YES;job.image=nil;}[self.decodeJobs removeAllObjects];
    for(WPQCAvatarDownload *download in self.downloads.allValues)[download cancel];
    for(id preparation in self.localPreparations.allValues)[preparation cancel];
    [self.localPreparations removeAllObjects];[self.downloads removeAllObjects];[self.avatarLoads removeAllObjects];[self.avatarRequests removeAllObjects];[self.avatarStates removeAllObjects];
    [self.avatars removeAllObjects];[self.avatarCacheKeys removeAllObjects];[self.avatarCacheCosts removeAllObjects];self.avatarCacheCost=0;
}
- (void)trimForMemoryPressure {
    // At most six already visible capsules keep their tiny image and animation.
    // Release waiting bodies and expensive work first; never blank the screen.
    self.avatarCooldownUntil=MAX(self.avatarCooldownUntil,CACurrentMediaTime()+8);
    [self releaseAvatarWorkAndCache];
    for(WPBarrageRecord *record in self.pending)record.body=@"";
    [self.pending removeAllObjects];
    [self scheduleWorkTimer];[self notifyPlaybackState];
}
- (void)purgeForMemoryPressure {
    // Explicit background/disable/privacy boundary, not the ordinary warning.
    [self releaseAvatarWorkAndCache];self.newestSequence=++self.sequence;
    for(WPBarrageRecord *record in self.pending)record.body=@"";
    [self.pending removeAllObjects];[self.completedRecords removeAllObjects];
    for(WPBarrageBubble *bubble in self.bubbles)[self clearControl:bubble];[self cancelFlight];
    [self.recentIdentifiers removeAllObjects];[self notifyPlaybackState];
}
- (void)rebuildLanes {
    NSMutableArray *ys=[NSMutableArray new];
    if(!WPBarrageRectValid(self.safeRect)){self.laneYs=ys;self.displayArea=CGRectZero;return;}
    CGRect area=WPBarrageDisplayArea(self.safeRect);self.displayArea=area;
    NSUInteger requested=[self resourceSaving]?(self.fullScreen?3:2):(self.fullScreen?6:3);
    CGFloat usable=area.size.height-16-WPBarrageHeight;
    if(usable<0){self.laneYs=ys;return;}
    NSUInteger count=MIN(requested,(NSUInteger)floor((area.size.height-16)/(WPBarrageHeight+8)));
    for(NSUInteger i=0;i<count;i++) {
        CGFloat y=CGRectGetMinY(area)+8+(count>1?usable*i/(count-1):0);
        CGRect track=CGRectMake(CGRectGetMinX(area),y,area.size.width,WPBarrageHeight);BOOL blocked=NO;
        for(NSValue *value in self.obstacles)if(CGRectIntersectsRect(track,value.CGRectValue)){blocked=YES;break;}
        if(!blocked)[ys addObject:@(y)];
    }
    self.laneYs=ys;
}
// Preserve each live control and its current visual x across keyboard, page,
// rotation and region adjustments. No layout transition counts as a message
// completion, and neither text nor pending messages are discarded here.
- (void)reflowBubblesFromArea:(CGRect)oldArea {
    CGRect area=self.displayArea;
    if(!WPBarrageRectValid(area))return;
    NSMutableArray<WPBarrageBubble *> *live=[NSMutableArray new];
    for(WPBarrageBubble *bubble in self.bubbles)if(bubble.record)[live addObject:bubble];
    [live sortUsingComparator:^NSComparisonResult(WPBarrageBubble *a,WPBarrageBubble *b){
        CGFloat ay=CGRectGetMidY([a visualFrame]),by=CGRectGetMidY([b visualFrame]);
        return ay<by?NSOrderedAscending:(ay>by?NSOrderedDescending:NSOrderedSame);
    }];
    // A newly shortened region must not squeeze the existing messages together.
    // Grandfather their tracks inside the screen until they naturally finish;
    // only newly started capsules use the smaller configured region.
    CGFloat spacing=WPBarrageHeight+8;
    CGFloat required=live.count?16+WPBarrageHeight+spacing*(live.count-1):0;
    if(area.size.height<required){
        area.size.height=MIN(self.safeRect.size.height,required);
        area.origin.y=MAX(CGRectGetMinY(self.safeRect),MIN(CGRectGetMaxY(self.safeRect)-area.size.height,CGRectGetMidY(self.displayArea)-area.size.height/2));
    }
    CGFloat low=CGRectGetMinY(area)+8+WPBarrageHeight/2;
    CGFloat high=MAX(low,CGRectGetMaxY(area)-8-WPBarrageHeight/2);
    if(live.count>1)spacing=MIN(spacing,(high-low)/(live.count-1));
    for(NSUInteger index=0;index<live.count;index++){
        WPBarrageBubble *bubble=live[index];CGRect visual=[bubble visualFrame];
        CGFloat oldTravel=MAX(1,oldArea.size.height-16-WPBarrageHeight);
        CGFloat fraction=MIN(1,MAX(0,(CGRectGetMidY(visual)-CGRectGetMinY(oldArea)-8-WPBarrageHeight/2)/oldTravel));
        CGFloat y=MAX(low+index*spacing,MIN(high-(live.count-1-index)*spacing,low+(high-low)*fraction));
        bubble.center=CGPointMake(bubble.center.x,y);
        if([self reduceMotion])bubble.center=CGPointMake(MAX(CGRectGetMinX(self.safeRect)+8+bubble.bounds.size.width/2,MIN(CGRectGetMaxX(self.safeRect)-8-bubble.bounds.size.width/2,CGRectGetMidX(visual))),y);
        else [self animateBubble:bubble fromX:CGRectGetMidX(visual)];
    }
}
- (void)updateLayoutSafeRect:(CGRect)safeRect obstacles:(NSArray<NSValue *> *)obstacles dockFrame:(CGRect)dockFrame {
    UIView *host=self.hostView;if(!host)return;
    CGRect clipped=WPBarrageRectValid(safeRect)?CGRectIntersection(safeRect,host.bounds):CGRectZero;
    CGRect safe=[host convertRect:clipped toView:self.view];
    NSMutableArray *clean=[NSMutableArray new];
    for(id item in obstacles) {
        if(![item isKindOfClass:NSValue.class]||strcmp([item objCType],@encode(CGRect))!=0)continue;
        CGRect obstacle=[item CGRectValue];
        if(WPBarrageRectValid(obstacle)){
            NSValue *rect=[NSValue valueWithCGRect:[host convertRect:obstacle toView:self.view]];
            if(![clean containsObject:rect])[clean addObject:rect];
        }
        if(clean.count==24)break;
    }
    CGRect dock=WPBarrageRectValid(dockFrame)?[host convertRect:dockFrame toView:self.view]:CGRectZero;
    BOOL geometryChanged=!CGRectEqualToRect(safe,self.safeRect);
    BOOL obstaclesChanged=![clean isEqual:self.obstacles];
    BOOL dockMoved=!CGRectEqualToRect(dock,self.dockFrame);
    CGRect oldArea=self.displayArea;
    CGPoint flightPoint=CGPointZero;
    if(self.flight.record)flightPoint=CGPointMake(CGRectGetMidX([self.flight visualFrame]),CGRectGetMidY([self.flight visualFrame]));
    self.safeRect=safe;self.obstacles=clean;self.dockFrame=dock;
    if(geometryChanged||obstaclesChanged){[self rebuildLanes];if(geometryChanged)[self reflowBubblesFromArea:oldArea];}
    // Moving the pet retargets the one flight from its presentation position.
    // It never commits immediately or causes other scrolling messages to fly.
    if(self.flight.record&&(geometryChanged||dockMoved)){
        if(WPBarrageRectValid(dock)) [self animateFlightFromPoint:flightPoint];
        else [self cancelFlight];
    }
    [self pump];
}
- (void)styleBubble:(WPBarrageBubble *)bubble {
    CGFloat opacity=MIN(.9,MAX(.25,WPBarrageBackgroundOpacity()));
    bubble.backgroundColor=[UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *trait){return [(trait.userInterfaceStyle==UIUserInterfaceStyleDark?[UIColor colorWithWhite:.10 alpha:1]:UIColor.whiteColor) colorWithAlphaComponent:opacity];}];
    bubble.layer.borderColor=[UIColor colorWithWhite:.6 alpha:.22].CGColor;
}
- (void)refreshPreferences {
    BOOL details=WPBarrageShowsDetails(),fullScreen=WPBarrageFullScreen();
    BOOL saving=[self resourceSaving];
    if(self.details&&!details) {
        for(WPBarrageRecord *record in self.pending)record.body=@"";
        for(WPBarrageBubble *bubble in self.bubbles)if(bubble.record) {
            CGRect frame=[bubble visualFrame];bubble.record.body=@"";bubble.bodyLabel.text=nil;
            bubble.accessibilityLabel=@"头像";bubble.accessibilityValue=nil;
            // Collapse in place; do not restart at the right edge or reveal
            // any previous body when details are enabled again.
            CGFloat width=bubble.nameLabel.text.length?MIN(1800,ceil([bubble.nameLabel.text sizeWithAttributes:@{NSFontAttributeName:bubble.nameLabel.font}].width)+61):46;
            if([self reduceMotion])width=MIN(width,self.safeRect.size.width-16);
            bubble.bounds=CGRectMake(0,0,width,46);[bubble layoutContents];
            if(![self reduceMotion])[self animateBubble:bubble fromX:CGRectGetMinX(frame)+width/2];
        }
        self.flight.record.body=@"";self.flight.accessibilityLabel=self.flight.record?@"头像":nil;
    }
    BOOL nameChanged=self.namesShown!=WPBarrageShowsName() || self.namesUseRemark!=WPBarrageNameUsesRemark();
    self.namesShown=WPBarrageShowsName();self.namesUseRemark=WPBarrageNameUsesRemark();
    if(nameChanged){
        for(WPBarrageRecord *record in self.pending)record.displayName=self.namesShown?[self displayNameForSender:record.sender]:@"";
        for(WPBarrageBubble *bubble in self.bubbles)if(bubble.record){
            CGRect visual=[bubble visualFrame];
            bubble.record.displayName=self.namesShown?[self displayNameForSender:bubble.record.sender]:@"";
            bubble.nameLabel.text=bubble.record.displayName;
            CGFloat width=bubble.record.body.length?ceil([bubble.record.body sizeWithAttributes:@{NSFontAttributeName:bubble.bodyLabel.font}].width)+61:46;
            if(bubble.record.displayName.length)width=MAX(width,ceil([bubble.record.displayName sizeWithAttributes:@{NSFontAttributeName:bubble.nameLabel.font}].width)+61);
            width=MIN(1800,MAX(46,width));if([self reduceMotion])width=MIN(width,self.safeRect.size.width-16);
            BOOL resized=fabs(width-bubble.bounds.size.width)>.5;bubble.bounds=CGRectMake(0,0,width,46);[bubble layoutContents];
            if(resized && ![self reduceMotion])[self animateBubble:bubble fromX:CGRectGetMinX(visual)+width/2];
        }
    }
    self.details=details;
    CGFloat position=WPBarrageVerticalPosition(),height=WPBarrageRegionHeight();
    if(self.fullScreen!=fullScreen||self.savingResources!=saving||fabs(self.verticalPosition-position)>.0001||fabs(self.regionHeight-height)>.0001) {
        CGRect oldArea=self.displayArea;
        self.fullScreen=fullScreen;self.savingResources=saving;self.verticalPosition=position;self.regionHeight=height;
        [self rebuildLanes];[self reflowBubblesFromArea:oldArea];
    }
    [self discardInvalidRecords];
    NSUInteger limit=saving?6:WPBarrageQueueLimit;
    while(self.pending.count>limit){self.pending.firstObject.body=@"";[self.pending removeObjectAtIndex:0];}
    for(WPBarrageBubble *bubble in self.bubbles)[self styleBubble:bubble];
    if(![self canDisplay]){[self purgeForMemoryPressure];self.view.hidden=YES;}else {self.view.hidden=NO;[self pump];}
}
- (void)rememberDockCandidate:(WPBarrageRecord *)record {
    for(WPBarrageRecord *old in self.completedRecords)if(old.sequence==record.sequence)return;
    WPBarrageRecord *candidate=[WPBarrageRecord new];candidate.conversation=record.conversation;candidate.sender=record.sender;
    candidate.identifier=record.identifier;candidate.createdAt=record.createdAt;candidate.sequence=record.sequence;
    candidate.localPreview=record.localPreview;candidate.eligibilityConfirmed=record.eligibilityConfirmed;candidate.body=@"";
    [self.completedRecords addObject:candidate];
    [self.completedRecords sortUsingComparator:^NSComparisonResult(WPBarrageRecord *a,WPBarrageRecord *b){return a.sequence<b.sequence?NSOrderedAscending:(a.sequence>b.sequence?NSOrderedDescending:NSOrderedSame);}];
    while(self.completedRecords.count>12)[self.completedRecords removeObjectAtIndex:0];
}
- (NSString *)displayNameForSender:(NSString *)username {
#if defined(WP_PREVIEW_HOST)
    if(self.previewDisplayNameProvider)return WPBarrageString(self.previewDisplayNameProvider(username,WPBarrageNameUsesRemark()),32);
#endif
    return WPBarrageString(WPQuickChatDisplayName(username,WPBarrageNameUsesRemark()),32);
}
- (void)enqueueMessage:(WPBarrageMessage *)message {
    if(![message isKindOfClass:WPBarrageMessage.class]||![self canDisplay])return;
    NSString *conversation=WPBarrageString(message.conversationUsername,256);
    if(!conversation.length)return;
    NSDate *now=NSDate.date;
    NSDate *created=[message.createdAt isKindOfClass:NSDate.class]?message.createdAt:now;
    NSTimeInterval age=[now timeIntervalSinceDate:created];
    if(!isfinite(age)||age>=WPBarrageQueueLifetime||age < -5)return;
    NSString *identifier=WPBarrageString(message.identifier,320);
    if(identifier.length&&[self.recentIdentifiers containsObject:identifier])return;
    WPBarrageRecord *record=[WPBarrageRecord new];record.conversation=conversation;
    record.identifier=identifier;record.localPreview=message.localPreview;record.eligibilityConfirmed=message.sourceEligibilityConfirmed;record.createdAt=created;record.arrivedAt=CACurrentMediaTime();record.expiresAt=record.arrivedAt+WPBarrageQueueLifetime-MAX(0,age);
    if(![self recordAllowed:record date:now])return;
    // A rejected/transient attempt must not poison a later valid retry.
    if(identifier.length){[self.recentIdentifiers addObject:identifier];while(self.recentIdentifiers.count>64)[self.recentIdentifiers removeObjectAtIndex:0];}
    if(!self.hasMovingMessages)[self.completedRecords removeAllObjects];
    record.sender=WPBarrageString(message.senderUsername,256);if(!record.sender.length)record.sender=conversation;
    record.body=self.details&&WPBarrageShowsDetails()?WPBarrageBody(message.text):@"";
    record.displayName=WPBarrageShowsName()?[self displayNameForSender:record.sender]:@"";
    record.sequence=++self.sequence;self.newestSequence=record.sequence;[self rememberDockCandidate:record];
    // Any new arrival wins, even if its capsule is waiting. Cancelling the
    // previous flight cannot invoke onDock through an animation completion.
    [self cancelFlight];
    for(NSInteger i=(NSInteger)self.pending.count-1;i>=0;i--)if([self.pending[(NSUInteger)i].conversation isEqual:conversation]){self.pending[(NSUInteger)i].body=@"";[self.pending removeObjectAtIndex:(NSUInteger)i];}
    NSUInteger limit=[self resourceSaving]?6:WPBarrageQueueLimit;
    while(self.pending.count>=limit){self.pending.firstObject.body=@"";[self.pending removeObjectAtIndex:0];}
    [self.pending addObject:record];[self react];[self pump];
}
- (void)react {
    CFTimeInterval now=CACurrentMediaTime();
    if([self canDisplay]&&![self resourceSaving]&&WPBarrageReactionsEnabled()&&self.onPetReaction&&now-self.lastReaction>=1.8){self.lastReaction=now;self.onPetReaction();}
}
- (void)discardInvalidRecords {
    NSDate *date=NSDate.date;CFTimeInterval now=CACurrentMediaTime();
    for(NSInteger index=(NSInteger)self.pending.count-1;index>=0;index--){
        WPBarrageRecord *record=self.pending[(NSUInteger)index];
        if(record.expiresAt<=now||![self recordAllowed:record date:date]){record.body=@"";[self.pending removeObjectAtIndex:(NSUInteger)index];}
    }
    // A settings change can start quiet hours or exclude a contact while a
    // capsule is already visible. It must not finish into a retained avatar.
    for(WPBarrageBubble *bubble in self.bubbles)if(bubble.record&&![self recordAllowed:bubble.record date:date])[self clearControl:bubble];
    if(self.flight.record&&![self recordAllowed:self.flight.record date:date])[self cancelFlight];
}
- (void)pump {
    if(self.temporarilySuspended){[self.workTimer invalidate];self.workTimer=nil;[self notifyPlaybackState];return;}
    if(![self canDisplay]){[self.workTimer invalidate];self.workTimer=nil;[self notifyPlaybackState];return;}
    [self discardInvalidRecords];
    for(WPBarrageBubble *bubble in self.bubbles)if(bubble.record&&((bubble.motionDuration>0&&CACurrentMediaTime()>=bubble.motionStart+bubble.motionDuration+.1)||(bubble.staticDeadline>0&&CACurrentMediaTime()>=bubble.staticDeadline))){
        [self finishBubble:bubble sequence:bubble.record.sequence motion:bubble.motionSerial finished:YES];
    }
    self.view.hidden=NO;
    NSUInteger liveCount=0;for(WPBarrageBubble *bubble in self.bubbles)if(bubble.record)liveCount++;
    NSUInteger concurrentLimit=[self resourceSaving]?(self.fullScreen?3:2):(self.fullScreen?6:3);
    // Existing capsules survive a lower budget, but cannot create replacement
    // work until their count drops below it. Track positions may have changed
    // after a resize, so global occupancy must not depend on exact y matches.
    for(NSUInteger lane=0;lane<self.laneYs.count&&self.pending.count&&liveCount<concurrentLimit;lane++) {
        BOOL used=NO;WPBarrageBubble *freeBubble=nil;
        CGFloat laneCenter=self.laneYs[lane].doubleValue+23;
        for(WPBarrageBubble *bubble in self.bubbles){if(bubble.record&&fabs(bubble.center.y-laneCenter)<WPBarrageHeight+8-.5)used=YES;if(!bubble.record&&!freeBubble)freeBubble=bubble;}
        if(used||!freeBubble)continue;
        WPBarrageRecord *record=self.pending.firstObject;[self.pending removeObjectAtIndex:0];
        // Recheck at the actual display boundary; enqueue eligibility may be
        // several seconds old by the time a slow preceding capsule leaves.
        if(record.expiresAt>CACurrentMediaTime()&&[self recordAllowed:record date:NSDate.date]){[self startBubble:freeBubble record:record lane:(NSInteger)lane];if(freeBubble.record)liveCount++;}
        else record.body=@"";
    }
    [self pumpAvatarWork];[self scheduleWorkTimer];[self notifyPlaybackState];
}
- (void)startBubble:(WPBarrageBubble *)bubble record:(WPBarrageRecord *)record lane:(NSInteger)lane {
    if(![self recordAllowed:record date:NSDate.date]||record.expiresAt<=CACurrentMediaTime()){record.body=@"";return;}
    bubble.record=record;bubble.lane=lane;bubble.hidden=NO;bubble.alpha=1;
    bubble.bodyLabel.text=record.body.length?record.body:nil;
    bubble.nameLabel.text=record.displayName.length?record.displayName:nil;
    CGFloat width=record.body.length?ceil([record.body sizeWithAttributes:@{NSFontAttributeName:bubble.bodyLabel.font}].width)+61:46;
    if(record.displayName.length)width=MAX(width,ceil([record.displayName sizeWithAttributes:@{NSFontAttributeName:bubble.nameLabel.font}].width)+61);
    // The source has at most 80 characters. This upper bound also covers a
    // malformed font measurement without allocating a huge backing surface.
    width=MIN(1800,MAX(46,width));
    if([self reduceMotion])width=MIN(width,self.safeRect.size.width-16);
    bubble.bounds=CGRectMake(0,0,width,46);bubble.center=CGPointMake(CGRectGetMaxX(self.safeRect)+8+width/2,self.laneYs[(NSUInteger)lane].doubleValue+23);
    [bubble layoutContents];[self styleBubble:bubble];
    UIImage *cachedShared = WPCachedSharedChatAvatar(record.sender);
    bubble.actualAvatar=[self.avatars objectForKey:record.sender] ?: cachedShared;
    bubble.avatarView.image=bubble.actualAvatar?:[UIImage systemImageNamed:@"person.crop.circle.fill"];
    bubble.accessibilityLabel=record.body.length?record.body:@"头像";bubble.accessibilityValue=nil;
    bubble.pixelsPerSecond=80*MIN(2,MAX(.5,WPBarrageSpeed()));
    if([self reduceMotion]) {
        bubble.motionDuration=0;bubble.staticDeadline=CACurrentMediaTime()+2.4;bubble.center=CGPointMake(CGRectGetMinX(self.safeRect)+8+width/2,bubble.center.y);
        NSUInteger sequence=record.sequence,motion=++bubble.motionSerial;__weak typeof(self) weakSelf=self;__weak WPBarrageBubble *weakBubble=bubble;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(2.4*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
            WPMessageBarrageController *owner=weakSelf;WPBarrageBubble *control=weakBubble;
            if(owner&&!owner.temporarilySuspended&&control.staticDeadline>0&&CACurrentMediaTime()>=control.staticDeadline)[owner finishBubble:control sequence:sequence motion:motion finished:YES];
        });
    } else [self animateBubble:bubble fromX:bubble.center.x];
}
- (void)animateBubble:(WPBarrageBubble *)bubble fromX:(CGFloat)fromX {
    if(!bubble.record)return;
    bubble.motionSerial++;bubble.animationEnd.completion=nil;[bubble.layer removeAllAnimations];
    CGFloat endX=CGRectGetMinX(self.safeRect)-8-bubble.bounds.size.width/2;
    CFTimeInterval duration=MAX(.05,(fromX-endX)/MAX(1,bubble.pixelsPerSecond));
    CGPoint from=CGPointMake(fromX,bubble.center.y),to=CGPointMake(endX,bubble.center.y);
    bubble.motionFrom=from;bubble.motionTo=to;bubble.motionStart=CACurrentMediaTime();bubble.motionDuration=duration;
    [CATransaction begin];[CATransaction setDisableActions:YES];bubble.layer.position=to;[CATransaction commit];
    CABasicAnimation *animation=[CABasicAnimation animationWithKeyPath:@"position.x"];
    animation.fromValue=@(fromX);animation.toValue=@(endX);animation.duration=duration;animation.timingFunction=[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    NSUInteger sequence=bubble.record.sequence,motion=bubble.motionSerial;__weak typeof(self) weakSelf=self;__weak WPBarrageBubble *weakBubble=bubble;
    WPBarrageAnimationEnd *end=[WPBarrageAnimationEnd new];end.completion=^(BOOL finished){[weakSelf finishBubble:weakBubble sequence:sequence motion:motion finished:finished];};
    bubble.animationEnd=end;animation.delegate=end;[bubble.layer addAnimation:animation forKey:@"WPBarrageMove"];
}
- (void)finishBubble:(WPBarrageBubble *)bubble sequence:(NSUInteger)sequence motion:(NSUInteger)motion finished:(BOOL)finished {
    if(!bubble||!bubble.record||bubble.record.sequence!=sequence||bubble.motionSerial!=motion||self.temporarilySuspended)return;
    if(!finished){
        // Reparenting a secure canvas or presenting a native page can cancel a
        // CA animation. Its model position is already offscreen; leaving it
        // there makes the message appear to disappear although its text lives.
        // Recover at the actual presentation/elapsed position next turn, with
        // identity and motion guards so deliberate clears can never resurrect.
        CGFloat fromX=CGRectGetMidX([bubble visualFrame]);
        if(fabs(fromX-bubble.motionTo.x)<.5&&bubble.motionDuration>0){
            CGFloat progress=MIN(1,MAX(0,(CACurrentMediaTime()-bubble.motionStart)/bubble.motionDuration));
            fromX=bubble.motionFrom.x+(bubble.motionTo.x-bubble.motionFrom.x)*progress;
        }
        __weak typeof(self) weakSelf=self;__weak WPBarrageBubble *weakBubble=bubble;
        dispatch_async(dispatch_get_main_queue(),^{
            WPMessageBarrageController *owner=weakSelf;WPBarrageBubble *control=weakBubble;
            if(!owner||!control||control.record.sequence!=sequence||control.motionSerial!=motion)return;
            // Another caller may have deliberately replaced the animation.
            if([control.layer animationForKey:@"WPBarrageMove"])return;
            if(owner.temporarilySuspended||![owner canDisplay])return;
            if(![owner recordAllowed:control.record date:NSDate.date]){[owner clearControl:control];[owner pump];return;}
            if(fromX<=CGRectGetMinX(owner.safeRect)-control.bounds.size.width/2){
                [owner finishBubble:control sequence:sequence motion:motion finished:YES];
            }else [owner animateBubble:control fromX:fromX];
        });
        return;
    }
    self.playbackStateDeferral++;
    WPBarrageRecord *record=bubble.record;record.body=@"";
    UIImage *image=bubble.actualAvatar;CGFloat y=bubble.center.y;
    [self rememberDockCandidate:record];
    [self clearControl:bubble];
    // Pump first: a queued capsule can occupy the newly freed track. Only the
    // final actual left-edge completion of the burst earns one local bounce.
    [self pump];
    if([self canDisplay]&&!self.hasMovingMessages){
        // Completion order depends on text length. The one end-of-burst signal
        // uses the newest still eligible message, never an older long capsule.
        WPBarrageRecord *newest=nil;
        for(WPBarrageRecord *candidate in self.completedRecords.reverseObjectEnumerator)
            if([self recordAllowed:candidate date:NSDate.date]&&[self hostAllowsDock:candidate]){newest=candidate;break;}
        [self.completedRecords removeAllObjects];
        if(newest)[self startFlight:newest image:(newest.sequence==record.sequence?image:(WPCachedSharedChatAvatar(newest.sender)?:[self.avatars objectForKey:newest.sender])) fromY:y];
    }
    self.playbackStateDeferral--;[self notifyPlaybackState];
}
- (void)startFlight:(WPBarrageRecord *)record image:(UIImage *)image fromY:(CGFloat)y {
    // Kept as an internal compatibility boundary for old preview drivers. There
    // is no return flight: the host performs one small local avatar bounce.
    if(!record||self.hasMovingMessages||record.sequence<=self.dockSuppressedThroughSequence||![self canDisplay]||![self recordAllowed:record date:NSDate.date]||![self hostAllowsDock:record])return;
    [self cancelFlight];record.body=@"";
    self.dockCandidateSequence=record.sequence;self.dockCandidateArrivalSequence=self.newestSequence;
    [self commitDock:record image:image];
    self.dockCandidateSequence=0;self.dockCandidateArrivalSequence=0;
}
- (void)animateFlightFromPoint:(CGPoint)from { [self cancelFlight]; }
- (void)finishFlightSequence:(NSUInteger)sequence motion:(NSUInteger)motion finished:(BOOL)finished {
    // A delayed callback from any preceding generation cannot create a dock.
    [self cancelFlight];
}
- (void)commitDock:(WPBarrageRecord *)record image:(UIImage *)image {
    if(!record||record.sequence!=self.dockCandidateSequence||self.dockCandidateArrivalSequence!=self.newestSequence||record.sequence<=self.dockedSequence||record.sequence<=self.dockSuppressedThroughSequence||self.hasMovingMessages||![self canDisplay]||![self recordAllowed:record date:NSDate.date]||![self hostAllowsDock:record])return;
    record.body=@"";self.dockedSequence=record.sequence;
    if(self.onBatchCompleted)self.onBatchCompleted([self identityForRecord:record],image);
    else if(self.onDockMessage)self.onDockMessage([self identityForRecord:record],image);
    else if(self.onDock)self.onDock(record.conversation,record.sender,image);
    [self react];
}
- (void)openControl:(WPBarrageMovingControl *)control {
    WPBarrageRecord *record=control.record;if(!record||control.hidden||self.temporarilySuspended||![self canDisplay])return;
    if(control.trackingSequence&&control.trackingSequence!=record.sequence)return;
    if(![self recordAllowed:record date:NSDate.date]){[self clearControl:control];[self pump];return;}
    NSString *conversation=[record.conversation copy];
    // Consume only the tapped capsule. Other conversations keep traversing
    // while the native chat is presented, instead of a global memory purge.
    self.playbackStateDeferral++;[self clearControl:control];[self pump];self.playbackStateDeferral--;[self notifyPlaybackState];
    if(conversation.length&&self.onOpenConversation)self.onOpenConversation(conversation);
}
- (void)tapControl:(UITapGestureRecognizer *)tap {
    // Tap recognition stays with the view originally hit. It does not compare
    // the finger to an offscreen model frame as a stock UIControl would.
    // Cancelling normal control tracking also prevents a duplicate open action.
    if(tap.state==UIGestureRecognizerStateRecognized&&[tap.view isKindOfClass:WPBarrageMovingControl.class]){
        WPBarrageMovingControl *control=(id)tap.view;
        if(control.record.sequence==control.tapSequence){control.trackingSequence=control.tapSequence;[self openControl:control];}
    }
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    if(![gesture.view isKindOfClass:WPBarrageMovingControl.class])return NO;
    WPBarrageMovingControl *control=(id)gesture.view;
    if(!control.record||control.hidden||self.temporarilySuspended||![self canDisplay])return NO;
    control.tapSequence=control.record.sequence;return YES;
}
- (UIView *)hitTest:(CGPoint)hostPoint withEvent:(UIEvent *)event {
    if(self.temporarilySuspended||![self canDisplay])return nil;
    return [self.view hitTest:[self.hostView convertPoint:hostPoint toView:self.view] withEvent:event];
}
- (void)pumpAvatarWork {
    if(self.temporarilySuspended||![self canDisplay])return;
    for(WPBarrageBubble *bubble in self.bubbles)if(bubble.record&&!bubble.record.localPreview&&!bubble.actualAvatar)[self requestAvatar:bubble.record.sender];
    if(self.flight.record&&!self.flight.record.localPreview&&!self.flight.actualAvatar)[self requestAvatar:self.flight.record.sender];
}
- (void)acceptAvatar:(UIImage *)image username:(NSString *)username generation:(NSUInteger)generation {
    if(generation!=self.generation)return;
    [self.avatarLoads removeObject:username];
    if(![self canDisplay])return;
    WPBarrageAvatarState *state=[self avatarStateForUsername:username create:YES];
    if(image.CGImage) {
        state.status=WPBarrageAvatarReady;state.failures=0;state.nextAttempt=0;
        // NSCache limits are advisory. Enforce both the decoded-byte ledger
        // and an explicit 24-entry ceiling before handing it another image.
        NSUInteger cost=WPBarrageImageCost(image),previous=[self.avatarCacheCosts[username] unsignedIntegerValue];
        self.avatarCacheCost-=MIN(self.avatarCacheCost,previous);[self.avatarCacheCosts removeObjectForKey:username];
        [self.avatarCacheKeys removeObject:username];[self.avatarCacheKeys addObject:username];
        while(self.avatarCacheKeys.count>24||(self.avatarCacheCost+cost>WPBarrageAvatarBytes&&self.avatarCacheKeys.count>1)){
            NSString *old=self.avatarCacheKeys.firstObject;[self.avatars removeObjectForKey:old];[self.avatarCacheKeys removeObjectAtIndex:0];
            self.avatarCacheCost-=MIN(self.avatarCacheCost,[self.avatarCacheCosts[old] unsignedIntegerValue]);[self.avatarCacheCosts removeObjectForKey:old];
        }
        if(cost<=WPBarrageAvatarBytes){self.avatarCacheCost+=cost;self.avatarCacheCosts[username]=@(cost);[self.avatars setObject:image forKey:username cost:cost];}
        for(WPBarrageBubble *bubble in self.bubbles)if([bubble.record.sender isEqualToString:username]){bubble.actualAvatar=image;bubble.avatarView.image=image;}
        if([self.flight.record.sender isEqualToString:username]){self.flight.actualAvatar=image;self.flight.avatarView.image=image;}
    } else {
        state.status=WPBarrageAvatarCooling;state.failures=MIN(4,state.failures+1);
        static const NSTimeInterval delays[]={2,5,15,30};
        state.nextAttempt=CACurrentMediaTime()+delays[state.failures-1];
    }
    [self pumpAvatarWork];[self scheduleWorkTimer];
}
- (void)decodeAvatar:(UIImage *)image username:(NSString *)username generation:(NSUInteger)generation {
    if(generation!=self.generation||![self canDisplay])return;
    if(self.decodeJobs.count>=2){[self acceptAvatar:nil username:username generation:generation];return;}
    WPBarrageDecodeJob *job=[WPBarrageDecodeJob new];job.image=image;job.username=username;job.generation=generation;
    [self.decodeJobs addObject:job];[self pumpDecodeJobs];
}
- (void)pumpDecodeJobs {
    if(self.decodingJob||!self.decodeJobs.count)return;
    WPBarrageDecodeJob *job=self.decodeJobs.firstObject;[self.decodeJobs removeObjectAtIndex:0];self.decodingJob=job;
    __weak typeof(self) weakSelf=self;
    dispatch_async(self.decodeQueue,^{@autoreleasepool {
        UIImage *input=job.cancelled?nil:job.image;
        UIImage *small=input?WPBarrageSmallImage(input):nil;job.image=nil;
        dispatch_async(dispatch_get_main_queue(),^{
            WPMessageBarrageController *strongSelf=weakSelf;if(!strongSelf)return;
            if(strongSelf.decodingJob==job)strongSelf.decodingJob=nil;
            if(!job.cancelled)[strongSelf acceptAvatar:small username:job.username generation:job.generation];
            [strongSelf pumpDecodeJobs];[strongSelf pumpAvatarWork];
        });
    }});
}
- (NSUInteger)avatarDemandSequence:(NSString *)username {
    NSUInteger sequence=0;
    for(WPBarrageBubble *bubble in self.bubbles)if(bubble.record&&!bubble.record.localPreview&&!bubble.actualAvatar&&[bubble.record.sender isEqual:username])sequence=MAX(sequence,bubble.record.sequence);
    if(self.flight.record&&!self.flight.record.localPreview&&!self.flight.actualAvatar&&[self.flight.record.sender isEqual:username])sequence=MAX(sequence,self.flight.record.sequence);
    return sequence;
}
- (WPBarrageAvatarState *)avatarStateForUsername:(NSString *)username create:(BOOL)create {
    WPBarrageAvatarState *state=self.avatarStates[username];
    if(!state&&create){state=[WPBarrageAvatarState new];self.avatarStates[username]=state;}
    if(!state)return nil;
    [self.avatarRequests removeObject:username];[self.avatarRequests addObject:username];
    while(self.avatarRequests.count>24){
        NSString *old=nil;
        for(NSString *candidate in self.avatarRequests)if(![self.avatarLoads containsObject:candidate]&&![self avatarDemandSequence:candidate]){old=candidate;break;}
        if(!old)for(NSString *candidate in self.avatarRequests)if(![self.avatarLoads containsObject:candidate]&&![candidate isEqual:username]){old=candidate;break;}
        if(!old)break;
        [self.avatarRequests removeObject:old];[self.avatarStates removeObjectForKey:old];
    }
    return state;
}
- (void)scheduleWorkTimer {
    if(self.temporarilySuspended||![self canDisplay]){[self.workTimer invalidate];self.workTimer=nil;return;}
    CFTimeInterval next=DBL_MAX,now=CACurrentMediaTime();
    for(WPBarrageRecord *record in self.pending)next=MIN(next,record.expiresAt);
    // One deadline per control also prevents a cancelled/missing delegate from
    // retaining its body forever. No display link or per-frame polling is used.
    for(WPBarrageBubble *bubble in self.bubbles)if(bubble.record){
        if(bubble.motionDuration>0)next=MIN(next,bubble.motionStart+bubble.motionDuration+.15);
        if(bubble.staticDeadline>0)next=MIN(next,bubble.staticDeadline);
    }
    // An in-flight completion will pump again. Do not keep waking a timer for
    // an already-due retry while both shared work slots are occupied.
    BOOL avatarSlotAvailable=now>=self.avatarCooldownUntil&&self.avatarLoads.count<2&&self.decodeJobs.count<2;
    for(NSString *username in self.avatarStates){
        WPBarrageAvatarState *state=self.avatarStates[username];NSUInteger demand=[self avatarDemandSequence:username];
        if(avatarSlotAvailable&&demand&&state.status==WPBarrageAvatarCooling&&(state.failures<4||demand>state.lastAttemptSequence))next=MIN(next,state.nextAttempt);
    }
    if(next==DBL_MAX){[self.workTimer invalidate];self.workTimer=nil;return;}
    NSDate *fire=[NSDate dateWithTimeIntervalSinceNow:MAX(.05,next-now)];
    if(self.workTimer){self.workTimer.fireDate=fire;return;}
    NSUInteger generation=self.generation;__weak typeof(self) weakSelf=self;
    self.workTimer=[[NSTimer alloc] initWithFireDate:fire interval:0 repeats:NO block:^(__unused NSTimer *timer){
        WPMessageBarrageController *strongSelf=weakSelf;if(!strongSelf||generation!=strongSelf.generation)return;
        strongSelf.workTimer=nil;[strongSelf pump];
    }];
    self.workTimer.tolerance=.05;[NSRunLoop.mainRunLoop addTimer:self.workTimer forMode:NSRunLoopCommonModes];
}
- (void)requestAvatar:(NSString *)username {
    if(!username.length||self.temporarilySuspended||CACurrentMediaTime()<self.avatarCooldownUntil||![self canDisplay])return;
    UIImage *cached=[self.avatars objectForKey:username];
    if(cached){[self acceptAvatar:cached username:username generation:self.generation];return;}
    if(self.avatarLoads.count>=2||self.decodeJobs.count>=2||[self.avatarLoads containsObject:username])return;
    WPBarrageAvatarState *state=[self avatarStateForUsername:username create:YES];
    CFTimeInterval now=CACurrentMediaTime();NSUInteger demand=[self avatarDemandSequence:username];
    if(!demand)return;
    // NSCache may evict a successfully decoded image at any time. A successful
    // history entry never becomes a permanent "requested" prohibition.
    if(state.status==WPBarrageAvatarReady){state.status=WPBarrageAvatarWaiting;state.failures=0;state.nextAttempt=0;}
    if(state.status==WPBarrageAvatarInFlight||now<state.nextAttempt)return;
    if(state.failures>=4){
        if(demand<=state.lastAttemptSequence)return;
        state.failures=0;
    }
    state.status=WPBarrageAvatarInFlight;state.lastAttemptSequence=demand;
    [self.avatarLoads addObject:username];NSUInteger generation=self.generation;
#if defined(WP_PREVIEW_HOST)
    if(self.previewAvatarProvider){UIImage *image=self.previewAvatarProvider(username);[self acceptAvatar:image username:username generation:generation];return;}
#endif
    __weak typeof(self) weakSelf=self;
    // Shared with sidebar and head avatar: one native/disk/network request per
    // contact. Cancelling this subscriber leaves other visible consumers alive.
    id token=WPRequestSharedChatAvatar(username,^(UIImage *image){
        WPMessageBarrageController *strongSelf=weakSelf;if(!strongSelf||generation!=strongSelf.generation)return;
        [strongSelf.localPreparations removeObjectForKey:username];
        [strongSelf acceptAvatar:image username:username generation:generation];
    });
    if(token&&[self.avatarLoads containsObject:username])self.localPreparations[username]=token;
}
@end
