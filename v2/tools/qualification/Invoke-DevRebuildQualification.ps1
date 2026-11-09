#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$DevZip,
    [Parameter(Mandatory = $true)][string]$ProdPack,
    [Parameter(Mandatory = $true)][ValidatePattern('^[a-f0-9]{40}$')][string]$ExpectedSourceCommit,
    [Parameter(Mandatory = $true)][string]$ReportDirectory,
    [string]$DotNet = 'dotnet',
    [string]$Node = 'node'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$workspace = $null
$reportCreated = $false
$failure = $null
$savedPackages = $env:NUGET_PACKAGES
$savedFallbackPackages = $env:NUGET_FALLBACK_PACKAGES
$checks = New-Object 'System.Collections.Generic.List[string]'
$proof = [ordered]@{
    schemaVersion = 1; kind = 'pesto.dev-source-rebuild'; success = $false
    sourceCommit = $ExpectedSourceCommit; nativeRebuiltStartupQualified = $false
    sourceOnlyRebuild = $false; freshNuGetCache = $false; originalPublishReused = $false
    sameExecutableBytesRequired = $false; adQualification = $false; ordinaryProfileAccess = $false
}

function Assert-LocalPath([string]$Value) {
    $full = [IO.Path]::GetFullPath($Value)
    if ($full.StartsWith('\\') -or $full.StartsWith('//')) { throw 'A local qualification path is required.' }
    $cursor = $full
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            $entry = Get-Item -LiteralPath $cursor -Force
            if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Links and junctions are forbidden.' }
        }
        $parent = [IO.Path]::GetDirectoryName($cursor)
        if ($parent -eq $cursor) { break }
        $cursor = $parent
    }
    return $full
}

function Hash([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }

function Inventory([string]$Root) {
    $prefix = $Root.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $result = [ordered]@{}
    foreach ($item in @(Get-ChildItem -LiteralPath $Root -Recurse -Force | Sort-Object FullName)) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'A source tree contains a link.' }
        if (-not $item.PSIsContainer) {
            $relative = $item.FullName.Substring($prefix.Length).Replace('\', '/')
            $result[$relative] = Hash $item.FullName
        }
    }
    return $result
}

function Save-Json([string]$Path, $Value) {
    $Value | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $Path -Encoding utf8
}

function Check([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw ('Rebuild check failed: ' + $Name) }
    $checks.Add($Name)
}

function Run-Logged([string]$Executable, [string[]]$Arguments, [string]$LogName) {
    $lines = @(& $Executable @Arguments 2>&1)
    $nativeExitCode = $LASTEXITCODE
    [IO.File]::WriteAllLines((Join-Path $ReportDirectory $LogName), [string[]]$lines, (New-Object Text.UTF8Encoding($false)))
    $lines | Out-Host
    if ($nativeExitCode -ne 0) { throw ('Command failed: ' + $LogName + ' (exit ' + $nativeExitCode + ')') }
}

function Extract-DevArchive([string]$Archive, [string]$Destination) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        if ($zip.Entries.Count -gt 20000) { throw 'Too many archive entries.' }
        $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        $kinds = New-Object 'System.Collections.Generic.Dictionary[string,bool]' ([StringComparer]::OrdinalIgnoreCase)
        $entries = New-Object 'System.Collections.Generic.List[object]'
        [long]$total = 0
        # Validate the complete archive before writing any entry.
        foreach ($entry in $zip.Entries) {
            $name = $entry.FullName.Replace('\', '/')
            $directory = $name.EndsWith('/')
            $name = $name.TrimEnd('/')
            if (-not $name -or $name.Length -gt 1024 -or -not $seen.Add($name)) { throw 'Empty, duplicate or oversized archive path.' }
            if (($entry.ExternalAttributes -shr 16 -band 0xf000) -eq 0xa000) { throw 'An archive link is forbidden.' }
            $parts = $name.Split('/')
            if ($parts[0] -cne 'DEV') { throw 'The delivered archive must have one DEV root.' }
            if ($parts.Length -eq 1 -and -not $directory) { throw 'The DEV root cannot be a file.' }
            foreach ($part in $parts) {
                if (-not $part -or $part -eq '.' -or $part -eq '..' -or $part -match '[<>:"|?*\x00-\x1f]' -or
                    $part -match '[ .]$' -or $part -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') {
                    throw 'An archive path is unsafe on Windows.'
                }
            }
            $total += $entry.Length
            if ($total -gt 4GB) { throw 'The archive exceeds the qualification size limit.' }
            $kinds.Add($name, $directory)
            $entries.Add([pscustomobject]@{ Entry = $entry; Name = $name; Directory = $directory })
        }
        foreach ($item in $entries) {
            $parts = $item.Name.Split('/')
            for ($i = 1; $i -lt $parts.Length; $i++) {
                $ancestor = [string]::Join('/', $parts[0..($i - 1)])
                if ($kinds.ContainsKey($ancestor) -and -not $kinds[$ancestor]) {
                    throw 'An archive file cannot also be a parent directory.'
                }
            }
        }
        New-Item -ItemType Directory -Path $Destination | Out-Null
        foreach ($item in $entries) {
            $target = Join-Path $Destination $item.Name
            if ($item.Directory) { New-Item -ItemType Directory -Path $target -Force | Out-Null; continue }
            New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($target)) -Force | Out-Null
            $source = $item.Entry.Open()
            try {
                $output = [IO.File]::Open($target, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
                try { $source.CopyTo($output) } finally { $output.Dispose() }
            }
            finally { $source.Dispose() }
        }
    }
    finally { $zip.Dispose() }
}

