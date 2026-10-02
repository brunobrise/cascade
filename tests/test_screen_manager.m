#import <Foundation/Foundation.h>
#import <assert.h>
#import "../src/ScreenManager.h"

static void testCoordinateConversion() {
    printf("Running testCoordinateConversion...\n");
    CGFloat h0 = 1440.0;

    // 1. Primary screen (5120x1440 at origin 0,0)
    CGRect cocoaP = CGRectMake(0, 0, 5120, 1440);
    CGRect quartzP = [ScreenManager convertCocoaFrameToQuartz:cocoaP primaryScreenHeight:h0];
    assert(quartzP.origin.x == 0.0 && quartzP.origin.y == 0.0);
    assert(quartzP.size.width == 5120.0 && quartzP.size.height == 1440.0);

    // Visible frame with 30px menu bar at top (Cocoa height 1410, origin 0,0)
    CGRect cocoaPVis = CGRectMake(0, 0, 5120, 1410);
    CGRect quartzPVis = [ScreenManager convertCocoaFrameToQuartz:cocoaPVis primaryScreenHeight:h0];
    assert(quartzPVis.origin.x == 0.0 && quartzPVis.origin.y == 30.0);
    assert(quartzPVis.size.width == 5120.0 && quartzPVis.size.height == 1410.0);

    // 2. Secondary screen below (1800x1169 at 2646, -1169)
    CGRect cocoaS = CGRectMake(2646, -1169, 1800, 1169);
    CGRect quartzS = [ScreenManager convertCocoaFrameToQuartz:cocoaS primaryScreenHeight:h0];
    assert(quartzS.origin.x == 2646.0 && quartzS.origin.y == 1440.0);
    assert(quartzS.size.width == 1800.0 && quartzS.size.height == 1169.0);

    // Visible frame with 38px menu bar on secondary screen
    CGRect cocoaSVis = CGRectMake(2646, -1169, 1800, 1131);
    CGRect quartzSVis = [ScreenManager convertCocoaFrameToQuartz:cocoaSVis primaryScreenHeight:h0];
    assert(quartzSVis.origin.x == 2646.0 && quartzSVis.origin.y == 1478.0);
    assert(quartzSVis.size.width == 1800.0 && quartzSVis.size.height == 1131.0);

    // 3. Secondary screen to the left (-1920, 0, 1920, 1080)
    CGRect cocoaL = CGRectMake(-1920, 0, 1920, 1080);
    CGRect quartzL = [ScreenManager convertCocoaFrameToQuartz:cocoaL primaryScreenHeight:h0];
    assert(quartzL.origin.x == -1920.0 && quartzL.origin.y == 360.0);

    // 4. Secondary screen above (0, 1440, 2560, 1440)
    CGRect cocoaA = CGRectMake(0, 1440, 2560, 1440);
    CGRect quartzA = [ScreenManager convertCocoaFrameToQuartz:cocoaA primaryScreenHeight:h0];
    assert(quartzA.origin.x == 0.0 && quartzA.origin.y == -1440.0);

    printf("  [PASS] Mathematical coordinate inversion verified across 4 screen arrangements.\n");
}

static void testWindowToScreenAssignment() {
    printf("Running testWindowToScreenAssignment...\n");

    CascadeScreen *s0 = [[CascadeScreen alloc] init];
    s0.index = 0;
    s0.name = @"Ultrawide";
    s0.isPrimary = YES;
    s0.quartzFrame = CGRectMake(0, 0, 5120, 1440);
    s0.quartzVisibleFrame = CGRectMake(0, 30, 5120, 1410);

    CascadeScreen *s1 = [[CascadeScreen alloc] init];
    s1.index = 1;
    s1.name = @"Retina";
    s1.isPrimary = NO;
    s1.quartzFrame = CGRectMake(2646, 1440, 1800, 1169);
    s1.quartzVisibleFrame = CGRectMake(2646, 1478, 1800, 1131);

    NSArray<CascadeScreen *> *screens = @[s0, s1];

    // Window A: purely on Ultrawide
    CGRect winA = CGRectMake(100, 100, 1000, 800);
    CascadeScreen *matchA = [ScreenManager screenForFrame:winA inScreens:screens];
    assert(matchA == s0);

    // Window B: purely on Retina
    CGRect winB = CGRectMake(2700, 1500, 1000, 800);
    CascadeScreen *matchB = [ScreenManager screenForFrame:winB inScreens:screens];
    assert(matchB == s1);

    // Window C: overlapping boundary, 80% on Ultrawide, 20% on Retina
    // Ultrawide bottom is Y=1440, Retina top is Y=1440
    // Window C: Y=1040, H=500. Span [1040, 1440] on s0 (400px), [1440, 1540] on s1 (100px)
    CGRect winC = CGRectMake(3000, 1040, 800, 500);
    CascadeScreen *matchC = [ScreenManager screenForFrame:winC inScreens:screens];
    assert(matchC == s0);

    // Window D: overlapping boundary, 20% on Ultrawide, 80% on Retina
    CGRect winD = CGRectMake(3000, 1340, 800, 500);
    CascadeScreen *matchD = [ScreenManager screenForFrame:winD inScreens:screens];
    assert(matchD == s1);

    printf("  [PASS] Window-to-screen assignment by maximum intersection area verified.\n");
}

