//
//  CLXGuard.xm
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <string.h>
#import <ctype.h>
#import <errno.h>
#import <stdio.h>
#import <unistd.h>
#import <fcntl.h>
#import <dirent.h>
#import <spawn.h>
#import <sys/stat.h>
#import <sys/sysctl.h>
#import <sys/proc.h>
#import <sys/types.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>

#import "CLXGuard.h"
#import "CLXShared.h"
#import "CLXStore.h"

#if __has_include(<substrate.h>)
#import <substrate.h>
#else
#ifdef __cplusplus
extern "C"
#endif
void MSHookFunction(void *symbol, void *replace, void **result);
#endif

#ifndef P_TRACED
#define P_TRACED 0x00000800
#endif

#define CLX_MAX_IMAGES 4096

static char gHome[PATH_MAX] = {0};
static size_t gHomeLen = 0;

#pragma mark - 特征匹配

// 越狱特征路径片段（大小写不敏感）
static const char *kBadPathParts[] = {
    // rootHide / roothide bootstrap
    "/jb",
    "jbroot",
    "/basebin/",
    "/.prelib",
    "/.tweaked",
    "/.rebuild",
    "tweakloader",
    "roothide",
    // 传统越狱
    "ellekit",
    "substrate",
    "substitute",
    "libhooker",
    "cydia",
    "sileo",
    "zebra",
    "unc0ver",
    "palera1n",
    "checkra1n",
    "dopamine",
    "rootlessjb",
    "/usr/libexec/sftp-server",
    "/usr/sbin/sshd",
    "/usr/bin/ssh",
    "/etc/apt",
    "/etc/apk",
    "/var/lib/dpkg",
    "/var/lib/apt",
    "/var/cache/apt",
    "/bin/bash",
    "/bin/sh",
    "/usr/bin/sshpass",
    "/Library/MobileSubstrate",
    "/Library/Themes",
    "/var/lib/filza",
    "/var/mobile/Library/Sileo",
    NULL
};

static BOOL CLXStringHit(const char *hay, const char *needle) {
    if (!hay || !needle) return NO;
    return strcasestr(hay, needle) != NULL;
}

// C 版本：**不要**在 stat 热路径里把 const char * 包成 NSString，
// 文件操作频率很高，每次分配对象会明显拖慢宿主。
static BOOL CLXPathHitC(const char *p) {
    if (!p || !*p) return NO;

    // 宿主自身数据沙箱一律放行，避免影响 App 正常读写
    if (gHomeLen && strncmp(p, gHome, gHomeLen) == 0) return NO;

    for (int i = 0; kBadPathParts[i]; i++) {
        if (CLXStringHit(p, kBadPathParts[i])) return YES;
    }
    return NO;
}

BOOL CLXPathBlocked(NSString *path) {
    if (!path.length) return NO;
    return CLXPathHitC(path.UTF8String);
}

// 镜像列表过滤
static const char *kBadImageParts[] = {
    "/.jbroot",
    ".jbroot-",
    "/basebin/",
    "/.prelib",
    "/.tweaked",
    "/jb",
    "jbroot",
    "tweakloader",
    "roothide",
    "ellekit",
    "substrate",
    "substitute",
    "libhooker",
    "tweakinject",
    "libclx",
    "dopamine",
    "rootless",
    "libkrw",
    NULL
};

static BOOL CLXImageIsOurs(const char *name) {
    if (!name) return NO;
    for (int i = 0; kBadImageParts[i]; i++) {
        if (CLXStringHit(name, kBadImageParts[i])) return YES;
    }
    return NO;
}

#pragma mark - 通用 hook 安装

static void *CLXSym(const char *name) {
    void *p = dlsym(RTLD_DEFAULT, name);
    if (p) return p;
    // 兼容旧架构导出名
    char alt[256];
    snprintf(alt, sizeof(alt), "%s$INODE64", name);
    return dlsym(RTLD_DEFAULT, alt);
}

