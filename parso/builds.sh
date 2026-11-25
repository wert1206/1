#!/bin/sh
BASE="${BASE:-https://api.github.com/repos/abcc123445653/1/contents/parso}"

option() {
	echo -n $echo_opt_e "1. 安装项目\n2. 卸载项目\n请输入选项(默认为1): "
	read install_opt
	echo "$install_opt"|grep -q '2' && task_type='uninstall' || task_type='install'
	echo -n $echo_opt_e "可选项目:
	\r1. tinyproxy
	\r2. cns
	\r3. xray
	\r4. amy4(服务端)
	\r请选择项目(多个用空格隔开): "
	read build_projects
	echo -n '后台运行吗?(输出保存在builds.out文件)[n]: '
	read daemon_run
}

tinyproxy_set() {
	echo -n '请输入tinyproxy端口: '
	read tinyproxy_port
	echo -n "请输入tinyproxy代理头域(默认为 'Meng'): "
	read tinyproxy_proxy_key
	echo -n '请输入tinyproxy安装目录(默认/usr/local/tinyproxy): '
	read tinyproxy_install_dir
	echo -n "安装UPX压缩版本?[n]: "
	read tinyproxy_UPX
	echo "tinyproxy_UPX"|grep -qi '^y' && tinyproxy_UPX="upx" || tinyproxy_UPX=""
	[ -z "$tinyproxy_install_dir" ] && tinyproxy_install_dir='/usr/local/tinyproxy'
	export tinyproxy_port tinyproxy_proxy_key tinyproxy_install_dir tinyproxy_UPX
}

cns_set() {
	echo -n '请输入cns服务端口(如果不用请留空): '
	read cns_port
	echo -n '请输入cns加密密码(默认不加密): '
	read cns_encrypt_password
	echo -n "请输入cns的udp标识(默认: 'httpUDP'): "
	read cns_udp_flag
	echo -n "请输入cns代理头域(默认: 'Meng'): "
	read cns_proxy_key
	echo -n '请输入tls服务端口(如果不用请留空): '
	read cns_tls_port
	echo -n '请输入cns安装目录(默认/usr/local/cns): '
	read cns_install_dir
	echo -n "安装UPX压缩版本?[n]: "
	read cns_UPX
	echo "$cns_UPX"|grep -qi '^y' && cns_UPX="upx" || cns_UPX=""
	[ -z "$cns_install_dir" ] && cns_install_dir='/usr/local/cns'
	export cns_port cns_encrypt_password cns_udp_flag cns_proxy_key cns_tls_port cns_install_dir cns_UPX
}