static void testTargetMatching() {
    printf("Running testTargetMatching...\n");

    CascadeScreen *s0 = [[CascadeScreen alloc] init];
    s0.index = 0;
    s0.name = @"C49RG9x";
    s0.isPrimary = YES;

    CascadeScreen *s1 = [[CascadeScreen alloc] init];
    s1.index = 1;
    s1.name = @"Built-in Retina Display";
    s1.isPrimary = NO;

    NSArray<CascadeScreen *> *screens = @[s0, s1];

    // 1. All screens
    NSArray *all = [ScreenManager screensMatchingTarget:@"all" inScreens:screens];
    assert(all.count == 2);

    // 2. Specific by name
    NSArray *matchName = [ScreenManager screensMatchingTarget:@"C49RG9x" inScreens:screens];
    assert(matchName.count == 1 && matchName[0] == s0);

    NSArray *matchRetina = [ScreenManager screensMatchingTarget:@"Built-in Retina Display" inScreens:screens];
    assert(matchRetina.count == 1 && matchRetina[0] == s1);

    // 3. Specific by index
    NSArray *matchIdx0 = [ScreenManager screensMatchingTarget:@"0" inScreens:screens];
    assert(matchIdx0.count == 1 && matchIdx0[0] == s0);

    NSArray *matchIdx1 = [ScreenManager screensMatchingTarget:@"1" inScreens:screens];
    assert(matchIdx1.count == 1 && matchIdx1[0] == s1);

    // 4. Primary and Main aliases
    NSArray *matchPrim = [ScreenManager screensMatchingTarget:@"primary" inScreens:screens];
    assert(matchPrim.count == 1 && matchPrim[0] == s0);
    NSArray *matchMain = [ScreenManager screensMatchingTarget:@"main" inScreens:screens];
    assert(matchMain.count == 1 && matchMain[0] == s0);

    // 5. Fallback on invalid
    NSArray *matchInvalid = [ScreenManager screensMatchingTarget:@"Nonexistent Display" inScreens:screens];
    assert(matchInvalid.count == 1 && matchInvalid[0] == s0);

    // Legacy "active" target gracefully falls back to all screens
    NSArray *matchActive = [ScreenManager screensMatchingTarget:@"active" inScreens:screens];
    assert(matchActive.count == 2);

    // Display ID matching
    s0.displayID = @"69734123";
    NSArray *matchID = [ScreenManager screensMatchingTarget:@"69734123" inScreens:screens];
    assert(matchID.count == 1 && matchID[0] == s0);

    printf("  [PASS] Screen target selection and fallback resolution verified.\n");
}

