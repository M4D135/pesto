#requires -Version 5.1
# Repères de présentation communs à Pesto, ADCC et RBP. Aucun droit métier ici.

function Set-PestoSuiteMode {
    param([ValidateSet('Single','Batch')][string]$Mode)
    if($script:DirectBusy -or $script:Running -or $script:PreflightRunning){return}
    if(-not $script:INDOMAIN){Set-PestoUxPage 'Join';return}
    if($script:EDIT_ROW_INDEX -ge 0 -and $Mode -eq 'Single'){
        Show-MsgInfo 'Terminez ou annulez la modification de la ligne avant de revenir au mode unitaire.';return
    }
    $script:SuiteMode=$Mode
    Set-PestoUxPage 'Rename'
    Update-PestoSuiteUI
    Update-PestoUxLayout
    if($Mode -eq 'Batch' -and -not $script:InventoryLoaded -and -not $script:GUI){[void](Refresh-Names)}
}

function Set-PestoSuiteHelp {
    param([bool]$Visible)
    $script:HelpVisible=$Visible
    Update-PestoSuiteLayout
    if(-not $Visible){[void]$BtnHelp.Focus()}
    Save-Prefs
}

function Invoke-PestoSuiteCommand {
    param($Sender,$EventArgs)
    switch([string]$Sender.Name){
        'SuiteModeSingle' {Set-PestoSuiteMode 'Single'}
        'SuiteModeBatch' {Set-PestoSuiteMode 'Batch'}
        'NavBatch' {Set-PestoSuiteMode 'Batch'}
        'SuiteNavToggle' {$script:NavigationCollapsed=-not $script:NavigationCollapsed;Update-PestoSuiteLayout;Update-PestoUxLayout;Save-Prefs}
        'SuiteAppearanceNav' {$script:NavigationCollapsed=-not $script:NavigationCollapsed;Update-PestoSuiteLayout;Update-PestoUxLayout;Save-Prefs}
        'SuiteAppearanceHelp' {Set-PestoSuiteHelp (-not $script:HelpVisible)}
        'SuiteAppearanceDensity' {Invoke-PestoWorkspaceAction 'density'}
        'SuiteAppearanceSaveColumns' {Invoke-PestoWorkspaceAction 'save-columns'}
        'SuiteAppearanceResetColumns' {Invoke-PestoWorkspaceAction 'reset-columns'}
        'SuiteHelpClose' {Set-PestoSuiteHelp $false}
        'SuiteHelpGuide' {Set-PestoUxPage 'Help'}
        'SuiteHelpDiagnostic' {Export-Diagnostics}
        'SuiteLogDiagnostic' {Export-Diagnostics}
        'SuiteLogPlus' {$script:LogFontSize=[Math]::Min(22,$script:LogFontSize+1);Render-Log;Save-Prefs}
        'SuiteLogMinus' {$script:LogFontSize=[Math]::Max(10,$script:LogFontSize-1);Render-Log;Save-Prefs}
        'SuiteLogRefresh' {$script:LogForceRefresh=$true;Render-Log}
        'SuiteLogErrors' {Copy-PestoLogErrors}
        'SuitePostState' {Show-PestoPostState -Mode Inspect}
        'SuiteDirectRun' {Invoke-PestoPrimaryAction $Sender $EventArgs}
        'SuiteDirectCheck' {Start-PestoDirectPreflight}
        'SuiteDirectVerify' {Show-PestoPostState -Mode Direct}
        'SuiteDirectDetails' {Show-PestoDirectDetails}
        'SuiteDirectCancelRead' {Stop-PestoDirectPreflight}
    }
}

function Get-PestoResponsiveLayout {
    # Width is in WPF device-independent pixels, so display scaling is already accounted for.
    param([double]$Width,[double]$Height,[bool]$NavigationCollapsed,[bool]$HelpVisible)
    $navigation=if($NavigationCollapsed -or $Width -lt 760){68}else{194}
    $help=if($HelpVisible -and $Width -ge 1450){280}else{0}
    $content=[Math]::Max(0,$Width-$navigation-$help-44)
    [pscustomobject]@{ContentWidth=$content;SingleColumn=($content -lt 660);Short=($Height -lt 740);HomeColumns=$(if($content -lt 580){1}elseif($content -lt 900){2}else{4})}
}

function Get-PestoResponsiveFieldCell {
    param([int]$Row,[int]$Column,[bool]$SingleColumn)
    if($SingleColumn){return [pscustomobject]@{Row=([int]([Math]::Floor($Row/2))*4+$(if($Column -gt 0){2}else{0})+($Row%2));Column=0}}
    [pscustomobject]@{Row=$Row;Column=$Column}
}

function Set-PestoResponsiveColumnGroups {
    param($Fields,[bool]$SingleColumn)
    if(-not $Fields){return}
    if(-not $script:PestoColumnLayouts){$script:PestoColumnLayouts=@{}}
    $key=[string]$Fields.Name
    if(-not $script:PestoColumnLayouts.ContainsKey($key)){
        $script:PestoColumnLayouts[$key]=[pscustomobject]@{Single=$null;Widths=@($Fields.ColumnDefinitions|ForEach-Object{$_.Width});Cells=@(foreach($child in $Fields.Children){[pscustomobject]@{Control=$child;Column=[Windows.Controls.Grid]::GetColumn($child)}})}
    }
    $layout=$script:PestoColumnLayouts[$key]
    if($null -ne $layout.Single -and [bool]$layout.Single -eq $SingleColumn){return}
    $Fields.RowDefinitions.Clear()
    $index=0
    foreach($cell in $layout.Cells){
        if($SingleColumn){$row=[Windows.Controls.RowDefinition]::new();$row.Height=[Windows.GridLength]::Auto;$Fields.RowDefinitions.Add($row)}
        [Windows.Controls.Grid]::SetRow($cell.Control,$(if($SingleColumn){$index}else{0}))
        [Windows.Controls.Grid]::SetColumn($cell.Control,$(if($SingleColumn){0}else{$cell.Column}));$index++
    }
    for($i=0;$i -lt $Fields.ColumnDefinitions.Count;$i++){$Fields.ColumnDefinitions[$i].Width=if($SingleColumn){if($i -eq 0){[Windows.GridLength]::new(1,[Windows.GridUnitType]::Star)}else{[Windows.GridLength]::new(0)}}else{$layout.Widths[$i]}}
    $layout.Single=$SingleColumn
}

