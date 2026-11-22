#import "CLXShared.h"
#import "CLXStore.h"
#import <stdio.h>
#import <stdlib.h>
#import <pthread.h>

// ── GCJ-02 / WGS-84 ──────────────────────────────────────
static const double kPI  = 3.14159265358979324;
static const double kA   = 6378245.0;
static const double kEE  = 0.00669342162296594323;

static BOOL clx_outOfChina(double lat, double lng) {
    return (lng < 72.004 || lng > 137.8347 || lat < 0.8293 || lat > 55.8271);
}

static double clx_tLat(double x, double y) {
    double ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(fabs(x));
    ret += (20.0 * sin(6.0 * x * kPI) + 20.0 * sin(2.0 * x * kPI)) * 2.0 / 3.0;
    ret += (20.0 * sin(y * kPI) + 40.0 * sin(y / 3.0 * kPI)) * 2.0 / 3.0;
    ret += (160.0 * sin(y / 12.0 * kPI) + 320.0 * sin(y * kPI / 30.0)) * 2.0 / 3.0;
    return ret;
}

static double clx_tLon(double x, double y) {
    double ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(fabs(x));
    ret += (20.0 * sin(6.0 * x * kPI) + 20.0 * sin(2.0 * x * kPI)) * 2.0 / 3.0;
    ret += (20.0 * sin(x * kPI) + 40.0 * sin(x / 3.0 * kPI)) * 2.0 / 3.0;
    ret += (150.0 * sin(x / 12.0 * kPI) + 300.0 * sin(x / 20.0 * kPI)) * 2.0 / 3.0;
    return ret;
}

CLLocationCoordinate2D CLXWGS84ToGCJ02(CLLocationCoordinate2D c) {
    if (clx_outOfChina(c.latitude, c.longitude)) return c;
    double dLat = clx_tLat(c.longitude - 105.0, c.latitude - 35.0);
    double dLon = clx_tLon(c.longitude - 105.0, c.latitude - 35.0);
    double radLat = c.latitude / 180.0 * kPI;
    double magic = sin(radLat);
    magic = 1.0 - kEE * magic * magic;
    double sqrtMagic = sqrt(magic);
    dLat = (dLat * 180.0) / ((kA * (1.0 - kEE)) / (magic * sqrtMagic) * kPI);
    dLon = (dLon * 180.0) / (kA / sqrtMagic * cos(radLat) * kPI);
    return CLLocationCoordinate2DMake(c.latitude + dLat, c.longitude + dLon);
}

CLLocationCoordinate2D CLXGCJ02ToWGS84(CLLocationCoordinate2D c) {
    if (clx_outOfChina(c.latitude, c.longitude)) return c;
    CLLocationCoordinate2D wgs = c;
    for (int i = 0; i < 6; i++) {
        CLLocationCoordinate2D gcj = CLXWGS84ToGCJ02(wgs);
        wgs = CLLocationCoordinate2DMake(c.latitude  + (wgs.latitude  - gcj.latitude),
                                        c.longitude + (wgs.longitude - gcj.longitude));
    }
    return wgs;
}

// ── 几何 ─────────────────────────────────────────────────
double CLXDistanceMeters(CLLocationCoordinate2D a, CLLocationCoordinate2D b) {
    double lat1 = a.latitude  * kPI / 180.0;
    double lat2 = b.latitude  * kPI / 180.0;
    double dLat = (b.latitude  - a.latitude)  * kPI / 180.0;
    double dLon = (b.longitude - a.longitude) * kPI / 180.0;
    double h = sin(dLat / 2.0) * sin(dLat / 2.0) +
               cos(lat1) * cos(lat2) * sin(dLon / 2.0) * sin(dLon / 2.0);
    return 2.0 * 6371000.0 * asin(fmin(1.0, sqrt(h)));
}

double CLXBearingDegrees(CLLocationCoordinate2D a, CLLocationCoordinate2D b) {
    double lat1 = a.latitude  * kPI / 180.0;
    double lat2 = b.latitude  * kPI / 180.0;
    double dLon = (b.longitude - a.longitude) * kPI / 180.0;
    double y = sin(dLon) * cos(lat2);
    double x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
    double brg = atan2(y, x) * 180.0 / kPI;
    if (brg < 0.0) brg += 360.0;
    return brg;
}

CLLocationCoordinate2D CLXLerp(CLLocationCoordinate2D a, CLLocationCoordinate2D b, double p) {
    p = CLAMP(p, 0.0, 1.0);
    double aLat = a.latitude  * kPI / 180.0;
    double bLat = b.latitude  * kPI / 180.0;
    double aLon = a.longitude * kPI / 180.0;
    double bLon = b.longitude * kPI / 180.0;
    double d = 2.0 * asin(fmin(1.0, sqrt(pow(sin((bLat - aLat) / 2.0), 2.0) +
                                      cos(aLat) * cos(bLat) * pow(sin((bLon - aLon) / 2.0), 2.0))));
    if (d < 1e-12) return b;
    double A = sin((1.0 - p) * d) / sin(d);
    double B = sin(p * d) / sin(d);
    double x = A * cos(aLat) * cos(aLon) + B * cos(bLat) * cos(bLon);
    double y = A * cos(aLat) * sin(aLon) + B * cos(bLat) * sin(bLon);
    double z = A * sin(aLat) + B * sin(bLat);
    return CLLocationCoordinate2DMake(atan2(z, sqrt(x * x + y * y)) * 180.0 / kPI,
                                      atan2(y, x) * 180.0 / kPI);
}

// ── 确定性噪声 [0,1) ─────────────────────────────────────
double CLXNoise(double seed) {
    double s = sin(seed * 12.9898 + 78.233) * 43758.5453123;
    return s - floor(s);
}

// ── 诊断日志 ─────────────────────────────────────────────
static pthread_mutex_t gLogLock = PTHREAD_MUTEX_INITIALIZER;

void CLXLog(NSString *fmt, ...) {
    if (![CLXStore diagnosticsEnabled]) return;

    va_list ap;
    va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    if (!msg) return;

    NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches"];
    NSString *path = [dir stringByAppendingPathComponent:@".dbg"];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:dir]) [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];

    // 文件超过 256KB 就截断，避免无限增长
    NSDictionary *attrs = [fm attributesOfItemAtPath:path error:NULL];
    if ([attrs fileSize] > 256 * 1024) [fm removeItemAtPath:path error:NULL];

    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"HH:mm:ss.SSS";
    });
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [formatter stringFromDate:[NSDate date]], msg];

    pthread_mutex_lock(&gLogLock);
    FILE *fp = fopen(path.UTF8String, "a");
    if (fp) {
        fputs(line.UTF8String, fp);
        fclose(fp);
    }
    pthread_mutex_unlock(&gLogLock);
}
