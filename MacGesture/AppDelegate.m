
#import "AppDelegate.h"
#import "AppPrefsWindowController.h"
#import "CanvasWindowController.h"
#import "BlockAllowFilter.h"
#import "RulesList.h"
#import "utils.h"

@interface AppDelegate () <AppPrefsDelegate>

@property (strong) IBOutlet NSMenu *statusItemMenu;
@property (strong) NSStatusItem *statusItem;

@end

@implementation AppDelegate

static CanvasWindowController *windowController;
static CGEventRef mouseDownEvent, mouseDraggedEvent;
static NSMutableString *direction;
static NSPoint lastLocation;
static CFMachPortRef mouseEventTap;
static AppPrefsWindowController *_preferencesWindowController;
static NSTimeInterval lastMouseWheelEventTime = 0;
static BOOL eventTriggered;
static NSUserDefaults *defaults;
static NSTimer *accessibilityWatchTimer;
static NSAlert *accessibilityAlert;

+ (AppDelegate *)appDelegate {
    return (AppDelegate *) [[NSApplication sharedApplication] delegate];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {

    defaults = [NSUserDefaults standardUserDefaults];
    NSBundle *bundle = [NSBundle mainBundle];

//#warning Debugging first app launch
//    [defaults removePersistentDomainForName:bundle.bundleIdentifier];
//    [defaults synchronize];

    NSArray<NSRunningApplication *> *apps =
        [NSRunningApplication runningApplicationsWithBundleIdentifier:bundle.bundleIdentifier];
    NSDistributedNotificationCenter *center = [NSDistributedNotificationCenter defaultCenter];
    NSString *name = @"MacGestureOpenPreferences";

    // Check whether MacGesture isn't running already.
    // In case it is, notify the earlier instance to open Preferences window and finish execution.
    if (apps.count > 1)
    {
        [center postNotificationName:name object:nil userInfo:nil deliverImmediately:YES];
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSApp terminate:self];
        });
        return;
    }

    // Defaults registration

    BOOL hasRunBefore = [defaults boolForKey:@"hasRunBefore"];

    NSURL *defaultPrefsFile = [bundle URLForResource:@"DefaultPreferences" withExtension:@"plist"];
    NSDictionary *defaultPrefs = [NSDictionary dictionaryWithContentsOfURL:defaultPrefsFile];
    [defaults registerDefaults:defaultPrefs];
    [defaults synchronize];

    // README prompt

    if (!hasRunBefore) {
        [defaults setBool:YES forKey:@"hasRunBefore"];

        NSString *text = NSLocalizedString(@"Welcome to MacGesture! 🎉", nil);
        NSString *info = NSLocalizedString(@"A brief information about how MacGesture works "
             "is available in README. A copy of README is also included in About section "
             "of MacGesture's Preferences.", nil);

        NSAlert *alert = [NSAlert new];
        alert.alertStyle = NSAlertStyleInformational;
        alert.messageText = text;
        alert.informativeText = info;
        [alert addButtonWithTitle:NSLocalizedString(@"Open README", nil)];
        [alert addButtonWithTitle:NSLocalizedString(@"Skip", nil)];

        if ([alert runModal] == NSAlertFirstButtonReturn) {
            NSURL *readmeURL = [bundle URLForResource:@"README" withExtension:@"html"];
            [[NSWorkspace sharedWorkspace] openURL:readmeURL];
        }
    }

    // Core initialization
    //
    // This has to happen before the Accessibility check below. That check's
    // alert used to run *modally* right here, which blocked the rest of
    // -applicationDidFinishLaunching: for as long as the alert was up — so
    // when the permission was missing, the status bar item was never created
    // and gestures were never wired up. MacGesture is an LSUIElement app, so
    // the alert has no Dock icon to surface it and can sit unnoticed behind
    // other windows, leaving the app looking dead. Set up everything that
    // does not depend on the permission first.

    windowController = [CanvasWindowController new];
    direction = [NSMutableString string];
    _enabled = YES;

    [BWFilter compatibleProcedureWithPreviousVersionBlockRules];

    [self updateStatusBarItem];

    // Accessibility permission check & alert

    const void * keys[] = { kAXTrustedCheckOptionPrompt };
    const void * values[] = { kCFBooleanTrue };

    CFDictionaryRef options = CFDictionaryCreate(
        kCFAllocatorDefault, keys, values, sizeof(keys) / sizeof(*keys),
        &kCFCopyStringDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

    BOOL accessibilityEnabled = AXIsProcessTrustedWithOptions(options);
    CFRelease(options);

    if (!accessibilityEnabled || ![self enableMouseEventTap]) {
        // Gestures cannot be wired up yet. Watch for the permission arriving so
        // they start working on their own — previously the tap was only ever
        // registered here at launch, so granting the permission did nothing
        // until the user quit and reopened MacGesture.
        [self startWatchingForAccessibilityPermission];

        // Only nag about the permission when that is actually what is missing.
        if (!accessibilityEnabled)
            [self presentAccessibilityAlert];
    }

    [center setSuspended:NO];
    [center addObserver:self selector:@selector(receiveOpenPreferencesNotification:)
        name:name object:nil suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];

    UNUserNotificationCenter *notificationCenter = [UNUserNotificationCenter currentNotificationCenter];
    notificationCenter.delegate = self;
    [notificationCenter requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound)
                                      completionHandler:^(BOOL granted, NSError *_Nullable error) {
        if (!granted)
            NSLog(@"[MacGesture] notification authorization not granted: %@", error);
    }];

    // The application is an ordinary app that appears in the Dock and may
    // have a user interface.
