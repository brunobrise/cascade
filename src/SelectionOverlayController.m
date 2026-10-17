#import "SelectionOverlayController.h"
#import "ScreenManager.h"

@interface CascadeSelectionOverlayView : NSView
@property (nonatomic, assign) NSPoint startPoint;
@property (nonatomic, assign) NSPoint currentPoint;
@property (nonatomic, assign) BOOL isDragging;
@property (nonatomic, copy) CascadeAreaSelectionCompletion completionHandler;
@property (nonatomic, weak) NSWindow *overlayWindow;
@end

@implementation CascadeSelectionOverlayView

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)resetCursorRects {
    [self addCursorRect:self.bounds cursor:[NSCursor crosshairCursor]];
}

- (void)mouseDown:(NSEvent *)event {
    self.startPoint = [self convertPoint:event.locationInWindow fromView:nil];
    self.currentPoint = self.startPoint;
    self.isDragging = YES;
    [self setNeedsDisplay:YES];
}

- (void)mouseDragged:(NSEvent *)event {
    self.currentPoint = [self convertPoint:event.locationInWindow fromView:nil];
    [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)event {
    (void)event;
    if (!self.isDragging) return;
    self.isDragging = NO;

    CGFloat minX = fmin(self.startPoint.x, self.currentPoint.x);
    CGFloat minY = fmin(self.startPoint.y, self.currentPoint.y);
    CGFloat width = fabs(self.currentPoint.x - self.startPoint.x);
    CGFloat height = fabs(self.currentPoint.y - self.startPoint.y);

    CascadeAreaSelectionCompletion comp = self.completionHandler;
    NSWindow *win = self.overlayWindow;

    if (width >= 10.0 && height >= 10.0) {
        NSRect cocoaRect = NSMakeRect(minX, minY, width, height);
        // Convert view/window coordinates to screen coordinates
        NSRect screenRect = [win convertRectToScreen:cocoaRect];
        CGFloat h0 = [NSScreen screens].firstObject.frame.size.height;
        CGRect quartzRect = [ScreenManager convertCocoaFrameToQuartz:screenRect primaryScreenHeight:h0];

        [win orderOut:nil];
        if (comp) comp(quartzRect, NO);
    } else {
        [win orderOut:nil];
        if (comp) comp(CGRectZero, YES);
    }
}

- (void)keyDown:(NSEvent *)event {
    if (event.keyCode == 53) { // Escape key
        CascadeAreaSelectionCompletion comp = self.completionHandler;
        NSWindow *win = self.overlayWindow;
        [win orderOut:nil];
        if (comp) comp(CGRectZero, YES);
    } else {
        [super keyDown:event];
    }
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    // Translucent background
    [[NSColor colorWithCalibratedWhite:0.0 alpha:0.25] setFill];
    NSRectFillUsingOperation(self.bounds, NSCompositingOperationSourceOver);

    if (self.isDragging) {
        CGFloat minX = fmin(self.startPoint.x, self.currentPoint.x);
        CGFloat minY = fmin(self.startPoint.y, self.currentPoint.y);
        CGFloat width = fabs(self.currentPoint.x - self.startPoint.x);
        CGFloat height = fabs(self.currentPoint.y - self.startPoint.y);
        NSRect selRect = NSMakeRect(minX, minY, width, height);

        // Selection interior
        [[NSColor colorWithCalibratedRed:0.0 green:0.48 blue:1.0 alpha:0.22] setFill];
        NSRectFillUsingOperation(selRect, NSCompositingOperationSourceOver);

        // Selection stroke
        NSBezierPath *border = [NSBezierPath bezierPathWithRect:selRect];
        border.lineWidth = 2.0;
        [[NSColor colorWithCalibratedRed:0.05 green:0.55 blue:1.0 alpha:0.95] setStroke];
        [border stroke];

        // Size badge
        NSString *badgeText = [NSString stringWithFormat:@"Zoom Area (%.0f × %.0f)", width, height];
        NSDictionary *attrs = @{
            NSFontAttributeName: [NSFont systemFontOfSize:11 weight:NSFontWeightMedium],
            NSForegroundColorAttributeName: [NSColor whiteColor]
        };
        NSSize textSize = [badgeText sizeWithAttributes:attrs];
        NSRect badgeRect = NSMakeRect(minX, minY - textSize.height - 8.0, textSize.width + 12.0, textSize.height + 4.0);
        if (badgeRect.origin.y < 10.0) {
            badgeRect.origin.y = minY + height + 6.0;
        }

        NSBezierPath *pill = [NSBezierPath bezierPathWithRoundedRect:badgeRect xRadius:4.0 yRadius:4.0];
        [[NSColor colorWithCalibratedWhite:0.1 alpha:0.85] setFill];
        [pill fill];
        [badgeText drawAtPoint:NSMakePoint(badgeRect.origin.x + 6.0, badgeRect.origin.y + 2.0) withAttributes:attrs];
    } else {
        // Prompt banner
        NSString *prompt = @"Click and drag to select area to zoom • Esc to cancel";
        NSDictionary *attrs = @{
            NSFontAttributeName: [NSFont systemFontOfSize:14 weight:NSFontWeightMedium],
            NSForegroundColorAttributeName: [NSColor whiteColor]
        };
        NSSize textSize = [prompt sizeWithAttributes:attrs];
        NSRect bannerRect = NSMakeRect((self.bounds.size.width - textSize.width) * 0.5 - 16.0,
                                       self.bounds.size.height - textSize.height - 40.0,
                                       textSize.width + 32.0,
                                       textSize.height + 12.0);
        NSBezierPath *pill = [NSBezierPath bezierPathWithRoundedRect:bannerRect xRadius:8.0 yRadius:8.0];
        [[NSColor colorWithCalibratedWhite:0.1 alpha:0.85] setFill];
        [pill fill];
        [prompt drawAtPoint:NSMakePoint(bannerRect.origin.x + 16.0, bannerRect.origin.y + 6.0) withAttributes:attrs];
    }
}

@end

@interface SelectionOverlayController ()
@property (nonatomic, strong) NSWindow *overlayWindow;
@property (nonatomic, copy) CascadeAreaSelectionCompletion completionHandler;
@end

@implementation SelectionOverlayController

+ (instancetype)sharedController {
    static SelectionOverlayController *sInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sInstance = [[SelectionOverlayController alloc] init];
    });
    return sInstance;
}

