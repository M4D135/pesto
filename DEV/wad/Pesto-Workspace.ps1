#requires -Version 5.1
# Panneaux intégrés et commandes de préparation. Aucun accès réseau au chargement.

function Invoke-PestoPanelButton {
    param($Sender,$EventArgs)
    $s=$Sender.Tag
    if(-not $s){return}
    switch($Sender.Name){
        'PanelCopy' {try{[Windows.Clipboard]::SetText($s.Body.Text)}catch{$s.Hint.Text='Presse-papiers indisponible.'};return}
        'PanelAccept' {if($s.Searchable -and -not $s.Choices.SelectedItem){return};$s.Result.Accepted=$true;$s.Result.Text=[string]$s.Input.Text;$s.Result.Selected=$s.Choices.SelectedItem}
        default {$s.Result.Accepted=$false}
    }
    $s.Frame.Continue=$false
}

function Invoke-PestoPanelKey {
    param($Sender,$EventArgs)
    $s=$Sender.Tag;if(-not $s){return}
    if($EventArgs.Key -eq [Windows.Input.Key]::Escape){$s.Result.Accepted=$false;$s.Frame.Continue=$false;$EventArgs.Handled=$true;return}
    if(-not $s.Searchable){return}
    if($s.Search.IsKeyboardFocusWithin -or $s.Choices.IsKeyboardFocusWithin){
        if($EventArgs.Key -eq [Windows.Input.Key]::Enter){if($s.Choices.SelectedItem){Invoke-PestoPanelButton $s.Accept $null};$EventArgs.Handled=$true}
        elseif($EventArgs.Key -in @([Windows.Input.Key]::Down,[Windows.Input.Key]::Up)){
            if($s.Choices.Items.Count){$delta=if($EventArgs.Key -eq [Windows.Input.Key]::Down){1}else{-1};$index=[Math]::Max(0,[Math]::Min($s.Choices.Items.Count-1,$s.Choices.SelectedIndex+$delta));$s.Choices.SelectedIndex=$index;$s.Choices.ScrollIntoView($s.Choices.SelectedItem)}
            $EventArgs.Handled=$true
        }
    }
}

function Get-PestoPaletteChoices {
    param([object[]]$Commands=@(),[string]$Query='',[string]$Category='')
    # A typed search always spans every category. Browsing a tab is local only
    # while the search is empty; neither path invokes the selected command.
    if(-not [string]::IsNullOrWhiteSpace($Query)){return @(Get-PestoCommandMatches -Commands $Commands -Query $Query)}
    if($Category){return @($Commands | Where-Object {$_.Category -eq $Category})}
    return @($Commands)
}

function Invoke-PestoPaletteSearch {
    param($Sender,$EventArgs)
    $s=$Sender.Tag;if(-not $s -or -not $s.Searchable){return}
    $selected=$s.Choices.SelectedItem
    $category=if($s.Categories -and $s.Categories.Visibility -eq 'Visible' -and $s.Categories.SelectedItem){[string]$s.Categories.SelectedItem.Tag}else{''}
    $found=@(Get-PestoPaletteChoices -Commands $s.AllChoices -Query $s.Search.Text -Category $category)
    $s.Choices.ItemsSource=$found
    if($selected -and $selected -in $found){$s.Choices.SelectedItem=$selected}else{$s.Choices.SelectedIndex=if($found.Count){0}else{-1}}
    $s.Accept.IsEnabled=($found.Count -gt 0)
    $scope=if(-not [string]::IsNullOrWhiteSpace($s.Search.Text)){'Recherche dans toutes les rubriques.'}elseif($category){'Rubrique : '+[string]$s.Categories.SelectedItem.Header+'.'}else{''}
    $s.Hint.Text=if($found.Count){"$scope $($found.Count) commande(s). Entrée pour ouvrir, Échap pour fermer.".Trim()}else{'Aucun résultat dans les outils. Modifiez la recherche.'}
}

function Invoke-PestoPaletteCategory {
    param($Sender,$EventArgs)
    if($EventArgs -and $EventArgs.OriginalSource -ne $Sender){return}
    $s=$Sender.Tag;if(-not $s){return}
    # Choosing a category returns to browsing. Clearing the search triggers the
    # same read-only filter; selecting a tab never runs a command.
    if($s.Search.Text){$s.Search.Text=''}
    Invoke-PestoPaletteSearch $s.Search $null
}

function Get-PestoPanelLayout {
    # Finite measurements keep report scrolling local and preserve the footer.
    param([double]$Width=1000,[double]$Height=700,[string]$Text='',[int]$ChoicesCount=0,[bool]$Searchable=$false,[bool]$HasInput=$false,[int]$SummaryCount=0)
    if([double]::IsNaN($Width) -or [double]::IsInfinity($Width) -or $Width -le 0){$Width=1000}
    if([double]::IsNaN($Height) -or [double]::IsInfinity($Height) -or $Height -le 0){$Height=700}
    $panelWidth=[Math]::Min(1000.0,[Math]::Max(280.0,$Width-32))
    $characters=[Math]::Max(24,[int](($panelWidth-68)/7))
    $lines=0;foreach($line in @($Text -split '\r?\n')){$lines += [Math]::Max(1,[int][Math]::Ceiling($line.Length/[double]$characters))}
    $desired=170.0+[Math]::Min(420.0,$lines*19.0)+$(if($HasInput){76}else{0})+[Math]::Min(180,$SummaryCount*48)
    if($Searchable){$desired=620.0}elseif($ChoicesCount -gt 0){$desired += [Math]::Min(220.0,$ChoicesCount*36.0)}
    [pscustomobject]@{Width=$panelWidth;Height=[Math]::Min([Math]::Max(220.0,$Height-32),[Math]::Max(240.0,$desired))}
}

