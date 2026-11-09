#requires -Version 5.1
# AD cmdlets and operator identity are local doubles. No network, Windows or VM.
$ErrorActionPreference='Stop'
Set-StrictMode -Off
$root=Split-Path $PSScriptRoot -Parent
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path (Join-Path $root 'wad') 'Pesto-Directory.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors.Message -join '; ')}
. (Join-Path $root 'wad/Pesto-Common.ps1');Initialize-PestoRuntimeTypes -Root (Join-Path $root 'wad')
$needed=@('Complete-PestoDirectoryRefresh','Split-PestoDistinguishedName','Test-PestoDNWithinScope','Select-PestoUniqueComputers','Select-PestoComputersInScope','Get-PestoDirectoryProjectionSource','Test-PestoSiteLookupFresh','Request-PestoSiteLookup','Complete-PestoSiteLookup','Get-PestoSiteLookupItems','Get-PestoNameInventoryIndex','Get-PestoSiteServiceCodes')
foreach($node in $ast.EndBlock.Statements){
    if($node -is [Management.Automation.Language.FunctionDefinitionAst]){. ([scriptblock]::Create($node.Extent.Text))}
    if($node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -in @('$script:PestoDirectorySnapshotWorker','$script:PestoSiteLookupWorker')){. ([scriptblock]::Create($node.Extent.Text))}
}
$journal=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'wad/Pesto-Journal.ps1'),[ref]$tokens,[ref]$errors)
foreach($node in $journal.EndBlock.Statements){if($node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Protect-PestoLogText'){. ([scriptblock]::Create($node.Extent.Text))}}
$contracts=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'wad/Pesto-Contracts.ps1'),[ref]$tokens,[ref]$errors)
foreach($node in $contracts.EndBlock.Statements){if($node -is [Management.Automation.Language.FunctionDefinitionAst]){. ([scriptblock]::Create($node.Extent.Text))}}
$identity='Identity=[string][Security.Principal.WindowsIdentity]::GetCurrent().Name'
if(-not $script:PestoDirectorySnapshotWorker.ToString().Contains($identity)){throw 'Operator identity test seam changed.'}
# The only replaced expression is the platform-specific operator label; all collection logic is original.
$snapshot=[scriptblock]::Create($script:PestoDirectorySnapshotWorker.ToString().Replace($identity,"Identity='LOCAL TEST DOUBLE'"))
$script:Calls=[Collections.Generic.List[string]]::new();$script:Mode='normal'
# Le delta tente RootDSE avant le scan : ne jamais laisser l'autoload AD contacter le réseau.
function Get-ADRootDSE {[CmdletBinding()]param($Server,$Credential);throw 'DirSync indisponible dans cette fixture de scan complet.'}
function Get-ADDomain {[CmdletBinding()]param($Server,$Credential);[pscustomobject]@{DNSRoot='example.test';NetBIOSName='EXAMPLE'}}
function Get-ADOrganizationalUnit {throw 'Unexpected site query.'}
function Get-ADComputer {
    [CmdletBinding()]param($Filter,$SearchBase,$SearchScope,$Properties,$Server,$Credential,$LDAPFilter,$ResultSetSize,$ResultPageSize,$Identity)
    $script:Calls.Add([string]$SearchBase)
    if($script:Mode -eq 'denied' -and $SearchBase){throw [UnauthorizedAccessException]::new('Denied by local test double.')}
    if($script:Mode -eq 'limited'){
        if($ResultSetSize -ne 5001){throw 'Expected an extra row to detect truncation.'}
        foreach($i in 1..5001){[pscustomobject]@{Name=('P111301AA765{0:D3}' -f ($i%999+1));DistinguishedName=('CN=X'+$i+',OU=ROOT,DC=example,DC=test');ObjectGUID=[string]$i}}
        return
    }
    $a=[pscustomobject]@{Name='P111301AA765001';DistinguishedName='CN=PC1,OU=Child,OU=ROOT,DC=example,DC=test';ObjectGUID='A'}
    $b=[pscustomobject]@{Name='S111301AA765002';DistinguishedName='CN=PC2,OU=ROOT,DC=example,DC=test';ObjectGUID='B'}
    if($script:Mode -eq 'empty'){return}
    if($script:Mode -eq 'late-error'){$a;throw 'Failure after one row.'}
    if($script:Mode -eq 'cancel-stream'){$a;$script:CollectionCancellation.Cancelled=$true;$b;return}
    $a;$a;$b
}
$request=[pscustomobject]@{Domain='example.test';DC='dc.example.test';Credential=$null;OUSite=@{};RootOU='OU=ROOT,DC=example,DC=test';ScanOU='OU=Child,OU=ROOT,DC=example,DC=test';LocalComputerName='';FullInventory=$true;IncludeLocalHardware=$false;Progress=[hashtable]::Synchronized(@{});ADModulePath='unused';ADLoaderSource='function Import-PestoADModule {param($ADModulePath)}';IdentitySource='function Get-PestoWindowsAuthIdentity {return $null}; function Add-PestoDomainIdentityCause {param($e,$i,$HasExplicitCredential);return $e}';ProjectionSource=(Get-PestoDirectoryProjectionSource)}
$checks=0
function Check-Directory {param($Condition,$Message);if(-not $Condition){throw $Message};$script:checks++}
$r=& $snapshot $request
Check-Directory ($script:Calls.Count -eq 1) 'Nested scan made a duplicate AD request.'
Check-Directory ($r.Root.Count -eq 2 -and $r.Names.Count -eq 1) 'Deduplication or nested filtering failed.'
Check-Directory ($request.Progress.State.Stage -eq 'Finalisation de la collecte') 'Missing final progress state.'
Check-Directory ($r.Complete -and $r.RootReceived -eq 3 -and $r.NamesReceived -eq 0) 'Received counters must include duplicate received rows, not inferred rows.'
$request|Add-Member NoteProperty MaxInventoryRows 3
$r=& $snapshot $request
Check-Directory ($r.Complete -and $r.Root.Count -eq 2) 'Exact limit with EOF must remain complete.'
$request.MaxInventoryRows=2;$rejected=$false;$partial=@()
try{$partial=@(& $snapshot $request)}catch{$rejected=$true}
Check-Directory ($rejected -and $partial.Count -eq 0) 'Overflow published a partial snapshot.'
$request.MaxInventoryRows=3
foreach($mode in @('late-error','cancel-stream')){
    $script:Mode=$mode;$script:CollectionCancellation=[hashtable]::Synchronized(@{Cancelled=$false})
    $request|Add-Member NoteProperty Cancellation $script:CollectionCancellation -Force
    $rejected=$false;$partial=@();try{$partial=@(& $snapshot $request)}catch{$rejected=$true}
    Check-Directory ($rejected -and $partial.Count -eq 0) ('Interrupted collection published partial data: '+$mode)
}
$script:CollectionCancellation.Cancelled=$false;$script:Mode='empty';$r=& $snapshot $request
Check-Directory ($r.Complete -and $r.RootReceived -eq 0 -and $r.Root.Count -eq 0) 'Empty complete inventory was rejected or invented.'
$request.Cancellation.Cancelled=$true;$script:Calls.Clear();$rejected=$false
try{& $snapshot $request|Out-Null}catch{$rejected=$true}
Check-Directory ($rejected -and $script:Calls.Count -eq 0) 'Cancelled request started an inventory read.'
$request.Cancellation.Cancelled=$false;$script:Mode='normal';$request.MaxInventoryRows=200000
$script:Calls.Clear();$request.ScanOU='OU=Separate,DC=example,DC=test';$r=& $snapshot $request
Check-Directory ($script:Calls.Count -eq 2) 'An external scope was incorrectly reused.'
$site=[pscustomobject]@{Key='local';DC='dc.example.test';Credential=$null;Prefix='111301';Tag='AA';SiteOU='OU=Child,OU=ROOT,DC=example,DC=test';ADLoaderSource=$request.ADLoaderSource;ADModulePath='unused'}
$script:Calls.Clear();$r=& $script:PestoSiteLookupWorker $site
Check-Directory ($r.Complete -and $r.Items.Count -eq 2 -and $script:Calls.Count -eq 2) 'Complete site query not deduplicated.'
$script:Mode='limited';$r=& $script:PestoSiteLookupWorker $site
Check-Directory (-not $r.Complete -and $r.Issues.Count -eq 2) 'Result cap presented as complete.'
$script:Mode='denied';$r=& $script:PestoSiteLookupWorker $site
Check-Directory (-not $r.Complete -and $r.Issues.Count -eq 1 -and $r.Items.Count -gt 0) 'Partial query hidden or successful observations discarded.'
function Get-SiteTag {param($SiteName);return 'AA'}
function ConvertTo-PestoRdnValue {param($Text);return $Text}
function Test-PestoOUPath {param($Path);return $true}
function Test-PestoAsyncOperationRunning {param($Name);return $false}
function Get-PestoADLoaderSource {return 'local mock'}
function Start-PestoAsyncOperation {param($Name,$ScriptBlock,$ArgumentList,[switch]$Replace,$TimeoutSec,$CallbackContext,$OnSuccess,$OnError);$script:Launches++;return $true}
$script:GUI=$false;$script:INDOMAIN=$true;$script:PREFIXE='111301';$script:DOMAINE='example.test';$script:DC='dc.example.test';$BasePath='.';$script:SiteLookupCache=@{};$script:SiteLookupInfo=@{};$script:Launches=0
Request-PestoSiteLookup -OrganismeOU 'OU=ROOT,DC=example,DC=test' -Site 'Site'
Check-Directory ($script:Launches -eq 1) 'Uncached site was not requested.'
$key=$script:SiteLookupKey;$script:SiteLookupCache[$key]=@();$script:SiteLookupInfo[$key]=[pscustomobject]@{Complete=$true;Tick=[Diagnostics.Stopwatch]::GetTimestamp()}
Request-PestoSiteLookup -OrganismeOU 'OU=ROOT,DC=example,DC=test' -Site 'Site'
Check-Directory ($script:Launches -eq 1) 'Fresh cache made another request.'
Request-PestoSiteLookup -OrganismeOU 'OU=ROOT,DC=example,DC=test' -Site 'Site' -Force
Check-Directory ($script:Launches -eq 2) 'Explicit refresh was ignored.'
$script:SiteLookupInfo[$key].Tick-=121*[Diagnostics.Stopwatch]::Frequency
Request-PestoSiteLookup -OrganismeOU 'OU=ROOT,DC=example,DC=test' -Site 'Site'
Check-Directory ($script:Launches -eq 3) 'Expired cache was not requested.'
function Write-Log {param($Message,$Level,$ErrorRecord,$Context)}
function Add-LogLine {param($Message,$Level)}
function Update-PestoServiceChoices {}
function Build-NmIndex {}
function Populate-NmFilters {}
function Update-NameGrid {}
$script:Computers=@([pscustomobject]@{Name='P111301AA765001'})
$script:DirectoryNameSnapshot=@([pscustomobject]@{Name='P111301AA765002'})
$script:AffectedNameSnapshot=@([pscustomobject]@{Name='P111301AA765005'})
$script:SiteLookupCache=@{local=@([pscustomobject]@{Name='P111301AA765003'})}
$result=[pscustomobject]@{Key='local';Items=@([pscustomobject]@{Name='P111301AA765004'});Complete=$false;CollectedUtc=[datetime]::UtcNow.ToString('o');Issues=@('partial local fixture');DC='dc.example.test';Ms=1}
Complete-PestoSiteLookup -Result $result -Key 'local'
Check-Directory ((@($script:ComputersNoms.Name|Sort-Object) -join ',') -eq 'P111301AA765001,P111301AA765002,P111301AA765003,P111301AA765004,P111301AA765005') 'Partial site refresh forgot already occupied names or base/post-operation inventory.'
$result.Complete=$true;$result.Issues=@()
Complete-PestoSiteLookup -Result $result -Key 'local'
Check-Directory ((@($script:ComputersNoms.Name|Sort-Object) -join ',') -eq 'P111301AA765001,P111301AA765002,P111301AA765004,P111301AA765005') 'Complete site refresh failed to replace previous site data or retain base inventory.'
# Un même snapshot conserve son index ; un nouveau tableau l'invalide.
$inventory=@([pscustomobject]@{Name='P111301AA765001';DistinguishedName='CN=A,OU=Site,OU=ROOT,DC=example,DC=test'},[pscustomobject]@{Name='S111301BBINF000';DistinguishedName='CN=B,OU=Site,OU=ROOT,DC=example,DC=test'},[pscustomobject]@{Name='P222222AACPT001';DistinguishedName='CN=C,OU=Site,OU=ROOT,DC=example,DC=test'},[pscustomobject]@{Name='INVALID'})
$first=Get-PestoNameInventoryIndex $inventory;$again=Get-PestoNameInventoryIndex $inventory
Check-Directory ([object]::ReferenceEquals($first,$again)) 'Same inventory rebuilt its index.'
Check-Directory ($first.Entries.Count -eq 3 -and $first.ByBase['P111301AA765'].Contains(1) -and $first.ByBase['S111301BBINF'].Contains(0)) 'Index lost a valid current name or included an invalid one.'
$codes=@(Get-PestoSiteServiceCodes -OrganismeOU 'OU=ROOT,DC=example,DC=test' -Site 'Site' -Computers $inventory)
Check-Directory (($codes -join ',') -eq '765,INF') 'Site projection lost OU service, included a foreign prefix, or changed sort.'
Check-Directory ([object]::ReferenceEquals($first,$script:NameInventoryIndex)) 'Service choices parsed names again rather than using the existing index.'
$replacement=@([pscustomobject]@{Name='P111301AA765002'})
$next=Get-PestoNameInventoryIndex $replacement
Check-Directory (-not [object]::ReferenceEquals($first,$next) -and $next.ByBase['P111301AA765'].Contains(2) -and -not $next.ByBase['P111301AA765'].Contains(1)) 'New inventory reused a stale index.'
# A failed refresh remains visible and preserves previous occupied names.
$before=@($script:SiteLookupCache['local']).Count
Complete-PestoSiteLookup -Failure 'Lecture refusée' -Key 'local'
Check-Directory ($script:SiteLookupState['local'].State -eq 'Failed' -and $script:SiteLookupState['local'].Error -eq 'Lecture refusée') 'Failed refresh not surfaced.'
Check-Directory (@($script:SiteLookupCache['local']).Count -eq $before) 'Failed refresh discarded existing names.'

