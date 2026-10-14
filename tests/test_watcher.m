#import <Foundation/Foundation.h>
#import <assert.h>
#import "../src/WindowWatcher.h"

@interface TestWatcherDelegate : NSObject <WindowWatcherDelegate>
@property (nonatomic, assign) BOOL changeDetected;
@end

@implementation TestWatcherDelegate
- (void)windowWatcherDidDetectChange:(WindowWatcher *)watcher {
    (void)watcher;
    self.changeDetected = YES;
}
@end

int main(int argc, const char * argv[]) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        printf("Running WindowWatcher tests...\n");

        TestWatcherDelegate *delegate = [[TestWatcherDelegate alloc] init];
        WindowWatcher *watcher = [[WindowWatcher alloc] initWithDelegate:delegate];
        watcher.debounceInterval = 0.05; // 50ms for fast testing

        assert(!watcher.isWatching);

        // 1. Test startWatching
        [watcher startWatching];
        assert(watcher.isWatching);
        printf("  [PASS] startWatching initialized successfully.\n");

        // 2. Test debounced callback
        [watcher scheduleDebouncedChange];
        assert(!delegate.changeDetected); // Not called synchronously

        // Run runloop until debounce timer fires (up to 0.5s timeout)
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:0.5];
        while (!delegate.changeDetected && [deadline timeIntervalSinceNow] > 0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
        }
        assert(delegate.changeDetected);
        printf("  [PASS] Debounced lifecycle change callback fired.\n");

        // 3. Test suppression (Cascade apply layout without triggering watcher)
        delegate.changeDetected = NO;
        [watcher performWithoutTriggering:^{
            [watcher scheduleDebouncedChange];
        }];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        assert(!delegate.changeDetected);
        printf("  [PASS] performWithoutTriggering successfully suppressed notification.\n");

        // 4. Test stopWatching
        [watcher stopWatching];
        assert(!watcher.isWatching);
        printf("  [PASS] stopWatching cleaned up observers.\n");

        printf("=== WindowWatcher Tests Passed! ===\n");
    }
    return 0;
}
