#requires -Version 5.1
# Lecture d'affichage tolérante ; Get-PestoInterventions reste strict pour les barrières métier.
function Get-PestoInterventionCatalogue {
    param([hashtable]$Cache=$null,[string]$Root='',[switch]$Force)
    if(-not $Root){$Root=Get-PestoInterventionRoot}
    if($Cache){return Get-PestoInterventionCatalogCached -Root $Root -Cache $Cache -Force:$Force}
    $root=$Root
    Assert-PestoPlainPath $root
    try{$directory=Get-Item -LiteralPath $root -Force -ErrorAction Stop}
    catch [Management.Automation.ItemNotFoundException]{return [pscustomobject]@{Entries=@();ValidCount=0;InvalidCount=0;Truncated=$false;ScannedCount=0}}
    if(-not $directory.PSIsContainer){throw 'Le registre des interventions n’’est pas un dossier.'}
    # La borne concerne l'affichage. Une liste tronquée n'est jamais exportée comme complète.
    $files=@(Get-ChildItem -LiteralPath $root -Filter '*.json' -File -Force -ErrorAction Stop | Select-Object -First 5001)
    $entries=[Collections.Generic.List[object]]::new();$valid=0;$invalid=0
    foreach($file in $files | Select-Object -First 5000){
        try{
            $receipt=Read-PestoIntervention -Path $file.FullName
            $entries.Add([pscustomobject]@{Id=$receipt.OperationId;Readable=$true;Receipt=$receipt;FileName=$file.Name;Issue=''})
            $valid++
        }catch{
            $entries.Add([pscustomobject]@{Id='invalid:'+$file.Name;Readable=$false;Receipt=$null;FileName=$file.Name;Issue='Reçu illisible ou invalide. Faites contrôler ce fichier par le support. Aucun verrou levé.'})
            $invalid++
        }
    }
    return [pscustomobject]@{Entries=$entries.ToArray();ValidCount=$valid;InvalidCount=$invalid;Truncated=($files.Count -gt 5000);ScannedCount=$files.Count}
}

function ConvertTo-PestoInterventionRow {
    param($Entry)
    $r=$Entry.Receipt;$readable=[bool]$Entry.Readable -and $null -ne $r
    $phase=if($readable){[string]$r.Phase}else{'Unreadable'}
    $optional=[bool]($readable -and (Test-PestoOptionalPostCheckReceipt -Receipt $r))
    $acknowledged=[bool]($readable -and (Test-PestoAcknowledgedReceipt -Receipt $r))
    $state=Get-PestoStatePresentation -State $(if($optional){'AcceptedOptional'}else{$phase}) -Code $(if($readable){$r.ResultCode}else{$null})
    $local='Date inconnue';$utc=$null
    if($readable){
        $stamp=[DateTimeOffset]::MinValue
        if([string]$r.UpdatedUtc -match '(Z|[+-]\d{2}:\d{2})$' -and [DateTimeOffset]::TryParse([string]$r.UpdatedUtc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$stamp)){
            $utc=$stamp;$local=$stamp.ToLocalTime().ToString('dd/MM/yyyy HH:mm:ss zzz',[Globalization.CultureInfo]::InvariantCulture)
        }
    }
    $computer=if($readable){[string]$r.Plan.Nom_du_PC}else{[string]$Entry.FileName}
    $next=if($acknowledged){Get-PestoAcknowledgementText $r}elseif($readable){$state.Action}else{[string]$Entry.Issue}
    [pscustomobject]@{RowId=[string]$Entry.Id;UpdatedUtc=$utc;UpdatedLocal=$local;Computer=$computer;NewName=$(if($readable){[string]$r.Plan.Nouveau_Nom}else{''});StatusCode=$phase;StatusLabel=$(if($acknowledged){$state.Label+' · acquittée'}else{$state.Label});
        StageLabel=$(if($readable){Get-PestoStageLabel ([string]$r.LastStage)}else{'Lecture impossible'});EntraLabel=$(if($readable){Get-PestoEffectLabel ([string]$r.Entra)}else{'Inconnu'});
        Readable=$readable;Unresolved=($phase -notin @('Verified','Failed','NotStarted') -and -not $acknowledged);OptionalPostCheck=$optional;Acknowledged=$acknowledged;NextAction=$next;Receipt=$r;
        SearchText=($computer+' '+[string]$r.Plan.Nouveau_Nom+' '+$state.Label+' '+[string]$Entry.Id)}
}

function Get-PestoInterventionQuery {
    param([object[]]$Rows=@(),[ValidateLength(0,256)][string]$Search='',
        [ValidateSet('All','Unresolved','NeedsAttention','Optional','Verified','Failed','Unreadable')][string]$State='All',
        [ValidateRange(0,2147483647)][int]$Offset=0,[ValidateRange(1,5000)][int]$PageSize=200)
    $fields=[M4D.Admin.Common.Query.FieldDefinition[]]@(
        [M4D.Admin.Common.Query.FieldDefinition]::new('Search',[M4D.Admin.Common.Query.FieldKind]::Text),
        [M4D.Admin.Common.Query.FieldDefinition]::new('State',[M4D.Admin.Common.Query.FieldKind]::Text),
        [M4D.Admin.Common.Query.FieldDefinition]::new('Unresolved',[M4D.Admin.Common.Query.FieldKind]::Boolean),
        [M4D.Admin.Common.Query.FieldDefinition]::new('Optional',[M4D.Admin.Common.Query.FieldKind]::Boolean),
        [M4D.Admin.Common.Query.FieldDefinition]::new('Updated',[M4D.Admin.Common.Query.FieldKind]::Timestamp))
    $definition=[M4D.Admin.Common.Query.QueryDefinition]::new()
    if($Search.Trim()){$definition.Clauses.Add([M4D.Admin.Common.Query.QueryClause]::new('Search',[M4D.Admin.Common.Query.QueryOperator]::Contains,$Search.Trim()))}
    if($State -eq 'Optional'){$definition.Clauses.Add([M4D.Admin.Common.Query.QueryClause]::new('Optional',[M4D.Admin.Common.Query.QueryOperator]::Equal,$true))}
    elseif($State -eq 'NeedsAttention'){$definition.Clauses.Add([M4D.Admin.Common.Query.QueryClause]::new('Unresolved',[M4D.Admin.Common.Query.QueryOperator]::Equal,$true));$definition.Clauses.Add([M4D.Admin.Common.Query.QueryClause]::new('Optional',[M4D.Admin.Common.Query.QueryOperator]::Equal,$false))}
    elseif($State -eq 'Unresolved'){$definition.Clauses.Add([M4D.Admin.Common.Query.QueryClause]::new('Unresolved',[M4D.Admin.Common.Query.QueryOperator]::Equal,$true))}
    elseif($State -ne 'All'){$definition.Clauses.Add([M4D.Admin.Common.Query.QueryClause]::new('State',[M4D.Admin.Common.Query.QueryOperator]::Equal,$State))}
    $query=[M4D.Admin.Common.Query.QueryEngine]::Compile($fields,$definition)
    $records=[Collections.Generic.List[M4D.Admin.Common.Query.QueryRecord]]::new();$byId=@{}
    foreach($row in @($Rows)){
        if(-not $row -or -not $row.RowId -or $byId.ContainsKey([string]$row.RowId)){throw 'Identité de ligne absente ou dupliquée.'}
        $data=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
        $data.Add('Search',[string]$row.SearchText);$data.Add('State',[string]$row.StatusCode);$data.Add('Unresolved',[bool]$row.Unresolved);$data.Add('Updated',$row.UpdatedUtc);$data.Add('Optional',[bool]$row.OptionalPostCheck)
        $records.Add([M4D.Admin.Common.Query.QueryRecord]::new([string]$row.RowId,$data));$byId[[string]$row.RowId]=$row
    }
    $options=[M4D.Admin.Common.Query.QueryOptions]::new();$options.Offset=$Offset;$options.Limit=$PageSize;$options.SortField='Updated';$options.Descending=$true
    $result=$query.Execute($records,$options)
    if($Offset -ge $result.Matched -and $Offset -gt 0){$options.Offset=[Math]::Max(0,([Math]::Ceiling($result.Matched/$PageSize)-1)*$PageSize);$result=$query.Execute($records,$options)}
    [pscustomobject]@{Items=@(foreach($record in $result.Rows){$byId[$record.Id]});MatchedCount=$result.Matched;TotalCount=$result.Total;UnknownCount=$result.Unknown;Offset=$options.Offset}
}

