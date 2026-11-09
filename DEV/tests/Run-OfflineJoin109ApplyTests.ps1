#requires -Version 5.1
[CmdletBinding()]
param([string]$ReportPath='')
$ErrorActionPreference='Stop';Set-StrictMode -Off
# Point 109, jambe d'application du blob secret. L'evaluation « jonction hors connexion : blob secret » se joue
# pour l'essentiel dans Invoke-PestoOfflineApply, aigille par Invoke-PestoExtensionCommand sous l'action
# OfflineApply (EXTENSIONS_120.md, section 109 : « import DPAPI local sous ACL administrateur/SYSTEM, intention
# durable avant djoin, application unique »). C'est la que le secret protege quitte le magasin, est verifie contre
# l'empreinte du plan scelle, ecrit le fichier transitoire remis a djoin, puis est detruit ; c'est aussi la que
# l'intention durable doit preceder l'appel natif et que le rejeu doit etre refuse. Les suites existantes du point
# ne jugent aucune de ces conditions une par une : Run-OfflineJoin109BlobTests.ps1 s'arrete a Imported,
# Run-OfflineJoin109ObserveTests.ps1 applique une seule fois pour preparer l'observation sans controler
# l'application, Run-OfflineJoin109NativeTests.ps1 et sa suite de ligne jugent le transport sur l'arbre syntaxique,
# et Run-ExtensionEffectsTests.ps1 ne joue l'application que par cinq cas globaux. Cette suite amene donc le blob a
# Imported, puis ne rejoue qu'OfflineApply, en gardant toutes les conditions reconciliees et n'en violant
# exactement une par cas : chaque garde doit etre la seule raison du refus, et tout refus doit etre verifie avant
# l'appel natif, avant la deprotection du secret et sans rien laisser dans le magasin ni dans le registre
# d'interventions. Ce qui est reel ici : le point d'entree public, Initialize-PestoOfflineContext, la relecture du
# recu ODJ (Read-PestoOfflineRecord, Assert-PestoClosedObject, recalcul de l'empreinte du plan), Get-PestoOfflinePaths,
# Get-PestoBytesHash, Assert-PestoPlainPath, la porte de politique Assert-PestoOperationPolicy, la porte
# d'approbation de campagne Assert-PestoCampaignApproval, le cycle complet des recus d'intervention
# (Start-PestoIntervention, Write-PestoIntervention, Read-PestoIntervention, Complete-PestoIntervention),
# l'ecriture durable du recu par Write-PestoAtomicText, l'ouverture du fichier transitoire en CreateNew et le
# nettoyage du finally. Les doubles restent a la frontiere Windows : plateforme, integrite du paquet, socle commun,
# statut local du poste, magasins ProgramData, ACL des recus, MachineGuid du registre, module ActiveDirectory,
# controleur, Get-ADComputer, canal securise, DPAPI et djoin. Aucun appel reseau, aucune VM, aucun cfg.json
# operationnel lu : la configuration vient du modele neutre DEV/tools/cfg.modele-complet.json recopie dans un
# dossier temporaire.
$dev=Split-Path $PSScriptRoot -Parent
$runtime=Join-Path $dev 'wad/Pesto.Engine.Runtime.ps1'
. $runtime
$script:passed=0;$script:failed=0
function Assert($v,$why='Assertion failed'){if(-not $v){throw $why}}
function Equal($actual,$expected,[string]$why=''){if($actual -cne $expected){throw ('attendu ['+$expected+'] obtenu ['+[string]$actual+'] '+$why)}}
function Case($name,[scriptblock]$body,[switch]$Reset){try{&$body;$script:passed++}catch{$script:failed++;Write-Host ('FAIL '+$name+': '+$_)}finally{if($Reset){Reset-Offline}}}
# Un refus n'est prouve que par la garde qui l'emet : la meme forme peut etre refusee plus loin, ce qui laisserait
# passer la garde amont. Le message est donc exige.
function RejectWith([scriptblock]$body,[string]$Needle){$caught='<aucun refus>';try{&$body|Out-Null}catch{$caught=[string]$_.Exception.Message};Assert ($caught.Contains($Needle)) ('refus attendu : '+$Needle+' ; obtenu : '+$caught)}
function Read-JsonFile([string]$Path){Assert ([IO.File]::Exists($Path)) ('fichier absent : '+$Path);return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json)}
function Write-JsonFile([string]$Path,$Document){[IO.File]::WriteAllText($Path,($Document|ConvertTo-Json -Depth 14),[Text.UTF8Encoding]::new($false))}
function FilesUnder([string]$Dir){if(-not[IO.Directory]::Exists($Dir)){return @()};return @(Get-ChildItem -LiteralPath $Dir -File|Sort-Object Name)}
function Iso-Instant($Value){
    if($Value -isnot [DateTime]){return $Value}
    if($Value.Kind -eq [DateTimeKind]::Unspecified){$Value=[DateTime]::SpecifyKind($Value,[DateTimeKind]::Utc)}
    return $Value.ToUniversalTime().ToString('o')
}
function Canonical-Plan($Plan){
    $copy=[ordered]@{}
    foreach($prop in $Plan.PSObject.Properties){
        if($prop.Name -eq 'Integrity'){continue}
        $copy[$prop.Name]=Iso-Instant $prop.Value
    }
    return $copy
}
# Le double qui remplace le transport d'ecriture des recus (ACL Windows) doit reproduire le produit et non une
# convenance de test : la profondeur de serialisation est lue dans la definition scellee de Write-PestoJoinReceipt,
# sinon le test validerait un format que le produit n'emet pas.
$writerSource=(Get-Command Write-PestoJoinReceipt).Definition
$writerMatch=[regex]::Match($writerSource,'ConvertTo-Json\s+-Depth\s+(\d+)')
if(-not $writerMatch.Success){throw 'La profondeur de serialisation du recus durable nest plus lisible dans Write-PestoJoinReceipt.'}
$writerDepth=[int]$writerMatch.Groups[1].Value

