#import "WindowEngine.h"
#import "ScreenManager.h"

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
        if (self.title.length > 0 && other.title.length > 0) return [self.title isEqualToString:other.title];
        return YES;
    }
    return NO;
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
    NSRunningApplication *parent = [[NSWorkspace sharedWorkspace] frontmostApplication];
    NSString *parentApp = parent.localizedName ?: @"Unknown";
    return @{ @"apiTrusted": @(apiTrusted), @"functional": @(functional),
              @"errorCode": @(errorCode), @"trusted": @(apiTrusted && functional),
              @"hostApp": parentApp };
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
        if (!pidToZRank[pid]) {
            pidToZRank[pid] = @(zRank++);
        }
    }

    NSMutableArray<CascadeWindow *> *result = [NSMutableArray array];
    NSArray<NSRunningApplication *> *apps = [[NSWorkspace sharedWorkspace] runningApplications];

    for (NSRunningApplication *app in apps) {
        if (app.activationPolicy != NSApplicationActivationPolicyRegular) continue;
        NSString *appName = app.localizedName ?: @"";

        if (onlyApps) {
            BOOL match = NO;
            for (NSString *allowed in onlyApps) {
                if ([appName localizedCaseInsensitiveContainsString:allowed]) { match = YES; break; }
            }
            if (!match) continue;
        }
        if (excludeApps) {
            BOOL excluded = NO;
            for (NSString *ex in excludeApps) {
                if ([appName localizedCaseInsensitiveContainsString:ex]) { excluded = YES; break; }
            }
            if (excluded) continue;
        }

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

                CGPoint curPos = CGPointZero;
                CGSize curSize = CGSizeZero;
                if (posRef) AXValueGetValue((AXValueRef)posRef, kAXValueTypeCGPoint, &curPos);
                if (szRef) AXValueGetValue((AXValueRef)szRef, kAXValueTypeCGSize, &curSize);
                if (posRef) CFRelease(posRef);
                if (szRef) CFRelease(szRef);

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
+ (CGFloat)savedDelta { NSNumber *n = getPref(@"delta", nil); return n ? (CGFloat)[n doubleValue] : 40.0; }
+ (void)saveDelta:(CGFloat)d { setPref(@"delta", @(d)); }
+ (BOOL)savedRestackZOrder { NSNumber *n = getPref(@"restackZOrder", nil); return n ? [n boolValue] : YES; }
+ (void)saveRestackZOrder:(BOOL)r { setPref(@"restackZOrder", @(r)); }
+ (BOOL)savedAutoRearrange { NSNumber *n = getPref(@"autoRearrange", nil); return n ? [n boolValue] : NO; }
+ (void)saveAutoRearrange:(BOOL)a { setPref(@"autoRearrange", @(a)); }
+ (NSArray<NSString *> *)preferredAppOrder { return getPref(@"preferredAppOrder", @[]); }
+ (void)setPreferredAppOrder:(NSArray<NSString *> *)o { setPref(@"preferredAppOrder", o ?: @[]); }

+ (NSArray<NSDictionary<NSString *, NSString *> *> *)serializeWindows:(NSArray<CascadeWindow *> *)windows {
    NSMutableArray *arr = [NSMutableArray arrayWithCapacity:windows.count];
    for (CascadeWindow *w in windows) {
        [arr addObject:@{@"appName": w.appName ?: @"", @"title": w.title ?: @""}];
    }
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
        if ([appName localizedCaseInsensitiveContainsString:preferred[i]]) return (NSInteger)i;
    }
    return 999999;
}

+ (NSArray<CascadeWindow *> *)calculateLayoutForWindows:(NSArray<CascadeWindow *> *)windows
                                              orderMode:(CascadeOrderMode)orderMode
                                                  delta:(CGFloat)delta {
    return [self calculateLayoutForWindows:windows
                                 orderMode:orderMode
                            preferredOrder:[self preferredAppOrder]
                                     delta:delta];
}

