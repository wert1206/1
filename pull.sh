#!/bin/sh
# pull.sh — 从本仓库拉取最新文件到本机（版本 v3）
#
#   sh pull.sh            拉整包 + 更新面板脚本 status.sh + 装好 ccc（推荐）
#   sh pull.sh status     只更新 status.sh（1 个请求，最快）
#   sh pull.sh kit        只拉整包（装/升级 parso 用）
#   sh pull.sh self       只把 pull.sh 自身更新成仓库最新版
#   FORCE=1 sh pull.sh    远端没变也强制重新下载
#   INSECURE=1            跳过 TLS 校验（仅老机器/异常 CA 时用）
#
# 可用环境变量覆盖：REPO=abcc123445653/1  BRANCH=main  DIR=/root
set -eu

REPO="${REPO:-abcc123445653/1}"
BRANCH="${BRANCH:-main}"
DIR="${DIR:-/root}"
RAW="https://api.github.com/repos/$REPO/contents"
TAR="https://codeload.github.com/$REPO/tar.gz/refs/heads/$BRANCH"
TARBALL="$DIR/repo.tar.gz"
mkdir -p "$DIR"

CURL_K=""
if [ "${INSECURE:-0}" = "1" ]; then CURL_K="-k"; fi

# 没设 GH_TOKEN 时，尝试从 /root/.gh_token 读（cron / 非交互 shell 也能用）
if [ -z "${GH_TOKEN:-}" ] && [ -f /root/.gh_token ]; then
	GH_TOKEN=$(cat /root/.gh_token 2>/dev/null || true)
	export GH_TOKEN
fi

info() { printf '\033[44;37m %s \033[0m\n' "$*"; }
die()  { echo "错误: $*" >&2; exit 1; }

usage() {
	cat <<'EOF'
pull.sh — 从本仓库拉取最新文件（版本 v3）

  sh pull.sh            拉整包 + 更新面板脚本 status.sh + 装好 ccc（推荐）
  sh pull.sh status     只更新 status.sh（1 个请求，最快）
  sh pull.sh kit        只拉整包（装/升级 parso 用）
  sh pull.sh self       只把 pull.sh 自身更新成仓库最新版
  FORCE=1 sh pull.sh    远端没变也强制重新下载
  INSECURE=1            跳过 TLS 校验（仅老机器/异常 CA 时用）

环境变量：REPO=abcc123445653/1  BRANCH=main  DIR=/root
EOF
}

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
	[ -f "$DIR/1-main/SHA256SUMS" ] || return 0
	if (cd "$DIR/1-main" && sha256sum -c SHA256SUMS >/dev/null 2>&1); then
		echo "  → 二进制校验通过（SHA256SUMS）"
	else
		die "整包校验失败：$DIR/1-main 与 SHA256SUMS 不符"
	fi
}

cleanup() {
	if [ "${TAR_DOWNLOADED:-0}" = "1" ]; then rm -f "$TARBALL"; fi
	return 0
}
trap cleanup 0 1 2 15


api_get() { # $1=url $2=out $3=timeout
	if [ -n "${GH_TOKEN:-}" ]; then
		curl $CURL_K -L --no-progress-meter --max-time "$3" -H "Authorization: Bearer $GH_TOKEN" \
			-H 'Accept: application/vnd.github.raw' -o "$2" "$1" >/dev/null 2>&1 || true
	else
		curl $CURL_K -L --no-progress-meter --max-time "$3" -H 'Accept: application/vnd.github.raw' \
			-o "$2" "$1" >/dev/null 2>&1 || true
	fi
}

install_ccc() {
	[ "${SKIP_CCC:-0}" != "1" ] || return 0
	[ -d /usr/local/bin ] || return 0
	src=""
	for c in "$DIR/1-main/ccc.sh" "$DIR/ccc.sh"; do
		[ -f "$c" ] && src="$c" && break
	done
	if [ -z "$src" ]; then
		api_get "$RAW/ccc.sh?ref=$BRANCH" /usr/local/bin/ccc 30
		head -1 /usr/local/bin/ccc 2>/dev/null | grep -q '^#!' || \
			printf '#!/bin/sh\nexec sh %s/status.sh edit "$@"\n' "$DIR" > /usr/local/bin/ccc
	else
		cp "$src" /usr/local/bin/ccc
	fi
	chmod +x /usr/local/bin/ccc
	echo "  → /usr/local/bin/ccc   输入 ccc 回车即打开面板"
}

install_wrapper() {
	[ -f "$DIR/run-upload.sh" ] || [ -f "$DIR/1-main/run-upload.sh" ] || return 0
	if [ -f "$DIR/1-main/run-upload.sh" ]; then
		cp "$DIR/1-main/run-upload.sh" "$DIR/run-upload.sh"
	elif [ -f "$DIR/run-upload.sh" ]; then
		return 0
	fi
	chmod +x "$DIR/run-upload.sh"
	echo "  → $DIR/run-upload.sh   上传包一键解压运行"
}

get_kit() {
	mkdir -p "$DIR"
	rev=$(remote_rev || true)
	if [ "${FORCE:-0}" != "1" ] && [ -n "$rev" ] && [ -f "$DIR/1-main/.kit-rev" ] \
		&& [ "$(cat "$DIR/1-main/.kit-rev" 2>/dev/null)" = "$rev" ]; then
		echo "  → 已是最新（$(echo "$rev" | cut -c1-8)），跳过整包下载"
		return 0
	fi
	info "拉整包 $REPO@$BRANCH → $DIR/1-main"
	TAR_DOWNLOADED=1
	curl $CURL_K -L --progress-bar --max-time 600 "$TAR" -o "$TARBALL" || die "整包下载失败"
	rm -rf "$DIR/1-main"
	tar xzf "$TARBALL" -C "$DIR" || die "解压失败"
	rm -f "$TARBALL"
	echo "  → $DIR/1-main   $(du -sh "$DIR/1-main" 2>/dev/null | cut -f1)"
	verify_kit
	if [ -n "$rev" ]; then printf '%s\n' "$rev" > "$DIR/1-main/.kit-rev"; fi
	install_wrapper
}

get_self() {
	info "更新 pull.sh 自身"
	rm -f "$DIR/pull.sh.new"
	api_get "$RAW/pull.sh?ref=$BRANCH" "$DIR/pull.sh.new" 60
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
	api_get "$RAW/status.sh?ref=$BRANCH" "$DIR/status.sh.new" 90
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
	install_wrapper
	ver=$(grep -o '"v[0-9][0-9]*[^"]*"' "$DIR/status.sh" | head -1 | tr -d '"')
	echo "  → $DIR/status.sh   版本 ${ver:-未知}"
}

case "${1:-all}" in
status) get_status ;;
self)   get_self ;;
kit)    get_kit ;;
all|"") get_kit; get_status ;;
-h|--help|help)
	usage ;;
*)
	echo "用法: sh pull.sh [all|status|kit|self]" >&2
	exit 2 ;;
esac
