#import <Cocoa/Cocoa.h>

static void drawWindow(CGContextRef ctx, CGRect rect, CGFloat radius, BOOL isFront, CGFloat delta) {
    CGContextSaveGState(ctx);

    // Window shadow
    if (isFront) {
        CGContextSetShadowWithColor(ctx, CGSizeMake(0, -18), 32, [NSColor colorWithCalibratedWhite:0.0 alpha:0.55].CGColor);
    } else {
        CGContextSetShadowWithColor(ctx, CGSizeMake(0, -10), 20, [NSColor colorWithCalibratedWhite:0.0 alpha:0.38].CGColor);
    }

    // Window body path
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSRectFromCGRect(rect) xRadius:radius yRadius:radius];
    
    // Window fill
    NSColor *topColor = isFront ? [NSColor colorWithCalibratedRed:0.16 green:0.20 blue:0.32 alpha:0.96]
                                : [NSColor colorWithCalibratedRed:0.11 green:0.14 blue:0.22 alpha:0.92];
    NSColor *botColor = isFront ? [NSColor colorWithCalibratedRed:0.09 green:0.11 blue:0.19 alpha:0.96]
                                : [NSColor colorWithCalibratedRed:0.06 green:0.08 blue:0.14 alpha:0.92];
    NSGradient *winGrad = [[NSGradient alloc] initWithStartingColor:topColor endingColor:botColor];
    [winGrad drawInBezierPath:path angle:270.0];

    // Reset shadow for crisp inner elements
    CGContextRestoreGState(ctx);
    CGContextSaveGState(ctx);

    // Window border
    [path setLineWidth:isFront ? 2.5 : 1.5];
    if (isFront) {
        [[NSColor colorWithCalibratedRed:0.42 green:0.70 blue:1.0 alpha:0.75] setStroke];
    } else {
        [[NSColor colorWithCalibratedWhite:1.0 alpha:0.18] setStroke];
    }
    [path stroke];

    // Title bar area
    CGFloat titleHeight = rect.size.height * 0.18;
    CGRect titleRect = CGRectMake(rect.origin.x, rect.origin.y + rect.size.height - titleHeight, rect.size.width, titleHeight);
    
    // Title bar separator
    CGContextSetStrokeColorWithColor(ctx, [NSColor colorWithCalibratedWhite:1.0 alpha:0.12].CGColor);
    CGContextSetLineWidth(ctx, 1.0);
    CGContextMoveToPoint(ctx, titleRect.origin.x, titleRect.origin.y);
    CGContextAddLineToPoint(ctx, titleRect.origin.x + titleRect.size.width, titleRect.origin.y);
    CGContextStrokePath(ctx);

    // Traffic light dots
    CGFloat dotSize = titleHeight * 0.32;
    CGFloat dotY = titleRect.origin.y + (titleHeight - dotSize) / 2.0;
    CGFloat dotSpacing = dotSize * 1.55;
    CGFloat dotStartX = rect.origin.x + titleHeight * 0.45;

    // Red
    CGContextSetFillColorWithColor(ctx, [NSColor colorWithCalibratedRed:1.0 green:0.37 blue:0.34 alpha:0.95].CGColor);
    CGContextFillEllipseInRect(ctx, CGRectMake(dotStartX, dotY, dotSize, dotSize));
    // Yellow
    CGContextSetFillColorWithColor(ctx, [NSColor colorWithCalibratedRed:1.0 green:0.74 blue:0.18 alpha:0.95].CGColor);
    CGContextFillEllipseInRect(ctx, CGRectMake(dotStartX + dotSpacing, dotY, dotSize, dotSize));
    // Green
    CGContextSetFillColorWithColor(ctx, [NSColor colorWithCalibratedRed:0.15 green:0.79 blue:0.25 alpha:0.95].CGColor);
    CGContextFillEllipseInRect(ctx, CGRectMake(dotStartX + dotSpacing * 2.0, dotY, dotSize, dotSize));

    // Signature Cascade Click Tab at top-right
    CGRect tabRect = CGRectMake(rect.origin.x + rect.size.width - delta, rect.origin.y + rect.size.height - delta, delta, delta);
    NSBezierPath *tabPath = [NSBezierPath bezierPathWithRoundedRect:NSRectFromCGRect(tabRect) xRadius:8 yRadius:8];
    
    NSColor *tabTop = isFront ? [NSColor colorWithCalibratedRed:0.0 green:0.92 blue:1.0 alpha:0.95]
                              : [NSColor colorWithCalibratedRed:0.0 green:0.75 blue:0.90 alpha:0.70];
    NSColor *tabBot = isFront ? [NSColor colorWithCalibratedRed:0.05 green:0.55 blue:0.95 alpha:0.95]
                              : [NSColor colorWithCalibratedRed:0.02 green:0.42 blue:0.75 alpha:0.70];
    NSGradient *tabGrad = [[NSGradient alloc] initWithStartingColor:tabTop endingColor:tabBot];
    [tabGrad drawInBezierPath:tabPath angle:270.0];

    [tabPath setLineWidth:1.5];
    [[NSColor colorWithCalibratedWhite:1.0 alpha:isFront ? 0.6 : 0.3] setStroke];
    [tabPath stroke];

    // Interior content lines for front window
    if (isFront) {
        CGFloat lineStartX = rect.origin.x + 30;
        CGFloat lineEndX = rect.origin.x + rect.size.width - 30;
        CGFloat lineY = titleRect.origin.y - 28;
        CGFloat lineSpacing = 22;
        for (int i = 0; i < 4; i++) {
            CGFloat curY = lineY - (i * lineSpacing);
            CGFloat curWidth = (i == 3) ? (lineEndX - lineStartX) * 0.52 : (lineEndX - lineStartX) * (0.84 - i * 0.08);
            CGContextSetStrokeColorWithColor(ctx, [NSColor colorWithCalibratedWhite:1.0 alpha:0.20 - i * 0.035].CGColor);
            CGContextSetLineWidth(ctx, 3.5);
            CGContextSetLineCap(ctx, kCGLineCapRound);
            CGContextMoveToPoint(ctx, lineStartX, curY);
            CGContextAddLineToPoint(ctx, lineStartX + curWidth, curY);
            CGContextStrokePath(ctx);
        }
    }

    CGContextRestoreGState(ctx);
}

