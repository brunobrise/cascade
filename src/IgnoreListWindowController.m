#import "IgnoreListWindowController.h"
#import "WindowEngine.h"

static NSTextField *makeLabel(NSRect f, NSString *s, NSFont *font, NSColor *c) {
    NSTextField *tf = [[NSTextField alloc] initWithFrame:f];
    tf.stringValue = s ?: @"";
    tf.font = font ?: [NSFont systemFontOfSize:12];
    tf.textColor = c ?: [NSColor labelColor];
    tf.bordered = NO; tf.editable = NO; tf.backgroundColor = [NSColor clearColor];
    return tf;
}

static NSButton *makeBtn(NSString *title, id target, SEL action, NSRect f, NSBezelStyle style, NSString *tip) {
    NSButton *b = [NSButton buttonWithTitle:title target:target action:action];
    b.frame = f; b.bezelStyle = style; b.toolTip = tip;
    return b;
}

@interface IgnoreListWindowController ()
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSMutableArray<NSString *> *items;
@property (nonatomic, strong) NSButton *removeButton;
@property (nonatomic, copy, nullable) void (^completionHandler)(BOOL applied);
@end

@implementation IgnoreListWindowController

+ (instancetype)sharedController {
    static IgnoreListWindowController *shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[IgnoreListWindowController alloc] init]; });
    return shared;
}

- (instancetype)init {
    if (self = [super init]) { _items = [NSMutableArray array]; }
    return self;
}

- (void)buildWindowIfNeeded {
    if (self.window) return;
    NSRect frame = NSMakeRect(0, 0, 480, 480);
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:frame
                                                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
                                                  backing:NSBackingStoreBuffered defer:NO];
    panel.title = @"Cascade — Ignored Applications";
    panel.floatingPanel = YES;
    [panel center];
    NSView *content = panel.contentView;

    NSTextField *desc = makeLabel(NSMakeRect(20, 428, 440, 36),
                                  @"Windows belonging to ignored applications will be skipped during cascade and left untouched in their original size and position.",
                                  [NSFont systemFontOfSize:11], [NSColor secondaryLabelColor]);
    [content addSubview:desc];

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 68, 440, 350)];
    scroll.hasVerticalScroller = YES; scroll.borderType = NSBezelBorder;

    self.tableView = [[NSTableView alloc] initWithFrame:scroll.bounds];
    self.tableView.headerView = nil; self.tableView.rowHeight = 36.0;
    self.tableView.dataSource = self; self.tableView.delegate = self;
    self.tableView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"IgnoreCol"];
    col.width = 430; [self.tableView addTableColumn:col];
    scroll.documentView = self.tableView;
    [content addSubview:scroll];

    [content addSubview:makeBtn(@"+", self, @selector(showAddMenu:), NSMakeRect(20, 32, 32, 24), NSBezelStyleSmallSquare, @"Add application to ignore list")];
    self.removeButton = makeBtn(@"−", self, @selector(removeSelected:), NSMakeRect(52, 32, 32, 24), NSBezelStyleSmallSquare, @"Remove selected application");
    [content addSubview:self.removeButton];

    NSButton *clearBtn = makeBtn(@"Clear All", self, @selector(clearAll:), NSMakeRect(92, 32, 64, 24), NSBezelStyleInline, @"Clear all ignored applications");
    clearBtn.font = [NSFont systemFontOfSize:10];
    [content addSubview:clearBtn];

    NSButton *cancelBtn = makeBtn(@"Cancel", self, @selector(cancelAndClose:), NSMakeRect(295, 18, 80, 32), NSBezelStyleRounded, nil);
    cancelBtn.keyEquivalent = @"\e";
    [content addSubview:cancelBtn];

    NSButton *saveBtn = makeBtn(@"Save", self, @selector(saveAndClose:), NSMakeRect(380, 18, 80, 32), NSBezelStyleRounded, nil);
    saveBtn.keyEquivalent = @"\r";
    [content addSubview:saveBtn];

    self.window = panel;
}

