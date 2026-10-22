# Security policy

Claude Proxy Guard is experimental Windows security-related software. It is not a filesystem sandbox, account-ban prevention tool or independently audited product. Read the [security model](docs/security-model.md) before deployment.

## Report a vulnerability privately

Use [GitHub private vulnerability reporting](https://github.com/KardeniaPoyu/claude-proxy-guard/security/advisories/new). Do not open a public issue containing exploit details, credentials or private configuration.

If that form is unavailable, open a minimal issue asking for a private contact. Do not post the vulnerability details until a private channel is established.

Include:

- Affected commit/version and Windows/PowerShell versions.
- The security boundary that failed and reproducible steps.
- A minimal example using synthetic credentials, documentation IPs and disposable executables.
- Any proposed mitigation and whether cleanup is required.

**Never send real tokens, passwords, complete proxy configurations, account exports or unredacted packet captures.** If you accidentally exposed a credential, revoke/rotate it through the relevant provider; deleting an issue or commit is not sufficient.

## Scope and support

Security fixes target the current development branch and the latest published version, if one exists. No commercial support, response-time SLA or long-term support policy is currently offered. Please allow time to reproduce an issue and coordinate disclosure.

Administrators, same-user malicious code, unlisted executables, delegated Windows DNS, proxy upstream fallback and already-established connections are outside the claimed boundary. A bypass inside the documented boundary is still valuable to report, even if another limitation is known.

We prefer transparent fixes and reproducible regression tests. Do not claim independent audit or full isolation based solely on CI success.
