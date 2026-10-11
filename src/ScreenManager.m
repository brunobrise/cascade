#import "ScreenManager.h"
#import "WindowEngine.h"

static NSString * const kScreenDomain = @"com.brunobrise.cascade";
static NSString * const kScreenTargetKey = @"screenTarget";

@implementation CascadeScreen
- (NSString *)uniqueID {
    if (self.screenUUID.length > 0) return self.screenUUID;
    if (self.displayID.length > 0) return self.displayID;
    return self.name ?: [NSString stringWithFormat:@"screen_%ld", (long)self.index];
}

- (BOOL)isEqual:(id)object {
    if (self == object) return YES;
    if (![object isKindOfClass:[CascadeScreen class]]) return NO;
    CascadeScreen *other = (CascadeScreen *)object;
    if (self.screenUUID.length > 0 && other.screenUUID.length > 0) {
        return [self.screenUUID isEqualToString:other.screenUUID];
    }
    if (self.displayID.length > 0 || other.displayID.length > 0) {
        return [self.displayID isEqualToString:other.displayID];
    }
    return self.index == other.index;
}

- (NSUInteger)hash {
    if (self.screenUUID.length > 0) return [self.screenUUID hash];
    return self.displayID.length > 0 ? [self.displayID hash] : (NSUInteger)self.index;
}

- (id)copyWithZone:(NSZone *)zone {
    (void)zone;
    return self;
}
@end

@implementation ScreenManager

+ (CGRect)convertCocoaFrameToQuartz:(CGRect)cocoaFrame primaryScreenHeight:(CGFloat)h0 {
    return CGRectMake(cocoaFrame.origin.x,
                      h0 - (cocoaFrame.origin.y + cocoaFrame.size.height),
                      cocoaFrame.size.width,
                      cocoaFrame.size.height);
}

+ (NSArray<CascadeScreen *> *)availableScreens {
    NSArray<NSScreen *> *screens = [NSScreen screens];
    if (screens.count == 0) return @[];

    CGFloat h0 = screens[0].frame.size.height;
    NSMutableArray<CascadeScreen *> *result = [NSMutableArray arrayWithCapacity:screens.count];

    for (NSUInteger i = 0; i < screens.count; i++) {
        NSScreen *s = screens[i];
        CascadeScreen *cs = [[CascadeScreen alloc] init];
        cs.index = (NSInteger)i;
        cs.name = s.localizedName ?: [NSString stringWithFormat:@"Display %lu", (unsigned long)i];
        NSNumber *dNum = s.deviceDescription[@"NSScreenNumber"];
        cs.displayID = dNum ? [dNum stringValue] : @"";
        if (dNum) {
            CFUUIDRef uRef = CGDisplayCreateUUIDFromDisplayID((CGDirectDisplayID)[dNum unsignedIntValue]);
            if (uRef) {
                CFStringRef sRef = CFUUIDCreateString(kCFAllocatorDefault, uRef);
                cs.screenUUID = (__bridge_transfer NSString *)sRef;
                CFRelease(uRef);
            }
        }
        cs.isPrimary = (i == 0);
        cs.cocoaFrame = s.frame;
        cs.cocoaVisibleFrame = s.visibleFrame;
        cs.quartzFrame = [self convertCocoaFrameToQuartz:s.frame primaryScreenHeight:h0];
        cs.quartzVisibleFrame = [self convertCocoaFrameToQuartz:s.visibleFrame primaryScreenHeight:h0];
        [result addObject:cs];
    }
    return result;
}

+ (CascadeScreen *)primaryScreen {
    return [self availableScreens].firstObject;
}

+ (CascadeScreen *)activeScreen {
    return [self screenForPointer];
}

+ (CascadeScreen *)screenForCocoaPoint:(NSPoint)cocoaPoint inScreens:(NSArray<CascadeScreen *> *)screens {
    if (screens.count == 0) return nil;
    if (screens.count == 1) return screens.firstObject;

    for (CascadeScreen *s in screens) {
        if (NSPointInRect(cocoaPoint, s.cocoaFrame)) return s;
    }
    CascadeScreen *best = screens.firstObject;
    CGFloat minDist = CGFLOAT_MAX;
    for (CascadeScreen *s in screens) {
        CGPoint center = CGPointMake(CGRectGetMidX(s.cocoaFrame), CGRectGetMidY(s.cocoaFrame));
        CGFloat dist = hypot(cocoaPoint.x - center.x, cocoaPoint.y - center.y);
        if (dist < minDist) { minDist = dist; best = s; }
    }
    return best;
}

+ (CascadeScreen *)screenForPointerInScreens:(NSArray<CascadeScreen *> *)screens {
    return [self screenForCocoaPoint:[NSEvent mouseLocation] inScreens:screens];
}

