#requires -Version 5.1
[CmdletBinding()]
param([string]$ReportPath='')
$ErrorActionPreference='Stop';Set-StrictMode -Off
# Point 114 : le point d'entree public exporte par Pesto.Engine.psd1, Invoke-PestoExtensionCommand, est la
# seule forme sous laquelle l'operateur joue l'extension attributs (EXTENSIONS_120.md). Cette suite le joue
# tel quel, sans appeler directement New-PestoAttributePlan ni Invoke-PestoAttributeMutation : c'est donc le
# verrou du mutex, la resolution du cfg par defaut, le garde-fou « plan ou changements directs », l'exigence
# PlanPath + IdempotencyKey sans export simultane, l'aller-retour du plan sur disque (Export-PestoPortablePlan
# puis Read-PestoAutomationJson et Assert-PestoAttributePlan) et le registre idempotent reel
# (Invoke-PestoIdempotentExecution) qui sont juges ici. Les doubles locaux restent a la frontiere Windows/AD :
# plateforme, integrity du paquet, socle commun, import du module ActiveDirectory, decouverte du controleur,
# Get-ADComputer / Get-ADObject / Set-ADObject, ACL des recus, registre de la machine et magasins ProgramData.
# Aucun appel reseau, aucune VM, aucun cfg.json operationnel lu : la configuration vient du modele neutre
# DEV/tools/cfg.modele-complet.json recopie dans un dossier temporaire.
$dev=Split-Path $PSScriptRoot -Parent
$runtime=Join-Path $dev 'wad'
. (Join-Path $runtime 'Pesto.Engine.Runtime.ps1')
$script:passed=0;$script:failed=0
function Assert($v,$why='Assertion failed'){if(-not $v){throw $why}}
function Equal($actual,$expected,[string]$why=''){if($actual -cne $expected){throw ('attendu ['+$expected+'] obtenu ['+[string]$actual+'] '+$why)}}
function Case($name,[scriptblock]$body,[switch]$Reset){try{&$body;$script:passed++}catch{$script:failed++;Write-Host ('FAIL '+$name+': '+$_)}finally{if($Reset){Reset-Entry}}}
function RejectWith([scriptblock]$body,[string]$Needle){$caught='<aucun refus>';try{&$body|Out-Null}catch{$caught=[string]$_.Exception.Message};Assert ($caught.Contains($Needle)) ('refus attendu : '+$Needle+' ; obtenu : '+$caught)}
function Read-JsonFile([string]$Path){Assert ([IO.File]::Exists($Path)) ('fichier absent : '+$Path);return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json)}
function ReceiptFiles([string]$Dir){if(-not[IO.Directory]::Exists($Dir)){return @()};return @(Get-ChildItem -LiteralPath $Dir -File|Sort-Object Name)}
$root=Join-Path $PSScriptRoot ('pesto-entry114-'+[Guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($root)
$machine='11111111-1111-1111-1111-111111111111';$guid='22222222-2222-2222-2222-222222222222'
$refGuid='33333333-3333-3333-3333-333333333333';$refDn='CN=Admin Reference,OU=Postes,OU=Organisme,DC=example,DC=local'
$canary='CANARY-SECRET-114-'+[Guid]::NewGuid().ToString('N')
$credential=[pscredential]::new('EXAMPLE\operateur',(ConvertTo-SecureString $canary -AsPlainText -Force))
$script:cfgTemplate=Get-Content (Join-Path $dev 'tools/cfg.modele-complet.json') -Raw|ConvertFrom-Json
$script:cfgTemplate.POLICY|Add-Member -NotePropertyName UnattendedOperationsEnabled -NotePropertyValue $true -Force
function Write-EntryCfg {[CmdletBinding()]param([scriptblock]$Edit=$null)
    $cfg=$script:cfgTemplate|ConvertTo-Json -Depth 15|ConvertFrom-Json
    if($Edit){&$Edit $cfg}
    $path=Join-Path $root ('cfg-'+[Guid]::NewGuid().ToString('N')+'.json')
    [IO.File]::WriteAllText($path,($cfg|ConvertTo-Json -Depth 15),[Text.UTF8Encoding]::new($false))
    return $path}
# Frontiere Windows/AD : ces doubles ne sont la que pour rendre le point d'entree jouable hors Windows.
function Assert-PestoAutomationPlatform {}
function Test-PestoPackage {param($Root);$script:packageChecks++;$true}
function Initialize-PestoCommon {param([string]$Root='',[switch]$IncludeWpf);$script:commonInits++}
function Import-PestoADModule {param($ADModulePath);$script:adImports++}
function Get-DomainController {param($Domain);$script:dcReads++;return $script:dcName}
function Get-ADDomain {param($Server,$Credential);return [pscustomobject]@{DNSRoot=$script:dnsRoot}}
function Get-PestoJoinLocalStatus {return [pscustomobject]@{Computer='PESTO-ENTRY-114';PartOfDomain=$script:inDomain;Domain='example.local';PendingRename=$false;Admin=$true;DomainRole=0;MachineId=$script:machine;BootUtc='2026-10-18T10:00:00Z'}}
function Get-PestoAutomationMachineId {return $script:machine}
function Get-PestoInterventionRoot {return $script:ledger}
function Get-PestoAutomationStore {return $script:store}
function Get-PestoOperatorSid {return 'S-1-5-21-222'}
function Get-PestoCampaignPolicy {return $script:campaignPolicy}
function Assert-PestoStoredMutationReady {param($Plan)}
function Get-ADComputer {param($Identity,$Properties,$ErrorAction,$Server,$Credential);$script:adReads++;$script:lastAdParams=@{Identity=$Identity;Server=$Server;Credential=$Credential};return $script:pc}
function Get-ADObject {param($Identity,$Properties,$ErrorAction,$Server,$Credential);$script:adReferenceReads++;return $script:adObject}
function Set-ADObject {param($Identity,$Replace,$Clear,$ErrorAction,$Server,$Credential)
    $script:adWrites++;$script:lastWrite=@{Identity=$Identity;Replace=$Replace;Clear=$Clear;Server=$Server;Credential=$Credential}
    Assert ($script:ActiveIntervention.Attributes -eq 'Requested') 'ecriture AD lancee avant que l intention soit enregistree'
    if($script:nativeFail){throw 'fixture interruption'}
    foreach($k in $Replace.Keys){$script:pc.$k=$Replace[$k]};foreach($k in $Clear){$script:pc.$k=''}}
function Write-PestoJoinReceipt {param($Path,$Receipt)
    $script:receiptWrites++;$script:receiptPaths+=@($Path)
    if($script:failWriteAt -gt 0 -and $script:failWriteAt -eq $script:receiptWrites){throw 'fixture disk failure'}
    if($script:failPathMatch -and ($Path -like $script:failPathMatch)){throw 'fixture disk failure'}
    Write-PestoAtomicText $Path ($Receipt|ConvertTo-Json -Depth 12)}
function Reset-Entry {
    $script:install=Join-Path $root ('pack-'+[Guid]::NewGuid().ToString('N'))
    $script:wad=Join-Path $script:install 'wad'
    foreach($dir in @($script:wad,(Join-Path $script:install 'ledger'),(Join-Path $script:install 'store'),(Join-Path $script:install 'plans'))){[void][IO.Directory]::CreateDirectory($dir)}
    [IO.File]::WriteAllBytes((Join-Path $script:install 'Pesto.exe'),[Text.Encoding]::UTF8.GetBytes('fixture-engine-marker'))
    $script:ledger=Join-Path $script:install 'ledger';$script:store=Join-Path $script:install 'store';$script:plans=Join-Path $script:install 'plans'
    $script:cfgFile=Write-EntryCfg
    $script:adWrites=0;$script:adReads=0;$script:adReferenceReads=0;$script:receiptWrites=0;$script:receiptPaths=@();$script:failWriteAt=0;$script:failPathMatch=''
    $script:packageChecks=0;$script:commonInits=0;$script:adImports=0;$script:dcReads=0
    $script:nativeFail=$false;$script:machine=$machine;$script:inDomain=$true;$script:dcName='dc.example.local';$script:dnsRoot='example.local'
    $script:campaignPolicy=$null;$script:lastAdParams=$null;$script:lastWrite=$null
    $script:pc=[pscustomobject]@{Name='P123456PA765001';ObjectGUID=$guid;DistinguishedName='CN=P123456PA765001,OU=Postes,OU=Organisme,DC=example,DC=local';description='old';location='old place';managedBy='';userAccountControl=4096}
    $script:adObject=[pscustomobject]@{ObjectGUID=$refGuid;DistinguishedName=$refDn}
    $script:ActiveIntervention=$null
    $env:PESTO_READONLY_SESSION=''
}
function Invoke-Entry {[CmdletBinding()]param([hashtable]$Params,$CredentialValue=$credential,$ConfigPath,$RuntimeRoot,[switch]$NoConfig)
    $call=@{Action='Attributes';Credential=$CredentialValue}
    $call['RuntimeRoot']=if($RuntimeRoot){$RuntimeRoot}else{$script:wad}
    if(-not $NoConfig){$call['ConfigPath']=if($ConfigPath){$ConfigPath}else{$script:cfgFile}}
    foreach($k in $Params.Keys){$call[$k]=$Params[$k]}
    return (Invoke-PestoExtensionCommand @call)}
function New-PlanOnDisk {[CmdletBinding()]param($Attributes=[pscustomobject]@{description='new'},[scriptblock]$Edit=$null)
    $path=Join-Path $script:plans ('plan-'+[Guid]::NewGuid().ToString('N')+'.json')
    $r=Invoke-Entry -Params @{ObjectGuid=([Guid]$guid);Attributes=$Attributes;OutPlanPath=$path}
    Assert ($r.ExitCode -eq 0 -and $r.State -ceq 'Prepared') ('preparation du plan refusee : '+$r.Message)
    if($Edit){$doc=Read-JsonFile $path;&$Edit $doc;[IO.File]::WriteAllText($path,($doc|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))}
    return $path}
function Resign-EntryPlan([object]$Plan){
    # PowerShell 7 relit les dates JSON en DateTime ; la garde du plan les ramene en UTC 'o' avant de hasher.
    foreach($date in @('CreatedUtc','ExpiresUtc')){if($Plan.$date -is [DateTime]){$Plan.$date=$Plan.$date.ToUniversalTime().ToString('o')}}
    $copy=[ordered]@{};foreach($p in $Plan.PSObject.Properties){if($p.Name -ne 'Integrity'){$copy[$p.Name]=$p.Value}}
    $Plan.Integrity=Get-PestoStableHash (ConvertTo-PestoCanonicalValue $copy);return $Plan}
try{
 Reset-Entry
 Case 'Preview writes the plan file the operator is told to hand over' {
    $path=Join-Path $script:plans 'handover.json'
    $r=Invoke-Entry -Params @{ObjectGuid=([Guid]$guid);Attributes=([pscustomobject]@{description='new';location=''});OutPlanPath=$path}
    Equal $r.ExitCode 0 $r.Message;Equal $r.State 'Prepared';Equal $r.Mode 'Attributes'
    Assert ([IO.File]::Exists($path)) 'le plan exporte est absent du disque'
    $disk=Read-JsonFile $path;Assert-PestoAttributePlan $disk
    Equal $script:adWrites 0;Equal (@(ReceiptFiles $script:ledger).Count) 0;Equal (@(ReceiptFiles $script:store).Count) 0
    } -Reset
 Case 'Preview without -OutPlanPath leaves nothing on disk' {
    $before=@(Get-ChildItem -LiteralPath $root -Recurse -File|ForEach-Object{$_.FullName})
    $r=Invoke-Entry -Params @{ObjectGuid=([Guid]$guid);Attributes=([pscustomobject]@{description='new'})}
    Equal $r.ExitCode 0 $r.Message;Equal $r.State 'Prepared'
    $after=@(Get-ChildItem -LiteralPath $root -Recurse -File|ForEach-Object{$_.FullName})
    Equal (@(Compare-Object -ReferenceObject $before -DifferenceObject $after).Count) 0 'la preparation sans export a ecrit sur le disque'
    } -Reset
 Case 'The exported plan carries the exact diff and the real configuration stamp' {
    $path=New-PlanOnDisk -Attributes ([pscustomobject]@{description='new';location='';managedBy=$refDn})
    $disk=Read-JsonFile $path
    Equal $disk.Action 'Attributes';Equal $disk.Purpose 'PestoPreparedPlan'
    Equal $disk.MachineId $machine;Equal $disk.ConfigStamp (Get-PestoConfigurationSignature (Read-JsonFile $script:cfgFile))
    Equal $disk.Domain 'EXAMPLE.LOCAL';Equal $disk.Computer 'P123456PA765001'
    Equal (@($disk.Changes).Count) 3
    Equal ([string]$disk.Changes[0].Before) 'old';Equal ([string]$disk.Changes[0].After) 'new'
    Equal ([string]$disk.Changes[2].Attribute) 'managedBy';Equal ([string]$disk.Changes[2].ReferenceGuid) $refGuid
    Equal $script:adReferenceReads 1 'la reference managedBy est resolue plus d une fois'
    } -Reset
 Case 'Directory reads carry the discovered domain controller and the in-memory credential' {
    New-PlanOnDisk|Out-Null
    Assert ($script:lastAdParams.Server -ceq 'dc.example.local') ('serveur AD transmis : '+[string]$script:lastAdParams.Server)
    Assert ($script:lastAdParams.Credential -is [pscredential]) 'aucun PSCredential transmis aux cmdlets AD'
    Equal $script:dcReads 1;Equal $script:adImports 1
    } -Reset
 Case 'Execution from the plan file writes once and confirms the receipt' {
    $path=New-PlanOnDisk
    $r=Invoke-Entry -Params @{PlanPath=$path;IdempotencyKey='PARIS-2026/attributs-01';Execute=$true}
    Equal $r.ExitCode 0 $r.Message;Equal $r.State 'Verified';Equal $r.Replayed $false
    Equal $script:adWrites 1;Equal ([string]$script:pc.description) 'new'
    Equal ([string]$script:lastWrite.Replace['description']) 'new'
    $ledger=@(ReceiptFiles $script:ledger);Equal $ledger.Count 1
    $receipt=Read-JsonFile $ledger[0].FullName
    Equal $receipt.OperationId ([Guid]$r.OperationId).ToString('N');Equal $receipt.Attributes 'Confirmed';Equal $receipt.ResultCode 30
    $store=@(ReceiptFiles $script:store);Equal $store.Count 1
    $record=Read-JsonFile $store[0].FullName;Equal $record.Status 'Completed';Equal $record.MachineId $machine
    } -Reset
 Case 'Replaying the same idempotency key never writes AD twice' {
    $path=New-PlanOnDisk
    $first=Invoke-Entry -Params @{PlanPath=$path;IdempotencyKey='PARIS-2026/replay';Execute=$true}
    $again=Invoke-Entry -Params @{PlanPath=$path;IdempotencyKey='PARIS-2026/replay';Execute=$true}
    Equal $first.ExitCode 0 $first.Message;Equal $again.ExitCode 0 $again.Message
    Equal $again.State 'Verified';Equal $again.Replayed $true;Equal $again.OperationId $first.OperationId
    Equal $script:adWrites 1 'la meme cle a declenche une seconde ecriture AD'
    } -Reset
 Case 'The same key with another plan is refused and never replayed' {
    $first=New-PlanOnDisk -Attributes ([pscustomobject]@{description='premiere valeur'})
    $other=New-PlanOnDisk -Attributes ([pscustomobject]@{description='autre valeur'})
    $a=Invoke-Entry -Params @{PlanPath=$first;IdempotencyKey='PARIS-2026/engagement';Execute=$true}
    Equal $a.ExitCode 0 $a.Message
    RejectWith -body {Invoke-Entry -Params @{PlanPath=$other;IdempotencyKey='PARIS-2026/engagement';Execute=$true}} -Needle 'Clé déjà utilisée pour une autre demande'
    Equal $script:adWrites 1 'le second plan a quand meme ecrit AD'
    } -Reset
 Case 'A record taken over by another operator machine is not replayed' {
    $path=New-PlanOnDisk
    $a=Invoke-Entry -Params @{PlanPath=$path;IdempotencyKey='PARIS-2026/machine';Execute=$true}
    Equal $a.ExitCode 0 $a.Message
    $store=@(ReceiptFiles $script:store);Equal $store.Count 1
    $doc=Read-JsonFile $store[0].FullName;$doc.MachineId='99999999-9999-9999-9999-999999999999'
    [IO.File]::WriteAllText($store[0].FullName,($doc|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
    RejectWith -body {Invoke-Entry -Params @{PlanPath=$path;IdempotencyKey='PARIS-2026/machine';Execute=$true}} -Needle 'Clé déjà utilisée pour une autre demande'
    Equal $script:adWrites 1 'le registre d une autre machine a ete rejoue comme une execution'
    } -Reset
 Case 'A refused execution stays recorded under its key' {
    $path=New-PlanOnDisk
    $script:pc.Name='P123456PA765002'
    $first=Invoke-Entry -Params @{PlanPath=$path;IdempotencyKey='PARIS-2026/refus';Execute=$true}
    Equal $first.ExitCode 96;Equal $first.State 'NotStarted';Equal $script:adWrites 0
    $again=Invoke-Entry -Params @{PlanPath=$path;IdempotencyKey='PARIS-2026/refus';Execute=$true}
    Equal $again.ExitCode 96;Equal $again.Replayed $true;Equal $script:adWrites 0 'un refus a ete rejoue comme une execution'
    } -Reset
 Case 'An interrupted write is reported uncertain and never replayed' {
    $path=New-PlanOnDisk
    $script:nativeFail=$true
    $first=Invoke-Entry -Params @{PlanPath=$path;IdempotencyKey='PARIS-2026/coupure';Execute=$true}
    Equal $first.ExitCode 97;Equal $first.State 'Uncertain';Equal $first.MutationStarted $true;Equal $script:adWrites 1
    $script:nativeFail=$false
    $again=Invoke-Entry -Params @{PlanPath=$path;IdempotencyKey='PARIS-2026/coupure';Execute=$true}
    Equal $again.ExitCode 97;Equal $script:adWrites 1 'une ecriture incertaine a ete rejouee'
    } -Reset
 Case 'The idempotency key is durably recorded before the AD write' {
    $path=New-PlanOnDisk
    $script:failPathMatch=$script:store+'*'
    RejectWith -body {Invoke-Entry -Params @{PlanPath=$path;IdempotencyKey='PARIS-2026/disque';Execute=$true}} -Needle 'fixture disk failure'
    Equal $script:adWrites 0 'AD ecrit avant que la cle ne soit enregistree'
    Equal (@(ReceiptFiles $script:store).Count) 0
    } -Reset
 Case 'The intervention receipt is persisted before the AD write' {
    $path=New-PlanOnDisk
    $script:failPathMatch=$script:ledger+'*'
    $r=Invoke-Entry -Params @{PlanPath=$path;IdempotencyKey='PARIS-2026/recu';Execute=$true}
    Equal $r.ExitCode 96;Equal $r.State 'NotStarted';Equal $script:adWrites 0 'AD ecrit avant que le recu ne soit enregistre'
    } -Reset
 Case 'Execute without a plan file is refused' {
    RejectWith -body {Invoke-Entry -Params @{ObjectGuid=([Guid]$guid);Attributes=([pscustomobject]@{description='new'});IdempotencyKey='PARIS-2026/sans-plan';Execute=$true}} -Needle 'Execution attributs : PlanPath et IdempotencyKey requis, sans export simultane.'
    Equal $script:adWrites 0
    } -Reset
 Case 'Execute cannot export a plan at the same time' {
    $path=New-PlanOnDisk
    RejectWith -body {Invoke-Entry -Params @{PlanPath=$path;OutPlanPath=(Join-Path $script:plans 'sortie.json');IdempotencyKey='PARIS-2026/export';Execute=$true}} -Needle 'Execution attributs : PlanPath et IdempotencyKey requis, sans export simultane.'
    Assert (-not [IO.File]::Exists((Join-Path $script:plans 'sortie.json'))) 'un plan a ete exporte pendant l execution'
    Equal $script:adWrites 0
    } -Reset
 Case 'Execute without an idempotency key is refused' {
    $path=New-PlanOnDisk
    RejectWith -body {Invoke-Entry -Params @{PlanPath=$path;Execute=$true}} -Needle 'Execution attributs : PlanPath et IdempotencyKey requis, sans export simultane.'
    Equal $script:adWrites 0;Equal (@(ReceiptFiles $script:store).Count) 0
    } -Reset
 Case 'A plan file and direct changes cannot be combined' {
    $path=New-PlanOnDisk
    RejectWith -body {Invoke-Entry -Params @{PlanPath=$path;ObjectGuid=([Guid]$guid);Execute=$true;IdempotencyKey='PARIS-2026/melange'}} -Needle 'Ne pas combiner plan et changements directs.'
    Equal $script:adWrites 0
    } -Reset
 Case 'A key outside the ASCII grammar is refused before any write' {
    $path=New-PlanOnDisk
    RejectWith -body {Invoke-Entry -Params @{PlanPath=$path;IdempotencyKey=('mauv#'+$guid);Execute=$true}} -Needle 'Clé idempotente : 1 à 128 caractères ASCII'
    Equal $script:adWrites 0
    } -Reset
 Case 'Relative plan paths are refused before any read' {
    RejectWith -body {Invoke-Entry -Params @{PlanPath='plan.json';IdempotencyKey='PARIS-2026/relatif';Execute=$true}} -Needle 'Un chemin absolu est requis.'
    RejectWith -body {Invoke-Entry -Params @{ObjectGuid=([Guid]$guid);Attributes=([pscustomobject]@{description='new'});OutPlanPath='plan.json'}} -Needle 'Chemin de plan absolu requis.'
    Equal $script:adWrites 0
    } -Reset
 Case 'DateTime plan dates are normalized before validation' {
    $path=New-PlanOnDisk
    $doc=Read-JsonFile $path
    $seal=$doc.Integrity
    # PS 5.1 garde les chaines JSON, PS 7 les convertit : presenter la meme donnee DateTime aux deux.
    foreach($date in @('CreatedUtc','ExpiresUtc')){
        $doc.$date=if($doc.$date -is [DateTime]){$doc.$date.ToUniversalTime()}else{[DateTimeOffset]::Parse($doc.$date,[Globalization.CultureInfo]::InvariantCulture).UtcDateTime}
        Assert ($doc.$date -is [DateTime]) 'la fixture doit presenter un instant DateTime'
    }
    Assert-PestoAttributePlan $doc
    foreach($date in @('CreatedUtc','ExpiresUtc')){Assert ($doc.$date -is [string]) 'le validateur doit normaliser l instant avant de verifier le sceau'}
    Equal $doc.Integrity $seal 'la normalisation ne doit pas refaire le sceau'
    Equal $script:adWrites 0
    } -Reset
 Case 'A plan file rewritten by an orchestrator still executes' {
    $path=New-PlanOnDisk
    $doc=Read-JsonFile $path
    [IO.File]::WriteAllText($path,($doc|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
    $r=Invoke-Entry -Params @{PlanPath=$path;IdempotencyKey='PARIS-2026/reecrit';Execute=$true}
    Equal $r.ExitCode 0 $r.Message;Equal $script:adWrites 1
    } -Reset
 Case 'A plan file tampered on disk is refused' {
    $path=New-PlanOnDisk -Edit{$args[0].Changes[0].After='altere'}
    RejectWith -body {Invoke-Entry -Params @{PlanPath=$path;IdempotencyKey='PARIS-2026/altere';Execute=$true}} -Needle 'Plan attributs invalide.'
    Equal $script:adWrites 0
    } -Reset
 Case 'A plan file re-signed for another operator machine is refused' {
    $path=New-PlanOnDisk -Edit{param($d) $d.MachineId='99999999-9999-9999-9999-999999999999';[void](Resign-EntryPlan $d)}
    RejectWith -body {Invoke-Entry -Params @{PlanPath=$path;IdempotencyKey='PARIS-2026/autre-machine';Execute=$true}} -Needle 'Plan attributs expire ou contexte modifie.'
    Equal $script:adWrites 0
    } -Reset
 Case 'A plan file beyond the read limit is refused' {
    $path=New-PlanOnDisk
    $padding=(' '*(70000-[IO.File]::ReadAllBytes($path).Length))
    [IO.File]::AppendAllText($path,$padding,[Text.UTF8Encoding]::new($false))
    RejectWith -body {Invoke-Entry -Params @{PlanPath=$path;IdempotencyKey='PARIS-2026/gonfle';Execute=$true}} -Needle 'Document absent ou trop volumineux.'
    Equal $script:adWrites 0
    } -Reset
 Case 'The same export path is never silently overwritten' {
    $path=New-PlanOnDisk -Attributes ([pscustomobject]@{description='premiere valeur'})
    $before=[IO.File]::ReadAllText($path)
    RejectWith -body {Invoke-Entry -Params @{ObjectGuid=([Guid]$guid);Attributes=([pscustomobject]@{description='seconde valeur'});OutPlanPath=$path}} -Needle 'already exists'
    Equal ([IO.File]::ReadAllText($path)) $before 'un plan deja remis a ete remplace'
    } -Reset
 Case 'AttributeObserve refuses -Execute and never writes AD' {
    $path=New-PlanOnDisk
    $run=Invoke-Entry -Params @{PlanPath=$path;IdempotencyKey='PARIS-2026/observer';Execute=$true}
    Equal $run.ExitCode 0 $run.Message
    RejectWith -body {Invoke-Entry -Params @{Action='AttributeObserve';OperationId=([Guid]$run.OperationId);Execute=$true}} -Needle 'Observation sans execution.'
    $before=[IO.File]::ReadAllBytes((@(ReceiptFiles $script:ledger)[0].FullName)).Length
    $o=Invoke-Entry -Params @{Action='AttributeObserve';OperationId=([Guid]$run.OperationId)}
    Equal $o.ExitCode 0;Equal $o.State 'Verified';Equal $o.TargetReadOnly $true;Equal $o.ReplayAllowed $false
    Equal $script:adWrites 1 'l observation a rejoue une ecriture AD'
    Assert ([IO.File]::ReadAllBytes((@(ReceiptFiles $script:ledger)[0].FullName)).Length -ge $before) 'le recu a disparu'
    } -Reset
 Case 'The configuration beside the runtime is used when -ConfigPath is omitted' {
    RejectWith -body {Invoke-Entry -NoConfig -Params @{ObjectGuid=([Guid]$guid);Attributes=([pscustomobject]@{description='new'})}} -Needle 'Cannot find path'
    Equal $script:adReads 0 'le point d entree a lu AD sans configuration resolue'
    Copy-Item -LiteralPath $script:cfgFile -Destination (Join-Path $script:wad 'cfg.json')
    $r=Invoke-Entry -NoConfig -Params @{ObjectGuid=([Guid]$guid);Attributes=([pscustomobject]@{description='new'})}
    Equal $r.ExitCode 0 $r.Message;Equal $r.State 'Prepared'
    } -Reset
 Case 'A missing configuration aborts before any directory read' {
    RejectWith -body {Invoke-Entry -ConfigPath (Join-Path $script:install 'absent.json') -Params @{ObjectGuid=([Guid]$guid);Attributes=([pscustomobject]@{description='new'})}} -Needle 'Cannot find path'
    Equal $script:adReads 0 'le point d entree a lu AD sans configuration'
    } -Reset
 Case 'A simulation flag in the configuration aborts the entry' {
    $cfg=Write-EntryCfg -Edit{$args[0].DEBUG.Simulation='true'}
    RejectWith -body {Invoke-Entry -ConfigPath $cfg -Params @{ObjectGuid=([Guid]$guid);Attributes=([pscustomobject]@{description='new'})}} -Needle 'DEBUG.Simulation doit être désactivé.'
    Equal $script:adReads 0
    } -Reset
 Case 'A domain controller of another domain aborts before any directory read' {
    $script:dnsRoot='other.local'
    RejectWith -body {Invoke-Entry -Params @{ObjectGuid=([Guid]$guid);Attributes=([pscustomobject]@{description='new'})}} -Needle 'Le contrôleur découvert ne correspond pas au domaine configuré.'
    Equal $script:adReads 0
    } -Reset
 Case 'Automation policy off aborts before any directory read' {
    $cfg=Write-EntryCfg -Edit{$args[0].POLICY.UnattendedOperationsEnabled=$false}
    RejectWith -body {Invoke-Entry -ConfigPath $cfg -Params @{ObjectGuid=([Guid]$guid);Attributes=([pscustomobject]@{description='new'});IdempotencyKey='PARIS-2026/politique';Execute=$true}} -Needle 'Automatisation des opérations désactivée'
    Equal $script:adReads 0;Equal $script:adWrites 0
    } -Reset
 Case 'A workstation outside the domain cannot execute' {
    $path=New-PlanOnDisk
    $script:inDomain=$false
    RejectWith -body {Invoke-Entry -Params @{PlanPath=$path;IdempotencyKey='PARIS-2026/hors-domaine';Execute=$true}} -Needle 'nécessitent un poste opérateur membre du domaine.'
    Equal $script:adWrites 0
    } -Reset
 Case 'A read-only session prepares a diff but cannot execute' {
    $path=New-PlanOnDisk
    $env:PESTO_READONLY_SESSION='1'
    try{
        $preview=Invoke-Entry -Params @{ObjectGuid=([Guid]$guid);Attributes=([pscustomobject]@{description='nouvelle valeur lecture'})}
        Equal $preview.ExitCode 0 $preview.Message;Equal $preview.State 'Prepared'
        RejectWith -body {Invoke-Entry -Params @{PlanPath=$path;IdempotencyKey='PARIS-2026/lecture';Execute=$true}} -Needle 'Automatisation des opérations désactivée, mode incident ou consultation actif.'
        Equal $script:adWrites 0
    }finally{$env:PESTO_READONLY_SESSION=''}
    } -Reset
 Case 'A credential handed over as text is refused' {
    RejectWith -body {Invoke-Entry -CredentialValue 'EXAMPLE\operateur' -Params @{ObjectGuid=([Guid]$guid);Attributes=([pscustomobject]@{description='new'})}} -Needle 'Credential doit être un PSCredential non vide fourni en mémoire.'
    Equal $script:adReads 0
    } -Reset
 Case 'An attribute outside the three allowed is refused through the entry' {
    RejectWith -body {Invoke-Entry -Params @{ObjectGuid=([Guid]$guid);Attributes=([pscustomobject]@{userAccountControl='0'})}} -Needle 'Champ non autorisé'
    Equal $script:adWrites 0
    } -Reset
 Case 'No secret reaches the plan file, the receipt or the idempotency record' {
    $path=New-PlanOnDisk -Attributes ([pscustomobject]@{description='valeur auditee'})
    $r=Invoke-Entry -Params @{PlanPath=$path;IdempotencyKey='PARIS-2026/secret';Execute=$true}
    Equal $r.ExitCode 0 $r.Message
    $paths=@($path)+@(ReceiptFiles $script:ledger|ForEach-Object{$_.FullName})+@(ReceiptFiles $script:store|ForEach-Object{$_.FullName})
    Assert ($paths.Count -eq 3) ('fichiers de preuve inattendus : '+$paths.Count)
    foreach($p in $paths){
        $text=[IO.File]::ReadAllText($p)
        Assert (-not $text.Contains($canary)) ('le secret de la credential fuite dans '+$p)
        Assert (-not ($text -match '(?i)password|securestring|credential')) ('un champ de credential parait dans '+$p)
        }
    Assert (-not (($r|ConvertTo-Json -Depth 8 -Compress).Contains($canary))) 'la credential fuite dans le résultat rendu'
    } -Reset
}finally{
    $env:PESTO_READONLY_SESSION=''
    if([IO.Directory]::Exists($root)){[IO.Directory]::Delete($root,$true)}
}
$report=[pscustomobject]@{Schema=1;Suite='AttributeEntry114';HostOS=[Environment]::OSVersion.ToString();PowerShell=$PSVersionTable.PSVersion.ToString();WindowsExecuted=$false;ADExecuted=$false;WPFExecuted=$false;GPOApplied=$false;RegistryWritten=$false;Scope='Point d entree public Invoke-PestoExtensionCommand joue reellement (mutex, cfg, plan sur disque, registre idempotent) ; plateforme, paquet, socle, module AD, cmdlets AD, ACL et magasins doublés ; aucun appel reseau ni VM';Total=$script:passed+$script:failed;Passed=$script:passed;Failed=$script:failed}
if($ReportPath){[IO.File]::WriteAllText([IO.Path]::GetFullPath($ReportPath),($report|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))}
Write-Host "AttributeEntry114: $script:passed passed, $script:failed failed. Public entry point, plan round trip and idempotency ledger real; AD/ACL/platform transports mocked; no VM."
if($script:failed){exit 1}
