# xray-deploy

把第三方 parso 一键安装套件（xray / cns / amy4 / tinyproxy）复刻成"文件全部来自本仓库"的安装器，外加一个查看 + 修改一体的运维面板。

## 上手三件套

```bash
ccc                      # 日常运维：查看 + 改配置 + 启停服务 + 安装/卸载，一个面板搞定
sh /root/pull.sh status  # 更新到最新：拉 status.sh 并重装 ccc（1 个请求，实测 0.7 秒）
sh /root/go.sh           # 新机器：拉整包 + 部署 ccc/pull.sh + 直接进安装菜单
```

三者都在仓库根目录：`ccc.sh`（面板短命令本体）、`pull.sh`（更新）、`go.sh`（一键拉取 + 安装）。

## 首次部署（空白机器）

```bash
curl -kL --no-progress-meter -H 'Accept: application/vnd.github.raw' -o /root/go.sh \
  'https://api.github.com/repos/abcc123445653/1/contents/go.sh?ref=main' && sh /root/go.sh
```

`go.sh` 依次做三件事：

1. 从 `codeload.github.com` 拉整包（约 20 MB，带进度条）解到 `/root/1-main`，覆盖旧副本；
2. 从新包里取出 `pull.sh`、`status.sh`、`ccc.sh` 装到 `/root/` 和 `/usr/local/bin/ccc`；
3. 进入 `parso/builds.sh` 的安装菜单（安装/卸载 → 选项目 → 填端口参数），与上游菜单逐字一致。

只想拉取部署、不进菜单：`sh /root/go.sh --no-menu`。

## 查看当前运行配置

```bash
curl -kL --no-progress-meter -O -H 'Accept: application/vnd.github.raw' 'https://api.github.com/repos/abcc123445653/1/contents/status.sh?ref=main' && sh status.sh
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

**增量**：远端 commit 没变就直接跳过整包下载（版本号记在 `/root/1-main/.kit-rev`，用 `git ls-remote` 查、不占 API 限额），重复执行约 1 秒（实测 0.93 秒）；要强制重下加 `--force`（`sh /root/go.sh --force`）或 `FORCE=1 sh /root/pull.sh kit`。

首次先把 `pull.sh` 取下来（之后一直用它，含自我更新）：

```bash
curl -kL --no-progress-meter -H 'Accept: application/vnd.github.raw' -o /root/pull.sh \
  'https://api.github.com/repos/abcc123445653/1/contents/pull.sh?ref=main'
```

## 目录结构

```
README.md          本说明
ccc.sh             面板短命令（安装到 /usr/local/bin/ccc）
pull.sh            拉取最新（整包 / 面板 / 自身）
go.sh              一键拉取 + 部署 + 进安装菜单
status.sh          查看 + 修改一体的面板脚本（v11）
SHA256SUMS         三个二进制 + 面板脚本的哈希清单，解压后自动校验
.github/workflows   CI：语法检查、哈希校验、面板冒烟
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
- 推 `main` 或打 tag 时 GitHub Actions 会跑：全部 shell 语法检查、`SHA256SUMS` 校验、面板 `printf '0\n' | sh status.sh edit` 冒烟。
- 旧版 `selfhost-kit/`（自解压离线套件、`bootstrap.sh` / `oneclick.sh` / `run.sh` / `install.sh` / `uninstall.sh`）已整体移除，入口只保留 `go.sh` / `pull.sh` / `ccc` 这一套。
- 卸载不额外问"后台运行吗"、不问安装目录，选完项目直接卸；停服务先 `systemctl stop` 再 `disable` 再删文件。

## 许可

脚本部分可自由使用。Xray-core 遵循 MIT；cns / amy4 的二进制来源与授权见上游，仓库公开分发前请自行确认授权范围。