function Export-PestoInterventionRows {
    param([Parameter(Mandatory=$true)][string]$Path,[object[]]$Rows=@())
    $export=@(foreach($row in $Rows){
        $values=[ordered]@{Date_locale=$row.UpdatedLocal;Poste=$row.Computer;Nom_prevu=$row.NewName;Etat=$row.StatusLabel;Etape=$row.StageLabel;Entra=$row.EntraLabel;Action=$row.NextAction}
        foreach($key in @($values.Keys)){$text=Protect-PestoLogText ([string]$values[$key]);if($text -match '^\s*[=+@-]' -or $text -match '^[\t\r\n]'){$text="'"+$text};$values[$key]=$text}
        [pscustomobject]$values
    })
    if(-not $export.Count){throw 'Aucun résultat filtré à exporter.'}
    Assert-PestoPlainPath $Path
    $csv=($export | ConvertTo-Csv -NoTypeInformation -Delimiter ';') -join "`r`n"
    Write-PestoAtomicText -Path $Path -Text ([string][char]0xFEFF+$csv+"`r`n")
}

function Show-PestoInterventions {
    if($script:GUI -or $script:SIM){Show-MsgInfo 'Les interventions réelles ne sont pas consultées depuis une simulation.';return}
    if($script:InterventionsUi){[void]$script:InterventionsUi.Window.Activate();return}
    [xml]$x=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Pesto · Interventions" Width="1060" Height="710" MinWidth="600" MinHeight="400" WindowStartupLocation="CenterOwner" Background="{DynamicResource BgWindow}" Foreground="{DynamicResource FgText}" FontFamily="Segoe UI" FontSize="13" UseLayoutRounding="True">
<Grid Margin="20"><Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
<ScrollViewer x:Name="LedgerPageScroll" Grid.Row="0" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" CanContentScroll="False"><Grid><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
<TextBlock Text="Interventions à suivre" FontSize="24" FontWeight="SemiBold"/>
<TextBlock x:Name="LedgerHint" Grid.Row="1" Text="Lecture des reçus locaux…" TextWrapping="Wrap" Margin="0,8,0,12" Foreground="{DynamicResource FgMuted}"/>
<WrapPanel Grid.Row="2" Margin="0,0,0,10"><TextBox x:Name="LedgerSearch" Width="230" MaxLength="256" Margin="0,0,8,4" ToolTip="Rechercher un poste, nom prévu, état ou identifiant" AutomationProperties.Name="Rechercher une intervention"/><ComboBox x:Name="LedgerState" Width="210" Margin="0,0,8,4" SelectedIndex="0" AutomationProperties.Name="Filtrer les interventions"><ComboBoxItem Content="Toutes les interventions" Tag="All"/><ComboBoxItem Content="À vérifier avant reprise" Tag="NeedsAttention"/><ComboBoxItem Content="Acceptées · suivi facultatif" Tag="Optional"/><ComboBoxItem Content="Tous les suivis non consignés" Tag="Unresolved"/><ComboBoxItem Content="Vérifiées" Tag="Verified"/><ComboBoxItem Content="Refus confirmés" Tag="Failed"/><ComboBoxItem Content="Reçus illisibles" Tag="Unreadable"/></ComboBox><Button x:Name="LedgerRefresh" Content="Actualiser" Margin="0,0,8,4"/><Button x:Name="LedgerExport" Content="Exporter le filtre" Margin="0,0,8,4" ToolTip="Exporter toutes les lignes filtrées, au-delà de la page affichée."/></WrapPanel>
<DataGrid x:Name="LedgerGrid" Grid.Row="3" Height="260" MinHeight="180" AutoGenerateColumns="False" IsReadOnly="True" CanUserAddRows="False" CanUserDeleteRows="False" CanUserSortColumns="False" SelectionMode="Single" EnableRowVirtualization="True" EnableColumnVirtualization="True" GridLinesVisibility="Horizontal" HeadersVisibility="Column" RowHeaderWidth="0" AutomationProperties.Name="Interventions enregistrées"><DataGrid.Columns>
<DataGridTextColumn Header="Date locale" Binding="{Binding UpdatedLocal}" Width="195"/><DataGridTextColumn Header="Poste" Binding="{Binding Computer}" Width="145"/><DataGridTextColumn Header="Nom prévu" Binding="{Binding NewName}" Width="145"/><DataGridTextColumn Header="État" Binding="{Binding StatusLabel}" Width="185"/><DataGridTextColumn Header="Entra" Binding="{Binding EntraLabel}" Width="150"/><DataGridTextColumn Header="Étape" Binding="{Binding StageLabel}" Width="160"/>
</DataGrid.Columns></DataGrid>
<DockPanel Grid.Row="4" Margin="0,10,0,8"><StackPanel DockPanel.Dock="Right" Orientation="Horizontal"><Button x:Name="LedgerPrevious" Content="Précédent"/><Button x:Name="LedgerNext" Content="Suivant" Margin="8,0,0,0"/></StackPanel><TextBlock x:Name="LedgerPage" VerticalAlignment="Center" TextWrapping="Wrap"/></DockPanel>
<StackPanel Grid.Row="5"><TextBlock x:Name="LedgerActionHint" Text="Sélectionnez une intervention pour connaître la prochaine action." TextWrapping="Wrap" Margin="0,0,0,8"/><Expander x:Name="LedgerTools" Header="Détails et outils" Margin="0,0,0,10" AutomationProperties.Name="Détails et outils des interventions"><ScrollViewer MaxHeight="190" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled"><TabControl x:Name="LedgerToolTabs" Margin="0,10,0,0" AutomationProperties.Name="Outils des interventions"><TabItem x:Name="LedgerTabRead" Header="Consulter" AutomationProperties.Name="Consulter"><StackPanel Margin="4,6,4,0"><TextBlock Text="Comprendre les effets déjà consignés." Style="{DynamicResource Hint}" Margin="0,0,0,10"/><WrapPanel><Button x:Name="LedgerDetails" Content="Voir le reçu" Margin="0,0,8,8"/><Button x:Name="LedgerTasks" Content="Relire les tâches" Margin="0,0,8,8"/><Button x:Name="LedgerCompare" Content="Comparer deux reçus" Margin="0,0,8,8"/><Button AutomationProperties.HelpText="Consulter les reçus du même identifiant de poste dans cette vue." x:Name="LedgerTimeline" Content="Chronologie du poste" Margin="0,0,8,8"/><Button AutomationProperties.HelpText="Prévisualiser et exporter un dossier de support masqué pour ce reçu." x:Name="LedgerSupport" Content="Dossier de support…" Margin="0,0,8,8"/></WrapPanel></StackPanel></TabItem><TabItem x:Name="LedgerTabMaintain" Header="Entretien" AutomationProperties.Name="Entretien"><StackPanel Margin="4,6,4,0"><TextBlock Text="Ces actions nécessitent des contrôles et une confirmation." Style="{DynamicResource Hint}" Margin="0,0,0,10"/><WrapPanel><Button x:Name="LedgerProtection" Content="Rétablir la protection" Margin="0,0,8,8"/><Button x:Name="LedgerCleanup" Content="Nettoyer les tâches terminées" Margin="0,0,8,8"/></WrapPanel></StackPanel></TabItem><TabItem x:Name="LedgerTabData" Header="Données" AutomationProperties.Name="Données"><StackPanel Margin="4,6,4,0"><TextBlock Text="Récupérer un ancien état ou personnaliser le tableau." Style="{DynamicResource Hint}" Margin="0,0,0,10"/><WrapPanel><Button x:Name="LedgerImport" Content="Importer un ancien état" Margin="0,0,8,8"/><Button x:Name="LedgerViews" Content="Vues et colonnes…" Margin="0,0,8,8" ToolTip="Mémoriser les filtres et le tri sans sélectionner ou consigner une intervention." AutomationProperties.HelpText="Mémoriser les filtres et le tri sans sélectionner ou consigner une intervention."/><Button x:Name="LedgerColumns" Content="Mémoriser les colonnes" Margin="0,0,8,8"/><Button AutomationProperties.HelpText="Basculer entre reçus actifs et archives sans modifier leur état." x:Name="LedgerArchives" Content="Consulter les archives" Margin="0,0,8,8"/><Button AutomationProperties.HelpText="Archiver un reçu terminal sans changement Windows ou AD, après confirmation." x:Name="LedgerArchiveSelected" Content="Archiver ce reçu…" Margin="0,0,8,8"/></WrapPanel></StackPanel></TabItem></TabControl></ScrollViewer></Expander></StackPanel>
</Grid></ScrollViewer>
<WrapPanel Grid.Row="1" Margin="0,10,0,0"><Button x:Name="LedgerObserve" Content="Vérifier l’état du poste" Style="{DynamicResource BtnAdd}"/><Button x:Name="LedgerAcknowledge" Content="Acquitter…" Margin="8,0,0,4" AutomationProperties.AutomationId="LedgerAcknowledge" ToolTip="Débloquer ce poste sans valider le résultat : le reçu garde son état réel, votre compte, l’heure et votre motif sont enregistrés. Aucune commande n’est lancée." AutomationProperties.HelpText="Débloquer ce poste sans valider le résultat : le reçu garde son état réel, votre compte, l’heure et votre motif sont enregistrés. Aucune commande n’est lancée."/><Button x:Name="LedgerReport" Content="Compte rendu" Margin="8,0,0,4"/><CheckBox x:Name="LedgerRedact" Content="Masquer poste et domaine" IsChecked="True" VerticalAlignment="Center" Margin="12,0,12,4" ToolTip="Décocher ajoute explicitement les noms du poste et du domaine au compte rendu."/><Button x:Name="LedgerClose" Content="Fermer" IsCancel="True"/></WrapPanel>
</Grid></Window>
'@
    $w=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($x));$w.Owner=$Win;$w.Resources=$Win.Resources;Set-WindowIcon $w
    $wa=[Windows.SystemParameters]::WorkArea;$w.MinWidth=[Math]::Min(600,$wa.Width-24);$w.MinHeight=[Math]::Min(400,$wa.Height-24);$w.MaxWidth=$wa.Width-24;$w.MaxHeight=$wa.Height-24
    $script:InterventionsUi=[pscustomobject]@{Window=$w;Grid=$w.FindName('LedgerGrid');Hint=$w.FindName('LedgerHint');Rows=@();Catalogue=$null;Offset=0;Loading=$false;PageSize=200}
    Register-PestoTable -Id interventions -Grid $script:InterventionsUi.Grid;Apply-PestoSavedTables;Apply-PestoDensity
    foreach($name in @('LedgerRefresh','LedgerExport','LedgerPrevious','LedgerNext','LedgerDetails','LedgerTasks','LedgerObserve','LedgerAcknowledge','LedgerReport','LedgerCompare','LedgerProtection','LedgerCleanup','LedgerImport','LedgerColumns','LedgerViews','LedgerTimeline','LedgerSupport','LedgerArchives','LedgerArchiveSelected','LedgerClose')){
        $button=$w.FindName($name);[Windows.Controls.ToolTipService]::SetShowOnDisabled($button,$true);[Windows.Automation.AutomationProperties]::SetName($button,[string]$button.Content)
        $button.Add_Click([Windows.RoutedEventHandler]${function:Invoke-PestoInterventionCommand})
    }
    $w.FindName('LedgerSearch').Add_TextChanged({if($script:InterventionsUi){$script:InterventionsUi.Offset=0;Update-PestoInterventionPage}})
    $w.FindName('LedgerState').Add_SelectionChanged({if($script:InterventionsUi){$script:InterventionsUi.Offset=0;Update-PestoInterventionPage}})
    $script:InterventionsUi|Add-Member -NotePropertyName ShowArchived -NotePropertyValue $false -Force
    $script:InterventionsUi.Grid.Add_SelectionChanged({Update-PestoInterventionActions})
    $w.Add_SizeChanged({param($sender,$e);$table=$sender.FindName('LedgerGrid');if($table){$table.Height=[Math]::Max(180.0,[Math]::Min(400.0,$sender.ActualHeight*0.40))}})
    $w.Add_Closing({param($sender,$e);if((Test-PestoAsyncOperationRunning 'RecoveryAction') -or (Test-PestoAsyncOperationRunning 'LedgerTasks')){$e.Cancel=$true}})
    try{Update-PestoInterventions;[void](Show-PestoHostedWindow $w)}finally{Stop-PestoAsyncOperation 'LedgerRead';$script:InterventionsUi=$null;if($script:PestoTables){[void]$script:PestoTables.Remove('interventions')}}
}

