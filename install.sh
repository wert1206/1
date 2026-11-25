#!/bin/sh
# xray-deploy / install.sh
#
# 从 XTLS/Xray-core 官方 GitHub Release 安装，使用固定的 SHA-256 校验。
# 不做 curl|sh，不使用 -k / --insecure，校验不通过即中止。
#
# 用法：
#   sudo ./install.sh [--port 8443] [--host 你的域名或IP] [--open-port]
#                     [--tls-cert /path/fullchain.pem --tls-key /path/privkey.pem]
#
set -eu

VERSION="v26.11.9"
X86_SHA256="b651f7e1d9966ee2c1b1ee1bf8b52c72771824d3065dce96bbc8bcc19ed95f82"
INSTALL_DIR="/usr/local/xray"
SERVICE_FILE="/etc/systemd/system/xray.service"
PORT="8443"
OPEN_PORT=0
TLS_CERT=""
TLS_KEY=""
CLIENT_HOST=""

usage() {
	cat <<'EOF'
用法: sudo ./install.sh [选项]

  --port <端口>         监听端口，默认 8443
  --host <地址>         生成客户端链接时使用的主机名/IP，默认自动探测
  --open-port           自动放行防火墙端口（ufw / firewalld）
  --tls-cert <路径>     启用 TLS，指定证书链文件
  --tls-key  <路径>     启用 TLS，指定私钥文件
  -h, --help            显示本帮助

卸载: sudo ./uninstall.sh
EOF
}

die() { echo "错误: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
	case "$1" in
		--port)      PORT="$2"; shift 2 ;;
		--host)      CLIENT_HOST="$2"; shift 2 ;;
		--open-port) OPEN_PORT=1; shift ;;
		--tls-cert)  TLS_CERT="$2"; shift 2 ;;
		--tls-key)   TLS_KEY="$2"; shift 2 ;;
		-h|--help)   usage; exit 0 ;;
		*)           echo "未知参数: $1" >&2; usage >&2; exit 2 ;;
	esac
done

# ---------- 前置检查 ----------
[ "$(id -u)" = "0" ] || die "需要 root 权限运行"
case "$PORT" in ''|*[!0-9]*) die "端口必须是数字" ;; esac
[ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ] || die "端口超出范围"

for c in curl unzip sha256sum systemctl; do
	command -v "$c" >/dev/null 2>&1 || die "缺少命令: $c"
done

if [ -n "$TLS_CERT" ] || [ -n "$TLS_KEY" ]; then
	[ -n "$TLS_CERT" ] && [ -n "$TLS_KEY" ] || die "--tls-cert 与 --tls-key 必须同时提供"
	[ -r "$TLS_CERT" ] || die "证书不可读: $TLS_CERT"
	[ -r "$TLS_KEY" ]  || die "私钥不可读: $TLS_KEY"
fi

# ---------- 选择资源 ----------
case "$(uname -m)" in
	x86_64|amd64)  ASSET="Xray-linux-64.zip"        PINNED="$X86_SHA256" ;;
	aarch64|arm64) ASSET="Xray-linux-arm64-v8a.zip" PINNED="" ;;
	*) die "不支持的架构: $(uname -m)（仅支持 x86_64 / arm64）" ;;
esac

BASE="https://github.com/XTLS/Xray-core/releases/download/${VERSION}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT INT TERM

echo "==> 下载 $VERSION / $ASSET"
curl --proto '=https' --tlsv1.2 -fsSL -o "$TMP/$ASSET" "$BASE/$ASSET" \
	|| die "下载失败"
curl --proto '=https' --tlsv1.2 -fsSL -o "$TMP/pkg.dgst" "$BASE/$ASSET.dgst" \
	|| die "下载校验文件失败"

# ---------- 校验 ----------
ACTUAL="$(sha256sum "$TMP/$ASSET" | awk '{print $1}')"
DGST="$(awk -F'= ' '/^SHA2-256/{print $2}' "$TMP/pkg.dgst" | tr -d ' \r')"

if [ -n "$PINNED" ]; then
	[ "$ACTUAL" = "$PINNED" ] || die "SHA-256 与仓库固定值不符，已中止
  期望: $PINNED
  实际: $ACTUAL"
	[ "$ACTUAL" = "$DGST" ] || die "SHA-256 与官方 .dgst 不符，已中止"
	echo "==> 校验通过（固定值 + 官方 .dgst 双重比对）"
