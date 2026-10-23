<div align="center">

# Claude Proxy Guard

**Turn an existing proxy node into a dedicated Claude Code development entry point on Windows.**

[![Windows build](https://github.com/KardeniaPoyu/claude-proxy-guard/actions/workflows/windows.yml/badge.svg)](https://github.com/KardeniaPoyu/claude-proxy-guard/actions/workflows/windows.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

[简体中文](README.md) · [Usage](docs/usage.md) · [Security model](docs/security-model.md) · [Verification](docs/verification.md)

</div>

Already using NekoRay, Clash/Mihomo or v2rayN? Select one node from a readable local config, create a separate proxy entry, then launch CC from a desktop shortcut or VS Code integrated terminal. No changes to whole-machine TUN or the original client selection are needed.

**Discover a config → choose one node → confirm storage and exit → create the CC entry point.**

For Windows users who want CC on a fixed proxy while other applications keep their existing network configuration. Restrictions follow executable paths, so other instances at the same path are also affected. The distinction is the integrated setup and verification workflow: a correctly configured TUN can also provide proxy routing and outage blocking. This project does not claim better account-ban prevention.

Before launch it verifies the proxy process, pinned files and expected IPv4. During use, persistent Windows Filtering Platform (WFP) policies restrict registered executables to the selected loopback TCP port. An imported proxy keeps one chosen node without DIRECT or automatic switching groups. **The local entry point and imported configuration are fixed; the remote service's routing still needs verification. Exit checks are not continuous monitoring.**

**Experimental.** A successful build does not establish network isolation. See the [verification matrix](docs/verification.md). This is not a filesystem sandbox or an account-ban prevention tool. It is unaffiliated with Anthropic and does not distribute Claude Code, accounts or proxy services.

![Architecture and trust boundaries](docs/assets/architecture.svg)

## Core differences

| Need | Implementation |
| --- | --- |
| Fail when the proxy stops | Environment variables configure proxy use; persistent WFP rules block registered executable paths from other addresses/ports, UDP and IPv6 |
| Avoid the wrong proxy | Verify the actual listener process, config path, SHA-256 pins, WFP policy and expected exit before starting CC |
| Reuse an existing node | Discover readable NekoRay, Clash/Mihomo and v2rayN core configs and import one node separately; original clients are unchanged, but not every GUI database/subscription format is supported |
| A separate development entry point | Independent `CLAUDE_CONFIG_DIR`, DPAPI-encrypted token, desktop/VS Code terminal launchers; MCP and project settings sources disabled by default; no login autostart |
| Reproducible diagnostics | Per-check exit/service observations, redacted reports and actual WFP stop/restore tests in Windows CI; untested areas stay explicitly unverified |

General proxy clients manage nodes and routing; IP-check websites observe the browser making the request. This project connects **pre-launch verification and per-executable connection restrictions** into one workflow. Its value is integration and verifiability, built on standard WFP and DPAPI technologies.

## Use cases

| Scenario | Entry point |
| --- | --- |
| Local Windows development | Desktop shortcut: verify the dedicated proxy, then load your authorization and start CC |
| Projects in VS Code | Use the same launcher in the integrated terminal, with your chosen working directory |
| Existing NekoRay / Clash / v2rayN node | Run `Setup.cmd`, choose a readable core config and import one node |
| Troubleshooting or reporting a bug | Run `Diagnose.cmd` for a report without credentials, raw IPs or private paths |

## Scope before setup

- **Windows foreground CC and VS Code integrated terminals only.** GUI extensions, authorization browsers, cloud CC, WSL and shared background sessions are not automatically protected.
- **Rules follow executable paths, not parent/child relationships.** Git, Python and MCP networking executables need individual configuration; other instances at the same path are also affected. MCP is disabled by default.
- **DNS and remote routing need separate tests.** CC's WFP policy does not establish isolation for delegated Windows DNS, browser WebRTC or the proxy server's upstream routing.

[Full security boundaries](docs/security-model.md) · [Verified and unverified behavior](docs/verification.md). Same-user malicious code and administrators are outside the threat model.

## Diagnose without an account

**Current preview:** [0.3.0-preview.1](https://github.com/KardeniaPoyu/claude-proxy-guard/releases/tag/v0.3.0-preview.1) includes `Diagnose.cmd` and HTML/JSON reports.

Start your dedicated proxy, then double-click **Diagnose.cmd**. It compares two HTTPS exit observations against the pinned IPv4, probes IPv6 egress, and checks Claude web/API and release metadata. It exports a private, self-contained HTML report plus JSON, without credentials, raw IPs, private paths or response bodies.

```powershell
.\scripts\Test-Guard.ps1 -ExtendedNetwork -ExportReport -OpenReport
.\scripts\Test-Guard.ps1 -Offline -ExportReport
```

Results distinguish **PASS / FAIL / WARN / NOT_CHECKED**. A timeout is not proof of IPv6 blocking, and HTTP 403 is not an IP-reputation verdict. DNS, WebRTC, outage behavior and shared background sessions remain explicitly unverified. No proxy is stopped and no network policy is changed. See the [diagnostic guide and sources](docs/diagnostics.md).

![Screenshot of the actual report UI using labeled synthetic fixtures, not measurements of this computer](docs/assets/diagnostics-example.png)

## Quick start

The enhanced wizard in current source adds rescan (`R`), portable-client folder search (`D`), exported-file selection (`F`), retryable choices and cancel (`Q`). These wizard improvements are not included in the `0.3.0-preview.1` ZIP linked below.

[Windows x64 ZIP](https://github.com/KardeniaPoyu/claude-proxy-guard/releases/download/v0.3.0-preview.1/claude-proxy-guard-0.3.0-preview.1-windows-x64.zip) · [SHA-256](https://github.com/KardeniaPoyu/claude-proxy-guard/releases/download/v0.3.0-preview.1/claude-proxy-guard-0.3.0-preview.1-windows-x64.zip.sha256)

Requirements: Windows 10/11, PowerShell 5.1+, an official native `claude.exe`, an installed proxy core with your own valid node, and permission to approve WFP operations.

Download the complete **windows-x64.zip** from [Releases](https://github.com/KardeniaPoyu/claude-proxy-guard/releases), verify its SHA-256, unblock the ZIP in Windows Properties if necessary, then extract and double-click **Setup.cmd**. The full package includes the helper and YAML parser; end users do not need Visual Studio. Binaries are unsigned.

Press Enter at the first prompt: **discover config → choose node → confirm core → verify exit IPv4 → install WFP → save token → create shortcut**. The shortcut starts the imported proxy on demand, without login autostart. Original clients stay unchanged. GUI databases and remote subscriptions require a local core-config export; see [import support and limitations](docs/client-discovery.md).

For manual setup, the HTTP proxy must run as the same Windows user, listen only on `127.0.0.1`, and take its absolute config path as a separate argument. Disable direct and alternate-upstream fallback in that proxy yourself.

Developers can instead build with C++ Build Tools + Windows SDK in **x64 Developer PowerShell for Visual Studio**:

```powershell
git clone https://github.com/KardeniaPoyu/claude-proxy-guard.git
cd claude-proxy-guard
.\scripts\Build.ps1
.\scripts\Restore-Dependencies.ps1
.\tests\Test-Static.ps1
```

Run the setup wizard from a normal, non-administrator PowerShell. Close target executables first and keep the proxy running:

```powershell
.\scripts\Setup.ps1
.\scripts\Start-Guard.ps1 -CheckOnly
.\scripts\Start-Guard.ps1
```

Only the policy helper should elevate. The default profile directory is `%LOCALAPPDATA%\ClaudeProxyGuard\default`; the imported node lives in `default-proxy` and contains plaintext proxy credentials protected by directory ACLs. Never commit either directory. Without an existing token, use `Start-Guard.ps1 -SetupToken`, complete the official authorization yourself, then `Save-Token.ps1`; the external authorization browser is outside this launcher's policy.

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
