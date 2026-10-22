param(
    [string]$ProfileDirectory = "$env:LOCALAPPDATA\ClaudeProxyGuard\default",
    [string]$WorkingDirectory = "$env:USERPROFILE",
    [string]$Name = 'Claude Proxy Guard'
)
$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot 'Start-Guard.ps1'
if ($ProfileDirectory.Contains('"') -or $script.Contains('"')) { throw 'Invalid path.' }
$shell = New-Object -ComObject WScript.Shell
$link = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) "$Name.lnk"))
$link.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$link.Arguments = '-NoProfile -NoExit -File "{0}" -ProfileDirectory "{1}"' -f $script, $ProfileDirectory
$link.WorkingDirectory = (Resolve-Path -LiteralPath $WorkingDirectory).Path
$link.Description = 'Claude with verified local proxy and per-executable WFP restrictions'
$link.Save()
