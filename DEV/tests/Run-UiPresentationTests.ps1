#requires -Version 5.1
param([string]$ReportPath='')
# Fonctions de présentation et contrats XML uniquement : aucun démarrage WPF, Windows ou AD.
$ErrorActionPreference='Stop';Set-StrictMode -Off
$root=Split-Path $PSScriptRoot -Parent;$defs=@{};$results=[Collections.Generic.List[object]]::new()
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'wad/Pesto-Contracts.ps1')
foreach($file in @('Pesto-SuiteUI.ps1','Pesto-UXFlow.ps1','Pesto-Configuration.ps1','Pesto-Interventions.ps1','Pesto-Authentication.ps1','Pesto-Join.ps1','Pesto-Directory.ps1','Pesto-Async.ps1','Pesto-Journal.ps1')){
 $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root ('wad/'+$file)),[ref]$tokens,[ref]$errors);if($errors.Count){throw ($errors.Message -join '; ')}
 foreach($node in $ast.EndBlock.Statements){if($node -is [Management.Automation.Language.FunctionDefinitionAst]){$defs[$node.Name]=$node.Extent.Text}}
}
foreach($name in @('Get-PestoResponsiveLayout','Get-PestoResponsiveFieldCell','Get-PestoConfigurationFieldErrors','Get-PestoPrimaryStep','Get-PestoModeChip','Get-PestoBlockState','Get-PestoSiteReadLabel','Get-PestoDataAgeText','Get-PestoOperationStages','New-PestoQueueMonitor','Set-PestoWorkerStage','Publish-PestoWorkerLog','Protect-PestoLogText','Get-PestoFilteredLogEntries')){. ([scriptblock]::Create($defs[$name]))}
function Test-PestoComputerName {param([string]$Name);return $Name -match '^[A-Za-z0-9][A-Za-z0-9-]{0,14}$'}
function Assert {param($Value,[string]$Message='Assertion failed');if(-not $Value){throw $Message}}
function Case {param([string]$Name,[scriptblock]$Body);try{& $Body;$results.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''})}catch{$results.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message})}}
[xml]$shell=Get-Content -LiteralPath (Join-Path $root 'wad/Pesto-Shell.xaml') -Raw -Encoding UTF8
[xml]$join=Get-Content -LiteralPath (Join-Path $root 'wad/Pesto-Join.xaml') -Raw -Encoding UTF8
function Named {param($Xml,[string]$Name);return $Xml.SelectSingleNode('//*[@*[local-name()="Name"]="'+$Name+'"]')}
function HasAncestor {param($Node,[string]$Name);$current=$Node.ParentNode;while($current){if($current.LocalName -eq $Name){return $true};$current=$current.ParentNode};return $false}
function HasPageScrollAncestor {param($Node)
 # Le viewport global permet l'accès au contenu agrandi ; les pieds d'action restent hors du défilement de leur page.
 $global=Named $shell 'PestoZoomViewport';$current=$Node.ParentNode
 while($current){
  if($current.LocalName -eq 'ScrollViewer' -and $current -ne $global){return $true}
  $current=$current.ParentNode
 }
 return $false
}
Case 'Normal desktop aligns the four home actions in one row' {$r=Get-PestoResponsiveLayout 1460 940 $false $false;Assert (-not $r.SingleColumn -and $r.HomeColumns -eq 4)}
Case 'Intermediate desktop uses two columns for the four home actions' {$r=Get-PestoResponsiveLayout 1100 800 $false $false;Assert ($r.HomeColumns -eq 2)}
Case 'Small display stacks fields and dashboard cards' {$r=Get-PestoResponsiveLayout 760 560 $false $false;Assert ($r.SingleColumn -and $r.HomeColumns -eq 1 -and $r.Short)}
Case 'Collapsed navigation gives space back without changing user preference' {$r=Get-PestoResponsiveLayout 800 800 $true $false;Assert (-not $r.SingleColumn -and $r.ContentWidth -eq 688)}
Case 'Docked help reduces available content only on wide screens' {$r=Get-PestoResponsiveLayout 1500 900 $false $true;Assert ($r.ContentWidth -eq 982);$r=Get-PestoResponsiveLayout 1400 900 $false $true;Assert ($r.ContentWidth -eq 1162)}
Case 'Layout calculation is bounded before window measurement' {$r=Get-PestoResponsiveLayout 0 0 $false $false;Assert ($r.ContentWidth -eq 0 -and $r.SingleColumn)}
Case 'Layout handler never assigns read-only PowerShell automatic variables' {Assert ($defs['Update-PestoSuiteLayout'] -notmatch '(?i)\$(?:HOME|PSHOME|PID|HOST)\s*=')}
Case 'Narrow join form preserves label and input order without overlaps' {
 $positions=@();foreach($row in 0..5){foreach($column in @(0,2)){$p=Get-PestoResponsiveFieldCell $row $column $true;$positions+=$p.Row;Assert ($p.Column -eq 0)}}
 Assert ((@($positions|Sort-Object -Unique).Count) -eq 12)
 Assert ((Get-PestoResponsiveFieldCell 0 2 $true).Row -eq 2);Assert ((Get-PestoResponsiveFieldCell 1 2 $true).Row -eq 3)
 Assert ((Get-PestoResponsiveFieldCell 5 2 $true).Row -eq 11)
}
Case 'Wide form restores original positions exactly' {foreach($row in 0..5){foreach($column in @(0,2)){$p=Get-PestoResponsiveFieldCell $row $column $false;Assert ($p.Row -eq $row -and $p.Column -eq $column)}}}
Case 'Single primary action stays outside page scrolling' {$node=Named $shell 'SuiteDirectRun';Assert ($null -ne $node -and -not (HasPageScrollAncestor $node));Assert ((Named $shell 'SuiteDirectCommands').GetAttribute('Grid.Row') -eq '1')}
Case 'Batch primary action stays outside page scrolling' {Assert (-not(HasPageScrollAncestor (Named $shell 'BtnRun')));Assert ((Named $shell 'SuiteQueueFooter').GetAttribute('Grid.Row') -eq '1')}
Case 'Global zoom viewport is unique and wraps the complete application root' {$nodes=@($shell.SelectNodes('//*[@*[local-name()="Name"]="PestoZoomViewport"]'));Assert ($nodes.Count -eq 1);Assert ($nodes[0].LocalName -eq 'ScrollViewer');Assert ((Named $shell 'SuiteRoot').ParentNode -eq $nodes[0]);Assert ($nodes[0].ParentNode -eq (Named $shell 'PestoZoomHost'))}
Case 'Join service status shares the responsive input cell' {
 $service=Named $join 'JnService';$status=Named $join 'JnServiceState'
 Assert ($service.ParentNode -eq $status.ParentNode -and $service.ParentNode.LocalName -eq 'StackPanel')
 Assert ($service.ParentNode.GetAttribute('Grid.Row') -eq '3' -and $service.ParentNode.GetAttribute('Grid.Column') -eq '2')
}
Case 'Join page fills its viewport without a fixed maximum width' {
 $page=$join.DocumentElement.SelectSingleNode('./*[local-name()="Grid"]/*[local-name()="ScrollViewer"]/*[local-name()="StackPanel"]')
 Assert ($page -and -not $page.HasAttribute('MaxWidth') -and $page.HorizontalAlignment -eq 'Stretch')
}
Case 'Join primary action stays outside page scrolling' {Assert (-not(HasAncestor (Named $join 'JnStart') 'ScrollViewer'))}
Case 'No duplicate named XAML controls after toolbar move' {foreach($xml in @($shell,$join)){$names=@($xml.SelectNodes('//*[@*[local-name()="Name"]]')|Where-Object{-not(HasAncestor $_ 'ControlTemplate') -and -not(HasAncestor $_ 'DataTemplate')}|ForEach-Object{$_.GetAttribute('Name','http://schemas.microsoft.com/winfx/2006/xaml')});Assert (@($names|Group-Object|Where-Object{$_.Count -gt 1}).Count -eq 0)}}
Case 'Domaine and advanced settings scroll on short screens' {foreach($header in @('Domaine','Options avancées')){$tab=$shell.SelectSingleNode('//*[local-name()="TabItem" and @Header="'+$header+'"]');Assert ($tab.FirstChild.LocalName -eq 'ScrollViewer')}}
Case 'Appearance contains density and column tools' {foreach($name in @('SuiteAppearanceDensity','SuiteAppearanceSaveColumns','SuiteAppearanceResetColumns')){Assert ($null -ne (Named $shell $name))}}
Case 'Remote credentials are explained near source choice' {$node=Named $shell 'SuiteRemoteAccountHint';Assert ($node.Text -match 'compte AD explicite' -and $node.TextWrapping -eq 'Wrap')}
Case 'Policy validation errors map to their field and clear after correction' {
 $fields=@(Get-PestoConfigurationFieldErrors @('MaxBatch : hors bornes.','LogRetentionDays : hors bornes.'))
 Assert (@($fields|Where-Object{$_.Name -eq 'SetTxtMaxBatch' -and $_.Message -like 'MaxBatch*'}).Count -eq 1)
 Assert (@($fields|Where-Object{$_.Name -eq 'SetTxtLogRetention' -and $_.Message -like 'LogRetentionDays*'}).Count -eq 1)
 Assert (@(Get-PestoConfigurationFieldErrors @()|Where-Object{$_.Message}).Count -eq 0)
}
Case 'Precise errors are adjacent to common inputs and announced politely' {foreach($name in @('SetTxtDomaine','SetTxtPrefixe','SetTxtBuffer','SetTxtMaxBatch','SetTxtLogRetention','SetTxtOUScan','SetTxtCoordRoot')){$node=Named $shell ($name+'Error');Assert ($null -ne $node -and $node.GetAttribute('AutomationProperties.LiveSetting') -eq 'Polite')}}
Case 'Error reset restores help rather than leaving stale message' {$body=$defs['Show-PestoConfigurationErrors'];Assert ($body.Contains('$control.ToolTip=$original.ToolTip') -and $body.Contains('SetHelpText($control,$original.Help)'))}
Case 'Missing name cannot launch mutation' {$s=Get-PestoPrimaryStep -Computer '' -Busy $false -Blocked $false -Loaded $false -FormReady $false -ResumeMove $false -Rename $true -ReadOnly $false;Assert (-not $s.Enabled -and $s.Action -eq 'None')}
Case 'Unread valid target offers read-only primary action' {$s=Get-PestoPrimaryStep -Computer 'PC-123' -Busy $false -Blocked $false -Loaded $false -FormReady $false -ResumeMove $false -Rename $true -ReadOnly $false;Assert ($s.Action -eq 'Read' -and $s.Enabled)}
Case 'Missing fields offer focus guidance without mutation' {$s=Get-PestoPrimaryStep -Computer 'PC-123' -Loaded $true -FormReady $false -Missing 'Choisissez le site.';Assert ($s.Action -eq 'Prepare' -and $s.Hint -match 'Choisissez le site')}
Case 'Read-only mode never offers execution' {$s=Get-PestoPrimaryStep -Computer 'PC-123' -Loaded $true -FormReady $true -ReadOnly $true;Assert (-not $s.Enabled -and $s.Action -eq 'None')}
Case 'Blocked operation routes to verification instead of execution' {$s=Get-PestoPrimaryStep -Computer 'PC-123' -Loaded $true -FormReady $true -Blocked $true -BlockedAction ReviewDirect;Assert ($s.Enabled -and $s.Action -eq 'ReviewDirect')}
Case 'Busy operations do not offer another launch' {$s=Get-PestoPrimaryStep -Computer 'PC-123' -Loaded $true -FormReady $true -Busy $true;Assert (-not $s.Enabled)}
Case 'Complete preparation offers explicit confirmation flow' {$s=Get-PestoPrimaryStep -Computer 'PC-123' -Loaded $true -FormReady $true -Rename $true;Assert ($s.Action -eq 'Execute' -and $s.Hint -match 'confirmation')}
Case 'Unattended opt-in is distinct from simulation settings' {$node=Named $shell 'SetChkUnattendedJoin';Assert ($node.ToolTip -match 'Inactif par défaut' -and $node.ToolTip -match 'explicite');Assert ($defs['Build-PestoPolicyFromUI'].Contains('$current.UnattendedJoinEnabled'))}
Case 'All two-file layouts remain valid XML without WPF execution' {Assert ($shell.DocumentElement.LocalName -eq 'Window' -and $join.DocumentElement.LocalName -eq 'UserControl')}
Case 'First-start repair wizard uses one apostrophe in its visible label' {
 $match=[regex]::Match($defs['Show-PestoConfigRepair'],'(?s)<Window\s.*?</Window>');Assert $match.Success
 [xml]$repair=$match.Value;Assert ((Named $repair 'Wizard').GetAttribute('Content') -ceq "Créer avec l’assistant")
}
Case 'First-start repair JSON and errors begin at the top of their editors' {
 $match=[regex]::Match($defs['Show-PestoConfigRepair'],'(?s)<Window\s.*?</Window>');Assert $match.Success
 [xml]$repair=$match.Value
 foreach($name in @('Json','Errors')){Assert ((Named $repair $name).GetAttribute('VerticalContentAlignment') -ceq 'Top') ($name+' must start at the top')}
}
Case 'Both login dialogs stay topmost and visible in the taskbar' {
 foreach($name in @('Show-LoginWindow','Show-PestoWindowsConnectionWindow')){
  $match=[regex]::Match($defs[$name],'(?s)<Window\s.*?</Window>');Assert $match.Success
  [xml]$dialog=$match.Value;Assert ($dialog.DocumentElement.GetAttribute('Topmost') -ceq 'True');Assert ($dialog.DocumentElement.GetAttribute('ShowInTaskbar') -ceq 'True')
  Assert ($defs[$name] -notmatch '(?i)\.Topmost\s*=\s*\$false')
 }
}
Case 'Login activation and focus occur once on opening without a focus timer' {
 $explicit=$defs['Show-LoginWindow'];$windows=$defs['Show-PestoWindowsConnectionWindow']
 Assert ($explicit.Contains('$ui.Window.Activate()') -and $explicit.Contains('$ui.Login.Focus()') -and $explicit.Contains('$ui.Password.Focus()') -and $explicit.Contains('-not $s.InitialFocusSet'))
 Assert ($windows.Contains('$s.Window.Activate()') -and $windows.Contains('$s.Cancel.Focus()') -and $windows.Contains('-not $s.Started'))
 foreach($source in @($explicit,$windows)){Assert ($source -notmatch '(?i)DispatcherTimer|Add_Deactivated|Add_Activated')}
}
Case 'Main window does not inherit always-on-top login behavior' {Assert ($shell.DocumentElement.GetAttribute('Topmost') -ne 'True')}
# Régression du nom grisé après jonction : vraies fonctions de présentation, contrôles mémoire et aucun WPF/AD.
foreach($name in @('Update-PestoJoinUI','Update-PestoJoinNames','Get-PestoJoinNameReadState')){. ([scriptblock]::Create($defs[$name]))}
function ConvertTo-PestoPolicy {param($Value);[pscustomobject]@{AllowPrecreatedJoin=$true}}
function New-PestoJoinPlanFromUI {[pscustomobject]@{NewName=[string]$script:JoinUI.Name.SelectedItem;TargetOU='OU=Lyon,DC=example,DC=local';Account='EXAMPLE\test'}}
function Get-PestoJoinPlanErrors {param($Plan);$script:NameSeenByPlan=$Plan.NewName}
function Test-PestoQueueWorkerStillActive {$false}
function Test-PestoAsyncOperationRunning {param($Name);$false}
function Format-OUPath {param($Path);$Path}
function Get-PestoUxNom {param($Name);$Name}
function Get-ComputersForNameGeneration {@()}
function Get-PestoJoinNameCandidates {param($Type,$Site,$Service,$Computers);$script:CandidateReads++;'P111301LY765358';'P111301LY765359'}
function Get-PestoInitialNameIndex {param($Count);$script:RandomReads++;0}
function Request-PestoJoinSiteLookup {param([switch]$Force);$script:JoinLookupRequests++}
function Get-SiteTag {param($SiteName);if($SiteName -eq 'Lyon'){'LY'}else{'PA'}}
function ConvertTo-PestoRdnValue {param($Value);$Value}
function Test-PestoOUPath {param($Value);[bool]$Value}
function Reset-JoinPresentation {
 $script:CFG=@{POLICY=@{}};$script:JoinBusy=$false;$script:JoinLocked=$false;$script:INDOMAIN=$false
 $script:DirectBusy=$false;$script:DirectLocked=$false;$script:Running=$false;$script:PreflightRunning=$false
 $script:MutationUncertain=$false;$script:CfgRestartRequired=$false;$script:PestoReadOnly=$false
 $script:GUI=$false;$script:SIM=$false;$script:PRD=$true;$script:DOMAINE='example.local';$script:JoinInputPending=$false
 $script:PREFIXE='111301';$script:DC='dc.example.local';$script:OUV=@{};$script:JoinLookupRequests=0
 $script:SiteLookupInfo=@{'EXAMPLE.LOCAL|DC.EXAMPLE.LOCAL|111301|LY|'=[pscustomobject]@{Complete=$true}}
 $script:SiteLookupState=@{'EXAMPLE.LOCAL|DC.EXAMPLE.LOCAL|111301|LY|'=[pscustomobject]@{State='Ready'}}
 $script:JoinSuspend=$false;$script:JoinLastCheck=$null;$script:JoinReceipt=$null
 $script:JoinLocal=[pscustomobject]@{PartOfDomain=$false;MachineId='machine';BootUtc='boot'}
 $script:CandidateReads=0;$script:RandomReads=0;$script:NameSeenByPlan='';$script:JoinUI=@{}
 foreach($key in @('Existing','Fields','Start','Check','CancelRead','Refresh','Restart','Review','Later','NamePreview','OUPreview','Domain','Current','Account','Policy','Hint','Export','Rename','Type','Site','Service','Org')){$script:JoinUI[$key]=@{IsChecked=$false;Visibility='Visible';IsEnabled=$true;Text='';ToolTip='';Content='';SelectedItem=$null}}
 $script:JoinUI.Type.SelectedItem='Portable';$script:JoinUI.Site.SelectedItem='Lyon';$script:JoinUI.Service.Text='765'
 $items=[Collections.Generic.List[object]]::new();$items.Add('P111301LY765128')
 $name=[pscustomobject]@{Items=$items;SelectedItem='P111301LY765128';Text='P111301LY765128';IsEditable=$false;IndexValue=0}
 $name|Add-Member -MemberType ScriptProperty -Name SelectedIndex -Value {$this.IndexValue} -SecondValue {param($value);$this.IndexValue=$value;$this.SelectedItem=if($value -ge 0 -and $value -lt $this.Items.Count){$this.Items[$value]}else{$null};$this.Text=[string]$this.SelectedItem}
 $script:JoinUI.Name=$name
}
function Set-JoinPresentationReceipt {param([string]$Phase);$script:JoinReceipt=[pscustomobject]@{Phase=$Phase;NewName='P111301LY765128';OU='OU=Lyon,DC=example,DC=local';OperationId='submitted-operation';MachineId='machine';BootUtc='boot'}}
foreach($phase in @('Running','PendingRestart','Uncertain')){
 Case ('Late inventory keeps submitted name for '+$phase) {
  Reset-JoinPresentation;Set-JoinPresentationReceipt $phase
  # Le nom soumis a déjà disparu des candidats libres ; un champ divergent doit être corrigé depuis le reçu.
  $script:JoinUI.Name.Items.Clear();$script:JoinUI.Name.Items.Add('P111301LY765358');$script:JoinUI.Name.SelectedItem='P111301LY765358';$script:JoinUI.Name.Text='P111301LY765358'
  1..3|ForEach-Object {Update-PestoJoinNames}
  Assert ($script:CandidateReads -eq 0 -and $script:RandomReads -eq 0) 'No new candidate after submission'
  Assert ($script:JoinUI.Name.SelectedItem -ceq 'P111301LY765128' -and $script:JoinUI.Name.Text -ceq 'P111301LY765128') 'Submitted name remains in the disabled field'
  Assert ($script:JoinUI.NamePreview.Text -ceq $script:JoinUI.Name.Text -and $script:NameSeenByPlan -ceq 'P111301LY765128') 'Field, plan and preview agree'
  Assert (-not $script:JoinUI.Fields.IsEnabled -and -not $script:JoinUI.Start.IsEnabled) 'Receipt keeps the form blocked'
  Assert ($script:JoinReceipt.OperationId -ceq 'submitted-operation' -and -not $script:JoinSuspend) 'No receipt mutation or leaked event suspension'
 }
}
Case 'Verified joined computer keeps its recorded name after inventory refresh' {
 Reset-JoinPresentation;Set-JoinPresentationReceipt 'Verified';$script:JoinLocal.PartOfDomain=$true
 $script:JoinUI.Name.SelectedItem='P111301LY765358';Update-PestoJoinNames
 Assert ($script:JoinUI.Name.SelectedItem -ceq 'P111301LY765128' -and $script:JoinUI.NamePreview.Text -ceq 'P111301LY765128')
 Assert ($script:CandidateReads -eq 0 -and $script:JoinUI.Fields.Visibility -ceq 'Collapsed')
}
Case 'Joined computer without receipt displays current name without proposing another' {
 Reset-JoinPresentation;$script:INDOMAIN=$true;$before=$env:COMPUTERNAME
 try{$env:COMPUTERNAME='P111301LY765128';Update-PestoJoinNames;Assert ($script:CandidateReads -eq 0 -and $script:JoinUI.Name.Text -ceq $env:COMPUTERNAME -and $script:JoinUI.NamePreview.Text -ceq $env:COMPUTERNAME)}finally{$env:COMPUTERNAME=$before}
}
foreach($phase in @('Verified','Failed')){
 Case ('Workgroup with resolved '+$phase+' receipt can prepare a fresh draft') {
  Reset-JoinPresentation;Set-JoinPresentationReceipt $phase;Update-PestoJoinNames
  Assert ($script:CandidateReads -eq 1 -and $script:RandomReads -eq 1)
  Assert ($script:JoinUI.Name.SelectedItem -ceq 'P111301LY765358' -and $script:JoinUI.NamePreview.Text -ceq 'P111301LY765358')
  Assert ($script:JoinUI.Fields.IsEnabled -and $script:JoinUI.Start.IsEnabled)
 }
}
Case 'Busy or locked operation without a receipt retains its submitted selection' {
 foreach($state in @('JoinBusy','JoinLocked')){
  Reset-JoinPresentation;Set-Variable -Scope Script -Name $state -Value $true;Update-PestoJoinNames
  Assert ($script:CandidateReads -eq 0 -and $script:JoinUI.Name.SelectedItem -ceq 'P111301LY765128' -and -not $script:JoinUI.Fields.IsEnabled)
 }
}
Case 'Recorded editable name is restored while preserving event suspension' {
 Reset-JoinPresentation;Set-JoinPresentationReceipt 'PendingRestart';$script:JoinSuspend=$true;$script:JoinUI.Existing.IsChecked=$true;$script:JoinUI.Name.Text='P111301LY765358'
 Update-PestoJoinUI
 Assert ($script:JoinUI.Name.Text -ceq 'P111301LY765128' -and $script:JoinSuspend -and $script:CandidateReads -eq 0)
}

