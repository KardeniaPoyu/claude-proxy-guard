param([string]$ProfileDirectory = "$env:LOCALAPPDATA\ClaudeProxyGuard\default")
. "$PSScriptRoot\Common.ps1"
$file = Join-Path $ProfileDirectory 'profile.json'
$p = Get-GuardProfile $file
Assert-GuardApplicationsStopped $p
Assert-GuardFilePins $p -SkipProxy
Assert-GuardProxyListener $p
Test-GuardExit $p
Write-Host 'Review the proxy configuration yourself: one intended upstream, no direct or alternate-node fallback.'
Write-Host 'The exit test proves only the current exit. It cannot validate fallback behavior.'
if ((Read-Host 'Type UPDATE to trust the current proxy binary and config') -cne 'UPDATE') { throw 'Pins unchanged.' }
$p.ProxyExeHash = (Get-FileHash -LiteralPath $p.ProxyExe -Algorithm SHA256).Hash
$p.ProxyConfigHash = (Get-FileHash -LiteralPath $p.ProxyConfig -Algorithm SHA256).Hash
Write-GuardJsonAtomic $p $file
Write-Host 'Proxy hashes updated. Endpoint and expected IPv4 remain unchanged.'
