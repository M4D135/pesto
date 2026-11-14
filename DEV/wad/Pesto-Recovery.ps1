#requires -Version 5.1
# Reprise explicite : aucun reçu ne devient vérifié à partir d'un fichier importé.
function ConvertFrom-PestoLegacyState {
    param($Value,[string]$Domain,[string]$MachineId,[string]$SourceHash)
    if(-not $Value -or $Value.Schema -ne 1 -or $SourceHash -notmatch '^[a-fA-F0-9]{64}$'){throw 'État historique non reconnu.'}
    if(-not $Value.PSObject.Properties['Rows'] -and -not $Value.Plan -and $Value.PSObject.Properties['BootUtc']){
        return ConvertFrom-PestoLegacyJoinReceipt -Value $Value -Domain $Domain -MachineId $MachineId -SourceHash $SourceHash
    }
    $rows=@();$origin='' 
    if($Value.PSObject.Properties['Rows']){
        if($Value.Domain -ine $Domain -or $Value.MachineId -ine $MachineId){throw 'Le checkpoint ne correspond pas au domaine et au PC opérateur.'}
        if(@($Value.Rows).Count -gt 5000){throw 'Checkpoint trop volumineux.'}
        $rows=@($Value.Rows);$origin='Queue'
    }elseif($Value.Plan -and $Value.OperatorMachineId -ieq $MachineId -and $Value.Plan.Domain -ieq $Domain){
        $p=$Value.Plan|Select-Object *;$p|Add-Member -NotePropertyName Operation_ID -NotePropertyValue $Value.OperationId -Force;$p|Add-Member -NotePropertyName Code -NotePropertyValue $Value.ResultCode -Force
        $rows=@($p);$origin='Direct'
    }else{throw 'Format ou propriétaire de l''état historique non confirmé. Le fichier est conservé.'}
    $index=0
    foreach($row in $rows){
        $index++
        if($origin -eq 'Queue' -and $row.Statut -notin @('INCERTAIN','TECHNIQUE','PROTECTION','EN COURS','PARTIEL')){continue}
        if($row.Renommer -isnot [bool] -or $row.Deplacer -isnot [bool] -or -not(Test-PestoComputerName ([string]$row.Nom_du_PC))){throw 'Ligne historique non typée.'}
        $guid=[Guid]::Empty
        if(-not [Guid]::TryParse([string]$row.Objet_GUID,[ref]$guid) -or $guid -eq [Guid]::Empty){throw 'Ancienne ligne sans GUID : vérification manuelle nécessaire, aucun GUID deviné.'}
        if($row.Renommer -and -not(Test-PestoGeneratedComputerName ([string]$row.Nouveau_Nom) -Prefix '')){throw 'Nom cible historique invalide.'}
        $id=[Guid]::Empty
        if(-not [Guid]::TryParse([string]$row.Operation_ID,[ref]$id) -or $id -eq [Guid]::Empty){$hash=Get-PestoStableHash ($SourceHash+'|'+$index);$id=[Guid]::Parse($hash.Substring(0,32))}
        $plan=[pscustomobject]@{Nom_du_PC=[string]$row.Nom_du_PC;Nouveau_Nom=[string]$row.Nouveau_Nom;OU_Actuelle=[string]$row.OU_Actuelle;OU_Destination=[string]$row.OU_Destination;Objet_GUID=$guid.ToString('D');Domain=$Domain;DC='';ConfigStamp='';TargetOUGuid='';Renommer=$row.Renommer;Deplacer=$row.Deplacer;Reboot=$false}
        [pscustomobject]@{Schema=1;Version=$script:Pesto_VERSION;OperationId=$id.ToString('N');Plan=$plan;StartedUtc='';UpdatedUtc=[DateTime]::UtcNow.ToString('o');Phase='Uncertain';InitialProtection=$null;TargetMachineId=[string]$row.TargetMachineId;TargetOUGuid='';Entra='Uncertain';Protection='NotChanged';Rename=$(if($row.Renommer){'Requested'}else{'NotRequested'});Move=$(if($row.Deplacer){'Requested'}else{'NotRequested'});ResultCode=97;ResultMessage='Import historique. Aucune réussite ni annulation déduite du fichier.';LastStage='LegacyImported';VerifiedUtc='';VerifiedBy='';ResumeFrom='';Sequence=0;Timeline=@();Legacy=[pscustomobject]@{Kind=$origin;SHA256=$SourceHash;Line=$index}}
    }
}

