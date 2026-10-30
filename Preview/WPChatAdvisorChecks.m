#import "WPChatAdvisorChecks.h"
#import "WPChatAdvisor.h"
#import "WPChatAdvisorPanel.h"
#import "WPCommon.h"
#import "WPRadialMenu.h"
#import "WPTapActions.h"

static NSString * const WPCAFixtureAdvice=@"{\"summary\":\"这句更像随口一说，不用过度解读，顺着接一句就好。\",\"strategy\":\"承接\","
    "\"intents\":[{\"label\":\"随口闲聊\",\"percent\":60},{\"label\":\"求回应求陪伴\",\"percent\":25},{\"label\":\"想确认你在不在乎\",\"percent\":15}],"
    "\"risk_level\":2,\"risk_label\":\"轻微\",\"reply_timing\":\"立刻回\",\"actions\":[\"轻松带过不深聊\"],\"replies\":[\"嗯嗯，我在呢\",\"怎么啦\",\"刚看到，你说\"]}";

@interface WPAdvisorFixtureWrap : NSObject
@property(nonatomic) unsigned int m_uiMessageType;
@property(nonatomic) unsigned int m_uiCreateTime;
@property(nonatomic,copy) NSString *m_nsContent;
@property(nonatomic,copy) NSString *m_nsFromUsr;
@property(nonatomic,copy) NSString *m_nsToUsr;
@property(nonatomic,copy) NSString *m_nsRealChatUsr;
@end
@implementation WPAdvisorFixtureWrap
@end
@interface WPAdvisorFixtureNode : NSObject
@property(nonatomic,strong) id m_msgWrap;
@end
@implementation WPAdvisorFixtureNode
@end

@interface WPAdvisorFixtureChatController : UIViewController
@property(nonatomic,copy) NSString *fixtureUsername;
@property(nonatomic,copy) NSArray *m_arrMessageNodeData;
@property(nonatomic) UITextView *topText;
@property(nonatomic) UITextView *inputText;
- (NSString *)getCurrentChatName;
@end
@implementation WPAdvisorFixtureChatController
- (NSString *)getCurrentChatName {return self.fixtureUsername;}
- (void)viewDidLoad {
    [super viewDidLoad];self.view.backgroundColor=UIColor.systemBackgroundColor;self.title=@"参谋夹具";
    self.topText=[[UITextView alloc] initWithFrame:CGRectMake(16,120,300,60)];self.topText.text=@"上方可编辑区域";
    self.inputText=[[UITextView alloc] initWithFrame:CGRectMake(16,0,300,36)];self.inputText.text=@"草稿";
    self.inputText.autoresizingMask=UIViewAutoresizingFlexibleTopMargin;
    [self.view addSubview:self.topText];[self.view addSubview:self.inputText];
}
- (void)viewDidLayoutSubviews {[super viewDidLayoutSubviews];self.inputText.frame=CGRectMake(16,self.view.bounds.size.height-90,self.view.bounds.size.width-32,36);}
@end

