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
