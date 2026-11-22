#import "CLXSession.h"
#import "CLXStore.h"
#import <pthread.h>

@implementation CLXSession {
    pthread_mutex_t _lock;

    // 真实样本（WGS-84）
    CLLocationCoordinate2D _real;
    double _realAlt;
    double _realAcc;
    NSTimeInterval _realAt;
    BOOL _hasReal;

    // 插值动画
    CLLocationCoordinate2D _from;
    NSTimeInterval _animStart;
    BOOL _hasAnim;

    // 目标缓存（用于检测目标变更）
    CLLocationCoordinate2D _lastTarget;

    // 输出
    CLLocation *_snapshot;
    NSTimeInterval _snapshotAt;
    CLLocationCoordinate2D _outCoord;      // WGS-84
    CLLocationCoordinate2D _outCoordGCJ;   // GCJ-02
    double _outAlt, _outAcc, _outSpeed, _outCourse;

    // 速度/朝向
    CLLocationCoordinate2D _prevPos;
    NSTimeInterval _prevAt;
    double _speed;
    double _course;
    BOOL _hasPrev;

    // 统计
    NSTimeInterval _lastCallbackAt;
    NSUInteger _callbackCount;
}

+ (instancetype)shared {
    static CLXSession *s = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [[CLXSession alloc] init];
    });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        pthread_mutexattr_t attr;
        pthread_mutexattr_init(&attr);
        pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE);
        pthread_mutex_init(&_lock, &attr);
        pthread_mutexattr_destroy(&attr);
        _real = CLXInvalidCoordinate();
        _lastTarget = CLXInvalidCoordinate();
        _prevPos = CLXInvalidCoordinate();
        _outCoord = CLXInvalidCoordinate();
        _outCoordGCJ = CLXInvalidCoordinate();
        _speed = 0.0;
        _course = 0.0;
    }
    return self;
}

#pragma mark - 状态

- (BOOL)isActive {
    if (![CLXStore enabled]) return NO;
    return CLXCoordinateValid([CLXStore target]);
}

- (void)noteRealCoordinate:(CLLocationCoordinate2D)c
                  altitude:(double)altitude
                  accuracy:(double)accuracy {
    if (!CLXCoordinateValid(c)) return;

    pthread_mutex_lock(&_lock);
    _real = c;
    if (altitude > -400.0 && altitude < 9000.0) _realAlt = altitude;
    if (accuracy > 0.0 && accuracy < 100000.0) _realAcc = accuracy;
    _realAt = CFAbsoluteTimeGetCurrent();
    _lastCallbackAt = _realAt;
    _callbackCount++;
    if (!_hasReal) {
        _hasReal = YES;
        _from = c;
        _animStart = _realAt;
        _hasAnim = NO;          // 首次拿到真实点，强制重建动画起点
    }
    pthread_mutex_unlock(&_lock);
}

- (void)clearTarget {
    [CLXStore setTarget:CLXInvalidCoordinate()];
    [CLXStore setTargetName:nil];
    [CLXStore setEnabled:NO];
    [CLXStore invalidate];

    pthread_mutex_lock(&_lock);
    _snapshot = nil;
    _snapshotAt = 0;
    _hasAnim = NO;
    _lastTarget = CLXInvalidCoordinate();
    _hasPrev = NO;
    _speed = 0.0;
    _outCoord = CLXInvalidCoordinate();
    _outCoordGCJ = CLXInvalidCoordinate();
    pthread_mutex_unlock(&_lock);
}

#pragma mark - 对外

- (CLLocation *)processLocations:(NSArray<CLLocation *> *)locations {
    (void)locations;
    // 真实样本由调用方通过 noteRealCoordinate: 提供（避免在读 CLLocation
    // getter 时被严格模式的自定义实现回环）。
    if (![self isActive]) return nil;
    return [self _buildSnapshot];
}

- (CLLocation *)currentLocation {
    if (![self isActive]) return nil;
    return [self _buildSnapshot];
}

- (CLLocationCoordinate2D)currentCoordinate {
    pthread_mutex_lock(&_lock);
    CLLocationCoordinate2D c = _outCoord;
    pthread_mutex_unlock(&_lock);
    return c;
}

