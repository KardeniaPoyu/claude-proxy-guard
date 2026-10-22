$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
foreach ($file in Get-ChildItem "$root\scripts\*.ps1") {
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw "$($file.Name): $errors" }
}
$helper = "$root\bin\proxy-guard.exe"
if (!(Test-Path $helper)) { throw 'Build native helper first.' }
foreach ($argsList in @(@('invalid'), @('install','relative.exe','2082','bad'), @('check','C:\fake.exe','0','bad'))) {
    & $helper @argsList
    if ($LASTEXITCODE -ne 2) { throw 'Invalid input was not rejected before opening WFP.' }
}
. "$root\scripts\Common.ps1"
$fixture = Join-Path "$root\build" 'test-profile.json'
try {
    $profile = @{ Port=2082; ExpectedIPv4='203.0.113.10'; ClaudeExe=$helper; ProxyExe=$helper; ProxyConfig=$helper }
    $profile | ConvertTo-Json | Set-Content -LiteralPath $fixture -Encoding UTF8
    [void](Get-GuardProfile $fixture)
    foreach ($bad in @(@{Port=0;ExpectedIPv4='203.0.113.10'}, @{Port=2082;ExpectedIPv4='::1'})) {
        $profile.Port=$bad.Port; $profile.ExpectedIPv4=$bad.ExpectedIPv4
        $profile | ConvertTo-Json | Set-Content -LiteralPath $fixture -Encoding UTF8
        $rejected=$false
        try { [void](Get-GuardProfile $fixture) } catch { $rejected=$true }
        if (!$rejected) { throw 'Invalid profile accepted.' }
    }
} finally { Remove-Item -LiteralPath $fixture -ErrorAction SilentlyContinue }
Write-Host 'PASS: PowerShell syntax; native invalid-input rejection; profile validation. No firewall rules changed.'
