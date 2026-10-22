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
# Explicit allowlist: never recursively package the working tree or local profile data.
foreach ($dir in @('scripts','native','docs','examples')) {
    $sourceDir = Join-Path $root $dir
    if (@(Get-ChildItem -LiteralPath $sourceDir -Recurse -Force | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count) { throw 'Refusing to package reparse points.' }
    Copy-Item -LiteralPath $sourceDir -Destination $stage -Recurse
}
foreach ($file in @('README.md','README.en.md','LICENSE','NOTICE.md','VERSION','SECURITY.md','CHANGELOG.md','CONTRIBUTING.md')) {
    Copy-Item -LiteralPath (Join-Path $root $file) -Destination $stage
}
Copy-Item -LiteralPath $helper -Destination "$stage\bin\proxy-guard.exe"
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
