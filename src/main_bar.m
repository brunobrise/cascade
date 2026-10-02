#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import "WindowEngine.h"
#import "ScreenManager.h"
#import "LoginItemManager.h"
#import "WindowWatcher.h"
#import "AppOrderWindowController.h"

@interface CascadeBarApp : NSObject <NSApplicationDelegate, WindowWatcherDelegate, NSMenuDelegate>
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) NSMenu *statusMenu;
@property (nonatomic, assign) CascadeOrderMode orderMode;
@property (nonatomic, copy) NSString *targetScreen;
@property (nonatomic, assign) CGFloat delta;
@property (nonatomic, assign) BOOL restackZOrder;
@property (nonatomic, assign) EventHotKeyRef hotKeyRef;
@property (nonatomic, strong) WindowWatcher *watcher;
@property (nonatomic, strong) NSArray<CascadeWindow *> *establishedOrder;
- (void)performCascade:(id)sender;
- (void)rearrangePreservingOrder;
- (void)openAccessibilitySettings:(id)sender;
- (void)showAbout:(id)sender;
- (void)setOrderCustom:(id)sender;
- (void)configureAppOrder:(id)sender;
- (void)checkPermissionsChange;
- (NSImage *)cascadeAppIcon;
@end

static OSStatus HotKeyHandler(EventHandlerCallRef nextHandler, EventRef theEvent, void *userData) {
    (void)nextHandler;
    (void)theEvent;
    CascadeBarApp *app = (__bridge CascadeBarApp *)userData;
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
    NSImage *appIcon = [self cascadeAppIcon];
    if (appIcon) [NSApp setApplicationIconImage:appIcon];

    self.watcher = [[WindowWatcher alloc] initWithDelegate:self];
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
            NSImageSymbolConfiguration *cfg = [NSImageSymbolConfiguration configurationWithPointSize:18.0 weight:NSFontWeightSemibold];
            button.image = [icon imageWithSymbolConfiguration:cfg] ?: icon;
            [button.image setTemplate:YES];
            button.imagePosition = NSImageOnly; button.title = @"";
        } else {
            button.title = @"⧉"; button.font = [NSFont boldSystemFontOfSize:18.0];
        }
        button.toolTip = @"Cascade (Click to arrange or configure)";
    }
    [self rebuildMenu];

    EventTypeSpec eventType = { kEventClassKeyboard, kEventHotKeyPressed };
    InstallApplicationEventHandler(&HotKeyHandler, 1, &eventType, (__bridge void *)self, NULL);
    EventHotKeyID hotKeyID = { 'CSCD', 1 };
    RegisterEventHotKey(0x08, cmdKey | optionKey, hotKeyID, GetApplicationEventTarget(), 0, &_hotKeyRef);

    self.targetScreen = [ScreenManager savedScreenTarget];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(screensDidChange:) name:NSApplicationDidChangeScreenParametersNotification object:nil];

    NSArray *savedOrder = [CascadeEngine savedEstablishedWindowOrder];
    if (savedOrder.count > 0 && [CascadeEngine isAccessibilityTrustedWithPrompt:NO]) {
        NSArray<CascadeWindow *> *wins = [CascadeEngine collectStandardWindowsWithOnly:nil exclude:nil];
        if (wins.count > 0) self.establishedOrder = [CascadeEngine matchWindows:wins withSavedDescriptors:savedOrder];
    }
}