function Update-PestoInterventionActions {
    $ui=$script:InterventionsUi;if(-not $ui){return};$row=$ui.Grid.SelectedItem
    $valid=$row -and $row.Readable -and -not $ui.Loading
    foreach($name in @('LedgerDetails','LedgerTasks','LedgerObserve','LedgerReport','LedgerCompare','LedgerProtection','LedgerCleanup','LedgerTimeline','LedgerSupport','LedgerArchiveSelected')){$ui.Window.FindName($name).IsEnabled=[bool]$valid}
    $ui.Window.FindName('LedgerAcknowledge').IsEnabled=[bool]($valid -and -not $ui.ShowArchived -and -not $script:PestoReadOnly -and (Test-PestoAcknowledgementNeeded $row.Receipt))
    if($valid){
        $r=$row.Receipt;$ui.Window.FindName('LedgerObserve').IsEnabled=[bool]($r.Plan.Objet_GUID -or (Test-PestoJoinIntervention $r))
        $ui.Window.FindName('LedgerProtection').IsEnabled=($r.ResultCode -eq 32 -and -not $script:PestoReadOnly)
        $ui.Window.FindName('LedgerCleanup').IsEnabled=(@($r.Tasks | Where-Object{$_ -and $_.Phase -eq 'Finished'}).Count -gt 0 -and -not $script:PestoReadOnly)
        $ui.Window.FindName('LedgerTasks').IsEnabled=(@($r.Tasks | Where-Object{$_ -and $_.Phase -ne 'Deleted'}).Count -gt 0 -and -not $script:PestoReadOnly)
    }
    if($ui.ShowArchived){foreach($name in @('LedgerObserve','LedgerTasks','LedgerProtection','LedgerCleanup','LedgerArchiveSelected')){$ui.Window.FindName($name).IsEnabled=$false}}
    elseif($valid){$ui.Window.FindName('LedgerArchiveSelected').IsEnabled=(-not $script:PestoReadOnly -and (Test-PestoReceiptArchivable $row.Receipt))}
    $ui.Window.FindName('LedgerObserve').ToolTip=if($valid){$row.NextAction}else{'Sélectionnez un reçu lisible ; aucune lecture n''est possible tant que le registre se charge.'}
    $ui.Window.FindName('LedgerActionHint').Text=if($ui.Loading){'Lecture en cours ; les actions seront disponibles après réception du registre.'}elseif($row){$row.NextAction}else{'Sélectionnez une intervention pour connaître la prochaine action.'}
}

function Update-PestoInterventionPage {
    $ui=$script:InterventionsUi;if(-not $ui -or $ui.Loading){return}
    $state=[string]$ui.Window.FindName('LedgerState').SelectedItem.Tag;if(-not $state){$state='All'}
    $result=Get-PestoInterventionQuery -Rows $ui.Rows -Search $ui.Window.FindName('LedgerSearch').Text -State $state -Offset $ui.Offset -PageSize $ui.PageSize
    $ui.Offset=$result.Offset
    # Le registre relit des reçus à chaque actualisation : seules les lignes dont le reçu a changé sont
    # remplacées, la sélection suit l'identité du reçu (RowId) et le tri porté par la vue est conservé.
    [void](Update-PestoGridRows -Grid $ui.Grid -Rows $result.Items -IdProperty 'RowId')
    $ui.Window.FindName('LedgerPrevious').IsEnabled=($ui.Offset -gt 0);$ui.Window.FindName('LedgerNext').IsEnabled=($ui.Offset+$ui.PageSize -lt $result.MatchedCount)
    $ui.Window.FindName('LedgerExport').IsEnabled=($result.MatchedCount -gt 0 -and $ui.Catalogue -and -not $ui.Catalogue.Truncated)
    $ui.Window.FindName('LedgerPage').Text=if($result.MatchedCount){'{0}–{1} sur {2} résultats filtrés / {3} reçus lus' -f ($ui.Offset+1),[Math]::Min($ui.Offset+$ui.PageSize,$result.MatchedCount),$result.MatchedCount,$result.TotalCount}else{'Aucun résultat pour ces filtres.'}
    Update-PestoInterventionActions
}

