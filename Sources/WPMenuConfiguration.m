#import "WPMenuConfiguration.h"
#import "WPCommon.h"
#import "WPPartnerContact.h"
#import "WPEdition.h"

static NSString * const WPMenuOrderKey=@"radialMenuOrder";
static NSString * const WPMenuEnabledKey=@"radialMenuEnabled";

// Couple editions keep their original menu first: moments, the two
// interactions sent to the partner, then the shared actions.
NSArray<NSString *> *WPMenuAvailableActions(void){
    if(WP_EDITION_COUPLE)return @[@"moments",@"miss",@"anger",@"read",@"advisor",@"quickChat",@"settings",@"contact1",@"contact2",@"contact3",@"advisorHistory",@"advisorDirect"];
    return @[@"read",@"advisor",@"moments",@"quickChat",@"settings",@"contact1",@"contact2",@"contact3",@"advisorHistory",@"advisorDirect"];
}
static NSArray<NSString *> *WPMenuDefaultEnabledActions(void){
    return WP_EDITION_COUPLE?@[@"moments",@"miss",@"anger",@"read",@"advisor"]:@[@"read",@"advisor",@"moments"];
}
NSString *WPMenuActionTitle(NSString *identifier){return @{@"miss":@"想你了",@"anger":@"生气了",@"read":@"一键已读",@"advisor":@"参谋聊天",@"advisorDirect":@"直接参谋",@"advisorHistory":@"参谋记录",@"moments":@"朋友圈",@"quickChat":@"快捷聊天",@"settings":@"桌宠设置",@"contact1":@"快捷联系人 1",@"contact2":@"快捷联系人 2",@"contact3":@"快捷联系人 3"}[identifier]?:@"";}
static BOOL WPMenuIsContact(NSString *identifier){return [@[@"contact1",@"contact2",@"contact3"] containsObject:identifier];}
NSString *WPMenuContactUsername(NSString *identifier){
    if(!WPMenuIsContact(identifier))return nil;
    id value=[WPPreferences() objectForKey:[@"radialMenu." stringByAppendingString:identifier]];
    if(![value isKindOfClass:NSString.class] || ![value length] || [value length]>256)return nil;
    return value;
}
void WPMenuSetContactUsername(NSString *identifier,NSString *username){
    if(!WPMenuIsContact(identifier))return;NSString *key=[@"radialMenu." stringByAppendingString:identifier];
    if(username && ![username isKindOfClass:NSString.class])return;
    if(!username.length)[WPPreferences() removeObjectForKey:key];
    else if([username isKindOfClass:NSString.class] && username.length<=256)[WPPreferences() setObject:username forKey:key];
    else return;
    [NSNotificationCenter.defaultCenter postNotificationName:WPSettingsDidChangeNotification object:nil];
}
NSInteger WPMenuContactPresentationMode(void){return [WPPreferences() integerForKey:@"radialMenu.contactPresentationMode"]==1?1:0;}
void WPMenuSetContactPresentationMode(NSInteger mode){[WPPreferences() setInteger:mode==1?1:0 forKey:@"radialMenu.contactPresentationMode"];}
NSArray<NSString *> *WPMenuOrderedActions(void){
    NSArray *allowed=WPMenuAvailableActions();id saved=[WPPreferences() objectForKey:WPMenuOrderKey];
    NSMutableOrderedSet *order=[NSMutableOrderedSet new];
    if([saved isKindOfClass:NSArray.class])for(id item in saved)if([item isKindOfClass:NSString.class] && [allowed containsObject:item])[order addObject:item];
    // New actions always remain available to enable after a later update.
    for(NSString *item in allowed)[order addObject:item];return order.array;
}
NSArray<NSString *> *WPMenuEnabledActions(void){
    NSArray *order=WPMenuOrderedActions();id saved=[WPPreferences() objectForKey:WPMenuEnabledKey];
    NSArray *enabled=[saved isKindOfClass:NSArray.class]?saved:WPMenuDefaultEnabledActions();
    NSMutableArray *result=[NSMutableArray new];for(NSString *item in order)if([enabled containsObject:item])[result addObject:item];return result;
}
void WPMenuSetOrder(NSArray<NSString *> *identifiers){
    if(![identifiers isKindOfClass:NSArray.class])return;
    NSMutableOrderedSet *order=[NSMutableOrderedSet new];NSArray *allowed=WPMenuAvailableActions();
    for(id item in identifiers)if([item isKindOfClass:NSString.class] && [allowed containsObject:item])[order addObject:item];
    for(NSString *item in allowed)[order addObject:item];
    [WPPreferences() setObject:order.array forKey:WPMenuOrderKey];
    [NSNotificationCenter.defaultCenter postNotificationName:WPSettingsDidChangeNotification object:nil];
}
void WPMenuSetActionEnabled(NSString *identifier,BOOL enabled){
    if(![WPMenuAvailableActions() containsObject:identifier])return;
    NSMutableOrderedSet *current=[NSMutableOrderedSet orderedSetWithArray:WPMenuEnabledActions()];
    if(enabled)[current addObject:identifier];else [current removeObject:identifier];
    [WPPreferences() setObject:current.array forKey:WPMenuEnabledKey];
    [NSNotificationCenter.defaultCenter postNotificationName:WPSettingsDidChangeNotification object:nil];
}
void WPMenuResetActions(void){
    [WPPreferences() removeObjectForKey:WPMenuOrderKey];[WPPreferences() removeObjectForKey:WPMenuEnabledKey];
    [NSNotificationCenter.defaultCenter postNotificationName:WPSettingsDidChangeNotification object:nil];
}

