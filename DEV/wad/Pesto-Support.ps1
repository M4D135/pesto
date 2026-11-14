#requires -Version 5.1
# Messages utiles et diagnostic à liste blanche. Aucun contexte de credential sérialisé.

function Get-PestoErrorExplanation {
    param([string]$Message,[string]$Stage,[bool]$MutationPossible=$true)
    $title='Cette étape n''a pas abouti.'
    $next='Consultez les détails et le journal, puis corrigez la cause avant un nouvel essai.'
    switch -Regex ($Message){
        '(?i)(access.*denied|acc.s.*refus|0x80070005|\b1326\b|identifiant|authentif)' {
            $title='Le compte ou les droits sont refusés.'
            $next='Vérifiez le compte affiché et ses droits sur la cible. L''élévation locale ne donne pas automatiquement les droits AD.';break
        }
        '(?i)(RPC|0x800706ba|\b1722\b|injoignable|ne r.pond)' {
            $title='Le poste ne répond pas au transport demandé.'
            $next='Vérifiez la connexion du poste, le pare-feu et le transport RPC/DCOM. Pesto ne démarre pas WinRM pour contourner cette erreur.';break
        }
        '(?i)(DNS|\b1355\b|contr.leur.*introuvable|domaine.*introuvable)' {
            $title='Le domaine ou son contrôleur n''est pas accessible.'
            $next='Vérifiez le réseau d''entreprise/VPN, le DNS et le domaine configuré. N''utilisez pas un autre domaine au hasard.';break
        }
        '(?i)(d.lai|timeout|timed?\s*out|ind.termin|incertain)' {
            $title='Le résultat n''est pas suffisamment confirmé.'
            $next='Ouvrez État du poste. Une limite de supervision ne prouve pas que Windows a annulé sa commande.';break
        }
        '(?i)(nom.*(pris|occup.|exist)|compte.*existe)' {
            $title='Le nom ou l''objet existe déjà.'
            $next='Vérifiez l''objet AD et choisissez un autre nom si nécessaire. Pesto ne supprime pas un compte existant pour libérer le nom.';break
        }
        '(?i)(config|cfg\.json|p.rim.tre|OU.*invalide)' {
            $title='Les paramètres ou l''emplacement doivent être corrigés.'
            $next='Vérifiez le domaine et le chemin exact de l''OU dans Paramètres. Les plans existants sont conservés et doivent être contrôlés à nouveau.';break
        }
        '(?i)(Azure AD|Entra|dsregcmd)' {
            $title='La préparation ou le retour Entra nécessite une vérification.'
            $next='Examinez l''état dsregcmd et le journal sur la cible. Ne confondez pas retrait Entra, renommage Windows et réinscription.';break
        }
    }
    $effect=if($MutationPossible){'Aucune relance automatique. Vérifiez le résultat connu avant d''engager une nouvelle écriture.'}else{'Aucune commande de modification n''a été lancée par cette étape.'}
    
    [pscustomobject]@{Title=$title;NextStep=$next;Effect=$effect;Stage=(Protect-PestoLogText $Stage);Detail=(Protect-PestoLogText $Message)}
}

