# Shared validation; loading this file does not change networking or policies.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:GuardRoot = Split-Path $PSScriptRoot

function Test-GuardAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-GuardPath([string]$Path, [switch]$MustExist) {
    if ($Path -notmatch '^[A-Za-z]:\\' -or $Path -match '["\r\n]' -or $Path.Substring(2).Contains(':')) {
        throw 'Use a local absolute Windows path without quotes, newlines or alternate data streams.'
    }
    if ($MustExist -and !(Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing file: $Path" }
}

function Read-GuardPolicyManifest([string]$Path) {
    $p = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$p.Port -notmatch '^[1-9][0-9]{0,4}$' -or [int]$p.Port -gt 65535) { throw 'Invalid proxy port.' }
    $apps = @($p.Applications)
    if ($apps.Count -lt 1 -or $apps.Count -gt 64) { throw 'Profile must contain 1-64 executable policies.' }
    $ids = @{}; $paths = @{}
    foreach ($a in $apps) {
        Assert-GuardPath $a.Path
        $id = [guid]::Parse($a.Id)
        if ($id -eq [guid]::Empty -or $ids.ContainsKey($id.ToString()) -or $paths.ContainsKey($a.Path)) { throw 'Empty or duplicate policy identity/path.' }
        $ids[$id.ToString()] = $true; $paths[$a.Path] = $true
    }
    return $p
}

function Get-GuardProfile([string]$Path) {
    $p = Read-GuardPolicyManifest $Path
    if (!$p.PSObject.Properties['SchemaVersion'] -or $p.SchemaVersion -ne 1) {
        throw 'Unsupported profile version. Remove old policies with Remove-Policies.ps1, then initialize a new profile.'
    }
    if ([System.Net.IPAddress]::Parse($p.ExpectedIPv4).AddressFamily -ne 'InterNetwork') { throw 'Expected exit must be IPv4.' }
    foreach ($f in @($p.ClaudeExe, $p.ProxyExe, $p.ProxyConfig)) { Assert-GuardPath $f -MustExist }
    foreach ($hash in @($p.ProxyExeHash, $p.ProxyConfigHash, $p.HelperHash)) {
        if ($hash -notmatch '^[a-fA-F0-9]{64}$') { throw 'Invalid SHA-256 pin.' }
    }
    foreach ($a in $p.Applications) {
        Assert-GuardPath $a.Path -MustExist
        if ($a.Sha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'Missing executable SHA-256 pin.' }
        if ($a.Path -eq $p.ProxyExe) { throw 'The proxy must never receive a client restriction.' }
    }
    if (@($p.Applications | Where-Object { $_.Path -eq $p.ClaudeExe }).Count -ne 1) { throw 'Claude executable has no unique WFP policy.' }
    if ($p.PSObject.Properties['ImportedProxyDirectory']) { Assert-GuardPath $p.ImportedProxyDirectory }
    return $p
}

function Get-GuardHelper {
    $helper = Join-Path $script:GuardRoot 'bin\proxy-guard.exe'
    if (!(Test-Path -LiteralPath $helper -PathType Leaf)) { throw 'WFP helper missing. Use the complete release ZIP or run scripts/Build.ps1.' }
    return (Resolve-Path -LiteralPath $helper).Path
}

function Assert-GuardFilePins($Profile, [switch]$SkipProxy) {
    if ((Get-FileHash -LiteralPath (Get-GuardHelper) -Algorithm SHA256).Hash -ne $Profile.HelperHash) {
        throw 'Helper changed. Review the release, remove old policies and initialize a new profile.'
    }
    foreach ($a in $Profile.Applications) {
        if ((Get-FileHash -LiteralPath $a.Path -Algorithm SHA256).Hash -ne $a.Sha256) { throw 'A protected executable changed. Review it and use Update-ExecutablePin.ps1.' }
    }
    if (!$SkipProxy) {
        foreach ($pair in @(@($Profile.ProxyExe, $Profile.ProxyExeHash), @($Profile.ProxyConfig, $Profile.ProxyConfigHash))) {
            if ((Get-FileHash -LiteralPath $pair[0] -Algorithm SHA256).Hash -ne $pair[1]) { throw 'Pinned proxy changed. Review its upstream/fallback configuration and use Update-ProxyPin.ps1.' }
        }
    }
}

function Invoke-GuardPolicy($Profile, [ValidateSet('install','check','remove')][string]$Action) {
    $helper = Get-GuardHelper
    foreach ($a in $Profile.Applications) {
        Assert-GuardPath $a.Path
        $id = [guid]::Parse($a.Id).ToString()
        $argsLine = '{0} "{1}" {2} {3}' -f $Action, $a.Path, [int]$Profile.Port, $id
        if (Test-GuardAdministrator) {
            & $helper $Action $a.Path ([int]$Profile.Port).ToString() $id
            $code = $LASTEXITCODE
        } else {
            # Only the narrowly-scoped native helper receives elevation.
            $proc = Start-Process -FilePath $helper -ArgumentList $argsLine -Verb RunAs -Wait -PassThru
            $code = $proc.ExitCode
        }
        if ($code -ne 0) { throw "WFP $Action failed. No client will be launched. Keep the profile for recovery/uninstall." }
    }
}

function Assert-GuardApplicationsStopped($Profile) {
    $targets = @($Profile.Applications | ForEach-Object { $_.Path })
    $running = @(Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -and $targets -contains $_.ExecutablePath })
    if ($running.Count) { throw 'Close protected executables before installing/updating policies. No processes were stopped automatically.' }
}

