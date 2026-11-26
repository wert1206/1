# xray-deploy

把第三方 parso 一键安装套件（xray / cns / amy4 / tinyproxy）复刻成"文件全部来自本仓库"的安装器，外加一个查看 + 修改一体的运维面板。

## 运行依赖

Debian 12 最小系统上先装三样（面板强依赖 python3，拉取用 git，下载用 curl）：

```bash
apt-get update && apt-get install -y curl git python3
```

## 上手三件套

```bash
ccc                      # 日常运维：查看 + 改配置 + 启停服务 + 安装/卸载，一个面板搞定
sh /root/pull.sh status  # 更新到最新：拉 status.sh 并重装 ccc（1 个请求，实测 0.7 秒）
sh /root/go.sh           # 新机器：拉整包 + 部署 ccc/pull.sh + 直接进安装菜单
```

仓库根目录有四个入口：`ccc.sh`（面板短命令本体）、`pull.sh`（更新）、`go.sh`（一键拉取 + 安装）、`run-upload.sh`（上传压缩包后一键解压运行）。

token 只需配一次（见「配置 GitHub token」），之后上面这些命令**都不用带 token**。

## 首次部署（空白机器）

```bash
curl -L --fail --no-progress-meter -H 'Accept: application/vnd.github.raw' -o /root/go.sh \
  'https://api.github.com/repos/abcc123445653/1/contents/go.sh?ref=main' && sh /root/go.sh
```

`go.sh` 依次做三件事：

1. 从 `codeload.github.com` 拉整包（约 20 MB，带进度条）解到 `/root/1-main`，覆盖旧副本；
2. 从新包里取出 `pull.sh`、`status.sh`、`run-upload.sh` 装到 `/root/`，`ccc.sh` 装到 `/usr/local/bin/ccc`；
3. 进入 `parso/builds.sh` 的安装菜单（安装/卸载 → 选项目 → 填端口参数），与上游菜单逐字一致。

只想拉取部署、不进菜单：`sh /root/go.sh --no-menu`。

### 直接上传压缩包（不走 GitHub）

在能上网的机器上从 GitHub 下整包（Code → Download ZIP，或 codeload 的 tar.gz），传到服务器：

```bash
scp 1-main.tar.gz root@<服务器IP>:/root/
```

服务器上一条命令即可（`run-upload.sh` 是更短的入口，会自动挑 `/root` 下最新的压缩包）：

```bash
sh /root/run-upload.sh                 # 自动选最新包 → 解压 + 校验 + 部署 + 进安装菜单
sh /root/run-upload.sh --no-menu       # 自动选最新包，只部署不进菜单
sh /root/run-upload.sh /root/1-main.zip # 指定压缩包

# 也可以直接用 go.sh（效果相同）
sh /root/go.sh /root/1-main.tar.gz
sh /root/go.sh /root/1-main.tar.gz --no-menu
```

自动模式按修改时间取最新的 `.tar.gz` / `.tgz` / `.zip`（跳过 `repo.tar.gz`）；`/root` 里有多个旧包时，建议指定文件名或先删旧的。

支持 `.tar.gz` / `.tgz` / `.tar` / `.zip`（zip 用 python3 解，不需要装 unzip）。

流程：解到临时目录 → 找到含 `go.sh` + `parso/builds.sh` + `status.sh` 的那层 → 替换 `/root/1-main` → 校验 `SHA256SUMS` → 部署 `pull.sh`/`status.sh`/`run-upload.sh`/`ccc` → 运行包里自带的 `go.sh`。**全程不访问 GitHub、不占 API 额度。**

注意：上传包模式不查远端版本，所以下次在线跑 `sh /root/go.sh` 时会重新拉一次整包并刷新 `.kit-rev`；这之后又恢复增量跳过。

### 在本地机器上试跑（不写 /root、不装服务）

压缩包在你自己电脑上（Linux / macOS / WSL）时，可以只做部署试跑：

