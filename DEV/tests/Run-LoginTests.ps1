#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$CorePath,
    [string]$ReportPath='',
    [switch]$Preview,
    [ValidateSet('Light','Dark')][string]$Theme='Light'
)
# Windows PowerShell 5.1 : $PSScriptRoot est vide dans les valeurs par défaut des paramètres (vu le 03/10).
if(-not $ReportPath){$ReportPath=Join-Path $PSScriptRoot 'windows-login-results.json'}
# Test local de mise en page : le moteur Pesto n'est JAMAIS execute ou dot-source.
# Seuls ses gabarits XAML et ses ressources visuelles sont charges.
# Les palettes Light/Dark viennent de $script:Themes (wad\Pesto-Core.ps1), lu par l'arbre du parseur :
# aucune evaluation de code, seules des chaines de couleur litterales sont acceptees.
$ErrorActionPreference='Stop'
if($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSEdition -ne 'Desktop' -or
   $PSVersionTable.PSVersion.Major -ne 5 -or -not [Environment]::Is64BitProcess){
    throw 'Windows PowerShell 5.1 x64 requis pour ce test WPF.'
}
if([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA'){throw 'Relancer avec powershell.exe -STA.'}
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Xml
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

function Get-LiteralExpression {
    # Expression pure d'un noeud du parseur (partie droite d'une affectation ou valeur d'une table).
    param([Management.Automation.Language.Ast]$Node)
    if($Node -is [Management.Automation.Language.PipelineAst]){return $Node.GetPureExpression()}
    if($Node -is [Management.Automation.Language.CommandExpressionAst]){return $Node.Expression}
    return $Node
}
function Get-LiteralKey {
    param([Management.Automation.Language.Ast]$Node,[string]$Where)
    if(-not($Node -is [Management.Automation.Language.StringConstantExpressionAst]) -or -not $Node.Value){
        throw ('Cle non litterale dans '+$Where+' : '+$Node.Extent.Text)
    }
    return [string]$Node.Value
}
function Read-ThemePalettes {
    # Lecture comme texte puis analyse par le parseur : aucune instruction du moteur n'est executee.
    # Seules des tables imbriquees de chaines '#RRGGBB' ou '#AARRGGBB' sont acceptees.
    param([string]$Path)
    $themeText=Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $themeTokens=$null;$themeParseErrors=$null
    $themeAst=[Management.Automation.Language.Parser]::ParseInput($themeText,[ref]$themeTokens,[ref]$themeParseErrors)
    if($themeParseErrors.Count){throw ('Source des themes invalide : '+(($themeParseErrors|ForEach-Object{$_.Message}) -join '; '))}
    $themeNodes=@($themeAst.FindAll({
        param($Candidate)
        ($Candidate -is [Management.Automation.Language.AssignmentStatementAst]) -and
        ([string]$Candidate.Operator -eq 'Equals') -and
        ($Candidate.Left -is [Management.Automation.Language.VariableExpressionAst]) -and
        ($Candidate.Left.VariablePath.UserPath -eq 'script:Themes' -or $Candidate.Left.Extent.Text -eq '$script:Themes')
    },$true))
    if($themeNodes.Count -ne 1){throw ('Affectation $script:Themes introuvable ou ambigue dans '+$Path+' ('+$themeNodes.Count+').')}
    $themeTable=Get-LiteralExpression $themeNodes[0].Right
    if(-not($themeTable -is [Management.Automation.Language.HashtableAst])){throw 'Palettes non litterales : aucune evaluation du moteur.'}
    $found=@{}
    foreach($themePair in $themeTable.KeyValuePairs){
        $themeName=Get-LiteralKey $themePair.Item1 '$script:Themes'
        $colorTable=Get-LiteralExpression $themePair.Item2
        if(-not($colorTable -is [Management.Automation.Language.HashtableAst])){throw ('Palette non litterale : '+$themeName)}
        $colors=@{}
        foreach($colorPair in $colorTable.KeyValuePairs){
            $colorKey=Get-LiteralKey $colorPair.Item1 $themeName
            $colorValue=Get-LiteralExpression $colorPair.Item2
            if(-not($colorValue -is [Management.Automation.Language.StringConstantExpressionAst]) -or
               -not [regex]::IsMatch([string]$colorValue.Value,'\A#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})\z')){
                throw ('Couleur non litterale ou invalide : '+$themeName+'.'+$colorKey)
            }
            if($colors.ContainsKey($colorKey)){throw ('Couleur dupliquee : '+$themeName+'.'+$colorKey)}
            $colors[$colorKey]=[string]$colorValue.Value
        }
        if($found.ContainsKey($themeName)){throw ('Palette dupliquee : '+$themeName)}
        $found[$themeName]=$colors
    }
    foreach($required in @('Light','Dark')){
        if(-not $found.ContainsKey($required) -or $found[$required].Count -lt 1){throw ('Palette absente : '+$required)}
    }
    # Une cle absente d'un theme laisserait le pinceau Light du Shell en place, sans erreur WPF.
    $lightKeys=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($colorKey in $found['Light'].Keys){[void]$lightKeys.Add([string]$colorKey)}
    $darkKeys=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($colorKey in $found['Dark'].Keys){[void]$darkKeys.Add([string]$colorKey)}
    if(-not $lightKeys.SetEquals($darkKeys)){
        $onlyLight=@($lightKeys|Where-Object{-not $darkKeys.Contains($_)})
        $onlyDark=@($darkKeys|Where-Object{-not $lightKeys.Contains($_)})
        throw ('Palettes Light et Dark incoherentes. Light seul : '+($onlyLight -join ', ')+' ; Dark seul : '+($onlyDark -join ', '))
    }
    return $found
}
function New-PaletteBrush {
    # Meme construction que New-Brush du moteur : pinceau uni gele.
    param([string]$Hex)
    $brush=[Windows.Media.SolidColorBrush]::new([Windows.Media.Color][Windows.Media.ColorConverter]::ConvertFromString($Hex))
    $brush.Freeze()
    return $brush
}

# Gabarits déplacés : fenêtre principale dans Pesto-Shell.xaml, connexion dans Pesto-Authentication.ps1.
if(-not $CorePath){$CorePath=Join-Path $root 'wad\Pesto-Authentication.ps1'}
$shellPath=Join-Path $root 'wad\Pesto-Shell.xaml'
# docs\RC6_UI_TOKENS.json a ete supprime : palettes actuelles du moteur, lues sans l'executer.
$themePath=Join-Path $root 'wad\Pesto-Core.ps1'
$source=Get-Content -LiteralPath $CorePath -Raw -Encoding UTF8
$parseTokens=$null;$parseErrors=$null
$null=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$parseTokens,[ref]$parseErrors)
if($parseErrors.Count){throw ('Source invalide : '+(($parseErrors|ForEach-Object{$_.Message}) -join '; '))}
$mainText=Get-Content -LiteralPath $shellPath -Raw -Encoding UTF8
$login=[regex]::Match($source,'(?ms)^\s*\[xml\]\$lxaml\s*=\s*@"\r?\n(.*?)^"@')
if(-not $mainText -or -not $login.Success){throw 'Gabarits XAML absents. Aucun lancement de Pesto.'}
[xml]$mainXml=$mainText
$resourceNode=$mainXml.DocumentElement.ChildNodes|Where-Object{$_.LocalName -eq 'Window.Resources'}|Select-Object -First 1
if(-not $resourceNode){throw 'Ressources visuelles absentes.'}
$resourceText='<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">'+$resourceNode.InnerXml+'</ResourceDictionary>'
# Seule variable inseree par Show-LoginWindow : $bannerTextXml, echappee comme dans le moteur.
$loginText=$login.Groups[1].Value.Replace('$bannerTextXml',[Security.SecurityElement]::Escape('Aperçu local · sans connexion AD'))
if($loginText.Contains('$') -or $loginText.Contains('`')){throw 'Variable PowerShell non resolue dans le gabarit de connexion : apercu impossible sans le moteur.'}
$palettes=Read-ThemePalettes $themePath
# Une ressource dynamique absente ne leve aucune erreur WPF : la verifier avant toute mesure.
# Cles WPF sensibles a la casse : comparaison ordinale.
$resourceKeys=[Collections.Generic.List[string]]::new()
foreach($resourceChild in $resourceNode.ChildNodes){
    if($resourceChild -is [Xml.XmlElement]){
        $resourceKey=$resourceChild.GetAttribute('Key','http://schemas.microsoft.com/winfx/2006/xaml')
        if($resourceKey){$resourceKeys.Add($resourceKey)}
    }
}
foreach($paletteName in @('Light','Dark')){
    $knownKeys=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($knownKey in $resourceKeys){[void]$knownKeys.Add($knownKey)}
    foreach($knownKey in $palettes[$paletteName].Keys){[void]$knownKeys.Add([string]$knownKey)}
    foreach($hit in [regex]::Matches($loginText+$resourceText,'\{DynamicResource\s+([^}\s]+)\}')){
        $dynamicKey=$hit.Groups[1].Value
        if(-not $knownKeys.Contains($dynamicKey)){
            throw ('Ressource dynamique sans couleur : '+$dynamicKey+' ('+$paletteName+').')
        }
    }
}
$results=[Collections.Generic.List[object]]::new()
$measurements=[Collections.Generic.List[object]]::new()

function Assert-Layout {
    param([bool]$Condition,[string]$Message)
    if(-not $Condition){throw $Message}
}
function Case {
    param([string]$Name,[scriptblock]$Body)
    try{& $Body;$results.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''});Write-Host "OK  $Name"}
    catch{$results.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message});Write-Host "KO  $Name : $($_.Exception.Message)"}
}
function Update-TestLayout {
    param([Windows.Window]$Window)
    $Window.UpdateLayout()
    # Attend les priorites de rendu sans timer ni callback dans une closure privee.
    [void]$Window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::ApplicationIdle)
    $Window.UpdateLayout()
}
function Close-TestPreview {
    param($Origin,$RoutedArgs)
    $w=[Windows.Window]::GetWindow($Origin)
    if($w){$p=$w.FindName('TxtPwd');if($p){$p.Clear()};$w.Close()}
}
function New-LoginFixture {
    param([string]$Palette,[switch]$LegacyPadding)
    $resources=$resourceText
    if($LegacyPadding){
        $needle='x:Name="PART_ContentHost" Margin="0"'
        Assert-Layout ($resources.Contains($needle)) 'Template corrige absent : reproduction RC6 impossible.'
        $resources=$resources.Replace($needle,'x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}"')
    }
    [xml]$rx=$resources
    $rd=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($rx))
    # Comme Initialize-PestoAppearance et Set-Theme : chaque couleur de la palette remplace la ressource du Shell.
    $colors=$palettes[$Palette]
    foreach($k in $colors.Keys){$rd[$k]=New-PaletteBrush $colors[$k]}
    [xml]$xml=$loginText
    $w=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($xml))
    $w.Resources=$rd
    $work=[Windows.SystemParameters]::WorkArea
    $w.MaxHeight=[Math]::Max(1,$work.Height-24)
    $w.MaxWidth=[Math]::Max(1,$work.Width-24)
    $w.Title+=' | TEST LOCAL SANS AD'
    $u=$w.FindName('TxtUser');$p=$w.FindName('TxtPwd')
    Assert-Layout ($u -is [Windows.Controls.TextBox]) 'Champ utilisateur introuvable.'
    Assert-Layout ($p -is [Windows.Controls.PasswordBox]) 'Champ mot de passe introuvable.'
    $u.Text='TEST\Utilisateur.gjpq'
    # Valeur synthetique, jamais utilisee pour une authentification ni journalisee.
    $p.Password='OnlyForLayout123'
    if($LegacyPadding){
        foreach($c in @($u,$p)){
            $c.MinHeight=0;$c.Height=40;$c.FontSize=13
            $c.Padding=[Windows.Thickness]::new(10,8,10,8)
        }
    }
    $w.FindName('BtnOk').IsDefault=$false
    $w.FindName('BtnOk').IsEnabled=$false
    $w.FindName('BtnWindows').IsEnabled=$false
    # Dans le moteur, ce bouton enregistre une preference de theme : inactif ici, -Theme choisit la palette.
    $themeButton=$w.FindName('LoginTheme')
    if($themeButton){$themeButton.IsEnabled=$false}
    $w.FindName('BtnCancel').Content='Fermer'
    $w.FindName('BtnCancel').Add_Click([Windows.RoutedEventHandler]${function:Close-TestPreview})
    $w.FindName('LblStep').Text='Essai de saisie local. Aucun compte verifie, aucune operation sur un poste.'
    return [pscustomobject]@{Window=$w;User=$u;Password=$p;Palette=$Palette}
}
function Show-HiddenFixture {
    param($Fixture)
    $w=$Fixture.Window
    $w.WindowStartupLocation='Manual';$w.Left=-12000;$w.Top=-12000
    $w.ShowInTaskbar=$false;$w.Opacity=0
    $w.Show();Update-TestLayout $w
}
function Get-FieldGeometry {
    param([Windows.Controls.Control]$Control,[string]$Palette)
    [void]$Control.ApplyTemplate();$Control.UpdateLayout()
    $hostPart=$Control.Template.FindName('PART_ContentHost',$Control)
    Assert-Layout ($hostPart -is [Windows.Controls.ScrollViewer]) 'PART_ContentHost doit etre un ScrollViewer.'
    [void]$hostPart.ApplyTemplate();$hostPart.UpdateLayout()
    $view=$hostPart.Content
    Assert-Layout ($null -ne $view) 'Vue de texte absente.'
    # DesiredSize de la vue interne peut elle-meme etre contrainte : mesurer une
    # ligne hors contrainte pour ne pas declarer lisible une vue deja ecrasee.
    $probe=[Windows.Controls.TextBlock]::new()
    $probe.FontFamily=$Control.FontFamily;$probe.FontSize=$Control.FontSize
    $probe.FontStyle=$Control.FontStyle;$probe.FontWeight=$Control.FontWeight
    $probe.FontStretch=$Control.FontStretch
    if($Control -is [Windows.Controls.PasswordBox]){$probe.Text=[string]$Control.PasswordChar}
    else{$probe.Text='Agjpq'}
    $probe.Measure([Windows.Size]::new([double]::PositiveInfinity,[double]::PositiveInfinity))
    $line=[double]$probe.DesiredSize.Height
    if($Control -is [Windows.Controls.TextBox]){
        $character=$Control.GetRectFromCharacterIndex(0)
        if(-not $character.IsEmpty -and $character.Height -gt 0){$line=$character.Height}
    }
    $viewport=[double]$hostPart.ViewportHeight
    Assert-Layout ($line -gt 0 -and $viewport -gt 0) 'Mesure WPF nulle : impossible de conclure sur la visibilite.'
    return [pscustomobject]@{
        Palette=$Palette;Field=$Control.Name;FontSize=$Control.FontSize
        ControlHeight=$Control.ActualHeight;HostHeight=$hostPart.ActualHeight
        ViewportHeight=$viewport;RequiredLineHeight=$line;TextDesiredHeight=$view.DesiredSize.Height
        HostMarginTop=$hostPart.Margin.Top;HostMarginBottom=$hostPart.Margin.Bottom
        PaddingTop=$hostPart.Padding.Top;PaddingBottom=$hostPart.Padding.Bottom
        Fits=($viewport+1 -ge $line)
    }
}
function Assert-ReadableField {
    param([Windows.Controls.Control]$Control,[string]$Palette)
    $g=Get-FieldGeometry $Control $Palette
    $measurements.Add($g)
    Assert-Layout ($g.HostMarginTop -eq 0 -and $g.HostMarginBottom -eq 0) 'Marge appliquee en plus du Padding WPF.'
    Assert-Layout ($g.PaddingTop -eq $Control.Padding.Top -and $g.PaddingBottom -eq $Control.Padding.Bottom) 'Padding interne incoherent.'
    Assert-Layout ([bool]$g.Fits) ('Texte coupe : vue='+$g.ViewportHeight+' ; hauteur texte='+$g.RequiredLineHeight)
    if($Control -is [Windows.Controls.TextBox]){
        $r=$Control.GetRectFromCharacterIndex(0)
        Assert-Layout (-not $r.IsEmpty -and $r.Height -gt 0) 'Geometrie du premier caractere absente.'
        Assert-Layout ($r.Top -ge 0 -and $r.Bottom -le $Control.ActualHeight+1) 'Caractere hors du champ.'
    }
}
function Get-Luminance {
    param([Windows.Media.Color]$Color)
    $v=@($Color.R,$Color.G,$Color.B)|ForEach-Object{
        $x=[double]$_/255
        if($x -le 0.04045){$x/12.92}else{[Math]::Pow(($x+0.055)/1.055,2.4)}
    }
    return 0.2126*$v[0]+0.7152*$v[1]+0.0722*$v[2]
}

