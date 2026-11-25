#!/bin/sh
# go.sh — 一键：拉取本仓库整包 → 部署 ccc / pull.sh / status.sh → 进入安装菜单
#
#   sh go.sh              拉整包 + 部署脚本 + 进安装/卸载菜单
#   sh go.sh --no-menu    只拉取和部署，不进菜单
#   sh go.sh --force      远端没变也强制重新下载
#
# 环境变量：REPO=abcc123445653/1  BRANCH=main  DIR=/root
set -eu

REPO="${REPO:-abcc123445653/1}"
BRANCH="${BRANCH:-main}"
DIR="${DIR:-/root}"
TAR="https://codeload.github.com/$REPO/tar.gz/refs/heads/$BRANCH"

# 没设 GH_TOKEN 时，尝试从 /root/.gh_token 读（cron / 非交互 shell 也能用）
if [ -z "${GH_TOKEN:-}" ] && [ -f /root/.gh_token ]; then
	GH_TOKEN=$(cat /root/.gh_token 2>/dev/null || true)
	export GH_TOKEN
fi

info() { printf '\033[44;37m %s \033[0m\n' "$*"; }
die()  { echo "错误: $*" >&2; exit 1; }

remote_rev() {
	r=$(git ls-remote "https://github.com/$REPO.git" "refs/heads/$BRANCH" 2>/dev/null \
		| sed -n 's/^\([0-9a-f][0-9a-f]*\)[[:space:]].*/\1/p' | head -1)
	if [ -n "$r" ]; then
		printf '%s\n' "$r"
		return 0
	fi
	if [ -n "${GH_TOKEN:-}" ]; then
		curl -kL --no-progress-meter --max-time 20 -H "Authorization: Bearer $GH_TOKEN" \
			"https://api.github.com/repos/$REPO/commits/$BRANCH" 2>/dev/null \
			| sed -n 's/.*"sha"[[:space:]]*:[[:space:]]*"\([0-9a-f][0-9a-f]*\)".*/\1/p' | head -1
	else
		curl -kL --no-progress-meter --max-time 20 "https://api.github.com/repos/$REPO/commits/$BRANCH" 2>/dev/null \
			| sed -n 's/.*"sha"[[:space:]]*:[[:space:]]*"\([0-9a-f][0-9a-f]*\)".*/\1/p' | head -1
	fi
}

verify_kit() {
	[ -f "$DIR/1-main/SHA256SUMS" ] || return 0
	if (cd "$DIR/1-main" && sha256sum -c SHA256SUMS >/dev/null 2>&1); then
		echo "  → 二进制校验通过（SHA256SUMS）"
	else
		die "整包校验失败：$DIR/1-main 与 SHA256SUMS 不符"
	fi
}


mkdir -p "$DIR"
rev=$(remote_rev || true)
if [ "${FORCE:-0}" != "1" ] && [ -n "$rev" ] && [ -f "$DIR/1-main/.kit-rev" ] \
	&& [ "$(cat "$DIR/1-main/.kit-rev" 2>/dev/null)" = "$rev" ]; then
	echo "  → 已是最新（$(echo "$rev" | cut -c1-8)），跳过整包下载"
else
	info "拉整包 $REPO@$BRANCH → $DIR/1-main"
	curl -kL --progress-bar --max-time 600 "$TAR" -o "$DIR/repo.tar.gz" || die "整包下载失败"
	rm -rf "$DIR/1-main"
	tar xzf "$DIR/repo.tar.gz" -C "$DIR" || die "解压失败"
	rm -f "$DIR/repo.tar.gz"
	echo "  → $DIR/1-main   $(du -sh "$DIR/1-main" 2>/dev/null | cut -f1)"
	verify_kit
	if [ -n "$rev" ]; then printf '%s\n' "$rev" > "$DIR/1-main/.kit-rev"; fi
fi

# 部署常用入口，之后直接 ccc / sh pull.sh 就能用
[ -f "$DIR/1-main/pull.sh" ] && cp "$DIR/1-main/pull.sh" "$DIR/pull.sh" && chmod +x "$DIR/pull.sh" && echo "  → $DIR/pull.sh"
[ -f "$DIR/1-main/status.sh" ] && cp "$DIR/1-main/status.sh" "$DIR/status.sh" && chmod +x "$DIR/status.sh" && echo "  → $DIR/status.sh"
if [ -d /usr/local/bin ] && [ -f "$DIR/status.sh" ]; then
	if [ -f "$DIR/1-main/ccc.sh" ]; then
		cp "$DIR/1-main/ccc.sh" /usr/local/bin/ccc
	else
		printf '#!/usr/bin/env sh\nexec sh %s/status.sh edit "$@"\n' "$DIR" > /usr/local/bin/ccc
	fi
	chmod +x /usr/local/bin/ccc
	echo "  → /usr/local/bin/ccc   输入 ccc 回车即打开面板"
fi

menu=1
for a in "$@"; do
	case "$a" in
	--no-menu) menu=0 ;;
	--force)   FORCE=1 ;;
	esac
done
[ "$menu" = "1" ] || exit 0

info "进入安装菜单"
cd "$DIR/1-main/parso" || die "整包里没有 parso/"
exec sh builds.sh
