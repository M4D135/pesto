#requires -Version 5.1
# Sources chargées par AST uniquement : aucun démarrage UI, import AD ou commande Windows.
param([string]$ReportPath='')
$ErrorActionPreference='Stop';Set-StrictMode -Off
$root=Split-Path $PSScriptRoot -Parent;$definitions=@{};$core=$null
foreach($file in Get-ChildItem (Join-Path $root 'wad') -Filter 'Pesto-*.ps1' -File){
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw ($file.Name+': '+($errors.Message -join '; '))}
    foreach($node in $ast.EndBlock.Statements){
        if($node -is [Management.Automation.Language.FunctionDefinitionAst]){$definitions[$node.Name]=$node.Extent.Text}
    }
    if($file.Name -eq 'Pesto-Core.ps1'){$core=$ast}
}
foreach($definition in $definitions.Values){. ([scriptblock]::Create($definition))}
foreach($node in $core.EndBlock.Statements){
    if($node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -in @('$script:PestoWorkerCoreNames','$script:PestoPreflightWorker')){
        . ([scriptblock]::Create($node.Extent.Text))
    }
}
$script:PestoWorkerCoreSourceCache=$null
$checks=[Collections.Generic.List[object]]::new()
function Test-WorkerContract {
    param([string]$Name,[scriptblock]$Body)
    try{& $Body;$checks.Add([pscustomobject]@{Name=$Name;Passed=$true})}
    catch{$checks.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message})}
}
function Assert-WorkerClosure {
    param([string]$Source,[string[]]$Bootstrap=@())
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseInput($Source,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw ($errors.Message -join '; ')}
    $functions=@($ast.EndBlock.Statements|Where-Object{$_ -is [Management.Automation.Language.FunctionDefinitionAst]})
    $names=@($functions.Name)+$Bootstrap
    if(-not $functions.Count){throw 'Source worker vide.'}
    foreach($fn in $functions){
        foreach($command in $fn.FindAll({param($n)$n -is [Management.Automation.Language.CommandAst]},$true)){
            $called=$command.GetCommandName()
            if($called -and $definitions.ContainsKey($called) -and $called -notin $names){throw ($fn.Name+' dépend de '+$called+' absent du worker.')}
        }
    }
}
$bootstrap=@('Write-Log','Add-LogLine','Show-MsgError','Show-MsgWarning','Show-MsgInfo','Confirm-YesNo','Invoke-DoEvents','Wait-Pumped')
Test-WorkerContract 'Queue worker exports every product function it calls' {Assert-WorkerClosure (Get-PestoWorkerCoreSource) $bootstrap}
Test-WorkerContract 'Join worker exports every product function it calls' {Assert-WorkerClosure (Get-PestoJoinWorkerSource) $bootstrap}
Test-WorkerContract 'Direct worker exports every product function it calls' {Assert-WorkerClosure ((Get-PestoWorkerCoreSource)+(Get-PestoDirectSupportSource)) $bootstrap}
Test-WorkerContract 'Preflight worker exports every product function it calls' {Assert-WorkerClosure (Get-PestoPreflightSource) $bootstrap}
Test-WorkerContract 'Directory projection has no missing product functions' {Assert-WorkerClosure (Get-PestoDirectoryProjectionSource)}
Test-WorkerContract 'Worker source cache is stable within the process' {
    $first=Get-PestoWorkerCoreSource;$second=Get-PestoWorkerCoreSource
    if($first -cne $second -or -not $script:PestoWorkerCoreSourceCache){throw 'Cache de source instable.'}
}