function Set-PestoResponsiveFieldPairs {
    param($Fields,[bool]$SingleColumn)
    if(-not $Fields){return}
    if(-not $script:PestoFieldLayouts){$script:PestoFieldLayouts=@{}}
    $key=[string]$Fields.Name
    if(-not $script:PestoFieldLayouts.ContainsKey($key)){
        $cells=@(foreach($child in $Fields.Children){[pscustomobject]@{Control=$child;Row=[Windows.Controls.Grid]::GetRow($child);Column=[Windows.Controls.Grid]::GetColumn($child)}})
        $script:PestoFieldLayouts[$key]=[pscustomobject]@{Cells=$cells;Rows=$Fields.RowDefinitions.Count;Single=$null}
    }
    $layout=$script:PestoFieldLayouts[$key]
    if($null -ne $layout.Single -and [bool]$layout.Single -eq $SingleColumn){return}
    $Fields.RowDefinitions.Clear()
    $rows=if($SingleColumn){$layout.Rows*2}else{$layout.Rows}
    for($i=0;$i -lt $rows;$i++){$row=[Windows.Controls.RowDefinition]::new();$row.Height=[Windows.GridLength]::Auto;$Fields.RowDefinitions.Add($row)}
    $Fields.ColumnDefinitions[1].Width=[Windows.GridLength]::new($(if($SingleColumn){0}else{18}))
    $Fields.ColumnDefinitions[2].Width=if($SingleColumn){[Windows.GridLength]::new(0)}else{[Windows.GridLength]::new(1,[Windows.GridUnitType]::Star)}
    foreach($cell in $layout.Cells){
        $position=Get-PestoResponsiveFieldCell $cell.Row $cell.Column $SingleColumn
        [Windows.Controls.Grid]::SetRow($cell.Control,$position.Row)
        [Windows.Controls.Grid]::SetColumn($cell.Control,$position.Column)
    }
    $layout.Single=$SingleColumn
}

function Update-PestoSuiteLayout {
    if(-not $script:SuiteReady -or -not $Win){return}
    $u=$script:SuiteUI
    $logical=Get-PestoUiLayoutSize
    $responsive=Get-PestoResponsiveLayout -Width $logical.Width -Height $logical.Height -NavigationCollapsed ([bool]$script:NavigationCollapsed) -HelpVisible ([bool]$script:HelpVisible)
    $homeActionsPanel=$Win.FindName('HomeActions');if($homeActionsPanel){$homeActionsPanel.Columns=$responsive.HomeColumns}
    $tools=$Win.FindName('SuiteHeaderTools');$badges=$Win.FindName('SuiteHeaderBadges')
    if($tools -and $badges){
        [Windows.Controls.Grid]::SetRow($tools,$(if($responsive.SingleColumn){1}else{0}))
        [Windows.Controls.Grid]::SetColumn($tools,$(if($responsive.SingleColumn){0}else{1}))
        [Windows.Controls.Grid]::SetColumnSpan($tools,$(if($responsive.SingleColumn){2}else{1}))
        [Windows.Controls.Grid]::SetColumnSpan($badges,$(if($responsive.SingleColumn){2}else{1}))
        $tools.Margin=if($responsive.SingleColumn){[Windows.Thickness]::new(0,8,0,0)}else{[Windows.Thickness]::new(10,0,0,0)}
    }
    foreach($name in @('RenameScopeFields','RenameNameFields')){Set-PestoResponsiveColumnGroups ($Win.FindName($name)) $responsive.SingleColumn}
    if($script:JoinUI){Set-PestoResponsiveFieldPairs $script:JoinUI.Fields $responsive.SingleColumn}
    $collapsed=([bool]$script:NavigationCollapsed -or $logical.Width -lt 760)
    $SidebarWidth.Width=[Windows.GridLength]::new($(if($collapsed){68}else{194}))
    $u.SuiteSidebarGrid.Margin=[Windows.Thickness]::new($(if($collapsed){6}else{14}),20,$(if($collapsed){6}else{14}),16)
    foreach($n in @('NavHome','NavRename','NavBatch','NavJoin','NavNames','NavHistory','NavLogs','NavSettings')){
        $b=$Win.FindName($n);$label=$Win.FindName($n+'Label')
        if($label){$label.Visibility=if($collapsed){'Collapsed'}else{'Visible'}}
        if($b){$b.Padding=[Windows.Thickness]::new($(if($collapsed){10}else{12}),10,$(if($collapsed){5}else{8}),10)}
    }
    foreach($n in @('SuiteBrandLabel','SuiteBrandHint','SuiteNavFooter')){$u[$n].Visibility=if($collapsed){'Collapsed'}else{'Visible'}}
    $u.SuiteBrand.Margin=[Windows.Thickness]::new($(if($collapsed){6}else{11}),0,0,20)
    $Win.FindName('NavHelp').Content=if($collapsed){'?'}else{'?   Aide et raccourcis'}
    $u.SuiteNavToggle.ToolTip=if($collapsed){'Déployer le menu : icônes et libellés.'}else{'Réduire le menu : conserver uniquement les icônes.'}
    $u.SuiteNavToggle.HorizontalAlignment=if($collapsed){'Center'}else{'Left'}
    [Windows.Automation.AutomationProperties]::SetName($u.SuiteNavToggle,$u.SuiteNavToggle.ToolTip)
    $glyph=if($collapsed){'M2,2 L20,2 20,18 2,18 Z M8,2 L8,18 M12,6 L16,10 12,14'}else{'M2,2 L20,2 20,18 2,18 Z M8,2 L8,18 M16,6 L12,10 16,14'}
    $u.SuiteNavToggleGlyph.Data=[Windows.Media.Geometry]::Parse($glyph)
    $u.SuiteHelpPanel.Visibility=if($script:HelpVisible){'Visible'}else{'Collapsed'}
    if($script:HelpVisible -and $logical.Width -ge 1450){
        $u.SuiteHelpWidth.Width=[Windows.GridLength]::new(280)
        [Windows.Controls.Grid]::SetColumn($u.SuiteHelpPanel,2)
        $u.SuiteHelpPanel.Width=[double]::NaN;$u.SuiteHelpPanel.HorizontalAlignment='Stretch'
        $u.SuiteHelpPanel.Margin=[Windows.Thickness]::new(0)
    }else{
        $u.SuiteHelpWidth.Width=[Windows.GridLength]::new(0)
        [Windows.Controls.Grid]::SetColumn($u.SuiteHelpPanel,1)
        $u.SuiteHelpPanel.Width=[Math]::Min(320,[Math]::Max(220,$logical.Width-100))
        $u.SuiteHelpPanel.HorizontalAlignment='Right';$u.SuiteHelpPanel.Margin=[Windows.Thickness]::new(0,65,12,12)
    }
}

