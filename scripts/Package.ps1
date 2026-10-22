param([Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+(-[a-zA-Z0-9.-]+)?$')][string]$Version)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
if ((Get-Content -LiteralPath (Join-Path $root 'VERSION') -Raw).Trim() -ne $Version) { throw 'Version must match the committed VERSION file.' }
$dirty = & git -C $root status --porcelain --untracked-files=no
if ($LASTEXITCODE -ne 0 -or $dirty) { throw 'Commit tracked changes before packaging so BUILD.json identifies the actual source.' }
$helper = Join-Path $root 'bin\proxy-guard.exe'
if (!(Test-Path -LiteralPath $helper)) { throw 'Build the native helper first.' }
$dist = Join-Path $root 'dist'
$name = "claude-proxy-guard-$Version-windows-x64"
$stage = Join-Path $dist $name
if (Test-Path -LiteralPath $stage) { throw 'Package directory already exists. Choose a fresh version or inspect/remove the old package manually.' }
New-Item -ItemType Directory -Path "$stage\bin" -Force | Out-Null
# Only tracked files within the allowlist: untracked/ignored credentials in a
# documentation or script directory must never slip into a distribution.
$allowedDirs=@('scripts','native','docs','examples')
foreach ($dir in $allowedDirs) {
    $sourceDir = Join-Path $root $dir
    if (@(Get-ChildItem -LiteralPath $sourceDir -Recurse -Force | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count) { throw 'Refusing to package reparse points.' }
}
$allowedFiles=@('Setup.cmd','README.md','README.en.md','LICENSE','NOTICE.md','VERSION','SECURITY.md','CHANGELOG.md','CONTRIBUTING.md','CODE_OF_CONDUCT.md')
$tracked=@(& git -C $root -c core.quotepath=false ls-files -- @allowedDirs @allowedFiles)
if ($LASTEXITCODE -ne 0 -or !$tracked.Count) { throw 'Unable to enumerate tracked release sources.' }
foreach ($file in $tracked) {
    if ($file -match '(^|/)\.\.(/|$)' -or [IO.Path]::IsPathRooted($file)) { throw 'Invalid tracked path.' }
    $destination=Join-Path $stage $file
    New-Item -ItemType Directory -Path (Split-Path $destination) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $root $file) -Destination $destination
}
Copy-Item -LiteralPath $helper -Destination "$stage\bin\proxy-guard.exe"
$parser = Join-Path $root 'bin\YamlDotNet.dll'
if (!(Test-Path -LiteralPath $parser) -or (Get-FileHash $parser -Algorithm SHA256).Hash -ne '9172f0758ed76963e0ede3b5ca9a1fb5b82f64c7e7a92cb3a6de39efa933a668') { throw 'Run Restore-Dependencies.ps1 before packaging.' }
Copy-Item -LiteralPath $parser -Destination "$stage\bin\YamlDotNet.dll"
$commit = & git -C $root rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'Package from a Git checkout so provenance includes the commit.' }
$manifest = [ordered]@{ project='claude-proxy-guard'; version=$Version; commit="$commit".Trim(); architecture='windows-x64'; builtUtc=[DateTime]::UtcNow.ToString('o'); signed=$false }
$manifest | ConvertTo-Json | Set-Content -LiteralPath "$stage\BUILD.json" -Encoding UTF8
$files = Get-ChildItem -LiteralPath $stage -File -Recurse | Sort-Object FullName
if (@($files | Where-Object { $_.Extension -in @('.dpapi','.log','.tmp') -or $_.Name -eq 'profile.json' }).Count) { throw 'Unexpected private/runtime file in package.' }
$checksums = foreach ($file in $files) {
    $relative = $file.FullName.Substring($stage.Length + 1).Replace('\','/')
    '{0}  {1}' -f (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant(), $relative
}
$checksums | Set-Content -LiteralPath "$stage\SHA256SUMS.txt" -Encoding ASCII
$zip = Join-Path $dist "$name.zip"
Compress-Archive -LiteralPath $stage -DestinationPath $zip
('{0}  {1}' -f (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant(), (Split-Path $zip -Leaf)) | Set-Content -LiteralPath "$zip.sha256" -Encoding ASCII
Write-Host "Packaged: $zip"
