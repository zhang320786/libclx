# libclx — 企业微信定位接管（rootHide / 越狱插件）

把 [wclocate](https://github.com/5hux1n/wclocate)（微信版）改造成**企业微信（`com.tencent.ww`）**版本，
并补上原版没有的部分：**坐标系分层处理**、**定位特征拟真**、**运行环境隐藏**、**无 UI 痕迹入口**。

- 注入目标：`com.tencent.ww`（可执行文件 `WeCom`）
- 越狱环境：Dopamine rootHide / roothide Bootstrap（iOS 15.0–16.6.x 为主）
- 打包：Theos + `THEOS_PACKAGE_SCHEME = roothide`

---

## 1. 和原版的区别（为什么要改这么多）

原版 wclocate 只做两件事：代理 `CLLocationManager` 的 delegate、hook `TencentLBSLocation.coordinate`，
然后把微信定位换成固定坐标。搬到企业微信上会踩到四个坑：

| 坑 | 原版做法 | 本版做法 |
|---|---|---|
| **坐标系** | 选点后转 WGS-84 存，直接返回 | 企业微信打卡上报的是 **GCJ-02 × 1000000**，而腾讯定位 SDK 默认输出 **GCJ-02**、CoreLocation 输出 **WGS-84**。两层必须分别喂对应坐标系，否则整体偏 300~600m。本版按 SDK 的 `coordinateType` 自适应 |
| **定位特征** | `horizontalAccuracy` 写死 5.0、`altitude` 写死、`speed` 用真值 | 精度 6~60m 按档位每 7 秒切换、速度由实际位移推导（静止时 0.1~0.4 m/s）、朝向连续、坐标带 1~2m 抖动 |
| **瞬移** | 目标点一步到位 | 目标变更时从**上一次真实位置**匀速走过去（步行 1.35 m/s，3km 内有效；车行 13 m/s，60km 内有效；超出范围直接切换），避免出现 100km/s 的瞬时速度 |
| **检测** | 无 | 文件路径、环境变量、`fork`、`ptrace`、`sysctl`、`csops`、dyld 镜像列表、`dladdr`、越狱 URL scheme、运行时越狱检测方法，全部处理 |
| **入口** | 在「我」页面插 cell | 企业微信没有 `WCPluginsMgr`，且插 cell 是可见痕迹。改为**屏幕任意位置连点 5 次**弹出设置页，进程内不新增任何可见 UI |
| **配置存储** | `CFPreferences` 全局 domain | 写 App 自身沙箱 `Library/Caches/.ds.v2`。全局 Preferences 目录下的 plist 是插件检测最廉价的特征点 |

---

## 2. 目录结构

```
wclocate-wecom/
├── Makefile                    # Theos 构建（roothide scheme）
├── control                     # deb 包信息
├── libclx.plist                # 注入过滤：Bundles = com.tencent.ww
├── Tweak.xm                    # 主 hook：L1 代理 / L2 腾讯SDK / L3 严格模式 / L4 深度模式 / 入口
├── CLXGuard.xm                 # 运行环境隐藏（C 函数 hook + 运行时检测方法覆盖）
├── CLXShared.h/.m              # GCJ-02 转换、距离、插值、确定性噪声、诊断日志
├── CLXStore.h/.m               # 配置读写（沙箱内、短键名）
├── CLXSession.h/.m             # 位置快照引擎（插值 / 抖动 / 精度 / 速度）
├── CLXPanelController.h/.m     # 设置页
├── CLXMapController.h/.m       # 地图选点
└── .github/workflows/build.yml # GitHub Actions 自动出 deb
```

---

## 3. 编译

### 3.1 GitHub Actions（推荐，不用 Mac）

仓库推到 GitHub → Actions 自动构建 → 在 Artifacts 下载 `libclx_1.0.0_iphoneos-arm64e.deb`。

workflow 用的是 **`roothide/theos`**（不是上游 theos），因为需要 `roothide` scheme。

### 3.2 本地 macOS

```bash
export THEOS=$HOME/theos
bash -c "$(curl -fsSL https://raw.githubusercontent.com/roothide/theos/master/bin/install-theos)"

cd wclocate-wecom
make clean
make package FINALPACKAGE=1
# 产物: packages/libclx_1.0.0_iphoneos-arm64e.deb
```

方案确认（必须看到 `roothide`）：

```bash
ls $THEOS/vendor/mod | grep -x roothide
```

如果你的 Theos 是上游版本（没有 roothide scheme），把 Makefile 第一行改成 `THEOS_PACKAGE_SCHEME = rootless`
—— 但那只适用于 **Dopamine 常规版**（有 `/var/jb`），**rootHide 上装不了**。

### 3.3 产物自检

```bash
deb=packages/libclx_1.0.0_iphoneos-arm64e.deb
dpkg-deb -f $deb Architecture Depends      # 应为 iphoneos-arm64e / mobilesubstrate, firmware (>= 15.0)
dpkg-deb -c $deb | head                    # 必须是 ./Library/MobileSubstrate/DynamicLibraries/，不能出现 ./var/jb/
```

---

## 4. 安装

```bash
# 传到设备后
dpkg -i libclx_1.0.0_iphoneos-arm64e.deb
# 或用 Sileo / Zebra 直接装 deb
killall -9 WeCom 2>/dev/null
```

验证已注入：

```bash
jbroot
ls -l "$(jbroot)/Library/MobileSubstrate/DynamicLibraries/" | grep -i clx
ls -l "$(jbroot)/Library/MobileSubstrate/DynamicLibraries/.jbroot"   # 应存在（dpkg 自动建）
vmmap $(pgrep -x WeCom) | grep -i 'clx\|ellekit\|jbroot'             # 应能看到镜像
```

---

## 5. 使用

1. 打开企业微信
2. 在**任意界面连续快速点击 5 次**（1.2 秒内，位置基本不动）
3. 弹出「位置」设置页：

| 项 | 说明 |
|---|---|
| 启用虚拟定位 | 总开关 |
| 选择目标位置 | 地图拖拽 / 关键词搜索选点 |
| 海拔高度 | 填 0 跟随真实海拔 |
| 移动方式 | 瞬移 / 步行（3km 内）/ 驾车（60km 内）——决定变更目标后的过渡速度 |
| 定位精度 | 自动 / 室外 5~15m / 室内 28~60m |
| 坐标系 | 自动 / 强制 GCJ-02 / 强制 WGS-84 |
| 严格模式 | 打卡地点仍未变时打开：额外接管所有 `CLLocation -coordinate` |
| 深度模式 | 严格模式仍无效时打开：接管 `WWKLocation*` / `WWKAttendance*` 业务层取点（需重启） |
| 屏蔽 WiFi 指纹 | 打卡规则是「位置打卡」时可开；规则是「WiFi 打卡」时必须关 |
| 隐藏越狱环境 | 默认开，需重启生效 |
| 诊断日志 | 写入 App 沙箱 `Library/Caches/.dbg` |

4. 选好点 → 打开开关 → 回打卡页，页面上的「当前位置」与「距离」应立即变成目标点。

---

## 6. 打卡不翻车的操作顺序

这是重点。坐标对了只是第一步，服务端还会对账：

1. **提前选好点，别在打卡按钮上才切**
   进入打卡页后先让插件跑 30~60 秒（完成定位、逆地理、距离计算），再点打卡。
2. **单点上报，不要制造轨迹矛盾**
   企业微信打卡是点击时上报一次坐标。但如果同一天早上在家、中午在公司、晚上又回家，
   而三次的坐标都是「公司」——这是最常见的服务端异常来源。按真实作息使用。
3. **目标点选在打卡范围中心**，不要卡在 100m / 3000m 边界上。
   插件的 1~2m 抖动 + 精度噪声可能让你在边界反复横跳。
4. **WiFi 打卡规则必须真连公司 WiFi**
   后台配置了 BSSID 时，虚拟定位无效；上报的 `wifimac` 必须匹配。这种情况插件帮不上，只能真连。
5. **拍照打卡关掉相机定位权限**
   系统设置 → 企业微信 → 照片 → 位置 → 选「永不」。否则照片 EXIF 里的 GPS 会和坐标打架。
6. **不要开 VPN / 全局代理**，也不要用爱思/i4 这类系统级虚拟定位叠加。
7. **首次使用先验证再上班**
   随便选个离家 1km 的点，去打卡页看「当前位置」是否真的变成目标地址、距离是否合理。

---

## 7. 技术说明

### 7.1 覆盖层级

```
L1  CLLocationManager -setDelegate:        ← 代理包装，改写 didUpdateLocations 的数组
    CLLocationManager -location             ← 缓存定位
L2  TencentLBSLocation -coordinate          ← 企业微信 WWKLocationRetriever 走腾讯定位 SDK
    TencentLBSLocation -location/-latitude/-longitude
    TencentLBSLocationManager -setCoordinateType:   ← 记录 SDK 坐标系，决定输出 GCJ 还是 WGS
L3  CLLocation -coordinate                  ← 严格模式：兜底所有直接构造/读取 CLLocation 的路径
L4  WWKLocation* / WWKAttendance* 坐标 getter ← 深度模式：业务层兜底
```

**只改源头，不改 getter**（严格模式除外）。这样企业微信拿到的第一个 `CLLocation` 就是假点，
它后续的逆地理、距离计算、地图渲染全部基于假坐标，**自洽**——
不会出现「坐标变成公司了，但地址还写着家里」这种一眼假的矛盾。

### 7.2 为什么坐标系要分两层

| 数据源 | 默认坐标系 |
|---|---|
| `CLLocation` / CoreLocation | WGS-84 |
| 腾讯定位 SDK `TencentLBSLocation` | **GCJ-02**（`coordinateType` 默认 0） |
| 企业微信打卡上报 `lat/lng` | **GCJ-02 × 1000000** |

所以：
- L1 层（CoreLocation）返回 **WGS-84** 目标点
- L2 层（腾讯 SDK）返回 **GCJ-02** 目标点（内部 `CLXWGS84ToGCJ02`）
- 引擎内部统一在 WGS-84 空间做插值，输出时再转换

如果统一返回 WGS-84 给腾讯 SDK，落点会整体偏 300~600m——这是企业微信版最容易踩的坑。

### 7.3 拟真的定位特征

| 字段 | 处理 |
|---|---|
| `horizontalAccuracy` | 自动档 6~15m（到达后）/ 12~26m（移动中），每 7 秒换一档；室内档 28~60m；室外档 5~15m |
| `verticalAccuracy` | `horizontalAccuracy × 1.7` |
| `altitude` | 自定义值优先，否则真实海拔 + ±1.2m 起伏 |
| `speed` | 由实际位移 / 时间推导；到达后 0.1~0.4 m/s 微抖 |
| `course` | 移动时按方位角，静止时保持 |
| `timestamp` | 当前时间（不是固定值） |
| 坐标抖动 | 两个不同频率正弦叠加，幅度 1~2m |

### 7.4 环境隐藏清单

C 函数层（`MSHookFunction`）：

```
stat lstat access faccessat fstatat opendir
getenv                     → DYLD_* / _MSSafeMode / JB_ROOT 返回 NULL
fork posix_spawn           → EPERM
ptrace                     → PT_DENY_ATTACH 返回 0
sysctl                     → 清 P_TRACED
csops                      → 清 CS_DEBUGGED
_dyld_image_count          → 过滤后计数
_dyld_get_image_name       → 索引重映射
_dyld_get_image_header     → 索引重映射
_dyld_get_image_vmaddr_slide → 索引重映射
dladdr                     → 命中自己的镜像时返回 0
CNCopyCurrentNetworkInfo / CNCopySupportedInterfaces → 可选屏蔽 WiFi 指纹
```

路径黑名单（大小写不敏感的子串匹配）覆盖 rootHide 结构：
`/.jbroot`、`.jbroot-`、`/basebin/`、`/.prelib`、`/.tweaked`、`tweakloader`、`roothide`、
`ellekit`、`substrate`、`substitute`、`libhooker`、`cydia`、`sileo`、`zebra`、`/var/lib/dpkg`、
`/etc/apt`、`/bin/bash`、`/usr/sbin/sshd` …

ObjC 层：`NSFileManager fileExistsAtPath:` / `contentsOfDirectoryAtPath:`、`NSProcessInfo environment`、
`UIApplication canOpenURL:`。

运行时：枚举所有类，方法名命中 `isJailbroken` / `jailbreakStatus` / `isRooted` / `isTampered` /
`isHooked` / `isInjected` 等且返回标量的方法，IMP 替换为返回 0。

> **注意**：rootHide 本身**不会**隐藏 dyld 镜像列表。它只做「黑名单进程不注入 + 环境变量抹除 + jbroot 随机化」。
> 你能在 `vmmap` 里看到 `bootstrap.dylib` / `TweakLoader.dylib` / `libellekit.dylib` / `libclx.dylib`，
> 所以 dyld 过滤必须由插件自己做（本版已做）。

---

## 8. 排障

| 现象 | 处理 |
|---|---|
| 打卡页位置没变 | ① 确认开关打开且选了点；② 开**严格模式**→重启 App；③ 还不行就开**深度模式**+**诊断日志**→重启→进打卡页→用文件管理器看 `WeCom/Library/Caches/.dbg` |
| 位置变了但地址/距离还是原来的 | 检查「坐标系」：自动不行就试「强制 GCJ-02」，再试「强制 WGS-84」。目标点偏离 300~600m 就是坐标系搞反了 |
| 地址对但差几十米 | 插件的抖动幅度导致的，属正常。要更精确就把「移动方式」设瞬移、「定位精度」设室外 |
| 提示「当前定位存在异常」 | 服务端/客户端识别。依次尝试：精度档位切「室内」、移动方式切「步行」并提前 5 分钟开、关掉「屏蔽 WiFi 指纹」、确认没开 VPN |
| 企业微信启动崩溃 | 关「深度模式」和「严格模式」再试；深度模式会 hook 业务层方法，版本差异大时容易崩 |
| 设置页打不开 | 连点要 1.2 秒内 5 次、位置基本不动。换个空白区域点 |
| 装了没反应 | `dpkg-deb -c` 确认包内路径无 `/var/jb`；`ls $(jbroot)/Library/MobileSubstrate/DynamicLibraries/` 确认 dylib 在；确认 `Bundles = com.tencent.ww` 与你的企业微信 bundle id 一致 |

诊断日志示例（`Library/Caches/.dbg`）：

```
[12:00:01.123] [init] libclx loaded, bundle=com.tencent.ww
[12:00:01.124] [L2] TencentLBS manager=1 location=1
[12:00:01.130] [guard] c-hooks installed (antiDetect=1, hideWiFi=0)
[12:00:03.620] [L1] delegate wrapped: WWKAttendanceBinaryCheckViewController
[12:00:03.700] [probe: WWKLocationRetriever count=42 :: ...]
```

- `TencentLBS manager=0` → 该版本没链腾讯定位 SDK，靠 L1/L3
- `delegate wrapped` 一直没出现 → 打卡页没用 `CLLocationManager`，开严格模式或深度模式
- `probe` 里能看到 4.x 的真实类名与方法名，可据此做精准 hook

---

## 9. 已知边界（做不到的部分）

诚实说明，避免误判：

1. **`dyld_all_image_infos` 残余**
   `_dyld_image_count` 系列已被过滤，但 `task_info(TASK_DYLD_INFO)` / `_dyld_get_all_image_infos()`
   仍能拿到原始镜像数组。要彻底覆盖需要返回改写后的结构体副本，本版未做。
2. **App bundle 内的注入痕迹**
   Bootstrap 改签过的 App 会有 `.prelib` / `.tweaked` / `.original` / `.jbroot`。
   本版对 `NSFileManager` 和 `stat` 做了隐藏，但 root 权限、调试器、备份仍可见。
3. **代码签名**
   rootHide 改签会改变 TeamID / 权限位（可能带 `get-task-allow`）。
   `SecCodeCopySigningInformation` 能读到，本版不处理。
4. **服务端规则**
   企业微信 4.1.26+ 后台有「防虚拟定位打卡」开关，属于**服务端+客户端联合判定**。
   客户端改坐标无法保证 100% 规避；后台可以选择「记录为地点异常」或「禁止打卡」。
5. **iOS 17 的 `CLLocationUpdate.liveUpdates`**
   若某个版本改用 Swift 并发取点（不经过 objc delegate），L1 会失效，需等 L3/深度模式。
6. **多账号 / 多开**
   企业微信多开容器的 bundle id 不同，`Bundles` 过滤不会注入，需要按实际 id 改 plist。

---

## 10. 免责

仅供本地测试与个人研究。虚拟定位打卡可能违反所在单位的考勤制度，
由此产生的后果（考勤异常、纪律处理等）由使用者自行承担。
