#requires -Version 5.1
# Configuration métier. L'apparence n'est jamais sauvegardée ici.

function ConvertTo-PestoCanonicalValue {
    param($Value)
    if($null -eq $Value){return $null}
    if($Value -is [Collections.IDictionary]){
        $map=[ordered]@{}
        foreach($key in @($Value.Keys|Sort-Object)){$map[[string]$key]=ConvertTo-PestoCanonicalValue $Value[$key]}
        return $map
    }
    if($Value -is [string] -or $Value -is [ValueType]){return $Value}
    if($Value -is [Collections.IEnumerable]){
        $list=@(foreach($item in $Value){ConvertTo-PestoCanonicalValue $item})
        return ,$list
    }
    $map=[ordered]@{}
    foreach($p in @($Value.PSObject.Properties|Sort-Object Name)){$map[$p.Name]=ConvertTo-PestoCanonicalValue $p.Value}
    return $map
}

function Resolve-PestoPolicyUiValue {
    param(
        [bool]$Forced,
        $UiValue,
        $LocalValue
    )
    if ($Forced) { return $LocalValue }
    return $UiValue
}

function Get-PestoConfigurationSignature {
    param($Config)
    if(-not $Config){return ''}
    $value=ConvertTo-PestoCanonicalValue $Config
    foreach($confKey in @($value.Keys|Where-Object{$_ -ieq 'CONF'})){
        foreach($c in @($value[$confKey])){
            if($c -is [Collections.IDictionary]){
                foreach($key in @($c.Keys)){if($key -in @('DarkMode','ADM','Buffer')){$c.Remove($key)}}
                # EntraPolicy absent ou vide = HybridOnly, valeur appliquée par le moteur : l'écrire en enregistrant les
                # paramètres n'est pas un changement (08/10 : « Enregistrer » sans rien changer imposait un redémarrage).
                $entra=@($c.Keys|Where-Object{$_ -ieq 'EntraPolicy'})
                if(-not $entra.Count){$c['EntraPolicy']='HybridOnly'}elseif(-not [string]$c[$entra[0]]){$c[$entra[0]]='HybridOnly'}
                # ClearProtectionOnMove absent = true (valeur appliquée par le moteur), écrit en texte par les paramètres.
                $clear=@($c.Keys|Where-Object{$_ -ieq 'ClearProtectionOnMove'})
                $clearValue=if($clear.Count){[string](Convert-Value-TF $c[$clear[0]] -Default $true)}else{'True'}
                foreach($k in $clear){$c.Remove($k)};$c['ClearProtectionOnMove']=$clearValue.ToLowerInvariant()
            }
        }
    }
    # POLICY absente ou partielle = valeurs par défaut : la signature compare la politique appliquée, pas sa forme écrite.
    try{
        $policy=ConvertTo-PestoCanonicalValue (ConvertTo-PestoPolicy $Config.POLICY -LocalOnly)
        foreach($k in @($value.Keys|Where-Object{$_ -ieq 'POLICY'})){$value.Remove($k)}
        $value['POLICY']=$policy
    }catch{}
    return (Get-PestoStableHash $value).ToUpperInvariant()
}

function Invalidate-PestoConfigurationPlans {
    $script:PreflightCache=@{}
    if($script:table){
        foreach($row in $script:table.Rows){
            $row.NeedsReview=$true
            $row.Precontrole='À REFAIRE';$row.Controle_Signature='';$row.Controle_Utc=''
            $row.Controle_Detail='Paramètres métier modifiés. Plan conservé à l''identique ; nouveau contrôle obligatoire.'
        }
        Save-PestoQueueCheckpointSafe
        Sync-Grid
    }
    $script:DirectCheckedKey=''
    if($script:JoinUI){$script:JoinCheckedKey=''}
    Add-LogLine 'Paramètres métier modifiés : plans conservés et contrôles invalidés, sans changer les noms ou les OU préparés.' 'warn'
}


function Invoke-PestoConfigRepairSave {
    param($Sender,$EventArgs)
    $ctx=$Sender.Tag
    if($null -eq $ctx){return}
    try{
        if($ctx.Json.Text.Length -gt 1MB){throw 'Configuration trop volumineuse (> 1 Mio).'}
        $cfg=$ctx.Json.Text|ConvertFrom-Json -ErrorAction Stop
        $errors=@(Test-CfgValid $cfg)
        if($errors.Count){$ctx.Errors.Text=$errors -join "`r`n";return}
        Write-PestoAtomicText -Path $ctx.Path -Text $ctx.Json.Text -Backup
        $ctx.Window.Tag=$cfg
        $ctx.Window.DialogResult=$true
    }catch{$ctx.Errors.Text=[string]$_.Exception.Message}
}

function Show-PestoConfigRepair {
    param([string]$Path,[string]$Text,[string[]]$Errors)
    [xml]$cx=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Pesto · Corriger la configuration" Width="1050" Height="780" MinWidth="700" MinHeight="500" WindowStartupLocation="CenterScreen" Background="{DynamicResource BgWindow}" Foreground="{DynamicResource FgText}">
 <Grid Margin="20"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
  <StackPanel><TextBlock Text="Configuration à corriger" FontSize="24" FontWeight="SemiBold"/><TextBlock x:Name="PathLabel" TextWrapping="Wrap" Margin="0,5,0,12" Foreground="{DynamicResource FgMuted}"/></StackPanel>
  <TextBox Grid.Row="1" x:Name="Errors" VerticalContentAlignment="Top" IsReadOnly="True" TextWrapping="Wrap" MaxHeight="160" VerticalScrollBarVisibility="Auto" Background="{DynamicResource BgInput}" Foreground="{DynamicResource FgText}" Padding="10" Margin="0,0,0,12" ToolTip="Erreurs de configuration à corriger avant connexion. Aucun changement de domaine ou de poste effectué ici." ToolTipService.ShowOnDisabled="True" ToolTipService.InitialShowDelay="450" ToolTipService.ShowDuration="30000" AutomationProperties.HelpText="Erreurs de configuration à corriger avant connexion. Aucun changement de domaine ou de poste effectué ici." AutomationProperties.Name="Erreurs de configuration" AutomationProperties.AutomationId="Errors"/>
  <TextBox Grid.Row="2" x:Name="Json" VerticalContentAlignment="Top" AcceptsReturn="True" AcceptsTab="True" HorizontalScrollBarVisibility="Auto" VerticalScrollBarVisibility="Auto" TextWrapping="NoWrap" FontFamily="Consolas" FontSize="13" Background="{DynamicResource BgInput}" Foreground="{DynamicResource FgText}" Padding="10" ToolTip="Configuration JSON affichée pour validation. Préférez Importer pour réutiliser le fichier opérationnel de votre installation." ToolTipService.ShowOnDisabled="True" ToolTipService.InitialShowDelay="450" ToolTipService.ShowDuration="30000" AutomationProperties.HelpText="Configuration JSON affichée pour validation. Préférez Importer pour réutiliser le fichier opérationnel de votre installation." AutomationProperties.Name="Configuration à valider" AutomationProperties.AutomationId="Json"/>
  <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0"><Button x:Name="Wizard" Content="Créer avec l’assistant" Padding="18,9" Margin="0,0,10,0" ToolTip="Créer un modèle en remplissant des champs guidés, sans réseau et sans sauvegarde automatique."/><Button x:Name="Import" Content="Importer une configuration" Padding="18,9" Margin="0,0,10,0" ToolTip="Choisir un fichier cfg.json existant. Il est affiché et contrôlé avant enregistrement." AutomationProperties.Name="Importer une configuration"/><Button x:Name="Save" Content="Valider, sauvegarder et continuer" Padding="18,9" Margin="0,0,10,0" ToolTip="Valider, sauvegarder et continuer : action uniquement au clic." ToolTipService.ShowOnDisabled="True" ToolTipService.InitialShowDelay="450" ToolTipService.ShowDuration="30000" AutomationProperties.HelpText="Valider, sauvegarder et continuer : action uniquement au clic." AutomationProperties.AutomationId="Save"/><Button Content="Quitter" IsCancel="True" Padding="18,9" ToolTip="Quitter : action uniquement au clic." ToolTipService.ShowOnDisabled="True" ToolTipService.InitialShowDelay="450" ToolTipService.ShowDuration="30000" AutomationProperties.HelpText="Quitter : action uniquement au clic."/></StackPanel>
 </Grid>
</Window>

'@
    if(-not $script:ThemeMode){
        Initialize-PestoAppearance -OwnerSid $AppearanceOwnerSid -Config ([pscustomobject]@{Conf=@([pscustomobject]@{DarkMode=2})})
        foreach($key in $script:Themes[$script:CurrentTheme].Keys){$Win.Resources[$key]=New-Brush $script:Themes[$script:CurrentTheme][$key]}
    }
    $w=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($cx))
    $w.Resources=$Win.Resources;Set-WindowIcon $w
    $wa=[Windows.SystemParameters]::WorkArea
    $w.MinWidth=[Math]::Min($w.MinWidth,[Math]::Max(320,$wa.Width-24));$w.MinHeight=[Math]::Min($w.MinHeight,[Math]::Max(300,$wa.Height-24))
    $w.MaxWidth=[Math]::Max($w.MinWidth,$wa.Width-24);$w.MaxHeight=[Math]::Max($w.MinHeight,$wa.Height-24)
    $box=$w.FindName('Json');$errBox=$w.FindName('Errors');$box.Text=$Text
    $errBox.Text=($Errors -join "`r`n");$w.FindName('PathLabel').Text="Aucun accès AD n'est lancé. Vérifiez vos valeurs réelles ; Pesto n'invente pas le domaine ni les OUs. Fichier : $Path"
    $save=$w.FindName('Save')
    $save.Tag=[pscustomobject]@{Window=$w;Json=$box;Errors=$errBox;Path=$Path}
    $save.Add_Click([Windows.RoutedEventHandler]${function:Invoke-PestoConfigRepairSave})
    $wizard=$w.FindName('Wizard');$wizard.Tag=$save.Tag;$wizard.Add_Click([Windows.RoutedEventHandler]${function:Invoke-PestoConfigWizard})
    $import=$w.FindName('Import');$import.Tag=$save.Tag
    $import.Add_Click([Windows.RoutedEventHandler]${function:Invoke-PestoConfigImport})
    if($w.ShowDialog() -eq $true){return $w.Tag}
    return $null
}

