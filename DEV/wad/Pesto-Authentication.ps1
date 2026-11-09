#requires -Version 5.1
# Définitions uniquement, chargées dans la portée du moteur.


function Get-PestoIdentityChangeReason {
    param([string]$ExpectedGuid,[string]$ActualGuid,[string]$ExpectedOU,[string]$ActualOU)
    if($ExpectedGuid) {
        $a=[Guid]::Empty;$b=[Guid]::Empty
        if(-not [Guid]::TryParse($ExpectedGuid,[ref]$a) -or $a -eq [Guid]::Empty){return 'GUID préparé invalide : relisez le poste.'}
        if(-not [Guid]::TryParse($ActualGuid,[ref]$b) -or $b -eq [Guid]::Empty -or $a -ne $b){return 'L''objet AD ne correspond plus au GUID préparé : aucune mutation autorisée.'}
    }
    if($ExpectedOU -and (Test-PestoOUPath $ExpectedOU)) {
        if(-not(Test-PestoOUPath $ActualOU)){return 'OU source réelle illisible : aucune mutation autorisée.'}
        $a=@(Split-PestoDistinguishedName $ExpectedOU) -join ','
        $b=@(Split-PestoDistinguishedName $ActualOU) -join ','
        if($a -ine $b){return "Le poste a changé d'OU depuis la préparation. Attendue : '$ExpectedOU'. Observée : '$ActualOU'. Relisez le poste et recréez la ligne."}
    }
    return ''
}

