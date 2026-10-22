
#import <Cocoa/Cocoa.h>
#import <UserNotifications/UserNotifications.h>

@interface AppDelegate : NSObject <NSApplicationDelegate, UNUserNotificationCenterDelegate>

@property (nonatomic, assign, getter=isEnabled) BOOL enabled;

- (instancetype)init UNAVAILABLE_ATTRIBUTE;
+ (instancetype)new  UNAVAILABLE_ATTRIBUTE;
+ (AppDelegate *)appDelegate;

- (void)updateStatusBarItem;
- (void)showPreferences;

// Issue #44: which modifier key held while pressing the right button asks for
// the raw right-drag (temporarily disabling gestures) is user-configurable.
// NSUserDefaults key holding one of: none / command / control / option /
// function. Absent or unrecognized values mean "command" (the default picked
// in #44; before that, #42 hardcoded Control).
extern NSString *const MGSuppressGestureModifierDefaultsKey;

// Maps a stored modifier value (nil = not set) to its CGEventFlags mask.
// "none" maps to 0; unknown values fall back to the command mask.
extern CGEventFlags MGFlagMaskForSuppressModifier(NSString *modifierValue);

// Pure decision core: YES when `flags` include the modifier described by
// `modifierValue`. Kept separate from the cached path below so unit tests can
// exercise every configuration without touching NSUserDefaults.
extern BOOL MGShouldSuppressGestureForDragWithModifier(CGEventFlags flags, NSString *modifierValue);

// Re-reads the stored modifier into the cache behind MGShouldSuppressGesture-
// ForDrag. Called at launch, on NSUserDefaultsDidChangeNotification, and by
// the Preferences popup so a change applies to the very next right-click.
extern void MGRefreshSuppressGestureModifierCache(void);

// YES when a right-mouse-down carrying these modifier flags must pass through
// untouched, skipping the gesture engine for the whole drag (issue #42).
// Only the flags of the right-mouse-down event are ever consulted, so
// modifier changes mid-drag do not affect an already-started gesture.
// Which modifier counts is the configured one (issue #44) — see above.
extern BOOL MGShouldSuppressGestureForDrag(CGEventFlags flags);

@end
