#!/bin/sh
# go.sh — 一键：拉取本仓库整包 → 部署 ccc / pull.sh / status.sh → 进入安装菜单
#
#   sh go.sh              拉整包 + 部署脚本 + 进安装/卸载菜单
#   sh go.sh --no-menu    只拉取和部署，不进菜单
#   sh go.sh --force      远端没变也强制重新下载
#   sh go.sh 包.tar.gz    直接解压本地上传的压缩包并运行（不联网，支持 .tar.gz/.zip）
#   sh go.sh --help       显示本用法
#
# 环境变量：REPO=wert1206/1  BRANCH=main  DIR=/root
#           FORCE=1（等同 --force）  INSECURE=1（跳过 TLS 校验）
#           SKIP_CCC=1（不安装 /usr/local/bin/ccc，便于非 root 测试）
set -eu

REPO="${REPO:-wert1206/1}"
BRANCH="${BRANCH:-main}"
DIR="${DIR:-/root}"
TAR="https://codeload.github.com/$REPO/tar.gz/refs/heads/$BRANCH"
TARBALL="$DIR/repo.tar.gz"

CURL_K=""
if [ "${INSECURE:-0}" = "1" ]; then CURL_K="-k"; fi

usage() {
	cat <<'EOF'
go.sh — 一键拉取 + 部署 + 安装菜单

  sh go.sh              拉整包 + 部署脚本 + 进安装/卸载菜单
  sh go.sh --no-menu    只拉取和部署，不进菜单
  sh go.sh --force      远端没变也强制重新下载
  sh go.sh 包.tar.gz    解压本地上传的整包（.tar.gz / .tgz / .zip）并运行
  sh go.sh --help       显示本用法

环境变量：
  REPO=wert1206/1  BRANCH=main  DIR=/root
  FORCE=1      等同 --force
  INSECURE=1   跳过 TLS 校验（仅老机器/异常 CA 时用）
  SKIP_CCC=1   不安装 /usr/local/bin/ccc（非 root 测试用）
EOF
}

info() { printf '\033[44;37m %s \033[0m\n' "$*"; }
die()  { echo "错误: $*" >&2; exit 1; }

menu=1
ARCHIVE=""
for a in "$@"; do
	case "$a" in
	--no-menu) menu=0 ;;
	--force)   FORCE=1 ;;
	-h|--help) usage; exit 0 ;;
	-*)        echo "未知参数: $a（可用 --no-menu / --force / --help）" >&2; exit 2 ;;
	*)
		if [ -n "$ARCHIVE" ]; then
			echo "只能指定一个压缩包（已指定 $ARCHIVE）" >&2
			exit 2
		fi
		ARCHIVE="$a" ;;
	esac
done

# 没设 GH_TOKEN 时，尝试从 /root/.gh_token 读（cron / 非交互 shell 也能用）
if [ -z "${GH_TOKEN:-}" ] && [ -f /root/.gh_token ]; then
	GH_TOKEN=$(cat /root/.gh_token 2>/dev/null || true)
	export GH_TOKEN
fi

cleanup() {
	if [ "${TAR_DOWNLOADED:-0}" = "1" ]; then rm -f "$TARBALL"; fi
	if [ -n "${EXT_DIR:-}" ]; then rm -rf "$EXT_DIR"; fi
	return 0
}
trap cleanup 0 1 2 15

# 脚本自己就在整包目录里（codeload 引导解压后直接跑）时，不再联网下载
SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd || echo "")
KIT="$DIR/1-main"
LOCAL_KIT=0
if [ -n "$SELF_DIR" ] && [ -f "$SELF_DIR/parso/builds.sh" ] && [ -f "$SELF_DIR/status.sh" ]; then
	KIT="$SELF_DIR"
	LOCAL_KIT=1
fi

# 本地上传的压缩包模式：解压 → 校验 → 部署 → 直接运行包里的 go.sh（全程不联网）
if [ -n "$ARCHIVE" ]; then
	[ -f "$ARCHIVE" ] || die "压缩包不存在: $ARCHIVE"
	case "$ARCHIVE" in
	*.zip|*.tar.gz|*.tgz|*.tar) ;;
	*) die "只支持 .tar.gz / .tgz / .tar / .zip" ;;
	esac
	mkdir -p "$DIR"
	EXT_DIR=$(mktemp -d "$DIR/.unpack.XXXXXX") || die "无法创建解压目录"
	info "解压 $ARCHIVE → $DIR/1-main"
	case "$ARCHIVE" in
	*.zip)
		python3 - "$ARCHIVE" "$EXT_DIR" <<'PY' || die "解压失败（需要 python3 处理 zip）"
