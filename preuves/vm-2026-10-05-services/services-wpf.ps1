# Liste des services de la jonction et libellés de Noms : comportement WPF réel sous Windows PowerShell 5.1 (STA, sans bureau).
# Charge le vrai Pesto-Join.xaml, le vrai Pesto-Shell.xaml et les vraies fonctions ; doubles pour l'interface voisine.
param([string]$Wad='C:\PestoTest\wad')
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$script:R=[Collections.Generic.List[string]]::new()
function Check([string]$Name,[bool]$Ok,[string]$Detail=''){ $script:R.Add($(if($Ok){'PASS '}else{'FAIL '})+$Name+$(if(-not $Ok -and $Detail){' :: '+$Detail}else{''})) }
function Import-Fn([string]$File,[string[]]$Names){
    $t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Wad $File),[ref]$t,[ref]$e)
    if(@($e).Count){throw "Syntaxe $File : $($e[0].Message)"}
    $sb=[Text.StringBuilder]::new()
    foreach($n in $Names){$f=@($ast.FindAll({param($x) $x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $n},$true));if(-not $f.Count){throw "Fonction absente : $n"};[void]$sb.AppendLine($f[0].Extent.Text)}
    return $sb.ToString()
}
. ([scriptblock]::Create((Import-Fn 'Pesto-Contracts.ps1' @('ConvertTo-PestoNameParts'))))
. ([scriptblock]::Create((Import-Fn 'Pesto-Core.ps1' @('ConvertTo-PestoRdnValue','Get-SiteTag'))))
. ([scriptblock]::Create((Import-Fn 'Pesto-Directory.ps1' @('Get-PestoSiteServiceCodes'))))
. ([scriptblock]::Create((Import-Fn 'Pesto-Join.ps1' @('Update-PestoJoinServices','Set-PestoJoinServiceEntry','Invoke-PestoJoinInputChanged'))))
# Doubles : pas d'AD, pas de minuteur réel, pas d'interface voisine.
$script:Requests=0;$script:UiUpdates=0
function Request-PestoJoinInventory {$script:Requests++}
function Update-PestoJoinUI {$script:UiUpdates++}
function Set-PestoJoinMessage {param($a,$b)}
$script:JoinInputTimer=[pscustomobject]@{}|Add-Member -MemberType ScriptMethod -Name Stop -Value {} -PassThru|Add-Member -MemberType ScriptMethod -Name Start -Value {$script:TimerStarts++} -PassThru
$script:TimerStarts=0
$script:PREFIXE='123456';$script:RuntimeTags=$null;$script:PREPRODSITE='765'
$script:CFG=[pscustomobject]@{TAGS=@([pscustomobject]@{Site='Paris';Tag='PA'},[pscustomobject]@{Site='Lyon';Tag='LY'})}
$script:PRD=$true;$script:OUV=@{'CPAM'='OU=Postes,DC=lab,DC=test'};$script:Sites=@{'CPAM'=@('Lyon','Paris')}
$script:Computers=@(
    [pscustomobject]@{Name='P123456PAINF001';DistinguishedName='CN=P123456PAINF001,OU=Paris,OU=Postes,DC=lab,DC=test'},
    [pscustomobject]@{Name='S123456PARH0002';DistinguishedName='CN=S123456PARH0002,OU=Etage 2,OU=Paris,OU=Postes,DC=lab,DC=test'},
    [pscustomobject]@{Name='P123456LYDIR001';DistinguishedName='CN=P123456LYDIR001,OU=Lyon,OU=Postes,DC=lab,DC=test'})
