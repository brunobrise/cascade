#import <Foundation/Foundation.h>
#import <assert.h>
#import "../src/UpdateChecker.h"

static void testSemVerComparison() {
    printf("Running testSemVerComparison...\n");

    // Equal versions
    assert([UpdateChecker compareVersion:@"0.23.4" withVersion:@"0.23.4"] == NSOrderedSame);
    assert([UpdateChecker compareVersion:@"v0.23.4" withVersion:@"0.23.4"] == NSOrderedSame);
    assert([UpdateChecker compareVersion:@"0.23.4" withVersion:@"v0.23.4"] == NSOrderedSame);
    assert(![UpdateChecker isVersion:@"0.23.4" newerThan:@"0.23.4"]);

    // Patch increment
    assert([UpdateChecker compareVersion:@"0.23.5" withVersion:@"0.23.4"] == NSOrderedDescending);
    assert([UpdateChecker isVersion:@"0.23.5" newerThan:@"0.23.4"]);
    assert(![UpdateChecker isVersion:@"0.23.4" newerThan:@"0.23.5"]);

    // Minor increment
    assert([UpdateChecker compareVersion:@"0.24.0" withVersion:@"0.23.4"] == NSOrderedDescending);
    assert([UpdateChecker isVersion:@"0.24.0" newerThan:@"0.23.4"]);

    // Major increment
    assert([UpdateChecker compareVersion:@"1.0.0" withVersion:@"0.23.4"] == NSOrderedDescending);
    assert([UpdateChecker isVersion:@"1.0.0" newerThan:@"0.23.4"]);

    // Critical ASCII string sorting edge case: 0.23.10 vs 0.23.4
    // In ASCII string comparison, "0.23.10" < "0.23.4" because '1' < '4'.
    // In SemVer numeric comparison, 0.23.10 is strictly greater than 0.23.4!
    assert([UpdateChecker compareVersion:@"0.23.10" withVersion:@"0.23.4"] == NSOrderedDescending);
    assert([UpdateChecker isVersion:@"0.23.10" newerThan:@"0.23.4"]);
    assert(![UpdateChecker isVersion:@"0.23.4" newerThan:@"0.23.10"]);

    // With leading 'v'
    assert([UpdateChecker isVersion:@"v0.24.0" newerThan:@"0.23.4"]);
    assert([UpdateChecker isVersion:@"0.24.0" newerThan:@"v0.23.4"]);

    printf("  [PASS] SemVer integer comparison verified.\n");
}

static void testCachePersistence() {
    printf("Running testCachePersistence...\n");

    NSString *tmpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"cascade_test_update_%u.json", arc4random()]];
    [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:nil];

    CascadeUpdateState *state = [[CascadeUpdateState alloc] init];
    state.latestVersion = @"0.24.0";
    state.releaseURL = @"https://github.com/brunobrise/cascade/releases/tag/v0.24.0";
    state.lastCheckedTimestamp = 1728633600.0;
    state.lastNotifiedTimestamp = 1728634000.0;
    state.skippedVersion = @"0.23.9";

    BOOL saved = [UpdateChecker saveState:state toPath:tmpPath];
    assert(saved);
    assert([[NSFileManager defaultManager] fileExistsAtPath:tmpPath]);

    CascadeUpdateState *loaded = [UpdateChecker loadStateFromPath:tmpPath];
    assert(loaded != nil);
    assert([loaded.latestVersion isEqualToString:@"0.24.0"]);
    assert([loaded.releaseURL isEqualToString:@"https://github.com/brunobrise/cascade/releases/tag/v0.24.0"]);
    assert(fabs(loaded.lastCheckedTimestamp - 1728633600.0) < 0.01);
    assert(fabs(loaded.lastNotifiedTimestamp - 1728634000.0) < 0.01);
    assert([loaded.skippedVersion isEqualToString:@"0.23.9"]);

    [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:nil];
    printf("  [PASS] Cache state round-trip verified.\n");
}

static void testTTLAndThrottling() {
    printf("Running testTTLAndThrottling...\n");

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];

    // Fresh cache (< 24h)
    CascadeUpdateState *freshState = [[CascadeUpdateState alloc] init];
    freshState.latestVersion = @"0.24.0";
    freshState.lastCheckedTimestamp = now - 3600.0; // 1 hour ago
    assert(![UpdateChecker isCacheStale:freshState interval:86400.0]);

    // Stale cache (>= 24h)
    CascadeUpdateState *staleState = [[CascadeUpdateState alloc] init];
    staleState.latestVersion = @"0.24.0";
    staleState.lastCheckedTimestamp = now - 90000.0; // 25 hours ago
    assert([UpdateChecker isCacheStale:staleState interval:86400.0]);
    assert([UpdateChecker isCacheStale:nil interval:86400.0]);

    // Notification throttle
    CascadeUpdateState *notifyState = [[CascadeUpdateState alloc] init];
    notifyState.latestVersion = @"0.24.0";
    notifyState.lastNotifiedTimestamp = 0; // Never notified
    assert([UpdateChecker shouldNotifyForState:notifyState currentVersion:@"0.23.4" throttleInterval:86400.0]);

    // Recently notified (10 minutes ago)
    notifyState.lastNotifiedTimestamp = now - 600.0;
    assert(![UpdateChecker shouldNotifyForState:notifyState currentVersion:@"0.23.4" throttleInterval:86400.0]);

    // Notification after 25 hours
    notifyState.lastNotifiedTimestamp = now - 90000.0;
    assert([UpdateChecker shouldNotifyForState:notifyState currentVersion:@"0.23.4" throttleInterval:86400.0]);

    // Skipped version
    notifyState.lastNotifiedTimestamp = 0;
    notifyState.skippedVersion = @"0.24.0";
    assert(![UpdateChecker shouldNotifyForState:notifyState currentVersion:@"0.23.4" throttleInterval:86400.0]);

    // Already on latest version
    notifyState.skippedVersion = nil;
    assert(![UpdateChecker shouldNotifyForState:notifyState currentVersion:@"0.24.0" throttleInterval:86400.0]);

    printf("  [PASS] TTL and throttling logic verified.\n");
}