+ (NSArray<CascadeWindow *> *)calculateLayoutForWindows:(NSArray<CascadeWindow *> *)windows
                                              orderMode:(CascadeOrderMode)orderMode
                                         preferredOrder:(NSArray<NSString *> *)preferredOrder
                                                  delta:(CGFloat)delta
                                          onUsableFrame:(CGRect)usableFrame {
    if (windows.count == 0) return @[];
    NSMutableArray<CascadeWindow *> *sorted = [windows mutableCopy];
    if (orderMode == CascadeOrderModeMRU) {
        [sorted sortUsingComparator:^NSComparisonResult(CascadeWindow *a, CascadeWindow *b) {
            return (a.zRank != b.zRank) ? (a.zRank < b.zRank ? NSOrderedAscending : NSOrderedDescending) :
                   [a.title ?: @"" localizedCaseInsensitiveCompare:b.title ?: @""];
        }];
    } else if (orderMode == CascadeOrderModeSpatial) {
        [sorted sortUsingComparator:^NSComparisonResult(CascadeWindow *a, CascadeWindow *b) {
            return (a.currentFrame.origin.x != b.currentFrame.origin.x) ?
                   (a.currentFrame.origin.x < b.currentFrame.origin.x ? NSOrderedAscending : NSOrderedDescending) :
                   [a.title ?: @"" localizedCaseInsensitiveCompare:b.title ?: @""];
        }];
    } else if (orderMode == CascadeOrderModeAlphabetical) {
        [sorted sortUsingComparator:^NSComparisonResult(CascadeWindow *a, CascadeWindow *b) {
            NSComparisonResult r = [a.appName ?: @"" localizedCaseInsensitiveCompare:b.appName ?: @""];
            return (r != NSOrderedSame) ? r : [a.title ?: @"" localizedCaseInsensitiveCompare:b.title ?: @""];
        }];
    } else if (orderMode == CascadeOrderModeCustom) {
        [sorted sortUsingComparator:^NSComparisonResult(CascadeWindow *a, CascadeWindow *b) {
            NSInteger rA = rankForApp(a.appName, preferredOrder), rB = rankForApp(b.appName, preferredOrder);
            if (rA != rB) return rA < rB ? NSOrderedAscending : NSOrderedDescending;
            return (a.zRank != b.zRank) ? (a.zRank < b.zRank ? NSOrderedAscending : NSOrderedDescending) :
                   [a.title ?: @"" localizedCaseInsensitiveCompare:b.title ?: @""];
        }];
    }
    [self assignFramesToOrderedWindows:sorted onUsableFrame:usableFrame delta:delta];
    return sorted;
}

+ (NSArray<CascadeWindow *> *)calculateLayoutForWindows:(NSArray<CascadeWindow *> *)windows
                                              orderMode:(CascadeOrderMode)orderMode
                                         preferredOrder:(NSArray<NSString *> *)preferredOrder
                                                  delta:(CGFloat)delta {
    return [self calculateLayoutForWindows:windows orderMode:orderMode preferredOrder:preferredOrder delta:delta onUsableFrame:[self usableScreenFrameWithTopInset:nil]];
}

+ (void)assignFramesToOrderedWindows:(NSArray<CascadeWindow *> *)ordered
                       onUsableFrame:(CGRect)usable
                               delta:(CGFloat)delta {
    NSUInteger count = ordered.count;
    if (count == 0) return;
    for (CascadeWindow *w in ordered) { w.usableFrame = usable; }
    CGFloat usableW = usable.size.width, usableH = usable.size.height;
    CGFloat originX = usable.origin.x, originY = usable.origin.y;

    if (count == 1) {
        ordered[0].targetFrame = usable;
    } else if (count == 2) {
        ordered[0].targetFrame = CGRectMake(originX, originY, usableW - delta, usableH);
        ordered[1].targetFrame = CGRectMake(originX + delta, originY, usableW - delta, usableH);
    } else {
        CGFloat totalOffsetX = (count - 1) * delta, totalOffsetY = (count - 1) * delta;
        if (usableW - totalOffsetX < 400 || usableH - totalOffsetY < 300) {
            delta = MIN((usableW - 400) / (count - 1), (usableH - 300) / (count - 1));
            totalOffsetX = (count - 1) * delta; totalOffsetY = (count - 1) * delta;
        }
        CGFloat targetW = usableW - totalOffsetX, targetH = usableH - totalOffsetY;
        for (NSUInteger i = 0; i < count; i++) {
            ordered[i].targetFrame = CGRectMake(originX + i * delta, originY + i * delta, targetW, targetH);
        }
    }
}