function Update-PestoSuiteHelp {
    if(-not $script:SuiteReady){return}
    $u=$script:SuiteUI
    $pages=@{
        0=@('Un poste, ou un lot','Un poste : lire, choisir le nom, vérifier puis confirmer. Aucun passage par la file. Plusieurs postes : utiliser la file, contrôler puis exécuter les lignes cochées. Le site change ? Le déplacement suit seulement un renommage confirmé.')
        1=@('Noms proposés','L''inventaire est chargé à la demande. Un nom affiché comme libre ne constitue pas une réservation AD. Pesto refait les vérifications critiques avant une écriture.')
        2=@('Deux sortes de préférences','Apparence : immédiate, liée à votre utilisateur de départ. Domaine : sauvegarde explicite ; un changement conserve les plans et impose leur nouveau contrôle. Les modes de test ne donnent aucun droit.')
        3=@('Lire sans interrompre','Décochez Suivre pour garder les messages à l''écran. Les nouveaux événements restent dans le journal. Une recherche ou un changement de taille ne modifie pas l''action en cours.')
        4=@('Le bon parcours',"Ce PC hors domaine : $(Get-PestoUxNom 'BtnAjouterPc'). Une modification : $(Get-PestoUxNom 'PagePoste'). Plusieurs machines : $(Get-PestoUxNom 'PageLot'). L'inventaire complet n'est pas requis pour ouvrir Pesto.")
        5=@('Une trace, pas une relance','L''historique décrit les résultats connus. Il ne relance aucune opération. Pour un résultat partiel ou incertain, relire l''état avant de choisir la prochaine étape.')
        6=@('Clavier et aides','F6 et Maj+F6 changent de zone. F1 explique le contrôle actif. Entrée dans le nom du poste lance sa lecture uniquement. Ctrl+F recherche dans la page active. Les infobulles restent actives lorsque ce panneau est fermé.')
        7=@('Ajouter uniquement ce PC','Compléter le nom et l''emplacement, vérifier puis confirmer. Aucun ajout à la file. La configuration impose l''OU réellement utilisée. Le redémarrage reste un choix explicite après acceptation.')
    }
    $p=$pages[[int]$MainTabs.SelectedIndex]
    if($p){$u.SuiteHelpTitle.Text=$p[0];$u.SuiteHelpText.Text=$p[1]}
    $u.SuiteHelpAccount.Text=[string]$script:AuthUser
}

function Get-PestoModeChip {
    param([bool]$Demo,[bool]$Simulation,[bool]$ReadOnly)
    if($Demo){return 'DÉMONSTRATION'}
    if($Simulation){return 'SIMULATION'}
    if($ReadOnly){return 'CONSULTATION'}
    return 'RÉEL'
}
function Get-PestoBlockState {
    param([bool]$RestartRequired,[bool]$GlobalBarrier,[bool]$JoinLocked,[bool]$Incident)
    $text=if($RestartRequired){'Configuration enregistrée : relancez Pesto pour appliquer le domaine ou le mode.'}
        elseif($Incident){'Mode incident : les mutations sont suspendues par la configuration.'}
        elseif($GlobalBarrier){'Une exécution reste indéterminée. Ouvrez les interventions pour examiner son état.'}
        elseif($JoinLocked){'La jonction de ce PC attend un redémarrage ou une vérification. Ouvrez Mise au domaine.'}
        else{''}
    [pscustomobject]@{Visible=[bool]$text;Text=$text}
}
function Get-PestoSiteReadLabel {
    param($Info,[string]$State='',[string]$ErrorText='')
    $age=if($Info){Get-PestoDataAgeText ([string]$Info.CollectedUtc) ([bool]$Info.Complete)}else{''}
    if($State -eq 'Loading'){return 'Services : lecture en cours'+$(if($age){' · '+$age}else{''})}
    if($State -eq 'Failed'){return 'Services : lecture indisponible'+$(if($age){' · données précédentes : '+$age}else{'. Saisie libre possible.'})}
    if($Info){return $(if($Info.Complete){'Services lus · '}else{'Services : liste partielle · '})+$age}
    return 'Services non lus · saisie libre possible'
}
function Get-PestoOperationStages {
    param($Monitor,[bool]$Busy)
    if(-not $Monitor){return}
    $previous=@();if($null -ne $Monitor.StageHistory){$previous=@($Monitor.StageHistory.ToArray()|Select-Object -Last 5)}
    foreach($entry in $previous){[pscustomobject]@{Label=([string]$entry.Name+' · '+[Math]::Round($entry.Milliseconds/1000.0,1)+' s');State='Étape passée'}}
    if($Monitor.Stage){[pscustomobject]@{Label=[string]$Monitor.Stage.Name;State=$(if($Monitor.TimedOut){'Surveillance expirée : résultat à vérifier'}elseif($Busy){'En cours'}else{'Surveillance terminée : consulter le résultat'})}}
}
function Update-PestoStatusHeader {
    $mode=$Win.FindName('PestoModeChip');if($mode){$mode.Text=Get-PestoModeChip ([bool]$script:GUI) ([bool]$script:SIM) ([bool]$script:PestoReadOnly)}
    $dc=$Win.FindName('PestoDcChip');if($dc){$dc.Text=if($script:DC){'DC : '+[string]$script:DC}else{'DC non sélectionné'}}
    $block=Get-PestoBlockState ([bool]$script:CfgRestartRequired) ([bool](Test-PestoGlobalSafetyBarrier)) ([bool]$script:JoinLocked) ([bool]$script:PestoPolicy.IncidentMode)
    $banner=$Win.FindName('PestoBlockBanner');if($banner){$banner.Text=$block.Text;$banner.Visibility=if($block.Visible){'Visible'}else{'Collapsed'}}
    $info=$null;$state='';$errorText=''
    if($script:SiteLookupKey){
        if($script:SiteLookupInfo){$info=$script:SiteLookupInfo[$script:SiteLookupKey]}
        if($script:SiteLookupState){$status=$script:SiteLookupState[$script:SiteLookupKey];$state=[string]$status.State;$errorText=[string]$status.Error}
    }
    $label=$Win.FindName('PestoServiceState');if($label){$label.Text=Get-PestoSiteReadLabel $info $state;$label.ToolTip=$errorText}
    $monitor=$null;$busy=$false
    if($script:DirectBusy){$monitor=$script:DirectMonitor;$busy=$true}
    elseif($script:JoinBusy -and $script:JoinActiveRequest){$monitor=$script:JoinActiveRequest.Monitor;$busy=$true}
    elseif($script:Running -and $script:QueueCurrentTicket){$monitor=$script:QueueCurrentTicket.Monitor;$busy=$true}
    elseif($script:PestoDisplayedMonitor){$monitor=$script:PestoDisplayedMonitor}
    if($monitor){$script:PestoDisplayedMonitor=$monitor}
    $stages=$Win.FindName('PestoOperationStages');$expander=$Win.FindName('PestoStageDetails')
    if($stages -and $expander){
        $key=if($monitor){[string]$monitor.WorkerId+'|'+[string]$monitor.Stage.Started+'|'+[string]$monitor.Stage.Name+'|'+$busy+'|'+[string]$monitor.TimedOut}else{''}
        if($script:PestoStagesKey -cne $key){$script:PestoStagesKey=$key;$stages.ItemsSource=@(Get-PestoOperationStages $monitor $busy)}
        $expander.Visibility=if($monitor){'Visible'}else{'Collapsed'}
    }
}

