#!/usr/bin/env bash
# ============================================================================
#   谛听 (DITING) Linux 端卸载脚本
#
#   停止并禁用 systemd 服务，还原系统 DNS 接管，清理单元与环境文件。
#   默认保留 /etc/diting 配置与 /var/lib/diting 数据；使用 --purge 一并删除。
#
#   用法:
#     sudo ./uninstall.sh [--purge]
# ============================================================================

set -euo pipefail

PURGE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --purge) PURGE=1; shift ;;
        -h|--help)
            sed -n '2,11p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) echo "[错误] 未知参数: $1" >&2; exit 1 ;;
    esac
done

if [ "$(id -u)" != "0" ]; then
    echo "[错误] 请以 root 身份运行：sudo $0" >&2
    exit 1
fi

SERVICE_NAME="diting-dnsservice"
UNIT_PATH="/etc/systemd/system/${SERVICE_NAME}.service"
INSTALL_BIN="/usr/local/bin/diting-service"
CONFIG_DIR="/etc/diting"
DATA_DIR="/var/lib/diting"

echo "============================================================"
echo " 谛听 (DITING) Linux 卸载"
echo "============================================================"

echo "[1/5] 停止并禁用服务"
# 不再用 `systemctl list-unit-files | grep -q ...` 判断服务是否已注册。
# 在 `set -o pipefail` 下这是个必然踩中的坑：grep -q 命中首行即退出并关闭管道，
# systemctl 收到 SIGPIPE 以 141 退出，pipefail 使整条管道判定为失败，于是
# 「单元明明已注册」被当成「未发现」，服务未被停止就删掉了单元文件与二进制，
# 进程继续存活并占用 53 / Web 端口。
# 改为只要 systemd 可用就无条件尝试停止与禁用（单元不存在时 systemctl 自身
# 报错，由 `|| true` 吞掉），判断仅用于输出文案，且不经过管道。
if command -v systemctl >/dev/null 2>&1; then
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    if [ -f "$UNIT_PATH" ] || systemctl cat "$SERVICE_NAME" >/dev/null 2>&1; then
        echo "  已停止并禁用 $SERVICE_NAME。"
    else
        echo "  未发现已注册的 $SERVICE_NAME，跳过。"
    fi
else
    echo "  未检测到 systemd，跳过服务停止。"
fi

# 兜底：终止未受 systemd 托管（或单元已被移除）却仍在运行的残留进程，
# 否则二进制删除后进程仍存活并占用端口。
if command -v pgrep >/dev/null 2>&1; then
    BIN_NAME="$(basename "$INSTALL_BIN")"
    leftover="$(pgrep -x "$BIN_NAME" 2>/dev/null || true)"
    if [ -n "$leftover" ]; then
        echo "  发现残留进程 $(echo "$leftover" | tr '\n' ' ')，正在终止"
        kill $leftover 2>/dev/null || true
        sleep 1
        leftover="$(pgrep -x "$BIN_NAME" 2>/dev/null || true)"
        if [ -n "$leftover" ]; then
            kill -9 $leftover 2>/dev/null || true
        fi
    fi
fi

echo "[2/5] 还原系统 DNS 接管"
# 优先使用服务自带的应急还原能力（读取 dns_state.json 快照）
if [ -x "$INSTALL_BIN" ]; then
    "$INSTALL_BIN" -restore 2>/dev/null || true
fi
# 无快照可用时，若存在离线还原脚本则执行
for script in "$DATA_DIR/restore-dns.sh" "$CONFIG_DIR/restore-dns.sh"; do
    if [ -x "$script" ]; then
        echo "  执行离线还原脚本: $script"
        sh "$script" || true
    fi
done

echo "[3/5] 删除 systemd 单元与环境文件"
rm -f "$UNIT_PATH"
rm -f /etc/default/diting
systemctl daemon-reload || true

echo "[4/5] 删除可执行文件"
rm -f "$INSTALL_BIN"

echo "[5/5] 清理配置与数据"
if [ "$PURGE" -eq 1 ]; then
    rm -rf "$CONFIG_DIR" "$DATA_DIR"
    echo "  已删除 $CONFIG_DIR 与 $DATA_DIR"
else
    echo "  已保留 $CONFIG_DIR 与 $DATA_DIR（使用 --purge 可一并删除）"
fi

echo "============================================================"
echo " 卸载完成。"
echo " 提示: 若曾关闭 systemd-resolved 的 stub 监听器，可执行以下命令恢复："
echo "   sudo rm -f /etc/systemd/resolved.conf.d/diting.conf"
echo "   sudo systemctl restart systemd-resolved"
echo "============================================================"
