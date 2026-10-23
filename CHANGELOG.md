# Changelog

所有行为变化和验证范围以具体版本为准。尚未发布的内容列在 Unreleased；不会把测试计划写成已完成结果。

## Unreleased

- 将“复用已有代理节点，创建 Windows CC 专用入口”作为主要使用路径，明确与 TUN 的适用差异。
- 安装向导支持重新扫描、添加便携版客户端目录、导出文件重选、兼容内核菜单及取消；导入前显示确认清单。
- 提前检查 profile/proxy 目录冲突和端口，确认后才运行所选内核；完成后给出针对当前 profile 的诊断命令。
- 新增模拟输入的向导测试，覆盖错误重试、配置重扫、指定目录、内核筛选及凭证不出现在选择结果中。


## 0.3.0-preview.1 — 2026-10-22

- 中英文 README 明确核心差异、使用场景和保护边界；发布 ZIP 解压后验证摘要、原生 helper、YAML 解析器与离线报告。

- 新增 `Diagnose.cmd`：多源出口、IPv6 出站、Claude 网页/API 与更新元数据检查，以及脱敏 HTML/JSON 报告。
- 明确区分 PASS、FAIL、WARN、NOT_CHECKED；代理文件/监听身份校验失败后跳过公网探测；支持完全离线检查。
- 探测固定使用专用 HTTP 代理，无账号凭证、跳转跟随或直连回退；拒绝本机检测目标以避开 .NET Framework 的隐式 loopback 绕过行为。
- 增加前台/共享后台会话的支持边界与入口拒绝检查，补充 CCbaga、Net.Coffee、BrowserLeaks、官方文档的研究对应表。
- 增加 Windows PowerShell 5.1/7 诊断与假代理测试并接入 CI；真实 WFP 仍由隔离 runner 验证。

## 0.2.0-preview.1 — 2026-10-22

### Added

- 本机代理发现、JSON/YAML 节点选择、单节点独立配置导入和按需启动/精确停止。
- `Setup.cmd` 双击入口、固定版本并校验 SHA-256 的 YAML 解析器及第三方许可证。
- Windows 2022/2025 上真实 WFP 允许/阻断/停止/恢复/卸载测试。
- `-SetupToken` 允许在尚未保存 token 时，通过受检查的入口完成官方授权流程。
- 安全发布包、构建来源记录、逐文件与 ZIP 校验和。

- 交互配置向导、诊断入口、策略重新安装及哈希更新入口。
- 中文操作手册、英文项目入口、架构图、排错、安全边界、FAQ 和验证矩阵。
- 贡献指南、安全报告渠道及问题/PR 模板。

### Changed

- 正确识别 Windows BFE 添加的 INDEXED 标记；仍拒绝禁用或异常规则。
- 修复 Windows PowerShell 5.1 的 DPAPI 换行、文件原子替换、快速退出进程状态读取，以及 PowerShell 7 的进程时间戳比较。

- 更严格的配置、程序哈希、权限及启动覆盖检查。
- 对文件访问、子进程、DNS、代理上游与账号风险明确说明边界。

### Validation

- 本次修改的实际测试记录见 [验证矩阵](docs/verification.md) 与 [CI](https://github.com/KardeniaPoyu/claude-proxy-guard/actions)。

## Initial public source — 2026-10-22

- 发布 Windows 原生 WFP helper、PowerShell 启动器、DPAPI token 保存与桌面快捷方式脚本。
- 提供独立 Claude 配置、固定 HTTP 代理与启动时 IPv4 出口检查。
- 添加 Windows 构建 CI，以及脚本语法、非法参数拒绝和 profile 校验测试。
- 采用 MIT License；初版为实验性质，不包含真实 WFP 断线集成测试证明。