function Import-PestoLegacyState {
    if($script:PestoReadOnly -or $script:GUI -or $script:SIM){throw 'Import de reçus disponible uniquement dans une session réelle autorisée.'}
    if(Test-PestoQueueWorkerStillActive){throw 'Terminez les opérations actives avant l''import.'}
    $dialog=[Microsoft.Win32.OpenFileDialog]::new();$dialog.Filter='État GP/Pesto (*.json)|*.json'
    if($dialog.ShowDialog($Win) -ne $true){return}
    Assert-PestoPlainPath $dialog.FileName
    $f=Get-Item -LiteralPath $dialog.FileName -ErrorAction Stop
    if($f.Length -gt 16777216){throw 'État trop volumineux.'}
    $text=[IO.File]::ReadAllText($f.FullName,[Text.Encoding]::UTF8)
    $hash=Get-PestoStableHash $text
    $machine=[string](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid -ErrorAction Stop).MachineGuid
    $records=@(ConvertFrom-PestoLegacyState -Value ($text|ConvertFrom-Json -ErrorAction Stop) -Domain $script:DOMAINE -MachineId $machine -SourceHash $hash)
    if(-not $records.Count){Show-MsgInfo 'Aucune intervention incertaine importable dans ce fichier.';return}
    $preview=$records|ForEach-Object{[pscustomobject]@{Poste=$_.Plan.Nom_du_PC;NomPrevu=$_.Plan.Nouveau_Nom;Etat='À vérifier';Id=$_.OperationId}}|Format-Table -AutoSize|Out-String -Width 170
    if(-not(Confirm-YesNo -Msg ($preview+"`nLe fichier d'origine ne sera pas modifié. Aucun ancien verrou ne sera supprimé. Importer ces reçus ?") -Confirm $true)){return}
    $mutex=[Threading.Mutex]::new($false,'Global\GP_PostMutation_v1');$owned=$false
    try{
        try{$owned=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$owned=$true}
        if(-not $owned){throw 'Une opération a démarré : import différé.'}
        $count=0
        foreach($r in $records){
            $path=Join-Path (Get-PestoInterventionRoot) ($r.OperationId+'.json')
            if([IO.File]::Exists($path)){
                $existing=Read-PestoIntervention $path
                if((Test-PestoJoinIntervention $existing) -and (Test-PestoJoinIntervention $r)){
                    if($existing.Plan.Domain -ine $r.Plan.Domain -or $existing.Plan.Nom_du_PC -ine $r.Plan.Nom_du_PC -or
                       $existing.Plan.Nouveau_Nom -ine $r.Plan.Nouveau_Nom -or $existing.Plan.OU_Destination -ine $r.Plan.OU_Destination -or
                       $existing.TargetMachineId -ine $r.TargetMachineId){throw 'Conflit de jonction historique : aucun remplacement.'}
                    if(-not $existing.JoinEvidence -and $existing.Phase -notin @('Verified','Failed')){
                        $r.JoinEvidence.BoundObjectGuid=[string]$existing.Plan.Objet_GUID
                        $existing|Add-Member -NotePropertyName JoinEvidence -NotePropertyValue $r.JoinEvidence
                        $existing.Schema=3;$existing.UpdatedUtc=[DateTime]::UtcNow.ToString('o')
                        Add-PestoInterventionEvent $existing 'LegacyJoinImported' 'UnverifiedEvidence'
                        Write-PestoIntervention $existing;$count++
                    }
                }elseif($existing.Plan.Nom_du_PC -ine $r.Plan.Nom_du_PC -or $existing.Plan.Objet_GUID -ine $r.Plan.Objet_GUID){throw 'Conflit d''identifiant historique. Aucun remplacement.'}
                continue
            }
            Write-PestoIntervention $r;$count++
        }
        Show-MsgInfo ("$count reçus importés. Les verrous et fichiers historiques restent conservés. Vérifiez les interventions une par une.")
    }finally{if($owned){$mutex.ReleaseMutex()};$mutex.Dispose()}
}

