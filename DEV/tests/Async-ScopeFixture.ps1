#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory)][string]$SourcePath,[Parameter(Mandatory)][string]$ReportPath)
$ErrorActionPreference='Stop';Set-StrictMode -Off
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName WindowsBase
$tokens=$null;$parseErrors=@();$defs=@{}
# Le moteur est modulaire : analyser chaque composant, puis extraire seulement
# la liste blanche. Le corps de Pesto n'est jamais exécuté ni dot-sourcé.
# L'agrégat CLI généré recopie ces sources : l'exclure de l'index, pas des gardes d'unicité.
$wadDir=Split-Path -Parent ([IO.Path]::GetFullPath($SourcePath))
foreach($file in Get-ChildItem -LiteralPath $wadDir -File | Where-Object{$_.Extension -eq '.ps1' -and $_.Name -ine 'Pesto.Engine.Runtime.ps1'}){
 $fileErrors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$fileErrors)
 $parseErrors+=@($fileErrors)
 foreach($node in $ast.EndBlock.Statements){if($node -is [Management.Automation.Language.FunctionDefinitionAst]){
  if($defs.ContainsKey($node.Name)){throw ('Fonction ambiguë : '+$node.Name)}
  $defs[$node.Name]=$node.Extent.Text
 }}
}
if($parseErrors.Count){throw ($parseErrors.Message -join '; ')}
$required=@('New-PestoReadRunspacePool','Close-PestoReadRunspacePool','Get-PestoSessionReadPool','Enter-PestoReadRunspace','Exit-PestoReadRunspace','Assert-PestoPlainPath','Test-PestoAsyncMutationName','Get-PestoADLoaderSource','Import-PestoADModule','New-PestoQueueMonitor','Publish-PestoWorkerLog','Set-PestoWorkerStage','Complete-PestoWorkerTiming','Assert-PestoWorkerMayContinue','Set-PestoQueueCancellationFence','Receive-PestoQueueEvents','Get-PestoQueueActivityText','Test-PestoQueueWorkerStillActive','Protect-PestoLogText','Test-PestoAsyncOperationRunning','Stop-PestoAsyncOperation','Invoke-PestoAsyncCallback','Start-PestoAsyncOperation',
    'Select-PCName','Refresh-Names','Load-OUChildren')
foreach($name in $required){
    if(-not $defs.ContainsKey($name)){throw "Fonction absente : $name"}
    . ([scriptblock]::Create($defs[$name]))
}
# Optionnelles pour permettre de lancer le reproducer sur une ancienne RC2.
foreach($name in @('Invoke-PestoAsyncTimerTick','Invoke-PestoConfigRepairSave')){
    if($defs.ContainsKey($name)){. ([scriptblock]::Create($defs[$name]))}
}
$script:PestoAsyncOperations=@{};$script:PestoAsyncTimerOperations=@{}
$script:TestResults=[Collections.Generic.List[object]]::new()
$script:TestEvents=[Collections.Generic.List[object]]::new()
$script:TestLogs=[Collections.Generic.List[object]]::new()
$script:TestMessages=[Collections.Generic.List[string]]::new()
$script:TestUiThread=[Threading.Thread]::CurrentThread.ManagedThreadId
$script:TestQueueFailed=$false;$script:MutationUncertain=$false;$script:QueueStopRequested=$false
function Assert-True {param($Value,[string]$Message='Condition non satisfaite.');if($Value -ne $true){throw $Message}}
function Assert-Equal {param($Actual,$Expected);if($Actual -cne $Expected){throw "Attendu [$Expected], obtenu [$Actual]."}}
function Record-PestoAsyncTestCallback {
    param($Value,$Context,[string]$Kind='success')
    $script:TestEvents.Add([pscustomobject]@{Value=$Value;Context=$Context;Kind=$Kind;Thread=[Threading.Thread]::CurrentThread.ManagedThreadId})
}
# Tous les effets metier et dialogues d'erreur sont remplaces ici par des mocks.
function Add-LogLine {param($Text,$Kind);$script:TestLogs.Add([pscustomobject]@{Message=$Text;Level=$Kind;Error=$null;Context='stream'})}
function Write-Log {param($Message,$Level,$Err,$Context);$script:TestLogs.Add([pscustomobject]@{Message=$Message;Level=$Level;Error=$Err;Context=$Context})}
function Show-MsgError {param($Message,$Title);$script:TestMessages.Add([string]$Message)}
function Fail-PestoQueueCallback {param($Failure);$script:TestQueueFailed=$true;$script:MutationUncertain=$true;$script:QueueStopRequested=$true}
function Set-PCInfo {param($Message,$Kind)}
function Set-PestoNamesViewState {param($State,$Monitor);$script:NmLoading=($State -eq 'Loading')}
function Test-PestoComputerName {param($Name);return $true}
function Get-PestoCachedComputerProbe {param($Name,[bool]$Local);return $null}
function Complete-PestoComputerProbeSuccess {param($Result,$Name,$Generation);Record-PestoAsyncTestCallback $Result ([pscustomobject]@{Name=$Name;Generation=$Generation}) 'probe-success'}
function Complete-PestoComputerProbeError {param($Failure,$Name,$Generation);Record-PestoAsyncTestCallback $Failure ([pscustomobject]@{Name=$Name;Generation=$Generation}) 'probe-error'}
function Complete-PestoDirectoryRefresh {param($Snapshot,[bool]$LockMain,$Failure);Record-PestoAsyncTestCallback $Snapshot ([pscustomobject]@{LockMain=$LockMain;Failure=$Failure}) 'directory'}
function New-PestoDirectorySnapshotRequest {param($Credential);return [pscustomobject]@{DC='dc.test.invalid'}}
function Test-CfgValid {param($Cfg);if($Cfg.Invalid){'Configuration refusee par le mock.'}}
function Write-PestoAtomicText {param($Path,$Text,[switch]$Backup);$script:TestWrite=[pscustomobject]@{Path=$Path;Text=$Text;Backup=$Backup.IsPresent}}

