#import "AppOrderWindowController.h"
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

@interface AppOrderWindowController ()
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSMutableArray<NSString *> *items;
@property (nonatomic, strong) NSButton *removeButton, *upButton, *downButton, *applyCheckbox;
@property (nonatomic, copy, nullable) void (^completionHandler)(BOOL applied);
@end

@implementation AppOrderWindowController

+ (instancetype)sharedController {
    static AppOrderWindowController *shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[AppOrderWindowController alloc] init]; });
    return shared;
}

- (instancetype)init {
    if (self = [super init]) { _items = [NSMutableArray array]; }
    return self;
}

- (void)buildWindowIfNeeded {
    if (self.window) return;
    NSRect frame = NSMakeRect(0, 0, 480, 520);
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:frame
                                                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
                                                  backing:NSBackingStoreBuffered defer:NO];
    panel.title = @"Cascade — Preferred Application Order";
    panel.floatingPanel = YES;
    [panel center];
    NSView *content = panel.contentView;

    NSTextField *desc = makeLabel(NSMakeRect(20, 470, 440, 36),
                                  @"Applications at the top are placed frontmost in the cascade. Unlisted applications cascade behind them.",
                                  [NSFont systemFontOfSize:11], [NSColor secondaryLabelColor]);
    [content addSubview:desc];

    NSButton *captureBtn = makeBtn(@"📸 Capture Current Window Order", self, @selector(captureCurrentWindows:),
                                   NSMakeRect(20, 434, 440, 30), NSBezelStyleRounded,
                                   @"Read active windows on screen and populate priority in front-to-back order");
    [content addSubview:captureBtn];

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 105, 440, 320)];
    scroll.hasVerticalScroller = YES; scroll.borderType = NSBezelBorder;

    self.tableView = [[NSTableView alloc] initWithFrame:scroll.bounds];
    self.tableView.headerView = nil; self.tableView.rowHeight = 36.0;
    self.tableView.dataSource = self; self.tableView.delegate = self;
    self.tableView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.tableView registerForDraggedTypes:@[NSPasteboardTypeString]];
    [self.tableView setDraggingSourceOperationMask:NSDragOperationMove forLocal:YES];

    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"AppCol"];
    col.width = 430; [self.tableView addTableColumn:col];
    scroll.documentView = self.tableView;
    [content addSubview:scroll];

    [content addSubview:makeBtn(@"+", self, @selector(showAddMenu:), NSMakeRect(20, 72, 32, 24), NSBezelStyleSmallSquare, @"Add application")];
    self.removeButton = makeBtn(@"−", self, @selector(removeSelected:), NSMakeRect(52, 72, 32, 24), NSBezelStyleSmallSquare, @"Remove selected application");
    [content addSubview:self.removeButton];
    self.upButton = makeBtn(@"▲", self, @selector(moveSelectedUp:), NSMakeRect(92, 72, 32, 24), NSBezelStyleSmallSquare, @"Move application up (closer to front)");
    [content addSubview:self.upButton];
    self.downButton = makeBtn(@"▼", self, @selector(moveSelectedDown:), NSMakeRect(124, 72, 32, 24), NSBezelStyleSmallSquare, @"Move application down (closer to back)");
    [content addSubview:self.downButton];

    NSButton *clearBtn = makeBtn(@"Clear All", self, @selector(clearAll:), NSMakeRect(396, 72, 64, 24), NSBezelStyleInline, @"Clear all priority applications");
    clearBtn.font = [NSFont systemFontOfSize:10];
    [content addSubview:clearBtn];

    self.applyCheckbox = [NSButton checkboxWithTitle:@"Apply cascade immediately upon saving" target:nil action:nil];
    self.applyCheckbox.state = NSControlStateValueOn;
    self.applyCheckbox.frame = NSMakeRect(20, 24, 270, 22);
    [content addSubview:self.applyCheckbox];

    NSButton *cancelBtn = makeBtn(@"Cancel", self, @selector(cancelAndClose:), NSMakeRect(295, 18, 80, 32), NSBezelStyleRounded, nil);
    cancelBtn.keyEquivalent = @"\e";
    [content addSubview:cancelBtn];

    NSButton *saveBtn = makeBtn(@"Save Order", self, @selector(saveAndClose:), NSMakeRect(375, 18, 90, 32), NSBezelStyleRounded, nil);
    saveBtn.keyEquivalent = @"\r";
    [content addSubview:saveBtn];

    self.window = panel;
}

