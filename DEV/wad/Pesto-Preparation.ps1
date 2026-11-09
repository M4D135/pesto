#requires -Version 5.1
# Favori de formulaire : aucune identité de poste, commande ou confirmation persistée.
function ConvertTo-PestoPreparation {
    param($Value)
    $keys=@('Schema','Domain','ConfigStamp','Org','Site','Service','Type')
    if(-not $Value -or ($Value.Schema -isnot [int] -and $Value.Schema -isnot [long]) -or $Value.Schema -ne 1){throw 'Favori absent ou incompatible.'}
    foreach($p in $Value.PSObject.Properties){if($p.Name -notin $keys){throw 'Champ non autorisé dans le favori.'}}
    foreach($name in @('Domain','ConfigStamp','Org','Site','Service','Type')){
        if($Value.$name -isnot [string] -or -not $Value.$name -or $Value.$name.Length -gt 512 -or $Value.$name -match '[\x00-\x1f]'){throw 'Valeur de favori invalide.'}
    }
    if(-not(Test-PestoDnsName $Value.Domain) -or $Value.Service -notmatch (Get-PestoFacetPattern Service) -or $Value.ConfigStamp -notmatch '^[A-Fa-f0-9]{64}$'){throw 'Domaine, empreinte ou service du favori invalide.'}
    return [pscustomobject]@{Schema=1;Domain=$Value.Domain;ConfigStamp=$Value.ConfigStamp;Org=$Value.Org;Site=$Value.Site;Service=$Value.Service;Type=$Value.Type}
}


function Read-PestoPreparations {
    $text=if($script:GUI -or $script:SIM){$script:PestoPrepMemory}else{Get-PestoAppearanceValue -Name 'Preparation'}
    if(-not $text){return @()}
    if($text.Length -gt 32768){throw 'La collection de favoris est trop volumineuse.'}
    $data=$text|ConvertFrom-Json -ErrorAction Stop
    if($data.Schema -eq 1){return @([pscustomobject]@{Name='Mon favori';Value=(ConvertTo-PestoPreparation $data)})}
    Assert-PestoClosedObject $data @('Schema','Favorites') @('Schema','Favorites')
    if(($data.Schema -isnot [int] -and $data.Schema -isnot [long]) -or $data.Schema -ne 2 -or @($data.Favorites).Count -gt 20){throw 'Collection de favoris invalide.'}
    $list=[Collections.Generic.List[object]]::new();$seen=@{}
    foreach($entry in @($data.Favorites)){
        Assert-PestoClosedObject $entry @('Name','Value') @('Name','Value')
        if($entry.Name -isnot [string] -or $entry.Name.Length -lt 1 -or $entry.Name.Length -gt 64 -or $entry.Name -match '[\x00-\x1f]' -or $seen.ContainsKey($entry.Name)){throw 'Nom de favori invalide ou dupliqué.'}
        $seen[$entry.Name]=$true;$list.Add([pscustomobject]@{Name=$entry.Name;Value=(ConvertTo-PestoPreparation $entry.Value)})
    }
    return $list.ToArray()
}

function Save-PestoPreparations {
    param([object[]]$Items)
    if($Items.Count -gt 20){throw 'Vingt favoris maximum.'}
    $text=[pscustomobject]@{Schema=2;Favorites=@($Items)}|ConvertTo-Json -Depth 5 -Compress
    if($text.Length -gt 32768){throw 'Collection trop volumineuse.'}
    if($script:GUI -or $script:SIM){$script:PestoPrepMemory=$text}else{Set-PestoAppearanceValue -Name 'Preparation' -Value $text}
    Update-PestoPreparationList
}

function Update-PestoPreparationList {
    $list=$Win.FindName('PrepList');if(-not $list){return}
    $selected=if($list.SelectedItem){[string]$list.SelectedItem.Name}else{''}
    try{
        $items=@(Read-PestoPreparations);$list.ItemsSource=$items
        $same=@($items|Where-Object{$_.Name -eq $selected}|Select-Object -First 1)
        if($same.Count){$list.SelectedItem=$same[0]}elseif($items.Count){$list.SelectedIndex=0}
    }catch{Add-LogLine ('Favoris non chargés : '+(Protect-PestoLogText $_.Exception.Message)) 'warn'}
}