- (void)rebuildMenu {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Cascade"];
    menu.delegate = self;
    if (![CascadeEngine isAccessibilityTrustedWithPrompt:NO]) {
        [menu addItem:makeItem(@"⚠️ Grant Accessibility Permission...", self, @selector(openAccessibilitySettings:), NSControlStateValueOff)];
        [menu addItem:[NSMenuItem separatorItem]];
    }
    NSMenuItem *cascadeItem = makeItem(@"Cascade Windows", self, @selector(performCascade:), NSControlStateValueOff);
    cascadeItem.keyEquivalent = @"c";
    cascadeItem.keyEquivalentModifierMask = NSEventModifierFlagOption | NSEventModifierFlagCommand;
    [menu addItem:cascadeItem];
    [menu addItem:[NSMenuItem separatorItem]];

    // Window Order Submenu
    NSMenuItem *orderSubmenuItem = [[NSMenuItem alloc] initWithTitle:@"Window Order" action:nil keyEquivalent:@""];
    NSMenu *orderMenu = [[NSMenu alloc] initWithTitle:@"Window Order"];

    [orderMenu addItem:makeItem(@"Most Recently Used (Front-to-Back)", self, @selector(setOrderMRU:), (self.orderMode == CascadeOrderModeMRU) ? NSControlStateValueOn : NSControlStateValueOff)];
    [orderMenu addItem:makeItem(@"Spatial Order (Left-to-Right)", self, @selector(setOrderSpatial:), (self.orderMode == CascadeOrderModeSpatial) ? NSControlStateValueOn : NSControlStateValueOff)];
    [orderMenu addItem:makeItem(@"Alphabetical (App Name)", self, @selector(setOrderAlpha:), (self.orderMode == CascadeOrderModeAlphabetical) ? NSControlStateValueOn : NSControlStateValueOff)];
    [orderMenu addItem:makeItem(@"Preferred App Order", self, @selector(setOrderCustom:), (self.orderMode == CascadeOrderModeCustom) ? NSControlStateValueOn : NSControlStateValueOff)];
    [orderMenu addItem:[NSMenuItem separatorItem]];
    [orderMenu addItem:makeItem(@"Configure App Order...", self, @selector(configureAppOrder:), NSControlStateValueOff)];

    orderSubmenuItem.submenu = orderMenu;
    [menu addItem:orderSubmenuItem];

    // Delta Submenu
    NSMenuItem *deltaSubmenuItem = [[NSMenuItem alloc] initWithTitle:@"Tab Size (Delta)" action:nil keyEquivalent:@""];
    NSMenu *deltaMenu = [[NSMenu alloc] initWithTitle:@"Tab Size"];

    NSArray *deltas = @[@(30), @(40), @(50), @(60)];
    for (NSNumber *d in deltas) {
        NSString *title = [NSString stringWithFormat:@"%d px%@", [d intValue], [d intValue] == 40 ? @" (Default)" : @""];
        NSMenuItem *dItem = [[NSMenuItem alloc] initWithTitle:title action:@selector(setDeltaValue:) keyEquivalent:@""];
        dItem.representedObject = d;
        dItem.target = self;
        dItem.state = (fabs(self.delta - [d doubleValue]) < 0.1) ? NSControlStateValueOn : NSControlStateValueOff;
        [deltaMenu addItem:dItem];
    }
    deltaSubmenuItem.submenu = deltaMenu;
    [menu addItem:deltaSubmenuItem];

    // Target Screen Submenu
    NSMenuItem *screenSubmenuItem = [[NSMenuItem alloc] initWithTitle:@"Target Screen" action:nil keyEquivalent:@""];
    NSMenu *screenMenu = [[NSMenu alloc] initWithTitle:@"Target Screen"];
    BOOL isAll = [self.targetScreen localizedCaseInsensitiveCompare:@"all"] == NSOrderedSame;
    BOOL isActive = [self.targetScreen localizedCaseInsensitiveCompare:@"active"] == NSOrderedSame;
    [screenMenu addItem:makeItem(@"All Screens (Independent)", self, @selector(setScreenTargetAll:), isAll ? NSControlStateValueOn : NSControlStateValueOff)];
    [screenMenu addItem:makeItem(@"Active Screen (Follows Focus)", self, @selector(setScreenTargetActive:), isActive ? NSControlStateValueOn : NSControlStateValueOff)];
    [screenMenu addItem:[NSMenuItem separatorItem]];

    for (CascadeScreen *s in [ScreenManager availableScreens]) {
        NSString *title = [NSString stringWithFormat:@"%@ (%dx%d)%@", s.name, (int)s.quartzFrame.size.width, (int)s.quartzFrame.size.height, s.isPrimary ? @" [Primary]" : @""];
        BOOL selected = (!isAll && !isActive && ([self.targetScreen isEqualToString:s.name] || [self.targetScreen isEqualToString:[@(s.index) stringValue]]));
        NSMenuItem *sItem = makeItem(title, self, @selector(setScreenTargetSpecific:), selected ? NSControlStateValueOn : NSControlStateValueOff);
        sItem.representedObject = s.name;
        [screenMenu addItem:sItem];
    }
    screenSubmenuItem.submenu = screenMenu;
    [menu addItem:screenSubmenuItem];

    // Toggles
    [menu addItem:makeItem(@"Restack Z-Order with Cascade", self, @selector(toggleRestack:), self.restackZOrder ? NSControlStateValueOn : NSControlStateValueOff)];
    [menu addItem:makeItem(@"Auto-Rearrange on Open / Minimize / Close", self, @selector(toggleAutoRearrange:), self.watcher.isWatching ? NSControlStateValueOn : NSControlStateValueOff)];
    [menu addItem:makeItem(@"Start at Login", self, @selector(toggleStartAtLogin:), [LoginItemManager isStartAtLoginEnabled] ? NSControlStateValueOn : NSControlStateValueOff)];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *aboutItem = makeItem(@"About Cascade", self, @selector(showAbout:), NSControlStateValueOff);
    NSImage *menuIcon = [NSImage imageWithSystemSymbolName:@"macwindow.on.rectangle" accessibilityDescription:@"Cascade"];
    if (menuIcon) {
        NSImageSymbolConfiguration *config = [NSImageSymbolConfiguration configurationWithPointSize:14.0 weight:NSFontWeightMedium];
        aboutItem.image = [menuIcon imageWithSymbolConfiguration:config];
        [aboutItem.image setTemplate:YES];
    } else {
        NSImage *appIcon = [self cascadeAppIcon];
        if (appIcon) {
            NSImage *fallbackIcon = [appIcon copy];
            fallbackIcon.size = NSMakeSize(16, 16);
            aboutItem.image = fallbackIcon;
        }
    }
    [menu addItem:aboutItem];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItem:makeItem(@"Quit Cascade", self, @selector(terminate:), NSControlStateValueOff)];

    self.statusMenu = menu;
    self.statusItem.menu = menu;
}

