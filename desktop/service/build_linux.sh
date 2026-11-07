#!/usr/bin/env bash
# ============================================================================
#   谛听 (DITING) Linux 端构建脚本
#
#   在 Linux 主机本地（或在 WSL 中）构建 diting-service 单二进制，
#   可选打包为 .deb 发行包。
#
#   用法:
#     ./build_linux.sh                    # 构建 amd64 二进制
#     ./build_linux.sh -a arm64           # 构建 arm64 二进制
#     ./build_linux.sh -v 2.3.0           # 手动指定版本号（默认读 ../app/pubspec.yaml）
#     ./build_linux.sh --package          # 打包为 .deb 发行包
#     ./build_linux.sh --prebuilt         # 复用 build/bin/diting-service（Windows 交叉编译）
#     ./build_linux.sh --clean            # 先清理旧产物
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

ARCH="amd64"
VERSION=""
BUILD_TYPE="release"
CLEAN=0
PACKAGE=0
PREBUILT=0
OUTPUT_DIR="$SCRIPT_DIR/build/bin"

usage() {
    sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

while [ $# -gt 0 ]; do
    case "$1" in
        -a|--arch)    ARCH="$2"; shift 2 ;;
        -v|--version) VERSION="$2"; shift 2 ;;
        -b|--build-type) BUILD_TYPE="$2"; shift 2 ;;
        -o|--output)  OUTPUT_DIR="$2"; shift 2 ;;
        --clean)      CLEAN=1; shift ;;
        --package)    PACKAGE=1; shift ;;
        --prebuilt)   PREBUILT=1; shift ;;
        -h|--help)    usage ;;
        *) echo "[错误] 未知参数: $1" >&2; usage 1 ;;
    esac
done

case "$ARCH" in
    amd64|arm64|arm) ;;
    *) echo "[错误] 不支持的架构: $ARCH (可选: amd64 / arm64 / arm)" >&2; exit 1 ;;
esac

# 版本号唯一真源是桌面端 pubspec.yaml（Flutter 强制要求那里有 version 行），
# 这里只负责读取，不再从 Go 源码里抠字面量。
PUBSPEC_FILE="$SCRIPT_DIR/../app/pubspec.yaml"
if [ -z "$VERSION" ]; then
    VERSION="$(sed -n 's/^version:[[:space:]]*\([^+ ]*\).*/\1/p' "$PUBSPEC_FILE" 2>/dev/null | head -n1 || true)"
    VERSION="${VERSION:-0.0.0}"
fi

GIT_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
BUILD_TIME="$(date -Iseconds)"

BIN_NAME="diting-service"
BIN_PATH="$OUTPUT_DIR/$BIN_NAME"

if [ "$CLEAN" -eq 1 ]; then
    # 仅清理本脚本自身的 Linux 产物（二进制 / 旧 .deb / 临时目录），保留同目录下的 Windows 安装包
    echo ">>> 清理旧构建产物 (仅 Linux 侧): $OUTPUT_DIR"
    if [ "$PREBUILT" -eq 0 ]; then
        rm -f "$OUTPUT_DIR/$BIN_NAME"
    fi
    rm -rf "$OUTPUT_DIR"/diting_*_linux_*
fi
mkdir -p "$OUTPUT_DIR"

if [ "$BUILD_TYPE" = "release" ]; then
    LDFLAGS="-s -w -X main.Version=$VERSION -X main.GitCommit=$GIT_COMMIT -X main.BuildTime=$BUILD_TIME"
else
    LDFLAGS="-X main.Version=$VERSION -X main.GitCommit=$GIT_COMMIT -X main.BuildTime=$BUILD_TIME"
fi

echo "============================================================"
echo " 谛听 (DITING) Linux 构建"
echo " 目标架构: linux/$ARCH   版本: $VERSION   类型: $BUILD_TYPE"
echo "============================================================"

if [ "$PREBUILT" -eq 1 ]; then
    if [ ! -f "$BIN_PATH" ]; then
        echo "[错误] --prebuilt 需要已存在的 Linux 二进制: $BIN_PATH" >&2
        exit 1
    fi
    echo ">>> 复用预编译 Linux 二进制: $BIN_PATH"
else
    if ! command -v go >/dev/null 2>&1; then
        if [ -x /usr/local/go/bin/go ]; then
            export PATH="$PATH:/usr/local/go/bin"
        else
            echo "[错误] 未找到 Go 工具链，请先安装 Go 1.25+，或在 Windows 侧交叉编译后使用 --prebuilt。" >&2
            exit 1
        fi
    fi
    echo ">>> 正在编译 $BIN_NAME ..."
    CGO_ENABLED=0 GOOS=linux GOARCH="$ARCH" go build -trimpath -ldflags "$LDFLAGS" -o "$BIN_PATH" ./cmd/service

    if [ ! -f "$BIN_PATH" ]; then
        echo "[错误] 编译失败，未生成 $BIN_PATH" >&2
        exit 1
    fi
