#requires -Version 5.1
[CmdletBinding()]
param([ValidateRange(0,89)][int]$ShardIndex=0,[ValidateRange(1,90)][int]$ShardCount=1,
    [ValidateRange(1,3600)][int]$SuiteTimeoutSeconds=600,[string]$ReportDirectory='')
$ErrorActionPreference='Stop'
if($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5 -or -not [Environment]::Is64BitProcess){throw 'Windows PowerShell 5.1 x64 requis.'}
# Toutes les suites tournent ici, chacune dans un powershell.exe -STA séparé (y compris les suites WPF).
# tests/suites.json décrit les mêmes suites pour le lanceur Mac (tools/run_tests.py) ; tests/test_spark_h01.py
# vérifie que les deux listes restent identiques.
$suites=@('Run-SsoTests.ps1','Run-StartupTests.ps1','Run-EngineTests.ps1','Run-Engine120Tests.ps1','Run-ReadPool56Tests.ps1','Run-DirectoryDelta60Tests.ps1','Run-DirectoryDelta60MutationTests.ps1','Run-CompiledHelpers63Tests.ps1','Run-CompiledHelpers63MutationTests.ps1','Run-ManagedExtensionsTests.ps1','Run-ExtensionEffectsTests.ps1','Run-OfflineJoin109EntryTests.ps1','Run-OfflineJoin109EntryMutationTests.ps1','Run-OfflineJoin109NativeTests.ps1','Run-OfflineJoin109NativeMutationTests.ps1','Run-OfflineJoin109NativeLineTests.ps1','Run-OfflineJoin109NativeLineMutationTests.ps1','Run-OfflineJoin109ObserveTests.ps1','Run-OfflineJoin109ObserveMutationTests.ps1','Run-OfflineJoin109BlobTests.ps1','Run-OfflineJoin109BlobMutationTests.ps1','Run-OfflineJoin109ApplyTests.ps1','Run-OfflineJoin109ApplyMutationTests.ps1','Run-OfflineJoin109SecretTests.ps1','Run-OfflineJoin109SecretMutationTests.ps1','Run-AttributeEffects114MutationTests.ps1','Run-AttributeEntry114Tests.ps1','Run-AttributeEntry114MutationTests.ps1','Run-AttributeDiff114PreflightTests.ps1','Run-AttributeDiff114PreflightMutationTests.ps1','Run-ManagedScenario111MutationTests.ps1','Run-ManagedScenarioPreflight111Tests.ps1','Run-ManagedScenario111FormMutationTests.ps1','Run-ManagedScenario111PlanTests.ps1','Run-ManagedScenario111PlanMutationTests.ps1','Run-CampaignApproval117Tests.ps1','Run-CampaignApproval117WeakKeyTests.ps1','Run-CampaignApproval117MutationTests.ps1','Run-NamingFlows119Tests.ps1','Run-IntegrationTests.ps1','Run-CliOutputTests.ps1','Run-AuditPathTests.ps1','Run-AuditSinkTests.ps1','Run-OptionalIntegrationsTests.ps1','Run-RetiredFeaturesTests.ps1','Run-Workbench120Tests.ps1','Run-ConfigEditor120Tests.ps1','Run-NamingConvention119Tests.ps1','Run-ReceiptTools120Tests.ps1','Run-BatchNames120Tests.ps1','Run-Collections120Tests.ps1','Run-V1ImprovementsTests.ps1','Run-DomainNavigationTests.ps1','Run-RandomNamesTests.ps1','Run-SharedNameReservationTests.ps1','Run-NamesLoadingTests.ps1','Run-DirectoryCacheTests.ps1','Run-BulkPlanningTests.ps1','Run-ReliabilityTests.ps1','Run-WorkerContractTests.ps1','Run-SettingsTests.ps1','Run-InterventionViewTests.ps1','Run-UiPresentationTests.ps1','Run-WpfProjectionBenchTests.ps1','Run-ZoomTests.ps1','Run-ToolsTabsTests.ps1','Run-HomeDashboardTests.ps1','Run-AutomationTests.ps1','Run-JoinReservationTests.ps1','Run-BootIdentityTests.ps1','Run-OptionalPostCheckTests.ps1','Run-OptionalFollowupUiTests.ps1','Run-CommonTests.ps1','Run-PackageTests.ps1','Run-AsyncTests.ps1','Run-RC4Tests.ps1','Run-PilotageTests.ps1','Run-UxTests.ps1','Run-LoginTests.ps1','Run-LoginPreferencesTests.ps1','Run-QueueRemovalTests.ps1','Run-ProgressTests.ps1','Run-AcknowledgementTests.ps1','Run-RemotePreparationTests.ps1','Run-HeadlessAuditTests.ps1','Run-ReconciliationAuditTests.ps1','Run-SecretOutputsTests.ps1','Run-SessionMeasureTests.ps1','Run-WpfSessionTests.ps1','Run-BuildValidationTests.ps1')
# Suites lancées ailleurs, jamais oubliées en silence : toute autre Run-*.ps1 du dossier arrête ce lanceur.
$separate=@{
    'Run-AllTests.ps1'='ce lanceur'
    'Run-JoinTests.ps1'='lancement manuel (rapport windows-join-results.json dans tests)'
    'Run-Pesto21Tests.ps1'='TESTER.cmd (-Wpf)'
    'Run-Pesto22Tests.ps1'='TESTER.cmd et TEST_RC22.cmd (-Wpf)'
    'Run-Pesto23Tests.ps1'='TESTER.cmd et TEST_RC23.cmd (-Wpf)'
    'Run-RC14Validation.ps1'='validation historique RC14, lancement manuel'
    'Run-StabilisationTests.ps1'='recette 1.5, lancement manuel documenté'
}
$unlisted=@(Get-ChildItem -LiteralPath $PSScriptRoot -Filter 'Run-*.ps1' -File|Where-Object{$_.Extension -eq '.ps1' -and $suites -notcontains $_.Name -and -not $separate.ContainsKey($_.Name)}|ForEach-Object{$_.Name})
if($unlisted.Count){throw ('Suites absentes de Run-AllTests.ps1 : '+($unlisted -join ', '))}
$missing=@($suites|Where-Object{-not [IO.File]::Exists((Join-Path $PSScriptRoot $_))})
if($missing.Count){throw ('Suites introuvables : '+($missing -join ', '))}
if($ShardIndex -ge $ShardCount){throw 'ShardIndex doit etre inferieur a ShardCount.'}
if(-not $ReportDirectory){$ReportDirectory=Join-Path $PSScriptRoot ('results/windows-'+$ShardIndex)}
$ReportDirectory=[IO.Path]::GetFullPath($ReportDirectory)
[void][IO.Directory]::CreateDirectory($ReportDirectory)
. (Join-Path $PSScriptRoot 'helpers/Invoke-IsolatedSuite.ps1')
$selected=@(for($i=0;$i -lt $suites.Count;$i++){if(($i % $ShardCount) -eq $ShardIndex){$suites[$i]}})
$failures=[Collections.Generic.List[string]]::new()
$results=[Collections.Generic.List[object]]::new()
$report=Join-Path $ReportDirectory 'suites.json'
function Save-SuiteProgress([string]$Running){
    $data=[ordered]@{Schema=1;ShardIndex=$ShardIndex;ShardCount=$ShardCount;TotalSuites=$suites.Count;Selected=$selected;Running=$Running;Results=@($results.ToArray())}
    [IO.File]::WriteAllText($report,($data|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
}
Save-SuiteProgress ''
foreach($suite in $selected) {
    Write-Host ("`n=== ["+$ShardIndex+'/'+$ShardCount+'] '+$suite+' ===')
    Save-SuiteProgress $suite
    $result=Invoke-PestoIsolatedSuite -Path (Join-Path $PSScriptRoot $suite) -OutputDirectory $ReportDirectory -TimeoutSeconds $SuiteTimeoutSeconds
    $results.Add($result);Save-SuiteProgress ''
    Write-Host ($suite+': exit='+$result.ExitCode+' timeout='+$result.TimedOut+' duration='+$result.DurationSeconds+'s')
    if($result.ExitCode -ne 0){$failures.Add($suite)}
}
if($failures.Count){throw ('Suites en echec : '+($failures.ToArray() -join ', '))}
Write-Host ('Les '+$selected.Count+' suites du lot '+$ShardIndex+' sont passees. Ces doubles isoles ne qualifient pas AD.')
