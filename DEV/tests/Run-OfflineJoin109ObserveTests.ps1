#requires -Version 5.1
[CmdletBinding()]
param([string]$ReportPath='')
$ErrorActionPreference='Stop';Set-StrictMode -Off
# Point 109, jambe d'observation. L'evaluation « jonction hors connexion : blob secret » ne devient un
# resultat pour l'operateur que lorsque Get-PestoOfflineObservation, aigille par Invoke-PestoExtensionCommand
# sous l'action OfflineObserve, confronte le poste redemarre, l'objet de l'annuaire et le canal securise au plan
# scelle (EXTENSIONS_120.md, section 109 : « observation du redemarrage, GUID, domaine et canal securise »).
# Les deux suites qui jouent deja cette jambe la refusent toujours pour une raison qui masque les autres :
# Run-OfflineJoin109EntryTests.ps1 observe avant le redemarrage sans jamais avoir joint le poste
# (PartOfDomain est faux, donc la conjonction locale est fausse avant meme la comparaison de redemarrage) et
# observe sans canal securise (la decision tombe par $secure). Un sondage consigne dans
# DEV/docs/implementation/proofs/OFFLINE_JOIN_109_OBSERVE_20261025.json mesure le resultat : sur douze
# reecritures de cette jambe, dix laissent les deux suites a 48/48 et 57/57 (retrait du drapeau de poste joint, de la
# comparaison de domaine, du nom de poste, de l'identite de machine, du renommage en attente, de la comparaison
# de redemarrage et de son affaiblissement en -ge, de la comparaison de GUID de l'annuaire, et de deux des trois
# controles croises du recu d'intervention) ; les deux autres ne sont vues que par la suite du point d'entree,
# a 47/1, et aucune par celle des effets, qui reste a 57/57 sur les douze. Cette suite ne fait donc que rejouer OfflineObserve, mais en gardant toutes
# les conditions reconciliees et n'en violant exactement une par cas : chaque garde doit etre la seule raison
# du refus. Ce qui est reel ici : le point d'entree public, Initialize-PestoOfflineContext, la lecture et la
# validation du recu ODJ (Read-PestoOfflineRecord, Assert-PestoClosedObject, recalcul de l'empreinte du plan),
# le cycle complet des recus d'intervention et l'ecriture durable qui clos le recu. Les doubles restent a la
# frontiere Windows/AD : plateforme, integrity du paquet, socle commun, module ActiveDirectory, controleur
# decouvert, Get-ADComputer, canal securise, DPAPI, djoin, ACL des recus, MachineGuid du registre et magasins
# ProgramData. Aucun appel reseau, aucune VM, aucun cfg.json operationnel lu : la configuration vient du modele
# neutre DEV/tools/cfg.modele-complet.json recopie dans un dossier temporaire.
$dev=Split-Path $PSScriptRoot -Parent
$runtime=Join-Path $dev 'wad'
. (Join-Path $runtime 'Pesto.Engine.Runtime.ps1')
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

# Le double qui remplace le transport d'ecriture des recus (ACL Windows) doit reproduire le produit et non une
# convenance de test : la profondeur de serialisation est lue dans la definition scellee de Write-PestoJoinReceipt,
# sinon le test validerait un format que le produit n'emet pas.
$writerSource=(Get-Command Write-PestoJoinReceipt).Definition
$writerMatch=[regex]::Match($writerSource,'ConvertTo-Json\s+-Depth\s+(\d+)')
if(-not $writerMatch.Success){throw 'La profondeur de serialisation du recus durable nest plus lisible dans Write-PestoJoinReceipt.'}
$writerDepth=[int]$writerMatch.Groups[1].Value

