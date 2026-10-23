# 网络诊断：先看证据，再改配置

[返回首页](../README.md) · [断线测试步骤](verification.md) · [安全边界](security-model.md)

## 一分钟开始

先启动你配置的**专用代理**，再双击项目根目录的 **`Diagnose.cmd`**。它会检测默认配置，并打开一份本地 HTML 报告。不启动 Claude、不解密 token、不停止代理、不修改防火墙。

使用自定义配置目录：

```powershell
.\scripts\Test-Guard.ps1 -ProfileDirectory 'D:\GuardProfile' -ExtendedNetwork -ExportReport -OpenReport
```

只检查本地状态，不发检测请求：

```powershell
.\scripts\Test-Guard.ps1 -Offline -ExportReport
```

需要核验实际 WFP 规则时，加上 `-VerifyPolicy`，按提示批准管理员检查。诊断自身不会安装、删除规则或提升 Claude 权限。

## 看懂结果

| 状态 | 含义 | 怎么处理 |
| --- | --- | --- |
| PASS | 该项观察符合预期 | 只对本次、该项目成立 |
| FAIL | 明确不符合预期，或基础检查失败 | 先修复，再启动 Claude |
| WARN | 有响应异常或证据不足 | 看下一步提示，不直接归因于 IP 或账号 |
| NOT_CHECKED | 没有做这个检测 | 不能当作通过 |

**退出码 `0` 只表示没有 FAIL，不表示全部检查通过。** 自动化系统应读取 JSON 中每项的 `Status`。基础文件或监听进程校验失败时，所有公网探测都跳过。

## 检查哪些内容

| 检查 | 能确认什么 | 不能确认什么 |
| --- | --- | --- |
| 配置、文件哈希、监听进程 | 当前专用代理与固定配置对应 | 代理远端永远不改路由 |
| ipify + Cloudflare | 两个 HTTPS 目标观察到的出口是否分别等于预设 IPv4 | 其他域名、所有协议、未来连接的出口 |
| IPv6 专用目标 | 若确实返回 IPv6，说明代理具有 IPv6 出站路径 | 请求失败不能证明 IPv6 已被禁止 |
| Claude 网页/API | TLS/HTTP 是否收到响应、具体 HTTP 状态 | 登录是否成功、订阅是否有效、账号是否会被封 |
| Claude Code 更新源 | 是否收到完整且格式正确的版本号 | 安装包下载、安装或升级成功 |
| 凭证文件存在 | 是否已保存加密文件 | token 有效性、所属账号或余额 |
| WFP（显式选用） | helper 是否核验当前规则内容 | 未列出的子进程、浏览器、DNS 服务 |

IPv6 探测经过 HTTP 代理：测到的是**代理出口**，不能直接称为“本机 IPv6 泄漏”。若只需要 IPv4，出现 IPv6 是需要检查的配置偏差。部分远端代理会自行解析目标域名，本机导入时固定了上游 IPv4，并不等于远端只能使用 IPv4。

## HTTP 状态怎么判断

- **401**：未带凭证的请求收到认证要求；说明收到 HTTPS 响应，没做登录测试。
- **403 + challenge 标记**：站点边缘要求浏览器验证；CLI 请求不能代表真实浏览器。
- **普通 403**：拒绝原因未知，不能仅凭这一项认定“IP 脏”。
- **429**：这次请求被限流；没有测试账号额度。
- **3xx**：仅记录跳转状态，不跟随到另一个地址。
- **更新源 200 但返回 HTML**：更新检测仍然不通过；不能把挑战页当作版本号。

不要为消除红色提示而随意更改预设出口或关闭 TLS 验证。先核对专用代理是否启动、文件是否变动、上游是否可达。

## DNS、WebRTC 和断线仍要单独测

1. **DNS**：在真正使用的浏览器环境里打开 [BrowserLeaks DNS](https://browserleaks.com/dns)，运行随机域名解析检测；CLI 与工具的解析要用受控域名或抓包另测。解析器所在国家不同，不自动等于本机泄漏。
2. **WebRTC**：在同一个浏览器环境里打开 [BrowserLeaks WebRTC](https://browserleaks.com/webrtc)。核对候选 IP；没有候选也可能是禁用 WebRTC、UDP 不通或检测失败。
3. **断线直连**：按[验证矩阵](verification.md#自己部署后的验收)在可恢复的测试机上执行。需要测试新连接、其他端口和其他地址；停代理后某网页打不开，只能说明那次请求失败。

浏览器检测页的结果只代表打开它的环境。默认 Chrome、比特浏览器中的另一个配置、VS Code 内置浏览器不能互相代替。报告里的外部链接不会自动运行，更不会据此把 CLI 的 DNS/WebRTC 标为 PASS。

本工具不为了生成一份报告而停掉你的 NekoRay、Clash、TUN 或远程连接。

## 报告保存与隐私

`-ExportReport` 会在配置目录下新建 `diagnostic-时间-随机标识`，其中有 `report.json` 和 `report.html`。只允许当前 Windows 用户、SYSTEM 和管理员访问。每次独立保存，不覆盖旧报告。

报告保留检查 ID、状态、建议、公共检测网址和 HTTP 状态；不写入真实 IP、账号、token、代理密码、私人路径、进程命令行、响应正文或原始异常文本。HTML 没有脚本、远程字体、统计或自动上传。分享前仍请自己看一遍。

默认基础模式只访问 `api.ipify.org`。`-ExtendedNetwork` / `Diagnose.cmd` 额外访问 `www.cloudflare.com`、`api6.ipify.org`、`claude.ai`、`api.anthropic.com` 和 `downloads.claude.ai`。这些站点会看到代理的请求；不会收到 Claude 登录凭证。报告本身离线可读。

## 后台会话的边界

当前支持前台终端和 VS Code **集成终端**入口。启动参数中的 `--bg` 和开头的 `agents` / `daemon` 命令会被拒绝，避免误用未经验证的共享后台进程。

这不是完整的命令沙箱：交互会话内的 `/background`、其他入口、参数重排、外部工具和企业 managed settings 仍需独立审查。不要把前台启动时注入的环境变量，推定为所有后台会话都会继承。依据见 [Claude 官方网络配置](https://code.claude.com/docs/en/network-config#apply-network-settings-to-background-agents)。

## 本次改进参考

检索日期：2026-10-22。参考功能和验证思路，没有复制第三方实现，也没有引入其账号/指纹修改能力。

| 参考来源 | 借鉴点 | 本项目如何落实 |
| --- | --- | --- |
| [CCBaga 网络诊断源码](https://github.com/liseami/CCBaga/blob/main/src-tauri/src/network_links.rs) | 真实服务响应、发布元数据、区分浏览器挑战 | 分项记录 HTTP 状态，验证版本正文；不执行安装 |
| [Net.Coffee Claude IP 页](https://ip.net.coffee/claude/) | 出口、IPv6、服务连通性和浏览器检查分开看 | 多源出口验证；DNS/WebRTC 留为明确的未检查项 |
| [BrowserLeaks DNS](https://browserleaks.com/dns) | 随机域名解析才能观察实际 DNS 解析器 | 不用 HTTPS 出口推断 DNS 无泄漏 |
| [Claude 官方网络配置](https://code.claude.com/docs/en/network-config) | 代理配置的生效时点、后台 supervisor 的特殊继承关系 | 补充前台/后台边界及入口检查 |

未采纳所谓“Claude 信任分”“家宽就安全”“无手机号就安全”等判断。第三方评分不是 Anthropic 的内部判定，地区/ASN 标签也不能证明账号存活率。本项目处理可测量的连接行为。
