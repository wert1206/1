# 来源与第三方组件清单

本文件记录仓库里第三方组件的来源、版本、SHA-256、许可与再分发状态，供公开分发前核对。记录时间：2026-11-26。

## 1. 组件清单

| 组件 | 仓库路径 | 版本 / 识别结果 | 大小（字节） | SHA-256 | 上游地址 | 许可 | 再分发状态 |
|---|---|---|---|---|---|---|---|---|
| Xray-core | `parso/xray/linux_amd64` | Xray 1.8.13 **Custom**（go1.22.3 linux/amd64） | 28,147,864 | `cc030e752b216a95b9ba2303e741779fd62532d9b45614c5368a3a6e75fdcc89` | <https://github.com/XTLS/Xray-core> | MPL-2.0 | 允许再分发，但须保留 MPL-2.0 文本、注明修改，并提供源码获取方式。当前是 Custom 构建，无法对应到官方 release 的字节或具体 commit。 |
| CNS | `parso/cns/linux_amd64` | CuteBi Network Server 0.5（go1.17.2） | 4,046,848 | `61d7f2b36c7e65e4e1be92e2cd0e280c1fb8f39704b9463604229419f13bc30d` | <https://github.com/mmmdbybyd/CNS> | **上游仓库未附 LICENSE**（截至 2026-11-26，仓库文件列表中没有 LICENSE） | 没有明确的再分发授权。公开仓库分发前应取得作者书面许可，或从仓库中移除该二进制。 |
| amy4 | `parso/amy4/linux_amd64` | amy4Client 1.7.1（闭源 Go 程序，内含 xtls/xray-core 相关包） | 18,591,870 | `32ede2eaebf6bfc4865332be84e956efd1339ce8016ad5d8ac6e658efaf6e292` | 未找到可核验的公开仓库或官网 | **闭源，未找到任何许可证声明** | 未授权公开再分发。除非拿到上游书面许可，否则不要把它放进公开仓库或公开下载包。 |
| tinyproxy（上游） | 仓库未收录二进制；仅有 `parso/tinyproxy/tinyproxy.sh` 安装脚本 | tinyproxy | — | — | <https://github.com/tinyproxy/tinyproxy> | GPL-2.0 | 仓库没有分发 tinyproxy 二进制，不存在该二进制的再分发；脚本本身的授权未声明，见下一条。 |
| parso 安装脚本 | `parso/builds.sh`、`parso/xray/xray.sh`、`parso/cns/cns.sh`、`parso/amy4/amy4.sh`、`parso/tinyproxy/tinyproxy.sh` | 原 parso 套件脚本（`cns.sh`、`tinyproxy.sh` 标有 `Author: CuteBi`） | 5–18 KB/个 | 见仓库文件 | 原分发地址 `binary.parso.org`（已不可用） | 未声明 | 仅作为安装逻辑保留；公开再分发前同样应确认授权，或重写为自有实现。 |

## 2. 这些文件是怎么来的

- 原始 parso 安装器通过 `http://binary.parso.org/...` 和 `https://binary.quicknet.cyou/...` 下载二进制，使用 `curl -k` 或明文 HTTP，没有证书校验，也没有哈希校验。
- 原始 tinyproxy 源返回的是一个 70 字节的 HTML 跳转页，而不是可执行文件。本仓库没有收录这个假文件，也没有把它算作 tinyproxy 二进制。
- `xray`、`cns`、`amy4` 三个文件取自安装完成后落在机器上的实际文件，逐字节计算 SHA-256 后收入 `parso/`。**没有做上游签名验证**，因此只能证明“这三个字节序列与当时机器上的一致”，不能证明它们与官方发布完全相同。
- `xray` 的版本字符串是 `Xray 1.8.13 (Xray, Penetrates Everything.) Custom (go1.22.3 linux/amd64)`，其中 `Custom` 表示非官方原样构建。

## 3. 自行复核

```bash
# 二进制哈希（与 SHA256SUMS 一致）
sha256sum -c SHA256SUMS

# 版本与构建信息
./parso/xray/linux_amd64 -version
./parso/cns/linux_amd64 -h
./parso/amy4/linux_amd64 -version

# Xray 的 Go 构建信息（可看到 xtls/xray-core 依赖）
go version -m parso/xray/linux_amd64
```

## 4. 公开分发前的处理建议

1. **Xray**：保留 `LICENSES/MPL-2.0.txt`，在仓库中注明“Custom build”，并给出上游源码地址。更稳妥的做法是改用官方 release，并记录 tag / commit / 官方 SHA-256。
2. **CNS / amy4**：这两个组件没有可核验的再分发授权。要么向上游取得书面许可，要么从公开仓库和公开压缩包中移除；只在自有服务器上离线使用，风险由使用者自行承担。
3. **tinyproxy**：不要分发二进制。Debian 12 可直接 `apt-get install -y tinyproxy`，或按上游 GPL-2.0 自行编译；本仓库只保留安装脚本时，也要先确认脚本授权。
4. **安装脚本**：`parso/` 下的脚本不是本仓库原创，MIT 许可不覆盖它们。公开前应取得授权或重写。
5. 本文件是事实记录，不构成法律意见；最终以各上游许可证文本和权利人的书面许可为准。

## 5. 许可文本

- `LICENSES/MPL-2.0.txt`：Xray-core 使用的 Mozilla Public License 2.0 全文。
- `LICENSES/GPL-2.0.txt`：tinyproxy 上游使用的 GNU GPL v2 全文（本仓库未分发其二进制）。
- 本仓库原创脚本与文档的 MIT 文本见根目录 `LICENSE`。