- (CLLocationCoordinate2D)currentCoordinateGCJ {
    pthread_mutex_lock(&_lock);
    CLLocationCoordinate2D c = _outCoordGCJ;
    pthread_mutex_unlock(&_lock);
    return c;
}

#pragma mark - 核心：生成快照

// 全程持有 _lock；内部不得再调用本类的加锁方法。
- (CLLocation *)_buildSnapshot {
    NSTimeInterval now = CFAbsoluteTimeGetCurrent();

    // CLXStore 使用独立锁，可以在持锁期间调用（本类不会回调 CLXStore）
    CLLocationCoordinate2D target = [CLXStore target];
    if (!CLXCoordinateValid(target)) return nil;

    CLXTravelMode mode      = [CLXStore travelMode];
    CLXAccuracyProfile prof = [CLXStore accuracyProfile];
    double altStore         = [CLXStore altitude];

    pthread_mutex_lock(&_lock);

    // 命中缓存
    if (_snapshot && (now - _snapshotAt) < 0.18) {
        CLLocation *cached = _snapshot;
        pthread_mutex_unlock(&_lock);
        return cached;
    }

    // ── 目标变更 → 从真实点重新起跑 ──
    BOOL targetChanged = !CLXCoordinateEqual(_lastTarget, target);
    if (targetChanged) {
        _lastTarget = target;
        if (_hasReal) {
            _from = _real;
        } else if (CLXCoordinateValid(_outCoord)) {
            _from = _outCoord;
        } else {
            _from = target;
        }
        _animStart = now;
        _hasAnim = YES;
        _snapshot = nil;
        _snapshotAt = 0;
        _hasPrev = NO;
        _speed = 0.0;
    } else if (!_hasAnim) {
        _from = _hasReal ? _real : target;
        _animStart = now;
        _hasAnim = YES;
    }

    // ── 位移进度 ──
    // 步行/驾车只在各自合理距离内做插值；超出范围直接切换，
    // 否则 5km 距离被钳到 2400s 会算出 2m/s 甚至 20m/s 的"走路速度"。
    double distance = CLXDistanceMeters(_from, target);
    double duration = 0.0;
    switch (mode) {
        case CLXTravelModeInstant:
            duration = 0.0;
            break;
        case CLXTravelModeWalk:
            duration = (distance <= 3000.0) ? CLAMP(distance / 1.35, 3.0, 2400.0) : 0.0;
            break;
        case CLXTravelModeDrive:
            duration = (distance <= 60000.0) ? CLAMP(distance / 13.0, 5.0, 3600.0) : 0.0;
            break;
    }

    double progress = 1.0;
    if (duration > 0.5) {
        progress = CLAMP((now - _animStart) / duration, 0.0, 1.0);
    }
    BOOL arrived = (progress >= 1.0);

    CLLocationCoordinate2D pos = CLXLerp(_from, target, progress);

    // ── 抖动：两个不同频率的正弦叠加，幅度 1~2m ──
    double jitterAmp = (prof == CLXAccuracyProfileIndoor) ? 2.2 : 1.2;
    double jLat = (sin(now * 0.311) * 0.6 + sin(now * 0.771 + 1.3) * 0.4) * jitterAmp;
    double jLng = (cos(now * 0.271 + 0.7) * 0.6 + cos(now * 0.833 + 2.1) * 0.4) * jitterAmp;
    double mPerDegLat = 111320.0;
    double mPerDegLng = 111320.0 * fmax(cos(pos.latitude * M_PI / 180.0), 0.15);
    pos.latitude  += jLat / mPerDegLat;
    pos.longitude += jLng / mPerDegLng;

    // ── 精度：每 7 秒切一档，避免恒定值 ──
    double tick = floor(now / 7.0);
    double n = CLXNoise(tick);
    double acc;
    if (prof == CLXAccuracyProfileIndoor) {
        acc = 28.0 + n * 32.0;                                // 28 ~ 60m
    } else if (prof == CLXAccuracyProfileOutdoor) {
        acc = 5.0 + n * 10.0;                                 // 5 ~ 15m
    } else {
        acc = arrived ? (6.0 + n * 9.0) : (12.0 + n * 14.0);  // 到达后收敛
    }
    double vacc = acc * 1.7;

    // ── 海拔 ──
    double altBase = (altStore > 0.0) ? altStore : (_hasReal ? _realAlt : 0.0);
    double alt = altBase + sin(now * 0.41) * 1.2;

    // ── 速度 / 朝向 ──
    double speed = 0.0;
    double course = _course;
    if (_hasPrev && (now - _prevAt) > 0.01) {
        double moved = CLXDistanceMeters(_prevPos, pos);
        speed = moved / (now - _prevAt);
        if (moved > 0.5) course = CLXBearingDegrees(_prevPos, pos);
    }
    if (arrived) {
        speed = 0.12 + CLXNoise(floor(now)) * 0.28;   // 站着不动的微小残留
    }
    if (speed > 60.0) speed = 60.0;

    _prevPos = pos;
    _prevAt = now;
    _hasPrev = YES;
    _speed = speed;
    _course = course;

    _outCoord = pos;
    _outCoordGCJ = CLXWGS84ToGCJ02(pos);
    _outAlt = alt;
    _outAcc = acc;
    _outSpeed = speed;
    _outCourse = course;

    CLLocation *loc;
    if (@available(iOS 13.4, *)) {
        loc = [[CLLocation alloc] initWithCoordinate:pos
                                            altitude:alt
                                  horizontalAccuracy:acc
                                    verticalAccuracy:vacc
                                              course:course
                                               speed:speed
                                           timestamp:[NSDate date]];
    } else {
        loc = [[CLLocation alloc] initWithCoordinate:pos
                                            altitude:alt
                                  horizontalAccuracy:acc
                                    verticalAccuracy:vacc
                                           timestamp:[NSDate date]];
    }

    _snapshot = loc;
    _snapshotAt = now;

    pthread_mutex_unlock(&_lock);
    return loc;
}

