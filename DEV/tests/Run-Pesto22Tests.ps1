#requires -Version 5.1
[CmdletBinding()]
param([switch]$Wpf,[string]$ReportPath=(Join-Path ([IO.Path]::GetTempPath()) ('Pesto-RC22-'+[guid]::NewGuid().ToString('N')+'.json')))
$ErrorActionPreference='Stop';Set-StrictMode -Off
if($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){throw 'Recette cible : Windows PowerShell 5.1 sous Windows.'}
$root=Split-Path -Parent $PSScriptRoot
$results=[Collections.Generic.List[object]]::new()
foreach($file in Get-ChildItem (Join-Path $root 'wad') -Filter 'Pesto-*.ps1' -File){
 $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
 if($errors.Count){throw ($file.Name+': '+(($errors|ForEach-Object{$_.Message}) -join '; '))}
 foreach($node in $ast.EndBlock.Statements){if($node -is [Management.Automation.Language.FunctionDefinitionAst]){. ([scriptblock]::Create($node.Extent.Text))}}
}
function Assert22 {param($Condition,[string]$Message='Assertion non satisfaite');if(-not $Condition){throw $Message}}
function Equal22 {param($Actual,$Expected);if($Actual -cne $Expected){throw ('Attendu [{0}] ; obtenu [{1}]' -f $Expected,$Actual)}}
function Throws22 {param([scriptblock]$Body);$ok=$false;try{& $Body|Out-Null}catch{$ok=$true};Assert22 $ok 'Refus attendu'}
function Case22 {param([string]$Name,[scriptblock]$Body);try{& $Body;$results.Add([pscustomobject]@{Name=$Name;State='PASS';Error=''});Write-Host ('PASS '+$Name)}catch{$results.Add([pscustomobject]@{Name=$Name;State='FAIL';Error=$_.Exception.Message});Write-Host ('FAIL '+$Name+' : '+$_.Exception.Message)}}
function Get-ADComputer {throw 'Accès AD réel interdit'}
function Set-ADObject {throw 'Écriture AD réelle interdite'}
function Move-ADObject {throw 'Déplacement réel interdit'}
function Rename-Computer {throw 'Renommage réel interdit'}
function Add-Computer {throw 'Jonction réelle interdite'}
function Write-PestoIntervention {param($Receipt);$script:Written22=($Receipt|ConvertTo-Json -Depth 10|ConvertFrom-Json);$script:Writes22++}
function Exit-PestoCoordination {param($Receipt,$Policy);$script:Releases22++}
function Add-LogLine {param($Text,$Kind)}
function Write-Log {param($Text,$Level,$Err,$Context)}
function Get-PestoAppearanceValue {throw 'Registre réel interdit'}
function Set-PestoAppearanceValue {throw 'Registre réel interdit'}
function Update-PestoSuiteUI {}
$script:GUI=$true;$script:SIM=$true;$script:DOMAINE='test.invalid';$script:PREFIXE='111301'
function Plan22 {
 [pscustomobject]@{Nom_du_PC='P111301AA765001';Nouveau_Nom='P111301BB765002';OU_Actuelle='OU=AA,DC=test,DC=invalid';OU_Destination='OU=BB,DC=test,DC=invalid';Objet_GUID='11111111-1111-1111-1111-111111111111';TargetOUGuid='22222222-2222-2222-2222-222222222222';Domain='test.invalid';DC='dc.test.invalid';ConfigStamp=('a'*64);Renommer=$true;Deplacer=$true;Reboot=$false}
}
function Observation22 {
 $now=[DateTimeOffset]::UtcNow.ToString('o')
 [pscustomobject]@{ObservedUtc=$now;ADUtc=$now;WindowsUtc=$now;AD=[pscustomobject]@{Name='P111301AA765001';Guid='11111111-1111-1111-1111-111111111111';OU='OU=AA,DC=test,DC=invalid';Protected=$false};Windows=[pscustomobject]@{ActiveName='P111301AA765001';ConfiguredName='P111301AA765001';Domain='test.invalid';PartOfDomain=$true;MachineId='fixture-machine';BootUtc=$now;DomainRole=1};Health=[pscustomobject]@{Utc=$now;Scope='Appareil local';AzureAdJoined='NO';DomainJoined='YES';SecureChannel='Conforme';Errors=@('SECRET-SENTINEL-22')}}
}
function Receipt22 {
 [pscustomobject]@{Schema=2;OperationId=('a'*32);Plan=(Plan22);Baseline=$null;LastObservation=$null;TargetMachineId='fixture-machine';InitialProtection=$false;Entra='Skipped';Rename='NotRequested';Move='NotRequested';Protection='NotChanged';Phase='Running';Sequence=0;Timeline=@();LastStage='';UpdatedUtc='';ResumeFrom='';ResultCode=0;ResultMessage=''}
}
Case22 'Types et codes inconnus restent incertains' {foreach($v in @($null,'20',[long]20,0,12345,-1)){Equal22 (Get-PestoOutcome $v) 'Uncertain'}}
Case22 'Précontrôle après engagement ne devient pas un refus certain' {Equal22 (Get-PestoOutcome 96 -Committed $true) 'Uncertain';Equal22 (Get-PestoOutcome 96) 'NotStarted'}
Case22 'Générateur normalise aussi la lettre de type' {Equal22 (New-PestoComputerName p '111301' aa a01 1) 'P111301AAA01001'}
Case22 'Analyse héritée refuse un nom arbitraire de quinze caractères' {Assert22 ($null -eq (Get-NameParts '123456789012345'));Equal22 (Get-NameParts 'p111301aa765001').Lettre 'P'}
Case22 'Déplacement confirmé puis erreur conserve un effet partiel' {
 $script:ActiveIntervention=Receipt22;$script:ActiveIntervention.Move='Confirmed';$script:Writes22=0;$script:Releases22=0
 $a=Complete-PestoIntervention (New-ActionResult 31 'fixture')
 Equal22 $script:ActiveIntervention.Phase 'Partial';Equal22 $a.ExitCode 97;Equal22 $a.Outcome 'Partial';Equal22 $script:Releases22 0;Assert22 ($script:Writes22 -gt 0)
}
Case22 'Code entier inconnu ne libère pas la coordination' {
 $script:ActiveIntervention=Receipt22;$script:Releases22=0
 $a=Complete-PestoIntervention (New-ActionResult 0 'fixture')
 Equal22 $a.ExitCode 97;Equal22 $script:ActiveIntervention.Phase 'Uncertain';Equal22 $script:Releases22 0
}
Case22 'Snapshot ferme ses champs et ne conserve pas les erreurs brutes' {
 $s=ConvertTo-PestoObservationSnapshot (Observation22);Equal22 $s.AD.Protected $false;Equal22 $s.Health.SecureChannel $true
 Assert22 (($s|ConvertTo-Json -Depth 8) -notmatch 'SECRET-SENTINEL-22');Assert22 (-not $s.Health.PSObject.Properties['Errors'])
}
Case22 'Snapshot refus des secrets ou champs inconnus' {$s=ConvertTo-PestoObservationSnapshot (Observation22);$s|Add-Member Password 'sentinelle';Throws22 {Assert-PestoObservationSnapshot $s}}
Case22 'Snapshot refus booléen sous forme de chaîne' {$o=Observation22;$o.AD.Protected='false';Throws22 {ConvertTo-PestoObservationSnapshot $o}}
Case22 'Canal sécurisé non lu reste inconnu, pas faux' {$o=Observation22;$o.Health.SecureChannel='Unknown';Assert22 ($null -eq (ConvertTo-PestoObservationSnapshot $o).Health.SecureChannel)}
Case22 'Snapshot dates et rôles malformés refusés' {$o=Observation22;$o.ADUtc='hier';Throws22 {ConvertTo-PestoObservationSnapshot $o};$o=Observation22;$o.Windows.DomainRole=9;Throws22 {ConvertTo-PestoObservationSnapshot $o}}
Case22 'Baseline initiale conservée pendant une seconde observation' {
 $script:GUI=$false;$script:SIM=$false;$script:ActiveIntervention=Receipt22;$script:Writes22=0
 try{Set-PestoInitialObservation (Observation22);$hash=Get-PestoStableHash $script:ActiveIntervention.Baseline;$o=Observation22;$o.AD.Name='P111301BB765002';Set-PestoInitialObservation $o;Equal22 (Get-PestoStableHash $script:ActiveIntervention.Baseline) $hash;Equal22 $script:Writes22 1}finally{$script:GUI=$true;$script:SIM=$true}
}
Case22 'Baseline étrangère refusée avant écriture' {
 $script:GUI=$false;$script:SIM=$false;$script:ActiveIntervention=Receipt22;$script:Writes22=0
 try{$o=Observation22;$o.AD.Guid='33333333-3333-3333-3333-333333333333';Throws22 {Set-PestoInitialObservation $o};Equal22 $script:Writes22 0}finally{$script:GUI=$true;$script:SIM=$true}
}
Case22 'Comparaison garde Avant et Prévu distincts des observations' {
 $r=Receipt22;$r.Baseline=ConvertTo-PestoObservationSnapshot (Observation22);$o=Observation22;$o.Windows.ConfiguredName=$r.Plan.Nouveau_Nom
 $rows=@(Get-PestoObservationComparison $r $o);Equal22 $rows.Count 10
 $row=@($rows|Where-Object Champ -eq 'Nom Windows configuré')[0];Equal22 $row.Avant $r.Plan.Nom_du_PC;Equal22 $row.Prevu $r.Plan.Nouveau_Nom;Equal22 $row.Etat 'Concordant'
 Equal22 $r.Baseline.Windows.ConfiguredName $r.Plan.Nom_du_PC
}
Case22 'Ancien reçu sans baseline ne fabrique pas une lecture Avant' {$rows=@(Get-PestoObservationComparison (Receipt22));Equal22 $rows[0].Avant 'Non enregistré';Equal22 $rows[0].Observe 'Inconnu'}
Case22 'Protection false est une observation connue' {$r=Receipt22;$rows=@(Get-PestoObservationComparison $r (Observation22));Equal22 (@($rows|Where-Object Champ -eq 'Protection AD')[0]).Etat 'Concordant'}
$commands22=@([pscustomobject]@{Id='move';Label='Déplacer un poste';Detail='Choisir un emplacement'};[pscustomobject]@{Id='read';Label='Lire un poste';Detail='Sans écriture'})
Case22 'Palette recherche multi-mots insensible aux accents' {Equal22 (@(Find-PestoCommands $commands22 'deplacer poste')[0]).Id 'move'}
Case22 'Palette filtre littéral et non expression régulière' {Equal22 @(Find-PestoCommands $commands22 '[').Count 0;Equal22 @(Find-PestoCommands $commands22 '.*').Count 0}
Case22 'Palette vide conserve toutes les commandes' {Equal22 @(Find-PestoCommands $commands22 '').Count 2}
Case22 'Palette recherche trop longue refusée' {Throws22 {Find-PestoCommands $commands22 ('x'*129)}}
$cat22=@([pscustomobject]@{Site='AA';Service='765'};[pscustomobject]@{Site='BB';Service='001'})
Case22 'Capacité inclut les combinaisons vides déclarées seulement' {$r=@(Get-PestoCapacityRows @() $cat22 @() '111301' $null);Equal22 $r.Count 6;Equal22 @($r|Where-Object {$_.Site -eq 'AA' -and $_.Service -eq '001'}).Count 0;Equal22 ($r|Measure-Object Libres -Sum).Sum 5994}
Case22 'Capacité ne compte pas deux fois doublons et réservations occupées' {
 $r=@(Get-PestoCapacityRows @([pscustomobject]@{Name='P111301AA765001'};[pscustomobject]@{Name='P111301AA765001'}) @() @('P111301AA765001','P111301AA765002','P111301AA765002') '111301' $null)
 Equal22 $r.Count 1;Equal22 $r[0].Occupes 1;Equal22 $r[0].Prepares 1;Equal22 $r[0].Libres 997
}
Case22 'Capacité ignore les noms invalides et annule à la demande' {Equal22 @(Get-PestoCapacityRows @([pscustomobject]@{Name='INVALIDE'}) @() @() '111301' $null).Count 0;Throws22 {Get-PestoCapacityRows @([pscustomobject]@{Name='P111301AA765001'}) @() @() '111301' ([pscustomobject]@{Cancelled=$true})}}
$meta22=@([pscustomobject]@{Org='Org';Name='Site A';DN='OU=Site\, A,OU=Sites,DC=test,DC=invalid';Root='OU=Sites,DC=test,DC=invalid';Guid='11111111-1111-1111-1111-111111111112'})
$tags22=@([pscustomobject]@{Site='Site A';Tag='AA'})
Case22 'Conformité respecte les virgules échappées et sous-OU' {$pc=[pscustomobject]@{Name='P111301AA765001';DistinguishedName='CN=P111301AA765001,OU=Sous,OU=Site\, A,OU=Sites,DC=test,DC=invalid'};$r=@(Get-PestoConformityRows @($pc) '111301' $tags22 $meta22);Equal22 $r[0].Etat 'Conforme au nom et au site'}
Case22 'Conformité détecte une OU différente sans générer de mutation' {$pc=[pscustomobject]@{Name='P111301AA765001';DistinguishedName='CN=P111301AA765001,OU=Autre,OU=Sites,DC=test,DC=invalid'};$r=@(Get-PestoConformityRows @($pc) '111301' $tags22 $meta22);Equal22 $r[0].Etat 'Emplacement différent';Equal22 $r[0].OUAttendues $meta22[0].DN}
Case22 'Conformité sans métadonnées reste inconnue' {$pc=[pscustomobject]@{Name='P111301AA765001';DistinguishedName='CN=P111301AA765001,OU=Autre,OU=Sites,DC=test,DC=invalid'};Equal22 (@(Get-PestoConformityRows @($pc) '111301' $tags22 @())[0]).Etat 'Emplacement non vérifié'}
Case22 'Conformité ne choisit pas entre deux destinations ambiguës' {$pc=[pscustomobject]@{Name='P111301AA765001';DistinguishedName='CN=P111301AA765001,OU=Autre,OU=Sites,DC=test,DC=invalid'};Equal22 (@(Get-PestoConformityRows @($pc) '111301' $tags22 @($meta22[0],$meta22[0]))[0]).Etat 'Destination ambiguë'}
Case22 'Conformité respecte la zone de préparation' {$pc=[pscustomobject]@{Name='P111301AA765001';DistinguishedName='CN=P111301AA765001,OU=PREPROD,DC=test,DC=invalid'};Equal22 (@(Get-PestoConformityRows @($pc) '111301' $tags22 $meta22 'OU=PREPROD,DC=test,DC=invalid')[0]).Etat 'Zone de préparation'}
function Tables22 {
 [pscustomobject]@{Schema=1;Tables=@([pscustomobject]@{Id='names';Signature=('a'*64);Columns=@([pscustomobject]@{Key='Nom';Order=0;Unit='Pixel';Value=200};[pscustomobject]@{Key='Site';Order=1;Unit='Star';Value=1})})}
}
Case22 'Préférences de colonnes acceptent le schéma fermé' {Equal22 (ConvertTo-PestoTablePreferences (Tables22)).Tables.Count 1}
Case22 'Préférences refusent sélection, ordre dupliqué et largeur invalide' {
 $p=Tables22;$p.Tables[0]|Add-Member SelectedItem 'poste';Throws22 {ConvertTo-PestoTablePreferences $p}
 $p=Tables22;$p.Tables[0].Columns[1].Order=0;Throws22 {ConvertTo-PestoTablePreferences $p}
 $p=Tables22;$p.Tables[0].Columns[0].Value=[double]::NaN;Throws22 {ConvertTo-PestoTablePreferences $p}
 $p=Tables22;$p.Tables[0].Columns[0].Value='200';Throws22 {ConvertTo-PestoTablePreferences $p}
}
Case22 'Préférences refusent une clé de commande et les largeurs excessives' {$p=Tables22;$p.Tables[0].Columns[0].Key='$(Get-Item)';Throws22 {ConvertTo-PestoTablePreferences $p};$p=Tables22;$p.Tables[0].Columns[0].Value=2000;Throws22 {ConvertTo-PestoTablePreferences $p}}
if($Wpf){
 Case22 'Tableaux WPF sauvegardés sans sélection ni changement de visibilité' {
  Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
  $script:PestoTables=@{};$script:PestoTablesMemory='';$g=[Windows.Controls.DataGrid]::new()
  foreach($name in @('Nom','Site','Service')){$c=[Windows.Controls.DataGridTextColumn]::new();$c.Binding=[Windows.Data.Binding]::new($name);$c.Width=[Windows.Controls.DataGridLength]::new(150);$g.Columns.Add($c)}
  Register-PestoTable -Id names -Grid $g -Fixed 1
  $g.Columns[1].DisplayIndex=2;$g.Columns[1].Width=[Windows.Controls.DataGridLength]::new(210);Save-PestoTables
  $g.Columns[1].DisplayIndex=1;$g.Columns[1].Width=[Windows.Controls.DataGridLength]::new(100);Apply-PestoSavedTables
  Equal22 $g.Columns[1].DisplayIndex 2;Equal22 $g.Columns[1].Width.Value 210;Assert22 (-not $g.Columns[0].CanUserReorder);Assert22 ($null -eq $g.SelectedItem)
  Reset-PestoTables;Equal22 $g.Columns[1].DisplayIndex 1;Equal22 $g.Columns[1].Width.Value 150
 }
 Case22 'Palette réelle filtre et ferme sans exécuter une action métier' {
  if([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA'){throw 'STA requis'}
  $shell=[Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText((Join-Path $root 'wad/Pesto-Shell.xaml')))
  $savedWin=$script:Win;$script:Win=[Windows.Window]::new();$script:Win.Resources=$shell.Resources;$script:Win.Width=850;$script:Win.Height=650;$script:Win.Content=[Windows.Controls.Grid]::new()
  $parent=[Windows.Controls.Button]::new();$parent.Content='Fixture';[void]$script:Win.Content.Children.Add($parent)
  function Invoke-Fixture22PaletteTick {
   $script:Ticks22++
   if($script:PestoPanelStack.Count){$s=$script:PestoPanelStack[$script:PestoPanelStack.Count-1];$s.Search.Text='deplacer poste';Invoke-PestoPanelButton $s.Accept $null}
   if($script:Ticks22 -gt 20){$script:PaletteTimeout22=$true;if($script:PestoPanelStack.Count){$script:PestoPanelStack[$script:PestoPanelStack.Count-1].Frame.Continue=$false}}
  }
  $script:Ticks22=0;$script:PaletteTimeout22=$false;$timer=[Windows.Threading.DispatcherTimer]::new();$timer.Interval=[TimeSpan]::FromMilliseconds(100);$handler=[EventHandler]${function:Invoke-Fixture22PaletteTick};$timer.Add_Tick($handler)
  try{$script:Win.Show();$timer.Start();$r=Show-PestoPanel -Title 'Fixture palette' -AcceptText 'Ouvrir' -Choices $commands22 -SearchChoices;Assert22 (-not $script:PaletteTimeout22) 'Palette fixture expirée';Assert22 $r.Accepted;Equal22 $r.Selected.Id 'move';Equal22 $script:Win.Content.Children.Count 1;Assert22 $parent.IsEnabled}
  finally{$timer.Stop();$timer.Remove_Tick($handler);$script:Win.Close();$script:Win=$savedWin;$shell.Close()}
 }
}else{$results.Add([pscustomobject]@{Name='WPF RC22';State='SKIP';Error='Passer -Wpf sous Windows PowerShell -STA.'})}
$fail=@($results|Where-Object State -eq 'FAIL').Count;$skip=@($results|Where-Object State -eq 'SKIP').Count
[pscustomobject]@{Version='1.0';Utc=[DateTime]::UtcNow.ToString('o');PowerShell=[string]$PSVersionTable.PSVersion;Failed=$fail;Skipped=$skip;NoLiveAD=$true;NoUAC=$true;Checks=$results.ToArray()}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $ReportPath -Encoding UTF8
Write-Host ('Rapport : '+$ReportPath)
if($fail -or $skip){exit 1}else{exit 0}
