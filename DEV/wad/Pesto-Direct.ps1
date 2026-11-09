#requires -Version 5.1
# Compatibilité : les clés de stockage/verrous GP sont stables ; ne pas les renommer ni les effacer. Voir docs/RENOMMAGE_PESTO.md (DEV).
# Parcours unitaire : plan immutable, contrôle, confirmation et worker partagé.
# Aucune DataRow n'est insérée dans la file par ce composant.

function Get-PestoDirectStatePath {
    $base=[Environment]::GetFolderPath('CommonApplicationData')
    if(-not $base){throw 'ProgramData introuvable.'}
    return [IO.Path]::Combine($base,'GP','Operations','direct.json')
}

function Read-PestoDirectReceipt {
    param([string]$Path)
    $ancestor=[IO.Path]::GetDirectoryName($Path)
    while($ancestor){
        if(Test-Path -LiteralPath $ancestor){
            if((Get-Item -LiteralPath $ancestor -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Le stockage de l''opération traverse un lien ou une jonction.'}
        }
        $next=[IO.Path]::GetDirectoryName($ancestor);if($next -eq $ancestor){break};$ancestor=$next
    }
    if(-not(Test-Path -LiteralPath $Path)){return $null}
    $file=Get-Item -LiteralPath $Path -ErrorAction Stop
    if($file.PSIsContainer -or $file.Length -gt 65536 -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Reçu d''opération invalide.'}
    $r=Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop
    $id=[Guid]::Empty;$guid=[Guid]::Empty
    if($r.Schema -ne 1 -or $r.Phase -notin @('Running','PendingRestart','Partial','Protection','Uncertain','Failed','NotStarted','Verified') -or
        -not [Guid]::TryParse([string]$r.OperationId,[ref]$id) -or $id -eq [Guid]::Empty -or -not $r.OperatorMachineId -or
        -not $r.Plan -or -not(Test-PestoComputerName ([string]$r.Plan.Nom_du_PC)) -or
        -not [Guid]::TryParse([string]$r.Plan.Objet_GUID,[ref]$guid) -or $guid -eq [Guid]::Empty -or
        -not (Test-PestoDnsName ([string]$r.Plan.Domain))){throw 'Reçu d''opération incomplet. Aucune relance automatique.'}
    if($r.Metadata){[void](ConvertTo-PestoDeploymentMetadata $r.Metadata -LegacyReceipt)}
    # Acquittement (15/10) : un objet altéré rend le reçu invalide, donc bloquant.
    if($r.PSObject.Properties['Acknowledged'] -and $null -ne $r.Acknowledged){[void](Assert-PestoAcknowledgement $r.Acknowledged)}
    return $r
}

function Write-PestoDirectReceipt {
    param([string]$Path,$Receipt)
    $json=$Receipt|ConvertTo-Json -Depth 8
    if([Text.Encoding]::UTF8.GetByteCount($json) -gt 65536){throw 'Reçu trop volumineux.'}
    # Même stockage restreint et même écriture atomique que le reçu de jonction.
    Write-PestoJoinReceipt -Path $Path -Receipt $Receipt
}

function Get-PestoDirectPhase {
    param([int]$Code,[bool]$Rename,[bool]$TimedOut)
    if($TimedOut -or $Code -in @(97,98,99)){return 'Uncertain'}
    if($Code -eq 96){return 'NotStarted'}
    if($Code -eq 89){return 'Partial'}
    if($Code -eq 32){return 'Protection'}
    if($Code -in @(20,77) -and $Rename){return 'PendingRestart'}
    if($Code -in @(30,33)){return 'Verified'}
    return 'Failed'
}

function Test-PestoDirectResumePlan {
    param($Old,$Plan,[string]$ResumeId)
    if(-not $Old -or $Old.Phase -ne 'Partial' -or $ResumeId -ne $Old.OperationId){return $false}
    if($Plan.Renommer -or -not $Plan.Deplacer -or $Plan.Reboot){return $false}
    return ($Plan.Nom_du_PC -ieq $Old.Plan.Nouveau_Nom -and $Plan.Objet_GUID -ieq $Old.Plan.Objet_GUID -and
        $Plan.Domain -ieq $Old.Plan.Domain -and $Plan.OU_Destination -ieq $Old.Plan.OU_Destination)
}

function Get-PestoDirectSupportSource {
    $names=@('Write-PestoAtomicText','Write-PestoJoinReceipt','Invoke-PestoAuditSinkReceipt','Get-PestoDirectStatePath','Read-PestoDirectReceipt','Write-PestoDirectReceipt','Get-PestoDirectPhase','Test-PestoDirectResumePlan','Test-PestoComputerName','Test-PestoDnsName','Protect-PestoLogText')
    $sb=[Text.StringBuilder]::new()
    foreach($n in $names){$cmd=Get-Command $n -CommandType Function -ErrorAction Stop;[void]$sb.AppendLine("function $n {");[void]$sb.AppendLine($cmd.Definition);[void]$sb.AppendLine('}')}
    return $sb.ToString()
}

$script:PestoDirectWorker={
    param($Request,$CoreSource,$ActionBody,$SupportSource)
    Set-StrictMode -Off;$ErrorActionPreference='Stop'
    . ([scriptblock]::Create($SupportSource))
    . ([scriptblock]::Create($CoreSource))
    $script:PestoPolicy=$Request.Policy;$script:PestoQueueMonitor=$Request.Telemetry
    function Write-Log {param($Message,$Level='INFO',$ErrorRecord,$Context='AuditSink');Publish-PestoWorkerLog -Text ([string]$Message) -Level $Level -Context $Context}
    $mutex=$null;$owned=$false;$receipt=$null;$path='';$storageConfirmed=$false;$old=$null
    try {
        $operationGuid=[Guid]::Empty
        if(-not [Guid]::TryParse([string]$Request.OperationId,[ref]$operationGuid) -or $operationGuid -eq [Guid]::Empty){throw 'Identifiant opération invalide. Aucune commande lancée.'}
        if(-not $Request.SIM){
            $mutex=[Threading.Mutex]::new($false,'Global\GP_PostMutation_v1')
            try{$owned=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$owned=$true}
            if(-not $owned){throw 'Une autre opération Pesto est active sur ce poste. Aucune commande lancée.'}
            $path=Get-PestoDirectStatePath
            $old=Read-PestoDirectReceipt $path
            $storageConfirmed=$true
            $machine=[string](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid -ErrorAction Stop).MachineGuid
            if(-not $machine){throw 'Identité locale non confirmée.'}
            if($old -and $old.OperatorMachineId -ine $machine){throw 'Reçu unitaire provenant d''un autre poste. Vérification manuelle requise.'}
            if($old -and $old.Phase -notin @('Failed','NotStarted','Verified') -and -not(Test-PestoOptionalPostCheckReceipt $old) -and -not(Test-PestoAcknowledgedReceipt $old)){
                if(-not(Test-PestoDirectResumePlan -Old $old -Plan $Request.Plan -ResumeId $Request.ResumeId)){
                    $linkedPath=Join-Path (Get-PestoInterventionRoot) (([Guid]$old.OperationId).ToString('N')+'.json')
                    $linked=if([IO.File]::Exists($linkedPath)){Read-PestoIntervention $linkedPath}else{$null}
                    if(-not $linked -or (Test-PestoInterventionConflict $linked $Request.Plan)){
                        throw 'Une opération précédente concerne cette cible ou un reçu historique non rattaché. Vérification requise.'
                    }
                }
            }
            if($old){
                $archive=[IO.Path]::Combine([IO.Path]::GetDirectoryName($path),'archive',([Guid]$old.OperationId).ToString('N')+'.json')
                Write-PestoDirectReceipt -Path $archive -Receipt $old
            }
            $receipt=[pscustomobject]@{
                Schema=1;Version=[string]$Request.Version;OperationId=[string]$Request.OperationId
                OperatorMachineId=$machine;LocalSource=[bool]$Request.LocalSource
                TargetMachineId=$(if($Request.LocalSource){$machine}else{[string]$Request.TargetMachineId})
                Phase='Running';StartedUtc=[DateTime]::UtcNow.ToString('o');FinishedUtc='';ObservedUtc=''
                Plan=$Request.Plan;ResultCode=0;ResultMessage='En attente du retour du moteur.';ResumeFrom=[string]$Request.ResumeId
            }
            if($Request.Metadata){$receipt|Add-Member NoteProperty Metadata (ConvertTo-PestoDeploymentMetadata $Request.Metadata)}
            Write-PestoDirectReceipt -Path $path -Receipt $receipt
        }
        # Le même moteur Go/Rename/Move que les lots, sans table ni pompe de file.
        $raw=@(& ([scriptblock]::Create([string]$ActionBody)) $Request $CoreSource)
        if($raw.Count -ne 1 -or -not $raw[0].Action -or -not $raw[0].Action.PSObject.Properties['ExitCode']){
            throw 'Résultat moteur absent ou ambigu.'
        }
        $worker=$raw[0]
        if($receipt){
            if($worker.Action.ExitCode -isnot [int]){throw 'Code de résultat non typé.'}
            $code=$worker.Action.ExitCode
            if($worker.Action.TargetMachineId){$receipt.TargetMachineId=[string]$worker.Action.TargetMachineId}
            if($worker.Action.ObjectGuid){$receipt.Plan.Objet_GUID=[string]$worker.Action.ObjectGuid}
            if($worker.Action.InitialProtection -is [bool]){$receipt.Plan|Add-Member -NotePropertyName InitialProtection -NotePropertyValue $worker.Action.InitialProtection -Force}
            $receipt.ResultCode=$code;$receipt.ResultMessage=Protect-PestoLogText ([string]$worker.Action.ExitMsg)
            if($receipt.ResultMessage.Length -gt 12000){$receipt.ResultMessage=$receipt.ResultMessage.Substring(0,12000)+' [tronqué]'}
            $receipt.Phase=Get-PestoDirectPhase -Code $code -Rename ([bool]$Request.Rename) -TimedOut ([bool]$Request.Telemetry.TimedOut)
            $receipt.FinishedUtc=[DateTime]::UtcNow.ToString('o')
            Write-PestoDirectReceipt -Path $path -Receipt $receipt
        }
        return [pscustomobject]@{Action=$worker.Action;Reboot=$worker.Reboot;Logs=$worker.Logs;Receipt=$receipt}
    }catch{
        $code=if($Request.Telemetry.MutationStarted -or (-not $Request.SIM -and -not $storageConfirmed -and $owned)){97}else{96}
        $message=Protect-PestoLogText $_.Exception.Message
        if($receipt){
            $receipt.ResultCode=$code;$receipt.ResultMessage=$message
            try{
                $centralPath=Join-Path (Get-PestoInterventionRoot) ($operationGuid.ToString('N')+'.json')
                if(Test-Path -LiteralPath $centralPath -ErrorAction Stop){$code=97}
            }catch{$code=97;$message+=' Le suivi central n''a pas pu être relu.'}
            $receipt.ResultCode=$code
            $receipt.Phase=if($code -eq 97){'Uncertain'}else{'NotStarted'}
            $receipt.FinishedUtc=[DateTime]::UtcNow.ToString('o')
            try{Write-PestoDirectReceipt -Path $path -Receipt $receipt}catch{$code=97;$message+=' Le résultat local n''a pas pu être enregistré. Vérifier avant toute reprise.';$receipt.Phase='Uncertain'}
        }
        return [pscustomobject]@{Action=[pscustomobject]@{ExitCode=$code;ExitMsg=$message};Reboot=$null;Logs=@();Receipt=$receipt}
    }finally{
        if($mutex){try{if($owned){$mutex.ReleaseMutex()}}finally{$mutex.Dispose()}}
    }
}

function Get-PestoDirectFormPlan {
    if($script:DirectResumePlan){return $script:DirectResumePlan}
    $computer=([string]$TxtPCName.Text).Trim().ToUpperInvariant()
    $new=([string]$CbName.SelectedItem).Trim().ToUpperInvariant()
    $decision=Get-PestoRenameMoveDecision -Computer $computer -NewName $new -CurrentOU ([string]$script:OU_ACTUELLE) -TargetOU ([string]$script:OU_FINAL) -Rename ([bool]$ChkRename.IsChecked) -Move ([bool]$ChkMove.IsChecked) -InDomain ([bool]$script:INDOMAIN)
    if(-not $decision.Valid){throw $decision.Error}
    $id='';$machine=''
    if($script:ComputerIndex -and $script:ComputerIndex.ContainsKey($computer)){$id=[string]$script:ComputerIndex[$computer].ObjectGUID}
    if($computer -ieq $env:COMPUTERNAME){$machine=[string]$script:HostMachineId}
    elseif($script:LastPostObservation -and $script:LastPostObservation.AD.Name -ieq $computer -and $script:LastPostObservation.AD.Guid -ieq $id){$machine=[string]$script:LastPostObservation.Windows.MachineId}
    [pscustomobject]@{
        Nom_du_PC=$computer;Nouveau_Nom=$new;OU_Actuelle=[string]$script:OU_ACTUELLE;OU_Destination=[string]$script:OU_FINAL
        Renommer=[bool]$ChkRename.IsChecked;Deplacer=[bool]$decision.Move;Reboot=$false;Objet_GUID=$id
        Domain=[string]$script:DOMAINE;TargetMachineId=$machine;ConfigStamp=(Get-PestoConfigurationSignature $script:CFG)
    }
}

function Get-PestoDirectPlanErrors {
    param($Plan)
    $errors=[Collections.Generic.List[string]]::new()
    if(-not $script:INDOMAIN){$errors.Add("Utilisez $(Get-PestoUxNom 'PageJonction') pour joindre ce PC.");return $errors.ToArray()}
    foreach($e in @(Test-QueueRowSafe -Nom $Plan.Nom_du_PC -NewName $Plan.Nouveau_Nom -OU $Plan.OU_Destination -Ren $Plan.Renommer -Move $Plan.Deplacer)){$errors.Add($e)}
    if(-not(Test-PestoOUPath ([string]$Plan.OU_Actuelle))){
        # La démonstration n'a pas de DN lu. Les tags du nom restent la règle, et la confirmation s'affiche quand même.
        if(-not(($script:GUI -or $script:SIM) -and [string]$Plan.OU_Actuelle -eq '(mode GUI)')){$errors.Add('Lisez le poste pour confirmer son emplacement actuel.')}
    }
    if(-not $Plan.Renommer -and -not $Plan.Deplacer){$errors.Add('Aucune modification demandée.')}
    if($script:table){
        foreach($r in $script:table.Rows){
            if($r.Nom_du_PC -ieq $Plan.Nom_du_PC -or ($Plan.Renommer -and $r.Renommer -and $r.Nouveau_Nom -ieq $Plan.Nouveau_Nom)){
                $errors.Add('Ce poste ou ce nom cible possède déjà une ligne dans la file. Utilisez cette ligne ou retirez-la explicitement, sans la rejouer.');break
            }
        }
    }
    if(-not($script:GUI -or $script:SIM)){
        if(-not $script:PestoReadOnly -and -not(Test-PestoIsAdministrator)){$errors.Add('Le processus n''est pas élevé. Relancez Pesto pour accepter l''UAC avant la connexion.')}
        $reason=Get-PestoExplicitCredentialRequirement -InDomain $true -Rows @($Plan) -LocalComputerName $env:COMPUTERNAME
        if($reason -and $script:cred -isnot [Management.Automation.PSCredential]){$errors.Add($reason+' Choisissez volontairement le parcours Pesto.exe -AskCredential ; aucun mot de passe ne sera demandé au milieu de cette action.')}
    }
    return $errors.ToArray()
}

function Set-PestoDirectBusy {
    param([bool]$Busy)
    $script:DirectBusy=$Busy
    # Empêche toute écriture parallèle depuis un autre parcours de cette instance.
    $ConfigPanel.IsEnabled=-not $Busy
    $CbOrg.IsEnabled=-not $Busy
    Update-QueueButtons;Update-AddButton
    if($script:JoinUI){Update-PestoJoinUI}
    Update-PestoSuiteUI
}

function Start-PestoDirectPreflight {
    param([switch]$Execute,[switch]$Auto)
    if($script:DirectBusy -or $script:Running -or $script:PreflightRunning -or $script:JoinBusy){return}
    if($script:CfgRestartRequired -or (Test-PestoGlobalSafetyBarrier) -or $script:JoinLocked){Show-MsgWarning 'Un changement de contexte ou une opération précédente doit être vérifié avant de continuer.';return}
    if((Test-PestoDirectTargetBarrier ([string]$TxtPCName.Text)) -and -not $script:DirectResumePlan){Show-PestoPostState -Mode Direct;return}
    if(Test-PestoAsyncOperationRunning 'DirectoryRefresh'){Show-MsgInfo 'L''inventaire est en cours de lecture. Patientez avant de contrôler ce plan.';return}
    try{
        $plan=Get-PestoDirectFormPlan
        $errors=@(Get-PestoDirectPlanErrors $plan)
        if($errors.Count){throw ($errors -join "`n")}
    }catch{
        $script:DirectMessage='Action non lancée.';$script:DirectAdvice=Protect-PestoLogText $_.Exception.Message
        Update-PestoSuiteUI
        if(-not $script:OU_ACTUELLE){[void]$TxtPCName.Focus()}elseif(-not $CbSite.SelectedItem){[void]$CbSite.Focus()}elseif(-not $CbService.Text){[void]$CbService.Focus()}else{[void]$CbName.Focus()}
        return
    }
    # Un clic du technicien repart de zéro ; seules les relances automatiques s'additionnent.
    if(-not $Auto){$script:DirectAutoNext=0}
    $key=Get-PestoPlanSignature $plan
    $item=[pscustomobject]@{Key=$key;Nom_du_PC=$plan.Nom_du_PC;Nouveau_Nom=$plan.Nouveau_Nom;OU_Actuelle=$plan.OU_Actuelle;OU_Destination=$plan.OU_Destination;Objet_GUID=$plan.Objet_GUID;Renommer=$plan.Renommer;Deplacer=$plan.Deplacer;Reboot=$false}
    $script:DirectGeneration=[int]$script:DirectGeneration+1
    $context=[pscustomobject]@{Generation=$script:DirectGeneration;Plan=$plan;Key=$key;Execute=[bool]$Execute}
    $script:DirectMessage='Contrôle du plan dans AD…';$script:DirectAdvice='Aucune mutation. L''identité, le nom et l''OU sont relus avant confirmation.'
    $script:DirectMonitor=$null;Set-PestoDirectBusy $true
    if($script:GUI){
        $id=if($plan.Objet_GUID){$plan.Objet_GUID}else{'11111111-1111-1111-1111-111111111111'}
        Complete-PestoDirectPreflight -Result ([pscustomobject]@{Results=@([pscustomobject]@{Key=$key;State='DÉMO';Detail='Démonstration, aucun accès AD.';Guid=$id;ObservedOU=$plan.OU_Actuelle;Utc=[DateTime]::UtcNow.ToString('o')})}) -Context $context
        return
    }
    $ou=@{};foreach($k in $script:OU.Keys){$ou[$k]=$script:OU[$k]};$ouv=@{};foreach($k in $script:OUV.Keys){$ouv[$k]=$script:OUV[$k]}
    $request=[pscustomobject]@{Items=@($item);DC=$script:DC;Domain=$script:DOMAINE;Credential=$script:cred;InDomain=$true;Prefix=$script:PREFIXE;PRD=[bool]$script:PRD;OU=$ou;OUSite=$ouv;ClearProtection=[bool]$script:CLEAR_PROTECTION;EntraPolicy=[string](@($script:CFG.CONF)[0].EntraPolicy);AllowPasswordTaskFallback=(ConvertTo-PestoPolicy $script:CFG.POLICY).AllowPasswordTaskFallback;Host=$env:COMPUTERNAME;ADModulePath=(Join-Path $BasePath 'ActiveDirectory.psd1');Progress=(New-PestoPreflightProgress -Total 1)}
    try{
        $started=Start-PestoAsyncOperation -Name 'DirectPreflight' -ScriptBlock $script:PestoPreflightWorker -ArgumentList @($request,(Get-PestoPreflightSource)) -TimeoutSec 120 -CallbackContext $context `
            -OnSuccess {param($r,$c) Complete-PestoDirectPreflight -Result $r -Context $c} `
            -OnError {param($e,$c) Complete-PestoDirectPreflight -Failure $e -Context $c}
        if(-not $started){throw 'Contrôle non lancé.'}
    }catch{Complete-PestoDirectPreflight -Failure $_ -Context $context}
    Update-PestoSuiteUI
}

function Stop-PestoDirectPreflight {
    if(-not(Test-PestoAsyncOperationRunning 'DirectPreflight')){return}
    $script:DirectGeneration++
    Stop-PestoAsyncOperation 'DirectPreflight'
    $script:DirectMessage='Contrôle annulé. Aucune commande de modification lancée.';$script:DirectAdvice='Le plan doit être contrôlé à nouveau avant toute exécution.'
    Set-PestoDirectBusy $false
}

function Select-PestoDirectNextName {
    <# Nom cible pris dans l'AD (souvent par un autre poste du banc) : écarté pour la session, nom libre suivant
       sélectionné et annoncé ; il est revérifié dans l'AD et le technicien confirme toujours. Au plus 5 bascules d'affilée. #>
    param([string]$TakenName,[string]$Reason,[switch]$RegistryHeld)
    if(-not $TakenName){return $false}
    if(-not $script:PestoTakenNames){$script:PestoTakenNames=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)}
    # Réservé au registre seulement : écarté tant que la réservation dure (Test-PestoNameReservedByOther), pas pour la session.
    if(-not $RegistryHeld){[void]$script:PestoTakenNames.Add($TakenName)}
    $script:DirectAutoNext=[int]$script:DirectAutoNext+1
    if($script:DirectAutoNext -gt 5){
        $script:DirectMessage='Plusieurs noms déjà pris.'
        $script:DirectAdvice="$TakenName $Reason Cinq noms de suite étaient pris : actualisez l'inventaire (Noms disponibles) puis choisissez un nom."
        return $false
    }
    Update-NameList
    $next=[string]$CbName.SelectedItem
    if(-not $next -or $next -ieq $TakenName){return $false}
    $script:DirectMessage=if($RegistryHeld){'Nom réservé par un autre poste : nom suivant proposé.'}else{'Nom déjà pris : nom suivant proposé.'}
    $how=if((Get-PestoSharedNameSettings).Random){'numéro tiré au hasard parmi tous les libres de la série'}else{'premier numéro libre de la série dans l''AD'}
    $script:DirectAdvice="$TakenName $Reason`nNom suivant proposé : $next, $how. Il est revérifié ; confirmez ensuite."
    Add-LogLine ("RENOMMAGE : $TakenName "+$(if($RegistryHeld){'réservé par un autre poste (registre partagé)'}else{'déjà utilisé dans l''AD'})+" ; nom suivant proposé : $next.") 'warn'
    return $true
}
function Request-PestoDirectAutoNextCheck {
    param([bool]$Execute)
    # Relance hors du rappel en cours : un minuteur à un coup.
    $script:DirectAutoNextExecute=$Execute
    if(-not $script:DirectAutoNextTimer){
        $script:DirectAutoNextTimer=[Windows.Threading.DispatcherTimer]::new();$script:DirectAutoNextTimer.Interval=[TimeSpan]::FromMilliseconds(150)
        $script:DirectAutoNextTimer.Add_Tick([EventHandler]${function:Invoke-PestoDirectAutoNextTick})
    }
    $script:DirectAutoNextTimer.Stop();$script:DirectAutoNextTimer.Start()
}
function Invoke-PestoDirectAutoNextTick {
    param($Sender,$EventArgs)
    $script:DirectAutoNextTimer.Stop()
    Start-PestoDirectPreflight -Execute:([bool]$script:DirectAutoNextExecute) -Auto
}

function Assert-PestoDirectPreflightFreshness {
    param([string]$Utc)
    $at=[DateTimeOffset]::MinValue
    if(-not [DateTimeOffset]::TryParse($Utc,[ref]$at)){
        throw 'Horodatage du contrôle invalide. Relancez le contrôle avant toute exécution.'
    }
    $age=([DateTimeOffset]::UtcNow-$at).TotalSeconds
    if($age -lt 0 -or $age -gt 120){
        throw 'Le contrôle a plus de deux minutes ou son horodatage est futur. Relancez le contrôle puis confirmez à nouveau.'
    }
}

function Complete-PestoDirectPreflight {
    param($Result,$Failure,$Context)
    if(-not $Context -or $Context.Generation -ne $script:DirectGeneration){return}
    try{
        if($Failure){throw $Failure.Exception}
        $results=@($Result.Results)
        if($results.Count -ne 1 -or $results[0].Key -ne $Context.Key -or $results[0].State -notin @('BLOQUÉ','VÉRIFIÉ','AVERTISSEMENT','DÉMO')){throw 'Résultat de contrôle incomplet.'}
        $r=$results[0]
        if($r.State -eq 'BLOQUÉ' -and [string]$r.Detail -like '*Nom cible déjà présent dans AD*' -and $r.PSObject.Properties['SeriesTaken'] -and (Get-Command Add-PestoTakenNames -ErrorAction SilentlyContinue)){Add-PestoTakenNames @($r.SeriesTaken)}
        if($r.State -eq 'BLOQUÉ' -and [string]$r.Detail -like '*Nom cible déjà présent dans AD*' -and [bool]$Context.Plan.Renommer -and
           (Select-PestoDirectNextName -TakenName ([string]$Context.Plan.Nouveau_Nom) -Reason 'est déjà utilisé dans l''AD (sans doute par un autre poste).')){
            Set-PestoDirectBusy $false;Update-PestoSuiteUI;Request-PestoDirectAutoNextCheck -Execute ([bool]$Context.Execute);return
        }
        if($r.State -eq 'BLOQUÉ'){throw $r.Detail}
        Assert-PestoDirectPreflightFreshness -Utc ([string]$r.Utc)
        $script:DirectAutoNext=0
        if($Context.Plan.ConfigStamp -ne (Get-PestoConfigurationSignature $script:CFG)){throw 'Les paramètres ont changé pendant le contrôle.'}
        $id=[Guid]::Empty
        if(-not [Guid]::TryParse([string]$r.Guid,[ref]$id) -or $id -eq [Guid]::Empty){throw 'Identité AD non confirmée par le contrôle.'}
        $Context.Plan.Objet_GUID=$id.ToString('D')
        $Context.Plan|Add-Member -NotePropertyName DC -NotePropertyValue ([string]$script:DC) -Force
        $Context.Plan|Add-Member -NotePropertyName TargetOUGuid -NotePropertyValue ([string]$r.TargetOUGuid) -Force
        if($r.ObservedOU -and $r.ObservedOU -ine $Context.Plan.OU_Actuelle){throw 'Le poste a changé d''emplacement. Relisez son état.'}
        $script:DirectCheckedKey=Get-PestoPlanSignature $Context.Plan
        $script:DirectMessage='Contrôle terminé : '+[string]$r.State
        $script:DirectAdvice=[string]$r.Detail
        if(-not $Context.Execute){Set-PestoDirectBusy $false;return}
        $p=$Context.Plan
        # Nom réservé par un autre poste dans le registre partagé (réponse arrivée pendant le contrôle) : nom suivant,
        # revérifié, avant la confirmation plutôt qu'un échec après.
        if([bool]$p.Renommer -and (Test-PestoNameReservedByOther ([string]$p.Nouveau_Nom)) -and
           (Select-PestoDirectNextName -TakenName ([string]$p.Nouveau_Nom) -Reason 'est réservé par un autre poste dans le registre partagé.' -RegistryHeld)){
            Set-PestoDirectBusy $false;Update-PestoSuiteUI;Request-PestoDirectAutoNextCheck -Execute $true;return
        }
        $verb=if($p.Renommer -and $p.Deplacer){'Renommer puis déplacer'}elseif($p.Renommer){'Renommer uniquement'}else{'Déplacer uniquement'}
        $ou=if($p.Deplacer){$p.OU_Destination}else{$p.OU_Actuelle}
        $mode=if($script:GUI -or $script:SIM){'SIMULATION'}else{'RÉEL'}
        $message="$mode · $verb`n`nPoste : $($p.Nom_du_PC)`nNom final : $(if($p.Renommer){$p.Nouveau_Nom}else{$p.Nom_du_PC})`nEmplacement : $(Format-OUPath $ou)`n`n$($r.Detail)`n`nAucun redémarrage automatique."
        if($p.Renommer){$message+="`nÉtat Entra relu avant renommage : aucun retrait si AD seul ; retrait si hybride et autorisé. Réinscription à vérifier séparément."}
        if($script:PestoPolicy.AllowPasswordTaskFallback){$message+="`nPolitique : le repli par tâche Windows utilisant le mot de passe du compte AD est autorisé en cas de refus confirmé. Aucun repli sur résultat incertain."}
        if(-not(Confirm-YesNo -Msg $message -Confirm $true -AcceptText $verb -SummaryRows @([pscustomobject]@{Field='Nom';Before=$p.Nom_du_PC;After=$(if($p.Renommer){$p.Nouveau_Nom}else{$p.Nom_du_PC})},[pscustomobject]@{Field='Emplacement';Before=$p.OU_Actuelle;After=$ou}))){
            $script:DirectMessage='Confirmation annulée. Aucun changement lancé.';Set-PestoDirectBusy $false;return
        }
        $p|Add-Member -NotePropertyName PlanFingerprint -NotePropertyValue (Get-PestoPlanFingerprint $p) -Force
        Start-PestoDirectAction -Plan $p -PreflightUtc ([string]$r.Utc)
    }catch{
        $script:DirectCheckedKey=''
        $script:DirectMessage='Contrôle non abouti. Aucune action de modification lancée.'
        $script:DirectAdvice=Protect-PestoLogText $_.Exception.Message
        Write-Log 'Contrôle unitaire refusé avant mutation.' 'WARN' $_ 'direct'
        Set-PestoDirectBusy $false
    }
}

function Start-PestoDirectAction {
    param($Plan,[string]$PreflightUtc)
    if($script:PestoReadOnly){throw 'Consultation : aucune mutation autorisée.'}
    # La confirmation modale peut rester ouverte longtemps : relire l'âge au
    # dernier point synchrone avant la création du worker et de son reçu.
    Assert-PestoDirectPreflightFreshness -Utc $PreflightUtc
    Assert-PestoConfirmedPlan -Plan $Plan -Fingerprint $Plan.PlanFingerprint -ConfigurationStamp (Get-PestoConfigurationSignature $script:CFG)
    if($script:CfgRestartRequired -or $Plan.ConfigStamp -ne (Get-PestoConfigurationSignature $script:CFG)){throw 'Contexte modifié depuis la confirmation.'}
    $mode=if($script:SIM -or $script:GUI){'SIMULATION'}else{'RÉEL'}
    $id=[Guid]::NewGuid().ToString('D')
    $local=($Plan.Nom_du_PC -ieq $env:COMPUTERNAME)
    $script:DirectMonitor=New-PestoQueueMonitor -Computer $Plan.Nom_du_PC -OperationId $id
    $script:DirectStarted=Get-Date;$script:DirectMessage='Commande en préparation…';$script:DirectAdvice='Le formulaire est verrouillé. Une limite de supervision ne garantit jamais l''annulation de Windows.'
    $script:LogFollow=$true;if($script:SuiteUI){$script:SuiteUI.SuiteLogFollow.IsChecked=$true}
    $context=[pscustomobject]@{Plan=$Plan;OperationId=$id;Started=$script:DirectStarted;Monitor=$script:DirectMonitor}
    if($script:GUI){
        $code=if($Plan.Renommer -and $Plan.Deplacer){77}elseif($Plan.Renommer){20}else{30}
        Complete-PestoDirectAction -Result ([pscustomobject]@{Action=[pscustomobject]@{ExitCode=$code;ExitMsg='Démonstration : aucune commande Windows/AD exécutée.'};Logs=@();Receipt=$null}) -Context $context;return
    }
    if(-not $script:SIM -and -not(Test-PestoAuditWritable)){throw 'Journal indisponible avant mutation. Action non lancée.'}
    $ou=@{};foreach($k in $script:OU.Keys){$ou[$k]=$script:OU[$k]};$ouv=@{};foreach($k in $script:OUV.Keys){$ouv[$k]=$script:OUV[$k]}
    $request=[pscustomobject]@{
        Plan=$Plan;Version=$script:Pesto_VERSION;OperationId=$id;ResumeId=[string]$script:DirectResumeId;LocalSource=$local;TargetMachineId=[string]$Plan.TargetMachineId
        Telemetry=$script:DirectMonitor;Computer=$Plan.Nom_du_PC;NewName=$Plan.Nouveau_Nom;TargetOU=$Plan.OU_Destination;CurrentOU=$Plan.OU_Actuelle
        Rename=$Plan.Renommer;Move=$Plan.Deplacer;Reboot=$false;ObjectGuid=$Plan.Objet_GUID
        TargetOUGuid=$Plan.TargetOUGuid;ConfigStamp=$Plan.ConfigStamp;PlanFingerprint=$Plan.PlanFingerprint;Policy=(ConvertTo-PestoPolicy $script:CFG.POLICY);ReadOnly=[bool]$script:PestoReadOnly
        DC=$script:DC;Domain=$script:DOMAINE;Credential=$script:cred;Prefix=$script:PREFIXE
        SIM=[bool]$script:SIM;InDomain=$true;PRD=[bool]$script:PRD;OU=$ou;OUSite=$ouv
        OUPostes=$script:OU_POSTES;OUScan=$script:OU_SCAN;ClearProtection=[bool]$script:CLEAR_PROTECTION
        EntraPolicy=[string](@($script:CFG.CONF)[0].EntraPolicy);AllowPasswordTaskFallback=(ConvertTo-PestoPolicy $script:CFG.POLICY).AllowPasswordTaskFallback
        ADModulePath=(Join-Path $BasePath 'ActiveDirectory.psd1')
    }
    Add-LogLine ("DÉBUT $mode UNITAIRE : "+$Plan.Nom_du_PC+' → '+$Plan.Nouveau_Nom+' | '+$id) 'head'
    $started=Start-PestoAsyncOperation -Name 'DirectAction' -ScriptBlock $script:PestoDirectWorker -ArgumentList @($request,(Get-PestoWorkerCoreSource),$script:PestoQueueWorker.ToString(),(Get-PestoDirectSupportSource)) `
        -ApartmentState STA -QueueMonitor $script:DirectMonitor -TimeoutSec 900 -CallbackContext $context `
        -OnSuccess {param($r,$c) Complete-PestoDirectAction -Result $r -Context $c} `
        -OnError {param($e,$c) Complete-PestoDirectAction -Failure $e -Context $c}
    if(-not $started){throw 'Worker non créé. Aucune commande unitaire lancée.'}
    Update-PestoSuiteUI
}

function Complete-PestoDirectAction {
    param($Result,$Failure,$Context)
    $code=97;$message='Résultat à vérifier.'
    $simulation=[bool]($script:GUI -or $script:SIM)
    try{
        if($Failure){throw $Failure.Exception}
        if(-not $Result -or -not $Result.Action -or $Result.Action.ExitCode -isnot [int]){throw 'Résultat unitaire absent ou non typé.'}
        $code=$Result.Action.ExitCode
        $message=Protect-PestoLogText ([string]$Result.Action.ExitMsg)
        if(-not $simulation -and $Result.Receipt){$script:DirectReceipt=$Result.Receipt}
        if(-not $simulation -and -not $Result.Receipt -and $code -ne 96){throw 'Reçu de résultat absent. Vérification nécessaire.'}
        if($simulation){
            $script:DirectMessage='SIMULATION TERMINÉE · aucune mutation réelle.'
            $script:DirectAdvice=$message;$script:DirectLocked=$false
        }else{
            $phase=if($Result.Receipt){[string]$Result.Receipt.Phase}else{'NotStarted'}
            $script:DirectLocked=($phase -notin @('Verified','Failed','NotStarted') -and -not(Test-PestoOptionalPostCheckReceipt $Result.Receipt) -and -not(Test-PestoAcknowledgedReceipt $Result.Receipt)) -or
                ($script:DirectReceipt -and $script:DirectReceipt.Phase -notin @('Verified','Failed','NotStarted') -and -not(Test-PestoOptionalPostCheckReceipt $script:DirectReceipt) -and -not(Test-PestoAcknowledgedReceipt $script:DirectReceipt))
            $script:DirectMessage=switch($phase){
                'PendingRestart'{'Renommage accepté · redémarrage nécessaire, vérification facultative.'}
                'Partial'{'Renommage accepté · déplacement restant à vérifier.'}
                'Protection'{'Protection AD à vérifier. Aucun enchaînement autorisé.'}
                'Verified'{'Déplacement confirmé par le moteur.'}
                'NotStarted'{'Action non lancée.'}
                'Failed'{'Action refusée ou en échec.'}
                default{'Résultat incertain. Ne relancez pas l''action.'}
            }
            $script:DirectAdvice=(Get-PestoResultGuidance -Code $code -Message $message)+"`n"+$message
        }
        Add-LogLine ('RÉSULTAT UNITAIRE '+$Context.OperationId+' | code '+$code+' | '+$message) $(if($code -in @(20,30,33,77)){'ok'}elseif($code -in @(89,96)){'warn'}else{'err'})
    }catch{
        $message=Protect-PestoLogText $_.Exception.Message
        $notLaunched=($Failure -and -not $Context.Monitor.MutationStarted -and -not $Context.Monitor.TimedOut)
        $script:DirectLocked=(-not $simulation -and -not $notLaunched)
        if(-not $simulation){try{$script:DirectReceipt=Read-PestoDirectReceipt (Get-PestoDirectStatePath)}catch{}}
        # L'absence de reçu lisible ne devient jamais un succès ni une annulation.
        $script:DirectMessage=if($notLaunched){'Action non lancée.'}else{'Résultat à vérifier. La commande Windows peut encore finir.'}
        $script:DirectAdvice=$message+' Aucun nouvel essai automatique.'
        Write-Log 'Résultat unitaire non confirmé.' 'ERROR' $_ 'direct'
        $code=if($notLaunched){96}else{97}
    }finally{
        $script:DirectResumePlan=$null;$script:DirectResumeId='';$script:DirectCheckedKey=''
        if(-not $simulation -and $code -notin @(21,31,69,88,96)){Invalidate-PestoNameInventory}
        # Si le timer a expiré, le worker peut être vivant. Les gardes globales le conservent.
        Set-PestoDirectBusy (Test-PestoAsyncOperationRunning 'DirectAction')
        if($script:DirectBusy){$script:DirectLocked=$true}
        $state=[pscustomobject]@{RunId=$Context.OperationId;Mode=$(if($simulation){'SIMULATION'}else{'RÉEL'});Total=1;OkCount=$(if($code -in @(20,30,33,77)){1}else{0});KoCount=$(if($code -notin @(20,30,33,77,96)){1}else{0});CancelCount=$(if($code -eq 96){1}else{0})}
        if(-not $simulation){try{Save-PestoRunHistory $state}catch{Write-Log 'Historique unitaire non enregistré ; le reçu reste la référence.' 'WARN' $_ 'direct'}}
        $autoNext=$false
        if($code -eq 69 -and -not $simulation -and -not $script:DirectBusy -and -not $script:DirectLocked -and $Context.Plan -and [bool]$Context.Plan.Renommer){
            $autoNext=Select-PestoDirectNextName -TakenName ([string]$Context.Plan.Nouveau_Nom) -Reason 'a été pris entre-temps (sans doute par un autre poste). Aucun renommage lancé.'
        }
        if(-not $simulation -and -not $script:DirectBusy){Request-PestoAffectedRefresh -Names @($Context.Plan.Nom_du_PC,$Context.Plan.Nouveau_Nom)}
        if(-not $simulation -and $code -in @(20,77) -and $Context.Plan -and ([string]$Context.Plan.Nom_du_PC) -ieq [string]$env:COMPUTERNAME -and (Get-Command Update-PestoHomeInterventions -CommandType Function -ErrorAction SilentlyContinue)){
            # Renommage de ce PC accepté, redémarrage attendu : relire l'observation Windows locale (lecture seule).
            try{$script:HomeLocalSnapshot=$null;$script:HomeReceiptsTick=0;Update-PestoHomeInterventions}catch{Write-Log 'Observation locale non relue après le renommage.' 'WARN' $_ 'direct'}
        }
        Update-PestoSuiteUI
        if($autoNext){Request-PestoDirectAutoNextCheck -Execute $true}
        elseif($script:DirectMessage){Show-PestoOutcome -Title ([string]$script:DirectMessage) -Message (([string]$script:DirectMessage)+"`n`n"+([string]$script:DirectAdvice))}
    }
}

