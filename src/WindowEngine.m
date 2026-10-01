#import "WindowEngine.h"

@implementation CascadeWindow
- (void)dealloc {
    if (_axRef) CFRelease(_axRef);
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

+ (NSArray<CascadeWindow *> *)calculateLayoutForWindows:(NSArray<CascadeWindow *> *)windows
                                              orderMode:(CascadeOrderMode)orderMode
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
    }

    CGFloat topInset = 0;
    CGRect usable = [self usableScreenFrameWithTopInset:&topInset];
    CGFloat usableW = usable.size.width;
    CGFloat usableH = usable.size.height;
    CGFloat originX = usable.origin.x;
    CGFloat originY = usable.origin.y;

    if (count == 1) {
        sorted[0].targetFrame = usable;
    } else if (count == 2) {
        // Optimal opposing edge layout: 98% screen area each
        sorted[0].targetFrame = CGRectMake(originX, originY, usableW - delta, usableH);
        sorted[1].targetFrame = CGRectMake(originX + delta, originY, usableW - delta, usableH);
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
            sorted[i].targetFrame = CGRectMake(originX + i * delta, originY + i * delta, targetW, targetH);
        }
    }

    return sorted;
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
