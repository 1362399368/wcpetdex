#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
/// SiliconFlow's OpenAI-compatible endpoint; any compatible base URL may replace it.
FOUNDATION_EXPORT NSString * const WPChatAdvisorDefaultBaseURL;
FOUNDATION_EXPORT NSString * const WPChatAdvisorDefaultModel;
FOUNDATION_EXPORT NSString * const WPChatAdvisorCustomPresetIdentifier;

/// A built-in analysis scene. The instruction steers both the reading and the replies.
@interface WPChatAdvisorPreset : NSObject
@property(nonatomic,copy,readonly) NSString *identifier;
@property(nonatomic,copy,readonly) NSString *title;
@property(nonatomic,copy,readonly) NSString *summary;
@property(nonatomic,copy,readonly) NSString *instruction;
+ (NSArray<WPChatAdvisorPreset *> *)builtinPresets;
+ (WPChatAdvisorPreset *)presetWithIdentifier:(nullable NSString *)identifier;
@end

/// One text line of the visible chat. Lives only for a single analysis.
@interface WPChatLine : NSObject
@property(nonatomic) BOOL fromMe;
@property(nonatomic,copy) NSString *speaker;
@property(nonatomic,copy) NSString *text;
@property(nonatomic,strong,nullable) NSDate *date;
+ (instancetype)lineFromMe:(BOOL)fromMe speaker:(NSString *)speaker text:(NSString *)text date:(nullable NSDate *)date;
@end

@interface WPChatAdvice : NSObject
@property(nonatomic,copy) NSString *summary;
@property(nonatomic,copy) NSString *strategy;
/// Each item: @{@"label":NSString,@"percent":NSNumber}, at most four.
@property(nonatomic,copy) NSArray<NSDictionary<NSString *,id> *> *intents;
@property(nonatomic) NSInteger riskLevel;
@property(nonatomic,copy) NSString *riskLabel;
@property(nonatomic,copy) NSString *replyTiming;
@property(nonatomic,copy) NSArray<NSString *> *actions;
@property(nonatomic,copy) NSArray<NSString *> *replies;
/// Accepts the model's message content, with or without a ```json fence.
+ (nullable instancetype)adviceFromModelContent:(NSString *)content error:(NSString * _Nullable * _Nullable)error;
@end

/// Cancels the active network request, including any retry. Use on the main thread.
@interface WPChatAdvisorRequest : NSObject
- (void)cancel;
@end

@interface WPChatAdvisor : NSObject
+ (BOOL)isEnabled;
+ (void)setEnabled:(BOOL)enabled;
/// Enabled and an API key is saved in the keychain.
+ (BOOL)isReady;
+ (NSString *)baseURL;
/// Returns NO when the URL is not https (plain http is allowed only for loopback).
+ (BOOL)setBaseURL:(NSString *)value;
+ (NSString *)model;
+ (void)setModel:(NSString *)model;
+ (WPChatAdvisorPreset *)currentPreset;
+ (void)setPresetIdentifier:(NSString *)identifier;
+ (NSString *)customInstruction;
+ (void)setCustomInstruction:(NSString *)instruction;
/// Number of recent text lines sent for one analysis, 6 through 40.
+ (NSUInteger)contextCount;
+ (void)setContextCount:(NSUInteger)count;
+ (BOOL)hasAPIKey;
+ (BOOL)saveAPIKey:(NSString *)key;
+ (void)clearAPIKey;

/// Reads loaded message wrappers from a visible native chat controller. Returns
/// nil when this WeChat build exposes no readable message list; route names it.
+ (nullable NSArray<WPChatLine *> *)transcriptForChatController:(UIViewController *)controller username:(NSString *)username
                                                         limit:(NSUInteger)limit route:(NSString * _Nullable * _Nullable)route;
/// Chat-completions body; split out so the preview checks can inspect it. Group
/// senders are renamed 成员1, 成员2…; no chat name or username is included.
+ (NSDictionary *)requestBodyForLines:(NSArray<WPChatLine *> *)lines group:(BOOL)group
                               preset:(WPChatAdvisorPreset *)preset customInstruction:(NSString *)custom model:(NSString *)model;
/// Completion runs on main. Exactly one of advice and error is non-nil.
+ (void)analyzeLines:(NSArray<WPChatLine *> *)lines group:(BOOL)group
          completion:(void (^)(WPChatAdvice * _Nullable advice, NSString * _Nullable error))completion;
+ (WPChatAdvisorRequest *)startAnalysisOfLines:(NSArray<WPChatLine *> *)lines group:(BOOL)group
                                   completion:(void (^)(WPChatAdvice * _Nullable advice, NSString * _Nullable error))completion;
+ (void)testConnection:(void (^)(BOOL success, NSString *message))completion;
+ (void)fetchModels:(void (^)(NSArray<NSString *> * _Nullable models, NSString * _Nullable error))completion;
/// Replaces the native input text without sending. NO means nothing was written.
+ (BOOL)fillReply:(NSString *)text intoChatController:(UIViewController *)controller;
/// Route and counters only; never chat text, usernames or the key.
+ (NSDictionary<NSString *,id> *)diagnostics;
@end
NS_ASSUME_NONNULL_END