static WPAdvisorFixtureWrap *WPCAWrap(unsigned int type,NSString *from,NSString *to,NSString *content,unsigned int time) {
    WPAdvisorFixtureWrap *wrap=[WPAdvisorFixtureWrap new];wrap.m_uiMessageType=type;wrap.m_nsFromUsr=from;wrap.m_nsToUsr=to;wrap.m_nsContent=content;wrap.m_uiCreateTime=time;return wrap;
}
static id WPCANode(WPAdvisorFixtureWrap *wrap) {WPAdvisorFixtureNode *node=[WPAdvisorFixtureNode new];node.m_msgWrap=wrap;return node;}
static NSArray *WPCAPrivateHistory(void) {
    unsigned int t=1798000000;
    return @[WPCANode(WPCAWrap(1,@"wxid_partner",@"wxid_me",@"今天好累啊",t)),
             WPCAWrap(1,@"wxid_me",@"wxid_partner",@"辛苦啦，早点休息",t+60),
             WPCANode(WPCAWrap(10000,@"wxid_partner",@"wxid_me",@"系统提示",t+61)),
             WPCANode(WPCAWrap(1,@"wxid_other",@"wxid_me",@"别的会话",t+62)),
             WPCANode(WPCAWrap(3,@"wxid_partner",@"wxid_me",@"<img/>",t+120)),
             WPCANode(WPCAWrap(1,@"wxid_partner",@"wxid_me",@"你在干嘛",t+180))];
}
static NSArray *WPCAGroupHistory(void) {
    unsigned int t=1798000000;
    WPAdvisorFixtureWrap *a=WPCAWrap(1,@"123@chatroom",@"wxid_me",@"wxid_alice:\n周末去哪玩",t);
    WPAdvisorFixtureWrap *b=WPCAWrap(1,@"123@chatroom",@"wxid_me",@"wxid_bob:\n我都行",t+30);b.m_nsRealChatUsr=@"wxid_bob";
    WPAdvisorFixtureWrap *me=WPCAWrap(1,@"wxid_me",@"123@chatroom",@"去爬山？",t+60);
    WPAdvisorFixtureWrap *c=WPCAWrap(1,@"123@chatroom",@"wxid_me",@"wxid_alice:\n好啊",t+90);
    return @[WPCANode(a),WPCANode(b),WPCANode(me),WPCANode(c)];
}
static NSString *WPCABodyText(NSDictionary *body) {
    NSData *data=[NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    return data?[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]:@"";
}
static void WPCAWritePanelImage(UIWindow *window,WPChatAdvice *advice,UIUserInterfaceStyle style,NSString *name) {
    WPChatAdvisorPanel *panel=[[WPChatAdvisorPanel alloc] initWithFrame:CGRectZero];
    panel.overrideUserInterfaceStyle=style;
    UIView *backdrop=[[UIView alloc] initWithFrame:window.bounds];backdrop.backgroundColor=style==UIUserInterfaceStyleDark?UIColor.blackColor:[UIColor colorWithWhite:.93 alpha:1];
    backdrop.overrideUserInterfaceStyle=style;[window addSubview:backdrop];[backdrop addSubview:panel];
    [panel showAdvice:advice lineCount:5];[panel layoutInBounds:UIEdgeInsetsInsetRect(window.bounds,window.safeAreaInsets)];
    UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithBounds:backdrop.bounds];
    UIImage *image=[renderer imageWithActions:^(__unused UIGraphicsImageRendererContext *context){[backdrop drawViewHierarchyInRect:backdrop.bounds afterScreenUpdates:YES];}];
    [UIImagePNGRepresentation(image) writeToFile:[WPDataDirectory() stringByAppendingPathComponent:name] atomically:YES];
    [backdrop removeFromSuperview];
}