# Contrat exécuté : vrais producteurs Direct/lot et vrai worker dans un runspace.
# Seules les surfaces WPF et les lectures AD sont remplacées. Aucun accès réseau.
if(-not ('Windows.Controls.DataGridEditingUnit' -as [type])){
    Add-Type 'namespace Windows.Controls { public enum DataGridEditingUnit { Cell, Row } }'
}
function Assert-Contract {param($Condition,[string]$Message='Contrat non respecté.');if(-not $Condition){throw $Message}}
function Test-PestoGlobalSafetyBarrier {return $false}
function Test-PestoDirectTargetBarrier {param($Computer);return $false}
function Test-PestoAsyncOperationRunning {param($Name);return $false}
function Get-PestoDirectFormPlan {return $script:FixturePlan}
function Get-PestoDirectPlanErrors {param($Plan);return @()}
function Get-PestoPlanSignature {param($Plan);return [string]$Plan.Nom_du_PC}
function Get-PestoConfigurationSignature {param($Config);return 'TEST'}
function Set-PestoDirectBusy {param([bool]$Busy);$script:DirectBusy=$Busy}
function Update-PestoSuiteUI {}
function Set-PestoQueueUiLocked {param($Locked)}
function Update-QueueButtons {}
function Start-PestoPilotagePulse {}
function Update-PestoQueueRenamePlan {param($Row)}
function Write-Log {param($Message,$Level,$ErrorRecord,$Context);$script:LastFailure=$ErrorRecord}
function Show-MsgWarning {param($Text);throw $Text}
function Show-MsgInfo {param($Text);throw $Text}
function Show-MsgError {param($Text);throw $Text}
function Test-PestoNameReservedByOther {param($Name);return $false}
function Format-OUPath {param($OU);return $OU}
function Confirm-YesNo {param($Msg,$Confirm);$script:ConfirmCount++;return $false}
function Start-PestoDirectAction {param($Plan);throw 'MUTATION INTERDITE PAR CE TEST'}
function Start-PestoAsyncOperation {
    param($Name,$ScriptBlock,$ArgumentList,$TimeoutSec,$CallbackContext,$OnSuccess,$OnError)
    $script:Captured=[pscustomobject]@{Name=$Name;Worker=$ScriptBlock;Arguments=$ArgumentList;Context=$CallbackContext;Success=$OnSuccess;Error=$OnError}
    return $true
}
function Reset-ContractFixture {
    $script:DirectBusy=$false;$script:Running=$false;$script:PreflightRunning=$false;$script:JoinBusy=$false
    $script:CfgRestartRequired=$false;$script:JoinLocked=$false;$script:DirectResumePlan=$null;$script:GUI=$false
    $script:INDOMAIN=$true;$script:PRD=$true;$script:CLEAR_PROTECTION=$true;$script:EDIT_ROW_INDEX=-1
    $script:CFG=[pscustomobject]@{CONF=@([pscustomobject]@{EntraPolicy='Auto'});POLICY=[pscustomobject]@{Schema=1}}
    $script:DC='dc01.example.local';$script:DOMAINE='example.local';$script:PREFIXE='111301';$script:cred=$null
    $script:OU=@{ROOT='OU=Postes,DC=example,DC=local'};$script:OUV=@{Org='OU=Sites,OU=Postes,DC=example,DC=local'}
    $script:FixturePlan=[pscustomobject]@{Nom_du_PC='P111301PR765129';Nouveau_Nom='P111301VA765001';OU_Actuelle='OU=PR,OU=Sites,OU=Postes,DC=example,DC=local';OU_Destination='OU=VA,OU=Sites,OU=Postes,DC=example,DC=local';Objet_GUID='12345678-1111-2222-3333-123456789012';Renommer=$true;Deplacer=$true;Reboot=$false;ConfigStamp='TEST'}
    $script:TxtPCName=[pscustomobject]@{Text=$script:FixturePlan.Nom_du_PC};$script:BasePath=Join-Path $root 'wad'
    $script:Captured=$null;$script:LastFailure=$null;$script:DirectCheckedKey='';$script:ConfirmCount=0
    $script:table=New-QueueTable
    foreach($index in 0..1){
        $row=$script:table.NewRow()
        foreach($key in @('Nom_du_PC','Nouveau_Nom','OU_Actuelle','OU_Destination','Objet_GUID','Renommer','Deplacer','Reboot','ConfigStamp')){$row[$key]=$script:FixturePlan.$key}
        if($index -eq 1){$row.Nom_du_PC='P111301PR765130';$row.Renommer=$false;$row.Nouveau_Nom=''}
        $row.Traiter=$true;[void]$script:table.Rows.Add($row)
    }
    $script:Grid=[pscustomobject]@{};$script:Grid|Add-Member ScriptMethod CommitEdit {param($Unit,$Exit);return $true}
}
$script:LocalADSource=@'
function Import-PestoADModule {
    param($ADModulePath)
    $Request.Progress.Loaded=$true
    if($Request.TestMode -eq 'ImportFailure'){throw 'fixture module refusal'}
}
function Get-ADComputer {
    [CmdletBinding()]param($LDAPFilter,$ResultSetSize,$Properties,$Server,$Credential)
    if($Request.TestMode -eq 'Denied'){throw [UnauthorizedAccessException]::new('fixture AD access denied')}
    foreach($candidate in $Request.Items){
        if($LDAPFilter.Contains('(name='+$candidate.Nom_du_PC+')')){
            return [pscustomobject]@{Name=$candidate.Nom_du_PC;DistinguishedName=('CN='+$candidate.Nom_du_PC+','+$candidate.OU_Actuelle);ObjectGUID=$candidate.Objet_GUID;Enabled=$true;ProtectedFromAccidentalDeletion=$false}
        }
    }
}
function Get-ADOrganizationalUnit {
    [CmdletBinding()]param($Identity,$Server,$Credential)
    if($Request.TestMode -eq 'CancelAfterFirst'){$Request.Progress.Cancelled=$true}
    return [pscustomobject]@{DistinguishedName=$Identity;ObjectGUID='bbbbbbbb-1111-2222-3333-123456789012'}
}
function Rename-Computer {throw 'MUTATION INTERDITE'}
function Add-Computer {throw 'MUTATION INTERDITE'}
function Move-ADObject {throw 'MUTATION INTERDITE'}
function Set-ADObject {throw 'MUTATION INTERDITE'}
function Restart-Computer {throw 'MUTATION INTERDITE'}
'@
function Invoke-CapturedPreflight {
    param([string]$Mode='Success')
    $request=$script:Captured.Arguments[0]
    # Empêche la sonde ICMP du premier poste. Le second fait un déplacement seul.
    $request.Host=$script:FixturePlan.Nom_du_PC
    $request|Add-Member -NotePropertyName TestMode -NotePropertyValue $Mode -Force
    $ps=[PowerShell]::Create()
    try{
        [void]$ps.AddScript($script:Captured.Worker.ToString()).AddArgument($request).AddArgument(([string]$script:Captured.Arguments[1]+"`n"+$script:LocalADSource))
        $invokeError=$null;$out=@()
        try{$out=@($ps.Invoke())}catch{$invokeError=$_}
        $errors=@($ps.Streams.Error);if($invokeError -and -not $errors.Count){$errors=@($invokeError)}
        return [pscustomobject]@{Output=$out;Errors=$errors;State=[string]$ps.InvocationStateInfo.State;Request=$request}
    }finally{$ps.Dispose()}
}
Test-WorkerContract 'Preflight progress is synchronized and independent for each request' {
    $a=New-PestoPreflightProgress -Total 1;$b=New-PestoPreflightProgress -Total 2
    Assert-Contract ($a.IsSynchronized -and $b.IsSynchronized -and $a.Total -eq 1 -and $b.Total -eq 2)
    $a.Results.Enqueue('A');$a.Cancelled=$true
    Assert-Contract ($b.Results.Count -eq 0 -and -not $b.Cancelled)
}
Test-WorkerContract 'Real direct request completes the shared worker and reaches user confirmation' {
    Reset-ContractFixture;Start-PestoDirectPreflight -Execute
    Assert-Contract ($script:Captured.Name -eq 'DirectPreflight')
    $run=Invoke-CapturedPreflight
    Assert-Contract ($run.State -eq 'Completed' -and $run.Errors.Count -eq 0) ($run.Errors -join '; ')
    Assert-Contract ($run.Output.Count -eq 1 -and @($run.Output[0].Results).Count -eq 1)
    Assert-Contract ($run.Output[0].Results[0].State -eq 'VÉRIFIÉ') $run.Output[0].Results[0].Detail
    Assert-Contract ($run.Request.Progress.Done -eq 1 -and $run.Request.Progress.Results.Count -eq 1)
    & $script:Captured.Success $run.Output[0] $script:Captured.Context
    Assert-Contract ($script:ConfirmCount -eq 1 -and $script:DirectCheckedKey -eq $script:FixturePlan.Nom_du_PC -and -not $script:DirectBusy)
    Assert-Contract (-not $script:LastFailure)
}
Test-WorkerContract 'Real queue producer shares progress with its callback and retains all results' {
    Reset-ContractFixture;Start-PestoQueuePreflight
    Assert-Contract ($script:Captured.Name -eq 'QueuePreflight')
    Assert-Contract ([object]::ReferenceEquals($script:Captured.Context.Progress,$script:Captured.Arguments[0].Progress))
    $run=Invoke-CapturedPreflight
    Assert-Contract ($run.State -eq 'Completed' -and $run.Errors.Count -eq 0) ($run.Errors -join '; ')
    Assert-Contract ($run.Output.Count -eq 1 -and @($run.Output[0].Results).Count -eq 2)
    Assert-Contract ($run.Request.Progress.Done -eq 2 -and $run.Request.Progress.Results.Count -eq 2)
    foreach($result in $run.Output[0].Results){Assert-Contract ($result.State -eq 'VÉRIFIÉ') $result.Detail}
}
Test-WorkerContract 'Cancelled queue retains exactly the row completed before cancellation' {
    Reset-ContractFixture;Start-PestoQueuePreflight;$run=Invoke-CapturedPreflight -Mode CancelAfterFirst
    Assert-Contract ($run.Errors.Count -eq 0 -and $run.Request.Progress.Cancelled)
    Assert-Contract ($run.Request.Progress.Done -eq 1 -and $run.Request.Progress.Results.Count -eq 1 -and @($run.Output[0].Results).Count -eq 1)
}
Test-WorkerContract 'AD refusal is returned as blocked and cannot reach direct confirmation' {
    Reset-ContractFixture;Start-PestoDirectPreflight -Execute;$run=Invoke-CapturedPreflight -Mode Denied
    Assert-Contract ($run.Errors.Count -eq 0 -and $run.Output[0].Results[0].State -eq 'BLOQUÉ')
    & $script:Captured.Success $run.Output[0] $script:Captured.Context
    Assert-Contract ($script:ConfirmCount -eq 0 -and -not $script:DirectCheckedKey -and $script:LastFailure)
}
Test-WorkerContract 'Import failure stays a worker error with no completed result' {
    Reset-ContractFixture;Start-PestoDirectPreflight;$run=Invoke-CapturedPreflight -Mode ImportFailure
    Assert-Contract ($run.State -eq 'Failed' -and $run.Errors.Count -gt 0 -and $run.Output.Count -eq 0)
    Assert-Contract ($run.Request.Progress.Results.Count -eq 0 -and $run.Request.Progress.Done -eq 0)
}
Test-WorkerContract 'Incomplete progress contract fails explicitly before importing AD' {
    Reset-ContractFixture;Start-PestoDirectPreflight
    $script:Captured.Arguments[0].Progress.Remove('Results');$run=Invoke-CapturedPreflight
    Assert-Contract ($run.State -eq 'Failed' -and ($run.Errors -join '; ') -like '*Contrat de progression*')
    Assert-Contract (-not $run.Request.Progress.Loaded -and $run.Output.Count -eq 0)
}


