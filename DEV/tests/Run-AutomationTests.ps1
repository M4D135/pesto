#requires -Version 5.1
[CmdletBinding()]
param([string]$ReportPath='')
# Fonctions réelles, moteur de jonction réel ; seuls Windows/AD/disque reçus sont des doubles locaux.
$ErrorActionPreference='Stop';Set-StrictMode -Off
$dev=Split-Path $PSScriptRoot -Parent;$runtime=Join-Path $dev 'wad'
. (Join-Path $runtime 'Pesto-Integrity.ps1')
. (Join-Path $runtime 'Pesto-Automation.ps1')
. ([scriptblock]::Create((Get-PestoAutomationRuntimeSource $runtime)))
$results=[Collections.Generic.List[object]]::new()
function Assert-Auto {param($Value,[string]$Message='Condition fausse');if(-not $Value){throw $Message}}
function Equal-Auto {param($Actual,$Expected);if($Actual -cne $Expected){throw "Attendu [$Expected], obtenu [$Actual]"}}
function Case-Auto {param([string]$Name,[scriptblock]$Body);try{Reset-Auto;& $Body;$results.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''});Write-Host "PASS $Name"}catch{$results.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message});Write-Host "FAIL $Name : $($_.Exception.Message)"}}
$temp=Join-Path $PSScriptRoot ('.pesto-automation-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
$configFile=Join-Path $temp 'cfg.json'
$oldComputer=$env:COMPUTERNAME;$oldReadOnly=$env:PESTO_READONLY_SESSION
$credential=[pscredential]::new('EXAMPLE\test',(ConvertTo-SecureString 'FAKE-LOCAL-TEST-ONLY' -AsPlainText -Force))
$platformDefinition=${function:Assert-PestoAutomationPlatform}
$joinDefinition=${function:Invoke-PestoJoinExecute}
function Assert-PestoAutomationPlatform {if($script:PlatformFail){throw 'Plateforme refusée (double)'}}
function Import-PestoADModule {param($ADModulePath);$script:Imports++}
function Get-PestoJoinLocalStatus {
    $script:LocalReads++
    if($script:LocalDrift -and $script:LocalReads -ge 3){$script:Local.MachineId='bbbbbbbb-1111-2222-3333-123456789012'}
    return $script:Local
}
function Get-PestoJoinStatePath {Join-Path $temp 'receipt.json'}
function Read-PestoJoinReceipt {param($Path);return $script:Receipt}
function Write-PestoJoinReceipt {
    param($Path,$Receipt);$script:ReceiptWrites++
    if($script:FailWrite -eq $script:ReceiptWrites){throw 'Mock disque refusé'}
    $script:Receipt=$Receipt|ConvertTo-Json -Depth 16|ConvertFrom-Json
    # Newtonsoft/PS7 retourne les int JSON en Int64 ; le contrat .NET Framework est Int32.
    $script:Receipt.Schema=[int]$script:Receipt.Schema
}
function Read-PestoDirectReceipt {param($Path);return $null}
function Get-ItemProperty {[CmdletBinding()]param($LiteralPath,$Name);[pscustomobject]@{MachineGuid=$script:Local.MachineId}}
function Get-PestoInterventions {$script:Interventions.Values}
function Write-PestoIntervention {param($Receipt);$script:LedgerWrites++;$script:Interventions[$Receipt.OperationId]=$Receipt;if($script:CancelAtJoinReceipt -and $Receipt.JoinEvidence.NativeStatus -eq 'Requested'){$script:PestoQueueMonitor.CancelRequested=$true}}
function Test-PestoIsAdministrator {$script:Local.Admin}
function Get-ADDomainController {
    [CmdletBinding()]param([switch]$Discover,$DomainName,[switch]$Writable,$Service,[switch]$ForceDiscover)
    $script:Discoveries++;Equal-Auto $Service 'ADWS';Assert-Auto $Writable;Assert-Auto $Discover
    [pscustomobject]@{HostName='dc.example.local'}
}
function Get-ADDomain {[CmdletBinding()]param($Server,$Credential);[pscustomobject]@{DNSRoot='example.local';DistinguishedName='DC=example,DC=local'}}
function Get-ADOrganizationalUnit {
    [CmdletBinding()]param($Identity,$Server,$Credential)
    $script:OUReads++;$id=if($script:OUDrift -and $script:OUReads -ge 2){'bbbbbbbb-1111-2222-3333-123456789012'}else{'aaaaaaaa-1111-2222-3333-123456789012'}
    [pscustomobject]@{DistinguishedName=$Identity;ObjectGUID=[Guid]$id;Name='Paris'}
}
function Get-ADComputer {
    [CmdletBinding()]param($LDAPFilter,$SearchBase,$SearchScope,$Properties,$ResultSetSize,$Server,$Credential)
    $script:Reads++
    if($LDAPFilter.Contains('*')){
        $script:InventoryReads++;$script:InventoryParams=@{Filter=$LDAPFilter;SearchBase=$SearchBase;SearchScope=$SearchScope;Limit=$ResultSetSize}
        if($script:InventoryFailure){throw 'Mock inventaire AD incomplet'}
        return $script:Inventory
    }
    $script:Checks++
    if($script:CollisionAt -gt 0 -and $script:Checks -ge $script:CollisionAt){return [pscustomobject]@{Name='P123456PR765999';ObjectGUID=[Guid]::NewGuid();DistinguishedName='CN=P123456PR765999,OU=Staging,OU=Postes,OU=Organisme,DC=example,DC=local'}}
}
function Rename-Computer {
 [CmdletBinding()]param($NewName,[switch]$PassThru,[switch]$Force)
 $script:RenameCalls++;$script:Local.ConfiguredName=$NewName;$script:Local.PendingRename=$true
 [pscustomobject]@{HasSucceeded=$true}
}
function Add-Computer {
    [CmdletBinding()]param($DomainName,$OUPath,$NewName,$Options,$Credential,$Server,[switch]$PassThru,[switch]$Force)
    $script:NativeCalls++;$script:NativeName=$script:Local.ConfiguredName
    Assert-Auto (-not $PSBoundParameters.ContainsKey('NewName'));Equal-Auto ($Options -join ',') 'JoinWithNewName,AccountCreate'
    Assert-Auto ($Credential -is [pscredential]);Equal-Auto $Server 'dc.example.local'
    switch($script:NativeMode){
        'False' {[pscustomobject]@{HasSucceeded=$false};return}
        'Missing' {return}
        'Throw' {throw 'Mock RPC perdu'}
        default {[pscustomobject]@{HasSucceeded=$true}}
    }
}
function Restart-Computer {throw 'REDÉMARRAGE INTERDIT DANS LE TEST'}
function New-PSDrive {throw 'PARTAGE INTERDIT DANS LE TEST'}
function Save-AutoConfig {$script:TestConfig|ConvertTo-Json -Depth 15|Set-Content -LiteralPath $configFile -Encoding UTF8}
function Reset-Auto {
    $env:COMPUTERNAME='PESTO-TEST';$env:PESTO_READONLY_SESSION=''
    $script:TestConfig=Get-Content (Join-Path $dev 'tools/cfg.modele-complet.json') -Raw|ConvertFrom-Json
    $script:TestConfig.POLICY|Add-Member -NotePropertyName UnattendedJoinEnabled -NotePropertyValue $true -Force
    $script:TestConfig.POLICY.RandomNameEnabled=$false;Save-AutoConfig
    $script:Local=[pscustomobject]@{Computer='PESTO-TEST';PartOfDomain=$false;Domain='WORKGROUP';ActiveName='PESTO-TEST';ConfiguredName='PESTO-TEST';PendingRename=$false;
        Admin=$true;MachineId='4b008d30-8c02-4894-a829-d3d692012eca';BootUtc='2026-01-01T08:00:00.0000000Z';SecureChannel=$null;DomainRole=0}
    $script:Receipt=$null;$script:Interventions=@{};$script:Imports=0;$script:Discoveries=0;$script:Reads=0;$script:Checks=0;$script:InventoryReads=0
    $script:ReceiptWrites=0;$script:LedgerWrites=0;$script:NativeCalls=0;$script:RenameCalls=0;$script:OUReads=0;$script:LocalReads=0
    $script:PlatformFail=$false;$script:LocalDrift=$false;$script:OUDrift=$false;$script:InventoryFailure=$false
    $script:CancelAtJoinReceipt=$false;$script:FailWrite=0;$script:CollisionAt=0;$script:NativeMode='True';$script:Inventory=@();$script:NativeName=''
}
function Run-Auto {param([switch]$Execute,$CredentialValue=$credential,[string]$Type='P',[string]$SiteCode='PR',[string]$ServiceCode='765',[string]$TargetOU='',$Metadata=$null)
    Invoke-PestoUnattendedJoin -RuntimeRoot $runtime -ConfigPath $configFile -Credential $CredentialValue -Type $Type -SiteCode $SiteCode -ServiceCode $ServiceCode -TargetOU $TargetOU -Execute:$Execute -Metadata $Metadata
}
try{
    Case-Auto 'Policy defaults off and rejects string booleans' {
        Assert-Auto (-not (ConvertTo-PestoPolicy $null).UnattendedJoinEnabled)
        $script:TestConfig.POLICY.UnattendedJoinEnabled='true';Save-AutoConfig;$r=Run-Auto -Execute
        Equal-Auto $r.ExitCode 96;Equal-Auto $Imports 0;Assert-Auto ($r.Message -match 'booléen')
    }
    Case-Auto 'Policy opt-in required before directory access' {$TestConfig.POLICY.UnattendedJoinEnabled=$false;Save-AutoConfig;$r=Run-Auto -Execute;Equal-Auto $r.ExitCode 96;Equal-Auto $Imports 0}
    Case-Auto 'Dry plan reads only, all 999 candidates, shared common RNG available' {
        $before=@(Get-ChildItem $temp).Count;$r=Run-Auto
        Equal-Auto $r.ExitCode 0;Equal-Auto $r.State 'Prepared';Equal-Auto $r.CandidateCount 999;Equal-Auto $r.Plan.NewName 'P123456PR765001'
        Equal-Auto $ReceiptWrites 0;Equal-Auto $LedgerWrites 0;Equal-Auto $NativeCalls 0;Equal-Auto @(Get-ChildItem $temp).Count $before
        Equal-Auto $InventoryParams.SearchBase 'DC=example,DC=local';Equal-Auto $InventoryParams.SearchScope 'Subtree';Assert-Auto ($null -eq $InventoryParams.Limit)
    }
    Case-Auto 'Name, SAM and DNS aliases exclude names across the full domain' {
        $script:Inventory=@([pscustomobject]@{Name='P123456PR765001';SamAccountName='P123456PR765998$';DNSHostName='P123456PR765999.example.local'})
        $r=Run-Auto;Equal-Auto $r.CandidateCount 996;Equal-Auto $r.Plan.NewName 'P123456PR765002'
        Assert-Auto ($InventoryParams.Filter -match 'sAMAccountName' -and $InventoryParams.Filter -match 'dNSHostName')
    }
    Case-Auto 'Random choice covers the complete pool' {
        $TestConfig.POLICY.RandomNameEnabled=$true;Save-AutoConfig
        $seen=[Collections.Generic.HashSet[string]]::new();$high=$false
        1..12|ForEach-Object{$r=Run-Auto;Equal-Auto $r.ExitCode 0;[void]$seen.Add($r.Plan.NewName);if([int]$r.Plan.NewName.Substring(12) -gt 50){$high=$true}}
        Assert-Auto ($seen.Count -gt 1);Assert-Auto $high;Equal-Auto $NativeCalls 0
    }
    Case-Auto 'Last candidate 999 remains selectable' {
        $script:Inventory=@(1..998|ForEach-Object{[pscustomobject]@{Name=('P123456PR765{0:D3}' -f $_)}})
        $r=Run-Auto;Equal-Auto $r.CandidateCount 1;Equal-Auto $r.Plan.NewName 'P123456PR765999'
    }
    Case-Auto 'Exhausted filter refuses without retry or mutation' {
        $script:Inventory=@(1..999|ForEach-Object{[pscustomobject]@{Name=('P123456PR765{0:D3}' -f $_)}})
        $r=Run-Auto -Execute;Equal-Auto $r.ExitCode 96;Equal-Auto $NativeCalls 0;Equal-Auto $InventoryReads 1
    }
    Case-Auto 'Partial AD inventory error never becomes free names' {$script:InventoryFailure=$true;$r=Run-Auto -Execute;Equal-Auto $r.ExitCode 96;Equal-Auto $NativeCalls 0;Equal-Auto $ReceiptWrites 0}
    Case-Auto 'Credential string does not prompt or reach AD' {$r=Run-Auto -Execute -CredentialValue 'EXAMPLE\test';Equal-Auto $r.ExitCode 96;Equal-Auto $Imports 0}
    Case-Auto 'Missing credential is refused' {$r=Run-Auto -CredentialValue $null;Equal-Auto $r.ExitCode 96;Equal-Auto $Imports 0}
    Case-Auto 'Simulation flags cannot turn a silent join into fake success' {$TestConfig.DEBUG.Simulation='true';Save-AutoConfig;$r=Run-Auto -Execute;Equal-Auto $r.ExitCode 96;Equal-Auto $Imports 0}
    Case-Auto 'Read-only session is honored' {$env:PESTO_READONLY_SESSION='1';$r=Run-Auto -Execute;Equal-Auto $r.ExitCode 96;Equal-Auto $Imports 0}
    Case-Auto 'Already joined local machine is refused before AD' {$Local.PartOfDomain=$true;$r=Run-Auto -Execute;Equal-Auto $r.ExitCode 96;Equal-Auto $Imports 0}
    Case-Auto 'Pending rename is refused before AD' {$Local.PendingRename=$true;$r=Run-Auto -Execute;Equal-Auto $r.ExitCode 96;Equal-Auto $Imports 0}
    Case-Auto 'Advanced AD reservation explicitly refused before any write' {$TestConfig.POLICY.ReserveNamesInAD=$true;Save-AutoConfig;$r=Run-Auto -Execute;Equal-Auto $r.ExitCode 96;Equal-Auto $Imports 0;Equal-Auto $ReceiptWrites 0}
    Case-Auto 'Shared coordination explicitly refused before connection' {$TestConfig.POLICY.CoordinationRoot=$temp;Save-AutoConfig;$r=Run-Auto -Execute;Equal-Auto $r.ExitCode 96;Equal-Auto $Imports 0}
    Case-Auto 'Preproduction filter must match configuration' {$r=Run-Auto -Execute -SiteCode PA;Equal-Auto $r.ExitCode 96;Equal-Auto $Imports 0}
    Case-Auto 'OU exclusions and name exclusions apply during preparation' {
        $TestConfig.POLICY.ExcludedNames=@('P123456PR76500?');Save-AutoConfig;$r=Run-Auto;Equal-Auto $r.Plan.NewName 'P123456PR765010'
        $TestConfig.POLICY.ExcludedOUs=@($TestConfig.OUBase[0].OU);Save-AutoConfig;$r=Run-Auto -Execute;Equal-Auto $r.ExitCode 96
    }
    Case-Auto 'Direct production confirms site code against actual OU' {
        $TestConfig.CONF[0].DirectProd='true';Save-AutoConfig
        $target='OU=Paris,'+$TestConfig.OUSite[0].OU
        $r=Run-Auto -Type V -SiteCode PA -ServiceCode INF -TargetOU $target;Equal-Auto $r.ExitCode 0;Equal-Auto $r.Plan.NewName 'V123456PAINF001'
        $r=Run-Auto -SiteCode LY -ServiceCode INF -TargetOU $target;Equal-Auto $r.ExitCode 96
    }
    Case-Auto 'Execute reuses engine mutex, fresh checks, receipts and returns 3010' {
        $r=Run-Auto -Execute;Assert-Auto ($r.ExitCode -eq 3010) ($r|ConvertTo-Json -Depth 4 -Compress)
        Equal-Auto $NativeCalls 1;Equal-Auto $r.Plan.NewName $NativeName;Assert-Auto $r.RestartRequired;Assert-Auto $r.MutationStarted
        Assert-Auto ($ReceiptWrites -ge 2);Assert-Auto ($LedgerWrites -gt 0);Equal-Auto $Receipt.Phase 'PendingRestart'
        $json=$r|ConvertTo-Json -Depth 6;Assert-Auto ($json -notmatch 'FAKE-LOCAL-TEST-ONLY|SecureString|Password|Credential')
        $again=Run-Auto -Execute;Equal-Auto $again.ExitCode 96;Equal-Auto $NativeCalls 1
    }
    Case-Auto 'Fresh collision freezes name and refuses without reroll' {$script:CollisionAt=2;$r=Run-Auto -Execute;Equal-Auto $r.ExitCode 96;Equal-Auto $NativeCalls 0;Equal-Auto $r.Plan.NewName 'P123456PR765001';Equal-Auto $InventoryReads 2}
    Case-Auto 'Last uniqueness check detects collision without native call' {$script:CollisionAt=3;$r=Run-Auto -Execute;Equal-Auto $r.ExitCode 13;Equal-Auto $NativeCalls 0;Equal-Auto $r.Plan.NewName 'P123456PR765001';Equal-Auto $InventoryReads 1}
    Case-Auto 'Local admin refusal cannot request UAC' {$Local.Admin=$false;$r=Run-Auto -Execute;Equal-Auto $r.ExitCode 96;Equal-Auto $Imports 0;Equal-Auto $NativeCalls 0}
    Case-Auto 'Disabled neutral configuration cannot access directory' {
        [IO.File]::WriteAllText($configFile,'{"SchemaVersion":2,"Configured":false}',[Text.UTF8Encoding]::new($false))
        $r=Run-Auto -Execute;Equal-Auto $r.ExitCode 96;Equal-Auto $Imports 0
    }
    Case-Auto 'OU GUID changed since preparation stops execution' {$script:OUDrift=$true;$r=Run-Auto -Execute;Equal-Auto $r.ExitCode 96;Equal-Auto $NativeCalls 0;Equal-Auto $ReceiptWrites 0}
    Case-Auto 'Local machine identity drift stops execution' {$script:LocalDrift=$true;$r=Run-Auto -Execute;Equal-Auto $r.ExitCode 96;Equal-Auto $NativeCalls 0}
    Case-Auto 'Receipt cannot be written so native command is not called' {$script:FailWrite=1;$r=Run-Auto -Execute;Equal-Auto $r.ExitCode 96;Equal-Auto $NativeCalls 0}
    Case-Auto 'Native refusal after local rename remains uncertain' {$script:NativeMode='False';$r=Run-Auto -Execute;Assert-Auto ($r.ExitCode -ceq 97) ('Code '+$r.ExitCode+' : '+$r.Message);Equal-Auto $NativeCalls 1;Equal-Auto $RenameCalls 1;Assert-Auto (-not $r.RestartRequired);Equal-Auto $r.State 'Uncertain';Equal-Auto $script:Receipt.Phase 'Uncertain'}
    Case-Auto 'Prepared local rename effect is recorded and cannot be replayed' {
        $script:NativeMode='False';$r=Run-Auto -Execute
        $ledger=@($script:Interventions.Values)[0];Equal-Auto $ledger.Rename 'Confirmed';Equal-Auto $ledger.Phase 'Uncertain'
        [void](Assert-PestoJoinEvidence $ledger.JoinEvidence);Assert-Auto (Test-PestoJoinIntervention $ledger)
        Equal-Auto $script:Receipt.Phase 'Uncertain';Equal-Auto $script:Local.ConfiguredName $r.Plan.NewName
        $again=Run-Auto -Execute;Equal-Auto $again.ExitCode 96;Equal-Auto $RenameCalls 1;Equal-Auto $NativeCalls 1
    }
    Case-Auto 'Cancellation while saving join request stops native join after prepared name' {$script:CancelAtJoinReceipt=$true;$r=Run-Auto -Execute;Equal-Auto $r.ExitCode 97;Equal-Auto $RenameCalls 1;Equal-Auto $NativeCalls 0;Equal-Auto $script:Receipt.Phase 'Uncertain';Equal-Auto $script:Local.ConfiguredName $r.Plan.NewName}
    Case-Auto 'Native missing response stays uncertain' {$script:NativeMode='Missing';$r=Run-Auto -Execute;Equal-Auto $r.ExitCode 97;Equal-Auto $r.State 'Uncertain';Equal-Auto $NativeCalls 1}
    Case-Auto 'Native transport failure stays uncertain and never retries' {$script:NativeMode='Throw';$r=Run-Auto -Execute;Equal-Auto $r.ExitCode 97;Equal-Auto $NativeCalls 1}
    Case-Auto 'Final receipt failure after native success stays uncertain' {$script:FailWrite=2;$r=Run-Auto -Execute;Equal-Auto $r.ExitCode 97;Assert-Auto (-not $r.RestartRequired);Equal-Auto $NativeCalls 1}
    Case-Auto 'T010 : erreur avant initialisation sans valeurs héritées' {
        $safeMetadata=[pscustomobject]@{Campaign='INHERITED'};$portable=[pscustomobject]@{Invalid='INHERITED'}
        $script:PlatformFail=$true;$r=Run-Auto -Execute -Metadata ([pscustomobject]@{Campaign='C42'})
        Equal-Auto $r.ExitCode 96;Equal-Auto $r.OperationId '';Assert-Auto ($null -eq $r.Metadata);Assert-Auto ($null -eq $r.PreparedPlan)
    }
    Case-Auto 'T010 : métadonnées invalides jamais renvoyées' {
        $r=Run-Auto -Execute -Metadata ([pscustomobject]@{Password='FAKE-INVALID'})
        Equal-Auto $r.ExitCode 96;Equal-Auto $r.OperationId '';Assert-Auto ($null -eq $r.Metadata);Equal-Auto $Imports 0
    }
    Case-Auto 'T010 : exception du contrôle conserve identifiant et métadonnées validées' {
        function Get-PestoJoinPreflight {param($Request);$script:T010Operation=$Request.OperationId;throw 'T010 contrôle interrompu'}
        $r=Run-Auto -Execute -Metadata ([pscustomobject]@{Campaign=' C42 ';Stage='Prepare'})
        Equal-Auto $r.ExitCode 96;Equal-Auto $r.OperationId $script:T010Operation;Assert-Auto ($r.OperationId -match '^[a-f0-9]{32}$')
        Equal-Auto $r.Metadata.Campaign 'C42';Equal-Auto $NativeCalls 0;Assert-Auto ($r.Message -match 'T010 contrôle')
    }
    Case-Auto 'T010 : exception après mutation conserve plan, identifiant et incertitude' {
        function Invoke-PestoJoinExecute {param($Request);$script:T010Operation=$Request.OperationId;$Request.Monitor.MutationStarted=$true;throw 'T010 après mutation factice'}
        $r=Run-Auto -Execute -Metadata ([pscustomobject]@{Campaign=' C42 ';Stage='Prepare'})
        Equal-Auto $r.ExitCode 97;Equal-Auto $r.State 'Uncertain';Assert-Auto $r.MutationStarted
        Equal-Auto $r.OperationId $script:T010Operation;Equal-Auto $r.Metadata.Stage 'Prepare';Assert-Auto ($null -ne $r.PreparedPlan)
        Equal-Auto $NativeCalls 0;Assert-Auto ($r.Message -match 'T010 après mutation')
    }
    Case-Auto 'Actual platform guard rejects unsupported host' {
        if($PSVersionTable.PSEdition -ne 'Desktop'){$thrown=$false;try{& $platformDefinition}catch{$thrown=$true};Assert-Auto $thrown}
    }
}finally{
    $env:COMPUTERNAME=$oldComputer;$env:PESTO_READONLY_SESSION=$oldReadOnly
    Remove-Item -LiteralPath $temp -Recurse -Force
}
$report=[pscustomobject]@{Suite='Automation';PowerShell=$PSVersionTable.PSVersion.ToString();Environment='Local doubles, no Windows/AD/VM';Total=$results.Count;Passed=@($results|Where-Object Passed).Count;Failed=@($results|Where-Object{-not $_.Passed}).Count;Tests=$results.ToArray()}
if($ReportPath){$report|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $ReportPath -Encoding UTF8}
$report|Select-Object Suite,Total,Passed,Failed
if($report.Failed){exit 1}
