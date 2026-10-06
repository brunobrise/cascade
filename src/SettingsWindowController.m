#import "SettingsWindowController.h"
#import "WindowEngine.h"
#import "ScreenManager.h"
#import "LoginItemManager.h"
#import "AppOrderWindowController.h"
#import "IgnoreListWindowController.h"

#ifndef CASCADE_VERSION
#define CASCADE_VERSION "0.19.1"
#endif

static NSTextField *makeLabel(NSRect f, NSString *s, NSFont *font, NSColor *c) {
    NSTextField *tf = [[NSTextField alloc] initWithFrame:f];
    tf.stringValue = s ?: @"";
    tf.font = font ?: [NSFont systemFontOfSize:12];
    tf.textColor = c ?: [NSColor labelColor];
    tf.bordered = NO; tf.editable = NO; tf.backgroundColor = [NSColor clearColor];
    return tf;
}

static NSBox *makeSeparator(NSRect f) {
    NSBox *b = [[NSBox alloc] initWithFrame:f];
    b.boxType = NSBoxSeparator;
    return b;
}

static NSButton *makeCheckbox(NSString *title, id target, SEL action, NSRect f) {
    NSButton *b = [NSButton checkboxWithTitle:title target:target action:action];
    b.frame = f;
    return b;
}

@interface SettingsWindowController () <NSWindowDelegate>
@property (nonatomic, strong) NSPanel *panel;
@property (nonatomic, strong) NSPopUpButton *targetScreenPopup;
@property (nonatomic, strong) NSPopUpButton *displayColumnsPopup;
@property (nonatomic, strong) NSSegmentedControl *columnsControl;
@property (nonatomic, strong) NSPopUpButton *orderModePopup;
@property (nonatomic, strong) NSButton *configureAppsButton;
@property (nonatomic, strong) NSPopUpButton *deltaPopup;
@property (nonatomic, strong) NSButton *autoRearrangeCheckbox;
@property (nonatomic, strong) NSButton *restackCheckbox;
@property (nonatomic, strong) NSTextField *ignoredAppsLabel;
@property (nonatomic, strong) NSButton *configureIgnoredButton;
@property (nonatomic, strong) NSButton *startAtLoginCheckbox;
@end

@implementation SettingsWindowController

+ (instancetype)sharedController {
    static SettingsWindowController *shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[SettingsWindowController alloc] init]; });
    return shared;
}

