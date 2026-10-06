#import <Cocoa/Cocoa.h>
#import "WindowEngine.h"

@interface WindowLayoutGeometry : NSObject

+ (void)assignDiagonalFramesToOrderedWindows:(NSArray<CascadeWindow *> *)ordered
                               onUsableFrame:(CGRect)usable
                                       delta:(CGFloat)delta;

+ (void)assignQuadEdgeFramesToOrderedWindows:(NSArray<CascadeWindow *> *)ordered
                               onUsableFrame:(CGRect)usable
                                       delta:(CGFloat)delta;

+ (void)assignFramesToOrderedWindows:(NSArray<CascadeWindow *> *)ordered
                       onUsableFrame:(CGRect)usable
                               delta:(CGFloat)delta
                         layoutStyle:(CascadeLayoutStyle)style;

@end
