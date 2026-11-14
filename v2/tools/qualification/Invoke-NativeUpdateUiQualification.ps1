#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$CurrentPack,
    [Parameter(Mandatory = $true)][string]$TargetPack,
    [Parameter(Mandatory = $true)][string]$TargetZip,
    [Parameter(Mandatory = $true)][string]$RunnerDll,
    [Parameter(Mandatory = $true)][string]$DotNet,
    [Parameter(Mandatory = $true)][string]$ReportDirectory
)

# Disposable local copies only. The actual current Pesto UI selects the exact prior-build ZIP,
# prepares it, confirms installation and launches its normal helper after closing MainForm.
# This script never creates the UI's transaction or supplies a replacement UI API response.
# The subsequent rollback is explicitly a service/helper check, not an additional UI claim.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:OperationNumber = 0
$suiteRoot = $null
$failure = $null
$reportCreated = $false

function Assert-LocalPath([string]$Path) {
    if (-not [IO.Path]::IsPathRooted($Path) -or $Path.StartsWith('\\') -or $Path.StartsWith('//') -or $Path -match '[\x00-\x1f"]') {
        throw 'Only fully qualified local paths are allowed; no UNC, URL or quoted/control path.'
    }
    $full = [IO.Path]::GetFullPath($Path)
    $drive = New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($full))
    if ($drive.DriveType -ne [IO.DriveType]::Fixed) { throw 'Only local fixed drives are allowed.' }
    $current = $full
    while ($current) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Reparse paths are forbidden.' }
        }
        $parent = [IO.Path]::GetDirectoryName($current)
        if ($parent -eq $current) { break }
        $current = $parent
    }
    return $full
}

function Save-Json([string]$Path, $Value) {
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding($false)))
}

function Invoke-QualificationRunner([string[]]$CommandArguments) {
    $script:OperationNumber++
    $log = Join-Path $ReportDirectory ('runner-{0:D2}-{1}.txt' -f $script:OperationNumber, $CommandArguments[0])
    $quoted = foreach ($argument in @($RunnerDll) + $CommandArguments) {
        if ($argument -match '["\x00-\x1f]') { throw 'Invalid runner argument.' }
        '"' + [regex]::Replace($argument, '(\\+)$', '$1$1') + '"'
    }
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $DotNet
    $start.Arguments = $quoted -join ' '
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $runner = [Diagnostics.Process]::Start($start)
    if ($null -eq $runner) { throw 'The qualification runner could not be started.' }
    try {
        $stdout = $runner.StandardOutput.ReadToEndAsync()
        $stderr = $runner.StandardError.ReadToEndAsync()
        $runner.WaitForExit()
        [IO.File]::WriteAllText($log, ($stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()), (New-Object Text.UTF8Encoding($false)))
        if ($runner.ExitCode -ne 0) { throw ('Qualification runner failed: {0}, exit {1}; see {2}' -f $CommandArguments[0], $runner.ExitCode, $log) }
    }
    finally { $runner.Dispose() }
}

