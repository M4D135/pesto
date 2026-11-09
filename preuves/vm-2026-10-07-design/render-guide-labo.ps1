#requires -Version 5.1
[CmdletBinding()]
param([string]$ReportPath='')
# Windows PowerShell 5.1 : $PSScriptRoot est vide dans les valeurs par défaut des paramètres (vu le 03/10).
if(-not $ReportPath){$ReportPath=Join-Path $PSScriptRoot 'windows-ui-results.json'}
$ErrorActionPreference='Stop'
Set-StrictMode -Off
if($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5 -or -not [Environment]::Is64BitProcess){throw 'Tests interface : Windows PowerShell 5.1 x64 requis.'}
if([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA'){throw 'Exécuter cette suite avec powershell.exe -STA.'}
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Xml,System.Data
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$path=Join-Path $root 'wad\Pesto-Core.ps1'
# Fenêtre principale dans Pesto-Shell.xaml, chargée comme le fait le moteur (Get-Content puis [xml]).
$shellPath=Join-Path $root 'wad\Pesto-Shell.xaml'
$source=Get-Content -LiteralPath $path -Raw -Encoding UTF8
$results=[Collections.Generic.List[object]]::new()
$script:UiErrors=[Collections.Generic.List[string]]::new()
$script:ForbiddenCalls=0;$script:SourceReads=0;$script:PrefsWrites=0
$temp=Join-Path ([IO.Path]::GetTempPath()) ('Pesto-UI-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
function Assert-True {param($Condition,[string]$Message='Assertion non satisfaite.');if(-not $Condition){throw $Message}}
function Equal {param($Actual,$Expected);if($Actual -ne $Expected){throw "Attendu : '$Expected', obtenu : '$Actual'."}}
function Case {param([string]$Name,[scriptblock]$Body)
    try{& $Body;$results.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''});Write-Host "OK  $Name"}
    catch{$results.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message});Write-Host "KO  $Name : $($_.Exception.Message)"}
}
# Palettes : même méthode que Run-LoginTests.ps1. $script:Themes est lu dans l'arbre du parseur,
# sans évaluation ; seules des tables imbriquées de chaînes '#RRGGBB' ou '#AARRGGBB' sont acceptées.
function Get-LiteralExpression {
    param([Management.Automation.Language.Ast]$Node)
    if($Node -is [Management.Automation.Language.PipelineAst]){return $Node.GetPureExpression()}
    if($Node -is [Management.Automation.Language.CommandExpressionAst]){return $Node.Expression}
    return $Node
}
function Get-LiteralKey {
    param([Management.Automation.Language.Ast]$Node,[string]$Where)
    if(-not($Node -is [Management.Automation.Language.StringConstantExpressionAst]) -or -not $Node.Value){
        throw ('Clé non littérale dans '+$Where+' : '+$Node.Extent.Text)
    }
    return [string]$Node.Value
}
function Read-ThemePalettes {
    param([Management.Automation.Language.Ast]$Ast,[string]$Where)
    $themeNodes=@($Ast.FindAll({
        param($Candidate)
        ($Candidate -is [Management.Automation.Language.AssignmentStatementAst]) -and
        ([string]$Candidate.Operator -eq 'Equals') -and
        ($Candidate.Left -is [Management.Automation.Language.VariableExpressionAst]) -and
        ($Candidate.Left.VariablePath.UserPath -eq 'script:Themes' -or $Candidate.Left.Extent.Text -eq '$script:Themes')
    },$true))
    if($themeNodes.Count -ne 1){throw ('Affectation $script:Themes introuvable ou ambiguë dans '+$Where+' ('+$themeNodes.Count+').')}
    $themeTable=Get-LiteralExpression $themeNodes[0].Right
    if(-not($themeTable -is [Management.Automation.Language.HashtableAst])){throw 'Palettes non littérales : aucune évaluation du moteur.'}
    $found=@{}
    foreach($themePair in $themeTable.KeyValuePairs){
        $themeName=Get-LiteralKey $themePair.Item1 '$script:Themes'
        $colorTable=Get-LiteralExpression $themePair.Item2
        if(-not($colorTable -is [Management.Automation.Language.HashtableAst])){throw ('Palette non littérale : '+$themeName)}
        $colors=@{}
        foreach($colorPair in $colorTable.KeyValuePairs){
            $colorKey=Get-LiteralKey $colorPair.Item1 $themeName
            $colorValue=Get-LiteralExpression $colorPair.Item2
            if(-not($colorValue -is [Management.Automation.Language.StringConstantExpressionAst]) -or
               -not [regex]::IsMatch([string]$colorValue.Value,'\A#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})\z')){
                throw ('Couleur non littérale ou invalide : '+$themeName+'.'+$colorKey)
            }
            if($colors.ContainsKey($colorKey)){throw ('Couleur dupliquée : '+$themeName+'.'+$colorKey)}
            $colors[$colorKey]=[string]$colorValue.Value
        }
        if($found.ContainsKey($themeName)){throw ('Palette dupliquée : '+$themeName)}
        $found[$themeName]=$colors
    }
    foreach($required in @('Light','Dark')){
        if(-not $found.ContainsKey($required) -or $found[$required].Count -lt 1){throw ('Palette absente : '+$required)}
    }
    # Une clé absente d'un thème laisserait le pinceau Light du Shell en place, sans erreur WPF.
    $lightKeys=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($colorKey in $found['Light'].Keys){[void]$lightKeys.Add([string]$colorKey)}
    $darkKeys=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($colorKey in $found['Dark'].Keys){[void]$darkKeys.Add([string]$colorKey)}
    if(-not $lightKeys.SetEquals($darkKeys)){throw 'Palettes Light et Dark incohérentes.'}
    return $found
}
function Assert-Palette {
    # Chaque couleur de la palette doit être le pinceau effectif de la fenêtre après Set-Theme.
    param([string]$Name)
    $palette=$script:Themes[$Name]
    Assert-True ($palette -and $palette.Count -gt 0) ('Palette absente : '+$Name)
    foreach($paletteKey in $palette.Keys){
        $expected=([Windows.Media.Color][Windows.Media.ColorConverter]::ConvertFromString([string]$palette[$paletteKey])).ToString()
        $brush=$Win.Resources[$paletteKey]
        if(-not($brush -is [Windows.Media.SolidColorBrush]) -or $brush.Color.ToString() -ne $expected){
            throw ($Name+'.'+$paletteKey+' : attendu '+$expected+', obtenu '+[string]$brush)
        }
    }
}
# Moteur et composants qu'il dot-source : lus comme texte, puis analysés par le parseur. Rien n'est exécuté.
$engineFiles=[Collections.Generic.List[string]]::new();$engineFiles.Add('Pesto-Core.ps1')
foreach($componentHit in [regex]::Matches($source,'(?m)^[ \t]*\.[ \t]+\(Join-Path[ \t]+\$PSScriptRoot[ \t]+''(Pesto-[A-Za-z]+\.ps1)''\)')){
    $componentName=$componentHit.Groups[1].Value
    if(-not $engineFiles.Contains($componentName)){$engineFiles.Add($componentName)}
}
$engineAst=@{};$parseIssues=[Collections.Generic.List[string]]::new()
$defs=@{};$defFiles=@{}
foreach($engineFile in $engineFiles){
    $engineText=if($engineFile -eq 'Pesto-Core.ps1'){$source}else{Get-Content -LiteralPath (Join-Path $root ('wad\'+$engineFile)) -Raw -Encoding UTF8}
    $engineTokens=$null;$engineErrors=$null
    $engineAst[$engineFile]=[Management.Automation.Language.Parser]::ParseInput($engineText,[ref]$engineTokens,[ref]$engineErrors)
    foreach($engineError in $engineErrors){$parseIssues.Add($engineFile+' : '+$engineError.Message)}
    foreach($d in $engineAst[$engineFile].EndBlock.Statements){
        if($d -is [Management.Automation.Language.FunctionDefinitionAst]){
            if($defs.ContainsKey($d.Name)){$parseIssues.Add('Fonction définie deux fois : '+$d.Name+' ('+$defFiles[$d.Name]+', '+$engineFile+')')}
            else{$defs[$d.Name]=$d;$defFiles[$d.Name]=$engineFile}
        }
    }
}
Case 'Parseur PowerShell natif du moteur et de ses composants' {Assert-True ($parseIssues.Count -eq 0) ($parseIssues -join '; ')}
if($parseIssues.Count){throw 'Le moteur ne peut pas être parsé sans ambiguïté. Aucun chargement de Pesto.'}
# Seules les définitions ci-dessous sont chargées. Le corps de Pesto n'est JAMAIS exécuté.
$load=@('Test-PestoDnsName','Get-PestoDomainFromDN','Test-PestoDNWithinScope','Test-PestoComputerName','Test-PestoGeneratedComputerName','Test-PestoOUPath','Split-PestoDistinguishedName','Get-PestoNameSiteCode','Get-PestoSiteContainerDN','Get-PestoRenameMoveDecision',
 'ConvertTo-PestoNameParts','Format-PestoOUForDisplay','Sync-PestoAppearanceControls','Set-PestoSuiteMode','Set-PestoSuiteHelp',
 'Get-PestoUxSnapshot','New-QueueTable','Format-OUPath','New-Brush','New-ThemeIcon','Set-Theme','Set-OULabel','Reset-ConfigFields','Update-FieldColor',
 'Request-PestoUxRefresh','Invoke-PestoUxRefreshTick','Invoke-PestoUxInputChanged','Update-PestoUx','Update-PestoUxLayout','Invoke-PestoUxSizeChanged',
 'Set-PestoUxPage','Sync-PestoUxNavigation','Invoke-PestoUxNavigate','Invoke-PestoUxPageChanged','Update-PestoUxHistory','Invoke-PestoUxHistoryRefresh',
 'Set-PestoUxTechnicalColumns','Invoke-PestoUxTechnicalChanged','Invoke-PestoUxCopyName','Request-PestoUxComputerLookup','Invoke-PestoUxComputerLookupTick',
 'Invoke-PestoUxReadComputer','Invoke-PestoUxSourceKey','Invoke-PestoUxKey','Initialize-PestoUx','Stop-PestoUx','Invoke-DoEvents','ConvertTo-PestoHighContrastPalette')
foreach($name in $load){if(-not $defs.ContainsKey($name)){throw "Fonction requise absente : $name"};. ([scriptblock]::Create($defs[$name].Extent.Text))}
# Doubles explicitement isolés : pas de compte, pas de module AD et pas de moteur.
function Test-PestoAsyncOperationRunning {param([string]$Name);return $false}
function Stop-PestoAsyncOperation {param([string]$Name)}
function Test-PestoGlobalSafetyBarrier {return [bool]$script:MutationUncertain}
function Select-PCName {$script:SourceReads++}
function Save-Prefs {$script:PrefsWrites++}
function Restyle-Chips {}
function Render-Log {}
function Update-NameGrid {}
function Update-PestoJoinUI {}
function Request-PestoJoinInventory {$script:JoinInventoryRequests++}
# Bandeau de suite non initialisé ($script:SuiteReady=$false) : les fonctions réelles ne feraient rien ici.
function Update-PestoSuiteUI {}
function Update-PestoSuiteLayout {}
function Write-Log {param($Message,$Level,$ErrorObject,$Area);if($Level -eq 'ERROR'){$script:UiErrors.Add([string]$Message)}}
function Show-MsgWarning {param($Message);throw "Dialogue inattendu : $Message"}
function Show-MsgInfo {param($Message);throw "Dialogue inattendu : $Message"}
function Show-PestoTextReport {param($Title,$Text)}
function Get-PestoStateDirectory {return $temp}
function Rename-Computer {$script:ForbiddenCalls++;throw 'Mutation interdite dans cette suite.'}
function Add-Computer {$script:ForbiddenCalls++;throw 'Mutation interdite dans cette suite.'}
function Move-ADObject {$script:ForbiddenCalls++;throw 'Mutation interdite dans cette suite.'}
function Get-ADComputer {$script:ForbiddenCalls++;throw 'Accès AD interdit dans cette suite.'}
function Refresh-Names {$script:ForbiddenCalls++;throw 'Inventaire AD interdit dans cette suite.'}
function Run-Queue {$script:ForbiddenCalls++;throw 'Exécution de file interdite dans cette suite.'}
function Pump {param([int]$Ms=130);$until=[DateTime]::UtcNow.AddMilliseconds($Ms);while([DateTime]::UtcNow -lt $until){Invoke-DoEvents;Start-Sleep -Milliseconds 10}}
function Start-StaleLookup {
    # Le moteur n'arme plus la lecture différée à la saisie (lecture par Lire ou Entrée) ; sa garde reste testée.
    $script:PestoUxLookupName=([string]$TxtPCName.Text).Trim().ToUpperInvariant()
    $script:PestoUxLookupEditIndex=[int]$script:EDIT_ROW_INDEX
    $script:PestoUxLookupLocal=[bool]$script:LOCALHOST
    $script:PestoUxLookupTimer.Start()
}
[xml]$xml=Get-Content -LiteralPath $shellPath -Raw -Encoding UTF8
if(-not $xml -or $xml.DocumentElement.LocalName -ne 'Window'){throw 'XAML principal introuvable.'}
$manager=[Xml.XmlNamespaceManager]::new($xml.NameTable);$manager.AddNamespace('x','http://schemas.microsoft.com/winfx/2006/xaml')
$manager.AddNamespace('p','http://schemas.microsoft.com/winfx/2006/xaml/presentation')
$publicXPath='//*[@x:Name and not(ancestor::p:ControlTemplate) and not(ancestor::p:DataTemplate) and not(ancestor::p:ItemsPanelTemplate)]'
$Win=$null
try{
    Case 'Chargement réel de la fenêtre XAML et de ses ressources' {$script:Win=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($xml));Assert-True ($null -ne $Win)}
    if(-not $Win){throw 'Chargement WPF impossible. Aucun test de navigation lancé.'}
    foreach($node in $xml.SelectNodes($publicXPath,$manager)){
        $n=$node.GetAttribute('Name','http://schemas.microsoft.com/winfx/2006/xaml');Set-Variable -Name $n -Value $Win.FindName($n) -Scope Script
    }
    Case 'Les contrôles publics du Shell sont uniques et résolus par FindName' {
        $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach($node in $xml.SelectNodes($publicXPath,$manager)){
            $controlName=$node.GetAttribute('Name','http://schemas.microsoft.com/winfx/2006/xaml')
            Assert-True ($seen.Add($controlName)) ('Nom public dupliqué : '+$controlName)
            Assert-True ($null -ne $Win.FindName($controlName)) $node.OuterXml
        }
        Assert-True ($seen.Count -gt 0) 'Aucun contrôle public.'
    }
    $script:Themes=@{}
    Case 'Palettes Light et Dark lues dans $script:Themes sans exécuter le moteur' {
        $script:Themes=Read-ThemePalettes $engineAst['Pesto-Core.ps1'] $path
        foreach($paletteKey in $script:Themes['Light'].Keys){Assert-True ($Win.Resources[$paletteKey] -is [Windows.Media.SolidColorBrush]) ('Pinceau absent du Shell : '+$paletteKey)}
    }
    $script:table=New-QueueTable;$Grid.ItemsSource=$script:table.DefaultView
    $script:INDOMAIN=$true;$script:LOCALHOST=$false;$script:GUI=$true;$script:SIM=$false
    $script:DOMAINE='TEST.LOCAL';$script:PREFIXE='111301';$script:OU=@{};$script:OUV=@{};$script:EDIT_ROW_INDEX=-1;$script:Suspend=$false
    $script:Running=$false;$script:PreflightRunning=$false;$script:MutationUncertain=$false;$script:CfgRestartRequired=$false
    $script:Computers=@();$script:PestoUxReady=$false;$script:PCProbeGeneration=0
    $script:ThemeMode='Light';$script:SuiteReady=$false;$script:SuiteMode='Single';$script:DirectBusy=$false
    $script:HelpVisible=$false;$script:NavigationCollapsed=$false;$script:InventoryLoaded=$false
    $sourceOU='OU=Windows11,OU=PR,OU=Postes,DC=test,DC=local'
    $targetOU='OU=Windows11,OU=VA,OU=Postes,DC=test,DC=local'
    $fixture=@{Computer='P111301PR765129';NewName='P111301VA765010';CurrentOU=$sourceOU;TargetOU=$targetOU;Rename=$true;Move=$false;Reboot=$false;InDomain=$true;CanAdd=$true;Service='765';Site='VA';Type='Portable'}
    Case 'PR vers VA : aperçu renommer puis déplacer' {$v=Get-PestoUxSnapshot @fixture;Equal $v.Operation 'Renommer puis déplacer';Equal $v.FutureOU $targetOU;Assert-True $v.Move}
    Case 'Même site : conserver l''OU actuelle malgré une autre OU proposée' {$f=$fixture.Clone();$f.Computer='P111301VA765129';$v=Get-PestoUxSnapshot @f;Equal $v.Operation 'Renommer seulement';Equal $v.FutureOU $sourceOU;Assert-True (-not $v.Move)}
    Case 'Même site, changement de service : aucun déplacement' {$f=$fixture.Clone();$f.NewName='P111301PR123010';$v=Get-PestoUxSnapshot @f;Assert-True (-not $v.Move);Equal $v.FutureOU $sourceOU}
    Case 'Déplacement seul : nom source conservé' {$f=$fixture.Clone();$f.Rename=$false;$f.Move=$true;$v=Get-PestoUxSnapshot @f;Equal $v.Operation 'Déplacer seulement';Equal $v.FinalName $f.Computer;Equal $v.FutureOU $targetOU}
    Case 'Redémarrage non demandé par défaut' {Equal (Get-PestoUxSnapshot @fixture).RebootText 'Redémarrage : non demandé'}
    Case 'Redémarrage explicite correctement présenté' {$f=$fixture.Clone();$f.Reboot=$true;Equal (Get-PestoUxSnapshot @f).RebootText 'Redémarrage : demandé après réussite'}
    Case 'Hors domaine : aperçu de jonction locale' {$f=$fixture.Clone();$f.InDomain=$false;$v=Get-PestoUxSnapshot @f;Equal $v.Operation 'Joindre ce PC au domaine';Equal $v.FutureOU $targetOU}
    Case 'Verrou de sécurité expliqué sans être effacé' {$f=$fixture.Clone();$f.SafetyLocked=$true;$v=Get-PestoUxSnapshot @f;Assert-True ($v.NextStep -like 'Verrou de sécurité*')}
    Case 'Nom occupé expliqué' {$f=$fixture.Clone();$f.NameTaken=$true;$f.CanAdd=$false;Assert-True ((Get-PestoUxSnapshot @f).AddHint -like 'Ce nom est déjà pris*')}
    Case 'Lecture source en cours explique l''attente' {$f=$fixture.Clone();$f.Reading=$true;Equal (Get-PestoUxSnapshot @f).Stage 1}
    Case 'Étape 4 réservée au traitement effectivement en cours' {$f=$fixture.Clone();$f.Running=$true;Equal (Get-PestoUxSnapshot @f).Stage 4}
    Case 'Contrôle AD reste en étape 3 sans annoncer une mutation' {$f=$fixture.Clone();$f.Preflight=$true;Equal (Get-PestoUxSnapshot @f).Stage 3}
    Case 'Aides des commandes désactivées activées dans WPF' {
        foreach($control in @($BtnAdd,$BtnRun,$BtnStop,$BtnRetryMove,$CbSite,$CbName)){
            Assert-True ([Windows.Controls.ToolTipService]::GetShowOnDisabled($control)) $control.Name
            Assert-True (-not [string]::IsNullOrWhiteSpace([string]$control.ToolTip)) $control.Name
        }
    }
    Case 'Tous les contrôles interactifs publics possèdent une aide' {
        foreach($node in $xml.SelectNodes($publicXPath,$manager)){
            $name=$node.GetAttribute('Name','http://schemas.microsoft.com/winfx/2006/xaml');$c=$Win.FindName($name)
            if($c -is [Windows.Controls.Primitives.ButtonBase] -or $c -is [Windows.Controls.TextBox] -or $c -is [Windows.Controls.ComboBox] -or $c -is [Windows.Controls.DataGrid]){
                Assert-True (-not [string]::IsNullOrWhiteSpace([string]$c.ToolTip)) "Aide absente : $name"
                Assert-True (-not [string]::IsNullOrWhiteSpace([Windows.Automation.AutomationProperties]::GetHelpText($c))) "HelpText absent : $name"
            }
        }
    }
    Case 'Colonnes simples : exactement six colonnes visibles' {Set-PestoUxTechnicalColumns $false;Equal @($Grid.Columns|Where-Object{$_.Visibility -eq 'Visible'}).Count 6}
    Case 'Colonnes techniques réversibles et liaisons conservées' {Set-PestoUxTechnicalColumns $true;Equal @($Grid.Columns|Where-Object{$_.Visibility -eq 'Visible'}).Count $Grid.Columns.Count;Set-PestoUxTechnicalColumns $false;Equal @($Grid.Columns|Where-Object{$_.Visibility -eq 'Visible'}).Count 6}
    Case 'Thème clair appliqué par le véritable Set-Theme' {Set-Theme 'Light';Assert-Palette 'Light';Equal $script:CurrentTheme 'Light'}
    Case 'Thème sombre appliqué aux mêmes ressources' {Set-Theme 'Dark';Assert-Palette 'Dark';Equal $script:CurrentTheme 'Dark'}
    Case 'Initialisation des événements sans closure privée' {Initialize-PestoUx;Assert-True $script:PestoUxReady;Pump}
    # Fenêtre WPF hors écran et transparente pour mesurer/arranger réellement les contrôles.
    # Ni login, ni moteur, ni module AD ne sont chargés par ces tests.
    Case 'Mise en page réelle à 1460 x 940' {
        $Win.ShowInTaskbar=$false;$Win.Opacity=0;$Win.WindowStartupLocation='Manual';$Win.Left=-12000;$Win.Top=-12000
        $Win.Width=1460;$Win.Height=940;$Win.Show();Pump 180;$Win.UpdateLayout();Update-PestoUxLayout
        Assert-True ($BodyGrid.ActualWidth -gt 0);Equal ([Windows.Controls.Grid]::GetColumn($PreviewPanel)) 2
        Assert-True ($BtnRun.ActualHeight -ge 36)
    }
    Case 'Mise en page compacte à 1100 : aperçu sous le formulaire' {$Win.Width=1100;Pump;Update-PestoUxLayout;$Win.UpdateLayout();Equal ([Windows.Controls.Grid]::GetColumn($PreviewPanel)) 0;Equal ([Windows.Controls.Grid]::GetRow($PreviewPanel)) 1;Equal $FormSplitter.Visibility 'Collapsed'}
    Case 'Retour à la disposition large sans recréer le formulaire' {$Win.Width=1460;Pump;Update-PestoUxLayout;Equal ([Windows.Controls.Grid]::GetColumn($PreviewPanel)) 2;Equal ([Windows.Controls.Grid]::GetRow($PreviewPanel)) 0;Equal $FormSplitter.Visibility 'Visible'}
    Case 'ComboBox non éditable : menu contractuel présent' {[void]$CbSite.ApplyTemplate();Assert-True ($null -ne $CbSite.Template.FindName('PART_Popup',$CbSite))}
    Case 'ComboBox éditable : vrai champ de saisie conservé' {[void]$CbService.ApplyTemplate();Assert-True ($CbService.Template.FindName('PART_EditableTextBox',$CbService) -is [Windows.Controls.TextBox])}
    Case 'Navigation par vrais événements WPF' {
        foreach($pair in @(@($NavHome,4),@($NavRename,0),@($NavNames,1),@($NavHistory,5),@($NavLogs,3),@($NavSettings,2),@($NavHelp,6),@($NavJoin,7))){
            $pair[0].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
            Equal $MainTabs.SelectedIndex $pair[1]
        }
        Equal $script:SuiteMode 'Single'
        Set-PestoUxPage 'Rename'
    }
    # X5 : anneaux d'état lus dans les vrais gabarits WPF. Couleurs système de contraste élevé simulées (Noir) ;
    # le rendu à l'écran reste à vérifier sur une capture Windows en contraste élevé.
    Case 'X5 contraste élevé : anneaux du menu actif, de l''onglet actif et de l''élément survolé, transparents en clair et sombre' {
        $hc=@{Window='#000000';WindowText='#FFFFFF';Highlight='#1AEBFF';HighlightText='#000000';ButtonFace='#000000';ButtonText='#FFFFFF';HotTrack='#FFFF00'}
        $script:Themes['HighContrast']=ConvertTo-PestoHighContrastPalette -Keys @($script:Themes['Light'].Keys) -System $hc
        $themeBefore=$script:CurrentTheme
        $probe=[Windows.Controls.ComboBoxItem]::new();$probe.Content='Sonde X5'
        $setHighlighted=[Windows.Controls.ComboBoxItem].GetProperty('IsHighlighted').GetSetMethod($true)
        $ringColor={
            param($Control,[string]$Part)
            [void]$Control.ApplyTemplate()
            $ring=$Control.Template.FindName($Part,$Control)
            Assert-True ($ring -is [Windows.Controls.Border]) ('Anneau absent : '+$Part)
            if($ring.BorderBrush -is [Windows.Media.SolidColorBrush]){return $ring.BorderBrush.Color.ToString()}
            return 'aucun'
        }
        try{
            Set-PestoUxPage 'Settings';$SetTabs.SelectedIndex=0;[void]$SuiteThemeChoiceHost.Children.Add($probe);Pump;$Win.UpdateLayout()
            foreach($theme in @('Light','Dark','HighContrast')){
                Set-Theme $theme;Assert-Palette $theme;Pump;$Win.UpdateLayout()
                [void]$setHighlighted.Invoke($probe,[object[]]@($true));$probe.IsSelected=$false
                $hover=& $ringColor $probe 'ComboItemState'
                $probe.IsSelected=$true
                $hoverSelected=& $ringColor $probe 'ComboItemState'
                [void]$setHighlighted.Invoke($probe,[object[]]@($false))
                $selectedOnly=& $ringColor $probe 'ComboItemState'
                $probe.IsSelected=$false
                $found=[ordered]@{
                    'menu actif'=(& $ringColor $NavSettings 'ButtonState');'onglet actif'=(& $ringColor $SetTabs.Items[0] 'InnerTabState')
                    'élément survolé'=$hover;'élément survolé et sélectionné'=$hoverSelected
                    'menu inactif'=(& $ringColor $NavHome 'ButtonState');'onglet inactif'=(& $ringColor $SetTabs.Items[1] 'InnerTabState')
                    'élément sélectionné non survolé'=$selectedOnly;'élément au repos'=(& $ringColor $probe 'ComboItemState')
                }
                # Contraste élevé : surlignage (Highlight), texte de surlignage sur un élément déjà sélectionné. Sinon : transparent.
                $wantRing=if($theme -eq 'HighContrast'){'#FF1AEBFF'}else{'#00000000'};$wantOnSelection=if($theme -eq 'HighContrast'){'#FF000000'}else{'#00000000'}
                $want=@{'menu actif'=$wantRing;'onglet actif'=$wantRing;'élément survolé'=$wantRing;'élément survolé et sélectionné'=$wantOnSelection}
                foreach($state in @($found.Keys)){
                    $expected=if($want.ContainsKey($state)){$want[$state]}else{'aucun'}
                    Assert-True ($found[$state] -eq $expected) ($theme+', '+$state+' : attendu '+$expected+', obtenu '+$found[$state])
                }
            }
        }finally{[void]$SuiteThemeChoiceHost.Children.Remove($probe);Set-Theme $themeBefore;Set-PestoUxPage 'Rename'}
    }
    Case 'Bouton Aide : panneau basculé et mémorisé, page conservée' {
        $page=$MainTabs.SelectedIndex;$writes=$script:PrefsWrites
        $BtnHelp.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
        Assert-True ([bool]$script:HelpVisible) 'Aide non affichée.'
        $BtnHelp.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
        Assert-True (-not $script:HelpVisible) 'Aide non refermée.'
        Equal $MainTabs.SelectedIndex $page;Equal ($script:PrefsWrites-$writes) 2
    }
    Case 'Historique vide clairement expliqué' {Update-PestoUxHistory;Assert-True ($UxHistoryMessage.Text -like 'Aucun lot terminé*')}
    Case 'Historique d''un autre domaine refusé' {
        [IO.File]::WriteAllText((Join-Path $temp 'history-v1.json'),'{"Schema":1,"Domain":"OTHER.LOCAL","Entries":[]}')
        Update-PestoUxHistory;Assert-True ($UxHistoryMessage.Text -like 'Historique non chargé*')
        Remove-Item -LiteralPath (Join-Path $temp 'history-v1.json') -Force
    }
    Case 'La recherche invalide immédiatement l''ancien plan' {
        $generation=[int]$script:PCProbeGeneration
        $TxtPCName.Text='P111301PR765129';$BtnAdd.IsEnabled=$true;Request-PestoUxComputerLookup
        Assert-True (-not $BtnAdd.IsEnabled) 'Ajout encore possible.';Equal $script:PCProbeGeneration ($generation+1)
        Assert-True (-not $script:PestoUxLookupTimer.IsEnabled) 'Lecture différée armée par la saisie.'
    }
    Case 'Saisies rapides : aucune lecture du poste sans demande explicite' {
        $before=$script:SourceReads
        Request-PestoUxComputerLookup;Request-PestoUxComputerLookup;Request-PestoUxComputerLookup
        Pump 450;Equal ($script:SourceReads-$before) 0
    }
    Case 'Lecture différée au même contexte : une seule lecture' {
        $before=$script:SourceReads;Start-StaleLookup
        Pump 450;Equal ($script:SourceReads-$before) 1;Assert-True (-not $script:PestoUxLookupTimer.IsEnabled) 'Timer de lecture resté actif.'
    }
    Case 'Demande temporisée abandonnée après changement de ligne éditée' {
        Start-StaleLookup;$before=$script:SourceReads;$script:EDIT_ROW_INDEX=3
        Pump 450;Equal $script:SourceReads $before;$script:EDIT_ROW_INDEX=-1
    }
    Case 'Demande temporisée abandonnée après changement local/distant' {
        Start-StaleLookup;$before=$script:SourceReads;$script:LOCALHOST=-not $script:LOCALHOST
        Pump 450;Equal $script:SourceReads $before;$script:LOCALHOST=-not $script:LOCALHOST
    }
    Case 'Bouton de lecture : une lecture, sans préparer ni lancer de ligne' {
        $before=$script:table.Rows.Count;$reads=$script:SourceReads;Invoke-PestoUxReadComputer $null $null
        Equal $script:table.Rows.Count $before;Equal ($script:SourceReads-$reads) 1;Equal $script:ForbiddenCalls 0
    }
    Case 'Touche Entrée : lecture du poste seulement' {
        $before=$script:table.Rows.Count;$reads=$script:SourceReads
        $keyEvent=[pscustomobject]@{Key=[Windows.Input.Key]::Return;Handled=$false}
        Invoke-PestoUxSourceKey $TxtPCName $keyEvent
        Assert-True $keyEvent.Handled 'Touche Entrée non consommée.';Equal ($script:SourceReads-$reads) 1;Equal $script:table.Rows.Count $before
    }
    Case 'Verrou de sécurité : aucune lecture du poste' {
        $reads=$script:SourceReads;$script:MutationUncertain=$true
        try{Invoke-PestoUxReadComputer $null $null}finally{$script:MutationUncertain=$false}
        Equal $script:SourceReads $reads
    }
    Case 'Rendus pour les guides (mode réel, valeurs fictives)' {
        $out='C:\PestoTest-preuves\guide-rendu-labo';New-Item -ItemType Directory -Force $out|Out-Null
        $Win.Width=1460;$Win.Height=940;Pump 60;$Win.UpdateLayout();Update-PestoUxLayout
        Set-Theme 'Light';Pump 60
        # Mode réel : aucun indicateur de démonstration ni de simulation (valeurs du code hors démonstration).
        $script:GUI=$false;$script:SIM=$false;$script:DOMAINE='labo.local';$script:INDOMAIN=$true
        try{Stop-PestoUx}catch{}
        $script:GuideTexts=@{}
        function Set-GuideTexts{foreach($k in $script:GuideTexts.Keys){$c=Get-Variable -Name $k -ValueOnly -ErrorAction SilentlyContinue;if($c){$c.Text=$script:GuideTexts[$k]}}}
        function Save-Render([string]$Name){
            Pump 120;Set-GuideTexts;$Win.UpdateLayout();Pump 40;Set-GuideTexts;$Win.UpdateLayout()
            $w=[int][Math]::Max(1,$Win.ActualWidth);$h=[int][Math]::Max(1,$Win.ActualHeight)
            $rtb=New-Object Windows.Media.Imaging.RenderTargetBitmap($w,$h,96,96,([Windows.Media.PixelFormats]::Pbgra32))
            $dv=New-Object Windows.Media.DrawingVisual;$dc=$dv.RenderOpen()
            $dc.DrawRectangle($Win.Background,$null,(New-Object Windows.Rect(0,0,$w,$h)))
            $dc.DrawRectangle((New-Object Windows.Media.VisualBrush($Win.Content)),$null,(New-Object Windows.Rect(0,0,$w,$h)));$dc.Close()
            $rtb.Render($dv)
            $enc=New-Object Windows.Media.Imaging.PngBitmapEncoder;$enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($rtb))
            $fs=[IO.File]::Create((Join-Path $out ($Name+'.png')));try{$enc.Save($fs)}finally{$fs.Close()}
        }
        function Set-GuideChip([string]$Name,[string]$Text){$c=$Win.FindName($Name);if($Text){$c.Child.Text=$Text;$c.Visibility='Visible'}else{$c.Visibility='Collapsed'}}
        # En-tête d'un poste du domaine, mode réel (textes identiques à ceux de Pesto-Core.ps1 hors démonstration)
        Set-GuideChip 'ChipMember' 'P111301VA765001';Set-GuideChip 'ChipDomain' 'labo.local';Set-GuideChip 'ChipAccount' 'LABO\tech.pesto'
        Set-GuideChip 'ChipJoin' '';Set-GuideChip 'ChipSim' '';Set-GuideChip 'ChipGui' ''
        $script:GuideTexts=@{UxCacheCount='1 284';UxQueueTotal='0';UxReviewTotal='0';
            UxHomeContext="Domaine : example.local`nMODE RÉEL : écritures après confirmation`nLes compteurs du cache n'indiquent pas la disponibilité réseau des postes.";
            UxExecutionMode='MODE RÉEL : écritures après confirmation';UxHistoryMessage=''}
        $script:MainTabs.SelectedIndex=4;Save-Render 'Accueil'
        $script:MainTabs.SelectedIndex=0;Save-Render 'UnPoste'
        # Noms disponibles : quelques lignes fictives, ligne d'inventaire au format réel (Pesto-Core.ps1, Update-NameGrid).
        $rows=New-Object System.Collections.ObjectModel.ObservableCollection[object]
        foreach($r in @(@('P111301VA765003','Portable','VA','765','003','Libre dans l''inventaire'),@('P111301VA765004','Portable','VA','765','004','Libre dans l''inventaire'),
                        @('P111301VA765005','Portable','VA','765','005','Libre dans l''inventaire'),@('P111301VA765006','Portable','VA','765','006','Libre dans l''inventaire'),
                        @('P111301VA765007','Portable','VA','765','007','Libre dans l''inventaire'),@('P111301VA765008','Portable','VA','765','008','Libre dans l''inventaire'))){
            $rows.Add([pscustomobject]@{Nom=$r[0];Type=$r[1];Site=$r[2];Equipe=$r[3];Num=$r[4];Statut=$r[5]})}
        try{Set-PestoNamesViewState -State Ready}catch{$NmLoadingPanel.Visibility='Collapsed';$NmGrid.Visibility='Visible';$NmGrid.IsEnabled=$true}
        $NmGrid.ItemsSource=$rows
        $script:GuideTexts['NmLblCount']='6 affichés / 6 correspondants · 6 libres · 2 AD · 0 préparés'
        $script:GuideTexts['NmViewNote']='Inventaire : 07/10/2026 10:42:15. Disponibilité dans le périmètre configuré, sans réservation AD. Export limité à la page affichée. Vérifier un candidat avant utilisation.'
        $script:MainTabs.SelectedIndex=1;Save-Render 'Noms'
        $script:MainTabs.SelectedIndex=5;Save-Render 'Historique'
        # Poste hors domaine : page Ajouter au domaine
        Set-GuideChip 'ChipMember' 'DESKTOP-7Q2K4LM';Set-GuideChip 'ChipJoin' 'Jonction : production directe'
        $reader=[Xml.XmlReader]::Create((Join-Path $root 'wad\Pesto-Join.xaml'));try{$view=[Windows.Markup.XamlReader]::Load($reader)}finally{$reader.Dispose()}
        $Win.FindName('UxJoinHost').Content=$view
        function J([string]$n){$view.FindName($n)}
        (J 'JnCurrent').Text='DESKTOP-7Q2K4LM';(J 'JnDomain').Text='labo.local';(J 'JnLocalState').Text='Groupe de travail : PC hors domaine';(J 'JnAccount').Text='LABO\tech.pesto'
        (J 'JnPolicy').Text='Production directe autorisée par la configuration.'
        foreach($v in @('Portable','Fixe','Virtuel')){[void](J 'JnType').Items.Add($v)};(J 'JnType').SelectedIndex=0
        [void](J 'JnOrg').Items.Add('Département 111301');(J 'JnOrg').SelectedIndex=0
        foreach($v in @('Paris','Lyon')){[void](J 'JnSite').Items.Add($v)};(J 'JnSite').SelectedIndex=0
        foreach($v in @('765','INF','RH0')){[void](J 'JnService').Items.Add($v)};(J 'JnService').Text='765'
        foreach($v in @('P111301VA765004','P111301VA765005','P111301VA765006')){[void](J 'JnName').Items.Add($v)};(J 'JnName').SelectedIndex=0
        (J 'JnReference').Text='INC-2026-0412';(J 'JnNamePreview').Text='P111301VA765004';(J 'JnOUPreview').Text='OU=Paris,OU=SITES,OU=Postes,OU=Departement 111301,OU=ADCC-Lab,DC=labo,DC=local'
        $script:MainTabs.SelectedIndex=7;Pump 160;(J 'JnFields').BringIntoView();Save-Render 'Jonction'
        # Fenêtre de bilan : vrai gabarit de Show-PestoPanel (Pesto-Workspace.ps1), texte du code 10 de Pesto-Join.ps1
        $ws=Get-Content -LiteralPath (Join-Path $root 'wad\Pesto-Workspace.ps1') -Raw -Encoding UTF8
        $xamlText=[regex]::Match($ws,"(?s)function Show-PestoPanel.*?\[xml\]\`$x=@'\r?\n(.*?)\r?\n'@").Groups[1].Value
        if(-not $xamlText){throw 'Gabarit du panneau introuvable dans Pesto-Workspace.ps1.'}
        $overlay=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new([xml]$xamlText))
        [Windows.Controls.Grid]::SetColumnSpan($overlay,99);[Windows.Controls.Grid]::SetRowSpan($overlay,99);[Windows.Controls.Panel]::SetZIndex($overlay,10000)
        $title='Ajout accepté · redémarrage nécessaire'
        $overlay.FindName('PanelTitle').Text=$title
        $overlay.FindName('PanelBody').Text=$title+"`n`n"+'Le nouveau nom et le domaine ne sont pas annoncés comme pleinement actifs avant redémarrage et vérification.'
        [void]$Win.Content.Children.Add($overlay);Save-Render 'Bilan';[void]$Win.Content.Children.Remove($overlay)
    }
    Case 'Fermeture arrête les deux timers UI' {Stop-PestoUx;Assert-True (-not $script:PestoUxTimer.IsEnabled);Assert-True (-not $script:PestoUxLookupTimer.IsEnabled)}
    Case 'Aucune mutation ni lecture AD pendant les tests UI' {Equal $script:ForbiddenCalls 0}
    Case 'Aucune exception masquée par le rafraîchissement d''aperçu' {Equal $script:UiErrors.Count 0}
}finally{
    if($Win){try{Stop-PestoUx;$Win.Close()}catch{}}
    if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force}
    $failed=@($results|Where-Object{-not $_.Passed})
    $report=[ordered]@{Suite='Pesto interface (fenêtre principale isolée)';Utc=[DateTime]::UtcNow.ToString('o');SourceHash=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash;
        ShellHash=(Get-FileHash -LiteralPath $shellPath -Algorithm SHA256).Hash;EngineFiles=$engineFiles.ToArray();
        Total=$results.Count;Passed=$results.Count-$failed.Count;Failed=$failed.Count;Tests=$results.ToArray();
        Scope='Fenêtre WPF isolée (Pesto-Shell.xaml), mise en page hors écran, palettes de $script:Themes, événements, aides, fonctions extraites du moteur et de ses composants. Aucun login, accès AD, mutation ni validation visuelle manuelle.'}
    $report|ConvertTo-Json -Depth 7|Set-Content -LiteralPath $ReportPath -Encoding UTF8
}
if($failed.Count){exit 1}
Write-Host 'Tests UI isolés réussis. Effectuer aussi une recette visuelle et un test sur des postes non critiques.'
exit 0
