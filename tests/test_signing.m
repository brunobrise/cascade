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

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        (void)argc; (void)argv;
        printf("=== Running Cascade Code Signing Verification Tests ===\n\n");
        testBundleSignatureIntegrity();
        printf("\n=== All Code Signing Tests Passed Successfully! ===\n");
    }
    return 0;
}
