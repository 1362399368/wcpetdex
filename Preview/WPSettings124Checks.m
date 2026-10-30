#import "WPSettings124Checks.h"
#import "WPSettings.h"
#import "WPCatalogController.h"
#import "WPBarrageSettingsController.h"
#import "WPBarragePreferences.h"
#import "WPCommon.h"

static UIView *WP124Find(UIView *root,NSString *identifier,Class kind){
    if((!identifier || [root.accessibilityIdentifier isEqual:identifier]) && (!kind || [root isKindOfClass:kind]))return root;
    for(UIView *child in root.subviews){UIView *found=WP124Find(child,identifier,kind);if(found)return found;}return nil;
}
static BOOL WP124HasLabel(UIView *root,NSString *text){
    if([root isKindOfClass:UILabel.class] && [((UILabel *)root).text isEqual:text])return YES;
    for(UIView *child in root.subviews)if(WP124HasLabel(child,text))return YES;return NO;
}
NSDictionary<NSString *,NSNumber *> *WPSettings124PreviewChecks(void){
    NSMutableDictionary *checks=[NSMutableDictionary new];
    NSArray *keys=@[@"barrageShowsName",@"barrageNameUsesRemark",@"barrageCompletionAnimation"];
    NSMutableDictionary *saved=[NSMutableDictionary new];for(NSString *key in keys)saved[key]=[WPPreferences() objectForKey:key]?:NSNull.null;
    BOOL animations=UIView.areAnimationsEnabled;[UIView setAnimationsEnabled:NO];
    @try{
        WPCardPageController *petPage=[NSClassFromString(@"WPPetSettingsController") new];
        UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:petPage];[nav loadViewIfNeeded];[petPage loadViewIfNeeded];
        checks[@"S124AppearanceEntryInsidePetSettings"]=@(WP124HasLabel(petPage.view,@"外观设置"));
        UIView *row=WP124Find(petPage.view,@"WPCurrentPetLocalLibrary",nil);
        UIButton *tap=(id)WP124Find(row,nil,UIButton.class);[tap sendActionsForControlEvents:UIControlEventTouchUpInside];
        WPCatalogController *library=(id)nav.topViewController;[library loadViewIfNeeded];
        checks[@"S124CurrentPetTapOpensDownloadedLibrary"]=@([library isKindOfClass:WPCatalogController.class] && library.startsWithDownloadedPets && ((UISegmentedControl *)[library valueForKey:@"segments"]).selectedSegmentIndex==2);
        checks[@"S124DownloadedLibraryDoesNotStartOnlineRequest"]=@(![[library valueForKey:@"catalogLoading"] boolValue]);
        WPBarrageSetShowsName(NO);WPBarrageSetCompletionAnimation(0);
        WPBarrageSettingsController *page=[WPBarrageSettingsController new];[page loadViewIfNeeded];
        UISwitch *names=(id)WP124Find(page.view,@"WPBarrageNameSwitch",UISwitch.class);
        checks[@"S124NamesDefaultOffWithSourceHidden"]=@(names && !names.on && !WP124Find(page.view,@"WPBarrageNameSource",nil));
        names.on=YES;[names sendActionsForControlEvents:UIControlEventValueChanged];
        UISegmentedControl *source=(id)WP124Find(page.view,@"WPBarrageNameSource",UISegmentedControl.class);
        source.selectedSegmentIndex=0;[source sendActionsForControlEvents:UIControlEventValueChanged];
        checks[@"S124NameSwitchAndNicknameSelectionPersist"]=@(WPBarrageShowsName() && source && !WPBarrageNameUsesRemark());
        UISegmentedControl *style=(id)WP124Find(page.view,@"WPBarrageCompletionStyle",UISegmentedControl.class);
        style.selectedSegmentIndex=1;[style sendActionsForControlEvents:UIControlEventValueChanged];
        checks[@"S124AvatarFlightSelectionPersists"]=@(style && WPBarrageCompletionAnimation()==1);
        UISwitch *ending=(id)WP124Find(page.view,@"WPBarrageCompletionSwitch",UISwitch.class);ending.on=NO;[ending sendActionsForControlEvents:UIControlEventValueChanged];
        checks[@"S124EndingAnimationCanBeDisabled"]=@(WPBarrageCompletionAnimation()==3 && !WP124Find(page.view,@"WPBarrageCompletionStyle",nil));
    }@catch(__unused NSException *error){checks[@"S124SettingsFlowCompleted"]=@NO;}
    @finally{for(NSString *key in keys){id value=saved[key];if(value==NSNull.null)[WPPreferences() removeObjectForKey:key];else [WPPreferences() setObject:value forKey:key];}[UIView setAnimationsEnabled:animations];}
    return checks;
}
