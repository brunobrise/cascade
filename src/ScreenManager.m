#import "ScreenManager.h"

static NSString * const kScreenDomain = @"com.brunobrise.cascade";
static NSString * const kScreenTargetKey = @"screenTarget";

@implementation CascadeScreen
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
    NSArray<CascadeScreen *> *screens = [self availableScreens];
    if (screens.count <= 1) return screens.firstObject;

    NSScreen *main = [NSScreen mainScreen];
    if (main) {
        for (CascadeScreen *cs in screens) {
            if (cs.index == (NSInteger)[screens indexOfObject:cs] &&
                NSEqualRects(cs.cocoaFrame, main.frame)) {
                return cs;
            }
        }
    }
    return screens.firstObject;
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
    if (!target || target.length == 0 || [target localizedCaseInsensitiveCompare:@"all"] == NSOrderedSame) {
        return screens;
    }
    if ([target localizedCaseInsensitiveCompare:@"active"] == NSOrderedSame) {
        CascadeScreen *act = [self activeScreen];
        return act ? @[act] : @[screens.firstObject];
    }
    if ([target localizedCaseInsensitiveCompare:@"primary"] == NSOrderedSame ||
        [target localizedCaseInsensitiveCompare:@"main"] == NSOrderedSame) {
        return @[screens.firstObject];
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

@end
