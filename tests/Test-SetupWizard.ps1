# Simulated input and fictional configs only. No real clients, network, exe launch or WFP.
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
. "$root\scripts\SetupWizard.ps1"
$work=Join-Path "$root\build" ('wizard-tests-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null
$count=0
function Assert-Test([bool]$Condition,[string]$Name) {
    if (!$Condition) { throw "FAIL: $Name" }; $script:count++; Write-Host "[PASS] $Name"
}
function Set-Answers([string[]]$Answers) { $script:answers=New-Object Collections.Queue; foreach ($answer in $Answers) { $script:answers.Enqueue($answer) } }
function Read-Host([string]$Prompt) {
    if (!$script:answers.Count) { throw 'Fixture input exhausted.' }
    return $script:answers.Dequeue()
}
try {
    Set-Answers @('wrong','0','99','2')
    Assert-Test ((Read-GuardMenu 'Choose' 2) -eq '2') 'Invalid selection retries without aborting'
    Set-Answers @('R')
    Assert-Test ((Read-GuardMenu 'Choose' 0 @('r')) -eq 'r') 'Empty discovery accepts rescan action'
    Set-Answers @('q'); $cancelled=$false
    try { Read-GuardMenu 'Choose' 1 } catch { $cancelled=$_.Exception.Message -like 'Setup cancelled*' }
    Assert-Test $cancelled 'Cancel is explicit and stops selection'
    $core=Join-Path $work 'sing-box.exe'; $gui=Join-Path $work 'v2rayN.exe'; $wrong=Join-Path $work 'mihomo.exe'
    foreach ($path in @($core,$gui,$wrong)) { [IO.File]::WriteAllText($path,'Fixture only, never execute') }
    Set-Answers @('1')
    Assert-Test ((Select-GuardCore 'sing-box' @($gui,$core,$core,$wrong)) -eq $core) 'Core menu filters incompatible GUI/engines and removes duplicates'
    Set-Answers @('f',$gui,'f',$wrong,'f',$core)
    Assert-Test ((Select-GuardCore 'sing-box') -eq $core) 'Manual incompatible core retries before execution'
    $file=Join-Path $work 'config.json'
    [IO.File]::WriteAllText($file,'{"outbounds":[{"type":"trojan","tag":"Example","server":"example.invalid","password":"fixture-secret"}]}')
    $script:scans=0; $script:lastSearch=@()
    function Find-GuardProxyConfig([string[]]$SearchDirectory=@()) {
        $script:scans++; $script:lastSearch=$SearchDirectory
        if ($script:scans -gt 1) { [pscustomobject]@{ConfigPath=$file;Engine='sing-box';NodeCount=1;CoreExe=$core;CandidateCores=@($core)} }
    }
    Set-Answers @('r','1')
    $result=Select-GuardProxySource
    Assert-Test ($result.ConfigPath -eq $file -and $script:scans -eq 2) 'Rescan refreshes the config list'
    $script:scans=0
    Set-Answers @('d',$work,'1')
    $result=Select-GuardProxySource
    Assert-Test ($result.ConfigPath -eq $file -and $script:lastSearch -contains $work) 'Portable folder is added to search scope'
    $script:scans=0
    Set-Answers @('f',(Join-Path $work 'missing.json'),'f',$file)
    $result=Select-GuardProxySource
    Assert-Test ($result.ConfigPath -eq $file -and $result.NodeCount -eq 1 -and !$result.CoreExe) 'Invalid export retries and valid export does not guess a core'
    Assert-Test (!(($result | ConvertTo-Json -Depth 5).Contains('fixture-secret'))) 'Selection metadata excludes node credentials'
    Write-Host "PASS: $count setup wizard checks. No real configuration or network changes."
} finally {
    $resolved=[IO.Path]::GetFullPath($work)
    if (!$resolved.StartsWith([IO.Path]::GetFullPath("$root\build")+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing cleanup outside build.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
