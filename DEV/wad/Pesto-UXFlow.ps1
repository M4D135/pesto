#requires -Version 5.1
# Présentation du parcours unitaire. Les décisions métier restent dans le moteur existant.

# Table unique des libellés affichés. Les messages ne doivent pas recopier un nom de
# page ou de bouton à la main : ils passent par Get-PestoUxNom. Chaque valeur doit
# correspondre à l'attribut Content, Header ou Text réellement présent dans le XAML —
# tests/test_ux_noms.py le vérifie, donc renommer un contrôle sans reprendre cette
# table fait échouer les tests au lieu de laisser un message citer un bouton qui
# n'existe plus (trois libellés de ce genre ont été mesurés et corrigés le 10/10/2026 ;
# leurs noms sont dans l'historique du dépôt, pas ici : tests/test_ux_noms.py interdit
# de les faire revenir dans wad/).
# Ne couvrent pas les libellés calculés par le code, comme celui que pose
# Get-PestoPrimaryStep sur l'action principale selon le blocage en cours.
$script:PESTO_UX_NOMS = [ordered]@{
    PageAccueil      = 'Accueil'
    PagePoste        = 'Un seul poste'
    PageLot          = 'Plusieurs postes'
    PageNoms         = 'Noms disponibles'
    PageJonction     = 'Ajouter au domaine'
    PageParametres   = 'Paramètres'
    BtnReprendre     = 'Vérifier puis reprendre'
    ChkPosteDistant  = 'Un autre poste du domaine'
    BtnAjouterPc     = 'Ajouter ce PC au domaine'
    BtnInterventions = 'Interventions et reprises'
    BtnReessayer     = 'Réessayer'
    BtnValider       = 'Valider, sauvegarder et continuer'
    BtnVerifierAD    = 'Vérifier dans AD'
    BtnVersRenommage = 'Ouvrir Renommer / déplacer'
}

function Get-PestoUxNom {
    <# Renvoie le libellé d'un élément d'interface pour que les messages ne le recopient
       pas. Une clé inconnue est une erreur de programmation : elle lève. Un message
       affichant « PagePoste » se voit à l'écran, un message vide à la place du nom non. #>
    param([Parameter(Mandatory=$true)][string]$Cle)
    if(-not $script:PESTO_UX_NOMS.Contains($Cle)){ throw "Nom UX inconnu : $Cle" }
    [string]$script:PESTO_UX_NOMS[$Cle]
}

function Get-PestoLocalPendingRename {
    <# Renommage local en attente de redémarrage, d'après l'observation Windows de l'accueil
       ($script:HomeLocalSnapshot : nom actif, nom configuré, PendingRename booléen ou $null).
       Observation absente ou incertaine : aucun blocage déduit. Retourne $null ou Active/Configured/Hint. #>
    param($Local,[string]$Target)
    if(-not $Local -or $Local.PendingRename -isnot [bool] -or -not $Local.PendingRename -or
        [string]::IsNullOrWhiteSpace([string]$Local.ConfiguredName) -or [string]::IsNullOrWhiteSpace([string]$Local.Computer) -or
        ([string]$Local.ConfiguredName) -ieq ([string]$Local.Computer) -or
        -not($Target -ieq [string]$Local.Computer -or $Target -ieq [string]$Local.ConfiguredName)){return $null}
    $configured=[string]$Local.ConfiguredName
    return [pscustomobject]@{
        Active=[string]$Local.Computer
        Configured=$configured
        Hint="Ce PC attend un redémarrage : Windows appliquera le nom « $configured » au prochain démarrage. Redémarrez-le avant de le modifier de nouveau. Le reçu est conservé ; la vérification reste facultative."
    }
}

