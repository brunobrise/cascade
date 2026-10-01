#import <Foundation/Foundation.h>
#import "WindowEngine.h"
#import "LoginItemManager.h"
#import "WindowWatcher.h"

@interface CliWatcherDelegate : NSObject <WindowWatcherDelegate>
@property (nonatomic, assign) CascadeOrderMode orderMode;
@property (nonatomic, assign) CGFloat delta;
@property (nonatomic, assign) BOOL restack;
@property (nonatomic, strong) NSArray<NSString *> *onlyApps;
@property (nonatomic, strong) NSArray<NSString *> *excludeApps;
@property (nonatomic, strong) NSArray<CascadeWindow *> *establishedOrder;
@end

@implementation CliWatcherDelegate
- (void)windowWatcherDidDetectChange:(WindowWatcher *)watcher {
    printf("\n[Watcher] Window lifecycle event detected! Adjusting window sizes...\n");
    [watcher performWithoutTriggering:^{
        NSArray<CascadeWindow *> *windows = [CascadeEngine collectStandardWindowsWithOnly:self.onlyApps exclude:self.excludeApps];
        if (windows.count > 0) {
            NSArray<CascadeWindow *> *planned = nil;
            if (self.establishedOrder.count > 0) {
                planned = [CascadeEngine calculateLayoutForWindows:windows
                                               preservingOrderFrom:self.establishedOrder
                                                             delta:self.delta];
            } else {
                planned = [CascadeEngine calculateLayoutForWindows:windows
                                                         orderMode:self.orderMode
                                                             delta:self.delta];
            }
            self.establishedOrder = planned;
            [CascadeEngine applyLayoutToWindows:planned restackZ:NO];
            printf("  [OK] %lu windows updated without changing order.\n", (unsigned long)planned.count);
        }
    }];
}
@end

