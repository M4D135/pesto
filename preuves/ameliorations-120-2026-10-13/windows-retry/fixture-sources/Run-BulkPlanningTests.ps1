#requires -Version 5.1
param([string]$ReportPath='')
# Logique de planification seulement ; aucune lecture réseau et aucune mutation.
$ErrorActionPreference='Stop';Set-StrictMode -Off
Add-Type -AssemblyName System.Data
$root=Split-Path $PSScriptRoot -Parent
foreach($file in @('Pesto-Core.ps1','Pesto-Contracts.ps1','Pesto-Directory.ps1','Pesto-Operations.ps1','Pesto-Policy.ps1','Pesto-ManagedPolicy.ps1','Pesto-Names.ps1')){
    $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root ('wad/'+$file)),[ref]$tokens,[ref]$errors)
    if($errors.Count){throw ($errors.Message -join '; ')}
    foreach($node in $ast.EndBlock.Statements){if($node -is [Management.Automation.Language.FunctionDefinitionAst]){. ([scriptblock]::Create($node.Extent.Text))}}
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
$failed=@($checks|Where-Object{-not $_.Passed}).Count
$report=[pscustomobject]@{Checks=$checks.ToArray();Failed=$failed;WindowsExecuted=$false;ADExecuted=$false}
if($ReportPath){$report|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $ReportPath -Encoding UTF8}
$report|ConvertTo-Json -Depth 5
if($failed){exit 1}