function Pump-PestoTestDispatcher {
    # Cette seule closure ne contient que des objets .NET locaux, aucune
    # fonction Pesto ni variable script:. Elle sert uniquement a borner PushFrame.
    $frame=[Windows.Threading.DispatcherFrame]::new()
    $timer=[Windows.Threading.DispatcherTimer]::new()
    $timer.Interval=[TimeSpan]::FromMilliseconds(15)
    $handler=[EventHandler]({param($s,$e);$s.Stop();$frame.Continue=$false}.GetNewClosure())
    $timer.Add_Tick($handler);$timer.Start()
    try{[Windows.Threading.Dispatcher]::PushFrame($frame)}
    finally{$timer.Stop();$timer.Remove_Tick($handler)}
}
function Wait-PestoTestIdle {
    param([int]$TimeoutSeconds=8)
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while($script:PestoAsyncOperations.Count -gt 0 -or $script:PestoAsyncTimerOperations.Count -gt 0){
        if($watch.Elapsed.TotalSeconds -gt $TimeoutSeconds){throw 'Delai de test depasse ; un timer/worker ne se nettoie pas.'}
        Pump-PestoTestDispatcher
    }
}
function Clear-PestoTestOperations {
    # Pas de Stop() synchrone sur un worker : les workers de test ne font que
    # dormir/calculer. Ce nettoyage ne touche ni service, ni machine, ni AD.
    $all=@($script:PestoAsyncOperations.Values)+@($script:PestoAsyncTimerOperations.Values)
    foreach($op in $all){
        try{$op.Cancelled=$true;$op.Timer.Stop();if($op.TickHandler){$op.Timer.Remove_Tick($op.TickHandler)}}catch{}
        try{if($op.Async -and -not $op.Async.IsCompleted){[void]$op.PowerShell.BeginStop($null,$null)}}catch{}
    }
    $watch=[Diagnostics.Stopwatch]::StartNew()
    foreach($op in $all){
        try{
            while($op.Async -and -not $op.Async.IsCompleted -and $watch.Elapsed.TotalSeconds -lt 3){[Threading.Thread]::Sleep(10)}
            if(-not $op.Async -or $op.Async.IsCompleted){$op.PowerShell.Dispose();$op.Runspace.Close();$op.Runspace.Dispose()}
        }catch{}
    }
    $script:PestoAsyncOperations.Clear();$script:PestoAsyncTimerOperations.Clear()
    if($script:PestoReadPool){Close-PestoReadRunspacePool $script:PestoReadPool;$script:PestoReadPool=$null}
}
function Case {
    param([string]$Name,[scriptblock]$Body)
    Clear-PestoTestOperations
    $script:TestEvents.Clear();$script:TestLogs.Clear();$script:TestMessages.Clear()
    $script:TestQueueFailed=$false;$script:MutationUncertain=$false;$script:QueueStopRequested=$false
    $watch=[Diagnostics.Stopwatch]::StartNew()
    try{
        & $Body
        $script:TestResults.Add([pscustomobject]@{Name=$Name;Passed=$true;Error='';Ms=$watch.ElapsedMilliseconds})
        Write-Host "OK  $Name"
    }catch{
        $script:TestResults.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message;Ms=$watch.ElapsedMilliseconds})
        Write-Host "KO  $Name : $($_.Exception.Message)"
    }finally{Clear-PestoTestOperations}
}
function Assert-PestoTestClean {
    Assert-Equal $script:PestoAsyncOperations.Count 0
    Assert-Equal $script:PestoAsyncTimerOperations.Count 0
    foreach($event in $script:TestEvents){Assert-Equal $event.Thread $script:TestUiThread}
}
$success={param($r,$ctx);Record-PestoAsyncTestCallback -Value $r -Context $ctx}
$errorCallback={param($e,$ctx);Record-PestoAsyncTestCallback -Value $e -Context $ctx -Kind 'error'}

