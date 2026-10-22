param([switch]$AcknowledgeIsolatedTestHost)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
. "$root\scripts\Common.ps1"
if (!$AcknowledgeIsolatedTestHost) { throw 'Run only on a disposable Windows test host, passing -AcknowledgeIsolatedTestHost.' }
if (!(Test-GuardAdministrator)) { throw 'This integration test needs an elevated disposable test host. It never prompts for UAC.' }
if (!(Get-Command cl.exe -ErrorAction SilentlyContinue)) { throw 'Use an x64 Visual Studio Developer PowerShell.' }
$helper = Get-GuardHelper
$testId = [guid]::NewGuid().ToString()
$directory = Join-Path "$root\build" "wfp-integration-$testId"
New-Item -ItemType Directory -Path $directory | Out-Null
$probe = Join-Path $directory 'restricted-probe.exe'
$server = Join-Path $directory 'unrestricted-server.exe'
$servers = New-Object System.Collections.Generic.List[object]
$results = New-Object System.Collections.Generic.List[object]
$installed = $false
function Invoke-NativePolicy([string]$Action, [int]$Port, [int]$Expected = 0, [string]$Executable = $probe) {
    & $helper $Action $Executable "$Port" $testId
    if ($LASTEXITCODE -ne $Expected) { throw "Policy $Action returned $LASTEXITCODE; expected $Expected." }
}
function Find-FreePort {
    $listener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 0)
    $listener.Start()
    try { return $listener.LocalEndpoint.Port } finally { $listener.Stop() }
}
function Start-ProbeServer([string]$Protocol, [string]$Address, [int]$Port) {
    $log = Join-Path $directory "server-$($servers.Count).out"
    $p = Start-Process -FilePath $server -ArgumentList @('serve', $Protocol, $Address, "$Port") -PassThru -WindowStyle Hidden -RedirectStandardOutput $log -RedirectStandardError "$log.err"
    $servers.Add($p)
    $deadline = [DateTime]::UtcNow.AddSeconds(8)
    while ([DateTime]::UtcNow -lt $deadline) {
        if ($p.HasExited) { throw 'Test listener exited before becoming ready.' }
        if ((Test-Path $log) -and ((Get-Content $log -Raw) -match 'READY')) { return $p }
        Start-Sleep -Milliseconds 50
    }
    throw 'Test listener readiness timeout.'
}
function Assert-Probe([string]$Name, [string]$Protocol, [string]$Address, [int]$Port, [bool]$Reachable) {
    & $probe probe $Protocol $Address "$Port"
    $expected = if ($Reachable) { 0 } else { 5 }
    if ($LASTEXITCODE -ne $expected) { throw "$Name failed: exit=$LASTEXITCODE expected=$expected" }
    $results.Add([pscustomobject]@{ name=$Name; passed=$true })
    Write-Host "PASS: $Name"
}
try {
    & cl.exe /nologo /std:c++17 /W4 /WX /EHsc /MT "/Fe:$probe" "/Fo:$directory\probe.obj" "$PSScriptRoot\native\network-probe.cpp" /link ws2_32.lib
    if ($LASTEXITCODE -ne 0) { throw 'Network probe compilation failed.' }
    Copy-Item -LiteralPath $probe -Destination $server
    $port = Find-FreePort
    do { $otherPort = Find-FreePort } while ($otherPort -eq $port)
    $primary = Start-ProbeServer 'tcp' '127.0.0.1' $port
    [void](Start-ProbeServer 'tcp' '127.0.0.1' $otherPort)
    [void](Start-ProbeServer 'tcp' '127.0.0.2' $port)
    [void](Start-ProbeServer 'tcp' '::1' $port)
    [void](Start-ProbeServer 'udp' '127.0.0.1' $port)
    Assert-Probe 'baseline permitted TCP endpoint' 'tcp' '127.0.0.1' $port $true
    Assert-Probe 'baseline alternate port reachable' 'tcp' '127.0.0.1' $otherPort $true
    Assert-Probe 'baseline alternate address reachable' 'tcp' '127.0.0.2' $port $true
    Assert-Probe 'baseline IPv6 reachable' 'tcp' '::1' $port $true
    Assert-Probe 'baseline UDP reachable' 'udp' '127.0.0.1' $port $true
    Invoke-NativePolicy 'check' $port 1
    # From here finally must remove policies even if installation partly fails.
    $installed = $true
    Invoke-NativePolicy 'install' $port
    Invoke-NativePolicy 'check' $port
    Invoke-NativePolicy 'check' $otherPort 1
    Invoke-NativePolicy 'check' $port 1 $server
    Assert-Probe 'allowed loopback TCP port' 'tcp' '127.0.0.1' $port $true
    Assert-Probe 'alternate TCP port blocked' 'tcp' '127.0.0.1' $otherPort $false
    Assert-Probe 'alternate address blocked' 'tcp' '127.0.0.2' $port $false
    Assert-Probe 'IPv6 blocked' 'tcp' '::1' $port $false
    Assert-Probe 'UDP blocked on allowed port' 'udp' '127.0.0.1' $port $false
    Stop-Process -Id $primary.Id -Force
    $primary.WaitForExit()
    Assert-Probe 'stopped proxy endpoint unavailable' 'tcp' '127.0.0.1' $port $false
    Assert-Probe 'stopped proxy cannot reach alternative endpoint' 'tcp' '127.0.0.1' $otherPort $false
    [void](Start-ProbeServer 'tcp' '127.0.0.1' $port)
    Assert-Probe 'same endpoint recovers' 'tcp' '127.0.0.1' $port $true
    Invoke-NativePolicy 'remove' $port
    $installed = $false
    Invoke-NativePolicy 'check' $port 1
    Invoke-NativePolicy 'remove' $port
    Assert-Probe 'cleanup restores alternate TCP port' 'tcp' '127.0.0.1' $otherPort $true
    Assert-Probe 'cleanup restores IPv6' 'tcp' '::1' $port $true
    Assert-Probe 'cleanup restores UDP' 'udp' '127.0.0.1' $port $true
    $results | ConvertTo-Json | Set-Content -LiteralPath "$root\build\wfp-integration-results.json" -Encoding UTF8
} finally {
    if ($installed) {
        & $helper remove $probe "$port" $testId
        if ($LASTEXITCODE -ne 0) { Write-Warning "CLEANUP FAILED: retain $directory and remove policy $testId manually." }
    }
    foreach ($p in $servers) { if (!$p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction Continue } }
}
Write-Host 'PASS: WFP integration tests completed against isolated loopback-only executables.'
exit 0
