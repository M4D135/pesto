#requires -Version 5.1
param([string]$ReportPath='')
$ErrorActionPreference='Stop';Set-StrictMode -Off
$root=Split-Path $PSScriptRoot -Parent;$defs=@{}
foreach($f in @('Pesto-Core.ps1','Pesto-Contracts.ps1','Pesto-Journal.ps1','Pesto-Directory.ps1','Pesto-Async.ps1','Pesto-Operations.ps1','Pesto-Safety.ps1')){
 $t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root ('wad/'+$f)),[ref]$t,[ref]$e);if($e.Count){throw ($e.Message -join '; ')}
 foreach($node in $ast.EndBlock.Statements){if($node -is [Management.Automation.Language.FunctionDefinitionAst]){$defs[$node.Name]=$node.Extent.Text}}
}
foreach($name in @('Get-PestoPreflightBudget','Start-PestoNextQueueTask','Assert-PestoWorkerMayContinue','Set-PestoQueueCancellationFence','Update-PestoPreflightFreshness','Get-PestoPreflightConfirmationText','Test-PestoFreshCheck','Get-PestoDataAgeText','Assert-PestoPlainPath','Remove-PestoExpiredLogs','Complete-PestoQueuePreflight','New-PestoQueueMonitor','Set-PestoWorkerStage','Complete-PestoWorkerTiming','Publish-PestoWorkerLog','Receive-PestoQueueEvents','Get-PestoReadFailure','Get-PestoNativeFailureCode','Get-PestoNativeGuidance','Invoke-PestoReadRetry')){. ([scriptblock]::Create($defs[$name]))}
$checks=[Collections.Generic.List[object]]::new()
function Assert {param($Condition,$Message='Assertion failed');if(-not $Condition){throw $Message}}
function Case {param($Name,[scriptblock]$Body);try{& $Body;$checks.Add([pscustomobject]@{Name=$Name;Passed=$true})}catch{$checks.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message})}}
function Protect-PestoLogText {param($Text);return [string]$Text}
function Add-LogLine {param($Text,$Kind)}
function Write-Log {param($Message,$Level,$ErrorRecord,$Context)}
function Show-MsgWarning {param($Text)}
function Get-PestoPlanSignature {param($Row);return $Row.Key}
function Get-PestoRowPlanText {param($Row,$InDomain);return 'plan retained'}
function Get-PestoConfigurationSignature {param($Config);return 'TEST'}
function Save-PestoQueueCheckpointSafe {}
function Stop-PestoPilotagePulse {}
function Set-PestoQueueUiLocked {param($Locked)}
function Sync-Grid {}
function Update-QueueButtons {}
function Run-Queue {$script:Runs++}
Case 'Preflight deadline scales and remains bounded' {Assert ((Get-PestoPreflightBudget 1) -eq 120);Assert ((Get-PestoPreflightBudget 30) -eq 480);Assert ((Get-PestoPreflightBudget 200) -eq 1800)}
Case 'Inventory freshness distinguishes missing stale and incomplete' {
 $now=[DateTimeOffset]::UtcNow
 Assert ((Get-PestoDataAgeText '') -eq 'Données non chargées')
 Assert ((Get-PestoDataAgeText $now.AddSeconds(-30).ToString('o') -Now $now) -match 'récent')
 Assert ((Get-PestoDataAgeText $now.AddMinutes(-3).ToString('o') -Now $now) -match 'à actualiser')
 Assert ((Get-PestoDataAgeText $now.ToString('o') -Complete $false -Now $now) -match 'incomplète')
}
function Reset-Preflight {
 $script:table=[pscustomobject]@{Rows=@(foreach($k in @('A','B')){[pscustomobject]@{Key=$k;Objet_GUID='';TargetOUGuid='';Precontrole='';Controle_Detail='';Controle_Utc='';Controle_Signature='';Plan='';ConfigStamp='';NeedsReview=$true}})}
 $script:PreflightCache=@{};$script:PreflightGeneration=8;$script:PreflightThenExecute=$true;$script:Runs=0;$script:LblQueueActivity=[pscustomobject]@{Text=''}
}
Case 'Interrupted preflight preserves completed row without automatic execution' {
 Reset-Preflight;$q=[Collections.Concurrent.ConcurrentQueue[object]]::new();$q.Enqueue([pscustomobject]@{Key='A';State='VÉRIFIÉ';Utc=[DateTime]::UtcNow.ToString('o');Guid='';TargetOUGuid='';Detail='local fixture'})
 $ctx=[pscustomobject]@{Generation=8;Keys=@('A','B');Progress=[hashtable]::Synchronized(@{Results=$q;Cancelled=$false})}
 Complete-PestoQueuePreflight -Failure ([Exception]::new('cancel')) -Context $ctx
 Assert ($script:table.Rows[0].Precontrole -eq 'VÉRIFIÉ');Assert ($script:table.Rows[1].Precontrole -eq 'À REFAIRE');Assert ($script:PreflightCache.Count -eq 1);Assert ($script:Runs -eq 0)
}
Case 'Invalid partial result clears approval and never executes' {
 Reset-Preflight;$q=[Collections.Concurrent.ConcurrentQueue[object]]::new();$q.Enqueue([pscustomobject]@{Key='UNKNOWN';State='VÉRIFIÉ';Utc=[DateTime]::UtcNow.ToString('o')})
 Complete-PestoQueuePreflight -Failure ([Exception]::new('timeout')) -Context ([pscustomobject]@{Generation=8;Keys=@('A','B');Progress=@{Results=$q;Cancelled=$false}})
 Assert ($script:PreflightCache.Count -eq 0 -and $script:Runs -eq 0);Assert (@($script:table.Rows|Where-Object{$_.Precontrole -eq 'À REFAIRE'}).Count -eq 2)
}
Case 'Late preflight generation ignored' {Reset-Preflight;Complete-PestoQueuePreflight -Failure ([Exception]::new('late')) -Context ([pscustomobject]@{Generation=7;Keys=@('A','B')});Assert ($script:table.Rows[0].Precontrole -eq '')}
Case 'Preflight display confirmation and execution expire together at two minutes' {
 $utc=[DateTimeOffset]::UtcNow.AddSeconds(-150).ToString('o')
 $row=[pscustomobject]@{Key='A';Statut='';Precontrole='VÉRIFIÉ';Controle_Signature='A';Controle_Utc=$utc;Traiter=$true;Deplacer=$false}
 $script:table=[pscustomobject]@{Rows=@($row);DefaultView=@($row)};$script:PreflightCache=@{A=[pscustomobject]@{State='VÉRIFIÉ';Utc=$utc}}
 Assert (-not(Test-PestoFreshCheck $row 'A'))
 Update-PestoPreflightFreshness;Assert ($row.Precontrole -eq 'PÉRIMÉ')
 Assert ((Get-PestoPreflightConfirmationText @($row)) -match '2 min : 0.*périmés : 1')
}
Case 'Known preflight refusal never expires into approval' {
 $script:PreflightCache.A.State='BLOQUÉ';Update-PestoPreflightFreshness;Assert ($script:table.Rows[0].Precontrole -eq 'BLOQUÉ')
}
Case 'First worker transition records previous stage in initially empty queue' {$script:PestoQueueMonitor=New-PestoQueueMonitor 'LOCAL';Set-PestoWorkerStage 'Lecture AD';Assert ($script:PestoQueueMonitor.StageTimings.Count -eq 1);Assert ($script:PestoQueueMonitor.Stage.Kind -eq 'Attente réseau / Windows')}
function Add-PestoPerformanceSample {throw 'fixture: telemetry unavailable'}
Case 'Telemetry failure cannot break worker event processing' {$script:PestoMetricsDropped=0;Receive-PestoQueueEvents $script:PestoQueueMonitor;Assert ($script:PestoMetricsDropped -eq 1)}
Case 'Final worker timing is recorded once and stops the stage clock' {
 $script:PestoQueueMonitor=New-PestoQueueMonitor 'LOCAL';Set-PestoWorkerStage 'Jonction Windows'
 Complete-PestoWorkerTiming $script:PestoQueueMonitor;Complete-PestoWorkerTiming $script:PestoQueueMonitor
 Assert ($script:PestoQueueMonitor.StageTimings.Count -eq 2)
 Assert (-not $script:PestoQueueMonitor.StageClock.IsRunning)
 $stages=$script:PestoQueueMonitor.StageTimings.ToArray();Assert ($stages[1].Kind -eq 'Écriture')
}
Case 'Partial failed read is discarded before retry' {
 $script:Attempts=0;$r=@(Invoke-PestoReadRetry -Read {$script:Attempts++;if($script:Attempts -eq 1){'partial';throw [ComponentModel.Win32Exception]::new(1722)};'complete'} -Attempts 2 -DelayMs 0)
 Assert ($r.Count -eq 1 -and $r[0] -eq 'complete' -and $script:Attempts -eq 2)
}
Case 'Terminal read failure publishes no partial objects' {
 $received=[Collections.Generic.List[object]]::new();$failed=$false
 try{Invoke-PestoReadRetry -Read {'partial';throw [ComponentModel.Win32Exception]::new(5)} -DelayMs 0|ForEach-Object{$received.Add($_)}}catch{$failed=$true}
 Assert ($failed -and $received.Count -eq 0)
}
Case 'Cancelled successful read cannot publish a stale result' {
 $cancel=@{Cancelled=$false};$received=[Collections.Generic.List[object]]::new();$failed=$false
 try{Invoke-PestoReadRetry -Read {$cancel.Cancelled=$true;'stale'} -Cancellation $cancel -DelayMs 0|ForEach-Object{$received.Add($_)}}catch{$failed=$true}
 Assert ($failed -and $received.Count -eq 0)
}
Case 'Cancellation fence prevents starting a later mutation' {
 $script:PestoQueueMonitor=New-PestoQueueMonitor 'LOCAL';Set-PestoQueueCancellationFence $script:PestoQueueMonitor;$failed=$false
 try{Assert-PestoWorkerMayContinue -Mutation}catch{$failed=$true}
 Assert ($failed -and $script:PestoQueueMonitor.CancelRequested -and -not $script:PestoQueueMonitor.MutationStarted)
}
function Test-PestoAsyncOperationRunning {param($Name);return $script:WorkerActive}
function Complete-PestoQueueRun {$script:CompletedRuns++}
Case 'Stop after current worker preserves its result and leaves remaining PCs unstarted' {
 $script:CompletedRuns=0;$script:QueueStopRequested=$true;$script:WorkerActive=$true
 $rows=@([pscustomobject]@{Statut='OK';Traiter=$false;Message='confirmed'},[pscustomobject]@{Statut='';Traiter=$true;Message=''},[pscustomobject]@{Statut='';Traiter=$true;Message=''})
 $script:QueueRunState=[pscustomobject]@{Items=@($rows|ForEach-Object{[pscustomobject]@{Row=$_}});Index=1;CancelCount=0}
 Start-PestoNextQueueTask;Assert ($script:CompletedRuns -eq 0 -and $script:QueueRunState.Index -eq 1)
 $script:WorkerActive=$false;Start-PestoNextQueueTask
 Assert ($rows[0].Statut -eq 'OK' -and $rows[0].Message -eq 'confirmed')
 Assert ($rows[1].Statut -eq 'NON LANCÉ' -and $rows[2].Statut -eq 'NON LANCÉ' -and -not $rows[1].Traiter -and -not $rows[2].Traiter)
 Assert ($script:CompletedRuns -eq 1 -and $script:QueueRunState.CancelCount -eq 2)
}
Case 'Access errors are not retried' {$script:Attempts=0;try{Invoke-PestoReadRetry -Read {$script:Attempts++;throw [ComponentModel.Win32Exception]::new(5)} -Attempts 3 -DelayMs 0}catch{};Assert ($script:Attempts -eq 1)}
Case 'Transient read failures retry up to configured count' {$script:Attempts=0;$r=Invoke-PestoReadRetry -Read {$script:Attempts++;if($script:Attempts -eq 1){throw [ComponentModel.Win32Exception]::new(1722)};return 'ok'} -Attempts 2 -DelayMs 0;Assert ($r -eq 'ok' -and $script:Attempts -eq 2)}
$testRoot=Join-Path $PSScriptRoot ('.retention-'+[Guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($testRoot)
try{
 foreach($name in @('Pesto_2020-01-01.log','Pesto_2020-01-02.log','Pesto_notes.log','receipt.json')){$p=Join-Path $testRoot $name;[IO.File]::WriteAllText($p,'fixture');[IO.File]::SetLastWriteTimeUtc($p,[DateTime]::UtcNow.AddDays(-100))}
 Case 'Retention zero preserves every log' {Assert ((Remove-PestoExpiredLogs $testRoot -Days 0) -eq 0);Assert (@(Get-ChildItem $testRoot).Count -eq 4)}
 Case 'Retention preserves current log receipts and noncanonical names' {
  Assert ((Remove-PestoExpiredLogs $testRoot -Days 30 -CurrentFile (Join-Path $testRoot 'Pesto_2020-01-02.log')) -eq 1)
  Assert (@(Get-ChildItem $testRoot).Count -eq 3);Assert (Test-Path (Join-Path $testRoot 'receipt.json'))
 }
}finally{Remove-Item $testRoot -Recurse -Force}
$failed=@($checks|Where-Object{-not $_.Passed}).Count;$report=[pscustomobject]@{Checks=$checks.ToArray();Failed=$failed;WindowsExecuted=$false;ADExecuted=$false}
if($ReportPath){$report|ConvertTo-Json -Depth 5|Set-Content $ReportPath -Encoding UTF8};$report|ConvertTo-Json -Depth 5;if($failed){exit 1}
