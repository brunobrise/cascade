#import <Cocoa/Cocoa.h>

static NSImage *generateCascadeIconImage(CGFloat size) {
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(size, size)];
    [image lockFocus];

    CGContextRef ctx = (CGContextRef)[[NSGraphicsContext currentContext] CGContext];
    CGFloat scale = size / 1024.0;
    CGContextScaleCTM(ctx, scale, scale);

    // 1. macOS Squircle Canvas (824x824 centered at origin 100, 100 on 1024x1024)
    CGRect squircleRect = CGRectMake(100, 100, 824, 824);
    CGFloat squircleRadius = 185;

    // Outer soft drop shadow (Apple HIG standard)
    CGContextSaveGState(ctx);
    CGContextSetShadowWithColor(ctx, CGSizeMake(0, -28), 40, [NSColor colorWithCalibratedWhite:0.0 alpha:0.42].CGColor);

    NSBezierPath *squircle = [NSBezierPath bezierPathWithRoundedRect:NSRectFromCGRect(squircleRect)
                                                            xRadius:squircleRadius
                                                            yRadius:squircleRadius];

    // Deep space obsidian gradient
    NSColor *bgTop = [NSColor colorWithCalibratedRed:0.07 green:0.10 blue:0.17 alpha:1.0];
    NSColor *bgMid = [NSColor colorWithCalibratedRed:0.04 green:0.06 blue:0.11 alpha:1.0];
    NSColor *bgBot = [NSColor colorWithCalibratedRed:0.01 green:0.02 blue:0.04 alpha:1.0];
    NSGradient *bgGrad = [[NSGradient alloc] initWithColors:@[bgTop, bgMid, bgBot]];
    [bgGrad drawInBezierPath:squircle angle:270.0];
    CGContextRestoreGState(ctx);

    // 2. Inner subtle top sheen & boundary perimeter hairline stroke
    CGContextSaveGState(ctx);
    [squircle addClip];

    CGRect sheenRect = CGRectMake(100, 512, 824, 412);
    NSGradient *sheenGrad = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithCalibratedWhite:1.0 alpha:0.06]
                                                          endingColor:[NSColor colorWithCalibratedWhite:1.0 alpha:0.0]];
    [sheenGrad drawInRect:NSRectFromCGRect(sheenRect) angle:270.0];

    [squircle setLineWidth:2.0];
    [[NSColor colorWithCalibratedWhite:1.0 alpha:0.18] setStroke];
    [squircle stroke];

    // 3. System Status Bar Symbol: "macwindow.on.rectangle"
    NSImage *sym = [NSImage imageWithSystemSymbolName:@"macwindow.on.rectangle" accessibilityDescription:@"Cascade"];
    if (sym) {
        NSImageSymbolConfiguration *pConfig = [NSImageSymbolConfiguration configurationWithPointSize:460 weight:NSFontWeightSemibold];
        NSImageSymbolConfiguration *cConfig = [NSImageSymbolConfiguration configurationWithHierarchicalColor:[NSColor whiteColor]];
        NSImageSymbolConfiguration *finalConfig = [pConfig configurationByApplyingConfiguration:cConfig];
        sym = [sym imageWithSymbolConfiguration:finalConfig];

        NSSize symSize = sym.size;
        NSRect destRect = NSMakeRect(512.0 - (symSize.width / 2.0),
                                     512.0 - (symSize.height / 2.0),
                                     symSize.width,
                                     symSize.height);
        [sym drawInRect:destRect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0];
    }

    CGContextRestoreGState(ctx);

    [image unlockFocus];
    return image;
}

static BOOL saveImageAsPNG(NSImage *image, NSString *path, CGFloat pixelSize) {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
        initWithBitmapDataPlanes:NULL
                      pixelsWide:(NSInteger)pixelSize
                      pixelsHigh:(NSInteger)pixelSize
                    bitsPerSample:8
                  samplesPerPixel:4
                         hasAlpha:YES
                         isPlanar:NO
                   colorSpaceName:NSDeviceRGBColorSpace
                      bytesPerRow:0
                     bitsPerPixel:0];
    rep.size = NSMakeSize(pixelSize, pixelSize);

    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
    [image drawInRect:NSMakeRect(0, 0, pixelSize, pixelSize)
             fromRect:NSZeroRect
            operation:NSCompositingOperationCopy
             fraction:1.0];
    [NSGraphicsContext restoreGraphicsState];

    NSData *pngData = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    return [pngData writeToFile:path atomically:YES];
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSString *outDir = @"resources/AppIcon.iconset";
        if (argc > 1) {
            outDir = [NSString stringWithUTF8String:argv[1]];
        }
        [[NSFileManager defaultManager] createDirectoryAtPath:outDir withIntermediateDirectories:YES attributes:nil error:nil];

        struct IconSpec {
            const char *name;
            CGFloat size;
        };

        struct IconSpec specs[] = {
            {"icon_16x16.png", 16},
            {"icon_16x16@2x.png", 32},
            {"icon_32x32.png", 32},
            {"icon_32x32@2x.png", 64},
            {"icon_128x128.png", 128},
            {"icon_128x128@2x.png", 256},
            {"icon_256x256.png", 256},
            {"icon_256x256@2x.png", 512},
            {"icon_512x512.png", 512},
            {"icon_512x512@2x.png", 1024},
            {NULL, 0}
        };

        NSImage *master = generateCascadeIconImage(1024);

        for (int i = 0; specs[i].name != NULL; i++) {
            NSString *filePath = [outDir stringByAppendingPathComponent:[NSString stringWithUTF8String:specs[i].name]];
            if (!saveImageAsPNG(master, filePath, specs[i].size)) {
                fprintf(stderr, "Failed to save %s\n", specs[i].name);
                return 1;
            }
        }
        printf("Successfully generated all unified status-bar iconset assets in %s\n", [outDir UTF8String]);
    }
    return 0;
}
