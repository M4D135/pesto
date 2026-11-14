#requires -Version 5.1
param([string]$ReportPath='')
$ErrorActionPreference='Stop';Set-StrictMode -Off
$root=Split-Path $PSScriptRoot -Parent;$defs=@{};$results=[Collections.Generic.List[object]]::new()
foreach($file in @('Pesto-Journal.ps1','Pesto-Policy.ps1','Pesto-Core.ps1','Pesto-Operations.ps1','Pesto-Contracts.ps1','Pesto-Safety.ps1','Pesto-Interventions.ps1','Pesto-Workspace.ps1','Pesto-Catalogue.ps1','Pesto-EngineContracts.ps1','Pesto-Directory.ps1')){
 $t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root ('wad/'+$file)),[ref]$t,[ref]$e);if($e.Count){throw ($e.Message -join '; ')}
 foreach($n in $ast.EndBlock.Statements){if($n -is [Management.Automation.Language.FunctionDefinitionAst]){$defs[$n.Name]=$n.Extent.Text}}
}
foreach($name in @('Protect-PestoLogText','New-PestoReadCoordinator','New-PestoInterventionCatalogCache','Test-PestoOptionalPostCheckReceipt','Test-PestoAcknowledgedReceipt','Get-PestoAcknowledgementText','Assert-PestoAcknowledgement','Assert-PestoObservationSnapshot','Assert-PestoClosedObject','Assert-PestoPlainPath','Test-PestoDnsName','Test-PestoComputerName','Get-PestoStatePresentation','Get-PestoEffectLabel','Get-PestoStageLabel','Get-PestoNativeGuidance','Read-PestoIntervention','Get-PestoInterventions','Get-PestoInterventionCatalogue','ConvertTo-PestoInterventionRow','Get-PestoInterventionQuery','Export-PestoInterventionRows','Write-PestoAtomicText','Get-PestoOperationReport','Format-OUPath','Split-PestoDistinguishedName')){if(-not $defs.ContainsKey($name)){throw ('Missing production function: '+$name)};. ([scriptblock]::Create($defs[$name]))}
. (Join-Path $root 'wad/Pesto-Common.ps1');Initialize-PestoCommon (Join-Path $root 'wad')
function Assert {param($Value,[string]$Message='Assertion failed');if(-not $Value){throw $Message}}
function Case {param([string]$Name,[scriptblock]$Body);try{& $Body;$results.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''})}catch{$results.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message})}}
$script:LedgerTestRoot=Join-Path $PSScriptRoot ('.pesto-ledger-'+[Guid]::NewGuid().ToString('N'))
function Get-PestoInterventionRoot {return $script:LedgerTestRoot}
function New-Receipt {param([string]$Phase='Verified',[int]$Code=30)
 [pscustomobject]@{Schema=1;OperationId=[Guid]::NewGuid().ToString('N');Plan=[pscustomobject]@{Nom_du_PC='PC-001';Nouveau_Nom='P123456PAINF001';Domain='lab.test';Renommer=$true;Deplacer=$false};Phase=$Phase;Entra='NotRequested';Protection='NotChanged';Rename='Confirmed';Move='NotRequested';ResultCode=$Code;UpdatedUtc='2026-10-12T10:00:00Z';LastStage='Rename: Confirmed'}
}
try{
 Case 'Absent directory returns empty catalogue' {$c=Get-PestoInterventionCatalogue;Assert ($c.Entries.Count -eq 0 -and -not $c.Truncated)}
 [void][IO.Directory]::CreateDirectory($script:LedgerTestRoot)
 $good=New-Receipt;$goodPath=Join-Path $script:LedgerTestRoot ($good.OperationId+'.json');$good|ConvertTo-Json -Depth 5|Set-Content $goodPath -Encoding UTF8
 [IO.File]::WriteAllText((Join-Path $script:LedgerTestRoot 'broken.json'),'{broken')
 Case 'Unreadable receipt isolated; readable receipt retained' {[void](Read-PestoIntervention $goodPath);$c=Get-PestoInterventionCatalogue;Assert ($c.ValidCount -eq 1 -and $c.InvalidCount -eq 1 -and $c.Entries.Count -eq 2);Assert (@($c.Entries|Where-Object{-not $_.Readable})[0].Receipt -eq $null)}
 Case 'Strict mutation reader still refuses corrupted file' {$blocked=$false;try{@(Get-PestoInterventions)|Out-Null}catch{$blocked=$true};Assert $blocked}
 Case 'Invalid identity remains separate with no receipt' {$row=ConvertTo-PestoInterventionRow ([pscustomobject]@{Id='invalid:broken';Readable=$false;FileName='broken.json';Issue='Support'});Assert (-not $row.Readable -and $null -eq $row.Receipt -and $row.StatusCode -eq 'Unreadable')}
 Case 'Completed command remains in follow-up filter without being certified' {$receipt=New-Receipt -Phase PendingRestart -Code 20;$before=$receipt|ConvertTo-Json -Depth 8;$row=ConvertTo-PestoInterventionRow ([pscustomobject]@{Id=$receipt.OperationId;Readable=$true;Receipt=$receipt});Assert ($row.OptionalPostCheck -and $row.Unresolved -and $row.StatusCode -eq 'PendingRestart');Assert ($row.StatusLabel -match 'facultatif');Assert ((Get-PestoInterventionQuery @($row) -State Unresolved).MatchedCount -eq 1);Assert (($receipt|ConvertTo-Json -Depth 8) -ceq $before)}
 Case 'Uncertain and partial results never become optional follow-up' {foreach($phase in @('Uncertain','Partial','Running')){$receipt=New-Receipt -Phase $phase -Code 97;$row=ConvertTo-PestoInterventionRow ([pscustomobject]@{Id=$receipt.OperationId;Readable=$true;Receipt=$receipt});Assert (-not $row.OptionalPostCheck -and $row.Unresolved)}}
 Case 'Acknowledged uncertain receipt is resolved but never a success' {
  $ackReceipt=New-Receipt -Phase Uncertain -Code 97
  $ackReceipt|Add-Member NoteProperty Acknowledged ([pscustomobject]@{Schema=1;Utc='2026-10-15T12:00:00.0000000Z';By='LABO\tech.pesto';Reason='Poste relu, rien appliqué';Phase='Uncertain';ResultCode=97;Observation=$null})
  $ackRow=ConvertTo-PestoInterventionRow ([pscustomobject]@{Id=$ackReceipt.OperationId;Readable=$true;Receipt=$ackReceipt})
  Assert ($null -ne $ackRow) 'Ligne acquittée attendue.'
  Assert ($ackRow.PSObject.Properties['Unresolved'] -and ($ackRow.Unresolved -is [bool]) -and ($ackRow.Unresolved -eq $false) -and ($ackRow.PSObject.Properties['Acknowledged']) -and ($ackRow.Acknowledged -is [bool]) -and ($ackRow.Acknowledged -eq $true)) 'Reçu acquitté doit être résolu et marqué acquitté.'
  Assert ($ackRow.StatusLabel -match 'acquittée' -and $ackRow.StatusLabel -match 'incertain') ('Libellé attendu : '+$ackRow.StatusLabel)
  Assert ($ackRow.NextAction -match 'jamais compté comme réussi') ('Action attendue : '+$ackRow.NextAction)
  $plainReceipt=New-Receipt -Phase Uncertain -Code 97
  $plainRow=ConvertTo-PestoInterventionRow ([pscustomobject]@{Id=$plainReceipt.OperationId;Readable=$true;Receipt=$plainReceipt})
  Assert ($null -ne $plainRow) 'Ligne non acquittée attendue.'
  Assert ($plainRow.PSObject.Properties['Unresolved'] -and ($plainRow.Unresolved -is [bool]) -and ($plainRow.Unresolved -eq $true) -and ($plainRow.PSObject.Properties['Acknowledged']) -and ($plainRow.Acknowledged -is [bool]) -and ($plainRow.Acknowledged -eq $false)) 'Reçu incertain sans acquittement doit rester non résolu.'
 }
 Case 'Inconsistent PendingRestart never promises optional verification' {foreach($effect in @('Requested','Refused','Uncertain')){$receipt=New-Receipt -Phase PendingRestart -Code 20;$receipt.Rename=$effect;$row=ConvertTo-PestoInterventionRow ([pscustomobject]@{Id=$receipt.OperationId;Readable=$true;Receipt=$receipt});Assert (-not $row.OptionalPostCheck -and $row.Unresolved);Assert ($row.StatusLabel -notmatch 'facultatif' -and $row.NextAction -notmatch 'facultatif')}}
 Case 'UTC converted to local with offset and localized state' {$row=ConvertTo-PestoInterventionRow ([pscustomobject]@{Id=$good.OperationId;Readable=$true;Receipt=$good});Assert ($row.UpdatedLocal -match '^12/10/2026 .+ [+-]\d{2}:\d{2}$');Assert ($row.StatusLabel -match 'vérifié');Assert ($row.StageLabel -eq 'Renommage : Confirmé')}
 Case 'Unknown date does not become now' {$bad=New-Receipt;$bad.UpdatedUtc='12/10/2026';$row=ConvertTo-PestoInterventionRow ([pscustomobject]@{Id=$bad.OperationId;Readable=$true;Receipt=$bad});Assert ($null -eq $row.UpdatedUtc -and $row.UpdatedLocal -eq 'Date inconnue')}
 $rows=@(for($i=0;$i -lt 451;$i++){$receipt=New-Receipt;$receipt.Plan.Nom_du_PC='PC-'+$i.ToString('D3');$receipt.UpdatedUtc=([DateTimeOffset]::Parse('2026-10-12T10:00:00Z')).AddMinutes($i).ToString('o');if($i%2){$receipt.Phase='Uncertain'};ConvertTo-PestoInterventionRow ([pscustomobject]@{Id=$receipt.OperationId;Readable=$true;Receipt=$receipt})})
 Case 'Common Query pages and counts full snapshot' {$q=Get-PestoInterventionQuery $rows;Assert ($q.TotalCount -eq 451 -and $q.MatchedCount -eq 451 -and $q.Items.Count -eq 200);Assert ($q.Items[0].Computer -eq 'PC-450')}
 Case 'Filter and search use AND; literal search cannot inject pattern' {$q=Get-PestoInterventionQuery $rows -Search 'PC-00' -State Unresolved;Assert ($q.MatchedCount -eq 5);Assert ((Get-PestoInterventionQuery $rows -Search '*').MatchedCount -eq 0)}
 Case 'Full filtered export includes rows beyond displayed page' {$q=Get-PestoInterventionQuery $rows -State Verified -PageSize 5000;$csv=Join-Path $script:LedgerTestRoot 'export.csv';Export-PestoInterventionRows $csv $q.Items;Assert (@(Import-Csv $csv -Delimiter ';').Count -eq 226);$b=[IO.File]::ReadAllBytes($csv);Assert ($b[0] -eq 239 -and $b[1] -eq 187 -and $b[2] -eq 191)}
 Case 'CSV neutralizes spreadsheet formulas and omits raw receipt' {$r=$rows[0].PSObject.Copy();$r.Computer=' =1+1';$csv=Join-Path $script:LedgerTestRoot 'safe.csv';Export-PestoInterventionRows $csv @($r);$v=Import-Csv $csv -Delimiter ';';Assert ($v.Poste.StartsWith("'"));Assert (-not $v.PSObject.Properties['Receipt'])}
 Case 'Offset resets to last valid page after filter' {$q=Get-PestoInterventionQuery $rows -Offset 400 -State Unresolved;Assert ($q.Offset -eq 200 -and $q.Items.Count -eq 25)}
 Case 'Duplicate row identity rejected' {$blocked=$false;try{Get-PestoInterventionQuery @($rows[0],$rows[0])|Out-Null}catch{$blocked=$true};Assert $blocked}
 Case 'Every business outcome has explicit label and next action' {foreach($state in @('NotStarted','Failed','Refused','Running','PendingRestart','Partial','MoveReady','Uncertain','Verified','Unreadable')){$p=Get-PestoStatePresentation $state;Assert ($p.Label -and $p.Action -and $p.Severity)}}
 Case 'Non-started code cannot appear as mutation refusal' {Assert ((Get-PestoStatePresentation Failed 96).Label -match 'Non lancé')}
 Case 'Masked report hides identity; unmasked choice restores it explicitly' {$masked=Get-PestoOperationReport $good;$open=Get-PestoOperationReport $good -Redact $false;Assert ($masked -notmatch 'PC-001|lab.test|P123456');Assert ($open -match 'PC-001' -and $open -match 'lab.test')}
 Case 'Report shows readable OU path and hides every DN component when masked' {
   $r=New-Receipt;$r.Plan|Add-Member NoteProperty OU_Actuelle 'OU=Transit,OU=Sites,DC=x,DC=y';$r.Plan|Add-Member NoteProperty OU_Destination 'OU=Postes,OU=Lyon,OU=Sites,DC=x,DC=y';$r.Plan|Add-Member NoteProperty DC 'dc01.x.y'
   $open=Get-PestoOperationReport $r -Redact $false;$masked=Get-PestoOperationReport $r
   Assert ($open -match 'OU : Sites › Transit → Sites › Lyon › Postes') $open
   Assert ($masked -match 'OU : \[MASQUÉ\]' -and $masked -notmatch 'OU=|DC=|dc01|Lyon|Transit') $masked
   $none=New-Receipt;Assert ((Get-PestoOperationReport $none -Redact $false) -match 'OU : Non défini → Non défini')
 }
 Case 'Report dates: damaged values become Inconnue, start comes from the receipt, never N/A' {
   $r=New-Receipt;$r|Add-Member NoteProperty StartedUtc '2026-10-12T08:00:00Z';$r|Add-Member NoteProperty VerifiedBy 'tech';$r|Add-Member NoteProperty VerifiedUtc 'pas une date'
   $r|Add-Member NoteProperty Timeline @([pscustomobject]@{Sequence=40;Utc='hier';Stage='Rename';State='Confirmed'},[pscustomobject]@{Sequence=41;Utc='2026-10-12T09:30:00Z';Stage='Result';State='Confirmed'})
   foreach($redact in @($true,$false)){
     $text=Get-PestoOperationReport $r -Redact $redact
     Assert ($text -match '(?m)^Inconnue \| ') $text
     Assert ($text -notmatch 'N/A') $text
     $start=[DateTime]::Parse('2026-10-12T08:00:00Z',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind).ToLocalTime().ToString('dd/MM/yyyy HH:mm')
     Assert ($text -match ('(?m)^Début : '+[regex]::Escape($start)+'\s*$')) $text
   }
   Assert ((Get-PestoOperationReport $r -Redact $false) -match 'Vérificateur : tech \(Inconnue\)')
   $empty=New-Receipt;$empty.UpdatedUtc=$null;$text=Get-PestoOperationReport $empty -Redact $false;Assert ($text -match '(?m)^Début : Inconnue' -and $text -match '(?m)^Fin : Inconnue') $text
 }
 Case 'Catalogue reparse guard rejects symbolic linked root without touching the target' {
   $base=$script:LedgerTestRoot;$target=Join-Path $base 'target';$link=Join-Path $base 'link'
   [void][IO.Directory]::CreateDirectory($target);[IO.File]::WriteAllText((Join-Path $target 'keep.txt'),'fixture')
   try{
    New-Item -ItemType SymbolicLink -Path $link -Target $target | Out-Null
    $script:LedgerTestRoot=$link;$blocked=$false;try{Get-PestoInterventionCatalogue|Out-Null}catch{$blocked=$true};Assert $blocked
   }finally{
    $script:LedgerTestRoot=$base
    # Directory.Delete removes only the link on Windows; Remove-Item on a
    # populated directory link can prompt in Windows PowerShell 5.1.
    if(Test-Path -LiteralPath $link){[IO.Directory]::Delete($link)}
   }
   Assert ([IO.File]::ReadAllText((Join-Path $target 'keep.txt')) -eq 'fixture')
 }
}finally{if(Test-Path -LiteralPath $script:LedgerTestRoot){Remove-Item -LiteralPath $script:LedgerTestRoot -Recurse -Force}}
# Exercise the asynchronous presentation contract with local data doubles only.
foreach($name in @('Update-PestoInterventions','Fail-PestoInterventionRead')){. ([scriptblock]::Create($defs[$name]))}
function Update-PestoInterventionActions {}
function Update-PestoInterventionPage {$script:PageRefreshed=$true}
function Get-PestoWorkerCoreSource {if($script:LedgerSourceThrows){throw 'Source worker indisponible'};return ''}
function Start-PestoAsyncOperation {param($Name,$ScriptBlock,$ArgumentList,$TimeoutSec,$CallbackContext,$OnSuccess,$OnError);return $false}
function Protect-PestoLogText {param($Text);return $Text}
Case 'Refused asynchronous start releases loading state and allows retry' {
 $controls=@{};foreach($name in @('LedgerRefresh','LedgerExport','LedgerPrevious','LedgerNext')){$controls[$name]=[pscustomobject]@{IsEnabled=$true}}
 $window=[pscustomobject]@{Controls=$controls};$window|Add-Member ScriptMethod FindName {param($Name);return $this.Controls[$Name]}
 $script:InterventionsUi=[pscustomobject]@{Window=$window;Loading=$false;Hint=[pscustomobject]@{Text=''};Rows=@();Catalogue=$null};$script:PageRefreshed=$false
 Update-PestoInterventions
 Assert (-not $script:InterventionsUi.Loading -and $controls.LedgerRefresh.IsEnabled -and $script:PageRefreshed)
 Assert ($script:InterventionsUi.Hint.Text -match 'Réessayez' -and -not $controls.LedgerExport.IsEnabled)
 $script:InterventionsUi=$null
}
Case 'Worker source failure restores refresh and leaves receipts unknown' {
 $controls=@{};foreach($name in @('LedgerRefresh','LedgerExport','LedgerPrevious','LedgerNext')){$controls[$name]=[pscustomobject]@{IsEnabled=$true}}
 $window=[pscustomobject]@{Controls=$controls};$window|Add-Member ScriptMethod FindName {param($Name);return $this.Controls[$Name]}
 $script:InterventionsUi=[pscustomobject]@{Window=$window;Loading=$false;Hint=[pscustomobject]@{Text=''};Rows=@();Catalogue=$null};$script:PageRefreshed=$false;$script:LedgerSourceThrows=$true
 try{Update-PestoInterventions;Assert (-not $script:InterventionsUi.Loading -and $controls.LedgerRefresh.IsEnabled -and $script:PageRefreshed);Assert ($null -eq $script:InterventionsUi.Catalogue -and $script:InterventionsUi.Hint.Text -match 'impossible')}
 finally{$script:LedgerSourceThrows=$false;$script:InterventionsUi=$null}
}
$failed=@($results|Where-Object{-not $_.Passed}).Count
$report=[pscustomobject]@{PowerShell=[string]$PSVersionTable.PSVersion;NoWindows=$true;NoAD=$true;Failed=$failed;Checks=$results.ToArray()}
if($ReportPath){$report|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $ReportPath -Encoding UTF8};$report|ConvertTo-Json -Depth 6;if($failed){exit 1}