else
	[ -n "$DGST" ] || die ".dgst 中未找到 SHA2-256"
	[ "$ACTUAL" = "$DGST" ] || die "SHA-256 与官方 .dgst 不符，已中止"
	echo "==> 校验通过（官方 .dgst 比对；本架构无仓库固定值）"
fi

# ---------- 安装 ----------
mkdir -p "$TMP/unpack" "$INSTALL_DIR"
unzip -o -q "$TMP/$ASSET" -d "$TMP/unpack" || die "解压失败"
cp "$TMP/unpack/xray" "$INSTALL_DIR/xray" || die "写入二进制失败"
chmod 0755 "$INSTALL_DIR/xray"
for f in geoip.dat geosite.dat; do
	[ -f "$TMP/unpack/$f" ] && cp "$TMP/unpack/$f" "$INSTALL_DIR/$f"
done
echo "==> 已安装 $("$INSTALL_DIR/xray" version 2>/dev/null | head -n1)"

# ---------- 生成配置 ----------
UUID="$("$INSTALL_DIR/xray" uuid)" || die "生成 UUID 失败"
[ -n "$UUID" ] || die "生成 UUID 失败"

if [ -n "$TLS_CERT" ]; then
	SECURITY="tls"
	STREAM="\"network\": \"tcp\",
			\"security\": \"tls\",
			\"tlsSettings\": {
				\"certificates\": [{
					\"certificateFile\": \"$TLS_CERT\",
					\"keyFile\": \"$TLS_KEY\"
				}]
			}"
else
	SECURITY="none"
	STREAM="\"network\": \"tcp\""
fi

cat > "$INSTALL_DIR/config.json" <<EOF
{
	"log": { "loglevel": "warning" },
	"inbounds": [{
		"port": $PORT,
		"listen": "0.0.0.0",
		"protocol": "vless",
		"settings": {
			"clients": [{ "id": "$UUID" }],
			"decryption": "none"
		},
		"streamSettings": { $STREAM }
	}],
	"outbounds": [{ "protocol": "freedom", "tag": "direct" }]
}
EOF
chmod 0644 "$INSTALL_DIR/config.json"

"$INSTALL_DIR/xray" run -test -c "$INSTALL_DIR/config.json" >/dev/null 2>&1 \
	|| die "配置自检未通过，请查看 $INSTALL_DIR/config.json"

# ---------- systemd ----------
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Xray Service
Documentation=https://github.com/XTLS/Xray-core
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
DynamicUser=yes
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
RestrictSUIDSGID=yes
ExecStart=$INSTALL_DIR/xray run -c $INSTALL_DIR/config.json
Restart=on-failure
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now xray >/dev/null 2>&1 || die "启动 systemd 服务失败"
sleep 1
systemctl is-active xray >/dev/null 2>&1 || die "服务未处于 active 状态，请执行: journalctl -u xray -n 50"

# ---------- 防火墙 ----------
if [ "$OPEN_PORT" = "1" ]; then
	if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi active; then
		ufw allow "$PORT"/tcp >/dev/null && echo "==> ufw 已放行 $PORT/tcp"
	elif command -v firewall-cmd >/dev/null 2>&1; then
		firewall-cmd --add-port="$PORT"/tcp --permanent >/dev/null \
			&& firewall-cmd --reload >/dev/null \
			&& echo "==> firewalld 已放行 $PORT/tcp"
	else
		echo "!! 未检测到已启用的 ufw / firewalld，请自行放行 $PORT/tcp"
	fi
else
	echo "==> 未改动防火墙（需要时加 --open-port，或手动放行 $PORT/tcp）"
fi

# ---------- 输出客户端链接 ----------
[ -n "$CLIENT_HOST" ] || CLIENT_HOST="$(hostname -I 2>/dev/null | awk '{print $1}')"
[ -n "$CLIENT_HOST" ] || CLIENT_HOST="<你的服务器IP>"

echo
echo "安装完成"
echo "  配置: $INSTALL_DIR/config.json"
echo "  服务: systemctl status xray | journalctl -u xray -f"
echo "  UUID: $UUID"
echo
echo "客户端链接（VLESS / TCP / security=$SECURITY）："
echo "  vless://$UUID@$CLIENT_HOST:$PORT?encryption=none&security=$SECURITY&type=tcp#xray-deploy"
echo
if [ "$SECURITY" = "none" ]; then
	echo "注意: 当前未启用 TLS，VLESS 本身不提供传输加密。"
	echo "      公网使用请配置证书后重跑 --tls-cert/--tls-key，或仅在可信链路内使用。"
	echo
fi
echo "卸载: sudo ./uninstall.sh"
