#import <Foundation/Foundation.h>
#import "WindowEngine.h"
#import "ScreenManager.h"
#import "LoginItemManager.h"
#import "WindowWatcher.h"

@interface CliWatcherDelegate : NSObject <WindowWatcherDelegate>
@property (nonatomic, assign) CascadeOrderMode orderMode;
@property (nonatomic, assign) CGFloat delta;
@property (nonatomic, assign) BOOL restack;
@property (nonatomic, strong) NSArray<NSString *> *onlyApps;
@property (nonatomic, strong) NSArray<NSString *> *excludeApps;
@property (nonatomic, strong) NSArray<NSString *> *preferredOrder;
@property (nonatomic, strong) NSArray<CascadeWindow *> *establishedOrder;
@property (nonatomic, copy) NSString *targetScreen;
@end

@implementation CliWatcherDelegate
- (void)windowWatcherDidDetectChange:(WindowWatcher *)watcher {
    printf("\n[Watcher] Window lifecycle event detected! Adjusting window sizes...\n");
    [watcher performWithoutTriggering:^{
        NSArray<CascadeWindow *> *allWindows = [CascadeEngine collectStandardWindowsWithOnly:self.onlyApps exclude:self.excludeApps];
        if (allWindows.count == 0) return;
        NSArray<CascadeScreen *> *allScreens = [ScreenManager availableScreens];
        NSArray<CascadeScreen *> *targetScreens = [ScreenManager screensMatchingTarget:self.targetScreen inScreens:allScreens];
        NSArray<CascadeScreen *> *expandedScreens = [ScreenManager expandScreensWithSplits:targetScreens];
        NSArray<CascadeScreen *> *allExpanded = [ScreenManager expandScreensWithSplits:allScreens];
        NSDictionary *partition = [ScreenManager partitionWindows:allWindows intoScreens:allExpanded];
        NSMutableArray<CascadeWindow *> *allPlanned = [NSMutableArray array];
        for (CascadeScreen *screen in expandedScreens) {
            NSArray<CascadeWindow *> *screenWins = partition[screen] ?: @[];
            if (screenWins.count == 0) continue;
            NSArray<CascadeWindow *> *planned = self.establishedOrder.count > 0 ?
                [CascadeEngine calculateLayoutForWindows:screenWins preservingOrderFrom:self.establishedOrder delta:self.delta onUsableFrame:screen.quartzVisibleFrame] :
                [CascadeEngine calculateLayoutForWindows:screenWins orderMode:self.orderMode preferredOrder:self.preferredOrder delta:self.delta onUsableFrame:screen.quartzVisibleFrame];
            [allPlanned addObjectsFromArray:planned];
            [CascadeEngine applyLayoutToWindows:planned restackZ:NO];
        }
        if (allPlanned.count > 0) {
            NSMutableArray<CascadeWindow *> *merged = [allPlanned mutableCopy];
            for (CascadeWindow *prev in (self.establishedOrder ?: @[])) {
                BOOL has = NO;
                for (CascadeWindow *p in allPlanned) { if ([p matchesWindow:prev]) { has = YES; break; } }
                if (!has) [merged addObject:prev];
            }
            self.establishedOrder = merged;
            printf("  [OK] %lu windows updated without changing order across %lu screen(s).\n", (unsigned long)allPlanned.count, (unsigned long)targetScreens.count);
        }
    }];
}
@end

static CascadeOrderMode parseOrderMode(NSString *modeStr) {
    NSString *m = [modeStr lowercaseString];
    if ([m isEqualToString:@"spatial"]) return CascadeOrderModeSpatial;
    if ([m hasPrefix:@"alpha"]) return CascadeOrderModeAlphabetical;
    if ([m isEqualToString:@"custom"] || [m isEqualToString:@"preferred"]) return CascadeOrderModeCustom;
    return CascadeOrderModeMRU;
}