function Read-PestoStartupConfig {
    param([string]$Path)
    $text='';$errors=@();$cfg=$null
    try{
        if(-not (Test-Path -LiteralPath $Path)){throw "Fichier absent : $Path"}
        if((Get-Item -LiteralPath $Path).Length -gt 1MB){throw 'Configuration trop volumineuse (> 1 Mio).'}
        $text=Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        $cfg=$text|ConvertFrom-Json -ErrorAction Stop;$errors=@(Test-CfgValid $cfg)
    }catch{$errors=@([string]$_.Exception.Message)}
    if($errors.Count){$cfg=Show-PestoConfigRepair -Path $Path -Text $text -Errors $errors}
    if($null -ne $cfg){[void](Set-PestoActiveNamingConvention $(if($cfg.PSObject.Properties['NamingConvention']){$cfg.NamingConvention}else{$null}))}
    return $cfg
}

function Test-CfgValid {
    <# Validation structurelle et métier du cfg.json. #>
    param($Cfg)
    $validationConvention=Get-PestoDefaultNamingConvention
    try{$validationConvention=Assert-PestoNamingConvention $Cfg.NamingConvention}catch{}
    $m = [System.Collections.Generic.List[string]]::new()
    if ($null -eq $Cfg) { [void]$m.Add('Configuration vide.'); return $m.ToArray() }
    if($Cfg.PSObject.Properties['Configured'] -and $Cfg.Configured -ne $true){[void]$m.Add('Première utilisation : importez une configuration d''entreprise valide, puis validez. Aucun accès AD tant que cette étape n''est pas terminée.')}

    try{[void](ConvertTo-PestoPolicy $Cfg.POLICY)}catch{[void]$m.Add($_.Exception.Message)}
    if($Cfg.PSObject.Properties['NamingConvention'] -and $null -ne $Cfg.NamingConvention){
        try{[void](Assert-PestoNamingConvention $Cfg.NamingConvention)}catch{[void]$m.Add('NamingConvention : '+$_.Exception.Message)}
    }
    foreach($e in @($Cfg.NameCatalogue)){if($null -ne $e){
        try{Assert-PestoClosedObject $e @('Site','Service') @('Site','Service');if($e.Site -notmatch (Get-PestoFacetPattern Site $validationConvention) -or $e.Service -notmatch (Get-PestoFacetPattern Service $validationConvention)){throw 'Catalogue site/service invalide.'}}catch{[void]$m.Add($_.Exception.Message)}
    }}
    $confs = @($Cfg.CONF)
    if ($confs.Count -ne 1 -or $null -eq $confs[0]) {
        [void]$m.Add("'CONF' doit contenir exactement un objet."); return $m.ToArray()
    }
    $conf = $confs[0]
    $domain = "$($conf.Domaine)".Trim(); $prefix = "$($conf.Prefixe)".Trim(); $pre = "$($conf.PreprodSite)".Trim()
    if(-not (Test-PestoDnsName $domain)){[void]$m.Add("Domaine DNS invalide : '$domain'.")}
    if ($prefix -notmatch (Get-PestoFacetPattern Prefix $validationConvention)) {
        [void]$m.Add('Préfixe invalide : largeur definie par la convention requise.')
    }
    if ($pre -notmatch (Get-PestoFacetPattern Service $validationConvention)) {
        [void]$m.Add('PreprodSite invalide : largeur de service definie par la convention requise.')
    }
    $darkMode = "$($conf.DarkMode)".Trim()
    if ($darkMode -and $darkMode -notin @('0','1','2')) { [void]$m.Add('DarkMode : 0, 1 ou 2 requis.') }
    $buffer = "$($conf.Buffer)".Trim()
    $bufferValue=0
    if($buffer -and (-not [int]::TryParse($buffer,[ref]$bufferValue) -or $bufferValue -lt 0 -or $bufferValue -gt 999)){
        [void]$m.Add('Buffer : entier compris entre 0 et 999 requis.')
    }
    if ("$($conf.OUScanNoms)".Trim() -and -not (Test-PestoOUPath "$($conf.OUScanNoms)")) {
        [void]$m.Add('OUScanNoms doit être un DN d''OU valide ou rester vide.')
    }

    if($conf.EntraPolicy -and $conf.EntraPolicy -notin @('HybridOnly','Disabled')){[void]$m.Add('EntraPolicy doit valoir HybridOnly ou Disabled.')}
    foreach ($prop in @('DirectProd','DsregLeaveOnMove','ClearProtectionOnMove','MoveRollbackOnRenameFail','AllowHybridRepair')) {
        if ($null -ne $conf.$prop -and -not [string]::IsNullOrWhiteSpace("$($conf.$prop)")) {
            try { [void](Convert-Value-TF $conf.$prop -Strict) }
            catch { [void]$m.Add("$prop : valeur booléenne invalide.") }
        }
    }
    foreach ($prop in @('Simulation','HorsDomaine','MauvaiseOU','BPVerifNomAD','ForceADM','GUI')) {
        if ($Cfg.DEBUG -and $null -ne $Cfg.DEBUG.$prop -and
            -not [string]::IsNullOrWhiteSpace("$($Cfg.DEBUG.$prop)")) {
            try { [void](Convert-Value-TF $Cfg.DEBUG.$prop -Strict) }
            catch { [void]$m.Add("DEBUG.$prop : valeur booléenne invalide.") }
        }
    }

    # Les drapeaux qui faussent volontairement l'état métier ne sont acceptés
    # qu'en démonstration/simulation. Les laisser actifs avec des écritures réelles
    # serait trop dangereux pour une version PROD (fausse détection hors domaine,
    # déplacement proposé artificiellement depuis une « mauvaise OU »).
    try {
        $dbgSim = if ($Cfg.DEBUG) { Convert-Value-TF $Cfg.DEBUG.Simulation -Strict } else { $false }
        $dbgGui = if ($Cfg.DEBUG) { Convert-Value-TF $Cfg.DEBUG.GUI -Strict } else { $false }
        $dbgODM = if ($Cfg.DEBUG) { Convert-Value-TF $Cfg.DEBUG.HorsDomaine -Strict } else { $false }
        $dbgWOU = if ($Cfg.DEBUG) { Convert-Value-TF $Cfg.DEBUG.MauvaiseOU -Strict } else { $false }
        if (-not ($dbgSim -or $dbgGui)) {
            if ($dbgODM) { [void]$m.Add('DEBUG.HorsDomaine=true est interdit en mode réel PROD. Utilisez Simulation/GUI ; en réel Pesto détecte automatiquement l''appartenance au domaine.') }
            if ($dbgWOU) { [void]$m.Add('DEBUG.MauvaiseOU=true est interdit en mode réel PROD. Utilisez Simulation/GUI pour ce test.') }
        }
    } catch { }

    $baseNames = @{}
    foreach ($o in @($Cfg.OUBase)) {
        $n = "$($o.Nom)".Trim(); $ou = "$($o.OU)".Trim()
        if (-not $n -or -not $ou) { [void]$m.Add('OUBase : Nom et OU sont obligatoires.'); continue }
        if ($baseNames.ContainsKey($n)) { [void]$m.Add("OUBase : nom dupliqué '$n'.") }
        else { $baseNames[$n] = $true }
        if (-not (Test-PestoOUPath $ou)) { [void]$m.Add("OUBase '$n' : DN invalide.") }
    }
    if (-not $baseNames.ContainsKey('ROOT')) { [void]$m.Add("L'OU ROOT est manquante (OUBase).") }

    $direct = $false
    try { $direct = Convert-Value-TF $conf.DirectProd -Strict } catch {}
    if (-not $direct -and -not $baseNames.ContainsKey('PREPROD')) {
        [void]$m.Add("L'OU PREPROD est obligatoire quand DirectProd=false.")
    }

    $siteNames = @{}
    if (-not $Cfg.OUSite -or @($Cfg.OUSite).Count -eq 0) { [void]$m.Add('Aucun organisme (OUSite) défini.') }
    foreach ($o in @($Cfg.OUSite)) {
        $n = "$($o.Nom)".Trim(); $ou = "$($o.OU)".Trim()
        if (-not $n -or -not $ou) { [void]$m.Add('OUSite : Nom et OU sont obligatoires.'); continue }
        if ($siteNames.ContainsKey($n)) { [void]$m.Add("OUSite : nom dupliqué '$n'.") }
        else { $siteNames[$n] = $true }
        if (-not (Test-PestoOUPath $ou)) { [void]$m.Add("OUSite '$n' : DN invalide.") }
    }

    $tagPatterns = @{}; $validPreprodTag = $false
    $aliases = @('PREPROD', $pre, "${pre}_PREPROD", "${pre}_PROD_A_NOMMER") | Where-Object { $_ }
    foreach ($t in @($Cfg.TAGS)) {
        $pat = "$($t.Site)".Trim(); $tag = "$($t.Tag)".Trim()
        if (-not $pat) { [void]$m.Add('TAGS : le motif Site est obligatoire.'); continue }
        $tagOk = ($tag -match (Get-PestoFacetPattern Site $validationConvention))
        if (-not $tagOk) { [void]$m.Add("Tag '$pat' incohérent : exactement 2 lettres requises.") }
        if ($tagPatterns.ContainsKey($pat)) { [void]$m.Add("TAGS : motif dupliqué '$pat'.") }
        else { $tagPatterns[$pat] = $true }

        $wild = $null
        try {
            $wild = [System.Management.Automation.WildcardPattern]::new(
                $pat, [System.Management.Automation.WildcardOptions]::IgnoreCase)
        } catch {
            [void]$m.Add("TAGS : motif wildcard invalide '$pat'.")
        }
        if ($tagOk -and $wild) {
            foreach ($a in $aliases) { if ($wild.IsMatch("$a")) { $validPreprodTag = $true; break } }
        }
    }
    if (-not $direct -and -not $validPreprodTag) {
        [void]$m.Add("Aucun TAGS valide ne couvre PREPROD / '$pre'.")
    }
    # Une chaîne syntaxiquement correcte peut désigner un AUTRE domaine.
    $dnsExpected=$domain.TrimEnd('.')
    $paths=@(@($Cfg.OUBase)+@($Cfg.OUSite))
    foreach($entry in $paths){
        if(Test-PestoOUPath ([string]$entry.OU)){
            $actual=Get-PestoDomainFromDN ([string]$entry.OU)
            if($actual -ine $dnsExpected){[void]$m.Add("OU '$($entry.Nom)' : domaine DN '$actual' différent de Domaine='$domain'.")}
        }
    }
    if(Test-PestoOUPath ([string]$conf.OUScanNoms)){
        if((Get-PestoDomainFromDN ([string]$conf.OUScanNoms)) -ine $dnsExpected){[void]$m.Add("OUScanNoms ne correspond pas au domaine '$domain'.")}
    }
    return $m.ToArray()
}

