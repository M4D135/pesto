#requires -Version 5.1
[CmdletBinding()]
param([string]$SourcePath='',[string]$ReportPath='')
# Windows PowerShell 5.1 : $PSScriptRoot est vide dans les valeurs par défaut des paramètres (vu le 03/10).
if(-not $SourcePath){$SourcePath=Join-Path $PSScriptRoot '..\wad\Pesto-Core.ps1'}
if(-not $ReportPath){$ReportPath=Join-Path $PSScriptRoot 'windows-pilotage-results.json'}
$ErrorActionPreference='Stop';Set-StrictMode -Off
if($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5 -or -not [Environment]::Is64BitProcess){throw 'Tests RC5 : Windows PowerShell 5.1 x64 requis.'}
Add-Type -AssemblyName System.Data,PresentationFramework,PresentationCore,WindowsBase
# Pas de dot-sourcing du moteur. Extraction AST des seules fonctions ci-dessous.
# Pas d'import AD. Toute lecture AD est simulée. Toute mutation externe est un piège.
# Les fonctions testees ont quitte Pesto-Core.ps1 : le banc indexe tout le repertoire wad/ de la source indiquee.
$tokens=$null
$wadDir=Split-Path ([IO.Path]::GetFullPath($SourcePath)) -Parent
$defs=@{}
foreach($file in (Get-ChildItem -LiteralPath $wadDir -File | Where-Object{$_.Extension -eq '.ps1' -and $_.Name -ine 'Pesto.Engine.Runtime.ps1'} | Sort-Object Name)){
    $parseErrors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$parseErrors)
    if($parseErrors.Count){throw (($parseErrors|ForEach-Object{"$($file.Name):$($_.Extent.StartLineNumber): $($_.Message)"}) -join "`n")}
    foreach($node in $ast.EndBlock.Statements){if($node -is [Management.Automation.Language.FunctionDefinitionAst] -and -not $defs.ContainsKey($node.Name)){$defs[$node.Name]=$node.Extent.Text}}
}
$load=@('Test-PestoDnsName','Split-PestoDistinguishedName','Get-PestoParentDN','Get-PestoDomainFromDN','Test-PestoDNWithinScope',
    'Test-PestoComputerName','Test-PestoGeneratedComputerName','Test-PestoOUPath','Test-PestoOUInConfiguredScope','Test-QueueRowSafe',
    'Get-PestoNameSiteCode','Get-PestoSiteContainerDN','Get-PestoRenameMoveDecision','New-QueueTable','Protect-PestoLogText',
    'Write-PestoAtomicText','Get-PestoRowPlanText','Get-PestoPlanSignature','Get-PestoIdentityChangeReason','ConvertTo-PestoFilterLiteral',
    'Get-PestoQueueFilterExpression','ConvertFrom-PestoComputerList','New-PestoBulkPlan','Get-PestoPreflightSource','Invoke-PestoReadOnlyPreflight',
    'Get-PestoResultGuidance','New-PestoQueueReportHtml','Reset-PestoRowPreflight','Get-PestoSelectedQueueIndex','Set-PestoVisibleSelection',
    'Update-PestoPreflightFreshness','Get-PestoPreflightRunIssues','Get-PestoPreflightConfirmationText','Save-PestoRunHistory',
    'Get-PestoInitialNameIndex','Get-PestoSharedNameSettings','ConvertTo-PestoPolicy','Merge-PestoManagedPolicy','Assert-PestoClosedObject','Test-PestoPropertyPresent','Get-PestoConfigurationSignature',
    'Convert-Value-TF','ConvertTo-PestoCanonicalValue','Get-PestoStableHash','ConvertTo-PestoNameParts','New-PestoComputerName','Import-PestoADModule','Get-PestoUxNom','Assert-PestoPlainPath')
