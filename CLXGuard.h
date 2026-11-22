//
//  CLXGuard.h
//  运行环境隐藏。
//
//  目标：让宿主 App 的越狱 / 注入 / 调试检测全部拿到"干净"的结果，
//  同时不改变宿主自身功能（不拦宿主自己沙箱内的文件操作）。
//

#import <Foundation/Foundation.h>

// 安装 C 函数层 hook（stat / getenv / fork / dyld 列表 / dladdr / ptrace / csops ...）
void CLXGuardInstall(void);

// 覆盖运行时找到的越狱检测方法（返回 0/NO）
void CLXGuardHookChecks(void);

// 路径是否属于越狱特征（供 NSFileManager 层复用）
BOOL CLXPathBlocked(NSString *path);