function Invoke-PestoPreparationCommand {
    param($Sender,$EventArgs)
    try{
        if($script:Running -or $script:DirectBusy -or $script:JoinBusy -or $script:PreflightRunning -or $script:CfgRestartRequired){throw 'Attendez la fin du traitement ou appliquez la configuration avant de changer le formulaire.'}
        $items=@(Read-PestoPreparations)
        $list=$Win.FindName('PrepList');$edit=$Win.FindName('PrepName')
        if($Sender.Name -eq 'PrepClear'){
            if(-not $list.SelectedItem){throw 'Choisissez le favori à retirer.'}
            $selected=[string]$list.SelectedItem.Name
            Save-PestoPreparations -Items @($items|Where-Object{$_.Name -ine $selected})
            Add-LogLine 'Favori sélectionné retiré. Aucune intervention modifiée.' 'info';return
        }
        if(-not $CbOrg.IsEnabled){throw 'Lisez d''abord le poste à préparer.'}
        if($Sender.Name -eq 'PrepSave'){
            $name=([string]$edit.Text).Trim()
            if(-not $name -or $name.Length -gt 64 -or $name -match '[\x00-\x1f]'){throw 'Donnez un nom au favori (64 caractères maximum).'}
            $favorite=ConvertTo-PestoPreparation ([pscustomobject]@{Schema=1;Domain=[string]$script:DOMAINE;ConfigStamp=(Get-PestoConfigurationSignature $script:CFG);
                Org=[string]$CbOrg.SelectedItem;Site=[string]$CbSite.SelectedItem;Service=([string]$CbService.Text).Trim();Type=[string]$CbType.SelectedItem})
            $duplicate=@($items|Where-Object{$_.Name -ieq $name})
            if($duplicate.Count -and -not(Confirm-YesNo -Msg ('Remplacer le favori « '+$name+' » ? Aucun poste ne sera modifié.') -Confirm $true)){return}
            Save-PestoPreparations -Items @(@($items|Where-Object{$_.Name -ine $name})+@([pscustomobject]@{Name=$name;Value=$favorite}))
            Add-LogLine 'Préparation mémorisée, sans cible, numéro, compte ni redémarrage.' 'info';return
        }
        if(-not $list.SelectedItem){throw 'Choisissez un favori.'}
        $favorite=ConvertTo-PestoPreparation $list.SelectedItem.Value
        if($favorite.Domain -ine $script:DOMAINE -or $favorite.ConfigStamp -cne (Get-PestoConfigurationSignature $script:CFG)){throw 'Domaine ou politique modifiés : contrôlez puis recréez ce favori.'}
        if($favorite.Org -notin @($CbOrg.Items) -or $favorite.Type -notin @($CbType.Items) -or $favorite.Site -notin @($script:Sites[$favorite.Org])){throw 'Organisme, site ou type indisponible.'}
        $CbOrg.SelectedItem=$favorite.Org
        if($favorite.Site -notin @($CbSite.Items)){throw 'Le site du favori n''est plus sélectionnable.'}
        $CbSite.SelectedItem=$favorite.Site;$CbService.Text=$favorite.Service;$CbType.SelectedItem=$favorite.Type
        $script:DirectCheckedKey=''
        Add-LogLine 'Favori appliqué au brouillon. Vérifier le nom et les impacts avant exécution.' 'info'
    }catch{Show-MsgWarning (Protect-PestoLogText $_.Exception.Message)}
}

function Initialize-PestoPreparationUI {
    $button=$Win.FindName('PrepScenario');if($button){$button.Add_Click([Windows.RoutedEventHandler]${function:Show-PestoScenarioFields})}
    foreach($name in @('PrepImportCollection','PrepExportCollection')){$button=$Win.FindName($name);if($button){$button.Add_Click([Windows.RoutedEventHandler]${function:Invoke-PestoPreparationExchange})}}
    foreach($name in @('PrepSave','PrepRestore','PrepClear')){
        $button=$Win.FindName($name)
        if($button){$button.Add_Click([Windows.RoutedEventHandler]${function:Invoke-PestoPreparationCommand})}
    }
    Update-PestoPreparationList
}

