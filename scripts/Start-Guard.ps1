param(
    [string]$ProfileDirectory = "$env:LOCALAPPDATA\ClaudeProxyGuard\default",
    [switch]$CheckOnly,
    [Parameter(ValueFromRemainingArguments)][string[]]$ClaudeArguments
)
. "$PSScriptRoot\Common.ps1"
$saved = @{}
try {
    $p = Get-GuardProfile (Join-Path $ProfileDirectory 'profile.json')
    if (@($p.Applications | Where-Object { $_.Path -eq $p.ClaudeExe }).Count -ne 1) { throw 'Claude executable has no unique WFP policy.' }
    Invoke-GuardPolicy $p 'check'
    foreach ($pair in @(@($p.ProxyExe, $p.ProxyExeHash), @($p.ProxyConfig, $p.ProxyConfigHash))) {
        if ((Get-FileHash -LiteralPath $pair[0] -Algorithm SHA256).Hash -ne $pair[1]) { throw 'Pinned proxy binary/config changed. Review it before creating a new profile.' }
    }
    $listeners = @(Get-NetTCPConnection -State Listen -LocalPort $p.Port -ErrorAction SilentlyContinue)
    if ($listeners.Count -ne 1 -or $listeners[0].LocalAddress -ne '127.0.0.1') { throw 'Expected a single loopback-only proxy listener.' }
    $owner = Get-CimInstance Win32_Process -Filter "ProcessId=$($listeners[0].OwningProcess)"
    if ($owner.ExecutablePath -ne $p.ProxyExe -or !$owner.CommandLine -or !$owner.CommandLine.Contains($p.ProxyConfig)) { throw 'Proxy listener identity/config does not match.' }
    $proxy = "http://127.0.0.1:$($p.Port)"
    $exit = & "$env:SystemRoot\System32\curl.exe" --silent --show-error --fail --max-time 15 --noproxy 'localhost' --proxy $proxy 'https://api.ipify.org'
    if ($LASTEXITCODE -ne 0 -or "$exit".Trim() -ne $p.ExpectedIPv4) { throw 'Proxy exit check failed. No fallback is permitted.' }
    if ($CheckOnly) { Write-Host 'Policy, pinned proxy and IPv4 exit verified.'; return }
    foreach ($name in @('ANTHROPIC_API_KEY','ANTHROPIC_AUTH_TOKEN','ANTHROPIC_BASE_URL','CLAUDE_CODE_USE_BEDROCK','CLAUDE_CODE_USE_VERTEX','CLAUDE_CODE_USE_FOUNDRY','CLAUDE_CODE_OAUTH_TOKEN')) {
        if ([Environment]::GetEnvironmentVariable($name, 'Process')) { throw "Remove inherited override first: $name" }
    }
    $values = @{
        HTTP_PROXY=$proxy; HTTPS_PROXY=$proxy; ALL_PROXY=$proxy; NO_PROXY='127.0.0.1,localhost'
        CLAUDE_CONFIG_DIR=(Join-Path $ProfileDirectory 'claude-config')
    }
    $secure = Get-Content -LiteralPath (Join-Path $ProfileDirectory 'token.dpapi') -Raw | ConvertTo-SecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { $values.CLAUDE_CODE_OAUTH_TOKEN = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr); $secure.Dispose() }
    foreach ($name in $values.Keys) {
        $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        [Environment]::SetEnvironmentVariable($name, $values[$name], 'Process')
    }
    & $p.ClaudeExe --setting-sources user --strict-mcp-config --mcp-config (Join-Path $ProfileDirectory 'empty-mcp.json') @ClaudeArguments
} catch {
    Write-Error "Startup stopped: $($_.Exception.Message). No direct or alternate proxy fallback was enabled."
} finally {
    foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
    if (Test-Path variable:values) { $values.Clear() }
}
