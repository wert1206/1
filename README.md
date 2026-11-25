# xray-deploy

## 查看当前运行配置（不重装、不下载整包）

```bash
curl -kL --no-progress-meter -O -H 'Accept: application/vnd.github.raw' 'https://api.github.com/repos/abcc123445653/1/contents/status.sh?ref=main' && sh status.sh
```

如果之前已经解压过整包（`1-main/`），直接跑本地的：

```bash
sh 1-main/status.sh
```

会打印：各服务是否在跑 / 是否开机自启 / 监听端口 / PID；xray 每个入站的协议类型、UUID、可直接导入的 vmess/vless/trojan 分享链接；cns 的端口、TLS 端口、加密密码；amy4 的端口与 ClientKey；tinyproxy 的端口与认证。公网 IP 用外部探针取，服务器在 NAT 后面（本机只有 172.x）也能生成正确的链接。

## 改端口 / 改密码（同一屏里先看后改）

```bash
sh status.sh edit
```

嫌长可以装个短命令 `ccc`（在服务器上执行一次，之后直接输 `ccc` 回车即可）：

```bash
printf '#!/bin/sh\nexec sh /root/status.sh edit "$@"\n' > /usr/local/bin/ccc && chmod +x /usr/local/bin/ccc
```

先打印上面那整屏配置，再进入修改：xray 可改每个入站的端口和 UUID（输入 `-` 随机生成新 UUID）；cns 可改 TCP 端口、TLS 端口（输入 `0` 关闭 TLS）、加密密码（输入 `-` 清空）、代理头域；amy4 可改端口、ClientKey（输入 `-` 清空）、IPv6 开关。xray 还能重选协议组合：1 tcp http / 2 tcp tls / 3 tcp reality / 4 websocket / 5 websocket tls / 6 websocket tls(vless) / 7 mkcp / 8 mkcp tls / 9 mkcp tls(vless) / 10 trojan tls，可多选，回车沿用原来的端口，TLS 自签证书和 reality 密钥用 xray 二进制现场生成；tinyproxy 用第 4 项改端口和 BasicAuth 用户名密码（新版 tinyproxy 语法是 `BasicAuth user pass`）。

菜单里还有：`5` 停止服务（同时 `systemctl disable` 关掉开机自启）、`6` 启动服务（同时 `systemctl enable` 打开开机自启）、`7` 查看当前配置（原地重打印整屏）、`8` 安装服务、`9` 卸载服务、`0` 关闭退出（什么都不改）；都是先输入编号再回车，可一次输入多个服务编号，回车取消。停止只是停进程，配置和文件都保留，`6` 随时能拉起来。

`8`/`9` 会直接进入安装器的项目菜单（1 tinyproxy / 2 cns / 3 xray / 4 amy4），选项目回车就装/卸，不用再回答“安装还是卸载”；本机若还没有 `parso/builds.sh`，会先自动拉整包再进菜单。

改完自动带时间戳备份原配置（`/usr/local/xxx/xxx.json.bak-YYYYMMDD-HHMMSS`）、重启对应服务并确认新端口确实在监听，最后刷新整屏显示新的分享链接。端口被别的进程占用会直接拦下来不让改。

## 拉取最新（pull.sh）

`pull.sh` 就是“从本仓库拉东西”的统一入口，三种用法：

```bash
sh /root/pull.sh          # 拉整包到 /root/1-main + 更新面板脚本 + 顺手装好 ccc
sh /root/pull.sh status   # 只更新面板脚本 status.sh（1 个请求，实测 0.7 秒）
sh /root/pull.sh kit      # 只拉整包（装 / 升级 parso 用）
sh /root/pull.sh self     # 只更新 pull.sh 自身到仓库最新版
```

第一次用先把 `pull.sh` 取下来（之后就一直用它）：

```bash
curl -kL --no-progress-meter -H 'Accept: application/vnd.github.raw' -o /root/pull.sh \
  'https://api.github.com/repos/abcc123445653/1/contents/pull.sh?ref=main' && sh /root/pull.sh
```

整包走 `codeload.github.com`（约 38 MB，解压 98 MB），不经过 `api.github.com`，不会被 60 次/小时限额卡住；`status` 模式只取一个文件，限额也几乎碰不到。拉完会把 `ccc` 重新指向最新的 `status.sh`，并打印拉到的版本号（如 `v8 · 支持 edit`）。

## 一键安装 / 卸载（与上游 parso 同款菜单，文件全部来自本仓库）

本仓库含两套东西：`parso/`（照上游目录结构的同款菜单安装器）和 `selfhost-kit/`（离线套件）。**来源固定、哈希校验、失败即中止。**

最省事的一个入口 `go.sh`：拉整包 → 部署好 `ccc` / `pull.sh` / `status.sh` → 直接进安装菜单。

```bash
curl -kL --no-progress-meter -H 'Accept: application/vnd.github.raw' -o /root/go.sh 'https://api.github.com/repos/abcc123445653/1/contents/go.sh?ref=main' && sh /root/go.sh
```

只拉取和部署、不进菜单：`sh /root/go.sh --no-menu`。

不用 `go.sh` 的等价写法（拉整包后自己进目录）：

```bash
curl -kL https://codeload.github.com/abcc123445653/1/tar.gz/refs/heads/main | tar xz && cd 1-main/parso && sh builds.sh
```

菜单与上游 parso 一致：安装还是卸载 → 选项目（1 tinyproxy / 2 cns / 3 xray / 4 amy4）→ 逐项参数。整包约 38 MB 一次拉完（实测 5-6 秒），之后脚本、init、service、二进制全部从本地 `file://` 读取，不再请求 `api.github.com`，不会被 60 次/小时限额卡住，也不经过任何第三方中转。卸载不问“后台运行吗”、不问安装目录，选完直接卸。