$root=Join-Path $PSScriptRoot ('pesto-offline109obs-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$machineValue='11111111-1111-1111-1111-111111111111'
$accountGuidValue='22222222-2222-2222-2222-222222222222'
$targetOuValue='OU=Postes,OU=Organisme,DC=example,DC=local'
$hostNameValue='PESTO-ODJ-109O'
$domainValue='example.local'
$dcValue='dc.example.local'
$bootBeforeValue='2026-10-17T10:00:00Z'
$bootAfterValue='2026-10-18T10:00:00Z'
$canary='ODJCANARY'+[Guid]::NewGuid().ToString('N')
$script:fixtureKey=173
$script:cfgTemplate=Get-Content (Join-Path $dev 'tools/cfg.modele-complet.json') -Raw|ConvertFrom-Json

function Write-OfflineCfg {[CmdletBinding()]param([scriptblock]$Edit=$null)
    $cfg=$script:cfgTemplate|ConvertTo-Json -Depth 15|ConvertFrom-Json
    $cfg.POLICY|Add-Member -NotePropertyName AllowOfflineJoin -NotePropertyValue $true -Force
    if($Edit){&$Edit $cfg}
    $path=Join-Path $root ('cfg-'+[Guid]::NewGuid().ToString('N')+'.json')
    [IO.File]::WriteAllText($path,($cfg|ConvertTo-Json -Depth 15),[Text.UTF8Encoding]::new($false))
    return $path}

# Frontiere Windows/AD : ces doubles ne sont la que pour rendre la jambe d'observation jouable hors Windows.
# Ils enregistrent ce qu'on leur demande et ne jugent rien : chaque controle est formule dans le cas.
function Get-PestoManagedPolicy {[pscustomobject]@{Values=[pscustomobject]@{}}}
function Assert-PestoAutomationPlatform {$script:platformChecks++}
function Test-PestoPackage {param($Root);$script:packageChecks++;return $true}
function Initialize-PestoCommon {param([string]$Root='',[switch]$IncludeWpf);$script:commonInits++}
function Get-PestoAutomationMachineId {return $script:machine}
function Get-PestoJoinLocalStatus {return $script:local}
function Get-PestoOfflineStore {return $script:store}
function Get-PestoInterventionRoot {return $script:ledger}
function Get-PestoAutomationStore {return $script:automationStore}
function Get-PestoOperatorSid {return 'S-1-5-21-222'}
function Get-PestoWindowsAuthIdentity {[pscustomobject]@{Name='EXAMPLE\\operateur';Sid='S-1-5-21-222';IsDomainUser=$true;IsAdministrator=$true}}
function Get-PestoCampaignPolicy {return $script:campaignPolicy}
function Assert-PestoStoredMutationReady {param($OwnOperationId='',[switch]$Joining,$Plan=$null);$script:storedChecks++}
function Import-PestoADModule {param($ADModulePath);$script:adImports++;$script:lastAdModule=[string]$ADModulePath}
function Get-DomainController {param($Domain);$script:dcReads++;$script:lastDcDomain=[string]$Domain;return $script:dcName}
function Get-ADComputer {param($Identity,$Properties,$ErrorAction,$Server,$Credential,$ResultSetSize,$LDAPFilter)
    $script:adReads++;$script:lastAdParams=@{Identity=$Identity;Server=$Server;Credential=$Credential;Properties=$Properties};return $script:pc}
function Test-ComputerSecureChannel {param($Server,$ErrorAction);$script:channelChecks++;$script:lastChannelServer=[string]$Server;return $script:secure}
function Write-PestoJoinReceipt {param($Path,$Receipt)
    $script:receiptWrites++;$script:receiptPaths+=@($Path)
    Write-PestoAtomicText $Path ($Receipt|ConvertTo-Json -Depth $writerDepth)}
# DPAPI et djoin : doubles de transport uniquement, aucun appel natif Windows, aucune lecture d'annuaire.
function Protect-PestoOfflineBytes {param([byte[]]$Bytes)
    Assert ($null -ne $Bytes -and $Bytes.Length -gt 0) 'DPAPI recoit un blob vide'
    $script:protectCalls++
    $out=New-Object byte[] $Bytes.Length
    for($i=0;$i -lt $Bytes.Length;$i++){$out[$i]=[byte]($Bytes[$i] -bxor $script:fixtureKey)}
    return ,$out}
function Unprotect-PestoOfflineBytes {param([byte[]]$Bytes)
    Assert ($null -ne $Bytes -and $Bytes.Length -gt 0) 'DPAPI recoit un secret vide'
    $script:unprotectCalls++
    $out=New-Object byte[] $Bytes.Length
    for($i=0;$i -lt $Bytes.Length;$i++){$out[$i]=[byte]($Bytes[$i] -bxor $script:fixtureKey)}
    return ,$out}
function Invoke-PestoOfflineNative {param([string]$Path)
    $script:native++;$script:nativePaths+=@($Path)
    $id=[IO.Path]::GetFileName($Path).Replace('.odj.tmp','')
    $r=Read-PestoOfflineRecord $id
    Equal $r.State 'Requested' 'l intention durable doit etre enregistree avant l appel natif'
    Assert ([IO.File]::Exists($Path)) 'le fichier transitoire doit exister pendant l appel natif'
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
    $script:local=[pscustomobject]@{Computer=$hostNameValue;PartOfDomain=$false;PendingRename=$false;Admin=$true;DomainRole=0;MachineId=$machineValue;BootUtc=$bootBeforeValue;Domain='WORKGROUP'}
    $script:pc=[pscustomobject]@{Name=$hostNameValue;ObjectGUID=$accountGuidValue;DistinguishedName=('CN='+$hostNameValue+','+$targetOuValue);userAccountControl=4096}
    $script:dcName=$dcValue;$script:secure=$false
    $script:native=0;$script:nativePaths=@();$script:nativeCode=0
    $script:protectCalls=0;$script:unprotectCalls=0
    $script:adReads=0;$script:adImports=0;$script:dcReads=0;$script:channelChecks=0
    $script:lastAdParams=$null;$script:lastAdModule='';$script:lastDcDomain='';$script:lastChannelServer=''
    $script:receiptWrites=0;$script:receiptPaths=@()
    $script:platformChecks=0;$script:packageChecks=0;$script:commonInits=0;$script:storedChecks=0
    $script:campaignPolicy=$null
    $script:cred=$null
    $env:PESTO_READONLY_SESSION=''
}
function Invoke-Offline {[CmdletBinding()]param([string]$Action,[hashtable]$Params=@{},$CredentialValue=$null,[string]$ConfigPath,[string]$RuntimeRoot,[switch]$NoConfig)
    $call=@{Action=$Action;RuntimeRoot=if($RuntimeRoot){$RuntimeRoot}else{$script:wad}}
    if(-not $NoConfig){$call['ConfigPath']=if($ConfigPath){$ConfigPath}else{$script:cfgFile}}
    if($null -ne $CredentialValue){$call['Credential']=$CredentialValue}
    foreach($k in $Params.Keys){$call[$k]=$Params[$k]}
    return (Invoke-PestoExtensionCommand @call)}
function New-BlobFile {[CmdletBinding()]param($Text,$Name='poste.odj')
    if($null -eq $Text){$Text=$script:blobText}
    $path=Join-Path $script:blobs $Name
    [IO.File]::WriteAllBytes($path,[Text.Encoding]::UTF8.GetBytes($Text))
    return $path}
function Import-Blob {[CmdletBinding()]param([string]$BlobPath,[Guid]$ObjectGuid=[Guid]::Empty,[string]$TargetOU='')
    if(-not $BlobPath){$BlobPath=New-BlobFile}
    if($ObjectGuid -eq [Guid]::Empty){$ObjectGuid=[Guid]$accountGuidValue}
    if(-not $TargetOU){$TargetOU=$targetOuValue}
    return (Invoke-Offline -Action 'OfflineImport' -Params @{BlobPath=$BlobPath;ObjectGuid=$ObjectGuid;TargetOU=$TargetOU;Execute=$true})}
function Apply-Blob {[CmdletBinding()]param([string]$BlobId)
    return (Invoke-Offline -Action 'OfflineApply' -Params @{BlobId=$BlobId;Approval=$null;Execute=$true})}
function Observe-Blob {[CmdletBinding()]param([string]$BlobId,$CredentialValue=$null)
    return (Invoke-Offline -Action 'OfflineObserve' -Params @{BlobId=$BlobId} -CredentialValue $CredentialValue)}
function New-AppliedBlob {
    # Amene le poste a l'etat reel qui precede l'observation : importe, applique, djoin appele une fois,
    # recu durable en PendingRestart et recu d'intervention porteur de l'intention.
    $import=Import-Blob
    Equal $import.ExitCode 0 $import.Message
    $apply=Apply-Blob -BlobId $import.BlobId
    Equal $apply.ExitCode 3010 $apply.Message
    Equal $apply.State 'PendingRestart'
    Equal $script:native 1 'djoin doit avoir ete appele exactement une fois avant l observation'
    $record=Read-PestoOfflineRecord $import.BlobId
    Equal $record.State 'PendingRestart'
    return [pscustomobject]@{Import=$import;Apply=$apply;Record=$record}
}
function Set-Reconciled {[CmdletBinding()]param([string]$Boot=$bootAfterValue)
    # Toutes les conditions de la jambe d'observation reunies : le cas n'a plus qu'en violer une seule.
    $script:local.PartOfDomain=$true;$script:local.Domain=$domainValue;$script:local.Computer=$hostNameValue
    $script:local.MachineId=$machineValue;$script:local.PendingRename=$false;$script:local.BootUtc=$Boot
    $script:pc.Name=$hostNameValue;$script:pc.ObjectGUID=$accountGuidValue
    $script:pc.DistinguishedName=('CN='+$hostNameValue+','+$targetOuValue)
    $script:secure=$true}
function LedgerPath([string]$OperationId){return Join-Path $script:ledger ($OperationId+'.json')}
function Edit-Ledger {[CmdletBinding()]param([string]$OperationId,[scriptblock]$Edit)
    # L'empreinte du plan est relue par Read-PestoIntervention : sans la recalculer, un plan altere serait arrete
    # par cette garde amont ('Le plan du recu a change depuis son enregistrement.') et le controle propre a
    # l'observation ne serait jamais joue. Le recu est donc re-scelle, ce qui laisse la garde visee seule en piste.
    $path=LedgerPath $OperationId;$doc=Read-JsonFile $path;&$Edit $doc
    if($doc.PSObject.Properties['PlanFingerprint'] -and $doc.PlanFingerprint){$doc.PlanFingerprint=Get-PestoPlanFingerprint $doc.Plan}
    Write-JsonFile $path $doc}
function UncertainOnly($o,[string]$why){
    # La garde doit etre la seule raison du refus : la jambe d'annuaire elle-meme ne doit pas avoir ete jouee
    # quand la confrontation locale a deja echoue, et le recu ne doit pas etre clos.
    Equal $o.State 'Uncertain' $why
    Equal $o.ExitCode 97 $why
    Equal $o.IdentityConfirmed $false $why
    Equal $o.SecureChannel $false $why
    Equal $o.TargetReadOnly $true $why
    Equal $o.ReplayAllowed $false $why
    Equal $script:adReads 0 ($why+' : la relecture de l annuaire a ete jouee alors que la confrontation locale avait echoue')
    Equal $script:dcReads 0 ($why+' : un controleur a ete decouvert alors que la confrontation locale avait echoue')
    Equal $script:channelChecks 0 ($why+' : le canal securise a ete interroge alors que la confrontation locale avait echoue')
    Equal $script:adImports 0 ($why+' : le module ActiveDirectory a ete importe alors que la confrontation locale avait echoue')
}

try{
 Reset-Offline
 Case 'Reconciled observation verifies and closes the receipt' {
    $setup=New-AppliedBlob
    Set-Reconciled
    $credential=[pscredential]::new('EXAMPLE\operateur',(ConvertTo-SecureString $canary -AsPlainText -Force))
    $o=Observe-Blob -BlobId $setup.Import.BlobId -CredentialValue $credential
    Equal $o.State 'Verified' ('observation reconciliee : '+$o.State);Equal $o.ExitCode 0
    Equal $o.IdentityConfirmed $true;Equal $o.SecureChannel $true
    Equal $o.BlobId $setup.Import.BlobId;Equal $o.OperationId $setup.Apply.OperationId
    Equal (Read-PestoOfflineRecord $setup.Import.BlobId).State 'Verified' 'le recu durable n a pas ete clos'
    $ledger=Read-PestoIntervention (LedgerPath $setup.Apply.OperationId)
    Equal $ledger.OfflineJoin 'Verified';Equal $ledger.Phase 'Verified';Equal $ledger.ResultCode 30
    Equal $ledger.VerifiedBy 'S-1-5-21-222'
    Assert ($ledger.VerifiedUtc) 'l observation n a pas date sa verification'
    Equal $script:adImports 1 'le module ActiveDirectory n a pas ete importe exactement une fois'
    Assert ($script:lastAdModule -like '*ActiveDirectory.psd1') ('module AD inattendu : '+$script:lastAdModule)
    Equal $script:dcReads 1 'le controleur n a pas ete decouvert exactement une fois'
    Assert ($script:lastDcDomain -ieq $setup.Record.Plan.Domain) ('controleur decouvre pour le domaine : '+$script:lastDcDomain)
    Equal $script:adReads 1 'l annuaire n a pas ete relu exactement une fois'
    Equal $script:channelChecks 1 'le canal securise n a pas ete interroge exactement une fois'
    Assert ($script:lastChannelServer -ceq $dcValue) ('canal securise interroge aupres de : '+$script:lastChannelServer)
    Assert ($script:lastAdParams.Server -ceq $dcValue) ('relecture AD adresssee au controleur : '+[string]$script:lastAdParams.Server)
    Assert ($script:lastAdParams.Identity -is [Guid]) ('la relecture AD n est pas adressee par GUID : '+[string]$script:lastAdParams.Identity)
    Assert ([string]$script:lastAdParams.Identity -ieq $setup.Record.Plan.ObjectGuid) ('objet relu par GUID : '+[string]$script:lastAdParams.Identity)
    Assert ($script:lastAdParams.Credential -is [pscredential]) 'aucun PSCredential transmis a la relecture AD'
    Assert ($null -eq $script:cred) 'la credential reste dans la portee du moteur apres l observation'
    } -Reset
 Case 'A machine not joined to the domain is never verified' {
    $setup=New-AppliedBlob
    Set-Reconciled;$script:local.PartOfDomain=$false
    $path=LedgerPath $setup.Apply.OperationId;$before=[IO.File]::ReadAllText($path)
    $o=Observe-Blob -BlobId $setup.Import.BlobId
    UncertainOnly $o 'un poste non joint doit rester incertain'
    Equal ([IO.File]::ReadAllText($path)) $before 'un poste non joint a clos le recu'
    Equal (Read-PestoOfflineRecord $setup.Import.BlobId).State 'PendingRestart'
    } -Reset
 Case 'A machine joined to another domain is never verified' {
    $setup=New-AppliedBlob
    Set-Reconciled;$script:local.Domain='autre.local'
    $o=Observe-Blob -BlobId $setup.Import.BlobId
    UncertainOnly $o 'un poste joint a un autre domaine doit rester incertain'
    Equal (Read-PestoOfflineRecord $setup.Import.BlobId).State 'PendingRestart'
    } -Reset
 Case 'A machine whose name differs from the plan is never verified' {
    $setup=New-AppliedBlob
    Set-Reconciled;$script:local.Computer='AUTRE-NOM'
    $o=Observe-Blob -BlobId $setup.Import.BlobId
    UncertainOnly $o 'un poste dont le nom ne suit pas le plan doit rester incertain'
    Equal (Read-PestoOfflineRecord $setup.Import.BlobId).State 'PendingRestart'
    } -Reset
 Case 'A machine whose machine identity changed is never verified' {
    $setup=New-AppliedBlob
    Set-Reconciled;$script:local.MachineId='99999999-9999-9999-9999-999999999999'
    $o=Observe-Blob -BlobId $setup.Import.BlobId
    UncertainOnly $o 'un poste dont l identite de machine a change doit rester incertain'
    Equal (Read-PestoOfflineRecord $setup.Import.BlobId).State 'PendingRestart'
    } -Reset
 Case 'A machine with a pending rename is never verified' {
    $setup=New-AppliedBlob
    Set-Reconciled;$script:local.PendingRename=$true
    $o=Observe-Blob -BlobId $setup.Import.BlobId
    UncertainOnly $o 'un poste dont le renommage est en attente doit rester incertain'
    Equal (Read-PestoOfflineRecord $setup.Import.BlobId).State 'PendingRestart'
    } -Reset
 Case 'A boot identical to the recorded boot is not a reboot' {
    $setup=New-AppliedBlob
    Set-Reconciled -Boot $setup.Record.BootUtc
    $o=Observe-Blob -BlobId $setup.Import.BlobId
    UncertainOnly $o 'le meme temps de demarrage que celui enregistre prouve seulement que le poste n a pas redemarre'
    Equal (Read-PestoOfflineRecord $setup.Import.BlobId).State 'PendingRestart'
    } -Reset
 Case 'A boot older than the recorded boot is not a reboot' {
    $setup=New-AppliedBlob
    Set-Reconciled -Boot '2026-10-16T10:00:00Z'
    $o=Observe-Blob -BlobId $setup.Import.BlobId
    UncertainOnly $o 'un demarrage anterieur a la demande ne prouve aucun redemarrage'
    Equal (Read-PestoOfflineRecord $setup.Import.BlobId).State 'PendingRestart'
    } -Reset
 Case 'A directory object with another GUID is never verified' {
    $setup=New-AppliedBlob
    Set-Reconciled;$script:pc.ObjectGUID=[Guid]::NewGuid().ToString('D')
    $path=LedgerPath $setup.Apply.OperationId;$before=[IO.File]::ReadAllText($path)
    $o=Observe-Blob -BlobId $setup.Import.BlobId
    Equal $o.State 'Uncertain' 'un objet de l annuaire au GUID different doit rester incertain'
    Equal $o.ExitCode 97;Equal $o.IdentityConfirmed $false
    Equal $o.SecureChannel $true 'la jambe annuaire devait etre jouee jusqu au canal securise'
    Equal $script:adReads 1;Equal $script:channelChecks 1
    Equal ([IO.File]::ReadAllText($path)) $before 'un objet au GUID different a clos le recu'
    Equal (Read-PestoOfflineRecord $setup.Import.BlobId).State 'PendingRestart'
    } -Reset
 Case 'A directory object renamed in the directory is never verified' {
    $setup=New-AppliedBlob
    Set-Reconciled;$script:pc.Name='POSTE-DEPLACE'
    $o=Observe-Blob -BlobId $setup.Import.BlobId
    Equal $o.State 'Uncertain' 'un objet renomme dans l annuaire doit rester incertain'
    Equal $o.IdentityConfirmed $false;Equal $o.SecureChannel $true
    Equal (Read-PestoOfflineRecord $setup.Import.BlobId).State 'PendingRestart'
    } -Reset
 Case 'A directory object moved out of the planned OU is never verified' {
    $setup=New-AppliedBlob
    Set-Reconciled;$script:pc.DistinguishedName=('CN='+$hostNameValue+',OU=Staging,OU=Postes,OU=Organisme,DC=example,DC=local')
    $o=Observe-Blob -BlobId $setup.Import.BlobId
    Equal $o.State 'Uncertain' 'un objet deplace hors de l OU planifie doit rester incertain'
    Equal $o.IdentityConfirmed $false;Equal $o.SecureChannel $true
    Equal (Read-PestoOfflineRecord $setup.Import.BlobId).State 'PendingRestart'
    } -Reset
 Case 'An unverified secure channel never closes the receipt' {
    $setup=New-AppliedBlob
    Set-Reconciled;$script:secure=$false
    $path=LedgerPath $setup.Apply.OperationId;$before=[IO.File]::ReadAllText($path)
    $o=Observe-Blob -BlobId $setup.Import.BlobId
    Equal $o.State 'Uncertain' 'un canal securise non verifie doit rester incertain'
    Equal $o.ExitCode 97;Equal $o.IdentityConfirmed $true;Equal $o.SecureChannel $false
    Equal $script:channelChecks 1 'le canal securise n a pas ete interroge'
    Assert ($script:lastChannelServer -ceq $dcValue) ('canal securise interroge aupres de : '+$script:lastChannelServer)
    Equal ([IO.File]::ReadAllText($path)) $before 'un canal non verifie a clos le recu'
    Equal (Read-PestoOfflineRecord $setup.Import.BlobId).State 'PendingRestart'
    } -Reset
 Case 'The controller is discovered for the planned domain and used for both checks' {
    $setup=New-AppliedBlob
    Set-Reconciled
    $o=Observe-Blob -BlobId $setup.Import.BlobId
    Equal $o.State 'Verified' ('observation reconciliee : '+$o.State)
    Assert ($script:lastDcDomain -ieq $setup.Record.Plan.Domain) ('controleur decouvre pour le domaine : '+$script:lastDcDomain)
    Assert ($script:lastAdParams.Server -ceq $script:lastChannelServer) ('relecture AD et canal securise adresses a des machines differentes : '+[string]$script:lastAdParams.Server+' / '+$script:lastChannelServer)
    Assert ($script:lastChannelServer -ceq $dcValue) ('canal securise interroge aupres de : '+$script:lastChannelServer)
    } -Reset
 Case 'An uncertain observation never recalls the native application' {
    $setup=New-AppliedBlob
    Set-Reconciled;$script:secure=$false
    [void](Observe-Blob -BlobId $setup.Import.BlobId)
    [void](Observe-Blob -BlobId $setup.Import.BlobId)
    Equal $script:native 1 'l observation a relance la demande native'
    Equal $script:unprotectCalls 1 'le secret a ete dechiffre par une observation'
    $paths=Get-PestoOfflinePaths $setup.Import.BlobId
    Assert (-not [IO.File]::Exists($paths.Plain)) 'une observation a laisse le fichier transitoire'
    Assert (-not [IO.File]::Exists($paths.Secret)) 'une observation a laisse le secret protege'
    } -Reset
 Case 'A ledger naming another computer is refused' {
    $setup=New-AppliedBlob
    Set-Reconciled
    Edit-Ledger -OperationId $setup.Apply.OperationId -Edit{$args[0].Plan.Nom_du_PC='AUTRE-POSTE'}
    RejectWith -body {Observe-Blob -BlobId $setup.Import.BlobId} -Needle 'Recu intervention ODJ incoherent.'
    Equal (Read-PestoOfflineRecord $setup.Import.BlobId).State 'PendingRestart' 'un recu incoherent a neanmoins ete clos'
    } -Reset
 Case 'A ledger belonging to another domain is refused' {
    $setup=New-AppliedBlob
    Set-Reconciled
    Edit-Ledger -OperationId $setup.Apply.OperationId -Edit{$args[0].Plan.Domain='autre.local'}
    RejectWith -body {Observe-Blob -BlobId $setup.Import.BlobId} -Needle 'Recu intervention ODJ incoherent.'
    Equal (Read-PestoOfflineRecord $setup.Import.BlobId).State 'PendingRestart' 'un recu incoherent a neanmoins ete clos'
    } -Reset
 Case 'A ledger without an offline join intention is refused' {
    $setup=New-AppliedBlob
    Set-Reconciled
    Edit-Ledger -OperationId $setup.Apply.OperationId -Edit{$args[0].OfflineJoin=''}
    RejectWith -body {Observe-Blob -BlobId $setup.Import.BlobId} -Needle 'Recu intervention ODJ incoherent.'
    Equal (Read-PestoOfflineRecord $setup.Import.BlobId).State 'PendingRestart' 'un recu sans intention a neanmoins ete clos'
    } -Reset
 Case 'A read-only observation reports verified without closing anything' {
    $setup=New-AppliedBlob
    Set-Reconciled
    $path=LedgerPath $setup.Apply.OperationId;$before=[IO.File]::ReadAllText($path)
    $env:PESTO_READONLY_SESSION='1'
    try{$o=Observe-Blob -BlobId $setup.Import.BlobId}finally{$env:PESTO_READONLY_SESSION=''}
    Equal $o.State 'Verified';Equal $o.ExitCode 0
    Equal ([IO.File]::ReadAllText($path)) $before 'une observation en consultation a reecrit le recu d intervention'
    Equal (Read-PestoOfflineRecord $setup.Import.BlobId).State 'PendingRestart' 'une observation en consultation a clos le recu durable'
    [void](Observe-Blob -BlobId $setup.Import.BlobId)
    Assert ([IO.File]::ReadAllText($path) -cne $before) 'l observation writable n a rien consigne'
    Equal (Read-PestoOfflineRecord $setup.Import.BlobId).State 'Verified'
    } -Reset
 Case 'A second observation keeps the receipt verified and never recalls the native call' {
    $setup=New-AppliedBlob
    Set-Reconciled
    [void](Observe-Blob -BlobId $setup.Import.BlobId)
    $again=Observe-Blob -BlobId $setup.Import.BlobId
    Equal $again.State 'Verified';Equal $again.ExitCode 0;Equal $again.ReplayAllowed $false
    Equal $again.BlobId $setup.Import.BlobId;Equal $again.OperationId $setup.Apply.OperationId
    Equal (Read-PestoOfflineRecord $setup.Import.BlobId).State 'Verified'
    $ledger=Read-PestoIntervention (LedgerPath $setup.Apply.OperationId)
    Equal $ledger.OfflineJoin 'Verified';Equal $ledger.Phase 'Verified';Equal $ledger.ResultCode 30
    Equal $script:native 1 'une observation a rappele la demande native'
    Equal $script:unprotectCalls 1 'une observation a dechiffre le secret'
    } -Reset
 Case 'Observation of a record still at Imported is refused before any directory read' {
    $import=Import-Blob
    Equal $import.ExitCode 0 $import.Message
    RejectWith -body {Observe-Blob -BlobId $import.BlobId} -Needle 'Blob non applique.'
    Equal $script:adReads 0 'l observation a lu l annuaire sans demande enregistree'
    Equal $script:dcReads 0 'l observation a decouvert un controleur sans demande enregistree'
    Equal $script:channelChecks 0 'l observation a interroge le canal securise sans demande enregistree'
    Equal $script:native 0
    } -Reset
 Case 'The observation never publishes the blob material' {
    $setup=New-AppliedBlob
    Set-Reconciled
    $o=Observe-Blob -BlobId $setup.Import.BlobId
    Equal $o.State 'Verified' ('cycle incomplet : '+$o.State)
    Assert (-not ((($o|ConvertTo-Json -Depth 8 -Compress)).Contains($canary))) 'le blob fuite dans le resultat rendu'
    $files=@(FilesUnder $script:store)+@(FilesUnder $script:ledger)+@(FilesUnder $script:automationStore)
    Assert ($files.Count -ge 2) ('peu de traces produites : '+$files.Count)
    foreach($file in $files){
        $text=[IO.File]::ReadAllText($file.FullName)
        Assert (-not $text.Contains($canary)) ('le blob fuite en clair dans '+$file.Name)
        Assert (-not ($text -match '(?i)protecteddata|dpapi')) ('un detail de protection du secret parait dans '+$file.Name)
        }
    } -Reset
}finally{
    $env:PESTO_READONLY_SESSION=''
    if([IO.Directory]::Exists($root)){[IO.Directory]::Delete($root,$true)}
}
$report=[pscustomobject]@{Schema=1;Suite='OfflineJoin109Observe';HostOS=[Environment]::OSVersion.ToString();PowerShell=$PSVersionTable.PSVersion.ToString();WindowsExecuted=$false;ADExecuted=$false;WPFExecuted=$false;GPOApplied=$false;RegistryWritten=$false;Scope='Jambe d observation OfflineObserve jouee par le point d entree public, chaque condition reconcilee une par une ; recus durables et recu d intervention reels ; plateforme, paquet, socle, module AD, controleur, Get-ADComputer, canal securise, DPAPI, djoin, ACL et magasins doubles ; aucun appel reseau ni VM'}
if($ReportPath){[IO.File]::WriteAllText([IO.Path]::GetFullPath($ReportPath),($report|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))}
Write-Host "OfflineJoin109Observe: $script:passed passed, $script:failed failed. Each offline join observation condition judged alone against the sealed engine; durable receipts real; AD/DPAPI/djoin/ACL transports mocked; no VM."
if($script:failed){exit 1}