static NSMutableDictionary *WPCAOfflineChecks(UIWindow *window) {
    NSMutableDictionary *r=[NSMutableDictionary new];
    r[@"presetUnknownFallsBack"]=@([[WPChatAdvisorPreset presetWithIdentifier:@"missing"].identifier isEqualToString:WPChatAdvisorPreset.builtinPresets.firstObject.identifier]);
    r[@"presetCustomExists"]=@([[WPChatAdvisorPreset presetWithIdentifier:WPChatAdvisorCustomPresetIdentifier].identifier isEqualToString:WPChatAdvisorCustomPresetIdentifier]);

    NSString *savedBase=[WPPreferences() stringForKey:@"chatAdvisorBaseURL"];
    r[@"baseRejectsRemoteHTTP"]=@(![WPChatAdvisor setBaseURL:@"http://example.com/v1"]);
    r[@"baseRejectsQuery"]=@(![WPChatAdvisor setBaseURL:@"https://example.com/v1?key=1"]);
    r[@"baseAcceptsHTTPS"]=@([WPChatAdvisor setBaseURL:@"https://example.com/v1/"] && [WPChatAdvisor.baseURL isEqualToString:@"https://example.com/v1"]);
    r[@"baseAcceptsLoopbackHTTP"]=@([WPChatAdvisor setBaseURL:@"http://127.0.0.1:9/v1"]);
    r[@"baseEmptyRestoresDefault"]=@([WPChatAdvisor setBaseURL:@""] && [WPChatAdvisor.baseURL isEqualToString:WPChatAdvisorDefaultBaseURL]);
    if(savedBase)[WPPreferences() setObject:savedBase forKey:@"chatAdvisorBaseURL"];

    id savedContext=[WPPreferences() objectForKey:@"chatAdvisorContext"];
    [WPChatAdvisor setContextCount:2];BOOL low=WPChatAdvisor.contextCount==6;
    [WPChatAdvisor setContextCount:100];BOOL high=WPChatAdvisor.contextCount==40;
    r[@"contextCountClamped"]=@(low && high);
    if(savedContext)[WPPreferences() setObject:savedContext forKey:@"chatAdvisorContext"];else [WPPreferences() removeObjectForKey:@"chatAdvisorContext"];

    WPAdvisorFixtureChatController *chat=[WPAdvisorFixtureChatController new];chat.fixtureUsername=@"wxid_partner";chat.m_arrMessageNodeData=WPCAPrivateHistory();
    NSString *route=nil;
    NSArray<WPChatLine *> *lines=[WPChatAdvisor transcriptForChatController:chat username:@"wxid_partner" limit:20 route:&route];
    r[@"transcriptRouteNamed"]=@([route hasSuffix:@".m_arrMessageNodeData"]);
    r[@"transcriptSkipsSystemAndOtherChat"]=@(lines.count==4);
    r[@"transcriptChronological"]=@([lines.firstObject.text isEqualToString:@"今天好累啊"] && [lines.lastObject.text isEqualToString:@"你在干嘛"]);
    r[@"transcriptDirection"]=@(lines.count==4 && !lines[0].fromMe && lines[1].fromMe && !lines[3].fromMe);
    r[@"transcriptMediaPlaceholder"]=@(lines.count==4 && [lines[2].text isEqualToString:@"[图片]"]);
    NSArray<WPChatLine *> *limited=[WPChatAdvisor transcriptForChatController:chat username:@"wxid_partner" limit:2 route:NULL];
    r[@"transcriptLimitKeepsNewest"]=@(limited.count==2 && [limited.lastObject.text isEqualToString:@"你在干嘛"] && [limited.firstObject.text isEqualToString:@"[图片]"]);
    r[@"transcriptUnavailableIsNil"]=@([WPChatAdvisor transcriptForChatController:[UIViewController new] username:@"wxid_partner" limit:20 route:NULL]==nil);

    WPAdvisorFixtureChatController *group=[WPAdvisorFixtureChatController new];group.fixtureUsername=@"123@chatroom";group.m_arrMessageNodeData=WPCAGroupHistory();
    NSArray<WPChatLine *> *groupLines=[WPChatAdvisor transcriptForChatController:group username:@"123@chatroom" limit:20 route:NULL];
    r[@"groupPrefixStripped"]=@(groupLines.count==4 && [groupLines[0].text isEqualToString:@"周末去哪玩"] && [groupLines[0].speaker isEqualToString:@"wxid_alice"]);
    r[@"groupRealSenderPreferred"]=@(groupLines.count==4 && [groupLines[1].speaker isEqualToString:@"wxid_bob"]);
    r[@"groupOutgoingFromMe"]=@(groupLines.count==4 && groupLines[2].fromMe);

    WPChatAdvisorPreset *couple=[WPChatAdvisorPreset presetWithIdentifier:@"couple"];
    NSDictionary *body=[WPChatAdvisor requestBodyForLines:lines group:NO preset:couple customInstruction:@"对方是我女朋友" model:@"test/model"];
    NSString *text=WPCABodyText(body);
    r[@"bodyUsesModelAndJSONMode"]=@([body[@"model"] isEqual:@"test/model"] && [body[@"response_format"][@"type"] isEqual:@"json_object"] && [body[@"messages"] count]==2);
    r[@"bodyCarriesPresetAndCustom"]=@([text containsString:couple.title] && [text containsString:@"对方是我女朋友"]);
    r[@"bodyHasNoUsernames"]=@(![text containsString:@"wxid_"]);
    r[@"bodyAsksAboutPartnerLastLine"]=@([text containsString:@"请分析对方最后一条消息"]);
    NSString *groupText=WPCABodyText([WPChatAdvisor requestBodyForLines:groupLines group:YES preset:couple customInstruction:@"" model:@"m"]);
    r[@"groupBodyAliasesMembers"]=@([groupText containsString:@"成员1：周末去哪玩"] && [groupText containsString:@"成员2：我都行"] && [groupText containsString:@"成员1：好啊"] && ![groupText containsString:@"wxid_"]);
    NSArray *mine=[lines arrayByAddingObject:[WPChatLine lineFromMe:YES speaker:@"" text:@"在呢" date:nil]];
    r[@"bodyHandlesLastLineFromMe"]=@([WPCABodyText([WPChatAdvisor requestBodyForLines:mine group:NO preset:couple customInstruction:@"" model:@"m"]) containsString:@"最后一条是我发的"]);

    NSString *error=nil;
    NSString *wrapped=[NSString stringWithFormat:@"<think>先想一想</think>\n```json\n%@\n```",[WPCAFixtureAdvice stringByReplacingOccurrencesOfString:@"\"risk_level\":2" withString:@"\"risk_level\":15"]];
    WPChatAdvice *advice=[WPChatAdvice adviceFromModelContent:wrapped error:&error];
    r[@"parseFencedThinking"]=@(advice!=nil && advice.replies.count==3 && advice.intents.count==3 && [advice.strategy isEqualToString:@"承接"]);
    r[@"parseClampsRisk"]=@(advice.riskLevel==10);
    error=nil;
    r[@"parseRejectsMissingReplies"]=@([WPChatAdvice adviceFromModelContent:@"{\"summary\":\"x\",\"replies\":[]}" error:&error]==nil && error.length>0);
    r[@"parseRejectsProse"]=@([WPChatAdvice adviceFromModelContent:@"抱歉，我无法回答" error:NULL]==nil);
    r[@"parseCapsReplies"]=@([WPChatAdvice adviceFromModelContent:@"{\"replies\":[\"a\",\"b\",\"c\",\"d\"]}" error:NULL].replies.count==3);

    UIViewController *root=window.rootViewController;
    WPAdvisorFixtureChatController *input=[WPAdvisorFixtureChatController new];input.fixtureUsername=@"wxid_partner";
    input.view.frame=window.bounds;[root.view addSubview:input.view];[input.view layoutIfNeeded];
    BOOL filled=[WPChatAdvisor fillReply:@"嗯嗯，我在呢" intoChatController:input];
    r[@"fillTargetsBottomInput"]=@(filled && [input.inputText.text isEqualToString:@"嗯嗯，我在呢"] && [input.topText.text isEqualToString:@"上方可编辑区域"]);
    [input.inputText resignFirstResponder];[input.view removeFromSuperview];
    UIViewController *empty=[UIViewController new];empty.view.frame=window.bounds;[root.view addSubview:empty.view];
    r[@"fillWithoutInputFails"]=@(![WPChatAdvisor fillReply:@"x" intoChatController:empty]);
    [empty.view removeFromSuperview];

    WPTapAction savedDouble=WPConfiguredTapAction(YES);
    WPSetConfiguredTapAction(YES,WPTapActionChatAdvisor);
    r[@"tapActionRoundTrip"]=@(WPConfiguredTapAction(YES)==WPTapActionChatAdvisor);
    WPSetConfiguredTapAction(YES,savedDouble);

    BOOL savedEnabled=WPChatAdvisor.isEnabled;
    WPRadialMenuView *menu=[[WPRadialMenuView alloc] initWithFrame:window.bounds];[window addSubview:menu];
    [WPChatAdvisor setEnabled:NO];[menu showAroundPoint:CGPointMake(200,400) inBounds:window.bounds];
    NSUInteger hidden=[[menu valueForKey:@"actionButtons"] count];[menu cancel];
    r[@"menuHidesAdvisorWhenOff"]=@(hidden==4);
    [WPChatAdvisor setEnabled:savedEnabled];[menu removeFromSuperview];

    if(advice){
        WPChatAdvice *display=[WPChatAdvice adviceFromModelContent:WPCAFixtureAdvice error:NULL];
        WPCAWritePanelImage(window,display,UIUserInterfaceStyleLight,@"chat-advisor-panel-light.png");
        WPCAWritePanelImage(window,display,UIUserInterfaceStyleDark,@"chat-advisor-panel-dark.png");
    }
    return r;
}

