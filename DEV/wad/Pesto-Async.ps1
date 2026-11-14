#requires -Version 5.1
# Définitions uniquement, chargées dans la portée du moteur.


function New-PestoQueueMonitor {
    param([string]$Computer,[string]$OperationId='',[string]$BuildSHA256='')
    if(-not $BuildSHA256){$BuildSHA256=[string]$script:PestoBuildSHA256}
    return [hashtable]::Synchronized(@{
        Computer=$Computer;OperationId=$OperationId;WorkerId=[Guid]::NewGuid().ToString('N');BuildSHA256=$BuildSHA256; Events=[Collections.Concurrent.ConcurrentQueue[object]]::new()
        Stage=[pscustomobject]@{Name='Préparation du worker';Kind='Calcul';Started=[DateTime]::UtcNow;Detail=''}
        StageHistory=[Collections.Concurrent.ConcurrentQueue[object]]::new()
        StageTimings=[Collections.Concurrent.ConcurrentQueue[object]]::new()
        CancelRequested=$false; MutationStarted=$false; TimedOut=$false; HelperPid=0
        LastHeartbeat=[DateTime]::UtcNow;DroppedEvents=0;StageClock=[Diagnostics.Stopwatch]::StartNew()
        AuditStream=$false;AuditSink=$null;AuditStreamed=0;AuditStreamFailed=0
    })
}

function Publish-PestoWorkerLog {
    param([string]$Text,[string]$Level='INFO',[string]$Context='worker')
    if($null -eq $script:PestoQueueMonitor){return}
    $pestoEvent=[pscustomobject]@{Time=[DateTime]::UtcNow;Text=(Protect-PestoLogText $Text);Level=$Level;Context=$Context;OperationId=[string]$script:PestoQueueMonitor.OperationId;WorkerId=[string]$script:PestoQueueMonitor.WorkerId;BuildSHA256=[string]$script:PestoQueueMonitor.BuildSHA256;Stage=[string]$script:PestoQueueMonitor.Stage.Name}
    # Le mode silencieux injecte son writer, dans le même runspace. Les workers GUI ne chargent
    # aucune dépendance UI/journal supplémentaire. En échec, la file de repli reste bornée et ses pertes comptées.
    if([bool]$script:PestoQueueMonitor.AuditStream){
        $streamed=$false;$streamError=$true
        try{
            if($script:PestoQueueMonitor.AuditSink -is [scriptblock]){
                $streamed=[bool](& $script:PestoQueueMonitor.AuditSink $pestoEvent)
                if($streamed){$streamError=$false}
            }
        }catch{}
        if($streamed){
            try{$script:PestoQueueMonitor.AuditStreamed=[int]$script:PestoQueueMonitor.AuditStreamed+1}catch{}
            return
        }
        if($streamError){try{$script:PestoQueueMonitor.AuditStreamFailed=[int]$script:PestoQueueMonitor.AuditStreamFailed+1}catch{}}
    }
    if($script:PestoQueueMonitor.Events.Count -ge 2000){$script:PestoQueueMonitor.DroppedEvents=[int]$script:PestoQueueMonitor.DroppedEvents+1;return}
    $script:PestoQueueMonitor.Events.Enqueue($pestoEvent)
}

function Set-PestoWorkerStage {
    param([string]$Name,[string]$Detail='')
    if($null -eq $script:PestoQueueMonitor){return}
    $m=$script:PestoQueueMonitor
    if($null -ne $m.StageHistory -and $m.StageClock -and $m.StageHistory.Count -lt 100){$m.StageHistory.Enqueue([pscustomobject]@{Name=[string]$m.Stage.Name;Milliseconds=[long]$m.StageClock.ElapsedMilliseconds})}
    if($null -ne $m.StageTimings -and $m.StageClock -and $m.StageTimings.Count -lt 100){$m.StageTimings.Enqueue([pscustomobject]@{Kind=[string]$m.Stage.Kind;Milliseconds=[long]$m.StageClock.ElapsedMilliseconds})}
    $kind=if($Name -match 'Renommage Windows|Jonction Windows|Déplacement dans AD|Lancement de tâche|Création de tâche|Demande de redémarrage|Retrait Entra'){'Écriture'}elseif($Name -match 'Lecture|Contrôle|Vérification|Attente|Connexion|Autorisation'){'Attente réseau / Windows'}else{'Calcul'}
    $script:PestoQueueMonitor.StageClock=[Diagnostics.Stopwatch]::StartNew()
    $script:PestoQueueMonitor.Stage=[pscustomobject]@{Name=$Name;Kind=$kind;Started=[DateTime]::UtcNow;Detail=$Detail}
    Publish-PestoWorkerLog -Text ($Name+$(if($Detail){' : '+$Detail}else{''})) -Context 'étape'
}