function Get-PestoWindowsAuthIdentity {
    # Lit le jeton du processus, jamais le nom du compte de la session de bureau.
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    try {
        $name=[string]$identity.Name
        $authority=($name -split '\\',2)[0]
        $domainUser=$identity.IsAuthenticated -and -not $identity.IsSystem -and
            $name.Contains('\') -and $authority -ine $env:COMPUTERNAME -and
            $authority -notin @('NT AUTHORITY','NT SERVICE','BUILTIN','Window Manager','Font Driver Host')
        return [pscustomobject]@{
            Name=$name;Sid=[string]$identity.User.Value;IsDomainUser=[bool]$domainUser
            IsAdministrator=([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        }
    } finally { $identity.Dispose() }
}

function Get-PestoDomainIdentityWarning {
    <# Avertissement à poser AVANT l'appel AD. En mode « Compte Windows » (aucun credential
       explicite), la cmdlet part avec l'identité du processus. Un compte local ou système
       n'établit pas à lui seul la cause d'un refus ADWS : réseau et droits restent à vérifier.
       Retourne '' quand il n'y a rien à signaler. #>
    param([object]$Identity,[switch]$HasExplicitCredential,[bool]$InDomain=$true)
    if($HasExplicitCredential){return ''}
    if(-not $InDomain){return ''}
    if($Identity -and [bool]$Identity.IsDomainUser){return ''}
    if(-not $Identity -or $null -eq $Identity.IsDomainUser){return 'L''identité Windows de Pesto est indéterminée. Vérifiez le compte choisi dans l''UAC et la connexion au domaine.'}
    return 'Le compte qui exécute Pesto est local ou système. La connexion intégrée peut ne pas disposer des droits AD attendus. Choisissez "Autre compte AD", ou relancez Pesto sous un compte du domaine.'
}

function Add-PestoDomainIdentityCause {
    <# Le worker de snapshot ne remonte que son flux d'erreur : un Write-Warning y
       reste avalé par l'hôte. Quand le premier contact ADWS a déjà échoué, on nomme
       la cause dans l'exception au lieu de laisser le texte muet « impossible de
       contacter le serveur ». Sans cause identifiée, l'erreur d'origine est rendue
       inchangée : ce point n'invente jamais un échec. #>
    param($ErrorRecord,[object]$Identity,[switch]$HasExplicitCredential)
    # En mode explicite le jeton Windows n'est pas l'identité envoyée à ADWS.
    # Une identité absente/illisible ne prouve pas non plus une cause locale.
    if($HasExplicitCredential -or -not $Identity -or $null -eq $Identity.IsDomainUser){return $ErrorRecord}
    $msg = Get-PestoDomainIdentityWarning -Identity $Identity -HasExplicitCredential:$HasExplicitCredential
    if (-not $msg) { return $ErrorRecord }
    $detail = if ($ErrorRecord -is [Management.Automation.ErrorRecord]) { $ErrorRecord.Exception.Message } else { [string]$ErrorRecord }
    $inner = if ($ErrorRecord -is [Management.Automation.ErrorRecord]) { $ErrorRecord.Exception } elseif ($ErrorRecord -is [Exception]) { $ErrorRecord } else { $null }
    return [Exception]::new('Échec de la connexion AD. ' + $msg + ' Détail : ' + $detail, $inner)
}

function Get-PestoDirectoryIdentitySource {
    # Le worker de snapshot court dans un runspace neuf : il ne reçoit que son propre texte
    # et la source du résolveur AD, jamais les fonctions du moteur. Celles qui nomment la cause
    # d'un refus ADWS doivent donc voyager avec la requête ; sans elles l'appel lève « terme non
    # reconnu » et l'écran affiche une panne imaginaire à la place du vrai refus du contrôleur.
    $builder=[Text.StringBuilder]::new()
    foreach($name in @('Get-PestoWindowsAuthIdentity','Get-PestoDomainIdentityWarning','Add-PestoDomainIdentityCause')){
        $definition=(Get-Command $name -CommandType Function -ErrorAction Stop).Definition
        [void]$builder.AppendLine("function $name {`r`n$definition`r`n}")
    }
    return $builder.ToString()
}

function Get-PestoExplicitCredentialRequirement {
    param([bool]$InDomain,[object[]]$Rows,[string]$LocalComputerName)
    if(-not $InDomain){return 'La jonction au domaine nécessite un compte AD explicite.'}
    foreach($row in $Rows){
        if([bool]$row.Renommer -and [string]$row.Nom_du_PC -ine $LocalComputerName){
            return 'Le renommage d''un autre PC nécessite un compte AD explicite dans ce moteur RPC, contrairement au renommage du PC local.'
        }
    }
    return ''
}

function Set-PestoAuthenticatedSnapshot {
    param($Snapshot,[Management.Automation.PSCredential]$Credential,[string]$Mode,[string]$User)
    if($null -eq $Snapshot -or [string]::IsNullOrWhiteSpace([string]$Snapshot.DC) -or $Snapshot.Complete -isnot [bool] -or -not $Snapshot.Complete){
        throw 'La validation AD n''a pas renvoyé de contrôleur de domaine.'
    }
    if(([string]$Snapshot.Domain).TrimEnd('.') -ine $script:DOMAINE.TrimEnd('.')){
        throw 'Le domaine retourné par AD ne correspond pas au domaine configuré.'
    }
    if($Mode -eq 'Windows' -and ([string]::IsNullOrWhiteSpace($User) -or [string]$Snapshot.Identity -ine $User)){
        throw 'Le compte utilisé par le worker AD ne correspond pas au compte Windows élevé.'
    }
    $script:DC=[string]$Snapshot.DC
    $script:Sites=$Snapshot.Sites;$script:SiteMetadata=@($Snapshot.SiteMetadata)
    $script:InventoryLoaded=[bool]$Snapshot.FullInventory
    $script:InventoryUtc=[string]$Snapshot.CollectedUtc
    $script:Computers=@($Snapshot.Root)
    $script:ComputersNoms=@($Snapshot.Names)
    $script:LocalComputerSnapshot=$Snapshot.LocalComputer
    if([string]$Snapshot.LocalPCType -in @('Portable','Fixe','Virtuel')){$script:CachedPCType=[string]$Snapshot.LocalPCType}
    Update-PestoComputerIndex
    $script:cred=$Credential
    $script:AuthMode=$Mode
    $script:AuthUser=$User
}

function Complete-PestoWindowsConnectionError {
    param($ErrorObject,[string]$Message='',$Context)
    $state=$script:PestoWindowsConnection
    if(-not $state -or $state.Result -ne 'Pending'){return}
    if($Context -and $Context.Id -ne $state.Id){return}
    $state.Busy=$false
    if(-not $Message){try{$Message=[string]$ErrorObject.Exception.Message}catch{}}
    if(-not $Message){$Message='La connexion AD n''a pas pu être établie.'}
    $state.Progress.Visibility='Collapsed'
    $state.Status.Text="Accès AD non établi.`n$Message`n`nVérifiez le compte choisi dans l'UAC, le réseau et le domaine configuré. Aucun autre mot de passe n'est demandé automatiquement."
    $state.Retry.Visibility='Visible';$state.Other.Visibility='Visible'
    $state.Retry.IsEnabled=$true;$state.Other.IsEnabled=$true
    Write-Log ('Connexion Windows intégrée non établie pour '+$state.User+'. '+$Message) 'ERROR' $null 'auth'
}

function Complete-PestoWindowsConnectionSuccess {
    param($Snapshot,$Context)
    $state=$script:PestoWindowsConnection
    if(-not $state -or $state.Result -ne 'Pending' -or -not $state.Busy){return}
    if(-not $Context -or $Context.Id -ne $state.Id){return}
    try {
        Set-PestoAuthenticatedSnapshot -Snapshot $Snapshot -Mode 'Windows' -User $Context.User
        $state.Busy=$false;$state.Result='Connected';$script:LoginOk=$true
        Write-Log ('Connexion Windows intégrée confirmée : '+$script:AuthUser+' ; aucun credential Pesto.') 'INFO' $null 'auth'
        try{Show-PestoStartupWindow;Set-PestoStartupStage -Stage 'Préparation de la session' -Detail ('Compte Windows : '+$script:AuthUser)}catch{}
        $state.Window.DialogResult=$true
    } catch { Complete-PestoWindowsConnectionError -ErrorObject $_ -Context $Context }
}

function Start-PestoWindowsConnection {
    $state=$script:PestoWindowsConnection
    if(-not $state -or $state.Result -ne 'Pending' -or $state.Busy){return}
    if(Test-PestoAsyncOperationRunning 'WindowsAuth'){return}
    try {
        $identity=Get-PestoWindowsAuthIdentity
        $state.User=[string]$identity.Name;$state.Identity.Text=$state.User
        if(-not $script:INDOMAIN){throw 'La connexion intégrée est réservée au poste membre du domaine cible.'}
        if(-not $identity.IsAdministrator -and -not $script:PestoReadOnly){throw 'Le jeton administrateur n''est pas actif. Relancez Pesto.exe.'}
        if(-not $identity.IsDomainUser){throw 'Le compte choisi dans l''UAC est local ou système. Relancez Pesto avec un compte du domaine autorisé sur ce PC.'}
        $state.Busy=$true;$state.Progress.Visibility='Visible'
        $state.Status.Text='Connexion au domaine et chargement des sites…'
        $state.Retry.IsEnabled=$false;$state.Other.IsEnabled=$false
        $context=[pscustomobject]@{Id=$state.Id;User=$state.User}
        $request=New-PestoDirectorySnapshotRequest -IncludeLocalHardware
        $started=Start-PestoAsyncOperation -Name 'WindowsAuth' -ScriptBlock $script:PestoDirectorySnapshotWorker -ArgumentList @($request) -TimeoutSec 180 -CallbackContext $context `
            -OnSuccess {param($snapshot,$ctx) Complete-PestoWindowsConnectionSuccess -Snapshot $snapshot -Context $ctx} `
            -OnError {param($errorObject,$ctx) Complete-PestoWindowsConnectionError -ErrorObject $errorObject -Context $ctx}
        if(-not $started){Complete-PestoWindowsConnectionError -Message 'Le worker de connexion n''a pas pu démarrer.' -Context $context}
    } catch { Complete-PestoWindowsConnectionError -ErrorObject $_ }
}

function Show-PestoWindowsConnectionWindow {
    # Fenêtre d'attente automatique : aucun champ de compte ou de mot de passe.
    [xml]$wxaml=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Pesto 1.0 | Connexion Windows" Topmost="True" ShowInTaskbar="True" Width="500" SizeToContent="Height" ResizeMode="NoResize" WindowStartupLocation="CenterScreen" Background="{DynamicResource BgWindow}" FontFamily="Segoe UI" FontSize="13" UseLayoutRounding="True">
 <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
  <Border Margin="16" Padding="22" CornerRadius="16" Background="{DynamicResource BgCard}" BorderBrush="{DynamicResource ClrBorder}" BorderThickness="1">
   <StackPanel>
    <TextBlock Text="Ouverture de Pesto" FontSize="22" FontWeight="SemiBold" Foreground="{DynamicResource FgText}"/>
    <TextBlock Text="Avec le compte Windows autorisé par l'UAC" TextWrapping="Wrap" Margin="0,6,0,10" Foreground="{DynamicResource FgMuted}"/>
    <Border Background="{DynamicResource AccentSoft}" CornerRadius="8" Padding="10"><TextBlock x:Name="WindowsIdentity" TextWrapping="Wrap" Foreground="{DynamicResource FgAccent}" ToolTip="Identité du processus élevé. Ce n'est pas nécessairement le compte de la session de bureau." AutomationProperties.HelpText="Identité du processus élevé. Ce n'est pas nécessairement le compte de la session de bureau." ToolTipService.ShowOnDisabled="True"/></Border>
    <TextBlock x:Name="WindowsStatus" Text="Préparation de la connexion automatique…" Margin="0,14,0,12" TextWrapping="Wrap" Foreground="{DynamicResource FgText}"/>
    <ProgressBar x:Name="WindowsProgress" IsIndeterminate="True" Height="6" Margin="0,0,0,12" ToolTip="Lecture AD en cours. Annuler arrête l'ouverture de Pesto, sans modifier les postes." AutomationProperties.HelpText="Lecture AD en cours. Annuler arrête l'ouverture de Pesto, sans modifier les postes." ToolTipService.ShowOnDisabled="True"/>
    <WrapPanel HorizontalAlignment="Right">
     <Button x:Name="WindowsRetry" Content="Réessayer" Visibility="Collapsed" Margin="0,4,6,0" Padding="12,8" MinHeight="38" ToolTip="Réessayer avec le même compte Windows, sans demander de mot de passe." AutomationProperties.HelpText="Réessayer avec le même compte Windows, sans demander de mot de passe." ToolTipService.ShowOnDisabled="True"/>
     <Button x:Name="WindowsOther" Content="Autre compte AD…" Visibility="Collapsed" Margin="0,4,6,0" Padding="12,8" MinHeight="38" ToolTip="Choix explicite : ouvrir le formulaire Pesto pour utiliser un autre compte AD." AutomationProperties.HelpText="Choix explicite : ouvrir le formulaire Pesto pour utiliser un autre compte AD." ToolTipService.ShowOnDisabled="True"/>
     <Button x:Name="WindowsCancel" Content="Annuler" IsCancel="True" Margin="0,4,0,0" Padding="12,8" MinHeight="38" ToolTip="Fermer Pesto sans lancer d'opération." AutomationProperties.HelpText="Fermer Pesto sans lancer d'opération." ToolTipService.ShowOnDisabled="True"/>
    </WrapPanel>
   </StackPanel>
  </Border>
 </ScrollViewer>
</Window>
'@
    $window=[Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $wxaml))
    $window.Resources=$Win.Resources
    Set-PestoLoginWindowBounds -Window $window
    Set-WindowIcon $window
    $state=[pscustomobject]@{
        Id=[guid]::NewGuid().ToString('N');Window=$window;Result='Pending';Busy=$false;Started=$false;User=''
        Identity=$window.FindName('WindowsIdentity');Status=$window.FindName('WindowsStatus');Progress=$window.FindName('WindowsProgress')
        Retry=$window.FindName('WindowsRetry');Other=$window.FindName('WindowsOther');Cancel=$window.FindName('WindowsCancel')
    }
    $script:PestoWindowsConnection=$state
    $script:cred=$null;$script:AuthMode=$null;$script:AuthUser=$null;$script:LoginOk=$false
    $state.Retry.Add_Click({Start-PestoWindowsConnection})
    $state.Other.Add_Click({
        $s=$script:PestoWindowsConnection
        if($s -and -not $s.Busy){$s.Result='Explicit';$s.Window.Close()}
    })
    $state.Cancel.Add_Click({
        $s=$script:PestoWindowsConnection
        if($s){$s.Result='Cancelled';$s.Window.Close()}
    })
    $window.Add_ContentRendered({
        $s=$script:PestoWindowsConnection
        if($s -and -not $s.Started){
            $s.Started=$true
            # Une seule activation a l'ouverture ; Topmost conserve la visibilite du dialogue.
            try{[void]$s.Window.Activate();[void]$s.Cancel.Focus()}catch{}
            Start-PestoWindowsConnection
        }
    })
    $window.Add_Closing({
        $s=$script:PestoWindowsConnection
        if($s -and $s.Result -eq 'Pending'){$s.Result='Cancelled'}
        if(Test-PestoAsyncOperationRunning 'WindowsAuth'){Stop-PestoAsyncOperation 'WindowsAuth'}
    })
    try {
        [void]$window.ShowDialog()
        return [string]$state.Result
    } finally {
        if(Test-PestoAsyncOperationRunning 'WindowsAuth'){Stop-PestoAsyncOperation 'WindowsAuth'}
        $script:PestoWindowsConnection=$null
    }
}

function Get-PestoLoginPreferencePath {
    # Même isolation par profil Windows et configuration que les autres préférences.
    return (Join-Path (Get-PestoStateDirectory) 'login.json')
}

function ConvertFrom-PestoLoginPreference {
    param([AllowNull()]$Preference,[string]$Domain)
    $empty=[pscustomobject]@{RememberUser=$false;UserName=''}
    if($null -eq $Preference -or $Preference.Schema -ne 1){return $empty}
    if($Preference.Domain -isnot [string] -or $Preference.Domain -ine $Domain){return $empty}
    if($Preference.RememberUser -isnot [bool] -or -not $Preference.RememberUser){return $empty}
    if($Preference.UserName -isnot [string]){return $empty}
    $name=$Preference.UserName.Trim()
    if(-not $name -or $name.Length -gt 256 -or $name -match '[\x00-\x1f\x7f]'){return $empty}
    return [pscustomobject]@{RememberUser=$true;UserName=$name}
}

function Get-PestoLoginPreference {
    $empty=[pscustomobject]@{RememberUser=$false;UserName=''}
    try {
        $path=Get-PestoLoginPreferencePath
        if(-not [IO.File]::Exists($path)){return $empty}
        $info=Get-Item -LiteralPath $path -ErrorAction Stop
        if($info.Length -gt 16384 -or ($info.Attributes -band [IO.FileAttributes]::ReparsePoint)){return $empty}
        $data=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8) | ConvertFrom-Json -ErrorAction Stop
        return (ConvertFrom-PestoLoginPreference -Preference $data -Domain $script:DOMAINE)
    } catch { return $empty }
}