function Update-PestoSuiteUI {
    if(-not $script:SuiteReady){return}
    $u=$script:SuiteUI;$single=$script:SuiteMode -ne 'Batch'
    $vis=if($single){'Collapsed'}else{'Visible'}
    $QueueCard.Visibility=$vis;$u.SuiteQueueFooter.Visibility=$vis;$BtnAdd.Visibility=$vis;$UxAddHint.Visibility=$vis
    $ChkReboot.Visibility=$vis
    $u.SuiteDirectCommands.Visibility=if($single){'Visible'}else{'Collapsed'}
    $u.SuitePreparationTools.Visibility=$u.SuiteDirectCommands.Visibility
    $remoteHint=$Win.FindName('SuiteRemoteAccountHint');if($remoteHint){$remoteHint.Visibility=if(-not $script:LOCALHOST){'Visible'}else{'Collapsed'}}
    $u.SuiteModeSingle.IsEnabled=($script:INDOMAIN -and -not ($script:Running -or $script:PreflightRunning -or $script:DirectBusy))
    $u.SuiteModeBatch.IsEnabled=$u.SuiteModeSingle.IsEnabled
    $u.SuiteModeSingle.FontWeight=if($single){'SemiBold'}else{'Normal'}
    $u.SuiteModeBatch.FontWeight=if($single){'Normal'}else{'SemiBold'}
    if($script:INDOMAIN){
        $UxPageTitle.Text=if($single){'Modifier un poste'}else{'Préparer plusieurs postes'}
        $UxPageSubtitle.Text=if($single){'Lire, vérifier, confirmer. Une seule action, sans file.'}else{'La file regroupe les postes à traiter. Les résultats partiels ne sont pas rejoués automatiquement.'}
    }
    $NavRenameLabel.Text=Get-PestoUxNom 'PagePoste'
    $u.SuiteDirectRun.IsEnabled=($BtnAdd.IsEnabled -and -not $script:DirectBusy -and -not (Test-PestoDirectTargetBarrier ([string]$TxtPCName.Text)) -and $script:EDIT_ROW_INDEX -lt 0)
    if($script:DirectResumePlan -and -not($script:DirectBusy -or $script:Running -or $script:PreflightRunning -or $script:JoinBusy -or $script:JoinLocked -or (Test-PestoGlobalSafetyBarrier) -or $script:CfgRestartRequired)){$u.SuiteDirectRun.IsEnabled=$true}
    $u.SuiteDirectCheck.IsEnabled=$u.SuiteDirectRun.IsEnabled
    $u.SuitePostState.IsEnabled=(-not $script:DirectBusy -and -not $script:Running -and -not $script:JoinBusy -and (Test-PestoComputerName ([string]$TxtPCName.Text)))
    $u.SuiteDirectRun.Content=if($script:DirectResumePlan){'Vérifier puis déplacer seulement'}elseif([bool]$ChkRename.IsChecked){'Vérifier puis renommer'}else{'Vérifier puis déplacer'}
    $hint=if($script:DirectBusy){'Opération en cours. Vous pouvez consulter le journal.'}
        elseif($script:DirectResumePlan){'Reprise préparée : déplacement seul, après une nouvelle lecture AD et confirmation. Le renommage ne sera pas rejoué.'}
        elseif(Test-PestoDirectTargetBarrier ([string]$TxtPCName.Text)){"La dernière opération unitaire attend une vérification. Utilisez « $(Get-PestoUxNom 'BtnReprendre') »."}
        elseif(Test-PestoGlobalSafetyBarrier){'Une ancienne exécution doit être vérifiée avant toute nouvelle écriture.'}
        elseif($script:JoinLocked -or $script:JoinBusy){'Une jonction est en cours ou attend une vérification.'}
        elseif($script:CfgRestartRequired){'Relancez Pesto pour appliquer le nouveau domaine ou mode.'}
        elseif(-not $script:OU_ACTUELLE){'Lisez le poste pour connaître son emplacement actuel.'}
        elseif($u.SuiteDirectRun.IsEnabled){'Le contrôle relit l''identité, le nom et l''OU. L''écriture ne commence qu''après votre confirmation.'}
        else{[string]$UxAddHint.Text}
    if($single -and $hint -like '*file*' -and -not $script:MutationUncertain){$hint='Complétez le formulaire ou lisez l''état du poste avant de continuer.'}
    $primary=Get-PestoPrimaryContext
    $u.SuiteDirectRun.Content=$primary.Label;$u.SuiteDirectRun.IsEnabled=$primary.Enabled
    $u.SuiteDirectCheck.IsEnabled=($primary.Action -eq 'Execute' -or ($script:PestoReadOnly -and $BtnAdd.IsEnabled))
    if($primary.Action -ne 'Execute'){$hint=$primary.Hint}
    $u.SuiteDirectHint.Text=$hint;$u.SuiteDirectRun.ToolTip=$hint
    [Windows.Automation.AutomationProperties]::SetName($u.SuiteDirectRun,$primary.Label)
    [Windows.Automation.AutomationProperties]::SetHelpText($u.SuiteDirectRun,$hint)
    if($single){$UxNextStep.Text=$hint;$UxRebootSummary.Text='Redémarrage : aucun redémarrage automatique'}
    $u.SuiteDirectCancelRead.Visibility=if(Test-PestoAsyncOperationRunning 'DirectPreflight'){'Visible'}else{'Collapsed'}
    if($script:DirectReceipt -or $script:DirectBusy -or $script:DirectMessage){$u.SuiteDirectResult.Visibility=if($single){'Visible'}else{'Collapsed'}}else{$u.SuiteDirectResult.Visibility='Collapsed'}
    if($script:DirectBusy -and $script:DirectMonitor){
        $u.SuiteDirectStage.Text=Get-PestoQueueActivityText $script:DirectMonitor
    }elseif($script:DirectMessage){$u.SuiteDirectStage.Text=[string]$script:DirectMessage}
    $u.SuiteDirectAdvice.Text=[string]$script:DirectAdvice
    $u.SuiteDirectVerify.IsEnabled=(-not $script:DirectBusy -and -not $script:Running -and -not $script:JoinBusy -and $null -ne $script:DirectReceipt)
    $optionalReview=(-not $script:DirectLocked -and (Test-PestoOptionalPostCheckReceipt -Receipt $script:DirectReceipt))
    $u.SuiteDirectVerify.Content=if($optionalReview){'Vérifier l''état (facultatif)'}else{'Vérifier puis reprendre'}
    $u.SuiteDirectVerify.ToolTip=if($optionalReview){'Relire le résultat enregistré si vous le souhaitez. La vérification ne conditionne pas une nouvelle préparation ; le redémarrage Windows reste nécessaire lorsqu''il est en attente.'}else{'Relire l''état réel sans modifier le poste. Une reprise de déplacement n''est proposée que lorsque le renommage est confirmé.'}
    [Windows.Automation.AutomationProperties]::SetName($u.SuiteDirectVerify,[string]$u.SuiteDirectVerify.Content)
    [Windows.Automation.AutomationProperties]::SetHelpText($u.SuiteDirectVerify,[string]$u.SuiteDirectVerify.ToolTip)
    $u.SuiteDirectDetails.IsEnabled=($null -ne $script:DirectReceipt)
    $nextButton=$Win.FindName('PestoNextOperation');if($nextButton){$nextButton.IsEnabled=(-not($script:DirectBusy -or $script:Running -or $script:JoinBusy -or $script:PreflightRunning))}
    $announcement=([string]$script:DirectReceipt.OperationId+'|'+[string]$script:DirectReceipt.Phase)
    if($script:DirectReceipt -and $script:PestoLastDirectAnnouncement -cne $announcement){$script:PestoLastDirectAnnouncement=$announcement;Set-PestoAccessibleStatus ([string]$u.SuiteDirectStage.Text)}
    $age=Get-PestoDataAgeText $script:InventoryUtc
    if($script:SiteLookupInfo -and $script:SiteLookupKey -and $script:SiteLookupInfo.ContainsKey($script:SiteLookupKey)){$info=$script:SiteLookupInfo[$script:SiteLookupKey];$age=Get-PestoDataAgeText $info.CollectedUtc $info.Complete}
    $badge=$Win.FindName('SuiteDataAge');if($badge){$badge.Text=$age}
    $pin=$Win.FindName('SuiteTargetPin');if($pin){$pin.Text=([string]$TxtPCName.Text+' · '+$(if($script:LOCALHOST){'Ce PC'}else{'Poste distant'})+' · '+$script:DOMAINE+' · '+$script:AuthUser);$pin.ToolTip='Cible du formulaire et compte utilisé. Aucune lecture réseau déclenchée par ce bandeau.'}
    Update-PestoStatusHeader
    Update-PestoSuiteHelp
    Sync-PestoUxNavigation
    if($script:PestoReadOnly){
        $u.SuiteDirectRun.IsEnabled=($primary.Action -eq 'Read' -and $primary.Enabled);$BtnRun.IsEnabled=$false
        $u.SuiteDirectHint.Text='Consultation : lectures autorisées selon vos droits, toutes les mutations sont interdites dans le moteur.'
        $UxExecutionMode.Text='CONSULTATION · aucune mutation';$ChkReboot.IsEnabled=$false
    }
}

