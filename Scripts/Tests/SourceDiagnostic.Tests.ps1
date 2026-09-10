param([switch]$NativeFixture, [string]$Payload)

if ($NativeFixture) {
    # Match the CLI's explicit UTF-8 byte output regardless of runner console code page.
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    [Console]::Out.Write($Payload)
    [Console]::Error.Write('private-stderr')
    if ($env:SOURCE_DIAGNOSTIC_JSON) { exit 9 }
    exit 1
}

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../SourceDiagnostic.psm1') -Force

# Dependency-free workflow tests; existing XCTest fixtures cover the business chain.
function Assert-True([bool]$Value, [string]$Message) {
    if (-not $Value) { throw $Message }
}
function Assert-Throws([scriptblock]$Action) {
    $didThrow = $false
    try { & $Action | Out-Null } catch { $didThrow = $true }
    Assert-True $didThrow 'Expected input validation to fail.'
}

$inputs = @{ keyword = '示例'; search_page = '1'; book_index = '0'; chapter_index = '0'; maximum_page_count = '3' }
$source = '{"bookSourceName":"Synthetic","bookSourceUrl":"https://fixture.invalid"}'
$options = Get-DiagnosticOptions $inputs $source
Assert-True ($options.search_page -eq 1 -and $options.maximum_page_count -eq 3) 'Valid inputs changed.'
Assert-Throws { Get-DiagnosticOptions $inputs '' }
Assert-Throws { Get-DiagnosticOptions $inputs '[]' }
Assert-Throws { Get-DiagnosticOptions $inputs 'not JSON' }
foreach ($field in @('keyword', 'search_page', 'book_index', 'chapter_index', 'maximum_page_count')) {
    $invalid = $inputs.Clone()
    $invalid[$field] = ''
    Assert-Throws { Get-DiagnosticOptions $invalid $source }
}
foreach ($case in @(
    @('search_page', '0'), @('book_index', '-1'), @('chapter_index', '1.5'),
    @('maximum_page_count', '11'), @('maximum_page_count', '0'),
    @('book_index', '999999999999999999999'), @('search_page', '1; exit 0'),
    @('keyword', '--help'), @('keyword', "bad`nkeyword")
)) {
    $invalid = $inputs.Clone()
    $invalid[$case[0]] = $case[1]
    Assert-Throws { Get-DiagnosticOptions $invalid $source }
}

# Shape matches the CLI Codable DTO, including omitted optional keys.
$success = '{"successful":true,"completedStage":"content","searchResultCount":1,"chapterCount":2,"contentSucceeded":true,"contentCharacterCount":12,"selectedBookName":"private-title","extra":"private-extra"}'
$report = ConvertTo-PublicDiagnostic $success 0
Assert-True ($report.status -eq 'success' -and $report.contentCharacterCount -eq 12) 'Success report rejected.'
Assert-True ((Get-DiagnosticExitCode 0 $report) -eq 0) 'Successful exit changed.'
Assert-True (($report | ConvertTo-Json) -notmatch 'private-') 'Extra fields leaked.'

$failure = @{
    successful = $false; completedStage = 'search'; searchResultCount = 1
    chapterCount = 0; contentSucceeded = $false; failureCategory = 'request'; failureOperation = 'bookInfo'
    errorMessage = 'https://user:private-password@fixture.invalid/?token=private-token Authorization: Bearer private-auth Cookie: private-cookie <script>private-script</script>'
    selectedBookAuthor = 'private-author'; variables = @{ session = 'private-session' }
} | ConvertTo-Json
$report = ConvertTo-PublicDiagnostic $failure 1
Assert-True ($report.status -eq 'diagnosticFailed' -and $report.completedStage -eq 'search') 'Partial progress lost.'
Assert-True ((Get-DiagnosticExitCode 1 $report) -eq 1) 'Compatibility failure hidden.'
$public = ($report | ConvertTo-Json) + (ConvertTo-DiagnosticSummary $report)
Assert-True ($public -notmatch 'private-|https://|Authorization|Cookie|<script>') 'Sensitive error text leaked.'
Assert-True ($report.errorSummary -eq 'Request construction or network execution failed.') 'Unsafe error summary.'
foreach ($field in @('requestFailureKind', 'networkErrorDomain', 'networkErrorCode', 'httpStatusCode', 'requestFailureSummary')) {
    Assert-True ($null -eq $report[$field]) 'Old report must leave new diagnostics empty.'
}

