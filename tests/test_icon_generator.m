#import <Cocoa/Cocoa.h>
#import <assert.h>

static void testIconSetIntegrity(void) {
    printf("Running testIconSetIntegrity...\n");
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *iconsetPath = @"resources/AppIcon.iconset";

    BOOL isDir = NO;
    assert([fm fileExistsAtPath:iconsetPath isDirectory:&isDir] && isDir);

    struct ExpectedIcon {
        const char *filename;
        NSInteger expectedWidth;
        NSInteger expectedHeight;
    } specs[] = {
        {"icon_16x16.png", 16, 16},
        {"icon_16x16@2x.png", 32, 32},
        {"icon_32x32.png", 32, 32},
        {"icon_32x32@2x.png", 64, 64},
        {"icon_128x128.png", 128, 128},
        {"icon_128x128@2x.png", 256, 256},
        {"icon_256x256.png", 256, 256},
        {"icon_256x256@2x.png", 512, 512},
        {"icon_512x512.png", 512, 512},
        {"icon_512x512@2x.png", 1024, 1024},
        {NULL, 0, 0}
    };

    for (int i = 0; specs[i].filename != NULL; i++) {
        NSString *filePath = [iconsetPath stringByAppendingPathComponent:[NSString stringWithUTF8String:specs[i].filename]];
        assert([fm fileExistsAtPath:filePath]);

        NSImage *img = [[NSImage alloc] initWithContentsOfFile:filePath];
        assert(img != nil);

        NSBitmapImageRep *rep = (NSBitmapImageRep *)[[img representations] firstObject];
        assert(rep != nil);
        assert([rep pixelsWide] == specs[i].expectedWidth);
        assert([rep pixelsHigh] == specs[i].expectedHeight);
    }

    // Verify master .icns
    NSString *icnsPath = @"resources/AppIcon.icns";
    assert([fm fileExistsAtPath:icnsPath]);
    NSDictionary *attrs = [fm attributesOfItemAtPath:icnsPath error:nil];
    assert([attrs fileSize] > 10000); // Must be a substantial multi-res icns file

    printf("  [PASS] testIconSetIntegrity passed.\n");
}

static void testBrandSvgSuite(void) {
    printf("Running testBrandSvgSuite...\n");
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *brandDir = @"resources/brand";

    BOOL isDir = NO;
    assert([fm fileExistsAtPath:brandDir isDirectory:&isDir] && isDir);

    NSArray<NSString *> *requiredFiles = @[
        @"brand-primary.svg",
        @"brand-mono.svg",
        @"brand-inverse.svg",
        @"brand-small.svg",
        @"brand-animated.svg",
        @"brand-preview.html",
        @"brand-rationale.md"
    ];

    for (NSString *file in requiredFiles) {
        NSString *path = [brandDir stringByAppendingPathComponent:file];
        assert([fm fileExistsAtPath:path]);

        if ([file hasSuffix:@".svg"]) {
            NSError *err = nil;
            NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&err];
            assert(err == nil);
            assert([content containsString:@"<svg"]);
            assert([content containsString:@"xmlns=\"http://www.w3.org/2000/svg\""]);
            assert([content containsString:@"viewBox="]);
            assert([content containsString:@"<title"]);
            assert([content containsString:@"</svg>"]);

            if ([file isEqualToString:@"brand-mono.svg"]) {
                assert([content containsString:@"currentColor"]);
            }
            if ([file isEqualToString:@"brand-animated.svg"]) {
                assert([content containsString:@"prefers-reduced-motion"]);
                assert([content containsString:@"@keyframes"]);
            }
        }
    }

    printf("  [PASS] testBrandSvgSuite passed.\n");
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        (void)argc;
        (void)argv;
        printf("=== Running Cascade Icon & Identity Tests ===\n\n");
        testIconSetIntegrity();
        testBrandSvgSuite();
        printf("\n=== All Icon & Identity Tests Passed Successfully! ===\n");
    }
    return 0;
}