function ConvertTo-PestoConfirmationRows {
    param([object[]]$Rows=@())
    if($Rows.Count -gt 12){throw 'Trop de champs dans la confirmation.'}
    foreach($row in $Rows){
        if(-not $row -or -not [string]$row.Field){throw 'Champ de confirmation absent.'}
        foreach($name in @('Field','Before','After')){if(([string]$row.$name).Length -gt 2048 -or ([string]$row.$name) -match '[\x00-\x08\x0b\x0c\x0e-\x1f]'){throw 'Champ de confirmation invalide.'}}
        [pscustomobject]@{Field=[string]$row.Field;Before=[string]$row.Before;After=[string]$row.After;Changed=([string]$row.Before -cne [string]$row.After)}
    }
}

function Show-PestoPanel {
    param([string]$Title,[string]$Body='', [string]$AcceptText='',[string]$InputLabel='',[string]$InitialValue='', [object[]]$Choices=@(),[switch]$SearchChoices,[switch]$CategoryTabs,[AllowNull()]$Work=$null,[switch]$Monospace,[object[]]$SummaryRows=@())
    if(-not $Win -or -not $Win.IsVisible -or $Win.Content -isnot [Windows.Controls.Grid]){throw 'La fenêtre principale doit être ouverte pour afficher ce panneau.'}
    if($Body.Length -gt 262144){$Body=$Body.Substring(0,262144)+"`n[Affichage limité]"}
    [xml]$x=@'
<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Background="#66000000" KeyboardNavigation.TabNavigation="Cycle" KeyboardNavigation.ControlTabNavigation="Cycle" Focusable="True">
 <Border x:Name="PanelCard" Margin="16" Padding="22" MaxWidth="1000" CornerRadius="14" BorderThickness="1" BorderBrush="{DynamicResource ClrBorder}" Background="{DynamicResource BgCard}" HorizontalAlignment="Center" VerticalAlignment="Center">
 <Grid><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
  <StackPanel><TextBlock x:Name="PanelTitle" FontSize="22" FontWeight="SemiBold" TextWrapping="Wrap" Margin="0,0,0,10"/><TextBlock x:Name="PanelCaption" Visibility="Collapsed" TextWrapping="Wrap" Foreground="{DynamicResource FgMuted}" Margin="0,0,0,14"/></StackPanel>
  <Grid Grid.Row="1"><Grid.RowDefinitions><RowDefinition x:Name="PanelBodyRow" Height="*"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition x:Name="PanelChoicesRow" Height="Auto"/></Grid.RowDefinitions>
   <Grid x:Name="PanelContent"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions><ItemsControl x:Name="PanelSummary" Margin="0,0,0,12" Visibility="Collapsed"><ItemsControl.ItemTemplate><DataTemplate><Grid Margin="0,0,0,8"><Grid.ColumnDefinitions><ColumnDefinition Width="130"/><ColumnDefinition Width="*"/><ColumnDefinition Width="18"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><TextBlock Text="{Binding Field}" FontWeight="SemiBold" TextWrapping="Wrap"/><TextBlock Grid.Column="1" Text="{Binding Before}" TextWrapping="Wrap"/><TextBlock Grid.Column="2" Text="→"/><TextBlock Grid.Column="3" Text="{Binding After}" TextWrapping="Wrap"><TextBlock.Style><Style TargetType="TextBlock"><Style.Triggers><DataTrigger Binding="{Binding Changed}" Value="True"><Setter Property="FontWeight" Value="SemiBold"/><Setter Property="Foreground" Value="{DynamicResource FgAccent}"/></DataTrigger></Style.Triggers></Style></TextBlock.Style></TextBlock></Grid></DataTemplate></ItemsControl.ItemTemplate></ItemsControl><TextBox Grid.Row="1" x:Name="PanelBody" IsReadOnly="True" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" VerticalContentAlignment="Top" MinHeight="120" Padding="12" ToolTip="Texte sélectionnable. Ctrl+C copie la sélection ; Copier copie tout le texte affiché." AutomationProperties.Name="Détails du panneau"/></Grid>
   <StackPanel x:Name="PanelSearchArea" Grid.Row="1" Visibility="Collapsed"><TextBlock Text="Rechercher un outil" FontWeight="SemiBold" Margin="0,0,0,6"/><TextBox x:Name="PanelSearch" Visibility="Collapsed" MaxLength="128" Margin="0,0,0,12" ToolTip="Rechercher dans toutes les rubriques, avec ou sans accents. Aucun accès au réseau." AutomationProperties.Name="Rechercher une commande dans toutes les rubriques" AutomationProperties.AutomationId="PanelSearch"/></StackPanel>
   <TabControl x:Name="PanelCategories" Grid.Row="2" Visibility="Collapsed" Margin="0,0,0,10" AutomationProperties.Name="Rubriques des outils" AutomationProperties.AutomationId="PanelCategories"><TabItem x:Name="PanelCategoryPostes" Header="Postes" Tag="Postes"/><TabItem x:Name="PanelCategoryPreparer" Header="Préparer" Tag="Preparer"/><TabItem x:Name="PanelCategoryAnalyser" Header="Analyser" Tag="Analyser"/><TabItem x:Name="PanelCategoryAffichage" Header="Affichage" Tag="Affichage"/></TabControl>
   <ListBox x:Name="PanelChoices" Grid.Row="3" MaxHeight="220" MinHeight="80" DisplayMemberPath="Label" Margin="0,8,0,0" Visibility="Collapsed" Background="{DynamicResource BgInput}" Foreground="{DynamicResource FgText}" ScrollViewer.HorizontalScrollBarVisibility="Disabled" ScrollViewer.CanContentScroll="True" VirtualizingPanel.IsVirtualizing="True" VirtualizingPanel.VirtualizationMode="Recycling" ToolTip="Choisissez un élément, puis validez. La sélection seule ne lance aucune opération." AutomationProperties.Name="Choix disponibles" AutomationProperties.AutomationId="PanelChoices"><ListBox.ItemContainerStyle><Style TargetType="ListBoxItem"><Setter Property="HorizontalContentAlignment" Value="Stretch"/><Setter Property="AutomationProperties.Name" Value="{Binding Label}"/></Style></ListBox.ItemContainerStyle></ListBox>
  </Grid>
  <StackPanel x:Name="PanelInputArea" Grid.Row="2" Visibility="Collapsed" Margin="0,12,0,0"><TextBlock x:Name="PanelInputLabel" Margin="0,0,0,5"/><TextBox x:Name="PanelInput" MaxLength="4096" ToolTip="Saisie de préparation uniquement. Entrée ne valide pas une opération." AutomationProperties.Name="Valeur à renseigner"/></StackPanel>
  <TextBlock x:Name="PanelHint" Grid.Row="3" TextWrapping="Wrap" Foreground="{DynamicResource WarnFg}" Margin="0,10,0,0"/>
  <WrapPanel Grid.Row="4" HorizontalAlignment="Right" Margin="0,14,0,0"><Button x:Name="PanelCopy" Content="Copier le texte" ToolTip="Copier uniquement le texte affiché. Il peut contenir des informations internes." Margin="0,0,8,0"/><Button x:Name="PanelCancel" Content="Fermer" ToolTip="Fermer ce panneau sans lancer d’action. Échap fait la même chose." MinWidth="100"/><Button x:Name="PanelAccept" Visibility="Collapsed" MinWidth="120" Margin="8,0,0,0" Style="{DynamicResource BtnAdd}" ToolTip="Valider uniquement le choix décrit dans ce panneau."/></WrapPanel>
 </Grid></Border>
</Grid>
'@
    $overlay=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($x))
    [Windows.Controls.Grid]::SetColumnSpan($overlay,99);[Windows.Controls.Grid]::SetRowSpan($overlay,99);[Windows.Controls.Panel]::SetZIndex($overlay,10000)
    $root=$Win.FindName('SuiteRoot');if(-not $root){$root=$Win.Content};$focus=[Windows.Input.Keyboard]::FocusedElement
    $s=[pscustomobject]@{Frame=[Windows.Threading.DispatcherFrame]::new();Result=[pscustomobject]@{Accepted=$false;Text='';Selected=$null;Data=$null};
        Body=$overlay.FindName('PanelBody');Input=$overlay.FindName('PanelInput');Choices=$overlay.FindName('PanelChoices');Hint=$overlay.FindName('PanelHint');Overlay=$overlay;Searchable=[bool]$SearchChoices;AllChoices=@($Choices);Search=$overlay.FindName('PanelSearch');Accept=$overlay.FindName('PanelAccept');Categories=$overlay.FindName('PanelCategories');Work=$Work}
    $overlay.FindName('PanelTitle').Text=$Title;$s.Body.Text=$Body
    $summary=@(ConvertTo-PestoConfirmationRows $SummaryRows)
    if($summary.Count){$summaryControl=$overlay.FindName('PanelSummary');$summaryControl.ItemsSource=$summary;$summaryControl.Visibility='Visible'}
    $layout=Get-PestoPanelLayout -Width $root.ActualWidth -Height $root.ActualHeight -Text $Body -ChoicesCount @($Choices).Count -Searchable ([bool]$SearchChoices) -HasInput ([bool]$InputLabel) -SummaryCount $summary.Count
    $overlay.FindName('PanelCard').Width=$layout.Width;$overlay.FindName('PanelCard').Height=$layout.Height
    if($Monospace){$s.Body.FontFamily=[Windows.Media.FontFamily]::new('Consolas')}
    $s.Input.Text=$InitialValue
    if($InputLabel){$overlay.FindName('PanelInputArea').Visibility='Visible';$overlay.FindName('PanelInputLabel').Text=$InputLabel}
    if(@($Choices).Count){$s.Choices.Visibility='Visible';$s.Choices.ItemsSource=@($Choices);$s.Choices.SelectedIndex=0}
    if($AcceptText){$overlay.FindName('PanelAccept').Visibility='Visible';$overlay.FindName('PanelAccept').Content=$AcceptText;$overlay.FindName('PanelCancel').Content='Annuler'}
    foreach($n in @('PanelCopy','PanelAccept','PanelCancel')){$b=$overlay.FindName($n);$b.Tag=$s;$b.Add_Click([Windows.RoutedEventHandler]${function:Invoke-PestoPanelButton})}
    if($SearchChoices){
        $overlay.FindName('PanelSearchArea').Visibility='Visible';$s.Search.Visibility='Visible';$s.Search.Tag=$s;$s.Body.Visibility='Collapsed';$s.Choices.MaxHeight=[double]::PositiveInfinity
        $overlay.FindName('PanelBodyRow').Height=[Windows.GridLength]::new(0)
        $overlay.FindName('PanelChoicesRow').Height=[Windows.GridLength]::new(1,[Windows.GridUnitType]::Star)
        $overlay.FindName('PanelCaption').Text=$Body;$overlay.FindName('PanelCaption').Visibility='Visible';$overlay.FindName('PanelCopy').Visibility='Collapsed'
        if($CategoryTabs){
            $s.Categories.Visibility='Visible';$s.Categories.Tag=$s;$s.Categories.SelectedIndex=0
            $s.Categories.Add_SelectionChanged([Windows.Controls.SelectionChangedEventHandler]${function:Invoke-PestoPaletteCategory})
            $s.Choices.DisplayMemberPath=''
            [xml]$template='<DataTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"><StackPanel Margin="10,9"><TextBlock Text="{Binding Label}" FontWeight="SemiBold" TextWrapping="Wrap"/><TextBlock Text="{Binding Detail}" Margin="0,4,0,0" TextWrapping="Wrap" FontSize="12" Opacity="0.9"/></StackPanel></DataTemplate>'
            $s.Choices.ItemTemplate=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($template))
        }
        $s.Search.Add_TextChanged([Windows.Controls.TextChangedEventHandler]${function:Invoke-PestoPaletteSearch});Invoke-PestoPaletteSearch $s.Search $null
    }
    $overlay.Tag=$s;$overlay.Add_PreviewKeyDown([Windows.Input.KeyEventHandler]${function:Invoke-PestoPanelKey})
    $disabled=@(foreach($child in $root.Children){[pscustomobject]@{Child=$child;Enabled=$child.IsEnabled}})
    if(-not $script:PestoPanelStack){$script:PestoPanelStack=[Collections.Generic.List[object]]::new()}
    try {
        foreach($item in $disabled){$item.Child.IsEnabled=$false}
        [void]$root.Children.Add($overlay);$script:PestoPanelStack.Add($s);$root.UpdateLayout()
        if($SearchChoices){[void]$s.Search.Focus()}else{[void]$overlay.FindName('PanelCancel').Focus()}
        if($Work){$s.Accept.IsEnabled=$false;Start-PestoInventoryReview -PanelState $s -Request $Work}
        [Windows.Threading.Dispatcher]::PushFrame($s.Frame)
        return $s.Result
    } finally {
        if($Work){$Work.Cancellation.Cancelled=$true;Stop-PestoAsyncOperation 'InventoryReview'}
        [void]$script:PestoPanelStack.Remove($s);[void]$root.Children.Remove($overlay)
        foreach($item in $disabled){$item.Child.IsEnabled=$item.Enabled}
        if($focus -is [Windows.IInputElement]){try{[void][Windows.Input.Keyboard]::Focus($focus)}catch{}}
        if(Get-Command Update-PestoSuiteUI -ErrorAction SilentlyContinue){Update-PestoSuiteUI}
    }
}

