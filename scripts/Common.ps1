Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
function Get-GuardProfile([string]$Path) {
    $p = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if ($p.Port -lt 1 -or $p.Port -gt 65535) { throw 'Invalid proxy port.' }
    $ip = [System.Net.IPAddress]::Parse($p.ExpectedIPv4)
    if ($ip.AddressFamily -ne 'InterNetwork') { throw 'Expected exit must be IPv4.' }
    foreach ($f in @($p.ClaudeExe, $p.ProxyExe, $p.ProxyConfig)) {
        if (!(Test-Path -LiteralPath $f -PathType Leaf)) { throw "Missing file: $f" }
    }
    return $p
}
function Invoke-GuardPolicy($p, [string]$Action) {
    $helper = Join-Path $PSScriptRoot '..\bin\proxy-guard.exe'
    if (!(Test-Path -LiteralPath $helper)) { throw 'Build the WFP helper first.' }
    foreach ($a in $p.Applications) {
        $id = [guid]::Parse($a.Id).ToString()
        if ($a.Path.Contains('"')) { throw 'Invalid executable path.' }
        $argsLine = '{0} "{1}" {2} {3}' -f $Action, $a.Path, $p.Port, $id
        # Elevate ONLY the policy helper. Claude always runs as the current user.
        $proc = Start-Process -FilePath $helper -ArgumentList $argsLine -Verb RunAs -Wait -PassThru
        if ($proc.ExitCode -ne 0) { throw "WFP $Action failed for $($a.Path). Startup blocked." }
    }
}
