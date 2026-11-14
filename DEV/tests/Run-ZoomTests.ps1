#requires -Version 5.1
[CmdletBinding()]
param([switch]$Wpf,[string]$ReportPath='')
# Définitions de présentation uniquement : aucun démarrage de Pesto, AD, identité ou registre.
# -Wpf ajoute une mesure du vrai XAML Windows sans Show(), utilisable en session 0.
$ErrorActionPreference='Stop';Set-StrictMode -Off
$root=Split-Path $PSScriptRoot -Parent
$defs=@{};$results=[Collections.Generic.List[object]]::new()
foreach($file in @('Pesto-Appearance.ps1','Pesto-SuiteUI.ps1','Pesto-Core.ps1')){
 $tokens=$null;$parseErrors=$null
 $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root ('wad/'+$file)),[ref]$tokens,[ref]$parseErrors)
 if($parseErrors.Count){throw ($parseErrors.Message -join '; ')}
 foreach($node in $ast.EndBlock.Statements){if($node -is [Management.Automation.Language.FunctionDefinitionAst]){$defs[$node.Name]=$node.Extent.Text}}
}
foreach($name in @('ConvertTo-PestoUiZoomPercent','Get-PestoZoomViewportLayout','ConvertTo-PestoLayoutPreference','Set-PestoUiZoom','Initialize-PestoAppearance','Get-PestoResponsiveLayout')){
 if(-not $defs.ContainsKey($name)){throw ('Fonction de zoom manquante : '+$name)}
 . ([scriptblock]::Create($defs[$name]))
}
function Assert-Zoom {param($Condition,[string]$Message='Assertion de zoom non satisfaite.');if(-not $Condition){throw $Message}}
function Equal-Zoom {param($Actual,$Expected);if($Actual -ne $Expected){throw ('Attendu '+$Expected+', obtenu '+$Actual)}}
function Case-Zoom {param([string]$Name,[scriptblock]$Body);try{& $Body;$results.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''})}catch{$results.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message})}}
function Update-PestoUiZoomLayout {$script:ZoomLayoutCalls++;$script:ZoomApplied=$script:PestoUiZoomPercent}
function Save-Prefs {$script:ZoomSaveCalls++;$script:ZoomSaved=$script:PestoUiZoomPercent}
function Write-Log {param($Message,$Level,$ErrorObject,$Area);$script:ZoomLog.Add([string]$Message)}
function Set-PestoPersistenceWarning {param($Message);$script:ZoomWarning=[string]$Message}
function Get-PrefsFile {$null}
function Resolve-PestoTheme {param($Mode);'Light'}
function Get-PestoAppearanceValue {param($Name);$script:ZoomStore[$Name]}
function Set-PestoAppearanceValue {param($Name,$Value);if($script:ZoomStoreFail){throw 'Échec de stockage du banc.'};$script:ZoomStore[$Name]=$Value;$script:ZoomStoreWrites++}
function Test-PestoAppearanceSid {param($Sid);$Sid -eq 'S-1-5-21-1-2-3-1001'}
function Reset-ZoomTest {
 $script:PestoUiZoomPercent=100;$script:ZoomLayoutCalls=0;$script:ZoomSaveCalls=0;$script:ZoomApplied=0;$script:ZoomSaved=0
 $script:ZoomStore=@{};$script:ZoomStoreFail=$false;$script:ZoomStoreWrites=0;$script:ZoomWarning='';$script:ZoomLog=[Collections.Generic.List[string]]::new()
 $script:LayoutPreference=[pscustomobject]@{Schema=1};$script:Win=$null;$script:SuiteReady=$false;$script:PestoUxReady=$false;$script:PestoUiZoomReady=$false;$script:PestoUiZoomUpdating=$false
}
[xml]$shell=Get-Content -LiteralPath (Join-Path $root 'wad/Pesto-Shell.xaml') -Raw -Encoding UTF8
function Find-ZoomNode {param([string]$Name);$shell.SelectSingleNode('//*[@*[local-name()="Name"]="'+$Name+'"]')}
function Test-ZoomAncestor {param($Node,[string]$Name);$candidate=$Node.ParentNode;while($candidate){if($candidate.GetAttribute -and $candidate.GetAttribute('Name','http://schemas.microsoft.com/winfx/2006/xaml') -eq $Name){return $true};$candidate=$candidate.ParentNode};$false}
Reset-ZoomTest
Case-Zoom 'Every supported ten-percent value is preserved exactly' {foreach($n in @(80,90,100,110,120,130,140,150)){Equal-Zoom (ConvertTo-PestoUiZoomPercent $n) $n}}
Case-Zoom 'Numeric values are clamped to 80 and 150' {foreach($n in @(-100000,-1,0,79)){Equal-Zoom (ConvertTo-PestoUiZoomPercent $n) 80};foreach($n in @(151,10000)){Equal-Zoom (ConvertTo-PestoUiZoomPercent $n) 150}}
Case-Zoom 'Intermediate values round to ten away from zero at the half step' {foreach($pair in @(@(84,80),@(85,90),@(94,90),@(95,100),@(105,110),@(144,140),@(145,150))){Equal-Zoom (ConvertTo-PestoUiZoomPercent $pair[0]) $pair[1]}}
Case-Zoom 'Missing, malformed and nonfinite values use 100 percent' {foreach($v in @($null,'','zoom','100%',[double]::NaN,[double]::PositiveInfinity,[double]::NegativeInfinity)){Equal-Zoom (ConvertTo-PestoUiZoomPercent $v) 100}}
Case-Zoom 'Normalization is idempotent and uses integer percentages' {foreach($n in (75..155)){ $r=ConvertTo-PestoUiZoomPercent $n;Assert-Zoom ($r -is [int]);Equal-Zoom (ConvertTo-PestoUiZoomPercent $r) $r;Equal-Zoom ($r%10) 0}}
Case-Zoom 'Stored layout preserves normalized zoom and unrelated fields' {$p=ConvertTo-PestoLayoutPreference ([pscustomobject]@{UiZoomPercent=125;WindowWidth=1280;NavigationCollapsed=$true;LogFontSize=16;LogWrap=$false});Equal-Zoom $p.UiZoomPercent 130;Equal-Zoom $p.WindowWidth 1280;Assert-Zoom $p.NavigationCollapsed;Equal-Zoom $p.LogFontSize 16;Assert-Zoom (-not $p.LogWrap)}
Case-Zoom 'Old layout without zoom opens at 100 percent' {$p=ConvertTo-PestoLayoutPreference ([pscustomobject]@{Schema=1;WindowWidth=900});Equal-Zoom (ConvertTo-PestoUiZoomPercent $p.UiZoomPercent) 100}
Case-Zoom 'Corrupt stored zoom cannot exceed bounds or become nonfinite' {foreach($v in @('broken','NaN','Infinity',-10,500)){$p=ConvertTo-PestoLayoutPreference ([pscustomobject]@{UiZoomPercent=$v});Assert-Zoom ($p.UiZoomPercent -ge 80 -and $p.UiZoomPercent -le 150 -and $p.UiZoomPercent%10 -eq 0)}}
Case-Zoom 'Layout JSON round trip preserves the chosen zoom' {foreach($n in @(80,100,150)){$p=ConvertTo-PestoLayoutPreference ([pscustomobject]@{UiZoomPercent=$n;NavigationCollapsed=$true});$q=ConvertTo-PestoLayoutPreference ($p|ConvertTo-Json -Compress|ConvertFrom-Json);Equal-Zoom $q.UiZoomPercent $n;Assert-Zoom $q.NavigationCollapsed}}
Case-Zoom 'Initialization reads layout zoom without writing preferences' {Reset-ZoomTest;$script:ZoomStore.Layout='{"Schema":1,"UiZoomPercent":140,"NavigationCollapsed":true}';Initialize-PestoAppearance -OwnerSid 'S-1-5-21-1-2-3-1001' -Config ([pscustomobject]@{Conf=@([pscustomobject]@{DarkMode=0})});Equal-Zoom $script:PestoUiZoomPercent 140;Equal-Zoom $script:ZoomStoreWrites 0;Assert-Zoom $script:NavigationCollapsed}
Case-Zoom 'Initialization without a preference chooses 100 percent' {Reset-ZoomTest;Initialize-PestoAppearance -OwnerSid 'S-1-5-21-1-2-3-1001' -Config ([pscustomobject]@{Conf=@([pscustomobject]@{DarkMode=0})});Equal-Zoom $script:PestoUiZoomPercent 100;Equal-Zoom $script:ZoomStoreWrites 0}
Case-Zoom 'Malformed layout falls back safely without saving' {Reset-ZoomTest;$script:ZoomStore.Layout='{broken';Initialize-PestoAppearance -OwnerSid 'S-1-5-21-1-2-3-1001' -Config ([pscustomobject]@{Conf=@([pscustomobject]@{DarkMode=0})});Equal-Zoom $script:PestoUiZoomPercent 100;Equal-Zoom $script:ZoomStoreWrites 0}
Case-Zoom 'Set applies an absolute normalized percentage without implicit persistence' {Reset-ZoomTest;Set-PestoUiZoom -Percent 135;Equal-Zoom $script:PestoUiZoomPercent 140;Equal-Zoom $script:ZoomApplied 140;Equal-Zoom $script:ZoomSaveCalls 0}
Case-Zoom 'Explicit persistence saves the percentage immediately' {Reset-ZoomTest;Set-PestoUiZoom -Percent 120 -Persist;Equal-Zoom $script:PestoUiZoomPercent 120;Equal-Zoom $script:ZoomSaveCalls 1;Equal-Zoom $script:ZoomSaved 120}
Case-Zoom 'Repeated assignment has no cumulative scale drift' {Reset-ZoomTest;1..100|ForEach-Object{Set-PestoUiZoom -Percent 130};Equal-Zoom $script:PestoUiZoomPercent 130;Equal-Zoom $script:ZoomApplied 130;Equal-Zoom $script:ZoomSaveCalls 0}
Case-Zoom 'Reset from both bounds returns exactly to 100 percent' {foreach($n in @(80,150)){Reset-ZoomTest;Set-PestoUiZoom -Percent $n;Set-PestoUiZoom -Percent 100 -Persist;Equal-Zoom $script:PestoUiZoomPercent 100;Equal-Zoom $script:ZoomSaved 100}}
Case-Zoom 'Viewport uses physical DIP divided by absolute scale' {foreach($n in @(80,100,150)){$v=Get-PestoZoomViewportLayout -Width 1500 -Height 1000 -Percent $n;Equal-Zoom $v.Scale ($n/100.0);Equal-Zoom $v.Width (1500/($n/100.0));Equal-Zoom $v.Height (1000/($n/100.0))}}
Case-Zoom 'Tiny viewport retains exact logical width without horizontal overflow' {$v=Get-PestoZoomViewportLayout -Width 320 -Height 200 -Percent 150;Equal-Zoom $v.Width (320/1.5);Equal-Zoom $v.Height 520;Equal-Zoom $v.Scale 1.5}
Case-Zoom 'Invalid or unmeasured viewport stays finite and positive' {foreach($n in @(-1,0,[double]::NaN,[double]::PositiveInfinity)){$v=Get-PestoZoomViewportLayout -Width $n -Height $n -Percent 120;Equal-Zoom $v.Width (760/1.2);Equal-Zoom $v.Height 520;Assert-Zoom (-not [double]::IsInfinity($v.Width) -and -not [double]::IsInfinity($v.Height));Assert-Zoom (-not [double]::IsNaN($v.Width) -and -not [double]::IsNaN($v.Height))}}
Case-Zoom 'Zoomed logical width drives responsive one-column form' {$v=Get-PestoZoomViewportLayout -Width 1280 -Height 800 -Percent 150;$r=Get-PestoResponsiveLayout -Width $v.Width -Height $v.Height -NavigationCollapsed $false -HelpVisible $false;Assert-Zoom $r.SingleColumn}
Case-Zoom 'All zoom controls have stable accessible names and tooltips' {foreach($name in @('PestoZoomOut','PestoZoomReset','PestoZoomIn')){$node=Find-ZoomNode $name;Assert-Zoom ($null -ne $node) $name;Assert-Zoom $node.GetAttribute('AutomationProperties.Name') $name;Assert-Zoom $node.GetAttribute('ToolTip') $name}}
Case-Zoom 'Zoom toolbar stays outside both scaled root and viewport scrolling' {foreach($name in @('PestoZoomOut','PestoZoomReset','PestoZoomIn')){$node=Find-ZoomNode $name;Assert-Zoom (Test-ZoomAncestor $node 'PestoZoomBar');Assert-Zoom (-not (Test-ZoomAncestor $node 'SuiteRoot'));Assert-Zoom (-not (Test-ZoomAncestor $node 'PestoZoomViewport'))}}
Case-Zoom 'Canvas uses vertical page scrolling and no horizontal page scrollbar' {$v=Find-ZoomNode 'PestoZoomViewport';Assert-Zoom ($v.LocalName -eq 'ScrollViewer');Equal-Zoom $v.GetAttribute('HorizontalScrollBarVisibility') 'Disabled';Equal-Zoom $v.GetAttribute('VerticalScrollBarVisibility') 'Auto';Assert-Zoom (Test-ZoomAncestor (Find-ZoomNode 'SuiteRoot') 'PestoZoomViewport')}
Case-Zoom 'Names page scrolls filters, grid and tools together while preserving grid virtualization' {
 $page=Find-ZoomNode 'NmPageScroll';Equal-Zoom $page.LocalName 'ScrollViewer';Equal-Zoom $page.VerticalScrollBarVisibility 'Auto';Equal-Zoom $page.HorizontalScrollBarVisibility 'Disabled'
 foreach($name in @('NmGrid','NmExtraTools','NmUseCandidate')){Assert-Zoom (Test-ZoomAncestor (Find-ZoomNode $name) 'NmPageScroll') $name}
 $grid=Find-ZoomNode 'NmGrid';Assert-Zoom ([double]$grid.MinHeight -ge 230 -and [double]$grid.Height -le 400);Equal-Zoom $grid.EnableRowVirtualization 'True'
}
Case-Zoom 'Names grid uses the same bounded responsive height as the batch grid' {
 Assert-Zoom ($defs['Update-PestoUxLayout'] -match '\$namesGrid\.Height=\$Grid\.Height')
 Assert-Zoom ($defs['Update-PestoUxLayout'] -match '\$Grid\.Height=\[Math\]::Max\(230,\[Math\]::Min\(400,')
}
Case-Zoom 'Preference save includes zoom in the established layout store' {Assert-Zoom ($defs['Save-Prefs'] -match 'UiZoomPercent\s*=');Assert-Zoom ($defs['Save-Prefs'] -match "Set-PestoAppearanceValue\s+-Name\s+'Layout'")}
Case-Zoom 'Zoom presentation does not call mutation or domain commands' {foreach($name in @('Set-PestoUiZoom','Update-PestoUiZoomLayout','Get-PestoZoomViewportLayout')){Assert-Zoom ($defs[$name] -notmatch '(?i)\b(Add-Computer|Rename-Computer|Move-ADObject|Remove-ADComputer|Set-ADComputer|Restart-Computer|Invoke-PestoJoinExecute|Save-Cfg)\b') $name}}

