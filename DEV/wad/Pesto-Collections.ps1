#requires -Version 5.1
# Vues et collections : filtres et identités observées, jamais accords d'exécution.
function ConvertTo-PestoSavedViews {
    param($Value)
    Assert-PestoClosedObject $Value @('Schema','Views') @('Schema','Views')
    if(($Value.Schema -isnot [int] -and $Value.Schema -isnot [long]) -or $Value.Schema -ne 1 -or @($Value.Views).Count -gt 30){throw 'Collection de vues invalide (30 maximum).'}
    $seen=@{}
    foreach($v in @($Value.Views)){
        Assert-PestoClosedObject $v @('Name','Table','Search','Filter','Site','Service','Type','ShowAll','Sort') @('Name','Table','Search','Filter','Sort')
        if($v.Name -isnot [string] -or -not$v.Name.Trim() -or $v.Name.Length -gt 64 -or $v.Name -match '[\x00-\x1f]' -or $v.Table -notin @('queue','names','interventions') -or $seen.ContainsKey($v.Table+'/'+$v.Name)){throw 'Nom ou tableau de vue invalide.'};$seen[$v.Table+'/'+$v.Name]=$true
        foreach($key in @('Search','Filter','Site','Service','Type')){if($null -ne $v.$key -and ($v.$key -isnot [string] -or $v.$key.Length -gt 256 -or $v.$key -match '[\x00-\x1f]')){throw 'Filtre de vue invalide.'}}
        if($null -ne $v.ShowAll -and $v.ShowAll -isnot [bool]){throw 'Option de vue invalide.'}
        if(@($v.Sort).Count -gt 4){throw 'Quatre critères de tri maximum.'}
        foreach($sort in @($v.Sort)){Assert-PestoClosedObject $sort @('Property','Direction') @('Property','Direction');if($sort.Property -notmatch '^[A-Za-z_][A-Za-z0-9_]{0,80}$' -or $sort.Direction -notin @('Ascending','Descending')){throw 'Tri non pris en charge.'}}
        $v
    }
}
function Read-PestoSavedViews {
    $text=if($script:SIM -or $script:GUI){$script:PestoViewsMemory}else{Get-PestoAppearanceValue -Name 'Views'}
    if(-not$text){return @()};if($text.Length -gt 65536){throw 'Vues enregistrées trop volumineuses.'};return @(ConvertTo-PestoSavedViews ($text|ConvertFrom-Json))
}
function Save-PestoSavedViews {
    param([object[]]$Views)
    $items=@(ConvertTo-PestoSavedViews ([pscustomobject]@{Schema=1;Views=@($Views)}));$text=[pscustomobject]@{Schema=1;Views=$items}|ConvertTo-Json -Depth 8 -Compress
    if($text.Length -gt 65536){throw 'Vues trop volumineuses.'};if($script:SIM -or $script:GUI){$script:PestoViewsMemory=$text}else{Set-PestoAppearanceValue -Name 'Views' -Value $text}
}
function Get-PestoCurrentView {
    param([ValidateSet('queue','names','interventions')][string]$Id,[string]$Name)
    $v=[ordered]@{Name=$Name;Table=$Id;Search='';Filter='';Site='';Service='';Type='';ShowAll=$false;Sort=@()}
    switch($Id){
        'queue'{$v.Search=[string]$TxtQueueSearch.Text;$v.Filter=[string]$CmbQueueFilter.SelectedItem}
        'names'{$v.Search=[string]$NmTxtSearch.Text;$v.Filter=[string]$NmCmbStatut.SelectedItem;$v.Site=[string]$NmCmbSite.SelectedItem;$v.Service=[string]$NmCmbEquipe.SelectedItem;$v.Type=[string]$NmCmbType.SelectedItem;$v.ShowAll=[bool]$NmChkAll.IsChecked}
        'interventions'{$v.Search=[string]$script:InterventionsUi.Window.FindName('LedgerSearch').Text;$v.Filter=[string]$script:InterventionsUi.Window.FindName('LedgerState').SelectedItem.Tag}
    }
    if($script:PestoTables[$Id]){$v.Sort=@(@(foreach($s in $script:PestoTables[$Id].Grid.Items.SortDescriptions){[pscustomobject]@{Property=$s.PropertyName;Direction=[string]$s.Direction}})|Select-Object -First 4)}
    [pscustomobject]$v
}
function Set-PestoSavedView {
    param($View)
    [void]@(ConvertTo-PestoSavedViews ([pscustomobject]@{Schema=1;Views=@($View)}))
    if(-not$script:PestoTables[$View.Table]){throw 'Le tableau doit être ouvert avant de restaurer sa vue.'}
    $grid=$script:PestoTables[$View.Table].Grid;$keys=$script:PestoTables[$View.Table].Keys
    foreach($sort in @($View.Sort)){if($sort.Property -notin $keys){throw 'Le tableau a changé : critère de tri absent. Recréez cette vue.'}}
    switch($View.Table){
        'queue'{if($View.Filter -notin @($CmbQueueFilter.Items)){throw 'Filtre de file inconnu.'};$TxtQueueSearch.Text=$View.Search;$CmbQueueFilter.SelectedItem=$View.Filter;Update-PestoQueueFilter}
        'names'{foreach($pair in @(@($NmCmbStatut,$View.Filter),@($NmCmbSite,$View.Site),@($NmCmbEquipe,$View.Service),@($NmCmbType,$View.Type))){if($pair[1] -notin @($pair[0].Items)){throw 'Le filtre enregistré ne fait plus partie du catalogue. Actualisez ou recréez la vue.'}};$script:SuspendNm=$true;try{$NmTxtSearch.Text=$View.Search;$NmCmbStatut.SelectedItem=$View.Filter;$NmCmbSite.SelectedItem=$View.Site;$NmCmbEquipe.SelectedItem=$View.Service;$NmCmbType.SelectedItem=$View.Type;$NmChkAll.IsChecked=[bool]$View.ShowAll}finally{$script:SuspendNm=$false};$script:PestoNamesViewSort=@($View.Sort);Update-NameGrid}
        'interventions'{$ui=$script:InterventionsUi;$item=@($ui.Window.FindName('LedgerState').Items|Where-Object{[string]$_.Tag -ceq $View.Filter});if($item.Count -ne 1){throw 'Filtre de suivi inconnu.'};$ui.Window.FindName('LedgerSearch').Text=$View.Search;$ui.Window.FindName('LedgerState').SelectedItem=$item[0];$ui.Offset=0;Update-PestoInterventionPage}
    }
    $grid.Items.SortDescriptions.Clear();foreach($sort in @($View.Sort)){$grid.Items.SortDescriptions.Add([ComponentModel.SortDescription]::new($sort.Property,([ComponentModel.ListSortDirection][Enum]::Parse([ComponentModel.ListSortDirection],$sort.Direction))))}
    # Les cases Traiter, lignes sélectionnées, résultats et contrôles ne sont pas lus ni modifiés.
}
function Set-PestoColumnPreset {
    param([ValidateSet('queue','names','interventions')][string]$Id,[ValidateSet('Essential','Diagnostic')][string]$Preset)
    if(-not$script:PestoTables[$Id]){return};$t=$script:PestoTables[$Id]
    $essential=switch($Id){'queue'{@('Nom_du_PC','Nouveau_Nom','Statut','Plan','Precontrole')};'names'{@('Nom','Statut','Site','Equipe')};'interventions'{@('UpdatedLocal','Computer','NewName','StatusLabel','NextAction')}}
    for($i=0;$i -lt $t.Grid.Columns.Count;$i++){$t.Grid.Columns[$i].Visibility=if($Preset -eq 'Diagnostic' -or $i -lt $t.Fixed -or $t.Keys[$i] -in $essential){'Visible'}else{'Collapsed'}}
}
function Get-PestoQueueGroupedRows {
    param([Data.DataTable]$Table,[ValidateSet('Site','Organisme','Statut')][string]$By='Site')
    $i=0;foreach($row in $Table.Rows){$i++;[pscustomobject]@{Groupe=$(if($row[$By]){[string]$row[$By]}else{'Non renseigné'});Ordre=$i;Poste=[string]$row.Nom_du_PC;NomPrevu=[string]$row.Nouveau_Nom;Plan=[string]$row.Plan;Etat=[string]$row.Statut}}
}
function Invoke-PestoViewTool {
    param([ValidateSet('queue','names','interventions')][string]$Id)
    $choices=@([pscustomobject]@{Id='save';Label='Enregistrer cette vue'},[pscustomobject]@{Id='load';Label='Restaurer une vue'},[pscustomobject]@{Id='delete';Label='Supprimer une vue'},[pscustomobject]@{Id='essential';Label='Colonnes : Essentiel'},[pscustomobject]@{Id='diagnostic';Label='Colonnes : Diagnostic'})
    if($Id -eq 'queue'){$choices+= [pscustomobject]@{Id='group';Label='Regrouper la file sans changer son ordre'}}
    $r=Show-PestoPanel -Title 'Présentation du tableau' -Body 'Vues personnelles : filtres et tri seulement. Aucun consentement, sélection exécutante ou résultat n''est enregistré.' -Choices $choices -AcceptText 'Continuer';if(-not$r.Accepted){return}
    if($r.Selected.Id -in @('essential','diagnostic')){Set-PestoColumnPreset $Id $(if($r.Selected.Id -eq 'essential'){'Essential'}else{'Diagnostic'});return}
    if($r.Selected.Id -eq 'group'){$by=Show-PestoPanel -Title 'Regrouper par' -Body 'Le numéro de ligne rappelle l''ordre réel d''exécution, inchangé par cette vue.' -Choices @(foreach($key in @('Site','Organisme','Statut')){[pscustomobject]@{Label=$key;Key=$key}}) -AcceptText 'Afficher';if($by.Accepted){[void](Show-PestoChoiceTable -Title 'File regroupée' -Description 'Vue de lecture seulement. L''ordre de la file et les cases à traiter restent inchangés.' -Rows @(Get-PestoQueueGroupedRows $script:table $by.Selected.Key|Sort-Object Groupe,Ordre) -Columns @(@{Key='Groupe';Label='Groupe'},@{Key='Ordre';Label='Ordre réel'},@{Key='Poste';Label='Poste'},@{Key='NomPrevu';Label='Nom prévu'},@{Key='Plan';Label='Plan'},@{Key='Etat';Label='État'}) -GroupBy 'Groupe')};return}
    $views=@(Read-PestoSavedViews)
    if($r.Selected.Id -eq 'save'){$name=Show-PestoPanel -Title 'Nommer la vue' -InputLabel 'Nom (64 caractères maximum)' -AcceptText 'Enregistrer';if(-not$name.Accepted){return};$v=Get-PestoCurrentView $Id $name.Text.Trim();if(@($views|Where-Object{$_.Table -eq $Id -and $_.Name -ieq $v.Name}).Count -and -not(Confirm-YesNo -Msg ('Remplacer la vue « '+$v.Name+' » ?') -Confirm $true -AcceptText 'Remplacer')){return};Save-PestoSavedViews @(@($views|Where-Object{-not($_.Table -eq $Id -and $_.Name -ieq $v.Name)})+@($v));return}
    $pick=Show-PestoChoiceTable -Title 'Vues enregistrées' -Description 'Seules les vues de ce tableau sont proposées.' -Rows @($views|Where-Object{$_.Table -eq $Id}) -Columns @(@{Key='Name';Label='Nom'},@{Key='Search';Label='Recherche'},@{Key='Filter';Label='Filtre'}) -AcceptText $(if($r.Selected.Id -eq 'delete'){'Supprimer cette vue'}else{'Appliquer cette vue'})
    if($pick.Accepted){$v=$pick.Items[0];if($r.Selected.Id -eq 'delete'){Save-PestoSavedViews @($views|Where-Object{-not($_.Table -eq $Id -and $_.Name -ieq $v.Name)})}else{Set-PestoSavedView $v}}
}
function ConvertTo-PestoDynamicCollections {
    param($Value)
    Assert-PestoClosedObject $Value @('Schema','Collections') @('Schema','Collections');if(($Value.Schema -isnot [int] -and $Value.Schema -isnot [long]) -or $Value.Schema -ne 1 -or @($Value.Collections).Count -gt 20){throw 'Collections invalides (20 maximum).'};$seen=@{}
    foreach($c in @($Value.Collections)){
        Assert-PestoClosedObject $c @('Name','Domain','ConfigStamp','Query','Baseline','ObservedUtc') @('Name','Domain','ConfigStamp','Query','Baseline','ObservedUtc')
        if($c.Name -isnot [string] -or -not$c.Name -or $c.Name.Length -gt 64 -or $c.Name -match '[\x00-\x1f]' -or $seen.ContainsKey($c.Name) -or -not(Test-PestoDnsName $c.Domain) -or $c.ConfigStamp -notmatch '^[a-fA-F0-9]{64}$'){throw 'Identité de collection invalide.'};$seen[$c.Name]=$true
        Assert-PestoClosedObject $c.Query @('Search','Site','Service','Type') @('Search','Site','Service','Type')
        foreach($k in @('Search','Site','Service','Type')){if($c.Query.$k -isnot [string] -or $c.Query.$k.Length -gt 128 -or $c.Query.$k -match '[\x00-\x1f]'){throw 'Critère de collection invalide.'}}
        if($c.Query.Site -and $c.Query.Site -notmatch '^[A-Z]{2}$'){throw 'Code de site invalide.'};if($c.Query.Service -and $c.Query.Service -notmatch '^[A-Z0-9]{3}$'){throw 'Code de service invalide.'};if($c.Query.Type -notin @('','P','S','V')){throw 'Type de collection invalide.'}
        if(@($c.Baseline).Count -gt 5000){throw 'Instantané de collection trop volumineux.'};$ids=@{}
        foreach($m in @($c.Baseline)){Assert-PestoClosedObject $m @('Guid','Name','DN') @('Guid','Name','DN');$g=[Guid]::Empty;if(-not[Guid]::TryParse([string]$m.Guid,[ref]$g) -or $g -eq [Guid]::Empty -or $ids.ContainsKey($g.ToString()) -or -not(Test-PestoComputerName $m.Name) -or $m.DN -isnot [string] -or $m.DN.Length -gt 4096 -or $m.DN -match '[\x00-\x1f]'){throw 'Identité de membre invalide.'};$ids[$g.ToString()]=$true}
        if($c.ObservedUtc){$utc=[DateTimeOffset]::MinValue;if($c.ObservedUtc -is [datetime]){$utc=[DateTimeOffset]::new($c.ObservedUtc.ToUniversalTime())}elseif(-not[DateTimeOffset]::TryParse([string]$c.ObservedUtc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$utc)){throw 'Date de collection invalide.'};$c=$c.PSObject.Copy();$c.ObservedUtc=$utc.ToUniversalTime().ToString('o')}
        $c
    }
}
function Read-PestoDynamicCollections {
    $text=if($script:SIM -or $script:GUI){$script:PestoCollectionsMemory}else{Get-PestoAppearanceValue -Name 'Collections'};if(-not$text){return @()};if($text.Length -gt 1048576){throw 'Collections trop volumineuses.'};return @(ConvertTo-PestoDynamicCollections ($text|ConvertFrom-Json))
}
function Save-PestoDynamicCollections {
    param([object[]]$Items)
    $items=@(ConvertTo-PestoDynamicCollections ([pscustomobject]@{Schema=1;Collections=@($Items)}));$text=[pscustomobject]@{Schema=1;Collections=$items}|ConvertTo-Json -Depth 10 -Compress;if($text.Length -gt 1048576){throw 'Collections trop volumineuses (1 Mio maximum).'};if($script:SIM -or $script:GUI){$script:PestoCollectionsMemory=$text}else{Set-PestoAppearanceValue -Name 'Collections' -Value $text}
}
function Get-PestoDynamicMembers {
    param($Query,[object[]]$Computers,[string]$Prefix)
    $seen=@{};$count=0;$search=ConvertTo-PestoSearchText $Query.Search
    foreach($pc in $Computers){$parts=ConvertTo-PestoNameParts ([string]$pc.Name) $Prefix;if(-not$parts){continue};if($Query.Site -and $parts.Site -ine $Query.Site){continue};if($Query.Service -and $parts.Service -ine $Query.Service){continue};if($Query.Type -and $parts.Type -ine $Query.Type){continue};if($search -and -not(ConvertTo-PestoSearchText $pc.Name).Contains($search)){continue}
        $g=[Guid]::Empty;if(-not[Guid]::TryParse([string]$pc.ObjectGUID,[ref]$g) -or $g -eq [Guid]::Empty){throw 'Identité AD manquante dans le cache : actualisez l''inventaire avant de figer la collection.'};if($seen.ContainsKey($g.ToString())){throw 'Identité AD dupliquée dans le cache.'};$seen[$g.ToString()]=$true
        $count++;if($count -gt 5000){throw 'Plus de 5 000 membres : réduisez les filtres.'};[pscustomobject]@{Guid=$g.ToString('D');Name=[string]$pc.Name;DN=[string]$pc.DistinguishedName}
    }
}
function Compare-PestoDynamicMembers {
    param([object[]]$Before,[object[]]$After)
    $a=@{};$b=@{};foreach($m in $Before){$a[[string]$m.Guid]=$m};foreach($m in $After){$b[[string]$m.Guid]=$m}
    foreach($id in @($b.Keys|Sort-Object)){if(-not$a.ContainsKey($id)){[pscustomobject]@{Etat='Ajouté';Avant='';Apres=$b[$id].Name;Guid=$id;OU=$b[$id].DN}}elseif($a[$id].Name -ine $b[$id].Name -or $a[$id].DN -ine $b[$id].DN){[pscustomobject]@{Etat='Nom ou emplacement changé';Avant=$a[$id].Name;Apres=$b[$id].Name;Guid=$id;OU=$b[$id].DN}}}
    foreach($id in @($a.Keys|Sort-Object)){if(-not$b.ContainsKey($id)){[pscustomobject]@{Etat='Absent du périmètre';Avant=$a[$id].Name;Apres='';Guid=$id;OU=$a[$id].DN}}}
}
function Invoke-PestoCollectionTool {
    param($Sender,$EventArgs)
    try{
        if(-not$script:InventoryLoaded){throw 'Actualisez volontairement l''inventaire avant de travailler sur une collection.'}
        $items=@(Read-PestoDynamicCollections);$stamp=Get-PestoConfigurationSignature $script:CFG
        if($Sender.Name -eq 'NmSaveCollection'){
            $name=Show-PestoPanel -Title 'Mémoriser les filtres comme collection' -Body 'La collection retient recherche, type, site et service. Elle contient uniquement les postes déjà observés dans AD ; le filtre de disponibilité ne crée pas de machine. Chaque futur lot montrera son delta avant d''être figé.' -InputLabel 'Nom de la collection' -AcceptText 'Enregistrer'
            if(-not$name.Accepted){return};$query=[pscustomobject]@{Search=[string]$NmTxtSearch.Text;Site=$(if($NmCmbSite.SelectedItem -eq '(tous)'){''}else{[string]$NmCmbSite.SelectedItem});Service=$(if($NmCmbEquipe.SelectedItem -eq '(tous)'){''}else{[string]$NmCmbEquipe.SelectedItem});Type=$(switch([string]$NmCmbType.SelectedItem){'Portable'{'P'};'Fixe'{'S'};'Virtuel'{'V'};default{''}})}
            $members=@(Get-PestoDynamicMembers $query @($script:ComputersNoms) $script:PREFIXE);$c=[pscustomobject]@{Name=$name.Text.Trim();Domain=$script:DOMAINE;ConfigStamp=$stamp;Query=$query;Baseline=$members;ObservedUtc=[string]$script:InventoryUtc}
            if(@($items|Where-Object{$_.Name -ieq $c.Name}).Count -and -not(Confirm-YesNo -Msg ('Remplacer la collection « '+$c.Name+' » ?') -Confirm $true -AcceptText 'Remplacer')){return};Save-PestoDynamicCollections @(@($items|Where-Object{$_.Name -ine $c.Name})+@($c));return
        }
        $choice=Show-PestoChoiceTable -Title 'Collections enregistrées' -Description 'Le cache existant sera évalué avec les critères enregistrés. Aucune recherche AD silencieuse et aucune ligne exécutée.' -Rows $items -Columns @(@{Key='Name';Label='Collection'},@{Key='Domain';Label='Domaine'},@{Key='ObservedUtc';Label='Dernier instantané'}) -AcceptText 'Examiner cette collection' -SecondaryText 'Supprimer la collection';if(-not$choice.Accepted){return};$c=$choice.Items[0]
        if($choice.Secondary){if(Confirm-YesNo -Msg ('Supprimer uniquement les critères enregistrés de « '+$c.Name+' » ? Aucun poste ou reçu ne sera supprimé.') -Confirm $true -AcceptText 'Supprimer la collection'){Save-PestoDynamicCollections @($items|Where-Object{$_.Name -ine $c.Name})};return}
        if($c.Domain -ine $script:DOMAINE -or $c.ConfigStamp -cne $stamp){throw 'Domaine ou configuration différents : recréez cette collection après avoir revu les filtres.'}
        $inventory=[string]$script:InventoryUtc;$members=@(Get-PestoDynamicMembers $c.Query @($script:ComputersNoms) $script:PREFIXE);$delta=@(Compare-PestoDynamicMembers $c.Baseline $members)
        [void](Show-PestoChoiceTable -Title 'Changements de la collection' -Description ($members.Count.ToString()+' membre(s) actuels. '+$delta.Count+' changement(s) depuis '+$c.ObservedUtc+'. Un objet absent du périmètre n''est pas nécessairement supprimé.') -Rows $delta -Columns @(@{Key='Etat';Label='Changement'},@{Key='Avant';Label='Avant'},@{Key='Apres';Label='Après'},@{Key='OU';Label='OU actuelle'}))
        $limit=(ConvertTo-PestoPolicy $script:CFG.POLICY).MaxBatch;if(-not$members.Count -or $members.Count -gt $limit){Show-MsgInfo ('Collection consultée. Pour préparer un lot, filtrez entre 1 et '+$limit+' postes. Aucun ajout partiel.');return}
        $plan=Show-PestoPanel -Title 'Figer la collection pour ce lot' -Body (($members.Name -join "`n")+"`n`nInstantané : "+$inventory+"`nLa liste ne changera plus pendant la préparation. Aucune case cochée ni commande lancée.") -AcceptText 'Choisir la destination du lot'
        if(-not$plan.Accepted){return};if($inventory -cne [string]$script:InventoryUtc -or $stamp -cne (Get-PestoConfigurationSignature $script:CFG)){throw 'Le contexte a changé. Réexaminez le delta.'}
        $c.Baseline=$members;$c.ObservedUtc=$inventory;Save-PestoDynamicCollections $items
        Show-PestoBulkPlanner -SourceNames @($members.Name)
    }catch{Show-MsgWarning $_.Exception.Message}
}
function Initialize-PestoCollections {
    foreach($pair in @(@('QueueViews','queue'),@('NmViews','names'))){$b=$Win.FindName($pair[0]);if($b){$b.Tag=$pair[1];$b.Add_Click({param($s,$e);try{Invoke-PestoViewTool $s.Tag}catch{Show-MsgWarning $_.Exception.Message}})}}
    foreach($name in @('NmSaveCollection','QueueCollection')){$b=$Win.FindName($name);if($b){$b.Add_Click([Windows.RoutedEventHandler]${function:Invoke-PestoCollectionTool})}}
}

