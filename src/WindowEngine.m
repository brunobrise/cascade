#import "WindowEngine.h"

@implementation CascadeWindow
- (void)dealloc {
    if (_axRef) CFRelease(_axRef);
}

- (BOOL)matchesWindow:(CascadeWindow *)other {
    if (!other) return NO;
    if (self.axRef && other.axRef && CFEqual(self.axRef, other.axRef)) {
        return YES;
    }
    if (self.pid == other.pid && self.pid != 0) {
        if (self.title.length > 0 && other.title.length > 0) {
            return [self.title isEqualToString:other.title];
        }
        if ([self.appName isEqualToString:other.appName]) {
            return YES;
        }
    }
    if (self.appName.length > 0 && other.appName.length > 0 && [self.appName isEqualToString:other.appName]) {
        if (self.title.length > 0 && other.title.length > 0) {
            return [self.title isEqualToString:other.title];
        }
        return YES;
    }
    return NO;
}
@end

@implementation CascadeEngine

+ (CGRect)usableScreenFrameWithTopInset:(CGFloat *)outTopInset {
    NSScreen *screen = [NSScreen mainScreen];
    NSRect screenFrame = [screen frame];
    NSRect visibleFrame = [screen visibleFrame];

    CGFloat topInset = screenFrame.size.height - (visibleFrame.origin.y + visibleFrame.size.height);
    if (outTopInset) *outTopInset = topInset;

    return CGRectMake(visibleFrame.origin.x, topInset, visibleFrame.size.width, visibleFrame.size.height);
}

+ (BOOL)isAccessibilityTrustedWithPrompt:(BOOL)prompt {
    if (prompt) {
        NSDictionary *options = @{(__bridge id)kAXTrustedCheckOptionPrompt: @YES};
        return AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
    }
    return AXIsProcessTrusted();
}

+ (void)openAccessibilitySettings {
    NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"];
    [[NSWorkspace sharedWorkspace] openURL:url];
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
                if ([appName localizedCaseInsensitiveContainsString:allowed]) {
                    match = YES; break;
                }
            }
            if (!match) continue;
        }

        if (excludeApps) {
            BOOL excluded = NO;
            for (NSString *ex in excludeApps) {
                if ([appName localizedCaseInsensitiveContainsString:ex]) {
                    excluded = YES; break;
                }
            }
            if (excluded) continue;
        }

        pid_t pid = app.processIdentifier;
        AXUIElementRef appRef = AXUIElementCreateApplication(pid);
        if (!appRef) continue;

        CFTypeRef winsRef = NULL;
        if (AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute, &winsRef) == kAXErrorSuccess && winsRef) {
            NSArray *appWins = (NSArray *)CFBridgingRelease(winsRef);
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
                    cw.zRank = [pidToZRank[@(pid)] integerValue] ?: 999;
                    [result addObject:cw];
                }
            }
        }
        CFRelease(appRef);
    }

    return result;
}

+ (NSArray<NSString *> *)preferredAppOrder {
    NSArray *order = [[NSUserDefaults standardUserDefaults] stringArrayForKey:@"preferredAppOrder"];
    return order ?: @[];
}

