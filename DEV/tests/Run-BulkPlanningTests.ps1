#requires -Version 5.1
param([string]$ReportPath='')
# Logique de planification seulement ; aucune lecture réseau et aucune mutation.
$ErrorActionPreference='Stop';Set-StrictMode -Off
Add-Type -AssemblyName System.Data
$root=Split-Path $PSScriptRoot -Parent
foreach($file in @('Pesto-Core.ps1','Pesto-Contracts.ps1','Pesto-Directory.ps1','Pesto-Operations.ps1','Pesto-Policy.ps1','Pesto-ManagedPolicy.ps1','Pesto-Names.ps1','Pesto-BatchTools.ps1','Pesto-Configuration.ps1','Pesto-Safety.ps1')){
    $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root ('wad/'+$file)),[ref]$tokens,[ref]$errors)
    if($errors.Count){throw ($errors.Message -join '; ')}
    foreach($node in $ast.EndBlock.Statements){if($node -is [Management.Automation.Language.FunctionDefinitionAst] -or ($node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq '$script:PestoBulkSourceWorker')){. ([scriptblock]::Create($node.Extent.Text))}}
}
. (Join-Path $root 'wad/Pesto-Common.ps1');Initialize-PestoCommon (Join-Path $root 'wad')
# La fusion reste celle du moteur ; seule la lecture GPO est remplacee pour ne pas lire le registre du pilote.
function Get-PestoManagedPolicy {[pscustomobject]@{Values=[pscustomobject]@{};Configured=$false;Source='fixture'}}
$checks=[Collections.Generic.List[object]]::new()
function Assert-Bulk {param($Condition,[string]$Message='Assertion failed');if(-not $Condition){throw $Message}}
function Case-Bulk {param($Name,[scriptblock]$Body);try{& $Body;$checks.Add([pscustomobject]@{Name=$Name;Passed=$true})}catch{$checks.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message})}}
function New-BulkFixture {
    $script:INDOMAIN=$true;$script:PREFIXE='111301';$script:DOMAINE='test.invalid';$script:DC='dc.test.invalid'
    $script:OU=@{ROOT='OU=Postes,DC=test,DC=invalid'};$script:OUV=@{Org='OU=Sites,OU=Postes,DC=test,DC=invalid'}
    $script:CFG=[pscustomobject]@{POLICY=[pscustomobject]@{Schema=1;RandomNameEnabled=$false}}
    $script:sourceOU='OU=AA,OU=Sites,OU=Postes,DC=test,DC=invalid';$script:targetOU='OU=BB,OU=Sites,OU=Postes,DC=test,DC=invalid'
    $pcs=@(foreach($n in @('P111301AA765100','P111301AA765101','P111301BB765001')){[pscustomobject]@{Name=$n;DistinguishedName=('CN='+$n+','+$script:sourceOU);ObjectGUID=[Guid]::NewGuid().ToString('D')}})
    return @{Names=@('P111301AA765100','P111301AA765101');Computers=$pcs;Existing=(New-QueueTable);Prefix='111301';Tag='BB';Service='765';TargetOU=$script:targetOU;Site='BB';Organisme='Org';ReservedNames=@('P111301BB765999')}
}
Case-Bulk 'Opt-out selects first free names and preserves source input' {
    $fixture=New-BulkFixture;$result=New-PestoBulkPlan @fixture
    Assert-Bulk (($result.Rows.Nouveau_Nom -join ',') -eq 'P111301BB765002,P111301BB765003')
    Assert-Bulk ($fixture.Existing.Rows.Count -eq 0 -and $fixture.Computers.Count -eq 3)
}
Case-Bulk 'Default random uses complete filtered pool without duplicates' {
    $fixture=New-BulkFixture;$script:CFG.POLICY=[pscustomobject]@{Schema=1}
    $result=New-PestoBulkPlan @fixture
    Assert-Bulk (($result.Rows.Nouveau_Nom|Select-Object -Unique).Count -eq 2)
    foreach($row in $result.Rows){Assert-Bulk ($row.Nouveau_Nom -match '^P111301BB765[0-9]{3}$');Assert-Bulk ($row.Nouveau_Nom -notin @('P111301BB765001','P111301BB765999'));Assert-Bulk (-not $row.Traiter -and -not $row.Reboot)}
}
$actualInitialNameIndex=${function:Get-PestoInitialNameIndex}
function Get-PestoInitialNameIndex {param([int]$Count);$script:poolSizes.Add($Count);return ($Count-1)}
Case-Bulk 'Whole series remains available after occupied reserved and prior-row exclusions' {
    $fixture=New-BulkFixture;$script:poolSizes=[Collections.Generic.List[int]]::new();$result=New-PestoBulkPlan @fixture
    Assert-Bulk (($result.Rows.Nouveau_Nom -join ',') -eq 'P111301BB765998,P111301BB765997')
    Assert-Bulk (($script:poolSizes -join ',') -eq '997,996')
}
Set-Item Function:Get-PestoInitialNameIndex $actualInitialNameIndex
Case-Bulk 'Preserving an occupied number refuses the whole batch' {
    $fixture=New-BulkFixture;$fixture.KeepNumber=$true;$fixture.ReservedNames=@('P111301BB765100');$failed=$false
    try{New-PestoBulkPlan @fixture|Out-Null}catch{$failed=$true}
    Assert-Bulk ($failed -and $fixture.Existing.Rows.Count -eq 0)
}
Case-Bulk 'Exhausted series never appends a partial plan' {
    $fixture=New-BulkFixture;$fixture.ReservedNames=@(1..999|ForEach-Object{'P111301BB765'+$_.ToString('D3')});$failed=$false
    try{New-PestoBulkPlan @fixture|Out-Null}catch{$failed=$true}
    Assert-Bulk ($failed -and $fixture.Existing.Rows.Count -eq 0)
}

