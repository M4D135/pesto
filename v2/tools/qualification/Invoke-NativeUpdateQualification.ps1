#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BasePack,
    [Parameter(Mandatory = $true)][string]$CandidatePack,
    [Parameter(Mandatory = $true)][string]$CandidateZip,
    [Parameter(Mandatory = $true)][string]$RunnerDll,
    [Parameter(Mandatory = $true)][string]$DotNet,
    [Parameter(Mandatory = $true)][string]$ReportDirectory
)

# No AD module, remoting, SMB, HTTP, global process stop, SendKeys or profile initialization.
# The .NET companion has no apphost. Native processes use the real base/candidate Pesto.exe builds.
# The helper is always copied from the base; normal acquisition uses the supplied candidate ZIP without fallback.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:OperationNumber = 0
$suiteRoot = $null
$failure = $null

function Assert-LocalPath([string]$Path) {
    if (-not [IO.Path]::IsPathRooted($Path) -or $Path.StartsWith('\\') -or $Path.StartsWith('//') -or $Path -match '[\x00-\x1f"]') {
        throw 'Only fully qualified local paths are allowed; no UNC, URL or quoted/control path.'
    }
    $full = [IO.Path]::GetFullPath($Path)
    $drive = New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($full))
    if ($drive.DriveType -ne [IO.DriveType]::Fixed) { throw 'Only local fixed drives are allowed; mapped/network drives are forbidden.' }
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

function Invoke-QualificationRunner([string[]]$CommandArguments) {
    $script:OperationNumber++
    $log = Join-Path $ReportDirectory ('runner-{0:D2}-{1}.txt' -f $script:OperationNumber, $CommandArguments[0])
    $quoted = foreach ($argument in @($RunnerDll) + $CommandArguments) {
        if ($argument -match '["\x00-\x1f]') { throw 'Invalid runner argument.' }
        # No shell is used. Quoted Windows arguments only need final backslashes doubled here because quotes are refused.
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
        # Windows PowerShell 5.1 turns stderr into terminating NativeCommandError under ErrorActionPreference=Stop.
        # Drain both streams directly so a failed native observation keeps its complete JSON diagnostic.
        $stdout = $runner.StandardOutput.ReadToEndAsync()
        $stderr = $runner.StandardError.ReadToEndAsync()
        $runner.WaitForExit()
        $output = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()
        [IO.File]::WriteAllText($log, $output, (New-Object Text.UTF8Encoding($false)))
        $script:LastRunnerOutput = $output
        if ($runner.ExitCode -ne 0) { throw ('Qualification runner failed: {0}, exit {1}; see {2}' -f $CommandArguments[0], $runner.ExitCode, $log) }
    }
    finally { $runner.Dispose() }
}

function Start-AndObserveHelper([string]$Scenario, [string]$Stage) {
    $caseEvidence = Join-Path (Join-Path $suiteRoot 'evidence') $Scenario
    $request = Get-Content -LiteralPath (Join-Path $caseEvidence ('request-' + $Stage + '.json')) -Raw | ConvertFrom-Json
    $suite = Get-Content -LiteralPath (Join-Path $suiteRoot 'qualification.json') -Raw | ConvertFrom-Json
    $helper = Assert-LocalPath $request.helperExecutable
    $transaction = Assert-LocalPath $request.transactionDirectory
    $prefix = $suiteRoot.TrimEnd([char[]]'\/') + [IO.Path]::DirectorySeparatorChar
    if (-not $helper.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or -not $transaction.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Helper request leaves the isolated fixture.'
    }
    if ((Get-FileHash -LiteralPath $helper -Algorithm SHA256).Hash.ToLowerInvariant() -ne $suite.base.executableSha256) {
        throw 'Helper hash differs from the installed base executable.'
    }
    # Each prepare/request runner has already EXITED. The native helper can now satisfy PID+StartTime waiting.
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
    $created = [Diagnostics.Process]::Start($start)
    if ($null -eq $created) { throw 'Windows did not create the requested isolated helper.' }
    try {
        $launch = [ordered]@{
            processId = $created.Id
            startUtcTicks = $created.StartTime.ToUniversalTime().Ticks.ToString([Globalization.CultureInfo]::InvariantCulture)
            executable = $helper
            transactionId = $request.transactionId
        }
        $launchPath = Join-Path $caseEvidence ('launch-' + $Stage + '.json')
        # Windows PowerShell 5.1's -Encoding utf8 writes a BOM. Native JSON input is explicitly BOM-free.
        $utf8NoBom = New-Object Text.UTF8Encoding($false)
        [IO.File]::WriteAllText($launchPath, ($launch | ConvertTo-Json), $utf8NoBom)
        # The companion waits for an owned dialog/exit or attributed health children before reading the journal, and only acknowledges
        # the #32770 result dialog of this PID/start-time/path AFTER a terminal journal. Interruption uses
        # .NET10 Kill(entireProcessTree:true), only after checking + real health/browser descendants exist.
        Invoke-QualificationRunner @('observe', $suiteRoot, $Scenario, $Stage, $launchPath)
        if (-not $created.WaitForExit(5000)) { throw 'Observed helper has not exited.' }
    }
    finally { $created.Dispose() }
}

