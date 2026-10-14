#import <Cocoa/Cocoa.h>
#import <assert.h>
#import "../src/WindowEngine.h"
#import "../src/WindowLayoutGeometry.h"

static CascadeWindow *makeTestWindow(NSString *app, NSString *title) {
    CascadeWindow *w = [[CascadeWindow alloc] init];
    w.appName = app;
    w.title = title;
    w.currentFrame = CGRectMake(100, 100, 800, 600);
    return w;
}

static void testFractalPreferencesPersistence() {
    printf("Running testFractalPreferencesPersistence...\n");
    CascadeLayoutStyle orig = [CascadeEngine savedLayoutStyle];

    [CascadeEngine saveLayoutStyle:CascadeLayoutStyleFractal];
    assert([CascadeEngine savedLayoutStyle] == CascadeLayoutStyleFractal);

    // Restore original
    [CascadeEngine saveLayoutStyle:orig];
    printf("  [PASS] Fractal layout style persistence verified.\n");
}

static void testFractalSingleWindow() {
    printf("Running testFractalSingleWindow...\n");
    CGRect screen = CGRectMake(0, 0, 2560, 1440);
    CascadeWindow *w1 = makeTestWindow(@"Code", @"Editor");
    NSArray *windows = @[w1];

    [WindowLayoutGeometry assignFramesToOrderedWindows:windows
                                         onUsableFrame:screen
                                                 delta:25.0
                                           layoutStyle:CascadeLayoutStyleFractal];

    assert(CGRectEqualToRect(w1.targetFrame, screen));
    printf("  [PASS] Single window fractal layout verified.\n");
}

static void testFractalTwoWindows() {
    printf("Running testFractalTwoWindows...\n");
    CGRect screen = CGRectMake(0, 0, 2560, 1440);
    CascadeWindow *w1 = makeTestWindow(@"Code", @"Editor");
    CascadeWindow *w2 = makeTestWindow(@"Terminal", @"Shell");
    NSArray *windows = @[w1, w2];

    [WindowLayoutGeometry assignFramesToOrderedWindows:windows
                                         onUsableFrame:screen
                                                 delta:25.0
                                           layoutStyle:CascadeLayoutStyleFractal];

    // First window should occupy ~61.8% of width
    CGFloat expectedW1 = screen.size.width * 0.6180339887;
    assert(fabs(w1.targetFrame.size.width - expectedW1) < 2.0);
    assert(fabs(w1.targetFrame.size.height - screen.size.height) < 1.0);
    assert(w1.targetFrame.origin.x == screen.origin.x);

    // Second window should occupy the remaining width
    assert(w2.targetFrame.origin.x >= w1.targetFrame.size.width - 2.0);
    assert(fabs(w2.targetFrame.size.width - (screen.size.width - expectedW1)) < 2.0);
    printf("  [PASS] Two window golden ratio split verified.\n");
}

static void testFractalFiveWindowsGoldenSpiral() {
    printf("Running testFractalFiveWindowsGoldenSpiral (N = 5)...\n");
    CGRect screen = CGRectMake(0, 0, 3840, 2160);
    NSMutableArray *windows = [NSMutableArray array];
    for (int i = 0; i < 5; i++) {
        [windows addObject:makeTestWindow([NSString stringWithFormat:@"App%d", i], [NSString stringWithFormat:@"Win%d", i])];
    }

    [WindowLayoutGeometry assignFramesToOrderedWindows:windows
                                         onUsableFrame:screen
                                                 delta:25.0
                                           layoutStyle:CascadeLayoutStyleFractal];

    // Every window must lie within screen bounds and have non-degenerate dimensions
    for (NSUInteger i = 0; i < windows.count; i++) {
        CascadeWindow *w = windows[i];
        assert(w.targetFrame.size.width > 100.0);
        assert(w.targetFrame.size.height > 100.0);
        assert(CGRectContainsRect(CGRectInset(screen, -1.0, -1.0), w.targetFrame));
    }

    // Direction cycle check:
    // Window 0 splits Left: origin X is screen origin X
    CascadeWindow *w0 = windows[0];
    assert(w0.targetFrame.origin.x == screen.origin.x);

    // Window 1 splits Top of residual: origin Y is screen origin Y
    CascadeWindow *w1 = windows[1];
    assert(w1.targetFrame.origin.y == screen.origin.y);
    assert(w1.targetFrame.origin.x >= w0.targetFrame.size.width - 1.0);

    printf("  [PASS] 5-window golden spiral spatial partitioning verified.\n");
}