function Get-PestoPrimaryStep {
    param([string]$Computer,[bool]$Busy,[bool]$Blocked,[bool]$Loaded,[bool]$FormReady,
          [bool]$ResumeMove,[bool]$Rename,[bool]$ReadOnly,[string]$Missing='',[string]$BlockedHint='',
          [ValidateSet('None','ReviewJoin','ReviewDirect','Interventions')][string]$BlockedAction='None',
          [string]$BlockedLabel='Vérification requise')
    $s=[ordered]@{Action='None';Label='Lire le poste';Enabled=$false;Hint='Saisissez le nom du poste.'}
    if($Busy){$s.Label='Traitement en cours';$s.Hint='Attendez la fin de la lecture ou de l''intervention. Le journal reste consultable.'}
    elseif($Blocked){
        # Le blocage dit sa cause et, quand c'est possible, le bouton ouvre la vérification qui le lève (08/10).
        $s.Label=$BlockedLabel;$s.Hint=if($BlockedHint){$BlockedHint}else{'Une opération ou une configuration attend votre vérification. Aucun nouveau traitement lancé.'}
        if($BlockedAction -ne 'None' -and -not $ReadOnly){
            $s.Action=$BlockedAction;$s.Enabled=$true
            $s.Label=switch($BlockedAction){'ReviewJoin'{'Vérifier la jonction'};'ReviewDirect'{'Vérifier l''opération'};default{'Ouvrir les interventions'}}
        }
    }
    elseif(-not(Test-PestoComputerName $Computer)){$s.Label='Saisir le poste'}
    elseif(-not $Loaded -and -not $ResumeMove){$s.Action='Read';$s.Label='Lire ce poste';$s.Enabled=$true;$s.Hint='Lire les informations du poste. Aucun changement Windows ou AD.'}
    elseif($ReadOnly){$s.Label='Consultation';$s.Hint='Les informations peuvent être relues. Les mutations sont interdites dans ce mode.'}
    elseif(-not $FormReady -and -not $ResumeMove){$s.Action='Prepare';$s.Label='Compléter le formulaire';$s.Enabled=$true;$s.Hint=$(if($Missing){$Missing+' « Compléter le formulaire » place le curseur sur ce choix.'}else{'Placer le curseur sur le prochain choix requis, sans lancer une opération.'})}
    else{$s.Action='Execute';$s.Label=if($ResumeMove){'Vérifier puis déplacer seulement'}elseif($Rename){'Vérifier puis renommer'}else{'Vérifier puis déplacer'};$s.Enabled=$true;$s.Hint='Relire le plan, afficher son impact puis attendre votre confirmation avant toute écriture.'}
    return [pscustomobject]$s
}

