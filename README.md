<div align="center">

# Claude Proxy Guard

**让 Claude Code 从一个经过检查的代理入口启动。**

[![Windows build](https://github.com/KardeniaPoyu/claude-proxy-guard/actions/workflows/windows.yml/badge.svg)](https://github.com/KardeniaPoyu/claude-proxy-guard/actions/workflows/windows.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-Windows-0078D4)
![Status](https://img.shields.io/badge/status-experimental-orange)

[快速开始](#快速开始) · [操作手册](docs/usage.md) · [安全边界](docs/security-model.md) · [排错](docs/troubleshooting.md) · [English](README.en.md)

</div>

Claude Proxy Guard 是一个 Windows Claude Code 启动器：核对本机代理和出口 IPv4，使用 WFP 限制指定程序的出站连接，再加载独立配置及加密保存的 token。可从桌面快捷方式或 VS Code 集成终端使用。

**当前为实验版。** 构建成功不等于网络隔离已验证；请查看[验证矩阵](docs/verification.md)。本项目不承诺“免封”，不是文件沙箱，与 Anthropic 无关联，也不分发 Claude Code 或代理节点。

![启动检查与网络边界示意图](docs/assets/architecture.svg)

## 核心能力

| 能力 | 实际行为 |
| --- | --- |
| 自动导入 | 发现 NekoRay、Clash/Mihomo、v2rayN 的本地核心配置，选择一个节点生成独立入口 |
| 固定入口 | 只接受指定的 `127.0.0.1:端口` HTTP 代理；导入配置不含 DIRECT、自动选择或切换组 |
| 启动检查 | 检查 WFP 策略、代理进程、配置路径、文件 SHA-256 和预期出口 IPv4 |
| 出站限制 | WFP 持久规则按 exe 路径阻断其他地址、端口、UDP 和 IPv6 |
| 凭证保存 | token 使用当前 Windows 用户的 DPAPI 加密，启动时临时注入 |
| 独立配置 | 使用独立 `CLAUDE_CONFIG_DIR`，默认禁用 MCP 和项目级设置来源 |
| 日常入口 | 桌面快捷方式、VS Code 集成终端；不添加开机自启 |

**保护范围是列入策略的 exe。** 未列入的子进程、Windows 代发的 DNS、代理自身的上游选择，不由这些规则完整覆盖。启动时的出口检查也不是持续监控。[查看详细边界 →](docs/security-model.md)

## 快速开始

### 1. 下载完整 ZIP

从 [Releases](https://github.com/KardeniaPoyu/claude-proxy-guard/releases) 下载 `windows-x64.zip` 和对应 `.sha256`。不要把 GitHub 的 **Source code (zip)** 当安装包。

```powershell
Get-FileHash .\claude-proxy-guard-0.2.0-preview.1-windows-x64.zip -Algorithm SHA256
```

核对摘要后，在 ZIP 属性里点“解除锁定”（如显示），再解压到固定目录。预编译包未做代码签名；摘要只核对文件完整性。完整包已含 WFP helper 和 YAML 解析器，**普通使用者不需要安装 Visual Studio。**

- Windows 10/11、PowerShell 5.1 或更新版本，以及安装策略所需的管理员批准权限。
- 官方 Claude Code 原生 `claude.exe`；本项目不以共享 `node.exe` 作为入口。
- 已安装的 NekoRay、Clash/Mihomo 或 v2rayN，以及自己的有效节点。也可以手动接入现有专用 HTTP 代理。

<details>
<summary>开发者：从源码构建</summary>

需要 Visual Studio C++ Build Tools 与 Windows SDK。

在 **x64 Developer PowerShell for Visual Studio** 中执行：

```powershell
git clone https://github.com/KardeniaPoyu/claude-proxy-guard.git
cd claude-proxy-guard
.\scripts\Build.ps1
.\scripts\Restore-Dependencies.ps1
.\tests\Test-Static.ps1
```

</details>

之后使用普通权限 PowerShell 运行启动器。**不要以管理员权限启动 Claude。**

### 2. 运行配置向导

双击解压目录里的 **`Setup.cmd`**，第一个问题回车选择自动发现。也可在普通 PowerShell 中运行：

```powershell
.\scripts\Setup.ps1
```

按顺序：**选配置 → 选节点 → 确认内核 → 核对出口 IP → 安装规则 → 保存 token → 建快捷方式**。安装规则前关闭待限制的 Claude。原客户端可以继续运行。

找不到便携安装、需要导出节点或想了解凭证存放位置，见[自动发现教程](docs/client-discovery.md)。手动入口保留在向导的 `n` 选项，完整命令见[操作手册](docs/usage.md#创建配置与网络规则)。

没有 token 时，先跳过向导的保存步骤，运行 `Start-Guard.ps1 -SetupToken`，自己完成官方授权后再运行 `Save-Token.ps1`。授权用的外部浏览器不由本项目接管，见[保存授权](docs/usage.md#保存授权)。

配置默认保存在 `%LOCALAPPDATA%\ClaudeProxyGuard\default`，不要把这个目录提交到 Git。

### 3. 检查并启动

```powershell
.\scripts\Start-Guard.ps1 -CheckOnly
.\scripts\Start-Guard.ps1
```

`CheckOnly` 不启动 Claude，也不加载保存的 token。第一次使用前，应完成[网络验证](docs/verification.md)。

需要单独创建快捷方式：

```powershell
.\scripts\New-DesktopShortcut.ps1 -WorkingDirectory 'D:\Projects'
```

以后双击 **Claude Proxy Guard**。导入配置会按需启动专用代理，每次启动会请求 UAC 检查策略。不设开机自启；停止方法见[自动发现教程](docs/client-discovery.md#启动和停止)。VS Code 使用方法见[操作手册](docs/usage.md#vs-code-集成终端)。

## 遇到问题

| 现象 | 先看这里 |
| --- | --- |
| 代理未启动、出口不同、配置发生变化 | [启动检查失败](docs/troubleshooting.md#启动检查失败) |
| 启动后仍提示登录 | [授权问题](docs/troubleshooting.md#授权问题) |
| Git、Python、MCP 不能联网 | [工具范围](docs/usage.md#gitpython-和-mcp) |
| 更换代理、升级程序、换工作区 | [维护与更新](docs/usage.md#维护与更新) |
| 准备删除项目或恢复网络 | [卸载步骤](docs/usage.md#卸载) |

**先卸载策略，再删除配置。** WFP 策略是持久的，删文件或重启电脑不会自动移除它们：

```powershell
.\scripts\Remove-Policies.ps1
```

## 项目资料

- [架构与信任边界](docs/security-model.md) — 什么被检查，什么不在保护范围内。
- [客户端发现与节点导入](docs/client-discovery.md) — NekoRay、Clash/Mihomo、v2rayN 的支持范围和步骤。
- [验证矩阵](docs/verification.md) — 已有证据、待验证项目、可复现测试步骤。
- [FAQ](docs/faq.md) — 订阅、DNS、TUN、文件访问、云端 CC。
- [贡献指南](CONTRIBUTING.md) · [安全报告](SECURITY.md) · [更新记录](CHANGELOG.md)

欢迎提交可复现问题、测试报告和改进。请不要上传 token、完整代理配置、真实节点凭证或个人日志。[MIT License](LICENSE)。
