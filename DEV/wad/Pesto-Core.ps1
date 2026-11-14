#requires -version 5.1
# Compatibilité : les clés de stockage/verrous GP sont stables ; ne pas les renommer ni les effacer. Voir docs/RENOMMAGE_PESTO.md (DEV).
[CmdletBinding()]
param([switch]$Consult,[switch]$Demo,[string]$ConfigPath,[switch]$AskCredential,[switch]$DemoJoin,[string]$AppearanceOwnerSid)
if($DemoJoin){$Demo=$true}
$script:PestoReadOnly=$Consult.IsPresent
if($Consult){$env:PESTO_READONLY_SESSION='1'}else{Remove-Item Env:PESTO_READONLY_SESSION -ErrorAction SilentlyContinue}
###############################################################################
#  Pesto   (interface WPF, Active Directory)
#  Jonction au domaine / Renommage / Déplacement / File d'actions
#
#  Historique 17.0 (RC21) - parcours unitaires et composants harmonisés :
#    - Préparation Entra conditionnelle avant le premier renommage, avec contrôle du résultat.
#    - Déplacements seuls et jonctions au domaine inchangés.
#    - Moteur AD entièrement découplé de l'interface (aucun appel UI dans le
#      moteur : les fonctions renvoient un résultat { ExitCode, ExitMsg }).
#    - Interface WPF moderne, thème clair / sombre commutable à chaud (soleil / lune).
#    - File d'actions (DataGrid) + journal couleur + barre de statut.
#    - Schéma cfg.json conservé, avec validation plus stricte et nouvelles options explicites.
#
#  MODES (cfg.json > Debug / Conf) :
#    $GUI  : interface seule, aucun appel AD réel (test visuel / logique UI)
#    $SIM  : simulation, affiche les commandes au lieu d'écrire dans l'AD
#    $ODM  : force le mode hors-domaine (GUI/SIM uniquement en version PROD)
#    $BVA  : clé legacy cfg.json conservée pour compatibilité (sans effet)
#    $WOU  : force "mauvaise OU" (GUI/SIM uniquement en version PROD)
#    $GOD  : clé legacy cfg.json conservée pour compatibilité (sans effet)
#    $PRD  : jonction directe vers l'OU cible (sinon -> PREPROD)
#
#  CODES DE SORTIE (renvoyés par les fonctions Go*) :
#    10 AddDomain OK   11 AddDomain KO   13 Compte AD déjà existant
#    20 Rename OK      21 Rename KO      69 Nom déjà pris (rename seul)
#    30 Move OK        31 Move KO        32 Protection non rétablie / arrêt sécurité
#    33 Déjà dans l'OU cible
#    Règle RC4 : renommage + site différent => déplacement auto ; même site => aucun déplacement.
#    40 Reboot demandé 41 Reboot KO (journal seul, ne change pas le statut AD)
#    77 Move+Rename OK 88 Nom déjà pris (rename+move)
#    89 Renommage réussi, déplacement à reprendre   91 Réservé compatibilité
#    96 Précontrôle local en échec / action non lancée
#    97 État de mutation indéterminé / arrêt sécurité de la file
#    98 Échec technique worker                       99 Poste introuvable / erreur inattendue
###############################################################################

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'
$script:Pesto_VERSION = '1.0'

if ($env:OS -ne 'Windows_NT') { throw "Pesto nécessite Windows PowerShell 5.1 x64 sous Windows." }
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    throw "Pesto nécessite un thread STA. Lancez powershell.exe -STA ou compilez Pesto en STA."
}
# Un appel direct du moteur passe aussi par le lanceur avant toute interface.
# Le parametre Demo impose ensuite GUI=True ; il ne permet aucune mutation.
if (-not $Demo -and -not $Consult) {
    $startupIdentity=[Security.Principal.WindowsIdentity]::GetCurrent()
    try { $startupAdmin=([Security.Principal.WindowsPrincipal]::new($startupIdentity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) }
    finally { $startupIdentity.Dispose() }
    if (-not $startupAdmin) {
        $startupLauncher=Join-Path $PSScriptRoot 'Pesto-Startup.ps1'
        if (-not (Test-Path -LiteralPath $startupLauncher -PathType Leaf)) { throw 'Pesto-Startup.ps1 absent de wad. Utilisez le pack complet ; le login ne peut pas commencer sans elevation.' }
        $startupParams=@{AskCredential=$AskCredential.IsPresent}
        if($AppearanceOwnerSid){$startupParams.AppearanceOwnerSid=$AppearanceOwnerSid}
        if ($PSBoundParameters.ContainsKey('ConfigPath')) {
            if ([string]::IsNullOrWhiteSpace($ConfigPath)) { throw 'ConfigPath vide.' }
            $startupParams.ConfigPath=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ConfigPath)
        }
        & $startupLauncher @startupParams
        exit $LASTEXITCODE
    }
}
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xml
. (Join-Path $PSScriptRoot 'Pesto-Integrity.ps1')
[void](Test-PestoPackage -Root (Split-Path -Parent $PSScriptRoot))

# Cible de production volontairement étroite : Windows PowerShell 5.1 x64.
# #requires -version 5.1 accepterait aussi PowerShell 7 ; on le refuse ici pour
# éviter les différences .NET/WPF/RSAT/PS2EXE et les comportements non validés.
if ($PSVersionTable.PSEdition -ne 'Desktop' -or [int]$PSVersionTable.PSVersion.Major -ne 5) {
    try { [System.Windows.MessageBox]::Show('Pesto nécessite Windows PowerShell 5.1 (powershell.exe), pas PowerShell 7/pwsh.', 'Pesto - environnement non supporté', 'OK', 'Error') | Out-Null } catch {}
    exit 1
}
if (-not [Environment]::Is64BitProcess) {
    try { [System.Windows.MessageBox]::Show('Pesto doit être exécuté en processus 64 bits. Utilisez Pesto.exe ou Windows PowerShell x64.', 'Pesto - architecture non supportée', 'OK', 'Error') | Out-Null } catch {}
    exit 1
}

# Composants chargés dans la portée du moteur.
. (Join-Path $PSScriptRoot 'Pesto-Common.ps1')
Initialize-PestoCommon -Root $PSScriptRoot
. (Join-Path $PSScriptRoot 'Pesto-Contracts.ps1')
. (Join-Path $PSScriptRoot 'Pesto-JoinRecovery.ps1')
. (Join-Path $PSScriptRoot 'Pesto-UXFlow.ps1')
. (Join-Path $PSScriptRoot 'Pesto-ManagedPolicy.ps1')
. (Join-Path $PSScriptRoot 'Pesto-EngineContracts.ps1')
. (Join-Path $PSScriptRoot 'Pesto-Catalogue.ps1')
. (Join-Path $PSScriptRoot 'Pesto-Diagnostics.ps1')
. (Join-Path $PSScriptRoot 'Pesto-Enterprise.ps1')
. (Join-Path $PSScriptRoot 'Pesto-Extensions.ps1')
. (Join-Path $PSScriptRoot 'Pesto-Policy.ps1')
. (Join-Path $PSScriptRoot 'Pesto-Appearance.ps1')
. (Join-Path $PSScriptRoot 'Pesto-Configuration.ps1')
. (Join-Path $PSScriptRoot 'Pesto-Authentication.ps1')
. (Join-Path $PSScriptRoot 'Pesto-Directory.ps1')
. (Join-Path $PSScriptRoot 'Pesto-Async.ps1')
. (Join-Path $PSScriptRoot 'Pesto-Journal.ps1')
. (Join-Path $PSScriptRoot 'Pesto-AuditSink.ps1')
. (Join-Path $PSScriptRoot 'Pesto-Operations.ps1')
. (Join-Path $PSScriptRoot 'Pesto-Safety.ps1')
. (Join-Path $PSScriptRoot 'Pesto-Interventions.ps1')
. (Join-Path $PSScriptRoot 'Pesto-Preparation.ps1')
. (Join-Path $PSScriptRoot 'Pesto-Names.ps1')
. (Join-Path $PSScriptRoot 'Pesto-Workspace.ps1')
. (Join-Path $PSScriptRoot 'Pesto-Workbench.ps1')
. (Join-Path $PSScriptRoot 'Pesto-Collections.ps1')
. (Join-Path $PSScriptRoot 'Pesto-BatchTools.ps1')
. (Join-Path $PSScriptRoot 'Pesto-NameWorkbench.ps1')
. (Join-Path $PSScriptRoot 'Pesto-ConfigEditor.ps1')
. (Join-Path $PSScriptRoot 'Pesto-ReceiptTools.ps1')
. (Join-Path $PSScriptRoot 'Pesto-Review.ps1')
. (Join-Path $PSScriptRoot 'Pesto-Tables.ps1')
. (Join-Path $PSScriptRoot 'Pesto-Recovery.ps1')

###############################################################################
#  SECTION 1 — UTILITAIRES (purs, sans dépendance UI)
###############################################################################

# Test-PestoDnsName : composant séparé.

# Split-PestoDistinguishedName : composant séparé.

# Get-PestoParentDN : composant séparé.

# Get-PestoDomainFromDN : composant séparé.

# Test-PestoDNWithinScope : composant séparé.

function ConvertTo-PestoRdnValue {
    param([string]$Value)
    if ([string]::IsNullOrEmpty($Value) -or $Value -match '[\x00-\x1f\x7f]') { throw 'Nom OU vide ou contenant un caractère de contrôle.' }
    $sb=New-Object Text.StringBuilder
    for($i=0;$i -lt $Value.Length;$i++) {
        $c=$Value[$i]
        if ($c -in @(',','+','"','\','<','>',';','=') -or ($i -eq 0 -and $c -eq '#') -or ($c -eq ' ' -and ($i -eq 0 -or $i -eq $Value.Length-1))) { [void]$sb.Append('\') }
        [void]$sb.Append($c)
    }
    return $sb.ToString()
}

# Test-PestoConfirmedChange : composant séparé.

# Protect-PestoLogText : composant séparé.

# Get-PestoNameSiteCode : composant séparé.

# Get-PestoSiteContainerDN : composant séparé.

# Get-PestoRenameMoveDecision : composant séparé.

function Write-PestoAtomicText {
    param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Path,
          [Parameter(Mandatory)][AllowEmptyString()][string]$Text,[switch]$Backup)
    $full=[IO.Path]::GetFullPath($Path); $dir=[IO.Path]::GetDirectoryName($full)
    [void][IO.Directory]::CreateDirectory($dir)
    $tmp=$full+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
    try {
        $bytes=([Text.UTF8Encoding]::new($false)).GetBytes($Text)
        $fs=[IO.File]::Open($tmp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try { $fs.Write($bytes,0,$bytes.Length); $fs.Flush($true) } finally { $fs.Dispose() }
        # Trois nouvelles tentatives courtes (100, 300 puis 900 ms), uniquement sur violation de partage ou de verrou.
        # $script:PestoFileReplaceHook est un point d'injection réservé aux tests : jamais défini en production.
        $delays=@(100,300,900);$attempt=0
        while($true){
            try {
                if($script:PestoFileReplaceHook){& $script:PestoFileReplaceHook $tmp $full $Backup}
                elseif([IO.File]::Exists($full)){
                    # PowerShell convertit $null en chaine vide pour un parametre .NET string.
                    # File.Replace attend un VRAI null pour ne pas creer de sauvegarde.
                    # Appels distincts : ne pas typer/caster NullString en [string].
                    if($Backup){[IO.File]::Replace($tmp,$full,($full+'.bak'))}
                    else{[IO.File]::Replace($tmp,$full,[System.Management.Automation.Language.NullString]::Value)}
                } else { [IO.File]::Move($tmp,$full) }
                break
            } catch {
                # Windows PowerShell 5.1 enveloppe l'exception .NET : lire l'IOException d'origine.
                $io=$_.Exception;if($io -isnot [IO.IOException] -and $io.InnerException -is [IO.IOException]){$io=$io.InnerException}
                # 0x80070020 (violation de partage) ou 0x80070021 (violation de verrou) ; toute autre erreur est immédiate.
                if($io -isnot [IO.IOException] -or ($io.HResult -ne -2147024864 -and $io.HResult -ne -2147024863) -or $attempt -ge $delays.Count){throw}
                $delayMs=$delays[$attempt];$attempt++
                if(Get-Command Write-Log -ErrorAction SilentlyContinue){Write-Log "Écriture atomique : fichier verrouillé, nouvelle tentative $attempt/$($delays.Count) dans $delayMs ms pour '$full'" 'WARN' $null 'IO'}
                Start-Sleep -Milliseconds $delayMs
            }
        }
    } catch {
        throw [IO.IOException]::new("Sauvegarde atomique impossible pour '$full' : $($_.Exception.Message)",$_.Exception)
    } finally {
        # Aucun delete+move du fichier de destination : sa version precedente reste protegee.
        if([IO.File]::Exists($tmp)){[IO.File]::Delete($tmp)}
    }
}

function Get-PestoHistoryEmptyText {
    <# Historique vide : les opérations unitaires et les ajouts au domaine ont leurs reçus dans « Interventions et reprises ». #>
    param([Nullable[int]]$ReceiptCount)
    $text='Aucun lot terminé dans cette installation. Les opérations unitaires et les ajouts au domaine sont dans « Interventions et reprises »'
    if($null -ne $ReceiptCount -and $ReceiptCount -gt 0){$text+=' ('+$ReceiptCount+' reçu(s) local(aux))'}
    return $text+'. Le journal conserve les événements de session.'
}

function Get-PestoStateDirectory {
    $base=[Environment]::GetFolderPath('LocalApplicationData')
    if (-not $base) { throw 'Profil local indisponible.' }
    # Sépare les installations/configurations : aucune reprise entre deux domaines.
    $sha=[Security.Cryptography.SHA256]::Create()
    try { $id=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFullPath($script:JsonFile).ToLowerInvariant())))).Replace('-','').Substring(0,16) }
    finally { $sha.Dispose() }
    $dir=Join-Path $base ("GP\State\$id")
    [void][IO.Directory]::CreateDirectory($dir)
    return $dir
}

function Save-PestoQueueCheckpoint {
    param([string]$Phase='Idle')
    if($script:PestoReadOnly){return}
    if ($script:GUI -or $script:SIM) { return }
    if($script:MutationUncertain){$Phase='Uncertain'}
    $rows=@(foreach($r in @($script:table.Rows)) {
        $obj=[ordered]@{}
        foreach($col in $script:table.Columns){$v=$r[$col.ColumnName];$obj[$col.ColumnName]=if($v -is [DBNull]){$null}else{$v}}
        [pscustomobject]$obj
    })
    $data=[ordered]@{Schema=1;Version=$script:Pesto_VERSION;Domain=$script:DOMAINE;Host=$env:COMPUTERNAME;MachineId=[string]$script:HostMachineId;Mode='REEL';Phase=$Phase;Utc=[DateTime]::UtcNow.ToString('o');OperationIds=@($script:QueueOperationIds|Select-Object -Unique);Rows=$rows}
    $json=$data|ConvertTo-Json -Depth 8
    if([Text.Encoding]::UTF8.GetByteCount($json) -gt 16MB){throw 'File trop volumineuse pour la reprise (16 Mio). Exportez le bilan puis réduisez la file avant toute mutation.'}
    Write-PestoAtomicText -Path (Join-Path (Get-PestoStateDirectory) 'queue.json') -Text $json
}

function Save-PestoQueueCheckpointSafe {
    param([string]$Phase='Idle')
    try { Save-PestoQueueCheckpoint -Phase $Phase }
    catch {Set-PestoPersistenceWarning ('Sauvegarde de la file impossible : '+$_.Exception.Message);Write-Log 'Sauvegarde de la file impossible.' 'WARN' $_ 'checkpoint'}
}

function Request-PestoQueuePump {
    # Évite les appels récursifs pour 1 000 simulations/annulations successives.
    if ($script:QueuePumpScheduled) { return }
    $script:QueuePumpScheduled=$true
    [void]$Win.Dispatcher.BeginInvoke([Action]{
        $script:QueuePumpScheduled=$false
        try { Start-PestoNextQueueTask }
        catch {
            $script:MutationUncertain=$true
            Write-Log 'Erreur de pilotage de la file : arrêt de sécurité.' 'ERROR' $_ 'queue'
            if($script:QueueRunState){Fail-PestoQueueCallback -Failure $_}
        }
    },[Windows.Threading.DispatcherPriority]::Background)
}

# New-PestoTaskService : composant séparé.

# Release-PestoComObject : composant séparé.

# Get-PestoTaskArgument : composant séparé.

# Test-PestoPipeClient : composant séparé.

# Invoke-PestoElevatedLocalChange : composant séparé.

function Show-PestoTextReport {
    param([string]$Title,[string]$Text)
    if($Win -and $Win.IsVisible -and $Win.IsActive -and (Get-Command Show-PestoPanel -ErrorAction SilentlyContinue)){[void](Show-PestoPanel -Title $Title -Body (Protect-PestoLogText $Text));return}
    [xml]$rx=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Width="930" Height="650" MinWidth="620" MinHeight="400" WindowStartupLocation="CenterOwner" Background="{DynamicResource BgWindow}" Foreground="{DynamicResource FgText}">
 <Grid Margin="18"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
  <TextBlock x:Name="Heading" FontSize="20" FontWeight="SemiBold" Margin="0,0,0,12" TextWrapping="Wrap"/>
  <TextBox x:Name="Report" Grid.Row="1" IsReadOnly="True" AcceptsReturn="True" TextWrapping="NoWrap" HorizontalScrollBarVisibility="Auto" VerticalScrollBarVisibility="Auto" Background="{DynamicResource BgInput}" Foreground="{DynamicResource FgText}" FontFamily="Consolas" Padding="12" ToolTip="Rapport en lecture seule. Vous pouvez sélectionner le texte pour le copier. Il peut contenir des informations internes." ToolTipService.ShowOnDisabled="True" ToolTipService.InitialShowDelay="450" ToolTipService.ShowDuration="30000" AutomationProperties.HelpText="Rapport en lecture seule. Vous pouvez sélectionner le texte pour le copier. Il peut contenir des informations internes." AutomationProperties.Name="Rapport en lecture seule" AutomationProperties.AutomationId="Report"/>
  <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
   <Button x:Name="Copy" Content="Copier" Padding="18,7" Margin="0,0,8,0" ToolTip="Copier le rapport affiché, sans modifier de poste." ToolTipService.ShowOnDisabled="True" ToolTipService.InitialShowDelay="450" ToolTipService.ShowDuration="30000" AutomationProperties.HelpText="Copier le rapport affiché, sans modifier de poste." AutomationProperties.AutomationId="Copy"/>
   <Button x:Name="Close" Content="Fermer" Padding="18,7" IsCancel="True" ToolTip="Fermer cette fenêtre et conserver la file." ToolTipService.ShowOnDisabled="True" ToolTipService.InitialShowDelay="450" ToolTipService.ShowDuration="30000" AutomationProperties.HelpText="Fermer cette fenêtre et conserver la file." AutomationProperties.AutomationId="Close"/>
  </StackPanel>
 </Grid>
</Window>

'@
    $w=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($rx))
    $w.Title=$Title;$w.FindName('Heading').Text=$Title;$box=$w.FindName('Report');$box.Text=Protect-PestoLogText $Text
    if($Win -and $Win.IsVisible){$w.Owner=$Win;$w.Resources=$Win.Resources}
    $w.FindName('Copy').Add_Click({try{[Windows.Clipboard]::SetText($box.Text)}catch{[Windows.MessageBox]::Show('Presse-papiers indisponible.')|Out-Null}}.GetNewClosure())
    [void]$w.ShowDialog()
}

function Update-PestoQueueRenamePlan {
    param($Row)
    $decision=Get-PestoRenameMoveDecision -Computer ([string]$Row.Nom_du_PC) -NewName ([string]$Row.Nouveau_Nom) `
        -CurrentOU ([string]$Row.OU_Actuelle) -TargetOU ([string]$Row.OU_Destination) `
        -Rename ([bool]$Row.Renommer) -Move ([bool]$Row.Deplacer) -InDomain ([bool]$script:INDOMAIN)
    if($decision.Valid -and $Row.Statut -notin @('OK','VÉRIFIÉ','SIMULÉ','PARTIEL','PROTECTION','INCERTAIN','TECHNIQUE','EN COURS')) {
        $Row.Deplacer=[bool]$decision.Move
    }
    if($Row -is [Data.DataRow] -and $Row.Table.Columns.Contains('Plan')){$Row.Plan=Get-PestoRowPlanText $Row ([bool]$script:INDOMAIN)}
    return $decision
}

function Show-PestoQueuePreview {
    if($script:PreflightRunning -or $script:Running){return}
    [void]$Grid.CommitEdit([Windows.Controls.DataGridEditingUnit]::Cell,$true)
    [void]$Grid.CommitEdit([Windows.Controls.DataGridEditingUnit]::Row,$true)
    $lines=[Collections.Generic.List[string]]::new()
    $mode=if($script:GUI){'DÉMONSTRATION — aucun accès AD'}elseif($script:SIM){'SIMULATION — lectures AD seulement'}else{'RÉEL — écritures après confirmation'}
    $lines.Add("Pesto $script:Pesto_VERSION | $mode")
    $lines.Add("Domaine : $script:DOMAINE | DC : $script:DC")
    $lines.Add("Prévisualisation locale : disponibilité, délégation et état réel AD restent à vérifier lors de l'exécution.")
    $lines.Add("Avant tout renommage AD : état Entra relu sur la cible ; retrait seulement si hybride et autorisé, puis contrôle. Jamais au déplacement seul.")
    $lines.Add('')
    $i=0
    foreach($r in @($script:table.Rows|Where-Object{$_.Traiter -eq $true})){
        $decision=Update-PestoQueueRenamePlan -Row $r
        $i++;$ops=@()
        if(-not $script:INDOMAIN){$ops+='JONCTION LOCALE'}else{
            if($r.Renommer){$ops+='CONTRÔLE ENTRA';$ops+='RENOMMER'};if($r.Deplacer){$ops+='DÉPLACER'}
        }
        $lines.Add("[$i] $($r.Nom_du_PC) | $($ops -join ' puis ')")
        if($r.Renommer){$lines.Add("    Nom cible : $($r.Nouveau_Nom)")}
        if($r.Deplacer){$lines.Add("    OU cible  : $($r.OU_Destination)")}
        $lines.Add("    Règle : $($decision.Reason)")
        if(-not $decision.Valid){$lines.Add("    BLOQUANT : $($decision.Error)")}
        $lines.Add("    Redémarrage demandé : $($r.Reboot) | Dernier statut : $($r.Statut)")
        $errors=@(Test-QueueRowSafe -Nom $r.Nom_du_PC -NewName $r.Nouveau_Nom -OU $r.OU_Destination -Ren $r.Renommer -Move $r.Deplacer)
        foreach($e in $errors){$lines.Add("    BLOQUANT : $e")}
        $lines.Add('')
    }
    if(-not $i){$lines.Add('Aucune ligne cochée.')}
    Show-PestoTextReport 'Prévisualisation de la file — aucune écriture' ($lines -join "`r`n")
}

function Show-PestoSelectedResult {
    $view=$Grid.SelectedItem;if(-not $view){return};$r=$view.Row
    $plan=Get-PestoRowPlanText $r ([bool]$script:INDOMAIN)
    $target=if($r.Deplacer){[string]$r.OU_Destination}else{'OU inchangée (renommage seul)'}
    $guidance=Get-PestoResultGuidance -Code ([string]$r.Code)
    $text="POSTE : $($r.Nom_du_PC)`r`nGUID préparé : $($r.Objet_GUID)`r`n`r`nPLAN : $plan`r`nNom prévu : $($r.Nouveau_Nom)`r`nOU source préparée : $($r.OU_Actuelle)`r`nDestination prévue : $target`r`n`r`nCONTRÔLE : $($r.Precontrole)`r`nLecture UTC : $($r.Controle_Utc)`r`n$($r.Controle_Detail)`r`n`r`nRÉSULTAT : $($r.Statut) | code $($r.Code) | $($r.Duree)`r`nMode du résultat : $($r.Mode_Resultat)`r`nLot : $($r.Lot_ID)`r`nHorodatage UTC : $($r.Horodatage)`r`n$($r.Message)`r`n`r`nSUITE À DONNER`r`n$guidance"
    if($r.PSObject.Properties['Resultat_Precedent'] -and $r.Resultat_Precedent){$text+="`r`n`r`nRÉSULTAT CONSERVÉ AVANT REPRISE`r`n"+[string]$r.Resultat_Precedent}
    Show-PestoDetailsPane 'Fiche du poste : plan, contrôle et résultat' $text
}

function Request-PestoQueueStop {
    if(-not $script:Running){return}
    $script:QueueStopRequested=$true;$BtnStop.IsEnabled=$false
    $LblStatus.Text="Arrêt demandé : attente de la fin de l'action en cours. Les suivantes ne seront pas lancées."
    Write-AuditLine "Arrêt coopératif demandé par l'opérateur." 'warn'
    # Ne jamais interrompre une écriture distante dont l'état deviendrait inconnu.
}

function Reset-PestoSafetyLock {
    if($script:PreflightRunning -or $script:Running -or $script:DirectBusy){return}
    if(Test-PestoQueueWorkerStillActive){Show-MsgWarning 'Le worker n''a pas encore terminé. Une commande Windows peut encore finir.';return}
    if((Get-PestoSelectedQueueIndex) -ge 0){Show-PestoPostState -Mode Queue}else{Show-PestoInterventions}
}

function Invoke-PestoQueueLockAcknowledgement {
    <# Acquitter le verrou ne rejoue aucune ligne et ne valide aucun résultat. Les identifiants et reçus
       restent conservés. Le checkpoint doit être écrit avant de rendre la file disponible. #>
    if($script:PreflightRunning -or $script:Running -or $script:DirectBusy -or $script:JoinBusy -or $script:EDIT_ROW_INDEX -ge 0){return}
    if($script:PestoReadOnly -or $script:SIM -or $script:GUI){Show-MsgInfo 'Acquittement disponible uniquement en session réelle d''intervention.';return}
    if((Test-PestoQueueWorkerStillActive) -or (Test-PestoAsyncOperationRunning 'QueueAction')){Show-MsgWarning 'Le worker n''a pas encore terminé. Une commande Windows peut encore finir : aucun acquittement.';return}
    if(-not $script:MutationUncertain){Show-MsgInfo 'Aucun verrou de file à acquitter.';return}
    $rows=@($script:table.Rows|Where-Object{$_.Statut -in @('INCERTAIN','TECHNIQUE','PROTECTION','EN COURS','PARTIEL')})
    $operationIds=@(@($script:QueueOperationIds)+@($rows|ForEach-Object{if($_.Operation_ID){[string]$_.Operation_ID}})|Select-Object -Unique)
    $summary='Le verrou de sécurité de la file sera levé. '+$rows.Count+' ligne(s) gardent leur statut réel (INCERTAIN, TECHNIQUE, PROTECTION, PARTIEL ; « EN COURS » devient INCERTAIN). Elles seront décochées : préparez une nouvelle ligne pour une nouvelle opération.'
    $summary+="`n`nLes reçus non résolus de ce lot seront acquittés avec le même motif. Ils restent dans l'historique, jamais comptés comme réussis. Aucune commande Windows ou AD n'est lancée."
    $reason=Show-PestoAcknowledgeDialog -Summary $summary
    if(-not $reason){return}
    $mutex=$null;$owned=$false;$savedRows=@();$wasUnmapped=[bool]$script:UnmappedQueueLock
    try{
        $mutex=[Threading.Mutex]::new($false,'Global\GP_PostMutation_v1')
        try{$owned=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$owned=$true}
        if(-not $owned){throw 'Une mutation détient encore le verrou machine : aucun acquittement.'}
        # Le dialogue peut avoir laissé une autre action démarrer : contrôler de nouveau sous le mutex.
        if($script:Running -or $script:PreflightRunning -or $script:DirectBusy -or $script:JoinBusy -or
            (Test-PestoQueueWorkerStillActive) -or (Test-PestoAsyncOperationRunning 'QueueAction') -or
            (Test-PestoAsyncOperationRunning 'DirectAction') -or (Test-PestoAsyncOperationRunning 'DomainJoin')){throw 'Une opération est encore active : aucun acquittement.'}
        $receipts=[Collections.Generic.List[object]]::new()
        foreach($value in $operationIds){
            $id=[Guid]::Empty
            if(-not [Guid]::TryParse([string]$value,[ref]$id) -or $id -eq [Guid]::Empty){throw 'Identifiant de reçu invalide : verrou conservé.'}
            $path=Join-Path (Get-PestoInterventionRoot) ($id.ToString('N')+'.json')
            if(-not [IO.File]::Exists($path)){throw 'Un reçu de ce lot est introuvable : verrou conservé.'}
            $r=Read-PestoIntervention $path
            if($r.Plan.Domain -ine $script:DOMAINE){throw 'Un reçu appartient à un autre domaine : verrou conservé.'}
            if(@($r.Tasks|Where-Object{$_ -and $_.Phase -notin @('Finished','Deleted')}).Count){throw 'Une tâche Windows peut encore agir. Utilisez « Relire les tâches » dans Interventions avant d''acquitter.'}
            if(Test-PestoAcknowledgementNeeded $r){$receipts.Add($r)}
        }
        foreach($r in $receipts){[void](Set-PestoOperationAcknowledgement -OperationId ([string]$r.OperationId) -Reason $reason)}
        foreach($row in $rows){
            $savedRows+=@([pscustomobject]@{Row=$row;Statut=$row.Statut;Code=$row.Code;Traiter=$row.Traiter})
            if($row.Statut -eq 'EN COURS'){$row.Statut='INCERTAIN';if(-not [string]$row.Code){$row.Code='97'}}
            $row.Traiter=$false
        }
        $script:MutationUncertain=$false;$script:UnmappedQueueLock=$false
        # Ne pas utiliser la variante Safe qui absorberait un échec d'écriture.
        if($script:table.Rows.Count){Save-PestoQueueCheckpoint -Phase 'Acknowledged'}else{Save-PestoQueueCheckpoint -Phase 'Idle'}
    }catch{
        foreach($saved in $savedRows){$saved.Row.Statut=$saved.Statut;$saved.Row.Code=$saved.Code;$saved.Row.Traiter=$saved.Traiter}
        $script:MutationUncertain=$true;$script:UnmappedQueueLock=$wasUnmapped
        Show-PestoUsefulError -Title 'Acquittement incomplet' -Message ('Verrou de file conservé. '+$_.Exception.Message) -Stage 'Acquittement' -MutationPossible $false
        Update-QueueButtons;return
    }finally{if($mutex){try{if($owned){$mutex.ReleaseMutex()}}finally{$mutex.Dispose()}}}
    $line='Verrou de file acquitté sans vérification par '+[Security.Principal.WindowsIdentity]::GetCurrent().Name+' ('+$rows.Count+' ligne(s) décochée(s), résultats conservés) : '+$reason
    try{Write-AuditLine $line 'warn'}catch{}
    Add-LogLine $line 'warn'
    $LblStatus.Text='Verrou de file acquitté : lignes décochées, résultats réels conservés. Préparez de nouvelles lignes pour continuer.'
    Sync-Grid;Update-QueueButtons;Update-AddButton;Update-PestoSuiteUI
    if($script:InterventionsUi -and (Get-Command Update-PestoInterventions -CommandType Function -ErrorAction SilentlyContinue)){try{Update-PestoInterventions -Force}catch{}}
}

function Prepare-PestoMoveRetry {
    if($script:PreflightRunning -or $script:Running -or $script:DirectBusy){return}
    if((Get-PestoSelectedQueueIndex) -ge 0){Show-PestoPostState -Mode Queue}else{Show-PestoInterventions}
}

function Restore-PestoQueueCheckpoint {
    if($script:QueueRestoreChecked){return};$script:QueueRestoreChecked=$true
    if($script:SIM -or $script:GUI){return}
    try{
        $path=Join-Path (Get-PestoStateDirectory) 'queue.json'
        if(-not (Test-Path -LiteralPath $path)){return}
        if((Get-Item -LiteralPath $path).Length -gt 16MB){throw 'Sauvegarde de file trop volumineuse (> 16 Mio).'}
        $state=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json
        if($state.Schema -ne 1 -or $state.Mode -ne 'REEL' -or $(if($state.MachineId){$state.MachineId -ine $script:HostMachineId}else{$state.Host -ine $env:COMPUTERNAME}) -or $state.Domain -ine $script:DOMAINE){throw 'Sauvegarde incompatible avec ce poste/domaine.'}
        $script:QueueOperationIds=@()
        foreach($candidateId in @($state.OperationIds)){
            $operationGuid=[Guid]::Empty
            if(-not [Guid]::TryParse([string]$candidateId,[ref]$operationGuid) -or $operationGuid -eq [Guid]::Empty){throw 'Identifiant de reprise de file invalide.'}
            $script:QueueOperationIds+=@($operationGuid.ToString('N'))
        }
        $rows=@($state.Rows)
        if($rows.Count -gt 5000){throw 'Trop de lignes dans la sauvegarde.'}
        $uncertain=$state.Phase -in @('Active','Uncertain') -or @($rows|Where-Object{$_.Statut -eq 'EN COURS'}).Count -gt 0
        # Le verrou appartient à l'exécution, pas au nombre de lignes affichées.
        # Retirer la dernière ligne ne doit pas le lever au prochain démarrage.
        $script:MutationUncertain=[bool]$uncertain
        $script:UnmappedQueueLock=$uncertain -and @($rows|Where-Object{$_.Statut -in @('INCERTAIN','TECHNIQUE','PROTECTION','EN COURS')}).Count -eq 0
        if(-not $rows.Count){
            Update-QueueButtons;Update-AddButton
            if($script:MutationUncertain){$LblStatus.Text='VERROU DE SÉCURITÉ : une ancienne exécution doit être vérifiée.'}
            return
        }
        $answer=[Windows.MessageBox]::Show("Une file sauvegardée existe ($($rows.Count) ligne(s), état $($state.Phase), UTC $($state.Utc)).`nLa restaurer pour consultation ? Toutes les actions resteront décochées.`nUne interruption pendant une mutation active le verrou de sécurité, même sans restauration.",'Reprise de la file Pesto','YesNo','Question','No')
        if($answer -eq 'Yes'){
            $candidate=New-QueueTable
            foreach($entry in $rows){
                if(-not (Test-PestoComputerName ([string]$entry.Nom_du_PC))){throw 'Nom de poste invalide dans la sauvegarde.'}
                $r=$candidate.NewRow()
                foreach($col in $candidate.Columns){
                    if($entry.PSObject.Properties[$col.ColumnName] -and $null -ne $entry.($col.ColumnName)){
                        if($col.DataType -eq [bool]){$r[$col.ColumnName]=Convert-Value-TF $entry.($col.ColumnName) -Strict}
                        else{$r[$col.ColumnName]=[string]$entry.($col.ColumnName)}
                    }
                }
                $r.Traiter=$false
                if([string]$r.ConfigStamp -ne (Get-PestoConfigurationSignature $script:CFG)){
                    $r.NeedsReview=$true;$r.Precontrole='À REFAIRE';$r.Controle_Signature=''
                }
                if($r.Precontrole){$r.Precontrole='À REFAIRE';$r.Controle_Signature=''}
                $r.Plan=Get-PestoRowPlanText $r ([bool]$script:INDOMAIN)
                if($r.Statut -eq 'EN COURS'){$r.Statut='INCERTAIN';$r.Code='97';$r.Message='Interruption durant une action : état réel à vérifier, aucune relance automatique.'}
                [void]$candidate.Rows.Add($r)
            }
            $script:table=$candidate;$Grid.ItemsSource=$candidate.DefaultView
            Add-LogLine 'File restaurée pour consultation ; toutes les lignes sont décochées.' 'warn'
        }
        Update-QueueButtons;Update-AddButton
        if($script:MutationUncertain){$LblStatus.Text='VERROU DE SÉCURITÉ : une ancienne exécution doit être vérifiée.'}
    }catch{
        $script:MutationUncertain=$true
        Write-Log "Sauvegarde illisible ; verrou de sécurité activé." 'ERROR' $_ 'recovery'
        Show-MsgWarning "La sauvegarde de file ne peut pas être validée. Contrôlez les dernières actions avant de lever le verrou :`n$($_.Exception.Message)"
        Update-QueueButtons
    }
}

# Invoke-PestoConfigRepairSave : composant séparé.

# Show-PestoConfigRepair : composant séparé.

# Read-PestoStartupConfig : composant séparé.

function Set-PestoQueueRowResult {
    param($Row,[int]$Code,[string]$Message,[double]$Duration)
    if($script:QueueRunState -and $Row -is [System.Data.DataRow]){
        $Row.Mode_Resultat=[string]$script:QueueRunState.Mode;$Row.Lot_ID=[string]$script:QueueRunState.RunId
    }
    $Row.Code=[string]$Code;$Row.Message=Protect-PestoLogText $Message
    $Row.Duree=[Math]::Round($Duration,2).ToString('0.00',[Globalization.CultureInfo]::InvariantCulture)+' s'
    $Row.Horodatage=[DateTime]::UtcNow.ToString('o');$Row.Traiter=$false
    $Row.Statut=switch($Code){
        89 {'PARTIEL'}
        32 {'PROTECTION'}
        96 {'NON LANCÉ'}
        97 {'INCERTAIN'}
        98 {'TECHNIQUE'}
        default {if($Code -in $script:OK_CODES){if($script:SIM -or $script:GUI){'SIMULÉ'}else{'OK'}}else{'KO'}}
    }
}

function Complete-PestoQueueNotStarted {
    <# Appelee UNIQUEMENT avant Start-PestoAsyncOperation : aucune mutation de cette ligne
       n'a pu etre emise. Arrete la file sans inventer un etat AD incertain. #>
    param($Failure)
    $ticket=$script:QueueCurrentTicket;$st=$script:QueueRunState
    if(-not $ticket -or -not $st -or $ticket.Completed){return}
    $ticket.Completed=$true
    $detail=Protect-PestoLogText "Action NON LANCÉE : précontrôle local impossible. $($Failure.Exception.Message) Aucun appel de renommage/déplacement n'a été émis pour ce poste."
    Write-Log 'Précontrôle local échoue avant lancement du worker.' 'ERROR' $Failure 'checkpoint'
    Set-PestoQueueRowResult -Row $ticket.Item.Row -Code 96 -Message $detail -Duration ((Get-Date)-$ticket.Started).TotalSeconds
    $st.CancelCount++
    for($i=[int]$st.Index;$i -lt $st.Items.Count;$i++) {
        Set-PestoQueueRowResult -Row $st.Items[$i].Row -Code 96 -Message 'File arrêtée avant lancement : précontrôle local en échec sur la ligne précédente.' -Duration 0
        $st.CancelCount++
    }
    $st.Index=$st.Items.Count;$script:QueueCurrentTicket=$null
    Add-LogLine $detail 'err';Write-AuditLine $detail 'err'
    Sync-Grid
    Complete-PestoQueueRun
}

function Complete-PestoQueueItem {
    param([AllowNull()]$WorkerResult,[AllowNull()]$Failure)
    $ticket=$script:QueueCurrentTicket;$st=$script:QueueRunState
    if(-not $ticket -or -not $st -or $ticket.Completed){return}
    $ticket.Completed=$true
    $row=$ticket.Item.Row; $code=98;$message='Worker terminé sans résultat exploitable.'
    if($Failure){
        if($Failure.Exception -is [TimeoutException] -or $Failure.Exception.InnerException -is [TimeoutException]){
            $code=97;$message="Délai de surveillance dépassé : $($Failure.Exception.Message) Aucun résultat positif déduit. Ne relancez pas la mutation."
        }else{$message="Worker interrompu : $($Failure.Exception.Message)"}
    }
    elseif($WorkerResult) {
        foreach($lg in @($WorkerResult.Logs)) {
            if(-not $lg.Text){continue}
            $kind=if($lg.Level -match 'ERR|FATAL'){'err'}elseif($lg.Level -match 'WARN'){'warn'}else{'info'}
            Write-AuditLine ("WORKER [{0}] {1} {2}" -f $lg.Context,$lg.Text,$lg.Detail) $kind
            if($kind -ne 'info'){Add-LogLine ([string]$lg.Text) $kind}
        }
        $a=$WorkerResult.Action
        if($a.TargetMachineId){$row.TargetMachineId=[string]$a.TargetMachineId}
        if($a.OperationId){$row.Operation_ID=[string]$a.OperationId}
        if($a.ObjectGuid){$row.Objet_GUID=[string]$a.ObjectGuid}
        if($a.InitialProtection -is [bool]){$row.InitialProtection=[string]$a.InitialProtection}
        if($a -and $a.PSObject.Properties['ExitCode'] -and $a.PSObject.Properties['ExitMsg']) {
            if($a.ExitCode -is [int]){$code=$a.ExitCode;$message=[string]$a.ExitMsg}else{$code=97;$message='Code de résultat non typé : intervention à vérifier.'}
        }
    }
    $known=($code -in $script:OK_CODES -or $code -in $script:NOK_CODES)
    if(-not $known){$message="Résultat inconnu ($code). $message";$code=98}
    if(-not($script:SIM -or $script:GUI) -and $code -notin @(21,31,69,88,96)){Invalidate-PestoNameInventory}
    Set-PestoQueueRowResult -Row $row -Code $code -Message $message -Duration ((Get-Date)-$ticket.Started).TotalSeconds
    if($code -in $script:OK_CODES){$st.OkCount++}else{$st.KoCount++}
    if(-not($script:SIM -or $script:GUI) -and $code -in @(10,20,77,89)){$st.RestartNeeded=$true}
    $kind=if($code -in $script:OK_CODES){'ok'}else{'err'}
    Add-LogLine $message $kind
    Write-AuditLine ("ACTION run={0} mode={1} poste={2} nom={3} ou={4} code={5} durée={6}" -f $st.RunId,$st.Mode,$ticket.Item.Computer,$ticket.Item.NewName,$ticket.Item.TargetOU,$code,$row.Duree) $kind
    if($WorkerResult -and $WorkerResult.Reboot) {
        $rb=$WorkerResult.Reboot
        Add-LogLine ([string]$rb.ExitMsg) $(if($rb.ExitCode -eq 40){'ok'}else{'warn'})
        $row.Message+=" | REDÉMARRAGE : $($rb.ExitMsg)"
        Write-AuditLine ("REBOOT poste={0} code={1} : {2}" -f $ticket.Item.Computer,$rb.ExitCode,$rb.ExitMsg) 'info'
    }
    if($st.Pilot -and $st.Index -eq 1 -and $st.Total -gt 1){$script:QueueStopRequested=$true;Add-LogLine 'Poste pilote terminé : vérifiez son résultat et son redémarrage avant de sélectionner le reste du lot.' 'warn'}
    $Progress.Value=$st.Index;$script:QueueCurrentTicket=$null
    Sync-Grid
    if($code -in @(32,97,98)) {
        Stop-PestoQueueRemainingForSafety -State $st -Reason $message
        Complete-PestoQueueRun
    } else {
        Save-PestoQueueCheckpointSafe -Phase 'BetweenActions'
        Request-PestoQueuePump
    }
}

function Fail-PestoQueueCallback {
    param($Failure)
    if(-not $script:QueueRunState){return}
    $st=$script:QueueRunState;$script:MutationUncertain=$true
    $detail="Erreur de pilotage : $($Failure.Exception.Message)"
    if($st.Index -gt 0 -and $st.Index -le $st.Items.Count){
        $r=$st.Items[$st.Index-1].Row
        # Un poste déjà conclu dans ce lot garde son résultat : l'erreur peut survenir après lui, avant le poste suivant.
        $concluded=([string]$r.Lot_ID -eq [string]$st.RunId -and [string]$r.Code -ne '')
        if(-not $concluded -and $r.Statut -notin @('ANNULÉ','NON LANCÉ')){Set-PestoQueueRowResult -Row $r -Code 98 -Message $detail -Duration 0}
    }
    Stop-PestoQueueRemainingForSafety -State $st -Reason $detail
    $st.OkCount=0;$st.KoCount=0;$st.CancelCount=0
    foreach($it in $st.Items){
        if($it.Row.Statut -in @('ANNULÉ','NON LANCÉ')){$st.CancelCount++}
        elseif([string]$it.Row.Code -match '^\d+$' -and [int]$it.Row.Code -in $script:OK_CODES){$st.OkCount++}
        else{$st.KoCount++}
    }
    Complete-PestoQueueRun
}

function Complete-PestoComputerProbeSuccess {
    param($Result,[string]$Name,[int]$Generation)
    if($Generation -ne [int]$script:PCProbeGeneration){return}
    [void](Apply-PestoComputerProbeResult -Result $Result -Name $Name -Generation $Generation)
    if($script:PestoStartupClosePending){
        $script:PestoStartupClosePending=$false
        try{Set-PestoStartupStage -Stage 'Prêt' -Detail 'Poste identifié.';Close-PestoStartupWindow}catch{}
    }
}

function Complete-PestoComputerProbeError {
    param($Failure,[string]$Name,[int]$Generation)
    if($Generation -ne [int]$script:PCProbeGeneration){return}
    Reset-ConfigFields -KeepName
    Set-PCInfo "Poste introuvable dans l'AD ou contrôleur indisponible : $($Failure.Exception.Message)" 'err'
    Write-Log "Lecture du poste '$Name' impossible." 'ERROR' $Failure 'AD'
    if($script:PestoStartupClosePending){$script:PestoStartupClosePending=$false;try{Close-PestoStartupWindow}catch{}}
}

# Complete-PestoDirectoryRefresh : composant séparé.

function ConvertTo-PestoSafeCsvCell {
    param([AllowNull()][string]$Value)
    # Les exports sont souvent ouverts dans Excel : neutraliser une formule CSV.
    if($Value -match '^\s*[=+@-]' -or $Value -match '^[\t\r\n]'){return "'"+$Value}
    return $Value
}

###############################################################################
#  Historique RC5 : planification, contrôles en lecture seule et bilans
#  Ces fonctions sont extraites par liste blanche dans les tests et les workers.
###############################################################################
function Get-PestoRowPlanText {
    param($Row,[bool]$InDomain=$true)
    $text=if(-not $InDomain){'JOINDRE'}elseif($Row.Renommer -and $Row.Deplacer){'RENOMMER > DÉPLACER'}elseif($Row.Renommer){'RENOMMER SEUL'}elseif($Row.Deplacer){'DÉPLACER SEUL'}else{'AUCUNE ACTION'}
    if($Row.Reboot){$text+=' > REDÉMARRAGE'}
    return $text
}

function Get-PestoPlanSignature {
    param($Row,[string]$Domain=$script:DOMAINE,[string]$Server=$script:DC)
    # Empreinte de données, jamais de credential. Le mode et la politique de
    # protection font partie du contexte ; un contrôle ne traverse pas les modes.
    $data=@([string]$Domain,[string]$Server,[bool]$script:INDOMAIN,[bool]$script:PRD,
        [bool]$script:GUI,[bool]$script:SIM,[bool]$script:CLEAR_PROTECTION,
        [string]$script:OU['PREPROD'],[string]$script:OU['ROOT'],[string]$script:PREFIXE,[string]$Row.Nom_du_PC,[string]$Row.Nouveau_Nom,
        [string]$Row.OU_Actuelle,[string]$Row.OU_Destination,[bool]$Row.Renommer,
        [bool]$Row.Deplacer,[bool]$Row.Reboot,[string]$Row.Objet_GUID,[string]$Row.TargetOUGuid,[string](Get-PestoConfigurationSignature $script:CFG))
    $json=ConvertTo-Json -InputObject $data -Compress -Depth 3
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($json)))).Replace('-','')}
    finally{$sha.Dispose()}
}

# Get-PestoIdentityChangeReason : composant séparé.

# ConvertTo-PestoFilterLiteral : composant séparé.

function Get-PestoQueueFilterExpression {
    param([string]$Search,[string]$Filter='Toute la file')
    $clauses=[Collections.Generic.List[string]]::new()
    switch($Filter) {
        'À traiter' {$clauses.Add('[Traiter] = true')}
        'À contrôler' {$clauses.Add("[Statut] IN ('','KO','ANNULÉ','NON LANCÉ') AND NOT ([Precontrole] IN ('VÉRIFIÉ','AVERTISSEMENT','DÉMO'))")}
        'À examiner' {$clauses.Add("([Statut] IN ('KO','PARTIEL','PROTECTION','INCERTAIN','TECHNIQUE') OR [Precontrole] = 'BLOQUÉ')")}
        'Réussites réelles' {$clauses.Add("[Statut] = 'OK' AND [Mode_Resultat] = 'RÉEL'")}
        'Simulations' {$clauses.Add("[Statut] = 'SIMULÉ'")}
        'Toute la file' {}
        default {throw 'Filtre de file inconnu.'}
    }
    $term="$Search".Trim()
    if($term.Length -gt 128){$term=$term.Substring(0,128)}
    if($term) {
        $escaped=ConvertTo-PestoFilterLiteral $term
        $parts=@(foreach($col in @('Nom_du_PC','Nouveau_Nom','Site','Service','Organisme','Message')) {"[$col] LIKE '%$escaped%'"})
        $clauses.Add('('+($parts -join ' OR ')+')')
    }
    return (@($clauses.ToArray()|ForEach-Object{'('+$_+')'}) -join ' AND ')
}

function ConvertFrom-PestoComputerList {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    if($Text.Length -gt 65536){throw 'Liste trop volumineuse (64 K caractères maximum).'}
    $list=[Collections.Generic.List[string]]::new();$seen=@{}
    foreach($token in ($Text -split '[\s,;]+')) {
        $name=$token.Trim().ToUpperInvariant();if(-not $name){continue}
        if(-not(Test-PestoComputerName $name)){throw "Nom de poste invalide : '$name'. Uniquement les noms courts, pas les FQDN, les commandes ni les colonnes CSV."}
        if($seen.ContainsKey($name)){throw "Doublon dans la liste : '$name'. La file n'a pas été modifiée."}
        $seen[$name]=$true;$list.Add($name)
        if($list.Count -gt 200){throw '200 postes maximum par préparation de lot.'}
    }
    if(-not $list.Count){throw 'Collez au moins un nom de poste.'}
    return $list.ToArray()
}

function ConvertTo-PestoLdapFilterValue {
    <# W4RT100 : échappement RFC4515 d'une valeur de filtre LDAP. ConvertTo-PestoFilterLiteral
       ne convient pas : il sert au DataView/RowFilter (grammaire différente). #>
    param([AllowNull()][string]$Value)
    if(-not $Value){return ''}
    $sb=[Text.StringBuilder]::new()
    foreach($c in $Value.ToCharArray()){
        $code=[int][char]$c
        if($code -eq 0){[void]$sb.Append('\00')}
        elseif($code -eq 92){[void]$sb.Append('\5c')}
        elseif($code -eq 42){[void]$sb.Append('\2a')}
        elseif($code -eq 40){[void]$sb.Append('\28')}
        elseif($code -eq 41){[void]$sb.Append('\29')}
        else{[void]$sb.Append($c)}
    }
    return $sb.ToString()
}

function New-PestoBulkSourceFilter {
    <# W4RT100 : filtre LDAP d'un nom court, détectant les conflits Name / sAMAccountName / dNSHostName. #>
    param([Parameter(Mandatory)][string]$Name,[string]$Domain='')
    if(-not(Test-PestoComputerName $Name)){throw ('Nom de source invalide : '+$Name+'.')}
    $n=ConvertTo-PestoLdapFilterValue $Name
    $parts=@('(name='+$n+')','(sAMAccountName='+$n+'$)')
    if($Domain){$parts+=('(dNSHostName='+$n+'.'+[string](ConvertTo-PestoLdapFilterValue $Domain)+')')}
    return ('(|'+($parts -join '')+')')
}

function Get-PestoBulkSourceBatches {
    <# W4RT100 : découpe explicite en petits lots bornés (taille et nombre de sources). #>
    param([string[]]$Names,[ValidateRange(1,100)][int]$BatchSize=50,[ValidateRange(1,200)][int]$MaxNames=200)
    if($Names.Count -lt 1){throw 'Aucune source à lire.'}
    if($Names.Count -gt $MaxNames){throw ([string]$MaxNames+' sources maximum par lecture ciblée.')}
    $batches=[Collections.Generic.List[object]]::new()
    for($i=0;$i -lt $Names.Count;$i+=$BatchSize){
        $end=[Math]::Min($i+$BatchSize-1,$Names.Count-1)
        $slice=[Collections.Generic.List[string]]::new()
        for($j=$i;$j -le $end;$j++){$slice.Add([string]$Names[$j])}
        $batches.Add($slice.ToArray())
    }
    return ,$batches.ToArray()
}

function Select-PestoBulkSourceResult {
    <# W4RT100 : résultat par nom demandé : Unique, Absent ou Ambigu. Aucun nom n'est
       déclaré exploitable sans réponse complète et non ambiguë. #>
    param([string[]]$Names,[object[]]$Objects,[string]$Domain='')
    $map=@{}
    foreach($name in @($Names)){$map[([string]$name).ToUpperInvariant()]=[Collections.Generic.List[object]]::new()}
    foreach($o in @($Objects)){
        $keys=[Collections.Generic.List[string]]::new()
        $keys.Add(([string]$o.Name).ToUpperInvariant())
        $keys.Add((([string]$o.SamAccountName).TrimEnd('$')).ToUpperInvariant())
        $keys.Add((((([string]$o.DNSHostName) -split '\.')[0])).ToUpperInvariant())
        foreach($key in $keys){if($key -and $map.ContainsKey($key)){$map[$key].Add($o)}}
    }
    $results=[Collections.Generic.List[object]]::new()
    foreach($name in @($Names)){
        $list=$map[([string]$name).ToUpperInvariant()]
        $seenDn=@{};$distinct=[Collections.Generic.List[object]]::new()
        foreach($o in $list){
            $dn=[string]$o.DistinguishedName+'|'+[string]$o.ObjectGUID
            if($seenDn.ContainsKey($dn)){continue};$seenDn[$dn]=$true
            $distinct.Add($o)
        }
        $state=if($distinct.Count -eq 0){'Absent'}elseif($distinct.Count -eq 1){'Unique'}else{'Ambigu'}
        $results.Add([pscustomobject]@{Name=[string]$name;State=$state;Count=$distinct.Count;Computer=$(if($state -eq 'Unique'){$distinct[0]}else{$null})})
    }
    return $results.ToArray()
}

function New-PestoNameConflictFilter {
    param([string[]]$Stems)
    if($Stems.Count -lt 1 -or $Stems.Count -gt 8){throw 'Entre 1 et 8 séries attendues.'}
    $clauses=[Collections.Generic.List[string]]::new()
    foreach($stem in $Stems){
        $sample=New-PestoNameFromSeries $stem 1
        if(-not(ConvertTo-PestoNameParts $sample)){throw 'Serie invalide.'}
        $layout=Get-PestoNamingLayout
        $value=$sample.Remove($layout.NumberOffset,$layout.NumberWidth).Insert($layout.NumberOffset,'*')
        foreach($attribute in @('name','sAMAccountName','dNSHostName')){$clauses.Add('('+$attribute+'='+$value+'*)')}
        foreach($service in @('HOST','RestrictedKrbHost')){$clauses.Add('(servicePrincipalName='+$service+'/'+$value+'*)')}
    }
    return '(|'+($clauses -join '')+')'
}

function Get-PestoBulkSourceWorkerSource {
    <# W4RT100 : source du worker de lecture ciblée. Un corps seul ne définit rien :
       chaque fonction est reenveloppée dans 'function NOM { ... }'. #>
    $sb=[Text.StringBuilder]::new()
    foreach($n in @('Test-PestoComputerName','Assert-PestoPlainPath','Import-PestoADModule','ConvertTo-PestoLdapFilterValue','New-PestoBulkSourceFilter','Select-PestoBulkSourceResult','New-PestoNameConflictFilter','Test-PestoDnsName','ConvertTo-PestoNameParts')){
        $fn=Get-Command $n -CommandType Function -ErrorAction Stop
        [void]$sb.AppendLine('function '+$n+' {')
        [void]$sb.AppendLine($fn.Definition)
        [void]$sb.AppendLine('}')
    }
    return ($sb.ToString()+(Get-PestoNamingContextSource))
}

$script:PestoBulkSourceWorker = {
    # Lecture des sources puis des séries cibles ; les erreurs/troncatures interdisent l'aperçu.
    param($Request)
    Set-StrictMode -Off;$ErrorActionPreference='Stop'
    if(-not $Request -or -not $Request.Source){throw 'Source worker absente.'}
    . ([scriptblock]::Create([string]$Request.Source))
    $domain=[string]$Request.Domain;$dc=[string]$Request.DC;$template=$Request.Template
    if(-not(Test-PestoDnsName $domain) -or -not(Test-PestoDnsName $dc)){throw 'Domaine ou contrôleur AD non confirmé.'}
    if($Request.Names.Count -lt 1 -or $Request.Names.Count -gt 200){throw 'Entre 1 et 200 sources attendues.'}
    if($template.Prefix -notmatch (Get-PestoFacetPattern Prefix) -or $template.Tag -notmatch (Get-PestoFacetPattern Site) -or $template.Service -notmatch (Get-PestoFacetPattern Service) -or $template.TypeLetter -notin @('P','S','V')){throw 'Modèle de lot invalide.'}
    Import-PestoADModule -ADModulePath ([string]$Request.ADModulePath)
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $adp=@{Server=$dc;ErrorAction='Stop';SearchBase=(($domain.Split('.')|ForEach-Object{'DC='+$_}) -join ',');SearchScope='Subtree'}
    if($null -ne $Request.Credential){$adp.Credential=$Request.Credential}
    $collected=[Collections.Generic.List[object]]::new()
    foreach($batch in @($Request.Batches)){
        if($watch.Elapsed.TotalSeconds -gt 45){throw 'Lecture ciblée trop longue : aucun aperçu partiel.'}
        $filter='(|'+(@(foreach($n in @($batch)){New-PestoBulkSourceFilter -Name ([string]$n) -Domain $domain}) -join '')+')'
        $found=@(Get-ADComputer -LDAPFilter $filter -ResultSetSize 401 -Properties DistinguishedName,ObjectGUID,SamAccountName,DNSHostName @adp)
        if($found.Count -ge 401){throw 'Lecture des sources trop volumineuse ou tronquée.'}
        foreach($o in $found){$collected.Add([pscustomobject]@{Name=[string]$o.Name;DistinguishedName=[string]$o.DistinguishedName;ObjectGUID=[string]$o.ObjectGUID;SamAccountName=[string]$o.SamAccountName;DNSHostName=[string]$o.DNSHostName})}
    }
    $selected=@(Select-PestoBulkSourceResult -Names @($Request.Names) -Objects $collected.ToArray() -Domain $domain)
    $bad=@($selected|Where-Object{$_.State -ne 'Unique'})
    if($bad.Count){throw ('Sources absentes ou ambiguës : '+(($bad|ForEach-Object{$_.Name+' ('+$_.State+')'}) -join ', '))}
    $series=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($row in $selected){
        $id=[Guid]::Empty
        if($row.Computer.Name -ine $row.Name -or -not[Guid]::TryParse([string]$row.Computer.ObjectGUID,[ref]$id) -or $id -eq [Guid]::Empty -or -not$row.Computer.DistinguishedName){throw 'Identité AD source non confirmée par nom et GUID.'}
        $part=ConvertTo-PestoNameParts $row.Name $template.Prefix
        if(($Request.KeepType -or $Request.KeepService -or $Request.KeepNumber) -and -not$part){throw 'Nom source hors convention : désactivez les conservations non applicables.'}
        $type=if($Request.KeepType){$part.Type}else{$template.TypeLetter}
        $service=if($Request.KeepService){$part.Service}else{$template.Service}
        [void]$series.Add((New-PestoNameSeries -Type $type -Prefix $template.Prefix -Site $template.Tag -Service $service -Convention $(Get-PestoNamingLayout).Convention))
    }
    $layout=Get-PestoNamingLayout
    $stems=@($series);$occupied=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase);$total=0
    for($i=0;$i -lt $stems.Count;$i+=8){
        if($watch.Elapsed.TotalSeconds -gt 45){throw 'Lecture des conflits trop longue : aucun aperçu partiel.'}
        $last=[Math]::Min($i+7,$stems.Count-1)
        $found=@(Get-ADObject -LDAPFilter (New-PestoNameConflictFilter -Stems @($stems[$i..$last])) -Properties sAMAccountName,dNSHostName,servicePrincipalName -ResultSetSize 10001 @adp)
        $total+=$found.Count;if($total -gt 10000){throw 'Trop de conflits à lire dans ce lot (limite 10 000). Réduisez le nombre de sources.'}
        foreach($object in $found){
            $aliases=@([string]$object.Name,([string]$object.SamAccountName).TrimEnd('$'),([string]$object.DNSHostName -split '\.')[0])
            foreach($spn in @($object.ServicePrincipalName)){if([string]$spn -match '^(?:HOST|RestrictedKrbHost)/([^/:]+)'){$aliases+=($Matches[1] -split '\.')[0]}}
            foreach($alias in $aliases){
                $value=([string]$alias).ToUpperInvariant()
                $seriesBase=Get-PestoNameSeriesBase -Name $value -Convention $layout.Convention
                if($seriesBase -and $series.Contains($seriesBase)){[void]$occupied.Add($value)}
            }
        }
    }
    [pscustomobject]@{Schema=1;Ok=$true;DC=$dc;Domain=$domain;Truncated=$false;Requested=@($Request.Names);Results=$selected;Computers=@($selected|ForEach-Object{$_.Computer});OccupiedNames=@($occupied);ConflictObjects=$total;CollectedUtc=[DateTime]::UtcNow.ToString('o')}
}

function Invoke-PestoBulkSourceRead {
    param([string[]]$Names,[string]$Domain,[string]$DC,[AllowNull()]$Credential,$Template,
        [bool]$KeepType,[bool]$KeepService,[bool]$KeepNumber,[scriptblock]$OnSuccess,[scriptblock]$OnError,$Context)
    $batches=Get-PestoBulkSourceBatches -Names $Names
    $request=[pscustomobject]@{Names=$Names;Batches=$batches;Domain=$Domain;DC=$DC;Credential=$Credential;Template=$Template;
        KeepType=$KeepType;KeepService=$KeepService;KeepNumber=$KeepNumber;ADModulePath=(Join-Path $BasePath 'ActiveDirectory.psd1');Source=(Get-PestoBulkSourceWorkerSource)}
    return (Start-PestoAsyncOperation -Name 'BulkSourceRead' -ScriptBlock $script:PestoBulkSourceWorker -ArgumentList @($request) -TimeoutSec 60 -CallbackContext $Context -OnSuccess $OnSuccess -OnError $OnError)
}

function New-PestoBulkPlan {
    param([string[]]$Names,[object[]]$Computers,[System.Data.DataTable]$Existing,
          [string]$Prefix,[string]$Tag,[string]$Service,[string]$TargetOU,
          [string]$Site,[string]$Organisme,[string]$TypeLetter='P',[bool]$KeepType=$true,[bool]$KeepService=$false,[bool]$KeepNumber=$false,[string[]]$ReservedNames=@(),[object[]]$ResolvedComputers=@())
    if(-not $script:INDOMAIN){throw 'La préparation de lot est réservée aux postes du domaine.'}
    $layout=Get-PestoNamingLayout;$resolved=$layout.Convention
    $policy=ConvertTo-PestoPolicy $script:CFG.POLICY;$maximum=$policy.MaxBatch
    if($Names.Count -lt 1 -or $Names.Count -gt $maximum){throw ('Entre 1 et '+$maximum+' sources sont autorisées par la politique.')}
    if($Prefix -notmatch ('^[0-9]{'+$resolved.Widths['Prefix']+'}$') -or $Tag -notmatch ('^[A-Za-z]{'+$resolved.Widths['Site']+'}$') -or
       $Service -notmatch ('^[A-Za-z0-9]{'+$resolved.Widths['Service']+'}$') -or $TypeLetter -notmatch ('^['+$resolved.Types+']$')){throw 'Type, préfixe, tag ou service incorrect.'}
    if(-not(Test-PestoOUInConfiguredScope $TargetOU)){throw 'OU cible invalide ou hors périmètre.'}
    $index=@{};$used=@{};$existingSources=@{};$seen=@{}
    # W4RT100 : les objets AD lus de façon ciblée complètent le cache ; ils n'y remplacent rien.
    foreach($pc in @($ResolvedComputers)) {
        $name=([string]$pc.Name).Trim().ToUpperInvariant();if(-not $name){continue}
        if(-not $index.ContainsKey($name)){$index[$name]=$pc}
        elseif([string]$index[$name].DistinguishedName -ine [string]$pc.DistinguishedName){throw "Source ambiguë pour '$name'. Relancez la lecture AD."}
    }
    foreach($pc in @($Computers)) {
        $name=([string]$pc.Name).Trim().ToUpperInvariant();if(-not $name){continue}
        $used[$name]=$true
        if(-not $index.ContainsKey($name)){$index[$name]=$pc}
        elseif([string]$index[$name].DistinguishedName -ine [string]$pc.DistinguishedName){throw "Cache ambigu pour '$name'. Actualisez l'annuaire."}
    }
    foreach($row in @($Existing.Rows)) {
        $existingSources[[string]$row.Nom_du_PC]=$true
        if($row.Renommer -and $row.Nouveau_Nom){$used[[string]$row.Nouveau_Nom]=$true}
    }
    foreach($reserved in $ReservedNames){
        if(-not(Test-PestoGeneratedComputerName $reserved)){throw 'Réservation de nom invalide dans le lot.'}
        $used[$reserved]=$true
    }
    foreach($name in $Names) {
        if(-not(Test-PestoComputerName $name)){throw "Source invalide : '$name'."}
        if($seen.ContainsKey($name) -or $existingSources.ContainsKey($name)){throw "Source dupliquée ou déjà présente dans la file : '$name'."}
        $seen[$name]=$true;$used[$name]=$true
        if(-not $index.ContainsKey($name)){throw "'$name' n'est pas dans le cache ni confirmé par une lecture AD ciblée. Actualisez l'annuaire, lisez les sources dans l'AD, ou ajoutez ce poste individuellement."}
    }
    $candidate=New-QueueTable;$candidatePools=@{}
    $excluded=@(foreach($pattern in $policy.ExcludedNames){[Management.Automation.WildcardPattern]::new($pattern,'IgnoreCase')})
    foreach($name in $Names) {
        $pc=$index[$name];$sourceOU=Get-PestoParentDN ([string]$pc.DistinguishedName)
        if(-not(Test-PestoOUInConfiguredScope $sourceOU)){throw "Source hors périmètre : '$name'."}
        $type=$TypeLetter
        if($KeepType) {
            if(-not(Test-PestoGeneratedComputerName $name)){throw "Type non déductible du nom '$name'. Décochez 'Conserver le type' pour utiliser le type du formulaire."}
            $type=$name.Substring([int]$layout.Offsets['Type'],1).ToUpperInvariant()
        }
        $parts=ConvertTo-PestoNameParts $name $Prefix
        if(($KeepService -or $KeepNumber) -and -not $parts){throw 'Pour conserver service ou numéro, tous les noms sources doivent respecter la convention.'}
        $serviceForRow=if($KeepService){$parts.Service}else{$Service}
        $stem=New-PestoNameSeries -Type $type -Prefix $Prefix -Site $Tag -Service $serviceForRow -Convention $resolved;$new=''
        if($KeepNumber){
            $n=New-PestoComputerName -Type $type -Prefix $Prefix -Site $Tag -Service $serviceForRow -Number $parts.Number
            if($n -ieq $name){throw ("Aucun changement de nom pour '$name'. Utilisez un déplacement seul si nécessaire.")}
            if(@($excluded|Where-Object{$_.IsMatch($n)}).Count){throw 'Numéro conservé exclu par la politique.'}
            if($used.ContainsKey($n)){throw ("Le nom '$n' est déjà présent ou préparé. Aucun numéro réattribué silencieusement.")}
            $new=$n;$used[$n]=$true
        }else{
            if(-not $candidatePools.ContainsKey($stem)){
                $pool=[Collections.Generic.List[string]]::new()
                for($i=1;$i -le $layout.MaximumNumber;$i++) {
                    $n=New-PestoComputerName -Type $type -Prefix $Prefix -Site $Tag -Service $serviceForRow -Number $i
                    if(-not $used.ContainsKey($n) -and -not @($excluded|Where-Object{$_.IsMatch($n)}).Count){$pool.Add($n)}
                }
                $candidatePools[$stem]=$pool
            }
            $available=$candidatePools[$stem]
            # Même sélection uniforme que les formulaires : tous les candidats
            # de cette série, puis exclusion immédiate pour les lignes suivantes.
            if($available.Count){$indexToTake=Get-PestoInitialNameIndex $available.Count;$new=$available[$indexToTake];$available.RemoveAt($indexToTake);$used[$new]=$true}
        }
        if(-not $new){throw "Plage 001-999 épuisée pour '$stem'. Aucun ajout partiel."}
        $decision=Get-PestoRenameMoveDecision -Computer $name -NewName $new -CurrentOU $sourceOU -TargetOU $TargetOU -Rename $true -Move $false
        if(-not $decision.Valid){throw $decision.Error}
        $r=$candidate.NewRow();$r.Nom_du_PC=$name;$r.Nouveau_Nom=$new;$r.OU_Actuelle=$sourceOU;$r.OU_Destination=$TargetOU
        $r.Type_de_PC=switch($type){'P'{'Portable'};'S'{'Fixe'};'V'{'Virtuel'}}
        $r.Organisme=$Organisme;$r.Site=$Site;$r.Service=$serviceForRow.ToUpperInvariant();$r.Renommer=$true;$r.Deplacer=[bool]$decision.Move
        $r.Traiter=$false;$r.Reboot=$false;$r.Precontrole='À CONTRÔLER'
        $guid=[Guid]::Empty
        if([Guid]::TryParse([string]$pc.ObjectGUID,[ref]$guid) -and $guid -ne [Guid]::Empty){$r.Objet_GUID=$guid.ToString('D')}
        $r.Plan=Get-PestoRowPlanText -Row $r
        [void]$candidate.Rows.Add($r)
    }
    if($Existing.Rows.Count+$candidate.Rows.Count -gt 5000){throw 'La file dépasserait 5 000 postes.'}
    return ,$candidate
}

function New-PestoPreflightProgress {
    param([ValidateRange(1,200)][int]$Total)
    # Contrat commun aux parcours unitaire et par lot. La file conserve les
    # résultats complets si un contrôle est interrompu avant son retour normal.
    return [hashtable]::Synchronized(@{
        Done=0;Total=$Total;Current='';Cancelled=$false
        Results=[Collections.Concurrent.ConcurrentQueue[object]]::new()
    })
}

function Get-PestoPreflightSource {
    $names=@('Import-PestoADModule','Assert-PestoPlainPath','Test-PestoDnsName','Split-PestoDistinguishedName','Get-PestoParentDN','Get-PestoDomainFromDN','Test-PestoDNWithinScope',
        'ConvertTo-PestoNameParts','Test-PestoComputerName','Test-PestoGeneratedComputerName','Test-PestoOUPath','Test-PestoOUInConfiguredScope',
        'Get-PestoNameSiteCode','Get-PestoSiteContainerDN','Get-PestoRenameMoveDecision','Get-PestoIdentityChangeReason',
        'Test-QueueRowSafe','Protect-PestoLogText','Invoke-PestoReadOnlyPreflight')
    $names=@($names+@('Assert-PestoClosedObject')+@(Get-PestoNamingFunctionNames)|Select-Object -Unique)
    $sb=[Text.StringBuilder]::new()
    foreach($n in $names){$fn=Get-Command $n -CommandType Function -ErrorAction Stop;[void]$sb.AppendLine("function $n {");[void]$sb.AppendLine($fn.Definition);[void]$sb.AppendLine('}')}
    return ($sb.ToString()+(Get-PestoNamingContextSource))
}

function Invoke-PestoReadOnlyPreflight {
    param($Item,$Request,[hashtable]$OUCache)
    $problems=[Collections.Generic.List[string]]::new();$warnings=[Collections.Generic.List[string]]::new();$checks=[Collections.Generic.List[string]]::new()
    $guid='';$observedOU='';$targetGuid='';$seriesTaken=@()
    try {
        $decision=Get-PestoRenameMoveDecision -Computer $Item.Nom_du_PC -NewName $Item.Nouveau_Nom -CurrentOU $Item.OU_Actuelle -TargetOU $Item.OU_Destination -Rename $Item.Renommer -Move $Item.Deplacer -InDomain $Request.InDomain
        if(-not $decision.Valid){throw $decision.Error}
        if([bool]$decision.Move -ne [bool]$Item.Deplacer){throw 'Le déplacement calculé diffère du plan. Recréez la ligne avant le contrôle.'}
        $errors=@(Test-QueueRowSafe -Nom $Item.Nom_du_PC -NewName $Item.Nouveau_Nom -OU $Item.OU_Destination -Ren $Item.Renommer -Move $Item.Deplacer)
        if($errors.Count){throw ($errors -join ' | ')}
        $checks.Add($decision.Reason)
        $adp=@{Server=[string]$Request.DC;ErrorAction='Stop'}
        if($Request.Credential){$adp.Credential=$Request.Credential}
        if($Request.InDomain) {
            $n=[string]$Item.Nom_du_PC
            $found=@(Get-ADComputer -LDAPFilter "(|(name=$n)(sAMAccountName=$n`$)(dNSHostName=$n.$($Request.Domain)))" -ResultSetSize 2 -Properties DistinguishedName,ObjectGUID,Enabled,ProtectedFromAccidentalDeletion @adp)
            if($found.Count -ne 1){throw "Source absente ou ambiguë dans l'AD ($($found.Count) résultat(s))."}
            $source=$found[0];$guid=[string]$source.ObjectGUID
            $g=[Guid]::Empty;if(-not [Guid]::TryParse($guid,[ref]$g) -or $g -eq [Guid]::Empty){throw 'GUID source absent ou invalide.'}
            $observedOU=Get-PestoParentDN ([string]$source.DistinguishedName)
            if(-not(Test-PestoOUInConfiguredScope $observedOU)){throw 'Source hors périmètre configuré.'}
            $drift=Get-PestoIdentityChangeReason -ExpectedGuid $Item.Objet_GUID -ActualGuid $guid -ExpectedOU $Item.OU_Actuelle -ActualOU $observedOU
            if($drift){throw $drift}
            $checks.Add('Source AD unique, périmètre et OU source contrôlés.')
            if($source.Enabled -eq $false){$warnings.Add('Compte ordinateur désactivé dans AD.')}
            if($Item.Deplacer -and $source.ProtectedFromAccidentalDeletion) {
                if(-not $Request.ClearProtection){throw 'Objet protégé : la levée temporaire est interdite par la configuration.'}
                $warnings.Add('Protection anti-suppression : levée temporaire et restauration prévues par le moteur.')
            }
        }
        if($Item.Renommer) {
            $n=[string]$Item.Nouveau_Nom
            $taken=@(Get-ADComputer -LDAPFilter "(|(name=$n)(sAMAccountName=$n`$)(dNSHostName=$n.$($Request.Domain)))" -ResultSetSize 2 @adp)
            if($taken.Count){
                # Toute la série du nom (12 premiers caractères) dans le domaine : le nom suivant proposé sera réellement libre.
                if(ConvertTo-PestoNameParts $n){
                    $series=Get-PestoNameSeriesBase $n
                    $ldapSeries=(New-PestoNameFromSeries $series 1).Remove((Get-PestoNamingLayout).NumberOffset,(Get-PestoNamingLayout).NumberWidth).Insert((Get-PestoNamingLayout).NumberOffset,'*')
                    # Lecture d'appoint : si elle échoue, le blocage reste le même et le nom suivant sera vérifié à son tour.
                    try{
                        $seriesTaken=@(Get-ADComputer -LDAPFilter ('(|(name='+$ldapSeries+')(sAMAccountName='+$ldapSeries+'$)(dNSHostName='+$ldapSeries+'.*))') -Properties DNSHostName,SamAccountName -ResultSetSize 2000 @adp |
                            ForEach-Object{foreach($v in @([string]$_.Name,([string]$_.SamAccountName).TrimEnd('$'),(([string]$_.DNSHostName) -split '\.')[0])){if($v){$v.ToUpperInvariant()}}} |
                            Where-Object{(Get-PestoNameSeriesBase $_) -ceq $series} | Sort-Object -Unique)
                    }catch{$seriesTaken=@()}
                }
                throw "Nom cible déjà présent dans AD : '$n'."
            }
            $checks.Add('Nom cible libre sur le contrôleur interrogé au moment de cette lecture.')
        }
        if($Item.Deplacer) {
            $dest=if(-not $Request.InDomain -and -not $Request.PRD){[string]$Request.OU['PREPROD']}else{[string]$Item.OU_Destination}
            if(-not(Test-PestoOUInConfiguredScope $dest)){throw 'Destination effective hors périmètre.'}
            if(-not $OUCache.ContainsKey($dest)) {
                $ouObject=Get-ADOrganizationalUnit -Identity $dest @adp
                if(-not $ouObject){throw 'OU cible absente.'}
                $og=[Guid]::Empty
                if(-not [Guid]::TryParse([string]$ouObject.ObjectGUID,[ref]$og) -or $og -eq [Guid]::Empty){throw 'GUID de destination non confirmé.'}
                $OUCache[$dest]=$og.ToString('D')
            }
            $targetGuid=[string]$OUCache[$dest]
            $checks.Add('OU de destination effective et son GUID confirmés sur le même contrôleur.')
        }
        if($Request.InDomain -and ($Item.Renommer -or $Item.Reboot) -and $Item.Nom_du_PC -ine $Request.Host) {
            $ping=[Net.NetworkInformation.Ping]::new()
            try {
                $hostName=[string]$Item.Nom_du_PC+'.'+[string]$Request.Domain
                $reply=$ping.Send($hostName,400)
                if($reply.Status -eq [Net.NetworkInformation.IPStatus]::Success){$checks.Add('Réponse ICMP reçue (ne prouve pas les droits RPC/WMI).')}
                else{$warnings.Add('Pas de réponse ICMP. Ce seul indicateur ne bloque pas le renommage.')}
            }catch{$warnings.Add('Sonde ICMP indisponible. Aucun échec de mutation ne peut en être déduit.')}
            finally{$ping.Dispose()}
        }
        $checks.Add('Droits de mutation, canaux RPC/WMI et redémarrage : non certifiés par ce contrôle en lecture seule.')
    }catch{$problems.Add((Protect-PestoLogText $_.Exception.Message))}
    $state=if($problems.Count){'BLOQUÉ'}elseif($warnings.Count){'AVERTISSEMENT'}else{'VÉRIFIÉ'}
    $detail=@(@($problems.ToArray()|ForEach-Object{'BLOCAGE : '+$_})+@($warnings.ToArray()|ForEach-Object{'ATTENTION : '+$_})+@($checks.ToArray()|ForEach-Object{'LECTURE : '+$_})) -join "`r`n"
    return [pscustomobject]@{Key=[string]$Item.Key;State=$state;Detail=$detail;Guid=$guid;ObservedOU=$observedOU;TargetOUGuid=$targetGuid;SeriesTaken=$seriesTaken;Utc=[DateTime]::UtcNow.ToString('o')}
}

function Get-PestoResultGuidance {
    param([string]$Code,[string]$Message)
    switch($Code) {
        '10' {'Jonction annoncée réussie. Contrôlez la connexion au domaine après redémarrage ; ne rejouez pas la jonction.'}
        '20' {'Renommage annoncé réussi. Redémarrez au moment prévu et contrôlez le nom appliqué ; ne relancez pas le renommage.'}
        '77' {'Renommage et déplacement annoncés réussis. Vérifiez le nom après redémarrage et les stratégies du nouveau site.'}
        '89' {"Le renommage a réussi. Utilisez $(Get-PestoUxNom 'BtnReprendre') après vérification AD, pas une nouvelle action de renommage."}
        '32' {'Vérifiez et rétablissez la protection anti-suppression de l''objet AD. Le verrou de sécurité ne doit pas être levé avant ce contrôle.'}
        '96' {'Aucune mutation lancée pour cette ligne. Corrigez le précontrôle local puis préparez un nouvel essai.'}
        '97' {'Résultat incertain : contrôlez le poste, l''objet AD et la réplication. Aucun replay automatique.'}
        '98' {'Échec technique : consultez le journal et vérifiez l''état réel du poste avant toute nouvelle action.'}
        '69' {'Le nom cible est occupé. Actualisez le cache AD puis choisissez un autre nom.'}
        '88' {'Le nom cible est occupé. Actualisez le cache AD puis choisissez un autre nom.'}
        '30' {'Déplacement confirmé. Le renommage et le redémarrage ne sont pas rejoués.'}
        '33' {'Le poste était déjà dans l''OU cible. Aucun déplacement inutile.'}
        default {'Consultez le message détaillé. Un contrôle préalable valide ne garantit ni les droits de mutation ni la réussite distante.'}
    }
}

function New-PestoQueueReportHtml {
    param([object[]]$Rows,[string]$Domain,[string]$Server,[string]$Version,[string]$ContextMode)
    $sb=[Text.StringBuilder]::new()
    [void]$sb.AppendLine(@'
<!doctype html><html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src 'none'; base-uri 'none'; form-action 'none'">
<title>Pesto | Bilan des opérations</title><style>
body{font:14px system-ui,Segoe UI,sans-serif;background:#f3f5f8;color:#192538;margin:0;padding:32px}main{max-width:1500px;margin:auto}h1{font-size:30px;margin:8px 0}h2{font-size:19px}.box{background:white;border:1px solid #dce2ea;border-radius:12px;padding:20px;margin:16px 0}small,.muted{color:#506078}table{border-collapse:collapse;width:100%;font-size:12px}th{text-align:left;background:#eef2f7}th,td{border-bottom:1px solid #dce2ea;padding:10px;vertical-align:top;overflow-wrap:anywhere}pre{white-space:pre-wrap;font:12px Consolas,monospace}.scroller{overflow-x:auto}footer{margin-top:24px;color:#506078}@media print{body{padding:0;background:white}.box{border-radius:0}tr{break-inside:avoid}thead{display:table-header-group}} </style></head><body><main>
<h1>Pesto</h1><p class="muted">Plan et résultats consignés, sans commande exécutable et sans ressource distante.</p>
'@)
    $encode={param($v) [Net.WebUtility]::HtmlEncode((Protect-PestoLogText ([string]$v)))}
    [void]$sb.AppendLine('<div class="box"><strong>Contexte de l''export</strong><p>Version : '+(& $encode $Version)+' | Domaine : '+(& $encode $Domain)+' | DC : '+(& $encode $Server)+'<br>Mode actuel : '+(& $encode $ContextMode)+' | Export UTC : '+[DateTime]::UtcNow.ToString('u')+'</p><small>Le mode de chaque résultat figure dans sa ligne. Une simulation n''est pas une mutation réelle. Un contrôle préalable est une observation datée, pas une certification des droits.</small></div>')
    $rowCount=@($Rows).Count
    [void]$sb.AppendLine('<div class="box scroller"><h2>'+$rowCount+' ligne(s)</h2><table><thead><tr><th>Poste / référence</th><th>Plan</th><th>Avant / destination prévue</th><th>Contrôle préalable</th><th>Résultat consigné</th></tr></thead><tbody>')
    foreach($r in @($Rows)) {
        $mode=if($r.Mode_Resultat){[string]$r.Mode_Resultat}elseif($r.Statut -eq 'SIMULÉ'){'SIMULATION'}elseif($r.Statut){'HISTORIQUE NON QUALIFIÉ'}else{'NON EXÉCUTÉ'}
        $dest=if($r.Deplacer){[string]$r.OU_Destination}else{'OU inchangée'}
        [void]$sb.AppendLine('<tr><td><strong>'+(& $encode $r.Nom_du_PC)+'</strong>'+'</td><td>'+(& $encode $r.Plan)+'<br>Nom cible : '+(& $encode $r.Nouveau_Nom)+'<br>Reboot demandé : '+(& $encode ([string][bool]$r.Reboot))+'</td><td><small>Source préparée :</small><br>'+(& $encode $r.OU_Actuelle)+'<br><small>Destination prévue :</small><br>'+(& $encode $dest)+'</td><td>'+(& $encode $r.Precontrole)+'<br>'+(& $encode $r.Controle_Utc)+'<pre>'+(& $encode $r.Controle_Detail)+'</pre></td><td><strong>'+(& $encode $r.Statut)+'</strong> ['+(& $encode $r.Code)+']<br>'+(& $encode $mode)+' | '+(& $encode $r.Duree)+'<br>'+(& $encode $r.Horodatage)+'<br>Lot : '+(& $encode $r.Lot_ID)+'<pre>'+(& $encode $r.Message)+'</pre></td></tr>')
    }
    [void]$sb.AppendLine('</tbody></table></div><footer>Export local Pesto. Contient des noms de machines, des chemins AD et des détails techniques : diffusion interne uniquement. L''OU cible affichée est une intention ; seul le résultat consigné précise ce qui a été confirmé. Ce rapport ne remplace pas le journal d''audit.</footer></main></body></html>')
    return $sb.ToString()
}

function Reset-PestoRowPreflight {
    param($Row,[switch]$ClearIdentity)
    if($script:PreflightCache){
        if($Row.Controle_Signature){$script:PreflightCache.Remove([string]$Row.Controle_Signature)}
        $script:PreflightCache.Remove((Get-PestoPlanSignature $Row))
    }
    foreach($col in @('Precontrole','Controle_Detail','Controle_Utc','Controle_Signature')){$Row[$col]=''}
    $Row.Precontrole='À CONTRÔLER'
    if($ClearIdentity){$Row.Objet_GUID='';$Row.TargetOUGuid=''}
    $Row.Plan=Get-PestoRowPlanText $Row ([bool]$script:INDOMAIN)
}

function Get-PestoSelectedQueueIndex {
    if(-not $Grid -or $Grid.SelectedItem -isnot [System.Data.DataRowView]){return -1}
    # L'index de la vue filtrée/triée n'est JAMAIS l'index dans DataTable.Rows.
    return $script:table.Rows.IndexOf($Grid.SelectedItem.Row)
}

function Update-PestoQueueFilter {
    if($null -eq $script:table -or -not $TxtQueueSearch -or -not $CmbQueueFilter){return}
    try {
        [void]$Grid.CommitEdit([Windows.Controls.DataGridEditingUnit]::Cell,$true)
        [void]$Grid.CommitEdit([Windows.Controls.DataGridEditingUnit]::Row,$true)
        $filter=if($CmbQueueFilter.SelectedItem){[string]$CmbQueueFilter.SelectedItem}else{'Toute la file'}
        $script:table.DefaultView.RowFilter=Get-PestoQueueFilterExpression -Search $TxtQueueSearch.Text -Filter $filter
        Update-QueueButtons
    }catch{Write-Log 'Filtre de file non appliqué.' 'WARN' $_ 'file';$LblPilotage.Text='Filtre invalide : la vue précédente est conservée.'}
}

function Invoke-PestoQueueSearchTick {
    param($Sender,$EventArgs)
    $Sender.Stop();Update-PestoQueueFilter
}

function Set-PestoVisibleSelection {
    param([bool]$Selected)
    if($script:Running -or $script:PreflightRunning){return}
    try{[void]$Grid.CommitEdit([Windows.Controls.DataGridEditingUnit]::Cell,$true);[void]$Grid.CommitEdit([Windows.Controls.DataGridEditingUnit]::Row,$true)}catch{return}
    # Matérialiser AVANT de changer Traiter : la vue peut se filtrer elle-même.
    $visible=@(foreach($rv in $script:table.DefaultView){$rv.Row})
    foreach($r in $visible) {
        if(-not $Selected){$r.Traiter=$false}
        elseif($r.Statut -in @('','KO','ANNULÉ','NON LANCÉ')){$r.Traiter=$true}
    }
    Sync-Grid;Update-QueueButtons;Save-PestoQueueCheckpointSafe
}

function Update-PestoPilotage {
    if($null -eq $script:table -or -not $LblPilotage){return}
    if(-not $script:Running -and -not $script:PreflightRunning){Update-PestoPreflightFreshness}
    $all=@($script:table.Rows);$selected=@($all|Where-Object{$_.Traiter});$visible=@($script:table.DefaultView)
    $visibleSelected=@($visible|Where-Object{$_.Traiter}).Count;$hidden=$selected.Count-$visibleSelected
    $ok=@($all|Where-Object{$_.Statut -eq 'OK'}).Count
    $review=@($all|Where-Object{$_.Statut -in @('KO','PARTIEL','PROTECTION','INCERTAIN','TECHNIQUE') -or $_.Precontrole -eq 'BLOQUÉ'}).Count
    $LblPilotage.Text="$($all.Count) poste(s) | $($selected.Count) coché(s) | $ok OK | $review à examiner"
    $LblFilterCount.Text="$($visible.Count) visible(s)"
    if($hidden -gt 0){$LblFilterCount.Text+=" | ATTENTION : $hidden coché(s) masqué(s)"}
    $LblEmpty.Text=if($all.Count){'Aucune ligne ne correspond au filtre.'}else{"Aucune action en file.`nConfigurez un poste ou utilisez Préparer un lot."}
    $LblEmpty.Visibility=if($visible.Count){'Collapsed'}else{'Visible'}
    $locked=[bool]$script:Running -or [bool]$script:PreflightRunning
    $editing=$script:EDIT_ROW_INDEX -ge 0
    $BtnPreflight.IsEnabled=(-not $locked -and -not $editing -and $selected.Count -gt 0 -and -not $script:CfgRestartRequired -and -not(Test-PestoAsyncOperationRunning 'DirectoryRefresh'))
    $BtnCancelPreflight.Visibility=if($script:PreflightRunning){'Visible'}else{'Collapsed'}
    $BtnBulk.IsEnabled=(-not $locked -and -not $editing -and [bool]$script:INDOMAIN -and -not (Test-PestoGlobalSafetyBarrier) -and -not $script:CfgRestartRequired -and -not(Test-PestoAsyncOperationRunning 'DirectoryRefresh'))
    $BtnHtmlReport.IsEnabled=(-not $locked -and $all.Count -gt 0)
    $BtnHistory.IsEnabled=(-not $locked)
    if($script:PreflightRunning){$BtnStop.IsEnabled=$false}
    if(-not $locked -and -not $script:LastPilotageNote){$LblQueueActivity.Text='Contrôler ne modifie aucun poste. Le rapport couvre toute la file.'}
    if($script:PestoUxReady){Request-PestoUxRefresh}
}

function Update-PestoPreflightFreshness {
    if($null -eq $script:table){return}
    foreach($row in @($script:table.Rows)) {
        if($row.Statut -notin @('','KO','ANNULÉ','NON LANCÉ')){continue}
        if($row.Precontrole -notin @('VÉRIFIÉ','AVERTISSEMENT','DÉMO','PÉRIMÉ','BLOQUÉ')){continue}
        $key=Get-PestoPlanSignature $row
        if(-not $script:PreflightCache -or -not $script:PreflightCache.ContainsKey($key)) {
            $row.Precontrole='À REFAIRE';$row.Controle_Signature='';continue
        }
        $r=$script:PreflightCache[$key];$at=[DateTimeOffset]::MinValue
        # Un blocage connu n'expire pas en une autorisation.
        if($r.State -eq 'BLOQUÉ'){$row.Precontrole='BLOQUÉ';continue}
        if(-not [DateTimeOffset]::TryParse([string]$r.Utc,[ref]$at)){$row.Precontrole='PÉRIMÉ';continue}
        $age=([DateTimeOffset]::UtcNow-$at).TotalSeconds
        if($age -lt 0 -or $age -gt 120){$row.Precontrole='PÉRIMÉ'}else{$row.Precontrole=[string]$r.State}
    }
}

function Get-PestoPreflightRunIssues {
    param([object[]]$Rows)
    $errors=[Collections.Generic.List[string]]::new()
    foreach($r in @($Rows)) {
        if($r.NeedsReview -eq $true -or [string]$r.ConfigStamp -ne (Get-PestoConfigurationSignature $script:CFG)){
            $errors.Add("$($r.Nom_du_PC) : paramètres métier modifiés ou plan ancien. Cliquez sur Contrôler avant l’exécution.")
        }
        $key=Get-PestoPlanSignature $r
        if($script:PreflightCache -and $script:PreflightCache.ContainsKey($key)) {
            $result=$script:PreflightCache[$key]
            if($result.State -eq 'BLOQUÉ'){$errors.Add("$($r.Nom_du_PC) : précontrôle bloqué. Corrigez la ligne puis contrôlez à nouveau. $($result.Detail)")}
        }
    }
    return $errors.ToArray()
}

function Get-PestoPreflightConfirmationText {
    param([object[]]$Rows)
    $fresh=0;$missing=0
    foreach($r in @($Rows)) {
        $key=Get-PestoPlanSignature $r;$result=$null
        if($script:PreflightCache -and $script:PreflightCache.ContainsKey($key)){$result=$script:PreflightCache[$key]}
        $at=[DateTimeOffset]::MinValue
        if($result -and [DateTimeOffset]::TryParse([string]$result.Utc,[ref]$at) -and ([DateTimeOffset]::UtcNow-$at).TotalSeconds -ge 0 -and ([DateTimeOffset]::UtcNow-$at).TotalSeconds -le 120){$fresh++}else{$missing++}
    }
    $visibleSelected=@($script:table.DefaultView|Where-Object{$_.Traiter}).Count
    $hidden=[Math]::Max(0,@($Rows).Count-$visibleSelected)
    $text="Contrôles valides au plus 2 min : $fresh | Absents/périmés : $missing."
    if($hidden){$text+="`nATTENTION : $hidden ligne(s) cochée(s) sont masquées par le filtre, mais seront exécutées."}
    $text+="`nLes contrôles sont des lectures AD, pas une garantie de droits ou de réussite."
    return $text
}

$script:PestoPreflightWorker={
    param($Request,$Source)
    Set-StrictMode -Off;$ErrorActionPreference='Stop'
    . ([scriptblock]::Create([string]$Source))
    if($Request.Progress -isnot [hashtable] -or -not $Request.Progress.IsSynchronized -or
        $Request.Progress.Results -isnot [Collections.Concurrent.ConcurrentQueue[object]]){
        throw 'Contrat de progression du précontrôle invalide. Aucune lecture AD lancée.'
    }
    Import-PestoADModule -ADModulePath ([string]$Request.ADModulePath)
    $script:INDOMAIN=[bool]$Request.InDomain;$script:OU=$Request.OU;$script:OUV=$Request.OUSite
    $script:PREFIXE=[string]$Request.Prefix
    $results=[Collections.Generic.List[object]]::new();$ouCache=@{}
    foreach($item in $Request.Items) {
        if($Request.Progress.Cancelled){break}
        $Request.Progress.Current=[string]$item.Nom_du_PC
        $result=Invoke-PestoReadOnlyPreflight -Item $item -Request $Request -OUCache $ouCache
        $results.Add($result);$Request.Progress.Results.Enqueue($result);$Request.Progress.Done=$results.Count
    }
    [pscustomobject]@{Results=$results.ToArray()}
}

function Start-PestoQueuePreflight {
    if($script:DirectBusy -or (Test-PestoDirectTargetBarrier)){return}

    if($script:JoinBusy -or (Test-PestoAsyncOperationRunning 'DomainJoin')){return}

    if($script:Running -or $script:PreflightRunning -or $script:CfgRestartRequired -or $script:EDIT_ROW_INDEX -ge 0){return}
    [void]$Grid.CommitEdit([Windows.Controls.DataGridEditingUnit]::Cell,$true)
    [void]$Grid.CommitEdit([Windows.Controls.DataGridEditingUnit]::Row,$true)
    $rows=@($script:table.Rows|Where-Object{$_.Traiter})
    if(-not $rows.Count){Show-MsgInfo 'Cochez les lignes à contrôler.';return}
    if($rows.Count -gt 200){Show-MsgWarning 'Contrôlez au maximum 200 lignes à la fois. Aucun contrôle lancé.';return}
    try {$items=@(foreach($r in $rows){
        $d=Update-PestoQueueRenamePlan $r
        $o=[ordered]@{}
        foreach($c in @('Nom_du_PC','Nouveau_Nom','OU_Actuelle','OU_Destination','Objet_GUID')){$o[$c]=[string]$r[$c]}
        foreach($c in @('Renommer','Deplacer','Reboot')){$o[$c]=[bool]$r[$c]}
        $o.Key=Get-PestoPlanSignature $r
        [pscustomobject]$o
    })}catch{Show-MsgError ('Préparation du contrôle impossible : '+$_.Exception.Message);return}
    if(-not $script:PreflightCache -or $script:PreflightCache.Count -gt 10000){$script:PreflightCache=@{}}
    $script:PreflightGeneration=[int]$script:PreflightGeneration+1
    $context=[pscustomobject]@{Generation=$script:PreflightGeneration;Keys=@($items|ForEach-Object{$_.Key})}
    $script:PreflightRunning=$true;$script:PreflightStarted=Get-Date
    $script:PreflightProgress=New-PestoPreflightProgress -Total $items.Count
    $context|Add-Member -NotePropertyName Progress -NotePropertyValue $script:PreflightProgress
    $script:PreflightContext=$context;$script:PreflightTimeout=Get-PestoPreflightBudget $items.Count
    Set-PestoQueueUiLocked $true;Update-QueueButtons;Start-PestoPilotagePulse
    if($script:GUI) {
        $results=@(foreach($item in $items){
            $d=Get-PestoRenameMoveDecision -Computer $item.Nom_du_PC -NewName $item.Nouveau_Nom -CurrentOU $item.OU_Actuelle -TargetOU $item.OU_Destination -Rename $item.Renommer -Move $item.Deplacer -InDomain $script:INDOMAIN
            $errors=@(Test-QueueRowSafe -Nom $item.Nom_du_PC -NewName $item.Nouveau_Nom -OU $item.OU_Destination -Ren $item.Renommer -Move $item.Deplacer)
            if(-not $d.Valid){$errors+=@($d.Error)}
            [pscustomobject]@{Key=$item.Key;State=$(if($errors.Count){'BLOQUÉ'}else{'DÉMO'});Detail=('Données fictives, aucun accès AD. '+($errors -join ' | '));Guid='';ObservedOU='';Utc=[DateTime]::UtcNow.ToString('o')}
        })
        Complete-PestoQueuePreflight -Result ([pscustomobject]@{Results=$results}) -Context $context
        return
    }
    $ou=@{};foreach($key in $script:OU.Keys){$ou[$key]=$script:OU[$key]}
    $ouv=@{};foreach($key in $script:OUV.Keys){$ouv[$key]=$script:OUV[$key]}
    $req=[pscustomobject]@{Items=$items;DC=$script:DC;Domain=$script:DOMAINE;Credential=$script:cred;InDomain=[bool]$script:INDOMAIN;
        Prefix=$script:PREFIXE;PRD=[bool]$script:PRD;OU=$ou;OUSite=$ouv;ClearProtection=[bool]$script:CLEAR_PROTECTION;EntraPolicy=[string](@($script:CFG.CONF)[0].EntraPolicy);AllowPasswordTaskFallback=(ConvertTo-PestoPolicy $script:CFG.POLICY).AllowPasswordTaskFallback;Host=$env:COMPUTERNAME;
        ADLoaderSource=(Get-PestoADLoaderSource);ADModulePath=(Join-Path $BasePath 'ActiveDirectory.psd1');Progress=$script:PreflightProgress}
    try {
        [void](Start-PestoAsyncOperation -Name 'QueuePreflight' -ScriptBlock $script:PestoPreflightWorker -ArgumentList @($req,(Get-PestoPreflightSource)) -TimeoutSec $script:PreflightTimeout -CallbackContext $context `
            -OnSuccess {param($r,$ctx) Complete-PestoQueuePreflight -Result $r -Context $ctx} `
            -OnError {param($e,$ctx) Complete-PestoQueuePreflight -Failure $e -Context $ctx})
    }catch{Complete-PestoQueuePreflight -Failure $_ -Context $context}
}

function Complete-PestoQueuePreflight {
    param($Result,$Failure,$Context)
    if(-not $Context -or $Context.Generation -ne $script:PreflightGeneration){return}
    try {
        $interrupted=[bool]$Failure
        if($interrupted){
            $script:PreflightThenExecute=$false
            if($Context.Progress){$Context.Progress.Cancelled=$true;$Result=[pscustomobject]@{Results=@($Context.Progress.Results.ToArray())}}else{$Result=[pscustomobject]@{Results=@()}}
        }
        if(-not $Result -or (-not $interrupted -and @($Result.Results).Count -ne @($Context.Keys).Count)){throw 'Le contrôle n''a pas renvoyé un résultat complet. Aucune ligne déclarée vérifiée.'}
        $results=@{};foreach($r in @($Result.Results)){
            if(-not $r.Key -or $r.Key -notin $Context.Keys -or $results.ContainsKey($r.Key) -or $r.State -notin @('VÉRIFIÉ','AVERTISSEMENT','BLOQUÉ','DÉMO')){throw 'Résultat de contrôle invalide ou dupliqué.'}
            $at=[DateTimeOffset]::MinValue
            if(-not [DateTimeOffset]::TryParse([string]$r.Utc,[ref]$at)){throw 'Horodatage du contrôle invalide.'}
            if($r.Guid){$g=[Guid]::Empty;if(-not [Guid]::TryParse([string]$r.Guid,[ref]$g) -or $g -eq [Guid]::Empty){throw 'GUID du contrôle invalide.'}}
            $results[$r.Key]=$r
        }
        $applied=0
        foreach($row in @($script:table.Rows)) {
            $key=Get-PestoPlanSignature $row
            if(-not $results.ContainsKey($key)){
                if($interrupted -and $key -in $Context.Keys){$row.Precontrole='À REFAIRE';$row.Controle_Detail='Lecture interrompue avant un résultat complet pour cette ligne.';$row.Controle_Utc='';$row.Controle_Signature='';[void]$script:PreflightCache.Remove($key)}
                continue
            }
            $r=$results[$key]
            # Ne pas réécrire le GUID/OU préparé après le contrôle : cela changerait
            # silencieusement le plan. Un GUID absent peut être épinglé uniquement
            # après un contrôle sans blocage, puis on recalcule son empreinte.
            if(-not $row.Objet_GUID -and $r.Guid -and $r.State -in @('VÉRIFIÉ','AVERTISSEMENT')){$row.Objet_GUID=[string]$r.Guid}
            if($r.State -in @('VÉRIFIÉ','AVERTISSEMENT')){$row.TargetOUGuid=[string]$r.TargetOUGuid}
            $key=Get-PestoPlanSignature $row
            $row.Precontrole=[string]$r.State;$row.Controle_Detail=Protect-PestoLogText ([string]$r.Detail)
            if($row.Controle_Detail.Length -gt 8192){$row.Controle_Detail=$row.Controle_Detail.Substring(0,8192)+' [détail tronqué]'}
            $row.Controle_Utc=[string]$r.Utc;$row.Controle_Signature=$key;$row.Plan=Get-PestoRowPlanText $row ([bool]$script:INDOMAIN)
            if($r.State -in @('VÉRIFIÉ','AVERTISSEMENT','DÉMO')){
                $row.ConfigStamp=Get-PestoConfigurationSignature $script:CFG;$row.NeedsReview=$false
            }
            $script:PreflightCache[$key]=$r;$applied++
        }
        $blocked=@($Result.Results|Where-Object{$_.State -eq 'BLOQUÉ'}).Count
        $warn=@($Result.Results|Where-Object{$_.State -eq 'AVERTISSEMENT'}).Count
        $text="Contrôle terminé : $applied ligne(s), $blocked blocage(s), $warn avertissement(s). Aucun poste modifié."
        if($interrupted){$text="Contrôle interrompu : $applied résultat(s) complet(s) conservé(s) / $(@($Context.Keys).Count). Les autres lignes restent à contrôler. Aucun poste modifié."}
        Add-LogLine $text $(if($blocked -or $warn){'warn'}else{'info'});$LblQueueActivity.Text=$text;$script:LastPilotageNote=$text
        Save-PestoQueueCheckpointSafe
    }catch {
        # Ne conserver aucune approbation si l'application du lot de résultats a échoué.
        # Cela couvre aussi une ligne dont le GUID absent vient d'être épinglé.
        $errorText=Protect-PestoLogText $_.Exception.Message
        $script:PreflightThenExecute=$false
        $script:PreflightCache=@{}
        foreach($row in @($script:table.Rows)) {
            if($row.Precontrole -or (Get-PestoPlanSignature $row) -in @($Context.Keys)) {
                $row.Precontrole='À REFAIRE';$row.Controle_Detail=$errorText;$row.Controle_Utc='';$row.Controle_Signature=''
            }
        }
        $text="Contrôle interrompu : $($_.Exception.Message) Aucun poste modifié."
        Write-Log $text 'WARN' $_ 'preflight';$LblQueueActivity.Text=$text;$script:LastPilotageNote=$text
        Show-MsgWarning $text
    }finally{
        $script:PreflightRunning=$false;Stop-PestoPilotagePulse;Set-PestoQueueUiLocked $false;Sync-Grid;Update-QueueButtons
    }
    if($script:PreflightThenExecute){$script:PreflightThenExecute=$false;if($blocked -eq 0){Run-Queue}}
}

function Stop-PestoQueuePreflight {
    $script:PreflightThenExecute=$false
    if(-not $script:PreflightRunning){return}
    if($script:PreflightProgress){$script:PreflightProgress.Cancelled=$true}
    Stop-PestoAsyncOperation 'QueuePreflight'
    Complete-PestoQueuePreflight -Failure ([Exception]::new('Arrêt demandé.')) -Context $script:PreflightContext
    $script:PreflightGeneration=[int]$script:PreflightGeneration+1

}

function Invoke-PestoPilotagePulse {
    param($Sender,$EventArgs)
    try {
        if($script:PreflightRunning) {
            $p=$script:PreflightProgress;$elapsed=[int]((Get-Date)-$script:PreflightStarted).TotalSeconds
            $LblQueueActivity.Text="Lecture AD : $($p.Done)/$($p.Total) | $($p.Current) | ${elapsed} s | limite de surveillance $script:PreflightTimeout s"
        } elseif($script:Running -and $script:QueueRunState) {
            $st=$script:QueueRunState;$elapsed=[int]((Get-Date)-$st.Started).TotalSeconds
            $done=[int]$st.OkCount+[int]$st.KoCount+[int]$st.CancelCount
            $LblQueueActivity.Text="Lot $($st.RunId.Substring(0,8)) | $done/$($st.Total) terminé(s) | ${elapsed} s"
            if($script:QueueCurrentTicket -and $script:QueueCurrentTicket.Monitor){
                $m=$script:QueueCurrentTicket.Monitor
                $step=Get-PestoQueueActivityText -Monitor $m
                $LblQueueActivity.Text+="`n$step"
                if(([DateTime]::UtcNow-$m.LastHeartbeat).TotalSeconds -ge 15){
                    $m.LastHeartbeat=[DateTime]::UtcNow
                    Write-AuditLine ('ATTENTE | '+[string]$m.Computer+' | '+$step+' | interface active, résultat non reçu') 'info'
                }
            }
            if($script:QueueStopRequested){$LblQueueActivity.Text+=' | arrêt après l''action en cours'}
        }else{$Sender.Stop()}
        Update-PestoPilotage
    }catch{try{$Sender.Stop();Write-Log 'Indicateur de progression suspendu.' 'WARN' $_ 'pilotage'}catch{}}
}

function Start-PestoPilotagePulse {
    if(-not $script:PilotageTimer) {
        $script:PilotageTimer=[Windows.Threading.DispatcherTimer]::new();$script:PilotageTimer.Interval=[TimeSpan]::FromSeconds(1)
        $script:PilotageTimer.Add_Tick([EventHandler]${function:Invoke-PestoPilotagePulse})
    }
    $script:PilotageTimer.Start()
}
function Stop-PestoPilotagePulse {if($script:PilotageTimer){$script:PilotageTimer.Stop()}}

function Show-PestoBulkPlanner {
    param([string[]]$SourceNames=@())
    if($script:DirectBusy -or (Test-PestoDirectTargetBarrier)){return}

    if($script:Running -or $script:PreflightRunning -or -not $script:INDOMAIN -or (Test-PestoGlobalSafetyBarrier) -or $script:CfgRestartRequired -or $script:EDIT_ROW_INDEX -ge 0){return}
    try{$template=Get-PestoBulkContext;if(-not $template){return}}catch{Show-MsgWarning $_.Exception.Message;return}
    [xml]$bulkXaml=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Pesto | Préparer un lot" Width="1000" Height="700" MinWidth="730" MinHeight="500" WindowStartupLocation="CenterOwner" Background="{DynamicResource BgWindow}" Foreground="{DynamicResource FgText}">
 <Grid Margin="18"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="140"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
 <StackPanel><TextBlock Text="Préparer un lot" FontSize="24" FontWeight="SemiBold"/><TextBlock x:Name="Context" TextWrapping="Wrap" Margin="0,8,0,8"/><TextBlock Text="Lecture ciblée des sources et des noms sur le contrôleur de la session. L’inventaire complet n’est pas nécessaire. Les nouvelles lignes seront décochées et sans redémarrage." TextWrapping="Wrap" Foreground="{DynamicResource FgMuted}"/></StackPanel>
 <Grid Grid.Row="1" Margin="0,12,0,6"><StackPanel><CheckBox x:Name="KeepService" Content="Conserver le service source" ToolTip="Déménagement de site : garder les trois caractères du service de chaque poste." ToolTipService.ShowOnDisabled="True" ToolTipService.InitialShowDelay="450" ToolTipService.ShowDuration="30000" AutomationProperties.HelpText="Déménagement de site : garder les trois caractères du service de chaque poste."/><CheckBox x:Name="KeepNumber" Content="Conserver le numéro source" ToolTip="Garder le numéro si libre à destination ; refuser le lot en cas de conflit plutôt que renuméroter." ToolTipService.ShowOnDisabled="True" ToolTipService.InitialShowDelay="450" ToolTipService.ShowDuration="30000" AutomationProperties.HelpText="Garder le numéro si libre à destination ; refuser le lot en cas de conflit plutôt que renuméroter."/><CheckBox x:Name="KeepType" Content="Conserver le type du nom source" IsChecked="True" Margin="12,0,0,0" ToolTip="Conserver la lettre du type de chaque nom source, plutôt que forcer le type du formulaire." ToolTipService.ShowOnDisabled="True" ToolTipService.InitialShowDelay="450" ToolTipService.ShowDuration="30000" AutomationProperties.HelpText="Conserver la lettre du type de chaque nom source, plutôt que forcer le type du formulaire." AutomationProperties.AutomationId="KeepType"/></StackPanel></Grid>
 <TextBox Grid.Row="2" x:Name="Sources" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" TextWrapping="Wrap" ToolTip="Collez uniquement les noms de postes, un par ligne. Virgules, points-virgules et tabulations sont acceptés. 200 postes maximum." ToolTipService.ShowOnDisabled="True" ToolTipService.InitialShowDelay="450" ToolTipService.ShowDuration="30000" AutomationProperties.HelpText="Collez uniquement les noms de postes, un par ligne. Virgules, points-virgules et tabulations sont acceptés. 200 postes maximum." AutomationProperties.Name="Noms de postes à préparer" AutomationProperties.AutomationId="Sources"/>
 <DockPanel Grid.Row="3" Margin="0,10,0,10"><Button x:Name="Prepare" Content="Construire le plan" Style="{DynamicResource Btn}" Padding="14,8" DockPanel.Dock="Left" ToolTip="Lire les sources et les conflits de noms puis construire un aperçu. Aucun poste n'est modifié et aucune ligne n'est encore ajoutée." ToolTipService.ShowOnDisabled="True" ToolTipService.InitialShowDelay="450" ToolTipService.ShowDuration="30000" AutomationProperties.HelpText="Lire les sources et les conflits de noms puis construire un aperçu. Aucun poste n'est modifié et aucune ligne n'est encore ajoutée." AutomationProperties.AutomationId="Prepare"/><TextBlock x:Name="Status" TextWrapping="Wrap" Margin="14,0,0,0" ToolTip="Résultat de la préparation locale du lot, pas un résultat de mutation AD." ToolTipService.ShowOnDisabled="True" ToolTipService.InitialShowDelay="450" ToolTipService.ShowDuration="30000" AutomationProperties.HelpText="Résultat de la préparation locale du lot, pas un résultat de mutation AD." AutomationProperties.AutomationId="Status"/></DockPanel>
 <DataGrid Grid.Row="4" x:Name="Preview" IsReadOnly="True" AutoGenerateColumns="False" CanUserAddRows="False" EnableRowVirtualization="True" ToolTip="Aperçu du lot préparé. Il faut ajouter les lignes à la file puis les sélectionner avant exécution." ToolTipService.ShowOnDisabled="True" ToolTipService.InitialShowDelay="450" ToolTipService.ShowDuration="30000" AutomationProperties.HelpText="Aperçu du lot préparé. Il faut ajouter les lignes à la file puis les sélectionner avant exécution." AutomationProperties.Name="Aperçu du lot préparé" AutomationProperties.AutomationId="Preview"><DataGrid.Columns><DataGridTextColumn Header="Poste source" Binding="{Binding Nom_du_PC}" Width="155"/><DataGridTextColumn Header="Nouveau nom" Binding="{Binding Nouveau_Nom}" Width="155"/><DataGridTextColumn Header="Plan" Binding="{Binding Plan}" Width="175"/><DataGridTextColumn Header="OU source" Binding="{Binding OU_Actuelle}" Width="*"/><DataGridTextColumn Header="OU choisie" Binding="{Binding OU_Destination}" Width="*"/></DataGrid.Columns></DataGrid>
 <StackPanel Grid.Row="5" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0"><Button x:Name="Apply" Content="Ajouter les lignes décochées" IsEnabled="False" Style="{DynamicResource BtnAdd}" Margin="0,0,12,0" ToolTip="Ajouter uniquement le plan affiché. Toutes les nouvelles lignes arrivent décochées, sans redémarrage." ToolTipService.ShowOnDisabled="True" ToolTipService.InitialShowDelay="450" ToolTipService.ShowDuration="30000" AutomationProperties.HelpText="Ajouter uniquement le plan affiché. Toutes les nouvelles lignes arrivent décochées, sans redémarrage." AutomationProperties.AutomationId="Apply"/><Button Content="Fermer" IsCancel="True" Style="{DynamicResource Btn}" ToolTip="Fermer cette fenêtre sans exécuter la file." ToolTipService.ShowOnDisabled="True" ToolTipService.InitialShowDelay="450" ToolTipService.ShowDuration="30000" AutomationProperties.HelpText="Fermer cette fenêtre sans exécuter la file."/></StackPanel>
 </Grid>
</Window>

'@
    $w=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($bulkXaml));$w.Owner=$Win;$w.Resources=$Win.Resources
    $state=[pscustomobject]@{Window=$w;Template=$template;Sources=$w.FindName('Sources');KeepType=$w.FindName('KeepType');KeepService=$w.FindName('KeepService');KeepNumber=$w.FindName('KeepNumber');
        Preview=$w.FindName('Preview');Status=$w.FindName('Status');Apply=$w.FindName('Apply');Candidate=$null;InputSignature='';BaseTable=$script:table;ResolvedComputers=$null;OccupiedNames=@();CandidateContext=$null;Epoch=0L;Closed=$false}
    if($SourceNames.Count){$state.Sources.Text=$SourceNames -join [Environment]::NewLine}
    $w.FindName('Context').Text="Site : $($template.Site) | service : $($template.Service) | préfixe : $($template.Prefix)`nOU sélectionnée : $($template.TargetOU)"
    $w.Tag=$state;$w.Add_Closed({param($s,$e);if($s.Tag){$s.Tag.Closed=$true;$s.Tag.ResolvedComputers=$null}})
    $w.FindName('Prepare').Tag=$state;$w.FindName('Prepare').Add_Click([Windows.RoutedEventHandler]${function:Invoke-PestoBulkPrepare})
    $state.Apply.Tag=$state;$state.Apply.Add_Click([Windows.RoutedEventHandler]${function:Invoke-PestoBulkApply})
    foreach($box in @($state.Sources)){$box.Tag=$state;$box.Add_TextChanged([Windows.Controls.TextChangedEventHandler]${function:Invalidate-PestoBulkPreview})}
    foreach($toggle in @($state.KeepService,$state.KeepNumber)){$toggle.Tag=$state;$toggle.Add_Checked([Windows.RoutedEventHandler]${function:Invalidate-PestoBulkPreview});$toggle.Add_Unchecked([Windows.RoutedEventHandler]${function:Invalidate-PestoBulkPreview})}
    $state.KeepType.Tag=$state;$state.KeepType.Add_Checked([Windows.RoutedEventHandler]${function:Invalidate-PestoBulkPreview});$state.KeepType.Add_Unchecked([Windows.RoutedEventHandler]${function:Invalidate-PestoBulkPreview})
    [void](Show-PestoHostedWindow $w)
}

function Invalidate-PestoBulkPreview {
    param($Sender,$EventArgs)
    $s=$Sender.Tag;if(-not$s){return};$s.Epoch=[long]$s.Epoch+1;$s.Candidate=$null;$s.CandidateContext=$null;$s.ResolvedComputers=$null;$s.OccupiedNames=@()
    $s.Apply.IsEnabled=$false;$s.Preview.ItemsSource=$null;$s.Status.Text='Construisez le plan après toute modification.'
}

function Invoke-PestoBulkPlanFromState {
    param($State,[string[]]$Names)
    $s=$State;$s.Candidate=$null;$s.Preview.ItemsSource=$null;$s.Apply.IsEnabled=$false
    $argsPlan=@{};foreach($key in $s.Template.Keys){$argsPlan[$key]=$s.Template[$key]}
    $argsPlan.Names=$Names;$argsPlan.Existing=$script:table
    $argsPlan.Computers=if($script:GUI -or $script:SIM){@($script:Computers)+@($script:ComputersNoms)}else{@($s.ResolvedComputers)}
    $argsPlan.ReservedNames=@($s.OccupiedNames)+@(foreach($reserved in @($script:SharedNameOthers.Keys)){if(Test-PestoNameReservedByOther $reserved){$reserved}})
    $argsPlan.KeepService=[bool]$s.KeepService.IsChecked;$argsPlan.KeepNumber=[bool]$s.KeepNumber.IsChecked;$argsPlan.KeepType=[bool]$s.KeepType.IsChecked
    $s.Candidate=New-PestoBulkPlan @argsPlan;$s.BaseTable=$script:table;$s.Preview.ItemsSource=$s.Candidate.DefaultView
    $moves=@($s.Candidate.Rows|Where-Object{$_.Deplacer}).Count
    $s.Status.Text="$($s.Candidate.Rows.Count) renommage(s), $moves déplacement(s). 0 redémarrage. Noms retenus dans ce plan uniquement ; nouveau contrôle avant exécution."
    $s.Apply.IsEnabled=$true
}

function Invoke-PestoBulkPrepare {
    param($Sender,$EventArgs)
    if(-not($script:GUI -or $script:SIM)){Invoke-PestoBulkAdRead $Sender $EventArgs;return}
    $s=$Sender.Tag;$s.ResolvedComputers=$null;$s.OccupiedNames=@()
    try{$names=@(ConvertFrom-PestoComputerList -Text $s.Sources.Text);$s.CandidateContext=New-PestoBulkReadContext $s $names;Invoke-PestoBulkPlanFromState $s $names}
    catch{$s.Candidate=$null;$s.Apply.IsEnabled=$false;$s.Status.Text=$_.Exception.Message}
}

function New-PestoBulkReadContext {
    param($State,[string[]]$Names)
    [pscustomobject]@{Window=$State.Window;Names=$Names;Sources=[string]$State.Sources.Text;
        Epoch=[long]$State.Epoch;KeepType=[bool]$State.KeepType.IsChecked;KeepService=[bool]$State.KeepService.IsChecked;KeepNumber=[bool]$State.KeepNumber.IsChecked;
        ConfigStamp=(Get-PestoConfigurationSignature $script:CFG);Table=$script:table;TableStamp=(Get-PestoQueueContentStamp $script:table);
        DC=[string]$script:DC;Domain=[string]$script:DOMAINE;Credential=$script:cred;Closed=$false}
}
function Test-PestoBulkAdContext {
    param($Context)
    if(-not$Context -or $Context.Closed){return $false};$s=$Context.Window.Tag
    if(-not$s -or $s.Closed -or [long]$s.Epoch -ne [long]$Context.Epoch){return $false}
    if([string]$s.Sources.Text -cne $Context.Sources){return $false}
    foreach($key in @('KeepType','KeepService','KeepNumber')){if([bool]$s.$key.IsChecked -ne [bool]$Context.$key){return $false}}
    if($Context.DC -cne [string]$script:DC -or $Context.Domain -cne [string]$script:DOMAINE -or -not[object]::ReferenceEquals($script:cred,$Context.Credential)){return $false}
    if($Context.ConfigStamp -cne (Get-PestoConfigurationSignature $script:CFG) -or -not[object]::ReferenceEquals($script:table,$Context.Table)){return $false}
    return ($Context.TableStamp -ceq (Get-PestoQueueContentStamp $script:table))
}

function Invoke-PestoBulkAdRead {
    param($Sender,$EventArgs)
    $s=$Sender.Tag;$s.Candidate=$null;$s.CandidateContext=$null;$s.ResolvedComputers=$null;$s.OccupiedNames=@();$s.Apply.IsEnabled=$false;$s.Preview.ItemsSource=$null
    try{
        if($script:GUI -or $script:SIM -or -not$script:INDOMAIN -or -not$script:DC){throw 'Lecture AD ciblée indisponible dans ce contexte.'}
        if(Test-PestoAsyncOperationRunning 'BulkSourceRead'){throw 'Une lecture est déjà en cours. Réessayez après sa fin.'}
        $names=@(ConvertFrom-PestoComputerList -Text $s.Sources.Text)
        if($names.Count -gt (ConvertTo-PestoPolicy $script:CFG.POLICY).MaxBatch){throw 'Nombre de sources supérieur à MaxBatch.'}
        $context=New-PestoBulkReadContext $s $names
        $template=@{};foreach($key in $s.Template.Keys){$template[$key]=$s.Template[$key]}
        $s.Status.Text='Lecture des sources et des conflits de noms dans l’’AD…'
        $started=Invoke-PestoBulkSourceRead -Names $names -Domain $context.Domain -DC $context.DC -Credential $script:cred -Template $template `
            -KeepType $context.KeepType -KeepService $context.KeepService -KeepNumber $context.KeepNumber -Context $context `
            -OnSuccess ${function:Complete-PestoBulkAdRead} -OnError ${function:Fail-PestoBulkAdRead}
        if(-not$started){throw 'Lecture non démarrée. Réessayez.'}
    }catch{$s.Status.Text=$_.Exception.Message}
}

function Complete-PestoBulkAdRead {
    param($Result,$Context)
    if(-not(Test-PestoBulkAdContext $Context)){return}
    $s=$Context.Window.Tag
    try{
        $values=@($Result)
        if($values.Count -ne 1 -or -not$values[0].Ok -or $values[0].Truncated -or $values[0].DC -cne $Context.DC -or $values[0].Domain -cne $Context.Domain -or @($values[0].Computers).Count -ne $Context.Names.Count){throw 'Lecture ciblée incomplète ou incohérente : aucun aperçu.'}
        $s.ResolvedComputers=@($values[0].Computers);$s.OccupiedNames=@($values[0].OccupiedNames);$s.CandidateContext=$Context
        Invoke-PestoBulkPlanFromState $s $Context.Names
    }catch{$s.Candidate=$null;$s.CandidateContext=$null;$s.Apply.IsEnabled=$false;$s.Status.Text=$_.Exception.Message}
}

function Fail-PestoBulkAdRead {
    param($Failure,$Context)
    if(-not(Test-PestoBulkAdContext -Context $Context)){return}
    $s=$Context.Window.Tag;$s.ResolvedComputers=$null;$s.Candidate=$null;$s.Apply.IsEnabled=$false
    $msg=if($Failure -is [Management.Automation.ErrorRecord]){$Failure.Exception.Message}else{[string]$Failure}
    $s.Status.Text='Lecture AD ciblée échouée : '+$msg+'. Aucun nom n''est déclaré libre.'
}
function Invoke-PestoBulkApply {
    param($Sender,$EventArgs)
    $s=$Sender.Tag
    if(-not $s.Candidate -or $script:Running -or $script:PreflightRunning -or (Test-PestoGlobalSafetyBarrier) -or $script:CfgRestartRequired){return}
    try {
        if(-not(Test-PestoBulkAdContext $s.CandidateContext)){throw 'La file, le formulaire ou la configuration a changé. Reconstruisez le plan.'}
        if(-not [object]::ReferenceEquals($script:table,$s.BaseTable)){throw 'La file a changé. Reconstruisez le plan.'}
        # Conflits revérifiés sans recalculer des noms différents de l'aperçu.
        $sources=@{};$targets=@{}
        foreach($r in $script:table.Rows){$sources[[string]$r.Nom_du_PC]=$true;if($r.Renommer){$targets[[string]$r.Nouveau_Nom]=$true}}
        foreach($r in $s.Candidate.Rows){if($sources.ContainsKey([string]$r.Nom_du_PC) -or $targets.ContainsKey([string]$r.Nouveau_Nom)){throw 'Conflit avec la file actuelle. Reconstruisez le plan.'}}
        if($script:table.Rows.Count+$s.Candidate.Rows.Count -gt 5000){throw 'La file dépasserait 5 000 lignes.'}
        $copy=$script:table.Copy();foreach($r in $s.Candidate.Rows){$copy.ImportRow($r)}
        $count=$s.Candidate.Rows.Count
        $undoBefore=$script:table.Copy()
        $script:table=$copy;$Grid.ItemsSource=$copy.DefaultView;$script:NmUsedSrc=$null
        Save-PestoQueueCheckpointSafe;Update-PestoQueueFilter;Sync-Grid;Update-QueueButtons
        Save-PestoQueueUndo -Before $undoBefore -Reason 'Ajout du lot préparé'
        Add-LogLine "Lot préparé : $count ligne(s) ajoutée(s), toutes décochées et sans redémarrage." 'info'
        $s.Window.Close()
    }catch{$s.Apply.IsEnabled=$false;$s.Status.Text=$_.Exception.Message}
}

function Export-PestoHtmlReport {
    if($script:Running -or $script:PreflightRunning -or -not $script:table.Rows.Count){return}
    $dlg=[Microsoft.Win32.SaveFileDialog]::new();$dlg.Filter='Rapport HTML autonome (*.html)|*.html';$dlg.FileName='Pesto_bilan_'+(Get-Date -Format 'yyyyMMdd_HHmmss')+'.html'
    if(-not $dlg.ShowDialog()){return}
    try {
        foreach($r in $script:table.Rows){$r.Plan=Get-PestoRowPlanText $r ([bool]$script:INDOMAIN)}
        $mode=if($script:GUI){'DÉMO'}elseif($script:SIM){'SIMULATION'}else{'RÉEL'}
        $html=New-PestoQueueReportHtml -Rows @($script:table.Rows) -Domain $script:DOMAINE -Server $script:DC -Version $script:Pesto_VERSION -ContextMode $mode
        Write-PestoAtomicText -Path $dlg.FileName -Text $html
        Add-LogLine "Bilan de toute la file exporté : $($dlg.FileName)" 'info'
        Show-MsgInfo "Rapport créé :`n$($dlg.FileName)`n`nIl contient les noms des postes et les chemins AD. Diffusion interne uniquement."
    }catch{Show-MsgError $_.Exception.Message;Write-Log 'Export du bilan HTML impossible.' 'ERROR' $_ 'rapport'}
}

function Save-PestoRunHistory {
    param($State)
    if(-not $State){return}
    # Synthèses seulement, pas de credential ni de copie du contexte de worker.
    $path=Join-Path (Get-PestoStateDirectory) 'history-v1.json';$entries=@()
    if(Test-Path -LiteralPath $path) {
        if((Get-Item -LiteralPath $path).Length -gt 2MB){throw 'Historique local trop volumineux (2 Mio).'}
        $old=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json
        if($old.Schema -ne 1 -or $old.Domain -ine $script:DOMAINE){throw 'Schéma ou domaine de l''historique incompatible.'}
        $entries=@($old.Entries|Where-Object{$_.RunId -ne $State.RunId}|Select-Object -Last 99)
    }
    $entry=[pscustomobject]@{RunId=[string]$State.RunId;Mode=[string]$State.Mode;Utc=[DateTime]::UtcNow.ToString('o');
        Total=[int]$State.Total;Ok=[int]$State.OkCount;Failed=[int]$State.KoCount;NotStarted=[int]$State.CancelCount;Locked=([bool]$script:MutationUncertain -or [bool]$script:JoinLocked)}
    $data=[ordered]@{Schema=1;Domain=$script:DOMAINE;Entries=@($entries)+@($entry)}
    Write-PestoAtomicText -Path $path -Text ($data|ConvertTo-Json -Depth 5)
}
function Show-PestoRunHistory {
    try {
        $path=Join-Path (Get-PestoStateDirectory) 'history-v1.json'
        if(-not(Test-Path -LiteralPath $path)){Show-MsgInfo (Get-PestoHistoryEmptyText);return}
        if((Get-Item -LiteralPath $path).Length -gt 2MB){throw 'Historique trop volumineux.'}
        $data=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json
        if($data.Schema -ne 1 -or $data.Domain -ine $script:DOMAINE){throw 'Historique incompatible avec ce domaine.'}
        $lines=[Collections.Generic.List[string]]::new();$lines.Add('Les 100 derniers lots terminés, dans cette installation et ce profil.');$lines.Add('Synthèses locales, sans reprise automatique. Un arrêt brutal peut empêcher la synthèse ; le checkpoint et le journal restent prioritaires.');$lines.Add('')
        foreach($e in @($data.Entries|Sort-Object Utc -Descending)){$lines.Add("$($e.Utc) | $($e.Mode) | $($e.Total) action(s) | $($e.Ok) OK / $($e.Failed) échec(s) / $($e.NotStarted) non lancée(s) | verrou=$($e.Locked)`r`nLot : $($e.RunId)`r`n")}
        Show-PestoTextReport 'Historique des lots' ($lines -join "`r`n")
    }catch{Show-MsgError $_.Exception.Message}
}


function Get-RootDir {
    <# Répertoire du moteur : wad. Pesto.exe est le seul point d’entrée public à la racine. #>
    if ($PSCommandPath -and (Split-Path $PSCommandPath -Leaf) -like '*.ps1') { return $PSScriptRoot }
    return [System.IO.Path]::GetDirectoryName(
        [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
}

function Remove-ADModuleSafe { Get-Module | Where-Object Name -eq 'ActiveDirectory' | Remove-Module -ErrorAction SilentlyContinue | Out-Null }
function Quit { param([int]$Code = 0) try { Close-PestoStartupWindow } catch {}; Remove-ADModuleSafe; exit $Code }
function Convert-Value-TF {
    <# Convertit une valeur booléenne issue du JSON/CSV en vrai [bool].
       Une valeur inconnue ne doit jamais rester une chaîne non vide (qui serait
       évaluée à $true par PowerShell). Avec -Strict, une valeur invalide lève
       une erreur explicite ; sinon $Default est utilisé. #>
    param(
        [AllowNull()]$Value,
        [bool]$Default = $false,
        [switch]$Strict
    )
    if ($null -eq $Value) { return $Default }
    if ($Value -is [bool]) { return [bool]$Value }
    if ($Value -is [byte] -or $Value -is [int16] -or $Value -is [int32] -or $Value -is [int64]) {
        if ([int64]$Value -eq 1) { return $true }
        if ([int64]$Value -eq 0) { return $false }
    }
    $txt = "$Value".Trim().ToLowerInvariant()
    switch -Regex ($txt) {
        '^(true|1|yes|oui|on)$'  { return $true }
        '^(false|0|no|non|off)$' { return $false }
        default {
            if ($Strict) { throw "Valeur booléenne invalide : '$Value'." }
            return $Default
        }
    }
}

# ─── Boîtes de dialogue WPF standardisées ────────────────────────────────────
function Show-MsgError {
    param([string]$Msg,[string]$Title='Erreur')
    if($Win -and (Get-Command Show-PestoUsefulError -CommandType Function -ErrorAction SilentlyContinue)){
        Show-PestoUsefulError -Message $Msg -Title $Title
    }else{[void][Windows.MessageBox]::Show($Msg,$Title,'OK','Error')}
}
function Show-MsgWarning {
    param([string]$Msg,[string]$Title='Pesto')
    if($Win -and $Win.IsVisible -and $Win.IsActive -and (Get-Command Show-PestoPanel -ErrorAction SilentlyContinue)){[void](Show-PestoPanel -Title $Title -Body $Msg)}
    else{[void][Windows.MessageBox]::Show($Msg,$Title,'OK','Information')}
}
function Show-MsgInfo {
    param([string]$Msg,[string]$Title='Pesto')
    if($Win -and $Win.IsVisible -and $Win.IsActive -and (Get-Command Show-PestoPanel -ErrorAction SilentlyContinue)){[void](Show-PestoPanel -Title $Title -Body $Msg)}
    else{[void][Windows.MessageBox]::Show($Msg,$Title,'OK','Information')}
}
function Show-PestoOutcome {
    param([string]$Title,[string]$Message)
    # Au retour d'un worker la fenêtre est souvent visible sans être active : MessageBox sans owner passe alors derrière.
    if(-not $Message){return}
    if(-not $Title){$Title='Pesto'}
    if($Win -and $Win.IsVisible -and (Get-Command Show-PestoPanel -ErrorAction SilentlyContinue)){
        try{[void](Show-PestoPanel -Title $Title -Body $Message);return}catch{}
    }
    if($Win -and $Win.IsVisible){
        try{[void][Windows.MessageBox]::Show($Win,$Message,$Title,[Windows.MessageBoxButton]::OK,[Windows.MessageBoxImage]::Information)}catch{}
    }
}

function Confirm-YesNo {
    param([string]$Msg,[bool]$Confirm,[string]$AcceptText='Confirmer',[object[]]$SummaryRows=@())
    if(-not $Confirm){return $true}
    if(-not $Win -or -not $Win.IsVisible){return ([Windows.MessageBox]::Show($Msg,'Confirmation','YesNo','Warning','No') -eq 'Yes')}
    if($Win.IsActive -and (Get-Command Show-PestoPanel -ErrorAction SilentlyContinue)){return [bool](Show-PestoPanel -Title 'Vérifier avant de confirmer' -Body $Msg -AcceptText $AcceptText -SummaryRows $SummaryRows).Accepted}
    [xml]$x=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Pesto · Confirmer l’action" Width="640" SizeToContent="Height" ResizeMode="NoResize" WindowStartupLocation="CenterOwner" Background="{DynamicResource BgWindow}" Foreground="{DynamicResource FgText}" FontFamily="Segoe UI" FontSize="13">
<Grid Margin="22"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
<TextBlock Text="Vérifier avant de confirmer" FontSize="21" FontWeight="SemiBold" Margin="0,0,0,14"/>
<ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" MaxHeight="420"><TextBlock x:Name="ConfirmText" TextWrapping="Wrap"/></ScrollViewer>
<WrapPanel Grid.Row="2" HorizontalAlignment="Right" Margin="0,18,0,0"><Button Content="Annuler" IsCancel="True" IsDefault="True" MinWidth="100" ToolTip="Ne pas lancer l’action." ToolTipService.ShowOnDisabled="True" ToolTipService.InitialShowDelay="450" ToolTipService.ShowDuration="30000" AutomationProperties.HelpText="Ne pas lancer l’action."/><Button x:Name="ConfirmRun" Content="Confirmer" MinWidth="110" Margin="8,0,0,0" ToolTip="Autoriser uniquement l’action décrite dans ce récapitulatif." ToolTipService.ShowOnDisabled="True" ToolTipService.InitialShowDelay="450" ToolTipService.ShowDuration="30000" AutomationProperties.HelpText="Autoriser uniquement l’action décrite dans ce récapitulatif."/></WrapPanel>
</Grid></Window>
'@
    $w=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($x));$w.Owner=$Win;$w.Resources=$Win.Resources
    $w.MaxHeight=[Windows.SystemParameters]::WorkArea.Height-24;$w.MaxWidth=[Windows.SystemParameters]::WorkArea.Width-24
    $w.FindName('ConfirmText').Text=$Msg;$w.FindName('ConfirmRun').Content=$AcceptText
    $w.FindName('ConfirmRun').Add_Click({param($s,$e);[Windows.Window]::GetWindow($s).DialogResult=$true})
    Set-WindowIcon $w
    return ($w.ShowDialog() -eq $true)
}

function Invoke-DoEvents {
    <# Équivalent WPF de Application.DoEvents() : vide la file du Dispatcher
       pour que l'interface se redessine pendant un traitement synchrone.
       PROTÉGÉ : PushFrame lève InvalidOperationException si le dispatcher est en
       cours de suspension (DisableProcessing, réentrance depuis un handler). Dans
       ce cas on ne fait rien plutôt que de planter (le redraw se fera plus tard). #>
    $disp = [System.Windows.Threading.Dispatcher]::CurrentDispatcher
    if ($disp.HasShutdownStarted -or $disp.HasShutdownFinished) { return }
    try {
        $frame = New-Object System.Windows.Threading.DispatcherFrame
        $cb = [System.Windows.Threading.DispatcherOperationCallback]{ param($f) $f.Continue = $false; return $null }
        [void]$disp.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, $cb, $frame)
        [System.Windows.Threading.Dispatcher]::PushFrame($frame)
    } catch [System.InvalidOperationException] {
        # Dispatcher suspendu (réentrance) : on abandonne silencieusement le pompage.
    } catch { }
}

function Wait-Pumped {
    <# Attente non bloquante : laisse l'UI vivre pendant la pause (réplication AD). #>
    param([double]$Seconds = 1)
    $deadline = [DateTime]::Now.AddSeconds($Seconds)
    while ([DateTime]::Now -lt $deadline) { Invoke-DoEvents; Start-Sleep -Milliseconds 60 }
}
function Set-BusyState {
    <# Curseur d'attente réentrant : un appel imbriqué ne peut plus effacer le
       curseur d'un traitement parent encore actif. #>
    param([bool]$Busy = $true)
    if ($null -eq $script:BusyDepth) { $script:BusyDepth = 0 }
    if ($Busy) { $script:BusyDepth++ }
    else { $script:BusyDepth = [Math]::Max(0, [int]$script:BusyDepth - 1) }

    [System.Windows.Input.Mouse]::OverrideCursor =
        if ($script:BusyDepth -gt 0) { [System.Windows.Input.Cursors]::Wait } else { $null }
}



# ─── Moteur asynchrone WPF / runspaces ───────────────────────────────────────
# Les opérations réseau/AD ne doivent jamais tourner sur le Dispatcher WPF.
# Les lectures utilisent MTA ; QueueAction utilise STA pour l'élévation locale.
# Les étapes transitent en mémoire partagée, les callbacks restent sur le Dispatcher. Les callbacks sont validés et encapsulés : une erreur dans un
# callback ne doit jamais faire tomber tout Pesto.
$script:PestoAsyncOperations = @{}
$script:PestoAsyncTimerOperations = @{}


# RC9 : messages en mémoire partagée. Le worker ne touche jamais un objet WPF.
# New-PestoQueueMonitor : composant séparé.

# Publish-PestoWorkerLog : composant séparé.

# Set-PestoWorkerStage : composant séparé.

# Assert-PestoWorkerMayContinue : composant séparé.

# Set-PestoQueueCancellationFence : composant séparé.

# Receive-PestoQueueEvents : composant séparé.

# Get-PestoQueueActivityText : composant séparé.

# Test-PestoQueueWorkerStillActive : composant séparé.

# Test-PestoAsyncOperationRunning : composant séparé.

# Stop-PestoAsyncOperation : composant séparé.

# Invoke-PestoAsyncCallback : composant séparé.

# Start-PestoAsyncOperation : composant séparé.

# Invoke-PestoAsyncTimerTick : composant séparé.


# Snapshot AD réutilisé au login et lors des rafraîchissements. Le worker ne
# touche jamais aux objets WPF.
# PestoDirectorySnapshotWorker : Pesto-Directory.ps1

# New-PestoDirectorySnapshotRequest : composant séparé.

###############################################################################
#  SECTION 1b — PRÉFÉRENCES INTERFACE (position, taille, splitter)
###############################################################################

function Get-PrefsFile {
    <# Retourne le chemin du fichier gp.prefs.json dans le même dossier que cfg.json. #>
    if ($script:JsonFile) { return [IO.Path]::Combine([IO.Path]::GetDirectoryName($script:JsonFile), 'gp.prefs.json') }
    return $null
}

# Save-Prefs : composant séparé.
# Load-Prefs : composant séparé.

###############################################################################
#  SECTION 2 — ACTIVE DIRECTORY (chargement module + lectures)
###############################################################################

# Ensure-ADModule : composant séparé.
# CheckDomainWMI : composant séparé.

# Get-DomainController : composant séparé.

# Get-ADParams : composant séparé.

# Test-PestoComputerName : composant séparé.

# Test-PestoGeneratedComputerName : composant séparé.
# Test-PestoOUPath : composant séparé.
# Find-ADComputerByName : composant séparé.
# Get-ComputerOU : composant séparé.
# Get-AllComputersInOU : composant séparé.
# Update-ComputersNoms : composant séparé.
# Extract-Site : composant séparé.
# Extract-Equipe : composant séparé.
# CheckOU : composant séparé.

###############################################################################
#  SECTION 3 — MATÉRIEL / CONVENTION DE NOMMAGE
#  Nom machine = [P|S][PREFIXE(6)][TAG_SITE(2)][CODE_EQUIPE(3)][NNN(3)] = 15
###############################################################################

# Types de châssis "portable" (SMBIOS) : portable, laptop, notebook, hand-held,
# docking, sub-notebook, plus les formats modernes 2-en-1 (30=tablette,
# 31=convertible, 32=détachable). Comparaison par appartenance d'entier exacte
# (l'ancien -match sur '8|9|...' pouvait correspondre à des sous-chaînes).
$script:LAPTOP_CHASSIS_IDS = @(8,9,10,11,12,14,18,21,30,31,32)

# Get-PCType : composant séparé.
function Get-SiteTag {
    <# Résout le tag 2 lettres d'un site. Les correspondances exactes sont
       prioritaires sur les motifs wildcard. PREPROD est résolu avec plusieurs
       alias (PREPROD, code de transit, <code>_PREPROD, <code>_PROD_A_NOMMER),
       ce qui corrige le cas où l'UI affichait PREPROD mais cherchait le tag de 131. #>
    param([string]$SiteName)
    $site = "$SiteName".Trim()
    if ([string]::IsNullOrWhiteSpace($site)) { return $null }

    $candidates = [System.Collections.Generic.List[string]]::new()
    $addCandidate = {
        param([string]$Value)
        $v = "$Value".Trim()
        if ($v -and -not (@($candidates) -icontains $v)) { [void]$candidates.Add($v) }
    }
    [void]$addCandidate.Invoke($site)

    $preCode = "$script:PREPRODSITE".Trim()
    if ($site -ieq 'PREPROD' -or ($preCode -and $site -ieq $preCode)) {
        [void]$addCandidate.Invoke('PREPROD')
        if ($preCode) {
            [void]$addCandidate.Invoke($preCode)
            [void]$addCandidate.Invoke("${preCode}_PREPROD")
            [void]$addCandidate.Invoke("${preCode}_PROD_A_NOMMER")
        }
    }

    $tags = if ($script:RuntimeTags) { @($script:RuntimeTags) } else { @($script:CFG.TAGS) }

    # 1) Correspondances exactes : évite qu'un wildcard trop large ne gagne.
    foreach ($candidate in $candidates) {
        foreach ($t in $tags) {
            $pattern = "$($t.Site)".Trim(); $tag = "$($t.Tag)".Trim()
            if ($pattern -ieq $candidate -and $tag -match (Get-PestoFacetPattern Site)) {
                return $tag.ToUpperInvariant()
            }
        }
    }

    # Les motifs qui produisent plusieurs codes distincts sont ambigus.
    $matching=@($(foreach($candidate in $candidates){foreach($t in $tags){
        $pattern=[string]$t.Site;$tag=[string]$t.Tag
        if($pattern -and $tag -match (Get-PestoFacetPattern Site) -and $candidate -like $pattern){$tag.ToUpperInvariant()}
    }})|Sort-Object -Unique)
    if($matching.Count -gt 1){Write-Log "Plusieurs codes TAGS correspondent à '$site'. Précisez la configuration." 'ERROR' $null 'naming';return $null}
    if($matching.Count -eq 1){return $matching[0]}

    # Compatibilité historique pour les sites ordinaires : deux dernières lettres.
    # Pour PREPROD, on refuse un repli silencieux afin d'éviter un nom faux.
    if ($site -ieq 'PREPROD' -or ($preCode -and $site -ieq $preCode)) {
        Write-Log "Aucun tag valide trouvé pour PREPROD (code '$preCode')." 'ERROR' $null 'naming'
        return $null
    }
    if ($site.Length -ge (Get-PestoNamingLayout).Convention.Widths.Site) {
        $fallback = $site.Substring($site.Length - (Get-PestoNamingLayout).Convention.Widths.Site)
        if ($fallback -match (Get-PestoFacetPattern Site)) {
            Write-Log "Aucun TAGS explicite pour '$site' : repli '$($fallback.ToUpperInvariant())'." 'WARN' $null 'naming'
            return $fallback.ToUpperInvariant()
        }
    }
    Write-Log "Impossible de déterminer un tag de site valide pour '$site'." 'ERROR' $null 'naming'
    return $null
}
function Get-AvailableMachines {
    param([array]$computers,[string]$baseName,[string]$site,[string]$equipe)
    $base=$baseName.Trim().ToUpperInvariant();if($base.Length -lt 2){return ,@()}
    try{$series=New-PestoNameSeries -Type $base.Substring(0,1) -Prefix $base.Substring(1) -Site $site -Service $equipe}catch{return ,@()}
    $layout=Get-PestoNamingLayout
    $used=[Collections.Generic.HashSet[int]]::new()
    if(Get-Command Get-PestoNameInventoryIndex -ErrorAction SilentlyContinue){$inventory=Get-PestoNameInventoryIndex $computers;if($inventory.ByBase.ContainsKey($series)){$used=$inventory.ByBase[$series]}}
    else{foreach($c in $computers){$parts=ConvertTo-PestoNameParts ([string]$c.Name);if($parts -and $parts.Base -ceq $series){[void]$used.Add($parts.Number)}}}
    $available=[Collections.Generic.List[string]]::new()
    for($i=1;$i -le $layout.MaximumNumber;$i++){if(-not $used.Contains($i)){$available.Add((New-PestoNameFromSeries $series $i))}}
    return ,$available.ToArray()
}
function Get-NameList {
    <# Combine résolution du tag et recherche des numéros disponibles. #>
    param([string]$codeSite,[string]$codeService,[array]$computers,[string]$baseName)
    $tag = Get-SiteTag -SiteName $codeSite
    $svc = "$codeService".Trim().ToUpperInvariant()
    $base = "$baseName".Trim().ToUpperInvariant()
    return Get-AvailableMachines -computers $computers -baseName $base -site $tag -equipe $svc
}

function Get-CityCodeFromComputerName {
    <# Code ville d'un nom machine conforme (parseur unique, types P, S et V).
       Un nom hors convention ne donne aucun code : pas de site deviné par position. #>
    param($compName)
    $parts=ConvertTo-PestoNameParts -Name ([string]$compName) -CurrentName
    if (-not $parts) { return $null }
    return $parts.Site.ToLowerInvariant()
}
function Find-TargetOU {
    <# Retourne le premier site dont le tag correspond au code ville. #>
    param($ous,$cityCode)
    $code = "$cityCode".Trim()
    if ($code -notmatch (Get-PestoFacetPattern Site)) { return $null }
    foreach ($ou in @($ous | Sort-Object)) {
        $name = "$ou".Trim()
        if (-not $name) { continue }
        $tag = Get-SiteTag -SiteName $name
        if ($tag -and $tag -ieq $code) { return $name }
    }
    return $null
}
function ComputerNameVSCityCode {
    <# Suggère organisme/site depuis le tag intégré au nom, uniquement si le nom
       respecte entièrement la convention Pesto. #>
    param([string]$COMPUTERNAME)
    if (-not (Test-PestoGeneratedComputerName $COMPUTERNAME)) { return }

    $cityCode = Get-CityCodeFromComputerName -compName $COMPUTERNAME
    if (-not $cityCode) { return }

    $targetOrg = $null; $targetSite = $null
    foreach ($org in @($script:Sites.Keys | Sort-Object)) {
        $site = Find-TargetOU -ous $script:Sites[$org] -cityCode $cityCode
        if ($site) { $targetOrg = $org; $targetSite = $site; break }
    }
    if (-not $targetOrg) { return }

    try {
        $pcInfo  = Get-ComputerOU -Identity $COMPUTERNAME
        $ouTest = "OU=$targetSite,$($script:OUV[$targetOrg])"
        if (-not $script:WOU -and $pcInfo.OU -ieq $ouTest) { return }
    } catch { return }

    return [PSCustomObject]@{ Organisme = $targetOrg; Site = $targetSite }
}

###############################################################################
#  SECTION 4a — ACTIONS AD (écriture). Renvoient { ExitCode, ExitMsg }.
###############################################################################

# New-ActionResult : composant séparé.


# --- Fallbacks distants via Planificateur de tâches ---------------------------
# Bloc inspiré de Rimotte : schtasks /s + XML RunOnce + /run + lecture du dernier
# code. Utilisé pour le fallback de renommage distant et pour demander un reboot
# sans dépendre de WinRM. Le comportement nominal de Pesto reste inchangé.
# ConvertTo-PestoQuotedArg : composant séparé.
# Get-PestoSecretArgIndexes : composant séparé.
# Invoke-PestoProcess : composant séparé.

# Invoke-PestoSchtasks : composant séparé.

# Get-PestoSchtasksTransportArgs : composant séparé.

# Get-PestoSchtasksHint : composant séparé.



# Test-PestoIsAdministrator : composant séparé.

# Invoke-PestoSystemTaskScript : composant séparé.

# Invoke-PestoDsregLeaveLocal : composant séparé.

# Invoke-PestoDsregLeaveBeforeRename : composant séparé.

# New-PestoRunOnceTaskXml : composant séparé.


# ConvertTo-PestoPowerShellLiteral : composant séparé.

# Get-PestoTaskRunResult : composant séparé.

# Get-PestoRemoteTaskLogTail : composant séparé.

# Invoke-RenameComputerTaskFallback : composant séparé.

# Request-ComputerReboot : composant séparé.
# Invoke-PestoElevatedDomainJoin : composant séparé.


# AddToDomain : composant séparé.
# Invoke-PestoWindowsLocalRename : composant séparé.

# RenameComputer : composant séparé.

# MoveComputer : composant séparé.

###############################################################################
#  SECTION 4b — ORCHESTRATION (décision + enchaînement)
###############################################################################
# GoJoinDomain : composant séparé.

# GoRenameOnly : composant séparé.

# GoMoveOnly : composant séparé.
# Wait-ADComputerVisible : composant séparé.

# GoRenameAndMove : composant séparé.

# Go : composant séparé.

###############################################################################
#  SECTION 5 — THÈME (clair / sombre commutable à chaud)
###############################################################################

$script:Themes = @{
    Dark = @{
        BgWindow='#121923'
        BgSidebar='#17212F'
        BgCard='#1D2A39'
        BgInput='#162130'
        BgInputRO='#202D3E'
        FgText='#EDF3FF'
        FgMuted='#B4C2D6'
        FgAccent='#8ABEFF'
        ClrBorder='#394A60'
        BtnBg='#28394D'
        BtnFg='#EDF3FF'
        BtnBorder='#465B76'
        GridBg='#1D2A39'
        GridAltBg='#213041'
        GridHeaderBg='#263649'
        GridLine='#304155'
        RowSelBg='#304C6C'
        RowSelFg='#FFFFFF'
        LogBg='#152030'
        AddBg='#0065D5'
        RunBg='#0065D5'
        RunFg='#FFFFFF'
        BadgeBg='#28394D'
        BadgeFg='#EDF3FF'
        FieldOk='#1C3C34'
        FieldKo='#492C37'
        OkFg='#89DDB4'
        ErrFg='#FF949A'
        WarnFg='#FFD18B'
        HeadFg='#8ABEFF'
        ChipOkBg='#224837'
        ChipOkFg='#9DE5BF'
        ChipWarnBg='#514027'
        ChipWarnFg='#FFDBA2'
        ChipInfoBg='#263F63'
        ChipInfoFg='#ACD1FF'
        ChipNeutralBg='#2E3D51'
        ChipNeutralFg='#D4E0F1'
        SectionFg='#8ABEFF'
        Divider='#394A60'
        Shadow='#000000'
        RowHoverBg='#2B405A'
        AccentSoft='#253D5B'
        FocusRing='#8ABEFF'
        # X5 : anneaux d'état (élément survolé, onglet, menu actifs) transparents ici ; visibles en contraste élevé seulement.
        HcStateRing='#00000000'
        HcSelStateRing='#00000000'
        TipBg='#0F1926'
        TipFg='#F3F7FF'
        TipBorder='#506780'
    }
    Light = @{
        BgWindow='#F5F7FB'
        BgSidebar='#EDF3FC'
        BgCard='#FFFFFF'
        BgInput='#FFFFFF'
        BgInputRO='#F0F3F8'
        FgText='#172B4D'
        FgMuted='#5A6C86'
        FgAccent='#0065D5'
        ClrBorder='#DCE4EF'
        BtnBg='#F7F9FD'
        BtnFg='#243B60'
        BtnBorder='#CED9E8'
        GridBg='#FFFFFF'
        GridAltBg='#FAFCFF'
        GridHeaderBg='#F3F6FB'
        GridLine='#E7EDF5'
        RowSelBg='#DCEAFF'
        RowSelFg='#172B4D'
        LogBg='#FFFFFF'
        AddBg='#0065D5'
        RunBg='#0065D5'
        RunFg='#FFFFFF'
        BadgeBg='#EDF3FC'
        BadgeFg='#172B4D'
        FieldOk='#F1FAF6'
        FieldKo='#FFF1F0'
        OkFg='#146845'
        ErrFg='#B52C32'
        WarnFg='#8A5700'
        HeadFg='#0065D5'
        ChipOkBg='#E3F5EB'
        ChipOkFg='#146845'
        ChipWarnBg='#FFF0D9'
        ChipWarnFg='#825000'
        ChipInfoBg='#E5EFFF'
        ChipInfoFg='#075BB4'
        ChipNeutralBg='#EEF2F7'
        ChipNeutralFg='#4D5F79'
        SectionFg='#0065D5'
        Divider='#E2E9F2'
        Shadow='#B3C0D4'
        RowHoverBg='#F0F6FF'
        AccentSoft='#E7F0FF'
        FocusRing='#0065D5'
        HcStateRing='#00000000'
        HcSelStateRing='#00000000'
        TipBg='#202E43'
        TipFg='#FFFFFF'
        TipBorder='#34455D'
    }
}
$script:CurrentTheme = 'Light'

function New-Brush {
    param([string]$Hex)
    [Windows.Media.Brush]$b = New-Object Windows.Media.SolidColorBrush(
        [Windows.Media.ColorConverter]::ConvertFromString($Hex))
    $b.Freeze(); return $b
}

function New-ThemeIcon {
    <# Petite icône vectorielle Soleil / Lune pour le bouton de thème. #>
    param([string]$Kind)
    $vb = New-Object Windows.Controls.Viewbox; $vb.Width = 20; $vb.Height = 20; $vb.Stretch = 'Uniform'
    $cv = New-Object Windows.Controls.Canvas; $cv.Width = 24; $cv.Height = 24
    if ($Kind -eq 'Sun') {
        $g = New-Brush '#FFB200'
        $c = New-Object Windows.Shapes.Ellipse; $c.Width = 11; $c.Height = 11; $c.Fill = $g
        [Windows.Controls.Canvas]::SetLeft($c,6.5); [Windows.Controls.Canvas]::SetTop($c,6.5); [void]$cv.Children.Add($c)
        for ($i=0; $i -lt 8; $i++) {
            $a = [math]::PI/4*$i; $l = New-Object Windows.Shapes.Line
            $l.X1 = 12+8.5*[math]::Cos($a); $l.Y1 = 12+8.5*[math]::Sin($a)
            $l.X2 = 12+11*[math]::Cos($a);  $l.Y2 = 12+11*[math]::Sin($a)
            $l.Stroke = $g; $l.StrokeThickness = 2; $l.StrokeStartLineCap='Round'; $l.StrokeEndLineCap='Round'
            [void]$cv.Children.Add($l)
        }
    } else {
        $m = New-Object Windows.Shapes.Path
        $m.Data = [Windows.Media.Geometry]::Parse('M12 3c-4.97 0-9 4.03-9 9s4.03 9 9 9c3.71 0 6.9-2.25 8.27-5.46-1.06.52-2.25.81-3.52.81-4.42 0-8-3.58-8-8 0-1.95.7-3.74 1.86-5.13C11.05 3.08 11.52 3 12 3z')
        # Couleur du texte du thème actif : lisible en clair, en sombre et en contraste élevé (une couleur fixe pâle ne l'était pas).
        $m.SetResourceReference([Windows.Shapes.Shape]::FillProperty,'FgText'); [void]$cv.Children.Add($m)
    }
    $vb.Child = $cv; return $vb
}

function Set-Theme {
    param([string]$Name)
    if(-not $script:Themes.ContainsKey($Name)){throw 'Thème effectif inconnu.'}
    $t = $script:Themes[$Name]
    foreach ($k in $t.Keys) { $Win.Resources[$k] = (New-Brush $t[$k]) }
    $script:CurrentTheme = $Name

    # Brushes "état de champ" mémorisés pour TxtPCName.
    $script:BR_FieldBg = New-Brush $t['BgInput']
    $script:BR_FieldRO = New-Brush $t['BgInputRO']
    $script:BR_FieldOk = New-Brush $t['FieldOk']
    $script:BR_FieldKo = New-Brush $t['FieldKo']

    $BtnTheme.Content = New-ThemeIcon ($(if ($Name -eq 'Dark') { 'Sun' } else { 'Moon' }))

    # ComboBox : recolorées explicitement (le chrome par défaut n'hérite pas tout).
    foreach ($cb in @($CbType,$CbOrg,$CbSite,$CbService,$CbName,$NmCmbSite,$NmCmbEquipe,$NmCmbType,$NmCmbStatut,$SetCmbDarkMode,$CmbQueueFilter)) {
        if ($cb) { $cb.Foreground = $Win.Resources['FgText']; $cb.Background = $Win.Resources['BgInput'] }
    }
    Restyle-Chips
    Update-FieldColor
    Render-Log
    if($script:PestoUxReady){Request-PestoUxRefresh}
    Sync-PestoAppearanceControls
}

# ── Pastilles d'état (chips) ─────────────────────────────────────────────────
$script:ChipKinds = @{}
function Set-Chip {
    param($Border, [string]$Text, [string]$Kind, [string]$ToolTip)
    if (-not $Border) { return }
    $Border.Child.Text = $Text
    if ($ToolTip) { $Border.ToolTip = $ToolTip }
    $script:ChipKinds[$Border.Name] = $Kind
    Restyle-OneChip $Border $Kind
}
function Restyle-OneChip {
    param($Border, [string]$Kind)
    $Border.Background      = $Win.Resources["Chip${Kind}Bg"]
    $Border.Child.Foreground = $Win.Resources["Chip${Kind}Fg"]
}
function Restyle-Chips {
    foreach ($n in @($script:ChipKinds.Keys)) {
        $b = $Win.FindName($n)
        if ($b) { Restyle-OneChip $b $script:ChipKinds[$n] }
    }
}

###############################################################################
#  SECTION 6 — JOURNAL (RichTextBox coloré, re-rendu au changement de thème)
###############################################################################

$script:LogEntries = [System.Collections.Generic.List[object]]::new()

# ── Journal persistant (audit des actions AD) ────────────────────────────────
# Trace sur disque chaque ligne du journal. Le journal à l'écran est vidé à
# chaque exécution (Clear-Log) ; le fichier, lui, conserve tout l'historique.
$script:AuditFile = $null
$script:LogLevel  = 'INFO'                                       # seuil de verbosité (DEBUG<INFO<WARN<ERROR<FATAL)
$script:LevelRank = @{ DEBUG=0; INFO=1; WARN=2; ERROR=3; FATAL=4 }

# Initialize-AuditLog : composant séparé.

# Test-PestoAuditWritable : composant séparé.

# Write-AuditLine : composant séparé.

function Get-ErrorDetail {
    <# Formate un ErrorRecord ou une Exception en bloc multi-ligne COMPLET (diagnostic prod) :
       type, message, catégorie, position dans le script, pile script, exceptions internes. #>
    param($Err)
    if (-not $Err) { return '' }
    $rec = $null; $ex = $null
    if     ($Err -is [System.Management.Automation.ErrorRecord]) { $rec = $Err; $ex = $Err.Exception }
    elseif ($Err -is [System.Exception])                         { $ex  = $Err }
    else   { return "    Detail : $Err" }
    $sb = New-Object System.Text.StringBuilder
    if ($ex) {
        [void]$sb.AppendLine("    Type      : $($ex.GetType().FullName)")
        [void]$sb.AppendLine("    Message   : $($ex.Message)")
    }
    if ($rec) {
        try { if ($rec.CategoryInfo)          { [void]$sb.AppendLine("    Categorie : $($rec.CategoryInfo)") } } catch {}
        try { if ($rec.FullyQualifiedErrorId) { [void]$sb.AppendLine("    ErrorId   : $($rec.FullyQualifiedErrorId)") } } catch {}
        try { if ($rec.InvocationInfo -and $rec.InvocationInfo.PositionMessage) {
                  foreach ($l in ($rec.InvocationInfo.PositionMessage -split "`r?`n")) { [void]$sb.AppendLine("    pos> $l") } } } catch {}
        try { if ($rec.ScriptStackTrace) {
                  foreach ($l in ($rec.ScriptStackTrace -split "`r?`n")) { [void]$sb.AppendLine("    stk> $l") } } } catch {}
    }
    $inner = if ($ex) { $ex.InnerException } else { $null }; $depth = 0
    while ($inner -and $depth -lt 5) {
        [void]$sb.AppendLine("    interne[$depth] : $($inner.GetType().FullName) : $($inner.Message)")
        $inner = $inner.InnerException; $depth++
    }
    return $sb.ToString().TrimEnd([char]13, [char]10)
}

# Write-Log : composant séparé.

# Open-AuditLog : composant séparé.

# Export-Diagnostics : composant séparé.

# Get-LogBrush : composant séparé.

# New-LogParagraph : composant séparé.
# Add-LogLine : composant séparé.
# Add-LogSeparator : composant séparé.

# Render-Log : composant séparé.

# Clear-Log : composant séparé.

###############################################################################
#  SECTION 6b — ICÔNE DE L'APPLICATION (embarquée : aucun fichier externe requis)
#  .ico multi-tailles 16/24/32/48 (barre de titre, barre des tâches, Alt-Tab).
#  NB : l'icône de l'EXE compilé dans l'Explorateur reste l'affaire de PS2EXE
#  (-iconFile icone_multi.ico) ; ceci couvre le runtime WPF (.ps1 comme .exe).
###############################################################################

$script:AppIconB64 = @'
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
'@

# Vrai conteneur ICO multi-tailles pour WM_SETICON / barre des taches.
$script:AppIconIcoB64 = @'
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
'@

function Get-AppIcon {
    <# ImageSource de l'icône embarquée (décodée une fois puis mise en cache).
       Renvoie $null en cas d'échec : l'appelant n'assigne alors rien (fenêtre
       sans icône = comportement d'avant, jamais un plantage pour une icône). #>
    if ($script:AppIcon) { return $script:AppIcon }
    try {
        $bytes = [Convert]::FromBase64String(($script:AppIconB64 -replace '\s',''))
        $ms = New-Object System.IO.MemoryStream(,$bytes)
        $frame = [System.Windows.Media.Imaging.BitmapFrame]::Create(
            $ms,
            [System.Windows.Media.Imaging.BitmapCreateOptions]::None,
            [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad)   # décodage complet -> flux libérable
        $frame.Freeze()
        $script:AppIcon = $frame
        return $script:AppIcon
    } catch {
        Write-Log "Icône embarquée indécodable (fenêtres sans icône)." 'WARN' $_ 'ui'
        return $null
    }
}


$script:PestoTaskbarIconHandles = [System.Collections.Generic.List[IntPtr]]::new()
$script:PestoAppUserModelIdSet = $false
try {
    Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
    Initialize-PestoRuntimeTypes -Root $PSScriptRoot
} catch {}

function Set-WindowIcon {
    param($Window)
    if(-not $Window){ return }
    try {
        $ic=Get-AppIcon
        if($ic){ $Window.Icon=$ic }
        if(-not $script:PestoAppUserModelIdSet -and ('Pesto.NativeShell' -as [type])){
            [void][Pesto.NativeShell]::SetCurrentProcessExplicitAppUserModelID('Pesto.GestionDesPostes')
            $script:PestoAppUserModelIdSet=$true
        }

        $w=$Window
        $iconBase64=$script:AppIconIcoB64
        $iconHandles=$script:PestoTaskbarIconHandles
        $writeIconLog=${function:Write-Log}
        $applyNative=({
            try {
                if(-not ('Pesto.NativeShell' -as [type])){ return }
                $helper=New-Object System.Windows.Interop.WindowInteropHelper($w)
                $hwnd=$helper.Handle
                if($hwnd -eq [IntPtr]::Zero){ return }

                $bytes=[Convert]::FromBase64String(($iconBase64 -replace '\s',''))
                $ms=New-Object IO.MemoryStream(,$bytes)
                $srcIcon=New-Object System.Drawing.Icon($ms)
                $small=New-Object System.Drawing.Icon($srcIcon,16,16)
                $large=New-Object System.Drawing.Icon($srcIcon,32,32)
                $hSmall=$small.Handle
                $hLarge=$large.Handle

                # Les objets Icon restent vivants jusqu'à la fermeture de la fenêtre.
                $holder=[pscustomobject]@{Stream=$ms;Source=$srcIcon;Small=$small;Large=$large;HSmall=$hSmall;HLarge=$hLarge}
                if(-not $w.Tag -or $w.Tag -is [string]){
                    # Ne pas détourner Tag si l'appelant l'utilise ; la closure suffit à garder holder vivant.
                }
                [void]$iconHandles.Add($hSmall)
                [void]$iconHandles.Add($hLarge)
                [void][Pesto.NativeShell]::SendMessage($hwnd,0x0080,[IntPtr]0,$hSmall)
                [void][Pesto.NativeShell]::SendMessage($hwnd,0x0080,[IntPtr]1,$hLarge)

                $cleanupHandles=$iconHandles
                $cleanup=({
                    try { [void][Pesto.NativeShell]::SendMessage($hwnd,0x0080,[IntPtr]0,[IntPtr]::Zero) } catch {}
                    try { [void][Pesto.NativeShell]::SendMessage($hwnd,0x0080,[IntPtr]1,[IntPtr]::Zero) } catch {}
                    try { $holder.Small.Dispose() } catch {}
                    try { $holder.Large.Dispose() } catch {}
                    try { $holder.Source.Dispose() } catch {}
                    try { $holder.Stream.Dispose() } catch {}
                    try { [void]$cleanupHandles.Remove($hSmall) } catch {}
                    try { [void]$cleanupHandles.Remove($hLarge) } catch {}
                }).GetNewClosure()
                $w.Add_Closed($cleanup)
            } catch {
                try { & $writeIconLog 'Application de l''icône Win32 impossible.' 'WARN' $_ 'ui' } catch {}
            }
        }).GetNewClosure()

        $helperNow=New-Object System.Windows.Interop.WindowInteropHelper($w)
        if($helperNow.Handle -ne [IntPtr]::Zero){ [void]$applyNative.Invoke() }
        else {
            $nativeHandler=({ [void]$applyNative.Invoke() }).GetNewClosure()
            $w.Add_SourceInitialized($nativeHandler)
        }
    } catch {
        try { Write-Log 'Application de l''icône de fenêtre impossible.' 'WARN' $_ 'ui' } catch {}
    }
}


# ─── Écran de chargement entre le login et la fenêtre principale ─────────────
# Inspiré du moniteur de démarrage ADCC : il masque totalement le temps de
# préparation post-authentification et reste affiché jusqu'au premier rendu de
# la fenêtre principale.
$script:PestoStartupWindow = $null
$script:PestoStartupCtrl = $null
$script:PestoStartupTimer = $null
$script:PestoStartupStarted = $null

function Show-PestoStartupWindow {
    if ($script:PestoStartupWindow) { return }
    try {
        $t = $script:Themes[$script:CurrentTheme]
        $accent = [string]$t['FgAccent']
        $bgWindow = [string]$t['BgWindow']
        $bgCard = [string]$t['BgCard']
        $fgText = [string]$t['FgText']
        $fgMuted = [string]$t['FgMuted']
        $border = [string]$t['ClrBorder']
        $bgInput = [string]$t['BgInputRO']

        [xml]$sxaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Pesto 1.0 — Initialisation" Width="620" Height="330" ResizeMode="NoResize" WindowStartupLocation="CenterScreen" Background="{DynamicResource BgWindow}" FontFamily="Segoe UI" FontSize="12" ShowInTaskbar="True" Topmost="True">
  <Border Margin="18" Padding="22" CornerRadius="18" Background="{DynamicResource BgCard}" BorderBrush="{DynamicResource ClrBorder}" BorderThickness="1">
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <StackPanel Grid.Row="0" HorizontalAlignment="Center" Margin="0,0,0,16">
        <TextBlock FontFamily="Segoe UI" FontWeight="SemiBold" FontSize="27" HorizontalAlignment="Center">
          <Run Text="P" Foreground="{DynamicResource FgAccent}"/><Run Text="esto" Foreground="{DynamicResource FgText}"/>
        </TextBlock>
        <TextBlock Text="Initialisation" Foreground="{DynamicResource FgMuted}" FontSize="11" HorizontalAlignment="Center" Margin="0,2,0,0"/>
      </StackPanel>

      <TextBlock Grid.Row="1" x:Name="LblStartupStage" Text="Préparation..." FontSize="16" FontWeight="SemiBold" Foreground="{DynamicResource FgText}" Margin="0,0,0,8"/>
      <ProgressBar Grid.Row="2" Height="7" IsIndeterminate="True" Foreground="{DynamicResource FgAccent}" Background="{DynamicResource BgInputRO}" BorderThickness="0" Margin="0,0,0,12" ToolTip="Progression de l’initialisation. Suivez les indications de cette fenêtre." ToolTipService.ShowOnDisabled="True" ToolTipService.InitialShowDelay="450" ToolTipService.ShowDuration="30000" AutomationProperties.HelpText="Progression de l’initialisation. Suivez les indications de cette fenêtre."/>

      <TextBox Grid.Row="3" x:Name="TxtStartupDetail" IsReadOnly="True" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" Background="{DynamicResource BgInputRO}" Foreground="{DynamicResource FgMuted}" BorderBrush="{DynamicResource ClrBorder}" BorderThickness="1" Padding="10" FontSize="11" ToolTip="Détail de l’initialisation, en lecture seule. Suivez les indications de cette fenêtre." ToolTipService.ShowOnDisabled="True" ToolTipService.InitialShowDelay="450" ToolTipService.ShowDuration="30000" AutomationProperties.HelpText="Détail de l’initialisation, en lecture seule. Suivez les indications de cette fenêtre." AutomationProperties.Name="Détail de l’initialisation" AutomationProperties.AutomationId="TxtStartupDetail"/>

      <DockPanel Grid.Row="4" Margin="0,10,0,0">
        <TextBlock x:Name="LblStartupElapsed" Text="0 s" Foreground="{DynamicResource FgMuted}" VerticalAlignment="Center"/>
        <TextBlock Text="Pesto" Foreground="{DynamicResource FgAccent}" FontWeight="SemiBold" HorizontalAlignment="Right" DockPanel.Dock="Right"/>
      </DockPanel>
    </Grid>
  </Border>
</Window>

"@
        $w = [Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $sxaml))
        $w.Resources=$Win.Resources
        Set-WindowIcon $w
        $script:PestoStartupWindow = $w
        $script:PestoStartupCtrl = [pscustomobject]@{
            Stage = $w.FindName('LblStartupStage')
            Detail = $w.FindName('TxtStartupDetail')
            Elapsed = $w.FindName('LblStartupElapsed')
        }
        $script:PestoStartupStarted = Get-Date

        $timer = New-Object System.Windows.Threading.DispatcherTimer
        $timer.Interval = [TimeSpan]::FromSeconds(1)
        $timer.Add_Tick({
            try {
                if ($script:PestoStartupCtrl -and $script:PestoStartupStarted) {
                    $script:PestoStartupCtrl.Elapsed.Text = "$([int]((Get-Date) - $script:PestoStartupStarted).TotalSeconds) s"
                }
            } catch {}
        })
        $script:PestoStartupTimer = $timer
        $timer.Start()

        [void]$w.Show()
        try { [void]$w.Activate() } catch {}
        Invoke-DoEvents
        # Le premier plan ne sert qu'à l'apparition : un démarrage peut dépasser
        # la minute ; la fenêtre ne doit pas rester accrochée au-dessus des autres.
        try { $w.Topmost = $false } catch {}
    }
    catch {
        try { Write-Log "Écran de chargement indisponible : $($_.Exception.Message)" 'WARN' $_ 'startup' } catch {}
        $script:PestoStartupWindow = $null
        $script:PestoStartupCtrl = $null
    }
}

function Set-PestoStartupStage {
    param([string]$Stage,[string]$Detail='')
    try {
        if (-not $script:PestoStartupWindow -or -not $script:PestoStartupCtrl) { return }
        if (-not [string]::IsNullOrWhiteSpace($Stage)) { $script:PestoStartupCtrl.Stage.Text = $Stage }
        if (-not [string]::IsNullOrWhiteSpace($Detail)) {
            $script:PestoStartupCtrl.Detail.AppendText("[$((Get-Date).ToString('HH:mm:ss'))] $Detail`r`n")
            $script:PestoStartupCtrl.Detail.ScrollToEnd()
        }
        if ($script:PestoStartupStarted) {
            $script:PestoStartupCtrl.Elapsed.Text = "$([int]((Get-Date) - $script:PestoStartupStarted).TotalSeconds) s"
        }
        Invoke-DoEvents
    } catch {}
}

function Close-PestoStartupWindow {
    try { if ($script:PestoStartupTimer) { $script:PestoStartupTimer.Stop() } } catch {}
    $script:PestoStartupTimer = $null
    try {
        if ($script:PestoStartupWindow) {
            $script:PestoStartupWindow.Topmost = $false
            $script:PestoStartupWindow.Close()
        }
    } catch {}
    $script:PestoStartupWindow = $null
    $script:PestoStartupCtrl = $null
    $script:PestoStartupStarted = $null
}

. (Join-Path $PSScriptRoot 'Pesto-Join.ps1')
. (Join-Path $PSScriptRoot 'Pesto-Inspection.ps1')
. (Join-Path $PSScriptRoot 'Pesto-Direct.ps1')
. (Join-Path $PSScriptRoot 'Pesto-SuiteUI.ps1')
. (Join-Path $PSScriptRoot 'Pesto-Support.ps1')

###############################################################################
#  SECTION 7 — XAML (interface)
###############################################################################

[xml]$xaml = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Pesto-Shell.xaml') -Raw -Encoding UTF8


$reader = New-Object System.Xml.XmlNodeReader $xaml
try {
    $Win = [Windows.Markup.XamlReader]::Load($reader)
    Set-WindowIcon $Win
} catch {
    [System.Windows.MessageBox]::Show("Échec du chargement de l'interface (XAML) :`n`n$($_.Exception.Message)",
        'Pesto — erreur de démarrage', 'OK', 'Error') | Out-Null
    Quit 1
}
if (-not $Win) {
    [System.Windows.MessageBox]::Show("L'interface n'a pas pu être créée (fenêtre nulle).",
        'Pesto — erreur de démarrage', 'OK', 'Error') | Out-Null
    Quit 1
}

# ── Adaptation aux petits écrans : la fenêtre ne dépasse jamais la zone de travail ──
$wa = [System.Windows.SystemParameters]::WorkArea
if ($Win.Width -gt $wa.Width) { $target=[Math]::Max(400,$wa.Width-20);$Win.MinWidth=[Math]::Min($Win.MinWidth,$target);$Win.Width=$target }
if ($Win.Height -gt $wa.Height) { $target=[Math]::Max(300,$wa.Height-20);$Win.MinHeight=[Math]::Min($Win.MinHeight,$target);$Win.Height=$target }

# ── Récupération des contrôles nommés ────────────────────────────────────────
$names = 'SidebarWidth','NavHome','NavHomeLabel','NavRename','NavRenameLabel','NavNames','NavNamesLabel',
         'NavHistory','NavHistoryLabel','NavLogs','NavLogsLabel','NavSettings','NavSettingsLabel','NavHelp',
         'UxVersion','ChipMember','ChipDomain','ChipAccount','ChipJoin','ChipSim','ChipGui','BtnLog',
         'BtnTheme','BtnHelp','MainTabs','ActionScroll','UxPageTitle','UxPageSubtitle','Step1',
         'Step1Text','Step2','Step2Text','Step3','Step3Text','Step4','Step4Text',
         'BodyGrid','ConfigPanel','ChkRemote','TxtPCName','BtnReadComputer','LblPCInfo','CbOrg',
         'CbSite','CbService','CbType','CbName','LblNameTaken','UxMoveRule','AdvancedOptions',
         'ChkRename','ChkMove','ChkReboot','BtnAdd','UxAddHint','FormSplitter','PreviewPanel',
         'UxCurrentName','UxNewName','BtnCopyNewName','UxSiteTransition','LblCurrentOU','LblTargetOU','UxActualTargetOU',
         'UxOperation','UxRebootSummary','UxNextStep','BtnInlineHelp','QueueCard','LblQueueCount','BtnPreflight',
         'BtnPreview','BtnDetails','BtnBulk','BtnCancelPreflight','TxtQueueSearch','CmbQueueFilter','LblFilterCount',
         'LblPilotage','Grid','LblEmpty','BtnCheckAll','BtnUncheckAll','ChkTechnicalColumns','QueueTools',
         'BtnEdit','BtnDelete','BtnImport','BtnExport','BtnHtmlReport','BtnHistory','BtnRetryMove',
         'BtnClear','BtnSafetyReset','BtnSafetyAck','UxExecutionMode','LblStatus','LblQueueActivity','Progress','ChkConfirm',
         'BtnRun','BtnStop','NmLblCount','NmBtnNextP','NmBtnNextS','NmBtnNextV','NmBtnCopy','NmBtnExport',
         'NmBtnRefresh','NmCmbSite','NmCmbEquipe','NmCmbType','NmCmbStatut','NmTxtSearch','NmChkAll',
         'NmLoadingPanel','NmLoadingTitle','NmLoadingDetail','NmLoadingElapsed','NmLoadingBar','NmBtnRetryNames','NmViewNote',
         'NmGrid','SetTabs','SetTxtDomaine','SetTxtADM','SetTxtPrefixe','SetTxtPreprod','SetTxtBuffer',
         'SetCmbDarkMode','SetChkDirectProd','SetTxtOUScan','SetBtnBrowseScan','SetChkDsreg','SetLblPrefixes','SetBtnTagAdd',
         'SetBtnTagDel','SetGridTags','SetBtnBaseBrowse','SetBtnBaseAdd','SetBtnBaseDel','SetGridOUBase','SetBtnSiteBrowse',
         'SetBtnSiteAdd','SetBtnSiteDel','SetGridOUSite','SetChkGUI','SetChkSim','SetChkODM','SetChkWOU',
         'SetChkBVA','SetChkGOD','SetBtnSave','SetBtnReload','SetLblStatus','LogBox','LogMnuCopy',
         'SetTxtCoordRoot','SetBtnCoordPrepare','SetBtnCoordTest','SetLblCoordStatus','SetTxtReserveMinutes','SetChkCoordRequired',
         'SetChkRandomName','SetChkReserveAD','SetChkPrecreated','SetTxtMaxBatch','SetTxtMaxReaders','SetTxtReadAttempts',
         'SetChkClearProtection','SetChkPasswordFallback','SetTxtExcludedNames','SetTxtExcludedOUs','SetTxtExcludedGroups',
         'LogMnuDiag','LogMnuClear','UxCacheCount','UxQueueTotal','UxReviewTotal','HomePrepare','HomeQueue',
         'HomeNames','HomeHistory','UxHomeContext','BtnHistoryRefresh','UxHistoryMessage','UxHistoryGrid'
foreach ($n in $names) { Set-Variable -Name $n -Value $Win.FindName($n) -Scope Script }

# CbType peuplé en chaînes simples (évite les objets ComboBoxItem du XAML)
'Portable','Fixe','Virtuel' | ForEach-Object { [void]$CbType.Items.Add($_) }

# Mode simulation interne (drapeau initialisé avant le câblage des handlers).
$script:SimOn    = $false

###############################################################################
#  SECTION 8 — TABLE / FILE D'ACTIONS
###############################################################################

function New-QueueTable {
    $t = New-Object System.Data.DataTable 'File'
    [void]$t.Columns.Add('Traiter',[bool])
    [void]$t.Columns.Add('Statut',[string])
    [void]$t.Columns.Add('Renommer',[bool])
    [void]$t.Columns.Add('Deplacer',[bool])
    $colReboot = $t.Columns.Add('Reboot',[bool]); $colReboot.DefaultValue = $false
    foreach ($c in 'Nom_du_PC','Type_de_PC','Organisme','Site','Service','Nouveau_Nom','OU_Actuelle','OU_Destination','Code','Message','Duree','Horodatage','Plan','Precontrole','Controle_Detail','Controle_Utc','Controle_Signature','Objet_GUID','Mode_Resultat','Lot_ID','ConfigStamp','TargetMachineId','Resultat_Precedent','Operation_ID','InitialProtection','Resume_ID','TargetOUGuid') {
        [void]$t.Columns.Add($c,[string])
    }
    [void]$t.Columns.Add('NeedsReview',[bool])
    foreach($col in $t.Columns){if($col.DataType -eq [string]){$col.DefaultValue=''}elseif($col.DataType -eq [bool]){$col.DefaultValue=$false}}
    return ,$t   # virgule = empêche PowerShell d'énumérer la DataTable (sinon une table vide -> $null)
}
$script:table = New-QueueTable
$Grid.ItemsSource = $script:table.DefaultView
$script:Running = $false

function Ensure-Table {
    # Garantit que la table existe et est reliée à la grille (auto-réparation).
    if (-not $script:table) {
        $script:table = New-QueueTable
        if ($Grid) { $Grid.ItemsSource = $script:table.DefaultView }
    }
    if ($script:table -and -not $script:table.Columns.Contains('Reboot')) {
        $colReboot = $script:table.Columns.Add('Reboot',[bool]); $colReboot.DefaultValue = $false
        foreach ($r in @($script:table.Rows)) { $r.Reboot = $false }
    }
}
function Update-QueueButtons {
    Ensure-Table
    $total=$script:table.Rows.Count; $has=$total -gt 0
    $selected=$null -ne $Grid.SelectedItem; $editing=$script:EDIT_ROW_INDEX -ge 0
    $toRun=@($script:table.Rows|Where-Object{$_.Traiter -eq $true -and ($_.Renommer -or $_.Deplacer)}).Count
    $locked=([bool]$script:DirectBusy -or [bool]$script:Running -or [bool]$script:PreflightRunning -or [bool]$script:JoinBusy -or (Test-PestoAsyncOperationRunning 'DomainJoin'))
    $BtnEdit.IsEnabled=(-not $locked -and ($selected -or $editing))
    # Retirer une intention locale reste possible pendant l'édition du formulaire.
    # La ligne surlignée, et non les cases Traiter, est la cible de cette commande.
    $removeRow=$null
    if($Grid.SelectedItem -is [System.Data.DataRowView]){$removeRow=$Grid.SelectedItem.Row}
    $removeState=Get-PestoQueueRemovalState -Row $removeRow
    $BtnDelete.IsEnabled=$removeState.CanRemove
    $BtnDelete.ToolTip=$removeState.Help
    $BtnClear.IsEnabled=(-not $locked -and $has -and -not $editing)
    $BtnImport.IsEnabled=(-not $locked -and -not $editing)
    $BtnExport.IsEnabled=(-not $locked -and $has)
    $BtnCheckAll.IsEnabled=(-not $locked -and $has -and -not $editing)
    $BtnUncheckAll.IsEnabled=$BtnCheckAll.IsEnabled
    $BtnPreview.IsEnabled=(-not $locked -and $toRun -gt 0)
    $BtnDetails.IsEnabled=$selected
    $BtnRetryMove.IsEnabled=(-not $locked -and $selected -and [string]$Grid.SelectedItem.Code -eq '89')
    $BtnSafetyReset.Visibility=if($script:MutationUncertain){'Visible'}else{'Collapsed'}
    $BtnSafetyReset.IsEnabled=(-not $locked)
    $BtnSafetyAck.Visibility=if($script:MutationUncertain -and -not $script:PestoReadOnly){'Visible'}else{'Collapsed'}
    $BtnSafetyAck.IsEnabled=(-not $locked -and -not $editing)
    $BtnStop.IsEnabled=($script:Running -and -not $script:QueueStopRequested)
    $BtnRun.IsEnabled=($script:INDOMAIN -and -not (Test-PestoDirectTargetBarrier) -and -not $script:JoinLocked -and -not $locked -and $toRun -gt 0 -and -not $editing -and -not (Test-PestoGlobalSafetyBarrier) -and -not $script:CfgRestartRequired -and -not (Test-PestoAsyncOperationRunning 'DirectoryRefresh'))
    $BtnRun.Content=if($toRun -gt 0){"Exécuter la file ($toRun)"}else{'Exécuter la file'}
    $LblEmpty.Visibility=if($has){'Collapsed'}else{'Visible'}
    $LblQueueCount.Text=if($has){"$total poste(s) • $toRun à traiter"}else{''}
    if($script:INDOMAIN){$ChkRemote.IsEnabled=(-not $locked -and -not $has)}
    Update-PestoPilotage
}

function Sync-Grid {
    # Rafraîchit la grille sans jamais lever d'exception (annule d'abord une
    # édition de cellule en cours, sinon Items.Refresh() est interdit).
    try { [void]$Grid.CommitEdit() } catch {}
    try { $Grid.CancelEdit() } catch {}
    # La file est liée à sa DataView : toute écriture dans une DataRow notifie WPF cellule par
    # cellule. Y forcer le rafraîchissement recréait tous les conteneurs de ligne à chaque ligne
    # traitée par le pump, l'inverse de la mise à jour incrémentale déjà livrée pour le registre
    # et la page des noms. Le rafraîchissement complet reste le repli des liaisons muettes.
    $source=$Grid.ItemsSource
    if($source -is [Data.DataView] -or $source -is [Collections.Specialized.INotifyCollectionChanged]){return}
    try { $Grid.Items.Refresh() } catch {}
}

###############################################################################
#  SECTION 9 — LOGIQUE DE CONFIGURATION (handlers de champs)
###############################################################################

function Format-OUPath {
    param([string]$DN)
    if([string]::IsNullOrWhiteSpace($DN)){return 'Non défini'}
    try {
        $parts=@(Split-PestoDistinguishedName $DN | Where-Object{$_ -match '^(?i:OU)='} | ForEach-Object{$_.Substring(3) -replace '\\([,+=<>;"\\])','$1'})
        if(-not $parts.Count){return $DN}
        [array]::Reverse($parts);return ($parts -join ' › ')
    } catch { return $DN }
}

function Set-OULabel {
    <# Affiche un chemin OU compact sur une ligne ; le DN complet passe en tooltip. #>
    param($Label,[string]$Prefix,[string]$Value)
    $Label.Text    = "$Prefix $(Format-OUPath $Value)"
    $Label.ToolTip = if ($Value -and $Value -match '(?i)\bOU=') { $Value } else { $null }
    if(-not $Label.ToolTip){$Label.ToolTip='Emplacement non déterminé. Identifiez le poste et choisissez un site.'}
    if($script:PestoUxReady){Request-PestoUxRefresh}
}
function Reset-ConfigFields {
    param([switch]$KeepName)
    $prevSuspend = $script:Suspend
    $script:Suspend = $true
    try {
        if (-not $KeepName) {
            $CbType.SelectedIndex = -1; $CbType.IsEnabled = $false
        }
        $CbOrg.SelectedIndex = -1; $CbOrg.IsEnabled = $false
        $CbSite.Items.Clear(); $CbSite.SelectedIndex = -1; $CbSite.IsEnabled = $false
        $CbService.Items.Clear(); $CbService.Text = ''; $CbService.IsEnabled = $false
        $CbName.Items.Clear(); $CbName.SelectedIndex = -1; $CbName.IsEnabled = $false
        $ChkRename.IsChecked = $false; $ChkRename.IsEnabled = $false
        $ChkMove.IsChecked = $false;   $ChkMove.IsEnabled = $false
        if ($ChkReboot) { $ChkReboot.IsChecked = $false; $ChkReboot.IsEnabled = $false }
        $LblNameTaken.Text = "Ce nom est déjà utilisé dans l'AD"
        $LblNameTaken.Visibility = 'Collapsed'
        Set-OULabel $LblCurrentOU 'OU actuelle  :' $null
        Set-OULabel $LblTargetOU  'OU cible     :' $null
        $BtnAdd.IsEnabled = $false
        $script:OU_FINAL = $null; $script:OU_ORGANISME = $null; $script:OU_ACTUELLE = $null
        $script:NewNameExists = $null
    } finally {
        $script:Suspend = $prevSuspend
    }
}

function Update-FieldColor {
    if (-not $TxtPCName) { return }
    $TxtPCName.Background =
        if ($TxtPCName.IsReadOnly) { $script:BR_FieldRO }
        elseif ($script:PING -eq $true)  { $script:BR_FieldOk }
        elseif ($script:PING -eq $false -and -not $script:LOCALHOST) { $script:BR_FieldKo }
        else { $script:BR_FieldBg }
}

function Set-PCInfo {
    param([string]$Text,[string]$Kind='err')
    if ($Text) {
        $LblPCInfo.Text = $Text
        $LblPCInfo.Foreground = $Win.Resources[ $(if ($Kind -eq 'warn') {'WarnFg'} elseif ($Kind -eq 'ok') {'OkFg'} else {'ErrFg'}) ]
        $LblPCInfo.Visibility = 'Visible'
    } else { $LblPCInfo.Visibility = 'Collapsed' }
    if($script:PestoUxReady){Request-PestoUxRefresh}
}
function Set-ModeLocal {
    $prevSuspend = $script:Suspend
    $script:Suspend = $true
    try {
        $script:LOCALHOST = $true
        $script:PING = $null
        $ChkRemote.IsChecked = $false
        $TxtPCName.Text = $env:COMPUTERNAME
        $TxtPCName.IsReadOnly = $true
        Update-FieldColor
    } finally {
        $script:Suspend = $prevSuspend
    }
    if (-not $prevSuspend) { Select-PCName }
}

function On-RemoteToggle {
    if ($script:Suspend) { return }
    if ($ChkRemote.IsChecked) {
        $script:LOCALHOST = $false
        $TxtPCName.IsReadOnly = $false
        $TxtPCName.Clear()
        $script:PING = $null
        Reset-ConfigFields
        Update-FieldColor
        $TxtPCName.Focus()
    } else {
        Set-ModeLocal
    }
}

function Update-PestoComputerIndex {
    <# Reconstruit l'index mémoire après login ou rafraîchissement AD. #>
    $script:ComputerIndex=@{}
    foreach($pc in @($script:Computers)){
        if($null -eq $pc){continue}
        $pcName="$($pc.Name)".Trim()
        if($pcName){$script:ComputerIndex[$pcName.ToUpperInvariant()]=$pc}
    }
    if($script:LocalComputerSnapshot -and $script:LocalComputerSnapshot.Name){
        $localName="$($script:LocalComputerSnapshot.Name)".Trim()
        if($localName){$script:ComputerIndex[$localName.ToUpperInvariant()]=$script:LocalComputerSnapshot}
    }
}

function Get-PestoCachedComputerProbe {
    <# Retourne les informations déjà chargées pendant le login. Aucune requête AD. #>
    param([string]$Name,[bool]$Local=$false)
    $n="$Name".Trim()
    if(-not $n){return $null}
    $pc=$null
    $key=$n.ToUpperInvariant()
    try{if($script:ComputerIndex -and $script:ComputerIndex.ContainsKey($key)){$pc=$script:ComputerIndex[$key]}}catch{}
    if(-not $pc -and $Local -and $script:LocalComputerSnapshot -and "$($script:LocalComputerSnapshot.Name)" -ieq $n){
        $pc=$script:LocalComputerSnapshot
    }
    if(-not $pc){return $null}
    $dn="$($pc.DistinguishedName)".Trim()
    if(-not $dn){return $null}
    [pscustomobject]@{
        Name="$($pc.Name)"
        DN=$dn
        OU=($dn -replace '^CN=.*?,','')
        Ping=$null
        Cached=$true
    }
}

function Apply-PestoComputerProbeResult {
    <# Applique le résultat d'identification d'un poste sur le thread WPF. #>
    param([AllowNull()]$Result,[string]$Name,[int]$Generation)
    if($null -eq $Result){return $false}
    if($Generation -ne [int]$script:PCProbeGeneration){return $false}
    if("$($TxtPCName.Text)".Trim() -ine "$Name".Trim()){return $false}

    $script:PING=$Result.Ping
    $script:OU_ACTUELLE=[string]$Result.OU
    Set-OULabel $LblCurrentOU 'OU actuelle  :' (Format-PestoOUForDisplay $script:OU_ACTUELLE)
    $CbOrg.IsEnabled=$true
    $CbType.IsEnabled=$true

    $prev=$script:Suspend;$script:Suspend=$true
    try{
        # Le type d'un nom conforme est conservé ; le matériel ne doit pas transformer une VM en portable.
        $currentParts=ConvertTo-PestoNameParts -Name $Name -CurrentName
        if($currentParts){$CbType.SelectedItem=$currentParts.Label}
        elseif($script:LOCALHOST){
            if($script:CachedPCType -in @('Portable','Fixe','Virtuel')){$CbType.SelectedItem=$script:CachedPCType}
            else{$CbType.SelectedItem=switch -Wildcard ($Name){'P*'{'Portable'};'V*'{'Virtuel'};default{'Fixe'}}}
        }
        else{$CbType.SelectedItem=switch -Wildcard ($Name){'P*'{'Portable'};'V*'{'Virtuel'};default{'Fixe'}}}
    } finally {$script:Suspend=$prev}
    Update-FieldColor

    # Détection org/site à partir du tag déjà présent dans le nom.
    $city=Get-CityCodeFromComputerName $Name
    $targetOrg=$null;$targetSite=$null
    if($city){
        foreach($org in @($script:Sites.Keys|Sort-Object)){
            $site=Find-TargetOU -ous $script:Sites[$org] -cityCode $city
            if($site){$targetOrg=$org;$targetSite=$site;break}
        }
    }
    if($targetOrg){
        $prev=$script:Suspend;$script:Suspend=$true
        try{
            $CbOrg.SelectedItem=$targetOrg
            Apply-OrganismeSelection
            if($targetSite){$CbSite.SelectedItem=$targetSite;Apply-SiteSelection}
        } finally {$script:Suspend=$prev}
        Select-NewName
        Check-SameOU
    } else {
        Set-PCInfo $null
    }
    if($script:PestoPendingDraft){Complete-PestoPendingDraft}
    return $true
}

$script:PestoComputerProbeWorker = {
    param($Request)
    Set-StrictMode -Off; $ErrorActionPreference='Stop'
    $adLoader=[string]$Request.ADLoaderSource
    if(-not $adLoader){throw 'Résolveur AD approuvé absent du worker.'}
    . ([scriptblock]::Create($adLoader))
    Import-PestoADModule -ADModulePath ([string]$Request.ADModulePath)
    $adp=@{Server=[string]$Request.DC}; if($null -ne $Request.Credential){$adp.Credential=$Request.Credential}
    $ping=if([bool]$Request.Local){$null}else{[bool](Test-Connection ([string]$Request.Name) -Count 1 -Quiet -ErrorAction SilentlyContinue)}
    $pc=Get-ADComputer -Identity ([string]$Request.Name) -Properties DistinguishedName -ErrorAction Stop @adp
    [pscustomobject]@{Name=[string]$pc.Name;DN=[string]$pc.DistinguishedName;OU=([string]$pc.DistinguishedName -replace '^CN=.*?,','');Ping=$ping}
}

function Select-PCName {
    if($script:Suspend){return}
    $name=$TxtPCName.Text.Trim()
    Set-PCInfo $null
    $BtnAdd.IsEnabled=$false
    $script:NewNameExists=$null

    if(-not $script:INDOMAIN -and $script:LOCALHOST){
        # Hors domaine : ne JAMAIS lancer de CIM/WMI synchrone depuis le Dispatcher WPF.
        # Le type a normalement déjà été détecté dans le worker du login. S'il ne l'est
        # pas, on laisse simplement Portable/Fixe/Virtuel à choisir manuellement.
        $prev=$script:Suspend;$script:Suspend=$true
        try {
            $CbType.IsEnabled=$true
            if($script:GUI){$CbType.SelectedItem='Fixe'}
            elseif($script:CachedPCType -in @('Portable','Fixe','Virtuel')){$CbType.SelectedItem=$script:CachedPCType}
            elseif($CbType.SelectedItem -notin @('Portable','Fixe','Virtuel')){$CbType.SelectedIndex=-1}
        } finally {$script:Suspend=$prev}
        Setup-HorsDomaineUI
        if($CbType.SelectedItem -in @('Portable','Fixe','Virtuel')){Update-NameList}
        return
    }
    if(-not (Test-PestoComputerName $name)){Reset-ConfigFields;return}
    if($name -ieq $env:COMPUTERNAME -and -not $script:LOCALHOST){Set-ModeLocal;return}
    if($name -ieq $env:COMPUTERNAME){$script:LOCALHOST=$true}

    if($script:GUI){
        $script:PING=if($script:LOCALHOST){$null}else{$true}
        $script:OU_ACTUELLE='(mode GUI)'
        Set-OULabel $LblCurrentOU 'OU actuelle  :' (Format-PestoOUForDisplay $script:OU_ACTUELLE)
        $CbOrg.IsEnabled=$true;$CbType.IsEnabled=$true
        Update-FieldColor
        if($script:PestoPendingDraft){Complete-PestoPendingDraft}
        return
    }

    $script:PCProbeGeneration=[int]$script:PCProbeGeneration+1
    $gen=[int]$script:PCProbeGeneration

    # Chemin rapide, en particulier au démarrage : le login vient déjà de charger
    # le poste local et le parc. Aucun worker AD supplémentaire n'est nécessaire.
    $cached=Get-PestoCachedComputerProbe -Name $name -Local ([bool]$script:LOCALHOST)
    if($cached){
        [void](Apply-PestoComputerProbeResult -Result $cached -Name $name -Generation $gen)
        return
    }

    # Repli uniquement si le poste n'était pas dans le snapshot (poste déplacé,
    # périmètre différent, saisie distante, réplication AD en cours...).
    $request=[pscustomobject]@{
        Name=$name;Local=[bool]$script:LOCALHOST;DC=$script:DC;Credential=$script:cred
        ADLoaderSource=(Get-PestoADLoaderSource);ADModulePath=(Join-Path $BasePath 'ActiveDirectory.psd1')
    }
    $context=[pscustomobject]@{Name=$name;Generation=$gen}
    $ok={param($r,$ctx) Complete-PestoComputerProbeSuccess -Result $r -Name $ctx.Name -Generation $ctx.Generation}
    $err={param($e,$ctx) Complete-PestoComputerProbeError -Failure $e -Name $ctx.Name -Generation $ctx.Generation}
    [void](Start-PestoAsyncOperation -Name 'PCProbe' -ScriptBlock $script:PestoComputerProbeWorker -ArgumentList @($request) -OnSuccess $ok -OnError $err -CallbackContext $context -Replace -TimeoutSec 75)
}
function Setup-HorsDomaineUI {
    <# Prépare l'interface de jonction au domaine. En transit, PREPROD reste le
       libellé de site transmis au résolveur TAGS ; le code PreprodSite reste le
       service/équipe à 3 caractères. #>
    $script:OU_ACTUELLE = 'Hors domaine'
    Set-OULabel $LblCurrentOU 'OU actuelle  :' (Format-PestoOUForDisplay $script:OU_ACTUELLE)
    $CbType.IsEnabled = $true

    $prevSuspend = $script:Suspend; $script:Suspend = $true
    try {
        $ChkRename.IsChecked = $true; $ChkRename.IsEnabled = $false
        $ChkMove.IsChecked   = $true; $ChkMove.IsEnabled   = $false
    } finally { $script:Suspend = $prevSuspend }
    Update-RebootOption

    if ($script:PRD) {
        Set-PCInfo 'Le poste est hors-domaine : il sera joint directement en production. Choisissez l''emplacement.' 'warn'
        $prevSuspend = $script:Suspend; $script:Suspend = $true
        try {
            if ($CbOrg.Items.Contains('PREPROD')) { [void]$CbOrg.Items.Remove('PREPROD') }
            if ("$($CbOrg.SelectedItem)" -ieq 'PREPROD') { $CbOrg.SelectedIndex = -1 }
            $CbOrg.IsEnabled = $true
        } finally { $script:Suspend = $prevSuspend }
        if ("$($CbOrg.SelectedItem)") { Apply-OrganismeSelection }
        else {
            $CbSite.Items.Clear(); $CbSite.IsEnabled = $false
            $CbService.Items.Clear(); $CbService.Text = ''; $CbService.IsEnabled = $false
            $CbName.Items.Clear(); $CbName.IsEnabled = $false
            $script:OU_FINAL = $null
            Set-OULabel $LblTargetOU 'OU cible     :' $null
        }
    } else {
        Set-PCInfo "Le poste est hors-domaine : il sera joint en zone de transit (pré-prod : $($script:PREPRODSITE))." 'warn'
        $prevSuspend = $script:Suspend; $script:Suspend = $true
        try {
            if (-not $CbOrg.Items.Contains('PREPROD')) { [void]$CbOrg.Items.Add('PREPROD') }
            $CbOrg.SelectedItem = 'PREPROD'; $CbOrg.IsEnabled = $false
        } finally { $script:Suspend = $prevSuspend }
        Apply-OrganismeSelection
    }
    # Une génération invalide ne doit jamais décocher les actions obligatoires.
    $prevSuspend = $script:Suspend; $script:Suspend = $true
    try { $ChkRename.IsChecked = $true; $ChkMove.IsChecked = $true }
    finally { $script:Suspend = $prevSuspend }
    Update-AddButton
}
function Initialize-PestoHorsDomainUI {
    <# Initialise ET répare l'état interactif hors domaine. Cette routine est
       idempotente et peut être rappelée après Loaded/ContentRendered : elle ne fait
       aucun accès réseau, AD ou WMI et ne dépend d'aucun événement WPF. #>
    if($script:INDOMAIN){return $true}
    if($script:JoinUI){Update-PestoJoinUI;return $true}

    try {
        # Un IsEnabled=False sur un ancêtre WPF rend tous les enfants inactifs même
        # si leur propre IsEnabled vaut True. On force donc aussi les conteneurs.
        foreach($c in @($Win,$MainTabs,$BodyGrid)){
            if($c){
                try{$c.IsEnabled=$true}catch{}
                try{$c.IsHitTestVisible=$true}catch{}
            }
        }

        $prev=$script:Suspend
        $script:Suspend=$true
        try {
            $script:LOCALHOST=$true
            $script:PING=$null
            $ChkRemote.IsChecked=$false
            $ChkRemote.IsEnabled=$false
            $TxtPCName.Text=$env:COMPUTERNAME
            $TxtPCName.IsReadOnly=$true
            $TxtPCName.IsEnabled=$true
            $TxtPCName.IsHitTestVisible=$true

            # TYPE doit TOUJOURS rester utilisable en hors domaine. Le matériel est
            # détecté dans le worker du login ; si rien n'est connu, l'utilisateur choisit.
            $CbType.IsEnabled=$true
            $CbType.IsHitTestVisible=$true
            if($script:GUI){$CbType.SelectedItem='Fixe'}
            elseif($script:CachedPCType -in @('Portable','Fixe','Virtuel') -and $CbType.SelectedItem -notin @('Portable','Fixe','Virtuel')){
                $CbType.SelectedItem=$script:CachedPCType
            }

            # Renommer + déplacer représentent la jonction hors domaine et sont donc
            # imposés. Leur grisé est volontaire ; ce ne sont pas des champs bloqués.
            $ChkRename.IsChecked=$true; $ChkRename.IsEnabled=$false
            $ChkMove.IsChecked=$true;   $ChkMove.IsEnabled=$false
        } finally {
            $script:Suspend=$prev
        }

        # Recalcule le workflow d'emplacement. En DirectProd, Organisme doit être
        # interactif. En PREPROD, organisme/site/service sont imposés volontairement.
        Setup-HorsDomaineUI
        if($script:PRD){
            $CbOrg.IsEnabled=$true
            $CbOrg.IsHitTestVisible=$true
        }
        Update-FieldColor

        # Ne jamais attendre SelectionChanged : toutes les valeurs peuvent avoir été
        # posées sous Suspend=True pendant le démarrage.
        if($CbType.SelectedItem -in @('Portable','Fixe','Virtuel')){Update-NameList}
        else{Update-AddButton}

        $state = "HDUI v$script:Pesto_VERSION | Win=$($Win.IsEnabled) Tabs=$($MainTabs.IsEnabled) Body=$($BodyGrid.IsEnabled) Type=$($CbType.IsEnabled) Org=$($CbOrg.IsEnabled) Site=$($CbSite.IsEnabled) Service=$($CbService.IsEnabled) Name=$($CbName.IsEnabled) PRD=$script:PRD TypeSel='$($CbType.SelectedItem)' OrgSel='$($CbOrg.SelectedItem)' SiteSel='$($CbSite.SelectedItem)' OU='$script:OU_FINAL'"
        try{Write-Log $state 'INFO' $null 'hd-ui'}catch{}

        # Invariant dur : si même après forçage le contrôle effectif reste désactivé,
        # on remonte une erreur au lieu d'afficher une interface morte.
        if(-not $Win.IsEnabled -or -not $MainTabs.IsEnabled -or -not $BodyGrid.IsEnabled){
            throw 'Un conteneur parent WPF est resté désactivé.'
        }
        if(-not $CbType.IsEnabled){throw 'TYPE DE POSTE est resté désactivé après réparation WPF.'}
        if($script:PRD -and -not $CbOrg.IsEnabled){throw 'ORGANISME est resté désactivé en DirectProd.'}
        if(-not $script:PRD){
            if("$($CbOrg.SelectedItem)" -ine 'PREPROD'){throw 'Le profil PREPROD n''a pas été initialisé.'}
            if(-not (Test-PestoOUPath $script:OU_FINAL)){throw 'L''OU PREPROD est absente ou invalide.'}
        }
        return $true
    } catch {
        Write-Log 'Initialisation/réparation du mode hors domaine impossible.' 'ERROR' $_ 'startup-hors-domaine'
        try{Set-PCInfo "Initialisation hors domaine impossible : $($_.Exception.Message)" 'err'}catch{}
        return $false
    }
}

function Get-InfoComputer {
    <# Charge l'OU actuelle d'un poste + pré-remplit org/site si détecté. #>
    param($Computer)
    if ($script:GUI) {
        $script:OU_ACTUELLE = '(mode GUI)'
        Set-OULabel $LblCurrentOU 'OU actuelle  :' (Format-PestoOUForDisplay $script:OU_ACTUELLE)
        $CbOrg.IsEnabled = $true; $CbType.IsEnabled = $true
        return $true
    }
    Set-BusyState $true
    try {
        try {
            $pc = Get-ComputerOU -Identity $Computer
            $script:OU_ACTUELLE = $pc.OU
            Set-OULabel $LblCurrentOU 'OU actuelle  :' (Format-PestoOUForDisplay $pc.OU)
            $CbOrg.IsEnabled = $true; $CbType.IsEnabled = $true
        } catch {
            Reset-ConfigFields -KeepName
            Set-PCInfo "Poste introuvable dans l'AD ou contrôleur de domaine indisponible : $($_.Exception.Message)"
            return $false
        }

        $target = ComputerNameVSCityCode -ComputerName $Computer
        if ($target -and $target.Organisme) {
            $prevSuspend = $script:Suspend; $script:Suspend = $true
            try {
                $CbOrg.SelectedItem = $target.Organisme
                Apply-OrganismeSelection
                if ($target.Site) { $CbSite.SelectedItem = $target.Site; Apply-SiteSelection }
            } finally { $script:Suspend = $prevSuspend }
            Select-NewName
            Check-SameOU
        }
        return $true
    } finally {
        Set-BusyState $false
    }
}
function Apply-OrganismeSelection {
    $prevSuspend = $script:Suspend; $script:Suspend = $true
    $applySite = $false
    try {
        $BtnAdd.IsEnabled = $false
        $CbName.Items.Clear(); $CbName.SelectedIndex = -1; $CbName.IsEnabled = $false
        $CbSite.Items.Clear(); $CbSite.SelectedIndex = -1; $CbSite.IsEnabled = $false
        $CbService.Items.Clear(); $CbService.Text = ''; $CbService.IsEnabled = $false
        $script:OU_FINAL = $null; $script:OU_ORGANISME = $null; $script:NewNameExists = $null
        Set-OULabel $LblTargetOU 'OU cible     :' $null
        $org = "$($CbOrg.SelectedItem)".Trim()

        if ($org -ieq 'PREPROD') {
            [void]$CbSite.Items.Add('PREPROD')
            $CbSite.SelectedItem = 'PREPROD'; $CbSite.IsEnabled = $false
            $applySite = $true
        } elseif ($org) {
            if (-not $script:OUV.ContainsKey($org)) {
                Set-PCInfo "Organisme '$org' absent de la configuration OUSite."
            } else {
                $script:OU_ORGANISME = $script:OUV[$org]
                foreach ($s in @($script:Sites[$org] | Sort-Object)) {
                    if ("$s".Trim()) { [void]$CbSite.Items.Add("$s") }
                }
                $CbSite.IsEnabled = ($CbSite.Items.Count -gt 0)
                if (-not $CbSite.IsEnabled) { Set-PCInfo "Aucun site lisible sous l'organisme '$org'." 'warn' }
            }
        }
    } finally {
        $script:Suspend = $prevSuspend
    }
    if ($applySite) { Apply-SiteSelection } else { Update-AddButton }
}
function Apply-SiteSelection {
    $previousService=[string]$CbService.Text
    $prevSuspend=$script:Suspend; $script:Suspend=$true
    $needNames=$false; $needSameOU=[bool]$script:INDOMAIN
    try {
        $BtnAdd.IsEnabled=$false
        $CbName.Items.Clear(); $CbName.SelectedIndex=-1; $CbName.IsEnabled=$false
        $CbService.Items.Clear(); $CbService.Text=''; $CbService.IsEnabled=$false
        $script:OU_FINAL=$null; $script:NewNameExists=$null
        if($script:INDOMAIN){$ChkMove.IsChecked=$false}
        $site="$($CbSite.SelectedItem)".Trim()
        if(-not $site){
            if($script:INDOMAIN){ $ChkMove.IsChecked=$false; $ChkMove.IsEnabled=$false; $ChkRename.IsChecked=$false; $ChkRename.IsEnabled=$false }
            Set-OULabel $LblTargetOU 'OU cible     :' $null
        } elseif($site -ieq 'PREPROD'){
            $script:OU_FINAL="$($script:OU['PREPROD'])".Trim()
            [void]$CbService.Items.Add("$script:PREPRODSITE"); $CbService.Text="$script:PREPRODSITE"; $CbService.IsEnabled=$false
            Set-OULabel $LblTargetOU 'OU cible     :' $script:OU_FINAL
            if(Test-PestoOUPath $script:OU_FINAL){$needNames=$true}else{Set-PCInfo 'OU PREPROD absente ou invalide dans OUBase.' 'err'}
            if(-not $script:INDOMAIN){$ChkMove.IsChecked=$true;$ChkMove.IsEnabled=$false;$ChkRename.IsChecked=$true;$ChkRename.IsEnabled=$false}
        } elseif(-not (Test-PestoOUPath $script:OU_ORGANISME)){
            Set-PCInfo "OU d'organisme invalide pour '$site'."
        } else {
            $script:OU_FINAL="OU=$(ConvertTo-PestoRdnValue $site),$($script:OU_ORGANISME)"
            Set-OULabel $LblTargetOU 'OU cible     :' $script:OU_FINAL
            if($script:INDOMAIN){$ChkMove.IsEnabled=$true;$ChkMove.IsChecked=$false;$needSameOU=$true}
            # ICMP est indicatif ; les contrôles AD/RPC décident si l'opération peut être engagée.
            foreach($e in @(Get-PestoSiteServiceCodes -OrganismeOU $script:OU_ORGANISME -Site $site -Computers (Get-PestoKnownComputers))){[void]$CbService.Items.Add($e)}
            $CbService.IsEnabled=$true; $needNames=$true
            Request-PestoSiteLookup -OrganismeOU $script:OU_ORGANISME -Site $site
        }
        if($site -and $site -ine 'PREPROD' -and $previousService -match (Get-PestoFacetPattern Service) -and $CbService.IsEnabled){$CbService.Text=$previousService;$needNames=$true}
    } finally { $script:Suspend=$prevSuspend }
    if($needSameOU){Check-SameOU}
    if($needNames){Update-NameList}else{Update-AddButton}
}

function Check-SameOU {
    if(-not $script:INDOMAIN){return}
    $prev=$script:Suspend;$script:Suspend=$true
    $script:AutoMoveError=$null
    try {
        if([bool]$ChkRename.IsChecked) {
            $decision=Get-PestoRenameMoveDecision -Computer ([string]$TxtPCName.Text) -NewName ([string]$CbName.SelectedItem) `
                -CurrentOU ([string]$script:OU_ACTUELLE) -TargetOU ([string]$script:OU_FINAL) -Rename $true -Move $false
            $ChkMove.IsChecked=[bool]$decision.Move
            $ChkMove.IsEnabled=$false
            $ChkMove.Content='Déplacer (auto)'
            $ChkMove.ToolTip=if($decision.Valid){$decision.Reason}else{$decision.Error}
            if(-not $decision.Valid){$script:AutoMoveError=$decision.Error}
        } else {
            $ChkMove.Content='Déplacer (seul)'
            $ChkMove.ToolTip='Action distincte, uniquement sur demande explicite. Pour un renommage, le déplacement dépend du changement de site.'
            if(-not(Test-PestoOUPath $script:OU_FINAL) -or $script:OU_FINAL -ieq $script:OU_ACTUELLE) {
                $ChkMove.IsChecked=$false;$ChkMove.IsEnabled=$false
            } else {$ChkMove.IsEnabled=$true}
        }
    } finally {$script:Suspend=$prev}
    Update-RebootOption
    Update-AddButton
}

function Get-ComputersForNameGeneration {
    <# Fusionne le cache AD et les noms cibles déjà réservés dans la file. La
       ligne en cours d'édition est exclue pour pouvoir conserver son propre nom. #>
    $items = [System.Collections.Generic.List[object]]::new()
    # Postes de l'OU racine, inventaire des noms (OUScanNoms) et recherches ciblées de site : un nom vu pris n'est pas proposé.
    foreach ($c in (Get-PestoKnownComputers)) { if ($c) { [void]$items.Add($c) } }
    if ($script:table) {
        for ($i = 0; $i -lt $script:table.Rows.Count; $i++) {
            if ($i -eq $script:EDIT_ROW_INDEX) { continue }
            $row = $script:table.Rows[$i]
            $target = "$($row.Nouveau_Nom)".Trim().ToUpperInvariant()
            if ([bool]$row.Renommer -and (Test-PestoGeneratedComputerName $target)) {
                [void]$items.Add([PSCustomObject]@{ Name = $target })
            }
        }
    }
    return $items.ToArray()
}
function Update-NameList {
    $previousName=[string]$CbName.SelectedItem
    $prevSuspend = $script:Suspend; $script:Suspend = $true
    try {
        $type = "$($CbType.SelectedItem)".Trim()
        $svc  = "$($CbService.Text)".Trim().ToUpperInvariant()
        $site = "$($CbSite.SelectedItem)".Trim()
        $CbName.Items.Clear(); $CbName.SelectedIndex = -1; $CbName.IsEnabled = $false
        $script:NewNameExists = $null

        $ready = ($site -and $type -in @('Portable','Fixe','Virtuel') -and $svc -match ('^[A-Z0-9]{'+(Get-PestoNamingLayout).Convention.Widths.Service+'}$'))
        if ($ready) {
            $policy=ConvertTo-PestoPolicy $script:PestoPolicy
            Assert-PestoScenarioValues $policy.Scenario ([pscustomobject]@{Type=$(switch($type){'Portable'{'P'};'Fixe'{'S'};'Virtuel'{'V'}});SiteCode=(Get-SiteTag $site);ServiceCode=$svc;TargetOU=[string]$script:OU_FINAL})
            $base = $(switch($type){'Portable'{'P'};'Fixe'{'S'};'Virtuel'{'V'}})+$script:PREFIXE
            # Conserver PREPROD : Get-SiteTag le résout vers PR via cfg.json.
            $nameSource = Get-ComputersForNameGeneration
            $names = Get-NameList -codeSite $site -codeService $svc -computers $nameSource -baseName $base
            # Noms trouvés pris dans l'AD pendant cette session (souvent par un autre poste du banc) : jamais reproposés.
            foreach ($n in $names) { if ($script:PestoTakenNames -and $script:PestoTakenNames.Contains([string]$n)) { continue }; if (Test-PestoNameReservedByOther ([string]$n)) { continue }; [void]$CbName.Items.Add($n) }
            if ($CbName.Items.Count -gt 0) {
                if($previousName -and $CbName.Items.Contains($previousName)){$CbName.SelectedItem=$previousName}else{$CbName.SelectedIndex=(Get-PestoInitialNameIndex $CbName.Items.Count)}; $CbName.IsEnabled=$true
                # Efface seulement un ancien message d'erreur de génération ; les messages
                # métier hors-domaine sont réappliqués par Setup-HorsDomaineUI si nécessaire.
                if($LblPCInfo.Visibility -eq 'Visible' -and "$($LblPCInfo.Text)" -like 'Aucun nom disponible*'){Set-PCInfo $null}
            } else {
                Set-PCInfo "Aucun nom disponible ou générable pour Type='$type', Site='$site', Service='$svc'. Vérifiez la configuration TAGS et la plage de noms." 'err'
            }
        }
    } finally {
        $script:Suspend = $prevSuspend
    }
    # Toujours recalculer les cases/actions, y compris après une saisie devenue invalide.
    if (-not $prevSuspend) { Select-NewName }
}
function Select-NewName {
    if($script:Suspend){return}
    $LblNameTaken.Text="Ce nom est déjà utilisé dans l'AD"; $LblNameTaken.Visibility='Collapsed'; $script:NewNameExists=$null
    $newCN="$($CbName.SelectedItem)".Trim().ToUpperInvariant()
    if(-not (Test-PestoGeneratedComputerName $newCN)){
        if($script:INDOMAIN){$ChkRename.IsChecked=$false;$ChkRename.IsEnabled=$false}else{$ChkRename.IsChecked=$true;$ChkRename.IsEnabled=$false}
        Check-SameOU; Update-AddButton; return
    }
    $sameName=($newCN -ieq "$($TxtPCName.Text)".Trim())
    if($script:INDOMAIN){$ChkRename.IsChecked=-not $sameName;$ChkRename.IsEnabled=-not $sameName}else{$ChkRename.IsChecked=$true;$ChkRename.IsEnabled=$false}
    $found=@(Get-PestoKnownComputers | Where-Object { "$($_.Name)" -ieq $newCN } | Select-Object -First 1)
    if($found.Count -gt 0 -and "$($found[0].Name)" -ine "$($TxtPCName.Text)".Trim()){$script:NewNameExists=$found[0]}
    Check-SameOU
    if($script:NewNameExists){$LblNameTaken.Visibility='Visible';$BtnAdd.IsEnabled=$false}else{Update-AddButton}
}

function Update-RebootOption {
    <# Active la case reboot uniquement quand une action est prévue. Décoché par
       défaut : le comportement historique reste inchangé tant que l'utilisateur
       ne demande pas explicitement le redémarrage. #>
    if (-not $ChkReboot) { return }
    $canReboot = ([bool]$ChkRename.IsChecked -or [bool]$ChkMove.IsChecked)
    if ((-not $script:LOCALHOST) -and ($script:PING -eq $false)) { $canReboot = $false }
    if (-not $canReboot) { $ChkReboot.IsChecked = $false }
    $ChkReboot.IsEnabled = $canReboot
}
function Update-AddButton {
    if($script:DirectBusy -or (Test-PestoDirectTargetBarrier)){$BtnAdd.IsEnabled=$false;return}

    <# Active « Ajouter » uniquement avec une action et des données entièrement valides. #>
    if($script:PreflightRunning -or $script:Running -or (Test-PestoGlobalSafetyBarrier) -or $script:CfgRestartRequired){$BtnAdd.IsEnabled=$false;return}
    if(-not $script:INDOMAIN -or $script:JoinBusy -or $script:JoinLocked -or (Test-PestoAsyncOperationRunning 'DomainJoin')){$BtnAdd.IsEnabled=$false;return}
    Update-RebootOption
    $source = "$($TxtPCName.Text)".Trim()
    $newName = "$($CbName.SelectedItem)".Trim()
    $newNameOk = Test-PestoGeneratedComputerName $newName

    if (-not $script:INDOMAIN) {
        $BtnAdd.IsEnabled = ($source -ieq $env:COMPUTERNAME `
                             -and $newNameOk `
                             -and (Test-PestoOUPath $script:OU_FINAL) `
                             -and -not $script:NewNameExists)
        return
    }

    $ren = [bool]$ChkRename.IsChecked; $move = [bool]$ChkMove.IsChecked
    if($ren -and $script:AutoMoveError){$BtnAdd.IsEnabled=$false;return}
    if (-not $ren -and -not $move) { $BtnAdd.IsEnabled = $false; return }
    if (-not (Test-PestoComputerName $source)) { $BtnAdd.IsEnabled = $false; return }
    if ($script:NewNameExists) { $BtnAdd.IsEnabled = $false; return }
    if ($ren -and -not $newNameOk) { $BtnAdd.IsEnabled = $false; return }
    if ($move -and -not (Test-PestoOUPath $script:OU_FINAL)) { $BtnAdd.IsEnabled = $false; return }
    $BtnAdd.IsEnabled = $true
}

###############################################################################
#  SECTION 10 — AJOUT / ÉDITION DE LIGNES
###############################################################################
function Add-Or-UpdateRow {
    if($script:DirectBusy -or (Test-PestoDirectTargetBarrier)){return}

    if(-not $script:INDOMAIN){Set-PestoUxPage 'Join';return}
    if($script:JoinBusy -or $script:JoinLocked){return}

    if($script:PreflightRunning -or $script:Running -or (Test-PestoGlobalSafetyBarrier) -or $script:CfgRestartRequired){return}
    Ensure-Table
    $NomPC   = "$($TxtPCName.Text)".Trim().ToUpperInvariant()
    $NewName = "$($CbName.SelectedItem)".Trim().ToUpperInvariant()

    if ([string]::IsNullOrWhiteSpace($NomPC)) { Show-MsgWarning 'Le nom du PC ne peut pas être vide.'; return }
    if (-not $script:INDOMAIN -and $NomPC -ine $env:COMPUTERNAME) {
        Show-MsgWarning 'Hors domaine, seul ce poste local peut être joint au domaine.'; return
    }

    $Deplacer = [bool]$ChkMove.IsChecked
    if ($script:OU_FINAL -and $script:OU_FINAL -ieq $script:OU_ACTUELLE) { $Deplacer = $false }
    $Renommer = [bool]$ChkRename.IsChecked
    if (-not $script:INDOMAIN) { $Deplacer = $true; $Renommer = $true }
    $Reboot = [bool]$ChkReboot.IsChecked
    $decision=Get-PestoRenameMoveDecision -Computer $NomPC -NewName $NewName -CurrentOU ([string]$script:OU_ACTUELLE) `
        -TargetOU ([string]$script:OU_FINAL) -Rename $Renommer -Move $Deplacer -InDomain ([bool]$script:INDOMAIN)
    if(-not $decision.Valid){Show-MsgWarning $decision.Error;return}
    $Deplacer=[bool]$decision.Move

    $errs = @(Test-QueueRowSafe -Nom $NomPC -NewName $NewName -OU "$script:OU_FINAL" -Ren $Renommer -Move $Deplacer)
    if ($errs.Count) { Show-MsgWarning ("Ligne invalide :`n- " + ($errs -join "`n- ")); return }

    $row = $null
    if ($script:EDIT_ROW_INDEX -ge 0 -and $script:EDIT_ROW_INDEX -lt $script:table.Rows.Count) {
        $row = $script:table.Rows[$script:EDIT_ROW_INDEX]
    }

    if ($Renommer) {
        $targetDup = @($script:table.Rows | Where-Object {
            $_ -ne $row -and [bool]$_.Renommer -and
            "$($_.Nouveau_Nom)".Trim() -ieq $NewName
        } | Select-Object -First 1)
        if ($targetDup.Count) {
            Show-MsgWarning "Le nom cible '$NewName' est déjà réservé dans la file pour '$($targetDup[0].Nom_du_PC)'."
            return
        }
    }

    # Une seule ligne par poste, y compris si le nom source est modifié en édition.
    $dupes = @($script:table.Rows | Where-Object { $_ -ne $row -and "$($_.Nom_du_PC)".Trim() -ieq $NomPC })
    if($dupes.Count){Show-MsgWarning "Ce poste possède déjà une ligne. Modifiez ou supprimez explicitement cette ligne.";return}
    $undoBefore=$script:table.Copy()
    if (-not $row) { $row = $script:table.NewRow(); [void]$script:table.Rows.Add($row) }

    $row.Traiter        = $true
    $row.Statut         = ''
    $row.ConfigStamp=Get-PestoConfigurationSignature $script:CFG
    $row.NeedsReview=$false
    $row.TargetMachineId=if($NomPC -ieq $env:COMPUTERNAME){[string]$script:HostMachineId}else{''}
    foreach($field in @('Code','Message','Duree','Horodatage','Mode_Resultat','Lot_ID')){$row[$field]=''}
    $row.Renommer       = $Renommer
    $row.Deplacer       = $Deplacer
    $row.Reboot         = ($Reboot -and ($Renommer -or $Deplacer))
    $row.Nom_du_PC      = $NomPC
    $row.Type_de_PC     = "$($CbType.SelectedItem)"
    $row.Organisme      = "$($CbOrg.SelectedItem)"
    $row.Site           = "$($CbSite.SelectedItem)"
    $row.Service        = "$($CbService.Text)".Trim().ToUpperInvariant()
    $row.Nouveau_Nom    = $NewName
    $row.OU_Actuelle    = if ($script:INDOMAIN) { "$script:OU_ACTUELLE" } else { 'Hors domaine' }
    $row.OU_Destination = "$script:OU_FINAL".Trim()

    Reset-PestoRowPreflight -Row $row -ClearIdentity
    if($script:ComputerIndex -and $script:ComputerIndex.ContainsKey($NomPC)){
        $id=[Guid]::Empty
        if([Guid]::TryParse([string]$script:ComputerIndex[$NomPC].ObjectGUID,[ref]$id) -and $id -ne [Guid]::Empty){$row.Objet_GUID=$id.ToString('D')}
    }
    $script:NmUsedSrc = $null
    Update-PestoQueueFilter
    Sync-Grid
    Exit-EditMode
    Update-QueueButtons
    Save-PestoQueueCheckpointSafe
    Save-PestoQueueUndo -Before $undoBefore -Reason 'Ajout ou modification locale'
    Add-LogLine "File : $NomPC ajouté (Ren=$Renommer / Dépl=$Deplacer / Reboot=$($row.Reboot) → $NewName) | $($decision.Reason)" 'info'
}
function Enter-EditMode {
    param([int]$Index)
    if($script:PreflightRunning -or $script:Running){return}
    if ($Index -lt 0 -or $Index -ge $script:table.Rows.Count) { return }
    if($script:table.Rows[$Index].Statut -in @('OK','VÉRIFIÉ','SIMULÉ','PARTIEL','PROTECTION','INCERTAIN','TECHNIQUE','EN COURS')){Show-MsgWarning "Cette ligne est un résultat historique : consultez le détail, ou utilisez $(Get-PestoUxNom 'BtnReprendre') pour le code 89.";return}
    $script:EDIT_ROW_INDEX = $Index
    $row = $script:table.Rows[$Index]
    $BtnAdd.Content = 'Mettre à jour'; $BtnEdit.Content = 'Annuler la modification'
    $BtnEdit.ToolTip = 'Quitter la modification du formulaire sans enregistrer les changements. La ligne reste dans la file. Utilisez Retirer de la file pour enlever cette action.'

    $prevSuspend = $script:Suspend; $script:Suspend = $true
    try {
        $remote = ($script:INDOMAIN -and "$($row.Nom_du_PC)" -ine $env:COMPUTERNAME)
        $ChkRemote.IsChecked = $remote
        $script:LOCALHOST = -not $remote
        # Pas de ping synchrone à l'entrée en édition : un poste éteint pouvait
        # bloquer le Dispatcher plusieurs secondes. La ligne a déjà été validée ;
        # l'exécution réelle recontrôle la connectivité dans son worker.
        $script:PING = if ($remote) { $true } else { $null }
        $TxtPCName.IsReadOnly = -not $remote
        $TxtPCName.Text = "$($row.Nom_du_PC)"
        $CbType.IsEnabled = $true; $CbType.SelectedItem = "$($row.Type_de_PC)"
        if (-not $script:INDOMAIN -and -not $CbOrg.Items.Contains('PREPROD')) { [void]$CbOrg.Items.Add('PREPROD') }
        $CbOrg.IsEnabled = $script:INDOMAIN -or $script:PRD
        $CbOrg.SelectedItem = "$($row.Organisme)"
        Apply-OrganismeSelection
        $CbSite.SelectedItem = "$($row.Site)"
        Apply-SiteSelection
        if ($CbService.Items -notcontains "$($row.Service)") { [void]$CbService.Items.Add("$($row.Service)") }
        $CbService.Text = "$($row.Service)"
        Update-NameList
        if ($CbName.Items -notcontains "$($row.Nouveau_Nom)" -and "$($row.Nouveau_Nom)") { [void]$CbName.Items.Insert(0,"$($row.Nouveau_Nom)") }
        $CbName.SelectedItem = "$($row.Nouveau_Nom)"
        $script:OU_ACTUELLE  = "$($row.OU_Actuelle)"
        $script:OU_FINAL     = "$($row.OU_Destination)"
        Set-OULabel $LblCurrentOU 'OU actuelle  :' (Format-PestoOUForDisplay $script:OU_ACTUELLE)
        Set-OULabel $LblTargetOU  'OU cible     :' $script:OU_FINAL
    } finally { $script:Suspend = $prevSuspend }

    Update-FieldColor
    Select-NewName
    $prevSuspend = $script:Suspend; $script:Suspend = $true
    try {
        $ChkRename.IsChecked = if ($script:INDOMAIN) { [bool]$row.Renommer } else { $true }
        $ChkMove.IsChecked   = if ($script:INDOMAIN) { [bool]$row.Deplacer } else { $true }
        if (-not $script:INDOMAIN) { $ChkRename.IsEnabled = $false; $ChkMove.IsEnabled = $false }
        if ($ChkReboot -and $script:table.Columns.Contains('Reboot')) { $ChkReboot.IsChecked = [bool]$row.Reboot }
    } finally { $script:Suspend = $prevSuspend }
    Check-SameOU; Update-RebootOption; Update-AddButton; Update-QueueButtons
}

function Exit-EditMode {
    $script:EDIT_ROW_INDEX = -1
    $BtnAdd.Content = 'Ajouter à la file'
    $BtnEdit.Content = 'Modifier'
    $BtnEdit.ToolTip = 'Modifier le plan de la ligne surlignée dans le formulaire. Aucune action sur le poste à cette étape.'
}

function Get-PestoQueueRemovalState {
    <# Un retrait de file ne supprime jamais un ordinateur AD. Politique commune
       au bouton et au gestionnaire : aucune modification pendant un worker. #>
    param([AllowNull()][System.Data.DataRow]$Row)
    $canRemove=$false; $endsEdit=$false
    if($script:Running){
        $help='Retrait indisponible pendant une exécution. Attendez sa fin ou demandez Arrêter après cette action.'
    }elseif($script:PreflightRunning){
        $help='Retrait indisponible pendant le contrôle AD. Attendez sa fin ou utilisez Annuler le contrôle.'
    }elseif($null -eq $Row -or $null -eq $script:table -or
        -not [object]::ReferenceEquals($Row.Table,$script:table) -or
        $script:table.Rows.IndexOf($Row) -lt 0 -or $Row.RowState -eq [System.Data.DataRowState]::Deleted){
        $help='Cliquez sur la ligne à retirer. La case cochée sert à exécuter une action, pas à sélectionner une suppression.'
    }else{
        $canRemove=$true
        $endsEdit=($script:EDIT_ROW_INDEX -ge 0 -and $script:EDIT_ROW_INDEX -eq $script:table.Rows.IndexOf($Row))
        $help='Retirer uniquement la ligne surlignée, après confirmation. Aucun poste ni objet Active Directory ne sera supprimé. Les opérations déjà effectuées ne sont pas annulées.'
        if($endsEdit){$help+=' Les changements non enregistrés dans le formulaire seront abandonnés.'}
    }
    return [pscustomobject]@{CanRemove=$canRemove;EndsEdit=$endsEdit;Help=$help}
}

function Remove-PestoQueueRow {
    <# Mutation locale, sans appel AD. La DataRow réelle reste la cible même
       après tri/filtrage. Une erreur de sauvegarde remet la ligne à sa place. #>
    param([AllowNull()][System.Data.DataRow]$Row)
    $state=Get-PestoQueueRemovalState -Row $Row
    if(-not $state.CanRemove){throw $state.Help}
    $undoBefore=$script:table.Copy()
    $index=$script:table.Rows.IndexOf($Row)
    $oldEdit=[int]$script:EDIT_ROW_INDEX
    $editRow=$null
    if($oldEdit -ge 0 -and $oldEdit -lt $script:table.Rows.Count){$editRow=$script:table.Rows[$oldEdit]}
    $values=$Row.ItemArray.Clone()
    $name=[string]$Row.Nom_du_PC
    $key=Get-PestoPlanSignature -Row $Row
    try{
        $script:table.Rows.Remove($Row)
        # Une autre ligne peut être en édition : recalculer son index réel.
        # Ne jamais laisser son brouillon pointer sur le poste suivant.
        $script:EDIT_ROW_INDEX=if($null -ne $editRow){$script:table.Rows.IndexOf($editRow)}else{-1}
        # Version non silencieuse : le retrait n'est confirmé que si la file
        # peut être sauvegardée (sauf modes GUI/SIM, sans persistance par contrat).
        Save-PestoQueueCheckpoint
    }catch{
        $errorRecord=$_
        if($script:table.Rows.IndexOf($Row) -lt 0){
            $Row.ItemArray=$values
            $script:table.Rows.InsertAt($Row,[Math]::Min($index,$script:table.Rows.Count))
        }
        $script:EDIT_ROW_INDEX=$oldEdit
        throw $errorRecord
    }
    if($null -ne $script:PreflightCache -and $script:PreflightCache.ContainsKey($key)){
        [void]$script:PreflightCache.Remove($key)
    }
    $script:NmUsedSrc=$null
    Save-PestoQueueUndo -Before $undoBefore -Reason 'Retrait local de ligne'
    # Aucun changement de MutationUncertain et aucun effacement d'historique.
    return [pscustomobject]@{Name=$name;EndsEdit=$state.EndsEdit}
}

function Delete-SelectedRow {
    $row=$null
    if($Grid.SelectedItem -is [System.Data.DataRowView]){$row=$Grid.SelectedItem.Row}
    $state=Get-PestoQueueRemovalState -Row $row
    if(-not $state.CanRemove){return}
    $name=[string]$row.Nom_du_PC
    $message="Retirer l'action de la file pour `"$name`" ?`n`nCela retire uniquement cette ligne de Pesto. Le poste et son objet Active Directory ne seront ni supprimés ni modifiés.`nLes autres lignes, même cochées, restent dans la file."
    if($state.EndsEdit){$message+="`n`nLes changements non enregistrés de cette ligne seront abandonnés."}
    if([string]$row.Statut){$message+="`n`nRetirer ce résultat n'annule pas les opérations déjà effectuées. Le journal et l'historique sont conservés."}
    if(-not (Confirm-YesNo -Msg $message -Confirm $true)){return}
    try{
        # Revalide aussi le verrou et l'appartenance à la table après la modale.
        $result=Remove-PestoQueueRow -Row $row
    }catch{
        Write-Log 'Retrait de la file refusé ; la ligne est conservée.' 'ERROR' $_ 'file'
        Sync-Grid;Update-QueueButtons
        Show-MsgError "Retrait impossible : la ligne est conservée.`n$($_.Exception.Message)" 'File Pesto'
        return
    }
    if($result.EndsEdit){Exit-EditMode}
    Sync-Grid;Update-QueueButtons;Update-AddButton
    Add-LogLine "File : $($result.Name) retiré de la liste. Aucun poste ni objet AD supprimé." 'info'
}

###############################################################################
#  SECTION 11 — EXÉCUTION DE LA FILE
###############################################################################

$script:OK_CODES  = @(10,20,30,33,77)
$script:NOK_CODES = @(11,13,21,31,32,69,88,89,91,96,97,98,99)


$script:PestoWorkerCoreNames = @(
 'Publish-PestoWorkerLog','Set-PestoWorkerStage','Assert-PestoWorkerMayContinue',
 'Get-PestoIdentityChangeReason','Get-PestoWindowsAuthIdentity','Get-PestoDomainIdentityWarning','Add-PestoDomainIdentityCause','Invoke-PestoWindowsLocalRename',
 'Get-PestoNameSiteCode','Get-PestoSiteContainerDN','Get-PestoRenameMoveDecision','Test-PestoDnsName','Split-PestoDistinguishedName','Get-PestoParentDN','Get-PestoDomainFromDN','Test-PestoDNWithinScope','Test-PestoOUInConfiguredScope','Test-QueueRowSafe','Test-PestoConfirmedChange','Protect-PestoLogText','New-PestoTaskService','Release-PestoComObject','Get-PestoTaskArgument','Test-PestoPipeClient','New-PestoElevatedHelperScript','Invoke-PestoElevatedLocalChange',
 'Test-PestoComputerName','Test-PestoGeneratedComputerName','Test-PestoOUPath','Get-ADParams','Find-ADComputerByName','Get-ComputerOU','Get-AllComputersInOU','Update-ComputersNoms',
 'Assert-PestoTargetNameAvailable','New-ActionResult','ConvertTo-PestoQuotedArg','Get-PestoSecretArgIndexes','Invoke-PestoProcess','Invoke-PestoSchtasks','ConvertTo-PestoTaskFailureCode','Get-PestoSchtasksTransportArgs','Get-PestoSchtasksHint',
 'Test-PestoIsAdministrator','New-PestoRunOnceTaskXml','ConvertTo-PestoPowerShellLiteral','Get-PestoTaskRunResult','Get-PestoRemoteTaskLogTail','Invoke-PestoSystemTaskScript','Invoke-PestoDsregLeaveLocal','Invoke-PestoDsregLeaveBeforeRename',
 'New-PestoRenameTaskScript','Invoke-RenameComputerTaskFallback','Request-ComputerReboot','Invoke-PestoElevatedDomainJoin','AddToDomain','RenameComputer','MoveComputer','GoJoinDomain','GoRenameOnly','GoMoveOnly','Wait-ADComputerVisible','GoRenameAndMove','Go',
    'Assert-PestoStoredMutationReady','Get-PestoDirectStatePath','Read-PestoDirectReceipt','Get-PestoJoinStatePath','Read-PestoJoinReceipt'
)
$script:PestoWorkerCoreNames+=@('Get-PestoFacetPattern','New-PestoNameLdapPattern','Get-PestoNameSeriesBase','Get-PestoNameNumber','Format-PestoNameNumber','Set-PestoActiveNamingConvention','New-PestoNameFromSeries','Assert-PestoAttributeChanges','Get-PestoCampaignPolicy','Get-PestoOperatorSid','Get-PestoBytesHash','Get-PestoCampaignPlanHash','Assert-PestoCampaignApproval','Get-PestoAutomationMachineId','ConvertTo-PestoCanonicalValue','ConvertTo-PestoScenario','Assert-PestoScenarioValues','Get-PestoPlanScenarioValues','Initialize-PestoRuntimeTypes','Get-PestoNativeFailureCode','Import-PestoADModule','Assert-PestoPlainPath','Get-PestoInterventionRoot','Read-PestoIntervention','Get-PestoInterventions','Write-PestoIntervention','Test-PestoInterventionConflict','Start-PestoIntervention','Set-PestoEffect','Complete-PestoIntervention','Assert-PestoRenameTarget','Invoke-PestoGuardedAction','Get-PestoPostObservation','ConvertTo-PestoFilterLiteral','Get-PestoJoinLocalStatus','Write-PestoJoinReceipt','Invoke-PestoAuditSinkReceipt','Write-PestoAtomicText','Test-PestoLedgerResume')
$script:PestoWorkerCoreNames+=@('Get-PestoTaskDefinitionHash','Set-PestoTaskEvidence','Assert-PestoTaskDefinition')
$script:PestoWorkerCoreNames+=@('ConvertTo-PestoNameParts','New-PestoComputerName','Get-PestoNamingLayout','Get-PestoActiveNamingConvention','Get-PestoDefaultNamingConvention','Get-PestoNamingResolutionNonce','Assert-PestoNamingConvention','Get-PestoOutcome','Get-PestoStableHash','Get-PestoPlanFingerprint','Assert-PestoConfirmedPlan','ConvertTo-PestoDeploymentMetadata','Assert-PestoClosedObject','Get-PestoNativeGuidance','Get-PestoReadFailure','Invoke-PestoReadRetry')
$script:PestoWorkerCoreNames+=@('New-PestoExecutionPlan','Test-PestoFreshCheck')
$script:PestoWorkerCoreNames+=@('New-PestoReadCoordinator','Invoke-PestoReadCoalesced','Read-PestoInterventionCatalogCachedCore','New-PestoInterventionCatalogCache','Clear-PestoInterventionCatalogCache','Copy-PestoCatalogValue','Get-PestoInterventionCatalogCached','Get-PestoManagedPolicy','Merge-PestoManagedPolicy','ConvertTo-PestoPolicy','Assert-PestoOperationPolicy','Add-PestoShareConnection','Connect-PestoCoordinationShare','Get-PestoCoordinationRoot','Get-PestoCoordinationKeys','Enter-PestoCoordination','Exit-PestoCoordination','Add-PestoInterventionEvent','Write-PestoReconciliationAudit')
$script:PestoWorkerCoreNames+=@('Test-PestoPropertyPresent','Get-PestoLocalHealth','Test-PestoOptionalPostCheckReceipt','Test-PestoAcknowledgedReceipt','Get-PestoJoinReceiptDecision','Get-PestoJoinReceiptStatus')
$script:PestoWorkerCoreNames+=@('ConvertTo-PestoObservationSnapshot','Assert-PestoObservationSnapshot','Assert-PestoAcknowledgement','Set-PestoInitialObservation')
$script:PestoWorkerCoreNames+=@('Assert-PestoJoinReceiptData','Test-PestoJoinIntervention','Assert-PestoJoinEvidence','Set-PestoInitialJoinObservation','Set-PestoJoinNativeStatus','Get-PestoJoinObservationDecision','ConvertFrom-PestoLegacyJoinReceipt')
$script:PestoWorkerCoreNames=@($script:PestoWorkerCoreNames|Select-Object -Unique)
$script:PestoWorkerCoreSourceCache = $null
function Get-PestoWorkerCoreSource {
    if($script:PestoWorkerCoreSourceCache){ return ($script:PestoWorkerCoreSourceCache+(Get-PestoNamingContextSource)) }
    $sb=New-Object Text.StringBuilder
    foreach($name in $script:PestoWorkerCoreNames){
      $cmd=Get-Command $name -CommandType Function -ErrorAction Stop
      [void]$sb.AppendLine("function $name {");[void]$sb.AppendLine($cmd.Definition);[void]$sb.AppendLine('}')
    }
    $script:PestoWorkerCoreSourceCache=$sb.ToString()
    return ($script:PestoWorkerCoreSourceCache+(Get-PestoNamingContextSource))
}
$script:PestoQueueWorker = {
    param($Request,$CoreSource)
    Set-StrictMode -Off;$ErrorActionPreference='Stop'
    $script:PestoQueueMonitor=$Request.Telemetry
    $script:WorkerLogs=[System.Collections.Generic.List[object]]::new()
    function Write-Log {
      param($Message,$Level='INFO',$ErrorRecord=$null,$Context='worker')
      $detail=''
      if($ErrorRecord){
        try{$detail=[string]$ErrorRecord.Exception.Message}catch{}
        try{if($ErrorRecord.FullyQualifiedErrorId){$detail+=$(if($detail){' | '}else{''})+[string]$ErrorRecord.FullyQualifiedErrorId}}catch{}
      }
      if($script:PestoQueueMonitor){Publish-PestoWorkerLog -Text ([string]$Message+$(if($detail){' | '+$detail}else{''})) -Level $Level -Context $Context}
      else{[void]$script:WorkerLogs.Add([pscustomobject]@{Text=[string]$Message;Level=[string]$Level;Context=[string]$Context;Detail=$detail})}
    }
    function Add-LogLine {param($Text,$Kind='info');Write-Log -Message $Text -Level $Kind -Context 'worker'}
    function Show-MsgError{};function Show-MsgWarning{};function Show-MsgInfo{}
    # Stub sans param() : un paramètre nommé $Confirm fait planter PSScriptAnalyzer 1.24 (PSUseSupportsShouldProcess)
    # dans ce bloc imbriqué, donc la porte Verify-Release. Les appels -Msg/-Confirm restent acceptés (fonction simple).
    function Confirm-YesNo {return $true}
    function Invoke-DoEvents{}
    function Wait-Pumped {param([double]$Seconds=1);Start-Sleep -Milliseconds ([int]([Math]::Max(0,$Seconds)*1000))}
    $coreBlock=[scriptblock]::Create([string]$CoreSource)
    . $coreBlock
    Set-PestoWorkerStage 'Chargement du module Active Directory' ('Thread '+[Threading.Thread]::CurrentThread.ApartmentState)
    Assert-PestoWorkerMayContinue
    Import-PestoADModule -ADModulePath ([string]$Request.ADModulePath)
    Assert-PestoWorkerMayContinue

    $script:DC=[string]$Request.DC;$script:DOMAINE=[string]$Request.Domain;$script:cred=$Request.Credential
    $script:PREFIXE=[string]$Request.Prefix;$script:SIM=[bool]$Request.SIM;$script:GUI=$false;$script:SimOn=$false;$script:INDOMAIN=[bool]$Request.InDomain;$script:PRD=[bool]$Request.PRD
    $script:OU=$Request.OU;$script:OU_POSTES=[string]$Request.OUPostes;$script:OU_SCAN=[string]$Request.OUScan;$script:CLEAR_PROTECTION=[bool]$Request.ClearProtection;$script:DSREG_LEAVE=$false
    $script:OUV=$Request.OUSite
    $script:ExpectedObjectGuid=[string]$Request.ObjectGuid;$script:ExpectedSourceOU=[string]$Request.CurrentOU
    $script:ApprovedADModulePath=[string]$Request.ADModulePath
    $script:PestoReadOnly=[bool]$Request.ReadOnly;$script:PestoPolicy=$Request.Policy
    $script:ExpectedTargetOUGuid=[string]$Request.TargetOUGuid
    $script:EntraPolicy=if($Request.EntraPolicy -in @('HybridOnly','Disabled')){[string]$Request.EntraPolicy}else{'HybridOnly'}
    $script:AllowPasswordTaskFallback=($Request.AllowPasswordTaskFallback -is [bool] -and $Request.AllowPasswordTaskFallback)
    Set-PestoWorkerStage 'Validation du plan' 'Lecture et contrôles avant toute mutation'
    $errors=@(Test-QueueRowSafe -Nom $Request.Computer -NewName $Request.NewName -OU $Request.TargetOU -Ren $Request.Rename -Move $Request.Move)
    if($errors.Count){throw ("Précontrôle worker refusé : "+($errors -join '; '))}
    $script:Computers=@();$script:ComputersNoms=@()
    Assert-PestoWorkerMayContinue
    $operationMutex=$null;$operationOwned=$false
    try {
      if(-not $script:SIM){
        $operationMutex=[Threading.Mutex]::new($false,'Global\GP_PostMutation_v1')
        try{$operationOwned=$operationMutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$operationOwned=$true}
        if(-not $operationOwned){return [pscustomobject]@{Action=(New-ActionResult 96 'Une autre mutation Pesto est active sur ce poste. Aucune commande lancée.');Reboot=$null;Logs=@()}}
        try{Assert-PestoStoredMutationReady -OwnOperationId ([string]$Request.OperationId) -Plan (New-PestoExecutionPlan $Request)}catch{
          # Refus avant toute commande : 96 (non lancé), jamais 97 ; l'état persistant reste intact et à examiner dans Interventions.
          return [pscustomobject]@{Action=(New-ActionResult 96 ('État persistant non résolu : '+$_.Exception.Message+' Cette commande n''a pas été lancée. Consulter Interventions.'));Reboot=$null;Logs=@()}
        }
      }
    $result=@(Invoke-PestoGuardedAction -Request $Request)
    $action=if($result.Count -eq 1){$result[0]}else{$null}

    # Une action effectivement lancée ne peut jamais disparaître en "annulation".
    # Absence de résultat ou résultat mal formé = échec technique explicite.
    if($null -eq $action){
      $action=New-ActionResult 98 'Le worker a terminé sans résultat d''action. Aucune modification n''est considérée comme réussie.'
    } elseif(-not $action.PSObject.Properties['ExitCode']){
      $action=New-ActionResult 98 'Le worker a renvoyé un résultat invalide sans ExitCode.'
    } elseif($action.ExitCode -isnot [int]){
      $action=New-ActionResult 97 'Code moteur non typé : aucune nouvelle action ni redémarrage autorisé.'
    } elseif(-not $action.PSObject.Properties['ExitMsg']){
      $action=New-ActionResult 98 ("Résultat d'action incomplet (code {0})." -f [int]$action.ExitCode)
    }
    $reboot=$null
    if([bool]$Request.Reboot -and $action -and ([int]$action.ExitCode -in @(10,20,30,33,77))){
      Assert-PestoWorkerMayContinue
      Set-PestoWorkerStage 'Demande de redémarrage' 'Option explicitement cochée'
      $reboot=Request-ComputerReboot -ComputerName ([string]$Request.Computer) -DelaySeconds 0
    }
    Set-PestoWorkerStage 'Résultat reçu' ('Code '+[string]$action.ExitCode)
    [pscustomobject]@{Action=$action;Reboot=$reboot;Logs=$script:WorkerLogs.ToArray()}
    } finally {
      if($operationMutex){try{if($operationOwned){$operationMutex.ReleaseMutex()}}finally{$operationMutex.Dispose()}}
    }
}

function Set-PestoQueueUiLocked {
    param([bool]$Locked)
    # Verrouillage de conteneurs : aucun handler enfant ne peut le contourner.
    if($ConfigPanel){$ConfigPanel.IsEnabled=-not $Locked}
    if($SetTabs){$SetTabs.IsEnabled=-not $Locked}
    foreach($b in @($BtnRun,$BtnAdd,$BtnEdit,$BtnDelete,$BtnClear,$BtnImport,$BtnExport,$BtnCheckAll,$BtnUncheckAll,$SetBtnSave,$SetBtnReload,$NmBtnRefresh,$NmBtnRetryNames,$BtnPreview,$BtnRetryMove,$BtnBulk,$BtnPreflight,$BtnHtmlReport,$BtnHistory)){
        if($b){$b.IsEnabled=-not $Locked}
    }
    $Grid.IsReadOnly=$Locked
    $BtnStop.IsEnabled=$Locked
    if(-not $Locked){Update-QueueButtons;Update-AddButton}
}

function Stop-PestoQueueRemainingForSafety {
    param($State,[string]$Reason)
    if(-not $State){return}
    $script:MutationUncertain=$true
    for($i=[int]$State.Index;$i -lt $State.Items.Count;$i++) {
        $r=$State.Items[$i].Row; $r.Statut='NON LANCÉ';$r.Message=$Reason;$r.Traiter=$false
        $State.CancelCount++
    }
    $State.Index=$State.Items.Count
    Add-LogLine "ARRÊT DE SÉCURITÉ : $Reason" 'err'
    Write-AuditLine "ARRÊT DE SÉCURITÉ : $Reason" 'err'
    Save-PestoQueueCheckpointSafe -Phase 'Uncertain'
}

function Complete-PestoQueueRun {
    $st=$script:QueueRunState;if(-not $st){return}
    $counted=[int]$st.OkCount+[int]$st.KoCount+[int]$st.CancelCount
    if($counted -ne [int]$st.Total) {
        $script:MutationUncertain=$true
        Write-Log "Comptage incohérent : $counted / $($st.Total)." 'ERROR' $null 'queue'
        if($counted -lt $st.Total){$st.KoCount+=($st.Total-$counted)}
    }
    $uncertain=@($st.Items|Where-Object{$_.Row.Statut -in @('INCERTAIN','TECHNIQUE','PROTECTION')}).Count
    $prefix=if($script:SIM -or $script:GUI){'SIMULATION'}elseif($script:MutationUncertain){'File arrêtée pour vérification'}else{'Terminé'}
    $failures=[Math]::Max(0,[int]$st.KoCount-$uncertain)
    $summary="${prefix} : $($st.Total) action(s) | $($st.OkCount) réussie(s), $failures échouée(s), $uncertain à vérifier, $($st.CancelCount) non lancée(s)."
    if(Test-PestoQueueWorkerStillActive){$summary+=' Un worker Windows est encore actif : surveillance conservée, ne pas relancer.'}
    try{Save-PestoRunHistory -State $st}catch{Write-Log 'Synthèse historique non enregistrée ; le journal reste la référence.' 'WARN' $_ 'history'}
    Stop-PestoPilotagePulse
    $script:LastPilotageNote=$summary;$LblQueueActivity.Text=$summary
    $script:Running=$false;$script:QueueRunState=$null;$script:QueueCurrentTicket=$null
    $Progress.Visibility='Collapsed';Set-PestoQueueUiLocked $false
    Add-LogLine $summary $(if($st.KoCount -or $st.CancelCount){'warn'}else{'ok'})
    $LblStatus.Text=$summary
    if($script:MutationUncertain){$LblStatus.Text+=' VERROU DE SÉCURITÉ ACTIF.'}
    Save-PestoQueueCheckpointSafe -Phase $(if($script:MutationUncertain){'Uncertain'}else{'Idle'})
    $endMsg=$summary
    if($st.RestartNeeded){$endMsg+="`nRedémarrage nécessaire pour appliquer les changements de nom/jonctions."}
    if($script:MutationUncertain){$endMsg+="`nVérifiez l'état réel des postes avant de lever le verrou de sécurité."}
    Set-PestoAccessibleStatus $summary
    if($script:PestoNotifyBatch -and -not $Win.IsActive){try{[System.Media.SystemSounds]::Asterisk.Play()}catch{}}
    Show-PestoOutcome -Title 'Bilan de la file' -Message $endMsg
    Request-PestoAffectedRefresh -Names @($st.Items|ForEach-Object{$_.Computer;$_.NewName})
}

function Start-PestoNextQueueTask {
    $st=$script:QueueRunState
    if(-not $st -or (Test-PestoAsyncOperationRunning 'QueueAction')){return}
    if($script:QueueStopRequested) {
        for($i=$st.Index;$i -lt $st.Items.Count;$i++) {
            $r=$st.Items[$i].Row;$r.Statut='NON LANCÉ';$r.Message='Arrêt demandé par l''opérateur avant lancement.';$r.Traiter=$false;$st.CancelCount++
        }
        $st.Index=$st.Items.Count
    }
    if($st.Index -ge $st.Items.Count){Complete-PestoQueueRun;return}
    $item=$st.Items[$st.Index];$st.Index++
    if($st.Confirm) {
        $verb=if(-not $script:INDOMAIN){'JONCTION'}elseif($item.Rename -and $item.Move){'RENOMMER puis DÉPLACER'}elseif($item.Rename){'RENOMMER'}else{'DÉPLACER'}
        if(-not(Confirm-YesNo -Msg "$verb : $($item.Computer)`nNouveau nom : $($item.NewName)`nOU : $($item.TargetOU)" -Confirm $true)) {
            $item.Row.Statut='ANNULÉ';$item.Row.Traiter=$false;$st.CancelCount++;Sync-Grid;Request-PestoQueuePump;return
        }
    }
    $planText=if(-not $script:INDOMAIN){'JONCTION'}elseif($item.Rename -and $item.Move){'RENOMMER puis DEPLACER (changement de site)'}elseif($item.Rename){'RENOMMER seulement (sans deplacement)'}else{'DEPLACER seulement (demande explicite)'}
    Add-LogLine "Plan : $planText | $($item.Computer) -> $($item.NewName) | Reboot=$($item.Reboot)" 'info'
    $script:QueueCurrentTicket=[pscustomobject]@{Item=$item;Started=Get-Date;Completed=$false;Monitor=$null}
    $item.Row.Statut='EN COURS';$item.Row.Code='';$item.Row.Message='';$item.Row.Horodatage=[DateTime]::UtcNow.ToString('o')
    $LblStatus.Text="$($st.Mode) — $($st.Index)/$($st.Total) : $($item.Computer)";Sync-Grid
    if($script:GUI -or $script:SimOn) {
        $code=if(-not $script:INDOMAIN){10}elseif($item.Rename -and $item.Move){77}elseif($item.Rename){20}else{30}
        Complete-PestoQueueItem -WorkerResult ([pscustomobject]@{Action=(New-ActionResult $code 'Démonstration : aucune commande Windows/AD exécutée.');Logs=@();Reboot=$null})
        return
    }
    if(-not $script:SIM) {
        $item.Row.Operation_ID=[Guid]::NewGuid().ToString('N')
        $script:QueueOperationIds=@($script:QueueOperationIds)+@([string]$item.Row.Operation_ID)
        try {
            if(-not(Test-PestoAuditWritable)){throw 'Journal indisponible avant mutation.'}
            Save-PestoQueueCheckpoint -Phase 'Active'
        } catch {
            # Frontiere explicite : le worker n'a pas encore ete cree.
            Complete-PestoQueueNotStarted -Failure $_;return
        }
    }
    $ou=@{};foreach($k in $script:OU.Keys){$ou[$k]=$script:OU[$k]}
    $ouv=@{};foreach($k in $script:OUV.Keys){$ouv[$k]=$script:OUV[$k]}
    $monitor=New-PestoQueueMonitor -Computer $item.Computer
    $script:QueueCurrentTicket.Monitor=$monitor
    Add-LogLine 'Worker STA demandé. Les étapes sont désormais journalisées pendant le traitement ; limite de surveillance : 300 s.' 'info'
    $req=[pscustomobject]@{
        Telemetry=$monitor
        OperationId=[string]$item.Row.Operation_ID;ResumeId=[string]$item.Row.Resume_ID
        Computer=$item.Computer;NewName=$item.NewName;TargetOU=$item.TargetOU;CurrentOU=$item.CurrentOU
        Rename=$item.Rename;Move=$item.Move;Reboot=$item.Reboot;ObjectGuid=[string]$item.Row.Objet_GUID
        TargetOUGuid=$item.TargetOUGuid;ConfigStamp=$item.ConfigStamp;PlanFingerprint=$item.PlanFingerprint;Policy=(ConvertTo-PestoPolicy $script:CFG.POLICY);ReadOnly=[bool]$script:PestoReadOnly
        DC=$script:DC;Domain=$script:DOMAINE;Credential=$script:cred;Prefix=$script:PREFIXE
        SIM=[bool]$script:SIM;InDomain=[bool]$script:INDOMAIN;PRD=[bool]$script:PRD;OU=$ou;OUSite=$ouv
        OUPostes=$script:OU_POSTES;OUScan=$script:OU_SCAN;ClearProtection=[bool]$script:CLEAR_PROTECTION
        EntraPolicy=[string](@($script:CFG.CONF)[0].EntraPolicy);AllowPasswordTaskFallback=(ConvertTo-PestoPolicy $script:CFG.POLICY).AllowPasswordTaskFallback
        ADLoaderSource=(Get-PestoADLoaderSource);ADModulePath=(Join-Path $BasePath 'ActiveDirectory.psd1')
    }
    # Callbacks nommés : pas de $script: capturé dans un module GetNewClosure.
    [void](Start-PestoAsyncOperation -Name 'QueueAction' -ScriptBlock $script:PestoQueueWorker -ArgumentList @($req,(Get-PestoWorkerCoreSource)) `
        -ApartmentState STA -QueueMonitor $monitor -TimeoutSec 900 `
        -OnSuccess {param($wr) Complete-PestoQueueItem -WorkerResult $wr} `
        -OnError {param($e) Complete-PestoQueueItem -Failure $e})
}

function Run-Queue {
    $script:PestoQueueUndo=$null # Aucun undo local ne traverse une tentative d’exécution.
    if($script:PestoReadOnly){Show-MsgInfo 'Consultation : aucune opération ne peut être exécutée.';return}
    if($script:DirectBusy -or (Test-PestoDirectTargetBarrier)){return}

    if(-not $script:INDOMAIN){Set-PestoUxPage 'Join';return}
    if($script:JoinBusy -or $script:JoinLocked -or (Test-PestoAsyncOperationRunning 'DomainJoin')){Show-MsgWarning 'Une jonction locale est en cours ou attend une vérification.';return}

    if($script:PreflightRunning -or $script:Running){return};Ensure-Table
    if(Test-PestoGlobalSafetyBarrier){Show-MsgWarning 'Verrou de sécurité : vérifiez les opérations précédentes avant toute nouvelle écriture.';return}
    if($script:CfgRestartRequired){Show-MsgWarning 'Configuration modifiée : redémarrez Pesto avant toute nouvelle exécution.';return}
    if(Test-PestoAsyncOperationRunning 'DirectoryRefresh'){Show-MsgWarning 'L''annuaire est en cours d''actualisation.';return}
    try{[void]$Grid.CommitEdit([Windows.Controls.DataGridEditingUnit]::Cell,$true);[void]$Grid.CommitEdit([Windows.Controls.DataGridEditingUnit]::Row,$true)}catch{Show-MsgError 'Impossible de valider la cellule en cours.';return}
    $rows=@($script:table.Rows|Where-Object{$_.Traiter -eq $true})
    if(-not $rows.Count){Show-MsgInfo 'Aucune ligne cochée.';return}
    if($rows.Count -gt (ConvertTo-PestoPolicy $script:CFG.POLICY).MaxBatch){Show-MsgWarning 'La sélection dépasse la limite de lot autorisée par la politique.';return}
    if(-not ($script:SIM -or $script:GUI -or $script:SimOn)){
        if(-not (Test-PestoIsAdministrator)){Show-MsgError 'File non lancée : les droits administrateur locaux ne sont pas actifs. Relancez Pesto.exe pour accepter l''UAC avant la connexion.';return}
        $credentialReason=Get-PestoExplicitCredentialRequirement -InDomain ([bool]$script:INDOMAIN) -Rows $rows -LocalComputerName $env:COMPUTERNAME
        if($credentialReason -and $script:cred -isnot [Management.Automation.PSCredential]){
            Show-MsgError ($credentialReason+"`nFermez Pesto puis utilisez Pesto.exe -AskCredential, pour choisir explicitement ce parcours.`nAucune action de ce lot n'a été lancée.");return
        }
    }
    $errors=New-Object 'System.Collections.Generic.List[string]';$sources=@{};$targets=@{}
    if(-not $script:INDOMAIN -and $rows.Count -ne 1){$errors.Add('Hors domaine : une seule jonction locale autorisée.')}
    foreach($r in $rows) {
        $decision=Update-PestoQueueRenamePlan -Row $r
        if(-not $decision.Valid){$errors.Add("$($r.Nom_du_PC) : $($decision.Error)")}
        foreach($e in @(Test-QueueRowSafe -Nom $r.Nom_du_PC -NewName $r.Nouveau_Nom -OU $r.OU_Destination -Ren $r.Renommer -Move $r.Deplacer)){$errors.Add("$($r.Nom_du_PC) : $e")}
        if($r.Statut -in @('OK','VÉRIFIÉ','SIMULÉ','PARTIEL','PROTECTION','INCERTAIN','TECHNIQUE','EN COURS')){$errors.Add("$($r.Nom_du_PC) : résultat précédent à examiner ($($r.Statut)). Recréez la ligne après vérification ; un succès/état incertain ne se rejoue pas.")}
        $src=[string]$r.Nom_du_PC
        if($sources.ContainsKey($src)){$errors.Add("Source dupliquée : $src")}else{$sources[$src]=$true}
        if($r.Renommer){$target=[string]$r.Nouveau_Nom;if($targets.ContainsKey($target)){$errors.Add("Nom cible dupliqué : $target")}else{$targets[$target]=$true}}
    }
    foreach($target in $targets.Keys){if($sources.ContainsKey($target)){$errors.Add("Renommages dépendants/cycliques interdits : $target est aussi une source de la file.")}}
    if(-not $errors.Count -and -not($script:GUI -or $script:SIM)){
        $stale=@($rows|Where-Object{-not(Test-PestoFreshCheck -Row $_ -Signature (Get-PestoPlanSignature $_))})
        if($stale.Count){
            if($rows.Count -gt 200){Show-MsgWarning 'Un lot est limité à 200 lignes pour sa vérification avant engagement.';return}
            if($script:EDIT_ROW_INDEX -ge 0){Show-MsgWarning 'Terminez la modification de la ligne avant de contrôler le lot.';return}
            $script:PreflightThenExecute=$true;Start-PestoQueuePreflight;return
        }
    }
    foreach($issue in @(Get-PestoPreflightRunIssues -Rows $rows)){$errors.Add($issue)}
    if($errors.Count){Show-MsgError ("File non exécutée :`n`n"+($errors -join "`n"));return}
    $mode=if($script:SIM -or $script:GUI){'SIMULATION'}else{'RÉEL'}
    $reboots=@($rows|Where-Object{$_.Reboot}).Count
    $renames=@($rows|Where-Object{$_.Renommer}).Count
    $moves=@($rows|Where-Object{$_.Deplacer}).Count
    Sync-Grid
    $controlSummary=Get-PestoPreflightConfirmationText -Rows $rows
    $controlSummary+="`n`nPOSTE PAR POSTE`n"+(@($rows|ForEach-Object{[pscustomobject]@{Poste=$_.Nom_du_PC;Nom_prevu=$_.Nouveau_Nom;Action=(Get-PestoRowPlanText $_ ([bool]$script:INDOMAIN));OU=$_.OU_Destination;Redemarrer=[bool]$_.Reboot}})|Format-Table -Wrap -AutoSize|Out-String -Width 160)
    if($script:PestoPolicy.AllowPasswordTaskFallback){$controlSummary+="`nPolitique : un repli par tâche Windows utilisant le mot de passe du compte AD est autorisé en cas de refus confirmé. Les tâches sont suivies ; aucun repli après résultat incertain."}
    if(-not(Confirm-YesNo -Msg "$mode : exécuter $($rows.Count) action(s) ?`nRenommages : $renames | Déplacements : $moves`nRedémarrages demandés : $reboots.`n`nAvant renommage : état Entra relu sur la cible. Retrait seulement si hybride et autorisé ; réinscription à vérifier séparément.`nUn renommage déplace uniquement si le site change.`nUtilisez Prévisualiser pour examiner le plan sans exécuter.`n`n$controlSummary" -Confirm $true)){return}
    $items=@(foreach($r in $rows){[pscustomobject]@{Row=$r;Computer=[string]$r.Nom_du_PC;NewName=[string]$r.Nouveau_Nom;TargetOU=[string]$r.OU_Destination;CurrentOU=[string]$r.OU_Actuelle;Rename=[bool]$r.Renommer;Move=[bool]$r.Deplacer;Reboot=[bool]$r.Reboot;ObjectGuid=[string]$r.Objet_GUID;TargetOUGuid=[string]$r.TargetOUGuid;ConfigStamp=(Get-PestoConfigurationSignature $script:CFG)}})
    foreach($i in $items){$p=New-PestoExecutionPlan ([pscustomobject]@{Computer=$i.Computer;NewName=$i.NewName;CurrentOU=$i.CurrentOU;TargetOU=$i.TargetOU;ObjectGuid=$i.ObjectGuid;TargetOUGuid=$i.TargetOUGuid;Rename=$i.Rename;Move=$i.Move;Reboot=$i.Reboot;Domain=$script:DOMAINE;DC=$script:DC;ConfigStamp=$i.ConfigStamp});$i|Add-Member -NotePropertyName PlanFingerprint -NotePropertyValue (Get-PestoPlanFingerprint $p)}
    $script:QueueRunState=[pscustomobject]@{RunId=[Guid]::NewGuid().ToString('N');Started=(Get-Date);Mode=$mode;Items=$items;Index=0;Total=$items.Count;OkCount=0;KoCount=0;CancelCount=0;RestartNeeded=$false;Pilot=[bool]$Win.FindName('QueuePilot').IsChecked;Confirm=[bool]$ChkConfirm.IsChecked}
    $script:Running=$true;$script:QueueStopRequested=$false;Set-PestoQueueUiLocked $true
    $Progress.Visibility='Visible';$Progress.Maximum=$items.Count;$Progress.Value=0
    Add-LogLine "DÉBUT $mode — $($items.Count) action(s)." 'head'
    Start-PestoPilotagePulse
    Request-PestoQueuePump
}

###############################################################################
#  SECTION 12 — IMPORT / EXPORT CSV
###############################################################################
function Export-Queue {
    if($script:PreflightRunning -or $script:Running){return};Ensure-Table
    if(-not $script:table.Rows.Count){Show-MsgInfo 'La file est vide.';return}
    $dlg=[Microsoft.Win32.SaveFileDialog]::new();$dlg.Filter='CSV UTF-8 (*.csv)|*.csv';$dlg.FileName='Pesto_export_'+(Get-Date -Format 'yyyyMMdd_HHmmss')+'.csv'
    if(-not $dlg.ShowDialog()){return}
    try{
        $rows=@(foreach($r in $script:table.Rows){
            $o=[ordered]@{}
            foreach($col in $script:table.Columns){
                $value=$r[$col.ColumnName]
                $o[$col.ColumnName]=if($col.DataType -eq [bool]){[bool]$value}else{ConvertTo-PestoSafeCsvCell (Protect-PestoLogText ([string]$value))}
            }
            [pscustomobject]$o
        })
        $text=($rows|ConvertTo-Csv -Delimiter ';' -NoTypeInformation)-join "`r`n"
        # BOM facilite l'ouverture UTF-8 dans Excel ; les lectures Pesto tolèrent le BOM.
        Write-PestoAtomicText -Path $dlg.FileName -Text ([string][char]0xFEFF+$text+"`r`n")
        Add-LogLine "Export de la file et de ses résultats : $($dlg.FileName)" 'info'
    }catch{Write-Log 'Export CSV impossible.' 'ERROR' $_ 'csv';Show-MsgError $_.Exception.Message}
}
# Test-PestoOUInConfiguredScope : composant séparé.
# Test-QueueRowSafe : composant séparé.
function Import-Queue {
    if($script:DirectBusy -or (Test-PestoDirectTargetBarrier)){return}

    if($script:PreflightRunning -or $script:Running -or (Test-PestoGlobalSafetyBarrier) -or $script:CfgRestartRequired){Show-MsgWarning 'Import interdit tant que le contexte est verrouillé.';return}
    Ensure-Table
    $dlg=[Microsoft.Win32.OpenFileDialog]::new();$dlg.Filter='CSV UTF-8 (*.csv)|*.csv'
    if(-not $dlg.ShowDialog()){return}
    try{
        if((Get-Item -LiteralPath $dlg.FileName).Length -gt 8MB){throw 'CSV trop volumineux : maximum 8 Mio.'}
        $entries=@(Import-Csv -LiteralPath $dlg.FileName -Delimiter ';' -Encoding UTF8)
        if(-not $entries.Count){Show-MsgInfo 'Le CSV est vide.';return}
        if($entries.Count -gt 5000){throw 'Maximum 5 000 lignes par import.'}
        $headers=@($entries[0].PSObject.Properties.Name)
        $missing=@(@('Renommer','Deplacer','Nom_du_PC','Nouveau_Nom','OU_Destination')|Where-Object{$_ -notin $headers})
        if($missing.Count){throw "Colonnes absentes : $($missing -join ', ')."}
        $preview=New-PestoCsvQueueCandidate -Entries $entries -Existing $script:table -Headers $headers -InDomain ([bool]$script:INDOMAIN)
        if(-not $preview.Valid){Show-PestoTextReport 'Import refusé — file inchangée' ($preview.Errors -join "`r`n");return}
        $candidate=$preview.Candidate
        if([Windows.MessageBox]::Show("Importer $($entries.Count) ligne(s) ?`nElles seront toutes décochées. Vérifiez les actions avant sélection.",'Import validé','YesNo','Question','No') -ne 'Yes'){return}
        $undoBefore=$script:table.Copy()
        $script:table=$candidate;$Grid.ItemsSource=$candidate.DefaultView;$script:NmUsedSrc=$null
        if(@($candidate.Rows|Where-Object{$_.Statut -in @('INCERTAIN','TECHNIQUE','PROTECTION')}).Count){$script:MutationUncertain=$true}
        Add-LogLine "Import CSV complet : $($entries.Count) ligne(s), aucune exécution automatique." 'info'
        Save-PestoQueueCheckpointSafe -Phase $(if($script:MutationUncertain){'Uncertain'}else{'Idle'})
        Save-PestoQueueUndo -Before $undoBefore -Reason 'Import local CSV'
        Update-PestoQueueFilter;Sync-Grid;Update-QueueButtons;Update-AddButton
    }catch{Write-Log 'Import CSV refusé ; file inchangée.' 'ERROR' $_ 'csv';Show-MsgError $_.Exception.Message}
}

###############################################################################
#  SECTION 12b — MODE DÉMONSTRATION : activé UNIQUEMENT via cfg.json (DEBUG.GUI=true).
#  Pas de bouton ni de bac à sable runtime. En mode GUI, New-DemoComputers fournit
#  des données fictives et $script:GUI court-circuite tout appel Active Directory.
###############################################################################

###############################################################################
#  SECTION 12c — ONGLET « NOMS DISPONIBLES » (moteur de nommage COMMUN)
#  Consomme $script:ComputersNoms (périmètre OU_SCAN ; = scan Actions si OU_SCAN=ROOT).
###############################################################################

function Get-NameParts {
    param([string]$Name)
    $part=ConvertTo-PestoNameParts $Name
    if(-not $part){return $null}
    [pscustomobject]@{Lettre=$part.Type;Prefixe=$part.Prefix;Site=$part.Site;Equipe=$part.Service;Num=$part.Number.ToString('D3');Type=$part.Label}
}
function New-DemoComputers {
    <# Jeu fictif réellement déterministe (sans String.GetHashCode()). #>
    $sites = 'AA','BC','LY'; $equipes = 'ADM','INF','RH0'
    $list = [System.Collections.Generic.List[object]]::new()
    foreach ($ty in 'P','S','V') {
        foreach ($s in $sites) {
            foreach ($e in $equipes) {
                $base = "$ty$($script:PREFIXE)$s$e"
                [int64]$seed = 17
                foreach ($ch in "$ty|$s|$e".ToCharArray()) { $seed = (($seed * 31) + [int]$ch) % 2147483647 }
                $count = 2 + [int]($seed % 5)
                for ($i = 1; $i -le $count; $i++) {
                    $nm = "$base$($i.ToString('D3'))"
                    [void]$list.Add([PSCustomObject]@{
                        Name = $nm
                        DistinguishedName = "CN=$nm,OU=Demo,DC=demo,DC=local"
                    })
                }
            }
        }
    }
    return ,@($list)
}
function Build-NmIndex {
    # Un site encore vide reste visible grâce au catalogue de configuration.
    $sites=@{};$teams=@{};$pairs=@{}
    foreach($tag in @($script:CFG.TAGS)){
        $code=([string]$tag.Tag).ToUpperInvariant()
        if($code -match (Get-PestoFacetPattern Site)){$sites[$code]=$true}
    }
    foreach($group in @($script:CFG.NameCatalogue)){
        $code=([string]$group.Site).ToUpperInvariant();$team=([string]$group.Service).ToUpperInvariant()
        if($code -match (Get-PestoFacetPattern Site)){$sites[$code]=$true}
        if($team -match (Get-PestoFacetPattern Service)){$teams[$team]=$true}
        if($code -match (Get-PestoFacetPattern Site) -and $team -match (Get-PestoFacetPattern Service)){$pairs[$code+'|'+$team]=$true}
    }
    foreach($c in @($script:ComputersNoms)){
        $parts=ConvertTo-PestoNameParts ([string]$c.Name) $script:PREFIXE
        if($parts){$sites[$parts.Site]=$true;$teams[$parts.Service]=$true;$pairs[$parts.Site+'|'+$parts.Service]=$true}
    }
    $script:NmSites=@($sites.Keys|Sort-Object);$script:NmEquipes=@($teams.Keys|Sort-Object)
    # Couples site/service réellement connus (catalogue, inventaire) : base du calcul quand « (tous) » serait trop large.
    $script:NmPairs=@($pairs.Keys|Sort-Object)
    $script:NmPageOffset=0;$script:NmPageFilterKey=''
}

function Populate-NmFilters {
    $script:SuspendNm=$true
    if ($NmCmbType.Items.Count   -eq 0) { 'Tous','Portable','Fixe','Virtuel' | ForEach-Object { [void]$NmCmbType.Items.Add($_) }; $NmCmbType.SelectedIndex=0 }
    if ($NmCmbStatut.Items.Count -eq 0) { 'Disponibles','Utilisés','Réservés','Tous' | ForEach-Object { [void]$NmCmbStatut.Items.Add($_) }; $NmCmbStatut.SelectedIndex=0 }
    $selS="$($NmCmbSite.SelectedItem)"; $selE="$($NmCmbEquipe.SelectedItem)"
    $NmCmbSite.Items.Clear();   [void]$NmCmbSite.Items.Add('(tous)');    foreach ($s in $script:NmSites)   { [void]$NmCmbSite.Items.Add($s) }
    $NmCmbEquipe.Items.Clear(); [void]$NmCmbEquipe.Items.Add('(tous)'); foreach ($e in $script:NmEquipes) { [void]$NmCmbEquipe.Items.Add($e) }
    $NmCmbSite.SelectedItem   = if ($selS -and $NmCmbSite.Items.Contains($selS))   { $selS } else { '(tous)' }
    $NmCmbEquipe.SelectedItem = if ($selE -and $NmCmbEquipe.Items.Contains($selE)) { $selE } else { '(tous)' }
    $script:SuspendNm=$false
}
function Get-NmUsedMap {
    param([string]$base)
    $used=@{}
    if(Get-Command Get-PestoNameInventoryIndex -ErrorAction SilentlyContinue){$inventory=Get-PestoNameInventoryIndex $script:ComputersNoms;if($inventory.ByBase.ContainsKey($base)){foreach($n in $inventory.ByBase[$base]){$used[$n]=$true}}}
    else{foreach($c in @($script:ComputersNoms)){$p=ConvertTo-PestoNameParts ([string]$c.Name);if($p -and $p.Base -ieq $base){$used[$p.Number]=$true}}}
    foreach($row in @($script:table.Rows)){if($row.Renommer){$p=ConvertTo-PestoNameParts ([string]$row.Nouveau_Nom);if($p -and $p.Base -ieq $base){$used[$p.Number]=$true}}}
    foreach($n in @($script:NmOwnReservations)){$p=ConvertTo-PestoNameParts ([string]$n);if($p -and $p.Base -ieq $base){$used[$p.Number]=$true}}
    return $used
}

function Invoke-PestoBuildNamesView {
    # Pure projection: one cached AD index, bounded page and reservoir samples over the complete filtered range.
    param([Parameter(Mandatory=$true)]$Request)
    $ErrorActionPreference='Stop'
    $clock=[Diagnostics.Stopwatch]::StartNew();$lastProgress=-100L
    $layout=Get-PestoNamingLayout;$max=$layout.MaximumNumber;$widths=$layout.Convention.Widths
    $prefix=[string]$Request.Prefix
    if($prefix -notmatch ('^[0-9]{'+$widths.Prefix+'}$')){throw 'Préfixe de nommage invalide.'}
    if($Request.Status -notin @('Disponibles','Utilisés','Réservés','Tous')){throw 'Statut de nom invalide.'}
    if($Request.Strategy -and $Request.Strategy -notin @('FirstGap','AfterLast')){throw 'Stratégie de nom invalide.'}
    $randomEnabled=$true
    if($null -ne $Request.RandomEnabled){
        if($Request.RandomEnabled -isnot [bool]){throw 'Le choix aléatoire exige un booléen.'}
        $randomEnabled=$Request.RandomEnabled
    }
    $randomIndex=$Request.RandomIndex
    if($null -ne $randomIndex -and $randomIndex -isnot [scriptblock]){throw 'Source de test aléatoire invalide.'}
    $draw={param([int]$Count)
        if($randomIndex){
            $value=& $randomIndex $Count
            if($value -isnot [int] -or $value -lt 0 -or $value -ge $Count){throw 'Indice aléatoire hors limites.'}
            return $value
        }
        return [M4D.Admin.Common.Core.RandomSelection]::NextIndex($Count)
    }
    $rx=$layout.Pattern
    $index=$Request.CachedIndex;$read=0;$indexBuilt=$false
    if($null -eq $index){
        $index=@{};$indexBuilt=$true
        foreach($c in $Request.Computers){
            if($Request.Cancellation -and $Request.Cancellation.Cancelled){throw [OperationCanceledException]::new('Calcul remplacé.')}
            $n=([string]$c.Name).Trim().ToUpperInvariant()
            if($n -match $rx -and $Matches.Prefix -ceq $prefix -and [int]$Matches.Number -gt 0){
                $base=$n.Remove($layout.NumberOffset,$layout.NumberWidth);$num=[int]$Matches.Number
                if(-not $index.ContainsKey($base)){$index[$base]=@{}}
                $index[$base][$num]=$true
            }
            $read++
            if($Request.Progress -and $clock.ElapsedMilliseconds-$lastProgress -ge 100){
                $Request.Progress.State=[pscustomobject]@{Stage='Indexation de l''inventaire';Count=$read;Total=0;Unit='postes analysés'};$lastProgress=$clock.ElapsedMilliseconds
            }
        }
    }
    $reserved=@{};$own=@{};$queue=@{}
    foreach($n in @($Request.OwnReservations)){$own[[string]$n]=$true}
    foreach($n in @($Request.QueueReservations)){$queue[[string]$n]=$true}
    foreach($target in @($Request.ReservedNames)){
        $n=([string]$target).Trim().ToUpperInvariant()
        if($n -notmatch $rx -or $Matches.Prefix -cne $prefix -or [int]$Matches.Number -eq 0){continue}
        $base=$n.Remove($layout.NumberOffset,$layout.NumberWidth);if(-not $reserved.ContainsKey($base)){$reserved[$base]=@{}}
        $reserved[$base][[int]$Matches.Number]=$true
    }
    $size=if($null -ne $Request.PageSize){[int]$Request.PageSize}else{[Math]::Min(250,[int]$Request.MaxRows)}
    if($size -lt 1 -or $size -gt 500){throw 'Taille de page invalide (1 à 500).'}
    $offset=[long]$Request.Offset;if($offset -lt 0 -or $offset -gt 100000000){throw 'Décalage de page invalide.'}
    $buffer=[Math]::Max(0,[Math]::Min($max,[int]$Request.Buffer));$search=([string]$Request.Search).Trim().ToUpperInvariant()
    if($search.Length -gt 64){throw 'Recherche trop longue.'}
    $groups=[Collections.Generic.List[object]]::new();$groupByBase=@{};$totalWork=0L
    # « (tous) » trop large : seuls les couples site/service connus, transmis par l'interface, sont calculés.
    $pairFilter=$null
    if($Request.PSObject.Properties['Pairs'] -and @($Request.Pairs).Count){$pairFilter=[Collections.Generic.HashSet[string]]::new([string[]]@($Request.Pairs),[StringComparer]::Ordinal)}
    $canSuggest=($Request.Status -in @('Disponibles','Tous'))
    foreach($ty in @($Request.Types|Sort-Object -Unique)){
        if($ty -cnotin @('P','S','V')){throw 'Type de poste non pris en charge.'}
        foreach($site in @($Request.Sites|Sort-Object -Unique)){
            if($site -cnotmatch ('^[A-Z]{'+$widths.Site+'}$')){throw 'Code site invalide.'}
            foreach($team in @($Request.Teams|Sort-Object -Unique)){
                if($team -cnotmatch ('^[A-Z0-9]{'+$widths.Service+'}$')){throw 'Code service invalide.'}
                if($pairFilter -and -not $pairFilter.Contains($site+'|'+$team)){continue}
                $base=New-PestoNameSeries $ty $prefix $site $team;$ad=$index[$base];$res=$reserved[$base];$last=0
                foreach($map in @($ad,$res)){if($map){foreach($k in $map.Keys){if([int]$k -gt $last){$last=[int]$k}}}}
                $upper=if([bool]$Request.ShowAll){$max}else{[Math]::Min($max,$last+$buffer)}
                $candidateStart=if($Request.Strategy -eq 'AfterLast'){$last+1}else{1}
                $start=if($Request.Status -eq 'Disponibles'){$candidateStart}else{1}
                $g=[pscustomobject]@{Base=$base;Type=$ty;Site=$site;Team=$team;AD=$ad;Reserved=$res;Upper=$upper;Start=$start;CandidateStart=$candidateStart}
                $groups.Add($g);$groupByBase[$base]=$g
                $totalWork+=$max
                if($totalWork -gt 2000000){throw 'Périmètre trop large : choisissez un site ou un service avant de calculer.'}
            }
        }
    }
    $makeRow={param($Group,[int]$Number,[bool]$InAD=$false,[bool]$InPrep=$false)
        $name=New-PestoNameFromSeries $Group.Base $Number;$mine=($own.ContainsKey($name) -and -not $queue.ContainsKey($name))
        $state=if($InAD){'Occupé dans AD'}elseif($InPrep -and $mine){'Retenu pour vous'}elseif($InPrep -and $queue.ContainsKey($name)){'Préparé dans la file'}elseif($InPrep){'Réservé ou indisponible'}else{'Libre dans l''inventaire'}
        [pscustomobject]@{Nom=$name;Type=$(switch($Group.Type){'P'{'Portable'};'S'{'Fixe'};'V'{'Virtuel'}});Site=$Group.Site;Equipe=$Group.Team;Num=(Format-PestoNameNumber $Number);
            Statut=$state;RowKind=$(if(-not($InAD -or $InPrep)){'Hit'}else{''});InAD=$InAD;Reserved=$InPrep;OwnReservation=$mine;CheckedUtc='';SourceUtc=[string]$Request.InventoryUtc}
    }
    # Revalidate previous proposals directly; no full candidate list is ever materialized.
    $eligiblePrevious={param([string]$Name)
        $n=$Name.Trim().ToUpperInvariant()
        if(-not $canSuggest -or $n -notmatch $rx){return}
        $g=$groupByBase[$n.Remove($layout.NumberOffset,$layout.NumberWidth)];$number=[int]$Matches.Number
        if(-not $g -or $number -lt $g.CandidateStart -or $number -lt 1 -or $number -gt $max){return}
        if(($search -and -not $n.Contains($search)) -or ($g.AD -and $g.AD.ContainsKey($number)) -or ($g.Reserved -and $g.Reserved.ContainsKey($number))){return}
        & $makeRow $g $number
    }
    $kept=[Collections.Generic.List[object]]::new();$keptNames=@{};$byType=@{P=$null;S=$null;V=$null};$keptTypes=@{}
    if(@($Request.PreviousSuggestions).Count -gt 5){throw 'Au plus cinq propositions précédentes.'}
    foreach($name in @($Request.PreviousSuggestions)){
        $row=& $eligiblePrevious ([string]$name)
        if($row -and -not $keptNames.ContainsKey($row.Nom)){$kept.Add($row);$keptNames[$row.Nom]=$true}
    }
    if($null -ne $Request.PreviousByType){
        if($Request.PreviousByType -isnot [Collections.IDictionary]){throw 'Propositions précédentes par type invalides.'}
        foreach($type in @('P','S','V')){
            $row=& $eligiblePrevious ([string]$Request.PreviousByType[$type])
            if($row -and ($row.Nom.Substring($layout.Offsets.Type,1) -ceq $type)){$byType[$type]=$row;$keptTypes[$type]=$true}
        }
    }
    $rows=[Collections.Generic.List[object]]::new();$sample=[Collections.Generic.List[object]]::new();$slots=5-$kept.Count
    $matched=0L;$available=0L;$occupied=0L;$prepared=0L;$examined=0L;$candidateCount=0;$sampleSeen=0
    $candidateCounts=@{P=0;S=0;V=0}
    foreach($g in $groups){
        for($i=1;$i -le $max;$i++){
            if($Request.Cancellation -and $Request.Cancellation.Cancelled){throw [OperationCanceledException]::new('Calcul remplacé.')}
            $examined++
            if($Request.Progress -and $clock.ElapsedMilliseconds-$lastProgress -ge 100){
                $Request.Progress.State=[pscustomobject]@{Stage='Calcul des noms';Count=$examined;Total=$totalWork;Unit='numéros examinés'};$lastProgress=$clock.ElapsedMilliseconds
            }
            $inAD=[bool]($g.AD -and $g.AD.ContainsKey($i));$inPrep=[bool]($g.Reserved -and $g.Reserved.ContainsKey($i));$taken=$inAD -or $inPrep
            $name=New-PestoNameFromSeries $g.Base $i
            if($search -and -not $name.Contains($search)){continue}
            $row=$null
            if($canSuggest -and -not $taken -and $i -ge $g.CandidateStart){
                $candidateCount++;$candidateCounts[$g.Type]++
                if(-not $keptNames.ContainsKey($name) -and $slots -gt 0){
                    $sampleSeen++;$slot=-1
                    if($sample.Count -lt $slots){$slot=$sample.Count}
                    elseif($randomEnabled){$slot=& $draw $sampleSeen}
                    if($slot -ge 0 -and $slot -lt $slots){
                        $row=& $makeRow $g $i
                        if($slot -eq $sample.Count){$sample.Add($row)}else{$sample[$slot]=$row}
                    }
                }
                if(-not $keptTypes.ContainsKey($g.Type)){
                    $pick=($candidateCounts[$g.Type] -eq 1)
                    if(-not $pick -and $randomEnabled){$pick=((& $draw $candidateCounts[$g.Type]) -eq 0)}
                    if($pick){if(-not $row){$row=& $makeRow $g $i};$byType[$g.Type]=$row}
                }
            }
            # Display bounds never limit the candidate reservoirs above.
            if($i -lt $g.Start -or $i -gt $g.Upper){continue}
            if($Request.Status -eq 'Disponibles' -and $taken){continue}
            if($Request.Status -eq 'Utilisés' -and -not $inAD){continue}
            if($Request.Status -eq 'Réservés' -and (-not $inPrep -or $inAD)){continue}
            if($inAD){$occupied++}elseif($inPrep){$prepared++}else{$available++}
            if($matched -ge $offset -and $rows.Count -lt $size){if(-not $row){$row=& $makeRow $g $i $inAD $inPrep};$rows.Add($row)}
            $matched++
        }
    }
    # Reservoir membership and order are uniform; stable previous choices keep their order.
    if($randomEnabled){for($i=$sample.Count-1;$i -gt 0;$i--){$j=& $draw ($i+1);$tmp=$sample[$i];$sample[$i]=$sample[$j];$sample[$j]=$tmp}}
    foreach($row in $sample){$kept.Add($row)}
    if($Request.Cancellation -and $Request.Cancellation.Cancelled){throw [OperationCanceledException]::new('Calcul remplacé.')}
    if($Request.Progress){$Request.Progress.State=[pscustomobject]@{Stage='Affichage de la page';Count=$examined;Total=$totalWork;Unit='numéros examinés'}}
    return [pscustomobject]@{Generation=[int]$Request.Generation;Rows=$rows.ToArray();Available=$available;Occupied=$occupied;Prepared=$prepared;
        Total=$matched;Offset=$offset;PageSize=$size;HasNext=($offset+$rows.Count -lt $matched);Limited=$false;Examined=$examined;
        ADIndex=$index;ReadCount=$read;IndexBuilt=$indexBuilt;Suggestions=$kept.ToArray();ByType=$byType;CandidateCount=$candidateCount;
        CandidateCountsByType=$candidateCounts;ElapsedMs=$clock.ElapsedMilliseconds}
}

function Stop-PestoNamesLoadTimer {
    if($script:NmLoadTimer){$script:NmLoadTimer.Stop()}
    if($script:NmLoadClock){$script:NmLoadClock.Stop()}
}

function Update-PestoNamesLoadProgress {
    param($Sender,$EventArgs)
    if(-not $script:NmLoading -or -not $NmLoadingTitle){return}
    $state=if($script:NmLoadMonitor){$script:NmLoadMonitor.State}else{$null}
    if($state){
        $NmLoadingTitle.Text=[string]$state.Stage
        $count=[Math]::Max(0,[long]$state.Count)
        $NmLoadingDetail.Text=if($count -gt 0){'{0:N0} {1}.' -f $count,$state.Unit}else{'Lecture en cours. La liste sera affichée après la fin du traitement.'}
        $total=[long]$state.Total
        $NmLoadingBar.IsIndeterminate=($total -le 0)
        if($total -gt 0){$NmLoadingBar.Value=[Math]::Min(100,100.0*$count/$total)}
    }
    $seconds=if($script:NmLoadClock){[int]$script:NmLoadClock.Elapsed.TotalSeconds}else{0}
    $NmLoadingElapsed.Text="Temps écoulé : $seconds s"
}

function Set-PestoNamesViewState {
    param([ValidateSet('Loading','Ready','Empty','Error','NotLoaded')][string]$State,
          [string]$Title='',[string]$Detail='',[AllowNull()]$Monitor=$null)
    $continueClock=($State -eq 'Loading' -and $script:NmLoading -and $script:NmLoadClock)
    Stop-PestoNamesLoadTimer
    $script:NmLoading=($State -eq 'Loading')
    $script:NmViewReady=($State -eq 'Ready')
    if($script:NamesExtras){foreach($name in @('NmOtherNames','NmVerifyCandidate','NmUseCandidate')){if($script:NamesExtras[$name]){$script:NamesExtras[$name].IsEnabled=($State -eq 'Ready')}}}
    $script:NmLoadMonitor=$Monitor
    if(-not $NmLoadingPanel){return}
    $NmLoadingPanel.Visibility=if($State -eq 'Ready'){'Collapsed'}else{'Visible'}
    $NmGrid.Visibility=if($State -eq 'Ready' -or ($State -eq 'Loading' -and $NmGrid.Items.Count -gt 0)){'Visible'}else{'Hidden'}
    $NmGrid.Opacity=if($State -eq 'Loading'){0.25}else{1.0}
    $NmGrid.IsEnabled=($State -eq 'Ready')
    $NmLoadingTitle.Text=$Title; $NmLoadingDetail.Text=$Detail
    $NmLoadingBar.IsIndeterminate=($State -eq 'Loading')
    $NmLoadingBar.Visibility=if($State -eq 'Loading'){'Visible'}else{'Collapsed'}
    $NmLoadingElapsed.Text=''
    $NmBtnRetryNames.Visibility=if($State -in @('Error','NotLoaded')){'Visible'}else{'Collapsed'}
    $NmBtnRetryNames.IsEnabled=($NmBtnRefresh -and $NmBtnRefresh.IsEnabled)
    foreach($button in @($NmBtnCopy,$NmBtnExport)){$button.IsEnabled=($State -eq 'Ready')}
    if($State -ne 'Ready'){
        if($State -ne 'Loading'){$NmGrid.ItemsSource=@()}; $NmLblCount.Text=if($State -eq 'Loading'){'Actualisation : ancien résultat non utilisable'}else{''}
        foreach($button in @($NmBtnNextP,$NmBtnNextS,$NmBtnNextV)){$button.Tag=$null;$button.IsEnabled=$false}
        $NmBtnNextP.Content='Portable : —';$NmBtnNextS.Content='Fixe : —';$NmBtnNextV.Content='Virtuel : —'
    }
    if($State -eq 'Loading'){
        $NmViewNote.Text='Actualisation en cours. Ancien résultat grisé, non sélectionnable et non exportable.'
        if($continueClock){$script:NmLoadClock.Start()}else{$script:NmLoadClock=[Diagnostics.Stopwatch]::StartNew()}
        if(-not $script:NmLoadTimer){
            $script:NmLoadTimer=New-Object System.Windows.Threading.DispatcherTimer
            $script:NmLoadTimer.Interval=[TimeSpan]::FromMilliseconds(200)
            $script:NmLoadTimer.Add_Tick([EventHandler]${function:Update-PestoNamesLoadProgress})
        }
        Update-PestoNamesLoadProgress
        $script:NmLoadTimer.Start()
    }elseif($State -in @('Error','NotLoaded')){
        $NmViewNote.Text='Aucune disponibilité publiée. Actualiser relance uniquement une lecture AD.'
    }
}

function Fail-PestoNamesProjection {
    param($Failure,$Context)
    if($Context -and [int]$Context.Generation -ne [int]$script:NmViewGeneration){return}
    # Le message du worker arrive enveloppé par EndInvoke : afficher la cause, pas l'enveloppe.
    $inner=if($Failure -and $Failure.Exception){$Failure.Exception}else{$null}
    while($inner -and $inner.InnerException -and ($inner -is [Management.Automation.MethodInvocationException] -or [string]$inner.Message -like '*EndInvoke*')){$inner=$inner.InnerException}
    $message=if($inner){[string]$inner.Message}else{'Résultat de calcul absent ou incomplet.'}
    if($message -like 'Périmètre trop large*'){
        Set-PestoNamesViewState -State Empty -Title 'Choisissez un site ou un service' -Detail ($message+' Aucun calcul lancé.')
        Add-LogLine ('Noms disponibles : '+$message) 'warn';return
    }
    Set-PestoNamesViewState -State Error -Title 'Impossible de préparer la liste' -Detail ('Réessayez ou précisez les filtres. '+$message)
    Add-LogLine ('Noms disponibles : '+$message) 'err'
}

function Complete-PestoNamesProjection {
    param($Result,$Context)
    if(-not $Context -or [int]$Context.Generation -ne [int]$script:NmViewGeneration){return}
    if(-not [object]::ReferenceEquals($Context.Source,$script:ComputersNoms)){
        Set-PestoNamesViewState -State NotLoaded -Title 'Inventaire modifié' -Detail 'Actualisez la liste pour utiliser les données à jour.'
        return
    }
    try{
        if(-not $Result -or $Result -is [array] -or $null -eq $Result.Rows -or
           [int]$Result.Generation -ne [int]$Context.Generation){throw 'Résultat de calcul absent ou incohérent.'}
        $script:NmUsedIndex=$Result.ADIndex; $script:NmUsedSrc=$Context.Source
        $script:NmPageResult=$Result;Update-PestoNamesPageControls $Result
        $rows=@($Result.Rows); $count=$rows.Count
        if($count -gt 0 -or [int]$Result.CandidateCount -gt 0){
            Set-PestoNamesViewState -State Ready
            # La page de noms est recalculée en entier à chaque filtre : seules les lignes dont l'état a
            # changé sont remplacées, la sélection suit le nom (seule identité stable d'un candidat) et le
            # tri porté par la vue est restitué. Un tri demandé par une vue enregistrée garde la priorité.
            [void](Update-PestoGridRows -Grid $NmGrid -Rows $rows -IdProperty 'Nom')
            if($script:PestoNamesViewSort){$NmGrid.Items.SortDescriptions.Clear();foreach($sort in $script:PestoNamesViewSort){$NmGrid.Items.SortDescriptions.Add([ComponentModel.SortDescription]::new($sort.Property,([ComponentModel.ListSortDirection][Enum]::Parse([ComponentModel.ListSortDirection],$sort.Direction))))}}
            $NmLblCount.Text=('{0:N0} affichés / {1:N0} correspondants · {2:N0} libres · {3:N0} AD · {4:N0} préparés' -f $count,$Result.Total,$Result.Available,$Result.Occupied,$Result.Prepared)
        }else{
            Set-PestoNamesViewState -State Empty -Title 'Aucun nom pour ces filtres' -Detail 'La lecture est terminée. Modifiez le site, le service, le statut ou la recherche.'
            $NmLblCount.Text='0 nom affiché'
        }
        $date=if($script:InventoryUtc){try{([datetime]::Parse([string]$script:InventoryUtc)).ToLocalTime().ToString('dd/MM/yyyy HH:mm:ss')}catch{'date inconnue'}}else{'données de démonstration'}
        $note="Inventaire : $date. Disponibilité dans le périmètre configuré, sans réservation AD."
        $note+=' '+[string]$Result.CandidateCount+' candidats libres dans la convention active selon les filtres. La marge et la page limitent uniquement le tableau. Vérifier un candidat avant utilisation.'
        $NmBtnExport.IsEnabled=($count -gt 0)
        Add-PestoPerformanceSample -Name 'NamesProjection' -Milliseconds ([long]$Result.ElapsedMs) -Count ([long]$Result.Examined)
        $NmViewNote.Text=$note
        Set-NmNextButtons
    }catch{Fail-PestoNamesProjection -Failure $_ -Context $Context}
}

function Update-NameGrid {
    if($script:SuspendNm){return}
    if($MainTabs -and $MainTabs.SelectedIndex -ne 1){$script:NmViewDirty=$true;return}
    $script:NmViewDirty=$false
    # Une collecte incomplète ne doit pas produire de noms prétendument libres.
    if(Test-PestoAsyncOperationRunning 'DirectoryRefresh'){return}
    if($script:NmNeedsDirectoryRetry){return}
    $script:NmViewGeneration=[int]$script:NmViewGeneration+1
    if($script:NmCalculationCancel){$script:NmCalculationCancel.Cancelled=$true}
    Stop-PestoAsyncOperation 'NamesProjection'
    if(-not $script:InventoryLoaded -and -not $script:GUI){
        Set-PestoNamesViewState -State NotLoaded -Title 'Inventaire non chargé' -Detail 'Cliquez sur Actualiser pour lire les postes avant de proposer des noms.'
        return
    }
    $fSite=[string]$NmCmbSite.SelectedItem; $fEq=[string]$NmCmbEquipe.SelectedItem
    $types=switch([string]$NmCmbType.SelectedItem){'Portable'{@('P')}'Fixe'{@('S')}'Virtuel'{@('V')}default{@('P','S','V')}}
    $reserved=New-Object 'System.Collections.Generic.List[string]'
    if($script:table){foreach($row in $script:table.Rows){if([bool]$row.Renommer){$reserved.Add([string]$row.Nouveau_Nom)}}}
    $queuedNames=$reserved.ToArray()
    foreach($n in @($script:PestoTakenNames)){if($n){$reserved.Add([string]$n)}}
    if($script:SharedNameOthers){foreach($n in @($script:SharedNameOthers.Keys)){if(Test-PestoNameReservedByOther ([string]$n)){$reserved.Add([string]$n)}}}
    $mine=@(Read-PestoNameReservations);$script:NmOwnReservations=$mine;foreach($n in $mine){$reserved.Add($n)}
    $filterKey=([string]$NmCmbType.SelectedItem+'|'+$fSite+'|'+$fEq+'|'+[string]$NmCmbStatut.SelectedItem+'|'+[string]$NmTxtSearch.Text+'|'+$NmChkAll.IsChecked+'|'+$script:NmStrategy)
    $keepProposals=($script:NmPageFilterKey -ceq $filterKey -and -not $script:NmSuggestionReset)
    # Sites et services retenus. Avec « (tous) », le produit complet peut dépasser la borne du calcul (2 000 000
    # numéros) : on se limite alors aux couples site/service connus, sinon on demande de choisir un filtre.
    $types=@($types|Where-Object{(Get-PestoActiveNamingConvention).Types.Contains([string]$_)})
    $siteList=if($fSite -and $fSite -ne '(tous)'){@($fSite)}else{@($script:NmSites)}
    $teamList=if($fEq -and $fEq -ne '(tous)'){@($fEq)}else{@($script:NmEquipes)}
    $pairs=@()
    if(([long]@($types).Count*@($siteList).Count*@($teamList).Count*(Get-PestoNameMaximumNumber)) -gt 2000000){
        $pairs=@(@($script:NmPairs)|Where-Object{$part=([string]$_ -split '\|',2);$part.Count -eq 2 -and $part[0] -cin $siteList -and $part[1] -cin $teamList})
        if(-not $pairs.Count -or ([long]@($types).Count*$pairs.Count*(Get-PestoNameMaximumNumber)) -gt 2000000){
            $script:NmPageResult=$null
            Set-PestoNamesViewState -State Empty -Title 'Choisissez un site ou un service' -Detail ('Tous les sites ('+@($siteList).Count+') et tous les services ('+@($teamList).Count+') dépassent la limite de calcul. Sélectionnez un site ou un service ; aucun calcul lancé.')
            return
        }
    }
    $previousSuggestions=@();$previousByType=@{}
    if($keepProposals -and $script:NmPageResult){
        $previousSuggestions=@($script:NmPageResult.Suggestions|ForEach-Object{[string]$_.Nom})
        if($script:NmPageResult.ByType){foreach($type in @('P','S','V')){if($script:NmPageResult.ByType[$type]){$previousByType[$type]=[string]$script:NmPageResult.ByType[$type].Nom}}}
    }
    $script:NmSuggestionReset=$false
    if($script:NmPageFilterKey -cne $filterKey){$script:NmPageOffset=0;$script:NmPageFilterKey=$filterKey}
    $script:NmCalculationCancel=[hashtable]::Synchronized(@{Cancelled=$false})
    $cachedIndex=if([object]::ReferenceEquals($script:NmUsedSrc,$script:ComputersNoms)){$script:NmUsedIndex}else{$null}
    $monitor=[hashtable]::Synchronized(@{State=[pscustomobject]@{Stage='Préparation des noms disponibles';Count=0;Unit=''}})
    $request=[pscustomobject]@{
        Generation=$script:NmViewGeneration;Computers=$script:ComputersNoms;Prefix=[string]$script:PREFIXE
        ReservedNames=$reserved.ToArray();OwnReservations=$mine;QueueReservations=$queuedNames;Progress=$monitor;Types=@($types)
        Sites=$siteList;Teams=$teamList;Pairs=$pairs
        Status=[string]$NmCmbStatut.SelectedItem;Search=[string]$NmTxtSearch.Text
        ShowAll=[bool]$NmChkAll.IsChecked;Buffer=[int]$script:NmBuffer;MaxRows=250
        PageSize=250;Offset=[long]$script:NmPageOffset;CachedIndex=$cachedIndex;Cancellation=$script:NmCalculationCancel
        Strategy=[string]$script:NmStrategy;InventoryUtc=[string]$script:InventoryUtc
        RandomEnabled=[bool](Get-PestoSharedNameSettings).Random;PreviousSuggestions=$previousSuggestions;PreviousByType=$previousByType
    }
    $context=[pscustomobject]@{Generation=$script:NmViewGeneration;Source=$script:ComputersNoms}
    Set-PestoNamesViewState -State Loading -Monitor $monitor
    $ok={param($result,$ctx) Complete-PestoNamesProjection -Result $result -Context $ctx}
    $err={param($failure,$ctx) Fail-PestoNamesProjection -Failure $failure -Context $ctx}
    try{
        $worker=[scriptblock]::Create('param($Request)'+[Environment]::NewLine+(Get-PestoNamingContextSource)+[Environment]::NewLine+'function Invoke-PestoBuildNamesView {'+(Get-Command Invoke-PestoBuildNamesView -CommandType Function -ErrorAction Stop).Definition+'}'+[Environment]::NewLine+'Invoke-PestoBuildNamesView $Request')
        $started=Start-PestoAsyncOperation -Name 'NamesProjection' -ScriptBlock $worker -ArgumentList @($request) -OnSuccess $ok -OnError $err -CallbackContext $context -TimeoutSec 120 -Replace
        if(-not $started -and $script:NmLoading){Fail-PestoNamesProjection -Failure $null -Context $context}
    }catch{Fail-PestoNamesProjection -Failure $_ -Context $context}
}

function Set-NmNextButtons {
    if(-not $script:NmViewReady){return}
    foreach($spec in @(@('P',$NmBtnNextP,'Portable'),@('S',$NmBtnNextS,'Fixe'),@('V',$NmBtnNextV,'Virtuel'))){
        $type=$spec[0];$button=$spec[1];$label=$spec[2]
        $proposal=if($script:NmPageResult.ByType){$script:NmPageResult.ByType[$type]}else{$null}
        $button.Tag=if($proposal){[string]$proposal.Nom}else{$null}
        $button.IsEnabled=($null -ne $proposal)
        $button.Content=if($proposal){$label+' : '+$proposal.Nom}else{$label+' : —'}
    }
}

function Copy-NmName {
    param([string]$Name)
    if (-not $Name -or -not $script:NmViewReady) { return }
    try { [System.Windows.Clipboard]::SetText($Name); Add-LogLine "Nom copié : $Name" 'info' }
    catch { Show-MsgError "Copie impossible :`n$($_.Exception.Message)" }
}

function Export-NameView {
    if(-not $script:NmViewReady){return}
    $rows=$NmGrid.ItemsSource
    if (-not $rows -or @($rows).Count -eq 0) { Show-MsgInfo 'Aucun nom à exporter.'; return }
    $dlg=New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Filter='CSV (*.csv)|*.csv'; $dlg.FileName="Noms_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    if (-not $dlg.ShowDialog()) { return }
    $rows | Select-Object Nom,Type,Site,@{Name='Service';Expression={$_.Equipe}},Num,Statut | Export-Csv $dlg.FileName -Delimiter ';' -NoTypeInformation -Encoding UTF8
    Add-LogLine "Export noms : $($dlg.FileName)" 'info'
}
# Refresh-Names : composant séparé.

###############################################################################
#  SECTION 12d — ÉDITEUR DE CONFIGURATION (cfg.json) + NAVIGATEUR D'OU AD
###############################################################################

function ToTF { param($Chk) if ($Chk.IsChecked) { 'true' } else { 'false' } }
function New-KvTable { param([string[]]$Cols) $t=New-Object System.Data.DataTable; foreach($c in $Cols){[void]$t.Columns.Add($c,[string])}; ,$t }

function ConvertTo-PestoOrderedMap {
    param($InputObject)
    $map = [ordered]@{}
    if ($null -eq $InputObject) { return ,$map }
    if ($InputObject -is [System.Collections.IDictionary]) {
        foreach ($k in $InputObject.Keys) { $map["$k"] = $InputObject[$k] }
    } else {
        foreach ($p in $InputObject.PSObject.Properties) { $map[$p.Name] = $p.Value }
    }
    return ,$map
}

function Set-PestoMapValue {
    param([System.Collections.IDictionary]$Map,[string]$Name,$Value)
    foreach ($k in @($Map.Keys)) {
        if ("$k" -ieq $Name) { $Map[$k] = $Value; return }
    }
    $Map[$Name] = $Value
}
# Test-CfgValid : composant séparé.

# Load-SettingsUI : composant séparé.
# Build-CfgFromUI : composant séparé.
# Save-Cfg : composant séparé.
# Apply-CfgHot : composant séparé.
# Reload-CfgFromDisk : composant séparé.


function Add-CfgRow    { param($Table,$Grid) try { [void]$Grid.CommitEdit() } catch {}; [void]$Table.Rows.Add($Table.NewRow()); try { $Grid.Items.Refresh() } catch {} }
function Remove-CfgRow {
    param($Grid)
    $rv=$Grid.SelectedItem
    if ($rv -and $rv.Row -and $rv.Row.Table) {
        $rv.Row.Table.Rows.Remove($rv.Row)
        try { $Grid.Items.Refresh() } catch {}
    }
}

function Browse-OUForGrid {
    param($Grid)
    $rv = $Grid.SelectedItem
    if (-not $rv -or -not $rv.Row) { Show-MsgInfo 'Sélectionnez d''abord une ligne dans la grille.'; return }
    $row = $rv.Row                              # DataRow réel, capturé AVANT la modale
    $dn  = @(Show-OUBrowser)[-1]                # [-1] : ignore toute sortie parasite du pipeline
    if ([string]::IsNullOrWhiteSpace("$dn")) { return }
    # Terminer toute transaction d'édition de la grille (cellule PUIS ligne) avant d'écrire :
    # sinon la DataRowView en édition masque puis écrase l'écriture directe dans la DataRow.
    try { [void]$Grid.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Cell, $true) } catch {}
    try { [void]$Grid.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Row,  $true) } catch {}
    # Écrire via une transaction DataRow propre -> la DataView émet ListChanged -> la cellule se rafraîchit.
    try { $row.BeginEdit() } catch {}
    $row['OU'] = "$dn"
    try { $row.EndEdit() } catch {}
    try { $Grid.Items.Refresh() } catch {}
}

# ── Navigateur d'OU (fenêtre modale, arbre AD paresseux) ─────────────────────
function Get-DomainDN { 'DC=' + (($script:DOMAINE -split '\.') -join ',DC=') }


$script:PestoOUChildrenWorker = {
    param($Request)
    Set-StrictMode -Off;$ErrorActionPreference='Stop'
    $adLoader=[string]$Request.ADLoaderSource
    if(-not $adLoader){throw 'Résolveur AD approuvé absent du worker.'}
    . ([scriptblock]::Create($adLoader))
    Import-PestoADModule -ADModulePath ([string]$Request.ADModulePath)
    $adp=@{Server=[string]$Request.DC};if($null -ne $Request.Credential){$adp.Credential=$Request.Credential}
    @(Get-ADOrganizationalUnit -SearchBase ([string]$Request.DN) -SearchScope OneLevel -Filter * -ErrorAction Stop @adp |
      Sort-Object Name | ForEach-Object{[pscustomobject]@{Name=[string]$_.Name;DN=[string]$_.DistinguishedName}})
}

function Load-OUChildren {
    param($item)
    $item.Items.Clear();$dn="$($item.Tag)"
    if($script:GUI){
      $children=if($dn -eq (Get-DomainDN)){@('Postes','Assurance Maladie','SITES')|ForEach-Object{[pscustomobject]@{Name=$_;DN="OU=$_,$dn"}}}else{@()}
      if(@($children).Count -eq 0){$leaf=New-Object Windows.Controls.TreeViewItem;$leaf.Header='(aucune sous-OU)';$leaf.IsEnabled=$false;[void]$item.Items.Add($leaf);return}
      foreach($c in $children){$ci=New-Object Windows.Controls.TreeViewItem;$ci.Header=$c.Name;$ci.Tag=$c.DN;[void]$ci.Items.Add('…');[void]$item.Items.Add($ci)};return
    }
    $wait=New-Object Windows.Controls.TreeViewItem;$wait.Header='Chargement…';$wait.IsEnabled=$false;[void]$item.Items.Add($wait)
    $req=[pscustomobject]@{DN=$dn;DC=$script:DC;Credential=$script:cred;ADLoaderSource=(Get-PestoADLoaderSource);ADModulePath=(Join-Path $BasePath 'ActiveDirectory.psd1')}
    $opName='OU_'+[Guid]::NewGuid().ToString('N')
    $context=[pscustomobject]@{Item=$item;DN=$dn}
    $ok={param($children,$ctx)
      $item=$ctx.Item
      $item.Items.Clear();$arr=@($children | Where-Object {$null -ne $_})
      if($arr.Count -eq 0){$leaf=New-Object Windows.Controls.TreeViewItem;$leaf.Header='(aucune sous-OU)';$leaf.IsEnabled=$false;[void]$item.Items.Add($leaf);return}
      foreach($c in $arr){$ci=New-Object Windows.Controls.TreeViewItem;$ci.Header=$c.Name;$ci.Tag=$c.DN;[void]$ci.Items.Add('…');[void]$item.Items.Add($ci)}
    }
    $err={param($e,$ctx)
      $item=$ctx.Item;$dn=$ctx.DN
      $item.Items.Clear();$leaf=New-Object Windows.Controls.TreeViewItem;$leaf.Header='(lecture impossible — voir Journal)';$leaf.IsEnabled=$false;[void]$item.Items.Add($leaf)
      Write-Log "Lecture des sous-OU impossible pour '$dn'." 'ERROR' $e 'AD'
    }
    [void](Start-PestoAsyncOperation -Name $opName -ScriptBlock $script:PestoOUChildrenWorker -ArgumentList @($req) -OnSuccess $ok -OnError $err -CallbackContext $context -TimeoutSec 90)
}

function Show-OUBrowser {
    <# Fenêtre modale : arbre d'OU AD (chargement paresseux). Renvoie le DN choisi ou $null. #>
    param([string]$Title='Choisir une OU (Active Directory)')
    $script:OUBrowserResult = $null
    $w = New-Object System.Windows.Window
    Set-WindowIcon $w
    $w.Title=$Title; $w.Width=560; $w.Height=600; $w.WindowStartupLocation='CenterOwner'
    $w.ShowInTaskbar=$false   # dialogue enfant : pas de bouton séparé dans la barre des tâches
    try { $w.Owner=$Win } catch {}
    $w.Background=$Win.Resources['BgWindow']; $w.FontFamily='Segoe UI'; $w.FontSize=13
    $w.Resources=$Win.Resources
    $grid=New-Object System.Windows.Controls.Grid; $grid.Margin='14'
    $r0=New-Object System.Windows.Controls.RowDefinition; $r0.Height='Auto'
    $r1=New-Object System.Windows.Controls.RowDefinition; $r1.Height='*'
    $r2=New-Object System.Windows.Controls.RowDefinition; $r2.Height='Auto'
    $grid.RowDefinitions.Add($r0); $grid.RowDefinitions.Add($r1); $grid.RowDefinitions.Add($r2)
    $info=New-Object System.Windows.Controls.TextBlock
    $info.Text=$(if ($script:GUI) { 'Mode démo : arbre fictif (pas de connexion AD).' } else { "Dépliez les nœuds, sélectionnez une OU, puis OK." })
    $info.Foreground=$Win.Resources['FgMuted']; $info.Margin='0,0,0,10'; $info.TextWrapping='Wrap'
    [System.Windows.Controls.Grid]::SetRow($info,0); [void]$grid.Children.Add($info)
    $tree=New-Object System.Windows.Controls.TreeView
    $tree.Background=$Win.Resources['BgInput']; $tree.Foreground=$Win.Resources['FgText']; $tree.BorderBrush=$Win.Resources['ClrBorder']
    [System.Windows.Controls.Grid]::SetRow($tree,1); [void]$grid.Children.Add($tree)
    $root=New-Object System.Windows.Controls.TreeViewItem; $root.Header=$script:DOMAINE; $root.Tag=(Get-DomainDN); [void]$root.Items.Add('…'); $root.IsExpanded=$true
    [void]$tree.Items.Add($root)
    Load-OUChildren $root
    $tree.AddHandler([System.Windows.Controls.TreeViewItem]::ExpandedEvent, [System.Windows.RoutedEventHandler]{
        param($s,$e)
        $it=$e.OriginalSource
        if ($it -is [System.Windows.Controls.TreeViewItem] -and $it.Items.Count -eq 1 -and "$($it.Items[0])" -eq '…') { Load-OUChildren $it }
    })
    $bp=New-Object System.Windows.Controls.StackPanel; $bp.Orientation='Horizontal'; $bp.HorizontalAlignment='Right'; $bp.Margin='0,12,0,0'
    [System.Windows.Controls.Grid]::SetRow($bp,2); [void]$grid.Children.Add($bp)
    $ok=New-Object System.Windows.Controls.Button; $ok.Content='OK'; $ok.Width=110; $ok.Height=38; $ok.Margin='0,0,8,0'
    $cl=New-Object System.Windows.Controls.Button; $cl.Content='Annuler'; $cl.Width=110; $cl.Height=38
    $tree.ToolTip='Dépliez un site pour lire ses sous-OU. Le survol montre le chemin complet. Sélectionner ici ne déplace aucun poste.'
    $ok.ToolTip='Reporter le chemin sélectionné dans le formulaire. Aucune écriture Active Directory.'
    $cl.ToolTip='Fermer le navigateur sans changer le chemin du formulaire.'
    foreach($element in @($tree,$ok,$cl)){
        [Windows.Controls.ToolTipService]::SetShowOnDisabled($element,$true)
        [Windows.Controls.ToolTipService]::SetInitialShowDelay($element,450)
        [Windows.Controls.ToolTipService]::SetShowDuration($element,30000)
        [Windows.Automation.AutomationProperties]::SetHelpText($element,[string]$element.ToolTip)
    }
    [void]$bp.Children.Add($ok); [void]$bp.Children.Add($cl)
    $ok.IsDefault = $true; $cl.IsCancel = $true   # Entrée = OK, Échap = Annuler
    $ok.Add_Click({
        $sel = $tree.SelectedItem
        if (-not ($sel -and $sel.Tag)) { Show-MsgInfo 'Sélectionnez une OU.' 'Sélection requise'; return }
        $script:OUBrowserResult = "$($sel.Tag)"; $w.DialogResult = $true
    })
    $cl.Add_Click({ $w.DialogResult=$false })
    # Double-clic sur un nœud valide = sélection directe.
    $tree.Add_MouseDoubleClick({ $sel=$tree.SelectedItem; if ($sel -and $sel.Tag) { $script:OUBrowserResult="$($sel.Tag)"; $w.DialogResult=$true } })
    $w.Content=$grid
    [void]$w.ShowDialog()
    return $script:OUBrowserResult
}

###############################################################################
###############################################################################
#  RC6 : PRESENTATION UNIQUEMENT. Aucun droit, aucune mutation depuis ces vues.
###############################################################################

function Get-PestoUxSnapshot {
    <# Projection pure du brouillon. La décision métier existante reste la source
       de vérité : cet aperçu ne coche rien et n'autorise jamais une exécution. #>
    param(
        [string]$Computer,[string]$NewName,[string]$CurrentOU,[string]$TargetOU,
        [bool]$Rename,[bool]$Move,[bool]$Reboot,[bool]$InDomain=$true,
        [bool]$CanAdd,[bool]$NameTaken,[bool]$Running,[bool]$Preflight,
        [bool]$SafetyLocked,[bool]$RestartRequired,[bool]$Reading,
        [int]$SelectedCount,[int]$QueueCount,[string]$Service,[string]$Site,
        [string]$Type,[bool]$Editing
    )
    $name="$Computer".Trim().ToUpperInvariant()
    $target="$NewName".Trim().ToUpperInvariant()
    $decision=Get-PestoRenameMoveDecision -Computer $name -NewName $target -CurrentOU $CurrentOU `
        -TargetOU $TargetOU -Rename $Rename -Move $Move -InDomain $InDomain
    $operation='Aucune action prête'
    if(-not $InDomain){$operation='Joindre ce PC au domaine'}
    elseif($Rename -and $decision.Valid){$operation=if($decision.Move){'Renommer puis déplacer'}else{'Renommer seulement'}}
    elseif(-not $Rename -and $Move){$operation='Déplacer seulement'}
    elseif($Rename -and -not $decision.Valid){$operation='Plan à compléter'}
    # Ne pas afficher l'OU choisie comme destination réelle en renommage seul.
    $futureOU=if(-not $InDomain -or ($decision.Valid -and $decision.Move)){$TargetOU}else{$CurrentOU}
    # Rien de choisi (pas de site) : « À définir », jamais le nom actuel présenté comme nouveau nom.
    $finalName=if(-not $Site){''}elseif($Rename -or -not $InDomain){$target}else{$name}
    $stage=1;$hint='Renseignez le poste à traiter.'
    if(Test-PestoComputerName $name){
        $stage=2
        if(-not $Site){$hint='Choisissez un organisme, puis un site.'}
        elseif($Service -notmatch (Get-PestoFacetPattern Service)){$hint='Saisissez un code service conforme a la convention.'}
        elseif($Type -notin @('Portable','Fixe','Virtuel')){$hint='Choisissez le type de poste.'}
        elseif($NameTaken){$hint='Ce nom est déjà pris. Choisissez un autre nom disponible.'}
        elseif($Rename -and -not $decision.Valid){$hint=$decision.Error}
        elseif($CanAdd){$stage=3;$hint=if($Editing){'Enregistrez la modification de la ligne, puis vérifiez la file.'}else{'Ajoutez ce brouillon à la file. Aucun poste ne sera modifié à cette étape.'}}
        elseif(-not $Rename -and -not $Move){$hint='Choisissez un autre nom, ou demandez explicitement un déplacement seul dans les options.'}
        else{$hint='Complétez les champs ou consultez le message sous le nom du poste.'}
    }
    if($SelectedCount -gt 0 -and -not $Editing){$stage=3;$next='Contrôlez les lignes cochées dans AD, puis prévisualisez la file avant de lancer son exécution.'}
    elseif($QueueCount -gt 0 -and -not $Editing){$next='La file contient des lignes. Cochez celles à traiter, puis contrôlez-les avant exécution.'}
    else{$next=$hint}
    if($Reading){$stage=1;$hint='Lecture du poste en cours. Le formulaire sera disponible après sa réponse.';$next=$hint}
    if($RestartRequired){$hint='La configuration a changé. Fermez puis relancez Pesto avant de préparer de nouvelles actions.';$next=$hint}
    if($SafetyLocked){$hint='Verrou de sécurité actif. Vérifiez le poste et l''objet AD avant de lever ce verrou dans la file.';$next=$hint}
    if($Preflight){$stage=3;$hint='Contrôle AD en cours. Aucune écriture ; patientez ou annulez le contrôle.';$next=$hint}
    if($Running){$stage=4;$hint='La file est en cours. Vous pouvez lire le journal ou demander un arrêt après l''action courante.';$next=$hint}
    [pscustomobject]@{
        CurrentName=$(if($name){$name}else{'Non renseigné'})
        FinalName=$(if($finalName){$finalName}else{'À définir'})
        FutureOU=[string]$futureOU;Operation=$operation;Stage=$stage;AddHint=$hint;NextStep=$next
        SourceSite=[string]$decision.SourceSite;TargetSite=[string]$decision.TargetSite
        DecisionValid=[bool]$decision.Valid;DecisionReason=$(if($decision.Valid){[string]$decision.Reason}else{[string]$decision.Error})
        Move=[bool]$decision.Move;CanCopy=[bool](Test-PestoGeneratedComputerName $target)
        RebootText=$(if($Reboot){'Redémarrage : demandé après réussite'}else{'Redémarrage : non demandé'})
    }
}

function Request-PestoUxRefresh {
    if(-not $script:PestoUxReady -or -not $script:PestoUxTimer){return}
    $script:PestoUxTimer.Stop();$script:PestoUxTimer.Start()
}
function Invoke-PestoUxRefreshTick {
    param($Sender,$EventArgs)
    $Sender.Stop()
    try{Update-PestoUx; $script:PestoUxRenderError=$false}
    catch{
        if(-not $script:PestoUxRenderError){Write-Log 'Aperçu non actualisé. Les validations du moteur restent actives.' 'ERROR' $_ 'interface';$script:PestoUxRenderError=$true}
        if($UxNextStep){$UxNextStep.Text='L''aperçu n''a pas pu être actualisé. Consultez Journal avant de continuer.'}
    }
}
function Invoke-PestoUxInputChanged {
    param($Sender,$EventArgs)
    Request-PestoUxRefresh
}
function Update-PestoUx {
    if(-not $script:PestoUxReady){return}
    $all=@($script:table.Rows);$selected=@($all|Where-Object{$_.Traiter}).Count
    $review=@($all|Where-Object{$_.Statut -in @('KO','PARTIEL','PROTECTION','INCERTAIN','TECHNIQUE') -or $_.Precontrole -eq 'BLOQUÉ'}).Count
    $readPending=($script:PestoUxLookupTimer -and $script:PestoUxLookupTimer.IsEnabled) -or (Test-PestoAsyncOperationRunning 'PCProbe')
    $view=Get-PestoUxSnapshot -Computer ([string]$TxtPCName.Text) -NewName ([string]$CbName.SelectedItem) `
        -CurrentOU ([string](Format-PestoOUForDisplay $script:OU_ACTUELLE)) -TargetOU ([string](Format-PestoOUForDisplay $script:OU_FINAL)) `
        -Rename ([bool]$ChkRename.IsChecked) -Move ([bool]$ChkMove.IsChecked) -Reboot ([bool]($script:SuiteMode -eq 'Batch' -and $ChkReboot.IsChecked)) `
        -InDomain ([bool]$script:INDOMAIN) -CanAdd ([bool]$BtnAdd.IsEnabled) -NameTaken ([bool]$script:NewNameExists) `
        -Running ([bool]$script:Running) -Preflight ([bool]$script:PreflightRunning) -SafetyLocked ([bool](Test-PestoGlobalSafetyBarrier)) `
        -RestartRequired ([bool]$script:CfgRestartRequired) -Reading ([bool]$readPending) `
        -SelectedCount $selected -QueueCount $all.Count -Service ([string]$CbService.Text) -Site ([string]$CbSite.SelectedItem) `
        -Type ([string]$CbType.SelectedItem) -Editing ($script:EDIT_ROW_INDEX -ge 0)
    $UxCurrentName.Text=$view.CurrentName;$UxNewName.Text=$view.FinalName
    $UxOperation.Text=$view.Operation;$UxOperation.ToolTip=$view.DecisionReason
    $UxActualTargetOU.Text=if($view.FutureOU){'Après : '+(Format-OUPath $view.FutureOU)}else{'Après : emplacement non déterminé'}
    $UxActualTargetOU.ToolTip=if($view.FutureOU){$view.FutureOU}else{'Aucun emplacement déterminé. Complétez le formulaire.'}
    $UxSiteTransition.Text=if($view.SourceSite -and $view.TargetSite){
        if($view.SourceSite -ieq $view.TargetSite){'Site conservé : '+(Format-OUPath $view.SourceSite)}
        else{'Site : '+(Format-OUPath $view.SourceSite)+' → '+(Format-OUPath $view.TargetSite)}
    }else{'Site cible : '+[string]$CbSite.SelectedItem}
    $UxRebootSummary.Text=$view.RebootText;$UxNextStep.Text=$view.NextStep;$UxAddHint.Text=$view.AddHint
    $segments=$Win.FindName('PestoNameSegments');if($segments){$segments.ItemsSource=@(Get-PestoNameSegments -Name ([string]$CbName.SelectedItem) -Previous ([string]$TxtPCName.Text))}
    $BtnCopyNewName.IsEnabled=$view.CanCopy
    $BtnReadComputer.IsEnabled=(-not $script:Running -and -not $script:PreflightRunning -and -not (Test-PestoGlobalSafetyBarrier) -and -not $script:CfgRestartRequired -and (Test-PestoComputerName ([string]$TxtPCName.Text)))
    $UxPageTitle.Text=if($script:INDOMAIN){'Renommer un poste'}else{'Joindre ce PC au domaine'}
    $UxPageSubtitle.Text=if($script:INDOMAIN){'Préparez le changement, vérifiez ses effets, puis lancez les actions choisies.'}else{'Seul ce poste local peut être joint. La destination dépend de votre configuration.'}
    $NavRenameLabel.Text=Get-PestoUxNom 'PagePoste'
    $UxMoveRule.Text=if($script:INDOMAIN){'ⓘ  Déplacement automatique uniquement si le site change.'}else{'ⓘ  Jonction locale vers l''OU autorisée par la configuration.'}
    $mode=if($script:GUI){'DÉMONSTRATION : aucun accès AD'}elseif($script:SIM){'SIMULATION : aucune mutation réelle'}else{'MODE RÉEL : écritures après confirmation'}
    $UxExecutionMode.Text=$mode
    $UxExecutionMode.Foreground=$Win.Resources[$(if($script:GUI -or $script:SIM){'WarnFg'}else{'FgText'})]
    $BtnRun.ToolTip=if($script:MutationUncertain){'Verrou de sécurité actif. Vérifiez l''état réel avant toute reprise.'}
        elseif($script:Running){'Une exécution est déjà en cours. Un deuxième lancement est interdit.'}
        elseif($script:PreflightRunning){'Attendez la fin du contrôle AD avant d''exécuter la file.'}
        elseif(Test-PestoAsyncOperationRunning 'DirectoryRefresh'){'Actualisation des listes AD en cours. Patientez avant de lancer la file.'}
        elseif($script:EDIT_ROW_INDEX -ge 0){'Terminez ou annulez la modification de la ligne en cours.'}
        elseif($script:CfgRestartRequired){'Relancez Pesto pour appliquer le nouveau contexte de configuration.'}
        elseif($selected -eq 0){'Cochez au moins une ligne dans la file pour pouvoir l''exécuter.'}
        else{"Afficher la confirmation puis exécuter $selected ligne(s) cochée(s), y compris les lignes masquées par un filtre."}
    $BtnAdd.ToolTip=$view.AddHint+' L''ajout prépare uniquement la file ; il ne modifie aucun poste.'
    foreach($pair in @(@($BtnAdd,$BtnAdd.ToolTip),@($BtnRun,$BtnRun.ToolTip),@($UxActualTargetOU,$UxActualTargetOU.ToolTip))){
        [Windows.Automation.AutomationProperties]::SetHelpText($pair[0],[string]$pair[1])
    }
    Update-PestoHomeDashboard
    for($i=1;$i -le 4;$i++){
        $b=$Win.FindName("Step$i");$t=$Win.FindName("Step${i}Text")
        $b.Background=$Win.Resources[$(if($i -eq $view.Stage){'AddBg'}else{'BgInputRO'})]
        $t.Foreground=$Win.Resources[$(if($i -eq $view.Stage){'RunFg'}else{'FgMuted'})]
    }
    # L'arrêt conserve une présence stable dans le pied, avec son motif au survol.
    Sync-PestoUxNavigation
    if($script:SuiteReady){Update-PestoSuiteUI}
}

function Update-PestoUxLayout {
    if(-not $script:PestoUxReady -or $Win.ActualWidth -le 0){return}
    Update-PestoUiZoomLayout
    $logical=Get-PestoUiLayoutSize
    $effectiveCollapsed=([bool]$script:NavigationCollapsed -or $logical.Width -lt 760)
    $available=$logical.Width-$(if($effectiveCollapsed){68}else{194})-$(if($script:HelpVisible -and $logical.Width -ge 1450){280}else{0})
    $compact=$available -lt 1050
    $SidebarWidth.Width=[Windows.GridLength]::new($(if($effectiveCollapsed){68}else{194}))
    $MainTabs.Margin=[Windows.Thickness]::new($(if($compact){14}else{22}),16,$(if($compact){14}else{22}),14)
    if($null -eq $script:PestoUxCompact -or [bool]$script:PestoUxCompact -ne $compact){
        if($compact){
            $BodyGrid.ColumnDefinitions[0].MinWidth=0;$BodyGrid.ColumnDefinitions[2].MinWidth=0
            $BodyGrid.ColumnDefinitions[0].Width=[Windows.GridLength]::new(1,[Windows.GridUnitType]::Star)
            $BodyGrid.ColumnDefinitions[1].Width=[Windows.GridLength]::new(0)
            $BodyGrid.ColumnDefinitions[2].Width=[Windows.GridLength]::new(0)
            [Windows.Controls.Grid]::SetColumn($PreviewPanel,0);[Windows.Controls.Grid]::SetRow($PreviewPanel,1)
            $PreviewPanel.Margin=[Windows.Thickness]::new(0,12,0,0);$FormSplitter.Visibility='Collapsed'
        }else{
            $BodyGrid.ColumnDefinitions[0].MinWidth=400;$BodyGrid.ColumnDefinitions[2].MinWidth=285
            $BodyGrid.ColumnDefinitions[0].Width=[Windows.GridLength]::new(2,[Windows.GridUnitType]::Star)
            $BodyGrid.ColumnDefinitions[1].Width=[Windows.GridLength]::new(12)
            $BodyGrid.ColumnDefinitions[2].Width=[Windows.GridLength]::new(1,[Windows.GridUnitType]::Star)
            [Windows.Controls.Grid]::SetColumn($PreviewPanel,2);[Windows.Controls.Grid]::SetRow($PreviewPanel,0)
            $PreviewPanel.Margin=[Windows.Thickness]::new(0);$FormSplitter.Visibility='Visible'
        }
        $script:PestoUxCompact=$compact
    }
    $Grid.Height=[Math]::Max(230,[Math]::Min(400,$logical.Height*0.30))
    $namesGrid=$Win.FindName('NmGrid');if($namesGrid){$namesGrid.Height=$Grid.Height}
    if($script:SuiteReady){Update-PestoSuiteLayout}
}
function Invoke-PestoUxSizeChanged {param($Sender,$EventArgs);Update-PestoUxLayout}

function Set-PestoUxPage {
    param([ValidateSet('Rename','Names','Settings','Log','Home','History','Help','Join')][string]$Page='Rename')
    $map=@{Rename=0;Names=1;Settings=2;Log=3;Home=4;History=5;Help=6;Join=7}
    if($Page -eq 'Rename' -and -not $script:INDOMAIN){$Page='Join'}
    $MainTabs.SelectedIndex=$map[$Page]
    if($Page -eq 'Join'){Update-PestoJoinUI;Request-PestoJoinSiteLookup}
    if($Page -eq 'Names'){
        if(-not $script:InventoryLoaded -and -not $script:GUI){[void](Refresh-Names)}
        elseif(-not (Test-PestoAsyncOperationRunning 'NamesProjection')){Update-NameGrid}
    }
    if($Page -eq 'Home'){Update-PestoHomeInterventions}
    if($Page -eq 'Log'){Render-Log}
    if($Page -eq 'History'){Update-PestoUxHistory}
    Sync-PestoUxNavigation
    Request-PestoUxRefresh
}
function Sync-PestoUxNavigation {
    $selected=@{0='NavRename';1='NavNames';2='NavSettings';3='NavLogs';4='NavHome';5='NavHistory';6='NavHelp';7='NavJoin'}[[int]$MainTabs.SelectedIndex]
    if($MainTabs.SelectedIndex -eq 0 -and $script:SuiteMode -eq 'Batch'){$selected='NavBatch'}
    foreach($n in @('NavBatch','NavRename','NavJoin','NavNames','NavSettings','NavLogs','NavHome','NavHistory','NavHelp')){
        $c=$Win.FindName($n);if($c){$c.Tag=if($n -eq $selected){'Selected'}else{''}}
    }
}
function Invoke-PestoUxNavigate {
    param($Sender,$EventArgs)
    switch([string]$Sender.Name){
        'NavHome'     {Set-PestoUxPage 'Home'}
        'NavRename'   {Set-PestoSuiteMode 'Single'}
        'NavJoin'     {Set-PestoUxPage 'Join'}
        'NavNames'    {Set-PestoUxPage 'Names'}
        'NavHistory'  {Set-PestoUxPage 'History'}
        'NavLogs'     {Set-PestoUxPage 'Log'}
        'NavSettings' {Set-PestoUxPage 'Settings'}
        'NavHelp'     {Set-PestoUxPage 'Help'}
        'BtnHelp'     {Set-PestoSuiteHelp (-not $script:HelpVisible)}
        'BtnInlineHelp' {Set-PestoSuiteHelp $true}
        'HomePrepare' {if($script:INDOMAIN){Set-PestoSuiteMode 'Single';[void]$TxtPCName.Focus()}else{Set-PestoUxPage 'Join'}}
        'HomeQueue'   {Set-PestoSuiteMode 'Batch';$QueueCard.BringIntoView();[void]$Grid.Focus()}
        'HomeNames'   {Set-PestoUxPage 'Names'}
        'HomeHistory' {Set-PestoUxPage 'History'}
    }
}
function Invoke-PestoUxPageChanged {
    param($Sender,$EventArgs)
    if([object]::ReferenceEquals($EventArgs.OriginalSource,$MainTabs)){Sync-PestoUxNavigation;Request-PestoUxRefresh;Request-PestoPageAutomationRefresh}
}

function Update-PestoUxHistory {
    <# Uniquement une lecture du fichier local ; pas de relance ni d'accès AD. #>
    try{
        $UxHistoryGrid.ItemsSource=$null
        $path=Join-Path (Get-PestoStateDirectory) 'history-v1.json'
        if(-not(Test-Path -LiteralPath $path)){$UxHistoryMessage.Text=Get-PestoHistoryEmptyText;return}
        if((Get-Item -LiteralPath $path).Length -gt 2MB){throw 'Historique trop volumineux (limite 2 Mio).'}
        $data=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json
        if($data.Schema -ne 1 -or $data.Domain -ine $script:DOMAINE){throw 'Historique incompatible avec ce domaine.'}
        $items=@(foreach($e in @($data.Entries|Sort-Object Utc -Descending|Select-Object -First 100)){
            $at=[DateTimeOffset]::MinValue;$stamp=[string]$e.Utc
            if([DateTimeOffset]::TryParse($stamp,[ref]$at)){$stamp=$at.LocalDateTime.ToString('dd/MM/yyyy HH:mm')}
            [pscustomobject]@{LocalDate=$stamp;Mode=[string]$e.Mode;Total=[int]$e.Total;Ok=[int]$e.Ok;Failed=[int]$e.Failed;
                NotStarted=[int]$e.NotStarted;Safety=$(if($e.Locked){'Actif'}else{'Non'});RunId=[string]$e.RunId}
        })
        $UxHistoryGrid.ItemsSource=$items
        # Mise en garde sur la simulation seulement si l'historique affiché contient des lots simulés.
        $simulated=@($items|Where-Object{[string]$_.Mode -match '^SIMUL'}).Count
        $UxHistoryMessage.Text="$($items.Count) lot(s)."+$(if($simulated){" Dont $simulated en simulation : leurs réussites ne sont pas des opérations réelles."}else{''})+' Le journal et les checkpoints restent prioritaires.'
    }catch{
        $UxHistoryMessage.Text='Historique non chargé : '+$_.Exception.Message
        Write-Log 'Lecture de l''historique depuis la page impossible.' 'WARN' $_ 'interface'
    }
}
function Invoke-PestoUxHistoryRefresh {param($Sender,$EventArgs);Update-PestoUxHistory}

function Set-PestoUxTechnicalColumns {
    param([bool]$Visible)
    foreach($col in $Grid.Columns){
        $key=if($col -is [Windows.Controls.DataGridBoundColumn]){[string]$col.Binding.Path.Path}else{[string]$col.SortMemberPath}
        if($key -notin @('Traiter','Nom_du_PC','Nouveau_Nom','Plan','Statut','Precontrole')){$col.Visibility=if($Visible){'Visible'}else{'Collapsed'}}
    }
}
function Invoke-PestoUxTechnicalChanged {
    param($Sender,$EventArgs)
    Set-PestoUxTechnicalColumns ([bool]$ChkTechnicalColumns.IsChecked)
}
function Invoke-PestoUxCopyName {
    param($Sender,$EventArgs)
    $name=[string]$CbName.SelectedItem
    if(-not(Test-PestoGeneratedComputerName $name)){return}
    try{[Windows.Clipboard]::SetText($name);$UxNextStep.Text="Nom copié : $name. Aucun poste modifié."}
    catch{Show-MsgWarning 'Le presse-papiers est indisponible. Réessayez.'}
}

function Request-PestoUxComputerLookup {
    if($script:Suspend -or $script:Running -or $script:DirectBusy -or $script:PreflightRunning){return}
    if($script:PestoUxLookupTimer){$script:PestoUxLookupTimer.Stop()}
    $script:PCProbeGeneration=[int]$script:PCProbeGeneration+1
    if(Test-PestoAsyncOperationRunning 'PCProbe'){Stop-PestoAsyncOperation 'PCProbe'}
    Reset-ConfigFields -KeepName
    $script:PING=$null;Update-FieldColor
    $BtnAdd.IsEnabled=$false
    if($LblPCInfo){$LblPCInfo.Text='Saisissez le poste, puis cliquez sur Lire ou appuyez sur Entrée.'}
    Request-PestoUxRefresh
}
function Invoke-PestoUxComputerLookupTick {
    param($Sender,$EventArgs)
    $Sender.Stop()
    # Un changement de mode ou l'ouverture d'une autre ligne pendant les 350 ms
    # ne doit jamais être écrasé par une ancienne demande de lecture.
    $sameContext=($script:PestoUxLookupName -ceq ([string]$TxtPCName.Text).Trim().ToUpperInvariant() -and
        $script:PestoUxLookupEditIndex -eq [int]$script:EDIT_ROW_INDEX -and
        $script:PestoUxLookupLocal -eq [bool]$script:LOCALHOST)
    if($sameContext -and -not $script:Running -and -not $script:PreflightRunning){Select-PCName}
    Request-PestoUxRefresh
}
function Invoke-PestoUxReadComputer {
    param($Sender,$EventArgs)
    if($script:Running -or $script:PreflightRunning -or (Test-PestoGlobalSafetyBarrier) -or $script:CfgRestartRequired){return}
    if($script:PestoUxLookupTimer){$script:PestoUxLookupTimer.Stop()}
    Select-PCName
    Request-PestoUxRefresh
}
function Invoke-PestoUxSourceKey {
    param($Sender,$EventArgs)
    if($EventArgs.Key -eq [Windows.Input.Key]::Return){$EventArgs.Handled=$true;Invoke-PestoUxReadComputer $Sender $EventArgs}
}
function Invoke-PestoUxKey {
    param($Sender,$EventArgs)
    if($EventArgs.Handled){return}
    $ctrl=([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Control)
    if($EventArgs.Key -eq [Windows.Input.Key]::F1){
        $EventArgs.Handled=$true;$focused=[Windows.Input.Keyboard]::FocusedElement
        $text=if($focused -and $focused -is [Windows.FrameworkElement]){[string]$focused.ToolTip}else{''}
        if($focused -is [Windows.Controls.TextBox] -and $focused.Name -eq 'PART_EditableTextBox'){
            $parent=[Windows.Controls.ItemsControl]::ItemsControlFromItemContainer($focused)
            if(-not $parent){$parent=$focused.TemplatedParent}
            if($parent -is [Windows.Controls.ComboBox]){$text=[string]$parent.ToolTip}
        }
        if($text){Show-PestoTextReport 'Aide du contrôle actif' $text}else{Set-PestoUxPage 'Help'}
    }elseif($ctrl){
        switch($EventArgs.Key){
            'D1' {Set-PestoUxPage 'Rename';$EventArgs.Handled=$true}
            'D2' {Set-PestoUxPage 'Names';$EventArgs.Handled=$true}
            'D3' {Set-PestoUxPage 'Log';$EventArgs.Handled=$true}
            'D4' {Set-PestoUxPage 'Join';$EventArgs.Handled=$true}
        }
    }
}

function Initialize-PestoUx {
    if($script:PestoUxReady){return}
    $script:PestoUxTimer=[Windows.Threading.DispatcherTimer]::new()
    $script:PestoUxTimer.Interval=[TimeSpan]::FromMilliseconds(90)
    $script:PestoUxTimer.Add_Tick([EventHandler]${function:Invoke-PestoUxRefreshTick})
    $script:PestoUxLookupTimer=[Windows.Threading.DispatcherTimer]::new()
    $script:PestoUxLookupTimer.Interval=[TimeSpan]::FromMilliseconds(350)
    $script:PestoUxLookupTimer.Add_Tick([EventHandler]${function:Invoke-PestoUxComputerLookupTick})
    foreach($n in @('NavHome','NavRename','NavJoin','NavNames','NavHistory','NavLogs','NavSettings','NavHelp','BtnHelp','BtnInlineHelp','HomePrepare','HomeQueue','HomeNames','HomeHistory')){
        $Win.FindName($n).Add_Click([Windows.RoutedEventHandler]${function:Invoke-PestoUxNavigate})
    }
    $BtnCopyNewName.Add_Click([Windows.RoutedEventHandler]${function:Invoke-PestoUxCopyName})
    $BtnReadComputer.Add_Click([Windows.RoutedEventHandler]${function:Invoke-PestoUxReadComputer})
    $BtnHistoryRefresh.Add_Click([Windows.RoutedEventHandler]${function:Invoke-PestoUxHistoryRefresh})
    $ChkTechnicalColumns.Add_Checked([Windows.RoutedEventHandler]${function:Invoke-PestoUxTechnicalChanged})
    $ChkTechnicalColumns.Add_Unchecked([Windows.RoutedEventHandler]${function:Invoke-PestoUxTechnicalChanged})
    $MainTabs.Add_SelectionChanged([Windows.Controls.SelectionChangedEventHandler]${function:Invoke-PestoUxPageChanged})
    $Win.Add_SizeChanged([Windows.SizeChangedEventHandler]${function:Invoke-PestoUxSizeChanged})
    $Win.Add_PreviewKeyDown([Windows.Input.KeyEventHandler]${function:Invoke-PestoUxKey})
    foreach($c in @($CbType,$CbOrg,$CbSite,$CbService,$CbName,$Grid,$CmbQueueFilter)){
        $c.Add_SelectionChanged([Windows.Controls.SelectionChangedEventHandler]${function:Invoke-PestoUxInputChanged})
    }
    foreach($c in @($ChkRemote,$ChkRename,$ChkMove,$ChkReboot)){
        $c.Add_Checked([Windows.RoutedEventHandler]${function:Invoke-PestoUxInputChanged})
        $c.Add_Unchecked([Windows.RoutedEventHandler]${function:Invoke-PestoUxInputChanged})
    }
    $BtnAdd.Add_IsEnabledChanged([Windows.DependencyPropertyChangedEventHandler]${function:Invoke-PestoUxInputChanged})
    $script:PestoUxReady=$true
    Set-PestoUxTechnicalColumns $false
    Update-PestoUxLayout
    Update-PestoUx
}
function Stop-PestoUx {
    $script:PestoUxReady=$false
    foreach($timer in @($script:PestoUxTimer,$script:PestoUxLookupTimer)){if($timer){$timer.Stop()}}
}

#  SECTION 13 — ÉVÉNEMENTS
###############################################################################

$BtnTheme.Add_Click([Windows.RoutedEventHandler]${function:Invoke-PestoThemeToggle})
$SetCmbDarkMode.Add_SelectionChanged([Windows.Controls.SelectionChangedEventHandler]${function:Invoke-PestoAppearanceChoice})
$BtnLog.Add_Click({ Open-AuditLog })

# ── Onglet « Noms disponibles » ──────────────────────────────────────────────
$NmCmbSite.Add_SelectionChanged({   if (-not $script:SuspendNm) { Update-NameGrid } })
$NmCmbEquipe.Add_SelectionChanged({ if (-not $script:SuspendNm) { Update-NameGrid } })
$NmCmbType.Add_SelectionChanged({   if (-not $script:SuspendNm) { Update-NameGrid } })
$NmCmbStatut.Add_SelectionChanged({ if (-not $script:SuspendNm) { Update-NameGrid } })
# La recherche texte est temporisée : pas de reconstruction de milliers de lignes
# à chaque frappe clavier.
$script:NmSearchTimer=New-Object System.Windows.Threading.DispatcherTimer
$script:NmSearchTimer.Interval=[TimeSpan]::FromMilliseconds(180)
$script:NmSearchTimer.Add_Tick({
    $script:NmSearchTimer.Stop()
    if(-not $script:SuspendNm){Update-NameGrid}
})
$NmTxtSearch.Add_TextChanged({
    if(-not $script:SuspendNm){
        # Invalider immédiatement ; le calcul reste temporisé.
        $script:NmViewGeneration=[int]$script:NmViewGeneration+1
        Stop-PestoAsyncOperation 'NamesProjection'
        if(-not (Test-PestoAsyncOperationRunning 'DirectoryRefresh') -and -not $script:NmNeedsDirectoryRetry){
            Set-PestoNamesViewState -State Loading -Title 'Application du filtre' -Detail 'Préparation de la liste filtrée.'
        }
        $script:NmSearchTimer.Stop();$script:NmSearchTimer.Start()
    }
})
$NmChkAll.Add_Checked({   if (-not $script:SuspendNm) { Update-NameGrid } })
$NmChkAll.Add_Unchecked({ if (-not $script:SuspendNm) { Update-NameGrid } })
$NmBtnNextP.Add_Click({ if ($NmBtnNextP.Tag) { Copy-NmName "$($NmBtnNextP.Tag)" } })
$NmBtnNextS.Add_Click({ if ($NmBtnNextS.Tag) { Copy-NmName "$($NmBtnNextS.Tag)" } })
$NmBtnNextV.Add_Click({ if ($NmBtnNextV.Tag) { Copy-NmName "$($NmBtnNextV.Tag)" } })
$NmBtnCopy.Add_Click({   if ($NmGrid.SelectedItem) { Copy-NmName "$($NmGrid.SelectedItem.Nom)" } })
$NmGrid.Add_MouseDoubleClick({ if ($NmGrid.SelectedItem) { Copy-NmName "$($NmGrid.SelectedItem.Nom)" } })
$NmBtnExport.Add_Click({ Export-NameView })
$NmBtnRefresh.Add_Click({ Refresh-Names })
foreach($name in @('NmRefreshSite','SuiteRefreshSite','JnRefreshSite')){$button=$Win.FindName($name);if($button){$button.Add_Click([Windows.RoutedEventHandler]${function:Request-PestoCurrentSiteRefresh})}}
$NmBtnRetryNames.Add_Click({ if(-not $NmBtnRefresh.IsEnabled){return}; if($script:NmNeedsDirectoryRetry -or (-not $script:InventoryLoaded -and -not $script:GUI)){[void](Refresh-Names)}else{Update-NameGrid} })

# ── Onglet « Paramètres » (éditeur cfg.json + navigateur OU) ──────────────────
Initialize-PestoSettingsTools
$SetBtnSave.Add_Click({ Save-Cfg })
$SetBtnCoordPrepare.Add_Click([Windows.RoutedEventHandler]${function:Invoke-PestoCoordinationCommand})
$SetBtnCoordTest.Add_Click([Windows.RoutedEventHandler]${function:Invoke-PestoCoordinationCommand})
$SetBtnReload.Add_Click({ Reload-CfgFromDisk })
$SetBtnBrowseScan.Add_Click({ $dn = Show-OUBrowser; if ($dn) { $SetTxtOUScan.Text = $dn } })
$SetBtnTagAdd.Add_Click({ Add-CfgRow $script:TblTags $SetGridTags })
$SetBtnTagDel.Add_Click({ Remove-CfgRow $SetGridTags })
$SetBtnBaseAdd.Add_Click({ Add-CfgRow $script:TblOUBase $SetGridOUBase })
$SetBtnBaseDel.Add_Click({ Remove-CfgRow $SetGridOUBase })
$SetBtnBaseBrowse.Add_Click({ Browse-OUForGrid $SetGridOUBase })
$SetBtnSiteAdd.Add_Click({ Add-CfgRow $script:TblOUSite $SetGridOUSite })
$SetBtnSiteDel.Add_Click({ Remove-CfgRow $SetGridOUSite })
$SetBtnSiteBrowse.Add_Click({ Browse-OUForGrid $SetGridOUSite })

$ChkRemote.Add_Checked({ On-RemoteToggle })
$ChkRemote.Add_Unchecked({ On-RemoteToggle })

$TxtPCName.Add_TextChanged({ Request-PestoUxComputerLookup })

$CbType.Add_SelectionChanged({ if (-not $script:Suspend) { Update-NameList } })
$CbOrg.Add_SelectionChanged({ if (-not $script:Suspend) { Apply-OrganismeSelection } })
$CbSite.Add_SelectionChanged({ if (-not $script:Suspend) { Apply-SiteSelection } })
$CbService.Add_SelectionChanged({ if (-not $script:Suspend) { Update-NameList } })
# Liste complétée à l'ouverture si la lecture ciblée du site n'a pas pu l'actualiser au chargement du poste.
$CbService.Add_DropDownOpened({ Invoke-PestoServiceDropDownOpened })
# Régénère le nom à chaque frappe dans le champ service / équipe (éditable), comme pour le site.
$CbService.AddHandler(
    [System.Windows.Controls.Primitives.TextBoxBase]::TextChangedEvent,
    [System.Windows.Controls.TextChangedEventHandler]{ if (-not $script:Suspend) { Update-NameList } })
$CbName.Add_SelectionChanged({ if (-not $script:Suspend) { Select-NewName } })

$ChkMove.Add_Checked({ if (-not $script:Suspend) { Update-RebootOption; Update-AddButton } })
$ChkMove.Add_Unchecked({ if (-not $script:Suspend) { Update-RebootOption; Update-AddButton } })
$ChkRename.Add_Checked({ if (-not $script:Suspend) { Check-SameOU } })
$ChkRename.Add_Unchecked({
    if(-not $script:Suspend) {
        $prev=$script:Suspend;$script:Suspend=$true
        try{$ChkMove.IsChecked=$false}finally{$script:Suspend=$prev}
        Check-SameOU
    }
})

$BtnAdd.Add_Click({
    try {
        $countBefore=$script:table.Rows.Count;$wasEditing=$script:EDIT_ROW_INDEX -ge 0
        Add-Or-UpdateRow
        if($script:PestoUxReady -and ($script:table.Rows.Count -gt $countBefore -or ($wasEditing -and $script:EDIT_ROW_INDEX -lt 0))){
            $QueueCard.BringIntoView();Request-PestoUxRefresh
        }
    }
    catch {
        $p = ''
        try { $p = "`n`n--- Position ---`n" + $_.InvocationInfo.PositionMessage } catch {}
        try { Add-LogLine "ERREUR à l'ajout : $($_.Exception.Message)" 'err' } catch {}
        [System.Windows.MessageBox]::Show("Erreur à l'ajout :`n$($_.Exception.Message)$p", 'Pesto — erreur', 'OK', 'Error') | Out-Null
    }
})

$Grid.Add_SelectionChanged({ Update-QueueButtons })
# Rafraîchit les compteurs après une coche « ✓ » (différé : la valeur n'est validée qu'après l'évènement).
$Grid.Add_CellEditEnding({
    $Grid.Dispatcher.BeginInvoke([action]{ Update-QueueButtons }) | Out-Null
})
$Grid.Add_MouseDoubleClick({
    $index=Get-PestoSelectedQueueIndex
    if($index -lt 0){return}
    if($script:table.Rows[$index].Statut -in @('OK','VÉRIFIÉ','SIMULÉ','PARTIEL','PROTECTION','INCERTAIN','TECHNIQUE','EN COURS')){Show-PestoSelectedResult}
    else{Enter-EditMode -Index $index}
})
$BtnEdit.Add_Click({ if ($script:EDIT_ROW_INDEX -ge 0) { Exit-EditMode; Update-QueueButtons } else { $index=Get-PestoSelectedQueueIndex;if($index -ge 0){Enter-EditMode -Index $index} } })
$BtnDelete.Add_Click({ Delete-SelectedRow })
$BtnClear.Add_Click({
    if($script:DirectBusy -or $script:JoinBusy -or $script:Running -or $script:PreflightRunning){return}
    if (Confirm-YesNo -Msg 'Vider toute la file ?' -Confirm $true) {
        $undoBefore=$script:table.Copy()
        $script:table.Rows.Clear(); $script:PreflightCache=@{}; $script:NmUsedSrc = $null; Sync-Grid; Exit-EditMode; Update-QueueButtons;Save-PestoQueueCheckpointSafe
        Save-PestoQueueUndo -Before $undoBefore -Reason 'Vidage local de la file'
    }
})
$BtnImport.Add_Click({ Import-Queue })
$BtnExport.Add_Click({ Export-Queue })
$BtnRun.Add_Click({ Run-Queue })
$BtnStop.Add_Click({ Request-PestoQueueStop })
$BtnPreview.Add_Click({ Show-PestoQueuePreview })
$BtnDetails.Add_Click({ Show-PestoSelectedResult })
$BtnRetryMove.Add_Click({ Prepare-PestoMoveRetry })
$BtnSafetyReset.Add_Click({ Reset-PestoSafetyLock })
$BtnSafetyAck.Add_Click({ Invoke-PestoQueueLockAcknowledgement })
$BtnBulk.Add_Click({Show-PestoBulkPlanner})
$BtnPreflight.Add_Click({Start-PestoQueuePreflight})
$BtnCancelPreflight.Add_Click({Stop-PestoQueuePreflight})
$BtnHtmlReport.Add_Click({Export-PestoHtmlReport})
$BtnHistory.Add_Click({Set-PestoUxPage 'History'})
$script:PreflightCache=@{};$script:PreflightRunning=$false;$script:PreflightGeneration=0
foreach($label in @('Toute la file','À traiter','À contrôler','À examiner','Réussites réelles','Simulations')){[void]$CmbQueueFilter.Items.Add($label)}
$CmbQueueFilter.SelectedIndex=0
$CmbQueueFilter.Add_SelectionChanged({Update-PestoQueueFilter})
$script:QueueSearchTimer=[Windows.Threading.DispatcherTimer]::new();$script:QueueSearchTimer.Interval=[TimeSpan]::FromMilliseconds(220)
$script:QueueSearchTimer.Add_Tick([EventHandler]${function:Invoke-PestoQueueSearchTick})
$TxtQueueSearch.Add_TextChanged({$script:QueueSearchTimer.Stop();$script:QueueSearchTimer.Start()})
$Win.Add_PreviewKeyDown({
    param($sender,$e)
    if($e.Handled){return}
    if($e.Key -eq [Windows.Input.Key]::F -and ([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Control)){
        $e.Handled=[bool](Invoke-PestoPageShortcut -Action Search)
    }elseif($e.Key -eq [Windows.Input.Key]::F5){
        $e.Handled=[bool](Invoke-PestoPageShortcut -Action Refresh)
    }
})

$BtnCheckAll.Add_Click({Set-PestoVisibleSelection -Selected $true})
$BtnUncheckAll.Add_Click({Set-PestoVisibleSelection -Selected $false})

$LogMnuCopy.Add_Click({
    try {
        $txt = ($script:LogEntries | ForEach-Object { '{0}  {1}' -f $_.Time, $_.Text }) -join [Environment]::NewLine
        if ($txt) { [System.Windows.Clipboard]::SetText($txt) }
    } catch { Show-MsgError "Copie impossible : $($_.Exception.Message)" 'Journal' }
})
$LogMnuClear.Add_Click({ Clear-Log })
$LogMnuDiag.Add_Click({ Export-Diagnostics })

# Entrée lit le poste. L'ajout reste une action explicite sur son bouton.
$TxtPCName.Add_KeyDown([Windows.Input.KeyEventHandler]${function:Invoke-PestoUxSourceKey})

###############################################################################
#  SECTION 14 — INITIALISATION
###############################################################################

$BasePath = Get-RootDir
$script:PestoBuildSHA256=''
try{$launcherPath=Join-Path $BasePath '..\Pesto.exe';if([IO.File]::Exists($launcherPath)){$script:PestoBuildSHA256=(Get-FileHash -LiteralPath $launcherPath -Algorithm SHA256).Hash.ToLowerInvariant()}}catch{}
Initialize-AuditLog -PreferredDir (Join-Path $BasePath 'logs')

# Filet de sécurité ULTIME : toute erreur terminante non interceptée ailleurs est
# journalisée (pile complète) puis signalée avant l'arrêt — crucial en .exe -NoConsole
# où un plantage non géré serait sinon TOTALEMENT silencieux.
trap {
    $fatalPos=''
    try { if($_.InvocationInfo -and $_.InvocationInfo.PositionMessage){ $fatalPos=[string]$_.InvocationInfo.PositionMessage } } catch {}
    try { Write-Log ("Erreur fatale non gérée — arrêt de Pesto. {0}" -f $fatalPos) 'FATAL' $_ 'trap' } catch {}
    try {
        $where=if($fatalPos){"`n`n$fatalPos"}else{''}
        [System.Windows.MessageBox]::Show(
            ("Une erreur fatale est survenue :`n$($_.Exception.Message)$where`n`nDétails complets dans le journal :`n$script:AuditFile"),
            'Pesto — erreur fatale', 'OK', 'Error') | Out-Null
    } catch {}
    try { Remove-ADModuleSafe } catch {}
    exit 1
}

$script:JsonFile = if($Demo){Join-Path $BasePath 'cfg.demo.json'}elseif($ConfigPath){[IO.Path]::GetFullPath($ConfigPath)}else{Join-Path $BasePath 'cfg.json'}
$JsonFile=$script:JsonFile
$script:CFG=Read-PestoStartupConfig -Path $script:JsonFile
# Read-PestoStartupConfig renvoie null uniquement après fermeture volontaire de
# la correction. Les erreurs de lecture/validation restent affichées dans cette
# fenêtre ; une exception inattendue reste traitée par le trap ci-dessus.
if($null -eq $script:CFG){Quit 0}
$script:PestoPolicy=ConvertTo-PestoPolicy $script:CFG.POLICY
if($script:AuditFile){
    try{[void](Remove-PestoExpiredLogs -Directory ([IO.Path]::GetDirectoryName($script:AuditFile)) -Days $script:PestoPolicy.LogRetentionDays -CurrentFile $script:AuditFile)}
    catch{Set-PestoPersistenceWarning ('Nettoyage des journaux incomplet : '+$_.Exception.Message)}
}
$conf = @($script:CFG.Conf)[0]

# ── Flags & paramètres ───────────────────────────────────────────────────────
$script:SIM         = Convert-Value-TF $script:CFG.Debug.Simulation
$script:ODM         = $DemoJoin.IsPresent -or (Convert-Value-TF $script:CFG.Debug.HorsDomaine)
$script:BVA         = Convert-Value-TF $script:CFG.Debug.BPVerifNomAD
$script:WOU         = Convert-Value-TF $script:CFG.Debug.MauvaiseOU
$script:GOD         = Convert-Value-TF $script:CFG.Debug.ForceADM
$script:GUI         = [bool]$Demo -or (Convert-Value-TF $script:CFG.Debug.GUI)
$script:PRD         = Convert-Value-TF $conf.DirectProd
$script:DSREG_LEAVE = $false # obsolète : jamais de dsregcmd /leave lors d'un simple déplacement d'OU
$script:CLEAR_PROTECTION = if ($null -ne $conf.ClearProtectionOnMove) { Convert-Value-TF $conf.ClearProtectionOnMove } else { $true }
$script:MOVE_ROLLBACK = if ($null -ne $conf.MoveRollbackOnRenameFail) { Convert-Value-TF $conf.MoveRollbackOnRenameFail } else { $false }
$script:PREFIXE     = "$($conf.Prefixe)".Trim().ToUpperInvariant()
$script:PREPRODSITE = "$($conf.PreprodSite)".Trim().ToUpperInvariant()
$script:DOMAINE     = "$($conf.Domaine)".Trim()
$script:DEFAULTADM  = "$($conf.ADM)".Trim()
$script:NmBuffer    = if ("$($conf.Buffer)".Trim()) { [int]$conf.Buffer } else { 10 }
$script:OU_SCAN     = "$($conf.OUScanNoms)".Trim()
$script:SuspendNm   = $false
$script:RuntimeTags = @($script:CFG.TAGS)

$script:HostMachineId=if($script:GUI){'DEMO-LOCAL'}else{[string](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid -ErrorAction Stop).MachineGuid}
Initialize-PestoAppearance -OwnerSid $AppearanceOwnerSid -Config $script:CFG
foreach($key in $script:Themes[$script:CurrentTheme].Keys){$Win.Resources[$key]=New-Brush $script:Themes[$script:CurrentTheme][$key]}
$script:AppearanceTimer=[Windows.Threading.DispatcherTimer]::new()
$script:AppearanceTimer.Interval=[TimeSpan]::FromSeconds(2)
$script:AppearanceTimer.Add_Tick([EventHandler]${function:Invoke-PestoAppearancePulse})
$script:AppearanceTimer.Start()


# ── Tables OU ────────────────────────────────────────────────────────────────
$script:OU  = @{}; @($script:CFG.OUBase) | ForEach-Object { $script:OU["$($_.Nom)".Trim()]  = "$($_.OU)".Trim() }
$script:OUV = @{}; @($script:CFG.OUSite) | ForEach-Object { $script:OUV["$($_.Nom)".Trim()] = "$($_.OU)".Trim() }
$script:OU_POSTES = $script:OU['ROOT']
if ([string]::IsNullOrWhiteSpace($script:OU_SCAN)) { $script:OU_SCAN = $script:OU['ROOT'] }

# ── Fenêtre de connexion WPF ─────────────────────────────────────────────────
# Même logique que le login ADCC : compte AD explicite OU session Windows,
# validation Active Directory inchangée ; erreurs et progression visibles seulement au besoin.

# Get-PestoWindowsAuthIdentity : composant séparé.

function Get-PestoAuthenticationRoute {
    param([bool]$InDomain,[bool]$AskCredential,[bool]$Demo)
    if($Demo){return 'Demo'}
    if($InDomain -and -not $AskCredential){return 'Windows'}
    return 'Explicit'
}

# Get-PestoExplicitCredentialRequirement : composant séparé.

# Set-PestoAuthenticatedSnapshot : composant séparé.

# Complete-PestoWindowsConnectionError : composant séparé.

# Complete-PestoWindowsConnectionSuccess : composant séparé.

# Start-PestoWindowsConnection : composant séparé.

# Show-PestoWindowsConnectionWindow : composant séparé.

# Get-PestoLoginPreferencePath : composant séparé.

# ConvertFrom-PestoLoginPreference : composant séparé.

# Get-PestoLoginPreference : composant séparé.

# Save-PestoLoginPreference : composant séparé.

# Set-PestoLoginFeedback : composant séparé.

# Invoke-PestoLoginForget : composant séparé.

# Set-PestoLoginWindowBounds : composant séparé.

# Set-PestoLoginBusy : composant séparé.

# Complete-PestoLoginError : composant séparé.

# Complete-PestoLoginSuccess : composant séparé.

# Start-PestoLoginAttempt : composant séparé.

# Show-LoginWindow : composant séparé.

# ── Module AD + détection domaine + connexion (sauf $GUI) ────────────────────
if (-not $script:GUI) {
    $domainState = CheckDomainWMI -DomainName2Compare $script:DOMAINE
    if ($script:ODM) { $script:INDOMAIN = $false }
    elseif ($null -eq $domainState) {
        Show-MsgError 'Impossible de déterminer si ce poste appartient au domaine. La jonction est bloquée par sécurité. Vérifiez le service WMI/CIM puis relancez Pesto.' 'Détection du domaine impossible'
        Quit 1
    } elseif ($script:DetectedDomain -and $script:DetectedDomain -ine $script:DOMAINE) {
        Show-MsgError "Ce poste appartient déjà au domaine '$script:DetectedDomain', différent du domaine cible '$script:DOMAINE'. La jonction automatique est bloquée pour éviter une sortie de domaine involontaire." 'Domaine différent détecté'
        Quit 1
    } else { $script:INDOMAIN = [bool]$domainState }

    $authRoute=Get-PestoAuthenticationRoute -InDomain ([bool]$script:INDOMAIN) -AskCredential $AskCredential.IsPresent -Demo $false
    if($authRoute -eq 'Windows'){
        $connection=Show-PestoWindowsConnectionWindow
        $loginOk=($connection -eq 'Connected')
        if($connection -eq 'Explicit'){$loginOk=Show-LoginWindow}
    } else { $loginOk=Show-LoginWindow }
    if (-not $loginOk) { Quit }
} else {
    $script:INDOMAIN = -not $script:ODM
    $script:DC = 'GUI-DC'; $script:cred = $null
}

# En mode normal le loading a déjà été créé juste avant la fermeture du login.
# Ce garde-fou couvre le mode GUI et toute transition où il n'aurait pas pu être créé.
if (-not $script:PestoStartupWindow) { Show-PestoStartupWindow }
Set-PestoStartupStage -Stage 'Préparation des données' -Detail 'Initialisation de Pesto.'

# ── Collecte AD initiale (sites + ordinateurs) — mode GUI seulement ──────────
# CORRECTIF : l'initialisation à vide ne doit s'exécuter QU'EN mode GUI. Exécutée
# sans condition (régression), elle ÉCRASAIT Sites + Computers chargés par
# Show-LoginWindow/doLoad juste au-dessus → combos Site/Équipe et onglet Noms vides.
if ($script:GUI) {
    $script:Sites = @{}; $script:Computers = @()
    # Jeu de données factice pour explorer l'UI sans AD (les deux onglets).
    $script:OUV.GetEnumerator() | ForEach-Object { $script:Sites[$_.Name] = @('Paris','Lyon','Marseille') }
    $script:Computers = New-DemoComputers
    $script:ComputersNoms = $script:Computers
    Update-PestoComputerIndex
}
# (mode non-GUI : Sites + Computers déjà remplis par Show-LoginWindow)

# ── État initial ─────────────────────────────────────────────────────────────
$script:EDIT_ROW_INDEX = -1
$script:LOCALHOST = $true
$script:Suspend = $false

# Renseigne les organismes.
Set-PestoStartupStage -Stage "Préparation de l'interface" -Detail 'Chargement des listes et des contrôles.'
$script:OUV.Keys | Sort-Object | ForEach-Object { [void]$CbOrg.Items.Add($_) }

# ── Pastilles d'état (en-tête) ───────────────────────────────────────────────
$modeTxt = if (-not $script:INDOMAIN) { 'HORS DOMAINE' } else { 'DANS LE DOMAINE' }

# Pastille « nom de ce poste (hôte) » — plus parlant qu'un libellé abstrait.
$hostTip = if ($script:INDOMAIN) {
    "Nom de ce poste (l'hôte sur lequel Pesto est lancé) — membre du domaine $($script:DOMAINE)."
} else {
    "Nom de ce poste (l'hôte sur lequel Pesto est lancé) — pas encore joint au domaine."
}
Set-Chip $ChipMember $env:COMPUTERNAME $(if ($script:INDOMAIN) { 'Neutral' } else { 'Warn' }) $hostTip

Set-Chip $ChipDomain $script:DOMAINE 'Neutral' 'Domaine Active Directory ciblé.'
$accountLabel=if($script:GUI){'Compte : démonstration'}elseif($script:AuthUser){[string]$script:AuthUser}else{'Compte non confirmé'}
$accountTip=if($script:AuthMode -eq 'Windows'){'Compte Windows élevé réutilisé automatiquement. Aucun mot de passe conservé par Pesto. Les droits sont vérifiés par Windows et AD à chaque opération.'}else{'Compte AD explicitement choisi pour cette session Pesto.'}
Set-Chip $ChipAccount $accountLabel 'Info' ($accountLabel+' : '+$accountTip)

# Le mode de jonction ne concerne qu'un poste PAS encore dans le domaine.
# Pour un poste déjà membre (renommage / déplacement), on masque la pastille.
if (-not $script:INDOMAIN) {
    $ChipJoin.Visibility = 'Visible'
    if ($script:PRD) {
        Set-Chip $ChipJoin 'Jonction : production directe' 'Ok' `
            "À la jonction au domaine, ce poste sera placé directement dans son OU de production cible."
    } else {
        Set-Chip $ChipJoin 'Jonction : zone de transit (pré-prod)' 'Info' `
            "À la jonction au domaine, ce poste sera d'abord placé dans l'OU de transit (pré-production : $($script:PREPRODSITE)) avant son placement final."
    }
} else {
    $ChipJoin.Visibility = 'Collapsed'
}

if ($script:SIM) { $ChipSim.Visibility = 'Visible'; Set-Chip $ChipSim 'SIMULATION' 'Warn' 'Les commandes sont affichées mais pas exécutées.' }
if ($script:GUI) { $ChipGui.Visibility = 'Visible'; Set-Chip $ChipGui 'démo · sans AD' 'Neutral' "Mode démonstration (cfg.json DEBUG.GUI=true) : aucun appel Active Directory réel, données fictives." }

# Applique le thème puis l'état local par défaut.
Set-PestoStartupStage -Stage 'Préparation du poste' -Detail 'Application du contexte de session.'
Set-Theme $script:CurrentTheme

if (-not $script:INDOMAIN) {
    # Initialisation dédiée : ne dépend pas des événements WPF et ne peut pas rester
    # dans l'état XAML par défaut (contrôles grisés).
    if(-not (Initialize-PestoHorsDomainUI)){
        try{Close-PestoStartupWindow}catch{}
        Show-MsgError 'Le mode hors domaine n''a pas pu être initialisé. Consultez le journal Pesto.' 'Pesto - initialisation hors domaine'
        Quit 1
    }
} else {
    Set-ModeLocal
}
Update-QueueButtons

# ── Onglet « Paramètres » : éditeur cfg.json ──
Set-PestoStartupStage -Stage 'Chargement des paramètres' -Detail 'Préparation de la configuration.'
$script:SuspendSet = $false
Load-SettingsUI

# ── Onglet « Noms disponibles » : initialisation (réutilise le scan partagé) ──
Set-PestoStartupStage -Stage 'Préparation des noms disponibles' -Detail 'Construction de la liste des noms.'
Build-NmIndex
Populate-NmFilters
Update-NameGrid
# À ce stade, le contexte local a été initialisé explicitement. En hors domaine,
# aucun événement WPF n'est requis pour déverrouiller le formulaire.
Set-PestoStartupStage -Stage 'Finalisation' -Detail 'Vérification des contrôles.'
if($script:INDOMAIN -and -not $script:GUI){
    if(-not $CbType.IsEnabled -or -not $CbOrg.IsEnabled){
        # Repli défensif : on force une nouvelle application du snapshot local avant affichage.
        $localCached=Get-PestoCachedComputerProbe -Name $env:COMPUTERNAME -Local $true
        if($localCached){
            $script:PCProbeGeneration=[int]$script:PCProbeGeneration+1
            [void](Apply-PestoComputerProbeResult -Result $localCached -Name $env:COMPUTERNAME -Generation $script:PCProbeGeneration)
        }
    }
} elseif(-not $script:INDOMAIN){
    # Repli défensif hors domaine : si une fonction intermédiaire a modifié l'état,
    # réappliquer le profil AVANT de montrer la fenêtre.
    $needRepair=(-not $CbType.IsEnabled)
    if($script:PRD){$needRepair=$needRepair -or (-not $CbOrg.IsEnabled)}
    else{$needRepair=$needRepair -or ("$($CbOrg.SelectedItem)" -ine 'PREPROD') -or (-not (Test-PestoOUPath $script:OU_FINAL))}
    if($needRepair){
        if(-not (Initialize-PestoHorsDomainUI)){
            try{Close-PestoStartupWindow}catch{}
            Show-MsgError 'L''interface hors domaine est restée dans un état invalide. Pesto s''arrête sans effectuer d''action.' 'Pesto - sécurité démarrage'
            Quit 1
        }
    }
}

# En-tête de session dans le journal d'audit (traçabilité + diagnostic complet).
if ($script:AuditFile) {
    Write-Log ('AuthMode='+[string]$script:AuthMode+' | AuthUser='+[string]$script:AuthUser+' | CredentialEnMemoire='+[bool]($null -ne $script:cred)) 'INFO' $null 'auth'
    $acct  = if ($script:cred) { $script:cred.UserName } elseif ($script:GUI) { '(aucun — mode GUI)' } elseif ($script:AuthUser) { "$($script:AuthUser) [Compte Windows]" } else { "$env:USERDOMAIN\$env:USERNAME [Compte Windows]" }
    $flags = (@(if ($script:SIM){'SIM'}; if ($script:GUI){'GUI'}; if ($script:PRD){'PRD'}; if ($script:ODM){'ODM'}; if ($script:WOU){'WOU'}) -join ',')
    $isAdmin = $false
    try { $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) } catch {}
    $exeMode = if ($PSCommandPath -and (Split-Path $PSCommandPath -Leaf) -like '*.ps1') { 'script .ps1' } else { 'exe compilé' }
    Write-AuditLine ('================ Session Pesto — {0} ================' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) 'head'
    Write-Log ("Hote={0} | UtilisateurWin={1} | CompteAD={2} | Admin={3} | Mode={4} | Domaine={5} | DC={6} | DansDomaine={7} | Flags={8}" -f `
        $env:COMPUTERNAME, $env:USERNAME, $acct, $isAdmin, $modeTxt, $script:DOMAINE, $script:DC, $script:INDOMAIN, $(if ($flags) { $flags } else { '—' })) 'INFO' $null 'session'
    Write-Log ("Env : PSVersion={0} | OS={1} | x64={2} | Lancement={3} | Prefixe={4} | PreprodSite={5} | NiveauLog={6} | Journal={7}" -f `
        $PSVersionTable.PSVersion, [Environment]::OSVersion.VersionString, [Environment]::Is64BitProcess, $exeMode, `
        $script:PREFIXE, $script:PREPRODSITE, $script:LogLevel, $script:AuditFile) 'INFO' $null 'session'
}

# Message d'accueil.
Add-LogLine "Pesto $script:Pesto_VERSION démarré — $modeTxt · domaine $($script:DOMAINE)." 'head'
# Bilan de la collecte initiale : un scan vide ou hors convention était auparavant
# totalement silencieux (catch muet + sortie muette) -> interface morte sans indice.
if (-not $script:GUI) {
    $nbOrg   = @($script:Sites.Keys).Count
    $nbSites = 0; foreach ($v in $script:Sites.Values) { $nbSites += @($v).Count }
    $nbPC    = @($script:Computers).Count
    $nb15    = @(@($script:Computers) | Where-Object { "$($_.Name)".Length -eq 15 }).Count
    $bilKind = if ($nbPC -eq 0 -or $nbSites -eq 0) { 'warn' } else { 'info' }
    Add-LogLine "Connexion prête : $nbOrg organisme(s) / $nbSites site(s). Inventaire complet chargé à la demande, pas pendant le login." 'info'
    if (-not [object]::ReferenceEquals($script:ComputersNoms, $script:Computers)) {
        Add-LogLine "Périmètre onglet Noms ($(Format-OUPath $script:OU_SCAN)) : $(@($script:ComputersNoms).Count) poste(s)." 'info'
    }
    if ($nbPC -gt 0 -and $nb15 -eq 0) {
        Add-LogLine "Aucun poste conforme à la convention 15 caractères : vérifiez le préfixe et l'OU scannée (l'onglet Noms restera vide)." 'warn'
    }
}
if ($script:AuditFile) { Add-LogLine "Journal d'audit : $script:AuditFile" 'info' }
if ($script:GUI) { Add-LogLine 'Mode démonstration : aucun appel Active Directory réel ne sera effectué.' 'info' }
elseif ($script:SIM) { Add-LogLine 'Mode SIMULATION : les commandes sont affichées, pas exécutées.' 'warn' }
if (-not $script:INDOMAIN) {
    $join = if ($script:PRD) { 'production directe' } else { "zone de transit (pré-prod : $($script:PREPRODSITE))" }
    Add-LogLine "Jonction au domaine prévue vers : $join." 'info'
}

$script:PestoDesignWidth=[double]$Win.Width;$script:PestoDesignHeight=[double]$Win.Height
$screenWork=[Windows.SystemParameters]::WorkArea
$Win.Width=[Math]::Min($Win.Width,[Math]::Max($Win.MinWidth,$screenWork.Width-20))
$Win.Height=[Math]::Min($Win.Height,[Math]::Max($Win.MinHeight,$screenWork.Height-20))
Initialize-PestoUx
Initialize-PestoJoinUI
Initialize-PestoSuiteUI
Initialize-PestoInterventionsUI
Initialize-PestoPreparationUI
Initialize-PestoNamesPageUI
Initialize-PestoWorkspace
Initialize-PestoWorkbench
Initialize-PestoCollections
Initialize-PestoBatchTools
Initialize-PestoNameWorkbench
Initialize-PestoConfigEditor
Initialize-PestoDirectState
if(-not $script:INDOMAIN){
    $Win.FindName('TabRename').IsEnabled=$false
    $Win.FindName('NavRename').IsEnabled=$false
    $Win.FindName('NavBatch').IsEnabled=$false
    $Win.FindName('NavBatch').ToolTip='Ce PC est hors domaine. Utilisez Ajouter au domaine.'
    $Win.FindName('NavRename').ToolTip='Ce PC est hors domaine. Utilisez Ajouter au domaine.'
    $Win.FindName('HomePrepare').IsEnabled=$false
    $Win.FindName('HomePrepare').ToolTip='Ce PC est hors domaine. Utilisez Ajouter au domaine.'
    $Win.FindName('HomeQueue').IsEnabled=$false
    $Win.FindName('HomeQueue').ToolTip='La file concerne le parc deja joint. Pour ce PC, utilisez Ajouter au domaine.'
    Set-PestoUxPage 'Join'
}

# ── Affichage ────────────────────────────────────────────────────────────────
# Filet de sécurité : une exception dans un handler ne doit pas tuer la fenêtre.
# On l'attrape, on l'affiche (cause + ligne) et on garde l'appli en vie.
try {
    $Win.Dispatcher.add_UnhandledException(
        [System.Windows.Threading.DispatcherUnhandledExceptionEventHandler]{
            param($s, $e)
            $e.Handled = $true
            if($script:Running){$script:MutationUncertain=$true;$script:QueueStopRequested=$true}
            if(Test-PestoAsyncOperationRunning 'DomainJoin'){$script:JoinLocked=$true;Set-PestoQueueCancellationFence $script:JoinActiveRequest.Monitor}
            # Action unitaire, reprise et réservation AD : verrou et barrière d'annulation ; aucun verrou n'est levé ici.
            if(Test-PestoAsyncOperationRunning 'DirectAction'){$script:DirectLocked=$true;try{Set-PestoQueueCancellationFence $script:PestoAsyncOperations['DirectAction'].QueueMonitor}catch{}}
            if(Test-PestoAsyncOperationRunning 'RecoveryAction'){$script:RecoveryBusy=$true;try{Set-PestoQueueCancellationFence $script:PestoAsyncOperations['RecoveryAction'].QueueMonitor}catch{}}
            foreach($adOperation in @('JoinADReserve','JoinADRelease','JoinADInspect')){if(Test-PestoAsyncOperationRunning $adOperation){$script:JoinADReservationNeedsReview=$true;$script:JoinLocked=$true}}
            $ex  = $e.Exception
            $pos = ''
            try {
                if ($ex.ErrorRecord -and $ex.ErrorRecord.InvocationInfo) {
                    $pos = "`n`n--- Position ---`n" + $ex.ErrorRecord.InvocationInfo.PositionMessage
                }
            } catch {}
            $detail = "$($ex.GetType().FullName)`n$($ex.Message)$pos"
            try { $errObj = if ($ex.ErrorRecord) { $ex.ErrorRecord } else { $ex }; Write-Log "Exception non gérée dans un gestionnaire d'interface : $($ex.Message)" 'ERROR' $errObj 'dispatcher' } catch {}
            try { Add-LogLine "ERREUR interceptée : $($ex.Message)" 'err' } catch {}
            try { [System.Windows.MessageBox]::Show($detail, 'Erreur Pesto (interceptée)', 'OK', 'Error') | Out-Null } catch {}
        })
} catch {}

$Win.Add_Closed({
    Close-PestoReadRunspacePool $script:PestoReadPool
    try{Stop-PestoJoinADReservationAtClose}catch{}
    Stop-PestoAuditWriter
    Stop-PestoNamesLoadTimer
    Stop-PestoJoinUI
    Stop-PestoSharedNameTimer
    if($script:AppearanceTimer){$script:AppearanceTimer.Stop()}
    if($script:SuiteTimer){$script:SuiteTimer.Stop()}
    Stop-PestoUx
    Stop-PestoPilotagePulse
    try{if($script:QueueSearchTimer){$script:QueueSearchTimer.Stop()}}catch{}
    try{if($script:NmSearchTimer){$script:NmSearchTimer.Stop()}}catch{}
    foreach($opName in @($script:PestoAsyncOperations.Keys)){ try{Stop-PestoAsyncOperation $opName}catch{} }
    Remove-ADModuleSafe
})
$Win.Add_Closing({
    param($sender,$e)
    # A hosted panel consumed this close request; the main window stays open.
    if($e.Cancel){return}
    if ($script:Running -or $script:DirectBusy -or $script:JoinBusy -or $script:RecoveryBusy -or (Test-PestoAsyncOperationRunning 'LedgerTasks') -or (Test-PestoQueueWorkerStillActive)) {
        $e.Cancel = $true
        Show-MsgWarning 'Une opération Windows est encore en cours. Consultez le journal ; fermer Pesto ne permettrait pas de garantir son annulation.' 'Traitement en cours'
        return
    }
    # Compte réservé dans l'AD en cours de création ou de retrait : fermer maintenant perdrait le résultat et laisserait un
    # compte « Réservé par Pesto » dans l'AD. L'opération dure 60 secondes au plus.
    if($script:PestoAsyncOperations -and @($script:PestoAsyncOperations.Keys|Where-Object{$_ -eq 'JoinADReserve' -or $_ -like 'JoinADRelease*'}).Count){
        $e.Cancel = $true
        Show-MsgWarning 'Réservation du nom dans l''AD en cours (création ou retrait du compte). Réessayez dans quelques secondes.' 'Réservation en cours'
        return
    }
    if(-not(Confirm-PestoDiscardSettings)){$e.Cancel=$true;return}
    if($script:PreflightRunning){Stop-PestoQueuePreflight}
    foreach($name in @('JoinCheck','JoinStatus')){if(Test-PestoAsyncOperationRunning $name){Stop-PestoAsyncOperation $name}}
    Save-PestoQueueCheckpointSafe -Phase $(if($script:MutationUncertain){'Uncertain'}else{'Idle'})
    Save-Prefs
})
# Focus initial : sur le champ « Nom du poste » (TxtPCName), qu'il soit saisissable
# (mode distant) OU en lecture seule (mode local) — un TextBox en lecture seule
# accepte le focus WPF et n'affiche qu'un liseré fin + caret, jamais le grand
# rectangle pointillé du TabControl. TxtPCName existant et focusable dans tous les
# modes, le repli onglets ne sert que s'il était absent du XAML.
$Win.Add_Loaded({
    Load-Prefs
    Apply-PestoSavedTables
    Update-PestoUxLayout
    Request-PestoUxRefresh
    if(-not $script:INDOMAIN){
        try {
            if(-not (Initialize-PestoHorsDomainUI)){
                Show-MsgError 'Le mode hors domaine n''a pas pu être réparé à l''événement Loaded. Consultez le journal.' 'Pesto 17 - hors domaine'
            }
        } catch { Write-Log 'Réparation hors domaine au Loaded impossible.' 'ERROR' $_ 'hd-ui' }
    }
    if(-not $script:INDOMAIN -and $script:JoinUI){Set-PestoUxPage 'Join';[void]$script:JoinUI.Type.Focus()}
    elseif ($TxtPCName) { [void]$TxtPCName.Focus() }
    elseif ($MainTabs)  { [void]$MainTabs.Focus() }
})

# Le loading reste au premier plan jusqu'au PREMIER rendu réel du GUI.
$script:PestoStartupClosePending = $true
$Win.Add_ContentRendered({
    # Registre partagé des réservations de noms (inactif sans POLICY.CoordinationRoot).
    try{Start-PestoSharedNameTimer}catch{Write-Log 'Registre partagé des noms non démarré.' 'WARN' $_ 'noms'}
    if(-not $script:QueueRestoreChecked){
        [void]$Win.Dispatcher.BeginInvoke([Action]{Restore-PestoQueueCheckpoint},[Windows.Threading.DispatcherPriority]::ApplicationIdle)
    }
    # Dernier passage APRÈS le rendu WPF : élimine un éventuel IsEnabled différé
    # provenant d'un événement de chargement/style. Ce passage est purement local.
    if(-not $script:INDOMAIN){
        try{[void](Initialize-PestoHorsDomainUI)}catch{Write-Log 'Réparation hors domaine au ContentRendered impossible.' 'ERROR' $_ 'hd-ui'}
        try{
            [void]$Win.Dispatcher.BeginInvoke([action]{
                try{
                    if(-not $script:INDOMAIN){
                        [void](Initialize-PestoHorsDomainUI)
                        $LblStatus.Text="Prêt · HORS DOMAINE · Pesto $script:Pesto_VERSION"
                    }
                } catch { Write-Log 'Réparation hors domaine différée impossible.' 'ERROR' $_ 'hd-ui' }
            }, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
        }catch{}
    }
    # 19/10/2026 : la lecture ciblée du site lancée pendant le chargement pouvait ne jamais aboutir ; relue une fois
    # la fenêtre prête (sans effet si elle est récente ou en cours).
    if(-not $script:FormSiteLookupStarted -and $script:INDOMAIN){$script:FormSiteLookupStarted=$true;[void]$Win.Dispatcher.BeginInvoke([Action]{Request-PestoFormSiteLookup},[Windows.Threading.DispatcherPriority]::ApplicationIdle)}
    if(-not $script:JoinStatusStarted -and $script:JoinUI){$script:JoinStatusStarted=$true;[void]$Win.Dispatcher.BeginInvoke([Action]{Start-PestoJoinStatus},[Windows.Threading.DispatcherPriority]::ApplicationIdle)}
    if ($script:PestoStartupClosePending) {
        if(Test-PestoAsyncOperationRunning 'PCProbe'){
            # Cas de repli : le GUI est déjà rendu derrière, mais le loading reste
            # devant jusqu'à la réponse du poste afin de ne jamais montrer un
            # formulaire gris sans explication.
            try{Set-PestoStartupStage -Stage 'Identification du poste' -Detail 'Vérification Active Directory.'}catch{}
        } else {
            $script:PestoStartupClosePending = $false
            try { Close-PestoStartupWindow } catch {}
        }
    }
})
Set-PestoStartupStage -Stage 'Prêt' -Detail 'Ouverture de Pesto.'
[void]$Win.ShowDialog()
try { Close-PestoStartupWindow } catch {}
Quit 0