+ (CascadeScreen *)screenForPointer {
    return [self screenForPointerInScreens:[self availableScreens]];
}

+ (CascadeScreen *)screenForFrame:(CGRect)quartzFrame inScreens:(NSArray<CascadeScreen *> *)screens {
    if (screens.count == 0) return nil;
    if (screens.count == 1) return screens.firstObject;

    CascadeScreen *bestScreen = screens.firstObject;
    CGFloat maxArea = 0;

    for (CascadeScreen *s in screens) {
        CGRect isect = CGRectIntersection(quartzFrame, s.quartzFrame);
        if (!CGRectIsNull(isect)) {
            CGFloat area = isect.size.width * isect.size.height;
            if (area > maxArea) {
                maxArea = area;
                bestScreen = s;
            }
        }
    }

    if (maxArea > 0) return bestScreen;

    // Fallback: check center point proximity
    CGPoint center = CGPointMake(CGRectGetMidX(quartzFrame), CGRectGetMidY(quartzFrame));
    CGFloat minDist = CGFLOAT_MAX;
    for (CascadeScreen *s in screens) {
        CGPoint sc = CGPointMake(CGRectGetMidX(s.quartzFrame), CGRectGetMidY(s.quartzFrame));
        CGFloat dist = hypot(center.x - sc.x, center.y - sc.y);
        if (dist < minDist) {
            minDist = dist;
            bestScreen = s;
        }
    }
    return bestScreen;
}

+ (CascadeScreen *)screenForFrame:(CGRect)quartzFrame {
    return [self screenForFrame:quartzFrame inScreens:[self availableScreens]];
}

static NSUserDefaults *screenDefaults(void) {
    static NSUserDefaults *defs = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        defs = [[NSUserDefaults alloc] initWithSuiteName:kScreenDomain];
        if (!defs) defs = [NSUserDefaults standardUserDefaults];
    });
    return defs;
}

+ (NSString *)savedScreenTarget {
    id val = [screenDefaults() objectForKey:kScreenTargetKey];
    if (!val) val = [[NSUserDefaults standardUserDefaults] persistentDomainForName:kScreenDomain][kScreenTargetKey];
    if (!val) val = [[NSUserDefaults standardUserDefaults] stringForKey:kScreenTargetKey];
    return ([val isKindOfClass:[NSString class]] && [val length] > 0) ? (NSString *)val : @"all";
}

+ (void)saveScreenTarget:(NSString *)target {
    NSString *val = (target && target.length > 0) ? target : @"all";
    [screenDefaults() setObject:val forKey:kScreenTargetKey];
    [screenDefaults() synchronize];

    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *domain = [[defs persistentDomainForName:kScreenDomain] mutableCopy] ?: [NSMutableDictionary dictionary];
    domain[kScreenTargetKey] = val;
    [defs setPersistentDomain:domain forName:kScreenDomain];
    [defs setObject:val forKey:kScreenTargetKey];
    [defs synchronize];
}

+ (NSArray<CascadeScreen *> *)screensMatchingTarget:(NSString *)target inScreens:(NSArray<CascadeScreen *> *)screens {
    if (screens.count == 0) return @[];
    if (!target || target.length == 0 || [target localizedCaseInsensitiveCompare:@"all"] == NSOrderedSame ||
        [target localizedCaseInsensitiveCompare:@"active"] == NSOrderedSame) {
        return screens;
    }
    if ([target localizedCaseInsensitiveCompare:@"primary"] == NSOrderedSame ||
        [target localizedCaseInsensitiveCompare:@"main"] == NSOrderedSame) {
        return @[screens.firstObject];
    }
    if ([target localizedCaseInsensitiveCompare:@"pointer"] == NSOrderedSame ||
        [target localizedCaseInsensitiveCompare:@"current"] == NSOrderedSame) {
        CascadeScreen *ptr = [self screenForPointerInScreens:screens];
        return ptr ? @[ptr] : screens;
    }

    // Match by screenUUID
    for (CascadeScreen *s in screens) {
        if (s.screenUUID.length > 0 && [s.screenUUID isEqualToString:target]) {
            return @[s];
        }
    }

    // Match by displayID
    for (CascadeScreen *s in screens) {
        if (s.displayID.length > 0 && [s.displayID isEqualToString:target]) {
            return @[s];
        }
    }

    // Match by name
    for (CascadeScreen *s in screens) {
        if ([s.name localizedCaseInsensitiveCompare:target] == NSOrderedSame ||
            [s.name localizedCaseInsensitiveContainsString:target]) {
            return @[s];
        }
    }

    // Match by index string
    for (CascadeScreen *s in screens) {
        if ([[NSString stringWithFormat:@"%ld", (long)s.index] isEqualToString:target]) {
            return @[s];
        }
    }

    // Fallback to primary
    return @[screens.firstObject];
}

