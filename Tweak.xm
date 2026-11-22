//
//  Tweak.xm
//  企业微信（com.tencent.ww）定位接管
//
//  覆盖层级（由内到外）：
//    L1  CLLocationManager delegate —— iOS 上取 GPS 的必经之路，代理包装后改写回调数组
//    L2  TencentLBSLocation —— 腾讯定位 SDK 的结果对象，企业微信打卡链路（WWKLocationRetriever）走这里
//    L3  CLLocation -coordinate —— 严格模式兜底，覆盖直接构造/读取 CLLocation 的路径
//    L4  WWKLocation* / WWKAttendance* —— 深度模式，业务层取点方法（版本漂移时启用）
//
//  坐标系：腾讯定位 SDK 默认输出 GCJ-02，CoreLocation 输出 WGS-84。
//  两层必须分别喂对应坐标系，否则落点会整体偏移 300~600m。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreLocation/CoreLocation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <math.h>
#import <string.h>
#import <stdlib.h>

#import "CLXShared.h"
#import "CLXStore.h"
#import "CLXSession.h"
#import "CLXGuard.h"
#import "CLXPanelController.h"

#pragma mark - 全局状态

// 腾讯定位 SDK 的坐标系设置：0 = GCJ-02（SDK 默认），1 = WGS-84
static NSInteger gLBSCoordinateType = 0;

// CLLocation -coordinate 的原始实现（永远返回"未被改写"的值）
static CLLocationCoordinate2D (*gOrigCoordinate)(id, SEL);

// 腾讯定位 SDK 原始实现
static void (*gOrigLBSSetType)(id, SEL, NSInteger);
static CLLocationCoordinate2D (*gOrigLBSCoord)(id, SEL);
static CLLocation *(*gOrigLBSLocation)(id, SEL);
static double (*gOrigLBSLatitude)(id, SEL);
static double (*gOrigLBSLongitude)(id, SEL);

// 合成对象标记
static char kSynthKey;

static inline BOOL CLXIsSynthetic(id obj) {
    return obj ? (objc_getAssociatedObject(obj, &kSynthKey) != nil) : NO;
}

static inline id CLXMarkSynthetic(id obj) {
    if (obj) objc_setAssociatedObject(obj, &kSynthKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return obj;
}

// 输出坐标系选择
static BOOL CLXWantGCJ(void) {
    NSInteger mode = [CLXStore coordinateMode];
    if (mode == 1) return YES;    // 强制 GCJ-02
    if (mode == 2) return NO;     // 强制 WGS-84
    return (gLBSCoordinateType != 1);   // 自动：跟随 SDK 配置，默认 GCJ-02
}

// 记录真实样本（只取未被改写的值）
static void CLXFeedReal(CLLocation *loc) {
    if (!loc) return;
    CLLocationCoordinate2D c = gOrigCoordinate ? gOrigCoordinate(loc, @selector(coordinate))
                                               : CLXInvalidCoordinate();
    if (!CLXCoordinateValid(c)) return;
    [[CLXSession shared] noteRealCoordinate:c
                                   altitude:loc.altitude
                                   accuracy:loc.horizontalAccuracy];
}

#pragma mark - 窗口 & 入口

static UIWindow *CLXKeyWindow(void) {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                if (w.isKeyWindow) return w;
            }
        }
    }
    NSArray<UIWindow *> *wins = [UIApplication sharedApplication].windows;
    for (UIWindow *w in wins.reverseObjectEnumerator) {
        if (w.isKeyWindow) return w;
    }
    return wins.firstObject;
}

