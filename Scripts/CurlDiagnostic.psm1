Set-StrictMode -Version Latest

function Get-DiagnosticFormAudit {
    param($Request, [byte[]]$Body, [string]$Keyword)
    $contentType = @($Request.headers.GetEnumerator() | Where-Object { $_.Key -ieq 'Content-Type' } | ForEach-Object { $_.Value })
    $mime = if ($contentType.Count) { ($contentType[0] -split ';', 2)[0].Trim().ToLowerInvariant() } else { '' }
    $classification = switch ($mime) {
        'application/x-www-form-urlencoded' { 'form' }
        'application/json' { 'json' }
        'multipart/form-data' { 'multipart' }
        'text/plain' { 'text' }
        '' { 'missing' }
        default { 'other' }
    }
    $method = if ($Request.method -cin @('GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS')) { $Request.method } else { 'other' }
    $valid = $null
    $matchesKeyword = $null
    $text = [System.Text.Encoding]::UTF8.GetString($Body)
    $decoded = [System.Net.WebUtility]::UrlDecode($text)
    $placeholder = ($text + $decoded + [System.Net.WebUtility]::UrlDecode($Request.url)) -match '\{\{|\}\}|@(?:get|put):\{|<js>|@js:'
    foreach ($header in $Request.headers.Values) {
        if ([System.Net.WebUtility]::UrlDecode($header) -match '\{\{|\}\}|@(?:get|put):\{|<js>|@js:') { $placeholder = $true }
    }
    if ($method -ceq 'POST' -and $classification -ceq 'form') {
        # Strict URL-encoded ASCII pairs; validate percent escapes before decoding.
        $valid = $Body.Length -gt 0 -and $text -cmatch '^(?:[A-Za-z0-9*_.+%~-]+=[A-Za-z0-9*_.+%~-]*)(?:&[A-Za-z0-9*_.+%~-]+=[A-Za-z0-9*_.+%~-]*)*$' -and $text -notmatch '%(?![0-9A-Fa-f]{2})'
        if ($valid) {
            $values = @($text.Split('&') | ForEach-Object {
                $pair = $_.Split('=', 2)
                if ([System.Net.WebUtility]::UrlDecode($pair[0]) -ceq 'searchkey') {
                    [System.Net.WebUtility]::UrlDecode($pair[1])
                }
            })
            if ($values.Count -eq 1 -and $values[0].Contains([string][char]0xfffd)) {
                $matchesKeyword = $null
            } else {
                $matchesKeyword = $values.Count -eq 1 -and $values[0] -ceq $Keyword
            }
        }
    }
    return [ordered]@{ method = $method; contentType = $classification; bodyByteCount = $Body.Length
        formEncoded = $valid; searchkeyMatchesKeyword = $matchesKeyword; unresolvedPlaceholder = [bool]$placeholder }
}

function ConvertTo-CurlConfigValue {
    param([string]$Value)
    if ($Value -match '[\x00-\x1f\x7f]') { throw 'Invalid config value.' }
    return '"' + $Value.Replace('\', '\\').Replace('"', '\"') + '"'
}

function New-CurlDiagnosticConfig {
    param($Request, [string]$Directory)
    $url = [uri]$Request.url
    if ($url.Scheme -notin @('http', 'https') -or $url.UserInfo) { throw 'Unsupported URL.' }
    if ($Request.method -cnotin @('GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS')) { throw 'Unsupported method.' }
    $credentialHeaders = @($Request.headers.Keys | Where-Object { $_ -iin @('Cookie', 'Authorization', 'Proxy-Authorization') })
    # Stop credential-bearing redirects altogether: stricter than the current cookie
    # wrapper, which reconstructs explicit headers on every hop. No trusted-location mode.
    $follow = $credentialHeaders.Count -eq 0 -and $Request.maximumRedirects -gt 0
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in @('silent', 'show-error', 'globoff', 'compressed', 'connect-timeout = 15', 'max-time = 60',
        'retry = 0', 'max-filesize = 8388608', 'proto = "=http,https"', 'proto-redir = "=http,https"',
        'write-out = "%{json}"')) { $lines.Add($line) }
    $lines.Add('max-redirs = ' + [string][Math]::Min(20, [Math]::Max(0, [int]$Request.maximumRedirects)))
    if ($follow) { $lines.Add('location') }
    $lines.Add('url = ' + (ConvertTo-CurlConfigValue $Request.url))
    $lines.Add('output = ' + (ConvertTo-CurlConfigValue (Join-Path $Directory 'curl.body')))
    if ($Request.method -ceq 'HEAD') { $lines.Add('head') }
    elseif ($Request.method -cnotin @('GET', 'POST')) { $lines.Add('request = ' + (ConvertTo-CurlConfigValue $Request.method)) }
    # --request POST persists across 301/302/303. Preserve curl's normal POST-to-GET
    # redirect behavior instead by selecting POST with data (including empty POST).
    if ($Request.hasBody -or $Request.method -ceq 'POST') {
        $lines.Add('data-binary = ' + (ConvertTo-CurlConfigValue ('@' + (Join-Path $Directory 'request.body'))))
        if ($Request.method -ceq 'GET') { $lines.Add('request = "GET"') }
    }
    foreach ($header in $Request.headers.GetEnumerator()) {
        if ($header.Key -notmatch '^[!#$%&''*+.^_`|~0-9A-Za-z-]+$') { throw 'Invalid header.' }
        $separator = if ($header.Value -eq '') { ';' } else { ': ' }
        $lines.Add('header = ' + (ConvertTo-CurlConfigValue ($header.Key + $separator + $header.Value)))
    }
    # Suppress curl defaults that RequestBuilder did not request.
    foreach ($name in @('Accept', 'Accept-Encoding', 'Content-Type', 'Expect')) {
        if ($name -notin @($Request.headers.Keys)) { $lines.Add('header = "' + $name + ':"') }
    }
    [System.IO.File]::WriteAllLines((Join-Path $Directory 'curl.config'), $lines, [System.Text.UTF8Encoding]::new($false))
    return ($credentialHeaders.Count -gt 0)
}

