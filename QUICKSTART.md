# 五分钟上手

你手上是**源码**，得先编译成 `.deb` 才能装。三条路，挑一条：

| 路线 | 需要什么 | 耗时 | 成本 |
|---|---|---|---|
| **A. GitHub Actions**（推荐） | 一个 GitHub 账号 | 10 分钟，第一次弄 | 免费 |
| **B. Mac 电脑** | 一台装 Xcode 的 Mac | 5 分钟 | 免费 |
| **C. 找人代编** | 把 `libclx-src.zip` 发给会的人 | 看对方 | — |

---

## 路线 A：GitHub Actions

### 1. 建仓库

1. 打开 https://github.com/new
2. **Repository name** 随便填，比如 `libclx`
3. 选 **Public**（公开仓库的 Actions 完全免费；私有仓库每月 2000 分钟也够，但公开更省事）
4. 不要勾 README / .gitignore / License
5. 点 **Create repository**

### 2. 上传代码

新仓库页面上会有个 **uploading an existing file** 的链接，点进去。

把这个目录里**除了 `tools/` 之外**的所有东西拖进去，注意要保留目录结构：

```
Makefile
control
libclx.plist
Tweak.xm
CLXGuard.h        CLXGuard.xm
CLXShared.h       CLXShared.m
CLXStore.h        CLXStore.m
CLXSession.h      CLXSession.m
CLXPanelController.h   CLXPanelController.m
CLXMapController.h     CLXMapController.m
README.md
QUICKSTART.md
build_local.sh
.github/workflows/build.yml      ← 这个最重要，别漏
```

> 网页拖拽对 `.github` 这种点开头的目录不友好。两个更稳的做法：
>
> **A. Git 命令行**
>
> ```bash
> cd wclocate-wecom
> git init
> git add -A
> git commit -m "init"
> git branch -M main
> git remote add origin https://github.com/你的用户名/libclx.git
> git push -u origin main
> ```
>
> **B. 网页手动建这一个文件**（不用装 Git）
>
> 1. 先把其余文件拖上去，Commit
> 2. 仓库页点 **Add file → Create new file**
> 3. 文件名框里直接填 `.github/workflows/build.yml`（斜杠会自动建目录）
> 4. 打开本地 `wclocate-wecom/.github/workflows/build.yml`，全选复制，粘进去
> 5. Commit

### 3. 等构建

1. 仓库页面点 **Actions** 标签
2. 左边选 **build**，右边会有一条正在跑的任务
3. 等 3~5 分钟，绿勾出现
4. 点进去，页面底部 **Artifacts** → 下载 `libclx-deb`
5. 解压得到 `libclx_1.0.0_iphoneos-arm64e.deb`

如果红了，点开失败的那一步，把报错发我。

---

## 路线 B：Mac

```bash
# 只用一次：装 theos（roothide fork，必须这个）
export THEOS=$HOME/theos
bash -c "$(curl -fsSL https://raw.githubusercontent.com/roothide/theos/master/bin/install-theos)"

# 编译
cd wclocate-wecom
chmod +x build_local.sh && ./build_local.sh
```

产物在 `packages/libclx_1.0.0_iphoneos-arm64e.deb`。

---

## 安装（两条路线都一样）

### 方式 1：Sileo / Zebra（简单）

把 deb 传到手机（AirDrop / 微信文件传输 / iCloud），用文件管理器点开 → 选 Sileo 打开 → 安装。

### 方式 2：命令行

```bash
# SSH 到手机，或者用 NewTerm
dpkg -i libclx_1.0.0_iphoneos-arm64e.deb
killall -9 WeCom 2>/dev/null
```

### 装完自检

```bash
jbroot
ls -l "$(jbroot)/Library/MobileSubstrate/DynamicLibraries/" | grep -i clx
```

应该看到 `libclx.dylib` 和 `libclx.plist` 两个文件。

---

## 用起来

1. 打开企业微信
2. **任意界面 1.2 秒内连点 5 次**（位置别乱动）
3. 弹出「位置」页
4. 点「选择目标位置」→ 地图拖到公司 / 搜公司名 → 确认
5. 回上一页，打开「启用虚拟定位」
6. 回打卡页，「当前位置」和「距离」应该立刻变成目标点

详细调参和排障看 [README.md](README.md)。

---

## 给我回传三样东西（决定下一步优化方向）

装好之后，麻烦回传：

1. **企业微信版本号**：企业微信 → 我 → 设置 → 关于企业微信
2. **iOS 版本**：设置 → 通用 → 关于本机
3. **诊断日志**：设置页打开「诊断日志」→ 进一次打卡页 → 停留 20 秒 → 用 Filza 打开
   `WeCom/Library/Caches/.dbg`（路径是 `/var/mobile/Containers/Data/Application/<一串UUID>/Library/Caches/.dbg`），把内容贴我

日志里会出现类似：

```
[12:00:01.124] [L2] TencentLBS manager=1 location=1
[12:00:03.620] [L1] delegate wrapped: WWKAttendanceBinaryCheckViewController
[12:00:03.700] [probe: WWKLocationRetriever count=42 :: xxx yyy zzz]
```

这三样决定了我要不要把这版从「靠腾讯 SDK + CoreLocation 兜底」升级成「按你的真实类名精准 hook」。
企业微信每个大版本都会改类名，日志能让我一次性对准。
