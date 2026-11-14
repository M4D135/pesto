#requires -Version 5.1
# Reçus machine partagés. Aucun accès réseau ou mutation lors du chargement.

function Get-PestoNativeFailureCode {
    param($ErrorRecord)
    $ex=if($ErrorRecord -is [Exception]){$ErrorRecord}else{$ErrorRecord.Exception}
    for($i=0;$ex -and $i -lt 8;$i++){
        if($ex.PSObject.Properties['NativeErrorCode'] -and $ex.NativeErrorCode -is [int]){return [long]$ex.NativeErrorCode}
        $hr=[long]$ex.HResult -band 4294967295
        if(($hr -band 4294901760) -eq 2147942400){return ($hr -band 65535)}
        $ex=$ex.InnerException
    }
    return $null
}

function Import-PestoADModule {
    param([Parameter(Mandatory=$true)][string]$ADModulePath)
    $path=[IO.Path]::GetFullPath($ADModulePath)
    if(-not [IO.Path]::IsPathRooted($ADModulePath) -or [IO.Path]::GetFileName($path) -ine 'ActiveDirectory.psd1'){
        throw 'Le module AD doit être le manifeste absolu approuvé du pack.'
    }
    Assert-PestoPlainPath $path
    if(-not [IO.File]::Exists($path)){throw 'Module ActiveDirectory embarqué absent.'}
    $folder=[IO.Path]::GetDirectoryName($path)
    $loaded=@(Get-Module -Name ActiveDirectory -ErrorAction Stop)
    foreach($module in $loaded){
        if([IO.Path]::GetFullPath([string]$module.ModuleBase).TrimEnd('\') -ine $folder.TrimEnd('\')){
            throw 'Un module ActiveDirectory d''une autre origine est déjà chargé. Redémarrez Pesto dans une session propre.'
        }
    }
    if(-not $loaded.Count){
        # Le module ActiveDirectory monte un lecteur AD: par défaut à chaque
        # import et contacte un contrôleur : ~140 ms par runspace (mesuré le
        # 10/10/2026 sur la VM de labo : 154 ms sans drapeau, 12 ms avec).
        # Pesto ne parcourt aucun chemin AD:\ — vérifié sur tout wad/ — donc
        # rien ne dépend de ce lecteur.
        $env:ADPS_LoadDefaultDrive='0'
        Import-Module -Name $path -ErrorAction Stop -WarningAction SilentlyContinue
    }
}

function Assert-PestoPlainPath {
    param([Parameter(Mandatory=$true)][string]$Path)
    $current=[IO.Path]::GetFullPath($Path)
    while($current){
        if(Test-Path -LiteralPath $current){
            $item=Get-Item -LiteralPath $current -Force -ErrorAction Stop
            if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Un chemin critique traverse un lien ou une jonction.'}
        }
        $next=[IO.Path]::GetDirectoryName($current)
        if($current -eq $next){break};$current=$next
    }
}

function Get-PestoInterventionRoot {
    $base=[Environment]::GetFolderPath('CommonApplicationData')
    if(-not $base){throw 'ProgramData indisponible : aucune mutation autorisée.'}
    return [IO.Path]::Combine($base,'GP','Interventions')
}

function Read-PestoIntervention {
    param([Parameter(Mandatory=$true)][string]$Path)
    Assert-PestoPlainPath $Path
    $file=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if($file.PSIsContainer -or $file.Length -gt 131072){throw 'Reçu d''intervention trop volumineux ou invalide.'}
    $r=Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    Assert-PestoClosedObject $r @('Schema','Version','OperationId','Plan','StartedUtc','UpdatedUtc','Phase','InitialProtection','TargetMachineId','TargetOUGuid','Entra','Protection','Rename','Move','ResultCode','ResultMessage','LastStage','VerifiedUtc','VerifiedBy','ResumeFrom','PlanFingerprint','Sequence','Timeline','Coordination','Tasks','Legacy','Baseline','LastObservation','JoinEvidence','Metadata','Acknowledged','Attributes','AttributeChanges','OfflineJoin') @('Schema','OperationId','Plan','Phase','Entra','Protection','Rename','Move','ResultCode')
    Assert-PestoClosedObject $r.Plan @('Nom_du_PC','Nouveau_Nom','OU_Actuelle','OU_Destination','Objet_GUID','Domain','DC','ConfigStamp','TargetOUGuid','Renommer','Deplacer','Reboot','Reference') @('Nom_du_PC','Domain','Renommer','Deplacer')
    if(($r.Schema -isnot [int] -and $r.Schema -isnot [long]) -or ($r.ResultCode -isnot [int] -and $r.ResultCode -isnot [long]) -or
       $r.Schema -lt 1 -or $r.Schema -gt 3 -or $r.ResultCode -lt [int]::MinValue -or $r.ResultCode -gt [int]::MaxValue){throw 'Types du reçu invalides.'}
    # JSON integers may be Int64 on PowerShell 7; retain the exact Int32 contract after range validation.
    $r.Schema=[int]$r.Schema;$r.ResultCode=[int]$r.ResultCode
    foreach($name in @('Nom_du_PC','Nouveau_Nom','OU_Actuelle','OU_Destination','Objet_GUID','Domain','DC','ConfigStamp','TargetOUGuid','Reference')){
        $value=$r.Plan.$name
        if($null -ne $value -and ($value -isnot [string] -or $value.Length -gt 4096 -or $value -match '[\x00-\x1f\x7f]')){throw ('Champ du plan invalide : '+$name)}
    }
    if($r.PlanFingerprint -and (Get-PestoPlanFingerprint $r.Plan) -cne $r.PlanFingerprint){throw 'Le plan du reçu a changé depuis son enregistrement.'}
    if(@($r.Timeline).Count -gt 96){throw 'Historique des phases trop volumineux.'}
    $last=0L
    foreach($timelineEvent in @($r.Timeline)){
        if($null -eq $timelineEvent){continue}
        Assert-PestoClosedObject $timelineEvent @('Sequence','Utc','Stage','State') @('Sequence','Utc','Stage','State')
        if(($timelineEvent.Sequence -isnot [int] -and $timelineEvent.Sequence -isnot [long]) -or $timelineEvent.Sequence -le $last -or $timelineEvent.Stage -isnot [string] -or $timelineEvent.State -isnot [string] -or $timelineEvent.Stage.Length -gt 200 -or $timelineEvent.State.Length -gt 4096){throw 'Historique des phases invalide.'}
        $last=[long]$timelineEvent.Sequence
    }
    if($r.Coordination){
        Assert-PestoClosedObject $r.Coordination @('Enabled','Keys','Owner','ResumeFrom') @('Enabled','Keys','Owner')
        if($r.Coordination.Enabled -isnot [bool] -or @($r.Coordination.Keys).Count -gt 3 -or [string]$r.Coordination.Owner -cne [string]$r.OperationId){throw 'Coordination du reçu invalide.'}
        foreach($key in @($r.Coordination.Keys)){if($key -isnot [string] -or $key -notmatch '^[a-f0-9]{64}$'){throw 'Clé de coordination invalide.'}}
    }
    $id=[Guid]::Empty
    if($r.Schema -notin @(1,2,3) -or -not [Guid]::TryParse([string]$r.OperationId,[ref]$id) -or $id -eq [Guid]::Empty -or
        $file.BaseName -ine $id.ToString('N') -or -not $r.Plan -or
        $r.Phase -notin @('Running','Failed','PendingRestart','Partial','MoveReady','Uncertain','Verified') -or
        $r.Entra -notin @('NotRequested','Requested','Skipped','Confirmed','Uncertain') -or
        $r.Protection -notin @('NotChanged','Prepared','Lowering','Lowered','Restoring','Restored') -or
        $r.Rename -notin @('NotRequested','Requested','Confirmed','Refused') -or
        $r.Move -notin @('NotRequested','Requested','Confirmed','Refused') -or
        -not (Test-PestoComputerName ([string]$r.Plan.Nom_du_PC)) -or
        -not (Test-PestoDnsName ([string]$r.Plan.Domain)) -or
        $r.Plan.Renommer -isnot [bool] -or $r.Plan.Deplacer -isnot [bool] -or
        ($null -ne $r.InitialProtection -and $r.InitialProtection -isnot [bool])){
        throw 'Reçu d''intervention illisible. Vérification manuelle requise ; aucun verrou supprimé.'
    }
    if($r.OfflineJoin -and $r.OfflineJoin -notin @('Requested','PendingRestart','Uncertain','Verified')){throw 'Effet ODJ invalide.'}
    if($r.Attributes){if($r.Attributes -notin @('NotRequested','Requested','Confirmed','Uncertain')){throw 'Effet attributs invalide.'};Assert-PestoAttributeChanges $r.AttributeChanges}
    if(@($r.Tasks).Count -gt 8){throw 'Reçu de tâches trop volumineux.'}
    foreach($task in @($r.Tasks)){if($task){
        Assert-PestoClosedObject $task @('Computer','Name','Phase','Hash','NativeCode','Utc') @('Computer','Name','Phase','Hash')
        if(-not(Test-PestoComputerName ([string]$task.Computer)) -or $task.Name -notmatch '^\\Pesto_[A-Za-z0-9_]+$' -or
            $task.Phase -notin @('Registering','Registered','StartRequested','Started','Finished','Deleted') -or
            ($task.Hash -and $task.Hash -notmatch '^[A-Fa-f0-9]{64}$')){throw 'Reçu de tâche invalide.'}
    }}
    if($r.JoinEvidence){
        if($r.Schema -ne 3 -or -not(Test-PestoJoinIntervention $r)){throw 'Preuve de jonction attachée à un reçu incompatible.'}
        [void](Assert-PestoJoinEvidence $r.JoinEvidence)
        if($r.JoinEvidence.MachineId -ine $r.TargetMachineId -or -not(Test-PestoOUPath ([string]$r.Plan.OU_Destination)) -or (Get-PestoDomainFromDN $r.Plan.OU_Destination) -ine $r.Plan.Domain){throw 'Identité de jonction différente du reçu.'}
    }elseif($r.Schema -eq 3){throw 'Preuve initiale de jonction absente.'}
    foreach($name in @('Baseline','LastObservation')){if($r.$name){[void](Assert-PestoObservationSnapshot $r.$name)}}
    # Acquittement (15/10) : schéma fermé ; un acquittement altéré rend le reçu illisible, jamais résolu.
    if($r.PSObject.Properties['Acknowledged'] -and $null -ne $r.Acknowledged){[void](Assert-PestoAcknowledgement $r.Acknowledged)}
    if($r.Metadata){[void](ConvertTo-PestoDeploymentMetadata $r.Metadata -LegacyReceipt)}
    if($r.Plan.Reference -and ([string]$r.Plan.Reference).Length -gt 120){throw 'Référence de reçu trop longue.'}
    return $r
}

function Get-PestoInterventions {
    $root=Get-PestoInterventionRoot
    Assert-PestoPlainPath $root
    if(-not [IO.Directory]::Exists($root)){return}
    $files=@(Get-ChildItem -LiteralPath $root -Filter '*.json' -File -ErrorAction Stop)
    if($files.Count -gt 5000){throw 'Trop de reçus dans le registre local. Archiver les interventions vérifiées avec le support.'}
    foreach($file in $files){Read-PestoIntervention -Path $file.FullName}
}

function Write-PestoIntervention {
    param([Parameter(Mandatory=$true)]$Receipt)
    $id=[Guid]::Empty
    if(-not [Guid]::TryParse([string]$Receipt.OperationId,[ref]$id) -or $id -eq [Guid]::Empty){throw 'Identifiant d''intervention invalide.'}
    $path=Join-Path (Get-PestoInterventionRoot) ($id.ToString('N')+'.json')
    $text=$Receipt|ConvertTo-Json -Depth 8
    if([Text.Encoding]::UTF8.GetByteCount($text) -gt 131072){throw 'Reçu trop volumineux : mutation suivante interdite.'}
    Write-PestoJoinReceipt -Path $path -Receipt $Receipt
}

function Test-PestoInterventionConflict {
    param($Existing,$Plan,[switch]$IncludeCompleted)
    if($Existing.Phase -in @('Failed','Verified')){return $false}
    if(-not $IncludeCompleted -and (Test-PestoOptionalPostCheckReceipt $Existing)){return $false}
    if(-not $IncludeCompleted -and (Test-PestoAcknowledgedReceipt $Existing)){return $false}
    if($Existing.Plan.Domain -ine $Plan.Domain){return $false}
    if($Existing.Plan.Objet_GUID -and $Plan.Objet_GUID -and $Existing.Plan.Objet_GUID -ieq $Plan.Objet_GUID){return $true}
    $names=@($Plan.Nom_du_PC,$Plan.Nouveau_Nom) | Where-Object {$_}
    foreach($name in @($Existing.Plan.Nom_du_PC,$Existing.Plan.Nouveau_Nom)){
        if($name -and $name -in $names){return $true}
    }
    return $false
}

function Start-PestoIntervention {
    param($Plan,[string]$OperationId,[string]$ResumeId)
    if($script:SIM -or $script:GUI){$script:ActiveIntervention=$null;return}
    if($Plan.Renommer -isnot [bool] -or $Plan.Deplacer -isnot [bool] -or
        -not(Test-PestoComputerName ([string]$Plan.Nom_du_PC)) -or
        -not(Test-PestoDnsName ([string]$Plan.Domain))){throw 'Plan d''intervention invalide.'}
    foreach($existing in @(Get-PestoInterventions)){
        # Anciens reçus : nettoyer uniquement les clés de cette cible, détenues par ce reçu terminé.
        # Une coordination désactivée ne requiert aucun accès à l'ancien partage.
        if(((Test-PestoOptionalPostCheckReceipt $existing) -or (Test-PestoAcknowledgedReceipt $existing)) -and $script:PestoPolicy.CoordinationRoot -and
            (Test-PestoInterventionConflict $existing $Plan -IncludeCompleted)){
            Exit-PestoCoordination -Receipt $existing -Policy $script:PestoPolicy
        }
        if(Test-PestoInterventionConflict $existing $Plan){
            if(Test-PestoLedgerResume -Existing $existing -Plan $Plan -ResumeId $ResumeId){continue}
            throw ('Intervention précédente à vérifier sur cette cible : '+$existing.OperationId+'. Ouvrez Interventions. Aucune nouvelle commande lancée.')
        }
    }
    $id=[Guid]::Empty
    if(-not [Guid]::TryParse($OperationId,[ref]$id) -or $id -eq [Guid]::Empty){$id=[Guid]::NewGuid()}
    $path=Join-Path (Get-PestoInterventionRoot) ($id.ToString('N')+'.json')
    if(Test-Path -LiteralPath $path){throw 'Identifiant d''intervention déjà utilisé.'}
    # Liste fermée : ne sérialise jamais le Request complet ni un PSCredential.
    $copy=[pscustomobject]@{Nom_du_PC=[string]$Plan.Nom_du_PC;Nouveau_Nom=[string]$Plan.Nouveau_Nom;
        OU_Actuelle=[string]$Plan.OU_Actuelle;OU_Destination=[string]$Plan.OU_Destination;
        Objet_GUID=[string]$Plan.Objet_GUID;Domain=[string]$Plan.Domain;DC=[string]$Plan.DC;
        ConfigStamp=[string]$Plan.ConfigStamp;TargetOUGuid=[string]$Plan.TargetOUGuid;
        Renommer=[bool]$Plan.Renommer;Deplacer=[bool]$Plan.Deplacer;Reboot=[bool]$Plan.Reboot}
    $r=[pscustomobject]@{Schema=2;Version='1.0';OperationId=$id.ToString('N');Plan=$copy;
        StartedUtc=[DateTime]::UtcNow.ToString('o');UpdatedUtc=[DateTime]::UtcNow.ToString('o');Phase='Running';
        InitialProtection=$null;TargetMachineId='';TargetOUGuid='';Entra='NotRequested';Protection='NotChanged';
        Rename='NotRequested';Move='NotRequested';ResultCode=0;ResultMessage='Plan enregistré avant commande.';
        Baseline=$null;LastObservation=$null;LastStage='Prepared';VerifiedUtc='';VerifiedBy='';ResumeFrom=$ResumeId;PlanFingerprint=(Get-PestoPlanFingerprint $copy);Sequence=0;Timeline=@()}
    if($Plan.Metadata){$r|Add-Member NoteProperty Metadata (ConvertTo-PestoDeploymentMetadata $Plan.Metadata)}
    $coord=Enter-PestoCoordination -Plan $copy -OperationId $id.ToString('N') -Policy $script:PestoPolicy -ResumeId $ResumeId
    $r|Add-Member -NotePropertyName Coordination -NotePropertyValue $coord
    try{Write-PestoIntervention $r}catch{$r.Phase='Failed';try{Exit-PestoCoordination $r $script:PestoPolicy}catch{};throw}
    $script:ActiveIntervention=$r
}

function Set-PestoEffect {
    param([ValidateSet('TargetMachineId','TargetOUGuid','InitialProtection','Entra','Protection','Rename','Move','Attributes')][string]$Name,$Value)
    if($script:SIM -or $script:GUI){return}
    if(-not $script:ActiveIntervention){throw 'Reçu d''intervention absent : commande refusée.'}
    if($Name -eq 'InitialProtection' -and $Value -isnot [bool]){throw 'État initial de protection non confirmé.'}
    if($Name -in @('Rename','Move') -and $Value -eq 'Requested' -and $script:ActiveIntervention.$Name -eq 'Confirmed'){throw 'Une étape confirmée ne peut pas être rejouée.'}
    $script:ActiveIntervention.$Name=$Value
    $script:ActiveIntervention.LastStage=$Name+': '+[string]$Value
    $script:ActiveIntervention.UpdatedUtc=[DateTime]::UtcNow.ToString('o')
    Add-PestoInterventionEvent -Receipt $script:ActiveIntervention -Stage $Name -State ([string]$Value)
    Write-PestoIntervention $script:ActiveIntervention
}

function Complete-PestoIntervention {
    param($Action,[bool]$TimedOut=$false)
    $r=$script:ActiveIntervention
    if(-not $r){return $Action}
    if(-not $Action -or $Action.ExitCode -isnot [int]){$Action=New-ActionResult 97 'Retour moteur non typé ; résultat à vérifier.'}
    $code=$Action.ExitCode
    $effects=($r.JoinEvidence.NativeStatus -in @('Requested','Accepted') -or $r.Entra -in @('Requested','Confirmed','Uncertain') -or $r.Rename -in @('Requested','Confirmed') -or
        $r.Move -in @('Requested','Confirmed') -or $r.Attributes -in @('Requested','Confirmed','Uncertain') -or $r.OfflineJoin -in @('Requested','PendingRestart','Uncertain') -or $r.Protection -notin @('NotChanged','Restored'))
    $outcome=Get-PestoOutcome -Code $code -Committed $effects -PartialEffect $effects -TimedOut $TimedOut
    $r.Phase=switch($outcome){'NotStarted'{'Failed'};'Refused'{'Failed'};'Partial'{'Partial'};'PendingRestart'{'PendingRestart'};'Verified'{'Verified'};default{'Uncertain'}}
    if($r.Phase -eq 'Uncertain' -and $code -notin @(32,97,98,99)){$Action=New-ActionResult 97 ($Action.ExitMsg+' Résultat non classifiable avec certitude ; aucune relance automatique.')}

    if($r.Phase -eq 'Partial' -and $code -ne 89){
        $Action=New-ActionResult 97 ($Action.ExitMsg+' Une étape a déjà pu modifier la cible. Consulter Interventions avant toute reprise.')
    }
    $Action|Add-Member -NotePropertyName Outcome -NotePropertyValue $(if($r.Phase -eq 'Partial'){'Partial'}else{Get-PestoOutcome -Code $Action.ExitCode -Committed $effects -PartialEffect $effects -TimedOut $TimedOut}) -Force
    Add-PestoInterventionEvent -Receipt $r -Stage 'Result' -State $r.Phase
    $r.ResultCode=[int]$Action.ExitCode;$r.ResultMessage=Protect-PestoLogText ([string]$Action.ExitMsg)
    if($r.ResultMessage.Length -gt 8000){$r.ResultMessage=$r.ResultMessage.Substring(0,8000)}
    $r.UpdatedUtc=[DateTime]::UtcNow.ToString('o')
    Write-PestoIntervention $r
    if($r.Phase -in @('Failed','Verified') -or (Test-PestoOptionalPostCheckReceipt $r)){Exit-PestoCoordination -Receipt $r -Policy $script:PestoPolicy}
    # Un retour tardif (supervision expirée) ou non classé « Verified » ne résout jamais l'intervention parente.
    if($r.ResumeFrom -and -not $TimedOut -and $r.Phase -eq 'Verified' -and $Action.ExitCode -in @(30,33)){
        $parentPath=Join-Path (Get-PestoInterventionRoot) (([Guid]$r.ResumeFrom).ToString('N')+'.json')
        $parent=Read-PestoIntervention $parentPath
        if(-not(Test-PestoLedgerResume $parent $r.Plan $r.ResumeFrom)){throw 'Le reçu parent ne correspond plus au déplacement terminé.'}
        $parent.Move='Confirmed';$parent.Phase=if($parent.Plan.Renommer){'PendingRestart'}else{'Verified'}
        $parent.UpdatedUtc=[DateTime]::UtcNow.ToString('o');$parent.LastStage='Move confirmed by '+$r.OperationId
        Write-PestoIntervention $parent
        Exit-PestoCoordination -Receipt $parent -Policy $script:PestoPolicy
    }
    foreach($property in @('OperationId','TargetMachineId','InitialProtection','Entra')){
        $Action|Add-Member -NotePropertyName $property -NotePropertyValue $r.$property -Force
    }
    $Action|Add-Member -NotePropertyName ObjectGuid -NotePropertyValue ([string]$r.Plan.Objet_GUID) -Force
    return $Action
}

function Assert-PestoRenameTarget {
    param([string]$ComputerName)
    if($script:SIM -or $script:GUI){return}
    $request=[pscustomobject]@{Computer=$ComputerName;AlternativeComputer='';ObjectGuid=$script:ExpectedObjectGuid;
        LocalSource=($ComputerName -ieq $env:COMPUTERNAME);Domain=$script:DOMAINE;DC=$script:DC;
        Credential=$script:cred;ADModulePath=$script:ApprovedADModulePath;RenamePreflight=$true}
    $observation=Get-PestoPostObservation $request
    if(-not $observation.Windows -or -not $observation.AD){throw 'L''identité Windows et AD ne peut pas être confirmée. Aucun retrait Entra ni renommage.'}
    $w=$observation.Windows;$ad=$observation.AD
    if($ad.Name -ine $ComputerName -or $w.ActiveName -ine $ComputerName -or
        ($w.ConfiguredName -and $w.ConfiguredName -ine $ComputerName) -or
        ($request.LocalSource -and (-not $w.ConfiguredName -or -not $w.MachineId)) -or -not $w.PartOfDomain -or $w.Domain -ine $script:DOMAINE -or $w.DomainRole -notin @(1,3)){
        throw 'Cible sensible, identité incohérente ou changement de nom déjà en attente. Aucun retrait Entra lancé.'
    }
    if($script:ExpectedObjectGuid -and $ad.Guid -ine $script:ExpectedObjectGuid){throw 'Le GUID de la cible a changé.'}
    $actualGuid=[Guid]::Empty
    if(-not [Guid]::TryParse([string]$ad.Guid,[ref]$actualGuid) -or $actualGuid -eq [Guid]::Empty){throw 'Identité AD vide avant commande.'}
    $script:ExpectedObjectGuid=$actualGuid.ToString()
    if($script:ActiveIntervention.Plan.Objet_GUID -and $script:ActiveIntervention.Plan.Objet_GUID -ine $actualGuid.ToString()){throw 'L''identité du plan immuable a changé.'}
    Set-PestoInitialObservation -Observation $observation
    if($w.MachineId){Set-PestoEffect -Name TargetMachineId -Value ([string]$w.MachineId)}
    if(-not $request.LocalSource -and (-not $w.ConfiguredName -or -not $w.MachineId)){
        Write-Log 'Identité distante confirmée par AD et Win32_ComputerSystem. Registre complémentaire non disponible ; suivi Windows détaillé à vérifier séparément.' 'WARN' $null 'rename'
    }
}

function Invoke-PestoGuardedAction {
    param($Request)
    $script:ActiveIntervention=$null
    $plan=$null
    try {
        if($Request.ReadOnly -eq $true){throw 'Consultation : mutation interdite dans le moteur.'}
        $plan=New-PestoExecutionPlan $Request
        if(-not($script:GUI -or $script:SIM)){
            Assert-PestoConfirmedPlan -Plan $plan -Fingerprint ([string]$Request.PlanFingerprint) -ConfigurationStamp ([string]$Request.ConfigStamp)
            Assert-PestoOperationPolicy -Plan $plan -Policy $Request.Policy
            if($plan.Deplacer){
                $adp=Get-ADParams
                $destination=Get-ADOrganizationalUnit -Identity $plan.OU_Destination -Properties ObjectGUID -ErrorAction Stop @adp
                if(-not $plan.TargetOUGuid -or [string]$destination.ObjectGUID -ine $plan.TargetOUGuid){throw 'La destination ne correspond plus à l''OU confirmée. Refaire le contrôle avant toute mutation.'}
            }
        }
        Start-PestoIntervention -Plan $plan -OperationId ([string]$Request.OperationId) -ResumeId ([string]$Request.ResumeId)
        Assert-PestoCampaignApproval -Plan $plan -Approval $Request.Approval
        $output=@(Go -Renommer $plan.Renommer -Deplacer $plan.Deplacer -Nom_du_PC $plan.Nom_du_PC -Nouveau_Nom $plan.Nouveau_Nom -OU_Destination $plan.OU_Destination -OU_Actuelle $plan.OU_Actuelle -Confirm $false)
        $action=if($output.Count -eq 1){$output[0]}else{New-ActionResult 97 'Résultat moteur absent ou multiple.'}
        return Complete-PestoIntervention -Action $action -TimedOut ([bool]$Request.Telemetry.TimedOut)
    }catch{
        $action=New-ActionResult $(if($script:ActiveIntervention){97}else{96}) (Protect-PestoLogText $_.Exception.Message)
        if($script:ActiveIntervention){try{return Complete-PestoIntervention $action}catch{return New-ActionResult 97 'Résultat non enregistré. Le reçu reste bloquant. Vérifiez la cible avant toute reprise.'}}
        return $action
    }finally{$script:ActiveIntervention=$null}
}

function Get-PestoADLoaderSource {
    $builder=[Text.StringBuilder]::new()
    foreach($name in @('Assert-PestoPlainPath','Import-PestoADModule')){
        $definition=(Get-Command $name -CommandType Function -ErrorAction Stop).Definition
        [void]$builder.AppendLine("function $name {`r`n$definition`r`n}")
    }
    return $builder.ToString()
}

function Test-PestoLedgerResume {
    param($Existing,$Plan,[string]$ResumeId)
    $a=[Guid]::Empty;$b=[Guid]::Empty
    if(-not [Guid]::TryParse($ResumeId,[ref]$a) -or -not [Guid]::TryParse([string]$Existing.OperationId,[ref]$b) -or $a -ne $b){return $false}
    return ($Existing.Phase -eq 'MoveReady' -and $Plan.Renommer -eq $false -and $Plan.Deplacer -eq $true -and
        $Existing.Plan.Objet_GUID -and $Existing.Plan.Objet_GUID -ieq $Plan.Objet_GUID -and
        $Existing.Plan.Domain -ieq $Plan.Domain -and $Existing.Plan.Nouveau_Nom -ieq $Plan.Nom_du_PC -and
        $Plan.Nouveau_Nom -ieq $Plan.Nom_du_PC -and $Existing.Plan.OU_Destination -ieq $Plan.OU_Destination)
}

function Confirm-PestoInterventionObservation {
    param([string]$OperationId,$Observation)
    if($script:PestoReadOnly){throw 'Consultation : observation affichée, reçu non modifié.'}
    $id=[Guid]::Empty
    if(-not [Guid]::TryParse($OperationId,[ref]$id) -or $id -eq [Guid]::Empty){throw 'Identifiant de reçu absent.'}
    $when=[DateTimeOffset]::MinValue
    if(-not [DateTimeOffset]::TryParse([string]$Observation.ObservedUtc,[ref]$when) -or
       ([DateTimeOffset]::UtcNow-$when).TotalSeconds -gt 120 -or ([DateTimeOffset]::UtcNow-$when).TotalSeconds -lt 0){throw 'Relisez l''état avant de le consigner.'}
    $mutex=$null;$owned=$false
    try{
        $mutex=[Threading.Mutex]::new($false,'Global\GP_PostMutation_v1')
        try{$owned=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$owned=$true}
        if(-not $owned){throw 'Une mutation est encore active. Aucune vérification appliquée.'}
        $r=Read-PestoIntervention (Join-Path (Get-PestoInterventionRoot) ($id.ToString('N')+'.json'))
        if($r.Plan.Domain -ine $script:DOMAINE){throw 'Ce reçu appartient à un autre domaine.'}
        if($r.Attributes -or $r.OfflineJoin){throw 'Utiliser AttributeObserve ou OfflineObserve pour relire les effets propres a cette intervention.'}
        $plan=$r.Plan|Select-Object *
        if($r.InitialProtection -is [bool]){$plan|Add-Member -NotePropertyName InitialProtection -NotePropertyValue $r.InitialProtection -Force}
        if(Test-PestoJoinIntervention $r){
            $machine=[string](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid -ErrorAction Stop).MachineGuid
            $decision=Get-PestoJoinObservationDecision -Receipt $r -Observation $Observation -LocalMachineId $machine
        }else{$decision=Get-PestoObservationDecision -Plan $plan -Observation $Observation -TargetMachineId $r.TargetMachineId -PreviousCode $r.ResultCode}
        if(-not $decision.Verified -and -not $decision.ResumeMove){throw $decision.Message}
        if($r.Entra -in @('Requested','Uncertain')){throw 'Retrait Entra non confirmé : examiner le reçu sur la cible avant de poursuivre. Le contrôle des noms seul ne suffit pas.'}
        if(@($r.Tasks|Where-Object{ $_ -and $_.Phase -notin @('Deleted','Finished') }).Count){throw 'Une tâche de cette intervention reste non confirmée terminée. Examinez son nom exact dans Détails avant de lever le verrou.'}
        $snapshot=ConvertTo-PestoObservationSnapshot $Observation
        $r|Add-Member -NotePropertyName LastObservation -NotePropertyValue $snapshot -Force
        if(Test-PestoJoinIntervention $r){$r.JoinEvidence.BoundObjectGuid=$decision.BoundObjectGuid;$r.Schema=3}else{$r.Schema=2}
        $r.Phase=if($decision.Verified){'Verified'}else{'MoveReady'}
        $r.VerifiedUtc=[string]$Observation.ObservedUtc;$r.VerifiedBy=[Security.Principal.WindowsIdentity]::GetCurrent().Name
        $r.UpdatedUtc=[DateTime]::UtcNow.ToString('o');$r.LastStage='Postconditions observed'
        Write-PestoIntervention $r
        if($r.Phase -eq 'Verified'){Exit-PestoCoordination -Receipt $r -Policy (ConvertTo-PestoPolicy $script:CFG.POLICY)}
        return $r
    }finally{if($mutex){try{if($owned){$mutex.ReleaseMutex()}}finally{$mutex.Dispose()}}}
}


function Get-PestoTaskDefinitionHash {
    param([string]$Xml)
    if(-not $Xml -or $Xml.Length -gt 131072){throw 'Définition de tâche absente ou trop volumineuse.'}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Xml)))).Replace('-','')}
    finally{$sha.Dispose()}
}

