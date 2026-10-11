#import "UpdateChecker.h"

#ifndef CASCADE_VERSION
#define CASCADE_VERSION "0.25.0"
#endif

@implementation CascadeUpdateState

- (NSDictionary *)toDictionary {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    if (self.latestVersion) d[@"latest_version"] = self.latestVersion;
    if (self.releaseURL) d[@"release_url"] = self.releaseURL;
    d[@"last_checked_timestamp"] = @(self.lastCheckedTimestamp);
    d[@"last_notified_timestamp"] = @(self.lastNotifiedTimestamp);
    if (self.skippedVersion) d[@"skipped_version"] = self.skippedVersion;
    return d;
}

+ (instancetype)fromDictionary:(NSDictionary *)dict {
    if (![dict isKindOfClass:[NSDictionary class]]) return nil;
    CascadeUpdateState *s = [[CascadeUpdateState alloc] init];
    s.latestVersion = dict[@"latest_version"];
    s.releaseURL = dict[@"release_url"];
    s.lastCheckedTimestamp = [dict[@"last_checked_timestamp"] doubleValue];
    s.lastNotifiedTimestamp = [dict[@"last_notified_timestamp"] doubleValue];
    s.skippedVersion = dict[@"skipped_version"];
    return s;
}

@end

@interface UpdateCheckerRedirectDelegate : NSObject <NSURLSessionTaskDelegate>
@property (nonatomic, copy) void (^redirectFound)(NSURL *redirectURL);
@end

@implementation UpdateCheckerRedirectDelegate
- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
willPerformHTTPRedirection:(NSHTTPURLResponse *)response
        newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest * _Nullable))completionHandler {
    (void)session; (void)task; (void)response;
    if (self.redirectFound && request.URL) {
        self.redirectFound(request.URL);
    }
    // Cancel following the redirect to save bandwidth and exit immediately
    completionHandler(nil);
}
@end

@implementation UpdateChecker

+ (void)parseSemVerString:(NSString *)str outMajor:(int *)outMaj outMinor:(int *)outMin outPatch:(int *)outPat {
    if (!str || str.length == 0) {
        if (outMaj) *outMaj = 0;
        if (outMin) *outMin = 0;
        if (outPat) *outPat = 0;
        return;
    }
    NSString *clean = [str stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([clean hasPrefix:@"v"] || [clean hasPrefix:@"V"]) {
        clean = [clean substringFromIndex:1];
    }
    int maj = 0, min = 0, pat = 0;
    // Handle standard "0.23.4" or "0.23.4-beta"
    sscanf([clean UTF8String], "%d.%d.%d", &maj, &min, &pat);
    if (outMaj) *outMaj = maj;
    if (outMin) *outMin = min;
    if (outPat) *outPat = pat;
}

+ (NSComparisonResult)compareVersion:(NSString *)v1 withVersion:(NSString *)v2 {
    int maj1 = 0, min1 = 0, pat1 = 0;
    int maj2 = 0, min2 = 0, pat2 = 0;
    [self parseSemVerString:v1 outMajor:&maj1 outMinor:&min1 outPatch:&pat1];
    [self parseSemVerString:v2 outMajor:&maj2 outMinor:&min2 outPatch:&pat2];

    if (maj1 != maj2) return (maj1 > maj2) ? NSOrderedDescending : NSOrderedAscending;
    if (min1 != min2) return (min1 > min2) ? NSOrderedDescending : NSOrderedAscending;
    if (pat1 != pat2) return (pat1 > pat2) ? NSOrderedDescending : NSOrderedAscending;
    return NSOrderedSame;
}

+ (BOOL)isVersion:(NSString *)remoteVersion newerThan:(NSString *)currentVersion {
    return [self compareVersion:remoteVersion withVersion:currentVersion] == NSOrderedDescending;
}

+ (NSString *)currentVersion {
    NSString *v = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    if (v.length > 0) return v;
    return [NSString stringWithUTF8String:CASCADE_VERSION];
}

+ (NSString *)defaultCachePath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *base = paths.firstObject ?: [NSTemporaryDirectory() stringByAppendingPathComponent:@"Caches"];
    NSString *cascadeCache = [base stringByAppendingPathComponent:@"com.brunobrise.cascade"];
    return [cascadeCache stringByAppendingPathComponent:@"update_state.json"];
}