$script:ComputersNoms=@([pscustomobject]@{Name='V123456PAADM003'})
& {
    'moteur : '+$PSVersionTable.PSVersion+' '+$PSVersionTable.PSEdition+' ; STA='+([Threading.Thread]::CurrentThread.ApartmentState)
    $reader=[Xml.XmlReader]::Create((Join-Path $Wad 'Pesto-Join.xaml'))
    try{$view=[Windows.Markup.XamlReader]::Load($reader)}finally{$reader.Dispose()}
    $ui=@{View=$view};foreach($k in @{Org='JnOrg';Site='JnSite';Service='JnService';Name='JnName';Checks='JnChecks';Start='JnStart';Check='JnCheck'}.GetEnumerator()){$ui[$k.Key]=$view.FindName($k.Value)}
    $script:JoinUI=$ui
    Check 'JnService est une liste éditable' (($ui.Service -is [Windows.Controls.ComboBox]) -and $ui.Service.IsEditable) ([string]$ui.Service.GetType().FullName)
    $script:JoinSuspend=$true
    [void]$ui.Org.Items.Add('CPAM');$ui.Org.SelectedIndex=0;foreach($s in $script:Sites['CPAM']){[void]$ui.Site.Items.Add($s)};$ui.Site.SelectedItem='Paris'
    $script:JoinSuspend=$false
    Update-PestoJoinServices
    Check 'Liste des services de Paris' ((@($ui.Service.Items) -join ',') -eq 'ADM,INF,RH0') (@($ui.Service.Items) -join ',')
    $ui.Service.Text='CPT'
    Update-PestoJoinServices
    Check 'Saisie libre conservée après actualisation de la liste' ($ui.Service.Text -eq 'CPT') $ui.Service.Text
    $ui.Site.SelectedItem='Lyon'
    Update-PestoJoinServices
    Check 'Liste des services de Lyon' ((@($ui.Service.Items) -join ',') -eq 'DIR') (@($ui.Service.Items) -join ',')
    # Zone éditable : le gabarit doit être appliqué ; on héberge la vue dans une fenêtre non affichée.
    $w=[Windows.Window]::new();$w.Content=$view;$w.Measure([Windows.Size]::new(900,700));$w.Arrange([Windows.Rect]::new(0,0,900,700))
    [void]$ui.Service.ApplyTemplate()
    Set-PestoJoinServiceEntry $ui.Service $null
    $box=$ui.Service.Template.FindName('PART_EditableTextBox',$ui.Service)
    Check 'Zone éditable : 3 caractères, majuscules' ($box -and $box.MaxLength -eq 3 -and $box.CharacterCasing -eq [Windows.Controls.CharacterCasing]::Upper) $(if($box){"MaxLength=$($box.MaxLength) Casing=$($box.CharacterCasing)"}else{'zone absente'})
    # Événements réels : frappe (TextChanged routé) puis choix dans la liste.
    $ui.Service.AddHandler([Windows.Controls.Primitives.TextBoxBase]::TextChangedEvent,[Windows.Controls.TextChangedEventHandler]${function:Invoke-PestoJoinInputChanged})
    $ui.Org.Add_SelectionChanged([Windows.Controls.SelectionChangedEventHandler]${function:Invoke-PestoJoinInputChanged})
    $ui.Site.Add_SelectionChanged([Windows.Controls.SelectionChangedEventHandler]${function:Invoke-PestoJoinInputChanged})
    $script:JoinGeneration=0;$script:JoinBusy=$false;$script:JoinSuspend=$false
    $box.Text='INF'
    Check 'Frappe dans la liste : brouillon invalidé et noms recalculés' ($script:JoinGeneration -ge 1 -and $script:TimerStarts -ge 1) "generation=$($script:JoinGeneration) timer=$($script:TimerStarts)"
    $g=$script:JoinGeneration;$ui.Service.SelectedItem='DIR'
    Check 'Choix dans la liste : texte et événement' ($ui.Service.Text -eq 'DIR' -and $script:JoinGeneration -gt $g) "texte=$($ui.Service.Text) generation=$($script:JoinGeneration)"
    $req=$script:Requests;$ui.Site.SelectedItem='Paris'
    Check 'Changement de site : liste refaite et inventaire demandé' ((@($ui.Service.Items) -join ',') -eq 'ADM,INF,RH0' -and $script:Requests -gt $req) ("items="+(@($ui.Service.Items) -join ',')+" demandes=$($script:Requests)")
    $script:JoinSuspend=$true;$ui.Service.Text='';$script:JoinSuspend=$false
    # Page Noms : libellés réels de la fenêtre principale.
    $raw=[IO.File]::ReadAllText((Join-Path $Wad 'Pesto-Shell.xaml'))
    $shell=[Windows.Markup.XamlReader]::Parse($raw)
    $grid=$shell.FindName('NmGrid');$headers=@($grid.Columns|ForEach-Object{[string]$_.Header})
    Check 'Noms : colonne Service, aucune colonne Équipe' (($headers -contains 'Service') -and -not ($headers -match 'quipe')) ($headers -join ',')
    $combo=$shell.FindName('NmCmbEquipe');$panel=[Windows.Media.VisualTreeHelper]::GetParent($combo);if(-not $panel){$panel=$combo.Parent}
    $labels=@($panel.Children|Where-Object{$_ -is [Windows.Controls.TextBlock]}|ForEach-Object{$_.Text})
    Check 'Noms : filtre libellé Service' (($labels -contains 'Service') -and -not ($labels -match 'quipe')) ($labels -join ',')
} *>&1 | ForEach-Object { $_ }
$script:R
$f=@($script:R|Where-Object{$_ -like 'FAIL*'}).Count
'RESULTAT {0} reussis, {1} echecs' -f ($script:R.Count-$f),$f
if($f){exit 1}