import sys, zipfile
zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])
PY
		;;
	*.tar.gz|*.tgz|*.tar)
		tar xzf "$ARCHIVE" -C "$EXT_DIR" || die "解压失败"
		;;
	esac
	ROOT=""
	for d in "$EXT_DIR" "$EXT_DIR"/*; do
		if [ -f "$d/go.sh" ] && [ -f "$d/parso/builds.sh" ] && [ -f "$d/status.sh" ]; then
			ROOT="$d"
			break
		fi
	done
	[ -n "$ROOT" ] || die "压缩包里没找到 go.sh + parso/builds.sh + status.sh，确认上传的是整包"
	rm -rf "$DIR/1-main"
	mv "$ROOT" "$DIR/1-main" || die "移动到 $DIR/1-main 失败"
	rm -rf "$EXT_DIR"
	EXT_DIR=""
	info "运行整包里的 go.sh（不再联网）"
	export DIR REPO BRANCH NO_REV=1
	if [ "$menu" = "1" ]; then
		exec sh "$DIR/1-main/go.sh"
	else
		exec sh "$DIR/1-main/go.sh" --no-menu
	fi
fi

remote_rev() {
	r=$(timeout 5 git ls-remote "https://github.com/$REPO.git" "refs/heads/$BRANCH" 2>/dev/null \
		| sed -n 's/^\([0-9a-f][0-9a-f]*\)[[:space:]].*/\1/p' | head -1)
	if [ -n "$r" ]; then
		printf '%s\n' "$r"
		return 0
	fi
	if [ -n "${GH_TOKEN:-}" ]; then
		curl $CURL_K -L --no-progress-meter --max-time 20 -H "Authorization: Bearer $GH_TOKEN" \
			"https://api.github.com/repos/$REPO/commits/$BRANCH" 2>/dev/null \
			| sed -n 's/.*"sha"[[:space:]]*:[[:space:]]*"\([0-9a-f][0-9a-f]*\)".*/\1/p' | head -1
	else
		curl $CURL_K -L --no-progress-meter --max-time 20 "https://api.github.com/repos/$REPO/commits/$BRANCH" 2>/dev/null \
			| sed -n 's/.*"sha"[[:space:]]*:[[:space:]]*"\([0-9a-f][0-9a-f]*\)".*/\1/p' | head -1
	fi
}

verify_kit() {
	[ -f "$KIT/SHA256SUMS" ] || return 0
	if (cd "$KIT" && sha256sum -c SHA256SUMS >/dev/null 2>&1); then
		echo "  → 二进制校验通过（SHA256SUMS）"
	else
		die "整包校验失败：$KIT 与 SHA256SUMS 不符"
	fi
}


mkdir -p "$DIR"
if [ "${NO_REV:-0}" = "1" ]; then
	rev=""
else
	rev=$(remote_rev || true)
fi
if [ "$LOCAL_KIT" = "1" ]; then
	echo "  → 已在整包里（$KIT），跳过下载"
	verify_kit
	if [ -n "$rev" ]; then
		printf '%s\n' "$rev" > "$KIT/.kit-rev" 2>/dev/null || true
	fi
elif [ "${FORCE:-0}" != "1" ] && [ -n "$rev" ] && [ -f "$DIR/1-main/.kit-rev" ] \
	&& [ "$(cat "$DIR/1-main/.kit-rev" 2>/dev/null)" = "$rev" ]; then
	echo "  → 已是最新（$(echo "$rev" | cut -c1-8)），跳过整包下载"
else
	info "拉整包 $REPO@$BRANCH → $DIR/1-main"
	TAR_DOWNLOADED=1
	curl $CURL_K -L --fail --progress-bar --max-time 600 "$TAR" -o "$TARBALL" || die "整包下载失败（HTTP 错误或网络中断）"
	tar tzf "$TARBALL" >/dev/null 2>&1 || die "整包不是有效的 tar.gz（可能是错误页或下载不完整），未改动 $DIR/1-main"
	rm -rf "$DIR/1-main"
	tar xzf "$TARBALL" -C "$DIR" || die "解压失败"
	rm -f "$TARBALL"
	echo "  → $DIR/1-main   $(du -sh "$DIR/1-main" 2>/dev/null | cut -f1)"
	verify_kit
	if [ -n "$rev" ]; then printf '%s\n' "$rev" > "$DIR/1-main/.kit-rev"; fi
fi

# 部署常用入口，之后直接 ccc / sh pull.sh 就能用
[ -f "$KIT/pull.sh" ] && cp "$KIT/pull.sh" "$DIR/pull.sh" && chmod +x "$DIR/pull.sh" && echo "  → $DIR/pull.sh"
[ -f "$KIT/status.sh" ] && cp "$KIT/status.sh" "$DIR/status.sh" && chmod +x "$DIR/status.sh" && echo "  → $DIR/status.sh"
[ -f "$KIT/run-upload.sh" ] && cp "$KIT/run-upload.sh" "$DIR/run-upload.sh" && chmod +x "$DIR/run-upload.sh" && echo "  → $DIR/run-upload.sh   上传包一键解压运行"
if [ "${SKIP_CCC:-0}" != "1" ] && [ -d /usr/local/bin ] && [ -f "$DIR/status.sh" ]; then
	if [ -f "$KIT/ccc.sh" ]; then
		cp "$KIT/ccc.sh" /usr/local/bin/ccc
	else
		printf '#!/usr/bin/env sh\nexec sh %s/status.sh edit "$@"\n' "$DIR" > /usr/local/bin/ccc
	fi
	chmod +x /usr/local/bin/ccc
	echo "  → /usr/local/bin/ccc   输入 ccc 回车即打开面板"
fi

[ "$menu" = "1" ] || exit 0

info "进入安装菜单"
cd "$KIT/parso" || die "整包里没有 parso/"
exec sh builds.sh
