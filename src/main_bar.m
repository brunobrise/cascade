#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import "WindowEngine.h"
#import "ScreenManager.h"
#import "LoginItemManager.h"
#import "WindowWatcher.h"
#import "AppOrderWindowController.h"
#import "SettingsWindowController.h"
#import "UpdateChecker.h"
#import "SelectionOverlayController.h"

@interface CascadeBarApp : NSObject <NSApplicationDelegate, WindowWatcherDelegate, NSMenuDelegate, SettingsWindowDelegate>
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) NSMenu *statusMenu;
@property (nonatomic, assign) CascadeOrderMode orderMode;
@property (nonatomic, copy) NSString *targetScreen;
@property (nonatomic, assign) CGFloat delta;
@property (nonatomic, assign) BOOL restackZOrder;
@property (nonatomic, assign) EventHotKeyRef hotKeyRef;
@property (nonatomic, assign) EventHotKeyRef zoomHotKeyRef;
@property (nonatomic, assign) EventHotKeyRef areaZoomHotKeyRef;
@property (nonatomic, strong) WindowWatcher *watcher;
@property (nonatomic, strong) NSArray<CascadeWindow *> *establishedOrder;
- (void)performCascade:(id)sender;
- (void)cascadeWindowsOnTargetScreensWithRestack:(BOOL)restack preserveOrder:(BOOL)preserveOrder;
- (void)openSettings:(id)sender;
- (void)toggleAreaZoom:(id)sender;
- (void)rememberWindowPositionsAction:(id)sender;
- (void)resetWindowPositionsAction:(id)sender;
@end

static OSStatus HotKeyHandler(EventHandlerCallRef nextHandler, EventRef theEvent, void *userData) {
    (void)nextHandler;
    CascadeBarApp *app = (__bridge CascadeBarApp *)userData;
    EventHotKeyID hkID;
    if (GetEventParameter(theEvent, kEventParamDirectObject, typeEventHotKeyID, NULL, sizeof(hkID), NULL, &hkID) == noErr) {
        if (hkID.id == 2) {
            [CascadeEngine toggleZoomActiveWindow];
            return noErr;
        } else if (hkID.id == 3) {
            [app toggleAreaZoom:nil];
            return noErr;
        }
    }
    [app performCascade:nil];
    return noErr;
}

static NSMenuItem *makeItem(NSString *title, id target, SEL action, NSControlStateValue state) {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:@""];
    item.target = target;
    item.state = state;
    return item;
}

