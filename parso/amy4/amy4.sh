#!/bin/bash
BASE="${BASE:-https://api.github.com/repos/abcc123445653/1/contents/parso}"

#Stop amy4 & delete amy4 files.
Delete() {
	systemctl stop amy4.service 2>/dev/null
	systemctl disable amy4.service
	chkconfig --del amy4
	/etc/init.d/amy4 disable
	if [ -f "${amy4_install_dir:=/usr/local/amy4}/amy4.init" ]; then
		"$amy4_install_dir"/amy4.init stop
		rm -rf "$amy4_install_dir"
	fi
	rm -f /etc/init.d/amy4 /lib/systemd/system/amy4.service /etc/rc.d/rc5.d/S99amy4 /etc/rc.d/S99amy4 /etc/rc5.d/S99amy4
}

#Print error message and exit.
Error() {
	echo $echo_e_arg "\033[41;37m$1\033[0m"
	echo -n "remove amy4?[y]: "
	read remove
	echo "$remove"|grep -qi 'n' || Delete
	exit 1
}

#Make amy4 start cmd
Config() {
	if [ -z "$amy4_install_dir" ]; then  #Variables come from the environment
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
	fi
	echo "$ipv6_support"|grep -qi '^y' && ipv6_support="true" || ipv6_support="false"
	echo "$amy4_UPX"|grep -qi '^y' && amy4_UPX="upx" || amy4_UPX=""
}

GetAbi() {
	machine=`uname -m`
	#mips[...] use 'le' version
	if echo "$machine"|grep -q 'mips64'; then
		shContent=`cat "$SHELL"`
		[ "${shContent:5:1}" = `echo $echo_e_arg "\x01"` ] && machine='mips64le' || machine='mips64'
	elif echo "$machine"|grep -q 'mips'; then
		shContent=`cat "$SHELL"`
		[ "${shContent:5:1}" = `echo $echo_e_arg "\x01"` ] && machine='mipsle' || machine='mips'
	elif echo "$machine"|grep -Eq 'i686|i386'; then
		machine='386'
	elif echo "$machine"|grep -Eq 'armv7|armv6'; then
		machine='arm'
	elif echo "$machine"|grep -Eq 'armv8|aarch64'; then
		machine='arm64'
	elif echo "$machine"|grep -q 's390x'; then
		machine='s390x'
	else
		machine='amd64'
	fi
}

GetOs() {
	if [ -f '/system/bin/sh' -a "$machine" = 'arm64' ]; then
		os=android
	else
		os=linux
	fi
}

#install amy4 files
InstallFiles() {
	GetAbi
	GetOs
	if echo "$machine" | grep -q '^mips'; then
		cat /proc/cpuinfo | grep -qiE 'fpu|neon|vfp|softfp|asimd' || softfloat='_softfloat'
	fi
	mkdir -p "$amy4_install_dir" || Error "Create amy4 install directory failed."
	cd "$amy4_install_dir" || exit 1
	download_tool amy4 ${BASE}/amy4/${amy4_UPX:+$amy4_UPX/}${os}_${machine}${softfloat}?ref=main || Error "amy4 download failed."
	download_tool amy4.init ${BASE}/amy4/amy4.init?ref=main || Error "amy4.init download failed."
	[ -f '/etc/rc.common' ] && rcCommon='/etc/rc.common'
	sed -i "s~#!/bin/sh~#!$SHELL $rcCommon~" amy4.init
	sed -i "s~\[amy4_install_dir\]~$amy4_install_dir~g" amy4.init
	sed -i "s~\[amy4_tcp_port_list\]~$amy4_port~g" amy4.init
	ln -s "$amy4_install_dir/amy4.init" /etc/init.d/amy4
	cat >amy4.json <<-EOF
{
	"PidFile": "${amy4_install_dir}/run.pid",
	"Log": {
		"Level": "none"
	},
	"AmyIns": [{
		"ProxyType": "ANet",
		"ANetSettings": {
			"ListenAddr": ":${amy4_port}",
			"ClientKeys": ["${amy4_clientkey}"],
			"IPv6Support": ${ipv6_support}
		}
	}],
	"AmyOuts": [{
		"ProxyType": "Origin",
		"Tag": "Origin"
	}],
	"Routers": []
}
	EOF
	chmod -R +rwx "$amy4_install_dir" /etc/init.d/amy4
	if type systemctl &>/dev/null && [ -z "$(systemctl --failed|grep -q 'Host is down')" ]; then
		download_tool /lib/systemd/system/amy4.service ${BASE}/amy4/amy4.service?ref=main || Error "amy4.service download failed."
		chmod +rwx /lib/systemd/system/amy4.service
		sed -i "s~\[amy4_install_dir\]~$amy4_install_dir~g"  /lib/systemd/system/amy4.service
		systemctl daemon-reload
	fi
}

