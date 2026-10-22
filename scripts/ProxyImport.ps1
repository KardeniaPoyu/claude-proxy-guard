. "$PSScriptRoot\ProxyDiscovery.ps1"

function Assert-GuardStandaloneNode($Value, [int]$Depth=0) {
    if ($Depth -gt 24) { throw 'Node nesting is too deep.' }
    if ($null -eq $Value -or $Value -is [string] -or $Value -is [ValueType]) { return }
    if ($Value -is [array]) { foreach ($v in $Value) { Assert-GuardStandaloneNode $v ($Depth+1) }; return }
    foreach ($p in $Value.PSObject.Properties) {
        # Chained nodes and external files/plugins need a separate audit; never copy them silently.
        if ($p.Name -match '^(detour|dialer-proxy|proxySettings|dialerProxy|download_detour|plugin|plugin-opts|certificate_path|key_path|certificate-path|private-key-path|client-fingerprint-path|sendThrough|bind_interface|bind-interface|routing-mark|interface-name|fallback.*|url|path_file)$' -and $p.Value) {
            throw 'This node depends on another proxy, external file, interface or plugin. Export a standalone node instead.'
        }
        if ($p.Name -match '^(insecure|allowInsecure|skip-cert-verify)$' -and $p.Value -eq $true) { throw 'Import requires TLS certificate verification. Fix the source node first.' }
        Assert-GuardStandaloneNode $p.Value ($Depth+1)
    }
}

function Set-GuardNodeField($Object, [string]$Name, $Value) { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force }

function New-GuardDedicatedConfig($Document, [int]$NodeIndex, [int]$Port, [string]$ServerIPv4, [switch]$ModernSingBox) {
    if ($Port -lt 1024 -or $Port -gt 65535) { throw 'Choose a dedicated port between 1024 and 65535.' }
    $ip=$null
    if (![Net.IPAddress]::TryParse($ServerIPv4,[ref]$ip) -or $ip.AddressFamily -ne 'InterNetwork') { throw 'The upstream must be pinned to an IPv4 address.' }
    $bytes=$ip.GetAddressBytes()
    if ($bytes[0] -in @(0,127) -or $bytes[0] -ge 224 -or ($bytes[0] -eq 169 -and $bytes[1] -eq 254)) { throw 'Loopback, unspecified, link-local and multicast upstreams cannot be imported as a fixed remote node.' }
    $choice=@(Get-GuardNodeCatalog $Document | Where-Object { $_.Index -eq $NodeIndex })
    if ($choice.Count -ne 1) { throw 'Select one supported concrete node, not DIRECT, a selector or a fallback group.' }
    $engine=$choice[0].Engine
    $list=if ($engine -eq 'mihomo') { @(Get-GuardField $Document 'proxies') } else { @(Get-GuardField $Document 'outbounds') }
    $node=$list[$NodeIndex] | ConvertTo-Json -Depth 32 | ConvertFrom-Json
    Assert-GuardStandaloneNode $node
    $tag='guard-upstream'
    if ($engine -eq 'sing-box') {
        $hostname=[string](Get-GuardField $node 'server' '')
        if (!$hostname) { throw 'Node has no upstream server.' }
        Set-GuardNodeField $node 'tag' $tag; Set-GuardNodeField $node 'server' $ServerIPv4
        $tls=Get-GuardField $node 'tls'
        if ($tls -and (Get-GuardField $tls 'enabled' $false) -and !(Get-GuardField $tls 'server_name')) { Set-GuardNodeField $tls 'server_name' $hostname }
        # No source routes, selectors, providers, DNS settings or control APIs are carried over.
        $dns=if ($ModernSingBox) { @{servers=@(@{type='https';tag='guard-dns';server='1.1.1.1';path='/dns-query';detour=$tag});strategy='ipv4_only'} }
             else { @{servers=@(@{tag='guard-dns';address='https://1.1.1.1/dns-query';detour=$tag});strategy='ipv4_only'} }
        return @{log=@{level='warn'};dns=$dns;inbounds=@(@{type='http';tag='guard-in';listen='127.0.0.1';listen_port=$Port});outbounds=@($node);route=@{final=$tag}}
    }
    if ($engine -eq 'mihomo') {
        $hostname=[string](Get-GuardField $node 'server' '')
        if (!$hostname) { throw 'Node has no upstream server.' }
        Set-GuardNodeField $node 'name' $tag; Set-GuardNodeField $node 'server' $ServerIPv4
        if (!(Get-GuardField $node 'sni')) { Set-GuardNodeField $node 'sni' $hostname }
        if (!(Get-GuardField $node 'servername')) { Set-GuardNodeField $node 'servername' $hostname }
        return @{
            port=$Port;'allow-lan'=$false;'bind-address'='127.0.0.1';ipv6=$false;mode='rule';'log-level'='warning'
            tun=@{enable=$false};profile=@{'store-selected'=$false;'store-fake-ip'=$false}
            dns=@{enable=$true;ipv6=$false;'enhanced-mode'='fake-ip';'nameserver'=@('https://1.1.1.1/dns-query#guard-upstream')}
            proxies=@($node);rules=@('MATCH,guard-upstream')
        }
    }
    $settings=Get-GuardField $node 'settings'
    $serverKey=if (Get-GuardField $settings 'vnext') { 'vnext' } else { 'servers' }
    $servers=@(Get-GuardField $settings $serverKey @())
    if ($servers.Count -ne 1) { throw 'Xray/V2Ray import requires exactly one upstream server.' }
    $hostname=[string](Get-GuardField $servers[0] 'address' '')
    if (!$hostname) { throw 'Node has no upstream address.' }
    Set-GuardNodeField $servers[0] 'address' $ServerIPv4
    Set-GuardNodeField $node 'tag' $tag
    $stream=Get-GuardField $node 'streamSettings'
    foreach ($name in @('tlsSettings','realitySettings')) {
        $tls=Get-GuardField $stream $name
        if ($tls -and !(Get-GuardField $tls 'serverName')) { Set-GuardNodeField $tls 'serverName' $hostname }
    }
    # HTTP CONNECT target hostnames are passed to this sole outbound; no freedom/DIRECT exists.
    return @{log=@{loglevel='warning'};inbounds=@(@{listen='127.0.0.1';port=$Port;protocol='http';tag='guard-in';settings=@{}});outbounds=@($node);routing=@{domainStrategy='AsIs';rules=@(@{type='field';inboundTag=@('guard-in');outboundTag=$tag})}}
}