+ (CascadeUpdateState *)loadStateFromPath:(NSString *)path {
    NSString *target = path ?: [self defaultCachePath];
    NSData *data = [NSData dataWithContentsOfFile:target];
    if (!data) return nil;
    NSError *err = nil;
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
    if (err || ![dict isKindOfClass:[NSDictionary class]]) return nil;
    return [CascadeUpdateState fromDictionary:dict];
}

+ (BOOL)saveState:(CascadeUpdateState *)state toPath:(NSString *)path {
    if (!state) return NO;
    NSString *target = path ?: [self defaultCachePath];
    NSString *parent = [target stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:parent withIntermediateDirectories:YES attributes:nil error:nil];

    NSDictionary *dict = [state toDictionary];
    if (!dict) return NO;
    NSError *err = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:NSJSONWritingPrettyPrinted error:&err];
    if (err || !data) return NO;
    return [data writeToFile:target options:NSDataWritingAtomic error:nil];
}

+ (BOOL)isCacheStale:(CascadeUpdateState *)state interval:(NSTimeInterval)intervalSeconds {
    if (!state || state.lastCheckedTimestamp <= 0) return YES;
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    return (now - state.lastCheckedTimestamp) >= intervalSeconds;
}

+ (BOOL)shouldNotifyForState:(CascadeUpdateState *)state
              currentVersion:(NSString *)currentVersion
            throttleInterval:(NSTimeInterval)throttleInterval {
    if (!state || !state.latestVersion || state.latestVersion.length == 0) return NO;
    if (![self isVersion:state.latestVersion newerThan:currentVersion]) return NO;
    if (state.skippedVersion && [state.skippedVersion isEqualToString:state.latestVersion]) return NO;

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (state.lastNotifiedTimestamp > 0 && (now - state.lastNotifiedTimestamp) < throttleInterval) {
        return NO;
    }
    return YES;
}

+ (BOOL)isAutomaticCheckEnabled {
    if (getenv("CASCADE_NO_UPDATE_CHECK") || getenv("DO_NOT_TRACK")) {
        return NO;
    }
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    if ([defs objectForKey:@"automaticallyCheckForUpdates"] != nil) {
        return [defs boolForKey:@"automaticallyCheckForUpdates"];
    }
    return YES; // Enabled by default in user preferences
}

+ (void)setAutomaticCheckEnabled:(BOOL)enabled {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:@"automaticallyCheckForUpdates"];
}

+ (CascadeInstallOrigin)detectInstallOriginForPath:(NSString *)path {
    NSString *p = path.lowercaseString;
    if ([p containsString:@"/homebrew/"] || [p containsString:@"/cellar/"]) {
        return CascadeInstallOriginHomebrew;
    }
    if ([p containsString:@"/build/"] || [p containsString:@"/cascade/cascade"]) {
        return CascadeInstallOriginSource;
    }
    return CascadeInstallOriginInstalled;
}

+ (NSString *)upgradeCommandForOrigin:(CascadeInstallOrigin)origin {
    switch (origin) {
        case CascadeInstallOriginHomebrew:
            return @"brew upgrade cascade";
        case CascadeInstallOriginSource:
            return @"git pull && make install";
        case CascadeInstallOriginInstalled:
        default:
            return @"curl -fsSL https://raw.githubusercontent.com/brunobrise/cascade/main/install.sh | bash";
    }
}

static void invokeCompletion(void (^completion)(BOOL, NSString *, NSString *, NSError *),
                             BOOL avail, NSString *ver, NSString *url, NSError *err) {
    if (completion) {
        completion(avail, ver, url, err);
    }
}