function Save-PestoLoginPreference {
    param([bool]$RememberUser,[AllowEmptyString()][string]$UserName='')
    $path=Get-PestoLoginPreferencePath
    if(-not $RememberUser){
        # Décocher oublie immédiatement l'identifiant, même si la connexion est annulée.
        if([IO.File]::Exists($path)){[IO.File]::Delete($path)}
        return
    }
    $data=[ordered]@{Schema=1;Domain=[string]$script:DOMAINE;RememberUser=$true;UserName=$UserName.Trim()}
    $checked=ConvertFrom-PestoLoginPreference -Preference ([pscustomobject]$data) -Domain $script:DOMAINE
    if(-not $checked.RememberUser){throw 'Identifiant non mémorisable.'}
    # Liste blanche : ni mot de passe, ni SecureString, ni PSCredential dans ce fichier.
    Write-PestoAtomicText -Path $path -Text ($data | ConvertTo-Json -Compress)
}

function Set-PestoLoginFeedback {
    param([string]$Message='', [switch]$ErrorMessage)
    $ui=$script:PestoLoginUi
    if($null -eq $ui){return}
    $ui.Feedback.Visibility=if($Message){'Visible'}else{'Collapsed'}
    if($ErrorMessage){
        $ui.Error.Text=$Message;$ui.Error.Visibility='Visible'
        $ui.Stage.Text='';$ui.Stage.Visibility='Collapsed'
    } else {
        $ui.Error.Text='';$ui.Error.Visibility='Collapsed'
        $ui.Stage.Text=$Message
        $ui.Stage.Visibility=if($Message){'Visible'}else{'Collapsed'}
    }
}

