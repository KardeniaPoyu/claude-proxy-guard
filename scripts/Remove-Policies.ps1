param([string]$ProfileDirectory = "$env:LOCALAPPDATA\ClaudeProxyGuard\default")
. "$PSScriptRoot\Common.ps1"
# Does not delete tokens, profiles, projects or any other firewall rules.
$p = Read-GuardPolicyManifest (Join-Path $ProfileDirectory 'profile.json')
Invoke-GuardPolicy $p 'remove'
Write-Host 'Recorded policies removed. Profile and encrypted token were preserved.'
