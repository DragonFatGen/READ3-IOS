$ErrorActionPreference = 'Stop'

# Offline tests for Scripts/ValidateIosDeviceApp.sh.
# The validator normally shells out to otool/lipo; here both are replaced by
# synthetic replay scripts driven by per-case fixture files, so no Apple
# toolchain and no real Mach-O binaries are required.

$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$validator = Join-Path $repoRoot 'Scripts/ValidateIosDeviceApp.sh'

function Assert-Validate([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$directory = Join-Path ([System.IO.Path]::GetTempPath()) ('ios-validate-offline-' + [guid]::NewGuid())
[System.IO.Directory]::CreateDirectory($directory) | Out-Null

try {
    $toolsDir = Join-Path $directory 'tools'
    [System.IO.Directory]::CreateDirectory($toolsDir) | Out-Null

    $fakeOtool = @'
#!/usr/bin/env bash
# Synthetic otool: replays canned output recorded per test case.
if [ "$1" = '-l' ]; then
    [ -f "$FAKE_TOOLBOX/listing.txt" ] && cat "$FAKE_TOOLBOX/listing.txt"
    exit 0
fi
if [ "$1" = '-L' ]; then
    name="$(basename "$2")"
    [ -f "$FAKE_TOOLBOX/deps_$name.txt" ] && cat "$FAKE_TOOLBOX/deps_$name.txt"
    exit 0
fi
echo "fake otool: unsupported arguments: $*" >&2
exit 2
'@ -replace "`r`n", "`n"

    $fakeLipo = @'
#!/usr/bin/env bash
# Synthetic lipo: replays the canned architecture line recorded per test case.
[ -f "$FAKE_TOOLBOX/lipo.txt" ] && cat "$FAKE_TOOLBOX/lipo.txt"
exit 0
'@ -replace "`r`n", "`n"

    $toolOtool = Join-Path $toolsDir 'otool'
    $toolLipo = Join-Path $toolsDir 'lipo'
    [IO.File]::WriteAllText($toolOtool, $fakeOtool)
    [IO.File]::WriteAllText($toolLipo, $fakeLipo)
    & bash -c "chmod +x `"$toolOtool`" `"$toolLipo`""
    Assert-Validate ($LASTEXITCODE -eq 0) 'Could not mark synthetic tools executable.'

    function New-Case([string]$Name) {
        $appDir = Join-Path (Join-Path $directory $Name) 'LegadoIOS.app'
        $toolbox = Join-Path (Join-Path $directory $Name) 'toolbox'
        [System.IO.Directory]::CreateDirectory($appDir) | Out-Null
        [System.IO.Directory]::CreateDirectory($toolbox) | Out-Null
        [IO.File]::WriteAllText((Join-Path $appDir 'LegadoIOS'), 'synthetic-binary')
        return @{ App = $appDir; Toolbox = $toolbox }
    }

    function Invoke-Validator([hashtable]$Case) {
        $env:FAKE_TOOLBOX = $Case.Toolbox
        $env:OTOOL = $toolOtool
        $env:LIPO = $toolLipo
        $appArg = $Case.App -replace '\\', '/'
        try {
            $output = (& bash $validator $appArg 2>&1 | Out-String)
            return @{ ExitCode = $LASTEXITCODE; Output = $output }
        } finally {
            Remove-Item Env:FAKE_TOOLBOX -ErrorAction SilentlyContinue
            Remove-Item Env:OTOOL -ErrorAction SilentlyContinue
            Remove-Item Env:LIPO -ErrorAction SilentlyContinue
        }
    }

    function Write-Listing([hashtable]$Case, [string]$Content) {
        [IO.File]::WriteAllText((Join-Path $Case.Toolbox 'listing.txt'), ($Content -replace "`r`n", "`n"))
    }

    function Write-Deps([hashtable]$Case, [string]$BinaryName, [string]$Content) {
        [IO.File]::WriteAllText((Join-Path $Case.Toolbox "deps_$BinaryName.txt"), ($Content -replace "`r`n", "`n"))
    }

    $lipoArm64 = "Non-fat file: LegadoIOS is architecture: arm64`n"
    $lipoFat = "Architectures in the fat file: LegadoIOS are: arm64 arm64e`n"
    $lipoX86 = "Architectures in the fat file: LegadoIOS are: x86_64 arm64`n"
    $lipoNoArm64 = "Non-fat file: LegadoIOS is architecture: armv7`n"

    $listingPlatform2 = "      cmd LC_BUILD_VERSION`n  cmdsize 32`n platform 2`n   minos 16.0`n    sdk 18.2`n"
    $listingPlatformIOS = "      cmd LC_BUILD_VERSION`n  cmdsize 32`n platform IOS`n   minos 16.0`n    sdk 18.2`n"
    $listingPlatform7 = "      cmd LC_BUILD_VERSION`n  cmdsize 32`n platform 7`n   minos 16.0`n    sdk 18.2`n"
    $listingPlatformIOSSIMULATOR = "      cmd LC_BUILD_VERSION`n  cmdsize 32`n platform IOSSIMULATOR`n   minos 16.0`n    sdk 18.2`n"
    $listingPlatform1 = "      cmd LC_BUILD_VERSION`n  cmdsize 32`n platform 1`n   minos 16.0`n    sdk 18.2`n"
    $listingMixedPlatforms = $listingPlatform2 + $listingPlatform7
    $listingSimulatorWithLegacyMin = $listingPlatform7 + "      cmd LC_VERSION_MIN_IPHONEOS`n  cmdsize 16`n  version 16.0`n"
    $listingLegacyMinOnly = "      cmd LC_VERSION_MIN_IPHONEOS`n  cmdsize 16`n  version 16.0`n"
    $listingRpath = "          cmd LC_RPATH`n      cmdsize 48`n         path @executable_path/Frameworks (offset 12)`n"

    $depsSystemOnly = "LegadoIOS:`n`t/System/Library/Frameworks/UIKit.framework/UIKit (compatibility version 300.0.0, current version 6100.0.0)`n`t/usr/lib/libobjc.A.dylib (compatibility version 1.0.0, current version 228.0.0)`n`t/usr/lib/swift/libswiftCore.dylib (compatibility version 1.0.0, current version 1200.0.0)`n"
    $depsNeedsLibFoo = "LegadoIOS:`n`t@rpath/libFoo.dylib (compatibility version 1.0.0, current version 1.0.0)`n`t/System/Library/Frameworks/UIKit.framework/UIKit (compatibility version 300.0.0, current version 6100.0.0)`n"
    $depsNeedsFooFramework = "LegadoIOS:`n`t@rpath/Foo.framework/Foo (compatibility version 1.0.0, current version 1.0.0)`n`t/usr/lib/libSystem.B.dylib (compatibility version 1.0.0, current version 1292.0.0)`n"

    # Case: numeric platform 2 is accepted; system-only deps pass without any Frameworks directory.
    $case = New-Case 'platform-2'
    Write-Listing $case $listingPlatform2
    Write-Deps $case 'LegadoIOS' $depsSystemOnly
    [IO.File]::WriteAllText((Join-Path $case.Toolbox 'lipo.txt'), $lipoArm64)
    $result = Invoke-Validator $case
    Assert-Validate ($result.ExitCode -eq 0) 'platform 2 must be accepted.'
    Assert-Validate ($result.Output -match 'accepted platform: 2') 'platform 2 was not reported as accepted.'

    # Case: textual platform IOS is accepted (fat multi-arch line too).
    $case = New-Case 'platform-IOS'
    Write-Listing $case $listingPlatformIOS
    Write-Deps $case 'LegadoIOS' $depsSystemOnly
    [IO.File]::WriteAllText((Join-Path $case.Toolbox 'lipo.txt'), $lipoFat)
    $result = Invoke-Validator $case
    Assert-Validate ($result.ExitCode -eq 0) 'platform IOS must be accepted.'

    # Case: numeric platform 7 (iOS Simulator) is rejected.
    $case = New-Case 'platform-7'
    Write-Listing $case $listingPlatform7
    Write-Deps $case 'LegadoIOS' $depsSystemOnly
    [IO.File]::WriteAllText((Join-Path $case.Toolbox 'lipo.txt'), $lipoArm64)
    $result = Invoke-Validator $case
    Assert-Validate ($result.ExitCode -ne 0) 'platform 7 must be rejected.'

    # Case: textual IOSSIMULATOR is rejected; a substring match on IOS must not let it pass.
    $case = New-Case 'platform-IOSSIMULATOR'
    Write-Listing $case $listingPlatformIOSSIMULATOR
    Write-Deps $case 'LegadoIOS' $depsSystemOnly
    [IO.File]::WriteAllText((Join-Path $case.Toolbox 'lipo.txt'), $lipoArm64)
    $result = Invoke-Validator $case
    Assert-Validate ($result.ExitCode -ne 0) 'platform IOSSIMULATOR must be rejected.'

    # Case: an unrecognized platform value is rejected.
    $case = New-Case 'platform-unknown'
    Write-Listing $case $listingPlatform1
    Write-Deps $case 'LegadoIOS' $depsSystemOnly
    [IO.File]::WriteAllText((Join-Path $case.Toolbox 'lipo.txt'), $lipoArm64)
    $result = Invoke-Validator $case
    Assert-Validate ($result.ExitCode -ne 0) 'an unknown platform must be rejected.'

    # Case: empty otool -l output is rejected instead of passing silently.
    $case = New-Case 'listing-empty'
    Write-Listing $case ''
    Write-Deps $case 'LegadoIOS' $depsSystemOnly
    [IO.File]::WriteAllText((Join-Path $case.Toolbox 'lipo.txt'), $lipoArm64)
    $result = Invoke-Validator $case
    Assert-Validate ($result.ExitCode -ne 0) 'empty otool -l output must be rejected.'

    # Case: mixed platform slices (2 and 7) are rejected even though one slice is iOS.
    $case = New-Case 'platform-mixed'
    Write-Listing $case $listingMixedPlatforms
    Write-Deps $case 'LegadoIOS' $depsSystemOnly
    [IO.File]::WriteAllText((Join-Path $case.Toolbox 'lipo.txt'), $lipoArm64)
    $result = Invoke-Validator $case
    Assert-Validate ($result.ExitCode -ne 0) 'mixed device/simulator platforms must be rejected.'

    # Case: LC_BUILD_VERSION is authoritative; a legacy LC_VERSION_MIN_IPHONEOS must not mask a simulator platform.
    $case = New-Case 'platform-7-legacy-min'
    Write-Listing $case $listingSimulatorWithLegacyMin
    Write-Deps $case 'LegadoIOS' $depsSystemOnly
    [IO.File]::WriteAllText((Join-Path $case.Toolbox 'lipo.txt'), $lipoArm64)
    $result = Invoke-Validator $case
    Assert-Validate ($result.ExitCode -ne 0) 'legacy min-version command must not mask a simulator platform.'

    # Case: a legacy binary without LC_BUILD_VERSION still passes via LC_VERSION_MIN_IPHONEOS.
    $case = New-Case 'legacy-min-only'
    Write-Listing $case $listingLegacyMinOnly
    Write-Deps $case 'LegadoIOS' $depsSystemOnly
    [IO.File]::WriteAllText((Join-Path $case.Toolbox 'lipo.txt'), $lipoArm64)
    $result = Invoke-Validator $case
    Assert-Validate ($result.ExitCode -eq 0) 'legacy LC_VERSION_MIN_IPHONEOS fallback was lost.'

    # Case: a required non-system dependency that is not embedded must fail, even with a missing Frameworks directory.
    $case = New-Case 'dep-missing'
    Write-Listing $case ($listingPlatform2 + $listingRpath)
    Write-Deps $case 'LegadoIOS' $depsNeedsLibFoo
    [IO.File]::WriteAllText((Join-Path $case.Toolbox 'lipo.txt'), $lipoArm64)
    $result = Invoke-Validator $case
    Assert-Validate ($result.ExitCode -ne 0) 'a missing non-system dependency must fail.'
    Assert-Validate ($result.Output -match 'libFoo') 'failure reason did not name libFoo.'

    # Case: the same dependency passes once it is embedded in Frameworks.
    $case = New-Case 'dep-embedded'
    Write-Listing $case ($listingPlatform2 + $listingRpath)
    Write-Deps $case 'LegadoIOS' $depsNeedsLibFoo
    Write-Deps $case 'libFoo.dylib' $depsSystemOnly
    [IO.File]::WriteAllText((Join-Path $case.Toolbox 'lipo.txt'), $lipoArm64)
    [System.IO.Directory]::CreateDirectory((Join-Path $case.App 'Frameworks')) | Out-Null
    [IO.File]::WriteAllText((Join-Path $case.App 'Frameworks/libFoo.dylib'), 'synthetic-dylib')
    $result = Invoke-Validator $case
    Assert-Validate ($result.ExitCode -eq 0) 'an embedded non-system dependency must pass.'

    # Case: an embedded framework is inspected too; its system-only deps pass.
    $case = New-Case 'framework-system-deps'
    Write-Listing $case ($listingPlatform2 + $listingRpath)
    Write-Deps $case 'LegadoIOS' $depsNeedsFooFramework
    Write-Deps $case 'Foo' $depsSystemOnly
    [IO.File]::WriteAllText((Join-Path $case.Toolbox 'lipo.txt'), $lipoArm64)
    [System.IO.Directory]::CreateDirectory((Join-Path $case.App 'Frameworks/Foo.framework')) | Out-Null
    [IO.File]::WriteAllText((Join-Path $case.App 'Frameworks/Foo.framework/Foo'), 'synthetic-framework')
    $result = Invoke-Validator $case
    Assert-Validate ($result.ExitCode -eq 0) 'an embedded framework with system-only deps must pass.'

    # Case: an embedded framework with a missing non-system dep must fail.
    $case = New-Case 'framework-dep-missing'
    Write-Listing $case ($listingPlatform2 + $listingRpath)
    Write-Deps $case 'LegadoIOS' $depsNeedsFooFramework
    Write-Deps $case 'Foo' $depsNeedsLibFoo
    [IO.File]::WriteAllText((Join-Path $case.Toolbox 'lipo.txt'), $lipoArm64)
    [System.IO.Directory]::CreateDirectory((Join-Path $case.App 'Frameworks/Foo.framework')) | Out-Null
    [IO.File]::WriteAllText((Join-Path $case.App 'Frameworks/Foo.framework/Foo'), 'synthetic-framework')
    $result = Invoke-Validator $case
    Assert-Validate ($result.ExitCode -ne 0) 'a framework with a missing non-system dependency must fail.'
    Assert-Validate ($result.Output -match 'libFoo') 'framework failure reason did not name libFoo.'

    # Case: simulator architecture in a fat binary is rejected.
    $case = New-Case 'arch-x86_64'
    Write-Listing $case $listingPlatform2
    Write-Deps $case 'LegadoIOS' $depsSystemOnly
    [IO.File]::WriteAllText((Join-Path $case.Toolbox 'lipo.txt'), $lipoX86)
    $result = Invoke-Validator $case
    Assert-Validate ($result.ExitCode -ne 0) 'an x86_64 slice must be rejected.'

    # Case: a binary without arm64 is rejected.
    $case = New-Case 'arch-no-arm64'
    Write-Listing $case $listingPlatform2
    Write-Deps $case 'LegadoIOS' $depsSystemOnly
    [IO.File]::WriteAllText((Join-Path $case.Toolbox 'lipo.txt'), $lipoNoArm64)
    $result = Invoke-Validator $case
    Assert-Validate ($result.ExitCode -ne 0) 'a binary without arm64 must be rejected.'
} finally {
    # Only the exact immediate temp child created by this test can be removed.
    $resolved = [IO.Path]::GetFullPath($directory)
    $parent = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()))
    if ([IO.Path]::GetDirectoryName($resolved) -ne $parent -or [IO.Path]::GetFileName($resolved) -notlike 'ios-validate-offline-*') { throw 'Unsafe cleanup path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
Assert-Validate (-not (Test-Path -LiteralPath $directory)) 'Synthetic fixtures retained after failure.'
Write-Output 'iOS device app validation tests passed (offline).'