#pragma mark - 诊断

- (NSDictionary *)diagnostics {
    pthread_mutex_lock(&_lock);
    BOOL hasReal = _hasReal;
    CLLocationCoordinate2D real = _real;
    double realAlt = _realAlt;
    double realAcc = _realAcc;
    NSUInteger cb = _callbackCount;
    NSTimeInterval last = _lastCallbackAt;
    CLLocationCoordinate2D out = _outCoord;
    CLLocationCoordinate2D outGCJ = _outCoordGCJ;
    double outAcc = _outAcc, outSpeed = _outSpeed;
    BOOL hasOut = CLXCoordinateValid(out);
    pthread_mutex_unlock(&_lock);

    CLLocationCoordinate2D target = [CLXStore target];

    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"enabled"] = @([CLXStore enabled]);
    d[@"active"]  = @([self isActive]);
    d[@"hasReal"] = @(hasReal);
    if (hasReal) {
        d[@"realLat"] = @(real.latitude);
        d[@"realLng"] = @(real.longitude);
    }
    d[@"realAlt"] = @(realAlt);
    d[@"realAcc"] = @(realAcc);
    if (CLXCoordinateValid(target)) {
        d[@"targetLat"] = @(target.latitude);
        d[@"targetLng"] = @(target.longitude);
        d[@"targetGCJLat"] = @(CLXWGS84ToGCJ02(target).latitude);
        d[@"targetGCJLng"] = @(CLXWGS84ToGCJ02(target).longitude);
    }
    if (hasOut) {
        d[@"outLat"]    = @(out.latitude);
        d[@"outLng"]    = @(out.longitude);
        d[@"outGCJLat"] = @(outGCJ.latitude);
        d[@"outGCJLng"] = @(outGCJ.longitude);
        d[@"outAcc"]    = @(outAcc);
        d[@"outSpeed"]  = @(outSpeed);
        if (CLXCoordinateValid(target)) {
            d[@"dist"] = @(CLXDistanceMeters(out, target));
        }
    }
    d[@"callbacks"] = @(cb);
    if (last > 0) d[@"lastCbAgo"] = @(CFAbsoluteTimeGetCurrent() - last);
    return d;
}

@end