@implementation CascadeBarApp
- (NSImage *)cascadeAppIcon {
    NSImage *icon = [NSImage imageNamed:@"AppIcon"];
    if (!icon) {
        NSString *p = [[NSBundle mainBundle] pathForResource:@"AppIcon" ofType:@"icns"];
        if (p) icon = [[NSImage alloc] initWithContentsOfFile:p];
    }
    return icon;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    self.orderMode = [CascadeEngine savedOrderMode];
    self.delta = [CascadeEngine savedDelta];
    self.restackZOrder = [CascadeEngine savedRestackZOrder];
    self.targetScreen = [ScreenManager savedScreenTarget];
    NSImage *appIcon = [self cascadeAppIcon];
    if (appIcon) [NSApp setApplicationIconImage:appIcon];

    self.watcher = [[WindowWatcher alloc] initWithDelegate:self];
    self.watcher.excludeApps = [CascadeEngine ignoredApps];
    if ([CascadeEngine savedAutoRearrange]) [self.watcher startWatching];

    [CascadeEngine isAccessibilityTrustedWithPrompt:YES];
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                           selector:@selector(checkPermissionsChange)
                                                               name:NSWorkspaceDidActivateApplicationNotification
                                                             object:nil];
    [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(checkPermissionsChange) userInfo:nil repeats:YES];

    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    NSStatusBarButton *button = self.statusItem.button;
    if (button) {
        NSImage *icon = [NSImage imageWithSystemSymbolName:@"macwindow.on.rectangle" accessibilityDescription:@"Cascade"];
        if (icon) {
            NSImageSymbolConfiguration *cfg = [NSImageSymbolConfiguration configurationWithPointSize:13.0 weight:NSFontWeightMedium];
            button.image = [icon imageWithSymbolConfiguration:cfg] ?: icon;
            [button.image setTemplate:YES];
            button.imagePosition = NSImageOnly; button.title = @"";
        } else {
            button.title = @"⧉"; button.font = [NSFont boldSystemFontOfSize:15.0];
        }
        button.toolTip = @"Cascade (Click to arrange or configure)";
    }
    [self rebuildMenu];

    EventTypeSpec eventType = { kEventClassKeyboard, kEventHotKeyPressed };
    InstallApplicationEventHandler(&HotKeyHandler, 1, &eventType, (__bridge void *)self, NULL);
    EventHotKeyID hotKeyID = { 'CSCD', 1 };
    RegisterEventHotKey(0x08, cmdKey | optionKey, hotKeyID, GetApplicationEventTarget(), 0, &_hotKeyRef);
    EventHotKeyID zoomHotKeyID = { 'CSCD', 2 };
    RegisterEventHotKey(0x31, cmdKey | optionKey, zoomHotKeyID, GetApplicationEventTarget(), 0, &_zoomHotKeyRef);
    EventHotKeyID areaZoomHotKeyID = { 'CSCD', 3 };
    RegisterEventHotKey(0x06, cmdKey | optionKey, areaZoomHotKeyID, GetApplicationEventTarget(), 0, &_areaZoomHotKeyRef);

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(screensDidChange:) name:NSApplicationDidChangeScreenParametersNotification object:nil];
    [SettingsWindowController sharedController].delegate = self;

    NSArray *savedOrder = [CascadeEngine savedEstablishedWindowOrder];
    if (savedOrder.count > 0 && [CascadeEngine isAccessibilityTrustedWithPrompt:NO]) {
        NSArray<CascadeWindow *> *wins = [CascadeEngine collectStandardWindowsWithOnly:nil exclude:[CascadeEngine ignoredApps]];
        if (wins.count > 0) self.establishedOrder = [CascadeEngine matchWindows:wins withSavedDescriptors:savedOrder];
    }

    // Schedule background update check (delayed 10s after launch for zero startup overhead)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self runBackgroundUpdateCheck];
    });
    [NSTimer scheduledTimerWithTimeInterval:86400.0 target:self selector:@selector(runBackgroundUpdateCheck) userInfo:nil repeats:YES];
}

