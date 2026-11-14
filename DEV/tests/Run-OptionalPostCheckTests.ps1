#requires -Version 5.1
# Fonctions réelles extraites par AST. Doubles Windows/AD ; fichiers de coordination isolés.
param([string]$ReportPath='')
$ErrorActionPreference='Stop';Set-StrictMode -Off
$dev=Split-Path $PSScriptRoot -Parent;$defs=@{};$asts=@{}
foreach($file in Get-ChildItem (Join-Path $dev 'wad') -Filter 'Pesto-*.ps1' -File){
    $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw ($file.Name+': '+($errors.Message -join '; '))}
    $asts[$file.Name]=$ast
    foreach($fn in $ast.EndBlock.Statements){if($fn -is [Management.Automation.Language.FunctionDefinitionAst]){$defs[$fn.Name]=$fn.Extent.Text}}
}
foreach($definition in $defs.Values){. ([scriptblock]::Create($definition))}
foreach($node in $asts['Pesto-Core.ps1'].EndBlock.Statements){if($node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq '$script:PestoWorkerCoreNames'){. ([scriptblock]::Create($node.Extent.Text))}}
foreach($node in $asts['Pesto-Direct.ps1'].EndBlock.Statements){if($node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq '$script:PestoDirectWorker'){. ([scriptblock]::Create($node.Extent.Text))}}
$script:FixtureRoot=Join-Path $PSScriptRoot ('optional-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($script:FixtureRoot)
$checks=[Collections.Generic.List[object]]::new()
function Assert {param($Value,[string]$Why='Assertion failed');if(-not $Value){throw $Why}}
function Throws {param([scriptblock]$Action);$thrown=$false;try{& $Action|Out-Null}catch{$thrown=$true};Assert $thrown 'Expected rejection'}
function Clone {param($Value);$Value|ConvertTo-Json -Depth 12|ConvertFrom-Json}
function New-Plan {
    [pscustomobject]@{Nom_du_PC='OLD-PC';Nouveau_Nom='P111301AA765001';Domain='example.test';DC='dc.example.test';Objet_GUID='11111111-1111-1111-1111-111111111111';OU_Actuelle='OU=AA,DC=example,DC=test';OU_Destination='OU=BB,DC=example,DC=test';Renommer=$true;Deplacer=$false;Reboot=$false;TargetOUGuid='22222222-2222-2222-2222-222222222222';ConfigStamp='test'}
}
function New-Completed {
    [pscustomobject]@{Schema=2;OperationId=[Guid]::NewGuid().ToString('N');Phase='PendingRestart';ResultCode=[int]20;Plan=(New-Plan);OperatorMachineId='operator';StartedUtc='2026-01-01T08:00:00Z';FinishedUtc='2026-01-01T08:30:00Z';UpdatedUtc='2026-01-01T08:30:00Z';VerifiedUtc='';Rename='Confirmed';Move='NotRequested';Entra='NotRequested';Protection='Restored';JoinEvidence=$null;Sequence=0;Timeline=@();ResumeFrom='';ResultMessage='accepted';Coordination=$null}
}
function New-JoinReceipt {
    [pscustomobject]@{Schema=1;Version='1.0';OperationId=[Guid]::NewGuid().ToString('N');Phase='PendingRestart';Utc='2026-01-01T08:30:00Z';MachineId='operator';BootUtc='2026-01-01T08:00:00Z';Computer='OLD-PC';NewName='P111301AA765001';Domain='example.test';DC='dc.example.test';OU='OU=AA,DC=example,DC=test';Reference='';Account='';Message='accepted'}
}
function Reset-Fixture {
    $script:SIM=$false;$script:GUI=$false;$script:DirectLocked=$false;$script:DirectReceipt=$null;$script:SavedJoin=$null;$script:SavedDirect=$null;$script:DOMAINE='example.test';$script:ExpectedObjectGuid='11111111-1111-1111-1111-111111111111'
    $script:HostMachineId='operator';$script:DirectBusy=$false;$script:DirectRunning=$false;$script:PestoWorkerCoreSourceCache=$null
    $script:Local=[pscustomobject]@{MachineId='operator';BootUtc='2026-01-02T08:00:00Z';Computer='P111301AA765001';ActiveName='P111301AA765001';ConfiguredName='P111301AA765001';Domain='example.test';PartOfDomain=$true;DomainRole=1;PendingRename=$false;SecureChannel=$null;Admin=$true}
    $script:Secure=$true;$script:SecureCalls=0;$script:LocalCalls=0;$script:Ledger=@();$script:Written=@();$script:ActiveIntervention=$null
    $script:CoordRoot=Join-Path $script:FixtureRoot ([Guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory((Join-Path $script:CoordRoot 'locks'))
    $script:PestoPolicy=[pscustomobject]@{CoordinationRoot=$script:CoordRoot}
}
function Case {param($Name,[scriptblock]$Body);Reset-Fixture;try{& $Body;$checks.Add([pscustomobject]@{Name=$Name;Passed=$true})}catch{$checks.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message;Location=$_.ScriptStackTrace})}}
# All operating-system and persistent operational stores are replaced before any invocation.
function Get-PestoJoinLocalStatus {$script:LocalCalls++;Clone $script:Local}
function Test-ComputerSecureChannel {[CmdletBinding()]param($Server);$script:SecureCalls++;if($script:Secure -is [string] -and $script:Secure -ceq 'throw'){throw 'channel unavailable'};return $script:Secure}
function Get-ItemProperty {[CmdletBinding()]param($LiteralPath,$Name);[pscustomobject]@{MachineGuid='operator'}}
function Get-PestoDirectStatePath {Join-Path $script:FixtureRoot 'direct.json'}
function Read-PestoDirectReceipt {param($Path);if($script:SavedDirect){return $script:SavedDirect};return $script:DirectReceipt}
function Get-PestoJoinStatePath {Join-Path $script:FixtureRoot 'join.json'}
function Read-PestoJoinReceipt {param($Path);return $script:SavedJoin}
function Get-PestoInterventionRoot {return $script:FixtureRoot}
function Get-PestoInterventions {return $script:Ledger}
function Write-PestoIntervention {param($Receipt);$script:Written+=,(Clone $Receipt)}
function Get-PestoCoordinationRoot {param($Policy,$Domain);if($Policy.CoordinationRoot){return $script:CoordRoot};return ''}
function Update-QueueButtons {};function Update-AddButton {};function Update-PestoSuiteUI {}
function Write-Log {};function Get-PestoUxNom {param($Name);return $Name}
foreach($code in @(10,20,77)){
    Case "Completed code $code is optional without changing receipt" {$r=New-Completed;$r.ResultCode=$code;$before=$r|ConvertTo-Json -Depth 8;Assert (Test-PestoOptionalPostCheckReceipt $r);Assert (($r|ConvertTo-Json -Depth 8) -ceq $before)}
}
Case 'JSON integer from disk is accepted' {$r=Clone (New-Completed);Assert (Test-PestoOptionalPostCheckReceipt $r)}
foreach($code in @('20',20.0,$true,$null,32,89,96,97,98,99)){
    Case "Non-success or untyped code [$code] is not optional" {$r=New-Completed;$r.ResultCode=$code;Assert (-not(Test-PestoOptionalPostCheckReceipt $r))}
}
foreach($phase in @('Running','Uncertain','Partial','Protection','MoveReady','Failed','Verified','pendingrestart','')){
    Case "Phase [$phase] does not bypass protection" {$r=New-Completed;$r.Phase=$phase;Assert (-not(Test-PestoOptionalPostCheckReceipt $r))}
}
Case 'Property Outcome does not replace Phase' {$r=[pscustomobject]@{Outcome='PendingRestart';ResultCode=20};Assert (-not(Test-PestoOptionalPostCheckReceipt $r))}
Case 'A direct receipt without code cannot masquerade as legacy join' {$r=New-Completed;$r.PSObject.Properties.Remove('ResultCode');Assert (-not(Test-PestoOptionalPostCheckReceipt $r))}
foreach($protection in @('Requested','Disabled','Uncertain','')){
    Case "Protection [$protection] remains blocking" {$r=New-Completed;$r.Protection=$protection;Assert (-not(Test-PestoOptionalPostCheckReceipt $r))}
}
Case 'Requested mutation is never optional' {$r=New-Completed;$r.Move='Requested';Assert (-not(Test-PestoOptionalPostCheckReceipt $r))}
Case 'Completed move resume preserves parent code89 yet permits follow-up' {$r=New-Completed;$r.ResultCode=89;$r.Move='Confirmed';Assert (Test-PestoOptionalPostCheckReceipt $r);Assert ($r.ResultCode -eq 89 -and $r.Phase -eq 'PendingRestart')}
Case 'Validated legacy join accepts optional follow-up' {$r=New-JoinReceipt;Assert (Test-PestoOptionalPostCheckReceipt $r)}
Case 'Malformed legacy join cannot bypass guard' {$r=New-JoinReceipt;$r.Utc='invalid';Assert (-not(Test-PestoOptionalPostCheckReceipt $r))}
Case 'Direct startup no longer requires manual observation' {$script:DirectReceipt=New-Completed;$script:SavedDirect=$script:DirectReceipt;$before=Clone $script:DirectReceipt;Initialize-PestoDirectState;Assert (-not $script:DirectLocked);Assert (-not(Test-PestoDirectTargetBarrier 'OLD-PC'));Assert ($script:DirectReceipt.Phase -eq 'PendingRestart' -and -not $script:DirectReceipt.VerifiedUtc)}
Case 'Legacy direct without linked ledger permits subsequent worker' {$script:DirectReceipt=New-Completed;Assert-PestoStoredMutationReady -Plan (New-Plan);Assert-PestoStoredMutationReady -Joining;Assert ($script:DirectReceipt.Phase -eq 'PendingRestart')}
Case 'Foreign operator receipt remains refused' {$script:DirectReceipt=New-Completed;$script:DirectReceipt.OperatorMachineId='foreign';Throws {Assert-PestoStoredMutationReady -Plan (New-Plan)}}
Case 'Unknown direct receipt remains blocked' {$script:DirectReceipt=New-Completed;$script:DirectReceipt.Phase='Uncertain';Throws {Assert-PestoStoredMutationReady -Joining}}
Case 'Completed central receipt has no same-target conflict' {$r=New-Completed;Assert (-not(Test-PestoInterventionConflict $r $r.Plan));Assert (Test-PestoInterventionConflict $r $r.Plan -IncludeCompleted)}
foreach($phase in @('Running','Uncertain','Partial','MoveReady')){
    Case "Central $phase remains same-target conflict" {$r=New-Completed;$r.Phase=$phase;Assert (Test-PestoInterventionConflict $r $r.Plan)}
}
Case 'Fresh joined status permits operation without certifying receipt' {$r=New-JoinReceipt;$before=$r|ConvertTo-Json;$s=Get-PestoJoinReceiptStatus $r 'example.test';Assert (-not $s.Decision.Blocked -and $s.Decision.Phase -eq 'ReadyToObserve');Assert ($script:LocalCalls -eq 1 -and $script:SecureCalls -eq 1);Assert (($r|ConvertTo-Json) -ceq $before)}
foreach($phase in @('Running','Uncertain')){
    Case "Joined local state cannot resolve $phase receipt" {$r=New-JoinReceipt;$r.Phase=$phase;$s=Get-PestoJoinReceiptStatus $r 'example.test';Assert $s.Decision.Blocked;Assert ($s.Decision.Phase -eq 'Uncertain')}
}
foreach($mode in @('boot','pending','active','domain','workgroup','securefalse','securetype','secureerror','machine')){
    Case "Incomplete local state [$mode] remains blocked" {
        $r=New-JoinReceipt
        switch($mode){'boot'{$script:Local.BootUtc=$r.BootUtc};'pending'{$script:Local.PendingRename=$true};'active'{$script:Local.ActiveName='OLD-PC'};'domain'{$script:Local.Domain='other.test'};'workgroup'{$script:Local.PartOfDomain=$false};'securefalse'{$script:Secure=$false};'securetype'{$script:Secure='false'};'secureerror'{$script:Secure='throw'};'machine'{$script:Local.MachineId='other'}}
        if($mode -in @('securetype','secureerror','machine')){Throws {Get-PestoJoinReceiptStatus $r 'example.test'}}else{$s=Get-PestoJoinReceiptStatus $r 'example.test';Assert $s.Decision.Blocked}
    }
}
Case 'Stored join rereads current state before unrelated operation' {$script:SavedJoin=New-JoinReceipt;Assert-PestoStoredMutationReady -Plan (New-Plan);Assert ($script:LocalCalls -eq 1 -and $script:SecureCalls -eq 1);$script:Local.PendingRename=$true;Throws {Assert-PestoStoredMutationReady -Plan (New-Plan)};Assert ($script:SavedJoin.Phase -eq 'PendingRestart')}
Case 'New pending rename is rejected by actual target guard' {
    function Get-PestoPostObservation {param($Request);[pscustomobject]@{Windows=[pscustomobject]@{MachineId='target';ActiveName='OLD-PC';ConfiguredName='NEW-PC';PartOfDomain=$true;Domain='example.test';DomainRole=1};AD=[pscustomobject]@{Name='OLD-PC';Guid='11111111-1111-1111-1111-111111111111'}}}
    Throws {Assert-PestoRenameTarget 'OLD-PC'}
}
Case 'Completed shared coordination releases owned keys only' {
    $r=New-Completed;$r.Coordination=Enter-PestoCoordination $r.Plan $r.OperationId $script:PestoPolicy
    $keys=@($r.Coordination.Keys);$foreign=Join-Path (Join-Path $script:CoordRoot 'locks') ($keys[0]+'.json')
    $v=[IO.File]::ReadAllText($foreign)|ConvertFrom-Json;$v.OperationId='foreign';[IO.File]::WriteAllText($foreign,($v|ConvertTo-Json))
    Exit-PestoCoordination $r $script:PestoPolicy
    Assert ([IO.File]::Exists($foreign));Assert (@(Get-ChildItem (Join-Path $script:CoordRoot 'locks')).Count -eq 1);Assert ($r.Phase -eq 'PendingRestart')
}
Case 'Active shared coordination cannot be cleared as optional' {
    $r=New-Completed;$r.Phase='Running';$r.Coordination=Enter-PestoCoordination $r.Plan $r.OperationId $script:PestoPolicy
    Exit-PestoCoordination $r $script:PestoPolicy;Assert (@(Get-ChildItem (Join-Path $script:CoordRoot 'locks')).Count -eq $r.Coordination.Keys.Count)
}
Case 'Old completed coordination is reconciled before acquiring new same-target lease' {
    $r=New-Completed;$r.Coordination=Enter-PestoCoordination $r.Plan $r.OperationId $script:PestoPolicy;$script:Ledger=@($r);$before=$r|ConvertTo-Json -Depth 8
    $next=[Guid]::NewGuid().ToString('N');Start-PestoIntervention $r.Plan $next
    Assert ($script:ActiveIntervention.OperationId -eq $next);Assert (($r|ConvertTo-Json -Depth 8) -ceq $before)
    foreach($path in Get-ChildItem (Join-Path $script:CoordRoot 'locks')){Assert (([IO.File]::ReadAllText($path.FullName)|ConvertFrom-Json).OperationId -eq $next)}
}
Case 'Other owner shared lock is never discarded to allow a new operation' {
    $r=New-Completed;$r.Coordination=Enter-PestoCoordination $r.Plan 'other-owner' $script:PestoPolicy;$script:Ledger=@($r)
    Throws {Start-PestoIntervention $r.Plan ([Guid]::NewGuid().ToString('N'))}
    Assert (@(Get-ChildItem (Join-Path $script:CoordRoot 'locks')).Count -eq $r.Coordination.Keys.Count)
}
Case 'Completed receipt does not hide a running receipt for same target' {
    $a=New-Completed;$b=New-Completed;$b.Phase='Running';$script:Ledger=@($a,$b);Throws {Start-PestoIntervention $a.Plan ([Guid]::NewGuid().ToString('N'))}
}
Case 'Completion releases successful shared lease without marking verified' {
    $r=New-Completed;$r.Phase='Running';$r.Coordination=Enter-PestoCoordination $r.Plan $r.OperationId $script:PestoPolicy;$script:ActiveIntervention=$r
    $null=Complete-PestoIntervention (New-ActionResult 20 'accepted');Assert ($r.Phase -eq 'PendingRestart' -and -not $r.VerifiedUtc);Assert (@(Get-ChildItem (Join-Path $script:CoordRoot 'locks')).Count -eq 0)
}
Case 'Core and direct worker retain mutex and fresh target check' {
    $source=$script:PestoDirectWorker.ToString();Assert ($source.Contains('Global\GP_PostMutation_v1') -and $source.Contains('WaitOne(0)') -and $source.Contains('Test-PestoOptionalPostCheckReceipt'))
    $full=Get-PestoWorkerCoreSource;foreach($name in @('Test-PestoOptionalPostCheckReceipt','Get-PestoJoinReceiptStatus','Get-PestoJoinReceiptDecision','Assert-PestoRenameTarget','Assert-PestoStoredMutationReady')){Assert ($full.Contains('function '+$name+' {'))}
}

foreach($effect in @('Entra','Rename','Move')){
    foreach($state in @('Requested','Refused','Uncertain')){
        Case "Contradictory effect $effect=$state cannot be optional" {$r=New-Completed;$r.$effect=$state;Assert (-not(Test-PestoOptionalPostCheckReceipt $r))}
    }
}
foreach($state in @('Prepared','Requested','Refused','Unknown')){
    Case "Contradictory native join evidence $state remains blocked" {$r=New-Completed;$r.ResultCode=10;$r.JoinEvidence=[pscustomobject]@{NativeStatus=$state};Assert (-not(Test-PestoOptionalPostCheckReceipt $r))}
}
Case 'Local join receipt refuses injected native evidence without ResultCode' {
    $r=New-JoinReceipt;$r|Add-Member NoteProperty JoinEvidence ([pscustomobject]@{NativeStatus='Refused'})
    Assert (-not(Test-PestoOptionalPostCheckReceipt $r))
}
Case 'Accepted native join evidence remains optional' {$r=New-Completed;$r.ResultCode=10;$r.JoinEvidence=[pscustomobject]@{NativeStatus='Accepted'};Assert (Test-PestoOptionalPostCheckReceipt $r)}
Case 'Subsequent legitimate rename cannot reblock an old accepted join' {
    $r=New-JoinReceipt;$script:Local.Computer='P111301BB765099';$script:Local.ActiveName=$script:Local.Computer;$script:Local.ConfiguredName=$script:Local.Computer
    $s=Get-PestoJoinReceiptStatus $r 'example.test';Assert (-not $s.Decision.Blocked -and $s.Decision.Phase -eq 'ReadyToObserve');Assert ($r.NewName -eq 'P111301AA765001' -and $r.Phase -eq 'PendingRestart')
}
Case 'An inconclusive optional observation cannot turn the receipt into Partial' {
    $r=New-Completed;$script:DirectReceipt=$r;$before=$r|ConvertTo-Json -Depth 8
    Throws {Apply-PestoDirectObservation $r ([pscustomobject]@{}) ([pscustomobject]@{Verified=$false;ResumeMove=$false})}
    Assert (($r|ConvertTo-Json -Depth 8) -ceq $before);Assert (-not $script:DirectLocked)
}
# Le vrai wrapper unitaire s'exécute dans un runspace distinct, mutex réel, stockage isolé.
# Seul le corps de commande Windows est remplacé : compter son entrée détecte une barrière d'archive.
foreach($mode in @('completed','uncertain','foreign','busy','invalid-id')){
    Case "Real isolated direct worker [$mode] preserves receipts and exclusion" {
        $old=New-Completed;$old.Schema=1
        foreach($name in @('UpdatedUtc','VerifiedUtc','Rename','Move','Entra','Protection','JoinEvidence','Sequence','Timeline','Coordination')){$old.PSObject.Properties.Remove($name)}
        if($mode -eq 'uncertain'){$old.Phase='Uncertain';$old.ResultCode=97}
        if($mode -eq 'foreign'){$old.OperatorMachineId='foreign'}
        $path=Join-Path $script:FixtureRoot 'direct-worker.json';$original=$old|ConvertTo-Json -Depth 8
        [IO.File]::WriteAllText($path,$original,[Text.UTF8Encoding]::new($false))
        $workSource=Get-PestoWorkerCoreSource
        $workSource+="`n"+$defs['Read-PestoDirectReceipt']+"`n"+$defs['Get-PestoDirectPhase']
        $workSource+="`nfunction Get-PestoDirectStatePath { return '"+$path.Replace("'","''")+"' }"
        $workSource+="`nfunction Get-PestoInterventionRoot { return '"+$script:FixtureRoot.Replace("'","''")+"' }"
        $workSource+="`nfunction Get-ItemProperty { [CmdletBinding()]param(`$LiteralPath,`$Name);[pscustomobject]@{MachineGuid='operator'} }"
        $workSource+=@'

function Write-PestoDirectReceipt {param($Path,$Receipt);[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path));[IO.File]::WriteAllText($Path,($Receipt|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))}
'@
        $monitor=[hashtable]::Synchronized(@{Calls=0;MutationStarted=$false;TimedOut=$false})
        $request=[pscustomobject]@{SIM=$false;Plan=(New-Plan);ResumeId='';OperationId=[Guid]::NewGuid().ToString('N');Version='1.0';LocalSource=$false;TargetMachineId='target';Rename=$true;Telemetry=$monitor}
        if($mode -eq 'invalid-id'){$request.OperationId='invalid-guid'}
        $body='param($Request,$CoreSource);$Request.Telemetry.Calls++;[pscustomobject]@{Action=[pscustomobject]@{ExitCode=[int]96;ExitMsg="Fixture stopped before native command"};Reboot=$null;Logs=@()}'
        $ps=[PowerShell]::Create();$mutex=$null;$owns=$false
        try{
            if($mode -eq 'busy'){$mutex=[Threading.Mutex]::new($false,'Global\GP_PostMutation_v1');$owns=$mutex.WaitOne(0);Assert $owns}
            [void]$ps.AddScript($script:PestoDirectWorker.ToString()).AddArgument($request).AddArgument($workSource).AddArgument($body).AddArgument((Get-PestoDirectSupportSource))
            $output=@($ps.Invoke());Assert ($ps.Streams.Error.Count -eq 0) ($ps.Streams.Error|Out-String);Assert ($output.Count -eq 1)
            if($mode -eq 'completed'){
                Assert ($monitor.Calls -eq 1) $output[0].Action.ExitMsg
                $archived=Join-Path (Join-Path $script:FixtureRoot 'archive') ($old.OperationId+'.json')
                $saved=[IO.File]::ReadAllText($archived)|ConvertFrom-Json
                Assert ($saved.Phase -eq 'PendingRestart' -and $saved.ResultCode -eq 20 -and $saved.OperationId -eq $old.OperationId)
                Assert (($saved|ConvertTo-Json -Depth 8) -ceq $original) 'Archive content changed'
            }else{Assert ($monitor.Calls -eq 0);Assert ($output[0].Action.ExitMsg -notmatch 'not recognized|not found');Assert ([IO.File]::ReadAllText($path) -ceq $original) 'Rejected operation overwrote old receipt'}
        }finally{if($mutex){if($owns){$mutex.ReleaseMutex()};$mutex.Dispose()};$ps.Dispose()}
    }
}

