#import <Cocoa/Cocoa.h>
#import <assert.h>
#import "../src/AppOrderWindowController.h"
#import "../src/WindowEngine.h"

int main(int argc, const char * argv[]) {
    (void)argc; (void)argv;
    @autoreleasepool {
        printf("Running AppOrderWindowController tests...\n");

        AppOrderWindowController *ctrl = [AppOrderWindowController sharedController];
        assert(ctrl != nil);
        printf("  [PASS] AppOrderWindowController singleton initialized.\n");

        NSArray<NSString *> *original = [CascadeEngine preferredAppOrder];

        // Test setting preferred order
        NSArray<NSString *> *testOrder = @[@"Cursor", @"Google Chrome", @"Terminal"];
        [CascadeEngine setPreferredAppOrder:testOrder];
        NSArray<NSString *> *retrieved = [CascadeEngine preferredAppOrder];
        assert(retrieved.count == 3);
        assert([retrieved[0] isEqualToString:@"Cursor"]);
        assert([retrieved[1] isEqualToString:@"Google Chrome"]);
        assert([retrieved[2] isEqualToString:@"Terminal"]);
        printf("  [PASS] Preferred app order matches expected sequence.\n");

        // Restore original
        [CascadeEngine setPreferredAppOrder:original];

        printf("=== AppOrderWindowController Tests Passed! ===\n");
    }
    return 0;
}