static void printHelp(const char *prog) {
    printf("Cascade - Maximize macOS windows while keeping all clickable at anytime\n\n");
    printf("Usage: %s [options]\n\n", prog);
    printf("Options:\n");
    printf("  --apply              Apply calculated cascade layout to windows\n");
    printf("  --watch              Continuously watch and rearrange on window open/minimize/close\n");
    printf("  --plan               Display layout calculation without applying (default)\n");
    printf("  --list               List current standard windows and exit\n");
    printf("  --order <mode>       Ordering: 'mru' (default), 'spatial', or 'alpha'\n");
    printf("  --delta <pixels>     Offset/tab size in pixels (default: 40)\n");
    printf("  --no-restack         Do not re-raise windows in order\n");
    printf("  --start-at-login <op> Enable, disable, or query login item ('enable'|'disable'|'status')\n");
    printf("  --only <apps>        Comma-separated list of app names to include\n");
    printf("  --exclude <apps>     Comma-separated list of app names to exclude\n");
    printf("  --help, -h           Show this help message\n");
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        BOOL doApply = NO;
        BOOL doWatch = NO;
        BOOL doList = NO;
        BOOL restack = YES;
        CGFloat delta = 40.0;
        CascadeOrderMode orderMode = CascadeOrderModeMRU;
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
            } else if ([arg isEqualToString:@"--no-restack"]) {
                restack = NO;
            } else if ([arg isEqualToString:@"--delta"] && i + 1 < argc) {
                delta = atof(argv[++i]);
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
                NSString *modeStr = [[NSString stringWithUTF8String:argv[++i]] lowercaseString];
                if ([modeStr isEqualToString:@"spatial"]) {
                    orderMode = CascadeOrderModeSpatial;
                } else if ([modeStr hasPrefix:@"alpha"]) {
                    orderMode = CascadeOrderModeAlphabetical;
                } else {
                    orderMode = CascadeOrderModeMRU;
                }
            } else if ([arg isEqualToString:@"--only"] && i + 1 < argc) {
                NSString *csv = [NSString stringWithUTF8String:argv[++i]];
                onlyApps = [csv componentsSeparatedByString:@","];
            } else if ([arg isEqualToString:@"--exclude"] && i + 1 < argc) {
                NSString *csv = [NSString stringWithUTF8String:argv[++i]];
                excludeApps = [csv componentsSeparatedByString:@","];
            } else if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
                printHelp(argv[0]);
                return 0;
            }
        }

        if (![CascadeEngine isAccessibilityTrustedWithPrompt:YES]) {
            fprintf(stderr, "\n============================================================\n");
            fprintf(stderr, "Error: Accessibility permission is required for Cascade.\n\n");
            fprintf(stderr, "To enable:\n");
            fprintf(stderr, "  1. Open System Settings > Privacy & Security > Accessibility\n");
            fprintf(stderr, "  2. Ensure Cascade (and your Terminal app) are enabled\n\n");
            fprintf(stderr, "Or run this command to jump directly to settings:\n");
            fprintf(stderr, "  open \"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility\"\n");
            fprintf(stderr, "============================================================\n\n");
            return 1;
        }

        if (doWatch) {
            printf("Starting Cascade watcher daemon (auto-rearranging on window open/minimize/close)...\n");
            printf("Press Ctrl+C to stop.\n\n");

            CliWatcherDelegate *del = [[CliWatcherDelegate alloc] init];
            del.orderMode = orderMode;
            del.delta = delta;
            del.restack = restack;
            del.onlyApps = onlyApps;
            del.excludeApps = excludeApps;

            WindowWatcher *watcher = [[WindowWatcher alloc] initWithDelegate:del];
            [watcher startWatching];

            // Perform initial cascade
            [del windowWatcherDidDetectChange:watcher];

            [[NSRunLoop currentRunLoop] run];
            return 0;
        }

        CGFloat topInset = 0;
        CGRect usable = [CascadeEngine usableScreenFrameWithTopInset:&topInset];
        printf("Screen Usable Bounds: X=%.0f, Y=%.0f, W=%.0f, H=%.0f (Top Inset: %.0f)\n\n",
               usable.origin.x, usable.origin.y, usable.size.width, usable.size.height, topInset);

        NSArray<CascadeWindow *> *windows = [CascadeEngine collectStandardWindowsWithOnly:onlyApps exclude:excludeApps];
        if (windows.count == 0) {
            printf("No active standard windows found matching criteria.\n");
            return 0;
        }

        printf("Found %lu window(s):\n", (unsigned long)windows.count);
        for (NSUInteger i = 0; i < windows.count; i++) {
            CascadeWindow *w = windows[i];
            printf("  [%lu] %-16s | pos=(%.0f, %.0f) size=(%.0f x %.0f) | \"%s\"\n",
                   i + 1, [w.appName UTF8String],
                   w.currentFrame.origin.x, w.currentFrame.origin.y,
                   w.currentFrame.size.width, w.currentFrame.size.height,
                   [w.title UTF8String]);
        }
        printf("\n");

        if (doList) return 0;

        NSArray<CascadeWindow *> *planned = [CascadeEngine calculateLayoutForWindows:windows orderMode:orderMode delta:delta];
        if (planned.count == 0) return 0;

        CGFloat screenArea = usable.size.width * usable.size.height;
        CGFloat winArea = planned[0].targetFrame.size.width * planned[0].targetFrame.size.height;
        CGFloat ratio = (winArea / screenArea) * 100.0;

        const char *orderName = (orderMode == CascadeOrderModeMRU) ? "MRU (Front-to-Back)" :
                               (orderMode == CascadeOrderModeSpatial) ? "Spatial (Left-to-Right)" : "Alphabetical";

        printf("=== Layout Plan [%s | Delta: %.0f px] ===\n", orderName, delta);
        printf("Window Dimensions: %.0f x %.0f (%.1f%% of screen per window!)\n",
               planned[0].targetFrame.size.width, planned[0].targetFrame.size.height, ratio);
        printf("--------------------------------------------------------------------------------\n");

        for (NSUInteger i = 0; i < planned.count; i++) {
            CascadeWindow *w = planned[i];
            CGRect tf = w.targetFrame;
            printf("  [%lu] %-16s -> X=%.0f, Y=%.0f, W=%.0f, H=%.0f\n",
                   i + 1, [w.appName UTF8String], tf.origin.x, tf.origin.y, tf.size.width, tf.size.height);
            if (planned.count == 2) {
                if (i == 0) printf("      * Tab (Left edge):  [X=%.0f..%.0f, Y=%.0f..%.0f]\n", usable.origin.x, usable.origin.x + delta, usable.origin.y, usable.origin.y + usable.size.height);
                if (i == 1) printf("      * Tab (Right edge): [X=%.0f..%.0f, Y=%.0f..%.0f]\n", usable.origin.x + usable.size.width - delta, usable.origin.x + usable.size.width, usable.origin.y, usable.origin.y + usable.size.height);
            } else {
                printf("      * Permanent Tab (Top-Right):   [X=%.0f..%.0f, Y=%.0f..%.0f]\n",
                       tf.origin.x + tf.size.width - delta, tf.origin.x + tf.size.width, tf.origin.y, tf.origin.y + delta);
                printf("      * Permanent Tab (Bottom-Left): [X=%.0f..%.0f, Y=%.0f..%.0f]\n",
                       tf.origin.x, tf.origin.x + delta, tf.origin.y + tf.size.height - delta, tf.origin.y + tf.size.height);
            }
        }
        printf("--------------------------------------------------------------------------------\n");

        if (doApply) {
            printf("\nApplying changes...\n");
            [CascadeEngine applyLayoutToWindows:planned restackZ:restack];
            printf("Done! Windows arranged with maximum size and permanent click access.\n");
        } else {
            printf("\n[Dry Run] Pass '--apply' to arrange windows.\n");
        }
    }
    return 0;
}
