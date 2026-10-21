//
//  MacGestureTests.m
//  MacGestureTests
//
//  Created by Charles Ross on 11/2/13.
//  Copyright (c) 2013 MacGesture. All rights reserved.
//

#import <XCTest/XCTest.h>

#import "AppDelegate.h"

// Issue #42: holding Control while pressing the right button temporarily
// disables the gesture for that whole drag. The decision is made from the
// flags of the right-mouse-down event alone, so pressing or releasing Control
// mid-drag cannot interrupt a gesture that already started.
@interface MGControlSuppressionTests : XCTestCase

@end

@implementation MGControlSuppressionTests

- (void)testControlAtRightMouseDownSuppressesGestureForDrag
{
    XCTAssertTrue(MGShouldSuppressGestureForDrag(kCGEventFlagMaskControl));
}

- (void)testControlTogetherWithOtherModifiersStillSuppresses
{
    XCTAssertTrue(MGShouldSuppressGestureForDrag(
        kCGEventFlagMaskControl | kCGEventFlagMaskShift | kCGEventFlagMaskCommand));
}

- (void)testNoModifiersDoesNotSuppress
{
    XCTAssertFalse(MGShouldSuppressGestureForDrag(0));
}

- (void)testOtherModifiersAloneDoNotSuppress
{
    XCTAssertFalse(MGShouldSuppressGestureForDrag(kCGEventFlagMaskShift));
    XCTAssertFalse(MGShouldSuppressGestureForDrag(kCGEventFlagMaskCommand));
    XCTAssertFalse(MGShouldSuppressGestureForDrag(kCGEventFlagMaskAlternate));
    XCTAssertFalse(MGShouldSuppressGestureForDrag(kCGEventFlagMaskSecondaryFn));
}

@end
