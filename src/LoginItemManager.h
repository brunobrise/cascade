#import <Foundation/Foundation.h>

@interface LoginItemManager : NSObject

+ (BOOL)isStartAtLoginEnabled;
+ (BOOL)setStartAtLoginEnabled:(BOOL)enabled error:(NSError **)outError;
+ (NSString *)launchAgentPlistPath;

@end