function Invoke-PestoPanelClosing {
    param($Sender,$EventArgs)
    if($script:PestoPanelStack -and $script:PestoPanelStack.Count){
        $EventArgs.Cancel=$true
        $s=$script:PestoPanelStack[$script:PestoPanelStack.Count-1]
        if($s.PSObject.Properties['HostedWindow']){$s.HostedWindow.Close();return}
        $s.Result.Accepted=$false;$s.Frame.Continue=$false
    }
}

function Get-PestoDraftFromForm {
    $plan=Get-PestoDirectFormPlan
    $value=[pscustomobject]@{Schema=1;Domain=[string]$script:DOMAINE;ConfigStamp=(Get-PestoConfigurationSignature $script:CFG);
        Nom_du_PC=$plan.Nom_du_PC;Nouveau_Nom=$plan.Nouveau_Nom;OU_Actuelle=$plan.OU_Actuelle;OU_Destination=$plan.OU_Destination;Objet_GUID=$plan.Objet_GUID;TargetOUGuid='';
        Renommer=[bool]$plan.Renommer;Deplacer=[bool]$plan.Deplacer;Org=[string]$CbOrg.SelectedItem;Site=[string]$CbSite.SelectedItem;Service=[string]$CbService.Text;Type=[string]$CbType.SelectedItem}
    return ConvertTo-PestoDraft $value
}

