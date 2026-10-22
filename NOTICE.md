# Third-party components

This repository contains original launcher scripts and a Windows Filtering Platform helper under the MIT license. It does not bundle Claude Code, a proxy client, tokens, accounts or proxy configurations.

The native helper is compiled using Microsoft's C++ toolchain and Windows SDK and links to Windows system APIs. These tools and Windows are governed by their own licenses. A prebuilt helper is not Authenticode signed; checksums establish file integrity, not publisher identity. Inspect the source and build locally if this distinction matters to your deployment.

The name Claude Code refers to Anthropic's product. This is an independent community project, not an Anthropic product or endorsement.

Release ZIPs include YamlDotNet 16.3.0 (MIT), copyright Antoine Aubry and contributors. The unmodified net47 assembly is restored from a checksum-pinned NuGet package. Its full license is in [docs/YamlDotNet-LICENSE.txt](docs/YamlDotNet-LICENSE.txt). It parses local YAML only; it does not download subscriptions or instantiate user-defined YAML types. Proxy core binaries used for optional compatibility tests are not redistributed.
