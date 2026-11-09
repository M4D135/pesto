#requires -Version 5.1
# Pagination, choix de candidats et contrôle explicite. Aucun accès réseau pendant la saisie.

function Add-PestoPerformanceSample {
    param([string]$Name,[long]$Milliseconds,[long]$Count=0,
        [ValidateSet('Computation','Worker')][string]$Kind='Computation',
        [ValidateSet('Returned','Faulted','Cancelled','Timeout','MonitorFault')][string]$State='Returned',
        [long]$WaitMilliseconds=0,[long]$WorkMilliseconds=0)
    if($Name -notmatch '^[A-Za-z][A-Za-z0-9_.-]{0,79}$'){throw 'Nom de mesure invalide. Aucun identifiant de cible accepté.'}
    foreach($n in @($Milliseconds,$Count,$WaitMilliseconds,$WorkMilliseconds)){if($n -lt 0){throw 'Mesure négative refusée.'}}
    if($Milliseconds -gt 86400000 -or $WaitMilliseconds -gt 86400000 -or $WorkMilliseconds -gt 86400000){throw 'Durée hors borne de mesure.'}
    if(-not $script:PestoPerformance){$script:PestoPerformance=[Collections.Generic.List[object]]::new()}

    # Horloge injectable pour tests, sinon UtcNow
    $now = if ($script:PestoPerfClock) { & $script:PestoPerfClock } else { [DateTime]::UtcNow }
    $shouldLog = $false
    if ($Kind -eq 'Worker') {
        if (-not $script:PestoPerfLastLog) { $script:PestoPerfLastLog = @{} }
        $key = "$Name|$Kind"
        $last = $script:PestoPerfLastLog[$key]
        if (-not $last -or ($now - $last).TotalSeconds -ge 1) {
            $shouldLog = $true
            $script:PestoPerfLastLog[$key] = $now
        }
    }

    $sample = [pscustomobject]@{Operation=$Name;Kind=$Kind;State=$State;Milliseconds=$Milliseconds;
        WaitMilliseconds=$WaitMilliseconds;WorkMilliseconds=$WorkMilliseconds;Count=$Count;Utc=$now.ToString('o')}

    $script:PestoPerformance.Add($sample)
    while($script:PestoPerformance.Count -gt 200){$script:PestoPerformance.RemoveAt(0)}

    if ($shouldLog) {
        $evt = New-PestoStructuredEvent -Message "Perf: $Name" -Level 'INFO' -Context 'Performance'
        $evt | Add-Member -NotePropertyName 'Kind' -NotePropertyValue 'perf' -Force
        $evt | Add-Member -NotePropertyName 'Operation' -NotePropertyValue $Name -Force
        $evt | Add-Member -NotePropertyName 'State' -NotePropertyValue $State -Force
        $evt | Add-Member -NotePropertyName 'Ms' -NotePropertyValue $Milliseconds -Force
        $evt | Add-Member -NotePropertyName 'WaitMs' -NotePropertyValue $WaitMilliseconds -Force
        $evt | Add-Member -NotePropertyName 'WorkMs' -NotePropertyValue $WorkMilliseconds -Force
        $evt | Add-Member -NotePropertyName 'Count' -NotePropertyValue $Count -Force
        $evt | Add-Member -NotePropertyName 'DC' -NotePropertyValue ([string]$script:DC) -Force

        [void](Write-PestoStructuredEvent -Event $evt)
    }
}

function Get-PestoPerformanceSummary {
    param([object[]]$Samples)
    if(@($Samples).Count -gt 200){throw 'Trop de mesures locales.'}
    foreach($group in @($Samples|Group-Object Operation,Kind)){
        $rows=@($group.Group);if(-not $rows.Count){continue}
        $durations=@($rows|ForEach-Object{[long]$_.Milliseconds}|Sort-Object)
        $p95=[Math]::Max(0,[int][Math]::Ceiling(0.95*$durations.Count)-1)
        [pscustomobject]@{Operation=$rows[0].Operation;Nature=$rows[0].Kind;Echantillons=$rows.Count;
            MoyenneMs=[Math]::Round(($durations|Measure-Object -Average).Average,1);P95Ms=$durations[$p95];MaximumMs=$durations[-1];
            AttenteMoyenneMs=[Math]::Round(($rows|Measure-Object WaitMilliseconds -Average).Average,1);
            Retours=@($rows|Where-Object State -eq 'Returned').Count;Erreurs=@($rows|Where-Object State -eq 'Faulted').Count;
            Delais=@($rows|Where-Object State -eq 'Timeout').Count;Annulations=@($rows|Where-Object State -eq 'Cancelled').Count;
            ErreursSurveillance=@($rows|Where-Object State -eq 'MonitorFault').Count}
    }
}

function Update-PestoNamesPageControls {
    param($Result)
    if(-not $script:NamesExtras){return}
    $ui=$script:NamesExtras
    $ui.NmPrevPage.IsEnabled=([long]$Result.Offset -gt 0)
    $ui.NmNextPage.IsEnabled=[bool]$Result.HasNext
    $page=[int]([long]$Result.Offset/[int]$Result.PageSize)+1
    $pages=[Math]::Max(1,[int][Math]::Ceiling([double]$Result.Total/[int]$Result.PageSize))
    $ui.NmPageLabel.Text="Page $page / $pages · 250 lignes maximum"
    $old=[string]$ui.NmSuggestions.SelectedItem.Nom
    $ui.NmSuggestions.ItemsSource=@($Result.Suggestions)
    $retained=@($Result.Suggestions|Where-Object{$_.Nom -ceq $old})
    if($retained.Count){$ui.NmSuggestions.SelectedItem=$retained[0]}elseif(@($Result.Suggestions).Count){$ui.NmSuggestions.SelectedIndex=0}
    $ui.NmCheckResult.Text='Choisissez un nom, puis vérifiez-le sur le contrôleur du domaine.'
    $script:NmVerifiedCandidate=$null
}

function Get-PestoSelectedCandidate {
    if(-not $script:NmViewReady){throw 'Attendez la fin du calcul.'}
    $selected=$NmGrid.SelectedItem
    if(-not $selected -and $script:NamesExtras){$selected=$script:NamesExtras.NmSuggestions.SelectedItem}
    if(-not $selected){throw 'Sélectionnez une ligne ou un des candidats proposés.'}
    if($selected.InAD -or ($selected.Reserved -and -not $selected.OwnReservation)){throw 'Ce nom est occupé ou déjà préparé.'}
    if(-not(Test-PestoGeneratedComputerName ([string]$selected.Nom))){throw 'Le nom sélectionné est invalide.'}
    return [string]$selected.Nom
}

function Invoke-PestoNameCheckWorker {
    param($Request,$Source)
    $ErrorActionPreference='Stop'
    . ([scriptblock]::Create($Source))
    if(-not(ConvertTo-PestoNameParts $Request.Name $Request.Prefix)){throw 'Candidat invalide.'}
    Import-PestoADModule -ADModulePath $Request.ADModulePath
    $adp=@{Server=[string]$Request.DC;ErrorAction='Stop'}
    if($Request.Credential){$adp.Credential=$Request.Credential}
    $name=[string]$Request.Name
    # Les valeurs sont validées avant insertion dans le filtre, sur tout le domaine.
    $domain=Get-ADDomain -Identity $Request.Domain @adp
    $found=@(Get-ADComputer -SearchBase $domain.DistinguishedName -SearchScope Subtree -LDAPFilter "(|(name=$name)(sAMAccountName=$name`$)(dNSHostName=$name.$($Request.Domain)))" -ResultSetSize 2 @adp)
    return [pscustomobject]@{Name=$name;Free=($found.Count -eq 0);Utc=[DateTime]::UtcNow.ToString('o');DC=$Request.DC;Generation=$Request.Generation}
}