- (void)toggleAutoRearrange:(id)sender {
    (void)sender;
    if (self.watcher.isWatching) {
        [self.watcher stopWatching];
        [CascadeEngine saveAutoRearrange:NO];
    } else {
        [self.watcher startWatching];
        [CascadeEngine saveAutoRearrange:YES];
        [self performCascade:nil];
    }
    [self rebuildMenu];
}

- (void)windowWatcherDidDetectChange:(WindowWatcher *)watcher {
    (void)watcher;
    [self rearrangePreservingOrder];
}

- (void)toggleStartAtLogin:(id)sender {
    (void)sender;
    BOOL current = [LoginItemManager isStartAtLoginEnabled];
    NSError *err = nil;
    [LoginItemManager setStartAtLoginEnabled:!current error:&err];
    [self rebuildMenu];
}

- (void)setOrderModeValue:(CascadeOrderMode)mode {
    self.orderMode = mode;
    [CascadeEngine saveOrderMode:mode];
    self.establishedOrder = nil;
    [CascadeEngine saveEstablishedWindowOrder:@[]];
    [self rebuildMenu];
    [self performCascade:nil];
}

- (void)setOrderMRU:(id)s { (void)s; [self setOrderModeValue:CascadeOrderModeMRU]; }
- (void)setOrderSpatial:(id)s { (void)s; [self setOrderModeValue:CascadeOrderModeSpatial]; }
- (void)setOrderAlpha:(id)s { (void)s; [self setOrderModeValue:CascadeOrderModeAlphabetical]; }

- (void)setOrderCustom:(id)sender {
    if ([CascadeEngine preferredAppOrder].count == 0) {
        [self configureAppOrder:sender];
        return;
    }
    [self setOrderModeValue:CascadeOrderModeCustom];
}

- (void)configureAppOrder:(id)sender {
    (void)sender;
    [[AppOrderWindowController sharedController] showWindowWithCompletion:^(BOOL applied) {
        self.orderMode = CascadeOrderModeCustom;
        [CascadeEngine saveOrderMode:self.orderMode];
        self.establishedOrder = nil;
        [CascadeEngine saveEstablishedWindowOrder:@[]];
        [self rebuildMenu];
        if (applied) [self performCascade:nil];
    }];
}

- (void)setDeltaValue:(NSMenuItem *)sender {
    self.delta = [sender.representedObject doubleValue];
    [CascadeEngine saveDelta:self.delta];
    [self rebuildMenu];
    [self performCascade:nil];
}

- (void)toggleRestack:(id)sender {
    (void)sender;
    self.restackZOrder = !self.restackZOrder;
    [CascadeEngine saveRestackZOrder:self.restackZOrder];
    [self rebuildMenu];
}

- (void)openAccessibilitySettings:(id)sender {
    (void)sender;
    [CascadeEngine openAccessibilitySettings];
}

- (void)showAbout:(id)sender {
    (void)sender;
    [NSApp activateIgnoringOtherApps:YES];
    NSMutableDictionary *options = [@{ NSAboutPanelOptionApplicationName: @"Cascade", NSAboutPanelOptionVersion: @"1.0" } mutableCopy];
    NSImage *appIcon = [self cascadeAppIcon];
    if (appIcon) options[NSAboutPanelOptionApplicationIcon] = appIcon;
    [NSApp orderFrontStandardAboutPanelWithOptions:options];
}

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
                    NSArray<CascadeWindow *> *wins = [CascadeEngine collectStandardWindowsWithOnly:nil exclude:nil];
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
}

