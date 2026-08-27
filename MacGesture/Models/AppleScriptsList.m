//
//  AppleScriptsList.m
//  MacGesture
//
//  Created by iMac on 3/19/16.
//  Copyright © 2016 Codefalling. All rights reserved.
//

#import "AppleScriptsList.h"
#import "utils.h"

@implementation AppleScriptsList

// From http://stackoverflow.com/questions/7997594/singleton-with-arc
+ (AppleScriptsList *)sharedAppleScriptsList {
    static dispatch_once_t pred;
    static AppleScriptsList *sharedInstance = nil;
    dispatch_once(&pred, ^{
        sharedInstance = [[super alloc] init];
    });
    return sharedInstance;
}

- (void)reInit {
    [_appleScriptsList removeAllObjects];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSData *data;
        NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
        data = [userDefaults objectForKey:@"appleScripts"];
        _appleScriptsList = [MGUnarchive(data, MGPropertyListClasses()) mutableCopy] ?: [NSMutableArray array];
        if (_appleScriptsList == nil) {
            _appleScriptsList = [[NSMutableArray alloc] init];
        }
    }
    
    return self;
}

- (NSData *)nsData {
    return MGArchive(_appleScriptsList);
}

- (void)save {
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setObject:self.nsData forKey:@"appleScripts"];
    [userDefaults synchronize];
}

- (NSInteger)count {
    return [_appleScriptsList count];
}

// Guards every index-based accessor below. -[NSTableView selectedRow] returns
// -1 when there is no selection, and rows can disappear between a control being
// edited and the edit being committed, so an out-of-range index here is a
// routine occurrence rather than a programming error.
- (BOOL)isValidIndex:(NSInteger)index {
    return index >= 0 && index < (NSInteger)_appleScriptsList.count;
}

- (NSString *)titleAtIndex:(NSInteger)index {
    if (![self isValidIndex:index]) return @"";
    return _appleScriptsList[index][@"title"];
}

- (NSString *)scriptAtIndex:(NSInteger)index {
    if (![self isValidIndex:index]) return @"";
    return _appleScriptsList[index][@"script"];
}

- (NSString *)idAtIndex:(NSInteger)index {
    if (![self isValidIndex:index]) return @"";
    return _appleScriptsList[index][@"id"];
}

- (NSString *)getScriptById:(NSString *)id {
    for (NSMutableDictionary *dict in _appleScriptsList) {
        if ([dict[@"id"] isEqualToString:id]) {
            return dict[@"script"];
        }
    }
    return @"";
}

- (NSInteger)getIndexById:(NSString *)id {
    NSInteger i = 0;
    for (NSMutableDictionary *dict in _appleScriptsList) {
        if ([dict[@"id"] isEqualToString:id]) {
            return i;
        }
        i++;
    }
    return -1;
}

- (void)setScriptAtIndex:(NSInteger)index script:(NSString *)script {
    if (![self isValidIndex:index]) return;
    _appleScriptsList[index][@"script"] = script;
}

- (void)setTitleAtIndex:(NSInteger)index title:(NSString *)title {
    if (![self isValidIndex:index]) return;
    _appleScriptsList[index][@"title"] = title;
}

- (void)addAppleScript:(NSString *)title
                script:(NSString *)script {
    NSMutableDictionary *array = [[NSMutableDictionary alloc] init];
    array[@"title"] = title;
    array[@"script"] = script;
    array[@"id"] = [[NSProcessInfo processInfo] globallyUniqueString];
    [_appleScriptsList addObject:array];
}

- (void)removeAtIndex:(NSInteger)index {
    if (![self isValidIndex:index]) return;
    [_appleScriptsList removeObjectAtIndex:index];
}

@end