function Complete-PestoNameCheck {
    param($Result,$Context,$Failure)
    $ui=$script:NamesExtras;if(-not $ui){return}
    $ui.NmVerifyCandidate.IsEnabled=$true
    if($Context.Generation -ne $script:NmViewGeneration -or -not $script:NmViewReady){return}
    if($Failure){$ui.NmCheckResult.Text='Vérification impossible : '+(Protect-PestoLogText $Failure.Exception.Message);return}
    if(-not $Result -or $Result.Name -cne $Context.Name -or $Result.Free -isnot [bool]){$ui.NmCheckResult.Text='Réponse invalide. Aucun nom validé.';return}
    $script:NmVerifiedCandidate=$Result
    $ui.NmCheckResult.Text=if($Result.Free){$Result.Name+' : libre à '+([DateTime]::Parse($Result.Utc).ToLocalTime().ToString('HH:mm:ss'))+' sur '+$Result.DC+'. Pas de réservation AD.'}else{$Result.Name+' : déjà présent dans le domaine.'}
}

function Invoke-PestoNamesPageCommand {
    param($Sender,$EventArgs)
    $ui=$script:NamesExtras
    try{
        switch($Sender.Name){
            'NmSharedRegistry' {Show-PestoSharedNameRegistry;return}
            'NmPrevPage' {if($script:NmViewReady){$script:NmPageOffset=[Math]::Max(0,[long]$script:NmPageOffset-250);Update-NameGrid};return}
            'NmNextPage' {if($script:NmViewReady -and $script:NmPageResult.HasNext){$script:NmPageOffset=[long]$script:NmPageOffset+250;Update-NameGrid};return}
            'NmStrategy' {$script:NmStrategy=if($ui.NmStrategy.SelectedIndex -eq 1){'AfterLast'}else{'FirstGap'};if($script:NmViewReady){Update-NameGrid};return}
            'NmAddService' {
                $service=([string]$ui.NmServiceInput.Text).Trim().ToUpperInvariant()
                if($service -notmatch (Get-PestoFacetPattern Service)){throw 'Saisissez un code service de trois caractères.'}
                $script:NmEquipes=@(@($script:NmEquipes)+@($service)|Sort-Object -Unique)
                $script:SuspendNm=$true
                try{if(-not $NmCmbEquipe.Items.Contains($service)){[void]$NmCmbEquipe.Items.Add($service)};$NmCmbEquipe.SelectedItem=$service}finally{$script:SuspendNm=$false}
                Update-NameGrid;return
            }
            'NmVerifyCandidate' {
                $name=Get-PestoSelectedCandidate
                $context=[pscustomobject]@{Name=$name;Generation=$script:NmViewGeneration}
                $script:NmVerifiedCandidate=$null;$ui.NmCheckResult.Text='Lecture du domaine en cours…'
                if($script:GUI){Complete-PestoNameCheck -Result ([pscustomobject]@{Name=$name;Free=$true;Utc=[DateTime]::UtcNow.ToString('o');DC='DÉMO : pas de contrôleur'}) -Context $context;return}
                $ui.NmVerifyCandidate.IsEnabled=$false
                $req=[pscustomobject]@{Name=$name;Prefix=$script:PREFIXE;Domain=$script:DOMAINE;DC=$script:DC;Generation=$script:NmViewGeneration;Credential=$script:cred;ADModulePath=(Join-Path $BasePath 'ActiveDirectory.psd1')}
                $source=(Get-PestoADLoaderSource)+"`nfunction ConvertTo-PestoNameParts {`n"+(Get-Command ConvertTo-PestoNameParts -CommandType Function).Definition+"`n}"
                [void](Start-PestoAsyncOperation -Name 'NameCandidateCheck' -ScriptBlock ${function:Invoke-PestoNameCheckWorker} -ArgumentList @($req,$source) -Replace -TimeoutSec 30 -CallbackContext $context -OnSuccess {param($r,$c)Complete-PestoNameCheck -Result $r -Context $c} -OnError {param($e,$c)Complete-PestoNameCheck -Failure $e -Context $c})
                return
            }
            'NmUseCandidate' {
                $name=Get-PestoSelectedCandidate;$parts=ConvertTo-PestoNameParts $name $script:PREFIXE
                if($script:Running -or $script:DirectBusy -or $script:JoinBusy -or $script:PreflightRunning){throw 'Un traitement est actif. Le brouillon ne peut pas être modifié.'}
                if(-not $script:INDOMAIN){
                    $j=$script:JoinUI
                    if(-not $j -or $script:JoinLocked -or $script:PestoReadOnly){throw 'La page de jonction n’’est pas disponible.'}
                    if(-not $script:PRD){throw "La configuration impose un nom de préproduction. Utilisez le générateur dédié dans $(Get-PestoUxNom 'PageJonction')."}
                    if(-not $j.Org.SelectedItem){throw 'Choisissez d’’abord l’’organisme dans Ajouter au domaine.'}
                    $sites=@($j.Site.Items|Where-Object{(Get-SiteTag ([string]$_)) -ceq $parts.Site})
                    if($sites.Count -ne 1){throw 'Site cible non unique dans le formulaire de jonction.'}
                    $j.Type.SelectedItem=$parts.Label;$j.Site.SelectedItem=$sites[0];$j.Service.Text=$parts.Service
                    if(-not $j.Name.Items.Contains($name)){[void]$j.Name.Items.Add($name)}
                    $j.Name.SelectedItem=$name;$script:JoinCheckedKey='';Set-PestoUxPage 'Join';Update-PestoJoinUI
                    return
                }
                if(-not $CbOrg.SelectedItem -or -not $CbSite.IsEnabled){throw "Lisez d'abord la machine dans $(Get-PestoUxNom 'PagePoste'), puis revenez utiliser ce nom."}
                $found=@($CbSite.Items|Where-Object{(Get-SiteTag ([string]$_)) -ceq $parts.Site})
                if($found.Count -ne 1){throw 'Le code site ne correspond pas à une destination unique dans ce formulaire.'}
                Set-PestoSuiteMode 'Single'
                $CbSite.SelectedItem=$found[0];$CbService.Text=$parts.Service;$CbType.SelectedItem=$parts.Label
                # Le générateur local valide le candidat avant de l'insérer dans le choix.
                if(-not $CbName.Items.Contains($name)){[void]$CbName.Items.Add($name)}
                $CbName.SelectedItem=$name;$script:DirectCheckedKey=''
                Update-AddButton;Update-PestoSuiteUI
                Add-LogLine 'Nom transféré au brouillon. Contrôle AD et confirmation requis avant exécution.' 'info';return
            }
        }
    }catch{if($ui){$ui.NmCheckResult.Text=Protect-PestoLogText $_.Exception.Message}else{Show-MsgWarning $_.Exception.Message}}
}

function Initialize-PestoNamesPageUI {
    $script:NmStrategy='FirstGap';$script:NmPageOffset=0
    $script:NamesExtras=@{}
    foreach($name in @('NmPrevPage','NmNextPage','NmPageLabel','NmSuggestions','NmStrategy','NmVerifyCandidate','NmUseCandidate','NmServiceInput','NmAddService','NmCheckResult','NmOtherNames','NmSharedRegistry')){
        $script:NamesExtras[$name]=$Win.FindName($name)
    }
    foreach($name in @('NmPrevPage','NmNextPage','NmVerifyCandidate','NmUseCandidate','NmAddService','NmSharedRegistry')){
        $script:NamesExtras[$name].Add_Click([Windows.RoutedEventHandler]${function:Invoke-PestoNamesPageCommand})
    }
    foreach($n in @('NmHoldCandidates','NmReleaseCandidate')){$Win.FindName($n).Add_Click([Windows.RoutedEventHandler]${function:Invoke-PestoNameReservationCommand})}
    foreach($name in @('BtnOtherName','NmOtherNames')){$Win.FindName($name).Add_Click([Windows.RoutedEventHandler]${function:Invoke-PestoOtherNameClick})}
    $script:NamesExtras.NmStrategy.Add_SelectionChanged([Windows.Controls.SelectionChangedEventHandler]${function:Invoke-PestoNamesPageCommand})
    Update-PestoSharedRegistryButton
}