//    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

    // The application does not appear in the Dock and does not have a menu
    // bar, but it may be activated programmatically or by clicking on one
    // of its windows.
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];

    // Open preferences on startup
    if (!hasRunBefore || [defaults boolForKey:@"openPrefOnStartup"]) {
        [self openPreferences:self];
    }

    // Register for Workspace session notifications
    [[[NSWorkspace sharedWorkspace] notificationCenter]
            addObserver:self
            selector:@selector(workspaceSessionActiveChange:)
            name:NSWorkspaceSessionDidBecomeActiveNotification
            object:nil];

    [[[NSWorkspace sharedWorkspace] notificationCenter]
            addObserver:self
            selector:@selector(workspaceSessionActiveChange:)
            name:NSWorkspaceSessionDidResignActiveNotification
            object:nil];
}

#pragma mark -
#pragma mark Accessibility permission & mouse event tap

// Creates the mouse event tap and wires it into the run loop.
//
// Idempotent: once the tap exists this only makes sure it is enabled, so it is
// safe to call from both the launch path and the permission watcher.
//
// Returns NO when the tap could not be created, which in practice means the
// Accessibility permission has not been granted (yet).
- (BOOL)enableMouseEventTap {
    if (mouseEventTap != NULL) {
        CGEventTapEnable(mouseEventTap, true);
        return YES;
    }

    CGEventMask eventMask = CGEventMaskBit(kCGEventRightMouseDown) | CGEventMaskBit(kCGEventRightMouseDragged) |
                            CGEventMaskBit(kCGEventRightMouseUp) | CGEventMaskBit(kCGEventLeftMouseDown) |
                            CGEventMaskBit(kCGEventScrollWheel);

    mouseEventTap = CGEventTapCreate(kCGHIDEventTap, kCGHeadInsertEventTap,
                                     kCGEventTapOptionDefault, eventMask,
                                     mouseEventCallback, NULL);
    if (mouseEventTap == NULL)
        return NO;

    CFRunLoopSourceRef runLoopSource =
        CFMachPortCreateRunLoopSource(kCFAllocatorDefault, mouseEventTap, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
    CFRelease(runLoopSource);

    // mouseEventTap is deliberately kept alive for the lifetime of the app and
    // not released here: mouseEventCallback re-enables it via CGEventTapEnable()
    // whenever the system disables the tap (kCGEventTapDisabledByTimeout /
    // ...ByUserInput), so the static has to remain an owned, valid reference.
    return YES;
}

// Polls until the Accessibility permission shows up, then wires up the event tap
// so gestures begin working without the user restarting MacGesture.
//
// The timer is installed in NSRunLoopCommonModes on purpose. The permission
// alert below runs a modal session, and a timer scheduled only in the default
// mode would be starved for exactly as long as that alert is on screen — which
// is precisely the window in which the user goes and grants the permission.
- (void)startWatchingForAccessibilityPermission {
    if (accessibilityWatchTimer)
        return;

    __weak AppDelegate *weakSelf = self;
    accessibilityWatchTimer =
        [NSTimer timerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *timer) {
            AppDelegate *strongSelf = weakSelf;
            if (!strongSelf) {
                [timer invalidate];
                return;
            }

            if (!AXIsProcessTrusted())
                return;

            // Trusted, but the tap may still be refused for a moment; keep
            // polling rather than giving up and looking dead again.
            if (![strongSelf enableMouseEventTap])
                return;

            [timer invalidate];
            accessibilityWatchTimer = nil;
            [strongSelf accessibilityPermissionDidArrive];
        }];

    [[NSRunLoop mainRunLoop] addTimer:accessibilityWatchTimer forMode:NSRunLoopCommonModes];
}

