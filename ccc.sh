#!/bin/sh
# ccc — 打开配置面板（查看 + 修改 + 启停 + 安装/卸载）
# 由 pull.sh / go.sh 安装到 /usr/local/bin/ccc，之后直接输 ccc 回车即可。
if [ -f /root/status.sh ]; then
	exec sh /root/status.sh edit "$@"
elif [ -f /usr/local/bin/status.sh ]; then
	exec sh /usr/local/bin/status.sh edit "$@"
else
	echo "找不到 status.sh，先执行："
	echo "  curl -L --no-progress-meter -H 'Accept: application/vnd.github.raw' -o /root/status.sh 'https://api.github.com/repos/wert1206/1/contents/status.sh?ref=main'"
	exit 1
fi
