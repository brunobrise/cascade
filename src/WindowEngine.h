#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>

typedef NS_ENUM(NSInteger, CascadeOrderMode) {
    CascadeOrderModeMRU = 0,          // Front-to-back (Most Recently Used)
    CascadeOrderModeSpatial = 1,      // Left-to-right based on existing X position
    CascadeOrderModeAlphabetical = 2,  // Alphabetical by application name
    CascadeOrderModeCustom = 3        // Preferred application order by name
};

typedef NS_ENUM(NSInteger, CascadeLayoutStyle) {
    CascadeLayoutStyleDiagonal = 0,  // Traditional top-left to bottom-right cascade
    CascadeLayoutStyleQuadEdge = 1,  // Clockwise perimeter: Top -> Right -> Bottom -> Left
    CascadeLayoutStyleFractal = 2    // Recursive golden ratio subdivision
};

typedef NS_ENUM(NSInteger, CascadeDockEdge) {
    CascadeDockEdgeLeft = 0,
    CascadeDockEdgeRight = 1,
    CascadeDockEdgeTop = 2,
    CascadeDockEdgeBottom = 3
};


@interface CascadeWindow : NSObject
@property (nonatomic, copy) NSString *appName;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) pid_t pid;
@property (nonatomic, assign) AXUIElementRef axRef;
@property (nonatomic, assign) CGRect currentFrame;
@property (nonatomic, assign) CGRect targetFrame;
@property (nonatomic, assign) CGRect usableFrame;
@property (nonatomic, assign) NSInteger zRank;
- (BOOL)matchesWindow:(CascadeWindow *)other;
@end

@interface CascadeEngine : NSObject

+ (CGRect)usableScreenFrameWithTopInset:(CGFloat *)outTopInset;
+ (BOOL)isAccessibilityTrustedWithPrompt:(BOOL)prompt;
+ (void)openAccessibilitySettings;
+ (NSDictionary<NSString *, id> *)accessibilityDiagnostics;
+ (NSArray<CascadeWindow *> *)collectStandardWindowsWithOnly:(NSArray<NSString *> *)onlyApps
                                                      exclude:(NSArray<NSString *> *)excludeApps;
+ (NSUserDefaults *)userDefaults;
+ (CascadeOrderMode)savedOrderMode;
+ (void)saveOrderMode:(CascadeOrderMode)mode;
+ (CascadeLayoutStyle)savedLayoutStyle;
+ (void)saveLayoutStyle:(CascadeLayoutStyle)style;
+ (CGFloat)savedDelta;
+ (void)saveDelta:(CGFloat)delta;
+ (BOOL)savedRestackZOrder;
+ (void)saveRestackZOrder:(BOOL)restack;
+ (BOOL)savedAutoRearrange;
+ (void)saveAutoRearrange:(BOOL)autoRearrange;
+ (NSArray<NSString *> *)preferredAppOrder;
+ (void)setPreferredAppOrder:(NSArray<NSString *> *)order;
+ (NSArray<NSString *> *)ignoredApps;
+ (void)setIgnoredApps:(NSArray<NSString *> *)apps;
+ (void)addIgnoredApp:(NSString *)app;
+ (void)removeIgnoredApp:(NSString *)app;
+ (void)clearIgnoredApps;
+ (NSArray<NSString *> *)parseAppOrderString:(NSString *)string;
+ (NSArray<CascadeWindow *> *)calculateLayoutForWindows:(NSArray<CascadeWindow *> *)windows
                                              orderMode:(CascadeOrderMode)orderMode
                                         preferredOrder:(NSArray<NSString *> *)preferredOrder
                                                  delta:(CGFloat)delta;
+ (NSArray<CascadeWindow *> *)calculateLayoutForWindows:(NSArray<CascadeWindow *> *)windows
                                              orderMode:(CascadeOrderMode)orderMode
                                         preferredOrder:(NSArray<NSString *> *)preferredOrder
                                                  delta:(CGFloat)delta
                                          onUsableFrame:(CGRect)usableFrame;
