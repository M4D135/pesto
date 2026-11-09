#requires -Version 5.1
[CmdletBinding()]
param([string]$WadPath='',[string]$ReportPath='')
# Windows PowerShell 5.1 : $PSScriptRoot est vide dans les valeurs par défaut des paramètres (vu le 03/10).
if(-not $WadPath){$WadPath=Join-Path $PSScriptRoot '..\wad'}
if(-not $ReportPath){$ReportPath=Join-Path $PSScriptRoot 'windows-test-results.json'}
$ErrorActionPreference='Stop';Set-StrictMode -Off
. (Join-Path $WadPath 'Pesto-Contracts.ps1')
Add-Type -AssemblyName System.Data
# Ne PAS dot-sourcer le moteur : seules ses définitions de fonctions sont chargées.
# Tous les points de mutation utilisés ci-dessous sont remplacés par des mocks locaux.
# Les fonctions testées sont réparties dans les modules de wad/ : un seul fichier faisait
# mourir le banc au chargement sur des fonctions qui existent pourtant. Premier gagnant :
# les seuls doublons du produit sont des mocks (Write-Log, Show-MsgWarning…) redéfinis plus bas.
$defs=@{};$parseErrors=@();$sourceHashes=@()
foreach($file in (Get-ChildItem -LiteralPath ([IO.Path]::GetFullPath($WadPath)) -Filter '*.ps1' -File | Where-Object{$_.Name -ne 'Pesto.Engine.Runtime.ps1'} | Sort-Object Name)){
    $tokens=$null;$fileErrors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$fileErrors)
    if($fileErrors.Count){throw (($fileErrors|ForEach-Object{"$($file.Name):$($_.Extent.StartLineNumber): $($_.Message)"})-join "`n")}
    $parseErrors+=@($fileErrors)
    $sourceHashes+=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    foreach($node in $ast.EndBlock.Statements){
        if($node -is [Management.Automation.Language.FunctionDefinitionAst] -and -not $defs.ContainsKey($node.Name)){$defs[$node.Name]=$node.Extent.Text}
    }
}
# Le banc ne porte plus sur un seul fichier : l'empreinte du rapport couvre donc tout
# ce qui a ete parse, dans l'ordre de chargement.
$sourceHash=[BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes(($sourceHashes -join '')))).Replace('-','')
# Dependants directs des fonctions ci-dessous, absents de la liste depuis leur depart de
# Pesto-Core.ps1 : sans eux un cas echoue en « terme non reconnu » au lieu de tester quoi
# que ce soit. Aucun n'appelle l'exterieur sans passer par un mock defini plus bas.
$load=@('New-PestoQueueMonitor','Publish-PestoWorkerLog','Set-PestoWorkerStage','Assert-PestoWorkerMayContinue','Set-PestoQueueCancellationFence','Receive-PestoQueueEvents','Get-PestoQueueActivityText','Test-PestoQueueWorkerStillActive','Convert-Value-TF','Test-PestoDnsName','Split-PestoDistinguishedName','Get-PestoParentDN','Get-PestoDomainFromDN','Test-PestoDNWithinScope','ConvertTo-PestoRdnValue',
 'Test-PestoComputerName','Test-PestoGeneratedComputerName','Test-PestoOUPath','Test-PestoOUInConfiguredScope','Test-QueueRowSafe','Test-PestoConfirmedChange',
 'Protect-PestoLogText','Write-PestoAtomicText','ConvertTo-PestoSafeCsvCell','Get-PestoTaskArgument','Get-PestoSchtasksTransportArgs',
 'New-ActionResult','New-PestoRunOnceTaskXml','Get-ADParams','Get-PestoIdentityChangeReason','Find-ADComputerByName','Get-ComputerOU','Assert-PestoTargetNameAvailable','RenameComputer','MoveComputer','AddToDomain',
 'New-QueueTable','Set-PestoQueueRowResult','Test-CfgValid','Get-PestoTaskRunResult','Release-PestoComObject','Invoke-PestoSchtasks',
 'Add-LogLine','Assert-PestoClosedObject','Assert-PestoTaskDefinition','ConvertTo-PestoNameParts',
 'ConvertTo-PestoPolicy','Get-PestoManagedPolicy','Merge-PestoManagedPolicy','ConvertTo-PestoTaskFailureCode','Get-PestoDomainIdentityWarning','Get-PestoNameSiteCode','Get-PestoNativeFailureCode',
 'Get-PestoOutcome','Get-PestoRenameMoveDecision','Get-PestoSiteContainerDN','Get-PestoTaskDefinitionHash','Get-PestoWindowsAuthIdentity',
 'Invoke-PestoReadRetry','Get-PestoReadFailure','Get-PestoNativeGuidance','Invoke-PestoWindowsLocalRename','Set-PestoEffect','Set-PestoInitialObservation','Set-PestoJoinNativeStatus',
 'Set-PestoTaskEvidence','Test-PestoJoinIntervention','ConvertTo-PestoObservationSnapshot','Assert-PestoObservationSnapshot','Assert-PestoJoinEvidence','Test-PestoPropertyPresent')