```bash
tar xzf 1-main.tar.gz && cd 1-main
DIR="$PWD/.local-run" SKIP_CCC=1 sh go.sh --no-menu
```

产物在 `.local-run/`（`pull.sh`、`status.sh` 等），不会写 `/root`、不会装 `ccc`、不会动系统服务。xray / cns / amy4 的安装依赖 **root + systemd**，macOS 或手机本地只能这样试跑。

### 不占 API 额度的引导（额度用完 / 不想用 api.github.com）

```bash
rm -rf /root/1-main && curl -L --fail https://codeload.github.com/abcc123445653/1/tar.gz/refs/heads/main \
  | tar xz -C /root && sh /root/1-main/go.sh --no-menu
```

整包直接从 `codeload.github.com` 解到 `/root/1-main`，`go.sh` 发现自己就在整包里，跳过联网下载，**全程 0 次 `api.github.com` 请求**；之后 `ccc`、`sh /root/pull.sh status` 照常用。想直接进安装菜单就去掉 `--no-menu`。

## 查看当前运行配置

```bash
curl -L --fail --no-progress-meter -H 'Accept: application/vnd.github.raw' \
  -o /root/status.sh 'https://api.github.com/repos/abcc123445653/1/contents/status.sh?ref=main' \
  && sh /root/status.sh
```

已经解压过整包的，直接跑本地：`sh 1-main/status.sh`。

打印内容：各服务是否在跑 / 是否开机自启 / 监听端口 / PID；xray 每个入站的协议、UUID、可直接导入的 vmess/vless/trojan 分享链接；cns 的端口、TLS 端口、加密密码、代理头域；amy4 的端口与 ClientKey；tinyproxy 的端口与认证。公网 IP 用外部探针取，服务器在 NAT 后面也能生成正确链接。顶部有"脚本版本"一行，用来确认跑的是不是最新版。

## 改端口 / 改密码：ccc 面板

```bash
ccc            # 等价于 sh /root/status.sh edit
```

面板先打印整屏配置，再进菜单；每一项右侧直接显示该服务当前状态（`● 运行中 :端口` / `○ 未运行` / `— 未安装`），每次回到菜单都重新查一遍：

```
 修改配置

   可修改项目（右侧为当前状态）：
   1. xray（协议/端口/UUID）  ● 运行中 :80
   2. cns（端口/密码/TLS）    ○ 未运行
   3. amy4（端口/ClientKey）  ○ 未运行
   4. tinyproxy（端口/认证）  — 未安装
   5. 停止服务（关自启）  6. 启动服务（开自启）
   7. 查看当前配置        8. 安装服务
   9. 卸载服务            0. 关闭
```

- `1`–`4` 改配置：xray 改每个入站的端口/UUID（输入 `-` 随机新 UUID），可整套重选协议（1 tcp http / 2 tcp tls / 3 tcp reality / 4 ws / 5 ws tls / 6 ws tls(vless) / 7 mkcp / 8 mkcp tls / 9 mkcp tls(vless) / 10 trojan tls，多选，回车沿用原端口，TLS 自签证书和 reality 密钥用 xray 现场生成）；cns 改端口/TLS 端口（`0` 关 TLS）/加密密码（`-` 清空）/代理头域；amy4 改端口/ClientKey（`-` 清空）/IPv6；tinyproxy 改端口和 BasicAuth（Debian 12 语法 `BasicAuth 用户 密码`）。
- `5`/`6` 停止/启动，同时 `systemctl disable`/`enable` 开关开机自启，先选服务编号再回车。
- `7` 原地重打印整屏；`8`/`9` 直接进安装器的项目菜单（1 tinyproxy / 2 cns / 3 xray / 4 amy4），不用回答"安装还是卸载"；本机没有 `parso/builds.sh` 时先自动拉整包。
- `0` 关闭退出，什么都不改。

改前自动备份（`/usr/local/xxx/xxx.json.bak-YYYYMMDD-HHMMSS`，每个配置文件只留最近 5 份），改完重启并确认新端口在监听，失败自动回滚；端口被别的进程占用会直接拦下。

