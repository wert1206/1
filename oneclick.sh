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

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

# 三种认证方式：GH_TOKEN（fine-grained PAT）> 部署密钥 > 已配置的 SSH
if [ -n "${GH_TOKEN:-}" ]; then
	REPO="https://x-access-token:${GH_TOKEN}@github.com/abcc123445653/1.git"
	echo "==> 用 GH_TOKEN 从 GitHub 克隆仓库"
	git clone --depth 1 "$REPO" "$TMP/repo" 2>/dev/null \
		|| die "克隆失败：检查 token 是否有效、是否勾选了该仓库的 Contents: Read"
else
	REPO="${REPO_URL:-$REPO_DEFAULT}"
	GH_KEY="${GH_KEY:-$HOME/.ssh/github_1}"
	if [ -f "$GH_KEY" ]; then
		export GIT_SSH_COMMAND="ssh -i $GH_KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
	fi
	echo "==> 未检测到本地套件，从 $REPO 克隆"
	git clone --depth 1 "$REPO" "$TMP/repo" 2>/dev/null \
		|| die "克隆失败。私有仓库需要 GH_TOKEN，或本机已配置可读它的 SSH 密钥（默认 $GH_KEY）"
fi

[ -f "$TMP/repo/selfhost-kit/install.sh" ] || die "仓库结构异常：找不到 selfhost-kit/install.sh"

echo "==> 已克隆到 $TMP/repo"
exec sh "$TMP/repo/selfhost-kit/install.sh" "$@"