function Complete-PestoWorkerTiming {
    <# Appel après le retour effectif du worker, jamais au timeout : une commande
       Windows peut continuer après la fin de sa surveillance. Idempotent. #>
    param([AllowNull()]$Monitor)
    if($null -eq $Monitor){return}
    [Threading.Monitor]::Enter($Monitor.SyncRoot)
    try{
        if($Monitor.StageClock -and $Monitor.StageClock.IsRunning){
            $Monitor.StageClock.Stop()
            if($null -ne $Monitor.StageTimings -and $Monitor.StageTimings.Count -lt 100){
                $Monitor.StageTimings.Enqueue([pscustomobject]@{Kind=[string]$Monitor.Stage.Kind;Milliseconds=[long]$Monitor.StageClock.ElapsedMilliseconds})
            }
        }
    }finally{[Threading.Monitor]::Exit($Monitor.SyncRoot)}
}

function Assert-PestoWorkerMayContinue {
    <# Barrière coopérative, distincte de Stop(). Une commande Windows déjà
       entrée peut encore agir ; elle n'est jamais annoncée comme annulée. #>
    param([switch]$Mutation)
    if($Mutation -and ($script:PestoReadOnly -or $env:PESTO_READONLY_SESSION -eq '1')){throw 'Consultation : les écritures sont interdites dans le moteur.'}
    $m=$script:PestoQueueMonitor
    if($null -eq $m){return} # Fonctions isolées / tests historiques.
    [Threading.Monitor]::Enter($m.SyncRoot)
    try {
        if($m.CancelRequested){throw [OperationCanceledException]::new('Surveillance expirée : aucune nouvelle étape de mutation autorisée. Vérification manuelle requise.')}
        if($Mutation){$m.MutationStarted=$true}
    } finally {[Threading.Monitor]::Exit($m.SyncRoot)}
}

function Set-PestoQueueCancellationFence {
    param([AllowNull()]$Monitor)
    if($null -eq $Monitor){return}
    [Threading.Monitor]::Enter($Monitor.SyncRoot)
    try {$Monitor.CancelRequested=$true;$Monitor.TimedOut=$true}
    finally {[Threading.Monitor]::Exit($Monitor.SyncRoot)}
}

function Receive-PestoQueueEvents {
    <# Appel Dispatcher uniquement. Drain borné : pas de Wait/Invoke synchrone. #>
    param([AllowNull()]$Monitor,[int]$Maximum=200)
    if($null -eq $Monitor){return}
    if($Monitor.DroppedEvents -gt 0){$dropped=$Monitor.DroppedEvents;$Monitor.DroppedEvents=0;Add-LogLine ("$dropped messages d’affichage non conservés : tampon plein. Les reçus critiques sont séparés.") 'warn'}
    $timing=$null
    if($Monitor.StageTimings){while($Monitor.StageTimings.TryDequeue([ref]$timing)){
        $kind=switch($timing.Kind){'Écriture'{'Write'};'Attente réseau / Windows'{'Wait'};default{'Compute'}}
        try{if(Get-Command Add-PestoPerformanceSample -ErrorAction SilentlyContinue){Add-PestoPerformanceSample -Name ('Stage.'+$kind) -Milliseconds ([long]$timing.Milliseconds) -Count 1}}catch{$script:PestoMetricsDropped=[int]$script:PestoMetricsDropped+1}
    }}
    $pestoEvent=$null;$read=0
    while($read -lt $Maximum -and $Monitor.Events.TryDequeue([ref]$pestoEvent)){
        $kind=if($pestoEvent.Level -match 'ERR|FATAL'){'err'}elseif($pestoEvent.Level -match 'WARN'){'warn'}else{'info'}
        $text='[{0}] {1} | {2} : {3}' -f $pestoEvent.Time.ToLocalTime().ToString('HH:mm:ss'),$Monitor.Computer,$pestoEvent.Context,$pestoEvent.Text
        Add-LogLine $text $kind
        if(Get-Command Write-PestoStructuredEvent -ErrorAction SilentlyContinue){
            try{[void](Write-PestoStructuredEvent -Event (New-PestoStructuredEvent -Message $pestoEvent.Text -Level $pestoEvent.Level -Context $pestoEvent.Context -OperationId $pestoEvent.OperationId -WorkerId $pestoEvent.WorkerId -Stage $pestoEvent.Stage -BuildSHA256 $pestoEvent.BuildSHA256))}
            catch{$script:PestoStructuredEventsDropped=[int]$script:PestoStructuredEventsDropped+1}
        }
        $read++;$pestoEvent=$null
    }
}

