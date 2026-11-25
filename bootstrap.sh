#!/bin/sh
# bootstrap.sh — 不依赖 git 的安装入口
#
# 直接取套件压缩包 → 校验 SHA-256 → 解压 → 安装。
# 只用 curl（或 wget）+ tar + sha256sum，全部是 Debian/Ubuntu 自带组件。
#
# 用法：
#   curl -fsSL <本脚本地址> | sudo sh -s -- --xray-port 443
#   或落盘后执行：sudo sh bootstrap.sh --dry-run
#
set -eu

KIT_URL="${KIT_URL:-https://aka.doubaocdn.com/s/hoQcKwnetc}"
KIT_SHA="${KIT_SHA:-e86b3a4f107ac06cfcc930dcaae93d41d09d83db95e1f84bf20ddd408b63bf73}"

die() { echo "错误: $*" >&2; exit 1; }

# 已在套件目录里，直接交给 install.sh
SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd || echo "")
if [ -n "$SELF_DIR" ] && [ -f "$SELF_DIR/selfhost-kit/install.sh" ]; then
	exec sh "$SELF_DIR/selfhost-kit/install.sh" "$@"
fi
if [ -n "$SELF_DIR" ] && [ -f "$SELF_DIR/install.sh" ] && [ -d "$SELF_DIR/bin" ]; then
	exec sh "$SELF_DIR/install.sh" "$@"
fi

command -v tar >/dev/null 2>&1 || die "缺少 tar"
command -v sha256sum >/dev/null 2>&1 || die "缺少 sha256sum"

fetch() {
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL --proto '=https' --tlsv1.2 "$1" -o "$2"
	elif command -v wget >/dev/null 2>&1; then
		wget -q --https-only "$1" -O "$2"
	else
		die "缺少 curl / wget"
	fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

echo "==> 下载套件（约 19 MB）"
fetch "$KIT_URL" "$TMP/kit.tar.gz" || die "下载失败: $KIT_URL"

echo "==> 校验 SHA-256"
printf '%s  %s\n' "$KIT_SHA" "$TMP/kit.tar.gz" | sha256sum -c - >/dev/null 2>&1 \
	|| die "校验失败，压缩包不完整或被替换（期望 $KIT_SHA）"

echo "==> 解压"
tar xzf "$TMP/kit.tar.gz" -C "$TMP"
[ -f "$TMP/selfhost-kit/install.sh" ] || die "包结构异常"

exec sh "$TMP/selfhost-kit/install.sh" "$@"
