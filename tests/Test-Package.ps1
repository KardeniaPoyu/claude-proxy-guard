param([Parameter(Mandatory)][string]$ZipPath)
# Exercise the extracted artifact without touching real profiles, accounts or WFP.
$ErrorActionPreference = 'Stop'
$ZipPath = (Resolve-Path -LiteralPath $ZipPath).Path
$expected = ((Get-Content -LiteralPath "$ZipPath.sha256" -Raw).Trim() -split '\s+')[0]
if ((Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256).Hash -ne $expected) { throw 'ZIP checksum mismatch.' }
$work = Join-Path (Split-Path $PSScriptRoot) ('build\package-smoke-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null
Expand-Archive -LiteralPath $ZipPath -DestinationPath $work
$roots = @(Get-ChildItem -LiteralPath $work -Directory)
if ($roots.Count -ne 1) { throw 'Expected one package root.' }
$package = $roots[0].FullName
$manifest = Get-Content -LiteralPath "$package\BUILD.json" -Raw | ConvertFrom-Json
if ($manifest.version -ne (Get-Content -LiteralPath "$package\VERSION" -Raw).Trim()) { throw 'Package version mismatch.' }
$listed = @{}
foreach ($line in Get-Content -LiteralPath "$package\SHA256SUMS.txt") {
    if ($line -notmatch '^([a-f0-9]{64})  (.+)$') { throw 'Invalid checksum entry.' }
    $hash = $Matches[1]; $relative = $Matches[2]
    if ([IO.Path]::IsPathRooted($relative) -or $relative -match '(^|[/\\])\.\.([/\\]|$)' -or $listed.ContainsKey($relative)) { throw 'Invalid or duplicate package path.' }
    $listed[$relative] = $true
    if ((Get-FileHash -LiteralPath (Join-Path $package $relative) -Algorithm SHA256).Hash -ne $hash) { throw "File checksum mismatch: $relative" }
}
$files = @(Get-ChildItem -LiteralPath $package -File -Recurse)
if ($files.Count -ne $listed.Count + 1) { throw 'Unexpected unlisted package files.' }
foreach ($required in @('Setup.cmd','Diagnose.cmd','scripts/Diagnostics.ps1','scripts/Test-Guard.ps1','bin/proxy-guard.exe','bin/YamlDotNet.dll')) {
    if (!$listed.ContainsKey($required)) { throw "Missing runtime file: $required" }
}
foreach ($script in Get-ChildItem -LiteralPath "$package\scripts" -Filter '*.ps1') {
    $tokens=$null; $errors=$null
    [void][Management.Automation.Language.Parser]::ParseFile($script.FullName,[ref]$tokens,[ref]$errors)
    if ($errors.Count) { throw "Invalid packaged script: $($script.Name)" }
}
& "$package\bin\proxy-guard.exe" invalid
if ($LASTEXITCODE -ne 2) { throw 'Packaged native helper failed argument validation.' }
Add-Type -Path "$package\bin\YamlDotNet.dll"
$parser = New-Object YamlDotNet.RepresentationModel.YamlStream
$reader = New-Object IO.StringReader('proxy: loopback')
try { $parser.Load($reader) } finally { $reader.Dispose() }
if ($parser.Documents.Count -ne 1) { throw 'Packaged YAML parser failed.' }
$testProfile = Join-Path $work 'empty-profile'
New-Item -ItemType Directory -Path $testProfile | Out-Null
$shell = (Get-Process -Id $PID).Path
& $shell -NoProfile -ExecutionPolicy Bypass -File "$package\scripts\Test-Guard.ps1" -ProfileDirectory $testProfile -Offline -ExportReport
if ($LASTEXITCODE -ne 1) { throw 'An unconfigured package must report failure, not a successful setup.' }
$json = @(Get-ChildItem -LiteralPath $testProfile -Filter report.json -Recurse)
if ($json.Count -ne 1) { throw 'Packaged diagnostics did not export JSON.' }
$report = Get-Content -LiteralPath $json[0].FullName -Raw | ConvertFrom-Json
if ($report.ProjectVersion -ne $manifest.version -or !@($report.Checks | Where-Object { $_.Id -eq 'profile' -and $_.Status -eq 'FAIL' }).Count) { throw 'Invalid packaged diagnostic result.' }
if (@($report.Checks | Where-Object { $_.Id -match '^(exit|service)\.' -and $_.Status -ne 'NOT_CHECKED' }).Count) { throw 'Offline diagnostics attempted network checks.' }
$html = Get-Content -LiteralPath (Join-Path $json[0].DirectoryName 'report.html') -Raw
if ($html -notmatch 'Content-Security-Policy' -or $html -notmatch 'NOT_CHECKED') { throw 'Packaged HTML report is incomplete.' }
Write-Host "PASS: extracted package $($manifest.version), all hashes, native helper, YAML parser, offline diagnostics and HTML/JSON reports. No real profile or WFP changes."
exit 0