# 19/10 : a site read answered during a treatment is not lost; opening the service list publishes it and retries the read.
$script:NameListUpdates=0;function Update-NameList {$script:NameListUpdates++}
$script:ServiceChoicesUpdates=0;function Update-PestoServiceChoices {$script:ServiceChoicesUpdates++}
$script:Suspend=$false;$script:Running=$false;$script:PreflightRunning=$false;$script:JoinBusy=$false;$script:DirectBusy=$true
$script:Computers=@([pscustomobject]@{Name='P111301AA765001';DistinguishedName='CN=P111301AA765001,OU=Site,OU=ROOT,DC=example,DC=test'})
$script:DirectoryNameSnapshot=@();$script:AffectedNameSnapshot=@();$script:SiteLookupCache=@{};$script:SiteLookupInfo=@{};$script:SiteLookupState=@{}
$script:KnownComputersCache=$null;$script:ComputersNoms=@();$script:OU_ORGANISME='OU=ROOT,DC=example,DC=test'
$CbSite=[pscustomobject]@{SelectedItem='Site'}
$CbService=[pscustomobject]@{IsEnabled=$true;Text='765';Items=[Collections.ArrayList]::new()};[void]$CbService.Items.Add('765')
$siteItems=@([pscustomobject]@{Name='P111301AA765002';DistinguishedName='CN=P111301AA765002,OU=Site,OU=ROOT,DC=example,DC=test'},[pscustomobject]@{Name='S111301AAINF001';DistinguishedName='CN=S111301AAINF001,OU=Site,OU=ROOT,DC=example,DC=test'})
Complete-PestoSiteLookup -Result ([pscustomobject]@{Key='busy';Items=$siteItems;Complete=$true;CollectedUtc=[datetime]::UtcNow.ToString('o');Issues=@();DC='dc.example.test';Ms=1}) -Key 'busy'
Check-Directory ([bool]$script:ServiceChoicesPending -and $script:ServiceChoicesUpdates -eq 0 -and (@($CbService.Items) -join ',') -eq '765') 'A site read answered during a treatment changed the lists or was forgotten.'
Invoke-PestoServiceDropDownOpened
Check-Directory ((@($CbService.Items) -join ',') -eq '765') 'Service list refreshed during a treatment.'
$script:DirectBusy=$false;$script:Launches=0;$script:SiteLookupKey=''
Invoke-PestoServiceDropDownOpened
Check-Directory ((@($CbService.Items) -join ',') -eq '765,INF' -and $CbService.Text -eq '765' -and -not $script:Suspend) 'Opening the service list did not publish the site services or lost the typed service.'
Check-Directory ($script:NameListUpdates -eq 1 -and -not $script:ServiceChoicesPending) 'Pending site data did not recompute the proposed names once.'
Check-Directory ($script:Launches -eq 1) 'Opening the service list did not retry a site read that never completed.'
$script:SiteLookupCache[$script:SiteLookupKey]=@($siteItems);$script:SiteLookupInfo[$script:SiteLookupKey]=[pscustomobject]@{Complete=$true;Tick=[Diagnostics.Stopwatch]::GetTimestamp()}
Invoke-PestoServiceDropDownOpened
Check-Directory ($script:Launches -eq 1 -and $script:NameListUpdates -eq 1) 'Opening the service list re-read a fresh site or recomputed names without new data.'
$CbSite.SelectedItem='PREPROD';$CbService.Items.Clear();[void]$CbService.Items.Add('TRANSIT')
Invoke-PestoServiceDropDownOpened
Check-Directory ((@($CbService.Items) -join ',') -eq 'TRANSIT' -and $script:Launches -eq 1) 'PREPROD service list was recomputed.'

