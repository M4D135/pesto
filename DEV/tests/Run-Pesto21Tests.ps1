#requires -Version 5.1
[CmdletBinding()]
param([switch]$Wpf,[string]$ReportPath=(Join-Path ([IO.Path]::GetTempPath()) ('Pesto-RC21-'+[guid]::NewGuid().ToString('N')+'.json')))
# Import des définitions AST uniquement. Aucun démarrage, aucun domaine, aucune UAC.
$ErrorActionPreference='Stop';Set-StrictMode -Off
if($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){throw 'Recette cible : Windows PowerShell 5.1 sous Windows.'}
$root=Split-Path -Parent $PSScriptRoot
$results=[Collections.Generic.List[object]]::new();$astFiles=[Collections.Generic.List[string]]::new()
$fixtures=Join-Path ([IO.Path]::GetTempPath()) ('Pesto21-fixtures-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixtures)
foreach($file in Get-ChildItem -LiteralPath (Join-Path $root 'wad') -Filter 'Pesto-*.ps1' -File){
 $tokens=$null;$errors=$null
 $ast=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
 if($errors.Count){throw ($file.Name+': '+(($errors|ForEach-Object{$_.Message}) -join '; '))}
 $astFiles.Add($file.Name)
 foreach($node in $ast.EndBlock.Statements){if($node -is [Management.Automation.Language.FunctionDefinitionAst]){. ([scriptblock]::Create($node.Extent.Text))}}
}
# Même initialisation vérifiée que le moteur pour le tirage natif.
Initialize-PestoCommon -Root (Join-Path $root 'wad')
function Assert-21 {param($Condition,[string]$Message='Condition non satisfaite');if(-not $Condition){throw $Message}}
function Equal-21 {param($Actual,$Expected);if($Actual -cne $Expected){throw ('Attendu [{0}], obtenu [{1}]' -f $Expected,$Actual)}}
function Throws-21 {param([scriptblock]$Body);$thrown=$false;try{& $Body|Out-Null}catch{$thrown=$true};Assert-21 $thrown 'Un refus était attendu.'}
function Case-21 {param([string]$Name,[scriptblock]$Body);try{& $Body;$results.Add([pscustomobject]@{Name=$Name;State='PASS';Message=''});Write-Host ('PASS '+$Name)}catch{$results.Add([pscustomobject]@{Name=$Name;State='FAIL';Message=$_.Exception.Message});Write-Host ('FAIL '+$Name+' : '+$_.Exception.Message)}}
# Toute tentative d'accès au domaine ou à un vrai magasin pendant ce banc est un échec.
function Get-ADComputer {throw 'Accès AD interdit dans cette fixture.'}
function Set-ADObject {throw 'Mutation AD interdite dans cette fixture.'}
function Add-Computer {throw 'Jonction interdite dans cette fixture.'}
function Get-PestoAppearanceValue {throw 'Préférences réelles interdites dans cette fixture.'}
function Set-PestoAppearanceValue {throw 'Préférences réelles interdites dans cette fixture.'}
function Show-MsgError {param($Message);throw $Message}
function Add-LogLine {param($Message,$Kind)}
$script:GUI=$true;$script:SIM=$true;$script:PestoReadOnly=$false;$script:Pesto_VERSION='1.0'
$script:DOMAINE='test.invalid';$script:PREFIXE='111301';$script:CFG=[pscustomobject]@{POLICY=$null;TAGS=@();NameCatalogue=@()}
function New-Plan21 {
 [pscustomobject]@{Nom_du_PC='P111301AA765001';Nouveau_Nom='P111301BB765002';Objet_GUID='11111111-1111-1111-1111-111111111111';OU_Actuelle='OU=AA,DC=test,DC=invalid';OU_Destination='OU=BB,DC=test,DC=invalid';TargetOUGuid='22222222-2222-2222-2222-222222222222';Domain='test.invalid';DC='dc.test.invalid';ConfigStamp=('a'*64);Renommer=$true;Deplacer=$true;Reboot=$false}
}
function New-Draft21 {
 [pscustomobject]@{Schema=1;Domain='test.invalid';Nom_du_PC='P111301AA765001';Nouveau_Nom='P111301BB765002';Renommer=$true;Deplacer=$true;Objet_GUID='11111111-1111-1111-1111-111111111111'}
}
function New-Names21 {
 [pscustomobject]@{Generation=1;RandomEnabled=$false;Computers=@([pscustomobject]@{Name='P111301AA765001'});Prefix='111301';Types=@('P');Sites=@('AA');Teams=@('765');Status='Tous';Search='';ShowAll=$true;Buffer=5;PageSize=250;Offset=0;MaxRows=250;ReservedNames=@('P111301AA765002');OwnReservations=@();QueueReservations=@('P111301AA765002');CachedIndex=$null;Cancellation=$null;Strategy='FirstGap';InventoryUtc='2026-10-02T00:00:00Z';Progress=[hashtable]::Synchronized(@{})}
}
Case-21 'Le parseur cible accepte chaque module applicatif' {Assert-21 ($astFiles.Count -ge 23)}
Case-21 'Nommage aller-retour sur 5 994 combinaisons' {
 foreach($type in @('P','S','V')){foreach($site in @('AA','ZZ')){for($n=1;$n -le 999;$n++){$name=New-PestoComputerName $type '111301' $site 'A01' $n;$parts=ConvertTo-PestoNameParts $name '111301';Assert-21 $parts;Equal-21 $parts.Number $n;Equal-21 $parts.Name $name}}}
}
Case-21 'Nommage : bornes et préfixe invalides' {foreach($n in @(0,1000,-1)){Throws-21 {New-PestoComputerName P '111301' AA 765 $n}};Throws-21 {New-PestoComputerName P '11130X' AA 765 1}}
Case-21 'Analyse refuse noms vides, 000 et autres conventions' {foreach($n in @('','X111301AA765001','P111301AA765000','P11130XAA765001','P111301A1765001')){Assert-21 ($null -eq (ConvertTo-PestoNameParts $n))}}
Case-21 'Analyse normalise la casse sans inventer le site' {Equal-21 (ConvertTo-PestoNameParts 'p111301aa765001').Name 'P111301AA765001'}
Case-21 'Empreinte canonique indépendante de l’’ordre des propriétés' {$a=[ordered]@{B=2;A=@('x','y')};$b=[ordered]@{A=@('x','y');B=2};Equal-21 (Get-PestoStableHash $a) (Get-PestoStableHash $b)}
Case-21 'Empreinte distingue ordre d’’un tableau et booléen chaîne' {Assert-21 ((Get-PestoStableHash @('x','y')) -cne (Get-PestoStableHash @('y','x')));Assert-21 ((Get-PestoStableHash $true) -cne (Get-PestoStableHash 'true'))}
Case-21 'Plan identique accepté' {$p=New-Plan21;Assert-PestoConfirmedPlan $p (Get-PestoPlanFingerprint $p) $p.ConfigStamp}
Case-21 'Plan modifié après confirmation refusé' {$p=New-Plan21;$hash=Get-PestoPlanFingerprint $p;$p.Nouveau_Nom='P111301BB765003';Throws-21 {Assert-PestoConfirmedPlan $p $hash ('a'*64)}}
Case-21 'Changement de politique invalide la confirmation' {$p=New-Plan21;Throws-21 {Assert-PestoConfirmedPlan $p (Get-PestoPlanFingerprint $p) ('b'*64)}}
Case-21 'Booléen chaîne dans un plan refusé' {$p=New-Plan21;$p.Reboot='false';Throws-21 {Get-PestoPlanFingerprint $p}}
Case-21 'Brouillon sans autorisation ni redémarrage' {$d=ConvertTo-PestoDraft (New-Draft21);Assert-21 (-not $d.PSObject.Properties['Reboot']);Assert-21 (-not $d.PSObject.Properties['Authorized'])}
Case-21 'Brouillon refuse tous les champs sensibles' {foreach($key in @('Reboot','Credential','Password','Checked','Authorized','ScriptPath','Command')){$d=New-Draft21;$d|Add-Member $key 'sentinelle';Throws-21 {ConvertTo-PestoDraft $d}}}
Case-21 'Brouillon refuse fausse identité et booléens textuels' {$d=New-Draft21;$d.Objet_GUID='bad';Throws-21 {ConvertTo-PestoDraft $d};$d=New-Draft21;$d.Renommer='true';Throws-21 {ConvertTo-PestoDraft $d}}
Case-21 'Brouillon borné et sans caractères de contrôle' {$d=New-Draft21;$d.Nom_du_PC=('x'*257);Throws-21 {ConvertTo-PestoDraft $d};$d.Nom_du_PC="a`nb";Throws-21 {ConvertTo-PestoDraft $d}}
Case-21 'Résultats mal typés ne deviennent jamais un succès' {foreach($x in @($null,'0',[long]0,[DBNull]::Value,@(20))){Equal-21 (Get-PestoOutcome $x) 'Uncertain'}}
Case-21 'Résultats des commandes différenciés' {Equal-21 (Get-PestoOutcome 96) 'NotStarted';Equal-21 (Get-PestoOutcome 20) 'PendingRestart';Equal-21 (Get-PestoOutcome 30) 'Verified';Equal-21 (Get-PestoOutcome 21 -PartialEffect $true) 'Partial';Equal-21 (Get-PestoOutcome 20 -TimedOut $true) 'Uncertain'}
Case-21 'Contrôle ancien, futur ou autre plan non frais' {$r=[pscustomobject]@{Precontrole='VÉRIFIÉ';Controle_Signature='x';Controle_Utc=[DateTimeOffset]::UtcNow.AddMinutes(-4).ToString('o');Deplacer=$false};Assert-21 (-not(Test-PestoFreshCheck $r x));$r.Controle_Utc=[DateTimeOffset]::UtcNow.AddMinutes(1).ToString('o');Assert-21 (-not(Test-PestoFreshCheck $r x));$r.Controle_Utc=[DateTimeOffset]::UtcNow.ToString('o');Assert-21 (Test-PestoFreshCheck $r x);Assert-21 (-not(Test-PestoFreshCheck $r y))}
Case-21 'Politiques par défaut sûres' {$p=ConvertTo-PestoPolicy $null;Assert-21 (-not $p.AllowPasswordTaskFallback);Assert-21 (-not $p.AllowPrecreatedJoin);Equal-21 $p.MaxReaders 4}
Case-21 'Politique refuse booléens textuels et clés inconnues' {Throws-21 {ConvertTo-PestoPolicy ([pscustomobject]@{Schema=1;AllowPrecreatedJoin='true'})};Throws-21 {ConvertTo-PestoPolicy ([pscustomobject]@{Schema=1;Command='cmd.exe'})}}
Case-21 'Politique refuse bornes et coordination sans chemin' {Throws-21 {ConvertTo-PestoPolicy ([pscustomobject]@{Schema=1;MaxReaders=9})};Throws-21 {ConvertTo-PestoPolicy ([pscustomobject]@{Schema=1;CoordinationRequired=$true})}}
Case-21 'ODJ reste desactive par defaut et exige activation explicite' {Assert-21 (-not (ConvertTo-PestoPolicy $null).AllowOfflineJoin);Assert-21 (ConvertTo-PestoPolicy ([pscustomobject]@{Schema=1;AllowOfflineJoin=$true})).AllowOfflineJoin}
Case-21 'Consultation bloque avant même la lecture AD de la politique' {$script:PestoReadOnly=$true;try{Throws-21 {Assert-PestoOperationPolicy (New-Plan21) $null}}finally{$script:PestoReadOnly=$false}}
Case-21 'Exclusion de nom bloque avant transport' {Throws-21 {Assert-PestoOperationPolicy (New-Plan21) ([pscustomobject]@{Schema=1;ExcludedNames=@('P111301AA*')})}}
Case-21 'Clés de coordination stables pour la même cible' {$p=New-Plan21;$a=Get-PestoCoordinationKeys $p;$p.Domain='TEST.INVALID';$b=Get-PestoCoordinationKeys $p;Equal-21 ($a -join ',') ($b -join ',');Equal-21 $a.Count 3}
Case-21 'Coordination sans infrastructure n’’invente pas un partage' {$l=Enter-PestoCoordination (New-Plan21) ('1'*32) $null;Assert-21 (-not $l.Enabled)}
Case-21 'Coordination arbitrée par création exclusive, pas par expiration' {
 $dir=Join-Path $fixtures 'coord';[void][IO.Directory]::CreateDirectory((Join-Path $dir 'locks'))
 [IO.File]::WriteAllText((Join-Path $dir 'pesto-coordination.json'),'{"Schema":1,"Domain":"test.invalid","Purpose":"PestoCoordination"}')
 $policy=[pscustomobject]@{Schema=1;CoordinationRoot=$dir;CoordinationRequired=$true};$plan=New-Plan21
 $lease=Enter-PestoCoordination $plan ('1'*32) $policy
 Throws-21 {Enter-PestoCoordination $plan ('2'*32) $policy}
 $receipt=[pscustomobject]@{Coordination=$lease;Phase='Uncertain';Plan=$plan;OperationId=('1'*32)}
 Exit-PestoCoordination $receipt $policy;Equal-21 @(Get-ChildItem (Join-Path $dir 'locks')).Count 3
 $receipt.Phase='Verified';Exit-PestoCoordination $receipt $policy;Equal-21 @(Get-ChildItem (Join-Path $dir 'locks')).Count 0
}
Case-21 'Deux cibles sans noms communs ont des clés distinctes' {$a=New-Plan21;$b=New-Plan21;$b.Objet_GUID='33333333-3333-3333-3333-333333333333';$b.Nom_du_PC='S111301CC765100';$b.Nouveau_Nom='S111301DD765101';$ka=Get-PestoCoordinationKeys $a;$kb=Get-PestoCoordinationKeys $b;Assert-21 (-not @($ka|Where-Object{$_ -in $kb}).Count)}
Case-21 'Index réutilisé sans relecture des postes' {$q=New-Names21;$a=Invoke-PestoBuildNamesView $q;$q.CachedIndex=$a.ADIndex;$q.Computers=@([pscustomobject]@{Name='P111301AA765999'});$b=Invoke-PestoBuildNamesView $q;Equal-21 $b.ReadCount 0;Assert-21 (-not $b.IndexBuilt);Assert-21 (-not $b.ADIndex['P111301AA765'].ContainsKey(999))}
Case-21 'Pagination ne matérialise que la page' {$q=New-Names21;$r=Invoke-PestoBuildNamesView $q;Equal-21 $r.Rows.Count 250;Equal-21 $r.Total 999;$q.Offset=750;$r=Invoke-PestoBuildNamesView $q;Equal-21 $r.Rows.Count 249;Equal-21 $r.Rows[-1].Num '999';Assert-21 (-not $r.HasNext)}
Case-21 'Cinq propositions maximum, déjà prises exclues' {$r=Invoke-PestoBuildNamesView (New-Names21);Equal-21 $r.Suggestions.Count 5;Equal-21 $r.Suggestions[0].Num '003'}
Case-21 'Propositions disponibles avec les deux types sélectionnés' {$q=New-Names21;$q.Types=@('P','S');$r=Invoke-PestoBuildNamesView $q;Equal-21 $r.Suggestions.Count 5;Equal-21 $r.Total 1998}
Case-21 'Occupé AD et préparé dans Pesto sont distincts' {$q=New-Names21;$r=Invoke-PestoBuildNamesView $q;Equal-21 $r.Rows[0].Statut 'Occupé dans AD';Equal-21 $r.Rows[1].Statut 'Préparé dans la file';Equal-21 $r.Prepared 1;Equal-21 $r.Occupied 1}
Case-21 'Réservation personnelle ne masque pas une réservation de file' {$q=New-Names21;$q.OwnReservations=@('P111301AA765002');$r=Invoke-PestoBuildNamesView $q;Assert-21 (-not $r.Rows[1].OwnReservation);$q.QueueReservations=@();$r=Invoke-PestoBuildNamesView $q;Assert-21 $r.Rows[1].OwnReservation}
Case-21 'Stratégies premier trou et après la séquence' {$q=New-Names21;$q.Computers=@([pscustomobject]@{Name='P111301AA765010'});$q.Status='Disponibles';$r=Invoke-PestoBuildNamesView $q;Equal-21 $r.Rows[0].Num '001';$q.Strategy='AfterLast';$r=Invoke-PestoBuildNamesView $q;Equal-21 $r.Rows[0].Num '011'}
Case-21 'Calcul remplacé annulé coopérativement' {$q=New-Names21;$q.Cancellation=[hashtable]::Synchronized(@{Cancelled=$true});Throws-21 {Invoke-PestoBuildNamesView $q}}
Case-21 'Taille et décalage de page bornés' {$q=New-Names21;$q.PageSize=501;Throws-21 {Invoke-PestoBuildNamesView $q};$q.PageSize=250;$q.Offset=-1;Throws-21 {Invoke-PestoBuildNamesView $q}}
Case-21 'Progression déterminée seulement avec dénominateur connu' {$q=New-Names21;$r=Invoke-PestoBuildNamesView $q;Equal-21 $q.Progress.State.Total 999;Equal-21 $q.Progress.State.Count 999}
Case-21 'Sites sans postes présents depuis la configuration' {$script:CFG=[pscustomobject]@{TAGS=@([pscustomobject]@{Tag='ZZ';Site='Vide-ZZ'});NameCatalogue=@([pscustomobject]@{Site='ZZ';Service='A01'})};$script:ComputersNoms=@();Build-NmIndex;Assert-21 ('ZZ' -in $script:NmSites);Assert-21 ('A01' -in $script:NmEquipes)}
Case-21 'Préparation personnelle sans accès au registre en simulation' {Save-PestoNameReservations @('P111301AA765020','P111301AA765021');$names=@(Read-PestoNameReservations);Equal-21 $names.Count 2;Assert-21 ($script:PestoNameReservationMemory -notmatch 'Password|Credential')}
Case-21 'Préparation personnelle d’’un autre domaine non appliquée' {$old=$script:DOMAINE;$script:DOMAINE='other.invalid';try{Equal-21 @(Read-PestoNameReservations).Count 0}finally{$script:DOMAINE=$old}}
Case-21 'Favori ancien migré uniquement dans la présentation' {$v=[pscustomobject]@{Schema=1;Domain='test.invalid';ConfigStamp=('a'*64);Org='Test';Site='Vide-ZZ';Service='765';Type='Portable'};$script:PestoPrepMemory=$v|ConvertTo-Json;Equal-21 @(Read-PestoPreparations).Count 1;Equal-21 (@(Read-PestoPreparations)[0].Name) 'Mon favori'}
Case-21 'Favoris multiples, noms uniques et 20 maximum' {$v=[pscustomobject]@{Schema=1;Domain='test.invalid';ConfigStamp=('a'*64);Org='Test';Site='Vide-ZZ';Service='765';Type='Portable'};$entry=[pscustomobject]@{Name='Même';Value=$v};$script:PestoPrepMemory=[pscustomobject]@{Schema=2;Favorites=@($entry,$entry)}|ConvertTo-Json -Depth 5;Throws-21 {Read-PestoPreparations}}
Case-21 'Favori refuse un champ mot de passe' {$v=[pscustomobject]@{Schema=1;Domain='test.invalid';ConfigStamp=('a'*64);Org='Test';Site='Vide-ZZ';Service='765';Type='Portable';Password='PESTO_SENTINEL_21'};Throws-21 {ConvertTo-PestoPreparation $v}}
Case-21 'Timeline bornée garde un ordre croissant' {$r=[pscustomobject]@{Sequence=0;Timeline=@()};for($i=0;$i -lt 120;$i++){Add-PestoInterventionEvent $r 'Lecture' 'Test'};Equal-21 $r.Sequence 120;Equal-21 $r.Timeline.Count 96;Equal-21 $r.Timeline[-1].Sequence 120}
Case-21 'Une cible incertaine ne bloque pas une autre identité' {$a=New-Plan21;$b=New-Plan21;$b.Objet_GUID='33333333-3333-3333-3333-333333333333';$b.Nom_du_PC='S111301CC765100';$b.Nouveau_Nom='S111301DD765101';$e=[pscustomobject]@{Phase='Uncertain';Plan=$a};Assert-21 (Test-PestoInterventionConflict $e $a);Assert-21 (-not(Test-PestoInterventionConflict $e $b))}
Case-21 'Ancien checkpoint importé sans transformer une incertitude en succès' {
 $row=New-Plan21;$row|Add-Member Statut 'INCERTAIN';$row|Add-Member Operation_ID ('1'*32)
 $data=[pscustomobject]@{Schema=1;Domain='test.invalid';MachineId='FIXTURE';Rows=@($row)}
 $r=@(ConvertFrom-PestoLegacyState $data 'test.invalid' FIXTURE ('a'*64));Equal-21 $r.Count 1;Equal-21 $r[0].Phase 'Uncertain';Assert-21 (-not $r[0].Plan.Reboot)
 Throws-21 {ConvertFrom-PestoLegacyState $data 'other.invalid' FIXTURE ('a'*64)}
}
Case-21 'Import historique sans GUID refusé' {$row=New-Plan21;$row.Objet_GUID='';$row|Add-Member Statut 'INCERTAIN';$data=[pscustomobject]@{Schema=1;Domain='test.invalid';MachineId='FIXTURE';Rows=@($row)};Throws-21 {ConvertFrom-PestoLegacyState $data 'test.invalid' FIXTURE ('a'*64)}}
Case-21 'Réessai de lecture transitoire borné' {$script:retry21=0;$value=Invoke-PestoReadRetry -Attempts 2 -DelayMs 0 -Read {$script:retry21++;if($script:retry21 -eq 1){throw [ComponentModel.Win32Exception]::new(1722)};return 'read-ok'};Equal-21 $value 'read-ok';Equal-21 $script:retry21 2}
Case-21 'Refus d’’authentification jamais réessayé' {$script:retry21=0;Throws-21 {Invoke-PestoReadRetry -Attempts 3 -DelayMs 0 -Read {$script:retry21++;throw [ComponentModel.Win32Exception]::new(1326)}};Equal-21 $script:retry21 1}
Case-21 'Masquage des motifs sensibles dans les traces' {$s=Protect-PestoLogText 'pwd=PESTO_SENTINEL_21 password="secret21"';Assert-21 ($s -notmatch 'PESTO_SENTINEL_21|secret21')}
Case-21 'Diagnostic natif sépare refus réseau, identité et Netjoin' {Assert-21 ((Get-PestoNativeGuidance 2732) -match 'Netjoin');Assert-21 ((Get-PestoNativeGuidance 1722) -match 'RPC');Assert-21 ((Get-PestoNativeGuidance 5) -match 'délégation')}
Case-21 'Aucune checklist ne confond santé locale et SSO utilisateur' {$p=New-Plan21;$obs=[pscustomobject]@{Windows=$null;AD=$null;Health=$null;ObservedUtc=''};$r=Get-PestoPostconditionChecklist $p $obs $null;Assert-21 (@($r|Where-Object{$_.Etat -eq 'Inconnu'}).Count -gt 0);Assert-21 (($r.Source -join ' ') -match 'pas SSO')}
Case-21 'Comparaison d’’interventions donne des différences, pas une causalité' {$a=[pscustomobject]@{Version='a';Plan=(New-Plan21)};$b=[pscustomobject]@{Version='b';Plan=(New-Plan21)};$r=@(Compare-PestoInterventions $a $b);Equal-21 $r.Count 1;Assert-21 ($r[0].Conclusion -match 'pas une preuve')}
Case-21 'Mesures locales bornées à 200 échantillons' {$script:PestoPerformance=$null;for($i=0;$i -lt 300;$i++){Add-PestoPerformanceSample Test $i 1};Equal-21 $script:PestoPerformance.Count 200}
Case-21 'Vraie compilation C# du writer et barrière d’’ordre' {
 . (Join-Path (Join-Path $root 'wad') 'Pesto-Common.ps1');Initialize-PestoRuntimeTypes -Root (Join-Path $root 'wad')
 $p=Join-Path $fixtures 'audit.log';[IO.File]::WriteAllText($p,'');$writer=[Pesto.Runtime.AsyncAuditWriter]::new($p,2048)
 try{for($i=0;$i -lt 100;$i++){Assert-21 ($writer.TryWrite(($i.ToString('D3')+"`n")))};Assert-21 ($writer.Flush(5000));Equal-21 $writer.Written 100;Equal-21 $writer.Dropped 0;Equal-21 ([IO.File]::ReadAllLines($p).Count) 100}finally{[void]$writer.Close(5000)}
 Assert-21 (-not $writer.TryWrite('late'))
}
Case-21 'Erreur disque du writer visible, pas ignorée' {
 $p=Join-Path $fixtures 'removed.log';[IO.File]::WriteAllText($p,'');$writer=[Pesto.Runtime.AsyncAuditWriter]::new($p,64)
 try{
  [IO.File]::Delete($p)
  Assert-21 ($writer.TryWrite('fixture')) 'La trace doit etre acceptee avant le constat de panne disque.'
  Assert-21 (-not $writer.Flush(5000)) 'La barriere doit signaler la panne disque.'
  # Error est publie avant le compteur Dropped ; attendre la fin du thread, pas un instant intermediaire.
  Assert-21 (-not $writer.Close(5000)) 'La fermeture ne doit pas masquer la panne disque.'
  Assert-21 $writer.Error 'Le diagnostic disque doit rester disponible.'
  Assert-21 ($writer.Dropped -gt 0) 'La trace perdue doit etre comptee apres la fin du writer.'
 }finally{[void]$writer.Close(5000)}
}

Case-21 'Reçu central relisible avec plan figé, timeline et coordination' {
 $id=[Guid]::NewGuid().ToString('N');$p=New-Plan21
 $receipt=[pscustomobject]@{Schema=1;Version='17.0-RC23';OperationId=$id;Plan=$p;Phase='Uncertain';Entra='Skipped';Protection='NotChanged';Rename='Requested';Move='NotRequested';ResultCode=97;PlanFingerprint=(Get-PestoPlanFingerprint $p);Sequence=1;Timeline=@([pscustomobject]@{Sequence=1;Utc=[DateTime]::UtcNow.ToString('o');Stage='Rename';State='Requested'});Coordination=[pscustomobject]@{Enabled=$true;Keys=(Get-PestoCoordinationKeys $p);Owner=$id;ResumeFrom=('1'*32)};Tasks=@()}
 $path=Join-Path $fixtures ($id+'.json');[IO.File]::WriteAllText($path,($receipt|ConvertTo-Json -Depth 8))
 $read=Read-PestoIntervention $path;Equal-21 $read.OperationId $id;Equal-21 $read.Coordination.ResumeFrom ('1'*32)
 $receipt.Plan.Nouveau_Nom='P111301BB765999';[IO.File]::WriteAllText($path,($receipt|ConvertTo-Json -Depth 8));Throws-21 {Read-PestoIntervention $path}
}
Case-21 'Reçu refuse un champ inconnu même si le JSON est valide' {
 $id=[Guid]::NewGuid().ToString('N');$p=New-Plan21
 $r=[pscustomobject]@{Schema=1;OperationId=$id;Plan=$p;Phase='Uncertain';Entra='Skipped';Protection='NotChanged';Rename='Requested';Move='NotRequested';ResultCode=97;Script='cmd.exe'}
 $path=Join-Path $fixtures ($id+'.json');[IO.File]::WriteAllText($path,($r|ConvertTo-Json -Depth 8));Throws-21 {Read-PestoIntervention $path}
}

if($Wpf){
 Case-21 'Vrais XAML et contrôles RC21 accessibles' {
  if([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA'){throw '-STA requis.'}
  Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
  $w=[Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText((Join-Path $root 'wad\Pesto-Shell.xaml')))
  try{foreach($name in @('NmPrevPage','NmNextPage','NmStrategy','NmSuggestions','PrepList','PrepName','HomeInterventions')){$control=$w.FindName($name);Assert-21 $control $name;Assert-21 $control.ToolTip ('Aide absente : '+$name)};$w.Measure([Windows.Size]::new(1000,720));$w.Arrange([Windows.Rect]::new(0,0,1000,720));$w.UpdateLayout()}finally{$w.Close()}
 }

 Case-21 'Panneau Interventions hébergé : fermeture et état du parent restaurés' {
  function Invoke-Fixture21HostedTick {
   $script:Fixture21Ticks++
   if($script:Fixture21Child -and $script:Fixture21Child.Tag){
    if($script:Fixture21Ticks -eq 1){$script:Fixture21Child.Close()}
    if($script:Fixture21Ticks -gt 10){$script:Fixture21TimedOut=$true;$script:Fixture21Child.Tag.Frame.Continue=$false}
   }
  }
  $savedWin=$script:Win;$script:Win=[Windows.Window]::new();$script:Win.Width=800;$script:Win.Height=600
  $script:Win.Content=[Windows.Controls.Grid]::new();$button=[Windows.Controls.Button]::new();$button.Content='fixture';[void]$script:Win.Content.Children.Add($button)
  $script:Fixture21Child=[Windows.Window]::new();$script:Fixture21Child.Content=[Windows.Controls.Grid]::new()
  $script:Fixture21Ticks=0;$script:Fixture21TimedOut=$false
  $timer=[Windows.Threading.DispatcherTimer]::new();$timer.Interval=[TimeSpan]::FromMilliseconds(100);$handler=[EventHandler]${function:Invoke-Fixture21HostedTick};$timer.Add_Tick($handler)
  try{$script:Win.Show();$timer.Start();Show-PestoHostedWindow $script:Fixture21Child;Assert-21 (-not $script:Fixture21TimedOut);Equal-21 $script:Win.Content.Children.Count 1;Assert-21 $button.IsEnabled;Equal-21 $script:PestoPanelStack.Count 0}
  finally{$timer.Stop();$timer.Remove_Tick($handler);$script:Win.Close();$script:Win=$savedWin;$script:Fixture21Child=$null}
 }
}else{$results.Add([pscustomobject]@{Name='Vrais XAML RC21';State='SKIP';Message='Passer -Wpf depuis Windows PowerShell -STA.'})}
$fail=@($results|Where-Object{$_.State -eq 'FAIL'}).Count;$skip=@($results|Where-Object{$_.State -eq 'SKIP'}).Count
[pscustomobject]@{Version='1.0';PowerShell=[string]$PSVersionTable.PSVersion;Utc=[DateTime]::UtcNow.ToString('o');Failed=$fail;Skipped=$skip;NoLiveAD=$true;NoUAC=$true;Fixtures=$fixtures;Checks=$results.ToArray()}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $ReportPath -Encoding UTF8
Write-Host ('Rapport : '+$ReportPath)
if($fail -or $skip){exit 1}else{exit 0}