static void CLXShowPanel(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = CLXKeyWindow();
        UIViewController *root = window.rootViewController;
        if (!root) return;

        Class panelClass = NSClassFromString(@"CLXPanelController");
        if (!panelClass) return;

        // 找到最上层控制器；已经在展示就不再叠一层
        UIViewController *top = root;
        while (top.presentedViewController) top = top.presentedViewController;
        if ([top isKindOfClass:panelClass]) return;
        if ([top isKindOfClass:[UINavigationController class]] &&
            [((UINavigationController *)top).topViewController isKindOfClass:panelClass]) {
            return;
        }

        CLXPanelController *vc = [[CLXPanelController alloc] init];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        nav.modalPresentationStyle = UIModalPresentationFormSheet;
        [top presentViewController:nav animated:YES completion:nil];
        CLXLog(@"[ui] panel opened");
    });
}

#pragma mark - L3: CLLocation -coordinate（严格模式兜底）

static CLLocationCoordinate2D CLXCoordinateHook(id self, SEL _cmd) {
    if (!gOrigCoordinate) return CLXInvalidCoordinate();
    CLLocationCoordinate2D real = gOrigCoordinate(self, _cmd);

    if (CLXIsSynthetic(self)) return real;
    if (![CLXStore strictMode]) return real;

    CLXSession *s = [CLXSession shared];
    if (![s isActive]) return real;

    if (CLXCoordinateValid(real)) {
        [s noteRealCoordinate:real altitude:-1000 accuracy:-1];
    }
    CLLocationCoordinate2D out = [s currentCoordinate];
    return CLXCoordinateValid(out) ? out : real;
}

#pragma mark - L1: CLLocationManager delegate 代理

@interface CLXLocationProxy : NSObject <CLLocationManagerDelegate>
@property (nonatomic, weak) id target;
@end

@implementation CLXLocationProxy