fi
chmod +x "$BIN_PATH"
echo "[OK] Linux 二进制就绪: $BIN_PATH ($(du -h "$BIN_PATH" | cut -f1))"

# ---------------------------------------------------------------------------
# Rust 内核（rust/diting-stamp-core、diting-filter-core、diting-rewrite-core、diting-safebrowsing-core、diting-hosts-core、diting-dns64-core、diting-ratelimit-core）
#
# Go 侧在运行期用纯 Go 动态加载它们（不链接、不依赖 cgo），所以它们都必须随二进制一起交付：
# deb 装到 /usr/lib/diting/，服务按该路径探测；缺任一库即服务启动失败，没有降级实现。
# ---------------------------------------------------------------------------
RUST_DIR="$SCRIPT_DIR/../../rust"
# crate 名:动态库基名
RUST_KERNELS="diting-stamp-core:diting_stamp_core diting-filter-core:diting_filter_core diting-rewrite-core:diting_rewrite_core diting-safebrowsing-core:diting_safebrowsing_core diting-hosts-core:diting_hosts_core diting-dns64-core:diting_dns64_core diting-ratelimit-core:diting_ratelimit_core"
case "$ARCH" in
    amd64) RUST_TARGET="x86_64-unknown-linux-gnu" ; RUST_TARGET_ARCH="x86_64" ;;
    arm64) RUST_TARGET="aarch64-unknown-linux-gnu" ; RUST_TARGET_ARCH="aarch64" ;;
    arm)   RUST_TARGET="armv7-unknown-linux-gnueabihf" ; RUST_TARGET_ARCH="armv7" ;;
esac
case "$(uname -m)" in
    x86_64|amd64)   RUST_HOST_ARCH="x86_64" ;;
    aarch64|arm64)  RUST_HOST_ARCH="aarch64" ;;
    armv7l|armv8l|arm) RUST_HOST_ARCH="armv7" ;;
    *)              RUST_HOST_ARCH="$(uname -m)" ;;
esac

# rust_lib_path <库基名> —— 本机架构直接取 release 目录，交叉编译取目标三元组目录
rust_lib_path() {
    if [ "$RUST_HOST_ARCH" = "$RUST_TARGET_ARCH" ]; then
        echo "$RUST_DIR/target/release/lib$1.so"
    else
        echo "$RUST_DIR/target/$RUST_TARGET/release/lib$1.so"
    fi
}

build_rust_kernel() {
    crate="$1"
    base="$2"
    lib="$(rust_lib_path "$base")"
    [ -f "$lib" ] && echo "[OK] Rust 内核就绪: $lib ($(du -h "$lib" | cut -f1))" && return 0

    if ! command -v cargo >/dev/null 2>&1; then
        echo "[错误] 未找到 Rust 工具链（cargo），也没有可复用的内核: $lib" >&2
        echo "       请安装 rustup 后重试；或先在目标架构上执行:" >&2
        echo "       cargo build --release -p $crate --target $RUST_TARGET" >&2
        return 1
    fi
    echo ">>> 正在编译 Rust 内核 ($crate, linux/$ARCH)..."
    if [ "$RUST_HOST_ARCH" = "$RUST_TARGET_ARCH" ]; then
        ( cd "$RUST_DIR" && cargo build --release -p "$crate" ) || return 1
    else
        ( cd "$RUST_DIR" && cargo build --release -p "$crate" --target "$RUST_TARGET" ) || return 1
    fi
    if [ ! -f "$lib" ]; then
        echo "[错误] Rust 内核编译失败，未生成 $lib" >&2
        echo "       交叉编译需要 rustup target add $RUST_TARGET 与对应的交叉链接器。" >&2
        return 1
    fi
    echo "[OK] Rust 内核就绪: $lib ($(du -h "$lib" | cut -f1))"
}

for entry in $RUST_KERNELS; do
    build_rust_kernel "${entry%%:*}" "${entry##*:}" || exit 1
done

