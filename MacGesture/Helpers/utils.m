
#import <Cocoa/Cocoa.h>
#import <UserNotifications/UserNotifications.h>
#import <ServiceManagement/ServiceManagement.h>
#import "utils.h"

void MGPostNotification(NSString *title, NSString *body, BOOL playSound) {
    UNMutableNotificationContent *content = [UNMutableNotificationContent new];
    content.title = title ?: @"";
    content.body = body ?: @"";
    if (playSound) content.sound = [UNNotificationSound defaultSound];
    UNNotificationRequest *request =
        [UNNotificationRequest requestWithIdentifier:[[NSUUID UUID] UUIDString]
                                             content:content
                                             trigger:nil];
    [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request
                                                          withCompletionHandler:nil];
}

NSData *MGArchive(id<NSSecureCoding> object) {
    if (!object) return nil;
    NSError *error = nil;
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:object requiringSecureCoding:YES error:&error];
    if (!data) NSLog(@"[MGArchive] failed: %@", error);
    return data;
}

id MGUnarchive(NSData *data, NSSet<Class> *classes) {
    if (!data) return nil;
    NSError *error = nil;
    id object = [NSKeyedUnarchiver unarchivedObjectOfClasses:classes fromData:data error:&error];
    if (!object) NSLog(@"[MGUnarchive] failed: %@", error);
    return object;
}

NSSet<Class> *MGPropertyListClasses(void) {
    static NSSet<Class> *classes = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        classes = [NSSet setWithObjects:NSArray.class, NSMutableArray.class,
                   NSDictionary.class, NSMutableDictionary.class,
                   NSString.class, NSNumber.class, nil];
    });
    return classes;
}

// Secure replacement for the deprecated/insecure NSKeyedUnarchiveFromData binding transformer.
// The stock NSSecureUnarchiveFromDataTransformer does NOT allow NSColor, so the color-well
// bindings need this subclass.
@interface MGColorValueTransformer : NSSecureUnarchiveFromDataTransformer @end
@implementation MGColorValueTransformer
+ (NSArray<Class> *)allowedTopLevelClasses {
    return [[super allowedTopLevelClasses] arrayByAddingObject:NSColor.class];
}
@end

void MGRegisterValueTransformers(void) {
    [NSValueTransformer setValueTransformer:[MGColorValueTransformer new]
                                    forName:@"MGColorValueTransformer"];
}

NSString *frontBundleName(void) {
    NSRunningApplication *runningApp = [[NSWorkspace sharedWorkspace] frontmostApplication];
    
    if (!runningApp.bundleIdentifier) {
        return @"";
    }
    return runningApp.bundleIdentifier;
}

BOOL wildcardArray(NSString *bundleName, NSArray *wildFilters, BOOL ignoreCase) {
    if (ignoreCase) {
        bundleName = [bundleName lowercaseString];
    }
    BOOL result = NO;
    for (NSString *filter in wildFilters) {
        NSString *wildcard = filter;
        if (ignoreCase) {
            wildcard = [filter lowercaseString];
        }
        BOOL negate = NO;
        if([wildcard hasPrefix:@"!"]) {
            negate = YES;
            wildcard = [wildcard substringFromIndex:1];
        }
        NSPredicate *pred = [NSPredicate predicateWithFormat:@"self LIKE %@", wildcard];
        BOOL match = [pred evaluateWithObject:bundleName];
        if (match && !negate) {
            result = YES;
        } else if (match && negate) {
            result = NO;
        }
    }
    return result;
}

BOOL wildcardString(NSString *bundleName, NSString *wildFilter, BOOL ignoreCase) {
    NSArray *filterArray = [wildFilter componentsSeparatedByCharactersInSet:
                            [NSCharacterSet characterSetWithCharactersInString:@"|\n"]];
    return wildcardArray(bundleName, filterArray, ignoreCase);
}

@implementation NSArray (Utils)

- (NSArray<__kindof NSObject *> *)mappedArrayUsingBlock:(__kindof NSObject *(NS_NOESCAPE ^)(id, NSUInteger))block
{
    NSMutableArray *results = [NSMutableArray arrayWithCapacity:self.count];

    [self enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        id remapped = block(obj, idx);
        if (remapped) [results addObject:remapped];
    }];

    return results;
}

@end

@implementation NSObject (Utils)

- (id)parsedKindOf:(Class)class
{
    return [self isKindOfClass:class] ? self : nil;
}

@end

@implementation LoginServicesHelper

// macOS 13+: SMAppService replaces the deprecated LSSharedFileList login-item API.
+ (BOOL)isLoginItem {
    return SMAppService.mainAppService.status == SMAppServiceStatusEnabled;
}

+ (void)makeLoginItemActive:(BOOL)active {
    NSError *error = nil;
    BOOL ok = active
        ? [SMAppService.mainAppService registerAndReturnError:&error]
        : [SMAppService.mainAppService unregisterAndReturnError:&error];
    if (!ok)
        NSLog(@"[LoginServicesHelper] failed to %@ login item: %@",
              active ? @"register" : @"unregister", error);
}

@end
