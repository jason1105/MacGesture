//
//  MacGestureTests.m
//  MacGestureTests
//
//  Created by Charles Ross on 11/2/13.
//  Copyright (c) 2013 MacGesture. All rights reserved.
//

#import <XCTest/XCTest.h>

#import "AppDelegate.h"

// Issue #44: which modifier key held while pressing the right button
// temporarily disables the gesture for that whole drag is user-configurable
// (Off / Command / Control / Option / fn, single choice, default Command).
// The decision is made from the flags of the right-mouse-down event alone, so
// pressing or releasing modifiers mid-drag cannot interrupt a gesture that
// already started.
@interface MGSuppressModifierTests : XCTestCase

@end

@implementation MGSuppressModifierTests

#pragma mark - Pure decision core (no NSUserDefaults involved)

- (void)testAbsentValueDefaultsToCommand
{
    XCTAssertTrue(MGShouldSuppressGestureForDragWithModifier(kCGEventFlagMaskCommand, nil));
    XCTAssertFalse(MGShouldSuppressGestureForDragWithModifier(kCGEventFlagMaskControl, nil));
}

- (void)testEachModifierExplicitlySuppresses
{
    XCTAssertTrue(MGShouldSuppressGestureForDragWithModifier(kCGEventFlagMaskCommand, @"command"));
    XCTAssertTrue(MGShouldSuppressGestureForDragWithModifier(kCGEventFlagMaskControl, @"control"));
    XCTAssertTrue(MGShouldSuppressGestureForDragWithModifier(kCGEventFlagMaskAlternate, @"option"));
    XCTAssertTrue(MGShouldSuppressGestureForDragWithModifier(kCGEventFlagMaskSecondaryFn, @"function"));
}

- (void)testOnlyTheConfiguredModifierSuppresses
{
    // Configured Control must not fire on Option, and vice versa.
    XCTAssertFalse(MGShouldSuppressGestureForDragWithModifier(kCGEventFlagMaskAlternate, @"control"));
    XCTAssertFalse(MGShouldSuppressGestureForDragWithModifier(kCGEventFlagMaskControl, @"option"));
    // And must not fire on any other single modifier either.
    XCTAssertFalse(MGShouldSuppressGestureForDragWithModifier(kCGEventFlagMaskCommand, @"control"));
    XCTAssertFalse(MGShouldSuppressGestureForDragWithModifier(kCGEventFlagMaskSecondaryFn, @"control"));
    XCTAssertFalse(MGShouldSuppressGestureForDragWithModifier(kCGEventFlagMaskCommand, @"option"));
    XCTAssertFalse(MGShouldSuppressGestureForDragWithModifier(kCGEventFlagMaskSecondaryFn, @"option"));
    XCTAssertFalse(MGShouldSuppressGestureForDragWithModifier(kCGEventFlagMaskControl, @"command"));
    XCTAssertFalse(MGShouldSuppressGestureForDragWithModifier(kCGEventFlagMaskAlternate, @"command"));
    XCTAssertFalse(MGShouldSuppressGestureForDragWithModifier(kCGEventFlagMaskShift, @"command"));
    XCTAssertFalse(MGShouldSuppressGestureForDragWithModifier(kCGEventFlagMaskControl, @"function"));
    // The configured modifier combined with unrelated modifiers still counts
    // (same semantics issue #42 had for Control).
    XCTAssertTrue(MGShouldSuppressGestureForDragWithModifier(
        kCGEventFlagMaskCommand | kCGEventFlagMaskShift, @"command"));
}

- (void)testNoneDisablesSuppressionForEveryKey
{
    XCTAssertFalse(MGShouldSuppressGestureForDragWithModifier(kCGEventFlagMaskCommand, @"none"));
    XCTAssertFalse(MGShouldSuppressGestureForDragWithModifier(kCGEventFlagMaskControl, @"none"));
    XCTAssertFalse(MGShouldSuppressGestureForDragWithModifier(kCGEventFlagMaskAlternate, @"none"));
    XCTAssertFalse(MGShouldSuppressGestureForDragWithModifier(kCGEventFlagMaskSecondaryFn, @"none"));
    // Even every modifier held at once must not suppress.
    XCTAssertFalse(MGShouldSuppressGestureForDragWithModifier(
        kCGEventFlagMaskCommand | kCGEventFlagMaskControl | kCGEventFlagMaskAlternate |
        kCGEventFlagMaskSecondaryFn | kCGEventFlagMaskShift, @"none"));
}

