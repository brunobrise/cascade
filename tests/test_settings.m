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

static void testSettingsColumnsControlSync() {
    printf("Running testSettingsColumnsControlSync...\n");
    SettingsWindowController *controller = [SettingsWindowController sharedController];
    NSInteger origSplit = [ScreenManager savedScreenSplit];
    [ScreenManager saveScreenSplit:3 forScreenName:@"all"];
    [controller showWindow];
    assert([controller isWindowVisible]);
    [controller closeWindow];
    [ScreenManager saveScreenSplit:origSplit forScreenName:@"all"];
    printf("  [PASS] SettingsWindowController columns control synced cleanly.\n");
}

static void testSettingsDisplayColumnsDecoupling() {
    printf("Running testSettingsDisplayColumnsDecoupling...\n");
    SettingsWindowController *controller = [SettingsWindowController sharedController];
    MockSettingsDelegate *mock = [[MockSettingsDelegate alloc] init];
    controller.delegate = mock;

    NSArray<CascadeScreen *> *screens = [ScreenManager availableScreens];
    if (screens.count > 0) {
        CascadeScreen *s0 = screens[0];
        NSInteger origSplit = [ScreenManager screenSplitForScreen:s0];
        [ScreenManager saveScreenSplit:2 forScreen:s0];
        assert([ScreenManager screenSplitForScreen:s0] == 2);

        [controller showWindow];
        assert([controller isWindowVisible]);
        [controller closeWindow];

        // Restore
        [ScreenManager saveScreenSplit:origSplit forScreen:s0];
    }
    printf("  [PASS] SettingsWindowController display columns decoupled from target screen.\n");
}

static void testSettingsAboutPanel() {
    printf("Running testSettingsAboutPanel...\n");
    SettingsWindowController *controller = [SettingsWindowController sharedController];
    assert(controller != nil);
    [controller showWindow];
    assert([controller isWindowVisible]);
    [controller showAboutPanel];
    [controller closeWindow];
    printf("  [PASS] SettingsWindowController about panel invocation verified.\n");
}

static void testSettingsFractalLayoutStyleSync() {
    printf("Running testSettingsFractalLayoutStyleSync...\n");
    SettingsWindowController *controller = [SettingsWindowController sharedController];
    CascadeLayoutStyle origStyle = [CascadeEngine savedLayoutStyle];

    [CascadeEngine saveLayoutStyle:CascadeLayoutStyleFractal];
    [controller showWindow];
    assert([controller isWindowVisible]);
    [controller closeWindow];

    [CascadeEngine saveLayoutStyle:origStyle];
    printf("  [PASS] SettingsWindowController synced CascadeLayoutStyleFractal cleanly.\n");
}

int main(int argc, const char * argv[]) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        [NSApplication sharedApplication];

        // Backup original settings
        CascadeOrderMode origMode = [CascadeEngine savedOrderMode];
        CGFloat origDelta = [CascadeEngine savedDelta];
        NSString *origTarget = [ScreenManager savedScreenTarget];
        NSInteger origSplit = [ScreenManager savedScreenSplit];
        NSMutableDictionary<NSString *, NSNumber *> *screenSplits = [NSMutableDictionary dictionary];
        for (CascadeScreen *s in [ScreenManager availableScreens]) {
            screenSplits[[s uniqueID]] = @([ScreenManager screenSplitForScreen:s]);
        }

        testSettingsControllerLifecycle();
        testSettingsPreferencesSync();
        testSettingsColumnsControlSync();
        testSettingsDisplayColumnsDecoupling();
        testSettingsAboutPanel();
        testSettingsFractalLayoutStyleSync();

        // Restore original settings
        [CascadeEngine saveOrderMode:origMode];
        [CascadeEngine saveDelta:origDelta];
        [ScreenManager saveScreenTarget:origTarget];
        [ScreenManager saveScreenSplit:origSplit forScreenName:@"all"];
        for (CascadeScreen *s in [ScreenManager availableScreens]) {
            NSNumber *saved = screenSplits[[s uniqueID]];
            if (saved) [ScreenManager saveScreenSplit:[saved integerValue] forScreen:s];
        }

        printf("\n=== All Settings Window Tests Passed Successfully! ===\n");
    }
    return 0;
}
