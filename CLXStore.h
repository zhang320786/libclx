//
//  CLXStore.h
//  配置存储。
//
//  刻意不用 CFPreferences：全局 domain 会在 /var/mobile/Library/Preferences
//  下留下可被任意进程枚举的 plist，是插件检测最廉价的特征点。
//  这里改为写入 App 自身沙箱 Caches 下的一个"缓存文件"，
//  文件名与内容都不含模块特征串。
//

#import <Foundation/Foundation.h>
#import "CLXShared.h"

@interface CLXStore : NSObject

+ (void)invalidate;

+ (BOOL)enabled;
+ (void)setEnabled:(BOOL)v;

+ (BOOL)hasTarget;
+ (CLLocationCoordinate2D)target;              // WGS-84
+ (void)setTarget:(CLLocationCoordinate2D)c;
+ (NSString *)targetName;
+ (void)setTargetName:(NSString *)n;

+ (double)altitude;                            // 0 = 跟随真实海拔
+ (void)setAltitude:(double)v;

+ (CLXTravelMode)travelMode;
+ (void)setTravelMode:(CLXTravelMode)m;

+ (CLXAccuracyProfile)accuracyProfile;
+ (void)setAccuracyProfile:(CLXAccuracyProfile)p;

+ (BOOL)hideWiFi;                              // 屏蔽 WiFi 指纹上报
+ (void)setHideWiFi:(BOOL)v;

// 坐标系输出策略：0=自动跟随腾讯定位 SDK 的 coordinateType，1=强制 GCJ-02，2=强制 WGS-84
+ (NSInteger)coordinateMode;
+ (void)setCoordinateMode:(NSInteger)v;

// 严格模式：额外在 CLLocation getter 层兜底（覆盖所有非标准取点路径）
+ (BOOL)strictMode;
+ (void)setStrictMode:(BOOL)v;

// 深度模式：额外 hook WWKLocation* / WWKAttendance* 业务层取点方法（版本漂移时用）
+ (BOOL)deepMode;
+ (void)setDeepMode:(BOOL)v;

+ (BOOL)antiDetect;                            // 环境隐藏（需重启生效）
+ (void)setAntiDetect:(BOOL)v;

+ (BOOL)diagnosticsEnabled;
+ (void)setDiagnosticsEnabled:(BOOL)v;

@end