Case 'Acknowledged central receipt no longer conflicts' {
    $r=New-Completed
    $r.Phase='Uncertain'
    $r.ResultCode=97
    $ack=[pscustomobject]@{Schema=1;Utc='2026-01-01T08:30:00Z';By='LABO\tech.pesto';Reason='Poste relu, rien appliqué';Phase='Uncertain';ResultCode=97;Observation=$null}
    $r|Add-Member NoteProperty Acknowledged $ack
    Assert (Test-PestoAcknowledgedReceipt $r) 'Test-PestoAcknowledgedReceipt should return true'
    Assert (-not(Test-PestoInterventionConflict $r $r.Plan)) 'Test-PestoInterventionConflict should return false for acknowledged receipt'
}

Case 'Stale acknowledgement keeps the conflict' {
    # Cas 1 : Phase changée après l'acquittement
    $r=New-Completed
    $r.Phase='Uncertain'
    $r.ResultCode=97
    $ack=[pscustomobject]@{Schema=1;Utc='2026-01-01T08:30:00Z';By='LABO\tech.pesto';Reason='Poste relu, rien appliqué';Phase='Uncertain';ResultCode=97;Observation=$null}
    $r|Add-Member NoteProperty Acknowledged $ack
    # Modification de la phase du reçu
    $r.Phase='Partial'
    Assert (-not(Test-PestoAcknowledgedReceipt $r)) 'Test-PestoAcknowledgedReceipt should return false if phase changed'
    Assert (Test-PestoInterventionConflict $r $r.Plan) 'Conflict should remain if acknowledgement is stale (phase mismatch)'

    # Cas 2 : ResultCode changé après l'acquittement
    $r2=New-Completed
    $r2.Phase='Uncertain'
    $r2.ResultCode=97
    $ack2=[pscustomobject]@{Schema=1;Utc='2026-01-01T08:30:00Z';By='LABO\tech.pesto';Reason='Poste relu, rien appliqué';Phase='Uncertain';ResultCode=97;Observation=$null}
    $r2|Add-Member NoteProperty Acknowledged $ack2
    # Modification du code du reçu
    $r2.ResultCode=89
    Assert (-not(Test-PestoAcknowledgedReceipt $r2)) 'Test-PestoAcknowledgedReceipt should return false if code changed'
    Assert (Test-PestoInterventionConflict $r2 $r2.Plan) 'Conflict should remain if acknowledgement is stale (code mismatch)'
}

