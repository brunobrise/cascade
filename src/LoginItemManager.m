#import "LoginItemManager.h"
#import <ServiceManagement/ServiceManagement.h>

@implementation LoginItemManager

+ (NSString *)launchAgentPlistPath {
    NSString *home = NSHomeDirectory();
    return [home stringByAppendingPathComponent:@"Library/LaunchAgents/com.brunobrise.cascade.plist"];
}

+ (NSString *)resolvedExecutablePath {
    NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
    if ([bundlePath hasSuffix:@".app"]) {
        NSString *exe = [bundlePath stringByAppendingPathComponent:@"Contents/MacOS/Cascade"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:exe]) {
            return exe;
        }
    }

    NSString *home = NSHomeDirectory();
    NSString *userApp = [home stringByAppendingPathComponent:@"Applications/Cascade.app/Contents/MacOS/Cascade"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:userApp]) {
        return userApp;
    }

    NSString *sysApp = @"/Applications/Cascade.app/Contents/MacOS/Cascade";
    if ([[NSFileManager defaultManager] fileExistsAtPath:sysApp]) {
        return sysApp;
    }

    return userApp;
}

+ (BOOL)isStartAtLoginEnabled {
    if (@available(macOS 13.0, *)) {
        SMAppService *service = [SMAppService mainAppService];
        if (service.status == SMAppServiceStatusEnabled) {
            return YES;
        }
    }

    return [[NSFileManager defaultManager] fileExistsAtPath:[self launchAgentPlistPath]];
}

+ (BOOL)setStartAtLoginEnabled:(BOOL)enabled error:(NSError **)outError {
    BOOL smSuccess = NO;

    if (@available(macOS 13.0, *)) {
        SMAppService *service = [SMAppService mainAppService];
        NSError *smErr = nil;
        if (enabled) {
            smSuccess = [service registerAndReturnError:&smErr];
        } else {
            smSuccess = [service unregisterAndReturnError:&smErr];
        }
    }

    // LaunchAgent fallback
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *plistPath = [self launchAgentPlistPath];

    if (enabled) {
        if (smSuccess) {
            // SMAppService succeeded; remove any legacy plist to avoid duplicates
            if ([fm fileExistsAtPath:plistPath]) {
                [fm removeItemAtPath:plistPath error:nil];
            }
            return YES;
        }

        // Fallback: Create ~/Library/LaunchAgents/com.brunobrise.cascade.plist
        NSString *dir = [plistPath stringByDeletingLastPathComponent];
        if (![fm fileExistsAtPath:dir]) {
            [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:outError];
        }

        NSString *exePath = [self resolvedExecutablePath];
        NSDictionary *plist = @{
            @"Label": @"com.brunobrise.cascade",
            @"ProgramArguments": @[exePath],
            @"RunAtLoad": @YES,
            @"ProcessType": @"Interactive"
        };

        return [plist writeToFile:plistPath atomically:YES];
    } else {
        if ([fm fileExistsAtPath:plistPath]) {
            [fm removeItemAtPath:plistPath error:outError];
        }
        return YES;
    }
}

@end