function Set-PestoTaskEvidence {
    param([string]$Computer,[string]$Name,[ValidateSet('Registering','Registered','StartRequested','Started','Finished','Deleted')][string]$Phase,[string]$DefinitionHash='', $NativeCode=$null)
    if($script:SIM -or $script:GUI -or -not $script:ActiveIntervention){return}
    if(-not(Test-PestoComputerName $Computer) -or $Name -notmatch '^\\Pesto_[A-Za-z0-9_]+$'){throw 'Identité de tâche invalide.'}
    $r=$script:ActiveIntervention
    if(-not $r.PSObject.Properties['Tasks']){$r|Add-Member -NotePropertyName Tasks -NotePropertyValue @()}
    $found=@($r.Tasks|Where-Object{$_.Computer -ieq $Computer -and $_.Name -ceq $Name})
    if($found.Count -gt 1){throw 'Suivi de tâche ambigu.'}
    if($found.Count){$entry=$found[0]}else{
        if(@($r.Tasks).Count -ge 8){throw 'Trop de tâches pour cette intervention.'}
        $entry=[pscustomobject]@{Computer=$Computer;Name=$Name;Phase=$Phase;Hash='';NativeCode=$null;Utc=''}
        $r.Tasks=@($r.Tasks)+@($entry)
    }
    $entry.Phase=$Phase;$entry.Utc=[DateTime]::UtcNow.ToString('o')
    if($DefinitionHash){$entry.Hash=$DefinitionHash}
    if($null -ne $NativeCode){$entry.NativeCode=[long]$NativeCode}
    $r.UpdatedUtc=$entry.Utc;$r.LastStage='Task: '+$Name+' / '+$Phase
    Write-PestoIntervention $r
}

