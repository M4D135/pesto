#requires -Version 5.1
param([string]$ReportPath='')
$ErrorActionPreference='Stop';Set-StrictMode -Off
$root=Split-Path $PSScriptRoot -Parent;$defs=@{};$results=[Collections.Generic.List[object]]::new()
foreach($file in @('Pesto-Safety.ps1','Pesto-Interventions.ps1','Pesto-Recovery.ps1','Pesto-ReceiptTools.ps1')){
 $t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root ('wad/'+$file)),[ref]$t,[ref]$e);if($e.Count){throw ($e.Message -join ';')}
 foreach($f in $ast.EndBlock.Statements){if($f -is [Management.Automation.Language.FunctionDefinitionAst]){$defs[$f.Name]=$f.Extent.Text}}
}
foreach($n in @('Add-PestoInterventionEvent','Write-PestoReconciliationAudit','Get-PestoReconciliationAudit','Invoke-PestoTaskReconciliationWorker')){. ([scriptblock]::Create($defs[$n]))}
function Assert {param($Value,$Message='Assertion failed');if(-not$Value){throw $Message}}
function Case {param($Name,[scriptblock]$Body);try{&$Body;$results.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''})}catch{$results.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message})}}
function New-Receipt {[pscustomobject]@{OperationId='a3111111111141118111111111111111';Plan=[pscustomobject]@{Domain='lab.test'};UpdatedUtc='';Phase='Uncertain';Entra='NotRequested';Protection='Lowered';ResultCode=97;Tasks=@()}}
function Write-PestoIntervention {param($Receipt);$script:Writes++}
Case 'Reconciliation audit persists a bounded closed event without changing outcome' {
 $r=New-Receipt;$script:Writes=0
 1..120|ForEach-Object{Write-PestoReconciliationAudit $r TaskRead Ready -TaskIndex 1 -NativeCode 42}
 Assert ($script:Writes -eq 120 -and $r.Timeline.Count -eq 96 -and $r.Phase -ceq 'Uncertain' -and $r.Protection -ceq 'Lowered' -and $r.ResultCode -eq 97)
 $rows=@(Get-PestoReconciliationAudit $r);Assert ($rows.Count -eq 96 -and $rows[-1].Sequence -eq 120 -and $rows[-1].NativeCode -eq 42)
}
Case 'Audit export excludes arbitrary state text XML credentials and malformed dates' {
 $r=New-Receipt;Write-PestoReconciliationAudit $r Protection Confirmed
 Add-PestoInterventionEvent $r Reconciliation 'Action=Protection;State=Confirmed;TaskIndex=0;Password=PRIVATE'
 Add-PestoInterventionEvent $r Reconciliation '<xml>PRIVATE</xml>'
 Add-PestoInterventionEvent $r Reconciliation 'Action=Protection;State=Confirmed;TaskIndex=0';$r.Timeline[-1].Utc='unknown'
 $json=@(Get-PestoReconciliationAudit $r)|ConvertTo-Json -Depth 6
 Assert ($json -notmatch 'PRIVATE|Password|xml|unknown');Assert (@(Get-PestoReconciliationAudit $r).Count -eq 1)
}
Case 'Invalid audit parameters are rejected before persistence' {
 foreach($caseArgs in @(@{Action='RawCommand';State='Requested'},@{Action='TaskRead';State='Ready';NativeCode=50000000000},@{Action='TaskRead';State='Ready';TaskIndex=9})){
  $script:Writes=0;$blocked=$false;try{Write-PestoReconciliationAudit (New-Receipt) @caseArgs}catch{$blocked=$true};Assert ($blocked -and $script:Writes -eq 0)
 }
}
$source=@'
function Get-PestoInterventionRoot {'fixture'}
function Read-PestoIntervention {param($Path);$script:TestReceipt}
function Get-PestoTaskRunResult {param($TaskName,$Transport,$TimeoutSec);if($script:ProbeThrows){throw 'Mock task unavailable'};$script:Probe}
function Set-PestoEffect {param($Name,$Value);$script:ActiveIntervention.$Name=$Value}
'@
$oldReadOnly=$env:PESTO_READONLY_SESSION;$env:PESTO_READONLY_SESSION=''
try {
 Case 'Actual reconciliation worker records READY code but never validates the operation' {
  $script:TestReceipt=New-Receipt;$script:TestReceipt.Tasks=@([pscustomobject]@{Name='\Pesto_Test';Computer='PC1';Hash=('a'*64);Phase='Started'})
  $script:Probe=[pscustomobject]@{State='READY';ResultNum=42};$script:ProbeThrows=$false
  $result=Invoke-PestoTaskReconciliationWorker ([pscustomobject]@{OperationId=$script:TestReceipt.OperationId;Domain='lab.test';Credential=$null}) $source
  $rows=@(Get-PestoReconciliationAudit $script:TestReceipt)
  Assert ($rows.Count -eq 2 -and $rows[-1].State -ceq 'Ready' -and $rows[-1].NativeCode -eq 42 -and $result.OperationId -ceq $script:TestReceipt.OperationId)
  Assert ($script:TestReceipt.Phase -ceq 'Uncertain' -and $script:TestReceipt.ResultCode -eq 97)
 }
 Case 'Unknown task and missing original hash are recorded without a false finish' {
  foreach($hash in @('',('a'*64))){
   $script:TestReceipt=New-Receipt;$script:TestReceipt.Tasks=@([pscustomobject]@{Name='\Pesto_Test';Computer='PC1';Hash=$hash;Phase='Started'})
   $script:Probe=[pscustomobject]@{State='UNKNOWN';ResultNum=267009}
   $null=Invoke-PestoTaskReconciliationWorker ([pscustomobject]@{OperationId=$script:TestReceipt.OperationId;Domain='lab.test';Credential=$null}) $source
   $row=@(Get-PestoReconciliationAudit $script:TestReceipt)[-1];Assert ($row.State -in @('Unknown','NoDefinition') -and $null -eq $row.NativeCode)
  }
 }
 Case 'Probe failure leaves durable unknown evidence and propagates failure' {
  $script:TestReceipt=New-Receipt;$script:TestReceipt.Tasks=@([pscustomobject]@{Name='\Pesto_Test';Computer='PC1';Hash=('a'*64);Phase='Started'});$script:ProbeThrows=$true
  $failed=$false;try{$null=Invoke-PestoTaskReconciliationWorker ([pscustomobject]@{OperationId=$script:TestReceipt.OperationId;Domain='lab.test';Credential=$null}) $source}catch{$failed=$true}
  Assert ($failed -and @(Get-PestoReconciliationAudit $script:TestReceipt)[-1].State -ceq 'Unknown')
 }
 Case 'Actual protection recovery persists requested confirmed and uncertain branches' {
  $s=$defs['Invoke-PestoRecoveryWorker'];Assert ($s -match 'Write-PestoReconciliationAudit \$r \$Request.Action Requested' -and $s -match 'Write-PestoReconciliationAudit \$r Protection Confirmed' -and $s -match 'Write-PestoReconciliationAudit \$r \$Request.Action Unknown')
 }
} finally {$env:PESTO_READONLY_SESSION=$oldReadOnly}
$failed=@($results|Where-Object{-not$_.Passed}).Count
$report=[pscustomobject]@{PowerShell=[string]$PSVersionTable.PSVersion;NoWindows=$true;NoAD=$true;Failed=$failed;Checks=$results.ToArray()}
if($ReportPath){$report|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $ReportPath -Encoding UTF8};$report|ConvertTo-Json -Depth 6;if($failed){exit 1}
