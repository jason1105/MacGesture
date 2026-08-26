
#import <Foundation/Foundation.h>
#import "Foundation+BetterNSCopying.h"

NSString *frontBundleName(void);

BOOL wildcardArray(NSString *bundleName, NSArray *wildFilters, BOOL ignoreCase);

BOOL wildcardString(NSString *bundleName, NSString *wildFilter, BOOL ignoreCase);

/// Post a user notification via UNUserNotificationCenter (replaces the deprecated NSUserNotification).
void MGPostNotification(NSString *title, NSString *body, BOOL playSound);

/// Secure-coding archive/unarchive (replace deprecated non-secure NSKeyedArchiver/Unarchiver).
/// MGArchive: requiringSecureCoding:YES; returns nil on failure.
/// MGUnarchive: unarchivedObjectOfClasses:; returns nil on nil/invalid data. `classes` must list
/// every class in the object graph or unarchiving fails (= silent data loss) — keep it exhaustive.
NSData *MGArchive(id<NSSecureCoding> object);
id MGUnarchive(NSData *data, NSSet<Class> *classes);
/// Allowed-class set for array/dictionary/string/number graphs (rules, AppleScripts).
NSSet<Class> *MGPropertyListClasses(void);
/// Register secure NSValueTransformers (NSColor). MUST run before any nib/binding loads.
void MGRegisterValueTransformers(void);

@interface NSArray<ObjectType> (Utils)

- (NSArray<__kindof NSObject *> *)mappedArrayUsingBlock:(__kindof NSObject *(NS_NOESCAPE ^)(ObjectType obj, NSUInteger idx))block;

@end

@interface NSObject (Utils)

- (id)parsedKindOf:(Class)class;

@end

@interface LoginServicesHelper : NSObject

+ (BOOL)isLoginItem;
+ (void)makeLoginItemActive:(BOOL)active;

@end


#if DEBUG == 0
#define DebugLog(...)
#elif DEBUG == 1
#define DebugLog(...) NSLog(__VA_ARGS__)
#endif
