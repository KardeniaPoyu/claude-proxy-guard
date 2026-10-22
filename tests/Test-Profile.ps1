# No account, public network, elevation or policy changes are required.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
. "$root\scripts\Common.ps1"
$work = Join-Path "$root\build" ('profile-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null
$count = 0
function Expect-Rejection([string]$Name, [scriptblock]$Operation) {
    $rejected = $false
    try { & $Operation | Out-Null } catch { $rejected = $true }
    if (!$rejected) { throw "Expected rejection: $Name" }
    $script:count++
    Write-Host "[PASS] $Name"
}
$names = @('ANTHROPIC_API_KEY','ANTHROPIC_AUTH_TOKEN','ANTHROPIC_BASE_URL','CLAUDE_CODE_USE_BEDROCK','CLAUDE_CODE_USE_VERTEX','CLAUDE_CODE_USE_FOUNDRY','CLAUDE_CODE_OAUTH_TOKEN','NODE_OPTIONS','NODE_TLS_REJECT_UNAUTHORIZED')
$saved = @{}
try {
    foreach ($name in $names) { $saved[$name] = [Environment]::GetEnvironmentVariable($name,'Process'); [Environment]::SetEnvironmentVariable($name,$null,'Process') }
    $claude = Join-Path $work 'claude.exe'; $proxy = Join-Path $work 'proxy.exe'; $config = Join-Path $work 'config.json'
    'fixture only' | Set-Content $claude, $proxy, $config
    $hash = (Get-FileHash $claude -Algorithm SHA256).Hash
    $profile = [ordered]@{
        SchemaVersion=1; Port=2082; ExpectedIPv4='203.0.113.10'; ClaudeExe=$claude; ProxyExe=$proxy; ProxyConfig=$config
        HelperHash=('a'*64); ProxyExeHash=$hash; ProxyConfigHash=$hash
        Applications=@(@{Id=[guid]::NewGuid().ToString(); Path=$claude; Sha256=$hash})
    }
    $file = Join-Path $work 'profile.json'
    Write-GuardJsonAtomic $profile $file
    [void](Get-GuardProfile $file); $count++; Write-Host '[PASS] Valid schema'
    foreach ($change in @(@('Port',0), @('ExpectedIPv4','::1'), @('SchemaVersion',99), @('HelperHash','bad'))) {
        $previous = $profile[$change[0]]; $profile[$change[0]] = $change[1]
        Write-GuardJsonAtomic $profile $file
        Expect-Rejection "Invalid $($change[0])" { Get-GuardProfile $file }
        $profile[$change[0]] = $previous
    }
    $profile.Applications += $profile.Applications[0]
    Write-GuardJsonAtomic $profile $file
    Expect-Rejection 'Duplicate policies' { Get-GuardProfile $file }
    $profile.Applications = @($profile.Applications[0])
    Write-GuardJsonAtomic $profile $file
    # Uninstallation must still be possible after the protected exe is deleted.
    Remove-Item -LiteralPath $claude
    [void](Read-GuardPolicyManifest $file); $count++; Write-Host '[PASS] Removal manifest survives deleted executable'
    Expect-Rejection 'Launch requires existing executable' { Get-GuardProfile $file }
    Expect-Rejection 'Relative path' { Assert-GuardPath 'relative.exe' }
    Expect-Rejection 'Alternate data stream' { Assert-GuardPath 'C:\file.exe:stream' }
    $unicode = 'C:\' + [char]0x6D4B + [char]0x8BD5 + '\file.json'
    Write-GuardJsonAtomic @{Path=$unicode} $file
    if ((Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json).Path -cne $unicode) { throw 'UTF-8 roundtrip failed.' }
    Write-GuardJsonAtomic @{Path=$unicode; Updated=$true} $file
    if (!(Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json).Updated) { throw 'Atomic replacement failed.' }
    $count++; Write-Host '[PASS] Unicode JSON and atomic replace'
    # Exercise the on-disk DPAPI format, including compatibility with old CRLF files.
    # This fixture is deliberately not a real token and is never sent anywhere.
    $secret = ConvertTo-SecureString 'offline-dpapi-fixture' -AsPlainText -Force
    try {
        $encrypted = ConvertFrom-SecureString $secret
        $tokenFile = Join-Path $work 'fixture.dpapi'
        foreach ($suffix in @('', "`r`n")) {
            [IO.File]::WriteAllText($tokenFile, $encrypted + $suffix, [Text.Encoding]::ASCII)
            $decoded = ConvertTo-SecureString ((Get-Content -LiteralPath $tokenFile -Raw -Encoding ASCII).Trim())
            $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($decoded)
            try {
                if ([Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) -cne 'offline-dpapi-fixture') { throw 'DPAPI file roundtrip failed.' }
            } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr); $decoded.Dispose() }
        }
    } finally { $secret.Dispose() }
    $count++; Write-Host '[PASS] DPAPI file roundtrip with and without CRLF'
    Assert-GuardLaunchInputs $work @('--model','sonnet'); $count++; Write-Host '[PASS] Normal model option'
    foreach ($arg in @('--bare','--settings=x','--setting-sources','--mcp-config=x','--plugin-dir=x')) {
        Expect-Rejection "Guarded CLI option $arg" { Assert-GuardLaunchInputs $work @($arg) }
    }
    $settings = Join-Path $work 'settings.json'
    foreach ($value in @(@{env=@{https_proxy='http://127.0.0.1:9'}}, @{apiKeyHelper='untrusted.exe'}, @{env=@{ANTHROPIC_BASE_URL='https://example.invalid'}})) {
        Write-GuardJsonAtomic $value $settings
        Expect-Rejection 'Conflicting settings' { Assert-GuardLaunchInputs $work @() }
    }
    Remove-Item -LiteralPath $settings
    [Environment]::SetEnvironmentVariable('ANTHROPIC_API_KEY','dummy-fixture-not-a-key','Process')
    Expect-Rejection 'Inherited provider credential' { Assert-GuardLaunchInputs $work @() }
    [Environment]::SetEnvironmentVariable('ANTHROPIC_API_KEY',$null,'Process')
    [Environment]::SetEnvironmentVariable('NODE_TLS_REJECT_UNAUTHORIZED','0','Process')
    Expect-Rejection 'Disabled TLS verification' { Assert-GuardLaunchInputs $work @() }
    Write-Host "PASS: $count profile/settings tests. No policies or real credentials touched."
} finally {
    foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name,$saved[$name],'Process') }
    # Unique, explicitly checked test directory under this repository's build directory.
    $build = [IO.Path]::GetFullPath((Join-Path $root 'build')) + [IO.Path]::DirectorySeparatorChar
    if (![IO.Path]::GetFullPath($work).StartsWith($build,[StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe cleanup path.' }
    Remove-Item -LiteralPath $work -Recurse -Force
}
exit 0
