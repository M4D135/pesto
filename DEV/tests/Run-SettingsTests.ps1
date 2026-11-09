#requires -Version 5.1
param([string]$ReportPath='')
$ErrorActionPreference='Stop';Set-StrictMode -Off
$root=Split-Path $PSScriptRoot -Parent;$defs=@{};$results=[Collections.Generic.List[object]]::new()
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'wad/Pesto-Contracts.ps1')
foreach($file in @('Pesto-Core.ps1','Pesto-Configuration.ps1','Pesto-Policy.ps1','Pesto-ManagedPolicy.ps1','Pesto-Operations.ps1','Pesto-Directory.ps1','Pesto-Contracts.ps1','Pesto-Safety.ps1','Pesto-Journal.ps1')){
 $t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root ('wad/'+$file)),[ref]$t,[ref]$e);if($e.Count){throw ($e.Message -join '; ')};if($file -eq 'Pesto-Core.ps1'){$coreAst=$ast}
 foreach($n in $ast.EndBlock.Statements){if($n -is [Management.Automation.Language.FunctionDefinitionAst]){$defs[$n.Name]=$n.Extent.Text}}
}
foreach($name in @('Assert-PestoClosedObject','Test-PestoPropertyPresent','Assert-PestoPlainPath','Convert-Value-TF','Test-PestoDnsName','Test-PestoOUPath','Split-PestoDistinguishedName','Get-PestoDomainFromDN','ConvertTo-PestoPolicy','Get-PestoManagedPolicy','Merge-PestoManagedPolicy','Test-CfgValid','Get-PestoStableHash','ConvertTo-PestoCanonicalValue','Get-PestoConfigurationSignature','Get-PestoConfigurationChanges','Get-PestoSettingsSource','Test-PestoSettingsDirty','Get-PestoConfigurationWarnings','Read-PestoConfigCandidate','Invoke-PestoConfigurationCheckWorker','Protect-PestoLogText','Build-PestoPolicyFromUI','Invoke-PestoSettingsFieldLeave','Read-PestoStartupConfig','Invoke-PestoConfigRepairSave')){. ([scriptblock]::Create($defs[$name]))}
function Get-PestoManagedPolicy {[pscustomobject]@{Values=[pscustomobject]@{};Configured=$false;Source='test'}}
function Assert {param($Value,[string]$Message='Assertion failed');if(-not $Value){throw $Message}}
function Case {param([string]$Name,[scriptblock]$Body);try{& $Body;$results.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''})}catch{$results.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message})}}
$fixtureCfg=Get-Content (Join-Path $root 'tools/cfg.modele-complet.json') -Raw|ConvertFrom-Json;$fixtureCfg.Configured=$true;$fixtureCfg.POLICY.CoordinationRoot='';$fixtureCfg.POLICY.CoordinationRequired=$false
Case 'Complete JSON model validates on local parser' {Assert (@(Test-CfgValid $fixtureCfg).Count -eq 0) (@(Test-CfgValid $fixtureCfg) -join '; ')}
Case 'Configuration diff identifies exact array field' {$after=$fixtureCfg|ConvertTo-Json -Depth 20|ConvertFrom-Json;$after.CONF[0].Domaine='new.test';$changes=@(Get-PestoConfigurationChanges $fixtureCfg $after);Assert ($changes.Count -eq 1 -and $changes[0].Champ -eq 'CONF[0].Domaine')}
Case 'Canonical comparison ignores property order' {Assert (@(Get-PestoConfigurationChanges ([pscustomobject]@{A=1;B=2}) ([pscustomobject]@{B=2;A=1})).Count -eq 0)}
Case 'Diff tracks removed and new fields' {$changes=@(Get-PestoConfigurationChanges @{A=1} @{B=2});Assert ($changes.Count -eq 2)}
Case 'Editor source does not replace running context' {$script:CFG=[pscustomobject]@{Tag='running'};$script:SettingsSourceConfig=[pscustomobject]@{Tag='saved'};$script:SettingsEditorConfig=[pscustomobject]@{Tag='draft'};Assert ((Get-PestoSettingsSource).Tag -eq 'draft');Assert ($script:CFG.Tag -eq 'running')}
function Build-CfgFromUI {return $script:TestEditor}
Case 'Dirty state tracks restoration exactly' {$script:TestEditor=@{A=1};$script:SettingsBaselineHash=Get-PestoStableHash $script:TestEditor;Assert (-not(Test-PestoSettingsDirty));$script:TestEditor.A=2;Assert (Test-PestoSettingsDirty);$script:TestEditor.A=1;Assert (-not(Test-PestoSettingsDirty))}
Case 'Invalid policy bool and oversized number remain rejected' {foreach($p in @(@{Schema=1;RandomNameEnabled='true'},@{Schema=1;MaxReaders=999999999999L},@{Schema=1;MaxReaders=2.1})){$blocked=$false;try{ConvertTo-PestoPolicy ([pscustomobject]$p)|Out-Null}catch{$blocked=$true};Assert $blocked}}
Case 'Reserved settings are reported as without effect' {$c=$fixtureCfg|ConvertTo-Json -Depth 20|ConvertFrom-Json;$c.DEBUG|Add-Member -NotePropertyName ForceADM -NotePropertyValue 'true' -Force;Assert ((@(Get-PestoConfigurationWarnings $c) -join ' ') -match 'ForceADM.*sans effet')}
$testRoot=Join-Path $PSScriptRoot ('.settings-'+[Guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($testRoot)
try{
 Case 'Validated import reads full candidate without changing active config' {$path=Join-Path $testRoot 'cfg.json';$fixtureCfg|ConvertTo-Json -Depth 20|Set-Content $path -Encoding UTF8;$c=Read-PestoConfigCandidate $path;Assert ($c.CONF[0].Domaine -eq $fixtureCfg.CONF[0].Domaine);Assert ($script:CFG.Tag -eq 'running')}
 Case 'Malformed import is rejected before publication' {$path=Join-Path $testRoot 'invalid.json';[IO.File]::WriteAllText($path,'{');$blocked=$false;try{Read-PestoConfigCandidate $path|Out-Null}catch{$blocked=$true};Assert $blocked}
 Case 'Oversized import rejected' {$path=Join-Path $testRoot 'large.json';[IO.File]::WriteAllText($path,(' '*1048577));$blocked=$false;try{Read-PestoConfigCandidate $path|Out-Null}catch{$blocked=$true};Assert $blocked}

 # Startup configuration uses the real reader/validator with a data-only dialog
 # double. No WPF startup, AD connection or production configuration is touched.
 function Show-PestoConfigRepair {
  param($Path,$Text,$Errors)
  $script:RepairCalls++;$script:RepairErrors=@($Errors)
  if($script:RepairFailure){throw 'Injected repair window failure'}
  return $script:RepairResult
 }
 $script:RepairCalls=0;$script:RepairErrors=@();$script:RepairFailure=$false;$script:RepairResult=$null
 Case 'Startup valid configuration bypasses repair' {
  $before=$script:RepairCalls;$loaded=Read-PestoStartupConfig (Join-Path $testRoot 'cfg.json')
  Assert ($loaded.CONF[0].Domaine -eq $fixtureCfg.CONF[0].Domaine -and $script:RepairCalls -eq $before)
 }
 Case 'Startup invalid JSON is displayed for repair and cancellation returns null' {
  $before=$script:RepairCalls;$loaded=Read-PestoStartupConfig (Join-Path $testRoot 'invalid.json')
  Assert ($null -eq $loaded -and $script:RepairCalls -eq $before+1 -and $script:RepairErrors.Count -gt 0)
  Assert ([IO.File]::ReadAllText((Join-Path $testRoot 'invalid.json')) -ceq '{')
 }
 Case 'Neutral startup configuration is not accepted by cancelling repair' {
  $neutral=Join-Path $root 'tools/cfg.template.json';$before=[IO.File]::ReadAllText($neutral)
  $loaded=Read-PestoStartupConfig $neutral
  Assert ($null -eq $loaded -and ($script:RepairErrors -join ' ') -match 'Première utilisation')
  Assert ([IO.File]::ReadAllText($neutral) -ceq $before)
 }
 Case 'Startup accepts the validated repair result' {
  $script:RepairResult=$fixtureCfg
  try{$loaded=Read-PestoStartupConfig (Join-Path $testRoot 'invalid.json');Assert ([object]::ReferenceEquals($loaded,$fixtureCfg))}
  finally{$script:RepairResult=$null}
 }
 Case 'Unexpected repair dialog failure is not converted to cancellation' {
  $script:RepairFailure=$true;$caught=$false
  try{try{Read-PestoStartupConfig (Join-Path $testRoot 'invalid.json')|Out-Null}catch{$caught=$_.Exception.Message -eq 'Injected repair window failure'}}
  finally{$script:RepairFailure=$false}
  Assert $caught
 }
 function Write-PestoAtomicText {param($Path,$Text,[switch]$Backup);$script:RepairWrites++;if($script:RepairWriteFailure){throw 'Injected configuration write failure'}}
 Case 'Invalid configuration cannot mark the repair dialog accepted' {
  $script:RepairWrites=0;$script:RepairWriteFailure=$false
  $ctx=[pscustomobject]@{Json=[pscustomobject]@{Text='null'};Errors=[pscustomobject]@{Text=''};Window=[pscustomobject]@{Tag=$null;DialogResult=$false};Path='unused'}
  Invoke-PestoConfigRepairSave ([pscustomobject]@{Tag=$ctx}) $null
  Assert ($script:RepairWrites -eq 0 -and $ctx.Errors.Text -and -not $ctx.Window.DialogResult -and $null -eq $ctx.Window.Tag)
 }
 Case 'Configuration write failure stays in repair without accepting it' {
  $script:RepairWrites=0;$script:RepairWriteFailure=$true
  $ctx=[pscustomobject]@{Json=[pscustomobject]@{Text=($fixtureCfg|ConvertTo-Json -Depth 20)};Errors=[pscustomobject]@{Text=''};Window=[pscustomobject]@{Tag=$null;DialogResult=$false};Path='unused'}
  try{Invoke-PestoConfigRepairSave ([pscustomobject]@{Tag=$ctx}) $null}finally{$script:RepairWriteFailure=$false}
  Assert ($script:RepairWrites -eq 1 -and $ctx.Errors.Text -eq 'Injected configuration write failure' -and -not $ctx.Window.DialogResult -and $null -eq $ctx.Window.Tag)
 }
 # Evaluate the exact top-level Core cancellation branch in a real child script.
 # Real Quit exits this child with code 0; unexpected reader errors still exit 1.
 $statements=@($coreAst.EndBlock.Statements);$configIndex=-1
 for($i=0;$i -lt $statements.Count;$i++){
  if($statements[$i] -is [Management.Automation.Language.AssignmentStatementAst] -and $statements[$i].Left.Extent.Text -eq '$script:CFG' -and $statements[$i].Right.Extent.Text -match '^Read-PestoStartupConfig\b'){$configIndex=$i;break}
 }
 if($configIndex -lt 0){throw 'Startup configuration boundary missing from Core.'}
 $boundary=$statements[$configIndex].Extent.Text+"`n"+$statements[$configIndex+1].Extent.Text
 $child=Join-Path $testRoot 'startup-config-boundary.ps1'
 $childSource=@'
param([string]$Outcome)
$ErrorActionPreference='Stop'
function Close-PestoStartupWindow {}
function Remove-ADModuleSafe {}
function Read-PestoStartupConfig {param($Path);if($Outcome -eq 'Error'){throw 'Injected startup failure'};if($Outcome -eq 'Ready'){return [pscustomobject]@{Configured=$true}};return $null}
'@
 $childSource+="`n"+$defs['Quit']+"`ntry {`n"+$boundary+"`n'Continued'`n}catch{exit 1}"
 [IO.File]::WriteAllText($child,$childSource,[Text.UTF8Encoding]::new($true))
 $hostPath=(Get-Process -Id $PID).Path
 Case 'Voluntary configuration close exits Core boundary successfully without continuing' {
  $out=@(& $hostPath -NoLogo -NoProfile -NonInteractive -File $child -Outcome Cancel 2>$null);$code=$LASTEXITCODE
  Assert ($code -eq 0 -and $out.Count -eq 0)
 }
 Case 'Valid configuration continues past Core startup boundary' {
  $out=@(& $hostPath -NoLogo -NoProfile -NonInteractive -File $child -Outcome Ready 2>$null);$code=$LASTEXITCODE
  Assert ($code -eq 0 -and $out.Count -eq 1 -and $out[0] -eq 'Continued')
 }
 Case 'Unexpected startup reader failure keeps nonzero process exit' {
  $out=@(& $hostPath -NoLogo -NoProfile -NonInteractive -File $child -Outcome Error 2>$null);$code=$LASTEXITCODE
  Assert ($code -ne 0 -and $out -notcontains 'Continued')
 }
}finally{Remove-Item -LiteralPath $testRoot -Recurse -Force}
function Import-PestoADModule {param($Path)}
function Get-DomainController {param($Domain);return 'dc.lab.test'}
function Get-ADOrganizationalUnit {param($Identity,$Properties,$SearchBase,$SearchScope,$Filter,$ResultSetSize,$Server,$ErrorAction,$Credential)
 if($Identity){return [pscustomobject]@{ObjectGUID=[Guid]::NewGuid()}}
 @([pscustomobject]@{Name='Paris'},[pscustomobject]@{Name='Unknown'},[pscustomobject]@{Name='Mixed'})
}
Case 'Read-only AD check resolves exact mapping before wildcard; reports missing and ambiguous' {
 $c=$fixtureCfg|ConvertTo-Json -Depth 20|ConvertFrom-Json;$c.TAGS=@(@{Site='Paris';Tag='PA'},@{Site='P*';Tag='PX'},@{Site='M*';Tag='MA'},@{Site='*ixed';Tag='MB'})
 $r=Invoke-PestoConfigurationCheckWorker ([pscustomobject]@{Source='';Config=$c;ADModulePath='unused';Credential=$null})
 Assert (@($r.Checks|Where-Object{$_.Champ -eq 'Site Paris' -and $_.Etat -eq 'Code résolu'}).Count -gt 0)
 Assert (@($r.Checks|Where-Object{$_.Champ -eq 'Site Unknown' -and $_.Etat -eq 'À corriger'}).Count -gt 0)
 Assert (@($r.Checks|Where-Object{$_.Champ -eq 'Site Mixed' -and $_.Detail -match 'Plusieurs'}).Count -gt 0)
}
# Controls below are local data doubles; no WPF type or window is created.
foreach($name in @('SetTxtExcludedNames','SetTxtExcludedOUs','SetTxtExcludedGroups','SetTxtCoordRoot')){Set-Variable -Name $name -Value ([pscustomobject]@{Text=''})}
foreach($pair in @(@('SetTxtMaxReaders','2'),@('SetTxtReadAttempts','2'),@('SetTxtMaxBatch','25'),@('SetTxtReserveMinutes','120'))){Set-Variable -Name $pair[0] -Value ([pscustomobject]@{Text=$pair[1]})}
foreach($name in @('SetChkCoordRequired','SetChkPasswordFallback','SetChkPrecreated','SetChkReserveAD','SetChkRandomName')){Set-Variable -Name $name -Value ([pscustomobject]@{IsChecked=$false})}
$Win=[pscustomobject]@{};$Win|Add-Member ScriptMethod FindName {param($Name);if($Name -eq 'SetChkUnattendedJoin'){return $script:TestUnattendedControl};return $null}
Case 'Saving other fields preserves unattended opt-in when control is unavailable' {
 $script:SettingsEditorConfig=[pscustomobject]@{POLICY=[pscustomobject]@{Schema=1;UnattendedJoinEnabled=$true}};$script:TestUnattendedControl=$null
 Assert ((Build-PestoPolicyFromUI).UnattendedJoinEnabled -eq $true)
}
Case 'Unattended checkbox can explicitly revoke previous opt-in' {
 $script:TestUnattendedControl=[pscustomobject]@{IsChecked=$false};Assert ((Build-PestoPolicyFromUI).UnattendedJoinEnabled -eq $false)
}
Case 'Unattended option remains false for neutral settings' {
 $script:SettingsEditorConfig=[pscustomobject]@{POLICY=$null};$script:TestUnattendedControl=$null;Assert ((Build-PestoPolicyFromUI).UnattendedJoinEnabled -eq $false)
}
Case 'Returning a field to its loaded value clears dirty status on focus leave' {
 $script:TestEditor=@{A=1};$script:SettingsBaselineHash=Get-PestoStableHash $script:TestEditor
 $script:PestoSettingsHaveErrors=$false;$script:SuspendSet=$false;$SetLblStatus=[pscustomobject]@{Text=''}
 $script:TestEditor.A=2;Invoke-PestoSettingsFieldLeave $null $null;Assert ($SetLblStatus.Text -match 'non enregistrées')
 $script:TestEditor.A=1;Invoke-PestoSettingsFieldLeave $null $null;Assert ($SetLblStatus.Text -match 'Aucune modification')
}
# Assistant de configuration : fonction réelle, contrôles remplacés par des données. Aucune fenêtre ni AD.
. ([scriptblock]::Create($defs['Complete-PestoConfigWizard']))
function New-WizardFixture {
 param([bool]$Clear,[bool]$Hybrid)
 $t={param($v)[pscustomobject]@{Text=$v}}
 @{Domain=(& $t 'lab.test');Prefix=(& $t '111301');RootOU=(& $t 'OU=Postes,DC=lab,DC=test');Org=(& $t 'ORG');SiteOU=(& $t 'OU=Sites,DC=lab,DC=test');PreOU=(& $t 'OU=Prep,DC=lab,DC=test');PreService=(& $t 'pre');Tags=(& $t "PREPROD=PR`nSIEGE=sg")
   Direct=[pscustomobject]@{IsChecked=$false};Hybrid=[pscustomobject]@{IsChecked=$Hybrid};ClearProtection=[pscustomobject]@{IsChecked=$Clear};Error=(& $t '')
   Parent=[pscustomobject]@{Json=(& $t '');Errors=(& $t '')};Window=[pscustomobject]@{DialogResult=$null}}
}
Case 'Wizard writes the protection choice explicitly and keeps the Entra decision' {
 foreach($combo in @(@($true,$true),@($false,$true),@($true,$false))){
  $c=New-WizardFixture -Clear $combo[0] -Hybrid $combo[1];Complete-PestoConfigWizard ([pscustomobject]@{Tag=$c}) $null
  Assert ($c.Window.DialogResult -eq $true) ('Assistant refusé : '+$c.Error.Text)
  $cfg=$c.Parent.Json.Text|ConvertFrom-Json
  Assert ($cfg.CONF[0].ClearProtectionOnMove -is [bool] -and $cfg.CONF[0].ClearProtectionOnMove -eq $combo[0])
  Assert ($cfg.CONF[0].EntraPolicy -ceq $(if($combo[1]){'HybridOnly'}else{'Disabled'}))
  Assert (@(Test-CfgValid $cfg).Count -eq 0) (@(Test-CfgValid $cfg) -join '; ')
  Assert ($cfg.DEBUG.Simulation -eq $false -and $cfg.TAGS.Count -eq 2 -and -not $cfg.PSObject.Properties['POLICY'])
 }
}
Case 'Wizard protection checkbox defaults to the engine value and explains the refusal' {
 $text=$defs['Invoke-PestoConfigWizard'];Assert ($text -match 'x:Name="ClearProtection" IsChecked="True"');Assert ($text -match "ClearProtection='[^']*code 31")
 Assert (-not $defs.ContainsKey('New-PestoWizardConfig'))
}
$failed=@($results|Where-Object{-not $_.Passed}).Count
$report=[pscustomobject]@{PowerShell=[string]$PSVersionTable.PSVersion;NoWindows=$true;NoAD=$true;Failed=$failed;Checks=$results.ToArray()}
if($ReportPath){$report|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $ReportPath -Encoding UTF8};$report|ConvertTo-Json -Depth 6;if($failed){exit 1}
