#requires -Version 5.1
[CmdletBinding()]
param([string]$ReportPath='')
# Functions only, local doubles: no application startup, Windows, WPF, AD or VM.
$ErrorActionPreference='Stop'
Set-StrictMode -Off
$root=Split-Path $PSScriptRoot -Parent
$results=[Collections.Generic.List[object]]::new()
$definitions=@{}
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'wad/Pesto-Contracts.ps1')
foreach($file in @('Pesto-Configuration.ps1','Pesto-Workspace.ps1','Pesto-Core.ps1','Pesto-Directory.ps1','Pesto-Operations.ps1','Pesto-Support.ps1')){
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path (Join-Path $root 'wad') $file),[ref]$tokens,[ref]$errors)
    if($errors.Count){throw ($errors.Message -join '; ')}
    foreach($node in $ast.EndBlock.Statements){if($node -is [Management.Automation.Language.FunctionDefinitionAst]){$definitions[$node.Name]=$node.Extent.Text}}
}
foreach($name in @('Save-Cfg','Apply-CfgHot','Invoke-PestoWorkspaceAction','Apply-SiteSelection','Split-PestoDistinguishedName','Test-PestoDNWithinScope')){. ([scriptblock]::Create($definitions[$name]))}
function Assert-V1 {param($Condition,[string]$Message);if(-not $Condition){throw $Message}}
function Case-V1 {param([string]$Name,[scriptblock]$Body);try{& $Body;$results.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''})}catch{$results.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message})}}
function Show-MsgWarning {param($Message);$script:Warning=[string]$Message}
function Show-MsgError {param($Message);throw $Message}
function Show-MsgInfo {param($Message,$Title)}
function Test-PestoAsyncOperationRunning {return $false}
function Build-CfgFromUI {$script:BuildCalled=$true;throw 'UI must not be read in Consultation.'}
Case-V1 'Consultation refuses saving before reading UI or writing any file' {
    $script:PestoReadOnly=$true;$script:BuildCalled=$false;$script:EDIT_ROW_INDEX=-1;$script:Warning=''
    Save-Cfg
    Assert-V1 (-not $script:BuildCalled) 'Configuration builder was invoked.'
    Assert-V1 ($script:Warning -match 'Consultation') 'Missing reason.'
    $script:PestoReadOnly=$false
}
function Test-CfgValid {param($Config)}
function Get-PestoConfigurationSignature {param($Config);return [string]$Config.Token}
function ConvertTo-PestoPolicy {param($Policy);return $Policy}
function Sync-PestoAppearanceControls {}
function Update-QueueButtons {$script:QueueRefresh++}
function Update-AddButton {$script:AddRefresh++}
function Invalidate-PestoConfigurationPlans {$script:Invalidations++}
function Convert-Value-TF {param($Value);return $Value -eq 'True'}
$script:JsonFile=Join-Path ([IO.Path]::GetTempPath()) ('pesto-v1-config-'+[Guid]::NewGuid().ToString('N')+'.json')
$SetLblStatus=[pscustomobject]@{Text=''}
try{
    Case-V1 'Restoring loaded configuration clears only its restart flag and refreshes commands' {
        $script:CFG=[pscustomobject]@{Token='loaded'}
        @{Token='loaded';POLICY=@{};CONF=@(@{ADM='test';Buffer=10})}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $script:JsonFile -Encoding UTF8
        $script:CfgRestartRequired=$true;$script:JoinLocked=$true;$script:DirectBusy=$true
        $script:QueueRefresh=0;$script:AddRefresh=0;$script:Invalidations=0
        Assert-V1 (Apply-CfgHot) 'Configuration rejected.'
        Assert-V1 (-not $script:CfgRestartRequired) 'Restart flag remained set.'
        Assert-V1 ($script:JoinLocked -and $script:DirectBusy) 'Unrelated operation state changed.'
        Assert-V1 ($script:QueueRefresh -eq 1 -and $script:AddRefresh -eq 1) 'Commands were not refreshed.'
        Assert-V1 ($script:Invalidations -eq 0) 'Unchanged configuration invalidated plans.'
        $script:DirectBusy=$false
    }
}finally{Remove-Item -LiteralPath $script:JsonFile -ErrorAction SilentlyContinue}
$MainTabs=[pscustomobject]@{SelectedIndex=42}
function Set-PestoUxPage {param($Page);$script:Page=$Page}
function Set-PestoSuiteMode {param($Mode);$script:Mode=$Mode}
foreach($pair in @(@('join','Join'),@('names','Names'),@('settings','Settings'),@('help','Help'))){
    Case-V1 ('Palette routes '+$pair[0]+' through page controller') {
        $script:Page='';$MainTabs.SelectedIndex=42
        Invoke-PestoWorkspaceAction -Id $pair[0]
        Assert-V1 ($script:Page -ceq $pair[1]) 'Page controller not called.'
        Assert-V1 ($MainTabs.SelectedIndex -eq 42) 'Raw tab index overwrote page controller.'
    }
}
foreach($id in @('single','batch')){
    Case-V1 ('Palette preserves mode controller decision for '+$id) {
        $MainTabs.SelectedIndex=42;$script:Mode=''
        Invoke-PestoWorkspaceAction -Id $id
        Assert-V1 ($script:Mode -ieq $id) 'Mode controller not called.'
        Assert-V1 ($MainTabs.SelectedIndex -eq 42) 'Mode controller guard bypassed.'
    }
}
function Test-PestoOUPath {param($Path);return [string]$Path -like 'OU=*'}
function ConvertTo-PestoRdnValue {param($Value);return $Value}
function Set-OULabel {param($Label,$Prefix,$Value)}
function Get-PestoKnownComputers {return @()}
function Get-PestoSiteServiceCodes {param($OrganismeOU,$Site,$Computers);return '765'}
function Request-PestoSiteLookup {param($OrganismeOU,$Site);$script:LookupCalls++}
function Check-SameOU {}
function Update-NameList {$script:NamesCalls++}
function Set-PCInfo {param($Text,$Level)}
Case-V1 'ICMP failure leaves services and rename available for the real preflight' {
    $CbSite=[pscustomobject]@{SelectedItem='PARIS'}
    $CbService=[pscustomobject]@{Text='765';Items=[Collections.Generic.List[string]]::new();IsEnabled=$true}
    $CbName=[pscustomobject]@{Items=[Collections.Generic.List[string]]::new();SelectedIndex=0;IsEnabled=$true}
    $BtnAdd=[pscustomobject]@{IsEnabled=$true}
    $ChkMove=[pscustomobject]@{IsChecked=$false;IsEnabled=$true}
    $ChkRename=[pscustomobject]@{IsChecked=$true;IsEnabled=$true}
    $script:INDOMAIN=$true;$script:LOCALHOST=$false;$script:PING=$false
    $script:OU_ORGANISME='OU=ORG,DC=example,DC=test';$script:OU_ACTUELLE='OU=OTHER,DC=example,DC=test'
    $script:LookupCalls=0;$script:NamesCalls=0
    Apply-SiteSelection
    Assert-V1 ($ChkRename.IsChecked -and $ChkRename.IsEnabled) 'Ping disabled rename.'
    Assert-V1 ($CbService.IsEnabled -and $CbService.Text -eq '765') 'Service unavailable or lost.'
    Assert-V1 ($script:LookupCalls -eq 1 -and $script:NamesCalls -eq 1) 'Targeted lookup or names skipped.'
}
foreach($name in @('Select-PestoUniqueComputers','Select-PestoComputersInScope','Test-PestoSiteLookupFresh')){if($definitions[$name]){. ([scriptblock]::Create($definitions[$name]))}}
Case-V1 'Computer snapshots deduplicate without losing names seen on the same GUID' {
    $a=[pscustomobject]@{Name='ONE';ObjectGUID='A';DistinguishedName='CN=ONE,OU=ROOT,DC=test'}
    $b=[pscustomobject]@{Name='TWO';ObjectGUID='A';DistinguishedName='CN=TWO,OU=ROOT,DC=test'}
    $c=[pscustomobject]@{Name='ONE';ObjectGUID='B';DistinguishedName='CN=ONE,OU=OTHER,DC=test'}
    $items=@(Select-PestoUniqueComputers @($a,$a,$b,$c,$null))
    Assert-V1 ($items.Count -eq 3) 'Lost a conflicting observation or retained identical records.'
}
Case-V1 'Nested scope filters at DN boundaries including escaped commas' {
    $items=@([pscustomobject]@{Name='INSIDE';DistinguishedName='CN=X,OU=Child,OU=ROOT,DC=test'},[pscustomobject]@{Name='OUTSIDE';DistinguishedName='CN=X,OU=NotROOT,DC=test'},[pscustomobject]@{Name='ESCAPED';DistinguishedName='CN=X,OU=prefix\,OU=ROOT,DC=test'})
    $selected=@(Select-PestoComputersInScope $items 'OU=ROOT,DC=test')
    Assert-V1 ($selected.Count -eq 1 -and $selected[0].Name -eq 'INSIDE') 'DN suffix matched an escaped separator or wrong scope.'
}
Case-V1 'Site cache freshness expires on monotonic time and refuses incomplete entries' {
    $script:SiteLookupCache=@{site=@()};$tick=[Diagnostics.Stopwatch]::GetTimestamp()
    $script:SiteLookupInfo=@{site=[pscustomobject]@{Tick=$tick;Complete=$true}}
    Assert-V1 (Test-PestoSiteLookupFresh 'site') 'Fresh empty complete result should be cached.'
    $script:SiteLookupInfo.site.Tick=$tick-121*[Diagnostics.Stopwatch]::Frequency
    Assert-V1 (-not (Test-PestoSiteLookupFresh 'site')) 'Cache did not expire.'
    $script:SiteLookupInfo.site.Tick=$tick;$script:SiteLookupInfo.site.Complete=$false
    Assert-V1 (-not (Test-PestoSiteLookupFresh 'site')) 'Partial inventory considered fresh.'
    Assert-V1 (-not (Test-PestoSiteLookupFresh 'missing')) 'Missing cache considered fresh.'
}
. ([scriptblock]::Create($definitions['Get-PestoComponentDiagnostics']))
function Get-PestoRuntimeFiles {return @('Pesto.exe','wad/shared.dll','wad/missing.ps1')}
Case-V1 'Diagnostic covers the canonical runtime and reports modified or missing components independently' {
    $temp=Join-Path ([IO.Path]::GetTempPath()) ('pesto-diag-'+[Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory((Join-Path $temp 'wad'))
    try{
        [IO.File]::WriteAllText((Join-Path $temp 'Pesto.exe'),'local fixture, never executed')
        [IO.File]::WriteAllText((Join-Path (Join-Path $temp 'wad') 'shared.dll'),'local fixture, never loaded')
        $manifest=@{Schema=2;Version='1.0';Scope='Runtime';Files=@(@{Path='Pesto.exe';SHA256=(Get-FileHash -LiteralPath (Join-Path $temp 'Pesto.exe')).Hash},@{Path='wad/shared.dll';SHA256=('0'*64)},@{Path='wad/missing.ps1';SHA256=('0'*64)})}
        $manifest|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path (Join-Path $temp 'wad') 'package.json') -Encoding UTF8
        $r=@(Get-PestoComponentDiagnostics $temp)
        Assert-V1 ($r.Count -eq 3) 'Runtime list not fully checked.'
        Assert-V1 ($r[0].Status -eq 'Cohérent') 'Intact component rejected.'
        Assert-V1 ($r[1].Status -eq 'Empreinte différente') 'Modified component hidden.'
        Assert-V1 ($r[2].Status -eq 'Absent') 'Missing component hidden.'
        Assert-V1 (($r|ConvertTo-Json) -notlike ('*'+$temp+'*')) 'Private path leaked into diagnostic.'
    }finally{Remove-Item -LiteralPath $temp -Recurse -Force}
}
$report=[ordered]@{Scope='Local functions and UI doubles only';PowerShell=$PSVersionTable.PSVersion.ToString();Passed=@($results|Where-Object Passed).Count;Failed=@($results|Where-Object{-not $_.Passed}).Count;Cases=@($results)}
$json=$report|ConvertTo-Json -Depth 5
if($ReportPath){[IO.File]::WriteAllText($ReportPath,$json,[Text.UTF8Encoding]::new($false))}
$json
if($report.Failed){exit 1}