function Invoke-CurlDiagnostic {
    param([string]$Directory, [string]$Keyword, [string]$Executable, [string[]]$CLIArguments)
    $result = [ordered]@{ requestAudit = $null; curlExitCode = $null; errorCategory = $null
        credentialRedirectsBlocked = $null; searchDiagnostic = $null
        responseStatusCode = $null; responseByteCount = $null; responseRedirected = $null
        pageHint = $null; bookListMatchedCount = $null; finalResultCount = $null }
    try {
        if (-not (Test-Path -LiteralPath (Join-Path $Directory 'request.json'))) {
            $result.errorCategory = 'requestUnavailable'
            return $result
        }
        $request = [System.IO.File]::ReadAllText((Join-Path $Directory 'request.json')) | ConvertFrom-Json -AsHashtable
        $body = [System.IO.File]::ReadAllBytes((Join-Path $Directory 'request.body'))
        $result.requestAudit = Get-DiagnosticFormAudit $request $body $Keyword
        $result.credentialRedirectsBlocked = New-CurlDiagnosticConfig $request $Directory
        $curlName = if ($IsWindows) { 'curl.exe' } else { 'curl' }
        $curl = (Get-Command $curlName -CommandType Application -ErrorAction Stop).Source
        # -q must be first: never load a runner/user curlrc. Only a private config path
        # crosses the process command line; stdout JSON and stderr stay private.
        $code = Invoke-DiagnosticProcess -Executable $curl -Arguments @('-q', '--config', (Join-Path $Directory 'curl.config')) `
            -Directory $Directory -Prefix 'curl' -TimeoutSeconds 75
        $result.curlExitCode = $code
        # A failed transfer can still have received an HTTP status. Partial body
        # sizes are deliberately not reported as complete response measurements.
        try {
            $metadata = [System.IO.File]::ReadAllText((Join-Path $Directory 'curl.stdout')) | ConvertFrom-Json -AsHashtable
            $status = $metadata['http_code']
            if (($status -is [int] -or $status -is [long]) -and $status -ge 100 -and $status -le 599) {
                $result.responseStatusCode = $status
            }
            $redirects = $metadata['num_redirects']
            if (($redirects -is [int] -or $redirects -is [long]) -and $redirects -ge 0) {
                $result.responseRedirected = $redirects -gt 0
            }
        } catch { } # No raw metadata or errors leave the private directory.
        if ($code -ne 0) {
            $result.errorCategory = switch ($code) {
                6 { 'dns' }; 7 { 'connection' }; 28 { 'timeout' }; 124 { 'timeout' }
                { $_ -in @(35, 51, 58, 60, 77, 80, 83, 90, 91) } { 'tls' }
                47 { 'redirectLimit' }; 63 { 'responseLimit' }; default { 'curlFailed' }
            }
            return $result
        }
        $env:DIAGNOSTIC_REPLAY_DIRECTORY = $Directory
        $replayCode = Invoke-DiagnosticProcess -Executable $Executable -Arguments $CLIArguments `
            -Directory $Directory -Prefix 'replay' -TimeoutSeconds 60
        if ($replayCode -notin @(0, 1)) { throw 'Replay failed.' }
        $raw = [System.IO.File]::ReadAllText((Join-Path $Directory 'replay.stdout')) | ConvertFrom-Json -AsHashtable
        $result.searchDiagnostic = ConvertTo-PublicSearchDiagnostic $raw.searchDiagnostic
        foreach ($field in @('responseStatusCode', 'responseByteCount', 'responseRedirected', 'bookListMatchedCount', 'finalResultCount')) {
            $result[$field] = $result.searchDiagnostic[$field]
        }
        if ($null -ne $result.responseByteCount) { $result.pageHint = $result.searchDiagnostic.pageHint }
        if ($raw['errorCategory'] -cnotin @($null, 'charset', 'parse', 'comparisonFailed', 'requestUnavailable')) { throw 'Invalid replay category.' }
        $result.errorCategory = $raw['errorCategory']
        if ($result.credentialRedirectsBlocked -and $result.searchDiagnostic.responseStatusCode -in @(301,302,303,307,308)) {
            $result.errorCategory = 'credentialRedirectBlocked'
        }
    } catch {
        $result.errorCategory = 'comparisonFailed'
    } finally {
        Remove-Item Env:DIAGNOSTIC_REPLAY_DIRECTORY -ErrorAction SilentlyContinue
    }
    return $result
}

Export-ModuleMember -Function Get-DiagnosticFormAudit, New-CurlDiagnosticConfig, Invoke-CurlDiagnostic
