#requires -Version 5.1
# Compatibilité : les clés de stockage/verrous GP sont stables ; ne pas les renommer ni les effacer. Voir docs/RENOMMAGE_PESTO.md (DEV).
# Apparence et favori de préparation sans secret. Le SID de départ ne confère aucun droit métier.

function Test-PestoAppearanceSid {
    param([string]$Sid)
    return ($Sid -match '^S-1-\d+(?:-\d+){1,14}$' -and $Sid.Length -le 184)
}

function Get-PestoAppearanceValue {
    param([ValidateSet('Theme','Layout','Preparation','Draft','Density','Reservations','Tables','Drafts','Views','Collections','NotifyBatch')][string]$Name)
    if($script:GUI -or $Demo){return $script:PestoAppearanceMemory[$Name]}
    if(-not (Test-PestoAppearanceSid $script:AppearanceOwnerSid)){return $null}
    $key=$null
    try {
        $key=[Microsoft.Win32.Registry]::Users.OpenSubKey($script:AppearanceOwnerSid+'\Software\GP\Appearance',$false)
        if(-not $key){return $null}
        $value=$key.GetValue($Name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        if($value -isnot [string] -or $value.Length -gt $(switch($Name){'Drafts'{262144};'Views'{65536};'Collections'{1048576};default{32768}})){return $null}
        return $value
    } finally {if($key){$key.Dispose()}}
}

function Set-PestoAppearanceValue {
    param([ValidateSet('Theme','Layout','Preparation','Draft','Density','Reservations','Tables','Drafts','Views','Collections','NotifyBatch')][string]$Name,[string]$Value)
    if($Value.Length -gt $(switch($Name){'Drafts'{262144};'Views'{65536};'Collections'{1048576};default{32768}})){throw 'Préférence trop volumineuse.'}
    if($Name -eq 'NotifyBatch' -and $Value -notin @('true','false')){throw 'Préférence de notification invalide.'}
    if($Name -eq 'Density' -and $Value -notin @('Compact','Comfort')){throw 'Densité non reconnue.'}
    if($Name -eq 'Theme' -and $Value -notin @('Light','Dark','System')){throw 'Thème non reconnu.'}
    if($script:GUI -or $Demo){$script:PestoAppearanceMemory[$Name]=$Value;return}
    if(-not (Test-PestoAppearanceSid $script:AppearanceOwnerSid)){throw 'Utilisateur de départ non identifié.'}
    $hive=$null;$key=$null
    try {
        # N'ouvre que la ruche existante : aucun chargement de profil ou changement d'ACL.
        $hive=[Microsoft.Win32.Registry]::Users.OpenSubKey($script:AppearanceOwnerSid,$true)
        if(-not $hive){throw 'La ruche de l''utilisateur de départ n''est pas disponible.'}
        $key=$hive.CreateSubKey('Software\GP\Appearance')
        if(-not $key){throw 'Préférences de présentation non accessibles en écriture.'}
        $key.SetValue($Name,$Value,[Microsoft.Win32.RegistryValueKind]::String)
        $key.Flush()
    } finally {if($key){$key.Dispose()};if($hive){$hive.Dispose()}}
}

function ConvertTo-PestoLayoutPreference {
    param($Value)
    $safe=[ordered]@{Schema=1}
    $bounds=@{WindowWidth=@(760,7680);WindowHeight=@(560,4320);SplitterLeft=@(280,2000);LogFontSize=@(10,22)}
    foreach($name in $bounds.Keys){
        $property=if($Value){$Value.PSObject.Properties[$name]}else{$null}
        if(-not $property){continue}
        $number=0.0
        if([double]::TryParse([string]$property.Value,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$number) -and
            -not [double]::IsNaN($number) -and -not [double]::IsInfinity($number)){
            $safe[$name]=[Math]::Min($bounds[$name][1],[Math]::Max($bounds[$name][0],$number))
        }
    }
    if($Value -and $Value.PSObject.Properties['UiZoomPercent']){$safe['UiZoomPercent']=ConvertTo-PestoUiZoomPercent $Value.UiZoomPercent}
    foreach($name in @('Maximized','NavigationCollapsed','HelpVisible','TechnicalColumns','AdvancedOptions','LogWrap')){
        $p=if($Value){$Value.PSObject.Properties[$name]}else{$null}
        if($p -and $p.Value -is [bool]){$safe[$name]=[bool]$p.Value}
    }
    return [pscustomobject]$safe
}

function ConvertTo-PestoUiZoomPercent {
    # Une valeur absolue, jamais un multiplicateur cumulatif ; données externes bornées.
    param($Value)
    $number=0.0
    if(-not [double]::TryParse([string]$Value,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$number) -or
       [double]::IsNaN($number) -or [double]::IsInfinity($number)){return 100}
    return [int][Math]::Min(150,[Math]::Max(80,[Math]::Round($number/10,0,[MidpointRounding]::AwayFromZero)*10))
}

function Get-PestoZoomViewportLayout {
    param([double]$Width,[double]$Height,$Percent=100)
    $scale=(ConvertTo-PestoUiZoomPercent $Percent)/100.0
    if([double]::IsNaN($Width) -or [double]::IsInfinity($Width) -or $Width -le 0){$Width=760}
    if([double]::IsNaN($Height) -or [double]::IsInfinity($Height) -or $Height -le 0){$Height=520}
    # Dimensions finies : les DataGrid gardent leur virtualisation et leurs propres scrollbars.
    [pscustomobject]@{Scale=$scale;Width=[Math]::Max(1.0,$Width/$scale);Height=[Math]::Max(520.0,$Height/$scale)}
}

function Get-PestoUiLayoutSize {
    if($Win){
        $root=$Win.FindName('SuiteRoot')
        if($root -and $root.Width -gt 0 -and $root.Height -gt 0 -and
           -not [double]::IsNaN($root.Width) -and -not [double]::IsNaN($root.Height)){
            return [pscustomobject]@{Width=[double]$root.Width;Height=[double]$root.Height}
        }
        return Get-PestoZoomViewportLayout -Width $Win.ActualWidth -Height $Win.ActualHeight -Percent $script:PestoUiZoomPercent
    }
    return Get-PestoZoomViewportLayout -Width 760 -Height 520 -Percent $script:PestoUiZoomPercent
}

function Update-PestoUiZoomLayout {
    if(-not $Win -or $script:PestoUiZoomUpdating){return}
    $root=$Win.FindName('SuiteRoot');$viewport=$Win.FindName('PestoZoomViewport')
    if(-not $root -or -not $viewport){return}
    $script:PestoUiZoomUpdating=$true
    try {
        $percent=ConvertTo-PestoUiZoomPercent $script:PestoUiZoomPercent
        $width=if($viewport.ViewportWidth -gt 0){$viewport.ViewportWidth}else{$viewport.ActualWidth}
        $height=if($viewport.ViewportHeight -gt 0){$viewport.ViewportHeight}else{$viewport.ActualHeight}
        $layout=Get-PestoZoomViewportLayout -Width $width -Height $height -Percent $percent
        if($root.LayoutTransform -isnot [Windows.Media.ScaleTransform]){$root.LayoutTransform=[Windows.Media.ScaleTransform]::new($layout.Scale,$layout.Scale)}
        elseif($root.LayoutTransform.ScaleX -ne $layout.Scale -or $root.LayoutTransform.ScaleY -ne $layout.Scale){$root.LayoutTransform.ScaleX=$layout.Scale;$root.LayoutTransform.ScaleY=$layout.Scale}
        if([double]::IsNaN($root.Width) -or [Math]::Abs($root.Width-$layout.Width) -gt 0.25){$root.Width=$layout.Width}
        if([double]::IsNaN($root.Height) -or [Math]::Abs($root.Height-$layout.Height) -gt 0.25){$root.Height=$layout.Height}
        $minus=$Win.FindName('PestoZoomOut');$reset=$Win.FindName('PestoZoomReset');$plus=$Win.FindName('PestoZoomIn')
        if($minus){$minus.IsEnabled=($percent -gt 80)}
        if($plus){$plus.IsEnabled=($percent -lt 150)}
        if($reset){
            $reset.Content=('{0} %' -f $percent);$reset.IsEnabled=$true
            [Windows.Automation.AutomationProperties]::SetName($reset,('Zoom {0} pour cent. Rétablir 100 pour cent.' -f $percent))
        }
    } finally {$script:PestoUiZoomUpdating=$false}
}

function Set-PestoUiZoom {
    param($Percent=100,[switch]$Persist)
    $script:PestoUiZoomPercent=ConvertTo-PestoUiZoomPercent $Percent
    Update-PestoUiZoomLayout
    if($script:PestoUxReady){Update-PestoUxLayout}
    if($Persist){Save-Prefs}
}

function Invoke-PestoUiZoomClick {
    param($Sender,$EventArgs)
    $current=ConvertTo-PestoUiZoomPercent $script:PestoUiZoomPercent
    switch([string]$Sender.Name){
        'PestoZoomOut' {Set-PestoUiZoom -Percent ($current-10) -Persist}
        'PestoZoomReset' {Set-PestoUiZoom -Percent 100 -Persist}
        'PestoZoomIn' {Set-PestoUiZoom -Percent ($current+10) -Persist}
    }
}

function Invoke-PestoUiZoomViewportChanged {
    param($Sender,$EventArgs)
    if($script:PestoUiZoomUpdating){return}
    # Ignorer les événements de défilement des pages imbriquées et les seuls changements d'offset.
    if($EventArgs.PSObject.Properties['ViewportWidthChange']){
        if($EventArgs.OriginalSource -ne $Sender){return}
        if($EventArgs.ViewportWidthChange -eq 0 -and $EventArgs.ViewportHeightChange -eq 0){return}
    }
    Update-PestoUiZoomLayout
    if($script:PestoUxReady){Update-PestoUxLayout}
}

function Initialize-PestoUiZoom {
    if($script:PestoUiZoomReady -or -not $Win){return}
    foreach($name in @('PestoZoomOut','PestoZoomReset','PestoZoomIn')){
        $button=$Win.FindName($name);if(-not $button){throw ('Commande de zoom absente : '+$name)}
        $button.Add_Click([Windows.RoutedEventHandler]${function:Invoke-PestoUiZoomClick})
    }
    $viewport=$Win.FindName('PestoZoomViewport');if(-not $viewport){throw 'Zone de zoom absente.'}
    $viewport.Add_SizeChanged([Windows.SizeChangedEventHandler]${function:Invoke-PestoUiZoomViewportChanged})
    $viewport.Add_ScrollChanged([Windows.Controls.ScrollChangedEventHandler]${function:Invoke-PestoUiZoomViewportChanged})
    $script:PestoUiZoomReady=$true
    Set-PestoUiZoom -Percent $script:PestoUiZoomPercent
}

function Get-PestoSystemContrastColors {
    <# Couleurs système Windows quand le contraste élevé est actif ; $null sinon ou en cas de doute. #>
    try {
        if(-not [Windows.SystemParameters]::HighContrast){return $null}
        $colors=@{}
        foreach($pair in @(@('Window','WindowColor'),@('WindowText','WindowTextColor'),@('Highlight','HighlightColor'),@('HighlightText','HighlightTextColor'),@('ButtonFace','ControlColor'),@('ButtonText','ControlTextColor'),@('HotTrack','HotTrackColor'))){
            $c=[Windows.SystemColors]::($pair[1])
            $colors[$pair[0]]='#{0:X2}{1:X2}{2:X2}' -f $c.R,$c.G,$c.B
        }
        return $colors
    } catch {return $null}
}

function ConvertTo-PestoHighContrastPalette {
    <# Chaque couleur de Pesto prend un rôle système : texte sur fond de fenêtre, texte de sélection sur sélection,
       texte de bouton sur bouton. Une couleur sans rôle ou une couleur système absente refuse la palette.
       X5 : les anneaux d'état, transparents en clair et sombre, prennent ici la couleur de sélection (texte de
       sélection quand l'élément est aussi sélectionné), seul repère hors couleur du texte. #>
    param([string[]]$Keys,[hashtable]$System)
    $roles=@{
        BgWindow='Window';BgSidebar='Window';BgCard='Window';BgInput='Window';BgInputRO='ButtonFace';FgText='WindowText';FgMuted='WindowText'
        FgAccent='HotTrack';ClrBorder='WindowText';BtnBg='ButtonFace';BtnFg='ButtonText';BtnBorder='ButtonText';GridBg='Window';GridAltBg='Window'
        GridHeaderBg='ButtonFace';GridLine='WindowText';RowSelBg='Highlight';RowSelFg='HighlightText';LogBg='Window';AddBg='Highlight';RunBg='Highlight'
        RunFg='HighlightText';BadgeBg='Window';BadgeFg='WindowText';FieldOk='Window';FieldKo='Window';OkFg='WindowText';ErrFg='WindowText';WarnFg='WindowText'
        HeadFg='HotTrack';ChipOkBg='Window';ChipOkFg='WindowText';ChipWarnBg='Window';ChipWarnFg='WindowText';ChipInfoBg='Window';ChipInfoFg='WindowText'
        ChipNeutralBg='Window';ChipNeutralFg='WindowText';SectionFg='HotTrack';Divider='WindowText';Shadow='WindowText';RowHoverBg='Window';AccentSoft='Window'
        FocusRing='Highlight';HcStateRing='Highlight';HcSelStateRing='HighlightText';TipBg='Window';TipFg='WindowText';TipBorder='WindowText'
    }
    $palette=@{}
    foreach($key in $Keys){
        if(-not $roles.ContainsKey($key)){throw ('Couleur sans rôle de contraste élevé : '+$key)}
        $value=[string]$System[$roles[$key]]
        if($value -notmatch '^#[0-9A-F]{6}$'){throw ('Couleur système absente : '+$roles[$key])}
        $palette[$key]=$value
    }
    return $palette
}

function Resolve-PestoTheme {
    param([string]$Mode)
    if($Mode -in @('Dark','Light')){return $Mode}
    # Suivre Windows : le contraste élevé l'emporte ; au moindre doute, thème habituel.
    if($script:Themes -and $script:Themes.ContainsKey('Light')){
        $system=Get-PestoSystemContrastColors
        if($system){
            try {$script:Themes['HighContrast']=ConvertTo-PestoHighContrastPalette -Keys @($script:Themes['Light'].Keys) -System $system;return 'HighContrast'}
            catch {Write-Log 'Contraste élevé Windows non appliqué : thème habituel utilisé.' 'WARN' $_ 'appearance'}
        }
    }
    $key=$null
    try {
        if(Test-PestoAppearanceSid $script:AppearanceOwnerSid){
            $key=[Microsoft.Win32.Registry]::Users.OpenSubKey($script:AppearanceOwnerSid+'\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize',$false)
            if($key -and [int]$key.GetValue('AppsUseLightTheme',1) -eq 0){return 'Dark'}
        }
    } catch {Write-Log 'Lecture du thème Windows indisponible : clair utilisé.' 'WARN' $null 'appearance'}
    finally {if($key){$key.Dispose()}}
    return 'Light'
}

function Initialize-PestoAppearance {
    param([string]$OwnerSid,$Config)
    $script:PestoAppearanceMemory=@{}
    $script:ThemeSaved=$null
    if(-not (Test-PestoAppearanceSid $OwnerSid)){
        try {$id=[Security.Principal.WindowsIdentity]::GetCurrent();try{$OwnerSid=$id.User.Value}finally{$id.Dispose()}}catch{$OwnerSid=''}
    }
    $script:AppearanceOwnerSid=$OwnerSid
    $script:ThemeMode=switch([string](@($Config.Conf)[0].DarkMode)){'0'{'Light'};'1'{'Dark'};default{'System'}}
    $script:LayoutPreference=[pscustomobject]@{Schema=1}
    try {
        $theme=Get-PestoAppearanceValue 'Theme'
        if($theme -in @('Light','Dark','System')){$script:ThemeMode=$theme;$script:ThemeSaved=$true}
        else {
            # Lecture de compatibilité bornée ; aucune écriture automatique au rendu.
            $legacy=Get-PrefsFile
            if($legacy -and (Test-Path -LiteralPath $legacy -PathType Leaf) -and (Get-Item -LiteralPath $legacy).Length -le 65536){
                $old=Get-Content -LiteralPath $legacy -Raw -Encoding UTF8 | ConvertFrom-Json
                if($old.Theme -in @('Light','Dark')){$script:ThemeMode=[string]$old.Theme}
                $script:LayoutPreference=ConvertTo-PestoLayoutPreference $old
            }
        }
        $layout=Get-PestoAppearanceValue 'Layout'
        if($layout){$script:LayoutPreference=ConvertTo-PestoLayoutPreference ($layout|ConvertFrom-Json)}
    } catch {Write-Log 'Préférences illisibles : valeurs de présentation par défaut utilisées.' 'WARN' $_ 'appearance'}
    $script:CurrentTheme=Resolve-PestoTheme $script:ThemeMode
    $script:NavigationCollapsed=[bool]$script:LayoutPreference.NavigationCollapsed
    $script:HelpVisible=[bool]$script:LayoutPreference.HelpVisible
    $script:LogFontSize=if($script:LayoutPreference.LogFontSize){[double]$script:LayoutPreference.LogFontSize}else{12}
    $script:LogWrap=if($script:LayoutPreference.PSObject.Properties['LogWrap']){[bool]$script:LayoutPreference.LogWrap}else{$true}
    $script:LogFollow=$true
    $script:PestoUiZoomPercent=ConvertTo-PestoUiZoomPercent $script:LayoutPreference.UiZoomPercent
}

function Set-PestoThemeMode {
    param([ValidateSet('Light','Dark','System')][string]$Mode)
    $script:ThemeMode=$Mode
    Set-Theme (Resolve-PestoTheme $Mode)
    try {
        Set-PestoAppearanceValue -Name 'Theme' -Value $Mode
        $script:ThemeSaved=$true
    } catch {
        $script:ThemeSaved=$false
        Add-LogLine 'Le thème est appliqué, mais sa sauvegarde a échoué.' 'warn'
        if($SetLblStatus){$SetLblStatus.Text='Thème appliqué, non enregistré. Consultez le journal.'}
        Write-Log 'Enregistrement du thème impossible.' 'WARN' $_ 'appearance'
    }
    Sync-PestoAppearanceControls
}

function Sync-PestoAppearanceControls {
    if(-not $SetCmbDarkMode){return}
    $script:AppearanceSync=$true
    try {
        $SetCmbDarkMode.DisplayMemberPath='Label';$SetCmbDarkMode.SelectedValuePath='Key'
        if($SetCmbDarkMode.Items.Count -ne 3 -or $SetCmbDarkMode.Items[0] -is [string]){
            $SetCmbDarkMode.Items.Clear()
            foreach($pair in @(@('Light','Clair'),@('Dark','Sombre'),@('System','Suivre Windows'))){
                [void]$SetCmbDarkMode.Items.Add([pscustomobject]@{Key=$pair[0];Label=$pair[1]})
            }
        }
        $SetCmbDarkMode.SelectedValue=$script:ThemeMode
    } finally {$script:AppearanceSync=$false}
    if($BtnTheme){$BtnTheme.ToolTip='Apparence actuelle : '+(@{Light='Clair';Dark='Sombre';System='Suivre Windows'}[$script:ThemeMode])+'. Cliquer pour passer au '+$(if($script:CurrentTheme -eq 'Dark'){'clair'}else{'sombre'})+'. Enregistrement immédiat pour l''utilisateur de départ.'}
}

function Invoke-PestoThemeToggle {
    param($Sender,$EventArgs)
    Set-PestoThemeMode $(if($script:CurrentTheme -eq 'Dark'){'Light'}else{'Dark'})
}

function Invoke-PestoAppearanceChoice {
    param($Sender,$EventArgs)
    if($script:AppearanceSync -or $script:SuspendSet -or -not $Sender.SelectedValue){return}
    Set-PestoThemeMode ([string]$Sender.SelectedValue)
}

function Save-Prefs {
    if(-not $Win){return}
    try {
        $bounds=if($Win.WindowState -eq [Windows.WindowState]::Normal){[pscustomobject]@{Width=$Win.Width;Height=$Win.Height}}else{$Win.RestoreBounds}
        $values=[pscustomobject]@{
            WindowWidth=[double]$bounds.Width;WindowHeight=[double]$bounds.Height
            Maximized=($Win.WindowState -eq [Windows.WindowState]::Maximized)
            NavigationCollapsed=[bool]$script:NavigationCollapsed;HelpVisible=[bool]$script:HelpVisible
            TechnicalColumns=[bool]$ChkTechnicalColumns.IsChecked;AdvancedOptions=[bool]$AdvancedOptions.IsExpanded
            LogFontSize=[double]$script:LogFontSize;LogWrap=[bool]$script:LogWrap
            UiZoomPercent=ConvertTo-PestoUiZoomPercent $script:PestoUiZoomPercent
        }
        $safe=ConvertTo-PestoLayoutPreference $values
        Set-PestoAppearanceValue -Name 'Layout' -Value ($safe|ConvertTo-Json -Compress)
        $script:LayoutPreference=$safe
    } catch {Set-PestoPersistenceWarning ('Disposition non enregistrée : '+$_.Exception.Message);Write-Log 'Disposition non enregistrée. Aucune préférence de thème modifiée.' 'WARN' $_ 'appearance'}
}

function Test-PestoStartupMaximized {
    param($Preference,[double]$DesignWidth,[double]$DesignHeight,[double]$WorkWidth,[double]$WorkHeight)
    if($Preference.Maximized -eq $true){return $true}
    $width=if($Preference.WindowWidth){[double]$Preference.WindowWidth}else{$DesignWidth}
    $height=if($Preference.WindowHeight){[double]$Preference.WindowHeight}else{$DesignHeight}
    return ($width -gt $WorkWidth -or $height -gt $WorkHeight)
}

function Load-Prefs {
    try {
        $p=$script:LayoutPreference
        $wa=[Windows.SystemParameters]::WorkArea
        # La fenêtre doit rester utilisable sur un petit écran/RDP. Pas de position absolue restaurée.
        $Win.MinWidth=[Math]::Min(760,[Math]::Max(320,$wa.Width-24))
        $Win.MinHeight=[Math]::Min(560,[Math]::Max(300,$wa.Height-24))
        $desiredWidth=if($p.WindowWidth){[double]$p.WindowWidth}else{[double]$Win.Width}
        $Win.Width=[Math]::Min($wa.Width-24,[Math]::Max($Win.MinWidth,$desiredWidth))
        $desiredHeight=if($p.WindowHeight){[double]$p.WindowHeight}else{[double]$Win.Height}
        $Win.Height=[Math]::Min($wa.Height-24,[Math]::Max($Win.MinHeight,$desiredHeight))
        $Win.WindowStartupLocation=[Windows.WindowStartupLocation]::CenterScreen
        if(Test-PestoStartupMaximized -Preference $p -DesignWidth $script:PestoDesignWidth -DesignHeight $script:PestoDesignHeight -WorkWidth $wa.Width -WorkHeight $wa.Height){$Win.WindowState=[Windows.WindowState]::Maximized}
        $ChkTechnicalColumns.IsChecked=[bool]$p.TechnicalColumns
        $AdvancedOptions.IsExpanded=[bool]$p.AdvancedOptions
        Set-PestoUxTechnicalColumns ([bool]$p.TechnicalColumns)
        Sync-PestoAppearanceControls
    } catch {Write-Log 'Disposition ignorée : valeurs invalides.' 'WARN' $_ 'appearance'}
}

function Invoke-PestoAppearancePulse {
    param($Sender,$EventArgs)
    if($script:ThemeMode -eq 'System'){
        $theme=Resolve-PestoTheme 'System'
        if($theme -ne $script:CurrentTheme){Set-Theme $theme}
    }
    if($script:PestoLoginUi){
        $caps=$script:PestoLoginUi.Window.FindName('LoginCaps')
        if($caps){$caps.Visibility=if([Windows.Input.Keyboard]::IsKeyToggled([Windows.Input.Key]::CapsLock)){'Visible'}else{'Collapsed'}}
    }
}