// Called once the permission is in place and gestures are actually live.
- (void)accessibilityPermissionDidArrive {
    // The "please grant the permission" alert, if it is still up, is now stale.
    // Ending its modal session makes runModal return NSModalResponseStop, so the
    // "Open System Settings" branch correctly does not fire.
    if (accessibilityAlert.window.isVisible)
        [NSApp stopModal];
    accessibilityAlert = nil;

    MGPostNotification(NSLocalizedString(@"MacGesture is ready", nil),
                       NSLocalizedString(@"Accessibility permission granted, gestures are now active.", nil),
                       NO);
}

- (void)presentAccessibilityAlert {
    NSAlert *alert = [NSAlert new];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = NSLocalizedString(
        @"MacGesture processes your mouse events, thus requires "
         "the Accessibility permission to work properly", nil);
    alert.informativeText = [NSString stringWithFormat:@"%@\n\n%@",
        NSLocalizedString(@"Please navigate to System Preferences → Security & "
            "Privacy → Privacy → Accessibility section to enable it for MacGesture.", nil),
        NSLocalizedString(@"If it's already enabled but gestures aren't "
            "working properly, please re-open MacGesture.", nil)];
    [alert addButtonWithTitle:NSLocalizedString(@"Open System Settings", nil)];
    [alert addButtonWithTitle:NSLocalizedString(@"Later", nil)];

    accessibilityAlert = alert;

    // Presented asynchronously so it cannot block the remainder of
    // -applicationDidFinishLaunching:. Activating first matters as well: an
    // LSUIElement app has no Dock icon, so an alert raised while the app is
    // inactive can end up buried behind other windows.
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSApp activateIgnoringOtherApps:YES];
        NSModalResponse response = [alert runModal];
        if (accessibilityAlert == alert)
            accessibilityAlert = nil;
        if (response == NSAlertFirstButtonReturn)
            [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:
                @"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]];
    });
}

#pragma mark -

- (void)workspaceSessionActiveChange:(NSNotification *)notification {
    BOOL nowActive = notification.name != NSWorkspaceSessionDidResignActiveNotification;
    NSLog(@"[WORKSPACE SESSION] Now active: %d", nowActive);
}