function Invoke-PestoRecoveryWorker {
    param($Request,$Source)
    $ErrorActionPreference='Stop';Set-StrictMode -Off
    . ([scriptblock]::Create($Source))
    function Write-Log {param($Message,$Level,$ErrorRecord,$Context);Publish-PestoWorkerLog -Text ([string]$Message) -Level $Level -Context $Context}
    $script:PestoQueueMonitor=$Request.Monitor;$script:GUI=$false;$script:SIM=$false;$script:cred=$Request.Credential;$script:DOMAINE=$Request.Domain;$script:DC=$Request.DC;$script:PestoPolicy=$Request.Policy
    if($Request.ReadOnly -or $env:PESTO_READONLY_SESSION -eq '1'){throw 'Consultation : réparation interdite.'}
    $mutex=$null;$owned=$false;$r=$null
    try{
        $mutex=[Threading.Mutex]::new($false,'Global\GP_PostMutation_v1')
        try{$owned=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$owned=$true}
        if(-not $owned){throw 'Une autre mutation est active.'}
        $id=[Guid]::Parse($Request.OperationId)
        $r=Read-PestoIntervention (Join-Path (Get-PestoInterventionRoot) ($id.ToString('N')+'.json'))
        if($r.Plan.Domain -ine $Request.Domain -or (Get-PestoStableHash $r) -cne $Request.ExpectedHash){throw 'Le reçu a changé depuis sa confirmation.'}
        if(-not $r.Plan.Objet_GUID){throw 'Identité AD non conservée : réparation guidée indisponible.'}
        Import-PestoADModule $Request.ADModulePath
        Assert-PestoOperationPolicy -Plan $r.Plan -Policy $Request.Policy
        $script:ActiveIntervention=$r
        Write-PestoReconciliationAudit $r $Request.Action Requested
        $taskResults=@()
        foreach($task in @($r.Tasks)){
            if(-not $task -or $task.Phase -eq 'Deleted'){continue}
            $probe=Get-PestoTaskRunResult -TaskName $task.Name -Transport @('/s',$task.Computer) -TimeoutSec 8
            if(-not $probe -or $probe.State -ne 'READY'){throw 'Une tâche reste active ou inconnue. Aucune réparation ni suppression.'}
            $taskResults+=,$task
        }
        if($Request.Action -eq 'Protection'){
            # Un résultat final de protection échouée autorise cette réparation ciblée.
            # Un crash sans résultat connu reste un cas à examiner, pas à deviner.
            if($r.ResultCode -ne 32 -or $r.InitialProtection -isnot [bool]){throw 'Restauration automatique limitée aux échecs de protection documentés (code 32). Après crash sans preuve, vérifiez manuellement.'}
            $adp=Get-ADParams;$pc=Get-ADComputer -Identity ([Guid]$r.Plan.Objet_GUID) -Properties ProtectedFromAccidentalDeletion,DistinguishedName -ErrorAction Stop @adp
            $currentOU=Get-PestoParentDN $pc.DistinguishedName
            if($currentOU -notin @($r.Plan.OU_Actuelle,$r.Plan.OU_Destination)){throw 'Emplacement inattendu : réparation refusée.'}
            $expectedName=if($r.Rename -eq 'Confirmed'){$r.Plan.Nouveau_Nom}else{$r.Plan.Nom_du_PC}
            if($pc.Name -ine $expectedName){throw 'Nom de l''objet différent du reçu.'}
            if([bool]$pc.ProtectedFromAccidentalDeletion -ne $r.InitialProtection){
                Set-PestoEffect Protection 'Restoring'
                Assert-PestoWorkerMayContinue -Mutation
                Set-ADObject -Identity ([Guid]$r.Plan.Objet_GUID) -ProtectedFromAccidentalDeletion $r.InitialProtection -ErrorAction Stop @adp
            }
            $after=Get-ADComputer -Identity ([Guid]$r.Plan.Objet_GUID) -Properties ProtectedFromAccidentalDeletion -ErrorAction Stop @adp
            if($after.ProtectedFromAccidentalDeletion -isnot [bool] -or $after.ProtectedFromAccidentalDeletion -ne $r.InitialProtection){throw 'Protection non confirmée après réparation.'}
            Set-PestoEffect Protection 'Restored'
            Write-PestoReconciliationAudit $r Protection Confirmed
            return [pscustomobject]@{Message='Protection initiale rétablie et relue. Le reste de l''intervention doit encore être vérifié.';OperationId=$r.OperationId}
        }
        if($Request.Action -ne 'Cleanup'){throw 'Action de reprise non autorisée.'}
        $count=0
        foreach($task in $taskResults){
            if(-not $r.TargetMachineId){throw 'Identité Windows initiale inconnue : aucune tâche supprimée.'}
            $observation=Get-PestoPostObservation ([pscustomobject]@{Computer=$task.Computer;AlternativeComputer='';ObjectGuid=$r.Plan.Objet_GUID;LocalSource=($task.Computer -ieq $env:COMPUTERNAME);Domain=$Request.Domain;DC=$Request.DC;Credential=$Request.Credential;ADModulePath=$Request.ADModulePath})
            if(-not $observation.Windows -or $observation.Windows.MachineId -ine $r.TargetMachineId){throw 'La cible de la tâche n''est pas confirmée.'}
            Assert-PestoWorkerMayContinue -Mutation
            $result=Invoke-PestoSchtasks -ArgList @('/delete','/s',$task.Computer,'/tn',$task.Name,'/f')
            if($result.ExitCode -ne 0){throw ('Nettoyage non confirmé : '+$task.Name)}
            # L'API n'autorise pas la suppression de la définition modifiée ou active.
            $count++
        }
        Write-PestoReconciliationAudit $r Cleanup Confirmed
        return [pscustomobject]@{Message=("$count tâches exactes supprimées. Aucun script distant exécuté, aucun reçu ni verrou supprimé.");OperationId=$r.OperationId}
    }catch{
        if($r -and $script:ActiveIntervention){try{Write-PestoReconciliationAudit $r $Request.Action Unknown}catch{}}
        throw
    }finally{$script:ActiveIntervention=$null;$script:cred=$null;if($mutex){if($owned){$mutex.ReleaseMutex()};$mutex.Dispose()}}
}

