#!/bin/sh
# selfhost-kit / install.sh
#
# 完全离线安装：不联网、不下载、不执行任何远程脚本。
# 只安装本仓库 bin/ 下经过 SHA-256 校验的二进制。
#
# 用法：
#   sudo ./install.sh [--xray-port 443] [--cns-port 80] [--amy4-port 18443]
#                     [--components xray,cns,amy4] [--dry-run]
#
set -eu

KIT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
XRAY_PORT=443
CNS_PORT=80
AMY4_PORT=18443
CNS_KEY="Meng"
COMPONENTS="xray,cns,amy4"
DRY_RUN=0

die() { echo "错误: $*" >&2; exit 1; }

usage() {
	cat <<'EOF'
用法: sudo ./install.sh [选项]

  --xray-port <端口>   Xray 监听端口，默认 443
  --cns-port <端口>    cns 监听端口，默认 80
  --amy4-port <端口>   amy4 监听端口，默认 18443
  --cns-key <标识>     cns 代理头域，默认 Meng
  --components <列表>  只装其中几个，逗号分隔，默认 xray,cns,amy4
  --dry-run            只做校验与生成配置，不写入系统、不启动服务
  -h, --help           显示本帮助

卸载: sudo ./uninstall.sh
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
		--xray-port)  XRAY_PORT="$2"; shift 2 ;;
		--cns-port)   CNS_PORT="$2"; shift 2 ;;
		--amy4-port)  AMY4_PORT="$2"; shift 2 ;;
		--cns-key)    CNS_KEY="$2"; shift 2 ;;
		--components) COMPONENTS="$2"; shift 2 ;;
		--dry-run)    DRY_RUN=1; shift ;;
		-h|--help)    usage; exit 0 ;;
		*)            echo "未知参数: $1" >&2; usage >&2; exit 2 ;;
	esac
done

for p in "$XRAY_PORT" "$CNS_PORT" "$AMY4_PORT"; do
	case "$p" in ''|*[!0-9]*) die "端口必须是数字: $p" ;; esac
done

has() { echo ",$COMPONENTS," | grep -q ",$1,"; }

if [ "$DRY_RUN" = "0" ]; then
	[ "$(id -u)" = "0" ] || die "需要 root 权限运行（或加 --dry-run 先做校验）"
fi

[ "$(uname -m)" = "x86_64" ] || die "本套件只含 x86_64 二进制，当前架构: $(uname -m)"

echo "==> 校验 bin/ 完整性"
(cd "$KIT_DIR" && sha256sum -c MANIFEST.sha256) || die "二进制校验失败，已中止（文件被改动或不完整）"

rand_hex() { head -c "$1" /dev/urandom | od -An -tx1 | tr -d ' \n'; }

if [ "$DRY_RUN" = "1" ]; then
	ROOT_DIR=$(mktemp -d)
	echo "==> 干跑模式，写入 $ROOT_DIR"
else
	ROOT_DIR=""
fi

target_dir() {
	if [ "$DRY_RUN" = "1" ]; then echo "$ROOT_DIR/usr/local/$1"; else echo "/usr/local/$1"; fi
}

write_unit() {
	if [ "$DRY_RUN" = "1" ]; then return 0; fi
	cat > "/etc/systemd/system/$1.service"
}

# ---------------- xray ----------------
if has xray; then
	D=$(target_dir xray)
	mkdir -p "$D"
	cp "$KIT_DIR/bin/xray" "$D/xray"
	chmod 755 "$D/xray"
	UUID=$("$D/xray" uuid)
	cat > "$D/xray.json" <<EOF
{
	"log": { "loglevel": "warning" },
	"inbounds": [{
		"port": $XRAY_PORT,
		"protocol": "vmess",
		"settings": {
			"udp": true,
			"clients": [{ "id": "$UUID", "level": 0, "alterId": 0 }],
			"decryption": "none"
		},
		"streamSettings": {
			"sockopt": { "tcpFastOpen": true },
			"network": "tcp",
			"tcpSettings": { "header": { "type": "http" } }
		}
	}],
	"outbounds": [{ "protocol": "freedom", "tag": "direct" }]
}
EOF
	"$D/xray" run -test -c "$D/xray.json" >/dev/null 2>&1 \
		|| die "xray 配置自检未通过"

	if [ "$DRY_RUN" = "0" ]; then
		systemctl stop xray >/dev/null 2>&1 || true
		write_unit xray <<EOF