function Load-SettingsUI {
    param($Config=$null,[switch]$Draft)
    if($null -eq $Config){$Config=if($script:SettingsSourceConfig){$script:SettingsSourceConfig}else{$script:CFG}}
    $script:SettingsEditorConfig=$Config
    if(-not $Draft){$script:SettingsSourceConfig=$Config;$script:SettingsDiskStamp=Get-PestoConfigFileStamp $script:JsonFile}
    <# Remplit les champs et grilles de l'onglet Paramètres depuis $Config. #>
    $script:SuspendSet = $true
    $conf = @($Config.Conf)[0]
    $SetTxtDomaine.Text = "$($conf.Domaine)"; $SetTxtADM.Text = "$($conf.ADM)"
    $SetTxtPrefixe.Text = "$($conf.Prefixe)"; $SetTxtPreprod.Text = "$($conf.PreprodSite)"
    $SetTxtBuffer.Text  = "$($conf.Buffer)";  $SetTxtOUScan.Text = "$($conf.OUScanNoms)"
    $SetChkDirectProd.IsChecked = (Convert-Value-TF $conf.DirectProd)
    $SetChkDsreg.IsChecked = ([string]$conf.EntraPolicy -ne 'Disabled'); $SetChkDsreg.IsEnabled = $true
    $SetChkDsreg.Content='Autoriser le retrait Entra avant renommage d''un poste hybride'
    $SetChkDsreg.ToolTip='État réel relu sur la cible. AD seul : aucun retrait. Hybride : retrait avant renommage uniquement si autorisé. Réinscription à vérifier séparément. Clé : CONF.0.EntraPolicy.'
    Sync-PestoAppearanceControls
    $SetChkSim.IsChecked = (Convert-Value-TF $Config.Debug.Simulation)
    $SetChkODM.IsChecked = (Convert-Value-TF $Config.Debug.HorsDomaine)
    $SetChkWOU.IsChecked = (Convert-Value-TF $Config.Debug.MauvaiseOU)
    $SetChkBVA.IsChecked = (Convert-Value-TF $Config.Debug.BPVerifNomAD)
    $SetChkGOD.IsChecked = (Convert-Value-TF $Config.Debug.ForceADM)
    $SetChkGUI.IsChecked = (Convert-Value-TF $Config.Debug.GUI)
    $script:TblTags = New-KvTable @('Site','Tag')
    foreach ($t in @($Config.TAGS)) { $r=$script:TblTags.NewRow(); $r.Site="$($t.Site)"; $r.Tag="$($t.Tag)"; [void]$script:TblTags.Rows.Add($r) }
    $SetGridTags.ItemsSource = $script:TblTags.DefaultView
    $script:TblOUBase = New-KvTable @('Nom','OU')
    foreach ($o in @($Config.OUBase)) { $r=$script:TblOUBase.NewRow(); $r.Nom="$($o.Nom)"; $r.OU="$($o.OU)"; [void]$script:TblOUBase.Rows.Add($r) }
    $SetGridOUBase.ItemsSource = $script:TblOUBase.DefaultView
    $script:TblOUSite = New-KvTable @('Nom','OU')
    foreach ($o in @($Config.OUSite)) { $r=$script:TblOUSite.NewRow(); $r.Nom="$($o.Nom)"; $r.OU="$($o.OU)"; [void]$script:TblOUSite.Rows.Add($r) }
    $SetGridOUSite.ItemsSource = $script:TblOUSite.DefaultView
    $SetLblPrefixes.Text = "Préfixes dérivés : P$($conf.Prefixe) (portable)  ·  S$($conf.Prefixe) (fixe)"
    # Noms et coordination, politique (08/10) : valeurs appliquées, défauts compris.
    $pol=$null;try{$pol=ConvertTo-PestoPolicy $Config.POLICY -LocalOnly}catch{$pol=ConvertTo-PestoPolicy $null -LocalOnly}
    if($SetTxtCoordRoot){
        $SetTxtCoordRoot.Text=[string]$pol.CoordinationRoot
        $SetTxtReserveMinutes.Text=[string]$pol.NameReservationMinutes
        $SetChkCoordRequired.IsChecked=[bool]$pol.CoordinationRequired
        $SetChkRandomName.IsChecked=[bool]$pol.RandomNameEnabled
        $SetChkReserveAD.IsChecked=[bool]$pol.ReserveNamesInAD
        $SetChkPrecreated.IsChecked=[bool]$pol.AllowPrecreatedJoin
        $retention=$Win.FindName('SetTxtLogRetention');if($retention){$retention.Text=[string]$pol.LogRetentionDays}
        $unattended=$Win.FindName('SetChkUnattendedJoin');if($unattended){$unattended.IsChecked=[bool]$pol.UnattendedJoinEnabled}
        foreach($pair in @(@('SetChkClockSkew','BlockJoinOnClockSkew'),@('SetChkIncidentMode','IncidentMode'),@('SetChkAuditEventLog','AuditEventLogEnabled'),@('SetChkUnattendedOperations','UnattendedOperationsEnabled'))){$control=$Win.FindName($pair[0]);if($control){$control.IsChecked=[bool]$pol.($pair[1])}}
        $SetTxtMaxBatch.Text=[string]$pol.MaxBatch;$SetTxtMaxReaders.Text=[string]$pol.MaxReaders;$SetTxtReadAttempts.Text=[string]$pol.ReadAttempts
        $SetChkPasswordFallback.IsChecked=[bool]$pol.AllowPasswordTaskFallback
        $SetTxtExcludedNames.Text=(@($pol.ExcludedNames) -join "`r`n")
        $SetTxtExcludedOUs.Text=(@($pol.ExcludedOUs) -join "`r`n")
        $SetTxtExcludedGroups.Text=(@($pol.ExcludedGroupGuids) -join "`r`n")
        $SetChkClearProtection.IsChecked=if($null -ne $conf.ClearProtectionOnMove){Convert-Value-TF $conf.ClearProtectionOnMove -Default $true}else{$true}
        Update-PestoSharedNameStatus
    }
    Sync-PestoManagedSettings
    $SetLblStatus.Text = "Chargé depuis cfg.json."
    Show-PestoConfigurationErrors @()
    $script:SuspendSet = $false
    if(-not $Draft){$script:SettingsBaselineHash=Get-PestoStableHash (Build-CfgFromUI)}
}

