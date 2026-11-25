#!/bin/sh
# pull.sh — 从本仓库拉取最新文件到本机
#
#   sh pull.sh            拉整包 + 更新面板脚本 status.sh + 装好 ccc（推荐）
#   sh pull.sh status     只更新 status.sh（1 个请求，最快）
#   sh pull.sh kit        只拉整包（装/升级 parso 用）
#
# 可用环境变量覆盖：REPO=abcc123445653/1  BRANCH=main  DIR=/root
set -eu

REPO="${REPO:-abcc123445653/1}"
BRANCH="${BRANCH:-main}"
DIR="${DIR:-/root}"
RAW="https://api.github.com/repos/$REPO/contents"
TAR="https://codeload.github.com/$REPO/tar.gz/refs/heads/$BRANCH"

info() { printf '\033[44;37m %s \033[0m\n' "$*"; }
die()  { echo "错误: $*" >&2; exit 1; }

install_ccc() {
	[ -d /usr/local/bin ] || return 0
	printf '#!/bin/sh\n# ccc = 打开配置面板（查看 + 修改 + 启停）\nexec sh %s/status.sh edit "$@"\n' "$DIR" > /usr/local/bin/ccc
	chmod +x /usr/local/bin/ccc
	echo "  → /usr/local/bin/ccc   输入 ccc 回车即打开面板"
}

get_kit() {
	info "拉整包 $REPO@$BRANCH → $DIR/1-main"
	mkdir -p "$DIR"
	curl -kL --progress-bar --max-time 600 "$TAR" -o "$DIR/repo.tar.gz" || die "整包下载失败"
	rm -rf "$DIR/1-main"
	tar xzf "$DIR/repo.tar.gz" -C "$DIR" || die "解压失败"
	rm -f "$DIR/repo.tar.gz"
	echo "  → $DIR/1-main   $(du -sh "$DIR/1-main" 2>/dev/null | cut -f1)"
}

get_status() {
	info "更新面板脚本 status.sh"
	mkdir -p "$DIR"
	rm -f "$DIR/status.sh.new"
	curl -kL --no-progress-meter --max-time 90 -H 'Accept: application/vnd.github.raw' \
		-o "$DIR/status.sh.new" "$RAW/status.sh?ref=$BRANCH" >/dev/null 2>&1 || true
	if [ ! -s "$DIR/status.sh.new" ] || ! grep -q 'PARSO_EDIT' "$DIR/status.sh.new" 2>/dev/null; then
		rm -f "$DIR/status.sh.new"
		echo "  接口取不到（可能限额），改从整包取"
		get_kit
		[ -f "$DIR/1-main/status.sh" ] || die "整包里没有 status.sh"
		cp "$DIR/1-main/status.sh" "$DIR/status.sh.new"
	fi
	mv "$DIR/status.sh.new" "$DIR/status.sh"
	chmod +x "$DIR/status.sh"
	install_ccc
	ver=$(grep -o '"v[0-9][0-9]*[^"]*"' "$DIR/status.sh" | head -1 | tr -d '"')
	echo "  → $DIR/status.sh   版本 ${ver:-未知}"
}

case "${1:-all}" in
status) get_status ;;
kit)    get_kit ;;
all|"") get_kit; get_status ;;
-h|--help|help)
	sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//' ;;
*)
	echo "用法: sh pull.sh [status|kit]" >&2
	exit 2 ;;
esac
