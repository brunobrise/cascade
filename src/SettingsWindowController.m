#import "SettingsWindowController.h"
#import "WindowEngine.h"
#import "ScreenManager.h"
#import "LoginItemManager.h"
#import "AppOrderWindowController.h"

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
    NSRect frame = NSMakeRect(0, 0, 480, 525);
    NSPanel *p = [[NSPanel alloc] initWithContentRect:frame
                                            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskUtilityWindow
                                              backing:NSBackingStoreBuffered defer:NO];
    p.title = @"Cascade Settings";
    p.floatingPanel = YES;
    p.delegate = self;
    [p center];
    NSView *c = p.contentView;

    // Header Area
    NSImageView *iconView = [[NSImageView alloc] initWithFrame:NSMakeRect(24, 465, 36, 36)];
    NSImage *appIcon = [NSImage imageNamed:@"AppIcon"] ?: [[NSImage alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"AppIcon" ofType:@"icns"]];
    if (appIcon) iconView.image = appIcon;
    [c addSubview:iconView];

    [c addSubview:makeLabel(NSMakeRect(70, 477, 380, 22), @"Cascade Preferences", [NSFont boldSystemFontOfSize:15], [NSColor labelColor])];
    [c addSubview:makeLabel(NSMakeRect(70, 461, 380, 16), @"Configure layout geometry, target displays, and automation", [NSFont systemFontOfSize:11], [NSColor secondaryLabelColor])];
    [c addSubview:makeSeparator(NSMakeRect(20, 447, 440, 1))];

    // Section 1: Layout & Geometry
    [c addSubview:makeLabel(NSMakeRect(24, 422, 430, 18), @"Layout & Geometry", [NSFont boldSystemFontOfSize:12], [NSColor secondaryLabelColor])];

    [c addSubview:makeLabel(NSMakeRect(34, 392, 110, 18), @"Target Screen:", [NSFont systemFontOfSize:12], nil)];
    self.targetScreenPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(148, 389, 298, 26) pullsDown:NO];
    self.targetScreenPopup.target = self;
    self.targetScreenPopup.action = @selector(targetScreenChanged:);
    [c addSubview:self.targetScreenPopup];

    [c addSubview:makeLabel(NSMakeRect(34, 357, 110, 18), @"Display Columns:", [NSFont systemFontOfSize:12], nil)];
    self.displayColumnsPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(148, 354, 298, 26) pullsDown:NO];
    self.displayColumnsPopup.target = self;
    self.displayColumnsPopup.action = @selector(displayColumnsChanged:);
    [c addSubview:self.displayColumnsPopup];

    [c addSubview:makeLabel(NSMakeRect(34, 324, 110, 18), @"Column Splits:", [NSFont systemFontOfSize:12], nil)];
    self.columnsControl = [NSSegmentedControl segmentedControlWithLabels:@[@"1 (Full)", @"2 Columns", @"3 Columns", @"4 Columns"]
                                                            trackingMode:NSSegmentSwitchTrackingSelectOne
                                                                  target:self
                                                                  action:@selector(columnsChanged:)];
    self.columnsControl.frame = NSMakeRect(148, 321, 298, 25);
    self.columnsControl.font = [NSFont systemFontOfSize:11];
    [c addSubview:self.columnsControl];

    [c addSubview:makeLabel(NSMakeRect(34, 289, 110, 18), @"Window Order:", [NSFont systemFontOfSize:12], nil)];
    self.orderModePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(148, 286, 185, 26) pullsDown:NO];
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
    self.configureAppsButton.frame = NSMakeRect(337, 286, 109, 26);
    self.configureAppsButton.bezelStyle = NSBezelStyleRounded;
    self.configureAppsButton.font = [NSFont systemFontOfSize:12];
    [c addSubview:self.configureAppsButton];

    [c addSubview:makeLabel(NSMakeRect(34, 254, 110, 18), @"Tab Size (Delta):", [NSFont systemFontOfSize:12], nil)];
    self.deltaPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(148, 251, 298, 26) pullsDown:NO];
    NSArray *deltas = @[@(30), @(40), @(50), @(60)];
    for (NSNumber *d in deltas) {
        NSString *title = [NSString stringWithFormat:@"%d px%@", [d intValue], [d intValue] == 40 ? @" (Standard)" : @""];
        [self.deltaPopup addItemWithTitle:title];
        self.deltaPopup.lastItem.representedObject = d;
    }
    self.deltaPopup.target = self;
    self.deltaPopup.action = @selector(deltaChanged:);
    [c addSubview:self.deltaPopup];

    [c addSubview:makeSeparator(NSMakeRect(20, 236, 440, 1))];

    // Section 2: Automation & Behavior
    [c addSubview:makeLabel(NSMakeRect(24, 212, 430, 18), @"Automation & Behavior", [NSFont boldSystemFontOfSize:12], [NSColor secondaryLabelColor])];

    self.autoRearrangeCheckbox = makeCheckbox(@"Auto-Rearrange on Open / Minimize / Close", self, @selector(autoRearrangeToggled:), NSMakeRect(34, 184, 410, 20));
    [c addSubview:self.autoRearrangeCheckbox];
    [c addSubview:makeLabel(NSMakeRect(54, 168, 390, 14), @"Keeps windows organized continuously as windows are created or closed", [NSFont systemFontOfSize:11], [NSColor secondaryLabelColor])];

    self.restackCheckbox = makeCheckbox(@"Restack window Z-order during cascade", self, @selector(restackToggled:), NSMakeRect(34, 140, 410, 20));
    [c addSubview:self.restackCheckbox];
    [c addSubview:makeLabel(NSMakeRect(54, 124, 390, 14), @"Brings cascaded windows forward to match front-to-back sequence", [NSFont systemFontOfSize:11], [NSColor secondaryLabelColor])];

    self.startAtLoginCheckbox = makeCheckbox(@"Launch Cascade automatically at login", self, @selector(startAtLoginToggled:), NSMakeRect(34, 96, 410, 20));
    [c addSubview:self.startAtLoginCheckbox];

    [c addSubview:makeSeparator(NSMakeRect(20, 74, 440, 1))];

    // Bottom Bar
    NSButton *cascadeBtn = [NSButton buttonWithTitle:@"Cascade Windows" target:self action:@selector(cascadeNowClicked:)];
    cascadeBtn.frame = NSMakeRect(20, 20, 160, 32);
    cascadeBtn.bezelStyle = NSBezelStyleRounded;
    [c addSubview:cascadeBtn];

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

@end
