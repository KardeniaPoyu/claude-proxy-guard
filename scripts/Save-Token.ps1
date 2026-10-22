param([string]$ProfileDirectory = "$env:LOCALAPPDATA\ClaudeProxyGuard\default")
$ErrorActionPreference = 'Stop'
if (!(Test-Path -LiteralPath (Join-Path $ProfileDirectory 'profile.json'))) { throw 'Initialize the profile first.' }
$token = Read-Host 'Paste your own Claude setup-token (hidden; never send it in chat)' -AsSecureString
if ($token.Length -eq 0) { throw 'Empty token.' }
try {
    # Windows DPAPI, current Windows user. No plaintext token is written.
    $token | ConvertFrom-SecureString | Set-Content -LiteralPath (Join-Path $ProfileDirectory 'token.dpapi') -Encoding ASCII
} finally { $token.Dispose() }
Write-Host 'Encrypted token saved for this Windows user.'