- (void)updateStatusBarItem {
    NSStatusBar *statusBar = [NSStatusBar systemStatusBar];

    if ([defaults boolForKey:@"showIconInStatusBar"]) {

        NSStatusItem *item = self.statusItem
                          ?: [statusBar statusItemWithLength:NSVariableStatusItemLength];

        NSString *iconName = @"menubar_icon";
        if (!_enabled) iconName = [iconName stringByAppendingString:@"-disabled"];
        if (@available(macOS 11.0, *)) iconName = [iconName stringByAppendingString:@"-big_sur"];

        NSImage *menuIcon = [NSImage imageNamed:iconName];
        menuIcon.template = YES;
        item.image = menuIcon;
//        item.alternateImage = highlightIcon;
        item.menu = self.statusItemMenu;

        if (@available(macOS 11.0, *));
        else item.highlightMode = YES;

        self.statusItem = item;

    } else {
        if (self.statusItem) {
            [statusBar removeStatusItem:self.statusItem];
            self.statusItem = nil;
        }
    }
}

- (void)setEnabled:(BOOL)enabled {
    _enabled = enabled;
    [self updateStatusBarItem];
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
    // Show notifications even while MacGesture is frontmost.
    completionHandler(UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionSound);
}

- (void)showPreferences {
    [NSApp activateIgnoringOtherApps:YES];

    // Instantiate Preferences window controller
    if (!_preferencesWindowController) {
        _preferencesWindowController = [[AppPrefsWindowController alloc] initWithWindowNibName:@"Preferences"];
        _preferencesWindowController.delegate = self;
        [_preferencesWindowController showWindow:self];
    } else [_preferencesWindowController.window orderFront:self];
}

- (void)appPrefsDidClose {
    _preferencesWindowController = nil;
}

- (IBAction)openPreferences:(id)sender {
    [self showPreferences];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    // Reopening the app (double-clicking it in Finder while it's already running)
    // brings the preferences window back. The menu-bar icon can be hidden in a
    // crowded / notched menu bar, so without this there's no other way back in.
    //
    // Do NOT trust `flag`: the gesture overlay (CanvasWindowController) is a borderless
    // full-screen window that stays ordered-in for the app's lifetime, so AppKit reports
    // hasVisibleWindows=YES even when Preferences is closed. Check the prefs window itself.
    if (!_preferencesWindowController || !_preferencesWindowController.window.isVisible) {
        [self showPreferences];
    }
    return YES;
}

- (IBAction)showHelp:(id)sender {
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"README" withExtension:@"html"];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

- (void)receiveOpenPreferencesNotification:(NSNotification *)notification {
    if ([notification.name isEqualToString:@"MacGestureOpenPreferences"])
        [self showPreferences];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    // This event can be triggered when switching desktops in Sierra. See BUG #37
    if ((![defaults boolForKey:@"openPrefOnStartup"]
         && ![defaults boolForKey:@"showIconInStatusBar"])
        || [defaults boolForKey:@"openPrefOnActivate"]) {
        [self openPreferences:self];
    }
}

static void addDirection(unichar dir, bool allowSameDirection) {
    unichar lastDirectionChar;
    if (direction.length > 0) {
        lastDirectionChar = [direction characterAtIndex:direction.length - 1];
    } else {
        lastDirectionChar = ' ';
    }
    
    if (dir != lastDirectionChar || allowSameDirection) {
        NSString *temp = [NSString stringWithCharacters:&dir length:1];
        [direction appendString:temp];
        [windowController writeDirection:direction];
        handleGesture(NO);
    }
}

static void updateDirections(NSEvent *event) {
    // not thread safe
    NSPoint newLocation = event.locationInWindow;
    double deltaX = newLocation.x - lastLocation.x;
    double deltaY = newLocation.y - lastLocation.y;
    double absX = fabs(deltaX);
    double absY = fabs(deltaY);
    double threshold = [defaults doubleForKey:@"directionDetectionThreshold"];
    if (absX + absY < threshold) {
        return; // ignore short distance
    }
    
    lastLocation = event.locationInWindow;
    
    if (absX > absY) {
        if (deltaX > 0) {
            addDirection('R', false);
            eventTriggered = YES;
            return;
        } else {
            addDirection('L', false);
            eventTriggered = YES;
            return;
        }
    } else {
        if (deltaY > 0) {
            addDirection('U', false);
            eventTriggered = YES;
            return;
        } else {
            addDirection('D', false);
            eventTriggered = YES;
            return;
        }
    }
    
}

