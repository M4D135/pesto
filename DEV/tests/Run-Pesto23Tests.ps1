#requires -Version 5.1
[CmdletBinding()]
param([switch]$Wpf,[string]$ReportPath=(Join-Path ([IO.Path]::GetTempPath()) ('Pesto-RC23-'+[guid]::NewGuid().ToString('N')+'.json')))
$ErrorActionPreference='Stop';Set-StrictMode -Off
if($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){throw 'Recette cible : Windows PowerShell 5.1 sous Windows.'}
$root=Split-Path -Parent $PSScriptRoot
$results=[Collections.Generic.List[object]]::new()
# Charger des définitions AST seulement, jamais le démarrage du moteur.
foreach($file in Get-ChildItem (Join-Path $root 'wad') -Filter 'Pesto-*.ps1' -File){
 $t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$t,[ref]$e)
 if($e.Count){throw ($file.Name+': '+(($e|ForEach-Object{$_.Message}) -join '; '))}
 foreach($node in $ast.EndBlock.Statements){if($node -is [Management.Automation.Language.FunctionDefinitionAst]){. ([scriptblock]::Create($node.Extent.Text))}}
}
function Assert23 {param($Value,[string]$Why='Condition non satisfaite');if(-not $Value){throw $Why}}
function Equal23 {param($Actual,$Expected);if($Actual -cne $Expected){throw ('Attendu [{0}], obtenu [{1}]' -f $Expected,$Actual)}}
function Throws23 {param([scriptblock]$Body);$thrown=$false;try{& $Body|Out-Null}catch{$thrown=$true};Assert23 $thrown 'Refus attendu'}
function Case23 {param([string]$Name,[scriptblock]$Body);try{& $Body;$results.Add([pscustomobject]@{Name=$Name;State='PASS';Error=''});Write-Host ('PASS '+$Name)}catch{$results.Add([pscustomobject]@{Name=$Name;State='FAIL';Error=$_.Exception.Message});Write-Host ('FAIL '+$Name+' : '+$_.Exception.Message)}}
function Get-ADComputer {throw 'AD réel interdit dans les fixtures'}
function Get-ADOrganizationalUnit {throw 'AD réel interdit dans les fixtures'}
function Set-ADObject {throw 'AD réel interdit dans les fixtures'}
function Add-Computer {throw 'Jonction réelle interdite'}
function Rename-Computer {throw 'Renommage réel interdit'}
function Test-ComputerSecureChannel {throw 'Canal réel interdit'}
function Restart-Computer {throw 'Redémarrage réel interdit'}
function Get-ItemProperty {throw 'Registre réel interdit'}
function Write-PestoIntervention {param($Receipt);$script:Writes23++;if($script:DiskFail23){throw 'Disque factice inaccessible'};$script:Saved23=($Receipt|ConvertTo-Json -Depth 10|ConvertFrom-Json)}
function Exit-PestoCoordination {param($Receipt,$Policy);$script:Release23++}
function Write-Log {param($Message,$Level,$Err,$Context)}
function Add-LogLine {param($Text,$Kind)}
function Update-PestoSuiteUI {}
$script:GUI=$false;$script:SIM=$false;$script:PestoReadOnly=$false;$script:Pesto_VERSION='1.0';$script:PREFIXE='111301';$script:DOMAINE='test.invalid'
function Legacy23 {
 [pscustomobject]@{Schema=1;Version='17.0-RC22';OperationId=('a'*32);Phase='PendingRestart';Utc='2026-01-01T12:00:00Z';MachineId='fixture-machine';BootUtc='2026-01-01T08:00:00Z';Computer='SOURCE';NewName='P111301AA765001';Domain='test.invalid';OU='OU=AA,DC=test,DC=invalid';DC='dc.test.invalid';Reference='';Account='fixture';Message='Demande historique'}
}
function Join23 {
 $r=ConvertFrom-PestoLegacyJoinReceipt (Legacy23) 'test.invalid' 'fixture-machine' ('f'*64)
 $r.Plan.TargetOUGuid='22222222-2222-2222-2222-222222222222'
 $r.PlanFingerprint=Get-PestoPlanFingerprint $r.Plan
 return $r
}
function Local23 {
 [pscustomobject]@{Computer='SOURCE';ActiveName='SOURCE';ConfiguredName='SOURCE';PartOfDomain=$false;PendingRename=$false;DomainRole=0;Domain='WORKGROUP';Admin=$true;MachineId='fixture-machine';BootUtc='2026-01-01T08:00:00Z'}
}
function Observation23 {
 $now=[DateTimeOffset]::UtcNow.ToString('o')
 [pscustomobject]@{ObservedUtc=$now;ADUtc=$now;WindowsUtc=$now;JoinDestinationGuid='22222222-2222-2222-2222-222222222222';
  AD=[pscustomobject]@{Name='P111301AA765001';Guid='11111111-1111-1111-1111-111111111111';OU='OU=AA,DC=test,DC=invalid';Protected=$false};
  Windows=[pscustomobject]@{ActiveName='P111301AA765001';ConfiguredName='P111301AA765001';Domain='test.invalid';PartOfDomain=$true;DomainRole=1;MachineId='fixture-machine';BootUtc='2026-01-02T08:00:00Z'};
  Health=[pscustomobject]@{Utc=$now;Scope='Appareil local';AzureAdJoined='NO';DomainJoined='YES';SecureChannel='Conforme';Errors=@('SECRET-SENTINEL-23')};Errors=@('SECRET-SENTINEL-23')}
}
function Decision23 {param($r=(Join23),$o=(Observation23),$machine='fixture-machine');Get-PestoJoinObservationDecision $r $o $machine}
function FreshLedger23 {
 $r=Join23;$r.PSObject.Properties.Remove('JoinEvidence');$r.Schema=2;$r.Baseline=$null;$r.Phase='Running'
 $script:ActiveIntervention=$r;$script:DiskFail23=$false;$script:Writes23=0;return $r
}
Case23 'Reçu historique exact accepté' {Equal23 (Assert-PestoJoinReceiptData (Legacy23)).Phase 'PendingRestart'}
Case23 'Schéma textuel refusé' {$r=Legacy23;$r.Schema='1';Throws23 {Assert-PestoJoinReceiptData $r}}
Case23 'Champ secret inattendu refusé' {$r=Legacy23;$r|Add-Member Password 'SECRET-SENTINEL-23';Throws23 {Assert-PestoJoinReceiptData $r}}
Case23 'Identifiant de reçu vide refusé' {$r=Legacy23;$r.OperationId='';Throws23 {Assert-PestoJoinReceiptData $r}}
Case23 'Champ date sans fuseau refusé' {$r=Legacy23;$r.Utc='2026-01-01T12:00:00';Throws23 {Assert-PestoJoinReceiptData $r}}
Case23 'Chronologie impossible refusée' {$r=Legacy23;$r.BootUtc='2026-01-02T12:00:00Z';Throws23 {Assert-PestoJoinReceiptData $r}}
Case23 'OU dans un autre domaine refusée' {$r=Legacy23;$r.OU='OU=AA,DC=else,DC=invalid';Throws23 {Assert-PestoJoinReceiptData $r}}
Case23 'Nom futur invalide refusé' {$r=Legacy23;$r.NewName='arbitrary';Throws23 {Assert-PestoJoinReceiptData $r}}
Case23 'Reçu d''un autre préfixe accepté (cfg.json changé depuis)' {$r=Legacy23;$r.NewName='V999004AAQA1006';Equal23 (Assert-PestoJoinReceiptData $r).NewName 'V999004AAQA1006'}
Case23 'Message trop volumineux refusé' {$r=Legacy23;$r.Message='x'*8193;Throws23 {Assert-PestoJoinReceiptData $r}}
Case23 'Import jonction sans inventer succès ou baseline' {$r=Join23;Equal23 $r.Schema 3;Equal23 $r.Phase 'Uncertain';Equal23 $r.JoinEvidence.NativeStatus 'Unknown';Assert23 ($null -eq $r.Baseline);Equal23 $r.Legacy.Kind 'Join'}
Case23 'Les trois phases historiques non résolues sont importables' {foreach($phase in @('Running','PendingRestart','Uncertain')){$r=Legacy23;$r.Phase=$phase;Equal23 (ConvertFrom-PestoLegacyState $r 'test.invalid' 'fixture-machine' ('f'*64)).Phase 'Uncertain'}}
Case23 'Historique déjà résolu non réimporté comme en cours' {foreach($phase in @('Failed','Verified')){$r=Legacy23;$r.Phase=$phase;Equal23 @(ConvertFrom-PestoLegacyJoinReceipt $r 'test.invalid' 'fixture-machine' ('f'*64)).Count 0}}
Case23 'Import autre PC refusé' {Throws23 {ConvertFrom-PestoLegacyJoinReceipt (Legacy23) 'test.invalid' 'other' ('f'*64)}}
Case23 'Import autre domaine refusé' {Throws23 {ConvertFrom-PestoLegacyJoinReceipt (Legacy23) 'other.invalid' 'fixture-machine' ('f'*64)}}
Case23 'Import hash tronqué refusé' {Throws23 {ConvertFrom-PestoLegacyJoinReceipt (Legacy23) 'test.invalid' 'fixture-machine' 'abc'}}
Case23 'L import ne modifie pas sa source' {$r=Legacy23;$before=Get-PestoStableHash $r;$null=ConvertFrom-PestoLegacyJoinReceipt $r 'test.invalid' 'fixture-machine' ('f'*64);Equal23 (Get-PestoStableHash $r) $before}
Case23 'Baseline locale durable avant commande' {$null=FreshLedger23;Set-PestoInitialJoinObservation (Local23);Equal23 $script:Writes23 1;Equal23 $script:Saved23.Schema 3;Equal23 $script:Saved23.JoinEvidence.NativeStatus 'Prepared';Equal23 $script:Saved23.Baseline.Windows.Domain 'WORKGROUP';Assert23 ($null -eq $script:Saved23.Baseline.AD)}
Case23 'Photographie de jonction immuable' {$null=FreshLedger23;Set-PestoInitialJoinObservation (Local23);$before=Get-PestoStableHash $script:ActiveIntervention.Baseline;Throws23 {Set-PestoInitialJoinObservation (Local23)};Equal23 (Get-PestoStableHash $script:ActiveIntervention.Baseline) $before;Equal23 $script:Writes23 1}
Case23 'Préparation échoue quand écriture durable échoue' {$null=FreshLedger23;$script:DiskFail23=$true;try{Throws23 {Set-PestoInitialJoinObservation (Local23)}}finally{$script:DiskFail23=$false}}
Case23 'Machine déjà dans un domaine refusée avant baseline' {$null=FreshLedger23;$l=Local23;$l.PartOfDomain=$true;Throws23 {Set-PestoInitialJoinObservation $l};Equal23 $script:Writes23 0}
Case23 'Jeton non élevé refusé avant baseline' {$null=FreshLedger23;$l=Local23;$l.Admin=$false;Throws23 {Set-PestoInitialJoinObservation $l};Equal23 $script:Writes23 0}
Case23 'Booléens sous forme de chaînes refusés avant baseline' {$null=FreshLedger23;$l=Local23;$l.PendingRename='false';Throws23 {Set-PestoInitialJoinObservation $l};Equal23 $script:Writes23 0}
Case23 'Demande native est persistée et ne peut être répétée' {$null=FreshLedger23;Set-PestoInitialJoinObservation (Local23);Set-PestoJoinNativeStatus Requested;Equal23 $script:Saved23.JoinEvidence.NativeStatus 'Requested';Throws23 {Set-PestoJoinNativeStatus Requested}}
Case23 'Acceptation native ne permet pas une seconde commande' {$null=FreshLedger23;Set-PestoInitialJoinObservation (Local23);Set-PestoJoinNativeStatus Requested;Set-PestoJoinNativeStatus Accepted;Throws23 {Set-PestoJoinNativeStatus Requested};Equal23 $script:Saved23.JoinEvidence.NativeStatus 'Accepted'}
Case23 'Acceptation sans demande native préalable refusée' {$null=FreshLedger23;Set-PestoInitialJoinObservation (Local23);Throws23 {Set-PestoJoinNativeStatus Accepted};Equal23 $script:Saved23.JoinEvidence.NativeStatus 'Prepared'}
Case23 'Retour tardif de jonction ne libère pas la coordination' {$null=FreshLedger23;Set-PestoInitialJoinObservation (Local23);Set-PestoJoinNativeStatus Requested;Set-PestoJoinNativeStatus Accepted;$script:Release23=0;$a=Complete-PestoIntervention (New-ActionResult 10 'fixture') -TimedOut $true;Equal23 $a.ExitCode 97;Equal23 $script:Release23 0;Equal23 $script:ActiveIntervention.JoinEvidence.NativeStatus 'Accepted'}
Case23 'Postconditions complètes vérifiables mais pas de réinscription Entra supposée' {$d=Decision23;Assert23 $d.Verified;Equal23 $d.BoundObjectGuid '11111111-1111-1111-1111-111111111111';Assert23 ($d.Message -match 'Entra')}
Case23 'Ancien reçu sans preuve de démarrage reste indéterminé' {$r=Join23;$r.PSObject.Properties.Remove('JoinEvidence');Assert23 (-not (Decision23 $r).Verified)}
Case23 'Identité du PC local différente refusée' {Assert23 (-not (Decision23 -machine other).Verified)}
Case23 'Identité Windows différente refusée' {$o=Observation23;$o.Windows.MachineId='other';Assert23 (-not (Decision23 -o $o).Verified)}
Case23 'Contrôleur de domaine non certifié par le test membre' {$o=Observation23;$o.Windows.DomainRole=5;Assert23 (-not (Decision23 -o $o).Verified)}
Case23 'Domaine Windows différent non vérifié' {$o=Observation23;$o.Windows.Domain='else.invalid';Assert23 (-not (Decision23 -o $o).Verified)}
Case23 'Nom actif précédent attend redémarrage' {$o=Observation23;$o.Windows.ActiveName='SOURCE';$d=Decision23 -o $o;Assert23 (-not $d.Verified);Assert23 $d.PendingRestart}
Case23 'Pas de nouveau boot déduit d une simple chaîne différente' {$o=Observation23;$o.Windows.BootUtc='2026-01-01T09:00:00+01:00';Assert23 (-not (Decision23 -o $o).Verified)}
Case23 'Boot antérieur au reçu refusé' {$o=Observation23;$o.Windows.BootUtc='2025-01-01T08:00:00Z';Assert23 (-not (Decision23 -o $o).Verified)}
Case23 'Boot avant la date de préparation ne résout pas la jonction' {$o=Observation23;$o.Windows.BootUtc='2026-01-01T10:00:00Z';Assert23 (-not (Decision23 -o $o).Verified)}
Case23 'Boot sans fuseau ne résout pas la jonction' {$o=Observation23;$o.Windows.BootUtc='2026-01-02T08:00:00';Assert23 (-not (Decision23 -o $o).Verified)}
Case23 'Absence AD conserve l incertitude' {$o=Observation23;$o.AD=$null;Assert23 (-not (Decision23 -o $o).Verified)}
Case23 'Emplacement AD différent refuse la résolution' {$o=Observation23;$o.AD.OU='OU=BB,DC=test,DC=invalid';Assert23 (-not (Decision23 -o $o).Verified)}
Case23 'OU supprimée recréée de même nom est rejetée' {$o=Observation23;$o.JoinDestinationGuid='33333333-3333-3333-3333-333333333333';Assert23 (-not (Decision23 -o $o).Verified)}
Case23 'Compte précréé remplacé est rejeté' {$r=Join23;$r.Plan.Objet_GUID='33333333-3333-3333-3333-333333333333';Assert23 (-not (Decision23 $r).Verified)}
Case23 'Compte déjà lié remplacé est rejeté' {$r=Join23;$r.JoinEvidence.BoundObjectGuid='33333333-3333-3333-3333-333333333333';Assert23 (-not (Decision23 $r).Verified)}
Case23 'Chaîne false du canal ne devient pas vraie' {$o=Observation23;$o.Health.SecureChannel='false';Assert23 (-not (Decision23 -o $o).Verified)}
Case23 'Canal booléen false reste non conforme' {$o=Observation23;$o.Health.SecureChannel=$false;Assert23 (-not (Decision23 -o $o).Verified)}
Case23 'Canal non prêt : relecture dans 30 s, sans réparation' {$o=Observation23;$o.Health.SecureChannel=$false;$d=Decision23 -o $o;Assert23 (-not $d.Verified);Assert23 ($d.RetryAfterSec -eq 30);Assert23 ($d.Message -like '*Aucune réparation automatique.');Assert23 (-not (Decision23).PSObject.Properties['RetryAfterSec'])}
Case23 'Sources périmées refusées séparément' {foreach($name in @('ADUtc','WindowsUtc','ObservedUtc','Health')){$o=Observation23;$old=[DateTimeOffset]::UtcNow.AddMinutes(-3).ToString('o');if($name -eq 'Health'){$o.Health.Utc=$old}else{$o.$name=$old};Assert23 (-not (Decision23 -o $o).Verified)}}
Case23 'Date de lecture future refusée' {$o=Observation23;$o.ADUtc=[DateTimeOffset]::UtcNow.AddMinutes(1).ToString('o');Assert23 (-not (Decision23 -o $o).Verified)}
Case23 'Plan de jonction reste immuable pendant décision' {$r=Join23;$hash=Get-PestoPlanFingerprint $r.Plan;$null=Decision23 $r;Equal23 (Get-PestoPlanFingerprint $r.Plan) $hash;Equal23 $r.JoinEvidence.BoundObjectGuid ''}
Case23 'Avant prévu observé montre aussi la cible de jonction' {$r=Join23;$rows=@(Get-PestoObservationComparison $r (Observation23));Equal23 ($rows|Where-Object Champ -eq 'Nom Windows actif').Prevu 'P111301AA765001';Equal23 ($rows|Where-Object Champ -eq 'Emplacement AD').Prevu 'OU=AA,DC=test,DC=invalid'}
Case23 'Une lecture de statut seule ne valide plus AD' {$r=Legacy23;$l=Local23;$l.PartOfDomain=$true;$l.DomainRole=1;$l.Domain=$r.Domain;$l.Computer=$r.NewName;$l.ActiveName=$r.NewName;$l.ConfiguredName=$r.NewName;$l.BootUtc='2026-01-02T08:00:00Z';$l|Add-Member SecureChannel $true;$d=Get-PestoJoinReceiptDecision $r $l 'test.invalid';Assert23 (-not $d.Blocked);Equal23 $d.Phase 'ReadyToObserve'}
Case23 'Tous les nouveaux exports écartent le secret sentinelle' {$s=ConvertTo-PestoObservationSnapshot (Observation23);Assert23 (($s|ConvertTo-Json -Depth 9) -notmatch 'SECRET-SENTINEL-23');$r=Join23;Assert23 (($r|ConvertTo-Json -Depth 9) -notmatch 'Account|Password|Credential')}
Case23 'Parcours primaire commence par lire une cible valide' {Equal23 (Get-PestoPrimaryStep -Computer SOURCE).Action 'Read'}
Case23 'Parcours primaire refuse un nom vide' {Assert23 (-not (Get-PestoPrimaryStep -Computer '').Enabled)}
Case23 'Parcours primaire prépare sans mutation un formulaire incomplet' {Equal23 (Get-PestoPrimaryStep -Computer SOURCE -Loaded $true).Action 'Prepare'}
Case23 'Parcours primaire conserve le contrôle puis confirmation' {$s=Get-PestoPrimaryStep -Computer SOURCE -Loaded $true -FormReady $true -Rename $true;Equal23 $s.Action 'Execute';Assert23 ($s.Label -match 'Vérifier')}
Case23 'Reprise primaire annonce uniquement le déplacement restant' {$s=Get-PestoPrimaryStep -Computer SOURCE -ResumeMove $true;Equal23 $s.Action 'Execute';Assert23 ($s.Label -match 'seulement')}
Case23 'Busy ou verrou restent prioritaires devant un plan prêt' {foreach($mode in @('Busy','Blocked')){$args=@{Computer='SOURCE';Loaded=$true;FormReady=$true};$args[$mode]=$true;Assert23 (-not (Get-PestoPrimaryStep @args).Enabled)}}
Case23 'Consultation permet la lecture mais pas exécution' {Equal23 (Get-PestoPrimaryStep -Computer SOURCE -ReadOnly $true).Action 'Read';Assert23 (-not (Get-PestoPrimaryStep -Computer SOURCE -ReadOnly $true -Loaded $true -FormReady $true).Enabled)}
Case23 'Instrumentation bornée à 200 échantillons' {$script:PestoPerformance=$null;for($i=0;$i -lt 205;$i++){Add-PestoPerformanceSample -Name TestRead -Milliseconds $i -Kind Worker};Equal23 $script:PestoPerformance.Count 200;Equal23 $script:PestoPerformance[0].Milliseconds 5}
Case23 'Instrumentation refuse les noms de cible et valeurs négatives' {Throws23 {Add-PestoPerformanceSample -Name 'PC\secret' -Milliseconds 5};Throws23 {Add-PestoPerformanceSample -Name Read -Milliseconds -1}}
Case23 'Résumé calcule moyenne et percentile sans prétendre au succès métier' {$script:PestoPerformance=$null;foreach($v in 1..20){Add-PestoPerformanceSample Read $v -Kind Worker -State Returned -WaitMilliseconds 1};$r=@(Get-PestoPerformanceSummary @($script:PestoPerformance))[0];Equal23 $r.P95Ms 19;Equal23 $r.MoyenneMs 10.5;Equal23 $r.Retours 20}
Case23 'Délais erreurs et annulations restent distincts' {$script:PestoPerformance=$null;foreach($state in @('Returned','Faulted','Timeout','Cancelled')){Add-PestoPerformanceSample Read 5 -Kind Worker -State $state};$r=@(Get-PestoPerformanceSummary @($script:PestoPerformance))[0];Equal23 $r.Erreurs 1;Equal23 $r.Delais 1;Equal23 $r.Annulations 1}
Case23 'Mesures worker et calcul ne sont pas mélangées' {$script:PestoPerformance=$null;Add-PestoPerformanceSample Read 5 -Kind Worker;Add-PestoPerformanceSample Read 10 -Kind Computation;Equal23 @(Get-PestoPerformanceSummary @($script:PestoPerformance)).Count 2}
Case23 'Lecture réelle du schéma 3 dans un fichier fixture' {
 $folder=Join-Path ([IO.Path]::GetTempPath()) ('Pesto23-read-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($folder)
 try{$r=Join23;$path=Join-Path $folder ($r.OperationId+'.json');[IO.File]::WriteAllText($path,($r|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false));$read=Read-PestoIntervention $path;Equal23 $read.JoinEvidence.NativeStatus 'Unknown';$r.JoinEvidence.MachineId='other';[IO.File]::WriteAllText($path,($r|ConvertTo-Json -Depth 10));Throws23 {Read-PestoIntervention $path}}finally{Remove-Item -LiteralPath $folder -Recurse -Force}
}
if($Wpf){
 Add-Type -AssemblyName PresentationFramework
 Case23 'Vrais XAML incluent le bouton de jonction accessible' {
  $shell=[Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText((Join-Path $root 'wad/Pesto-Shell.xaml')))
  $join=[Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText((Join-Path $root 'wad/Pesto-Join.xaml')))
  try{$button=$join.FindName('JnReview');Assert23 ($null -ne $button);Assert23 ([string]$button.ToolTip).Length;Assert23 ([Windows.Automation.AutomationProperties]::GetName($button)).Length}finally{$shell.Close()}
 }
 Case23 'Vrai bouton primaire conserve sa zone tactile et absence de défaut Entrée' {
  $shell=[Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText((Join-Path $root 'wad/Pesto-Shell.xaml')))
  try{$b=$shell.FindName('SuiteDirectRun');Assert23 ($b.MinHeight -ge 42);Assert23 (-not $b.IsDefault);Assert23 ([string]$b.ToolTip).Length}finally{$shell.Close()}
 }
}else{$results.Add([pscustomobject]@{Name='WPF RC23';State='SKIP';Error='Passer -Wpf sous Windows PowerShell -STA.'})}
$failed=@($results|Where-Object State -eq FAIL).Count;$skip=@($results|Where-Object State -eq SKIP).Count
[pscustomobject]@{Version='1.0';Utc=[DateTime]::UtcNow.ToString('o');PowerShell=[string]$PSVersionTable.PSVersion;Failed=$failed;Skipped=$skip;NoLiveAD=$true;NoUAC=$true;Checks=$results.ToArray()}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $ReportPath -Encoding UTF8
Write-Host ('Rapport : '+$ReportPath)
if($failed -or $skip){exit 1}else{exit 0}
