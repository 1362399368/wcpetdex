#import <UIKit/UIKit.h>
#import "WPAdvisorReplyAction.h"

@interface WPAdvisorReplyMockChat : UIViewController
@property(nonatomic,strong) UITextView *composer;
@property(nonatomic,strong) UIButton *sendButton;
@property(nonatomic) NSUInteger sent;
@end
@implementation WPAdvisorReplyMockChat
- (NSString *)getCurrentChatName {return @"advisor-reply-fixture";}
- (void)viewDidLoad {
    [super viewDidLoad];self.view.backgroundColor=UIColor.whiteColor;
    self.composer=[[UITextView alloc] initWithFrame:CGRectMake(20,500,220,60)];[self.view addSubview:self.composer];
    self.sendButton=[UIButton buttonWithType:UIButtonTypeSystem];self.sendButton.frame=CGRectMake(260,500,80,60);
    [self.sendButton setTitle:@"发送" forState:UIControlStateNormal];[self.sendButton addTarget:self action:@selector(sentAction) forControlEvents:UIControlEventTouchUpInside];[self.view addSubview:self.sendButton];
}
- (void)sentAction {self.sent++;self.composer.text=@"";}
@end

NSDictionary *WPAdvisorReplyPreviewChecks(void) {
    UIWindow *window=[[UIWindow alloc] initWithFrame:CGRectMake(0,0,390,844)];
    WPAdvisorReplyMockChat *chat=[WPAdvisorReplyMockChat new];window.rootViewController=chat;window.hidden=NO;[window makeKeyAndVisible];[chat.view layoutIfNeeded];
    NSString *name=@"advisor-reply-fixture";
    chat.composer.text=@"existing draft";
    BOOL draft=WPAdvisorApplyReply(@"suggestion",name,chat,NO)==WPAdvisorReplyDraftPresent && [chat.composer.text isEqual:@"existing draft"];
    chat.composer.text=@"";
    BOOL wrong=WPAdvisorApplyReply(@"suggestion",@"someone-else",chat,YES)==WPAdvisorReplyWrongChat && !chat.sent && !chat.composer.text.length;
    BOOL fill=WPAdvisorApplyReply(@"suggestion",name,chat,NO)==WPAdvisorReplyFilled && [chat.composer.text isEqual:@"suggestion"] && !chat.sent;
    chat.composer.text=@"";
    BOOL send=WPAdvisorApplyReply(@"send me",name,chat,YES)==WPAdvisorReplySendTriggered && chat.sent==1 && !chat.composer.text.length;
    chat.sendButton.hidden=YES;
    BOOL fallback=WPAdvisorApplyReply(@"manual",name,chat,YES)==WPAdvisorReplySendUnavailable && chat.sent==1 && [chat.composer.text isEqual:@"manual"];
    window.hidden=YES;window.rootViewController=nil;
    return @{@"advisorReplyProtectsDraft":@(draft),@"advisorReplyRejectsWrongChat":@(wrong),@"advisorReplyTapFillsOnly":@(fill),@"advisorReplyHoldTriggersOnce":@(send),@"advisorReplyMissingSendKeepsText":@(fallback)};
}