function Invoke-PestoLogOption {
    param($Sender,$EventArgs)
    if(-not $script:SuiteReady -or $script:SuiteInitializing){return}
    $script:LogFollow=[bool]$script:SuiteUI.SuiteLogFollow.IsChecked
    $script:LogWrap=[bool]$script:SuiteUI.SuiteLogWrap.IsChecked
    Render-Log;Save-Prefs
}
function Invoke-PestoLogSearch {
    param($Sender,$EventArgs)
    $script:LogFilter=[string]$Sender.Text
    $script:LogForceRefresh=$true
}
function Invoke-PestoSuitePulse {
    param($Sender,$EventArgs)
    if(-not $script:SuiteReady){return}
    if($script:DirectBusy){
        if($script:DirectMonitor -and $script:DirectMonitor.TimedOut -and -not(Test-PestoAsyncOperationRunning 'DirectAction')){
            $script:DirectLocked=$true;Set-PestoDirectBusy $false
            $script:DirectAdvice='Le worker a terminé après la limite de supervision. Relisez l''état réel ; le retour tardif n''a pas levé le verrou.'
        }
        Update-PestoSuiteUI
    }
    if(-not $script:DirectBusy){Update-PestoStatusHeader}
    if($script:PestoLogDirty -or $script:LogForceRefresh){
        if($MainTabs.SelectedIndex -eq 3 -and ($script:LogFollow -or $script:LogForceRefresh)){Render-Log}
        elseif($script:SuiteUI.SuiteLogCount){$script:SuiteUI.SuiteLogCount.Text='Lecture en pause. Les nouveaux événements sont conservés ; Actualiser ou cocher Suivre pour les afficher.'}
    }
}

