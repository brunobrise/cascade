#import <Cocoa/Cocoa.h>
#import "WindowEngine.h"

@interface WindowLayoutGeometry : NSObject

+ (void)assignDiagonalFramesToOrderedWindows:(NSArray<CascadeWindow *> *)ordered
                               onUsableFrame:(CGRect)usable
                                       delta:(CGFloat)delta;

+ (void)assignQuadEdgeFramesToOrderedWindows:(NSArray<CascadeWindow *> *)ordered
                               onUsableFrame:(CGRect)usable
                                       delta:(CGFloat)delta;

+ (void)assignFractalFramesToOrderedWindows:(NSArray<CascadeWindow *> *)ordered
                              onUsableFrame:(CGRect)usable
                                      delta:(CGFloat)delta;

+ (void)assignDockedFramesToWindows:(NSArray<CascadeWindow *> *)windows
                  activeWindowIndex:(NSUInteger)activeIdx
                               edge:(CascadeDockEdge)edge
                      onUsableFrame:(CGRect)usable
                              delta:(CGFloat)delta
                        layoutStyle:(CascadeLayoutStyle)style;

+ (void)assignFramesToOrderedWindows:(NSArray<CascadeWindow *> *)ordered
                       onUsableFrame:(CGRect)usable
                               delta:(CGFloat)delta
                         layoutStyle:(CascadeLayoutStyle)style;

@end