function Get-GuardNodeServer($Document, [int]$NodeIndex) {
    $catalog=@(Get-GuardNodeCatalog $Document | Where-Object { $_.Index -eq $NodeIndex })
    if ($catalog.Count -ne 1) { throw 'Unknown node index.' }
    if ($catalog[0].Engine -eq 'mihomo') { return [string]$Document.proxies[$NodeIndex].server }
    $node=$Document.outbounds[$NodeIndex]
    if ($catalog[0].Engine -eq 'sing-box') { return [string]$node.server }
    $key=if (Get-GuardField $node.settings 'vnext') { 'vnext' } else { 'servers' }
    $servers=@(Get-GuardField $node.settings $key @())
    if ($servers.Count -ne 1) { throw 'Select a node containing exactly one upstream server.' }
    return [string]$servers[0].address
}

function Get-GuardCoreArguments([string]$Engine, [string]$ConfigPath, [switch]$Check) {
    Assert-GuardPath $ConfigPath
    switch ($Engine) {
        'sing-box' { if ($Check) { return "check -c `"$ConfigPath`"" }; return "run -c `"$ConfigPath`"" }
        'mihomo' { $dir=Split-Path $ConfigPath; if ($Check) { return "-t -d `"$dir`" -f `"$ConfigPath`"" }; return "-d `"$dir`" -f `"$ConfigPath`"" }
        { $_ -in @('xray','v2ray') } { if ($Check) { return "run -test -config `"$ConfigPath`"" }; return "run -config `"$ConfigPath`"" }
        default { throw 'Unsupported core.' }
    }
}

function Read-GuardImportedProxy([string]$Directory) {
    Assert-GuardPath $Directory
    $p=Get-Content -LiteralPath (Join-Path $Directory 'proxy.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($p.SchemaVersion -ne 1 -or [int]$p.Port -lt 1024 -or [int]$p.Port -gt 65535) { throw 'Invalid imported proxy manifest.' }
    foreach ($field in @('ProxyExe','ProxyConfig')) { Assert-GuardPath $p.$field -MustExist }
    if ((Get-FileHash $p.ProxyExe -Algorithm SHA256).Hash -ne $p.ProxyExeHash -or (Get-FileHash $p.ProxyConfig -Algorithm SHA256).Hash -ne $p.ProxyConfigHash) { throw 'Imported proxy changed. Re-import and review it; no automatic repinning is allowed.' }
    [void](Get-GuardCoreArguments $p.Engine $p.ProxyConfig)
    return $p
}
