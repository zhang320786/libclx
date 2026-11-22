#!/bin/bash
# libclx 一键编译脚本（macOS + Theos）
set -e

cd "$(dirname "$0")"

if [ -z "$THEOS" ]; then
    if [ -d "$HOME/theos" ]; then
        export THEOS="$HOME/theos"
    else
        echo "==> 未找到 Theos，正在安装 roothide/theos ..."
        export THEOS="$HOME/theos"
        bash -c "$(curl -fsSL https://raw.githubusercontent.com/roothide/theos/master/bin/install-theos)"
    fi
fi

echo "==> THEOS = $THEOS"

if [ ! -d "$THEOS/vendor/mod/roothide" ]; then
    echo "!! 当前 Theos 没有 roothide scheme"
    echo "!! 你需要 roothide/theos，而不是上游 theos："
    echo "   bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/roothide/theos/master/bin/install-theos)\""
    exit 1
fi

if ! command -v ldid >/dev/null 2>&1; then
    echo "==> 安装 ldid / dpkg"
    brew install ldid dpkg 2>/dev/null || true
fi

echo "==> 清理"
make clean 2>/dev/null || true

echo "==> 构建"
make package FINALPACKAGE=1

DEB=$(ls -t packages/*.deb 2>/dev/null | head -n1)
if [ -z "$DEB" ]; then
    echo "!! 没有生成 deb"
    exit 1
fi

echo
echo "==> 产物: $DEB"
dpkg-deb -f "$DEB" Package Version Architecture Depends

if dpkg-deb -c "$DEB" | grep -q '\./var/jb/'; then
    echo "!! 包内出现 /var/jb 前缀，rootHide 上装不上"
    exit 1
fi

if ! dpkg-deb -c "$DEB" | grep -q 'MobileSubstrate/DynamicLibraries'; then
    echo "!! 找不到 DynamicLibraries 目录"
    exit 1
fi

echo
echo "==> 检查通过，拷到手机后："
echo "    dpkg -i $(basename "$DEB") && killall -9 WeCom"