function Get-PestoGridRowId {
    <# La clé stable est le seul moyen de retrouver une ligne après projection : sans elle, rien ne
       distingue un déplacement d'un remplacement, et la sélection retomberait sur un index.
       L'indexeur de PSObject.Properties remplace l'énumération de toutes les propriétés : cette lookup
       est payée une fois par ligne projetée, et l'énumération la payait sept fois. Le nom reste comparé
       à l'ordinal près, donc une propriété dont seule la casse diffère est refusée comme avant. #>
    param($Row,[Parameter(Mandatory=$true)][string]$IdProperty)
    if($null -eq $Row){throw 'Ligne de tableau absente.'}
    $property=$Row.PSObject.Properties[$IdProperty]
    if($null -eq $property -or $property.Name -cne $IdProperty){throw ('Identité de ligne absente : '+$IdProperty+'.')}
    $value=$property.Value
    if($null -eq $value){throw ('Identité de ligne absente : '+$IdProperty+'.')}
    $text=[string]$value
    if(-not $text){throw ('Identité de ligne vide : '+$IdProperty+'.')}
    return $text
}

function New-PestoGridRowCollection {
    <# ObservableCollection : seule source qui notifie WPF ligne par ligne. Un tableau assigné en
       entier recrée chaque conteneur de ligne, ce que cette mise à jour doit justement éviter. #>
    param([object[]]$Rows=@())
    $collection=[Collections.ObjectModel.ObservableCollection[object]]::new()
    foreach($row in @($Rows)){[void]$collection.Add($row)}
    return ,$collection
}

