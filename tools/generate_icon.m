#import <Cocoa/Cocoa.h>

static void drawWindow(CGContextRef ctx, CGRect rect, CGFloat radius, int level, CGFloat delta) {
    CGContextSaveGState(ctx);

    // Layer-dependent ambient contact shadow
    if (level == 2) { // Front
        CGContextSetShadowWithColor(ctx, CGSizeMake(0, -16), 28, [NSColor colorWithCalibratedWhite:0.0 alpha:0.48].CGColor);
    } else if (level == 1) { // Mid
        CGContextSetShadowWithColor(ctx, CGSizeMake(0, -10), 18, [NSColor colorWithCalibratedWhite:0.0 alpha:0.35].CGColor);
    } else { // Back
        CGContextSetShadowWithColor(ctx, CGSizeMake(0, -6), 12, [NSColor colorWithCalibratedWhite:0.0 alpha:0.25].CGColor);
    }

    // Window body path
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSRectFromCGRect(rect) xRadius:radius yRadius:radius];
    
    // Minimalist window gradient fills
    NSColor *topColor, *botColor;
    if (level == 2) {
        topColor = [NSColor colorWithCalibratedRed:0.18 green:0.24 blue:0.34 alpha:0.96];
        botColor = [NSColor colorWithCalibratedRed:0.09 green:0.13 blue:0.20 alpha:0.98];
    } else if (level == 1) {
        topColor = [NSColor colorWithCalibratedRed:0.14 green:0.20 blue:0.28 alpha:0.90];
        botColor = [NSColor colorWithCalibratedRed:0.07 green:0.11 blue:0.17 alpha:0.95];
    } else {
        topColor = [NSColor colorWithCalibratedRed:0.12 green:0.16 blue:0.23 alpha:0.85];
        botColor = [NSColor colorWithCalibratedRed:0.06 green:0.09 blue:0.14 alpha:0.92];
    }

    NSGradient *winGrad = [[NSGradient alloc] initWithStartingColor:topColor endingColor:botColor];
    [winGrad drawInBezierPath:path angle:270.0];

    // Restore for crisp vector overlays
    CGContextRestoreGState(ctx);
    CGContextSaveGState(ctx);

    // Window perimeter hairline border
    CGFloat strokeWidth = (level == 2) ? 2.0 : 1.2;
    [path setLineWidth:strokeWidth];
    if (level == 2) {
        [[NSColor colorWithCalibratedRed:0.22 green:0.74 blue:0.97 alpha:0.75] setStroke]; // Electric Cyan accent
    } else if (level == 1) {
        [[NSColor colorWithCalibratedRed:0.39 green:0.46 blue:0.55 alpha:0.55] setStroke];
    } else {
        [[NSColor colorWithCalibratedRed:0.28 green:0.33 blue:0.41 alpha:0.40] setStroke];
    }
    [path stroke];

    // Title bar hairline separator
    CGFloat titleHeight = rect.size.height * 0.16;
    CGFloat titleLineY = rect.origin.y + rect.size.height - titleHeight;
    CGContextSetStrokeColorWithColor(ctx, [NSColor colorWithCalibratedWhite:1.0 alpha:0.08].CGColor);
    CGContextSetLineWidth(ctx, 1.0);
    CGContextMoveToPoint(ctx, rect.origin.x, titleLineY);
    CGContextAddLineToPoint(ctx, rect.origin.x + rect.size.width, titleLineY);
    CGContextStrokePath(ctx);

    // Front Window: Minimalist Traffic-Light Dots
    if (level == 2) {
        CGFloat dotSize = 8.0;
        CGFloat dotY = rect.origin.y + rect.size.height - (titleHeight + dotSize) / 2.0;
        CGFloat dotSpacing = 14.0;
        CGFloat dotStartX = rect.origin.x + 18.0;

        CGContextSetFillColorWithColor(ctx, [NSColor colorWithCalibratedRed:0.96 green:0.25 blue:0.37 alpha:0.85].CGColor);
        CGContextFillEllipseInRect(ctx, CGRectMake(dotStartX, dotY, dotSize, dotSize));

        CGContextSetFillColorWithColor(ctx, [NSColor colorWithCalibratedRed:0.98 green:0.75 blue:0.14 alpha:0.85].CGColor);
        CGContextFillEllipseInRect(ctx, CGRectMake(dotStartX + dotSpacing, dotY, dotSize, dotSize));

        CGContextSetFillColorWithColor(ctx, [NSColor colorWithCalibratedRed:0.06 green:0.73 blue:0.51 alpha:0.85].CGColor);
        CGContextFillEllipseInRect(ctx, CGRectMake(dotStartX + dotSpacing * 2.0, dotY, dotSize, dotSize));

        // Minimal content capsule bars
        CGFloat lineStartX = rect.origin.x + 24.0;
        CGFloat lineY = titleLineY - 26.0;
        CGFloat lineSpacing = 18.0;
        CGFloat barWidths[3] = { rect.size.width * 0.38, rect.size.width * 0.62, rect.size.width * 0.48 };
        CGFloat barAlphas[3] = { 0.22, 0.14, 0.08 };

        for (int i = 0; i < 3; i++) {
            CGRect barRect = CGRectMake(lineStartX, lineY - (i * lineSpacing), barWidths[i], 5.0);
            NSBezierPath *barPath = [NSBezierPath bezierPathWithRoundedRect:NSRectFromCGRect(barRect) xRadius:2.5 yRadius:2.5];
            [[NSColor colorWithCalibratedWhite:1.0 alpha:barAlphas[i]] setFill];
            [barPath fill];
        }
    }

    // Signature Cascade Click Tab at top-right
    CGRect tabRect = CGRectMake(rect.origin.x + rect.size.width - delta, rect.origin.y + rect.size.height - delta, delta, delta);
    NSBezierPath *tabPath = [NSBezierPath bezierPathWithRoundedRect:NSRectFromCGRect(tabRect) xRadius:radius * 0.7 yRadius:radius * 0.7];

    NSColor *tabTop, *tabBot;
    if (level == 2) {
        tabTop = [NSColor colorWithCalibratedRed:0.22 green:0.74 blue:0.97 alpha:0.98];
        tabBot = [NSColor colorWithCalibratedRed:0.01 green:0.52 blue:0.78 alpha:0.98];
    } else if (level == 1) {
        tabTop = [NSColor colorWithCalibratedRed:0.05 green:0.65 blue:0.91 alpha:0.85];
        tabBot = [NSColor colorWithCalibratedRed:0.01 green:0.41 blue:0.63 alpha:0.85];
    } else {
        tabTop = [NSColor colorWithCalibratedRed:0.01 green:0.52 blue:0.78 alpha:0.70];
        tabBot = [NSColor colorWithCalibratedRed:0.03 green:0.35 blue:0.52 alpha:0.70];
    }

    NSGradient *tabGrad = [[NSGradient alloc] initWithStartingColor:tabTop endingColor:tabBot];
    [tabGrad drawInBezierPath:tabPath angle:270.0];

    // High-precision tab beacon dot
    CGFloat beaconSize = 6.0;
    CGFloat beaconX = tabRect.origin.x + (tabRect.size.width - beaconSize) / 2.0;
    CGFloat beaconY = tabRect.origin.y + (tabRect.size.height - beaconSize) / 2.0;
    CGContextSetFillColorWithColor(ctx, [NSColor colorWithCalibratedWhite:1.0 alpha:level == 2 ? 0.95 : 0.85].CGColor);
    CGContextFillEllipseInRect(ctx, CGRectMake(beaconX, beaconY, beaconSize, beaconSize));

    CGContextRestoreGState(ctx);
}

