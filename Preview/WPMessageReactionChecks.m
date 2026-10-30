#import "WPMessageReactionChecks.h"
#import "WPPetRenderer.h"
#import <QuartzCore/QuartzCore.h>

static BOOL WPMessageSamePosition(WPPetRenderer *pet, CGPoint center) {
    return CGPointEqualToPoint(pet.center, center);
}

NSDictionary<NSString *, NSNumber *> *WPMessageReactionPreviewChecks(void) {
    NSMutableDictionary<NSString *, NSNumber *> *checks = [NSMutableDictionary new];
    WPPetRenderer *pet = nil;
    @try {
        pet = [[WPPetRenderer alloc] initWithFrame:CGRectMake(168, 310, 88, 96)];
        [pet setAnimationActive:YES];
        CGPoint center = pet.center;
        NSInteger frameRate = [[pet valueForKey:@"frameRate"] integerValue];
        CGRect bounds = pet.bounds;

        BOOL accepted = [pet playMessageAcknowledgement];
        CFTimeInterval started = [[pet valueForKey:@"animationStartedAt"] doubleValue];
        CFTimeInterval until = [[pet valueForKey:@"greetingUntil"] doubleValue];
        checks[@"messageReactionIdleUsesExistingTap"] = @(accepted && [[pet valueForKey:@"reactionKind"] isEqual:@"tap"]);
        checks[@"messageReactionDoesNotMoveOrResizePet"] = @(WPMessageSamePosition(pet, center) && CGRectEqualToRect(pet.bounds, bounds));
        checks[@"messageReactionKeepsExistingTimingAndFrameRate"] = @(
            [[pet valueForKey:@"frameRate"] integerValue] == frameRate &&
            fabs((until - started) - (CGFloat)[[pet valueForKey:@"frameCount"] integerValue] / MAX(1, frameRate)) < .0001);
        checks[@"messageReactionDoesNotRestartCurrentTap"] = @(![pet playMessageAcknowledgement] &&
            [[pet valueForKey:@"animationStartedAt"] doubleValue] == started &&
            [[pet valueForKey:@"greetingUntil"] doubleValue] == until && [pet valueForKey:@"queuedReaction"] == nil);

        [pet setValue:nil forKey:@"reactionKind"];
        [pet setValue:@0 forKey:@"greetingUntil"];
        pet.angry = YES;
        NSInteger angryRow = [[pet valueForKey:@"animationRow"] integerValue];
        checks[@"messageReactionPreservesAnger"] = @(![pet playMessageAcknowledgement] && pet.angry &&
            [[pet valueForKey:@"animationRow"] integerValue] == angryRow && WPMessageSamePosition(pet, center));

        pet.angry = NO;
        [pet beginDragAnimation];
        NSInteger dragRow = [[pet valueForKey:@"dragRow"] integerValue];
        checks[@"messageReactionPreservesDrag"] = @(![pet playMessageAcknowledgement] &&
            dragRow >= 0 && [[pet valueForKey:@"dragRow"] integerValue] == dragRow &&
            [[pet valueForKey:@"animationRow"] integerValue] == dragRow && WPMessageSamePosition(pet, center));
        [pet endDragAnimation];

        [pet holdPeekOnLeft:YES];
        NSInteger peekRow = [[pet valueForKey:@"heldPeekRow"] integerValue];
        checks[@"messageReactionPreservesHeldPeek"] = @(![pet playMessageAcknowledgement] &&
            peekRow >= 0 && [[pet valueForKey:@"heldPeekRow"] integerValue] == peekRow &&
            [[pet valueForKey:@"animationRow"] integerValue] == peekRow && WPMessageSamePosition(pet, center));
        [pet endPeek];

        [pet playReaction:@"anger"];
        NSString *reaction = [[pet valueForKey:@"reactionKind"] copy];
        started = [[pet valueForKey:@"animationStartedAt"] doubleValue];
        checks[@"messageReactionPreservesCurrentInteraction"] = @(![pet playMessageAcknowledgement] &&
            [reaction isEqual:[pet valueForKey:@"reactionKind"]] &&
            [[pet valueForKey:@"animationStartedAt"] doubleValue] == started && WPMessageSamePosition(pet, center));

        [pet playReaction:@"miss"];
        NSString *queued = [[pet valueForKey:@"queuedReaction"] copy];
        [pet setValue:@0 forKey:@"greetingUntil"];
        checks[@"messageReactionDoesNotDiscardQueuedInteraction"] = @(queued.length > 0 &&
            ![pet playMessageAcknowledgement] && [queued isEqual:[pet valueForKey:@"queuedReaction"]]);

        [pet setValue:nil forKey:@"queuedReaction"];
        [pet setValue:nil forKey:@"reactionKind"];
        pet.hidden = YES;
        checks[@"messageReactionHiddenPetStaysIdle"] = @(![pet playMessageAcknowledgement] && [pet valueForKey:@"reactionKind"] == nil);
        pet.hidden = NO;
        [pet setAnimationActive:NO];
        checks[@"messageReactionPausedPetDoesNotWakeOrAllocate"] = @(![pet playMessageAcknowledgement] &&
            [pet valueForKey:@"displayLink"] == nil && [pet valueForKey:@"atlas"] == nil &&
            [pet valueForKey:@"reactionKind"] == nil && WPMessageSamePosition(pet, center));
    } @catch (__unused NSException *exception) {
        checks[@"messageReactionNoUnexpectedException"] = @NO;
    } @finally {
        [pet setAnimationActive:NO];
    }
    return checks;
}
