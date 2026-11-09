#requires -Version 5.1
param([string]$ReportPath='')
$ErrorActionPreference='Stop';Set-StrictMode -Off
$dev=Split-Path $PSScriptRoot -Parent
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $dev 'wad/Pesto-Join.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors.Message -join '; ')}
foreach($name in @('Get-PestoJoinLocalStatus','Get-PestoJoinReceiptDecision')){
    $node=@($ast.EndBlock.Statements|Where-Object{$_ -is [Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -eq $name})
    if($node.Count -ne 1){throw ('Missing production function: '+$name)}
    . ([scriptblock]::Create($node[0].Extent.Text))
}
$policyAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $dev 'wad/Pesto-Policy.ps1'),[ref]$tokens,[ref]$errors)
$predicate=@($policyAst.EndBlock.Statements|Where-Object{$_ -is [Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -in @('Test-PestoOptionalPostCheckReceipt','Test-PestoAcknowledgedReceipt')})
foreach($definition in $predicate){. ([scriptblock]::Create($definition.Extent.Text))}
$contractsAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $dev 'wad/Pesto-Contracts.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors.Message -join '; ')}
foreach($name in @('Assert-PestoClosedObject','Assert-PestoAcknowledgement','Assert-PestoObservationSnapshot','Get-PestoAcknowledgementText','Get-PestoStatePresentation')){
    $node=@($contractsAst.EndBlock.Statements|Where-Object{$_ -is [Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -eq $name})
    if($node.Count -ne 1){throw ('Missing production function: '+$name)}
    . ([scriptblock]::Create($node[0].Extent.Text))
}
$recoveryAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $dev 'wad/Pesto-JoinRecovery.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors.Message -join '; ')}
foreach($name in @('Assert-PestoJoinReceiptData')){
    $node=@($recoveryAst.EndBlock.Statements|Where-Object{$_ -is [Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -eq $name})
    if($node.Count -ne 1){throw ('Missing production function: '+$name)}
    . ([scriptblock]::Create($node[0].Extent.Text))
}
$operationsAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $dev 'wad/Pesto-Operations.ps1'),[ref]$tokens,[ref]$errors)
$computerCheck=@($operationsAst.EndBlock.Statements|Where-Object{$_ -is [Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -eq 'Test-PestoComputerName'})
. ([scriptblock]::Create($computerCheck[0].Extent.Text))
function Test-PestoGeneratedComputerName {param($Name,$Prefix='');return ($Name -match '^[A-Za-z0-9][A-Za-z0-9-]{0,14}$')}
function Test-PestoDnsName {param($Name);return ($Name -match '^[A-Za-z0-9.-]{1,253}$')}
function Test-PestoOUPath {param($Path);return ($Path -match '^OU=[^,]+(,DC=[^,]+)+$')}
function Get-PestoDomainFromDN {param($DN);return (([regex]::Matches($DN,'DC=([^,]+)')|ForEach-Object{$_.Groups[1].Value}) -join '.')}
$checks=[Collections.Generic.List[object]]::new()
function Assert {param($Value);if(-not $Value){throw 'Assertion failed'}}
function Assert-Throws {param([scriptblock]$Action);$caught=$false;try{& $Action|Out-Null}catch{$caught=$true};Assert $caught}
function Reset-Fixture {
    $script:Fixture=@{Active='OLD-PC';Configured='OLD-PC';CimBoot='2026-01-01T08:00:00Z';CimOSReads=0;Id=12;Provider='Microsoft-Windows-Kernel-General';Count=1;Failure=$false;Xml='<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event"><EventData><Data Name="StartTime">2026-01-01T08:00:00.500000000Z</Data></EventData></Event>'}
}
function Case {param($Name,[scriptblock]$Body);Reset-Fixture;try{& $Body;$checks.Add([pscustomobject]@{Name=$Name;Passed=$true})}catch{$checks.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message})}}
function Get-CimInstance {
    [CmdletBinding()]param($ClassName,$OperationTimeoutSec)
    if($ClassName -eq 'Win32_OperatingSystem'){$script:Fixture.CimOSReads++;return [pscustomobject]@{LastBootUpTime=[DateTime]$script:Fixture.CimBoot}}
    if($ClassName -ne 'Win32_ComputerSystem'){throw 'Unexpected CIM query'}
    [pscustomobject]@{Name='OLD-PC';PartOfDomain=$false;DomainRole=0;Domain='WORKGROUP'}
}
function Get-ItemProperty {
    [CmdletBinding()]param($LiteralPath,$Name)
    if($Name -eq 'MachineGuid'){return [pscustomobject]@{MachineGuid='aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'}}
    [pscustomobject]@{ComputerName=$(if($LiteralPath.EndsWith('\ActiveComputerName')){$script:Fixture.Active}else{$script:Fixture.Configured})}
}
function Test-PestoIsAdministrator {$true}
function Get-WinEvent {
    [CmdletBinding()]param($FilterHashtable,$MaxEvents)
    Assert ($MaxEvents -eq 1 -and $FilterHashtable.LogName -eq 'System' -and $FilterHashtable.Id -eq 12 -and $FilterHashtable.ProviderName -eq 'Microsoft-Windows-Kernel-General')
    if($script:Fixture.Failure){throw 'Fixture event log unavailable'}
    for($i=0;$i -lt $script:Fixture.Count;$i++){
        $event=[pscustomobject]@{Id=$script:Fixture.Id;ProviderName=$script:Fixture.Provider}
        $event|Add-Member ScriptMethod ToXml {return $script:Fixture.Xml}
        $event
    }
}
# Assert-PestoJoinReceiptData est chargé depuis Pesto-JoinRecovery.ps1.
function New-Receipt {
    [pscustomobject]@{
        Schema=1;OperationId='11111111-1111-1111-1111-111111111111';Phase='PendingRestart';
        BootUtc='2026-01-01T08:00:00.0000000Z';Utc='2026-01-01T08:30:00.0000000Z';
        MachineId='aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';Computer='OLD-PC';NewName='NEW-PC';
        Domain='example.test';OU='OU=Computers,DC=example,DC=test'
    }
}
function New-JoinedStatus {
    param($BootUtc)
    [pscustomobject]@{BootUtc=$BootUtc;MachineId='aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';PartOfDomain=$true;DomainRole=1;Domain='example.test';Computer='NEW-PC';ActiveName='NEW-PC';ConfiguredName='NEW-PC';PendingRename=$false;SecureChannel=$true}
}
function New-UncertainReceipt {
    $r=New-Receipt
    $r.Phase='Uncertain'
    return $r
}
function New-Acknowledgement {
    param([string]$Phase='Uncertain')
    [pscustomobject]@{Schema=1;Utc='2026-10-15T12:00:00.0000000Z';By='LABO\tech.pesto';Reason='Jonction relue, acquittée';Phase=$Phase;ResultCode=$null;Observation=$null}
}
Case 'Native event UTC accepts and normalizes nine fractional digits' {$s=Get-PestoJoinLocalStatus;Assert ($s.BootUtc -ceq '2026-01-01T08:00:00.5000000Z')}
Case 'Clock correction changing CIM boot time cannot invent a reboot' {$a=Get-PestoJoinLocalStatus;$script:Fixture.CimBoot='2026-01-01T08:00:02.1245780Z';$b=Get-PestoJoinLocalStatus;Assert ($a.BootUtc -ceq $b.BootUtc -and $script:Fixture.CimOSReads -eq 0)}
Case 'Pending local name is preserved with stable boot identity' {$script:Fixture.Configured='NEW-PC';$s=Get-PestoJoinLocalStatus;Assert ($s.PendingRename -and $s.ActiveName -eq 'OLD-PC' -and $s.ConfiguredName -eq 'NEW-PC')}
Case 'Missing boot event refuses local status' {$script:Fixture.Count=0;Assert-Throws {Get-PestoJoinLocalStatus}}
Case 'Unavailable event log refuses local status' {$script:Fixture.Failure=$true;Assert-Throws {Get-PestoJoinLocalStatus}}
Case 'Unexpected provider refuses local status' {$script:Fixture.Provider='Other';Assert-Throws {Get-PestoJoinLocalStatus}}
Case 'Unexpected event ID refuses local status' {$script:Fixture.Id=1;Assert-Throws {Get-PestoJoinLocalStatus}}
Case 'Multiple returned boot records refuse local status' {$script:Fixture.Count=2;Assert-Throws {Get-PestoJoinLocalStatus}}
Case 'Missing StartTime refuses local status' {$script:Fixture.Xml='<Event><EventData /></Event>';Assert-Throws {Get-PestoJoinLocalStatus}}
Case 'Duplicate StartTime refuses local status' {$script:Fixture.Xml='<Event><EventData><Data Name="StartTime">2026-01-01T08:00:00Z</Data><Data Name="StartTime">2026-01-01T08:00:01Z</Data></EventData></Event>';Assert-Throws {Get-PestoJoinLocalStatus}}
Case 'Malformed XML refuses local status' {$script:Fixture.Xml='<Event';Assert-Throws {Get-PestoJoinLocalStatus}}
Case 'Invalid calendar date refuses local status' {$script:Fixture.Xml=$script:Fixture.Xml.Replace('2026-01-01','2026-02-31');Assert-Throws {Get-PestoJoinLocalStatus}}
Case 'Timestamp without UTC refuses local status' {$script:Fixture.Xml=$script:Fixture.Xml.Replace('000Z','000');Assert-Throws {Get-PestoJoinLocalStatus}}
Case 'Future boot timestamp refuses local status' {$script:Fixture.Xml=$script:Fixture.Xml.Replace('2026-01-01','2099-01-01');Assert-Throws {Get-PestoJoinLocalStatus}}
Case 'Drift from an older receipt before operation is not a restart' {$r=New-Receipt;$s=New-JoinedStatus '2026-01-01T08:00:02.1245780Z';$d=Get-PestoJoinReceiptDecision $r $s 'example.test';Assert ($d.Blocked -and $d.Phase -eq 'PendingRestart')}
Case 'Boot exactly at receipt creation does not prove a later restart' {$r=New-Receipt;$s=New-JoinedStatus $r.Utc;$d=Get-PestoJoinReceiptDecision $r $s 'example.test';Assert ($d.Phase -eq 'PendingRestart')}
Case 'Boot after receipt with matching Windows state is ready for AD observation' {$r=New-Receipt;$s=New-JoinedStatus '2026-01-01T08:31:00.0000000Z';$d=Get-PestoJoinReceiptDecision $r $s 'example.test';Assert (-not $d.Blocked -and $d.Phase -eq 'ReadyToObserve')}
Case 'Acknowledged join receipt is not blocked' {
    $r=New-UncertainReceipt
    $r|Add-Member NoteProperty Acknowledged (New-Acknowledgement 'Uncertain')
    $s=New-JoinedStatus '2026-01-01T08:31:00.0000000Z'
    $d=Get-PestoJoinReceiptDecision $r $s 'example.test'
    Assert (-not $d.Blocked -and $d.Phase -eq 'Acknowledged')
    Assert ($d.Message -like '*jamais compté comme réussi*')
}
Case 'Stale join acknowledgement stays blocked' {
    $r=New-UncertainReceipt
    $r|Add-Member NoteProperty Acknowledged (New-Acknowledgement 'Running')
    $s=New-JoinedStatus '2026-01-01T08:31:00.0000000Z'
    $d=Get-PestoJoinReceiptDecision $r $s 'example.test'
    Assert ($d.Blocked)
}
$failed=@($checks|Where-Object{-not $_.Passed}).Count
$report=[pscustomobject]@{Passed=($checks.Count-$failed);Failed=$failed;Checks=$checks.ToArray();PowerShell=$PSVersionTable.PSVersion.ToString();WindowsExecuted=$false;ADExecuted=$false;Scope='Production local-status and receipt decisions with CIM, registry and event-log doubles'}
if($ReportPath){$report|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $ReportPath -Encoding UTF8}
$report|ConvertTo-Json -Depth 6
if($failed){exit 1}
