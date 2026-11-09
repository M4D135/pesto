#requires -Version 5.1
[CmdletBinding()]
param([switch]$Wpf,[string]$ReportPath='')
# AST et contrôles isolés : aucun démarrage de Pesto, AD, registre ou écriture de configuration.
$ErrorActionPreference='Stop';Set-StrictMode -Off
$root=Split-Path $PSScriptRoot -Parent;$defs=@{};$results=[Collections.Generic.List[object]]::new()
foreach($file in @('Pesto-Core.ps1','Pesto-SuiteUI.ps1','Pesto-Workspace.ps1','Pesto-Workbench.ps1','Pesto-Interventions.ps1','Pesto-Contracts.ps1')){
 $tokens=$null;$parseErrors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root ('wad/'+$file)),[ref]$tokens,[ref]$parseErrors)
 if($parseErrors.Count){throw ($parseErrors.Message -join '; ')}
 foreach($node in $ast.EndBlock.Statements){if($node -is [Management.Automation.Language.FunctionDefinitionAst]){$defs[$node.Name]=$node.Extent.Text}}
}
foreach($name in @('Invoke-PestoUxPageChanged','Get-PestoPaletteChoices','Find-PestoCommands','Get-PestoCommandMatches','ConvertTo-PestoSearchText','Get-PestoWorkspaceCommands','Invoke-PestoPaletteCategory','Invoke-PestoPaletteSearch')){
 if(-not $defs.ContainsKey($name)){throw ('Fonction absente : '+$name)};. ([scriptblock]::Create($defs[$name]))
}
function Assert-Tabs {param($Condition,[string]$Message='Assertion onglets non satisfaite.');if(-not $Condition){throw $Message}}
function Equal-Tabs {param($Actual,$Expected);if($Actual -ne $Expected){throw ('Attendu '+$Expected+', obtenu '+$Actual)}}
function Case-Tabs {param([string]$Name,[scriptblock]$Body);try{& $Body;$results.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''})}catch{$results.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message})}}
function Named-Tabs {param($Xml,[string]$Name);$Xml.SelectSingleNode('//*[@*[local-name()="Name"]="'+$Name+'"]')}
function Within-Tabs {param($Xml,[string]$Name,[string]$Ancestor);$target=Named-Tabs $Xml $Ancestor;$node=Named-Tabs $Xml $Name;if(-not $target -or -not $node){return $false};while($node.ParentNode){$node=$node.ParentNode;if($node -eq $target){return $true}};$false}
function Get-TabsXaml {param([string]$Function,[string]$Tag);$match=[regex]::Match($defs[$Function],'(?s)\[xml\]\$x=@''\r?\n(.*?)\r?\n''@');if(-not $match.Success){throw ('XAML absent de '+$Function)};[xml]$match.Groups[1].Value}
function Sync-PestoUxNavigation {$script:TabsNavCalls++}
function Request-PestoUxRefresh {$script:TabsRefreshCalls++}
function Request-PestoPageAutomationRefresh {$script:TabsAutomationCalls++}
function Get-PestoUxNom {param($Key);$Key}
[xml]$shell=Get-Content -LiteralPath (Join-Path $root 'wad/Pesto-Shell.xaml') -Raw -Encoding UTF8
[xml]$ledger=Get-TabsXaml 'Show-PestoInterventions' 'Window'
[xml]$palette=Get-TabsXaml 'Show-PestoPanel' 'Grid'
Case-Tabs 'Main navigation preserves all eight page indices' {$headers=@((Named-Tabs $shell 'MainTabs').SelectNodes('./*[local-name()="TabItem"]')|ForEach-Object{$_.Header});Equal-Tabs ($headers -join '|') 'Renommer|Noms disponibles|Paramètres|Journal|Accueil|Historique|Aide|Ajouter au domaine'}
Case-Tabs 'Nested SelectionChanged cannot trigger global navigation or refresh' {
 $script:TabsNavCalls=0;$script:TabsRefreshCalls=0;$script:TabsAutomationCalls=0;$script:MainTabs=[pscustomobject]@{Name='MainTabs';SelectedIndex=0}
 foreach($name in @('QueueToolTabs','LedgerToolTabs','SetTabs','PanelCategories')){Invoke-PestoUxPageChanged $MainTabs ([pscustomobject]@{OriginalSource=[pscustomobject]@{Name=$name}})}
 Equal-Tabs $script:TabsNavCalls 0;Equal-Tabs $script:TabsRefreshCalls 0;Equal-Tabs $script:TabsAutomationCalls 0
}
Case-Tabs 'An actual main-page selection refreshes navigation once' {$script:TabsNavCalls=0;$script:TabsRefreshCalls=0;$script:TabsAutomationCalls=0;Invoke-PestoUxPageChanged $MainTabs ([pscustomobject]@{OriginalSource=$MainTabs});Equal-Tabs $script:TabsNavCalls 1;Equal-Tabs $script:TabsRefreshCalls 1;Equal-Tabs $script:TabsAutomationCalls 1}
Case-Tabs 'Accessibility refresh reuses existing peers without polling, focus or peer creation' {
 foreach($name in @('Request-PestoPageAutomationRefresh','Update-PestoPageAutomationPeers')){Assert-Tabs $defs[$name];Assert-Tabs ($defs[$name] -notmatch '(?i)CreatePeerForElement|DispatcherTimer|\.Focus\(');Assert-Tabs ($defs[$name] -match 'FromElement')}
 Assert-Tabs ($defs['Request-PestoPageAutomationRefresh'] -match 'PestoPageAutomationPending' -and $defs['Request-PestoPageAutomationRefresh'] -match 'BeginInvoke')
 Assert-Tabs ($defs['Update-PestoPageAutomationPeers'] -match 'ResetChildrenCache')
}
Case-Tabs 'Queue tools use File, import/export and follow-up tabs' {$tabs=Named-Tabs $shell 'QueueToolTabs';Assert-Tabs ($tabs.LocalName -eq 'TabControl');Equal-Tabs ((@($tabs.SelectNodes('./*[local-name()="TabItem"]')|ForEach-Object{$_.Header})) -join '|') 'File|Import et export|Suivi'}
Case-Tabs 'Queue tools preserve every existing action control exactly once' {foreach($name in @('BtnEdit','BtnImport','BtnExport','BtnHtmlReport','BtnHistory','BtnRetryMove','BtnClear')){Assert-Tabs (Within-Tabs $shell $name 'QueueToolTabs') $name;Equal-Tabs @($shell.SelectNodes('//*[@*[local-name()="Name"]="'+$name+'"]')).Count 1}}
Case-Tabs 'Batch execute and selection commands remain outside tool tabs' {foreach($name in @('BtnRun','BtnCheckAll','BtnUncheckAll')){Assert-Tabs (Named-Tabs $shell $name);Assert-Tabs (-not(Within-Tabs $shell $name 'QueueToolTabs')) $name}}
Case-Tabs 'Intervention tools use Consulter, Entretien and Donnees tabs' {$tabs=Named-Tabs $ledger 'LedgerToolTabs';Assert-Tabs ($tabs.LocalName -eq 'TabControl');Equal-Tabs ((@($tabs.SelectNodes('./*[local-name()="TabItem"]')|ForEach-Object{$_.Header})) -join '|') 'Consulter|Entretien|Données'}
Case-Tabs 'Observe and report actions stay outside intervention tool tabs' {foreach($name in @('LedgerObserve','LedgerReport','LedgerRedact')){Assert-Tabs (Named-Tabs $ledger $name);Assert-Tabs (-not(Within-Tabs $ledger $name 'LedgerToolTabs')) $name};Equal-Tabs (Named-Tabs $ledger 'LedgerRedact').IsChecked 'True'}
Case-Tabs 'Intervention table and tools scroll while all final actions remain outside' {
 foreach($name in @('LedgerGrid','LedgerTools')){Assert-Tabs (Within-Tabs $ledger $name 'LedgerPageScroll') $name}
 foreach($name in @('LedgerObserve','LedgerReport','LedgerRedact','LedgerClose')){Assert-Tabs (Named-Tabs $ledger $name) $name;Assert-Tabs (-not(Within-Tabs $ledger $name 'LedgerPageScroll')) $name}
 $grid=Named-Tabs $ledger 'LedgerGrid';Assert-Tabs ([double]$grid.MinHeight -ge 180 -and [double]$grid.Height -le 400);Equal-Tabs $grid.EnableRowVirtualization 'True'
}
Case-Tabs 'Settings preserves old tab order and appends Fichiers' {$headers=@((Named-Tabs $shell 'SetTabs').SelectNodes('./*[local-name()="TabItem"]')|ForEach-Object{$_.Header});Equal-Tabs ($headers -join '|') 'Apparence|Domaine|Noms et coordination|Politique|Tags|OU & organismes|Options avancées|Fichiers'}
Case-Tabs 'Config file actions remain explicit and are grouped in Fichiers' {foreach($name in @('SetBtnConfigImport','SetBtnConfigExport','SetBtnConfigRestore')){Assert-Tabs (Within-Tabs $shell $name 'SetTabFiles') $name}}
Case-Tabs 'Journal search and refresh stay visible outside display options' {foreach($name in @('SuiteLogSearch','SuiteLogRefresh')){Assert-Tabs (Named-Tabs $shell $name);Assert-Tabs (-not(Within-Tabs $shell $name 'SuiteLogOptions')) $name};foreach($name in @('SuiteLogFollow','SuiteLogWrap','SuiteLogMinus','SuiteLogPlus')){Assert-Tabs (Within-Tabs $shell $name 'SuiteLogOptions') $name}}
Case-Tabs 'Name tools are divided into preparation, inventory and options' {$tabs=Named-Tabs $shell 'NmToolTabs';Assert-Tabs ($tabs.LocalName -eq 'TabControl');Equal-Tabs ((@($tabs.SelectNodes('./*[local-name()="TabItem"]')|ForEach-Object{$_.Header})) -join '|') 'Préparation|Inventaire|Options';Assert-Tabs (Within-Tabs $shell 'NmToolTabs' 'NmExtraTools')}
Case-Tabs 'Name candidates and pagination remain outside the secondary tabs' {foreach($name in @('NmPrevPage','NmNextPage','NmOtherNames','NmVerifyCandidate','NmUseCandidate','NmBtnNextP','NmBtnNextS','NmBtnNextV')){Assert-Tabs (Named-Tabs $shell $name);Assert-Tabs (-not(Within-Tabs $shell $name 'NmToolTabs')) $name}}
Case-Tabs 'Name secondary actions preserve their control identities' {foreach($name in @('NmHoldCandidates','NmReleaseCandidate','NmBtnCopy','NmBtnExport','NmBtnRefresh','NmStrategy','NmServiceInput','NmAddService')){Assert-Tabs (Within-Tabs $shell $name 'NmToolTabs') $name}}
Case-Tabs 'Palette category tabs have stable identifiers' {foreach($name in @('PanelCategories','PanelCategoryPostes','PanelCategoryPreparer','PanelCategoryAnalyser','PanelCategoryAffichage')){Assert-Tabs (Named-Tabs $palette $name) $name}}
Case-Tabs 'Every workspace command has one valid category and a unique action id' {$commands=@(Get-PestoWorkspaceCommands);Assert-Tabs ($commands.Count -gt 10);Equal-Tabs (@($commands|Group-Object Id|Where-Object{$_.Count -gt 1}).Count) 0;foreach($c in $commands){Assert-Tabs ($c.Category -in @('Postes','Preparer','Analyser','Affichage')) $c.Id}}
$commands=@(
 [pscustomobject]@{Id='single';Label='Préparer un poste';Detail='Renommer';Category='Postes'},
 [pscustomobject]@{Id='draft';Label='Exporter un dossier';Detail='Préparation hors ligne';Category='Preparer'},
 [pscustomobject]@{Id='perf';Label='Mesures de performance';Detail='Analyse locale';Category='Analyser'},
 [pscustomobject]@{Id='density';Label='Densité';Detail='Confort ou compact';Category='Affichage'}
)
Case-Tabs 'Empty search restricts choices to the selected category' {foreach($category in @('Postes','Preparer','Analyser','Affichage')){$found=@(Get-PestoPaletteChoices -Commands $commands -Query '' -Category $category);Equal-Tabs $found.Count 1;Equal-Tabs $found[0].Category $category}}
Case-Tabs 'Whitespace search uses the selected category' {$found=@(Get-PestoPaletteChoices -Commands $commands -Query '   ' -Category 'Affichage');Equal-Tabs $found.Count 1;Equal-Tabs $found[0].Id 'density'}
Case-Tabs 'Typing searches globally even when another category is selected' {$found=@(Get-PestoPaletteChoices -Commands $commands -Query 'performance' -Category 'Postes');Equal-Tabs $found.Count 1;Equal-Tabs $found[0].Id 'perf'}
Case-Tabs 'Global search remains accent and case insensitive' {$found=@(Get-PestoPaletteChoices -Commands $commands -Query 'DENSITE' -Category 'Postes');Equal-Tabs $found.Count 1;Equal-Tabs $found[0].Id 'density'}
Case-Tabs 'No match returns no command without a fallback selection' {Equal-Tabs @(Get-PestoPaletteChoices -Commands $commands -Query 'introuvable' -Category 'Postes').Count 0}
Case-Tabs 'Category filtering retains command identity and does not rewrite the source list' {$before=$commands|ConvertTo-Json -Compress;$found=@(Get-PestoPaletteChoices -Commands $commands -Query '' -Category 'Preparer');Assert-Tabs ([object]::ReferenceEquals($found[0],$commands[1]));Equal-Tabs ($commands|ConvertTo-Json -Compress) $before}
Case-Tabs 'Category handler cannot execute a workspace action' {Assert-Tabs ($defs['Invoke-PestoPaletteCategory'] -notmatch '(?i)\b(Invoke-PestoWorkspaceAction|Invoke-PestoPanelButton|Add-Computer|Rename-Computer|Save-Cfg)\b');Assert-Tabs ($defs['Invoke-PestoPaletteCategory'] -match 'Invoke-PestoPaletteSearch')}
function New-TabsPaletteState {
 $s=[pscustomobject]@{Searchable=$true;AllChoices=$commands;Search=[pscustomobject]@{Text='performance';Tag=$null};Choices=[pscustomobject]@{SelectedItem=$null;SelectedIndex=-1;ItemsSource=@()};Categories=[pscustomobject]@{Visibility='Visible';SelectedItem=[pscustomobject]@{Tag='Affichage';Header='Affichage'};Tag=$null};Accept=[pscustomobject]@{IsEnabled=$false};Hint=[pscustomobject]@{Text=''}}
 $s.Search.Tag=$s;$s.Categories.Tag=$s;return $s
}
function Invoke-PestoWorkspaceAction {throw "Une sélection d’onglet ne doit pas lancer de commande."}
Case-Tabs 'Choosing a palette category clears search and only filters choices' {$s=New-TabsPaletteState;Invoke-PestoPaletteCategory $s.Categories ([pscustomobject]@{OriginalSource=$s.Categories});Equal-Tabs $s.Search.Text '';Equal-Tabs @($s.Choices.ItemsSource).Count 1;Equal-Tabs $s.Choices.ItemsSource[0].Id 'density';Assert-Tabs $s.Accept.IsEnabled}
Case-Tabs 'A nested selection cannot clear the palette search or category' {$s=New-TabsPaletteState;Invoke-PestoPaletteCategory $s.Categories ([pscustomobject]@{OriginalSource=[pscustomobject]@{Name='PanelChoices'}});Equal-Tabs $s.Search.Text 'performance';Equal-Tabs @($s.Choices.ItemsSource).Count 0}

