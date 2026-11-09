#requires -Version 5.1
param([string]$ReportPath='')
$ErrorActionPreference='Stop';Set-StrictMode -Off
$dev=Split-Path $PSScriptRoot -Parent;$definitions=@{};$worker=$null
foreach($file in Get-ChildItem (Join-Path $dev 'wad') -Filter 'Pesto-*.ps1' -File){
    $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw ($file.Name+': '+($errors.Message -join '; '))}
    foreach($node in $ast.EndBlock.Statements){
        if($node -is [Management.Automation.Language.FunctionDefinitionAst]){$definitions[$node.Name]=$node.Extent.Text}
        if($node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq '$script:PestoJoinADReserveWorker'){. ([scriptblock]::Create($node.Extent.Text))}
    }
}
foreach($definition in $definitions.Values){. ([scriptblock]::Create($definition))}
if(-not ('PestoReservationFixture.ADIdentityNotFoundException' -as [type])){
    Add-Type 'namespace PestoReservationFixture { public class ADIdentityNotFoundException : System.Exception {} public class ADIdentityAlreadyExistsException : System.Exception {} }'
}
$checks=[Collections.Generic.List[object]]::new();$temp=Join-Path $PSScriptRoot ('.pesto-reservation-tests-'+[Guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($temp)
function Assert {param($Value,$Message='Assertion failed');if(-not $Value){throw $Message}}
function Case {param($Name,[scriptblock]$Body);try{& $Body;$checks.Add([pscustomobject]@{Name=$Name;Passed=$true})}catch{$checks.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message})}}
$source=Get-PestoJoinADReservationWorkerSource
$mock=@'
function Import-PestoADModule {param($ADModulePath)}
function Get-ADDomain {[CmdletBinding()]param($Server,$Credential);[pscustomobject]@{DNSRoot=$(if($Request.Fixture.WrongDomain){'other.test'}else{$Request.Domain})}}
function Write-PestoJoinReceipt {
 param($Path,$Receipt);$Request.Fixture.Writes++
 if($Request.Fixture.FailWrite -eq $Request.Fixture.Writes){throw 'Fixture storage failure'}
 [IO.File]::WriteAllText($Path,($Receipt|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
}
function New-ADComputer {
 [CmdletBinding()]param($Name,$SamAccountName,$Path,$Enabled,$Description,[switch]$PassThru,$Server,$Credential)
 $Request.Fixture.Creates++;$Request.Fixture.BeforeMutation=([IO.File]::ReadAllText($Request.StatePath)|ConvertFrom-Json).State
 if($Request.Fixture.CreateTaken){throw [PestoReservationFixture.ADIdentityAlreadyExistsException]::new()}
 if($Request.Fixture.CreateFailure){throw 'Creation transport interrupted'}
 if($Request.Fixture.Late){$Request.Monitor.TimedOut=$true;$Request.Monitor.CancelRequested=$true}
 [pscustomobject]@{Name=$Name;ObjectGUID=$(if($Request.Fixture.BadGuid){[Guid]::Empty}else{[Guid]'11111111-2222-3333-4444-555555555555'});DistinguishedName=('CN='+$Name+','+$Path)}
}
function Get-ADComputer {
 [CmdletBinding()]param($Identity,$Properties,$Server,$Credential);$Request.Fixture.Reads++
 if($Request.Fixture.Absent){throw [PestoReservationFixture.ADIdentityNotFoundException]::new()}
 if($Request.Fixture.ReadFailure){throw [UnauthorizedAccessException]::new('Fixture access denied')}
 [pscustomobject]@{Name=$Request.Name;ObjectGUID=[Guid]'11111111-2222-3333-4444-555555555555';DistinguishedName=('CN='+$Request.Name+','+$Request.OU);Description=$(if($Request.Fixture.MarkerChanged){'Réservé par Pesto [different-owner]'}else{'Réservé par Pesto ['+$Request.OperationId+']'});DNSHostName=$(if($Request.Fixture.Used){'used.example.test'}else{''});ServicePrincipalName=@()}
}
function Remove-ADComputer {[CmdletBinding(SupportsShouldProcess)]param($Identity,$Server,$Credential);$Request.Fixture.Deletes++;if($Request.Fixture.Late){$Request.Monitor.TimedOut=$true;$Request.Monitor.CancelRequested=$true}}
'@
function New-FixtureRequest {
 param([string]$Mode='Reserve')
 [pscustomobject]@{Mode=$Mode;OperationId=[Guid]::NewGuid().ToString('D');MachineId='aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';Name='PTESTPR00100001';Guid=$(if($Mode -eq 'Reserve'){''}else{'11111111-2222-3333-4444-555555555555'});OU='OU=Paris,DC=example,DC=test';Domain='example.test';DC='dc.example.test';Credential=$null;ReadOnly=$false;Source=($source+"`n"+$mock);StatePath=(Join-Path $temp ([Guid]::NewGuid().ToString('N')+'.json'));ADModulePath='fixture';Monitor=(New-PestoQueueMonitor 'FIXTURE');Fixture=[hashtable]::Synchronized(@{Writes=0;FailWrite=0;Creates=0;Deletes=0;Reads=0;Late=$false;ReadFailure=$false;Absent=$false;MarkerChanged=$false;Used=$false;CreateTaken=$false;CreateFailure=$false;BadGuid=$false;WrongDomain=$false;BeforeMutation=''})}
}
function Invoke-Fixture {param($Request);return & $script:PestoJoinADReserveWorker $Request}
function Add-LogLine {param($Text,$Kind)}
function Write-Log {}
function Show-MsgError {}
try{
Case 'Only proven AD absence is Gone' {$q=New-FixtureRequest Release;$q.Fixture.Absent=$true;$r=Invoke-Fixture $q;Assert ($r.State -eq 'Gone' -and $q.Fixture.Deletes -eq 0)}
Case 'Access failure remains Failed with review required' {$q=New-FixtureRequest Release;$q.Fixture.ReadFailure=$true;$r=Invoke-Fixture $q;Assert ($r.State -eq 'Failed' -and $r.NeedsReview -and $q.Fixture.Deletes -eq 0)}
Case 'Exact stored identity and marker permit release' {$q=New-FixtureRequest Release;$r=Invoke-Fixture $q;Assert ($r.State -eq 'Released' -and $q.Fixture.Deletes -eq 1)}
Case 'Different reservation owner is kept' {$q=New-FixtureRequest Release;$q.Fixture.MarkerChanged=$true;$r=Invoke-Fixture $q;Assert ($r.State -eq 'Kept' -and $r.NeedsReview -and $q.Fixture.Deletes -eq 0)}
Case 'Used account is kept' {$q=New-FixtureRequest Release;$q.Fixture.Used=$true;$r=Invoke-Fixture $q;Assert ($r.State -eq 'Kept' -and $q.Fixture.Deletes -eq 0)}
Case 'Pending receipt exists before account creation' {$q=New-FixtureRequest;$r=Invoke-Fixture $q;Assert ($r.State -eq 'Reserved' -and $r.Guid -and $q.Fixture.BeforeMutation -eq 'Pending');Assert (-not ((Get-Content $q.StatePath -Raw) -match 'Credential|Password'))}
Case 'Storage failure before create prevents mutation' {$q=New-FixtureRequest;$q.Fixture.FailWrite=1;$failed=$false;try{Invoke-Fixture $q}catch{$failed=$true};Assert ($failed -and $q.Fixture.Creates -eq 0)}
Case 'Creation transport failure is uncertain' {$q=New-FixtureRequest;$q.Fixture.CreateFailure=$true;$r=Invoke-Fixture $q;Assert ($r.State -eq 'Uncertain' -and $r.NeedsReview)}
Case 'Unconfirmed creation GUID is uncertain' {$q=New-FixtureRequest;$q.Fixture.BadGuid=$true;$r=Invoke-Fixture $q;Assert ($r.State -eq 'Uncertain')}
Case 'Already exists never claims reservation ownership' {$q=New-FixtureRequest;$q.Fixture.CreateTaken=$true;$r=Invoke-Fixture $q;Assert ($r.State -eq 'Taken' -and -not $r.Guid)}
Case 'Late creation preserves GUID and uncertainty' {$q=New-FixtureRequest;$q.Fixture.Late=$true;$r=Invoke-Fixture $q;Assert ($r.State -eq 'Uncertain' -and $r.Outcome -eq 'Reserved' -and $r.Guid -and $r.NeedsReview);$stored=Read-PestoJoinADReservationState $q.StatePath;Assert ($stored.Guid -eq $r.Guid -and $stored.State -eq 'Uncertain')}
Case 'Late deletion remains uncertain without replay' {$q=New-FixtureRequest Release;$q.Fixture.Late=$true;$r=Invoke-Fixture $q;Assert ($r.State -eq 'Uncertain' -and $r.Outcome -eq 'Released' -and $q.Fixture.Deletes -eq 1)}
Case 'Cancelled request cannot start a mutation' {$q=New-FixtureRequest;$q.Monitor.CancelRequested=$true;$r=Invoke-Fixture $q;Assert ($r.State -eq 'Uncertain' -and $q.Fixture.Creates -eq 0)}
Case 'Wrong domain refuses any AD mutation' {$q=New-FixtureRequest;$q.Fixture.WrongDomain=$true;$r=Invoke-Fixture $q;Assert ($r.State -eq 'Failed' -and $q.Fixture.Creates -eq 0)}
Case 'Receipt from another machine cannot be resumed' {$q=New-FixtureRequest;$r=Invoke-Fixture $q;$q.Mode='Inspect';$q.Guid=$r.Guid;$q.MachineId=[Guid]::NewGuid().ToString('D');$failed=$false;try{Invoke-Fixture $q}catch{$failed=$true};Assert ($failed -and $q.Fixture.Reads -eq 0)}
Case 'Another installation cannot overwrite a pending reservation' {$q=New-FixtureRequest;$r=Invoke-Fixture $q;$q.OperationId=[Guid]::NewGuid().ToString('D');$failed=$false;try{Invoke-Fixture $q}catch{$failed=$true};Assert ($failed -and $q.Fixture.Creates -eq 1)}
Case 'Explicit inspection recovers known reservation without AD writes' {$q=New-FixtureRequest;$q.Fixture.Late=$true;$r=Invoke-Fixture $q;$q.Mode='Inspect';$q.Guid=$r.Guid;$q.Monitor=New-PestoQueueMonitor 'FIXTURE';$q.Fixture.Late=$false;$r=Invoke-Fixture $q;Assert ($r.State -eq 'Reserved' -and -not $r.NeedsReview -and $q.Fixture.Creates -eq 1 -and $q.Fixture.Deletes -eq 0)}
Case 'Real runspace keeps monitor and result identities' {
 $q=New-FixtureRequest;$q.Fixture.Late=$true;$ps=[PowerShell]::Create()
 try{[void]$ps.AddScript($script:PestoJoinADReserveWorker.ToString()).AddArgument($q);$data=@($ps.Invoke());Assert ($ps.Streams.Error.Count -eq 0 -and $data.Count -eq 1 -and $data[0].State -eq 'Uncertain' -and $q.Monitor.MutationStarted)}finally{$ps.Dispose()}
}
Case 'All reservation names use mutation cancellation classification' {foreach($name in @('JoinADReserve','JoinADRelease','JoinADInspect')){Assert (Test-PestoAsyncMutationName $name)};Assert (-not(Test-PestoAsyncMutationName 'JoinCheck'))}
Case 'Stopping reservation preserves live worker and sets cooperative fence' {
 $monitor=New-PestoQueueMonitor 'FIXTURE';$ps=[pscustomobject]@{Stops=0};$ps|Add-Member ScriptMethod BeginStop {param($a,$b);$this.Stops++}
 $op=[pscustomobject]@{Name='JoinADReserve';Cancelled=$false;QueueMonitor=$monitor;Async=[pscustomobject]@{IsCompleted=$false};PowerShell=$ps}
 $script:PestoAsyncOperations=@{JoinADReserve=$op};$script:PestoAsyncTimerOperations=@{fixture=$op};Stop-PestoAsyncOperation 'JoinADReserve'
 Assert ($script:PestoAsyncOperations.ContainsKey('JoinADReserve') -and $monitor.CancelRequested -and $ps.Stops -eq 0 -and (Test-PestoQueueWorkerStillActive))
}
Case 'Async timer delivers late reservation evidence only to late callback' {
 $script:LateDeliveries=0;$script:NormalDeliveries=0;$script:LatePayload=$null
 $timer=[pscustomobject]@{};$timer|Add-Member ScriptMethod Stop {};$timer|Add-Member ScriptMethod Remove_Tick {param($h)}
 $rs=[Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace();$rs.Open();$ps=[PowerShell]::Create();$ps.Runspace=$rs
 [void]$ps.AddScript({[pscustomobject]@{State='Reserved';Guid='11111111-2222-3333-4444-555555555555'}})
 $handle=$ps.BeginInvoke();while(-not $handle.IsCompleted){Start-Sleep -Milliseconds 5}
 $op=[pscustomobject]@{Name='JoinADReserve';Runspace=$rs;PowerShell=$ps;Async=$handle;Timer=$timer;TickHandler=$null;TickBusy=$false;Completed=$false;Cancelled=$true;TimeoutReported=$true;TimerFaultReported=$false;TimeoutSec=60;Clock=[Diagnostics.Stopwatch]::StartNew();QueueMonitor=(New-PestoQueueMonitor 'FIXTURE');Timing=@{WaitMs=0;WorkMs=0};Context=$null;
  OnSuccess={param($r)$script:NormalDeliveries++};OnError={param($e)$script:NormalDeliveries++};OnLateResult={param($r)$script:LateDeliveries++;$script:LatePayload=$r}}
 $script:PestoAsyncOperations=@{JoinADReserve=$op};$script:PestoAsyncTimerOperations=@{};$script:PestoAsyncTimerOperations[$timer]=$op
 Invoke-PestoAsyncTimerTick $timer $null
 Assert ($script:LateDeliveries -eq 1 -and $script:NormalDeliveries -eq 0 -and $script:LatePayload.Result.Guid -eq '11111111-2222-3333-4444-555555555555')
 Assert (-not $script:PestoAsyncOperations.ContainsKey('JoinADReserve') -and $op.Completed)
}
# Callback doubles do not touch AD or the Windows registry.
function Set-PestoJoinBusy {param($Busy);$script:JoinBusy=$Busy}
function Set-PestoJoinMessage {param($Title,$Detail,$Kind);$script:CallbackTitle=$Title;$script:CallbackDetail=$Detail}
function Update-PestoJoinUI {}
function Start-PestoJoinCheck {$script:JoinStarts++}
function Write-Log {}
function Write-PestoJoinReceipt {param($Path,$Receipt);$script:CallbackReceipt=$Receipt}
Case 'Late callback preserves GUID and never chains to domain join' {
 $q=New-FixtureRequest;$r=Invoke-Fixture $q;$script:PestoAsyncOperations=@{};$script:JoinGeneration=1;$script:JoinStarts=0
 $ctx=[pscustomobject]@{Request=$q;Generation=1};Complete-PestoJoinADReservation -Result $r -Context $ctx -Late
 Assert ($script:JoinStarts -eq 0 -and $script:JoinLocked -and $script:JoinADReservation.Guid -eq $r.Guid -and $script:CallbackReceipt.State -eq 'Uncertain')
}
function Start-PestoJoinADReservationInspection {$script:InspectionStarts++}
Case 'Automatic status keeps reservation locked without inspection' {
 $script:JoinUI=[pscustomobject]@{Fixture=$true};$script:JoinBusy=$false;$script:DirectBusy=$false;$script:DirectLocked=$false;$script:Running=$false;$script:PestoAsyncOperations=@{}
 $script:JoinADReservationNeedsReview=$true;$script:JoinLocked=$true;$script:InspectionStarts=0
 Start-PestoJoinStatus
 Assert ($script:InspectionStarts -eq 0 -and $script:JoinLocked -and $script:JoinADReservationNeedsReview -and $script:CallbackTitle -eq 'Réservation AD conservée')
}
Case 'Reservation recovery messages name the visible status button exactly' {
 [xml]$xaml=Get-Content -LiteralPath (Join-Path $dev 'wad/Pesto-Join.xaml') -Raw -Encoding UTF8
 $button=$xaml.SelectSingleNode('//*[local-name()="Button" and @*[local-name()="Name"]="JnRefresh"]')
 $label=[string]$button.Content
 Assert ($label -ceq 'Vérifier l’’état')
 Start-PestoJoinStatus
 Assert ($script:CallbackDetail.Contains($label))
 function Read-PestoJoinADReservationState {[pscustomobject]@{State='Reserved';NeedsReview=$true;MachineId='fixture';Domain='example.test';DC='dc.example.test';Name='FIXTURE'}}
 function Get-PestoReservationMachineId {'fixture'}
 function Get-PestoJoinADReservationPath {'fixture-receipt'}
 $caught=''
 try{Assert-PestoJoinADReservationResolved -Plan ([pscustomobject]@{Domain='example.test';DC='dc.example.test'})}catch{$caught=$_.Exception.Message}
 Assert ($caught.Contains($label))
}
Case 'Explicit status click starts reservation inspection only' {
 $script:InspectionStarts=0;$script:JoinStarts=0
 Invoke-PestoJoinStatusClick $null $null
 Assert ($script:InspectionStarts -eq 1 -and $script:JoinStarts -eq 0 -and $script:JoinLocked)
}
Case 'Explicit status click respects existing mutation lock' {
 $script:InspectionStarts=0;$script:JoinBusy=$true
 try{Invoke-PestoJoinStatusClick $null $null;Assert ($script:InspectionStarts -eq 0)}finally{$script:JoinBusy=$false}
}
Case 'Closing only preserves reservation without any AD worker' {
 $script:JoinADReservation=[pscustomobject]@{Name='FIXTURE'};$script:CloseStarts=0
 function Start-PestoAsyncOperation {$script:CloseStarts++;throw 'No worker expected'}
 function Get-PestoJoinADReservationPath {'fixture-receipt'}
 Stop-PestoJoinADReservationAtClose;Assert ($script:CloseStarts -eq 0 -and $script:JoinADReservation.Name -eq 'FIXTURE')
}
}finally{if([IO.Directory]::Exists($temp)){[IO.Directory]::Delete($temp,$true)}}
$failed=@($checks|Where-Object{-not $_.Passed}).Count
$report=[pscustomobject]@{Checks=$checks.ToArray();Passed=($checks.Count-$failed);Failed=$failed;PowerShell=$PSVersionTable.PSVersion.ToString();WindowsExecuted=$false;ADExecuted=$false;Scope='Local worker requests, real in-process runspace, AD/registry/ACL doubles'}
if($ReportPath){$report|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $ReportPath -Encoding UTF8}
$report|ConvertTo-Json -Depth 6
if($failed){exit 1}
