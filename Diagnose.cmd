@echo off
setlocal
cd /d "%~dp0"
echo Read-only diagnostics through the dedicated proxy. No credentials are sent.
echo Contacts ipify, Cloudflare and official Claude endpoints. Does not stop any proxy.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Test-Guard.ps1" -ExtendedNetwork -ExportReport -OpenReport
pause