function Read-PestoNameReservations {
    $text=if($script:GUI -or $script:SIM){$script:PestoNameReservationMemory}else{Get-PestoAppearanceValue -Name 'Reservations'}
    if(-not $text){return @()}
    if($text.Length -gt 16384){throw 'Réservations personnelles trop volumineuses.'}
    $r=$text|ConvertFrom-Json -ErrorAction Stop
    Assert-PestoClosedObject $r @('Schema','Domain','Names','CreatedUtc') @('Schema','Domain','Names')
    if($r.Schema -isnot [int] -or $r.Schema -ne 1 -or $r.Names -is [string] -or @($r.Names).Count -gt 64){throw 'Réservations personnelles invalides.'}
    if($r.Domain -ine $script:DOMAINE){return @()}
    foreach($name in @($r.Names)){if($name -isnot [string] -or -not(ConvertTo-PestoNameParts $name $script:PREFIXE)){throw 'Nom retenu invalide.'}}
    return @($r.Names|Sort-Object -Unique)
}
function Save-PestoNameReservations {
    param([string[]]$Names)
    $names=@($Names|Sort-Object -Unique)
    if($names.Count -gt 64){throw '64 noms maximum dans votre préparation personnelle.'}
    foreach($n in $names){if(-not(ConvertTo-PestoNameParts $n $script:PREFIXE)){throw 'Nom non conforme.'}}
    $text=[pscustomobject]@{Schema=1;Domain=$script:DOMAINE;Names=$names;CreatedUtc=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json -Compress
    if($script:GUI -or $script:SIM){$script:PestoNameReservationMemory=$text}else{Set-PestoAppearanceValue -Name 'Reservations' -Value $text}
}
function Invoke-PestoNameReservationCommand {
    param($Sender,$EventArgs)
    try{
        if(-not $script:NmViewReady){throw 'Attendez la fin du calcul.'}
        $names=@(Read-PestoNameReservations)
        if($Sender.Name -eq 'NmHoldCandidates'){
            $candidates=@($script:NmPageResult.Suggestions|Where-Object{-not $_.InAD -and -not $_.Reserved}|ForEach-Object{[string]$_.Nom})
            if(-not $candidates.Count){throw 'Choisissez un site et un service pour obtenir cinq propositions.'}
            if(-not(Confirm-YesNo -Msg (($candidates -join "`n")+"`nRetenir ces noms dans votre préparation personnelle ? Ce choix ne réserve rien dans AD ni chez les autres techniciens.") -Confirm $true)){return}
            Save-PestoNameReservations -Names @($names+$candidates)
        }else{
            $row=$NmGrid.SelectedItem
            if(-not $row -or $row.Nom -notin $names){throw 'Choisissez une ligne retenue pour vous dans le filtre Réservés.'}
            Save-PestoNameReservations -Names @($names|Where-Object{$_ -cne $row.Nom})
        }
        $script:NmPageOffset=0;Update-NameGrid
    }catch{Show-MsgWarning $_.Exception.Message}
}


function Invalidate-PestoNameInventory {
    param([string]$Reason='Une intervention a pu modifier le parc. Actualisez avant de choisir un autre nom.')
    if($script:GUI -or $script:SIM){return}
    $script:InventoryLoaded=$false;$script:NmUsedSrc=$null;$script:NmUsedIndex=$null
    # Garder tous les noms déjà observés pendant les relectures ciblées : une
    # réponse sur un autre site ne doit pas rendre un nom récemment occupé libre.
    $script:AffectedNameSnapshot=@($script:ComputersNoms)
    # Les recherches ciblées de site sont relues au prochain choix de site.
    $script:SiteLookupCache=@{};$script:KnownComputersCache=$null;$script:SiteServiceCache=@{}
    $script:NmViewGeneration=[int]$script:NmViewGeneration+1
    $script:NmVerifiedCandidate=$null;$script:NmViewReady=$false;$script:NmNeedsDirectoryRetry=$true
    if($script:NmCalculationCancel){$script:NmCalculationCancel.Cancelled=$true}
    if($NmLoadingPanel){Set-PestoNamesViewState -State NotLoaded -Title 'Inventaire à actualiser' -Detail $Reason}
}

###############################################################################
#  Registre partagé des réservations de noms (08/10/2026, demande de David)
#  Plusieurs Pesto sur plusieurs postes : le nom proposé est réservé dans le
#  dossier de coordination (POLICY.CoordinationRoot) dès qu'il s'affiche ; les
#  autres Pesto ne le proposent plus. Création exclusive d'un fichier par nom
#  (une seule machine peut le créer), durée NameReservationMinutes, reprise d'une
#  réservation expirée sous verrou exclusif. Toutes les écritures passent par un
#  worker : un partage lent ou coupé ne fige jamais l'interface. Sans dossier
#  configuré, rien ne change ; la revérification AD avant l'opération demeure.
###############################################################################

$script:PestoSharedNameWorker = {
    param($Request)
    Set-StrictMode -Off
    $ErrorActionPreference = 'Stop'
    $root=[string]$Request.Root
    if(-not $root -or $root.Length -gt 240 -or $root -match '[\x00-\x1f"*?]' -or -not [IO.Path]::IsPathRooted($root)){throw 'Chemin du registre partagé invalide.'}
    $root=[IO.Path]::GetFullPath($root).TrimEnd('\')
    $marker=[IO.Path]::Combine($root,'pesto-coordination.json')
    $dir=[IO.Path]::Combine($root,'reservations')
    # Poste hors domaine : le jeton du compte local n'ouvre pas un partage du domaine. Si le registre est illisible avec ce
    # jeton, connexion au partage avec le compte AD saisi dans Pesto, sans lettre de lecteur ni mot de passe écrit. Cette
    # connexion vaut pour la session Windows : Pesto la ferme à sa fermeture (Close-PestoShareConnections).
    $connected=''
    $unc=[regex]::Match($root,'^\\\\([^\\]+)\\([^\\]+)')
    if($null -ne $Request.Credential -and $unc.Success -and -not [IO.File]::Exists($marker) -and -not [IO.Directory]::Exists($root)){
        $share='\\'+$unc.Groups[1].Value+'\'+$unc.Groups[2].Value
        if(-not [IO.Directory]::Exists($share)){
            try{[void](New-PSDrive -Name ('PestoReg'+[Guid]::NewGuid().ToString('N').Substring(0,8)) -PSProvider FileSystem -Root $share -Credential $Request.Credential -Scope Global -ErrorAction Stop)}
            catch{throw ('Partage du registre inaccessible avec le compte '+[string]$Request.Credential.UserName+' : '+$_.Exception.Message)}
            $connected=$share
        }
    }
    $utf8=[Text.UTF8Encoding]::new($false)
    if($Request.Mode -eq 'Prepare'){
        # Prépare un dossier existant (ou à créer sous un parent existant) ; ne crée jamais de partage ni de droits.
        $parent=[IO.Path]::GetDirectoryName($root)
        if(-not [IO.Directory]::Exists($root)){
            if(-not $parent -or -not [IO.Directory]::Exists($parent)){throw 'Le dossier parent n''existe pas. Pesto ne crée aucun partage.'}
            [void][IO.Directory]::CreateDirectory($root)
        }
        if([IO.File]::Exists($marker)){
            $m=[IO.File]::ReadAllText($marker,[Text.Encoding]::UTF8)|ConvertFrom-Json
            if([int]$m.Schema -ne 1 -or [string]$m.Domain -ine [string]$Request.Domain -or [string]$m.Purpose -cne 'PestoCoordination'){throw 'Ce dossier contient le registre d''un autre domaine.'}
        }else{
            $json=([ordered]@{Schema=1;Domain=[string]$Request.Domain;Purpose='PestoCoordination'}|ConvertTo-Json -Compress)
            [IO.File]::WriteAllText($marker,$json,$utf8)
        }
        foreach($d in @([IO.Path]::Combine($root,'locks'),$dir)){if(-not [IO.Directory]::Exists($d)){[void][IO.Directory]::CreateDirectory($d)}}
    }
    if(-not [IO.File]::Exists($marker)){throw 'Registre partagé non préparé (pesto-coordination.json absent). Utilisez « Préparer ce dossier » dans Paramètres.'}
    $m=[IO.File]::ReadAllText($marker,[Text.Encoding]::UTF8)|ConvertFrom-Json
    if([int]$m.Schema -ne 1 -or [string]$m.Domain -ine [string]$Request.Domain -or [string]$m.Purpose -cne 'PestoCoordination'){throw 'Ce registre partagé appartient à un autre domaine.'}
    if(-not [IO.Directory]::Exists($dir)){[void][IO.Directory]::CreateDirectory($dir)}
    $now=[DateTime]::UtcNow
    $owner=[string]$Request.Owner
    function Test-Active($e,[string]$path){
        # Réservation illisible ou sans date (poste arrêté pendant l'écriture) : active tant que le fichier a moins que la
        # durée de réservation, expirée ensuite.
        $exp=[DateTime]::MinValue
        if($e -and [DateTime]::TryParse([string]$e.ExpiresUtc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]'AdjustToUniversal, AssumeUniversal',[ref]$exp)){return ($exp -gt $now)}
        try{return (($now-[IO.File]::GetLastWriteTimeUtc($path)).TotalMinutes -lt [Math]::Max(5,[int]$Request.Minutes))}catch{return $true}
    }
    function New-Entry([string]$name){
        $minutes=[Math]::Max(5,[Math]::Min(240,[int]$Request.Minutes))
        return ([ordered]@{Schema=1;Name=$name;Domain=[string]$Request.Domain;Station=[string]$Request.Station;User=[string]$Request.User;Owner=$owner;
            Context=[string]$Request.Context;CreatedUtc=$now.ToString('o');ExpiresUtc=$now.AddMinutes($minutes).ToString('o')}|ConvertTo-Json -Compress)
    }
    $result=[ordered]@{Mode=[string]$Request.Mode;Name=[string]$Request.Name;State='';Holder='';HolderExpiresUtc='';Others=@();Count=0;Root=$root;Connected=$connected}
    switch([string]$Request.Mode){
        {$_ -in @('Snapshot','Test','Prepare')}{
            $others=[Collections.Generic.List[object]]::new()
            foreach($f in [IO.Directory]::GetFiles($dir,'*.json')){
                $e=$null;try{$e=[IO.File]::ReadAllText($f,[Text.Encoding]::UTF8)|ConvertFrom-Json}catch{$e=$null}
                $name=[IO.Path]::GetFileNameWithoutExtension($f).ToUpperInvariant()
                if((Test-Active $e $f) -and (-not $e -or [string]$e.Owner -ne $owner)){
                    $others.Add([pscustomobject]@{Name=$name;Station=[string]$e.Station;User=[string]$e.User;ExpiresUtc=[string]$e.ExpiresUtc})
                }
            }
            $result.Others=$others.ToArray();$result.Count=$others.Count
            if($_ -eq 'Test'){
                # Écriture d'essai : création exclusive puis suppression d'un fichier propre à ce test.
                $probe=[IO.Path]::Combine($dir,'_essai-'+[Guid]::NewGuid().ToString('N')+'.tmp')
                $s=[IO.File]::Open($probe,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);$s.Dispose();[IO.File]::Delete($probe)
            }
            $result.State='OK'
        }
        'Reserve'{
            $name=([string]$Request.Name).ToUpperInvariant()
            if($name -notmatch '^[A-Z0-9-]{1,15}$'){throw 'Nom à réserver invalide.'}
            $path=[IO.Path]::Combine($dir,$name+'.json')
            $bytes=$utf8.GetBytes((New-Entry $name))
            $created=$false
            try{
                $s=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
                try{$s.Write($bytes,0,$bytes.Length);$s.Flush()}finally{$s.Dispose()}
                $created=$true;$result.State='Reserved'
            }catch{
                if(-not [IO.File]::Exists($path)){throw}
            }
            if(-not $created){
                # Déjà présent : à nous (renouvellement), expiré (reprise) ou détenu par un autre poste. Lecture et réécriture
                # sous verrou exclusif : deux postes ne peuvent pas reprendre la même réservation expirée.
                $s=$null
                try{$s=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}
                catch{$result.State='Held';$result.Holder='autre poste (réservation en cours d''écriture)'}
                if($s){
                    try{
                        $buffer=New-Object byte[] ([int][Math]::Min(8192,$s.Length))
                        $read=0;while($read -lt $buffer.Length){$n=$s.Read($buffer,$read,$buffer.Length-$read);if($n -le 0){break};$read+=$n}
                        $e=$null;try{$e=$utf8.GetString($buffer,0,$read)|ConvertFrom-Json}catch{$e=$null}
                        if(($e -and [string]$e.Owner -eq $owner) -or -not (Test-Active $e $path)){
                            $s.SetLength(0);$s.Position=0;$s.Write($bytes,0,$bytes.Length);$s.Flush()
                            $result.State=if($e -and [string]$e.Owner -eq $owner){'Renewed'}else{'Reserved'}
                        }else{
                            $result.State='Held';$result.Holder=(([string]$e.Station+' · '+[string]$e.User).Trim(' ·'));$result.HolderExpiresUtc=[string]$e.ExpiresUtc
                        }
                    }finally{$s.Dispose()}
                }
            }
        }
        'Release'{
            $released=[Collections.Generic.List[string]]::new()
            foreach($n in @($Request.Names)){
                $name=([string]$n).ToUpperInvariant()
                if($name -notmatch '^[A-Z0-9-]{1,15}$'){continue}
                $path=[IO.Path]::Combine($dir,$name+'.json')
                if(-not [IO.File]::Exists($path)){continue}
                # Garder la même poignée entre lecture du propriétaire et suppression. Sinon un autre poste
                # peut reprendre une réservation expirée dans cet intervalle, puis perdre son propre fichier.
                # Delete autorise la suppression sous Windows ; aucun autre lecteur/rédacteur ne peut ouvrir
                # cette réservation avant la fermeture. Une réservation occupée reste conservée pour expirer.
                $s=$null
                try{
                    $s=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Delete)
                    if($s.Length -gt 8192){continue}
                    $buffer=New-Object byte[] ([int]$s.Length)
                    $read=0;while($read -lt $buffer.Length){$n=$s.Read($buffer,$read,$buffer.Length-$read);if($n -le 0){break};$read+=$n}
                    $e=$null;try{$e=$utf8.GetString($buffer,0,$read)|ConvertFrom-Json}catch{$e=$null}
                    # Seules nos propres réservations sont retirées ; celles des autres expirent d'elles-mêmes.
                    if($e -and [string]$e.Owner -eq $owner){[IO.File]::Delete($path);$released.Add($name)}
                }catch{
                    # Ne jamais annoncer une libération si le propriétaire ou la suppression n'est pas établi.
                }finally{if($s){$s.Dispose()}}
            }
            $result.Others=$released.ToArray();$result.State='OK'
        }
        default{throw 'Opération de registre inconnue.'}
    }
    return [pscustomobject]$result
}

