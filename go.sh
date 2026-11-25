#!/bin/sh
# go.sh — 一键：拉取本仓库整包 → 部署 ccc / pull.sh / status.sh → 进入安装菜单
#
#   sh go.sh              拉整包 + 部署脚本 + 进安装/卸载菜单
#   sh go.sh --no-menu    只拉取和部署，不进菜单
#
# 环境变量：REPO=abcc123445653/1  BRANCH=main  DIR=/root
set -eu

REPO="${REPO:-abcc123445653/1}"
BRANCH="${BRANCH:-main}"
DIR="${DIR:-/root}"
TAR="https://codeload.github.com/$REPO/tar.gz/refs/heads/$BRANCH"

info() { printf '\033[44;37m %s \033[0m\n' "$*"; }
die()  { echo "错误: $*" >&2; exit 1; }

info "拉整包 $REPO@$BRANCH → $DIR/1-main"
mkdir -p "$DIR"
curl -kL --progress-bar --max-time 600 "$TAR" -o "$DIR/repo.tar.gz" || die "整包下载失败"
rm -rf "$DIR/1-main"
tar xzf "$DIR/repo.tar.gz" -C "$DIR" || die "解压失败"
rm -f "$DIR/repo.tar.gz"
echo "  → $DIR/1-main   $(du -sh "$DIR/1-main" 2>/dev/null | cut -f1)"

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

[ "${1:-}" = "--no-menu" ] && exit 0

info "进入安装菜单"
cd "$DIR/1-main/parso" || die "整包里没有 parso/"
exec sh builds.sh