function Invoke-PestoLoginForget {
    if(-not $script:PestoLoginUi -or $script:PestoLoginUi.Remember.IsChecked){return}
    try { Save-PestoLoginPreference -RememberUser $false }
    catch { Set-PestoLoginFeedback -ErrorMessage -Message "Impossible d'oublier l'identifiant enregistré : $($_.Exception.Message)" }
}

function Set-PestoLoginWindowBounds {
    param([Windows.Window]$Window)
    $work=[Windows.SystemParameters]::WorkArea
    # Limites calculées en unités WPF : pas de hauteur de 700 ni de redimensionnement utilisateur.
    $Window.MaxHeight=[Math]::Max(1,[double]$work.Height-24)
    $Window.MaxWidth=[Math]::Max(1,[double]$work.Width-24)
    $Window.ResizeMode=[Windows.ResizeMode]::NoResize
    $Window.WindowState=[Windows.WindowState]::Normal
}

function Set-PestoLoginBusy {
    param([bool]$Busy,[string]$Stage='')
    $ui=$script:PestoLoginUi
    if($null -eq $ui){return}
    foreach($control in @($ui.Connect,$ui.Windows,$ui.Login,$ui.Password,$ui.Remember)){
        $control.IsEnabled=-not $Busy
    }
    $ui.Progress.Visibility=if($Busy){'Visible'}else{'Collapsed'}
    Set-PestoLoginFeedback -Message $Stage
}