- (void)showWindowWithCompletion:(void (^)(BOOL applied))completion {
    [self buildWindowIfNeeded];
    self.completionHandler = completion;
    self.items = [[CascadeEngine ignoredApps] mutableCopy];
    [self.tableView reloadData];
    if (self.items.count > 0) {
        [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    }
    [self updateButtonStates];
    [NSApp activateIgnoringOtherApps:YES];
    [self.window makeKeyAndOrderFront:nil];
}

- (void)updateButtonStates {
    NSInteger row = self.tableView.selectedRow;
    self.removeButton.enabled = (row >= 0 && row < (NSInteger)self.items.count);
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    (void)tableView;
    return self.items.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    (void)tableColumn;
    NSString *name = self.items[row];
    NSTableCellView *cell = [tableView makeViewWithIdentifier:@"IgnoreCell" owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, tableView.bounds.size.width, 36)];
        cell.identifier = @"IgnoreCell";

        NSImageView *iv = [[NSImageView alloc] initWithFrame:NSMakeRect(12, 6, 24, 24)];
        iv.tag = 101; iv.imageScaling = NSImageScaleProportionallyUpOrDown;
        [cell addSubview:iv];

        NSTextField *nameLabel = makeLabel(NSMakeRect(44, 8, cell.bounds.size.width - 60, 20), @"", [NSFont systemFontOfSize:13], nil);
        nameLabel.tag = 102; nameLabel.autoresizingMask = NSViewWidthSizable;
        [cell addSubview:nameLabel];
    }
    NSImageView *iv = [cell viewWithTag:101];
    NSTextField *nameLabel = [cell viewWithTag:102];
    nameLabel.stringValue = name;
    iv.image = [self iconForAppName:name];
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)note {
    (void)note; [self updateButtonStates];
}

- (void)showAddMenu:(NSButton *)sender {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Add Ignored Application"];
    NSMenuItem *hdr = [[NSMenuItem alloc] initWithTitle:@"Running Applications" action:nil keyEquivalent:@""];
    [hdr setEnabled:NO];
    [menu addItem:hdr];

    NSArray<NSRunningApplication *> *apps = [[NSWorkspace sharedWorkspace] runningApplications];
    NSMutableArray<NSRunningApplication *> *guiApps = [NSMutableArray array];
    for (NSRunningApplication *app in apps) {
        if (app.activationPolicy == NSApplicationActivationPolicyRegular && app.localizedName.length > 0) {
            if (![app.bundleIdentifier isEqualToString:[[NSBundle mainBundle] bundleIdentifier]]) {
                [guiApps addObject:app];
            }
        }
    }
    [guiApps sortUsingComparator:^NSComparisonResult(NSRunningApplication *a, NSRunningApplication *b) {
        return [a.localizedName localizedCaseInsensitiveCompare:b.localizedName];
    }];

    for (NSRunningApplication *app in guiApps) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:app.localizedName action:@selector(addRunningApp:) keyEquivalent:@""];
        item.target = self; item.representedObject = app.localizedName;
        if (app.icon) {
            NSImage *ic = [app.icon copy]; ic.size = NSMakeSize(16, 16); item.image = ic;
        }
        for (NSString *ex in self.items) {
            if ([ex localizedCaseInsensitiveCompare:app.localizedName] == NSOrderedSame) {
                item.state = NSControlStateValueOn; [item setEnabled:NO]; break;
            }
        }
        [menu addItem:item];
    }

    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *browse = [[NSMenuItem alloc] initWithTitle:@"Choose Other Application..." action:@selector(browseOtherApp:) keyEquivalent:@""];
    browse.target = self; [menu addItem:browse];

    NSMenuItem *byName = [[NSMenuItem alloc] initWithTitle:@"Add by Name..." action:@selector(addByName:) keyEquivalent:@""];
    byName.target = self; [menu addItem:byName];

    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, sender.bounds.size.height + 4) inView:sender];
}

