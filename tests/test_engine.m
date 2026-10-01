#import <Foundation/Foundation.h>
#import <assert.h>
#import "../src/WindowEngine.h"

// Helper to construct mock CascadeWindow
static CascadeWindow *makeMockWindow(NSString *name, CGFloat x, CGFloat y, CGFloat w, CGFloat h, NSInteger zRank) {
    CascadeWindow *win = [[CascadeWindow alloc] init];
    win.appName = name;
    win.title = [NSString stringWithFormat:@"%@ Window", name];
    win.pid = (pid_t)(abs((int)[name hash]) % 9000 + 1000);
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

static void testOrderPreservationOnWindowClose() {
    printf("Running testOrderPreservationOnWindowClose...\n");
    CascadeWindow *winA = makeMockWindow(@"Editor", 0, 0, 800, 600, 1);
    CascadeWindow *winB = makeMockWindow(@"Browser", 100, 100, 800, 600, 2);
    CascadeWindow *winC = makeMockWindow(@"Terminal", 200, 200, 800, 600, 3);

    // Initial established order: Editor -> Browser -> Terminal
    NSArray<CascadeWindow *> *initialOrder = @[winA, winB, winC];
    NSArray<CascadeWindow *> *baseline = [CascadeEngine calculateLayoutForWindows:initialOrder
                                                                        orderMode:CascadeOrderModeMRU
                                                                            delta:40.0];
    assert(baseline.count == 3);
    assert([baseline[0].appName isEqualToString:@"Editor"]);
    assert([baseline[1].appName isEqualToString:@"Browser"]);
    assert([baseline[2].appName isEqualToString:@"Terminal"]);

    // Event: Browser is closed/minimized. Terminal is now frontmost (zRank 1).
    CascadeWindow *winC_active = makeMockWindow(@"Terminal", 200, 200, 800, 600, 1);
    CascadeWindow *winA_back = makeMockWindow(@"Editor", 0, 0, 800, 600, 2);
    NSArray<CascadeWindow *> *currentWindows = @[winC_active, winA_back];

    // Preserving order must keep Editor at slot 0 and Terminal at slot 1
    NSArray<CascadeWindow *> *preserved = [CascadeEngine calculateLayoutForWindows:currentWindows
                                                              preservingOrderFrom:baseline
                                                                            delta:40.0];
    assert(preserved.count == 2);
    assert([preserved[0].appName isEqualToString:@"Editor"]);
    assert([preserved[1].appName isEqualToString:@"Terminal"]);

    // Windows must expand to 2-window dimensions (usableW - delta)
    CGFloat topInset = 0;
    CGRect usable = [CascadeEngine usableScreenFrameWithTopInset:&topInset];
    assert(fabs(preserved[0].targetFrame.size.width - (usable.size.width - 40.0)) < 0.01);
    assert(fabs(preserved[1].targetFrame.size.width - (usable.size.width - 40.0)) < 0.01);
    printf("  [PASS] Order preserved on window close and size recalculated.\n");
}

static void testOrderPreservationOnNewWindow() {
    printf("Running testOrderPreservationOnNewWindow...\n");
    CascadeWindow *winA = makeMockWindow(@"Editor", 0, 0, 800, 600, 1);
    CascadeWindow *winC = makeMockWindow(@"Terminal", 200, 200, 800, 600, 2);

    NSArray<CascadeWindow *> *baseline = [CascadeEngine calculateLayoutForWindows:@[winA, winC]
                                                                        orderMode:CascadeOrderModeMRU
                                                                            delta:40.0];

    // Event: New window (Slack) opens and becomes frontmost (zRank 1)
    CascadeWindow *winD_new = makeMockWindow(@"Slack", 50, 50, 400, 400, 1);
    CascadeWindow *winA_curr = makeMockWindow(@"Editor", 0, 0, 800, 600, 2);
    CascadeWindow *winC_curr = makeMockWindow(@"Terminal", 200, 200, 800, 600, 3);
    NSArray<CascadeWindow *> *currentWindows = @[winD_new, winA_curr, winC_curr];

    NSArray<CascadeWindow *> *preserved = [CascadeEngine calculateLayoutForWindows:currentWindows
                                                              preservingOrderFrom:baseline
                                                                            delta:40.0];
    assert(preserved.count == 3);
    // Existing windows retain relative order: Editor (0), Terminal (1), Slack (2 appended)
    assert([preserved[0].appName isEqualToString:@"Editor"]);
    assert([preserved[1].appName isEqualToString:@"Terminal"]);
    assert([preserved[2].appName isEqualToString:@"Slack"]);

    printf("  [PASS] Existing order preserved when new window opens.\n");
}

static void testOrderPreservationOnResize() {
    printf("Running testOrderPreservationOnResize...\n");
    CascadeWindow *winA = makeMockWindow(@"Editor", 0, 0, 800, 600, 1);
    CascadeWindow *winB = makeMockWindow(@"Browser", 100, 100, 800, 600, 2);
    CascadeWindow *winC = makeMockWindow(@"Terminal", 200, 200, 800, 600, 3);

    NSArray<CascadeWindow *> *baseline = [CascadeEngine calculateLayoutForWindows:@[winA, winB, winC]
                                                                        orderMode:CascadeOrderModeMRU
                                                                            delta:40.0];

    // Event: Browser resized manually by user, bringing it to front
    CascadeWindow *winB_resized = makeMockWindow(@"Browser", 50, 50, 1200, 900, 1);
    CascadeWindow *winA_curr = makeMockWindow(@"Editor", 0, 0, 800, 600, 2);
    CascadeWindow *winC_curr = makeMockWindow(@"Terminal", 200, 200, 800, 600, 3);
    NSArray<CascadeWindow *> *currentWindows = @[winB_resized, winA_curr, winC_curr];

    NSArray<CascadeWindow *> *preserved = [CascadeEngine calculateLayoutForWindows:currentWindows
                                                              preservingOrderFrom:baseline
                                                                            delta:40.0];
    assert(preserved.count == 3);
    assert([preserved[0].appName isEqualToString:@"Editor"]);
    assert([preserved[1].appName isEqualToString:@"Browser"]);
    assert([preserved[2].appName isEqualToString:@"Terminal"]);

    // All windows must have uniform cascade dimensions
    assert(fabs(preserved[0].targetFrame.size.width - preserved[1].targetFrame.size.width) < 0.01);
    assert(fabs(preserved[1].targetFrame.size.width - preserved[2].targetFrame.size.width) < 0.01);

    printf("  [PASS] Order preserved on resize event.\n");
}

static void testPreferredAppOrderSorting() {
    printf("Running testPreferredAppOrderSorting...\n");
    CascadeWindow *wSlack = makeMockWindow(@"Slack", 0, 0, 800, 600, 1);
    CascadeWindow *wChrome1 = makeMockWindow(@"Google Chrome", 0, 0, 800, 600, 2);
    CascadeWindow *wChrome2 = makeMockWindow(@"Google Chrome", 0, 0, 800, 600, 4);
    CascadeWindow *wCursor = makeMockWindow(@"Cursor", 0, 0, 800, 600, 3);
    CascadeWindow *wTerminal = makeMockWindow(@"Terminal", 0, 0, 800, 600, 5);

    NSArray<NSString *> *preferred = @[@"Cursor", @"Chrome", @"Terminal"];
    NSArray<CascadeWindow *> *windows = @[wSlack, wChrome1, wChrome2, wCursor, wTerminal];

    NSArray<CascadeWindow *> *planned = [CascadeEngine calculateLayoutForWindows:windows
                                                                       orderMode:CascadeOrderModeCustom
                                                                  preferredOrder:preferred
                                                                           delta:40.0];
    assert(planned.count == 5);
    // 1. Cursor is rank 0
    assert([planned[0].appName isEqualToString:@"Cursor"]);
    // 2. Chrome is rank 1 (Chrome 1 has zRank 2, Chrome 2 has zRank 4)
    assert([planned[1].appName isEqualToString:@"Google Chrome"] && planned[1].zRank == 2);
    assert([planned[2].appName isEqualToString:@"Google Chrome"] && planned[2].zRank == 4);
    // 3. Terminal is rank 2
    assert([planned[3].appName isEqualToString:@"Terminal"]);
    // 4. Slack is unlisted, so placed last
    assert([planned[4].appName isEqualToString:@"Slack"]);

    printf("  [PASS] Preferred app order sorting verified with substring and tie-breakers.\n");
}

static void testPreferencesPersistence() {
    printf("Running testPreferencesPersistence...\n");

    // 1. Order mode
    [CascadeEngine saveOrderMode:CascadeOrderModeCustom];
    assert([CascadeEngine savedOrderMode] == CascadeOrderModeCustom);
    [CascadeEngine saveOrderMode:CascadeOrderModeSpatial];
    assert([CascadeEngine savedOrderMode] == CascadeOrderModeSpatial);

    // 2. Delta
    [CascadeEngine saveDelta:55.0];
    assert(fabs([CascadeEngine savedDelta] - 55.0) < 0.001);
    [CascadeEngine saveDelta:40.0];
    assert(fabs([CascadeEngine savedDelta] - 40.0) < 0.001);

    // 3. Restack Z-Order
    [CascadeEngine saveRestackZOrder:NO];
    assert([CascadeEngine savedRestackZOrder] == NO);
    [CascadeEngine saveRestackZOrder:YES];
    assert([CascadeEngine savedRestackZOrder] == YES);

    // 4. Auto-Rearrange
    [CascadeEngine saveAutoRearrange:YES];
    assert([CascadeEngine savedAutoRearrange] == YES);
    [CascadeEngine saveAutoRearrange:NO];
    assert([CascadeEngine savedAutoRearrange] == NO);

    // 5. Preferred App Order
    NSArray<NSString *> *order = @[@"Cursor", @"Terminal", @"Chrome"];
    [CascadeEngine setPreferredAppOrder:order];
    NSArray<NSString *> *retrieved = [CascadeEngine preferredAppOrder];
    assert(retrieved.count == 3);
    assert([retrieved[0] isEqualToString:@"Cursor"]);
    assert([retrieved[1] isEqualToString:@"Terminal"]);
    assert([retrieved[2] isEqualToString:@"Chrome"]);

    printf("  [PASS] All user preferences round-trip and persist via shared storage.\n");
}

static void testAccessibilityDiagnostics() {
    printf("Running testAccessibilityDiagnostics...\n");
    NSDictionary *diag = [CascadeEngine accessibilityDiagnostics];
    assert(diag != nil);
    assert(diag[@"apiTrusted"] != nil);
    assert(diag[@"functional"] != nil);
    assert(diag[@"errorCode"] != nil);
    assert(diag[@"trusted"] != nil);
    assert([diag[@"hostApp"] isKindOfClass:[NSString class]]);

    BOOL trusted = [CascadeEngine isAccessibilityTrustedWithPrompt:NO];
    assert(trusted == [diag[@"trusted"] boolValue]);

    printf("  [PASS] Active accessibility probe and diagnostics verified.\n");
}

int main(int argc, const char * argv[]) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        printf("=== Running Cascade Unit Tests ===\n\n");
        testTwoWindowLayout();
        testCascadeTabDisjointness();
        testSortingModes();
        testOrderPreservationOnWindowClose();
        testOrderPreservationOnNewWindow();
        testOrderPreservationOnResize();
        testPreferredAppOrderSorting();
        testPreferencesPersistence();
        testAccessibilityDiagnostics();
        printf("\n=== All Tests Passed Successfully! ===\n");
    }
    return 0;
}
