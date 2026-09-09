# Only fixed messages, allowlisted enums, booleans and integer counts may leave
# the private runner directory. The CLI's free-form text is never a public API.
Set-StrictMode -Version Latest

function Get-DiagnosticOptions {
    param([hashtable]$Inputs, [string]$SourceJSON)
    if ([string]::IsNullOrWhiteSpace($SourceJSON)) { throw 'missingSecret' }
    if ([string]::IsNullOrWhiteSpace($Inputs.keyword) -or
        $Inputs.keyword.Length -gt 200 -or $Inputs.keyword.StartsWith('--') -or
        $Inputs.keyword -match '[\x00-\x1f\x7f]') { throw 'invalidInput' }
    $options = @{ keyword = $Inputs.keyword }
    foreach ($name in @('search_page', 'book_index', 'chapter_index', 'maximum_page_count')) {
        $minimum = if ($name -in @('search_page', 'maximum_page_count')) { 1 } else { 0 }
        $maximum = if ($name -eq 'maximum_page_count') { 10 } else { [int]::MaxValue }
        $number = 0
        if (-not [int]::TryParse($Inputs[$name], [ref]$number) -or
            $number -lt $minimum -or $number -gt $maximum) { throw 'invalidInput' }
        $options[$name] = $number
    }
    try {
        $document = [System.Text.Json.JsonDocument]::Parse($SourceJSON)
        try {
            if ($document.RootElement.ValueKind -ne [System.Text.Json.JsonValueKind]::Object) {
                throw 'invalidInput'
            }
        } finally { $document.Dispose() }
    } catch { throw 'invalidInput' }
    return $options
}

function New-DiagnosticStatus {
    param([ValidateSet('missingSecret', 'invalidInput', 'buildFailed', 'executionFailed',
        'invalidReport', 'infrastructureFailed')][string]$Status)
    $messages = @{
        missingSecret = 'Repository Secret SOURCE_DIAGNOSTIC_JSON is missing or empty.'
        invalidInput = 'Invalid inputs or source JSON. Supply one source object and valid parameter ranges.'
        buildFailed = 'CLI build or executable discovery failed. No business diagnostic was produced.'
        executionFailed = 'CLI could not complete execution. No trustworthy business report is available.'
        invalidReport = 'CLI output was missing, malformed, or inconsistent with its exit code.'
        infrastructureFailed = 'Runner setup or diagnostic infrastructure failed before a report was available.'
    }
    return [ordered]@{
        status = $Status
        successful = $false
        completedStage = $null
        searchResultCount = $null
        chapterCount = $null
        contentCharacterCount = $null
        failureCategory = $null
        failureOperation = $null
        errorSummary = $messages[$Status]
    }
}

