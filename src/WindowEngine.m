#import "WindowEngine.h"
#import "ScreenManager.h"
#import "WindowLayoutGeometry.h"

@implementation CascadeWindow
- (void)dealloc {
    if (_axRef) CFRelease(_axRef);
}

- (BOOL)matchesWindow:(CascadeWindow *)other {
    if (!other) return NO;
    if (self.axRef && other.axRef && CFEqual(self.axRef, other.axRef)) return YES;
    if (self.pid == other.pid && self.pid != 0) {
        if (self.title.length > 0 && other.title.length > 0) return [self.title isEqualToString:other.title];
        if ([self.appName isEqualToString:other.appName]) return YES;
    }
    if (self.appName.length > 0 && [self.appName isEqualToString:other.appName]) {
        return (self.title.length > 0 && other.title.length > 0) ? [self.title isEqualToString:other.title] : YES;
    }
    return NO;
}
@end

@interface CascadeAppGroup : NSObject
@property (nonatomic, copy) NSString *appName;
@property (nonatomic, strong) NSMutableArray<CascadeWindow *> *windows;
@property (nonatomic, assign) NSInteger minZRank;
@property (nonatomic, assign) CGFloat minOriginX;
@property (nonatomic, assign) NSInteger preferredRank;
@property (nonatomic, assign) NSUInteger firstAppearanceIndex;
@end

@implementation CascadeAppGroup
- (instancetype)initWithAppName:(NSString *)name firstIndex:(NSUInteger)idx {
    self = [super init];
    if (self) {
        _appName = name ?: @"";
        _windows = [NSMutableArray array];
        _minZRank = NSIntegerMax;
        _minOriginX = CGFLOAT_MAX;
        _preferredRank = 999999;
        _firstAppearanceIndex = idx;
    }
    return self;
}
@end

@implementation CascadeEngine

+ (CGRect)usableScreenFrameWithTopInset:(CGFloat *)outTopInset {
    CascadeScreen *primary = [ScreenManager primaryScreen];
    if (primary) {
        if (outTopInset) *outTopInset = primary.quartzVisibleFrame.origin.y;
        return primary.quartzVisibleFrame;
    }
    NSScreen *screen = [NSScreen mainScreen];
    NSRect sf = [screen frame], vf = [screen visibleFrame];
    CGFloat topInset = sf.size.height - (vf.origin.y + vf.size.height);
    if (outTopInset) *outTopInset = topInset;
    return CGRectMake(vf.origin.x, topInset, vf.size.width, vf.size.height);
}

+ (NSDictionary<NSString *, id> *)accessibilityDiagnostics {
    BOOL apiTrusted = AXIsProcessTrusted(), functional = YES;
    NSInteger errorCode = 0;
    AXUIElementRef sysWide = AXUIElementCreateSystemWide();
    if (sysWide) {
        CFTypeRef focusedApp = NULL;
        AXError err = AXUIElementCopyAttributeValue(sysWide, kAXFocusedApplicationAttribute, &focusedApp);
        CFRelease(sysWide);
        if (focusedApp) CFRelease(focusedApp);
        errorCode = (NSInteger)err;
        if (err == kAXErrorAPIDisabled) functional = NO;
    } else { functional = NO; }
    NSString *parentApp = [[NSWorkspace sharedWorkspace] frontmostApplication].localizedName ?: @"Unknown";
    return @{ @"apiTrusted": @(apiTrusted), @"functional": @(functional),
              @"errorCode": @(errorCode), @"trusted": @(apiTrusted && functional), @"hostApp": parentApp };
}

+ (BOOL)isAccessibilityTrustedWithPrompt:(BOOL)prompt {
    if (prompt) {
        NSDictionary *options = @{(__bridge id)kAXTrustedCheckOptionPrompt: @YES};
        AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
    }
    return [[self accessibilityDiagnostics][@"trusted"] boolValue];
}

+ (void)openAccessibilitySettings {
    NSArray *urls = @[@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
                      @"x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"];
    for (NSString *str in urls) {
        if ([[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:str]]) return;
    }
    [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:@"/System/Applications/System Settings.app"]];
}

static BOOL listMatchesApp(NSArray<NSString *> *list, NSString *appName) {
    if (!list || list.count == 0 || appName.length == 0) return NO;
    for (NSString *item in list) {
        NSString *trimmed = [item stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length == 0) continue;
        if ([appName localizedCaseInsensitiveCompare:trimmed] == NSOrderedSame ||
            [appName localizedCaseInsensitiveContainsString:trimmed]) return YES;
    }
    return NO;
}