function Get-PestoSharedNameRegistrySource {
    <# T108 : source complète du worker de lecture. Un corps de fonction seul ne définit
       rien : chaque fonction est reenveloppée dans 'function NOM { ... }' avant d'être
       transmise au runspace. Assert-PestoPlainPath reste autonome (aucune dépendance). #>
    $sb=[Text.StringBuilder]::new()
    foreach($n in @('Assert-PestoPlainPath','Get-PestoSharedNameRegistrySnapshot')){
        $fn=Get-Command $n -CommandType Function -ErrorAction Stop
        [void]$sb.AppendLine('function '+$n+' {')
        [void]$sb.AppendLine($fn.Definition)
        [void]$sb.AppendLine('}')
    }
    return $sb.ToString()
}

$script:PestoSharedNameReader = {
    <# T108 : worker de lecture seule. Ne prend aucun verrou, ne crée rien, n'écrit rien.
       La source passée en 2e argument porte la fonction de lecture et le contrôle de liens. #>
    param($Request,$Source)
    Set-StrictMode -Off
    $ErrorActionPreference='Stop'
    if($Source){. ([scriptblock]::Create([string]$Source))}
    Get-PestoSharedNameRegistrySnapshot -Root ([string]$Request.Root) -Domain ([string]$Request.Domain)
}