- (void)testNoModifierPressedNeverSuppresses
{
    XCTAssertFalse(MGShouldSuppressGestureForDragWithModifier(0, nil));
    XCTAssertFalse(MGShouldSuppressGestureForDragWithModifier(0, @"command"));
    XCTAssertFalse(MGShouldSuppressGestureForDragWithModifier(0, @"control"));
    XCTAssertFalse(MGShouldSuppressGestureForDragWithModifier(0, @"option"));
    XCTAssertFalse(MGShouldSuppressGestureForDragWithModifier(0, @"function"));
    XCTAssertFalse(MGShouldSuppressGestureForDragWithModifier(0, @"none"));
}

- (void)testUnknownValueFallsBackToCommand
{
    XCTAssertTrue(MGShouldSuppressGestureForDragWithModifier(kCGEventFlagMaskCommand, @"bogus"));
    XCTAssertFalse(MGShouldSuppressGestureForDragWithModifier(kCGEventFlagMaskControl, @"bogus"));
}

#pragma mark - Defaults-backed cache used by the event tap path

- (void)testCachedConfigFollowsDefaultsAfterRefresh
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *saved = [defaults stringForKey:MGSuppressGestureModifierDefaultsKey];

    @try {
        [defaults setObject:@"control" forKey:MGSuppressGestureModifierDefaultsKey];
        MGRefreshSuppressGestureModifierCache();
        XCTAssertTrue(MGShouldSuppressGestureForDrag(kCGEventFlagMaskControl));
        XCTAssertFalse(MGShouldSuppressGestureForDrag(kCGEventFlagMaskCommand));

        [defaults setObject:@"none" forKey:MGSuppressGestureModifierDefaultsKey];
        MGRefreshSuppressGestureModifierCache();
        XCTAssertFalse(MGShouldSuppressGestureForDrag(kCGEventFlagMaskControl));
        XCTAssertFalse(MGShouldSuppressGestureForDrag(kCGEventFlagMaskCommand));

        // No stored value → registered/default behavior is Command.
        [defaults removeObjectForKey:MGSuppressGestureModifierDefaultsKey];
        MGRefreshSuppressGestureModifierCache();
        XCTAssertTrue(MGShouldSuppressGestureForDrag(kCGEventFlagMaskCommand));
        XCTAssertFalse(MGShouldSuppressGestureForDrag(kCGEventFlagMaskControl));
    } @finally {
        if (saved != nil)
            [defaults setObject:saved forKey:MGSuppressGestureModifierDefaultsKey];
        else
            [defaults removeObjectForKey:MGSuppressGestureModifierDefaultsKey];
        MGRefreshSuppressGestureModifierCache();
    }
}

@end

// ============================================================================
// Issue #45 cursor freeze fix: AppleScript rule actions must execute
// asynchronously on a dedicated serial queue, off the CGEventTap callback
// thread. All fixtures are injected in-memory only (archive round-trip via
// initWithNsData:, KVC on the scripts backing store); nothing is persisted
// to NSUserDefaults and no real user rule or script is modified.
// ============================================================================

#import "RulesList.h"
#import "AppleScriptsList.h"

// executeActionAt: is implemented in RulesList.m but not declared in the
// public header; declare it here so tests can call the unit under test.
@interface RulesList (MGFreezeFixTestAccess)
- (bool)executeActionAt:(NSUInteger)index;
@end

static NSString *const kFreezeFixScriptId = @"mg-freeze-fix-test-script";

@interface MGFreezeFixTests : XCTestCase
@end