function Assert-GuardProxyListener($Profile) {
    $listeners = @(Get-NetTCPConnection -State Listen -LocalPort $Profile.Port -ErrorAction SilentlyContinue)
    if ($listeners.Count -ne 1 -or $listeners[0].LocalAddress -ne '127.0.0.1') { throw 'Expected exactly one proxy listener on 127.0.0.1. Start the dedicated proxy.' }
    $owner = Get-CimInstance Win32_Process -Filter "ProcessId=$($listeners[0].OwningProcess)"
    if (!$owner -or $owner.ExecutablePath -ne $Profile.ProxyExe -or !$owner.CommandLine) { throw 'Proxy process cannot be verified. Run it under the same Windows user using the pinned executable.' }
    # Match a whole Windows argument, never a misleading config.json.backup prefix.
    if (-not ('GuardCommandLine' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class GuardCommandLine {
    [DllImport("shell32.dll", SetLastError=true)] static extern IntPtr CommandLineToArgvW([MarshalAs(UnmanagedType.LPWStr)] string s, out int n);
    [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr p);
    public static string[] Split(string s) {
        int n; IntPtr p = CommandLineToArgvW(s, out n);
        if (p == IntPtr.Zero) throw new System.ComponentModel.Win32Exception();
        try { var a = new string[n]; for (int i=0;i<n;i++) a[i]=Marshal.PtrToStringUni(Marshal.ReadIntPtr(p,i*IntPtr.Size)); return a; }
        finally { LocalFree(p); }
    }
}
'@
    }
    if (@([GuardCommandLine]::Split($owner.CommandLine)) -notcontains $Profile.ProxyConfig) { throw 'Proxy command line must contain the exact absolute config path as a separate argument.' }
}

function Test-GuardExit($Profile) {
    $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
    if (!(Test-Path -LiteralPath $curl)) { throw 'Windows curl.exe is required for the HTTPS exit check.' }
    # -q must be first: ignore .curlrc, and explicitly override proxy bypass settings.
    $result = & $curl -q --silent --show-error --fail --max-time 15 --connect-timeout 8 --proto '=https' --noproxy 'localhost' --proxy "http://127.0.0.1:$($Profile.Port)" 'https://api.ipify.org'
    if ($LASTEXITCODE -ne 0 -or "$result".Trim() -ne $Profile.ExpectedIPv4) { throw 'Proxy exit failed or returned a different IPv4. No fallback is permitted.' }
}

function Set-GuardPrivateDirectory([string]$Directory) {
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($identity in @($sid, [Security.Principal.SecurityIdentifier]'S-1-5-18', [Security.Principal.SecurityIdentifier]'S-1-5-32-544')) {
        $rule = New-Object Security.AccessControl.FileSystemAccessRule($identity, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
        $acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $Directory -AclObject $acl
}

function Write-GuardJsonAtomic($Value, [string]$Path) {
    $temp = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllText($temp, ($Value | ConvertTo-Json -Depth 32), (New-Object Text.UTF8Encoding($false)))
        if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($temp, $Path, [NullString]::Value) } else { [IO.File]::Move($temp, $Path) }
    } finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force } }
}

function Assert-GuardLaunchInputs([string]$ConfigDirectory, [string[]]$Arguments) {
    if ([Environment]::GetEnvironmentVariable('NODE_TLS_REJECT_UNAUTHORIZED', 'Process') -eq '0') { throw 'TLS verification must remain enabled.' }
    $forbidden = @('ANTHROPIC_API_KEY','ANTHROPIC_AUTH_TOKEN','ANTHROPIC_BASE_URL','CLAUDE_CODE_USE_BEDROCK','CLAUDE_CODE_USE_VERTEX','CLAUDE_CODE_USE_FOUNDRY','CLAUDE_CODE_OAUTH_TOKEN','NODE_OPTIONS')
    foreach ($name in $forbidden) {
        if ([Environment]::GetEnvironmentVariable($name, 'Process')) { throw "Remove inherited authentication/provider/runtime override: $name" }
    }
    foreach ($arg in $Arguments) {
        if ($arg -match '^--(bare|settings|setting-sources|mcp-config|strict-mcp-config|plugin-dir)(=|$)') { throw 'That CLI option overrides guarded startup configuration.' }
    }
    $settingsPath = Join-Path $ConfigDirectory 'settings.json'
    if (Test-Path -LiteralPath $settingsPath) {
        $settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($settings.PSObject.Properties['apiKeyHelper']) { throw 'apiKeyHelper conflicts with token-only authentication.' }
        if ($settings.PSObject.Properties['env']) {
            foreach ($prop in $settings.env.PSObject.Properties) {
                if ($prop.Name -match '(?i)proxy|^ANTHROPIC_|^CLAUDE_CODE_(OAUTH|USE_)|^CLAUDE_CONFIG_DIR$|^NODE_(OPTIONS|TLS_REJECT_UNAUTHORIZED)$') { throw 'User settings contain a proxy/auth/runtime override.' }
            }
        }
    }
}