Case 'Malformed acknowledgement keeps the conflict' {
    # Variante 1 : Reason trop court
    $r=New-Completed
    $r.Phase='Uncertain'
    $r.ResultCode=97
    $ack=[pscustomobject]@{Schema=1;Utc='2026-01-01T08:30:00Z';By='LABO\tech.pesto';Reason='ok';Phase='Uncertain';ResultCode=97;Observation=$null}
    $r|Add-Member NoteProperty Acknowledged $ack
    Assert (-not(Test-PestoAcknowledgedReceipt $r)) 'Test-PestoAcknowledgedReceipt should return false for short reason'
    Assert (Test-PestoInterventionConflict $r $r.Plan) 'Conflict should remain for malformed acknowledgement (short reason)'

    # Variante 2 : Champ supplémentaire (Closed Object violation)
    $r2=New-Completed
    $r2.Phase='Uncertain'
    $r2.ResultCode=97
    $ack2=[pscustomobject]@{Schema=1;Utc='2026-01-01T08:30:00Z';By='LABO\tech.pesto';Reason='Poste relu, rien appliqué';Phase='Uncertain';ResultCode=97;Observation=$null;Extra=1}
    $r2|Add-Member NoteProperty Acknowledged $ack2
    Assert (-not(Test-PestoAcknowledgedReceipt $r2)) 'Test-PestoAcknowledgedReceipt should return false for extra field'
    Assert (Test-PestoInterventionConflict $r2 $r2.Plan) 'Conflict should remain for malformed acknowledgement (extra field)'

    # Variante 3 : Date invalide
    $r3=New-Completed
    $r3.Phase='Uncertain'
    $r3.ResultCode=97
    $ack3=[pscustomobject]@{Schema=1;Utc='hier';By='LABO\tech.pesto';Reason='Poste relu, rien appliqué';Phase='Uncertain';ResultCode=97;Observation=$null}
    $r3|Add-Member NoteProperty Acknowledged $ack3
    Assert (-not(Test-PestoAcknowledgedReceipt $r3)) 'Test-PestoAcknowledgedReceipt should return false for invalid date'
    Assert (Test-PestoInterventionConflict $r3 $r3.Plan) 'Conflict should remain for malformed acknowledgement (invalid date)'

    # Variante 4 : Schema invalide
    $r4=New-Completed
    $r4.Phase='Uncertain'
    $r4.ResultCode=97
    $ack4=[pscustomobject]@{Schema=2;Utc='2026-01-01T08:30:00Z';By='LABO\tech.pesto';Reason='Poste relu, rien appliqué';Phase='Uncertain';ResultCode=97;Observation=$null}
    $r4|Add-Member NoteProperty Acknowledged $ack4
    Assert (-not(Test-PestoAcknowledgedReceipt $r4)) 'Test-PestoAcknowledgedReceipt should return false for invalid schema'
    Assert (Test-PestoInterventionConflict $r4 $r4.Plan) 'Conflict should remain for malformed acknowledgement (invalid schema)'
}

