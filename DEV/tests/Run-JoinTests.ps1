#requires -Version 5.1
[CmdletBinding()]
param([string]$ReportPath='')
# Windows PowerShell 5.1 : $PSScriptRoot est vide dans les valeurs par défaut des paramètres (vu le 03/10).
if(-not $ReportPath){$ReportPath=Join-Path $PSScriptRoot 'windows-join-results.json'}
# Isolated unit tests. Never dot-source Pesto-Core or launch Pesto.exe. AD, registry,
# receipts and Add-Computer are replaced by local fakes before any test call.
$ErrorActionPreference='Stop';Set-StrictMode -Off
if($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){throw 'Windows PowerShell 5.1 requis.'}
$root=Split-Path $PSScriptRoot -Parent
$results=[Collections.Generic.List[object]]::new()
function Assert {param($Value,[string]$Why='Condition fausse');if(-not $Value){throw $Why}}
function Equal {param($Actual,$Expected);if($Actual -cne $Expected){throw "Attendu [$Expected], obtenu [$Actual]"}}
function Throws {param([scriptblock]$Body);$ok=$false;try{& $Body}catch{$ok=$true};Assert $ok 'Exception attendue'}
function Case {param([string]$Name,[scriptblock]$Body);try{& $Body;$results.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''});Write-Host "OK $Name"}catch{$results.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message});Write-Host "KO $Name : $($_.Exception.Message)"}}
$definitions=@{}
# Les fonctions testees ont quitte Pesto-Core.ps1 : le banc indexe tout wad/, sinon il meurt au chargement.
foreach($file in (Get-ChildItem -LiteralPath (Join-Path $root 'wad') -File | Where-Object{$_.Extension -eq '.ps1'} | Sort-Object Name)){
    $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw ($file.Name+': '+($errors|Out-String))}
    foreach($fn in $ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){$definitions[$fn.Name]=$fn.Extent.Text}
}
foreach($name in @('Test-PestoDnsName','Test-PestoComputerName','Test-PestoGeneratedComputerName','Split-PestoDistinguishedName','Get-PestoDomainFromDN','Test-PestoOUPath','Test-PestoDNWithinScope','Test-PestoOUInConfiguredScope','Protect-PestoLogText','New-ActionResult','Test-PestoConfirmedChange','AddToDomain','Get-PestoJoinPlanErrors','Get-PestoJoinPlanKey','Get-PestoJoinReceiptDecision','Get-PestoJoinClockCheck','Get-PestoJoinPreflight','Assert-PestoJoinADReservationResolved','Invoke-PestoJoinExecuteLocked','Get-PestoJoinGuidance','Format-OUPath','Get-PestoJoinNameCandidates','Get-NameList','Get-AvailableMachines','ConvertTo-PestoPolicy','Get-PestoManagedPolicy','Merge-PestoManagedPolicy','Assert-PestoClosedObject','Test-PestoPropertyPresent','ConvertTo-PestoNameParts','Assert-PestoJoinReceiptData','New-PestoComputerName','Assert-PestoOperationPolicy','Get-PestoOutcome','Start-PestoIntervention','Get-PestoInterventions','Get-PestoInterventionRoot','Assert-PestoPlainPath','Read-PestoIntervention','Get-PestoPlanFingerprint','Get-PestoStableHash','Enter-PestoCoordination','Get-PestoCoordinationRoot','Write-PestoIntervention','Set-PestoEffect','Add-PestoInterventionEvent','Set-PestoInitialJoinObservation','Test-PestoJoinIntervention','Assert-PestoJoinEvidence','Test-PestoInterventionConflict','Test-PestoNameReservedByOther','ConvertTo-PestoObservationSnapshot','Test-PestoLedgerResume','Assert-PestoObservationSnapshot','Get-PestoNativeFailureCode','Complete-PestoIntervention','Connect-PestoCoordinationShare','Exit-PestoCoordination','Get-ADParams','Get-PestoCoordinationKeys','Get-PestoParentDN','Set-PestoJoinNativeStatus','Show-MsgWarning','Test-PestoOptionalPostCheckReceipt','Test-PestoAcknowledgedReceipt','Get-PestoNamingLayout','ConvertTo-PestoScenario','Get-PestoNamingResolutionNonce','Get-PestoDefaultNamingConvention','Assert-PestoNamingConvention','Set-PestoActiveNamingConvention','Get-PestoActiveNamingConvention','Get-PestoNameLength','Get-PestoNameMaximumNumber','New-PestoNameSeries','Format-PestoNameNumber','New-PestoNameFromSeries','Get-PestoNameSeriesBase','Get-PestoNameNumber','Test-PestoNameSeries','Get-PestoNamingFunctionNames','Get-PestoFacetPattern','New-PestoNameLdapPattern','Assert-PestoScenarioValues','Get-PestoPlanScenarioValues','Assert-PestoCampaignApproval')){
    if(-not $definitions.ContainsKey($name)){throw "Definition absente : $name"}
    . ([scriptblock]::Create($definitions[$name]))
}
# La fusion reste celle du moteur ; seule la lecture GPO est remplacee pour ne pas lire le registre du pilote.
function Get-PestoManagedPolicy {[pscustomobject]@{Values=[pscustomobject]@{};Configured=$false;Source='fixture'}}
# La politique HKLM est absente dans cette fixture ; l'assertion produit reste reelle.
function Get-PestoCampaignPolicy {return $null}
function Reset-Fakes {
    $script:PREFIXE='111301';$script:DOMAINE='example.local';$script:DC='dc01.example.local';$script:SIM=$false;$script:GUI=$false
    $script:OU=@{ROOT='OU=Postes,DC=example,DC=local';PREPROD='OU=Preparation,OU=Postes,DC=example,DC=local'};$script:OUV=@{Sites='OU=Sites,OU=Postes,DC=example,DC=local'}
    $script:cred=[pscredential]::new('EXAMPLE\test',(ConvertTo-SecureString 'FAKE-TEST-NOT-A-REAL-SECRET' -AsPlainText -Force))
    $script:FakeLocal=[pscustomobject]@{Computer=$env:COMPUTERNAME;PartOfDomain=$false;Domain='WORKGROUP';ActiveName=$env:COMPUTERNAME;ConfiguredName=$env:COMPUTERNAME;PendingRename=$false;Admin=$true;MachineId='4b008d30-8c02-4894-a829-d3d692012eca';BootUtc='2026-01-01T08:00:00.0000000Z';SecureChannel=$null;DomainRole=0}
    $script:SavedReceipt=$null;$script:FailSave=0;$script:WriteCount=0;$script:Taken=$false;$script:ADFail=$false;$script:NativeCalls=0;$script:FakeChange='ok';$script:NativeParams=$null;$script:LocalReads=0;$script:LocalDrift=$false;$script:RenameCalls=0;$script:FakeRename='ok';$script:RenameParams=$null;$script:ActiveIntervention=$null
    $script:Interventions=@{}
    $script:Writes=[Collections.Generic.List[string]]::new();$script:Order=[Collections.Generic.List[string]]::new()
    $script:Req=[pscustomobject]@{OperationId=[Guid]::NewGuid().ToString('N');StatePath='FAKE-NO-IO';Credential=$script:cred;Monitor=[hashtable]::Synchronized(@{MutationStarted=$false;CancelRequested=$false;TimedOut=$false});Plan=[pscustomobject]@{Computer=$env:COMPUTERNAME;NewName='P111301PR765010';Domain=$script:DOMAINE;DC=$script:DC;TargetOU=$script:OU.PREPROD;DirectProd=$false;Account=$script:cred.UserName};ConfirmedTargetOUGuid='aaaaaaaa-1111-2222-3333-123456789012';ConfirmedExistingGuid='';ConfirmedMachineId='4b008d30-8c02-4894-a829-d3d692012eca'}
}
function Get-PestoJoinLocalStatus {$script:LocalReads++;if($script:LocalDrift -and $script:LocalReads -gt 1){$script:FakeLocal.PartOfDomain=$true};return $script:FakeLocal}
function Read-PestoJoinReceipt {param($Path);return $script:SavedReceipt}
function Read-PestoJoinADReservationState {return $null}
function Write-PestoJoinReceipt {param($Path,$Receipt);$script:WriteCount++;if($script:FailSave -eq $script:WriteCount){throw 'Mock disk error'};$script:SavedReceipt=$Receipt|ConvertTo-Json -Depth 7|ConvertFrom-Json;$script:Writes.Add($Receipt.Phase);$script:Order.Add('receipt:'+ $Receipt.Phase)}
function Get-ADDomain {[CmdletBinding()]param($Server,$Credential);if($script:ADFail){throw 'Mock AD unreachable'};[pscustomobject]@{DNSRoot='example.local';DistinguishedName='DC=example,DC=local'}}
function Get-ADOrganizationalUnit {[CmdletBinding()]param($Identity,$Server,$Credential);[pscustomobject]@{DistinguishedName=$Identity;ObjectGUID=[Guid]::new('aaaaaaaa-1111-2222-3333-123456789012')}}
function Get-ADComputer {[CmdletBinding()]param($LDAPFilter,$SearchBase,$SearchScope,$Server,$Credential);if($script:Taken){[pscustomobject]@{Name='P111301PR765010'}}}
function Find-ADComputerByName {param($Name);if($script:Taken){[pscustomobject]@{Name=$Name}}}
function Test-PestoIsAdministrator {return $script:FakeLocal.Admin}
function Set-PestoWorkerStage {param($Name,$Detail)}
function Write-Log {param($Message,$Level,$ErrorRecord,$Context)}
function Assert-PestoWorkerMayContinue {param([switch]$Mutation);if($script:Req.Monitor.CancelRequested){throw 'Mock cancelled'};if($Mutation){$script:Req.Monitor.MutationStarted=$true}}
function Rename-Computer {
    [CmdletBinding()]param($NewName,[switch]$PassThru,[switch]$Force)
    $script:RenameCalls++;$script:Order.Add('Rename-Computer');$script:RenameParams=@{};foreach($key in $PSBoundParameters.Keys){$script:RenameParams[$key]=$PSBoundParameters[$key]}
    if($script:FakeRename -eq 'false'){return [pscustomobject]@{HasSucceeded=$false}}
    if($script:FakeRename -eq 'throw'){throw 'Mock local rename transport error'}
    $script:FakeLocal.ConfiguredName=$NewName;$script:FakeLocal.PendingRename=($script:FakeLocal.ActiveName -ine $NewName)
    return [pscustomobject]@{HasSucceeded=$true}
}
function Add-Computer {
    [CmdletBinding()]param($DomainName,$OUPath,$NewName,$Options,$Credential,$Server,[switch]$PassThru,[switch]$Force)
    if($PSBoundParameters.ContainsKey('NewName')){throw 'FORBIDDEN: Add-Computer must use the prepared local name'}
    if(($Options -join ',') -cne 'JoinWithNewName,AccountCreate'){throw 'Missing explicit new-name join options'}
    if($script:FakeLocal.ConfiguredName -cne $script:Req.Plan.NewName){throw 'Local name was not prepared before joining'}
    $script:NativeCalls++;$script:Order.Add('Add-Computer');$script:NativeParams=@{};foreach($key in $PSBoundParameters.Keys){$script:NativeParams[$key]=$PSBoundParameters[$key]}
    switch($script:FakeChange){
        'false' {return [pscustomobject]@{HasSucceeded=$false}}
        'empty' {return}
        'string' {return [pscustomobject]@{HasSucceeded='true'}}
        'rpc' {throw 'RPC 0x800706ba transport error'}
        'late' {$script:Req.Monitor.TimedOut=$true;return [pscustomobject]@{HasSucceeded=$true}}
        default {return [pscustomobject]@{HasSucceeded=$true}}
    }
}
function Restart-Computer {throw 'FORBIDDEN: no restart in unit tests'}
function Invoke-PestoDsregLeaveBeforeRename {throw 'FORBIDDEN: no Entra change in join tests'}
function Get-SiteTag {param($SiteName);return 'PR'}
# Le registre d'interventions du moteur passe par Write-PestoJoinReceipt : le banc le remplace par un faux en memoire,
# sinon les ecritures du registre compteraient comme des recus de jonction et deplaceront les pannes simulees.
$script:Interventions=@{}
function Write-PestoIntervention {param($Receipt);$script:Interventions[([Guid][string]$Receipt.OperationId).ToString('N')]=$Receipt|ConvertTo-Json -Depth 8|ConvertFrom-Json}
function Read-PestoIntervention {param($Path);$k=[IO.Path]::GetFileNameWithoutExtension([string]$Path);if($script:Interventions.ContainsKey($k)){$script:Interventions[$k]}}
function Get-PestoInterventions {@($script:Interventions.Values)}
# Le registre d'interventions du moteur ecrit ses recus sur disque : le banc confine la racine dans un repertoire temporaire.
$script:InterventionDir=Join-Path ([IO.Path]::GetTempPath()) ('pesto-join-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $script:InterventionDir | Out-Null
function Get-PestoInterventionRoot {$script:InterventionDir}
function Get-PestoStateDirectory {$script:InterventionDir}
function New-Receipt([string]$Phase) {[pscustomobject]@{Schema=1;OperationId='11111111-2222-3333-4444-555555555555';Phase=$Phase;Utc='2026-01-01T09:00:00.0000000Z';MachineId=$script:FakeLocal.MachineId;Computer=$env:COMPUTERNAME;NewName=$script:Req.Plan.NewName;Domain=$script:DOMAINE;OU=$script:Req.Plan.TargetOU;DC=$script:DC;BootUtc=$script:FakeLocal.BootUtc}}
Case 'Formulaire valide' {Reset-Fakes;Equal (@(Get-PestoJoinPlanErrors $script:Req.Plan).Count) 0}
Case 'Cible distante refusee' {Reset-Fakes;$script:Req.Plan.Computer='REMOTE';Assert (@(Get-PestoJoinPlanErrors $script:Req.Plan).Count -gt 0)}
Case 'Nom hors convention refuse' {Reset-Fakes;$script:Req.Plan.NewName='OTHER';Assert (@(Get-PestoJoinPlanErrors $script:Req.Plan).Count -gt 0)}
Case 'Domaine incompatible avec OU refuse' {Reset-Fakes;$script:Req.Plan.Domain='other.local';Assert (@(Get-PestoJoinPlanErrors $script:Req.Plan).Count -gt 0)}
Case 'Production ne contourne pas le transit impose' {Reset-Fakes;$script:Req.Plan.TargetOU=$script:OUV.Sites;Assert (@(Get-PestoJoinPlanErrors $script:Req.Plan).Count -gt 0)}
Case 'Production directe explicite dans le perimetre' {Reset-Fakes;$script:Req.Plan.DirectProd=$true;$script:Req.Plan.TargetOU=$script:OUV.Sites;Equal (@(Get-PestoJoinPlanErrors $script:Req.Plan).Count) 0}
Case 'Nom multiligne refuse' {Reset-Fakes;$script:Req.Plan.NewName="a`nb";Assert (@(Get-PestoJoinPlanErrors $script:Req.Plan).Count -gt 0)}
Case 'Toute modification de plan invalide sa signature' {Reset-Fakes;$key=Get-PestoJoinPlanKey $script:Req.Plan;$script:Req.Plan.NewName='P111301PR765011';Assert ($key -ne (Get-PestoJoinPlanKey $script:Req.Plan))}
Case 'Lecture seule ne joint pas le PC' {Reset-Fakes;$r=Get-PestoJoinPreflight $script:Req;Assert $r.Valid;Equal $script:NativeCalls 0;Equal $script:RenameCalls 0;Equal $script:WriteCount 0}
Case 'PC deja dans un domaine bloque' {Reset-Fakes;$script:FakeLocal.PartOfDomain=$true;Assert (-not (Get-PestoJoinPreflight $script:Req).Valid);Equal $script:NativeCalls 0}
Case 'Absence elevation bloque avant ecriture' {Reset-Fakes;$script:FakeLocal.Admin=$false;Assert (-not (Get-PestoJoinPreflight $script:Req).Valid)}
Case 'Redemarrage nom en attente bloque' {Reset-Fakes;$script:FakeLocal.PendingRename=$true;Assert (-not (Get-PestoJoinPreflight $script:Req).Valid)}
Case 'Absence credential bloque sans prompt' {Reset-Fakes;$script:Req.Credential=$null;Assert (-not (Get-PestoJoinPreflight $script:Req).Valid)}
Case 'Collision de nom bloque sans supprimer objet' {Reset-Fakes;$script:Taken=$true;Assert (-not (Get-PestoJoinPreflight $script:Req).Valid)}
Case 'Panne AD reste une erreur' {Reset-Fakes;$script:ADFail=$true;Throws {Get-PestoJoinPreflight $script:Req};Equal $script:NativeCalls 0}
Case 'Controleur explicite requis' {Reset-Fakes;$script:Req.Plan.DC='example.local';Throws {Get-PestoJoinPreflight $script:Req}}
Case 'Recu Running bloque une nouvelle jonction' {Reset-Fakes;$script:SavedReceipt=New-Receipt 'Running';Assert (-not (Get-PestoJoinPreflight $script:Req).Valid)}
Case 'Recu incertain reste bloque' {Reset-Fakes;$r=Get-PestoJoinReceiptDecision (New-Receipt 'Uncertain') $script:FakeLocal $script:DOMAINE;Assert $r.Blocked;Equal $r.Phase 'Uncertain'}
Case 'Un recu d une autre machine est refuse' {Reset-Fakes;$r=New-Receipt 'Running';$r.MachineId='different';Throws {Get-PestoJoinReceiptDecision $r $script:FakeLocal $script:DOMAINE}}
Case 'Succession recu / appel Windows / recu confirme' {Reset-Fakes;$r=Invoke-PestoJoinExecuteLocked $script:Req;Equal $r.Action.ExitCode 10;Equal ($script:Order -join ',') 'receipt:Running,Rename-Computer,Add-Computer,receipt:PendingRestart'}
Case 'Aucun parametre Restart ni cible distante' {Reset-Fakes;$null=Invoke-PestoJoinExecuteLocked $script:Req;Assert (-not $script:NativeParams.ContainsKey('Restart'));Assert (-not $script:NativeParams.ContainsKey('ComputerName'));Assert (-not $script:NativeParams.ContainsKey('NewName'));Equal ($script:NativeParams.Options -join ',') 'JoinWithNewName,AccountCreate';Equal $script:NativeParams.OUPath $script:OU.PREPROD;Equal $script:NativeCalls 1;Equal $script:RenameCalls 1;Assert (-not $script:RenameParams.ContainsKey('ComputerName'));Assert (-not $script:RenameParams.ContainsKey('DomainCredential'))}
Case 'Le recu ne contient pas de credential' {Reset-Fakes;$null=Invoke-PestoJoinExecuteLocked $script:Req;$j=$script:SavedReceipt|ConvertTo-Json;Assert ($j -notmatch 'FAKE-TEST-NOT-A-REAL-SECRET|SecureString|Credential')}
Case 'Recu initial impossible : aucune mutation' {Reset-Fakes;$script:FailSave=1;Throws {Invoke-PestoJoinExecuteLocked $script:Req};Equal $script:NativeCalls 0;Equal $script:RenameCalls 0}
Case 'Recu final impossible : resultat incertain' {Reset-Fakes;$script:FailSave=2;$r=Invoke-PestoJoinExecuteLocked $script:Req;Equal $r.Action.ExitCode 97;Equal $script:SavedReceipt.Phase 'Running'}
Case 'Etat local change pendant controle : non lance' {Reset-Fakes;$script:LocalDrift=$true;$r=Invoke-PestoJoinExecuteLocked $script:Req;Equal $r.Action.ExitCode 96;Equal $script:NativeCalls 0}
Case 'HasSucceeded faux apres preparation locale : incertain sans reprise' {Reset-Fakes;$script:FakeChange='false';$r=Invoke-PestoJoinExecuteLocked $script:Req;Equal $r.Action.ExitCode 97;Equal $script:SavedReceipt.Phase 'Uncertain';Equal $script:RenameCalls 1}
foreach($badRename in @('false','throw')){
    Case "Renommage local $badRename : jonction jamais lancee" {Reset-Fakes;$script:FakeRename=$badRename;$r=Invoke-PestoJoinExecuteLocked $script:Req;Equal $r.Action.ExitCode 97;Equal $script:SavedReceipt.Phase 'Uncertain';Equal $script:RenameCalls 1;Equal $script:NativeCalls 0}
}
foreach($bad in @('empty','string','rpc','late')){
    Case "Retour Windows $bad : incertain" {Reset-Fakes;$script:FakeChange=$bad;$r=Invoke-PestoJoinExecuteLocked $script:Req;Equal $r.Action.ExitCode 97;Equal $script:SavedReceipt.Phase 'Uncertain'}
}
Case 'Annulation avant appel : aucune mutation' {Reset-Fakes;$script:Req.Monitor.CancelRequested=$true;Throws {Invoke-PestoJoinExecuteLocked $script:Req};Equal $script:NativeCalls 0;Equal $script:RenameCalls 0}
Case 'Sans reboot le succes reste en attente' {Reset-Fakes;$r=Get-PestoJoinReceiptDecision (New-Receipt 'PendingRestart') $script:FakeLocal $script:DOMAINE;Assert $r.Blocked;Equal $r.Phase 'PendingRestart'}
Case 'Apres reboot sans canal confirme : pas de verification inventee' {Reset-Fakes;$rec=New-Receipt 'PendingRestart';$script:FakeLocal.BootUtc='2026-01-02T08:00:00Z';$r=Get-PestoJoinReceiptDecision $rec $script:FakeLocal $script:DOMAINE;Assert $r.Blocked;Equal $r.Phase 'Uncertain'}
# Get-PestoJoinReceiptDecision ne rend jamais Verified de lui-meme : l'accord Windows+canal ouvre seulement l'observation AD.
Case 'Reboot + nom + domaine + canal : pret a observer, verification AD jamais auto-certifiee' {Reset-Fakes;$rec=New-Receipt 'PendingRestart';$script:FakeLocal.BootUtc='2026-01-02T08:00:00Z';$script:FakeLocal.Computer=$rec.NewName;$script:FakeLocal.ActiveName=$rec.NewName;$script:FakeLocal.ConfiguredName=$rec.NewName;$script:FakeLocal.DomainRole=1;$script:FakeLocal.PartOfDomain=$true;$script:FakeLocal.Domain=$rec.Domain;$script:FakeLocal.SecureChannel=$true;$r=Get-PestoJoinReceiptDecision $rec $script:FakeLocal $script:DOMAINE;Assert (-not $r.Blocked);Equal $r.Phase 'ReadyToObserve';Assert ($r.Message -match 'Interventions')}
Case 'Virgule echappee preservee dans le chemin lisible' {Reset-Fakes;$text=Format-OUPath 'OU=Site\, Centre,OU=Postes,DC=example,DC=local';Assert ($text -match 'Site, Centre')}
Case 'Noms generes : chaines distinctes, pas tableau dans la ComboBox' {Reset-Fakes;$names=@(Get-PestoJoinNameCandidates -Type Portable -Site PREPROD -Service 765 -Computers @());Equal $names.Count 999;Equal $names[0] 'P111301PR765001';Assert ($names[0] -is [string])}
Case 'Noms generes : reservations ecartees' {Reset-Fakes;$names=@(Get-PestoJoinNameCandidates -Type Portable -Site PREPROD -Service 765 -Computers @([pscustomobject]@{Name='P111301PR765001'}));Equal $names.Count 998;Equal $names[0] 'P111301PR765002'}
$failed=@($results|Where-Object{-not $_.Passed}).Count
[pscustomobject]@{Version='1.0';Kind='Windows isolated tests, no real AD or join';Failed=$failed;Tests=$results.ToArray()}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $ReportPath -Encoding UTF8
try{Remove-Item -LiteralPath $script:InterventionDir -Recurse -Force -ErrorAction SilentlyContinue}catch{}
Write-Host "$($results.Count) cas ; $failed echec(s)."
if($failed){exit 1}else{exit 0}