function Show-PestoUsefulError {
    param([string]$Title='Pesto · Erreur',[string]$Message,[string]$Stage='Application',[bool]$MutationPossible=$true)
    $info=Get-PestoErrorExplanation -Message $Message -Stage $Stage -MutationPossible $MutationPossible
    if(-not $Win){[void][Windows.MessageBox]::Show(($info.Title+"`n`n"+$info.NextStep+"`n`n"+$info.Detail),$Title,'OK','Error');return}
    if($Win.IsVisible -and $Win.IsActive -and (Get-Command Show-PestoPanel -ErrorAction SilentlyContinue)){[void](Show-PestoPanel -Title $Title -Body ($info.Title+"`n`n"+$info.Effect+"`n"+$info.NextStep+"`n`nDétails :`n"+$info.Detail));return}
    [xml]$x=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Width="590" SizeToContent="Height" ResizeMode="NoResize" WindowStartupLocation="CenterOwner" Background="{DynamicResource BgWindow}" Foreground="{DynamicResource FgText}" FontFamily="Segoe UI" FontSize="13" UseLayoutRounding="True">
<ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel Margin="22">
<TextBlock x:Name="ErrorTitle" FontSize="20" FontWeight="SemiBold" TextWrapping="Wrap"/>
<TextBlock x:Name="ErrorStage" Foreground="{DynamicResource FgMuted}" Margin="0,8,0,0" TextWrapping="Wrap"/>
<TextBlock x:Name="ErrorEffect" Margin="0,14,0,0" TextWrapping="Wrap"/>
<TextBlock x:Name="ErrorNext" Margin="0,12,0,14" TextWrapping="Wrap"/>
<Expander Header="Détails techniques" ToolTip="Afficher le message précis sans relancer l’opération."><TextBox x:Name="ErrorDetail" IsReadOnly="True" TextWrapping="Wrap" AcceptsReturn="True" MaxHeight="230" VerticalScrollBarVisibility="Auto" Margin="0,8,0,0" ToolTip="Détail technique filtré. Sélectionnez et copiez uniquement ce qui est utile." ToolTipService.ShowOnDisabled="True" ToolTipService.InitialShowDelay="450" ToolTipService.ShowDuration="30000" AutomationProperties.HelpText="Détail technique filtré. Sélectionnez et copiez uniquement ce qui est utile." AutomationProperties.Name="Détails techniques"/></Expander>
<Button x:Name="ErrorClose" Content="Fermer" IsDefault="True" IsCancel="True" HorizontalAlignment="Right" MinWidth="100" Margin="0,18,0,0" ToolTip="Fermer le message. Aucune action n’est relancée." ToolTipService.ShowOnDisabled="True" ToolTipService.InitialShowDelay="450" ToolTipService.ShowDuration="30000" AutomationProperties.HelpText="Fermer le message. Aucune action n’est relancée."/>
</StackPanel></ScrollViewer></Window>
'@
    $w=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($x));$w.Title=$Title;$w.Resources=$Win.Resources
    if($Win.IsVisible){$w.Owner=$Win}
    $w.MaxHeight=[Windows.SystemParameters]::WorkArea.Height-24;$w.MaxWidth=[Windows.SystemParameters]::WorkArea.Width-24
    $w.FindName('ErrorTitle').Text=$info.Title;$w.FindName('ErrorStage').Text='Étape : '+$info.Stage
    $w.FindName('ErrorEffect').Text=$info.Effect;$w.FindName('ErrorNext').Text=$info.NextStep;$w.FindName('ErrorDetail').Text=$info.Detail
    $w.FindName('ErrorClose').Add_Click({param($s,$e);[Windows.Window]::GetWindow($s).Close()})
    Set-WindowIcon $w;[void]$w.ShowDialog()
}

function Get-PestoDiagnosticEventClass {
    param([string]$Text)
    switch -Regex ($Text){
        '(?i)(uncertain|incertain|ind.termin|timeout|d.lai)' {return 'Résultat à vérifier'}
        '(?i)(erreur|échou|echou|ERROR|ERR\s)' {return 'Erreur'}
        '(?i)(rename|renomm)' {return 'Renommage'}
        '(?i)(join|jonction|ajout.*domaine)' {return 'Jonction'}
        '(?i)(déplac|deplac|move)' {return 'Déplacement'}
        '(?i)(config|paramètre|parametre)' {return 'Configuration'}
        '(?i)(connect|login|auth)' {return 'Connexion'}
        '(?i)(theme|thème|appearance)' {return 'Apparence'}
        '(?i)(perf|performance)' {return 'Performance'}
        '(?i)(contr.le|preflight)' {return 'Contrôle'}
        default {return 'Événement applicatif'}
    }
}

