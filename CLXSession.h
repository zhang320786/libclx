//
//  CLXSession.h
//  位置快照引擎。
//
//  设计原则：
//  1) 只在"定位源头"（CLLocationManager delegate / TencentLBS）替换坐标，
//     不篡改 CLLocation 的 getter。这样上层拿到的第一个 CLLocation 就是假点，
//     逆地理、距离计算、地图渲染全部自洽，不会出现"坐标改了但地址没变"的矛盾。
//  2) 严格模式下才额外接管 CLLocation getter，作为非标准取点路径的兜底。
//  3) 输出带真实感的抖动：horizontalAccuracy / speed / course / altitude
//     随时间连续变化，而不是常量（常量是最容易被风控抓住的特征）。
//  4) 目标变更时从上一个真实点匀速插值过去，避免出现超大瞬时速度。
//

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import "CLXShared.h"

@interface CLXSession : NSObject

+ (instancetype)shared;

// 当前是否接管定位（开关打开 + 有合法目标点）
- (BOOL)isActive;

// 记录一个真实样本。注意：调用方必须传入"未经本插件改写"的原始值，
// 否则会污染插值起点。
- (void)noteRealCoordinate:(CLLocationCoordinate2D)c
                  altitude:(double)altitude
                  accuracy:(double)accuracy;

// 处理 delegate 回调：返回应交给上层的合成对象；nil 表示不接管
- (CLLocation *)processLocations:(NSArray<CLLocation *> *)locations;

// 直接取当前合成对象（CLLocationManager -location / 腾讯定位 SDK 用）
- (CLLocation *)currentLocation;

// 当前合成坐标（WGS-84）
- (CLLocationCoordinate2D)currentCoordinate;

// 当前合成坐标（GCJ-02，腾讯定位 SDK 默认坐标系）
- (CLLocationCoordinate2D)currentCoordinateGCJ;

// 诊断信息（设置页展示）
- (NSDictionary *)diagnostics;

// 丢弃当前目标，回到真实定位
- (void)clearTarget;

@end
