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
    if (count == 2) {
        ordered[0].targetFrame = CGRectMake(originX, originY, usableW - delta, usableH);
        ordered[1].targetFrame = CGRectMake(originX + delta, originY, usableW - delta, usableH);
        return;
    }

    NSUInteger nT = (count + 3) / 4;
    NSUInteger nR = (count + 2) / 4;
    NSUInteger nB = (count + 1) / 4;
    NSUInteger nL = count / 4;

    CGFloat maxDeltaX = (usableW - 400.0) / (CGFloat)MAX((NSUInteger)1, (nL + nR + MAX((NSInteger)0, (NSInteger)nT - 1)));
    CGFloat maxDeltaY = (usableH - 300.0) / (CGFloat)MAX((NSUInteger)1, (nT + nB + MAX((NSInteger)0, (NSInteger)nR - 1)));
    CGFloat effDelta = MIN(delta, MIN(maxDeltaX, maxDeltaY));
    if (effDelta < 15.0) effDelta = 15.0;

    CGFloat mT = nT * effDelta, mR = nR * effDelta;
    CGFloat mB = nB * effDelta, mL = nL * effDelta;

    for (NSUInteger i = 0; i < count; i++) {
        NSUInteger side = i % 4;
        NSUInteger cycle = i / 4;
        CGFloat x = originX, y = originY, w = usableW, h = usableH;

        if (side == 0) { // Top
            w = usableW - mL - mR - (nT - 1) * effDelta;
            h = usableH - mB - (nT - 1) * effDelta;
            x = originX + mL + cycle * effDelta;
            y = originY + cycle * effDelta;
        } else if (side == 1) { // Right
            w = usableW - mL - (nR - 1) * effDelta;
            h = usableH - mT - mB - (nR - 1) * effDelta;
            x = originX + usableW - w - cycle * effDelta;
            y = originY + mT + cycle * effDelta;
        } else if (side == 2) { // Bottom
            w = usableW - mL - mR - (nB - 1) * effDelta;
            h = usableH - mT - (nB - 1) * effDelta;
            x = originX + mL + cycle * effDelta;
            y = originY + usableH - h - cycle * effDelta;
        } else if (side == 3) { // Left
            w = usableW - mR - (nL - 1) * effDelta;
            h = usableH - mT - mB - (nL - 1) * effDelta;
            x = originX + cycle * effDelta;
            y = originY + mT + cycle * effDelta;
        }

        if (w < 200.0) w = 200.0;
        if (h < 150.0) h = 150.0;
        ordered[i].targetFrame = CGRectMake(x, y, w, h);
    }
}

+ (void)assignFractalFramesToOrderedWindows:(NSArray<CascadeWindow *> *)ordered
                              onUsableFrame:(CGRect)usable
                                      delta:(CGFloat)delta {
    (void)delta;
    NSUInteger count = ordered.count;
    if (count == 0) return;
    for (CascadeWindow *w in ordered) { w.usableFrame = usable; }

    if (count == 1) {
        ordered[0].targetFrame = usable;
        return;
    }

    const CGFloat phi = (sqrt(5.0) - 1.0) / 2.0; // ~0.6180339887
    CGRect curBox = usable;

    for (NSUInteger i = 0; i < count; i++) {
        if (i == count - 1) {
            ordered[i].targetFrame = curBox;
            break;
        }

        NSUInteger side = i % 4;
        CGFloat curX = curBox.origin.x;
        CGFloat curY = curBox.origin.y;
        CGFloat curW = curBox.size.width;
        CGFloat curH = curBox.size.height;

        if (side == 0) { // Left
            CGFloat sliceW = curW * phi;
            ordered[i].targetFrame = CGRectMake(curX, curY, sliceW, curH);
            curBox = CGRectMake(curX + sliceW, curY, curW - sliceW, curH);
        } else if (side == 1) { // Top
            CGFloat sliceH = curH * phi;
            ordered[i].targetFrame = CGRectMake(curX, curY, curW, sliceH);
            curBox = CGRectMake(curX, curY + sliceH, curW, curH - sliceH);
        } else if (side == 2) { // Right
            CGFloat sliceW = curW * phi;
            ordered[i].targetFrame = CGRectMake(curX + curW - sliceW, curY, sliceW, curH);
            curBox = CGRectMake(curX, curY, curW - sliceW, curH);
        } else if (side == 3) { // Bottom
            CGFloat sliceH = curH * phi;
            ordered[i].targetFrame = CGRectMake(curX, curY + curH - sliceH, curW, sliceH);
            curBox = CGRectMake(curX, curY, curW, curH - sliceH);
        }
    }
}