- (void)rebuildMenu {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Cascade"];
    menu.delegate = self;
    if (![CascadeEngine isAccessibilityTrustedWithPrompt:NO]) {
        [menu addItem:makeItem(@"⚠️ Grant Accessibility Permission...", self, @selector(openAccessibilitySettings:), NSControlStateValueOff)];
        [menu addItem:[NSMenuItem separatorItem]];
    }

    CascadeUpdateState *updateState = [UpdateChecker loadStateFromPath:nil];
    if (updateState && [UpdateChecker isVersion:updateState.latestVersion newerThan:[UpdateChecker currentVersion]]) {
        NSString *title = [NSString stringWithFormat:@"✨ Update Available: v%@...", updateState.latestVersion];
        NSMenuItem *updateItem = makeItem(title, self, @selector(openReleasePage:), NSControlStateValueOff);
        [menu addItem:updateItem];
        [menu addItem:[NSMenuItem separatorItem]];
    }

    NSMenuItem *cascadeItem = makeItem(@"Cascade Windows", self, @selector(performCascade:), NSControlStateValueOff);
    cascadeItem.keyEquivalent = @"c";
    cascadeItem.keyEquivalentModifierMask = NSEventModifierFlagOption | NSEventModifierFlagCommand;
    [menu addItem:cascadeItem];
    if ([ScreenManager availableScreens].count > 1) {
        [menu addItem:makeItem(@"Cascade All Screens", self, @selector(performCascadeAllScreens:), NSControlStateValueOff)];
    }

    NSMenuItem *zoomItem = makeItem(@"Toggle Focus Zoom", self, @selector(toggleZoomMenuAction:), NSControlStateValueOff);
    zoomItem.keyEquivalent = @" ";
    zoomItem.keyEquivalentModifierMask = NSEventModifierFlagOption | NSEventModifierFlagCommand;
    [menu addItem:zoomItem];

    BOOL isZoomed = [CascadeEngine isFractalZoomed];
    NSMenuItem *areaZoomItem = makeItem(isZoomed ? @"Exit Zoom (Restore Windows)" : @"Select Area to Zoom...", self, @selector(toggleAreaZoom:), isZoomed ? NSControlStateValueOn : NSControlStateValueOff);
    areaZoomItem.keyEquivalent = @"z";
    areaZoomItem.keyEquivalentModifierMask = NSEventModifierFlagOption | NSEventModifierFlagCommand;
    [menu addItem:areaZoomItem];

    NSMenuItem *dockMenu = [[NSMenuItem alloc] initWithTitle:@"Dock Active Window" action:nil keyEquivalent:@""];
    NSMenu *dockSubmenu = [[NSMenu alloc] initWithTitle:@"Dock Active Window"];
    [dockSubmenu addItem:makeItem(@"Dock Left", self, @selector(dockLeftAction:), NSControlStateValueOff)];
    [dockSubmenu addItem:makeItem(@"Dock Right", self, @selector(dockRightAction:), NSControlStateValueOff)];
    [dockSubmenu addItem:makeItem(@"Dock Top", self, @selector(dockTopAction:), NSControlStateValueOff)];
    [dockSubmenu addItem:makeItem(@"Dock Bottom", self, @selector(dockBottomAction:), NSControlStateValueOff)];
    [dockMenu setSubmenu:dockSubmenu];
    [menu addItem:dockMenu];

    if ([CascadeEngine savedLayoutStyle] == CascadeLayoutStyleFractal) {
        [menu addItem:[NSMenuItem separatorItem]];
        [menu addItem:makeItem(@"Remember Window Positions", self, @selector(rememberWindowPositionsAction:), NSControlStateValueOff)];
        [menu addItem:makeItem(@"Reset Window Positions", self, @selector(resetWindowPositionsAction:), NSControlStateValueOff)];
    }

    [menu addItem:[NSMenuItem separatorItem]];

    [menu addItem:makeItem(@"Auto-Rearrange Windows", self, @selector(toggleAutoRearrange:), self.watcher.isWatching ? NSControlStateValueOn : NSControlStateValueOff)];
    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *settingsItem = makeItem(@"Settings...", self, @selector(openSettings:), NSControlStateValueOff);
    settingsItem.keyEquivalent = @",";
    settingsItem.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    [menu addItem:settingsItem];

    NSMenuItem *checkUpdatesItem = makeItem(@"Check for Updates...", self, @selector(checkForUpdatesMenuAction:), NSControlStateValueOff);
    [menu addItem:checkUpdatesItem];
    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *quitItem = makeItem(@"Quit Cascade", self, @selector(quitCascade:), NSControlStateValueOff);
    quitItem.keyEquivalent = @"q";
    [menu addItem:quitItem];

    self.statusMenu = menu;
    self.statusItem.menu = menu;
}

- (void)openSettings:(id)sender {
    (void)sender;
    [SettingsWindowController sharedController].delegate = self;
    [[SettingsWindowController sharedController] showWindow];
}

- (void)settingsDidChange {
    self.orderMode = [CascadeEngine savedOrderMode];
    self.delta = [CascadeEngine savedDelta];
    self.targetScreen = [ScreenManager savedScreenTarget];
    self.restackZOrder = [CascadeEngine savedRestackZOrder];
    self.watcher.excludeApps = [CascadeEngine ignoredApps];
    self.establishedOrder = nil;
    [CascadeEngine saveEstablishedWindowOrder:@[]];
    if ([CascadeEngine savedAutoRearrange] && !self.watcher.isWatching) {
        [self.watcher startWatching];
    } else if (![CascadeEngine savedAutoRearrange] && self.watcher.isWatching) {
        [self.watcher stopWatching];
    }
    [self rebuildMenu];
    [self cascadeWindowsOnTargetScreensWithRestack:self.restackZOrder preserveOrder:NO];
}

- (void)settingsRequestsCascade {
    self.establishedOrder = nil;
    [CascadeEngine saveEstablishedWindowOrder:@[]];
    [self cascadeWindowsOnTargetScreensWithRestack:self.restackZOrder preserveOrder:NO];
}

- (void)toggleZoomMenuAction:(id)sender {
    (void)sender;
    if (![self ensureAccessibility]) return;
    [CascadeEngine toggleZoomActiveWindow];
}

