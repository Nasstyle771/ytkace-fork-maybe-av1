#import "Hooking.h"
#import <os/lock.h>

static os_unfair_lock s_hookLock = OS_UNFAIR_LOCK_INIT;
static NSMutableSet<NSString *> *s_hookKeys = nil;

static NSMutableSet<NSString *> *YTKACEGetHookKeys(void) {
    if (s_hookKeys == nil) {
        s_hookKeys = [NSMutableSet setWithCapacity:64];
    }
    return s_hookKeys;
}

static BOOL YTKACEInstallHook(NSString *className,
                              NSString *selectorName,
                              BOOL classMethod,
                              IMP replacement,
                              IMP *originalStorage) {
    if (className.length == 0 || selectorName.length == 0 || replacement == NULL) {
        return NO;
    }

    Class cls = NSClassFromString(className);
    if (cls == Nil) {
        return NO;
    }

    Class targetClass = classMethod ? object_getClass(cls) : cls;
    if (targetClass == Nil) {
        return NO;
    }

    SEL selector = NSSelectorFromString(selectorName);
    Method method = class_getInstanceMethod(targetClass, selector);
    if (method == NULL) {
        return NO;
    }

    NSString *key = [NSString stringWithFormat:@"%@|%@|%@",
                     className,
                     classMethod ? @"+" : @"-",
                     selectorName];

    os_unfair_lock_lock(&s_hookLock);
    if ([YTKACEGetHookKeys() containsObject:key]) {
        os_unfair_lock_unlock(&s_hookLock);
        return YES;
    }

    IMP original = method_getImplementation(method);
    const char *types = method_getTypeEncoding(method);

    BOOL added = class_addMethod(targetClass, selector, replacement, types);
    if (!added) {
        Method directMethod = class_getInstanceMethod(targetClass, selector);
        if (directMethod == NULL) {
            os_unfair_lock_unlock(&s_hookLock);
            return NO;
        }
        IMP prev = method_setImplementation(directMethod, replacement);
        if (prev != NULL) {
            original = prev;
        }
    }

    if (originalStorage != NULL) {
        *originalStorage = original;
    }
    [YTKACEGetHookKeys() addObject:key];
    os_unfair_lock_unlock(&s_hookLock);
    return YES;
}

BOOL YTKACEInstallInstanceHook(NSString *className,
                               NSString *selectorName,
                               IMP replacement,
                               IMP *originalStorage) {
    return YTKACEInstallHook(className, selectorName, NO, replacement, originalStorage);
}

BOOL YTKACEInstallClassHook(NSString *className,
                            NSString *selectorName,
                            IMP replacement,
                            IMP *originalStorage) {
    return YTKACEInstallHook(className, selectorName, YES, replacement, originalStorage);
}

BOOL YTKACEAddInstanceMethod(NSString *className,
                             NSString *selectorName,
                             IMP implementation,
                             const char *typeEncoding) {
    if (className.length == 0 || selectorName.length == 0 ||
        implementation == NULL || typeEncoding == NULL) {
        return NO;
    }

    Class cls = NSClassFromString(className);
    if (cls == Nil) {
        return NO;
    }

    NSString *key = [NSString stringWithFormat:@"%@|add|%@", className, selectorName];
    os_unfair_lock_lock(&s_hookLock);
    if ([YTKACEGetHookKeys() containsObject:key]) {
        os_unfair_lock_unlock(&s_hookLock);
        return YES;
    }

    BOOL added = class_addMethod(cls,
                                 NSSelectorFromString(selectorName),
                                 implementation,
                                 typeEncoding);
    if (added) {
        [YTKACEGetHookKeys() addObject:key];
        [YTKACEGetHookKeys() addObject:
            [NSString stringWithFormat:@"%@|-|%@", className, selectorName]];
    }
    os_unfair_lock_unlock(&s_hookLock);
    return added;
}

NSUInteger YTKACEInstalledHookCount(void) {
    os_unfair_lock_lock(&s_hookLock);
    NSUInteger count = s_hookKeys != nil ? s_hookKeys.count : 0;
    os_unfair_lock_unlock(&s_hookLock);
    return count;
}
