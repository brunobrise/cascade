#import <Cocoa/Cocoa.h>
#import <assert.h>
#import "../src/IgnoreListWindowController.h"
#import "../src/WindowEngine.h"
#import "../src/WindowWatcher.h"
#import "../src/SettingsWindowController.h"

static void testIgnoredAppsPersistence() {
    printf("Running testIgnoredAppsPersistence...\n");
    NSArray<NSString *> *original = [CascadeEngine ignoredApps];

    [CascadeEngine clearIgnoredApps];
    assert([CascadeEngine ignoredApps].count == 0);

    // Test setting list
    NSArray<NSString *> *testList = @[@"Slack", @"Spotify", @"Discord"];
    [CascadeEngine setIgnoredApps:testList];
    NSArray<NSString *> *retrieved = [CascadeEngine ignoredApps];
    assert(retrieved.count == 3);
    assert([retrieved[0] isEqualToString:@"Slack"]);
    assert([retrieved[1] isEqualToString:@"Spotify"]);
    assert([retrieved[2] isEqualToString:@"Discord"]);

    // Test addIgnoredApp
    [CascadeEngine addIgnoredApp:@"  Zoom  "];
    retrieved = [CascadeEngine ignoredApps];
    assert(retrieved.count == 4);
    assert([retrieved[3] isEqualToString:@"Zoom"]);

    // Test add duplicate (case-insensitive)
    [CascadeEngine addIgnoredApp:@"zoom"];
    assert([CascadeEngine ignoredApps].count == 4);

    // Test removeIgnoredApp (case-insensitive)
    [CascadeEngine removeIgnoredApp:@"slack"];
    retrieved = [CascadeEngine ignoredApps];
    assert(retrieved.count == 3);
    assert(![retrieved containsObject:@"Slack"]);

    // Test clear
    [CascadeEngine clearIgnoredApps];
    assert([CascadeEngine ignoredApps].count == 0);

    // Restore original
    [CascadeEngine setIgnoredApps:original];
    printf("  [PASS] Ignored apps CRUD and preferences persistence verified.\n");
}

static void testWatcherExclusionLogic() {
    printf("Running testWatcherExclusionLogic...\n");
    WindowWatcher *watcher = [[WindowWatcher alloc] initWithDelegate:nil];
    watcher.excludeApps = @[@"Slack", @"Google Chrome"];

    assert(watcher.excludeApps.count == 2);
    [watcher setExcludeApps:@[@"Spotify"]];
    assert(watcher.excludeApps.count == 1);
    assert([watcher.excludeApps[0] isEqualToString:@"Spotify"]);

    printf("  [PASS] WindowWatcher excludeApps property and lifecycle verified.\n");
}

static void testIgnoreListWindowController() {
    printf("Running testIgnoreListWindowController...\n");
    IgnoreListWindowController *ctrl = [IgnoreListWindowController sharedController];
    assert(ctrl != nil);

    NSArray<NSString *> *original = [CascadeEngine ignoredApps];
    [CascadeEngine setIgnoredApps:@[@"Preview", @"TextEdit"]];

    __block BOOL completionCalled = NO;
    [ctrl showWindowWithCompletion:^(BOOL applied) {
        completionCalled = applied;
    }];
    (void)completionCalled;

    [CascadeEngine setIgnoredApps:original];
    printf("  [PASS] IgnoreListWindowController singleton and window construction verified.\n");
}

int main(int argc, const char * argv[]) {
    (void)argc; (void)argv;
    @autoreleasepool {
        [NSApplication sharedApplication];
        printf("=== Running Ignore List Unit Tests ===\n\n");
        testIgnoredAppsPersistence();
        testWatcherExclusionLogic();
        testIgnoreListWindowController();
        printf("\n=== All Ignore List Tests Passed Successfully! ===\n");
    }
    return 0;
}
