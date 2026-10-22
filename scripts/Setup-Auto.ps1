param([string[]]$SearchDirectory=@())
. "$PSScriptRoot\ProxyImport.ps1"
if (Test-GuardAdministrator) { throw 'Open a normal PowerShell window. Only WFP policy installation will request elevation.' }
[void](Get-GuardHelper)
Write-Host 'Claude Proxy Guard | discover -> choose -> isolate -> verify' -ForegroundColor Cyan
Write-Host 'Reads local proxy configs. Credentials stay on this PC. Original clients remain unchanged.'
$found=@(Find-GuardProxyConfig -SearchDirectory $SearchDirectory)
for ($i=0;$i -lt $found.Count;$i++) { Write-Host ("[{0}] {1}, {2} nodes | {3}" -f ($i+1),$found[$i].Engine,$found[$i].NodeCount,$found[$i].ConfigPath) }
$select=Read-Host 'Config number, or Enter to select an exported JSON/YAML file'
$source=$null
if ($select) {
    $n=0
    if (![int]::TryParse($select,[ref]$n) -or $n -lt 1 -or $n -gt $found.Count) { throw 'Invalid config number.' }
    $source=$found[$n-1]; $config=$source.ConfigPath
} else { $config=(Read-Host 'Full path to exported config').Trim('"') }
$doc=Read-GuardProxyDocument $config
$nodes=@(Get-GuardNodeCatalog $doc)
if (!$nodes.Count) { throw 'No supported concrete nodes. Export a core config, not a subscription URL or GUI database.' }
for ($i=0;$i -lt $nodes.Count;$i++) { Write-Host ("[{0}] {1} ({2})" -f ($i+1),$nodes[$i].Name,$nodes[$i].Protocol) }
$n=0; $select=Read-Host 'Node number to dedicate to Claude (no automatic selection)'
if (![int]::TryParse($select,[ref]$n) -or $n -lt 1 -or $n -gt $nodes.Count) { throw 'Invalid node number.' }
$node=$nodes[$n-1]
$core=''; if ($source) { $core=$source.CoreExe }
if ($core) {
    Write-Host "Detected core: $core"
    $entered=Read-Host 'Enter to use this core, or type a different full .exe path'
    if ($entered) { $core=$entered.Trim('"') }
} else { $core=(Read-Host 'Full path to matching core .exe (sing-box, mihomo/clash, xray/v2ray; not the GUI)').Trim('"') }
$modern=$false
if ($node.Engine -eq 'sing-box') {
    # Version detection never reads a config, and its output is not printed.
    $versionText=(& $core version 2>$null | Out-String)
    if ($versionText -match 'sing-box version (\d+)\.(\d+)') { $modern=([int]$Matches[1] -gt 1 -or [int]$Matches[2] -ge 12) }
    else { $modern=((Read-Host 'Is your sing-box version 1.12 or newer? [y/N]') -eq 'y') }
}
$claudeCommand=Get-Command claude.exe -ErrorAction SilentlyContinue
$claude=if ($claudeCommand) { $claudeCommand.Source } else { '' }
$entered=Read-Host "Native claude.exe path [$claude]"
if ($entered) { $claude=$entered.Trim('"') }
Assert-GuardPath $claude -MustExist
$dir=Read-Host 'New profile directory [Enter for default]'
if (!$dir) { $dir="$env:LOCALAPPDATA\ClaudeProxyGuard\default" }
Assert-GuardPath $dir
if (Test-Path -LiteralPath $dir) { throw 'That profile already exists. Choose a new name; existing profiles are preserved.' }
$runtime=$dir+'-proxy'
$port=2082
while (@(Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue).Count -and $port -lt 2182) { $port++ }
$entered=Read-Host "Dedicated HTTP port [$port]"
if ($entered) { $port=[int]$entered }
Write-Host 'The next step copies ONE node and its credentials to a private local directory, validates it, then starts a separate core process.'
Write-Host 'If the node uses a hostname, Windows DNS resolves that SERVER once; its IPv4 is then pinned. Original subscriptions are not fetched.'
if ((Read-Host 'Continue with the selected node? [y/N]') -ne 'y') { return }
& "$PSScriptRoot\Import-ProxyNode.ps1" -ConfigPath $config -NodeIndex $node.Index -CoreExe $core -OutputDirectory $runtime -Port $port -ModernSingBox:$modern
& "$PSScriptRoot\Start-ImportedProxy.ps1" -Directory $runtime
try {
    $ip=(& "$env:SystemRoot\System32\curl.exe" -q --fail --silent --show-error --max-time 15 --connect-timeout 8 --proto '=https' --noproxy localhost --proxy "http://127.0.0.1:$port" https://api.ipify.org | Out-String).Trim()
    $parsed=$null
    if ($LASTEXITCODE -ne 0 -or ![Net.IPAddress]::TryParse($ip,[ref]$parsed) -or $parsed.AddressFamily -ne 'InterNetwork') { throw 'Expected an IPv4 exit through the imported proxy.' }
    Write-Host "Observed public IPv4: $ip"
    if ((Read-Host 'Compare it with your node provider. Type this IPv4 to pin and continue') -ne $ip) { throw 'Exit not confirmed. No Claude profile was installed.' }
    Write-Host 'Close Claude before continuing. Windows will request elevation only for its WFP policy.'
    & "$PSScriptRoot\Initialize-Profile.ps1" -ClaudeExe $claude -ProxyExe $core -ProxyConfig (Join-Path $runtime 'proxy-config.json') -ExpectedIPv4 $ip -Port $port -ProfileDirectory $dir -ImportedProxyDirectory $runtime
    if ((Read-Host 'Save an existing setup-token now? [y/N]') -eq 'y') { & "$PSScriptRoot\Save-Token.ps1" -ProfileDirectory $dir }
    if ((Read-Host 'Create Claude desktop shortcut? [y/N]') -eq 'y') { & "$PSScriptRoot\New-DesktopShortcut.ps1" -ProfileDirectory $dir }
    Write-Host "Ready. Proxy directory: $runtime"
    Write-Host 'The Claude shortcut starts this proxy on demand. Stop-ImportedProxy.ps1 stops only this instance. No login autostart is installed.'
    Write-Host 'If you have no token yet: Start-Guard.ps1 -SetupToken, then Save-Token.ps1 (use your new ProfileDirectory).'
} catch {
    & "$PSScriptRoot\Stop-ImportedProxy.ps1" -Directory $runtime
    throw
}