function Read-PestoDraftFile {
    param([string]$Path)
    Assert-PestoPlainPath $Path
    $f=Get-Item -LiteralPath $Path -ErrorAction Stop
    if($f.PSIsContainer -or $f.Length -gt 65536){throw 'Fichier de brouillon invalide ou trop volumineux.'}
    $value=[IO.File]::ReadAllText($f.FullName,[Text.Encoding]::UTF8)|ConvertFrom-Json -ErrorAction Stop
    return ConvertTo-PestoDraft $value
}

function Complete-PestoPendingDraft {
    if(-not $script:PestoPendingDraft){return}
    $draft=$script:PestoPendingDraft;$script:PestoPendingDraft=$null
    if($draft.Nom_du_PC -ine ([string]$TxtPCName.Text).Trim() -or $draft.Domain -ine $script:DOMAINE -or $draft.ConfigStamp -cne (Get-PestoConfigurationSignature $script:CFG)){throw 'Le brouillon ne correspond plus au contexte. Aucune action restaurée.'}
    if($draft.Objet_GUID){
        $source=if($script:ComputerIndex -and $script:ComputerIndex.ContainsKey($draft.Nom_du_PC)){$script:ComputerIndex[$draft.Nom_du_PC]}else{$null}
        if(-not $source -or [string]$source.ObjectGUID -ine [string]$draft.Objet_GUID){throw 'L’’identité AD a changé depuis ce brouillon. Repréparez le poste ; aucun champ sensible n’’a été restauré.'}
    }
    if($draft.Org -notin @($CbOrg.Items) -or $draft.Site -notin @($script:Sites[$draft.Org]) -or $draft.Type -notin @('Portable','Fixe','Virtuel')){throw 'Site ou type du brouillon indisponible. Repréparez le poste.'}
    $CbOrg.SelectedItem=$draft.Org;$CbSite.SelectedItem=$draft.Site;$CbService.Text=$draft.Service;$CbType.SelectedItem=$draft.Type
    if($draft.Nouveau_Nom -notin @($CbName.Items)){[void]$CbName.Items.Add($draft.Nouveau_Nom)}
    $CbName.SelectedItem=$draft.Nouveau_Nom;$ChkRename.IsChecked=[bool]$draft.Renommer;$ChkMove.IsChecked=[bool]$draft.Deplacer
    $ChkReboot.IsChecked=$false;$script:DirectCheckedKey='';$script:DirectResumePlan=$null;$script:DirectResumeId=''
    Check-SameOU;Request-PestoUxRefresh
    Add-LogLine 'Brouillon rechargé après lecture de la cible. Aucun contrôle ni accord précédent restauré ; redémarrage désactivé.' 'info'
}



