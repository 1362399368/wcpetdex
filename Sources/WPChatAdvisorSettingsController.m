#import "WPChatAdvisorSettingsController.h"
#import "WPChatAdvisor.h"
#import "WPCommon.h"
#import "WPAdvisorContinuousCoordinator.h"
#import "WPPartnerContact.h"

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
    [WPAdvisorContinuousCoordinator.sharedCoordinator refreshAccountIfNeeded];
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
    [service addArrangedSubview:[self rowWithTitle:@"使用 DeepSeek 官方接口" detail:@"地址填入后请点保存，并使用 DeepSeek 官方 API Key" actionTitle:@"填入" handler:^{weakSelf.urlField.text=@"https://api.deepseek.com";}]];
    [service addArrangedSubview:[self buttonWithTitle:@"保存" primary:YES handler:^{[weakSelf saveService];}]];
    [service addArrangedSubview:[self rowWithTitle:@"模型" detail:WPChatAdvisor.model actionTitle:@"选择" handler:^{
        if(!WPChatAdvisor.hasAPIKey){[weakSelf alert:@"请先保存 API Key，再获取可用模型。"];return;}
        [weakSelf.navigationController pushViewController:[[WPChatAdvisorModelPicker alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];}]];
    [service addArrangedSubview:[self rowWithTitle:@"测试连接" detail:self.testing?@"正在连接…":@"检查 Key、地址和当前模型" actionTitle:@"测试" handler:^{[weakSelf test];}]];
    if(keySaved)[service addArrangedSubview:[self rowWithTitle:@"删除 API Key" detail:@"从本机钥匙串移除" actionTitle:@"删除" handler:^{
        [WPChatAdvisor clearAPIKey];[WPChatAdvisor setEnabled:NO];[weakSelf changed];[weakSelf reloadCards];}]];
    [self addNote:@"硅基流动和 DeepSeek 官方的 API Key 不能混用。DeepSeek 官方地址为 https://api.deepseek.com，推荐模型 deepseek-flash；控制台网页地址会自动转换。API Key 保存在本机钥匙串。"];

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
    [self addNote:@"分析时聊天文字（图片、语音等只记类型）会发送到配置的模型服务；原始消息只在内存短暂保留，分析结果最多在本机保留三天。群聊成员只以「成员1」「成员2」区分，不发送昵称和微信号。"];

    [self addSectionTitle:@"连续对话"];
    UIStackView *continuousCard=[self addCard];
    WPAdvisorContinuousCoordinator *continuous=WPAdvisorContinuousCoordinator.sharedCoordinator;
    NSString *locked=continuous.lockedUsername;
    NSString *continuousAccount=[continuous.accountToken copy];
    NSString *display=locked.length?[WPPartnerContact displayNameForUsername:locked]:@"";
    [continuousCard addArrangedSubview:[self rowWithTitle:@"锁定私聊联系人" detail:locked.length?(display.length?display:@"已选择联系人"):@"选择要开启连续对话的联系人" actionTitle:@"选择" handler:^{
        WPPartnerPickerController *picker=[[WPPartnerPickerController alloc] initWithStyle:UITableViewStyleInsetGrouped];picker.pickerTitle=@"选择连续对话联系人";
        picker.selectionHandler=^(NSString *username,__unused NSString *name){[WPAdvisorContinuousCoordinator.sharedCoordinator setLockedUsername:username];};
        [weakSelf.navigationController pushViewController:picker animated:YES];
    }]];
    [continuousCard addArrangedSubview:[self switchRowWithTitle:@"开启连续对话" detail:@"对方停止发消息 30 秒后合并分析；微信需在前台" on:continuous.isEnabled handler:^(BOOL enabled){
        if(enabled && !WPAdvisorContinuousCoordinator.sharedCoordinator.lockedUsername.length){[weakSelf alert:@"请先选择私聊联系人。"];[weakSelf reloadCards];return;}
        if(enabled && !WPChatAdvisor.isReady){[weakSelf alert:@"请先启用聊天参谋并配置 API Key。"];[weakSelf reloadCards];return;}
        [WPAdvisorContinuousCoordinator.sharedCoordinator setEnabled:enabled];
        if(enabled && !WPAdvisorContinuousCoordinator.sharedCoordinator.enabled)[weakSelf alert:@"最多同时开启 8 个私聊，请先关闭其他联系人。"];
        [weakSelf reloadCards];
    }]];
    if(locked.length && continuous.isEnabled)[continuousCard addArrangedSubview:[self switchRowWithTitle:@"有新消息时重新分析才能发送" detail:@"仅对该联系人生效；关闭后仍可使用已有建议" on:[continuous requiresFreshAnalysisForUsername:locked] handler:^(BOOL enabled){
        WPAdvisorContinuousCoordinator *current=WPAdvisorContinuousCoordinator.sharedCoordinator;[current refreshAccountIfNeeded];
        if(continuousAccount.length && [current.accountToken isEqualToString:continuousAccount] && [current.lockedUsername isEqualToString:locked] && current.isEnabled)
            [current setRequiresFreshAnalysis:enabled forUsername:locked];
        [weakSelf reloadCards];
    }]];
    if(locked.length)[continuousCard addArrangedSubview:[self rowWithTitle:@"解除锁定" detail:@"关闭连续对话并移除所选联系人" actionTitle:@"解除" handler:^{[WPAdvisorContinuousCoordinator.sharedCoordinator setLockedUsername:nil];[weakSelf reloadCards];}]];
    if(continuous.enabledUsernames.count){
        [self addSectionTitle:@"已开启的私聊"];
        UIStackView *enabledCard=[self addCard];
        for(NSString *username in continuous.enabledUsernames){
            NSString *name=[WPPartnerContact displayNameForUsername:username];
            [enabledCard addArrangedSubview:[self rowWithTitle:name.length?name:@"私聊联系人" detail:@"单独设置或关闭" actionTitle:@"管理" handler:^{[WPAdvisorContinuousCoordinator.sharedCoordinator setLockedUsername:username];[weakSelf reloadCards];}]];
        }
    }
    [self addNote:@"最多为 8 个私聊分别开启。需先打开对应聊天一次以加载上下文；切换账号、内存紧张或重新启动后可能需重新打开。微信须在前台；接口不兼容可能无法触发。模型服务可能产生费用。"];
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