function Build-PestoPolicyFromUI {
    <# Section POLICY écrite depuis Paramètres. Un nombre illisible est gardé tel quel : Test-CfgValid le signale. #>
    $number={param($text) $v=0;$s=([string]$text).Trim();if([int]::TryParse($s,[ref]$v)){$v}else{$s}}
    $lines={param($text) ,([object[]]@(([string]$text) -split "`r?`n"|ForEach-Object{$_.Trim()}|Where-Object{$_}))}
    $current=$null;try{$current=ConvertTo-PestoPolicy (Get-PestoSettingsSource).POLICY -LocalOnly}catch{$current=ConvertTo-PestoPolicy $null}
    $pol=[ordered]@{Schema=1}
    $pol.ExcludedNames=& $lines $SetTxtExcludedNames.Text
    $pol.ExcludedOUs=& $lines $SetTxtExcludedOUs.Text
    $pol.ExcludedGroupGuids=& $lines $SetTxtExcludedGroups.Text
    $pol.CoordinationRoot=([string]$SetTxtCoordRoot.Text).Trim()
    $pol.CoordinationRequired=[bool]$SetChkCoordRequired.IsChecked
    $pol.AllowPasswordTaskFallback=[bool]$SetChkPasswordFallback.IsChecked
    $pol.AllowPrecreatedJoin=[bool]$SetChkPrecreated.IsChecked
    $pol.AllowOfflineJoin=[bool]$current.AllowOfflineJoin
    $pol.Scenario=$current.Scenario
    $unattended=$Win.FindName('SetChkUnattendedJoin');$pol.UnattendedJoinEnabled=if($unattended){[bool]$unattended.IsChecked}else{[bool]$current.UnattendedJoinEnabled}
    foreach($pair in @(@('SetChkClockSkew','BlockJoinOnClockSkew'),@('SetChkIncidentMode','IncidentMode'),@('SetChkAuditEventLog','AuditEventLogEnabled'),@('SetChkUnattendedOperations','UnattendedOperationsEnabled'))){$control=$Win.FindName($pair[0]);$pol[$pair[1]]=if($control){[bool]$control.IsChecked}else{[bool]$current.($pair[1])}}
    $pol.MaxReaders=& $number $SetTxtMaxReaders.Text
    $pol.ReadAttempts=& $number $SetTxtReadAttempts.Text
    $pol.MaxBatch=& $number $SetTxtMaxBatch.Text
    $pol.NameReservationMinutes=& $number $SetTxtReserveMinutes.Text
    $pol.ReserveNamesInAD=[bool]$SetChkReserveAD.IsChecked
    $pol.RandomNameEnabled=[bool]$SetChkRandomName.IsChecked
    $retention=$Win.FindName('SetTxtLogRetention');$pol.LogRetentionDays=if($retention){& $number $retention.Text}else{$current.LogRetentionDays}
    $managed=Get-PestoManagedPolicy
    if($managed.Configured){
        if($managed.Values.IncidentMode -eq 1){$pol.IncidentMode=[bool]$current.IncidentMode}
        if($managed.Values.DisableUnattendedJoin -eq 1){$pol.UnattendedJoinEnabled=[bool]$current.UnattendedJoinEnabled}
        if($managed.Values.DisableUnattendedOperations -eq 1){$pol.UnattendedOperationsEnabled=[bool]$current.UnattendedOperationsEnabled}
        if($null -ne $managed.Values.MaxBatch){$pol.MaxBatch=$current.MaxBatch}
    }
    return $pol
}

function Invoke-PestoCoordinationCommand {
    <# « Préparer ce dossier » et « Tester » : registre partagé lu ou préparé en arrière-plan, jamais de partage créé. #>
    param($Sender,$EventArgs)
    try{
        if($script:GUI){Show-MsgInfo 'Démonstration : aucun accès au registre partagé.';return}
        $root=([string]$SetTxtCoordRoot.Text).Trim()
        if(-not $root){throw 'Saisissez le chemin du dossier partagé, par exemple \\serveur\partage\Pesto.'}
        if($root.Length -gt 240 -or $root -match '[\x00-\x1f"*?]' -or -not [IO.Path]::IsPathRooted($root)){throw 'Chemin absolu de 240 caractères au plus attendu.'}
        $mode=if($Sender -and $Sender.Name -eq 'SetBtnCoordPrepare'){'Prepare'}else{'Test'}
        if($mode -eq 'Prepare' -and -not (Confirm-YesNo -Msg ("Préparer le registre partagé dans :`n$root`n`nPesto crée ce dossier s'il manque (sous un dossier parent existant), le marqueur du domaine $script:DOMAINE et les sous-dossiers locks et reservations.`nAucun partage n'est créé, aucun droit n'est modifié.`n`nPréparer ?") -Confirm $true)){return}
        $script:SharedNameStatus=if($mode -eq 'Prepare'){'Préparation du registre partagé…'}else{'Test du registre partagé…'}
        Update-PestoSharedNameStatus
        if(-not (Start-PestoSharedNameOperation -Mode $mode -Root $root)){throw 'Opération non lancée : une autre lecture du registre est en cours.'}
    }catch{Show-MsgWarning $_.Exception.Message}
}

function Build-CfgFromUI {
    foreach ($g in @($SetGridTags,$SetGridOUBase,$SetGridOUSite)) {
        try { [void]$g.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Cell,$true) } catch {}
        try { [void]$g.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Row,$true) } catch {}
    }
    $conf = ConvertTo-PestoOrderedMap ((@((Get-PestoSettingsSource).Conf))[0])
    Set-PestoMapValue $conf 'Domaine' "$($SetTxtDomaine.Text)".Trim()
    Set-PestoMapValue $conf 'ADM' "$($SetTxtADM.Text)".Trim()
    Set-PestoMapValue $conf 'Prefixe' "$($SetTxtPrefixe.Text)".Trim().ToUpperInvariant()
    Set-PestoMapValue $conf 'PreprodSite' "$($SetTxtPreprod.Text)".Trim().ToUpperInvariant()
    Set-PestoMapValue $conf 'DirectProd' (ToTF $SetChkDirectProd)
    # DarkMode du fichier reste la valeur de repli. Le choix utilisateur est une préférence séparée.
    Set-PestoMapValue $conf 'Buffer' "$($SetTxtBuffer.Text)".Trim()
    Set-PestoMapValue $conf 'OUScanNoms' "$($SetTxtOUScan.Text)".Trim()
    Set-PestoMapValue $conf 'EntraPolicy' $(if($SetChkDsreg.IsChecked){'HybridOnly'}else{'Disabled'})
    if($SetChkClearProtection){Set-PestoMapValue $conf 'ClearProtectionOnMove' (ToTF $SetChkClearProtection)}
    # AllowHybridRepair : ancien réglage conservé, EntraPolicy décrit le parcours actuel.

    $debug = ConvertTo-PestoOrderedMap (Get-PestoSettingsSource).DEBUG
    Set-PestoMapValue $debug 'Simulation' (ToTF $SetChkSim)
    Set-PestoMapValue $debug 'HorsDomaine' (ToTF $SetChkODM)
    Set-PestoMapValue $debug 'MauvaiseOU' (ToTF $SetChkWOU)
    Set-PestoMapValue $debug 'BPVerifNomAD' (ToTF $SetChkBVA)
    Set-PestoMapValue $debug 'ForceADM' (ToTF $SetChkGOD)
    Set-PestoMapValue $debug 'GUI' (ToTF $SetChkGUI)

    $tags = @(); foreach ($row in @($script:TblTags.Rows)) {
        if ($row.RowState -eq 'Deleted') { continue }
        $s = "$($row.Site)".Trim(); $g = "$($row.Tag)".Trim().ToUpperInvariant()
        if ($s -or $g) { $tags += [ordered]@{ Site=$s; Tag=$g } }
    }
    $oubase = @(); foreach ($row in @($script:TblOUBase.Rows)) {
        if ($row.RowState -eq 'Deleted') { continue }
        $n = "$($row.Nom)".Trim(); $o = "$($row.OU)".Trim()
        if ($n -or $o) { $oubase += [ordered]@{ Nom=$n; OU=$o } }
    }
    $ousite = @(); foreach ($row in @($script:TblOUSite.Rows)) {
        if ($row.RowState -eq 'Deleted') { continue }
        $n = "$($row.Nom)".Trim(); $o = "$($row.OU)".Trim()
        if ($n -or $o) { $ousite += [ordered]@{ Nom=$n; OU=$o } }
    }

    $cfg = ConvertTo-PestoOrderedMap (Get-PestoSettingsSource)
    Set-PestoMapValue $cfg 'DEBUG' $debug
    if($SetTxtCoordRoot){Set-PestoMapValue $cfg 'POLICY' (Build-PestoPolicyFromUI)}
    Set-PestoMapValue $cfg 'CONF' ([object[]]@($conf))
    Set-PestoMapValue $cfg 'TAGS' ([object[]]$tags)
    Set-PestoMapValue $cfg 'OUBase' ([object[]]$oubase)
    Set-PestoMapValue $cfg 'OUSite' ([object[]]$ousite)
    return $cfg
}

