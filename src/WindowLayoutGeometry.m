#import "WindowLayoutGeometry.h"

@implementation WindowLayoutGeometry

+ (void)assignDiagonalFramesToOrderedWindows:(NSArray<CascadeWindow *> *)ordered
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

+ (void)assignQuadEdgeFramesToOrderedWindows:(NSArray<CascadeWindow *> *)ordered
                               onUsableFrame:(CGRect)usable
                                       delta:(CGFloat)delta {
    NSUInteger count = ordered.count;
    if (count == 0) return;
    for (CascadeWindow *w in ordered) { w.usableFrame = usable; }
    CGFloat usableW = usable.size.width, usableH = usable.size.height;
    CGFloat originX = usable.origin.x, originY = usable.origin.y;

    if (count == 1) {
        ordered[0].targetFrame = usable;
        return;
    }

    NSUInteger nT = (count + 3) / 4;
    NSUInteger nR = (count + 2) / 4;
    NSUInteger nB = (count + 1) / 4;
    NSUInteger nL = count / 4;

    CGFloat maxDeltaX = (usableW - 400.0) / MAX((NSUInteger)1, (nL + nR));
    CGFloat maxDeltaY = (usableH - 300.0) / MAX((NSUInteger)1, (nT + nB));
    CGFloat effDelta = MIN(delta, MIN(maxDeltaX, maxDeltaY));
    if (effDelta < 15.0) effDelta = 15.0;

    CGFloat mT = nT * effDelta, mR = nR * effDelta;
    CGFloat mB = nB * effDelta, mL = nL * effDelta;

    for (NSUInteger i = 0; i < count; i++) {
        NSUInteger side = i % 4;
        NSUInteger cycle = i / 4;
        CGFloat x = originX, y = originY, w = usableW, h = usableH;

        if (side == 0) { // Top
            x = originX + mL;
            y = originY + cycle * effDelta;
            w = usableW - mL - mR;
            h = usableH - mB - cycle * effDelta;
        } else if (side == 1) { // Right
            x = originX + mL + cycle * effDelta;
            y = originY + mT;
            w = usableW - mL - cycle * effDelta;
            h = usableH - mT - mB;
        } else if (side == 2) { // Bottom
            x = originX + mL;
            y = originY + mT + cycle * effDelta;
            w = usableW - mL - mR;
            h = usableH - mT - cycle * effDelta;
        } else if (side == 3) { // Left
            x = originX + cycle * effDelta;
            y = originY + mT;
            w = usableW - mR - cycle * effDelta;
            h = usableH - mT - mB;
        }

        if (w < 200.0) w = 200.0;
        if (h < 150.0) h = 150.0;
        ordered[i].targetFrame = CGRectMake(x, y, w, h);
    }
}

+ (void)assignFramesToOrderedWindows:(NSArray<CascadeWindow *> *)ordered
                       onUsableFrame:(CGRect)usable
                               delta:(CGFloat)delta
                         layoutStyle:(CascadeLayoutStyle)style {
    if (style == CascadeLayoutStyleQuadEdge) {
        [self assignQuadEdgeFramesToOrderedWindows:ordered onUsableFrame:usable delta:delta];
    } else {
        [self assignDiagonalFramesToOrderedWindows:ordered onUsableFrame:usable delta:delta];
    }
}

@end
