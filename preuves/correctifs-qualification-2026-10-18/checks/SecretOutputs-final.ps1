#requires -Version 5.1
[CmdletBinding()]
param([string]$ReportPath='', [string]$EvidenceDirectory='')
$ErrorActionPreference='Stop';Set-StrictMode -Off
$root='C:\PestoQualPersonal_20261018\candidate-fix\PROD';$defs=@{};$results=[Collections.Generic.List[object]]::new()
foreach($file in @('Pesto-Journal.ps1','Pesto-Core.ps1','Pesto-Support.ps1','Pesto-ReceiptTools.ps1','Pesto-Workspace.ps1','Pesto-Contracts.ps1','Pesto-Safety.ps1','Pesto-Directory.ps1','Pesto-Interventions.ps1')){
 $t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root ('wad/'+$file)),[ref]$t,[ref]$e)
 if($e.Count){throw 'Source parse error'}
 foreach($node in $ast.EndBlock.Statements){if($node -is [Management.Automation.Language.FunctionDefinitionAst]){$defs[$node.Name]=$node.Extent.Text}}
}
foreach($name in @('Protect-PestoLogText','New-PestoStructuredEvent','Write-PestoStructuredEvent','Write-PestoAuditQueued','Write-AuditLine','Write-Log','Get-ErrorDetail','New-PestoQueueReportHtml','Get-PestoDiagnosticText','Get-PestoDiagnosticEventClass','Get-PestoOperationSupport','Get-PestoReconciliationAudit','Get-PestoOperationReport','Get-PestoStatePresentation','Get-PestoStageLabel','Get-PestoEffectLabel','Get-PestoNativeGuidance','Format-OUPath','Split-PestoDistinguishedName','Export-PestoOperationSupport','Write-PestoNewExport','Assert-PestoPlainPath','Export-PestoInterventionRows','Write-PestoAtomicText','Get-PestoErrorExplanation')){
 if(-not $defs.ContainsKey($name)){throw ('Missing definition '+$name)}
 . ([scriptblock]::Create($defs[$name]))
}
function Assert {param($Value,$Message='Assertion failed');if(-not $Value){throw $Message}}
function Case {param($Name,[scriptblock]$Body);try{& $Body;$results.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''})}catch{$results.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=([string]$_.Exception.Message).Replace($marker,'[SYNTHETIC]')})}}
function Test-PestoIsAdministrator {$false}
$marker='PESTO_SYNTHETIC_SECRET_106_ONLY';$identity='PESTO_PRIVATE_IDENTITY_106_ONLY'
$payload='password='+$marker
$temporary=Join-Path $PSScriptRoot ('.pesto-secrets-'+[guid]::NewGuid().ToString('N'))
$output=if($EvidenceDirectory){[IO.Path]::GetFullPath($EvidenceDirectory)}else{$temporary}
if(Test-Path -LiteralPath $output){throw 'Choose a new evidence directory'}
[void][IO.Directory]::CreateDirectory($output)
function Save-Evidence {param($Name,$Text);[IO.File]::WriteAllText((Join-Path $output $Name),[string]$Text,[Text.UTF8Encoding]::new($false));Assert (-not ([string]$Text).Contains($marker)) 'Secret leaked'}
$receipt=[pscustomobject]@{Version='1.0';OperationId=[guid]::NewGuid().ToString();Phase='Verified';ResultCode=20;Rename='Confirmed';Move='NotRequested';Protection='NotChanged';Entra='NotRequested';UpdatedUtc='2026-10-16T00:00:00Z';StartedUtc='2026-10-16T00:00:00Z';FinishedUtc='2026-10-16T00:00:01Z';Plan=[pscustomobject]@{Nom_du_PC='PC-OLD';Nouveau_Nom='PC-NEW';Domain='example.test';Reference=$payload};ResultMessage=$payload;Credential=$payload;Timeline=@([pscustomobject]@{Stage='Reconciliation';State=$payload;Utc='2026-10-16T00:00:00Z';Sequence=1})}
try{
 Case 'Real async log writer filters error chains context and structured metadata' {
  . (Join-Path (Join-Path $root 'wad') 'Pesto-Common.ps1');Initialize-PestoRuntimeTypes -Root (Join-Path $root 'wad')
  $script:AuditFile=Join-Path $output ('Pesto_'+(Get-Date -Format 'yyyy-MM-dd')+'.log');[IO.File]::WriteAllText($script:AuditFile,'');$script:PestoAuditWriter=[Pesto.Runtime.AsyncAuditWriter]::new($script:AuditFile,64)
  try{
   Write-AuditLine $payload
   $inner=[Exception]::new('Authorization: Bearer '+$marker)
   Write-Log -Message $payload -Context $payload -Level ERROR -Err ([Exception]::new('token='+$marker,$inner))
   $event=New-PestoStructuredEvent -Message $payload -Context $payload -Stage $payload
   Assert (Write-PestoStructuredEvent $event)
   Assert ($script:PestoAuditWriter.Flush(2000))
  }finally{[void]$script:PestoAuditWriter.Close(2000);$script:PestoAuditWriter=$null}
  $text=[IO.File]::ReadAllText($script:AuditFile);Assert ($text.Contains('PESTO_EVENT') -and $text.Contains('********'));Assert (-not $text.Contains($marker))
 }
 Case 'HTML report filters all free text and escapes markup' {
  $row=[pscustomobject]@{Nom_du_PC='PC-OLD';Reference=$payload;Plan='<script>alert(1)</script>';Message=$payload;Controle_Detail=$payload;Statut='ERROR';Code=98}
  $html=New-PestoQueueReportHtml -Rows @($row) -Domain example.test -Server dc.example.test -Version 1.0 -ContextMode TEST
  Save-Evidence 'report.html' $html;Assert (-not $html.Contains('<script>'));Assert ($html.Contains('&lt;script&gt;'))
 }
 Case 'Masked diagnostics omit configuration credentials identities and raw errors' {
  $script:AuthUser=$identity;$script:DOMAINE=$identity;$script:DC=$identity;$script:JsonFile=$identity
  $script:CFG=@{Password=$marker;Credential=$marker};$script:LogEntries=@([pscustomobject]@{Time='12:00';Kind='err';Text=$payload})
  $script:BasePath=$null;$BasePath=$null;$script:Pesto_VERSION='1.0';$script:OUV=@{}
  $diagnostic=Get-PestoDiagnosticText
  Save-Evidence 'diagnostic.json' $diagnostic;Assert (-not $diagnostic.Contains($identity));Assert (($diagnostic|ConvertFrom-Json).RecentEventCategories.Count -eq 1)
 }
 Case 'Unmasked diagnostics still exclude secrets and raw log text' {Save-Evidence 'diagnostic-internal.json' (Get-PestoDiagnosticText -Redact $false)}
 Case 'Masked support bundle publishes only bounded receipt fields' {
  $data=Get-PestoOperationSupport $receipt
  Export-PestoOperationSupport (Join-Path $output 'masked.support') $data (Get-PestoDiagnosticText)
  foreach($file in Get-ChildItem (Join-Path $output 'masked.support') -File){Assert (-not [IO.File]::ReadAllText($file.FullName).Contains($marker))}
  $manifest=Get-Content (Join-Path $output 'masked.support/manifest.json') -Raw|ConvertFrom-Json
  foreach($entry in $manifest.Files){Assert ((Get-FileHash (Join-Path $output ('masked.support/'+$entry.Name))).Hash.ToLowerInvariant() -ceq $entry.SHA256)}
 }
 Case 'Internal support retains names but never credentials pasted in a reference' {
  $data=Get-PestoOperationSupport $receipt -Redact $false
  Save-Evidence 'operation-internal.json' ($data|ConvertTo-Json -Depth 10);Assert ($data.Computer -ceq 'PC-OLD')
 }
 Case 'Internal report keeps useful identity and filters credential-like text' {
  $ticket=Get-PestoOperationReport $receipt -Redact $false
  Save-Evidence 'report.txt' $ticket;Assert ($ticket.Contains('PC-OLD'))
 }
 Case 'User-facing error explanation filters message and stage' {
  Save-Evidence 'error.json' ((Get-PestoErrorExplanation -Message $payload -Stage $payload)|ConvertTo-Json)
 }
 Case 'CSV export of interventions filters credential-like text and keeps CSV injection guard' {
  $row=[pscustomobject]@{UpdatedLocal='01/01/2026 00:00:00 +00:00';Computer='PC-OLD';NewName='PC-NEW';StatusLabel='VÉRIFIÉ';StageLabel=$payload;EntraLabel='NotRequested';NextAction='=cmd /c calc'}
  $csvPath=Join-Path $output 'interventions.csv'
  Export-PestoInterventionRows -Path $csvPath -Rows @($row)
  $csv=[IO.File]::ReadAllText($csvPath,[Text.UTF8Encoding]::new($false,$true))
  Save-Evidence 'interventions.csv' $csv
  Assert ($csv.Contains('password=********'))
  Assert ($csv.Contains("'=cmd /c calc"))
  Assert (-not $csv.Contains($marker))
 }
}finally{
 if($script:PestoAuditWriter){[void]$script:PestoAuditWriter.Close(2000);$script:PestoAuditWriter=$null}
 if(-not $EvidenceDirectory -and [IO.Directory]::Exists($output)){[IO.Directory]::Delete($output,$true)}
}
$report=[ordered]@{Suite='SecretOutputs';Passed=@($results|Where-Object{$_.Passed}).Count;Failed=@($results|Where-Object{-not $_.Passed}).Count;NoAD=$true;NoVM=$false;PowerShell=$PSVersionTable.PSVersion.ToString();Scope='Synthetic canary in real local textual outputs; no screenshots or arbitrary-secret guarantee';Tests=$results.ToArray()}
if($ReportPath){[IO.File]::WriteAllText($ReportPath,($report|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))}
$report|ConvertTo-Json -Depth 6
if($report.Failed){exit 1}