if($Wpf){
 if($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){throw '-Wpf exige Windows PowerShell 5.1.'}
 if([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA'){throw '-Wpf exige -STA.'}
 Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
 $script:ToolsTestWindow=$null;$script:ToolsTestLedger=$null
 try{
  Case-Tabs 'WPF: all three real XAML trees load with the new tabs' {
   $script:ToolsTestWindow=[Windows.Markup.XamlReader]::Parse($shell.OuterXml)
   $script:ToolsTestLedger=[Windows.Markup.XamlReader]::Parse($ledger.OuterXml);$script:ToolsTestLedger.Resources=$script:ToolsTestWindow.Resources
   $script:ToolsTestPalette=[Windows.Markup.XamlReader]::Parse($palette.OuterXml);$script:ToolsTestPalette.Resources=$script:ToolsTestWindow.Resources
   Equal-Tabs $script:ToolsTestWindow.FindName('QueueToolTabs').Items.Count 3;Equal-Tabs $script:ToolsTestLedger.FindName('LedgerToolTabs').Items.Count 3
   Equal-Tabs $script:ToolsTestWindow.FindName('SetTabs').Items.Count 8;Equal-Tabs $script:ToolsTestPalette.FindName('PanelCategories').Items.Count 4
  }
  Case-Tabs 'WPF: switching settings tabs preserves typed draft and the same controls' {
   $tabs=$script:ToolsTestWindow.FindName('SetTabs');$field=$script:ToolsTestWindow.FindName('SetTxtDomaine');$field.Text='draft.example.test'
   $button=$script:ToolsTestWindow.FindName('SetBtnConfigImport');$button.IsEnabled=$false
   foreach($n in @(0,7,1,7,0)){$tabs.SelectedIndex=$n;Assert-Tabs ([object]::ReferenceEquals($field,$script:ToolsTestWindow.FindName('SetTxtDomaine')));Equal-Tabs $field.Text 'draft.example.test';Assert-Tabs ([object]::ReferenceEquals($button,$script:ToolsTestWindow.FindName('SetBtnConfigImport')));Assert-Tabs (-not $button.IsEnabled)}
  }
  Case-Tabs 'WPF: nested queue selection does not change main page or trigger its refresh' {
   $script:MainTabs=$script:ToolsTestWindow.FindName('MainTabs');$MainTabs.SelectedIndex=0
   $script:TabsNavCalls=0;$script:TabsRefreshCalls=0;$script:TabsAutomationCalls=0
   $handler=[Windows.Controls.SelectionChangedEventHandler]${function:Invoke-PestoUxPageChanged};$MainTabs.Add_SelectionChanged($handler)
   try{
    $tabs=$script:ToolsTestWindow.FindName('QueueToolTabs');$run=$script:ToolsTestWindow.FindName('BtnRun');$run.IsEnabled=$false
    foreach($n in @(1,2,0,2)){$tabs.SelectedIndex=$n;Equal-Tabs $MainTabs.SelectedIndex 0;Assert-Tabs ([object]::ReferenceEquals($run,$script:ToolsTestWindow.FindName('BtnRun')));Assert-Tabs (-not $run.IsEnabled)}
    Equal-Tabs $script:TabsNavCalls 0;Equal-Tabs $script:TabsRefreshCalls 0;Equal-Tabs $script:TabsAutomationCalls 0
   }finally{$MainTabs.Remove_SelectionChanged($handler)}
  }
  Case-Tabs 'WPF: real palette tabs filter and preserve explicit activation' {
   $panel=$script:ToolsTestPalette;$category=$panel.FindName('PanelCategories');$search=$panel.FindName('PanelSearch');$choices=$panel.FindName('PanelChoices');$accept=$panel.FindName('PanelAccept')
   $category.Visibility='Visible';$category.SelectedIndex=0
   $state=[pscustomobject]@{Searchable=$true;AllChoices=$commands;Categories=$category;Search=$search;Choices=$choices;Accept=$accept;Hint=$panel.FindName('PanelHint')};$category.Tag=$state;$search.Tag=$state
   $categoryHandler=[Windows.Controls.SelectionChangedEventHandler]${function:Invoke-PestoPaletteCategory};$searchHandler=[Windows.Controls.TextChangedEventHandler]${function:Invoke-PestoPaletteSearch}
   $category.Add_SelectionChanged($categoryHandler);$search.Add_TextChanged($searchHandler)
   try{
    $search.Text='DENSITE';Equal-Tabs $choices.Items.Count 1;Equal-Tabs $choices.SelectedItem.Id 'density';Assert-Tabs $accept.IsEnabled
    $category.SelectedIndex=2;Equal-Tabs $search.Text '';Equal-Tabs $choices.Items.Count 1;Equal-Tabs $choices.SelectedItem.Id 'perf'
    $search.Text='introuvable';Equal-Tabs $choices.Items.Count 0;Equal-Tabs $choices.SelectedIndex -1;Assert-Tabs (-not $accept.IsEnabled)
   }finally{$category.Remove_SelectionChanged($categoryHandler);$search.Remove_TextChanged($searchHandler)}
  }
  Case-Tabs 'WPF: intervention tool tabs preserve selection and redaction' {
   $tabs=$script:ToolsTestLedger.FindName('LedgerToolTabs');$grid=$script:ToolsTestLedger.FindName('LedgerGrid');$redact=$script:ToolsTestLedger.FindName('LedgerRedact')
   $rows=@([pscustomobject]@{Computer='PC-ONE'},[pscustomobject]@{Computer='PC-TWO'});$grid.ItemsSource=$rows;$grid.SelectedItem=$rows[1]
   Assert-Tabs $redact.IsChecked;$observe=$script:ToolsTestLedger.FindName('LedgerObserve');$observe.IsEnabled=$false
   foreach($n in @(1,2,0,2)){$tabs.SelectedIndex=$n;Assert-Tabs ([object]::ReferenceEquals($grid.SelectedItem,$rows[1]));Assert-Tabs $redact.IsChecked;Assert-Tabs (-not $observe.IsEnabled)}
  }
  Case-Tabs 'WPF: intervention grid and tools remain reachable at 600 by 400 with a fixed footer' {
   $w=$script:ToolsTestLedger;$body=$w.Content;$grid=$w.FindName('LedgerGrid');$tools=$w.FindName('LedgerTools');$tools.IsExpanded=$true
   $grid.ItemsSource=@(1..20|ForEach-Object{[pscustomobject]@{Computer=('PC-'+$_);StatusLabel='Vérifié';UpdatedLocal='13/10/2026'}})
   for($n=0;$n -lt 3;$n++){$body.Measure([Windows.Size]::new(600,400));$body.Arrange([Windows.Rect]::new(0,0,600,400));$body.UpdateLayout()}
   Assert-Tabs ($grid.ActualHeight -ge 180 -and $grid.ActualHeight -le 400) ('Grille interventions écrasée : '+$grid.ActualHeight)
   $page=$w.FindName('LedgerPageScroll');Assert-Tabs ($page.ScrollableHeight -gt 0)
   $tools.BringIntoView();$body.UpdateLayout()
   $position=$tools.TranslatePoint([Windows.Point]::new(0,0),$page)
   Assert-Tabs ($position.Y -lt $page.ActualHeight -and $position.Y+$tools.ActualHeight -gt 0) 'Outils hors défilement accessible.'
   foreach($name in @('LedgerObserve','LedgerReport','LedgerRedact','LedgerClose')){
    $control=$w.FindName($name);Assert-Tabs $control $name;$p=$control.TranslatePoint([Windows.Point]::new(0,0),$body)
    Assert-Tabs ($control.ActualHeight -gt 0 -and $control.ActualWidth -gt 0) $name
    Assert-Tabs ($p.X -ge 0 -and $p.Y -ge 0 -and $p.X+$control.ActualWidth -le 600.5 -and $p.Y+$control.ActualHeight -le 400.5) ('Pied hors fenêtre : '+$name+' '+$p)
   }
  }
 }finally{if($script:ToolsTestWindow){$script:ToolsTestWindow.Close()};if($script:ToolsTestLedger){$script:ToolsTestLedger.Close()}}
}
$failed=@($results|Where-Object{-not $_.Passed}).Count
$report=[pscustomobject]@{PowerShell=[string]$PSVersionTable.PSVersion;WindowsWpfRequested=[bool]$Wpf;WindowShown=$false;NoAD=$true;NoRegistry=$true;NoApplicationStartup=$true;Failed=$failed;Checks=$results.ToArray()}
if($ReportPath){$report|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $ReportPath -Encoding UTF8}
$report|ConvertTo-Json -Depth 6
if($failed){exit 1}
