#requires -Version 5.1
# Présentation et préparations locales ; aucune mutation AD au chargement.

function Get-PestoChoiceSearchKeys {
    param([object[]]$Columns=@(),[string[]]$SearchProperties=@())
    $keys=@(@($Columns|ForEach-Object{[string]$_.Key})+@($SearchProperties)|Select-Object -Unique)
    if($keys.Count -gt 32){throw 'Trop de champs de recherche.'}
    foreach($key in $keys){if($key -notmatch '^[A-Za-z_][A-Za-z0-9_]*$'){throw 'Champ de recherche invalide.'};$key}
}
function New-PestoChoiceSearchIndex {
    param([object[]]$Rows=@(),[string[]]$Keys=@())
    if($Rows.Count -gt 10000){throw 'Recherche limitée à 10 000 lignes.'}
    [void]@(Get-PestoChoiceSearchKeys -SearchProperties $Keys)
    $projection=[Collections.Generic.List[object]]::new();$total=0
    foreach($row in $Rows){
        $builder=[Text.StringBuilder]::new()
        foreach($key in $Keys){[void]$builder.Append([string]$row.$key);[void]$builder.Append(' ')}
        $total+=$builder.Length
        if($total -gt 16777216){throw 'Tableau trop volumineux pour la recherche. Réduisez le périmètre.'}
        $projection.Add([pscustomobject]@{Row=$row;Text=(ConvertTo-PestoSearchText $builder.ToString())})
    }
    return $projection.ToArray()
}
function Get-PestoFilteredChoiceRows {
    param([object[]]$Rows=@(),[string[]]$Keys=@(),[string]$Query='',[AllowNull()]$SearchIndex=$null)
    if($Rows.Count -gt 10000 -or $Query.Length -gt 256){throw 'Recherche trop volumineuse.'}
    if($null -eq $SearchIndex){$SearchIndex=@(New-PestoChoiceSearchIndex -Rows $Rows -Keys $Keys)}
    $normalized=ConvertTo-PestoSearchText $Query
    foreach($entry in $SearchIndex){if(-not $normalized -or $entry.Text.Contains($normalized)){$entry.Row}}
}
function Update-PestoChoiceSearch {
    param($State)
    if(-not $State -or $State.Closed){return}
    $State.Timer.Stop()
    $filtered=@(Get-PestoFilteredChoiceRows -SearchIndex $State.SearchIndex -Query $State.Search.Text)
    $State.Grid.ItemsSource=$filtered
    Set-PestoChoiceGrouping $State.Grid $State.GroupBy
    $State.Count.Text=([string]$filtered.Count+' / '+$State.Rows.Count+' résultat(s)')
    $State.Accept.IsEnabled=($State.Grid.SelectedItems.Count -gt 0)
    $State.Secondary.IsEnabled=$State.Accept.IsEnabled
}

