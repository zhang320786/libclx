//
//  CLXShared.h
//  libclx — 企业微信定位支撑库（内部组件）
//
//  命名刻意中性：进程内不出现任何可被特征扫描的模块名。
//

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import <math.h>

#ifndef CLAMP
#define CLAMP(x, lo, hi) ((x) < (lo) ? (lo) : ((x) > (hi) ? (hi) : (x)))
#endif

// 无效坐标哨兵
static inline CLLocationCoordinate2D CLXInvalidCoordinate(void) {
    return CLLocationCoordinate2DMake(1000.0, 1000.0);
}

static inline BOOL CLXCoordinateValid(CLLocationCoordinate2D c) {
    if (!isfinite(c.latitude) || !isfinite(c.longitude)) return NO;
    if (fabs(c.latitude) > 90.0 || fabs(c.longitude) > 180.0) return NO;
    if (c.latitude == 0.0 && c.longitude == 0.0) return NO;
    return YES;
}

static inline BOOL CLXCoordinateEqual(CLLocationCoordinate2D a, CLLocationCoordinate2D b) {
    return (fabs(a.latitude - b.latitude) < 1e-9 && fabs(a.longitude - b.longitude) < 1e-9);
}

// ── 移动模式 ──────────────────────────────────────────────
typedef NS_ENUM(NSInteger, CLXTravelMode) {
    CLXTravelModeInstant = 0,   // 瞬移到目标点
    CLXTravelModeWalk    = 1,   // 以步行速度渐变过去
    CLXTravelModeDrive   = 2,   // 以车行速度渐变过去
};

// ── 精度档位 ──────────────────────────────────────────────
typedef NS_ENUM(NSInteger, CLXAccuracyProfile) {
    CLXAccuracyProfileAuto    = 0,  // 自动（到达后收敛）
    CLXAccuracyProfileOutdoor = 1,  // 室外 5~15m
    CLXAccuracyProfileIndoor  = 2,  // 室内 28~60m
};

// ── 坐标转换 ──────────────────────────────────────────────
CLLocationCoordinate2D CLXWGS84ToGCJ02(CLLocationCoordinate2D c);
CLLocationCoordinate2D CLXGCJ02ToWGS84(CLLocationCoordinate2D c);

// ── 几何 ──────────────────────────────────────────────────
double CLXDistanceMeters(CLLocationCoordinate2D a, CLLocationCoordinate2D b);
double CLXBearingDegrees(CLLocationCoordinate2D a, CLLocationCoordinate2D b);
CLLocationCoordinate2D CLXLerp(CLLocationCoordinate2D a, CLLocationCoordinate2D b, double p);

// ── 确定性噪声（同一时刻多次取值一致，避免抖动穿帮）─────────
double CLXNoise(double seed);

// ── 诊断日志（仅诊断开关打开时写盘，写入 App 沙箱 Caches）───
void CLXLog(NSString *fmt, ...);