function Assert-PestoTaskDefinition {
    param([string]$Computer,[string]$Name,$Task)
    if(-not $script:ActiveIntervention){return}
    $entry=@($script:ActiveIntervention.Tasks|Where-Object{$_.Computer -ieq $Computer -and $_.Name -ceq $Name})
    if($entry.Count -ne 1 -or -not $entry[0].Hash -or
        (Get-PestoTaskDefinitionHash ([string]$Task.Xml)) -cne $entry[0].Hash){
        throw 'La définition de la tâche ne correspond pas au reçu. Aucun lancement ni nettoyage automatique.'
    }
}


function Add-PestoInterventionEvent {
    param($Receipt,[string]$Stage,[string]$State)
    $sequence=if($Receipt.PSObject.Properties['Sequence']){[long]$Receipt.Sequence}else{0}
    $events=@($Receipt.Timeline|Where-Object{$null -ne $_}|Select-Object -Last 95)
    $sequence++
    $pestoEvent=[pscustomobject]@{Sequence=$sequence;Utc=[DateTime]::UtcNow.ToString('o');Stage=$Stage;State=$State}
    $Receipt|Add-Member -NotePropertyName Sequence -NotePropertyValue $sequence -Force
    $Receipt|Add-Member -NotePropertyName Timeline -NotePropertyValue @($events+@($pestoEvent)) -Force
}


