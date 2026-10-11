#import <Cocoa/Cocoa.h>
#import <assert.h>

static void testBundleSignatureIntegrity(void) {
    printf("Running testBundleSignatureIntegrity...\n");
    NSString *appPath = @"build/Cascade.app";
    NSFileManager *fm = [NSFileManager defaultManager];

    if (![fm fileExistsAtPath:appPath]) {
        appPath = [@"~/Applications/Cascade.app" stringByExpandingTildeInPath];
    }
    if (![fm fileExistsAtPath:appPath]) {
        (void)system("make build >/dev/null 2>&1");
        appPath = @"build/Cascade.app";
    }
    assert([fm fileExistsAtPath:appPath]);

    // 1. Verify bundle validity using codesign -v
    NSTask *verifyTask = [[NSTask alloc] init];
    verifyTask.launchPath = @"/usr/bin/codesign";
    verifyTask.arguments = @[@"-v", @"--deep", @"--strict", appPath];
    NSPipe *verifyErr = [NSPipe pipe];
    verifyTask.standardError = verifyErr;
    [verifyTask launch];
    [verifyTask waitUntilExit];
    assert(verifyTask.terminationStatus == 0);

    // 2. Inspect bundle identifier via codesign -d -v
    NSTask *infoTask = [[NSTask alloc] init];
    infoTask.launchPath = @"/usr/bin/codesign";
    infoTask.arguments = @[@"-d", @"-v", appPath];
    NSPipe *infoErr = [NSPipe pipe];
    infoTask.standardError = infoErr;
    [infoTask launch];
    [infoTask waitUntilExit];
    assert(infoTask.terminationStatus == 0);

    NSData *infoData = [[infoErr fileHandleForReading] readDataToEndOfFile];
    NSString *infoStr = [[NSString alloc] initWithData:infoData encoding:NSUTF8StringEncoding];
    assert([infoStr containsString:@"Identifier=com.brunobrise.cascade"]);

    // 3. Inspect designated requirement
    NSTask *drTask = [[NSTask alloc] init];
    drTask.launchPath = @"/usr/bin/codesign";
    drTask.arguments = @[@"-d", @"-r-", appPath];
    NSPipe *drOut = [NSPipe pipe];
    drTask.standardOutput = drOut;
    drTask.standardError = [NSPipe pipe];
    [drTask launch];
    [drTask waitUntilExit];
    assert(drTask.terminationStatus == 0);

    NSData *drData = [[drOut fileHandleForReading] readDataToEndOfFile];
    NSString *drStr = [[NSString alloc] initWithData:drData encoding:NSUTF8StringEncoding];

    // Must be bound to com.brunobrise.cascade or ad-hoc cdhash
    assert([drStr containsString:@"com.brunobrise.cascade"] || [drStr containsString:@"designated => cdhash"]);

    printf("  Designated Requirement: %s\n", [drStr UTF8String]);
    printf("  [PASS] testBundleSignatureIntegrity passed.\n");
}

static void testPersistentIdentityRequirement(void) {
    printf("Running testPersistentIdentityRequirement...\n");
    NSString *appPath = @"build/Cascade.app";
    NSTask *drTask = [[NSTask alloc] init];
    drTask.launchPath = @"/usr/bin/codesign";
    drTask.arguments = @[@"-d", @"-r-", appPath];
    NSPipe *drOut = [NSPipe pipe];
    drTask.standardOutput = drOut;
    drTask.standardError = [NSPipe pipe];
    [drTask launch];
    [drTask waitUntilExit];
    assert(drTask.terminationStatus == 0);

    NSData *drData = [[drOut fileHandleForReading] readDataToEndOfFile];
    NSString *drStr = [[NSString alloc] initWithData:drData encoding:NSUTF8StringEncoding];

    char *ciEnv = getenv("CI");
    if (!ciEnv) ciEnv = getenv("GITHUB_ACTIONS");
    if (ciEnv && (strcmp(ciEnv, "true") == 0 || strcmp(ciEnv, "1") == 0)) {
        printf("  [SKIP] CI environment active (builds signed ad-hoc on ephemeral runners).\n");
        return;
    }

    // Check if system has a persistent identity available
    NSTask *idTask = [[NSTask alloc] init];
    idTask.launchPath = @"/usr/bin/security";
    idTask.arguments = @[@"find-identity", @"-v", @"-p", @"codesigning"];
    NSPipe *idOut = [NSPipe pipe];
    idTask.standardOutput = idOut;
    [idTask launch];
    [idTask waitUntilExit];
    NSData *idData = [[idOut fileHandleForReading] readDataToEndOfFile];
    NSString *idStr = [[NSString alloc] initWithData:idData encoding:NSUTF8StringEncoding];

    if ([idStr containsString:@"Cascade Code Signing"] || [idStr containsString:@"Apple Development"]) {
        // Must NOT be ad-hoc cdhash! Must be anchored to certificate root or leaf
        assert(![drStr containsString:@"designated => cdhash"]);
        assert([drStr containsString:@"certificate root"] || [drStr containsString:@"certificate leaf"] || [drStr containsString:@"anchor apple generic"]);
        printf("  [PASS] Confirmed persistent identity requirement anchor (NO cdhash).\n");
    } else {
        printf("  [SKIP] No persistent identity installed in keychain (CI or sandbox environment).\n");
    }
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        (void)argc; (void)argv;
        printf("=== Running Cascade Code Signing Verification Tests ===\n\n");
        testBundleSignatureIntegrity();
        testPersistentIdentityRequirement();
        printf("\n=== All Code Signing Tests Passed Successfully! ===\n");
    }
    return 0;
}
