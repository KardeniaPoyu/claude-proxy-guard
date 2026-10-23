# Offline fixtures + a loopback-only fake proxy. No account, public network or WFP changes.
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
. "$root\scripts\Common.ps1"
. "$root\scripts\Diagnostics.ps1"
$work=Join-Path "$root\build" ('diagnostics-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null
$count=0
function Assert-Test([bool]$Condition,[string]$Name) {
    if (!$Condition) { throw "Failed: $Name" }
    $script:count++; Write-Host "[PASS] $Name"
}
function Check-Response([string]$Id,[string]$Body,[int]$Status=200,[string]$Outcome='Http',[bool]$Challenge=$false) {
    $target=@(Get-GuardProbeTargets | Where-Object Id -eq $Id)[0]
    ConvertTo-GuardProbeCheck $target ([pscustomobject]@{Body=$Body; HttpStatus=$Status; Outcome=$Outcome; Challenge=$Challenge}) '203.0.113.10'
}
try {
    foreach ($id in @('exit.ipify','exit.cloudflare')) {
        $body=if ($id -eq 'exit.ipify') {'203.0.113.10'} else {"ip=203.0.113.10`nloc=US`nsecret=do-not-export"}
        Assert-Test ((Check-Response $id $body).Status -eq 'PASS') "$id matching IPv4"
        $body=$body.Replace('203.0.113.10','198.51.100.42')
        $check=Check-Response $id $body
        Assert-Test ($check.Status -eq 'FAIL' -and !($check | ConvertTo-Json -Depth 5).Contains('198.51.100.42')) "$id mismatch fails without exporting IP"
    }
    Assert-Test ((Check-Response exit.ipify '<html>Challenge</html>').Status -eq 'FAIL') 'HTML is not a successful primary exit check'
    Assert-Test ((Check-Response exit.cloudflare "ip=203.0.113.10`nip=198.51.100.42").Status -eq 'WARN') 'Ambiguous trace data rejected'
    Assert-Test ((Check-Response exit.ipv6 '2001:db8::10').Status -eq 'FAIL') 'Observed IPv6 egress conflicts with IPv4-only expectation'
    Assert-Test ((Check-Response exit.ipv6 '' 0 Timeout).Status -eq 'WARN') 'IPv6 timeout is inconclusive, never PASS'
    Assert-Test ((Check-Response exit.ipv6 '203.0.113.10').Status -eq 'WARN') 'IPv6-only endpoint returning IPv4 is inconclusive'
    Assert-Test ((Check-Response exit.cloudflare 'ip=fe80::1%secret').Status -eq 'WARN') 'Scoped IPv6 rejected'
    foreach ($status in @(401,403,429,302,500,404)) {
        Assert-Test ((Check-Response service.api 'not retained' $status).Status -eq 'WARN') "HTTP $status is not authentication or reputation success"
    }
    $challenge=Check-Response service.web '<script>secret</script>' 403 Http $true
    Assert-Test ($challenge.Summary -match 'browser verification' -and $challenge.Status -eq 'WARN') 'Browser challenge distinguished from unspecified 403'
    Assert-Test ((Check-Response service.web 'not retained').Status -eq 'PASS') '200 proves only HTTP response'
    Assert-Test ((Check-Response service.release "2.1.300`n").Status -eq 'PASS') 'Version metadata accepted'
    foreach ($body in @('', '2.1','2.01.300','2.1.300.1','<html>2.1.300</html>',('1'*65))) {
        Assert-Test ((Check-Response service.release $body).Status -eq 'WARN') 'Malformed/oversized version rejected'
    }
    Assert-Test ((Check-Response service.release '2.1.300' 302).Status -eq 'WARN') 'Redirected version never accepted'
    Assert-Test ((Check-Response exit.ipify '203.0.113.10' 200 IncompleteBody).Status -eq 'FAIL') 'Partial successful-looking body rejected'
    foreach ($case in @(
        @{Body='203.0.113.10';Length=12;Outcome='Http'},
        @{Body='203.0.113.10';Length=-1;Outcome='Http'},
        @{Body='203.0.113.10';Length=40;Outcome='IncompleteBody'},
        @{Body=('x'*8192);Length=-1;Outcome='Http'},
        @{Body=('x'*8193);Length=-1;Outcome='TooLarge'},
        @{Body=('x'*8193);Length=1;Outcome='TooLarge'},
        @{Body='small';Length=9000;Outcome='TooLarge'}
    )) {
        $bytes=[Text.Encoding]::UTF8.GetBytes($case.Body)
        $stream=New-Object IO.MemoryStream(,$bytes)
        $timer=[Diagnostics.Stopwatch]::StartNew()
        try {
            $body=Read-GuardProbeBody $stream $case.Length $timer
            Assert-Test ($body.Outcome -eq $case.Outcome) 'Reader bounds actual bytes and rejects truncated/oversized responses'
            if ($body.Outcome -ne 'Http') { Assert-Test ($body.Body -eq '') 'Rejected body is discarded' }
        } finally { $stream.Dispose(); $timer.Stop() }
    }
    $stream=New-Object IO.MemoryStream(,([byte[]]@(255,254,255)))
    $timer=[Diagnostics.Stopwatch]::StartNew(); $rejected=$false
    try { $null=Read-GuardProbeBody $stream 3 $timer } catch { $rejected=$true }
    finally { $stream.Dispose(); $timer.Stop() }
    Assert-Test $rejected 'Invalid UTF-8 is rejected instead of silently replaced'
    foreach ($url in @('http://example.invalid/','https://u:p@example.invalid/','https://example.invalid:444/','https://127.0.0.1/','https://[::1]/')) {
        $rejected=$false
        try { Invoke-GuardHttpProbe $url 9 | Out-Null } catch { $rejected=$true }
        Assert-Test $rejected 'Transport rejects non-HTTPS, credentials, loopback targets or custom ports'
    }

    # A real TCP listener sees the CONNECT hostname, without local target DNS.
    # Setting NO_PROXY=* and an unrelated HTTP_PROXY must not bypass our explicit proxy.
    Add-Type -TypeDefinition @'
using System;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading.Tasks;
public sealed class GuardDiagnosticFakeProxy : IDisposable {
    readonly TcpListener listener = new TcpListener(IPAddress.Loopback, 0);
    public string Request = "";
    public int Port { get { return ((IPEndPoint)listener.LocalEndpoint).Port; } }
    public Task Worker;
    public GuardDiagnosticFakeProxy() {
        listener.Start();
        Worker = Task.Run(() => {
            try {
                using (var client = listener.AcceptTcpClient()) {
                    client.ReceiveTimeout=3000;
                    var stream=client.GetStream();
                    var buffer=new byte[1]; var text=new StringBuilder();
                    while (text.Length<8192 && stream.Read(buffer,0,1)>0) {
                        text.Append((char)buffer[0]);
                        if (text.ToString().EndsWith("\r\n\r\n")) break;
                    }
                    Request=text.ToString();
                    var reply=Encoding.ASCII.GetBytes("HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
                    stream.Write(reply,0,reply.Length);
                }
            } catch (SocketException) { }
        });
    }
    public void Dispose() { listener.Stop(); Worker.Wait(4000); }
}
'@
    $oldNoProxy=$env:NO_PROXY; $oldHttpProxy=$env:HTTP_PROXY; $oldHttpsProxy=$env:HTTPS_PROXY
    $fake=New-Object GuardDiagnosticFakeProxy
    $other=New-Object GuardDiagnosticFakeProxy
    try {
        $env:NO_PROXY='*'; $env:HTTP_PROXY="http://127.0.0.1:$($other.Port)"; $env:HTTPS_PROXY=$env:HTTP_PROXY
        $actual=Invoke-GuardHttpProbe 'https://proxy-guard.invalid/' $fake.Port
        Assert-Test ($fake.Worker.Wait(4000) -and $fake.Request -match '^CONNECT proxy-guard.invalid:443 HTTP/') 'Explicit proxy used with NO_PROXY=*; target hostname goes into CONNECT'
        Assert-Test ($actual.HttpStatus -ne 200 -and $other.Request -eq '') 'Rejected CONNECT never switches to inherited alternate proxy'
        Assert-Test ($fake.Request -notmatch '(?im)^(Authorization|Proxy-Authorization|Cookie):') 'CONNECT carries no authorization or cookies'
        $port=$fake.Port; $fake.Dispose()
        $actual=Invoke-GuardHttpProbe 'https://proxy-guard.invalid/' $port
        Assert-Test ($actual.Outcome -ne 'Http' -and $other.Request -eq '') 'Stopped dedicated proxy fails without selecting an alternate proxy'
    } finally {
        $fake.Dispose(); $other.Dispose()
        $env:NO_PROXY=$oldNoProxy; $env:HTTP_PROXY=$oldHttpProxy; $env:HTTPS_PROXY=$oldHttpsProxy
    }

    # Mock local facts, not real user profiles. Prove negative gating and report privacy.
    $script:badProfile=$false; $script:badPins=$false; $script:badListener=$false; $script:networkCalls=0; $script:policyCalls=0
    function Get-GuardProfile {
        if ($script:badProfile) { throw 'private-path-C:\Users\secret token=do-not-export' }
        [pscustomobject]@{ Port=2082; ExpectedIPv4='203.0.113.10'; Private='credential-do-not-export' }
    }
    function Assert-GuardFilePins { if ($script:badPins) { throw 'private hash failure' } }
    function Assert-GuardProxyListener { if ($script:badListener) { throw 'private command line' } }
    function Assert-GuardLaunchInputs { }
    function Invoke-GuardPolicy { $script:policyCalls++ }
    function Invoke-GuardHttpProbe {
        param($Uri,$Port,[switch]$ReadBody)
        $script:networkCalls++
        [pscustomobject]@{Outcome='Http';HttpStatus=200;Body='203.0.113.10';Challenge=$false}
    }
    $report=Invoke-GuardDiagnostics $work -Offline
    Assert-Test ($script:networkCalls -eq 0 -and $script:policyCalls -eq 0) 'Offline mode does not contact endpoints or elevate'
    foreach ($id in @('dns','webrtc','outage','background','wfp')) {
        Assert-Test (@($report.Checks | Where-Object { $_.Id -eq $id -and $_.Status -eq 'NOT_CHECKED' }).Count -eq 1) "$id never inferred from IP checks"
    }
    $report=Invoke-GuardDiagnostics $work
    Assert-Test ($script:networkCalls -eq 1) 'Basic mode contacts only the primary IP endpoint'
    foreach ($condition in @('badProfile','badPins','badListener')) {
        Set-Variable -Name $condition -Value $true -Scope Script
        $script:networkCalls=0; $script:policyCalls=0
        $report=Invoke-GuardDiagnostics $work -ExtendedNetwork
        Assert-Test ($script:networkCalls -eq 0 -and @($report.Checks | Where-Object Status -eq 'FAIL').Count -gt 0) "$condition stops all network probes"
        if ($condition -ne 'badListener') {
            $null=Invoke-GuardDiagnostics $work -VerifyPolicy
            Assert-Test ($script:policyCalls -eq 0) "$condition never executes a changed/unknown helper"
        }
        Set-Variable -Name $condition -Value $false -Scope Script
    }
    $script:networkCalls=0
    $report=Invoke-GuardDiagnostics $work -ExtendedNetwork -VerifyPolicy
    Assert-Test ($script:networkCalls -eq 6 -and $script:policyCalls -eq 1) 'Extended mode runs the six fixed probes; policy check is explicit'
    $json=$report | ConvertTo-Json -Depth 10
    $html=ConvertTo-GuardDiagnosticHtml $report
    Assert-Test ($json -notmatch '203\.0\.113|do-not-export|Users\\secret' -and !$json.Contains($work)) 'Report excludes IP, credentials, private paths and exception text'
    Assert-Test ($html -notmatch '<script|<iframe|<img|<link' -and $html.Contains("default-src 'none'")) 'HTML has no remote assets/scripts and restrictive CSP'
    $report.Checks[0].Summary='<img src=x onerror=alert(1)>'
    $html=ConvertTo-GuardDiagnosticHtml $report
    Assert-Test ($html.Contains('&lt;img') -and $html -notmatch '<img') 'HTML encodes untrusted text'
    $directory=Export-GuardDiagnostics $report $work
    $saved=Get-Content -LiteralPath (Join-Path $directory 'report.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Test ($saved.Checks.Count -eq $report.Checks.Count -and (Get-Acl -LiteralPath $directory).AreAccessRulesProtected) 'JSON roundtrip and private report ACL'
    $second=Export-GuardDiagnostics $report $work
    Assert-Test ($directory -ne $second -and (Test-Path -LiteralPath (Join-Path $directory 'report.html'))) 'Export does not overwrite earlier reports'
    Write-Host "PASS: $count diagnostics tests. Only fake loopback traffic; no real account or firewall touched."
} finally {
    $build=[IO.Path]::GetFullPath((Join-Path $root 'build')) + [IO.Path]::DirectorySeparatorChar
    if (![IO.Path]::GetFullPath($work).StartsWith($build,[StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe cleanup path.' }
    Remove-Item -LiteralPath $work -Recurse -Force
}
exit 0
