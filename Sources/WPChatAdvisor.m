#import "WPChatAdvisor.h"
#import "WPCommon.h"
#import "WPSessionEligibility.h"
#import "WPPartnerContact.h"
#import <Security/Security.h>

NSString * const WPChatAdvisorDefaultBaseURL=@"https://api.siliconflow.cn/v1";
NSString * const WPChatAdvisorDefaultModel=@"deepseek-ai/DeepSeek-V3";
NSString * const WPChatAdvisorCustomPresetIdentifier=@"custom";
static const NSUInteger WPCALineTextLimit=300;
BOOL WPChatAdvisorIsGroupUsername(NSString *username){
    if(![username isKindOfClass:NSString.class])return NO;
    NSString *lower=username.lowercaseString;
    return [lower hasSuffix:@"@chatroom"] || [lower hasSuffix:@"@im.chatroom"];
}

static NSString *WPCATrim(id value) {
    return [value isKindOfClass:NSString.class]?[value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]:@"";
}
static NSString *WPCAClip(NSString *value,NSUInteger limit) {
    if(value.length<=limit)return value;
    NSRange range=[value rangeOfComposedCharacterSequencesForRange:NSMakeRange(0,limit)];
    return [[value substringWithRange:range] stringByAppendingString:@"…"];
}

@interface WPChatAdvisorPreset ()
@property(nonatomic,copy,readwrite) NSString *identifier;
@property(nonatomic,copy,readwrite) NSString *title;
@property(nonatomic,copy,readwrite) NSString *summary;
@property(nonatomic,copy,readwrite) NSString *instruction;
@end
@implementation WPChatAdvisorPreset
+ (instancetype)presetWithIdentifier:(NSString *)identifier title:(NSString *)title summary:(NSString *)summary instruction:(NSString *)instruction {
    WPChatAdvisorPreset *preset=[self new];preset.identifier=identifier;preset.title=title;preset.summary=summary;preset.instruction=instruction;return preset;
}
+ (NSArray<WPChatAdvisorPreset *> *)builtinPresets {
    static NSArray *presets;static dispatch_once_t once;
    dispatch_once(&once,^{presets=@[
        [self presetWithIdentifier:@"couple" title:@"恋爱聊天" summary:@"恋人沟通，读情绪、给回应感"
                       instruction:@"对方是恋人。重点读出对方的情绪，以及想要的回应：陪伴、被在乎、被哄还是单纯分享。回复温柔自然、有回应感，不油腻、不说教、不敷衍。"],
        [self presetWithIdentifier:@"flirt" title:@"暧昧聊天" summary:@"暧昧互动，自然回应、不冒进"
                       instruction:@"对方是有好感或暧昧中的对象。结合聊天判断熟悉程度，自然回应，适度表达好感，不强行升级关系，不油腻，也不编造承诺。"],
        [self presetWithIdentifier:@"friend" title:@"朋友闲聊" summary:@"熟人闲聊，轻松接话"
                       instruction:@"对方是朋友或熟人，以日常闲聊为主。回复轻松、口语化，可以接梗，不过度解读，也不要太客气。"],
        [self presetWithIdentifier:@"work" title:@"职场沟通" summary:@"同事、上级、客户，分清派活和催进度"
                       instruction:@"对方是同事、上级或客户。先判断是派活、催进度、问情况、提意见还是闲聊。回复礼貌清楚，交代事实和下一步，不替我承诺聊天里没有的时间和结果。"],
        [self presetWithIdentifier:@"eq" title:@"高情商" summary:@"先接情绪再表达，拒绝留余地"
                       instruction:@"先接住对方的情绪或需求，再表达我的意思。需要拒绝时语气委婉，并给出替代方案。整体得体、不卑不亢。"],
        [self presetWithIdentifier:@"humor" title:@"幽默接梗" summary:@"机灵有梗，带点自嘲"
                       instruction:@"回复机灵、有梗，可以适度自嘲或调侃，让聊天更轻松。不冒犯、不刻薄，对方明显不开心时先收起玩笑。"],
        [self presetWithIdentifier:@"calm" title:@"冷静降温" summary:@"吵架或对方情绪激动时用"
                       instruction:@"对方可能在生气、抱怨或和我起争执。先降温，承认对方的感受，不争输赢、不翻旧账、不火上浇油。避免任何一句可能激化矛盾的话。"],
        [self presetWithIdentifier:WPChatAdvisorCustomPresetIdentifier title:@"自定义" summary:@"只按补充说明里的要求分析"
                       instruction:@""]];
    });
    return presets;
}
+ (WPChatAdvisorPreset *)presetWithIdentifier:(NSString *)identifier {
    for(WPChatAdvisorPreset *preset in self.builtinPresets)if([preset.identifier isEqualToString:identifier])return preset;
    return self.builtinPresets.firstObject;
}
@end