static NSImage *generateCascadeIconImage(CGFloat size) {
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(size, size)];
    [image lockFocus];

    CGContextRef ctx = (CGContextRef)[[NSGraphicsContext currentContext] CGContext];
    CGFloat scale = size / 1024.0;
    CGContextScaleCTM(ctx, scale, scale);

    // 1. macOS Squircle Canvas (824x824 centered at origin 100, 100)
    CGRect squircleRect = CGRectMake(100, 100, 824, 824);
    CGFloat squircleRadius = 185;

    // Outer soft drop shadow
    CGContextSaveGState(ctx);
    CGContextSetShadowWithColor(ctx, CGSizeMake(0, -32), 44, [NSColor colorWithCalibratedWhite:0.0 alpha:0.45].CGColor);

    NSBezierPath *squircle = [NSBezierPath bezierPathWithRoundedRect:NSRectFromCGRect(squircleRect)
                                                            xRadius:squircleRadius
                                                            yRadius:squircleRadius];
    
    // Deep obsidian background gradient
    NSColor *bgTop = [NSColor colorWithCalibratedRed:0.06 green:0.09 blue:0.16 alpha:1.0];
    NSColor *bgMid = [NSColor colorWithCalibratedRed:0.04 green:0.05 blue:0.09 alpha:1.0];
    NSColor *bgBot = [NSColor colorWithCalibratedRed:0.01 green:0.02 blue:0.03 alpha:1.0];
    NSGradient *bgGrad = [[NSGradient alloc] initWithColors:@[bgTop, bgMid, bgBot]];
    [bgGrad drawInBezierPath:squircle angle:270.0];
    CGContextRestoreGState(ctx);

    // Inner subtle sheen and boundary stroke
    CGContextSaveGState(ctx);
    [squircle addClip];

    CGRect sheenRect = CGRectMake(100, 512, 824, 412);
    NSGradient *sheenGrad = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithCalibratedWhite:1.0 alpha:0.07]
                                                          endingColor:[NSColor colorWithCalibratedWhite:1.0 alpha:0.0]];
    [sheenGrad drawInRect:NSRectFromCGRect(sheenRect) angle:270.0];

    [squircle setLineWidth:2.0];
    [[NSColor colorWithCalibratedRed:0.20 green:0.25 blue:0.35 alpha:0.45] setStroke];
    [squircle stroke];
    CGContextRestoreGState(ctx);

    // 2. Minimalist Invariant Window Cascade
    CGFloat winW = 440;
    CGFloat winH = 308;
    CGFloat delta = 76;
    CGFloat radius = 24;

    CGFloat startX = 216;
    CGFloat startY = 424;

    // Window 1 (Back, Level 0)
    CGRect win1 = CGRectMake(startX, startY, winW, winH);
    drawWindow(ctx, win1, radius, 0, delta);

    // Window 2 (Middle, Level 1)
    CGRect win2 = CGRectMake(startX + delta, startY - delta, winW, winH);
    drawWindow(ctx, win2, radius, 1, delta);

    // Window 3 (Front Active, Level 2)
    CGRect win3 = CGRectMake(startX + delta * 2, startY - delta * 2, winW, winH);
    drawWindow(ctx, win3, radius, 2, delta);

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
        printf("Successfully generated all minimalist iconset assets in %s\n", [outDir UTF8String]);
    }
    return 0;
}