function Initialize-PestoSuiteUI {
    if($script:SuiteReady){return}
    Initialize-PestoUiZoom
    $names=@('NavBatch','SuiteRoot','SuiteSidebarGrid','SuiteBrand','SuiteBrandLabel','SuiteBrandHint','SuiteNavFooter','SuiteNavToggle','SuiteNavToggleGlyph',
        'SuiteHelpWidth','SuiteHelpPanel','SuiteHelpClose','SuiteHelpTitle','SuiteHelpText','SuiteHelpAccount','SuiteHelpGuide','SuiteHelpDiagnostic',
        'SuiteModeSingle','SuiteModeBatch','SuitePostState','SuiteDirectCommands','SuiteDirectRun','SuiteDirectCheck','SuiteDirectHint',
        'SuiteDirectResult','SuiteDirectTitle','SuiteDirectStage','SuiteDirectAdvice','SuiteDirectVerify','SuiteDirectDetails','SuiteDirectCancelRead','SuiteQueueFooter',
        'SuitePreparationTools','SuiteAppearanceDensity','SuiteAppearanceSaveColumns','SuiteAppearanceResetColumns','SuiteAppearanceNav','SuiteAppearanceHelp','SuiteLogSearch','SuiteLogFollow','SuiteLogWrap','SuiteLogMinus','SuiteLogPlus','SuiteLogDiagnostic','SuiteLogCount','SuiteLogRefresh','SuiteLogLevel','SuiteLogErrors')
    $script:SuiteUI=@{}
    foreach($n in $names){$c=$Win.FindName($n);if(-not $c){throw "Interface incomplète : $n."};$script:SuiteUI[$n]=$c}
    foreach($n in $names){$c=$script:SuiteUI[$n];if($c -is [Windows.Controls.Button]){$c.Add_Click([Windows.RoutedEventHandler]${function:Invoke-PestoSuiteCommand})}}
    $script:SuiteUI.SuiteLogLevel.Add_SelectionChanged([Windows.Controls.SelectionChangedEventHandler]${function:Invoke-PestoLogLevel})
    $script:SuiteUI.SuiteLogSearch.Add_TextChanged([Windows.Controls.TextChangedEventHandler]${function:Invoke-PestoLogSearch})
    foreach($n in @('SuiteLogFollow','SuiteLogWrap')){
        $script:SuiteUI[$n].Add_Checked([Windows.RoutedEventHandler]${function:Invoke-PestoLogOption})
        $script:SuiteUI[$n].Add_Unchecked([Windows.RoutedEventHandler]${function:Invoke-PestoLogOption})
    }
    $script:SuiteInitializing=$true
    $script:SuiteUI.SuiteLogWrap.IsChecked=[bool]$script:LogWrap
    $script:SuiteUI.SuiteLogFollow.IsChecked=$true
    $script:SuiteInitializing=$false
    $script:SuiteMode='Single';$script:SuiteReady=$true
    $script:SuiteTimer=[Windows.Threading.DispatcherTimer]::new()
    $script:SuiteTimer.Interval=[TimeSpan]::FromMilliseconds(250)
    $script:SuiteTimer.Add_Tick([EventHandler]${function:Invoke-PestoSuitePulse});$script:SuiteTimer.Start()
    Update-PestoSuiteLayout;Update-PestoSuiteUI
}

function Get-PestoHomeReceiptSummary {
    param($Catalogue=$null,[bool]$Demo=$false,[bool]$Simulation=$false,[string]$ReceiptsError='')
    $demoMode=$Demo -or $Simulation
    $rows=@();$issues=[Collections.Generic.List[string]]::new()
    if(-not $demoMode -and -not $ReceiptsError -and $Catalogue){$rows=@(foreach($entry in $Catalogue.Entries){ConvertTo-PestoInterventionRow $entry});if($Catalogue.Truncated){$issues.Add('Registre local partiel : seuls les 5 000 premiers fichiers ont été lus. Les résultats affichés ne sont pas exhaustifs.')}}
    if($ReceiptsError){$issues.Add($ReceiptsError)}
    $attention=@($rows | Where-Object {$_.Unresolved -and -not $_.OptionalPostCheck})
    $attentionText=if($attention.Count){([string]$attention.Count+' intervention(s) demandent une vérification selon les reçus locaux.')+"`n"+(@($attention | Sort-Object UpdatedUtc -Descending | Select-Object -First 2 | ForEach-Object {$_.Computer+' · '+$_.StatusLabel+' · '+$_.NextAction}) -join "`n")}else{''}
    $recent=@(foreach($row in @($rows | Where-Object {$_.Readable} | Sort-Object UpdatedUtc -Descending | Select-Object -First 3)){
        $target=[string]$row.Computer;if($row.NewName -and $row.NewName -ine $row.Computer){$target+=' → '+$row.NewName}
        $resultLine=$row.StatusLabel+' · '+$row.UpdatedLocal
        [pscustomobject]@{RowId=$row.RowId;Target=$target;ResultLine=$resultLine;NextAction=$row.NextAction;AccessibleText=$target+' · '+$resultLine;UpdatedUtc=$row.UpdatedUtc}
    })
    $empty=if($demoMode){'Les reçus réels ne sont pas chargés dans ce mode.'}elseif($ReceiptsError){'Reçus indisponibles. Actualisez pour réessayer.'}elseif($null -eq $Catalogue){'Reçus locaux non lus.'}elseif($Catalogue.InvalidCount -gt 0 -and -not $recent.Count){'Aucun reçu lisible. Ouvrez les interventions pour examiner les fichiers.'}else{'Aucune intervention enregistrée localement.'}
    [pscustomobject]@{ReceiptsKnown=(-not $demoMode -and -not $ReceiptsError -and $null -ne $Catalogue);AttentionCount=$(if(-not $demoMode -and -not $ReceiptsError -and $null -ne $Catalogue){$attention.Count}else{$null});AttentionText=$attentionText;ReadIssue=($issues -join "`n");Recent=$recent;EmptyRecent=$empty}
}

