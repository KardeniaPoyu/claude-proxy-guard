param([Parameter(Mandatory)][string]$Directory)
. "$PSScriptRoot\ProxyImport.ps1"
if (Test-GuardAdministrator) { throw 'Start the imported proxy as your normal Windows user.' }
$p=Read-GuardImportedProxy $Directory
if (@(Get-NetTCPConnection -State Listen -LocalPort $p.Port -ErrorAction SilentlyContinue).Count) {
    Assert-GuardProxyListener $p
    Write-Host 'Pinned imported proxy is already listening.'
    return
}
$argsLine=Get-GuardCoreArguments $p.Engine $p.ProxyConfig
$proc=Start-Process -FilePath $p.ProxyExe -ArgumentList $argsLine -WorkingDirectory $Directory -WindowStyle Hidden -PassThru
try {
    $ready=$false
    for ($i=0;$i -lt 40;$i++) {
        if ($proc.HasExited) { throw 'Imported proxy exited. No fallback was started.' }
        try { Assert-GuardProxyListener $p; $ready=$true; break } catch { Start-Sleep -Milliseconds 250 }
    }
    if (!$ready) { throw 'Imported proxy did not open its pinned listener.' }
    Write-GuardJsonAtomic @{ProcessId=$proc.Id;StartTimeUtc=$proc.StartTime.ToUniversalTime().ToString('o')} (Join-Path $Directory 'process.json')
    Write-Host "Started dedicated HTTP proxy on 127.0.0.1:$($p.Port). No login autostart was added."
} catch {
    if (!$proc.HasExited) { $proc.Kill() }
    throw
}