function Start-PestoRecovery {
    param($Receipt,[ValidateSet('Protection','Cleanup')][string]$Action)
    if($script:PestoReadOnly -or $script:GUI -or $script:SIM){throw 'Action réelle indisponible dans ce mode.'}
    if(Test-PestoQueueWorkerStillActive){throw 'Une opération est encore active.'}
    $ui=$script:InterventionsUi
    $text=if($Action -eq 'Protection'){'Rétablir exclusivement la valeur initiale de protection enregistrée. Aucun renommage ni déplacement.'}else{'Supprimer uniquement les tâches exactes terminées, dont la définition et la machine sont confirmées. Aucune tâche active supprimée.'}
    if(-not(Confirm-YesNo -Msg ($Receipt.Plan.Nom_du_PC+"`n`n"+$text) -Confirm $true)){return}
    if(-not(Test-PestoAuditWritable)){throw 'Audit indisponible.'}
    $req=[pscustomobject]@{Action=$Action;OperationId=$Receipt.OperationId;ExpectedHash=(Get-PestoStableHash $Receipt);ReadOnly=[bool]$script:PestoReadOnly;Domain=$script:DOMAINE;DC=$script:DC;Credential=$script:cred;Policy=(ConvertTo-PestoPolicy $script:CFG.POLICY);ADModulePath=(Join-Path $BasePath 'ActiveDirectory.psd1');Monitor=(New-PestoQueueMonitor -Computer $Receipt.Plan.Nom_du_PC)}
    $script:RecoveryBusy=$true
    if($ui){$ui.Hint.Text='Reprise contrôlée en cours. Les autres mutations restent bloquées.'}
    try{
        $started=Start-PestoAsyncOperation -Name 'RecoveryAction' -ScriptBlock ${function:Invoke-PestoRecoveryWorker} -ArgumentList @($req,(Get-PestoWorkerCoreSource)) -ApartmentState STA -QueueMonitor $req.Monitor -TimeoutSec 180 -CallbackContext $ui -OnSuccess ${function:Complete-PestoRecovery} -OnError ${function:Fail-PestoRecovery}
        if(-not $started){throw 'Worker de reprise non créé. Aucune action de reprise lancée.'}
    }catch{$script:RecoveryBusy=Test-PestoAsyncOperationRunning 'RecoveryAction';throw}
}
function Complete-PestoRecovery {
    param($Result,$Context)
    $script:RecoveryBusy=$false
    if($Context -and [object]::ReferenceEquals($Context,$script:InterventionsUi)){Update-PestoInterventions;$Context.Hint.Text=[string]$Result.Message}
    Add-LogLine ([string]$Result.Message) 'info'
}
function Fail-PestoRecovery {
    param($Failure,$Context)
    $script:RecoveryBusy=Test-PestoAsyncOperationRunning 'RecoveryAction'
    $message='Reprise non confirmée : '+(Protect-PestoLogText ([string]$Failure))+'. Relire le reçu et la cible.'
    if($Context -and [object]::ReferenceEquals($Context,$script:InterventionsUi)){$Context.Hint.Text=$message}
    Add-LogLine $message 'err'
}
