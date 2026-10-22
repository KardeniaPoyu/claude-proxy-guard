# Local-only readers. Never invoke a client API, switch its active node, or fetch subscriptions.
. "$PSScriptRoot\Common.ps1"

function Get-GuardField($Object, [string]$Name, $Default = $null) {
    if ($null -eq $Object) { return $Default }
    if ($Object -is [Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
    } elseif ($Object.PSObject.Properties[$Name]) { return $Object.$Name }
    return $Default
}

function Read-GuardProxyDocument([string]$Path) {
    Assert-GuardPath $Path -MustExist
    $file = Get-Item -LiteralPath $Path
    if ($file.Length -gt 4MB -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Config must be a regular local file no larger than 4 MB.' }
    $text = [IO.File]::ReadAllText($Path)
    try {
        if ($text.TrimStart().StartsWith('{')) { return ($text | ConvertFrom-Json -ErrorAction Stop) }
        $dll = Join-Path $script:GuardRoot 'bin\YamlDotNet.dll'
        if (!(Test-Path -LiteralPath $dll) -or (Get-FileHash $dll -Algorithm SHA256).Hash -ne '9172f0758ed76963e0ede3b5ca9a1fb5b82f64c7e7a92cb3a6de39efa933a668') {
            throw 'Verified YAML parser missing. Use the release ZIP or run Restore-Dependencies.ps1.'
        }
        if (!('YamlDotNet.RepresentationModel.YamlStream' -as [type])) { Add-Type -Path $dll }
        # Reject aliases before building a graph: no alias expansion bombs, cycles or YAML merge keys.
        $reader = New-Object IO.StringReader($text)
        try {
            $parser = New-Object YamlDotNet.Core.Parser($reader)
            $events = 0
            while ($parser.MoveNext()) {
                if (++$events -gt 60000 -or $parser.Current -is [YamlDotNet.Core.Events.AnchorAlias]) { throw 'Aliases or oversized YAML are not supported.' }
            }
        } finally { $reader.Dispose() }
        $stream = New-Object YamlDotNet.RepresentationModel.YamlStream
        $reader = New-Object IO.StringReader($text)
        try { $stream.Load($reader) } finally { $reader.Dispose() }
        if ($stream.Documents.Count -ne 1) { throw 'Expected one YAML document.' }
        function Convert-GuardYamlNode($Node, [int]$Depth = 0) {
            if ($Depth -gt 24) { throw 'Config nesting is too deep.' }
            $tag = $Node.Tag.ToString()
            if ($tag -and $tag -notin @('?','!','tag:yaml.org,2002:map','tag:yaml.org,2002:seq','tag:yaml.org,2002:str','tag:yaml.org,2002:int','tag:yaml.org,2002:bool','tag:yaml.org,2002:null','tag:yaml.org,2002:float')) { throw 'Custom YAML tags are not supported.' }
            if ($Node -is [YamlDotNet.RepresentationModel.YamlMappingNode]) {
                $map = [ordered]@{}
                foreach ($pair in $Node.Children.GetEnumerator()) {
                    if ($pair.Key -isnot [YamlDotNet.RepresentationModel.YamlScalarNode]) { throw 'Only scalar mapping keys are supported.' }
                    $key = $pair.Key.Value
                    if ($key -eq '<<' -or $map.Contains($key)) { throw 'Duplicate keys and YAML merges are not supported.' }
                    $map[$key] = Convert-GuardYamlNode $pair.Value ($Depth + 1)
                }
                return $map
            }
            if ($Node -is [YamlDotNet.RepresentationModel.YamlSequenceNode]) {
                $items = @($Node.Children | ForEach-Object { Convert-GuardYamlNode $_ ($Depth + 1) })
                return ,$items
            }
            if ($Node -isnot [YamlDotNet.RepresentationModel.YamlScalarNode]) { throw 'Unsupported YAML node.' }
            $value = [string]$Node.Value
            if ($Node.Style.ToString() -eq 'Plain' -and $tag -ne 'tag:yaml.org,2002:str') {
                if ($value -ceq 'true') { return $true }; if ($value -ceq 'false') { return $false }
                if ($value -in @('null','~','')) { return $null }
                $number = 0L
                if ($value -match '^-?(0|[1-9][0-9]*)$' -and [long]::TryParse($value, [ref]$number)) { return $number }
            }
            return $value
        }
        $data = Convert-GuardYamlNode $stream.Documents[0].RootNode
        return ($data | ConvertTo-Json -Depth 32 | ConvertFrom-Json)
    } catch {
        # Parser exceptions may contain passwords, URLs or source lines. Do not echo them.
        throw 'Config could not be read safely. Use valid JSON or simple YAML without aliases, custom tags or duplicate keys. YAML needs the verified parser.'
    }
}

function Get-GuardNodeCatalog($Document) {
    $list = @(Get-GuardField $Document 'proxies' @())
    if ($list.Count) {
        for ($i=0; $i -lt $list.Count; $i++) {
            $node = $list[$i]
            if ((Get-GuardField $node 'type' '') -in @('ss','ssr','vmess','vless','trojan','hysteria','hysteria2','tuic','http','socks5','snell','anytls')) {
                [pscustomobject]@{Index=$i; Engine='mihomo'; Name=([string](Get-GuardField $node 'name' 'Unnamed') -replace '[\x00-\x1F\x7F]', '?'); Protocol=[string]$node.type}
            }
        }
        return
    }
    $list = @(Get-GuardField $Document 'outbounds' @())
    for ($i=0; $i -lt $list.Count; $i++) {
        $node = $list[$i]; $type = [string](Get-GuardField $node 'type' '')
        $protocol = [string](Get-GuardField $node 'protocol' '')
        $engine = ''; $kind = ''
        if ($type -in @('shadowsocks','vmess','vless','trojan','hysteria','hysteria2','tuic','http','socks','anytls')) { $engine='sing-box'; $kind=$type }
        elseif ($protocol -in @('vmess','vless','shadowsocks','trojan','http','socks')) { $engine='xray'; $kind=$protocol }
        if ($engine) { [pscustomobject]@{Index=$i; Engine=$engine; Name=([string](Get-GuardField $node 'tag' "Node $i") -replace '[\x00-\x1F\x7F]', '?'); Protocol=$kind} }
    }
}

function Get-GuardCoreKind([string]$Path) {
    switch -Regex ([IO.Path]::GetFileName($Path)) {
        '^(sing-box|sing_box)(-[^\\]*)?\.exe$' { return 'sing-box' }
        '^(mihomo|clash)(-(windows|win|amd64|386|arm64|meta)[^\\]*)?\.exe$' { return 'mihomo' }
        '^xray\.exe$' { return 'xray' }
        '^v2ray\.exe$' { return 'v2ray' }
        default { return '' }
    }
}

function Find-GuardProxyConfig([string[]]$SearchDirectory = @(), [switch]$OnlySearchDirectory) {
    $roots = New-Object 'Collections.Generic.List[string]'
    $configs = @{}; $cores = @{}
    $defaultRoots=@(
        "$env:APPDATA\nekoray", "$env:LOCALAPPDATA\nekoray", "$env:APPDATA\v2rayN",
        "$env:APPDATA\io.github.clash-verge-rev.clash-verge-rev", "$env:APPDATA\io.github.clash-verge.clash-verge",
        "$env:USERPROFILE\.config\clash", "$env:USERPROFILE\.config\mihomo",
        "$env:APPDATA\clash_win", "$env:LOCALAPPDATA\Programs\Clash Verge"
    )
    if ($OnlySearchDirectory) { $defaultRoots=@() }
    foreach ($root in @($SearchDirectory) + $defaultRoots) { if (Test-Path -LiteralPath $root -PathType Container) { $roots.Add((Resolve-Path -LiteralPath $root).Path) } }
    # Only inspect command lines for known proxy/client process names, never dump them.
    $processes=@()
    if (!$OnlySearchDirectory) { $processes = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -match '^(nekoray|nekobox|v2rayN|v2ray|xray|sing-box|mihomo|clash|Clash Verge|clash-verge)(-[^\\]*)?\.exe$' }) }
    foreach ($process in $processes) {
        if (!$process.ExecutablePath) { continue }
        $dir = Split-Path $process.ExecutablePath; $roots.Add($dir)
        $kind = Get-GuardCoreKind $process.ExecutablePath
        if ($kind) { $cores[$process.ExecutablePath] = $kind }
        if ($process.CommandLine) {
            foreach ($match in [regex]::Matches($process.CommandLine, '(?:^|\s)(?:-c|-config|--config|-f)\s+(?:"([^"]+)"|(\S+))')) {
                $candidate = $match.Groups[1].Value; if (!$candidate) { $candidate=$match.Groups[2].Value }
                if ($candidate -match '^[A-Za-z]:\\' -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { $configs[$candidate] = $process.ExecutablePath }
            }
        }
    }
    foreach ($root in @($roots | Select-Object -Unique)) {
        # Bounded search; no whole-disk crawl and no following directory junctions.
        $queue = New-Object Collections.Queue; $queue.Enqueue(@($root,0)); $seen=0
        while ($queue.Count -and $seen -lt 1500) {
            $item = $queue.Dequeue()
            foreach ($entry in @(Get-ChildItem -LiteralPath $item[0] -Force -ErrorAction SilentlyContinue)) {
                if (++$seen -gt 1500) { break }
                if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                if ($entry.PSIsContainer) {
                    if ($item[1] -lt 3 -and $entry.Name -notmatch '^(logs?|cache|node_modules|\.git|webview.*)$') { $queue.Enqueue(@($entry.FullName,($item[1]+1))) }
                } else {
                    $kind=Get-GuardCoreKind $entry.Name
                    if ($kind) { $cores[$entry.FullName]=$kind }
                    if ($entry.Extension -in @('.json','.yaml','.yml') -and $entry.Length -le 4MB -and !$configs.ContainsKey($entry.FullName)) { $configs[$entry.FullName]='' }
                }
            }
        }
    }
    foreach ($path in @($configs.Keys | Sort-Object)) {
        try {
            $doc=Read-GuardProxyDocument $path; $nodes=@(Get-GuardNodeCatalog $doc)
            if (!$nodes.Count) { continue }
            $engine=$nodes[0].Engine; $owner=$configs[$path]
            $compatible=@($cores.Keys | Where-Object { $cores[$_] -eq $engine -or ($engine -eq 'xray' -and $cores[$_] -eq 'v2ray') } | Sort-Object)
            if ($owner -and $compatible -contains $owner) { $core=$owner }
            elseif ($compatible.Count -eq 1) { $core=$compatible[0] }
            else { $core='' }
            [pscustomobject]@{ConfigPath=$path; Engine=$engine; NodeCount=$nodes.Count; CoreExe=$core; CandidateCores=$compatible}
        } catch { continue }
    }
}
