# Build-time only. Release ZIPs already contain the verified parser.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$dll = Join-Path $root 'bin\YamlDotNet.dll'
$dllHash = '9172f0758ed76963e0ede3b5ca9a1fb5b82f64c7e7a92cb3a6de39efa933a668'
if ((Test-Path -LiteralPath $dll) -and (Get-FileHash $dll -Algorithm SHA256).Hash -eq $dllHash) { return }
$package = Join-Path $root 'build\yamldotnet.16.3.0.nupkg'
New-Item -ItemType Directory -Path (Split-Path $package), (Split-Path $dll) -Force | Out-Null
if (!(Test-Path -LiteralPath $package)) {
    & "$env:SystemRoot\System32\curl.exe" -q --fail --silent --show-error --location --max-time 120 --proto '=https' --proto-redir '=https' --output $package 'https://api.nuget.org/v3-flatcontainer/yamldotnet/16.3.0/yamldotnet.16.3.0.nupkg'
    if ($LASTEXITCODE -ne 0) { throw 'Dependency download failed. No parser was installed.' }
}
if ((Get-FileHash $package -Algorithm SHA256).Hash -ne 'e068bcc1243c46c8bfdfe2f27a026bfff03cde7c67d9f37c2cdd70bd24a9dfd4') { throw 'Dependency package checksum mismatch.' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead($package)
try {
    $entry = $zip.GetEntry('lib/net47/YamlDotNet.dll')
    if (!$entry) { throw 'Parser assembly missing from pinned package.' }
    [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $dll, $true)
} finally { $zip.Dispose() }
if ((Get-FileHash $dll -Algorithm SHA256).Hash -ne $dllHash) { throw 'Parser assembly checksum mismatch.' }
Write-Host 'Verified YamlDotNet 16.3.0 (MIT).'