+ (void)checkForUpdatesForce:(BOOL)force
                  completion:(void (^)(BOOL updateAvailable, NSString *_Nullable latestVersion, NSString *_Nullable releaseURL, NSError *_Nullable error))completion {
    NSString *currVer = [self currentVersion];
    CascadeUpdateState *cached = [self loadStateFromPath:nil];

    if (!force && ![self isCacheStale:cached interval:86400.0]) {
        BOOL avail = cached.latestVersion ? [self isVersion:cached.latestVersion newerThan:currVer] : NO;
        invokeCompletion(completion, avail, cached.latestVersion, cached.releaseURL, nil);
        return;
    }

    if (!force && ![self isAutomaticCheckEnabled]) {
        invokeCompletion(completion, NO, nil, nil, nil);
        return;
    }

    // Step 1: Check for explicit token or gh auth for private repo support
    NSString *authToken = nil;
    char *envToken = getenv("GITHUB_TOKEN");
    if (!envToken) envToken = getenv("GH_TOKEN");
    if (envToken && strlen(envToken) > 0) {
        authToken = [NSString stringWithUTF8String:envToken];
    }

    if (authToken) {
        [self queryGitHubRestApiWithToken:authToken currentVersion:currVer cachedState:cached completion:completion];
        return;
    }

    // Step 2: Try zero-cost HEAD redirect request against public web release endpoint
    NSURL *headURL = [NSURL URLWithString:@"https://github.com/brunobrise/cascade/releases/latest"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:headURL
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:2.5];
    request.HTTPMethod = @"HEAD";
    [request setValue:@"Cascade-UpdateChecker" forHTTPHeaderField:@"User-Agent"];

    UpdateCheckerRedirectDelegate *del = [[UpdateCheckerRedirectDelegate alloc] init];
    __block BOOL redirectHandled = NO;

    del.redirectFound = ^(NSURL *redirectURL) {
        redirectHandled = YES;
        NSString *tag = redirectURL.lastPathComponent;
        if ([tag hasPrefix:@"v"] || [tag hasPrefix:@"V"]) {
            tag = [tag substringFromIndex:1];
        }

        CascadeUpdateState *newState = cached ?: [[CascadeUpdateState alloc] init];
        newState.latestVersion = tag;
        newState.releaseURL = redirectURL.absoluteString;
        newState.lastCheckedTimestamp = [[NSDate date] timeIntervalSince1970];
        [UpdateChecker saveState:newState toPath:nil];

        BOOL avail = [UpdateChecker isVersion:tag newerThan:currVer];
        invokeCompletion(completion, avail, tag, redirectURL.absoluteString, nil);
    };

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:del delegateQueue:nil];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        (void)data;
        if (redirectHandled) return;

        NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
        if (httpResp.statusCode == 404 || error != nil) {
            // Private repo or offline: attempt gh CLI query if present
            [self queryGhCliFallbackWithCurrentVersion:currVer cachedState:cached completion:completion];
            return;
        }

        invokeCompletion(completion, NO, nil, nil, error);
    }];
    [task resume];
}