static void testInstallOriginDetection() {
    printf("Running testInstallOriginDetection...\n");

    CascadeInstallOrigin brewArm = [UpdateChecker detectInstallOriginForPath:@"/opt/homebrew/bin/cascade"];
    assert(brewArm == CascadeInstallOriginHomebrew);
    assert([[UpdateChecker upgradeCommandForOrigin:brewArm] containsString:@"brew upgrade cascade"]);

    CascadeInstallOrigin brewIntel = [UpdateChecker detectInstallOriginForPath:@"/usr/local/Cellar/cascade/0.23.4/bin/cascade"];
    assert(brewIntel == CascadeInstallOriginHomebrew);

    CascadeInstallOrigin source = [UpdateChecker detectInstallOriginForPath:@"/Users/chainsona/Code/cascade/build/cascade"];
    assert(source == CascadeInstallOriginSource);
    assert([[UpdateChecker upgradeCommandForOrigin:source] containsString:@"make install"]);

    CascadeInstallOrigin localBin = [UpdateChecker detectInstallOriginForPath:@"/Users/chainsona/.local/bin/cascade"];
    assert(localBin == CascadeInstallOriginInstalled);
    assert([[UpdateChecker upgradeCommandForOrigin:localBin] containsString:@"install.sh"]);

    printf("  [PASS] Install origin detection verified.\n");
}

static void testGhCliDetection() {
    printf("Running testGhCliDetection...\n");
    NSString *gh = [UpdateChecker findGhExecutable];
    if ([[NSFileManager defaultManager] isExecutableFileAtPath:@"/opt/homebrew/bin/gh"]) {
        assert([gh isEqualToString:@"/opt/homebrew/bin/gh"]);
    } else if ([[NSFileManager defaultManager] isExecutableFileAtPath:@"/usr/local/bin/gh"]) {
        assert([gh isEqualToString:@"/usr/local/bin/gh"]);
    }
    printf("  [PASS] gh CLI detection verified: %s\n", gh ? [gh UTF8String] : "none");
}

static void testUpdateAssetURLs() {
    printf("Running testUpdateAssetURLs...\n");
    NSString *dmgURL = [UpdateChecker downloadURLForVersion:@"0.25.1" assetName:@"Cascade-v0.25.1-Universal.dmg"];
    assert([dmgURL isEqualToString:@"https://github.com/brunobrise/cascade/releases/download/v0.25.1/Cascade-v0.25.1-Universal.dmg"]);

    NSString *dmgName = [UpdateChecker universalDmgAssetNameForVersion:@"0.25.1"];
    assert([dmgName isEqualToString:@"Cascade-v0.25.1-Universal.dmg"]);

    NSString *cliTarball = [UpdateChecker cliTarballAssetNameForVersion:@"0.25.1" arch:@"arm64"];
    assert([cliTarball isEqualToString:@"cascade-v0.25.1-darwin-arm64.tar.gz"]);
    printf("  [PASS] Update asset URL formatting verified.\n");
}

static void testUpdateSwapScript() {
    printf("Running testUpdateSwapScript...\n");
    NSString *script = [UpdateChecker generateSwapScriptWithOldPID:12345
                                                        targetPath:@"/Applications/Cascade.app"
                                                         mountPath:@"/tmp/cascade-mount-test"
                                                   signingIdentity:@"Cascade Code Signing"
                                                           tempDir:@"/tmp/cascade-test"];
    assert(script != nil);
    assert([script containsString:@"OLD_PID=12345"]);
    assert([script containsString:@"kill -0 \"$OLD_PID\""]);
    assert([script containsString:@"TARGET=\"/Applications/Cascade.app\""]);
    assert([script containsString:@"BACKUP=\"${TARGET}.old\""]);
    assert([script containsString:@"Cascade Code Signing"]);
    assert([script containsString:@"xattr -cr"]);
    assert([script containsString:@"hdiutil detach"]);
    assert([script containsString:@"open \"$TARGET\""]);
    printf("  [PASS] Atomic swap script structure verified.\n");
}

int main(void) {
    @autoreleasepool {
        printf("=== Running UpdateChecker Unit Tests ===\n");
        testSemVerComparison();
        testCachePersistence();
        testTTLAndThrottling();
        testInstallOriginDetection();
        testGhCliDetection();
        testUpdateAssetURLs();
        testUpdateSwapScript();
        printf("=== All UpdateChecker Tests Passed Successfully! ===\n");
    }
    return 0;
}
