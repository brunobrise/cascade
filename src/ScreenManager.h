#import <Cocoa/Cocoa.h>

@class CascadeWindow;

@interface CascadeScreen : NSObject <NSCopying>
@property (nonatomic, assign) NSInteger index;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *displayID;
@property (nonatomic, assign) BOOL isPrimary;
@property (nonatomic, assign) CGRect cocoaFrame;
@property (nonatomic, assign) CGRect cocoaVisibleFrame;
@property (nonatomic, assign) CGRect quartzFrame;
@property (nonatomic, assign) CGRect quartzVisibleFrame;
@property (nonatomic, assign) NSInteger columnIndex;
@property (nonatomic, assign) NSInteger totalColumns;
@end

@interface ScreenManager : NSObject

+ (NSArray<CascadeScreen *> *)availableScreens;
+ (CascadeScreen *)primaryScreen;
+ (CascadeScreen *)activeScreen;
+ (CascadeScreen *)screenForPointer;
+ (CascadeScreen *)screenForPointerInScreens:(NSArray<CascadeScreen *> *)screens;
+ (CascadeScreen *)screenForCocoaPoint:(NSPoint)cocoaPoint inScreens:(NSArray<CascadeScreen *> *)screens;
+ (CascadeScreen *)screenForFrame:(CGRect)quartzFrame;
+ (CascadeScreen *)screenForFrame:(CGRect)quartzFrame inScreens:(NSArray<CascadeScreen *> *)screens;
+ (CGRect)convertCocoaFrameToQuartz:(CGRect)cocoaFrame primaryScreenHeight:(CGFloat)h0;
+ (NSString *)savedScreenTarget;
+ (void)saveScreenTarget:(NSString *)target;
+ (NSArray<CascadeScreen *> *)screensMatchingTarget:(NSString *)target;
+ (NSArray<CascadeScreen *> *)screensMatchingTarget:(NSString *)target inScreens:(NSArray<CascadeScreen *> *)screens;

+ (NSInteger)savedScreenSplit;
+ (void)saveScreenSplit:(NSInteger)split;
+ (NSInteger)screenSplitForScreen:(CascadeScreen *)screen;
+ (void)saveScreenSplit:(NSInteger)split forScreenName:(NSString *)name;
+ (NSArray<CascadeScreen *> *)subscreensForScreen:(CascadeScreen *)screen splitCount:(NSInteger)k;
+ (NSArray<CascadeScreen *> *)expandScreensWithSplits:(NSArray<CascadeScreen *> *)screens;
+ (NSDictionary<CascadeScreen *, NSArray<CascadeWindow *> *> *)partitionWindows:(NSArray<CascadeWindow *> *)windows intoScreens:(NSArray<CascadeScreen *> *)screens;

@end
