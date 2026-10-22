param([string]$ProfileDirectory = "$env:LOCALAPPDATA\ClaudeProxyGuard\default")
. "$PSScriptRoot\Common.ps1"
# Does not delete tokens, profiles, projects or any other firewall rules.
$p = Get-Content -LiteralPath (Join-Path $ProfileDirectory 'profile.json') -Raw | ConvertFrom-Json
Invoke-GuardPolicy $p 'remove'
