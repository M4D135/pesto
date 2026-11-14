#requires -Version 5.1
param([string]$ReportPath='')
$ErrorActionPreference='Stop';Set-StrictMode -Off
$root=Split-Path $PSScriptRoot -Parent;$defs=@{};$results=[Collections.Generic.List[object]]::new()
foreach($file in @('Pesto-Journal.ps1','Pesto-ReceiptTools.ps1','Pesto-Safety.ps1','Pesto-Contracts.ps1','Pesto-Core.ps1','Pesto-Operations.ps1','Pesto-Workspace.ps1','Pesto-Interventions.ps1','Pesto-Policy.ps1','Pesto-Directory.ps1')){$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root ('wad/'+$file)),[ref]$t,[ref]$e);if($e.Count){throw ($file+': '+($e.Message -join '; '))};foreach($f in $ast.EndBlock.Statements){if($f -is [Management.Automation.Language.FunctionDefinitionAst]){$defs[$f.Name]=$f.Extent.Text}}}
foreach($name in @('Protect-PestoLogText','Get-PestoReceiptIdentity','Get-PestoReceiptTimeline','Test-PestoReceiptArchivable','Move-PestoReceiptToArchive','Get-PestoReconciliationAudit','Get-PestoOperationSupport','Export-PestoOperationSupport','Write-PestoNewExport','Read-PestoIntervention','Test-PestoAcknowledgedReceipt','Assert-PestoPlainPath','Assert-PestoClosedObject','Test-PestoComputerName','Test-PestoDnsName','Get-PestoOperationReport','Get-PestoStatePresentation','Get-PestoEffectLabel','Get-PestoStageLabel','Get-PestoNativeGuidance','Compare-PestoInterventions','Merge-PestoTimelineRows','Get-PestoReceiptTimelineOtherRoot','Get-PestoInterventionCatalogue','ConvertTo-PestoInterventionRow','Test-PestoOptionalPostCheckReceipt','Format-OUPath','Split-PestoDistinguishedName')){. ([scriptblock]::Create($defs[$name]))}
function Assert {param($Value,[string]$Message='Assertion failed');if(-not$Value){throw $Message}}
function Case {param($Name,[scriptblock]$Test);try{&$Test;$results.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''})}catch{$results.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message})}}
function Reject {param([scriptblock]$Test);$caught=$false;try{&$Test|Out-Null}catch{$caught=$true};Assert $caught}
function New-Receipt {param([string]$Phase='Verified');[pscustomobject]@{Schema=1;OperationId=[Guid]::NewGuid().ToString('N');Phase=$Phase;Plan=[pscustomobject]@{Nom_du_PC='PC-OLD';Nouveau_Nom='PC-NEW';Domain='private.test';Renommer=$true;Deplacer=$false;Reference='ticket-private'};Protection='NotChanged';Rename='Confirmed';Move='NotRequested';Entra='NotRequested';ResultCode=20;UpdatedUtc='2026-10-13T08:00:00Z'}}
Case 'Identities never merge receipts by name only' {$a=New-Receipt;$b=New-Receipt;Assert ((Get-PestoReceiptIdentity $a) -cne (Get-PestoReceiptIdentity $b))}
Case 'AD object identity survives renaming' {$a=New-Receipt;$b=New-Receipt;$id=[Guid]::NewGuid().ToString();$a.Plan|Add-Member NoteProperty Objet_GUID $id;$b.Plan|Add-Member NoteProperty Objet_GUID $id;$b.Plan.Nom_du_PC='AFTER';Assert ((Get-PestoReceiptIdentity $a) -ceq (Get-PestoReceiptIdentity $b))}
Case 'Invalid GUID falls back to intervention identity' {$a=New-Receipt;$a.Plan|Add-Member NoteProperty Objet_GUID 'bad';Assert ((Get-PestoReceiptIdentity $a).StartsWith('Operation:'))}
Case 'Every active or unresolved phase refuses archive' {foreach($p in @('Running','PendingRestart','Partial','MoveReady','Uncertain')){Assert (-not(Test-PestoReceiptArchivable (New-Receipt $p)))}}
Case 'Terminal phase cannot hide uncertain effects or lowered protection' {$r=New-Receipt;$r.Protection='Lowered';Assert (-not(Test-PestoReceiptArchivable $r));$r.Protection='Restored';$r.Entra='Uncertain';Assert (-not(Test-PestoReceiptArchivable $r))}
Case 'Unfinished tasks refuse archive' {$r=New-Receipt;$r|Add-Member NoteProperty Tasks @([pscustomobject]@{Phase='Started'});Assert (-not(Test-PestoReceiptArchivable $r))}
Case 'Masked support excludes private names reference and raw result text' {$r=New-Receipt;$r|Add-Member NoteProperty ResultMessage 'secret exception';$json=Get-PestoOperationSupport $r|ConvertTo-Json -Depth 8;Assert ($json -notmatch 'PC-OLD|PC-NEW|private.test|ticket-private|secret exception')}
Case 'Unmasked support retains identity and omits legacy reference' {$r=New-Receipt;$data=Get-PestoOperationSupport $r -Redact $false;Assert ($data.Computer -ceq 'PC-OLD' -and $null -eq $data.PSObject.Properties['Reference'])}
$tmp=Join-Path $PSScriptRoot ('.receipt120-'+[Guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($tmp);$script:TestRoot=$tmp
function Get-PestoInterventionRoot {$script:TestRoot}
try{
 Case 'New export publishes exact UTF8 bytes and leaves no temporary file' {
  $path=Join-Path $tmp 'unicode-export.json';$text='{"texte":"Été ☕"}'
  Write-PestoNewExport -Path $path -Text $text
  Assert ([IO.File]::ReadAllText($path,[Text.Encoding]::UTF8) -ceq $text)
  Assert (@(Get-ChildItem $tmp -Filter '.pesto-export-*.tmp' -Force).Count -eq 0)
 }
 Case 'New export never overwrites an existing destination' {
  $path=Join-Path $tmp 'existing.txt';[IO.File]::WriteAllText($path,'original')
  Reject {Write-PestoNewExport -Path $path -Text 'replacement'}
  Assert ([IO.File]::ReadAllText($path) -ceq 'original')
 }
 Case 'Oversized export refuses before publishing or creating a temporary file' {
  $path=Join-Path $tmp 'too-big.txt'
  Reject {Write-PestoNewExport -Path $path -Text ('é'*524289)}
  Assert (-not [IO.File]::Exists($path));Assert (@(Get-ChildItem $tmp -Filter '.pesto-export-*.tmp' -Force).Count -eq 0)
 }
 Case 'Concurrent destination wins and failed publication removes its temporary file' {
  $path=Join-Path $tmp 'concurrent.txt';$script:ExportPathChecks=0
  $script:OriginalPathCheck=[scriptblock]::Create($defs['Assert-PestoPlainPath'])
  # Inject a concurrent file creation at the last path check; all IO is real.
  function Assert-PestoPlainPath {param([string]$Path)
   $script:ExportPathChecks++
   if($script:ExportPathChecks -eq 2){[IO.File]::WriteAllText($Path,'concurrent writer')}
  }
  try{Reject {Write-PestoNewExport -Path $path -Text 'replacement'};Assert ([IO.File]::ReadAllText($path) -ceq 'concurrent writer');Assert (@(Get-ChildItem $tmp -Filter '.pesto-export-*.tmp' -Force).Count -eq 0)}
  finally{. $script:OriginalPathCheck}
 }
 Case 'Archive preserves bytes hash and identity and creates provenance' {$r=New-Receipt;$p=Join-Path $tmp ($r.OperationId+'.json');Write-PestoNewExport $p ($r|ConvertTo-Json -Depth 8);$before=[Convert]::ToBase64String([IO.File]::ReadAllBytes($p));$moved=Move-PestoReceiptToArchive $r.OperationId;Assert (-not[IO.File]::Exists($p));Assert ($before -ceq [Convert]::ToBase64String([IO.File]::ReadAllBytes($moved.Path)));Assert ([IO.File]::Exists((Join-Path (Split-Path $moved.Path) ($r.OperationId+'.archive-info'))));Assert ($moved.Sha256 -ceq (Get-FileHash $moved.Path).Hash.ToLowerInvariant())}
 Case 'Matching orphan provenance resumes archive without rewriting provenance' {
  $r=New-Receipt;$p=Join-Path $tmp ($r.OperationId+'.json');Write-PestoNewExport $p ($r|ConvertTo-Json -Depth 8)
  $metaPath=Join-Path (Join-Path $tmp 'Archive') ($r.OperationId+'.archive-info')
  $meta=[pscustomobject]@{Schema=1;OperationId=$r.OperationId;ArchivedUtc='2026-10-13T08:00:00Z';Phase=$r.Phase;Sha256=(Get-FileHash $p).Hash.ToLowerInvariant()}
  Write-PestoNewExport $metaPath ($meta|ConvertTo-Json);$before=[IO.File]::ReadAllText($metaPath)
  $moved=Move-PestoReceiptToArchive $r.OperationId
  Assert ([IO.File]::Exists($moved.Path));Assert ([IO.File]::ReadAllText($metaPath) -ceq $before)
 }
 Case 'Conflicting orphan provenance is preserved along with the receipt' {
  $r=New-Receipt;$p=Join-Path $tmp ($r.OperationId+'.json');Write-PestoNewExport $p ($r|ConvertTo-Json -Depth 8)
  $metaPath=Join-Path (Join-Path $tmp 'Archive') ($r.OperationId+'.archive-info')
  Write-PestoNewExport $metaPath '{"Schema":1,"Sha256":"different"}'
  $before=[IO.File]::ReadAllText($metaPath);$hash=(Get-FileHash $p).Hash
  Reject {Move-PestoReceiptToArchive $r.OperationId}
  Assert ([IO.File]::ReadAllText($metaPath) -ceq $before);Assert ((Get-FileHash $p).Hash -ceq $hash)
 }
 Case 'Unresolved receipt remains byte identical at active path' {$r=New-Receipt 'PendingRestart';$p=Join-Path $tmp ($r.OperationId+'.json');Write-PestoNewExport $p ($r|ConvertTo-Json -Depth 8);$hash=(Get-FileHash $p).Hash;Reject{Move-PestoReceiptToArchive $r.OperationId};Assert ((Get-FileHash $p).Hash -ceq $hash)}
 Case 'Read-only context refuses archive before touching filesystem' {$script:PestoReadOnly=$true;try{Reject{Move-PestoReceiptToArchive ([Guid]::NewGuid().ToString())}}finally{$script:PestoReadOnly=$false}}
 Case 'Timeline joins active and archived receipts of the same machine' {
  $machine=[Guid]::NewGuid().ToString();$archiveRoot=Join-Path $tmp 'Archive';[void][IO.Directory]::CreateDirectory($archiveRoot)
  $old=New-Receipt;$old|Add-Member NoteProperty TargetMachineId $machine;$old.UpdatedUtc='2026-10-01T08:00:00Z';$old.Plan.Reference='T-ARCH'
  $new=New-Receipt;$new|Add-Member NoteProperty TargetMachineId $machine.ToUpperInvariant();$new.UpdatedUtc='2026-10-12T08:00:00Z';$new.Plan.Nom_du_PC='PC-NEW';$new.Plan.Nouveau_Nom='PC-NEXT'
  $stranger=New-Receipt;$stranger|Add-Member NoteProperty TargetMachineId ([Guid]::NewGuid().ToString())
  Write-PestoNewExport (Join-Path $archiveRoot ($old.OperationId+'.json')) ($old|ConvertTo-Json -Depth 8)
  Write-PestoNewExport (Join-Path $archiveRoot ($stranger.OperationId+'.json')) ($stranger|ConvertTo-Json -Depth 8)
  $activeRows=@(foreach($r in @($new,$stranger)){ConvertTo-PestoInterventionRow ([pscustomobject]@{Id=$r.OperationId;Readable=$true;Receipt=$r})})
  $t=@(Get-PestoReceiptTimeline $new $activeRows $false)
  Assert ($t.Count -eq 2) ('Lignes : '+$t.Count+' '+(($t|ForEach-Object{$_.Emplacement+':'+$_.Etat}) -join ' | '))
  $a=@($t|Where-Object{$_.OperationId -ceq $old.OperationId});$c=@($t|Where-Object{$_.OperationId -ceq $new.OperationId})
  Assert ($a.Count -eq 1 -and $a[0].Emplacement -ceq 'Archivé' -and $null -eq $a[0].PSObject.Properties['Reference'])
  Assert ($c.Count -eq 1 -and $c[0].Emplacement -ceq 'Actif' -and $c[0].Avant -ceq 'PC-NEW' -and $c[0].Apres -ceq 'PC-NEXT')
  # Vue des archives : les reçus actifs deviennent l'autre emplacement.
  $archivedRows=@(ConvertTo-PestoInterventionRow ([pscustomobject]@{Id=$old.OperationId;Readable=$true;Receipt=$old}))
  Write-PestoNewExport (Join-Path $tmp ($new.OperationId+'.json')) ($new|ConvertTo-Json -Depth 8)
  $v=@(Get-PestoReceiptTimeline $old $archivedRows $true)
  # PowerShell 7 convertit les dates JSON lues sur disque : l'ordre n'est vérifié qu'en mémoire (cas suivant).
  Assert ($v.Count -eq 2 -and @($v|Where-Object{$_.OperationId -ceq $old.OperationId -and $_.Emplacement -ceq 'Archivé'}).Count -eq 1 -and @($v|Where-Object{$_.OperationId -ceq $new.OperationId -and $_.Emplacement -ceq 'Actif'}).Count -eq 1)
  Remove-Item -LiteralPath (Join-Path $tmp ($new.OperationId+'.json')) -Force;Remove-Item -LiteralPath $archiveRoot -Recurse -Force
 }
 Case 'Timeline orders by UTC date, not by location' {
  $machine=[Guid]::NewGuid().ToString();$active=New-Receipt;$active|Add-Member NoteProperty TargetMachineId $machine;$active.UpdatedUtc='2026-10-02T08:00:00Z'
  $archived=New-Receipt;$archived|Add-Member NoteProperty TargetMachineId $machine;$archived.UpdatedUtc='2026-10-09T08:00:00Z'
  $rows=@(ConvertTo-PestoInterventionRow ([pscustomobject]@{Id=$active.OperationId;Readable=$true;Receipt=$active}))
  $catalogue=[pscustomobject]@{Entries=@([pscustomobject]@{Id=$archived.OperationId;Readable=$true;Receipt=$archived},[pscustomobject]@{Id='invalid:x.json';Readable=$false;Receipt=$null});Truncated=$false}
  $t=@(Get-PestoReceiptTimeline -Receipt $active -Rows $rows -OtherCatalogue $catalogue)
  Assert ($t.Count -eq 2 -and $t[0].Emplacement -ceq 'Actif' -and $t[1].Emplacement -ceq 'Archivé' -and $t[1].OperationId -ceq $archived.OperationId)
  Assert ($t[0].Date -match '^02/10/2026' -and $t[1].Date -match '^09/10/2026')
 }
 Case 'Timeline without archive folder keeps active rows and adds no note' {$r=New-Receipt;$rows=@(ConvertTo-PestoInterventionRow ([pscustomobject]@{Id=$r.OperationId;Readable=$true;Receipt=$r}));$t=@(Get-PestoReceiptTimeline $r $rows);Assert ($t.Count -eq 1 -and $t[0].Emplacement -ceq 'Actif' -and $t[0].OperationId -ceq $r.OperationId)}
 Case 'Unreadable other location is reported without hiding current rows' {$r=New-Receipt;$rows=@(ConvertTo-PestoInterventionRow ([pscustomobject]@{Id=$r.OperationId;Readable=$true;Receipt=$r}));$t=@(Get-PestoReceiptTimeline -Receipt $r -Rows $rows -OtherError 'délai dépassé');Assert ($t.Count -eq 2 -and $t[0].Emplacement -ceq 'Actif' -and $t[1].Emplacement -ceq 'Info' -and $t[1].Etat -match '^Archives non lues : délai dépassé')}
 Case 'Same receipt read in both locations is listed once' {$r=New-Receipt;$row=ConvertTo-PestoInterventionRow ([pscustomobject]@{Id=$r.OperationId;Readable=$true;Receipt=$r});$catalogue=[pscustomobject]@{Entries=@([pscustomobject]@{Id=$r.OperationId;Readable=$true;Receipt=$r});Truncated=$false};$t=@(Get-PestoReceiptTimeline -Receipt $r -Rows @($row) -OtherCatalogue $catalogue);Assert ($t.Count -eq 1 -and $t[0].Emplacement -ceq 'Actif')}
 Case 'Support export publishes three files with matching hashes' {$dest=Join-Path $tmp 'case.support';$r=New-Receipt;$data=Get-PestoOperationSupport $r;Export-PestoOperationSupport $dest $data '{"redacted":true}';$m=Get-Content (Join-Path $dest 'manifest.json') -Raw|ConvertFrom-Json;Assert (@($m.Files).Count -eq 2 -and $m.Redacted);foreach($f in $m.Files){Assert ((Get-FileHash (Join-Path $dest $f.Name)).Hash.ToLowerInvariant() -ceq $f.SHA256)};Reject{Export-PestoOperationSupport $dest $data '{}'}}
}finally{Remove-Item -LiteralPath $tmp -Recurse -Force}
foreach($name in @('Show-PestoReceiptTimeline','Complete-PestoReceiptTimelineRead','Fail-PestoReceiptTimelineRead')){. ([scriptblock]::Create($defs[$name]))}
function Show-PestoChoiceTable {param($Title,$Description,$Rows,$Columns);$script:TimelineShown.Add(@($Rows))}
function Show-MsgWarning {param($Text);throw $Text}
function Protect-PestoLogText {param($Text);$Text}
Case 'Asynchronous timeline shows once, with archive rows or the read failure' {
 $script:TimelineShown=[Collections.Generic.List[object]]::new();$ui=[pscustomobject]@{Name='ledger'};$script:InterventionsUi=$ui
 $r=New-Receipt
 $arch=New-Receipt;$arch.OperationId=[Guid]::NewGuid().ToString('N');$arch.Plan|Add-Member NoteProperty Objet_GUID ([Guid]::NewGuid().ToString());$r.Plan|Add-Member NoteProperty Objet_GUID $arch.Plan.Objet_GUID
 $row=ConvertTo-PestoInterventionRow ([pscustomobject]@{Id=$r.OperationId;Readable=$true;Receipt=$r})
 $ctx=[pscustomobject]@{Ui=$ui;Receipt=$r;Rows=@($row);ShowingArchive=$false;Shown=$false}
 Complete-PestoReceiptTimelineRead ([pscustomobject]@{Entries=@([pscustomobject]@{Id=$arch.OperationId;Readable=$true;Receipt=$arch});Truncated=$false}) $ctx
 Fail-PestoReceiptTimelineRead 'second appel' $ctx
 Assert ($script:TimelineShown.Count -eq 1 -and @($script:TimelineShown[0]).Count -eq 2 -and @($script:TimelineShown[0]|Where-Object{$_.Emplacement -ceq 'Archivé'}).Count -eq 1)
 $ctx2=[pscustomobject]@{Ui=$ui;Receipt=$r;Rows=@($row);ShowingArchive=$true;Shown=$false};Fail-PestoReceiptTimelineRead 'délai dépassé' $ctx2
 Assert ($script:TimelineShown.Count -eq 2 -and @($script:TimelineShown[1])[-1].Etat -ceq 'Reçus actifs non lus : délai dépassé')
 $stale=[pscustomobject]@{Ui=[pscustomobject]@{Name='closed'};Receipt=$r;Rows=@($row);ShowingArchive=$false;Shown=$false};Fail-PestoReceiptTimelineRead 'x' $stale
 Assert ($script:TimelineShown.Count -eq 2)
 $script:InterventionsUi=$null
}
Case 'Archive uses same mutation mutex as real commands and never writes receipt status' {$s=$defs['Move-PestoReceiptToArchive'];Assert ($s.Contains('Global\GP_PostMutation_v1') -and $s.Contains('Read-PestoIntervention $source') -and $s -notmatch '\.Phase\s*=')}
Case 'Comparison explicitly requires two receipts instead of hidden first-click state' {$s=$defs['Invoke-PestoReceiptTool'];Assert ($s.Contains('-Multiple') -and $s.Contains('$r.Items.Count -ne 2'))}
$failed=@($results|Where-Object{-not $_.Passed});$report=[pscustomobject]@{Suite='ReceiptTools120';Passed=$results.Count-$failed.Count;Failed=$failed.Count;Cases=$results};if($ReportPath){[IO.File]::WriteAllText($ReportPath,($report|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))};$failed|%{Write-Output ($_.Name+': '+$_.Error)};Write-Output ("ReceiptTools120 : {0}/{1} PASS" -f $report.Passed,$results.Count);if($failed.Count){exit 1}