- (void)toggleAreaZoom:(id)sender {
    (void)sender;
    if (![self ensureAccessibility]) return;
    if ([CascadeEngine isFractalZoomed]) {
        [CascadeEngine resetFractalZoom];
        [self rebuildMenu];
        return;
    }
    CascadeScreen *screen = [ScreenManager screenForPointer];
    NSScreen *targetNSScreen = nil;
    if (screen) {
        for (NSScreen *ns in [NSScreen screens]) {
            NSNumber *dNum = ns.deviceDescription[@"NSScreenNumber"];
            if (dNum && [dNum.stringValue isEqualToString:screen.displayID]) {
                targetNSScreen = ns;
                break;
            }
        }
    }
    if (!targetNSScreen) targetNSScreen = [NSScreen mainScreen];

    [[SelectionOverlayController sharedController] startSelectionOnScreen:targetNSScreen completion:^(CGRect quartzRect, BOOL cancelled) {
        if (cancelled || CGRectIsNull(quartzRect)) return;
        CGRect usable = screen ? screen.quartzVisibleFrame : [CascadeEngine usableScreenFrameWithTopInset:nil];
        BOOL ok = [CascadeEngine zoomFractalWindowsInQuartzRect:quartzRect onUsableFrame:usable];
        if (ok) {
            [self rebuildMenu];
        } else {
            NSBeep();
        }
    }];
}

- (void)rememberWindowPositionsAction:(id)sender {
    (void)sender;
    if (![self ensureAccessibility]) return;
    NSArray<CascadeWindow *> *wins = [CascadeEngine collectStandardWindowsWithOnly:nil exclude:[CascadeEngine ignoredApps]];
    CGRect usable = [CascadeEngine usableScreenFrameWithTopInset:nil];
    [CascadeEngine saveFractalPositionsForWindows:wins onUsableFrame:usable];
}

- (void)resetWindowPositionsAction:(id)sender {
    (void)sender;
    [CascadeEngine clearSavedFractalPositions];
    [self cascadeWindowsOnTargetScreensWithRestack:self.restackZOrder preserveOrder:NO];
}

- (void)dockLeftAction:(id)s { (void)s; [self dockActiveWindowWithEdge:CascadeDockEdgeLeft]; }
- (void)dockRightAction:(id)s { (void)s; [self dockActiveWindowWithEdge:CascadeDockEdgeRight]; }
- (void)dockTopAction:(id)s { (void)s; [self dockActiveWindowWithEdge:CascadeDockEdgeTop]; }
- (void)dockBottomAction:(id)s { (void)s; [self dockActiveWindowWithEdge:CascadeDockEdgeBottom]; }

- (void)dockActiveWindowWithEdge:(CascadeDockEdge)edge {
    if (![self ensureAccessibility]) return;
    [CascadeEngine dockActiveWindowWithEdge:edge layoutStyle:[CascadeEngine savedLayoutStyle] delta:self.delta];
}

- (void)toggleAutoRearrange:(id)sender {
    (void)sender;
    if (self.watcher.isWatching) {
        [self.watcher stopWatching];
        [CascadeEngine saveAutoRearrange:NO];
    } else {
        [self.watcher startWatching];
        [CascadeEngine saveAutoRearrange:YES];
        [self cascadeWindowsOnTargetScreensWithRestack:self.restackZOrder preserveOrder:NO];
    }
    [self rebuildMenu];
}

- (void)windowWatcherDidDetectChange:(WindowWatcher *)watcher {
    (void)watcher;
    if ([CascadeEngine savedLayoutStyle] == CascadeLayoutStyleFractal) {
        CascadeWindow *front = [CascadeEngine frontmostStandardWindow];
        if (front) {
            CGRect usable = [CascadeEngine usableScreenFrameWithTopInset:nil];
            [CascadeEngine saveFractalPositionForWindow:front onUsableFrame:usable];
        }
    }
    [self rearrangePreservingOrder];
}

- (void)openAccessibilitySettings:(id)s { (void)s; [CascadeEngine openAccessibilitySettings]; }

- (void)runBackgroundUpdateCheck {
    if (![UpdateChecker isAutomaticCheckEnabled]) return;
    [UpdateChecker checkForUpdatesForce:NO completion:^(BOOL updateAvailable, NSString *latestVersion, NSString *releaseURL, NSError *error) {
        (void)latestVersion; (void)releaseURL; (void)error;
        if (updateAvailable) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self rebuildMenu];
            });
        }
    }];
}

