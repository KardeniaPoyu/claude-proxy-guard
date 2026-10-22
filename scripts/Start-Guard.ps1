param(
    [string]$ProfileDirectory = "$env:LOCALAPPDATA\ClaudeProxyGuard\default",
    [switch]$CheckOnly,
    [Parameter(ValueFromRemainingArguments)][string[]]$ClaudeArguments
)
. "$PSScriptRoot\Common.ps1"
$saved = @{}
$resultCode = 1
$values = @{}
try {
    if (!$CheckOnly -and (Test-GuardAdministrator)) { throw 'Do not run Claude as Administrator. Reopen this launcher as your normal user.' }
    $p = Get-GuardProfile (Join-Path $ProfileDirectory 'profile.json')
    Assert-GuardFilePins $p
    $config = Join-Path $ProfileDirectory 'claude-config'
    Assert-GuardLaunchInputs $config $ClaudeArguments
    Invoke-GuardPolicy $p 'check'
    Assert-GuardProxyListener $p
    Test-GuardExit $p
    if ($CheckOnly) {
        Write-Host '[OK] Policies, pinned proxy and expected IPv4 exit verified.' -ForegroundColor Green
        $resultCode = 0
    } else {
        $mcpPath = Join-Path $ProfileDirectory 'empty-mcp.json'
        $mcp = Get-Content -LiteralPath $mcpPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (@($mcp.mcpServers.PSObject.Properties).Count -ne 0) { throw 'The default MCP configuration must be empty.' }
        $proxy = "http://127.0.0.1:$($p.Port)"
        $values = @{
            HTTP_PROXY=$proxy; HTTPS_PROXY=$proxy; ALL_PROXY=$proxy; NO_PROXY='127.0.0.1,localhost'
            CLAUDE_CONFIG_DIR=$config
            # Git HTTP transport does not uniformly use HTTP_PROXY. SSH requires separate configuration.
            GIT_CONFIG_COUNT='1'; GIT_CONFIG_KEY_0='http.proxy'; GIT_CONFIG_VALUE_0=$proxy
        }
        $encrypted = (Get-Content -LiteralPath (Join-Path $ProfileDirectory 'token.dpapi') -Raw -Encoding ASCII).Trim()
        $secure = ConvertTo-SecureString $encrypted
        $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try { $values.CLAUDE_CODE_OAUTH_TOKEN = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr); $secure.Dispose() }
        foreach ($name in $values.Keys) {
            $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
            [Environment]::SetEnvironmentVariable($name, $values[$name], 'Process')
        }
        Write-Host 'Claude Proxy Guard | verified proxy | independent config' -ForegroundColor Cyan
        & $p.ClaudeExe --setting-sources user --strict-mcp-config --mcp-config $mcpPath @ClaudeArguments
        $resultCode = $LASTEXITCODE
    }
} catch {
    Write-Error "Startup stopped: $($_.Exception.Message) No direct or alternate proxy fallback was enabled." -ErrorAction Continue
    $resultCode = 1
} finally {
    foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
    $values.Clear()
}
exit $resultCode