function Initialize-PestoDirectState {
    $script:DirectBusy=$false;$script:DirectLocked=$false;$script:DirectReceipt=$null
    if($script:GUI -or $script:SIM){return}
    try{
        $r=Read-PestoDirectReceipt (Get-PestoDirectStatePath)
        if(-not $r){return}
        if($r.OperatorMachineId -ine $script:HostMachineId){throw 'Reçu provenant d''un autre poste opérateur.'}
        $script:DirectReceipt=$r
        $acknowledged=Test-PestoAcknowledgedReceipt $r
        $script:DirectLocked=($r.Phase -notin @('Verified','Failed','NotStarted') -and -not(Test-PestoOptionalPostCheckReceipt $r) -and -not $acknowledged)
        $presentationPhase=if(Test-PestoOptionalPostCheckReceipt $r){'AcceptedOptional'}else{[string]$r.Phase}
        $script:DirectMessage='Dernière opération unitaire : '+(Get-PestoStatePresentation $presentationPhase).Label+$(if($acknowledged){' (acquittée)'}else{''})+' · '+$r.Plan.Nom_du_PC+' → '+$r.Plan.Nouveau_Nom
        $script:DirectAdvice=if($script:DirectLocked){"Utilisez « $(Get-PestoUxNom 'BtnReprendre') ». Les noms identiques à l'ancien état ne prouvent pas l'annulation."}elseif($acknowledged){Get-PestoAcknowledgementText $r}else{[string]$r.ResultMessage}
    }catch{
        $script:DirectLocked=$true;$script:DirectMessage='État unitaire illisible. Vérification nécessaire.';$script:DirectAdvice=Protect-PestoLogText $_.Exception.Message
        Write-Log 'Reprise unitaire verrouillée.' 'ERROR' $_ 'direct'
    }
    Update-QueueButtons;Update-AddButton;Update-PestoSuiteUI
}

