$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
New-Item -ItemType Directory -Force -Path "$root\bin", "$root\build" | Out-Null
if (!(Get-Command cl.exe -ErrorAction SilentlyContinue)) { throw 'Run from an x64 Visual Studio Developer PowerShell (C++ tools + Windows SDK).' }
& cl.exe /nologo /W4 /WX /EHsc /MT "/Fe:$root\bin\proxy-guard.exe" "/Fo:$root\build\proxy-guard.obj" "$root\native\proxy-guard.cpp" /link fwpuclnt.lib rpcrt4.lib
if ($LASTEXITCODE -ne 0) { throw 'Native build failed.' }
