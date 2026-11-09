#requires -Version 5.1
param([string]$ReportPath='')
$ErrorActionPreference='Stop';Set-StrictMode -Off
$runtime=Join-Path (Split-Path $PSScriptRoot -Parent) 'wad';$defs=@{};$results=[Collections.Generic.List[object]]::new()
foreach($file in @('Pesto-Async.ps1','Pesto-Journal.ps1','Pesto-Enterprise.ps1','Pesto-Automation.ps1')){
 $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $runtime $file),[ref]$tokens,[ref]$errors)
 if($errors.Count){throw ($errors.Message -join '; ')}
 foreach($node in $ast.EndBlock.Statements){if($node -is [Management.Automation.Language.FunctionDefinitionAst]){$defs[$node.Name]=$node.Extent.Text}}
}
foreach($name in @('New-PestoQueueMonitor','Publish-PestoWorkerLog','Enable-PestoHeadlessEventStream','Write-PestoHeadlessEvents','Close-PestoHeadlessAudit','Protect-PestoLogText','New-PestoStructuredEvent','Write-PestoStructuredEvent','Write-PestoAuditQueued')){. ([scriptblock]::Create($defs[$name]))}
function Assert {param($Value,$Message='Assertion failed');if(-not $Value){throw $Message}}
function Case {param($Name,[scriptblock]$Body);try{& $Body;$results.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''})}catch{$results.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message})}}
function Set-PestoPersistenceWarning {param($Message);$script:Warning=$Message}
function Write-AuditLine {param($Text,$Kind);$script:Summary=$Text}
function Reset-TestAudit {
 $script:Warning='';$script:Summary='';$script:PestoAuditLost=$false;$script:PestoAuditClock=$null
 $script:AuditFile=Join-Path $temp ('Pesto_'+(Get-Date -Format 'yyyy-MM-dd')+'.log')
 $script:PestoAuditWriter=[pscustomobject]@{Accept=$true;Lines=[Collections.Generic.List[string]]::new();CloseOK=$true;CloseLimit=0}
 $script:PestoAuditWriter|Add-Member ScriptMethod TryWrite {param($Text);if(-not $this.Accept){return $false};$this.Lines.Add($Text);return $true}
 $script:PestoAuditWriter|Add-Member ScriptMethod Close {param($Limit);$this.CloseLimit=$Limit;return $this.CloseOK}
 $script:PestoQueueMonitor=New-PestoQueueMonitor -Computer PC01 -OperationId 'aaaaaaaa-1111-2222-3333-bbbbbbbbbbbb'
}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('pesto-audit-'+[Guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($temp)
try{
 Case 'GUI monitor keeps the bounded event queue and never invokes a sink' {
  Reset-TestAudit;Publish-PestoWorkerLog 'GUI event';Assert ($script:PestoQueueMonitor.Events.Count -eq 1 -and $script:PestoAuditWriter.Lines.Count -eq 0)
 }
 Case 'Headless events reach the sink immediately before final draining' {
  Reset-TestAudit;Enable-PestoHeadlessEventStream $script:PestoQueueMonitor
  Publish-PestoWorkerLog 'first' -Level WARN;Publish-PestoWorkerLog 'second'
  Assert ($script:PestoAuditWriter.Lines.Count -eq 2 -and $script:PestoQueueMonitor.Events.Count -eq 0)
  Write-PestoHeadlessEvents $script:PestoQueueMonitor
  Assert ($script:PestoAuditWriter.Lines.Count -eq 2 -and $script:PestoQueueMonitor.AuditStreamed -eq 2 -and $script:Summary -match '2 événement')
 }
 Case 'Stream preserves original UTC and redacts tokens' {
  Reset-TestAudit;Enable-PestoHeadlessEventStream $script:PestoQueueMonitor
  $entry=[pscustomobject]@{Text='token=secret-value';Level='INFO';Context='test';OperationId=$script:PestoQueueMonitor.OperationId;WorkerId=$script:PestoQueueMonitor.WorkerId;Stage='Read';BuildSHA256='';Time=[datetime]'2026-10-15T10:12:13Z'}
  [void](& $script:PestoQueueMonitor.AuditSink $entry)
  $line=$script:PestoAuditWriter.Lines[0];Assert (-not $line.Contains('secret-value')) 'Redaction failure'
  $event=$line.Substring(12)|ConvertFrom-Json;Assert (([datetime]$event.Utc).ToUniversalTime() -eq $entry.Time.ToUniversalTime()) ('Timestamp '+[string]$event.Utc+' expected '+[string]$entry.Time)
 }
 Case 'Quoted JSON secrets escaped quotes and authorization schemes are fully redacted' {
  $marker='PESTO_CANARY_'+[guid]::NewGuid().ToString('N')
  $samples=@(
   ('{"password":"'+$marker+'"}'),
   ('{"Password" : "escaped\\\" '+$marker+'"}'),
   ('{"secret":"unterminated '+$marker),
   ("{'token': '"+$marker+"'}"),
   ('Authorization: Bearer '+$marker),
   ('{"authorization":"Basic '+$marker+'"}'),
   ('access_token='+$marker),('client_secret='+$marker),('api-key='+$marker),
   ('https://user:'+$marker+'@example.test/'),('https://'+$marker+'@example.test/'),
   ('sa_password='+$marker),('accessToken='+$marker),('secret_key='+$marker),
   ('Authorization: Negotiate '+$marker),('Authorization: Digest username=x, response='+$marker),
   ('token=Bearer prefix '+$marker),('{"secret": {"nested": "'+$marker+'"}}'))
  foreach($sample in $samples){Assert (-not (Protect-PestoLogText $sample).Contains($marker)) 'Synthetic marker leaked'}
  Assert ((Protect-PestoLogText 'status=Ready computer=PC001') -ceq 'status=Ready computer=PC001')
  Assert ((Protect-PestoLogText ('x'*65537)) -eq '[contenu masqué : taille excessive]')
 }
 Case 'Real event and queued writer redact JSON secrets in message stage and context' {
  Reset-TestAudit;Enable-PestoHeadlessEventStream $script:PestoQueueMonitor
  $marker='PESTO_CANARY_'+[guid]::NewGuid().ToString('N');$payload='{"password":"'+$marker+'"}'
  $entry=[pscustomobject]@{Text=$payload;Level='INFO';Context=$payload;Stage=$payload;OperationId=$script:PestoQueueMonitor.OperationId;WorkerId=$script:PestoQueueMonitor.WorkerId;BuildSHA256='';Time=[datetime]::UtcNow}
  [void](& $script:PestoQueueMonitor.AuditSink $entry)
  Assert ($script:PestoAuditWriter.Lines.Count -eq 1)
  Assert (-not $script:PestoAuditWriter.Lines[0].Contains($marker)) 'Synthetic marker leaked in event metadata'
 }
 Case 'Temporary sink failure falls back once without duplicating accepted events' {
  Reset-TestAudit;Enable-PestoHeadlessEventStream $script:PestoQueueMonitor;$script:PestoAuditWriter.Accept=$false
  Publish-PestoWorkerLog 'fallback';Assert ($script:PestoQueueMonitor.Events.Count -eq 1 -and $script:PestoQueueMonitor.AuditStreamFailed -eq 1)
  $script:PestoAuditWriter.Accept=$true;Write-PestoHeadlessEvents $script:PestoQueueMonitor
  Write-PestoHeadlessEvents $script:PestoQueueMonitor
  Assert ($script:PestoAuditWriter.Lines.Count -eq 1 -and $script:PestoQueueMonitor.Events.Count -eq 0)
 }
 Case 'Sink exceptions never escape the worker event publisher' {
  Reset-TestAudit;Enable-PestoHeadlessEventStream $script:PestoQueueMonitor;$script:PestoQueueMonitor.AuditSink={throw 'test failure'}
  Publish-PestoWorkerLog 'event';Assert ($script:PestoQueueMonitor.Events.Count -eq 1 -and $script:PestoQueueMonitor.AuditStreamFailed -eq 1)
 }
 Case 'Exhausted fallback queue reports losses and remains bounded' {
  Reset-TestAudit;$script:PestoQueueMonitor.AuditStream=$true
  for($i=0;$i -lt 2005;$i++){Publish-PestoWorkerLog ('event '+$i)}
  Assert ($script:PestoQueueMonitor.Events.Count -eq 2000 -and $script:PestoQueueMonitor.DroppedEvents -eq 5)
 }
 Case 'Final drain records persistent writer rejection as incomplete' {
  Reset-TestAudit;Publish-PestoWorkerLog 'lost';$script:PestoAuditWriter.Accept=$false
  Write-PestoHeadlessEvents $script:PestoQueueMonitor;Assert ($script:PestoAuditLost -and $script:Summary -match '1 non conservé')
 }
 Case 'Closing is bounded and incomplete output uses stderr only' {
  Reset-TestAudit;$writer=$script:PestoAuditWriter;$writer.CloseOK=$false
  $previous=[Console]::Error;$capture=[IO.StringWriter]::new()
  try{[Console]::SetError($capture);$out=@(Close-PestoHeadlessAudit);Assert ($out.Count -eq 0 -and $capture.ToString().Contains('PESTO_AUDIT_INCOMPLETE'))}
  finally{[Console]::SetError($previous);$capture.Dispose()}
  Assert ($writer.CloseLimit -eq 2000 -and $null -eq $script:PestoAuditWriter)
 }
 Case 'Real async writer persists streaming events before worker completion' {
  Reset-TestAudit
  . (Join-Path $runtime 'Pesto-Common.ps1');Initialize-PestoRuntimeTypes -Root $runtime
  [IO.File]::WriteAllText($script:AuditFile,'')
  $script:PestoAuditWriter=[Pesto.Runtime.AsyncAuditWriter]::new($script:AuditFile,64)
  try{
   Enable-PestoHeadlessEventStream $script:PestoQueueMonitor
   for($i=0;$i -lt 12;$i++){Publish-PestoWorkerLog ('stream '+$i)}
   Assert ($script:PestoAuditWriter.Flush(1500)) 'Writer flush failed'
   $lines=@([IO.File]::ReadAllLines($script:AuditFile)|Where-Object{$_ -like 'PESTO_EVENT *'})
   Assert ($lines.Count -eq 12 -and $script:PestoQueueMonitor.Events.Count -eq 0) 'Events were delayed or lost'
   Write-PestoHeadlessEvents $script:PestoQueueMonitor
   Assert ($script:PestoAuditWriter.Flush(1500))
   Assert (@([IO.File]::ReadAllLines($script:AuditFile)|Where-Object{$_ -like 'PESTO_EVENT *'}).Count -eq 12) 'Events duplicated'
  }finally{Close-PestoHeadlessAudit}
 }
 Case 'Both real operation and join routes opt into streaming' {
  Assert ($defs['Invoke-PestoUnattendedOperation'].Contains('Enable-PestoHeadlessEventStream $monitor'))
  Assert ($defs['Invoke-PestoUnattendedJoin'].Contains('if($Execute -and $script:PestoAuditWriter){Enable-PestoHeadlessEventStream $monitor}'))
  Assert ($defs['Publish-PestoWorkerLog'] -notmatch 'New-PestoStructuredEvent|Write-PestoAuditQueued|Write-PestoStructuredEvent') 'No new GUI worker dependencies'
 }
}finally{$script:PestoQueueMonitor=$null;if($script:PestoAuditWriter){Close-PestoHeadlessAudit};if([IO.Directory]::Exists($temp)){[IO.Directory]::Delete($temp,$true)}}
$report=[pscustomobject]@{Suite='HeadlessAudit';PowerShell=$PSVersionTable.PSVersion.ToString();NoAD=$true;NoVM=$true;RealLocalWriter=$true;Failed=@($results|Where-Object{-not $_.Passed}).Count;Checks=$results.ToArray()}
if($ReportPath){$report|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $ReportPath -Encoding UTF8};$report|ConvertTo-Json -Depth 5;if($report.Failed){exit 1}