# La partie WPF est ajoutée ci-dessous ; les doubles de stockage sont conservés.
if(-not $defs.ContainsKey('Invoke-PestoUiZoomClick')){throw 'Handler de clic zoom absent.'}
. ([scriptblock]::Create($defs['Invoke-PestoUiZoomClick']))
Case-Zoom 'Plus and minus buttons change by exactly ten and persist each click' {Reset-ZoomTest;Invoke-PestoUiZoomClick ([pscustomobject]@{Name='PestoZoomIn'}) $null;Equal-Zoom $script:PestoUiZoomPercent 110;Invoke-PestoUiZoomClick ([pscustomobject]@{Name='PestoZoomOut'}) $null;Equal-Zoom $script:PestoUiZoomPercent 100;Equal-Zoom $script:ZoomSaveCalls 2}
Case-Zoom 'Repeated button clicks stop at both bounds' {Reset-ZoomTest;1..20|ForEach-Object{Invoke-PestoUiZoomClick ([pscustomobject]@{Name='PestoZoomIn'}) $null};Equal-Zoom $script:PestoUiZoomPercent 150;1..20|ForEach-Object{Invoke-PestoUiZoomClick ([pscustomobject]@{Name='PestoZoomOut'}) $null};Equal-Zoom $script:PestoUiZoomPercent 80}
Case-Zoom 'Percentage button resets to exactly 100 and persists' {Reset-ZoomTest;$script:PestoUiZoomPercent=150;Invoke-PestoUiZoomClick ([pscustomobject]@{Name='PestoZoomReset'}) $null;Equal-Zoom $script:PestoUiZoomPercent 100;Equal-Zoom $script:ZoomSaveCalls 1}
Case-Zoom 'Unknown button cannot change or persist zoom' {Reset-ZoomTest;Invoke-PestoUiZoomClick ([pscustomobject]@{Name='NotAZoomButton'}) $null;Equal-Zoom $script:PestoUiZoomPercent 100;Equal-Zoom $script:ZoomSaveCalls 0}
Case-Zoom 'One hundred reversible click cycles cannot accumulate rounding error' {Reset-ZoomTest;1..100|ForEach-Object{Invoke-PestoUiZoomClick ([pscustomobject]@{Name='PestoZoomIn'}) $null;Invoke-PestoUiZoomClick ([pscustomobject]@{Name='PestoZoomOut'}) $null};Equal-Zoom $script:PestoUiZoomPercent 100;Equal-Zoom $script:ZoomSaveCalls 200}