static void CLXHook(const char *name, void *repl, void **orig) {
    void *sym = CLXSym(name);
    if (!sym) return;
    MSHookFunction(sym, repl, orig);
}

#pragma mark - stat / access / open 层

static int (*orig_stat)(const char *, struct stat *);
static int hook_stat(const char *path, struct stat *buf) {
    if (CLXPathHitC(path)) { errno = ENOENT; return -1; }
    return orig_stat(path, buf);
}

static int (*orig_lstat)(const char *, struct stat *);
static int hook_lstat(const char *path, struct stat *buf) {
    if (CLXPathHitC(path)) { errno = ENOENT; return -1; }
    return orig_lstat(path, buf);
}

static int (*orig_access)(const char *, int);
static int hook_access(const char *path, int mode) {
    if (CLXPathHitC(path)) { errno = ENOENT; return -1; }
    return orig_access(path, mode);
}

static int (*orig_faccessat)(int, const char *, int, int);
static int hook_faccessat(int fd, const char *path, int mode, int flag) {
    if (CLXPathHitC(path)) { errno = ENOENT; return -1; }
    return orig_faccessat(fd, path, mode, flag);
}

static int (*orig_fstatat)(int, const char *, struct stat *, int);
static int hook_fstatat(int fd, const char *path, struct stat *buf, int flag) {
    if (CLXPathHitC(path)) { errno = ENOENT; return -1; }
    return orig_fstatat(fd, path, buf, flag);
}

static DIR *(*orig_opendir)(const char *);
static DIR *hook_opendir(const char *path) {
    if (CLXPathHitC(path)) { errno = ENOENT; return NULL; }
    return orig_opendir(path);
}

#pragma mark - 环境变量

static char *(*orig_getenv)(const char *);
static const char *kBadEnv[] = {
    "DYLD_INSERT_LIBRARIES",
    "DYLD_LIBRARY_PATH",
    "DYLD_FRAMEWORK_PATH",
    "DYLD_FALLBACK_LIBRARY_PATH",
    "DYLD_FALLBACK_FRAMEWORK_PATH",
    "DYLD_ROOT_PATH",
    "DYLD_SHARED_CACHE_DIR",
    "DYLD_PRINT_LIBRARIES",
    "_MSSafeMode",
    "JB_ROOT",
    "_JB_ROOT",
    "JBROOT",
    NULL
};

static char *hook_getenv(const char *name) {
    if (name && name[0]) {
        char c = name[0];
        if (c == 'D' || c == '_' || c == 'J' || c == 'j') {
            for (int i = 0; kBadEnv[i]; i++) {
                if (!strcmp(name, kBadEnv[i])) return NULL;
            }
        }
    }
    return orig_getenv(name);
}

#pragma mark - 进程 / 调试

static pid_t (*orig_fork)(void);
static pid_t hook_fork(void) {
    errno = EPERM;
    return -1;
}

static int (*orig_posix_spawn)(pid_t *, const char *,
                               const posix_spawn_file_actions_t *,
                               const posix_spawnattr_t *,
                               char *const[], char *const[]);
static int hook_posix_spawn(pid_t *pid, const char *path,
                            const posix_spawn_file_actions_t *fa,
                            const posix_spawnattr_t *attr,
                            char *const argv[], char *const envp[]) {
    return EPERM;
}

static int (*orig_ptrace)(int, pid_t, caddr_t, int);
static int hook_ptrace(int req, pid_t pid, caddr_t addr, int data) {
    if (req == 31 /* PT_DENY_ATTACH */) return 0;
    return orig_ptrace(req, pid, addr, data);
}

