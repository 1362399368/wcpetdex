#import "WPMenuConfigurationChecks.h"
#import "WPMenuConfiguration.h"
#import "WPRadialMenu.h"
#import "WPCommon.h"
#import "WPEdition.h"
#import "WPSharedChatAvatar.h"
extern void WPPreviewSeedSharedAvatar(NSString *, UIImage *);

static BOOL WPAdvisorIconHasDistinctColors(UIImage *image){
    if(!image.CGImage || image.renderingMode!=UIImageRenderingModeAlwaysOriginal)return NO;
    unsigned char pixels[34*34*4]={0};
    CGColorSpaceRef colors=CGColorSpaceCreateDeviceRGB();
    CGContextRef context=CGBitmapContextCreate(pixels,34,34,8,34*4,colors,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colors);if(!context)return NO;
    CGContextDrawImage(context,CGRectMake(0,0,34,34),image.CGImage);CGContextRelease(context);
    BOOL purple=NO,teal=NO,orange=NO;
    for(NSUInteger i=0;i<34*34;i++){
        unsigned char *p=&pixels[i*4];if(p[3]<225)continue;
        purple|=p[2]>p[0]+25 && p[0]>p[1]+15;
        teal|=p[1]>p[0]+50 && p[2]>p[0]+50;
        orange|=p[0]>p[1]+50 && p[1]>p[2]+35;
    }
    return purple && teal && orange;
}

// Couple editions enable miss and anger by default. The layout checks below
// count the shared items, so they start from the shared defaults only.
static void WPMenuResetSharedActions(void){
    WPMenuResetActions();
    if(WP_EDITION_COUPLE){WPMenuSetActionEnabled(@"miss",NO);WPMenuSetActionEnabled(@"anger",NO);}
}