@implementation WPMenuSettingsController
- (instancetype)init {return [super initWithStyle:UITableViewStyleInsetGrouped];}
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"长按菜单";self.tableView.editing=YES;self.tableView.allowsSelectionDuringEditing=YES;
    self.tableView.accessibilityIdentifier=@"WPMenuSettingsTable";
}
- (void)viewWillAppear:(BOOL)animated {[super viewWillAppear:animated];[self.tableView reloadData];}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView{return 3;}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{return section==0?(NSInteger)WPMenuOrderedActions().count:1;}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section{return section==0?@"菜单项目":(section==1?@"快捷联系人打开方式":@"恢复默认");}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section{return section==0?@"拖动右侧手柄调整顺序，关闭开关可从菜单移除。点快捷联系人可选择联系人；聊天参谋需要先完成配置。":nil;}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    if(indexPath.section==1){
        cell.textLabel.text=@"打开聊天";cell.selectionStyle=UITableViewCellSelectionStyleNone;
        UISegmentedControl *mode=[[UISegmentedControl alloc] initWithItems:@[@"半屏",@"全屏"]];mode.selectedSegmentIndex=WPMenuContactPresentationMode();
        __weak UISegmentedControl *weakMode=mode;
        [mode addAction:[UIAction actionWithHandler:^(__unused UIAction *action){WPMenuSetContactPresentationMode(weakMode.selectedSegmentIndex);}] forControlEvents:UIControlEventValueChanged];
        cell.editingAccessoryView=mode;cell.accessoryView=mode;return cell;
    }
    if(indexPath.section==2){cell.textLabel.text=@"恢复默认菜单";cell.textLabel.textColor=UIColor.systemBlueColor;cell.selectionStyle=UITableViewCellSelectionStyleDefault;return cell;}
    NSString *item=WPMenuOrderedActions()[indexPath.row];cell.textLabel.text=WPMenuActionTitle(item);
    BOOL contact=WPMenuIsContact(item);cell.selectionStyle=contact?UITableViewCellSelectionStyleDefault:UITableViewCellSelectionStyleNone;
    if(contact){NSString *username=WPMenuContactUsername(item);NSString *name=username.length?[WPPartnerContact displayNameForUsername:username]:nil;
        cell.detailTextLabel.text=username.length?(name.length?name:@"已选择联系人"):@"点击选择联系人";}
    cell.showsReorderControl=YES;
    UISwitch *toggle=[UISwitch new];toggle.on=[WPMenuEnabledActions() containsObject:item];toggle.accessibilityLabel=[@"显示" stringByAppendingString:WPMenuActionTitle(item)];
    toggle.accessibilityIdentifier=[@"WPMenuEnabled-" stringByAppendingString:item];
    __weak UISwitch *weakToggle=toggle;
    [toggle addAction:[UIAction actionWithHandler:^(__unused UIAction *action){WPMenuSetActionEnabled(item,weakToggle.isOn);}] forControlEvents:UIControlEventValueChanged];
    cell.editingAccessoryView=toggle;return cell;
}
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath{return indexPath.section==0;}
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath{return indexPath.section==0;}
- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath{return UITableViewCellEditingStyleNone;}
- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath{return NO;}
- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)source toProposedIndexPath:(NSIndexPath *)proposed {
    if(proposed.section==0)return proposed;return [NSIndexPath indexPathForRow:(NSInteger)WPMenuOrderedActions().count-1 inSection:0];
}
- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)source toIndexPath:(NSIndexPath *)destination {
    NSMutableArray *order=[WPMenuOrderedActions() mutableCopy];if(source.row<0 || destination.row<0 || (NSUInteger)source.row>=order.count || (NSUInteger)destination.row>=order.count)return;
    NSString *item=order[source.row];[order removeObjectAtIndex:source.row];[order insertObject:item atIndex:destination.row];WPMenuSetOrder(order);
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if(indexPath.section==2){WPMenuResetActions();[tableView reloadData];return;}
    NSArray *order=WPMenuOrderedActions();if(indexPath.section!=0 || indexPath.row<0 || (NSUInteger)indexPath.row>=order.count)return;
    NSString *item=order[indexPath.row];if(!WPMenuIsContact(item))return;
    WPPartnerPickerController *picker=[[WPPartnerPickerController alloc] initWithStyle:UITableViewStyleInsetGrouped];picker.pickerTitle=WPMenuActionTitle(item);
    picker.selectionHandler=^(NSString *username,__unused NSString *displayName){WPMenuSetContactUsername(item,username);};
    [self.navigationController pushViewController:picker animated:YES];
}
@end