Case 'Join preview waits for AD before generating or enabling Add' {
 Reset-JoinPresentation;$script:SiteLookupInfo=@{};$script:SiteLookupState=@{}
 Update-PestoJoinNames
 Assert ($script:JoinLookupRequests -eq 1 -and $script:CandidateReads -eq 0 -and $script:JoinUI.Name.Items.Count -eq 0)
 Assert (-not $script:JoinUI.Start.IsEnabled -and $script:JoinUI.NamePreview.Text -like 'Calcul du nom*')
}
Case 'Complete AD result computes the preview without pressing Add and keeps it stable' {
 Reset-JoinPresentation;$key='EXAMPLE.LOCAL|DC.EXAMPLE.LOCAL|111301|LY|';$script:SiteLookupState[$key].State='Loading'
 Update-PestoJoinNames;$script:SiteLookupState[$key].State='Ready';Update-PestoJoinNames -NoLookup
 Assert ($script:JoinUI.NamePreview.Text -ceq 'P111301LY765358' -and $script:JoinUI.Start.IsEnabled)
 $draws=$script:RandomReads;Update-PestoJoinNames -NoLookup
 Assert ($script:JoinUI.NamePreview.Text -ceq 'P111301LY765358' -and $script:RandomReads -eq $draws)
}
Case 'Partial failed and other-site inventories never expose a provisional name' {
 foreach($state in @('Partial','Failed','OtherSite')){
  Reset-JoinPresentation;$key='EXAMPLE.LOCAL|DC.EXAMPLE.LOCAL|111301|LY|'
  if($state -eq 'Partial'){$script:SiteLookupInfo[$key].Complete=$false}
  if($state -eq 'Failed'){$script:SiteLookupState[$key].State='Failed'}
  if($state -eq 'OtherSite'){$script:JoinUI.Site.SelectedItem='Paris'}
  Update-PestoJoinNames -NoLookup
  Assert (-not $script:JoinUI.Start.IsEnabled -and $script:CandidateReads -eq 0 -and $script:JoinUI.Name.Items.Count -eq 0) $state
 }
}
Case 'Explicit precreated name stays editable without generated inventory' {
 Reset-JoinPresentation;$script:SiteLookupInfo=@{};$script:JoinUI.Existing.IsChecked=$true
 Update-PestoJoinNames
 Assert ($script:CandidateReads -eq 0 -and $script:JoinLookupRequests -eq 0 -and $script:JoinUI.Name.SelectedItem -ceq 'P111301LY765128')
}
Case 'Changed fields hide the previous name during debounce' {
 Reset-JoinPresentation;$script:JoinInputPending=$true;Update-PestoJoinUI
 Assert (-not $script:JoinUI.Start.IsEnabled -and $script:JoinUI.NamePreview.Text -like 'Calcul du nom*')
}