function Save-Cfg {
    if($script:PestoReadOnly){Show-MsgWarning 'Consultation : la configuration ne peut pas être enregistrée. Ouvrez une session d''intervention pour la modifier.';return}
    if($script:DirectBusy -or $script:PreflightRunning -or (Test-PestoAsyncOperationRunning 'DirectoryRefresh')){Show-MsgWarning 'Attendez la fin de l''opération ou du contrôle avant de modifier les paramètres métier.';return}
    if($script:JoinBusy -or (Test-PestoAsyncOperationRunning 'DomainJoin')){Show-MsgWarning 'Attendez la fin de la jonction avant de modifier la configuration.';return}
    if ($script:Running) { Show-MsgWarning 'Enregistrement impossible pendant l''exécution de la file.'; return }
    if ($script:EDIT_ROW_INDEX -ge 0) { Show-MsgWarning 'Terminez ou annulez l''édition de la ligne avant de modifier la configuration.'; return }

    $cfg = Build-CfgFromUI
    $errs = @(Test-CfgValid $cfg)
    if ($errs.Count) {
        Show-PestoConfigurationErrors $errs
        Show-MsgError ("Configuration invalide — rien n'a été enregistré :`n`n- " + ($errs -join "`n- "))
        return
    }

    Show-PestoConfigurationErrors @()
    $changes=@(Get-PestoConfigurationChanges $(if($script:SettingsSourceConfig){$script:SettingsSourceConfig}else{$script:CFG}) $cfg)
    if($changes.Count){
        $readable=@(Get-PestoReadableConfigChanges $(if($script:SettingsSourceConfig){$script:SettingsSourceConfig}else{$script:CFG}) $cfg)
        $preview=Format-PestoConfigChanges $readable
        $beforePolicy=(Get-PestoSettingsSource).POLICY
        if([bool]$cfg.POLICY.IncidentMode -ne [bool]$beforePolicy.IncidentMode){if(-not(Confirm-YesNo -Msg ('Mode incident : '+[bool]$cfg.POLICY.IncidentMode+'. Ce réglage suspend les nouvelles mutations après rechargement ; les lectures restent autorisées.') -Confirm $true -AcceptText 'Confirmer ce réglage')){return}}
        $warnings=@(Get-PestoConfigurationWarnings $cfg);if($warnings.Count){$preview+="`n"+($warnings -join "`n")}
        $answer=Show-PestoPanel -Title 'Enregistrer ces paramètres ?' -Body ($preview+"`nLa sauvegarde .bak est conservée. Un changement métier demande de relancer Pesto.") -AcceptText 'Enregistrer' -Monospace
        if(-not $answer.Accepted){return}
    }
    try {
        $json=$cfg|ConvertTo-Json -Depth 20
        Assert-PestoConfigFileUnchanged -Path $script:JsonFile -Expected $script:SettingsDiskStamp
        Write-PestoAtomicText -Path $script:JsonFile -Text $json -Backup
        $script:SettingsDiskStamp=Get-PestoConfigFileStamp $script:JsonFile
        Add-LogLine 'cfg.json enregistré (sauvegarde cfg.json.bak conservée).' 'ok'
        $SetLblStatus.Text = "Enregistré à $(Get-Date -Format 'HH:mm:ss') — sauvegarde .bak conservée."
        [void](Apply-CfgHot)
        $script:SettingsSourceConfig=$cfg;$script:SettingsEditorConfig=$cfg;$script:SettingsBaselineHash=Get-PestoStableHash (Build-CfgFromUI)
    } catch {
        Write-Log "Écriture de cfg.json impossible ('$script:JsonFile')." 'ERROR' $_ 'config'
        Show-MsgError "Écriture de cfg.json impossible :`n$($_.Exception.Message)"
    }
}

