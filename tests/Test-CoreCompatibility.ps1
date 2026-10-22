# Optional: use trusted official core binaries, as a normal Windows user.
# No real accounts/upstreams; no WFP, TUN or system proxy changes.
param([Parameter(Mandatory)][string]$SingBoxExe,[Parameter(Mandatory)][string]$MihomoExe,[Parameter(Mandatory)][string]$XrayExe)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
. "$root\scripts\ProxyImport.ps1"
$work=Join-Path "$root\build" ('core-tests-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null
$fixtures=@(
    @{Engine='sing-box';Exe=$SingBoxExe;Config='{"outbounds":[{"type":"tuic","tag":"fixture","server":"203.0.113.1","server_port":443,"uuid":"00000000-0000-0000-0000-000000000001","password":"fixture-only","tls":{"enabled":true,"server_name":"proxy.example"}}]}'},
    @{Engine='mihomo';Exe=$MihomoExe;Config='{"proxies":[{"type":"tuic","name":"fixture","server":"203.0.113.1","port":443,"uuid":"00000000-0000-0000-0000-000000000001","password":"fixture-only","sni":"proxy.example"}]}'},
    @{Engine='xray';Exe=$XrayExe;Config='{"outbounds":[{"protocol":"vless","tag":"fixture","settings":{"vnext":[{"address":"203.0.113.1","port":443,"users":[{"id":"00000000-0000-0000-0000-000000000001","encryption":"none"}]}]},"streamSettings":{"network":"tcp","security":"tls","tlsSettings":{"serverName":"proxy.example"}}}]}' }
)
$results=@()
try {
    foreach ($fixture in $fixtures) {
        $source=Join-Path $work ($fixture.Engine+'.json'); [IO.File]::WriteAllText($source,$fixture.Config)
        $output=Join-Path $work ($fixture.Engine+'-proxy')
        $port=32082
        while (@(Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue).Count -and $port -lt 32182) { $port++ }
        & "$root\scripts\Import-ProxyNode.ps1" -ConfigPath $source -NodeIndex 0 -CoreExe $fixture.Exe -OutputDirectory $output -Port $port -ModernSingBox
        & "$root\scripts\Start-ImportedProxy.ps1" -Directory $output
        try {
            $profile=Read-GuardImportedProxy $output
            Assert-GuardProxyListener $profile
            # A second start must reuse the pinned listener, never launch another core.
            $first=@(Get-NetTCPConnection -State Listen -LocalPort $port).OwningProcess
            & "$root\scripts\Start-ImportedProxy.ps1" -Directory $output
            $second=@(Get-NetTCPConnection -State Listen -LocalPort $port).OwningProcess
            if ($first -ne $second) { throw 'Repeated start replaced the proxy.' }
        } finally { & "$root\scripts\Stop-ImportedProxy.ps1" -Directory $output }
        if (@(Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue).Count) { throw 'Test listener still active after stop.' }
        $results+=@{engine=$fixture.Engine;sha256=(Get-FileHash $fixture.Exe -Algorithm SHA256).Hash;schema='pass';startIdentityStop='pass';realUpstream='not tested'}
        Write-Host "[PASS] $($fixture.Engine): schema, start, process identity, repeated start, stop"
    }
    Write-GuardJsonAtomic $results (Join-Path "$root\build" 'core-compatibility-results.json')
} finally {
    $resolved=[IO.Path]::GetFullPath($work)
    if (!$resolved.StartsWith([IO.Path]::GetFullPath("$root\build")+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing cleanup outside build.' }
    # If a test process is still running, retain the manifest for safe manual cleanup.
    $running=@(Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -and $_.CommandLine.Contains($resolved) })
    if (!$running.Count) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
