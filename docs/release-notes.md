## Claude Proxy Guard 0.3.0-preview.1

Windows Claude Code 固定代理启动器。本版新增一键诊断与脱敏 HTML/JSON 报告。

### 下载与使用

- [Windows x64 完整 ZIP](https://github.com/KardeniaPoyu/claude-proxy-guard/releases/download/v0.3.0-preview.1/claude-proxy-guard-0.3.0-preview.1-windows-x64.zip)
- [ZIP SHA-256](https://github.com/KardeniaPoyu/claude-proxy-guard/releases/download/v0.3.0-preview.1/claude-proxy-guard-0.3.0-preview.1-windows-x64.zip.sha256)

核对 SHA-256，按需在 ZIP 属性中解除锁定，解压至固定目录，双击 `Setup.cmd`。不要下载 Source code ZIP 代替完整包。完整包包含原生 helper 与 YAML 解析器，无需 Visual Studio。

已配置专用代理后，双击 `Diagnose.cmd` 生成报告。尚未配置时会明确提示配置缺失，不会把诊断失败显示为通过。离线检查：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Guard.ps1 -Offline -ExportReport
```

### 新功能与修复

- 核对 ipify / Cloudflare 两处出口，探测 IPv6，检查 Claude 网页、API 和更新源响应。
- PASS / FAIL / WARN / NOT_CHECKED 分级，区分浏览器验证、HTTP 限流、响应格式错误与未完成检测。
- 本地 HTML + JSON 报告，不导出 token、真实 IP、私人路径或响应正文；报告目录使用私有 ACL。
- 网络探测使用显式固定代理，不发送账号凭证、不跟随重定向、不回退直连；配置/监听进程校验失败时跳过网络探测。限制响应大小及请求时限。
- 前台启动器拒绝已知 `--bg`、`agents`、`daemon` 入口，明确共享后台会话不在保护范围内。
- 中英文 README 重写定位、使用场景、保护边界，并附诊断示例截图。

### 升级

本版不修改 profile schema、DPAPI token 格式或 WFP 策略格式，无需重新授权。先关闭受保护的 CC，再将新包解压到单独目录，保留原配置和 token。使用新目录的启动脚本并更新指向旧目录的快捷方式；若 profile 固定的 helper 路径或文件摘要发生变化，按维护文档重新核验配置，不要直接跳过 pin 检查。不要先删除原目录，以免丢失移除旧策略所需的工具。

### 发布检查与边界

发布流水线要求通过语法/原生参数、29 项 profile/DPAPI、32 项节点导入、66 项诊断测试，以及隔离 Windows runner 上的实际 WFP 安装、出站阻断、代理停止/恢复和卸载测试。打包后再次解压 ZIP，验证全部文件摘要、原生 helper、YAML 解析器、离线诊断和 HTML/JSON 生成，然后发布。

这是未签名的实验预览版。上述测试不代表真实 Claude 账号端到端验证或所有 Windows 10/11 环境均已覆盖。DNS、浏览器 WebRTC、未登记子进程和远端代理路由需要单独验证；IPv6 超时不等于已阻断。本项目不承诺免封，也不是文件沙箱。完整边界见包内 `docs/security-model.md` 和 `docs/verification.md`。

`BUILD.json` 记录版本与源提交，`SHA256SUMS.txt` 记录包内文件摘要；校验和不替代代码签名。
