#requires -Version 5.1
# Recherche et édition locale de configuration ; lectures AD uniquement sur demande.
function Get-PestoSettingDefinitions {
    $definitions=@(
      @('Domaine','Domaine DNS','CONF.0.Domaine','SetTxtDomaine',1,'Relancer Pesto ; recontrôler les plans'),
      @('Domaine','Compte AD proposé','CONF.0.ADM','SetTxtADM',1,'Immédiat ; ne change pas la session ouverte'),
      @('Domaine','Préfixe (6 chiffres)','CONF.0.Prefixe','SetTxtPrefixe',1,'Relancer Pesto ; recalculer les noms'),
      @('Domaine','Site de préparation (3 caractères)','CONF.0.PreprodSite','SetTxtPreprod',1,'Relancer Pesto ; recontrôler les plans'),
      @('Domaine','Réserve de propositions','CONF.0.Buffer','SetTxtBuffer',1,'Immédiat pour les prochaines propositions'),
      @('Domaine','Périmètre de lecture des noms','CONF.0.OUScanNoms','SetTxtOUScan',1,'Relancer Pesto ; recharger le périmètre'),
      @('Domaine','Placement direct en production','CONF.0.DirectProd','SetChkDirectProd',1,'Relancer Pesto ; recontrôler les plans'),
      @('Domaine','Retrait Entra autorisé','CONF.0.EntraPolicy','SetChkDsreg',1,'Relancer Pesto ; nouveaux contrôles requis'),
      @('Noms et coordination','Nom aléatoire selon les filtres','POLICY.RandomNameEnabled','SetChkRandomName',2,'Relancer Pesto ; nouveaux noms proposés'),
      @('Noms et coordination','Dossier de coordination','POLICY.CoordinationRoot','SetTxtCoordRoot',2,'Relancer Pesto ; vérifier la coordination'),
      @('Noms et coordination','Coordination obligatoire','POLICY.CoordinationRequired','SetChkCoordRequired',2,'Relancer Pesto ; recontrôler les plans'),
      @('Noms et coordination','Réservation dans AD','POLICY.ReserveNamesInAD','SetChkReserveAD',2,'Relancer Pesto ; futures jonctions'),
      @('Noms et coordination','Durée de réservation','POLICY.NameReservationMinutes','SetTxtReserveMinutes',2,'Relancer Pesto ; futures réservations'),
      @('Politique','Nombre maximal de postes','POLICY.MaxBatch','SetTxtMaxBatch',3,'Relancer Pesto ; futurs lots'),
      @('Politique','Lectures parallèles','POLICY.MaxReaders','SetTxtMaxReaders',3,'Relancer Pesto ; futures lectures'),
      @('Politique','Tentatives de lecture','POLICY.ReadAttempts','SetTxtReadAttempts',3,'Relancer Pesto ; jamais de répétition automatique des mutations'),
      @('Politique','Noms exclus','POLICY.ExcludedNames','SetTxtExcludedNames',3,'Relancer Pesto ; recontrôler les plans'),
      @('Politique','OU exclues','POLICY.ExcludedOUs','SetTxtExcludedOUs',3,'Relancer Pesto ; recontrôler les plans'),
      @('Politique','Groupes exclus','POLICY.ExcludedGroupGuids','SetTxtExcludedGroups',3,'Relancer Pesto ; recontrôler les plans'),
      @('Politique','Rétention des journaux','POLICY.LogRetentionDays','SetTxtLogRetention',3,'Relancer Pesto ; politique de conservation'),
      @('Politique','Écart d’’horloge avant jonction','POLICY.BlockJoinOnClockSkew','SetChkClockSkew',3,'Relancer Pesto ; bloque seulement un écart mesuré de 300 secondes ou plus'),
      @('Politique','Compte ordinateur précréé','POLICY.AllowPrecreatedJoin','SetChkPrecreated',3,'Relancer Pesto ; futures jonctions'),
      @('Tags','Codes des sites (2 lettres)','TAGS','SetGridTags',4,'Relancer Pesto ; recalculer les noms'),
      @('OU & organismes','OU de base','OUBase','SetGridOUBase',5,'Relancer Pesto ; recontrôler les plans'),
      @('OU & organismes','Organismes et OU de sites','OUSite','SetGridOUSite',5,'Relancer Pesto ; recontrôler les plans'),
      @('Options avancées','Journal d''evenements Windows','POLICY.AuditEventLogEnabled','SetChkAuditEventLog',6,'Relancer Pesto ; source Pesto à provisionner par l''administrateur'),
      @('Options avancées','Mode incident','POLICY.IncidentMode','SetChkIncidentMode',6,'Relancer Pesto ; suspension des nouvelles mutations'),
      @('Options avancées','Jonction silencieuse','POLICY.UnattendedJoinEnabled','SetChkUnattendedJoin',6,'Relancer Pesto ; opt-in de la commande de jonction'),
      @('Options avancées','Renommage et déplacement silencieux','POLICY.UnattendedOperationsEnabled','SetChkUnattendedOperations',6,'Relancer Pesto ; opt-in des commandes silencieuses'),
      @('Options avancées','Simulation','DEBUG.Simulation','SetChkSim',6,'Relancer Pesto ; changement de contexte'),
      @('Options avancées','Démonstration','DEBUG.GUI','SetChkGUI',6,'Relancer Pesto ; données fictives'),
      @('Options avancées','Hors domaine forcé','DEBUG.HorsDomaine','SetChkODM',6,'Relancer Pesto ; simulation uniquement')
    )
    foreach($d in $definitions){[pscustomobject]@{Section=$d[0];Label=$d[1];Path=$d[2];Control=$d[3];Tab=[int]$d[4];Impact=$d[5]}}
}
function Find-PestoSettings {
    param([string]$Query='')
    $words=@((ConvertTo-PestoSearchText $Query) -split '\s+'|Where-Object{$_})
    foreach($setting in @(Get-PestoSettingDefinitions)){$text=ConvertTo-PestoSearchText ($setting.Section+' '+$setting.Label+' '+$setting.Path);$match=$true;foreach($word in $words){if(-not$text.Contains($word)){$match=$false;break}};if($match){$setting}}
}
function Get-PestoConfigPathValue {
    param($Config,[string]$Path)
    $value=$Config;foreach($key in $Path.Split('.')){if($key -match '^\d+$'){$value=@($value)[[int]$key]}else{$value=$value.$key}};return $value
}
function Set-PestoConfigPathValue {
    param($Config,[string]$Path,$Value)
    if($Path -notin @(Get-PestoSettingDefinitions|ForEach-Object{$_.Path})){throw 'Champ non modifiable par cet outil.'}
    $keys=$Path.Split('.');$node=$Config;for($i=0;$i -lt $keys.Count-1;$i++){if($keys[$i] -match '^\d+$'){$node=@($node)[[int]$keys[$i]]}else{$node=$node.($keys[$i])}}
    if($null -eq $node){throw 'Rubrique absente de la configuration.'};$key=$keys[-1]
    if($node -is [Collections.IDictionary]){$node[$key]=$Value}elseif($node.PSObject.Properties[$key]){$node.$key=$Value}else{$node|Add-Member -NotePropertyName $key -NotePropertyValue $Value}
}
function Restore-PestoConfigValues {
    param($Candidate,$Baseline,[string[]]$Paths)
    $result=$Candidate|ConvertTo-Json -Depth 30|ConvertFrom-Json -ErrorAction Stop
    foreach($path in $Paths){$value=Get-PestoConfigPathValue $Baseline $path;Set-PestoConfigPathValue $result $path $value};return $result
}
function Get-PestoConfigFileStamp {
    param([string]$Path)
    if(-not $Path){return ''};Assert-PestoPlainPath $Path
    if(-not [IO.File]::Exists($Path)){return 'Missing'}
    $file=Get-Item -LiteralPath $Path -ErrorAction Stop;if($file.Length -gt 1048576){throw 'cfg.json dépasse 1 Mio.'}
    $stream=[IO.File]::OpenRead($Path);$hash=[Security.Cryptography.SHA256]::Create();try{return ([BitConverter]::ToString($hash.ComputeHash($stream))).Replace('-','').ToLowerInvariant()}finally{$stream.Dispose();$hash.Dispose()}
}
function Assert-PestoConfigFileUnchanged {
    param([string]$Path,[string]$Expected)
    if(-not $Expected){throw 'Version du fichier non mémorisée. Rechargez les paramètres avant de les enregistrer.'}
    if((Get-PestoConfigFileStamp $Path) -cne $Expected){throw 'cfg.json a été modifié en dehors de ce formulaire. Exportez vos changements si nécessaire, puis Recharger pour comparer la nouvelle version. Aucun fichier remplacé.'}
}
function Get-PestoReadableConfigChanges {
    param($Before,$After)
    $definitions=@(Get-PestoSettingDefinitions)
    foreach($change in @(Get-PestoConfigurationChanges $Before $After)){
        $path=([string]$change.Champ -replace '\[(\d+)\]','.$1');$definition=@($definitions|Where-Object{$path -ieq $_.Path -or $path.StartsWith($_.Path+'.',[StringComparison]::OrdinalIgnoreCase)}|Sort-Object @{Expression={$_.Path.Length};Descending=$true}|Select-Object -First 1)
        $d=if($definition.Count){$definition[0]}else{$null}
        [pscustomobject]@{Rubrique=$(if($d){$d.Section}else{'Configuration'});Reglage=$(if($d){$d.Label}else{$change.Champ});Avant=[string]$change.Avant;Apres=[string]$change.Apres;Effet=$(if($d){$d.Impact}else{'Relancer Pesto ; contexte métier à revalider'});Control=$(if($d){$d.Control}else{''});Tab=$(if($d){$d.Tab}else{7});Path=$path}
    }
}
function Format-PestoConfigChanges {
    param([object[]]$Changes)
    if(-not $Changes.Count){return 'Aucune modification.'}
    (@(foreach($c in $Changes){$c.Rubrique+' · '+$c.Reglage+"`nAvant : "+$c.Avant+"`nAprès : "+$c.Apres+"`nEffet : "+$c.Effet}) -join "`n`n")
}
function Focus-PestoSetting {
    param($Setting)
    Set-PestoUxPage 'Settings';$SetTabs.SelectedIndex=[int]$Setting.Tab;$Win.UpdateLayout()
    $control=$Win.FindName([string]$Setting.Control);if($control){$control.BringIntoView();[void]$control.Focus()}
}
function Show-PestoSettingSearch {
    $r=Show-PestoChoiceTable -Title 'Rechercher un réglage' -Description 'Recherchez par nom, rubrique ou clé JSON. Ouvrir un réglage ne le modifie pas.' -Rows @(Find-PestoSettings) -SearchProperties @('Path') -Columns @(@{Key='Label';Label='Réglage'},@{Key='Section';Label='Rubrique'},@{Key='Impact';Label='Effet du changement'}) -AcceptText 'Ouvrir le réglage'
    if($r.Accepted){Focus-PestoSetting $r.Items[0]}
}
function Show-PestoConfigurationDiff {
    $changes=@(Get-PestoReadableConfigChanges $(if($script:SettingsSourceConfig){$script:SettingsSourceConfig}else{$script:CFG}) (Build-CfgFromUI))
    $r=Show-PestoChoiceTable -Title 'Modifications des paramètres' -Description 'Les effets indiqués concernent un futur enregistrement. Aucun fichier modifié. Sélectionnez une ligne pour retrouver le réglage.' -Rows $changes -Columns @(@{Key='Reglage';Label='Réglage'},@{Key='Avant';Label='Avant'},@{Key='Apres';Label='Après'},@{Key='Effet';Label='Effet'}) -AcceptText 'Retrouver le réglage'
    if($r.Accepted -and $r.Items[0].Control){Focus-PestoSetting $r.Items[0]}
}
function Get-PestoConfigNameExamples {
    param($Config,[string]$Service='001',[int]$Number=1)
    $convention=Assert-PestoNamingConvention $Config.NamingConvention
    if(-not $PSBoundParameters.ContainsKey('Service')){$Service='0'*([int]$convention.Widths.Service-1)+'1'}
    if($Service -notmatch (Get-PestoFacetPattern Service $convention) -or $Number -lt 1 -or $Number -gt (Get-PestoNameMaximumNumber $convention)){throw 'Service ou numéro invalide.'}
    $conf=@($Config.CONF)[0];$rows=@();foreach($tag in @($Config.TAGS|Select-Object -First 100)){
        if([string]$tag.Tag -notmatch (Get-PestoFacetPattern Site $convention)){continue}
        foreach($type in @('P','S','V')){$name=New-PestoComputerName -Type $type -Prefix $conf.Prefixe -Site $tag.Tag -Service $Service -Number $Number -Convention $convention
            $rows+=[pscustomobject]@{Nom=$name;Site=[string]$tag.Site;Service=$Service;Type=$type;Destination=$(if(-not(Convert-Value-TF $conf.DirectProd)){[string](@($Config.OUBase|Where-Object{$_.Nom -eq 'PREPROD'})|Select-Object -First 1).OU}else{'OU du site à choisir et relire dans AD'});Etat='Exemple de règle, disponibilité non vérifiée'}
        }
    };return $rows
}
function Show-PestoConfigurationCheckResults {
    param($Result)
    $rows=@(foreach($check in @($Result.Checks)){
        $setting=if($check.Control){@(Get-PestoSettingDefinitions|Where-Object{$_.Control -eq $check.Control})[0]}elseif($check.Champ -eq 'OUScanNoms'){@(Get-PestoSettingDefinitions|Where-Object{$_.Control -eq 'SetTxtOUScan'})[0]}elseif($check.Champ -like 'Site *'){@(Get-PestoSettingDefinitions|Where-Object{$_.Control -eq 'SetGridTags'})[0]}else{@(Get-PestoSettingDefinitions|Where-Object{$_.Control -eq 'SetGridOUSite'})[0]}
        [pscustomobject]@{Champ=$check.Champ;Etat=$check.Etat;Detail=$check.Detail;Control=$setting.Control;Tab=$setting.Tab}
    })
    $r=Show-PestoChoiceTable -Title 'Configuration : observations AD' -Description ('Contrôleur : '+$Result.DC+' · Lecture UTC : '+$Result.Utc+'. Les droits de mutation ne sont pas certifiés.') -Rows $rows -Columns @(@{Key='Champ';Label='Contrôle'},@{Key='Etat';Label='État'},@{Key='Detail';Label='Observation'}) -AcceptText 'Ouvrir le réglage'
    if($r.Accepted){Focus-PestoSetting $r.Items[0]}
}
function Invoke-PestoOuPickerWorker {
    param($Request)
    . ([scriptblock]::Create($Request.Source));Import-PestoADModule $Request.ADModulePath
    $dc=Get-DomainController $Request.Domain;$ad=@{Server=$dc;ErrorAction='Stop'};if($Request.Credential){$ad.Credential=$Request.Credential}
    $seen=@{};$rows=[Collections.Generic.List[object]]::new()
    foreach($root in $Request.Roots){
        if(-not(Test-PestoOUPath $root)){throw 'Périmètre OU invalide.'}
        foreach($ou in @(Get-ADOrganizationalUnit -SearchBase $root -SearchScope Subtree -Filter * -Properties ObjectGUID -ResultSetSize 2001 @ad)){
            if($seen.ContainsKey([string]$ou.DistinguishedName)){continue};$seen[[string]$ou.DistinguishedName]=$true
            $rows.Add([pscustomobject]@{Nom=[string]$ou.Name;DN=[string]$ou.DistinguishedName;GUID=[string]$ou.ObjectGUID})
            if($rows.Count -gt 2000){throw 'Plus de 2 000 OU : réduisez les périmètres configurés ou utilisez le DN manuel.'}
        }
    };[pscustomobject]@{Rows=$rows.ToArray();DC=$dc;Utc=[DateTimeOffset]::UtcNow.ToString('o')}
}
function Start-PestoOuPicker {
    if($script:GUI -or $script:SIM){Show-MsgInfo 'Choix AD réservé au mode réel. La saisie manuelle du DN reste disponible.';return}
    if($script:PestoReadOnly){Show-MsgInfo 'Consultation : le formulaire de configuration reste en lecture seule.';return}
    $targets=@([pscustomobject]@{Label='Périmètre de lecture des noms';Kind='Scope';Row=$null},[pscustomobject]@{Label='Ajouter une OU aux exclusions';Kind='Excluded';Row=$null})
    foreach($item in @(@($SetGridOUBase,'Base'),@($SetGridOUSite,'Site'))){if($item[0].SelectedItem -is [Data.DataRowView]){$targets+= [pscustomobject]@{Label=('OU '+$item[0].SelectedItem.Nom);Kind=$item[1];Row=$item[0].SelectedItem.Row}}}
    $choice=Show-PestoPanel -Title 'Choisir le champ OU' -Body 'Sélectionnez la destination du DN. Pour une OU de base ou un organisme, sélectionnez sa ligne dans Paramètres au préalable.' -Choices $targets -AcceptText 'Parcourir les OU'
    if(-not $choice.Accepted -or -not $choice.Selected){return}
    $candidate=Build-CfgFromUI;$roots=@(@($candidate.OUBase)+@($candidate.OUSite)|ForEach-Object{[string]$_.OU}|Where-Object{$_}|Sort-Object -Unique)
    if(-not$roots.Count){Show-MsgWarning 'Renseignez au moins une OU racine valide avant de la parcourir.';return}
    $source=Get-PestoWorkerCoreSource;$source+="`nfunction Get-DomainController {`n"+(Get-Command Get-DomainController).Definition+"`n}"
    $request=[pscustomobject]@{Source=$source;Roots=$roots;Domain=[string]@($candidate.CONF)[0].Domaine;Credential=$script:cred;ADModulePath=(Join-Path $BasePath 'ActiveDirectory.psd1')}
    $context=[pscustomobject]@{Target=$choice.Selected;EditorHash=(Get-PestoStableHash $candidate)}
    $started=Start-PestoAsyncOperation -Name 'ConfigOuPicker' -ScriptBlock ${function:Invoke-PestoOuPickerWorker} -ArgumentList @($request) -CallbackContext $context -TimeoutSec 90 -OnSuccess {
        param($r,$ctx)
        $chosen=Show-PestoChoiceTable -Title 'Choisir une OU' -Description ('Lecture seule sur '+$r.DC+' · '+$r.Utc+'. Le DN manuel reste disponible.') -Rows $r.Rows -Columns @(@{Key='Nom';Label='Nom'},@{Key='DN';Label='Chemin complet'}) -AcceptText 'Reporter ce DN'
        if($chosen.Accepted){if((Get-PestoStableHash (Build-CfgFromUI)) -cne $ctx.EditorHash){Show-MsgWarning 'Les paramètres ont changé pendant la lecture. Relancez le choix pour conserver votre travail.';return};if($script:PestoReadOnly -or $script:Running -or $script:PreflightRunning -or $script:DirectBusy -or $script:JoinBusy){Show-MsgWarning 'Une opération est active. Aucun réglage modifié.';return};if($ctx.Target.Kind -eq 'Scope'){$SetTxtOUScan.Text=$chosen.Items[0].DN}elseif($ctx.Target.Kind -eq 'Excluded'){$SetTxtExcludedOUs.Text=Add-PestoExcludedConfigValue -Text $SetTxtExcludedOUs.Text -Value $chosen.Items[0].DN -Kind OU}else{$ctx.Target.Row.OU=$chosen.Items[0].DN};$SetLblStatus.Text='DN reporté dans le formulaire. Enregistrer reste une action séparée.'}
    } -OnError {param($e,$c);Show-MsgWarning ('Lecture OU interrompue : '+(Protect-PestoLogText $e.Exception.Message))}
    if(-not $started){throw 'Lecture des OU non lancée. Attendez la lecture en cours puis réessayez.'}
}
function Invoke-PestoConfigEditor {
    param($Sender,$EventArgs)
    try{
        switch($Sender.Name){
            'SetSearchSettings' {Show-PestoSettingSearch;return}
            'SetConfigJson' {[void](Show-PestoPanel -Title 'Configuration JSON du formulaire' -Body ((Build-CfgFromUI)|ConvertTo-Json -Depth 30) -Monospace);return}
            'SetConfigNames' {$rows=@(Get-PestoConfigNameExamples (Build-CfgFromUI));[void](Show-PestoChoiceTable -Title 'Exemples de nommage' -Description 'Exemples calculés sur le formulaire, sans vérifier la disponibilité des noms ni modifier un poste.' -Rows $rows -Columns @(@{Key='Nom';Label='Exemple'},@{Key='Site';Label='Règle de site'},@{Key='Destination';Label='Emplacement prévu'},@{Key='Etat';Label='Portée'}));return}
            'SetBrowseOU' {Start-PestoOuPicker;return}
            'SetBrowseExcludedGroup' {Start-PestoExcludedGroupPicker;return}
        }
        if($script:PestoReadOnly -or $script:Running -or $script:DirectBusy -or $script:JoinBusy -or $script:PreflightRunning){throw 'Modification du formulaire indisponible pendant ce contexte.'}
        $definitions=@(Get-PestoSettingDefinitions)
        $r=Show-PestoChoiceTable -Title 'Rétablir les valeurs chargées' -Description 'Seul le formulaire change. Les autres modifications sont conservées. Enregistrer reste séparé.' -Rows $definitions -Columns @(@{Key='Label';Label='Réglage'},@{Key='Section';Label='Rubrique'}) -AcceptText $(if($Sender.Name -eq 'SetResetSection'){'Rétablir la rubrique'}else{'Rétablir ce champ'})
        if($r.Accepted){$selected=$r.Items[0];$paths=if($Sender.Name -eq 'SetResetSection'){@($definitions|Where-Object{$_.Section -eq $selected.Section}|ForEach-Object{$_.Path})}else{@($selected.Path)}
            if(-not(Confirm-YesNo -Msg ('Rétablir '+$paths.Count+' réglage(s) depuis la version chargée ? Les autres champs sont conservés.') -Confirm $true -AcceptText 'Rétablir dans le formulaire')){return}
            $candidate=Restore-PestoConfigValues -Candidate (Build-CfgFromUI) -Baseline $script:SettingsSourceConfig -Paths $paths;Load-SettingsUI -Config $candidate -Draft;Focus-PestoSetting $selected
        }
    }catch{Show-MsgWarning $_.Exception.Message}
}
function Initialize-PestoConfigEditor {
    foreach($name in @('SetSearchSettings','SetConfigJson','SetConfigNames','SetBrowseOU','SetBrowseExcludedGroup','SetResetField','SetResetSection')){$control=$Win.FindName($name);if($control){$control.Add_Click([Windows.RoutedEventHandler]${function:Invoke-PestoConfigEditor})}}
}

