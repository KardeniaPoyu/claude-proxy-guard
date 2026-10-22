param([Parameter(Mandatory)][string]$Directory)
. "$PSScriptRoot\ProxyImport.ps1"
$p=Read-GuardImportedProxy $Directory
$stateFile=Join-Path $Directory 'process.json'
if (!(Test-Path -LiteralPath $stateFile)) { throw 'No owned process record. No process was stopped.' }
$state=Get-Content -LiteralPath $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json
$proc=Get-Process -Id $state.ProcessId -ErrorAction SilentlyContinue
if (!$proc) { Write-Host 'Imported proxy is already stopped.'; return }
if ($proc.Path -ne $p.ProxyExe -or $proc.StartTime.ToUniversalTime().Ticks -ne ([datetime]$state.StartTimeUtc).ToUniversalTime().Ticks) { throw 'Process identity changed. No process was stopped.' }
Assert-GuardProxyListener $p
$proc.Kill(); $proc.WaitForExit(5000) | Out-Null
Write-Host 'Stopped only the imported proxy. Client WFP restrictions remain installed.'
