#!/usr/bin/env bash
# ============================================================================
#   谛听 (DITING) Linux 端安装脚本
#
#   将 diting-service 安装为 systemd 系统服务，创建数据目录与默认配置，
#   并注册开机自启。需以 root 身份运行。
#
#   用法:
#     sudo ./install.sh [--bin /path/to/diting-service] [--port 53] [--no-start]
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_SRC=""
WEB_PORT=15353
DNS_PORT=53
AUTO_START=1

SERVICE_NAME="diting-dnsservice"
UNIT_PATH="/etc/systemd/system/${SERVICE_NAME}.service"
INSTALL_BIN="/usr/local/bin/diting-service"
CONFIG_DIR="/etc/diting"
DATA_DIR="/var/lib/diting"
SERVICE_USER="root"

while [ $# -gt 0 ]; do
    case "$1" in
        --bin)      BIN_SRC="$2"; shift 2 ;;
        --port)     DNS_PORT="$2"; shift 2 ;;
        --web-port) WEB_PORT="$2"; shift 2 ;;
        --no-start) AUTO_START=0; shift ;;
        -h|--help)
            sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) echo "[错误] 未知参数: $1" >&2; exit 1 ;;
    esac
done

if [ "$(id -u)" != "0" ]; then
    echo "[错误] 请以 root 身份运行：sudo $0" >&2
    exit 1
fi

if ! command -v systemctl >/dev/null 2>&1; then
    echo "[错误] 未检测到 systemd，本脚本仅支持 systemd 发行版。" >&2
    exit 1
fi

# 定位二进制：显式参数 → 同目录 → 上级 build/bin → PATH
if [ -z "$BIN_SRC" ]; then
    for candidate in \
        "$SCRIPT_DIR/diting-service" \
        "$SCRIPT_DIR/../bin/diting-service" \
        "$(command -v diting-service 2>/dev/null || true)"; do
        if [ -n "$candidate" ] && [ -f "$candidate" ]; then
            BIN_SRC="$candidate"
            break
        fi
    done
fi
if [ -z "$BIN_SRC" ] || [ ! -f "$BIN_SRC" ]; then
    echo "[错误] 未找到 diting-service 二进制，请通过 --bin 指定路径。" >&2
    exit 1
fi

echo "============================================================"
echo " 谛听 (DITING) Linux 安装"
echo " 二进制来源: $BIN_SRC"
echo " DNS 端口: $DNS_PORT   Web 端口: $WEB_PORT"
echo "============================================================"

echo "[1/6] 安装可执行文件 -> $INSTALL_BIN"
install -d -m 0755 "$(dirname "$INSTALL_BIN")"
install -m 0755 "$BIN_SRC" "$INSTALL_BIN"

echo "[2/6] 创建配置目录 $CONFIG_DIR 与数据目录 $DATA_DIR"
install -d -m 0700 "$CONFIG_DIR"
install -d -m 0700 "$DATA_DIR"
install -d -m 0700 "$DATA_DIR/filters"
install -d -m 0700 "$DATA_DIR/backups"

echo "[3/6] 写入 systemd 单元 -> $UNIT_PATH"
if [ -f "$SCRIPT_DIR/diting-dnsservice.service" ]; then
    install -m 0644 "$SCRIPT_DIR/diting-dnsservice.service" "$UNIT_PATH"
else
    cat > "$UNIT_PATH" <<EOF
[Unit]
Description=谛听 DNS 内核特权服务 (DITING DNS Service)
Documentation=https://github.com/haoze-evolluling/diting
After=syslog.target network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=-/etc/default/diting
EnvironmentFile=-/etc/sysconfig/diting
ExecStart=${INSTALL_BIN} -run
Restart=always
RestartSec=10
LimitNOFILE=65536
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
fi

echo "[4/6] 写入环境文件 /etc/default/diting"
cat > /etc/default/diting <<EOF
# 谛听 (DITING) 运行环境（可选覆盖）
# DITING_DATA_DIR=/var/lib/diting
# DITING_PORT=${DNS_PORT}
EOF
chmod 0644 /etc/default/diting

echo "[5/6] 重载 systemd 并启用开机自启"
systemctl daemon-reload
systemctl enable "$SERVICE_NAME" >/dev/null

echo "[6/6] 启动服务"
if [ "$AUTO_START" -eq 1 ]; then
    systemctl restart "$SERVICE_NAME"
    sleep 1
    systemctl --no-pager --lines=0 status "$SERVICE_NAME" || true
else
    echo "已跳过启动（--no-start）。可执行: systemctl start $SERVICE_NAME"
fi

echo "============================================================"
echo " 安装完成。"
echo "   管理地址: http://127.0.0.1:${WEB_PORT}"
echo "   查看日志: journalctl -u $SERVICE_NAME -f"
echo "   卸载服务: sudo $SCRIPT_DIR/uninstall.sh"
echo "============================================================"
echo "提示: 若 53 端口被 systemd-resolved 的 stub 监听器占用，"
echo "      可在 Web 控制台执行【一键自动修复】，或手动关闭 DNSStubListener。"