foreach($n in $load){if(-not $defs.ContainsKey($n)){throw "Fonction absente : $n"};. ([scriptblock]::Create($defs[$n]))}
function Get-PestoManagedPolicy {[pscustomobject]@{Values=[pscustomobject]@{};Configured=$false;Source='test'}}
$results=[Collections.Generic.List[object]]::new();$oldComputerName=$env:COMPUTERNAME
function Assert-True {param($Value,[string]$Message='Condition non satisfaite.');if($Value -ne $true){throw $Message}}
function Assert-Equal {param($Actual,$Expected);if($Actual -cne $Expected){throw "Attendu [$Expected], obtenu [$Actual]."}}
function Assert-Throws {param([scriptblock]$Body);$thrown=$false;try{& $Body}catch{$thrown=$true};if(-not $thrown){throw 'Une exception était attendue.'}}
function Case {param([string]$Name,[scriptblock]$Body);$watch=[Diagnostics.Stopwatch]::StartNew();try{& $Body;$results.Add([pscustomobject]@{Name=$Name;Passed=$true;Error='';Ms=$watch.ElapsedMilliseconds});Write-Host "OK  $Name"}catch{$results.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message;Ms=$watch.ElapsedMilliseconds});Write-Host "KO  $Name : $($_.Exception.Message)"}}
function Get-ADObject {[CmdletBinding()]param($LDAPFilter,$Properties,$ResultSetSize,$Server,$Credential);@()}
function Write-Log {param($Message,$Level,$Err,$Context)}
# L'identité est une donnée de la fixture ; ne pas interroger le jeton Windows de l'hôte.
function Get-PestoWindowsAuthIdentity {return [pscustomobject]@{Name='EXAMPLE\test';IsDomainUser=$true;IsAdministrator=$true}}
function Show-MsgWarning {param($Message,$Title)}
function Test-PestoIsAdministrator {return $script:FakeIsAdmin}
# Porte d'observation prealable a tout renommage (Assert-PestoRenameTarget, Pesto-Safety.ps1).
# Elle exige Get-PestoPostObservation : session CIM distante, registre distant et lecture AD
# reelles, hors de portee d'un harnais sans bureau. La suite la remplace par un enregistreur,
# comme elle le fait deja pour Test-PestoIsAdministrator et les cmdlets AD. Les deux cas ajoutes
# plus bas verrouillent le contrat vu de RenameComputer (appelee avant toute mutation, refus rendu
# en 96 sans aucun appel). Limite assumée et mesuree le 11/10/2026 : aucune suite du depot n'exerce
# le corps reel de cette porte, ce mock ne prouve donc que son branchement, pas son contenu.
function Assert-PestoRenameTarget {[CmdletBinding()]param([string]$ComputerName);$script:GateCalls++;$script:GateSawMutations=$script:DsregCalls+$script:RenameCalls;if($script:GateThrows){throw 'MOCK cible non confirmée.'}}
# Couche « reçu d'intervention » et journal : Set-PestoEffect / Set-PestoInitialObservation les
# appellent et elles écrivent normalement un JSON sur disque. Enregistreurs, aucune écriture ;
# même forme que le harnais de Run-StabilisationTests.ps1 (seule suite de la famille à tourner).
function Write-PestoIntervention {param($Receipt);if($script:FailInterventionWrite -or ($script:FailRenameConfirmedWrite -and $Receipt.Rename -eq 'Confirmed')){throw 'Mock reçu indisponible'};$script:WrittenInterventions.Add(($Receipt|ConvertTo-Json -Depth 12|ConvertFrom-Json));if($script:CancelOnRenameReceipt -and $Receipt.Rename -eq 'Requested'){$script:PestoQueueMonitor.CancelRequested=$true}}
function Add-PestoInterventionEvent {param($Receipt,$Stage,$State)}
function Write-PestoJoinReceipt {param($Receipt);$script:WrittenInterventions.Add($Receipt)}
function Get-PestoInterventionRoot {return 'C:\PestoTest-run\harnais-engine'}
function Write-PestoAuditQueued {param($Message,$Level,$Err,$Context)}
function Write-AuditLine {param($Message,$Level,$Err,$Context)}
function Invoke-PestoElevatedDomainJoin {throw 'Test refusé : élévation réelle interdite.'}
function Invoke-PestoElevatedLocalChange {throw 'Test refusé : élévation réelle interdite.'}
function Invoke-PestoHybridRenameRepair {throw 'Test refusé : réparation Entra réelle interdite.'}
function Invoke-PestoDsregLeaveBeforeRename {
    param($ComputerName)
    $script:DsregCalls++;$script:CallOrder.Add('dsreg')
    return New-ActionResult $script:DsregResult 'Preparation Entra factice, aucun processus dsregcmd lance.'
}
function Invoke-RenameComputerTaskFallback {param($Computername,$NewName);$script:FallbackCalls++;return New-ActionResult 20 'MOCK fallback'}
function Get-PestoJoinLocalStatus {
    $script:LocalForJoin=$true;$script:JoinLocalReads++
    $snapshot=$script:JoinLocal|ConvertTo-Json|ConvertFrom-Json
    if($script:JoinLocalReads -gt 1 -and $script:AfterRenameDrift){$snapshot.($script:AfterRenameDrift)=$script:AfterRenameValue}
    return $snapshot
}
function Reset-Fakes {
    $env:COMPUTERNAME='OLD-PC';$script:LocalForJoin=$false;$script:JoinLocalReads=0;$script:AfterRenameDrift='';$script:AfterRenameValue=$null
    $script:JoinLocal=[pscustomobject]@{Computer='OLD-PC';ActiveName='OLD-PC';ConfiguredName='OLD-PC';PartOfDomain=$false;PendingRename=$false;Admin=$true;DomainRole=0;Domain='WORKGROUP';MachineId='4b008d30-8c02-4894-a829-d3d692012eca';BootUtc='2026-01-01T08:00:00Z'}
    $script:CancelOnRenameReceipt=$false;$script:FailInterventionWrite=$false;$script:FailRenameConfirmedWrite=$false;$script:RenameSawReceipt='';$script:CancelAfterRename=$false;$script:LastJoinArgs=@{};$script:JoinNativeCode=$null
    $script:AllowPrecreatedJoin=$false;$script:ExpectedJoinAccountGuid='';$script:PestoQueueMonitor=New-PestoQueueMonitor 'OLD-PC'
    $script:PestoDomainIdentityWarned=$false
    $script:FakeIsAdmin=$true;$script:DsregCalls=0;$script:DsregResult=20;$script:CallOrder=[Collections.Generic.List[string]]::new()
    $script:ExpectedObjectGuid='';$script:ExpectedSourceOU='';$script:SIM=$false;$script:GUI=$false;$script:SimOn=$false;$script:INDOMAIN=$true;$script:PRD=$true
    $script:DOMAINE='example.local';$script:DC='dc01.example.local';$script:PREFIXE='111301'
    $script:OU=@{ROOT='OU=Postes,DC=example,DC=local';PREPROD='OU=Transit,OU=Postes,DC=example,DC=local'}
    $script:OUV=@{Demo='OU=Sites,OU=Postes,DC=example,DC=local'}
    $script:CLEAR_PROTECTION=$true;$script:ALLOW_HYBRID_REPAIR=$false
    $script:cred=[Management.Automation.PSCredential]::new('EXAMPLE\test',(ConvertTo-SecureString 'test-only-not-a-real-secret' -AsPlainText -Force))
    $script:FakeName='OLD-PC';$script:FakeOU=$script:OU.ROOT;$script:FakeGuid=[Guid]'12345678-1111-2222-3333-123456789012'
    # Set-PestoEffect et Set-PestoInitialObservation refusent toute commande sans reçu d'intervention,
    # et exigent que le plan porte le GUID réellement observé (mesuré le 11/10/2026 : sans ça tout
    # déplacement rend 96 « Le plan confirmé ne possède pas l'identité AD observée »). Un PSCustomObject
    # n'accepte pas l'ajout d'une propriété par affectation : le reçu du harnais doit donc porter
    # lui-même chaque propriété que le produit assigne (Schema, LastStage, UpdatedUtc, et les sept
    # effets autorisés par Set-PestoEffect), sinon le produit lève en plein chemin testé.
    $script:ActiveIntervention=[pscustomobject]@{OperationId='11111111111111111111111111111111';Schema=1
        Plan=[pscustomobject]@{Objet_GUID=$script:FakeGuid.ToString()}
        Phase='Running';Baseline=$null;JoinEvidence=$null;Tasks=@()
        Entra='NotRequested';Rename='NotRequested';Move='NotRequested';Protection='NotChanged'
        ResultCode=0;ResultMessage='';UpdatedUtc='';LastStage=''
        TargetMachineId='';TargetOUGuid='';InitialProtection=$false}
    $script:WrittenInterventions=[Collections.Generic.List[object]]::new()
    $script:GateCalls=0;$script:GateThrows=$false;$script:GateSawMutations=-1
    $script:FakeProtected=$true;$script:MoveError='';$script:ReadFails=$false;$script:RestoreFails=$false
    $script:RenameResult='success';$script:RenameError='';$script:JoinResult='success';$script:JoinError='';$script:RenameNativeCode=$null
    $script:RenameCalls=0;$script:MoveCalls=0;$script:ProtectionCalls=0;$script:JoinCalls=0;$script:FallbackCalls=0
    # Assert-PestoTaskDefinition compare l'Xml de la tâche relancée à l'empreinte consignée au
    # lancement : sans reçu de tâche la relecture du résultat lève et Get-PestoTaskRunResult rend
    # 267009 au lieu de tester quoi que ce soit. Consigné par la fonction produit elle-même.
    $script:TaskXml='<Task><Version>1.2</Version><Actions><Exec><Command>C:\Pesto\Pesto.exe</Command></Exec></Actions></Task>'
    Set-PestoTaskEvidence -Computer 'OLD-PC' -Name '\Pesto_Test' -Phase Started -DefinitionHash (Get-PestoTaskDefinitionHash $script:TaskXml)
    $script:LastRenameArgs=@{};$script:MoveIdentities=@();$script:TaskQueryCount=0
}
function Get-FakeADObject {
    # userAccountControl : MoveComputer refuse toute cible dont le rôle AD n'est pas confirmé et
    # exclut les contrôleurs (8192). 4096 = poste de travail ordinaire (mesuré le 11/10/2026 : sans
    # ce champ tout déplacement rendait 99 « Rôle AD de la cible non confirmé »).
    return [pscustomobject]@{Name=$script:FakeName;ObjectGUID=$script:FakeGuid;DistinguishedName="CN=$($script:FakeName),$($script:FakeOU)";ProtectedFromAccidentalDeletion=$script:FakeProtected;userAccountControl=4096}
}
function Get-ADComputer {
    [CmdletBinding()]param($Identity,$Properties,$LDAPFilter,$ResultSetSize,$Server,$Credential)
    if($script:ReadFails){throw 'MOCK lecture AD indisponible.'}
    if($LDAPFilter){if($LDAPFilter -match '\(name=([^\)]+)\)' -and $Matches[1] -ieq $script:FakeName){return Get-FakeADObject};return $null}
    if([string]$Identity -ieq $script:FakeName -or [string]$Identity -eq [string]$script:FakeGuid){return Get-FakeADObject}
    throw "MOCK poste absent : $Identity"
}
# -Properties et ObjectGUID : MoveComputer lit le GUID de la destination avant toute écriture et
# refuse un GUID absent (mesuré le 11/10/2026 : sans lui tout déplacement rendait 99).
function Get-ADOrganizationalUnit {[CmdletBinding()]param($Identity,$Properties,$Server,$Credential);return [pscustomobject]@{DistinguishedName=$Identity;ObjectGUID=[Guid]'aaaaaaaa-1111-2222-3333-123456789012'}}
function Set-ADObject {
    [CmdletBinding()]param($Identity,[bool]$ProtectedFromAccidentalDeletion,$Server,$Credential)
    $script:ProtectionCalls++;Assert-Equal ([string]$Identity) ([string]$script:FakeGuid)
    if($ProtectedFromAccidentalDeletion -and $script:RestoreFails){throw 'MOCK restauration refusée.'}
    $script:FakeProtected=$ProtectedFromAccidentalDeletion
}
function Move-ADObject {
    [CmdletBinding()]param($Identity,$TargetPath,$Server,$Credential)
    $script:MoveCalls++;$script:MoveIdentities+=,[string]$Identity
    if($script:MoveError){throw $script:MoveError}
    $script:FakeOU=$TargetPath
}
function Rename-Computer {
    [CmdletBinding()]param($ComputerName,$NewName,$LocalCredential,$DomainCredential,[switch]$Force,[switch]$PassThru)
    $script:RenameCalls++;$script:CallOrder.Add('rename');$script:LastRenameArgs=@{};foreach($k in $PSBoundParameters.Keys){$script:LastRenameArgs[$k]=$PSBoundParameters[$k]}
    if($script:LocalForJoin){$script:RenameSawReceipt=$script:WrittenInterventions[$script:WrittenInterventions.Count-1].Rename}
    if($script:RenameError){
        # Un refus Windows se distingue d'un resultat perdu par son code natif : Get-PestoNativeFailureCode
        # ne peut confirmer un refus (code 21) que si l'exception le porte. Une chaine nue rend 97, ce
        # qui est le comportement voulu du produit, pas un cas a faire passer en force.
        if($script:RenameNativeCode){throw [ComponentModel.Win32Exception]::new([int]$script:RenameNativeCode,$script:RenameError)}
        throw $script:RenameError
    }
    switch($script:RenameResult){
        'none'{return $null};'missing'{return [pscustomobject]@{Other=$true}};'string'{return [pscustomobject]@{HasSucceeded='true'}}
        'false'{return [pscustomobject]@{HasSucceeded=$false}}
        default{if($script:LocalForJoin){$script:JoinLocal.ConfiguredName=$NewName;$script:JoinLocal.PendingRename=$true;if($script:CancelAfterRename){$script:PestoQueueMonitor.CancelRequested=$true}}else{$script:FakeName=$NewName};return [pscustomobject]@{HasSucceeded=$true}}
    }
}
function Add-Computer {
    [CmdletBinding()]param($DomainName,$OUPath,$NewName,$Options,$Server,$Credential,[switch]$PassThru,[switch]$Force)
    $script:JoinCalls++;$script:CallOrder.Add('join');$script:LastJoinArgs=@{};foreach($k in $PSBoundParameters.Keys){$script:LastJoinArgs[$k]=$PSBoundParameters[$k]}
    if($script:JoinError){if($script:JoinNativeCode){throw [ComponentModel.Win32Exception]::new([int]$script:JoinNativeCode,$script:JoinError)};throw $script:JoinError}
    switch($script:JoinResult){'none'{return $null};'missing'{return [pscustomobject]@{Other=1}};'false'{return [pscustomobject]@{HasSucceeded=$false}};default{return [pscustomobject]@{HasSucceeded=$true}}}
}
# COM est remplacé pour les tests du polling : aucun Schedule.Service réel.
function New-PestoTaskService {
    param($ComputerName)
    $svc=[pscustomobject]@{}
    $svc|Add-Member ScriptMethod GetFolder {
        param($Path)
        $f=[pscustomobject]@{}
        $f|Add-Member ScriptMethod GetTask {
            param($Name)
            $script:TaskQueryCount++
            if($script:TaskQueryCount -eq 1){return [pscustomobject]@{State=4;LastRunTime=[DateTime]'2026-01-01';LastTaskResult=0;Xml=$script:TaskXml}}
            return [pscustomobject]@{State=3;LastRunTime=[DateTime]'2026-01-01';LastTaskResult=0;Xml=$script:TaskXml}
        }
        return $f
    }
    return $svc
}
Reset-Fakes
Case 'PS 5.1 : parsing natif du script complet' {Assert-Equal $parseErrors.Count 0}
foreach($v in @('true','TRUE','oui','1','on',$true)){Case "Booléen vrai : $v" {Assert-True (Convert-Value-TF $v -Strict)}}
foreach($v in @('false','FALSE','non','0','off',$false)){Case "Booléen faux : $v" {Assert-Equal (Convert-Value-TF $v -Strict) $false}}
Case 'Booléen inconnu strict refusé' {Assert-Throws {Convert-Value-TF 'peut-être' -Strict}}
Case 'Booléen inconnu non strict reste faux' {Assert-Equal (Convert-Value-TF 'erreur') $false}
Case 'DNS valide' {Assert-True (Test-PestoDnsName 'dc01.example.local')}
Case 'DNS sans label vide' {Assert-Equal (Test-PestoDnsName 'example..local') $false}
Case 'DNS label trop long refusé' {Assert-Equal (Test-PestoDnsName (('a'*64)+'.local')) $false}
Case 'Nom source court autorisé' {Assert-True (Test-PestoComputerName 'PC-1')}
Case 'Nom source injectable refusé' {Assert-Equal (Test-PestoComputerName 'PC;whoami') $false}
Case 'Nom source >15 refusé' {Assert-Equal (Test-PestoComputerName ('A'*16)) $false}
Case 'Nom généré conforme' {Assert-True (Test-PestoGeneratedComputerName 'S111301MA123001')}
Case 'Numéro 000 refusé' {Assert-Equal (Test-PestoGeneratedComputerName 'S111301MA123000') $false}
Case 'Mauvais préfixe refusé' {Assert-Equal (Test-PestoGeneratedComputerName 'S999999MA123001') $false}
Case 'DN OU valide' {Assert-True (Test-PestoOUPath 'OU=Paris,OU=Postes,DC=example,DC=local')}
Case 'DC avant OU refusé' {Assert-Equal (Test-PestoOUPath 'OU=A,DC=example,OU=B,DC=local') $false}
Case 'CN racine non OU refusé' {Assert-Equal (Test-PestoOUPath 'CN=Computers,DC=example,DC=local') $false}
Case 'Virgule échappée préservée dans le parent' {Assert-Equal (Get-PestoParentDN 'CN=PC\,1,OU=Postes,DC=example,DC=local') 'OU=Postes,DC=example,DC=local'}
Case 'DN malformé refusé' {Assert-Throws {Split-PestoDistinguishedName 'OU=A,,DC=local'}}
Case 'RDN multivalué refusé' {Assert-Equal (Test-PestoOUPath 'OU=A+CN=B,DC=local') $false}
Case 'Extraction domaine DN' {Assert-Equal (Get-PestoDomainFromDN 'OU=A,DC=EXAMPLE,DC=local') 'example.local'}
Case 'Suffixe par composants autorisé' {Assert-True (Test-PestoDNWithinScope 'OU=A,OU=Postes,DC=example,DC=local' @($script:OU.ROOT))}
Case 'Faux suffixe DN refusé' {Assert-Equal (Test-PestoDNWithinScope 'OU=PasPostes,DC=example,DC=local' @($script:OU.ROOT)) $false}
Case 'Virgule échappée ne crée pas un faux parent' {Assert-Equal (Test-PestoDNWithinScope 'OU=Malin\,OU=Postes,DC=example,DC=local' @($script:OU.ROOT)) $false}
Case 'Échappement de valeur OU' {Assert-Equal (ConvertTo-PestoRdnValue 'Paris, Centre') 'Paris\, Centre'}
Case 'Confirmation HasSucceeded=True booléen' {Assert-True (Test-PestoConfirmedChange ([pscustomobject]@{HasSucceeded=$true}))}
Case 'Confirmation chaîne true refusée' {Assert-Equal (Test-PestoConfirmedChange ([pscustomobject]@{HasSucceeded='true'})) $false}
Case 'Confirmation absente refusée' {Assert-Equal (Test-PestoConfirmedChange $null) $false}
Case 'Confirmation multiple refusée' {Assert-Equal (Test-PestoConfirmedChange @([pscustomobject]@{HasSucceeded=$true},[pscustomobject]@{HasSucceeded=$true})) $false}
# Sans guillemets, la fin de valeur est ambiguë : masquer le reste de la ligne.
Case 'Masquage du champ password non quote et de la fin de ligne' {Assert-Equal (Protect-PestoLogText 'password=abc user=test') 'password=********'}
Case 'Valeur password quotee conserve les champs suivants' {Assert-Equal (Protect-PestoLogText 'password="abc" user=test') 'password=******** user=test'}
Case 'Formule CSV neutralisée' {Assert-Equal (ConvertTo-PestoSafeCsvCell '=1+2') "'=1+2"}
Case 'Texte CSV ordinaire conservé' {Assert-Equal (ConvertTo-PestoSafeCsvCell 'PC-TEST') 'PC-TEST'}
Case 'Transport sans mot de passe en argument' {Assert-Equal ((Get-PestoSchtasksTransportArgs 'OLD-PC') -join '|') '/s|OLD-PC'}
Case 'Ancien transport secret bloqué avant COM' {$r=Invoke-PestoSchtasks -ArgList @('/run','/s','OLD-PC','/tn','\Pesto_Test','/p','test-only');Assert-True ($r.ExitCode -ne 0)}
Case 'Résultat tâche 0 en RUNNING pas encore réussi' {$script:TaskQueryCount=0;$r=Get-PestoTaskRunResult '\Pesto_Test' @('/s','OLD-PC') 3;Assert-Equal $r.ResultNum 0;Assert-True ($script:TaskQueryCount -ge 2)}
Case 'XML tâche à la demande sans trigger' {
    [xml]$x=New-PestoRunOnceTaskXml -Command 'test.exe' -Arguments 'A&B' -UserId 'EXAMPLE\test'
    Assert-Equal ([string]$x.Task.Actions.Exec.Arguments) 'A&B'
    Assert-Equal @($x.SelectNodes("//*[local-name()='Triggers']")).Count 0
}
Case 'Table : métadonnées et booléens par défaut' {$t=New-QueueTable;$r=$t.NewRow();Assert-Equal $r.Code '';Assert-Equal $r.Traiter $false;Assert-True $t.Columns.Contains('Horodatage')}
Case 'Ligne sans action refusée' {Reset-Fakes;Assert-True (@(Test-QueueRowSafe 'OLD-PC' '' '' $false $false).Count -gt 0)}
Case 'Ligne déplacement seul valide' {Reset-Fakes;Assert-Equal @(Test-QueueRowSafe 'OLD-PC' '' 'OU=A,OU=Postes,DC=example,DC=local' $false $true).Count 0}
Case 'Hors domaine interdit un autre poste' {Reset-Fakes;$script:INDOMAIN=$false;Assert-True (@(Test-QueueRowSafe 'NOT-LOCAL' 'S111301MA123001' $script:OU.ROOT $true $true).Count -gt 0)}
Case 'Porte d''observation consultee avant toute mutation' {
    Reset-Fakes;[void](RenameComputer 'OLD-PC' 'S111301MA123001')
    Assert-Equal $script:GateCalls 1
    Assert-Equal $script:GateSawMutations 0
}
Case 'Porte d''observation refusee : 96 et aucun appel de mutation' {
    Reset-Fakes;$script:GateThrows=$true;$r=RenameComputer 'OLD-PC' 'S111301MA123001'
    Assert-Equal $r.ExitCode 96;Assert-Equal $script:DsregCalls 0;Assert-Equal $script:RenameCalls 0;Assert-Equal $script:FallbackCalls 0
}
foreach($result in @('none','missing','string')){
    Case "Renommage résultat $result => indéterminé sans repli" {Reset-Fakes;$script:RenameResult=$result;$r=RenameComputer 'OLD-PC' 'S111301MA123001';Assert-Equal $r.ExitCode 97;Assert-Equal $script:FallbackCalls 0}
}
Case 'Renommage HasSucceeded=False => échec' {Reset-Fakes;$script:RenameResult='false';Assert-Equal (RenameComputer 'OLD-PC' 'S111301MA123001').ExitCode 21}
Case 'Renommage confirmé' {Reset-Fakes;Assert-Equal (RenameComputer 'OLD-PC' 'S111301MA123001').ExitCode 20}
Case 'Compte de domaine du login reutilise sans nouveau prompt' {
    Reset-Fakes;Assert-Equal (RenameComputer 'OLD-PC' 'S111301MA123001').ExitCode 20
    Assert-True ([object]::ReferenceEquals($script:LastRenameArgs.DomainCredential,$script:cred))
}
Case 'Ordre preserve : preparation Entra puis renommage' {
    Reset-Fakes;[void](RenameComputer 'OLD-PC' 'S111301MA123001')
    Assert-Equal ($script:CallOrder -join ',') 'dsreg,rename'
}
Case 'Preparation Entra echouee : pas de renommage' {
    Reset-Fakes;$script:DsregResult=21
    Assert-Equal (RenameComputer 'OLD-PC' 'S111301MA123001').ExitCode 21
    Assert-Equal $script:RenameCalls 0;Assert-Equal $script:DsregCalls 1
}
Case 'Preparation Entra incertaine : verrou, pas de renommage' {
    Reset-Fakes;$script:DsregResult=97
    Assert-Equal (RenameComputer 'OLD-PC' 'S111301MA123001').ExitCode 97;Assert-Equal $script:RenameCalls 0
}
Case 'Renommage distant sans credential : refus avant dsregcmd, aucun prompt natif' {
    Reset-Fakes;$script:cred=$null;$before=$env:COMPUTERNAME
    try {
        $env:COMPUTERNAME='TEST-OPERATOR'
        Assert-Equal (RenameComputer 'OLD-PC' 'S111301MA123001').ExitCode 96
        Assert-Equal $script:DsregCalls 0;Assert-Equal $script:RenameCalls 0
    } finally {$env:COMPUTERNAME=$before}
}
Case 'Perte des droits locaux : aucun helper UAC pendant action' {
    Reset-Fakes;$before=$env:COMPUTERNAME
    try{
        $env:COMPUTERNAME='OLD-PC';$script:FakeIsAdmin=$false
        Assert-Equal (RenameComputer 'OLD-PC' 'S111301MA123001').ExitCode 96
        Assert-Equal $script:DsregCalls 0;Assert-Equal $script:RenameCalls 0
    }finally{$env:COMPUTERNAME=$before}
}
Case 'Jonction non elevee : code 96 sans nouveau UAC' {
    Reset-Fakes;$script:FakeIsAdmin=$false
    Assert-Equal (AddToDomain $script:DC $script:DOMAINE $script:OU.ROOT 'S111301MA123001' $script:cred).ExitCode 96
    Assert-Equal $script:JoinCalls 0
}
Case 'Renommage RPC ambigu => arrêt sans repli' {Reset-Fakes;$script:RenameError='RPC server unavailable';Assert-Equal (RenameComputer 'OLD-PC' 'S111301MA123001').ExitCode 97;Assert-Equal $script:FallbackCalls 0}
Case 'Refus Entra apres preparation ne provoque pas de deuxieme tentative' {Reset-Fakes;$script:RenameError='Azure AD hostname update failed';$script:RenameNativeCode=5;Assert-Equal (RenameComputer 'OLD-PC' 'S111301MA123001').ExitCode 21;Assert-Equal $script:FallbackCalls 0}
Case 'Simulation renommage aucune mutation' {Reset-Fakes;$script:SIM=$true;Assert-Equal (RenameComputer 'OLD-PC' 'S111301MA123001').ExitCode 20;Assert-Equal $script:RenameCalls 0}
Case 'Renommage source hors périmètre interdit' {Reset-Fakes;$script:FakeOU='OU=Autres,DC=example,DC=local';Assert-Equal (RenameComputer 'OLD-PC' 'S111301MA123001').ExitCode 21;Assert-Equal $script:RenameCalls 0}
Case 'Renommage local sans ComputerName ni LocalCredential' {
    Reset-Fakes;$oldEnv=$env:COMPUTERNAME
    try{$env:COMPUTERNAME='OLD-PC';Assert-Equal (RenameComputer 'OLD-PC' 'S111301MA123001').ExitCode 20;Assert-Equal $script:LastRenameArgs.ContainsKey('ComputerName') $false;Assert-Equal $script:LastRenameArgs.ContainsKey('LocalCredential') $false}
    finally{$env:COMPUTERNAME=$oldEnv}
}
Case 'GUID source remplace : aucun renommage' {Reset-Fakes;$script:ExpectedObjectGuid='99999999-1111-2222-3333-123456789012';Assert-Equal (RenameComputer 'OLD-PC' 'S111301MA123001').ExitCode 21;Assert-Equal $script:RenameCalls 0}
Case 'OU source derivee : aucun renommage' {Reset-Fakes;$script:ExpectedSourceOU='OU=A,OU=Postes,DC=example,DC=local';Assert-Equal (RenameComputer 'OLD-PC' 'S111301MA123001').ExitCode 21;Assert-Equal $script:RenameCalls 0}
Case 'GUID source remplace : aucun deplacement ni protection' {Reset-Fakes;$script:ExpectedObjectGuid='99999999-1111-2222-3333-123456789012';Assert-Equal (MoveComputer 'OLD-PC' 'OU=A,OU=Postes,DC=example,DC=local').ExitCode 31;Assert-Equal $script:MoveCalls 0;Assert-Equal $script:ProtectionCalls 0}
Case 'OU source derivee : aucun deplacement' {Reset-Fakes;$script:ExpectedSourceOU='OU=B,OU=Postes,DC=example,DC=local';Assert-Equal (MoveComputer 'OLD-PC' 'OU=A,OU=Postes,DC=example,DC=local').ExitCode 31;Assert-Equal $script:MoveCalls 0}
Case 'Déplacement utilise GUID et restaure protection' {Reset-Fakes;$r=MoveComputer 'OLD-PC' 'OU=A,OU=Postes,DC=example,DC=local';Assert-Equal $r.ExitCode 30;Assert-True $script:FakeProtected;Assert-Equal $script:ProtectionCalls 2;Assert-Equal $script:MoveIdentities[0] ([string]$script:FakeGuid)}
Case 'Déplacement déjà dans OU => sans écriture' {Reset-Fakes;Assert-Equal (MoveComputer 'OLD-PC' $script:OU.ROOT).ExitCode 33;Assert-Equal $script:MoveCalls 0}
# Attendu aligné sur le contrat écrit du produit (mesuré le 11/10/2026) : une fois Move-ADObject
# appelé, un refus reste INCERTAIN (97) même si la relecture par GUID montre l'objet encore dans
# l'OU source — le commentaire de MoveComputer le justifie par un effet différé possible. Le 31
# « refusé » n'est rendu que si l'écriture n'a jamais été engagée ; ce chemin est couvert par
# « Déplacement protégé sans autorisation => refus ». L'assertion utile, la restauration de la
# protection dans le finally, est conservée.
Case 'Déplacement engagé puis refusé : 97 et protection restaurée' {Reset-Fakes;$script:MoveError='Access is denied';Assert-Equal (MoveComputer 'OLD-PC' 'OU=A,OU=Postes,DC=example,DC=local').ExitCode 97;Assert-True $script:FakeProtected}
Case 'Déplacement RPC non confirmé => code 97 sans relance' {Reset-Fakes;$script:MoveError='The RPC server is unavailable';Assert-Equal (MoveComputer 'OLD-PC' 'OU=A,OU=Postes,DC=example,DC=local').ExitCode 97;Assert-Equal $script:MoveCalls 1}
Case 'Échec reprotection => code 32 et non succès' {Reset-Fakes;$script:RestoreFails=$true;Assert-Equal (MoveComputer 'OLD-PC' 'OU=A,OU=Postes,DC=example,DC=local').ExitCode 32}
Case 'Déplacement protégé sans autorisation => refus' {Reset-Fakes;$script:CLEAR_PROTECTION=$false;Assert-Equal (MoveComputer 'OLD-PC' 'OU=A,OU=Postes,DC=example,DC=local').ExitCode 31;Assert-Equal $script:ProtectionCalls 0}
Case 'Simulation déplacement aucune écriture' {Reset-Fakes;$script:SIM=$true;Assert-Equal (MoveComputer 'OLD-PC' 'OU=A,OU=Postes,DC=example,DC=local').ExitCode 30;Assert-Equal $script:MoveCalls 0;Assert-Equal $script:ProtectionCalls 0}
Case 'OU cible hors périmètre refusée' {Reset-Fakes;Assert-Equal (MoveComputer 'OLD-PC' 'OU=A,DC=other,DC=local').ExitCode 31;Assert-Equal $script:MoveCalls 0}
foreach($result in @('none','missing')){Case "Jonction résultat $result => code 97" {Reset-Fakes;$script:JoinResult=$result;Assert-Equal (AddToDomain $script:DC $script:DOMAINE $script:OU.ROOT 'S111301MA123001' $script:cred).ExitCode 97}}
Case 'Jonction HasSucceeded=False après nom préparé => code 97' {Reset-Fakes;$script:JoinResult='false';Assert-Equal (AddToDomain $script:DC $script:DOMAINE $script:OU.ROOT 'S111301MA123001' $script:cred).ExitCode 97}
Case 'Jonction confirmée => code 10' {Reset-Fakes;Assert-Equal (AddToDomain $script:DC $script:DOMAINE $script:OU.ROOT 'S111301MA123001' $script:cred).ExitCode 10}
Case 'Jonction serveur égal domaine refusée' {Reset-Fakes;Assert-Equal (AddToDomain 'example.local' $script:DOMAINE $script:OU.ROOT 'S111301MA123001' $script:cred).ExitCode 11;Assert-Equal $script:JoinCalls 0}
Case 'Jonction prépare le nom local puis utilise JoinWithNewName sans ancien compte AD' {
 Reset-Fakes;$r=AddToDomain $script:DC $script:DOMAINE $script:OU.ROOT 'S111301MA123001' $script:cred
 Assert-Equal $r.ExitCode 10;Assert-Equal ($script:CallOrder -join ',') 'rename,join';Assert-Equal $script:FakeName 'OLD-PC'
 Assert-Equal $script:ActiveIntervention.Rename 'Confirmed';Assert-Equal $script:JoinLocal.ConfiguredName 'S111301MA123001'
 Assert-Equal ($script:LastJoinArgs.Options -join ',') 'JoinWithNewName,AccountCreate';Assert-True (-not $script:LastJoinArgs.ContainsKey('NewName'))
 foreach($key in @('ComputerName','DomainCredential','LocalCredential','Restart')){Assert-True (-not $script:LastRenameArgs.ContainsKey($key))}
 Assert-True (-not $script:LastJoinArgs.ContainsKey('Restart'));Assert-Equal $script:RenameSawReceipt 'Requested'
}
Case 'Jonction nom déjà actif ne lance pas de renommage' {
 Reset-Fakes;$env:COMPUTERNAME='S111301MA123001';foreach($k in @('Computer','ActiveName','ConfiguredName')){$script:JoinLocal.$k=$env:COMPUTERNAME}
 Assert-Equal (AddToDomain $script:DC $script:DOMAINE $script:OU.ROOT $env:COMPUTERNAME $script:cred).ExitCode 10;Assert-Equal $script:RenameCalls 0;Assert-Equal $script:JoinCalls 1
}
Case 'Jonction refusée sans renommage reste refus confirmé' {
 Reset-Fakes;$env:COMPUTERNAME='S111301MA123001';foreach($k in @('Computer','ActiveName','ConfiguredName')){$script:JoinLocal.$k=$env:COMPUTERNAME};$script:JoinResult='false'
 Assert-Equal (AddToDomain $script:DC $script:DOMAINE $script:OU.ROOT $env:COMPUTERNAME $script:cred).ExitCode 11;Assert-Equal $script:RenameCalls 0
}
foreach($result in @('false','none','missing','string')){Case "Préparation locale $result bloque tout ajout AD" {
 Reset-Fakes;$script:RenameResult=$result;Assert-Equal (AddToDomain $script:DC $script:DOMAINE $script:OU.ROOT 'S111301MA123001' $script:cred).ExitCode 97;Assert-Equal $script:JoinCalls 0;Assert-Equal $script:RenameCalls 1
}}
Case 'Exception du renommage ne lance jamais Add-Computer' {Reset-Fakes;$script:RenameError='Mock RPC';Assert-Equal (AddToDomain $script:DC $script:DOMAINE $script:OU.ROOT 'S111301MA123001' $script:cred).ExitCode 97;Assert-Equal $script:JoinCalls 0}
foreach($field in @('PartOfDomain','PendingRename')){Case "État préalable $field bloque les deux mutations" {Reset-Fakes;$script:JoinLocal.$field=$true;Assert-Equal (AddToDomain $script:DC $script:DOMAINE $script:OU.ROOT 'S111301MA123001' $script:cred).ExitCode 96;Assert-Equal $script:RenameCalls 0;Assert-Equal $script:JoinCalls 0}}
foreach($field in @('MachineId','BootUtc','ConfiguredName','ActiveName','PartOfDomain','Computer')){Case "Dérive $field après préparation bloque la jonction" {
 Reset-Fakes;$script:AfterRenameDrift=$field;$script:AfterRenameValue=if($field -eq 'PartOfDomain'){$true}else{'CHANGED'}
 Assert-Equal (AddToDomain $script:DC $script:DOMAINE $script:OU.ROOT 'S111301MA123001' $script:cred).ExitCode 97;Assert-Equal $script:JoinCalls 0
}}
Case 'Nom CIM nouveau accepté si registres et identité concordent' {Reset-Fakes;$script:AfterRenameDrift='Computer';$script:AfterRenameValue='S111301MA123001';Assert-Equal (AddToDomain $script:DC $script:DOMAINE $script:OU.ROOT 'S111301MA123001' $script:cred).ExitCode 10}
Case 'Reçu de préparation indisponible empêche les deux mutations' {Reset-Fakes;$script:FailInterventionWrite=$true;Assert-Equal (AddToDomain $script:DC $script:DOMAINE $script:OU.ROOT 'S111301MA123001' $script:cred).ExitCode 96;Assert-Equal $script:RenameCalls 0;Assert-Equal $script:JoinCalls 0}
Case 'Annulation pendant reçu initial empêche la première commande' {Reset-Fakes;$script:CancelOnRenameReceipt=$true;Assert-Equal (AddToDomain $script:DC $script:DOMAINE $script:OU.ROOT 'S111301MA123001' $script:cred).ExitCode 96;Assert-Equal $script:RenameCalls 0;Assert-Equal $script:JoinCalls 0}
Case 'Reçu après nom préparé indisponible bloque ajout AD et reste incertain' {Reset-Fakes;$script:FailRenameConfirmedWrite=$true;Assert-Equal (AddToDomain $script:DC $script:DOMAINE $script:OU.ROOT 'S111301MA123001' $script:cred).ExitCode 97;Assert-Equal $script:RenameCalls 1;Assert-Equal $script:JoinCalls 0}
Case 'Annulation après préparation conserve le nom et bloque ajout AD' {Reset-Fakes;$script:CancelAfterRename=$true;Assert-Equal (AddToDomain $script:DC $script:DOMAINE $script:OU.ROOT 'S111301MA123001' $script:cred).ExitCode 97;Assert-Equal $script:JoinCalls 0;Assert-Equal $script:JoinLocal.ConfiguredName 'S111301MA123001'}
foreach($native in @(5,1326,2732)){Case "Refus natif $native après renommage reste partiel 97" {Reset-Fakes;$script:JoinError='Mock refus';$script:JoinNativeCode=$native;Assert-Equal (AddToDomain $script:DC $script:DOMAINE $script:OU.ROOT 'S111301MA123001' $script:cred).ExitCode 97;Assert-Equal $script:JoinCalls 1;Assert-Equal $script:ActiveIntervention.Rename 'Confirmed'}}
Case 'Helper élevé refuse jonction avant tout effet' {
 Reset-Fakes;& ([scriptblock]::Create($defs['Invoke-PestoElevatedLocalChange']+"`n"+'$result=Invoke-PestoElevatedLocalChange -Action Join;Assert-Equal $result.ExitCode 96'))
 & ([scriptblock]::Create($defs['New-PestoElevatedHelperScript']+"`n"+'$helper=New-PestoElevatedHelperScript -SettingsB64 "e30=";Assert-True (-not ($helper -match "Add-Computer"))'))
}
Case 'Configuration exemple cohérente' {$cfg=Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\wad\cfg.example.json') -Raw -Encoding UTF8|ConvertFrom-Json;Assert-Equal @(Test-CfgValid $cfg).Count 0}
Case 'Domaine / DN incohérents refusés' {$cfg=Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\wad\cfg.example.json') -Raw -Encoding UTF8|ConvertFrom-Json;$cfg.CONF[0].Domaine='wrong.local';Assert-True (@(Test-CfgValid $cfg).Count -gt 0)}
Case 'Buffer énorme refusé sans exception de conversion' {$cfg=Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\wad\cfg.example.json') -Raw -Encoding UTF8|ConvertFrom-Json;$cfg.CONF[0].Buffer='999999999999999999999999999999999999999';Assert-True (@(Test-CfgValid $cfg).Count -gt 0)}
Case 'Faux mode hors domaine interdit en réel' {$cfg=Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\wad\cfg.example.json') -Raw -Encoding UTF8|ConvertFrom-Json;$cfg.DEBUG.GUI='false';$cfg.DEBUG.Simulation='false';$cfg.DEBUG.HorsDomaine='true';Assert-True (@(Test-CfgValid $cfg).Count -gt 0)}
Case 'Écriture atomique et sauvegarde du précédent' {
    $dir=Join-Path ([IO.Path]::GetTempPath()) ('Pesto-Test-'+[Guid]::NewGuid().ToString('N'))
    try{$p=Join-Path $dir 'cfg.json';Write-PestoAtomicText $p 'premier';Write-PestoAtomicText $p 'deuxième' -Backup;Assert-Equal ([IO.File]::ReadAllText($p)) 'deuxième';Assert-Equal ([IO.File]::ReadAllText($p+'.bak')) 'premier'}
    finally{if(Test-Path -LiteralPath $dir){Remove-Item -LiteralPath $dir -Recurse -Force}}
}
Case 'Ecriture atomique repetee sans backup (regression RC3 File.Replace)' {
    $dir=Join-Path ([IO.Path]::GetTempPath()) ('Pesto-Test-NoBackup-'+[Guid]::NewGuid().ToString('N'))
    try{
        $p=Join-Path $dir 'queue.json'
        Write-PestoAtomicText $p 'Idle';Write-PestoAtomicText $p 'Active';Write-PestoAtomicText $p 'Idle'
        Assert-Equal ([IO.File]::ReadAllText($p)) 'Idle';Assert-Equal ([IO.File]::Exists($p+'.bak')) $false
    }finally{if(Test-Path -LiteralPath $dir){Remove-Item -LiteralPath $dir -Recurse -Force}}
}
$failed=@($results|Where-Object{-not $_.Passed})
$report=[ordered]@{Suite='Pesto 17 Engine';Utc=[DateTime]::UtcNow.ToString('o');PowerShell=$PSVersionTable.PSVersion.ToString();SourceHash=$sourceHash;Total=$results.Count;Passed=$results.Count-$failed.Count;Failed=$failed.Count;Tests=$results.ToArray();Scope='Fonctions extraites + mocks ; pas de validation AD/WPF/UAC réelle.'}
$report|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $ReportPath -Encoding UTF8
$script:cred=$null;$env:COMPUTERNAME=$oldComputerName
Write-Host "$($report.Passed)/$($report.Total) cas réussis. Rapport : $ReportPath"
if($failed.Count){throw "$($failed.Count) test(s) en échec."}
