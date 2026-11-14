#requires -Version 5.1
param([string]$ReportPath='', [switch]$Wpf)
$ErrorActionPreference='Stop';Set-StrictMode -Off
$root=Split-Path $PSScriptRoot -Parent;$defs=@{};$results=[Collections.Generic.List[object]]::new()
foreach($file in @('Pesto-Workbench.ps1','Pesto-ConfigEditor.ps1','Pesto-Workspace.ps1','Pesto-Contracts.ps1','Pesto-Appearance.ps1','Pesto-Core.ps1','Pesto-Directory.ps1','Pesto-Operations.ps1')){
 $t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root ('wad/'+$file)),[ref]$t,[ref]$e);if($e.Count){throw ($file+': '+($e.Message -join '; '))}
 foreach($f in $ast.EndBlock.Statements){if($f -is [Management.Automation.Language.FunctionDefinitionAst]){$defs[$f.Name]=$f.Extent.Text}}
}
foreach($n in @('Get-PestoPageShortcut','Test-PestoStartupMaximized','New-PestoChoiceSearchIndex','Update-PestoChoiceSearch','Get-PestoNextFocusZoneTarget','Get-PestoChoiceSearchKeys','Get-PestoFilteredChoiceRows','Get-PestoPanelLayout','ConvertTo-PestoConfirmationRows','ConvertTo-PestoSearchText','Get-PestoCommandMatches','Get-PestoPaletteChoices','ConvertTo-PestoNameParts','Get-PestoNameSegments','Find-PestoExactCandidate','Test-PestoGeneratedComputerName','Assert-PestoClosedObject','ConvertTo-PestoDraft','ConvertTo-PestoDraftCollection','Read-PestoDraftCollection','Save-PestoNamedDraft','Test-PestoComputerName','Test-PestoDnsName','Test-PestoOUPath','Get-PestoZoomViewportLayout','ConvertTo-PestoUiZoomPercent','Get-PestoAppearanceValue','Set-PestoAppearanceValue','Test-PestoAppearanceSid')){if($defs[$n]){. ([scriptblock]::Create($defs[$n]))}}
. (Join-Path $root 'wad/Pesto-Contracts.ps1')
function Assert {param($Value,[string]$Message='Assertion failed');if(-not $Value){throw $Message}}
function Case {param($Name,[scriptblock]$Test);try{& $Test;$results.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''})}catch{$results.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message})}}
function Reject {param([scriptblock]$Test);$blocked=$false;try{& $Test|Out-Null}catch{$blocked=$true};Assert $blocked}
Case 'Short confirmation does not fill the whole desktop' {$r=Get-PestoPanelLayout 1920 1160 'Un changement';Assert ($r.Height -le 320 -and $r.Width -eq 1000)}
Case 'Long report fits finite viewport and scrolls internally' {$r=Get-PestoPanelLayout 760 560 ('ligne longue'*2000);Assert ($r.Height -le 528 -and $r.Width -eq 728)}
Case 'Invalid panel dimensions receive finite defaults' {$r=Get-PestoPanelLayout ([double]::NaN) ([double]::PositiveInfinity);Assert (-not[double]::IsNaN($r.Height) -and $r.Width -gt 0)}
Case 'Typed before and after retain exact values and mark only differences' {$r=@(ConvertTo-PestoConfirmationRows @(@{Field='Nom';Before='PC01';After='PC02'},@{Field='OU';Before='Paris';After='Paris'}));Assert ($r.Count -eq 2 -and $r[0].Changed -and -not $r[1].Changed -and $r[0].Before -ceq 'PC01')}
Case 'Oversized confirmation fields rejected' {Reject {ConvertTo-PestoConfirmationRows @(@{Field='Nom';Before=('X'*2049);After=''})}}
Case 'Palette synonyms find receipts with report vocabulary' {$c=@([pscustomobject]@{Id='interventions';Label='Interventions';Detail='Suivi'});Assert (@(Get-PestoCommandMatches $c 'rapport').Count -eq 1)}
Case 'Palette exact title comes first and retains original command reference' {$a=[pscustomobject]@{Id='a';Label='Noms libres du site';Detail=''};$b=[pscustomobject]@{Id='b';Label='Noms';Detail=''};$r=@(Get-PestoCommandMatches @($a,$b) 'noms');Assert ([object]::ReferenceEquals($r[0],$b))}
Case 'Palette combines accent insensitive words' {$c=@([pscustomobject]@{Id='capacity';Label='Capacité';Detail='site'});Assert (@(Get-PestoCommandMatches $c 'capacite libres').Count -eq 1)}
Case 'Palette typed query searches every category' {$c=@([pscustomobject]@{Id='settings';Label='Paramètres';Detail='';Category='Affichage'});Assert (@(Get-PestoPaletteChoices $c 'config' 'Postes').Count -eq 1)}
Case 'Exact candidate requires membership in current filter' {Assert ((Find-PestoExactCandidate ' p111301ly765128 ' @('P111301LY765128')) -ceq 'P111301LY765128');Reject {Find-PestoExactCandidate 'P111301LY765129' @('P111301LY765128')}}
Case 'Exact candidate rejects arbitrary Windows name' {Reject {Find-PestoExactCandidate 'OTHER' @('OTHER')}}
Case 'Name segments show all fields and retain leading zeros' {$r=@(Get-PestoNameSegments 'P111301LY765003' 'P111301LY765002');Assert ($r.Count -eq 5 -and $r[4].Value -ceq '003' -and $r[4].Changed -and -not $r[0].Changed)}
Case 'Unknown name produces no misleading segments' {Assert (@(Get-PestoNameSegments 'INVALID').Count -eq 0)}
Case 'Zoom logical width fits physical width at150percent' {$r=Get-PestoZoomViewportLayout 760 560 150;Assert ([Math]::Abs($r.Width*1.5-760) -lt 0.001 -and $r.Height -ge 520)}
[xml]$shell=Get-Content (Join-Path $root 'wad/Pesto-Shell.xaml') -Raw -Encoding UTF8
function Named {param($Name);$shell.SelectSingleNode('//*[@*[local-name()="Name"]="'+$Name+'"]')}
Case 'New actions are reachable as named controls' {foreach($n in @('PestoExactName','PestoNextOperation','PestoNotifyBatch','PestoNameSegments')){Assert ($null -ne (Named $n)) $n}}
Case 'Appearance notification keeps spacing before the density action' {$control=Named 'PestoNotifyBatch';Assert ($control.ParentNode.LocalName -eq 'WrapPanel');$m=@(([string]$control.Margin).Split(','));Assert ($m.Count -eq 4 -and [double]$m[2] -ge 12);Assert ([object]::ReferenceEquals($control.ParentNode,(Named 'SuiteAppearanceDensity').ParentNode))}
Case 'One global scrolling axis preserves the fixed zoom controls' {Assert ((Named 'PestoZoomViewport').HorizontalScrollBarVisibility -eq 'Disabled');Assert ((Named 'PestoZoomReset').ParentNode -ne (Named 'PestoZoomViewport'))}
Case 'Four home shortcuts remain exactly four' {Assert (@((Named 'HomeActions').ChildNodes|Where-Object{$_.LocalName -eq 'Button'}).Count -eq 4)}
Case 'Next-operation action never removes writes or verifies receipts' {$s=$defs['Initialize-PestoWorkbench'];Assert ($s -notmatch 'Remove-Item|Write-Pesto.*Receipt|\.Phase\s*=|Verified');Assert ($s.Contains("`$script:DirectCheckedKey=''"))}
Case 'Narrator deduplicates text and never creates peers' {$s=$defs['Set-PestoAccessibleStatus'];Assert ($s.Contains('PestoAnnouncedStatus -ceq $Text') -and $s.Contains('::FromElement(') -and -not $s.Contains('CreatePeerForElement'))}
Case 'F6 does not leave a modal panel' {Assert ($defs['Invoke-PestoFocusZone'].Contains('PestoPanelStack.Count'))}
Case 'Choice table remains read-only and selection cannot mutate' {$s=$defs['Show-PestoChoiceTable'];Assert ($s.Contains('IsReadOnly="True"') -and $s.Contains('SelectionMode="Single"') -and -not($s -match 'Add-Computer|Rename-Computer|Move-ADObject'))}