static const char *orderModeName(CascadeOrderMode mode) {
    switch (mode) {
        case CascadeOrderModeMRU: return "Most Recently Used (Front-to-Back)";
        case CascadeOrderModeSpatial: return "Spatial (Left-to-Right)";
        case CascadeOrderModeAlphabetical: return "Alphabetical (App Name)";
        case CascadeOrderModeCustom: return "Preferred Application Order";
    }
}

static void printHelp(const char *prog) {
    printf("Cascade - Maximize macOS windows while keeping all clickable at anytime\n\n");
    printf("Usage: %s [options]\n\n", prog);
    printf("Options:\n");
    printf("  --apply              Apply calculated cascade layout to windows\n");
    printf("  --watch              Continuously watch and rearrange on window open/minimize/close\n");
    printf("  --plan               Display layout calculation without applying (default)\n");
    printf("  --list               List current standard windows and exit\n");
    printf("  --list-screens       List connected screens/monitors and exit\n");
    printf("  --screen <target>    Target screen ('all', 'pointer', 'primary', index, or name)\n");
    printf("  --split <1..4>       Override screen column split (1, 2, 3, or 4)\n");
    printf("  --order <mode>       Ordering: 'mru', 'spatial', 'alpha', or 'preferred'\n");
    printf("  --delta <pixels>     Offset/tab size in pixels (default: saved or 40)\n");
    printf("  --no-restack         Do not re-raise windows in order\n");
    printf("  --get-preferences    Print all saved user preferences and exit\n");
    printf("  --set-screen <target> Persist default target screen ('all'|name|index)\n");
    printf("  --set-split <1..4>   Persist default screen columns (1..4) for target screen\n");
    printf("  --set-order <mode>   Persist default order mode ('mru'|'spatial'|'alpha'|'preferred')\n");
    printf("  --set-delta <pixels> Persist default delta in pixels\n");
    printf("  --set-restack <on|off> Persist restack Z-order preference ('enable'|'disable')\n");
    printf("  --set-auto-rearrange <on|off> Persist auto-rearrange watcher preference ('enable'|'disable')\n");
    printf("  --app-order <apps>   Comma-separated list of app names to prioritize (frontmost first)\n");
    printf("  --set-app-order <apps> Persist preferred app order to preferences and exit\n");
    printf("  --get-app-order      Print current preferred app order and exit\n");
    printf("  --start-at-login <op> Enable, disable, or query login item ('enable'|'disable'|'status')\n");
    printf("  --only <apps>        Comma-separated list of app names to include\n");
    printf("  --check-permissions Run diagnostic tests on Accessibility permissions and exit\n");
    printf("  --open-permissions  Open System Settings directly to Accessibility panel and exit\n");
    printf("  --help, -h           Show this help message\n");
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        BOOL doApply = NO;
        BOOL doWatch = NO;
        BOOL doList = NO;
        BOOL restack = [CascadeEngine savedRestackZOrder];
        CGFloat delta = [CascadeEngine savedDelta];
        CascadeOrderMode orderMode = [CascadeEngine savedOrderMode];
        NSArray<NSString *> *preferredOrder = [CascadeEngine preferredAppOrder];
        NSString *targetScreen = [ScreenManager savedScreenTarget];
        NSInteger cliSplit = 0;
        NSArray<NSString *> *onlyApps = nil;
        NSArray<NSString *> *excludeApps = nil;

        for (int i = 1; i < argc; i++) {
            NSString *arg = [NSString stringWithUTF8String:argv[i]];
            if ([arg isEqualToString:@"--apply"]) {
                doApply = YES;
            } else if ([arg isEqualToString:@"--watch"]) {
                doWatch = YES;
            } else if ([arg isEqualToString:@"--plan"]) {
                doApply = NO;
            } else if ([arg isEqualToString:@"--list"]) {
                doList = YES;
            } else if ([arg isEqualToString:@"--list-screens"]) {
                NSArray<CascadeScreen *> *screens = [ScreenManager availableScreens];
                printf("Connected Displays (%lu):\n", (unsigned long)screens.count);
                for (CascadeScreen *s in screens) {
                    NSInteger sp = [ScreenManager screenSplitForScreen:s];
                    printf("  [%ld] %-24s | %4.0fx%4.0f at (%5.0f, %5.0f)%s%s\n",
                           (long)s.index, [s.name UTF8String],
                           s.quartzFrame.size.width, s.quartzFrame.size.height,
                           s.quartzFrame.origin.x, s.quartzFrame.origin.y,
                           s.isPrimary ? " [Primary]" : "",
                           sp > 1 ? [[NSString stringWithFormat:@" [%ld cols]", (long)sp] UTF8String] : "");
                    printf("       Usable: %4.0fx%4.0f at (%5.0f, %5.0f)\n",
                           s.quartzVisibleFrame.size.width, s.quartzVisibleFrame.size.height,
                           s.quartzVisibleFrame.origin.x, s.quartzVisibleFrame.origin.y);
                }
                return 0;
            } else if ([arg isEqualToString:@"--screen"] && i + 1 < argc) {
                targetScreen = [NSString stringWithUTF8String:argv[++i]];
            } else if ([arg isEqualToString:@"--split"] && i + 1 < argc) {
                cliSplit = atoi(argv[++i]);
                if (cliSplit < 1) cliSplit = 1;
                if (cliSplit > 4) cliSplit = 4;
            } else if ([arg isEqualToString:@"--set-screen"] && i + 1 < argc) {
                NSString *target = [NSString stringWithUTF8String:argv[++i]];
                [ScreenManager saveScreenTarget:target];
                printf("Saved target screen preference: %s\n", target.UTF8String);
                return 0;
            } else if ([arg isEqualToString:@"--set-split"] && i + 1 < argc) {
                NSInteger split = atoi(argv[++i]);
                [ScreenManager saveScreenSplit:split forScreenName:targetScreen];
                printf("Saved screen split preference (%ld cols) for '%s'\n", (long)split, targetScreen.UTF8String);
                return 0;
            } else if ([arg isEqualToString:@"--no-restack"]) {
                restack = NO;
            } else if ([arg isEqualToString:@"--delta"] && i + 1 < argc) {
                delta = atof(argv[++i]);
            } else if ([arg isEqualToString:@"--get-preferences"]) {
                printf("Cascade User Preferences:\n");
                printf("  Order Mode:        %s\n", orderModeName([CascadeEngine savedOrderMode]));
                printf("  Delta:             %.0f px\n", [CascadeEngine savedDelta]);
                printf("  Restack Z-Order:   %s\n", [CascadeEngine savedRestackZOrder] ? "YES" : "NO");
                printf("  Auto-Rearrange:    %s\n", [CascadeEngine savedAutoRearrange] ? "YES" : "NO");
                printf("  Screen Target:     %s\n", [ScreenManager savedScreenTarget].UTF8String);
                printf("  Screen Split:      %ld cols\n", (long)[ScreenManager savedScreenSplit]);
                NSArray *apps = [CascadeEngine preferredAppOrder];
                printf("  Preferred Apps:    %s\n", apps.count > 0 ? [apps componentsJoinedByString:@", "].UTF8String : "(none set)");
                printf("  Start at Login:    %s\n", [LoginItemManager isStartAtLoginEnabled] ? "YES" : "NO");
                return 0;
            } else if ([arg isEqualToString:@"--set-order"] && i + 1 < argc) {
                CascadeOrderMode m = parseOrderMode([NSString stringWithUTF8String:argv[++i]]);
                [CascadeEngine saveOrderMode:m];
                printf("Saved order mode: %s\n", orderModeName(m));
                return 0;
            } else if ([arg isEqualToString:@"--set-delta"] && i + 1 < argc) {
                CGFloat d = atof(argv[++i]);
                [CascadeEngine saveDelta:d];
                printf("Saved delta: %.0f px\n", d);
                return 0;
            } else if ([arg isEqualToString:@"--set-restack"] && i + 1 < argc) {
                NSString *val = [[NSString stringWithUTF8String:argv[++i]] lowercaseString];
                BOOL en = [val isEqualToString:@"enable"] || [val isEqualToString:@"yes"] || [val isEqualToString:@"1"] || [val isEqualToString:@"true"];
                [CascadeEngine saveRestackZOrder:en];
                printf("Saved restack Z-order: %s\n", en ? "YES" : "NO");
                return 0;
            } else if ([arg isEqualToString:@"--set-auto-rearrange"] && i + 1 < argc) {
                NSString *val = [[NSString stringWithUTF8String:argv[++i]] lowercaseString];
                BOOL en = [val isEqualToString:@"enable"] || [val isEqualToString:@"yes"] || [val isEqualToString:@"1"] || [val isEqualToString:@"true"];
                [CascadeEngine saveAutoRearrange:en];
                printf("Saved auto-rearrange: %s\n", en ? "YES" : "NO");
                return 0;
            } else if ([arg isEqualToString:@"--start-at-login"] && i + 1 < argc) {
                NSString *action = [[NSString stringWithUTF8String:argv[++i]] lowercaseString];
                if ([action isEqualToString:@"enable"]) {
                    NSError *err = nil;
                    if ([LoginItemManager setStartAtLoginEnabled:YES error:&err]) {
                        printf("Start at login: ENABLED\n");
                    } else {
                        fprintf(stderr, "Failed to enable start at login: %s\n", err.localizedDescription.UTF8String);
                    }
                } else if ([action isEqualToString:@"disable"]) {
                    NSError *err = nil;
                    if ([LoginItemManager setStartAtLoginEnabled:NO error:&err]) {
                        printf("Start at login: DISABLED\n");
                    } else {
                        fprintf(stderr, "Failed to disable start at login: %s\n", err.localizedDescription.UTF8String);
                    }
                } else {
                    BOOL enabled = [LoginItemManager isStartAtLoginEnabled];
                    printf("Start at login: %s\n", enabled ? "ENABLED" : "DISABLED");
                }
                return 0;
            } else if ([arg isEqualToString:@"--order"] && i + 1 < argc) {
                orderMode = parseOrderMode([NSString stringWithUTF8String:argv[++i]]);
            } else if ([arg isEqualToString:@"--app-order"] && i + 1 < argc) {
                NSString *csv = [NSString stringWithUTF8String:argv[++i]];
                preferredOrder = [CascadeEngine parseAppOrderString:csv];
                orderMode = CascadeOrderModeCustom;
            } else if ([arg isEqualToString:@"--set-app-order"] && i + 1 < argc) {
                NSString *csv = [NSString stringWithUTF8String:argv[++i]];
                NSArray<NSString *> *parsed = [CascadeEngine parseAppOrderString:csv];
                [CascadeEngine setPreferredAppOrder:parsed];
                printf("Preferred app order set to: %s\n", [parsed componentsJoinedByString:@", "].UTF8String);
                return 0;
            } else if ([arg isEqualToString:@"--get-app-order"]) {
                NSArray<NSString *> *current = [CascadeEngine preferredAppOrder];
                if (current.count > 0) {
                    printf("Current preferred app order: %s\n", [current componentsJoinedByString:@", "].UTF8String);
                } else {
                    printf("Current preferred app order: (none set)\n");
                }
                return 0;
            } else if ([arg isEqualToString:@"--only"] && i + 1 < argc) {
                NSString *csv = [NSString stringWithUTF8String:argv[++i]];
                onlyApps = [csv componentsSeparatedByString:@","];
            } else if ([arg isEqualToString:@"--exclude"] && i + 1 < argc) {
                NSString *csv = [NSString stringWithUTF8String:argv[++i]];
                excludeApps = [csv componentsSeparatedByString:@","];
            } else if ([arg isEqualToString:@"--check-permissions"]) {
                NSDictionary *d = [CascadeEngine accessibilityDiagnostics];
                BOOL ok = [d[@"trusted"] boolValue];
                printf("Cascade Accessibility Diagnostics:\n");
                printf("  Host Application:    %s\n", [d[@"hostApp"] UTF8String]);
                printf("  TCC Process Trusted: %s\n", [d[@"apiTrusted"] boolValue] ? "YES" : "NO");
                printf("  Live AX Probe:       %s (AXError: %ld)\n",
                       [d[@"functional"] boolValue] ? "FUNCTIONAL" : "DISABLED",
                       (long)[d[@"errorCode"] integerValue]);
                printf("  Effective Status:    %s\n", ok ? "GRANTED (Ready)" : "DENIED (Action Required)");
                if (!ok) {
                    printf("\nAction Required:\n");
                    printf("  Enable your terminal (%s) and Cascade in System Settings > Privacy & Security > Accessibility\n", [d[@"hostApp"] UTF8String]);
                    printf("  Or run: cascade --open-permissions\n");
                }
                return ok ? 0 : 1;
            } else if ([arg isEqualToString:@"--open-permissions"]) {
                [CascadeEngine openAccessibilitySettings];
                printf("Opened System Settings > Privacy & Security > Accessibility\n");
                return 0;
            } else if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
                printHelp(argv[0]);
                return 0;
            }
        }

        if (![CascadeEngine isAccessibilityTrustedWithPrompt:YES]) {
            NSDictionary *d = [CascadeEngine accessibilityDiagnostics];
            fprintf(stderr, "\n============================================================\n");
            fprintf(stderr, "Error: Accessibility permission is required for Cascade.\n\n");
            fprintf(stderr, "Diagnostics:\n");
            fprintf(stderr, "  Host Application: %s\n", [d[@"hostApp"] UTF8String]);
            fprintf(stderr, "  TCC Trusted:      %s\n", [d[@"apiTrusted"] boolValue] ? "YES" : "NO");
            fprintf(stderr, "  Live Probe:       %s (AXError: %ld)\n\n",
                    [d[@"functional"] boolValue] ? "FUNCTIONAL" : "DISABLED",
                    (long)[d[@"errorCode"] integerValue]);
            fprintf(stderr, "To enable:\n");
            fprintf(stderr, "  1. Open System Settings > Privacy & Security > Accessibility\n");
            fprintf(stderr, "  2. Ensure %s and Cascade are enabled\n\n", [d[@"hostApp"] UTF8String]);
            fprintf(stderr, "Or run:\n");
            fprintf(stderr, "  cascade --open-permissions\n");
            fprintf(stderr, "============================================================\n\n");
            return 1;
        }

        if (doWatch) {
            printf("Starting Cascade watcher daemon (auto-rearranging on window open/minimize/close)...\n");
            printf("Target Screen: %s\n", targetScreen.UTF8String);
            printf("Press Ctrl+C to stop.\n\n");

            CliWatcherDelegate *del = [[CliWatcherDelegate alloc] init];
            del.orderMode = orderMode;
            del.delta = delta;
            del.restack = restack;
            del.onlyApps = onlyApps;
            del.excludeApps = excludeApps;
            del.preferredOrder = preferredOrder;
            del.targetScreen = targetScreen;

            WindowWatcher *watcher = [[WindowWatcher alloc] initWithDelegate:del];
            [watcher startWatching];

            // Perform initial cascade
            [del windowWatcherDidDetectChange:watcher];

            [[NSRunLoop currentRunLoop] run];
            return 0;
        }

        NSArray<CascadeScreen *> *allScreens = [ScreenManager availableScreens];
        NSArray<CascadeScreen *> *targetScreens = [ScreenManager screensMatchingTarget:targetScreen inScreens:allScreens];
        NSArray<CascadeScreen *> *expandedScreens = nil;
        if (cliSplit > 0) {
            NSMutableArray *m = [NSMutableArray array];
            for (CascadeScreen *s in targetScreens) [m addObjectsFromArray:[ScreenManager subscreensForScreen:s splitCount:cliSplit]];
            expandedScreens = m;
        } else {
            expandedScreens = [ScreenManager expandScreensWithSplits:targetScreens];
        }
        NSArray<CascadeScreen *> *allExpanded = [ScreenManager expandScreensWithSplits:allScreens];
        printf("Screen Target: %s (%lu column(s)/screen(s) selected across %lu display(s))\n\n",
               targetScreen.UTF8String, (unsigned long)expandedScreens.count, (unsigned long)allScreens.count);

        NSArray<CascadeWindow *> *windows = [CascadeEngine collectStandardWindowsWithOnly:onlyApps exclude:excludeApps];
        if (windows.count == 0) {
            printf("No active standard windows found matching criteria.\n");
            return 0;
        }

        printf("Found %lu window(s) across displays:\n", (unsigned long)windows.count);
        for (NSUInteger i = 0; i < windows.count; i++) {
            CascadeWindow *w = windows[i];
            CascadeScreen *s = [ScreenManager screenForFrame:w.currentFrame inScreens:allScreens];
            printf("  [%lu] %-16s | Screen: %s | pos=(%.0f, %.0f) size=(%.0f x %.0f) | \"%s\"\n",
                   i + 1, [w.appName UTF8String], s ? [s.name UTF8String] : "Unknown",
                   w.currentFrame.origin.x, w.currentFrame.origin.y,
                   w.currentFrame.size.width, w.currentFrame.size.height,
                   [w.title UTF8String]);
        }
        printf("\n");

        if (doList) return 0;

        NSDictionary *partition = [ScreenManager partitionWindows:windows intoScreens:allExpanded];
        NSUInteger totalPlanned = 0;
        for (CascadeScreen *screen in expandedScreens) {
            NSArray<CascadeWindow *> *screenWins = partition[screen] ?: @[];
            if (screenWins.count == 0) {
                printf("=== Screen [%s] === No matching windows to cascade.\n\n", [screen.name UTF8String]);
                continue;
            }

            NSArray<CascadeWindow *> *planned = [CascadeEngine calculateLayoutForWindows:screenWins
                                                                               orderMode:orderMode
                                                                          preferredOrder:preferredOrder
                                                                                   delta:delta
                                                                           onUsableFrame:screen.quartzVisibleFrame];
            if (planned.count == 0) continue;
            totalPlanned += planned.count;

            CGFloat screenArea = screen.quartzVisibleFrame.size.width * screen.quartzVisibleFrame.size.height;
            CGFloat winArea = planned[0].targetFrame.size.width * planned[0].targetFrame.size.height;
            CGFloat ratio = (winArea / screenArea) * 100.0;
            const char *orderName = orderModeName(orderMode);

            printf("=== Display: %s (%dx%d) [%s | Delta: %.0f px] ===\n",
                   [screen.name UTF8String], (int)screen.quartzFrame.size.width, (int)screen.quartzFrame.size.height,
                   orderName, delta);
            printf("Usable Bounds: X=%.0f, Y=%.0f, W=%.0f, H=%.0f\n",
                   screen.quartzVisibleFrame.origin.x, screen.quartzVisibleFrame.origin.y,
                   screen.quartzVisibleFrame.size.width, screen.quartzVisibleFrame.size.height);
            printf("Window Dimensions: %.0f x %.0f (%.1f%% of screen per window!)\n",
                   planned[0].targetFrame.size.width, planned[0].targetFrame.size.height, ratio);
            printf("--------------------------------------------------------------------------------\n");

            for (NSUInteger i = 0; i < planned.count; i++) {
                CascadeWindow *w = planned[i];
                CGRect tf = w.targetFrame;
                printf("  [%lu] %-16s -> X=%.0f, Y=%.0f, W=%.0f, H=%.0f\n",
                       i + 1, [w.appName UTF8String], tf.origin.x, tf.origin.y, tf.size.width, tf.size.height);
            }
            printf("--------------------------------------------------------------------------------\n\n");

            if (doApply) {
                printf("Applying changes to %s...\n", [screen.name UTF8String]);
                [CascadeEngine applyLayoutToWindows:planned restackZ:restack];
            }
        }

        if (doApply) {
            printf("Done! %lu windows arranged across %lu target screen(s).\n", (unsigned long)totalPlanned, (unsigned long)targetScreens.count);
        } else {
            printf("[Dry Run] Pass '--apply' to arrange windows.\n");
        }
    }
    return 0;
}