- (void)buildWindowIfNeeded {
    if (self.panel) return;
    NSRect frame = NSMakeRect(0, 0, 480, 565);
    NSPanel *p = [[NSPanel alloc] initWithContentRect:frame
                                            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskUtilityWindow
                                              backing:NSBackingStoreBuffered defer:NO];
    p.title = @"Cascade Settings";
    p.floatingPanel = YES;
    p.delegate = self;
    [p center];
    NSView *c = p.contentView;

    // Header Area
    NSImageView *iconView = [[NSImageView alloc] initWithFrame:NSMakeRect(24, 505, 36, 36)];
    NSImage *appIcon = [NSImage imageNamed:@"AppIcon"] ?: [[NSImage alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"AppIcon" ofType:@"icns"]];
    if (appIcon) iconView.image = appIcon;
    [c addSubview:iconView];

    NSString *ver = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: [NSString stringWithUTF8String:CASCADE_VERSION];
    [c addSubview:makeLabel(NSMakeRect(70, 517, 240, 22), @"Cascade Preferences", [NSFont boldSystemFontOfSize:15], [NSColor labelColor])];
    [c addSubview:makeLabel(NSMakeRect(315, 519, 135, 18), [NSString stringWithFormat:@"v%@", ver], [NSFont systemFontOfSize:12 weight:NSFontWeightMedium], [NSColor secondaryLabelColor])];
    [c addSubview:makeLabel(NSMakeRect(70, 501, 380, 16), @"Configure layout geometry, target displays, and automation", [NSFont systemFontOfSize:11], [NSColor secondaryLabelColor])];
    [c addSubview:makeSeparator(NSMakeRect(20, 487, 440, 1))];

    // Section 1: Layout & Geometry
    [c addSubview:makeLabel(NSMakeRect(24, 462, 430, 18), @"Layout & Geometry", [NSFont boldSystemFontOfSize:12], [NSColor secondaryLabelColor])];

    [c addSubview:makeLabel(NSMakeRect(34, 432, 110, 18), @"Target Screen:", [NSFont systemFontOfSize:12], nil)];
    self.targetScreenPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(148, 429, 298, 26) pullsDown:NO];
    self.targetScreenPopup.target = self;
    self.targetScreenPopup.action = @selector(targetScreenChanged:);
    [c addSubview:self.targetScreenPopup];

    [c addSubview:makeLabel(NSMakeRect(34, 397, 110, 18), @"Display Columns:", [NSFont systemFontOfSize:12], nil)];
    self.displayColumnsPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(148, 394, 298, 26) pullsDown:NO];
    self.displayColumnsPopup.target = self;
    self.displayColumnsPopup.action = @selector(displayColumnsChanged:);
    [c addSubview:self.displayColumnsPopup];

    [c addSubview:makeLabel(NSMakeRect(34, 364, 110, 18), @"Column Splits:", [NSFont systemFontOfSize:12], nil)];
    self.columnsControl = [NSSegmentedControl segmentedControlWithLabels:@[@"1 (Full)", @"2 Columns", @"3 Columns", @"4 Columns"]
                                                            trackingMode:NSSegmentSwitchTrackingSelectOne
                                                                  target:self
                                                                  action:@selector(columnsChanged:)];
    self.columnsControl.frame = NSMakeRect(148, 361, 298, 25);
    self.columnsControl.font = [NSFont systemFontOfSize:11];
    [c addSubview:self.columnsControl];

    [c addSubview:makeLabel(NSMakeRect(34, 329, 110, 18), @"Window Order:", [NSFont systemFontOfSize:12], nil)];
    self.orderModePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(148, 326, 185, 26) pullsDown:NO];
    [self.orderModePopup addItemWithTitle:@"Most Recently Used"];
    self.orderModePopup.lastItem.tag = CascadeOrderModeMRU;
    [self.orderModePopup addItemWithTitle:@"Spatial (Left-to-Right)"];
    self.orderModePopup.lastItem.tag = CascadeOrderModeSpatial;
    [self.orderModePopup addItemWithTitle:@"Alphabetical"];
    self.orderModePopup.lastItem.tag = CascadeOrderModeAlphabetical;
    [self.orderModePopup addItemWithTitle:@"Preferred App Order"];
    self.orderModePopup.lastItem.tag = CascadeOrderModeCustom;
    self.orderModePopup.target = self;
    self.orderModePopup.action = @selector(orderModeChanged:);
    [c addSubview:self.orderModePopup];

    self.configureAppsButton = [NSButton buttonWithTitle:@"Configure..." target:self action:@selector(configureAppsClicked:)];
    self.configureAppsButton.frame = NSMakeRect(337, 326, 109, 26);
    self.configureAppsButton.bezelStyle = NSBezelStyleRounded;
    self.configureAppsButton.font = [NSFont systemFontOfSize:12];
    [c addSubview:self.configureAppsButton];

    [c addSubview:makeLabel(NSMakeRect(34, 294, 110, 18), @"Tab Size (Delta):", [NSFont systemFontOfSize:12], nil)];
    self.deltaPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(148, 291, 298, 26) pullsDown:NO];
    NSArray *deltas = @[@(30), @(40), @(50), @(60)];
    for (NSNumber *d in deltas) {
        NSString *title = [NSString stringWithFormat:@"%d px%@", [d intValue], [d intValue] == 40 ? @" (Standard)" : @""];
        [self.deltaPopup addItemWithTitle:title];
        self.deltaPopup.lastItem.representedObject = d;
    }
    self.deltaPopup.target = self;
    self.deltaPopup.action = @selector(deltaChanged:);
    [c addSubview:self.deltaPopup];

    [c addSubview:makeSeparator(NSMakeRect(20, 276, 440, 1))];

    // Section 2: Automation & Behavior
    [c addSubview:makeLabel(NSMakeRect(24, 252, 430, 18), @"Automation & Behavior", [NSFont boldSystemFontOfSize:12], [NSColor secondaryLabelColor])];

    self.autoRearrangeCheckbox = makeCheckbox(@"Auto-Rearrange on Open / Minimize / Close", self, @selector(autoRearrangeToggled:), NSMakeRect(34, 224, 410, 20));
    [c addSubview:self.autoRearrangeCheckbox];
    [c addSubview:makeLabel(NSMakeRect(54, 208, 390, 14), @"Keeps windows organized continuously as windows are created or closed", [NSFont systemFontOfSize:11], [NSColor secondaryLabelColor])];

    self.restackCheckbox = makeCheckbox(@"Restack window Z-order during cascade", self, @selector(restackToggled:), NSMakeRect(34, 180, 410, 20));
    [c addSubview:self.restackCheckbox];
    [c addSubview:makeLabel(NSMakeRect(54, 164, 390, 14), @"Brings cascaded windows forward to match front-to-back sequence", [NSFont systemFontOfSize:11], [NSColor secondaryLabelColor])];

    [c addSubview:makeLabel(NSMakeRect(34, 134, 110, 18), @"Ignored Apps:", [NSFont systemFontOfSize:12], nil)];
    self.ignoredAppsLabel = makeLabel(NSMakeRect(148, 134, 185, 18), @"None", [NSFont systemFontOfSize:12], [NSColor secondaryLabelColor]);
    [c addSubview:self.ignoredAppsLabel];

    self.configureIgnoredButton = [NSButton buttonWithTitle:@"Configure..." target:self action:@selector(configureIgnoredClicked:)];
    self.configureIgnoredButton.frame = NSMakeRect(337, 130, 109, 26);
    self.configureIgnoredButton.bezelStyle = NSBezelStyleRounded;
    self.configureIgnoredButton.font = [NSFont systemFontOfSize:12];
    [c addSubview:self.configureIgnoredButton];
    [c addSubview:makeLabel(NSMakeRect(54, 114, 390, 14), @"Windows of ignored applications are excluded from cascade", [NSFont systemFontOfSize:11], [NSColor secondaryLabelColor])];

    self.startAtLoginCheckbox = makeCheckbox(@"Launch Cascade automatically at login", self, @selector(startAtLoginToggled:), NSMakeRect(34, 88, 410, 20));
    [c addSubview:self.startAtLoginCheckbox];

    [c addSubview:makeSeparator(NSMakeRect(20, 70, 440, 1))];

    // Bottom Bar
    NSButton *cascadeBtn = [NSButton buttonWithTitle:@"Cascade Windows" target:self action:@selector(cascadeNowClicked:)];
    cascadeBtn.frame = NSMakeRect(20, 20, 145, 32);
    cascadeBtn.bezelStyle = NSBezelStyleRounded;
    [c addSubview:cascadeBtn];

    NSButton *aboutBtn = [NSButton buttonWithTitle:@"About Cascade..." target:self action:@selector(aboutClicked:)];
    aboutBtn.frame = NSMakeRect(175, 20, 140, 32);
    aboutBtn.bezelStyle = NSBezelStyleRounded;
    [c addSubview:aboutBtn];

    NSButton *doneBtn = [NSButton buttonWithTitle:@"Done" target:self action:@selector(doneClicked:)];
    doneBtn.frame = NSMakeRect(370, 20, 90, 32);
    doneBtn.bezelStyle = NSBezelStyleRounded;
    doneBtn.keyEquivalent = @"\r";
    [c addSubview:doneBtn];

    self.panel = p;
}

