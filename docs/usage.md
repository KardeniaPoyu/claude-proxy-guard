# 操作手册

[返回首页](../README.md) · [排错](troubleshooting.md) · [验证](verification.md)

本手册覆盖构建、创建配置、日常使用、更新和卸载。所有示例都需要替换为你自己的路径；不会下载 Claude、购买服务或配置代理上游。

## 准备清单

| 项目 | 要求 |
| --- | --- |
| 系统 | Windows 10/11，PowerShell 5.1 或更新版本 |
| Claude | 已安装的官方原生 `claude.exe` |
| 代理 | HTTP 入口，只监听 `127.0.0.1` |
| 代理启动方式 | 同一 Windows 用户运行，完整配置路径为独立参数，如 `-c C:\Proxy\config.json`；不接受 `--config=路径` |
| 上游 | 自己审查过，禁止直连及其他节点回退 |
| 构建工具 | Visual Studio C++ Build Tools、Windows SDK |
| 权限 | 普通用户运行 Claude；仅策略操作批准 UAC |

共享 Node.js/npm 入口、Cloudflare WARP、浏览器代理插件，以及不暴露配置路径的 GUI 代理，不一定满足当前启动检查。不要仅为了通过检查而填写不真实的配置路径。

## 构建

在 x64 Developer PowerShell for Visual Studio 中：

```powershell
.\scripts\Build.ps1
.\tests\Test-Static.ps1
```

输出为 `bin\proxy-guard.exe`。请保留整个仓库目录结构，脚本按相对路径定位 helper。

若系统执行策略阻止脚本，先阅读脚本并遵循组织的 PowerShell 策略；不要关闭整个系统的安全策略。公司设备受管理的策略优先。

## 创建配置与网络规则

首次使用推荐在普通权限 PowerShell 运行向导：

```powershell
.\scripts\Setup.ps1
```

需要显式参数时：

1. 关闭目标 Claude 和将要纳入限制的工具，避免已有连接影响测试。
2. 启动已经配置好的代理。
3. 使用真实 exe 路径、代理配置路径和预期 IPv4 初始化。

```powershell
.\scripts\Initialize-Profile.ps1 `
  -ClaudeExe 'C:\Tools\Claude\claude.exe' `
  -ProxyExe 'C:\Tools\Proxy\sing-box.exe' `
  -ProxyConfig 'C:\Tools\Proxy\config.json' `
  -ExpectedIPv4 '203.0.113.10' `
  -Port 2082
```

`203.0.113.10` 属于文档保留地址，不能实际使用。初始化要求普通用户权限，先验证运行中的代理与出口，再安装策略；不会覆盖已有配置目录。安装可能为各个程序分别请求 UAC。若中途取消或失败，保留配置并使用 `Install-Policies.ps1` 重试；需要重新初始化时，先移除已安装的策略。

默认目录：

```text
%LOCALAPPDATA%\ClaudeProxyGuard\default\
  profile.json       # 本机路径、预期出口、哈希、策略 ID
  token.dpapi        # 当前用户 DPAPI 加密 token
  empty-mcp.json     # 默认空 MCP 配置
  claude-config\    # 独立 Claude 配置
```

配置目录权限限定为当前用户、SYSTEM 和管理员。它仍可能包含敏感数据，不要加入仓库、同步到公共存储或附到 Issue。

## 保存授权

如果已有自己生成的有效 token，直接保存即可。没有 token 时，先完成上述初始化，再通过受检查的代理环境启动官方授权命令：

```powershell
.\scripts\Start-Guard.ps1 -SetupToken
```

它在验证策略、代理和出口后执行官方 `claude setup-token`，不要求预先存在 token 文件。自行完成浏览器授权，然后运行下面的保存命令。不要在已安装限制却未配置代理的普通终端直接授权。

**外部浏览器不属于本项目的网络策略范围。** 请自行配置和核对浏览器网络；不要把授权 URL、code 或 token 发到 Issue。项目不负责账号资格、token 有效期或订阅状态，也没有使用真实账号测试本版本的授权流程。

```powershell
.\scripts\Save-Token.ps1
```

在隐藏输入提示中粘贴 token。脚本将其用当前 Windows 用户的 DPAPI 加密；更换 Windows 用户或机器后，不应期待该文件能直接解密。需要重新保存自己有效的授权。

## 检查与启动

```powershell
.\scripts\Test-Guard.ps1
.\scripts\Start-Guard.ps1 -CheckOnly
.\scripts\Start-Guard.ps1
```

`Test-Guard.ps1` 用于非破坏诊断；加 `-VerifyPolicy` 可请求 UAC 验证 WFP 策略。`Start-Guard.ps1 -CheckOnly` 执行启动检查，但不加载保存的 token，也不启动 Claude。检查失败时停止，不自动更换节点。

正常启动时，脚本在当前进程环境中临时设置 HTTP 代理、独立配置目录和 token，结束后恢复这些环境变量。启动前检查不会持续监控出口，也不能证明代理进程内存中的路由一定等同于磁盘配置。实际使用前请按[验证矩阵](verification.md)测试。

## 桌面快捷方式与工作区

```powershell
.\scripts\New-DesktopShortcut.ps1 -WorkingDirectory 'D:\Projects'
```

双击 **Claude Proxy Guard** 启动。工作目录只是 Claude 开始工作的目录，不限制它能读取哪些文件。

需要另一个工作区，可以创建另一个名称的快捷方式：

```powershell
.\scripts\New-DesktopShortcut.ps1 `
  -WorkingDirectory 'D:\Projects\another-project' `
  -Name 'Claude - Another Project'
