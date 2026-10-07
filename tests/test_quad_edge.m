#import <Cocoa/Cocoa.h>
#import <assert.h>
#import "../src/WindowEngine.h"
#import "../src/WindowLayoutGeometry.h"

static void testQuadEdgePreferencesPersistence() {
    printf("Running testQuadEdgePreferencesPersistence...\n");
    CascadeLayoutStyle orig = [CascadeEngine savedLayoutStyle];

    [CascadeEngine saveLayoutStyle:CascadeLayoutStyleQuadEdge];
    assert([CascadeEngine savedLayoutStyle] == CascadeLayoutStyleQuadEdge);

    [CascadeEngine saveLayoutStyle:CascadeLayoutStyleDiagonal];
    assert([CascadeEngine savedLayoutStyle] == CascadeLayoutStyleDiagonal);

    [CascadeEngine saveLayoutStyle:orig];
    printf("  [PASS] Layout style preference persistence verified.\n");
}

static void testQuadEdgeGeometricInvariants() {
    printf("Running testQuadEdgeGeometricInvariants...\n");
    CGRect usable = CGRectMake(0, 30, 2560, 1410);
    CGFloat delta = 40.0;

    // N = 1
    CascadeWindow *w1 = [[CascadeWindow alloc] init];
    [WindowLayoutGeometry assignQuadEdgeFramesToOrderedWindows:@[w1] onUsableFrame:usable delta:delta];
    assert(CGRectEqualToRect(w1.targetFrame, usable));

    // N = 4: Top -> Right -> Bottom -> Left
    NSMutableArray<CascadeWindow *> *wins4 = [NSMutableArray array];
    for (int i = 0; i < 4; i++) [wins4 addObject:[[CascadeWindow alloc] init]];
    [WindowLayoutGeometry assignQuadEdgeFramesToOrderedWindows:wins4 onUsableFrame:usable delta:delta];

    CascadeWindow *topWin = wins4[0];
    CascadeWindow *rightWin = wins4[1];
    CascadeWindow *bottomWin = wins4[2];
    CascadeWindow *leftWin = wins4[3];

    // Verify Top window has unoccluded top strip (y in [30, 30 + delta])
    assert(topWin.targetFrame.origin.y == 30.0);
    assert(rightWin.targetFrame.origin.y >= 30.0 + delta);
    assert(bottomWin.targetFrame.origin.y >= 30.0 + delta);
    assert(leftWin.targetFrame.origin.y >= 30.0 + delta);

    // Verify Right window has unoccluded right strip (x in [2560 - delta, 2560])
    CGFloat rightMaxX = CGRectGetMaxX(rightWin.targetFrame);
    assert(fabs(rightMaxX - 2560.0) < 1.0);
    assert(CGRectGetMaxX(topWin.targetFrame) <= 2560.0 - delta);
    assert(CGRectGetMaxX(bottomWin.targetFrame) <= 2560.0 - delta);
    assert(CGRectGetMaxX(leftWin.targetFrame) <= 2560.0 - delta);

    // Verify Bottom window has unoccluded bottom strip (y in [1440 - delta, 1440])
    CGFloat bottomMaxY = CGRectGetMaxY(bottomWin.targetFrame);
    assert(fabs(bottomMaxY - 1440.0) < 1.0);
    assert(CGRectGetMaxY(topWin.targetFrame) <= 1440.0 - delta);
    assert(CGRectGetMaxY(rightWin.targetFrame) <= 1440.0 - delta);
    assert(CGRectGetMaxY(leftWin.targetFrame) <= 1440.0 - delta);

    // Verify Left window has unoccluded left strip (x in [0, delta])
    assert(leftWin.targetFrame.origin.x == 0.0);
    assert(topWin.targetFrame.origin.x >= delta);
    assert(rightWin.targetFrame.origin.x >= delta);
    assert(bottomWin.targetFrame.origin.x >= delta);

    // Verify area comparison: Quad-Edge area > Diagonal area for N = 4
    NSMutableArray<CascadeWindow *> *diagWins4 = [NSMutableArray array];
    for (int i = 0; i < 4; i++) [diagWins4 addObject:[[CascadeWindow alloc] init]];
    [WindowLayoutGeometry assignDiagonalFramesToOrderedWindows:diagWins4 onUsableFrame:usable delta:delta];

    CGFloat quadArea = topWin.targetFrame.size.width * topWin.targetFrame.size.height;
    CGFloat diagArea = diagWins4[0].targetFrame.size.width * diagWins4[0].targetFrame.size.height;
    assert(quadArea > diagArea);
    printf("  [PASS] Quad-Edge (area: %.0f px^2) is larger than Diagonal (area: %.0f px^2).\n", quadArea, diagArea);
    printf("  [PASS] Top, Right, Bottom, Left unoccluded edge invariant verified.\n");
}