Case 'AD names received during a local read appear when it fails or is cancelled' {
 function Set-PestoJoinBusy {param($Busy);$script:JoinBusy=$Busy}
 function Set-PestoJoinMessage {param($Title,$Message,$Kind)}
 function Get-PestoJoinGuidance {param($Message);''}
 function Write-Log {param($Message,$Level,$ErrorRecord,$Category)}
 foreach($callback in @('Complete-PestoJoinReadError','Invoke-PestoJoinCancelReadClick')){
  . ([scriptblock]::Create($defs[$callback]))
  Reset-JoinPresentation;$script:JoinBusy=$true;$script:JoinUI.Name.SelectedIndex=-1
  Update-PestoJoinNames -NoLookup
  Assert ($script:CandidateReads -eq 0)
  & $callback
  Assert ($script:JoinUI.NamePreview.Text -ceq 'P111301LY765358' -and $script:JoinUI.Start.IsEnabled) $callback
 }
}

Case 'Collision rechecks the new preview without continuing the previous Add request' {
 . ([scriptblock]::Create($defs['Complete-PestoJoinCheck']))
 function Set-PestoJoinBusy {param($Busy);$script:JoinBusy=$Busy}
 function Get-PestoJoinPlanKey {param($Plan);[string]$Plan.NewName}
 function Test-PestoJoinNameTaken {param($Result);-not $Result.Valid}
 function Add-PestoTakenNames {param($Names)}
 function Set-PestoJoinMessage {param($Title,$Message,$Kind)}
 function Test-PestoNameReservedByOther {param($Name);$true}
 function Select-PestoJoinNextName {param($TakenName,$Reason,[switch]$RegistryHeld);$script:JoinUI.Name.SelectedItem='P111301LY765359';Update-PestoJoinUI;$true}
 function Request-PestoJoinAutoNextCheck {param([bool]$Execute);$script:Rechecks.Add($Execute)}
 function Start-PestoJoinADReservation {throw 'Must not reserve a different name automatically'}
 function Confirm-YesNo {throw 'Must return to preview before another confirmation'}
 foreach($scenario in @('TakenInAD','ReservedByOther','ChangedDuringRead')){
  Reset-JoinPresentation;$script:JoinGeneration=1;$script:JoinAutoRecheck=0;$script:JoinUI.Checks=@{ItemsSource=$null}
  $script:Rechecks=[Collections.Generic.List[bool]]::new()
  $plan=New-PestoJoinPlanFromUI
  $result=[pscustomobject]@{Valid=($scenario -ne 'TakenInAD');Key=$plan.NewName;Local=$script:JoinLocal;Receipt=$null;Decision=$null;Checks=@();SeriesTaken=@()}
  if($scenario -eq 'ChangedDuringRead'){$script:JoinUI.Name.SelectedItem='P111301LY765359'}
  Complete-PestoJoinCheck $result ([pscustomobject]@{Generation=1;Plan=$plan;Execute=$true})
  Assert ($script:Rechecks.Count -eq 1 -and -not $script:Rechecks[0]) $scenario
  Assert ($script:JoinUI.Name.SelectedItem -ceq 'P111301LY765359') $scenario
 }
}