+ (NSArray<CascadeWindow *> *)collectStandardWindowsWithOnly:(NSArray<NSString *> *)onlyApps
                                                      exclude:(NSArray<NSString *> *)excludeApps {
    CFArrayRef windowList = CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements, kCGNullWindowID);
    if (!windowList) return @[];

    NSArray *cgWindows = (NSArray *)CFBridgingRelease(windowList);
    NSMutableDictionary<NSNumber *, NSNumber *> *pidToZRank = [NSMutableDictionary dictionary];
    int zRank = 1;
    for (NSDictionary *info in cgWindows) {
        NSNumber *layer = info[(id)kCGWindowLayer];
        if ([layer intValue] != 0) continue;
        NSNumber *pid = info[(id)kCGWindowOwnerPID];
        if (!pidToZRank[pid]) pidToZRank[pid] = @(zRank++);
    }

    NSMutableArray<CascadeWindow *> *result = [NSMutableArray array];
    NSArray<NSRunningApplication *> *apps = [[NSWorkspace sharedWorkspace] runningApplications];

    for (NSRunningApplication *app in apps) {
        if (app.activationPolicy != NSApplicationActivationPolicyRegular) continue;
        NSString *appName = app.localizedName ?: @"";
        if (onlyApps && !listMatchesApp(onlyApps, appName)) continue;
        if (excludeApps && listMatchesApp(excludeApps, appName)) continue;

        pid_t pid = app.processIdentifier;
        AXUIElementRef appRef = AXUIElementCreateApplication(pid);
        if (!appRef) continue;

        CFTypeRef winsRef = NULL;
        if (AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute, &winsRef) == kAXErrorSuccess && winsRef) {
            NSArray *appWins = (NSArray *)CFBridgingRelease(winsRef);
            NSUInteger winIdx = 0;
            for (id winObj in appWins) {
                AXUIElementRef win = (__bridge AXUIElementRef)winObj;

                CFTypeRef subroleRef = NULL, minRef = NULL, titleRef = NULL, posRef = NULL, szRef = NULL;
                AXUIElementCopyAttributeValue(win, kAXSubroleAttribute, &subroleRef);
                AXUIElementCopyAttributeValue(win, kAXMinimizedAttribute, &minRef);
                AXUIElementCopyAttributeValue(win, kAXTitleAttribute, &titleRef);
                AXUIElementCopyAttributeValue(win, kAXPositionAttribute, &posRef);
                AXUIElementCopyAttributeValue(win, kAXSizeAttribute, &szRef);

                NSString *subrole = subroleRef ? (NSString *)CFBridgingRelease(subroleRef) : @"";
                BOOL isMin = minRef ? CFBooleanGetValue((CFBooleanRef)minRef) : NO;
                if (minRef) CFRelease(minRef);
                CGPoint curPos = CGPointZero; CGSize curSize = CGSizeZero;
                if (posRef) { AXValueGetValue((AXValueRef)posRef, kAXValueTypeCGPoint, &curPos); CFRelease(posRef); }
                if (szRef) { AXValueGetValue((AXValueRef)szRef, kAXValueTypeCGSize, &curSize); CFRelease(szRef); }
                NSString *title = titleRef ? (NSString *)CFBridgingRelease(titleRef) : @"";

                if ([subrole isEqualToString:@"AXStandardWindow"] && !isMin && curSize.width > 100 && curSize.height > 100) {
                    CascadeWindow *cw = [[CascadeWindow alloc] init];
                    cw.appName = appName;
                    cw.title = title;
                    cw.pid = pid;
                    cw.axRef = (AXUIElementRef)CFRetain(win);
                    cw.currentFrame = CGRectMake(curPos.x, curPos.y, curSize.width, curSize.height);
                    NSInteger baseRank = [pidToZRank[@(pid)] integerValue] ?: 999;
                    cw.zRank = baseRank * 1000 + (winIdx++);
                    [result addObject:cw];
                }
            }
        }
        CFRelease(appRef);
    }

    return result;
}

+ (NSUserDefaults *)userDefaults {
    static NSUserDefaults *d = nil; static dispatch_once_t t;
    dispatch_once(&t, ^{ d = [[NSUserDefaults alloc] initWithSuiteName:@"com.brunobrise.cascade"] ?: [NSUserDefaults standardUserDefaults]; });
    return d;
}

static id getPref(NSString *k, id def) {
    id v = [[CascadeEngine userDefaults] objectForKey:k] ?: [[NSUserDefaults standardUserDefaults] objectForKey:k];
    return v ?: def;
}

static void setPref(NSString *k, id v) {
    NSUserDefaults *u = [CascadeEngine userDefaults], *s = [NSUserDefaults standardUserDefaults];
    if (v) { [u setObject:v forKey:k]; [s setObject:v forKey:k]; }
    else { [u removeObjectForKey:k]; [s removeObjectForKey:k]; }
    [u synchronize]; [s synchronize];
}

