#!/bin/sh
# builds.sh —— 交互式安装
#
# 两种用法：
#   1) 在套件目录里跑：     sudo ./builds.sh
#   2) 只有这一个文件时：   curl -kL <地址> -o builds.sh && sudo sh builds.sh
#      这时它会自己下载整包、校验 SHA-256、解压到临时目录，再进入同样的菜单。
#
# 菜单与问答文案沿用上游 builds.sh 原文，二进制全部取自包内 bin/，
# 不执行任何远程脚本。
#
set -eu

KIT_URL_DEFAULT="https://aka.doubaocdn.com/s/NVMTvoVlvm"
KIT_SHA_DEFAULT="1cc5398e973d78180b6b7d91aa5a2ce4252bd4e4a5580df00736b65ddb27f1cc"

KIT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DRY=""
for a in "$@"; do
	[ "$a" = "--dry-run" ] && DRY="--dry-run"
done

if [ -z "$DRY" ] && [ "$(id -u)" != "0" ]; then
	echo "错误: 需要 root 权限，请用 sudo sh $0" >&2
	exit 1
fi

# 当前目录没有套件 → 先试着从自己的 GitHub 克隆，失败再回退到压缩包
if [ ! -f "$KIT/install.sh" ] || [ ! -d "$KIT/bin" ]; then
	GH_REPO="${GH_REPO:-git@github.com:abcc123445653/1.git}"
	GH_HTTPS="https://github.com/abcc123445653/1.git"
	GH_KEY="${GH_KEY:-$HOME/.ssh/github_1}"
	PKG=$(mktemp -d)

	if command -v git >/dev/null 2>&1; then
		: > "$PKG/err"
		if [ -n "${GH_TOKEN:-}" ]; then
			echo "==> 用 GH_TOKEN 从 GitHub 克隆"
			git clone --depth 1 "https://x-access-token:${GH_TOKEN}@github.com/abcc123445653/1.git" "$PKG/repo" >/dev/null 2>>"$PKG/err" || true
		elif [ -f "$GH_KEY" ]; then
			echo "==> 从 GitHub 克隆 $GH_REPO"
			GIT_SSH_COMMAND="ssh -i $GH_KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new" \
				git clone --depth 1 "$GH_REPO" "$PKG/repo" >/dev/null 2>>"$PKG/err" || true
		else
			echo "==> 尝试用已有凭据克隆 $GH_HTTPS"
			git clone --depth 1 "$GH_HTTPS" "$PKG/repo" >/dev/null 2>>"$PKG/err" || true
		fi
		if [ -f "$PKG/repo/selfhost-kit/builds.sh" ]; then
			echo "==> 使用仓库内套件（bin/ 由 MANIFEST 校验）"
			RC=0
			sh "$PKG/repo/selfhost-kit/builds.sh" "$@" || RC=$?
			rm -rf "$PKG"
			exit "$RC"
		fi
		echo "!! 克隆失败（$([ -s "$PKG/err" ] && head -1 "$PKG/err" || echo 未知原因)），回退到压缩包来源"
		rm -rf "$PKG/repo"
	fi

	KIT_URL="${KIT_URL:-$KIT_URL_DEFAULT}"
	KIT_SHA="${KIT_SHA:-$KIT_SHA_DEFAULT}"
	if [ -z "$KIT_URL" ] || [ -z "$KIT_SHA" ]; then
		rm -rf "$PKG"
		echo "错误: 当前目录缺少 install.sh 和 bin/，本文件也没有内置下载地址。" >&2
		echo "请把整包放在同目录，或设置 GH_KEY / KIT_URL / KIT_SHA。" >&2
		exit 1
	fi
	command -v tar >/dev/null 2>&1 || { rm -rf "$PKG"; echo "错误: 缺少 tar" >&2; exit 1; }
	command -v sha256sum >/dev/null 2>&1 || { rm -rf "$PKG"; echo "错误: 缺少 sha256sum" >&2; exit 1; }

	echo "==> 下载套件（约 19 MB）"
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL --proto '=https' --tlsv1.2 "$KIT_URL" -o "$PKG/kit.tar.gz" \
			|| { rm -rf "$PKG"; echo "错误: 下载失败 $KIT_URL" >&2; exit 1; }
	elif command -v wget >/dev/null 2>&1; then
		wget -q --https-only "$KIT_URL" -O "$PKG/kit.tar.gz" \
			|| { rm -rf "$PKG"; echo "错误: 下载失败 $KIT_URL" >&2; exit 1; }
	else
		rm -rf "$PKG"; echo "错误: 缺少 curl / wget" >&2; exit 1
	fi

	echo "==> 校验 SHA-256"
	printf '%s  %s\n' "$KIT_SHA" "$PKG/kit.tar.gz" | sha256sum -c - >/dev/null 2>&1 \
		|| { rm -rf "$PKG"; echo "错误: 校验失败，包不完整或被替换" >&2; exit 1; }

	echo "==> 解压并进入菜单"
	tar xzf "$PKG/kit.tar.gz" -C "$PKG" || { rm -rf "$PKG"; echo "错误: 解压失败" >&2; exit 1; }
	RC=0
	sh "$PKG/selfhost-kit/builds.sh" "$@" || RC=$?
	rm -rf "$PKG"
	exit "$RC"
fi

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
			6) printf '请输入vless websocket tls服务端口: '; ask ''; P="$REPLY"
			   printf "请输入vless websocket tls路径(默认: '/'): "; ask ''; [ -n "$REPLY" ] && xray_ws_path="$REPLY" ;;
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

	[ -n "$COMPS" ] || { echo "没有选中任何可安装的组件"; return 1; }

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
if [ "$task_type" = "install" ]; then
	try=0
	while :; do
		try=$((try + 1))
		server_install_set
		if run_tasks; then
			break
		fi
		if [ "$try" -ge 3 ]; then
			echo "已连续 $try 次没有选中可安装的组件，退出"
			exit 1
		fi
		printf '\n提示: 1 是 tinyproxy，本套件装不了；要装 xray/cns/amy4 请选 2 3 4\n'
		printf '请重新选择项目(多个用空格隔开，默认 2 3 4): '
		ask ''
		[ -n "$REPLY" ] || REPLY="2 3 4"
		build_projects="$REPLY"
	done
else
	server_uninstall_set
	run_tasks
fi