Case 'Primary action matrix covers all boolean combinations and blocked routes' {
 $count=0
 foreach($computer in @('PC-123','')){foreach($route in @('None','ReviewJoin','ReviewDirect','Interventions')){for($bits=0;$bits -lt 128;$bits++){
  $a=@{Computer=$computer;Busy=[bool]($bits-band 1);Blocked=[bool]($bits-band 2);Loaded=[bool]($bits-band 4);FormReady=[bool]($bits-band 8);ResumeMove=[bool]($bits-band 16);ReadOnly=[bool]($bits-band 32);Rename=[bool]($bits-band 64);BlockedAction=$route;Missing='Champ à compléter.';BlockedHint='Cause explicite.'}
  $r=Get-PestoPrimaryStep @a;$expected='None'
  if(-not $a.Busy){
   if($a.Blocked){if(-not $a.ReadOnly -and $route -ne 'None'){$expected=$route}}
   elseif($computer){
    if(-not $a.Loaded -and -not $a.ResumeMove){$expected='Read'}
    elseif(-not $a.ReadOnly){if($a.FormReady -or $a.ResumeMove){$expected='Execute'}else{$expected='Prepare'}}
   }
  }
  Assert ($r.Action -eq $expected -and $r.Enabled -eq ($expected -ne 'None')) ("Matrix $computer $route $bits : $($r.Action) != $expected")
  if($r.Action -eq 'Execute'){Assert ($r.Label -match 'Vérifier' -and $r.Hint -match 'confirmation')}
  if($a.Blocked -and -not $a.Busy){Assert ($r.Hint -eq 'Cause explicite.')}
  $count++
 }}}
 Assert ($count -eq 1024)
}
Case 'Mode labels distinguish real readonly simulation and demonstration' {
 Assert ((Get-PestoModeChip $false $false $false) -ceq 'RÉEL')
 Assert ((Get-PestoModeChip $false $false $true) -ceq 'CONSULTATION')
 Assert ((Get-PestoModeChip $false $true $true) -ceq 'SIMULATION')
 Assert ((Get-PestoModeChip $true $true $true) -ceq 'DÉMONSTRATION')
}
Case 'Common block banner explains existing blockers without inventing one' {
 Assert (-not (Get-PestoBlockState).Visible)
 foreach($key in @('RestartRequired','GlobalBarrier','JoinLocked','Incident')){$a=@{};$a[$key]=$true;$r=Get-PestoBlockState @a;Assert ($r.Visible -and $r.Text)}
 Assert ((Get-PestoBlockState -RestartRequired $true -JoinLocked $true).Text -match 'Configuration')
}
Case 'Site status never labels failed or partial results complete' {
 $info=[pscustomobject]@{CollectedUtc=[DateTimeOffset]::UtcNow.ToString('o');Complete=$false}
 Assert ((Get-PestoSiteReadLabel $info Ready) -match 'liste partielle')
 Assert ((Get-PestoSiteReadLabel $info Loading) -match 'en cours')
 Assert ((Get-PestoSiteReadLabel $info Failed) -match 'indisponible.*précédentes')
 Assert ((Get-PestoSiteReadLabel $null Failed) -match 'Saisie libre')
 $info.Complete=$true;Assert ((Get-PestoSiteReadLabel $info Ready) -match '^Services lus')
}
Case 'Worker stage history retains actual transitions and no progress percentage' {
 $script:PestoQueueMonitor=New-PestoQueueMonitor -Computer PC01
 Set-PestoWorkerStage 'Lecture AD';Set-PestoWorkerStage 'Renommage Windows'
 $r=@(Get-PestoOperationStages $script:PestoQueueMonitor $true)
 Assert ($r.Count -eq 3 -and $r[1].Label -match '^Lecture AD' -and $r[2].State -eq 'En cours')
 $script:PestoQueueMonitor.TimedOut=$true
 Assert ((@(Get-PestoOperationStages $script:PestoQueueMonitor $false)[-1]).State -match 'résultat à vérifier')
 for($i=0;$i -lt 120;$i++){Set-PestoWorkerStage ('Étape '+$i)}
 Assert ($script:PestoQueueMonitor.StageHistory.Count -eq 100)
 Assert (@(Get-PestoOperationStages $script:PestoQueueMonitor $false).Count -le 6)
 $script:PestoQueueMonitor=$null
}
Case 'Log level combines with literal query and keeps original event references' {
 $entries=@([pscustomobject]@{Text='Message [x]';Kind='info'},[pscustomobject]@{Text='Alerte [x]';Kind='warn'},[pscustomobject]@{Text='Erreur [x]';Kind='err'})
 $r=@(Get-PestoFilteredLogEntries $entries '[x]' Error);Assert ($r.Count -eq 1 -and [object]::ReferenceEquals($r[0],$entries[2]))
 Assert (@(Get-PestoFilteredLogEntries $entries '' Info).Count -eq 1)
 Assert (@(Get-PestoFilteredLogEntries $entries '' Warn).Count -eq 1)
 Assert (@(Get-PestoFilteredLogEntries $entries '' All).Count -eq 3)
 Assert (@(Get-PestoFilteredLogEntries $entries 'absent' All).Count -eq 0)
}
Case 'Log dates and controls expose full timestamps and error copying' {
 Assert ($defs['Add-LogLine'].Contains("yyyy-MM-dd HH:mm:ss"))
 foreach($name in @('PestoBlockBanner','PestoModeChip','PestoDcChip','PestoServiceState','PestoStageDetails','PestoOperationStages','SuiteLogLevel','SuiteLogErrors')){Assert ($null -ne (Named $shell $name)) $name}
 Assert (-not (HasAncestor (Named $shell 'PestoBlockBanner') 'TabItem'))
 Assert ($defs['Copy-PestoLogErrors'].Contains('Protect-PestoLogText'))
}
Case 'Local hardware reuses ComputerSystem query and is explicitly unavailable without result' {
 Assert ($defs['Get-PestoJoinLocalStatus'].Contains('Manufacturer=[string]$cs.Manufacturer'))
 Assert ($defs['Get-PestoJoinLocalStatus'].Contains('Model=[string]$cs.Model'))
 Assert ($null -ne (Named $join 'JnHardware'))
 Assert ([int](Named $join 'JnNamePreview').FontSize -ge 24)
 Assert ($defs['Update-PestoJoinUI'].Contains('Identité matérielle non lue'))
}
Case 'Unit form tab order follows source naming and confirmation' {
 $prev=-1;foreach($name in @('TxtPCName','BtnReadComputer','CbType','CbOrg','CbSite','CbService','CbName','BtnOtherName','SuiteDirectCheck','SuiteDirectRun')){
  $index=[int](Named $shell $name).GetAttribute('KeyboardNavigation.TabIndex');Assert ($index -gt $prev) $name;$prev=$index
 }
}

$failed=@($results|Where-Object{-not $_.Passed}).Count
$report=[pscustomobject]@{PowerShell=[string]$PSVersionTable.PSVersion;NoWindows=$true;NoWpf=$true;NoAD=$true;Failed=$failed;Checks=$results.ToArray()}
if($ReportPath){$report|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $ReportPath -Encoding UTF8};$report|ConvertTo-Json -Depth 6;if($failed){exit 1}