每次打开面板、改配置、启停服务、进安装/卸载菜单，都会追加一行到 `/var/log/xray-panel.log`（超过 1 MB 自动改名为 `.log.1`）（时间、用户、改了什么，形如 `2026-11-25 23:33:03 [root] xray: vmess:80 / UUID 552e6fa0 → vmess:8443 / UUID 552e6fa0`），事后能查“谁在什么时候把端口改成多少”。

## 拉取最新（pull.sh）

```bash
sh /root/pull.sh          # 拉整包到 /root/1-main + 更新面板脚本 + 顺手装好 ccc
sh /root/pull.sh status   # 只更新面板脚本 status.sh（1 个请求，实测 0.7 秒）
sh /root/pull.sh kit      # 只拉整包（装 / 升级 parso 用，带进度条）
sh /root/pull.sh self     # 只把 pull.sh 自身更新成仓库最新版
```

整包走 `codeload.github.com`，不经过 `api.github.com`，不会被 60 次/小时限额卡住；`status` 只取一个文件，限额基本碰不到。接口取不到时 `status` 会自动改从整包里取，不会中断。

**增量**：远端 commit 没变就直接跳过整包下载（版本号记在 `/root/1-main/.kit-rev`，用 `git ls-remote` 查、不占 API 限额），重复执行通常不到 1 秒（实测 0.93 秒；Git 端点卡住时最多 5 秒后回退 API）；要强制重下加 `--force`（`sh /root/go.sh --force`）或 `FORCE=1 sh /root/pull.sh kit`。

**限额**：匿名 60 次/小时/IP；配只读 token 后 5000 次/小时。配置方法见下一节，**不要把 token 直接写进命令行**——会留在 shell 历史、`ps` 输出和终端记录里。脚本按 `GH_TOKEN` → `/root/.gh_token` 的顺序自动取，所以配一次之后命令保持清爽：

```bash
sh /root/go.sh --no-menu      # 不带 token，脚本自己读 /root/.gh_token
sh /root/pull.sh status
```

当前额度随时可查（脱敏显示 + limit / remaining）：`sh /root/token.sh --show`。

首次先把 `pull.sh` 取下来（之后一直用它，含自我更新）：

```bash
curl -L --fail --no-progress-meter -H 'Accept: application/vnd.github.raw' -o /root/pull.sh \
  'https://api.github.com/repos/abcc123445653/1/contents/pull.sh?ref=main'
```

## 配置 GitHub token（可选）

脚本默认匿名跑（60 次/小时/IP），日常够用。要把额度提到 5000 次/小时，用 `token.sh` 把**只读** token 存到本机（token 本身不进仓库，仓库只放脚本）：

**怎么申请**（GitHub 网页，1 分钟）：

1. 打开 <https://github.com/settings/personal-access-tokens/new>（Fine-grained token）；
2. Token name 随意（如 `server-read`），Expiration 选 90 天；
3. Repository access → Only select repositories → 只选 `abcc123445653/1`；
4. Permissions → Repository permissions → **Contents: Read-only**，其余全部 `No access`；
5. Generate token，复制 `github_pat_…`，粘进下面的 `sh token.sh` 回车。

只读就够：写操作（建 Release、传资产）用临时授权的 classic token，用完即撤。

```bash
sh token.sh                 # 粘贴 token 回车（终端不回显、不进 shell 历史），存到 /root/.gh_token（600）
sh token.sh --show          # 查看是否已配置（脱敏）与当前额度
sh token.sh --clear         # 清除 token
sh token.sh ghp_xxx --bashrc   # 顺便写进 /root/.bashrc 的 export GH_TOKEN
```

`pull.sh` / `go.sh` / `parso/builds.sh` 启动时按这个顺序取 token：环境变量 `GH_TOKEN` → `/root/.gh_token`，所以配一次之后 cron、非交互 shell 都能用。token 只用 `Contents: Read` 就够；写操作（建 Release、传资产）另行临时授权。