+ (NSArray<CascadeScreen *> *)screensMatchingTarget:(NSString *)target {
    return [self screensMatchingTarget:target inScreens:[self availableScreens]];
}

+ (NSInteger)savedScreenSplit {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:kScreenDomain];
    id val = [defaults objectForKey:@"screenSplit"];
    NSInteger s = val ? [val integerValue] : 1;
    return (s >= 1 && s <= 4) ? s : 1;
}

+ (void)saveScreenSplit:(NSInteger)split {
    if (split < 1) split = 1;
    if (split > 4) split = 4;
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:kScreenDomain];
    [defaults setInteger:split forKey:@"screenSplit"];
    for (CascadeScreen *s in [self availableScreens]) {
        [self saveScreenSplit:split forScreen:s];
    }
}

+ (NSInteger)screenSplitForScreen:(CascadeScreen *)screen {
    if (!screen) return [self savedScreenSplit];
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:kScreenDomain];
    NSArray<NSString *> *keys = @[
        screen.screenUUID.length > 0 ? [@"screenSplit_uuid_" stringByAppendingString:screen.screenUUID] : @"",
        screen.displayID.length > 0 ? [@"screenSplit_id_" stringByAppendingString:screen.displayID] : @"",
        screen.name.length > 0 ? [@"screenSplit_name_" stringByAppendingString:screen.name] : @""
    ];
    for (NSString *k in keys) {
        if (k.length == 0) continue;
        id val = [defaults objectForKey:k];
        if (val) {
            NSInteger s = [val integerValue];
            return (s >= 1 && s <= 4) ? s : 1;
        }
    }
    NSInteger saved = [self savedScreenSplit];
    if (saved > 1) return saved;
    CGFloat w = screen.quartzFrame.size.width, h = screen.quartzFrame.size.height;
    if (h > 0) {
        CGFloat r = w / h;
        if (r >= 2.8) return 3;
        if (r >= 2.0) return 2;
    }
    return 1;
}

+ (void)saveScreenSplit:(NSInteger)split forScreen:(CascadeScreen *)screen {
    if (split < 1) split = 1;
    if (split > 4) split = 4;
    if (!screen) { [self saveScreenSplit:split]; return; }
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:kScreenDomain];
    if (screen.screenUUID.length > 0)
        [defaults setInteger:split forKey:[@"screenSplit_uuid_" stringByAppendingString:screen.screenUUID]];
    if (screen.displayID.length > 0)
        [defaults setInteger:split forKey:[@"screenSplit_id_" stringByAppendingString:screen.displayID]];
    if (screen.name.length > 0)
        [defaults setInteger:split forKey:[@"screenSplit_name_" stringByAppendingString:screen.name]];
}

+ (void)saveScreenSplit:(NSInteger)split forScreenUUID:(NSString *)uuid {
    if (split < 1) split = 1;
    if (split > 4) split = 4;
    if (!uuid || uuid.length == 0 || [uuid localizedCaseInsensitiveCompare:@"all"] == NSOrderedSame) {
        [self saveScreenSplit:split];
        return;
    }
    [[[NSUserDefaults alloc] initWithSuiteName:kScreenDomain] setInteger:split forKey:[@"screenSplit_uuid_" stringByAppendingString:uuid]];
}

+ (void)saveScreenSplit:(NSInteger)split forScreenName:(NSString *)name {
    if (split < 1) split = 1;
    if (split > 4) split = 4;
    if (!name || [name localizedCaseInsensitiveCompare:@"all"] == NSOrderedSame) {
        [self saveScreenSplit:split];
        return;
    }
    for (CascadeScreen *s in [self availableScreens]) {
        if ([s.name localizedCaseInsensitiveCompare:name] == NSOrderedSame ||
            (s.screenUUID.length > 0 && [s.screenUUID isEqualToString:name]) ||
            (s.displayID.length > 0 && [s.displayID isEqualToString:name])) {
            [self saveScreenSplit:split forScreen:s];
            return;
        }
    }
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:kScreenDomain];
    [defaults setInteger:split forKey:[NSString stringWithFormat:@"screenSplit_name_%@", name]];
}