static void testPointerScreenDetection() {
    printf("Running testPointerScreenDetection...\n");

    CascadeScreen *s0 = [[CascadeScreen alloc] init];
    s0.index = 0;
    s0.name = @"Ultrawide";
    s0.isPrimary = YES;
    s0.cocoaFrame = CGRectMake(0, 0, 5120, 1440);
    s0.quartzFrame = CGRectMake(0, 0, 5120, 1440);

    CascadeScreen *s1 = [[CascadeScreen alloc] init];
    s1.index = 1;
    s1.name = @"Retina";
    s1.isPrimary = NO;
    s1.cocoaFrame = CGRectMake(2646, -1169, 1800, 1169);
    s1.quartzFrame = CGRectMake(2646, 1440, 1800, 1169);

    NSArray<CascadeScreen *> *screens = @[s0, s1];

    // 1. Point on Ultrawide screen
    NSPoint p0 = NSMakePoint(500, 500);
    CascadeScreen *match0 = [ScreenManager screenForCocoaPoint:p0 inScreens:screens];
    assert(match0 == s0);

    // 2. Point on Retina screen
    NSPoint p1 = NSMakePoint(3000, -500);
    CascadeScreen *match1 = [ScreenManager screenForCocoaPoint:p1 inScreens:screens];
    assert(match1 == s1);

    // 3. Fallback on outside coordinate: closest screen center
    NSPoint pOutside = NSMakePoint(3000, -2000); // Closest to s1
    CascadeScreen *matchOutside = [ScreenManager screenForCocoaPoint:pOutside inScreens:screens];
    assert(matchOutside == s1);

    // 4. Live pointer screen query returns a valid screen
    CascadeScreen *livePtr = [ScreenManager screenForPointer];
    assert(livePtr != nil);

    printf("  [PASS] Screen for pointer detection verified across multi-display coordinates.\n");
}

static void testPreferencesRoundTrip() {
    printf("Running testPreferencesRoundTrip...\n");
    NSString *orig = [ScreenManager savedScreenTarget];

    NSUserDefaults *suiteDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.brunobrise.cascade"];
    assert(suiteDefaults != nil);

    [ScreenManager saveScreenTarget:@"C49RG9x"];
    assert([[ScreenManager savedScreenTarget] isEqualToString:@"C49RG9x"]);
    assert([[suiteDefaults stringForKey:@"screenTarget"] isEqualToString:@"C49RG9x"]);

    [ScreenManager saveScreenTarget:@"Built-in Retina Display"];
    assert([[ScreenManager savedScreenTarget] isEqualToString:@"Built-in Retina Display"]);
    assert([[suiteDefaults stringForKey:@"screenTarget"] isEqualToString:@"Built-in Retina Display"]);

    [ScreenManager saveScreenTarget:@"all"];
    assert([[ScreenManager savedScreenTarget] isEqualToString:@"all"]);
    assert([[suiteDefaults stringForKey:@"screenTarget"] isEqualToString:@"all"]);

    [ScreenManager saveScreenTarget:nil];
    assert([[ScreenManager savedScreenTarget] isEqualToString:@"all"]);

    // Direct suite defaults modification (e.g. from CLI or external tool)
    [suiteDefaults setObject:@"ExternalDisplay" forKey:@"screenTarget"];
    [suiteDefaults synchronize];
    assert([[ScreenManager savedScreenTarget] isEqualToString:@"ExternalDisplay"]);

    [ScreenManager saveScreenTarget:orig];
    printf("  [PASS] Screen target preference saved and restored cleanly across suite defaults.\n");
}

static void testScreenEquality() {
    printf("Running testScreenEquality...\n");
    CascadeScreen *s1 = [[CascadeScreen alloc] init];
    s1.index = 0;
    s1.name = @"Display A";
    s1.displayID = @"12345";

    CascadeScreen *s2 = [[CascadeScreen alloc] init];
    s2.index = 0;
    s2.name = @"Display A (Duplicate)";
    s2.displayID = @"12345";

    CascadeScreen *s3 = [[CascadeScreen alloc] init];
    s3.index = 1;
    s3.name = @"Display B";
    s3.displayID = @"67890";

    assert([s1 isEqual:s2]);
    assert(![s1 isEqual:s3]);
    assert([s1 hash] == [s2 hash]);

    printf("  [PASS] CascadeScreen equality and hashing verified.\n");
}

int main(int argc, const char * argv[]) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        printf("=== Running ScreenManager Unit Tests ===\n\n");
        testCoordinateConversion();
        testWindowToScreenAssignment();
        testTargetMatching();
        testPointerScreenDetection();
        testScreenEquality();
        testPreferencesRoundTrip();
        printf("\n=== All ScreenManager Tests Passed Successfully! ===\n");
    }
    return 0;
}