- (void)locationManager:(CLLocationManager *)manager
     didUpdateLocations:(NSArray<CLLocation *> *)locations {
    CLXFeedReal(locations.lastObject);

    CLXSession *session = [CLXSession shared];
    NSArray<CLLocation *> *outgoing = locations;
    CLLocation *syn = [session processLocations:locations];
    if (syn) outgoing = @[CLXMarkSynthetic(syn)];

    id target = self.target;
    if ([target respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
        [target locationManager:manager didUpdateLocations:outgoing];
    }
}

- (void)locationManager:(CLLocationManager *)manager
     didUpdateToLocation:(CLLocation *)newLocation
            fromLocation:(CLLocation *)oldLocation {
    CLXFeedReal(newLocation);

    NSArray *arr = newLocation ? @[newLocation] : @[];
    CLLocation *syn = [[CLXSession shared] processLocations:arr];

    id target = self.target;
    if ([target respondsToSelector:@selector(locationManager:didUpdateToLocation:fromLocation:)]) {
        [target locationManager:manager
              didUpdateToLocation:(syn ? CLXMarkSynthetic(syn) : newLocation)
                     fromLocation:oldLocation];
    }
}

- (BOOL)respondsToSelector:(SEL)aSelector {
    if (aSelector == @selector(locationManager:didUpdateLocations:)) return YES;
    if ([super respondsToSelector:aSelector]) return YES;
    return [self.target respondsToSelector:aSelector];
}

- (BOOL)conformsToProtocol:(Protocol *)aProtocol {
    if ([super conformsToProtocol:aProtocol]) return YES;
    return [self.target conformsToProtocol:aProtocol];
}

- (id)forwardingTargetForSelector:(SEL)aSelector {
    if ([self.target respondsToSelector:aSelector]) return self.target;
    return [super forwardingTargetForSelector:aSelector];
}

@end

static char kProxyKey;

%hook CLLocationManager

- (void)setDelegate:(id<CLLocationManagerDelegate>)delegate {
    if (!delegate) {
        %orig(nil);
        return;
    }
    if ([delegate isKindOfClass:[CLXLocationProxy class]]) {
        %orig(delegate);
        return;
    }
    CLXLocationProxy *proxy = [[CLXLocationProxy alloc] init];
    proxy.target = delegate;
    objc_setAssociatedObject(self, &kProxyKey, proxy, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig(proxy);
    CLXLog(@"[L1] delegate wrapped: %s", class_getName([delegate class]));
}

- (CLLocation *)location {
    CLLocation *real = %orig;
    CLXFeedReal(real);

    CLXSession *session = [CLXSession shared];
    if (![session isActive]) return real;

    CLLocation *syn = [session currentLocation];
    return syn ? CLXMarkSynthetic(syn) : real;
}

%end

#pragma mark - L2: 腾讯定位 SDK

static void CLXLBSSetCoordinateType(id self, SEL _cmd, NSInteger type) {
    gLBSCoordinateType = type;
    CLXLog(@"[L2] TencentLBS coordinateType = %ld", (long)type);
    if (gOrigLBSSetType) gOrigLBSSetType(self, _cmd, type);
}

static CLLocationCoordinate2D CLXLBSCoordinate(id self, SEL _cmd) {
    CLLocationCoordinate2D real = gOrigLBSCoord ? gOrigLBSCoord(self, _cmd) : CLXInvalidCoordinate();

    CLXSession *session = [CLXSession shared];
    if (![session isActive]) return real;

    if (CLXCoordinateValid(real)) {
        // SDK 输出什么坐标系，就转回 WGS-84 存进引擎
        CLLocationCoordinate2D wgs = (gLBSCoordinateType == 1) ? real : CLXGCJ02ToWGS84(real);
        [session noteRealCoordinate:wgs altitude:-1000 accuracy:-1];
    }

    CLLocationCoordinate2D out = CLXWantGCJ() ? [session currentCoordinateGCJ]
                                              : [session currentCoordinate];
    return CLXCoordinateValid(out) ? out : real;
}

static CLLocation *CLXLBSCLLocation(id self, SEL _cmd) {
    CLLocation *real = gOrigLBSLocation ? gOrigLBSLocation(self, _cmd) : nil;
    CLXSession *session = [CLXSession shared];
    if (![session isActive]) return real;
    CLLocation *syn = [session currentLocation];
    return syn ? CLXMarkSynthetic(syn) : real;
}

static double CLXLBSLatitude(id self, SEL _cmd) {
    double real = gOrigLBSLatitude ? gOrigLBSLatitude(self, _cmd) : 0.0;
    CLXSession *session = [CLXSession shared];
    if (![session isActive]) return real;
    CLLocationCoordinate2D out = CLXWantGCJ() ? [session currentCoordinateGCJ]
                                              : [session currentCoordinate];
    return CLXCoordinateValid(out) ? out.latitude : real;
}

static double CLXLBSLongitude(id self, SEL _cmd) {
    double real = gOrigLBSLongitude ? gOrigLBSLongitude(self, _cmd) : 0.0;
    CLXSession *session = [CLXSession shared];
    if (![session isActive]) return real;
    CLLocationCoordinate2D out = CLXWantGCJ() ? [session currentCoordinateGCJ]
                                              : [session currentCoordinate];
    return CLXCoordinateValid(out) ? out.longitude : real;
}

static BOOL CLXHookMethod(Class cls, const char *selName, IMP replacement, IMP *outOrig) {
    if (!cls) return NO;
    SEL sel = sel_registerName(selName);
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return NO;
    IMP cur = method_getImplementation(m);
    if (cur == replacement) return NO;
    if (outOrig) *outOrig = cur;

    // 只覆盖类自身定义的方法。若方法是从父类继承来的，
    // class_addMethod 会成功，从而不会污染父类实现。
    if (!class_addMethod(cls, sel, replacement, method_getTypeEncoding(m))) {
        method_setImplementation(m, replacement);
    }
    return YES;
}

static void CLXInstallLBSHooks(void) {
    Class mgr = NSClassFromString(@"TencentLBSLocationManager");
    if (mgr) {
        CLXHookMethod(mgr, "setCoordinateType:", (IMP)CLXLBSSetCoordinateType, (IMP *)&gOrigLBSSetType);
    }

    Class loc = NSClassFromString(@"TencentLBSLocation");
    if (loc) {
        CLXHookMethod(loc, "coordinate", (IMP)CLXLBSCoordinate, (IMP *)&gOrigLBSCoord);
        CLXHookMethod(loc, "location", (IMP)CLXLBSCLLocation, (IMP *)&gOrigLBSLocation);
        CLXHookMethod(loc, "latitude", (IMP)CLXLBSLatitude, (IMP *)&gOrigLBSLatitude);
        CLXHookMethod(loc, "longitude", (IMP)CLXLBSLongitude, (IMP *)&gOrigLBSLongitude);
    }

    CLXLog(@"[L2] TencentLBS manager=%d location=%d", mgr ? 1 : 0, loc ? 1 : 0);
}

#pragma mark - L4: 深度模式（业务层取点）

#define CLX_DEEP_MAX 128

typedef struct {
    Class cls;
    SEL   sel;
    IMP   orig;
} CLXDeepEntry;

static CLXDeepEntry gDeep[CLX_DEEP_MAX];
static int gDeepCount = 0;

static IMP CLXDeepFindOrig(Class cls, SEL _cmd) {
    for (int i = 0; i < gDeepCount; i++) {
        if (gDeep[i].sel == _cmd && gDeep[i].cls == cls) return gDeep[i].orig;
    }
    for (int i = 0; i < gDeepCount; i++) {
        if (gDeep[i].sel == _cmd && class_isSubclass(cls, gDeep[i].cls)) return gDeep[i].orig;
    }
    return NULL;
}

static CLLocationCoordinate2D CLXDeepCoordinate(id self, SEL _cmd) {
    IMP orig = CLXDeepFindOrig(object_getClass(self), _cmd);
    CLLocationCoordinate2D real = orig ? ((CLLocationCoordinate2D (*)(id, SEL))orig)(self, _cmd)
                                       : CLXInvalidCoordinate();

    CLXSession *session = [CLXSession shared];
    if (![session isActive]) return real;

    if (CLXCoordinateValid(real)) {
        [session noteRealCoordinate:real altitude:-1000 accuracy:-1];
    }
    CLLocationCoordinate2D out = CLXWantGCJ() ? [session currentCoordinateGCJ]
                                              : [session currentCoordinate];
    return CLXCoordinateValid(out) ? out : real;
}

static BOOL CLXClassHasPrefix(const char *name, const char **prefixes) {
    for (int i = 0; prefixes[i]; i++) {
        if (strncmp(name, prefixes[i], strlen(prefixes[i])) == 0) return YES;
    }
    return NO;
}

static void CLXInstallDeepHooks(void) {
    if (![CLXStore deepMode]) return;

    static const char *prefixes[] = { "WWKLocation", "WWKAttendance", "WWKCheckin", NULL };

    int total = objc_getClassList(NULL, 0);
    if (total <= 0) return;
    Class *classes = (Class *)malloc(sizeof(Class) * (size_t)total);
    if (!classes) return;
    total = objc_getClassList(classes, total);

    int hooked = 0;
    for (int i = 0; i < total && gDeepCount < CLX_DEEP_MAX; i++) {
        Class cls = classes[i];
        if (!cls) continue;
        const char *name = class_getName(cls);
        if (!name || !CLXClassHasPrefix(name, prefixes)) continue;

        unsigned int count = 0;
        Method *methods = class_copyMethodList(cls, &count);
        if (!methods) continue;
        for (unsigned int j = 0; j < count && gDeepCount < CLX_DEEP_MAX; j++) {
            Method m = methods[j];
            const char *enc = method_getTypeEncoding(m);
            if (!enc || strncmp(enc, "{CLLocationCoordinate2D=", 24) != 0) continue;
            if (method_getNumberOfArguments(m) != 2) continue;   // 只要无参 getter

            IMP cur = method_getImplementation(m);
            if (cur == (IMP)CLXDeepCoordinate) continue;

            gDeep[gDeepCount].cls = cls;
            gDeep[gDeepCount].sel = method_getName(m);
            gDeep[gDeepCount].orig = cur;
            gDeepCount++;
            method_setImplementation(m, (IMP)CLXDeepCoordinate);
            hooked++;
            CLXLog(@"[L4] deep hook %s -%s", name, sel_getName(method_getName(m)));
        }
        free(methods);
    }

    free(classes);
    CLXLog(@"[L4] deep hooks installed = %d (enabled=%d)", hooked, (int)[CLXStore deepMode]);
}

#pragma mark - 诊断探测

static void CLXDumpClassInfo(const char *name) {
    Class cls = NSClassFromString(@(name));
    if (!cls) {
        CLXLog(@"probe: %s MISSING", name);
        return;
    }
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    NSMutableArray *items = [NSMutableArray array];
    for (unsigned int i = 0; i < count && i < 400; i++) {
        const char *sel = sel_getName(method_getName(methods[i]));
        const char *enc = method_getTypeEncoding(methods[i]);
        [items addObject:[NSString stringWithFormat:@"%s %s", sel, enc ? enc : ""]];
    }
    if (methods) free(methods);
    CLXLog(@"probe: %s count=%u :: %@", name, count, [items componentsJoinedByString:@" | "]);
}

static void CLXRunProbe(void) {
    if (![CLXStore diagnosticsEnabled]) return;
    @autoreleasepool {
        static const char *classes[] = {
            "WWKLocationRetriever",
            "WWKLocationRetrieverBaseTask",
            "WWKLocationItem",
            "WWKAttendanceCheckViewController",
            "WWKAttendanceBinaryCheckViewController",
            "TencentLBSLocationManager",
            "TencentLBSLocation",
            NULL
        };
        for (int i = 0; classes[i]; i++) CLXDumpClassInfo(classes[i]);
    }
}

#pragma mark - 隐藏入口（连续点击 5 次）

// 用 UIApplication 而不是 UIWindow：App 自己可能重写 UIWindow 子类的 sendEvent:，
// 而 UIApplication 的事件入口几乎不会被业务代码覆盖。
// 进入方式：任意界面 1.2 秒内连点 5 次，且点位基本不移动。
%hook UIApplication

- (void)sendEvent:(UIEvent *)event {
    %orig;

    if (event.type != UIEventTypeTouches) return;

    for (UITouch *touch in event.allTouches) {
        if (touch.phase != UITouchPhaseEnded) continue;

        static NSInteger tapCount = 0;
        static NSTimeInterval lastTap = 0;
        static CGPoint firstPoint = {0, 0};

        NSTimeInterval now = CFAbsoluteTimeGetCurrent();
        CGPoint p = [touch locationInWindow:touch.window];

        if (now - lastTap > 1.2) {
            tapCount = 0;
            firstPoint = p;
        }
        lastTap = now;
        tapCount++;

        if (tapCount >= 5) {
            BOOL near = (hypot(p.x - firstPoint.x, p.y - firstPoint.y) < 90.0);
            tapCount = 0;
            if (near) CLXShowPanel();
        }
        break;
    }
}

%end

#pragma mark - 初始化

%ctor {
    @autoreleasepool {
        // 无论如何先装 CLLocation -coordinate 的钩子：它同时承担"取真值"的职责。
        // 是否真正改写由 strictMode 决定。
        Method m = class_getInstanceMethod([CLLocation class], @selector(coordinate));
        if (m) {
            gOrigCoordinate = (CLLocationCoordinate2D (*)(id, SEL))method_getImplementation(m);
            method_setImplementation(m, (IMP)CLXCoordinateHook);
        }

        CLXInstallLBSHooks();

        CLXLog(@"[init] libclx loaded, bundle=%@", [[NSBundle mainBundle] bundleIdentifier]);

        // 腾讯定位 SDK 可能是延迟加载的，1.5s 后再挂一次（CLXHookMethod 幂等）
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            CLXInstallLBSHooks();
        });

        // 深度模式与类探测放到 4s 后，避开启动阶段最密集的检测窗口
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            CLXInstallDeepHooks();
            CLXRunProbe();
        });
    }
}