+ (void)assignFramesToOrderedWindows:(NSArray<CascadeWindow *> *)ordered delta:(CGFloat)delta {
    [self assignFramesToOrderedWindows:ordered onUsableFrame:[self usableScreenFrameWithTopInset:nil] delta:delta];
}

+ (NSArray<CascadeWindow *> *)calculateLayoutForWindows:(NSArray<CascadeWindow *> *)windows
                                    preservingOrderFrom:(NSArray<CascadeWindow *> *)previousOrder
                                                  delta:(CGFloat)delta
                                          onUsableFrame:(CGRect)usableFrame {
    if (windows.count == 0) return @[];
    if (previousOrder.count == 0) {
        return [self calculateLayoutForWindows:windows orderMode:CascadeOrderModeMRU preferredOrder:[self preferredAppOrder] delta:delta onUsableFrame:usableFrame];
    }
    NSMutableArray<CascadeWindow *> *remaining = [windows mutableCopy], *ordered = [NSMutableArray array];
    for (CascadeWindow *prev in previousOrder) {
        CascadeWindow *matched = nil;
        for (CascadeWindow *cur in remaining) {
            if ([cur matchesWindow:prev]) { matched = cur; break; }
        }
        if (matched) { [ordered addObject:matched]; [remaining removeObject:matched]; }
    }
    if (remaining.count > 0) [ordered addObjectsFromArray:remaining];
    [self assignFramesToOrderedWindows:ordered onUsableFrame:usableFrame delta:delta];
    return ordered;
}

+ (NSArray<CascadeWindow *> *)calculateLayoutForWindows:(NSArray<CascadeWindow *> *)windows
                                    preservingOrderFrom:(NSArray<CascadeWindow *> *)previousOrder
                                                  delta:(CGFloat)delta {
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
        CGSize targetSize = cw.targetFrame.size;
        BOOL szChanged = fabs(cw.currentFrame.size.width - targetSize.width) > 1.0 || fabs(cw.currentFrame.size.height - targetSize.height) > 1.0;
        if (szChanged) {
            AXValueRef szVal = AXValueCreate(kAXValueTypeCGSize, &targetSize);
            if (szVal) { AXUIElementSetAttributeValue(cw.axRef, kAXSizeAttribute, szVal); CFRelease(szVal); }
        }

        CGSize actualSize = targetSize;
        CFTypeRef actualSzRef = NULL;
        if (AXUIElementCopyAttributeValue(cw.axRef, kAXSizeAttribute, &actualSzRef) == kAXErrorSuccess && actualSzRef) {
            AXValueGetValue((AXValueRef)actualSzRef, kAXValueTypeCGSize, &actualSize);
            CFRelease(actualSzRef);
        }

        CGRect usable = !CGRectIsEmpty(cw.usableFrame) ? cw.usableFrame : [self usableScreenFrameWithTopInset:nil];
        CGRect finalFrame = [self clampedFrameForTargetFrame:cw.targetFrame actualSize:actualSize usableFrame:usable];
        CGPoint finalPos = finalFrame.origin;
        BOOL posChanged = fabs(cw.currentFrame.origin.x - finalPos.x) > 1.0 || fabs(cw.currentFrame.origin.y - finalPos.y) > 1.0;
        if (posChanged) {
            AXValueRef posVal = AXValueCreate(kAXValueTypeCGPoint, &finalPos);
            if (posVal) { AXUIElementSetAttributeValue(cw.axRef, kAXPositionAttribute, posVal); CFRelease(posVal); }
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

@end