function Get-PestoQueueActivityText {
    param([AllowNull()]$Monitor)
    if($null -eq $Monitor){return ''}
    $stage=$Monitor.Stage
    $seconds=if($Monitor.StageClock){[int]$Monitor.StageClock.Elapsed.TotalSeconds}else{[Math]::Max(0,[int]([DateTime]::UtcNow-$stage.Started).TotalSeconds)}
    $text='{0} · {1} | {2} s dans cette étape' -f $stage.Kind,$stage.Name,$seconds
    if($stage.Detail){$text+=' | '+[string]$stage.Detail}
    if([int]$Monitor.HelperPid -gt 0){$text+=' | helper PID '+[int]$Monitor.HelperPid}
    return $text
}

function Test-PestoAsyncMutationName {
    param([string]$Name)
    return ($Name -in @('QueueAction','DomainJoin','DirectAction','RecoveryAction','JoinADReserve','JoinADRelease','JoinADInspect'))
}

function Test-PestoQueueWorkerStillActive {
    foreach($op in @($script:PestoAsyncTimerOperations.Values)){
        if((Test-PestoAsyncMutationName $op.Name) -and $op.Async -and -not $op.Async.IsCompleted){return $true}
    }
    return $false
}

function Test-PestoAsyncOperationRunning {
    param([string]$Name)
    return ($script:PestoAsyncOperations -and $script:PestoAsyncOperations.ContainsKey($Name))
}

function Stop-PestoAsyncOperation {
    <# Annulation NON BLOQUANTE. PowerShell.Stop() est volontairement évité ici :
       appelé depuis le Dispatcher WPF, il peut attendre une commande AD/RPC bloquée
       et figer l'interface. On marque l'opération comme annulée, on détache son nom
       public immédiatement, puis BeginStop demande l'arrêt en arrière-plan quand
       l'API le permet. Exception QueueAction : barrière coopérative, nom conservé
       et aucun BeginStop ; ne jamais couper une restauration de protection. #>
    param([string]$Name)
    if (-not (Test-PestoAsyncOperationRunning $Name)) { return }
    $op = $script:PestoAsyncOperations[$Name]
    if($Name -eq 'NamesProjection' -and $script:NmCalculationCancel){$script:NmCalculationCancel.Cancelled=$true}
    if((Test-PestoAsyncMutationName $Name)){
        $op.Cancelled=$true
        Set-PestoQueueCancellationFence -Monitor $op.QueueMonitor
        # Le timer reste propriétaire du worker jusqu'à sa sortie réelle.
        return
    }
    if($op.Cancellation){$op.Cancellation.Cancelled=$true}
    try { $op.Cancelled = $true } catch {}
    try {
        if ($script:PestoAsyncOperations.ContainsKey($Name) -and
            [object]::ReferenceEquals($script:PestoAsyncOperations[$Name], $op)) {
            [void]$script:PestoAsyncOperations.Remove($Name)
        }
    } catch {}

    # BeginStop retourne immédiatement. En cas d'indisponibilité/erreur, on laisse
    # simplement le worker terminer naturellement ; son callback sera ignoré.
    try {
        if ($op.PowerShell -and -not $op.Async.IsCompleted) {
            $beginStop = $op.PowerShell.PSObject.Methods['BeginStop']
            if ($beginStop) { [void]$op.PowerShell.BeginStop($null, $null) }
        }
    } catch {}
}