- (void)installUpdateWithVersion:(NSString *)latestVersion {
    NSPanel *hud = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 360, 110)
                                              styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskUtilityWindow
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    hud.title = @"Updating Cascade";
    [hud center];
    [hud makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];

    NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 55, 320, 22)];
    label.stringValue = [NSString stringWithFormat:@"Downloading Cascade v%@...", latestVersion];
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.editable = NO;
    label.selectable = NO;
    label.font = [NSFont boldSystemFontOfSize:13];
    [hud.contentView addSubview:label];

    NSProgressIndicator *indicator = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(20, 25, 320, 20)];
    indicator.indeterminate = YES;
    indicator.style = NSProgressIndicatorStyleBar;
    [indicator startAnimation:nil];
    [hud.contentView addSubview:indicator];

    [UpdateChecker downloadAndInstallUpdateVersion:latestVersion progress:^(NSString *statusMessage, double fraction) {
        (void)fraction;
        dispatch_async(dispatch_get_main_queue(), ^{
            label.stringValue = statusMessage;
        });
    } completion:^(BOOL success, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [indicator stopAnimation:nil];
            [hud close];
            if (!success && error) {
                NSAlert *errAlert = [[NSAlert alloc] init];
                errAlert.alertStyle = NSAlertStyleCritical;
                errAlert.messageText = @"Update Installation Failed";
                errAlert.informativeText = [NSString stringWithFormat:@"Cascade could not complete the automatic update:\n%@\n\nWould you like to download the release manually?", error.localizedDescription ?: @"Unknown error"];
                [errAlert addButtonWithTitle:@"View Release"];
                [errAlert addButtonWithTitle:@"Cancel"];
                if ([errAlert runModal] == NSAlertFirstButtonReturn) {
                    CascadeUpdateState *st = [UpdateChecker loadStateFromPath:nil];
                    NSString *url = st.releaseURL ?: @"https://github.com/brunobrise/cascade/releases/latest";
                    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:url]];
                }
            } else if (success) {
                [NSApp terminate:nil];
            }
        });
    }];
}

- (void)checkForUpdatesMenuAction:(id)sender {
    (void)sender;
    [NSApp activateIgnoringOtherApps:YES];
    [UpdateChecker checkForUpdatesForce:YES completion:^(BOOL updateAvailable, NSString *latestVersion, NSString *releaseURL, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSAlert *alert = [[NSAlert alloc] init];
            alert.alertStyle = NSAlertStyleInformational;
            if (error) {
                alert.messageText = @"Update Check Failed";
                alert.informativeText = [NSString stringWithFormat:@"Could not check for updates: %@", error.localizedDescription ?: @"Network error"];
                [alert addButtonWithTitle:@"OK"];
            } else if (updateAvailable) {
                alert.messageText = @"Update Available!";
                alert.informativeText = [NSString stringWithFormat:@"A newer version of Cascade is available: v%@ (current: v%@).\n\nWould you like to update now?", latestVersion, [UpdateChecker currentVersion]];
                [alert addButtonWithTitle:@"Update Now"];
                [alert addButtonWithTitle:@"View Release"];
                [alert addButtonWithTitle:@"Later"];
                NSModalResponse resp = [alert runModal];
                if (resp == NSAlertFirstButtonReturn) {
                    [self installUpdateWithVersion:latestVersion];
                } else if (resp == NSAlertSecondButtonReturn && releaseURL) {
                    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:releaseURL]];
                }
                [self rebuildMenu];
                return;
            } else {
                alert.messageText = @"You're Up to Date!";
                NSString *v = latestVersion ?: [UpdateChecker currentVersion];
                alert.informativeText = [NSString stringWithFormat:@"Cascade v%@ is currently the newest version available.", v];
                [alert addButtonWithTitle:@"OK"];
            }
            [alert runModal];
        });
    }];
}

- (void)openReleasePage:(id)sender {
    [self checkForUpdatesMenuAction:sender];
}
- (void)quitCascade:(id)s { (void)s; [NSApp terminate:nil]; }
- (void)terminate:(id)s { [self quitCascade:s]; }
- (BOOL)validateMenuItem:(NSMenuItem *)item { (void)item; return YES; }