static int (*orig_sysctl)(int *, u_int, void *, size_t *, void *, size_t);
static int hook_sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    int r = orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);
    if (r == 0 && oldp && oldlenp && namelen >= 4 &&
        name[0] == CTL_KERN && name[1] == KERN_PROC) {
        size_t n = *oldlenp / sizeof(struct kinfo_proc);
        struct kinfo_proc *kp = (struct kinfo_proc *)oldp;
        for (size_t i = 0; i < n; i++) {
            kp[i].kp_proc.p_flag &= ~P_TRACED;
        }
    }
    return r;
}

static int (*orig_csops)(pid_t, unsigned int, void *, size_t);
static int hook_csops(pid_t pid, unsigned int ops, void *addr, size_t size) {
    int r = orig_csops(pid, ops, addr, size);
    // CS_OPS_STATUS == 0 ：清掉 CS_DEBUGGED，避免"进程被调试/注入"判定
    if (r == 0 && ops == 0 && addr && size >= sizeof(uint32_t)) {
        uint32_t *flags = (uint32_t *)addr;
        *flags &= ~(uint32_t)0x10000000u;   // CS_DEBUGGED
    }
    return r;
}

#pragma mark - dyld 镜像列表

static uint32_t (*orig_image_count)(void);
static const char *(*orig_image_name)(uint32_t);
static const struct mach_header *(*orig_image_header)(uint32_t);

static uint32_t gMap[CLX_MAX_IMAGES];
static uint32_t gMapCount = 0;
static uint32_t gMapSourceN = 0;
static BOOL gMapReady = NO;

static void CLXBuildImageMap(void) {
    uint32_t n = orig_image_count ? orig_image_count() : 0;
    if (n > CLX_MAX_IMAGES) n = CLX_MAX_IMAGES;
    gMapCount = 0;
    for (uint32_t i = 0; i < n; i++) {
        const char *nm = orig_image_name ? orig_image_name(i) : NULL;
        if (CLXImageIsOurs(nm)) continue;
        gMap[gMapCount++] = i;
    }
    gMapSourceN = n;
    gMapReady = YES;
}

static uint32_t hook_image_count(void) {
    uint32_t n = orig_image_count();
    if (!gMapReady || n != gMapSourceN) CLXBuildImageMap();
    return gMapCount;
}

static const char *hook_image_name(uint32_t idx) {
    hook_image_count();
    if (idx >= gMapCount) return NULL;
    return orig_image_name(gMap[idx]);
}

static const struct mach_header *hook_image_header(uint32_t idx) {
    hook_image_count();
    if (idx >= gMapCount) return NULL;
    return orig_image_header(gMap[idx]);
}

static intptr_t (*orig_image_slide)(uint32_t);
static intptr_t hook_image_slide(uint32_t idx) {
    hook_image_count();
    if (idx >= gMapCount) return 0;
    return orig_image_slide ? orig_image_slide(gMap[idx]) : 0;
}

#pragma mark - dladdr

static int (*orig_dladdr)(const void *, Dl_info *);
static int hook_dladdr(const void *addr, Dl_info *info) {
    int r = orig_dladdr(addr, info);
    if (r && info && CLXImageIsOurs(info->dli_fname)) {
        memset(info, 0, sizeof(Dl_info));
        return 0;
    }
    return r;
}

#pragma mark - WiFi / 网络指纹

static CFDictionaryRef (*orig_CNCopyCurrentNetworkInfo)(CFStringRef);
static CFDictionaryRef hook_CNCopyCurrentNetworkInfo(CFStringRef ifname) {
    if ([CLXStore hideWiFi]) return NULL;
    return orig_CNCopyCurrentNetworkInfo ? orig_CNCopyCurrentNetworkInfo(ifname) : NULL;
}

static CFArrayRef (*orig_CNCopySupportedInterfaces)(void);
static CFArrayRef hook_CNCopySupportedInterfaces(void) {
    if ([CLXStore hideWiFi]) {
        static CFArrayRef empty = NULL;
        if (!empty) empty = CFArrayCreate(NULL, NULL, 0, &kCFTypeArrayCallBacks);
        return empty;
    }
    return orig_CNCopySupportedInterfaces ? orig_CNCopySupportedInterfaces() : NULL;
}

