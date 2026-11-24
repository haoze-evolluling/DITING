#!/usr/bin/env bash
# ============================================================================
#   谛听 (DITING) OpenWrt 路由端构建与 .ipk 打包脚本
#
#   在 Linux 主机或 WSL 中使用 musl + crt-static 编译零外部依赖的 diting-service
#   纯静态单二进制（内嵌 Web 管理端），并可组装兼容 OpenWrt 21.02~24.10 /
#   ImmortalWrt / iStoreOS（opkg，fw3/fw4 自适应）的 .ipk 安装包。
#
#   用法:
#     ./build_openwrt.sh                        # 构建 x86_64 musl 静态二进制
#     ./build_openwrt.sh -a arm64 --package     # 构建 aarch64 .ipk 安装包
#     ./build_openwrt.sh -a both --package      # 同时构建 x86_64 与 aarch64 .ipk
#     ./build_openwrt.sh -v 2.3.0 --package     # 指定版本号（默认读 ./VERSION）
#     ./build_openwrt.sh --clean                # 先清理旧 OpenWrt 产物
#     ./build_openwrt.sh --skip-ui              # 跳过前端构建（复用现有 dist）
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
    sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

while [ $# -gt 0 ]; do
    case "$1" in
        -a|--arch)       ARCH="$2"; shift 2 ;;
        -v|--version)    VERSION="$2"; shift 2 ;;
        -b|--build-type) BUILD_TYPE="$2"; shift 2 ;;
        -o|--output)     OUTPUT_DIR="$2"; shift 2 ;;
        --clean)         CLEAN=1; shift ;;
        --package)       PACKAGE=1; shift ;;
        --skip-ui)       SKIP_UI=1; shift ;;
        -h|--help)       usage ;;
        *) echo "[错误] 未知参数: $1" >&2; usage 1 ;;
    esac
done

case "$ARCH" in
    amd64|x86_64)  TARGET_ARCHES=("x86_64") ;;
    arm64|aarch64) TARGET_ARCHES=("aarch64") ;;
    both)          TARGET_ARCHES=("x86_64" "aarch64") ;;
    *)
        echo "[错误] OpenWrt 构建仅支持架构: amd64(x86_64) / arm64(aarch64) / both，收到: $ARCH" >&2
        exit 1
        ;;
esac

case "$BUILD_TYPE" in
    release|debug) ;;
    *) echo "[错误] 不支持的构建类型: $BUILD_TYPE (可选: release / debug)" >&2; exit 1 ;;
esac

VERSION_FILE="$SCRIPT_DIR/VERSION"
if [ -z "$VERSION" ]; then
    VERSION="$(awk 'NF && $1 !~ /^#/ { sub(/^v/, ""); sub(/\+.*/, ""); print; exit }' "$VERSION_FILE" 2>/dev/null || true)"
    VERSION="${VERSION:-0.0.0}"
fi

BIN_NAME="diting-service"
INIT_SCRIPT_SRC="$SCRIPT_DIR/build/openwrt/diting.init"
if [ ! -f "$INIT_SCRIPT_SRC" ]; then
    echo "[错误] 缺少 OpenWrt procd 启动脚本模板: $INIT_SCRIPT_SRC" >&2
    exit 1
fi

if [ "$CLEAN" -eq 1 ]; then
    echo ">>> 清理旧 OpenWrt 构建产物: $OUTPUT_DIR"
    rm -f "$OUTPUT_DIR"/${BIN_NAME}-openwrt-*
    rm -f "$OUTPUT_DIR"/diting_*_openwrt_*.ipk
fi
mkdir -p "$OUTPUT_DIR"

echo "============================================================"
echo " 谛听 (DITING) OpenWrt 构建 (musl + crt-static)"
echo " 目标架构: ${TARGET_ARCHES[*]}   版本: $VERSION   类型: $BUILD_TYPE"
echo "============================================================"

UI_DIR="$SCRIPT_DIR/../../desktop/ui"
if [ "$SKIP_UI" -eq 0 ] && [ -d "$UI_DIR" ]; then
    if command -v npm >/dev/null 2>&1; then
        if [ ! -d "$UI_DIR/node_modules" ]; then
            echo ">>> 正在安装桌面管理端依赖 (npm ci)..."
            ( cd "$UI_DIR" && npm ci ) || exit 1
        fi
        echo ">>> 正在构建管理端前端 (npm run build)..."
        ( cd "$UI_DIR" && npm run build ) || exit 1
    else
        echo "[警告] 未找到 npm，跳过 Web 管理页构建；请确认 desktop/ui/dist 已存在。" >&2
    fi