+ (void)setPreferredAppOrder:(NSArray<NSString *> *)order {
    [[NSUserDefaults standardUserDefaults] setObject:(order ?: @[]) forKey:@"preferredAppOrder"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (NSArray<NSString *> *)parseAppOrderString:(NSString *)string {
    if (!string || string.length == 0) return @[];
    NSArray *parts = [string componentsSeparatedByString:@","];
    NSMutableArray *result = [NSMutableArray array];
    for (NSString *p in parts) {
        NSString *trimmed = [p stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length > 0) {
            [result addObject:trimmed];
        }
    }
    return result;
}

static NSInteger rankForApp(NSString *appName, NSArray<NSString *> *preferred) {
    if (!appName || preferred.count == 0) return 999999;
    for (NSUInteger i = 0; i < preferred.count; i++) {
        if ([appName localizedCaseInsensitiveCompare:preferred[i]] == NSOrderedSame) {
            return (NSInteger)i;
        }
    }
    for (NSUInteger i = 0; i < preferred.count; i++) {
        if ([appName localizedCaseInsensitiveContainsString:preferred[i]]) {
            return (NSInteger)i;
        }
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
                                                  delta:(CGFloat)delta {
    NSUInteger count = windows.count;
    if (count == 0) return @[];

    NSMutableArray<CascadeWindow *> *sorted = [windows mutableCopy];
    if (orderMode == CascadeOrderModeMRU) {
        [sorted sortUsingComparator:^NSComparisonResult(CascadeWindow *a, CascadeWindow *b) {
            if (a.zRank < b.zRank) return NSOrderedAscending;
            if (a.zRank > b.zRank) return NSOrderedDescending;
            return NSOrderedSame;
        }];
    } else if (orderMode == CascadeOrderModeSpatial) {
        [sorted sortUsingComparator:^NSComparisonResult(CascadeWindow *a, CascadeWindow *b) {
            if (a.currentFrame.origin.x < b.currentFrame.origin.x) return NSOrderedAscending;
            if (a.currentFrame.origin.x > b.currentFrame.origin.x) return NSOrderedDescending;
            return NSOrderedSame;
        }];
    } else if (orderMode == CascadeOrderModeAlphabetical) {
        [sorted sortUsingComparator:^NSComparisonResult(CascadeWindow *a, CascadeWindow *b) {
            return [a.appName localizedCaseInsensitiveCompare:b.appName];
        }];
    } else if (orderMode == CascadeOrderModeCustom) {
        [sorted sortUsingComparator:^NSComparisonResult(CascadeWindow *a, CascadeWindow *b) {
            NSInteger rankA = rankForApp(a.appName, preferredOrder);
            NSInteger rankB = rankForApp(b.appName, preferredOrder);
            if (rankA < rankB) return NSOrderedAscending;
            if (rankA > rankB) return NSOrderedDescending;
            if (a.zRank < b.zRank) return NSOrderedAscending;
            if (a.zRank > b.zRank) return NSOrderedDescending;
            return [a.appName localizedCaseInsensitiveCompare:b.appName];
        }];
    }

    [self assignFramesToOrderedWindows:sorted delta:delta];
    return sorted;
}

+ (void)assignFramesToOrderedWindows:(NSArray<CascadeWindow *> *)ordered delta:(CGFloat)delta {
    NSUInteger count = ordered.count;
    if (count == 0) return;

    CGFloat topInset = 0;
    CGRect usable = [self usableScreenFrameWithTopInset:&topInset];
    CGFloat usableW = usable.size.width;
    CGFloat usableH = usable.size.height;
    CGFloat originX = usable.origin.x;
    CGFloat originY = usable.origin.y;

    if (count == 1) {
        ordered[0].targetFrame = usable;
    } else if (count == 2) {
        // Optimal opposing edge layout: 98% screen area each
        ordered[0].targetFrame = CGRectMake(originX, originY, usableW - delta, usableH);
        ordered[1].targetFrame = CGRectMake(originX + delta, originY, usableW - delta, usableH);
    } else {
        // Invariant staggered cascade
        CGFloat totalOffsetX = (count - 1) * delta;
        CGFloat totalOffsetY = (count - 1) * delta;

        if (usableW - totalOffsetX < 400 || usableH - totalOffsetY < 300) {
            delta = MIN((usableW - 400) / (count - 1), (usableH - 300) / (count - 1));
            totalOffsetX = (count - 1) * delta;
            totalOffsetY = (count - 1) * delta;
        }

        CGFloat targetW = usableW - totalOffsetX;
        CGFloat targetH = usableH - totalOffsetY;

        for (NSUInteger i = 0; i < count; i++) {
            ordered[i].targetFrame = CGRectMake(originX + i * delta, originY + i * delta, targetW, targetH);
        }
    }
}

+ (NSArray<CascadeWindow *> *)calculateLayoutForWindows:(NSArray<CascadeWindow *> *)windows
                                    preservingOrderFrom:(NSArray<CascadeWindow *> *)previousOrder
                                                  delta:(CGFloat)delta {
    if (windows.count == 0) return @[];
    if (previousOrder.count == 0) {
        return [self calculateLayoutForWindows:windows orderMode:CascadeOrderModeMRU delta:delta];
    }

    NSMutableArray<CascadeWindow *> *remaining = [windows mutableCopy];
    NSMutableArray<CascadeWindow *> *ordered = [NSMutableArray array];

    // 1. Maintain established sequence for windows already present in previousOrder
    for (CascadeWindow *prev in previousOrder) {
        CascadeWindow *matched = nil;
        for (CascadeWindow *cur in remaining) {
            if ([cur matchesWindow:prev]) {
                matched = cur;
                break;
            }
        }
        if (matched) {
            [ordered addObject:matched];
            [remaining removeObject:matched];
        }
    }

    // 2. Append any newly opened windows at the end so existing window positions/order are untouched
    if (remaining.count > 0) {
        [ordered addObjectsFromArray:remaining];
    }

    // 3. Recalculate target sizes and slot coordinates strictly based on the preserved sequence
    [self assignFramesToOrderedWindows:ordered delta:delta];
    return ordered;
}

+ (void)applyLayoutToWindows:(NSArray<CascadeWindow *> *)windows
                    restackZ:(BOOL)restackZ {
    for (CascadeWindow *cw in windows) {
        CGRect tf = cw.targetFrame;
        CGPoint targetPos = CGPointMake(tf.origin.x, tf.origin.y);
        CGSize targetSize = CGSizeMake(tf.size.width, tf.size.height);

        AXValueRef posVal = AXValueCreate(kAXValueTypeCGPoint, &targetPos);
        AXValueRef sizeVal = AXValueCreate(kAXValueTypeCGSize, &targetSize);

        AXUIElementSetAttributeValue(cw.axRef, kAXPositionAttribute, posVal);
        AXUIElementSetAttributeValue(cw.axRef, kAXSizeAttribute, sizeVal);
        AXUIElementSetAttributeValue(cw.axRef, kAXPositionAttribute, posVal);

        if (posVal) CFRelease(posVal);
        if (sizeVal) CFRelease(sizeVal);
    }

    if (restackZ) {
        for (NSInteger i = (NSInteger)windows.count - 1; i >= 0; i--) {
            AXUIElementPerformAction(windows[i].axRef, kAXRaiseAction);
        }
    }
}

@end
