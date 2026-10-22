. "$PSScriptRoot\Common.ps1"
if (Test-GuardAdministrator) { throw 'Open a normal PowerShell window. Setup will elevate only the WFP helper.' }
[void](Get-GuardHelper)
Write-Host 'Claude Proxy Guard | Windows setup' -ForegroundColor Cyan
Write-Host 'Start your dedicated HTTP proxy first. Close Claude. Never paste proxy passwords into these prompts.'
$claude = (Read-Host 'Full path to native claude.exe').Trim('"')
$proxy = (Read-Host 'Full path to the running proxy executable').Trim('"')
$config = (Read-Host 'Full path to the proxy config file').Trim('"')
$ip = Read-Host 'Expected public exit IPv4'
$portText = Read-Host 'Local HTTP proxy port [2082]'
$port = 2082; if ($portText) { $port = [int]$portText }
$dir = Read-Host 'New profile directory [Enter for default]'
if (!$dir) { $dir = "$env:LOCALAPPDATA\ClaudeProxyGuard\default" }
& "$PSScriptRoot\Initialize-Profile.ps1" -ClaudeExe $claude -ProxyExe $proxy -ProxyConfig $config -ExpectedIPv4 $ip -Port $port -ProfileDirectory $dir
if ((Read-Host 'Save your existing setup-token now? [y/N]') -eq 'y') { & "$PSScriptRoot\Save-Token.ps1" -ProfileDirectory $dir }
if ((Read-Host 'Create a desktop shortcut? [y/N]') -eq 'y') { & "$PSScriptRoot\New-DesktopShortcut.ps1" -ProfileDirectory $dir }
Write-Host 'Setup complete. Use Test-Guard.ps1 -VerifyPolicy before your first session.'