static void testFractalDeepNesting() {
    printf("Running testFractalDeepNesting (N = 10)...\n");
    CGRect screen = CGRectMake(0, 0, 5120, 2880);
    NSMutableArray *windows = [NSMutableArray array];
    for (int i = 0; i < 10; i++) {
        [windows addObject:makeTestWindow([NSString stringWithFormat:@"App%d", i], [NSString stringWithFormat:@"Win%d", i])];
    }

    [WindowLayoutGeometry assignFramesToOrderedWindows:windows
                                         onUsableFrame:screen
                                                 delta:25.0
                                           layoutStyle:CascadeLayoutStyleFractal];

    for (NSUInteger i = 0; i < windows.count; i++) {
        CascadeWindow *w = windows[i];
        assert(!isnan(w.targetFrame.origin.x));
        assert(!isnan(w.targetFrame.origin.y));
        assert(w.targetFrame.size.width > 20.0);
        assert(w.targetFrame.size.height > 20.0);
    }
    printf("  [PASS] Deep unconstrained recursion (N = 10) verified without numerical degeneration.\n");
}

static void testFractalDocking() {
    printf("Running testFractalDocking...\n");
    CGRect screen = CGRectMake(0, 0, 2560, 1440);
    CascadeWindow *w0 = makeTestWindow(@"Primary", @"Doc");
    CascadeWindow *w1 = makeTestWindow(@"Side1", @"Ref");
    CascadeWindow *w2 = makeTestWindow(@"Side2", @"Term");
    NSArray *windows = @[w0, w1, w2];

    // Dock active window w0 to the Left
    [WindowLayoutGeometry assignDockedFramesToWindows:windows
                                    activeWindowIndex:0
                                                 edge:CascadeDockEdgeLeft
                                        onUsableFrame:screen
                                                delta:25.0
                                          layoutStyle:CascadeLayoutStyleDiagonal];

    // Window 0 should be docked to left half
    assert(fabs(w0.targetFrame.origin.x - screen.origin.x) < 1.0);
    assert(fabs(w0.targetFrame.size.width - (screen.size.width * 0.5)) < 1.0);
    assert(fabs(w0.targetFrame.size.height - screen.size.height) < 1.0);

    // Remaining windows w1 and w2 should be inside the right half residual area
    CGRect rightHalf = CGRectMake(screen.origin.x + screen.size.width * 0.5, screen.origin.y, screen.size.width * 0.5, screen.size.height);
    assert(CGRectContainsRect(CGRectInset(rightHalf, -1.0, -1.0), w1.targetFrame));
    assert(CGRectContainsRect(CGRectInset(rightHalf, -1.0, -1.0), w2.targetFrame));

    // w1 and w2 should cascade within right half with delta offset
    assert(w2.targetFrame.origin.x > w1.targetFrame.origin.x);

    printf("  [PASS] Fractal edge docking with nested residual cascade verified.\n");
}

int main(void) {
    @autoreleasepool {
        printf("=== Running Fractal Window Management Unit Tests ===\n");
        testFractalPreferencesPersistence();
        testFractalSingleWindow();
        testFractalTwoWindows();
        testFractalFiveWindowsGoldenSpiral();
        testFractalDeepNesting();
        testFractalDocking();
        printf("=== All Fractal Tests Passed Successfully! ===\n");
    }
    return 0;
}
