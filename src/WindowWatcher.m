#import "WindowWatcher.h"

@interface WindowWatcher ()
@property (nonatomic, assign) BOOL isWatching;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSValue *> *observers;
@property (nonatomic, strong) NSTimer *debounceTimer;
- (void)scheduleDebouncedChange;
@end

static void axObserverCallback(AXObserverRef observer, AXUIElementRef element, CFStringRef notification, void *refcon) {
    (void)observer;
    (void)element;
    (void)notification;
    WindowWatcher *watcher = (__bridge WindowWatcher *)refcon;
    dispatch_async(dispatch_get_main_queue(), ^{
        [watcher scheduleDebouncedChange];
    });
}

@implementation WindowWatcher

- (instancetype)initWithDelegate:(id<WindowWatcherDelegate>)delegate {
    self = [super init];
    if (self) {
        _delegate = delegate;
        _isWatching = NO;
        _debounceInterval = 0.35;
        _observers = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)dealloc {
    [self stopWatching];
}

- (void)startWatching {
    if (self.isWatching) return;
    self.isWatching = YES;

    // 1. Observe all current regular running applications
    [self refreshObservers];

    // 2. Subscribe to application lifecycle events
    NSNotificationCenter *nc = [[NSWorkspace sharedWorkspace] notificationCenter];
    [nc addObserver:self selector:@selector(appDidLaunch:) name:NSWorkspaceDidLaunchApplicationNotification object:nil];
    [nc addObserver:self selector:@selector(appDidTerminate:) name:NSWorkspaceDidTerminateApplicationNotification object:nil];
    [nc addObserver:self selector:@selector(appDidHideOrUnhide:) name:NSWorkspaceDidHideApplicationNotification object:nil];
    [nc addObserver:self selector:@selector(appDidHideOrUnhide:) name:NSWorkspaceDidUnhideApplicationNotification object:nil];
    [nc addObserver:self selector:@selector(spaceDidChange:) name:NSWorkspaceActiveSpaceDidChangeNotification object:nil];
}

static BOOL isAppExcluded(NSString *appName, NSArray<NSString *> *excludeApps) {
    if (!excludeApps || excludeApps.count == 0 || appName.length == 0) return NO;
    for (NSString *item in excludeApps) {
        NSString *trimmed = [item stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length == 0) continue;
        if ([appName localizedCaseInsensitiveCompare:trimmed] == NSOrderedSame ||
            [appName localizedCaseInsensitiveContainsString:trimmed]) return YES;
    }
    return NO;
}

- (void)setExcludeApps:(NSArray<NSString *> *)excludeApps {
    _excludeApps = [excludeApps copy];
    [self refreshObservers];
}

- (void)refreshObservers {
    if (!self.isWatching) return;
    NSArray<NSRunningApplication *> *apps = [[NSWorkspace sharedWorkspace] runningApplications];
    for (NSRunningApplication *app in apps) {
        if (app.activationPolicy == NSApplicationActivationPolicyRegular) {
            if (isAppExcluded(app.localizedName, self.excludeApps)) {
                [self detachFromPid:app.processIdentifier];
            } else {
                [self attachToApp:app];
            }
        }
    }
}

- (void)stopWatching {
    if (!self.isWatching) return;
    self.isWatching = NO;

    [self.debounceTimer invalidate];
    self.debounceTimer = nil;

    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];

    for (NSNumber *pidNum in self.observers) {
        AXObserverRef observer = (AXObserverRef)[self.observers[pidNum] pointerValue];
        if (observer) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), kCFRunLoopCommonModes);
            CFRelease(observer);
        }
    }
    [self.observers removeAllObjects];
}

- (void)attachToApp:(NSRunningApplication *)app {
    if (isAppExcluded(app.localizedName, self.excludeApps)) return;
    pid_t pid = app.processIdentifier;
    if (self.observers[@(pid)]) return;

    AXObserverRef observer = NULL;
    AXError err = AXObserverCreate(pid, axObserverCallback, &observer);
    if (err != kAXErrorSuccess || !observer) return;

    AXUIElementRef appRef = AXUIElementCreateApplication(pid);
    if (appRef) {
        AXObserverAddNotification(observer, appRef, kAXWindowCreatedNotification, (__bridge void *)self);
        AXObserverAddNotification(observer, appRef, kAXUIElementDestroyedNotification, (__bridge void *)self);
        AXObserverAddNotification(observer, appRef, kAXWindowMiniaturizedNotification, (__bridge void *)self);
        AXObserverAddNotification(observer, appRef, kAXWindowDeminiaturizedNotification, (__bridge void *)self);
        AXObserverAddNotification(observer, appRef, kAXWindowMovedNotification, (__bridge void *)self);
        AXObserverAddNotification(observer, appRef, kAXWindowResizedNotification, (__bridge void *)self);

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), kCFRunLoopCommonModes);
        self.observers[@(pid)] = [NSValue valueWithPointer:observer];

        CFRelease(appRef);
    } else {
        CFRelease(observer);
    }
}

- (void)detachFromPid:(pid_t)pid {
    NSValue *val = self.observers[@(pid)];
    if (!val) return;

    AXObserverRef observer = (AXObserverRef)[val pointerValue];
    if (observer) {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), kCFRunLoopCommonModes);
        CFRelease(observer);
    }
    [self.observers removeObjectForKey:@(pid)];
}

- (void)appDidLaunch:(NSNotification *)note {
    NSRunningApplication *app = note.userInfo[NSWorkspaceApplicationKey];
    if (app && app.activationPolicy == NSApplicationActivationPolicyRegular) {
        if (isAppExcluded(app.localizedName, self.excludeApps)) return;
        [self attachToApp:app];
        [self scheduleDebouncedChange];
    }
}

- (void)appDidTerminate:(NSNotification *)note {
    NSRunningApplication *app = note.userInfo[NSWorkspaceApplicationKey];
    if (app) {
        [self detachFromPid:app.processIdentifier];
        if (!isAppExcluded(app.localizedName, self.excludeApps)) {
            [self scheduleDebouncedChange];
        }
    }
}

- (void)appDidHideOrUnhide:(NSNotification *)note {
    NSRunningApplication *app = note.userInfo[NSWorkspaceApplicationKey];
    if (app && isAppExcluded(app.localizedName, self.excludeApps)) return;
    [self scheduleDebouncedChange];
}

- (void)spaceDidChange:(NSNotification *)note {
    (void)note;
    [self scheduleDebouncedChange];
}

- (void)performWithoutTriggering:(dispatch_block_t)block {
    if (!block) return;
    self.isSuppressed = YES;
    [self.debounceTimer invalidate];
    self.debounceTimer = nil;
    block();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.isSuppressed = NO;
    });
}

- (void)scheduleDebouncedChange {
    if (!self.isWatching || self.isSuppressed) return;

    [self.debounceTimer invalidate];
    self.debounceTimer = [NSTimer scheduledTimerWithTimeInterval:self.debounceInterval
                                                          target:self
                                                        selector:@selector(handleDebounceTimer:)
                                                        userInfo:nil
                                                         repeats:NO];
}

- (void)handleDebounceTimer:(NSTimer *)timer {
    (void)timer;
    if (!self.isWatching || self.isSuppressed) return;
    if ([self.delegate respondsToSelector:@selector(windowWatcherDidDetectChange:)]) {
        [self.delegate windowWatcherDidDetectChange:self];
    }
}

@end
