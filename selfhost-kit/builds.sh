#!/bin/sh
# builds.sh —— 交互式安装（离线版）
#
# 菜单与问答文案沿用上游 builds.sh 原文，底层全部取自本目录 bin/，
# 不联网、不下载二级脚本。
#
# 用法：sudo ./builds.sh [--dry-run]
#
set -eu

KIT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DRY=""
for a in "$@"; do
	[ "$a" = "--dry-run" ] && DRY="--dry-run"
done

[ -f "$KIT/install.sh" ] || { echo "错误: 找不到 $KIT/install.sh" >&2; exit 1; }

task_type=""
build_projects=""
daemon_run=""

xray_dir="" xray_options="" xray_port="" xray_ws_path="/"
cns_port="" cns_pw="" cns_udp="" cns_key="" cns_tls="" cns_dir=""
amy4_port="" amy4_key="" amy4_ipv6="" amy4_dir=""
tpr_port="" tpr_key="" tpr_dir=""

ask() { printf '%s' "$1"; IFS= read -r REPLY || REPLY=""; }

option() {
	printf '1. 安装项目\n2. 卸载项目\n请输入选项(默认为1): '
	ask ''
	echo "$REPLY" | grep -q '2' && task_type="uninstall" || task_type="install"
	printf '可选项目:\n\t1. tinyproxy\n\t2. cns\n\t3. xray\n\t4. amy4(服务端)\n\t请选择项目(多个用空格隔开): '
	ask ''
	build_projects="$REPLY"
	printf '后台运行吗?(输出保存在builds.out文件)[n]: '
	ask ''
	daemon_run="$REPLY"
}

tinyproxy_set() {
	printf '请输入tinyproxy端口: '; ask ''; tpr_port="$REPLY"
	printf "请输入tinyproxy代理头域(默认为 'Meng'): "; ask ''; tpr_key="$REPLY"
	printf '请输入tinyproxy安装目录(默认/usr/local/tinyproxy): '; ask ''; tpr_dir="$REPLY"
	printf '安装UPX压缩版本?[n]: '; ask ''; tpr_upx="$REPLY"
}

cns_set() {
	printf '请输入cns服务端口(如果不用请留空): '; ask ''; cns_port="$REPLY"
	printf '请输入cns加密密码(默认不加密): '; ask ''; cns_pw="$REPLY"
	printf "请输入cns的udp标识(默认: 'httpUDP'): "; ask ''; cns_udp="$REPLY"
	printf "请输入cns代理头域(默认: 'Meng'): "; ask ''; cns_key="$REPLY"
	printf '请输入tls服务端口(如果不用请留空): '; ask ''; cns_tls="$REPLY"
	printf '请输入cns安装目录(默认/usr/local/cns): '; ask ''; cns_dir="$REPLY"
	printf '安装UPX压缩版本?[n]: '; ask ''; cns_upx="$REPLY"
}

xray_set() {
	printf '请输入xray安装目录(默认: /usr/local/xray): '; ask ''; xray_dir="$REPLY"
	printf '选项(TLS默认为自签名证书, 如有需要请自行更改):\n'
	printf '\t1. tcp http                   (vmess)\n'
	printf '\t2. tcp tls                    (vmess)\n'
	printf '\t3. tcp reality                (vless)\n'
	printf '\t4. websocket                  (vmess)\n'
	printf '\t5. websocket tls              (vmess)\n'
	printf '\t6. websocket tls              (vless)\n'
	printf '\t7. mkcp                       (vmess)\n'
	printf '\t8. mkcp tls                   (vmess)\n'
	printf '\t9. mkcp tls                   (vless)\n'
	printf '\t10. trojan tls\n'
	printf '请输入你的选项(多个选项用空格分隔): '
	ask ''
	xray_options="$REPLY"
	XMODE=""
	XPORT=""
	for opt in $xray_options; do
		m=$(mode_of "$opt")
		P=""
		case $opt in
			1) printf '请输入vmess tcp http服务端口: '; ask ''; P="$REPLY" ;;
			2) printf '请输入vmess tcp tls服务端口: '; ask ''; P="$REPLY" ;;
			3) printf '请输入vless tcp reality服务端口: '; ask ''; P="$REPLY" ;;
			4) printf '请输入vmess websocket服务端口: '; ask ''; P="$REPLY"
			   printf "请输入vmess websocket路径(默认: '/'): "; ask ''; [ -n "$REPLY" ] && xray_ws_path="$REPLY" ;;
			5) printf '请输入vmess websocket tls服务端口: '; ask ''; P="$REPLY"
			   printf "请输入vmess websocket tls路径(默认: '/'): "; ask ''; [ -n "$REPLY" ] && xray_ws_path="$REPLY" ;;
			6) printf '请输入vless websocket tls服务端口: '; ask ''; P="$REPLY" ;;
			7) printf '请输入vmess mKCP服务端口: '; ask ''; P="$REPLY" ;;
			8) printf '请输入vmess mKCP tls服务端口: '; ask ''; P="$REPLY" ;;
			9) printf '请输入vless mKCP tls服务端口: '; ask ''; P="$REPLY" ;;
			10) printf '请输入trojan tls服务端口: '; ask ''; P="$REPLY" ;;
		esac
		if [ -n "$m" ] && [ -z "$XMODE" ]; then
			XMODE="$m"
			[ -n "$P" ] && XPORT="$P"
		fi
		REPLY=""
	done
	printf '安装UPX压缩版本?[n]: '; ask ''; xray_upx="$REPLY"
}