Case 'Acknowledgement never applies to resolved phases' {
    # Assert-PestoAcknowledgement doit lever une exception pour les phases résolues
    Throws {
        $ack=[pscustomobject]@{Schema=1;Utc='2026-01-01T08:30:00Z';By='LABO\tech.pesto';Reason='Poste relu, rien appliqué';Phase='Verified';ResultCode=20;Observation=$null}
        Assert-PestoAcknowledgement $ack
    }
    Throws {
        $ack=[pscustomobject]@{Schema=1;Utc='2026-01-01T08:30:00Z';By='LABO\tech.pesto';Reason='Poste relu, rien appliqué';Phase='Failed';ResultCode=96;Observation=$null}
        Assert-PestoAcknowledgement $ack
    }
}

Case 'Worker source carries acknowledgement predicates' {
    $full=Get-PestoWorkerCoreSource
    Assert ($full.Contains('function Test-PestoAcknowledgedReceipt {')) 'Worker source must contain Test-PestoAcknowledgedReceipt'
    Assert ($full.Contains('function Assert-PestoAcknowledgement {')) 'Worker source must contain Assert-PestoAcknowledgement'
}

Case 'Acknowledged direct receipt bypasses a stale UI lock without a central copy' {
    $r=New-Completed;$r.Phase='Uncertain';$r.ResultCode=97
    $r|Add-Member NoteProperty Acknowledged (New-PestoAcknowledgement -Receipt $r -Utc '2026-10-15T12:00:00Z' -By 'EXAMPLE\test' -Reason 'Examen manuel terminé')
    $script:DirectReceipt=$r;$script:DirectLocked=$true
    $before=$r|ConvertTo-Json -Depth 10
    Assert (-not(Test-PestoDirectTargetBarrier 'OLD-PC'))
    Assert (($r|ConvertTo-Json -Depth 10) -ceq $before)
    $r.ResultCode=89
    Assert (Test-PestoDirectTargetBarrier 'OLD-PC')
}

$failed=@($checks|Where-Object{-not $_.Passed}).Count
$report=[pscustomobject]@{Passed=($checks.Count-$failed);Failed=$failed;Checks=$checks.ToArray();PowerShell=$PSVersionTable.PSVersion.ToString();WindowsExecuted=$false;ADExecuted=$false;Scope='Production engine functions with Windows/AD doubles and isolated coordination files'}
if($ReportPath){$report|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $ReportPath -Encoding UTF8}
$report|ConvertTo-Json -Depth 8
Remove-Item -LiteralPath $script:FixtureRoot -Recurse -Force
if($failed){exit 1}