[Unit]
Description=Xray Service
After=network-online.target

[Service]
Type=simple
WorkingDirectory=/usr/local/xray
ExecStart=/usr/local/xray/xray run -c /usr/local/xray/xray.json
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
	fi
	echo "==> xray 就绪 (端口 $XRAY_PORT, UUID $UUID)"
fi

# ---------------- cns ----------------
if has cns; then
	D=$(target_dir cns)
	mkdir -p "$D"
	cp "$KIT_DIR/bin/cns" "$D/cns"
	chmod 755 "$D/cns"
	CNS_PW=$(rand_hex 8)
	cat > "$D/cns.json" <<EOF
{
	"Listen_addr": [":$CNS_PORT"],
	"Proxy_key": "$CNS_KEY",
	"Encrypt_password": "$CNS_PW",
	"Udp_flag": "httpUDP",
	"Enable_dns_tcpOverUdp": true,
	"Enable_httpDNS": true,
	"Enable_TFO": false,
	"Udp_timeout": 60,
	"Tcp_timeout": 600,
	"Pid_path": "$D/run.pid"
}
EOF
	if [ "$DRY_RUN" = "0" ]; then
		systemctl stop cns >/dev/null 2>&1 || true
		write_unit cns <<EOF
[Unit]
Description=CNS Tunnel Service
After=network-online.target

[Service]
Type=simple
WorkingDirectory=/usr/local/cns
ExecStart=/usr/local/cns/cns -json=cns.json
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
	fi
	echo "==> cns 就绪 (端口 $CNS_PORT, 密码 $CNS_PW, 头域 $CNS_KEY)"
fi

# ---------------- amy4 ----------------
if has amy4; then
	D=$(target_dir amy4)
	mkdir -p "$D"
	cp "$KIT_DIR/bin/amy4" "$D/amy4"
	chmod 755 "$D/amy4"
	AMY_KEY=$(rand_hex 6)
	cat > "$D/amy4.json" <<EOF
{
	"PidFile": "$D/run.pid",
	"Log": { "Level": "warning" },
	"AmyIns": [{
		"ProxyType": "ANet",
		"ANetSettings": {
			"ListenAddr": ":$AMY4_PORT",
			"ClientKeys": ["$AMY_KEY"],
			"IPv6Support": false
		}
	}],
	"AmyOuts": [{ "ProxyType": "Origin", "Tag": "Origin" }],
	"Routers": []
}
EOF
	if [ "$DRY_RUN" = "0" ]; then
		systemctl stop amy4 >/dev/null 2>&1 || true
		write_unit amy4 <<EOF
[Unit]
Description=Amy4 ANet Service
After=network-online.target

[Service]
Type=simple
WorkingDirectory=/usr/local/amy4
ExecStart=/usr/local/amy4/amy4 -config=amy4.json
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
	fi
	echo "==> amy4 就绪 (端口 $AMY4_PORT, ClientKey $AMY_KEY)"
fi

# ---------------- 启动 ----------------
if [ "$DRY_RUN" = "0" ]; then
	systemctl daemon-reload
	for s in xray cns amy4; do
		has "$s" || continue
		systemctl enable --now "$s" >/dev/null 2>&1 || die "$s 启动失败"
	done
	sleep 1
	for s in xray cns amy4; do
		has "$s" || continue
		if systemctl is-active "$s" >/dev/null 2>&1; then
			echo "==> $s 运行中"
		else
			echo "!! $s 未运行，查看: journalctl -u $s -n 30"
		fi
	done
	echo
	echo "已安装完成。端口冲突检查: ss -lntp | grep -E ':$XRAY_PORT|:$CNS_PORT|:$AMY4_PORT'"
else
	echo
	echo "干跑完成，配置位于 $ROOT_DIR"
fi