```

## VS Code 集成终端

把下列配置合并到 VS Code 用户 `settings.json`，修改仓库路径，不要覆盖已有设置：

```json
{
  "terminal.integrated.profiles.windows": {
    "Claude Proxy Guard": {
      "path": "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe",
      "args": [
        "-NoProfile", "-NoExit", "-File",
        "C:\\Tools\\claude-proxy-guard\\scripts\\Start-Guard.ps1"
      ]
    }
  }
}
```

在终端下拉菜单中选择 **Claude Proxy Guard**。这是集成终端中的 CLI，不涵盖独立 Claude 图形扩展、VS Code 本身或 Remote-SSH 远端进程。

## Git、Python 和 MCP

WFP 按 exe 路径工作，不自动限制整个进程树。初始化时可以显式加入额外程序：

```powershell
# 添加到 Initialize-Profile.ps1 的参数中：
-AdditionalExecutables @(
  'C:\DedicatedTools\Python\python.exe',
  'C:\DedicatedTools\Git\mingw64\libexec\git-core\git-remote-https.exe'
)
```

优先使用专用工具副本，避免把你日常使用的共享 Python、Git 或 Node 路径一起限制。Git HTTPS、Git SSH、Python 扩展、MCP 服务可能调用其他程序；需要逐个识别真实发起连接的 exe，配置工具自身的 HTTP 代理支持，并实际验证。

本项目默认禁用 MCP。增加 exe 策略不会自动启用 MCP，也不会自动为不支持 HTTP 代理的工具改写流量。启动器会向 Git 注入 HTTP 代理配置，但不自动发现工具路径，也不配置 Git SSH。

## 多个配置

各主要命令接受 `-ProfileDirectory`；所有步骤必须使用同一路径：

```powershell
.\scripts\Start-Guard.ps1 -ProfileDirectory 'C:\LocalProfiles\work'
```

同一个 exe 路径不应同时受多个不同代理端口的配置限制：各组阻断规则可能叠加，导致它无法连接任一代理。不同项目通常只需要更换工作目录，无需新建网络配置。

## 维护与更新

| 变化 | 处理方式 |
| --- | --- |
| 更换项目目录 | 换工作目录或快捷方式即可 |
| token 失效 | 通过官方流程取得自己的有效授权，再运行保存脚本 |
| 代理配置或二进制变化 | 审查变更，再运行 `Update-ProxyPin.ps1` 重新检查出口并确认新哈希 |
| Claude 或受保护工具同路径升级 | 退出相关程序，审查官方新版本，再使用 `Update-ExecutablePin.ps1` 确认新哈希 |
| Claude 或受保护工具更换路径 | 先移除旧策略，再使用新路径创建配置 |
| helper 更新 | 审查更新并重新构建；旧配置中的 helper 哈希可能阻止继续运行，需要重新配置 |
| 添加工具 | 记录所需 exe，移除旧策略，再创建包含新列表的配置 |

不要通过手工删除校验逻辑或复制旧哈希绕过失败。保留旧配置直至相关策略卸载成功。

代理哈希更新需要退出受保护程序、验证当前出口，并输入 `UPDATE` 确认；它不用于更改预期 IP 或代理端口。更换这些值应重新初始化。

当前 profile 格式为 `SchemaVersion = 1`。初版旧配置不自动迁移：先使用原目录移除策略，再创建新目录。卸载入口不要求旧 exe 仍存在，便于清理已升级或已删除的程序路径。

## 卸载

1. 退出 Claude 和受保护工具。
2. 使用原配置目录移除规则。

```powershell
.\scripts\Remove-Policies.ps1
# 使用自定义目录时：
.\scripts\Remove-Policies.ps1 -ProfileDirectory 'C:\LocalProfiles\work'
```

3. 确认移除成功，再删除不需要的快捷方式、配置目录和仓库。

脚本只移除对应策略，不删除 token、项目或其他防火墙规则。**重启电脑或删除仓库不能代替卸载。** 如果卸载失败，保留 `profile.json` 和 helper，按[排错文档](troubleshooting.md)处理；不要重置整机防火墙。
