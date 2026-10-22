# Changelog

所有行为变化和验证范围以具体版本为准。尚未发布的内容列在 Unreleased；不会把测试计划写成已完成结果。

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
