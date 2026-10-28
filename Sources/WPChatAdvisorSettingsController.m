#import "WPChatAdvisorSettingsController.h"
#import "WPChatAdvisor.h"
#import "WPCommon.h"

/// Lists the account's chat models from the provider and saves the picked one.
@interface WPChatAdvisorModelPicker : UITableViewController <UISearchResultsUpdating>
@property(nonatomic,copy) NSArray<NSString *> *models;
@property(nonatomic,copy) NSArray<NSString *> *filtered;
@property(nonatomic,copy) NSString *status;
@end
@implementation WPChatAdvisorModelPicker
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=@"选择模型";self.status=@"正在获取模型列表…";self.filtered=@[];
    UISearchController *search=[[UISearchController alloc] initWithSearchResultsController:nil];
    search.searchResultsUpdater=self;search.obscuresBackgroundDuringPresentation=NO;search.searchBar.placeholder=@"搜索模型，如 DeepSeek、Qwen";
    self.navigationItem.searchController=search;self.navigationItem.hidesSearchBarWhenScrolling=NO;
    __weak typeof(self) weakSelf=self;
    [WPChatAdvisor fetchModels:^(NSArray<NSString *> *models,NSString *error){
        weakSelf.models=models ?: @[];weakSelf.status=error;[weakSelf updateSearchResultsForSearchController:search];
    }];
}
- (void)updateSearchResultsForSearchController:(UISearchController *)controller {
    NSString *query=controller.searchBar.text ?: @"";
    self.filtered=query.length?[self.models filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF CONTAINS[cd] %@",query]]:self.models;
    [self.tableView reloadData];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {return self.filtered.count;}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return self.status ?: [NSString stringWithFormat:@"共 %lu 个对话模型，当前使用 %@",(unsigned long)self.models.count,WPChatAdvisor.model];
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"model"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"model"];
    NSString *model=self.filtered[indexPath.row];
    cell.textLabel.text=model;cell.textLabel.font=[UIFont systemFontOfSize:15];cell.textLabel.numberOfLines=0;
    cell.accessoryType=[model isEqualToString:WPChatAdvisor.model]?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [WPChatAdvisor setModel:self.filtered[indexPath.row]];
    self.navigationItem.searchController.active=NO;
    [self.navigationController popViewControllerAnimated:YES];
}
@end

