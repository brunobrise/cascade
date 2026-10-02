#import <Cocoa/Cocoa.h>

@interface CascadeScreen : NSObject
@property (nonatomic, assign) NSInteger index;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *displayID;
@property (nonatomic, assign) BOOL isPrimary;
@property (nonatomic, assign) CGRect cocoaFrame;
@property (nonatomic, assign) CGRect cocoaVisibleFrame;
@property (nonatomic, assign) CGRect quartzFrame;
@property (nonatomic, assign) CGRect quartzVisibleFrame;
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

@end
