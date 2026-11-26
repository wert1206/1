#!/bin/sh
# run-upload.sh — 上传压缩包后的一键入口：自动解压 → 校验 → 部署 → 运行
#
#   sh run-upload.sh /root/1-main.tar.gz   指定压缩包
#   sh run-upload.sh                       自动选 /root 下最新的 .tar.gz / .tgz / .zip
#   sh run-upload.sh --no-menu             自动选，但不进安装菜单
#
# 支持 .tar.gz / .tgz / .tar / .zip；解压、校验、部署交给同目录的 go.sh。
set -eu

DIR="${DIR:-/root}"

usage() {
	cat <<'EOF'
run-upload.sh — 上传压缩包后的一键解压运行

  sh run-upload.sh <压缩包>   指定 /root 下的 .tar.gz / .tgz / .tar / .zip
  sh run-upload.sh            自动选 /root 下最新的压缩包
  sh run-upload.sh --no-menu  自动选，但不进安装菜单

实际解压、SHA256 校验、部署与运行由同目录的 go.sh 完成。
EOF
}

MENU=""
case "${1:-}" in
-h|--help) usage; exit 0 ;;
--no-menu) MENU="--no-menu"; shift ;;
esac

PKG="${1:-}"
if [ -z "$PKG" ]; then
	PKG=$(ls -t "$DIR"/*.tar.gz "$DIR"/*.tgz "$DIR"/*.zip 2>/dev/null \
		| grep -v '/repo.tar.gz' | head -1 || true)
	if [ -z "$PKG" ]; then
		echo "错误：$DIR 下没找到 .tar.gz / .tgz / .zip，先把压缩包上传上来" >&2
		exit 2
	fi
	echo "  → 自动选择压缩包：$PKG"
fi

[ -f "$PKG" ] || { echo "错误：压缩包不存在: $PKG" >&2; exit 2; }
[ -f "$DIR/go.sh" ] || {
	echo "错误：找不到 $DIR/go.sh" >&2
	echo "先按 README「首次部署」把 go.sh 拉下来，或直接用：sh $DIR/go.sh $PKG" >&2
	exit 2
}

exec sh "$DIR/go.sh" "$PKG" $MENU