function Show-PestoChoiceTable {
    param([string]$Title,[string]$Description='',[object[]]$Rows=@(),[object[]]$Columns=@(),[string]$AcceptText='', [switch]$Multiple,[string]$GroupBy='',[string]$SecondaryText='',[string[]]$SearchProperties=@())
    if($Rows.Count -gt 10000){throw 'La vue est limitée à 10 000 lignes. Réduisez le périmètre.'}
    [xml]$x=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Width="1000" Height="680" MinWidth="320" MinHeight="340" WindowStartupLocation="CenterOwner" Background="{DynamicResource BgWindow}" Foreground="{DynamicResource FgText}" FontFamily="Segoe UI" FontSize="13"><Grid Margin="20"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions><TextBlock x:Name="Title" FontSize="22" FontWeight="SemiBold" TextWrapping="Wrap"/><TextBlock x:Name="Description" Grid.Row="1" TextWrapping="Wrap" Margin="0,8,0,12"/><DockPanel Grid.Row="2" Margin="0,0,0,10"><TextBlock Text="Rechercher" VerticalAlignment="Center" Margin="0,0,12,0"/><TextBox x:Name="Search" MaxLength="256" AutomationProperties.Name="Rechercher dans le tableau" AutomationProperties.HelpText="Filtrer les données déjà chargées ; aucune lecture réseau." ToolTip="Filtrer les données déjà chargées ; aucune lecture réseau."/></DockPanel><DataGrid x:Name="Rows" Grid.Row="3" IsReadOnly="True" AutoGenerateColumns="False" CanUserAddRows="False" CanUserDeleteRows="False" EnableRowVirtualization="True" EnableColumnVirtualization="True" VirtualizingPanel.IsVirtualizingWhenGrouping="True" SelectionMode="Single" SelectionUnit="FullRow" AutomationProperties.Name="Résultats"/><WrapPanel Grid.Row="4" Margin="0,14,0,0" HorizontalAlignment="Right"><TextBlock x:Name="Count" Margin="0,0,14,6" VerticalAlignment="Center"/><Button x:Name="Cancel" Content="Fermer" IsCancel="True" IsDefault="True" Margin="0,0,8,6" AutomationProperties.HelpText="Fermer sans appliquer de changement." ToolTip="Fermer sans appliquer de changement."/><Button x:Name="Secondary" Visibility="Collapsed" Margin="0,0,8,6" IsEnabled="False" AutomationProperties.HelpText="Appliquer seulement l’action secondaire explicitement nommée sur la sélection."/><Button x:Name="Accept" Visibility="Collapsed" Margin="0,0,0,6" IsEnabled="False" Style="{DynamicResource BtnAdd}" AutomationProperties.HelpText="Utiliser uniquement la sélection affichée. Aucun poste ne sera modifié ici." ToolTip="Utiliser uniquement la sélection affichée. Aucun poste ne sera modifié ici."/></WrapPanel></Grid></Window>
'@
    $w=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($x));$w.Owner=$Win;$w.Resources=$Win.Resources;$w.Title=$Title;$w.FindName('Title').Text=$Title;$w.FindName('Description').Text=$Description
    $grid=$w.FindName('Rows');if($GroupBy -and $GroupBy -notin @($Columns.Key)){throw 'Critère de regroupement absent.'};if($Multiple){$grid.SelectionMode='Extended'}
    foreach($c in $Columns){$column=[Windows.Controls.DataGridTextColumn]::new();$column.Header=[string]$c.Label;$column.Binding=[Windows.Data.Binding]::new([string]$c.Key);$column.Width=[Windows.Controls.DataGridLength]::new(1,[Windows.Controls.DataGridLengthUnitType]::Star);$grid.Columns.Add($column)}
    $state=[pscustomobject]@{Window=$w;Grid=$grid;Rows=@($Rows);Keys=@(Get-PestoChoiceSearchKeys -Columns $Columns -SearchProperties $SearchProperties);GroupBy=$GroupBy;Count=$w.FindName('Count');Accept=$w.FindName('Accept');Secondary=$w.FindName('Secondary');Result=[pscustomobject]@{Accepted=$false;Secondary=$false;Items=@()}}
    $grid.ItemsSource=@($Rows);Set-PestoChoiceGrouping $grid $GroupBy;$state.Count.Text=([string]$Rows.Count+' résultat(s)');$grid.Tag=$state
    $grid.Add_SelectionChanged({param($s,$e);$s.Tag.Accept.IsEnabled=($s.SelectedItems.Count -gt 0);$s.Tag.Secondary.IsEnabled=($s.SelectedItems.Count -gt 0)})
    $search=$w.FindName('Search');$search.Tag=$state
    $state|Add-Member NoteProperty SearchIndex @(New-PestoChoiceSearchIndex -Rows $Rows -Keys $state.Keys)
    $state|Add-Member NoteProperty Search $search
    $state|Add-Member NoteProperty Closed $false
    $timer=[Windows.Threading.DispatcherTimer]::new();$timer.Interval=[TimeSpan]::FromMilliseconds(220)
    $state|Add-Member NoteProperty Timer $timer
    $tick=[EventHandler]{param($sender,$eventArgs) Update-PestoChoiceSearch $state}.GetNewClosure()
    $timer.Add_Tick($tick)
    $search.Add_TextChanged({param($s,$e)
        $u=$s.Tag;if($u.Closed){return};$u.Timer.Stop()
        $u.Accept.IsEnabled=$false;$u.Secondary.IsEnabled=$false;$u.Count.Text='Recherche…';$u.Timer.Start()
    })
    $w.Add_Closed([EventHandler]{param($sender,$eventArgs)
        $state.Closed=$true;$state.Timer.Stop();$state.Timer.Remove_Tick($tick);$state.SearchIndex=@()
    }.GetNewClosure())
    if($AcceptText){$state.Accept.Visibility='Visible';$state.Accept.Content=$AcceptText;$state.Accept.Tag=$state;$state.Accept.Add_Click({param($s,$e);$u=$s.Tag;if($u.Grid.SelectedItems.Count){$u.Result.Accepted=$true;$u.Result.Items=@($u.Grid.SelectedItems);$u.Window.Close()}})}
    if($SecondaryText){$state.Secondary.Content=$SecondaryText;$state.Secondary.Visibility='Visible';$state.Secondary.Tag=$state;$state.Secondary.Add_Click({param($s,$e);$u=$s.Tag;if($u.Grid.SelectedItems.Count){$u.Result.Accepted=$true;$u.Result.Secondary=$true;$u.Result.Items=@($u.Grid.SelectedItems);$u.Window.Close()}})}
    $w.FindName('Cancel').Tag=$w;$w.FindName('Cancel').Add_Click({param($s,$e);$s.Tag.Close()})
    Set-WindowIcon $w;[void](Show-PestoHostedWindow $w);return $state.Result
}

