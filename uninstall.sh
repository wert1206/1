#!/bin/sh
# xray-deploy / uninstall.sh
set -eu

INSTALL_DIR="/usr/local/xray"
SERVICE_FILE="/etc/systemd/system/xray.service"
PORT=""

while [ $# -gt 0 ]; do
	case "$1" in
		--port) PORT="$2"; shift 2 ;;
		-h|--help) echo "用法: sudo ./uninstall.sh [--port <端口，用于回收防火墙规则>]"; exit 0 ;;
		*) echo "未知参数: $1" >&2; exit 2 ;;
	esac
done

[ "$(id -u)" = "0" ] || { echo "错误: 需要 root 权限运行" >&2; exit 1; }

if [ -f "$SERVICE_FILE" ]; then
	systemctl disable --now xray >/dev/null 2>&1 || true
	rm -f "$SERVICE_FILE"
	systemctl daemon-reload
	systemctl reset-failed xray >/dev/null 2>&1 || true
	echo "==> 已停止并移除 systemd 服务"
fi

if [ -n "$PORT" ]; then
	if command -v ufw >/dev/null 2>&1; then
		ufw delete allow "$PORT"/tcp >/dev/null 2>&1 || true
	fi
	if command -v firewall-cmd >/dev/null 2>&1; then
		firewall-cmd --remove-port="$PORT"/tcp --permanent >/dev/null 2>&1 || true
		firewall-cmd --reload >/dev/null 2>&1 || true
	fi
	echo "==> 已尝试回收 $PORT/tcp 防火墙规则"
fi

if [ -d "$INSTALL_DIR" ]; then
	rm -rf "$INSTALL_DIR"
	echo "==> 已删除 $INSTALL_DIR"
fi

echo "卸载完成。"
