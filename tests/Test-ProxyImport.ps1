# Fictional nodes only; no real client scans, network requests, credentials or WFP changes.
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
. "$root\scripts\ProxyImport.ps1"
$work=Join-Path "$root\build" ('import-tests-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null
$count=0
function Assert-Test([bool]$Condition,[string]$Name) {
    if (!$Condition) { throw "FAIL: $Name" }; $script:count++; Write-Host "[PASS] $Name"
}
function Reject-Test([string]$Name,[scriptblock]$Operation) {
    $rejected=$false; try { & $Operation | Out-Null } catch { $rejected=$true }
    Assert-Test $rejected $Name
}
try {
    $sb=@'
{"outbounds":[{"type":"direct","tag":"direct"},{"type":"selector","tag":"auto","outbounds":["node","direct"]},{"type":"tuic","tag":"node","server":"proxy.example","server_port":443,"uuid":"00000000-0000-0000-0000-000000000001","password":"fixture-only","tls":{"enabled":true}},{"type":"trojan","tag":"other","server":"other.example","server_port":443,"password":"not-selected"}],"route":{"final":"auto"},"experimental":{"clash_api":{"external_controller":"127.0.0.1:9090"}}}
'@ | ConvertFrom-Json
    $before=$sb | ConvertTo-Json -Depth 32
    $nodes=@(Get-GuardNodeCatalog $sb)
    Assert-Test ($nodes.Count -eq 2 -and $nodes[0].Index -eq 2) 'Selectors and DIRECT are excluded; original indexes retained'
    $config=New-GuardDedicatedConfig $sb 2 2082 '203.0.113.10'
    Assert-Test ($config.outbounds.Count -eq 1 -and $config.route.final -eq 'guard-upstream') 'Sing-box contains one fixed upstream'
    Assert-Test ($config.outbounds[0].server -eq '203.0.113.10' -and $config.outbounds[0].tls.server_name -eq 'proxy.example') 'Upstream IPv4 pin preserves TLS hostname'
    Assert-Test ($config.inbounds[0].listen -eq '127.0.0.1' -and $config.inbounds[0].type -eq 'http') 'Dedicated listener is loopback HTTP only'
    Assert-Test ($config.dns.servers[0].detour -eq 'guard-upstream' -and $config.dns.strategy -eq 'ipv4_only') 'DNS uses selected outbound and IPv4-only answers'
    Assert-Test (!(Get-GuardField $config 'experimental')) 'Source control API is not copied'
    Assert-Test (($sb | ConvertTo-Json -Depth 32) -eq $before) 'Original config remains byte-equivalent after conversion'
    $modern=New-GuardDedicatedConfig $sb 2 2083 '203.0.113.10' -ModernSingBox
    Assert-Test ($modern.dns.servers[0].type -eq 'https') 'Modern sing-box DNS schema supported'
    Reject-Test 'Selector cannot be imported as a node' { New-GuardDedicatedConfig $sb 1 2082 '203.0.113.10' }
    Reject-Test 'Privileged local port rejected' { New-GuardDedicatedConfig $sb 2 80 '203.0.113.10' }
    Reject-Test 'IPv6-only upstream rejected' { New-GuardDedicatedConfig $sb 2 2082 '2001:db8::1' }
    Reject-Test 'Another local client cannot masquerade as a fixed remote node' { New-GuardDedicatedConfig $sb 2 2082 '127.0.0.1' }
    Set-GuardNodeField $sb.outbounds[2] 'detour' 'another-node'
    Reject-Test 'Proxy chain rejected' { New-GuardDedicatedConfig $sb 2 2082 '203.0.113.10' }
    $sb.outbounds[2].PSObject.Properties.Remove('detour')
    Set-GuardNodeField $sb.outbounds[2].tls 'insecure' $true
    Reject-Test 'Disabled TLS verification rejected' { New-GuardDedicatedConfig $sb 2 2082 '203.0.113.10' }
    $yaml=@'
mixed-port: 7890
mode: global
external-controller: 127.0.0.1:9090
secret: fixture-controller-secret
proxies:
  - name: "Test node"
    type: trojan
    server: proxy.example
    port: 443
    password: "00123"
    udp: true
proxy-groups:
  - name: Auto
    type: fallback
    proxies: ["Test node", DIRECT]
rules: ["MATCH,Auto"]
'@
    $file=Join-Path $work 'clash.yaml'; [IO.File]::WriteAllText($file,$yaml)
    $clash=Read-GuardProxyDocument $file
    [IO.File]::WriteAllText((Join-Path $work 'mihomo.exe'),'fixture, never executed')
    $found=@(Find-GuardProxyConfig -SearchDirectory @($work) -OnlySearchDirectory)
    Assert-Test ($found.Count -eq 1 -and $found[0].NodeCount -eq 1 -and $found[0].CoreExe.EndsWith('mihomo.exe')) 'Bounded directory discovery finds a config and matching core without scanning user data'
    Assert-Test ($clash.proxies[0].password -ceq '00123' -and $clash.proxies[0].udp -is [bool] -and $clash.proxies[0].port -is [ValueType]) 'YAML preserves quoted secrets, booleans and numeric ports'
    $c=New-GuardDedicatedConfig $clash 0 2082 '203.0.113.11'
    Assert-Test ($c.proxies.Count -eq 1 -and $c.rules[0] -eq 'MATCH,guard-upstream') 'Clash selection produces one node and fixed MATCH rule'
    Assert-Test (!(Get-GuardField $c 'proxy-groups') -and !(Get-GuardField $c 'secret') -and !(Get-GuardField $c 'external-controller')) 'Controller secrets and fallback groups excluded'
    Assert-Test (!$c.ipv6 -and !$c.tun.enable -and $c.dns.nameserver[0].EndsWith('#guard-upstream')) 'Clash DNS detour, TUN off, IPv6 off'
    $v=@'
{"outbounds":[{"protocol":"freedom","tag":"direct"},{"protocol":"vless","tag":"test","settings":{"vnext":[{"address":"proxy.example","port":443,"users":[{"id":"00000000-0000-0000-0000-000000000001","encryption":"none"}]}]},"streamSettings":{"network":"tcp","security":"tls","tlsSettings":{}}}]}
'@ | ConvertFrom-Json
    $x=New-GuardDedicatedConfig $v 1 2082 '203.0.113.12'
    Assert-Test ($x.outbounds.Count -eq 1 -and $x.outbounds[0].settings.vnext[0].address -eq '203.0.113.12') 'Xray/V2Ray keeps only selected proxy'
    Assert-Test ($x.outbounds[0].streamSettings.tlsSettings.serverName -eq 'proxy.example' -and $x.routing.domainStrategy -eq 'AsIs') 'Xray preserves SNI and forwards destination hostname'
    Assert-Test ((Get-GuardNodeServer $v 1) -eq 'proxy.example') 'Xray upstream hostname discovery'
    $v.outbounds[1].settings.vnext += $v.outbounds[1].settings.vnext[0]
    Reject-Test 'Multiple upstream servers rejected' { New-GuardDedicatedConfig $v 1 2082 '203.0.113.12' }
    foreach ($bad in @('a: &a [*a]',"a: 1`na: 2",'a: !custom bad',"---`na: 1`n---`nb: 2")) {
        [IO.File]::WriteAllText($file,$bad)
        Reject-Test 'Unsupported YAML rejected without source disclosure' { Read-GuardProxyDocument $file }
    }
    [IO.File]::WriteAllText($file,'{"password":"DO-NOT-LOG-THIS", broken')
    try { Read-GuardProxyDocument $file; throw 'Expected parse error' } catch { Assert-Test (!$_.Exception.Message.Contains('DO-NOT-LOG-THIS')) 'Parser error hides source credentials' }
    Assert-Test ((Get-GuardCoreKind 'C:\client\mihomo-windows-amd64.exe') -eq 'mihomo') 'Mihomo core naming detected'
    Assert-Test (!(Get-GuardCoreKind 'C:\client\v2rayN.exe')) 'GUI executable is not accepted as core'
    Assert-Test (!(Get-GuardCoreKind 'C:\client\clash-verge.exe')) 'Clash Verge GUI is not mistaken for Mihomo'
    $argsLine=Get-GuardCoreArguments 'sing-box' 'C:\private folder\proxy-config.json'
    Assert-Test ($argsLine -eq 'run -c "C:\private folder\proxy-config.json"') 'Paths with spaces are quoted as a separate config argument'
    Write-Host "PASS: $count import/parser checks. No real proxy configs were accessed."
} finally {
    $resolved=[IO.Path]::GetFullPath($work)
    if (!$resolved.StartsWith([IO.Path]::GetFullPath("$root\build")+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing cleanup outside build.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