static void testMultiCycleQuadEdge() {
    printf("Running testMultiCycleQuadEdge (N = 8)...\n");
    CGRect usable = CGRectMake(0, 0, 1920, 1080);
    CGFloat delta = 30.0;
    NSMutableArray<CascadeWindow *> *wins8 = [NSMutableArray array];
    for (int i = 0; i < 8; i++) [wins8 addObject:[[CascadeWindow alloc] init]];

    [WindowLayoutGeometry assignQuadEdgeFramesToOrderedWindows:wins8 onUsableFrame:usable delta:delta];
    for (NSUInteger i = 0; i < 8; i++) {
        CGRect f = wins8[i].targetFrame;
        assert(f.size.width > 300);
        assert(f.size.height > 200);
    }
    printf("  [PASS] Multi-cycle Quad-Edge (N = 8) correctly calculated without distortion.\n");
}

static BOOL pointInRect(CGRect r, CGFloat px, CGFloat py) {
    return px >= r.origin.x && px < CGRectGetMaxX(r) && py >= r.origin.y && py < CGRectGetMaxY(r);
}

static void testFiveWindowQuadEdgeUnoccludedTarget() {
    printf("Running testFiveWindowQuadEdgeUnoccludedTarget (N = 5)...\n");
    CGRect usable = CGRectMake(0, 30, 2560, 1410);
    CGFloat delta = 40.0;
    NSMutableArray<CascadeWindow *> *wins5 = [NSMutableArray array];
    for (int i = 0; i < 5; i++) [wins5 addObject:[[CascadeWindow alloc] init]];
    [WindowLayoutGeometry assignQuadEdgeFramesToOrderedWindows:wins5 onUsableFrame:usable delta:delta];

    for (int i = 0; i < 5; i++) {
        CGFloat unoccluded = 0;
        CGRect fi = wins5[i].targetFrame;
        for (CGFloat px = fi.origin.x; px < CGRectGetMaxX(fi); px += 4.0) {
            for (CGFloat py = fi.origin.y; py < CGRectGetMaxY(fi); py += 4.0) {
                BOOL covered = NO;
                for (int j = 0; j < 5; j++) {
                    if (j != i && pointInRect(wins5[j].targetFrame, px, py)) {
                        covered = YES;
                        break;
                    }
                }
                if (!covered) unoccluded += 16.0;
            }
        }
        assert(unoccluded > 0);
    }
    printf("  [PASS] 5th window (and all 5 windows) has guaranteed unoccluded click target.\n");
}

int main(int argc, const char * argv[]) {
    (void)argc; (void)argv;
    @autoreleasepool {
        printf("=== Running Quad-Edge Layout Unit Tests ===\n\n");
        testQuadEdgePreferencesPersistence();
        testQuadEdgeGeometricInvariants();
        testMultiCycleQuadEdge();
        testFiveWindowQuadEdgeUnoccludedTarget();
        printf("\n=== All Quad-Edge Tests Passed Successfully! ===\n");
    }
    return 0;
}
