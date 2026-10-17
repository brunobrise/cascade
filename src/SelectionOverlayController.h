#import <Cocoa/Cocoa.h>

typedef void (^CascadeAreaSelectionCompletion)(CGRect quartzRect, BOOL cancelled);

@interface SelectionOverlayController : NSObject

+ (instancetype)sharedController;
- (void)startSelectionOnScreen:(NSScreen *)screen completion:(CascadeAreaSelectionCompletion)completion;
- (void)cancelSelection;

@end