try {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Native DEV rebuild qualification requires Windows.' }
    $DevZip = Assert-LocalPath $DevZip
    $ProdPack = Assert-LocalPath $ProdPack
    $ReportDirectory = Assert-LocalPath $ReportDirectory
    if (Test-Path -LiteralPath $ReportDirectory) { throw 'The report destination must be new.' }
    New-Item -ItemType Directory -Path $ReportDirectory | Out-Null
    $reportCreated = $true
    $workspace = Assert-LocalPath (Join-Path ([IO.Path]::GetTempPath()) ('Pesto-dev-rebuild-' + [guid]::NewGuid().ToString('N')))
    New-Item -ItemType Directory -Path $workspace | Out-Null
    $proof.workspace = $workspace
    $proof.archiveSha256 = Hash $DevZip
    $prodBefore = Inventory $ProdPack
    $extraction = Join-Path $workspace 'delivered'
    Extract-DevArchive $DevZip $extraction
    $delivered = Join-Path $extraction 'DEV'
    $deliveredSource = Join-Path $delivered 'wad/dev'
    $manifest = Get-Content -LiteralPath (Join-Path $delivered 'wad/Pesto.package.json') -Raw | ConvertFrom-Json
    $prodManifest = Get-Content -LiteralPath (Join-Path $ProdPack 'wad/Pesto.package.json') -Raw | ConvertFrom-Json
    Check ($manifest.channel -ceq 'DEV' -and $prodManifest.channel -ceq 'PROD' -and
        $manifest.sourceCommit -ceq $ExpectedSourceCommit -and $prodManifest.sourceCommit -ceq $ExpectedSourceCommit -and
        $manifest.version -ceq $prodManifest.version -and
        $manifest.distribution -cin @('candidate','official') -and $manifest.distribution -ceq $prodManifest.distribution -and
        $manifest.official -is [bool] -and $prodManifest.official -is [bool] -and
        $manifest.official -eq ($manifest.distribution -ceq 'official') -and $prodManifest.official -eq $manifest.official -and
        $manifest.qualification -ceq 'unqualified' -and $prodManifest.qualification -ceq 'unqualified') 'exactDeliveredSourceCommitAndChannels'
    $proof['distribution'] = $manifest.distribution
    $deliveredTool = Join-Path $deliveredSource 'tools/pack/make-pack.mjs'
    Run-Logged $Node @($deliveredTool, '--verify', $delivered) 'verify-delivered-dev.log'
    Run-Logged $Node @($deliveredTool, '--verify', $ProdPack) 'verify-original-prod.log'
    $deliveredBefore = Inventory $delivered
    $sourceBefore = Inventory $deliveredSource
    Check (@($sourceBefore.Keys | Where-Object { $_ -match '(^|/)(bin|obj|node_modules|\.git)(/|$)' }).Count -eq 0) 'noDeliveredBuildOutputsOrRepository'
    Save-Json (Join-Path $ReportDirectory 'delivered-source-inputs.json') $sourceBefore

    $buildWad = Join-Path $workspace 'build/wad'
    New-Item -ItemType Directory -Path $buildWad -Force | Out-Null
    $buildSource = Join-Path $buildWad 'dev'
    Copy-Item -LiteralPath $deliveredSource -Destination $buildSource -Recurse
    New-Item -ItemType Directory -Path (Join-Path $buildWad 'runtime') | Out-Null
    Copy-Item -LiteralPath (Join-Path $delivered 'wad/runtime/activedirectory') -Destination (Join-Path $buildWad 'runtime/activedirectory') -Recurse
    $copiedSource = Inventory $buildSource
    Check (($copiedSource | ConvertTo-Json -Compress) -ceq ($sourceBefore | ConvertTo-Json -Compress)) 'cleanBuildSourcesExactlyMatchDeliveredDev'
    $proof.sourceOnlyRebuild = $true
    $nugetRoot = Join-Path $workspace 'nuget'
    Check (-not (Test-Path -LiteralPath $nugetRoot)) 'nugetCacheStartsAbsent'
    $env:NUGET_PACKAGES = $nugetRoot
    $env:NUGET_FALLBACK_PACKAGES = $null
    $proof.freshNuGetCache = $true
    $proof.inheritedFallbackPackagesDisabled = $true
    $proof.nugetPackagesRoot = $nugetRoot
    $publish = Join-Path $workspace 'new-publication'
    $rebuilt = Join-Path $workspace 'rebuilt-PROD'
    Push-Location $buildSource
    try {
        $sdkPolicy = (Get-Content -LiteralPath 'global.json' -Raw | ConvertFrom-Json).sdk
        $sdk = (& $DotNet --version).Trim()
        if ($LASTEXITCODE -ne 0) { throw 'Could not resolve the SDK from delivered global.json.' }
        $proof.expectedSdkVersion = $sdkPolicy.version
        $proof.sdkVersion = $sdk
        $proof.sdkRollForwardPolicy = $sdkPolicy.rollForward
        Run-Logged $DotNet @('--info') 'sdk-info.log'
        Check ($sdk -ceq $sdkPolicy.version -and $sdkPolicy.rollForward -ceq 'disable') 'deliveredSdkVersionUsed'
        Run-Logged $DotNet @('publish', 'src/Pesto.App/Pesto.App.csproj', '-c', 'Release', '-r', 'win-x64',
            '--self-contained', 'true', '--disable-build-servers', '-m:1', '-p:UseSharedCompilation=false', '-o', $publish) 'publish-from-dev.log'
        Check ((Test-Path -LiteralPath (Join-Path $publish 'Pesto.exe')) -and -not (Test-Path -LiteralPath (Join-Path $publish 'Pesto.dll'))) 'freshSingleFileExecutablePublished'
        $assets = @(Get-ChildItem -LiteralPath 'src' -Recurse -File -Filter project.assets.json)
        Check ($assets.Count -eq 5) 'allFiveProjectsRestoredFromCleanSources'
        $restoreObservations = New-Object 'System.Collections.Generic.List[object]'
        foreach ($asset in $assets) {
            $data = Get-Content -LiteralPath $asset.FullName -Raw | ConvertFrom-Json
            $restoreObservations.Add([ordered]@{
                assetsPath = $asset.FullName
                assetsSha256 = Hash $asset.FullName
                projectName = $data.project.restore.projectName
                projectPath = $data.project.restore.projectPath
                packageFolders = @($data.packageFolders.PSObject.Properties.Name)
            })
        }
        # Retain every observed restore root before validating it, including a failing one.
        Save-Json (Join-Path $ReportDirectory 'restored-projects.json') $restoreObservations.ToArray()
        foreach ($restored in $restoreObservations) {
            Check ([IO.Path]::GetFullPath($restored.projectPath).StartsWith($buildSource + '\', [StringComparison]::OrdinalIgnoreCase)) ('restoredProject-' + $restored.projectName)
            if ($restored.packageFolders.Count -ne 1 -or
                -not [IO.Path]::GetFullPath($restored.packageFolders[0]).TrimEnd('\', '/').Equals($nugetRoot, [StringComparison]::OrdinalIgnoreCase)) {
                throw ('The restore graph must reference only the fresh NuGet package folder: ' + $restored.projectName + ' -> ' + ($restored.packageFolders -join '; '))
            }
        }
        Run-Logged $Node @('tools/pack/make-pack.mjs', '--source', $publish, '--dest', $rebuilt, '--channel', 'PROD',
            '--source-commit', $ExpectedSourceCommit, '--distribution', $manifest.distribution) 'assemble-rebuilt-prod.log'
        Run-Logged $Node @('tools/pack/make-pack.mjs', '--verify', $rebuilt) 'verify-rebuilt-prod.log'
    }
    finally { Pop-Location }
    $rebuiltFiles = Inventory $rebuilt
    $ignored = @('Pesto.exe', 'wad/SHA256SUMS')
    $originalContent = [ordered]@{}
    $rebuiltContent = [ordered]@{}
    foreach ($key in $prodBefore.Keys) { if ($key -notin $ignored) { $originalContent[$key] = $prodBefore[$key] } }
    foreach ($key in $rebuiltFiles.Keys) { if ($key -notin $ignored) { $rebuiltContent[$key] = $rebuiltFiles[$key] } }
    Check (($originalContent | ConvertTo-Json -Compress) -ceq ($rebuiltContent | ConvertTo-Json -Compress)) 'rebuiltProdPayloadMatchesOriginalExceptExecutableAndSums'
    $proof.originalExecutableSha256 = $prodBefore['Pesto.exe']
    $proof.rebuiltExecutableSha256 = $rebuiltFiles['Pesto.exe']
    $proof.rebuiltPackSumsSha256 = $rebuiltFiles['wad/SHA256SUMS']
    $proof.sameExecutableBytes = $proof.originalExecutableSha256 -ceq $proof.rebuiltExecutableSha256
    Save-Json (Join-Path $ReportDirectory 'rebuilt-package-inventory.json') $rebuiltFiles

    $nativeReport = Join-Path $workspace 'native-demo'
    $processInfo = New-Object Diagnostics.ProcessStartInfo
    $processInfo.FileName = Join-Path $rebuilt 'Pesto.exe'
    $processInfo.WorkingDirectory = $rebuilt
    $processInfo.Arguments = '--qualify-demo "' + $nativeReport + '"'
    $processInfo.UseShellExecute = $false
    $process = [Diagnostics.Process]::Start($processInfo)
    try {
        $proof.rebuiltNativeProcessId = $process.Id
        $proof.rebuiltNativeProcessStartUtcTicks = $process.StartTime.ToUniversalTime().Ticks
        if (-not $process.WaitForExit(240000)) {
            # This is only the exact process created above, never a global Pesto/WebView2 kill.
            & taskkill.exe /PID $process.Id /T /F | Out-Null
            throw 'The rebuilt executable did not finish its native smoke.'
        }
        $proof.rebuiltNativeProcessExitCode = $process.ExitCode
        Check ($process.ExitCode -eq 0) 'rebuiltNativeProcessExitedSuccessfully'
    }
    finally {
        $process.Dispose()
        if (Test-Path -LiteralPath (Join-Path $nativeReport 'proof.json')) {
            Copy-Item -LiteralPath (Join-Path $nativeReport 'proof.json') -Destination (Join-Path $ReportDirectory 'rebuilt-native-demo.json')
        }
    }
    $native = Get-Content -LiteralPath (Join-Path $nativeReport 'proof.json') -Raw | ConvertFrom-Json
    Check ($native.success -eq $true -and $native.ready -eq $true -and $native.closeReturned -eq $true -and
        $native.temporaryProfilesRemoved -eq $true -and $native.realProfileCreated -eq $false -and
        $native.adQualification -eq $false -and $native.binaryUpdateQualification -eq $false -and
        $native.blockedDirectApis -eq 43 -and $native.hostInvocations -eq 0 -and
        $native.channel -ceq 'PROD' -and $native.executableSha256 -ceq $proof.rebuiltExecutableSha256) 'rebuiltNativeStartupDemoAndIsolationProved'
    $proof.nativeRebuiltStartupQualified = $true
    Check ((Hash $DevZip) -ceq $proof.archiveSha256) 'deliveredZipUnchanged'
    Check (((Inventory $delivered) | ConvertTo-Json -Compress) -ceq ($deliveredBefore | ConvertTo-Json -Compress)) 'extractedDeliveredPackUnchanged'
    Check (((Inventory $ProdPack) | ConvertTo-Json -Compress) -ceq ($prodBefore | ConvertTo-Json -Compress)) 'originalProdPackUnchanged'
    $proof.success = $true
}
catch {
    $failure = $_.Exception.Message
    $proof.error = $failure
}
finally {
    $env:NUGET_PACKAGES = $savedPackages
    $env:NUGET_FALLBACK_PACKAGES = $savedFallbackPackages
    $proof.checks = @($checks)
    $proof.utc = [DateTimeOffset]::UtcNow.ToString('O')
    $proof.temporaryWorkspaceRemoved = $false
    # Only the unique workspace created by this invocation can be removed.
    # A cleanup failure remains a failed run, with its evidence and remaining fixture preserved.
    if (-not $failure -and $workspace -and (Test-Path -LiteralPath $workspace)) {
        try {
            Remove-Item -LiteralPath $workspace -Recurse -Force
            if (Test-Path -LiteralPath $workspace) { throw 'The DEV rebuild workspace still exists.' }
            $proof.temporaryWorkspaceRemoved = $true
        }
        catch {
            $failure = $_.Exception.Message
            $proof.error = $failure
            $proof.success = $false
        }
    }
    if ($reportCreated) {
        Save-Json (Join-Path $ReportDirectory 'proof.json') $proof
    }
}
if ($failure) { Write-Error $failure; exit 2 }
Write-Output ('DEV SOURCE REBUILD PASSED - evidence: ' + (Join-Path $ReportDirectory 'proof.json'))