- (void)addRunningApp:(NSMenuItem *)sender {
    NSString *name = sender.representedObject;
    if (name.length == 0) return;
    for (NSString *s in self.items) { if ([s localizedCaseInsensitiveCompare:name] == NSOrderedSame) return; }
    [self.items addObject:name];
    [self.tableView reloadData];
    NSInteger newRow = self.items.count - 1;
    [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:newRow] byExtendingSelection:NO];
    [self.tableView scrollRowToVisible:newRow];
    [self updateButtonStates];
}

- (void)browseOtherApp:(id)sender {
    (void)sender;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.directoryURL = [NSURL fileURLWithPath:@"/Applications"];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    panel.allowedFileTypes = @[@"app"];
#pragma clang diagnostic pop
    panel.allowsMultipleSelection = NO;
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse res) {
        if (res == NSModalResponseOK && panel.URL) {
            NSString *name = [[panel.URL lastPathComponent] stringByDeletingPathExtension];
            if (name.length > 0) {
                for (NSString *s in self.items) { if ([s localizedCaseInsensitiveCompare:name] == NSOrderedSame) return; }
                [self.items addObject:name];
                [self.tableView reloadData];
                NSInteger newRow = self.items.count - 1;
                [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:newRow] byExtendingSelection:NO];
                [self.tableView scrollRowToVisible:newRow];
                [self updateButtonStates];
            }
        }
    }];
}

- (void)addByName:(id)sender {
    (void)sender;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Add Application by Name";
    alert.informativeText = @"Enter application name or substring to ignore:";
    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 260, 24)];
    alert.accessoryView = input;
    [alert addButtonWithTitle:@"Add"];
    [alert addButtonWithTitle:@"Cancel"];
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse resp) {
        if (resp == NSAlertFirstButtonReturn) {
            NSString *val = [input.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (val.length > 0) {
                for (NSString *s in self.items) { if ([s localizedCaseInsensitiveCompare:val] == NSOrderedSame) return; }
                [self.items addObject:val];
                [self.tableView reloadData];
                NSInteger newRow = self.items.count - 1;
                [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:newRow] byExtendingSelection:NO];
                [self.tableView scrollRowToVisible:newRow];
                [self updateButtonStates];
            }
        }
    }];
}

- (void)removeSelected:(id)sender {
    (void)sender;
    NSInteger row = self.tableView.selectedRow;
    if (row < 0 || row >= (NSInteger)self.items.count) return;
    [self.items removeObjectAtIndex:row];
    [self.tableView reloadData];
    NSInteger newRow = MIN(row, (NSInteger)self.items.count - 1);
    if (newRow >= 0) [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:newRow] byExtendingSelection:NO];
    [self updateButtonStates];
}

- (void)clearAll:(id)sender {
    (void)sender;
    [self.items removeAllObjects];
    [self.tableView reloadData];
    [self updateButtonStates];
}

- (void)saveAndClose:(id)sender {
    (void)sender;
    [CascadeEngine setIgnoredApps:self.items];
    [self.window close];
    if (self.completionHandler) self.completionHandler(YES);
}

- (void)cancelAndClose:(id)sender {
    (void)sender;
    [self.window close];
    if (self.completionHandler) self.completionHandler(NO);
}

- (NSImage *)iconForAppName:(NSString *)name {
    for (NSRunningApplication *app in [[NSWorkspace sharedWorkspace] runningApplications]) {
        if ([app.localizedName localizedCaseInsensitiveCompare:name] == NSOrderedSame) {
            if (app.icon) return app.icon;
        }
    }
    NSArray *paths = @[
        [NSString stringWithFormat:@"/Applications/%@.app", name],
        [NSString stringWithFormat:@"/System/Applications/%@.app", name],
        [NSString stringWithFormat:@"/System/Applications/Utilities/%@.app", name]
    ];
    for (NSString *p in paths) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:p]) return [[NSWorkspace sharedWorkspace] iconForFile:p];
    }
    return [NSImage imageWithSystemSymbolName:@"macwindow" accessibilityDescription:nil] ?: [NSImage imageNamed:NSImageNameApplicationIcon];
}

@end