NSDictionary<NSString *,NSNumber *> *WPMenuConfigurationPreviewChecks(void){
    NSCAssert(NSThread.isMainThread,@"Menu checks require main thread");
    NSUserDefaults *prefs=WPPreferences();NSString *orderKey=@"radialMenuOrder",*enabledKey=@"radialMenuEnabled";
    id oldOrder=[prefs objectForKey:orderKey],oldEnabled=[prefs objectForKey:enabledKey];
    NSArray *contactKeys=@[@"radialMenu.contact1",@"radialMenu.contact2",@"radialMenu.contact3"];
    NSMutableArray *oldContacts=[NSMutableArray new];for(NSString *key in contactKeys)[oldContacts addObject:[prefs objectForKey:key]?:NSNull.null];
    WPMenuResetActions();NSMutableDictionary *checks=[NSMutableDictionary new];
    checks[@"menuDefaultActions"]=@([WPMenuEnabledActions() isEqual:WP_EDITION_COUPLE?@[@"moments",@"miss",@"anger",@"read",@"advisor"]:@[@"read",@"advisor",@"moments"]]);
    WPMenuResetSharedActions();
    WPMenuSetOrder(@[@"moments",@"advisor",@"read",@"quickChat",@"settings"]);
    WPMenuSetActionEnabled(@"advisor",NO);WPMenuSetActionEnabled(@"quickChat",YES);
    checks[@"menuOrderAndVisibilitySaved"]=@([WPMenuEnabledActions() isEqual:@[@"moments",@"read",@"quickChat"]]);
    WPRadialMenuView *menu=[[WPRadialMenuView alloc] initWithFrame:CGRectMake(0,0,390,700)];
    [menu showAroundPoint:CGPointMake(195,350) inBounds:menu.bounds];
    NSArray *buttons=[menu valueForKey:@"actionButtons"];
    checks[@"menuRendersSavedOrder"]=@(menu.isShowing && [[buttons valueForKey:@"actionIdentifier"] isEqual:@[@"moments",@"read",@"quickChat"]]);
    [menu cancel];
    WPMenuSetActionEnabled(@"read",NO);WPMenuSetActionEnabled(@"quickChat",NO);
    [menu showAroundPoint:CGPointMake(195,350) inBounds:menu.bounds];
    buttons=[menu valueForKey:@"actionButtons"];
    checks[@"menuOneActionFits"]=@(menu.isShowing && buttons.count==1 && CGRectContainsRect(menu.bounds,((UIView *)buttons.firstObject).frame));
    [menu cancel];WPMenuSetActionEnabled(@"moments",NO);[menu showAroundPoint:CGPointMake(195,350) inBounds:menu.bounds];
    checks[@"menuAllDisabledSafe"]=@(!menu.isShowing && menu.hidden && WPMenuEnabledActions().count==0);
    [prefs setObject:@[@"moments",@"unknown",@"moments"] forKey:orderKey];
    NSArray *sanitized=WP_EDITION_COUPLE?@[@"moments",@"miss",@"anger",@"read",@"advisor",@"quickChat",@"settings",@"contact1",@"contact2",@"contact3",@"advisorHistory",@"advisorDirect"]:@[@"moments",@"read",@"advisor",@"quickChat",@"settings",@"contact1",@"contact2",@"contact3",@"advisorHistory",@"advisorDirect"];
    checks[@"menuInvalidOrderSanitized"]=@([WPMenuOrderedActions() isEqual:sanitized]);
    WPMenuResetSharedActions();
    [menu showAroundPoint:CGPointMake(195,350) inBounds:menu.bounds];buttons=[menu valueForKey:@"actionButtons"];
    id advisor=nil;for(id button in buttons)if([[button valueForKey:@"actionIdentifier"] isEqual:@"advisor"])advisor=button;
    UIImageView *advisorIcon=[advisor valueForKey:@"symbolView"];
    checks[@"menuAdvisorIconHasThreeColors"]=@(WPAdvisorIconHasDistinctColors(advisorIcon.image));
    __block NSString *chosen=nil;menu.actionHandler=^(NSString *action){chosen=action;};
    [menu updateFingerAtPoint:((UIView *)advisor).center];
    BOOL selected=(((UIView *)advisor).accessibilityTraits & UIAccessibilityTraitSelected)!=0 && advisorIcon.transform.a>1;
    [menu finishTracking];
    checks[@"menuAdvisorSelectionAndAction"]=@(selected && [chosen isEqual:@"advisor"] && !menu.isShowing);
    menu.actionHandler=nil;
    WPMenuSetContactUsername(@"contact1",@"test-contact-one");WPMenuSetContactUsername(@"contact2",@"test-contact-two");WPMenuSetContactUsername(@"contact3",@"test-contact-three");
    WPMenuSetActionEnabled(@"contact1",YES);WPMenuSetActionEnabled(@"contact2",YES);WPMenuSetActionEnabled(@"contact3",YES);
    WPMenuSetOrder(@[@"contact2",@"read",@"contact1",@"advisor",@"moments",@"contact3"]);
    checks[@"menuContactSelectionAndOrder"]=@([WPMenuEnabledActions() isEqual:@[@"contact2",@"read",@"contact1",@"advisor",@"moments",@"contact3"]] && [WPMenuContactUsername(@"contact1") isEqual:@"test-contact-one"]);
    UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(24,24)];
    UIImage *avatar=[renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx){[UIColor.systemBlueColor setFill];[ctx fillRect:CGRectMake(0,0,24,24)];}];
    WPPreviewSeedSharedAvatar(@"test-contact-one",avatar);
    [menu showAroundPoint:CGPointMake(195,350) inBounds:menu.bounds];buttons=[menu valueForKey:@"actionButtons"];
    id contactButton=nil;for(id button in buttons)if([[button valueForKey:@"actionIdentifier"] isEqual:@"contact1"])contactButton=button;
    UIImageView *icon=[contactButton valueForKey:@"symbolView"];
    checks[@"menuSelectedContactUsesSharedAvatar"]=@(menu.isShowing && icon.image==avatar && icon.clipsToBounds);
    [menu cancel];WPMenuSetActionEnabled(@"contact1",NO);
    checks[@"menuDisabledContactKeepsBinding"]=@(![WPMenuEnabledActions() containsObject:@"contact1"] && [WPMenuContactUsername(@"contact1") isEqual:@"test-contact-one"]);
    WPMenuSetContactUsername(@"contact1",nil);checks[@"menuContactCanBeCleared"]=@(WPMenuContactUsername(@"contact1")==nil);
    WPMenuSetActionEnabled(@"contact1",YES);WPMenuSetActionEnabled(@"quickChat",YES);WPMenuSetActionEnabled(@"settings",YES);
    [menu showAroundPoint:CGPointMake(195,350) inBounds:menu.bounds];buttons=[menu valueForKey:@"actionButtons"];
    BOOL allFit=menu.isShowing && buttons.count==8;
    for(UIView *button in buttons)allFit &= CGRectContainsRect(menu.bounds,button.frame);
    checks[@"menuEightActionsFit"]=@(allFit);[menu cancel];
    WPMenuSetActionEnabled(@"advisorHistory",YES);
    [menu showAroundPoint:CGPointMake(195,350) inBounds:menu.bounds];buttons=[menu valueForKey:@"actionButtons"];
    BOOL nineFit=menu.isShowing && buttons.count==9;
    for(UIView *button in buttons)nineFit &= CGRectContainsRect(menu.bounds,button.frame);
    checks[@"menuNineActionsFit"]=@(nineFit);[menu cancel];
    WPMenuSetActionEnabled(@"advisorDirect",YES);[menu showAroundPoint:CGPointMake(195,350) inBounds:menu.bounds];buttons=[menu valueForKey:@"actionButtons"];
    BOOL tenFit=menu.isShowing && buttons.count==10;for(UIView *button in buttons)tenFit &= CGRectContainsRect(menu.bounds,button.frame);
    checks[@"menuDirectAdvisorFits"]=@(tenFit);[menu cancel];
    id oldMode=[prefs objectForKey:@"radialMenu.contactPresentationMode"];WPMenuSetContactPresentationMode(1);BOOL full=WPMenuContactPresentationMode()==1;
    WPMenuSetContactPresentationMode(0);checks[@"menuContactPresentationIndependent"]=@(full && WPMenuContactPresentationMode()==0);
    if(oldMode)[prefs setObject:oldMode forKey:@"radialMenu.contactPresentationMode"];else [prefs removeObjectForKey:@"radialMenu.contactPresentationMode"];
    for(NSUInteger index=0;index<contactKeys.count;index++){id value=oldContacts[index];if(value==NSNull.null)[prefs removeObjectForKey:contactKeys[index]];else[prefs setObject:value forKey:contactKeys[index]];}
    if(oldOrder)[prefs setObject:oldOrder forKey:orderKey];else[prefs removeObjectForKey:orderKey];
    if(oldEnabled)[prefs setObject:oldEnabled forKey:enabledKey];else[prefs removeObjectForKey:enabledKey];
    return checks;
}
