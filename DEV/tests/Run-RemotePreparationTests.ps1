#requires -Version 5.1
param([string]$ReportPath='')
$ErrorActionPreference='Stop';Set-StrictMode -Off
$root=Split-Path $PSScriptRoot -Parent;$defs=@{};$results=[Collections.Generic.List[object]]::new()
foreach($file in @('Pesto-Operations.ps1','Pesto-Inspection.ps1','Pesto-Safety.ps1','Pesto-Journal.ps1','Pesto-Directory.ps1','Pesto-Diagnostics.ps1','Pesto-Policy.ps1','Pesto-Contracts.ps1')){
 $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root ('wad/'+$file)),[ref]$tokens,[ref]$errors)
 if($errors.Count){throw ($file+': '+($errors.Message -join '; '))}
 foreach($f in $ast.EndBlock.Statements){if($f -is [Management.Automation.Language.FunctionDefinitionAst]){$defs[$f.Name]=$f.Extent.Text}}
}
foreach($name in @('Assert-PestoTargetNameAvailable','Get-PestoJoinClockCheck','Test-PestoDnsName','ConvertTo-PestoPolicy','Assert-PestoClosedObject','Test-PestoPropertyPresent','Test-PestoComputerName','Get-PestoPostObservation','Assert-PestoRenameTarget','Invoke-PestoSystemTaskScript','Invoke-PestoDsregLeaveBeforeRename','Invoke-PestoDsregLeaveLocal','Protect-PestoLogText','ConvertTo-PestoPowerShellLiteral')){. ([scriptblock]::Create($defs[$name]))}
function Assert {param($Value,[string]$Message='Assertion failed');if(-not $Value){throw $Message}}
function Reject {param([scriptblock]$Action);$caught=$false;try{&$Action|Out-Null}catch{$caught=$true};Assert $caught}
function Case {param($Name,[scriptblock]$Action);try{Reset-Fakes;&$Action;$results.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''})}catch{$results.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message})}}
function Reset-Fakes {
 $script:SIM=$false;$script:GUI=$false;$script:DOMAINE='example.test';$script:DC='dc.example.test';$script:ExpectedObjectGuid='11111111-2222-3333-4444-555555555555'
 $script:Conflict=$false;$script:ConflictError=$false;$script:ClockReads=0;$script:ClockThrow=$false;$script:Clock=[pscustomobject]@{State='Observed';Data=[pscustomobject]@{OffsetSeconds=[double]1}}
 $script:CS=[pscustomobject]@{Name='REMOTE-PC';PartOfDomain=$true;Domain='example.test';DomainRole=1}
 $script:RegistryMode='Unavailable';$script:OsReads=0;$script:RegistryReads=0;$script:RemovedSessions=0;$script:SavedObservation=$null;$script:Effects=@{}
 $script:ActiveIntervention=[pscustomobject]@{OperationId='aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';Plan=[pscustomobject]@{Objet_GUID=$script:ExpectedObjectGuid}}
 $script:TaskCalls=[Collections.Generic.List[string]]::new();$script:CreateCode=0;$script:RunCode=0;$script:RunState='Started'
 $script:Probe=[pscustomobject]@{State='READY';ResultNum=42;ResultRaw='42';Hint='done'};$script:EntraPolicy='HybridOnly'
}
function Get-ADParams {@{Server=$script:DC;Credential=$script:cred}}
function Get-ADObject {[CmdletBinding()]param($LDAPFilter,$Properties,$ResultSetSize,$Server,$Credential)
 $script:ConflictFilter=$LDAPFilter;Assert ($Server -eq $script:DC -and $ResultSetSize -eq 1)
 if($script:ConflictError){throw 'AD unavailable'};if($script:Conflict){[pscustomobject]@{ObjectGUID='12345678-1111-2222-3333-123456789012'}}
}
function Get-PestoClockObservation {param($DC,$TimeoutMilliseconds);$script:ClockReads++;Assert ($DC -eq $script:DC -and $TimeoutMilliseconds -eq 6000);if($script:ClockThrow){throw 'timeout'};$script:Clock}
function Merge-PestoManagedPolicy {param($Policy);$Policy}
function Import-PestoADModule {param($ADModulePath)}
function Get-ADComputer {[CmdletBinding()]param($Identity,$Properties,$Server,$Credential,$LDAPFilter,$ResultSetSize);[pscustomobject]@{Name='REMOTE-PC';ObjectGUID=$script:ExpectedObjectGuid;DistinguishedName='CN=REMOTE-PC,OU=PCs,DC=example,DC=test';Enabled=$true;ProtectedFromAccidentalDeletion=$false}}
function Get-PestoParentDN {param($DN);'OU=PCs,DC=example,DC=test'}
function New-CimSessionOption {
 [CmdletBinding(DefaultParameterSetName='ProtocolTypeSet')]
 param([Parameter(ParameterSetName='ProtocolTypeSet')][string]$Protocol,[Parameter(ParameterSetName='DcomParameterSet')][switch]$PacketPrivacy)
 Assert ($PSCmdlet.ParameterSetName -eq 'DcomParameterSet' -and $PacketPrivacy);'Dcom'
}
function New-CimSession {[CmdletBinding()]param($ComputerName,$SessionOption,$OperationTimeoutSec,$Credential);'session'}
function Get-CimInstance {[CmdletBinding()]param($ClassName,$CimSession,$OperationTimeoutSec);if($ClassName -eq 'Win32_ComputerSystem'){return $script:CS};$script:OsReads++;throw 'OS unavailable'}
function Invoke-CimMethod {[CmdletBinding()]param($CimSession,$Namespace,$ClassName,$MethodName,$Arguments,$OperationTimeoutSec)
 $script:RegistryReads++;Assert ($OperationTimeoutSec -le 2)
 if($script:RegistryMode -eq 'Unavailable'){throw 'Registry denied'}
 $value=if($Arguments.sValueName -eq 'MachineGuid'){'12345678-1111-2222-3333-123456789012'}elseif($script:RegistryMode -eq 'Pending'){'OTHER-PC'}else{'REMOTE-PC'}
 [pscustomobject]@{ReturnValue=[uint32]0;sValue=$value}
}
function Remove-CimSession {[CmdletBinding()]param($CimSession);$script:RemovedSessions++}
function Set-PestoInitialObservation {param($Observation);$script:SavedObservation=$Observation}
function Set-PestoEffect {param($Name,$Value);$script:Effects[$Name]=$Value}
function Write-Log {param($Message,$Level,$Err,$Context)}
function Assert-PestoWorkerMayContinue {param([switch]$Mutation)}
function Set-PestoWorkerStage {param($Name,$Detail)}
function New-ActionResult {param([int]$ExitCode,$ExitMsg);[pscustomobject]@{ExitCode=$ExitCode;ExitMsg=$ExitMsg}}
function New-PestoRunOnceTaskXml {param($Command,$Arguments,$UserId,$LogonType,$RunLevel,$Description);'<Task/>'}
function Get-PestoSchtasksTransportArgs {param($ComputerName);@('/s',$ComputerName)}
function Get-PestoSecretArgIndexes {param($ArgList);@()}
function Invoke-PestoSchtasks {param($ArgList,$MaskIndexes)
 $script:TaskCalls.Add([string]$ArgList[0])
 if($ArgList[0] -eq '/create'){return [pscustomobject]@{ExitCode=$script:CreateCode;Output='create';LaunchState='NotRequested'}}
 if($ArgList[0] -eq '/run'){return [pscustomobject]@{ExitCode=$script:RunCode;Output='run';LaunchState=$script:RunState}}
 [pscustomobject]@{ExitCode=0;Output='delete';LaunchState='NotRequested'}
}
function Get-PestoTaskRunResult {param($TaskName,$Transport,$TimeoutSec);$script:Probe}
$previousTemp=$env:TEMP;$env:TEMP=Join-Path ([IO.Path]::GetTempPath()) ('pesto-remote-'+[Guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($env:TEMP)
try{
 Case 'Source DCOM options bind to the native cmdlet with packet privacy' {
  $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($defs['Get-PestoPostObservation'],[ref]$tokens,[ref]$errors)
  $calls=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'New-CimSessionOption'},$true))
  Assert ($calls.Count -eq 1)
  $command=$calls[0].Extent.Text
  $native=Get-Command New-CimSessionOption -CommandType Cmdlet -ErrorAction SilentlyContinue
  if($native){
   $command=$command.Replace('New-CimSessionOption',($native.ModuleName+'\New-CimSessionOption'))
   $options=& ([scriptblock]::Create($command))
   Assert ($options.GetType().FullName -eq 'Microsoft.Management.Infrastructure.Options.DComSessionOptions')
   Assert $options.PacketPrivacy
  }else{Assert ((& ([scriptblock]::Create($command))) -eq 'Dcom')}
 }
 Case 'Remote rename accepts AD and DCOM identity with optional registry unavailable' {Assert-PestoRenameTarget 'REMOTE-PC';Assert ($script:SavedObservation.Windows.ActiveName -eq 'REMOTE-PC');Assert (-not $script:SavedObservation.Windows.MachineId);Assert ($script:OsReads -eq 0 -and $script:RegistryReads -eq 2 -and $script:RemovedSessions -eq 1)}
 Case 'Known pending remote name blocks rename' {$script:RegistryMode='Pending';Reject {Assert-PestoRenameTarget 'REMOTE-PC'}}
 Case 'Known MachineGuid remains recorded' {$script:RegistryMode='Known';Assert-PestoRenameTarget 'REMOTE-PC';Assert ($script:Effects.TargetMachineId -eq '12345678-1111-2222-3333-123456789012')}
 Case 'Wrong active Windows name blocks rename' {$script:CS.Name='OTHER-PC';Reject {Assert-PestoRenameTarget 'REMOTE-PC'}}
 Case 'Wrong Windows domain blocks rename' {$script:CS.Domain='other.test';Reject {Assert-PestoRenameTarget 'REMOTE-PC'}}
 Case 'Domain controller role remains excluded' {$script:CS.DomainRole=5;Reject {Assert-PestoRenameTarget 'REMOTE-PC'}}
 Case 'Missing Windows identity is not replaced by AD alone' {$script:CS=$null;Reject {Assert-PestoRenameTarget 'REMOTE-PC'}}
 Case 'Task creation refusal is explicitly not started' {$script:CreateCode=5;$r=Invoke-PestoSystemTaskScript 'REMOTE-PC' 'exit 42';Assert ($r.ExitCode -eq 21 -and $r.TaskOutcome -eq 'NotStarted' -and $r.LaunchState -eq 'NotRequested');Assert ('/run' -notin $script:TaskCalls)}
 Case 'Refusal before COM Run does not create uncertainty' {$script:RunCode=1722;$script:RunState='NotRequested';$r=Invoke-PestoSystemTaskScript 'REMOTE-PC' 'exit 42';Assert ($r.ExitCode -eq 21 -and $r.TaskOutcome -eq 'NotStarted')}
 Case 'Uncertain Run response retains the task' {$script:RunCode=1460;$script:RunState='Unknown';$r=Invoke-PestoSystemTaskScript 'REMOTE-PC' 'exit 42';Assert ($r.ExitCode -eq 97 -and '/delete' -notin $script:TaskCalls)}
 Case 'Legacy error without launch evidence remains uncertain' {$script:RunCode=5;$script:RunState='';$r=Invoke-PestoSystemTaskScript 'REMOTE-PC' 'exit 42';Assert ($r.ExitCode -eq 97 -and '/delete' -notin $script:TaskCalls)}
 Case 'Task not finished is retained even with zero result' {$script:Probe.State='RUNNING';$script:Probe.ResultNum=0;$r=Invoke-PestoSystemTaskScript 'REMOTE-PC' 'exit 42';Assert ($r.ExitCode -eq 97 -and '/delete' -notin $script:TaskCalls)}
 Case 'Completed leave propagates confirmation' {$r=Invoke-PestoDsregLeaveBeforeRename 'REMOTE-PC';Assert ($r.ExitCode -eq 20 -and $r.Entra -eq 'Confirmed' -and '/delete' -in $script:TaskCalls)}
 Case 'Completed pre-leave refusal remains not requested' {$script:Probe.ResultNum=44;$r=Invoke-PestoDsregLeaveBeforeRename 'REMOTE-PC';Assert ($r.ExitCode -eq 21 -and $r.Entra -eq 'NotRequested')}
 Case 'Generic completed task error is never assumed pre-leave' {$script:Probe.ResultNum=1;$r=Invoke-PestoDsregLeaveBeforeRename 'REMOTE-PC';Assert ($r.ExitCode -eq 97 -and $r.Entra -eq 'Uncertain')}
 Case 'Prelaunch refusal propagates no Entra mutation' {$script:CreateCode=5;$r=Invoke-PestoDsregLeaveBeforeRename 'REMOTE-PC';Assert ($r.ExitCode -eq 21 -and $r.Entra -eq 'NotRequested')}
 Case 'Simulation never creates a remote Entra task' {$script:SIM=$true;$r=Invoke-PestoDsregLeaveBeforeRename 'REMOTE-PC';Assert ($r.ExitCode -eq 20 -and $script:TaskCalls.Count -eq 0)}
 Case 'Target conflict searches DNS and both HOST SPN forms on same DC' {Assert-PestoTargetNameAvailable -Name 'NEW-PC' -Domain $script:DOMAINE -CurrentGuid $script:ExpectedObjectGuid;Assert ($script:ConflictFilter.Contains('(dNSHostName=NEW-PC.example.test)'));Assert ($script:ConflictFilter.Contains('(servicePrincipalName=RestrictedKrbHost/NEW-PC)'));Assert ($script:ConflictFilter.Contains('(servicePrincipalName=HOST/NEW-PC.example.test)'));Assert ($script:ConflictFilter.Contains('(!(objectGUID='))}
 Case 'Any conflicting AD object blocks target name' {$script:Conflict=$true;Reject {Assert-PestoTargetNameAvailable -Name 'NEW-PC' -Domain $script:DOMAINE}}
 Case 'Failed AD conflict read cannot become a free name' {$script:ConflictError=$true;Reject {Assert-PestoTargetNameAvailable -Name 'NEW-PC' -Domain $script:DOMAINE}}
 Case 'Invalid target never enters LDAP query' {Reject {Assert-PestoTargetNameAvailable -Name 'X*)(name=*' -Domain $script:DOMAINE}}
 Case 'Clock check is disabled by default and performs no read' {$policy=ConvertTo-PestoPolicy $null -LocalOnly;Assert (-not $policy.BlockJoinOnClockSkew);Assert ($null -eq (Get-PestoJoinClockCheck $script:DC $policy));Assert ($script:ClockReads -eq 0)}
 Case 'Clock policy rejects a string boolean' {Reject {ConvertTo-PestoPolicy ([pscustomobject]@{Schema=1;BlockJoinOnClockSkew='true'}) -LocalOnly}}
 Case 'Measured offset below threshold allows join' {$script:Clock.Data.OffsetSeconds=[double]299;$v=Get-PestoJoinClockCheck $script:DC ([pscustomobject]@{BlockJoinOnClockSkew=$true});Assert ($v.State -eq 'OK')}
 Case 'Positive and negative measured 300 seconds block join' {foreach($offset in @(-300,300)){$script:Clock.Data.OffsetSeconds=[double]$offset;$v=Get-PestoJoinClockCheck $script:DC ([pscustomobject]@{BlockJoinOnClockSkew=$true});Assert ($v.State -eq 'Bloqué')}}
 Case 'Unknown clock and timeout warn without blocking' {$script:Clock.State='Unknown';$script:Clock.Data=$null;$v=Get-PestoJoinClockCheck $script:DC ([pscustomobject]@{BlockJoinOnClockSkew=$true});Assert ($v.State -eq 'Avertissement');$script:ClockThrow=$true;$v=Get-PestoJoinClockCheck $script:DC ([pscustomobject]@{BlockJoinOnClockSkew=$true});Assert ($v.State -eq 'Avertissement')}
}finally{Remove-Item -LiteralPath $env:TEMP -Recurse -Force;$env:TEMP=$previousTemp}
$failed=@($results|Where-Object{-not $_.Passed});if($ReportPath){$results|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $ReportPath -Encoding UTF8}
foreach($r in $failed){Write-Host ($r.Name+': '+$r.Error)}
Write-Host ('RemotePreparation : '+($results.Count-$failed.Count)+'/'+$results.Count+' PASS');if($failed.Count){exit 1}