Case 'Real preference gateway supports new keys within explicit limits without touching registry' {
 $script:GUI=$true;$script:PestoAppearanceMemory=@{}
 foreach($pair in @(@('Drafts',262144),@('Views',65536),@('Collections',1048576),@('NotifyBatch',4))){$value=if($pair[0] -eq 'NotifyBatch'){'true'}else{'x'*[int]$pair[1]};Set-PestoAppearanceValue -Name $pair[0] -Value $value;Assert ((Get-PestoAppearanceValue -Name $pair[0]) -ceq $value)}
 Reject{Set-PestoAppearanceValue -Name 'Drafts' -Value ('x'*262145)};Reject{Set-PestoAppearanceValue -Name 'NotifyBatch' -Value 'maybe'}
}
$draft=[pscustomobject]@{Schema=1;Domain='lab.test';ConfigStamp=('a'*64);Nom_du_PC='PC1';Nouveau_Nom='P123456LYINF001';Renommer=$true;Deplacer=$false}
Case 'Named drafts survive JSON dates and remain distinct in storage' {$script:GUI=$true;$script:PestoDraftsMemory='';Save-PestoNamedDraft 'Premier' $draft;Save-PestoNamedDraft 'Second' $draft;$r=@(Read-PestoDraftCollection);Assert ($r.Count -eq 2 -and $r[0].Draft.Nom_du_PC -ceq 'PC1' -and $null -eq $r[0].Draft.PSObject.Properties['Reference'])}
Case 'Draft collection cannot restore reboot or execution agreement' {$bad=$draft.PSObject.Copy();$bad|Add-Member NoteProperty Reboot $true;Reject{ConvertTo-PestoDraftCollection ([pscustomobject]@{Schema=1;Drafts=@([pscustomobject]@{Name='bad';UpdatedUtc='2026-10-13T10:00:00Z';Draft=$bad})})}}
Case 'Choice tables wire close explicitly when hosted rather than relying on IsCancel' {Assert ($defs['Show-PestoChoiceTable'].Contains("`$w.FindName('Cancel').Add_Click"))}

