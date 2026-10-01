#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>

typedef NS_ENUM(NSInteger, CascadeOrderMode) {
    CascadeOrderModeMRU = 0,         // Front-to-back (Most Recently Used)
    CascadeOrderModeSpatial = 1,     // Left-to-right based on existing X position
    CascadeOrderModeAlphabetical = 2 // Alphabetical by application name
};

@interface CascadeWindow : NSObject
@property (nonatomic, copy) NSString *appName;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) pid_t pid;
@property (nonatomic, assign) AXUIElementRef axRef;
@property (nonatomic, assign) CGRect currentFrame;
@property (nonatomic, assign) CGRect targetFrame;
@property (nonatomic, assign) NSInteger zRank;
@end

@interface CascadeEngine : NSObject

+ (CGRect)usableScreenFrameWithTopInset:(CGFloat *)outTopInset;
+ (NSArray<CascadeWindow *> *)collectStandardWindowsWithOnly:(NSArray<NSString *> *)onlyApps
                                                      exclude:(NSArray<NSString *> *)excludeApps;
+ (NSArray<CascadeWindow *> *)calculateLayoutForWindows:(NSArray<CascadeWindow *> *)windows
                                              orderMode:(CascadeOrderMode)orderMode
                                                  delta:(CGFloat)delta;
+ (void)applyLayoutToWindows:(NSArray<CascadeWindow *> *)windows
                    restackZ:(BOOL)restackZ;

@end