xray_set() {
		echo -n "请输入xray安装目录(默认: /usr/local/xray): "
		read xray_install_directory
		echo $echo_opt_e "选项(TLS默认为自签名证书, 如有需要请自行更改):
		\r1. tcp http                   (vmess)
		\r2. tcp tls                    (vmess)
		\r3. tcp reality                (vless)
		\r4. websocket                  (vmess)
		\r5. websocket tls              (vmess)
		\r6. websocket tls              (vless)
		\r7. mkcp                       (vmess)
		\r8. mkcp tls                   (vmess)
		\r9. mkcp tls                   (vless)
		\r10. trojan tls
		\r请输入你的选项(多个选项用空格分隔):"
		read xray_inbounds_options
		for opt in $xray_inbounds_options; do
			case $opt in
				1)
					echo -n "请输入vmess tcp http服务端口: "
					read vmess_tcp_http_port
				;;
				2)
					echo -n "请输入vmess tcp tls服务端口: "
					read vmess_tcp_tls_port
				;;
				3)
					echo -n "请输入vless tcp reality服务端口: "
					read vless_tcp_reality_port
				;;
				4)
					echo -n "请输入vmess websocket服务端口: "
					read vmess_ws_port
					echo -n "请输入vmess websocket路径(默认: '/'): "
					read vmess_ws_path
					vmess_ws_path=${vmess_ws_path:-/}
				;;
				5)
					echo -n "请输入vmess websocket tls服务端口: "
					read vmess_ws_tls_port
					echo -n "请输入vmess websocket tls路径(默认: '/'): "
					read vmess_ws_tls_path
					vmess_ws_tls_path=${vmess_ws_tls_path:-/}
				;;
				6)
					echo -n "请输入vless websocket tls服务端口: "
					read vless_ws_tls_port
					echo -n "请输入vless websocket tls路径(默认: '/'): "
					read vless_ws_tls_path
					vless_ws_tls_path=${vless_ws_tls_path:-/}
				;;
				7)
					echo -n "请输入vmess mKCP服务端口: "
					read vmess_mkcp_port
				;;
				8)
					echo -n "请输入vmess mKCP tls服务端口: "
					read vmess_mkcp_tls_port
				;;
				9)
					echo -n "请输入vless mKCP tls服务端口: "
					read vless_mkcp_tls_port
				;;
				10)
					echo -n "请输入trojan tls服务端口: "
					read trojan_tls_port
				;;
			esac
		done
		echo -n "安装UPX压缩版本?[n]: "
		read xray_UPX
		[ -z "$xray_install_directory" ] && xray_install_directory='/usr/local/xray'
		export xray_install_directory xray_inbounds_options vmess_tcp_http_port vmess_tcp_tls_port vless_tcp_reality_port vmess_ws_port vmess_ws_path vmess_ws_tls_port vmess_ws_tls_path vless_ws_tls_port vless_ws_tls_path vmess_mkcp_port vmess_mkcp_tls_port vless_mkcp_tls_port trojan_tls_port xray_UPX
}

amy4_set() {

	echo -n "请输入amy4服务端口: "
	read amy4_port
	echo -n "请输入amy4连接密码(ClientKey): "
	read amy4_clientkey
	echo -n "服务器是否支持IPV6[n]: "
	read ipv6_support
	echo -n "请输入安装目录(默认/usr/local/amy4): "  #安装目录
	read amy4_install_dir
	[ -z "$amy4_install_dir" ] && amy4_install_dir=/usr/local/amy4
	echo -n "安装UPX压缩版本?[n]: "
	read amy4_UPX

	echo "$amy4_install_dir"|grep -q '^/' || amy4_install_dir="$PWD/$amy4_install_dir"
	export amy4_port amy4_clientkey ipv6_support amy4_install_dir amy4_UPX
}

tinyproxy_task() {
	if dl tinyproxy.sh ${BASE}/tinyproxy/tinyproxy.sh?ref=main; then
		chmod 777 tinyproxy.sh
		sed -i "s~#\!/bin/bash~#\!$SHELL~" tinyproxy.sh
		./tinyproxy.sh $task_type && \
				echo 'tinyproxy任务成功' >>builds.log || \
				echo 'tinyproxy启动失败' >>builds.log
	else
		echo 'tinyproxy脚本下载失败' >>builds.log
	fi
	rm -f tinyproxy.sh
}

cns_task() {
	if dl cns.sh ${BASE}/cns/cns.sh?ref=main; then
		chmod 777 cns.sh
		sed -i "s~#\!/bin/bash~#\!$SHELL~" cns.sh
		echo $echo_opt_e "n\ny\ny\ny\ny\n"|./cns.sh $task_type && \
				echo 'cns任务成功' >>builds.log || \
				echo 'cns启动失败' >>builds.log
	else
		echo 'cns脚本下载失败' >>builds.log
	fi
	rm -f cns.sh
}

xray_task() {
	if dl xray.sh ${BASE}/xray/xray.sh?ref=main; then
		chmod 777 xray.sh
		sed -i "s~#\!/bin/bash~#\!$SHELL~" xray.sh
		echo $echo_opt_e "n\ny\ny\ny\ny\n"|./xray.sh $task_type && \
			echo 'xray任务成功' >>builds.log || \
			echo 'xray任务失败' >>builds.log
	else
		echo 'xray脚本下载失败' >>builds.log
	fi
	rm -f xray.sh
}