function Start-UiParent {
    $requestPath = Join-Path $suiteRoot 'ui-request.json'
    $request = Get-Content -LiteralPath $requestPath -Raw | ConvertFrom-Json
    $installation = Assert-LocalPath $request.installation
    $exe = Assert-LocalPath (Join-Path $installation 'Pesto.exe')
    $caseEvidence = Join-Path $suiteRoot 'evidence\normal'
    if ($request.root -ne $suiteRoot -or $request.kind -ne 'pesto.native-update-ui-request' -or $request.schemaVersion -ne 1 -or
        $installation -ne (Join-Path $suiteRoot 'cases\normal\installation') -or
        (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant() -ne $request.sourceExecutableSha256) {
        throw 'The generated UI fixture identity is inconsistent.'
    }
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $exe
    $start.Arguments = '--qualify-update-ui "' + $requestPath + '"'
    $start.WorkingDirectory = $installation
    $start.UseShellExecute = $false
    # TEMP remains the real Temp root so the app can independently enforce its named-child scope.
    $start.EnvironmentVariables['LOCALAPPDATA'] = Join-Path $suiteRoot 'profile-sentinel'
    $start.EnvironmentVariables['APPDATA'] = Join-Path $suiteRoot 'profile-sentinel'
    $created = [Diagnostics.Process]::Start($start)
    if ($null -eq $created) { throw 'Windows did not create the isolated Pesto UI.' }
    $parent = $null
    try {
        $parent = [ordered]@{
            processId = $created.Id
            startUtcTicks = $created.StartTime.ToUniversalTime().Ticks.ToString([Globalization.CultureInfo]::InvariantCulture)
            executable = $exe
        }
        Save-Json (Join-Path $caseEvidence 'ui-parent-launch.json') $parent
        $exited = $created.WaitForExit(480000)
        Save-Json (Join-Path $caseEvidence 'ui-parent-exit.json') ([ordered]@{
            processId = $parent.processId; startUtcTicks = $parent.startUtcTicks
            exited = $exited; exitCode = $(if ($exited) { $created.ExitCode } else { $null })
        })
        if (-not $exited) {
            # No broad process-tree stop: a timed-out UI may already have handed work to the helper.
            # Ask only this exact started UI to close, preserve all evidence, and fail the campaign.
            if (-not $created.HasExited -and $created.StartTime.ToUniversalTime().Ticks.ToString([Globalization.CultureInfo]::InvariantCulture) -eq $parent.startUtcTicks) {
                $null = $created.CloseMainWindow()
                $null = $created.WaitForExit(10000)
            }
            throw 'The owned UI parent timed out; no successful native UI installation is claimed.'
        }
        if ($created.ExitCode -ne 0) { throw ('The native UI handoff failed with exit {0}.' -f $created.ExitCode) }
    }
    finally { $created.Dispose() }
}

function Start-AndObserveRollback {
    $caseEvidence = Join-Path $suiteRoot 'evidence\normal'
    $request = Get-Content -LiteralPath (Join-Path $caseEvidence 'request-rollback.json') -Raw | ConvertFrom-Json
    $suite = Get-Content -LiteralPath (Join-Path $suiteRoot 'qualification.json') -Raw | ConvertFrom-Json
    $helper = Assert-LocalPath $request.helperExecutable
    $transaction = Assert-LocalPath $request.transactionDirectory
    $prefix = $suiteRoot.TrimEnd([char[]]'\/') + [IO.Path]::DirectorySeparatorChar
    if (-not $helper.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or -not $transaction.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or
        (Get-FileHash -LiteralPath $helper -Algorithm SHA256).Hash.ToLowerInvariant() -ne $suite.base.executableSha256) {
        throw 'Rollback helper request leaves the reviewed disposable fixture.'
    }
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $helper
    $start.Arguments = '--update-helper "' + $transaction.TrimEnd([char[]]'\/') + '"'
    $start.WorkingDirectory = [IO.Path]::GetDirectoryName($helper)
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.EnvironmentVariables['TEMP'] = Join-Path $suiteRoot 'process-temp'
    $start.EnvironmentVariables['TMP'] = Join-Path $suiteRoot 'process-temp'
    $start.EnvironmentVariables['LOCALAPPDATA'] = Join-Path $suiteRoot 'profile-sentinel'
    $start.EnvironmentVariables['APPDATA'] = Join-Path $suiteRoot 'profile-sentinel'
    # Enable host tracing for this isolated rollback launch; children may inherit these variables.
    # The existing finally archives this owned file without treating it as a qualification verdict.
    $start.EnvironmentVariables['DOTNET_HOST_TRACE'] = '1'
    $start.EnvironmentVariables['DOTNET_HOST_TRACEFILE'] = Assert-LocalPath (Join-Path $caseEvidence 'helper-rollback-host.log')
    $created = [Diagnostics.Process]::Start($start)
    if ($null -eq $created) { throw 'Windows did not create the requested rollback helper.' }
    try {
        $launch = [ordered]@{
            processId = $created.Id
            startUtcTicks = $created.StartTime.ToUniversalTime().Ticks.ToString([Globalization.CultureInfo]::InvariantCulture)
            executable = $helper; transactionId = $request.transactionId
        }
        $launchPath = Join-Path $caseEvidence 'launch-rollback.json'
        Save-Json $launchPath $launch
        Invoke-QualificationRunner @('observe', $suiteRoot, 'normal', 'rollback', $launchPath)
        if (-not $created.WaitForExit(5000)) { throw 'The observed rollback helper has not exited.' }
    }
    finally { $created.Dispose() }
}

try {
    $CurrentPack = Assert-LocalPath $CurrentPack
    $TargetPack = Assert-LocalPath $TargetPack
    $TargetZip = Assert-LocalPath $TargetZip
    $RunnerDll = Assert-LocalPath $RunnerDll
    $DotNet = Assert-LocalPath $DotNet
    $ReportDirectory = Assert-LocalPath $ReportDirectory
    if (Test-Path -LiteralPath $ReportDirectory) { throw 'The report destination must be new.' }
    New-Item -ItemType Directory -Path $ReportDirectory | Out-Null
    $reportCreated = $true
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Native Windows qualification requires Windows.' }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    try {
        $principal = New-Object Security.Principal.WindowsPrincipal $identity
        if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            throw 'An already elevated runner is required; this test does not automate or qualify UAC.'
        }
    }
    finally { $identity.Dispose() }
    $suiteRoot = Assert-LocalPath (Join-Path ([IO.Path]::GetTempPath()) ('Pesto-native-update-' + [guid]::NewGuid().ToString('N')))
    Invoke-QualificationRunner @('ui-init', $CurrentPack, $TargetPack, $TargetZip, $suiteRoot)
    Start-UiParent
    Invoke-QualificationRunner @('ui-adopt', $suiteRoot)
    Invoke-QualificationRunner @('observe', $suiteRoot, 'normal', 'install', (Join-Path $suiteRoot 'evidence\normal\launch-install.json'))
    Invoke-QualificationRunner @('ui-verify', $suiteRoot, 'install')
    # This service request runs in a separate process which exits before the real rollback helper starts.
    Invoke-QualificationRunner @('request', $suiteRoot, 'normal', 'rollback')
    Start-AndObserveRollback
    Invoke-QualificationRunner @('ui-verify', $suiteRoot, 'rollback')
    Invoke-QualificationRunner @('ui-cleanup', $suiteRoot)
    Invoke-QualificationRunner @('ui-finish', $suiteRoot)
}
catch {
    $failure = $_.Exception.Message
    if ($reportCreated) {
        Save-Json (Join-Path $ReportDirectory 'failure.json') ([ordered]@{ success = $false; failure = $failure; nativeUpdateInstallFromUiQualified = $false })
    }
}
finally {
    if ($reportCreated -and $suiteRoot -and (Test-Path -LiteralPath (Join-Path $suiteRoot 'evidence'))) {
        $evidenceRoot = Join-Path $suiteRoot 'evidence'
        $outputRoot = Join-Path $ReportDirectory 'transaction-evidence'
        New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
        $excludedData = (Join-Path $evidenceRoot 'normal\ui\coexistence\data').TrimEnd([char[]]'\/') + [IO.Path]::DirectorySeparatorChar
        foreach ($file in Get-ChildItem -LiteralPath $evidenceRoot -File -Recurse) {
            if ($file.FullName.StartsWith($excludedData, [StringComparison]::OrdinalIgnoreCase)) { continue }
            $source = Assert-LocalPath $file.FullName
            $relative = $source.Substring($evidenceRoot.TrimEnd([char[]]'\/').Length + 1)
            $destination = Join-Path $outputRoot $relative
            New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($destination)) -Force | Out-Null
            Copy-Item -LiteralPath $source -Destination $destination
        }
        Copy-Item -LiteralPath (Join-Path $suiteRoot 'ui-request.json') -Destination (Join-Path $ReportDirectory 'ui-request.json')
    }
}
if ($failure) { Write-Error $failure; exit 2 }
Write-Output 'Native maintenance UI installation and separate service rollback qualified on disposable copies.'
exit 0
