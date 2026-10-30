#import "WPMenuIcons.h"
#import <math.h>

UIImage *WPMomentsMenuIcon(void){
    static UIImage *icon;static dispatch_once_t once;dispatch_once(&once,^{
        UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat defaultFormat];format.opaque=NO;format.scale=3;
        UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(48,48) format:format];
        icon=[[renderer imageWithActions:^(UIGraphicsImageRendererContext *context){
            CGFloat radius=21,inner=radius*.4,step=M_PI/4;
            CGPoint q=CGPointMake(inner,0),next=CGPointMake(inner*cos(step),inner*sin(step));
            CGPoint d=CGPointMake(next.x-q.x,next.y-q.y);CGFloat dd=d.x*d.x+d.y*d.y,qd=q.x*d.x+q.y*d.y;
            CGFloat t=(qd+sqrt(qd*qd+dd*(radius*radius-inner*inner)))/dd;
            CGFloat rotation=-M_PI_2-atan2(q.y-t*d.y,q.x-t*d.x);
            NSArray<UIColor *> *colors=@[
                [UIColor colorWithRed:1 green:.23 blue:.34 alpha:1],[UIColor colorWithRed:.52 green:.26 blue:1 alpha:1],
                [UIColor colorWithRed:.15 green:.43 blue:1 alpha:1],[UIColor colorWithRed:.03 green:.72 blue:.94 alpha:1],
                [UIColor colorWithRed:.05 green:.74 blue:.34 alpha:1],[UIColor colorWithRed:.45 green:.78 blue:.13 alpha:1],
                [UIColor colorWithRed:1 green:.78 blue:.04 alpha:1],[UIColor colorWithRed:1 green:.48 blue:.10 alpha:1]];
            for(NSUInteger i=0;i<8;i++){
                CGFloat start=-M_PI_2+i*step,end=start+step;
                UIBezierPath *arc=[UIBezierPath bezierPathWithArcCenter:CGPointMake(24,24) radius:radius startAngle:start endAngle:end clockwise:YES];
                arc.lineWidth=1.8;arc.lineCapStyle=kCGLineCapRound;[colors[i] setStroke];[arc stroke];
                CGFloat innerAngle=rotation+(i+1)*step;
                UIBezierPath *blade=[UIBezierPath bezierPath];[blade moveToPoint:CGPointMake(24+radius*cos(start),24+radius*sin(start))];
                [blade addLineToPoint:CGPointMake(24+inner*cos(innerAngle),24+inner*sin(innerAngle))];blade.lineWidth=1.8;blade.lineCapStyle=kCGLineCapRound;[blade stroke];
            }
        }] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    });return icon;
}

UIImage *WPBrokenHeartMenuIcon(void){
    static UIImage *icon;static dispatch_once_t once;dispatch_once(&once,^{
        UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat defaultFormat];format.opaque=NO;format.scale=3;
        UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(34,34) format:format];
        icon=[[renderer imageWithActions:^(UIGraphicsImageRendererContext *context){
            UIBezierPath *heart=[UIBezierPath bezierPath];[heart moveToPoint:CGPointMake(17,31)];
            [heart addCurveToPoint:CGPointMake(3,9) controlPoint1:CGPointMake(6,23) controlPoint2:CGPointMake(0,17)];
            [heart addCurveToPoint:CGPointMake(17,7) controlPoint1:CGPointMake(5,1) controlPoint2:CGPointMake(13,1)];
            [heart addCurveToPoint:CGPointMake(31,9) controlPoint1:CGPointMake(22,1) controlPoint2:CGPointMake(29,1)];
            [heart addCurveToPoint:CGPointMake(17,31) controlPoint1:CGPointMake(35,17) controlPoint2:CGPointMake(27,24)];[heart closePath];
            [UIColor.systemGrayColor setFill];[heart fill];
            CGContextSetBlendMode(context.CGContext,kCGBlendModeClear);
            UIBezierPath *crack=[UIBezierPath bezierPath];[crack moveToPoint:CGPointMake(18,1)];
            for(NSValue *point in @[[NSValue valueWithCGPoint:CGPointMake(14,11)],[NSValue valueWithCGPoint:CGPointMake(20,15)],[NSValue valueWithCGPoint:CGPointMake(14,21)],[NSValue valueWithCGPoint:CGPointMake(18,34)]])[crack addLineToPoint:point.CGPointValue];
            crack.lineWidth=2.4;crack.lineJoinStyle=kCGLineJoinMiter;[crack stroke];
        }] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    });return icon;
}