+ (void)queryGitHubRestApiWithToken:(NSString *)token
                     currentVersion:(NSString *)currVer
                        cachedState:(CascadeUpdateState *)cached
                         completion:(void (^)(BOOL, NSString *, NSString *, NSError *))completion {
    NSURL *url = [NSURL URLWithString:@"https://api.github.com/repos/brunobrise/cascade/releases/latest"];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url
                                                       cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                   timeoutInterval:2.5];
    [req setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    [req setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [req setValue:@"Cascade-UpdateChecker" forHTTPHeaderField:@"User-Agent"];

    NSURLSessionDataTask *t = [[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *res, NSError *err) {
        (void)res;
        if (err || !data) {
            invokeCompletion(completion, NO, nil, nil, err);
            return;
        }
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSString *tagName = json[@"tag_name"];
        NSString *htmlURL = json[@"html_url"];
        if (tagName) {
            NSString *v = tagName;
            if ([v hasPrefix:@"v"] || [v hasPrefix:@"V"]) v = [v substringFromIndex:1];
            CascadeUpdateState *newState = cached ?: [[CascadeUpdateState alloc] init];
            newState.latestVersion = v;
            newState.releaseURL = htmlURL;
            newState.lastCheckedTimestamp = [[NSDate date] timeIntervalSince1970];
            [UpdateChecker saveState:newState toPath:nil];

            BOOL avail = [UpdateChecker isVersion:v newerThan:currVer];
            invokeCompletion(completion, avail, v, htmlURL, nil);
        } else {
            invokeCompletion(completion, NO, nil, nil, nil);
        }
    }];
    [t resume];
}

+ (NSString *)findGhExecutable {
    NSArray *candidates = @[
        @"/opt/homebrew/bin/gh",
        @"/usr/local/bin/gh",
        @"/usr/bin/gh",
        @"/bin/gh",
        [NSHomeDirectory() stringByAppendingPathComponent:@".nix-profile/bin/gh"]
    ];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *p in candidates) {
        if ([fm isExecutableFileAtPath:p]) return p;
    }
    return nil;
}

+ (void)queryGhCliFallbackWithCurrentVersion:(NSString *)currVer
                                 cachedState:(CascadeUpdateState *)cached
                                  completion:(void (^)(BOOL, NSString *, NSString *, NSError *))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSString *ghPath = [self findGhExecutable];
        if (!ghPath) {
            NSError *err = [NSError errorWithDomain:@"CascadeUpdate" code:404
                                           userInfo:@{NSLocalizedDescriptionKey: @"GitHub release unreachable and 'gh' CLI not found."}];
            invokeCompletion(completion, NO, nil, nil, err);
            return;
        }

        NSTask *ghTask = [[NSTask alloc] init];
        ghTask.launchPath = ghPath;
        ghTask.arguments = @[@"release", @"view", @"-R", @"brunobrise/cascade", @"--json", @"tagName,url"];
        NSMutableDictionary *env = [[[NSProcessInfo processInfo] environment] mutableCopy];
        env[@"PATH"] = @"/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
        ghTask.environment = env;
        NSPipe *outPipe = [NSPipe pipe];
        ghTask.standardOutput = outPipe;
        ghTask.standardError = [NSPipe pipe];
        @try {
            [ghTask launch];
            [ghTask waitUntilExit];
            if (ghTask.terminationStatus == 0) {
                NSData *outData = [outPipe.fileHandleForReading readDataToEndOfFile];
                NSDictionary *res = [NSJSONSerialization JSONObjectWithData:outData options:0 error:nil];
                NSString *tag = res[@"tagName"];
                NSString *url = res[@"url"];
                if (tag) {
                    NSString *v = tag;
                    if ([v hasPrefix:@"v"] || [v hasPrefix:@"V"]) v = [v substringFromIndex:1];
                    CascadeUpdateState *newState = cached ?: [[CascadeUpdateState alloc] init];
                    newState.latestVersion = v;
                    newState.releaseURL = url;
                    newState.lastCheckedTimestamp = [[NSDate date] timeIntervalSince1970];
                    [UpdateChecker saveState:newState toPath:nil];

                    BOOL avail = [UpdateChecker isVersion:v newerThan:currVer];
                    invokeCompletion(completion, avail, v, url, nil);
                    return;
                }
            }
        } @catch (NSException *e) {
            (void)e;
        }

        NSError *err = [NSError errorWithDomain:@"CascadeUpdate" code:500
                                       userInfo:@{NSLocalizedDescriptionKey: @"Failed to fetch latest release via 'gh' CLI."}];
        invokeCompletion(completion, NO, nil, nil, err);
    });
}

@end
