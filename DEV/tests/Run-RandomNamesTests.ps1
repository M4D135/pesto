#requires -Version 5.1
[CmdletBinding()]
param([string]$ReportPath='')
# Pure functions and pinned DLL only; no Windows, WPF, AD or VM execution.
$ErrorActionPreference='Stop';Set-StrictMode -Off
$root=Split-Path $PSScriptRoot -Parent
$defs=@{};$results=[Collections.Generic.List[object]]::new()
foreach($file in @('Pesto-Contracts.ps1','Pesto-Policy.ps1','Pesto-ManagedPolicy.ps1','Pesto-Names.ps1','Pesto-Core.ps1','Pesto-Join.ps1')){
 $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root ('wad/'+$file)),[ref]$tokens,[ref]$errors)
 if($errors.Count){throw ($errors.Message -join '; ')}
 foreach($node in $ast.EndBlock.Statements){if($node -is [Management.Automation.Language.FunctionDefinitionAst]){$defs[$node.Name]=$node.Extent.Text}}
}
foreach($name in @('ConvertTo-PestoPolicy','Get-PestoManagedPolicy','Merge-PestoManagedPolicy','Assert-PestoClosedObject','Test-PestoPropertyPresent','Get-PestoInitialNameIndex','Get-PestoOtherNameIndex','Get-PestoSharedNameSettings','Invoke-PestoOtherNameClick')){. ([scriptblock]::Create($defs[$name]))}
function Get-PestoManagedPolicy {[pscustomobject]@{Values=[pscustomobject]@{};Configured=$false;Source='test'}}
. (Join-Path $root 'wad/Pesto-Common.ps1');Initialize-PestoCommon (Join-Path $root 'wad')
function Assert-Random {param($Value,[string]$Message='Assertion failed');if(-not $Value){throw $Message}}
function Case-Random {param([string]$Name,[scriptblock]$Body);try{& $Body;$results.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''})}catch{$results.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message})}}
Case-Random 'Absent policy enables full random and leaves optional coordination disabled' {
 $p=ConvertTo-PestoPolicy $null;Assert-Random $p.RandomNameEnabled;Assert-Random (-not $p.ReserveNamesInAD);Assert-Random (-not $p.CoordinationRoot);Assert-Random (-not $p.CoordinationRequired)
}
Case-Random 'Empty policy schema enables random' {Assert-Random (ConvertTo-PestoPolicy ([pscustomobject]@{Schema=1})).RandomNameEnabled}
Case-Random 'Legacy explicit 0 and 1 remain opt-out' {foreach($v in @(0,1)){Assert-Random (-not (ConvertTo-PestoPolicy ([pscustomobject]@{Schema=1;RandomNameChoice=$v})).RandomNameEnabled)}}
Case-Random 'Legacy positive setting maps to whole pool without numeric limit' {foreach($v in @(2,50)){$p=ConvertTo-PestoPolicy ([pscustomobject]@{Schema=1;RandomNameChoice=$v});Assert-Random $p.RandomNameEnabled;Assert-Random (-not $p.PSObject.Properties['RandomNameChoice'])}}
Case-Random 'Conflicting legacy/new choices are rejected' {$rejected=$false;try{ConvertTo-PestoPolicy ([pscustomobject]@{Schema=1;RandomNameChoice=0;RandomNameEnabled=$true})|Out-Null}catch{$rejected=$true};Assert-Random $rejected}
Case-Random 'Invalid legacy/new types rejected' {foreach($p in @(@{Schema=1;RandomNameEnabled='true'},@{Schema=1;RandomNameChoice=-1},@{Schema=1;RandomNameChoice=51},@{Schema=1;RandomNameChoice=2.5})){$rejected=$false;try{ConvertTo-PestoPolicy ([pscustomobject]$p)|Out-Null}catch{$rejected=$true};Assert-Random $rejected}}
Case-Random 'Explicit false selects first; empty pool has no index' {$script:CFG=[pscustomobject]@{POLICY=[pscustomobject]@{Schema=1;RandomNameEnabled=$false}};Assert-Random ((Get-PestoInitialNameIndex 999) -eq 0);Assert-Random ((Get-PestoInitialNameIndex 0) -eq -1)}
Case-Random 'System RNG supports entire pool rather than first 50' {
 $script:CFG=[pscustomobject]@{POLICY=[pscustomobject]@{Schema=1;RandomNameEnabled=$true}};$large=$false
 for($i=0;$i -lt 128;$i++){$index=Get-PestoInitialNameIndex 999;Assert-Random ($index -ge 0 -and $index -lt 999);if($index -ge 50){$large=$true}}
 Assert-Random $large
}
Case-Random 'Other name always excludes current index and handles edge cases' {
 foreach($current in @(0,499,998)){for($i=0;$i -lt 32;$i++){$next=Get-PestoOtherNameIndex 999 $current;Assert-Random ($next -ge 0 -and $next -lt 999 -and $next -ne $current)}}
 Assert-Random ((Get-PestoOtherNameIndex 0 0) -eq -1);Assert-Random ((Get-PestoOtherNameIndex 1 0) -eq 0)
}
Case-Random 'Sequential other name wraps without repetition' {$script:CFG=[pscustomobject]@{POLICY=[pscustomobject]@{Schema=1;RandomNameEnabled=$false}};Assert-Random ((Get-PestoOtherNameIndex 3 2) -eq 0)}
Case-Random 'Other name refuses to alter pending operation selection' {
 $script:CbName=[pscustomobject]@{IsEnabled=$true;Items=@('a','b');SelectedIndex=0};$script:Running=$true
 Invoke-PestoOtherNameClick ([pscustomobject]@{Name='BtnOtherName'}) $null;Assert-Random ($CbName.SelectedIndex -eq 0);$script:Running=$false
}
$failed=@($results|Where-Object{-not $_.Passed}).Count
$report=[pscustomobject]@{PowerShell=[string]$PSVersionTable.PSVersion;Platform='Local only';NoWindows=$true;NoAD=$true;Failed=$failed;Checks=$results.ToArray()}
if($ReportPath){$report|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $ReportPath -Encoding UTF8}
$report|ConvertTo-Json -Depth 6
if($failed){exit 1}
