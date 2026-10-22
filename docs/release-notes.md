## Claude Proxy Guard 0.2.0-preview.1

Windows 上的 Claude Code 专用代理启动器。下载完整 `windows-x64.zip`，核对 `.sha256` 后解除 ZIP 锁定并解压，双击 `Setup.cmd`。

### 本次功能

- 自动发现 NekoRay、Clash/Mihomo、v2rayN 的可读核心配置；导入选中的一个节点，保留原客户端。
- 为 Claude 生成独立 HTTP 入口，按需启动；不复制 DIRECT、节点切换组、订阅更新或控制 API。
- WFP 持久规则限制指定 exe 的网络出口；启动前核对代理归属、配置哈希及出口 IPv4。
- DPAPI 保存自己的 setup-token；独立 Claude 配置、桌面快捷方式、VS Code 集成终端示例。
- 中文操作手册、英文入口、问题模板、安全报告、可复现测试与第三方许可证。

### 验证与边界

Windows Server 2022/2025 CI 实测 WFP 规则安装、指定入口可达、其他地址/端口/UDP/IPv6 阻断、代理停止/恢复与卸载；32 项节点导入测试和 23 项 profile/DPAPI 测试在 Windows PowerShell 5.1 与 PowerShell 7 上运行。

本地额外使用官方 sing-box 1.14.3、Mihomo 1.19.33、Xray 26.3.27 校验虚构 HTTP/TUIC/VLESS 配置和启停归属。未在通用发行版进行真实 Claude 账号端到端测试，也未覆盖全部客户端版本和 Windows 10/11 桌面组合。

这是**未签名的预览版**，不是免封保证或完整沙箱。未知子进程、Windows 代发 DNS、外部授权浏览器不自动受到保护。节点私有配置包含明文代理凭证，勿上传或同步。卸载前先移除 WFP 规则。

源码、ZIP 内 BUILD.json 和 SHA256SUMS.txt 提供版本来源与完整性信息；校验和不代替代码签名。安装前请阅读仓库的安全边界和验证记录。