+ (CascadeOrderMode)savedOrderMode { NSNumber *n = getPref(@"orderMode", nil); return n ? (CascadeOrderMode)[n integerValue] : CascadeOrderModeMRU; }
+ (void)saveOrderMode:(CascadeOrderMode)m { setPref(@"orderMode", @(m)); }
+ (CascadeLayoutStyle)savedLayoutStyle { NSNumber *n = getPref(@"layoutStyle", nil); return n ? (CascadeLayoutStyle)[n integerValue] : CascadeLayoutStyleDiagonal; }
+ (void)saveLayoutStyle:(CascadeLayoutStyle)s { setPref(@"layoutStyle", @(s)); }
+ (CGFloat)savedDelta { NSNumber *n = getPref(@"delta", nil); return n ? (CGFloat)[n doubleValue] : 40.0; }
+ (void)saveDelta:(CGFloat)d { setPref(@"delta", @(d)); }
+ (BOOL)savedRestackZOrder { NSNumber *n = getPref(@"restackZOrder", nil); return n ? [n boolValue] : YES; }
+ (void)saveRestackZOrder:(BOOL)r { setPref(@"restackZOrder", @(r)); }
+ (BOOL)savedAutoRearrange { NSNumber *n = getPref(@"autoRearrange", nil); return n ? [n boolValue] : NO; }
+ (void)saveAutoRearrange:(BOOL)a { setPref(@"autoRearrange", @(a)); }
+ (NSArray<NSString *> *)preferredAppOrder { return getPref(@"preferredAppOrder", @[]); }
+ (void)setPreferredAppOrder:(NSArray<NSString *> *)o { setPref(@"preferredAppOrder", o ?: @[]); }
+ (NSArray<NSString *> *)ignoredApps { return getPref(@"ignoredApps", @[]); }
+ (void)setIgnoredApps:(NSArray<NSString *> *)a { setPref(@"ignoredApps", a ?: @[]); }
+ (void)addIgnoredApp:(NSString *)a {
    NSString *t = [a stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!t.length) return;
    NSMutableArray *m = [[self ignoredApps] mutableCopy];
    for (NSString *s in m) { if ([s localizedCaseInsensitiveCompare:t] == NSOrderedSame) return; }
    [m addObject:t]; [self setIgnoredApps:m];
}
+ (void)removeIgnoredApp:(NSString *)a {
    NSString *t = [a stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!t.length) return;
    NSMutableArray *m = [NSMutableArray array];
    for (NSString *s in [self ignoredApps]) { if ([s localizedCaseInsensitiveCompare:t] != NSOrderedSame) [m addObject:s]; }
    [self setIgnoredApps:m];
}
+ (void)clearIgnoredApps { [self setIgnoredApps:@[]]; }

+ (NSArray<NSDictionary<NSString *, NSString *> *> *)serializeWindows:(NSArray<CascadeWindow *> *)windows {
    NSMutableArray *arr = [NSMutableArray arrayWithCapacity:windows.count];
    for (CascadeWindow *w in windows) [arr addObject:@{@"appName": w.appName ?: @"", @"title": w.title ?: @""}];
    return arr;
}

+ (NSArray<CascadeWindow *> *)matchWindows:(NSArray<CascadeWindow *> *)currentWindows
                      withSavedDescriptors:(NSArray<NSDictionary<NSString *, NSString *> *> *)saved {
    if (saved.count == 0 || currentWindows.count == 0) return currentWindows;
    NSMutableArray<CascadeWindow *> *remaining = [currentWindows mutableCopy];
    NSMutableArray<CascadeWindow *> *ordered = [NSMutableArray array];
    for (NSDictionary *desc in saved) {
        NSString *sApp = desc[@"appName"] ?: @"", *sTitle = desc[@"title"] ?: @"";
        CascadeWindow *matched = nil;
        for (CascadeWindow *cur in remaining) {
            if ([cur.appName isEqualToString:sApp] && [cur.title isEqualToString:sTitle]) {
                matched = cur; break;
            }
        }
        if (!matched && sApp.length > 0) {
            for (CascadeWindow *cur in remaining) {
                if ([cur.appName isEqualToString:sApp]) { matched = cur; break; }
            }
        }
        if (matched) { [ordered addObject:matched]; [remaining removeObject:matched]; }
    }
    if (remaining.count > 0) [ordered addObjectsFromArray:remaining];
    return ordered;
}

+ (NSArray<NSDictionary<NSString *, NSString *> *> *)savedEstablishedWindowOrder { return getPref(@"establishedWindowOrder", @[]); }
+ (void)saveEstablishedWindowOrder:(NSArray<CascadeWindow *> *)windows { setPref(@"establishedWindowOrder", [self serializeWindows:windows]); }

+ (NSArray<NSString *> *)parseAppOrderString:(NSString *)string {
    if (!string || string.length == 0) return @[];
    NSMutableArray *result = [NSMutableArray array];
    for (NSString *p in [string componentsSeparatedByString:@","]) {
        NSString *trimmed = [p stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length > 0) [result addObject:trimmed];
    }
    return result;
}