function Sync-PestoManagedSettings {
    $managed=Get-PestoManagedPolicy;$summary=$Win.FindName('SetManagedPolicySource')
    if($summary){$summary.Text=if($managed.Configured){Get-PestoManagedPolicySummary}else{'Source : configuration locale cfg.json ; aucune restriction administrée.'}}
    foreach($pair in @(@('SetChkIncidentMode','IncidentMode',$true),@('SetChkUnattendedJoin','DisableUnattendedJoin',$false),@('SetChkUnattendedOperations','DisableUnattendedOperations',$false))){
        $control=$Win.FindName($pair[0]);if($control){$forced=($managed.Configured -and $managed.Values.($pair[1]) -eq 1);$control.IsEnabled=(-not $forced -and -not $script:PestoReadOnly);if($forced){$control.IsChecked=[bool]$pair[2]}}
    }
    $batch=$Win.FindName('SetTxtMaxBatch');if($batch){$batch.IsEnabled=(-not $script:PestoReadOnly -and $null -eq $managed.Values.MaxBatch)}
}

function Add-PestoExcludedConfigValue {
    param([string]$Text,[string]$Value,[ValidateSet('OU','Group')][string]$Kind)
    $name=if($Kind -eq 'OU'){'ExcludedOUs'}else{'ExcludedGroupGuids'}
    $items=@(@($Text -split '\r?\n'|ForEach-Object{$_.Trim()}|Where-Object{$_})+@($Value.Trim())|Select-Object -Unique)
    $candidate=[pscustomobject]@{Schema=1};$candidate|Add-Member NoteProperty $name $items
    $safe=ConvertTo-PestoPolicy $candidate
    return (@($safe.$name) -join "`r`n")
}