foreach($n in $load){if(-not $defs.ContainsKey($n)){throw "Fonction absente : $n"};. ([scriptblock]::Create($defs[$n]))}
# Get-PestoUxNom lit $script:PESTO_UX_NOMS, table de donnees du moteur : le banc l'evalue depuis l'AST, sinon elle reste nulle.
$uxTokens=$null;$uxErrors=$null
$uxAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $wadDir 'Pesto-UXFlow.ps1'),[ref]$uxTokens,[ref]$uxErrors)
if($uxErrors.Count){throw ("Pesto-UXFlow.ps1: " + (($uxErrors|ForEach-Object{"$($_.Extent.StartLineNumber): $($_.Message)"}) -join "`n"))}
$uxNamesAst=$null
foreach($stmt in $uxAst.EndBlock.Statements){if($stmt -is [Management.Automation.Language.AssignmentStatementAst] -and $stmt.Left.Extent.Text -eq '$script:PESTO_UX_NOMS'){$uxNamesAst=$stmt}}
if(-not $uxNamesAst){throw 'Affectation $script:PESTO_UX_NOMS absente de Pesto-UXFlow.ps1.'}
if($uxNamesAst.Right.Extent.Text -notmatch '^(\[ordered\])?@\{'){throw 'Affectation $script:PESTO_UX_NOMS non litterale : le banc refuse d''evaluer du code du moteur.'}
. ([scriptblock]::Create($uxNamesAst.Extent.Text))
$results=[Collections.Generic.List[object]]::new()
function Assert-True {param($Value,[string]$Message='Condition non satisfaite.');if($Value -ne $true){throw $Message}}
function Assert-Equal {param($Actual,$Expected);if($Actual -cne $Expected){throw "Attendu [$Expected], obtenu [$Actual]."}}
function Assert-Throws {param([scriptblock]$Body);$thrown=$false;try{& $Body}catch{$thrown=$true};if(-not $thrown){throw 'Une exception était attendue.'}}
function Case {param([string]$Name,[scriptblock]$Body);try{& $Body;$results.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''});Write-Host "OK  $Name"}catch{$results.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message});Write-Host "KO  $Name : $($_.Exception.Message)"}}
# Politique isolée : le banc ne lit aucune GPO ni préférence de la machine hôte.
function Get-PestoManagedPolicy {return [pscustomobject]@{Values=[pscustomobject]@{};Configured=$false;Source='fixture'}}
function Sync-Grid {}
function Update-QueueButtons {}
function Save-PestoQueueCheckpointSafe {}
function Get-PestoStateDirectory {return $script:TempState}
function Rename-Computer {throw 'MUTATION INTERDITE PAR LE TEST'}
function Add-Computer {throw 'MUTATION INTERDITE PAR LE TEST'}
function Move-ADObject {throw 'MUTATION INTERDITE PAR LE TEST'}
function Set-ADObject {throw 'MUTATION INTERDITE PAR LE TEST'}
function Restart-Computer {throw 'MUTATION INTERDITE PAR LE TEST'}
function Reset-Fixture {
    $script:CFG=[pscustomobject]@{POLICY=[pscustomobject]@{Schema=1;RandomNameEnabled=$false}}
    $script:INDOMAIN=$true;$script:PRD=$true;$script:GUI=$false;$script:SIM=$false;$script:CLEAR_PROTECTION=$true
    $script:DOMAINE='example.local';$script:DC='dc01.example.local';$script:PREFIXE='111301'
    $script:OU=@{ROOT='OU=Postes,DC=example,DC=local';PREPROD='OU=Transit,OU=Postes,DC=example,DC=local'}
    $script:OUV=@{Org='OU=Sites,OU=Postes,DC=example,DC=local'}
    $script:SourceOU='OU=PR,OU=Sites,OU=Postes,DC=example,DC=local';$script:TargetOU='OU=VA,OU=Sites,OU=Postes,DC=example,DC=local'
    $script:SourceName='P111301PR765129';$script:SourceGuid='12345678-1111-2222-3333-123456789012'
    $script:Computers=@((New-FakePC $script:SourceName $script:SourceOU))
    $script:ReadError=$false;$script:ReadDuplicate=$false;$script:MissingOU=$false;$script:ADCalls=[Collections.Generic.List[object]]::new()
    $script:Running=$false;$script:PreflightRunning=$false;$script:PreflightCache=@{};$script:MutationUncertain=$false
    $script:table=New-QueueTable
}
function New-FakePC {
    param([string]$Name,[string]$OU,[string]$Guid=$script:SourceGuid)
    return [pscustomobject]@{Name=$Name;DistinguishedName="CN=$Name,$OU";ObjectGUID=$Guid;Enabled=$true;ProtectedFromAccidentalDeletion=$false}
}
function New-TestRow {
    $t=New-QueueTable;$r=$t.NewRow();$r.Nom_du_PC=$script:SourceName;$r.Nouveau_Nom='P111301VA765001';$r.OU_Actuelle=$script:SourceOU;$r.OU_Destination=$script:TargetOU
    $r.Renommer=$true;$r.Deplacer=$true;$r.Traiter=$true;$r.Objet_GUID=$script:SourceGuid;$r.Precontrole='À CONTRÔLER';$r.Plan=Get-PestoRowPlanText $r
    [void]$t.Rows.Add($r);return ,$r
}
function New-ReadRequest {
    # Host = source pour désactiver complètement la sonde ICMP pendant les tests.
    return [pscustomobject]@{DC=$script:DC;Domain=$script:DOMAINE;Credential=$null;InDomain=$true;Host=$script:SourceName;PRD=$true;OU=$script:OU;ClearProtection=$script:CLEAR_PROTECTION}
}
function New-ReadItem {
    param($Row)
    $o=[ordered]@{Key=Get-PestoPlanSignature $Row}
    foreach($k in @('Nom_du_PC','Nouveau_Nom','OU_Actuelle','OU_Destination','Objet_GUID')){$o[$k]=[string]$Row[$k]}
    foreach($k in @('Renommer','Deplacer','Reboot')){$o[$k]=[bool]$Row[$k]}
    return [pscustomobject]$o
}
function Read-Plan {param($Row);return Invoke-PestoReadOnlyPreflight -Item (New-ReadItem $Row) -Request (New-ReadRequest) -OUCache @{}}
function Get-ADComputer {
    [CmdletBinding()]param($LDAPFilter,$ResultSetSize,$Properties,$Server,$Credential,$Identity)
    if($script:ReadError){throw 'MOCK lecture AD refusée, password=mock-secret'}
    if($Identity){throw 'Le précontrôle doit utiliser une recherche contrôlée, pas une identité libre.'}
    $script:ADCalls.Add([pscustomobject]@{Kind='PC';Server=$Server;Limit=$ResultSetSize;Query=$LDAPFilter})
    if($LDAPFilter -notmatch '\(name=([^\)]+)\)'){throw 'MOCK filtre imprévu.'}
    $name=$Matches[1];$found=@($script:Computers|Where-Object{$_.Name -ieq $name})
    if($script:ReadDuplicate -and $name -ieq $script:SourceName){return @($found)+@($found)}
    return $found
}
function Get-ADOrganizationalUnit {
    [CmdletBinding()]param($Identity,$Server,$Credential)
    $script:ADCalls.Add([pscustomobject]@{Kind='OU';Server=$Server;Limit=0;Query=$Identity})
    if($script:MissingOU){throw 'MOCK OU absente.'};return [pscustomobject]@{DistinguishedName=$Identity;ObjectGUID=[Guid]::new('bbbbbbbb-1111-2222-3333-123456789012')}
}
function Build-Bulk {
    param([string[]]$Names=@($script:SourceName),[string]$Tag='VA',[string]$OU=$script:TargetOU,[bool]$KeepType=$true)
    return ,(New-PestoBulkPlan -Names $Names -Computers $script:Computers -Existing $script:table -Prefix $script:PREFIXE -Tag $Tag -Service '765' -TargetOU $OU -Site $Tag -Organisme 'Org' -KeepType $KeepType -Reference 'INC-123')
}
Reset-Fixture
Case 'Schéma RC5 complet, aucun champ credential' {
    foreach($c in @('Plan','Precontrole','Controle_Detail','Controle_Utc','Controle_Signature','Objet_GUID','Reference','Mode_Resultat','Lot_ID')){Assert-True $script:table.Columns.Contains($c)}
    Assert-Equal @($script:table.Columns|Where-Object{$_.ColumnName -match 'password|credential'}).Count 0
}
Case 'Liste accepte espaces tabulations virgules et point-virgule' {Assert-Equal ((ConvertFrom-PestoComputerList "PC-1,pc-2;PC-3`r`nPC-4`tPC-5") -join ',') 'PC-1,PC-2,PC-3,PC-4,PC-5'}
Case 'Liste vide refusée' {Assert-Throws {ConvertFrom-PestoComputerList ''}}
Case 'Doublon insensible à la casse refusé' {Assert-Throws {ConvertFrom-PestoComputerList 'PC-1;pc-1'}}
Case 'FQDN et commandes refusés' {Assert-Throws {ConvertFrom-PestoComputerList 'pc.example.local'};Assert-Throws {ConvertFrom-PestoComputerList 'PC1;$(whoami)'}}
Case 'Limite 200 postes' {Assert-Equal @(ConvertFrom-PestoComputerList ((1..200|ForEach-Object{'PC-'+$_}) -join ' ')).Count 200;Assert-Throws {ConvertFrom-PestoComputerList ((1..201|ForEach-Object{'PC-'+$_}) -join ' ')}}
Case 'Liste volumineuse refusée' {Assert-Throws {ConvertFrom-PestoComputerList ('A'*65537)}}
Case 'Filtre littéral applique les métacaractères à DataView' {
    $t=New-QueueTable
    foreach($v in @("A'[x]*%B",'Autre')){$r=$t.NewRow();$r.Nom_du_PC='PC1';$r.Reference=$v;[void]$t.Rows.Add($r)}
    $t.DefaultView.RowFilter=Get-PestoQueueFilterExpression -Search "'[x]*%";Assert-Equal $t.DefaultView.Count 1
    Assert-Equal $t.DefaultView[0].Reference "A'[x]*%B"
}
Case 'Filtre ne transforme pas une chaîne en expression' {$t=New-QueueTable;$r=$t.NewRow();$r.Nom_du_PC='PC1';[void]$t.Rows.Add($r);$t.DefaultView.RowFilter=Get-PestoQueueFilterExpression -Search "' OR 1=1 OR '";Assert-Equal $t.DefaultView.Count 0}
Case 'Filtre inconnu refusé' {Assert-Throws {Get-PestoQueueFilterExpression -Filter 'injection'}}
Case 'Succès simulation exclus du filtre réel' {
    $t=New-QueueTable
    foreach($m in @('RÉEL','SIMULATION','')){$r=$t.NewRow();$r.Statut='OK';$r.Mode_Resultat=$m;[void]$t.Rows.Add($r)}
    $t.DefaultView.RowFilter=Get-PestoQueueFilterExpression -Filter 'Réussites réelles';Assert-Equal $t.DefaultView.Count 1
}
Case 'Index sélectionné suit la DataRow après tri et filtre' {
    Reset-Fixture
    foreach($n in @('PC-B','PC-A','PC-C')){$r=$script:table.NewRow();$r.Nom_du_PC=$n;[void]$script:table.Rows.Add($r)}
    $script:table.DefaultView.Sort='Nom_du_PC ASC';$script:table.DefaultView.RowFilter="Nom_du_PC <> 'PC-C'"
    $script:Grid=[pscustomobject]@{SelectedItem=$script:table.DefaultView[0]}
    Assert-Equal (Get-PestoSelectedQueueIndex) 1
}
Case 'Décocher visibles ne perd pas la deuxième ligne dans un filtre actif' {
    Reset-Fixture
    foreach($n in @('PC-A','PC-B','PC-C')){$r=$script:table.NewRow();$r.Nom_du_PC=$n;$r.Traiter=$true;[void]$script:table.Rows.Add($r)}
    $script:table.DefaultView.RowFilter="Traiter = true AND Nom_du_PC <> 'PC-C'"
    $script:Grid=[pscustomobject]@{};$script:Grid|Add-Member ScriptMethod CommitEdit {param($a,$b) return $true}
    Set-PestoVisibleSelection -Selected $false
    Assert-Equal $script:table.Rows[0].Traiter $false;Assert-Equal $script:table.Rows[1].Traiter $false;Assert-Equal $script:table.Rows[2].Traiter $true
}
Case 'Lot PR vers VA : renommage puis déplacement, décoché, sans reboot' {Reset-Fixture;$t=Build-Bulk;Assert-Equal $t.Rows.Count 1;Assert-Equal $t.Rows[0].Nouveau_Nom 'P111301VA765001';Assert-Equal $t.Rows[0].Deplacer $true;Assert-Equal $t.Rows[0].Traiter $false;Assert-Equal $t.Rows[0].Reboot $false;Assert-Equal $t.Rows[0].Reference 'INC-123'}
Case 'Lot PR vers PR : conserve sa sous-OU' {Reset-Fixture;$script:Computers[0].DistinguishedName="CN=$script:SourceName,OU=Equipe,$script:SourceOU";$t=Build-Bulk -Tag 'PR' -OU $script:SourceOU;Assert-Equal $t.Rows[0].Deplacer $false;Assert-True ($t.Rows[0].OU_Actuelle -like 'OU=Equipe,*')}
Case 'Lot ignore numéros occupés et réservés' {
    Reset-Fixture;$script:Computers+=@(New-FakePC 'P111301VA765001' $script:TargetOU)
    $r=$script:table.NewRow();$r.Nom_du_PC='PC-OTHER';$r.Nouveau_Nom='P111301VA765002';$r.Renommer=$true;[void]$script:table.Rows.Add($r)
    $t=Build-Bulk;Assert-Equal $t.Rows[0].Nouveau_Nom 'P111301VA765003'
}
Case 'Lot conserve le type S' {Reset-Fixture;$script:SourceName='S111301PR765129';$script:Computers=@(New-FakePC $script:SourceName $script:SourceOU);$t=Build-Bulk;Assert-Equal $t.Rows[0].Nouveau_Nom 'S111301VA765001'}
Case 'Lot source inconnue : aucun ajout partiel' {Reset-Fixture;Assert-Throws {Build-Bulk -Names @($script:SourceName,'PC-ABSENT')};Assert-Equal $script:table.Rows.Count 0}
Case 'Lot source dupliquée refusée' {Reset-Fixture;Assert-Throws {Build-Bulk -Names @($script:SourceName,$script:SourceName)}}
Case 'Lot source déjà en file refusée' {Reset-Fixture;$r=New-TestRow;$script:table.ImportRow($r);Assert-Throws {Build-Bulk}}
Case 'Lot source hors périmètre refusée' {Reset-Fixture;$script:Computers[0].DistinguishedName="CN=$script:SourceName,OU=Other,DC=other,DC=local";Assert-Throws {Build-Bulk}}
Case 'Lot cible hors périmètre refusée' {Reset-Fixture;Assert-Throws {Build-Bulk -OU 'OU=Other,DC=other,DC=local'}}
Case 'Lot cache ambigu refusé' {Reset-Fixture;$script:Computers+=@(New-FakePC $script:SourceName $script:TargetOU);Assert-Throws {Build-Bulk}}
Case 'Lot plage épuisée refusée sans écriture' {
    Reset-Fixture;$script:Computers+=@(1..999|ForEach-Object{New-FakePC ('P111301VA765'+$_.ToString('000')) $script:TargetOU});Assert-Throws {Build-Bulk};Assert-Equal $script:table.Rows.Count 0
}
Case 'Lot n''ajoute rien au cache' {Reset-Fixture;$before=$script:Computers.Count;$t=Build-Bulk;Assert-Equal $script:Computers.Count $before;Assert-Equal $script:table.Rows.Count 0;Assert-Equal $t.Rows[0].Objet_GUID $script:SourceGuid}
Case 'Lot refusé hors domaine' {Reset-Fixture;$script:INDOMAIN=$false;Assert-Throws {Build-Bulk}}
Case 'Empreinte indépendante des cases Traiter et du texte de ticket' {Reset-Fixture;$r=New-TestRow;$a=Get-PestoPlanSignature $r;$r.Traiter=$false;$r.Reference='NEW';Assert-Equal (Get-PestoPlanSignature $r) $a}
Case 'Empreinte change avec cible, GUID et mode' {Reset-Fixture;$r=New-TestRow;$a=Get-PestoPlanSignature $r;$r.Nouveau_Nom='P111301VA765002';Assert-True ((Get-PestoPlanSignature $r) -ne $a);$r=New-TestRow;$r.Objet_GUID='';Assert-True ((Get-PestoPlanSignature $r) -ne $a);$r=New-TestRow;$script:SIM=$true;Assert-True ((Get-PestoPlanSignature $r) -ne $a)}
Case 'Identité égale acceptée ; GUID invalide et différent refusés' {Reset-Fixture;Assert-Equal (Get-PestoIdentityChangeReason $script:SourceGuid $script:SourceGuid $script:SourceOU $script:SourceOU) '';Assert-True ([bool](Get-PestoIdentityChangeReason 'invalid' $script:SourceGuid '' ''));Assert-True ([bool](Get-PestoIdentityChangeReason $script:SourceGuid '99999999-1111-2222-3333-123456789012' '' ''))}
Case 'Dérive OU source détectée' {Reset-Fixture;Assert-True ([bool](Get-PestoIdentityChangeReason '' '' $script:SourceOU $script:TargetOU))}
Case 'Contrôle valide : lecture sur DC unique, sans certification de droits' {Reset-Fixture;$r=Read-Plan (New-TestRow);Assert-Equal $r.State 'VÉRIFIÉ';Assert-True ($r.Detail -match 'non certifiés');Assert-Equal @($script:ADCalls|Where-Object{$_.Server -ne $script:DC}).Count 0;Assert-Equal @($script:ADCalls|Where-Object{$_.Kind -eq 'PC' -and $_.Limit -ne 2}).Count 0}
Case 'Contrôle nom cible occupé bloqué' {Reset-Fixture;$script:Computers+=@(New-FakePC 'P111301VA765001' $script:TargetOU);Assert-Equal (Read-Plan (New-TestRow)).State 'BLOQUÉ'}
Case 'Contrôle source absente bloqué' {Reset-Fixture;$script:Computers=@();Assert-Equal (Read-Plan (New-TestRow)).State 'BLOQUÉ'}
Case 'Contrôle source ambiguë bloqué' {Reset-Fixture;$script:ReadDuplicate=$true;Assert-Equal (Read-Plan (New-TestRow)).State 'BLOQUÉ'}
Case 'Contrôle GUID remplacé bloqué' {Reset-Fixture;$script:Computers[0].ObjectGUID='99999999-1111-2222-3333-123456789012';Assert-Equal (Read-Plan (New-TestRow)).State 'BLOQUÉ'}
Case 'Contrôle OU déplacée bloqué' {Reset-Fixture;$script:Computers[0].DistinguishedName="CN=$script:SourceName,$script:TargetOU";Assert-Equal (Read-Plan (New-TestRow)).State 'BLOQUÉ'}
Case 'Contrôle OU inexistante bloqué' {Reset-Fixture;$script:MissingOU=$true;Assert-Equal (Read-Plan (New-TestRow)).State 'BLOQUÉ'}
Case 'Contrôle ordinateur désactivé : avertissement' {Reset-Fixture;$script:Computers[0].Enabled=$false;Assert-Equal (Read-Plan (New-TestRow)).State 'AVERTISSEMENT'}
Case 'Contrôle protection interdite : blocage, sans levée de protection' {Reset-Fixture;$script:CLEAR_PROTECTION=$false;$script:Computers[0].ProtectedFromAccidentalDeletion=$true;Assert-Equal (Read-Plan (New-TestRow)).State 'BLOQUÉ'}
Case 'Contrôle protection autorisée : avertissement, aucune levée réelle' {Reset-Fixture;$script:Computers[0].ProtectedFromAccidentalDeletion=$true;Assert-Equal (Read-Plan (New-TestRow)).State 'AVERTISSEMENT'}
Case 'Contrôle lecture impossible : blocage et secret masqué' {Reset-Fixture;$script:ReadError=$true;$r=Read-Plan (New-TestRow);Assert-Equal $r.State 'BLOQUÉ';Assert-True ($r.Detail -notmatch 'mock-secret')}
Case 'Contrôle renommage seul ne requiert pas une lecture OU cible' {Reset-Fixture;$r=New-TestRow;$r.Nouveau_Nom='P111301PR765001';$r.Deplacer=$false;$script:MissingOU=$true;Assert-Equal (Read-Plan $r).State 'VÉRIFIÉ';Assert-Equal @($script:ADCalls|Where-Object{$_.Kind -eq 'OU'}).Count 0}
Case 'Contrôle respecte le plan de déplacement signé' {Reset-Fixture;$r=New-TestRow;$r.Deplacer=$false;Assert-Equal (Read-Plan $r).State 'BLOQUÉ';Assert-Equal $script:ADCalls.Count 0}
Case 'Contrôle met en cache uniquement les OU lues' {Reset-Fixture;$c=@{};$item=New-ReadItem (New-TestRow);$req=New-ReadRequest;[void](Invoke-PestoReadOnlyPreflight $item $req $c);[void](Invoke-PestoReadOnlyPreflight $item $req $c);Assert-Equal @($script:ADCalls|Where-Object{$_.Kind -eq 'OU'}).Count 1}
Case 'Source du worker en lecture seule sans commande de mutation' {
    $text=Get-PestoPreflightSource;$tok=$null;$err=$null;$a=[Management.Automation.Language.Parser]::ParseInput($text,[ref]$tok,[ref]$err);Assert-Equal $err.Count 0
    $commands=@($a.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst]},$true)|ForEach-Object{$_.GetCommandName()})
    foreach($bad in @('Rename-Computer','Move-ADObject','Set-ADObject','Add-Computer','Restart-Computer','Invoke-Expression','Start-Process','Invoke-Command')){Assert-True ($bad -notin $commands)}
}
Case 'Blocage daté ne devient jamais autorisation par expiration' {Reset-Fixture;$r=New-TestRow;$r.ConfigStamp=Get-PestoConfigurationSignature $script:CFG;$key=Get-PestoPlanSignature $r;$script:PreflightCache[$key]=[pscustomobject]@{State='BLOQUÉ';Detail='occupé';Utc=[DateTime]::UtcNow.AddHours(-1).ToString('o')};Assert-Equal @(Get-PestoPreflightRunIssues @($r)).Count 1}
Case 'Résultat expiré signalé périmé' {Reset-Fixture;$r=New-TestRow;$r.Precontrole='VÉRIFIÉ';$script:table.ImportRow($r);$key=Get-PestoPlanSignature $r;$script:PreflightCache[$key]=[pscustomobject]@{State='VÉRIFIÉ';Utc=[DateTime]::UtcNow.AddMinutes(-6).ToString('o')};Update-PestoPreflightFreshness;Assert-Equal $script:table.Rows[0].Precontrole 'PÉRIMÉ'}
Case 'Un ancien marquage importé ne vaut pas contrôle de la session' {Reset-Fixture;$r=New-TestRow;$r.Precontrole='VÉRIFIÉ';$script:table.ImportRow($r);Update-PestoPreflightFreshness;Assert-Equal $script:table.Rows[0].Precontrole 'À REFAIRE'}
Case 'Confirmation indique les lignes cochées masquées' {Reset-Fixture;$r=New-TestRow;$script:table.ImportRow($r);$script:table.DefaultView.RowFilter="Nom_du_PC = 'PC-INVISIBLE'";$text=Get-PestoPreflightConfirmationText @($script:table.Rows);Assert-True ($text -match '1 ligne\(s\) cochée\(s\) sont masquées')}
Case 'Rapport HTML encode les valeurs et masque les secrets' {
    Reset-Fixture;$r=New-TestRow;$r.Reference='<script>alert(1)</script>';$r.Message='password=private-secret';$r.Statut='SIMULÉ';$r.Mode_Resultat='SIMULATION'
    $html=New-PestoQueueReportHtml @($r) $script:DOMAINE $script:DC 'RC5' 'RÉEL'
    Assert-True ($html -notmatch '<script>');Assert-True ($html.Contains('&lt;script&gt;'));Assert-True ($html -notmatch 'private-secret');Assert-True ($html -match 'SIMULATION');Assert-True ($html -match "default-src 'none'")
}
Case 'Rapport vide et absence de ressource distante' {Reset-Fixture;$html=New-PestoQueueReportHtml @() $script:DOMAINE $script:DC 'RC5' 'RÉEL';Assert-True ($html -match '0 ligne\(s\)');Assert-True ($html -notmatch '(?i)(src|href)\s*=')}
Case 'Conseil partiel ne préconise pas un second renommage' {Assert-True ((Get-PestoResultGuidance '89') -match 'pas une nouvelle action de renommage')}
$script:TempState=Join-Path ([IO.Path]::GetTempPath()) ('Pesto-RC5-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($script:TempState)
try {
    Case 'Historique borné à 100 et sans objet de credential' {
        Reset-Fixture;$entries=@(1..100|ForEach-Object{[pscustomobject]@{RunId='old-'+$_;Mode='RÉEL';Utc='2026-01-01T00:00:00Z';Total=1;Ok=1;Failed=0;NotStarted=0;Locked=$false}})
        $path=Join-Path $script:TempState 'history-v1.json';Write-PestoAtomicText $path (([ordered]@{Schema=1;Domain=$script:DOMAINE;Entries=$entries})|ConvertTo-Json -Depth 5)
        $state=[pscustomobject]@{RunId='current';Mode='SIMULATION';Total=3;OkCount=2;KoCount=1;CancelCount=0;Credential='NEVER-SERIALIZE'}
        Save-PestoRunHistory $state;$text=[IO.File]::ReadAllText($path);$d=$text|ConvertFrom-Json;Assert-Equal @($d.Entries).Count 100;Assert-Equal $d.Entries[-1].Mode 'SIMULATION';Assert-True ($text -notmatch 'NEVER-SERIALIZE')
        Save-PestoRunHistory $state;$d=Get-Content $path -Raw|ConvertFrom-Json;Assert-Equal @($d.Entries|Where-Object{$_.RunId -eq 'current'}).Count 1
    }
    Case 'Historique corrompu non écrasé' {
        $path=Join-Path $script:TempState 'history-v1.json';Write-PestoAtomicText $path 'NOT JSON';Assert-Throws {Save-PestoRunHistory ([pscustomobject]@{RunId='new'})};Assert-Equal ([IO.File]::ReadAllText($path)) 'NOT JSON'
    }
}finally{if(Test-Path -LiteralPath $script:TempState){Remove-Item -LiteralPath $script:TempState -Recurse -Force}}
Case 'Gabarit de lot construit par le moteur WPF sans afficher une fenêtre' {
    $raw=[IO.File]::ReadAllText([IO.Path]::GetFullPath($SourcePath));$match=[regex]::Match($raw,'(?ms)^\s*\[xml\]\$bulkXaml=@''\r?\n(.*?)^''@')
    Assert-True $match.Success
    [xml]$x=$match.Groups[1].Value;$w=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($x))
    foreach($n in @('Sources','Reference','KeepType','Prepare','Apply','Preview','Status','Context')){Assert-True ($null -ne $w.FindName($n))}
    Assert-Equal $w.FindName('Apply').IsEnabled $false
    $w.Close()
}
$failed=@($results|Where-Object{-not $_.Passed})
$report=[ordered]@{Suite='Pesto RC5 Pilotage';Utc=[DateTime]::UtcNow.ToString('o');PowerShell=$PSVersionTable.PSVersion.ToString();SourceHash=(Get-FileHash -LiteralPath $SourcePath -Algorithm SHA256).Hash;Total=$results.Count;Passed=$results.Count-$failed.Count;Failed=$failed.Count;Tests=$results.ToArray();Scope='Fonctions extraites, DataView réel, WPF non affiché, mocks AD, fichiers temporaires. Aucun test AD/UAC/poste réel.'}
$report|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $ReportPath -Encoding UTF8
Write-Host "$($report.Passed)/$($report.Total) cas réussis. Rapport : $ReportPath"
if($failed.Count){throw "$($failed.Count) test(s) en échec."}
