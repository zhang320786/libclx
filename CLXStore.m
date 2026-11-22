#import "CLXStore.h"
#import <pthread.h>
#import <sys/stat.h>

// ── 存储键（短名，避免明文特征）──────────────────────────
static NSString * const kKEnable  = @"e";
static NSString * const kKLat     = @"a";
static NSString * const kKLng     = @"o";
static NSString * const kKName    = @"n";
static NSString * const kKAlt     = @"h";
static NSString * const kKTravel  = @"t";
static NSString * const kKProfile = @"p";
static NSString * const kKWiFi    = @"w";
static NSString * const kKGuard   = @"g";
static NSString * const kKDiag    = @"d";
static NSString * const kKCoord   = @"c";
static NSString * const kKStrict  = @"s";
static NSString * const kKDeep    = @"x";

static pthread_mutex_t gLock = PTHREAD_MUTEX_INITIALIZER;
static NSMutableDictionary *gDict = nil;
static CFAbsoluteTime gLoadedAt = 0;
static const CFTimeInterval kTTL = 0.35;

#pragma mark - Path

static NSString *StorePath(void) {
    NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches"];
    return [dir stringByAppendingPathComponent:@".ds.v2"];
}

static void EnsureDir(void) {
    NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches"];
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:dir isDirectory:&isDir] || !isDir) {
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    }
}

static NSMutableDictionary *DictLocked(void) {
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (gDict && (now - gLoadedAt) < kTTL) return gDict;

    NSData *data = [NSData dataWithContentsOfFile:StorePath()];
    id obj = nil;
    if (data.length) {
        obj = [NSPropertyListSerialization propertyListWithData:data
                                                       options:NSPropertyListMutableContainers
                                                        format:NULL
                                                         error:NULL];
    }
    gDict = [obj isKindOfClass:[NSMutableDictionary class]] ? obj : [NSMutableDictionary dictionary];
    gLoadedAt = now;
    return gDict;
}

static void SaveLocked(void) {
    if (!gDict) return;
    EnsureDir();
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:gDict
                                                             format:NSPropertyListBinaryFormat_v1_0
                                                            options:0
                                                              error:NULL];
    if (data) {
        [data writeToFile:StorePath() atomically:YES];
    }
    gLoadedAt = CFAbsoluteTimeGetCurrent();
}

static id Get(NSString *key) {
    pthread_mutex_lock(&gLock);
    id v = DictLocked()[key];
    pthread_mutex_unlock(&gLock);
    return v;
}

static void Set(NSString *key, id value) {
    pthread_mutex_lock(&gLock);
    NSMutableDictionary *d = DictLocked();
    if (value) d[key] = value; else [d removeObjectForKey:key];
    SaveLocked();
    pthread_mutex_unlock(&gLock);
}

static double GetDouble(NSString *key, double def) {
    id v = Get(key);
    return [v isKindOfClass:[NSNumber class]] ? [v doubleValue] : def;
}

static BOOL GetBool(NSString *key, BOOL def) {
    id v = Get(key);
    return [v isKindOfClass:[NSNumber class]] ? [v boolValue] : def;
}

#pragma mark -

@implementation CLXStore

+ (void)invalidate {
    pthread_mutex_lock(&gLock);
    gLoadedAt = 0;
    pthread_mutex_unlock(&gLock);
}

+ (BOOL)enabled {
    return GetBool(kKEnable, NO);
}

+ (void)setEnabled:(BOOL)v {
    Set(kKEnable, @(v));
}

+ (BOOL)hasTarget {
    return CLXCoordinateValid([self target]);
}

+ (CLLocationCoordinate2D)target {
    double lat = GetDouble(kKLat, 1000.0);
    double lng = GetDouble(kKLng, 1000.0);
    CLLocationCoordinate2D c = CLLocationCoordinate2DMake(lat, lng);
    return CLXCoordinateValid(c) ? c : CLXInvalidCoordinate();
}

+ (void)setTarget:(CLLocationCoordinate2D)c {
    if (!CLXCoordinateValid(c)) {
        Set(kKLat, nil);
        Set(kKLng, nil);
        return;
    }
    Set(kKLat, @(c.latitude));
    Set(kKLng, @(c.longitude));
}

+ (NSString *)targetName {
    id v = Get(kKName);
    return [v isKindOfClass:[NSString class]] ? v : @"";
}

+ (void)setTargetName:(NSString *)n {
    Set(kKName, n.length ? n : nil);
}

+ (double)altitude {
    return GetDouble(kKAlt, 0.0);
}

+ (void)setAltitude:(double)v {
    Set(kKAlt, @(v));
}

+ (CLXTravelMode)travelMode {
    NSInteger m = (NSInteger)GetDouble(kKTravel, (double)CLXTravelModeWalk);
    if (m < CLXTravelModeInstant || m > CLXTravelModeDrive) m = CLXTravelModeWalk;
    return (CLXTravelMode)m;
}

+ (void)setTravelMode:(CLXTravelMode)m {
    Set(kKTravel, @((NSInteger)m));
}

+ (CLXAccuracyProfile)accuracyProfile {
    NSInteger p = (NSInteger)GetDouble(kKProfile, (double)CLXAccuracyProfileAuto);
    if (p < CLXAccuracyProfileAuto || p > CLXAccuracyProfileIndoor) p = CLXAccuracyProfileAuto;
    return (CLXAccuracyProfile)p;
}

+ (void)setAccuracyProfile:(CLXAccuracyProfile)p {
    Set(kKProfile, @((NSInteger)p));
}

+ (BOOL)hideWiFi {
    // 默认关闭：位置打卡规则下上报的 wifi 字段通常为空，
    // 强行屏蔽反而容易撞上"wifi 异常"标签。需要防泄漏时手动打开。
    return GetBool(kKWiFi, NO);
}

+ (void)setHideWiFi:(BOOL)v {
    Set(kKWiFi, @(v));
}

+ (NSInteger)coordinateMode {
    NSInteger m = (NSInteger)GetDouble(kKCoord, 0.0);
    if (m < 0 || m > 2) m = 0;
    return m;
}

+ (void)setCoordinateMode:(NSInteger)v {
    Set(kKCoord, @(v));
}

+ (BOOL)strictMode {
    return GetBool(kKStrict, NO);
}

+ (void)setStrictMode:(BOOL)v {
    Set(kKStrict, @(v));
}

+ (BOOL)deepMode {
    return GetBool(kKDeep, NO);
}

+ (void)setDeepMode:(BOOL)v {
    Set(kKDeep, @(v));
}

+ (BOOL)antiDetect {
    return GetBool(kKGuard, YES);
}

+ (void)setAntiDetect:(BOOL)v {
    Set(kKGuard, @(v));
}

+ (BOOL)diagnosticsEnabled {
    // 默认开启：日志文件本身有 256KB 上限，开销可忽略，
    // 而且它同时是"插件是否成功注入"最直接的证据（沙箱内会出现 .dbg）。
    return GetBool(kKDiag, YES);
}

+ (void)setDiagnosticsEnabled:(BOOL)v {
    Set(kKDiag, @(v));
}

@end