- (void)startSelectionOnScreen:(NSScreen *)screen completion:(CascadeAreaSelectionCompletion)completion {
    if (!screen) screen = [NSScreen mainScreen] ?: [NSScreen screens].firstObject;
    if (!screen) {
        if (completion) completion(CGRectZero, YES);
        return;
    }

    self.completionHandler = completion;
    NSRect screenFrame = screen.frame;

    if (!self.overlayWindow) {
        NSWindow *win = [[NSWindow alloc] initWithContentRect:screenFrame
                                                    styleMask:NSWindowStyleMaskBorderless
                                                      backing:NSBackingStoreBuffered
                                                        defer:NO
                                                       screen:screen];
        win.level = NSScreenSaverWindowLevel;
        win.opaque = NO;
        win.backgroundColor = [NSColor clearColor];
        win.ignoresMouseEvents = NO;
        win.hasShadow = NO;
        win.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorStationary;
        self.overlayWindow = win;
    } else {
        [self.overlayWindow setFrame:screenFrame display:YES];
    }

    CascadeSelectionOverlayView *view = [[CascadeSelectionOverlayView alloc] initWithFrame:NSMakeRect(0, 0, screenFrame.size.width, screenFrame.size.height)];
    view.overlayWindow = self.overlayWindow;
    __weak typeof(self) weakSelf = self;
    view.completionHandler = ^(CGRect quartzRect, BOOL cancelled) {
        weakSelf.overlayWindow = nil;
        if (completion) completion(quartzRect, cancelled);
    };

    self.overlayWindow.contentView = view;
    [NSApp activateIgnoringOtherApps:YES];
    [self.overlayWindow makeKeyAndOrderFront:nil];
    [self.overlayWindow makeFirstResponder:view];
}

- (void)cancelSelection {
    if (self.overlayWindow) {
        [self.overlayWindow orderOut:nil];
        self.overlayWindow = nil;
    }
    if (self.completionHandler) {
        self.completionHandler(CGRectZero, YES);
        self.completionHandler = nil;
    }
}

@end
