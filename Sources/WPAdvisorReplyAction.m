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

WPAdvisorReplyOutcome WPAdvisorApplyReply(NSString *reply,NSString *username,UIViewController *chat,BOOL send) {
    NSCAssert(NSThread.isMainThread,@"Chat input must be updated on main");
    if(!username.length || !chat.isViewLoaded || !chat.view.window || ![WPChatPresentationUsernameForController(chat) isEqualToString:username] || ![WPChatPresentationActiveUsernameInWindow(chat.view.window) isEqualToString:username])return WPAdvisorReplyWrongChat;
    NSString *text=[reply stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if(!text.length)return WPAdvisorReplyInputUnavailable;
    NSMutableArray *inputs=[NSMutableArray new],*buttons=[NSMutableArray new];
    WPAdvisorCollect(chat.view,inputs,buttons,0);
    UITextView *input=nil;CGFloat lowest=-CGFLOAT_MAX;
    for(UITextView *view in inputs){CGFloat bottom=CGRectGetMaxY([view convertRect:view.bounds toView:nil]);if(bottom>lowest){lowest=bottom;input=view;}}
    if(!input)return WPAdvisorReplyInputUnavailable;
    if(input.text.length || input.markedTextRange)return WPAdvisorReplyDraftPresent;
    [input becomeFirstResponder];[input insertText:text];
    if(![input.text isEqualToString:text])return WPAdvisorReplyInputUnavailable;
    if(!send)return WPAdvisorReplyFilled;
    // The native composer may create its Send button only after text is inserted.
    [chat.view layoutIfNeeded];[buttons removeAllObjects];[inputs removeAllObjects];WPAdvisorCollect(chat.view,inputs,buttons,0);
    if(buttons.count!=1 || ![WPChatPresentationUsernameForController(chat) isEqualToString:username] || ![WPChatPresentationActiveUsernameInWindow(chat.view.window) isEqualToString:username])return WPAdvisorReplySendUnavailable;
    UIButton *button=buttons.firstObject;
    [button sendActionsForControlEvents:UIControlEventTouchUpInside];
    return WPAdvisorReplySendTriggered;
}