# ---------------------------------------------------------------------------
# 发行包
# ---------------------------------------------------------------------------
if [ "$PACKAGE" -eq 1 ]; then
    # Go 的 GOARCH=arm 对应 Debian 归档架构 armhf（ARMv7 硬浮点，与默认 GOARM=7 一致）
    case "$ARCH" in
        arm) DEB_ARCH="armhf" ;;
        *)   DEB_ARCH="$ARCH" ;;
    esac

    PKG_NAME="diting_${VERSION}_linux_${ARCH}"
    TMP_STAGE="$(mktemp -d /tmp/diting-pkg.XXXXXX 2>/dev/null || mktemp -d)"
    PKG_DIR="$TMP_STAGE/$PKG_NAME"

    echo ">>> 正在组装发行包: $PKG_NAME"
    rm -rf "$PKG_DIR"
    mkdir -p "$PKG_DIR/usr/local/bin"
    mkdir -p "$PKG_DIR/usr/lib/diting"
    mkdir -p "$PKG_DIR/usr/share/diting"
    mkdir -p "$PKG_DIR/lib/systemd/system"
    mkdir -p "$PKG_DIR/etc/diting"
    mkdir -p "$PKG_DIR/usr/share/applications"
    mkdir -p "$PKG_DIR/usr/share/pixmaps"

    cp "$BIN_PATH" "$PKG_DIR/usr/local/bin/$BIN_NAME"
    # 服务按 /usr/lib/diting 探测七个 Rust 内核，装在这里无需任何环境变量或 rpath
    for entry in $RUST_KERNELS; do
        base="${entry##*:}"
        lib="$(rust_lib_path "$base")"
        cp "$lib" "$PKG_DIR/usr/lib/diting/lib$base.so"
        chmod 0755 "$PKG_DIR/usr/lib/diting/lib$base.so"
    done
    cp "build/linux/diting-dnsservice.service" "$PKG_DIR/lib/systemd/system/"
    chmod 0644 "$PKG_DIR/lib/systemd/system/diting-dnsservice.service"
    cp "build/linux/install.sh" "$PKG_DIR/usr/share/diting/install.sh"
    cp "build/linux/uninstall.sh" "$PKG_DIR/usr/share/diting/uninstall.sh"
    chmod 0755 "$PKG_DIR/usr/share/diting/install.sh" "$PKG_DIR/usr/share/diting/uninstall.sh"

    if [ -f "build/appicon.png" ]; then
        cp "build/appicon.png" "$PKG_DIR/usr/share/pixmaps/diting.png"
        chmod 0644 "$PKG_DIR/usr/share/pixmaps/diting.png"
    fi

    cat > "$PKG_DIR/usr/share/applications/diting.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Diting DNS
Name[zh_CN]=谛听 DNS
Comment=Diting DNS Management Console
Comment[zh_CN]=谛听 DNS 管理控制台
Exec=xdg-open http://127.0.0.1:15353
Icon=diting
Terminal=false
Categories=Network;System;
EOF
    chmod 0644 "$PKG_DIR/usr/share/applications/diting.desktop"

    if command -v dpkg-deb >/dev/null 2>&1; then
        mkdir -p "$PKG_DIR/DEBIAN"
        chmod 0755 "$PKG_DIR/DEBIAN"
        cat > "$PKG_DIR/DEBIAN/control" <<EOF
Package: diting
Version: $VERSION
Section: net
Priority: optional
Architecture: $DEB_ARCH
Maintainer: DITING <https://github.com/haoze-evolluling/diting>
Description: 谛听 (DITING) DNS 内核特权服务
 谛听 DNS 内核的 Linux 端特权服务，负责系统 DNS 接管、
 多协议上游转发、本地缓存与规则拦截，并内嵌 Web 控制台。
EOF

        cat > "$PKG_DIR/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
systemctl daemon-reload || true
systemctl enable diting-dnsservice.service || true
echo "谛听 DNS 服务已安装。请执行 'systemctl start diting-dnsservice' 启动，"
echo "或运行 'diting-service -service install' 完成注册。"
exit 0
EOF

        cat > "$PKG_DIR/DEBIAN/prerm" <<'EOF'
#!/bin/sh
set -e
systemctl stop diting-dnsservice.service || true
systemctl disable diting-dnsservice.service || true
exit 0
EOF

        chmod 0755 "$PKG_DIR/DEBIAN/postinst" "$PKG_DIR/DEBIAN/prerm"
    fi

    # .deb 安装包（仅保留此最终产物）
    if [ -d "$PKG_DIR/DEBIAN" ] && command -v dpkg-deb >/dev/null 2>&1; then
        DEB="$OUTPUT_DIR/${PKG_NAME}.deb"
        dpkg-deb --build --root-owner-group "$PKG_DIR" "$DEB" >/dev/null
        echo "[OK] 已生成 Debian 安装包: $DEB"
        # 仅保留 .deb 安装包，清理临时中间二进制
        rm -f "$BIN_PATH"
    else
        echo "[错误] 未找到 dpkg-deb 工具，无法生成 .deb 安装包。" >&2
        rm -rf "$TMP_STAGE"
        exit 1
    fi

    rm -rf "$TMP_STAGE"
fi

echo "============================================================"
if [ "$PACKAGE" -eq 1 ]; then
    echo " 构建完成。仅保留 .deb 安装包（中间二进制已清理）:"
    echo "   sudo dpkg -i $DEB"
    echo "   或解包后执行: sudo /usr/share/diting/install.sh"
else
    echo " 构建完成。安装方式:"
    echo "   sudo install -m 0755 $BIN_PATH /usr/local/bin/$BIN_NAME"
    echo "   sudo install -d -m 0755 /usr/lib/diting"
    for entry in $RUST_KERNELS; do
        base="${entry##*:}"
        echo "   sudo install -m 0755 $(rust_lib_path "$base") /usr/lib/diting/lib$base.so"
    done
    echo "   sudo $BIN_NAME -service install && sudo $BIN_NAME -service start"
fi
echo "   管理地址: http://127.0.0.1:15353"
echo "============================================================"