function ConvertTo-PublicDiagnostic {
    param([string]$RawJSON, [int]$ExitCode)
    # Non-CLI process failures (including timeouts) must not look like diagnostics.
    if ($ExitCode -notin @(0, 1, 2)) { return New-DiagnosticStatus executionFailed }
    try {
        $raw = ConvertFrom-Json -InputObject $RawJSON -AsHashtable -ErrorAction Stop
        if ($raw -isnot [System.Collections.IDictionary] -or
            $raw['successful'] -isnot [bool] -or $raw['contentSucceeded'] -isnot [bool]) { throw 'schema' }
        $stages = @('import', 'search', 'bookInfo', 'toc', 'content')
        $categories = $stages + @('input', 'request', 'charset', 'ruleParser', 'selector',
            'javascript', 'unsupportedCapability')
        foreach ($field in @('completedStage', 'failureOperation', 'failureCategory')) {
            $allowed = if ($field -eq 'failureCategory') { $categories } else { $stages }
            if ($null -ne $raw[$field] -and $raw[$field] -cnotin $allowed) { throw 'schema' }
        }
        foreach ($field in @('searchResultCount', 'chapterCount', 'contentCharacterCount')) {
            $value = $raw[$field]
            if ($null -eq $value -and $field -eq 'contentCharacterCount') { continue }
            if (($value -isnot [int] -and $value -isnot [long]) -or $value -lt 0) { throw 'schema' }
        }
        if ($raw['successful'] -ne ($ExitCode -eq 0)) { throw 'exit mismatch' }
        if ($raw['successful'] -and ($raw['completedStage'] -cne 'content' -or
            -not $raw['contentSucceeded'] -or $null -eq $raw['contentCharacterCount'] -or
            $null -ne $raw['failureCategory'] -or $null -ne $raw['failureOperation'])) { throw 'schema' }
        if (-not $raw['successful'] -and $null -eq $raw['failureCategory']) { throw 'schema' }

        $messages = @{
            input = 'The source input could not be read or imported.'
            import = 'Source import failed.'
            search = 'Search parsing or result selection failed.'
            bookInfo = 'Book information parsing failed.'
            toc = 'TOC parsing, pagination or chapter selection failed.'
            content = 'Content parsing or pagination failed.'
            request = 'Request construction or network execution failed.'
            charset = 'Response character decoding failed.'
            ruleParser = 'Rule parsing failed.'
            selector = 'Selector execution failed.'
            javascript = 'JavaScript execution is unavailable or failed.'
            unsupportedCapability = 'The source requires an unsupported capability.'
        }
        return [ordered]@{
            status = if ($raw['successful']) { 'success' } else { 'diagnosticFailed' }
            successful = $raw['successful']
            completedStage = $raw['completedStage']
            searchResultCount = $raw['searchResultCount']
            chapterCount = $raw['chapterCount']
            contentCharacterCount = $raw['contentCharacterCount']
            failureCategory = $raw['failureCategory']
            failureOperation = $raw['failureOperation']
            # Never carry errorMessage, titles, URLs or arbitrary extra fields forward.
            errorSummary = if ($raw['successful']) { $null } else { $messages[$raw['failureCategory']] }
        }
    } catch { return New-DiagnosticStatus invalidReport }
}

function Get-DiagnosticExitCode {
    param([int]$CLIExitCode, [System.Collections.IDictionary]$Report)
    if ($CLIExitCode -ne 0) { return $CLIExitCode }
    if ($Report.status -cne 'success') { return 1 }
    return 0
}

function ConvertTo-DiagnosticSummary {
    param([System.Collections.IDictionary]$Report)
    # Even the sanitized representation is escaped as text, never executable markup.
    $text = $Report | ConvertTo-Json -Depth 4
    return "## Source diagnostic`n`n<pre>" + [System.Net.WebUtility]::HtmlEncode($text) + "</pre>`n"
}

function Invoke-DiagnosticProcess {
    param([string]$Executable, [string[]]$Arguments, [string]$Directory,
        [string]$Prefix, [int]$TimeoutSeconds)
    $start = [System.Diagnostics.ProcessStartInfo]::new($Executable)
    $start.UseShellExecute = $false
    $start.WorkingDirectory = (Get-Location).Path
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.Environment.Remove('SOURCE_DIAGNOSTIC_JSON') | Out-Null
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    $stdout = [System.IO.File]::Create((Join-Path $Directory "$Prefix.stdout"))
    $stderr = [System.IO.File]::Create((Join-Path $Directory "$Prefix.stderr"))
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $start
    try {
        if (-not $process.Start()) { throw 'process start failed' }
        $outTask = $process.StandardOutput.BaseStream.CopyToAsync($stdout)
        $errTask = $process.StandardError.BaseStream.CopyToAsync($stderr)
        $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
        if ($timedOut) {
            $process.Kill($true)
            $process.WaitForExit()
        }
        # PowerShell can expose the task's internal completion value on its
        # success stream. The function must emit only the native integer exit code.
        $null = $outTask.GetAwaiter().GetResult()
        $null = $errTask.GetAwaiter().GetResult()
        if ($timedOut) { return 124 }
        return $process.ExitCode
    } finally {
        $stdout.Dispose()
        $stderr.Dispose()
        $process.Dispose()
    }
}

Export-ModuleMember -Function Get-DiagnosticOptions, New-DiagnosticStatus,
    ConvertTo-PublicDiagnostic, Get-DiagnosticExitCode, ConvertTo-DiagnosticSummary,
    Invoke-DiagnosticProcess