function FocusTarget {param([string]$Name);[pscustomobject]@{Name=$Name;IsVisible=$true;IsEnabled=$true;Focusable=$true;IsKeyboardFocusWithin=$false}}
# Build sibling-focused roots while no anchor itself owns keyboard focus.
function MakeZones {param([int]$Focused);$out=@();$i=0;foreach($name in @('Navigation','Source','Nom','Action','Zoom')){$out+=[pscustomobject]@{Target=(FocusTarget $name);Root=[pscustomobject]@{IsKeyboardFocusWithin=($i -eq $Focused)}};$i++};return $out}
Case 'F6 from a sibling navigation button advances to the source zone' {$z=@(MakeZones 0);Assert ((Get-PestoNextFocusZoneTarget $z).Name -ceq 'Source')}
Case 'F6 and ShiftF6 from an organism field use its complete name zone' {$z=@(MakeZones 2);Assert ((Get-PestoNextFocusZoneTarget $z).Name -ceq 'Action');Assert ((Get-PestoNextFocusZoneTarget $z $true).Name -ceq 'Source')}
Case 'F6 cycles both ways at the first and last zones' {Assert ((Get-PestoNextFocusZoneTarget @(MakeZones 4)).Name -ceq 'Navigation');Assert ((Get-PestoNextFocusZoneTarget @(MakeZones 0) $true).Name -ceq 'Zoom')}
Case 'F6 skips disabled or invisible target zones' {$z=@(MakeZones 0);$z[1].Target.IsEnabled=$false;$z[2].Target.IsVisible=$false;Assert ((Get-PestoNextFocusZoneTarget $z).Name -ceq 'Action')}
Case 'Hidden JSON key participates in choice search without a visible column' {$columns=@(@{Key='Label';Label='Réglage'});$keys=@(Get-PestoChoiceSearchKeys $columns @('Path'));$row=[pscustomobject]@{Label='Suspendre les mutations';Path='POLICY.IncidentMode'};$found=@(Get-PestoFilteredChoiceRows @($row) $keys 'POLICY.IncidentMode');Assert ($found.Count -eq 1 -and [object]::ReferenceEquals($found[0],$row) -and $columns.Count -eq 1)}
Case 'Choice search still matches visible accent insensitive values' {$row=[pscustomobject]@{Label='Réglage';Path='POLICY.X'};Assert (@(Get-PestoFilteredChoiceRows @($row) @('Label','Path') 'reglage').Count -eq 1)}
Case 'Choice search accepts only explicit property names' {Reject {Get-PestoChoiceSearchKeys @(@{Key='Label'}) @('Path;Remove-Item')};Assert (@(Get-PestoChoiceSearchKeys @(@{Key='Label'}) @('Label','Path')).Count -eq 2)}
Case 'Settings search includes JSON path in the real table route' {Assert ($defs['Show-PestoSettingSearch'].Contains("-SearchProperties @('Path')"))}