Test-WorkerContract 'Direct freshness accepts a recent result only within the two minute window' {
    Assert-PestoDirectPreflightFreshness -Utc ([DateTimeOffset]::UtcNow.AddSeconds(-30).ToString('o'))
    foreach($utc in @('', 'invalid', '2001-01-01T00:00:00Z', [DateTimeOffset]::UtcNow.AddMinutes(5).ToString('o'))){
        $refused=$false;try{Assert-PestoDirectPreflightFreshness -Utc $utc}catch{$refused=$true}
        Assert-Contract $refused ('Horodatage accepté : '+$utc)
    }
}
foreach($invalidTime in @('Missing','Malformed','Expired','Future')){
    Test-WorkerContract ('Direct callback refuses '+$invalidTime+' preflight before confirmation') {
        Reset-ContractFixture;Start-PestoDirectPreflight -Execute;$run=Invoke-CapturedPreflight
        $run.Output[0].Results[0].Utc=switch($invalidTime){
            Missing {''};Malformed {'not a timestamp'};Expired {'2001-01-01T00:00:00Z'}
            Future {[DateTimeOffset]::UtcNow.AddMinutes(5).ToString('o')}
        }
        & $script:Captured.Success $run.Output[0] $script:Captured.Context
        Assert-Contract ($script:ConfirmCount -eq 0 -and -not $script:DirectCheckedKey -and $script:LastFailure)
    }
}
# Restaurer le vrai point d'entrée d'exécution : les refus ci-dessous doivent
# intervenir avant journal, reçu, lancement du worker ou commande Windows.
. ([scriptblock]::Create($definitions['Start-PestoDirectAction']))
Test-WorkerContract 'Expired preflight cannot enter the direct execution boundary' {
    Reset-ContractFixture;$failure=$null
    try{Start-PestoDirectAction -Plan $script:FixturePlan -PreflightUtc '2001-01-01T00:00:00Z'}catch{$failure=$_}
    Assert-Contract ($failure -and $failure.Exception.Message -like '*deux minutes*' -and -not $script:Captured)
}
Test-WorkerContract 'Expiry during modal confirmation is rejected without starting another worker' {
    Reset-ContractFixture;Start-PestoDirectPreflight -Execute;$run=Invoke-CapturedPreflight
    $script:ResultToExpire=$run.Output[0].Results[0]
    function Confirm-YesNo {
        param($Msg,$Confirm)
        $script:ConfirmCount++
        # Avancer l'âge observé sans attendre réellement 120 secondes.
        $script:ResultToExpire.Utc='2001-01-01T00:00:00Z'
        return $true
    }
    & $script:Captured.Success $run.Output[0] $script:Captured.Context
    Assert-Contract ($script:ConfirmCount -eq 1 -and $script:Captured.Name -eq 'DirectPreflight')
    Assert-Contract ($script:LastFailure.Exception.Message -like '*deux minutes*' -and -not $script:DirectCheckedKey -and -not $script:DirectBusy)
}

$failed=@($checks|Where-Object{-not $_.Passed}).Count
$report=[pscustomobject]@{Checks=$checks.ToArray();Failed=$failed;PowerShell=$PSVersionTable.PSVersion.ToString();WindowsExecuted=$false;ADExecuted=$false}
if($ReportPath){$report|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $ReportPath -Encoding UTF8}
$report|ConvertTo-Json -Depth 5
if($failed){exit 1}
