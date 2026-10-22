param(
    [Parameter(Mandatory)][string]$ClaudeExe,
    [Parameter(Mandatory)][string]$ProxyExe,
    [Parameter(Mandatory)][string]$ProxyConfig,
    [Parameter(Mandatory)][string]$ExpectedIPv4,
    [int]$Port = 2082,
    [string]$ProfileDirectory = "$env:LOCALAPPDATA\ClaudeProxyGuard\default",
    [string[]]$AdditionalExecutables = @(),
    [string]$ImportedProxyDirectory
)
. "$PSScriptRoot\Common.ps1"
if (Test-GuardAdministrator) { throw 'Run setup as your normal Windows user. Only the WFP helper will request elevation.' }
Assert-GuardPath $ProfileDirectory
if (Test-Path -LiteralPath $ProfileDirectory) { throw 'Choose a new profile directory; existing profiles are never overwritten.' }
$helper = Get-GuardHelper
$paths = @($ClaudeExe, $ProxyExe, $ProxyConfig) | ForEach-Object { (Resolve-Path -LiteralPath $_).Path }
$apps = @(@($paths[0]) + $AdditionalExecutables | Select-Object -Unique | ForEach-Object {
    $exe = (Resolve-Path -LiteralPath $_).Path
    Assert-GuardPath $exe -MustExist
    if ([IO.Path]::GetExtension($exe) -ne '.exe') { throw 'Only native .exe paths are supported.' }
    @{ Path = $exe; Id = [guid]::NewGuid().ToString(); Sha256 = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash }
})
if (@($apps | Where-Object { $_.Path -eq $paths[1] }).Count) { throw 'Never apply the client restriction to the proxy process itself.' }
$p = [ordered]@{
    SchemaVersion = 1; CreatedUtc = [DateTime]::UtcNow.ToString('o')
    Port = $Port; ExpectedIPv4 = $ExpectedIPv4; ClaudeExe = $paths[0]
    ProxyExe = $paths[1]; ProxyConfig = $paths[2]
    ProxyExeHash = (Get-FileHash -LiteralPath $paths[1] -Algorithm SHA256).Hash
    ProxyConfigHash = (Get-FileHash -LiteralPath $paths[2] -Algorithm SHA256).Hash
    HelperHash = (Get-FileHash -LiteralPath $helper -Algorithm SHA256).Hash
    Applications = $apps
}
if ($ImportedProxyDirectory) {
    Assert-GuardPath $ImportedProxyDirectory
    $p.ImportedProxyDirectory = $ImportedProxyDirectory
}
if ([System.Net.IPAddress]::Parse($ExpectedIPv4).AddressFamily -ne 'InterNetwork') { throw 'Expected exit must be IPv4.' }
if ($Port -lt 1 -or $Port -gt 65535) { throw 'Invalid port.' }
New-Item -ItemType Directory -Path $ProfileDirectory | Out-Null
Set-GuardPrivateDirectory $ProfileDirectory
$file = Join-Path $ProfileDirectory 'profile.json'
Write-GuardJsonAtomic $p $file
Write-GuardJsonAtomic @{mcpServers=@{}} (Join-Path $ProfileDirectory 'empty-mcp.json')
New-Item -ItemType Directory -Path (Join-Path $ProfileDirectory 'claude-config') | Out-Null
$validated = Get-GuardProfile $file
Assert-GuardApplicationsStopped $validated
Assert-GuardProxyListener $validated
Test-GuardExit $validated
Invoke-GuardPolicy $validated 'install'
Write-Host "Created: $file"
Write-Host 'Next: Save-Token.ps1, then Start-Guard.ps1. No autostart was installed.'