- (void)showWindowWithCompletion:(void (^)(BOOL applied))completion {
    [self buildWindowIfNeeded];
    self.completionHandler = completion;
    self.items = [[CascadeEngine preferredAppOrder] mutableCopy];
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
    BOOL hasSel = (row >= 0 && row < (NSInteger)self.items.count);
    self.removeButton.enabled = hasSel;
    self.upButton.enabled = (hasSel && row > 0);
    self.downButton.enabled = (hasSel && row < (NSInteger)self.items.count - 1);
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    (void)tableView;
    return self.items.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    (void)tableColumn;
    NSString *name = self.items[row];
    NSTableCellView *cell = [tableView makeViewWithIdentifier:@"AppCell" owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, tableView.bounds.size.width, 36)];
        cell.identifier = @"AppCell";
        NSTextField *rank = makeLabel(NSMakeRect(8, 8, 70, 20), @"", [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightMedium], nil);
        rank.tag = 101; [cell addSubview:rank];

        NSImageView *iv = [[NSImageView alloc] initWithFrame:NSMakeRect(82, 6, 24, 24)];
        iv.tag = 102; iv.imageScaling = NSImageScaleProportionallyUpOrDown;
        [cell addSubview:iv];

        NSTextField *nameLabel = makeLabel(NSMakeRect(114, 8, cell.bounds.size.width - 150, 20), @"", [NSFont systemFontOfSize:13], nil);
        nameLabel.tag = 103; nameLabel.autoresizingMask = NSViewWidthSizable;
        [cell addSubview:nameLabel];

        NSTextField *handle = makeLabel(NSMakeRect(cell.bounds.size.width - 32, 8, 24, 20), @"≡", [NSFont systemFontOfSize:14], [NSColor tertiaryLabelColor]);
        handle.tag = 104; handle.alignment = NSTextAlignmentCenter; handle.autoresizingMask = NSViewMinXMargin;
        [cell addSubview:handle];
    }
    NSTextField *rank = [cell viewWithTag:101];
    NSImageView *iv = [cell viewWithTag:102];
    NSTextField *nameLabel = [cell viewWithTag:103];

    rank.stringValue = (row == 0) ? @"#1 Front" : [NSString stringWithFormat:@"#%ld", (long)(row + 1)];
    rank.textColor = (row == 0) ? [NSColor systemBlueColor] : [NSColor secondaryLabelColor];
    nameLabel.stringValue = name;
    iv.image = [self iconForAppName:name];
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)note {
    (void)note; [self updateButtonStates];
}

- (id<NSPasteboardWriting>)tableView:(NSTableView *)tv pasteboardWriterForRow:(NSInteger)r {
    (void)tv;
    NSPasteboardItem *item = [[NSPasteboardItem alloc] init];
    [item setString:[NSString stringWithFormat:@"%ld", (long)r] forType:NSPasteboardTypeString];
    return item;
}

- (NSDragOperation)tableView:(NSTableView *)tv validateDrop:(id<NSDraggingInfo>)info proposedRow:(NSInteger)r proposedDropOperation:(NSTableViewDropOperation)op {
    (void)info; (void)tv;
    if (op == NSTableViewDropOn) { [tv setDropRow:r dropOperation:NSTableViewDropAbove]; }
    return NSDragOperationMove;
}