function Update-PestoInterventions {
    param([switch]$Force)
    $ui=$script:InterventionsUi;if(-not $ui -or $ui.Loading){return}
    $ui.Loading=$true;$ui.Hint.Text='Lecture des reçus locaux…';$ui.Window.FindName('LedgerRefresh').IsEnabled=$false
    foreach($name in @('LedgerExport','LedgerPrevious','LedgerNext')){$ui.Window.FindName($name).IsEnabled=$false}
    Update-PestoInterventionActions
    try{
    $source=(Get-PestoWorkerCoreSource)+"`nfunction Get-PestoInterventionCatalogue {`n"+${function:Get-PestoInterventionCatalogue}.ToString()+"`n}"
        if(-not $script:PestoReceiptCatalogCache){$script:PestoReceiptCatalogCache=New-PestoInterventionCatalogCache}
        $readRoot=Get-PestoInterventionRoot;if($ui.ShowArchived){$readRoot=Join-Path $readRoot 'Archive'}
        $started=Start-PestoAsyncOperation -Name 'LedgerRead' -ScriptBlock {param($Source,$Cache,$Root,$Force);. ([scriptblock]::Create($Source));Get-PestoInterventionCatalogue -Root $Root -Cache $Cache -Force:$Force} -ArgumentList @($source,$script:PestoReceiptCatalogCache,$readRoot,[bool]$Force) -TimeoutSec 120 -CallbackContext $ui `
            -OnSuccess ${function:Complete-PestoInterventionRead} -OnError ${function:Fail-PestoInterventionRead}
        if(-not $started){Fail-PestoInterventionRead 'Une lecture est déjà active. Réessayez après sa fin.' $ui}
    }catch{Fail-PestoInterventionRead $_ $ui}
}
function Complete-PestoInterventionRead {
    param($Payload,$Context)
    if(-not [object]::ReferenceEquals($Context,$script:InterventionsUi)){return}
    $values=@($Payload);if($values.Count -ne 1){Fail-PestoInterventionRead 'Retour de lecture ambigu.' $Context;return}
    $oldVersion=if($Context.Catalogue){$Context.Catalogue.Version}else{$null}
    $Context.Loading=$false;$Context.Window.FindName('LedgerRefresh').IsEnabled=$true;$Context.Catalogue=$values[0]
    if($null -eq $oldVersion -or $oldVersion -ne $Context.Catalogue.Version){$Context.Rows=@(foreach($entry in $Context.Catalogue.Entries){ConvertTo-PestoInterventionRow $entry})}
    $Context.Hint.Text=('{0} reçu(s) valide(s), {1} illisible(s). Données locales à ce poste ; la vérification Entra reste distincte.' -f $Context.Catalogue.ValidCount,$Context.Catalogue.InvalidCount)
    if($Context.Catalogue.Truncated){$Context.Hint.Text+=' Registre limité aux 5 000 premiers fichiers lus : export désactivé. Faites archiver les reçus vérifiés par le support.'}
    Update-PestoInterventionPage
}
function Fail-PestoInterventionRead {
    param($ErrorRecord,$Context)
    if(-not [object]::ReferenceEquals($Context,$script:InterventionsUi)){return}
    $Context.Loading=$false;$Context.Window.FindName('LedgerRefresh').IsEnabled=$true;$Context.Rows=@();$Context.Catalogue=$null
    $Context.Hint.Text='Lecture des reçus impossible : '+(Protect-PestoLogText ([string]$ErrorRecord))+'. Aucun résultat partiel publié.';Update-PestoInterventionPage
}

function Invoke-PestoInterventionCommand {
    param($Sender,$EventArgs)
    $ui=$script:InterventionsUi;if(-not $ui){return}
    if($Sender.Name -eq 'LedgerClose'){if($script:RecoveryBusy){$ui.Hint.Text='La reprise est encore en cours.';return};$ui.Window.Close();return}
    if($Sender.Name -eq 'LedgerViews'){try{Invoke-PestoViewTool 'interventions'}catch{Show-MsgWarning $_.Exception.Message};return}
    if($Sender.Name -eq 'LedgerColumns'){try{Save-PestoTables;$ui.Hint.Text='Présentation enregistrée, sans sélection ni effet métier.'}catch{$ui.Hint.Text=$_.Exception.Message};return}
    if($Sender.Name -eq 'LedgerRefresh'){Update-PestoInterventions -Force;return}
    if($Sender.Name -in @('LedgerCompare','LedgerTimeline','LedgerSupport','LedgerArchives','LedgerArchiveSelected')){Invoke-PestoReceiptTool $Sender.Name;return}
    if($Sender.Name -in @('LedgerPrevious','LedgerNext')){$ui.Offset=[Math]::Max(0,$ui.Offset+$(if($Sender.Name -eq 'LedgerNext'){$ui.PageSize}else{-$ui.PageSize}));Update-PestoInterventionPage;return}
    if($Sender.Name -eq 'LedgerExport'){
        try{
            if($ui.Loading -or -not $ui.Catalogue -or $ui.Catalogue.Truncated){throw 'Actualisez un registre complet avant l’’export.'}
            $state=[string]$ui.Window.FindName('LedgerState').SelectedItem.Tag
            $result=Get-PestoInterventionQuery -Rows $ui.Rows -Search $ui.Window.FindName('LedgerSearch').Text -State $state -PageSize 5000
            if($result.Items.Count -ne $result.MatchedCount){throw 'Export incomplet refusé.'}
            $dialog=[Microsoft.Win32.SaveFileDialog]::new();$dialog.Filter='CSV (*.csv)|*.csv';$dialog.FileName='Pesto-interventions.csv'
            # Hosted sheets have no native window handle; the file dialog needs the visible host.
            $owner=if($ui.Window -and $ui.Window.IsVisible){$ui.Window}else{$Win}
            if($dialog.ShowDialog($owner)){Export-PestoInterventionRows -Path $dialog.FileName -Rows $result.Items;$ui.Hint.Text=([string]$result.MatchedCount+' lignes filtrées exportées.')}
        }catch{Show-MsgError $_.Exception.Message};return
    }
    if($Sender.Name -eq 'LedgerImport'){try{Import-PestoLegacyState;Update-PestoInterventions}catch{Show-MsgError $_.Exception.Message};return}
    $selected=$ui.Grid.SelectedItem
    if(-not $selected){Show-MsgInfo 'Sélectionnez une intervention.';return}
    if(-not $selected.Readable){Show-MsgInfo $selected.NextAction;return}
    $r=$selected.Receipt
    if($Sender.Name -eq 'LedgerReport'){$redact=[bool]$ui.Window.FindName('LedgerRedact').IsChecked;Show-PestoTextReport $(if($redact){'Compte rendu masqué'}else{'Compte rendu avec noms explicites'}) (Get-PestoOperationReport -Receipt $r -Redact $redact);return}
    if($Sender.Name -eq 'LedgerCompare'){
        if($script:PestoCompareReceipt){Show-PestoTextReport 'Différences observées' ((Compare-PestoInterventions $script:PestoCompareReceipt $r|Format-Table -AutoSize|Out-String -Width 180)+'Les différences ne prouvent pas une causalité.');$script:PestoCompareReceipt=$null}
        else{$script:PestoCompareReceipt=$r;$ui.Hint.Text='Première intervention choisie. Sélectionnez la seconde puis Comparer.'};return
    }
    if($Sender.Name -in @('LedgerProtection','LedgerCleanup')){
        try{Start-PestoRecovery -Receipt $r -Action $(if($Sender.Name -eq 'LedgerProtection'){'Protection'}else{'Cleanup'})}catch{Show-MsgError $_.Exception.Message};return
    }
    if($Sender.Name -eq 'LedgerTasks'){
        if($script:PestoReadOnly){Show-MsgInfo 'La réconciliation des tâches met à jour un reçu. Ouvrez une session d’’intervention pour cette action.';return}Start-PestoTaskReconciliation -Receipt $r;return}
    if($Sender.Name -eq 'LedgerDetails'){
        $detail=@('Intervention : '+$r.OperationId,'Version : '+$r.Version,'Dernière mise à jour locale : '+$selected.UpdatedLocal,
            'État : '+$selected.StatusLabel,'Nom actuel préparé : '+$r.Plan.Nom_du_PC,'Nom cible : '+$r.Plan.Nouveau_Nom,
            'OU source : '+$r.Plan.OU_Actuelle,'OU cible : '+$r.Plan.OU_Destination,'GUID AD : '+$r.Plan.Objet_GUID,
            'Contrôleur : '+$r.Plan.DC,'Identité Windows : '+$r.TargetMachineId,'Entra : '+$r.Entra,
            'Protection initiale : '+[string]$r.InitialProtection,'Protection : '+$r.Protection,
            'Renommage : '+$r.Rename,'Déplacement : '+$r.Move,'Résultat : '+$r.ResultCode,'Message : '+$r.ResultMessage)
        foreach($task in @($r.Tasks)){if($task){$detail+=('Tâche : '+$task.Computer+' / '+$task.Name+' / '+$task.Phase+' / code '+$task.NativeCode+' / SHA256 '+$task.Hash)}}
        $detail+="`r`nATTENDU / OBSERVÉ / RÉSULTAT"
        $detail+=(@(Get-PestoObservationComparison -Receipt $r)|Format-List|Out-String -Width 160)
        Show-PestoTextReport 'Pesto · Reçu d''intervention' ($detail -join "`r`n");return
    }
    if($Sender.Name -eq 'LedgerAcknowledge'){
        if($script:PestoReadOnly){Show-MsgInfo 'L''acquittement modifie un reçu. Ouvrez une session d''intervention pour cette action.';return}
        if(Invoke-PestoAcknowledgeFlow -Receipt $r){Update-PestoInterventions -Force};return
    }
    if($Sender.Name -eq 'LedgerObserve'){
        if(-not $r.Plan.Objet_GUID -and -not(Test-PestoJoinIntervention $r)){throw 'Ce reçu ne contient pas une identité permettant une lecture guidée.'}
        Show-PestoPostState -Mode Ledger -ReceiptOverride $r
        Update-PestoInterventions
    }
}

function Sync-PestoInterventionViews {
    param($Receipt,$Observation,$Decision)
    # Appelé uniquement après validation fraîche du reçu central et confirmation UI.
    if(Test-PestoJoinIntervention $Receipt){
        if(-not $Decision.Verified -or $Receipt.Phase -ne 'Verified'){throw 'Aucune jonction non vérifiée ne peut être libérée.'}
        $joinPath=Get-PestoJoinStatePath;$old=Read-PestoJoinReceipt $joinPath
        if($old -and ([Guid]$old.OperationId -eq [Guid]$Receipt.OperationId)){
            if($old.MachineId -ine $Receipt.TargetMachineId -or $old.Domain -ine $Receipt.Plan.Domain -or
               $old.NewName -ine $Receipt.Plan.Nouveau_Nom -or $old.OU -ine $Receipt.Plan.OU_Destination){throw 'Le reçu local de jonction a changé : aucun remplacement.'}
            $old.Phase='Verified';$old.Utc=[DateTime]::UtcNow.ToString('o');$old.Message=$Decision.Message
            Write-PestoJoinReceipt -Path $joinPath -Receipt $old
            $script:JoinReceipt=$old;$script:JoinLocked=$false
            Update-PestoJoinUI
        }
        Add-LogLine ('Jonction vérifiée après redémarrage : '+$Receipt.OperationId+'. État Entra distinct.') 'info'
        return
    }
    $direct=Read-PestoDirectReceipt (Get-PestoDirectStatePath)
    $isMatch=$direct -and ([Guid]$direct.OperationId -eq [Guid]$Receipt.OperationId)
    if($isMatch){Apply-PestoDirectObservation -Receipt $direct -Observation $Observation -Decision $Decision}
    if($script:table){
        foreach($row in @($script:table.Rows)){
            $id=[Guid]::Empty
            if([Guid]::TryParse([string]$row.Operation_ID,[ref]$id) -and $id -eq [Guid]$Receipt.OperationId -and
                ([string]$row.Statut -in @('INCERTAIN','TECHNIQUE','PROTECTION','EN COURS') -or [string]$row.Code -eq '89')){
                Apply-PestoQueueObservation $row $Observation $Decision
            }
        }
    }
    if($Decision.ResumeMove -and -not $isMatch){
        # Ne remplace jamais un ancien reçu non résolu pour lequel il n'existe pas de copie partagée.
        if($direct -and $direct.Phase -notin @('Failed','NotStarted','Verified') -and -not(Test-PestoAcknowledgedReceipt $direct)){
            $path=Join-Path (Get-PestoInterventionRoot) (([Guid]$direct.OperationId).ToString('N')+'.json')
            if(-not(Test-Path -LiteralPath $path)){throw 'Une ancienne opération unitaire doit être vérifiée avant de préparer ce déplacement.'}
        }
        if($direct){Write-PestoDirectReceipt -Path (Join-Path ([IO.Path]::GetDirectoryName((Get-PestoDirectStatePath))) ('archive\'+([Guid]$direct.OperationId).ToString('N')+'.json')) -Receipt $direct}
        $machine=[string](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid -ErrorAction Stop).MachineGuid
        $plan=$Receipt.Plan|Select-Object *
        if($Receipt.InitialProtection -is [bool]){$plan|Add-Member -NotePropertyName InitialProtection -NotePropertyValue $Receipt.InitialProtection -Force}
        $legacy=[pscustomobject]@{Schema=1;Version=$script:Pesto_VERSION;OperationId=$Receipt.OperationId;OperatorMachineId=$machine;
            LocalSource=($machine -ieq $Receipt.TargetMachineId);TargetMachineId=$Receipt.TargetMachineId;Phase='Partial';
            StartedUtc=$Receipt.StartedUtc;FinishedUtc=$Receipt.UpdatedUtc;ObservedUtc=$Receipt.VerifiedUtc;
            Plan=$plan;ResultCode=$Receipt.ResultCode;ResultMessage=$Receipt.ResultMessage;ResumeFrom=''}
        Write-PestoDirectReceipt -Path (Get-PestoDirectStatePath) -Receipt $legacy
        Apply-PestoDirectObservation -Receipt $legacy -Observation $Observation -Decision $Decision
        Set-PestoSuiteMode 'Single'
    }
    if($script:MutationUncertain -and @($script:QueueOperationIds).Count -gt 0){
        $allVerified=$true
        foreach($savedId in @($script:QueueOperationIds)){
            try{$entry=Read-PestoIntervention (Join-Path (Get-PestoInterventionRoot) (([Guid]$savedId).ToString('N')+'.json'))
                if($entry.Phase -notin @('Verified','Failed') -and -not(Test-PestoAcknowledgedReceipt $entry)){$allVerified=$false}
            }catch{$allVerified=$false}
        }
        if($allVerified){$script:MutationUncertain=$false;$script:UnmappedQueueLock=$false;Save-PestoQueueCheckpoint -Phase 'Reviewed';Update-QueueButtons;Update-AddButton}
    }
    Add-LogLine ('Intervention vérifiée : '+$Receipt.OperationId+'. Réinscription Entra non certifiée par cette lecture.') 'info'
}

function Set-PestoOperationAcknowledgement {
    <# Acquittement explicite (décision de David du 15/10) : mêmes auteur, date, motif et lecture recopiés dans chaque reçu
       non résolu de l'opération (registre, unitaire, jonction), chacun avec SA phase et SON code. Phase, code, effets et
       messages restent inchangés : jamais un succès. Refusé tant qu'une mutation peut encore travailler. #>
    param([Parameter(Mandatory=$true)][string]$OperationId,[Parameter(Mandatory=$true)][string]$Reason,$Observation=$null)
    if($script:PestoReadOnly -or $script:SIM -or $script:GUI){throw 'Acquittement impossible en consultation, simulation ou démonstration : aucun reçu modifié.'}
    if($script:Running -or $script:PreflightRunning -or $script:DirectBusy -or $script:JoinBusy -or (Test-PestoQueueWorkerStillActive) -or
        (Test-PestoAsyncOperationRunning 'DirectAction') -or (Test-PestoAsyncOperationRunning 'QueueAction') -or (Test-PestoAsyncOperationRunning 'DomainJoin')){
        throw 'Une opération est encore active : aucun acquittement.'
    }
    $id=[Guid]::Empty
    if(-not [Guid]::TryParse($OperationId,[ref]$id) -or $id -eq [Guid]::Empty){throw 'Identifiant d''opération invalide.'}
    $text=([string]$Reason -replace '[\x00-\x1f\x7f]',' ').Trim()
    if($text.Length -lt 3){throw 'Indiquez un motif d''acquittement (3 caractères au moins).'}
    if($text.Length -gt 500){$text=$text.Substring(0,500).Trim()}
    $snapshot=$null
    if($Observation -and ($Observation.AD -or $Observation.Windows -or $Observation.Health)){
        $when=[DateTimeOffset]::MinValue
        if(-not [DateTimeOffset]::TryParse([string]$Observation.ObservedUtc,[ref]$when) -or ([DateTimeOffset]::UtcNow-$when).TotalSeconds -gt 600){throw 'Lecture trop ancienne : relisez l''état avant d''acquitter.'}
        $snapshot=ConvertTo-PestoObservationSnapshot $Observation
    }
    $utc=[DateTime]::UtcNow.ToString('o');$by=[Security.Principal.WindowsIdentity]::GetCurrent().Name
    $done=[Collections.Generic.List[string]]::new();$notes=[Collections.Generic.List[string]]::new();$ledger=$null
    $mutex=$null;$owned=$false
    try{
        $mutex=[Threading.Mutex]::new($false,'Global\GP_PostMutation_v1')
        try{$owned=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$owned=$true}
        if(-not $owned){throw 'Une mutation détient encore le verrou machine : aucun acquittement.'}
        $key=$id.ToString('N')
        # Registre d'abord : le moteur relit ce reçu avant toute nouvelle opération sur la cible.
        $ledgerPath=Join-Path (Get-PestoInterventionRoot) ($key+'.json')
        if([IO.File]::Exists($ledgerPath)){
            $ledger=Read-PestoIntervention $ledgerPath
            if($ledger.Plan.Domain -ine $script:DOMAINE){throw 'Ce reçu appartient à un autre domaine.'}
            if(@($ledger.Tasks|Where-Object{$_ -and $_.Phase -notin @('Finished','Deleted')}).Count){throw 'Une tâche Windows peut encore agir sur ce poste. Utilisez « Relire les tâches » dans Interventions pour confirmer sa fin avant d''acquitter.'}
            if(Test-PestoAcknowledgementNeeded $ledger){
                $ledger|Add-Member -NotePropertyName Acknowledged -NotePropertyValue (New-PestoAcknowledgement -Receipt $ledger -Utc $utc -By $by -Reason $text -Observation $snapshot) -Force
                if($snapshot){$ledger|Add-Member -NotePropertyName LastObservation -NotePropertyValue $snapshot -Force}
                $ledger|Add-Member -NotePropertyName UpdatedUtc -NotePropertyValue $utc -Force
                $ledger|Add-Member -NotePropertyName LastStage -NotePropertyValue 'Acknowledged' -Force
                Add-PestoInterventionEvent -Receipt $ledger -Stage 'Acknowledged' -State ([string]$ledger.Phase)
                Write-PestoIntervention $ledger
                $done.Add('registre des interventions')
            }
        }
        $directPath=Get-PestoDirectStatePath;$direct=$null
        try{$direct=Read-PestoDirectReceipt $directPath}catch{$notes.Add('Reçu unitaire illisible : non modifié.')}
        if($direct -and ([Guid][string]$direct.OperationId) -eq $id -and $direct.OperatorMachineId -ieq $script:HostMachineId -and $direct.Plan.Domain -ieq $script:DOMAINE -and (Test-PestoAcknowledgementNeeded $direct)){
            $direct|Add-Member -NotePropertyName Acknowledged -NotePropertyValue (New-PestoAcknowledgement -Receipt $direct -Utc $utc -By $by -Reason $text -Observation $snapshot) -Force
            Write-PestoDirectReceipt -Path $directPath -Receipt $direct
            $script:DirectReceipt=$direct;$script:DirectLocked=$false
            $script:DirectMessage='Dernière opération unitaire acquittée · '+$direct.Plan.Nom_du_PC+' → '+$direct.Plan.Nouveau_Nom
            $script:DirectAdvice=Get-PestoAcknowledgementText $direct
            $done.Add('opération unitaire')
        }
        $joinPath=Get-PestoJoinStatePath;$join=$null
        try{$join=Read-PestoJoinReceipt $joinPath}catch{$notes.Add('Reçu local de jonction illisible : non modifié.')}
        if($join -and ([Guid][string]$join.OperationId) -eq $id -and $join.MachineId -ieq $script:HostMachineId -and $join.Domain -ieq $script:DOMAINE -and (Test-PestoAcknowledgementNeeded $join)){
            $join|Add-Member -NotePropertyName Acknowledged -NotePropertyValue (New-PestoAcknowledgement -Receipt $join -Utc $utc -By $by -Reason $text -Observation $snapshot) -Force
            Write-PestoJoinReceipt -Path $joinPath -Receipt $join
            $script:JoinReceipt=$join
            if(-not $script:JoinADReservationNeedsReview){$script:JoinLocked=$false}
            $done.Add('jonction locale')
        }
        if(-not $done.Count){throw 'Aucun reçu non résolu de cette opération à acquitter : déjà vérifié, refusé, acquitté ou en suivi facultatif.'}
        if($ledger -and (Test-PestoAcknowledgedReceipt $ledger) -and $notes.Count -eq 0){
            try{Exit-PestoCoordination -Receipt $ledger -Policy (ConvertTo-PestoPolicy $script:CFG.POLICY)}catch{$notes.Add('Verrous partagés conservés : '+(Protect-PestoLogText $_.Exception.Message))}
        }
    }finally{if($mutex){try{if($owned){$mutex.ReleaseMutex()}}finally{$mutex.Dispose()}}}
    $line='Acquittement sans vérification '+$key+' par '+$by+' ('+($done -join ', ')+') : '+$text
    try{Write-AuditLine $line 'warn'}catch{}
    Add-LogLine $line 'warn'
    Update-QueueButtons;Update-AddButton;Update-PestoSuiteUI
    if($script:JoinUI){try{Update-PestoJoinUI}catch{}}
    $message='Acquitté : '+($done -join ', ')+'. Le résultat réel reste dans l''historique, jamais compté comme réussi. La prochaine opération repartira d''une lecture complète du poste.'
    if($notes.Count){$message+=' '+($notes -join ' ')}
    return [pscustomobject]@{OperationId=$key;Receipts=$done.ToArray();Message=$message}
}

function Get-PestoAcknowledgeSummary {
    param($Receipt,$Observation=$null)
    $lines=[Collections.Generic.List[string]]::new()
    $code=if($Receipt.PSObject.Properties['ResultCode'] -and $null -ne $Receipt.ResultCode){' (code '+[string]$Receipt.ResultCode+')'}else{''}
    $computer=if($Receipt.Plan){[string]$Receipt.Plan.Nom_du_PC}else{[string]$Receipt.Computer}
    $target=if($Receipt.Plan){[string]$Receipt.Plan.Nouveau_Nom}else{[string]$Receipt.NewName}
    $lines.Add('Poste '+$computer+$(if($target -and $target -ine $computer){' → '+$target}else{''})+' : '+(Get-PestoStatePresentation ([string]$Receipt.Phase)).Label+$code+'.')
    $lines.Add('Ce résultat reste tel quel dans l''historique : il n''est pas compté comme réussi. Le poste n''est plus bloqué ; la prochaine opération repartira d''une lecture complète (AD, Windows, Entra). Aucune commande n''est lancée par cet acquittement.')
    if($Receipt.PSObject.Properties['Entra'] -and [string]$Receipt.Entra -in @('Requested','Uncertain')){
        $lines.Add('Entra : retrait demandé sans contrôle final. Vérifiez « dsregcmd /status » sur le poste et prévoyez la réinscription hybride si AzureAdJoined vaut NO.')
    }
    $pending=@($Receipt.Tasks|Where-Object{$_ -and $_.Phase -notin @('Finished','Deleted')})
    if($pending.Count){$lines.Add('Attention : '+$pending.Count+' tâche(s) Windows non confirmée(s) terminée(s) ; elles peuvent encore s''exécuter sur la cible. « Relire les tâches » dans Interventions doit confirmer leur fin avant l''acquittement.')}
    if(-not($Observation -and ($Observation.AD -or $Observation.Windows -or $Observation.Health))){$lines.Add('Aucune lecture d''état jointe : l''acquittement sera enregistré sans observation.')}
    return ($lines -join "`n`n")
}

function Show-PestoAcknowledgeDialog {
    <# Saisie du motif. Retourne le motif ou $null si l'opérateur annule. Aucune écriture ici. #>
    param([string]$Summary)
    [xml]$x=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Pesto · Acquitter sans valider" Width="660" Height="460" MinWidth="420" MinHeight="300" WindowStartupLocation="CenterOwner" Background="{DynamicResource BgWindow}" Foreground="{DynamicResource FgText}" FontFamily="Segoe UI" FontSize="13" UseLayoutRounding="True">
<Grid Margin="20"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
<TextBlock Text="Acquitter sans valider" FontSize="20" FontWeight="SemiBold" Margin="0,0,0,10"/>
<ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto"><TextBlock x:Name="AckSummary" TextWrapping="Wrap"/></ScrollViewer>
<TextBlock Grid.Row="2" Text="Motif (obligatoire, conservé dans le reçu avec votre compte et l’heure)" Margin="0,14,0,4"/>
<TextBox x:Name="AckReason" Grid.Row="3" MaxLength="500" AutomationProperties.AutomationId="AckReason" AutomationProperties.Name="Motif de l’acquittement" ToolTip="Exemple : poste relu, nom inchangé, Entra retiré ; réinscription demandée au support. Trois caractères au moins." AutomationProperties.HelpText="Motif conservé dans le reçu. Trois caractères au moins." ToolTipService.ShowOnDisabled="True"/>
<WrapPanel Grid.Row="4" HorizontalAlignment="Right" Margin="0,16,0,0"><Button x:Name="AckConfirm" Content="Acquitter" IsEnabled="False" AutomationProperties.AutomationId="AckConfirm" ToolTip="Enregistrer l’acquittement. Le résultat réel est conservé ; aucune commande n’est lancée." AutomationProperties.HelpText="Enregistrer l’acquittement. Le résultat réel est conservé ; aucune commande n’est lancée." ToolTipService.ShowOnDisabled="True"/><Button x:Name="AckCancel" Content="Annuler" IsCancel="True" Margin="8,0,0,0" AutomationProperties.AutomationId="AckCancel" ToolTip="Fermer sans rien enregistrer." AutomationProperties.HelpText="Fermer sans rien enregistrer." ToolTipService.ShowOnDisabled="True"/></WrapPanel>
</Grid></Window>
'@
    $w=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($x));if($Win){$w.Owner=$Win;$w.Resources=$Win.Resources};Set-WindowIcon $w
    $w.FindName('AckSummary').Text=$Summary
    $script:PestoAckDialog=[pscustomobject]@{Window=$w;Reason=$w.FindName('AckReason');Confirm=$w.FindName('AckConfirm');Result=$null}
    $script:PestoAckDialog.Reason.Add_TextChanged([Windows.Controls.TextChangedEventHandler]${function:Invoke-PestoAckReasonChanged})
    $script:PestoAckDialog.Confirm.Add_Click([Windows.RoutedEventHandler]${function:Invoke-PestoAckConfirmClick})
    $w.FindName('AckCancel').Add_Click([Windows.RoutedEventHandler]${function:Invoke-PestoAckCancelClick})
    try{[void](Show-PestoHostedWindow $w);return $script:PestoAckDialog.Result}
    finally{$script:PestoAckDialog=$null}
}
function Invoke-PestoAckReasonChanged {param($Sender,$EventArgs);$d=$script:PestoAckDialog;if($d){$d.Confirm.IsEnabled=((([string]$d.Reason.Text) -replace '[\x00-\x1f\x7f]',' ').Trim().Length -ge 3)}}
function Invoke-PestoAckConfirmClick {
    param($Sender,$EventArgs)
    $d=$script:PestoAckDialog;if(-not $d){return}
    $text=(([string]$d.Reason.Text) -replace '[\x00-\x1f\x7f]',' ').Trim();if($text.Length -lt 3){return}
    $d.Result=$text;$d.Window.Close()
}
function Invoke-PestoAckCancelClick {param($Sender,$EventArgs);$d=$script:PestoAckDialog;if($d){$d.Result=$null;$d.Window.Close()}}

function Invoke-PestoAcknowledgeFlow {
    <# Point d'entrée commun (fiche État, Interventions) : résumé honnête, motif, puis acquittement. #>
    param($Receipt,$Observation=$null)
    if(-not $Receipt){Show-MsgInfo 'Aucun reçu à acquitter.';return $false}
    if(-not(Test-PestoAcknowledgementNeeded $Receipt)){Show-MsgInfo 'Ce reçu ne bloque pas de nouvelle opération : rien à acquitter.';return $false}
    $reason=Show-PestoAcknowledgeDialog -Summary (Get-PestoAcknowledgeSummary -Receipt $Receipt -Observation $Observation)
    if(-not $reason){return $false}
    try{$result=Set-PestoOperationAcknowledgement -OperationId ([string]$Receipt.OperationId) -Reason $reason -Observation $Observation;Show-MsgInfo $result.Message;return $true}
    catch{Show-PestoUsefulError -Title 'Acquittement non enregistré' -Message $_.Exception.Message -Stage 'Acquittement' -MutationPossible $false;return $false}
}

function Initialize-PestoInterventionsUI {
    $button=$Win.FindName('BtnInterventions')
    if($button){$button.Add_Click([Windows.RoutedEventHandler]${function:Open-PestoInterventionCenter})}
}
function Open-PestoInterventionCenter {param($Sender,$EventArgs);Show-PestoInterventions}


function Invoke-PestoTaskReconciliationWorker {
    param($Request,$Source)
    Set-StrictMode -Off;$ErrorActionPreference='Stop'
    . ([scriptblock]::Create($Source))
    $script:GUI=$false;$script:SIM=$false;$script:cred=$Request.Credential
    if($env:PESTO_READONLY_SESSION -eq '1'){throw 'Réconciliation interdite en consultation.'}
    function Write-Log {param($Message,$Level,$ErrorRecord,$Context)}
    $mutex=$null;$owned=$false;$r=$null;$auditStarted=$false
    try {
        $mutex=[Threading.Mutex]::new($false,'Global\GP_PostMutation_v1')
        try{$owned=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$owned=$true}
        if(-not $owned){throw 'Une opération est active. Relisez les tâches après sa fin.'}
        $id=[Guid]::Empty
        if(-not [Guid]::TryParse([string]$Request.OperationId,[ref]$id) -or $id -eq [Guid]::Empty){throw 'Intervention invalide.'}
        $r=Read-PestoIntervention (Join-Path (Get-PestoInterventionRoot) ($id.ToString('N')+'.json'))
        if($r.Plan.Domain -ine $Request.Domain){throw 'Le domaine du reçu ne correspond pas à la session.'}
        $script:ActiveIntervention=$r
        $notes=[Collections.Generic.List[string]]::new();$taskIndex=0;$auditStarted=$true
        Write-PestoReconciliationAudit $r TaskRead Requested
        foreach($task in @($r.Tasks)){
            $taskIndex++
            if(-not $task -or $task.Phase -eq 'Deleted'){continue}
            if(-not $task.Hash){Write-PestoReconciliationAudit $r TaskRead NoDefinition -TaskIndex $taskIndex;$notes.Add($task.Name+' : définition initiale non confirmée, contrôle manuel nécessaire.');continue}
            # Query-only COM path. Get-PestoTaskRunResult verifies the full stored XML hash.
            $result=Get-PestoTaskRunResult -TaskName $task.Name -Transport @('/s',$task.Computer) -TimeoutSec 8
            if($result -and $result.State -eq 'READY'){
                Write-PestoReconciliationAudit $r TaskRead Ready -TaskIndex $taskIndex -NativeCode ([long]$result.ResultNum)
                $notes.Add($task.Name+' : fin confirmée, code '+$result.ResultNum)
                if($task.Name -match '^\\Pesto_DsregLeave_' -and $r.Entra -in @('Requested','Uncertain')){
                    if($result.ResultNum -eq 42){Set-PestoEffect Entra 'Confirmed'}
                    elseif($result.ResultNum -eq 43){Set-PestoEffect Entra 'Skipped'}
                }
            }else{Write-PestoReconciliationAudit $r TaskRead Unknown -TaskIndex $taskIndex;$notes.Add($task.Name+' : pas de fin confirmée. Aucune suppression ni relance.')}
        }
        # A local dsreg subprocess can finish after its parent's supervision. Read only
        # the exact target-side receipt after matching the local machine identity.
        if($r.Entra -in @('Requested','Uncertain')){
            $machine=[string](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid -ErrorAction Stop).MachineGuid
            if($r.TargetMachineId -and $r.TargetMachineId -ieq $machine){
                $path=[IO.Path]::Combine([Environment]::GetFolderPath('CommonApplicationData'),'GP','Entra',$id.ToString('N')+'.json')
                Assert-PestoPlainPath $path
                if([IO.File]::Exists($path)){
                    $item=Get-Item -LiteralPath $path -Force -ErrorAction Stop
                    if($item.Length -gt 16384){throw 'Reçu Entra trop volumineux.'}
                    $local=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json
                    if($local.Schema -eq 1 -and $local.OperationId -ceq $id.ToString('N') -and $local.Computer -ieq $r.Plan.Nom_du_PC -and
                       $local.Phase -eq 'LeaveConfirmed_ReenrollmentPending'){
                        Set-PestoEffect Entra 'Confirmed';$notes.Add('Reçu local : retrait Entra terminé, réinscription restant à vérifier.')
                    }
                }
            }
        }
        if(-not $notes.Count){Write-PestoReconciliationAudit $r TaskRead Empty;$notes.Add('Aucune tâche enregistrée à relire. Le reçu d''intervention est conservé.')}
        return [pscustomobject]@{OperationId=$r.OperationId;Message=($notes -join "`r`n")}
    }catch{
        if($r -and $auditStarted){try{Write-PestoReconciliationAudit $r TaskRead Unknown}catch{}}
        throw
    }finally{
        $script:ActiveIntervention=$null;$script:cred=$null
        if($mutex){try{if($owned){$mutex.ReleaseMutex()}}finally{$mutex.Dispose()}}
    }
}

function Start-PestoTaskReconciliation {
    param($Receipt)
    if($script:PestoReadOnly){throw 'Réconciliation interdite en consultation ; le reçu doit rester inchangé.'}
    $ui=$script:InterventionsUi
    if(-not $ui -or $script:Running -or $script:DirectBusy -or $script:JoinBusy){Show-MsgInfo 'Attendez la fin de l''opération active.';return}
    if(Test-PestoAsyncOperationRunning 'LedgerTasks'){return}
    $req=[pscustomobject]@{OperationId=$Receipt.OperationId;Domain=$script:DOMAINE;Credential=$script:cred}
    $ui.Hint.Text='Lecture des tâches du reçu, sans lancement ni suppression...'
    [void](Start-PestoAsyncOperation -Name 'LedgerTasks' -ScriptBlock ${function:Invoke-PestoTaskReconciliationWorker} `
        -ArgumentList @($req,(Get-PestoWorkerCoreSource)) -CallbackContext $ui `
        -OnSuccess ${function:Complete-PestoTaskReconciliation} -OnError ${function:Fail-PestoTaskReconciliation} -TimeoutSec 100)
}
function Complete-PestoTaskReconciliation {
    param($Payload,$Context)
    if(-not [object]::ReferenceEquals($Context,$script:InterventionsUi)){return}
    $data=@($Payload)
    if($data.Count -ne 1){$Context.Hint.Text='Retour de lecture ambigu. Aucun verrou levé.';return}
    Update-PestoInterventions;$Context.Hint.Text=$data[0].Message+' Vérifiez ensuite l''état du poste.'
    Add-LogLine ('Relecture des tâches consignée : '+[string]$data[0].OperationId+'. '+[string]$data[0].Message) 'info'
}
function Fail-PestoTaskReconciliation {
    param($ErrorRecord,$Context)
    if([object]::ReferenceEquals($Context,$script:InterventionsUi)){$Context.Hint.Text='Lecture interrompue : '+(Protect-PestoLogText ([string]$ErrorRecord))+'. Aucun verrou levé.'}
}

function Get-PestoHomeLocalSnapshot {
    # Local Windows observation only; deliberately independent from AD and the
    # operation receipts. A failed read never becomes a workgroup assertion.
    $cs=Get-CimInstance -ClassName Win32_ComputerSystem -OperationTimeoutSec 15 -ErrorAction Stop
    if(@($cs).Count -ne 1 -or $cs.PartOfDomain -isnot [bool] -or -not $cs.Name -or -not $cs.Domain){throw 'Informations Windows locales incomplètes.'}
    $active=[string]$cs.Name;$configured='';$pending=$null
    try{
        $active=[string](Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName' -Name ComputerName -ErrorAction Stop).ComputerName
        $configured=[string](Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' -Name ComputerName -ErrorAction Stop).ComputerName
        if(-not $active){$active=[string]$cs.Name}
        if($active -and $configured){$pending=($active -ine $configured)}
    }catch{$active=[string]$cs.Name;$configured='';$pending=$null}
    [pscustomobject]@{Computer=$active.ToUpperInvariant();Domain=[string]$cs.Domain;PartOfDomain=[bool]$cs.PartOfDomain;ConfiguredName=$configured;PendingRename=$pending;CollectedUtc=[DateTime]::UtcNow.ToString('o')}
}

function Complete-PestoHomeRead {
    param($Result,$Context)
    $script:HomeReceiptsTick=[Diagnostics.Stopwatch]::GetTimestamp()
    $script:HomeLocalSnapshot=$Result.Local;$script:HomeReceiptCatalogue=$Result.Catalogue
    $script:HomeLocalError=[string]$Result.LocalError;$script:HomeReceiptsError=[string]$Result.ReceiptsError
    Update-PestoHomeDashboard
}

function Fail-PestoHomeRead {
    param($ErrorRecord,$Context)
    $script:HomeReceiptCatalogue=$null
    $script:HomeReceiptsError='Lecture des reçus locaux interrompue. Actualisez pour réessayer ; aucun état supposé résolu.'
    if(-not $script:HomeLocalSnapshot){$script:HomeLocalError='Informations Windows non lues : lecture interrompue.'}
    Update-PestoHomeDashboard
}

function Update-PestoHomeInterventions {
    Update-PestoHomeDashboard
    if($script:GUI -or $script:SIM){return}
    if(Test-PestoAsyncOperationRunning 'HomeReceipts'){return}
    if($script:HomeReceiptsTick -and ([Diagnostics.Stopwatch]::GetTimestamp()-$script:HomeReceiptsTick)/[double][Diagnostics.Stopwatch]::Frequency -lt 30){return}
    try {
    $source=(Get-PestoWorkerCoreSource)+"`nfunction Get-PestoInterventionCatalogue {`n"+${function:Get-PestoInterventionCatalogue}.ToString()+"`n}`nfunction Get-PestoHomeLocalSnapshot {`n"+${function:Get-PestoHomeLocalSnapshot}.ToString()+"`n}"
    # The local Windows snapshot is reused between visits. Only Actualiser clears
    # it. Receipts are re-read on a visit (at most once in 30 s), never by a pulse.
    if(-not $script:PestoReceiptCatalogCache){$script:PestoReceiptCatalogCache=New-PestoInterventionCatalogCache}
    $started=Start-PestoAsyncOperation -Name 'HomeReceipts' -ScriptBlock {
        param($Source,$CachedLocal,$Cache)
        . ([scriptblock]::Create($Source))
        $local=$CachedLocal;$catalogue=$null;$localError='';$receiptsError=''
        if(-not $local){try{$local=Get-PestoHomeLocalSnapshot}catch{$localError='Informations Windows non lues. Actualisez pour réessayer.'}}
        try{$catalogue=Get-PestoInterventionCatalogue -Cache $Cache}catch{$receiptsError='Reçus locaux non lus. Ouvrez les interventions pour réessayer.'}
        [pscustomobject]@{Local=$local;Catalogue=$catalogue;LocalError=$localError;ReceiptsError=$receiptsError}
      } -ArgumentList @($source,$script:HomeLocalSnapshot,$script:PestoReceiptCatalogCache) -TimeoutSec 120 -OnSuccess ${function:Complete-PestoHomeRead} -OnError ${function:Fail-PestoHomeRead}
    if(-not $started){Fail-PestoHomeRead -ErrorRecord 'Lecture locale non démarrée.' -Context $null}
    }catch{Fail-PestoHomeRead -ErrorRecord $_ -Context $null}
    Update-PestoHomeDashboard
}
