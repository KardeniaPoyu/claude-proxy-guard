$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
foreach ($file in @(Get-ChildItem "$root\scripts\*.ps1") + @(Get-ChildItem "$root\tests\*.ps1")) {
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw "$($file.Name): $errors" }
}
$helper = "$root\bin\proxy-guard.exe"
if (!(Test-Path $helper)) { throw 'Build native helper first.' }
$id = '9dca3389-07bd-4741-b617-f37618199fde'
foreach ($argsList in @(
    @('invalid'), @('install','relative.exe','2082',$id), @('check','C:\fake.exe','0',$id),
    @('check','C:\fake.exe','65536',$id), @('check','C:\fake.exe','20x',$id),
    @('check','C:\fake.exe','2082','00000000-0000-0000-0000-000000000000'),
    @('check','C:\fake.exe:stream','2082',$id), @('check','C:\..\fake.exe','2082',$id)
)) {
    & $helper @argsList
    if ($LASTEXITCODE -ne 2) { throw 'Invalid input was not rejected before opening WFP.' }
}
Write-Host 'PASS: all PowerShell syntax and eight native invalid-input cases. No firewall rules changed.'
# Expected native failures must not leak into the CI wrapper exit status.
exit 0