- (void)populateScreenTargets {
    [self.targetScreenPopup removeAllItems];
    [self.displayColumnsPopup removeAllItems];
    NSString *curr = [ScreenManager savedScreenTarget];
    BOOL isAll = [curr localizedCaseInsensitiveCompare:@"all"] == NSOrderedSame;

    [self.targetScreenPopup addItemWithTitle:@"All Screens (Independent)"];
    self.targetScreenPopup.lastItem.representedObject = @"all";
    if (isAll) [self.targetScreenPopup selectItem:self.targetScreenPopup.lastItem];

    NSArray<CascadeScreen *> *screens = [ScreenManager availableScreens];
    for (CascadeScreen *s in screens) {
        NSString *title = [NSString stringWithFormat:@"%@ (%dx%d)%@", s.name, (int)s.quartzFrame.size.width, (int)s.quartzFrame.size.height, s.isPrimary ? @" [Primary]" : @""];
        [self.targetScreenPopup addItemWithTitle:title];
        self.targetScreenPopup.lastItem.representedObject = [s uniqueID];
        BOOL sel = (!isAll && ([s.name localizedCaseInsensitiveCompare:curr] == NSOrderedSame ||
                               [s.name localizedCaseInsensitiveContainsString:curr] ||
                               (s.screenUUID.length > 0 && [s.screenUUID isEqualToString:curr]) ||
                               (s.displayID.length > 0 && [s.displayID isEqualToString:curr])));
        if (sel) [self.targetScreenPopup selectItem:self.targetScreenPopup.lastItem];

        [self.displayColumnsPopup addItemWithTitle:title];
        self.displayColumnsPopup.lastItem.representedObject = s;
    }
    if (self.displayColumnsPopup.numberOfItems > 0 && !self.displayColumnsPopup.selectedItem) {
        [self.displayColumnsPopup selectItemAtIndex:0];
    }
}

