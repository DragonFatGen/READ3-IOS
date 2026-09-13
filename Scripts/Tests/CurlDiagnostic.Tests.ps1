$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../SourceDiagnostic.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '../CurlDiagnostic.psm1') -Force
function Assert-Curl([bool]$Value, [string]$Message) { if (-not $Value) { throw $Message } }

$directory = Join-Path ([System.IO.Path]::GetTempPath()) ('curl-offline-' + [guid]::NewGuid())
[System.IO.Directory]::CreateDirectory($directory) | Out-Null
try {
    $keyword = '苟在两界修仙'
    $body = [System.Text.Encoding]::UTF8.GetBytes('searchkey=' + [uri]::EscapeDataString($keyword))
    $request = @{ url = 'https://fixture.invalid/search?private-token'; method = 'POST'
        headers = @{ 'Content-Type' = 'application/x-www-form-urlencoded'; 'Cookie' = 'private-cookie'; 'Authorization' = 'private-auth' }
        maximumRedirects = 20; hasBody = $true }
    [System.IO.File]::WriteAllBytes((Join-Path $directory 'request.body'), $body)
    [System.IO.File]::WriteAllText((Join-Path $directory 'request.json'), ($request | ConvertTo-Json))
    $audit = Get-DiagnosticFormAudit $request $body $keyword
    Assert-Curl ($audit.formEncoded -and $audit.searchkeyMatchesKeyword -and -not $audit.unresolvedPlaceholder) 'Chinese form audit failed.'
    Assert-Curl ($audit.bodyByteCount -eq $body.Length) 'Body size changed.'
    Assert-Curl (($audit | ConvertTo-Json) -notmatch 'private-|苟在|https://') 'Audit leaked values.'
    foreach ($invalid in @('searchkey=%ZZ', 'searchkey=未编码', 'searchkey')) {
        Assert-Curl (-not (Get-DiagnosticFormAudit $request ([Text.Encoding]::UTF8.GetBytes($invalid)) $keyword).formEncoded) 'Invalid encoding accepted.'
    }
    $placeholder = Get-DiagnosticFormAudit $request ([Text.Encoding]::UTF8.GetBytes('searchkey=%7B%7Bkey%7D%7D')) $keyword
    Assert-Curl ($placeholder.unresolvedPlaceholder -and -not $placeholder.searchkeyMatchesKeyword) 'Encoded placeholder missed.'
    $duplicate = Get-DiagnosticFormAudit $request ([Text.Encoding]::UTF8.GetBytes('searchkey=x&searchkey=y')) 'x'
    Assert-Curl (-not $duplicate.searchkeyMatchesKeyword) 'Duplicate searchkey accepted.'
    $blocked = New-CurlDiagnosticConfig $request $directory
    $config = [IO.File]::ReadAllText((Join-Path $directory 'curl.config'))
    Assert-Curl ($blocked -and $config -notmatch '(?m)^location\s*$|insecure|location-trusted') 'Unsafe credential redirects.'
    Assert-Curl ($config.Contains('data-binary = "@') -and $config.Contains('request.body')) 'Body file not used.'
    Assert-Curl ($config -notmatch 'searchkey=|request = "POST"') 'Body expanded or POST redirect method forced.'
    Assert-Curl ([Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $directory 'request.body'))) -ceq [Convert]::ToBase64String($body)) 'Request bytes changed.'
    $request.headers.Remove('Cookie'); $request.headers.Remove('Authorization')
    Assert-Curl (-not (New-CurlDiagnosticConfig $request $directory)) 'Credential-free request blocked.'
    Assert-Curl ([IO.File]::ReadAllText((Join-Path $directory 'curl.config')) -match '(?m)^location\s*$') 'Redirect policy lost.'

    # Replace only the native process boundary in module scope; never run curl/Swift.
    $module = Get-Module CurlDiagnostic
    & $module {
        $script:invocations = 0
        function script:Invoke-DiagnosticProcess {
            param($Executable, $Arguments, $Directory, $Prefix, $TimeoutSeconds)
            $script:invocations++
            [IO.File]::WriteAllText((Join-Path $Directory 'curl.stderr'), 'private-stderr')
            [IO.File]::WriteAllText((Join-Path $Directory 'curl.stdout'), '{"http_code":0,"num_redirects":0,"url_effective":"private-url"}')
            return 60
        }
    }
    $result = Invoke-CurlDiagnostic $directory $keyword 'never-swift' @()
    Assert-Curl ($result.curlExitCode -eq 60 -and $result.errorCategory -ceq 'tls') 'Curl failure classification lost.'
    Assert-Curl ($null -eq $result.responseStatusCode -and $null -eq $result.finalResultCount) 'Failure invented observations.'
    Assert-Curl ((& $module { $script:invocations }) -eq 1) 'Comparison retried.'
    Assert-Curl (($result | ConvertTo-Json -Depth 6) -notmatch 'private-|https://|苟在') 'Failure report leaked.'
    Assert-Curl ((Get-DiagnosticExitCode 1 @{status='diagnosticFailed'; curlComparison=$result}) -eq 1) 'Swift failure overridden.'
    & $module {
        $script:curlCalls = 0
        function script:Invoke-DiagnosticProcess {
            param($Executable, $Arguments, $Directory, $Prefix, $TimeoutSeconds)
            if ($Prefix -eq 'curl') {
                $script:curlCalls++
                if ($Arguments.Count -ne 3 -or $Arguments[0] -cne '-q' -or $Arguments[1] -cne '--config') { throw 'Unsafe process arguments.' }
                [IO.File]::WriteAllText((Join-Path $Directory 'curl.stdout'), '{"http_code":200,"num_redirects":0}')
                [IO.File]::WriteAllText((Join-Path $Directory 'curl.body'), 'private-body')
            } else {
                [IO.File]::WriteAllText((Join-Path $Directory 'replay.stdout'), '{"searchDiagnostic":{"lastStage":"parsed","pageHint":"bookDetail","bookListMatchedCount":1,"finalResultCount":1,"ruleThrew":false,"responseStatusCode":200,"responseByteCount":12,"responseRedirected":false,"responseBody":"private-body","url":"https://private.invalid"},"private":"private-error"}')
            }
            return 0
        }
    }
    $result = Invoke-CurlDiagnostic $directory $keyword 'never-swift' @()
    Assert-Curl ($result.curlExitCode -eq 0 -and $result.finalResultCount -eq 1 -and $null -eq $result.errorCategory) 'Successful replay rejected.'
    Assert-Curl ((& $module { $script:curlCalls }) -eq 1) 'Successful comparison repeated search.'
    Assert-Curl ((($result | ConvertTo-Json -Depth 6) + (ConvertTo-DiagnosticSummary @{curlComparison=$result})) -notmatch 'private-|https://|苟在') 'Replay leaked raw response fields.'
    Assert-Curl ((Get-DiagnosticExitCode 1 @{status='diagnosticFailed'; curlComparison=$result}) -eq 1) 'Curl success hid Swift failure.'
} finally {
    # Only the exact immediate temp child created by this test can be removed.
    $resolved = [IO.Path]::GetFullPath($directory)
    $parent = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))
    if ([IO.Path]::GetDirectoryName($resolved) -ne $parent -or [IO.Path]::GetFileName($resolved) -notlike 'curl-offline-*') { throw 'Unsafe cleanup path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
Assert-Curl (-not (Test-Path -LiteralPath $directory)) 'Private curl files retained after failure.'
Write-Output 'Curl comparison tests passed (offline).'