if($Wpf){
 if($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){throw '-Wpf exige Windows PowerShell 5.1.'}
 if([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA'){throw '-Wpf exige powershell.exe -STA.'}
 Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
 foreach($name in @('Update-PestoUiZoomLayout','Save-Prefs','Get-PestoUiLayoutSize','Initialize-PestoUiZoom','Invoke-PestoUiZoomViewportChanged')){if(-not $defs.ContainsKey($name)){throw ('Fonction WPF manquante : '+$name)};. ([scriptblock]::Create($defs[$name]))}
 # Fenêtre jamais montrée : seul son arbre visuel est arrangé, sans activité de Pesto ni accès métier.
 function Arrange-ZoomCanvas {param([double]$Width,[double]$Height)
  $hostElement=$script:Win.Content
  for($i=0;$i -lt 4;$i++){
   $hostElement.Measure([Windows.Size]::new($Width,$Height));$hostElement.Arrange([Windows.Rect]::new(0,0,$Width,$Height));$hostElement.UpdateLayout()
   Update-PestoUiZoomLayout
  }
 }
 function Assert-ZoomControlsInside {param([double]$Width,[double]$Height)
  foreach($name in @('PestoZoomOut','PestoZoomReset','PestoZoomIn')){
   $control=$script:Win.FindName($name);$position=$control.TranslatePoint([Windows.Point]::new(0,0),$script:Win.Content)
   Assert-Zoom ($control.IsVisible -or $control.Visibility -eq [Windows.Visibility]::Visible) ('Contrôle masqué : '+$name)
   Assert-Zoom ($control.ActualWidth -gt 0 -and $control.ActualHeight -gt 0) ('Contrôle non mesuré : '+$name)
   Assert-Zoom ($position.X -ge -0.1 -and $position.Y -ge -0.1 -and $position.X+$control.ActualWidth -le $Width+0.1 -and $position.Y+$control.ActualHeight -le $Height+0.1) ('Contrôle hors fenêtre : '+$name+' '+$position)
  }
 }
 Reset-ZoomTest
 try{
  Case-Zoom 'WPF: real XAML loads and zoom controls remain outside the transformed root' {
   $script:Win=[Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText((Join-Path $root 'wad/Pesto-Shell.xaml')))
   Assert-Zoom $script:Win
   $script:ChkTechnicalColumns=$Win.FindName('ChkTechnicalColumns');$script:AdvancedOptions=$Win.FindName('AdvancedOptions')
   $script:NavigationCollapsed=$false;$script:HelpVisible=$false;$script:LogFontSize=12;$script:LogWrap=$true;$script:PestoUxReady=$false
   foreach($name in @('SuiteRoot','PestoZoomViewport','PestoZoomBar','PestoZoomOut','PestoZoomReset','PestoZoomIn')){Assert-Zoom ($null -ne $Win.FindName($name)) $name}
   Initialize-PestoUiZoom
   Arrange-ZoomCanvas 1280 800
   Assert-ZoomControlsInside 1280 800
  }
  Case-Zoom 'WPF: initialization is idempotent and a routed click saves once' {
   Initialize-PestoUiZoom;Initialize-PestoUiZoom;Set-PestoUiZoom -Percent 100;$script:ZoomStoreWrites=0
   $button=$Win.FindName('PestoZoomIn');$button.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
   Equal-Zoom $script:PestoUiZoomPercent 110;Equal-Zoom $script:ZoomStoreWrites 1
  }
  Case-Zoom 'WPF: all percentages give an absolute uniform transform with no drift' {
   foreach($n in @(80,150,120,120,150,80,100)){
    Set-PestoUiZoom -Percent $n;Arrange-ZoomCanvas 1280 800
    $transform=$Win.FindName('SuiteRoot').LayoutTransform
    Assert-Zoom ($transform -is [Windows.Media.ScaleTransform]);Equal-Zoom $transform.ScaleX ($n/100.0);Equal-Zoom $transform.ScaleY ($n/100.0)
   }
  }
  Case-Zoom 'WPF: buttons reflect both bounds and reset remains enabled at 100' {
   foreach($n in @(80,100,150)){
    Set-PestoUiZoom -Percent $n;Arrange-ZoomCanvas 1280 800
    Equal-Zoom $Win.FindName('PestoZoomOut').IsEnabled ($n -gt 80);Equal-Zoom $Win.FindName('PestoZoomIn').IsEnabled ($n -lt 150)
    Assert-Zoom $Win.FindName('PestoZoomReset').IsEnabled;Assert-Zoom ([string]$Win.FindName('PestoZoomReset').Content -match ('^'+$n+'\s*%$'))
   }
  }
  Case-Zoom 'WPF: 150 percent on 760 by 560 keeps commands accessible with scrollable content' {
   Set-PestoUiZoom -Percent 150;Arrange-ZoomCanvas 760 560;Assert-ZoomControlsInside 760 560
   $viewport=$Win.FindName('PestoZoomViewport');$canvas=$Win.FindName('SuiteRoot')
   Assert-Zoom ($viewport.ExtentWidth -ge $canvas.Width*1.5-1);Assert-Zoom ($viewport.ExtentHeight -ge $canvas.Height*1.5-1)
   Assert-Zoom ($viewport.ScrollableWidth -le 1 -and $viewport.ScrollableHeight -gt 0)
  }
  Case-Zoom 'WPF: expanded name tools retain a finite visible grid at 760 by 560 and 150 percent' {
   $main=$Win.FindName('MainTabs');$main.SelectedIndex=1;$Win.FindName('NmExtraTools').IsExpanded=$true
   $names=$Win.FindName('NmGrid');$names.ItemsSource=@(1..40|ForEach-Object{[pscustomobject]@{Nom=('P111301LY765'+$_.ToString('D3'));Type='Portable';Site='LY';Equipe='765';Num=$_.ToString('D3');Statut='Libre'}})
   Set-PestoUiZoom -Percent 150;Arrange-ZoomCanvas 760 560
   Assert-Zoom ($names.ActualHeight -ge 230 -and $names.ActualHeight -le 400) ('Grille Noms écrasée : '+$names.ActualHeight)
   Assert-Zoom ($names.ActualWidth -gt 0 -and $names.Items.Count -eq 40)
   $page=$Win.FindName('NmPageScroll');Assert-Zoom ($page.ScrollableHeight -gt 0)
   foreach($name in @('NmGrid','NmUseCandidate','NmOtherNames','NmVerifyCandidate','NmExtraTools')){
    $control=$Win.FindName($name);$control.BringIntoView();Arrange-ZoomCanvas 760 560
    $point=$control.TranslatePoint([Windows.Point]::new(0,0),$page)
    Assert-Zoom ($control.ActualWidth -gt 0 -and $control.ActualHeight -gt 0) ('Non mesuré : '+$name)
    Assert-Zoom ($point.Y -lt $page.ActualHeight -and $point.Y+$control.ActualHeight -gt 0) ('Inatteignable dans le défilement Noms : '+$name+' '+$point)
   }
   Assert-ZoomControlsInside 760 560
   $Win.FindName('NmExtraTools').IsExpanded=$false;$main.SelectedIndex=0
  }
  Case-Zoom 'WPF: zoom commands remain reachable at 320 by 300 without shrinking their text' {
   Set-PestoUiZoom -Percent 150;Arrange-ZoomCanvas 320 300;Assert-ZoomControlsInside 320 300
   Assert-Zoom ($Win.FindName('PestoZoomBar').LayoutTransform.Value.IsIdentity)
  }
  Case-Zoom 'WPF: reset restores logical viewport without leaving accumulated scale' {
   Set-PestoUiZoom -Percent 150;Arrange-ZoomCanvas 1280 800
   Invoke-PestoUiZoomClick ([pscustomobject]@{Name='PestoZoomReset'}) $null;Arrange-ZoomCanvas 1280 800
   Equal-Zoom $Win.FindName('SuiteRoot').LayoutTransform.ScaleX 1.0;Equal-Zoom $script:PestoUiZoomPercent 100
   $logical=Get-PestoUiLayoutSize;Equal-Zoom $logical.Width $Win.FindName('SuiteRoot').Width;Equal-Zoom $logical.Height $Win.FindName('SuiteRoot').Height
  }
  Case-Zoom 'WPF: join uses available width and service status stays below its field at every viewport' {
   foreach($name in @('Get-PestoResponsiveFieldCell','Set-PestoResponsiveFieldPairs')){. ([scriptblock]::Create($defs[$name]))}
   $joinView=[Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText((Join-Path $root 'wad/Pesto-Join.xaml')))
   $joinHost=$Win.FindName('UxJoinHost');$joinHost.Content=$joinView
   $main=$Win.FindName('MainTabs');$main.SelectedItem=$Win.FindName('TabJoin')
   $fields=$joinView.FindName('JnFields');$service=$joinView.FindName('JnService');$status=$joinView.FindName('JnServiceState')
   $status.Text='Services : lecture indisponible. Saisie libre possible.'
   $script:PestoFieldLayouts=@{}
   try{
    foreach($size in @(@(1920,1200),@(1024,768),@(760,560),@(1920,1200))){foreach($percent in @(80,100,150)){
     Set-PestoUiZoom -Percent $percent;Arrange-ZoomCanvas $size[0] $size[1]
     $logical=Get-PestoUiLayoutSize
     $responsive=Get-PestoResponsiveLayout $logical.Width $logical.Height $false $false
     $Win.FindName('SidebarWidth').Width=[Windows.GridLength]::new($(if($logical.Width -lt 760){68}else{194}))
     Set-PestoResponsiveFieldPairs $fields $responsive.SingleColumn
     Arrange-ZoomCanvas $size[0] $size[1]
     $context=('{0}x{1} / {2}%' -f $size[0],$size[1],$percent)
     $scroll=$joinView.Content.Children[0];$body=$scroll.Content
     Assert-Zoom ($joinHost.ActualWidth -gt 0 -and [Math]::Abs($joinView.ActualWidth-$joinHost.ActualWidth) -le 1) ('Join host width: '+$context)
     Assert-Zoom ([Math]::Abs($body.ActualWidth-$scroll.ViewportWidth) -le 1) ('Join body leaves side margins: '+$context+' body='+$body.ActualWidth+' viewport='+$scroll.ViewportWidth)
     $statusPoint=$status.TranslatePoint([Windows.Point]::new(0,0),$fields)
     $servicePoint=$service.TranslatePoint([Windows.Point]::new(0,0),$fields)
     Assert-Zoom ($status.ActualHeight -gt 0 -and $status.ActualWidth -gt 0) ('Status not measured: '+$context)
     Assert-Zoom ($statusPoint.Y -ge $servicePoint.Y+$service.ActualHeight+3) ('Status overlaps service: '+$context)
     Assert-Zoom ([Math]::Abs($statusPoint.X-$servicePoint.X) -le 1) ('Status separated from service: '+$context)
     $statusRect=[Windows.Rect]::new($statusPoint,[Windows.Size]::new($status.ActualWidth,$status.ActualHeight))
     foreach($control in $fields.Children){
      if($control -eq $service.Parent){continue}
      $point=$control.TranslatePoint([Windows.Point]::new(0,0),$fields)
      $overlap=[Windows.Rect]::Intersect($statusRect,[Windows.Rect]::new($point,[Windows.Size]::new($control.ActualWidth,$control.ActualHeight)))
      Assert-Zoom ($overlap.IsEmpty -or $overlap.Width -le 1 -or $overlap.Height -le 1) ('Service status overlaps '+$control.GetType().Name+': '+$context)
     }
     Assert-Zoom ($scroll.ScrollableWidth -le 1) ('Horizontal join overflow: '+$context)
     $start=$joinView.FindName('JnStart');$position=$start.TranslatePoint([Windows.Point]::new(0,0),$joinView)
     Assert-Zoom ($position.Y+$start.ActualHeight -le $joinView.ActualHeight+1) ('Join action outside page: '+$context)
    }}
   }finally{$joinHost.Content=$null;$main.SelectedIndex=0;$script:PestoFieldLayouts=@{}}
  }
  Case-Zoom 'WPF: responsive header keeps toolbar and operation notices on separate rows' {
   foreach($name in @('Set-PestoResponsiveColumnGroups','Set-PestoResponsiveFieldPairs','Get-PestoResponsiveFieldCell','Update-PestoSuiteLayout')){. ([scriptblock]::Create($defs[$name]))}
   $script:SuiteUI=@{}
   foreach($node in $shell.SelectNodes('//*[@*[local-name()="Name"]]')){$name=$node.GetAttribute('Name','http://schemas.microsoft.com/winfx/2006/xaml');$control=$Win.FindName($name);if($control){$script:SuiteUI[$name]=$control}}
   $script:SidebarWidth=$Win.FindName('SidebarWidth');$script:SuiteReady=$true;$script:HelpVisible=$false;$script:NavigationCollapsed=$false
   $banner=$Win.FindName('PestoBlockBanner');$banner.Text='Une intervention attend une vérification.';$banner.Visibility='Visible'
   $stages=$Win.FindName('PestoStageDetails');$stages.Visibility='Visible';$stages.IsExpanded=$true
   $warning=$Win.FindName('PestoPersistenceWarning');$warning.Text='Préférences non enregistrées.';$warning.Visibility='Visible'
   try{
    foreach($size in @(@(1920,1200),@(1024,768),@(760,560),@(1920,1200))){foreach($percent in @(80,100,150)){
     Set-PestoUiZoom -Percent $percent;Arrange-ZoomCanvas $size[0] $size[1];Update-PestoSuiteLayout;Arrange-ZoomCanvas $size[0] $size[1]
     $tools=$Win.FindName('SuiteHeaderTools');$header=$tools.Parent
     $toolsPoint=$tools.TranslatePoint([Windows.Point]::new(0,0),$header)
     $noticePoint=$banner.Parent.TranslatePoint([Windows.Point]::new(0,0),$header)
     $warningPoint=$warning.TranslatePoint([Windows.Point]::new(0,0),$header)
     $context=('{0}x{1} / {2}%' -f $size[0],$size[1],$percent)
     Assert-Zoom ($noticePoint.Y -ge $toolsPoint.Y+$tools.ActualHeight-1) ('Operation notices overlap toolbar: '+$context)
     Assert-Zoom ($warningPoint.Y -ge $noticePoint.Y+$banner.Parent.ActualHeight-1) ('Persistence notice overlaps operation: '+$context)
    }}
   }finally{$script:SuiteReady=$false;$banner.Visibility='Collapsed';$stages.Visibility='Collapsed';$warning.Visibility='Collapsed'}
  }
  Case-Zoom 'WPF: real Save-Prefs stores zoom with the existing layout and reloads it' {
   $script:ZoomStoreWrites=0;$script:NavigationCollapsed=$true;$script:LogFontSize=16
   Set-PestoUiZoom -Percent 140 -Persist
   Equal-Zoom $script:ZoomStoreWrites 1
   $stored=$script:ZoomStore.Layout|ConvertFrom-Json;Equal-Zoom $stored.UiZoomPercent 140;Assert-Zoom $stored.NavigationCollapsed;Equal-Zoom $stored.LogFontSize 16
   $script:PestoUiZoomPercent=100
   Initialize-PestoAppearance -OwnerSid 'S-1-5-21-1-2-3-1001' -Config ([pscustomobject]@{Conf=@([pscustomobject]@{DarkMode=0})})
   Equal-Zoom $script:PestoUiZoomPercent 140;Equal-Zoom $script:ZoomStoreWrites 1
  }
  Case-Zoom 'WPF: storage failure keeps applied zoom and surfaces a persistence warning' {
   $script:ZoomStoreFail=$true;$script:ZoomWarning=''
   try{Set-PestoUiZoom -Percent 110 -Persist;Equal-Zoom $script:PestoUiZoomPercent 110;Assert-Zoom $script:ZoomWarning}finally{$script:ZoomStoreFail=$false}
  }
 }finally{if($script:Win){$script:Win.Close();$script:Win=$null}}
}
$failed=@($results|Where-Object{-not $_.Passed}).Count
$report=[pscustomobject]@{PowerShell=[string]$PSVersionTable.PSVersion;WindowsWpfRequested=[bool]$Wpf;WindowShown=$false;NoAD=$true;NoRegistry=$true;Failed=$failed;Checks=$results.ToArray()}
if($ReportPath){$report|ConvertTo-Json -Depth 7|Set-Content -LiteralPath $ReportPath -Encoding UTF8}
$report|ConvertTo-Json -Depth 7
if($failed){exit 1}