static NSInteger rankForApp(NSString *appName, NSArray<NSString *> *preferred) {
    if (!appName || preferred.count == 0) return 999999;
    for (NSUInteger i = 0; i < preferred.count; i++) {
        if ([appName localizedCaseInsensitiveCompare:preferred[i]] == NSOrderedSame) return (NSInteger)i;
    }
    for (NSUInteger i = 0; i < preferred.count; i++) {
        if ([appName localizedCaseInsensitiveContainsString:preferred[i]] || [preferred[i] localizedCaseInsensitiveContainsString:appName]) return (NSInteger)i;
    }
    return 999999;
}

static NSArray<CascadeWindow *> *groupAndSortWindows(NSArray<CascadeWindow *> *windows,
                                                     CascadeOrderMode orderMode,
                                                     NSArray<NSString *> *preferredOrder,
                                                     CascadeLayoutStyle layoutStyle) {
    if (windows.count <= 1) return windows;

    NSMutableArray<CascadeAppGroup *> *groups = [NSMutableArray array];
    NSMutableDictionary<NSString *, CascadeAppGroup *> *groupMap = [NSMutableDictionary dictionary];

    for (NSUInteger i = 0; i < windows.count; i++) {
        CascadeWindow *w = windows[i];
        NSString *key = [w.appName lowercaseString] ?: @"";
        CascadeAppGroup *g = groupMap[key];
        if (!g) {
            g = [[CascadeAppGroup alloc] initWithAppName:w.appName firstIndex:i];
            g.preferredRank = rankForApp(w.appName, preferredOrder);
            groupMap[key] = g;
            [groups addObject:g];
        }
        [g.windows addObject:w];
        if (w.zRank < g.minZRank) g.minZRank = w.zRank;
        if (w.currentFrame.origin.x < g.minOriginX) g.minOriginX = w.currentFrame.origin.x;
    }

    // Sort windows internally within each app group
    for (CascadeAppGroup *g in groups) {
        if (orderMode == CascadeOrderModeSpatial && layoutStyle != CascadeLayoutStyleFractal) {
            [g.windows sortUsingComparator:^NSComparisonResult(CascadeWindow *a, CascadeWindow *b) {
                if (a.currentFrame.origin.x != b.currentFrame.origin.x) {
                    return a.currentFrame.origin.x < b.currentFrame.origin.x ? NSOrderedAscending : NSOrderedDescending;
                }
                if (a.zRank != b.zRank) return a.zRank < b.zRank ? NSOrderedAscending : NSOrderedDescending;
                return [a.title ?: @"" localizedCaseInsensitiveCompare:b.title ?: @""];
            }];
        } else if (orderMode == CascadeOrderModeAlphabetical && layoutStyle != CascadeLayoutStyleFractal) {
            [g.windows sortUsingComparator:^NSComparisonResult(CascadeWindow *a, CascadeWindow *b) {
                NSComparisonResult r = [a.title ?: @"" localizedCaseInsensitiveCompare:b.title ?: @""];
                if (r != NSOrderedSame) return r;
                return a.zRank < b.zRank ? NSOrderedAscending : NSOrderedDescending;
            }];
        } else {
            // MRU, Custom, and Fractal: order within app by zRank ascending (frontmost first)
            [g.windows sortUsingComparator:^NSComparisonResult(CascadeWindow *a, CascadeWindow *b) {
                if (a.zRank != b.zRank) return a.zRank < b.zRank ? NSOrderedAscending : NSOrderedDescending;
                return [a.title ?: @"" localizedCaseInsensitiveCompare:b.title ?: @""];
            }];
        }
    }

    // Sort the app groups by representative key
    if (layoutStyle == CascadeLayoutStyleFractal) {
        if (preferredOrder.count > 0) {
            [groups sortUsingComparator:^NSComparisonResult(CascadeAppGroup *a, CascadeAppGroup *b) {
                if (a.preferredRank != b.preferredRank) return a.preferredRank < b.preferredRank ? NSOrderedAscending : NSOrderedDescending;
                if (a.firstAppearanceIndex != b.firstAppearanceIndex) return a.firstAppearanceIndex < b.firstAppearanceIndex ? NSOrderedAscending : NSOrderedDescending;
                return [a.appName localizedCaseInsensitiveCompare:b.appName];
            }];
        } else {
            [groups sortUsingComparator:^NSComparisonResult(CascadeAppGroup *a, CascadeAppGroup *b) {
                if (a.firstAppearanceIndex != b.firstAppearanceIndex) return a.firstAppearanceIndex < b.firstAppearanceIndex ? NSOrderedAscending : NSOrderedDescending;
                return [a.appName localizedCaseInsensitiveCompare:b.appName];
            }];
        }
    } else if (orderMode == CascadeOrderModeMRU) {
        [groups sortUsingComparator:^NSComparisonResult(CascadeAppGroup *a, CascadeAppGroup *b) {
            if (a.minZRank != b.minZRank) return a.minZRank < b.minZRank ? NSOrderedAscending : NSOrderedDescending;
            return [a.appName localizedCaseInsensitiveCompare:b.appName];
        }];
    } else if (orderMode == CascadeOrderModeSpatial) {
        [groups sortUsingComparator:^NSComparisonResult(CascadeAppGroup *a, CascadeAppGroup *b) {
            if (a.minOriginX != b.minOriginX) return a.minOriginX < b.minOriginX ? NSOrderedAscending : NSOrderedDescending;
            if (a.minZRank != b.minZRank) return a.minZRank < b.minZRank ? NSOrderedAscending : NSOrderedDescending;
            return [a.appName localizedCaseInsensitiveCompare:b.appName];
        }];
    } else if (orderMode == CascadeOrderModeAlphabetical) {
        [groups sortUsingComparator:^NSComparisonResult(CascadeAppGroup *a, CascadeAppGroup *b) {
            return [a.appName localizedCaseInsensitiveCompare:b.appName];
        }];
    } else if (orderMode == CascadeOrderModeCustom) {
        [groups sortUsingComparator:^NSComparisonResult(CascadeAppGroup *a, CascadeAppGroup *b) {
            if (a.preferredRank != b.preferredRank) return a.preferredRank < b.preferredRank ? NSOrderedAscending : NSOrderedDescending;
            if (a.minZRank != b.minZRank) return a.minZRank < b.minZRank ? NSOrderedAscending : NSOrderedDescending;
            return [a.appName localizedCaseInsensitiveCompare:b.appName];
        }];
    }

    NSMutableArray<CascadeWindow *> *sorted = [NSMutableArray arrayWithCapacity:windows.count];
    for (CascadeAppGroup *g in groups) {
        [sorted addObjectsFromArray:g.windows];
    }
    return sorted;
}