+ (NSArray<CascadeWindow *> *)calculateLayoutForWindows:(NSArray<CascadeWindow *> *)windows
                                              orderMode:(CascadeOrderMode)orderMode
                                         preferredOrder:(NSArray<NSString *> *)preferredOrder
                                                  delta:(CGFloat)delta
                                            layoutStyle:(CascadeLayoutStyle)layoutStyle
                                          onUsableFrame:(CGRect)usableFrame;
+ (NSArray<CascadeWindow *> *)calculateLayoutForWindows:(NSArray<CascadeWindow *> *)windows
                                              orderMode:(CascadeOrderMode)orderMode
                                                  delta:(CGFloat)delta;
+ (NSArray<CascadeWindow *> *)calculateLayoutForWindows:(NSArray<CascadeWindow *> *)windows
                                    preservingOrderFrom:(NSArray<CascadeWindow *> *)previousOrder
                                                  delta:(CGFloat)delta;
+ (NSArray<CascadeWindow *> *)calculateLayoutForWindows:(NSArray<CascadeWindow *> *)windows
                                    preservingOrderFrom:(NSArray<CascadeWindow *> *)previousOrder
                                                  delta:(CGFloat)delta
                                          onUsableFrame:(CGRect)usableFrame;
+ (NSArray<CascadeWindow *> *)calculateLayoutForWindows:(NSArray<CascadeWindow *> *)windows
                                    preservingOrderFrom:(NSArray<CascadeWindow *> *)previousOrder
                                                  delta:(CGFloat)delta
                                            layoutStyle:(CascadeLayoutStyle)layoutStyle
                                          onUsableFrame:(CGRect)usableFrame;
+ (NSArray<NSDictionary<NSString *, NSString *> *> *)serializeWindows:(NSArray<CascadeWindow *> *)windows;
+ (NSArray<CascadeWindow *> *)matchWindows:(NSArray<CascadeWindow *> *)currentWindows
                      withSavedDescriptors:(NSArray<NSDictionary<NSString *, NSString *> *> *)saved;
+ (NSArray<NSDictionary<NSString *, NSString *> *> *)savedEstablishedWindowOrder;
+ (void)saveEstablishedWindowOrder:(NSArray<CascadeWindow *> *)windows;
+ (CGRect)clampedFrameForTargetFrame:(CGRect)targetFrame
                          actualSize:(CGSize)actualSize
                         usableFrame:(CGRect)usableFrame;
+ (void)applyLayoutToWindows:(NSArray<CascadeWindow *> *)windows
                    restackZ:(BOOL)restackZ;
+ (CascadeWindow *)frontmostStandardWindow;
+ (CascadeDockEdge)parseDockEdgeString:(NSString *)string;
+ (CascadeLayoutStyle)parseLayoutStyleString:(NSString *)string;
+ (NSString *)nameForLayoutStyle:(CascadeLayoutStyle)style;
+ (BOOL)toggleZoomActiveWindow;
+ (BOOL)dockActiveWindowWithEdge:(CascadeDockEdge)edge layoutStyle:(CascadeLayoutStyle)style delta:(CGFloat)delta;

// Fractal Manual Window Positions
+ (void)saveFractalPositionForWindow:(CascadeWindow *)window onUsableFrame:(CGRect)usableFrame;
+ (void)saveFractalPositionsForWindows:(NSArray<CascadeWindow *> *)windows onUsableFrame:(CGRect)usableFrame;
+ (NSValue *)savedFractalPositionForWindow:(CascadeWindow *)window onUsableFrame:(CGRect)usableFrame;
+ (NSDictionary<NSString *, NSDictionary<NSString *, NSNumber *> *> *)allSavedFractalPositions;
+ (void)clearSavedFractalPositions;

// Fractal Area Selection & Zoom
+ (NSArray<CascadeWindow *> *)windowsIntersectingQuartzRect:(CGRect)rect inWindows:(NSArray<CascadeWindow *> *)windows;
+ (BOOL)isFractalZoomed;
+ (BOOL)zoomFractalWindows:(NSArray<CascadeWindow *> *)selectedWindows onUsableFrame:(CGRect)usableFrame;
+ (BOOL)zoomFractalWindowsInQuartzRect:(CGRect)selectionRect onUsableFrame:(CGRect)usableFrame;
+ (BOOL)resetFractalZoom;

@end