$network = $failure | ConvertFrom-Json -AsHashtable
$network.requestFailureKind = 'timeout'
$network.networkErrorDomain = 'NSURLErrorDomain'
$network.networkErrorCode = -1001
$network.httpStatusCode = $null
$network.requestFailureSummary = 'private-untrusted-summary'
$report = ConvertTo-PublicDiagnostic ($network | ConvertTo-Json) 1
Assert-True ($report.requestFailureKind -ceq 'timeout' -and $report.networkErrorCode -eq -1001) 'Network metadata lost.'
Assert-True ($report.networkErrorDomain -ceq 'NSURLErrorDomain' -and $null -eq $report.httpStatusCode) 'Invented response or lost domain.'
Assert-True ($report.requestFailureSummary -ceq 'The request timed out.') 'Untrusted request summary accepted.'
$public = ($report | ConvertTo-Json) + (ConvertTo-DiagnosticSummary $report)
Assert-True ($public -notmatch 'private-|https://|Authorization|Cookie|<script>') 'Structured diagnostics leaked private data.'
Assert-True ($public.Contains('networkErrorCode') -and $public.Contains('-1001')) 'Step summary lost metadata.'
Assert-True ((Get-DiagnosticExitCode 1 $report) -eq 1) 'Network failure exit changed.'
foreach ($kind in @('requestConstruction', 'dns', 'connection', 'tls', 'cancelled', 'otherNetwork', 'unknown')) {
    $sample = $network.Clone()
    $sample.requestFailureKind = $kind
    $sample.networkErrorDomain = $null
    $sample.networkErrorCode = $null
    $report = ConvertTo-PublicDiagnostic ($sample | ConvertTo-Json) 1
    Assert-True ($report.requestFailureKind -ceq $kind -and $null -ne $report.requestFailureSummary) 'Allowed kind lost.'
}
$received = $network.Clone()
$received.httpStatusCode = 503
$report = ConvertTo-PublicDiagnostic ($received | ConvertTo-Json) 1
Assert-True ($report.httpStatusCode -eq 503) 'Actual response status lost.'
foreach ($case in @(
    @('requestFailureKind', 'private-kind'), @('networkErrorDomain', 'private-domain'),
    @('networkErrorCode', 'private-code'), @('networkErrorCode', 1.5), @('networkErrorCode', $true),
    @('httpStatusCode', '503'), @('httpStatusCode', 0), @('httpStatusCode', 600),
    @('requestFailureKind', $null), @('networkErrorDomain', $null), @('networkErrorCode', $null)
)) {
    $invalid = $network.Clone()
    $invalid[$case[0]] = $case[1]
    $report = ConvertTo-PublicDiagnostic ($invalid | ConvertTo-Json) 1
    Assert-True ($report.status -eq 'invalidReport') 'Invalid diagnostic metadata accepted.'
    Assert-True ((($report | ConvertTo-Json) + (ConvertTo-DiagnosticSummary $report)) -notmatch 'private-') 'Rejected metadata leaked.'
    Assert-True ((Get-DiagnosticExitCode 1 $report) -ne 0) 'Invalid metadata became success.'
}

$inputFailure = '{"successful":false,"contentSucceeded":false,"searchResultCount":0,"chapterCount":0,"failureCategory":"input","failureOperation":"import"}'
Assert-True ((Get-DiagnosticExitCode 2 (ConvertTo-PublicDiagnostic $inputFailure 2)) -eq 2) 'Input exit changed.'
foreach ($raw in @('not JSON', '[]', '{}', '{"successful":"true"}', $success.Replace('"content"', '"<script>"'), $success.Replace('"searchResultCount":1', '"searchResultCount":"private-count"'))) {
    $report = ConvertTo-PublicDiagnostic $raw 0
    Assert-True ($report.status -eq 'invalidReport') 'Malformed report accepted.'
    Assert-True ((Get-DiagnosticExitCode 0 $report) -ne 0) 'Malformed output became a successful run.'
}
Assert-True ((ConvertTo-PublicDiagnostic $success 1).status -eq 'invalidReport') 'Exit/report contradiction accepted.'
Assert-True ((ConvertTo-PublicDiagnostic $failure 0).status -eq 'invalidReport') 'Failure with exit 0 accepted.'
Assert-True ((ConvertTo-PublicDiagnostic $success 124).status -eq 'executionFailed') 'Timeout became success.'
foreach ($status in @('missingSecret', 'invalidInput', 'buildFailed', 'infrastructureFailed')) {
    $report = New-DiagnosticStatus $status
    Assert-True (-not $report.successful -and $null -eq $report.completedStage -and $null -eq $report.searchResultCount) 'Invented business result.'
    Assert-True ((Get-DiagnosticExitCode 1 $report) -eq 1) 'Infrastructure failure hidden.'
}
$escaped = ConvertTo-DiagnosticSummary @{ text = '</pre><script>alert(1)</script> & "' }
Assert-True ($escaped -notmatch '<script>' -and $escaped.Contains('&lt;script&gt;')) 'Summary markup was not escaped.'