非交互装机可用同仓库的离线套件脚本：`sh selfhost-kit/install.sh --xray-port 8443 --cns-password 新密码`。

## selfhost-kit 说明

- 组件：xray `1.8.13`、cns `0.5`、amy4 `1.7.1`（均为 x86_64 ELF，SHA-256 固定在 `selfhost-kit/MANIFEST.sha256`）
- 不含：`tinyproxy`（上游那条 URL 返回的是 70 字节跳转页，不是程序；用 `apt install tinyproxy`）
- 交互脚本：`selfhost-kit/builds.sh`，文案与上游逐字一致
- 非交互脚本：`selfhost-kit/install.sh`，支持 `--xray-mode tcp-http|tcp-tls|ws|ws-tls`

## xray-deploy 脚本

- 组件：Xray-core（XTLS 官方 Release，MIT）
- 版本：`v26.11.9`（x86_64 固定 SHA-256 已写入 `install.sh`）

## 一键安装

推荐先取回脚本再执行，不要直接管道给 `sh`：

```bash
git clone https://github.com/abcc123445653/1.git
cd 1
sudo ./install.sh --port 8443 --open-port
```

装好后脚本会直接打印客户端链接，形如：

```
vless://<uuid>@<你的IP>:8443?encryption=none&security=none&type=tcp#xray-deploy
```

启用 TLS（推荐公网使用）：

```bash
sudo ./install.sh --port 8443 --open-port \
  --tls-cert /etc/letsencrypt/live/example.com/fullchain.pem \
  --tls-key  /etc/letsencrypt/live/example.com/privkey.pem \
  --host example.com
```

## 参数

| 参数 | 说明 |
|---|---|
| `--port <端口>` | 监听端口，默认 `8443`（非特权端口，服务以 `DynamicUser` 运行，不需要 root 常驻） |
| `--host <地址>` | 生成客户端链接时使用的主机名，默认取本机第一个 IP |
| `--open-port` | 自动放行 ufw / firewalld 的对应端口 |
| `--tls-cert` / `--tls-key` | 启用 TLS，需同时提供；只做加载，不代申请证书 |

## 校验机制

`install.sh` 做了三层约束：

1. 全程 HTTPS，`curl --proto '=https' --tlsv1.2`，**不使用 `-k` / `--insecure`**。
2. 下载后计算 SHA-256，与仓库内固定值比对（x86_64）。
3. 再与同一 Release 的官方 `.dgst` 比对。

任一不符立即退出，不落盘、不启动。归档本身不进入仓库，仓库里只有脚本和校验值。

arm64 走官方 `.dgst` 比对，没有仓库固定值（避免我写入一个未经实测的数字）。

## 安装后

```bash
systemctl status xray
journalctl -u xray -f
```

配置位于 `/usr/local/xray/config.json`，UUID 在首次安装时随机生成，不使用任何默认口令。

加固项：`DynamicUser`、`NoNewPrivileges`、`ProtectSystem=strict`、`ProtectHome`、`PrivateTmp`、`RestrictAddressFamilies`。

## 卸载

```bash
sudo ./uninstall.sh --port 8443
```

停服务、删 unit、删目录，并回收防火墙规则。

## 安全边界

- **VLESS 本身不做传输加密。** 不加 `--tls-cert/--tls-key` 时，流量只在协议层封装，公网裸跑等同于明文。要么配证书，要么只在可信链路内用。
- 脚本不修改 sysctl、不写 iptables 自定义链、不下载任何二次脚本。
- 端口放行是显式行为，默认不动防火墙。

## 为什么不含 cns / amy4 / tinyproxy

那套包经字节级核对存在以下问题，不适合作为可分发内容：

| 文件 | 问题 |
|---|---|
| `tinyproxy/tinyproxy` | 70 字节 HTML，内容是跳转到 `binary.quicknet.cyou` 的脚本，不是可执行程序 |
| `tinyproxy/tinyproxy.init` | 与上者哈希完全相同 |
| `xray.sb-part-1jqqlzv-3` | 文件名含 `sb-part`，27 MB 分片且 ELF 段表偏移越界，无法运行 |
| `cns.json` / `amy4.json` | 硬编码 `123456` 口令、`ClientKey: ["443"]` |
| `builds.sh` | 明文 HTTP 取包、`curl -k` 关闭证书校验、`chmod 777` 后 root 执行 |

因此本仓库只收录能从官方渠道验证来源的这一部分。

## 许可

脚本部分可自由使用。Xray-core 遵循 MIT，许可证随归档分发至 `/usr/local/xray`。

## 从哪里拉取

`builds.sh` 的取包顺序：

1. 当前目录已有 `install.sh` + `bin/` → 直接用
2. 有 `git` 且存在部署密钥（默认 `~/.ssh/github_1`）→ `git clone` 本仓库，用仓库内 `selfhost-kit/`（`GH_REPO`、`GH_KEY` 可覆盖）
3. 两者都没有 → 回退内置压缩包地址（`KIT_URL` / `KIT_SHA`）

私有仓库的克隆依赖部署密钥，新机器上把 `github_1` 放进 `~/.ssh/` 并 `chmod 600` 即可：

    GH_KEY=/root/.ssh/github_1 sh builds.sh

克隆下来的 `bin/` 会按 `selfhost-kit/MANIFEST.sha256` 逐个校验，校验不过直接中止。