- (void)syncControlsFromSettings {
    [self populateScreenTargets];
    CascadeOrderMode mode = [CascadeEngine savedOrderMode];
    [self.orderModePopup selectItemWithTag:(NSInteger)mode];
    self.configureAppsButton.enabled = (mode == CascadeOrderModeCustom);

    CGFloat curD = [CascadeEngine savedDelta];
    for (NSMenuItem *item in self.deltaPopup.itemArray) {
        if (fabs([item.representedObject doubleValue] - curD) < 0.1) {
            [self.deltaPopup selectItem:item];
            break;
        }
    }

    self.autoRearrangeCheckbox.state = [CascadeEngine savedAutoRearrange] ? NSControlStateValueOn : NSControlStateValueOff;
    self.restackCheckbox.state = [CascadeEngine savedRestackZOrder] ? NSControlStateValueOn : NSControlStateValueOff;
    self.startAtLoginCheckbox.state = [LoginItemManager isStartAtLoginEnabled] ? NSControlStateValueOn : NSControlStateValueOff;
    NSArray *ignored = [CascadeEngine ignoredApps];
    if (ignored.count == 0) self.ignoredAppsLabel.stringValue = @"None";
    else if (ignored.count == 1) self.ignoredAppsLabel.stringValue = @"1 app ignored";
    else self.ignoredAppsLabel.stringValue = [NSString stringWithFormat:@"%lu apps ignored", (unsigned long)ignored.count];
    [self updateColumnsControlForSelectedDisplay];
}

- (CascadeScreen *)selectedDisplayForColumns {
    NSMenuItem *item = self.displayColumnsPopup.selectedItem;
    if (item && [item.representedObject isKindOfClass:[CascadeScreen class]]) {
        return (CascadeScreen *)item.representedObject;
    }
    return [ScreenManager primaryScreen];
}

- (void)updateColumnsControlForSelectedDisplay {
    CascadeScreen *s = [self selectedDisplayForColumns];
    NSInteger split = [ScreenManager screenSplitForScreen:s];
    if (split < 1) split = 1;
    if (split > 4) split = 4;
    self.columnsControl.selectedSegment = split - 1;
}

- (void)displayColumnsChanged:(id)sender {
    (void)sender;
    [self updateColumnsControlForSelectedDisplay];
}

- (void)columnsChanged:(id)sender {
    (void)sender;
    NSInteger split = self.columnsControl.selectedSegment + 1;
    CascadeScreen *s = [self selectedDisplayForColumns];
    [ScreenManager saveScreenSplit:split forScreen:s];
    [self.delegate settingsDidChange];
}

- (void)showWindow {
    [self buildWindowIfNeeded];
    [self syncControlsFromSettings];
    [NSApp activateIgnoringOtherApps:YES];
    [self.panel makeKeyAndOrderFront:nil];
}