#pragma mark - 安装

void CLXGuardInstall(void) {
    NSString *home = NSHomeDirectory();
    if (home.length) {
        strlcpy(gHome, home.UTF8String, sizeof(gHome));
        gHomeLen = strlen(gHome);
    }

    if (![CLXStore antiDetect]) return;

    // 文件层
    CLXHook("stat",  (void *)hook_stat,  (void **)&orig_stat);
    CLXHook("lstat", (void *)hook_lstat, (void **)&orig_lstat);
    CLXHook("access", (void *)hook_access, (void **)&orig_access);
    CLXHook("faccessat", (void *)hook_faccessat, (void **)&orig_faccessat);
    CLXHook("fstatat", (void *)hook_fstatat, (void **)&orig_fstatat);
    CLXHook("opendir", (void *)hook_opendir, (void **)&orig_opendir);

    // 环境变量
    CLXHook("getenv", (void *)hook_getenv, (void **)&orig_getenv);

    // 进程 / 调试
    CLXHook("fork", (void *)hook_fork, (void **)&orig_fork);
    CLXHook("posix_spawn", (void *)hook_posix_spawn, (void **)&orig_posix_spawn);
    CLXHook("ptrace", (void *)hook_ptrace, (void **)&orig_ptrace);
    CLXHook("sysctl", (void *)hook_sysctl, (void **)&orig_sysctl);
    CLXHook("csops", (void *)hook_csops, (void **)&orig_csops);

    // dyld 镜像列表（rootHide 不会帮你隐藏这些，必须自己过滤）
    CLXHook("_dyld_image_count", (void *)hook_image_count, (void **)&orig_image_count);
    CLXHook("_dyld_get_image_name", (void *)hook_image_name, (void **)&orig_image_name);
    CLXHook("_dyld_get_image_header", (void *)hook_image_header, (void **)&orig_image_header);
    CLXHook("_dyld_get_image_vmaddr_slide", (void *)hook_image_slide, (void **)&orig_image_slide);
    CLXHook("dladdr", (void *)hook_dladdr, (void **)&orig_dladdr);

    // WiFi 指纹
    CLXHook("CNCopyCurrentNetworkInfo", (void *)hook_CNCopyCurrentNetworkInfo, (void **)&orig_CNCopyCurrentNetworkInfo);
    CLXHook("CNCopySupportedInterfaces", (void *)hook_CNCopySupportedInterfaces, (void **)&orig_CNCopySupportedInterfaces);

    CLXLog(@"[guard] c-hooks installed (antiDetect=1, hideWiFi=%d)", (int)[CLXStore hideWiFi]);
}

#pragma mark - 运行时越狱检测方法覆盖

static BOOL clx_return_no(id self, SEL _cmd) {
    return NO;
}

static BOOL CLXMethodLooksLikeCheck(const char *name) {
    if (!name) return NO;
    char low[192];
    size_t n = strlen(name);
    if (n == 0 || n >= sizeof(low)) return NO;
    for (size_t i = 0; i <= n; i++) low[i] = (char)tolower((unsigned char)name[i]);

    static const char *exact[] = {
        "isjailbroken", "isjailbreak", "isjb", "jailbroken", "jailbreakstatus",
        "checkjailbreak", "detectjailbreak", "isdevicejailbroken", "isjailbreakdevice",
        "isrooted", "isdevicerooted", "istampered", "ishooked", "isinjected",
        "hasinjectedlibrary", "isdylibinjected", "jailbreakcheck", "isjailbreakdetected",
        NULL
    };
    for (int i = 0; exact[i]; i++) {
        if (!strcmp(low, exact[i])) return YES;
    }
    if (strstr(low, "jailbreak")) return YES;
    if (strstr(low, "jailbroken")) return YES;
    return NO;
}