if($Preview){
    $fixture=New-LoginFixture $Theme
    try{
        $fixture.Password.Clear()
        $work=[Windows.SystemParameters]::WorkArea
        if($fixture.Window.Height -gt $work.Height-24){
            $fixture.Window.MinHeight=[Math]::Min($fixture.Window.MinHeight,$work.Height-24)
            $fixture.Window.Height=$work.Height-24
        }
        [void]$fixture.Window.ShowDialog()
    }finally{$fixture.Password.Clear();$fixture.Window.Close()}
    return
}

try{
    foreach($mode in @('Light','Dark')){
        $fixture=$null
        try{
            $fixture=New-LoginFixture $mode
            Show-HiddenFixture $fixture
            Case "$mode : format compact sans agrandissement" {
                Assert-Layout ($fixture.Window.ResizeMode -eq [Windows.ResizeMode]::NoResize) 'Agrandissement encore autorise.'
                Assert-Layout ($fixture.Window.SizeToContent -eq [Windows.SizeToContent]::Height) 'Hauteur non adaptee au contenu.'
                Assert-Layout ($fixture.Window.Width -eq 460) 'Largeur du login incorrecte.'
                Assert-Layout ($fixture.Window.ActualHeight -lt 600) 'La fenetre de connexion est encore trop haute.'
                Assert-Layout ($fixture.Window.FindName('LoginFeedback').Visibility -eq 'Collapsed') 'Zone vide reservee aux erreurs.'
                Assert-Layout ($fixture.Window.FindName('ChkRememberUser').IsChecked -eq $false) 'Memorisation active sans choix sans consentement.'
            }
            Case "$mode : erreur visible et retour au format compact" {
                $before=$fixture.Window.ActualHeight
                $box=$fixture.Window.FindName('LoginFeedback');$err=$fixture.Window.FindName('LblErr')
                $box.Visibility='Visible';$err.Visibility='Visible'
                $err.Text='TEST : le controleur de domaine est injoignable. Verifier la connexion reseau, puis recommencer. Aucun vrai compte utilise.'
                Update-TestLayout $fixture.Window
                Assert-Layout ($fixture.Window.ActualHeight -gt $before) 'Erreur tronquee par une hauteur fixe.'
                Assert-ReadableField $fixture.User $mode
                Assert-ReadableField $fixture.Password $mode
                $box.Visibility='Collapsed';$err.Visibility='Collapsed';$err.Text=''
                Update-TestLayout $fixture.Window
                Assert-Layout ([Math]::Abs($fixture.Window.ActualHeight-$before) -lt 2) 'Espace vide conserve apres fermeture du message.'
            }
            Case "$mode : nom de compte entier, sans double marge" {Assert-ReadableField $fixture.User $mode}
            Case "$mode : puces du mot de passe, sans double marge" {Assert-ReadableField $fixture.Password $mode}
            Case "$mode : curseur et texte contrastes" {
                foreach($c in @($fixture.User,$fixture.Password)){
                    $a=Get-Luminance $c.Foreground.Color;$b=Get-Luminance $c.Background.Color
                    $ratio=([Math]::Max($a,$b)+0.05)/([Math]::Min($a,$b)+0.05)
                    Assert-Layout ($ratio -ge 4.5) 'Contraste texte/fond insuffisant.'
                    Assert-Layout ($c.CaretBrush.Color -eq $c.Foreground.Color) 'Couleur du curseur incoherente.'
                }
            }
            Case "$mode : hauteur flexible et champs centres" {
                foreach($c in @($fixture.User,$fixture.Password)){
                    Assert-Layout ([double]::IsNaN($c.Height)) 'Height fixe pouvant couper une police plus grande.'
                    Assert-Layout ($c.MinHeight -ge 44) 'Champ trop bas.'
                    Assert-Layout ($c.VerticalContentAlignment -eq 'Center') 'Texte non centre verticalement.'
                }
            }
            foreach($size in @(18,24)){
                Case "$mode : agrandissement de police a $size" {
                    $fixture.User.FontSize=$size;$fixture.Password.FontSize=$size
                    Update-TestLayout $fixture.Window
                    Assert-ReadableField $fixture.User $mode
                    Assert-ReadableField $fixture.Password $mode
                }
            }
            Case "$mode : saisie modifiable sans authentification" {
                $fixture.User.SelectAll();$fixture.User.SelectedText='Autre.identifiant'
                Update-TestLayout $fixture.Window
                Assert-Layout ($fixture.User.Text -eq 'Autre.identifiant') 'Edition de texte impossible.'
                Assert-Layout (-not $fixture.Window.FindName('BtnOk').IsEnabled) 'Authentification active dans un test.'
                Assert-Layout (-not $fixture.Window.FindName('BtnWindows').IsEnabled) 'Session Windows active dans un test.'
            }
        }finally{if($fixture){$fixture.Password.Clear();$fixture.Window.Close()}}
    }
    Case 'Controle negatif : le template RC6 reintroduit est bien detecte comme coupe' {
        $bad=$null
        try{
            $bad=New-LoginFixture 'Light' -LegacyPadding
            Show-HiddenFixture $bad
            foreach($c in @($bad.User,$bad.Password)){
                $g=Get-FieldGeometry $c 'RC6-negative-control'
                Assert-Layout (-not $g.Fits) 'La reproduction RC6 ne montre pas le defaut attendu.'
            }
        }finally{if($bad){$bad.Password.Clear();$bad.Window.Close()}}
    }
}catch{
    # Echec hors d'un controle (preparation d'une fenetre) : visible dans le rapport, puis relance.
    $results.Add([pscustomobject]@{Name='Execution interrompue hors controle';Passed=$false;Error=$_.Exception.Message})
    Write-Host "KO  Execution interrompue hors controle : $($_.Exception.Message)"
    throw
}finally{
    $failed=@($results|Where-Object{-not $_.Passed}).Count
    [pscustomobject]@{
        Utc=[DateTime]::UtcNow.ToString('o');SourceSHA256=(Get-FileHash -LiteralPath $CorePath -Algorithm SHA256).Hash
        ShellSHA256=(Get-FileHash -LiteralPath $shellPath -Algorithm SHA256).Hash
        ThemeSourceSHA256=(Get-FileHash -LiteralPath $themePath -Algorithm SHA256).Hash
        Scope='WPF local : layout login, aucune execution du moteur et aucun acces AD. Ne certifie pas tous les DPI/ecrans.'
        Total=$results.Count;Failed=$failed;Tests=$results.ToArray();Geometry=$measurements.ToArray()
    }|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $ReportPath -Encoding UTF8
}
if($failed){throw "$failed test(s) de saisie en echec. Rapport : $ReportPath"}
Write-Host "Tests de saisie termines : $($results.Count) controles. Rapport : $ReportPath"