fi

if ! command -v cargo >/dev/null 2>&1; then
    if [ -x "$HOME/.cargo/bin/cargo" ]; then
        export PATH="$HOME/.cargo/bin:$PATH"
    else
        echo "[错误] 未找到 Rust 工具链（cargo），请先安装 rustup: https://rustup.rs" >&2
        exit 1
    fi
fi

RUST_DIR="$SCRIPT_DIR/../../rust"
HOST_UNAME="$(uname -m 2>/dev/null || echo unknown)"

assemble_ipk() {
    local bin_file="$1"
    local pkg_arch="$2"
    local expected_uname="$3"
    local ipk_name="diting_${VERSION}_openwrt_${pkg_arch}.ipk"
    local ipk_path="$OUTPUT_DIR/$ipk_name"

    local stage_dir
    stage_dir="$(mktemp -d /tmp/diting-ipk.XXXXXX 2>/dev/null || mktemp -d)"
    local data_dir="$stage_dir/data"
    local ctrl_dir="$stage_dir/control"
    local out_dir="$stage_dir/ipk"

    mkdir -p "$data_dir/usr/bin" "$data_dir/etc/init.d" "$data_dir/etc/diting"
    mkdir -p "$ctrl_dir" "$out_dir"

    cp "$bin_file" "$data_dir/usr/bin/$BIN_NAME"
    chmod 0755 "$data_dir/usr/bin/$BIN_NAME"
    tr -d '\r' < "$INIT_SCRIPT_SRC" > "$data_dir/etc/init.d/diting"
    chmod 0755 "$data_dir/etc/init.d/diting"
    chmod 0700 "$data_dir/etc/diting"

    local installed_size
    installed_size="$(wc -c < "$data_dir/usr/bin/$BIN_NAME" | tr -d '[:space:]')"

    cat > "$ctrl_dir/control" <<EOF
Package: diting
Version: $VERSION
Depends: libc
Section: net
Priority: optional
Architecture: all
Maintainer: DITING <https://github.com/haoze-evolluling/diting>
Installed-Size: ${installed_size:-0}
Description: 谛听 (DITING) OpenWrt 智能 DNS 与规则拦截服务
 纯 Rust 静态链接单二进制 DNS 引擎，内嵌 Web 管理端 (:15353)，
 支持替换 dnsmasq 53 端口与作为 dnsmasq 上游双模式、UCI 防火墙联动及闪存冷热分库。
EOF

    cat > "$ctrl_dir/conffiles" <<'EOF'
/etc/diting/
EOF

    cat > "$ctrl_dir/preinst" <<EOF
#!/bin/sh
if [ -z "\${IPKG_INSTROOT:-}" ]; then
    HOST_ARCH="\$(uname -m 2>/dev/null || echo unknown)"
    if [ "\$HOST_ARCH" != "$expected_uname" ]; then
        echo "[DITING] 架构不匹配: 当前设备为 \${HOST_ARCH}，此安装包仅适用于 $expected_uname。" >&2
        exit 1
    fi
fi
exit 0
EOF

    cat > "$ctrl_dir/postinst" <<'EOF'
#!/bin/sh
[ -n "${IPKG_INSTROOT:-}" ] && exit 0

mkdir -p /etc/diting /tmp/diting
chmod 0700 /etc/diting /tmp/diting

if [ -f /etc/sysupgrade.conf ]; then
    grep -qxF '/etc/diting/' /etc/sysupgrade.conf 2>/dev/null || echo '/etc/diting/' >> /etc/sysupgrade.conf
else
    echo '/etc/diting/' > /etc/sysupgrade.conf
fi

if command -v uci >/dev/null 2>&1; then
    uci -q batch <<'UCIEOF' || true
set firewall.diting_web_lan='rule'
set firewall.diting_web_lan.name='DITING-Web-LAN'
set firewall.diting_web_lan.src='lan'
set firewall.diting_web_lan.proto='tcp'
set firewall.diting_web_lan.dest_port='15353'
set firewall.diting_web_lan.target='ACCEPT'
set firewall.diting_web_lan.enabled='1'
commit firewall
UCIEOF
    /etc/init.d/firewall reload >/dev/null 2>&1 || fw4 reload >/dev/null 2>&1 || true
fi

if [ -x /etc/init.d/diting ]; then
    /etc/init.d/diting enable >/dev/null 2>&1 || true
    /etc/init.d/diting restart >/dev/null 2>&1 || /etc/init.d/diting start >/dev/null 2>&1 || true
fi

LAN_IP="$(uci -q get network.lan.ipaddr 2>/dev/null | awk '{print $1}' | cut -d/ -f1)"
LAN_IP="${LAN_IP:-192.168.1.1}"
echo "============================================================"
echo " 谛听 (DITING) OpenWrt 服务已安装并启动"
echo " 管理界面: http://${LAN_IP}:15353"
echo " 说明: 默认仅启动管理界面，不会立即改动 dnsmasq 53 端口；"
echo "       请登录 Web 管理端完成管理员设置并开启路由器 DNS 接管。"
echo "============================================================"
exit 0
EOF

    cat > "$ctrl_dir/prerm" <<'EOF'
#!/bin/sh
[ -n "${IPKG_INSTROOT:-}" ] && exit 0

if [ -x /etc/init.d/diting ]; then
    /etc/init.d/diting stop >/dev/null 2>&1 || true
    /etc/init.d/diting disable >/dev/null 2>&1 || true
fi

if [ -x /usr/bin/diting-service ]; then
    /usr/bin/diting-service -restore >/dev/null 2>&1 || true
fi

if command -v uci >/dev/null 2>&1; then
    uci -q delete firewall.diting_web_lan || true
    uci -q delete firewall.diting_dns_lan || true
    uci -q delete firewall.diting_dns_redirect || true
    uci -q commit firewall || true
    /etc/init.d/firewall reload >/dev/null 2>&1 || fw4 reload >/dev/null 2>&1 || true
fi
exit 0
EOF

    chmod 0644 "$ctrl_dir/control" "$ctrl_dir/conffiles"
    chmod 0755 "$ctrl_dir/preinst" "$ctrl_dir/postinst" "$ctrl_dir/prerm"

    printf '2.0\n' > "$out_dir/debian-binary"
    ( cd "$ctrl_dir" && tar --numeric-owner --owner=0 --group=0 -cf - . | gzip -n > "$out_dir/control.tar.gz" )
    ( cd "$data_dir" && tar --numeric-owner --owner=0 --group=0 -cf - . | gzip -n > "$out_dir/data.tar.gz" )
    ( cd "$out_dir" && tar --numeric-owner --owner=0 --group=0 -cf - ./debian-binary ./control.tar.gz ./data.tar.gz | gzip -n > "$ipk_path" )

    rm -rf "$stage_dir"
    echo "[OK] 已生成 OpenWrt 安装包: $ipk_path ($(du -h "$ipk_path" | cut -f1))"
}

