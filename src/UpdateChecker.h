#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, CascadeInstallOrigin) {
    CascadeInstallOriginInstalled,
    CascadeInstallOriginHomebrew,
    CascadeInstallOriginSource
};

@interface CascadeUpdateState : NSObject
@property (nonatomic, copy, nullable) NSString *latestVersion;
@property (nonatomic, copy, nullable) NSString *releaseURL;
@property (nonatomic, assign) NSTimeInterval lastCheckedTimestamp;
@property (nonatomic, assign) NSTimeInterval lastNotifiedTimestamp;
@property (nonatomic, copy, nullable) NSString *skippedVersion;

- (nullable NSDictionary *)toDictionary;
+ (nullable instancetype)fromDictionary:(NSDictionary *)dict;
@end

@interface UpdateChecker : NSObject

/// Compares two SemVer strings (supports optional 'v' prefix).
/// Returns NSOrderedDescending if v1 > v2, NSOrderedAscending if v1 < v2, NSOrderedSame if equal.
+ (NSComparisonResult)compareVersion:(NSString *)v1 withVersion:(NSString *)v2;

/// Returns YES if remoteVersion is strictly newer than currentVersion.
+ (BOOL)isVersion:(NSString *)remoteVersion newerThan:(NSString *)currentVersion;

/// Returns the current running version string.
+ (NSString *)currentVersion;

/// Cache file path used for update check state.
+ (NSString *)defaultCachePath;

/// Loads cached state from path (or defaultCachePath if nil).
+ (nullable CascadeUpdateState *)loadStateFromPath:(nullable NSString *)path;

/// Saves state atomically to path (or defaultCachePath if nil).
+ (BOOL)saveState:(CascadeUpdateState *)state toPath:(nullable NSString *)path;

/// Checks if cached state is older than intervalSeconds.
+ (BOOL)isCacheStale:(nullable CascadeUpdateState *)state interval:(NSTimeInterval)intervalSeconds;

/// Checks if notification should be shown based on throttle interval and skipped versions.
+ (BOOL)shouldNotifyForState:(nullable CascadeUpdateState *)state
              currentVersion:(NSString *)currentVersion
            throttleInterval:(NSTimeInterval)throttleInterval;

/// Checks if automatic background update checks are enabled (considers NSUserDefaults and environment variables).
+ (BOOL)isAutomaticCheckEnabled;

/// Sets whether automatic background update checks are enabled in preferences.
+ (void)setAutomaticCheckEnabled:(BOOL)enabled;

/// Identifies where the binary was run from (Homebrew, git source build, or standard install).
+ (CascadeInstallOrigin)detectInstallOriginForPath:(NSString *)path;

/// Returns human-readable upgrade command recommended for the install origin.
+ (NSString *)upgradeCommandForOrigin:(CascadeInstallOrigin)origin;

/// Asynchronously checks for updates.
/// Completion handler called on main queue.
+ (void)checkForUpdatesForce:(BOOL)force
                  completion:(void (^)(BOOL updateAvailable, NSString *_Nullable latestVersion, NSString *_Nullable releaseURL, NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
