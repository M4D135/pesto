#Requires -Version 5.1
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$ErrorActionPreference='Stop'
$root='C:\Users\degun\actions-runner\PestoTargetedDiag-20261101'
$repo='C:\Users\degun\actions-runner\_work\pesto\pesto'
$dotnet='C:\Users\degun\actions-runner\_dotnet\dotnet.exe'
$result=[ordered]@{kind='pesto.targeted-update-diagnostic-launch';diagnosticOnly=$true;fullSuite=$false;success=$false;startedUtc=[DateTimeOffset]::UtcNow.ToString('O');sessionId=[Diagnostics.Process]::GetCurrentProcess().SessionId;userInteractive=[Environment]::UserInteractive}
try {
    Set-Location $root
    if ((& 'C:\Program Files\Git\cmd\git.exe' -C $repo rev-parse HEAD).Trim() -cne '61c2ffd9439cc5dac0e9f8d66d08558dad2084b8') {throw 'Actions checkout no longer matches the observed build'}
    $base=Join-Path $repo 'v2\out\baseline-PROD'
    $candidate=Join-Path $repo 'v2\out\PROD'
    if ((Get-FileHash (Join-Path $base 'Pesto.exe')).Hash.ToLowerInvariant() -cne 'e4627b726b425e53c3f9949cb0460013fd582bd1c305efca02548c05ce6f04f5') {throw 'Baseline hash changed'}
    if ((Get-FileHash (Join-Path $candidate 'Pesto.exe')).Hash.ToLowerInvariant() -cne '257b832f6affa1001f6d33176dd61e9727d71ffd9ff9504f24d3e5d5aab838e7') {throw 'Candidate hash changed'}
    $hook=Join-Path $root 'Hook\bin\Release\net10.0\PestoDiagHook.dll'
    $runner=Join-Path $repo 'v2\tools\qualification\Pesto.UpdateQualification\bin\Release\net10.0\Pesto.UpdateQualification.dll'
    $result.runnerSha256=(Get-FileHash -LiteralPath $runner).Hash.ToLowerInvariant()
    $result.hookSha256=(Get-FileHash -LiteralPath $hook).Hash.ToLowerInvariant()
    $result.sdkVersion=(& $dotnet --version).Trim()
    $result | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'launch.json') -Encoding utf8
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'Invoke-PestoTargetedHealthDiagnostic.ps1') -BasePack $base -CandidatePack $candidate -CandidateZip (Join-Path $repo 'v2\out\Pesto_V2_PROD_candidate.zip') -RunnerDll $runner -DotNet $dotnet -ReportDirectory (Join-Path $root 'report') -HookAssembly $hook -ExpectedHookSha256 '2b25a844b51aae3cec718a9d0483b9c4d126136049efbbd027734145ce7d08f3' *> (Join-Path $root 'targeted.log')
    $result.exitCode=$LASTEXITCODE
    $result.success=$LASTEXITCODE -eq 0
} catch { $result.error=$_.Exception.Message }
finally { $result.finishedUtc=[DateTimeOffset]::UtcNow.ToString('O'); $result | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'result.json') -Encoding utf8 }
if(-not $result.success){exit 2}