function Get-PestoOperationReport {
    param($Receipt,[bool]$Redact=$true)
    # Date absente ou illisible : « Inconnue », jamais une exception ni l'heure courante.
    $fmt={param($v,$f) $d=[DateTime]::MinValue; if($v -is [DateTime]){$d=$v;if($d.Kind -eq [DateTimeKind]::Unspecified){$d=[DateTime]::SpecifyKind($d,[DateTimeKind]::Utc)};$d.ToLocalTime().ToString($f,[Globalization.CultureInfo]::GetCultureInfo('fr-FR'))}elseif($v -and [DateTime]::TryParse([string]$v,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind,[ref]$d)){$d.ToLocalTime().ToString($f,[Globalization.CultureInfo]::GetCultureInfo('fr-FR'))}else{'Inconnue'}}
    $lines=[Collections.Generic.List[string]]::new()
    $lines.Add('PESTO | Compte rendu d''intervention')
    $lines.Add('Version : '+[string]$Receipt.Version)
    $lines.Add('Résultat connu : '+(Get-PestoStatePresentation $Receipt.Phase $Receipt.ResultCode).Label)
    $lines.Add('Code : '+[string]$Receipt.ResultCode)
    $lines.Add('Poste : '+$(if($Redact){'[MASQUÉ]'}else{[string]$Receipt.Plan.Nom_du_PC}))
    $lines.Add('Nom prévu : '+$(if($Redact){'[MASQUÉ]'}else{[string]$Receipt.Plan.Nouveau_Nom}))
    $lines.Add('Domaine : '+$(if($Redact){'[MASQUÉ]'}else{[string]$Receipt.Plan.Domain}))
    $ouText=(Format-OUPath ([string]$Receipt.Plan.OU_Actuelle))+' → '+(Format-OUPath ([string]$Receipt.Plan.OU_Destination))
    $lines.Add('OU : '+$(if($Redact){'[MASQUÉ]'}else{$ouText}))
    $dc=if($Receipt.Plan.DC){[string]$Receipt.Plan.DC}else{'Inconnu'}
    $lines.Add('Contrôleur : '+$(if($Redact){'[MASQUÉ]'}else{$dc}))
    $verif='Non vérifié — suivi facultatif'
    if($Receipt.VerifiedBy){$verif=[string]$Receipt.VerifiedBy+' ('+(& $fmt $Receipt.VerifiedUtc 'dd/MM/yyyy HH:mm')+')'}
    $lines.Add('Vérificateur : '+$(if($Redact){'[MASQUÉ]'}else{$verif}))
    $lines.Add('Début : '+(& $fmt $Receipt.StartedUtc 'dd/MM/yyyy HH:mm'))
    $lines.Add('Fin : '+(& $fmt $Receipt.UpdatedUtc 'dd/MM/yyyy HH:mm'))
    $lines.Add('Entra : '+(Get-PestoEffectLabel $Receipt.Entra)+' | Renommage : '+(Get-PestoEffectLabel $Receipt.Rename)+' | Déplacement : '+(Get-PestoEffectLabel $Receipt.Move)+' | Protection : '+(Get-PestoEffectLabel $Receipt.Protection))
    foreach($e in @($Receipt.Timeline|Select-Object -Last 40)){
        # Une liste fermée évite d'exporter les messages bruts, chemins ou credentials.
        $stage=if([string]$e.Stage -in @('Rename','Move','Entra','Protection','Result')){[string]$e.Stage}else{'Contrôle'}
        $state=if([string]$e.State -match '^[A-Za-z]{1,32}$'){[string]$e.State}else{'Consigné'}
        $lines.Add((& $fmt $e.Utc 'dd/MM/yyyy HH:mm:ss')+' | '+(Get-PestoStageLabel $stage)+' | '+(Get-PestoEffectLabel $state))
    }
    $lines.Add((Get-PestoNativeGuidance -Code ([long]$Receipt.ResultCode) -Stage 'intervention'))
    $lines.Add('Une réponse tardive ou un délai dépassé ne prouve pas l''annulation de Windows.')
    # Identity visibility never authorizes exposing credentials pasted in free text.
    return Protect-PestoLogText ($lines -join [Environment]::NewLine)
}

