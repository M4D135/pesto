#requires -Version 7.0
param([Parameter(Mandatory=$true)][string]$root,[Parameter(Mandatory=$true)][string]$repo,[Parameter(Mandatory=$true)][string]$node)
$ErrorActionPreference = 'Stop'

# Provided variables (assumed available in scope)
# $root = 'C:\Users\degun\actions-runner\PestoTargetedDiag-20261101'
# $repo = 'C:\Users\degun\actions-runner\_work\pesto\pesto'
# $node = 'C:\path\to\node.exe'

$releaseCommit = 'aeb00259b3ef094e14c584559b788433aea38901'
$releaseVersion = '2.0.8'
$releaseBase = 'https://github.com/M4D135/pesto/releases/download/v2.0.8'

$hashes = @{
    'PROD' = '0fcbb2ce36c5ffc3acd146cbbdbd3ca76d6bba2b0bf56bcd837dfef262f494bf'
    'DEV'  = 'a094152ada77f59e86368a38708c32813e558bf4df2bedecd3ae6853d8537519'
}

# 1. Create new input folder (refuse if exists)
$uiRetryInputs = Join-Path $root 'ui-retry-inputs'
if (Test-Path $uiRetryInputs) {
    throw "Directory already exists: $uiRetryInputs"
}
New-Item -ItemType Directory -Path $uiRetryInputs | Out-Null

$results = @()

foreach ($channel in @('PROD', 'DEV')) {
    # Determine paths
    $packDirName = "released-$channel"
    $zipPath = Join-Path $uiRetryInputs "Pesto_V2_${channel}_2.0.8.zip"
    $destDir = Join-Path $uiRetryInputs $packDirName
    $packRoot = Join-Path $destDir $channel

    # 2. Download ZIP
    $url = "$releaseBase/Pesto_V2_${channel}_2.0.8.zip"
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $zipPath

    # 3. Verify SHA256 against fixed official value
    $actualHash = (Get-FileHash $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $expectedHash = $hashes[$channel].ToLowerInvariant()
    if ($actualHash -ne $expectedHash) {
        throw "SHA256 mismatch for $channel release zip"
    }

    # 4. Extract to new folder
    Expand-Archive -LiteralPath $zipPath -DestinationPath $destDir

    # 5. Verify pack via node make-pack.mjs --verify
    # Capture stdout/stderr to a log file to avoid mixing with return array output
    $logFile = Join-Path $uiRetryInputs "verify-log-$channel.txt"
    & $node (Join-Path $repo 'v2/tools/pack/make-pack.mjs') --verify $packRoot *> $logFile
    if ($LASTEXITCODE -ne 0) {
        throw "make-pack.mjs --verify failed for $channel with exit code $LASTEXITCODE. Check log: $logFile"
    }

    # 6. Validate Pesto.package.json metadata
    $packageJsonPath = Join-Path $packRoot 'wad\Pesto.package.json'
    if (-not (Test-Path $packageJsonPath)) {
        throw "Pesto.package.json not found in $packRoot"
    }

    $pkgContent = Get-Content $packageJsonPath -Raw -Encoding UTF8
    $pkgObj = $pkgContent | ConvertFrom-Json

    if ($pkgObj.sourceCommit -ne $releaseCommit) {
        throw "sourceCommit mismatch for $channel. Expected $releaseCommit, got $($pkgObj.sourceCommit)"
    }
    if ($pkgObj.version -ne $releaseVersion) {
        throw "version mismatch for $channel. Expected $releaseVersion, got $($pkgObj.version)"
    }
    if ($pkgObj.channel -ne $channel) {
        throw "channel mismatch for $channel. Expected $channel, got $($pkgObj.channel)"
    }
    if ($pkgObj.distribution -ne 'official') {
        throw "distribution mismatch for $channel. Expected official, got $($pkgObj.distribution)"
    }

    # 7. Construct result object
    $currentPack = (Resolve-Path $packRoot).Path
    $targetPack = (Resolve-Path (Join-Path $repo "v2/out/$channel")).Path
    $targetZip = Join-Path (Resolve-Path (Join-Path $repo 'v2/out')).Path "Pesto_V2_${channel}_candidate.zip"

    $results += [PSCustomObject]@{
        channel          = $channel
        currentPack      = $currentPack
        targetPack       = $targetPack
        targetZip        = $targetZip
        releaseZipSha256 = $actualHash
    }
}

# 8. Write prepared.json UTF8 without BOM
$jsonContent = $results | ConvertTo-Json -Depth 10
$preparedJsonPath = Join-Path $uiRetryInputs 'prepared.json'

# Use .NET for UTF8 without BOM
[System.IO.File]::WriteAllText($preparedJsonPath, $jsonContent, [System.Text.UTF8Encoding]::new($false))

$results