function Complete-PestoLoginError {
    param([AllowNull()]$ErrorObject,[string]$Message='')
    $ui=$script:PestoLoginUi;$state=$script:PestoLoginState
    if($null -eq $ui -or $null -eq $state){return}
    $msg=$Message
    if(-not $msg){
        try{$msg=[string]$ErrorObject.Exception.Message}catch{}
        if(-not $msg){try{$msg=[string]$ErrorObject.Message}catch{}}
        if(-not $msg){$msg='Erreur de connexion Active Directory.'}
    }
    try{Write-Log "Connexion AD échouée (mode $($state.PendingMode), compte '$($state.PendingUser)')." 'ERROR' $ErrorObject 'init'}catch{}
    $state.PendingCredential=$null
    Set-PestoLoginBusy $false 'Connexion non établie.'
    Set-PestoLoginFeedback -ErrorMessage -Message "Échec de connexion : $msg"
    try{if($ui.Login.Text){[void]$ui.Password.Focus()}else{[void]$ui.Login.Focus()}}catch{}
}

function Complete-PestoLoginSuccess {
    param([AllowNull()]$Snapshot)
    $ui=$script:PestoLoginUi;$state=$script:PestoLoginState
    if($null -eq $ui -or $null -eq $state){return}
    try {
        Set-PestoAuthenticatedSnapshot -Snapshot $Snapshot -Credential $state.PendingCredential -Mode ([string]$state.PendingMode) -User ([string]$state.PendingUser)
        $state.PendingCredential=$null
        try{$ui.Password.Clear()}catch{}
        if($state.PendingMode -eq 'Explicit'){
            try { Save-PestoLoginPreference -RememberUser ([bool]$ui.Remember.IsChecked) -UserName ([string]$ui.Login.Text) }
            catch {
                # L'échec d'une préférence ne doit pas invalider une authentification réussie.
                try { Write-Log "Connexion validée ; préférence d'identifiant non enregistrée." 'WARN' $_ 'login' } catch {}
            }
        }
        $state.LoginOk=$true
        Set-PestoLoginBusy $false 'Connecté.'
        # Transition sans écran vide : le loading apparaît avant la fermeture du login.
        try {
            Show-PestoStartupWindow
            Set-PestoStartupStage -Stage 'Préparation de la session' -Detail 'Connexion validée.'
        } catch {}
        try{$ui.Window.DialogResult=$true}catch{}
        $ui.Window.Close()
    } catch {
        Complete-PestoLoginError -ErrorObject $_
    }
}