function Get-PestoWorkspaceCommands {
    @(
      @('single',(Get-PestoUxNom 'PagePoste'),'Préparer un renommage ou déplacement individuel.'),@('batch',(Get-PestoUxNom 'PageLot'),'Préparer un lot, sans exécution immédiate.'),
      @('join',(Get-PestoUxNom 'PageJonction'),'Ouvrir la page de jonction du PC local.'),@('names',(Get-PestoUxNom 'PageNoms'),'Ouvrir les propositions et leurs états datés.'),
      @('interventions','Interventions à vérifier','Revoir les effets et les reprises, indépendamment de la file.'),
      @('draft-save','Enregistrer le brouillon','Conserver les champs de préparation uniquement.'),@('draft-load','Restaurer le brouillon','Relire la cible et invalider les anciens accords.'),
      @('draft-export','Exporter un dossier hors ligne','JSON de préparation sans secret, reboot ou autorisation.'),@('draft-import','Importer un dossier de préparation','Prévisualiser, relire puis reprendre uniquement les champs.'),
      @('label','Lire une étiquette de poste','Nom ou URI pesto:PC ; lecture volontaire et identité à vérifier.'),
      @('conformity','Contrôler noms et emplacements','Comparer les noms et sites réellement lus dans l’’inventaire ; aucune correction.'),
      @('capacity','Capacité de nommage','Capacité de toutes les combinaisons configurées ou observées dans le périmètre chargé.'),
      @('changes','Comparer les deux derniers inventaires','Noms ajoutés et retirés du cache, pas des réservations AD.'),
      @('performance','Mesures de performance locales','Durées observées et état du rédacteur de journal ; pas de télémétrie.'),
      @('density','Densité de présentation','Basculer confort ou compact, sans modifier les droits.'),
      @('save-columns','Mémoriser les colonnes','Enregistrer largeur et ordre des tableaux sans les sélections.'),@('reset-columns','Réinitialiser les colonnes','Rétablir la présentation initiale sans toucher aux lignes.'),
      @('settings','Paramètres','Apparence, domaine et politiques.'),@('diagnostic','Préparer un diagnostic','Rapport masqué et prévisualisé.'),@('help','Aide','Règles, raccourcis et prochaine étape.')
    )|ForEach-Object{
        $category=switch([string]$_[0]){
            {$_ -in @('single','batch','join','names','interventions')} {'Postes';break}
            {$_ -in @('draft-save','draft-load','draft-export','draft-import','label')} {'Preparer';break}
            {$_ -in @('conformity','capacity','changes','performance','diagnostic')} {'Analyser';break}
            default {'Affichage'}
        }
        [pscustomobject]@{Id=$_[0];Label=$_[1];Detail=$_[2];Category=$category}
    }
}

function Show-PestoWorkspace {
    param($Sender,$EventArgs)
    if($script:PestoPanelStack -and $script:PestoPanelStack.Count){return}
    $commands=@(Get-PestoWorkspaceCommands)
    $r=Show-PestoPanel -Title 'Outils et navigation' -Body 'Parcourez une rubrique ou recherchez dans tous les outils. Aucun choix ne lance une opération sur un poste.' -AcceptText 'Ouvrir' -Choices $commands -SearchChoices -CategoryTabs
    if($r.Accepted -and $r.Selected){Invoke-PestoWorkspaceAction -Id $r.Selected.Id}
}

