#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ReportDirectory)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){throw 'Windows PowerShell 5.1 requis.'}
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
# Chemin relatif résolu depuis le dossier courant PowerShell (les API .NET utilisent celui du processus).
$ReportDirectory=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ReportDirectory)
[void][IO.Directory]::CreateDirectory($ReportDirectory)
# Dependencies installed by the developer through the organization's approved source.
# No automatic gallery install, certificate trust change or elevated relaunch.
Import-Module PSScriptAnalyzer -RequiredVersion 1.24.0 -ErrorAction Stop
Import-Module Pester -RequiredVersion 5.7.1 -ErrorAction Stop
$diagnostics=@(foreach($file in Get-ChildItem -LiteralPath (Join-Path $root 'wad') -Filter 'Pesto-*.ps1' -File){
 Invoke-ScriptAnalyzer -Path $file.FullName -ErrorAction Stop
})
$diagnostics|Select-Object RuleName,Severity,ScriptName,Line,Message|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $ReportDirectory 'analysis.json') -Encoding UTF8
$config=New-PesterConfiguration
$config.Run.Path=@((Join-Path $root 'tests\Pesto.Safety.Tests.ps1'),(Join-Path $root 'tests\Pesto.RC21.Tests.ps1'));$config.Run.PassThru=$true
$config.TestResult.Enabled=$true;$config.TestResult.OutputPath=Join-Path $ReportDirectory 'pester.xml'
$config.Output.Verbosity='Detailed'
$result=Invoke-Pester -Configuration $config
if($result.FailedCount -or $result.SkippedCount -or $result.NotRunCount -or -not $result.PassedCount){throw 'Pester incomplet ou en échec. Publication interdite.'}
if(@($diagnostics|Where-Object{[string]$_.Severity -eq 'Error'}).Count){throw 'Analyse PowerShell en erreur. Publication interdite.'}
$nativeReport=Join-Path $ReportDirectory 'native\windows-rc19.json'
if(-not(Test-Path -LiteralPath $nativeReport)){throw 'Rapport Windows isolé absent.'}
$native=Get-Content -LiteralPath $nativeReport -Raw|ConvertFrom-Json
if($native.Version -ne '1.0' -or $native.Failed -ne 0 -or @($native.Checks).Count -lt 40){throw 'Rapport Windows isolé incomplet ou en échec.'}
foreach($reportName in @('names.json','rc21.json','rc22.json','rc23.json')){
 $path=Join-Path $ReportDirectory $reportName
 if(-not [IO.File]::Exists($path)){throw ('Preuve Windows absente : '+$reportName)}
 $evidence=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
 if($evidence.Version -ne '1.0' -or $evidence.Failed -ne 0 -or $evidence.Skipped -gt 0 -or @($evidence.Checks).Count -lt 25){throw ('Preuve Windows incomplète : '+$reportName)}
}
$record=[pscustomobject]@{Version='1.0';Utc=[DateTime]::UtcNow.ToString('o');PesterPassed=$result.PassedCount;NativeCases=@($native.Checks).Count;Signature='NOT_VALIDATED';InteractiveUac='NOT_VALIDATED';LiveAD='NOT_VALIDATED';PublicReleaseAuthorized=$false}
$record|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $ReportDirectory 'release-gate.json') -Encoding UTF8
Write-Warning 'Tests automatiques terminés. Cette étape ne signe ni ne publie le logiciel. Recette interactive et autorisation de diffusion encore requises.'
