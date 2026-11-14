#requires -Version 5.1
[CmdletBinding()]
param([switch]$Wpf,[string]$ReportPath=(Join-Path ([IO.Path]::GetTempPath()) ('Pesto-Names-'+[guid]::NewGuid().ToString('N')+'.json')))
# Définitions uniquement : ni démarrage du moteur, ni AD, ni mutation Windows.
$ErrorActionPreference='Stop';Set-StrictMode -Off
$root=Split-Path $PSScriptRoot -Parent
$results=New-Object 'System.Collections.Generic.List[object]';$defs=@{}
function Assert-Nm {param($Condition,[string]$Message='Condition fausse');if(-not $Condition){throw $Message}}
function Equal-Nm {param($Actual,$Expected);if($Actual -cne $Expected){throw "Attendu [$Expected], obtenu [$Actual]"}}
function Case-Nm {param([string]$Name,[scriptblock]$Body);try{& $Body;$results.Add([pscustomobject]@{Name=$Name;Passed=$true;Error='' });Write-Host ('OK '+$Name)}catch{$results.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message});Write-Host ('KO '+$Name+' : '+$_.Exception.Message)}}
foreach($file in @('Pesto-Core.ps1','Pesto-Directory.ps1','Pesto-Async.ps1','Pesto-Contracts.ps1','Pesto-Policy.ps1','Pesto-ManagedPolicy.ps1','Pesto-Names.ps1','Pesto-Safety.ps1')){
 $tokens=$null;$errors=$null
 $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root ('wad\'+$file)),[ref]$tokens,[ref]$errors)
 if($errors.Count){throw ($file+': '+(($errors|ForEach-Object{$_.Message}) -join '; '))}
 foreach($node in $ast.EndBlock.Statements){if($node -is [Management.Automation.Language.FunctionDefinitionAst]){$defs[$node.Name]=$node.Extent.Text}}
}
foreach($name in @('Test-PestoAsyncMutationName','Complete-PestoWorkerTiming','Invoke-PestoBuildNamesView','Stop-PestoNamesLoadTimer','Update-PestoNamesLoadProgress','Set-PestoNamesViewState','Complete-PestoNamesProjection','Fail-PestoNamesProjection','Update-NameGrid','Set-NmNextButtons','Get-NmUsedMap','Copy-NmName','Export-NameView','Test-PestoAsyncOperationRunning','Stop-PestoAsyncOperation','Start-PestoAsyncOperation','Invoke-PestoAsyncCallback','Invoke-PestoAsyncTimerTick','Build-NmIndex','Populate-NmFilters','ConvertTo-PestoNameParts','ConvertTo-PestoPolicy','Get-PestoManagedPolicy','Merge-PestoManagedPolicy','Assert-PestoClosedObject','Test-PestoPropertyPresent','Add-PestoPerformanceSample','Update-PestoNamesPageControls','Get-PestoSharedNameSettings','Test-PestoNameReservedByOther','Assert-PestoPlainPath','Get-PestoSharedNameRegistrySnapshot','ConvertTo-PestoSharedNameRegistryLines','Get-PestoSharedNameRegistrySource','Complete-PestoSharedNameRegistry')){
 . ([scriptblock]::Create($defs[$name]))
}
. (Join-Path $root 'wad/Pesto-Contracts.ps1')
. (Join-Path $root 'wad/Pesto-Collections.ps1')
. (Join-Path $root 'wad/Pesto-Common.ps1');Initialize-PestoCommon (Join-Path $root 'wad')
# Garder la fusion de politique réelle, avec une lecture GPO fictive sans accès registre.
function Get-PestoManagedPolicy {[pscustomobject]@{Values=[pscustomobject]@{};Configured=$false;Source='fixture'}}
function Add-LogLine {param($Text,$Kind);$script:TestMessages.Add([string]$Text)}
function Write-Log {param($Message,$Level,$ErrorRecord,$Context)}
function Show-MsgError {param($Message,$Title);throw $Message}
function Test-PestoGeneratedComputerName {param($Name);return ($Name -match '^[PSV]111301[A-Z]{2}[A-Z0-9]{3}[0-9]{3}$' -and -not $Name.EndsWith('000'))}
function Read-PestoNameReservations {return @()}
$script:CFG=$null
$script:TestMessages=New-Object 'System.Collections.Generic.List[string]'
function New-NmRequest {
 [pscustomobject]@{Generation=7;Computers=@([pscustomobject]@{Name='P111301AA765001'},[pscustomobject]@{Name='P111301AA765003'});ReservedNames=@('P111301AA765002');Prefix='111301';Types=@('P');Sites=@('AA');Teams=@('765');Status='Disponibles';Search='';ShowAll=$false;Buffer=2;MaxRows=250;PageSize=250;Offset=0;CachedIndex=$null;Cancellation=$null;OwnReservations=@();QueueReservations=@('P111301AA765002');Strategy='FirstGap';InventoryUtc='2026-10-02T12:00:00Z';Progress=[hashtable]::Synchronized(@{})}
}
Case-Nm 'Noms AD et réservations exclus des disponibles' {$r=Invoke-PestoBuildNamesView (New-NmRequest);Equal-Nm ($r.Rows.Nom -join ',') 'P111301AA765004,P111301AA765005';Equal-Nm $r.Available 2}
Case-Nm 'Utilisés distingue les noms occupés des réservations' {$q=New-NmRequest;$q.Status='Utilisés';$r=Invoke-PestoBuildNamesView $q;Equal-Nm ($r.Rows.Nom -join ',') 'P111301AA765001,P111301AA765003';Equal-Nm $r.Available 0}
Case-Nm 'Tous conserve les statuts et le nombre de libres' {$q=New-NmRequest;$q.Status='Tous';$r=Invoke-PestoBuildNamesView $q;Equal-Nm $r.Rows.Count 5;Equal-Nm $r.Rows[3].Statut 'Libre dans l''inventaire';Equal-Nm $r.Available 2}
Case-Nm 'Recherche insensible à la casse' {$q=New-NmRequest;$q.Search='aa765005';$r=Invoke-PestoBuildNamesView $q;Equal-Nm $r.Rows.Count 1;Equal-Nm $r.Rows[0].Num '005'}
Case-Nm 'Un filtre sans résultat rend un tableau vide' {$q=New-NmRequest;$q.Search='XYZ';$r=Invoke-PestoBuildNamesView $q;Assert-Nm ($null -ne $r.Rows);Equal-Nm $r.Rows.Count 0;Equal-Nm $r.Available 0}
Case-Nm 'Une collecte vide ne crée pas de site ou équipe arbitraire' {$q=New-NmRequest;$q.Computers=@();$q.Sites=@();$q.Teams=@();$r=Invoke-PestoBuildNamesView $q;Equal-Nm $r.Rows.Count 0;Equal-Nm $r.ReadCount 0}
Case-Nm 'Noms mal formés, 000 et autres préfixes ignorés' {$q=New-NmRequest;$q.Computers=@([pscustomobject]@{Name='BAD'},[pscustomobject]@{Name='P111301AA765000'},[pscustomobject]@{Name='P222222AA765001'});$q.ReservedNames=@();$r=Invoke-PestoBuildNamesView $q;Equal-Nm ($r.Rows.Num -join ',') '001,002'}
Case-Nm 'Jusqu''à 999 respecte exactement la borne' {$q=New-NmRequest;$q.Computers=@();$q.ReservedNames=@();$q.ShowAll=$true;$r=Invoke-PestoBuildNamesView $q;Equal-Nm $r.Rows.Count 250;Equal-Nm $r.Total 999;Assert-Nm $r.HasNext;$q.Offset=750;$last=Invoke-PestoBuildNamesView $q;Equal-Nm $last.Rows.Count 249;Equal-Nm $last.Rows[-1].Num '999';Assert-Nm (-not $last.HasNext)}
Case-Nm 'Limite d''affichage explicite et comptage non trompeur' {$q=New-NmRequest;$q.ShowAll=$true;$q.PageSize=2;$r=Invoke-PestoBuildNamesView $q;Equal-Nm $r.Rows.Count 2;Assert-Nm $r.HasNext;Assert-Nm (-not $r.Limited);Equal-Nm $r.Available 996;Equal-Nm $r.Total 996}
Case-Nm 'Limite exacte sans résultat supplémentaire non tronquée' {$q=New-NmRequest;$q.PageSize=2;$r=Invoke-PestoBuildNamesView $q;Assert-Nm (-not $r.Limited);Equal-Nm $r.Rows.Count 2}
Case-Nm 'Index AD sans réservation persistée par erreur' {$r=Invoke-PestoBuildNamesView (New-NmRequest);Assert-Nm $r.ADIndex['P111301AA765'].ContainsKey(1);Assert-Nm (-not $r.ADIndex['P111301AA765'].ContainsKey(2))}
Case-Nm 'Types indépendants pour le même site/service' {$q=New-NmRequest;$q.Types=@('S');$r=Invoke-PestoBuildNamesView $q;Equal-Nm ($r.Rows.Nom -join ',') 'S111301AA765001,S111301AA765002'}
Case-Nm 'VM : inventaire, reservation et generation restent distincts de P/S' {$q=New-NmRequest;$q.Types=@('V');$q.Computers=@([pscustomobject]@{Name='V111301AA765001'},[pscustomobject]@{Name='P111301AA765004'});$q.ReservedNames=@('V111301AA765002');$r=Invoke-PestoBuildNamesView $q;Equal-Nm ($r.Rows.Nom -join ',') 'V111301AA765003,V111301AA765004';Equal-Nm $r.Rows[0].Type 'Virtuel';Equal-Nm $r.Total 2}
Case-Nm 'Progression partagée et génération restituée' {$q=New-NmRequest;$q.ShowAll=$true;$r=Invoke-PestoBuildNamesView $q;Equal-Nm $r.Generation 7;Equal-Nm $q.Progress.State.Stage 'Affichage de la page';Equal-Nm $q.Progress.State.Count $r.Examined}
Case-Nm 'Entrées de calcul invalides refusées' {foreach($pair in @(@('Prefix','bad'),@('PageSize',-1),@('PageSize',501),@('Types',@('X')),@('Sites',@('!!!')))){$q=New-NmRequest;$q.($pair[0])=$pair[1];$threw=$false;try{Invoke-PestoBuildNamesView $q|Out-Null}catch{$threw=$true};Assert-Nm $threw ('Rejet attendu pour '+$pair[0])}}

Case-Nm 'Tirage sur 001-999 indépendant de la marge et de la page' {
 $q=New-NmRequest;$q|Add-Member NoteProperty RandomIndex {param($Count) return 0};$q.PageSize=1
 $r=Invoke-PestoBuildNamesView $q
 Equal-Nm $r.CandidateCount 996;Equal-Nm $r.Rows.Count 1
 Assert-Nm ('P111301AA765999' -in @($r.Suggestions.Nom));Equal-Nm $r.ByType.P.Nom 'P111301AA765999'
 Equal-Nm (@($r.Suggestions.Nom|Sort-Object -Unique).Count) 5
 foreach($name in $r.Suggestions.Nom){Assert-Nm ($name -notin @('P111301AA765001','P111301AA765002','P111301AA765003'))}
}
Case-Nm 'Chaque bouton tire dans son type actif sur tous les sites et services' {
 $q=New-NmRequest;$q.Types=@('P','S','V','P');$q.Sites=@('AA','BB');$q.Teams=@('765','ABC')
 $r=Invoke-PestoBuildNamesView $q
 Equal-Nm $r.CandidateCount (12*999-3)
 foreach($type in @('P','S','V')){Assert-Nm $r.ByType[$type].Nom.StartsWith($type);Equal-Nm $r.CandidateCountsByType[$type] $(if($type -eq 'P'){3993}else{3996})}
 $q.Types=@('V');$r=Invoke-PestoBuildNamesView $q;Assert-Nm (-not $r.ByType.P);Assert-Nm (-not $r.ByType.S);Assert-Nm $r.ByType.V
}
Case-Nm 'Recherche éloignée trouve un candidat hors marge sans fausse ligne' {
 $q=New-NmRequest;$q.Search='765999';$r=Invoke-PestoBuildNamesView $q
 Equal-Nm $r.Rows.Count 0;Equal-Nm $r.CandidateCount 1;Equal-Nm $r.Suggestions[0].Nom 'P111301AA765999'
}
Case-Nm 'Statuts occupés et réservés ne proposent aucun nom' {
 foreach($status in @('Utilisés','Réservés')){$q=New-NmRequest;$q.Status=$status;$r=Invoke-PestoBuildNamesView $q;Equal-Nm $r.CandidateCount 0;Equal-Nm $r.Suggestions.Count 0;Assert-Nm (-not $r.ByType.P)}
}
Case-Nm 'Séquentiel propose les premiers candidats même avec marge nulle' {
 $q=New-NmRequest;$q.Computers=@();$q.ReservedNames=@();$q.Buffer=0;$q|Add-Member NoteProperty RandomEnabled $false
 $r=Invoke-PestoBuildNamesView $q;Equal-Nm $r.Rows.Count 0;Equal-Nm $r.CandidateCount 999;Equal-Nm ($r.Suggestions.Num -join ',') '001,002,003,004,005';Equal-Nm $r.ByType.P.Num '001'
}
Case-Nm 'Propositions conservées entre pages puis remplacement seulement du nom devenu occupé' {
 $q=New-NmRequest;$q.ShowAll=$true;$r=Invoke-PestoBuildNamesView $q
 $q|Add-Member NoteProperty PreviousSuggestions @($r.Suggestions.Nom)
 $q|Add-Member NoteProperty PreviousByType @{P=$r.ByType.P.Nom}
 $q.Offset=500;$again=Invoke-PestoBuildNamesView $q
 Equal-Nm ($again.Suggestions.Nom -join ',') ($r.Suggestions.Nom -join ',');Equal-Nm $again.ByType.P.Nom $r.ByType.P.Nom
 $lost=$r.Suggestions[0].Nom;$q.ReservedNames+=@($lost);$updated=Invoke-PestoBuildNamesView $q
 Equal-Nm $updated.Suggestions.Count 5;Assert-Nm ($lost -notin @($updated.Suggestions.Nom))
 foreach($name in @($r.Suggestions.Nom|Select-Object -Skip 1)){Assert-Nm ($name -in @($updated.Suggestions.Nom))}
}
Case-Nm 'Le cache AD est réutilisé et les nouvelles réservations restent séparées' {
 $q=New-NmRequest;$r=Invoke-PestoBuildNamesView $q;$q.CachedIndex=$r.ADIndex;$q.ReservedNames+=@('P111301AA765999');$q.Search='999'
 $again=Invoke-PestoBuildNamesView $q;Assert-Nm (-not $again.IndexBuilt);Equal-Nm $again.ReadCount 0;Equal-Nm $again.CandidateCount 0
 Assert-Nm (-not $r.ADIndex['P111301AA765'].ContainsKey(999))
}
Case-Nm 'Après le dernier ignore les trous y compris pour les suggestions' {
 $q=New-NmRequest;$q.Computers=@([pscustomobject]@{Name='P111301AA765990'});$q.ReservedNames=@();$q.Strategy='AfterLast'
 $r=Invoke-PestoBuildNamesView $q;Equal-Nm $r.CandidateCount 9;foreach($s in $r.Suggestions){Assert-Nm ([int]$s.Num -gt 990)}
}
Case-Nm 'Domaine complet de candidats borné même avec marge nulle' {
 $q=New-NmRequest;$q.Buffer=0;$q.Types=@('P','S','V');$q.Sites=@(65..90|ForEach-Object{'A'+[char]$_});$q.Teams=@(1..30|ForEach-Object{$_.ToString('D3')})
 $threw=$false;try{Invoke-PestoBuildNamesView $q|Out-Null}catch{$threw=$_.Exception.Message -like 'Périmètre trop large*'};Assert-Nm $threw
}
Case-Nm 'Annulation et indice aléatoire invalide échouent sans résultat partiel' {
 $q=New-NmRequest;$q.Cancellation=@{Cancelled=$true};$threw=$false;try{Invoke-PestoBuildNamesView $q|Out-Null}catch{$threw=$_.Exception -is [OperationCanceledException]};Assert-Nm $threw
 $q=New-NmRequest;$q|Add-Member NoteProperty RandomIndex {param($Count) return $Count};$threw=$false;try{Invoke-PestoBuildNamesView $q|Out-Null}catch{$threw=$_.Exception.Message -eq 'Indice aléatoire hors limites.'};Assert-Nm $threw
}

# T108 : vue « Registre partagé » strictement en lecture. Dossier reel sous DEV (aucun acces AD/reseau).
function New-T108Registry {
    param([int]$Active=1,[int]$Expired=1,[int]$Unknown=1,[int]$Oversized=0)
    $base=Join-Path $root ('t108-'+[Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($base)
    [IO.File]::WriteAllText((Join-Path $base 'pesto-coordination.json'),([ordered]@{Schema=1;Domain='test.invalid';Purpose='PestoCoordination'}|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
    $dir=Join-Path $base 'reservations';[void][IO.Directory]::CreateDirectory($dir)
    $now=[DateTime]::UtcNow
    function Write-T108Entry {param([string]$Name,[AllowNull()]$Expires=$null)
        $value=if($null -ne $Expires){$Expires.ToString('o')}else{''}
        $body=([ordered]@{Schema=1;Name=$Name;Domain='test.invalid';Station='POSTE-X';User='alice';Owner=('owner-'+$Name);Context='';CreatedUtc=$now.AddHours(-2).ToString('o');ExpiresUtc=$value}|ConvertTo-Json -Compress)
        [IO.File]::WriteAllText((Join-Path $dir ($Name+'.json')),$body,[Text.UTF8Encoding]::new($false))
    }
    for($i=1;$i -le $Active;$i++){Write-T108Entry ('P111301AA7650'+$i.ToString('D2')) $now.AddHours(1)}
    for($i=1;$i -le $Expired;$i++){Write-T108Entry ('P222222BB7650'+$i.ToString('D2')) $now.AddHours(-1)}
    for($i=1;$i -le $Unknown;$i++){Write-T108Entry ('P333333CC7650'+$i.ToString('D2')) $null}
    for($i=1;$i -le $Oversized;$i++){[IO.File]::WriteAllText((Join-Path $dir ('BAD'+$i.ToString('D2')+'.json')),('x'*9000),[Text.UTF8Encoding]::new($false))}
    return [pscustomobject]@{Base=$base;Reservations=$dir}
}
$t108Bases=New-Object 'System.Collections.Generic.List[string]'
Case-Nm 'T108 : registre absent jamais cree, aucun etat vide annonce' {
    $missing=Join-Path $root ('t108-missing-'+[Guid]::NewGuid().ToString('N'))
    $r=Get-PestoSharedNameRegistrySnapshot -Root $missing
    Assert-Nm (-not $r.Ok) 'Une lecture absente ne doit pas etre OK'
    Assert-Nm (-not [IO.Directory]::Exists($missing)) 'La vue ne doit creer aucun dossier'
    $lines=ConvertTo-PestoSharedNameRegistryLines -Snapshot $r
    Assert-Nm (@($lines|Where-Object{$_ -match 'impossible'}).Count -ge 1) 'Echec non affiche'
    Assert-Nm (@($lines|Where-Object{$_ -match 'Aucune réservation lisible'}).Count -eq 0) 'Ne jamais annoncer vide sur echec'
}
Case-Nm 'T108 : registre prepare lu en lecture seule sans creation ni verrou' {
    $reg=New-T108Registry -Active 1 -Expired 1 -Unknown 1 -Oversized 1;$t108Bases.Add($reg.Base)
    $before=@([IO.Directory]::GetFiles($reg.Reservations)).Count
    $r=Get-PestoSharedNameRegistrySnapshot -Root $reg.Base -Domain 'test.invalid'
    Assert-Nm $r.Ok ([string]$r.Error)
    Equal-Nm $r.Count 3;Equal-Nm $r.Files 4
    Assert-Nm ($r.Skipped -ge 1) 'Le fichier trop volumineux doit etre ignore et signale'
    Equal-Nm (@($r.Entries|Where-Object{$_.State -eq 'Active'}).Count) 1
    Equal-Nm (@($r.Entries|Where-Object{$_.State -eq 'Expirée'}).Count) 1
    Equal-Nm (@($r.Entries|Where-Object{$_.State -eq 'Inconnue'}).Count) 1
    Equal-Nm (@([IO.Directory]::GetFiles($reg.Reservations)).Count) $before
    Assert-Nm (-not [IO.Directory]::Exists((Join-Path $reg.Base 'locks'))) 'Aucun dossier de verrou cree'
    $lines=ConvertTo-PestoSharedNameRegistryLines -Snapshot $r
    Assert-Nm (@($lines|Where-Object{$_ -match 'tronquée'}).Count -eq 0) 'Troncature annoncee a tort'
    Equal-Nm (@($lines|Where-Object{$_ -match ' expir'}).Count) 3
    Assert-Nm (@($lines|Where-Object{$_ -match 'état Inconnue'}).Count -eq 1) 'Etat inconnu non affiche'
}
Case-Nm 'T108 : troncature signalee au-dela de la borne' {
    $reg=New-T108Registry -Active 3 -Expired 0 -Unknown 0;$t108Bases.Add($reg.Base)
    $r=Get-PestoSharedNameRegistrySnapshot -Root $reg.Base -MaxEntries 2
    Assert-Nm $r.Ok;Assert-Nm $r.Truncated;Equal-Nm $r.Count 2;Equal-Nm $r.Files 3
    $lines=ConvertTo-PestoSharedNameRegistryLines -Snapshot $r
    Equal-Nm (@($lines|Where-Object{$_ -match 'tronquée'}).Count) 1
    Assert-Nm (@($lines|Where-Object{$_ -match 'au moins'}).Count -ge 1) 'Compte annonce comme exact alors que tronque'
}
Case-Nm 'T108 : un registre d un autre domaine est refuse' {
    $reg=New-T108Registry -Active 1 -Expired 0 -Unknown 0;$t108Bases.Add($reg.Base)
    $bad=Get-PestoSharedNameRegistrySnapshot -Root $reg.Base -Domain 'autre.invalid'
    Assert-Nm (-not $bad.Ok) 'Un autre domaine doit etre refuse'
    Assert-Nm ([string]$bad.Error -match 'domaine') 'Motif de refus non explicite'
    $lines=ConvertTo-PestoSharedNameRegistryLines -Snapshot $bad
    Assert-Nm (@($lines|Where-Object{$_ -match 'Aucune réservation lisible'}).Count -eq 0) 'Ne jamais annoncer vide sur refus'
}
Case-Nm 'T108 : entree dont le nom ou le domaine differe du fichier est ignoree' {
    $reg=New-T108Registry -Active 1 -Expired 0 -Unknown 0;$t108Bases.Add($reg.Base)
    $wrongName=[ordered]@{Schema=1;Name='P999999ZZ999901';Domain='test.invalid';Station='S';User='u';Owner='o';Context='';CreatedUtc=[DateTime]::UtcNow.ToString('o');ExpiresUtc=[DateTime]::UtcNow.AddHours(1).ToString('o')}
    [IO.File]::WriteAllText((Join-Path $reg.Reservations 'P555555EE765001.json'),($wrongName|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
    $r=Get-PestoSharedNameRegistrySnapshot -Root $reg.Base -Domain 'test.invalid'
    Assert-Nm $r.Ok ([string]$r.Error)
    Equal-Nm $r.Count 1
    Assert-Nm ($r.Skipped -ge 1) 'Une incoherence nom/fichier doit etre ignoree'
    Equal-Nm (@($r.Entries|Where-Object{$_.Name -eq 'P555555EE765001'}).Count) 0
}
Case-Nm 'T108 : la source construite definit bien la fonction de lecture (vrai runspace)' {
    $reg=New-T108Registry -Active 1 -Expired 0 -Unknown 0;$t108Bases.Add($reg.Base)
    $source=Get-PestoSharedNameRegistrySource
    Assert-Nm ([string]$source -match 'function Get-PestoSharedNameRegistrySnapshot\s*\{') 'Corps non reenveloppe dans une definition'
    $rs=[Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace();$rs.Open()
    $ps=[Management.Automation.PowerShell]::Create();$ps.Runspace=$rs
    try{
        [void]$ps.AddScript('param($s,$root,$domain) . ([scriptblock]::Create([string]$s)); $r=Get-PestoSharedNameRegistrySnapshot -Root $root -Domain $domain; [pscustomobject]@{Ok=$r.Ok;Count=$r.Count;Type=(Get-Command Get-PestoSharedNameRegistrySnapshot -CommandType Function).CommandType}',$true)
        [void]$ps.AddArgument([string]$source);[void]$ps.AddArgument($reg.Base);[void]$ps.AddArgument('test.invalid')
        $out=@($ps.Invoke())
        Assert-Nm ($ps.Streams.Error.Count -eq 0) ('Erreur worker : '+(($ps.Streams.Error|ForEach-Object{$_.ToString()}) -join '; '))
        Equal-Nm $out.Count 1
        Assert-Nm $out[0].Ok 'La source construite ne lit pas le registre'
        Equal-Nm $out[0].Count 1
        Equal-Nm ([string]$out[0].Type) 'Function'
    }finally{$ps.Dispose();$rs.Close();$rs.Dispose()}
}
Case-Nm 'T108 : bornes refusees et octets non UTF-8 ignores' {
    $reg=New-T108Registry -Active 1 -Expired 0 -Unknown 0;$t108Bases.Add($reg.Base)
    $threw=$false;try{[void](Get-PestoSharedNameRegistrySnapshot -Root $reg.Base -MaxEntries 0)}catch{$threw=$true}
    Assert-Nm $threw 'MaxEntries hors bornes doit etre refuse par la signature'
    $threw=$false;try{[void](Get-PestoSharedNameRegistrySnapshot -Root $reg.Base -MaxFileBytes 0)}catch{$threw=$true}
    Assert-Nm $threw 'MaxFileBytes hors bornes doit etre refuse par la signature'
    [IO.File]::WriteAllBytes((Join-Path $reg.Reservations 'P666666FF765001.json'),[byte[]]@(0x7B,0xFF,0xFE,0x7D))
    $r=Get-PestoSharedNameRegistrySnapshot -Root $reg.Base -Domain 'test.invalid'
    Assert-Nm $r.Ok ([string]$r.Error)
    Equal-Nm $r.Count 1
    Assert-Nm ($r.Skipped -ge 1) 'Le fichier non UTF-8 doit etre ignore et signale'
}
Case-Nm 'T108 : expiration antérieure à la création reste inconnue' {
    $reg=New-T108Registry -Active 1 -Expired 0 -Unknown 0;$t108Bases.Add($reg.Base)
    $path=@(Get-ChildItem $reg.Reservations -File)[0].FullName
    $entry=Get-Content $path -Raw|ConvertFrom-Json;$entry.CreatedUtc=[DateTime]::UtcNow.AddHours(2).ToString('o')
    [IO.File]::WriteAllText($path,($entry|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    $snapshot=Get-PestoSharedNameRegistrySnapshot -Root $reg.Base -Domain 'test.invalid'
    Equal-Nm $snapshot.Entries[0].State 'Inconnue'
}
Case-Nm 'T108 : marqueur trop volumineux ou UTF8 invalide refusé' {
    $reg=New-T108Registry -Active 0 -Expired 0 -Unknown 0;$t108Bases.Add($reg.Base)
    $marker=Join-Path $reg.Base 'pesto-coordination.json'
    [IO.File]::WriteAllText($marker,('x'*4097));Assert-Nm (-not(Get-PestoSharedNameRegistrySnapshot -Root $reg.Base).Ok)
    [IO.File]::WriteAllBytes($marker,[byte[]](0xC0,0xAF));Assert-Nm (-not(Get-PestoSharedNameRegistrySnapshot -Root $reg.Base).Ok)
}
Case-Nm 'T108 : lecture tardive ignoree si racine, domaine ou configuration ont change' {
    $script:DOMAINE='test.invalid'
    $script:T108Shown=0;$script:T108Logs=0
    function Get-PestoSharedNameSettings {[pscustomobject]@{Root='X:\root';Minutes=15;Random=$true;ReserveInAD=$false}}
    function Get-PestoConfigurationSignature {param($Config);return 'STAMP-A'}
    function Show-PestoTextReport {param($Title,$Text);$script:T108Shown=[int]$script:T108Shown+1}
    function Show-MsgWarning {param($Message,$Title);$script:T108Shown=[int]$script:T108Shown+1}
    $snap=[pscustomobject]@{Ok=$true;Root='X:\root';Domain='test.invalid';ReadUtc='x';Count=0;Files=0;Truncated=$false;Skipped=0;Entries=@()}
    Complete-PestoSharedNameRegistry -Result $snap -Context ([pscustomobject]@{Root='X:\root';Domain='test.invalid';ConfigStamp='STAMP-A'})
    Equal-Nm $script:T108Shown 1
    $script:T108Shown=0
    Complete-PestoSharedNameRegistry -Result $snap -Context ([pscustomobject]@{Root='Y:\autre';Domain='test.invalid';ConfigStamp='STAMP-A'})
    Equal-Nm $script:T108Shown 0
    Complete-PestoSharedNameRegistry -Result $snap -Context ([pscustomobject]@{Root='X:\root';Domain='autre.invalid';ConfigStamp='STAMP-A'})
    Equal-Nm $script:T108Shown 0
    function Get-PestoConfigurationSignature {param($Config);return 'STAMP-B'}
    Complete-PestoSharedNameRegistry -Result $snap -Context ([pscustomobject]@{Root='X:\root';Domain='test.invalid';ConfigStamp='STAMP-A'})
    Equal-Nm $script:T108Shown 0
}
Case-Nm 'T108 : un lien dans les reservations est refuse, jamais suivi' {
    $reg=New-T108Registry -Active 1 -Expired 0 -Unknown 0;$t108Bases.Add($reg.Base)
    $target=Join-Path $reg.Base 'target.json';[IO.File]::WriteAllText($target,'{}',[Text.UTF8Encoding]::new($false))
    $link=Join-Path $reg.Reservations 'P444444DD765001.json'
    $linked=$false
    try{[void](New-Item -ItemType SymbolicLink -Path $link -Target $target -ErrorAction Stop);$linked=$true}catch{}
    if($linked){
        $r=Get-PestoSharedNameRegistrySnapshot -Root $reg.Base
        Assert-Nm $r.Ok ([string]$r.Error)
        Assert-Nm ($r.Skipped -ge 1) 'Le lien doit etre ignore et signale'
        Equal-Nm (@($r.Entries|Where-Object{$_.Name -eq 'P444444DD765001'}).Count) 0
        $lines=ConvertTo-PestoSharedNameRegistryLines -Snapshot $r
        Assert-Nm (@($lines|Where-Object{$_ -match 'ignor'}).Count -ge 1) 'Entree ignoree non signalee'
    }
}
foreach($base in $t108Bases){if([IO.Directory]::Exists($base)){[void][IO.Directory]::Delete($base,$true)}}

# Doubles de présentation : vérifient les transitions, pas le rendu WPF.
$uiNames=@('NmLoadingPanel','NmLoadingTitle','NmLoadingDetail','NmLoadingElapsed','NmLoadingBar','NmBtnRetryNames','NmViewNote','NmGrid','NmLblCount','NmBtnNextP','NmBtnNextS','NmBtnNextV','NmBtnCopy','NmBtnExport','NmBtnRefresh')
foreach($n in $uiNames){Set-Variable -Scope Script -Name $n -Value ([pscustomobject]@{Text='';Content='';Tag='stale';Visibility='Visible';IsEnabled=$true;IsIndeterminate=$false;ItemsSource=@();Items=@();Opacity=1.0;Value=0;ToolTip=''})}
$script:NmLoadTimer=[pscustomobject]@{Started=$false}
$script:NmLoadTimer|Add-Member ScriptMethod Start {$this.Started=$true}
$script:NmLoadTimer|Add-Member ScriptMethod Stop {$this.Started=$false}
$script:NmLoading=$false;$script:PestoAsyncOperations=@{};$script:PestoAsyncTimerOperations=@{}
Case-Nm 'Chargement garde les anciennes lignes grisées et désactive les commandes' {
 $NmGrid.ItemsSource=@('stale');$NmGrid.Items=@('stale');Set-PestoNamesViewState -State Loading -Title 'Lecture'
 Assert-Nm $NmLoadingBar.IsIndeterminate;Assert-Nm $script:NmLoadTimer.Started;Equal-Nm $NmGrid.Visibility 'Visible';Equal-Nm $NmGrid.ItemsSource.Count 1;Equal-Nm $NmGrid.Opacity 0.25;Assert-Nm (-not $NmGrid.IsEnabled)
 foreach($b in @($NmBtnCopy,$NmBtnExport,$NmBtnNextP,$NmBtnNextS,$NmBtnNextV)){Assert-Nm (-not $b.IsEnabled)}
 Assert-Nm (-not $script:NmViewReady)
}
Case-Nm 'Le compteur est une quantité réellement lue, sans pourcentage' {
 $script:NmLoadMonitor=[hashtable]::Synchronized(@{State=[pscustomobject]@{Stage='Inventaire des postes';Count=3159;Unit='postes lus'}})
 Update-PestoNamesLoadProgress;Assert-Nm ($NmLoadingDetail.Text -match 'postes lus');Assert-Nm ($NmLoadingDetail.Text -notmatch '%');Equal-Nm $NmLoadingTitle.Text 'Inventaire des postes'
}
Case-Nm 'Erreur arrête l''indicateur et propose Réessayer' {
 $script:NmViewGeneration=7;Fail-PestoNamesProjection -Failure $null -Context ([pscustomobject]@{Generation=7})
 Assert-Nm (-not $NmLoadingBar.IsIndeterminate);Assert-Nm (-not $script:NmLoadTimer.Started);Equal-Nm $NmBtnRetryNames.Visibility 'Visible';Assert-Nm (-not $NmBtnCopy.IsEnabled)
}
Case-Nm 'Ancien résultat filtré jamais publié' {
 $NmLoadingTitle.Text='KEEP';$script:NmViewGeneration=9
 Complete-PestoNamesProjection -Result (Invoke-PestoBuildNamesView (New-NmRequest)) -Context ([pscustomobject]@{Generation=7;Source=@()})
 Equal-Nm $NmLoadingTitle.Text 'KEEP';Fail-PestoNamesProjection -Failure $null -Context ([pscustomobject]@{Generation=7});Equal-Nm $NmLoadingTitle.Text 'KEEP'
}
Case-Nm 'Copie refusée quand la vue n''est pas prête' {$script:NmViewReady=$false;Copy-NmName 'P111301AA765004';Assert-Nm (-not $script:NmViewReady)}
Case-Nm 'Inventaire partiel ne lance aucun calcul de libres' {
 $script:GUI=$false;$script:InventoryLoaded=$false;$script:NmNeedsDirectoryRetry=$false;$script:SuspendNm=$false
 Update-NameGrid;Equal-Nm $NmLoadingTitle.Text 'Inventaire non chargé';Assert-Nm (-not (Test-PestoAsyncOperationRunning 'NamesProjection'))
}
Case-Nm 'Une collecte déjà active ne déclenche pas un deuxième calcul' {
 $script:PestoAsyncOperations.DirectoryRefresh=[pscustomobject]@{};$NmLoadingTitle.Text='LECTURE'
 Update-NameGrid;Equal-Nm $NmLoadingTitle.Text 'LECTURE';[void]$script:PestoAsyncOperations.Remove('DirectoryRefresh')
}
Case-Nm 'Cache changé en plein calcul : pas de chargement infini ni résultat obsolète' {
 $script:NmViewGeneration=7;$script:ComputersNoms=@([pscustomobject]@{Name='NEW'})
 Complete-PestoNamesProjection -Result (Invoke-PestoBuildNamesView (New-NmRequest)) -Context ([pscustomobject]@{Generation=7;Source=@([pscustomobject]@{Name='OLD'})})
 Equal-Nm $NmLoadingTitle.Text 'Inventaire modifié';Assert-Nm (-not $NmLoadingBar.IsIndeterminate)
}
Case-Nm 'Candidat hors marge reste utilisable même quand le tableau est vide' {
 $NmGrid.Items=[pscustomobject]@{SortDescriptions=[Collections.Generic.List[object]]::new()}
 $NmGrid | Add-Member NoteProperty SelectedItem $null -Force
 $q=New-NmRequest;$q.Search='765999';$r=Invoke-PestoBuildNamesView $q
 $script:NmViewGeneration=7;$script:ComputersNoms=$q.Computers
 Complete-PestoNamesProjection -Result $r -Context ([pscustomobject]@{Generation=7;Source=$script:ComputersNoms})
 Assert-Nm $script:NmViewReady;Assert-Nm $NmBtnNextP.IsEnabled;Equal-Nm $NmBtnNextP.Tag 'P111301AA765999';Assert-Nm (-not $NmBtnExport.IsEnabled)
}
Stop-PestoNamesLoadTimer

if($Wpf){
 if($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSEdition -ne 'Desktop'){throw '-Wpf exige Windows PowerShell 5.1 sous Windows.'}
 if([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA'){throw 'Le test WPF doit être lancé avec -STA.'}
 Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
 $script:NmLoadTimer=$null;$script:NmLoadClock=$null
 $w=$null
 try{
  Case-Nm 'Vrai XAML : indicateur, aide et virtualisation présents' {
   $script:NamesTestWindow=[Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText((Join-Path $root 'wad\Pesto-Shell.xaml')))
   foreach($n in @($uiNames)+@('NmCmbSite','NmCmbEquipe','NmCmbType','NmCmbStatut','NmTxtSearch','NmChkAll','NmBtnRefresh')){Set-Variable -Name $n -Scope Script -Value $script:NamesTestWindow.FindName($n);Assert-Nm (Get-Variable -Name $n -ValueOnly) $n}
   $w=$script:NamesTestWindow;$w.ShowInTaskbar=$false;$w.Title='TEST LOCAL - Noms disponibles';$w.FindName('MainTabs').SelectedIndex=1;$w.Show();$w.UpdateLayout()
   Assert-Nm $NmGrid.EnableRowVirtualization;Assert-Nm $NmBtnRetryNames.ToolTip;Assert-Nm ([Windows.Controls.ToolTipService]::GetShowOnDisabled($NmBtnRetryNames))
  }
  function Invoke-NmTestPumpTick {param($Sender,$EventArgs);if(-not(Test-PestoAsyncOperationRunning 'NamesProjection') -or $script:NmTestClock.Elapsed.TotalSeconds -gt 8){$script:NmTestFrame.Continue=$false}}
  function Wait-NmProjection {
   $script:NmTestClock=[Diagnostics.Stopwatch]::StartNew();$script:NmTestFrame=New-Object Windows.Threading.DispatcherFrame
   $timer=New-Object Windows.Threading.DispatcherTimer;$timer.Interval=[TimeSpan]::FromMilliseconds(30)
   $handler=[EventHandler]${function:Invoke-NmTestPumpTick};$timer.Add_Tick($handler);$timer.Start()
   try{[Windows.Threading.Dispatcher]::PushFrame($script:NmTestFrame)}finally{$timer.Stop();$timer.Remove_Tick($handler)}
   Assert-Nm (-not(Test-PestoAsyncOperationRunning 'NamesProjection')) 'Worker de test non terminé.'
  }
  Case-Nm 'Vrai worker : indicateur immédiat puis tableau sans bloquer le Dispatcher' {
   Assert-Nm $script:NamesTestWindow
   $script:PREFIXE='111301';$script:GUI=$true;$script:InventoryLoaded=$true;$script:InventoryUtc=[DateTime]::UtcNow.ToString('o')
   $script:NmNeedsDirectoryRetry=$false;$script:ComputersNoms=(New-NmRequest).Computers;$script:table=$null;$script:NmBuffer=2
   Build-NmIndex;Populate-NmFilters;Update-NameGrid
   Assert-Nm $NmLoadingBar.IsIndeterminate;Equal-Nm $NmLoadingPanel.Visibility ([Windows.Visibility]::Visible)
   Wait-NmProjection;Assert-Nm $script:NmViewReady;Assert-Nm ($NmGrid.ItemsSource.Count -gt 0);Assert-Nm (-not $NmLoadingBar.IsIndeterminate)
  }
  Case-Nm 'Vrai worker en erreur : indicateur retiré et aucune liste publiée' {
   $script:NmViewGeneration++;$context=[pscustomobject]@{Generation=$script:NmViewGeneration;Source=$script:ComputersNoms}
   Set-PestoNamesViewState -State Loading -Title 'Erreur fictive'
   [void](Start-PestoAsyncOperation -Name NamesProjection -ScriptBlock {Start-Sleep -Milliseconds 200;throw 'Erreur de lecture simulée'} -CallbackContext $context -TimeoutSec 5 -OnError {param($e,$c) Fail-PestoNamesProjection $e $c})
   Wait-NmProjection;Assert-Nm (-not $script:NmViewReady);Assert-Nm (-not $NmLoadingBar.IsIndeterminate);Equal-Nm $NmBtnRetryNames.Visibility ([Windows.Visibility]::Visible)
  }
 }finally{
  Stop-PestoNamesLoadTimer
  foreach($n in @($script:PestoAsyncOperations.Keys)){Stop-PestoAsyncOperation $n}
  if($script:NamesTestWindow){$script:NamesTestWindow.Close()}
 }
}
$failed=@($results|Where-Object{-not $_.Passed}).Count
[pscustomobject]@{Version='1.0';PowerShell=[string]$PSVersionTable.PSVersion;WindowsWpfRequested=[bool]$Wpf;NoAD=$true;Failed=$failed;Checks=$results.ToArray()}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $ReportPath -Encoding UTF8
Write-Host ('Rapport : '+$ReportPath)
if($failed){exit 1}else{exit 0}
