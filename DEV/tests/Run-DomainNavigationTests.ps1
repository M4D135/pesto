#requires -Version 5.1
[CmdletBinding()]
param([string]$ReportPath='')
# UI state doubles only. Does not start Pesto, WPF, AD, Windows or a VM.
$ErrorActionPreference='Stop';Set-StrictMode -Off
$root=Split-Path $PSScriptRoot -Parent
$tokens=$null;$errors=$null
$core=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'wad/Pesto-Core.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors.Message -join '; ')}
$block=@($core.EndBlock.Statements|Where-Object{$_ -is [Management.Automation.Language.IfStatementAst] -and $_.Extent.Text.Contains("`$Win.FindName('NavRename').IsEnabled=`$false")})
if($block.Count -ne 1){throw 'Expected exactly one domain navigation initialization.'}
$initialize=[scriptblock]::Create($block[0].Extent.Text)
$suite=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'wad/Pesto-SuiteUI.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors.Message -join '; ')}
$fn=$suite.EndBlock.Statements|Where-Object{$_ -is [Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -eq 'Set-PestoSuiteMode'}
. ([scriptblock]::Create($fn.Extent.Text))
function Set-PestoUxPage {param($Page);$script:Page=$Page}
function Get-PestoUxNom {param($Name);return $Name}
function Update-PestoSuiteUI {$script:SuiteUpdated++}
function Update-PestoUxLayout {}
function Refresh-Names {$script:RefreshCalled++}
$script:Win=[pscustomobject]@{Controls=@{}}
$Win|Add-Member ScriptMethod FindName {param($Name);return $this.Controls[$Name]}
$count=0
foreach($inDomain in @($false,$true)){
 foreach($simulation in @($false,$true)){
  foreach($demo in @($false,$true)){
   $script:INDOMAIN=$inDomain;$script:SIM=$simulation;$script:GUI=$demo;$script:Page=''
   foreach($name in @('TabRename','NavRename','NavBatch','HomeQueue','HomePrepare')){$Win.Controls[$name]=[pscustomobject]@{IsEnabled=$true;ToolTip='';Content=''}}
   & $initialize
   foreach($name in @('NavRename','NavBatch','HomePrepare','HomeQueue')){if($Win.Controls[$name].IsEnabled -ne $inDomain){throw "Wrong enabled state for $name (domain=$inDomain, sim=$simulation, demo=$demo)"}}
   if(-not $inDomain -and $Win.Controls.NavBatch.ToolTip -notmatch 'Ajouter au domaine'){throw 'Missing disabled explanation.'}
   $count++
  }
 }
}
$script:INDOMAIN=$false;$script:SuiteMode='Single';$script:SuiteUpdated=0;$script:RefreshCalled=0;$script:EDIT_ROW_INDEX=-1
Set-PestoSuiteMode Batch
if($script:SuiteMode -ne 'Single' -or $script:Page -ne 'Join' -or $script:RefreshCalled -ne 0 -or $script:SuiteUpdated -ne 0){throw 'Programmatic batch navigation bypasses out-of-domain guard.'}
$count++
$script:INDOMAIN=$true;$script:InventoryLoaded=$true
Set-PestoSuiteMode Batch
if($script:SuiteMode -ne 'Batch' -or $script:Page -ne 'Rename' -or $script:SuiteUpdated -ne 1){throw 'In-domain batch navigation regressed.'}
$count++
$report=[pscustomobject]@{Passed=$count;PowerShell=[string]$PSVersionTable.PSVersion;Scope='Local UI state doubles';WindowsExecuted=$false;ADExecuted=$false}
if($ReportPath){$report|ConvertTo-Json|Set-Content -LiteralPath $ReportPath -Encoding UTF8}
$report|ConvertTo-Json