#install initialization
InstallInit() {
	echo -n "make a update?[n]: "
	read update
	PM=$(command -v apt-get || command -v yum)
	PM=`echo "$PM" | grep -o '/.*'`
	echo "$update"|grep -qi 'y' && $PM -y update
	$PM -y install curl wget unzip sed
	if type curl &>/dev/null; then
		download_tool() {
			if [ -n "${GH_TOKEN:-}" ]; then
				curl -fsSL -k -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github.raw" -o $@
			else
				curl -fsSL -k -H "Accept: application/vnd.github.raw" -o $@
			fi
		}
	else
		download_tool() {
			if [ -n "${GH_TOKEN:-}" ]; then
				wget -q --no-check-certificate --header="Authorization: Bearer $GH_TOKEN" --header='Accept: application/vnd.github.raw' -O $@
			else
				wget -q --no-check-certificate --header='Accept: application/vnd.github.raw' -O $@
			fi
		}
	fi
}

AddAutoStart() {
	if [ -n "$rcCommon" ]; then
		if /etc/init.d/amy4 enable; then
			echo '已添加开机自启, 如需关闭请执行: /etc/init.d/amy4 disable'
			return
		fi
	fi
	if type systemctl &>/dev/null && [ -z "$(systemctl --failed|grep -q 'Host is down')" ]; then
		if systemctl enable amy4 &>/dev/null; then
			echo '已添加开机自启, 如需关闭请执行: systemctl disable amy4'
			return
		fi
	fi
	if type chkconfig &>/dev/null; then
		if chkconfig --add amy4 &>/dev/null && chkconfig amy4 on &>/dev/null; then
			echo '已添加开机自启, 如需关闭请执行: chkconfig amy4 off'
			return
		fi
	fi
	if [ -d '/etc/rc.d/rc5.d' -a -f '/etc/init.d/amy4' ]; then
		if ln -s '/etc/init.d/amy4' '/etc/rc.d/rc5.d/S99amy4'; then
			echo '已添加开机自启, 如需关闭请执行: rm -f /etc/rc.d/rc5.d/S99amy4'
			return
		fi
	fi
	if [ -d '/etc/rc5.d' -a -f '/etc/init.d/amy4' ]; then
		if ln -s '/etc/init.d/amy4' '/etc/rc5.d/S99amy4'; then
			echo '已添加开机自启, 如需关闭请执行: rm -f /etc/rc5.d/S99amy4'
			return
		fi
	fi
	if [ -d '/etc/rc.d' -a -f '/etc/init.d/amy4' ]; then
		if ln -s '/etc/init.d/amy4' '/etc/rc.d/S99amy4'; then
			echo '已添加开机自启, 如需关闭请执行: rm -f /etc/rc.d/S99amy4'
			return
		fi
	fi
	echo '没有添加开机自启, 如需开启请手动添加'
}

Install() {
	Config
	Delete >/dev/null 2>&1
	InstallInit
	InstallFiles
	ret=`"${amy4_install_dir}/amy4.init" start`
	if ! echo "$ret"|grep -q 'OK' || echo "$ret"|grep -q 'FAILED'; then
		Error "amy4 install failed."
	fi
	type systemctl &>/dev/null && [ -z "$(systemctl --failed|grep -q 'Host is down')" ] && systemctl restart amy4
	echo $echo_e_arg \
		"\033[44;37mamy4 install success.\033[0;34m
		\r	amy4 server port:\033[35G${amy4_port}
		\r	amy4 client key:\033[35G${amy4_clientkey}
		\r`[ -f /etc/init.d/amy4 ] && /etc/init.d/amy4 usage || \"$amy4_install_dir/amy4.init\" usage`
		\r`AddAutoStart`\033[0m"
}

Uninstall() {
	if [ -z "$amy4_install_dir" ]; then
		echo -n "Please input amy4 install directory(default is /usr/local/amy4): "
		read amy4_install_dir
	fi
	Delete >/dev/null 2>&1 && \
		echo $echo_e_arg "\n\033[44;37mamy4 uninstall success.\033[0m" || \
		echo $echo_e_arg "\n\033[41;37mamy4 uninstall failed.\033[0m"
}

#script initialization
ScriptInit() {
	emulate bash 2>/dev/null #zsh emulation mode
	if echo -e ''|grep -q 'e'; then
		echo_e_arg=''
		echo_E_arg=''
	else
		echo_e_arg='-e'
		echo_E_arg='-E'
	fi
}

ScriptInit
echo $*|grep -qi uninstall && Uninstall || Install