- (void)setScreenTargetValue:(NSString *)target {
    self.targetScreen = target;
    [ScreenManager saveScreenTarget:target];
    [self rebuildMenu];
    [self performCascade:nil];
}
- (void)setScreenTargetAll:(id)s { (void)s; [self setScreenTargetValue:@"all"]; }
- (void)setScreenTargetActive:(id)s { (void)s; [self setScreenTargetValue:@"active"]; }
- (void)setScreenTargetSpecific:(NSMenuItem *)s { [self setScreenTargetValue:s.representedObject]; }
- (void)screensDidChange:(NSNotification *)n { (void)n; [self rebuildMenu]; }

- (void)cascadeWindowsOnTargetScreensWithRestack:(BOOL)restack {
    NSArray<CascadeWindow *> *allWindows = [CascadeEngine collectStandardWindowsWithOnly:nil exclude:nil];
    if (allWindows.count == 0) return;

    if (self.establishedOrder.count == 0) {
        NSArray *saved = [CascadeEngine savedEstablishedWindowOrder];
        if (saved.count > 0) self.establishedOrder = [CascadeEngine matchWindows:allWindows withSavedDescriptors:saved];
    }

    NSArray<CascadeScreen *> *allScreens = [ScreenManager availableScreens];
    NSArray<CascadeScreen *> *targetScreens = [ScreenManager screensMatchingTarget:self.targetScreen inScreens:allScreens];
    NSMutableArray<CascadeWindow *> *allPlanned = [NSMutableArray array];

    for (CascadeScreen *screen in targetScreens) {
        NSMutableArray<CascadeWindow *> *screenWins = [NSMutableArray array];
        for (CascadeWindow *w in allWindows) {
            if ([ScreenManager screenForFrame:w.currentFrame inScreens:allScreens] == screen) {
                [screenWins addObject:w];
            }
        }
        if (screenWins.count == 0) continue;

        NSArray<CascadeWindow *> *planned = nil;
        if (self.establishedOrder.count > 0) {
            planned = [CascadeEngine calculateLayoutForWindows:screenWins
                                           preservingOrderFrom:self.establishedOrder
                                                         delta:self.delta
                                                 onUsableFrame:screen.quartzVisibleFrame];
        } else {
            planned = [CascadeEngine calculateLayoutForWindows:screenWins
                                                     orderMode:self.orderMode
                                                preferredOrder:[CascadeEngine preferredAppOrder]
                                                         delta:self.delta
                                                 onUsableFrame:screen.quartzVisibleFrame];
        }
        [allPlanned addObjectsFromArray:planned];
        [CascadeEngine applyLayoutToWindows:planned restackZ:restack];
    }
    if (allPlanned.count > 0) {
        NSMutableArray<CascadeWindow *> *merged = [allPlanned mutableCopy];
        for (CascadeWindow *prev in (self.establishedOrder ?: @[])) {
            BOOL has = NO;
            for (CascadeWindow *p in allPlanned) { if ([p matchesWindow:prev]) { has = YES; break; } }
            if (!has) [merged addObject:prev];
        }
        self.establishedOrder = merged;
        [CascadeEngine saveEstablishedWindowOrder:merged];
    }
}

- (void)rearrangePreservingOrder {
    if (![CascadeEngine isAccessibilityTrustedWithPrompt:NO]) return;
    [self.watcher performWithoutTriggering:^{
        [self cascadeWindowsOnTargetScreensWithRestack:NO];
    }];
}

- (void)performCascade:(id)sender {
    (void)sender;
    if (![CascadeEngine isAccessibilityTrustedWithPrompt:NO]) {
        if ([CascadeEngine isAccessibilityTrustedWithPrompt:YES]) {
            [self checkPermissionsChange];
        } else {
            [self rebuildMenu];
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"Accessibility Permission Required";
            alert.informativeText = @"Cascade needs Accessibility permission to move and resize windows.\n\nPlease enable Cascade in System Settings > Privacy & Security > Accessibility.";
            NSImage *appIcon = [self cascadeAppIcon];
            if (appIcon) alert.icon = appIcon;
            [alert addButtonWithTitle:@"Open System Settings"];
            [alert addButtonWithTitle:@"Cancel"];
            if ([alert runModal] == NSAlertFirstButtonReturn) [CascadeEngine openAccessibilitySettings];
            return;
        }
    }

    [self.watcher refreshObservers];
    [self.watcher performWithoutTriggering:^{
        [self cascadeWindowsOnTargetScreensWithRestack:self.restackZOrder];
    }];
}

@end

int main(int argc, const char * argv[]) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];

        CascadeBarApp *delegate = [[CascadeBarApp alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