@implementation WPChatLine
+ (instancetype)lineFromMe:(BOOL)fromMe speaker:(NSString *)speaker text:(NSString *)text date:(NSDate *)date {
    WPChatLine *line=[self new];line.fromMe=fromMe;line.speaker=speaker ?: @"";line.text=text ?: @"";line.date=date;return line;
}
@end

@implementation WPChatAdvice
+ (instancetype)adviceFromModelContent:(NSString *)content error:(NSString **)error {
    NSString *text=WPCATrim(content);
    // Reasoning models may prepend <think>…</think>; fences are common too.
    NSRange think=[text rangeOfString:@"</think>" options:NSBackwardsSearch];
    if(think.location!=NSNotFound)text=[text substringFromIndex:NSMaxRange(think)];
    NSRange open=[text rangeOfString:@"{"],close=[text rangeOfString:@"}" options:NSBackwardsSearch];
    if(open.location==NSNotFound || close.location==NSNotFound || close.location<open.location){if(error)*error=@"模型没有返回分析结果，可以换个模型再试";return nil;}
    NSData *data=[[text substringWithRange:NSMakeRange(open.location,NSMaxRange(close)-open.location)] dataUsingEncoding:NSUTF8StringEncoding];
    id json=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
    if(![json isKindOfClass:NSDictionary.class]){if(error)*error=@"模型返回的内容无法解析，可以换个模型再试";return nil;}
    NSMutableArray<NSString *> *replies=[NSMutableArray new];
    for(id reply in [json[@"replies"] isKindOfClass:NSArray.class]?json[@"replies"]:@[]){
        NSString *value=WPCATrim([reply isKindOfClass:NSDictionary.class]?reply[@"text"]:reply);
        if(value.length && replies.count<3)[replies addObject:WPCAClip(value,120)];
    }
    if(!replies.count){if(error)*error=@"模型没有给出建议回复，可以换个模型再试";return nil;}
    WPChatAdvice *advice=[self new];advice.replies=replies;
    advice.summary=WPCAClip(WPCATrim(json[@"summary"]),200);
    advice.strategy=WPCAClip(WPCATrim(json[@"strategy"]),20);
    advice.riskLabel=WPCAClip(WPCATrim(json[@"risk_label"]),10);
    advice.replyTiming=WPCAClip(WPCATrim(json[@"reply_timing"]),10);
    NSNumber *risk=[json[@"risk_level"] isKindOfClass:NSNumber.class]?json[@"risk_level"]:([json[@"risk_level"] isKindOfClass:NSString.class]?@([json[@"risk_level"] integerValue]):nil);
    advice.riskLevel=risk?MAX(0,MIN(10,risk.integerValue)):-1;
    NSMutableArray *intents=[NSMutableArray new];
    for(id item in [json[@"intents"] isKindOfClass:NSArray.class]?json[@"intents"]:@[]){
        if(![item isKindOfClass:NSDictionary.class] || intents.count>=4)continue;
        NSString *label=WPCAClip(WPCATrim(item[@"label"]),16);id percent=item[@"percent"];
        if(label.length && ([percent isKindOfClass:NSNumber.class] || [percent isKindOfClass:NSString.class]))
            [intents addObject:@{@"label":label,@"percent":@(MAX(0,MIN(100,[percent integerValue])))}];
    }
    advice.intents=intents;
    NSMutableArray *actions=[NSMutableArray new];
    for(id action in [json[@"actions"] isKindOfClass:NSArray.class]?json[@"actions"]:@[]){NSString *value=WPCATrim(action);if(value.length && actions.count<3)[actions addObject:WPCAClip(value,40)];}
    advice.actions=actions;
    return advice;
}
@end

#pragma mark - Advisor

static NSUInteger WPCAAnalyses,WPCAFailures,WPCALastLineCount;
static NSInteger WPCALastHTTPStatus;
static NSString *WPCALastRoute,*WPCALastFailure;

