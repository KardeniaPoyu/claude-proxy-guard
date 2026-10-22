# 自动发现并导入代理节点

[返回首页](../README.md)

**目标：选一次节点，以后双击 Claude 快捷方式。** 原 NekoRay、Clash 或 v2rayN 可以继续使用；Claude 使用导入后的独立配置。

## 操作步骤

1. 解压完整 Release ZIP 到固定目录，双击 `Setup.cmd`。使用普通用户权限。
2. 第一个问题直接回车，进入自动发现。
3. 选配置，再选一个具体节点。不会替你选“最快节点”或自动切换组。
4. 确认找到的内核和 `claude.exe` 路径。找不到时手动选文件。
5. 确认复制节点到本机私有目录。程序生成独立配置、校验并启动内核。
6. 对照节点服务商信息确认显示的出口 IPv4，输入该 IP 固定出口。
7. 关闭旧 Claude 进程，允许 Windows 安装该 exe 的 WFP 规则。
8. 按提示保存自己的 token、创建快捷方式。没有 token 时，按[授权步骤](usage.md#保存授权)操作。

双击快捷方式会检查规则、按需启动专用代理，再核对出口。**不会添加开机自启。** 关闭 Claude 不会自动停止代理，避免打断同配置的其他会话。

## 支持范围

| 客户端/格式 | 能自动处理什么 | 需要手动的情况 |
| --- | --- | --- |
| NekoRay / NekoBox 的 sing-box | 运行中的核心配置路径、常见目录中的完整 JSON；选择其中具体 outbound | 私有节点数据库、GUI 专用 bean 格式需先导出核心配置 |
| v2rayN / Xray / V2Ray | 核心 JSON 中的具体 outbound；自动匹配已发现的内核 | GUI 数据库需先导出；旧版 V2Ray 命令不兼容时需更新核心 |
| Clash / Mihomo | 本地 YAML/JSON 的 `proxies` 节点 | `proxy-providers` 内的远程订阅不会下载；先在客户端更新并选择本地缓存配置 |
| 便携安装 | 运行中的内核目录，或用户指定目录 | 未运行且装在未知目录时指定安装文件夹 |

导入复用本机已有核心，不转换协议、不下载代理内核。当前真实格式/启停测试：**sing-box 1.14.3、Mihomo 1.19.33、Xray 26.3.27**；HTTP outbound 以及 TUIC/VLESS 的校验与运行情况见[验证记录](verification.md)。旧 Clash、旧 V2Ray、其他版本与协议组合不保证兼容。

YAML 支持普通映射、列表和行内结构；拒绝别名、合并键、重复键、自定义标签、多文档和大于 4 MB 的文件。复杂配置可从客户端导出 JSON。解析失败不会把包含密码的原文输出到日志。

## 自动配置做了什么

- 仅保留选中节点；不复制原路由、DIRECT、fallback、负载均衡、选择组、控制 API 或订阅更新。
- 新建只监听 `127.0.0.1` 的 HTTP 入口；不启用 TUN、不改系统代理。
- 上游服务器固定为 IPv4。若原节点用域名，导入时用 Windows DNS 解析一次该**服务器域名**，保留 TLS 主机名；服务器 IP 变化需要重新导入。
- sing-box/Mihomo 生成经所选节点访问的 DoH 配置；Xray/V2Ray 将 HTTP CONNECT 目标域名交给唯一代理 outbound。
- 拒绝依赖其他节点、外部插件、特定网卡或关闭 TLS 校验的配置。不会静默“修好”一个无法理解的节点。
- 保存内核与生成配置的 SHA-256。修改文件或更新内核后，启动器会停止并要求复核。
- 受 WFP 限制的 Claude 只允许连接这个入口；入口关闭时不切其他端口。**没有代理进程层面的全系统防火墙，也不隔离未知子进程或 Windows DNS 服务。**

HTTP 出口地址一致不等于 DNS、WebRTC 或所有子工具已经通过泄漏检测。导入不会修改浏览器。参考[安全边界](security-model.md)与[网络测试](verification.md)。

## 找不到配置

先启动客户端并选中要导出的节点，再运行：

```powershell
.\scripts\Find-ProxyClients.ps1
# 便携版：增加指定目录（深度最多 3 层，每个根目录最多检查 1500 项）
.\scripts\Find-ProxyClients.ps1 -SearchDirectory 'D:\Apps\NekoRay'
# 只扫描指定目录，不查询运行进程或默认目录
.\scripts\Find-ProxyClients.ps1 -SearchDirectory 'D:\Exports' -OnlySearchDirectory
# 在向导中回车，可直接选择导出的 JSON/YAML 文件
.\scripts\Setup-Auto.ps1 -SearchDirectory 'D:\Apps\v2rayN'
```

扫描输出仅包含配置路径、核心路径、节点数量。节点选择菜单显示本机节点名称和协议；不要把包含个人路径或敏感名称的截图公开上传。

## 启动和停止

自动向导的默认路径为：

- Claude 配置：`%LOCALAPPDATA%\ClaudeProxyGuard\default`
- 专用代理：`%LOCALAPPDATA%\ClaudeProxyGuard\default-proxy`

```powershell
.\scripts\Start-ImportedProxy.ps1 -Directory "$env:LOCALAPPDATA\ClaudeProxyGuard\default-proxy"
.\scripts\Stop-ImportedProxy.ps1 -Directory "$env:LOCALAPPDATA\ClaudeProxyGuard\default-proxy"
```

停止脚本校验 PID、启动时间、程序路径和监听归属；不会按进程名结束你正在使用的其他客户端。停止后 WFP 规则仍然生效。

## 凭证与卸载

导入配置包含所选节点的凭证。文件夹 ACL 限制为当前用户、SYSTEM 和管理员，但**配置本身是明文**，代理内核需要读取它；DPAPI 保护的是 Claude token。不要同步、提交或分享这两个运行目录。

卸载顺序：关闭 Claude → `Remove-Policies.ps1` → `Stop-ImportedProxy.ps1` → 删除自己创建的运行目录与快捷方式。失败安装的目录也应先检查其中是否有已安装的策略，保留 profile 直到卸载完成。

格式参考：[sing-box](https://sing-box.sagernet.org/configuration/)、[Mihomo](https://wiki.metacubex.one/en/config/)、[V2Fly](https://www.v2fly.org/en_US/config/overview.html)。