static NSImage *generateCascadeIconImage(CGFloat size) {
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(size, size)];
    [image lockFocus];

    CGContextRef ctx = (CGContextRef)[[NSGraphicsContext currentContext] CGContext];
    CGFloat scale = size / 1024.0;
    CGContextScaleCTM(ctx, scale, scale);

    // 1. macOS Squircle Canvas (824x824 at origin 100, 100)
    CGRect squircleRect = CGRectMake(100, 100, 824, 824);
    CGFloat squircleRadius = 185;

    // Outer drop shadow
    CGContextSaveGState(ctx);
    CGContextSetShadowWithColor(ctx, CGSizeMake(0, -32), 48, [NSColor colorWithCalibratedWhite:0.0 alpha:0.45].CGColor);

    NSBezierPath *squircle = [NSBezierPath bezierPathWithRoundedRect:NSRectFromCGRect(squircleRect)
                                                            xRadius:squircleRadius
                                                            yRadius:squircleRadius];
    // Squircle background gradient (deep space indigo to midnight obsidian)
    NSColor *bgTop = [NSColor colorWithCalibratedRed:0.12 green:0.16 blue:0.28 alpha:1.0];
    NSColor *bgMid = [NSColor colorWithCalibratedRed:0.07 green:0.09 blue:0.17 alpha:1.0];
    NSColor *bgBot = [NSColor colorWithCalibratedRed:0.03 green:0.04 blue:0.09 alpha:1.0];
    NSGradient *bgGrad = [[NSGradient alloc] initWithColors:@[bgTop, bgMid, bgBot]];
    [bgGrad drawInBezierPath:squircle angle:270.0];
    CGContextRestoreGState(ctx);

    // Subtle inner bevel and border
    CGContextSaveGState(ctx);
    [squircle addClip];

    // Subtle top light sheen
    CGRect sheenRect = CGRectMake(100, 512, 824, 412);
    NSGradient *sheenGrad = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithCalibratedWhite:1.0 alpha:0.08]
                                                          endingColor:[NSColor colorWithCalibratedWhite:1.0 alpha:0.0]];
    [sheenGrad drawInRect:NSRectFromCGRect(sheenRect) angle:270.0];

    // Squircle border
    [squircle setLineWidth:2.5];
    [[NSColor colorWithCalibratedWhite:1.0 alpha:0.22] setStroke];
    [squircle stroke];
    CGContextRestoreGState(ctx);

    // 2. Cascading Staggered Windows
    // Window dimensions: 440 x 300
    // Centered at (512, 512)
    CGFloat winW = 440;
    CGFloat winH = 300;
    CGFloat delta = 65;

    CGFloat startX = 225;
    CGFloat startY = 430;

    // Window 1 (Back)
    CGRect win1 = CGRectMake(startX, startY, winW, winH);
    drawWindow(ctx, win1, 18, NO, delta);

    // Window 2 (Middle)
    CGRect win2 = CGRectMake(startX + delta, startY - delta, winW, winH);
    drawWindow(ctx, win2, 18, NO, delta);

    // Window 3 (Front)
    CGRect win3 = CGRectMake(startX + delta * 2, startY - delta * 2, winW, winH);
    drawWindow(ctx, win3, 18, YES, delta);

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
        printf("Successfully generated all iconset assets in %s\n", [outDir UTF8String]);
    }
    return 0;
}
