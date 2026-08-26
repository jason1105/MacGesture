//
//  main.m
//  MenuBarApp
//
//  Created by Charles Ross on 11/2/13.
//  Copyright (c) 2013 MacGesture. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "utils.h"

int main(int argc, const char *argv[]) {
    MGRegisterValueTransformers();   // must run before any nib/binding loads
    return NSApplicationMain(argc, argv);
}