# 19/10 : a failed read of the displayed site is retried once, and again only after a success.
$script:Retries=0;function Start-PestoSiteLookupRetry {$script:Retries++}
$script:SiteLookupRetried=@{};$script:SiteLookupKey='shown'
Complete-PestoSiteLookup -Failure 'Créneau de lecture indisponible' -Key 'other'
Complete-PestoSiteLookup -Failure 'Créneau de lecture indisponible' -Key 'shown'
Complete-PestoSiteLookup -Failure 'Créneau de lecture indisponible' -Key 'shown'
Check-Directory ($script:Retries -eq 1) 'A failed site read was not retried exactly once, or a hidden site was retried.'
Complete-PestoSiteLookup -Result ([pscustomobject]@{Key='shown';Items=@();Complete=$true;CollectedUtc=[datetime]::UtcNow.ToString('o');Issues=@();DC='dc.example.test';Ms=1}) -Key 'shown'
Complete-PestoSiteLookup -Failure 'Créneau de lecture indisponible' -Key 'shown'
Check-Directory ($script:Retries -eq 2) 'A later failure after a success was not retried.'

# The publication boundary refuses incomplete and stale responses before changing inventory state.
function Stop-PestoAsyncOperation {param($Name)}
function Set-PestoNamesViewState {param($State,$Title,$Detail)}
function Update-QueueButtons {}
function Update-AddButton {}
function Get-PestoUxNom {param($Key);return 'Reessayer'}
$script:Computers=@([pscustomobject]@{Name='OLD'});$previous=$script:Computers
$script:DirectoryNameSnapshot=@([pscustomobject]@{Name='OLD-NAME'});$previousNames=$script:DirectoryNameSnapshot
$script:DC='old.example.test';$script:NmDirectoryRequestId='current';$LblStatus=[pscustomobject]@{Text=''}
Complete-PestoDirectoryRefresh -Snapshot ([pscustomobject]@{Complete=$false;DC='new.example.test';Root=@();Names=@()}) -LockMain $false -RequestId 'current'
Check-Directory ([object]::ReferenceEquals($previous,$script:Computers) -and [object]::ReferenceEquals($previousNames,$script:DirectoryNameSnapshot) -and $script:DC -ceq 'old.example.test') 'An incomplete response replaced the previous snapshot.'
Complete-PestoDirectoryRefresh -Snapshot ([pscustomobject]@{Complete=$true;DC='new.example.test';Root=@();Names=@()}) -LockMain $false -RequestId 'obsolete'
Check-Directory ([object]::ReferenceEquals($previous,$script:Computers) -and $script:DC -ceq 'old.example.test') 'A stale response replaced the snapshot.'

[pscustomobject]@{Passed=$checks;Scope='Local AD and operator-identity doubles only';PowerShell=$PSVersionTable.PSVersion.ToString();WindowsExecuted=$false}|ConvertTo-Json