function Show-PestoDirectDetails {
    $r=$script:DirectReceipt
    if(-not $r){Show-MsgInfo 'Aucun reçu unitaire disponible.';return}
    $lines=[Collections.Generic.List[string]]::new()
    foreach($pair in @(@('Opération',$r.OperationId),@('Début UTC',$r.StartedUtc),@('Fin UTC',$r.FinishedUtc),@('Phase',$r.Phase),
        @('Poste',$r.Plan.Nom_du_PC),@('Nouveau nom',$r.Plan.Nouveau_Nom),@('GUID',$r.Plan.Objet_GUID),@('OU avant',$r.Plan.OU_Actuelle),@('OU prévue',$r.Plan.OU_Destination),
        @('Code original',$r.ResultCode),@('Résultat original',$r.ResultMessage),@('Observation ultérieure UTC',$r.ObservedUtc))){
        $lines.Add(([string]$pair[0]+ ' : '+[string]$pair[1]))
    }
    $text=$lines -join "`r`n"
    Show-PestoTextReport 'Pesto · Détail unitaire' $text
}

function Apply-PestoDirectObservation {
    param($Receipt,$Observation,$Decision)
    if(-not $Receipt -or (-not $Decision.Verified -and -not $Decision.ResumeMove)){throw 'Observation insuffisante.'}
    $mutex=$null;$owned=$false
    try{
        $mutex=[Threading.Mutex]::new($false,'Global\GP_PostMutation_v1')
        try{$owned=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$owned=$true}
        if(-not $owned){throw 'Le worker détient encore le verrou machine. Aucune reprise préparée.'}
        $path=Get-PestoDirectStatePath;$current=Read-PestoDirectReceipt $path
        if(-not $current -or $current.OperationId -ne $Receipt.OperationId){throw 'Le reçu a changé depuis la lecture.'}
        if($Decision.ResumeMove -and -not(Test-PestoOUInConfiguredScope ([string]$current.Plan.OU_Destination))){throw 'La destination ne fait plus partie du périmètre. Aucun déplacement préparé.'}
        $ledgerPath=Join-Path (Get-PestoInterventionRoot) (([Guid]$current.OperationId).ToString('N')+'.json')
        if(Test-Path -LiteralPath $ledgerPath){[void](Confirm-PestoInterventionObservation -OperationId $current.OperationId -Observation $Observation)}
        $current.ObservedUtc=[string]$Observation.ObservedUtc
        $current.Phase=if($Decision.Verified){'Verified'}else{'Partial'}
        # Le code et message d'origine sont conservés, y compris un code 97.
        Write-PestoDirectReceipt -Path $path -Receipt $current
        $script:DirectReceipt=$current
        $script:DirectLocked=-not $Decision.Verified
        $script:DirectMessage=$Decision.Message;$script:DirectAdvice='Observation consignée. Le résultat original reste disponible dans Détails.'
        if($Decision.ResumeMove){
            $script:DirectResumeId=[string]$current.OperationId
            $script:DirectResumePlan=[pscustomobject]@{Nom_du_PC=[string]$current.Plan.Nouveau_Nom;Nouveau_Nom=[string]$current.Plan.Nouveau_Nom;OU_Actuelle=[string]$Observation.AD.OU;OU_Destination=[string]$current.Plan.OU_Destination;Objet_GUID=[string]$current.Plan.Objet_GUID;Renommer=$false;Deplacer=$true;Reboot=$false;Domain=[string]$current.Plan.Domain;TargetMachineId=[string]$current.TargetMachineId;ConfigStamp=(Get-PestoConfigurationSignature $script:CFG)}
            $script:DirectAdvice='Le prochain bouton lancera le contrôle du DÉPLACEMENT SEUL, puis sa confirmation. Aucun renommage ni dsregcmd rejoué.'
        }
        Add-LogLine ('Vérification unitaire consignée : '+$Decision.Message) 'info'
    }finally{if($mutex){try{if($owned){$mutex.ReleaseMutex()}}finally{$mutex.Dispose()}}}
    Update-QueueButtons;Update-AddButton;Update-PestoSuiteUI
}