# cargo-zigbuild 需要 PATH 中存在名为 `zig` 的可执行文件；PyPI 的 ziglang 只提供
# `python3 -m ziglang`，这里按需生成一个轻量 shim，让文档中的安装方式即可用。
ensure_zig_on_path() {
    if command -v zig >/dev/null 2>&1; then
        return 0
    fi
    if ! python3 -c 'import ziglang' >/dev/null 2>&1; then
        return 1
    fi
    local shim_dir="$HOME/.cargo/bin"
    mkdir -p "$shim_dir" || return 1
    if [ ! -x "$shim_dir/zig" ]; then
        printf '#!/bin/sh\nexec python3 -m ziglang "$@"\n' > "$shim_dir/zig" || return 1
        chmod +x "$shim_dir/zig" || return 1
    fi
    case ":$PATH:" in
        *":$shim_dir:"*) ;;
        *) export PATH="$shim_dir:$PATH" ;;
    esac
    return 0
}

build_one_arch() {
    local pkg_arch="$1"
    local rust_target=""
    local expected_uname=""

    case "$pkg_arch" in
        x86_64)
            rust_target="x86_64-unknown-linux-musl"
            expected_uname="x86_64"
            ;;
        aarch64)
            rust_target="aarch64-unknown-linux-musl"
            expected_uname="aarch64"
            ;;
    esac

    if command -v rustup >/dev/null 2>&1; then
        if ! rustup target list --installed 2>/dev/null | grep -qx "$rust_target"; then
            echo ">>> 正在安装 Rust 目标工具链: $rust_target ..."
            rustup target add "$rust_target"
        fi
    fi

    local use_zigbuild=0
    if command -v cargo-zigbuild >/dev/null 2>&1 && ensure_zig_on_path; then
        use_zigbuild=1
        echo ">>> 使用 cargo-zigbuild 交叉编译 ($(zig version 2>/dev/null || echo zig))..."
    fi

    local subcmd="build"
    if [ "$use_zigbuild" -eq 1 ]; then
        subcmd="zigbuild"
    elif [ "$pkg_arch" = "aarch64" ] && [ "$HOST_UNAME" != "aarch64" ]; then
        if [ -z "${CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER:-}" ]; then
            if command -v aarch64-linux-musl-gcc >/dev/null 2>&1; then
                export CC_aarch64_unknown_linux_musl="aarch64-linux-musl-gcc"
                export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER="aarch64-linux-musl-gcc"
            elif command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then
                export CC_aarch64_unknown_linux_musl="aarch64-linux-gnu-gcc"
                export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER="aarch64-linux-gnu-gcc"
            else
                echo "[错误] 交叉编译 $rust_target 需要 zig + cargo-zigbuild 或 aarch64 交叉链接器。" >&2
                echo "       推荐安装: cargo install cargo-zigbuild && pip install ziglang" >&2
                echo "       或安装交叉工具链: sudo apt install musl-tools gcc-aarch64-linux-gnu" >&2
                exit 1
            fi
        fi
    elif [ "$pkg_arch" = "x86_64" ]; then
        # ring 的汇编与 rusqlite 的内置 SQLite 都要用 musl 目标的 C 编译器；
        # 部分发行版的 musl-tools 只提供 musl-gcc，没有带三元组前缀的封装，故两者都探测。
        if [ -z "${CC_x86_64_unknown_linux_musl:-}" ]; then
            if command -v x86_64-linux-musl-gcc >/dev/null 2>&1; then
                export CC_x86_64_unknown_linux_musl="x86_64-linux-musl-gcc"
            elif command -v musl-gcc >/dev/null 2>&1; then
                export CC_x86_64_unknown_linux_musl="musl-gcc"
            else
                echo "[错误] 编译 ring 与内置 SQLite 需要 musl 目标的 C 工具链，但未找到" >&2
                echo "       x86_64-linux-musl-gcc 或 musl-gcc。" >&2
                echo "       Ubuntu/Debian 请执行: sudo apt install musl-tools" >&2
                exit 1
            fi
        fi
    fi

    local cargo_args=("$subcmd" --target "$rust_target" -p diting-desktop-service)
    local profile_dir="debug"
    if [ "$BUILD_TYPE" = "release" ]; then
        cargo_args=("$subcmd" --release --target "$rust_target" -p diting-desktop-service)
        profile_dir="release"
    fi

    echo ">>> 正在编译 $BIN_NAME ($rust_target, cargo $subcmd, +crt-static)..."
    (
        cd "$RUST_DIR"
        export RUSTFLAGS="${RUSTFLAGS:-} -C target-feature=+crt-static"
        cargo "${cargo_args[@]}"
    ) || exit 1

    local bin_src="$RUST_DIR/target/$rust_target/$profile_dir/$BIN_NAME"
    if [ ! -f "$bin_src" ]; then
        echo "[错误] 编译失败，未找到产物: $bin_src" >&2
        exit 1
    fi

    local out_bin="$OUTPUT_DIR/${BIN_NAME}-openwrt-${pkg_arch}"
    cp "$bin_src" "$out_bin"
    chmod 0755 "$out_bin"
    echo "[OK] OpenWrt 静态二进制就绪: $out_bin ($(du -h "$out_bin" | cut -f1))"

    if [ "$PACKAGE" -eq 1 ]; then
        assemble_ipk "$out_bin" "$pkg_arch" "$expected_uname"
        rm -f "$out_bin"
    fi
}

for target_arch in "${TARGET_ARCHES[@]}"; do
    build_one_arch "$target_arch"
done

echo "============================================================"
if [ "$PACKAGE" -eq 1 ]; then
    echo " OpenWrt .ipk 构建完成。路由器安装命令示例:"
    for target_arch in "${TARGET_ARCHES[@]}"; do
        echo "   opkg install $OUTPUT_DIR/diting_${VERSION}_openwrt_${target_arch}.ipk"
    done
else
    echo " OpenWrt 二进制构建完成:"
    for target_arch in "${TARGET_ARCHES[@]}"; do
        echo "   $OUTPUT_DIR/${BIN_NAME}-openwrt-${target_arch}"
    done
fi
echo "   默认 Web 管理端端口: http://<路由器LAN_IP>:15353"
echo "============================================================"