function Write-PestoReconciliationAudit {
    param([Parameter(Mandatory=$true)]$Receipt,
          [ValidateSet('TaskRead','Protection','Cleanup')][string]$Action,
          [ValidateSet('Requested','Confirmed','Unknown','Ready','NoDefinition','Empty')][string]$State,
          [ValidateRange(0,8)][int]$TaskIndex=0,[Nullable[long]]$NativeCode=$null)
    if($NativeCode -and ($NativeCode -lt [int]::MinValue -or $NativeCode -gt [uint32]::MaxValue)){throw 'Code de tâche hors limites.'}
    $detail='Action='+$Action+';State='+$State+';TaskIndex='+$TaskIndex
    if($null -ne $NativeCode){$detail+=';NativeCode='+$NativeCode.ToString([Globalization.CultureInfo]::InvariantCulture)}
    Add-PestoInterventionEvent -Receipt $Receipt -Stage 'Reconciliation' -State $detail
    $Receipt.UpdatedUtc=[DateTime]::UtcNow.ToString('o')
    Write-PestoIntervention $Receipt
}

function Set-PestoInitialObservation {
    param([Parameter(Mandatory=$true)]$Observation)
    if($script:SIM -or $script:GUI){return}
    $r=$script:ActiveIntervention
    if(-not $r){throw 'Reçu absent avant observation initiale.'}
    $snapshot=ConvertTo-PestoObservationSnapshot $Observation
    if(-not $snapshot.AD -or $snapshot.AD.Guid -ine $r.Plan.Objet_GUID){throw 'La lecture initiale ne correspond pas à l’’identité AD du plan.'}
    if($r.Baseline){
        if($r.Baseline.AD.Guid -ine $snapshot.AD.Guid){throw 'Identité initiale différente.'}
        return # Préserver la lecture d'avant renommage pendant le déplacement qui suit.
    }
    $r|Add-Member -NotePropertyName Baseline -NotePropertyValue $snapshot -Force
    $r.Schema=2
    Add-PestoInterventionEvent -Receipt $r -Stage 'Observation' -State 'Initial'
    Write-PestoIntervention $r
}