function Assert-PestoStoredMutationReady {
    param([string]$OwnOperationId='', [switch]$Joining,$Plan=$null)
    if($script:SIM -or $script:GUI){return}
    $currentMachine=[string](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid -ErrorAction Stop).MachineGuid
    $direct=Read-PestoDirectReceipt (Get-PestoDirectStatePath)
    if($direct){
        if($direct.OperatorMachineId -ine $currentMachine){throw 'Reçu unitaire provenant d''un autre poste. Vérification manuelle requise.'}
        if($direct.Phase -notin @('Failed','NotStarted','Verified') -and $direct.OperationId -ne $OwnOperationId -and -not(Test-PestoOptionalPostCheckReceipt $direct) -and -not(Test-PestoAcknowledgedReceipt $direct)){
            $linked=$null
            if($Plan){
                $linkId=[Guid]::Empty
                if([Guid]::TryParse([string]$direct.OperationId,[ref]$linkId)){
                    $linkPath=Join-Path (Get-PestoInterventionRoot) ($linkId.ToString('N')+'.json')
                    if([IO.File]::Exists($linkPath)){$linked=Read-PestoIntervention $linkPath}
                }
            }
            if(-not $linked -or -not $Plan -or (Test-PestoInterventionConflict $linked $Plan)){
                throw 'Une opération non résolue concerne cette cible ou un ancien reçu non rattaché. Consulter Interventions.'
            }
        }
    }
    if(-not $Joining){
        $join=Read-PestoJoinReceipt (Get-PestoJoinStatePath)
        if($join){
            if($join.MachineId -ine $currentMachine){throw 'Reçu de jonction provenant d''un autre poste. Vérification manuelle requise.'}
            if($join.Phase -notin @('Failed','Verified')){
                $status=Get-PestoJoinReceiptStatus -Receipt $join -Domain $join.Domain
                if($status.Decision.Blocked){throw ('La jonction précédente reste en attente : '+$status.Decision.Message)}
            }
        }
    }
}
