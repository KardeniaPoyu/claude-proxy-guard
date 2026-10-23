# Read-only diagnostics. Load Common.ps1 first. Never export private exception text.
function Get-GuardProbeTargets {
    @(
        [pscustomobject]@{ Id='exit.ipify'; Kind='ipv4'; Url='https://api.ipify.org' }
        [pscustomobject]@{ Id='exit.cloudflare'; Kind='trace'; Url='https://www.cloudflare.com/cdn-cgi/trace' }
        [pscustomobject]@{ Id='exit.ipv6'; Kind='ipv6'; Url='https://api6.ipify.org' }
        [pscustomobject]@{ Id='service.web'; Kind='http'; Url='https://claude.ai/' }
        [pscustomobject]@{ Id='service.api'; Kind='http'; Url='https://api.anthropic.com/v1/models' }
        [pscustomobject]@{ Id='service.release'; Kind='release'; Url='https://downloads.claude.ai/claude-code-releases/latest' }
    )
}

function New-GuardDiagnosticCheck([string]$Id,
    [ValidateSet('PASS','FAIL','WARN','NOT_CHECKED')][string]$Status,
    [string]$Summary, [string]$NextStep='', $Evidence=@{}) {
    [pscustomobject][ordered]@{ Id=$Id; Status=$Status; Summary=$Summary; NextStep=$NextStep; Evidence=$Evidence }
}

function Read-GuardProbeBody([IO.Stream]$Stream, [long]$ContentLength, [Diagnostics.Stopwatch]$Timer) {
    if ($ContentLength -gt 8192) { return [pscustomobject]@{Outcome='TooLarge';Body=''} }
    $bytes=New-Object byte[] 8193; $length=0
    while ($true) {
        if ($Timer.ElapsedMilliseconds -gt 12000) { return [pscustomobject]@{Outcome='Timeout';Body=''} }
        if ($Stream.CanTimeout) { $Stream.ReadTimeout=[Math]::Max(1,[Math]::Min(3000,12000-[int]$Timer.ElapsedMilliseconds)) }
        $n=$Stream.Read($bytes,$length,$bytes.Length-$length)
        if ($n -eq 0) { break }
        $length+=$n
        if ($length -gt 8192) { return [pscustomobject]@{Outcome='TooLarge';Body=''} }
    }
    if ($ContentLength -ge 0 -and $ContentLength -ne $length) { return [pscustomobject]@{Outcome='IncompleteBody';Body=''} }
    $encoding=New-Object Text.UTF8Encoding($false,$true)
    [pscustomobject]@{Outcome='Http';Body=$encoding.GetString($bytes,0,$length)}
}