@interface WPChatAdvisorSettingsController ()
@property(nonatomic) UITextField *keyField;
@property(nonatomic) UITextField *urlField;
@property(nonatomic) UITextField *customField;
@property(nonatomic) BOOL testing;
@end
@implementation WPChatAdvisorSettingsController
- (UITextField *)plainField {
    UITextField *field=[UITextField new];field.autocapitalizationType=UITextAutocapitalizationTypeNone;field.autocorrectionType=UITextAutocorrectionTypeNo;
    field.clearButtonMode=UITextFieldViewModeWhileEditing;return field;
}
- (void)viewDidLoad {
    self.title=@"聊天参谋";
    self.keyField=[self plainField];self.keyField.secureTextEntry=YES;self.keyField.accessibilityIdentifier=@"WPChatAdvisorKeyField";
    self.urlField=[self plainField];self.urlField.keyboardType=UIKeyboardTypeURL;self.urlField.placeholder=WPChatAdvisorDefaultBaseURL;
    self.customField=[self plainField];self.customField.autocapitalizationType=UITextAutocapitalizationTypeSentences;
    self.customField.placeholder=@"例如：对方是我女朋友，最近工作很忙";
    [super viewDidLoad];
}
- (void)viewWillAppear:(BOOL)animated {[super viewWillAppear:animated];[self reloadCards];}
- (void)viewWillDisappear:(BOOL)animated {[super viewWillDisappear:animated];[self saveCustom];}
- (void)changed {[NSNotificationCenter.defaultCenter postNotificationName:WPSettingsDidChangeNotification object:nil];}
- (void)buildCards {
    __weak typeof(self) weakSelf=self;
    BOOL keySaved=WPChatAdvisor.hasAPIKey;
    self.keyField.placeholder=keySaved?@"已保存，留空保持不变":@"sk-…";
    if(!self.urlField.isFirstResponder)self.urlField.text=[WPChatAdvisor.baseURL isEqualToString:WPChatAdvisorDefaultBaseURL]?@"":WPChatAdvisor.baseURL;
    if(!self.customField.isFirstResponder)self.customField.text=WPChatAdvisor.customInstruction;

    UIStackView *main=[self addCard];
    UIView *toggle=[self switchRowWithTitle:@"启用聊天参谋" detail:keySaved?@"长按桌宠滑到「参谋」，或在快捷设置里把单击、双击设为聊天参谋":@"先在下方填写 API Key"
                                         on:WPChatAdvisor.isEnabled handler:^(BOOL on){[WPChatAdvisor setEnabled:on];[weakSelf changed];[weakSelf reloadCards];}];
    [main addArrangedSubview:toggle];

    [self addSectionTitle:@"模型服务"];
    UIStackView *service=[self addCard];
    [service addArrangedSubview:[self fieldRowWithTitle:@"API Key" field:self.keyField]];
    [service addArrangedSubview:[self fieldRowWithTitle:@"接口地址（留空用硅基流动）" field:self.urlField]];
    [service addArrangedSubview:[self buttonWithTitle:@"保存" primary:YES handler:^{[weakSelf saveService];}]];
    [service addArrangedSubview:[self rowWithTitle:@"模型" detail:WPChatAdvisor.model actionTitle:@"选择" handler:^{
        if(!WPChatAdvisor.hasAPIKey){[weakSelf alert:@"请先保存 API Key，再获取可用模型。"];return;}
        [weakSelf.navigationController pushViewController:[[WPChatAdvisorModelPicker alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];}]];
    [service addArrangedSubview:[self rowWithTitle:@"测试连接" detail:self.testing?@"正在连接…":@"检查 Key、地址和当前模型" actionTitle:@"测试" handler:^{[weakSelf test];}]];
    if(keySaved)[service addArrangedSubview:[self rowWithTitle:@"删除 API Key" detail:@"从本机钥匙串移除" actionTitle:@"删除" handler:^{
        [WPChatAdvisor clearAPIKey];[WPChatAdvisor setEnabled:NO];[weakSelf changed];[weakSelf reloadCards];}]];
    [self addNote:@"API Key 在硅基流动控制台「API 密钥」页面创建，保存在本机钥匙串。也可以填其他兼容 OpenAI 接口的服务地址。"];

    [self addSectionTitle:@"分析预设"];
    UIStackView *presets=[self addCard];
    NSString *current=WPChatAdvisor.currentPreset.identifier;
    for(WPChatAdvisorPreset *preset in WPChatAdvisorPreset.builtinPresets){
        BOOL selected=[preset.identifier isEqualToString:current];
        [presets addArrangedSubview:[self rowWithTitle:preset.title detail:preset.summary actionTitle:selected?@"使用中":@"选用" handler:^{
            [weakSelf saveCustom];[WPChatAdvisor setPresetIdentifier:preset.identifier];[weakSelf reloadCards];}]];
    }
    UIStackView *custom=[self addCard];
    [custom addArrangedSubview:[self fieldRowWithTitle:@"补充说明（最多 300 字）" field:self.customField]];
    [self addNote:@"补充说明会附在任何预设后面，可以写你们的关系、对方的性格或你想要的语气。选「自定义」时只按补充说明分析。"];

    [self addSectionTitle:@"上下文"];
    UIStackView *context=[self addCard];
    [context addArrangedSubview:[self sliderRowWithTitle:@"分析最近的消息条数" value:WPChatAdvisor.contextCount minimum:6 maximum:40
        format:^NSString *(float value){return [NSString stringWithFormat:@"%.0f 条",value];}
        handler:^(float value){[WPChatAdvisor setContextCount:(NSUInteger)lroundf(value)];}]];
    [self addNote:@"分析时，当前聊天里最近这些条文字（图片、语音等只记类型）会发送到上面的模型服务，不会保存在插件里。群聊成员只以「成员1」「成员2」区分，不发送昵称和微信号。"];
}
- (void)saveCustom {
    if(self.customField)[WPChatAdvisor setCustomInstruction:self.customField.text ?: @""];
}
- (void)saveService {
    [self.view endEditing:YES];
    if(![WPChatAdvisor setBaseURL:self.urlField.text ?: @""]){[self alert:@"接口地址需以 https:// 开头，且不能包含参数。"];return;}
    NSString *key=[self.keyField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if(key.length && ![WPChatAdvisor saveAPIKey:key]){[self alert:@"API Key 没有保存成功，请重试。"];return;}
    BOOL firstKey=key.length && !WPChatAdvisor.isEnabled;
    if(firstKey)[WPChatAdvisor setEnabled:YES];
    self.keyField.text=@"";[self changed];[self reloadCards];
    [self alert:firstKey?@"已保存并启用聊天参谋。可以点「测试连接」确认。":@"已保存。"];
}
- (void)test {
    if(self.testing)return;
    [self.view endEditing:YES];
    if(!WPChatAdvisor.hasAPIKey){[self alert:@"请先保存 API Key。"];return;}
    self.testing=YES;[self reloadCards];
    __weak typeof(self) weakSelf=self;
    [WPChatAdvisor testConnection:^(__unused BOOL success,NSString *message){weakSelf.testing=NO;[weakSelf reloadCards];[weakSelf alert:message];}];
}
@end
