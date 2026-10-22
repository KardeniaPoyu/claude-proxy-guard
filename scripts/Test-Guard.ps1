param(
    [string]$ProfileDirectory = "$env:LOCALAPPDATA\ClaudeProxyGuard\default",
    [switch]$VerifyPolicy
)
. "$PSScriptRoot\Common.ps1"
$failed = $false
$p = $null
function Show-GuardCheck([string]$Name, [scriptblock]$Check) {
    try { & $Check; Write-Host "[PASS] $Name" -ForegroundColor Green }
    catch { $script:failed = $true; Write-Host "[FAIL] $Name -- $($_.Exception.Message)" -ForegroundColor Red }
}
Write-Host 'Claude Proxy Guard diagnostics (does not read token plaintext or change network rules)'
Write-Host ("Windows: {0} | PowerShell: {1}" -f [Environment]::OSVersion.VersionString, $PSVersionTable.PSVersion)
Write-Host ("Project: {0}" -f (Get-Content -LiteralPath (Join-Path $script:GuardRoot 'VERSION') -Raw).Trim())
try { $p = Get-GuardProfile (Join-Path $ProfileDirectory 'profile.json'); Write-Host '[PASS] Profile schema and paths' }
catch { Write-Error $_ -ErrorAction Continue; exit 1 }
Show-GuardCheck 'Pinned file hashes' { Assert-GuardFilePins $p }
Show-GuardCheck 'Dedicated loopback listener' { Assert-GuardProxyListener $p }
Show-GuardCheck 'Expected HTTPS exit IPv4 (contacts api.ipify.org)' { Test-GuardExit $p }
Show-GuardCheck 'User settings and inherited authentication overrides' { Assert-GuardLaunchInputs (Join-Path $ProfileDirectory 'claude-config') @() }
Show-GuardCheck 'Encrypted credential file exists (not decrypted)' {
    if (!(Test-Path -LiteralPath (Join-Path $ProfileDirectory 'token.dpapi') -PathType Leaf)) { throw 'Run Save-Token.ps1.' }
}
if ($VerifyPolicy) { Show-GuardCheck 'Actual WFP policy contents (UAC)' { Invoke-GuardPolicy $p 'check' } }
else { Write-Host '[NOT CHECKED] WFP contents; rerun with -VerifyPolicy for the administrator check.' }
if ($failed) { exit 1 }
exit 0
