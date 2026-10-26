#import "WPShakeDetector.h"
#import <math.h>

NSInteger WPShakeSensitivityFromPreferenceValue(id value){
    return [value isKindOfClass:NSNumber.class]?MAX(0,MIN(2,[value integerValue])):1;
}

@interface WPShakeDetector ()
@property(nonatomic,readwrite) CGFloat minimumSwing;
@property(nonatomic,readwrite) NSUInteger requiredReversals;
@property(nonatomic,readwrite) NSTimeInterval window;
@property(nonatomic,readwrite) BOOL triggered;
@property(nonatomic) CGFloat origin;
@property(nonatomic) CGFloat extreme;
@property(nonatomic) NSInteger direction;
@property(nonatomic) NSMutableArray<NSNumber *> *reversals;
@property(nonatomic) NSTimeInterval lastTrigger;
@end
@implementation WPShakeDetector
- (instancetype)initWithSensitivity:(NSInteger)sensitivity{
    if((self=[super init])){
        // Swing in points between direction changes, reversals inside the window.
        NSInteger level=MAX(0,MIN(2,sensitivity));
        static const CGFloat swings[]={30,22,16};static const NSUInteger reversals[]={4,3,3};static const NSTimeInterval windows[]={1.2,1.2,1.4};
        _minimumSwing=swings[level];_requiredReversals=reversals[level];_window=windows[level];
        _cooldown=1.5;_lastTrigger=-INFINITY;_reversals=[NSMutableArray new];
    }return self;
}
- (void)beginAtPoint:(CGPoint)point time:(NSTimeInterval)time{
    self.origin=self.extreme=point.x;self.direction=0;self.triggered=NO;[self.reversals removeAllObjects];
}
- (BOOL)addPoint:(CGPoint)point time:(NSTimeInterval)time{
    if(self.triggered)return NO;
    CGFloat x=point.x;
    if(self.direction==0){
        if(fabs(x-self.origin)>=self.minimumSwing){self.direction=x>self.origin?1:-1;self.extreme=x;}
        return NO;
    }
    if((self.direction>0 && x>self.extreme) || (self.direction<0 && x<self.extreme)){self.extreme=x;return NO;}
    if(fabs(self.extreme-x)<self.minimumSwing)return NO;
    self.direction=-self.direction;self.extreme=x;[self.reversals addObject:@(time)];
    while(self.reversals.count && time-self.reversals.firstObject.doubleValue>self.window)[self.reversals removeObjectAtIndex:0];
    if(self.reversals.count<self.requiredReversals || time-self.lastTrigger<self.cooldown)return NO;
    self.triggered=YES;self.lastTrigger=time;return YES;
}
@end
