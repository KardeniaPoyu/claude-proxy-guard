param([string]$ProfileDirectory = "$env:LOCALAPPDATA\ClaudeProxyGuard\default")
. "$PSScriptRoot\Common.ps1"
if (Test-GuardAdministrator) { throw 'Save the token as the normal Windows user who will run Claude.' }
if (!(Test-Path -LiteralPath (Join-Path $ProfileDirectory 'profile.json'))) { throw 'Initialize the profile first.' }
$token = Read-Host 'Paste your own Claude setup-token (hidden; never send it in chat)' -AsSecureString
if ($token.Length -eq 0) { throw 'Empty token.' }
try {
    # Windows DPAPI, current Windows user. No plaintext token is written.
    $path = Join-Path $ProfileDirectory 'token.dpapi'
    $temp = $path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        $token | ConvertFrom-SecureString | Set-Content -LiteralPath $temp -Encoding ASCII -NoNewline
        if (Test-Path -LiteralPath $path) { [IO.File]::Replace($temp, $path, [NullString]::Value) } else { [IO.File]::Move($temp, $path) }
    } finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force } }
} finally { $token.Dispose() }
Write-Host 'Encrypted token saved for this Windows user.'