- (void)checkPermissionsChange {
    static BOOL lastTrusted = NO;
    BOOL current = [CascadeEngine isAccessibilityTrustedWithPrompt:NO];
    if (current != lastTrusted) {
        lastTrusted = current;
        if (current) {
            [self.watcher refreshObservers];
            if ([CascadeEngine savedAutoRearrange] && !self.watcher.isWatching) {
                [self.watcher startWatching];
            }
            if (self.establishedOrder.count == 0) {
                NSArray *saved = [CascadeEngine savedEstablishedWindowOrder];
                if (saved.count > 0) {
                    NSArray<CascadeWindow *> *wins = [CascadeEngine collectStandardWindowsWithOnly:nil exclude:[CascadeEngine ignoredApps]];
                    if (wins.count > 0) self.establishedOrder = [CascadeEngine matchWindows:wins withSavedDescriptors:saved];
                }
            }
        }
        [self rebuildMenu];
    }
}

- (void)menuWillOpen:(NSMenu *)menu {
    (void)menu;
    [self checkPermissionsChange];
    [self rebuildMenu];
}

- (void)setScreenTargetValue:(NSString *)target {
    self.targetScreen = target;
    [ScreenManager saveScreenTarget:target];
    [self rebuildMenu];
    [self cascadeWindowsOnTargetScreensWithRestack:self.restackZOrder preserveOrder:NO];
}
- (void)screensDidChange:(NSNotification *)n { (void)n; self.targetScreen = [ScreenManager savedScreenTarget]; [self rebuildMenu]; }

- (void)cascadeWindowsOnScreens:(NSArray<CascadeScreen *> *)targetScreens
                        restack:(BOOL)restack
                  preserveOrder:(BOOL)preserveOrder {
    NSArray<CascadeWindow *> *allWindows = [CascadeEngine collectStandardWindowsWithOnly:nil exclude:[CascadeEngine ignoredApps]];
    if (allWindows.count == 0) return;

    if (preserveOrder && self.establishedOrder.count == 0) {
        NSArray *saved = [CascadeEngine savedEstablishedWindowOrder];
        if (saved.count > 0) self.establishedOrder = [CascadeEngine matchWindows:allWindows withSavedDescriptors:saved];
    }

    NSArray<CascadeScreen *> *allScreens = [ScreenManager availableScreens];
    if (targetScreens.count == 0) targetScreens = allScreens;

    NSMutableArray<CascadeScreen *> *allExpandedScreens = [NSMutableArray array], *expandedScreens = [NSMutableArray array];
    for (CascadeScreen *s in allScreens) {
        BOOL isTarget = [targetScreens containsObject:s];
        NSInteger k = [ScreenManager screenSplitForScreen:s];
        NSArray<CascadeScreen *> *subs = (k > 1) ? [ScreenManager subscreensForScreen:s splitCount:k] : @[s];
        [allExpandedScreens addObjectsFromArray:subs];
        if (isTarget) [expandedScreens addObjectsFromArray:subs];
    }
    NSDictionary<CascadeScreen *, NSArray<CascadeWindow *> *> *partition = [ScreenManager partitionWindows:allWindows intoScreens:allExpandedScreens];
    NSMutableArray<CascadeWindow *> *allPlanned = [NSMutableArray array];

    for (CascadeScreen *screen in expandedScreens) {
        NSArray<CascadeWindow *> *screenWins = partition[screen] ?: @[];
        if (screenWins.count == 0) continue;

        NSArray<CascadeWindow *> *planned = (preserveOrder && self.establishedOrder.count > 0) ?
            [CascadeEngine calculateLayoutForWindows:screenWins preservingOrderFrom:self.establishedOrder delta:self.delta onUsableFrame:screen.quartzVisibleFrame] :
            [CascadeEngine calculateLayoutForWindows:screenWins orderMode:self.orderMode preferredOrder:[CascadeEngine preferredAppOrder] delta:self.delta onUsableFrame:screen.quartzVisibleFrame];

        [allPlanned addObjectsFromArray:planned];
        [CascadeEngine applyLayoutToWindows:planned restackZ:restack];
    }
    if (allPlanned.count > 0) {
        NSMutableArray<CascadeWindow *> *merged = [NSMutableArray array];
        if (preserveOrder && self.establishedOrder.count > 0) {
            NSMutableSet<CascadeWindow *> *used = [NSMutableSet set];
            for (CascadeWindow *prev in self.establishedOrder) {
                CascadeWindow *matched = nil;
                for (CascadeWindow *p in allPlanned) { if ([p matchesWindow:prev]) { matched = p; break; } }
                if (matched) { [merged addObject:matched]; [used addObject:matched]; }
                else { [merged addObject:prev]; }
            }
            for (CascadeWindow *p in allPlanned) { if (![used containsObject:p]) [merged addObject:p]; }
        } else {
            [merged addObjectsFromArray:allPlanned];
        }
        self.establishedOrder = merged;
        [CascadeEngine saveEstablishedWindowOrder:merged];
    }
}

