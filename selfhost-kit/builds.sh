#!/bin/sh
# builds.sh —— 交互式安装界面（离线版）
#
# 保留上游 builds.sh 的菜单与问答习惯，但所有文件都取自本目录 bin/，
# 全程不联网、不下载二级脚本。底层调用 selfhost-kit/install.sh。
#
# 用法：
#   sudo ./builds.sh            # 交互
#   sudo ./builds.sh --dry-run  # 只生成配置，不写系统
#
set -eu

KIT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DRY=""
for a in "$@"; do
	[ "$a" = "--dry-run" ] && DRY="--dry-run"
done

prompt() { printf '%s' "$1"; IFS= read -r REPLY || REPLY=""; }

die() { echo "错误: $*" >&2; exit 1; }

[ -f "$KIT/install.sh" ] || die "找不到 $KIT/install.sh，请在套件目录内运行"

cat <<'EOF'
1. 安装项目
2. 卸载项目
EOF
prompt "请输入选项(默认为1): "
case "$REPLY" in
	2) TASK="uninstall" ;;
	*) TASK="install" ;;
esac

cat <<'EOF'

可选项目:
	1. tinyproxy（上游下载源已损坏，本套件不可用）
	2. cns
	3. xray
	4. amy4
EOF
prompt "请选择项目(多个用空格隔开): "
[ -z "$REPLY" ] && REPLY="2 3 4"
PROJECTS="$REPLY"

COMPS=""
XPORT="443"
XMODE="tcp-http"
CPORT="80"
CKEY="Meng"
CPASS=""
APORT="18443"
AKEY=""

for p in $PROJECTS; do
	case "$p" in
	1)
		echo
		echo "!! tinyproxy 跳过：binary.quicknet.cyou 当前返回的是 70 字节跳转页，不是程序。"
		echo "!! 需要 HTTP 代理请用系统包：apt install tinyproxy"
		;;
	2)
		echo
		[ "$TASK" = "install" ] && {
			prompt "请输入cns服务端口(默认 80): "
			[ -n "$REPLY" ] && CPORT="$REPLY"
			prompt "请输入cns加密密码(留空则随机生成): "
			CPASS="$REPLY"
			prompt "请输入cns代理头域(默认 Meng): "
			[ -n "$REPLY" ] && CKEY="$REPLY"
			echo "   （udp标识固定 httpUDP，tls 端口未启用，安装目录固定 /usr/local/cns）"
		}
		COMPS="$COMPS cns"
		;;
	3)
		echo
		if [ "$TASK" = "install" ]; then
			cat <<'EOF'
	入站类型（本套件支持 1 / 2 / 4 / 5，其余标注不支持）:
	1. tcp http   (vmess)
	2. tcp tls    (vmess, 自签证书)
	3. tcp reality(vless)      —— 暂不支持
	4. websocket  (vmess)
	5. websocket tls (vmess)   —— 支持
	6. websocket tls (vless)   —— 暂不支持
	7. mkcp / 8. mkcp tls / 9. mkcp tls(vless) / 10. trojan tls —— 暂不支持
EOF
			prompt "请输入你的选项: "
			case "$REPLY" in
				1) XMODE="tcp-http" ;;
				2) XMODE="tcp-tls" ;;
				4) XMODE="ws" ;;
				5) XMODE="ws-tls" ;;
				"") XMODE="tcp-http" ;;
				*) echo "   !! 选项 $REPLY 暂不支持，改用 1（tcp http）"; XMODE="tcp-http" ;;
			esac
			prompt "请输入xray服务端口(默认 443): "
			[ -n "$REPLY" ] && XPORT="$REPLY"
			echo "   （安装目录固定 /usr/local/xray）"
		fi
		COMPS="$COMPS xray"
		;;
	4)
		echo
		[ "$TASK" = "install" ] && {
			prompt "请输入amy4端口(默认 18443): "
			[ -n "$REPLY" ] && APORT="$REPLY"
			prompt "请输入amy4连接密码(ClientKey，留空则随机生成): "
			AKEY="$REPLY"
			echo "   （原机配的 443 会被 xray 占用，故默认改到 18443；安装目录固定 /usr/local/amy4）"
		}
		COMPS="$COMPS amy4"
		;;
	*)
		echo "!! 未知选项 $p，跳过"
		;;
	esac
done

COMPS=$(echo "$COMPS" | tr ' ' ',')
COMPS=$(echo "$COMPS" | sed 's/^,//; s/,$//')
[ -n "$COMPS" ] || die "没有选中任何可安装的组件"

echo
echo "==> 组件: $COMPS   任务: $TASK"

if [ "$TASK" = "uninstall" ]; then
	exec sh "$KIT/uninstall.sh" --components "$COMPS"
fi

set -- --components "$COMPS" \
	--xray-port "$XPORT" --xray-mode "$XMODE" \
	--cns-port "$CPORT" --cns-key "$CKEY" \
	--amy4-port "$APORT"

[ -n "$CPASS" ] && set -- "$@" --cns-password "$CPASS"
[ -n "$AKEY" ]  && set -- "$@" --amy4-key "$AKEY"

exec sh "$KIT/install.sh" "$@" $DRY
