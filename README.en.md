<div align="center">

# Claude Proxy Guard

**A checked proxy entry point for Claude Code on Windows.**

[![Windows build](https://github.com/KardeniaPoyu/claude-proxy-guard/actions/workflows/windows.yml/badge.svg)](https://github.com/KardeniaPoyu/claude-proxy-guard/actions/workflows/windows.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

[简体中文](README.md) · [Usage](docs/usage.md) · [Security model](docs/security-model.md) · [Verification](docs/verification.md)

</div>

Claude Proxy Guard checks a local HTTP proxy and its expected IPv4 exit before launching Claude Code with an independent configuration and a Windows DPAPI-encrypted token. Persistent Windows Filtering Platform (WFP) policies restrict specified executables to the chosen loopback TCP port.

**Experimental.** A successful build does not establish network isolation. See the [verification matrix](docs/verification.md). This is not a filesystem sandbox or an account-ban prevention tool. It is unaffiliated with Anthropic and does not distribute Claude Code, accounts or proxy services.

![Architecture and trust boundaries](docs/assets/architecture.svg)

## What it does

- Checks the WFP policies, proxy process, config path, binary/config hashes and expected exit IPv4 before launch.
- Blocks specified executable paths from connecting to other destination addresses/ports, UDP or IPv6.
- Stores your token encrypted for the current Windows user and injects it into the launched process environment.
- Uses an independent `CLAUDE_CONFIG_DIR`; disables MCP and project settings sources by default.
- Provides desktop and VS Code integrated-terminal entry points. Does not add startup tasks.

**Scope matters:** unlisted child processes, delegated Windows DNS, the proxy's upstream routing and existing connections require separate consideration. The exit check runs at startup, not continuously. Same-user malicious code and administrators are outside the threat model.

## Quick start

Requirements: Windows 10/11, PowerShell 5.1+, an official native `claude.exe`, Visual Studio C++ Build Tools + Windows SDK, and permission to approve WFP operations. The HTTP proxy must listen only on `127.0.0.1`, have its full config path in its command line, and be configured without direct or alternate upstream fallback.

Build in **x64 Developer PowerShell for Visual Studio**:

```powershell
git clone https://github.com/KardeniaPoyu/claude-proxy-guard.git
cd claude-proxy-guard
.\scripts\Build.ps1
.\tests\Test-Static.ps1
```

Run the setup wizard from a normal, non-administrator PowerShell. Close target executables first and keep the proxy running:

```powershell
.\scripts\Setup.ps1
.\scripts\Start-Guard.ps1 -CheckOnly
.\scripts\Start-Guard.ps1
```

The wizard collects your program paths, local proxy port and expected exit IPv4. It can also save your own token and create a desktop shortcut. Only the policy helper should elevate. The default profile directory is `%LOCALAPPDATA%\ClaudeProxyGuard\default`; never commit it.

For scripted initialization, see the [usage guide](docs/usage.md). Validate network behavior on a recoverable test machine before relying on it.

## Remove policies before deleting files

Close Claude and the protected tools, then run:

```powershell
.\scripts\Remove-Policies.ps1
```

Persistent WFP policies survive file deletion and reboot. Keep the profile until removal succeeds. This command does not delete your projects, tokens or proxy configuration.

## Documentation and contributing

Detailed documentation currently uses Simplified Chinese: [usage](docs/usage.md), [troubleshooting](docs/troubleshooting.md), [security model](docs/security-model.md), [verification](docs/verification.md), [FAQ](docs/faq.md).

Reproducible bug reports, Windows test results and documentation improvements are welcome. Read [CONTRIBUTING](CONTRIBUTING.md) and [SECURITY](SECURITY.md). Never attach credentials or full proxy configurations. [MIT License](LICENSE).
