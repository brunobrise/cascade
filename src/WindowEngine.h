#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>

typedef NS_ENUM(NSInteger, CascadeOrderMode) {
    CascadeOrderModeMRU = 0,          // Front-to-back (Most Recently Used)
    CascadeOrderModeSpatial = 1,      // Left-to-right based on existing X position
    CascadeOrderModeAlphabetical = 2,  // Alphabetical by application name
    CascadeOrderModeCustom = 3        // Preferred application order by name
};

@interface CascadeWindow : NSObject
@property (nonatomic, copy) NSString *appName;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) pid_t pid;
@property (nonatomic, assign) AXUIElementRef axRef;
@property (nonatomic, assign) CGRect currentFrame;
@property (nonatomic, assign) CGRect targetFrame;
@property (nonatomic, assign) NSInteger zRank;
- (BOOL)matchesWindow:(CascadeWindow *)other;
@end

@interface CascadeEngine : NSObject

+ (CGRect)usableScreenFrameWithTopInset:(CGFloat *)outTopInset;
+ (BOOL)isAccessibilityTrustedWithPrompt:(BOOL)prompt;
+ (void)openAccessibilitySettings;
+ (NSArray<CascadeWindow *> *)collectStandardWindowsWithOnly:(NSArray<NSString *> *)onlyApps
                                                      exclude:(NSArray<NSString *> *)excludeApps;
+ (NSUserDefaults *)userDefaults;
+ (CascadeOrderMode)savedOrderMode;
+ (void)saveOrderMode:(CascadeOrderMode)mode;
+ (CGFloat)savedDelta;
+ (void)saveDelta:(CGFloat)delta;
+ (BOOL)savedRestackZOrder;
+ (void)saveRestackZOrder:(BOOL)restack;
+ (BOOL)savedAutoRearrange;
+ (void)saveAutoRearrange:(BOOL)autoRearrange;
+ (NSArray<NSString *> *)preferredAppOrder;
+ (void)setPreferredAppOrder:(NSArray<NSString *> *)order;
+ (NSArray<NSString *> *)parseAppOrderString:(NSString *)string;
+ (NSArray<CascadeWindow *> *)calculateLayoutForWindows:(NSArray<CascadeWindow *> *)windows
                                              orderMode:(CascadeOrderMode)orderMode
                                         preferredOrder:(NSArray<NSString *> *)preferredOrder
                                                  delta:(CGFloat)delta;
+ (NSArray<CascadeWindow *> *)calculateLayoutForWindows:(NSArray<CascadeWindow *> *)windows
                                              orderMode:(CascadeOrderMode)orderMode
                                                  delta:(CGFloat)delta;
+ (NSArray<CascadeWindow *> *)calculateLayoutForWindows:(NSArray<CascadeWindow *> *)windows
                                    preservingOrderFrom:(NSArray<CascadeWindow *> *)previousOrder
                                                  delta:(CGFloat)delta;
+ (void)applyLayoutToWindows:(NSArray<CascadeWindow *> *)windows
                    restackZ:(BOOL)restackZ;

@end