@implementation MGFreezeFixTests {
    AppleScriptsList *_scripts;
    NSMutableArray *_savedScriptsStorage;
    NSString *_markerPath;
}

- (void)setUp {
    [super setUp];
    _scripts = [AppleScriptsList sharedAppleScriptsList];
    _savedScriptsStorage = [_scripts valueForKey:@"_appleScriptsList"];
    _markerPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"mg-freeze-fix-%@.marker",
            [[NSProcessInfo processInfo] globallyUniqueString]]];
}

- (void)tearDown {
    if (_savedScriptsStorage != nil) {
        [_scripts setValue:_savedScriptsStorage forKey:@"_appleScriptsList"];
    }
    if (_markerPath != nil) {
        [[NSFileManager defaultManager] removeItemAtPath:_markerPath error:NULL];
    }
    [super tearDown];
}

#pragma mark - Fixture injection (in-memory only)

- (RulesList *)injectedRulesListWithSleepScript {
    NSDictionary *scriptEntry = @{
        @"id": kFreezeFixScriptId,
        @"title": @"MGFreezeFixTests sleep script",
        @"script": [NSString stringWithFormat:@"do shell script \"sleep 1; touch '%@'\"", _markerPath],
    };
    [_scripts setValue:[NSMutableArray arrayWithObject:scriptEntry]
              forKey:@"_appleScriptsList"];
    XCTAssertTrue([[_scripts getScriptById:kFreezeFixScriptId] length] > 0,
                  @"script injection failed: getScriptById could not resolve the test script");

    // Same shape addRuleWithDirection:... would build, loaded via the public
    // in-memory loader so nothing is saved to defaults.
    NSDictionary *rule = @{
        @"direction": @"left",
        @"filter": @"*",
        @"filterType": @(FILTER_TYPE_WILDCARD),
        @"actionType": @(ACTION_TYPE_APPLE_SCRIPT),
        @"apple_script_id": kFreezeFixScriptId,
        @"note": @"MGFreezeFixTests",
        @"enabled": @(YES),
    };
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:@[rule]];
    RulesList *rules = [[RulesList alloc] initWithNsData:data];
    XCTAssertEqual([rules count], 1,
                   @"rule injection failed: initWithNsData did not load the test rule");
    return rules;
}

- (BOOL)markerExists {
    return [[NSFileManager defaultManager] fileExistsAtPath:_markerPath];
}

- (void)drainRuleExecutionQueue {
    dispatch_sync([RulesList ruleExecutionQueue], ^{ });
}

#pragma mark - Tests

// executeActionAt: must return without waiting for the AppleScript to finish.
- (void)testAppleScriptActionDoesNotBlockCallerThread {
    RulesList *rules = [self injectedRulesListWithSleepScript];

    NSDate *start = [NSDate date];
    [rules executeActionAt:0];
    NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:start];

    XCTAssertTrue(elapsed < 0.5,
                  @"executeActionAt: blocked the caller for %.3fs; AppleScript actions must run asynchronously",
                  elapsed);
    [self drainRuleExecutionQueue];
}

// The script must run on the serial rule-execution queue, not inline: hold
// the queue with a gate, verify the script has not run when executeActionAt:
// returns, then release and verify completion.
- (void)testAppleScriptActionRunsOnRuleExecutionQueueAfterReturn {
    RulesList *rules = [self injectedRulesListWithSleepScript];
    dispatch_semaphore_t gate = dispatch_semaphore_create(0);
    dispatch_async([RulesList ruleExecutionQueue], ^{
        dispatch_semaphore_wait(gate, DISPATCH_TIME_FOREVER);
    });

    [rules executeActionAt:0];
    XCTAssertFalse([self markerExists],
                   @"script already executed when executeActionAt: returned; it must be queued, not run synchronously");

    dispatch_semaphore_signal(gate);
    [self drainRuleExecutionQueue]; // waits for gate block + sleep 1 script
    XCTAssertTrue([self markerExists],
                  @"script never executed; the async dispatch must still run the AppleScript");
}

@end
