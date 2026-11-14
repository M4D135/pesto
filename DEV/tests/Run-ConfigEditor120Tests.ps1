#requires -Version 5.1
param([string]$ReportPath='')
$ErrorActionPreference='Stop';Set-StrictMode -Off
$root=Split-Path $PSScriptRoot -Parent;$defs=@{};$results=[Collections.Generic.List[object]]::new()
foreach($file in @('Pesto-Directory.ps1','Pesto-ConfigEditor.ps1','Pesto-Configuration.ps1','Pesto-Core.ps1','Pesto-Contracts.ps1','Pesto-Operations.ps1','Pesto-Safety.ps1','Pesto-Policy.ps1','Pesto-ManagedPolicy.ps1')){
 $t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root ('wad/'+$file)),[ref]$t,[ref]$e);if($e.Count){throw ($file+': '+($e.Message -join '; '))};foreach($f in $ast.EndBlock.Statements){if($f -is [Management.Automation.Language.FunctionDefinitionAst]){$defs[$f.Name]=$f.Extent.Text}}
}
foreach($name in @('Add-PestoExcludedConfigValue','Invoke-PestoExcludedGroupPickerWorker','ConvertTo-PestoFilterLiteral','Get-PestoSettingDefinitions','Find-PestoSettings','Get-PestoConfigPathValue','Set-PestoConfigPathValue','Restore-PestoConfigValues','Get-PestoConfigFileStamp','Assert-PestoConfigFileUnchanged','Get-PestoReadableConfigChanges','Format-PestoConfigChanges','Get-PestoConfigNameExamples','ConvertTo-PestoSearchText','Get-PestoConfigurationChanges','ConvertTo-PestoCanonicalValue','Convert-Value-TF','New-PestoComputerName','Get-PestoNamingLayout','Get-PestoActiveNamingConvention','Get-PestoDefaultNamingConvention','Assert-PestoNamingConvention','Get-PestoNamingResolutionNonce','Assert-PestoPlainPath','ConvertTo-PestoPolicy','Merge-PestoManagedPolicy','Get-PestoManagedPolicy','Assert-PestoClosedObject','Test-PestoPropertyPresent','Test-PestoDnsName','Test-PestoOUPath','Split-PestoDistinguishedName','Get-PestoDomainFromDN')){. ([scriptblock]::Create($defs[$name]))}
. (Join-Path $root 'wad/Pesto-Contracts.ps1')
function Assert {param($Value,[string]$Message='Assertion failed');if(-not $Value){throw $Message}}
function Case {param($Name,[scriptblock]$Test);try{& $Test;$results.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''})}catch{$results.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message})}}
function Reject {param([scriptblock]$Test);$blocked=$false;try{& $Test|Out-Null}catch{$blocked=$true};Assert $blocked}
$cfg=Get-Content (Join-Path $root 'tools/cfg.modele-complet.json') -Raw -Encoding UTF8|ConvertFrom-Json
Case 'Search finds settings without accents and combines terms' {$r=@(Find-PestoSettings 'nom aleatoire');Assert ($r.Count -eq 1 -and $r[0].Control -eq 'SetChkRandomName')}
Case 'Every searchable control has a known stable tab' {$d=@(Get-PestoSettingDefinitions);Assert ($d.Count -ge 25 -and @($d|Where-Object{$_.Tab -lt 0 -or $_.Tab -gt 7 -or -not $_.Control}).Count -eq 0)}
Case 'Config field read supports arrays without executing expressions' {Assert ((Get-PestoConfigPathValue $cfg 'CONF.0.Prefixe') -eq $cfg.CONF[0].Prefixe)}
Case 'Restore one field preserves all other unsaved modifications' {$draft=$cfg|ConvertTo-Json -Depth 30|ConvertFrom-Json;$draft.CONF[0].Domaine='changed.example';$draft.CONF[0].Prefixe='123456';$r=Restore-PestoConfigValues $draft $cfg @('CONF.0.Domaine');Assert ($r.CONF[0].Domaine -eq $cfg.CONF[0].Domaine -and $r.CONF[0].Prefixe -eq '123456' -and $draft.CONF[0].Domaine -eq 'changed.example')}
Case 'Restore collection preserves source arrays' {$draft=$cfg|ConvertTo-Json -Depth 30|ConvertFrom-Json;$draft.TAGS=@();$r=Restore-PestoConfigValues $draft $cfg @('TAGS');Assert (@($r.TAGS).Count -eq @($cfg.TAGS).Count -and @($draft.TAGS).Count -eq 0)}
Case 'Unknown config setter paths are rejected' {Reject {Set-PestoConfigPathValue $cfg 'DEBUG.ForceADM' 'true'}}
Case 'Human diff names changed field and its impact' {$after=$cfg|ConvertTo-Json -Depth 30|ConvertFrom-Json;$after.CONF[0].Domaine='changed.example';$r=@(Get-PestoReadableConfigChanges $cfg $after);Assert ($r.Count -eq 1 -and $r[0].Reglage -eq 'Domaine DNS' -and $r[0].Control -eq 'SetTxtDomaine' -and $r[0].Effet -match 'Relancer');Assert ((Format-PestoConfigChanges $r) -match 'Avant.*Après|Avant')}
Case 'Indexed tag diff maps back to editable tags grid' {$after=$cfg|ConvertTo-Json -Depth 30|ConvertFrom-Json;$after.TAGS[0].Tag='ZZ';$r=@(Get-PestoReadableConfigChanges $cfg $after);Assert ($r[0].Control -eq 'SetGridTags')}
Case 'Naming examples use current draft prefix and remain explicitly unverified' {$draft=$cfg|ConvertTo-Json -Depth 30|ConvertFrom-Json;$draft.CONF[0].Prefixe='123456';$rows=@(Get-PestoConfigNameExamples $draft);Assert ($rows.Count -gt 0 -and @($rows|Where-Object{$_.Nom -notmatch '^[PSV]123456' -or $_.Etat -notmatch 'non vérifiée'}).Count -eq 0)}
Case 'Name preview rejects bad service' {Reject {Get-PestoConfigNameExamples $cfg 'bad service'}}
$tmp=Join-Path $PSScriptRoot ('.pesto-config120-'+[Guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($tmp)
try{
 Case 'Disk signature detects external changes without touching the file' {$path=Join-Path $tmp 'cfg.json';[IO.File]::WriteAllText($path,'{"v":1}');$stamp=Get-PestoConfigFileStamp $path;Assert-PestoConfigFileUnchanged $path $stamp;[IO.File]::WriteAllText($path,'{"v":2}');Reject {Assert-PestoConfigFileUnchanged $path $stamp};Assert ([IO.File]::ReadAllText($path) -ceq '{"v":2}')}
 Case 'Missing baseline does not authorize overwriting' {Reject {Assert-PestoConfigFileUnchanged (Join-Path $tmp 'new.json') ''}}
 Case 'Missing file is a distinct version' {Assert ((Get-PestoConfigFileStamp (Join-Path $tmp 'absent.json')) -ceq 'Missing')}
}finally{Remove-Item -LiteralPath $tmp -Recurse -Force}
Case 'Save rechecks disk immediately before atomic publication' {$s=$defs['Save-Cfg'];Assert ($s.IndexOf('Assert-PestoConfigFileUnchanged') -lt $s.IndexOf('Write-PestoAtomicText'));Assert ($s.Contains('Expected $script:SettingsDiskStamp'))}
Case 'OU selection worker contains only bounded AD reads' {$s=$defs['Invoke-PestoOuPickerWorker'];Assert ($s -match 'Get-ADOrganizationalUnit' -and $s -match 'ResultSetSize 2001' -and $s -notmatch 'New-AD|Set-AD|Move-AD|Remove-AD')}
Case 'OU result refuses to overwrite a changed editor' {Assert ($defs['Start-PestoOuPicker'].Contains('EditorHash') -and $defs['Start-PestoOuPicker'].Contains('Get-PestoStableHash (Build-CfgFromUI)'))}
Case 'Local cfg serialization preserves raw values when GPO restricts them' {$s=$defs['Build-PestoPolicyFromUI'];Assert ($s.Contains('-LocalOnly') -and $s.Contains('$pol.IncidentMode=[bool]$current.IncidentMode') -and $s.Contains('$pol.MaxBatch=$current.MaxBatch'))}
Case 'Config incident toggle has an explicit confirmation' {$s=$defs['Save-Cfg'];Assert ($s.Contains('$cfg.POLICY.IncidentMode -ne') -and $s.Contains("-AcceptText 'Confirmer ce réglage'"))}
[xml]$shell=Get-Content (Join-Path $root 'wad/Pesto-Shell.xaml') -Raw -Encoding UTF8
Case 'Every config tool has a reachable named button' {foreach($name in @('SetSearchSettings','SetConfigJson','SetConfigNames','SetBrowseOU','SetResetField','SetResetSection')){Assert ($null -ne $shell.SelectSingleNode('//*[@*[local-name()="Name"]="'+$name+'"]')) $name}}
Case 'OU reader refusal is reported explicitly for retry' {Assert ($defs['Start-PestoOuPicker'].Contains('if(-not $started)') -and $defs['Start-PestoOuPicker'].Contains('Lecture des OU non lancée'))}
Case 'Every setting section is a visible settings tab and every control tooltip names its key' {
 [xml]$shell=[IO.File]::ReadAllText((Join-Path $root 'wad/Pesto-Shell.xaml'))
 $tabs=@($shell.SelectNodes('//*[local-name()="TabItem"]')|ForEach-Object{[string]$_.GetAttribute('Header')})
 $settingsTabs=@($shell.SelectNodes('//*[@*[local-name()="Name"]="SetTabs"]/*[local-name()="TabItem"]')|ForEach-Object{[string]$_.GetAttribute('Header')})
 foreach($d in @(Get-PestoSettingDefinitions)){
  Assert ($tabs -ccontains $d.Section) ('Rubrique sans onglet visible : '+$d.Section)
  if($settingsTabs.Count){Assert ($settingsTabs[$d.Tab] -ceq $d.Section) ('Rubrique '+$d.Section+' affichée sous l''onglet '+$settingsTabs[$d.Tab])}
  $node=$shell.SelectSingleNode('//*[@*[local-name()="Name"]="'+$d.Control+'"]');Assert $node ('Contrôle absent : '+$d.Control)
  Assert (([string]$node.GetAttribute('ToolTip')).Contains($d.Path)) ('Infobulle sans clé : '+$d.Control)
  $help=@($node.Attributes|Where-Object{$_.Name -eq 'AutomationProperties.HelpText'}|ForEach-Object{$_.Value})
  Assert ($help.Count -eq 1 -and $help[0].Contains($d.Path)) ('Aide accessible sans clé : '+$d.Control)
 }
 $labels=@($shell.SelectNodes('//*[local-name()="TextBlock"]')|ForEach-Object{[string]$_.GetAttribute('Text')})
 Assert ($labels -ccontains 'Préfixe (6 chiffres)' -and $labels -ccontains 'Site de préparation (3 caractères)' -and $labels -cnotcontains 'Préfixe (6 caractères)')
}
Case 'Section reset covers every control of the visible advanced tab' {$adv=@(Get-PestoSettingDefinitions|Where-Object{$_.Tab -eq 6});Assert ($adv.Count -eq 7 -and @($adv|Where-Object{$_.Section -cne 'Options avancées'}).Count -eq 0)}

Case 'Excluded group picker preserves existing GUIDs and deduplicates selection' {
 $id='11111111-1111-1111-1111-111111111111';$other='22222222-2222-2222-2222-222222222222'
 $s=Add-PestoExcludedConfigValue -Text $id -Value $other -Kind Group
 Assert (@($s -split '\r?\n').Count -eq 2)
 Assert ((Add-PestoExcludedConfigValue -Text $s -Value $id -Kind Group) -ceq $s)
 Reject {Add-PestoExcludedConfigValue -Text $s -Value 'not-a-guid' -Kind Group}
}
Case 'Excluded OU picker validates DN and keeps the draft only' {
 $dn='OU=Clients,DC=example,DC=test';Assert ((Add-PestoExcludedConfigValue -Text '' -Value $dn -Kind OU) -ceq $dn)
 Reject {Add-PestoExcludedConfigValue -Text '' -Value 'bad' -Kind OU}
}
function Import-PestoADModule {param($ADModulePath)}
function Get-DomainController {param($Domain);if($Domain -ne 'example.test'){throw 'unexpected domain'};'dc.example.test'}
function Get-ADGroup {param($LDAPFilter,$Properties,$ResultSetSize,$Server,$Credential,$ErrorAction)
 $script:GroupArgs=@{Filter=$LDAPFilter;Limit=$ResultSetSize;DC=$Server;Credential=$Credential}
 if($script:GroupReadFailure){throw 'read failed'};$script:GroupRows
}
$request=[pscustomobject]@{Source='';Search='Ops*)(x=*';Domain='example.test';Credential='fixture-only';ADModulePath='unused'}
$script:GroupReadFailure=$false
$script:GroupRows=@([pscustomobject]@{Name='Ops';SamAccountName='Ops';ObjectGUID='11111111-1111-1111-1111-111111111111';DistinguishedName='CN=Ops,OU=Groups,DC=example,DC=test'})
Case 'Group name search is escaped bounded and uses the requested identity' {
 $r=Invoke-PestoExcludedGroupPickerWorker $request
 Assert (@($r.Rows).Count -eq 1 -and $r.Rows[0].GUID -eq $script:GroupRows[0].ObjectGUID)
 Assert ($script:GroupArgs.DC -eq 'dc.example.test' -and $script:GroupArgs.Credential -eq 'fixture-only' -and $script:GroupArgs.Limit -eq 101)
 Assert ($script:GroupArgs.Filter.Contains('\2a\29\28x=\2a'))
}
Case 'Partial or foreign group results never modify exclusions' {
 $one=$script:GroupRows[0];$script:GroupRows=@(1..101|ForEach-Object{$one})
 Reject {Invoke-PestoExcludedGroupPickerWorker $request}
 $script:GroupRows=@($one);$one.DistinguishedName='CN=Ops,DC=other,DC=test'
 Reject {Invoke-PestoExcludedGroupPickerWorker $request}
 $one.DistinguishedName='CN=Ops,DC=example,DC=test';$script:GroupReadFailure=$true
 Reject {Invoke-PestoExcludedGroupPickerWorker $request};$script:GroupReadFailure=$false
}
$failed=@($results|Where-Object{-not $_.Passed});$report=[pscustomobject]@{Suite='ConfigEditor120';Platform=[Environment]::OSVersion.ToString();PowerShell=$PSVersionTable.PSVersion.ToString();Passed=$results.Count-$failed.Count;Failed=$failed.Count;Cases=$results}
if($ReportPath){[IO.File]::WriteAllText($ReportPath,($report|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))};$failed|ForEach-Object{Write-Output ($_.Name+': '+$_.Error)};Write-Output ("ConfigEditor120 : {0}/{1} PASS" -f $report.Passed,$results.Count);if($failed.Count){exit 1}
