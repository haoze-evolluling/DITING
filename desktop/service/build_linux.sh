#!/usr/bin/env bash
# ============================================================================
#   谛听 (DITING) Linux 端构建脚本
#
#   在 Linux 主机本地（或在 WSL 中）用 cargo 构建纯 Rust 的 diting-service 单二进制，
#   可选打包为 .deb 发行包。二进制静态链接全部内核，不再附带 .so。
#
#   用法:
#     ./build_linux.sh                    # 构建 amd64 二进制
#     ./build_linux.sh -a arm64           # 构建 arm64 二进制
#     ./build_linux.sh -v 2.3.0           # 指定 deb 版本号（默认读 ./VERSION）
#     ./build_linux.sh --package          # 打包为 .deb 发行包
#     ./build_linux.sh --clean            # 先清理旧产物
#     ./build_linux.sh --skip-ui          # 跳过前端构建（使用现有 dist）
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

ARCH="amd64"
VERSION=""
BUILD_TYPE="release"
CLEAN=0
PACKAGE=0
SKIP_UI=0
OUTPUT_DIR="$SCRIPT_DIR/build/bin"

usage() {
    sed -n '2,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
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
        --skip-ui)    SKIP_UI=1; shift ;;
        -h|--help)    usage ;;
        *) echo "[错误] 未知参数: $1" >&2; usage 1 ;;
    esac
done

case "$ARCH" in
    amd64|arm64|arm) ;;
    *) echo "[错误] 不支持的架构: $ARCH (可选: amd64 / arm64 / arm)" >&2; exit 1 ;;
esac

VERSION_FILE="$SCRIPT_DIR/VERSION"
if [ -z "$VERSION" ]; then
    VERSION="$(awk 'NF && $1 !~ /^#/ { sub(/^v/, ""); sub(/\+.*/, ""); print; exit }' "$VERSION_FILE" 2>/dev/null || true)"
    VERSION="${VERSION:-0.0.0}"
fi


BIN_NAME="diting-service"
BIN_PATH="$OUTPUT_DIR/$BIN_NAME"

if [ "$CLEAN" -eq 1 ]; then
    echo ">>> 清理旧构建产物 (仅 Linux 侧): $OUTPUT_DIR"
    rm -f "$OUTPUT_DIR/$BIN_NAME"
    rm -rf "$OUTPUT_DIR"/diting_*_linux_*
fi
mkdir -p "$OUTPUT_DIR"

echo "============================================================"
echo " 谛听 (DITING) Linux 构建"
echo " 目标架构: linux/$ARCH   版本: $VERSION   类型: $BUILD_TYPE"
echo "============================================================"

UI_DIR="$SCRIPT_DIR/../../desktop/ui"
if [ "$SKIP_UI" -eq 0 ] && [ -d "$UI_DIR" ]; then
    if command -v npm >/dev/null 2>&1; then
        if [ ! -d "$UI_DIR/node_modules" ]; then
            echo ">>> 正在安装桌面管理端依赖 (npm ci)..."
            ( cd "$UI_DIR" && npm ci ) || exit 1
        fi
        echo ">>> 正在构建桌面管理端前端 (npm run build)..."
        ( cd "$UI_DIR" && npm run build ) || exit 1
    else
        echo "[警告] 未找到 npm，跳过 Web 管理页构建；服务将返回占位页。" >&2
    fi
fi

RUST_DIR="$SCRIPT_DIR/../../rust"
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

if ! command -v cargo >/dev/null 2>&1; then
    if [ -x "$HOME/.cargo/bin/cargo" ]; then
        export PATH="$PATH:$HOME/.cargo/bin"
    else
        echo "[错误] 未找到 Rust 工具链（cargo），请先安装 rustup: https://rustup.rs" >&2
        exit 1
    fi
fi

CARGO_ARGS=(build -p diting-desktop-service)
if [ "$BUILD_TYPE" = "release" ]; then
    CARGO_ARGS=(build --release -p diting-desktop-service)
fi
if [ "$RUST_HOST_ARCH" = "$RUST_TARGET_ARCH" ]; then
    CARGO_PROFILE_DIR="$RUST_DIR/target"
else
    CARGO_ARGS+=(--target "$RUST_TARGET")
    CARGO_PROFILE_DIR="$RUST_DIR/target/$RUST_TARGET"
fi
if [ "$BUILD_TYPE" = "release" ]; then
    BIN_SRC="$CARGO_PROFILE_DIR/release/$BIN_NAME"
else
    BIN_SRC="$CARGO_PROFILE_DIR/debug/$BIN_NAME"
fi

echo ">>> 正在编译 $BIN_NAME (cargo ${CARGO_ARGS[*]}) ..."
( cd "$RUST_DIR" && cargo "${CARGO_ARGS[@]}" ) || exit 1
if [ ! -f "$BIN_SRC" ]; then
    echo "[错误] 编译失败，未生成 $BIN_SRC" >&2
    echo "       交叉编译需要 rustup target add $RUST_TARGET 与对应的交叉链接器。" >&2
    exit 1
fi
cp "$BIN_SRC" "$BIN_PATH"
chmod +x "$BIN_PATH"
echo "[OK] Linux 二进制就绪: $BIN_PATH ($(du -h "$BIN_PATH" | cut -f1))"

if [ "$PACKAGE" -eq 1 ]; then
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
    mkdir -p "$PKG_DIR/usr/share/diting"
    mkdir -p "$PKG_DIR/lib/systemd/system"
    mkdir -p "$PKG_DIR/etc/diting"
    mkdir -p "$PKG_DIR/usr/share/pixmaps"

    cp "$BIN_PATH" "$PKG_DIR/usr/local/bin/$BIN_NAME"
    chmod 0755 "$PKG_DIR/usr/local/bin/$BIN_NAME"
    cp "build/linux/diting-dnsservice.service" "$PKG_DIR/lib/systemd/system/"
    chmod 0644 "$PKG_DIR/lib/systemd/system/diting-dnsservice.service"
    cp "build/linux/install.sh" "$PKG_DIR/usr/share/diting/install.sh"
    cp "build/linux/uninstall.sh" "$PKG_DIR/usr/share/diting/uninstall.sh"
    chmod 0755 "$PKG_DIR/usr/share/diting/install.sh" "$PKG_DIR/usr/share/diting/uninstall.sh"

    if [ -f "build/appicon.png" ]; then
        cp "build/appicon.png" "$PKG_DIR/usr/share/pixmaps/diting.png"
        chmod 0644 "$PKG_DIR/usr/share/pixmaps/diting.png"
    fi

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
 多协议上游转发、本地缓存与规则拦截，并提供管理 API。
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

    if [ -d "$PKG_DIR/DEBIAN" ] && command -v dpkg-deb >/dev/null 2>&1; then
        DEB="$OUTPUT_DIR/${PKG_NAME}.deb"
        dpkg-deb --build --root-owner-group "$PKG_DIR" "$DEB" >/dev/null
        echo "[OK] 已生成 Debian 安装包: $DEB"
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
    echo "   sudo $BIN_NAME -service install && sudo $BIN_NAME -service start"
fi
echo "   管理 API: http://127.0.0.1:15353"
echo "============================================================"