+ (CGRect)dockedFrameForEdge:(CascadeDockEdge)edge onUsableFrame:(CGRect)usable {
    CGFloat uX = usable.origin.x, uY = usable.origin.y;
    CGFloat uW = usable.size.width, uH = usable.size.height;
    CGFloat halfW = uW * 0.5;
    CGFloat halfH = uH * 0.5;
    switch (edge) {
        case CascadeDockEdgeLeft:
            return CGRectMake(uX, uY, halfW, uH);
        case CascadeDockEdgeRight:
            return CGRectMake(uX + halfW, uY, halfW, uH);
        case CascadeDockEdgeTop:
            return CGRectMake(uX, uY, uW, halfH);
        case CascadeDockEdgeBottom:
            return CGRectMake(uX, uY + halfH, uW, halfH);
    }
}

+ (void)assignDockedFramesToWindows:(NSArray<CascadeWindow *> *)windows
                  activeWindowIndex:(NSUInteger)activeIdx
                               edge:(CascadeDockEdge)edge
                      onUsableFrame:(CGRect)usable
                              delta:(CGFloat)delta
                        layoutStyle:(CascadeLayoutStyle)style {
    NSUInteger count = windows.count;
    if (count == 0) return;
    for (CascadeWindow *w in windows) { w.usableFrame = usable; }

    if (count == 1 || activeIdx >= count) {
        [self assignFramesToOrderedWindows:windows onUsableFrame:usable delta:delta layoutStyle:style];
        return;
    }

    CascadeWindow *activeWin = windows[activeIdx];
    CGFloat uX = usable.origin.x, uY = usable.origin.y;
    CGFloat uW = usable.size.width, uH = usable.size.height;
    CGRect activeFrame = [self dockedFrameForEdge:edge onUsableFrame:usable];
    CGRect residualFrame = CGRectZero;

    CGFloat halfW = uW * 0.5;
    CGFloat halfH = uH * 0.5;

    switch (edge) {
        case CascadeDockEdgeLeft:
            residualFrame = CGRectMake(uX + halfW, uY, halfW, uH);
            break;
        case CascadeDockEdgeRight:
            residualFrame = CGRectMake(uX, uY, halfW, uH);
            break;
        case CascadeDockEdgeTop:
            residualFrame = CGRectMake(uX, uY + halfH, uW, halfH);
            break;
        case CascadeDockEdgeBottom:
            residualFrame = CGRectMake(uX, uY, uW, halfH);
            break;
    }

    activeWin.targetFrame = activeFrame;

    NSMutableArray<CascadeWindow *> *remaining = [NSMutableArray arrayWithCapacity:count - 1];
    for (NSUInteger i = 0; i < count; i++) {
        if (i != activeIdx) {
            [remaining addObject:windows[i]];
        }
    }

    if (remaining.count > 0) {
        [self assignFramesToOrderedWindows:remaining onUsableFrame:residualFrame delta:delta layoutStyle:style];
        for (CascadeWindow *rw in remaining) {
            rw.usableFrame = usable;
        }
    }
}

+ (void)assignFramesToOrderedWindows:(NSArray<CascadeWindow *> *)ordered
                       onUsableFrame:(CGRect)usable
                               delta:(CGFloat)delta
                         layoutStyle:(CascadeLayoutStyle)style {
    if (style == CascadeLayoutStyleQuadEdge) {
        [self assignQuadEdgeFramesToOrderedWindows:ordered onUsableFrame:usable delta:delta];
    } else if (style == CascadeLayoutStyleFractal) {
        [self assignFractalFramesToOrderedWindows:ordered onUsableFrame:usable delta:delta];
    } else {
        [self assignDiagonalFramesToOrderedWindows:ordered onUsableFrame:usable delta:delta];
    }
}

@end
