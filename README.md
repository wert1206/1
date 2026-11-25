# xray-deploy

本仓库含两套东西：`selfhost-kit/`（xray + cns + amy4 的离线套件，带上游同款交互菜单）和根目录的 `xray-deploy` 脚本。**来源固定、哈希校验、失败即中止。**

## 一条命令（交互式，推荐）

```bash
curl -kL https://aka.doubaocdn.com/s/bRKMFv5It6 -o builds.sh && sudo sh builds.sh
```

`builds.sh` 是自解压入口：发现同目录没有 `bin/` 时，自己下载 19 MB 整包、校验 SHA-256、解压到临时目录，再进入与上游完全相同的菜单（安装/卸载 → 选 `1`-`4` → 逐个问答）。装完清掉临时目录。

不想回答任何问题：

```bash
curl -kL https://aka.doubaocdn.com/s/D5CpJrxXxA -o run.sh && sudo sh run.sh
```

默认装 `xray:443`(tcp http) + `cns:80` + `amy4:18443`，凭据随机生成，结束打印服务状态表与客户端参数。

看状态、端口、当前凭据（不重装）：

```bash
sh run.sh status
```

改端口、密码而保留其他凭据：

```bash
sh run.sh --xray-port 8443 --cns-password 新密码 --keep
```

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
