#requires -Version 5.1
param([string]$ReportPath='',[switch]$Wpf)
$ErrorActionPreference='Stop';Set-StrictMode -Off
$root=Split-Path $PSScriptRoot -Parent;$defs=@{};$results=[Collections.Generic.List[object]]::new()
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'wad/Pesto-Contracts.ps1')
foreach($file in @('Pesto-BatchTools.ps1','Pesto-Core.ps1','Pesto-Contracts.ps1','Pesto-Operations.ps1','Pesto-Policy.ps1','Pesto-NameWorkbench.ps1','Pesto-Directory.ps1','Pesto-Review.ps1')){$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root ('wad/'+$file)),[ref]$t,[ref]$e);if($e.Count){throw ($file+': '+($e.Message -join '; '))};foreach($f in $ast.EndBlock.Statements){if($f -is [Management.Automation.Language.FunctionDefinitionAst]){$defs[$f.Name]=$f.Extent.Text}}}
foreach($name in @('Read-PestoImportFile','ConvertFrom-PestoTabularText','New-PestoCsvQueueCandidate','Get-PestoRenameMoveDecision','Get-PestoNameSiteCode','Get-PestoSiteContainerDN','Split-PestoDistinguishedName','Get-PestoDomainFromDN','Test-PestoDnsName','New-PestoImportEditor','Test-PestoImportEditor','New-QueueTable','Convert-Value-TF','Test-QueueRowSafe','Test-PestoComputerName','Test-PestoGeneratedComputerName','ConvertTo-PestoNameParts','Test-PestoOUPath','Get-PestoRowPlanText','Get-PestoQueueContentStamp','Get-PestoStableHash','ConvertTo-PestoCanonicalValue','Get-PestoCapacityThresholdRows','Get-PestoNameExclusionDetails','Get-PestoHardwareSuggestion','Save-PestoQueueUndo','Undo-PestoQueuePreparation','Publish-PestoPreparedQueue','Reset-PestoRowPreflight','Restore-PestoEditedQueueOrder')){. ([scriptblock]::Create($defs[$name]))}
function Assert {param($Value,[string]$Message='Assertion failed');if(-not$Value){throw $Message}}
function Case {param($Name,[scriptblock]$Test);try{&$Test;$results.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''})}catch{$results.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message})}}
function Reject {param([scriptblock]$Test);$caught=$false;try{&$Test|Out-Null}catch{$caught=$true};Assert $caught}
$script:INDOMAIN=$true
function Test-PestoOUInConfiguredScope {param($OU);return $OU -eq 'OU=Lab,DC=lab,DC=test'}
function Test-PestoGlobalSafetyBarrier {$false}
function Get-PestoConfigurationSignature {param($Config);'fixed-config'}
function Save-PestoQueueCheckpoint {if($script:FailSave){throw 'Fixture storage error'}}
function Update-PestoQueueFilter {}
function Sync-Grid {}
function Update-QueueButtons {}
function Add-LogLine {param($Text,$Level)}
Case 'CSV quoted delimiters and escaped quotes preserve cells' {$r=ConvertFrom-PestoTabularText "name;note`r`nPC1;`"a;b `"`"quoted`"`"`"";Assert ($r.Rows.Count -eq 1 -and $r.Rows[0].Cells[1] -ceq 'a;b "quoted"')}
Case 'Excel tabs and Unicode survive without executing formulas' {$r=ConvertFrom-PestoTabularText "Poste`tLibellé`nPC1`t=1+1";Assert ($r.Delimiter -eq "`t" -and $r.Rows[0].Cells[1] -ceq '=1+1')}
Case 'Duplicate headers rejected case-insensitively' {Reject{ConvertFrom-PestoTabularText "Name;name`n1;2"}}
Case 'Broken quoting and row width are rejected' {Reject{ConvertFrom-PestoTabularText "A;B`n1"};Reject{ConvertFrom-PestoTabularText "A;B`n1;`"bad"}}
Case 'Multiline quoted cells remain data until field validation' {$r=ConvertFrom-PestoTabularText "A;B`n1;`"two`nlines`"";Assert ($r.Rows[0].Cells[1] -ceq "two`nlines")}
Case 'Maximum row limit includes final line without newline' {Reject{ConvertFrom-PestoTabularText ("A;B`n"+(@(1..5001|%{'1;2'}) -join "`n"))}}
Case 'Import file: UTF-8 with or without BOM and UTF-16 with BOM decode exactly' {
 $text="Poste;Libellé`r`nPC1;Accès é"
 foreach($bytes in @(([Text.UTF8Encoding]::new($false)).GetBytes($text),([byte[]](0xEF,0xBB,0xBF)+([Text.UTF8Encoding]::new($false)).GetBytes($text)),([byte[]](0xFF,0xFE)+[Text.Encoding]::Unicode.GetBytes($text)),([byte[]](0xFE,0xFF)+[Text.Encoding]::BigEndianUnicode.GetBytes($text)))){
  $decoded=Read-PestoImportFile -Bytes ([byte[]]$bytes);Assert ($decoded -ceq $text) ('Décodage : '+$decoded)
  Assert ((ConvertFrom-PestoTabularText $decoded).Rows[0].Cells[1] -ceq 'Accès é')
 }
}
Case 'Import file: ANSI bytes are refused with the Excel guidance, never guessed' {
 $ansi=[byte[]](0x50,0x6F,0x73,0x74,0x65,0x3B,0x4C,0x69,0x62,0x65,0x6C,0x6C,0xE9,0x0D,0x0A,0x50,0x43,0x31,0x3B,0x41)
 $message='';try{Read-PestoImportFile -Bytes $ansi|Out-Null}catch{$message=$_.Exception.Message};Assert ($message -match 'CSV UTF-8') $message
 $message='';try{Read-PestoImportFile -Bytes ([byte[]](0xFF,0xFE,0x00,0xD8,0x41,0x00))|Out-Null}catch{$message=$_.Exception.Message};Assert ($message -match 'CSV UTF-8') ('UTF-16 invalide : '+$message)
}
Case 'Import file size is checked on the file before reading its bytes' {
 $s=$defs['Show-PestoMappedImport'];$check=$s.IndexOf('[IO.FileInfo]::new($dialog.FileName)).Length -gt 8MB');$read=$s.IndexOf('[IO.File]::ReadAllBytes($dialog.FileName)')
 Assert ($check -gt 0 -and $read -gt $check -and $s -notmatch '\$bytes\.Length -gt 8MB')
}
$headers=@('Nom_du_PC','Nouveau_Nom','OU_Destination','Renommer','Deplacer');$mapping=@{};foreach($h in $headers){$mapping[$h]=$h}
function Editor {param([string[][]]$Rows);$d=[pscustomobject]@{Headers=$headers;Rows=@(for($i=0;$i -lt $Rows.Count;$i++){[pscustomobject]@{Line=$i+2;Cells=$Rows[$i]}})};return ,(New-PestoImportEditor $d $mapping)}
Case 'Mapping defaults command flags to false and never imports consent or reboot' {$d=ConvertFrom-PestoTabularText "Machine;Cible;Traiter;Reboot`nPC1;P123456PAINF001;true;true";$r=New-PestoImportEditor $d @{Nom_du_PC='Machine';Nouveau_Nom='Cible'};Assert ($r.Rows[0].Renommer -ceq 'false' -and -not$r.Columns.Contains('Traiter') -and -not$r.Columns.Contains('Reboot'))}
Case 'Valid import produces DataTable unchecked and no restart with fresh checks' {$ed=Editor -Rows @(,@('PC1','P123456PAINF001','','true','false'));$r=Test-PestoImportEditor $ed (New-QueueTable);Assert ($r.Valid -and $r.Candidate -is [Data.DataTable]);Assert (-not$r.Candidate.Rows[0].Traiter -and -not$r.Candidate.Rows[0].Reboot -and $r.Candidate.Rows[0].NeedsReview -and -not$r.Candidate.Rows[0].Operation_ID)}
Case 'All row problems are retained and no partial candidate escapes' {$ed=Editor -Rows @(@('BAD NAME','WRONG','bad','maybe','true'),@('PC2','BAD','','true','false'));$r=Test-PestoImportEditor $ed (New-QueueTable);Assert (-not$r.Valid -and $null -eq $r.Candidate -and $r.ErrorRows -eq 2);Assert ($ed.Rows[0].Erreurs -match 'Renommer' -and $ed.Rows[0].Erreurs -match 'OU_Destination' -and $ed.Rows[0].Erreurs -match 'Nom_du_PC')}
Case 'Duplicates among import rows and existing queue are rejected' {$ed=Editor -Rows @(@('PC1','P123456PAINF001','','true','false'),@('PC2','P123456PAINF001','','true','false'));$r=Test-PestoImportEditor $ed (New-QueueTable);Assert (-not$r.Valid -and $ed.Rows[1].Erreurs -match 'cible dupliqué')}
Case 'Capacity sorts most exhausted first and respects threshold' {$r=@(Get-PestoCapacityThresholdRows @([pscustomobject]@{Libres=200},[pscustomobject]@{Libres=0},[pscustomobject]@{Libres=10},[pscustomobject]@{Libres=51}) 50);Assert ($r.Count -eq 2 -and $r[0].Niveau -eq 'Épuisé' -and $r[1].Libres -eq 10)}
Case 'Exclusions distinguish AD queue personal and shared expiry without invented timestamps' {$n='P123456PAINF001';$r=@(Get-PestoNameExclusionDetails $n ([pscustomobject]@{InAD=$true;SourceUtc='2026-10-13T10:00:00Z'}) @([pscustomobject]@{Nouveau_Nom=$n}) @($n) @{$n=[pscustomobject]@{ExpiresUtc='2026-10-14T00:00:00Z'}});Assert ($r.Count -eq 4 -and $r[0].Date -ceq '2026-10-13T10:00:00Z' -and $r[2].Date -match 'non enregistrée')}
Case 'Unknown provenance never promises availability' {$r=@(Get-PestoNameExclusionDetails 'PC1' ([pscustomobject]@{Reserved=$true}));Assert ($r.Count -eq 1 -and $r[0].Date -eq 'Date inconnue' -and $r[0].Limite -match 'Ne prouve')}
Case 'Hardware suggestions distinguish mobile fixed virtual and unknown' {Assert ((Get-PestoHardwareSuggestion 'Dell' 'Latitude' @(9)).Type -eq 'Portable');Assert ((Get-PestoHardwareSuggestion 'Dell' 'Optiplex' @(3)).Type -eq 'Fixe');Assert ((Get-PestoHardwareSuggestion 'Microsoft' 'Virtual Machine' @(3)).Type -eq 'Virtuel');Assert (-not(Get-PestoHardwareSuggestion '' '' @()).Type)}
Case 'Hardware reads are bounded local-only and suggestions require explicit acceptance' {Assert ($defs['Invoke-PestoHardwareRead'] -match 'OperationTimeoutSec 8' -and $defs['Invoke-PestoHardwareRead'] -notmatch 'ComputerName|CimSession');Assert ($defs['Invoke-PestoNameWorkbench'].Contains('Confirm-YesNo') -and $defs['Invoke-PestoNameWorkbench'].Contains('$c.Computer'))}
Case 'Standalone bulk planner no longer requires remote toggle or source form selection' {$s=$defs['Show-PestoBulkPlanner'];Assert ($s.Contains('Get-PestoBulkContext') -and -not$s.Contains('if(-not $ChkRemote.IsChecked)'))}
$script:table=New-QueueTable;$Grid=[pscustomobject]@{ItemsSource=$null};$script:CFG=[pscustomobject]@{};$script:PestoQueueUndo=$null
Case 'Published preparation creates undo; undo restores unchecked without receipt changes' {$before=Get-PestoQueueContentStamp $script:table;$ed=Editor -Rows @(,@('PC1','P123456PAINF001','','true','false'));$r=Test-PestoImportEditor $ed $script:table;Publish-PestoPreparedQueue $r.Candidate $before 'import';Assert ($script:table.Rows.Count -eq 1 -and $script:PestoQueueUndo.Count -eq 1);Undo-PestoQueuePreparation;Assert ($script:table.Rows.Count -eq 0)}
Case 'Publication conflict preserves current table and rejects stale preview' {$old=$script:table;Reject{Publish-PestoPreparedQueue (New-QueueTable) 'other' 'import'};Assert ([object]::ReferenceEquals($old,$script:table))}
Case 'Failed checkpoint publication rolls back table reference' {$old=$script:table;$script:FailSave=$true;try{Reject{Publish-PestoPreparedQueue (New-QueueTable) (Get-PestoQueueContentStamp $script:table) 'import'};Assert ([object]::ReferenceEquals($old,$script:table))}finally{$script:FailSave=$false}}
Case 'Undo refuses after table result changes and never clears results' {$before=$script:table.Copy();$ed=Editor -Rows @(,@('PC1','P123456PAINF001','','true','false'));$r=Test-PestoImportEditor $ed $script:table;Publish-PestoPreparedQueue $r.Candidate (Get-PestoQueueContentStamp $script:table) 'import';$script:table.Rows[0].Statut='OK';Reject{Undo-PestoQueuePreparation};Assert ($script:table.Rows[0].Statut -ceq 'OK')}

Case 'Multi-edit preserves original execution order even after table selection sorting' {
 $candidate=New-QueueTable;foreach($name in @('PC2','PC1-NEW','PC3')){$r=$candidate.NewRow();$r.Nom_du_PC=$name;[void]$candidate.Rows.Add($r)}
 $editor=Editor -Rows @(@('PC3','','','false','true'),@('PC1-NEW','','','false','true'));$editor.Rows[0].Ligne=3;$editor.Rows[1].Ligne=1
 $ordered=Restore-PestoEditedQueueOrder $candidate $editor @('PC1','PC2','PC3');Assert ((@($ordered.Rows.Nom_du_PC) -join ',') -ceq 'PC1-NEW,PC2,PC3')
}
Case 'Undo hooks cover local add remove clear classic import and bulk additions' {
 foreach($name in @('Add-Or-UpdateRow','Remove-PestoQueueRow','Import-Queue','Invoke-PestoBulkApply')){Assert ($defs[$name].Contains('Save-PestoQueueUndo')) $name};Assert ($defs['Run-Queue'].Contains('$script:PestoQueueUndo=$null'))
}

if($Wpf){Add-Type -AssemblyName PresentationFramework;Case 'WPF editable import grid loads with fixed result footer' {$match=[regex]::Match($defs['Show-PestoQueueEditor'],"(?s)\[xml\]\`$x=@'\s*(.*?)\s*'@");Assert $match.Success;[xml]$x=$match.Groups[1].Value;$w=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($x));Assert ($w.FindName('Editor') -and -not$w.FindName('Apply').IsEnabled);$w.Close()}}

function New-CsvRow {param($Name='PC1',$Target='P123456PAINF001');[pscustomobject]@{Nom_du_PC=$Name;Nouveau_Nom=$Target;OU_Actuelle='OU=Lab,DC=lab,DC=test';OU_Destination='OU=Lab,DC=lab,DC=test';Renommer='true';Deplacer='false';Statut='';Reboot='true'}}
Case 'Classic CSV validates actual rows atomically and leaves consent unset' {
 $old=New-QueueTable;$entry=New-CsvRow;$r=New-PestoCsvQueueCandidate @($entry) $old @('Reboot') $true
 Assert ($r.Valid -and $old.Rows.Count -eq 0 -and $r.Candidate.Rows.Count -eq 1) (($r.Errors|Select-Object -First 3) -join ';')
 Assert (-not$r.Candidate.Rows[0].Traiter -and $r.Candidate.Rows[0].Reboot)
}
Case 'Classic CSV detects source and target duplicates case insensitively' {
 foreach($rows in @(@((New-CsvRow 'PC1'),(New-CsvRow 'pc1' 'P123456PAINF002')),@((New-CsvRow 'PC1'),(New-CsvRow 'PC2' 'p123456painf001')))){
  $old=New-QueueTable;$r=New-PestoCsvQueueCandidate $rows $old @() $true
  Assert (-not$r.Valid -and $null -eq $r.Candidate -and $old.Rows.Count -eq 0 -and $r.Errors.Count -eq 1)
 }
}
Case 'Classic CSV indexes existing sources and reserved targets' {
 $old=New-QueueTable;$row=$old.NewRow();$row.Nom_du_PC='PC1';$row.Renommer=$true;$row.Nouveau_Nom='P123456PAINF001';$old.Rows.Add($row)
 foreach($entry in @((New-CsvRow 'pc1' 'P123456PAINF002'),(New-CsvRow 'PC2'))){$r=New-PestoCsvQueueCandidate @($entry) $old @() $true;Assert (-not$r.Valid -and $old.Rows.Count -eq 1)}
}
Case 'Classic CSV retains historical outcomes and marks interrupted rows uncertain' {
 $entry=New-CsvRow;$entry.Statut='EN COURS';$r=New-PestoCsvQueueCandidate @($entry) (New-QueueTable) @() $true
 Assert ($r.Valid -and $r.Candidate.Rows[0].Statut -ceq 'INCERTAIN' -and $r.Candidate.Rows[0].Code -ceq '97' -and -not$r.Candidate.Rows[0].Traiter)
}
Case 'Classic CSV 5000 rows use the product validator without recursive hash calls' {
 $items=@(1..5000|ForEach-Object{[pscustomobject]@{Nom_du_PC=('PC'+$_.ToString('D5'));Nouveau_Nom='';OU_Actuelle='';OU_Destination='OU=Lab,DC=lab,DC=test';Renommer='false';Deplacer='true';Statut=''}})
 $watch=[Diagnostics.Stopwatch]::StartNew();$r=New-PestoCsvQueueCandidate $items (New-QueueTable) @() $true;$watch.Stop()
 Assert ($r.Valid -and $r.Candidate.Rows.Count -eq 5000) (($r.Errors|Select-Object -First 3) -join ';')
 Write-Host ('ClassicCsv5000Ms='+$watch.ElapsedMilliseconds)
 Assert ($defs['New-PestoCsvQueueCandidate'] -notmatch 'Get-PestoStableHash|Get-PestoQueueContentStamp|candidate.Rows\|Where-Object')
}

$failed=@($results|Where-Object{-not $_.Passed});$report=[pscustomobject]@{Suite='BatchNames120';Wpf=[bool]$Wpf;Passed=$results.Count-$failed.Count;Failed=$failed.Count;Cases=$results};if($ReportPath){[IO.File]::WriteAllText($ReportPath,($report|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))};$failed|%{Write-Output ($_.Name+': '+$_.Error)};Write-Output ("BatchNames120 : {0}/{1} PASS" -f $report.Passed,$results.Count);if($failed.Count){exit 1}
