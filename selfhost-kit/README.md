# selfhost-kit

三个组件的**完全离线**安装套件。不联网、不 `curl`、不下载二级脚本，只装 `bin/` 下经校验的二进制。

## 内容与来源

| 文件 | 大小 | SHA-256 | 版本标识 |
|---|---|---|---|
| `bin/xray` | 28,147,864 | `cc030e752b216a95b9ba2303e741779fd62532d9b45614c5368a3a6e75fdcc89` | `Xray 1.8.13 ... Custom (go1.22.3 linux/amd64)` |
| `bin/cns` | 4,046,848 | `61d7f2b36c7e65e4e1be92e2cd0e280c1fb8f39704b9463604229419f13bc30d` | `CuteBi Network Server 0.5` |
| `bin/amy4` | 18,591,870 | `32ede2eaebf6bfc4865332be84e956efd1339ce8016ad5d8ac6e658efaf6e292` | `amy4Client 1.7.1` |

三个文件均从你自己的服务器 `47.111.156.207:/usr/local/{xray,cns,amy4}/` 原样取回，`file` 均为 `ELF 64-bit LSB executable, x86-64, statically linked`。哈希即上表，`install.sh` 启动时会用 `sha256sum -c MANIFEST.sha256` 重新比对，不符即中止。

`xray` 是 **1.8.13 的自编译版本**（构建元数据为 `Custom`），不是官方 Release 的产物。哈希只能证明「就是你服务器上那一个」，不能证明它没有改动。

## 一键入口

仓库根目录有 `oneclick.sh`，两种情况都能用：

```bash
# 一、已经在仓库里
sudo ./oneclick.sh --xray-port 443 --cns-port 80 --amy4-port 18443

# 二、手上只有这一个脚本（自动克隆私有仓库再安装）
sudo sh oneclick.sh
```

参数原样透传给 `selfhost-kit/install.sh`。第二条要求本机已配置能读这个私有仓库的 SSH 密钥；想换仓库地址用 `REPO_URL=...` 覆盖。

## 交互式菜单（builds.sh）

保留了上游 `builds.sh` 的菜单结构：先选安装／卸载，再选项目（`1` tinyproxy / `2` cns / `3` xray / `4` amy4），然后逐个问端口和密码。

```bash
sudo ./builds.sh              # 交互
sudo ./builds.sh --dry-run    # 只生成配置并自检，不动系统
```

与上游的差异：

| 项 | 上游 | 本套件 |
|---|---|---|
| 文件来源 | 运行时从 binary.parso.org 下载 | 本目录 `bin/`，不联网 |
| tinyproxy | 可装 | **不可用**，上游源返回 70 字节跳转页，引导用 `apt install tinyproxy` |
| 只选了不可用组件 | 直接退出 | 提示后回到项目选择，回车默认 `2 3 4`；连续 3 次空选才退出 |
| xray 入站 | 10 种 | 支持 `1` tcp http、`2` tcp tls、`4` ws、`5` ws tls；reality / vless ws / mkcp / trojan 暂不支持 |
| UPX | 可选 | 无（本地已是最终二进制） |
| 安装目录 | 可自定义 | 固定 `/usr/local/<组件>` |
| cns tls 端口 | 可选 | 未启用 |

xray `2` / `5` 需要 TLS，若未提供证书则用 `openssl` 生成自签证书放在 `/usr/local/xray/{cert,key}.pem`。

## 安装

`bin/` 已随本仓库提交（仓库为私有）。装之前先自己验一遍：

```bash
sha256sum -c MANIFEST.sha256     # 三个文件逐个比对
sudo ./install.sh                # 默认 xray:443, cns:80, amy4:18443
```

常用参数：

```bash
sudo ./install.sh --dry-run                      # 只校验+生成配置，不写系统
sudo ./install.sh --components xray,cns          # 只装部分
sudo ./install.sh --xray-port 443 --cns-port 80 --amy4-port 18443
sudo ./install.sh --components xray --xray-port 8443
```

`--dry-run` 会把配置生成到临时目录并跑 `xray run -test` 自检，不碰 `/usr/local` 和 systemd。

## 端口与冲突

| 组件 | 默认端口 | 说明 |
|---|---|---|
| xray | 443 | VMess + TCP + HTTP 头域，与你原机 `xray.json` 同构 |
| cns | 80 | 原机即监听 `:80` |
| amy4 | 18443 | **原机 amy4 也配的 443，但 443 被 xray 占着，实际没起来**。这里默认改到 18443 避免冲突 |

装完自查：

```bash
ss -lntp | grep -E ':443|:80|:18443'
systemctl status xray cns amy4
```

## 凭据

安装时随机生成，不再使用原机的 `Encrypt_password: 123456`、固定 UUID、固定 `ClientKeys: ["443"]`。每次安装的值会打印出来，请自行记录。

## 关于 tinyproxy

**没有包含。** 你服务器上 `/usr/local/tinyproxy/tinyproxy` 就是 70 字节的 HTML：

```
<script>window.location.href = "https://binary.quicknet.cyou"</script>
```

即它自己的下载渠道返回的是跳转页而非二进制，这个组件在你机上从未真正装上。需要 HTTP 代理请走系统包：

```bash
apt install tinyproxy && systemctl enable --now tinyproxy
```

## 卸载

```bash
sudo ./uninstall.sh                      # 全卸
sudo ./uninstall.sh --components xray    # 只卸一个
```

停服务、删 unit、删 `/usr/local/<组件>`。

## 边界

- 三个二进制是第三方产物，其中 `amy4` 为闭源。哈希证明的是「同一份字节」，不是「安全」。**建议只在自己的私有环境使用，不要公开分发。**
- `cns` 的 `Proxy_key` 默认沿用 `Meng`，需要改就加 `--cns-key`。
- 本套件不做防火墙操作，端口放行请自行处理。