Case 'Choice index preserves references and searches snapshot without re-reading rows' {
 $row=[pscustomobject]@{Label='Éléphant';Path='POLICY.X'};$idx=@(New-PestoChoiceSearchIndex @($row) @('Label','Path'))
 $row.Label='Changed after projection'
 $found=@(Get-PestoFilteredChoiceRows -SearchIndex $idx -Query 'elephant')
 Assert ($found.Count -eq 1 -and [object]::ReferenceEquals($found[0],$row))
 Assert (@(Get-PestoFilteredChoiceRows -SearchIndex $idx -Query 'changed').Count -eq 0)
}
Case 'Choice projected search handles literal punctuation empty and no matches' {
 $row=[pscustomobject]@{Label='a[*] b'};$idx=@(New-PestoChoiceSearchIndex @($row) @('Label'))
 Assert (@(Get-PestoFilteredChoiceRows -SearchIndex $idx -Query '[*]').Count -eq 1)
 Assert (@(Get-PestoFilteredChoiceRows -SearchIndex $idx -Query '').Count -eq 1)
 Assert (@(Get-PestoFilteredChoiceRows -SearchIndex $idx -Query 'none').Count -eq 0)
}
Case 'Closed choice dialog ignores a pending search callback' {Update-PestoChoiceSearch ([pscustomobject]@{Closed=$true})}
Case 'Choice timer is delayed and explicitly stopped and detached on close' {
 $code=$defs['Show-PestoChoiceTable'];Assert ($code.Contains('FromMilliseconds(220)'))
 Assert ($code.Contains('$state.Timer.Stop();$state.Timer.Remove_Tick($tick)'))
 Assert (-not $code.Contains('Get-PestoFilteredChoiceRows -Rows $u.Rows'))
}

Case 'Search shortcuts stay scoped to every active page' {
 $expected=@('Source','Names','Settings','Log','Home','History','','Join')
 for($i=0;$i -lt 8;$i++){if($i -eq 6){Assert ([string]::IsNullOrEmpty((Get-PestoPageShortcut $i Single Search)))}else{Assert ([string](Get-PestoPageShortcut $i Single Search) -ceq $expected[$i]) ('route '+$i)}}
 Assert ((Get-PestoPageShortcut 0 Batch Search) -eq 'Queue')
 Assert ($defs['Invoke-PestoPageShortcut'] -notmatch 'Set-PestoUxPage|Set-PestoSuiteMode|Invoke-PestoPrimaryAction') 'No navigation'
}
Case 'Refresh shortcuts map to current page and do not execute operations' {
 foreach($i in 0,1,2,3,4,5,7){Assert ([string](Get-PestoPageShortcut $i Single Refresh))}
 Assert ($defs['Invoke-PestoPageShortcut'].Contains('$script:Running -or $script:PreflightRunning -or $script:DirectBusy -or $script:JoinBusy'))
}
Case 'Small workspace maximizes oversized design without changing valid preferences' {
 Assert (Test-PestoStartupMaximized $null 1600 1000 1366 768)
 Assert (-not (Test-PestoStartupMaximized ([pscustomobject]@{WindowWidth=1000;WindowHeight=650;Maximized=$false}) 1600 1000 1366 768))
 Assert (Test-PestoStartupMaximized ([pscustomobject]@{WindowWidth=1000;WindowHeight=650;Maximized=$true}) 1600 1000 1920 1080)
 Assert (-not (Test-PestoStartupMaximized $null 1200 760 1920 1080))
}