#ifdef WP_PREVIEW_HOST
// The ad-hoc signed preview host has no keychain entitlement; keep the key in memory there.
static NSString *WPCAPreviewKey;
#endif
static NSDictionary *WPCAKeyQuery(void) {
    return @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,(__bridge id)kSecAttrService:@"dev.zhour.wechatpet.single.chat-advisor",(__bridge id)kSecAttrAccount:@"api-key"};
}
static NSString *WPCALoadKey(void) {
    NSMutableDictionary *query=WPCAKeyQuery().mutableCopy;query[(__bridge id)kSecReturnData]=@YES;query[(__bridge id)kSecMatchLimit]=(__bridge id)kSecMatchLimitOne;
    CFTypeRef result=NULL;
    if(SecItemCopyMatching((__bridge CFDictionaryRef)query,&result)!=errSecSuccess){
#ifdef WP_PREVIEW_HOST
        return WPCAPreviewKey;
#endif
        return nil;
    }
    NSString *key=[[NSString alloc] initWithData:CFBridgingRelease(result) encoding:NSUTF8StringEncoding];
    return key.length?key:nil;
}
static NSURLSession *WPCASession(void) {
    static NSURLSession *session;static dispatch_once_t once;
    dispatch_once(&once,^{
        NSURLSessionConfiguration *configuration=NSURLSessionConfiguration.ephemeralSessionConfiguration;
        configuration.timeoutIntervalForRequest=60;configuration.timeoutIntervalForResource=90;
        configuration.URLCache=nil;configuration.HTTPCookieStorage=nil;
#ifdef WP_PREVIEW_HOST
        Class mock=NSClassFromString(@"WPAdvisorMockURLProtocol");
        if(mock)configuration.protocolClasses=@[mock];
#endif
        session=[NSURLSession sessionWithConfiguration:configuration];
    });
    return session;
}
static BOOL WPCAAllowedURL(NSURL *url) {
    NSString *scheme=url.scheme.lowercaseString,*host=url.host.lowercaseString;
    if(!host.length || url.user || url.password || url.query || url.fragment)return NO;
    if([scheme isEqualToString:@"https"])return YES;
    return [scheme isEqualToString:@"http"] && [@[@"127.0.0.1",@"localhost",@"::1"] containsObject:host];
}
// DeepSeek's account console is not its API endpoint. Only rewrite the exact
// official console root; never redirect an arbitrary host carrying a key.
static NSString *WPCANormalizedBase(NSString *value) {
    NSString *base=WPCATrim(value);
    while([base hasSuffix:@"/"])base=[base substringToIndex:base.length-1];
    NSURL *url=[NSURL URLWithString:base];
    if([url.scheme.lowercaseString isEqual:@"https"] && [url.host.lowercaseString isEqual:@"platform.deepseek.com"] &&
       !url.user && !url.password && !url.port && !url.query && !url.fragment && (!url.path.length || [url.path isEqual:@"/"]))
        return @"https://api.deepseek.com";
    return base;
}
static BOOL WPCAIsDeepSeek(NSString *base) {
    NSURL *url=[NSURL URLWithString:base];
    return [url.scheme.lowercaseString isEqual:@"https"] && [url.host.lowercaseString isEqual:@"api.deepseek.com"] && !url.port;
}
static NSString *WPCAHTTPError(NSInteger status,NSData *data) {
    NSString *detail=nil;
    id json=data.length?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
    if([json isKindOfClass:NSDictionary.class]){
        id message=json[@"message"];
        if([json[@"error"] isKindOfClass:NSDictionary.class])message=json[@"error"][@"message"];
        else if([json[@"error"] isKindOfClass:NSString.class])message=json[@"error"];
        if([message isKindOfClass:NSString.class] && [message length])detail=WPCAClip(message,80);
    }
    NSString *reason=status==401?@"API Key 无效或已过期，请确认密钥与服务商对应":status==402?@"模型服务余额不足，请检查账户余额":status==403?@"没有权限使用这个模型，或账户未实名":status==404?@"模型或接口地址不存在，请检查模型名称":
        status==429?@"请求太频繁或额度不足":status>=500?@"模型服务暂时不可用，请稍后再试":[NSString stringWithFormat:@"请求失败（HTTP %ld）",(long)status];
    return detail?[NSString stringWithFormat:@"%@：%@",reason,detail]:reason;
}
static NSString *WPCANetworkError(NSError *error) {
    if([error.domain isEqualToString:NSURLErrorDomain]){
        if(error.code==NSURLErrorTimedOut)return @"请求超时，可以换个更快的模型再试";
        if(error.code==NSURLErrorNotConnectedToInternet || error.code==NSURLErrorNetworkConnectionLost)return @"网络未连接";
        if(error.code==NSURLErrorAppTransportSecurityRequiresSecureConnection)return @"接口地址必须使用 https";
    }
    return @"无法连接模型服务，请检查网络和接口地址";
}