static BOOL CLXReturnTypeIsScalar(Method m) {
    const char *t = method_getTypeEncoding(m);
    if (!t) return NO;
    const char c = t[0];
    return (c == 'B' || c == 'c' || c == 'i' || c == 'I' ||
            c == 's' || c == 'S' || c == 'l' || c == 'L' ||
            c == 'q' || c == 'Q');
}

void CLXGuardHookChecks(void) {
    if (![CLXStore antiDetect]) return;

    int total = objc_getClassList(NULL, 0);
    if (total <= 0) return;

    Class *classes = (Class *)malloc(sizeof(Class) * (size_t)total);
    if (!classes) return;
    total = objc_getClassList(classes, total);

    NSUInteger patched = 0;

    for (int i = 0; i < total; i++) {
        Class cls = classes[i];
        if (!cls) continue;

        for (int pass = 0; pass < 2; pass++) {
            Class target = (pass == 0) ? cls : object_getClass(cls);
            if (!target) continue;

            unsigned int count = 0;
            Method *methods = class_copyMethodList(target, &count);
            if (!methods) continue;

            for (unsigned int j = 0; j < count; j++) {
                Method m = methods[j];
                const char *sel = sel_getName(method_getName(m));
                if (!CLXMethodLooksLikeCheck(sel)) continue;
                if (!CLXReturnTypeIsScalar(m)) continue;

                IMP cur = method_getImplementation(m);
                if (cur == (IMP)clx_return_no) continue;

                method_setImplementation(m, (IMP)clx_return_no);
                patched++;
                CLXLog(@"[guard] patch %s -%s", class_getName(cls), sel);
            }
            free(methods);
        }
    }

    free(classes);
    CLXLog(@"[guard] runtime checks patched = %lu", (unsigned long)patched);
}

#pragma mark - ObjC 层配合

%hook NSFileManager

- (BOOL)fileExistsAtPath:(NSString *)path {
    if ([CLXStore antiDetect] && CLXPathBlocked(path)) return NO;
    return %orig;
}

- (BOOL)fileExistsAtPath:(NSString *)path isDirectory:(BOOL *)isDirectory {
    if ([CLXStore antiDetect] && CLXPathBlocked(path)) {
        if (isDirectory) *isDirectory = NO;
        return NO;
    }
    return %orig;
}

- (NSArray<NSString *> *)contentsOfDirectoryAtPath:(NSString *)path error:(NSError **)error {
    if ([CLXStore antiDetect] && CLXPathBlocked(path)) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError userInfo:nil];
        return nil;
    }
    return %orig;
}

%end

%hook NSProcessInfo

- (NSDictionary<NSString *, NSString *> *)environment {
    NSDictionary *env = %orig;
    if (![CLXStore antiDetect] || !env.count) return env;

    NSMutableDictionary *clean = [NSMutableDictionary dictionaryWithCapacity:env.count];
    for (NSString *key in env) {
        if ([key hasPrefix:@"DYLD_"]) continue;
        if ([key isEqualToString:@"_MSSafeMode"]) continue;
        if ([key isEqualToString:@"JB_ROOT"] || [key isEqualToString:@"_JB_ROOT"]) continue;
        clean[key] = env[key];
    }
    return clean;
}

%end

%hook UIApplication

- (BOOL)canOpenURL:(NSURL *)url {
    if ([CLXStore antiDetect]) {
        NSString *s = url.absoluteString.lowercaseString;
        static NSArray *jailSchemes = nil;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            jailSchemes = @[@"cydia://", @"sileo://", @"zbra://", @"filza://",
                            @"undecimus://", @"activator://", @"prefs://"];
        });
        for (NSString *scheme in jailSchemes) {
            if ([s hasPrefix:scheme]) return NO;
        }
    }
    return %orig;
}

%end

%ctor {
    @autoreleasepool {
        CLXGuardInstall();
        // 避开 App 启动头 2 秒的检测密集窗口，再扫全类
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            CLXGuardHookChecks();
        });
    }
}