function ConvertTo-PestoPreparationBundle {
    param($Value)
    Assert-PestoClosedObject $Value @('Schema','Favorites','Drafts') @('Schema','Favorites','Drafts')
    if(($Value.Schema -isnot [int] -and $Value.Schema -isnot [long]) -or $Value.Schema -ne 1 -or @($Value.Favorites).Count -gt 20 -or @($Value.Drafts).Count -gt 20){throw 'Collection de préparations invalide.'}
    $seen=@{};$favorites=@(foreach($entry in @($Value.Favorites)){Assert-PestoClosedObject $entry @('Name','Value') @('Name','Value');if($entry.Name -isnot [string] -or -not$entry.Name.Trim() -or $entry.Name.Length -gt 64 -or $entry.Name -match '[\x00-\x1f]' -or $seen.ContainsKey($entry.Name)){throw 'Nom de favori invalide.'};$seen[$entry.Name]=$true;[pscustomobject]@{Name=$entry.Name;Value=(ConvertTo-PestoPreparation $entry.Value)}})
    $drafts=@(ConvertTo-PestoDraftCollection ([pscustomobject]@{Schema=1;Drafts=@($Value.Drafts)}))
    return [pscustomobject]@{Schema=1;Favorites=$favorites;Drafts=$drafts}
}
function Get-PestoPreparationCompatibility {
    param($Bundle,[string]$Domain,[string]$ConfigStamp)
    foreach($group in @(@('Favori','Favorites','Value'),@('Brouillon','Drafts','Draft'))){foreach($item in @($Bundle.($group[1]))){$data=$item.($group[2]);$valid=($data.Domain -ieq $Domain -and $data.ConfigStamp -ceq $ConfigStamp);[pscustomobject]@{Type=$group[0];Name=$item.Name;Domain=$data.Domain;Compatible=$valid;Etat=$(if($valid){'Compatible'}else{'À recréer : domaine ou configuration différent'});Item=$item}}}
}
function Invoke-PestoPreparationExchange {
    param($Sender,$EventArgs)
    try{
        if($script:Running -or $script:DirectBusy -or $script:JoinBusy -or $script:PreflightRunning -or $script:CfgRestartRequired){throw 'Terminez le traitement avant de modifier les préparations.'}
        $current=ConvertTo-PestoPreparationBundle ([pscustomobject]@{Schema=1;Favorites=@(Read-PestoPreparations);Drafts=@(Read-PestoDraftCollection)})
        if($Sender.Name -eq 'PrepExportCollection'){
            $text=$current|ConvertTo-Json -Depth 12
            $p=Show-PestoPanel -Title 'Partager les préparations' -Body $text -AcceptText 'Choisir un fichier' -Monospace;if(-not$p.Accepted){return}
            $dialog=[Microsoft.Win32.SaveFileDialog]::new();$dialog.Filter='Collection Pesto JSON (*.json)|*.json';$dialog.FileName='Pesto-preparations.json';if($dialog.ShowDialog($Win)){Write-PestoNewExport $dialog.FileName $text};return
        }
        $dialog=[Microsoft.Win32.OpenFileDialog]::new();$dialog.Filter='Collection Pesto JSON (*.json)|*.json';if(-not$dialog.ShowDialog($Win)){return};Assert-PestoPlainPath $dialog.FileName;if((Get-Item -LiteralPath $dialog.FileName).Length -gt 1MB){throw 'Collection trop volumineuse.'}
        $bundle=ConvertTo-PestoPreparationBundle ([IO.File]::ReadAllText($dialog.FileName,[Text.UTF8Encoding]::new($false,$true))|ConvertFrom-Json)
        $rows=@(Get-PestoPreparationCompatibility $bundle $script:DOMAINE (Get-PestoConfigurationSignature $script:CFG));[void](Show-PestoChoiceTable -Title 'Compatibilité des préparations' -Description 'Seules les entrées du même domaine et de la même configuration sont importables. Les autres restent dans le fichier, sans modification.' -Rows $rows -Columns @(@{Key='Type';Label='Type'},@{Key='Name';Label='Nom'},@{Key='Domain';Label='Domaine'},@{Key='Etat';Label='Compatibilité'}))
        $compatible=@($rows|Where-Object{$_.Compatible});if(-not$compatible.Count){throw 'Aucune préparation compatible à importer.'}
        $favorites=@{};$drafts=@{};foreach($f in $current.Favorites){$favorites[$f.Name]=$f};foreach($d in $current.Drafts){$drafts[$d.Name]=$d};$replaced=[Collections.Generic.List[string]]::new()
        foreach($row in $compatible){$target=if($row.Type -eq 'Favori'){$favorites}else{$drafts};if($target.ContainsKey($row.Name)){$replaced.Add($row.Type+' : '+$row.Name)};$target[$row.Name]=$row.Item}
        $safe=ConvertTo-PestoPreparationBundle ([pscustomobject]@{Schema=1;Favorites=@($favorites.Values|Sort-Object Name);Drafts=@($drafts.Values|Sort-Object Name)})
        $message=[string]$compatible.Count+' entrée(s) compatibles. '+$replaced.Count+" remplacement(s) :`n"+($replaced -join "`n")+"`nAucun champ de formulaire, redémarrage ou accord ne sera appliqué."
        if(-not(Confirm-YesNo -Msg $message -Confirm $true -AcceptText 'Importer ces préparations')){return}
        $favoriteText=[pscustomobject]@{Schema=2;Favorites=$safe.Favorites}|ConvertTo-Json -Depth 8 -Compress;$draftText=[pscustomobject]@{Schema=1;Drafts=$safe.Drafts}|ConvertTo-Json -Depth 12 -Compress
        if($favoriteText.Length -gt 32768 -or $draftText.Length -gt 262144){throw 'La collection fusionnée dépasse la capacité des préférences.'}
        if($script:SIM -or $script:GUI){$script:PestoPrepMemory=$favoriteText;$script:PestoDraftsMemory=$draftText}
        else{$oldFavorites=Get-PestoAppearanceValue -Name 'Preparation';$oldDrafts=Get-PestoAppearanceValue -Name 'Drafts';try{Set-PestoAppearanceValue -Name 'Preparation' -Value $favoriteText;Set-PestoAppearanceValue -Name 'Drafts' -Value $draftText}catch{$original=$_;try{Set-PestoAppearanceValue -Name 'Preparation' -Value $oldFavorites;Set-PestoAppearanceValue -Name 'Drafts' -Value $oldDrafts}catch{throw 'Import interrompu et restauration des préférences impossible. Conservez le fichier exporté et relisez les préparations avant utilisation.'};throw $original}}
        Update-PestoPreparationList;Show-MsgInfo 'Préparations importées. Chaque reprise relira le poste et invalidera les anciens contrôles.'
    }catch{Show-MsgWarning $_.Exception.Message}
}

function Show-PestoScenarioFields {
    try{
        $s=(ConvertTo-PestoPolicy $script:PestoPolicy).Scenario
        if(-not $s){Show-MsgInfo 'Aucun scenario administre configure.';return}
        $rows=@(foreach($field in @('Type','SiteCode','ServiceCode','TargetOU')){
            [pscustomobject]@{Champ=$field;Obligatoire=($field -cin @($s.Required));Autorise=(@($s.Allowed.$field) -join ', ');Verrou=[string]$s.Locked.$field}
        })
        [void](Show-PestoChoiceTable -Title ('Scenario : '+$s.Name) -Description 'Contraintes appliquees aux champs de preparation et controlees a nouveau avant toute commande.' -Rows $rows -Columns @(@{Key='Champ';Label='Champ'},@{Key='Obligatoire';Label='Obligatoire'},@{Key='Autorise';Label='Valeurs autorisees'},@{Key='Verrou';Label='Valeur verrouillee'}))
    }catch{Show-MsgWarning $_.Exception.Message}
}
