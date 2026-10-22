param([string]$ProfileDirectory = "$env:LOCALAPPDATA\ClaudeProxyGuard\default")
. "$PSScriptRoot\Common.ps1"
$file = Join-Path $ProfileDirectory 'profile.json'
$p = Get-GuardProfile $file
if ((Get-FileHash -LiteralPath (Get-GuardHelper) -Algorithm SHA256).Hash -ne $p.HelperHash) { throw 'Helper changed. Review the release and reinitialize the profile instead of updating executable pins.' }
Assert-GuardApplicationsStopped $p
Invoke-GuardPolicy $p 'check'
$changed = @($p.Applications | Where-Object { (Get-FileHash -LiteralPath $_.Path -Algorithm SHA256).Hash -ne $_.Sha256 })
if (!$changed.Count) { Write-Host 'Executable pins are current.'; return }
Write-Host 'Verify these updates came from official/trusted sources before approving:'
$changed | ForEach-Object { Write-Host $_.Path }
if ((Read-Host 'Type UPDATE to trust these executable updates at the same paths') -cne 'UPDATE') { throw 'Pins unchanged.' }
foreach ($a in $changed) { $a.Sha256 = (Get-FileHash -LiteralPath $a.Path -Algorithm SHA256).Hash }
Write-GuardJsonAtomic $p $file
Write-Host 'Executable pins updated. WFP rules and proxy configuration were not changed.'
