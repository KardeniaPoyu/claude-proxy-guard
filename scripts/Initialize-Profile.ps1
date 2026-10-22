param(
    [Parameter(Mandatory)][string]$ClaudeExe,
    [Parameter(Mandatory)][string]$ProxyExe,
    [Parameter(Mandatory)][string]$ProxyConfig,
    [Parameter(Mandatory)][string]$ExpectedIPv4,
    [int]$Port = 2082,
    [string]$ProfileDirectory = "$env:LOCALAPPDATA\ClaudeProxyGuard\default",
    [string[]]$AdditionalExecutables = @()
)
. "$PSScriptRoot\Common.ps1"
if (Test-Path -LiteralPath $ProfileDirectory) { throw 'Choose a new profile directory; existing profiles are never overwritten.' }
$paths = @($ClaudeExe, $ProxyExe, $ProxyConfig) | ForEach-Object { (Resolve-Path -LiteralPath $_).Path }
$apps = @(@($paths[0]) + $AdditionalExecutables | Select-Object -Unique | ForEach-Object {
    @{ Path = (Resolve-Path -LiteralPath $_).Path; Id = [guid]::NewGuid().ToString() }
})
if (@($apps | Where-Object { $_.Path -eq $paths[1] }).Count) { throw 'Never apply the client restriction to the proxy process itself.' }
$p = [ordered]@{
    Port = $Port; ExpectedIPv4 = $ExpectedIPv4; ClaudeExe = $paths[0]
    ProxyExe = $paths[1]; ProxyConfig = $paths[2]
    ProxyExeHash = (Get-FileHash -LiteralPath $paths[1] -Algorithm SHA256).Hash
    ProxyConfigHash = (Get-FileHash -LiteralPath $paths[2] -Algorithm SHA256).Hash
    Applications = $apps
}
if ([System.Net.IPAddress]::Parse($ExpectedIPv4).AddressFamily -ne 'InterNetwork') { throw 'Expected exit must be IPv4.' }
if ($Port -lt 1 -or $Port -gt 65535) { throw 'Invalid port.' }
New-Item -ItemType Directory -Path $ProfileDirectory | Out-Null
$file = Join-Path $ProfileDirectory 'profile.json'
$p | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $file -Encoding UTF8
'{"mcpServers":{}}' | Set-Content -LiteralPath (Join-Path $ProfileDirectory 'empty-mcp.json') -Encoding UTF8
New-Item -ItemType Directory -Path (Join-Path $ProfileDirectory 'claude-config') | Out-Null
$validated = Get-GuardProfile $file
Invoke-GuardPolicy $validated 'install'
Write-Host "Created: $file"
Write-Host 'Next: Save-Token.ps1, then Start-Guard.ps1. No autostart was installed.'
