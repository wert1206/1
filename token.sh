#!/bin/sh
# token.sh — 保存 / 查看 / 清除 GitHub token（token 本身不进仓库，只存在本机）
#
#   sh token.sh                 从标准输入读 token 并保存（推荐，不留在 shell history）
#   sh token.sh ghp_xxx         直接带参数保存（会进 shell history，慎用）
#   sh token.sh ghp_xxx --bashrc   同时写进 /root/.bashrc 的 export GH_TOKEN
#   sh token.sh --show          查看当前是否已配置（脱敏）与额度
#   sh token.sh --clear         删除 /root/.gh_token 和 .bashrc 里的那一行
#
# 保存位置：/root/.gh_token（权限 600）。pull.sh / go.sh / parso/builds.sh 会自动读。
set -eu

FILE="${TOKEN_FILE:-/root/.gh_token}"
BRC="${BASHRC:-/root/.bashrc}"

mask() { printf '%s' "$1" | cut -c1-14; }

quota() { # $1=token
	if [ -n "${1:-}" ]; then
		curl -kL --no-progress-meter --max-time 20 -H "Authorization: Bearer $1" \
			https://api.github.com/rate_limit 2>/dev/null | python3 -c '
import sys, json
try:
	d = json.load(sys.stdin)["resources"]["core"]
	print("limit=%d remaining=%d" % (d["limit"], d["remaining"]))
except Exception:
	print("取不到")'
	fi
}

clear_all() {
	rm -f "$FILE"
	if [ -f "$BRC" ]; then
		sed -i '/^export GH_TOKEN=/d' "$BRC"
	fi
	echo "已清除 $FILE 与 $BRC 中的 GH_TOKEN"
}

show() {
	if [ -s "$FILE" ]; then
		t=$(cat "$FILE")
		echo "已配置：$(mask "$t")…（$FILE，权限 $(stat -c '%a' "$FILE" 2>/dev/null || echo '?')）"
		q=$(quota "$t")
		echo "额度：${q:-取不到（token 可能失效）}"
	else
		echo "未配置 $FILE"
		[ -f "$BRC" ] && grep -q '^export GH_TOKEN=' "$BRC" && echo "注意：$BRC 里还有一行 export GH_TOKEN"
	fi
}

case "${1:-}" in
--show)  show; exit 0 ;;
--clear) clear_all; exit 0 ;;
-h|--help|help)
	sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac

WITH_BRC=0
if [ "${1:-}" = "--bashrc" ]; then WITH_BRC=1; shift; fi
if [ "${1:-}" = "" ]; then
	printf '粘贴 token 后回车（不回显到命令历史）: '
	read -r TOK
else
	TOK="$1"; shift || true
	[ "${1:-}" = "--bashrc" ] && WITH_BRC=1
fi

[ -n "${TOK:-}" ] || { echo "错误：没有收到 token" >&2; exit 1; }

code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 -H "Authorization: Bearer $TOK" https://api.github.com/user || echo 000)
if [ "$code" != "200" ]; then
	echo "错误：token 验证失败（HTTP $code），没有保存" >&2
	exit 1
fi

umask 077
printf '%s\n' "$TOK" > "$FILE"
chmod 600 "$FILE"
echo "已保存到 $FILE（600）"

if [ "$WITH_BRC" = "1" ]; then
	if [ -f "$BRC" ]; then
		sed -i '/^export GH_TOKEN=/d' "$BRC"
		[ -n "$(tail -c1 "$BRC" 2>/dev/null)" ] && printf '\n' >> "$BRC"
	fi
	printf 'export GH_TOKEN=%s\n' "$TOK" >> "$BRC"
	echo "已写入 $BRC 的 export GH_TOKEN"
fi

echo "额度：$(quota "$TOK")"
echo "验证：sh token.sh --show"
