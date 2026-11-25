# vendor-scripts —— 上游安装脚本原样归档

这里存放厂商分发的五个安装脚本，**仅作存档与对照，不是推荐路径**。

## 这五个文件里有什么

| 文件 | 行数 | 大小 | 作用 | 下载到的二进制 |
|---|---|---|---|---|
| `builds.sh` | 290 | 8,724 B | 交互菜单，按选项再下载另外四个脚本并执行 | 无 |
| `xray.sh` | 510 | 17,376 B | 组装 xray 配置、写 init/systemd | `http://binary.parso.org/xray/{upx}/linux_<arch>` |
| `cns.sh` | 160 | 5,379 B | 写 cns 配置、装守护 | `http://binary.parso.org/cns/{upx}/linux_<arch>` |
| `amy4.sh` | 219 | 6,913 B | 写 amy4 配置、装守护 | `http://binary.parso.org/amy4/{upx}/{os}_<arch>` |
| `tinyproxy.sh` | 136 | 4,911 B | 写 tinyproxy 配置、装守护 | `https://binary.quicknet.cyou/tinyproxy/{upx}/linux_<arch>` |

合计 1,315 行、43 KB。**二进制为 0 字节**——它们都是下载器，运行的那一刻才去取货。

## 已知问题

1. **全部经过未校验证书的通道取包。** `builds.sh` 解析器用 `curl -sk`；`xray.sh` / `cns.sh` / `tinyproxy.sh` 用 `curl -L -ko`（`-k` 关掉证书校验）；`http://binary.parso.org` 本身还是明文 HTTP。
2. **没有任何哈希校验**，取到什么就装什么。
3. **`tinyproxy` 的源是坏的。** `binary.quicknet.cyou/tinyproxy/...` 现在返回的是一个 70 字节跳转页：

   ```
   <script>window.location.href = "https://binary.quicknet.cyou"</script>
   ```

   装完以后 `tinyproxy` 这个“程序”跑不起来。你自己的服务器 `<your-server>:/usr/local/tinyproxy/tinyproxy` 就是这 70 字节，可对照。
4. **`amy4.sh` 原文硬编码了一组第三方代理凭据。** 第 129、133 行的 `Proxy-Authorization: Basic dWMxMC43LjE2My4xNDQ6...` 与 `X-T5-Auth: 1967948331`，配合伪装成 `curl baiduboxapp` 的 UA。本归档已把这两处替换为 `<REDACTED>`，其余未改。

## 为什么归档而不推荐

真正可离线、可校验的安装方式在仓库的 `../selfhost-kit/`：二进制随仓库提交，`sha256sum -c MANIFEST.sha256` 先校验再安装，全程不联网。

这五个脚本留在这里的价值是**可追溯**：需要确认某个配置字段、某个服务单元原本怎么写，可以对照；不要拿它们当部署入口。

## 与原文的差异

仅 `amy4.sh` 两处凭据被替换为 `<REDACTED>`，其余四个文件与上游逐字节一致（可用 `sha256sum` 对照你手上的原始副本）。