Case 'Parseur natif du moteur complet' {Assert-Equal $parseErrors.Count 0}
Case 'La fixture ne rend pas les fonctions Pesto globales' {
    $privateCheck={Get-Command Invoke-PestoAsyncCallback -CommandType Function -ErrorAction SilentlyContinue}.GetNewClosure()
    $visible=@($privateCheck.Invoke())
    Assert-Equal $visible.Count 0
}
Case 'Reproduction du login : timer WPF vers fonction privee du script enfant' {
    Assert-True (Start-PestoAsyncOperation -Name 'LoginAuth' -ScriptBlock {'LOGIN-OK'} -OnSuccess $success -OnError $errorCallback)
    Wait-PestoTestIdle
    Assert-Equal $script:TestEvents.Count 1
    Assert-Equal $script:TestEvents[0].Value 'LOGIN-OK'
    Assert-Equal $script:TestEvents[0].Kind 'success'
    Assert-Equal $script:TestMessages.Count 0
    Assert-PestoTestClean
}
Case 'Erreur worker relayee au callback, sans sortir du Dispatcher' {
    [void](Start-PestoAsyncOperation -Name 'Failure' -ScriptBlock {throw 'worker-test-error'} -OnSuccess $success -OnError $errorCallback)
    Wait-PestoTestIdle
    Assert-Equal $script:TestEvents.Count 1
    Assert-Equal $script:TestEvents[0].Kind 'error'
    Assert-True ($script:TestEvents[0].Value.Exception.Message -match 'worker-test-error')
    Assert-PestoTestClean
}
Case 'Erreur non terminante worker ne devient pas un succes' {
    [void](Start-PestoAsyncOperation -Name 'StreamError' -ScriptBlock {Write-Error 'stream-test-error' -ErrorAction Continue;'sortie-partielle'} -OnSuccess $success -OnError $errorCallback)
    Wait-PestoTestIdle
    Assert-Equal $script:TestEvents.Count 1
    Assert-Equal $script:TestEvents[0].Kind 'error'
    Assert-PestoTestClean
}
Case 'Resultat vide conserve sous forme null' {
    [void](Start-PestoAsyncOperation -Name 'Empty' -ScriptBlock {$null} -OnSuccess $success -OnError $errorCallback)
    Wait-PestoTestIdle
    Assert-Equal $script:TestEvents.Count 1
    Assert-True ($null -eq $script:TestEvents[0].Value)
}
Case 'Tableau resultat garde entier dans le premier argument' {
    $ctx=[pscustomobject]@{Marker='array-context'}
    [void](Start-PestoAsyncOperation -Name 'Array' -ScriptBlock {'a';'b';'c'} -CallbackContext $ctx -OnSuccess $success -OnError $errorCallback)
    Wait-PestoTestIdle
    Assert-Equal $script:TestEvents.Count 1
    Assert-Equal (@($script:TestEvents[0].Value).Count) 3
    Assert-Equal ($script:TestEvents[0].Value -join ',') 'a,b,c'
    Assert-True ([object]::ReferenceEquals($ctx,$script:TestEvents[0].Context))
}
Case 'Contexte erreur conserve par reference' {
    $ctx=[pscustomobject]@{Marker='error-context'}
    [void](Start-PestoAsyncOperation -Name 'ErrorContext' -ScriptBlock {throw 'context-error'} -CallbackContext $ctx -OnSuccess $success -OnError $errorCallback)
    Wait-PestoTestIdle
    Assert-Equal $script:TestEvents[0].Kind 'error'
    Assert-True ([object]::ReferenceEquals($ctx,$script:TestEvents[0].Context))
}
Case 'Absence de callbacks autorisee' {
    [void](Start-PestoAsyncOperation -Name 'NoCallbacks' -ScriptBlock {'ignored'})
    Wait-PestoTestIdle
    Assert-Equal $script:TestEvents.Count 0
    Assert-Equal $script:TestMessages.Count 0
    Assert-PestoTestClean
}
Case 'Callback invalide signale sans exception fatale' {
    Invoke-PestoAsyncCallback -Callback 'not-a-scriptblock' -Argument 'ignored' -OperationName 'Invalid'
    Assert-Equal $script:TestMessages.Count 1
    Assert-Equal $script:TestLogs.Count 1
}
Case 'Exception du callback contenue et journalisee' {
    [void](Start-PestoAsyncOperation -Name 'CallbackThrows' -ScriptBlock {1} -OnSuccess {throw 'callback-test-error'} -OnError $errorCallback)
    Wait-PestoTestIdle
    Assert-Equal $script:TestMessages.Count 1
    Assert-True ($script:TestMessages[0] -match 'callback-test-error')
    Assert-PestoTestClean
}
Case 'Erreur du callback de file conserve le verrou de securite' {
    [void](Start-PestoAsyncOperation -Name 'QueueAction' -ScriptBlock {1} -OnSuccess {throw 'queue-callback-test-error'} -OnError $errorCallback)
    Wait-PestoTestIdle
    Assert-True $script:TestQueueFailed
    Assert-True $script:MutationUncertain
    Assert-True $script:QueueStopRequested
    Assert-PestoTestClean
}
Case 'Annulation non bloquante sans succes tardif' {
    [void](Start-PestoAsyncOperation -Name 'Cancel' -ScriptBlock {Start-Sleep -Milliseconds 500;'too-late'} -OnSuccess $success -OnError $errorCallback)
    $watch=[Diagnostics.Stopwatch]::StartNew()
    Stop-PestoAsyncOperation 'Cancel'
    Assert-True ($watch.Elapsed.TotalSeconds -lt 2) 'Annulation anormalement bloquante.'
    Assert-True (-not (Test-PestoAsyncOperationRunning 'Cancel'))
    Wait-PestoTestIdle
    Assert-Equal $script:TestEvents.Count 0
    Assert-PestoTestClean
}
Case 'Remplacement : ancien worker ne supprime pas le nouveau' {
    [void](Start-PestoAsyncOperation -Name 'ReplaceMe' -ScriptBlock {Start-Sleep -Milliseconds 400;'old'} -OnSuccess $success -OnError $errorCallback)
    Assert-True (Start-PestoAsyncOperation -Name 'ReplaceMe' -ScriptBlock {Start-Sleep -Milliseconds 120;'new'} -OnSuccess $success -OnError $errorCallback -Replace)
    Wait-PestoTestIdle
    Assert-Equal $script:TestEvents.Count 1
    Assert-Equal $script:TestEvents[0].Value 'new'
    Assert-PestoTestClean
}
Case 'Doublon sans Replace refuse sans perdre le premier worker' {
    Assert-True (Start-PestoAsyncOperation -Name 'Duplicate' -ScriptBlock {Start-Sleep -Milliseconds 150;'first'} -OnSuccess $success -OnError $errorCallback)
    Assert-True (-not (Start-PestoAsyncOperation -Name 'Duplicate' -ScriptBlock {'second'} -OnSuccess $success -OnError $errorCallback))
    Wait-PestoTestIdle
    Assert-Equal $script:TestEvents.Count 1
    Assert-Equal $script:TestEvents[0].Value 'first'
}
Case 'Timeout notifie une seule fois puis nettoie le worker' {
    [void](Start-PestoAsyncOperation -Name 'Timeout' -ScriptBlock {Start-Sleep -Seconds 4;'late'} -OnSuccess $success -OnError $errorCallback -TimeoutSec 1)
    Wait-PestoTestIdle
    Assert-Equal $script:TestEvents.Count 1
    Assert-Equal $script:TestEvents[0].Kind 'error'
    Assert-True ($script:TestEvents[0].Value.Exception -is [TimeoutException])
    Assert-PestoTestClean
}
Case 'Quatre workers concurrents gardent leur propre contexte' {
    foreach($i in 1..4){
        $ctx=[pscustomobject]@{Number=$i}
        [void](Start-PestoAsyncOperation -Name "Concurrent$i" -ScriptBlock {param($v);Start-Sleep -Milliseconds (20*$v);$v} -ArgumentList @($i) -CallbackContext $ctx -OnSuccess $success -OnError $errorCallback)
    }
    Wait-PestoTestIdle
    Assert-Equal $script:TestEvents.Count 4
    foreach($event in $script:TestEvents){Assert-Equal $event.Value $event.Context.Number}
    Assert-PestoTestClean
}
Case 'Reentrance du timer pendant le callback de timeout neutralisee' {
    $ctx=[pscustomobject]@{Timer=$null}
    $cb={param($e,$state);Invoke-PestoAsyncTimerTick $state.Timer ([EventArgs]::Empty);Record-PestoAsyncTestCallback $e $state 'timeout'}
    [void](Start-PestoAsyncOperation -Name 'Reentry' -ScriptBlock {Start-Sleep -Seconds 4} -CallbackContext $ctx -OnError $cb -TimeoutSec 1)
    $ctx.Timer=$script:PestoAsyncOperations['Reentry'].Timer
    Wait-PestoTestIdle
    Assert-Equal $script:TestEvents.Count 1
    Assert-Equal $script:TestEvents[0].Kind 'timeout'
    Assert-PestoTestClean
}
Case 'Defaut du polling notifie sans remonter a PushFrame' {
    [void](Start-PestoAsyncOperation -Name 'PollingFault' -ScriptBlock {Start-Sleep -Seconds 2} -OnSuccess $success -OnError $errorCallback -TimeoutSec 1)
    $op=$script:PestoAsyncOperations['PollingFault'];$op.TimeoutSec='invalid-timeout-for-test'
    Wait-PestoTestIdle
    Assert-Equal $script:TestEvents.Count 1
    Assert-Equal $script:TestEvents[0].Kind 'error'
    Assert-True $op.TimerFaultReported
    Assert-PestoTestClean
}