try {
    $BasePack = Assert-LocalPath $BasePack
    $CandidatePack = Assert-LocalPath $CandidatePack
    $CandidateZip = Assert-LocalPath $CandidateZip
    $RunnerDll = Assert-LocalPath $RunnerDll
    $DotNet = Assert-LocalPath $DotNet
    $ReportDirectory = Assert-LocalPath $ReportDirectory
    if (Test-Path -LiteralPath $ReportDirectory) { throw 'The report destination must be new; no existing evidence is overwritten.' }
    New-Item -ItemType Directory -Path $ReportDirectory | Out-Null
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Native Windows qualification requires Windows.' }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    try {
        $principal = New-Object Security.Principal.WindowsPrincipal $identity
        if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            throw 'This runner is not elevated. UAC is not automated and native update qualification is not granted.'
        }
    }
    finally { $identity.Dispose() }
    $suiteRoot = Join-Path ([IO.Path]::GetTempPath()) ('Pesto-native-update-' + [guid]::NewGuid().ToString('N'))
    $suiteRoot = Assert-LocalPath $suiteRoot
    Invoke-QualificationRunner @('init', $BasePack, $CandidatePack, $CandidateZip, $suiteRoot)
    $suite = Get-Content -LiteralPath (Join-Path $suiteRoot 'qualification.json') -Raw | ConvertFrom-Json
    # The companion derives the scenarios from both packs: a DEV base that predates the exact DEV sources of the
    # candidate must refuse it with its own validator (new installation required), never update in place.
    Invoke-QualificationRunner @('scenarios', $suiteRoot)
    # Windows PowerShell 5.1 emits a JSON array as one pipeline object: enumerate it explicitly.
    $scenarios = @($script:LastRunnerOutput | ConvertFrom-Json | ForEach-Object { $_ })
    if ($suite.channel -eq 'PROD') { $expected = 'normal health-failure interruption' }
    elseif ($suite.channel -eq 'DEV') { $expected = '^(normal|format-refusal)$' }
    else { throw 'Unknown qualification channel.' }
    if (($suite.channel -eq 'PROD' -and ($scenarios -join ' ') -ne $expected) -or ($suite.channel -eq 'DEV' -and ($scenarios.Count -ne 1 -or $scenarios[0] -notmatch $expected))) {
        throw 'Unexpected native update scenarios for this channel.'
    }
    foreach ($scenario in $scenarios) {
        Invoke-QualificationRunner @('prepare', $suiteRoot, $scenario)
        Start-AndObserveHelper $scenario 'install'
        if ($scenario -eq 'normal') {
            Invoke-QualificationRunner @('verify', $suiteRoot, $scenario, 'install')
            Invoke-QualificationRunner @('request', $suiteRoot, $scenario, 'rollback')
            Start-AndObserveHelper $scenario 'rollback'
            Invoke-QualificationRunner @('verify', $suiteRoot, $scenario, 'rollback')
        }
        elseif ($scenario -eq 'interruption') {
            Invoke-QualificationRunner @('request', $suiteRoot, $scenario, 'recovery')
            Start-AndObserveHelper $scenario 'recovery'
            Invoke-QualificationRunner @('verify', $suiteRoot, $scenario, 'recovery')
        }
        else { Invoke-QualificationRunner @('verify', $suiteRoot, $scenario, 'install') }
        Invoke-QualificationRunner @('cleanup', $suiteRoot, $scenario)
    }
    Invoke-QualificationRunner @('finish', $suiteRoot)
}
catch {
    $failure = $_.Exception.Message
}
finally {
    if ($suiteRoot -and (Test-Path -LiteralPath (Join-Path $suiteRoot 'evidence'))) {
        # Evidence contains synthetic paths/identities and hashes only. Keep failed fixture binaries in Temp
        # for diagnosis; do not delete or follow an arbitrary profile path and do not use a global cleanup glob.
        try { Copy-Item -LiteralPath (Join-Path $suiteRoot 'evidence') -Destination (Join-Path $ReportDirectory 'transaction-evidence') -Recurse }
        catch { if (-not $failure) { $failure = 'Could not preserve complete native qualification evidence: ' + $_.Exception.Message } }
    }
    if ($failure -and (Test-Path -LiteralPath $ReportDirectory)) {
        [ordered]@{ schemaVersion = 1; kind = 'pesto.native-update-qualification'; success = $false;
            nativeBinaryUpdateQualification = $false; adQualification = $false; error = $failure; fixtureRoot = $suiteRoot } |
            ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $ReportDirectory 'failure.json') -Encoding utf8
    }
}
if ($failure) { Write-Error $failure; exit 2 }
$proofPath = Join-Path (Join-Path $ReportDirectory 'transaction-evidence') 'proof.json'
$proof = Get-Content -LiteralPath $proofPath -Raw | ConvertFrom-Json
$explicitRefusal = $proof.channel -eq 'DEV' -and $proof.formatRefusalQualified -and $proof.newInstallationRequired -and -not $proof.inPlaceUpdateQualified
if (-not $proof.success -or -not ($proof.nativeBinaryUpdateQualification -or $explicitRefusal) -or -not $proof.distinctBuilds -or -not $proof.zipAcquisitionQualified -or
    $proof.syntheticVersions -or $proof.adQualification -or $proof.uncQualification) {
    throw 'Native update evidence is incomplete.'
}
Write-Output ('NATIVE UPDATE QUALIFICATION PASSED - evidence: ' + $proofPath)