static bool handleGesture(BOOL lastGesture) {
    return [[RulesList sharedRulesList] handleGesture:direction isLastGesture:lastGesture];
}

void resetDirection(void) {
    [direction setString:@""];
}

// See https://developer.apple.com/library/mac/documentation/Carbon/Reference/QuartzEventServicesRef/#//apple_ref/c/tdef/CGEventTapCallBack
static CGEventRef mouseEventCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon) {
    static BOOL shouldShow;

    if (![[AppDelegate appDelegate] isEnabled])
        return event;

    NSEvent *mouseEvent;
    switch (type) {
        case kCGEventRightMouseDown:
            DebugLog(@"kCGEventRightMouseDown");
            // not thread safe, but it's always called on main thread
            // check blocker apps
            //    if(wildLike(frontBundleName(), [defaults stringForKey:@"blockFilter"])){
            if (true)
            {
                NSString *frontBundle = frontBundleName();
                if (![BWFilter shouldHookMouseEventForApp:frontBundle] || (![defaults boolForKey:@"showUIInWhateverApp"] && ![[RulesList sharedRulesList] appSuitedRule:frontBundle])) {
//                        CGEventPost(kCGSessionEventTap, mouseDownEvent);
//                        if (mouseDraggedEvent) {
//                            CGEventPost(kCGSessionEventTap, mouseDraggedEvent);
//                        }
                    shouldShow = NO;
                    return event;
                }
                shouldShow = YES;
                eventTriggered = NO;
            }
            
            if (mouseDownEvent) { // mouseDownEvent may not release when kCGEventTapDisabledByTimeout
                resetDirection();
                
                CGPoint location = CGEventGetLocation(mouseDownEvent);
                CGEventPost(kCGSessionEventTap, mouseDownEvent);
                CFRelease(mouseDownEvent);
                if (mouseDraggedEvent) {
                    location = CGEventGetLocation(mouseDraggedEvent);
                    CGEventPost(kCGSessionEventTap, mouseDraggedEvent);
                    CFRelease(mouseDraggedEvent);
                }
                CGEventRef event_up = CGEventCreateMouseEvent(NULL, kCGEventRightMouseUp, location, kCGMouseButtonRight);
                CGEventPost(kCGSessionEventTap, event_up);
                CFRelease(event_up);
                mouseDownEvent = mouseDraggedEvent = NULL;
            }
            mouseEvent = [NSEvent eventWithCGEvent:event];
            mouseDownEvent = event;
            CFRetain(mouseDownEvent);
            
            [windowController handleMouseEvent:mouseEvent];
            lastLocation = mouseEvent.locationInWindow;
            break;
        case kCGEventRightMouseDragged:
            DebugLog(@"kCGEventRightMouseDragged");
            if (!shouldShow){
                return event;
            }
            
            if (mouseDownEvent) {
                mouseEvent = [NSEvent eventWithCGEvent:event];
                
                // Hack when Synergy is started after MacGesture
                // -- when dragging to a client, the mouse point resets to (server_screenwidth/2+rnd(-1,1),server_screenheight/2+rnd(-1,1))
                if (mouseDraggedEvent) {
                    NSPoint lastPoint = CGEventGetLocation(mouseDraggedEvent);
                    NSPoint currentPoint = [mouseEvent locationInWindow];
                    // FIXME: use which screen?
                    // Here use main screen
                    NSRect screen = [[NSScreen mainScreen] frame];
                    // The distance from the cursor to the left of the main screen
                    float d1 = fabs(lastPoint.x - screen.origin.x);
                    // The distance from the cursor to the right of the main screen
                    float d2 = fabs(lastPoint.x - screen.origin.x - screen.size.width);
                    // The distance from the cursor to the top of the main screen
                    float d3 = fabs(lastPoint.y - screen.origin.y);
                    // The distance from the cursor to the bottom of the main screen
                    float d4 = fabs(lastPoint.y - screen.origin.y - screen.size.height);
                    // The distance from the cursor to the center of the main screen in the horizontal direction
                    float d5 = fabs(currentPoint.x - screen.origin.x - screen.size.width/2);
                    // The distance from the cursor to the center of the main screen in the vertical direction
                    float d6 = fabs(currentPoint.y - screen.origin.y - screen.size.height/2);
 
                    DebugLog(@"d1: %f, d2: %f, d3: %f, d4: %f, d5: %f, d6: %f", d1, d2, d3, d4, d5, d6);

                    const float threshold = 30.0;
                    if ((d1 < threshold || d2 < threshold || d3 < threshold || d4 < threshold) &&
                        d5 < threshold && d6 < threshold) {
                        CFRelease(mouseDraggedEvent);
                        CFRelease(mouseDownEvent);
                        mouseDownEvent = mouseDraggedEvent = NULL;
                        shouldShow = NO;
                        resetDirection();
                        break;
                    }
                    
                }
                
                if (mouseDraggedEvent) {
                    CFRelease(mouseDraggedEvent);
                }
                mouseDraggedEvent = event;
                CFRetain(mouseDraggedEvent);
                
                [windowController handleMouseEvent:mouseEvent];
                updateDirections(mouseEvent);
            }
            break;
        case kCGEventRightMouseUp: {
            DebugLog(@"kCGEventRightMouseUp");
            if (!shouldShow){
                return event;
            }
            
            if (mouseDownEvent) {
                mouseEvent = [NSEvent eventWithCGEvent:event];
                [windowController handleMouseEvent:mouseEvent];
                updateDirections(mouseEvent);
                if (handleGesture(true)) {
                    eventTriggered = YES;
                }
                
                if (!eventTriggered) {
                    CGPoint location = CGEventGetLocation(event);
                    CGEventSetLocation(mouseDownEvent, location);
                    CGEventPost(kCGSessionEventTap, mouseDownEvent);
       
                    // Fix issue #70 dunno why here
                    usleep(1000);
                    CGEventPost(kCGSessionEventTap, event);
                }
                CFRelease(mouseDownEvent);
            }
            
            if (mouseDraggedEvent) {
                CFRelease(mouseDraggedEvent);
            }
            
            mouseDownEvent = mouseDraggedEvent = NULL;
            shouldShow = NO;
            
            resetDirection();
            break;
        }
        case kCGEventScrollWheel: {
            if (!shouldShow || !mouseDownEvent) {
                return event;
            }
            mouseEvent = [NSEvent eventWithCGEvent:event];
            double delta = CGEventGetDoubleValueField(event, kCGScrollWheelEventDeltaAxis1);
            BOOL unnaturalDirection = mouseEvent.isDirectionInvertedFromDevice;
            if (unnaturalDirection) {} // delta *= -1;
            DebugLog(@"scrollWheel delta:%f", delta);
            
            NSTimeInterval current = [NSDate timeIntervalSinceReferenceDate];
            if (current - lastMouseWheelEventTime > 0.3) {
                if (delta > 0) {
                    DebugLog(@"Traditional scroll wheel up!");
                    addDirection('u', true);
                    eventTriggered = YES;
                } else if (delta < 0){
                    DebugLog(@"Traditional scroll wheel down!");
                    addDirection('d', true);
                    eventTriggered = YES;
                }
                lastMouseWheelEventTime = current;
            }
            break;
        }
        case kCGEventTapDisabledByUserInput:
            DebugLog(@"kCGEventTapDisabledByUserInput");
        case kCGEventTapDisabledByTimeout:
            DebugLog(@"kCGEventTapDisabledByTimeout");
            CGEventTapEnable(mouseEventTap, true); // re-enable
            // windowController.enable = isEnable;
            break;
        case kCGEventLeftMouseDown: {
            if (!shouldShow || !mouseDownEvent) {
                return event;
            }
            addDirection('Z', true);
            eventTriggered = YES;
            break;
        }
        default:
            return event;
    }
    
    return NULL;
}

@end