function Start-PestoLoginAttempt {
    param([switch]$UseCurrentCredentials)
    $ui=$script:PestoLoginUi;$state=$script:PestoLoginState
    if($null -eq $ui -or $null -eq $state){return}
    if(Test-PestoAsyncOperationRunning 'LoginAuth'){return}

    try {
        Set-PestoLoginFeedback
        $cred=$null
        $mode=if($UseCurrentCredentials){'Windows'}else{'Explicit'}
        $user=if($UseCurrentCredentials){[string]$state.WindowsIdentity}else{[string]$ui.Login.Text.Trim()}

        if(-not $UseCurrentCredentials){
            if([string]::IsNullOrWhiteSpace($user)){
                Set-PestoLoginFeedback -ErrorMessage -Message "L'identifiant est requis.";[void]$ui.Login.Focus();return
            }
            $securePassword=$ui.Password.SecurePassword
            if($null -eq $securePassword -or $securePassword.Length -eq 0){
                Set-PestoLoginFeedback -ErrorMessage -Message 'Le mot de passe est requis.';[void]$ui.Password.Focus();return
            }
            # Comme ADCC : on conserve tel quel DOMAIN\user ou user@domaine ;
            # seul un identifiant court reçoit le suffixe DNS du domaine cible.
            if($user -notmatch '@' -and $user -notmatch '\\'){$user="$user@$($script:DOMAINE)"}
            $cred=New-Object System.Management.Automation.PSCredential($user,$securePassword)
        } elseif([string]::IsNullOrWhiteSpace($user)){
            Set-PestoLoginFeedback -ErrorMessage -Message 'La session Windows courante est indisponible.';return
        }

        $state.PendingCredential=$cred
        $state.PendingMode=$mode
        $state.PendingUser=$user
        Set-PestoLoginBusy $true $(if($UseCurrentCredentials){"Validation de la session Windows $user…"}else{"Validation de $user…"})

        $request=New-PestoDirectorySnapshotRequest -Credential $cred -IncludeLocalHardware
        $onSuccess={param($snapshot) Complete-PestoLoginSuccess -Snapshot $snapshot}
        $onError={param($errorObject) Complete-PestoLoginError -ErrorObject $errorObject}
        $started=Start-PestoAsyncOperation -Name 'LoginAuth' -ScriptBlock $script:PestoDirectorySnapshotWorker -ArgumentList @($request) -OnSuccess $onSuccess -OnError $onError -TimeoutSec 180
        if(-not $started){Complete-PestoLoginError -Message 'Impossible de démarrer la validation Active Directory.'}
    } catch {
        Complete-PestoLoginError -ErrorObject $_
    }
}