@interface WPChatAdvisorRequest ()
@property(nonatomic,strong) NSURLSessionTask *task;
@property(nonatomic) BOOL cancelled;
@end
@implementation WPChatAdvisorRequest
- (void)cancel {
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{[self cancel];});return;}
    if(self.cancelled)return;self.cancelled=YES;[self.task cancel];self.task=nil;
}
@end

@implementation WPChatAdvisor
+ (BOOL)isEnabled {return [WPPreferences() boolForKey:@"chatAdvisorEnabled"];}
+ (void)setEnabled:(BOOL)enabled {[WPPreferences() setBool:enabled forKey:@"chatAdvisorEnabled"];}
+ (BOOL)isReady {return self.isEnabled && self.hasAPIKey;}
+ (NSString *)baseURL {
    NSString *value=WPCANormalizedBase([WPPreferences() stringForKey:@"chatAdvisorBaseURL"]);
    return value.length?value:WPChatAdvisorDefaultBaseURL;
}
+ (BOOL)setBaseURL:(NSString *)value {
    NSString *trimmed=WPCANormalizedBase(value);
    if(!trimmed.length){[WPPreferences() removeObjectForKey:@"chatAdvisorBaseURL"];return YES;}
    NSURL *url=[NSURL URLWithString:trimmed];
    if(!url || !WPCAAllowedURL(url))return NO;
    [WPPreferences() setObject:trimmed forKey:@"chatAdvisorBaseURL"];return YES;
}
+ (NSString *)model {
    NSString *value=WPCATrim([WPPreferences() stringForKey:@"chatAdvisorModel"]);
    if(WPCAIsDeepSeek(self.baseURL) && (!value.length || [value isEqualToString:WPChatAdvisorDefaultModel]))return @"deepseek-flash";
    return value.length?value:WPChatAdvisorDefaultModel;
}
+ (void)setModel:(NSString *)model {
    NSString *value=WPCATrim(model);
    if(value.length && value.length<=128)[WPPreferences() setObject:value forKey:@"chatAdvisorModel"];
    else [WPPreferences() removeObjectForKey:@"chatAdvisorModel"];
}
+ (WPChatAdvisorPreset *)currentPreset {return [WPChatAdvisorPreset presetWithIdentifier:[WPPreferences() stringForKey:@"chatAdvisorPreset"]];}
+ (void)setPresetIdentifier:(NSString *)identifier {[WPPreferences() setObject:[WPChatAdvisorPreset presetWithIdentifier:identifier].identifier forKey:@"chatAdvisorPreset"];}
+ (NSString *)customInstruction {return WPCATrim([WPPreferences() stringForKey:@"chatAdvisorCustom"]);}
+ (void)setCustomInstruction:(NSString *)instruction {
    NSString *value=WPCAClip(WPCATrim(instruction),300);
    if(value.length)[WPPreferences() setObject:value forKey:@"chatAdvisorCustom"];else [WPPreferences() removeObjectForKey:@"chatAdvisorCustom"];
}
+ (NSUInteger)contextCount {
    NSInteger value=[WPPreferences() integerForKey:@"chatAdvisorContext"];
    return value?(NSUInteger)MAX(6,MIN(40,value)):20;
}
+ (void)setContextCount:(NSUInteger)count {[WPPreferences() setInteger:(NSInteger)MAX(6,MIN(40,count)) forKey:@"chatAdvisorContext"];}
+ (BOOL)hasAPIKey {return WPCALoadKey().length>0;}
+ (BOOL)saveAPIKey:(NSString *)key {
    NSString *value=WPCATrim(key);
    if(!value.length || value.length>512)return NO;
    NSData *data=[value dataUsingEncoding:NSUTF8StringEncoding];
    OSStatus status=SecItemUpdate((__bridge CFDictionaryRef)WPCAKeyQuery(),(__bridge CFDictionaryRef)@{(__bridge id)kSecValueData:data});
    if(status==errSecItemNotFound){
        NSMutableDictionary *entry=WPCAKeyQuery().mutableCopy;entry[(__bridge id)kSecValueData]=data;
        entry[(__bridge id)kSecAttrAccessible]=(__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
        status=SecItemAdd((__bridge CFDictionaryRef)entry,NULL);
    }
#ifdef WP_PREVIEW_HOST
    if(status==errSecMissingEntitlement){WPCAPreviewKey=value;return YES;}
#endif
    return status==errSecSuccess;
}
+ (void)clearAPIKey {
    SecItemDelete((__bridge CFDictionaryRef)WPCAKeyQuery());
#ifdef WP_PREVIEW_HOST
    WPCAPreviewKey=nil;
#endif
}

#pragma mark Transcript

+ (NSArray *)messageListFromTarget:(id)target route:(NSString **)route {
    for(NSString *key in @[@"GetMessagesWrapArray",@"getMessagesWrapArray",@"m_arrMessageNodeData",@"messageNodeDataArray",@"m_arrMessages",@"m_messageWrapArray"]){
        id list=WPSEReadObject(target,@[key]);
        if([list isKindOfClass:NSArray.class] && [list count]){if(route)*route=[NSString stringWithFormat:@"%@.%@",NSStringFromClass([target class]),key];return list;}
    }
    return nil;
}
+ (NSArray<WPChatLine *> *)transcriptForChatController:(UIViewController *)controller username:(NSString *)username limit:(NSUInteger)limit route:(NSString **)route {
    if(route)*route=@"none";
    if(!controller || !username.length)return nil;
    // The visible controller first, then its direct children and the current
    // logic controller. Only messages already loaded for display are read.
    NSMutableArray *targets=[NSMutableArray arrayWithObject:controller];
    [targets addObjectsFromArray:[controller.childViewControllers subarrayWithRange:NSMakeRange(0,MIN((NSUInteger)6,controller.childViewControllers.count))]];
    id logic=WPSEReadObject(WPWeChatService(@"MMMsgLogicManager"),@[@"GetCurrentLogicController"]);
    if(logic)[targets addObject:logic];
    NSArray *list=nil;NSString *found=nil;
    for(id target in targets){list=[self messageListFromTarget:target route:&found];if(list)break;}
    if(!list){WPCALastRoute=@"unavailable";return nil;}
    if(route)*route=found;WPCALastRoute=found;
    BOOL group=WPChatAdvisorIsGroupUsername(username);
    NSMutableArray<WPChatLine *> *lines=[NSMutableArray new];
    NSUInteger scanned=0;
    for(id item in list.reverseObjectEnumerator){
        if(lines.count>=limit || scanned++>=limit*4+40)break;
        id wrap=WPSEReadNumber(item,@[@"m_uiMessageType"])?item:WPSEReadObject(item,@[@"m_msgWrap",@"msgWrap",@"messageWrap"]);
        NSNumber *type=WPSEReadNumber(wrap,@[@"m_uiMessageType"]);
        NSString *from=WPCATrim(WPSEReadObject(wrap,@[@"m_nsFromUsr"])),*to=WPCATrim(WPSEReadObject(wrap,@[@"m_nsToUsr"]));
        if(!type || !from.length || (![from isEqualToString:username] && ![to isEqualToString:username]))continue;
        NSString *text=nil;
        switch(type.unsignedIntegerValue){
            case 1:text=WPCATrim(WPSEReadObject(wrap,@[@"m_nsContent"]));break;
            case 3:text=@"[图片]";break;
            case 34:text=@"[语音]";break;
            case 42:text=@"[名片]";break;
            case 43:text=@"[视频]";break;
            case 47:text=@"[表情]";break;
            case 48:text=@"[位置]";break;
            case 49:text=@"[链接或文件]";break;
            case 50:text=@"[通话]";break;
            default:continue;
        }
        if(!text.length)continue;
        BOOL fromMe=![from isEqualToString:username];
        NSString *sender=fromMe?@"":(group?WPCATrim(WPSEReadObject(wrap,@[@"m_nsRealChatUsr"])):username);
        if(group && !fromMe && type.unsignedIntegerValue==1){
            // Received group text carries a "username:\n" prefix in the body.
            NSRange split=[text rangeOfString:@":\n"];
            if(split.location!=NSNotFound && split.location>0 && split.location<=80){
                NSString *prefix=[text substringToIndex:split.location];
                if([prefix rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location==NSNotFound){
                    if(!sender.length)sender=prefix;
                    text=WPCATrim([text substringFromIndex:NSMaxRange(split)]);
                }
            }
        }
        NSNumber *created=WPSEReadNumber(wrap,@[@"m_uiCreateTime"]);
        [lines insertObject:[WPChatLine lineFromMe:fromMe speaker:sender text:WPCAClip(text,WPCALineTextLimit) date:created.doubleValue>0?[NSDate dateWithTimeIntervalSince1970:created.doubleValue]:nil] atIndex:0];
    }
    WPCALastLineCount=lines.count;
    return lines;
}

#pragma mark Request

+ (NSString *)systemPromptForPreset:(WPChatAdvisorPreset *)preset custom:(NSString *)custom {
    NSMutableString *prompt=[NSMutableString stringWithString:@"你是微信聊天参谋，帮我读懂对方的话，并想好怎么回。\n"];
    if(preset.instruction.length)[prompt appendFormat:@"场景：%@。%@\n",preset.title,preset.instruction];
    if(custom.length)[prompt appendFormat:@"我的补充说明：%@\n",custom];
    [prompt appendString:@"分析要求：\n"
        "- 以对方最后一条消息为重点，结合上文判断真实意图，不要过度解读。\n"
        "- intents 给出 2～4 种可能的真实意图，percent 是整数，总和为 100，按概率从高到低排列。\n"
        "- risk_level 是 0～10 的整数，表示回得不好会引起误会或让关系变差的风险；risk_label 取「轻微」「一般」「较高」「很高」之一。\n"
        "- reply_timing 取「立刻回」「稍后回」「可以不回」之一。\n"
        "- strategy 用 2～6 个字概括本轮回应策略，例如「承接」「安抚」「推进」「澄清」「降温」「委婉拒绝」。\n"
        "- actions 给出 1～3 条最佳动作，每条不超过 20 字。\n"
        "- replies 给出正好 3 条可以直接发出去的回复，每条不超过 40 字，像微信里打字；不要编号、引号或风格标签；不编造聊天里没有的事实、时间和承诺。\n"
        "只输出一个 JSON 对象，不要输出任何其他文字。格式：\n"
        "{\"summary\":\"一句话说明对方的意思和该怎么接\",\"strategy\":\"承接\",\"intents\":[{\"label\":\"随口闲聊\",\"percent\":60}],"
        "\"risk_level\":2,\"risk_label\":\"轻微\",\"reply_timing\":\"立刻回\",\"actions\":[\"轻松带过不深聊\"],\"replies\":[\"…\",\"…\",\"…\"]}"];
    return prompt;
}
+ (NSString *)transcriptTextForLines:(NSArray<WPChatLine *> *)lines group:(BOOL)group {
    NSDateFormatter *format=[NSDateFormatter new];format.locale=[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];format.dateFormat=@"MM-dd HH:mm";
    NSMutableDictionary<NSString *,NSString *> *aliases=[NSMutableDictionary new];
    NSMutableString *text=[NSMutableString stringWithFormat:@"这是一个%@，以下是最近的聊天记录，按时间先后排列：\n",group?@"群聊":@"私聊"];
    for(WPChatLine *line in lines){
        NSString *name=@"我";
        if(!line.fromMe){
            if(group){
                NSString *key=line.speaker.length?line.speaker:@"?";
                if(!aliases[key])aliases[key]=[NSString stringWithFormat:@"成员%lu",(unsigned long)aliases.count+1];
                name=aliases[key];
            }else name=@"对方";
        }
        if(line.date)[text appendFormat:@"[%@] ",[format stringFromDate:line.date]];
        [text appendFormat:@"%@：%@\n",name,[line.text stringByReplacingOccurrencesOfString:@"\n" withString:@" "]];
    }
    [text appendString:lines.lastObject.fromMe?@"最后一条是我发的。请分析当前局面，replies 给出我接下来可以补充或推进的话。":@"请分析对方最后一条消息，给出建议回复。"];
    return text;
}
+ (NSDictionary *)requestBodyForLines:(NSArray<WPChatLine *> *)lines group:(BOOL)group preset:(WPChatAdvisorPreset *)preset customInstruction:(NSString *)custom model:(NSString *)model {
    return @{@"model":model,@"stream":@NO,@"temperature":@0.7,@"max_tokens":@1024,@"response_format":@{@"type":@"json_object"},
             @"messages":@[@{@"role":@"system",@"content":[self systemPromptForPreset:preset custom:custom]},
                           @{@"role":@"user",@"content":[self transcriptTextForLines:lines group:group]}]};
}
+ (NSURL *)endpoint:(NSString *)path {
    NSString *base=self.baseURL;while([base hasSuffix:@"/"])base=[base substringToIndex:base.length-1];
    NSURL *url=[NSURL URLWithString:[base stringByAppendingString:path]];
    NSURL *check=[NSURL URLWithString:base];
    return url && check && WPCAAllowedURL(check)?url:nil;
}
+ (void)postBody:(NSDictionary *)body allowRetry:(BOOL)allowRetry requestToken:(WPChatAdvisorRequest *)token completion:(void (^)(NSString *content,NSString *error))completion {
    if(token.cancelled)return;
    NSString *key=WPCALoadKey();NSURL *url=[self endpoint:@"/chat/completions"];
    if(!key.length){completion(nil,@"请先在聊天参谋设置里填写 API Key");return;}
    if(!url){completion(nil,@"接口地址无效，请使用 https 地址");return;}
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:url];request.HTTPMethod=@"POST";
    [request setValue:[@"Bearer " stringByAppendingString:key] forHTTPHeaderField:@"Authorization"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    request.HTTPBody=[NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    NSURLSessionDataTask *task=[WPCASession() dataTaskWithRequest:request completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){
        NSInteger status=[response isKindOfClass:NSHTTPURLResponse.class]?((NSHTTPURLResponse *)response).statusCode:0;
        dispatch_async(dispatch_get_main_queue(),^{
            token.task=nil;if(token.cancelled)return;
            WPCALastHTTPStatus=status;
            if(error){completion(nil,WPCANetworkError(error));return;}
            // Some compatible models reject JSON mode; retry once without it.
            if(status==400 && allowRetry && body[@"response_format"]){
                NSMutableDictionary *plain=body.mutableCopy;[plain removeObjectForKey:@"response_format"];
                [self postBody:plain allowRetry:NO requestToken:token completion:completion];return;
            }
            if(status<200 || status>=300){completion(nil,WPCAHTTPError(status,data));return;}
            id json=data.length?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
            id choices=[json isKindOfClass:NSDictionary.class]?json[@"choices"]:nil;
            id message=[choices isKindOfClass:NSArray.class] && [choices count] && [choices[0] isKindOfClass:NSDictionary.class]?choices[0][@"message"]:nil;
            id content=[message isKindOfClass:NSDictionary.class]?message[@"content"]:nil;
            if(![content isKindOfClass:NSString.class] || ![content length]){completion(nil,@"模型没有返回内容，可以换个模型再试");return;}
            completion(content,nil);
        });
    }];token.task=task;[task resume];
}
+ (void)analyzeLines:(NSArray<WPChatLine *> *)lines group:(BOOL)group completion:(void (^)(WPChatAdvice *,NSString *))completion {
    [self startAnalysisOfLines:lines group:group completion:completion];
}
+ (WPChatAdvisorRequest *)startAnalysisOfLines:(NSArray<WPChatLine *> *)lines group:(BOOL)group completion:(void (^)(WPChatAdvice *,NSString *))completion {
    return [self startAnalysisOfLines:lines group:group preset:self.currentPreset customInstruction:self.customInstruction completion:completion];
}
+ (WPChatAdvisorRequest *)startAnalysisOfLines:(NSArray<WPChatLine *> *)lines group:(BOOL)group preset:(WPChatAdvisorPreset *)preset customInstruction:(NSString *)custom completion:(void (^)(WPChatAdvice *,NSString *))completion {
    NSAssert(NSThread.isMainThread,@"Start advisor analysis on main thread");
    WPChatAdvisorRequest *token=[WPChatAdvisorRequest new];
    if(!lines.count){completion(nil,@"当前聊天没有可分析的文字消息");return token;}
    WPCAAnalyses++;
    NSMutableDictionary *body=[[self requestBodyForLines:lines group:group preset:preset customInstruction:custom model:self.model] mutableCopy];
    // DeepSeek's thinking mode is on by default; this brief JSON task needs
    // the output budget for the answer rather than hidden reasoning.
    if(WPCAIsDeepSeek(self.baseURL))body[@"thinking"]=@{@"type":@"disabled"};
    [self postBody:body allowRetry:YES requestToken:token completion:^(NSString *content,NSString *error){
        NSString *parseError=nil;WPChatAdvice *advice=content?[WPChatAdvice adviceFromModelContent:content error:&parseError]:nil;
        if(!advice){WPCAFailures++;WPCALastFailure=error?@"request":@"parse";completion(nil,error ?: parseError);return;}
        WPCALastFailure=nil;completion(advice,nil);
    }];
    return token;
}
+ (void)fetchModels:(void (^)(NSArray<NSString *> *,NSString *))completion {
    NSURL *base=[NSURL URLWithString:self.baseURL];
    NSString *path=[base.host.lowercaseString isEqual:@"api.siliconflow.cn"]?@"/models?type=text&sub_type=chat":@"/models";
    NSString *key=WPCALoadKey();NSURL *url=[self endpoint:path];
    if(!key.length){completion(nil,@"请先保存 API Key");return;}
    if(!url){completion(nil,@"接口地址无效，请使用 https 地址");return;}
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:url];
    [request setValue:[@"Bearer " stringByAppendingString:key] forHTTPHeaderField:@"Authorization"];
    [[WPCASession() dataTaskWithRequest:request completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){
        NSInteger status=[response isKindOfClass:NSHTTPURLResponse.class]?((NSHTTPURLResponse *)response).statusCode:0;
        dispatch_async(dispatch_get_main_queue(),^{
            if(error){completion(nil,WPCANetworkError(error));return;}
            if(status<200 || status>=300){completion(nil,WPCAHTTPError(status,data));return;}
            id json=data.length?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
            id items=[json isKindOfClass:NSDictionary.class]?json[@"data"]:nil;
            NSMutableOrderedSet *models=[NSMutableOrderedSet new];
            for(id item in [items isKindOfClass:NSArray.class]?items:@[])
                if([item isKindOfClass:NSDictionary.class] && [item[@"id"] isKindOfClass:NSString.class] && [item[@"id"] length])[models addObject:item[@"id"]];
            if(!models.count){completion(nil,@"没有获取到可用模型");return;}
            completion([models.array sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)],nil);
        });
    }] resume];
}
+ (void)testConnection:(void (^)(BOOL,NSString *))completion {
    NSString *model=self.model;
    [self fetchModels:^(NSArray<NSString *> *models,NSString *error){
        if(!models){completion(NO,error);return;}
        if([models containsObject:model])completion(YES,[NSString stringWithFormat:@"连接成功，模型列表包含 %@。实际对话还需账户有可用额度。",model]);
        else completion(NO,[NSString stringWithFormat:@"连接成功，但模型列表里没有 %@，请重新选择模型",model]);
    }];
}