+ (NSArray<CascadeWindow *> *)calculateLayoutForWindows:(NSArray<CascadeWindow *> *)windows orderMode:(CascadeOrderMode)orderMode delta:(CGFloat)delta {
    return [self calculateLayoutForWindows:windows orderMode:orderMode preferredOrder:[self preferredAppOrder] delta:delta];
}

+ (NSArray<CascadeWindow *> *)calculateLayoutForWindows:(NSArray<CascadeWindow *> *)windows
                                              orderMode:(CascadeOrderMode)orderMode
                                         preferredOrder:(NSArray<NSString *> *)preferredOrder
                                                  delta:(CGFloat)delta
                                            layoutStyle:(CascadeLayoutStyle)layoutStyle
                                          onUsableFrame:(CGRect)usableFrame {
    if (windows.count == 0) return @[];
    NSArray<CascadeWindow *> *sorted = groupAndSortWindows(windows, orderMode, preferredOrder, layoutStyle);

    if (layoutStyle == CascadeLayoutStyleFractal) {
        NSArray *participating = sorted.count > 4 ? [sorted subarrayWithRange:NSMakeRange(0, 4)] : sorted;
        [WindowLayoutGeometry assignFramesToOrderedWindows:participating onUsableFrame:usableFrame delta:delta layoutStyle:layoutStyle];
        for (NSUInteger i = 4; i < sorted.count; i++) {
            sorted[i].targetFrame = sorted[i].currentFrame;
        }
        return sorted;
    }

    [WindowLayoutGeometry assignFramesToOrderedWindows:sorted onUsableFrame:usableFrame delta:delta layoutStyle:layoutStyle];
    return sorted;
}

+ (NSArray<CascadeWindow *> *)calculateLayoutForWindows:(NSArray<CascadeWindow *> *)windows
                                              orderMode:(CascadeOrderMode)orderMode
                                         preferredOrder:(NSArray<NSString *> *)preferredOrder
                                                  delta:(CGFloat)delta
                                           onUsableFrame:(CGRect)usableFrame {
    return [self calculateLayoutForWindows:windows orderMode:orderMode preferredOrder:preferredOrder delta:delta layoutStyle:[self savedLayoutStyle] onUsableFrame:usableFrame];
}

+ (NSArray<CascadeWindow *> *)calculateLayoutForWindows:(NSArray<CascadeWindow *> *)windows orderMode:(CascadeOrderMode)orderMode preferredOrder:(NSArray<NSString *> *)preferredOrder delta:(CGFloat)delta {
    return [self calculateLayoutForWindows:windows orderMode:orderMode preferredOrder:preferredOrder delta:delta onUsableFrame:[self usableScreenFrameWithTopInset:nil]];
}

+ (void)assignFramesToOrderedWindows:(NSArray<CascadeWindow *> *)ordered onUsableFrame:(CGRect)usable delta:(CGFloat)delta {
    [WindowLayoutGeometry assignFramesToOrderedWindows:ordered onUsableFrame:usable delta:delta layoutStyle:[self savedLayoutStyle]];
}

+ (void)assignFramesToOrderedWindows:(NSArray<CascadeWindow *> *)ordered delta:(CGFloat)delta {
    [self assignFramesToOrderedWindows:ordered onUsableFrame:[self usableScreenFrameWithTopInset:nil] delta:delta];
}

