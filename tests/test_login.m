#import <Foundation/Foundation.h>
#import <assert.h>
#import "../src/LoginItemManager.h"

int main(int argc, const char * argv[]) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        printf("Running LoginItemManager tests...\n");

        BOOL originalState = [LoginItemManager isStartAtLoginEnabled];
        printf("  Initial state: %s\n", originalState ? "ENABLED" : "DISABLED");

        // 1. Test enabling
        NSError *err = nil;
        BOOL ok = [LoginItemManager setStartAtLoginEnabled:YES error:&err];
        assert(ok);
        assert([LoginItemManager isStartAtLoginEnabled]);
        printf("  [PASS] Successfully enabled start-at-login.\n");

        // 2. Test disabling
        ok = [LoginItemManager setStartAtLoginEnabled:NO error:&err];
        assert(ok);
        assert(![LoginItemManager isStartAtLoginEnabled]);
        printf("  [PASS] Successfully disabled start-at-login.\n");

        // 3. Restore original state
        if (originalState) {
            [LoginItemManager setStartAtLoginEnabled:YES error:nil];
        }

        printf("=== LoginItemManager Tests Passed! ===\n");
    }
    return 0;
}