if($Wpf){
 Add-Type -AssemblyName PresentationFramework

 # Use the production closing handlers in their real registration order, with I/O trapped.
 foreach($name in @('Show-PestoHostedWindow','Complete-PestoHostedWindow','Invoke-PestoHostedKey','Invoke-PestoPanelClosing')){. ([scriptblock]::Create($defs[$name]))}
 $tokens=$null;$errors=$null;$coreAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'wad/Pesto-Core.ps1'),[ref]$tokens,[ref]$errors)
 $closing=@($coreAst.FindAll({param($n) $n -is [Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Expression.Extent.Text -eq '$Win' -and $n.Member.Value -eq 'Add_Closing'},$true))
 Assert ($closing.Count -eq 1) 'Main Closing handler must be unambiguous'
 $script:ClosingUnderTest=$closing[0].Arguments[0].ScriptBlock.GetScriptBlock()
 $script:ClosingHandler=[ComponentModel.CancelEventHandler]$script:ClosingUnderTest
 function Test-PestoAsyncOperationRunning {param($Name);$false}
 function Test-PestoQueueWorkerStillActive {$false}
 function Confirm-PestoDiscardSettings {$script:DiscardCalls++;$false}
 function Show-MsgWarning {param($Message,$Title);$script:WarningCalls++}
 function Save-PestoQueueCheckpointSafe {throw 'Unexpected checkpoint write'}
 function Save-Prefs {throw 'Unexpected preference write'}
 function Invoke-HostedRegressionTick {
  param($Sender,$EventArgs)
  $Sender.Stop()
  try{
   $script:FocusInside=$script:Win.Content.Children[1].IsKeyboardFocusWithin
   if($script:CloseScenario -eq 'Escape'){
    $focused=[Windows.Input.Keyboard]::FocusedElement
    Assert ($focused -is [Windows.UIElement]) 'No keyboard focus in hosted preview'
    $key=[Windows.Input.KeyEventArgs]::new([Windows.Input.Keyboard]::PrimaryDevice,[Windows.PresentationSource]::FromVisual($script:Win),0,[Windows.Input.Key]::Escape)
    $key.RoutedEvent=[Windows.Input.Keyboard]::PreviewKeyDownEvent
    $focused.RaiseEvent($key)
    Assert $key.Handled 'Escape was not consumed by hosted preview'
   }else{$script:Win.Close()}
  }catch{$script:HostedFailure=$_.Exception.Message}
  finally{if($script:HostedChild.Tag.Frame.Continue){$script:HostedFailure+=' Preview remained open.';$script:HostedChild.Close()}}
 }
 foreach($scenario in @('Escape','ParentClose')){
  Case ('WPF '+$scenario+' closes only generic preview and preserves settings draft') {
   $script:CloseScenario=$scenario;$script:HostedFailure='';$script:FocusInside=$false;$script:DiscardCalls=0;$script:WarningCalls=0
   $script:Running=$false;$script:DirectBusy=$false;$script:JoinBusy=$false;$script:RecoveryBusy=$false;$script:PestoAsyncOperations=@{}
   $script:Win=[Windows.Window]::new();$script:Win.Width=600;$script:Win.Height=400;$script:Win.Content=[Windows.Controls.Grid]::new()
   $field=[Windows.Controls.TextBox]::new();$field.Text='unsaved';[void]$script:Win.Content.Children.Add($field)
   $script:Win.Add_Closing([ComponentModel.CancelEventHandler]${function:Invoke-PestoPanelClosing});$script:Win.Add_Closing($script:ClosingHandler)
   $script:HostedChild=[Windows.Markup.XamlReader]::Parse('<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"><Grid><Button Name="Cancel" IsCancel="True" Content="Close"/></Grid></Window>')
   $timer=[Windows.Threading.DispatcherTimer]::new();$timer.Interval=[TimeSpan]::FromMilliseconds(250);$timer.Add_Tick([EventHandler]${function:Invoke-HostedRegressionTick})
   try{
    $script:Win.Show();$script:HostedChild.Owner=$script:Win;[void]$script:Win.Activate();[void]$field.Focus();$timer.Start();Show-PestoHostedWindow $script:HostedChild
    Assert (-not $script:HostedFailure) $script:HostedFailure;Assert $script:FocusInside 'Focus stayed outside generic preview'
    Assert ($script:DiscardCalls -eq 0 -and $script:WarningCalls -eq 0) 'Parent close handler ran after panel cancelled closing'
    Assert ($script:Win.IsVisible -and $field.Text -ceq 'unsaved' -and $field.IsEnabled -and $script:PestoPanelStack.Count -eq 0)
    Assert $field.IsKeyboardFocusWithin 'Original field focus was not restored'
   }finally{$timer.Stop();$script:Win.Remove_Closing($script:ClosingHandler);$script:Win.Close()}
  }
 }
 Case 'Main close still refuses active mutation and asks before discarding a draft' {
  $script:DiscardCalls=0;$script:WarningCalls=0;$script:Running=$true;$e=[ComponentModel.CancelEventArgs]::new()
  & $script:ClosingUnderTest $null $e
  Assert ($e.Cancel -and $script:WarningCalls -eq 1 -and $script:DiscardCalls -eq 0)
  $script:Running=$false;$e=[ComponentModel.CancelEventArgs]::new();& $script:ClosingUnderTest $null $e
  Assert ($e.Cancel -and $script:DiscardCalls -eq 1)
 }
 Case 'WPF focus container includes sibling fields within their shared card' {. ([scriptblock]::Create($defs['Get-PestoFocusZoneContainer']));$card=[Windows.Controls.Border]::new();$panel=[Windows.Controls.StackPanel]::new();$organism=[Windows.Controls.ComboBox]::new();$candidate=[Windows.Controls.ComboBox]::new();[void]$panel.Children.Add($organism);[void]$panel.Children.Add($candidate);$card.Child=$panel;Assert ([object]::ReferenceEquals((Get-PestoFocusZoneContainer $organism),$card) -and [object]::ReferenceEquals((Get-PestoFocusZoneContainer $candidate),$card))}

 foreach($functionName in @('Show-PestoPanel','Show-PestoChoiceTable','Show-PestoDetailsPane')){Case ('WPF XAML loads: '+$functionName) {$match=[regex]::Match($defs[$functionName],"(?s)\[xml\]\`$x=@'\s*(.*?)\s*'@");Assert $match.Success ('Bloc XAML littéral absent de '+$functionName);[xml]$xml=$match.Groups[1].Value;$control=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($xml));Assert ($null -ne $control);if($control -is [Windows.Window]){$control.Close()}}}

 foreach($name in @('Show-PestoChoiceTable','Set-PestoChoiceGrouping')){. ([scriptblock]::Create($defs[$name]))}
 function Set-WindowIcon {param($Window)}
 function Show-PestoHostedWindow {param($Window);$script:HostedClosed=$false;$Window.Add_Closed({$script:HostedClosed=$true});if($script:HostedChoice -eq 'Accept'){$Window.FindName('Rows').SelectedIndex=0};$Window.FindName($script:HostedChoice).RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent));Assert $script:HostedClosed 'Hosted table did not close'}
 $script:Win=[Windows.Window]::new();$script:Win.ShowActivated=$false;$script:Win.ShowInTaskbar=$false;$script:Win.Opacity=0;$script:Win.Left=-20000;$script:Win.Top=-20000;$script:Win.Width=1;$script:Win.Height=1;$script:Win.Show()
 Case 'WPF hosted cancel closes without selecting or accepting' {$script:HostedChoice='Cancel';$r=Show-PestoChoiceTable -Title 'Fixture' -Rows @([pscustomobject]@{Name='A'}) -Columns @(@{Key='Name';Label='Name'}) -AcceptText 'Use';Assert (-not$r.Accepted -and $r.Items.Count -eq 0)}
 Case 'WPF hosted accept returns exact selected row and closes' {$script:HostedChoice='Accept';$row=[pscustomobject]@{Name='A'};$r=Show-PestoChoiceTable -Title 'Fixture' -Rows @($row) -Columns @(@{Key='Name';Label='Name'}) -AcceptText 'Use';Assert ($r.Accepted -and [object]::ReferenceEquals($r.Items[0],$row))}
 $script:Win.Close()
}
$failed=@($results|Where-Object{-not $_.Passed});$report=[pscustomobject]@{Suite='Workbench120';Platform=[Environment]::OSVersion.ToString();PowerShell=$PSVersionTable.PSVersion.ToString();Wpf=[bool]$Wpf;Passed=$results.Count-$failed.Count;Failed=$failed.Count;Cases=$results}
if($ReportPath){[IO.File]::WriteAllText($ReportPath,($report|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))}
$failed|ForEach-Object {Write-Output ($_.Name+": "+$_.Error)};Write-Output ("Workbench120 : {0}/{1} PASS" -f $report.Passed,$results.Count);if($failed.Count){exit 1}