amy4_set() {
	printf '请输入amy4服务端口: '; ask ''; amy4_port="$REPLY"
	printf '请输入amy4连接密码(ClientKey): '; ask ''; amy4_key="$REPLY"
	printf '服务器是否支持IPV6[n]: '; ask ''; amy4_ipv6="$REPLY"
	printf '请输入安装目录(默认/usr/local/amy4): '; ask ''; amy4_dir="$REPLY"
	printf '安装UPX压缩版本?[n]: '; ask ''; amy4_upx="$REPLY"
}

# 把上游的入站编号映射成本套件支持的模式；不支持返回空
mode_of() {
	case "$1" in
		1) echo "tcp-http" ;;
		2) echo "tcp-tls" ;;
		4) echo "ws" ;;
		5) echo "ws-tls" ;;
		*) echo "" ;;
	esac
}

server_install_set() {
	XMODE=""
	for opt in $build_projects; do
		case $opt in
			1) tinyproxy_set ;;
			2) cns_set ;;
			3) xray_set ;;
			4) amy4_set ;;
			*) echo "选项($opt)不正确，请输入正确的选项！" >&2 ;;
		esac
	done
}

server_uninstall_set() {
	for opt in $build_projects; do
		case $opt in
			1) printf '请输入tinyproxy安装目录(默认/usr/local/tinyproxy): '; ask ''; tpr_dir="$REPLY" ;;
			2) printf '请输入cns安装目录(默认/usr/local/cns): '; ask ''; cns_dir="$REPLY" ;;
			3) printf '请输入xray安装目录(默认/usr/local/xray): '; ask ''; xray_dir="$REPLY" ;;
			4) printf '请输入amy4安装目录(默认/usr/local/amy4): '; ask ''; amy4_dir="$REPLY" ;;
		esac
	done
}

note_default_dir() {
	[ -n "$1" ] && [ "$1" != "/usr/local/$2" ] && echo "   → 本套件安装目录固定 /usr/local/$2，已忽略输入值"
	return 0
}

run_tasks() {
	COMPS=""
	ARGS=""

	for opt in $build_projects; do
		case $opt in
			1) COMPS="$COMPS tinyproxy" ;;
			2) COMPS="$COMPS cns"
			   [ -n "$cns_port" ] && ARGS="$ARGS --cns-port $cns_port"
			   [ -n "$cns_pw" ]   && ARGS="$ARGS --cns-password $cns_pw"
			   [ -n "$cns_key" ]  && ARGS="$ARGS --cns-key $cns_key"
			   note_default_dir "$cns_dir" cns
			   [ -n "$cns_udp" ] && [ "$cns_udp" != "httpUDP" ] && echo "   → udp 标识固定 httpUDP，已忽略输入值"
			   [ -n "$cns_tls" ] && echo "   → cns tls 端口暂不支持，已跳过"
			   ;;
			3) COMPS="$COMPS xray"
			   SUP=0
			   for o in $xray_options; do
					if [ -n "$(mode_of "$o")" ]; then
						SUP=$((SUP + 1))
					else
						echo "   → 选项 $o 暂不支持，已跳过"
					fi
			   done
			   [ -z "$XMODE" ] && XMODE="tcp-http"
			   [ -z "$XPORT" ] && XPORT="443"
			   [ "$SUP" -gt 1 ] && echo "   → 本套件每次只生成一个入站，采用第一个受支持的选项（$XMODE）"
			   ARGS="$ARGS --xray-port $XPORT --xray-mode $XMODE --xray-ws-path $xray_ws_path"
			   note_default_dir "$xray_dir" xray
			   ;;
			4) COMPS="$COMPS amy4"
			   [ -n "$amy4_port" ] && ARGS="$ARGS --amy4-port $amy4_port"
			   [ -n "$amy4_key" ]  && ARGS="$ARGS --amy4-key $amy4_key"
			   note_default_dir "$amy4_dir" amy4
			   ;;
		esac
	done

	COMPS=$(echo "$COMPS" | tr ' ' ',' | sed 's/^,//; s/,$//')

	if [ "$task_type" = "uninstall" ]; then
		[ -n "$COMPS" ] || { echo "没有选中任何组件"; return 0; }
		exec sh "$KIT/uninstall.sh" --components "$COMPS"
	fi

	# tinyproxy 单独处理：源已损坏
	case ",$COMPS," in
		*,tinyproxy,*)
			COMPS=$(echo "$COMPS" | sed 's/tinyproxy,//; s/,tinyproxy//; s/^tinyproxy$//')
			echo
			echo "tinyproxy任务失败：上游下载源 binary.quicknet.cyou 返回的是 70 字节跳转页，不是程序"
			echo "如需 HTTP 代理，请用系统包：apt install tinyproxy"
			;;
	esac

	[ -n "$COMPS" ] || { echo "没有选中任何可安装的组件"; return 0; }

	echo
	echo "==> 组件: $COMPS   任务: $task_type"

	if echo "$daemon_run" | grep -qi 'y'; then
		( sh "$KIT/install.sh" --components "$COMPS" $ARGS $DRY > builds.out 2>&1 ) &
		echo "正在后台运行中......"
		return 0
	fi

	sh "$KIT/install.sh" --components "$COMPS" $ARGS $DRY
}

option
[ "$task_type" = "install" ] && server_install_set || server_uninstall_set
run_tasks
