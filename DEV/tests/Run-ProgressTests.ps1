#requires -Version 5.1
[CmdletBinding()]
param([string]$SourcePath='',[string]$ReportPath='')
# Windows PowerShell 5.1 : $PSScriptRoot est vide dans les valeurs par défaut des paramètres (vu le 03/10).
if(-not $SourcePath){$SourcePath=Join-Path $PSScriptRoot '..\wad\Pesto-Core.ps1'}
if(-not $ReportPath){$ReportPath=Join-Path $PSScriptRoot 'windows-progress-results.json'}
$ErrorActionPreference='Stop';Set-StrictMode -Off
if($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){throw 'Windows PowerShell 5.1 requis.'}
if([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA'){throw 'Lancer TEST_PROGRESS.cmd (STA).'}
Add-Type -AssemblyName PresentationFramework,WindowsBase
# Pesto ne démarre JAMAIS ici : seules des définitions sélectionnées sont extraites.
# Aucun accès AD, aucune élévation et aucun redémarrage.
# Les fonctions testees ont quitte Pesto-Core.ps1 : le banc indexe tout le repertoire wad/ de la source indiquee.
$tokens=$null
$errors=[Collections.Generic.List[object]]::new()
$wadDir=Split-Path ([IO.Path]::GetFullPath($SourcePath)) -Parent
$defs=@{}
foreach($file in (Get-ChildItem -LiteralPath $wadDir -File | Where-Object{$_.Extension -eq '.ps1'} | Sort-Object Name)){
    $fileErrors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$fileErrors)
    foreach($e in $fileErrors){$errors.Add([pscustomobject]@{Extent=$e.Extent;Message=$e.Message})}
    foreach($node in $ast.EndBlock.Statements){if($node -is [Management.Automation.Language.FunctionDefinitionAst] -and -not $defs.ContainsKey($node.Name)){$defs[$node.Name]=$node.Extent.Text}}
}
if($errors.Count){throw (($errors|ForEach-Object{"$($_.Extent.StartLineNumber): $($_.Message)"})-join "`n")}
$load=@('New-PestoReadRunspacePool','Close-PestoReadRunspacePool','Get-PestoSessionReadPool','Enter-PestoReadRunspace','Exit-PestoReadRunspace','Test-PestoAsyncMutationName','Complete-PestoWorkerTiming','New-PestoQueueMonitor','Publish-PestoWorkerLog','Set-PestoWorkerStage','Assert-PestoWorkerMayContinue','Set-PestoQueueCancellationFence','Receive-PestoQueueEvents','Get-PestoQueueActivityText','Test-PestoQueueWorkerStillActive','Protect-PestoLogText','Test-PestoAsyncOperationRunning','Stop-PestoAsyncOperation','Invoke-PestoAsyncCallback','Start-PestoAsyncOperation','Invoke-PestoAsyncTimerTick','Reset-PestoSafetyLock')
foreach($name in $load){if(-not $defs.ContainsKey($name)){throw "Fonction absente : $name"};. ([scriptblock]::Create($defs[$name]))}
$script:Results=[Collections.Generic.List[object]]::new()
$script:Logs=[Collections.Generic.List[object]]::new();$script:Callbacks=[Collections.Generic.List[object]]::new();$script:Dialogs=[Collections.Generic.List[string]]::new()
$script:PestoAsyncOperations=@{};$script:PestoAsyncTimerOperations=@{}
$workerHelpers=(@('Protect-PestoLogText','Publish-PestoWorkerLog','Set-PestoWorkerStage','Assert-PestoWorkerMayContinue')|ForEach-Object{$defs[$_]})-join "`n"
function Add-LogLine {param($Text,$Kind);$script:Logs.Add([pscustomobject]@{Text=[string]$Text;Kind=$Kind})}
function Write-Log {param($Text,$Level,$Err,$Context);Add-LogLine ([string]$Text) $Level}
function Show-MsgError {param($Text,$Title);$script:Dialogs.Add([string]$Text)}
function Show-MsgWarning {param($Text,$Title);$script:Dialogs.Add([string]$Text)}
function Fail-PestoQueueCallback {param($Failure);throw "Callback de test en erreur : $($Failure.Exception.Message)"}
function Assert-True {param($Value,[string]$Message='Assertion non satisfaite');if(-not $Value){throw $Message}}
function Equal {param($Actual,$Expected);if($Actual -cne $Expected){throw "Attendu [$Expected], obtenu [$Actual]"}}
function Throws {param([scriptblock]$Body);$did=$false;try{&$Body}catch{$did=$true};Assert-True $did 'Exception attendue'}
function Pump {
    $frame=[Windows.Threading.DispatcherFrame]::new();$timer=[Windows.Threading.DispatcherTimer]::new();$timer.Interval=[TimeSpan]::FromMilliseconds(15)
    # Capture uniquement des objets .NET locaux, aucune fonction Pesto.
    $handler=[EventHandler]({param($s,$e);$s.Stop();$frame.Continue=$false}.GetNewClosure())
    $timer.Add_Tick($handler);$timer.Start()
    try{[Windows.Threading.Dispatcher]::PushFrame($frame)}finally{$timer.Stop();$timer.Remove_Tick($handler)}
}
function Until {
    param([scriptblock]$Condition,[int]$Milliseconds=7000)
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while(-not(&$Condition)){if($watch.ElapsedMilliseconds -ge $Milliseconds){throw 'Délai de test dépassé'};Pump}
}
function Idle {Until {$script:PestoAsyncTimerOperations.Count -eq 0}}
function Case {
    param([string]$Name,[scriptblock]$Body)
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $script:Logs.Clear();$script:Callbacks.Clear();$script:Dialogs.Clear();$script:PestoQueueMonitor=$null
    try{&$Body;$script:Results.Add([pscustomobject]@{Name=$Name;Passed=$true;Message='';Ms=$watch.ElapsedMilliseconds});Write-Host "OK $Name"}
    catch{$script:Results.Add([pscustomobject]@{Name=$Name;Passed=$false;Message=$_.Exception.Message;Ms=$watch.ElapsedMilliseconds});Write-Host "KO $Name : $($_.Exception.Message)"}
    finally{
        # Uniquement des workers de test limités à de courts calculs/Sleep.
        foreach($op in @($script:PestoAsyncTimerOperations.Values)){
            try{$op.Timer.Stop();$op.Timer.Remove_Tick($op.TickHandler);if(-not $op.Async.IsCompleted){[void]$op.PowerShell.BeginStop($null,$null)}}catch{}
            $wait=[Diagnostics.Stopwatch]::StartNew()
            while($op.Async -and -not $op.Async.IsCompleted -and $wait.ElapsedMilliseconds -lt 4000){[Threading.Thread]::Sleep(10)}
            if(-not $op.Async -or $op.Async.IsCompleted){try{$op.PowerShell.Dispose();$op.Runspace.Close();$op.Runspace.Dispose()}catch{}}
        }
        $script:PestoAsyncOperations.Clear();$script:PestoAsyncTimerOperations.Clear()
        if($script:PestoReadPool){Close-PestoReadRunspacePool $script:PestoReadPool;$script:PestoReadPool=$null}
    }
}
$success={param($value);$script:Callbacks.Add([pscustomobject]@{Kind='success';Value=$value})}
$failure={param($value);$script:Callbacks.Add([pscustomobject]@{Kind='error';Value=$value})}
Case 'Parseur PowerShell natif : source complet' {Equal $errors.Count 0}
Case 'Parseur natif : script du helper UAC' {
    $match=[regex]::Match($defs['New-PestoElevatedHelperScript'],"(?ms)\`$helper=@'\r?\n(.*?)\r?\n'@")
    Assert-True $match.Success 'Helper absent';$t=$null;$e=$null
    [void][Management.Automation.Language.Parser]::ParseInput($match.Groups[1].Value,[ref]$t,[ref]$e);Equal $e.Count 0
}
Case 'Moniteur initial sans mutation' {$m=New-PestoQueueMonitor 'TEST-PC';Equal $m.MutationStarted $false;Equal $m.CancelRequested $false;Equal $m.Events.Count 0}
Case 'Étape publiée immédiatement' {$script:PestoQueueMonitor=New-PestoQueueMonitor 'TEST-PC';Set-PestoWorkerStage 'Précontrôle' 'lecture seulement';Equal $script:PestoQueueMonitor.Stage.Name 'Précontrôle';Equal $script:PestoQueueMonitor.Events.Count 1}
Case 'Masquage des clés de mot de passe dans les traces' {$script:PestoQueueMonitor=New-PestoQueueMonitor 'TEST-PC';Publish-PestoWorkerLog 'password=FAUX_SECRET';$e=$null;[void]$script:PestoQueueMonitor.Events.TryDequeue([ref]$e);Assert-True ($e.Text -notmatch 'FAUX_SECRET')}
Case 'Drain FIFO sans duplication' {$script:PestoQueueMonitor=New-PestoQueueMonitor 'TEST-PC';Publish-PestoWorkerLog 'premier';Publish-PestoWorkerLog 'second';Receive-PestoQueueEvents $script:PestoQueueMonitor;Receive-PestoQueueEvents $script:PestoQueueMonitor;Equal $script:Logs.Count 2;Assert-True ($script:Logs[0].Text -match 'premier')}
Case 'Drain borné pour laisser le Dispatcher disponible' {$script:PestoQueueMonitor=New-PestoQueueMonitor 'TEST-PC';1..5|ForEach-Object{Publish-PestoWorkerLog "test $_"};Receive-PestoQueueEvents $script:PestoQueueMonitor -Maximum 2;Equal $script:Logs.Count 2;Equal $script:PestoQueueMonitor.Events.Count 3}
Case 'Pied de page : étape et PID du helper' {$m=New-PestoQueueMonitor 'TEST-PC';$m.HelperPid=1234;Assert-True ((Get-PestoQueueActivityText $m) -match '1234')}
Case 'Barrière : lecture ne marque pas de mutation' {$script:PestoQueueMonitor=New-PestoQueueMonitor 'TEST-PC';Assert-PestoWorkerMayContinue;Equal $script:PestoQueueMonitor.MutationStarted $false}
Case 'Barrière : mutation annoncée avant appel' {$script:PestoQueueMonitor=New-PestoQueueMonitor 'TEST-PC';Assert-PestoWorkerMayContinue -Mutation;Equal $script:PestoQueueMonitor.MutationStarted $true}
Case 'Barrière : aucune étape nouvelle après expiration' {$script:PestoQueueMonitor=New-PestoQueueMonitor 'TEST-PC';Set-PestoQueueCancellationFence $script:PestoQueueMonitor;Throws {Assert-PestoWorkerMayContinue -Mutation};Equal $script:PestoQueueMonitor.MutationStarted $false}
Case 'Compatibilité des fonctions isolées sans moniteur' {$script:PestoQueueMonitor=$null;Assert-PestoWorkerMayContinue -Mutation;Set-PestoWorkerStage 'sans UI'}
Case 'Worker réel en STA sur demande' {[void](Start-PestoAsyncOperation -Name 'STAProbe' -ApartmentState STA -ScriptBlock {[Threading.Thread]::CurrentThread.ApartmentState.ToString()} -OnSuccess $success -OnError $failure);Idle;Equal $script:Callbacks.Count 1;Equal $script:Callbacks[0].Value 'STA'}
Case 'Lecture AD : MTA reste le défaut' {[void](Start-PestoAsyncOperation -Name 'MTAProbe' -ScriptBlock {[Threading.Thread]::CurrentThread.ApartmentState.ToString()} -OnSuccess $success -OnError $failure);Idle;Equal $script:Callbacks[0].Value 'MTA'}
Case 'Messages visibles AVANT la fin du worker réel' {
    $m=New-PestoQueueMonitor 'TEST-PC'
    $worker={param($m,$src);. ([scriptblock]::Create($src));$script:PestoQueueMonitor=$m;Set-PestoWorkerStage 'Phase visible';[Threading.Thread]::Sleep(1200);'terminé'}
    [void](Start-PestoAsyncOperation -Name 'Live' -QueueMonitor $m -ScriptBlock $worker -ArgumentList @($m,$workerHelpers) -OnSuccess $success -OnError $failure)
    Until {$script:Logs.Count -gt 0};Assert-True (-not $script:PestoAsyncOperations['Live'].Async.IsCompleted) 'Le premier message ne doit pas attendre la fin';Idle;Equal $script:Callbacks[0].Value 'terminé'
}
Case 'Expiration : erreur unique, worker encore suivi, aucune mutation différée' {
    $m=New-PestoQueueMonitor 'TEST-PC';$m.ProbeMutations=0
    $worker={param($m,$src);. ([scriptblock]::Create($src));$script:PestoQueueMonitor=$m;Set-PestoWorkerStage 'Attente simulée';[Threading.Thread]::Sleep(2300);Assert-PestoWorkerMayContinue -Mutation;$m.ProbeMutations++;'succès interdit'}
    [void](Start-PestoAsyncOperation -Name 'QueueAction' -ApartmentState STA -QueueMonitor $m -TimeoutSec 1 -ScriptBlock $worker -ArgumentList @($m,$workerHelpers) -OnSuccess $success -OnError $failure)
    Until {$script:Callbacks.Count -gt 0};Equal $script:Callbacks[0].Kind 'error';Assert-True (Test-PestoAsyncOperationRunning 'QueueAction');Assert-True (Test-PestoQueueWorkerStillActive);Assert-True $m.CancelRequested
    Assert-True ($script:PestoAsyncOperations['QueueAction'].PowerShell.InvocationStateInfo.State.ToString() -ne 'Stopping') 'Pas de BeginStop pendant la mutation'
    Idle;Equal $m.ProbeMutations 0;Equal $script:Callbacks.Count 1;Assert-True (-not(Test-PestoAsyncOperationRunning 'QueueAction'))
}
Case 'Succès tardif non publié après expiration' {
    $m=New-PestoQueueMonitor 'TEST-PC'
    [void](Start-PestoAsyncOperation -Name 'QueueAction' -ApartmentState STA -QueueMonitor $m -TimeoutSec 1 -ScriptBlock {[Threading.Thread]::Sleep(1600);[pscustomobject]@{Action=[pscustomobject]@{ExitCode=20;ExitMsg='FAUX SUCCÈS TARDIF'}}} -OnSuccess $success -OnError $failure)
    Idle;Equal $script:Callbacks.Count 1;Equal $script:Callbacks[0].Kind 'error';Assert-True (@($script:Logs|Where-Object{$_.Text -match 'verrou reste actif'}).Count -gt 0)
}
Case 'Une mutation active ne peut pas être remplacée' {
    $m=New-PestoQueueMonitor 'TEST-PC'
    [void](Start-PestoAsyncOperation -Name 'QueueAction' -ApartmentState STA -QueueMonitor $m -ScriptBlock {[Threading.Thread]::Sleep(250);'original'} -OnSuccess $success)
    $second=Start-PestoAsyncOperation -Name 'QueueAction' -Replace -ScriptBlock {'INTERDIT'} -OnSuccess $success;Equal $second $false;Idle;Equal $script:Callbacks.Count 1;Equal $script:Callbacks[0].Value 'original'
}
Case 'Arrêt coopératif conserve le suivi du worker' {
    $m=New-PestoQueueMonitor 'TEST-PC'
    [void](Start-PestoAsyncOperation -Name 'QueueAction' -ApartmentState STA -QueueMonitor $m -ScriptBlock {[Threading.Thread]::Sleep(250);'retour'} -OnSuccess $success)
    Stop-PestoAsyncOperation 'QueueAction';Assert-True $m.CancelRequested;Assert-True (Test-PestoAsyncOperationRunning 'QueueAction');Idle;Equal $script:Callbacks.Count 0
}
Case 'Déverrouillage refusé tant que le worker est actif' {
    $script:PreflightRunning=$false;$script:Running=$false;$script:MutationUncertain=$true
    $m=New-PestoQueueMonitor 'TEST-PC'
    [void](Start-PestoAsyncOperation -Name 'QueueAction' -ApartmentState STA -QueueMonitor $m -ScriptBlock {[Threading.Thread]::Sleep(250);'retour'} -OnSuccess $success)
    Reset-PestoSafetyLock;Assert-True $script:MutationUncertain;Assert-True ($script:Dialogs.Count -gt 0);Idle
}
Case 'Timeout des lectures : ancien contrat conservé' {
    [void](Start-PestoAsyncOperation -Name 'ReadOnly' -TimeoutSec 1 -ScriptBlock {Start-Sleep -Seconds 4;'trop tard'} -OnSuccess $success -OnError $failure)
    Idle;Equal $script:Callbacks.Count 1;Equal $script:Callbacks[0].Kind 'error'
}
$failed=@($script:Results|Where-Object{-not $_.Passed}).Count
$report=[ordered]@{Version='17.0-RC9';Engine=[string]$PSVersionTable.PSVersion;Platform=[string][Environment]::OSVersion;Utc=[DateTime]::UtcNow.ToString('o');Scope='Parseur natif, fonctions isolées, vrais runspaces et timers WPF. Aucune connexion AD, aucun UAC, aucune mutation.';Total=$script:Results.Count;Failed=$failed;Results=$script:Results.ToArray()}
$report|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $ReportPath -Encoding UTF8
Write-Host ("Tests : {0}, échecs : {1}. Rapport : {2}" -f $script:Results.Count,$failed,$ReportPath)
if($failed){exit 1}else{exit 0}
