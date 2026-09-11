param([switch]$Publish, [switch]$Cleanup, [switch]$CheckToolchain)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'SourceDiagnostic.psm1') -Force
if ([string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) { throw 'RUNNER_TEMP is required.' }
$runnerDirectory = [System.IO.Path]::TrimEndingDirectorySeparator([System.IO.Path]::GetFullPath($env:RUNNER_TEMP))
$privateDirectory = Join-Path $runnerDirectory 'source-diagnostic-private'
$publicDirectory = Join-Path $runnerDirectory 'source-diagnostic-public'
$reportPath = Join-Path $publicDirectory 'report.json'
$environmentPath = Join-Path $publicDirectory 'environment.json'
$utf8 = [System.Text.UTF8Encoding]::new($false)

function Remove-PrivateDiagnosticFiles {
    # Never delete a computed broad path: only this fixed immediate child is allowed.
    $resolved = [System.IO.Path]::GetFullPath($privateDirectory)
    if ([System.IO.Path]::GetDirectoryName($resolved) -ne $runnerDirectory -or
        [System.IO.Path]::GetFileName($resolved) -ne 'source-diagnostic-private') {
        throw 'Unsafe cleanup path.'
    }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}

if ($Cleanup) {
    try { Remove-PrivateDiagnosticFiles } catch { throw 'Private diagnostic cleanup failed.' }
    exit 0
}

function Get-RecordedEnvironment {
    $version = $null
    if (Test-Path -LiteralPath $environmentPath) {
        try {
            $saved = Get-Content -LiteralPath $environmentPath -Raw | ConvertFrom-Json -AsHashtable
            if ($saved.swiftVersion -is [string] -and $saved.swiftVersion -cmatch '^\d{1,3}\.\d{1,3}(?:\.\d{1,3})?$') {
                $version = $saved.swiftVersion
            }
        } catch { } # Only validated numeric version metadata can be published.
    }
    return New-DiagnosticEnvironment -SwiftVersion $version
}

if ($CheckToolchain) {
    $version = $null
    $code = 1
    try {
        [System.IO.Directory]::CreateDirectory($privateDirectory) | Out-Null
        $swift = (Get-Command swift -CommandType Application -ErrorAction Stop).Source
        $versionCode = Invoke-DiagnosticProcess -Executable $swift -Arguments @('--version') `
            -Directory $privateDirectory -Prefix 'version' -TimeoutSeconds 30
        if ($versionCode -ne 0) { throw 'version check failed' }
        $version = ConvertTo-DiagnosticSwiftVersion ([System.IO.File]::ReadAllText((Join-Path $privateDirectory 'version.stdout')))
        if ([version]$version -lt [version]'6.0') { throw 'Swift 6.0 or newer required' }
        $code = 0
    } catch {
        Write-Output 'Swift toolchain check failed; Swift 6.0 or newer is required.'
    } finally {
        [System.IO.Directory]::CreateDirectory($publicDirectory) | Out-Null
        [System.IO.File]::WriteAllText($environmentPath, ((New-DiagnosticEnvironment $version) | ConvertTo-Json), $utf8)
        try { Remove-PrivateDiagnosticFiles } catch { $code = 1 }
    }
    exit $code
}

if ($Publish) {
    $missingReport = -not (Test-Path -LiteralPath $reportPath)
    if ($missingReport) {
        $report = New-DiagnosticStatus infrastructureFailed
        [System.IO.Directory]::CreateDirectory($publicDirectory) | Out-Null
        [System.IO.File]::WriteAllText($reportPath, ($report | ConvertTo-Json), $utf8)
    } else {
        $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json -AsHashtable
    }
    $report['environment'] = Get-RecordedEnvironment
    [System.IO.File]::WriteAllText($reportPath, ($report | ConvertTo-Json -Depth 4), $utf8)
    [System.IO.File]::AppendAllText($env:GITHUB_STEP_SUMMARY, (ConvertTo-DiagnosticSummary $report), $utf8)
    if ($missingReport) { exit 1 }
    exit 0
}

$report = New-DiagnosticStatus infrastructureFailed
$exitCode = 1
try {
    $sourceJSON = $env:SOURCE_DIAGNOSTIC_JSON
    # Do not pass the secret on to the build process or CLI environment.
    Remove-Item Env:SOURCE_DIAGNOSTIC_JSON -ErrorAction SilentlyContinue
    try {
        $options = Get-DiagnosticOptions -SourceJSON $sourceJSON -Inputs @{
            keyword = $env:DIAGNOSTIC_KEYWORD
            search_page = $env:DIAGNOSTIC_SEARCH_PAGE
            book_index = $env:DIAGNOSTIC_BOOK_INDEX
            chapter_index = $env:DIAGNOSTIC_CHAPTER_INDEX
            maximum_page_count = $env:DIAGNOSTIC_MAXIMUM_PAGE_COUNT
        }
    } catch {
        $status = if ([string]::IsNullOrWhiteSpace($sourceJSON)) { 'missingSecret' } else { 'invalidInput' }
        $report = New-DiagnosticStatus $status
        $exitCode = 2
        throw 'input validation stopped'
    }
    [System.IO.Directory]::CreateDirectory($privateDirectory) | Out-Null
    $report = New-DiagnosticStatus buildFailed
    $swift = (Get-Command swift -CommandType Application -ErrorAction Stop).Source
    $buildCode = Invoke-DiagnosticProcess -Executable $swift -Arguments @(
        'build', '--package-path', 'Packages/LegadoCore', '--product', 'legado-compatibility'
    ) -Directory $privateDirectory -Prefix 'build' -TimeoutSeconds 600
    if ($buildCode -ne 0) { throw 'build stopped' }
    $pathCode = Invoke-DiagnosticProcess -Executable $swift -Arguments @(
        'build', '--package-path', 'Packages/LegadoCore', '--show-bin-path'
    ) -Directory $privateDirectory -Prefix 'bin-path' -TimeoutSeconds 60
    if ($pathCode -ne 0) { throw 'binary discovery stopped' }
    $binaryDirectory = [System.IO.Path]::GetFullPath(
        [System.IO.File]::ReadAllText((Join-Path $privateDirectory 'bin-path.stdout')).Trim())
    $buildRoot = [System.IO.Path]::GetFullPath('Packages/LegadoCore/.build') + [System.IO.Path]::DirectorySeparatorChar
    $pathComparison = if ($IsWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
    if (-not $binaryDirectory.StartsWith($buildRoot, $pathComparison)) {
        throw 'unexpected binary directory'
    }
    $executable = Join-Path $binaryDirectory (Get-DiagnosticExecutableName)
    if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) { throw 'binary missing' }
    $sourcePath = Join-Path $privateDirectory 'source.json'
    # Write the original string, not a deserialize/serialize round trip; no added newline or BOM.
    [System.IO.File]::WriteAllText($sourcePath, $sourceJSON, $utf8)
    $sourceJSON = $null
    $report = New-DiagnosticStatus executionFailed
    $cliCode = Invoke-DiagnosticProcess -Executable $executable -Arguments @(
        '--source', $sourcePath, '--keyword', $options.keyword,
        '--search-page', [string]$options.search_page,
        '--book-index', [string]$options.book_index,
        '--chapter-index', [string]$options.chapter_index,
        '--maximum-page-count', [string]$options.maximum_page_count, '--json'
    ) -Directory $privateDirectory -Prefix 'cli' -TimeoutSeconds 180
    $rawReport = [System.IO.File]::ReadAllText((Join-Path $privateDirectory 'cli.stdout'))
    $report = ConvertTo-PublicDiagnostic -RawJSON $rawReport -ExitCode $cliCode
    $exitCode = Get-DiagnosticExitCode -CLIExitCode $cliCode -Report $report
} catch {
    # Exception strings can contain source data, process arguments or raw output.
    # Retain only the fixed phase status; never print $_ or native stderr.
} finally {
    $sourceJSON = $null
    try { Remove-PrivateDiagnosticFiles } catch {
        $exitCode = 1
        Write-Output 'Private diagnostic cleanup failed; cleanup will be retried by the workflow.'
    }
    [System.IO.Directory]::CreateDirectory($publicDirectory) | Out-Null
    [System.IO.File]::WriteAllText($reportPath, ($report | ConvertTo-Json -Depth 4), $utf8)
}
Write-Output $report.errorSummary
exit $exitCode