function Get-PestoPageShortcut {
    param([int]$Page,[string]$Mode='Single',[ValidateSet('Search','Refresh')][string]$Action='Search')
    if($Action -eq 'Search'){
        switch($Page){
            0 {if($Mode -eq 'Single'){'Source'}else{'Queue'}}
            1 {'Names'};2 {'Settings'};3 {'Log'};4 {'Home'};5 {'History'};7 {'Join'}
        }
    }else{
        switch($Page){0 {if($Mode -eq 'Single'){'Source'}else{'Queue'}};1 {'Names'};2 {'Settings'};3 {'Log'};4 {'Home'};5 {'History'};7 {'Join'}}
    }
}
function Invoke-PestoPageShortcut {
    param([ValidateSet('Search','Refresh')][string]$Action)
    if($script:PestoPanelStack -and $script:PestoPanelStack.Count){return $false}
    $route=Get-PestoPageShortcut -Page ([int]$MainTabs.SelectedIndex) -Mode ([string]$script:SuiteMode) -Action $Action
    if(-not $route){return $false}
    if($Action -eq 'Search'){
        $control=$null
        switch($route){
            'Source' {$control=$TxtPCName};'Queue' {$control=$TxtQueueSearch};'Names' {$control=$NmTxtSearch}
            'Log' {$control=$Win.FindName('SuiteLogSearch')}
            'Join' {if($script:JoinUI){$control=$script:JoinUI.Name}}
            'Settings' {Show-PestoSettingSearch;return $true}
            'Home' {
                $rows=@($Win.FindName('HomeRecentList').ItemsSource)
                [void](Show-PestoChoiceTable -Title 'Rechercher dans les interventions récentes' -Rows $rows -Columns @(@{Key='Target';Label='Poste'},@{Key='ResultLine';Label='Résultat et date'},@{Key='NextAction';Label='Suite'}) -SearchProperties @('RowId'))
                return $true
            }
            'History' {
                [void](Show-PestoChoiceTable -Title 'Rechercher dans l’’historique affiché' -Rows @($UxHistoryGrid.ItemsSource) -Columns @(@{Key='LocalDate';Label='Date'},@{Key='Mode';Label='Mode'},@{Key='Total';Label='Postes'},@{Key='Failed';Label='Échecs'},@{Key='RunId';Label='Lot'}))
                return $true
            }
        }
        if($control -and $control.IsVisible -and $control.IsEnabled){[void]$control.Focus();if($control -is [Windows.Controls.TextBox]){$control.SelectAll()};return $true}
        return $false
    }
    # La touche réutilise l'action visible et ses barrières. Elle n'exécute jamais un plan.
    if($route -eq 'Log'){$script:LogForceRefresh=$true;Render-Log;return $true}
    if($route -eq 'History'){Update-PestoUxHistory;return $true}
    if($route -eq 'Queue'){Update-PestoQueueFilter;return $true}
    if($script:Running -or $script:PreflightRunning -or $script:DirectBusy -or $script:JoinBusy){return $true}
    switch($route){
        'Source' {Select-PCName}
        'Names' {if($NmBtnRefresh.IsEnabled){Refresh-Names|Out-Null}}
        'Settings' {if($SetBtnReload.IsEnabled){Reload-CfgFromDisk}}
        'Home' {$button=$Win.FindName('HomeRefresh');if($button.IsEnabled){Invoke-PestoHomeCommand $button $null}}
        'Join' {Start-PestoJoinStatus}
    }
    return $true
}