存好之后，所有命令都不需要再带 token：

```bash
sh /root/go.sh              # 直接用
sh /root/pull.sh status
```

不要把 token 内联在命令行里（`GH_TOKEN=github_pat_… sh …`）：会留在 `~/.bash_history` 和 `ps` 输出里，换机器、截图、共享终端时容易外泄。确实要临时内联，命令前加一个空格（配合 `HISTCONTROL=ignorespace`），或跑完 `history -d` 删掉那条。

## 目录结构

```
README.md          本说明
LICENSE            原创脚本与文档的 MIT 许可
NOTICE             第三方组件（parso/ 二进制）授权说明
.gitattributes     强制 LF，防止 CRLF 弄坏 #!/bin/sh
pull.sh            拉取最新（整包 / 面板 / 自身）
go.sh              一键拉取 + 部署 + 进安装菜单
run-upload.sh      上传压缩包后的一键入口（自动选最新包）
status.sh          查看 + 修改一体的面板脚本（v12）
token.sh           存 / 查 / 清 GitHub token（只落本机 /root/.gh_token）
SHA256SUMS         三个二进制（xray / cns / amy4）的哈希清单，解压后自动校验
.github/workflows   CI：语法检查、哈希校验、部署/上传包/面板冒烟
parso/             安装器本体，与上游目录结构一致，二进制随仓库分发
  builds.sh        安装 / 卸载菜单
  xray/            xray.sh、xray.init、xray.service、linux_amd64
  cns/             cns.sh、cns.init、cns.service、linux_amd64
  amy4/            amy4.sh、amy4.init、amy4.service、linux_amd64
  tinyproxy/       tinyproxy.sh
vendor-scripts/    上游原版脚本留档（只作对照，不参与安装）
```

## 来源与约束

- 所有脚本、init、service、二进制都来自本仓库；`parso/builds.sh` 发现同目录有 `xray/xray.sh` 和 `xray/linux_amd64` 时把下载源切成 `file://` 本地路径，安装过程中 0 次网络请求、0 次第三方中转。
- 整包约 19 MB，一次拉完；`go.sh` / `pull.sh` 解压后自动 `sha256sum -c SHA256SUMS`，二进制哈希不符直接中止。早期那条 `aka.doubaocdn.com` 临时 CDN 已过期，全部引用已删除。
- 顶级脚本（`go.sh` / `pull.sh` / `token.sh` / `status.sh`）默认**校验证书**，不再用 `curl -k`；只有证书异常的老机器才加 `INSECURE=1`（等价 `curl -k`）。`parso/` 内为保持与上游一致仍保留 `-k`，但本地 `file://` 模式安装时不联网。
- 推 `main` 或打 tag 时 GitHub Actions 会跑：全部 shell 语法检查、`shellcheck -S error`、`SHA256SUMS` 校验、面板 `printf '0\n' | sh status.sh edit` 冒烟、`DIR=临时目录 SKIP_CCC=1 sh go.sh --no-menu` 的部署冒烟，以及 `run-upload.sh` 自动选包 + 解压运行的冒烟。
- 旧版 `selfhost-kit/`（自解压离线套件、`bootstrap.sh` / `oneclick.sh` / `run.sh` / `install.sh` / `uninstall.sh`）已整体移除，入口只保留 `go.sh` / `pull.sh` / `run-upload.sh` / `ccc` 这一套。
- 卸载不额外问"后台运行吗"、不问安装目录，选完项目直接卸；停服务先 `systemctl stop` 再 `disable` 再删文件。

## 许可

原创脚本与文档采用 MIT 许可，见 [LICENSE](LICENSE)；`parso/` 下第三方二进制的授权说明见 [NOTICE](NOTICE)。Xray-core 遵循 MIT；cns / amy4 的二进制来源与授权见上游，仓库公开分发前请自行确认授权范围。