# Real capture and argument code, using a local child fixture; no Swift or network.
$temporary = Join-Path ([System.IO.Path]::GetTempPath()) ('diagnostic-tests-' + [guid]::NewGuid())
$previousSecret = $env:SOURCE_DIAGNOSTIC_JSON
$previousRunnerTemp = $env:RUNNER_TEMP
$previousSummary = $env:GITHUB_STEP_SUMMARY
try {
    [System.IO.Directory]::CreateDirectory($temporary) | Out-Null
    $env:SOURCE_DIAGNOSTIC_JSON = 'private-fixture-secret'
    $payload = '中文 "quoted"; $(not-a-command) <tag>'
    $code = Invoke-DiagnosticProcess -Executable (Get-Command pwsh).Source -Arguments @(
        '-NoProfile', '-File', $PSCommandPath, '-NativeFixture', '-Payload', $payload
    ) -Directory $temporary -Prefix 'fixture' -TimeoutSeconds 30
    Assert-True ($code -is [int]) 'Process capture emitted values other than its integer exit code.'
    Assert-True ($code -eq 1) 'Native exit code or secret environment isolation changed.'
    $actualOutput = [System.IO.File]::ReadAllText((Join-Path $temporary 'fixture.stdout'))
    $fixtureBytes = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes((Join-Path $temporary 'fixture.stdout')))
    Assert-True ($actualOutput -ceq $payload) "Argument or stdout changed (synthetic fixture bytes: $fixtureBytes)."
    Assert-True ([System.IO.File]::ReadAllText((Join-Path $temporary 'fixture.stderr')) -ceq 'private-stderr') 'Streams mixed.'

    # The actual entry script must stop before Swift when the secret is missing.
    $env:RUNNER_TEMP = $temporary + [System.IO.Path]::DirectorySeparatorChar
    $env:GITHUB_STEP_SUMMARY = Join-Path $temporary 'summary.txt'
    $entry = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../Invoke-SourceDiagnostic.ps1'))
    $code = Invoke-DiagnosticProcess -Executable (Get-Command pwsh).Source -Arguments @(
        '-NoProfile', '-File', $entry
    ) -Directory $temporary -Prefix 'missing-secret' -TimeoutSeconds 30
    Assert-True ($code -eq 2) 'Missing secret did not fail the entry script.'
    $saved = Get-Content (Join-Path $temporary 'source-diagnostic-public/report.json') -Raw | ConvertFrom-Json
    Assert-True ($saved.status -eq 'missingSecret') 'Missing secret summary was lost.'
    $code = Invoke-DiagnosticProcess -Executable (Get-Command pwsh).Source -Arguments @(
        '-NoProfile', '-File', $entry, '-Publish'
    ) -Directory $temporary -Prefix 'publish' -TimeoutSeconds 30
    Assert-True ($code -eq 0) 'Safe report publication failed.'
    Assert-True ([System.IO.File]::ReadAllText($env:GITHUB_STEP_SUMMARY).Contains('missingSecret')) 'Step summary missing.'
    Assert-True (-not (Test-Path (Join-Path $temporary 'source-diagnostic-private'))) 'Private directory retained.'
} finally {
    $env:SOURCE_DIAGNOSTIC_JSON = $previousSecret
    $env:RUNNER_TEMP = $previousRunnerTemp
    $env:GITHUB_STEP_SUMMARY = $previousSummary
    # Exact unique directory created above, never a user-controlled path.
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force }
}
Write-Output 'Source diagnostic helper tests passed (offline).'