function Get-PestoSharedNameRegistrySnapshot {
    <# T108 : lecture seule du registre partagé pour la vue « Registre partagé ».
       Aucune création de dossier, aucun verrou, aucun fichier d'essai, aucune écriture.
       Les liens/jonctions sont refusés par Assert-PestoPlainPath, la taille des fichiers
       et le nombre d'entrées sont bornés, et une troncature est signalée. #>
    param([ValidateNotNullOrEmpty()][string]$Root,[string]$Domain='',
          [ValidateRange(1,5000)][int]$MaxEntries=500,[ValidateRange(1,1048576)][int]$MaxFileBytes=8192,[AllowNull()]$Now=$null)
    function Read-PestoRegistryDocument {
        param([string]$Path,[int]$Limit)
        Assert-PestoPlainPath $Path
        $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
        try{
            $length=$stream.Length
            if($length -lt 1 -or $length -gt $Limit){throw 'Document de coordination vide ou trop volumineux.'}
            $buffer=New-Object byte[] ([int]$length);$offset=0
            while($offset -lt $length){$n=$stream.Read($buffer,$offset,[int]$length-$offset);if($n -le 0){throw 'Lecture de coordination incomplète.'};$offset+=$n}
            if($stream.Length -ne $length){throw 'Document modifié pendant sa lecture. Actualisez la vue.'}
            return ([Text.UTF8Encoding]::new($false,$true)).GetString($buffer).TrimStart([char]0xFEFF)|ConvertFrom-Json -ErrorAction Stop
        }finally{$stream.Dispose()}
    }
    $readUtc=[DateTime]::UtcNow
    if($null -eq $Now){$Now=$readUtc}
    $result=[ordered]@{Schema=1;Mode='Inspect';Root='';Domain='';Ok=$false;Error='';Entries=@();Count=0;Truncated=$false;Skipped=0;Files=0;ReadUtc=$readUtc.ToString('o')}
    try{
        $rootText=[string]$Root
        if($rootText.Length -gt 240 -or $rootText -match '[\x00-\x1f"*?]' -or -not [IO.Path]::IsPathRooted($rootText)){throw 'Chemin du registre partagé invalide.'}
        $root=[IO.Path]::GetFullPath($rootText).TrimEnd([char[]]@('\','/'))
        $result.Root=$root
        $domainText=[string]$Domain
        if($domainText.Length -gt 253 -or $domainText -match '[\x00-\x1f]'){throw 'Domaine attendu invalide.'}
        $result.Domain=$domainText
        if(-not [IO.Directory]::Exists($root)){throw 'Dossier du registre absent. La vue ne crée rien.'}
        Assert-PestoPlainPath $root
        $marker=[IO.Path]::Combine($root,'pesto-coordination.json')
        if(-not [IO.File]::Exists($marker)){throw 'Registre partagé non préparé (pesto-coordination.json absent).'}
        Assert-PestoPlainPath $marker
        if(([IO.FileInfo]::new($marker)).Length -gt 4096){throw 'Marqueur du registre trop volumineux.'}
        $m=Read-PestoRegistryDocument -Path $marker -Limit 4096
        if([int]$m.Schema -ne 1 -or [string]$m.Purpose -cne 'PestoCoordination'){throw 'Registre de coordination inconnu.'}
        if($domainText -and [string]$m.Domain -ine $domainText){throw 'Ce registre appartient à un autre domaine.'}
        if(-not $domainText){$domainText=[string]$m.Domain;$result.Domain=$domainText}
        if(-not $domainText -or $domainText.Length -gt 253 -or $domainText -notmatch '^[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$'){throw 'Domaine du marqueur invalide.'}
        $dir=[IO.Path]::Combine($root,'reservations')
        if(-not [IO.Directory]::Exists($dir)){$result.Ok=$true;return [pscustomobject]$result}
        Assert-PestoPlainPath $dir
        # Énumération paresseuse jusqu'à limite+1 : jamais tout le dossier matérialisé.
        $names=[Collections.Generic.List[string]]::new()
        foreach($f in [IO.Directory]::EnumerateFiles($dir,'*.json')){$names.Add($f);if($names.Count -gt $MaxEntries){break}}
        $result.Files=$names.Count;$result.Truncated=($names.Count -gt $MaxEntries)
        $files=@($names.ToArray());[Array]::Sort($files,[StringComparer]::OrdinalIgnoreCase)
        if($files.Count -gt $MaxEntries){$files=@($files[0..($MaxEntries-1)])}
        $utf8=[Text.UTF8Encoding]::new($false,$true)
        $entries=[Collections.Generic.List[object]]::new()
        foreach($f in $files){
            try{
                Assert-PestoPlainPath $f
                $entryJson=Read-PestoRegistryDocument -Path $f -Limit $MaxFileBytes
                if([int]$entryJson.Schema -ne 1){throw 'Schéma de réservation inconnu.'}
                if($domainText -and [string]$entryJson.Domain -ine $domainText){throw 'Réservation d''un autre domaine.'}
                $name=[IO.Path]::GetFileNameWithoutExtension($f).ToUpperInvariant()
                if($name -notmatch '^[A-Z0-9][A-Z0-9-]{0,14}$' -or ([string]$entryJson.Name).ToUpperInvariant() -cne $name){throw 'Le nom interne ne correspond pas au fichier.'}
                $exp=[DateTime]::MinValue
                $expiresText=if($entryJson.ExpiresUtc -is [DateTime]){$entryJson.ExpiresUtc.ToUniversalTime().ToString('o')}else{[string]$entryJson.ExpiresUtc}
                $hasExpiry=([DateTime]::TryParse($expiresText,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]'AdjustToUniversal, AssumeUniversal',[ref]$exp))
                $created=[DateTime]::MinValue
                $createdText=if($entryJson.CreatedUtc -is [DateTime]){$entryJson.CreatedUtc.ToUniversalTime().ToString('o')}else{[string]$entryJson.CreatedUtc}
                $hasCreation=[DateTime]::TryParse($createdText,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]'AdjustToUniversal, AssumeUniversal',[ref]$created)
                $state=if($hasExpiry -and $hasCreation -and $exp -gt $created -and $created -le $Now){if($exp -gt $Now){'Active'}else{'Expirée'}}else{'Inconnue'}
                foreach($field in @('Station','User','Context')){if(([string]$entryJson.$field).Length -gt 256 -or [string]$entryJson.$field -match '[\x00-\x1f\x7f]'){throw 'Métadonnée de réservation invalide.'}}
                $age=[int][Math]::Round(($Now-[IO.File]::GetLastWriteTimeUtc($f)).TotalMinutes)
                $entries.Add([pscustomobject]@{Name=$name;Station=[string]$entryJson.Station;User=[string]$entryJson.User;Context=[string]$entryJson.Context;
                    CreatedUtc=$createdText;ExpiresUtc=$expiresText;State=$state;AgeMinutes=$age})
            }catch{$result.Skipped=[int]$result.Skipped+1}
        }
        $result.Entries=@($entries|Sort-Object Name);$result.Count=$result.Entries.Count;$result.Ok=$true
    }catch{$result.Ok=$false;$msg=[string]$_.Exception.Message;if($msg.Length -gt 600){$msg=$msg.Substring(0,600)};$result.Error=$msg}
    return [pscustomobject]$result
}