function Update-PestoGridRows {
    <# Ne remplace que les lignes dont le contenu a changé. Les lignes inchangées gardent leur
       conteneur WPF (aucune notification, donc ni recréation ni disposition), la sélection est rendue
       par identité et non par index, et le tri porté par la vue est restitué s'il a été perdu.
       L'empreinte d'une ligne est son hash canonique complet, reçu compris : un champ que seule une
       action relit (tâches, acquittement) force donc bien le remplacement. Elle n'est calculée que
       pour les lignes projetées à nouveau, jamais pour celles déjà rendues, d'où la comparaison
       d'abord par référence. Au-delà de la borne, une seule liaison complète coûte moins cher que
       mille notifications : c'est le repli, pas le chemin ordinaire. #>
    param($Grid,[object[]]$Rows=@(),[string]$IdProperty='RowId',[int]$MaximumInPlaceOperations=256)
    if(-not $Grid){throw 'Tableau WPF requis.'}
    if(-not $IdProperty){throw 'Propriété d''identité de ligne requise.'}
    if($MaximumInPlaceOperations -lt 1){throw 'Borne de mise à jour en place invalide.'}
    if($null -eq $Grid.Items -or $null -eq $Grid.Items.SortDescriptions){throw 'Le tableau n''expose pas de vue de tri.'}
    $next=[Collections.Generic.List[object]]::new();foreach($row in @($Rows)){[void]$next.Add($row)}
    $sort=@($Grid.Items.SortDescriptions)
    $selectedId=$null
    if($null -ne $Grid.SelectedItem){$selectedId=Get-PestoGridRowId -Row $Grid.SelectedItem -IdProperty $IdProperty}

    function Publish-PestoGridRowsInner {
        param([object[]]$Items)
        $fresh=@{}
        $collection=New-PestoGridRowCollection -Rows $Items
        foreach($row in $collection){$fresh[(Get-PestoGridRowId -Row $row -IdProperty $IdProperty)]=Get-PestoStableHash $row}
        # -InputObject et jamais le pipeline : pipe enverrait la note sur chaque ligne, ce qui rend le
        # cache illisible (le collecteur remonte un tableau par énumération de membres) et fait
        # remplacer toute la page reprojetée, le contraire même de ce que ce chemin doit éviter.
        [void](Add-Member -InputObject $collection -NotePropertyName PestoRowFingerprints -NotePropertyValue $fresh -Force)
        $Grid.ItemsSource=$collection
    }

    $source=$Grid.ItemsSource
    $rebound=$true;$replaced=0;$inserted=0;$removed=0;$moved=0;$unchanged=0;$operations=0
    $fingerprints=@{}
    $liveIds=$null;$positions=$null
    if($source -is [Collections.IList] -and $source -is [Collections.Specialized.INotifyCollectionChanged]){
        $stored=$source.PestoRowFingerprints
        $cached=$stored -is [hashtable]
        if($cached){$fingerprints=$stored}
        # L'identité n'est lue qu'une fois de chaque côté et conservée dans un tableau parallèle aux
        # lignes. Elle était relue à chaque phase, sept fois par ligne affichée : la page payait son
        # prix complet même pour une seule ligne changée, soit exactement ce que ce chemin évite.
        $sourceIds=[Collections.Generic.List[string]]::new()
        $seen=@{}
        for($i=0;$i -lt $source.Count;$i++){
            $id=Get-PestoGridRowId -Row $source[$i] -IdProperty $IdProperty
            if($seen.ContainsKey($id)){throw ('Identité de ligne dupliquée dans le tableau : '+$id)}
            $seen[$id]=$true;[void]$sourceIds.Add($id)
        }
        $nextIds=[Collections.Generic.List[string]]::new()
        $wanted=@{}
        for($i=0;$i -lt $next.Count;$i++){
            $id=Get-PestoGridRowId -Row $next[$i] -IdProperty $IdProperty
            if($wanted.ContainsKey($id)){throw ('Identité de ligne dupliquée dans le résultat : '+$id)}
            $wanted[$id]=$true;[void]$nextIds.Add($id)
        }
        $structural=0
        foreach($id in $seen.Keys){if(-not $wanted.ContainsKey($id)){$structural++}}
        foreach($id in $wanted.Keys){if(-not $seen.ContainsKey($id)){$structural++}}
        for($i=0;$i -lt [Math]::Min($nextIds.Count,$sourceIds.Count);$i++){if($sourceIds[$i] -cne $nextIds[$i]){$structural++}}
        if($structural -le $MaximumInPlaceOperations){
            $rebound=$false;$collection=$source
            $liveIds=[Collections.Generic.List[string]]::new();$liveIds.AddRange($sourceIds)
            for($i=$collection.Count-1;$i -ge 0;$i--){
                $id=$liveIds[$i]
                if($wanted.ContainsKey($id)){continue}
                [void]$collection.RemoveAt($i);[void]$liveIds.RemoveAt($i);$removed++;$operations++
                [void]$fingerprints.Remove($id)
            }
            # Les index de position sont rebatis une seule fois, aprs les suppressions : la table
            # tait corrige ligne supprime par ligne, donc chaque suppression relisait toute la page.
            $positions=@{}
            for($i=0;$i -lt $liveIds.Count;$i++){$positions[$liveIds[$i]]=$i}
            for($i=0;$i -lt $next.Count;$i++){
                $id=$nextIds[$i]
                if($i -lt $collection.Count -and $liveIds[$i] -ceq $id){
                    $current=$collection[$i];$target=$next[$i]
                    if([object]::ReferenceEquals($current,$target)){$unchanged++;continue}
                    $hash=Get-PestoStableHash $target
                    # L'empreinte de la ligne rendue est mise en cache sur la collection. Si ce cache
                    # n'a pas survécu, elle est recalculée : le résultat est le même, seul le coût change.
                    $previous=$null
                    if($fingerprints.ContainsKey($id)){$previous=[string]$fingerprints[$id]}else{$previous=Get-PestoStableHash $current}
                    if($previous -ceq $hash){
                        $fingerprints[$id]=$hash;$next[$i]=$current;$unchanged++;continue
                    }
                    $collection[$i]=$target;$fingerprints[$id]=$hash;$replaced++;$operations++;continue
                }
                if($positions.ContainsKey($id)){
                    $from=[int]$positions[$id];$collection.Move($from,$i)
                    [void]$liveIds.RemoveAt($from);[void]$liveIds.Insert($i,$id)
                    for($k=$i;$k -le $from;$k++){$positions[$liveIds[$k]]=$k}
                    $moved++;$operations++
                }else{
                    $target=$next[$i]
                    $collection.Insert($i,$target)
                    [void]$liveIds.Insert($i,$id)
                    for($k=$i;$k -lt $liveIds.Count;$k++){$positions[$liveIds[$k]]=$k}
                    $fingerprints[$id]=Get-PestoStableHash $target
                    $inserted++;$operations++
                }
            }
            while($collection.Count -gt $next.Count){
                $id=$liveIds[$liveIds.Count-1]
                [void]$collection.RemoveAt($collection.Count-1);[void]$liveIds.RemoveAt($liveIds.Count-1);$removed++;$operations++
                [void]$fingerprints.Remove($id);[void]$positions.Remove($id)
            }
            # Une liaison faite hors de ce helper (collection construite par le consommateur lui-meme,
            # ou repli d'un autre chemin) n'a pas de cache : sans pose ici, chaque projection paierait
            # une empreinte par ligne affichée, indéfiniment.
            if(-not $cached){[void](Add-Member -InputObject $collection -NotePropertyName PestoRowFingerprints -NotePropertyValue $fingerprints -Force)}
        }
    }
    if($rebound){$fingerprints=@{};Publish-PestoGridRowsInner -Items @($next.ToArray())}

    $restored=$null
    if($selectedId){
        # Sur le chemin en place, la position de la ligne selectionnee est deja connue : la selection est
        # rendue par identite sans relire toute la page. Le nom est quand meme compare a l'ordinal pres,
        # comme le faisait le parcours, pour ne jamais rendre une ligne dont seule la casse differe.
        if($null -ne $positions -and $positions.ContainsKey($selectedId)){
            $at=[int]$positions[$selectedId]
            if($at -ge 0 -and $at -lt $liveIds.Count -and $liveIds[$at] -ceq $selectedId){$restored=$collection[$at]}
        }
        if($null -eq $restored){
            foreach($row in $Grid.ItemsSource){if((Get-PestoGridRowId -Row $row -IdProperty $IdProperty) -ceq $selectedId){$restored=$row;break}}
        }
    }
    if($null -ne $restored){
        if(-not [object]::ReferenceEquals($Grid.SelectedItem,$restored)){$Grid.SelectedItem=$restored}
        $scroll=$Grid.GetType().GetMethod('ScrollIntoView',[type[]]@([object]))
        if($null -ne $scroll){$Grid.ScrollIntoView($restored)}
    }elseif($null -ne $Grid.SelectedItem){$Grid.SelectedItem=$null}
    $kept=@(foreach($entry in $sort){[string]$entry.PropertyName+'|'+[string]$entry.Direction})
    $rendered=@(foreach($entry in $Grid.Items.SortDescriptions){[string]$entry.PropertyName+'|'+[string]$entry.Direction})
    if(($kept -join ';') -cne ($rendered -join ';')){
        $Grid.Items.SortDescriptions.Clear();foreach($entry in $sort){$Grid.Items.SortDescriptions.Add($entry)}
    }
    [pscustomobject]@{Rebound=$rebound;Replaced=$replaced;Inserted=$inserted;Removed=$removed;Moved=$moved;Unchanged=$unchanged;Operations=$operations;Total=$next.Count}
}
