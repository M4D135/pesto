#requires -Version 5.1
[CmdletBinding()]
param([string]$ReportPath='')
$ErrorActionPreference='Stop';Set-StrictMode -Off
# Point 109, sous-lot « le blob secret a l entree du magasin ». L evaluation « jonction hors connexion : blob
# secret » (EXTENSIONS_120.md, section 109 : « import DPAPI local sous ACL administrateur/SYSTEM, intention
# durable avant djoin, application unique ») se joue d abord dans Import-PestoOfflineBlob : c'est la que le
# fichier remis par l'operateur devient un identifiant, un plan scelle et un secret protege, et que Read-PestoOfflineRecord
# le rend ensuite a l'application et a l'observation. Les trois suites existantes du point ne jugent aucune de ces
# gardes une par une : Run-OfflineJoin109EntryTests.ps1 ne joue que le point d'entree public et n'amene le blob a
# Imported qu'une fois, Run-OfflineJoin109ObserveTests.ps1 importe pour preparer l'observation sans controler
# l'import, et Run-OfflineJoin109NativeTests.ps1 juge le transport sur l'arbre syntaxique. Un sondage consigne dans
# DEV/docs/implementation/proofs/OFFLINE_JOIN_109_BLOB_20261025.json le mesure au lieu de l'affirmer : seize
# reecritures de ces gardes (retrait du controle de poste joint, de renommage en attente, d'administration, de role
# de domaine, du GUID vide, du perimetre d'OU, du domaine de l'OU, de la taille minimale, de la taille maximale, du
# controle de conteneur, de la seconde moitie du garde de rejeu, de la relecture du chemin clair du secret, de la
# comparaison d'empreinte du recu, de la comparaison d'empreinte du plan, du domaine du plan et de l'identite de
# machine du plan), chacune rejouee contre les trois suites existantes. Douze sont vues, presque toutes par la suite
# du point d'entree ; quatre laissent les trois suites a 48/48, 21/21 et 20/20 : le rejeu qui ne regarde plus le
# cote secret, la relecture du chemin clair du secret avant ecriture, l'empreinte propre du recu et l'identite de
# machine du plan. Ces quatre-la sont rejouees contre cette suite, qui doit les faire rougir. Cette suite n'aime
# donc rien d'autre : elle amene le poste a un etat
# reellement eligible, ne viole qu'une seule condition par cas et exige le message de la garde visee, car la meme
# forme est refusee plus loin par une autre garde. Ce qui est reel ici : le point d'entree public
# Invoke-PestoExtensionCommand sous -Action OfflineImport avec -Execute, Initialize-PestoOfflineContext, la lecture
# des octets, Get-PestoBytesHash, Get-PestoOfflinePaths, New-PestoPortablePlan, le scellement du plan par
# Get-PestoStableHash et ConvertTo-PestoCanonicalValue, l'ecriture durable du recu, Assert-PestoPlainPath,
# Write-PestoAtomicText, Read-PestoAutomationJson et la relecture complete Read-PestoOfflineRecord. Les doubles
# restent a la frontiere Windows : plateforme, integrite du paquet, socle commun, statut local du poste, ACL du
# magasin, DPAPI et magasins ProgramData. Aucun appel reseau, aucune VM, aucun cfg.json operationnel lu : la
# configuration vient du modele neutre DEV/tools/cfg.modele-complet.json recopie dans un dossier temporaire.
$dev=Split-Path $PSScriptRoot -Parent
$runtime=Join-Path $dev 'wad/Pesto.Engine.Runtime.ps1'
. $runtime
$script:passed=0;$script:failed=0
function Assert($v,$why='Assertion failed'){if(-not $v){throw $why}}
function Equal($actual,$expected,[string]$why=''){if($actual -cne $expected){throw ('attendu ['+$expected+'] obtenu ['+[string]$actual+'] '+$why)}}
function Case($name,[scriptblock]$body,[switch]$Reset){try{&$body;$script:passed++}catch{$script:failed++;Write-Host ('FAIL '+$name+': '+$_)}finally{if($Reset){Reset-Blob}}}
# Un refus n'est prouve que par la garde qui l'emet : la meme forme peut etre refusee plus loin, ce qui laisserait
# passer la garde amont. Le message est donc exige.
function RejectWith([scriptblock]$body,[string]$Needle){$caught='<aucun refus>';try{&$body|Out-Null}catch{$caught=[string]$_.Exception.Message};Assert ($caught.Contains($Needle)) ('refus attendu : '+$Needle+' ; obtenu : '+$caught)}
function Accept-Nothing([scriptblock]$body){$caught='<aucun refus>';try{&$body|Out-Null}catch{$caught=[string]$_.Exception.Message};Assert ($caught -eq '<aucun refus>') ('refus inattendu : '+$caught)}
function Read-JsonFile([string]$Path){Assert ([IO.File]::Exists($Path)) ('fichier absent : '+$Path);return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json)}
function Write-JsonFile([string]$Path,$Document){[IO.File]::WriteAllText($Path,($Document|ConvertTo-Json -Depth 14),[Text.UTF8Encoding]::new($false))}
# ConvertFrom-Json rend toute chaine ISO en DateTime, et cette conversion n'est pas stable d'un instant a l'autre
# (le nombre de chiffres de la partie fractionnaire change le rendu). Le produit normalise lui-meme ses instants
# avant de sceller : le recalcul independant doit repartir de la meme forme, sinon c'est la fixture qui serait
# jugee et non l'empreinte du plan. Les trois Kind possibles convergent vers l'instant UTC tel qu'il a ete ecrit.
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
function FilesUnder([string]$Dir){if(-not[IO.Directory]::Exists($Dir)){return @()};return @(Get-ChildItem -LiteralPath $Dir -File|Sort-Object Name)}
# Lectures de l'arbre syntaxique scelle : ce que l'execution ne peut pas montrer hors Windows (les octets clairs
# effaces dans le finally, le secret ecrit en base64 et jamais en clair, l'ordre protect-avant-recu).
function AllNodes($Node){return @($Node.FindAll({param($n)$true},$true))}
function OfKind($Node,[string]$Kind){return @(AllNodes $Node|Where-Object{$_.GetType().Name -eq $Kind})}
function MemberInvokes($Node,[string]$Name){return @(OfKind $Node 'InvokeMemberExpressionAst'|Where-Object{$_.Member.Value -eq $Name})}
# Un appel de methode statique et une lecture de propriete statique ne sont pas les memes noeuds : ProtectedData::Protect
# est une invocation, DataProtectionScope::LocalMachine une simple lecture de membre.
function MemberReads($Node,[string]$Name){return @(OfKind $Node 'MemberExpressionAst'|Where-Object{$_.Member.Value -eq $Name})}
function CommandAsts($Node){return @(OfKind $Node 'CommandAst')}
function CommandInvokes($Node,[string]$Name){return @(CommandAsts $Node|Where-Object{$_.GetCommandName() -eq $Name})}
function VariableUses($Node,[string]$Name){return @(OfKind $Node 'VariableExpressionAst'|Where-Object{$_.VariablePath.UserPath -eq $Name})}
# La profondeur de serialisation du receveur durable est lue dans sa definition scellee : le double doit reproduire
# le produit, sinon le test validerait un format que le produit n'emet pas.
$writerSource=(Get-Command Write-PestoJoinReceipt).Definition
$writerMatch=[regex]::Match($writerSource,'ConvertTo-Json\s+-Depth\s+(\d+)')
if(-not $writerMatch.Success){throw 'La profondeur de serialisation du recus durable nest plus lisible dans Write-PestoJoinReceipt.'}
$writerDepth=[int]$writerMatch.Groups[1].Value
$parseTokens=$null;$parseErrors=$null
$script:tree=[System.Management.Automation.Language.Parser]::ParseFile($runtime,[ref]$parseTokens,[ref]$parseErrors)
if($parseErrors -and $parseErrors.Count){throw ('le moteur scelle ne se parse pas : '+$parseErrors[0].Message)}
# Arbre immuable par processus : indexer les definitions une fois, sans modifier les controles des noeuds.
$script:sealedFunctions=@($script:tree.FindAll({param($n)$n -is [System.Management.Automation.Language.FunctionDefinitionAst]},$true))
function SealedFunction([string]$Name){
    $found=@($script:sealedFunctions|Where-Object{$_.Name -eq $Name})
    if($found.Count -ne 1){throw ('la fonction '+$Name+' nest pas trouvee exactement une fois dans le moteur scelle : '+$found.Count)}
    return $found[0]
}
$root=Join-Path $PSScriptRoot ('pesto-offline109blob-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$machineValue='11111111-1111-1111-1111-111111111111'
$accountGuidValue='22222222-2222-2222-2222-222222222222'
$targetOuValue='OU=Postes,OU=Organisme,DC=example,DC=local'
$outOfScopeOuValue='OU=HorsPerimetre,DC=example,DC=local'
$hostNameValue='PESTO-ODJ-109B'
$canary='ODJBLOB'+[Guid]::NewGuid().ToString('N')
$script:fixtureKey=211
$script:cfgTemplate=Get-Content (Join-Path $dev 'tools/cfg.modele-complet.json') -Raw|ConvertFrom-Json

function Write-OfflineCfg {[CmdletBinding()]param([scriptblock]$Edit=$null)
    $cfg=$script:cfgTemplate|ConvertTo-Json -Depth 15|ConvertFrom-Json
    $cfg.POLICY|Add-Member -NotePropertyName AllowOfflineJoin -NotePropertyValue $true -Force
    if($Edit){&$Edit $cfg}
    $path=Join-Path $root ('cfg-'+[Guid]::NewGuid().ToString('N')+'.json')
    [IO.File]::WriteAllText($path,($cfg|ConvertTo-Json -Depth 15),[Text.UTF8Encoding]::new($false))
    return $path}

# Frontiere Windows : ces doubles ne sont la que pour rendre l'import jouable hors Windows. Ils enregistrent ce
# qu'on leur demande et ne jugent rien : chaque controle est formule dans le cas.
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
# DPAPI : double de transport uniquement. Le xor avec une cle de fixture n'est pas de la cryptographie, c'est ce
# qui rend visible sur disque la difference entre le materiel clair et le materiel protege.
function Protect-PestoOfflineBytes {param([byte[]]$Bytes)
    $script:protectCalls++
    if($script:protectFails){throw 'DPAPI indisponible (double).'}
    Assert ($null -ne $Bytes -and $Bytes.Length -gt 0) 'DPAPI recoit un blob vide'
    # Copie, pas reference : le produit efface le tampon clair dans son finally, ce qui est exactement ce qu'on lui
    # demande de faire, et effacerait la trace que ce cas doit pouvoir relire apres le retour.
    $witness=New-Object byte[] $Bytes.Length
    [Array]::Copy($Bytes,$witness,$Bytes.Length)
    $script:lastProtectBytes=$witness
    $out=New-Object byte[] $Bytes.Length
    for($i=0;$i -lt $Bytes.Length;$i++){$out[$i]=[byte]($Bytes[$i] -bxor $script:fixtureKey)}
    return ,$out}
function Unprotect-PestoOfflineBytes {param([byte[]]$Bytes)
    $script:unprotectCalls++
    Assert ($null -ne $Bytes -and $Bytes.Length -gt 0) 'DPAPI recoit un secret vide'
    $out=New-Object byte[] $Bytes.Length
    for($i=0;$i -lt $Bytes.Length;$i++){$out[$i]=[byte]($Bytes[$i] -bxor $script:fixtureKey)}
    return ,$out}
# Le receveur durable est double sur sa seule partie Windows (ACL SYSTEM/Administrateurs) : l'ecriture, la
# desactivation des liens et la serialisation restent celles du produit, a la profondeur lue plus haut.
function Write-PestoJoinReceipt {param($Path,$Receipt)
    $script:receiptWrites++;$script:receiptPaths+=@($Path)
    Write-PestoAtomicText $Path ($Receipt|ConvertTo-Json -Depth $writerDepth)}

function Reset-Blob {
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
    # Etat reel d'un poste pretable a une jonction hors connexion : hors domaine, sans renommage en attente,
    # administrateur, membre d'un groupe de travail (role 0). Le cas n'a plus qu'en violer une seule condition.
    $script:local=[pscustomobject]@{Computer=$hostNameValue;PartOfDomain=$false;PendingRename=$false;Admin=$true;DomainRole=0;MachineId=$machineValue;BootUtc='2026-10-17T10:00:00Z';Domain='WORKGROUP'}
    $script:protectCalls=0;$script:unprotectCalls=0;$script:protectFails=$false;$script:lastProtectBytes=$null
    $script:receiptWrites=0;$script:receiptPaths=@()
    $script:platformChecks=0;$script:packageChecks=0;$script:commonInits=0
    $script:cred=$null
    $env:PESTO_READONLY_SESSION=''
}
function Invoke-Offline {[CmdletBinding()]param([string]$Action,[hashtable]$Params=@{},[string]$ConfigPath)
    $call=@{Action=$Action;RuntimeRoot=$script:wad;ConfigPath=$script:cfgFile}
    foreach($k in $Params.Keys){$call[$k]=$Params[$k]}
    return (Invoke-PestoExtensionCommand @call)}
function New-BlobFile {[CmdletBinding()]param($Bytes,$Name='poste.odj')
    if($null -eq $Bytes){$Bytes=[Text.Encoding]::UTF8.GetBytes($script:blobText)}
    $path=Join-Path $script:blobs $Name
    [IO.File]::WriteAllBytes($path,$Bytes)
    return $path}
# Le GUID n'a pas de valeur par substituee : un cas qui veut jouer le GUID vide doit pouvoir le remettre tel quel,
# sinon la fixture reparerait d'elle-meme ce que le produit doit refuser.
function Import-Blob {[CmdletBinding()]param([string]$BlobPath,$ObjectGuid=$null,[string]$TargetOU='')
    if(-not $BlobPath){$BlobPath=New-BlobFile}
    if($null -eq $ObjectGuid){$ObjectGuid=[Guid]$accountGuidValue}
    if(-not $TargetOU){$TargetOU=$targetOuValue}
    return (Invoke-Offline -Action 'OfflineImport' -Params @{BlobPath=$BlobPath;ObjectGuid=$ObjectGuid;TargetOU=$TargetOU;Execute=$true})}
function Import-Ok {[CmdletBinding()]param([string]$BlobPath,$ObjectGuid=$null,[string]$TargetOU='')
    $r=Import-Blob -BlobPath $BlobPath -ObjectGuid $ObjectGuid -TargetOU $TargetOU
    Equal $r.ExitCode 0 ('import refuse : '+$r.Message)
    Equal $r.State 'Imported'
    return $r}
function ReceiptPath([string]$Id){return Join-Path $script:store ($Id+'.json')}
function SecretPath([string]$Id){return Join-Path $script:store ($Id+'.protected')}
function Sha256Of([byte[]]$Bytes){$h=[Security.Cryptography.SHA256]::Create();try{return ([BitConverter]::ToString($h.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant()}finally{$h.Dispose()}}
# Altere un recu reellement ecrit par le produit. Le re-scellement optionnel recalculerait l'empreinte du plan :
# sans lui, toute alteration du plan serait arretee par la garde d'empreinte en aval et le controle que le cas veut
# jouer ne serait jamais atteint.
function Tamper-Receipt {[CmdletBinding()]param([string]$Id,[scriptblock]$Edit,[switch]$Reseal)
    $path=ReceiptPath $Id;$doc=Read-JsonFile $path;&$Edit $doc
    if($Reseal){$doc.Plan.Integrity=Get-PestoStableHash (ConvertTo-PestoCanonicalValue (Canonical-Plan $doc.Plan))}
    Write-JsonFile $path $doc}
# Un refus d import ne doit rien laisser : ni secret protege, ni trace dans le magasin. Sans cette exigence, une
# garde amont supprimee se verrait compensee par une garde aval qui refuserait quand meme, apres que le secret fut
# ecrit et protege.
function Refused-WithoutTrace([scriptblock]$body,[string]$Needle){
    $caught='<aucun refus>'
    try{&$body|Out-Null}catch{$caught=[string]$_.Exception.Message}
    Assert ($caught.Contains($Needle)) ('refus attendu : '+$Needle+' ; obtenu : '+$caught)
    Equal $script:protectCalls 0 'le materiel a ete protege par DPAPI alors que la garde visee devait refuser avant'
    Equal $script:receiptWrites 0 'un recu a ete ecrit alors que la garde visee devait refuser avant'
    Equal @(FilesUnder $script:store).Count 0 'le magasin porte une trace alors que l import devait etre refuse sans rien ecrire'}

try{
 Reset-Blob

# ---------- A. Le poste doit etre reellement pretable a une jonction hors connexion ----------
$localNeedle='ODJ exige un poste local hors domaine, sans renommage en attente.'
Case 'A machine already joined to a domain cannot import a secret blob' {
    $script:local.PartOfDomain=$true
    Refused-WithoutTrace {Import-Blob} $localNeedle
} -Reset
Case 'A machine with a pending rename cannot import a secret blob' {
    $script:local.PendingRename=$true
    Refused-WithoutTrace {Import-Blob} $localNeedle
} -Reset
Case 'An operator without local administration cannot import a secret blob' {
    $script:local.Admin=$false
    Refused-WithoutTrace {Import-Blob} $localNeedle
} -Reset
Case 'A domain controller role cannot import a secret blob' {
    $script:local.DomainRole=1
    Refused-WithoutTrace {Import-Blob} $localNeedle
} -Reset
Case 'A backup controller role cannot import a secret blob' {
    $script:local.DomainRole=3
    Refused-WithoutTrace {Import-Blob} $localNeedle
} -Reset
Case 'An interoperable role cannot import a secret blob' {
    $script:local.DomainRole=4
    Refused-WithoutTrace {Import-Blob} $localNeedle
} -Reset
Case 'A standalone workstation is accepted as the import context' {
    $script:local.DomainRole=0
    $r=Import-Ok
    Equal $r.BlobId (Sha256Of ([Text.Encoding]::UTF8.GetBytes($script:blobText))) "l'identifiant n'est pas l'empreinte SHA256 du materiel remis"
} -Reset
Case 'A member server is accepted as the import context' {
    $script:local.DomainRole=2
    $r=Import-Ok
    Assert ([IO.File]::Exists((ReceiptPath $r.BlobId))) 'le recu d import manque au magasin'
} -Reset

# ---------- B. Le compte provisionne : GUID et unite organisationnelle ----------
$guidNeedle='GUID et OU du compte provisionne requis dans le domaine configure.'
Case 'The all-zero provisioning account GUID is refused' {
    Refused-WithoutTrace {Import-Blob -ObjectGuid ([Guid]::Empty)} $guidNeedle
} -Reset
Case 'The all-zero provisioning account GUID is refused beside an otherwise valid organisational unit' {
    Refused-WithoutTrace {Import-Blob -ObjectGuid ([Guid]'00000000-0000-0000-0000-000000000000') -TargetOU $targetOuValue} $guidNeedle
} -Reset
Case 'An organisational unit outside the configured scope is refused' {
    Refused-WithoutTrace {Import-Blob -TargetOU $outOfScopeOuValue} $guidNeedle
} -Reset
Case 'An organisational unit of another forest is refused' {
    Refused-WithoutTrace {Import-Blob -TargetOU 'OU=Postes,OU=Organisme,DC=autre,DC=local'} $guidNeedle
} -Reset
Case 'A configuration whose organisational units leave the configured domain is refused before any import' {
    # La troisieme clause de la garde du compte provisionne (domaine de l'OU contre domaine configure) ne peut pas
    # etre atteinte par une configuration reglee : Test-CfgValid refuse deja un OUBase dont le domaine differe de
    # Domaine. Le controle est donc joue a la porte d'entree, ou il est reellement jouable, et la clause garde du
    # produit reste la derniere ligne de surete de ce que la configuration laisse passer.
    $script:cfgFile=Write-OfflineCfg {param($c)$c.CONF[0].Domaine='autre.local'}
    Refused-WithoutTrace {Import-Blob -TargetOU $targetOuValue} 'différent de Domaine'
} -Reset
Case 'A provisioning account GUID and an organisational unit of the configured domain are accepted' {
    $r=Import-Ok -ObjectGuid ([Guid]$accountGuidValue) -TargetOU $targetOuValue
    Equal $r.Plan.ObjectGuid $accountGuidValue "le GUID du compte provisionne n'est pas repris tel quel dans le plan"
} -Reset

# ---------- C. La forme du materiel remis par l'operateur ----------
$sizeNeedle='Blob ODJ vide ou trop volumineux.'
Case 'A directory handed over as the blob is refused' {
    $dossier=Join-Path $script:blobs 'dossier.odj'
    [void][IO.Directory]::CreateDirectory($dossier)
    Refused-WithoutTrace {Import-Blob -BlobPath $dossier} $sizeNeedle
} -Reset
Case 'An empty blob is refused' {
    $path=New-BlobFile -Bytes ([byte[]]@())
    Refused-WithoutTrace {Import-Blob -BlobPath $path} $sizeNeedle
} -Reset
Case 'A blob one byte over the megabyte ceiling is refused' {
    $path=New-BlobFile -Bytes ((New-Object byte[] 1048577))
    Refused-WithoutTrace {Import-Blob -BlobPath $path} $sizeNeedle
} -Reset
Case 'A blob of exactly the megabyte ceiling is accepted' {
    $path=New-BlobFile -Bytes ((New-Object byte[] 1048576))
    $r=Import-Ok -BlobPath $path
    Assert ([IO.File]::Exists((SecretPath $r.BlobId))) 'le secret du blob a la limite haute n est pas protege'
} -Reset
Case 'A single byte blob is accepted' {
    $path=New-BlobFile -Bytes ([byte[]]@(65))
    $r=Import-Ok -BlobPath $path
    Assert ([IO.File]::Exists((SecretPath $r.BlobId))) 'le secret du blob d un octet n est pas protege'
} -Reset
Case 'A blob handed over through a symbolic link is refused before being read' {
    $real=New-BlobFile -Name 'reel.odj'
    $link=Join-Path $script:blobs ('lien-'+[Guid]::NewGuid().ToString('N')+'.odj')
    [void](New-Item -ItemType SymbolicLink -Path $link -Target $real -ErrorAction Stop)
    Refused-WithoutTrace {Import-Blob -BlobPath $link} 'Un chemin critique traverse un lien ou une jonction.'
} -Reset
Case 'A blob handed over from a directory replaced by a junction is refused before being read' {
    $sac=Join-Path $root ('sac-'+[Guid]::NewGuid().ToString('N'))
    $reel=Join-Path $root ('reel-'+[Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($reel)
    $vrai=Join-Path $reel 'poste.odj'
    [IO.File]::WriteAllBytes($vrai,[Text.Encoding]::UTF8.GetBytes($script:blobText))
    [void][IO.Directory]::CreateDirectory($sac)
    [void](New-Item -ItemType SymbolicLink -Path (Join-Path $sac 'sous') -Target $reel -ErrorAction Stop)
    Refused-WithoutTrace {Import-Blob -BlobPath (Join-Path $sac 'sous/poste.odj')} 'Un chemin critique traverse un lien ou une jonction.'
} -Reset

# ---------- D. Le rejeu : un blob secret ne s'importe qu'une fois ----------
$replayNeedle='Ce blob a deja ete importe. Reprendre son observation, jamais le rejouer.'
Case 'The same blob cannot be imported a second time' {
    $path=New-BlobFile
    $first=Import-Ok -BlobPath $path
    RejectWith {Import-Blob -BlobPath $path} $replayNeedle
    Equal $script:protectCalls 1 'le materiel a ete protege une seconde fois alors que le rejeu devait etre arrete avant DPAPI'
    Equal $script:receiptWrites 1 'un second recu a ete ecrit alors que le rejeu devait etre arrete avant toute ecriture'
    Equal @(FilesUnder $script:store).Count 2 'le rejeu a laisse des traces de plus au magasin'
    $reloaded=Read-PestoOfflineRecord $first.BlobId
    Equal $reloaded.State 'Imported' 'le rejeu a fait avancer l etat du blob deja importe'
} -Reset
Case 'A replay is still refused when only the protected secret is left on disk' {
    $path=New-BlobFile
    $first=Import-Ok -BlobPath $path
    [IO.File]::Delete((ReceiptPath $first.BlobId))
    RejectWith {Import-Blob -BlobPath $path} $replayNeedle
    Assert ([IO.File]::Exists((SecretPath $first.BlobId))) 'le secret a ete detruit par la preparation du cas'
    Equal $script:protectCalls 1 'le materiel a ete re-protege alors que la presence du secret devait suffire a refuser'
} -Reset
Case 'A replay is still refused when only the state receipt is left on disk' {
    $path=New-BlobFile
    $first=Import-Ok -BlobPath $path
    [IO.File]::Delete((SecretPath $first.BlobId))
    RejectWith {Import-Blob -BlobPath $path} $replayNeedle
    Assert ([IO.File]::Exists((ReceiptPath $first.BlobId))) 'le recu a ete detruit par la preparation du cas'
    Equal $script:protectCalls 1 'le materiel a ete re-protege alors que la presence du recu devait suffire a refuser'
} -Reset
Case 'A different blob is imported beside the first one without disturbing it' {
    $first=Import-Ok -BlobPath (New-BlobFile -Name 'premier.odj')
    $second=Import-Ok -BlobPath (New-BlobFile -Name 'second.odj' -Bytes ([Text.Encoding]::UTF8.GetBytes($script:blobText+'-autre')))
    Assert ($first.BlobId -ne $second.BlobId) 'deux materiels differents ont recu le meme identifiant'
    Equal @(FilesUnder $script:store).Count 4 'les deux imports ne laissent pas chacun son recu et son secret'
    Equal (Read-PestoOfflineRecord $first.BlobId).State 'Imported' 'le second import a modifie l etat du premier blob'
} -Reset

# ---------- E. Le secret : protege a l'entree, jamais ecrit en clair ----------
Case 'DPAPI is asked exactly once, over the bytes of the file and not its path' {
    $path=New-BlobFile
    $r=Import-Ok -BlobPath $path
    Equal $script:protectCalls 1 'le materiel n a pas ete protege exactement une fois'
    $expected=[IO.File]::ReadAllBytes($path)
    Assert ($null -ne $script:lastProtectBytes) 'DPAPI n a recu aucun materiel'
    Equal $script:lastProtectBytes.Length $expected.Length 'DPAPI ne recoit pas autant d octets que le fichier remis'
    for($i=0;$i -lt $expected.Length;$i++){Equal $script:lastProtectBytes[$i] $expected[$i] ('DPAPI recoit un materiel different du fichier a l octet '+$i)}
} -Reset
Case 'The protected file is the base64 of the protected material and decodes back to the blob' {
    $path=New-BlobFile
    $r=Import-Ok -BlobPath $path
    $stored=[IO.File]::ReadAllText((SecretPath $r.BlobId))
    $decoded=$null
    try{$decoded=[Convert]::FromBase64String($stored)}catch{throw 'le secret protege n est plus du base64 : '+$_.Exception.Message}
    $clear=[IO.File]::ReadAllBytes($path)
    $expected=New-Object byte[] $clear.Length
    for($i=0;$i -lt $clear.Length;$i++){$expected[$i]=[byte]($clear[$i] -bxor $script:fixtureKey)}
    Equal $decoded.Length $expected.Length 'le secret protege n a pas la taille du materiel'
    for($i=0;$i -lt $expected.Length;$i++){Equal $decoded[$i] $expected[$i] ('le secret protege differe du materiel protege a l octet '+$i)}
    $restored=Unprotect-PestoOfflineBytes $decoded
    for($i=0;$i -lt $clear.Length;$i++){Equal $restored[$i] $clear[$i] ('le secret protege ne se reconvertit pas en le blob d origine a l octet '+$i)}
} -Reset
Case 'Nothing in the store carries the blob in the clear, nor the secret in the receipt' {
    $path=New-BlobFile
    $r=Import-Ok -BlobPath $path
    $clearBase64=[Convert]::ToBase64String([IO.File]::ReadAllBytes($path))
    $files=@(FilesUnder $script:store)
    Equal $files.Count 2 'le magasin ne contient pas exactement le recu et le secret'
    foreach($file in $files){
        $text=[IO.File]::ReadAllText($file.FullName)
        Assert (-not $text.Contains($canary)) ('le blob fuite en clair dans '+$file.Name)
        Assert (-not ($text -match '(?i)protecteddata|dpapi')) ('un detail de protection du secret parait dans '+$file.Name)
    }
    $receipt=Read-JsonFile (ReceiptPath $r.BlobId)
    $receiptText=$receipt|ConvertTo-Json -Depth 14
    Assert (-not $receiptText.Contains($canary)) 'le recu porte le materiel clair'
    Assert (-not $receiptText.Contains($clearBase64)) 'le recu porte le materiel clair encode'
    $secretText=[IO.File]::ReadAllText((SecretPath $r.BlobId))
    Assert (-not ((ConvertTo-Json $receipt -Depth 14 -Compress).Contains($secretText.Substring(0,[Math]::Min(40,$secretText.Length))))) 'le recu porte le secret protege'
} -Reset
Case 'The product never deletes the operator source file' {
    $path=New-BlobFile
    $before=[IO.File]::ReadAllBytes($path)
    $r=Import-Ok -BlobPath $path
    Equal $r.SourceRetained $true "l'import ne declare pas que la source est conservee"
    Assert ([IO.File]::Exists($path)) 'l import a detruit le fichier remis par l operateur'
    $after=[IO.File]::ReadAllBytes($path)
    Equal $after.Length $before.Length 'l import a modifie la taille du fichier remis'
    Assert ($r.Message.Contains('Supprimer la source')) "l'import ne renvoie plus a la procedure de suppression de la source"
} -Reset
Case 'The result handed back to the operator never carries the secret material' {
    $r=Import-Ok
    $text=$r|ConvertTo-Json -Depth 12 -Compress
    Assert (-not $text.Contains($canary)) 'le materiel clair remonte jusqu au resultat rendu'
    Assert (-not ($text -match '(?i)protecteddata|dpapi')) 'un detail de protection du secret remonte jusqu au resultat rendu'
} -Reset
Case 'When the protection fails, neither the receipt nor the secret is persisted' {
    $script:protectFails=$true
    RejectWith {Import-Blob} 'DPAPI indisponible'
    Equal @(FilesUnder $script:store).Count 0 'un import dont la protection a echoue a laisse des traces au magasin'
} -Reset

# ---------- F. Le recu d'import et le plan scelle ----------
Case 'The import receipt carries exactly the closed durable schema' {
    $r=Import-Ok
    $receipt=Read-JsonFile (ReceiptPath $r.BlobId)
    $names=@($receipt.PSObject.Properties.Name|Sort-Object)
    $expected=@('BootUtc','Id','Mode','NativeCode','OperationId','Plan','Schema','State','Utc')
    Equal (@(Compare-Object -ReferenceObject $expected -DifferenceObject $names).Count) 0 ('le recu d import ne porte plus exactement le schema ferme : '+($names -join ','))
} -Reset
Case 'The import receipt records a request that has not been applied yet' {
    $r=Import-Ok
    $receipt=Read-JsonFile (ReceiptPath $r.BlobId)
    Equal $receipt.Schema 1 'le schema du recu'
    Equal $receipt.Mode 'OfflineJoin' 'le mode du recu'
    Equal $receipt.State 'Imported' "l'etat sorti de l'import"
    Equal $receipt.Id $r.BlobId "l'identifiant du recu n'est pas l'empreinte du materiel"
    Equal ([string]$receipt.OperationId) '' "l'import ne doit pas encore ouvrir d'operation"
    Assert ($null -eq $receipt.NativeCode) 'un code natif est enregistre des l import'
    $raw=[IO.File]::ReadAllText((ReceiptPath $r.BlobId))
    Assert ($raw -match ('"BootUtc"\s*:\s*"'+[regex]::Escape($script:local.BootUtc)+'"')) "le demarrage enregistre n'est pas l'instant ISO du poste au moment de l import"
    Assert ($raw -match '"Utc"\s*:\s*"\d{4}-\d{2}-\d{2}T[^"]*Z"') "l'horodatage du recu n'est pas un instant ISO UTC"
    Assert ($raw -match '"OperationId"\s*:\s*""') "l'import persiste une operation alors qu'il ne doit pas en ouvrir"
} -Reset
Case 'The sealed plan of the receipt verifies independently of the product' {
    $r=Import-Ok
    $receipt=Read-JsonFile (ReceiptPath $r.BlobId)
    Equal $receipt.Plan.Integrity (Get-PestoStableHash (ConvertTo-PestoCanonicalValue (Canonical-Plan $receipt.Plan))) "l'empreinte du plan scelle ne se recalcule pas a partir du plan relu"
} -Reset
Case 'The plan is an offline join plan for the configured domain and the planned organisational unit' {
    $r=Import-Ok
    $plan=$r.Plan
    Equal $plan.Action 'OfflineJoin' "l'action du plan n'est pas la jonction hors connexion"
    Equal $plan.Purpose 'PestoPreparedPlan' 'le plan na plus la finalite dun plan prepare'
    Equal $plan.Domain $script:DOMAINE "le plan ne vise pas le domaine configure"
    Equal $plan.TargetOU $targetOuValue "le plan ne vise pas l'unite organisationnelle remise a l'import"
    Equal $plan.BlobSHA256 $r.BlobId "le plan ne porte pas l'empreinte du blob"
    Equal $plan.ConfigStamp (Get-PestoConfigurationSignature $script:CFG) "le plan ne porte pas l'empreinte de la configuration"
} -Reset
Case 'The plan identity is the local machine that asked for the import' {
    $r=Import-Ok
    $plan=$r.Plan
    Equal $plan.Computer $script:local.Computer "le plan ne nomme pas le poste qui a demande l'import"
    Equal $plan.NewName $script:local.Computer "le plan renomme le poste a l'import, ce que la jonction hors connexion ne fait pas"
    Equal $plan.MachineId $script:local.MachineId "le plan ne porte pas l'identite de machine du poste"
} -Reset
Case 'The three store paths of an imported blob are the receipt, the secret and the transient file' {
    $r=Import-Ok
    $paths=Get-PestoOfflinePaths $r.BlobId
    Equal $paths.State (ReceiptPath $r.BlobId) 'le chemin du recu'
    Equal $paths.Secret (SecretPath $r.BlobId) 'le chemin du secret'
    Equal ([IO.Path]::GetExtension($paths.Plain)) '.tmp' 'le fichier transitoir de l appel natif na plus une extension temporaire'
    Assert ($paths.Plain.EndsWith($r.BlobId+'.odj.tmp')) 'le fichier transitoire nest pas nomme d apres l identifiant du blob'
} -Reset

# ---------- G. L'identifiant du blob : une empreinte, rien d'autre ----------
# Sans cette garde, un identifiant remis par l'operateur remonterait hors du magasin (../../) ou echapperait au
# controle de rejeu en changeant de casse.
$idNeedle='Identifiant ODJ invalide.'
$validId=(Sha256Of ([Text.Encoding]::UTF8.GetBytes('identifiant')))
Case 'A blob identifier written in upper case is refused' {
    RejectWith {Get-PestoOfflinePaths $validId.ToUpperInvariant()} $idNeedle
} -Reset
Case 'A blob identifier one character short is refused' {
    RejectWith {Get-PestoOfflinePaths $validId.Substring(0,63)} $idNeedle
} -Reset
Case 'A blob identifier one character long is refused' {
    RejectWith {Get-PestoOfflinePaths ($validId+'a')} $idNeedle
} -Reset
Case 'A blob identifier carrying a non hexadecimal letter is refused' {
    RejectWith {Get-PestoOfflinePaths (($validId.Substring(0,63))+'z')} $idNeedle
} -Reset
Case 'An empty blob identifier is refused' {
    RejectWith {Get-PestoOfflinePaths ''} $idNeedle
} -Reset
Case 'A blob identifier that walks out of the store is refused' {
    RejectWith {Get-PestoOfflinePaths '../../../../etc/passwd'} $idNeedle
} -Reset
Case 'A blob identifier naming another store file is refused' {
    RejectWith {Get-PestoOfflinePaths ($validId+'.protected')} $idNeedle
} -Reset
Case 'A well formed blob identifier yields the three paths of the store' {
    $paths=Get-PestoOfflinePaths $validId
    Assert ($paths.State.StartsWith($script:store)) 'le recu ne se lit plus dans le magasin configure'
    Equal ([IO.Path]::GetFileName($paths.State)) ($validId+'.json') 'le recu ne porte plus l empreinte en nom de fichier'
    Equal ([IO.Path]::GetFileName($paths.Secret)) ($validId+'.protected') 'le secret ne porte plus l empreinte en nom de fichier'
} -Reset

# ---------- H. La relecture du recu : chaque garde jouee seule ----------
$recordNeedle='Recu ODJ invalide.'
$planNeedle='Identite ou integrite du plan ODJ invalide.'
$targetNeedle='Cible ODJ invalide.'
Case 'An untouched import receipt reads back through the closed record reader' {
    $id=(Import-Ok).BlobId
    $r=Read-PestoOfflineRecord $id
    Equal $r.State 'Imported' 'la relecture d un recu intact ne rend pas l etat d import'
    Equal $r.Plan.BlobSHA256 $id 'la relecture d un recu intact ne rend pas l empreinte du blob'
} -Reset
Case 'A receipt declaring another schema is refused' {
    $id=(Import-Ok).BlobId;Tamper-Receipt $id {param($d)$d.Schema=2}
    RejectWith {Read-PestoOfflineRecord $id} $recordNeedle
} -Reset
Case 'A receipt declaring another mode than offline join is refused' {
    $id=(Import-Ok).BlobId;Tamper-Receipt $id {param($d)$d.Mode='OnlineJoin'}
    RejectWith {Read-PestoOfflineRecord $id} $recordNeedle
} -Reset
Case 'A receipt naming another blob than the one asked for is refused' {
    $id=(Import-Ok).BlobId;Tamper-Receipt $id {param($d)$d.Id=(New-Guid).Guid.Replace('-','').ToLowerInvariant()}
    RejectWith {Read-PestoOfflineRecord $id} $recordNeedle
} -Reset
Case 'A receipt carrying a state outside the closed set is refused' {
    $id=(Import-Ok).BlobId;Tamper-Receipt $id {param($d)$d.State='Applied'}
    RejectWith {Read-PestoOfflineRecord $id} $recordNeedle
} -Reset
Case 'A receipt whose plan was sealed for another blob fingerprint is refused' {
    $id=(Import-Ok).BlobId;Tamper-Receipt $id {param($d)$d.Plan.BlobSHA256=(New-Guid).Guid.Replace('-','').ToLowerInvariant()}
    RejectWith {Read-PestoOfflineRecord $id} $recordNeedle
} -Reset
Case 'A receipt carrying an extra field is refused' {
    $id=(Import-Ok).BlobId;Tamper-Receipt $id {param($d)$d|Add-Member -NotePropertyName Extra -NotePropertyValue 'x' -Force}
    RejectWith {Read-PestoOfflineRecord $id} 'Champ non autorisé'
} -Reset
Case 'A receipt missing one of its mandatory fields is refused' {
    $id=(Import-Ok).BlobId;Tamper-Receipt $id {param($d)$d.PSObject.Properties.Remove('Utc')}
    RejectWith {Read-PestoOfflineRecord $id} 'Champ obligatoire absent'
} -Reset
Case 'A plan carrying an extra field is refused' {
    $id=(Import-Ok).BlobId;Tamper-Receipt $id {param($d)$d.Plan|Add-Member -NotePropertyName Extra -NotePropertyValue 'x' -Force}
    RejectWith {Read-PestoOfflineRecord $id} 'Champ non autorisé'
} -Reset
Case 'A plan missing one of its mandatory fields is refused' {
    $id=(Import-Ok).BlobId;Tamper-Receipt $id {param($d)$d.Plan.PSObject.Properties.Remove('Purpose')}
    RejectWith {Read-PestoOfflineRecord $id} 'Champ obligatoire absent'
} -Reset
Case 'A plan whose seal was altered is refused' {
    $id=(Import-Ok).BlobId;Tamper-Receipt $id {param($d)$d.Plan.Integrity=('0'*64)}
    RejectWith {Read-PestoOfflineRecord $id} $planNeedle
} -Reset
Case 'A plan sealed for another action than offline join is refused even resealed' {
    $id=(Import-Ok).BlobId;Tamper-Receipt $id {param($d)$d.Plan.Action='Join'} -Reseal
    RejectWith {Read-PestoOfflineRecord $id} $planNeedle
} -Reset
Case 'A plan sealed for another purpose than a prepared plan is refused even resealed' {
    $id=(Import-Ok).BlobId;Tamper-Receipt $id {param($d)$d.Plan.Purpose='PestoAdHocPlan'} -Reseal
    RejectWith {Read-PestoOfflineRecord $id} $planNeedle
} -Reset
Case 'A plan sealed for another domain is refused even resealed' {
    $id=(Import-Ok).BlobId;Tamper-Receipt $id {param($d)$d.Plan.Domain='autre.local'} -Reseal
    RejectWith {Read-PestoOfflineRecord $id} $planNeedle
} -Reset
Case 'A plan sealed for another machine is refused even resealed' {
    $id=(Import-Ok).BlobId;Tamper-Receipt $id {param($d)$d.Plan.MachineId=(New-Guid).Guid} -Reseal
    RejectWith {Read-PestoOfflineRecord $id} $planNeedle
} -Reset
Case 'A plan naming an impossible computer name is refused' {
    # Le nom de rechange est pose aussi sur Nouveau_Nom : seule la clause de nom reste en defaut,
    # sinon la clause "pas de renommage" du meme throw masquerait la garde frappee.
    $id=(Import-Ok).BlobId;Tamper-Receipt $id {param($d)$d.Plan.Computer='PESTO/ODJ/109';$d.Plan.NewName='PESTO/ODJ/109'}
    RejectWith {Read-PestoOfflineRecord $id} $targetNeedle
} -Reset
Case 'A plan that renames the machine behind the offline join is refused' {
    $id=(Import-Ok).BlobId;Tamper-Receipt $id {param($d)$d.Plan.NewName='PESTO-ODJ-109X'}
    RejectWith {Read-PestoOfflineRecord $id} $targetNeedle
} -Reset
Case 'A plan naming a container instead of an organisational unit is refused' {
    $id=(Import-Ok).BlobId;Tamper-Receipt $id {param($d)$d.Plan.TargetOU='CN=Postes,DC=example,DC=local'}
    RejectWith {Read-PestoOfflineRecord $id} $targetNeedle
} -Reset
Case 'A plan declaring another schema is refused' {
    $id=(Import-Ok).BlobId;Tamper-Receipt $id {param($d)$d.Plan.Schema=2}
    RejectWith {Read-PestoOfflineRecord $id} $targetNeedle
} -Reset

# ---------- I. Ce que l'execution hors Windows ne peut pas montrer ----------
Case 'Both the clear material and the protected material are wiped when the import ends' {
    $fn=SealedFunction 'Import-PestoOfflineBlob'
    $tries=@(OfKind $fn 'TryStatementAst')
    Equal $tries.Count 1 "l'import n'a plus un seul bloc try protegeant le materiel"
    Assert ($null -ne $tries[0].Finally) "l'import n'a plus de bloc finally ou effacer le materiel"
    $clears=@(MemberInvokes $tries[0].Finally 'Clear')
    Equal $clears.Count 2 'le materiel clair et le materiel protege ne sont plus tous les deux effaces a la sortie'
    $wiped=@($clears|ForEach-Object{$_.Arguments[0].VariablePath.UserPath}|Sort-Object)
    Equal (@($wiped) -join ',') 'bytes,encrypted' 'ce ne sont plus le materiel clair et le materiel protege qui sont effaces'
} -Reset
Case 'The secret reaches disk only as the base64 of the protected material' {
    $fn=SealedFunction 'Import-PestoOfflineBlob'
    $b64=@(MemberInvokes $fn 'ToBase64String')
    Equal $b64.Count 1 'le secret remis au disque nest plus converti exactement une fois en base64'
    Equal @(VariableUses $b64[0] 'encrypted').Count 1 'ce nest plus le materiel protege qui est converti pour le disque'
    Equal @(VariableUses $b64[0] 'bytes').Count 0 'le materiel clair est converti pour le disque'
    $writes=@(CommandInvokes $fn 'Write-PestoAtomicText')
    Equal $writes.Count 1 "le secret n'est plus ecrit par une seule ecriture atomique"
    $extent=$writes[0].Extent
    $inside=@(AllNodes $fn|Where-Object{$_.Extent.StartOffset -ge $extent.StartOffset -and $_.Extent.EndOffset -le $extent.EndOffset})
    Equal @($inside|Where-Object{$_.GetType().Name -eq 'VariableExpressionAst' -and $_.VariablePath.UserPath -eq 'bytes'}).Count 0 'le materiel clair est remis a lecrture atomique du secret'
} -Reset
Case 'The material is protected before anything is persisted and the secret path is re-checked before it is written' {
    $fn=SealedFunction 'Import-PestoOfflineBlob'
    $protect=@(CommandInvokes $fn 'Protect-PestoOfflineBytes')
    $receipt=@(CommandInvokes $fn 'Write-PestoJoinReceipt')
    $secret=@(CommandInvokes $fn 'Write-PestoAtomicText')
    $plain=@(CommandInvokes $fn 'Assert-PestoPlainPath')
    Equal $protect.Count 1 'le materiel nest plus protege exactement une fois'
    Equal $receipt.Count 1 'le recu d import nest plus ecrit exactement une fois'
    Equal $secret.Count 1 'le secret nest plus ecrit exactement une fois'
    Assert ($protect[0].Extent.StartOffset -lt $receipt[0].Extent.StartOffset) 'le recu est ecrit avant que le materiel soit protege'
    Assert ($receipt[0].Extent.StartOffset -lt $secret[0].Extent.StartOffset) 'le secret est ecrit avant le recu : un recu sans secret serait relu'
    Assert ($plain.Count -ge 2) 'le chemin clair du secret nest plus re-verifie avant son ecriture'
    Assert ($plain[-1].Extent.StartOffset -lt $secret[0].Extent.StartOffset) 'le chemin du secret est ecrit sans relecture prealable du lien'
} -Reset
Case 'The blob is protected for the machine, not for the operator who imports it' {
    $fn=SealedFunction 'Protect-PestoOfflineBytes'
    Equal @(MemberInvokes $fn 'Protect').Count 1 'le secret nest plus protege par ProtectedData'
    Equal @(MemberReads $fn 'LocalMachine').Count 1 'le blob nest plus protege pour la machine'
    Equal @(MemberReads $fn 'CurrentUser').Count 0 'le blob est protege pour l operateur qui importe : un autre compte ne pourrait plus le relire apres la jonction'
} -Reset
}finally{
    $env:PESTO_READONLY_SESSION=''
    if([IO.Directory]::Exists($root)){[IO.Directory]::Delete($root,$true)}
}
$report=[pscustomobject]@{Schema=1;Suite='OfflineJoin109Blob';HostOS=[Environment]::OSVersion.ToString();PowerShell=$PSVersionTable.PSVersion.ToString();WindowsExecuted=$false;ADExecuted=$false;WPFExecuted=$false;GPOApplied=$false;RegistryWritten=$false;Scope='Import du blob secret joue par le point d entree public sous -Action OfflineImport, chaque garde jouee seule ; identifiant, plan scelle, receveur durable, ecriture atomique et relecture complete reels ; plateforme, paquet, socle, statut local du poste, ACL du magasin, DPAPI et magasins ProgramData doubles ; aucun appel reseau ni VM'}
if($ReportPath){[IO.File]::WriteAllText([IO.Path]::GetFullPath($ReportPath),($report|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))}
Write-Host "OfflineJoin109Blob: $script:passed passed, $script:failed failed. Each offline join blob import guard judged alone against the sealed engine; identifier, sealed plan, durable receipt and full reread real; DPAPI, ACL, local status and ProgramData stores mocked; no VM."
if($script:failed){exit 1}