function Get-PestoPrimaryContext {
    $computer=([string]$TxtPCName.Text).Trim()
    $busy=($script:Running -or $script:PreflightRunning -or $script:DirectBusy -or $script:JoinBusy -or
        (Test-PestoAsyncOperationRunning 'PCProbe') -or (Test-PestoQueueWorkerStillActive))
    # Renommage local en attente de redémarrage (V2B03) : aucune nouvelle modification de ce PC avant le
    # redémarrage. La reprise d'un déplacement déjà accepté reste disponible ; cette cause est dite en
    # dernier pour que les vérifications proposées ci-dessous restent accessibles.
    $pendingRename=Get-PestoLocalPendingRename -Local $script:HomeLocalSnapshot -Target $computer
    $isPendingRename=($null -ne $pendingRename -and -not $script:DirectResumePlan)
    $blocked=($script:CfgRestartRequired -or $script:JoinLocked -or (Test-PestoGlobalSafetyBarrier) -or
        $script:EDIT_ROW_INDEX -ge 0 -or ((Test-PestoDirectTargetBarrier $computer) -and -not $script:DirectResumePlan) -or $isPendingRename)
    # Cause du blocage, dite en clair, et action qui ouvre la vérification correspondante (lecture seule jusqu'à confirmation).
    $blockedHint='';$blockedAction='None';$blockedLabel='Vérification requise'
    if($script:CfgRestartRequired){$blockedHint='Paramètres enregistrés : fermez puis relancez Pesto pour continuer.'}
    elseif($script:JoinLocked){
        $blockedHint='La jonction de ce PC nécessite encore un redémarrage ou son état reste indéterminé. Cliquez sur « Vérifier la jonction » pour relire Windows et l''AD. Le suivi complémentaire d''une commande terminée reste facultatif.'
        if($script:JoinReceipt){$blockedAction='ReviewJoin'}
    }
    elseif(Test-PestoGlobalSafetyBarrier){$blockedHint='Une ancienne exécution doit être vérifiée avant toute nouvelle écriture. Cliquez sur « Ouvrir les interventions ».';$blockedAction='Interventions'}
    elseif($script:EDIT_ROW_INDEX -ge 0){$blockedHint='Une ligne de la file est en cours de modification : terminez ou annulez l''édition.'}
    elseif((Test-PestoDirectTargetBarrier $computer) -and -not $script:DirectResumePlan){$blockedHint='La dernière opération sur ce poste attend une vérification. Cliquez sur « Vérifier l''opération ».';$blockedAction='ReviewDirect'}
    elseif($isPendingRename){$blockedHint=$pendingRename.Hint;$blockedLabel='Redémarrage requis'}
    # Reset-ConfigFields invalide ces champs dès que la cible saisie change.
    $loaded=([bool]$script:OU_ACTUELLE -and $CbOrg.IsEnabled -and $CbType.IsEnabled)
    # Ce qui manque, dit en clair : « Vérifier » reste grisé tant que le formulaire n'est pas complet.
    $missing=if(-not $CbType.SelectedItem){'Choisissez le type de poste.'}elseif(-not $CbOrg.SelectedItem){'Choisissez l''organisme.'}`
        elseif(-not $CbSite.SelectedItem){'Choisissez le site.'}elseif(([string]$CbService.Text) -notmatch '^[A-Za-z0-9]{3}$'){'Choisissez ou saisissez le service (3 caractères).'}`
        elseif($script:NewNameExists){'Ce nom est déjà utilisé dans l''AD : choisissez-en un autre.'}elseif($script:AutoMoveError){[string]$script:AutoMoveError}`
        elseif(-not [bool]$ChkRename.IsChecked -and -not [bool]$ChkMove.IsChecked){'Ni renommage ni déplacement demandé : voir Options.'}`
        elseif([bool]$ChkRename.IsChecked -and -not $CbName.SelectedItem){'Aucun nom proposé pour ce service.'}else{''}
    return Get-PestoPrimaryStep -Computer $computer -Busy $busy -Blocked $blocked -Loaded $loaded `
        -FormReady ([bool]$BtnAdd.IsEnabled) -ResumeMove ([bool]$script:DirectResumePlan) `
        -Rename ([bool]$ChkRename.IsChecked) -ReadOnly ([bool]$script:PestoReadOnly) -Missing $missing `
        -BlockedHint $blockedHint -BlockedAction $blockedAction -BlockedLabel $blockedLabel
}

function Invoke-PestoPrimaryAction {
    param($Sender,$EventArgs)
    try{
        # Recalcul au clic : ne jamais exécuter selon un Tag ou un libellé périmé.
        $step=Get-PestoPrimaryContext
        if(-not $step.Enabled){Update-PestoSuiteUI;return}
        switch($step.Action){
            'Read' {Invoke-PestoUxReadComputer $Sender $EventArgs}
            'ReviewJoin' {Invoke-PestoJoinReviewClick $Sender $EventArgs;Update-AddButton;Update-PestoSuiteUI}
            'ReviewDirect' {Show-PestoPostState -Mode Direct;Update-AddButton;Update-PestoSuiteUI}
            'Interventions' {Show-PestoInterventions;Update-AddButton;Update-PestoSuiteUI}
            'Prepare' {
                $control=if(-not $CbType.SelectedItem){$CbType}elseif(-not $CbOrg.SelectedItem){$CbOrg}`
                    elseif(-not $CbSite.SelectedItem){$CbSite}elseif(([string]$CbService.Text) -notmatch '^[A-Za-z0-9]{3}$'){$CbService}`
                    elseif(-not $ChkRename.IsChecked -and -not $ChkMove.IsChecked){$ChkRename}else{$CbName}
                if($control){$control.BringIntoView();[void]$control.Focus()}
                $script:SuiteUI.SuiteDirectHint.Text=if($UxAddHint.Text){[string]$UxAddHint.Text}else{$step.Hint}
            }
            'Execute' {Start-PestoDirectPreflight -Execute}
        }
    }catch{Show-PestoUsefulError -Title 'Préparation non lancée' -Message $_.Exception.Message -Stage 'Parcours unitaire' -MutationPossible $false}
}
