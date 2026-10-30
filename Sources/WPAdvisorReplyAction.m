#import "WPAdvisorReplyAction.h"
#import "WPChatPresentationState.h"

static void WPAdvisorCollect(UIView *view, NSMutableArray<UITextView *> *inputs, NSMutableArray<UIButton *> *sends, NSUInteger depth) {
    if(!view || view.hidden || view.alpha<.01 || depth>40 || !view.window)return;
    if([view isKindOfClass:UITextView.class] && ((UITextView *)view).editable && inputs.count<12)[inputs addObject:(UITextView *)view];
    if([view isKindOfClass:UIButton.class] && sends.count<12){
        UIButton *button=(UIButton *)view;
        NSString *title=button.currentTitle ?: button.titleLabel.text;
        if(button.enabled && button.userInteractionEnabled && ([title isEqualToString:@"发送"] || [title isEqualToString:@"Send"]))[sends addObject:button];
    }
    for(UIView *child in view.subviews)WPAdvisorCollect(child,inputs,sends,depth+1);
}

static BOOL WPAdvisorChatMatches(NSString *username,UIViewController *chat) {
    return username.length && chat.isViewLoaded && chat.view.window && [WPChatPresentationUsernameForController(chat) isEqualToString:username] && [WPChatPresentationActiveUsernameInWindow(chat.view.window) isEqualToString:username];
}
static UITextView *WPAdvisorLowestInput(NSArray<UITextView *> *inputs) {
    UITextView *input=nil;CGFloat lowest=-CGFLOAT_MAX;
    for(UITextView *view in inputs){CGFloat bottom=CGRectGetMaxY([view convertRect:view.bounds toView:nil]);if(bottom>lowest){lowest=bottom;input=view;}}
    return input;
}

WPAdvisorReplyOutcome WPAdvisorCheckReplyInput(NSString *username,UIViewController *chat) {
    if(!WPAdvisorChatMatches(username,chat))return WPAdvisorReplyWrongChat;
    NSMutableArray *inputs=[NSMutableArray new],*buttons=[NSMutableArray new];WPAdvisorCollect(chat.view,inputs,buttons,0);
    UITextView *input=WPAdvisorLowestInput(inputs);
    if(!input)return WPAdvisorReplyInputUnavailable;
    return input.text.length || input.markedTextRange?WPAdvisorReplyDraftPresent:WPAdvisorReplyFilled;
}

WPAdvisorReplyOutcome WPAdvisorApplyReply(NSString *reply,NSString *username,UIViewController *chat,BOOL send) {
    NSCAssert(NSThread.isMainThread,@"Chat input must be updated on main");
    if(!WPAdvisorChatMatches(username,chat))return WPAdvisorReplyWrongChat;
    NSString *text=[reply stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if(!text.length)return WPAdvisorReplyInputUnavailable;
    NSMutableArray *inputs=[NSMutableArray new],*buttons=[NSMutableArray new];
    WPAdvisorCollect(chat.view,inputs,buttons,0);
    UITextView *input=WPAdvisorLowestInput(inputs);
    if(!input)return WPAdvisorReplyInputUnavailable;
    if(input.text.length || input.markedTextRange)return WPAdvisorReplyDraftPresent;
    [input becomeFirstResponder];[input insertText:text];
    if(![input.text isEqualToString:text])return WPAdvisorReplyInputUnavailable;
    if(!send)return WPAdvisorReplyFilled;
    return WPAdvisorSendFilledReply(text,username,chat);
}

WPAdvisorReplyOutcome WPAdvisorSendFilledReply(NSString *reply,NSString *username,UIViewController *chat) {
    NSCAssert(NSThread.isMainThread,@"Chat input must be updated on main");
    if(!WPAdvisorChatMatches(username,chat))return WPAdvisorReplyWrongChat;
    NSMutableArray *inputs=[NSMutableArray new],*buttons=[NSMutableArray new];
    [chat.view layoutIfNeeded];WPAdvisorCollect(chat.view,inputs,buttons,0);
    UITextView *input=WPAdvisorLowestInput(inputs);
    if(!input || ![input.text isEqualToString:[reply stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]] || input.markedTextRange)return WPAdvisorReplyDraftPresent;
    if(buttons.count!=1)return WPAdvisorReplySendUnavailable;
    [buttons.firstObject sendActionsForControlEvents:UIControlEventTouchUpInside];
    return WPAdvisorReplySendTriggered;
}