Case 'Toutes les mutations gardent leur worker et refusent Replace' {
 foreach($name in @('QueueAction','DomainJoin','DirectAction','RecoveryAction','JoinADReserve','JoinADRelease','JoinADInspect')){
  Assert-True (Start-PestoAsyncOperation -Name $name -ScriptBlock {Start-Sleep -Milliseconds 100;'done'})
  $original=$script:PestoAsyncOperations[$name]
  Assert-True (-not (Start-PestoAsyncOperation -Name $name -ScriptBlock {'replacement'} -Replace))
  Assert-True ([object]::ReferenceEquals($original,$script:PestoAsyncOperations[$name]))
 }
 Wait-PestoTestIdle;Assert-PestoTestClean
}
Case 'Treizieme lecture refusee avec un seul rappel et aucun worker supplementaire' {
 foreach($n in 1..12){Assert-True (Start-PestoAsyncOperation -Name ('ReadAdmission'+$n) -ScriptBlock {Start-Sleep -Milliseconds 50;'done'})}
 Assert-True (-not (Start-PestoAsyncOperation -Name 'ReadAdmission13' -ScriptBlock {'unexpected'} -OnError $errorCallback))
 Assert-Equal $script:PestoAsyncTimerOperations.Count 12;Assert-Equal $script:TestEvents.Count 1
 Assert-True ($script:TestEvents[0].Value.Exception.Message -match 'Trop de lectures')
 Wait-PestoTestIdle;Assert-PestoTestClean
}
function Set-PestoDirectBusy {param($Busy);$script:TestDirectBusy=$Busy}
Case 'Erreur restitution directe conserve le verrou et rend la main sans mutation' {
 $script:DirectLocked=$false;$script:TestDirectBusy=$true
 Invoke-PestoAsyncCallback -Callback {throw 'UI failure'} -Argument $null -OperationName DirectAction
 Assert-True $script:DirectLocked;Assert-True (-not $script:TestDirectBusy)
 Assert-True ($script:DirectMessage -match 'Vérifier');Assert-Equal $script:TestMessages.Count 1
}

