#requires -Version 5.1
[CmdletBinding()]
param([switch]$Wpf,[string]$ReportPath='')
# Fonctions réelles et reçus temporaires. Aucune exécution Windows/AD, préférence ou console modifiée.
$ErrorActionPreference='Stop';Set-StrictMode -Off
$root=Split-Path $PSScriptRoot -Parent;$defs=@{};$results=[Collections.Generic.List[object]]::new()
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'wad/Pesto-Contracts.ps1')
foreach($file in Get-ChildItem (Join-Path $root 'wad') -Filter 'Pesto-*.ps1' -File){
 $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
 if($errors.Count){throw ($file.Name+': '+($errors.Message -join '; '))}
 foreach($node in $ast.EndBlock.Statements){if($node -is [Management.Automation.Language.FunctionDefinitionAst]){$defs[$node.Name]=$node.Extent.Text}}
}
$load=@('Test-PestoOptionalPostCheckReceipt','Test-PestoAcknowledgedReceipt','Assert-PestoClosedObject','Assert-PestoPlainPath','Test-PestoComputerName','Test-PestoDnsName','Test-PestoGeneratedComputerName','Test-PestoOUPath','Split-PestoDistinguishedName','Get-PestoDomainFromDN','ConvertTo-PestoNameParts','Assert-PestoJoinReceiptData','Read-PestoDirectReceipt','Read-PestoIntervention','Get-PestoStatePresentation','Initialize-PestoDirectState','Test-PestoDirectTargetBarrier','Test-PestoGlobalSafetyBarrier','Get-PestoLocalPendingRename','Get-PestoPrimaryStep','Get-PestoPrimaryContext','Invoke-PestoPrimaryAction','Get-PestoJoinReceiptDecision')
foreach($name in $load){if(-not $defs.ContainsKey($name)){throw ('Fonction absente : '+$name)};. ([scriptblock]::Create($defs[$name]))}
function Assert-Follow {param($Value,[string]$Message='Assertion non satisfaite');if(-not $Value){throw $Message}}
function Equal-Follow {param($Actual,$Expected);if($Actual -cne $Expected){throw ('Attendu '+$Expected+', obtenu '+$Actual)}}
function Case-Follow {param([string]$Name,[scriptblock]$Body);try{& $Body;$results.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''})}catch{$results.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message})}}
$script:FollowRoot=Join-Path $PSScriptRoot ('.pesto-optional-followup-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($FollowRoot);[void][IO.Directory]::CreateDirectory((Join-Path $FollowRoot 'interventions'))
function Get-PestoDirectStatePath {Join-Path $script:FollowRoot 'direct.json'}
function Get-PestoInterventionRoot {Join-Path $script:FollowRoot 'interventions'}
function Update-QueueButtons {}
function Update-AddButton {}
function Update-PestoSuiteUI {}
function Get-PestoUxNom {param($Name);$Name}
function Protect-PestoLogText {param($Text);$Text}
function Write-Log {param($Message,$Level,$Exception,$Source)}
function Test-PestoAsyncOperationRunning {param($Name);$script:FollowWorkerBusy}
function Test-PestoQueueWorkerStillActive {$script:FollowWorkerBusy}
function Invoke-PestoUxReadComputer {param($Sender,$EventArgs);$script:FollowReadCalls++}
function Start-PestoDirectPreflight {param([switch]$Execute);Assert-Follow $Execute;$script:FollowPreflightCalls++}
function Show-PestoPostState {param($Mode);$script:FollowReviewCalls++}
function Invoke-PestoJoinReviewClick {param($Sender,$EventArgs);$script:FollowReviewCalls++}
function Show-PestoInterventions {$script:FollowReviewCalls++}
function Show-PestoUsefulError {param($Title,$Message,$Stage,$MutationPossible);throw $Message}
function Show-MsgWarning {throw 'Aucun dialogue automatique autorisé par ce banc'}
function Show-MsgInfo {throw 'Aucun dialogue automatique autorisé par ce banc'}
function Get-CimInstance {throw 'CIM réel interdit'}
function Get-ItemProperty {throw 'Registre réel interdit'}
function Get-ADComputer {throw 'AD réel interdit'}
function Test-ComputerSecureChannel {throw 'Canal réel interdit'}
function Rename-Computer {throw 'Renommage réel interdit'}
function Add-Computer {throw 'Jonction réelle interdite'}
function Restart-Computer {throw 'Redémarrage réel interdit'}
function Reset-Follow {
 $script:GUI=$false;$script:SIM=$false;$script:Running=$false;$script:PreflightRunning=$false;$script:DirectBusy=$false;$script:DirectLocked=$false;$script:JoinBusy=$false;$script:JoinLocked=$false
 $script:MutationUncertain=$false;$script:QueueOperationIds=@();$script:CfgRestartRequired=$false;$script:EDIT_ROW_INDEX=-1;$script:PestoReadOnly=$false;$script:DirectResumePlan=$null
 $script:HostMachineId='fixture-operator';$script:FollowWorkerBusy=$false;$script:FollowReadCalls=0;$script:FollowPreflightCalls=0;$script:FollowReviewCalls=0
 $script:NewNameExists=$false;$script:AutoMoveError='';$script:OU_ACTUELLE='';$script:DOMAINE='example.invalid';$script:HomeLocalSnapshot=$null;$script:JoinReceipt=$null
 foreach($name in @('TxtPCName','CbOrg','CbType','CbSite','CbService','CbName','ChkRename','ChkMove','BtnAdd')){
  if($Wpf){$control=$script:FollowWindow.FindName($name);Assert-Follow $control ('Contrôle absent : '+$name)}
  else{$control=[pscustomobject]@{Text='';IsEnabled=$true;SelectedItem=$null;IsChecked=$false}}
  Set-Variable -Name $name -Scope Script -Value $control
 }
 $TxtPCName.Text='P111301AAINF002';$CbOrg.IsEnabled=$true;$CbType.IsEnabled=$true;$BtnAdd.IsEnabled=$true;$ChkRename.IsChecked=$true;$ChkMove.IsChecked=$false
 foreach($pair in @(@($CbOrg,'ORG'),@($CbType,'Portable'),@($CbSite,'AA'),@($CbName,'P111301AAINF003'))){if($Wpf){$pair[0].Items.Clear();[void]$pair[0].Items.Add($pair[1])};$pair[0].SelectedItem=$pair[1]}
 $CbService.Text='INF'
}
function Write-FollowReceipt {
 param([string]$Phase='PendingRestart',[int]$Code=20)
 $id='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';$plan=[pscustomobject]@{Nom_du_PC='P111301AAINF001';Nouveau_Nom='P111301AAINF002';Domain='example.invalid';Objet_GUID='11111111-1111-1111-1111-111111111111';Renommer=$true;Deplacer=$false;Reboot=$false;OU_Actuelle='OU=AA,DC=example,DC=invalid';OU_Destination='OU=AA,DC=example,DC=invalid'}
 $direct=[pscustomobject]@{Schema=1;Version='1.0';OperationId=$id;OperatorMachineId='fixture-operator';LocalSource=$true;TargetMachineId='fixture-target';Phase=$Phase;StartedUtc='2026-10-12T12:00:00Z';FinishedUtc='2026-10-12T12:00:05Z';ObservedUtc='';Plan=$plan;ResultCode=$Code;ResultMessage='Reçu synthétique';ResumeFrom=''}
 $central=[pscustomobject]@{Schema=1;OperationId=$id;Plan=$plan;Phase=$Phase;StartedUtc=$direct.StartedUtc;UpdatedUtc=$direct.FinishedUtc;Entra='NotRequested';Protection='NotChanged';Rename='Confirmed';Move='NotRequested';ResultCode=$Code;ResultMessage='Reçu synthétique';Tasks=@()}
 if($Phase -eq 'Protection'){$central.Phase='Uncertain';$central.Protection='Lowered'}
 if($Phase -eq 'Running'){$central.Rename='Requested'}
 if($Phase -eq 'Partial'){$central.Plan.Deplacer=$true;$central.Move='Refused'}
 $script:FollowCentralPath=Join-Path (Get-PestoInterventionRoot) ($id+'.json')
 [IO.File]::WriteAllText((Get-PestoDirectStatePath),($direct|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
 [IO.File]::WriteAllText($FollowCentralPath,($central|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
 $script:FollowDirectBefore=[IO.File]::ReadAllText((Get-PestoDirectStatePath));$script:FollowCentralBefore=[IO.File]::ReadAllText($FollowCentralPath)
}
function Assert-FollowUnchanged {
 Equal-Follow ([IO.File]::ReadAllText((Get-PestoDirectStatePath))) $script:FollowDirectBefore
 Equal-Follow ([IO.File]::ReadAllText($script:FollowCentralPath)) $script:FollowCentralBefore
}
function New-FollowJoinReceipt {
 param([string]$Phase='PendingRestart')
 [pscustomobject]@{Schema=1;Version='1.0';OperationId='bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';Phase=$Phase;Utc='2026-10-12T12:00:05Z';MachineId='fixture-target';BootUtc='2026-10-12T11:00:00Z';Computer='PC-BEFORE';NewName='P111301AAINF002';Domain='example.invalid';OU='OU=AA,DC=example,DC=invalid';DC='dc.example.invalid'}
}
function New-FollowJoinLocal {
 [pscustomobject]@{MachineId='fixture-target';Computer='P111301AAINF002';ActiveName='P111301AAINF002';ConfiguredName='P111301AAINF002';Domain='example.invalid';PartOfDomain=$true;DomainRole=1;PendingRename=$false;BootUtc='2026-10-12T12:10:00Z';SecureChannel=$true}
}
if($Wpf){
 if($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){throw '-Wpf exige Windows PowerShell5.1'}
 if([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA'){throw '-Wpf exige -STA'}
 Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
 $script:FollowWindow=[Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText((Join-Path $root 'wad/Pesto-Shell.xaml')))
}
try{
 Case-Follow 'Saved accepted rename loads without locking a new operation or changing its receipt' {Reset-Follow;Write-FollowReceipt;Initialize-PestoDirectState;Assert-Follow (-not $script:DirectLocked) $script:DirectAdvice;Equal-Follow $script:DirectReceipt.Phase 'PendingRestart';Assert-FollowUnchanged}
 Case-Follow 'Same target after accepted result offers ordinary read instead of forced review' {Reset-Follow;Write-FollowReceipt;Initialize-PestoDirectState;$step=Get-PestoPrimaryContext;Equal-Follow $step.Action 'Read';Assert-Follow $step.Enabled;Invoke-PestoPrimaryAction;Equal-Follow $FollowReadCalls 1;Equal-Follow $FollowReviewCalls 0;Assert-FollowUnchanged}
 Case-Follow 'New preparation after accepted result reaches preflight, never replays the previous command' {Reset-Follow;Write-FollowReceipt;Initialize-PestoDirectState;$script:OU_ACTUELLE='OU=AA,DC=example,DC=invalid';$step=Get-PestoPrimaryContext;Equal-Follow $step.Action 'Execute';Assert-Follow $step.Enabled;Invoke-PestoPrimaryAction;Equal-Follow $FollowPreflightCalls 1;Equal-Follow $FollowReviewCalls 0;Assert-FollowUnchanged}
 Case-Follow 'Another target remains available after an accepted result' {Reset-Follow;Write-FollowReceipt;Initialize-PestoDirectState;$TxtPCName.Text='PC-OTHER';Equal-Follow (Get-PestoPrimaryContext).Action 'Read';Assert-FollowUnchanged}
 foreach($item in @(@('Running',0),@('Uncertain',97),@('Partial',89),@('Protection',32))){
  Case-Follow ('Unresolved '+$item[0]+' still routes the same target to review') {Reset-Follow;Write-FollowReceipt $item[0] $item[1];Initialize-PestoDirectState;Assert-Follow $script:DirectLocked;$step=Get-PestoPrimaryContext;Equal-Follow $step.Action 'ReviewDirect';Invoke-PestoPrimaryAction;Equal-Follow $FollowReviewCalls 1;Equal-Follow $FollowPreflightCalls 0;Assert-FollowUnchanged}
 }
 function New-FollowLocal {param($Pending=$true,[string]$Active='P111301AAINF001',[string]$Configured='P111301AAINF002');[pscustomobject]@{Computer=$Active;Domain='example.invalid';PartOfDomain=$true;ConfiguredName=$Configured;PendingRename=$Pending;CollectedUtc='2026-10-12T12:01:00Z'}}
 foreach($typed in @('P111301AAINF001','p111301aainf002')){
  Case-Follow ('Pending local rename blocks a new change typed as '+$typed) {Reset-Follow;$script:DirectReceipt=$null;$script:HomeLocalSnapshot=New-FollowLocal;$TxtPCName.Text=$typed;$script:OU_ACTUELLE='OU=AA,DC=example,DC=invalid';$step=Get-PestoPrimaryContext;Equal-Follow $step.Label 'Redémarrage requis';Assert-Follow (-not $step.Enabled);Equal-Follow $step.Action 'None';Assert-Follow ($step.Hint -match 'P111301AAINF002' -and $step.Hint -match 'facultative');Invoke-PestoPrimaryAction;Equal-Follow $FollowPreflightCalls 0;Equal-Follow $FollowReadCalls 0}
 }
 foreach($local in @($null,(New-FollowLocal -Pending $null),(New-FollowLocal -Pending $false),(New-FollowLocal -Configured ''),(New-FollowLocal -Configured 'P111301AAINF001'))){
  Case-Follow ('Unknown or absent pending rename never blocks ('+$(if($local){[string]$local.PendingRename+'/'+$local.ConfiguredName}else{'aucune observation'})+')') {Reset-Follow;$script:DirectReceipt=$null;$script:HomeLocalSnapshot=$local;$TxtPCName.Text='P111301AAINF001';$script:OU_ACTUELLE='OU=AA,DC=example,DC=invalid';Equal-Follow (Get-PestoPrimaryContext).Action 'Execute'}
 }
 Case-Follow 'Pending local rename does not block another target nor the move resume' {Reset-Follow;$script:DirectReceipt=$null;$script:HomeLocalSnapshot=New-FollowLocal;$TxtPCName.Text='PC-OTHER';Equal-Follow (Get-PestoPrimaryContext).Action 'Read';$TxtPCName.Text='P111301AAINF001';$script:DirectResumePlan=[pscustomobject]@{Nom_du_PC='P111301AAINF001'};Equal-Follow (Get-PestoPrimaryContext).Action 'Execute'}
 Case-Follow 'Unresolved operation keeps its review action even while a rename is pending' {Reset-Follow;Write-FollowReceipt 'Uncertain' 97;Initialize-PestoDirectState;$script:HomeLocalSnapshot=New-FollowLocal;$TxtPCName.Text='P111301AAINF001';Equal-Follow (Get-PestoPrimaryContext).Action 'ReviewDirect';Assert-FollowUnchanged}
 Case-Follow 'Live worker remains prioritary even when the previous receipt is accepted' {Reset-Follow;Write-FollowReceipt;Initialize-PestoDirectState;$script:FollowWorkerBusy=$true;$step=Get-PestoPrimaryContext;Assert-Follow (-not $step.Enabled);Equal-Follow $step.Action 'None';Assert-FollowUnchanged}
 Case-Follow 'Read-only context cannot execute a new mutation' {Reset-Follow;Write-FollowReceipt;Initialize-PestoDirectState;$script:OU_ACTUELLE='OU=AA,DC=example,DC=invalid';$script:PestoReadOnly=$true;$step=Get-PestoPrimaryContext;Assert-Follow (-not $step.Enabled);Equal-Follow $step.Action 'None';Assert-FollowUnchanged}
 Case-Follow 'Successful join after a proven boot and matching secure channel permits a new preparation' {
  Reset-Follow;Write-FollowReceipt;Initialize-PestoDirectState;$script:JoinReceipt=New-FollowJoinReceipt;$before=$JoinReceipt|ConvertTo-Json -Depth 8
  $decision=Get-PestoJoinReceiptDecision $JoinReceipt (New-FollowJoinLocal) 'example.invalid';Equal-Follow $decision.Phase 'ReadyToObserve';Assert-Follow (-not $decision.Blocked)
  $script:JoinLocked=$decision.Blocked;$script:OU_ACTUELLE='OU=AA,DC=example,DC=invalid';Equal-Follow (Get-PestoPrimaryContext).Action 'Execute';Invoke-PestoPrimaryAction
  Equal-Follow $FollowPreflightCalls 1;Equal-Follow $FollowReviewCalls 0;Equal-Follow ($JoinReceipt|ConvertTo-Json -Depth 8) $before;Assert-FollowUnchanged
 }
 Case-Follow 'Join before the required restart keeps its specific review action and clear explanation' {
  Reset-Follow;Write-FollowReceipt;Initialize-PestoDirectState;$script:JoinReceipt=New-FollowJoinReceipt;$local=New-FollowJoinLocal;$local.BootUtc=$JoinReceipt.BootUtc
  $decision=Get-PestoJoinReceiptDecision $JoinReceipt $local 'example.invalid';Assert-Follow $decision.Blocked;$script:JoinLocked=$decision.Blocked
  $context=Get-PestoPrimaryContext;Equal-Follow $context.Action 'ReviewJoin';Assert-Follow ($context.Hint -match 'redémarrage|indéterminé');Assert-Follow ($context.Hint -notmatch 'puis vous consignez')
  Invoke-PestoPrimaryAction;Equal-Follow $FollowReviewCalls 1;Equal-Follow $FollowPreflightCalls 0;Assert-FollowUnchanged
 }
 foreach($phase in @('Running','Uncertain')){
  Case-Follow ('Join '+$phase+' stays protected even with matching names after a boot') {
   Reset-Follow;Write-FollowReceipt;Initialize-PestoDirectState;$script:JoinReceipt=New-FollowJoinReceipt $phase;$before=$JoinReceipt|ConvertTo-Json -Depth 8
   $decision=Get-PestoJoinReceiptDecision $JoinReceipt (New-FollowJoinLocal) 'example.invalid';Assert-Follow $decision.Blocked;$script:JoinLocked=$decision.Blocked
   Equal-Follow (Get-PestoPrimaryContext).Action 'ReviewJoin';Equal-Follow ($JoinReceipt|ConvertTo-Json -Depth 8) $before;Assert-FollowUnchanged
  }
 }
 foreach($channel in @($null,$false)){
  Case-Follow ('Join secure channel '+$(if($null -eq $channel){'unknown'}else{'failed'})+' keeps review required') {
   Reset-Follow;Write-FollowReceipt;Initialize-PestoDirectState;$script:JoinReceipt=New-FollowJoinReceipt;$local=New-FollowJoinLocal;$local.SecureChannel=$channel
   $decision=Get-PestoJoinReceiptDecision $JoinReceipt $local 'example.invalid';Assert-Follow $decision.Blocked;$script:JoinLocked=$decision.Blocked;Equal-Follow (Get-PestoPrimaryContext).Action 'ReviewJoin';Assert-FollowUnchanged
  }
 }
 if($Wpf){
  Case-Follow 'WPF: actual primary button routes a new preparation to preflight without consigning' {
   Reset-Follow;Write-FollowReceipt;Initialize-PestoDirectState;$script:OU_ACTUELLE='OU=AA,DC=example,DC=invalid'
   $button=$FollowWindow.FindName('SuiteDirectRun');$step=Get-PestoPrimaryContext;$button.Content=$step.Label;$button.IsEnabled=$step.Enabled
   Assert-Follow $button.IsEnabled;Assert-Follow ($button.Content -match 'renommer')
   $handler=[Windows.RoutedEventHandler]${function:Invoke-PestoPrimaryAction};$button.Add_Click($handler)
   try{$button.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))}finally{$button.Remove_Click($handler)}
   Equal-Follow $FollowPreflightCalls 1;Equal-Follow $FollowReviewCalls 0;Equal-Follow $script:DirectReceipt.Phase 'PendingRestart';Assert-FollowUnchanged
  }
  Case-Follow 'WPF: join accepted after reboot uses the same real primary button without mandatory verification' {
   Reset-Follow;Write-FollowReceipt;Initialize-PestoDirectState;$script:JoinReceipt=New-FollowJoinReceipt;$before=$JoinReceipt|ConvertTo-Json -Depth 8
   $script:JoinLocked=(Get-PestoJoinReceiptDecision $JoinReceipt (New-FollowJoinLocal) 'example.invalid').Blocked;$script:OU_ACTUELLE='OU=AA,DC=example,DC=invalid'
   $button=$FollowWindow.FindName('SuiteDirectRun');$context=Get-PestoPrimaryContext;$button.Content=$context.Label;$button.IsEnabled=$context.Enabled;Assert-Follow $button.IsEnabled
   $handler=[Windows.RoutedEventHandler]${function:Invoke-PestoPrimaryAction};$button.Add_Click($handler)
   try{$button.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))}finally{$button.Remove_Click($handler)}
   Equal-Follow $FollowPreflightCalls 1;Equal-Follow $FollowReviewCalls 0;Equal-Follow ($JoinReceipt|ConvertTo-Json -Depth 8) $before;Assert-FollowUnchanged
  }
 }
}finally{if($script:FollowWindow){$script:FollowWindow.Close()};if(Test-Path -LiteralPath $FollowRoot){Remove-Item -LiteralPath $FollowRoot -Recurse -Force}}
$failed=@($results|Where-Object{-not $_.Passed}).Count
$sourceHashes=@(foreach($source in @('Pesto-Policy.ps1','Pesto-Direct.ps1','Pesto-Join.ps1','Pesto-JoinRecovery.ps1','Pesto-UXFlow.ps1','Pesto-SuiteUI.ps1','Pesto-Interventions.ps1','Pesto-Contracts.ps1','Pesto-Shell.xaml')){$path=Join-Path $root ('wad/'+$source);[pscustomobject]@{Path='DEV/wad/'+$source;Sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}})
$report=[pscustomobject]@{Suite='OptionalFollowupUi';SourceHashes=$sourceHashes;PowerShell=[string]$PSVersionTable.PSVersion;WpfRequested=[bool]$Wpf;WpfExecuted=[bool]$Wpf;ADExecuted=$false;ApplicationLaunched=$false;Passed=$results.Count-$failed;Failed=$failed;Checks=$results.ToArray()}
if($ReportPath){$report|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $ReportPath -Encoding UTF8};$report|ConvertTo-Json -Depth 6;if($failed){exit 1}