function Invoke-GuardHttpProbe([uri]$Uri, [int]$Port, [switch]$ReadBody) {
    # Explicit HTTP CONNECT proxy. No system/PAC/env proxy, credentials, cookies,
    # redirects, retries or direct fallback. Production targets are fixed above.
    if ($Uri.Scheme -ne 'https' -or $Uri.UserInfo -or $Uri.IsLoopback -or $Uri.Port -ne 443 -or $Port -lt 1 -or $Port -gt 65535) {
        throw 'Diagnostics require HTTPS on port 443 and a valid loopback proxy port.'
    }
    $result=[ordered]@{ Outcome='NetworkFailure'; HttpStatus=0; Body=''; Challenge=$false }
    $request=$null; $response=$null; $stream=$null; $deadline=$null
    $timer=[Diagnostics.Stopwatch]::StartNew()
    try {
        if ($null -ne [Net.ServicePointManager]::ServerCertificateValidationCallback) {
            $result.Outcome='CustomTlsCallback'; return [pscustomobject]$result
        }
        # No PAC or proxy bypass list. Loopback destinations are rejected above:
        # .NET Framework treats them specially even with an explicit IWebProxy.
        if (-not ('GuardDiagnosticFixedProxy' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Net;
using System.Threading;
public sealed class GuardDiagnosticFixedProxy : IWebProxy {
    readonly Uri address;
    public GuardDiagnosticFixedProxy(int port) { address=new Uri("http://127.0.0.1:"+port); }
    public ICredentials Credentials { get; set; }
    public Uri GetProxy(Uri destination) { return address; }
    public bool IsBypassed(Uri destination) { return false; }
}
public sealed class GuardDiagnosticDeadline : IDisposable {
    readonly Timer timer;
    public GuardDiagnosticDeadline(WebRequest request) {
        timer=new Timer(state => { try { request.Abort(); } catch (ObjectDisposedException) { } }, null, 12000, Timeout.Infinite);
    }
    public void Dispose() { timer.Dispose(); }
}
'@
        }
        $proxy=New-Object GuardDiagnosticFixedProxy($Port)
        $request=[Net.HttpWebRequest][Net.WebRequest]::Create($Uri)
        $request.Proxy=$proxy
        $request.Method='GET'; $request.AllowAutoRedirect=$false; $request.KeepAlive=$false
        $request.UseDefaultCredentials=$false; $request.Credentials=$null; $request.PreAuthenticate=$false
        $request.CookieContainer=$null
        $request.UserAgent='ClaudeProxyGuard-Diagnostics/1'
        $request.Timeout=8000; $request.ReadWriteTimeout=3000
        $request.MaximumResponseHeadersLength=16
        # Also bounds body reads on runtimes whose streams lack ReadTimeout.
        $deadline=New-Object GuardDiagnosticDeadline($request)
        try { $response=[Net.HttpWebResponse]$request.GetResponse() }
        catch {
            $err=$_.Exception
            while ($err.InnerException -and $err -isnot [Net.WebException]) { $err=$err.InnerException }
            if ($err -is [Net.WebException] -and $err.Response) { $response=[Net.HttpWebResponse]$err.Response }
            else {
                if ($err -is [Net.WebException] -and $err.Status -eq [Net.WebExceptionStatus]::Timeout) { $result.Outcome='Timeout' }
                elseif ($err -is [Net.WebException] -and $err.Status -in @([Net.WebExceptionStatus]::TrustFailure,[Net.WebExceptionStatus]::SecureChannelFailure)) { $result.Outcome='TlsFailure' }
                return [pscustomobject]$result
            }
        }
        $result.HttpStatus=[int]$response.StatusCode
        $result.Challenge=($response.Headers['cf-mitigated'] -eq 'challenge')
        $result.Outcome='Http'
        if ($ReadBody -and $result.HttpStatus -eq 200) {
            # Bound bytes actually read, including chunked or lying Content-Length.
            $stream=$response.GetResponseStream()
            $bodyResult=Read-GuardProbeBody $stream $response.ContentLength $timer
            $result.Outcome=$bodyResult.Outcome; $result.Body=$bodyResult.Body
        }
    } catch { $result.Outcome='ReadFailure'; $result.Body='' }
    finally {
        if ($deadline) { $deadline.Dispose() }
        if ($stream) { $stream.Dispose() }
        if ($response) { $response.Close() }
        if ($request) { $request.Abort() }
        $timer.Stop()
    }
    [pscustomobject]$result
}

function ConvertTo-GuardProbeCheck($Target, $Result, [string]$ExpectedIPv4) {
    $evidence=[ordered]@{ Endpoint=$Target.Url; HttpStatus=[int]$Result.HttpStatus; Transport=$Result.Outcome }
    if ($Result.Outcome -ne 'Http') {
        if ($Target.Kind -eq 'ipv6') {
            return New-GuardDiagnosticCheck $Target.Id WARN 'No IPv6 reply; IPv6 blocking is NOT proven.' 'Check WFP separately. An unavailable test server or broken route gives the same result.' $evidence
        }
        $status=if ($Target.Id -eq 'exit.ipify') { 'FAIL' } else { 'WARN' }
        return New-GuardDiagnosticCheck $Target.Id $status 'The probe did not produce a complete HTTPS response.' 'Check the dedicated proxy, upstream and TLS. No direct retry was made.' $evidence
    }
    if ($Target.Kind -eq 'http') {
        $status=[int]$Result.HttpStatus
        if ($status -ge 200 -and $status -lt 300) {
            return New-GuardDiagnosticCheck $Target.Id PASS 'HTTPS endpoint responded; account access was not tested.' '' $evidence
        }
        if ($status -eq 401) { $message='HTTPS endpoint reached; HTTP 401 is expected without credentials. Login was not tested.' }
        elseif ($status -eq 403 -and $Result.Challenge) { $message='HTTPS edge reached; browser verification is required. This is not an IP reputation verdict.' }
        elseif ($status -eq 403) { $message='HTTP 403: request refused. The cause cannot be determined from this response alone.' }
        elseif ($status -eq 429) { $message='HTTP 429: endpoint limited this request. Account quota was not tested.' }
        elseif ($status -ge 300 -and $status -lt 400) { $message='HTTP redirect received; not followed. Destination availability was not tested.' }
        else { $message='HTTPS endpoint responded with an unexpected status; service availability is unconfirmed.' }
        return New-GuardDiagnosticCheck $Target.Id WARN $message 'Inspect the HTTP status; use your configured browser for browser verification. Do not infer a ban or a clean IP.' $evidence
    }
    if ($Result.HttpStatus -ne 200) {
        $status=if ($Target.Id -eq 'exit.ipify') { 'FAIL' } else { 'WARN' }
        return New-GuardDiagnosticCheck $Target.Id $status 'Probe returned no usable data (HTTP 200 required).' 'Retry later through the same proxy; do not change the expected IP to bypass a failed check.' $evidence
    }
    if ($Target.Kind -eq 'release') {
        if ($Result.Body.Length -le 64 -and $Result.Body.Trim() -cmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') {
            $evidence.LatestVersion=$Result.Body.Trim()
            return New-GuardDiagnosticCheck $Target.Id PASS 'Release version metadata is valid; no executable was downloaded or updated.' '' $evidence
        }
        return New-GuardDiagnosticCheck $Target.Id WARN 'Release endpoint returned invalid version metadata.' 'A 200 HTML/challenge page is not a working update check.' $evidence
    }
    $value=$Result.Body.Trim()
    if ($Target.Kind -eq 'trace') {
        $ipLines=@($value -split '\r?\n' | Where-Object { $_ -cmatch '^ip=' })
        if ($ipLines.Count -ne 1) { $value='' } else { $value=$ipLines[0].Substring(3).Trim() }
    }
    $address=$null
    if ($value.Length -gt 64 -or $value.Contains('%') -or ![Net.IPAddress]::TryParse($value,[ref]$address)) {
        $status=if ($Target.Id -eq 'exit.ipify') { 'FAIL' } else { 'WARN' }
        return New-GuardDiagnosticCheck $Target.Id $status 'Response was not a valid exit address.' 'Raw responses are not retained. Retry the same endpoint later.' $evidence
    }
    $family=if ($address.AddressFamily -eq 'InterNetwork') { 'IPv4' } else { 'IPv6' }
    $evidence.AddressFamily=$family
    $evidence.MatchesExpectedIPv4=($family -eq 'IPv4' -and $address.ToString() -eq $ExpectedIPv4)
    if ($Target.Kind -eq 'ipv6') {
        if ($family -eq 'IPv6') {
            return New-GuardDiagnosticCheck $Target.Id FAIL 'The proxy can exit over IPv6; this conflicts with an IPv4-only expectation.' 'Check proxy/server IPv6 routing. This is a proxy egress observation, not proof of a local browser leak.' $evidence
        }
        return New-GuardDiagnosticCheck $Target.Id WARN 'The IPv6-only probe returned IPv4; IPv6 behavior is inconclusive.' 'Check DNS interception and repeat with independent measurements.' $evidence
    }
    if (!$evidence.MatchesExpectedIPv4) {
        return New-GuardDiagnosticCheck $Target.Id FAIL 'Observed exit differs from the pinned IPv4.' 'Check the fixed upstream and destination-dependent routing. The report intentionally omits both IP addresses.' $evidence
    }
    New-GuardDiagnosticCheck $Target.Id PASS 'Observed exit matches the pinned IPv4 for this endpoint at this time.' '' $evidence
}

function Invoke-GuardDiagnostics([string]$ProfileDirectory, [switch]$VerifyPolicy, [switch]$ExtendedNetwork, [switch]$Offline) {
    $checks=New-Object 'Collections.Generic.List[object]'
    $profile=$null; $pinsOk=$false; $listenerOk=$false
    try {
        $profile=Get-GuardProfile (Join-Path $ProfileDirectory 'profile.json')
        $checks.Add((New-GuardDiagnosticCheck profile PASS 'Profile schema and required paths are valid.'))
    } catch {
        $checks.Add((New-GuardDiagnosticCheck profile FAIL 'Profile is missing, incomplete or invalid.' 'Run Setup; keep existing profiles for policy removal. Private paths and exception text are not exported.'))
    }
    if ($profile) {
        try { Assert-GuardFilePins $profile; $pinsOk=$true; $checks.Add((New-GuardDiagnosticCheck pins PASS 'Pinned executable and proxy configuration hashes match.')) }
        catch { $checks.Add((New-GuardDiagnosticCheck pins FAIL 'A pinned file is missing or changed.' 'Review the changed file before updating its pin. Network probes and policy helper are skipped.')) }
        try { Assert-GuardProxyListener $profile; $listenerOk=$true; $checks.Add((New-GuardDiagnosticCheck listener PASS 'The dedicated loopback listener belongs to the pinned proxy and config path.')) }
        catch { $checks.Add((New-GuardDiagnosticCheck listener FAIL 'The dedicated proxy listener could not be verified.' 'Start the dedicated proxy and check the port/process/config. No alternate listener is used.')) }
        try { Assert-GuardLaunchInputs (Join-Path $ProfileDirectory 'claude-config') @(); $checks.Add((New-GuardDiagnosticCheck settings PASS 'No conflicting user settings or inherited authentication overrides were found.')) }
        catch { $checks.Add((New-GuardDiagnosticCheck settings FAIL 'User settings or inherited authentication/runtime values conflict with the launcher.' 'Use a fresh shell and review the independent settings. Values are never exported.')) }
        if (Test-Path -LiteralPath (Join-Path $ProfileDirectory 'token.dpapi') -PathType Leaf) {
            $checks.Add((New-GuardDiagnosticCheck credential PASS 'Encrypted credential file exists; validity and decryption were NOT tested.'))
        } else { $checks.Add((New-GuardDiagnosticCheck credential WARN 'No encrypted credential file; network tests do not require one.' 'Save your own token when ready to launch. Do not include it in a diagnostic report.')) }
    }
    if ($VerifyPolicy -and $pinsOk) {
        try { Invoke-GuardPolicy $profile 'check' | Out-Null; $checks.Add((New-GuardDiagnosticCheck wfp PASS 'The helper verified the current WFP policy contents.')) }
        catch { $checks.Add((New-GuardDiagnosticCheck wfp FAIL 'WFP verification failed or elevation was declined.' 'Check installation and approve the narrowly scoped helper. No policy was modified.')) }
    } else { $checks.Add((New-GuardDiagnosticCheck wfp NOT_CHECKED 'WFP policy contents were not verified.' 'Use -VerifyPolicy after file pins pass; administrator approval is required.')) }
    foreach ($target in @(Get-GuardProbeTargets)) {
        $requested=($target.Id -eq 'exit.ipify' -or $ExtendedNetwork)
        if ($Offline -or !$requested -or !$pinsOk -or !$listenerOk) {
            $checks.Add((New-GuardDiagnosticCheck $target.Id NOT_CHECKED 'Network probe skipped.' 'Requires verified pins/listener, network mode, and -ExtendedNetwork for optional probes.'))
            continue
        }
        try {
            $response=Invoke-GuardHttpProbe -Uri $target.Url -Port $profile.Port -ReadBody:($target.Kind -ne 'http')
            $checks.Add((ConvertTo-GuardProbeCheck $target $response $profile.ExpectedIPv4))
        } catch { $checks.Add((New-GuardDiagnosticCheck $target.Id FAIL 'The probe could not run.' 'Check the diagnostic runtime. No response, exception text or credentials were exported.')) }
    }
    $checks.Add((New-GuardDiagnosticCheck dns NOT_CHECKED 'DNS resolver egress was not measured.' 'Use a controlled unique-domain DNS test or packet capture. Matching HTTPS exits does not prove DNS isolation.'))
    $checks.Add((New-GuardDiagnosticCheck webrtc NOT_CHECKED 'Browser WebRTC was not measured by this CLI diagnostic.' 'Open a WebRTC test inside the actual configured browser. A default-browser result cannot certify a different profile.'))
    $checks.Add((New-GuardDiagnosticCheck outage NOT_CHECKED 'Proxy outage/direct-fallback behavior was not tested on this machine.' 'Use the disposable-host test plan. This diagnostic never stops a proxy, TUN, or existing connection.'))
    $checks.Add((New-GuardDiagnosticCheck background NOT_CHECKED 'Shared background agents and unlisted child executables are outside this verification.' 'Use foreground terminal/VS Code terminal sessions. Audit every actual child executable and managed setting separately.'))
    [pscustomobject][ordered]@{
        SchemaVersion=1; ProjectVersion=(Get-Content -LiteralPath (Join-Path $script:GuardRoot 'VERSION') -Raw).Trim()
        CreatedUtc=[DateTime]::UtcNow.ToString('o'); WindowsVersion=[Environment]::OSVersion.Version.ToString()
        PowerShellVersion=$PSVersionTable.PSVersion.ToString(); NetworkMode=$(if ($Offline) {'offline'} elseif ($ExtendedNetwork) {'extended'} else {'basic'})
        Scope='Point-in-time proxy diagnostics, not an account, reputation, DNS or browser safety certificate.'
        Privacy='No tokens, account data, proxy credentials, raw responses, private paths, process command lines or IP addresses are included.'
        Checks=@($checks.ToArray())
    }
}

function ConvertTo-GuardDiagnosticHtml($Report) {
    function Encode([object]$Value) { [Net.WebUtility]::HtmlEncode([string]$Value) }
    $rows=foreach ($check in $Report.Checks) {
        $status=Encode $check.Status
        '<tr><td><span class="{0}">{0}</span></td><td><b>{1}</b><p>{2}</p><p class="hint">{3}</p></td><td><pre>{4}</pre></td></tr>' -f $status,(Encode $check.Id),(Encode $check.Summary),(Encode $check.NextStep),(Encode ($check.Evidence | ConvertTo-Json -Depth 4 -Compress))
    }
    $counts=foreach ($s in @('PASS','FAIL','WARN','NOT_CHECKED')) { '{0}: {1}' -f $s,@($Report.Checks | Where-Object Status -eq $s).Count }
    @"
<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Claude Proxy Guard diagnostics</title>
<style>body{font:16px/1.6 system-ui,sans-serif;max-width:1150px;margin:40px auto;padding:0 20px;color:#182430;background:#f4f7fb}h1{margin-bottom:0}header,table,aside{background:white;padding:20px;border:1px solid #d8e0ea;border-radius:10px;margin:20px 0}table{border-collapse:collapse;width:100%}td,th{text-align:left;padding:14px;border-bottom:1px solid #d8e0ea;vertical-align:top}th{font-size:13px;color:#526273}td:first-child{white-space:nowrap}p{margin:5px 0}.hint{color:#526273;font-size:14px}pre{white-space:pre-wrap;overflow-wrap:anywhere;font-size:12px;max-width:340px}.PASS{color:#13663a}.FAIL{color:#ad2424}.WARN{color:#865600}.NOT_CHECKED{color:#526273}a{color:#1458a8}footer{font-size:13px;color:#526273}@media(max-width:700px){td,th{display:block}thead{display:none}pre{max-width:100%}}</style></head>
<body><header><h1>Claude Proxy Guard</h1><p>Network diagnostics / $(Encode $Report.ProjectVersion)</p><p class="hint">$(Encode $Report.CreatedUtc) | Windows $(Encode $Report.WindowsVersion) | PowerShell $(Encode $Report.PowerShellVersion) | $(Encode $Report.NetworkMode)</p></header>
<p><strong>$(Encode ($counts -join ' / '))</strong></p><p>$(Encode $Report.Scope)</p>
<table><thead><tr><th>Result</th><th>Finding / next step</th><th>Evidence (redacted)</th></tr></thead><tbody>$($rows -join "`n")</tbody></table>
<aside><b>Browser checks are separate</b><p>Open these links inside your configured browser profile yourself. This local report does not test or configure that browser. No result is uploaded by this report.</p><ul>
<li><a href="https://browserleaks.com/dns" rel="noreferrer noopener">BrowserLeaks: DNS resolver observation</a></li>
<li><a href="https://browserleaks.com/webrtc" rel="noreferrer noopener">BrowserLeaks: WebRTC</a></li>
<li><a href="https://ip.net.coffee/claude/" rel="noreferrer noopener">Net.Coffee: third-party Claude IP checks</a> (scores are not Anthropic verdicts)</li>
</ul><p>These external sites receive your browser's requests only when you open them. No WebRTC candidates is an inconclusive result, not proof that every route is blocked.</p></aside>
<footer>$(Encode $Report.Privacy) Review reports before sharing. No scripts, remote assets, analytics or auto-refresh.</footer></body></html>
"@
}

function Export-GuardDiagnostics($Report, [string]$ProfileDirectory) {
    Assert-GuardPath $ProfileDirectory
    $profileRoot=[IO.Path]::GetFullPath($ProfileDirectory)
    $cursor=$profileRoot
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            $item=Get-Item -LiteralPath $cursor -Force
            if (!$item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Report parent must be a regular local directory.' }
        }
        $parent=Split-Path $cursor -Parent
        if ($parent -eq $cursor) { break }; $cursor=$parent
    }
    # New unique directory: never overwrite existing reports or change their ACLs.
    $directory=Join-Path $profileRoot ('diagnostic-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $directory -ErrorAction Stop | Out-Null
    Set-GuardPrivateDirectory $directory
    Write-GuardJsonAtomic $Report (Join-Path $directory 'report.json')
    [IO.File]::WriteAllText((Join-Path $directory 'report.html'), (ConvertTo-GuardDiagnosticHtml $Report), (New-Object Text.UTF8Encoding($false)))
    return $directory
}