function Invoke-PestoExcludedGroupPickerWorker {
    param($Request)
    . ([scriptblock]::Create($Request.Source))
    $search=([string]$Request.Search).Trim()
    if($search.Length -lt 2 -or $search.Length -gt 128 -or $search -match '[\x00-\x1f]'){throw 'Saisissez entre 2 et 128 caractères pour chercher un groupe.'}
    Import-PestoADModule $Request.ADModulePath
    $dc=Get-DomainController $Request.Domain
    $argsAD=@{Server=$dc;ErrorAction='Stop'};if($Request.Credential){$argsAD.Credential=$Request.Credential}
    # Filtre LDAP (RFC 4515), distinct du RowFilter des tableaux.
    $literal=$search.Replace('\','\5c').Replace('*','\2a').Replace('(','\28').Replace(')','\29')
    $groups=@(Get-ADGroup -LDAPFilter "(|(name=*$literal*)(sAMAccountName=*$literal*))" -Properties ObjectGUID,SamAccountName -ResultSetSize 101 @argsAD)
    if($groups.Count -gt 100){throw 'Plus de 100 groupes correspondent. Précisez le nom ; aucun résultat partiel utilisé.'}
    $seen=@{};$rows=@(foreach($group in $groups){
        $guid=[Guid]::Empty
        if(-not [Guid]::TryParse([string]$group.ObjectGUID,[ref]$guid) -or $guid -eq [Guid]::Empty -or
           (Get-PestoDomainFromDN ([string]$group.DistinguishedName)) -ine $Request.Domain){throw 'Identité ou domaine du groupe non confirmé.'}
        if($seen.ContainsKey($guid.ToString('D'))){continue};$seen[$guid.ToString('D')]=$true
        [pscustomobject]@{Nom=[string]$group.Name;Compte=[string]$group.SamAccountName;DN=[string]$group.DistinguishedName;GUID=$guid.ToString('D')}
    })
    [pscustomobject]@{Rows=$rows;DC=$dc;Utc=[DateTime]::UtcNow.ToString('o')}
}

function Start-PestoExcludedGroupPicker {
    if($script:GUI -or $script:SIM){Show-MsgInfo 'Recherche AD disponible en mode réel. La saisie manuelle du GUID reste disponible.';return}
    if($script:PestoReadOnly -or $script:Running -or $script:PreflightRunning -or $script:DirectBusy -or $script:JoinBusy){Show-MsgInfo 'Attendez la fin de l''opération pour modifier les exclusions.';return}
    $prompt=Show-PestoPanel -Title 'Choisir un groupe à exclure' -Body 'Cherchez son nom ou son nom de compte. Seul le GUID du groupe choisi sera ajouté au formulaire ; aucune modification AD.' -InputLabel 'Nom du groupe (2 caractères au moins)' -AcceptText 'Rechercher'
    if(-not $prompt.Accepted){return}
    $candidate=Build-CfgFromUI
    $source=Get-PestoWorkerCoreSource;$source+="`nfunction Get-DomainController {`n"+(Get-Command Get-DomainController).Definition+"`n}"
    $request=[pscustomobject]@{Source=$source;Search=$prompt.Text;Domain=[string]@($candidate.CONF)[0].Domaine;Credential=$script:cred;ADModulePath=(Join-Path $BasePath 'ActiveDirectory.psd1')}
    $ctx=[pscustomobject]@{EditorHash=(Get-PestoStableHash $candidate)}
    $started=Start-PestoAsyncOperation -Name 'ConfigGroupPicker' -ScriptBlock ${function:Invoke-PestoExcludedGroupPickerWorker} -ArgumentList @($request) -CallbackContext $ctx -TimeoutSec 90 -OnSuccess {
        param($r,$context)
        try{
            $chosen=Show-PestoChoiceTable -Title 'Groupe à exclure' -Description ('Lecture sur '+$r.DC+' · '+$r.Utc+'. Le GUID reste stable si le groupe est renommé.') -Rows $r.Rows -Columns @(@{Key='Nom';Label='Nom'},@{Key='Compte';Label='Compte'},@{Key='DN';Label='Emplacement'}) -AcceptText 'Ajouter aux exclusions'
            if(-not $chosen.Accepted){return}
            if($script:PestoReadOnly -or $script:Running -or $script:PreflightRunning -or $script:DirectBusy -or $script:JoinBusy){throw 'Une opération est active. Aucun réglage modifié.'}
            if((Get-PestoStableHash (Build-CfgFromUI)) -cne $context.EditorHash){throw 'Le formulaire a changé pendant la recherche. Relancez le choix du groupe.'}
            $SetTxtExcludedGroups.Text=Add-PestoExcludedConfigValue -Text $SetTxtExcludedGroups.Text -Value $chosen.Items[0].GUID -Kind Group
            $SetLblStatus.Text='Groupe ajouté au formulaire par son GUID. Enregistrer reste une action séparée.'
        }catch{Show-MsgWarning $_.Exception.Message}
    } -OnError {param($e,$c);Show-MsgWarning ('Recherche des groupes interrompue : '+(Protect-PestoLogText $e.Exception.Message))}
    if(-not $started){Show-MsgWarning 'Recherche non lancée. Attendez la recherche en cours puis réessayez.'}
}