+ (NSArray<CascadeWindow *> *)calculateLayoutForWindows:(NSArray<CascadeWindow *> *)windows
                                    preservingOrderFrom:(NSArray<CascadeWindow *> *)previousOrder
                                                  delta:(CGFloat)delta
                                            layoutStyle:(CascadeLayoutStyle)layoutStyle
                                          onUsableFrame:(CGRect)usableFrame {
    if (windows.count == 0) return @[];
    if (previousOrder.count == 0) {
        return [self calculateLayoutForWindows:windows orderMode:[self savedOrderMode] preferredOrder:[self preferredAppOrder] delta:delta layoutStyle:layoutStyle onUsableFrame:usableFrame];
    }
    NSMutableArray<CascadeWindow *> *remaining = [windows mutableCopy], *ordered = [NSMutableArray array];
    for (CascadeWindow *prev in previousOrder) {
        CascadeWindow *matched = nil;
        for (CascadeWindow *cur in remaining) {
            if ([cur matchesWindow:prev]) { matched = cur; break; }
        }
        if (matched) { [ordered addObject:matched]; [remaining removeObject:matched]; }
    }
    if (remaining.count > 0) {
        for (CascadeWindow *newWin in remaining) {
            NSString *appKey = [newWin.appName lowercaseString] ?: @"";
            NSInteger insertIdx = -1;
            for (NSInteger i = (NSInteger)ordered.count - 1; i >= 0; i--) {
                if ([[ordered[i].appName lowercaseString] isEqualToString:appKey]) {
                    insertIdx = i + 1;
                    break;
                }
            }
            if (insertIdx >= 0) {
                [ordered insertObject:newWin atIndex:(NSUInteger)insertIdx];
            } else {
                [ordered addObject:newWin];
            }
        }
    }

    // Ensure strict contiguous app grouping across preserved windows
    NSMutableArray<CascadeWindow *> *stabilized = [NSMutableArray arrayWithCapacity:ordered.count];
    NSMutableSet *handledApps = [NSMutableSet set];
    for (NSUInteger i = 0; i < ordered.count; i++) {
        NSString *appKey = [ordered[i].appName lowercaseString] ?: @"";
        if ([handledApps containsObject:appKey]) continue;
        [handledApps addObject:appKey];
        for (NSUInteger j = i; j < ordered.count; j++) {
            if ([[ordered[j].appName lowercaseString] isEqualToString:appKey]) {
                [stabilized addObject:ordered[j]];
            }
        }
    }
    ordered = stabilized;

    if (layoutStyle == CascadeLayoutStyleFractal) {
        NSArray *participating = ordered.count > 4 ? [ordered subarrayWithRange:NSMakeRange(0, 4)] : ordered;
        [WindowLayoutGeometry assignFramesToOrderedWindows:participating onUsableFrame:usableFrame delta:delta layoutStyle:layoutStyle];
        for (NSUInteger i = 4; i < ordered.count; i++) {
            ordered[i].targetFrame = ordered[i].currentFrame;
        }
    } else {
        [WindowLayoutGeometry assignFramesToOrderedWindows:ordered onUsableFrame:usableFrame delta:delta layoutStyle:layoutStyle];
    }
    return ordered;
}

+ (NSArray<CascadeWindow *> *)calculateLayoutForWindows:(NSArray<CascadeWindow *> *)windows preservingOrderFrom:(NSArray<CascadeWindow *> *)previousOrder delta:(CGFloat)delta onUsableFrame:(CGRect)usableFrame {
    return [self calculateLayoutForWindows:windows preservingOrderFrom:previousOrder delta:delta layoutStyle:[self savedLayoutStyle] onUsableFrame:usableFrame];
}

+ (NSArray<CascadeWindow *> *)calculateLayoutForWindows:(NSArray<CascadeWindow *> *)windows preservingOrderFrom:(NSArray<CascadeWindow *> *)previousOrder delta:(CGFloat)delta {
    return [self calculateLayoutForWindows:windows preservingOrderFrom:previousOrder delta:delta onUsableFrame:[self usableScreenFrameWithTopInset:nil]];
}

+ (CGRect)clampedFrameForTargetFrame:(CGRect)targetFrame
                          actualSize:(CGSize)actualSize
                         usableFrame:(CGRect)usableFrame {
    if (CGRectIsEmpty(usableFrame)) usableFrame = [self usableScreenFrameWithTopInset:nil];
    CGFloat minX = usableFrame.origin.x, maxX = usableFrame.origin.x + usableFrame.size.width;
    CGFloat minY = usableFrame.origin.y, maxY = usableFrame.origin.y + usableFrame.size.height;
    CGFloat w = actualSize.width > 0 ? actualSize.width : targetFrame.size.width;
    CGFloat h = actualSize.height > 0 ? actualSize.height : targetFrame.size.height;
    CGFloat x = targetFrame.origin.x, y = targetFrame.origin.y;

    if (w >= usableFrame.size.width) { x = minX; }
    else { if (x + w > maxX) x = maxX - w; if (x < minX) x = minX; }

    if (h >= usableFrame.size.height) { y = minY; }
    else { if (y + h > maxY) y = maxY - h; if (y < minY) y = minY; }

    return CGRectMake(x, y, w, h);
}

