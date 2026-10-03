---
date: 2026-10-03
type: success
status: validated
---

# Move About to Settings Modal Success Story

## Context

Following user feedback and the overarching goal of keeping the macOS status bar menu hyper-minimal, uncluttered, and focused purely on core actions, the user requested:
> *"Move about to settings modal! think twice, don't hesitate to challenge if needed! /ultrathink"*

Previously:
- The status bar menu contained an "About Cascade" item alongside "Settings...", "Cascade Windows", "Auto-Rearrange", and "Quit".
- Having an informational "About" item at the root of a quick-action status bar menu consumed unnecessary visual vertical space and cognitive overhead.
- Meanwhile, the Settings modal (`SettingsWindowController`) already functioned as the centralized hub for preferences, but lacked an explicit version indicator and an integrated About action.

## The Ultrathink Stress-Test & Architecture

We analyzed user interaction patterns for modern macOS menu bar utility apps (e.g. Rectangle, Raycast, Bartender):

| Dimension | Previous Status Bar Menu | Modern Minimal Architecture | User Experience Benefit |
| :--- | :--- | :--- | :--- |
| **Root Menu Cleanliness** | 6 menu items + separators, including informational "About". | 4 core actionable items: Cascade, Auto-Rearrange, Settings..., Quit. | Instant visual scanning; zero extraneous non-actionable clutter. |
| **Version Visibility** | Hidden inside separate modal about dialog. | Prominently displayed in Settings modal header (`Cascade Preferences  v0.19.1`). | Immediate version verification without opening an extra dialog. |
| **About Panel Access** | Accessible only via menu bar item. | Accessible via "About Cascade..." button in Settings modal bottom bar and `showAboutPanel` API. | Intuitive co-location with configuration, licenses, and preferences. |

The execution lifecycle is illustrated below:

![Move About to Settings Modal Sequence](./diagrams/d854bdedd5474fa4/about-in-settings.svg)

*Figure 1: Sequence of invoking Settings, displaying version badge in header, and launching the standard About panel.*

## Implementation Details

### 1. Minimal Status Bar Menu ([`src/main_bar.m`](file:///Users/bruno/Code/brunobrise/cascade/src/main_bar.m))
Removed `aboutItem` from `rebuildMenu` and eliminated the standalone `showAbout:` method:

```objc
    NSMenuItem *settingsItem = makeItem(@"Settings...", self, @selector(openSettings:), NSControlStateValueOff);
    settingsItem.keyEquivalent = @",";
    settingsItem.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    [menu addItem:settingsItem];
    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *quitItem = makeItem(@"Quit Cascade", self, @selector(quitCascade:), NSControlStateValueOff);
    quitItem.keyEquivalent = @"q";
    [menu addItem:quitItem];
```

### 2. Header Version Badge & "About Cascade..." Action ([`src/SettingsWindowController.m`](file:///Users/bruno/Code/brunobrise/cascade/src/SettingsWindowController.m))
Added dynamic version display in the header and an `About Cascade...` button in the bottom control strip:

```objc
    NSString *ver = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: [NSString stringWithUTF8String:CASCADE_VERSION];
    [c addSubview:makeLabel(NSMakeRect(70, 477, 240, 22), @"Cascade Preferences", [NSFont boldSystemFontOfSize:15], [NSColor labelColor])];
    [c addSubview:makeLabel(NSMakeRect(315, 479, 135, 18), [NSString stringWithFormat:@"v%@", ver], [NSFont systemFontOfSize:12 weight:NSFontWeightMedium], [NSColor secondaryLabelColor])];
...
    NSButton *aboutBtn = [NSButton buttonWithTitle:@"About Cascade..." target:self action:@selector(aboutClicked:)];
    aboutBtn.frame = NSMakeRect(175, 20, 140, 32);
    aboutBtn.bezelStyle = NSBezelStyleRounded;
    [c addSubview:aboutBtn];
```

Implemented `showAboutPanel` and `aboutClicked:`:

```objc
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
```

## Verification & Results

1. **Unit Testing ([`tests/test_settings.m`](file:///Users/bruno/Code/brunobrise/cascade/tests/test_settings.m)):**
   - Added `testSettingsAboutPanel` verifying that `showAboutPanel` executes cleanly without throwing or crashing.
   - All 10 unit test suites pass (100% green).
2. **Line Budget ($\le 420$ LOC):**
   - `src/main_bar.m`: 315 LOC (down from 340).
   - `src/SettingsWindowController.h`: 22 LOC.
   - `src/SettingsWindowController.m`: 353 LOC (well below 420).
   - `tests/test_settings.m`: 107 LOC.
3. **App Build & Restart:**
   - Compiled, signed, installed to `~/Applications/Cascade.app`, and restarted cleanly in the status bar.
