//
//  AppleScriptsList.h
//  MacGesture
//
//  Created by iMac on 3/19/16.
//  Copyright © 2016 Codefalling. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface AppleScriptsList : NSObject

+ (AppleScriptsList *)sharedAppleScriptsList;

- (void)addAppleScript:(NSString *)title
                script:(NSString *)script;

- (void)reInit;

- (void)save;

- (NSInteger)count;

// The index parameters below are NSInteger rather than NSUInteger on purpose:
// callers routinely pass -[NSTableView selectedRow], which is -1 when nothing
// is selected. As NSUInteger that sentinel silently becomes a huge value and
// blows up as an out-of-bounds subscript. Every one of these methods bounds
// checks its index and is a no-op (getters return @"") when it is out of range.

- (NSString *)titleAtIndex:(NSInteger)index;

- (NSString *)scriptAtIndex:(NSInteger)index;

- (NSString *)idAtIndex:(NSInteger)index;

- (NSString *)getScriptById:(NSString *)id;

- (NSInteger)getIndexById:(NSString *)id;

- (void)setScriptAtIndex:(NSInteger)index script:(NSString *)script;

- (void)setTitleAtIndex:(NSInteger)index title:(NSString *)title;

- (void)removeAtIndex:(NSInteger)index;

@property (strong, atomic) NSMutableArray<NSMutableDictionary *> *appleScriptsList;

@end
