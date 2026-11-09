#requires -Version 5.1
[CmdletBinding()]
param([string]$ReportPath='')
$ErrorActionPreference='Stop';Set-StrictMode -Off
# Point 109 : l'evaluation « jonction hors connexion : blob secret » n'existe pour l'operateur que par le point
# d'entree public Invoke-PestoExtensionCommand, exporte par Pesto.Engine.psd1 et rejoue par wad/Invoke-PestoExtension.ps1
# sous les actions OfflineImport, OfflineApply et OfflineObserve (EXTENSIONS_120.md, section 109). La suite
# historique Run-ExtensionEffectsTests.ps1 appelle Import-PestoOfflineBlob, Invoke-PestoOfflineApply et
# Get-PestoOfflineObservation en direct : elle ne joue donc jamais Initialize-PestoOfflineContext (drapeaux DEBUG,
# AllowOfflineJoin, mode incident, consultation, incompatibilite de coordination ni d'exclusion de groupes),
# l'exigence -Execute de l'import et de l'application, le refus d'observer en execution, ni l'aiguillage du switch.
# Cette suite n'appelle qu'Invoke-PestoExtensionCommand. Sont donc joues pour de vrai : la lecture et la validation
# de la configuration, ConvertTo-PestoPolicy, l'empreinte de configuration du plan, le cycle des recus
# (Start-PestoIntervention, Write-PestoIntervention, Read-PestoIntervention, Complete-PestoIntervention et le
# Get-PestoOutcome qui en tire l'etat), Assert-PestoOperationPolicy,
# Assert-PestoCampaignApproval, la garde du recu ODJ et l'empreinte SHA256 du blob. Les doubles restent a la
# frontiere Windows/AD : plateforme, integrity du paquet, socle commun, module ActiveDirectory, controleur
# decouvert, Get-ADComputer, canal securise, DPAPI, djoin, ACL des recus, MachineGuid du registre et magasins
# ProgramData. Aucun appel reseau, aucune VM, aucun cfg.json operationnel lu : la configuration vient du modele
# neutre DEV/tools/cfg.modele-complet.json recopie dans un dossier temporaire, AllowOfflineJoin y etant active
# explicitement comme l'exige la documentation.
$dev=Split-Path $PSScriptRoot -Parent
$runtime=Join-Path $dev 'wad'
. (Join-Path $runtime 'Pesto.Engine.Runtime.ps1')
$script:passed=0;$script:failed=0
function Assert($v,$why='Assertion failed'){if(-not $v){throw $why}}
function Equal($actual,$expected,[string]$why=''){if($actual -cne $expected){throw ('attendu ['+$expected+'] obtenu ['+[string]$actual+'] '+$why)}}
function Case($name,[scriptblock]$body,[switch]$Reset){try{&$body;$script:passed++}catch{$script:failed++;Write-Host ('FAIL '+$name+': '+$_)}finally{if($Reset){Reset-Offline}}}
function Reject([scriptblock]$body){$caught=$false;try{&$body|Out-Null}catch{$caught=$true};Assert $caught 'un refus etait attendu, la commande a reussi'}
# Un refus n'est prouve que par le garde qui l'emet : la meme forme peut etre refusee plus loin, ce qui laisserait
# passer la garde amont. Le message est donc exige.
function RejectWith([scriptblock]$body,[string]$Needle){$caught='<aucun refus>';try{&$body|Out-Null}catch{$caught=[string]$_.Exception.Message};Assert ($caught.Contains($Needle)) ('refus attendu : '+$Needle+' ; obtenu : '+$caught)}
function Read-JsonFile([string]$Path){Assert ([IO.File]::Exists($Path)) ('fichier absent : '+$Path);return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json)}
function Write-JsonFile([string]$Path,$Document){[IO.File]::WriteAllText($Path,($Document|ConvertTo-Json -Depth 14),[Text.UTF8Encoding]::new($false))}
function FilesUnder([string]$Dir){if(-not[IO.Directory]::Exists($Dir)){return @()};return @(Get-ChildItem -LiteralPath $Dir -File|Sort-Object Name)}
function Sha256Hex([string]$Text){$h=[Security.Cryptography.SHA256]::Create();try{return ([BitConverter]::ToString($h.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-','').ToLowerInvariant()}finally{$h.Dispose()}}

# Les definitions reelles sont saisies avant les doubles : ce sont elles que les cas d'inspection jugent.
$protectSource=(Get-Command Protect-PestoOfflineBytes).Definition
$unprotectSource=(Get-Command Unprotect-PestoOfflineBytes).Definition
$nativeSource=(Get-Command Invoke-PestoOfflineNative).Definition
$applySource=(Get-Command Invoke-PestoOfflineApply).Definition
$importSource=(Get-Command Import-PestoOfflineBlob).Definition
$observeSource=(Get-Command Get-PestoOfflineObservation).Definition

$root=Join-Path $PSScriptRoot ('pesto-offline109-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$machineValue='11111111-1111-1111-1111-111111111111'
$accountGuidValue='22222222-2222-2222-2222-222222222222'
$targetOuValue='OU=Postes,OU=Organisme,DC=example,DC=local'
$hostNameValue='PESTO-ODJ-109'
$canary='ODJCANARY'+[Guid]::NewGuid().ToString('N')
$script:fixtureKey=167
$script:cfgTemplate=Get-Content (Join-Path $dev 'tools/cfg.modele-complet.json') -Raw|ConvertFrom-Json

function Write-OfflineCfg {[CmdletBinding()]param([scriptblock]$Edit=$null)
    $cfg=$script:cfgTemplate|ConvertTo-Json -Depth 15|ConvertFrom-Json
    $cfg.POLICY|Add-Member -NotePropertyName AllowOfflineJoin -NotePropertyValue $true -Force
    if($Edit){&$Edit $cfg}
    $path=Join-Path $root ('cfg-'+[Guid]::NewGuid().ToString('N')+'.json')
    [IO.File]::WriteAllText($path,($cfg|ConvertTo-Json -Depth 15),[Text.UTF8Encoding]::new($false))
    return $path}

# Frontiere Windows/AD : ces doubles ne sont la que pour rendre le point d'entree jouable hors Windows.
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
function Import-PestoADModule {param($ADModulePath);$script:adImports++;Assert ($ADModulePath -like '*ActiveDirectory.psd1') ('module AD inattendu : '+[string]$ADModulePath)}
function Get-DomainController {param($Domain);$script:dcReads++;return $script:dcName}
function Get-ADComputer {param($Identity,$Properties,$ErrorAction,$Server,$Credential,$ResultSetSize,$LDAPFilter)
    $script:adReads++;$script:lastAdParams=@{Identity=$Identity;Server=$Server;Credential=$Credential};return $script:pc}
function Test-ComputerSecureChannel {param($Server,$ErrorAction);$script:channelChecks++;Assert ($Server -ceq $script:dcName) ('canal securise verifie hors du controleur decouvert : '+[string]$Server);return $script:secure}
function Write-PestoJoinReceipt {param($Path,$Receipt)
    $script:receiptWrites++;$script:receiptPaths+=@($Path)
    if($script:failWriteAt -gt 0 -and $script:failWriteAt -eq $script:receiptWrites){throw 'fixture disk failure'}
    if($script:failPathMatch -and ($Path -like $script:failPathMatch)){throw 'fixture disk failure'}
    Write-PestoAtomicText $Path ($Receipt|ConvertTo-Json -Depth 14)}
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
    $script:native++
    $script:nativePaths+=@($Path)
    $id=[IO.Path]::GetFileName($Path).Replace('.odj.tmp','')
    $r=Read-PestoOfflineRecord $id
    Equal $r.State 'Requested' 'l intention durable doit etre enregistree avant l appel natif'
    Assert ($r.OperationId) 'le recu ODJ doit porter l identifiant de l intervention avant l appel natif'
    Assert ([IO.File]::Exists($Path)) 'le fichier transitoire doit exister pendant l appel natif'
    Equal ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Path))) $script:store 'le fichier transitoire est ecrit hors du magasin protege'
    Equal ([Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($Path))) $script:blobText 'djoin ne recoit pas le blob importe'
    $ledger=Read-PestoIntervention (Join-Path $script:ledger ($r.OperationId+'.json'))
    Equal $ledger.OfflineJoin 'Requested' 'le recu d intervention ne porte pas l intention avant l appel natif'
    if($script:nativeFail){throw 'fixture native interruption'}
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
    $script:local=[pscustomobject]@{Computer=$hostNameValue;PartOfDomain=$false;PendingRename=$false;Admin=$true;DomainRole=0;MachineId=$machineValue;BootUtc='2026-10-17T10:00:00Z';Domain='WORKGROUP'}
    $script:pc=[pscustomobject]@{Name=$hostNameValue;ObjectGUID=$accountGuidValue;DistinguishedName=('CN='+$hostNameValue+','+$targetOuValue);userAccountControl=4096}
    $script:dcName='dc.example.local';$script:secure=$false
    $script:native=0;$script:nativePaths=@();$script:nativeFail=$false;$script:nativeCode=0
    $script:protectCalls=0;$script:unprotectCalls=0
    $script:adReads=0;$script:adImports=0;$script:dcReads=0;$script:channelChecks=0;$script:lastAdParams=$null
    $script:receiptWrites=0;$script:receiptPaths=@();$script:failWriteAt=0;$script:failPathMatch=''
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
function Import-Blob {[CmdletBinding()]param([string]$BlobPath,[Guid]$ObjectGuid=[Guid]::Empty,[string]$TargetOU='',$Metadata=$null,[string]$ConfigPath,[switch]$NoGuid)
    if(-not $BlobPath){$BlobPath=New-BlobFile}
    if(-not $NoGuid -and $ObjectGuid -eq [Guid]::Empty){$ObjectGuid=[Guid]$accountGuidValue}
    if(-not $TargetOU){$TargetOU=$targetOuValue}
    return (Invoke-Offline -Action 'OfflineImport' -ConfigPath $ConfigPath -Params @{BlobPath=$BlobPath;ObjectGuid=$ObjectGuid;TargetOU=$TargetOU;Metadata=$Metadata;Execute=$true})}
function Apply-Blob {[CmdletBinding()]param([string]$BlobId,$Approval=$null,[string]$ConfigPath)
    return (Invoke-Offline -Action 'OfflineApply' -ConfigPath $ConfigPath -Params @{BlobId=$BlobId;Approval=$Approval;Execute=$true})}
function Observe-Blob {[CmdletBinding()]param([string]$BlobId,$CredentialValue=$null)
    return (Invoke-Offline -Action 'OfflineObserve' -Params @{BlobId=$BlobId} -CredentialValue $CredentialValue)}
function Set-JoinedLocal {[CmdletBinding()]param([string]$Boot='2026-10-18T10:00:00Z')
    $script:local.PartOfDomain=$true;$script:local.Domain='example.local';$script:local.BootUtc=$Boot;$script:local.PendingRename=$false}
function Edit-OfflineRecord {[CmdletBinding()]param([string]$Id,[scriptblock]$Edit)
    $path=(Get-PestoOfflinePaths $Id).State;$doc=Read-JsonFile $path;&$Edit $doc;Write-JsonFile $path $doc}
function Resign-OfflinePlan([object]$Plan){
    # PowerShell 7 relit les dates JSON en DateTime ; la garde du recu les ramene en UTC 'o' avant de hasher.
    foreach($date in @('CreatedUtc','ExpiresUtc')){if($Plan.$date -is [DateTime]){$Plan.$date=$Plan.$date.ToUniversalTime().ToString('o')}}
    $copy=[ordered]@{};foreach($p in $Plan.PSObject.Properties){if($p.Name -ne 'Integrity'){$copy[$p.Name]=$p.Value}}
    $Plan.Integrity=Get-PestoStableHash (ConvertTo-PestoCanonicalValue $copy);return $Plan}
function New-ShapedApproval{[pscustomobject]@{Schema=1;Payload=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"Schema":1}'));Certificate=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('fixture-cert'));Signature=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('fixture-signature'))}}
function LedgerPath([string]$OperationId){return Join-Path $script:ledger ($OperationId+'.json')}

try{
 Reset-Offline
 Case 'Import refuses while the offline join policy is off' {
    $cfg=Write-OfflineCfg -Edit{$args[0].POLICY.AllowOfflineJoin=$false}
    RejectWith -body {Import-Blob -ConfigPath $cfg} -Needle 'Jonction hors connexion desactivee par la politique.'
    Equal (@(FilesUnder $script:store).Count) 0 'l import a ecrit dans le magasin malgre la politique'
    Equal $script:protectCalls 0 'le blob a ete chiffre malgre la politique'
    } -Reset
 Case 'Import requires an explicit -Execute' {
    $blob=New-BlobFile
    RejectWith -body {Invoke-Offline -Action 'OfflineImport' -Params @{BlobPath=$blob;ObjectGuid=([Guid]$accountGuidValue);TargetOU=$targetOuValue}} -Needle 'Import ou application ODJ exige -Execute explicite.'
    Equal (@(FilesUnder $script:store).Count) 0 'l import sans -Execute a ecrit dans le magasin'
    } -Reset
 Case 'Apply requires an explicit -Execute' {
    $import=Import-Blob
    Equal $import.ExitCode 0 $import.Message
    RejectWith -body {Invoke-Offline -Action 'OfflineApply' -Params @{BlobId=$import.BlobId}} -Needle 'Import ou application ODJ exige -Execute explicite.'
    Equal $script:native 0 'djoin a ete appele sans -Execute'
    } -Reset
 Case 'Import protects the blob and publishes only its hash' {
    $blob=New-BlobFile
    $r=Import-Blob -BlobPath $blob
    Equal $r.ExitCode 0 $r.Message;Equal $r.State 'Imported';Equal $r.SourceRetained $true
    Equal $r.BlobId (Sha256Hex $script:blobText) 'l identifiant du blob n est pas son empreinte SHA256'
    $paths=Get-PestoOfflinePaths $r.BlobId
    Equal ([IO.Path]::GetDirectoryName($paths.State)) $script:store 'le recu d etat est hors du magasin protege'
    Equal ([IO.Path]::GetDirectoryName($paths.Secret)) $script:store 'le secret protege est hors du magasin protege'
    Assert ([IO.File]::Exists($paths.State)) 'le recu d etat est absent'
    Assert ([IO.File]::Exists($paths.Secret)) 'le secret protege est absent'
    $state=[IO.File]::ReadAllText($paths.State);$secret=[IO.File]::ReadAllText($paths.Secret)
    Assert (-not $state.Contains($canary)) 'le recu d etat porte le blob en clair'
    Assert (-not $secret.Contains($canary)) 'le fichier protege porte le blob en clair'
    Assert (-not $secret.Contains('ODJ-BLOB')) 'le fichier protege porte le marqueur du blob'
    Assert ([IO.File]::Exists($blob)) 'l import a supprime le fichier source sans y etre autorise'
    Equal $script:protectCalls 1 'le blob n a pas ete chiffre exactement une fois'
    $plan=$r.Plan
    Equal $plan.Action 'OfflineJoin';Equal $plan.Purpose 'PestoPreparedPlan'
    Equal $plan.Computer $hostNameValue;Equal $plan.NewName $hostNameValue
    Equal $plan.TargetOU $targetOuValue;Equal $plan.ObjectGuid $accountGuidValue
    Equal $plan.Domain 'EXAMPLE.LOCAL';Equal $plan.MachineId $machineValue
    Equal $plan.BlobSHA256 $r.BlobId
    Equal $plan.ConfigStamp (Get-PestoConfigurationSignature (Read-JsonFile $script:cfgFile)) 'l empreinte de configuration du plan ODJ est fausse'
    Assert ($plan.Integrity -cmatch '^[a-f0-9]{64}$') 'le plan ODJ n est pas scelle'
    Assert (-not (($r|ConvertTo-Json -Depth 8 -Compress).Contains($canary))) 'le blob fuite dans le resultat rendu'
    } -Reset
 Case 'The same blob cannot be imported twice' {
    $blob=New-BlobFile
    $first=Import-Blob -BlobPath $blob
    Equal $first.ExitCode 0 $first.Message
    $state=[IO.File]::ReadAllText((Get-PestoOfflinePaths $first.BlobId).State)
    RejectWith -body {Import-Blob -BlobPath $blob} -Needle 'Ce blob a deja ete importe. Reprendre son observation, jamais le rejouer.'
    Equal ([IO.File]::ReadAllText((Get-PestoOfflinePaths $first.BlobId).State)) $state 'le second import a reecrit le recu'
    Equal $script:protectCalls 1 'le blob a ete chiffre une seconde fois'
    } -Reset
 Case 'An empty blob is refused' {
    RejectWith -body {Import-Blob -BlobPath (New-BlobFile -Text '')} -Needle 'Blob ODJ vide ou trop volumineux.'
    Equal (@(FilesUnder $script:store).Count) 0
    } -Reset
 Case 'An oversized blob is refused' {
    RejectWith -body {Import-Blob -BlobPath (New-BlobFile -Text ('x'*1048577))} -Needle 'Blob ODJ vide ou trop volumineux.'
    Equal (@(FilesUnder $script:store).Count) 0
    Equal $script:protectCalls 0
    } -Reset
 Case 'A directory handed over as the blob is refused' {
    RejectWith -body {Import-Blob -BlobPath $script:blobs} -Needle 'Blob ODJ vide ou trop volumineux.'
    Equal (@(FilesUnder $script:store).Count) 0
    } -Reset
 Case 'A missing blob file is refused before anything is stored' {
    Reject -body {Import-Blob -BlobPath (Join-Path $script:blobs 'absent.odj')}
    Equal (@(FilesUnder $script:store).Count) 0
    Equal $script:protectCalls 0
    } -Reset
 Case 'A machine already joined to the domain cannot import' {
    $script:local.PartOfDomain=$true
    RejectWith -body {Import-Blob} -Needle 'ODJ exige un poste local hors domaine, sans renommage en attente.'
    Equal (@(FilesUnder $script:store).Count) 0
    } -Reset
 Case 'A pending rename refuses the import' {
    $script:local.PendingRename=$true
    RejectWith -body {Import-Blob} -Needle 'ODJ exige un poste local hors domaine, sans renommage en attente.'
    } -Reset
 Case 'A non elevated operator refuses the import' {
    $script:local.Admin=$false
    RejectWith -body {Import-Blob} -Needle 'ODJ exige un poste local hors domaine, sans renommage en attente.'
    } -Reset
 Case 'A domain controller role refuses the import' {
    $script:local.DomainRole=5
    RejectWith -body {Import-Blob} -Needle 'ODJ exige un poste local hors domaine, sans renommage en attente.'
    $script:local.DomainRole=6
    RejectWith -body {Import-Blob} -Needle 'ODJ exige un poste local hors domaine, sans renommage en attente.'
    $script:local.DomainRole=1
    RejectWith -body {Import-Blob} -Needle 'ODJ exige un poste local hors domaine, sans renommage en attente.'
    } -Reset
 Case 'The provisioning account GUID is required' {
    RejectWith -body {Import-Blob -NoGuid} -Needle 'GUID et OU du compte provisionne requis dans le domaine configure.'
    } -Reset
 Case 'A target OU outside the configured scope is refused' {
    RejectWith -body {Import-Blob -TargetOU 'OU=Inconnu,DC=example,DC=local'} -Needle 'GUID et OU du compte provisionne requis dans le domaine configure.'
    RejectWith -body {Import-Blob -TargetOU 'OU=Postes,OU=Organisme,DC=other,DC=local'} -Needle 'GUID et OU du compte provisionne requis dans le domaine configure.'
    RejectWith -body {Import-Blob -TargetOU 'poste.example.local'} -Needle 'GUID et OU du compte provisionne requis dans le domaine configure.'
    } -Reset
 Case 'A debug flag in the configuration aborts the import' {
    $cfg=Write-OfflineCfg -Edit{$args[0].DEBUG.Simulation='true'}
    RejectWith -body {Import-Blob -ConfigPath $cfg} -Needle 'Configuration DEBUG interdite pour ODJ.'
    Equal (@(FilesUnder $script:store).Count) 0
    } -Reset
 Case 'Incident mode suspends the offline import' {
    $cfg=Write-OfflineCfg -Edit{$args[0].POLICY|Add-Member -NotePropertyName IncidentMode -NotePropertyValue $true -Force}
    RejectWith -body {Import-Blob -ConfigPath $cfg} -Needle 'Jonction hors connexion desactivee par la politique.'
    } -Reset
 Case 'A read-only session refuses the import but a writable one proceeds' {
    $blob=New-BlobFile
    $env:PESTO_READONLY_SESSION='1'
    try{
        RejectWith -body {Import-Blob -BlobPath $blob} -Needle 'Jonction hors connexion desactivee par la politique.'
        Equal (@(FilesUnder $script:store).Count) 0
    }finally{$env:PESTO_READONLY_SESSION=''}
    $r=Import-Blob -BlobPath $blob
    Equal $r.ExitCode 0 $r.Message
    } -Reset
 Case 'A coordination registry is refused for offline join' {
    $cfg=Write-OfflineCfg -Edit{$args[0].POLICY.CoordinationRoot='/srv/coordination'}
    RejectWith -body {Import-Blob -ConfigPath $cfg} -Needle 'ODJ hors ligne incompatible avec une coordination ou exclusion de groupes exigeant AD.'
    } -Reset
 Case 'Excluded group identities are refused for offline join' {
    $cfg=Write-OfflineCfg -Edit{$args[0].POLICY.ExcludedGroupGuids=@($accountGuidValue)}
    RejectWith -body {Import-Blob -ConfigPath $cfg} -Needle 'ODJ hors ligne incompatible avec une coordination ou exclusion de groupes exigeant AD.'
    } -Reset
 Case 'Apply writes the durable intention before djoin and calls it once' {
    $import=Import-Blob
    $r=Apply-Blob -BlobId $import.BlobId
    Equal $r.ExitCode 3010 $r.Message;Equal $r.State 'PendingRestart'
    Equal $r.RestartRequired $true;Equal $r.ReplayAllowed $false
    Equal $script:native 1 'djoin n a pas ete appele exactement une fois'
    Equal $script:unprotectCalls 1 'le secret n a pas ete dechiffre exactement une fois'
    $paths=Get-PestoOfflinePaths $import.BlobId
    Assert (-not [IO.File]::Exists($paths.Plain)) 'le fichier transitoire a survecu a la tentative'
    Assert (-not [IO.File]::Exists($paths.Secret)) 'le secret protege a survecu a l application'
    $record=Read-PestoOfflineRecord $import.BlobId
    Equal $record.State 'PendingRestart';Equal $record.OperationId $r.OperationId;Equal $record.NativeCode 0
    $ledger=Read-PestoIntervention (LedgerPath $r.OperationId)
    Equal $ledger.OfflineJoin 'PendingRestart';Equal $ledger.Phase 'PendingRestart';Equal $ledger.ResultCode 10
    } -Reset
 Case 'A second application never calls djoin again' {
    $import=Import-Blob
    $first=Apply-Blob -BlobId $import.BlobId
    Equal $first.ExitCode 3010 $first.Message
    $again=Apply-Blob -BlobId $import.BlobId
    Equal $again.ExitCode 97;Equal $again.State 'PendingRestart';Equal $again.ReplayAllowed $false
    Equal $script:native 1 'une seconde application a rappele djoin'
    } -Reset
 Case 'A machine renamed after the import cannot apply' {
    $import=Import-Blob
    $script:local.Computer='AUTRE-POSTE'
    RejectWith -body {Apply-Blob -BlobId $import.BlobId} -Needle 'Contexte ODJ change ou delai d application expire.'
    Equal $script:native 0 'djoin a ete appele sur un poste qui n est plus la cible'
    } -Reset
 Case 'Another operator machine identity refuses the application' {
    $import=Import-Blob
    $script:local.MachineId='99999999-9999-9999-9999-999999999999'
    RejectWith -body {Apply-Blob -BlobId $import.BlobId} -Needle 'Contexte ODJ change ou delai d application expire.'
    Equal $script:native 0
    } -Reset
 Case 'An expired application window refuses djoin' {
    $import=Import-Blob
    Edit-OfflineRecord -Id $import.BlobId -Edit{param($d) $d.Plan.ExpiresUtc=[DateTime]::UtcNow.AddMinutes(-5).ToString('o');[void](Resign-OfflinePlan $d.Plan)}
    RejectWith -body {Apply-Blob -BlobId $import.BlobId} -Needle 'Contexte ODJ change ou delai d application expire.'
    Equal $script:native 0 'djoin a ete appele apres l echeance'
    } -Reset
 Case 'A configuration change after the import refuses the application' {
    $import=Import-Blob
    $cfg=Write-OfflineCfg -Edit{$args[0].POLICY.MaxBatch=150}
    RejectWith -body {Apply-Blob -BlobId $import.BlobId -ConfigPath $cfg} -Needle 'Contexte ODJ change ou delai d application expire.'
    Equal $script:native 0
    } -Reset
 Case 'A tampered state record is refused before any native call' {
    $import=Import-Blob
    Edit-OfflineRecord -Id $import.BlobId -Edit{$args[0].Plan.TargetOU='OU=Staging,OU=Postes,OU=Organisme,DC=example,DC=local'}
    RejectWith -body {Apply-Blob -BlobId $import.BlobId} -Needle 'Identite ou integrite du plan ODJ invalide.'
    Equal $script:native 0 'le plan altere a quand meme ete applique'
    } -Reset
 Case 'A record whose plan points at another blob is refused' {
    $import=Import-Blob
    Edit-OfflineRecord -Id $import.BlobId -Edit{param($d) $d.Plan.BlobSHA256=('b'*64);[void](Resign-OfflinePlan $d.Plan)}
    RejectWith -body {Apply-Blob -BlobId $import.BlobId} -Needle 'Recu ODJ invalide.'
    Equal $script:native 0
    } -Reset
 Case 'A protected file that no longer decrypts to the planned blob is refused' {
    $import=Import-Blob
    $other=Import-Blob -BlobPath (New-BlobFile -Text ('autre-blob-'+$canary) -Name 'autre.odj')
    Equal $other.ExitCode 0 $other.Message
    $mine=Get-PestoOfflinePaths $import.BlobId;$theirs=Get-PestoOfflinePaths $other.BlobId
    [IO.File]::Copy($theirs.Secret,$mine.Secret,$true)
    RejectWith -body {Apply-Blob -BlobId $import.BlobId} -Needle 'Blob decrypte different du plan.'
    Equal $script:native 0 'un secret qui ne correspond pas au plan a quand meme ete remis a djoin'
    } -Reset
 Case 'An oversized protected file is refused' {
    $import=Import-Blob
    $paths=Get-PestoOfflinePaths $import.BlobId
    [IO.File]::WriteAllText($paths.Secret,('A'*3145728),[Text.UTF8Encoding]::new($false))
    RejectWith -body {Apply-Blob -BlobId $import.BlobId} -Needle 'Secret protege invalide.'
    Equal $script:native 0
    } -Reset
 Case 'A leftover plaintext file is never silently reused' {
    $import=Import-Blob
    $paths=Get-PestoOfflinePaths $import.BlobId
    [IO.File]::WriteAllText($paths.Plain,'residu-d-une-panne-precedente',[Text.UTF8Encoding]::new($false))
    Reject -body {Apply-Blob -BlobId $import.BlobId}
    Equal $script:native 0 'djoin a ete appele malgre un residu en clair'
    Equal (Read-PestoOfflineRecord $import.BlobId).State 'Uncertain' 'la tentative echouee n est pas marquee incertaine'
    } -Reset
 Case 'An interrupted application stays uncertain and is never replayed' {
    $import=Import-Blob
    $script:nativeFail=$true
    RejectWith -body {Apply-Blob -BlobId $import.BlobId} -Needle 'fixture native interruption'
    $script:nativeFail=$false
    Equal (Read-PestoOfflineRecord $import.BlobId).State 'Uncertain' 'une coupure n est pas marquee incertaine'
    $again=Apply-Blob -BlobId $import.BlobId
    Equal $again.ExitCode 97;Equal $script:native 1 'une application coupee a ete rejouee'
    Assert (-not [IO.File]::Exists((Get-PestoOfflinePaths $import.BlobId).Plain)) 'le fichier transitoire a survecu a la coupure'
    } -Reset
 Case 'A nonzero native code is reported uncertain without replay' {
    $import=Import-Blob
    $script:nativeCode=33561
    $r=Apply-Blob -BlobId $import.BlobId
    Equal $r.ExitCode 97;Equal $r.State 'Uncertain';Equal $script:native 1
    Equal (Read-PestoOfflineRecord $import.BlobId).State 'Uncertain'
    $again=Apply-Blob -BlobId $import.BlobId
    Equal $again.ExitCode 97;Equal $script:native 1 'un code natif inconnu a ete rejoue'
    } -Reset
 Case 'The engine policy guard suspends the application for an excluded computer' {
    $cfg=Write-OfflineCfg -Edit{$args[0].POLICY.ExcludedNames=@($hostNameValue)}
    $import=Import-Blob -ConfigPath $cfg
    Equal $import.ExitCode 0 $import.Message
    RejectWith -body {Apply-Blob -BlobId $import.BlobId -ConfigPath $cfg} -Needle 'Cible exclue par la politique : '
    Equal $script:native 0 'la politique d exclusion n a pas arrete djoin'
    } -Reset
 Case 'The engine policy guard suspends the application for an excluded OU' {
    $cfg=Write-OfflineCfg -Edit{$args[0].POLICY.ExcludedOUs=@($targetOuValue)}
    $import=Import-Blob -ConfigPath $cfg
    Equal $import.ExitCode 0 $import.Message
    RejectWith -body {Apply-Blob -BlobId $import.BlobId -ConfigPath $cfg} -Needle 'Un emplacement du plan est exclu par la politique.'
    Equal $script:native 0
    } -Reset
 Case 'A campaign tagged offline plan requires an approval' {
    $import=Import-Blob -Metadata ([pscustomobject]@{Campaign='campagne-a'})
    Equal $import.ExitCode 0 $import.Message
    $script:campaignPolicy=[pscustomobject]@{Campaigns=@('campagne-a');Signers=@()}
    RejectWith -body {Apply-Blob -BlobId $import.BlobId -Approval ([pscustomobject]@{})} -Needle 'Champ obligatoire absent : Schema'
    RejectWith -body {Apply-Blob -BlobId $import.BlobId -Approval (New-ShapedApproval)} -Needle 'Certificat approbateur non approuve.'
    Equal $script:native 0 'une demande de campagne a ete appliquee sans accord'
    } -Reset
 Case 'A campaign outside the approved list is applied without approval' {
    $import=Import-Blob -Metadata ([pscustomobject]@{Campaign='campagne-b'})
    $script:campaignPolicy=[pscustomobject]@{Campaigns=@('campagne-a');Signers=@()}
    $apply=Apply-Blob -BlobId $import.BlobId
    Equal $apply.ExitCode 3010 $apply.Message
    Equal $script:native 1 'une campagne hors liste a ete refusee a tort'
    } -Reset
 Case 'Observe refuses -Execute and never calls djoin' {
    $import=Import-Blob
    $apply=Apply-Blob -BlobId $import.BlobId
    Equal $apply.ExitCode 3010 $apply.Message
    RejectWith -body {Invoke-Offline -Action 'OfflineObserve' -Params @{BlobId=$import.BlobId;Execute=$true}} -Needle 'Observation sans execution.'
    Equal $script:native 1
    } -Reset
 Case 'Observe before the reboot stays uncertain and leaves the receipt untouched' {
    $import=Import-Blob
    $apply=Apply-Blob -BlobId $import.BlobId
    $path=LedgerPath $apply.OperationId;$before=[IO.File]::ReadAllText($path)
    $o=Observe-Blob -BlobId $import.BlobId
    Equal $o.State 'Uncertain';Equal $o.ExitCode 97;Equal $o.TargetReadOnly $true;Equal $o.ReplayAllowed $false
    Equal $o.IdentityConfirmed $false;Equal $o.SecureChannel $false
    Equal ([IO.File]::ReadAllText($path)) $before 'l observation a reecrit le recu sans redemarrage'
    Equal (Read-PestoOfflineRecord $import.BlobId).State 'PendingRestart'
    } -Reset
 Case 'Observe without a verified secure channel stays uncertain' {
    $import=Import-Blob
    $apply=Apply-Blob -BlobId $import.BlobId
    Set-JoinedLocal
    $path=LedgerPath $apply.OperationId;$before=[IO.File]::ReadAllText($path)
    $o=Observe-Blob -BlobId $import.BlobId
    Equal $o.State 'Uncertain';Equal $o.IdentityConfirmed $true;Equal $o.SecureChannel $false
    Equal $script:channelChecks 1 'le canal securise n a pas ete interroge'
    Equal ([IO.File]::ReadAllText($path)) $before 'un canal non verifie a clos le recu'
    } -Reset
 Case 'Observe reconciles reboot, name, GUID, OU and secure channel' {
    $import=Import-Blob
    $apply=Apply-Blob -BlobId $import.BlobId
    Set-JoinedLocal;$script:secure=$true
    $credential=[pscredential]::new('EXAMPLE\operateur',(ConvertTo-SecureString $canary -AsPlainText -Force))
    $o=Observe-Blob -BlobId $import.BlobId -CredentialValue $credential
    Equal $o.State 'Verified' ('observation : '+$o.State);Equal $o.ExitCode 0
    Equal $o.IdentityConfirmed $true;Equal $o.SecureChannel $true
    Equal (Read-PestoOfflineRecord $import.BlobId).State 'Verified'
    $ledger=Read-PestoIntervention (LedgerPath $apply.OperationId)
    Equal $ledger.OfflineJoin 'Verified';Equal $ledger.Phase 'Verified';Equal $ledger.ResultCode 30
    Equal $ledger.VerifiedBy 'S-1-5-21-222'
    Equal $script:adReads 1 'l observation a relu l annuaire plus d une fois'
    Assert ($script:lastAdParams.Server -ceq 'dc.example.local') ('controleur transmis a la relecture : '+[string]$script:lastAdParams.Server)
    Assert ($script:lastAdParams.Credential -is [pscredential]) 'aucun PSCredential transmis a la relecture AD'
    Assert ($null -eq $script:cred) 'la credential reste dans la portee du moteur apres l observation'
    Assert (-not ((($o|ConvertTo-Json -Depth 8 -Compress)).Contains($canary))) 'la credential fuite dans le resultat rendu'
    } -Reset
 Case 'Observe refuses a directory object that moved' {
    $import=Import-Blob
    $apply=Apply-Blob -BlobId $import.BlobId
    Set-JoinedLocal;$script:secure=$true
    $script:pc.DistinguishedName=('CN='+$hostNameValue+',OU=Staging,OU=Postes,OU=Organisme,DC=example,DC=local')
    $o=Observe-Blob -BlobId $import.BlobId
    Equal $o.State 'Uncertain';Equal $o.IdentityConfirmed $false
    Equal (Read-PestoOfflineRecord $import.BlobId).State 'PendingRestart' 'une cible deplacee a clos le recu'
    } -Reset
 Case 'Observe refuses a blob that was never applied' {
    $import=Import-Blob
    RejectWith -body {Observe-Blob -BlobId $import.BlobId} -Needle 'Blob non applique.'
    Equal $script:adReads 0 'l observation a lu l annuaire sans demande enregistree'
    } -Reset
 Case 'A read-only observation never confirms the receipt' {
    $import=Import-Blob
    $apply=Apply-Blob -BlobId $import.BlobId
    Set-JoinedLocal;$script:secure=$true
    $path=LedgerPath $apply.OperationId;$before=[IO.File]::ReadAllText($path)
    $env:PESTO_READONLY_SESSION='1'
    try{$o=Observe-Blob -BlobId $import.BlobId}finally{$env:PESTO_READONLY_SESSION=''}
    Equal $o.State 'Verified';Equal $o.ExitCode 0
    Equal ([IO.File]::ReadAllText($path)) $before 'une observation en consultation a reecrit le recu'
    [void](Observe-Blob -BlobId $import.BlobId)
    Assert ([IO.File]::ReadAllText($path) -cne $before) 'l observation writable n a rien consigne'
    } -Reset
 Case 'Observe refuses a receipt without an offline join intention' {
    $import=Import-Blob
    $apply=Apply-Blob -BlobId $import.BlobId
    Set-JoinedLocal;$script:secure=$true
    $path=LedgerPath $apply.OperationId
    $doc=Read-JsonFile $path;$doc.OfflineJoin='';Write-JsonFile $path $doc
    RejectWith -body {Observe-Blob -BlobId $import.BlobId} -Needle 'Recu intervention ODJ incoherent.'
    } -Reset
 Case 'A blob identifier outside the hexadecimal form is refused' {
    RejectWith -body {Observe-Blob -BlobId '../../../etc/passwd'} -Needle 'Identifiant ODJ invalide.'
    RejectWith -body {Apply-Blob -BlobId ('Z'*64)} -Needle 'Identifiant ODJ invalide.'
    RejectWith -body {Apply-Blob -BlobId ''} -Needle 'Identifiant ODJ invalide.'
    Equal $script:native 0
    } -Reset
 Case 'The offline transport never asks for an online join or a repair' {
    Assert ($nativeSource.Contains('/requestodj') -and $nativeSource.Contains('/loadfile') -and $nativeSource.Contains('/localos')) 'le transport natif ne joue plus le contrat djoin /requestodj /loadfile /localos'
    Assert (-not $nativeSource.Contains('/machine')) 'le transport natif transmet une identite de machine en argument'
    Assert (-not ($nativeSource -match '/p\b|/rp\b|password')) 'le transport natif vehicule un secret en ligne de commande'
    Assert ($protectSource.Contains('ProtectedData') -and $protectSource.Contains('LocalMachine')) 'le secret n est plus protege par DPAPI LocalMachine'
    Assert ($unprotectSource.Contains('ProtectedData') -and $unprotectSource.Contains('LocalMachine')) 'le secret n est plus dechiffre par DPAPI LocalMachine'
    Assert (-not $applySource.Contains('Add-Computer') -and -not $applySource.Contains('AddToDomain') -and -not $applySource.Contains('Invoke-PestoUnattendedJoin')) 'le parcours hors connexion rappelle la jonction en ligne'
    Assert ($observeSource.Contains('Test-ComputerSecureChannel') -and -not $observeSource.Contains('Add-Computer') -and -not $observeSource.Contains('Invoke-PestoOfflineApply')) 'l observation repare ou relance une jonction'
    Assert ($applySource.Contains('CreateNew')) 'le fichier transitoire n est plus cree en exclusivite'
    Assert ($importSource.Contains('Array]::Clear')) 'les tampons du blob ne sont plus effaces'
    } -Reset
 Case 'No blob material reaches the receipts or the automation store' {
    $import=Import-Blob
    $apply=Apply-Blob -BlobId $import.BlobId
    Set-JoinedLocal;$script:secure=$true
    $o=Observe-Blob -BlobId $import.BlobId
    Equal $o.State 'Verified' ('cycle incomplet : '+$o.State)
    $files=@(FilesUnder $script:store)+@(FilesUnder $script:ledger)+@(FilesUnder $script:automationStore)
    Assert ($files.Count -ge 2) ('peu de traces produites : '+$files.Count)
    foreach($file in $files){
        $text=[IO.File]::ReadAllText($file.FullName)
        Assert (-not $text.Contains($canary)) ('le blob fuite en clair dans '+$file.Name)
        Assert (-not ($text -match '(?i)protecteddata|dpapi')) ('un detail de protection du secret parait dans '+$file.Name)
        }
    Assert (-not ((($import|ConvertTo-Json -Depth 10 -Compress)).Contains($canary))) 'le blob fuite dans le resultat d import'
    Assert (-not ((($o|ConvertTo-Json -Depth 10 -Compress)).Contains($canary))) 'le blob fuite dans le resultat d observation'
    } -Reset
}finally{
    $env:PESTO_READONLY_SESSION=''
    if([IO.Directory]::Exists($root)){[IO.Directory]::Delete($root,$true)}
}
$report=[pscustomobject]@{Schema=1;Suite='OfflineJoin109Entry';HostOS=[Environment]::OSVersion.ToString();PowerShell=$PSVersionTable.PSVersion.ToString();WindowsExecuted=$false;ADExecuted=$false;WPFExecuted=$false;GPOApplied=$false;RegistryWritten=$false;Scope='Point d entree public Invoke-PestoExtensionCommand joue reellement sur OfflineImport, OfflineApply et OfflineObserve (contexte ODJ, plan scelle, recus, garde de politique, approbation de campagne) ; plateforme, paquet, socle, module AD, cmdlets AD, canal securise, DPAPI, djoin, ACL et magasins doubles ; aucun appel reseau ni VM';Total=$script:passed+$script:failed;Passed=$script:passed;Failed=$script:failed}
if($ReportPath){[IO.File]::WriteAllText([IO.Path]::GetFullPath($ReportPath),($report|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))}
Write-Host "OfflineJoin109Entry: $script:passed passed, $script:failed failed. Public entry point played for the three offline join actions; durable intent, receipts and policy guards real; AD/DPAPI/djoin/ACL transports mocked; no VM."
if($script:failed){exit 1}