function Invoke-PestoWorkspaceAction {
    param([ValidateSet('single','batch','join','names','interventions','draft-save','draft-load','draft-export','draft-import','label','conformity','capacity','changes','performance','density','save-columns','reset-columns','settings','diagnostic','help')][string]$Id)
    try {
        switch($Id){
            'single' {Set-PestoSuiteMode 'Single';return}
            'batch' {Set-PestoSuiteMode 'Batch';return}
            'join' {Set-PestoUxPage 'Join';return}
            'names' {Set-PestoUxPage 'Names';return}
            'settings' {Set-PestoUxPage 'Settings';return}
            'help' {Set-PestoUxPage 'Help';return}
            'interventions' {Show-PestoInterventions;return}
            'diagnostic' {Export-Diagnostics;return}
            'performance' {
                $report='MESURES AGRÉGÉES (200 derniers échantillons au maximum)'+"`r`n"+(@(Get-PestoPerformanceSummary @($script:PestoPerformance))|Format-Table -AutoSize|Out-String -Width 200)
                $report+="`r`nDERNIÈRES MESURES`r`n"+(@($script:PestoPerformance)|Select-Object -Last 40|Format-Table -AutoSize|Out-String -Width 200)
                $health=Get-PestoAuditHealth
                $report+="`nJournal : "+($health|ConvertTo-Json -Compress)+"`nMesures locales de cette session. Returned signifie retour du worker, pas réussite de l'opération métier. Aucun gain de vitesse supposé. Mesures non conservées : $script:PestoMetricsDropped."
                [void](Show-PestoPanel -Title 'Performance observée' -Body $report -Monospace);return
            }
            'capacity' {Show-PestoInventoryReview -Kind capacity;return}
            'conformity' {Show-PestoInventoryReview -Kind conformity;return}
            'changes' {
                if(-not $script:NmPreviousNames){throw 'Deux inventaires complets de cette session sont nécessaires.'}
                $old=@{};foreach($n in $script:NmPreviousNames){$old[[string]$n]=$true};$current=@{};foreach($n in @($script:ComputersNoms.Name)){$current[[string]$n]=$true}
                $diff=@(foreach($n in $current.Keys){if(-not $old.ContainsKey($n)){[pscustomobject]@{Nom=$n;Etat='Apparu dans le périmètre'}}};foreach($n in $old.Keys){if(-not $current.ContainsKey($n)){[pscustomobject]@{Nom=$n;Etat='Absent du nouveau périmètre'}}})
                [void](Show-PestoPanel -Title 'Différence des inventaires' -Body (($diff|Select-Object -First 1000|Sort-Object Nom|Format-Table -AutoSize|Out-String -Width 160)+"`nUn nom absent du périmètre n'est pas garanti libre dans le domaine."));return
            }
            'save-columns' {Save-PestoTables;return}
            'reset-columns' {Reset-PestoTables;return}
            'density' {
                $script:PestoCompact=-not $script:PestoCompact
                Set-PestoAppearanceValue -Name 'Density' -Value $(if($script:PestoCompact){'Compact'}else{'Comfort'})
                Apply-PestoDensity;return
            }
        }
        if($script:Running -or $script:DirectBusy -or $script:JoinBusy -or $script:PreflightRunning -or $script:CfgRestartRequired){throw 'Terminez le traitement ou appliquez la configuration avant de changer la préparation.'}
        if($Id -eq 'label'){
            $r=Show-PestoPanel -Title 'Lire une étiquette' -Body 'Accepte un nom Windows ou pesto: suivi du nom. Un numéro de série non résolu ne sera pas deviné. La lecture ne lance aucune modification.' -InputLabel 'Nom du poste' -AcceptText 'Lire'
            if($r.Accepted){$name=$r.Text.Trim() -replace '(?i)^pesto:','';if(-not(Test-PestoComputerName $name)){throw 'Étiquette non reconnue. Utilisez le nom Windows exact.'};$TxtPCName.Text=$name;Set-PestoSuiteMode 'Single';Select-PCName};return
        }
        if($Id -in @('draft-save','draft-export')){
            $draft=Get-PestoDraftFromForm;$text=$draft|ConvertTo-Json -Depth 4
            if($Id -eq 'draft-save'){
                $name=Show-PestoPanel -Title 'Nommer le brouillon' -Body 'Seuls les champs de préparation sont mémorisés. Aucun accord, contrôle ou redémarrage.' -InputLabel 'Nom du brouillon' -InitialValue ([string]$draft.Nom_du_PC) -AcceptText 'Enregistrer'
                if(-not $name.Accepted){return};if(@(Read-PestoDraftCollection|Where-Object{$_.Name -ieq $name.Text.Trim()}).Count -and -not(Confirm-YesNo -Msg ('Remplacer le brouillon « '+$name.Text.Trim()+' » ?') -Confirm $true -AcceptText 'Remplacer')){return};Save-PestoNamedDraft -Name $name.Text.Trim() -Draft $draft
                Add-LogLine 'Brouillon enregistré. Aucun mot de passe, redémarrage ou accord de mutation mémorisé.' 'info';return
            }
            $r=Show-PestoPanel -Title 'Dossier de préparation hors ligne' -Body $text -AcceptText 'Choisir un fichier'
            if(-not $r.Accepted){return}
            $dialog=[Microsoft.Win32.SaveFileDialog]::new();$dialog.Filter='Brouillon JSON (*.json)|*.json';$dialog.FileName='Pesto-brouillon.json';$dialog.OverwritePrompt=$true
            if($dialog.ShowDialog($Win) -eq $true){Write-PestoNewExport -Path $dialog.FileName -Text $text};return
        }
        $draft=$null
        if($Id -eq 'draft-load'){
            $collection=@(Read-PestoDraftCollection);if($collection.Count){$draft=Get-PestoNamedDraft;if(-not $draft){return}}
            $text=if($script:SIM -or $script:GUI){$script:PestoDraftMemory}else{Get-PestoAppearanceValue -Name 'Draft'}
            if(-not $draft -and -not $text){return}
            if(-not $draft -and (-not $text -or $text.Length -gt 65536)){throw 'Aucun brouillon valide enregistré.'}
            if(-not $draft){$draft=ConvertTo-PestoDraft ($text|ConvertFrom-Json -ErrorAction Stop)}
        }elseif($Id -eq 'draft-import'){
            $dialog=[Microsoft.Win32.OpenFileDialog]::new();$dialog.Filter='Brouillon JSON (*.json)|*.json'
            if($dialog.ShowDialog($Win) -ne $true){return};$draft=Read-PestoDraftFile $dialog.FileName
        }
        if($draft){
            if($draft.Domain -ine $script:DOMAINE -or $draft.ConfigStamp -cne (Get-PestoConfigurationSignature $script:CFG)){throw 'Domaine ou configuration différents : ce brouillon doit être préparé de nouveau.'}
            $r=Show-PestoPanel -Title 'Reprendre la préparation' -Body ($draft|ConvertTo-Json -Depth 4) -AcceptText 'Relire le poste'
            if($r.Accepted){$script:PestoPendingDraft=$draft;$TxtPCName.Text=$draft.Nom_du_PC;Set-PestoSuiteMode 'Single';Select-PCName}
        }
    }catch{Show-MsgError $_.Exception.Message 'Préparation Pesto'}
}