function Show-PestoDetailsPane {
    param([string]$Title,[string]$Text)
    if(-not $Win -or -not $Win.IsVisible){Show-PestoTextReport $Title $Text;return}
    $root=$Win.FindName('SuiteRoot');if(-not $root){return}
    if($script:PestoDetailsPane){[void]$root.Children.Remove($script:PestoDetailsPane)}
    [xml]$x=@'
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" HorizontalAlignment="Right" VerticalAlignment="Stretch" Background="{DynamicResource BgCard}" BorderBrush="{DynamicResource ClrBorder}" BorderThickness="1" Padding="18" Margin="12" CornerRadius="10" KeyboardNavigation.TabNavigation="Cycle"><Grid><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions><TextBlock x:Name="Title" FontSize="20" FontWeight="SemiBold" TextWrapping="Wrap" Margin="0,0,0,12"/><TextBox x:Name="Detail" Grid.Row="1" IsReadOnly="True" AcceptsReturn="True" TextWrapping="Wrap" VerticalContentAlignment="Top" VerticalScrollBarVisibility="Auto" AutomationProperties.Name="Détails de la sélection"/><WrapPanel Grid.Row="2" Margin="0,12,0,0"><Button x:Name="Copy" Content="Copier" Margin="0,0,8,4" AutomationProperties.HelpText="Copier les détails affichés." ToolTip="Copier les détails affichés."/><Button x:Name="Close" Content="Fermer les détails" Margin="0,0,0,4" AutomationProperties.HelpText="Revenir au tableau sans modifier sa sélection." ToolTip="Revenir au tableau sans modifier sa sélection."/></WrapPanel></Grid></Border>
'@
    $pane=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($x));$pane.Width=[Math]::Min(450.0,[Math]::Max(260.0,$root.ActualWidth-24));$pane.FindName('Title').Text=$Title;$pane.FindName('Detail').Text=$Text
    [Windows.Controls.Grid]::SetColumnSpan($pane,99);[Windows.Controls.Grid]::SetRowSpan($pane,99);[Windows.Controls.Panel]::SetZIndex($pane,200)
    $state=[pscustomobject]@{Root=$root;Pane=$pane;Focus=[Windows.Input.Keyboard]::FocusedElement;Text=$Text}
    $pane.FindName('Close').Tag=$state;$pane.FindName('Close').Add_Click({param($s,$e);$u=$s.Tag;[void]$u.Root.Children.Remove($u.Pane);$script:PestoDetailsPane=$null;if($u.Focus){[void][Windows.Input.Keyboard]::Focus($u.Focus)}})
    $pane.FindName('Copy').Tag=$state;$pane.FindName('Copy').Add_Click({param($s,$e);try{[Windows.Clipboard]::SetText($s.Tag.Text)}catch{Show-MsgWarning 'Presse-papiers indisponible.'}})
    $script:PestoDetailsPane=$pane;[void]$root.Children.Add($pane);[void]$pane.FindName('Close').Focus()
}

function Get-PestoCommandMatches {
    param([object[]]$Commands=@(),[string]$Query='')
    if($Query.Length -gt 128 -or $Commands.Count -gt 100){throw 'Recherche trop volumineuse.'}
    $aliases=@{names='libre disponibilité candidat numéro nom';interventions='reçu rapport historique suivi état';'draft-save'='mémoriser enregistrer modèle';'draft-load'='rappeler reprendre restaurer modèle';capacity='plage épuisement places libres';settings='configuration réglages config cfg json';'save-columns'='tableau largeur disposition colonnes';diagnostic='support erreur incident dépannage';single='ordinateur machine renommer déplacer';batch='lot plusieurs file campagne import excel csv';density='zoom taille compact confort affichage'}
    $queryText=ConvertTo-PestoSearchText $Query;$words=@($queryText -split '\s+'|Where-Object{$_});$found=@(foreach($c in $Commands){
        $label=ConvertTo-PestoSearchText ([string]$c.Label);$hay=ConvertTo-PestoSearchText ($c.Label+' '+$c.Detail+' '+[string]$aliases[[string]$c.Id]);$match=$true
        foreach($word in $words){if(-not $hay.Contains($word)){$match=$false;break}}
        if($match){$score=if($label -ceq $queryText){0}elseif($label.StartsWith($queryText,[StringComparison]::Ordinal)){1}elseif($label.Contains($queryText)){2}else{3};[pscustomobject]@{Score=$score;Label=$label;Command=$c}}
    });foreach($m in @($found|Sort-Object Score,Label)){$m.Command}
}