$root=Join-Path $PSScriptRoot ('pesto-offline109apply-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$machineValue='11111111-1111-1111-1111-111111111111'
$accountGuidValue='22222222-2222-2222-2222-222222222222'
$targetOuValue='OU=Postes,OU=Organisme,DC=example,DC=local'
$excludedOuValue='OU=Exclues,OU=Organisme,DC=example,DC=local'
$hostNameValue='PESTO-ODJ-109A'
$canary='ODJAPPLY'+[Guid]::NewGuid().ToString('N')
$script:fixtureKey=197
$script:cfgTemplate=Get-Content (Join-Path $dev 'tools/cfg.modele-complet.json') -Raw|ConvertFrom-Json

function Write-OfflineCfg {[CmdletBinding()]param([scriptblock]$Edit=$null)
    $cfg=$script:cfgTemplate|ConvertTo-Json -Depth 15|ConvertFrom-Json
    $cfg.POLICY|Add-Member -NotePropertyName AllowOfflineJoin -NotePropertyValue $true -Force
    if($Edit){&$Edit $cfg}
    $path=Join-Path $root ('cfg-'+[Guid]::NewGuid().ToString('N')+'.json')
    [IO.File]::WriteAllText($path,($cfg|ConvertTo-Json -Depth 15),[Text.UTF8Encoding]::new($false))
    return $path}

# Frontiere Windows : ces doubles ne sont la que pour rendre la jambe d'application jouable hors Windows. Ils
# enregistrent ce qu'on leur demande et ne jugent rien : chaque controle est formule dans le cas.
function Get-PestoManagedPolicy {[pscustomobject]@{Values=[pscustomobject]@{}}}
function Assert-PestoAutomationPlatform {$script:platformChecks++}
function Test-PestoPackage {param($Root);$script:packageChecks++;return $true}
function Initialize-PestoCommon {param([string]$Root='',[switch]$IncludeWpf);$script:commonInits++}
function Get-PestoAutomationMachineId {return $script:machine}
function Get-PestoJoinLocalStatus {$script:localReads++;return $script:local}
function Get-PestoOfflineStore {return $script:store}
function Get-PestoInterventionRoot {return $script:ledger}
function Get-PestoAutomationStore {return $script:automationStore}
function Get-PestoOperatorSid {return 'S-1-5-21-222'}
function Get-PestoWindowsAuthIdentity {[pscustomobject]@{Name='EXAMPLE\\operateur';Sid='S-1-5-21-222';IsDomainUser=$true;IsAdministrator=$true}}
function Get-PestoCampaignPolicy {return $script:campaignPolicy}
# Le registre HKLM MachineGuid et les recus directs de cette porte sont Windows : double de frontiere. Le plan qui
# lui est remis est le meme objet que celui remis a la porte de politique, rejouee reellement juste avant : il est
# donc capte ici, ce qui juge la forme de l'effet sans doubler la porte de politique elle-meme.
function Assert-PestoStoredMutationReady {param($OwnOperationId='',[switch]$Joining,$Plan=$null)
    $script:storedChecks++;$script:lastStoredPlan=$Plan
    if($script:storedRefuses){throw 'Une operation non resolue concerne cette cible ou un ancien reçu non rattaché. Consulter Interventions.'}}
function Import-PestoADModule {param($ADModulePath);$script:adImports++;$script:lastAdModule=[string]$ADModulePath}
function Get-DomainController {param($Domain);$script:dcReads++;$script:lastDcDomain=[string]$Domain;return $script:dcName}
function Get-ADComputer {param($Identity,$Properties,$ErrorAction,$Server,$Credential,$ResultSetSize,$LDAPFilter)
    $script:adReads++;$script:lastAdParams=@{Identity=$Identity;Server=$Server;Credential=$Credential;Properties=$Properties};return $script:pc}
function Test-ComputerSecureChannel {param($Server,$ErrorAction);$script:channelChecks++;$script:lastChannelServer=[string]$Server;return $script:secure}
function Write-PestoJoinReceipt {param($Path,$Receipt)
    $script:receiptWrites++;$script:receiptPaths+=@($Path)
    Write-PestoAtomicText $Path ($Receipt|ConvertTo-Json -Depth $writerDepth)}
# DPAPI et djoin : doubles de transport uniquement, aucun appel natif Windows. Le tampon rendu par la deprotection
# est garde par reference : le produit doit l'effacer dans son finally, ce qui se verifie apres son retour.
function Protect-PestoOfflineBytes {param([byte[]]$Bytes)
    Assert ($null -ne $Bytes -and $Bytes.Length -gt 0) 'DPAPI recoit un blob vide'
    $script:protectCalls++
    $out=New-Object byte[] $Bytes.Length
    for($i=0;$i -lt $Bytes.Length;$i++){$out[$i]=[byte]($Bytes[$i] -bxor $script:fixtureKey)}
    return ,$out}
function Unprotect-PestoOfflineBytes {param([byte[]]$Bytes)
    Assert ($null -ne $Bytes -and $Bytes.Length -gt 0) 'DPAPI recoit un secret vide'
    $script:unprotectCalls++
    # Copie, pas reference : le produit efface le tampon recu dans son finally, ce qui est exactement ce qu'on lui
    # demande de faire, et effacerait la trace que ce cas doit pouvoir relire apres le retour.
    $witness=New-Object byte[] $Bytes.Length
    [Array]::Copy($Bytes,$witness,$Bytes.Length)
    $script:lastProtectedInput=$witness
    $key=$script:fixtureKey
    if($script:unprotectTamper){$key=$key -bxor 1}
    $out=New-Object byte[] $Bytes.Length
    for($i=0;$i -lt $Bytes.Length;$i++){$out[$i]=[byte]($Bytes[$i] -bxor $key)}
    $script:lastClearBuffer=$out
    return ,$out}
# Le transport natif est le seul endroit ou le produit touche djoin. Le double ne juge rien : il releve l'etat du
# disque a l'instant exact de l'appel, ce qui est la seule facon de prouver que l'intention durable precede djoin.
function Invoke-PestoOfflineNative {param([string]$Path)
    $script:native++;$script:nativePaths+=@($Path)
    $id=[IO.Path]::GetFileName($Path).Replace('.odj.tmp','')
    $record=$null;try{$record=Read-PestoOfflineRecord $id}catch{$script:nativeRecordError=[string]$_.Exception.Message}
    $ledgerDoc=$null;$opId=''
    if($record -and $record.OperationId){
        $opId=[string]$record.OperationId
        $lp=Join-Path $script:ledger ($opId+'.json')
        if([IO.File]::Exists($lp)){$ledgerDoc=Read-JsonFile $lp}
    }
    $bytes=$null
    try{$bytes=[IO.File]::ReadAllBytes($Path)}catch{}
    $script:nativeWitness=[pscustomobject]@{
        Path=$Path
        BlobId=$id
        Exists=($null -ne $bytes)
        Bytes=$bytes
        State=$(if($record){[string]$record.State}else{'<recu illisible: '+$script:nativeRecordError+'>'})
        OperationId=$opId
        NativeCode=$(if($record){$record.NativeCode}else{$null})
        LedgerExists=($null -ne $ledgerDoc)
        LedgerOfflineJoin=$(if($ledgerDoc){[string]$ledgerDoc.OfflineJoin}else{''})
        LedgerPhase=$(if($ledgerDoc){[string]$ledgerDoc.Phase}else{''})
        StoreFiles=@(FilesUnder $script:store).Count}
    if($script:nativeThrows){throw $script:nativeMessage}
    return $script:nativeCode}

function Reset-Offline {
    $script:install=Join-Path $root ('pack-'+[Guid]::NewGuid().ToString('N'))
    $script:wad=Join-Path $script:install 'wad'
    $script:store=Join-Path $script:install 'offline'
    $script:ledger=Join-Path $script:install 'ledger'
    $script:automationStore=Join-Path $script:install 'automation'
    $script:blobs=Join-Path $script:install 'blobs'
    foreach($dir in @($script:wad,$script:store,$script:ledger,$script:automationStore,$script:blobs)){[void][IO.Directory]::CreateDirectory($dir)}
    [IO.File]::WriteAllBytes((Join-Path $script:install 'Pesto.exe'),[Text.Encoding]::UTF8.GetBytes('fixture-engine-marker'))
    $script:cfgFile=Write-OfflineCfg
    $script:machine=$machineValue
    $script:blobText='ODJ-BLOB-'+$canary
    $script:sourcePath=$null
    # Etat reel d'un poste pretable a une jonction hors connexion : hors domaine, sans renommage en attente,
    # administrateur, membre d'un groupe de travail (role 0). Le cas n'a plus qu'en violer une seule condition.
    $script:local=[pscustomobject]@{Computer=$hostNameValue;PartOfDomain=$false;PendingRename=$false;Admin=$true;DomainRole=0;MachineId=$machineValue;BootUtc='2026-10-17T10:00:00Z';Domain='WORKGROUP'}
    $script:pc=[pscustomobject]@{Name=$hostNameValue;ObjectGUID=$accountGuidValue;DistinguishedName=('CN='+$hostNameValue+','+$targetOuValue);userAccountControl=4096}
    $script:dcName='dc.example.local';$script:secure=$false
    $script:protectCalls=0;$script:unprotectCalls=0;$script:lastProtectedInput=$null;$script:lastClearBuffer=$null;$script:unprotectTamper=$false
    $script:native=0;$script:nativePaths=@();$script:nativeCode=0;$script:nativeThrows=$false;$script:nativeMessage='Delai djoin depasse : resultat incertain, aucun rejeu.'
    $script:nativeWitness=$null;$script:nativeRecordError=''
    $script:adReads=0;$script:adImports=0;$script:dcReads=0;$script:channelChecks=0
    $script:lastAdParams=$null;$script:lastAdModule='';$script:lastDcDomain='';$script:lastChannelServer=''
    $script:receiptWrites=0;$script:receiptPaths=@()
    $script:localReads=0;$script:platformChecks=0;$script:packageChecks=0;$script:commonInits=0;$script:storedChecks=0;$script:lastStoredPlan=$null;$script:storedRefuses=$false
    $script:campaignPolicy=$null
    $script:ActiveIntervention=$null
    $script:cred=$null
    $env:PESTO_READONLY_SESSION=''
}
function Invoke-Offline {[CmdletBinding()]param([string]$Action,[hashtable]$Params=@{},[string]$ConfigPath)
    $call=@{Action=$Action;RuntimeRoot=$script:wad;ConfigPath=if($ConfigPath){$ConfigPath}else{$script:cfgFile}}
    foreach($k in $Params.Keys){$call[$k]=$Params[$k]}
    return (Invoke-PestoExtensionCommand @call)}
function New-BlobFile {[CmdletBinding()]param($Text,$Name='poste.odj')
    if($null -eq $Text){$Text=$script:blobText}
    $path=Join-Path $script:blobs $Name
    [IO.File]::WriteAllBytes($path,[Text.Encoding]::UTF8.GetBytes($Text))
    $script:sourcePath=$path
    return $path}
function Import-Blob {[CmdletBinding()]param([string]$BlobPath,$ObjectGuid=$null,[string]$TargetOU='',$Metadata=$null,[string]$ConfigPath)
    if(-not $BlobPath){$BlobPath=New-BlobFile}
    if($null -eq $ObjectGuid){$ObjectGuid=[Guid]$accountGuidValue}
    if(-not $TargetOU){$TargetOU=$targetOuValue}
    return (Invoke-Offline -Action 'OfflineImport' -Params @{BlobPath=$BlobPath;ObjectGuid=$ObjectGuid;TargetOU=$TargetOU;Execute=$true;Metadata=$Metadata} -ConfigPath $ConfigPath)}
function Import-Ok {[CmdletBinding()]param([string]$BlobPath,$ObjectGuid=$null,[string]$TargetOU='',$Metadata=$null,[string]$ConfigPath)
    $r=Import-Blob -BlobPath $BlobPath -ObjectGuid $ObjectGuid -TargetOU $TargetOU -Metadata $Metadata -ConfigPath $ConfigPath
    Equal $r.ExitCode 0 ('import refuse : '+$r.Message)
    Equal $r.State 'Imported'
    return $r}
function Apply-Blob {[CmdletBinding()]param([string]$BlobId,$Approval=$null,[string]$ConfigPath)
    return (Invoke-Offline -Action 'OfflineApply' -Params @{BlobId=$BlobId;Approval=$Approval;Execute=$true} -ConfigPath $ConfigPath)}
function New-ImportedBlob {[CmdletBinding()]param($Metadata=$null,[string]$ConfigPath)
    $r=Import-Ok -Metadata $Metadata -ConfigPath $ConfigPath
    Assert ([IO.File]::Exists((SecretPath $r.BlobId))) 'le secret protege manque au magasin apres l import'
    Equal (Read-PestoOfflineRecord $r.BlobId).State 'Imported'
    return $r}
function ReceiptPath([string]$Id){return Join-Path $script:store ($Id+'.json')}
function SecretPath([string]$Id){return Join-Path $script:store ($Id+'.protected')}
function PlainPath([string]$Id){return Join-Path $script:store ($Id+'.odj.tmp')}
function LedgerPath([string]$OperationId){return Join-Path $script:ledger ($OperationId+'.json')}
# Amene le recu durable a un etat donne sans passer par le produit : c'est le seul moyen de rejouer l'application
# sur un etat que seule une interruption brutale laisse sur le disque (Requested) ou que l'observation seule
# produit (Verified). Le plan n'est pas touche, donc son empreinte scellee reste valide.
function Set-RecordState {[CmdletBinding()]param([string]$Id,[string]$State,[string]$OperationId='')
    $path=ReceiptPath $Id;$doc=Read-JsonFile $path
    $doc.State=$State
    if($OperationId){$doc.OperationId=$OperationId}
    Write-JsonFile $path $doc}
function Refused-BeforeNative([scriptblock]$body,[string]$Needle,[string]$Id){
    # Le refus doit venir de la garde visee, avant toute deprotection du secret, avant tout appel natif, et ne rien
    # laisser : ni fichier transitoire, ni recu d'intervention, ni magasin modifie, ni secret consomme.
    $caught='<aucun refus>'
    try{&$body|Out-Null}catch{$caught=[string]$_.Exception.Message}
    Assert ($caught.Contains($Needle)) ('refus attendu : '+$Needle+' ; obtenu : '+$caught)
    Equal $script:native 0 'djoin a ete appele alors que la garde visee devait arreter avant'
    Equal $script:unprotectCalls 0 'le secret a ete deprotege alors que la garde visee devait arreter avant'
    Equal $script:adReads 0 "l'annuaire a ete interroge depuis la jambe d application"
    Equal $script:channelChecks 0 'le canal securise a ete interroge depuis la jambe d application'
    Equal $script:dcReads 0 'un controleur a ete decouvert depuis la jambe d application'
    Equal @(FilesUnder $script:ledger).Count 0 'un recu d intervention a ete ecrit alors que la garde visee devait arreter avant'
    Equal @(FilesUnder $script:store).Count 2 'le magasin porte plus que le recu et le secret : rien ne devait etre ecrit'
    Assert ([IO.File]::Exists((SecretPath $Id))) 'le secret a ete detruit par un refus posterieur a son import'
    Assert (-not [IO.File]::Exists((PlainPath $Id))) 'un fichier transitoire a ete ecrit alors que la garde visee devait arreter avant'
    Equal (Read-PestoOfflineRecord $Id).State 'Imported' 'le refus a fait avancer l etat du blob'
}

try{
 Reset-Offline

# ---------- A. Le secret ne s'applique qu'une fois : la garde d'etat ----------
$alreadyNeedle='Demande deja enregistree ; observer apres redemarrage, sans repetition.'
Case 'A blob left at Requested by an interrupted run is never handed to djoin again' {
    $import=New-ImportedBlob
    Set-RecordState -Id $import.BlobId -State 'Requested'
    $r=Apply-Blob -BlobId $import.BlobId
    Equal $r.ExitCode 97 'la reprise d une demande enregistree doit etre refusee'
    Equal $r.State 'Requested'
    Equal $r.BlobId $import.BlobId
    Equal $r.ReplayAllowed $false 'le rejeu est annonce comme permis'
    Equal $r.Message $alreadyNeedle
    Equal $script:native 0 'djoin a ete rappele sur une demande deja enregistree'
    Equal $script:unprotectCalls 0 'le secret a ete deprotege pour une demande deja enregistree'
    Equal @(FilesUnder $script:ledger).Count 0 'une intervention a ete ouverte pour une demande deja enregistree'
    Assert ([IO.File]::Exists((SecretPath $import.BlobId))) 'le secret a ete detruit sans que la demande soit appliquee'
    Assert (-not [IO.File]::Exists((PlainPath $import.BlobId))) 'un fichier transitoire a ete ecrit sans appel natif'
} -Reset
Case 'A blob already pending restart is never handed to djoin again' {
    $import=New-ImportedBlob
    Set-RecordState -Id $import.BlobId -State 'PendingRestart'
    $r=Apply-Blob -BlobId $import.BlobId
    Equal $r.ExitCode 97;Equal $r.State 'PendingRestart';Equal $r.ReplayAllowed $false
    Equal $r.Message $alreadyNeedle
    Equal $script:native 0 'djoin a ete rappele sur un poste deja en attente de redemarrage'
    Assert ([IO.File]::Exists((SecretPath $import.BlobId))) 'le secret a ete detruit par un refus'
} -Reset
Case 'A blob left Uncertain by a failed application is never handed to djoin again' {
    $import=New-ImportedBlob
    Set-RecordState -Id $import.BlobId -State 'Uncertain'
    $r=Apply-Blob -BlobId $import.BlobId
    Equal $r.ExitCode 97;Equal $r.State 'Uncertain';Equal $r.ReplayAllowed $false
    Equal $script:native 0 'un resultat incertain a ete rejoue aupres de djoin'
    Equal $script:unprotectCalls 0 'le secret a ete deprotege pour un etat incertain'
} -Reset
Case 'A verified blob is never handed to djoin a second time' {
    $import=New-ImportedBlob
    Set-RecordState -Id $import.BlobId -State 'Verified'
    $r=Apply-Blob -BlobId $import.BlobId
    Equal $r.ExitCode 97;Equal $r.State 'Verified';Equal $r.ReplayAllowed $false
    Equal $script:native 0 'une jonction deja verifiee a ete redemandee a djoin'
} -Reset
Case 'A second application of a freshly applied blob does not call djoin again' {
    $import=New-ImportedBlob
    $first=Apply-Blob -BlobId $import.BlobId
    Equal $first.ExitCode 3010 $first.Message
    Equal $script:native 1 'djoin doit etre appele exactement une fois par blob'
    $ledgerCount=@(FilesUnder $script:ledger).Count
    $second=Apply-Blob -BlobId $import.BlobId
    Equal $second.ExitCode 97 'la seconde application devait etre refusee'
    Equal $second.State 'PendingRestart'
    Equal $second.ReplayAllowed $false
    Equal $script:native 1 'djoin a ete rappele par la seconde application'
    Equal $script:unprotectCalls 1 'le secret a ete deprotege une seconde fois'
    Equal @(FilesUnder $script:ledger).Count $ledgerCount 'la seconde application a ouvert une nouvelle intervention'
    Equal (Read-PestoOfflineRecord $import.BlobId).State 'PendingRestart' 'la seconde application a modifie l etat du blob'
} -Reset
Case 'A second application after a failed native code does not call djoin again' {
    $import=New-ImportedBlob
    $script:nativeCode=19
    $first=Apply-Blob -BlobId $import.BlobId
    Equal $first.ExitCode 97;Equal $first.State 'Uncertain'
    Equal $script:native 1
    $second=Apply-Blob -BlobId $import.BlobId
    Equal $second.ExitCode 97;Equal $second.State 'Uncertain'
    Equal $script:native 1 'un echec natif a ete rejoue aupres de djoin'
} -Reset
Case 'The refusal of a replay leaves the protected secret where the operator can still find it' {
    $import=New-ImportedBlob
    Set-RecordState -Id $import.BlobId -State 'PendingRestart'
    [void](Apply-Blob -BlobId $import.BlobId)
    $before=[IO.File]::ReadAllBytes((SecretPath $import.BlobId))
    [void](Apply-Blob -BlobId $import.BlobId)
    $after=[IO.File]::ReadAllBytes((SecretPath $import.BlobId))
    Equal ([BitConverter]::ToString($before)) ([BitConverter]::ToString($after)) 'le secret protege a change alors qu aucune application n a ete jouee'
} -Reset

# ---------- B. Le contexte du poste, revifie au moment d'appliquer ----------
$contextNeedle='Contexte ODJ change ou delai d application expire.'
Case 'A machine joined between the import and the application cannot consume the secret' {
    $import=New-ImportedBlob
    $script:local.PartOfDomain=$true
    Refused-BeforeNative {Apply-Blob -BlobId $import.BlobId} $contextNeedle $import.BlobId
} -Reset
Case 'A pending rename appearing between the import and the application stops the secret' {
    $import=New-ImportedBlob
    $script:local.PendingRename=$true
    Refused-BeforeNative {Apply-Blob -BlobId $import.BlobId} $contextNeedle $import.BlobId
} -Reset
Case 'An operator who lost local administration cannot consume the secret' {
    $import=New-ImportedBlob
    $script:local.Admin=$false
    Refused-BeforeNative {Apply-Blob -BlobId $import.BlobId} $contextNeedle $import.BlobId
} -Reset
Case 'A machine promoted to domain controller between import and application is refused' {
    $import=New-ImportedBlob
    $script:local.DomainRole=1
    Refused-BeforeNative {Apply-Blob -BlobId $import.BlobId} $contextNeedle $import.BlobId
} -Reset
Case 'A backup controller role appearing between import and application is refused' {
    $import=New-ImportedBlob
    $script:local.DomainRole=3
    Refused-BeforeNative {Apply-Blob -BlobId $import.BlobId} $contextNeedle $import.BlobId
} -Reset
Case 'The machine that was renamed since the import does not consume the secret' {
    $import=New-ImportedBlob
    $script:local.Computer='PESTO-AUTRE-109'
    Refused-BeforeNative {Apply-Blob -BlobId $import.BlobId} $contextNeedle $import.BlobId
} -Reset
Case 'A machine whose hardware identity changed since the import does not consume the secret' {
    $import=New-ImportedBlob
    $script:local.MachineId='99999999-9999-9999-9999-999999999999'
    Refused-BeforeNative {Apply-Blob -BlobId $import.BlobId} $contextNeedle $import.BlobId
} -Reset
Case 'A configuration edited between the import and the application invalidates the secret' {
    # Le marqueur de configuration est calcule a l'import ; un parametre metier modifie depuis doit empecher de
    # consommer le secret, sinon un blob prepare sous une politique le serait sous une autre.
    $import=New-ImportedBlob
    $other=Write-OfflineCfg {param($c)$c.POLICY.ExcludedNames=@('P123456*SRV*','ZZZ-EXCLU*')}
    Refused-BeforeNative {Apply-Blob -BlobId $import.BlobId -ConfigPath $other} $contextNeedle $import.BlobId
} -Reset
Case 'A plan whose validity window elapsed cannot consume the secret' {
    $import=New-ImportedBlob
    $path=ReceiptPath $import.BlobId;$doc=Read-JsonFile $path
    $doc.Plan.ExpiresUtc=[DateTime]::UtcNow.AddMinutes(-5).ToString('o')
    $doc.Plan.Integrity=Get-PestoStableHash (ConvertTo-PestoCanonicalValue (Canonical-Plan $doc.Plan))
    Write-JsonFile $path $doc
    Refused-BeforeNative {Apply-Blob -BlobId $import.BlobId} $contextNeedle $import.BlobId
} -Reset
Case 'A plan still inside its validity window is applied' {
    $import=New-ImportedBlob
    $path=ReceiptPath $import.BlobId;$doc=Read-JsonFile $path
    $doc.Plan.ExpiresUtc=[DateTime]::UtcNow.AddHours(6).ToString('o')
    $doc.Plan.Integrity=Get-PestoStableHash (ConvertTo-PestoCanonicalValue (Canonical-Plan $doc.Plan))
    Write-JsonFile $path $doc
    $r=Apply-Blob -BlobId $import.BlobId
    Equal $r.ExitCode 3010 ('plan encore valide : '+$r.Message)
    Equal $script:native 1
} -Reset
Case 'A member server is a valid application context' {
    $import=New-ImportedBlob
    $script:local.DomainRole=2
    $r=Apply-Blob -BlobId $import.BlobId
    Equal $r.ExitCode 3010 ('serveur membre refuse : '+$r.Message)
    Equal $script:native 1
} -Reset

# ---------- C. Les portes de politique et d'approbation ----------
Case 'A computer name excluded by policy never reaches djoin' {
    # La politique est la meme a l'import et a l'application : seule la porte de politique de l'application peut
    # arreter ici, l'import ne la joue pas.
    $cfg=Write-OfflineCfg {param($c)$c.POLICY.ExcludedNames=@('P123456*SRV*','PESTO-ODJ-109*')}
    $import=New-ImportedBlob -ConfigPath $cfg
    Refused-BeforeNative {Apply-Blob -BlobId $import.BlobId -ConfigPath $cfg} ('Cible exclue par la politique : '+$hostNameValue) $import.BlobId
} -Reset
Case 'An organisational unit outside the exclusion list does not block the application' {
    # Controle : une exclusion qui ne couvre pas l'unite planifiee ne doit pas arreter l'application, sinon la
    # porte suivante serait tenue pour porte de politique a tort.
    $cfg=Write-OfflineCfg {param($c)$c.POLICY.ExcludedOUs=@($excludedOuValue)}
    $import=New-ImportedBlob -ConfigPath $cfg
    $r=Apply-Blob -BlobId $import.BlobId -ConfigPath $cfg
    Equal $r.ExitCode 3010 ('unite hors de la liste d exclusion bloquee : '+$r.Message)
    Equal $script:lastStoredPlan.OU_Destination $targetOuValue "l'unite remise a la porte n'est pas l'unite planifiee"
    Equal $script:lastStoredPlan.OU_Actuelle '' "l'effet pretend une unite actuelle alors que ODJ n'en connait pas"
} -Reset
Case 'The destination of the effect is the planned organisational unit and is judged by the policy gate' {
    $cfg=Write-OfflineCfg {param($c)$c.POLICY.ExcludedOUs=@($targetOuValue)}
    $import=New-ImportedBlob -ConfigPath $cfg
    $caught='<aucun refus>'
    try{[void](Apply-Blob -BlobId $import.BlobId -ConfigPath $cfg)}catch{$caught=[string]$_.Exception.Message}
    Assert ($caught.Contains('exclu par la politique')) ('unite planifiee non soumise a la porte de politique : '+$caught)
    Equal $script:native 0 'djoin a ete appele malgre une unite exclue par la politique'
    Equal (Read-PestoOfflineRecord $import.BlobId).State 'Imported'
} -Reset
Case 'A campaign-gated policy refuses a blob imported without any campaign' {
    $import=New-ImportedBlob
    $script:campaignPolicy=@{Campaigns=@('*');Signers=@()}
    Refused-BeforeNative {Apply-Blob -BlobId $import.BlobId} 'Campagne obligatoire pour la politique approbation.' $import.BlobId
} -Reset
Case 'A blob of a gated campaign is refused when no approval object is handed over' {
    $import=New-ImportedBlob -Metadata @{Campaign='ODJ-2026'}
    $script:campaignPolicy=@{Campaigns=@('ODJ-2026');Signers=@()}
    # L'accord attendu est un objet ferme ; remis absent, c'est la porte d'approbation qui le refuse a la porte
    # d'objet ferme, avant toute lecture du secret.
    $caught='<aucun refus>'
    try{[void](Apply-Blob -BlobId $import.BlobId)}catch{$caught=[string]$_.Exception.Message}
    Assert ($caught.Contains('Value') -and $caught.Contains('null')) ('accord absent non refuse par la porte d approbation : '+$caught)
    Equal $script:native 0 'djoin a ete appele sans accord de campagne'
    Equal $script:unprotectCalls 0 'le secret a ete deprotege sans accord de campagne'
    Equal @(FilesUnder $script:ledger).Count 0 'une intervention a ete ouverte sans accord de campagne'
    Equal (Read-PestoOfflineRecord $import.BlobId).State 'Imported'
} -Reset
Case 'An approval that is not a structured object is refused by the campaign gate' {
    $import=New-ImportedBlob -Metadata @{Campaign='ODJ-2026'}
    $script:campaignPolicy=@{Campaigns=@('ODJ-2026');Signers=@()}
    $caught='<aucun refus>'
    try{[void](Apply-Blob -BlobId $import.BlobId -Approval 'accord-en-vrac')}catch{$caught=[string]$_.Exception.Message}
    Assert ($caught.Contains('Objet structuré attendu.')) ('accord non structure accepte : '+$caught)
    Equal $script:native 0 'djoin a ete appele sur un accord non structure'
    Equal (Read-PestoOfflineRecord $import.BlobId).State 'Imported'
} -Reset
Case 'A blob whose campaign is outside the gated list is not held by the approval gate' {
    $import=New-ImportedBlob -Metadata @{Campaign='HORS-CAMPAGNE'}
    $script:campaignPolicy=@{Campaigns=@('ODJ-2026');Signers=@()}
    $r=Apply-Blob -BlobId $import.BlobId
    Equal $r.ExitCode 3010 ('approuvation exigee hors de la campagne concernee : '+$r.Message)
} -Reset
Case 'A policy without campaign requirement applies a blob carrying no campaign' {
    $import=New-ImportedBlob
    $script:campaignPolicy=$null
    $r=Apply-Blob -BlobId $import.BlobId
    Equal $r.ExitCode 3010 ('approbation exigee a tort : '+$r.Message)
} -Reset
Case 'The unresolved-operation gate of the local register stops the secret before djoin' {
    $import=New-ImportedBlob
    $script:storedRefuses=$true
    Refused-BeforeNative {Apply-Blob -BlobId $import.BlobId} 'Une operation non resolue concerne cette cible' $import.BlobId
} -Reset
Case 'The effect handed to the gates is an offline join effect for the planned blob' {
    $import=New-ImportedBlob
    [void](Apply-Blob -BlobId $import.BlobId)
    $effect=$script:lastStoredPlan
    Assert ($null -ne $effect) "aucun effet n'a ete remis aux portes"
    Equal $effect.Action 'OfflineJoin' "l'effet remis aux portes n'est pas une jonction hors connexion"
    Equal $effect.BlobSHA256 $import.BlobId "l'effet ne porte pas l'empreinte du blob secret"
    Equal $effect.Nom_du_PC $hostNameValue "l'effet ne nomme pas le poste planifie"
    Equal $effect.Nouveau_Nom $hostNameValue "l'effet ne porte pas le nom planifie"
    Equal $effect.Domain 'EXAMPLE.LOCAL' "l'effet ne porte pas le domaine configure"
    Equal $effect.Renommer $false "l'effet demande un renommage"
    Equal $effect.Deplacer $false "l'effet demande un deplacement"
    Equal $effect.Reboot $false "l'effet demande un redemarrage"
    Equal $effect.ConfigStamp (Get-PestoConfigurationSignature $script:CFG) "l'effet ne porte pas le marqueur de la configuration en cours"
    Assert ($effect.PSObject.Properties.Name -ccontains 'BlobSHA256') "l'effet ne porte pas l'empreinte du blob"
} -Reset

# ---------- D. Le secret protege : lecture, deprotection, verification contre le plan ----------
Case 'A blob whose protected secret vanished is refused before any native call' {
    $import=New-ImportedBlob
    [IO.File]::Delete((SecretPath $import.BlobId))
    $caught='<aucun refus>'
    try{[void](Apply-Blob -BlobId $import.BlobId)}catch{$caught=[string]$_.Exception.Message}
    Assert ($caught -ne '<aucun refus>') 'un secret absent doit etre refuse'
    Equal $script:native 0 'djoin a ete appele sans secret'
    Equal $script:unprotectCalls 0 'la deprotection a ete tentee sans secret'
    Equal @(FilesUnder $script:store).Count 1 'le magasin porte un fichier inattendu apres un secret absent'
    Equal @(FilesUnder $script:ledger).Count 0 'une intervention a ete ouverte sans secret'
    Equal (Read-PestoOfflineRecord $import.BlobId).State 'Imported' 'le refus a fait avancer l etat du blob'
} -Reset
Case 'A secret replaced by a symbolic link is refused before being read' {
    $import=New-ImportedBlob
    $real=Join-Path $root ('vole-'+[Guid]::NewGuid().ToString('N')+'.protected')
    [IO.File]::WriteAllBytes($real,[IO.File]::ReadAllBytes((SecretPath $import.BlobId)))
    [IO.File]::Delete((SecretPath $import.BlobId))
    [void](New-Item -ItemType SymbolicLink -Path (SecretPath $import.BlobId) -Target $real -ErrorAction Stop)
    Refused-BeforeNative {Apply-Blob -BlobId $import.BlobId} 'Un chemin critique traverse un lien ou une jonction.' $import.BlobId
} -Reset
Case 'A secret one byte over the two megabyte ceiling is refused before being unprotected' {
    $import=New-ImportedBlob
    [IO.File]::WriteAllText((SecretPath $import.BlobId),('A'*2200001),[Text.UTF8Encoding]::new($false))
    Refused-BeforeNative {Apply-Blob -BlobId $import.BlobId} 'Secret protege invalide.' $import.BlobId
} -Reset
Case 'A secret that is not base64 is refused before any native call' {
    $import=New-ImportedBlob
    [IO.File]::WriteAllText((SecretPath $import.BlobId),'ceci n est pas du base64 !!!',[Text.UTF8Encoding]::new($false))
    $caught='<aucun refus>'
    try{[void](Apply-Blob -BlobId $import.BlobId)}catch{$caught=[string]$_.Exception.Message}
    Assert ($caught -ne '<aucun refus>') 'un secret hors base64 doit etre refuse'
    Equal $script:native 0 'djoin a ete appele sur un secret illisible'
    Equal $script:unprotectCalls 0 'la deprotection a ete tentee sur un secret hors base64'
    Equal (Read-PestoOfflineRecord $import.BlobId).State 'Imported'
} -Reset
Case 'A secret that decrypts to something else than the sealed plan is refused' {
    # Cette garde est la derniere avant l'intention durable : la deprotection a donc deja ete jouee, ce qui la
    # distingue des refus amont. Rien d'autre ne doit suivre.
    $import=New-ImportedBlob
    $script:unprotectTamper=$true
    RejectWith {Apply-Blob -BlobId $import.BlobId} 'Blob decrypte different du plan.'
    Equal $script:unprotectCalls 1 'la deprotection n a pas ete jouee une fois avant la comparaison d empreinte'
    Equal $script:native 0 'djoin a ete appele sur un materiel qui ne correspond pas au plan'
    Equal @(FilesUnder $script:ledger).Count 0 'une intervention a ete ouverte sur un materiel non conforme'
    Equal @(FilesUnder $script:store).Count 2 'le magasin a ete modifie par un materiel non conforme'
    Assert (-not [IO.File]::Exists((PlainPath $import.BlobId))) 'un fichier transitoire a ete ecrit sur un materiel non conforme'
    Assert ([IO.File]::Exists((SecretPath $import.BlobId))) 'le secret a ete detruit par un refus de conformite'
    Equal (Read-PestoOfflineRecord $import.BlobId).State 'Imported' 'un materiel non conforme a fait avancer l etat du blob'
} -Reset
Case 'DPAPI is asked exactly once, over the bytes stored in the secret file' {
    $import=New-ImportedBlob
    $stored=[Convert]::FromBase64String([IO.File]::ReadAllText((SecretPath $import.BlobId)))
    [void](Apply-Blob -BlobId $import.BlobId)
    Equal $script:unprotectCalls 1 'le secret n a pas ete deprotege exactement une fois'
    Equal ([BitConverter]::ToString($script:lastProtectedInput)) ([BitConverter]::ToString($stored)) 'la deprotection ne porte pas sur les octets du fichier secret'
} -Reset
Case 'The clear material is wiped from memory when the application ends' {
    $import=New-ImportedBlob
    [void](Apply-Blob -BlobId $import.BlobId)
    $buffer=$script:lastClearBuffer
    Assert ($null -ne $buffer -and $buffer.Length -gt 0) 'le materiel clair deprotege na pas ete observe'
    $zeroes=0;foreach($b in $buffer){if($b -eq 0){$zeroes++}}
    Equal $zeroes $buffer.Length 'le materiel clair deprotege na pas ete efface a la fin de l application'
} -Reset
Case 'The clear material is wiped even when the application is refused after unprotection' {
    $import=New-ImportedBlob
    $script:unprotectTamper=$true
    try{[void](Apply-Blob -BlobId $import.BlobId)}catch{}
    $buffer=$script:lastClearBuffer
    Assert ($null -ne $buffer -and $buffer.Length -gt 0) 'le materiel clair deprotege na pas ete observe'
    $zeroes=0;foreach($b in $buffer){if($b -eq 0){$zeroes++}}
    Equal $zeroes $buffer.Length 'le materiel clair na pas ete efface apres un echec de verification'
} -Reset

# ---------- E. L'intention durable precede djoin, le fichier transitoire est le seul porteur ----------
Case 'The durable receipt already reads Requested at the instant djoin is called' {
    $import=New-ImportedBlob
    [void](Apply-Blob -BlobId $import.BlobId)
    Assert ($null -ne $script:nativeWitness) "djoin n'a pas ete appele"
    Equal $script:nativeWitness.State 'Requested' "l'intention durable n'est pas enregistree avant l'appel natif"
    Equal $script:nativeWitness.BlobId $import.BlobId 'le fichier remis a djoin ne porte pas l identifiant du blob'
} -Reset
Case 'The intervention ledger already carries the offline intention at the instant djoin is called' {
    $import=New-ImportedBlob
    [void](Apply-Blob -BlobId $import.BlobId)
    Equal $script:nativeWitness.LedgerExists $true "le recu d'intervention n'existe pas au moment de l'appel natif"
    Equal $script:nativeWitness.LedgerOfflineJoin 'Requested' "l'intention hors connexion n'est pas gravee dans le registre avant djoin"
} -Reset
Case 'The file handed to djoin carries exactly the blob material' {
    $import=New-ImportedBlob
    [void](Apply-Blob -BlobId $import.BlobId)
    Assert ($script:nativeWitness.Exists) 'le fichier transitoire n existe pas au moment de l appel natif'
    $expected=[Text.Encoding]::UTF8.GetBytes($script:blobText)
    Equal ([BitConverter]::ToString($script:nativeWitness.Bytes)) ([BitConverter]::ToString($expected)) 'le fichier remis a djoin n est pas le materiel du blob'
    Equal $script:nativeWitness.Path (PlainPath $import.BlobId) 'le fichier remis a djoin n est pas dans le magasin ACL'
} -Reset
Case 'A plain path replaced by a link never lets the blob material leave the store' {
    # Le fichier transitoire porte le materiel clair du blob : si son chemin n'est pas verifie, l'ouverture y
    # ecrit hors du magasin ACL. Sans la garde, la deprotection aboutit donc a une exfiltration silencieuse.
    $import=New-ImportedBlob
    $hors=Join-Path $root ('fuite-'+[Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($hors)
    $cible=Join-Path $hors 'blob-exfiltre.odj'
    [void](New-Item -ItemType SymbolicLink -Path (PlainPath $import.BlobId) -Target $cible -ErrorAction Stop)
    RejectWith {Apply-Blob -BlobId $import.BlobId} 'Un chemin critique traverse un lien ou une jonction.'
    Equal $script:native 0 'djoin a ete appele sur un chemin transitoire detourne'
    Assert (-not [IO.File]::Exists($cible)) 'le materiel clair du blob a ete ecrit hors du magasin ACL'
    Equal (Read-PestoOfflineRecord $import.BlobId).State 'Uncertain' 'un detournement de chemin laisse un etat rejouable'
} -Reset
Case 'Both the plain file and the protected secret are destroyed once djoin answered' {
    $import=New-ImportedBlob
    [void](Apply-Blob -BlobId $import.BlobId)
    Assert (-not [IO.File]::Exists((PlainPath $import.BlobId))) 'le fichier transitoire survit a l application'
    Assert (-not [IO.File]::Exists((SecretPath $import.BlobId))) 'le secret protege survit a son utilisation unique'
    Equal @(FilesUnder $script:store).Count 1 'le magasin ne garde plus que le recu'
} -Reset
Case 'A plain file left on disk by a crash refuses the application and never reaches djoin' {
    $import=New-ImportedBlob
    [IO.File]::WriteAllBytes((PlainPath $import.BlobId),[Text.Encoding]::UTF8.GetBytes('restes d une application interrompue'))
    $caught='<aucun refus>'
    try{[void](Apply-Blob -BlobId $import.BlobId)}catch{$caught=[string]$_.Exception.Message}
    Assert ($caught -ne '<aucun refus>') 'une collision sur le fichier transitoire doit etre refusee'
    Equal $script:native 0 'djoin a ete appele malgre un fichier transitoire deja present'
    Equal (Read-PestoOfflineRecord $import.BlobId).State 'Uncertain' 'une collision sur le transitoire laisse un etat rejouable'
    Assert (-not [IO.File]::Exists((PlainPath $import.BlobId))) 'le fichier transitoire parasite survit'
    Assert (-not [IO.File]::Exists((SecretPath $import.BlobId))) 'le secret survit a une application interrompue'
} -Reset
Case 'Nothing on disk ever carries the blob material in the clear' {
    $import=New-ImportedBlob
    [void](Apply-Blob -BlobId $import.BlobId)
    $files=@(FilesUnder $script:store)+@(FilesUnder $script:ledger)+@(FilesUnder $script:automationStore)
    Assert ($files.Count -ge 2) ('peu de traces produites : '+$files.Count)
    foreach($file in $files){
        $text=[IO.File]::ReadAllText($file.FullName)
        Assert (-not $text.Contains($canary)) ('le blob fuite en clair dans '+$file.Name)
        Assert (-not ($text -match '(?i)protecteddata|dpapi')) ('un detail de protection du secret parait dans '+$file.Name)
    }
} -Reset
Case 'The operator source file is never deleted by the application' {
    $import=New-ImportedBlob
    Assert ([IO.File]::Exists($script:sourcePath)) 'la source remise par l operateur a disparu avant l application'
    [void](Apply-Blob -BlobId $import.BlobId)
    Assert ([IO.File]::Exists($script:sourcePath)) 'le logiciel a supprime le fichier de l operateur'
} -Reset

# ---------- F. Le code de sortie natif decide seul de l'etat ----------
Case 'A zero native code asks for a restart and marks the blob pending restart' {
    $import=New-ImportedBlob
    $r=Apply-Blob -BlobId $import.BlobId
    Equal $r.ExitCode 3010 'le code natif nul doit demander un redemarrage'
    Equal $r.State 'PendingRestart'
    Equal $r.RestartRequired $true
    Equal $r.BlobId $import.BlobId
    Equal $r.ReplayAllowed $false 'une demande enregistree doit interdire le rejeu'
    Assert ($r.OperationId -match '^[a-f0-9]{32}$') "l'identifiant d'operation n'est pas un guide sans tirets : "+$r.OperationId
    Equal (Read-PestoOfflineRecord $import.BlobId).State 'PendingRestart' 'le recu durable ne suit pas le code natif'
    Equal (Read-PestoOfflineRecord $import.BlobId).NativeCode 0 'le code natif na pas ete grave dans le recu'
    $ledger=Read-PestoIntervention (LedgerPath $r.OperationId)
    Equal $ledger.OfflineJoin 'PendingRestart' "le registre ne suit pas le code natif"
    Equal $ledger.ResultCode 10 "le registre ne clos pas l'intervention sur le code de redemarrage"
} -Reset
Case 'A nonzero native code leaves the blob Uncertain and asks for no restart' {
    $import=New-ImportedBlob
    $script:nativeCode=19
    $r=Apply-Blob -BlobId $import.BlobId
    Equal $r.ExitCode 97 'un code natif non nul ne doit pas annoncer de redemarrage'
    Equal $r.State 'Uncertain'
    Equal $r.RestartRequired $false
    Equal (Read-PestoOfflineRecord $import.BlobId).State 'Uncertain'
    Equal (Read-PestoOfflineRecord $import.BlobId).NativeCode 19 'le code natif na pas ete grave dans le recu'
    $ledger=Read-PestoIntervention (LedgerPath $r.OperationId)
    Equal $ledger.OfflineJoin 'Uncertain'
    Equal $ledger.ResultCode 97 "le registre ne clos pas l'intervention en incertain"
    Assert (-not [IO.File]::Exists((PlainPath $import.BlobId))) 'le fichier transitoire survit a un echec natif'
    Assert (-not [IO.File]::Exists((SecretPath $import.BlobId))) 'le secret survit a un echec natif'
} -Reset
Case 'A restart code from djoin itself is not mistaken for success' {
    # 3010 est le code Windows « redemarrage requis » : le produit ne reconnait que 0 comme demande enregistree.
    $import=New-ImportedBlob
    $script:nativeCode=3010
    $r=Apply-Blob -BlobId $import.BlobId
    Equal $r.ExitCode 97 'un code non nul a ete traite comme un succes'
    Equal $r.State 'Uncertain'
    Equal $r.RestartRequired $false
} -Reset
Case 'A native timeout is reported as uncertain and never replayed' {
    $import=New-ImportedBlob
    $script:nativeThrows=$true
    RejectWith {Apply-Blob -BlobId $import.BlobId} 'Delai djoin depasse'
    Equal $script:native 1 'le transport a ete rappele apres le delai'
    Equal (Read-PestoOfflineRecord $import.BlobId).State 'Uncertain' 'un delai depasse laisse un etat rejouable'
    $record=Read-PestoOfflineRecord $import.BlobId
    Assert ($record.OperationId -match '^[a-f0-9]{32}$') "l'operation du recu n'est pas guidee"
    $ledger=Read-PestoIntervention (LedgerPath $record.OperationId)
    # L'intention gravee avant djoin n'est jamais retractee par le chemin d'echec : ce sont la phase et le code
    # du registre qui portent l'incertitude, ce qui empeche une relance automatique.
    Equal $ledger.OfflineJoin 'Requested' "le chemin d'echec a reecrit l'intention durable"
    Equal $ledger.Phase 'Uncertain' 'le registre ne classe pas le delai en incertain'
    Equal $ledger.ResultCode 97 'le registre na pas ete clos en incertain apres le delai'
    Assert (-not [IO.File]::Exists((PlainPath $import.BlobId))) 'le fichier transitoire survit au delai depasse'
    Assert (-not [IO.File]::Exists((SecretPath $import.BlobId))) 'le secret survit au delai depasse'
} -Reset
Case 'The operation id is the same in the result, the durable receipt and the ledger' {
    $import=New-ImportedBlob
    $r=Apply-Blob -BlobId $import.BlobId
    Equal (Read-PestoOfflineRecord $import.BlobId).OperationId $r.OperationId 'le recu durable ne porte pas la meme operation que le resultat'
    Equal $script:nativeWitness.OperationId $r.OperationId "l'appel natif n'a pas vu la meme operation"
    Assert ([IO.File]::Exists((LedgerPath $r.OperationId))) "le registre ne porte pas l'operation rendue"
} -Reset
Case 'The application never touches the directory, the controller or the secure channel' {
    $import=New-ImportedBlob
    [void](Apply-Blob -BlobId $import.BlobId)
    Equal $script:adReads 0 "la jambe d'application interroge l'annuaire"
    Equal $script:dcReads 0 "la jambe d'application decouvre un controleur"
    Equal $script:channelChecks 0 "la jambe d'application verifie le canal securise"
    Equal $script:adImports 0 "la jambe d'application importe le module ActiveDirectory"
} -Reset
Case 'The application asks the local status, the policy and the register gates once each' {
    $import=New-ImportedBlob
    [void](Apply-Blob -BlobId $import.BlobId)
    Equal $script:storedChecks 1 'la porte du registre local na pas ete jouee exactement une fois'
    Assert ($script:localReads -ge 1) 'le statut local du poste na pas ete reluu avant dappliquer'
} -Reset

}finally{
    $env:PESTO_READONLY_SESSION=''
    if([IO.Directory]::Exists($root)){[IO.Directory]::Delete($root,$true)}
}
$report=[pscustomobject]@{Schema=1;Suite='OfflineJoin109Apply';HostOS=[Environment]::OSVersion.ToString();PowerShell=$PSVersionTable.PSVersion.ToString();WindowsExecuted=$false;ADExecuted=$false;WPFExecuted=$false;GPOApplied=$false;RegistryWritten=$false;Scope='Jambe d application OfflineApply jouee par le point d entree public, chaque condition rejouee une par une contre le moteur scelle ; recus durables, cycle d intervention, empreinte du plan, porte de politique et approbation de campagne reels ; plateforme, paquet, socle, statut du poste, registre, DPAPI, djoin, ACL, AD et magasins doubles ; aucun appel reseau ni VM'}
if($ReportPath){[IO.File]::WriteAllText([IO.Path]::GetFullPath($ReportPath),($report|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))}
Write-Host "OfflineJoin109Apply: $script:passed passed, $script:failed failed. Each offline join application condition judged alone against the sealed engine; durable receipts and intervention ledger real; DPAPI/djoin/ACL/AD transports mocked; no VM."
if($script:failed){exit 1}