amy4_task() {
	if dl amy4.sh ${BASE}/amy4/amy4.sh?ref=main; then
		chmod 777 amy4.sh
		sed -i "s~#\!/bin/bash~#\!$SHELL~" amy4.sh
		echo $echo_opt_e "n"|./amy4.sh $task_type && \
			echo 'amy4任务成功' >>builds.log || \
			echo 'amy4任务失败' >>builds.log
	else
		echo 'amy4脚本下载失败' >>builds.log
	fi
	rm -f amy4.sh
}

tinyproxy_uninstall_set() {
	echo -n '请输入tinyproxy安装目录(默认/usr/local/tinyproxy): '
	read tinyproxy_install_dir
	[ -z "$tinyproxy_install_dir" ] && tinyproxy_install_dir='/usr/local/tinyproxy'
	export tinyproxy_install_dir
}

cns_uninstall_set() {
	echo -n '请输入cns安装目录(默认/usr/local/cns): '
	read cns_install_dir
	[ -z "$cns_install_dir" ] && cns_install_dir='/usr/local/cns'
	export cns_install_dir
}

xray_uninstall_set() {
	echo -n "请输入xray安装目录(默认/usr/local/xray): "
	read xray_install_directory
	[ -z "$xray_install_directory" ] && xray_install_directory='/usr/local/xray'
	export xray_install_directory
}

amy4_uninstall_set() {
	echo -n "请输入amy4安装目录(默认/usr/local/amy4): "
	read amy4_install_dir
	[ -z "$amy4_install_dir" ] && amy4_install_dir='/usr/local/amy4'
	export amy4_install_dir
}

server_install_set() {
	for opt in $*; do
		case $opt in
			1) echo "   → tinyproxy: 本仓库没有可用二进制，本次跳过";;
			2) cns_set;;
			3) xray_set;;
			4) amy4_set;;
			*) exec echo "选项($opt)不正确，请输入正确的选项！";;
		esac
	done
}

server_uninstall_set() {
	for opt in $*; do
		case $opt in
			1) tinyproxy_uninstall_set;;
			2) cns_uninstall_set;;
			3) xray_uninstall_set;;
			4) amy4_uninstall_set;;
			*) exec echo "选项($opt)不正确，请输入正确的选项！";;
		esac
	done
}

start_task() {
	for opt in $*; do
		case $opt in
			1) echo "   → tinyproxy: 本仓库没有可用二进制（上游那份是 70 字节跳转页），本次跳过";;
			2) cns_task;;
			3) xray_task;;
			4) amy4_task;;
		esac
		sleep 1
	done
	echo '所有任务完成' >>builds.log
	echo $echo_opt_e "\033[32m`cat builds.log 2>&-`\033[0m"
}

run_tasks() {
	[ "$task_type" != 'uninstall' ] && server_install_set $build_projects || server_uninstall_set $build_projects
	if echo "$daemon_run"|grep -qi 'y'; then
		(`start_task $build_projects &>builds.out` &)
		echo "正在后台运行中......"
	else
		start_task $build_projects
		rm -f builds.log
	fi
}

script_init() {
	emulate bash 2>/dev/null #zsh仿真模式
	echo -e '' | grep -q 'e' && echo_opt_e='' || echo_opt_e='-e' #dash的echo没有-e选项
	PM=`which apt-get || which yum`
	type curl || type wget || $PM -y install curl wget
	dl() {
	if type curl &>/dev/null; then
		if [ -n "${GH_TOKEN:-}" ]; then
			curl -fsSL -k -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github.raw" -o "$1" "$2"
		else
			curl -fsSL -k -H "Accept: application/vnd.github.raw" -o "$1" "$2"
		fi
	else
		if [ -n "${GH_TOKEN:-}" ]; then
			wget -q --no-check-certificate --header="Authorization: Bearer $GH_TOKEN" --header='Accept: application/vnd.github.raw' -O "$1" "$2"
		else
			wget -q --no-check-certificate --header='Accept: application/vnd.github.raw' -O "$1" "$2"
		fi
	fi
}
	rm -f builds.log builds.out
	clear
}

main() {
	script_init
	option
	run_tasks
}

main