function Get-PestoHomeDashboard {
    param($Local=$null,$Catalogue=$null,[bool]$InDomain=$false,[bool]$Demo=$false,[bool]$Simulation=$false,[bool]$ReadOnly=$false,[bool]$Busy=$false,[string]$Activity='',[string]$OU='',[string]$OUStamp='',[string]$LocalError='',[string]$ReceiptsError='',$ReceiptSummary=$null)
    $demoMode=$Demo -or $Simulation
    $known=(-not $demoMode -and -not $LocalError -and $Local -and $Local.PartOfDomain -is [bool] -and -not [string]::IsNullOrWhiteSpace([string]$Local.Computer) -and -not [string]::IsNullOrWhiteSpace([string]$Local.Domain))
    $computer=if($known){[string]$Local.Computer}else{'Nom Windows non lu'}
    $domain=if($known){$(if($Local.PartOfDomain){'Domaine Windows : '}else{'Groupe de travail : '})+[string]$Local.Domain}else{'Domaine Windows non lu'}
    $read='Informations locales non lues.'
    if($known){$date=[DateTimeOffset]::MinValue;if([DateTimeOffset]::TryParse([string]$Local.CollectedUtc,[ref]$date)){$read='Lecture Windows : '+$date.ToLocalTime().ToString('dd/MM/yyyy HH:mm:ss')}else{$read='Lecture Windows : date inconnue.'}}
    $location='Emplacement AD non observé.'
    if($known -and $OU){
        $stamp=[DateTimeOffset]::MinValue;$dateText=if([DateTimeOffset]::TryParse($OUStamp,[ref]$stamp)){$stamp.ToLocalTime().ToString('dd/MM/yyyy HH:mm:ss')}else{'date inconnue'}
        $location='Emplacement déjà observé : '+$OU+"`n"+'Lecture AD : '+$dateText+'. Cet écran ne l''actualise pas.'
    }elseif($known -and -not $Local.PartOfDomain){$location='Ce PC est dans un groupe de travail. Aucun emplacement AD local observé.'}
    $summary=if($ReceiptSummary){$ReceiptSummary}else{Get-PestoHomeReceiptSummary -Catalogue $Catalogue -Demo $Demo -Simulation $Simulation -ReceiptsError $ReceiptsError}
    $issue=@($LocalError,$summary.ReadIssue | Where-Object {$_}) -join "`n"
    if($demoMode){$read='Informations Windows réelles non lues dans ce mode.';$location='';$Activity=''}
    elseif($known -and $Local.PendingRename -is [bool] -and $Local.PendingRename -eq $true -and -not [string]::IsNullOrWhiteSpace([string]$Local.ConfiguredName) -and $Local.ConfiguredName -ine $Local.Computer){$Activity+=($(if($Activity){"`n"}else{''})+'Nom Windows configuré : '+[string]$Local.ConfiguredName+'. Un redémarrage reste nécessaire pour activer ce nom.')}
    [pscustomobject]@{LocalKnown=[bool]$known;Computer=$computer;Domain=$domain;LocalRead=$read;Location=$location;Activity=$Activity;ReceiptsKnown=$summary.ReceiptsKnown;AttentionCount=$summary.AttentionCount;AttentionText=$summary.AttentionText;ReadIssue=$issue;Recent=$summary.Recent;EmptyRecent=$summary.EmptyRecent;
        Mode=$(if($Demo){'Démonstration · aucune opération réelle'}elseif($Simulation){'Simulation · aucune mutation réelle'}elseif($ReadOnly){'Consultation · lectures uniquement'}else{'Session d''intervention · confirmation avant exécution'});CanPrepare=($InDomain -and -not $Busy)}
}

