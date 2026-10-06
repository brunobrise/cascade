#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>

@class WindowWatcher;

@protocol WindowWatcherDelegate <NSObject>
- (void)windowWatcherDidDetectChange:(WindowWatcher *)watcher;
@end

@interface WindowWatcher : NSObject

@property (nonatomic, weak) id<WindowWatcherDelegate> delegate;
@property (nonatomic, readonly) BOOL isWatching;
@property (nonatomic, assign) BOOL isSuppressed;
@property (nonatomic, assign) NSTimeInterval debounceInterval; // default: 0.35s
@property (nonatomic, copy) NSArray<NSString *> *excludeApps;

- (instancetype)initWithDelegate:(id<WindowWatcherDelegate>)delegate;
- (void)startWatching;
- (void)stopWatching;
- (void)refreshObservers;
- (void)scheduleDebouncedChange;
- (void)performWithoutTriggering:(dispatch_block_t)block;

@end
