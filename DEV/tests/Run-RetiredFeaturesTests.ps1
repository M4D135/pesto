#requires -Version 5.1
[CmdletBinding()]
param([string]$ReportPath='')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$engine=Import-Module (Join-Path $root 'wad/Pesto.Engine.psd1') -Force -PassThru
$optional=Import-Module (Join-Path $root 'integrations/Pesto.Optional.psm1') -Force -PassThru
$cases=[Collections.Generic.List[object]]::new()
function Require {param($Value);if(-not $Value){throw 'Condition non satisfaite.'}}
function Reject {param([scriptblock]$Body);$rejected=$false;try{& $Body|Out-Null}catch{$rejected=$true};Require $rejected}
function Case {param([string]$Name,[scriptblock]$Body);try{& $Body;$cases.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''})}catch{$cases.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message})}}
Case 'Providers removed from the optional module' {
 foreach($name in @('Get-PestoLapsCredential','New-PestoTicketLink','Test-PestoEnvironmentProfile','Get-PestoProfileLaunch')){Require (-not $optional.ExportedFunctions.ContainsKey($name))}
}
Case 'New metadata rejects ticket and asset identifiers' {
 foreach($name in @('Ticket','AssetId')){$value=[pscustomobject]@{Campaign='Deploy'};$value|Add-Member NoteProperty $name 'OLD-42';Reject {ConvertTo-PestoDeploymentMetadata $value}}
}
Case 'Legacy metadata is readable but excluded from normalized output' {
 $old=[pscustomobject]@{Campaign='Deploy';Ticket='OLD-42';AssetId='ASSET-42'}
 $clean=ConvertTo-PestoDeploymentMetadata $old -LegacyReceipt
 Require ($clean.Campaign -ceq 'Deploy' -and @($clean.PSObject.Properties).Count -eq 1)
 Require ($old.Ticket -ceq 'OLD-42')
 Reject {ConvertTo-PestoDeploymentMetadata ([pscustomobject]@{Ticket=42}) -LegacyReceipt}
 Reject {ConvertTo-PestoDeploymentMetadata ([pscustomobject]@{Password='FAKE'}) -LegacyReceipt}
}
Case 'Existing join receipt keeps its phase and identity' {
 $old=[pscustomobject]@{Schema=1;OperationId='33333333333343338333333333333333';Phase='PendingRestart';Utc='2026-10-13T10:00:00Z';BootUtc='2026-10-13T09:00:00Z';MachineId='test-machine';Computer='PC1';NewName='P111301LY765128';Domain='example.test';OU='OU=Postes,DC=example,DC=test';Reference='OLD-42';Metadata=[pscustomobject]@{Ticket='OLD-42';AssetId='ASSET-42'}}
 $read=& $engine {param($Value) Assert-PestoJoinReceiptData $Value} $old
 Require ($read.OperationId -ceq $old.OperationId -and $read.Phase -ceq 'PendingRestart')
}
Case 'Execution plan does not carry retired reference data' {
 $plan=& $engine {New-PestoExecutionPlan ([pscustomobject]@{Rename=$true;Move=$false;Reboot=$false;Computer='PC1';Reference='OLD-42';Metadata=[pscustomobject]@{Campaign='Deploy'}})}
 Require ($null -eq $plan.PSObject.Properties['Reference'] -and $plan.Metadata.Campaign -ceq 'Deploy')
}
Case 'CLI entry points no longer expose the removed argument' {
 foreach($path in @('wad/Invoke-Pesto.ps1','wad/Invoke-PestoAutoJoin.ps1','integrations/Invoke-PestoDeployment.ps1')){
  $command=Get-Command (Join-Path $root $path)
  Require (-not $command.Parameters.ContainsKey('Reference'))
 }
}
Case 'Real XAML no longer offers reference input or a reference column' {
 foreach($path in @('wad/Pesto-Shell.xaml','wad/Pesto-Join.xaml')){
  [xml]$xml=Get-Content -LiteralPath (Join-Path $root $path) -Raw
  $nodes=@($xml.SelectNodes('//*'))
  foreach($node in $nodes){foreach($attribute in $node.Attributes){Require ($attribute.Value -notmatch '(?i)PestoTicketReference|JnReference|\{Binding Reference\}|\bticket\b|\bGLPI\b|\bCMDB\b|\bLAPS\b')}}
 }
}
$report=[pscustomobject]@{Schema=1;Suite='RetiredFeatures';PowerShell=$PSVersionTable.PSVersion.ToString();WindowsExecuted=([Environment]::OSVersion.Platform -eq 'Win32NT');ADExecuted=$false;WPFExecuted=$false;Passed=@($cases|Where-Object Passed).Count;Failed=@($cases|Where-Object{-not $_.Passed}).Count;Cases=$cases.ToArray()}
if($ReportPath){$report|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $ReportPath -Encoding UTF8}
$report|ConvertTo-Json -Depth 8
if($report.Failed){exit 1}
