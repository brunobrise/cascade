#import <Foundation/Foundation.h>
#import "WindowEngine.h"
#import "ScreenManager.h"
#import "LoginItemManager.h"
#import "WindowWatcher.h"

@interface CliWatcherDelegate : NSObject <WindowWatcherDelegate>
@property (nonatomic, assign) CascadeOrderMode orderMode;
@property (nonatomic, assign) CascadeLayoutStyle layoutStyle;
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
                [CascadeEngine calculateLayoutForWindows:screenWins preservingOrderFrom:self.establishedOrder delta:self.delta layoutStyle:self.layoutStyle onUsableFrame:screen.quartzVisibleFrame] :
                [CascadeEngine calculateLayoutForWindows:screenWins orderMode:self.orderMode preferredOrder:self.preferredOrder delta:self.delta layoutStyle:self.layoutStyle onUsableFrame:screen.quartzVisibleFrame];
            [allPlanned addObjectsFromArray:planned];
            [CascadeEngine applyLayoutToWindows:planned restackZ:NO];
        }
        if (allPlanned.count > 0) {
            NSMutableArray<CascadeWindow *> *merged = [NSMutableArray array];
            if (self.establishedOrder.count > 0) {
                NSMutableSet<CascadeWindow *> *used = [NSMutableSet set];
                for (CascadeWindow *prev in self.establishedOrder) {
                    CascadeWindow *matched = nil;
                    for (CascadeWindow *p in allPlanned) { if ([p matchesWindow:prev]) { matched = p; break; } }
                    if (matched) { [merged addObject:matched]; [used addObject:matched]; }
                    else { [merged addObject:prev]; }
                }
                for (CascadeWindow *p in allPlanned) { if (![used containsObject:p]) [merged addObject:p]; }
            } else { [merged addObjectsFromArray:allPlanned]; }
            self.establishedOrder = merged;
            printf("  [OK] %lu windows updated without changing order across %lu screen(s).\n", (unsigned long)allPlanned.count, (unsigned long)targetScreens.count);
        }
    }];
}
@end

static CascadeOrderMode parseOrderMode(NSString *s) {
    NSString *m = [s lowercaseString];
    if ([m isEqualToString:@"spatial"]) return CascadeOrderModeSpatial;
    if ([m hasPrefix:@"alpha"]) return CascadeOrderModeAlphabetical;
    if ([m isEqualToString:@"custom"] || [m isEqualToString:@"preferred"]) return CascadeOrderModeCustom;
    return CascadeOrderModeMRU;
}

static const char *orderModeName(CascadeOrderMode mode) {
    if (mode == CascadeOrderModeSpatial) return "Spatial (Left-to-Right)";
    if (mode == CascadeOrderModeAlphabetical) return "Alphabetical (App Name)";
    if (mode == CascadeOrderModeCustom) return "Preferred Application Order";
    return "Most Recently Used (Front-to-Back)";
}

static CascadeLayoutStyle parseLayoutStyle(NSString *s) {
    NSString *l = [s lowercaseString];
    if ([l containsString:@"quad"] || [l containsString:@"edge"] || [l containsString:@"perimeter"]) return CascadeLayoutStyleQuadEdge;
    return CascadeLayoutStyleDiagonal;
}

static const char *layoutStyleName(CascadeLayoutStyle style) {
    return (style == CascadeLayoutStyleQuadEdge) ? "Quad-Edge (Clockwise Perimeter)" : "Diagonal Cascade";
}

