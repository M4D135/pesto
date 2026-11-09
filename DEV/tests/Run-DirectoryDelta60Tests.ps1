#requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'wad/Pesto-Directory.ps1')
$n=0
function Check($ok,$message){if(-not $ok){Write-Output ('PESTO60-FAIL: '+$message);throw $message};$script:n++}
$root='OU=Machines,DC=example,DC=test';$id=[Guid]::NewGuid().ToString('D');$other=[Guid]::NewGuid().ToString('D')
$before=[pscustomobject]@{ObjectGUID=$id;Name='PC1';DistinguishedName="CN=PC1,$root"}
# DN figes avant l'appel : dans le worker, $root est la table d'inventaire locale, pas l'OU.
$pc2Dn='CN=PC2,'+$root
$renamed=[pscustomobject]@{ObjectGUID=$id;Name='PC2';DistinguishedName="CN=PC2,$root";Deleted=$false}
$r=@(Merge-PestoDirectoryDelta @($before) @($renamed) @($root));Check ($r.Count -eq 1 -and $r[0].Name -eq 'PC2') 'Rename duplicated identity'
Check ($before.Name -eq 'PC1') 'Previous snapshot was mutated'
$r=@(Merge-PestoDirectoryDelta @($before) @([pscustomobject]@{ObjectGUID=$id;Deleted=$true}) @($root));Check ($r.Count -eq 0) 'Deletion retained'
$r=@(Merge-PestoDirectoryDelta @($before) @([pscustomobject]@{ObjectGUID=$id;Name='PC1';DistinguishedName='CN=PC1,OU=Elsewhere,DC=example,DC=test'}) @($root));Check ($r.Count -eq 0) 'Move outside scope retained'
$r=@(Merge-PestoDirectoryDelta @() @($before,$before) @($root));Check ($r.Count -eq 1) 'Duplicate GUID retained'
$refused=$false;try{Merge-PestoDirectoryDelta @($before) @([pscustomobject]@{ObjectGUID='bad';Deleted=$true}) @($root)}catch{$refused=$true};Check $refused 'Invalid GUID accepted'
$script:instance=[Guid]::NewGuid().ToString('D');$scope=($root.ToUpperInvariant()+'|'+$root.ToUpperInvariant())
$state=[pscustomobject]@{Schema=1;DC='dc.example.test';Instance=$script:instance;Scope=$scope;AuthScope='a';Cookie=[byte[]]@(1);Rows=@($before);Utc=[DateTime]::UtcNow.ToString('o')}
Check (Test-PestoDirectoryCursor $state 'dc.example.test' $script:instance $scope 'a') 'Valid cursor refused'
Check (-not(Test-PestoDirectoryCursor $state 'dc2.example.test' $script:instance $scope 'a')) 'Different DC accepted'
Check (-not(Test-PestoDirectoryCursor $state 'dc.example.test' ([Guid]::NewGuid().ToString('D')) $scope 'a')) 'Restored instance accepted'
Check (-not(Test-PestoDirectoryCursor $state 'dc.example.test' $script:instance 'changed' 'a')) 'Changed scope accepted'
Check (-not(Test-PestoDirectoryCursor $state 'dc.example.test' $script:instance $scope 'b')) 'Changed identity accepted'
$state.Utc=[DateTime]::UtcNow.AddMinutes(-16).ToString('o');Check (-not(Test-PestoDirectoryCursor $state 'dc.example.test' $script:instance $scope 'a')) 'Expired cursor accepted';$state.Utc=[DateTime]::UtcNow.ToString('o')
function Get-ADRootDSE {param($Server,$ErrorAction);[pscustomobject]@{dsServiceName='NTDS';defaultNamingContext='DC=example,DC=test'}}
function Get-ADObject {param($Identity,$Properties,$Server,$ErrorAction)
 if([string]$Identity -eq 'NTDS'){return [pscustomobject]@{invocationId=$script:instance}}
 [pscustomobject]@{ObjectGUID=$id;Name='PC2';DistinguishedName=$pc2Dn;ObjectClass='computer'}
}
$script:changes=@([pscustomobject]@{ObjectGUID=$id;Deleted=$false;Container=$false;UnknownClass=$true});$script:transportFail=$false;$script:seenCookie=$null
function Read-PestoDirectoryChanges {param($DC,$NamingContext,$Credential,$Cookie,$Maximum,$Cancellation)
 if($Cancellation.Cancelled){throw [OperationCanceledException]::new('cancelled')}
 if($script:transportFail){throw 'replication rights unavailable'}
 $script:seenCookie=$Cookie;[pscustomobject]@{Cookie=[byte[]]@(2);Changes=$script:changes}
}
$req=[pscustomobject]@{RootOU=$root;ScanOU=$root;AuthScope='a';SyncState=$state;Cancellation=@{Cancelled=$false}}
$r=Get-PestoIncrementalInventory $req 'dc.example.test'
Check ($null -ne $r -and $r.Root.Count -eq 1 -and $r.Root[0].Name -eq 'PC2') 'Incremental rename was not resolved'
Check ($script:seenCookie[0] -eq 1 -and $r.State.Cookie[0] -eq 2) 'Cookie was not advanced with the rows'
Check ($state.Cookie[0] -eq 1 -and $state.Rows[0].Name -eq 'PC1') 'Previous cursor/rows mutated'
$script:instance=[Guid]::NewGuid().ToString('D');$r=Get-PestoIncrementalInventory $req 'dc.example.test';Check ($script:seenCookie.Length -eq 0) 'Instance change reused cookie'
$script:instance=$state.Instance;$script:changes=@([pscustomobject]@{ObjectGUID=$other;Container=$true;Deleted=$false})
Check ($null -eq (Get-PestoIncrementalInventory $req 'dc.example.test')) 'OU change did not require full fallback'
$script:changes=@([pscustomobject]@{ObjectGUID=$id;Container=$false;Deleted=$true;UnknownClass=$true})
$r=Get-PestoIncrementalInventory $req 'dc.example.test';Check ($null -ne $r -and $r.Root.Count -eq 0) 'Deleted cached computer did not disappear'
$script:transportFail=$true;Check ($null -eq (Get-PestoIncrementalInventory $req 'dc.example.test')) 'Denied DirSync did not require full fallback'
$req.Cancellation.Cancelled=$true;$cancelled=$false;try{Get-PestoIncrementalInventory $req 'dc.example.test'}catch [OperationCanceledException]{$cancelled=$true};Check $cancelled 'Cancellation hidden by fallback'

