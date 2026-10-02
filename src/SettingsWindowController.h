#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@protocol SettingsWindowDelegate <NSObject>
- (void)settingsDidChange;
- (void)settingsRequestsCascade;
@end

@interface SettingsWindowController : NSObject

@property (nonatomic, weak, nullable) id<SettingsWindowDelegate> delegate;

+ (instancetype)sharedController;
- (void)showWindow;
- (void)closeWindow;
- (BOOL)isWindowVisible;

@end

NS_ASSUME_NONNULL_END