function Get-PestoComponentDiagnostics {
    param([string]$Root)
    $expected=@{};$manifestValid=$false;$required=@(Get-PestoRuntimeFiles)
    try{
        $manifestPath=Join-Path (Join-Path $Root 'wad') 'package.json'
        $item=Get-Item -LiteralPath $manifestPath -Force -ErrorAction Stop
        if($item.Length -gt 262144 -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Invalid manifest.'}
        $manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop
        if($manifest.Schema -ne 2 -or $manifest.Scope -cne 'Runtime' -or $manifest.Version -cne '1.0' -or @($manifest.Files).Count -ne $required.Count){throw 'Invalid manifest.'}
        foreach($entry in @($manifest.Files)){
            if([string]$entry.Path -cnotin $required -or $expected.ContainsKey([string]$entry.Path) -or [string]$entry.SHA256 -notmatch '^[a-fA-F0-9]{64}$'){throw 'Invalid manifest entry.'}
            $expected[[string]$entry.Path]=[string]$entry.SHA256
        }
        $manifestValid=$true
    }catch{$expected=@{}}
    foreach($name in $required){
        $present=$false;$hash='';$status='Absent';$errorType=''
        try{
            $path=Join-Path $Root $name
            if(Test-Path -LiteralPath $path -PathType Leaf){
                $present=$true;$item=Get-Item -LiteralPath $path -Force -ErrorAction Stop
                if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Linked component.'}
                $hash=(Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash
                $status=if(-not $manifestValid){'Manifeste illisible'}elseif(-not $expected.ContainsKey($name)){'Absent du manifeste'}elseif($hash -ine $expected[$name]){'Empreinte différente'}else{'Cohérent'}
            }
        }catch{$status='Lecture impossible';$errorType=$_.Exception.GetType().Name}
        # Relative component names only: no exception text or private filesystem path.
        [pscustomobject]@{Component=$name;Present=$present;SHA256=$hash;Status=$status;ErrorType=$errorType}
    }
}

function Get-PestoDiagnosticText {
    param([bool]$Redact=$true)
    $identity=if($Redact){'[COMPTE MASQUÉ]'}else{[string]$script:AuthUser}
    $computer=if($Redact){'[POSTE MASQUÉ]'}else{[string]$env:COMPUTERNAME}
    $domain=if($Redact){'[DOMAINE MASQUÉ]'}else{[string]$script:DOMAINE}
    $dc=if($Redact){'[DC MASQUÉ]'}else{[string]$script:DC}
    $cfgPath=if($Redact){'[CHEMIN MASQUÉ]'}else{[string]$script:JsonFile}
    $versionFiles=@()
    if($script:BasePath -or $BasePath){
        $versionFiles=@(Get-PestoComponentDiagnostics -Root (Split-Path -Parent $BasePath))
    }
    # Ne collecte PAS les textes libres, commandes, dumps de requête ou exceptions
    # sérialisées. Les traces ne fournissent ici qu'une classe et une gravité.
    $events=@(foreach($e in @($script:LogEntries|Select-Object -Last 80)){
        [pscustomobject]@{Time=[string]$e.Time;Severity=[string]$e.Kind;Category=(Get-PestoDiagnosticEventClass ([string]$e.Text))}
    })
    $direct=if($script:DirectReceipt){[pscustomobject]@{Phase=[string]$script:DirectReceipt.Phase;ResultCode=[int]$script:DirectReceipt.ResultCode;StartedUtc=[string]$script:DirectReceipt.StartedUtc;FinishedUtc=[string]$script:DirectReceipt.FinishedUtc}}else{$null}
    $payload=[ordered]@{
        Schema=1;Application='Pesto';Version=[string]$script:Pesto_VERSION;CollectedUtc=[DateTime]::UtcNow.ToString('o');IdentitiesMasked=$Redact
        Notice='Aucun texte brut du journal, commande, mot de passe, PSCredential ou configuration complète collecté. Relire avant partage.'
        Environment=[ordered]@{PowerShell=[string]$PSVersionTable.PSVersion;Edition=[string]$PSVersionTable.PSEdition;OS=[string][Environment]::OSVersion.Version;Process64Bit=[Environment]::Is64BitProcess;Admin=(Test-PestoIsAdministrator)}
        Session=[ordered]@{Computer=$computer;Account=$identity;AuthMode=[string]$script:AuthMode;Domain=$domain;DC=$dc;InDomain=[bool]$script:INDOMAIN;Demo=[bool]$script:GUI;Simulation=[bool]$script:SIM}
        Presentation=[ordered]@{ThemeMode=[string]$script:ThemeMode;EffectiveTheme=[string]$script:CurrentTheme;Saved=$script:ThemeSaved;NavigationCollapsed=[bool]$script:NavigationCollapsed;HelpVisible=[bool]$script:HelpVisible}
        Configuration=[ordered]@{Path=$cfgPath;SiteGroups=@($script:OUV.Keys).Count;InventoryLoaded=[bool]$script:InventoryLoaded;InventoryUtc=[string]$script:InventoryUtc;RestartRequired=[bool]$script:CfgRestartRequired}
        Operations=[ordered]@{QueueRows=$(if($script:table){$script:table.Rows.Count}else{0});QueueRunning=[bool]$script:Running;QueueLocked=[bool]$script:MutationUncertain;DirectBusy=[bool]$script:DirectBusy;DirectLocked=[bool]$script:DirectLocked;JoinBusy=[bool]$script:JoinBusy;JoinLocked=[bool]$script:JoinLocked;Direct=$direct}
        Components=$versionFiles;RecentEventCategories=$events
    }
    return ($payload|ConvertTo-Json -Depth 8)
}

function Export-Diagnostics {
    if($script:PestoDiagnosticUi){[void]$script:PestoDiagnosticUi.Window.Activate();return}
    [xml]$x=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Pesto · Préparer un diagnostic" Width="820" Height="640" MinWidth="550" MinHeight="400" WindowStartupLocation="CenterOwner" Background="{DynamicResource BgWindow}" Foreground="{DynamicResource FgText}" FontFamily="Segoe UI" FontSize="13">
<Grid Margin="20"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
<TextBlock Text="Relire avant d’exporter" FontSize="22" FontWeight="SemiBold"/>
<StackPanel Grid.Row="1" Margin="0,12,0,12"><TextBlock Text="Liste blanche : état de l’application et des composants, sans journal brut ni contexte d’identification. Aucune lecture AD supplémentaire." TextWrapping="Wrap" Foreground="{DynamicResource FgMuted}"/><CheckBox x:Name="DiagMask" Content="Masquer les comptes, postes, domaine et chemins internes" IsChecked="True" Margin="0,10,0,0" ToolTip="Masquage activé par défaut. Le contenu exact à enregistrer est visible ci-dessous." ToolTipService.ShowOnDisabled="True" ToolTipService.InitialShowDelay="450" ToolTipService.ShowDuration="30000" AutomationProperties.HelpText="Masquage activé par défaut. Le contenu exact à enregistrer est visible ci-dessous."/></StackPanel>
<TextBox x:Name="DiagText" Grid.Row="2" IsReadOnly="True" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" FontFamily="Consolas" FontSize="12" ToolTip="Prévisualisation exacte du rapport. Aucun envoi automatique ; l’export crée seulement le fichier choisi." ToolTipService.ShowOnDisabled="True" ToolTipService.InitialShowDelay="450" ToolTipService.ShowDuration="30000" AutomationProperties.HelpText="Prévisualisation exacte du rapport. Aucun envoi automatique ; l’export crée seulement le fichier choisi." AutomationProperties.Name="Prévisualisation du diagnostic"/>
<WrapPanel Grid.Row="3" HorizontalAlignment="Right" Margin="0,14,0,0"><Button x:Name="DiagClose" Content="Annuler" IsCancel="True" ToolTip="Fermer sans exporter." ToolTipService.ShowOnDisabled="True" ToolTipService.InitialShowDelay="450" ToolTipService.ShowDuration="30000" AutomationProperties.HelpText="Fermer sans exporter."/><Button x:Name="DiagSave" Content="Enregistrer le rapport…" Margin="8,0,0,0" ToolTip="Choisir un fichier et enregistrer uniquement le texte prévisualisé." ToolTipService.ShowOnDisabled="True" ToolTipService.InitialShowDelay="450" ToolTipService.ShowDuration="30000" AutomationProperties.HelpText="Choisir un fichier et enregistrer uniquement le texte prévisualisé."/></WrapPanel>
</Grid></Window>
'@
    try{
        $w=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($x));$w.Resources=$Win.Resources;$w.Owner=$Win;Set-WindowIcon $w
        $w.MaxWidth=[Windows.SystemParameters]::WorkArea.Width-20;$w.MaxHeight=[Windows.SystemParameters]::WorkArea.Height-20
        $script:PestoDiagnosticUi=[pscustomobject]@{Window=$w;Text=$w.FindName('DiagText');Mask=$w.FindName('DiagMask')}
        $w.FindName('DiagMask').Add_Checked([Windows.RoutedEventHandler]${function:Update-PestoDiagnosticPreview})
        $w.FindName('DiagMask').Add_Unchecked([Windows.RoutedEventHandler]${function:Update-PestoDiagnosticPreview})
        $w.FindName('DiagSave').Add_Click([Windows.RoutedEventHandler]${function:Save-PestoDiagnosticPreview})
        $w.FindName('DiagClose').Add_Click({param($s,$e);[Windows.Window]::GetWindow($s).Close()})
        $w.Add_Closed({$script:PestoDiagnosticUi=$null})
        Update-PestoDiagnosticPreview
        [void]$w.ShowDialog()
    }catch{$script:PestoDiagnosticUi=$null;Show-MsgWarning ('Diagnostic non préparé : '+$_.Exception.Message)}
}
function Update-PestoDiagnosticPreview {
    param($Sender,$EventArgs)
    if($script:PestoDiagnosticUi){$script:PestoDiagnosticUi.Text.Text=Get-PestoDiagnosticText -Redact ([bool]$script:PestoDiagnosticUi.Mask.IsChecked)}
}
function Save-PestoDiagnosticPreview {
    param($Sender,$EventArgs)
    if(-not $script:PestoDiagnosticUi){return}
    $dialog=[Microsoft.Win32.SaveFileDialog]::new();$dialog.Filter='Rapport JSON (*.json)|*.json';$dialog.FileName='Pesto_DIAGNOSTIC_'+(Get-Date -Format 'yyyyMMdd_HHmmss')+'.json';$dialog.OverwritePrompt=$true
    if($dialog.ShowDialog($script:PestoDiagnosticUi.Window) -ne $true){return}
    try{Write-PestoAtomicText -Path $dialog.FileName -Text ([string]$script:PestoDiagnosticUi.Text.Text);$script:PestoDiagnosticUi.Window.Close();Add-LogLine 'Diagnostic prévisualisé enregistré dans le fichier choisi. Aucun envoi automatique.' 'info'}
    catch{Show-MsgWarning ('Le rapport n''a pas été enregistré : '+$_.Exception.Message)}
}

function Apply-PestoQueueObservation {
    param($Row,$Observation,$Decision)
    if(-not $Row -or (-not $Decision.Verified -and -not $Decision.ResumeMove)){throw 'Observation insuffisante.'}
    if($Row.Operation_ID){
        $ledgerPath=Join-Path (Get-PestoInterventionRoot) (([Guid]$Row.Operation_ID).ToString('N')+'.json')
        if(Test-Path -LiteralPath $ledgerPath){[void](Confirm-PestoInterventionObservation -OperationId $Row.Operation_ID -Observation $Observation)}
    }
    $wasUncertain=[string]$Row.Statut -in @('INCERTAIN','TECHNIQUE','PROTECTION','EN COURS')
    if(-not $wasUncertain -and [string]$Row.Code -ne '89'){throw 'Cette ligne ne porte pas un résultat incertain ou un déplacement partiel.'}
    $previous='Statut '+[string]$Row.Statut+' ; code '+[string]$Row.Code+' ; '+[string]$Row.Message
    $old=@{};foreach($c in $script:table.Columns){$old[$c.ColumnName]=$Row[$c.ColumnName]}
    $wasLocked=[bool]$script:MutationUncertain
    try{
        $Row.Resultat_Precedent=Protect-PestoLogText $previous
        $Row.Traiter=$false
        if($Decision.ResumeMove){
            if(-not(Test-PestoOUInConfiguredScope ([string]$Row.OU_Destination))){throw 'La destination ne fait plus partie du périmètre.'}
            $Row.Resume_ID=[string]$Row.Operation_ID
            $Row.Nom_du_PC=[string]$Observation.AD.Name;$Row.Renommer=$false;$Row.Deplacer=$true;$Row.Reboot=$false
            $Row.OU_Actuelle=[string]$Observation.AD.OU;$Row.Objet_GUID=[string]$Observation.AD.Guid
            $Row.Statut='';$Row.Code='';$Row.Message='Déplacement seul préparé après observation. Résultat précédent conservé dans le détail.'
            $Row.Duree='';$Row.Horodatage='';$Row.Mode_Resultat='';$Row.Lot_ID=''
            Reset-PestoRowPreflight $Row
            $Row.NeedsReview=$true;$Row.ConfigStamp=Get-PestoConfigurationSignature $script:CFG
        }else{
            $Row.Statut='VÉRIFIÉ';$Row.Message=$previous+"`nObservation UTC "+$Observation.ObservedUtc+' : '+$Decision.Message
            $Row.Horodatage=[string]$Observation.ObservedUtc
        }
        if($wasUncertain -and -not $script:UnmappedQueueLock){
            $remaining=@(foreach($candidate in @($script:table.Rows|Where-Object{$_.Statut -in @('INCERTAIN','TECHNIQUE','PROTECTION','EN COURS')})){
                $acknowledged=$false
                try{
                    $candidateId=[Guid]::Empty
                    if([Guid]::TryParse([string]$candidate.Operation_ID,[ref]$candidateId) -and $candidateId -ne [Guid]::Empty){
                        $candidatePath=Join-Path (Get-PestoInterventionRoot) ($candidateId.ToString('N')+'.json')
                        $acknowledged=Test-PestoAcknowledgedReceipt (Read-PestoIntervention $candidatePath)
                    }
                }catch{$acknowledged=$false}
                if(-not $acknowledged){$candidate}
            })
            if($remaining.Count -eq 0){$script:MutationUncertain=$false}
        }
        Save-PestoQueueCheckpoint -Phase 'Reviewed'
    }catch{
        foreach($k in $old.Keys){$Row[$k]=$old[$k]};$script:MutationUncertain=$wasLocked
        throw
    }
    Write-AuditLine ('Observation du résultat de file consignée : '+$Decision.Message+' | '+$previous) 'info'
    Sync-Grid;Update-QueueButtons;Update-AddButton
}