+ (void)applyLayoutToWindows:(NSArray<CascadeWindow *> *)windows restackZ:(BOOL)restackZ {
    for (CascadeWindow *cw in windows) {
        if (!cw.axRef) continue;
        CGRect t = cw.targetFrame, cur = cw.currentFrame;
        CGRect usable = !CGRectIsEmpty(cw.usableFrame) ? cw.usableFrame : [self usableScreenFrameWithTopInset:nil];

        BOOL posDiff = fabs(cur.origin.x - t.origin.x) > 1.0 || fabs(cur.origin.y - t.origin.y) > 1.0;
        if (posDiff) {
            CGPoint p = t.origin; AXValueRef pv = AXValueCreate(kAXValueTypeCGPoint, &p);
            if (pv) { AXUIElementSetAttributeValue(cw.axRef, kAXPositionAttribute, pv); CFRelease(pv); }
        }

        BOOL szDiff = fabs(cur.size.width - t.size.width) > 1.0 || fabs(cur.size.height - t.size.height) > 1.0;
        if (szDiff) {
            CGSize s = t.size; AXValueRef sv = AXValueCreate(kAXValueTypeCGSize, &s);
            if (sv) { AXUIElementSetAttributeValue(cw.axRef, kAXSizeAttribute, sv); CFRelease(sv); }
        }

        CGSize actSize = t.size;
        CFTypeRef actRef = NULL;
        if (AXUIElementCopyAttributeValue(cw.axRef, kAXSizeAttribute, &actRef) == kAXErrorSuccess && actRef) {
            if (CFGetTypeID(actRef) == AXValueGetTypeID()) {
                CGSize readSz = CGSizeZero; AXValueGetValue((AXValueRef)actRef, kAXValueTypeCGSize, &readSz);
                if ((readSz.width > t.size.width + 1.0 || readSz.height > t.size.height + 1.0) &&
                    (readSz.width < usable.size.width || readSz.height < usable.size.height)) {
                    actSize = readSz;
                }
            }
            CFRelease(actRef);
        }

        CGRect finalFrame = [self clampedFrameForTargetFrame:t actualSize:actSize usableFrame:usable];
        CGPoint fp = finalFrame.origin;
        if (fabs(cur.origin.x - fp.x) > 1.0 || fabs(cur.origin.y - fp.y) > 1.0 || posDiff) {
            AXValueRef fpv = AXValueCreate(kAXValueTypeCGPoint, &fp);
            if (fpv) { AXUIElementSetAttributeValue(cw.axRef, kAXPositionAttribute, fpv); CFRelease(fpv); }
        }
        cw.targetFrame = finalFrame;
        cw.currentFrame = finalFrame;
    }
    if (restackZ) {
        for (NSInteger i = (NSInteger)windows.count - 1; i >= 0; i--) {
            if (windows[i].axRef) AXUIElementPerformAction(windows[i].axRef, kAXRaiseAction);
        }
    }
}

+ (CascadeDockEdge)parseDockEdgeString:(NSString *)string {
    NSString *s = [string lowercaseString];
    if ([s containsString:@"right"]) return CascadeDockEdgeRight;
    if ([s containsString:@"top"]) return CascadeDockEdgeTop;
    if ([s containsString:@"bottom"]) return CascadeDockEdgeBottom;
    return CascadeDockEdgeLeft;
}

+ (CascadeLayoutStyle)parseLayoutStyleString:(NSString *)string {
    NSString *l = [string lowercaseString];
    if ([l containsString:@"fractal"] || [l containsString:@"golden"] || [l containsString:@"spiral"]) return CascadeLayoutStyleFractal;
    if ([l containsString:@"quad"] || [l containsString:@"edge"] || [l containsString:@"perimeter"]) return CascadeLayoutStyleQuadEdge;
    return CascadeLayoutStyleDiagonal;
}

+ (NSString *)nameForLayoutStyle:(CascadeLayoutStyle)style {
    switch (style) {
        case CascadeLayoutStyleFractal: return @"Fractal (Golden Ratio)";
        case CascadeLayoutStyleQuadEdge: return @"Quad-Edge (Clockwise Perimeter)";
        case CascadeLayoutStyleDiagonal:
        default: return @"Diagonal Cascade";
    }
}