static void printHelp(const char *prog) {
    printf("Cascade - Maximize macOS windows while keeping all clickable at anytime\n\n"
           "Usage: %s [options]\n\n"
           "Options:\n"
           "  --apply, --plan, --watch   Cascade execution modes (apply, plan/preview, daemon watcher)\n"
           "  --list, --list-screens     List on-screen windows or connected displays and exit\n"
           "  --screen <target>          Target screen ('all', 'pointer', 'primary', index, or name)\n"
           "  --split <1..4>             Override screen column split (1, 2, 3, or 4)\n"
           "  --layout <style>           Layout style ('diagonal' or 'quad-edge')\n"
           "  --order <mode>             Ordering: 'mru', 'spatial', 'alpha', or 'preferred'\n"
           "  --delta <pixels>           Offset/tab size in pixels (default: saved or 40)\n"
           "  --no-restack               Do not re-raise windows in order\n"
           "  --get-preferences          Print all saved user preferences and exit\n"
           "  --set-layout <style>       Persist default layout style ('diagonal'|'quad-edge')\n"
           "  --get-layout               Print current default layout style and exit\n"
           "  --set-screen <target>      Persist default target screen ('all'|name|index)\n"
           "  --set-split <1..4>         Persist default screen columns (1..4) for target screen\n"
           "  --set-order <mode>         Persist default order mode ('mru'|'spatial'|'alpha'|'preferred')\n"
           "  --set-delta <pixels>       Persist default delta in pixels\n"
           "  --set-restack <on|off>     Persist restack Z-order preference ('enable'|'disable')\n"
           "  --set-auto-rearrange <on|off> Persist auto-rearrange watcher preference ('enable'|'disable')\n"
           "  --app-order, --set-app-order, --get-app-order Preferred app order management\n"
           "  --get-ignored, --set-ignored, --add-ignore, --remove-ignore, --clear-ignored, --no-ignore Ignored apps\n"
           "  --start-at-login <op>      Enable, disable, or query login item ('enable'|'disable'|'status')\n"
           "  --only <apps>, --exclude <apps> Filter apps for this cascade run\n"
           "  --check-permissions, --open-permissions Accessibility diagnostic and setup\n"
           "  --version, -v, --help, -h  Display version or this help message\n", prog);
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        BOOL doApply = NO, doWatch = NO, doList = NO, bypassIgnore = NO;
        BOOL restack = [CascadeEngine savedRestackZOrder];
        CGFloat delta = [CascadeEngine savedDelta];
        CascadeOrderMode orderMode = [CascadeEngine savedOrderMode];
        CascadeLayoutStyle layoutStyle = [CascadeEngine savedLayoutStyle];
        NSArray<NSString *> *preferredOrder = [CascadeEngine preferredAppOrder];
        NSString *targetScreen = [ScreenManager savedScreenTarget];
        NSInteger cliSplit = 0;
        NSArray<NSString *> *onlyApps = nil;
        NSMutableArray<NSString *> *cliExcludes = [NSMutableArray array];

        for (int i = 1; i < argc; i++) {
            NSString *arg = [NSString stringWithUTF8String:argv[i]];
            if ([arg isEqualToString:@"--apply"]) { doApply = YES; }
            else if ([arg isEqualToString:@"--watch"]) { doWatch = YES; }
            else if ([arg isEqualToString:@"--plan"]) { doApply = NO; }
            else if ([arg isEqualToString:@"--list"]) { doList = YES; }
            else if ([arg isEqualToString:@"--list-screens"]) {
                NSArray<CascadeScreen *> *screens = [ScreenManager availableScreens];
                printf("Connected Displays (%lu):\n", (unsigned long)screens.count);
                for (NSUInteger idx = 0; idx < screens.count; idx++) {
                    CascadeScreen *s = screens[idx];
                    printf("  [%lu] %s (%dx%d)%s [Split: %ld cols]\n",
                           (unsigned long)idx, [s.name UTF8String], (int)s.quartzFrame.size.width, (int)s.quartzFrame.size.height,
                           s.isPrimary ? " [Primary]" : "", (long)[ScreenManager screenSplitForScreen:s]);
                }
                return 0;
            } else if ([arg isEqualToString:@"--screen"] && i + 1 < argc) {
                targetScreen = [NSString stringWithUTF8String:argv[++i]];
            } else if ([arg isEqualToString:@"--split"] && i + 1 < argc) {
                cliSplit = atoi(argv[++i]);
                if (cliSplit < 1) cliSplit = 1; if (cliSplit > 4) cliSplit = 4;
            } else if ([arg isEqualToString:@"--layout"] && i + 1 < argc) {
                layoutStyle = parseLayoutStyle([NSString stringWithUTF8String:argv[++i]]);
            } else if ([arg isEqualToString:@"--get-layout"]) {
                printf("Layout Style: %s\n", layoutStyleName([CascadeEngine savedLayoutStyle]));
                return 0;
            } else if ([arg isEqualToString:@"--set-layout"] && i + 1 < argc) {
                CascadeLayoutStyle s = parseLayoutStyle([NSString stringWithUTF8String:argv[++i]]);
                [CascadeEngine saveLayoutStyle:s];
                printf("Layout style set to: %s\n", layoutStyleName(s));
                return 0;
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
                printf("  Layout Style:      %s\n", layoutStyleName([CascadeEngine savedLayoutStyle]));
                printf("  Order Mode:        %s\n", orderModeName([CascadeEngine savedOrderMode]));
                printf("  Delta:             %.0f px\n", [CascadeEngine savedDelta]);
                printf("  Restack Z-Order:   %s\n", [CascadeEngine savedRestackZOrder] ? "YES" : "NO");
                printf("  Auto-Rearrange:    %s\n", [CascadeEngine savedAutoRearrange] ? "YES" : "NO");
                printf("  Screen Target:     %s\n", [ScreenManager savedScreenTarget].UTF8String);
                printf("  Screen Split:      %ld cols\n", (long)[ScreenManager savedScreenSplit]);
                NSArray *apps = [CascadeEngine preferredAppOrder];
                printf("  Preferred Apps:    %s\n", apps.count > 0 ? [apps componentsJoinedByString:@", "].UTF8String : "(none set)");
                NSArray *ignored = [CascadeEngine ignoredApps];
                printf("  Ignored Apps:      %s\n", ignored.count > 0 ? [ignored componentsJoinedByString:@", "].UTF8String : "(none set)");
                printf("  Start at Login:    %s\n", [LoginItemManager isStartAtLoginEnabled] ? "YES" : "NO");
                return 0;
            } else if ([arg isEqualToString:@"--set-order"] && i + 1 < argc) {
                CascadeOrderMode m = parseOrderMode([NSString stringWithUTF8String:argv[++i]]);
                [CascadeEngine saveOrderMode:m]; [CascadeEngine saveEstablishedWindowOrder:@[]];
                printf("Saved order mode: %s\n", orderModeName(m)); return 0;
            } else if ([arg isEqualToString:@"--set-delta"] && i + 1 < argc) {
                CGFloat d = atof(argv[++i]); [CascadeEngine saveDelta:d];
                printf("Saved delta: %.0f px\n", d); return 0;
            } else if ([arg isEqualToString:@"--set-restack"] && i + 1 < argc) {
                NSString *val = [[NSString stringWithUTF8String:argv[++i]] lowercaseString];
                BOOL en = [val isEqualToString:@"enable"] || [val isEqualToString:@"yes"] || [val isEqualToString:@"1"] || [val isEqualToString:@"true"];
                [CascadeEngine saveRestackZOrder:en]; printf("Saved restack Z-order: %s\n", en ? "YES" : "NO"); return 0;
            } else if ([arg isEqualToString:@"--set-auto-rearrange"] && i + 1 < argc) {
                NSString *val = [[NSString stringWithUTF8String:argv[++i]] lowercaseString];
                BOOL en = [val isEqualToString:@"enable"] || [val isEqualToString:@"yes"] || [val isEqualToString:@"1"] || [val isEqualToString:@"true"];
                [CascadeEngine saveAutoRearrange:en]; printf("Saved auto-rearrange: %s\n", en ? "YES" : "NO"); return 0;
            } else if ([arg isEqualToString:@"--start-at-login"] && i + 1 < argc) {
                NSString *act = [[NSString stringWithUTF8String:argv[++i]] lowercaseString];
                if ([act isEqualToString:@"enable"] || [act isEqualToString:@"disable"]) {
                    BOOL en = [act isEqualToString:@"enable"]; NSError *err = nil;
                    if ([LoginItemManager setStartAtLoginEnabled:en error:&err]) printf("Start at login: %s\n", en ? "ENABLED" : "DISABLED");
                    else fprintf(stderr, "Failed to update start at login: %s\n", err.localizedDescription.UTF8String);
                } else {
                    printf("Start at login: %s\n", [LoginItemManager isStartAtLoginEnabled] ? "ENABLED" : "DISABLED");
                }
                return 0;
            } else if ([arg isEqualToString:@"--order"] && i + 1 < argc) {
                orderMode = parseOrderMode([NSString stringWithUTF8String:argv[++i]]);
            } else if ([arg isEqualToString:@"--app-order"] && i + 1 < argc) {
                preferredOrder = [CascadeEngine parseAppOrderString:[NSString stringWithUTF8String:argv[++i]]];
                orderMode = CascadeOrderModeCustom;
            } else if ([arg isEqualToString:@"--set-app-order"] && i + 1 < argc) {
                NSArray<NSString *> *parsed = [CascadeEngine parseAppOrderString:[NSString stringWithUTF8String:argv[++i]]];
                [CascadeEngine setPreferredAppOrder:parsed]; [CascadeEngine saveEstablishedWindowOrder:@[]];
                printf("Preferred app order set to: %s\n", [parsed componentsJoinedByString:@", "].UTF8String);
                return 0;
            } else if ([arg isEqualToString:@"--get-app-order"]) {
                NSArray<NSString *> *cur = [CascadeEngine preferredAppOrder];
                printf("Current preferred app order: %s\n", cur.count > 0 ? [cur componentsJoinedByString:@", "].UTF8String : "(none set)");
                return 0;
            } else if ([arg isEqualToString:@"--get-ignored"] || [arg isEqualToString:@"--get-ignore"]) {
                NSArray *cur = [CascadeEngine ignoredApps];
                printf("Ignored applications: %s\n", cur.count > 0 ? [cur componentsJoinedByString:@", "].UTF8String : "(none set)");
                return 0;
            } else if ([arg isEqualToString:@"--set-ignored"] && i + 1 < argc) {
                NSArray *parsed = [CascadeEngine parseAppOrderString:[NSString stringWithUTF8String:argv[++i]]];
                [CascadeEngine setIgnoredApps:parsed];
                printf("Ignored applications set to: %s\n", parsed.count > 0 ? [parsed componentsJoinedByString:@", "].UTF8String : "(none set)");
                return 0;
            } else if ([arg isEqualToString:@"--add-ignore"] && i + 1 < argc) {
                NSString *app = [NSString stringWithUTF8String:argv[++i]];
                [CascadeEngine addIgnoredApp:app];
                printf("Added '%s' to ignored apps. Current: %s\n", app.UTF8String, [[CascadeEngine ignoredApps] componentsJoinedByString:@", "].UTF8String);
                return 0;
            } else if ([arg isEqualToString:@"--remove-ignore"] && i + 1 < argc) {
                NSString *app = [NSString stringWithUTF8String:argv[++i]];
                [CascadeEngine removeIgnoredApp:app];
                printf("Removed '%s' from ignored apps. Current: %s\n", app.UTF8String, [[CascadeEngine ignoredApps] componentsJoinedByString:@", "].UTF8String);
                return 0;
            } else if ([arg isEqualToString:@"--clear-ignored"]) {
                [CascadeEngine clearIgnoredApps];
                printf("Cleared ignored applications.\n");
                return 0;
            } else if ([arg isEqualToString:@"--no-ignore"]) {
                bypassIgnore = YES;
            } else if ([arg isEqualToString:@"--only"] && i + 1 < argc) {
                onlyApps = [CascadeEngine parseAppOrderString:[NSString stringWithUTF8String:argv[++i]]];
            } else if (([arg isEqualToString:@"--exclude"] || [arg isEqualToString:@"--ignore"]) && i + 1 < argc) {
                NSString *csv = [NSString stringWithUTF8String:argv[++i]];
                [cliExcludes addObjectsFromArray:[CascadeEngine parseAppOrderString:csv]];
            } else if ([arg isEqualToString:@"--check-permissions"]) {
                NSDictionary *d = [CascadeEngine accessibilityDiagnostics];
                BOOL ok = [d[@"trusted"] boolValue];
                printf("Cascade Accessibility Diagnostics:\n"
                       "  Host Application:    %s\n"
                       "  TCC Process Trusted: %s\n"
                       "  Live AX Probe:       %s (AXError: %ld)\n"
                       "  Effective Status:    %s\n",
                       [d[@"hostApp"] UTF8String], [d[@"apiTrusted"] boolValue] ? "YES" : "NO",
                       [d[@"functional"] boolValue] ? "FUNCTIONAL" : "DISABLED",
                       (long)[d[@"errorCode"] integerValue], ok ? "GRANTED (Ready)" : "DENIED (Action Required)");
                if (!ok) printf("\nAction Required:\n  Enable terminal (%s) and Cascade in Accessibility Settings\n  Or run: cascade --open-permissions\n", [d[@"hostApp"] UTF8String]);
                return ok ? 0 : 1;
            } else if ([arg isEqualToString:@"--open-permissions"]) {
                [CascadeEngine openAccessibilitySettings];
                printf("Opened System Settings > Privacy & Security > Accessibility\n");
                return 0;
            } else if ([arg isEqualToString:@"--version"] || [arg isEqualToString:@"-v"]) {
#ifdef CASCADE_VERSION
                printf("Cascade %s\n", CASCADE_VERSION);
#else
                printf("Cascade 0.17.0\n");
#endif
                return 0;
            } else if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
                printHelp(argv[0]);
                return 0;
            } else {
                fprintf(stderr, "Unknown option: %s\nRun '%s --help' for usage.\n", argv[i], argv[0]);
                return 1;
            }
        }

        if (![CascadeEngine isAccessibilityTrustedWithPrompt:YES]) {
            NSDictionary *d = [CascadeEngine accessibilityDiagnostics];
            fprintf(stderr, "\n============================================================\n"
                            "Error: Accessibility permission is required for Cascade.\n\n"
                            "Diagnostics:\n"
                            "  Host Application: %s\n"
                            "  TCC Trusted:      %s\n"
                            "  Live Probe:       %s (AXError: %ld)\n\n"
                            "To enable:\n"
                            "  1. Open System Settings > Privacy & Security > Accessibility\n"
                            "  2. Ensure %s and Cascade are enabled\n\n"
                            "Or run: cascade --open-permissions\n"
                            "============================================================\n\n",
                    [d[@"hostApp"] UTF8String], [d[@"apiTrusted"] boolValue] ? "YES" : "NO",
                    [d[@"functional"] boolValue] ? "FUNCTIONAL" : "DISABLED",
                    (long)[d[@"errorCode"] integerValue], [d[@"hostApp"] UTF8String]);
            return 1;
        }

        NSMutableArray<NSString *> *effectiveExclude = [NSMutableArray array];
        if (!bypassIgnore) [effectiveExclude addObjectsFromArray:[CascadeEngine ignoredApps]];
        [effectiveExclude addObjectsFromArray:cliExcludes];
        NSArray<NSString *> *finalExcludes = effectiveExclude.count > 0 ? effectiveExclude : nil;

        if (doWatch) {
            printf("Starting Cascade watcher daemon (auto-rearranging on window open/minimize/close)...\n");
            printf("Target Screen: %s | Layout: %s\n", targetScreen.UTF8String, layoutStyleName(layoutStyle));
            printf("Press Ctrl+C to stop.\n");

            CliWatcherDelegate *del = [[CliWatcherDelegate alloc] init];
            del.orderMode = orderMode; del.layoutStyle = layoutStyle; del.delta = delta; del.restack = restack;
            del.onlyApps = onlyApps; del.excludeApps = finalExcludes; del.preferredOrder = preferredOrder; del.targetScreen = targetScreen;

            WindowWatcher *watcher = [[WindowWatcher alloc] initWithDelegate:del];
            watcher.excludeApps = finalExcludes;
            [watcher startWatching];

            [del windowWatcherDidDetectChange:watcher];
            [[NSRunLoop currentRunLoop] run];
            return 0;
        }

        NSArray<CascadeScreen *> *allScreens = [ScreenManager availableScreens];
        NSArray<CascadeScreen *> *targetScreens = [ScreenManager screensMatchingTarget:targetScreen inScreens:allScreens];
        NSArray<CascadeScreen *> *expandedScreens;
        if (cliSplit > 0) {
            NSMutableArray *m = [NSMutableArray array];
            for (CascadeScreen *s in targetScreens) [m addObjectsFromArray:[ScreenManager subscreensForScreen:s splitCount:cliSplit]];
            expandedScreens = m;
        } else { expandedScreens = [ScreenManager expandScreensWithSplits:targetScreens]; }
        NSArray<CascadeScreen *> *allExpanded = [ScreenManager expandScreensWithSplits:allScreens];
        printf("Screen Target: %s (%lu column(s)/screen(s) selected across %lu display(s))\n",
               targetScreen.UTF8String, (unsigned long)expandedScreens.count, (unsigned long)allScreens.count);
        printf("Layout Style: %s\n\n", layoutStyleName(layoutStyle));

        NSArray<CascadeWindow *> *windows = [CascadeEngine collectStandardWindowsWithOnly:onlyApps exclude:finalExcludes];
        if (windows.count == 0) {
            printf("No active standard windows found matching criteria.\n");
            return 0;
        }

        if (doList) {
            printf("Found %lu active standard window(s):\n", (unsigned long)windows.count);
            for (NSUInteger i = 0; i < windows.count; i++) {
                CascadeWindow *w = windows[i];
                printf("  [%lu] PID=%-5d App=\"%-20s\" Title=\"%s\"\n",
                       (unsigned long)i, w.pid, [w.appName UTF8String], [w.title UTF8String]);
            }
            return 0;
        }

        NSDictionary<CascadeScreen *, NSArray<CascadeWindow *> *> *partition = [ScreenManager partitionWindows:windows intoScreens:allExpanded];
        NSUInteger totalPlanned = 0;

        for (CascadeScreen *screen in expandedScreens) {
            NSArray<CascadeWindow *> *screenWins = partition[screen] ?: @[];
            if (screenWins.count == 0) {
                printf("=== Display: %s (%dx%d) [No Windows] ===\n\n",
                       [screen.name UTF8String], (int)screen.quartzFrame.size.width, (int)screen.quartzFrame.size.height);
                continue;
            }

            NSArray<CascadeWindow *> *planned = [CascadeEngine calculateLayoutForWindows:screenWins orderMode:orderMode preferredOrder:preferredOrder delta:delta layoutStyle:layoutStyle onUsableFrame:screen.quartzVisibleFrame];
            if (planned.count == 0) continue;
            totalPlanned += planned.count;

            CGFloat screenArea = screen.quartzVisibleFrame.size.width * screen.quartzVisibleFrame.size.height;
            CGFloat winArea = planned[0].targetFrame.size.width * planned[0].targetFrame.size.height;
            CGFloat ratio = (winArea / screenArea) * 100.0;
            const char *orderName = orderModeName(orderMode);

            printf("=== Display: %s (%dx%d) [%s | %s | Delta: %.0f px] ===\n"
                   "Usable Bounds: X=%.0f, Y=%.0f, W=%.0f, H=%.0f\n"
                   "Window Dimensions: %.0f x %.0f (%.1f%% of screen per window!)\n"
                   "--------------------------------------------------------------------------------\n",
                   [screen.name UTF8String], (int)screen.quartzFrame.size.width, (int)screen.quartzFrame.size.height,
                   orderName, layoutStyleName(layoutStyle), delta,
                   screen.quartzVisibleFrame.origin.x, screen.quartzVisibleFrame.origin.y,
                   screen.quartzVisibleFrame.size.width, screen.quartzVisibleFrame.size.height,
                   planned[0].targetFrame.size.width, planned[0].targetFrame.size.height, ratio);

            for (NSUInteger i = 0; i < planned.count; i++) {
                CascadeWindow *w = planned[i];
                printf("  [%lu] PID=%-5d App=\"%-18s\" Origin=(%-4.0f, %-4.0f) Size=(%-4.0f, %-4.0f) Title=\"%s\"\n",
                       (unsigned long)i, w.pid, [w.appName UTF8String],
                       w.targetFrame.origin.x, w.targetFrame.origin.y,
                       w.targetFrame.size.width, w.targetFrame.size.height,
                       [w.title UTF8String]);
            }
            printf("\n");

            if (doApply) {
                [CascadeEngine applyLayoutToWindows:planned restackZ:restack];
            }
        }

        if (doApply) {
            printf("Successfully applied cascade layout to %lu window(s) across %lu display(s)!\n",
                   (unsigned long)totalPlanned, (unsigned long)expandedScreens.count);
        } else {
            printf("Plan complete for %lu window(s). Run with '--apply' to execute layout.\n",
                   (unsigned long)totalPlanned);
        }
    }
    return 0;
}
