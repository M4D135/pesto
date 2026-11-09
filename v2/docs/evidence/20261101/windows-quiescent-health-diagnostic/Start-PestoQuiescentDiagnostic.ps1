#Requires -Version 5.1
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$ErrorActionPreference='Stop'
$root='C:\Users\degun\actions-runner\PestoTargetedDiag-20261101'
$repo='C:\Users\degun\actions-runner\_work\pesto\pesto'
$dotnet='C:\Users\degun\actions-runner\_dotnet\dotnet.exe'
$result=[ordered]@{kind='pesto.quiescent-journal-diagnostic-launch';diagnosticOnly=$true;fullSuite=$false;success=$false;startedUtc=[DateTimeOffset]::UtcNow.ToString('O');sessionId=[Diagnostics.Process]::GetCurrentProcess().SessionId;userInteractive=[Environment]::UserInteractive}
try {
    Set-Location $root
    if ((& 'C:\Program Files\Git\cmd\git.exe' -C $repo rev-parse HEAD).Trim() -cne 'ad0f78935b24281dce91f038d478b4516c7bee20') {throw 'Actions checkout no longer matches the observed build'}
    $base=Join-Path $repo 'v2\out\baseline-PROD'
    $candidate=Join-Path $repo 'v2\out\PROD'
    if ((Get-FileHash (Join-Path $base 'Pesto.exe')).Hash.ToLowerInvariant() -cne 'e4627b726b425e53c3f9949cb0460013fd582bd1c305efca02548c05ce6f04f5') {throw 'Baseline hash changed'}
    if ((Get-FileHash (Join-Path $candidate 'Pesto.exe')).Hash.ToLowerInvariant() -cne '10d9c8867f54dff07cefd2339ea50d790e9210dbfe8ed76bc051c410a09a857b') {throw 'Candidate hash changed'}
    $runner=Join-Path $root 'quiescent-src\v2\tools\qualification\Pesto.UpdateQualification\bin\Release\net10.0\Pesto.UpdateQualification.dll'
    $result.runnerSha256=(Get-FileHash -LiteralPath $runner).Hash.ToLowerInvariant()
    $result.sdkVersion=(& $dotnet --version).Trim()
    $result | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'quiescent-launch.json') -Encoding utf8
    $ErrorActionPreference='Continue'
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'Invoke-PestoQuiescentDiagnostic.ps1') -BasePack $base -CandidatePack $candidate -CandidateZip (Join-Path $repo 'v2\out\Pesto_V2_PROD_candidate.zip') -RunnerDll $runner -DotNet $dotnet -ReportDirectory (Join-Path $root 'quiescent-report') *> (Join-Path $root 'quiescent-targeted.log')
    $ErrorActionPreference='Stop'
    $result.exitCode=$LASTEXITCODE
    $result.success=$LASTEXITCODE -eq 0
} catch { $result.error=$_.Exception.Message }
finally { $result.finishedUtc=[DateTimeOffset]::UtcNow.ToString('O'); $result | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'quiescent-result.json') -Encoding utf8 }
if(-not $result.success){exit 2}
