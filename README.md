# Claude Proxy Guard

Windows 上的 Claude Code 独立启动入口：固定本机 HTTP 代理、核对出口 IPv4、使用 Windows WFP 限制指定程序的出站连接，支持桌面快捷方式和 VS Code 终端。

**实验版，尚未经过独立安全审计。不是“免封工具”，也不是文件沙箱。** 不修改设备指纹、不注册账号、不提供节点；请使用自己获授权的账号并遵守服务条款。项目与 Anthropic 无关联，不分发 Claude Code 本体。

## 能做什么

- 启动前核对代理进程路径、配置路径、二者 SHA-256 和预期出口 IPv4。
- 原生 WFP 持久规则：指定 exe 只能尝试连接 `127.0.0.1:指定端口` 的 TCP；阻断其他目的地址、端口、UDP 和 IPv6。
- 代理未启动、出口不符、规则缺失时停止启动，不添加直连或备用节点。
- 自己生成的 `setup-token` 使用 Windows 当前用户 DPAPI 加密存储；运行时临时注入环境变量。
- 独立 `CLAUDE_CONFIG_DIR`；默认禁用 MCP，关闭项目级设置来源。
- 不添加开机自启，不改整机 TUN，不停止现有代理。

## 先准备

1. Windows 10/11，PowerShell 5.1 或更新版本，管理员批准权限。
2. 已安装的官方 Claude Code **原生 `claude.exe`**。不直接支持 npm 的共享 `node.exe` 入口。
3. 自己配置好的本机 HTTP 代理，**只监听 `127.0.0.1`**。代理进程命令行必须含完整配置文件路径；固定一个上游，不配置直连或其他节点回退。代理维护与上游规则需要你自己审查。
4. Visual Studio C++ Build Tools 和 Windows SDK（构建原生 helper 使用）。

## 1. 构建

在 **x64 Developer PowerShell for Visual Studio** 中进入仓库：

```powershell
.\scripts\Build.ps1
.\tests\Test-Static.ps1
```

生成 `bin\proxy-guard.exe`。安全相关组件建议从源码构建；不要下载陌生人提供的替换二进制。

## 2. 创建配置和网络限制

先关闭待限制程序，保持代理运行。以下地址和路径都是示例，必须改成自己的：

```powershell
.\scripts\Initialize-Profile.ps1 `
  -ClaudeExe 'C:\Tools\Claude\claude.exe' `
  -ProxyExe 'C:\Tools\Proxy\sing-box.exe' `
  -ProxyConfig 'C:\Tools\Proxy\config.json' `
  -ExpectedIPv4 '203.0.113.10' `
  -Port 2082
```

每个 exe 安装规则时弹出 UAC，批准的是 WFP helper。**不要以管理员身份运行 Claude。** 配置默认保存至 `%LOCALAPPDATA%\ClaudeProxyGuard\default`，不在仓库中。示例 IP 属于文档地址，不能实际使用。

可用 `-AdditionalExecutables @('C:\DedicatedTools\python.exe', 'C:\DedicatedTools\git-remote-https.exe')` 同时限制工具。建议使用专用副本：这些持久规则影响同一路径程序的所有调用。Git/SSH/MCP 可能实际启动多个 exe，必须逐一识别并限制；默认不提供自动发现或工具安装。

安装中途失败时保留配置，不要直接删除：先执行第 6 步移除已安装的规则，再重新创建。

## 3. 保存授权

用官方 `claude setup-token` 完成自己的授权，然后运行：

```powershell
.\scripts\Save-Token.ps1
```

在隐藏输入提示中粘贴 token。不要把它发到聊天、Issue、命令行参数或 Git。这个脚本只保存凭证，不代替订阅；实际授权和计费以账号及 Anthropic 规则为准。

## 4. 检查并启动

```powershell
.\scripts\Start-Guard.ps1 -CheckOnly
.\scripts\Start-Guard.ps1
.\scripts\New-DesktopShortcut.ps1 -WorkingDirectory 'D:\Projects'
```

以后双击 **Claude Proxy Guard**。每次启动都需要 UAC 检查现有 WFP 规则，只有 helper 提权，Claude 保持当前用户权限。直接在普通终端输入 `claude` 不会获得本启动器的独立配置和授权注入。

代理升级或配置修改会导致哈希不一致，启动器会拒绝运行。先审查变更、移除旧策略，再使用新的配置目录重新初始化。不要为了绕过错误跳过检查。

## 5. VS Code 中使用

这是 VS Code **集成终端中的 CLI**，不是 Claude 图形扩展的隔离方案。在用户 `settings.json` 的现有配置中合并：

```json
{
  "terminal.integrated.profiles.windows": {
    "Claude Proxy Guard": {
      "path": "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe",
      "args": ["-NoProfile", "-NoExit", "-File", "C:\\Tools\\claude-proxy-guard\\scripts\\Start-Guard.ps1"]
    }
  }
}
```

修改仓库路径，从终端下拉菜单选择此配置。不要覆盖其他 VS Code 设置。

## 6. 卸载限制

退出 Claude 和受保护工具，再运行：

```powershell
.\scripts\Remove-Policies.ps1
```

只移除此配置记录的 WFP 规则，不删除项目、凭证和代理配置。移除成功后可以手动删除配置目录、桌面快捷方式和仓库。**删除仓库或重启电脑不会自动删除持久 WFP 规则**，请保留配置直到卸载完成。

## 必须知道的边界

- WFP 按 exe 路径限制。未列入的子进程、改名/复制后的程序不受保护；不是整个进程树沙箱。
- 本机 DNS 可能由 Windows DNS 服务代发，本项目不能声称实现整机或所有工具的 DNS 防泄漏。代理应使用远端解析；需要更强保证时使用独立 VM 和网络边界。
- 只限制客户端访问本机代理端口，**不能证明代理本身没有上游回退**。出口校验只发生在启动时；应在代理配置层禁用直连和切换。
- 已存在的连接、其他 WFP 驱动、系统版本可能影响行为；安装前关闭程序，并在你的机器做断线验证。
- DPAPI 防止离线明文泄露，不能阻止同一 Windows 用户或管理员读取运行中的凭证。子进程可能继承 token 环境变量。
- Claude 能读到的文件、发送到服务端的任务内容不由这个工具隔离。独立配置不等于独立文件系统。
- 用户级/管理员管理设置、hooks 和自行添加的 CLI 参数属于信任边界；不要运行不可信脚本或插件。
- 不提供云端 Linux 防火墙方案、不承诺降低封号率。

## 验证范围

首版包含脚本语法检查、原生 helper 构建和参数拒绝测试。**本仓库的新通用版本尚未完成真实 WFP 断线集成测试**，不要将前身个人脚本的测试结果当成此版本证明。

正式使用前，在可恢复的 Windows 测试机中验证：允许指定代理 TCP、禁止其他端口/UDP/IPv6；代理停止后请求失败；代理恢复仍为预期出口；移除策略后正常恢复。测试时不要影响自己唯一的远程连接。

参考：[Claude 网络配置](https://code.claude.com/docs/en/network-config)、[认证](https://code.claude.com/docs/en/authentication)、[设置](https://code.claude.com/docs/en/settings)、[Microsoft WFP ALE](https://learn.microsoft.com/en-us/windows/win32/fwp/ale-layers)。

MIT License。