+ (CascadeWindow *)frontmostStandardWindow {
    NSRunningApplication *frontApp = [[NSWorkspace sharedWorkspace] frontmostApplication];
    if (!frontApp) return nil;
    pid_t pid = frontApp.processIdentifier;
    AXUIElementRef appRef = AXUIElementCreateApplication(pid);
    if (!appRef) return nil;

    CascadeWindow *cw = nil;
    CFTypeRef winRef = NULL;
    if (AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute, &winRef) == kAXErrorSuccess && winRef) {
        CFTypeRef posRef = NULL, szRef = NULL, titleRef = NULL;
        AXUIElementCopyAttributeValue((AXUIElementRef)winRef, kAXPositionAttribute, &posRef);
        AXUIElementCopyAttributeValue((AXUIElementRef)winRef, kAXSizeAttribute, &szRef);
        AXUIElementCopyAttributeValue((AXUIElementRef)winRef, kAXTitleAttribute, &titleRef);
        CGPoint curPos = CGPointZero; CGSize curSize = CGSizeZero;
        if (posRef) { AXValueGetValue((AXValueRef)posRef, kAXValueTypeCGPoint, &curPos); CFRelease(posRef); }
        if (szRef) { AXValueGetValue((AXValueRef)szRef, kAXValueTypeCGSize, &curSize); CFRelease(szRef); }
        NSString *title = titleRef ? (NSString *)CFBridgingRelease(titleRef) : @"";

        cw = [[CascadeWindow alloc] init];
        cw.appName = frontApp.localizedName ?: @"";
        cw.title = title;
        cw.pid = pid;
        cw.axRef = (AXUIElementRef)winRef;
        cw.currentFrame = CGRectMake(curPos.x, curPos.y, curSize.width, curSize.height);
        cw.zRank = 0;
    }
    CFRelease(appRef);

    if (!cw) {
        NSArray<CascadeWindow *> *all = [self collectStandardWindowsWithOnly:nil exclude:[self ignoredApps]];
        return all.firstObject;
    }
    return cw;
}

+ (BOOL)toggleZoomActiveWindow {
    if (![self isAccessibilityTrustedWithPrompt:YES]) return NO;

    CascadeWindow *cw = [self frontmostStandardWindow];
    if (!cw || !cw.axRef) return NO;

    NSDictionary *saved = [[self userDefaults] dictionaryForKey:@"activeZoomState"];
    CGRect currentFrame = cw.currentFrame;

    if (saved) {
        pid_t savedPid = [saved[@"pid"] intValue];
        NSString *savedTitle = saved[@"title"] ?: @"";
        CGFloat origX = [saved[@"x"] doubleValue];
        CGFloat origY = [saved[@"y"] doubleValue];
        CGFloat origW = [saved[@"w"] doubleValue];
        CGFloat origH = [saved[@"h"] doubleValue];

        if (savedPid == cw.pid && (savedTitle.length == 0 || [savedTitle isEqualToString:cw.title])) {
            CGRect origFrame = CGRectMake(origX, origY, origW, origH);
            cw.targetFrame = origFrame;
            cw.usableFrame = [self usableScreenFrameWithTopInset:nil];
            [self applyLayoutToWindows:@[cw] restackZ:NO];
            [[self userDefaults] removeObjectForKey:@"activeZoomState"];
            [[self userDefaults] synchronize];
            return YES;
        }
    }

    CascadeScreen *screen = [ScreenManager screenForFrame:currentFrame];
    CGRect screenFrame = screen ? screen.quartzVisibleFrame : [self usableScreenFrameWithTopInset:nil];

    NSDictionary *state = @{
        @"pid": @(cw.pid),
        @"title": cw.title ?: @"",
        @"x": @(currentFrame.origin.x),
        @"y": @(currentFrame.origin.y),
        @"w": @(currentFrame.size.width),
        @"h": @(currentFrame.size.height)
    };
    [[self userDefaults] setObject:state forKey:@"activeZoomState"];
    [[self userDefaults] synchronize];

    cw.targetFrame = screenFrame;
    cw.usableFrame = screenFrame;
    [self applyLayoutToWindows:@[cw] restackZ:YES];
    return YES;
}

+ (BOOL)dockActiveWindowWithEdge:(CascadeDockEdge)edge layoutStyle:(CascadeLayoutStyle)style delta:(CGFloat)delta {
    (void)style;
    (void)delta;
    if (![self isAccessibilityTrustedWithPrompt:YES]) return NO;

    CascadeWindow *activeWin = [self frontmostStandardWindow];
    if (!activeWin || !activeWin.axRef) return NO;

    CascadeScreen *screen = [ScreenManager screenForFrame:activeWin.currentFrame];
    CGRect usable = screen ? screen.quartzVisibleFrame : [self usableScreenFrameWithTopInset:nil];

    CGRect docked = [WindowLayoutGeometry dockedFrameForEdge:edge onUsableFrame:usable];
    activeWin.targetFrame = docked;
    activeWin.usableFrame = usable;

    [self applyLayoutToWindows:@[activeWin] restackZ:YES];
    return YES;
}

@end
