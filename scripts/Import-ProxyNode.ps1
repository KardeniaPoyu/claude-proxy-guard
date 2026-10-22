param(
    [Parameter(Mandatory)][string]$ConfigPath,
    [Parameter(Mandatory)][int]$NodeIndex,
    [Parameter(Mandatory)][string]$CoreExe,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [int]$Port=2082,
    [string]$ServerIPv4,
    [switch]$ModernSingBox
)
. "$PSScriptRoot\ProxyImport.ps1"
if (Test-GuardAdministrator) { throw 'Import as your normal Windows user.' }
Assert-GuardPath $OutputDirectory
Assert-GuardPath $CoreExe -MustExist
if (Test-Path -LiteralPath $OutputDirectory) { throw 'Choose a new directory. Existing proxy files are never overwritten.' }
if (@(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue).Count) { throw 'That local port is already in use. Choose another port.' }
$doc=Read-GuardProxyDocument $ConfigPath
$choice=@(Get-GuardNodeCatalog $doc | Where-Object { $_.Index -eq $NodeIndex })
if ($choice.Count -ne 1) { throw 'Choose a concrete node from the catalog.' }
$engine=Get-GuardCoreKind $CoreExe
if ($engine -ne $choice[0].Engine -and !($engine -eq 'v2ray' -and $choice[0].Engine -eq 'xray')) { throw 'Select the matching core executable, not the client GUI.' }
$server=Get-GuardNodeServer $doc $NodeIndex
if (!$ServerIPv4) {
    $address=$null
    if ([Net.IPAddress]::TryParse($server,[ref]$address)) {
        if ($address.AddressFamily -ne 'InterNetwork') { throw 'An IPv4 upstream is required.' }
        $ServerIPv4=$address.ToString()
    } else {
        Write-Host 'Resolving the proxy SERVER hostname once with Windows DNS (bootstrap only). No subscription is downloaded.'
        $answers=@(Resolve-DnsName -Name $server -Type A -DnsOnly -ErrorAction Stop | Where-Object { $_.Type -eq 'A' })
        if (!$answers.Count) { throw 'No upstream IPv4 found.' }
        $ServerIPv4=$answers[0].IPAddress
    }
}
$config=New-GuardDedicatedConfig $doc $NodeIndex $Port $ServerIPv4 -ModernSingBox:$ModernSingBox
New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
Set-GuardPrivateDirectory $OutputDirectory
$output=Join-Path $OutputDirectory 'proxy-config.json'
Write-GuardJsonAtomic $config $output
$argsLine=Get-GuardCoreArguments $engine $output -Check
$out=Join-Path $OutputDirectory 'check.stdout.tmp'; $err=Join-Path $OutputDirectory 'check.stderr.tmp'
try {
    $check=Start-Process -FilePath $CoreExe -ArgumentList $argsLine -WorkingDirectory $OutputDirectory -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
    # Cache the handle before waiting: Windows PowerShell 5.1 can otherwise return
    # a null ExitCode for a quickly exiting Start-Process -PassThru child.
    $checkHandle=$check.Handle
    if (!$check.WaitForExit(30000)) { $check.Kill(); throw 'Core config validation timed out.' }
    if ($check.ExitCode -ne 0) { throw 'Core rejected the isolated config. For sing-box 1.12+ retry a NEW directory with -ModernSingBox. See client-discovery.md for supported formats.' }
} finally {
    foreach ($file in @($out,$err)) { if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force } }
}
$manifest=@{SchemaVersion=1;Engine=$engine;ProxyExe=$CoreExe;ProxyConfig=$output;Port=$Port;ProxyExeHash=(Get-FileHash $CoreExe -Algorithm SHA256).Hash;ProxyConfigHash=(Get-FileHash $output -Algorithm SHA256).Hash}
Write-GuardJsonAtomic $manifest (Join-Path $OutputDirectory 'proxy.json')
Write-Host 'Imported one node into a private directory. Original client untouched; no TUN, API, selector, fallback, subscription update or autostart copied.'