function Invoke-PestoAsyncCallback {
    param(
        [AllowNull()]$Callback,
        [AllowNull()]$Argument,
        [string]$OperationName = 'Async',
        [string]$CallbackKind = 'callback',
        [AllowNull()]$Context = $null
    )
    if ($null -eq $Callback) { return }
    if ($Callback -isnot [scriptblock]) {
        $typeName = try { $Callback.GetType().FullName } catch { '<null>' }
        $msg = "Callback $CallbackKind invalide pour '$OperationName' (type=$typeName)."
        try { Write-Log $msg 'ERROR' $null 'async' } catch {}
        try { Show-MsgError $msg 'Pesto — moteur asynchrone' } catch {}
        return
    }
    try {
        # Un tableau résultat doit rester UN SEUL argument du callback.
        # Le contexte est un second argument optionnel, jamais une closure privée.
        $count=if($null -eq $Context){1}else{2}
        $cbArgs = New-Object 'System.Object[]' $count
        $cbArgs[0] = $Argument
        if($count -eq 2){$cbArgs[1]=$Context}
        [void]$Callback.InvokeReturnAsIs($cbArgs)
    } catch {
        if($OperationName -eq "QueueAction"){try{Fail-PestoQueueCallback -Failure $_}catch{$script:MutationUncertain=$true;$script:QueueStopRequested=$true}}
        if($OperationName -eq 'RecoveryAction'){$script:RecoveryBusy=(Test-PestoAsyncOperationRunning 'RecoveryAction');try{if($script:InterventionsUi){$script:InterventionsUi.Hint.Text='Reprise non confirmée : erreur de restitution. Relire le reçu et la cible avant toute nouvelle action.'}}catch{}}
        if($OperationName -eq 'DirectAction'){$script:DirectLocked=$true;$script:DirectMessage='Erreur de restitution. Vérifier le résultat avant toute reprise.';Set-PestoDirectBusy (Test-PestoAsyncOperationRunning 'DirectAction')}
        if($OperationName -in @('JoinADReserve','JoinADRelease','JoinADInspect')){$script:JoinADReservationNeedsReview=$true;$script:JoinLocked=$true;Set-PestoJoinBusy (Test-PestoAsyncOperationRunning $OperationName)}
        if($OperationName -eq 'DomainJoin'){try{Complete-PestoJoinExecutionError -Failure $_ -Request $script:JoinActiveRequest}catch{$script:JoinLocked=$true;$script:JoinBusy=$false}}
        $msg = "Erreur dans le $CallbackKind de l'opération '$OperationName' : $($_.Exception.Message)"
        try { Write-Log $msg 'ERROR' $_ 'async-callback' } catch {}
        try { Show-MsgError $msg 'Pesto — erreur asynchrone' } catch {}
    }
}

