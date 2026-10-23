param(
    [string]$ProfileDirectory = "$env:LOCALAPPDATA\ClaudeProxyGuard\default",
    [switch]$VerifyPolicy,
    [switch]$ExtendedNetwork,
    [switch]$Offline,
    [switch]$ExportReport,
    [switch]$OpenReport
)
. "$PSScriptRoot\Common.ps1"
. "$PSScriptRoot\Diagnostics.ps1"
if ($OpenReport -and !$ExportReport) { throw '-OpenReport requires -ExportReport.' }
if ($Offline -and $ExtendedNetwork) { throw 'Choose -Offline or -ExtendedNetwork.' }
Write-Host 'Claude Proxy Guard diagnostics: no token decryption or network rule changes.'
if (!$Offline) {
    Write-Host 'Basic mode contacts api.ipify.org through the verified proxy.'
    if ($ExtendedNetwork) { Write-Host 'Extended mode also contacts Cloudflare, api6.ipify.org, Claude web/API and release metadata. No account authorization is sent.' }
}
$report=Invoke-GuardDiagnostics $ProfileDirectory -VerifyPolicy:$VerifyPolicy -ExtendedNetwork:$ExtendedNetwork -Offline:$Offline
foreach ($check in $report.Checks) {
    $color=switch ($check.Status) { 'PASS' {'Green'} 'FAIL' {'Red'} 'WARN' {'Yellow'} default {'Gray'} }
    Write-Host ("[{0}] {1}: {2}" -f $check.Status,$check.Id,$check.Summary) -ForegroundColor $color
    if ($check.NextStep) { Write-Host ('  ' + $check.NextStep) }
}
if ($ExportReport) {
    $directory=Export-GuardDiagnostics $report $ProfileDirectory
    Write-Host "Redacted JSON + HTML report: $directory"
    if ($OpenReport) { Start-Process -FilePath (Join-Path $directory 'report.html') | Out-Null }
}
Write-Host 'NOT_CHECKED is not a pass. Exit code 0 only means no FAIL findings; it is not a safety certificate.'
if (@($report.Checks | Where-Object Status -eq 'FAIL').Count) { exit 1 }
exit 0
