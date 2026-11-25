#!/bin/sh
# run.sh —— 一键安装 + 状态查看 + 改端口/改密码
#
#   sh run.sh                            装（xray:443 + cns:80 + amy4:18443）
#   sh run.sh status                     看状态、端口、当前凭据、客户端参数（不重装）
#   sh run.sh --xray-port 8443 --keep    只改 xray 端口，其余凭据不变
#   sh run.sh --cns-password 新密码 --keep
#
set -eu

KIT_URL="https://aka.doubaocdn.com/s/TIwY2x7EgP"
KIT_SHA="2a1c3c255af2fa41c984d3e7262d6c4e8877a8ff156239c350612de0e681f4b2"
CACHE_DIR="/var/cache/selfhost-kit"

die() { echo "错误: $*" >&2; exit 1; }

cfg() { sed -n "$1" "$2" 2>/dev/null | head -1; }

xray_json=/usr/local/xray/xray.json
cns_json=/usr/local/cns/cns.json
amy4_json=/usr/local/amy4/amy4.json

xray_port() { cfg 's/.*"port"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' "$xray_json"; }
xray_uuid() { cfg 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$xray_json"; }
cns_port()  { cfg 's/.*"Listen_addr"[[:space:]]*:[[:space:]]*\[":\([0-9]*\)".*/\1/p' "$cns_json"; }
cns_pw()    { cfg 's/.*"Encrypt_password"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$cns_json"; }
cns_key()   { cfg 's/.*"Proxy_key"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$cns_json"; }
amy4_port() { cfg 's/.*"ListenAddr"[[:space:]]*:[[:space:]]*":\([0-9]*\)".*/\1/p' "$amy4_json"; }
amy4_key()  { cfg 's/.*"ClientKeys"[[:space:]]*:[[:space:]]*\["\([^"]*\)"\].*/\1/p' "$amy4_json"; }

is_active() { systemctl is-active "$1" >/dev/null 2>&1; }
listening() { ss -lnt 2>/dev/null | grep -qE "[:.]$1[[:space:]]"; }

show_status() {
	echo "======== 服务状态 ========"
	for s in xray cns amy4; do
		[ -d "/usr/local/$s" ] || continue
		if is_active "$s"; then st="运行中"; else st="未运行"; fi
		case "$s" in
			xray) p=$(xray_port) ;;
			cns)  p=$(cns_port) ;;
			amy4) p=$(amy4_port) ;;
		esac
		if [ -n "${p:-}" ] && listening "$p"; then pt=":$p 已监听"; else pt=":${p:-?} 未监听"; fi
		printf '  %-6s %-8s %s\n' "$s" "$st" "$pt"
	done
	echo "  详情: systemctl status xray cns amy4 --no-pager"
	echo "  启停: systemctl {start|stop|restart|status} xray / cns / amy4"
	echo "  配置: /usr/local/xray/xray.json  /usr/local/cns/cns.json  /usr/local/amy4/amy4.json"
}

show_params() {
	IP=$(curl -fsS --max-time 6 https://api.ipify.org 2>/dev/null \
		|| curl -fsS --max-time 6 http://ip.sb/ 2>/dev/null || echo "服务器公网IP")

	echo
	echo "======== 客户端参数 ========"
	if [ -f "$xray_json" ]; then
		p=$(xray_port); u=$(xray_uuid)
		echo
		echo "[xray / vmess]"
		echo "  地址     $IP"
		echo "  端口     $p"
		echo "  传输     tcp + http 伪装"
		echo "  UUID     $u"
		echo "  额外ID   0"
		echo "  加密     none"
		if command -v base64 >/dev/null 2>&1 && [ -n "$p" ] && [ -n "$u" ]; then
			link=$(printf '{"v":"2","ps":"selfhost","add":"%s","port":"%s","id":"%s","aid":"0","net":"tcp","type":"http","host":"","path":"","tls":""}' \
				"$IP" "$p" "$u" | base64 -w0 2>/dev/null || true)
			[ -n "$link" ] && echo "  链接     vmess://$link"
		fi
	fi
	if [ -f "$cns_json" ]; then
		echo
		echo "[cns]"
		echo "  地址     $IP"
		echo "  端口     $(cns_port)"
		echo "  密码     $(cns_pw)"
		echo "  头域     $(cns_key)"
	fi
	if [ -f "$amy4_json" ]; then
		echo
		echo "[amy4]"
		echo "  地址     $IP"
		echo "  端口     $(amy4_port)"
		echo "  ClientKey $(amy4_key)"
	fi
}

show_howto() {
	echo
	echo "======== 改端口 / 改密码 ========"
	echo "  改 xray 端口   sh run.sh --xray-port 8443 --keep"
	echo "  改 cns 密码    sh run.sh --cns-password 新密码 --keep"
	echo "  改 amy4 Key    sh run.sh --amy4-key 新Key --keep"
	echo "  一起改         sh run.sh --xray-port 8443 --cns-port 8080 --cns-password xx --keep"
	echo "  --keep 保留没改动的凭据；不加则全部重新生成，客户端要重配。"
}

case "${1:-}" in
	status|--status|show)
		[ -d /usr/local/xray ] || [ -d /usr/local/cns ] || [ -d /usr/local/amy4 ] || die "本机还没装"
		show_status; show_params; show_howto
		exit 0 ;;
	-h|--help)
		sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'
		exit 0 ;;
esac

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

TGZ=""
if [ -f "$CACHE_DIR/kit.tar.gz" ] \
	&& printf '%s  %s\n' "$KIT_SHA" "$CACHE_DIR/kit.tar.gz" | sha256sum -c - >/dev/null 2>&1; then
	echo "==> 使用本地缓存 $CACHE_DIR/kit.tar.gz"
	TGZ="$CACHE_DIR/kit.tar.gz"
else
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
	TGZ="$TMP/kit.tar.gz"
fi

echo "==> 解压并安装"
tar xzf "$TGZ" -C "$TMP"
[ -f "$TMP/selfhost-kit/install.sh" ] || die "包结构异常"

sh "$TMP/selfhost-kit/install.sh" "$@"

if [ "$DRY" = "1" ]; then
	exit 0
fi

if [ "$TGZ" != "$CACHE_DIR/kit.tar.gz" ]; then
	mkdir -p "$CACHE_DIR" 2>/dev/null || true
	cp "$TGZ" "$CACHE_DIR/kit.tar.gz" 2>/dev/null || true
fi

show_status
show_params
show_howto
