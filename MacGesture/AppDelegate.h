
#import <Cocoa/Cocoa.h>
#import <UserNotifications/UserNotifications.h>

@interface AppDelegate : NSObject <NSApplicationDelegate, UNUserNotificationCenterDelegate>

@property (nonatomic, assign, getter=isEnabled) BOOL enabled;

- (instancetype)init UNAVAILABLE_ATTRIBUTE;
+ (instancetype)new  UNAVAILABLE_ATTRIBUTE;
+ (AppDelegate *)appDelegate;

- (void)updateStatusBarItem;
- (void)showPreferences;

// YES when a right-mouse-down carrying these modifier flags must pass through
// untouched, skipping the gesture engine for the whole drag (issue #42).
// Only the flags of the right-mouse-down event are ever consulted, so
// modifier changes mid-drag do not affect an already-started gesture.
extern BOOL MGShouldSuppressGestureForDrag(CGEventFlags flags);

@end