static void WPCAWait(NSTimeInterval timeout,BOOL (^condition)(void),void (^done)(BOOL)) {
    if(condition()){done(YES);return;}
    if(timeout<=0){done(NO);return;}
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,200*NSEC_PER_MSEC),dispatch_get_main_queue(),^{WPCAWait(timeout-.2,condition,done);});
}
static UIButton *WPCAFindButton(UIView *view,NSString *identifier) {
    if([view isKindOfClass:UIButton.class] && [view.accessibilityIdentifier isEqualToString:identifier])return (UIButton *)view;
    for(UIView *child in view.subviews){UIButton *found=WPCAFindButton(child,identifier);if(found)return found;}
    return nil;
}

void WPChatAdvisorRunPreviewChecks(UIWindow *window,UIWindow *overlay,NSString *baseURL,void (^completion)(NSDictionary<NSString *,NSNumber *> *)) {
    NSMutableDictionary *results=WPCAOfflineChecks(window);
    if(!baseURL.length){completion(results);return;}
    // Network and overlay flow against the loopback mock in Tests/chat-advisor-mock-server.py.
    NSString *savedModel=[WPPreferences() stringForKey:@"chatAdvisorModel"];BOOL savedEnabled=WPChatAdvisor.isEnabled;
    results[@"mockBaseAccepted"]=@([WPChatAdvisor setBaseURL:baseURL]);
    results[@"keySaved"]=@([WPChatAdvisor saveAPIKey:@"test-key-123"] && WPChatAdvisor.hasAPIKey);
    [WPChatAdvisor setModel:@"deepseek-ai/DeepSeek-V3"];[WPChatAdvisor setEnabled:YES];
    WPRadialMenuView *menu=[[WPRadialMenuView alloc] initWithFrame:window.bounds];[window addSubview:menu];
    [menu showAroundPoint:CGPointMake(200,400) inBounds:window.bounds];
    results[@"menuShowsAdvisorWhenReady"]=@([[menu valueForKey:@"actionButtons"] count]==5);[menu cancel];[menu removeFromSuperview];
    NSArray<WPChatLine *> *lines=@[[WPChatLine lineFromMe:NO speaker:@"wxid_partner" text:@"你在干嘛" date:nil]];
    void (^finish)(void)=^{
        [WPChatAdvisor clearAPIKey];[WPChatAdvisor setBaseURL:@""];[WPChatAdvisor setModel:savedModel ?: @""];[WPChatAdvisor setEnabled:savedEnabled];
        completion(results);
    };
    [WPChatAdvisor analyzeLines:lines group:NO completion:^(WPChatAdvice *advice,NSString *error){
        results[@"networkAnalysisParsed"]=@(advice.replies.count==3 && [advice.replies[0] isEqualToString:@"嗯嗯，我在呢"] && !error);
        [WPChatAdvisor setModel:@"reject-json-mode"];
        [WPChatAdvisor analyzeLines:lines group:NO completion:^(WPChatAdvice *retried,NSString *retryError){
            results[@"retriesWithoutJSONMode"]=@(retried!=nil && !retryError);
            [WPChatAdvisor setModel:@"deepseek-ai/DeepSeek-V3"];
            [WPChatAdvisor testConnection:^(BOOL success,NSString *message){
                results[@"testConnectionFindsModel"]=@(success && [message containsString:@"DeepSeek-V3"]);
                [WPChatAdvisor saveAPIKey:@"wrong-key"];
                [WPChatAdvisor analyzeLines:lines group:NO completion:^(WPChatAdvice *denied,NSString *deniedError){
                    results[@"unauthorizedExplained"]=@(denied==nil && [deniedError containsString:@"API Key 无效"]);
                    [WPChatAdvisor saveAPIKey:@"test-key-123"];
                    UINavigationController *navigation=(id)window.rootViewController;
                    UIViewController *overlayRoot=overlay.rootViewController;
                    SEL open=NSSelectorFromString(@"openChatAdvisor");
                    if(![navigation isKindOfClass:UINavigationController.class] || ![overlayRoot respondsToSelector:open]){results[@"overlayFlowAvailable"]=@NO;finish();return;}
                    WPAdvisorFixtureChatController *chat=[WPAdvisorFixtureChatController new];chat.fixtureUsername=@"wxid_partner";chat.m_arrMessageNodeData=WPCAPrivateHistory();
                    [navigation pushViewController:chat animated:NO];
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,600*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
                        ((void (*)(id,SEL))[overlayRoot methodForSelector:open])(overlayRoot,open);
                        WPCAWait(8,^BOOL{return WPCAFindButton(overlayRoot.view,@"WPChatAdvisorReply1")!=nil;},^(BOOL shown){
                            results[@"overlayCardShowsReplies"]=@(shown);
                            UIView *panel=[overlayRoot valueForKey:@"advisorPanel"];
                            if(shown){
                                UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithBounds:window.bounds];
                                UIImage *image=[renderer imageWithActions:^(__unused UIGraphicsImageRendererContext *context){
                                    [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:YES];
                                    [panel drawViewHierarchyInRect:panel.frame afterScreenUpdates:YES];}];
                                [UIImagePNGRepresentation(image) writeToFile:[WPDataDirectory() stringByAppendingPathComponent:@"chat-advisor-overlay.png"] atomically:YES];
                            }
                            [WPCAFindButton(overlayRoot.view,@"WPChatAdvisorReply1") sendActionsForControlEvents:UIControlEventTouchUpInside];
                            results[@"overlayReplyFillsInput"]=@([chat.inputText.text isEqualToString:@"嗯嗯，我在呢"]);
                            results[@"overlayCardClosesAfterFill"]=@([overlayRoot valueForKey:@"advisorPanel"]==nil);
                            [chat.inputText resignFirstResponder];[navigation popToRootViewControllerAnimated:NO];
                            finish();
                        });
                    });
                }];
            }];
        }];
    }];
}