function ConvertTo-PestoSharedNameRegistryLines {
    <# T108 : rendu texte de la vue, partagé par l'interface et les tests. Une lecture en
       échec affiche l'erreur, jamais un état vide trompeur. #>
    param($Snapshot)
    $lines=[Collections.Generic.List[string]]::new()
    if(-not $Snapshot){$lines.Add('Lecture indisponible : aucune donnée reçue.');return $lines.ToArray()}
    if(-not [bool]$Snapshot.Ok){
        $lines.Add('Lecture du registre partagé impossible.')
        $lines.Add('Détail : '+[string]$Snapshot.Error)
        $lines.Add('Aucun état vide n''est annoncé : relancez la lecture ou vérifiez le dossier de coordination.')
        return $lines.ToArray()
    }
    $lines.Add('Dossier : '+[string]$Snapshot.Root)
    $lines.Add('Lecture UTC : '+[string]$Snapshot.ReadUtc)
    $filesText=if([bool]$Snapshot.Truncated){'au moins '+[string]$Snapshot.Files}else{[string]$Snapshot.Files}
    $summary='Réservations lues : '+[string]$Snapshot.Count+' sur '+$filesText+' fichier(s)'
    if([bool]$Snapshot.Truncated){$summary+=' · tronquée (limite d''entrées atteinte)'}
    if([int]$Snapshot.Skipped -gt 0){$summary+=' · '+[string]$Snapshot.Skipped+' entrée(s) ignorée(s) (lien, illisible, domaine ou nom incohérent, ou trop volumineuse)'}
    $lines.Add($summary)
    if([int]$Snapshot.Count -eq 0){$lines.Add('Aucune réservation lisible dans le dossier.')}
    foreach($entry in @($Snapshot.Entries)){
        $expires=if([string]$entry.ExpiresUtc){[string]$entry.ExpiresUtc}else{'inconnue'}
        $station=if([string]$entry.Station){[string]$entry.Station}else{'station inconnue'}
        $user=if([string]$entry.User){[string]$entry.User}else{'utilisateur inconnu'}
        $lines.Add(([string]$entry.Name+' · '+$station+' · '+$user+' · état '+[string]$entry.State+' · expire '+$expires+' · fichier il y a '+[string]$entry.AgeMinutes+' min'))
    }
    return $lines.ToArray()
}

function Complete-PestoSharedNameRegistry {
    param($Result,$Failure,[AllowNull()]$Context=$null)
    # Le contexte de lancement (racine, domaine, empreinte de configuration) revient dans le rappel :
    # une lecture dont la configuration a changé entre-temps est ignorée, jamais publiée.
    if($Context){
        $stale=$false
        try{
            $current=Get-PestoSharedNameSettings
            if(-not $current.Root){$stale=$true}
            elseif([string]$Context.Root -cne [string]$current.Root){$stale=$true}
            elseif([string]$Context.Domain -cne [string]$script:DOMAINE){$stale=$true}
            elseif([string]$Context.ConfigStamp -cne (Get-PestoConfigurationSignature $script:CFG)){$stale=$true}
        }catch{$stale=$true}
        if($stale){
            try{Add-LogLine 'Registre partagé (vue) : lecture ignorée (racine, domaine ou configuration modifiée pendant la lecture).' 'warn'}catch{}
            return
        }
    }
    if($Failure){
        $msg=if($Failure -is [Management.Automation.ErrorRecord]){$Failure.Exception.Message}else{[string]$Failure}
        $text='Lecture du registre partagé impossible.'+"`r`n"+'Détail : '+$msg+"`r`n"+'Aucune liste vide n''est affichée : réessayez après vérification du dossier de coordination.'
        try{Add-LogLine ('Registre partagé (vue) : lecture impossible — '+$msg) 'warn'}catch{}
        Show-MsgWarning $text
        return
    }
    $lines=ConvertTo-PestoSharedNameRegistryLines -Snapshot $Result
    Show-PestoTextReport 'Pesto · Registre partagé' ($lines -join "`r`n")
}

