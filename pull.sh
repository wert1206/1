#!/bin/sh
# pull.sh — 从本仓库拉取最新文件到本机（版本 v2）
#
#   sh pull.sh            拉整包 + 更新面板脚本 status.sh + 装好 ccc（推荐）
#   sh pull.sh status     只更新 status.sh（1 个请求，最快）
#   sh pull.sh kit        只拉整包（装/升级 parso 用）
#   sh pull.sh self       只把 pull.sh 自身更新成仓库最新版
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

verify_kit() {
	[ -f "$DIR/1-main/SHA256SUMS" ] || return 0
	if (cd "$DIR/1-main" && sha256sum -c SHA256SUMS >/dev/null 2>&1); then
		echo "  → 二进制校验通过（SHA256SUMS）"
	else
		die "整包校验失败：$DIR/1-main 与 SHA256SUMS 不符"
	fi
}


install_ccc() {
	[ -d /usr/local/bin ] || return 0
	src=""
	for c in "$DIR/1-main/ccc.sh" "$DIR/ccc.sh"; do
		[ -f "$c" ] && src="$c" && break
	done
	if [ -z "$src" ]; then
		curl -kL --no-progress-meter --max-time 30 -H 'Accept: application/vnd.github.raw' \
			-o /usr/local/bin/ccc "$RAW/ccc.sh?ref=$BRANCH" >/dev/null 2>&1 || true
		grep -q 'ccc' /usr/local/bin/ccc 2>/dev/null || \
			printf '#!/bin/sh\nexec sh %s/status.sh edit "$@"\n' "$DIR" > /usr/local/bin/ccc
	else
		cp "$src" /usr/local/bin/ccc
	fi
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
	verify_kit
}

get_self() {
	info "更新 pull.sh 自身"
	rm -f "$DIR/pull.sh.new"
	curl -kL --no-progress-meter --max-time 60 -H 'Accept: application/vnd.github.raw' \
		-o "$DIR/pull.sh.new" "$RAW/pull.sh?ref=$BRANCH" >/dev/null 2>&1 || true
	[ -s "$DIR/pull.sh.new" ] && grep -q 'pull.sh' "$DIR/pull.sh.new" || { rm -f "$DIR/pull.sh.new"; die "拉取 pull.sh 失败（可能限额）"; }
	mv "$DIR/pull.sh.new" "$DIR/pull.sh"
	chmod +x "$DIR/pull.sh"
	ver=$(grep -o '版本 v[0-9][0-9]*' "$DIR/pull.sh" | head -1)
	echo "  → $DIR/pull.sh   ${ver:-已更新}"
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
self)   get_self ;;
kit)    get_kit ;;
all|"") get_kit; get_status ;;
-h|--help|help)
	sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//' ;;
*)
	echo "用法: sh pull.sh [all|status|kit|self]" >&2
	exit 2 ;;
esac