function Reject-Bulk {param([scriptblock]$Body);$failed=$false;try{&$Body|Out-Null}catch{$failed=$true};Assert-Bulk $failed}
Case-Bulk 'LDAP values escape RFC4515 metacharacters without RowFilter grammar' {
 Assert-Bulk ((ConvertTo-PestoLdapFilterValue ('A*()\'+[char]0)) -ceq 'A\2a\28\29\5c\00')
 $f=New-PestoNameConflictFilter @('P111301BB765');Assert-Bulk ($f -match 'servicePrincipalName=HOST/P111301BB765\*' -and $f -match 'RestrictedKrbHost')
 Reject-Bulk {New-PestoNameConflictFilter @('bad*)(')}
}
Case-Bulk 'Source batches retain nested arrays for 1 and 200 sources' {
 $one=Get-PestoBulkSourceBatches @('PC1');Assert-Bulk ($one.Count -eq 1 -and @($one[0]).Count -eq 1 -and $one[0][0] -ceq 'PC1')
 $many=Get-PestoBulkSourceBatches @(1..200|ForEach-Object{'PC'+$_});Assert-Bulk ($many.Count -eq 4 -and @($many[0]).Count -eq 50)
 Reject-Bulk {Get-PestoBulkSourceBatches @(1..201|ForEach-Object{'PC'+$_})}
}
$mockSource=@'
function Import-PestoADModule {param($ADModulePath)}
function Get-ADComputer {
 [CmdletBinding()]param($LDAPFilter,$ResultSetSize,$Properties,$Server,$Credential,$SearchBase,$SearchScope)
 $script:BulkCalls.Add([pscustomobject]@{Kind='source';Server=$Server;Credential=$Credential;Base=$SearchBase;Filter=$LDAPFilter;Limit=$ResultSetSize})
 if($script:BulkMode -eq 'source-failure'){throw 'Read denied'}
 if($script:BulkMode -eq 'source-limit'){return @(1..401|ForEach-Object{$script:BulkSource[0]})}
 if($script:BulkMode -eq 'missing'){return $script:BulkSource[0]}
 if($script:BulkMode -eq 'ambiguous'){
  $other=$script:BulkSource[0].PSObject.Copy();$other.ObjectGUID=[Guid]::NewGuid().ToString('D');return @($script:BulkSource)+@($other)
 }
 if($script:BulkMode -eq 'alias-only'){$other=$script:BulkSource[0].PSObject.Copy();$other.Name='OTHER';$other|Add-Member NoteProperty SamAccountName ($script:BulkSource[0].Name+'$') -Force;return @($other,$script:BulkSource[1])}
 if($script:BulkMode -eq 'invalid-guid'){$other=$script:BulkSource[0].PSObject.Copy();$other.ObjectGUID='bad';return @($other,$script:BulkSource[1])}
 return $script:BulkSource
}
function Get-ADObject {
 [CmdletBinding()]param($LDAPFilter,$ResultSetSize,$Properties,$Server,$Credential,$SearchBase,$SearchScope)
 $script:BulkCalls.Add([pscustomobject]@{Kind='target';Server=$Server;Credential=$Credential;Base=$SearchBase;Filter=$LDAPFilter;Limit=$ResultSetSize})
 if($script:BulkMode -eq 'target-failure'){throw 'Target query denied'}
 if($script:BulkMode -eq 'target-limit'){return @(1..10001|ForEach-Object{$script:BulkConflicts[0]})}
 return $script:BulkConflicts
}
'@
function Read-BulkFixture {
 param([string]$Mode='normal')
 $script:BulkFixture=New-BulkFixture;$script:BulkSource=@($script:BulkFixture.Computers|Select-Object -First 2)
 $script:BulkMode=$Mode;$script:BulkCalls=[Collections.Generic.List[object]]::new()
 $script:BulkConflicts=@([pscustomobject]@{Name='OTHER';SamAccountName='P111301BB765001$';DNSHostName='P111301BB765002.test.invalid';ServicePrincipalName=@('HOST/P111301BB765003.test.invalid','RestrictedKrbHost/P111301BB765004')})
 $script:BulkCredential=[pscredential]::new('LAB\fixture',(ConvertTo-SecureString 'LOCAL-FAKE-ONLY' -AsPlainText -Force))
 $request=[pscustomobject]@{Names=$script:BulkFixture.Names;Batches=(Get-PestoBulkSourceBatches $script:BulkFixture.Names);Domain=$script:DOMAINE;DC=$script:DC;Credential=$script:BulkCredential;Template=@{Prefix='111301';Tag='BB';Service='765';TypeLetter='P'};KeepType=$true;KeepService=$false;KeepNumber=$false;ADModulePath='fixture';Source=((Get-PestoBulkSourceWorkerSource)+$mockSource)}
 & $script:PestoBulkSourceWorker $request
}
Case-Bulk 'Actual worker reads sources AND target aliases/SPNs on same DC credential domain root' {
 $r=Read-BulkFixture
 Assert-Bulk ($r.Ok -and $r.Computers.Count -eq 2 -and $r.OccupiedNames.Count -eq 4)
 foreach($suffix in @('001','002','003','004')){Assert-Bulk (('P111301BB765'+$suffix) -in $r.OccupiedNames)}
 Assert-Bulk ($script:BulkCalls.Count -eq 2)
 foreach($call in $script:BulkCalls){Assert-Bulk ($call.Server -ceq $script:DC -and [object]::ReferenceEquals($call.Credential,$script:BulkCredential) -and $call.Base -ceq 'DC=test,DC=invalid')}
 $fixture=$script:BulkFixture;$fixture.Computers=$r.Computers;$fixture.ReservedNames=$r.OccupiedNames
 $plan=New-PestoBulkPlan @fixture;Assert-Bulk (($plan.Rows.Nouveau_Nom -join ',') -ceq 'P111301BB765005,P111301BB765006')
}
foreach($mode in @('source-failure','source-limit','missing','ambiguous','alias-only','invalid-guid','target-failure','target-limit')){
 $caseMode=$mode
 Case-Bulk ('Actual targeted worker refuses '+$mode+' without partial result') {
  $expected=@{'source-failure'='Read denied';'source-limit'='tronquée';missing='absentes';ambiguous='ambiguës';'alias-only'='Identité AD';'invalid-guid'='Identité AD';'target-failure'='Target query denied';'target-limit'='10 000'}
  $message='';try{Read-BulkFixture -Mode $caseMode|Out-Null}catch{$message=$_.Exception.Message}
  Assert-Bulk ($message -match [regex]::Escape($expected[$caseMode])) $message
 }
}
Case-Bulk 'Name exclusion policy applies to random pool and preserved number' {
 $fixture=New-BulkFixture;$script:CFG.POLICY|Add-Member NoteProperty ExcludedNames @('P111301BB765002','P111301BB765100')
 $plan=New-PestoBulkPlan @fixture;Assert-Bulk ($plan.Rows[0].Nouveau_Nom -ceq 'P111301BB765003')
 $fixture.KeepNumber=$true;Reject-Bulk {New-PestoBulkPlan @fixture}
}
function New-BulkUiFixture {
 $fixture=New-BulkFixture;$script:table=New-QueueTable;$script:cred=$null
 $window=[pscustomobject]@{Tag=$null};$state=[pscustomobject]@{Window=$window;Closed=$false;Epoch=0L;Sources=[pscustomobject]@{Text=($fixture.Names -join "`n")};KeepType=[pscustomobject]@{IsChecked=$true};KeepService=[pscustomobject]@{IsChecked=$false};KeepNumber=[pscustomobject]@{IsChecked=$false}}
 $window.Tag=$state;return $state
}
Case-Bulk 'Current unchanged context can publish targeted preview' {$state=New-BulkUiFixture;$c=New-PestoBulkReadContext $state @('PC1');Assert-Bulk (Test-PestoBulkAdContext $c)}
foreach($kind in @('closed','epoch','source','type','service','number','dc','domain','credential','config','table-replaced','table-edited')){
 $change=$kind
 Case-Bulk ('Late targeted result refused after '+$kind) {
  $state=New-BulkUiFixture;$c=New-PestoBulkReadContext $state @('PC1')
  switch($change){
   closed {$state.Closed=$true};epoch {$state.Epoch++};source {$state.Sources.Text='PC2'}
   type {$state.KeepType.IsChecked=$false};service {$state.KeepService.IsChecked=$true};number {$state.KeepNumber.IsChecked=$true}
   dc {$script:DC='other.test.invalid'};domain {$script:DOMAINE='other.invalid'}
   credential {$script:cred=[pscredential]::new('LAB\other',(ConvertTo-SecureString 'LOCAL-FAKE-ONLY' -AsPlainText -Force))}
   config {$script:CFG.POLICY.RandomNameEnabled=$true}
   table-replaced {$script:table=New-QueueTable};table-edited {$row=$script:table.NewRow();$row.Nom_du_PC='PC1';$script:table.Rows.Add($row)}
  }
  Assert-Bulk (-not(Test-PestoBulkAdContext $c))
 }
}

$failed=@($checks|Where-Object{-not $_.Passed}).Count
$report=[pscustomobject]@{Checks=$checks.ToArray();Failed=$failed;WindowsExecuted=$false;ADExecuted=$false}
if($ReportPath){$report|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $ReportPath -Encoding UTF8}
$report|ConvertTo-Json -Depth 5
if($failed){exit 1}