function Show-PestoSharedNameRegistry {
    <# T108 : vue « Registre partagé », lecture asynchrone bornée hors dispatcher. Jamais en démonstration. #>
    try{
        $settings=Get-PestoSharedNameSettings
        if(-not $settings.Root){Show-MsgInfo 'Registre partagé non configuré. Renseignez POLICY.CoordinationRoot dans Paramètres, puis préparez le dossier.';return}
        if($script:GUI -or $script:SIM){Show-MsgInfo 'La vue du registre partagé n''est pas disponible en démonstration ou simulation.';return}
        if(Test-PestoAsyncOperationRunning 'SharedNameRegistry'){return}
        $user=if($script:AuthUser){[string]$script:AuthUser}else{[string][Environment]::UserName}
        $request=[pscustomobject]@{Mode='Inspect';Root=[string]$settings.Root;Domain=[string]$script:DOMAINE;Station=[string]$env:COMPUTERNAME;User=$user;Name='';Names=@();Context='Inspect';Minutes=$settings.Minutes;Credential=$script:cred}
        $source=Get-PestoSharedNameRegistrySource
        $context=[pscustomobject]@{Root=[string]$settings.Root;Domain=[string]$script:DOMAINE;ConfigStamp=(Get-PestoConfigurationSignature $script:CFG)}
        $started=Start-PestoAsyncOperation -Name 'SharedNameRegistry' -ScriptBlock $script:PestoSharedNameReader -ArgumentList @($request,$source) -Replace -TimeoutSec 45 -CallbackContext $context `
            -OnSuccess {param($r,$c) Complete-PestoSharedNameRegistry -Result $r -Context $c} -OnError {param($e,$c) Complete-PestoSharedNameRegistry -Failure $e -Context $c}
        if(-not $started){Show-MsgWarning 'Lecture du registre partagé déjà en cours.'}
    }catch{Show-MsgWarning $_.Exception.Message}
}

function Update-PestoSharedRegistryButton {
    <# Le bouton n'est actif que si un dossier de coordination est configuré, jamais en démonstration ou simulation. #>
    try{
        $button=if($script:NamesExtras){$script:NamesExtras['NmSharedRegistry']}else{$null}
        if($button){$button.IsEnabled=(-not $script:GUI -and -not $script:SIM -and [bool](Get-PestoSharedNameSettings).Root)}
    }catch{}
}

function Get-PestoSharedNameSettings {
    <# Réglages du registre partagé lus dans POLICY ; registre inactif si le chemin est vide ou en démonstration. #>
    $p=ConvertTo-PestoPolicy $script:CFG.POLICY
    $root=if($p -and -not $script:GUI){[string]$p.CoordinationRoot}else{''}
    return [pscustomobject]@{Root=$root;Minutes=$(if($p){[int]$p.NameReservationMinutes}else{15});Random=$(if($p){[bool]$p.RandomNameEnabled}else{$true});ReserveInAD=$(if($p){[bool]$p.ReserveNamesInAD}else{$false})}
}

function Test-PestoNameReservedByOther {
    <# Vrai si un autre Pesto détient ce nom dans le registre partagé (dernier relevé). #>
    param([string]$Name)
    if(-not $Name -or -not $script:SharedNameOthers){return $false}
    $e=$script:SharedNameOthers[$Name.ToUpperInvariant()]
    if(-not $e){return $false}
    $exp=[DateTime]::MinValue
    if([DateTime]::TryParse([string]$e.ExpiresUtc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]'AdjustToUniversal, AssumeUniversal',[ref]$exp) -and $exp -le [DateTime]::UtcNow){return $false}
    return $true
}

function Get-PestoInitialNameIndex {
    <# Tirage uniforme sur tous les candidats déjà filtrés ; générateur système du socle commun. #>
    param([int]$Count)
    if($Count -lt 1){return -1}
    if($Count -eq 1 -or -not (Get-PestoSharedNameSettings).Random){return 0}
    return [M4D.Admin.Common.Core.RandomSelection]::NextIndex($Count)
}

function Get-PestoOtherNameIndex {
    param([int]$Count,[int]$Current=-1)
    if($Count -lt 2){return $(if($Count -eq 1){0}else{-1})}
    if($Current -lt 0 -or $Current -ge $Count){return Get-PestoInitialNameIndex $Count}
    if(-not (Get-PestoSharedNameSettings).Random){return (($Current+1)%$Count)}
    $index=[M4D.Admin.Common.Core.RandomSelection]::NextIndex($Count-1)
    if($index -ge $Current){$index++}
    return $index
}

function Invoke-PestoOtherNameClick {
    param($Sender,$EventArgs)
    if($script:Running -or $script:PreflightRunning -or $script:DirectBusy -or $script:JoinBusy -or
       $script:DirectLocked -or $script:JoinLocked -or $script:MutationUncertain){return}
    if($Sender.Name -eq 'NmOtherNames'){
        if($script:NmViewReady){$script:NmSuggestionReset=$true;Update-NameGrid}
        return
    }
    if($Sender.Name -eq 'JnOtherName'){
        if(-not $script:JoinUI -or $script:INDOMAIN -or [bool]$script:JoinUI.Existing.IsChecked){return}
        $combo=$script:JoinUI.Name
    }else{$combo=$CbName}
    if(-not $combo -or -not $combo.IsEnabled -or $combo.Items.Count -lt 2){return}
    $combo.SelectedIndex=Get-PestoOtherNameIndex $combo.Items.Count $combo.SelectedIndex
    # SelectionChanged invalide le précontrôle ; ce bouton ne déclenche aucune opération AD.
}

function Start-PestoSharedNameOperation {
    param([string]$Mode,[string]$Name='',[string[]]$Names=@(),[string]$Context='',[string]$Root='')
    $settings=Get-PestoSharedNameSettings
    if(-not $Root){$Root=$settings.Root}
    if(-not $Root){return $false}
    if(-not $script:SharedNameOwner){$script:SharedNameOwner=[Guid]::NewGuid().ToString('N')}
    $user=if($script:AuthUser){[string]$script:AuthUser}else{[string][Environment]::UserName}
    $request=[pscustomobject]@{Mode=$Mode;Root=$Root;Domain=[string]$script:DOMAINE;Owner=$script:SharedNameOwner;Station=[string]$env:COMPUTERNAME;User=$user;
        Minutes=$settings.Minutes;Name=$Name;Names=@($Names);Context=$Context;Credential=$script:cred}
    $opName=if($Mode -eq 'Reserve'){'SharedNameReserve'+$Context}elseif($Mode -eq 'Release'){'SharedNameRelease'+[Guid]::NewGuid().ToString('N')}else{'SharedName'+$Mode}
    return (Start-PestoAsyncOperation -Name $opName -ScriptBlock $script:PestoSharedNameWorker -ArgumentList @($request) -Replace:($Mode -ne 'Release') -TimeoutSec 30 `
        -CallbackContext ([pscustomobject]@{Mode=$Mode;Name=$Name;Context=$Context;Names=@($Names)}) `
        -OnSuccess {param($r,$c) Complete-PestoSharedNameOperation -Result $r -Context $c} -OnError {param($e,$c) Complete-PestoSharedNameOperation -Failure $e -Context $c})
}

function Complete-PestoSharedNameOperation {
    param($Result,$Failure,$Context)
    if(-not $script:SharedNameOthers){$script:SharedNameOthers=@{}}
    if(-not $script:SharedNameMine){$script:SharedNameMine=@{}}
    if(-not $script:SharedNamePending){$script:SharedNamePending=@{}}
    if($Failure){
        $msg=if($Failure -is [Management.Automation.ErrorRecord]){$Failure.Exception.Message}else{[string]$Failure}
        $script:SharedNameStatus='Registre partagé indisponible : '+$msg
        if($Context.Mode -eq 'Reserve'){$script:SharedNamePending.Remove([string]$Context.Context)}
        if(-not $script:SharedNameWarned){$script:SharedNameWarned=$true;try{Add-LogLine ($script:SharedNameStatus+' Les noms restent revérifiés dans l''AD avant chaque opération.') 'warn'}catch{}}
        try{Write-Log $script:SharedNameStatus 'WARN' $null 'noms'}catch{}
        Update-PestoSharedNameStatus
        return
    }
    $script:SharedNameWarned=$false;$script:SharedNameLastOk=[DateTime]::UtcNow
    if($Result -and $Result.PSObject.Properties['Connected'] -and $Result.Connected){Add-PestoShareConnection ([string]$Result.Connected)}
    switch([string]$Context.Mode){
        {$_ -in @('Snapshot','Test','Prepare')}{
            $map=@{};foreach($o in @($Result.Others)){$map[[string]$o.Name]=$o}
            $script:SharedNameOthers=$map
            $script:SharedNameStatus=if($Context.Mode -eq 'Prepare'){'Registre partagé prêt : '+$Result.Root}elseif($Context.Mode -eq 'Test'){'Registre partagé joignable, écriture possible. Réservations actives des autres postes : '+$Result.Count+'.'}else{'Registre partagé : '+$Result.Count+' réservation(s) d''autres postes.'}
            if($Context.Mode -ne 'Snapshot'){try{Add-LogLine $script:SharedNameStatus 'ok'}catch{}}
            Invoke-PestoSharedNameRefreshLists
        }
        'Reserve'{
            $ctx=[string]$Context.Context;$name=[string]$Context.Name
            $script:SharedNamePending.Remove($ctx)
            if($Result.State -in @('Reserved','Renewed')){
                $previous=$script:SharedNameMine[$ctx]
                $script:SharedNameMine[$ctx]=[pscustomobject]@{Name=$name;Utc=[DateTime]::UtcNow}
                if($Result.State -eq 'Reserved'){
                    $script:SharedNameStatus="Nom $name réservé pour vous dans le registre partagé."
                    try{Add-LogLine ("NOMS : $name réservé dans le registre partagé ("+(Get-PestoSharedNameSettings).Minutes+' min, prolongé tant qu''il reste proposé).') 'info'}catch{}
                }
                if($previous -and [string]$previous.Name -ine $name){[void](Start-PestoSharedNameOperation -Mode Release -Names @([string]$previous.Name) -Context $ctx)}
            }elseif($Result.State -eq 'Held'){
                $script:SharedNameOthers[$name.ToUpperInvariant()]=[pscustomobject]@{Name=$name;Station=[string]$Result.Holder;User='';ExpiresUtc=[string]$Result.HolderExpiresUtc}
                $busy=if($ctx -eq 'Join'){[bool]$script:JoinBusy}else{[bool]($script:DirectBusy -or $script:PreflightRunning)}
                if($busy){
                    # Opération déjà engagée sur ce nom : elle continue, l'AD tranche avant toute écriture.
                    $script:SharedNameStatus="Nom $name aussi réservé par $($Result.Holder) pendant votre opération."
                    try{Add-LogLine ("NOMS : $name aussi réservé par $($Result.Holder) pendant votre opération ; un autre nom est proposé à la fin du contrôle, sinon l'AD tranche avant l'écriture.") 'warn'}catch{}
                }else{
                    $script:SharedNameStatus="Nom $name réservé par un autre poste ($($Result.Holder)) : autre nom proposé."
                    try{Add-LogLine ("NOMS : $name déjà réservé par $($Result.Holder) ; autre nom proposé.") 'warn'}catch{}
                }
                Invoke-PestoSharedNameRefreshLists
            }
        }
        'Release'{}
    }
    Update-PestoSharedNameStatus
}

function Invoke-PestoSharedNameRefreshLists {
    <# Un nom proposé est réservé ailleurs : les listes sont recalculées (jamais pendant un traitement). #>
    if($script:Running -or $script:PreflightRunning -or $script:DirectBusy -or $script:JoinBusy){return}
    try{
        if($script:JoinUI -and -not $script:INDOMAIN){
            $current=[string]$script:JoinUI.Name.SelectedItem
            if($current -and (Test-PestoNameReservedByOther $current)){Update-PestoJoinNames}
        }
        if($script:INDOMAIN -and $CbName){
            $current=[string]$CbName.SelectedItem
            if($current -and (Test-PestoNameReservedByOther $current)){Update-NameList}
        }
    }catch{try{Write-Log ('Listes de noms non recalculées : '+$_.Exception.Message) 'WARN' $_ 'noms'}catch{}}
}

function Get-PestoSharedNameWanted {
    <# Nom à réserver pour chaque parcours : celui proposé dans un formulaire complet, hors traitement en cours. #>
    $wanted=@{}
    try{
        if($script:JoinUI -and -not $script:INDOMAIN -and -not $script:JoinLocked -and -not [bool]$script:JoinUI.Existing.IsChecked){
            $n=[string]$script:JoinUI.Name.SelectedItem
            if($n -and (Test-PestoGeneratedComputerName $n)){$wanted['Join']=$n.ToUpperInvariant()}
        }
        if($script:INDOMAIN -and $CbName -and $ChkRename -and [bool]$ChkRename.IsChecked){
            $n=[string]$CbName.SelectedItem
            if($n -and (Test-PestoGeneratedComputerName $n)){$wanted['Direct']=$n.ToUpperInvariant()}
        }
    }catch{}
    return $wanted
}

function Invoke-PestoSharedNameTick {
    <# Toutes les secondes : réserve le nom proposé après une seconde de stabilité, prolonge nos réservations à mi-durée,
       libère celles qui ne sont plus proposées et relève les réservations des autres toutes les 30 secondes. #>
    param($Sender,$EventArgs)
    try{
        $settings=Get-PestoSharedNameSettings
        if(-not $settings.Root){return}
        if(-not $script:SharedNameMine){$script:SharedNameMine=@{}}
        if(-not $script:SharedNamePending){$script:SharedNamePending=@{}}
        if(-not $script:SharedNameSeen){$script:SharedNameSeen=@{}}
        $now=[DateTime]::UtcNow
        if(-not $script:SharedNameSnapshotUtc -or ($now-$script:SharedNameSnapshotUtc).TotalSeconds -ge 30){
            $script:SharedNameSnapshotUtc=$now
            if(-not (Test-PestoAsyncOperationRunning 'SharedNameSnapshot')){[void](Start-PestoSharedNameOperation -Mode Snapshot)}
        }
        # Simulation : les réservations des autres sont respectées, mais rien n'est réservé (aucune écriture partagée).
        if($script:SIM){return}
        $wanted=Get-PestoSharedNameWanted
        foreach($ctx in @('Join','Direct')){
            $busy=if($ctx -eq 'Join'){[bool]$script:JoinBusy}else{[bool]($script:DirectBusy -or $script:PreflightRunning)}
            $mine=$script:SharedNameMine[$ctx]
            $want=[string]$wanted[$ctx]
            if($busy){
                # Contrôle, réservation AD, confirmation ou exécution en cours : le nom visé est réservé tout de suite (le
                # technicien a pu cliquer avant la seconde de stabilité, ou Pesto a pris le nom suivant) puis prolongé ;
                # rien n'est libéré avant la fin de l'opération.
                if($want -and -not $script:SharedNamePending.ContainsKey($ctx) -and -not (Test-PestoNameReservedByOther $want)){
                    $renew=($mine -and [string]$mine.Name -eq $want -and ($now-$mine.Utc).TotalMinutes -ge ($settings.Minutes/2))
                    if(-not $mine -or [string]$mine.Name -ne $want -or $renew){
                        $script:SharedNamePending[$ctx]=$want
                        if(-not (Start-PestoSharedNameOperation -Mode Reserve -Name $want -Context $ctx)){$script:SharedNamePending.Remove($ctx)}
                    }
                }
                continue
            }
            if(-not $want){
                if($mine -and -not $script:SharedNamePending.ContainsKey($ctx)){
                    $script:SharedNameMine.Remove($ctx)
                    [void](Start-PestoSharedNameOperation -Mode Release -Names @([string]$mine.Name) -Context $ctx)
                }
                $script:SharedNameSeen.Remove($ctx);continue
            }
            if($script:SharedNamePending.ContainsKey($ctx)){continue}
            if(Test-PestoNameReservedByOther $want){Invoke-PestoSharedNameRefreshLists;continue}
            $seen=$script:SharedNameSeen[$ctx]
            if(-not $seen -or [string]$seen.Name -ne $want){$script:SharedNameSeen[$ctx]=[pscustomobject]@{Name=$want;Utc=$now};continue}
            if(($now-$seen.Utc).TotalMilliseconds -lt 900){continue}
            $renew=($mine -and [string]$mine.Name -eq $want -and ($now-$mine.Utc).TotalMinutes -ge ($settings.Minutes/2))
            if(-not $mine -or [string]$mine.Name -ne $want -or $renew){
                $script:SharedNamePending[$ctx]=$want
                if(-not (Start-PestoSharedNameOperation -Mode Reserve -Name $want -Context $ctx)){$script:SharedNamePending.Remove($ctx)}
            }
        }
    }catch{try{Write-Log ('Registre partagé : '+$_.Exception.Message) 'WARN' $_ 'noms'}catch{}}
}

function Start-PestoSharedNameTimer {
    if($script:SharedNameTimer){return}
    $script:SharedNameTimer=[Windows.Threading.DispatcherTimer]::new()
    $script:SharedNameTimer.Interval=[TimeSpan]::FromSeconds(1)
    $script:SharedNameTimer.Add_Tick([EventHandler]${function:Invoke-PestoSharedNameTick})
    $script:SharedNameTimer.Start()
}

function Stop-PestoSharedNameTimer {
    if($script:SharedNameTimer){$script:SharedNameTimer.Stop()}
    # Libération de nos réservations à la fermeture (y compris une réservation en cours d'écriture), attendue 3 s au plus :
    # la fermeture annule ensuite toutes les opérations. Au-delà (partage lent), elles expirent d'elles-mêmes.
    $ps=$null
    try{
        $settings=Get-PestoSharedNameSettings
        $names=@(@($script:SharedNameMine.Values|ForEach-Object{[string]$_.Name})+@($script:SharedNamePending.Values|ForEach-Object{[string]$_})|Where-Object{$_}|Sort-Object -Unique)
        if($names.Count -and $settings.Root -and $script:SharedNameOwner){
            $user=if($script:AuthUser){[string]$script:AuthUser}else{[string][Environment]::UserName}
            $request=[pscustomobject]@{Mode='Release';Root=$settings.Root;Domain=[string]$script:DOMAINE;Owner=$script:SharedNameOwner;Station=[string]$env:COMPUTERNAME;User=$user;
                Minutes=$settings.Minutes;Name='';Names=$names;Context='Close';Credential=$script:cred}
            $ps=[PowerShell]::Create()
            [void]$ps.AddScript($script:PestoSharedNameWorker.ToString()).AddArgument($request)
            $h=$ps.BeginInvoke()
            if($h.AsyncWaitHandle.WaitOne(3000)){try{$res=@($ps.EndInvoke($h))|Select-Object -Last 1;if($res -and $res.Connected){Add-PestoShareConnection ([string]$res.Connected)}}catch{}}else{[void]$ps.BeginStop($null,$null);$ps=$null}
            $script:SharedNameMine=@{};$script:SharedNamePending=@{}
        }
    }catch{}finally{if($ps){try{$ps.Dispose()}catch{}}}
    Close-PestoShareConnections
}

function Close-PestoShareConnections {
    <# Connexions au partage du registre ouvertes par Pesto avec le compte AD : fermées à la fermeture de Pesto, sinon elles
       resteraient ouvertes pour toute la session Windows, jusqu'à la déconnexion. Hors domaine, la connexion au partage
       configuré est la sienne (le compte local n'y a aucun droit) ; ailleurs, seulement celles que Pesto a signalées. #>
    try{
        $settings=Get-PestoSharedNameSettings
        $unc=[regex]::Match([string]$settings.Root,'^\\\\([^\\]+)\\([^\\]+)')
        if(-not $script:INDOMAIN -and $script:cred -and $unc.Success){Add-PestoShareConnection ('\\'+$unc.Groups[1].Value+'\'+$unc.Groups[2].Value)}
        foreach($share in @($script:PestoShareConnections)){
            if([string]$share -match '^\\\\[^\\/]+\\[^\\/]+$'){& (Join-Path $env:SystemRoot 'System32\net.exe') use ([string]$share) /delete /y 2>&1|Out-Null}
        }
    }catch{}
    $script:PestoShareConnections=$null
}

function Update-PestoSharedNameStatus {
    <# Texte d'état affiché dans Paramètres (registre) ; les parcours l'affichent dans le Journal. #>
    try{if($SetLblCoordStatus){$SetLblCoordStatus.Text=[string]$script:SharedNameStatus}}catch{}
    Update-PestoSharedRegistryButton
}