# Branchement des consommateurs reels : le worker d'inventaire livre le delta sans rescan,
# la publication persiste le curseur, la releve suivante le rejoue, un autre compte l'annule,
# et le refus DirSync retombe sur le scan complet a l'interieur du worker.
function Get-ADDomain {[CmdletBinding()]param($Server,$Credential);[pscustomobject]@{DNSRoot='example.test';NetBIOSName='EXAMPLE'}}
function Get-ADOrganizationalUnit {[CmdletBinding()]param($SearchBase,$SearchScope,$Filter,$Properties,$Server,$Credential);throw 'Unexpected site query.'}
$script:ScanCalls=[Collections.Generic.List[string]]::new()
$pcfullDn='CN=PCFULL,'+$root
function Get-ADComputer {[CmdletBinding()]param($Filter,$SearchBase,$SearchScope,$Properties,$Server,$Credential,$LDAPFilter,$ResultSetSize,$ResultPageSize,$Identity)
 $script:ScanCalls.Add([string]$SearchBase)
 [pscustomobject]@{Name='PCFULL';DistinguishedName=$pcfullDn;ObjectGUID=$other}
}
function Get-PestoADLoaderSource {'function Import-PestoADModule {param($ADModulePath)}'}
function Get-PestoNamingContextSource {''}
function Get-PestoDirectoryIdentitySource {'function Get-PestoWindowsAuthIdentity {return $null}; function Add-PestoDomainIdentityCause {param($e,$i,$HasExplicitCredential);return $e}'}
function Write-Log {param($Message,$Level,$ErrorRecord,$Context)}
function Add-LogLine {param($Message,$Level)}
function Update-PestoComputerIndex {}
function Build-NmIndex {}
function Populate-NmFilters {}
function Update-NameGrid {}
function Update-PestoServiceChoices {}
function Update-QueueButtons {}
function Update-AddButton {}
function Stop-PestoAsyncOperation {param($Name)}
function Set-PestoNamesViewState {param($State,$Title,$Detail)}
function Get-PestoUxNom {param($Key);return 'Reessayer'}
$LblStatus=[pscustomobject]@{Text=''}
$script:GUI=$false;$script:Running=$false
$script:DOMAINE='example.test';$script:DC='dc.example.test';$script:OUV=@{};$script:OU=[hashtable]@{ROOT=$root};$script:OU_SCAN=$root;$BasePath='.';$env:COMPUTERNAME=''
$identity='Identity=[string][Security.Principal.WindowsIdentity]::GetCurrent().Name'
if(-not $script:PestoDirectorySnapshotWorker.ToString().Contains($identity)){throw 'Operator identity test seam changed.'}
# Seule l'etiquette d'identite specifique a Windows est remplacee ; toute la logique de collecte reste l'originale.
$snapshot=[scriptblock]::Create($script:PestoDirectorySnapshotWorker.ToString().Replace($identity,"Identity='LOCAL TEST DOUBLE'"))
$script:transportFail=$false;$script:changes=@([pscustomobject]@{ObjectGUID=$id;Deleted=$false;Container=$false;UnknownClass=$true});$script:seenCookie=$null
$reqA=New-PestoDirectorySnapshotRequest -FullInventory
$state2=[pscustomobject]@{Schema=1;DC='dc.example.test';Instance=$script:instance;Scope=($root.ToUpperInvariant()+'|'+$root.ToUpperInvariant());AuthScope=$reqA.AuthScope;Cookie=[byte[]]@(1);Rows=@($before);Utc=[DateTime]::UtcNow.ToString('o')}
$script:PestoDirectorySyncState=$state2
$reqB=New-PestoDirectorySnapshotRequest -FullInventory
Check ($reqB.AuthScope -ceq $reqA.AuthScope -and [object]::ReferenceEquals($reqB.SyncState,$state2)) 'Same session rebuilt its cursor request'
$script:ScanCalls.Clear()
$snap=& $snapshot $reqB
Check ($snap.Complete -and $snap.FullInventory) 'Incremental snapshot not published by the worker'
Check ($script:ScanCalls.Count -eq 0) 'Full scan ran despite incremental delta'
Check ($snap.Root.Count -eq 1 -and $snap.Root[0].Name -eq 'PC2' -and $snap.Names.Count -eq 1) 'Worker did not project the incremental rows'
Check ($script:seenCookie[0] -eq 1 -and $snap.SyncState.Cookie[0] -eq 2) 'Worker did not carry the cursor through the transport'
Check ($snap.RootReceived -eq 1 -and $snap.NamesReceived -eq 1) 'Worker counters did not follow the delta'
Complete-PestoDirectoryRefresh -Snapshot $snap -LockMain $false
Check ([object]::ReferenceEquals($script:PestoDirectorySyncState,$snap.SyncState) -and $script:InventoryLoaded) 'Refresh did not persist the published cursor'
$reqC=New-PestoDirectorySnapshotRequest -FullInventory
Check ([object]::ReferenceEquals($reqC.SyncState,$snap.SyncState) -and $reqC.AuthScope -ceq $reqB.AuthScope) 'Next refresh lost the published cursor'
$credA=New-Object System.Management.Automation.PSCredential('domain\a',(ConvertTo-SecureString 'p1' -AsPlainText -Force))
$reqD=New-PestoDirectorySnapshotRequest -Credential $credA -FullInventory
Check ($reqD.AuthScope -cne $reqC.AuthScope -and $null -eq $reqD.SyncState) 'Another credential kept the authenticated cursor'
$script:transportFail=$true;$script:ScanCalls.Clear()
$reqE=New-PestoDirectorySnapshotRequest -FullInventory
$snap2=& $snapshot $reqE
Check ($script:ScanCalls.Count -ge 1 -and $snap2.Root.Count -eq 1 -and $snap2.Root[0].Name -eq 'PCFULL') 'Denied DirSync did not fall back to the full scan in the worker'
Check ($null -eq $snap2.SyncState) 'Fallback published a stale cursor'
Write-Output "DirectoryDelta60 : $n/$n PASS"