- (void)cascadeWindowsOnTargetScreensWithRestack:(BOOL)restack preserveOrder:(BOOL)preserveOrder {
    if (![CascadeEngine isAccessibilityTrustedWithPrompt:NO]) return;
    [self.watcher performWithoutTriggering:^{
        NSArray<CascadeScreen *> *all = [ScreenManager availableScreens];
        NSString *tgt = self.targetScreen ?: [ScreenManager savedScreenTarget];
        [self cascadeWindowsOnScreens:[ScreenManager screensMatchingTarget:tgt inScreens:all] restack:restack preserveOrder:preserveOrder];
    }];
}
- (void)rearrangePreservingOrder { [self cascadeWindowsOnTargetScreensWithRestack:NO preserveOrder:YES]; }

- (BOOL)ensureAccessibility {
    if ([CascadeEngine isAccessibilityTrustedWithPrompt:NO]) return YES;
    if ([CascadeEngine isAccessibilityTrustedWithPrompt:YES]) { [self checkPermissionsChange]; return YES; }
    [self rebuildMenu];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Accessibility Permission Required";
    alert.informativeText = @"Cascade needs Accessibility permission to move and resize windows.\n\nPlease enable Cascade in System Settings > Privacy & Security > Accessibility.";
    NSImage *appIcon = [self cascadeAppIcon];
    if (appIcon) alert.icon = appIcon;
    [alert addButtonWithTitle:@"Open System Settings"];
    [alert addButtonWithTitle:@"Cancel"];
    if ([alert runModal] == NSAlertFirstButtonReturn) [CascadeEngine openAccessibilitySettings];
    return NO;
}

- (void)performCascade:(id)sender {
    (void)sender;
    if (![self ensureAccessibility]) return;
    NSString *tgt = self.targetScreen ?: [ScreenManager savedScreenTarget];
    NSArray *all = [ScreenManager availableScreens];
    NSArray *targets = nil;
    if ([tgt localizedCaseInsensitiveCompare:@"pointer"] == NSOrderedSame ||
        [tgt localizedCaseInsensitiveCompare:@"active"] == NSOrderedSame) {
        CascadeScreen *ptr = [ScreenManager screenForPointer];
        targets = ptr ? @[ptr] : all;
    } else {
        targets = [ScreenManager screensMatchingTarget:tgt inScreens:all];
    }
    [self.watcher refreshObservers];
    [self.watcher performWithoutTriggering:^{
        [self cascadeWindowsOnScreens:targets restack:self.restackZOrder preserveOrder:NO];
    }];
}

- (void)performCascadeAllScreens:(id)sender {
    (void)sender;
    if (![self ensureAccessibility]) return;
    [self.watcher refreshObservers];
    [self.watcher performWithoutTriggering:^{
        [self cascadeWindowsOnScreens:[ScreenManager availableScreens] restack:self.restackZOrder preserveOrder:NO];
    }];
}
@end

int main(int argc, const char * argv[]) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier] ?: @"com.brunobrise.cascade";
        NSArray<NSRunningApplication *> *apps = [NSRunningApplication runningApplicationsWithBundleIdentifier:bundleId];
        pid_t currentPid = [[NSProcessInfo processInfo] processIdentifier];
        for (NSRunningApplication *app in apps) {
            if (app.processIdentifier != currentPid) {
                NSLog(@"Cascade is already running with PID %d. Exiting duplicate instance.", (int)app.processIdentifier);
                return 0;
            }
        }
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        CascadeBarApp *delegate = [[CascadeBarApp alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
