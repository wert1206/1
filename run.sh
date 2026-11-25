#!/bin/sh
# run.sh —— 一键安装（不问任何问题）
#
# 默认装 xray(443, tcp http) + cns(80) + amy4(18443)，凭据随机生成。
# 想改端口就透传参数，例如：sh run.sh --xray-port 8443 --cns-port 8080
#
# 用法：
#   curl -fsSL <本脚本地址> | sh
#   sh run.sh --dry-run       # 只校验+生成配置，不动系统
#
set -eu

KIT_URL="https://aka.doubaocdn.com/s/hoQcKwnetc"
KIT_SHA="e86b3a4f107ac06cfcc930dcaae93d41d09d83db95e1f84bf20ddd408b63bf73"

die() { echo "错误: $*" >&2; exit 1; }

DRY=0
for a in "$@"; do
	[ "$a" = "--dry-run" ] && DRY=1
done

if [ "$DRY" = "0" ] && [ "$(id -u)" != "0" ]; then
	if command -v sudo >/dev/null 2>&1; then
		exec sudo -E sh "$0" "$@"
	fi
	die "需要 root 权限（或先加 --dry-run 做校验）"
fi

command -v tar >/dev/null 2>&1 || die "缺少 tar"
command -v sha256sum >/dev/null 2>&1 || die "缺少 sha256sum"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

echo "==> 下载套件（约 19 MB）"
if command -v curl >/dev/null 2>&1; then
	curl -fsSL --proto '=https' --tlsv1.2 "$KIT_URL" -o "$TMP/kit.tar.gz" || die "下载失败"
elif command -v wget >/dev/null 2>&1; then
	wget -q --https-only "$KIT_URL" -O "$TMP/kit.tar.gz" || die "下载失败"
else
	die "缺少 curl / wget"
fi

echo "==> 校验 SHA-256"
printf '%s  %s\n' "$KIT_SHA" "$TMP/kit.tar.gz" | sha256sum -c - >/dev/null 2>&1 \
	|| die "校验失败，包被替换或不完整（期望 $KIT_SHA）"

echo "==> 解压并安装"
tar xzf "$TMP/kit.tar.gz" -C "$TMP"
[ -f "$TMP/selfhost-kit/install.sh" ] || die "包结构异常"

sh "$TMP/selfhost-kit/install.sh" "$@"

if [ "$DRY" = "1" ]; then exit 0; fi

# ---- 装完把客户端要用的东西打出来 ----
echo
echo "======== 客户端参数 ========"

IP=$(curl -fsS --max-time 6 https://api.ipify.org 2>/dev/null \
	|| curl -fsS --max-time 6 http://ip.sb/ 2>/dev/null \
	|| echo "服务器公网IP")

XJ=/usr/local/xray/xray.json
if [ -f "$XJ" ]; then
	UUID=$(sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$XJ" | head -1)
	PORT=$(sed -n 's/.*"port"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' "$XJ" | head -1)
	MODE=$(grep -q '"tcpSettings"' "$XJ" && echo "tcp + http 伪装" || echo "见 $XJ")
	echo
	echo "[xray / vmess]"
	echo "  地址     $IP"
	echo "  端口     ${PORT:-443}"
	echo "  传输     $MODE"
	echo "  UUID     $UUID"
	echo "  额外ID   0"
	echo "  加密     none"
	if command -v base64 >/dev/null 2>&1; then
		LINK=$(printf '{"v":"2","ps":"selfhost","add":"%s","port":"%s","id":"%s","aid":"0","net":"tcp","type":"http","host":"","path":"","tls":""}' \
			"$IP" "${PORT:-443}" "$UUID" | base64 -w0 2>/dev/null)
		[ -n "$LINK" ] && echo "  链接     vmess://$LINK"
	fi
fi

CJ=/usr/local/cns/cns.json
if [ -f "$CJ" ]; then
	echo
	echo "[cns]"
	echo "  地址     $IP"
	echo "  端口     $(sed -n 's/.*"Listen_addr"[[:space:]]*:[[:space:]]*\[":\([0-9]*\)".*/\1/p' "$CJ")"
	echo "  密码     $(sed -n 's/.*"Encrypt_password"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$CJ")"
	echo "  头域     $(sed -n 's/.*"Proxy_key"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$CJ")"
fi

AJ=/usr/local/amy4/amy4.json
if [ -f "$AJ" ]; then
	echo
	echo "[amy4]"
	echo "  地址     $IP"
	echo "  端口     $(sed -n 's/.*"ListenAddr"[[:space:]]*:[[:space:]]*":\([0-9]*\)".*/\1/p' "$AJ")"
	echo "  ClientKey $(sed -n 's/.*"ClientKeys"[[:space:]]*:[[:space:]]*\["\([^"]*\)"\].*/\1/p' "$AJ")"
fi

echo
echo "服务状态: systemctl status xray cns amy4 --no-pager"
echo "卸载:     sh uninstall.sh（从套件目录运行），或 systemctl disable --now xray cns amy4"
