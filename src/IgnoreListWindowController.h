#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface IgnoreListWindowController : NSObject <NSTableViewDataSource, NSTableViewDelegate>

+ (instancetype)sharedController;
- (void)showWindowWithCompletion:(nullable void (^)(BOOL applied))completion;

@end

NS_ASSUME_NONNULL_END
