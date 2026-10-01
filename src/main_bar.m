#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import "WindowEngine.h"
#import "LoginItemManager.h"

@interface CascadeBarApp : NSObject <NSApplicationDelegate>
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) NSMenu *statusMenu;
@property (nonatomic, assign) CascadeOrderMode orderMode;
@property (nonatomic, assign) CGFloat delta;
@property (nonatomic, assign) BOOL restackZOrder;
@property (nonatomic, assign) EventHotKeyRef hotKeyRef;
- (void)performCascade:(id)sender;
@end

static OSStatus HotKeyHandler(EventHandlerCallRef nextHandler, EventRef theEvent, void *userData) {
    (void)nextHandler;
    (void)theEvent;
    CascadeBarApp *app = (__bridge CascadeBarApp *)userData;
    [app performCascade:nil];
    return noErr;
}

@implementation CascadeBarApp

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    self.orderMode = CascadeOrderModeMRU;
    self.delta = 40.0;
    self.restackZOrder = YES;

    // 1. Setup Status Bar Item
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    NSStatusBarButton *button = self.statusItem.button;
    if (button) {
        NSImage *icon = [NSImage imageWithSystemSymbolName:@"macwindow.on.rectangle" accessibilityDescription:@"Cascade"];
        if (icon) {
            NSImageSymbolConfiguration *config = [NSImageSymbolConfiguration configurationWithPointSize:18.0 weight:NSFontWeightSemibold];
            icon = [icon imageWithSymbolConfiguration:config];
            [icon setTemplate:YES];
            button.image = icon;
            button.imagePosition = NSImageOnly;
            button.title = @"";
        } else {
            button.title = @"⧉";
            button.font = [NSFont boldSystemFontOfSize:18.0];
        }
        button.toolTip = @"Cascade (Click to arrange or configure)";
    }

    [self rebuildMenu];

    // 2. Global Hotkey (Option + Command + C)
    EventTypeSpec eventType;
    eventType.eventClass = kEventClassKeyboard;
    eventType.eventKind = kEventHotKeyPressed;
    InstallApplicationEventHandler(&HotKeyHandler, 1, &eventType, (__bridge void *)self, NULL);

    EventHotKeyID hotKeyID;
    hotKeyID.signature = 'CSCD';
    hotKeyID.id = 1;
    RegisterEventHotKey(0x08, cmdKey | optionKey, hotKeyID, GetApplicationEventTarget(), 0, &_hotKeyRef);
}

- (void)rebuildMenu {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Cascade"];

    NSMenuItem *cascadeItem = [[NSMenuItem alloc] initWithTitle:@"Cascade Windows"
                                                         action:@selector(performCascade:)
                                                  keyEquivalent:@"c"];
    cascadeItem.keyEquivalentModifierMask = NSEventModifierFlagOption | NSEventModifierFlagCommand;
    cascadeItem.target = self;
    [menu addItem:cascadeItem];

    [menu addItem:[NSMenuItem separatorItem]];

    // Window Order Submenu
    NSMenuItem *orderSubmenuItem = [[NSMenuItem alloc] initWithTitle:@"Window Order" action:nil keyEquivalent:@""];
    NSMenu *orderMenu = [[NSMenu alloc] initWithTitle:@"Window Order"];

    NSMenuItem *mruItem = [[NSMenuItem alloc] initWithTitle:@"Most Recently Used (Front-to-Back)"
                                                     action:@selector(setOrderMRU:)
                                              keyEquivalent:@""];
    mruItem.target = self;
    mruItem.state = (self.orderMode == CascadeOrderModeMRU) ? NSControlStateValueOn : NSControlStateValueOff;
    [orderMenu addItem:mruItem];

    NSMenuItem *spatialItem = [[NSMenuItem alloc] initWithTitle:@"Spatial Order (Left-to-Right)"
                                                         action:@selector(setOrderSpatial:)
                                                  keyEquivalent:@""];
    spatialItem.target = self;
    spatialItem.state = (self.orderMode == CascadeOrderModeSpatial) ? NSControlStateValueOn : NSControlStateValueOff;
    [orderMenu addItem:spatialItem];

    NSMenuItem *alphaItem = [[NSMenuItem alloc] initWithTitle:@"Alphabetical (App Name)"
                                                       action:@selector(setOrderAlpha:)
                                                keyEquivalent:@""];
    alphaItem.target = self;
    alphaItem.state = (self.orderMode == CascadeOrderModeAlphabetical) ? NSControlStateValueOn : NSControlStateValueOff;
    [orderMenu addItem:alphaItem];

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

    // Restack Z-order toggle
    NSMenuItem *restackItem = [[NSMenuItem alloc] initWithTitle:@"Restack Z-Order with Cascade"
                                                         action:@selector(toggleRestack:)
                                                  keyEquivalent:@""];
    restackItem.target = self;
    restackItem.state = self.restackZOrder ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:restackItem];

    // Start at Login toggle
    NSMenuItem *loginItem = [[NSMenuItem alloc] initWithTitle:@"Start at Login"
                                                       action:@selector(toggleStartAtLogin:)
                                                keyEquivalent:@""];
    loginItem.target = self;
    loginItem.state = [LoginItemManager isStartAtLoginEnabled] ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:loginItem];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit Cascade"
                                                      action:@selector(terminate:)
                                               keyEquivalent:@"q"];
    [menu addItem:quitItem];

    self.statusMenu = menu;
    self.statusItem.menu = menu;
}

- (void)toggleStartAtLogin:(id)sender {
    (void)sender;
    BOOL current = [LoginItemManager isStartAtLoginEnabled];
    NSError *err = nil;
    [LoginItemManager setStartAtLoginEnabled:!current error:&err];
    [self rebuildMenu];
}

- (void)setOrderMRU:(id)sender {
    (void)sender;
    self.orderMode = CascadeOrderModeMRU;
    [self rebuildMenu];
    [self performCascade:nil];
}

- (void)setOrderSpatial:(id)sender {
    (void)sender;
    self.orderMode = CascadeOrderModeSpatial;
    [self rebuildMenu];
    [self performCascade:nil];
}

- (void)setOrderAlpha:(id)sender {
    (void)sender;
    self.orderMode = CascadeOrderModeAlphabetical;
    [self rebuildMenu];
    [self performCascade:nil];
}

- (void)setDeltaValue:(NSMenuItem *)sender {
    self.delta = [sender.representedObject doubleValue];
    [self rebuildMenu];
    [self performCascade:nil];
}

- (void)toggleRestack:(id)sender {
    (void)sender;
    self.restackZOrder = !self.restackZOrder;
    [self rebuildMenu];
}

- (void)performCascade:(id)sender {
    (void)sender;
    NSArray<CascadeWindow *> *windows = [CascadeEngine collectStandardWindowsWithOnly:nil exclude:nil];
    if (windows.count == 0) return;

    NSArray<CascadeWindow *> *planned = [CascadeEngine calculateLayoutForWindows:windows
                                                                       orderMode:self.orderMode
                                                                           delta:self.delta];
    [CascadeEngine applyLayoutToWindows:planned restackZ:self.restackZOrder];
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
