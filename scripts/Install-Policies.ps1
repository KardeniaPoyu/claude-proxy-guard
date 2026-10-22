param([string]$ProfileDirectory = "$env:LOCALAPPDATA\ClaudeProxyGuard\default")
. "$PSScriptRoot\Common.ps1"
$p = Get-GuardProfile (Join-Path $ProfileDirectory 'profile.json')
Assert-GuardFilePins $p
Assert-GuardApplicationsStopped $p
Assert-GuardProxyListener $p
Test-GuardExit $p
Invoke-GuardPolicy $p 'install'
Write-Host 'All recorded executable policies installed.'