function Save-PestoUnverifiedObservation {
    param([string]$OperationId,[string]$ExpectedPlanFingerprint,$Observation)
    if($script:PestoReadOnly -or $script:SIM -or $script:GUI){throw 'Enregistrement de reçu interdit dans ce mode.'}
    $snapshot=ConvertTo-PestoObservationSnapshot $Observation
    $age=([DateTimeOffset]::UtcNow-[DateTimeOffset]::Parse($snapshot.CapturedUtc,[Globalization.CultureInfo]::InvariantCulture)).TotalSeconds
    if($age -lt -5 -or $age -gt 120){throw 'Lecture périmée : relisez le poste avant de la conserver.'}
    $id=[Guid]::Empty
    if(-not [Guid]::TryParse($OperationId,[ref]$id) -or $id -eq [Guid]::Empty){throw 'Identifiant d’’intervention invalide.'}
    $mutex=[Threading.Mutex]::new($false,'Global\GP_PostMutation_v1');$owned=$false
    try{
        try{$owned=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$owned=$true}
        if(-not $owned){throw 'Une mutation travaille encore. La lecture n’’a pas été enregistrée.'}
        $r=Read-PestoIntervention (Join-Path (Get-PestoInterventionRoot) ($id.ToString('N')+'.json'))
        if($r.Plan.Domain -ine $script:DOMAINE -or -not $ExpectedPlanFingerprint -or (Get-PestoPlanFingerprint $r.Plan) -cne $ExpectedPlanFingerprint){throw 'Le plan a changé ou appartient à un autre domaine.'}
        if(Test-PestoJoinIntervention $r){
            if(-not $r.JoinEvidence -or -not $snapshot.Windows -or $snapshot.Windows.MachineId -ine $r.TargetMachineId -or
               -not $snapshot.AD -or $snapshot.AD.Name -ine $r.Plan.Nouveau_Nom -or
               ($r.JoinEvidence.BoundObjectGuid -and $snapshot.AD.Guid -ine $r.JoinEvidence.BoundObjectGuid) -or
               ($r.Plan.Objet_GUID -and $snapshot.AD.Guid -ine $r.Plan.Objet_GUID)){throw 'Identité de jonction non confirmée pour conserver la lecture.'}
        }elseif(-not $snapshot.AD -or $snapshot.AD.Guid -ine $r.Plan.Objet_GUID){throw 'Identité AD de cette lecture non confirmée.'}
        if($snapshot.Windows -and $snapshot.Windows.MachineId -and $r.TargetMachineId -and $snapshot.Windows.MachineId -ine $r.TargetMachineId){throw 'L’’identité Windows ne correspond pas au reçu.'}
        if($r.LastObservation -and [DateTimeOffset]::Parse($r.LastObservation.CapturedUtc) -ge [DateTimeOffset]::Parse($snapshot.CapturedUtc)){throw 'Une lecture aussi récente ou plus récente est déjà conservée.'}
        # Aucun changement de Phase, VerifiedUtc, effets ou coordination.
        $r|Add-Member -NotePropertyName LastObservation -NotePropertyValue $snapshot -Force
        if($r.Schema -lt 2){$r.Schema=2};$r.UpdatedUtc=[DateTime]::UtcNow.ToString('o')
        Add-PestoInterventionEvent -Receipt $r -Stage 'Observation' -State 'RecordedNotResolved'
        Write-PestoIntervention $r
        return $r
    }finally{if($owned){$mutex.ReleaseMutex()};$mutex.Dispose()}
}
