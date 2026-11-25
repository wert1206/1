#!/bin/sh
# selfhost-kit / uninstall.sh
set -eu

COMPONENTS="xray,cns,amy4"
while [ $# -gt 0 ]; do
	case "$1" in
		--components) COMPONENTS="$2"; shift 2 ;;
		-h|--help) echo "用法: sudo ./uninstall.sh [--components xray,cns,amy4]"; exit 0 ;;
		*) echo "未知参数: $1" >&2; exit 2 ;;
	esac
done

[ "$(id -u)" = "0" ] || { echo "错误: 需要 root 权限" >&2; exit 1; }
has() { echo ",$COMPONENTS," | grep -q ",$1,"; }

for s in xray cns amy4; do
	has "$s" || continue
	if [ -f "/etc/systemd/system/$s.service" ]; then
		systemctl disable --now "$s" >/dev/null 2>&1 || true
		rm -f "/etc/systemd/system/$s.service"
		echo "==> 已停止并移除 $s.service"
	fi
done

systemctl daemon-reload
for s in xray cns amy4; do
	has "$s" || continue
	systemctl reset-failed "$s" >/dev/null 2>&1 || true
	rm -rf "/usr/local/$s"
	echo "==> 已删除 /usr/local/$s"
done

echo "卸载完成。"
