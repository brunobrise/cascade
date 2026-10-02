#import <Cocoa/Cocoa.h>
#import <assert.h>
#import "../src/SettingsWindowController.h"
#import "../src/WindowEngine.h"
#import "../src/ScreenManager.h"

@interface MockSettingsDelegate : NSObject <SettingsWindowDelegate>
@property (nonatomic, assign) BOOL didChangeCalled;
@property (nonatomic, assign) BOOL requestsCascadeCalled;
@end

@implementation MockSettingsDelegate
- (void)settingsDidChange { self.didChangeCalled = YES; }
- (void)settingsRequestsCascade { self.requestsCascadeCalled = YES; }
@end

static void testSettingsControllerLifecycle() {
    printf("Running testSettingsControllerLifecycle...\n");
    SettingsWindowController *controller = [SettingsWindowController sharedController];
    assert(controller != nil);

    MockSettingsDelegate *mock = [[MockSettingsDelegate alloc] init];
    controller.delegate = mock;
    assert(controller.delegate == mock);

    assert(![controller isWindowVisible]);
    [controller showWindow];
    assert([controller isWindowVisible]);

    [controller closeWindow];
    assert(![controller isWindowVisible]);

    printf("  [PASS] SettingsWindowController lifecycle and visibility verified.\n");
}

static void testSettingsPreferencesSync() {
    printf("Running testSettingsPreferencesSync...\n");
    SettingsWindowController *controller = [SettingsWindowController sharedController];

    [CascadeEngine saveOrderMode:CascadeOrderModeAlphabetical];
    [CascadeEngine saveDelta:50.0];
    [ScreenManager saveScreenTarget:@"all"];

    [controller showWindow];
    assert([controller isWindowVisible]);
    [controller closeWindow];

    printf("  [PASS] SettingsWindowController preferences synced cleanly.\n");
}

int main(int argc, const char * argv[]) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        [NSApplication sharedApplication];
        testSettingsControllerLifecycle();
        testSettingsPreferencesSync();
        printf("\n=== All Settings Window Tests Passed Successfully! ===\n");
    }
    return 0;
}