function New-PestoReadRunspacePool {
    param([ValidateRange(1,12)][int]$Maximum=12,$Credential=$null,[string]$Domain='',[string]$DC='')
    [hashtable]::Synchronized(@{Maximum=$Maximum;Count=0;Idle=[Collections.Generic.Stack[object]]::new();
        Retired=$false;Credential=$Credential;Domain=$Domain;DC=$DC;Scope=[Guid]::NewGuid().ToString('N')})
}
function Close-PestoReadRunspacePool {
    param([hashtable]$Pool)
    if(-not $Pool){return}
    [Threading.Monitor]::Enter($Pool.SyncRoot)
    try{
        $Pool.Retired=$true;$Pool.Credential=$null
        while($Pool.Idle.Count){$slot=$Pool.Idle.Pop();$slot.Runspace.Dispose();$Pool.Count--}
    }finally{[Threading.Monitor]::Exit($Pool.SyncRoot)}
}
function Get-PestoSessionReadPool {
    param($Credential,[string]$Domain,[string]$DC)
    $pool=$script:PestoReadPool
    if($pool -and (-not [object]::ReferenceEquals($pool.Credential,$Credential) -or $pool.Domain -cne $Domain -or $pool.DC -cne $DC)){
        Close-PestoReadRunspacePool $pool;$pool=$null
    }
    if(-not $pool -or $pool.Retired){$pool=New-PestoReadRunspacePool -Credential $Credential -Domain $Domain -DC $DC;$script:PestoReadPool=$pool}
    return $pool
}
function Enter-PestoReadRunspace {
    param([Parameter(Mandatory=$true)][hashtable]$Pool)
    [Threading.Monitor]::Enter($Pool.SyncRoot)
    try{
        if($Pool.Retired){throw 'Session de lecture retiree.'}
        if($Pool.Idle.Count){$slot=$Pool.Idle.Pop();return [pscustomobject]@{Pool=$Pool;Slot=$slot;Returned=$false}}
        if($Pool.Count -ge $Pool.Maximum){throw 'Pool de lectures sature.'}
        $Pool.Count++
        $rs=$null;$ps=$null
        try{
            # PS5.1 exige un InitialSessionState explicite pour ResetRunspaceState.
            $rs=[runspacefactory]::CreateRunspace([Management.Automation.Runspaces.InitialSessionState]::CreateDefault());$rs.ApartmentState=[Threading.ApartmentState]::MTA
            $rs.ThreadOptions=[Management.Automation.Runspaces.PSThreadOptions]::ReuseThread;$rs.Open()
            $ps=[powershell]::Create();$ps.Runspace=$rs
            [void]$ps.AddScript('@{Functions=@(Get-ChildItem Function: | ForEach-Object { @{Name=$_.Name;Definition=$_.Definition} });Aliases=@(Get-Alias | ForEach-Object { @{Name=$_.Name;Definition=$_.Definition} });Modules=@(Get-Module | ForEach-Object Name);Drives=@(Get-PSDrive | ForEach-Object Name)}')
            $baseline=@($ps.Invoke())[0];if($ps.HadErrors){throw 'Initialisation du pool impossible.'}
            return [pscustomobject]@{Pool=$Pool;Slot=[pscustomobject]@{Runspace=$rs;Baseline=$baseline};Returned=$false}
        }catch{if($rs){$rs.Dispose()};$Pool.Count--;throw}finally{if($ps){$ps.Dispose()}}
    }finally{[Threading.Monitor]::Exit($Pool.SyncRoot)}
}
function Exit-PestoReadRunspace {
    param($Lease,[switch]$Discard)
    if(-not $Lease){return}
    $pool=$Lease.Pool
    [Threading.Monitor]::Enter($pool.SyncRoot)
    try{
        if($Lease.Returned){return};$Lease.Returned=$true
        $slot=$Lease.Slot;$keep=(-not $Discard -and -not $pool.Retired);$ps=$null
        try{
            if($keep){
                # ResetRunspaceState efface les variables, mais laisse les fonctions ajoutees.
                # Retirer les modules/fonctions/alias/lecteurs propres au travail avant le reset.
                $ps=[powershell]::Create();$ps.Runspace=$slot.Runspace
                [void]$ps.AddScript({param($Baseline)
                    $ErrorActionPreference='Stop'
                    foreach($m in @(Get-Module)){if($m.Name -notin $Baseline.Modules){Remove-Module -ModuleInfo $m -Force}}
                    foreach($f in @(Get-ChildItem Function:)){
                        $original=@($Baseline.Functions|Where-Object Name -EQ $f.Name)
                        if(-not $original.Count){Remove-Item -LiteralPath ('Function:\'+$f.Name) -Force}
                        elseif($original[0].Definition -cne $f.Definition){throw 'Fonction initiale modifiee.'}
                    }
                    foreach($a in @(Get-Alias)){
                        $original=@($Baseline.Aliases|Where-Object Name -EQ $a.Name)
                        if(-not $original.Count){Remove-Item -LiteralPath ('Alias:\'+$a.Name) -Force}
                        elseif($original[0].Definition -cne $a.Definition){throw 'Alias initial modifie.'}
                    }
                    # Le reset des variables ne restaure pas une fonction ou un alias supprime.
                    if(@(Get-ChildItem Function:).Count -ne @($Baseline.Functions).Count -or @(Get-Alias).Count -ne @($Baseline.Aliases).Count){throw 'Etat initial incomplet.'}
                    foreach($d in @(Get-PSDrive)){if($d.Name -notin $Baseline.Drives){Remove-PSDrive -Name $d.Name -Force}}
                }.ToString());[void]$ps.AddArgument($slot.Baseline);[void]$ps.Invoke()
                if($ps.HadErrors){throw 'Etat de lecture non reutilisable.'}
                $ps.Dispose();$ps=$null;$slot.Runspace.ResetRunspaceState()
            }
        }catch{$keep=$false}finally{if($ps){$ps.Dispose()}}
        if($keep){$pool.Idle.Push($slot)}else{$slot.Runspace.Dispose();$pool.Count--}
    }finally{[Threading.Monitor]::Exit($pool.SyncRoot)}
}

function Start-PestoAsyncOperation {
    <# Le timer appelle une fonction liée au script Pesto, jamais un GetNewClosure.
       Les données propres à un callback passent par CallbackContext ; elles ne
       doivent pas être capturées dans un module dynamique privé. #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [object[]]$ArgumentList = @(),
        [scriptblock]$OnSuccess,
        [scriptblock]$OnError,
        [scriptblock]$OnLateResult,
        [switch]$Replace,
        [ValidateRange(0,3600)][int]$TimeoutSec = 0,
        [AllowNull()]$CallbackContext = $null,
        [ValidateSet('MTA','STA')][string]$ApartmentState = 'MTA',
        [AllowNull()]$QueueMonitor = $null
    )
    if (Test-PestoAsyncOperationRunning $Name) {
        if (-not $Replace -or (Test-PestoAsyncMutationName $Name)) { return $false }
        Stop-PestoAsyncOperation $Name
    }

    if($QueueMonitor -and $ArgumentList.Count -gt 0 -and $ArgumentList[0].OperationId){$QueueMonitor.OperationId=[string]$ArgumentList[0].OperationId}
    $mutation=(Test-PestoAsyncMutationName $Name)
    if(-not $mutation){
        $reads=@($script:PestoAsyncTimerOperations.Values|Where-Object{(-not(Test-PestoAsyncMutationName $_.Name)) -and -not $_.Completed})
        if($reads.Count -ge 12){
            $record=$null;try{throw 'Trop de lectures encore actives. Attendez leur retour ; aucune nouvelle lecture lancée.'}catch{$record=$_}
            Invoke-PestoAsyncCallback -Callback $OnError -Argument $record -Context $CallbackContext -OperationName $Name -CallbackKind 'admission'
            return $false
        }
        if(-not $script:PestoBackgroundGate){
            $limit=4
            if($script:CFG){$limit=(ConvertTo-PestoPolicy $script:CFG.POLICY).MaxReaders}
            $background=[Math]::Max(1,$limit-1)
            $script:PestoBackgroundGate=[Threading.SemaphoreSlim]::new($background,$background)
            $script:PestoInteractiveGate=if($limit -eq 1){$script:PestoBackgroundGate}else{[Threading.SemaphoreSlim]::new(1,1)}
        }
    }
    $rs=$null; $ps=$null; $timer=$null; $op=$null; $tickHandler=$null;$readLease=$null
    $timing=[hashtable]::Synchronized(@{WaitMs=0L;WorkMs=0L;Phase='Starting'})
    try {
        if(-not $mutation -and $ApartmentState -eq 'MTA'){
            $credential=if($ArgumentList.Count -and $null -ne $ArgumentList[0].Credential){$ArgumentList[0].Credential}else{$script:cred}
            $pool=Get-PestoSessionReadPool -Credential $credential -Domain ([string]$script:DOMAINE) -DC ([string]$script:DC)
            $readLease=Enter-PestoReadRunspace $pool;$rs=$readLease.Slot.Runspace
        }else{
            $rs=[System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
            $rs.ApartmentState=[System.Threading.ApartmentState]$ApartmentState
            $rs.ThreadOptions=[System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread
            $rs.Open()
        }
        $ps=[System.Management.Automation.PowerShell]::Create()
        $ps.Runspace=$rs
        if($mutation){
            [void]$ps.AddScript($ScriptBlock.ToString(),$true)
            foreach($arg in @($ArgumentList)){[void]$ps.AddArgument($arg)}
        }else{
            # Un créneau réservé aux lectures demandées par un clic, MaxReaders-1 (au moins un) aux travaux de fond.
            # Les mutations n'attendent jamais derrière une lecture ; leur verrou est séparé.
            $gate=if($Name -in @('PCProbe','DirectPreflight','JoinCheck','JoinStatus','PostState','WindowsAuth','LoginAuth','NameCandidateCheck','SiteLookup','QueuePreflight','ConfigReadCheck')){$script:PestoInteractiveGate}else{$script:PestoBackgroundGate}
            $wrapper={param($Source,$Arguments,$Gate,$Timing)
                $taken=$false;$work=$null;$clock=[Diagnostics.Stopwatch]::StartNew();$Timing.Phase='Waiting'
                try{
                    while(-not $taken){$taken=$Gate.Wait(200);if(-not $taken -and $clock.Elapsed.TotalSeconds -gt 30){throw 'Créneau de lecture indisponible après 30 secondes.'}}
                    $Timing.WaitMs=[long]$clock.Elapsed.TotalMilliseconds;$Timing.Phase='Running';$work=[Diagnostics.Stopwatch]::StartNew()
                    & ([scriptblock]::Create([string]$Source)) @Arguments
                }finally{if($work){$Timing.WorkMs=[long]$work.Elapsed.TotalMilliseconds}else{$Timing.WaitMs=[long]$clock.Elapsed.TotalMilliseconds};$Timing.Phase='Ended';if($taken){[void]$Gate.Release()}}
            }
            [void]$ps.AddScript($wrapper.ToString(),$true);[void]$ps.AddArgument($ScriptBlock.ToString());[void]$ps.AddArgument($ArgumentList);[void]$ps.AddArgument($gate);[void]$ps.AddArgument($timing)
        }

        $timer=New-Object System.Windows.Threading.DispatcherTimer
        $timer.Interval=[TimeSpan]::FromMilliseconds(90)
        # Conserver le même délégué pour Add_Tick et Remove_Tick.
        $tickHandler=[System.EventHandler]${function:Invoke-PestoAsyncTimerTick}
        $op=[pscustomobject]@{
            Cancellation=$(if($ArgumentList.Count){$ArgumentList[0].Cancellation}else{$null})
            Name=$Name; Runspace=$rs; ReadLease=$readLease; PowerShell=$ps; Async=$null; Timer=$timer
            OnSuccess=$OnSuccess; OnError=$OnError; OnLateResult=$OnLateResult; Context=$CallbackContext; QueueMonitor=$QueueMonitor
            Timing=$timing;Started=(Get-Date); Clock=[Diagnostics.Stopwatch]::StartNew(); Completed=$false; Cancelled=$false
            TimeoutSec=$TimeoutSec; TimeoutReported=$false
            TickHandler=$tickHandler; TickBusy=$false; TimerFaultReported=$false
        }
        $script:PestoAsyncOperations[$Name]=$op
        # Une opération remplacée conserve sa propre entrée jusqu'à son nettoyage.
        $script:PestoAsyncTimerOperations[$timer]=$op
        $timer.Add_Tick($tickHandler)
        $timer.Start()
        # Dernière étape susceptible d'échouer : avant BeginInvoke aucun worker
        # n'a démarré. Le Dispatcher ne reprend qu'après le retour de la fonction.
        $op.Async=$ps.BeginInvoke()
        return $true
    } catch {
        $failure=$_
        try{if($timer){$timer.Stop();if($tickHandler){$timer.Remove_Tick($tickHandler)}}}catch{}
        try{if($timer){[void]$script:PestoAsyncTimerOperations.Remove($timer)}}catch{}
        try{
            if($op -and $script:PestoAsyncOperations.ContainsKey($Name) -and
                [object]::ReferenceEquals($script:PestoAsyncOperations[$Name],$op)){
                [void]$script:PestoAsyncOperations.Remove($Name)
            }
        }catch{}
        try{if($ps){$ps.Dispose()}}catch{}
        try{if($readLease){Exit-PestoReadRunspace $readLease -Discard}else{if($rs){$rs.Close();$rs.Dispose()}}}catch{}
        Invoke-PestoAsyncCallback -Callback $OnError -Argument $failure -Context $CallbackContext -OperationName $Name -CallbackKind 'callback de démarrage'
        return $false
    }
}

function Invoke-PestoAsyncTimerTick {
    <# Handler WPF nommé : sa portée reste celle de Pesto-Core.ps1 même si ce fichier
       est appelé via & depuis le composant Pesto-Startup.ps1. Aucune fonction globale ajoutée. #>
    param($Sender,$EventArgs)
    if($null -eq $Sender -or -not $script:PestoAsyncTimerOperations.ContainsKey($Sender)){return}
    $op=$script:PestoAsyncTimerOperations[$Sender]
    if($null -eq $op -or $op.Completed -or $op.TickBusy -or $null -eq $op.Async){return}
    $op.TickBusy=$true
    try {
        if($op.QueueMonitor){Receive-PestoQueueEvents -Monitor $op.QueueMonitor}
        if(-not $op.Async.IsCompleted){
            if(-not $op.Cancelled -and [int]$op.TimeoutSec -gt 0 -and -not $op.TimeoutReported -and
                $op.Clock.Elapsed.TotalSeconds -ge [int]$op.TimeoutSec){
                $op.TimeoutReported=$true
                if((Test-PestoAsyncMutationName $op.Name)){
                    Set-PestoQueueCancellationFence -Monitor $op.QueueMonitor
                }
                if((-not(Test-PestoAsyncMutationName $op.Name)) -and $script:PestoAsyncOperations.ContainsKey($op.Name) -and
                    [object]::ReferenceEquals($script:PestoAsyncOperations[$op.Name],$op)){
                    [void]$script:PestoAsyncOperations.Remove($op.Name)
                }
                # Annulation non bloquante. Le timer reste vivant pour nettoyer
                # le worker quand celui-ci a effectivement terminé.
                try{
                    if((-not(Test-PestoAsyncMutationName $op.Name)) -and -not $op.Async.IsCompleted -and $op.PowerShell.PSObject.Methods['BeginStop']){
                        [void]$op.PowerShell.BeginStop($null,$null)
                    }
                }catch{}
                $timeoutRecord=$null
                try{
                    $detail="L'opération '$($op.Name)' a dépassé le délai de $($op.TimeoutSec) s."
                    if((Test-PestoAsyncMutationName $op.Name)){$detail+=' Dernière étape : '+(Get-PestoQueueActivityText $op.QueueMonitor)+'. La commande Windows peut encore travailler. Aucun déplacement suivant ni redémarrage ne sera lancé par ce worker.'}
                    throw ([System.TimeoutException]::new($detail))
                }catch{$timeoutRecord=$_}
                Invoke-PestoAsyncCallback -Callback $op.OnError -Argument $timeoutRecord -Context $op.Context -OperationName $op.Name -CallbackKind 'callback de timeout'
            }
            return
        }

        $op.Completed=$true
        $op.Clock.Stop()

        try{$op.Timer.Stop()}catch{}
        try{$op.Timer.Remove_Tick($op.TickHandler)}catch{}
        $value=$null; $caught=$null
        try{
            $raw=@($op.PowerShell.EndInvoke($op.Async))
            if($op.PowerShell.Streams.Error.Count -gt 0){
                $first=$op.PowerShell.Streams.Error[0]
                if($first.Exception){throw $first.Exception}
                throw $first
            }
            if($raw.Count -eq 0){$value=$null}
            elseif($raw.Count -eq 1){$value=$raw[0]}
            else{$value=$raw}
        }catch{$caught=$_}
        finally{
            try{$op.PowerShell.Dispose()}catch{}
            try{if($op.ReadLease){Exit-PestoReadRunspace $op.ReadLease -Discard:([bool]($caught -or $op.Cancelled -or $op.TimeoutReported))}else{$op.Runspace.Close();$op.Runspace.Dispose()}}catch{}
            try{[void]$script:PestoAsyncTimerOperations.Remove($op.Timer)}catch{}
            try{
                if($script:PestoAsyncOperations.ContainsKey($op.Name) -and
                    [object]::ReferenceEquals($script:PestoAsyncOperations[$op.Name],$op)){
                    [void]$script:PestoAsyncOperations.Remove($op.Name)
                }
            }catch{}
        }
        try{
            Complete-PestoWorkerTiming -Monitor $op.QueueMonitor
            if(Get-Command Add-PestoPerformanceSample -ErrorAction SilentlyContinue){
                $state=if($op.TimerFaultReported){'MonitorFault'}elseif($op.TimeoutReported){'Timeout'}elseif($op.Cancelled){'Cancelled'}elseif($caught){'Faulted'}else{'Returned'}
                $work=if((Test-PestoAsyncMutationName $op.Name)){[long]$op.Clock.Elapsed.TotalMilliseconds}else{[long]$op.Timing.WorkMs}
                Add-PestoPerformanceSample -Name $op.Name -Milliseconds ([long]$op.Clock.Elapsed.TotalMilliseconds) -Count 1 -Kind Worker -State $state -WaitMilliseconds ([long]$op.Timing.WaitMs) -WorkMilliseconds $work
            }
        }catch{$script:PestoMetricsDropped=[int]$script:PestoMetricsDropped+1}
        if($op.QueueMonitor){Receive-PestoQueueEvents -Monitor $op.QueueMonitor}
        if($op.Name -eq 'RecoveryAction'){$script:RecoveryBusy=$false}
        # Un worker annulé/remplacé/expiré ne peut jamais publier un succès tardif.
        if($op.Cancelled -or $op.TimeoutReported -or $op.TimerFaultReported){
            if($op.Name -in @('JoinADReserve','JoinADRelease','JoinADInspect') -and $op.OnLateResult){
                Invoke-PestoAsyncCallback -Callback $op.OnLateResult -Argument ([pscustomobject]@{Result=$value;Failure=$caught}) -Context $op.Context -OperationName $op.Name -CallbackKind 'constat tardif sans relance'
            }
            if((Test-PestoAsyncMutationName $op.Name)){
                Receive-PestoQueueEvents -Monitor $op.QueueMonitor
                $late=if($caught){[string]$caught.Exception.Message}elseif($value -and $value.Action){'code '+[string]$value.Action.ExitCode+' : '+[string]$value.Action.ExitMsg}else{'aucun résultat exploitable'}
                Add-LogLine ('Worker revenu après arrêt de surveillance : '+$late+'. Le verrou reste actif ; vérifier le poste avant toute reprise.') 'warn'
            }
            return
        }
        if($caught){
            Invoke-PestoAsyncCallback -Callback $op.OnError -Argument $caught -Context $op.Context -OperationName $op.Name -CallbackKind 'callback d''erreur'
        }else{
            Invoke-PestoAsyncCallback -Callback $op.OnSuccess -Argument $value -Context $op.Context -OperationName $op.Name -CallbackKind 'callback de succès'
        }
    }catch{
        # Une défaillance du polling doit notifier l'opération, pas remonter à
        # Window.ShowDialog. Aucun résultat positif n'est fabriqué en secours.
        $failure=$_
        if(-not $op.TimerFaultReported){
            $op.TimerFaultReported=$true
            $op.Cancelled=$true
            if((Test-PestoAsyncMutationName $op.Name)){Set-PestoQueueCancellationFence -Monitor $op.QueueMonitor}
            try{
                if((-not(Test-PestoAsyncMutationName $op.Name)) -and $script:PestoAsyncOperations.ContainsKey($op.Name) -and
                    [object]::ReferenceEquals($script:PestoAsyncOperations[$op.Name],$op)){
                    [void]$script:PestoAsyncOperations.Remove($op.Name)
                }
            }catch{}
            try{if((-not(Test-PestoAsyncMutationName $op.Name)) -and -not $op.Async.IsCompleted){[void]$op.PowerShell.BeginStop($null,$null)}}catch{}
            Invoke-PestoAsyncCallback -Callback $op.OnError -Argument $failure -Context $op.Context -OperationName $op.Name -CallbackKind 'callback du timer'
        }
    }finally{$op.TickBusy=$false}
}
