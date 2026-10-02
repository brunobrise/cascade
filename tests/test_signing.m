#import <Cocoa/Cocoa.h>
#import <assert.h>

static void testBundleSignatureIntegrity(void) {
    printf("Running testBundleSignatureIntegrity...\n");
    NSString *appPath = @"build/Cascade.app";
    NSFileManager *fm = [NSFileManager defaultManager];

    if (![fm fileExistsAtPath:appPath]) {
        appPath = [@"~/Applications/Cascade.app" stringByExpandingTildeInPath];
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

    // 2. Inspect designated requirement
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

    // Must be bound to com.brunobrise.cascade
    assert([drStr containsString:@"identifier \"com.brunobrise.cascade\""] || [drStr containsString:@"com.brunobrise.cascade"]);

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