# Vrais callbacks de leurs fonctions appelantes, mais workers sans AD.
$script:Suspend=$false;$script:GUI=$false;$script:INDOMAIN=$true;$script:LOCALHOST=$false
$script:PCProbeGeneration=0;$script:DC='dc.test.invalid';$script:cred=$null
$script:BasePath=$PSScriptRoot
$script:TxtPCName=[pscustomobject]@{Text='Pesto-TEST-REMOTE'}
$script:BtnAdd=[pscustomobject]@{IsEnabled=$false}
$script:NmBtnRefresh=[pscustomobject]@{IsEnabled=$true}
$script:LblStatus=[pscustomobject]@{Text=''}
foreach($control in @('CbOrg','CbSite','CbService','CbName')){Set-Variable -Name $control -Scope Script -Value ([pscustomobject]@{IsEnabled=$true})}
Case 'Lecture poste : nom et generation restent disponibles au retour' {
    $script:PestoComputerProbeWorker={param($r);[pscustomobject]@{Name=$r.Name}}
    Select-PCName
    Wait-PestoTestIdle
    Assert-Equal $script:TestEvents.Count 1
    Assert-Equal $script:TestEvents[0].Kind 'probe-success'
    Assert-Equal $script:TestEvents[0].Context.Name 'Pesto-TEST-REMOTE'
    Assert-Equal $script:TestEvents[0].Context.Generation $script:PCProbeGeneration
}
Case 'Lecture poste en erreur : rappel prive retrouve' {
    $script:PestoComputerProbeWorker={param($r);throw 'probe-error'}
    Select-PCName
    Wait-PestoTestIdle
    Assert-Equal $script:TestEvents.Count 1
    Assert-Equal $script:TestEvents[0].Kind 'probe-error'
    Assert-Equal $script:TestEvents[0].Context.Name 'Pesto-TEST-REMOTE'
}
Case 'Actualisation AD : LockMain transmis sans closure privee' {
    $script:PestoDirectorySnapshotWorker={param($r);[pscustomobject]@{DC=$r.DC}}
    Assert-True (Refresh-Names -LockMain)
    Wait-PestoTestIdle
    Assert-Equal $script:TestEvents.Count 1
    Assert-Equal $script:TestEvents[0].Kind 'directory'
    Assert-True $script:TestEvents[0].Context.LockMain
    Assert-Equal $script:TestEvents[0].Value.DC 'dc.test.invalid'
}
Case 'Actualisation AD en erreur : echec et verrou UI transmis' {
    $script:PestoDirectorySnapshotWorker={param($r);throw 'directory-error'}
    Assert-True (Refresh-Names -LockMain)
    Wait-PestoTestIdle
    Assert-Equal $script:TestEvents.Count 1
    Assert-True $script:TestEvents[0].Context.LockMain
    Assert-True ($null -ne $script:TestEvents[0].Context.Failure)
}
Case 'Navigateur OU : deux enfants, controle WPF reel' {
    $script:PestoOUChildrenWorker={param($r);[pscustomobject]@{Name='A';DN="OU=A,$($r.DN)"};[pscustomobject]@{Name='B';DN="OU=B,$($r.DN)"}}
    $item=[Windows.Controls.TreeViewItem]::new();$item.Tag='DC=test,DC=invalid'
    Load-OUChildren $item
    Wait-PestoTestIdle
    Assert-Equal $item.Items.Count 2
    Assert-Equal $item.Items[0].Header 'A'
    Assert-Equal $item.Items[1].Header 'B'
}
Case 'Navigateur OU vide : une indication, pas une OU sans nom' {
    $script:PestoOUChildrenWorker={param($r);$null}
    $item=[Windows.Controls.TreeViewItem]::new();$item.Tag='DC=test,DC=invalid'
    Load-OUChildren $item
    Wait-PestoTestIdle
    Assert-Equal $item.Items.Count 1
    Assert-Equal $item.Items[0].Header '(aucune sous-OU)'
    Assert-Equal $item.Items[0].IsEnabled $false
}
Case 'Navigateur OU en erreur : Write-Log retrouve la portee Pesto' {
    $script:PestoOUChildrenWorker={param($r);throw 'ou-error'}
    $item=[Windows.Controls.TreeViewItem]::new();$item.Tag='DC=test,DC=invalid'
    Load-OUChildren $item
    Wait-PestoTestIdle
    Assert-Equal $item.Items.Count 1
    Assert-Equal $item.Items[0].IsEnabled $false
    Assert-Equal $script:TestLogs.Count 1
    Assert-Equal $script:TestMessages.Count 0
}
Case 'Validation config : fonctions du script retrouvees, ecriture mockee' {
    $script:TestWrite=$null
    $ctx=[pscustomobject]@{Json=[pscustomobject]@{Text='{"Invalid":false}'};Errors=[pscustomobject]@{Text=''};Window=[pscustomobject]@{Tag=$null;DialogResult=$null};Path='never-written.json'}
    Invoke-PestoConfigRepairSave ([pscustomobject]@{Tag=$ctx}) ([EventArgs]::Empty)
    Assert-Equal $ctx.Errors.Text ''
    Assert-True $ctx.Window.DialogResult
    Assert-Equal $script:TestWrite.Path 'never-written.json'
    Assert-True $script:TestWrite.Backup
}
Case 'Validation config refusee : aucune sauvegarde' {
    $script:TestWrite=$null
    $ctx=[pscustomobject]@{Json=[pscustomobject]@{Text='{"Invalid":true}'};Errors=[pscustomobject]@{Text=''};Window=[pscustomobject]@{Tag=$null;DialogResult=$null};Path='never-written.json'}
    Invoke-PestoConfigRepairSave ([pscustomobject]@{Tag=$ctx}) ([EventArgs]::Empty)
    Assert-True ($null -eq $script:TestWrite)
    Assert-True ($ctx.Errors.Text -match 'refusee')
    Assert-True ($null -eq $ctx.Window.DialogResult)
}
Case 'JSON invalide : erreur inline et aucune sauvegarde' {
    $script:TestWrite=$null
    $ctx=[pscustomobject]@{Json=[pscustomobject]@{Text='{invalid-json'};Errors=[pscustomobject]@{Text=''};Window=[pscustomobject]@{Tag=$null;DialogResult=$null};Path='never-written.json'}
    Invoke-PestoConfigRepairSave ([pscustomobject]@{Tag=$ctx}) ([EventArgs]::Empty)
    Assert-True ($null -eq $script:TestWrite)
    Assert-True (-not [string]::IsNullOrWhiteSpace($ctx.Errors.Text))
}
$failed=@($script:TestResults|Where-Object{-not $_.Passed}).Count
$report=[ordered]@{
    Version='17.0-RC3';Utc=[DateTime]::UtcNow.ToString('o');PowerShell=$PSVersionTable.PSVersion.ToString()
    SourcePath=$SourcePath;SourceSHA256=(Get-FileHash -LiteralPath $SourcePath -Algorithm SHA256).Hash
    Scope='Windows PowerShell 5.1, portee de script enfant, vrais runspaces/DispatcherTimer et TreeViewItem WPF ; workers et effets AD/configuration simules. Pas de lancement complet de Pesto.'
    Total=$script:TestResults.Count;Passed=($script:TestResults.Count-$failed);Failed=$failed;Results=$script:TestResults.ToArray()
}
$report|ConvertTo-Json -Depth 7|Set-Content -LiteralPath $ReportPath -Encoding UTF8
if($failed){throw "$failed test(s) asynchrones en echec. Rapport : $ReportPath"}
Write-Host "Tests asynchrones reussis : $($script:TestResults.Count). Rapport : $ReportPath"