- (BOOL)tableView:(NSTableView *)tv acceptDrop:(id<NSDraggingInfo>)info row:(NSInteger)r dropOperation:(NSTableViewDropOperation)op {
    (void)op;
    NSString *rowStr = [[info draggingPasteboard] stringForType:NSPasteboardTypeString];
    if (!rowStr) return NO;
    NSInteger src = [rowStr integerValue];
    if (src < 0 || src >= (NSInteger)self.items.count) return NO;

    NSString *item = self.items[src];
    [self.items removeObjectAtIndex:src];
    NSInteger dest = (src < r) ? (r - 1) : r;
    dest = MAX(0, MIN(dest, (NSInteger)self.items.count));
    [self.items insertObject:item atIndex:dest];
    [tv reloadData];
    [tv selectRowIndexes:[NSIndexSet indexSetWithIndex:dest] byExtendingSelection:NO];
    [self updateButtonStates];
    return YES;
}

- (void)captureCurrentWindows:(id)sender {
    (void)sender;
    NSArray<CascadeWindow *> *windows = [CascadeEngine collectStandardWindowsWithOnly:nil exclude:nil];
    NSMutableArray<NSString *> *captured = [NSMutableArray array];
    for (CascadeWindow *win in windows) {
        if (win.appName.length > 0 && ![captured containsObject:win.appName]) {
            [captured addObject:win.appName];
        }
    }
    if (captured.count > 0) {
        self.items = captured;
        [self.tableView reloadData];
        [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
        [self updateButtonStates];
    } else {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"No Active Windows Detected";
        alert.informativeText = @"No standard resizable windows were found on screen to capture.";
        [alert beginSheetModalForWindow:self.window completionHandler:nil];
    }
}

- (void)showAddMenu:(NSButton *)sender {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Add Application"];
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
        if ([self.items containsObject:app.localizedName]) {
            item.state = NSControlStateValueOn; [item setEnabled:NO];
        }
        [menu addItem:item];
    }

    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *browse = [[NSMenuItem alloc] initWithTitle:@"Choose Other Application..." action:@selector(browseOtherApp:) keyEquivalent:@""];
    browse.target = self; [menu addItem:browse];

    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, sender.bounds.size.height + 4) inView:sender];
}

- (void)addRunningApp:(NSMenuItem *)sender {
    NSString *name = sender.representedObject;
    if (name.length == 0 || [self.items containsObject:name]) return;
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
            if (name.length > 0 && ![self.items containsObject:name]) {
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

- (void)removeSelected:(id)sender {
    (void)sender;
    NSInteger row = self.tableView.selectedRow;
    if (row < 0 || row >= (NSInteger)self.items.count) return;
    [self.items removeObjectAtIndex:row];
    [self.tableView reloadData];
    NSInteger newRow = MIN(row, (NSInteger)self.items.count - 1);
    if (newRow >= 0) {
        [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:newRow] byExtendingSelection:NO];
    }
    [self updateButtonStates];
}

- (void)moveSelectedUp:(id)sender {
    (void)sender;
    NSInteger row = self.tableView.selectedRow;
    if (row <= 0 || row >= (NSInteger)self.items.count) return;
    NSString *item = self.items[row];
    [self.items removeObjectAtIndex:row];
    [self.items insertObject:item atIndex:row - 1];
    [self.tableView reloadData];
    [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row - 1] byExtendingSelection:NO];
    [self updateButtonStates];
}

- (void)moveSelectedDown:(id)sender {
    (void)sender;
    NSInteger row = self.tableView.selectedRow;
    if (row < 0 || row >= (NSInteger)self.items.count - 1) return;
    NSString *item = self.items[row];
    [self.items removeObjectAtIndex:row];
    [self.items insertObject:item atIndex:row + 1];
    [self.tableView reloadData];
    [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row + 1] byExtendingSelection:NO];
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
    [CascadeEngine setPreferredAppOrder:self.items];
    BOOL applied = (self.applyCheckbox.state == NSControlStateValueOn);
    [self.window close];
    if (self.completionHandler) {
        self.completionHandler(applied);
    }
}

- (void)cancelAndClose:(id)sender {
    (void)sender;
    [self.window close];
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
        if ([[NSFileManager defaultManager] fileExistsAtPath:p]) {
            return [[NSWorkspace sharedWorkspace] iconForFile:p];
        }
    }
    return [NSImage imageWithSystemSymbolName:@"macwindow" accessibilityDescription:nil] ?: [NSImage imageNamed:NSImageNameApplicationIcon];
}

@end