- (void)closeWindow {
    [self.panel close];
}

- (BOOL)isWindowVisible {
    return self.panel.isVisible;
}

- (void)targetScreenChanged:(id)sender {
    (void)sender;
    NSString *val = self.targetScreenPopup.selectedItem.representedObject ?: @"all";
    [ScreenManager saveScreenTarget:val];
    if (![val isEqualToString:@"all"]) {
        for (NSMenuItem *item in self.displayColumnsPopup.itemArray) {
            CascadeScreen *cs = item.representedObject;
            if ([cs isKindOfClass:[CascadeScreen class]] &&
                ([[cs uniqueID] isEqualToString:val] || [cs.name isEqualToString:val])) {
                [self.displayColumnsPopup selectItem:item];
                break;
            }
        }
    }
    [self updateColumnsControlForSelectedDisplay];
    [self.delegate settingsDidChange];
}

- (void)orderModeChanged:(id)sender {
    (void)sender;
    CascadeOrderMode mode = (CascadeOrderMode)self.orderModePopup.selectedItem.tag;
    [CascadeEngine saveOrderMode:mode];
    self.configureAppsButton.enabled = (mode == CascadeOrderModeCustom);
    [self.delegate settingsDidChange];
}

- (void)configureAppsClicked:(id)sender {
    (void)sender;
    [[AppOrderWindowController sharedController] showWindowWithCompletion:^(BOOL applied) {
        [self syncControlsFromSettings];
        if (applied) [self.delegate settingsRequestsCascade];
    }];
}

- (void)configureIgnoredClicked:(id)sender {
    (void)sender;
    [[IgnoreListWindowController sharedController] showWindowWithCompletion:^(BOOL applied) {
        [self syncControlsFromSettings];
        if (applied) [self.delegate settingsDidChange];
    }];
}

- (void)deltaChanged:(id)sender {
    (void)sender;
    CGFloat d = [self.deltaPopup.selectedItem.representedObject doubleValue];
    [CascadeEngine saveDelta:d];
    [self.delegate settingsDidChange];
}

- (void)autoRearrangeToggled:(id)sender {
    (void)sender;
    BOOL val = (self.autoRearrangeCheckbox.state == NSControlStateValueOn);
    [CascadeEngine saveAutoRearrange:val];
    [self.delegate settingsDidChange];
}

- (void)restackToggled:(id)sender {
    (void)sender;
    BOOL val = (self.restackCheckbox.state == NSControlStateValueOn);
    [CascadeEngine saveRestackZOrder:val];
    [self.delegate settingsDidChange];
}

- (void)startAtLoginToggled:(id)sender {
    (void)sender;
    BOOL val = (self.startAtLoginCheckbox.state == NSControlStateValueOn);
    NSError *err = nil;
    [LoginItemManager setStartAtLoginEnabled:val error:&err];
    self.startAtLoginCheckbox.state = [LoginItemManager isStartAtLoginEnabled] ? NSControlStateValueOn : NSControlStateValueOff;
    [self.delegate settingsDidChange];
}

- (void)cascadeNowClicked:(id)sender {
    (void)sender;
    [self.delegate settingsRequestsCascade];
}

- (void)doneClicked:(id)sender {
    (void)sender;
    [self.panel close];
}

- (void)showAboutPanel {
    [NSApp activateIgnoringOtherApps:YES];
    NSString *ver = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: [NSString stringWithUTF8String:CASCADE_VERSION];
    NSMutableDictionary *options = [@{ NSAboutPanelOptionApplicationName: @"Cascade", NSAboutPanelOptionVersion: ver } mutableCopy];
    NSImage *appIcon = [NSImage imageNamed:@"AppIcon"] ?: [[NSImage alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"AppIcon" ofType:@"icns"]];
    if (appIcon) options[NSAboutPanelOptionApplicationIcon] = appIcon;
    [NSApp orderFrontStandardAboutPanelWithOptions:options];
}

- (void)aboutClicked:(id)sender {
    (void)sender;
    [self showAboutPanel];
}

@end