function Write-PestoNewExport {
    param([string]$Path,[string]$Text)
    Assert-PestoPlainPath $Path
    $bytes=[Text.Encoding]::UTF8.GetBytes($Text)
    if($bytes.Length -gt 1048576){throw 'Export trop volumineux.'}
    $destination=[IO.Path]::GetFullPath($Path)
    $parent=[IO.Path]::GetDirectoryName($destination)
    if(-not [IO.Directory]::Exists($parent)){throw 'Le dossier parent de l''export doit déjà exister.'}
    if([IO.File]::Exists($destination) -or [IO.Directory]::Exists($destination)){throw 'Un fichier ou dossier existe déjà à cet emplacement. Aucun remplacement.'}
    # Même volume : seul le fichier complet devient visible au chemin demandé.
    # Move sans écrasement protège aussi contre une destination créée entre-temps.
    $temporary=Join-Path $parent ('.pesto-export-'+[Guid]::NewGuid().ToString('N')+'.tmp')
    try{
        $f=[IO.File]::Open($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try{$f.Write($bytes,0,$bytes.Length);$f.Flush($true)}finally{$f.Dispose()}
        Assert-PestoPlainPath $destination
        [IO.File]::Move($temporary,$destination)
    }finally{if([IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}}
}

function Apply-PestoDensity {
    $height=if($script:PestoCompact){28.0}else{36.0}
    foreach($grid in @($Grid,$NmGrid,$UxHistoryGrid)){if($grid){$grid.RowHeight=$height}}
    if($script:InterventionsUi -and $script:InterventionsUi.Grid){$script:InterventionsUi.Grid.RowHeight=$height}
    $button=$Win.FindName('SuiteAppearanceDensity');if($button){$button.Content='Densité : '+$(if($script:PestoCompact){'compact'}else{'confort'})}
}

function Invoke-PestoWorkspaceKeys {
    param($Sender,$EventArgs)
    if($EventArgs.Key -eq [Windows.Input.Key]::F6){$EventArgs.Handled=$true;Invoke-PestoFocusZone -Reverse ([bool]([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Shift));return}
    if($EventArgs.Key -eq [Windows.Input.Key]::K -and ([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Control)){
        $EventArgs.Handled=$true;Show-PestoWorkspace
    }
}

function Initialize-PestoWorkspace {
    $homeButton=$Win.FindName('HomeInterventions');if($homeButton){$homeButton.Add_Click({Show-PestoInterventions})}
    foreach($name in @('HomeJoin','HomeRefresh','HomeOpenReceipt')){$button=$Win.FindName($name);if($button){$button.Add_Click([Windows.RoutedEventHandler]${function:Invoke-PestoHomeCommand})}}
    $recent=$Win.FindName('HomeRecentList');if($recent){$recent.Add_SelectionChanged({$Win.FindName('HomeOpenReceipt').IsEnabled=($null -ne $Win.FindName('HomeRecentList').SelectedItem)})}
    $b=$Win.FindName('WorkspaceButton');if($b){$b.Add_Click([Windows.RoutedEventHandler]${function:Show-PestoWorkspace})}
    $Win.Add_PreviewKeyDown([Windows.Input.KeyEventHandler]${function:Invoke-PestoWorkspaceKeys})
    $Win.Add_Closing([ComponentModel.CancelEventHandler]${function:Invoke-PestoPanelClosing})
    Register-PestoTable -Id queue -Grid $Grid -Fixed 2
    Register-PestoTable -Id names -Grid $NmGrid -Fixed 1
    $script:PestoCompact=(Get-PestoAppearanceValue -Name 'Density') -eq 'Compact';Apply-PestoDensity
}

function Complete-PestoHostedWindow {
    param($Sender,$EventArgs)
    if($Sender.Tag -and $Sender.Tag.Frame){$Sender.Tag.Frame.Continue=$false}
}
function Invoke-PestoHostedKey {
    param($Sender,$EventArgs)
    if($EventArgs.Key -eq [Windows.Input.Key]::Escape -and $Sender.Tag.HostedWindow){
        $Sender.Tag.HostedWindow.Close()
        $EventArgs.Handled=$true
    }
}

function Show-PestoHostedWindow {
    param([Parameter(Mandatory=$true)][Windows.Window]$Window)
    if(-not $Win -or -not $Win.IsVisible -or $Win.Content -isnot [Windows.Controls.Grid]){return $Window.ShowDialog()}
    $root=$Win.FindName('SuiteRoot');if(-not $root){$root=$Win.Content};$content=$Window.Content
    $focusButton=$Window.FindName('LedgerClose');if(-not $focusButton){$focusButton=$Window.FindName('StateClose')}
    $Window.Content=$null
    $overlay=[Windows.Controls.Grid]::new();$overlay.Background=[Windows.Media.BrushConverter]::new().ConvertFromString('#66000000');$overlay.Focusable=$true
    [Windows.Controls.Grid]::SetColumnSpan($overlay,99);[Windows.Controls.Grid]::SetRowSpan($overlay,99);[Windows.Controls.Panel]::SetZIndex($overlay,10000)
    [Windows.Input.KeyboardNavigation]::SetTabNavigation($overlay,'Cycle')
    $border=[Windows.Controls.Border]::new();$border.Margin=[Windows.Thickness]::new(20);$border.CornerRadius=[Windows.CornerRadius]::new(14)
    $border.SetResourceReference([Windows.Controls.Border]::BackgroundProperty,'BgCard');$border.Child=$content
    [void]$overlay.Children.Add($border)
    $state=[pscustomobject]@{Frame=[Windows.Threading.DispatcherFrame]::new();Result=[pscustomobject]@{Accepted=$false};HostedWindow=$Window}
    $Window.Tag=$state;$Window.Add_Closed([EventHandler]${function:Complete-PestoHostedWindow})
    $overlay.Tag=$state;$overlay.Add_PreviewKeyDown([Windows.Input.KeyEventHandler]${function:Invoke-PestoHostedKey})
    $old=@(foreach($child in $root.Children){[pscustomobject]@{Child=$child;Enabled=$child.IsEnabled}})
    $focus=[Windows.Input.Keyboard]::FocusedElement
    if(-not $script:PestoPanelStack){$script:PestoPanelStack=[Collections.Generic.List[object]]::new()}
    try{
        foreach($item in $old){$item.Child.IsEnabled=$false}
        [void]$root.Children.Add($overlay);$script:PestoPanelStack.Add($state);$root.UpdateLayout()
        if(-not $focusButton){$focusButton=$content.FindName('LedgerClose');if(-not $focusButton){$focusButton=$content.FindName('StateClose')}}
        # Every hosted view must own keyboard focus, including generic previews.
        [void]$overlay.Focus()
        if($focusButton){[void]$focusButton.Focus()}
        [Windows.Threading.Dispatcher]::PushFrame($state.Frame)
    }finally{
        [void]$script:PestoPanelStack.Remove($state);[void]$root.Children.Remove($overlay)
        $border.Child=$null
        foreach($item in $old){$item.Child.IsEnabled=$item.Enabled}
        if($focus){try{[void][Windows.Input.Keyboard]::Focus($focus)}catch{}}
    }
}
