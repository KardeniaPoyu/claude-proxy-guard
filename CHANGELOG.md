# Changelog

所有行为变化和验证范围以具体版本为准。尚未发布的内容列在 Unreleased；不会把测试计划写成已完成结果。

## Unreleased

### Added

- 交互配置向导、诊断入口、策略重新安装及哈希更新入口。
- 中文操作手册、英文项目入口、架构图、排错、安全边界、FAQ 和验证矩阵。
- 贡献指南、安全报告渠道及问题/PR 模板。

### Changed

- 更严格的配置、程序哈希、权限及启动覆盖检查。
- 对文件访问、子进程、DNS、代理上游与账号风险明确说明边界。

### Validation

- 本次修改的实际测试记录见 [验证矩阵](docs/verification.md) 与 [CI](https://github.com/KardeniaPoyu/claude-proxy-guard/actions)。

## Initial public source — 2026-10-22

- 发布 Windows 原生 WFP helper、PowerShell 启动器、DPAPI token 保存与桌面快捷方式脚本。
- 提供独立 Claude 配置、固定 HTTP 代理与启动时 IPv4 出口检查。
- 添加 Windows 构建 CI，以及脚本语法、非法参数拒绝和 profile 校验测试。
- 采用 MIT License；初版为实验性质，不包含真实 WFP 断线集成测试证明。
