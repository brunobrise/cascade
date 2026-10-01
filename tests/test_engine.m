#import <Foundation/Foundation.h>
#import <assert.h>
#import "../src/WindowEngine.h"

// Helper to construct mock CascadeWindow
static CascadeWindow *makeMockWindow(NSString *name, CGFloat x, CGFloat y, CGFloat w, CGFloat h, NSInteger zRank) {
    CascadeWindow *win = [[CascadeWindow alloc] init];
    win.appName = name;
    win.title = [NSString stringWithFormat:@"%@ Window", name];
    win.pid = 1000 + (pid_t)zRank;
    win.currentFrame = CGRectMake(x, y, w, h);
    win.zRank = zRank;
    return win;
}

static void testTwoWindowLayout() {
    printf("Running testTwoWindowLayout...\n");
    NSMutableArray *wins = [NSMutableArray array];
    [wins addObject:makeMockWindow(@"Slack", 100, 100, 800, 600, 1)];
    [wins addObject:makeMockWindow(@"Chrome", 200, 200, 800, 600, 2)];

    CGFloat delta = 40.0;
    NSArray<CascadeWindow *> *planned = [CascadeEngine calculateLayoutForWindows:wins orderMode:CascadeOrderModeMRU delta:delta];

    assert(planned.count == 2);
    CGFloat topInset = 0;
    CGRect usable = [CascadeEngine usableScreenFrameWithTopInset:&topInset];

    CascadeWindow *w1 = planned[0];
    CascadeWindow *w2 = planned[1];

    // Slack was zRank 1 (MRU), so it is first
    assert([w1.appName isEqualToString:@"Slack"]);
    assert([w2.appName isEqualToString:@"Chrome"]);

    // Opposed edge widths must be usableW - delta
    assert(fabs(w1.targetFrame.size.width - (usable.size.width - delta)) < 0.01);
    assert(fabs(w2.targetFrame.size.width - (usable.size.width - delta)) < 0.01);
    assert(fabs(w1.targetFrame.size.height - usable.size.height) < 0.01);
    assert(fabs(w2.targetFrame.size.height - usable.size.height) < 0.01);

    // Offsets
    assert(fabs(w1.targetFrame.origin.x - usable.origin.x) < 0.01);
    assert(fabs(w2.targetFrame.origin.x - (usable.origin.x + delta)) < 0.01);

    printf("  [PASS] testTwoWindowLayout passed.\n");
}

static void testCascadeTabDisjointness() {
    printf("Running testCascadeTabDisjointness (N=5)...\n");
    NSMutableArray *wins = [NSMutableArray array];
    [wins addObject:makeMockWindow(@"AppA", 0, 0, 500, 500, 1)];
    [wins addObject:makeMockWindow(@"AppB", 0, 0, 500, 500, 2)];
    [wins addObject:makeMockWindow(@"AppC", 0, 0, 500, 500, 3)];
    [wins addObject:makeMockWindow(@"AppD", 0, 0, 500, 500, 4)];
    [wins addObject:makeMockWindow(@"AppE", 0, 0, 500, 500, 5)];

    CGFloat delta = 45.0;
    NSArray<CascadeWindow *> *planned = [CascadeEngine calculateLayoutForWindows:wins orderMode:CascadeOrderModeMRU delta:delta];
    assert(planned.count == 5);

    // Verify mathematical theorem:
    // For every window i, its top-right tab P_i must NOT intersect any other window j != i
    for (NSUInteger i = 0; i < planned.count; i++) {
        CGRect tf_i = planned[i].targetFrame;
        // Top-right tab of size (delta - 1) to check open interior
        CGRect tab_i = CGRectMake(tf_i.origin.x + tf_i.size.width - delta + 1,
                                  tf_i.origin.y + 1,
                                  delta - 2,
                                  delta - 2);

        for (NSUInteger j = 0; j < planned.count; j++) {
            if (i == j) continue;
            CGRect tf_j = planned[j].targetFrame;
            BOOL intersects = CGRectIntersectsRect(tab_i, tf_j);
            if (intersects) {
                printf("  [FAIL] Window %lu tab intersects Window %lu!\n", i, j);
                printf("         Tab %lu: %.1f,%.1f %.1fx%.1f\n", i, tab_i.origin.x, tab_i.origin.y, tab_i.size.width, tab_i.size.height);
                printf("         Win %lu: %.1f,%.1f %.1fx%.1f\n", j, tf_j.origin.x, tf_j.origin.y, tf_j.size.width, tf_j.size.height);
                assert(!intersects);
            }
        }
    }
    printf("  [PASS] Mathematical invariant verified: All 5 tabs are mutually disjoint!\n");
}

static void testSortingModes() {
    printf("Running testSortingModes...\n");
    NSMutableArray *wins = [NSMutableArray array];
    [wins addObject:makeMockWindow(@"Slack", 500, 0, 400, 400, 3)];
    [wins addObject:makeMockWindow(@"Chrome", 100, 0, 400, 400, 1)];
    [wins addObject:makeMockWindow(@"Antigravity", 300, 0, 400, 400, 2)];

    // 1. Test MRU: Chrome (zRank 1) -> Antigravity (2) -> Slack (3)
    NSArray<CascadeWindow *> *mru = [CascadeEngine calculateLayoutForWindows:wins orderMode:CascadeOrderModeMRU delta:40];
    assert([mru[0].appName isEqualToString:@"Chrome"]);
    assert([mru[1].appName isEqualToString:@"Antigravity"]);
    assert([mru[2].appName isEqualToString:@"Slack"]);

    // 2. Test Spatial (X position): Chrome (x=100) -> Antigravity (x=300) -> Slack (x=500)
    NSArray<CascadeWindow *> *spatial = [CascadeEngine calculateLayoutForWindows:wins orderMode:CascadeOrderModeSpatial delta:40];
    assert([spatial[0].appName isEqualToString:@"Chrome"]);
    assert([spatial[1].appName isEqualToString:@"Antigravity"]);
    assert([spatial[2].appName isEqualToString:@"Slack"]);

    // 3. Test Alphabetical: Antigravity -> Chrome -> Slack
    NSArray<CascadeWindow *> *alpha = [CascadeEngine calculateLayoutForWindows:wins orderMode:CascadeOrderModeAlphabetical delta:40];
    assert([alpha[0].appName isEqualToString:@"Antigravity"]);
    assert([alpha[1].appName isEqualToString:@"Chrome"]);
    assert([alpha[2].appName isEqualToString:@"Slack"]);

    printf("  [PASS] All 3 sorting modes correctly ordered.\n");
}

int main(int argc, const char * argv[]) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        printf("=== Running Cascade Unit Tests ===\n\n");
        testTwoWindowLayout();
        testCascadeTabDisjointness();
        testSortingModes();
        printf("\n=== All Tests Passed Successfully! ===\n");
    }
    return 0;
}