function Apply-CfgHot {
    <# Les réglages sans impact métier sont rechargés. Un changement métier
       reste en attente du prochain lancement, sans mélange de contextes AD. #>
    try { $newCfg = Get-Content -LiteralPath $script:JsonFile -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch {
        Add-LogLine "Relecture de cfg.json échouée : $($_.Exception.Message)" 'warn'
        Show-MsgWarning 'Configuration enregistrée, mais sa relecture a échoué.'
        return $false
    }
    $errs = @(Test-CfgValid $newCfg)
    if ($errs.Count) { Show-MsgError ("cfg.json invalide :`n- " + ($errs -join "`n- ")); return $false }
    [void](Set-PestoActiveNamingConvention $(if($newCfg.PSObject.Properties['NamingConvention']){$newCfg.NamingConvention}else{$null}))

    $script:SettingsSourceConfig=$newCfg
    $changed=(Get-PestoConfigurationSignature $newCfg) -ne (Get-PestoConfigurationSignature $script:CFG)
    if(-not $changed){
        $script:CFG=$newCfg
        $script:PestoPolicy=ConvertTo-PestoPolicy $newCfg.POLICY
        $presentationConf=@($newCfg.Conf)[0]
        $script:DEFAULTADM=[string]$presentationConf.ADM
        $script:NmBuffer=if([string]$presentationConf.Buffer){[int]$presentationConf.Buffer}else{10}
        $SetLblStatus.Text='Paramètres enregistrés. Apparence, formulaire et file conservés.'
        $script:CfgRestartRequired=$false
        Sync-PestoAppearanceControls
        Update-QueueButtons;Update-AddButton
        return $true
    }
    Invalidate-PestoConfigurationPlans
    $newConf = (@($newCfg.Conf))[0]
    $newDomain = "$($newConf.Domaine)".Trim()
    $newGUI = Convert-Value-TF $newCfg.Debug.GUI
    $newODM = Convert-Value-TF $newCfg.Debug.HorsDomaine
    $restartRequired = $changed # Le contexte métier est activé ensemble au prochain lancement.
    $script:CfgRestartRequired = $restartRequired

    # L’’apparence ne dépend jamais d’’une relecture de la configuration métier.

    if ($restartRequired) {
        Update-QueueButtons;Update-AddButton
        # Conserver le contexte en mémoire jusqu’’à fermeture. Le nouveau cfg est déjà sur disque.
        # Thème inchangé.
        $SetLblStatus.Text = 'Enregistré : paramètres métier à appliquer au prochain lancement.'
        Show-MsgInfo 'Paramètres métier enregistrés. Relancez Pesto pour charger un contexte cohérent ; vos plans restent conservés et doivent être revérifiés.' 'Redémarrage requis'
        return $true
    }

}


function Reload-CfgFromDisk {
    if(-not(Confirm-PestoDiscardSettings)){return}
    if($script:DirectBusy -or $script:PreflightRunning -or (Test-PestoAsyncOperationRunning 'DirectoryRefresh')){Show-MsgWarning 'Attendez la fin de l''opération ou du contrôle avant de modifier les paramètres métier.';return}
    if($script:JoinBusy -or (Test-PestoAsyncOperationRunning 'DomainJoin')){Show-MsgWarning 'Attendez la fin de la jonction avant de modifier la configuration.';return}
    if ($script:Running) { Show-MsgWarning 'Rechargement impossible pendant l''exécution de la file.'; return }
    if ($script:EDIT_ROW_INDEX -ge 0) { Show-MsgWarning 'Terminez ou annulez l''édition de la ligne avant de recharger la configuration.'; return }
    if (Apply-CfgHot) {
        Load-SettingsUI
        if ($script:CfgRestartRequired) {
            $SetLblStatus.Text = 'Relu depuis cfg.json — redémarrage requis pour le domaine/mode.'
        } else {
            $SetLblStatus.Text = "Relu depuis cfg.json à $(Get-Date -Format 'HH:mm:ss')."
        }
        Add-LogLine 'Paramètres relus et validés depuis cfg.json.' 'info'
    }
}

function Invoke-PestoConfigImport {
    param($Sender,$EventArgs)
    $ctx=$Sender.Tag;if(-not $ctx){return}
    $dialog=[Microsoft.Win32.OpenFileDialog]::new();$dialog.Filter='Configuration (*.json)|*.json';$dialog.Multiselect=$false
    if($dialog.ShowDialog($ctx.Window) -ne $true){return}
    try{
        $file=Get-Item -LiteralPath $dialog.FileName -Force -ErrorAction Stop
        if($file.Length -gt 1MB -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Configuration liée ou trop volumineuse.'}
        $text=Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 -ErrorAction Stop
        $cfg=$text|ConvertFrom-Json -ErrorAction Stop
        $ctx.Json.Text=$text
        $errors=@(Test-CfgValid $cfg)
        $ctx.Errors.Text=if($errors.Count){$errors -join "`r`n"}else{"Configuration importée et syntaxiquement valide. Vérifiez les valeurs, puis cliquez sur $(Get-PestoUxNom 'BtnValider'). Aucun accès AD réalisé."}
    }catch{$ctx.Errors.Text=$_.Exception.Message}
}

# Création locale de la configuration. La fenêtre ne contacte pas l'annuaire.
function Invoke-PestoConfigWizard {
    param($Sender,$EventArgs)
    $parent=$Sender.Tag
    [xml]$x=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Pesto · Préparer la configuration" Width="700" SizeToContent="Height" ResizeMode="NoResize" WindowStartupLocation="CenterOwner" Background="{DynamicResource BgWindow}" Foreground="{DynamicResource FgText}">
 <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel Margin="22">
 <TextBlock Text="Configurer votre environnement" FontSize="24" FontWeight="SemiBold"/>
 <TextBlock Text="Renseignez les chemins approuvés par votre organisation. Les valeurs sont vérifiées localement avant de les reporter dans le formulaire ; aucun appel AD et aucune sauvegarde automatique." TextWrapping="Wrap" Margin="0,8,0,16"/>
 <TextBlock Text="Domaine DNS"/><TextBox x:Name="Domain" Margin="0,4,0,10" MinHeight="34"/>
 <TextBlock Text="Préfixe de six chiffres"/><TextBox x:Name="Prefix" MaxLength="6" Margin="0,4,0,10" MinHeight="34"/>
 <TextBlock Text="OU racine des postes (DN exact)"/><TextBox x:Name="RootOU" Margin="0,4,0,10" MinHeight="34"/>
 <TextBlock Text="Nom de l'organisme"/><TextBox x:Name="Org" Margin="0,4,0,10" MinHeight="34"/>
 <TextBlock Text="OU contenant les sites de cet organisme (DN exact)"/><TextBox x:Name="SiteOU" Margin="0,4,0,10" MinHeight="34"/>
 <CheckBox x:Name="Direct" Content="Autoriser la jonction directement en production" Margin="0,3,0,10"/>
 <TextBlock Text="OU de préparation (obligatoire sans production directe)"/><TextBox x:Name="PreOU" Margin="0,4,0,10" MinHeight="34"/>
 <TextBlock Text="Code service de préparation (3 caractères)"/><TextBox x:Name="PreService" MaxLength="3" Margin="0,4,0,10" MinHeight="34"/>
 <TextBlock Text="Codes des sites : un motif = deux lettres par ligne"/><TextBox x:Name="Tags" AcceptsReturn="True" Height="100" VerticalScrollBarVisibility="Auto" Margin="0,4,0,10"/>
 <CheckBox x:Name="Hybrid" Content="Autoriser la préparation Entra avant renommage des postes hybrides" Margin="0,4,0,10"/>
 <CheckBox x:Name="ClearProtection" IsChecked="True" AutomationProperties.Name="Lever temporairement la protection contre la suppression pour déplacer un objet protégé" Margin="0,4,0,10"><TextBlock TextWrapping="Wrap" Text="Lever temporairement la protection contre la suppression pour déplacer un objet protégé (rétablie et relue ensuite)"/></CheckBox>
 <TextBlock x:Name="Error" TextWrapping="Wrap" Foreground="{DynamicResource ErrFg}" Margin="0,4,0,10"/>
 <StackPanel Orientation="Horizontal" HorizontalAlignment="Right"><Button x:Name="Apply" Content="Vérifier et reporter" Padding="16,9" Margin="0,0,8,0"/><Button Content="Annuler" IsCancel="True" Padding="16,9"/></StackPanel>
 </StackPanel></ScrollViewer>
</Window>
'@
    $w=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($x));$w.Resources=$parent.Window.Resources;$w.Owner=$parent.Window
    $w.MaxHeight=[Math]::Max(360,[Windows.SystemParameters]::WorkArea.Height-30)
    $w.MaxWidth=[Math]::Max(340,[Windows.SystemParameters]::WorkArea.Width-30)
    $ctx=@{Window=$w;Parent=$parent}
    $help=@{Domain='Domaine DNS réel, par exemple entreprise.local. La valeur de la session est une suggestion, pas une validation AD.';Prefix='Code du département sur six chiffres, par exemple 111301 ; jamais un nom de machine complet.';RootOU='DN approuvé de la racine où Pesto peut intervenir.';Org='Libellé affiché dans le choix de l’’organisme.';SiteOU='Conteneur des OU de sites, dans le même domaine.';Direct='Désactivé : la jonction utilise la zone de préparation configurée. Ne cochez que selon votre politique.';PreOU='DN exact de la zone de préparation ; ne sera pas créé automatiquement.';PreService='Trois lettres ou chiffres du service utilisé en préproduction.';Tags='Exemple : PREPROD=PR puis SIEGE-VA=VA. Aucun code de site n’’est attribué au hasard.';Hybrid='Décision explicite : AD seul ne déclenche jamais de retrait Entra.';ClearProtection='Coché (valeur par défaut du moteur) : la protection contre la suppression est levée le temps du déplacement, puis rétablie et relue. Décoché : le déplacement d’’un objet protégé est refusé (code 31).';Apply='Contrôler sans réseau puis reporter le JSON. La sauvegarde reste une action distincte dans la fenêtre précédente.'}
    foreach($n in $help.Keys){$ctx[$n]=$w.FindName($n);$ctx[$n].ToolTip=$help[$n];[Windows.Automation.AutomationProperties]::SetHelpText($ctx[$n],$help[$n]);[Windows.Automation.AutomationProperties]::SetName($ctx[$n],$help[$n])}
    $ctx.Error=$w.FindName('Error');$ctx.Domain.Text=[string]$env:USERDNSDOMAIN
    $ctx.Tags.Text='PREPROD=PR';$ctx.Apply.Tag=$ctx;$ctx.Apply.Add_Click([Windows.RoutedEventHandler]${function:Complete-PestoConfigWizard})
    [void]$w.ShowDialog()
}
function Complete-PestoConfigWizard {
    param($Sender,$EventArgs)
    $c=$Sender.Tag
    try{
        $tags=@(foreach($line in ($c.Tags.Text -split '\r?\n')){
            if(-not $line.Trim()){continue}
            $parts=$line.Split('=');if($parts.Count -ne 2){throw 'Chaque ligne de code site doit contenir un seul signe =.'}
            [pscustomobject]@{Site=$parts[0].Trim();Tag=$parts[1].Trim().ToUpperInvariant()}
        })
        $root=$c.RootOU.Text.Trim();$pre=$c.PreOU.Text.Trim()
        $bases=@([pscustomobject]@{Nom='ROOT';OU=$root})
        if($pre){$bases+=,[pscustomobject]@{Nom='PREPROD';OU=$pre}}
        $cfg=[pscustomobject]@{Schema=2;Configured=$true;DEBUG=[pscustomobject]@{Simulation=$false;HorsDomaine=$false;MauvaiseOU=$false;GUI=$false};CONF=@([pscustomobject]@{Domaine=$c.Domain.Text.Trim();Prefixe=$c.Prefix.Text.Trim();PreprodSite=$c.PreService.Text.Trim().ToUpperInvariant();DirectProd=[bool]$c.Direct.IsChecked;DarkMode=2;Buffer=10;OUScanNoms=$root;ClearProtectionOnMove=[bool]$c.ClearProtection.IsChecked;EntraPolicy=$(if($c.Hybrid.IsChecked){'HybridOnly'}else{'Disabled'})});OUBase=$bases;OUSite=@([pscustomobject]@{Nom=$c.Org.Text.Trim();OU=$c.SiteOU.Text.Trim()});TAGS=$tags}
        $errors=@(Test-CfgValid $cfg)
        if($errors.Count){$c.Error.Text=$errors -join "`n";return}
        $c.Parent.Json.Text=$cfg|ConvertTo-Json -Depth 8;$c.Parent.Errors.Text='Modèle vérifié localement. Les OU et les droits seront vérifiés à la connexion.'
        $c.Window.DialogResult=$true
    }catch{$c.Error.Text=$_.Exception.Message}
}

function Get-PestoSettingsSource {
    if($script:SettingsEditorConfig){return $script:SettingsEditorConfig}
    if($script:SettingsSourceConfig){return $script:SettingsSourceConfig}
    return $script:CFG
}
function Get-PestoConfigurationChanges {
    param($Before,$After)
    $left=ConvertTo-PestoCanonicalValue $Before;$right=ConvertTo-PestoCanonicalValue $After
    function Expand-PestoConfigFields {
        param($Value,[string]$Path,$Map)
        if($Value -is [Collections.IDictionary]){foreach($key in $Value.Keys){Expand-PestoConfigFields $Value[$key] ($Path+$(if($Path){'.'}else{''})+$key) $Map};return}
        if($Value -is [Collections.IEnumerable] -and $Value -isnot [string]){$i=0;foreach($item in $Value){Expand-PestoConfigFields $item ($Path+'['+$i+']') $Map;$i++};if(-not $i){$Map[$Path]='[]'};return}
        $Map[$Path]=ConvertTo-Json -InputObject $Value -Compress -Depth 20
    }
    $a=@{};$b=@{};Expand-PestoConfigFields $left '' $a;Expand-PestoConfigFields $right '' $b
    foreach($key in @(@($a.Keys)+@($b.Keys)|Sort-Object -Unique)){
        if($a.ContainsKey($key) -and $b.ContainsKey($key) -and $a[$key] -ceq $b[$key]){continue}
        [pscustomobject]@{Champ=$key;Avant=$(if($a.ContainsKey($key)){$a[$key]}else{'(absent)'});Apres=$(if($b.ContainsKey($key)){$b[$key]}else{'(retiré)'})}
    }
}
function Test-PestoSettingsDirty {
    if(-not $script:SettingsBaselineHash){return $false}
    try{return (Get-PestoStableHash (Build-CfgFromUI)) -cne $script:SettingsBaselineHash}catch{return $true}
}
function Invoke-PestoSettingsChanged {
    if($script:SuspendSet -or -not $script:SettingsBaselineHash){return}
    $SetLblStatus.Text='Modifications non enregistrées. Prévisualisez puis enregistrez.'
}
function Confirm-PestoDiscardSettings {
    if(-not(Test-PestoSettingsDirty)){return $true}
    return Confirm-YesNo -Msg 'Des paramètres ne sont pas enregistrés. Abandonner ces modifications ?' -Confirm $true
}
function Read-PestoConfigCandidate {
    param([string]$Path)
    Assert-PestoPlainPath $Path;$item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if($item.PSIsContainer -or $item.Length -gt 1MB){throw 'Configuration invalide ou trop volumineuse (1 Mio maximum).'}
    $config=Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop
    $errors=@(Test-CfgValid $config);if($errors.Count){throw ($errors -join "`r`n")}
    return $config
}
function Get-PestoConfigurationWarnings {
    param($Config)
    foreach($name in @('BPVerifNomAD','ForceADM')){if($Config.DEBUG -and (Convert-Value-TF $Config.DEBUG.$name)){"DEBUG.$name : réglage réservé, sans effet. Décochez-le pour éviter toute confusion."}}
    $conf=@($Config.CONF)[0]
    foreach($name in @('MoveRollbackOnRenameFail','AllowHybridRepair','DsregLeaveOnMove')){if($null -ne $conf.$name){"CONF.$name : réglage ancien conservé pour compatibilité ; EntraPolicy et les contrôles du parcours définissent le comportement."}}
    $tags=@{};foreach($entry in @($Config.TAGS)){$tag=([string]$entry.Tag).ToUpperInvariant();if($tags.ContainsKey($tag) -and [string]$entry.Site -notmatch 'PREPROD' -and [string]$tags[$tag] -notmatch 'PREPROD'){"TAGS : le code $tag est partagé par '$($tags[$tag])' et '$($entry.Site)'. Les propositions utilisent un espace de noms commun."}else{$tags[$tag]=[string]$entry.Site}}
}
function Get-PestoConfigurationFieldErrors {
    param([string[]]$Errors)
    $map=[ordered]@{
        SetTxtDomaine='Domaine|domaine DNS';SetTxtPrefixe='Préfixe';SetTxtPreprod='PreprodSite';SetTxtBuffer='Buffer';SetTxtOUScan='OUScanNoms'
        SetGridTags='TAGS|Tag ';SetGridOUBase='OUBase|OU ROOT|OU PREPROD';SetGridOUSite='OUSite|organisme'
        SetTxtCoordRoot='CoordinationRoot|dossier partagé';SetTxtReserveMinutes='NameReservationMinutes';SetTxtMaxBatch='MaxBatch'
        SetTxtMaxReaders='MaxReaders';SetTxtReadAttempts='ReadAttempts';SetTxtLogRetention='LogRetentionDays'
        SetTxtExcludedNames='ExcludedNames';SetTxtExcludedOUs='ExcludedOUs';SetTxtExcludedGroups='ExcludedGroupGuids'
        SetChkUnattendedJoin='UnattendedJoinEnabled'
    }
    foreach($name in $map.Keys){[pscustomobject]@{Name=$name;Message=(@($Errors|Where-Object{$_ -match $map[$name]}) -join "`n")}}
}
function Show-PestoConfigurationErrors {
    param([string[]]$Errors)
    if($SetLblStatus -and @($Errors).Count){$SetLblStatus.Text=($Errors -join ' ')}
    if(-not $script:PestoSettingFieldHelp){$script:PestoSettingFieldHelp=@{}}
    foreach($field in @(Get-PestoConfigurationFieldErrors $Errors)){
        $control=$Win.FindName($field.Name);if(-not $control){continue}
        if(-not $script:PestoSettingFieldHelp.ContainsKey($field.Name)){
            $script:PestoSettingFieldHelp[$field.Name]=[pscustomobject]@{ToolTip=$control.ToolTip;Help=[Windows.Automation.AutomationProperties]::GetHelpText($control);Border=$control.ReadLocalValue([Windows.Controls.Control]::BorderBrushProperty)}
        }
        $original=$script:PestoSettingFieldHelp[$field.Name];$label=$Win.FindName($field.Name+'Error')
        if($field.Message){
            $control.BorderBrush=$Win.Resources['ErrFg'];$control.ToolTip=$field.Message
            [Windows.Automation.AutomationProperties]::SetHelpText($control,$field.Message)
        }else{
            if($original.Border -eq [Windows.DependencyProperty]::UnsetValue){$control.ClearValue([Windows.Controls.Control]::BorderBrushProperty)}else{$control.SetValue([Windows.Controls.Control]::BorderBrushProperty,$original.Border)}
            $control.ToolTip=$original.ToolTip;[Windows.Automation.AutomationProperties]::SetHelpText($control,$original.Help)
        }
        if($label){$label.Text=$field.Message;$label.Visibility=if($field.Message){'Visible'}else{'Collapsed'}}
    }
    $script:PestoSettingsHaveErrors=(@($Errors).Count -gt 0)
}
function Invoke-PestoSettingsFieldLeave {
    param($Sender,$EventArgs)
    if($script:SuspendSet -or -not $script:SettingsBaselineHash){return}
    # Refresh existing errors after editing; never save or display a modal dialog here.
    # Compare on leaving a field, not on each keystroke (grid edits must not be committed mid-entry).
    try{
        if($script:PestoSettingsHaveErrors){Show-PestoConfigurationErrors @(Test-CfgValid (Build-CfgFromUI))}
        if(-not $script:PestoSettingsHaveErrors){
            $SetLblStatus.Text=if(Test-PestoSettingsDirty){'Modifications non enregistrées. Prévisualisez puis enregistrez.'}else{'Aucune modification par rapport aux paramètres chargés.'}
        }
    }catch{return}
}
function Invoke-PestoSettingsTool {
    param($Sender,$EventArgs)
    try{
        if($Sender.Name -eq 'SetBtnConfigAD'){Start-PestoConfigurationCheck;return}
        if($Sender.Name -eq 'SetBtnConfigPreview'){Show-PestoConfigurationDiff;return}
        if($Sender.Name -in @('SetBtnConfigImport','SetBtnConfigRestore')){
            if($script:PestoReadOnly){throw 'Consultation : modification de configuration interdite.'}
            if($script:Running -or $script:DirectBusy -or $script:JoinBusy -or $script:PreflightRunning){throw 'Attendez la fin du traitement avant de remplacer le formulaire.'}
            if(-not(Confirm-PestoDiscardSettings)){return}
            if($Sender.Name -eq 'SetBtnConfigRestore'){$path=$script:JsonFile+'.bak'}else{
                $dialog=[Microsoft.Win32.OpenFileDialog]::new();$dialog.Filter='Configuration (*.json)|*.json';if(-not $dialog.ShowDialog($Win)){return};$path=$dialog.FileName
            }
            $candidate=Read-PestoConfigCandidate $path
            Load-SettingsUI -Config $candidate -Draft
            $SetLblStatus.Text='Configuration validée et reportée dans le formulaire. Prévisualisez puis enregistrez pour l’’appliquer.'
            return
        }
        $candidate=Build-CfgFromUI;$errors=@(Test-CfgValid $candidate);Show-PestoConfigurationErrors $errors
        if($errors.Count){return}
        if($Sender.Name -eq 'SetBtnConfigExport'){
            $dialog=[Microsoft.Win32.SaveFileDialog]::new();$dialog.Filter='Configuration (*.json)|*.json';$dialog.FileName='Pesto-configuration.json'
            if($dialog.ShowDialog($Win)){Assert-PestoPlainPath $dialog.FileName;Write-PestoAtomicText -Path $dialog.FileName -Text ($candidate|ConvertTo-Json -Depth 20);$SetLblStatus.Text='Configuration validée exportée. Le fichier actif reste inchangé.'};return
        }
        $changes=@(Get-PestoConfigurationChanges $(if($script:SettingsSourceConfig){$script:SettingsSourceConfig}else{$script:CFG}) $candidate)
        $text=if($changes.Count){$changes|Format-Table -Wrap -AutoSize|Out-String -Width 160}else{'Aucun changement.'}
        $warnings=@(Get-PestoConfigurationWarnings $candidate);if($warnings.Count){$text+="`nPoints à examiner :`n"+($warnings -join "`n")}
        [void](Show-PestoPanel -Title 'Prévisualiser les paramètres' -Body $text -Monospace)
    }catch{$SetLblStatus.Text=$_.Exception.Message;Show-MsgError $_.Exception.Message}
}
function Invoke-PestoConfigurationCheckWorker {
    param($Request)
    . ([scriptblock]::Create($Request.Source));Import-PestoADModule $Request.ADModulePath
    $cfg=$Request.Config;$domain=[string]@($cfg.CONF)[0].Domaine
    $dc=Get-DomainController $domain;$adp=@{Server=$dc;ErrorAction='Stop'};if($Request.Credential){$adp.Credential=$Request.Credential}
    $checks=[Collections.Generic.List[object]]::new();$seen=@{}
    $paths=@(foreach($entry in @($cfg.OUBase)){[pscustomobject]@{Nom=$entry.Nom;OU=$entry.OU;Control='SetGridOUBase'}};foreach($entry in @($cfg.OUSite)){[pscustomobject]@{Nom=$entry.Nom;OU=$entry.OU;Control='SetGridOUSite'}};[pscustomobject]@{Nom='OUScanNoms';OU=[string]@($cfg.CONF)[0].OUScanNoms;Control='SetTxtOUScan'})
    foreach($entry in $paths){
        $dn=[string]$entry.OU;if(-not $dn -or $seen.ContainsKey($dn)){continue};$seen[$dn]=$true
        try{$ou=Get-ADOrganizationalUnit -Identity $dn -Properties ObjectGUID @adp;if(-not $ou.ObjectGUID){throw 'Identité OU absente.'};$checks.Add([pscustomobject]@{Champ=$entry.Nom;Control=$entry.Control;Etat='Lisible';Detail=$dn})}
        catch{$checks.Add([pscustomobject]@{Champ=$entry.Nom;Control=$entry.Control;Etat='À corriger';Detail=(Protect-PestoLogText $_.Exception.Message)})}
    }
    foreach($org in @($cfg.OUSite)){
        try{
            $sites=@(Get-ADOrganizationalUnit -SearchBase $org.OU -SearchScope OneLevel -Filter * -ResultSetSize 1001 @adp)
            if($sites.Count -ge 1001){throw 'Plus de 1 000 sites : contrôle incomplet. Réduisez le périmètre.'}
            foreach($site in $sites){
                if($checks.Count -gt 1500){throw 'Trop de sites pour ce contrôle ; réduisez le périmètre.'}
                $exact=@($cfg.TAGS|Where-Object{[string]$_.Site -ieq [string]$site.Name})
                $matchesForSite=if($exact.Count){$exact}else{@($cfg.TAGS|Where-Object{[Management.Automation.WildcardPattern]::new([string]$_.Site,'IgnoreCase').IsMatch([string]$site.Name)})}
                $codes=@($matchesForSite.Tag|Sort-Object -Unique)
                $checks.Add([pscustomobject]@{Champ=('Site '+$site.Name);Control='SetGridTags';Etat=$(if($codes.Count -eq 1){'Code résolu'}else{'À corriger'});Detail=$(if(-not $codes.Count){'Aucun code de site correspondant.'}elseif($codes.Count -gt 1){'Plusieurs codes applicables : '+($codes -join ', ')}else{$codes[0]})})
            }
        }catch{$checks.Add([pscustomobject]@{Champ=('Sites '+$org.Nom);Control='SetGridOUSite';Etat='Lecture incomplète';Detail=(Protect-PestoLogText $_.Exception.Message)})}
    }
    [pscustomobject]@{DC=$dc;Utc=[DateTime]::UtcNow.ToString('o');Checks=$checks.ToArray()}
}
function Start-PestoConfigurationCheck {
    if($script:GUI -or $script:SIM){Show-MsgInfo 'Ce contrôle de configuration AD est réservé au mode réel, en lecture seule.';return}
    if(Test-PestoAsyncOperationRunning 'ConfigReadCheck'){return}
    $candidate=Build-CfgFromUI;$errors=@(Test-CfgValid $candidate);Show-PestoConfigurationErrors $errors;if($errors.Count){return}
    if(-not $script:INDOMAIN -and -not $script:cred){Show-MsgInfo 'Connectez explicitement un compte AD avant ce contrôle.';return}
    $source=Get-PestoWorkerCoreSource
    foreach($name in @('Get-DomainController')){$source+="`nfunction $name {`n"+(Get-Item ('Function:\'+$name)).Definition+"`n}"}
    $request=[pscustomobject]@{Source=$source;Config=$candidate;Credential=$script:cred;ADModulePath=(Join-Path $BasePath 'ActiveDirectory.psd1')}
    $SetLblStatus.Text='Lecture du domaine, des OU et des codes de site…'
    [void](Start-PestoAsyncOperation -Name ConfigReadCheck -ScriptBlock ${function:Invoke-PestoConfigurationCheckWorker} -ArgumentList @($request) -TimeoutSec 120 `
        -OnSuccess {param($r,$c);$SetLblStatus.Text='Contrôle AD terminé en lecture seule.';Show-PestoConfigurationCheckResults $r} `
        -OnError {param($e,$c);$SetLblStatus.Text='Contrôle AD interrompu : '+(Protect-PestoLogText ([string]$e))})
}
function Initialize-PestoSettingsTools {
    foreach($name in @('SetBtnConfigPreview','SetBtnConfigExport','SetBtnConfigImport','SetBtnConfigRestore','SetBtnConfigAD')){
        $button=$Win.FindName($name);if($button){$button.Add_Click([Windows.RoutedEventHandler]${function:Invoke-PestoSettingsTool})}
    }
    foreach($name in @('SetTxtLogRetention','SetTxtDomaine','SetTxtADM','SetTxtPrefixe','SetTxtPreprod','SetTxtBuffer','SetTxtOUScan','SetTxtCoordRoot','SetTxtReserveMinutes','SetTxtMaxBatch','SetTxtMaxReaders','SetTxtReadAttempts','SetTxtExcludedNames','SetTxtExcludedOUs','SetTxtExcludedGroups')){
        $control=$Win.FindName($name);if($control){$control.Add_TextChanged({Invoke-PestoSettingsChanged});$control.Add_LostKeyboardFocus([Windows.Input.KeyboardFocusChangedEventHandler]${function:Invoke-PestoSettingsFieldLeave})}
    }
    foreach($name in @('SetChkAuditEventLog','SetChkIncidentMode','SetChkUnattendedOperations','SetChkClockSkew','SetChkUnattendedJoin','SetChkDirectProd','SetChkDsreg','SetChkSim','SetChkODM','SetChkWOU','SetChkBVA','SetChkGOD','SetChkGUI','SetChkCoordRequired','SetChkRandomName','SetChkReserveAD','SetChkPrecreated','SetChkPasswordFallback','SetChkClearProtection')){
        $control=$Win.FindName($name);if($control){$control.Add_Checked({Invoke-PestoSettingsChanged});$control.Add_Unchecked({Invoke-PestoSettingsChanged})}
    }
    foreach($control in @($SetGridTags,$SetGridOUBase,$SetGridOUSite)){if($control){$control.Add_CellEditEnding({Invoke-PestoSettingsChanged});$control.Add_RowEditEnding({Invoke-PestoSettingsChanged})}}
}
