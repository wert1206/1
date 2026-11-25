#!/bin/sh
# oneclick.sh — 仓库根的一键入口
#
# 两种用法：
#   1) 已在仓库里：  sudo ./oneclick.sh
#   2) 不在仓库里：  sudo sh oneclick.sh          # 自动克隆到临时目录再装
#
# 所有参数原样透传给 selfhost-kit/install.sh，例如：
#   sudo ./oneclick.sh --xray-port 443 --cns-port 80 --amy4-port 18443
#   sudo ./oneclick.sh --dry-run
#
set -eu

REPO_DEFAULT="git@github.com:abcc123445653/1.git"
SELF=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
KIT="$SELF/selfhost-kit/install.sh"

die() { echo "错误: $*" >&2; exit 1; }

if [ -f "$KIT" ]; then
	exec sh "$KIT" "$@"
fi

# 当前目录不是仓库：克隆后再执行
command -v git >/dev/null 2>&1 || die "缺少 git，请先安装"

REPO="${REPO_URL:-$REPO_DEFAULT}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

echo "==> 未检测到本地套件，从 $REPO 克隆"
git clone --depth 1 "$REPO" "$TMP/repo" >/dev/null 2>&1 \
	|| die "克隆失败。私有仓库需要本机已配置可读它的 SSH 密钥（~/.ssh/config 指定 IdentityFile）"

[ -f "$TMP/repo/selfhost-kit/install.sh" ] || die "仓库结构异常：找不到 selfhost-kit/install.sh"

echo "==> 已克隆到 $TMP/repo"
exec sh "$TMP/repo/selfhost-kit/install.sh" "$@"