+ (NSArray<CascadeScreen *> *)subscreensForScreen:(CascadeScreen *)screen splitCount:(NSInteger)k {
    if (k <= 1 || !screen) return screen ? @[screen] : @[];
    NSMutableArray<CascadeScreen *> *subs = [NSMutableArray arrayWithCapacity:k];
    CGRect qf = screen.quartzVisibleFrame;
    CGRect qfTotal = screen.quartzFrame;
    CGFloat colW = floor(qf.size.width / (CGFloat)k);

    for (NSInteger i = 0; i < k; i++) {
        CascadeScreen *cs = [[CascadeScreen alloc] init];
        cs.index = screen.index * 10 + i;
        cs.columnIndex = i;
        cs.totalColumns = k;
        cs.isPrimary = screen.isPrimary && (i == 0);
        cs.name = [NSString stringWithFormat:@"%@ [Col %ld/%ld]", screen.name, (long)(i + 1), (long)k];
        cs.displayID = [NSString stringWithFormat:@"%@_col%ld", screen.displayID.length > 0 ? screen.displayID : [@(screen.index) stringValue], (long)i];
        cs.screenUUID = screen.screenUUID.length > 0 ? [NSString stringWithFormat:@"%@_col%ld", screen.screenUUID, (long)i] : nil;

        CGFloat x = qf.origin.x + (CGFloat)i * colW;
        CGFloat w = (i == k - 1) ? (qf.size.width - (CGFloat)(k - 1) * colW) : colW;
        cs.quartzVisibleFrame = CGRectMake(x, qf.origin.y, w, qf.size.height);
        cs.quartzFrame = CGRectMake(x, qfTotal.origin.y, w, qfTotal.size.height);
        CGFloat cx = screen.cocoaFrame.origin.x + (CGFloat)i * colW;
        cs.cocoaFrame = CGRectMake(cx, screen.cocoaFrame.origin.y, w, screen.cocoaFrame.size.height);
        cs.cocoaVisibleFrame = CGRectMake(cx, screen.cocoaVisibleFrame.origin.y, w, screen.cocoaVisibleFrame.size.height);
        [subs addObject:cs];
    }
    return subs;
}

+ (NSArray<CascadeScreen *> *)expandScreensWithSplits:(NSArray<CascadeScreen *> *)screens {
    if (screens.count == 0) return @[];
    NSMutableArray<CascadeScreen *> *result = [NSMutableArray array];
    for (CascadeScreen *s in screens) {
        NSInteger k = [self screenSplitForScreen:s];
        if (k > 1) {
            [result addObjectsFromArray:[self subscreensForScreen:s splitCount:k]];
        } else {
            [result addObject:s];
        }
    }
    return result;
}

+ (NSDictionary<CascadeScreen *, NSArray<CascadeWindow *> *> *)partitionWindows:(NSArray<CascadeWindow *> *)windows intoScreens:(NSArray<CascadeScreen *> *)screens {
    NSMutableDictionary<CascadeScreen *, NSMutableArray<CascadeWindow *> *> *dict = [NSMutableDictionary dictionary];
    for (CascadeScreen *s in screens) {
        dict[s] = [NSMutableArray array];
    }
    if (windows.count == 0 || screens.count == 0) return dict;

    for (CascadeWindow *w in windows) {
        CascadeScreen *best = [self screenForFrame:w.currentFrame inScreens:screens];
        if (best && dict[best]) {
            [dict[best] addObject:w];
        } else {
            [dict[screens.firstObject] addObject:w];
        }
    }

    NSMutableDictionary<NSString *, NSMutableArray<CascadeScreen *> *> *groups = [NSMutableDictionary dictionary];
    for (CascadeScreen *s in screens) {
        if (s.totalColumns > 1) {
            NSString *base = [s.displayID componentsSeparatedByString:@"_col"].firstObject ?: s.name;
            if (!groups[base]) groups[base] = [NSMutableArray array];
            [groups[base] addObject:s];
        }
    }

    for (NSString *base in groups) {
        NSArray<CascadeScreen *> *colScreens = groups[base];
        if (colScreens.count <= 1) continue;

        NSMutableArray<CascadeWindow *> *totalWins = [NSMutableArray array];
        BOOL hasEmpty = NO;
        for (CascadeScreen *cs in colScreens) {
            NSArray *wList = dict[cs];
            if (wList.count == 0) hasEmpty = YES;
            [totalWins addObjectsFromArray:wList];
        }

        if (hasEmpty && totalWins.count > 0) {
            for (CascadeScreen *cs in colScreens) {
                [dict[cs] removeAllObjects];
            }
            NSUInteger total = totalWins.count;
            NSUInteger numCols = colScreens.count;
            for (NSUInteger idx = 0; idx < total; idx++) {
                NSUInteger colIdx = (total >= numCols) ? ((idx * numCols) / total) : idx;
                CascadeScreen *targetCol = colScreens[colIdx];
                [dict[targetCol] addObject:totalWins[idx]];
            }
        }
    }

    return dict;
}

@end