#pragma mark Input

+ (void)collectTextViews:(UIView *)view into:(NSMutableArray<UITextView *> *)result depth:(NSUInteger)depth {
    if(!view || view.hidden || view.alpha<.01 || depth>40 || result.count>=8)return;
    if([view isKindOfClass:UITextView.class] && ((UITextView *)view).isEditable && view.window){[result addObject:(UITextView *)view];return;}
    for(UIView *child in view.subviews)[self collectTextViews:child into:result depth:depth+1];
}
+ (BOOL)fillReply:(NSString *)text intoChatController:(UIViewController *)controller {
    NSString *reply=WPCATrim(text);
    if(!reply.length || !controller.isViewLoaded)return NO;
    NSMutableArray<UITextView *> *views=[NSMutableArray new];
    [self collectTextViews:controller.view into:views depth:0];
    // The chat's composer is the lowest editable text view on screen.
    UITextView *input=nil;CGFloat lowest=-CGFLOAT_MAX;
    for(UITextView *view in views){CGFloat bottom=CGRectGetMaxY([view convertRect:view.bounds toView:nil]);if(bottom>lowest){lowest=bottom;input=view;}}
    if(!input)return NO;
    [input becomeFirstResponder];
    // insertText: follows the keyboard path, so WeChat's delegate sees the edit.
    input.selectedRange=NSMakeRange(0,input.text.length);
    [input insertText:reply];
    return [input.text containsString:reply];
}
+ (NSDictionary<NSString *,id> *)diagnostics {
    return @{@"enabled":@(self.isEnabled),@"keySaved":@(self.hasAPIKey),@"customBaseURL":@(![self.baseURL isEqualToString:WPChatAdvisorDefaultBaseURL]),@"model":self.model,
             @"preset":self.currentPreset.identifier,@"contextCount":@(self.contextCount),@"route":WPCALastRoute ?: @"not-run",@"lastLineCount":@(WPCALastLineCount),
             @"analyses":@(WPCAAnalyses),@"failures":@(WPCAFailures),@"lastHTTPStatus":@(WPCALastHTTPStatus),@"lastFailure":WPCALastFailure ?: @"none"};
}
@end