function Get-PestoNameSegments {
    param([string]$Name,[string]$Previous='')
    $parts=ConvertTo-PestoNameParts $Name;$old=ConvertTo-PestoNameParts $Previous
    if(-not $parts){return @()}
    foreach($pair in @(@('Type','Type'),@('Préfixe','Prefix'),@('Site','Site'),@('Service','Service'),@('Numéro','Number'))){$key=$pair[1];[pscustomobject]@{Label=$pair[0];Value=$(if($key -eq 'Number'){([int]$parts.Number).ToString('D3')}else{[string]$parts.$key});Changed=($old -and [string]$parts.$key -cne [string]$old.$key)}}
}

function Find-PestoExactCandidate {
    param([string]$Name,[string[]]$Candidates=@())
    $value=$Name.Trim().ToUpperInvariant();if(-not(Test-PestoGeneratedComputerName $value)){throw 'Saisissez un nom Pesto complet valide.'}
    $found=@($Candidates|Where-Object{$_ -ieq $value}|Select-Object -First 1)
    if(-not $found.Count){throw 'Ce nom ne figure pas parmi les candidats libres du filtre actuel. Actualisez le site ou modifiez les filtres.'}
    return [string]$found[0]
}

function Invoke-PestoExactCandidate {
    if($script:DirectBusy -or $script:Running -or $script:PreflightRunning -or $script:JoinBusy -or $script:CfgRestartRequired){return}
    try{$answer=Show-PestoPanel -Title 'Choisir un nom exact' -Body 'Le nom doit appartenir aux candidats libres des filtres actuels. Le contrôle AD avant confirmation reste obligatoire.' -InputLabel 'Nom complet' -InitialValue ([string]$CbName.SelectedItem) -AcceptText 'Choisir ce candidat';if($answer.Accepted){$candidate=Find-PestoExactCandidate -Name $answer.Text -Candidates @($CbName.Items);$CbName.SelectedItem=$candidate;$script:DirectCheckedKey='';Select-NewName}}catch{Show-MsgWarning $_.Exception.Message}
}

function ConvertTo-PestoDraftCollection {
    param($Value)
    Assert-PestoClosedObject $Value @('Schema','Drafts') @('Schema','Drafts')
    if(($Value.Schema -isnot [int] -and $Value.Schema -isnot [long]) -or $Value.Schema -ne 1 -or @($Value.Drafts).Count -gt 20){throw 'Collection de brouillons invalide (20 maximum).'}
    $seen=@{};$items=@(foreach($item in @($Value.Drafts)){
        Assert-PestoClosedObject $item @('Name','UpdatedUtc','Draft') @('Name','UpdatedUtc','Draft')
        if($item.Name -isnot [string] -or $item.Name.Length -lt 1 -or $item.Name.Length -gt 64 -or $item.Name -match '[\x00-\x1f]' -or $seen.ContainsKey($item.Name)){throw 'Nom de brouillon invalide ou dupliqué.'}
        $date=[DateTimeOffset]::MinValue;if($item.UpdatedUtc -is [datetime]){$date=[DateTimeOffset]::new($item.UpdatedUtc.ToUniversalTime())}elseif(-not [DateTimeOffset]::TryParse([string]$item.UpdatedUtc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$date)){throw 'Date de brouillon invalide.'};$seen[$item.Name]=$true
        [pscustomobject]@{Name=$item.Name;UpdatedUtc=$date.ToUniversalTime().ToString('o');Draft=(ConvertTo-PestoDraft $item.Draft)}
    });return $items
}