function Show-LoginWindow {
    if(-not $script:GUI -and -not $script:PestoReadOnly -and -not(Test-PestoIsAdministrator)){
        Show-MsgError 'Connexion non ouverte : Pesto doit être élevé avant le login. Relancez Pesto.exe.'
        return $false
    }
    $t=$script:Themes[$script:CurrentTheme]
    $horsDomaine=-not $script:INDOMAIN
    $bannerText=if($horsDomaine){'Compte de domaine requis'}else{'Compte administrateur requis'}
    $bannerTextXml=[Security.SecurityElement]::Escape($bannerText)

    [xml]$lxaml=@"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Pesto 1.0 · Connexion" Topmost="True" Width="460" SizeToContent="Height" ResizeMode="NoResize" WindowStyle="SingleBorderWindow" WindowState="Normal" WindowStartupLocation="CenterScreen" Background="{DynamicResource BgWindow}" Foreground="{DynamicResource FgText}" FontFamily="Segoe UI" FontSize="13" ShowInTaskbar="True" UseLayoutRounding="True" TextOptions.TextFormattingMode="Display">
 <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" CanContentScroll="False" Focusable="False">
  <Border Margin="14,16,14,16" Padding="20,22,20,18" Background="{DynamicResource BgCard}" CornerRadius="17" BorderBrush="{DynamicResource ClrBorder}" BorderThickness="1">
   <StackPanel>
    <Grid Margin="0,0,0,20">
     <Grid.ColumnDefinitions><ColumnDefinition Width="42"/><ColumnDefinition Width="12"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
     <Button x:Name="LoginTheme" Grid.Column="3" Content="◐" Padding="8,4" Margin="6,0,0,0" ToolTip="Changer le thème de toutes les fenêtres et mémoriser le choix." ToolTipService.ShowOnDisabled="True" ToolTipService.InitialShowDelay="450" ToolTipService.ShowDuration="30000" AutomationProperties.HelpText="Changer le thème de toutes les fenêtres et mémoriser le choix."/>
     <Border Width="42" Height="42" CornerRadius="12" Background="{DynamicResource AddBg}" VerticalAlignment="Center"><TextBlock Text="P" FontSize="20" FontWeight="SemiBold" Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
     <StackPanel Grid.Column="2"><TextBlock Text="Connexion à Pesto" FontSize="22" FontWeight="SemiBold" Foreground="{DynamicResource FgText}"/><TextBlock Text="$bannerTextXml" FontSize="12" Foreground="{DynamicResource FgMuted}" Margin="0,3,0,0" TextWrapping="Wrap"/></StackPanel>
    </Grid>
    <TextBlock Text="Compte Windows" Foreground="{DynamicResource FgText}" Margin="0,0,0,6"/>
    <TextBox x:Name="TxtUser" MinHeight="44" Padding="12,8" FontSize="14" VerticalContentAlignment="Center" TabIndex="0" MaxLength="256" AutomationProperties.Name="Compte Windows du domaine" AutomationProperties.AutomationId="TxtUser" AutomationProperties.HelpText="Identifiant court, DOMAINE\identifiant ou identifiant@domaine." ToolTip="Compte autorisé dans le domaine ciblé : identifiant, DOMAINE\identifiant ou identifiant@domaine. Le compte local Windows ne remplace pas un compte de domaine." ToolTipService.ShowOnDisabled="True" ToolTipService.InitialShowDelay="450" ToolTipService.ShowDuration="30000"/>
    <TextBlock Text="Mot de passe" Foreground="{DynamicResource FgText}" Margin="0,14,0,6"/>
    <PasswordBox x:Name="TxtPwd" MinHeight="44" Padding="12,8" FontSize="14" VerticalContentAlignment="Center" TabIndex="1" AutomationProperties.Name="Mot de passe" AutomationProperties.AutomationId="TxtPwd" AutomationProperties.HelpText="Mot de passe du compte de domaine. Jamais enregistré dans les préférences." ToolTip="Mot de passe du compte ci-dessus. Il reste en mémoire pour les actions autorisées et n'est pas enregistré dans les préférences." ToolTipService.ShowOnDisabled="True" ToolTipService.InitialShowDelay="450" ToolTipService.ShowDuration="30000"/>
    <TextBlock x:Name="LoginCaps" Text="Verr. Maj est activé." Foreground="{DynamicResource WarnFg}" Visibility="Collapsed" Margin="0,8,0,0" TextWrapping="Wrap"/>
    <CheckBox x:Name="ChkRememberUser" Content="Mémoriser uniquement l'identifiant" IsChecked="False" Margin="0,12,0,0" TabIndex="2" AutomationProperties.AutomationId="ChkRememberUser" AutomationProperties.HelpText="Après connexion réussie, mémoriser seulement le nom de compte pour cette configuration et ce profil Windows. Décocher efface la préférence." ToolTip="Mémorise seulement l'identifiant après une connexion réussie, dans le profil Windows qui exécute Pesto. Décocher l'efface immédiatement. Aucun mot de passe n'est sauvegardé." ToolTipService.ShowOnDisabled="True" ToolTipService.InitialShowDelay="450" ToolTipService.ShowDuration="30000"/>
    <StackPanel x:Name="LoginFeedback" Visibility="Collapsed" Margin="0,10,0,0">
     <TextBlock x:Name="LblErr" Text="" Foreground="{DynamicResource ErrFg}" FontSize="12" Visibility="Collapsed" TextWrapping="Wrap" AutomationProperties.AutomationId="LblErr" ToolTip="L'erreur de connexion est affichée ici. Aucune opération sur les postes n'a été lancée." ToolTipService.ShowOnDisabled="True" AutomationProperties.HelpText="L'erreur de connexion est affichée ici. Aucune opération sur les postes n'a été lancée."/>
     <TextBlock x:Name="LblStep" Text="" Foreground="{DynamicResource FgMuted}" FontSize="12" Visibility="Collapsed" TextWrapping="Wrap" AutomationProperties.AutomationId="LblStep" ToolTip="Étape de validation du compte." ToolTipService.ShowOnDisabled="True" AutomationProperties.HelpText="Étape de validation du compte."/>
     <ProgressBar x:Name="PbLogin" Height="4" Margin="0,7,0,0" IsIndeterminate="True" Visibility="Collapsed" Foreground="{DynamicResource FgAccent}" Background="{DynamicResource BgInputRO}" BorderThickness="0" AutomationProperties.AutomationId="PbLogin" ToolTip="Connexion en cours. Vous pouvez encore annuler." ToolTipService.ShowOnDisabled="True" AutomationProperties.HelpText="Connexion en cours. Vous pouvez encore annuler."/>
    </StackPanel>
    <Grid Margin="0,18,0,0">
     <Grid.ColumnDefinitions><ColumnDefinition Width="94"/><ColumnDefinition Width="10"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
     <Button x:Name="BtnCancel" Content="Annuler" IsCancel="True" MinHeight="40" Padding="12,8" TabIndex="4" Background="{DynamicResource BgInputRO}" BorderThickness="0" AutomationProperties.AutomationId="BtnCancel" ToolTip="Annuler la connexion et fermer Pesto. Raccourci : Échap." ToolTipService.ShowOnDisabled="True" AutomationProperties.HelpText="Annuler la connexion et fermer Pesto. Raccourci : Échap."/>
     <Button x:Name="BtnOk" Grid.Column="2" Content="Se connecter" IsDefault="True" MinHeight="40" Padding="12,8" TabIndex="3" Background="{DynamicResource AddBg}" Foreground="White" BorderBrush="{DynamicResource AddBg}" AutomationProperties.AutomationId="BtnOk" ToolTip="Valider ce compte et ouvrir Pesto. Le compte reste disponible pour les actions de cette session. Raccourci : Entrée." ToolTipService.ShowOnDisabled="True" AutomationProperties.HelpText="Valider ce compte et ouvrir Pesto. Le compte reste disponible pour les actions de cette session. Raccourci : Entrée."/>
    </Grid>
    <Button x:Name="BtnWindows" Content="Utiliser mon compte Windows" Margin="0,8,0,0" MinHeight="36" Padding="12,7" TabIndex="5" Background="{DynamicResource BgInputRO}" BorderThickness="0" AutomationProperties.AutomationId="BtnWindows" AutomationProperties.HelpText="Session Windows élevée : lectures AD, déplacements autorisés et renommage du PC local. La jonction et le renommage distant exigent un compte explicite." ToolTip="Utiliser la session Windows élevée pour les lectures AD, les déplacements autorisés et le renommage local. Pour joindre au domaine ou renommer un autre PC, utilisez un compte explicite." ToolTipService.ShowOnDisabled="True"/>
    <TextBlock Text="Le mot de passe n'est jamais enregistré." Foreground="{DynamicResource FgMuted}" FontSize="11" TextAlignment="Center" Margin="0,12,0,0" TextWrapping="Wrap"/>
   </StackPanel>
  </Border>
 </ScrollViewer>
</Window>
"@
    try{$window=[Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $lxaml))}
    catch{Show-MsgError "Impossible de créer la fenêtre de connexion :`n$($_.Exception.Message)" 'Pesto — Connexion';return $false}
    $window.Resources=$Win.Resources
    Set-PestoLoginWindowBounds -Window $window
    $window.Add_StateChanged({param($sender,$eventArgs)
        if($sender.WindowState -eq [Windows.WindowState]::Maximized){$sender.WindowState=[Windows.WindowState]::Normal}
    })
    Set-WindowIcon $window

    $ui=[pscustomobject]@{
        Window=$window;Login=$window.FindName('TxtUser');Password=$window.FindName('TxtPwd');Error=$window.FindName('LblErr');Stage=$window.FindName('LblStep');Progress=$window.FindName('PbLogin');
        Connect=$window.FindName('BtnOk');Windows=$window.FindName('BtnWindows');Cancel=$window.FindName('BtnCancel');Remember=$window.FindName('ChkRememberUser');Feedback=$window.FindName('LoginFeedback')
    }
    foreach($prop in @('Login','Password','Error','Stage','Progress','Connect','Windows','Cancel','Remember','Feedback')){
        if($null -eq $ui.$prop){Show-MsgError "Fenêtre de connexion incomplète : contrôle '$prop' introuvable." 'Pesto — Connexion';return $false}
    }

    $winIdentity=try{[Security.Principal.WindowsIdentity]::GetCurrent().Name}catch{"$env:USERDOMAIN\$env:USERNAME"}
    $ui.Windows.ToolTip="Session élevée : $winIdentity. Lecture AD, déplacements autorisés et renommage local. Jonction et renommage distant : compte explicite."
    $preference=Get-PestoLoginPreference
    $ui.Remember.IsChecked=[bool]$preference.RememberUser
    if($preference.RememberUser){$ui.Login.Text=[string]$preference.UserName}
    $window.FindName('LoginTheme').Add_Click([Windows.RoutedEventHandler]${function:Invoke-PestoThemeToggle})
    $script:PestoLoginUi=$ui
    $script:PestoLoginState=[pscustomobject]@{LoginOk=$false;WindowsIdentity=$winIdentity;PendingCredential=$null;PendingMode='';PendingUser='';InitialFocusSet=$false}
    $script:LoginOk=$false;$script:AuthMode=$null;$script:AuthUser=$null

    $ui.Remember.Add_Unchecked({Invoke-PestoLoginForget})
    $ui.Connect.Add_Click({Start-PestoLoginAttempt})
    $ui.Windows.Add_Click({Start-PestoLoginAttempt -UseCurrentCredentials})
    $ui.Cancel.Add_Click({
        if(Test-PestoAsyncOperationRunning 'LoginAuth'){Stop-PestoAsyncOperation 'LoginAuth'}
        if($script:PestoLoginState){$script:PestoLoginState.LoginOk=$false}
        try{$script:PestoLoginUi.Window.DialogResult=$false}catch{}
        try{$script:PestoLoginUi.Window.Close()}catch{}
    })
    $window.Add_Closing({
        if(Test-PestoAsyncOperationRunning 'LoginAuth'){Stop-PestoAsyncOperation 'LoginAuth'}
        if($script:PestoLoginUi){$script:PestoLoginUi.Password.Clear()}
        if($script:PestoLoginState){$script:PestoLoginState.PendingCredential=$null}
    })
    $window.Add_ContentRendered({
        $s=$script:PestoLoginState;$ui=$script:PestoLoginUi
        if($s -and $ui -and -not $s.InitialFocusSet){
            $s.InitialFocusSet=$true
            # Le dialogue reste au-dessus, sans reprendre le focus apres le choix de l'utilisateur.
            try{[void]$ui.Window.Activate();if($ui.Login.Text){[void]$ui.Password.Focus()}else{[void]$ui.Login.Focus()}}catch{}
        }
    })

    [void]$window.ShowDialog()
    $ok=if($script:PestoLoginState){[bool]$script:PestoLoginState.LoginOk}else{$false}
    $script:LoginOk=$ok
    $script:PestoLoginUi=$null;$script:PestoLoginState=$null
    return $ok
}
