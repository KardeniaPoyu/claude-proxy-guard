# Interactive local selection only. No process launch, network request or policy mutation.
. "$PSScriptRoot\ProxyDiscovery.ps1"

function Read-GuardMenu([string]$Prompt, [int]$Count, [string[]]$Actions=@()) {
    while ($true) {
        $answer = (Read-Host "$Prompt (Q = cancel)").Trim()
        if ($answer -ieq 'q') { throw 'Setup cancelled. No further changes were made.' }
        if ($Actions -contains $answer.ToLowerInvariant()) { return $answer.ToLowerInvariant() }
        $number=0
        if ([int]::TryParse($answer,[ref]$number) -and $number -ge 1 -and $number -le $Count) { return $number.ToString() }
        Write-Host 'Choose one of the displayed numbers or actions.' -ForegroundColor Yellow
    }
}

function Select-GuardProxySource([string[]]$SearchDirectory=@()) {
    $found=@(Find-GuardProxyConfig -SearchDirectory $SearchDirectory)
    while ($true) {
        Write-Host "Found $($found.Count) readable config(s). Only concrete nodes are listed; subscriptions and GUI databases are not imported."
        for ($i=0;$i -lt $found.Count;$i++) { Write-Host ("[{0}] {1}, {2} nodes | {3}" -f ($i+1),$found[$i].Engine,$found[$i].NodeCount,$found[$i].ConfigPath) }
        Write-Host '[R] Rescan after starting your proxy client  [D] Search a portable-client folder  [F] Select exported JSON/YAML'
        $choice=Read-GuardMenu 'Config number or R/D/F' $found.Count @('r','d','f')
        if ($choice -eq 'r') { $found=@(Find-GuardProxyConfig -SearchDirectory $SearchDirectory); continue }
        if ($choice -eq 'd') {
            $directory=(Read-Host 'Client folder (local absolute path; no whole-disk scan)').Trim('"')
            try {
                Assert-GuardPath $directory
                $item=Get-Item -LiteralPath $directory -ErrorAction Stop
                if (!$item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Invalid directory.' }
                $SearchDirectory=@($SearchDirectory)+@($directory)
                $found=@(Find-GuardProxyConfig -SearchDirectory $SearchDirectory)
            } catch { Write-Host 'Folder unavailable. Choose a regular local client folder.' -ForegroundColor Yellow }
            continue
        }
        if ($choice -eq 'f') {
            $path=(Read-Host 'Full path to exported JSON/YAML (not a subscription URL)').Trim('"')
            try {
                $doc=Read-GuardProxyDocument $path; $nodes=@(Get-GuardNodeCatalog $doc)
                if (!$nodes.Count) { throw 'No concrete nodes.' }
                return [pscustomobject]@{ConfigPath=$path;Engine=$nodes[0].Engine;NodeCount=$nodes.Count;CoreExe='';CandidateCores=@()}
            } catch { Write-Host 'No supported nodes could be read. Export a core config from your client; do not paste credentials here.' -ForegroundColor Yellow }
            continue
        }
        return $found[([int]$choice)-1]
    }
}

function Select-GuardCore([string]$Engine, [string[]]$Candidates=@(), [string]$Preferred='') {
    $options=@(@($Preferred)+$Candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) -and ((Get-GuardCoreKind $_) -eq $Engine -or ($Engine -eq 'xray' -and (Get-GuardCoreKind $_) -eq 'v2ray')) } | Select-Object -Unique)
    while ($true) {
        for ($i=0;$i -lt $options.Count;$i++) { Write-Host ("[{0}] {1}" -f ($i+1),$options[$i]) }
        Write-Host '[F] Choose a core executable. Use the proxy engine, not the client GUI.'
        $choice=Read-GuardMenu "Compatible $Engine core number or F" $options.Count @('f')
        $path=if ($choice -eq 'f') { (Read-Host 'Full path to core .exe').Trim('"') } else { $options[([int]$choice)-1] }
        try {
            Assert-GuardPath $path -MustExist
            $kind=Get-GuardCoreKind $path
            if ($kind -ne $Engine -and !($Engine -eq 'xray' -and $kind -eq 'v2ray')) { throw 'Wrong engine.' }
            if ((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Linked executable.' }
            return $path
        } catch { Write-Host 'Choose an existing compatible core .exe; no executable has been started by this selection step.' -ForegroundColor Yellow }
    }
}