function Read-PestoDraftCollection {
    $text=if($script:SIM -or $script:GUI){$script:PestoDraftsMemory}else{Get-PestoAppearanceValue -Name 'Drafts'}
    if(-not $text){return @()};if($text.Length -gt 262144){throw 'Brouillons enregistrés trop volumineux.'}
    return @(ConvertTo-PestoDraftCollection ($text|ConvertFrom-Json -ErrorAction Stop))
}

function Save-PestoNamedDraft {
    param([string]$Name,$Draft)
    $items=@(Read-PestoDraftCollection);$items=@($items|Where-Object{$_.Name -ine $Name})+@([pscustomobject]@{Name=$Name;UpdatedUtc=[DateTimeOffset]::UtcNow.ToString('o');Draft=$Draft})
    $data=[pscustomobject]@{Schema=1;Drafts=$items};[void](ConvertTo-PestoDraftCollection $data);$text=$data|ConvertTo-Json -Depth 8 -Compress
    if($text.Length -gt 262144){throw 'Collection trop volumineuse.'}
    if($script:SIM -or $script:GUI){$script:PestoDraftsMemory=$text}else{Set-PestoAppearanceValue -Name 'Drafts' -Value $text}
}

function Get-PestoNamedDraft {
    $items=@(Read-PestoDraftCollection);if(-not $items.Count){return $null}
    $choices=@(foreach($item in $items){[pscustomobject]@{Name=$item.Name;Computer=$item.Draft.Nom_du_PC;Domain=$item.Draft.Domain;Updated=$item.UpdatedUtc;Draft=$item.Draft}})
    $r=Show-PestoChoiceTable -Title 'Brouillons enregistrés' -Description 'Seuls les champs sont restaurés après relecture de la cible. Aucun accord, contrôle ou redémarrage ne sera réutilisé.' -Rows $choices -Columns @(@{Key='Name';Label='Brouillon'},@{Key='Computer';Label='Poste'},@{Key='Domain';Label='Domaine'},@{Key='Updated';Label='Date UTC'}) -AcceptText 'Prévisualiser' -SecondaryText 'Supprimer ce brouillon'
    if($r.Accepted -and $r.Secondary){if(Confirm-YesNo -Msg ('Supprimer uniquement le brouillon « '+$r.Items[0].Name+' » ? Les reçus restent conservés.') -Confirm $true -AcceptText 'Supprimer le brouillon'){$remaining=@($items|Where-Object{$_.Name -ine $r.Items[0].Name});$text=[pscustomobject]@{Schema=1;Drafts=$remaining}|ConvertTo-Json -Depth 12 -Compress;if($script:SIM -or $script:GUI){$script:PestoDraftsMemory=$text}else{Set-PestoAppearanceValue -Name 'Drafts' -Value $text}};return $null}
    if($r.Accepted){return $r.Items[0].Draft};return $null
}