function Update-PestoHomeDashboard {
    if(-not $Win){return}
    $computer=if($script:HomeLocalSnapshot){[string]$script:HomeLocalSnapshot.Computer}else{[string]$env:COMPUTERNAME}
    $probe=if($computer){Get-PestoCachedComputerProbe -Name $computer -Local $true}else{$null}
    $ou=if($probe){Format-OUPath $probe.OU}else{''}
    $activity=if($script:DirectBusy){'Intervention unitaire en cours. Consultez le journal pour sa progression.'}elseif($script:JoinBusy){'Ajout au domaine en cours. Consultez la page Ajouter au domaine.'}elseif($script:Running){'Traitement de la file en cours. Consultez Plusieurs postes.'}elseif($script:PreflightRunning){'Contrôle de la file en cours. Aucune exécution lancée par ce contrôle.'}elseif($script:CfgRestartRequired){'La configuration a changé. Relancez Pesto pour appliquer le nouveau contexte.'}else{''}
    $busy=$script:DirectBusy -or $script:JoinBusy -or $script:Running -or $script:PreflightRunning
    # Catalogues are immutable worker results. Rebuild the local presentation
    # only on a new result/error/mode, never for every form field or UI pulse.
    $receiptContext=([string][bool]$script:GUI)+'|'+([string][bool]$script:SIM)+'|'+[string]$script:HomeReceiptsError
    if(-not $script:HomeReceiptSummary -or -not [object]::ReferenceEquals($script:HomeReceiptSummaryCatalogue,$script:HomeReceiptCatalogue) -or $script:HomeReceiptSummaryContext -cne $receiptContext){
        $script:HomeReceiptSummary=Get-PestoHomeReceiptSummary -Catalogue $script:HomeReceiptCatalogue -Demo ([bool]$script:GUI) -Simulation ([bool]$script:SIM) -ReceiptsError ([string]$script:HomeReceiptsError)
        $script:HomeReceiptSummaryCatalogue=$script:HomeReceiptCatalogue;$script:HomeReceiptSummaryContext=$receiptContext
    }
    $model=Get-PestoHomeDashboard -Local $script:HomeLocalSnapshot -Catalogue $script:HomeReceiptCatalogue -InDomain ([bool]$script:INDOMAIN) -Demo ([bool]$script:GUI) -Simulation ([bool]$script:SIM) -ReadOnly ([bool]$script:PestoReadOnly) -Busy $busy -Activity $activity -OU $ou -OUStamp '' -LocalError ([string]$script:HomeLocalError) -ReceiptsError ([string]$script:HomeReceiptsError) -ReceiptSummary $script:HomeReceiptSummary
    foreach($pair in @(@('UxHomeContext',$model.Mode),@('HomeLocalComputer',$model.Computer),@('HomeLocalDomain',$model.Domain),@('HomeLocalRead',$model.LocalRead),@('HomeLocalLocation',$model.Location),@('HomeActivityText',$model.Activity),@('HomeInterventionSummary',$model.AttentionText),@('HomeReadIssue',$model.ReadIssue),@('HomeRecentEmpty',$model.EmptyRecent))){$control=$Win.FindName($pair[0]);if($control){$control.Text=[string]$pair[1]}}
    foreach($pair in @(@('HomeActivityCard',[bool]$model.Activity),@('HomeAttentionCard',($model.AttentionCount -gt 0)),@('HomeReadIssue',[bool]$model.ReadIssue),@('HomeRecentList',($model.Recent.Count -gt 0)),@('HomeRecentEmpty',($model.Recent.Count -eq 0)))){$control=$Win.FindName($pair[0]);if($control){$control.Visibility=if($pair[1]){'Visible'}else{'Collapsed'}}}
    $list=$Win.FindName('HomeRecentList')
    if($list -and -not [object]::ReferenceEquals($list.ItemsSource,$model.Recent)){
        $selectedId=if($list.SelectedItem){[string]$list.SelectedItem.RowId}else{''}
        $list.ItemsSource=$model.Recent
        if($selectedId){$list.SelectedItem=@($model.Recent | Where-Object {$_.RowId -eq $selectedId} | Select-Object -First 1)[0]}
        if(-not $list.SelectedItem -and $list.Items.Count){$list.SelectedIndex=0}
        $button=$Win.FindName('HomeOpenReceipt');if($button){$button.IsEnabled=($null -ne $list.SelectedItem)}
    }
    $button=$Win.FindName('HomePrepare');if($button){$button.IsEnabled=$model.CanPrepare}
    $button=$Win.FindName('HomeQueue');if($button){$button.IsEnabled=$model.CanPrepare}
    $button=$Win.FindName('HomeRefresh');if($button){$button.IsEnabled=(-not $script:GUI -and -not $script:SIM -and -not(Test-PestoAsyncOperationRunning 'HomeReceipts'))}
}

function Invoke-PestoHomeCommand {
    param($Sender,$EventArgs)
    switch($Sender.Name){
        'HomeJoin' {Set-PestoUxPage 'Join';return}
        'HomeRefresh' {$script:HomeReceiptsTick=0;$script:HomeLocalSnapshot=$null;Update-PestoHomeInterventions;return}
        'HomeOpenReceipt' {
            $row=$Win.FindName('HomeRecentList').SelectedItem;if(-not $row){return}
            try{
                $id=[Guid]::Empty;if(-not [Guid]::TryParse([string]$row.RowId,[ref]$id) -or $id -eq [Guid]::Empty){throw 'Identifiant de reçu invalide.'}
                $receipt=Read-PestoIntervention -Path (Join-Path (Get-PestoInterventionRoot) ($id.ToString('N')+'.json'))
                if([Guid]$receipt.OperationId -ne $id){throw 'Le reçu ne correspond plus à cette ligne.'}
                Show-PestoTextReport 'Reçu d''intervention local' ((Get-PestoOperationReport -Receipt $receipt -Redact:$false)+"`r`nIdentifiant : "+$receipt.OperationId)
            }catch{Show-MsgError ('Impossible de relire le reçu. Actualisez les informations locales. '+$_.Exception.Message)}
            return
        }
    }
}


function Request-PestoPageAutomationRefresh {
    # Hidden tab headers retain a native UIA child cache. Refresh only when a
    # client has already created this peer, after the selected page is laid out.
    if(-not $Win -or -not $MainTabs -or $script:PestoPageAutomationPending){return}
    if(-not [Windows.Automation.Peers.UIElementAutomationPeer]::FromElement($MainTabs)){return}
    if($Win.Dispatcher.HasShutdownStarted -or $Win.Dispatcher.HasShutdownFinished){return}
    $script:PestoPageAutomationPending=$true
    try{
        [void]$Win.Dispatcher.BeginInvoke([Action]{Update-PestoPageAutomationPeers},[Windows.Threading.DispatcherPriority]::Loaded)
    }catch{$script:PestoPageAutomationPending=$false;Write-Log 'Actualisation de l''accessibilité non planifiée.' 'WARN' $_ 'interface'}
}

function Update-PestoPageAutomationPeers {
    $script:PestoPageAutomationPending=$false
    if(-not $Win -or -not $MainTabs -or $Win.Dispatcher.HasShutdownStarted -or $Win.Dispatcher.HasShutdownFinished){return}
    $peer=[Windows.Automation.Peers.UIElementAutomationPeer]::FromElement($MainTabs)
    if(-not $peer){return}
    try{
        $MainTabs.UpdateLayout()
        foreach($child in @($peer.GetChildren())){if($child){$child.ResetChildrenCache();$child.InvalidatePeer()}}
        $peer.ResetChildrenCache();$peer.InvalidatePeer()
        $windowPeer=[Windows.Automation.Peers.UIElementAutomationPeer]::FromElement($Win)
        if($windowPeer){$windowPeer.ResetChildrenCache();$windowPeer.InvalidatePeer()}
    }catch{Write-Log 'Arbre d''accessibilité non actualisé après navigation.' 'WARN' $_ 'interface'}
}