function Get-PestoFocusZoneContainer {
    param($Control,[string[]]$Types=@('Border'))
    $ancestor=$Control
    for($depth=0;$ancestor -and $depth -lt 64;$depth++){
        if($ancestor.GetType().Name -in $Types){return $ancestor}
        $ancestor=$ancestor.Parent
    }
    return $Control
}
function Get-PestoNextFocusZoneTarget {
    param([object[]]$Zones=@(),[bool]$Reverse=$false)
    $available=@($Zones|Where-Object{$_.Target -and $_.Target.IsVisible -and $_.Target.IsEnabled -and $_.Target.Focusable})
    if(-not $available.Count){return $null}
    $current=-1
    for($i=0;$i -lt $available.Count;$i++){
        if($available[$i].Root.IsKeyboardFocusWithin -or $available[$i].Target.IsKeyboardFocusWithin){$current=$i;break}
    }
    $next=if($current -lt 0){if($Reverse){$available.Count-1}else{0}}else{($current+$(if($Reverse){-1}else{1})+$available.Count)%$available.Count}
    return $available[$next].Target
}
function Invoke-PestoFocusZone {
    param([bool]$Reverse=$false)
    if($script:PestoPanelStack -and $script:PestoPanelStack.Count){return}
    $zones=@([pscustomobject]@{Target=$Win.FindName('NavHome');Root=$Win.FindName('SuiteSidebarGrid')})
    switch([int]$MainTabs.SelectedIndex){
        0 {
            $zones+=@([pscustomobject]@{Target=$TxtPCName;Root=(Get-PestoFocusZoneContainer $TxtPCName)},[pscustomobject]@{Target=$CbName;Root=(Get-PestoFocusZoneContainer $CbName)})
            if($script:SuiteMode -eq 'Batch'){$zones+=[pscustomobject]@{Target=$Grid;Root=$Win.FindName('QueueCard')}}else{$zones+=[pscustomobject]@{Target=$Win.FindName('SuiteDirectRun');Root=$Win.FindName('SuiteDirectCommands')}}
        }
        1 {foreach($target in @($NmTxtSearch,$NmGrid,$Win.FindName('NmUseCandidate'))){$zones+=[pscustomobject]@{Target=$target;Root=(Get-PestoFocusZoneContainer $target)}}}
        3 {$search=$Win.FindName('SuiteLogSearch');$zones+=@([pscustomobject]@{Target=$search;Root=(Get-PestoFocusZoneContainer $search @('StackPanel'))},[pscustomobject]@{Target=$LogBox;Root=(Get-PestoFocusZoneContainer $LogBox)})}
        default {$zones+=[pscustomobject]@{Target=$MainTabs;Root=$MainTabs}}
    }
    $zones+=[pscustomobject]@{Target=$Win.FindName('PestoZoomReset');Root=$Win.FindName('PestoZoomBar')}
    $target=Get-PestoNextFocusZoneTarget -Zones $zones -Reverse $Reverse
    if($target){[void]$target.Focus();$target.BringIntoView()}
}

function Set-PestoAccessibleStatus {
    param([string]$Text)
    if(-not $Win -or -not $Text -or $script:PestoAnnouncedStatus -ceq $Text){return}
    $control=$Win.FindName('PestoStatusAnnouncement');if(-not $control){return}
    $script:PestoAnnouncedStatus=$Text;$control.Text=$Text
    $peer=[Windows.Automation.Peers.UIElementAutomationPeer]::FromElement($control)
    if($peer){$peer.RaiseAutomationEvent([Windows.Automation.Peers.AutomationEvents]::LiveRegionChanged)}
}

function Initialize-PestoWorkbench {
    $script:PestoNotifyBatch=((Get-PestoAppearanceValue -Name 'NotifyBatch') -eq 'true')
    $notify=$Win.FindName('PestoNotifyBatch');if($notify){$notify.IsChecked=$script:PestoNotifyBatch;$notify.Add_Click({param($s,$e);try{Set-PestoAppearanceValue -Name 'NotifyBatch' -Value ([string][bool]$s.IsChecked).ToLowerInvariant();$script:PestoNotifyBatch=[bool]$s.IsChecked}catch{$s.IsChecked=$script:PestoNotifyBatch;Set-PestoPersistenceWarning $_.Exception.Message}})}
    $button=$Win.FindName('PestoExactName');if($button){$button.Add_Click({Invoke-PestoExactCandidate})}
    $button=$Win.FindName('PestoNextOperation');if($button){$button.Add_Click({
        if($script:DirectBusy -or $script:Running -or $script:JoinBusy -or $script:PreflightRunning){return}
        $script:DirectCheckedKey='';$ChkReboot.IsChecked=$false;Set-PestoSuiteMode 'Single';[void]$TxtPCName.Focus();$TxtPCName.SelectAll()
        Set-PestoAccessibleStatus 'Préparez le poste suivant. Les reçus sont conservés ; aucune opération n''a été relancée.'
    })}
}

function Set-PestoChoiceGrouping {
    param($Grid,[string]$Property)
    if(-not$Property){return}
    $view=[Windows.Data.CollectionViewSource]::GetDefaultView($Grid.ItemsSource);if($view -and $view.CanGroup){$view.GroupDescriptions.Clear();$view.GroupDescriptions.Add([Windows.Data.PropertyGroupDescription]::new($Property));if(-not$Grid.GroupStyle.Count){$style=[Windows.Controls.GroupStyle]::new();[xml]$template='<DataTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"><TextBlock Text="{Binding Name}" FontWeight="SemiBold" Margin="8,12,8,6"/></DataTemplate>';$style.HeaderTemplate=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($template));$Grid.GroupStyle.Add($style)}}
}
