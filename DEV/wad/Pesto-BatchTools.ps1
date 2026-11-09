#requires -Version 5.1
# Préparation locale de lots. Aucune confirmation d'exécution n'est conservée.
function Get-PestoBulkContext {
    $sites=@(foreach($org in @($script:Sites.Keys|Sort-Object)){foreach($site in @($script:Sites[$org])){$tag=Get-SiteTag $site;$ou=if($site -ieq 'PREPROD'){$script:OU['PREPROD']}elseif($script:OU[$org]){'OU='+(ConvertTo-PestoRdnValue $site)+','+$script:OU[$org]}else{''};if($tag -and (Test-PestoOUInConfiguredScope $ou)){[pscustomobject]@{Organisme=$org;Site=$site;Tag=$tag;TargetOU=$ou}}}})
    $r=Show-PestoChoiceTable -Title 'Destination du lot' -Description 'Choisissez le site cible, indépendamment du formulaire unitaire. Le plan sera construit par lectures ciblées dans l’’AD, puis ajouté décoché.' -Rows $sites -Columns @(@{Key='Organisme';Label='Organisme'},@{Key='Site';Label='Site'},@{Key='TargetOU';Label='OU cible'}) -AcceptText 'Choisir ce site'
    if(-not$r.Accepted){return $null};$site=$r.Items[0]
    $service=Show-PestoPanel -Title 'Modèle du lot' -Body 'Le service peut ensuite être conservé depuis chaque nom source. Le type portable est le repli utilisé seulement si vous décochez « Conserver le type ».' -InputLabel 'Code service (3 caractères)' -InitialValue ([string]$CbService.Text) -AcceptText 'Préparer le lot'
    if(-not$service.Accepted){return $null};if($service.Text.Trim() -notmatch (Get-PestoFacetPattern Service)){throw 'Code service invalide : 3 caractères alphanumériques.'}
    return @{Prefix=$script:PREFIXE;Tag=$site.Tag;Service=$service.Text.Trim().ToUpperInvariant();TargetOU=$site.TargetOU;Site=$site.Site;Organisme=$site.Organisme;TypeLetter='P'}
}
function ConvertFrom-PestoTabularText {
    param([Parameter(Mandatory=$true)][AllowEmptyString()][string]$Text,[char]$Delimiter=[char]0)
    if(-not$Text -or $Text.Length -gt 8388608){throw 'Tableau vide ou supérieur à 8 Mio.'}
    $Text=$Text.TrimStart([char]0xFEFF)
    if($Delimiter -eq [char]0){$head=($Text -split '\r?\n',2)[0];$counts=@(foreach($d in @([char]9,[char]59,[char]44)){[pscustomobject]@{D=$d;Count=@($head.ToCharArray()|Where-Object{$_ -eq $d}).Count}});$Delimiter=($counts|Sort-Object Count -Descending|Select-Object -First 1).D}
    if($Delimiter -notin @([char]9,[char]59,[char]44)){throw 'Séparateur non pris en charge.'}
    $records=[Collections.Generic.List[object]]::new();$cells=[Collections.Generic.List[string]]::new();$cell=[Text.StringBuilder]::new();$quoted=$false;$closed=$false
    for($i=0;$i -lt $Text.Length;$i++){
        $c=$Text[$i]
        if($quoted){if($c -eq [char]34){if($i+1 -lt $Text.Length -and $Text[$i+1] -eq [char]34){[void]$cell.Append([char]34);$i++}else{$quoted=$false;$closed=$true}}else{[void]$cell.Append($c)};continue}
        if($c -eq [char]34){if($cell.Length -or $closed){throw 'Guillemet inattendu dans une cellule.'};$quoted=$true;continue}
        if($closed -and $c -ne $Delimiter -and $c -ne [char]10 -and $c -ne [char]13){throw 'Texte après un guillemet fermant.'}
        if($c -eq $Delimiter){$cells.Add($cell.ToString());[void]$cell.Clear();$closed=$false;if($cells.Count -gt 64){throw '64 colonnes maximum.'};continue}
        if($c -eq [char]10 -or $c -eq [char]13){if($c -eq [char]13 -and $i+1 -lt $Text.Length -and $Text[$i+1] -eq [char]10){$i++};$cells.Add($cell.ToString());[void]$cell.Clear();$closed=$false;if(@($cells|Where-Object{$_}).Count){$records.Add($cells.ToArray())};$cells.Clear();if($records.Count -gt 5001){throw '5 000 lignes maximum.'};continue}
        [void]$cell.Append($c);if($cell.Length -gt 8192){throw 'Cellule trop volumineuse.'}
    }
    if($quoted){throw 'Guillemet non fermé.'};if($cell.Length -or $cells.Count -or $closed){$cells.Add($cell.ToString());$records.Add($cells.ToArray())}
    if($records.Count -lt 2 -or $records.Count -gt 5001){throw 'Un en-tête et 1 à 5 000 lignes sont nécessaires.'}
    $headers=@($records[0]|ForEach-Object{$_.Trim()});$seen=@{};foreach($h in $headers){if(-not$h -or $h.Length -gt 128 -or $seen.ContainsKey($h) -or $h -match '[\x00-\x1f]'){throw 'En-tête vide, dupliqué ou invalide.'};$seen[$h]=$true}
    if($headers.Count -gt 64){throw '64 colonnes maximum.'};$rows=@(for($n=1;$n -lt $records.Count;$n++){if($records[$n].Count -ne $headers.Count){throw ('Ligne '+($n+1)+' : nombre de colonnes différent de l''en-tête.')};[pscustomobject]@{Line=$n+1;Cells=[string[]]$records[$n]}})
    [pscustomobject]@{Headers=$headers;Rows=$rows;Delimiter=[string]$Delimiter}
}
function New-PestoImportEditor {
    param($Data,[hashtable]$Mapping)
    $fields=@('Nom_du_PC','Nouveau_Nom','OU_Destination','Renommer','Deplacer');$table=[Data.DataTable]::new('Import')
    [void]$table.Columns.Add('Ligne',[int]);foreach($key in $fields){[void]$table.Columns.Add($key,[string])};[void]$table.Columns.Add('Erreurs',[string])
    foreach($source in $Data.Rows){$r=$table.NewRow();$r.Ligne=$source.Line;foreach($key in $fields){$index=[Array]::IndexOf([string[]]$Data.Headers,[string]$Mapping[$key]);$r[$key]=if($index -ge 0){$source.Cells[$index]}elseif($key -in @('Renommer','Deplacer')){'false'}else{''}};[void]$table.Rows.Add($r)}
    return ,$table
}
function Test-PestoImportEditor {
    param([Data.DataTable]$Editor,[Data.DataTable]$Existing)
    $candidate=$Existing.Copy();$seen=@{};$targets=@{};$valid=$true
    foreach($row in $Existing.Rows){$seen[[string]$row.Nom_du_PC]=$true;if($row.Renommer){$targets[[string]$row.Nouveau_Nom]=$true}}
    foreach($entry in $Editor.Rows){
        $errors=[Collections.Generic.List[string]]::new();$name=([string]$entry.Nom_du_PC).Trim().ToUpperInvariant();$new=([string]$entry.Nouveau_Nom).Trim().ToUpperInvariant();$ou=([string]$entry.OU_Destination).Trim();$ren=$false;$move=$false
        try{$ren=Convert-Value-TF $entry.Renommer -Strict}catch{$errors.Add('Renommer : utilisez true ou false.')};try{$move=Convert-Value-TF $entry.Deplacer -Strict}catch{$errors.Add('Déplacer : utilisez true ou false.')}
        foreach($problem in @(Test-QueueRowSafe -Nom $name -NewName $new -OU $ou -Ren $ren -Move $move)){$errors.Add($problem)}
        if($seen.ContainsKey($name)){$errors.Add('Poste source dupliqué ou déjà présent dans la file.')}else{$seen[$name]=$true}
        if($ren){if($targets.ContainsKey($new)){$errors.Add('Nom cible dupliqué ou déjà préparé.')}else{$targets[$new]=$true}}
        foreach($value in @($name,$new,$ou)){if($value.Length -gt 4096 -or $value -match '[\x00-\x1f\x7f]'){$errors.Add('Champ trop long ou caractère de contrôle.')}}
        $entry.Erreurs=$errors -join ' · '
        if($errors.Count){$valid=$false;continue}
        $r=$candidate.NewRow();$r.Nom_du_PC=$name;$r.Nouveau_Nom=$new;$r.OU_Destination=$ou;$r.Renommer=$ren;$r.Deplacer=$move;$r.Traiter=$false;$r.Reboot=$false;$r.NeedsReview=$true;$r.Precontrole='À CONTRÔLER';$r.Plan=Get-PestoRowPlanText $r ([bool]$script:INDOMAIN);[void]$candidate.Rows.Add($r)
    }
    if($candidate.Rows.Count -gt 5000){$valid=$false;foreach($r in $Editor.Rows){$r.Erreurs+= ' · La file totale dépasse 5 000 lignes.'}}
    [pscustomobject]@{Valid=$valid;Candidate=$(if($valid){,$candidate}else{$null});ErrorRows=@($Editor.Rows|Where-Object{$_.Erreurs}).Count}
}
function New-PestoCsvQueueCandidate {
    <# Validation atomique de l'import classique. Les index sont propres à cet aperçu :
       aucun cache périmé, aucun hachage récursif par ligne, aucun effet sur la file. #>
    param([object[]]$Entries,[Data.DataTable]$Existing,[string[]]$Headers,[bool]$InDomain)
    if($Entries.Count -lt 1 -or $Entries.Count -gt 5000){throw 'Import : 1 à 5 000 lignes attendues.'}
        $candidate=$Existing.Copy();$errors=[Collections.Generic.List[string]]::new();$seen=@{};$index=1
        $sources=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $targets=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach($row in $Existing.Rows){[void]$sources.Add([string]$row.Nom_du_PC);if($row.Renommer){[void]$targets.Add([string]$row.Nouveau_Nom)}}
        foreach($e in $entries){
            $index++;$nom=([string]$e.Nom_du_PC).Trim().ToUpperInvariant()
            try{
                if($seen.ContainsKey($nom)){throw "Source dupliquée dans le CSV : $nom"};$seen[$nom]=$true
                if($sources.Contains($nom)){throw "Le poste '$nom' est déjà dans la file : aucun remplacement implicite."}
                $ren=Convert-Value-TF $e.Renommer -Strict;$move=Convert-Value-TF $e.Deplacer -Strict
                $new=([string]$e.Nouveau_Nom).Trim().ToUpperInvariant();$dest=([string]$e.OU_Destination).Trim()
                $oldStatus=([string]$e.Statut).Trim()
                if($oldStatus -notin @('OK','VÉRIFIÉ','SIMULÉ','PARTIEL','PROTECTION','INCERTAIN','TECHNIQUE','EN COURS')) {
                    $decision=Get-PestoRenameMoveDecision -Computer $nom -NewName $new -CurrentOU ([string]$e.OU_Actuelle) `
                        -TargetOU $dest -Rename $ren -Move $move -InDomain ([bool]$InDomain)
                    if(-not $decision.Valid){throw $decision.Error}
                    $move=[bool]$decision.Move
                }
                $problems=@(Test-QueueRowSafe -Nom $nom -NewName $new -OU $dest -Ren $ren -Move $move)
                if($problems.Count){throw ($problems -join '; ')}
                if($ren -and $targets.Contains($new)){throw "Nom cible réservé dans la file : $new"}
                $r=$candidate.NewRow();$r.Nom_du_PC=$nom;$r.Nouveau_Nom=$new;$r.OU_Destination=$dest
                $r.Renommer=$ren;$r.Deplacer=$move;$r.Traiter=$false
                $r.Reboot=if($headers -contains 'Reboot') {Convert-Value-TF $e.Reboot -Strict}else{$false}
                foreach($col in @('Type_de_PC','Organisme','Site','Service','OU_Actuelle')){
                    if($headers -contains $col){$v=([string]$e.$col).Trim();if($v.Length -gt 2048){throw "Champ '$col' trop long."};$r[$col]=$v}
                }
                # Un export historique reste historique ; ne transforme pas un succès en action neuve.
                $oldStatus=([string]$e.Statut).Trim()
                if($oldStatus -in @('OK','VÉRIFIÉ','SIMULÉ','PARTIEL','PROTECTION','INCERTAIN','TECHNIQUE','EN COURS')){
                    $r.Statut=$oldStatus
                    foreach($col in @('Code','Message','Duree','Horodatage','Mode_Resultat','Lot_ID')){if($headers -contains $col){$r[$col]=[string]$e.$col}}
                    if($oldStatus -eq 'EN COURS'){$r.Statut='INCERTAIN';$r.Code='97'}
                }
                $r.Precontrole='À CONTRÔLER';$r.Plan=Get-PestoRowPlanText $r ([bool]$InDomain)
                [void]$candidate.Rows.Add($r)
                [void]$sources.Add($nom);if($ren){[void]$targets.Add($new)}
            }catch{$errors.Add("Ligne $index ($nom) : $($_.Exception.Message)")}
        }
        if($candidate.Rows.Count -gt 5000){$errors.Add('La file totale dépasserait 5 000 lignes.')}
        [pscustomobject]@{Valid=($errors.Count -eq 0);Candidate=$(if($errors.Count -eq 0){,$candidate}else{$null});Errors=$errors.ToArray()}
}

function Get-PestoQueueContentStamp {
    param([Data.DataTable]$Table)
    $values=@(foreach($row in $Table.Rows){[pscustomobject]@{Values=@($row.ItemArray)}})
    Get-PestoStableHash $values
}
function Save-PestoQueueUndo {
    param([Data.DataTable]$Before,[string]$Reason)
    if(-not$Before -or $script:Running -or $script:DirectBusy -or $script:JoinBusy){return}
    # Une pile locale, bornée. Aucun reçu, credential ou accord WPF n'y figure.
    if(-not$script:PestoQueueUndo){$script:PestoQueueUndo=[Collections.Generic.List[object]]::new()}
    $script:PestoQueueUndo.Add([pscustomobject]@{Before=$Before.Copy();After=(Get-PestoQueueContentStamp $script:table);Reason=$Reason;ConfigStamp=(Get-PestoConfigurationSignature $script:CFG)})
    while($script:PestoQueueUndo.Count -gt 10){$script:PestoQueueUndo.RemoveAt(0)}
}
function Undo-PestoQueuePreparation {
    if($script:Running -or $script:DirectBusy -or $script:JoinBusy -or $script:PreflightRunning -or $script:CfgRestartRequired -or (Test-PestoGlobalSafetyBarrier)){throw 'Terminez les traitements avant de modifier la préparation.'}
    if(-not$script:PestoQueueUndo -or -not$script:PestoQueueUndo.Count){throw 'Aucun changement local à annuler dans cette session.'}
    $index=$script:PestoQueueUndo.Count-1;$frame=$script:PestoQueueUndo[$index]
    if($frame.ConfigStamp -cne (Get-PestoConfigurationSignature $script:CFG) -or $frame.After -cne (Get-PestoQueueContentStamp $script:table)){throw 'La file ou la configuration a changé depuis cette préparation. Annulation refusée ; aucun résultat ne sera réécrit.'}
    $candidate=$frame.Before.Copy();foreach($r in $candidate.Rows){$r.Traiter=$false;$r.Reboot=$false;if(-not$r.Statut -or $r.Statut -in @('À FAIRE','PRÊT')){Reset-PestoRowPreflight $r;$r.NeedsReview=$true}}
    $before=$script:table;$script:table=$candidate
    try{Save-PestoQueueCheckpoint}catch{$script:table=$before;throw}
    $script:PestoQueueUndo.RemoveAt($index);if($script:PestoQueueUndo.Count){$script:PestoQueueUndo[$script:PestoQueueUndo.Count-1].After=Get-PestoQueueContentStamp $candidate};$Grid.ItemsSource=$candidate.DefaultView;$script:PreflightCache=@{};$script:DirectCheckedKey='';$script:NmUsedSrc=$null;Update-PestoQueueFilter;Sync-Grid;Update-QueueButtons
    Add-LogLine ('Changement local annulé : '+$frame.Reason+'. Aucun effet Windows ou AD annulé ; toutes les lignes sont décochées.') 'info'
}
function Publish-PestoPreparedQueue {
    param([Data.DataTable]$Candidate,[string]$ExpectedStamp,[string]$Reason)
    if($script:Running -or $script:DirectBusy -or $script:JoinBusy -or $script:PreflightRunning -or $script:CfgRestartRequired -or (Test-PestoGlobalSafetyBarrier)){throw 'La file est actuellement verrouillée.'}
    if($ExpectedStamp -cne (Get-PestoQueueContentStamp $script:table)){throw 'La file a changé pendant la préparation. Recommencez l''aperçu.'}
    $old=$script:table;$script:table=$Candidate
    try{Save-PestoQueueCheckpoint}catch{$script:table=$old;throw}
    Save-PestoQueueUndo -Before $old -Reason $Reason;$Grid.ItemsSource=$Candidate.DefaultView;$script:PreflightCache=@{};$script:NmUsedSrc=$null;Update-PestoQueueFilter;Sync-Grid;Update-QueueButtons
}
function Show-PestoMappedImport {
    if($script:Running -or $script:DirectBusy -or $script:JoinBusy -or $script:PreflightRunning -or $script:CfgRestartRequired -or -not$script:INDOMAIN){throw 'Import disponible seulement pour préparer des postes du domaine, hors traitement.'}
    $choice=Show-PestoPanel -Title 'Importer un tableau de préparation' -Body 'Fichier CSV UTF-8 ou tableau Excel copié. Vous choisirez les colonnes et corrigerez toutes les lignes avant ajout. Les historiques doivent passer par l''import CSV classique. Aucun accord ni redémarrage importé.' -Choices @([pscustomobject]@{Label='Choisir un fichier CSV';Id='file'},[pscustomobject]@{Label='Lire le tableau du presse-papiers';Id='clipboard'}) -AcceptText 'Continuer'
    if(-not$choice.Accepted){return};$text=''
    if($choice.Selected.Id -eq 'file'){$dialog=[Microsoft.Win32.OpenFileDialog]::new();$dialog.Filter='Tableau CSV (*.csv;*.tsv)|*.csv;*.tsv';if(-not$dialog.ShowDialog($Win)){return};Assert-PestoPlainPath $dialog.FileName;if(([IO.FileInfo]::new($dialog.FileName)).Length -gt 8MB){throw 'Fichier trop volumineux.'};$bytes=[IO.File]::ReadAllBytes($dialog.FileName);$text=Read-PestoImportFile -Bytes $bytes}else{$text=[Windows.Clipboard]::GetText()}
    $data=ConvertFrom-PestoTabularText $text;$map=@{}
    foreach($target in @('Nom_du_PC','Nouveau_Nom','OU_Destination','Renommer','Deplacer')){
        $choices=@([pscustomobject]@{Label='Non renseigné (false pour les actions)';Header=''})+@(foreach($h in $data.Headers){[pscustomobject]@{Label=$h;Header=$h}})
        if($target -in $data.Headers){$map[$target]=$target;continue}
        $r=Show-PestoPanel -Title ('Colonne : '+$target) -Body 'Associez une colonne source à ce champ. Les cellules restent modifiables dans l''aperçu suivant.' -Choices $choices -AcceptText 'Associer';if(-not$r.Accepted){return};$map[$target]=[string]$r.Selected.Header
    }
    $editor=New-PestoImportEditor $data $map;Show-PestoQueueEditor -Editor $editor -Title 'Corriger le tableau importé'
}
function Show-PestoQueueEditor {
    param([Data.DataTable]$Editor,[string]$Title,[Data.DataTable]$Base=$null,[string]$ExpectedStamp='',[string[]]$OriginalOrder=@())
    if($null -eq $Base){$Base=$script:table.Copy()};if(-not$ExpectedStamp){$ExpectedStamp=Get-PestoQueueContentStamp $script:table}
    [xml]$x=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Width="1120" Height="720" Title="Préparation du lot"><Grid Margin="18"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions><StackPanel><TextBlock x:Name="Title" FontSize="22" FontWeight="SemiBold"/><TextBlock Text="Corrigez les cellules, puis Valider. Toutes les erreurs sont affichées par ligne. Aucun ajout partiel, aucune exécution." TextWrapping="Wrap" Margin="0,8,0,14"/></StackPanel><DataGrid x:Name="Editor" Grid.Row="1" AutoGenerateColumns="False" CanUserAddRows="False" CanUserDeleteRows="False" EnableRowVirtualization="True" EnableColumnVirtualization="True" ScrollViewer.CanContentScroll="True" AutomationProperties.Name="Préparation modifiable du lot"/><TextBlock Grid.Row="2" x:Name="Status" TextWrapping="Wrap" Margin="0,10,0,10"/><WrapPanel Grid.Row="3" HorizontalAlignment="Right"><Button x:Name="Validate" Content="Valider les lignes" Margin="0,0,8,6" AutomationProperties.HelpText="Calculer toutes les erreurs sans changer la file."/><Button x:Name="Apply" Content="Ajouter à la file décochée" IsEnabled="False" Margin="0,0,8,6" AutomationProperties.HelpText="Confirmer la préparation affichée sans lancer de commande."/><Button x:Name="Close" Content="Annuler" AutomationProperties.HelpText="Fermer sans modifier la file."/></WrapPanel></Grid></Window>
'@
    $w=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($x));$w.Resources=$Win.Resources;$w.FindName('Title').Text=$Title;$grid=$w.FindName('Editor')
    foreach($name in $Editor.Columns.ColumnName){$c=[Windows.Controls.DataGridTextColumn]::new();$c.Header=$name;$c.Binding=[Windows.Data.Binding]::new($name);$c.IsReadOnly=($name -in @('Ligne','Erreurs'));$c.Width=[Windows.Controls.DataGridLength]::new($(if($name -eq 'Erreurs'){280}else{140}));[void]$grid.Columns.Add($c)};$grid.ItemsSource=$Editor.DefaultView
    $state=[pscustomobject]@{Window=$w;Editor=$Editor;Grid=$grid;Base=$Base;Stamp=$ExpectedStamp;OriginalOrder=$OriginalOrder;Candidate=$null;InputStamp='';Status=$w.FindName('Status');Apply=$w.FindName('Apply')}
    $grid.Tag=$state;$grid.Add_CellEditEnding({param($s,$e);$s.Tag.Candidate=$null;$s.Tag.Apply.IsEnabled=$false;$s.Tag.Status.Text='Modification à valider.'})
    $w.FindName('Validate').Tag=$state;$w.FindName('Validate').Add_Click({param($s,$e);$u=$s.Tag;try{[void]$u.Grid.CommitEdit([Windows.Controls.DataGridEditingUnit]::Cell,$true);[void]$u.Grid.CommitEdit([Windows.Controls.DataGridEditingUnit]::Row,$true);$r=Test-PestoImportEditor $u.Editor $u.Base;$u.Candidate=$r.Candidate;if($r.Valid -and $u.OriginalOrder.Count){$u.Candidate=Restore-PestoEditedQueueOrder $r.Candidate $u.Editor $u.OriginalOrder};$u.Apply.IsEnabled=$r.Valid;$u.InputStamp=Get-PestoQueueContentStamp $u.Editor;$u.Status.Text=if($r.Valid){'Toutes les lignes sont valides pour la préparation. Le précontrôle AD reste nécessaire.'}else{[string]$r.ErrorRows+' ligne(s) à corriger. La file est inchangée.'}}catch{$u.Candidate=$null;$u.Apply.IsEnabled=$false;$u.Status.Text=$_.Exception.Message}})
    $state.Apply.Tag=$state;$state.Apply.Add_Click({param($s,$e);$u=$s.Tag;try{if(-not$u.Candidate -or $u.InputStamp -cne (Get-PestoQueueContentStamp $u.Editor)){throw 'Validez les modifications avant cet ajout.'};if(Confirm-YesNo -Msg ('Appliquer cette préparation de '+$u.Editor.Rows.Count+' ligne(s) ? Aucun accord, redémarrage ou résultat antérieur ne sera réutilisé.') -Confirm $true -AcceptText 'Appliquer la préparation'){Publish-PestoPreparedQueue $u.Candidate $u.Stamp 'Préparation du tableau';$u.Window.Close()}}catch{$u.Status.Text=$_.Exception.Message}})
    $w.FindName('Close').Tag=$w;$w.FindName('Close').Add_Click({param($s,$e);$s.Tag.Close()});[void](Show-PestoHostedWindow $w)
}
function Show-PestoMultiEdit {
    $rows=@(foreach($r in $script:table.Rows){if(-not$r.Statut -and -not$r.Operation_ID){$r}})
    $picked=Show-PestoChoiceTable -Title 'Modifier plusieurs préparations' -Description 'Choisissez avec Ctrl+clic les lignes sans résultat. Les lignes exécutées ne sont pas modifiables ici. Les lignes modifiées seront décochées, sans redémarrage et à contrôler de nouveau.' -Rows $rows -Columns @(@{Key='Nom_du_PC';Label='Poste'},@{Key='Nouveau_Nom';Label='Nom prévu'},@{Key='OU_Destination';Label='OU cible'}) -Multiple -AcceptText 'Modifier ces lignes'
    if(-not$picked.Accepted){return};$stamp=Get-PestoQueueContentStamp $script:table;$selected=@{};foreach($r in $picked.Items){$selected[[string]$r.Nom_du_PC]=$true};$base=$script:table.Clone();foreach($r in $script:table.Rows){if(-not$selected.ContainsKey([string]$r.Nom_du_PC)){$base.ImportRow($r)}}
    $headers=@('Nom_du_PC','Nouveau_Nom','OU_Destination','Renommer','Deplacer');$data=[pscustomobject]@{Headers=$headers;Rows=@(foreach($r in $picked.Items){[pscustomobject]@{Line=$script:table.Rows.IndexOf($r)+1;Cells=@(foreach($h in $headers){[string]$r[$h]})}})};$map=@{};foreach($h in $headers){$map[$h]=$h};$editor=New-PestoImportEditor $data $map
    Show-PestoQueueEditor -Editor $editor -Base $base -ExpectedStamp $stamp -OriginalOrder @($script:table.Rows|ForEach-Object{[string]$_.Nom_du_PC}) -Title 'Modifier les préparations choisies'
}
function Initialize-PestoBatchTools {
    foreach($name in @('QueueMappedImport','QueueMultiEdit','QueueUndo')){$b=$Win.FindName($name);if($b){$b.Add_Click({param($s,$e);try{switch($s.Name){'QueueMappedImport'{Show-PestoMappedImport};'QueueMultiEdit'{Show-PestoMultiEdit};'QueueUndo'{Undo-PestoQueuePreparation}}}catch{Show-MsgWarning $_.Exception.Message}})}}
}

function Restore-PestoEditedQueueOrder {
    param([Data.DataTable]$Candidate,[Data.DataTable]$Editor,[string[]]$OriginalOrder)
    $positions=@{};for($i=0;$i -lt $OriginalOrder.Count;$i++){$positions[$OriginalOrder[$i]]=$i}
    $used=@{};foreach($entry in $Editor.Rows){$index=[int]$entry.Ligne-1;if($index -lt 0 -or $index -ge $OriginalOrder.Count -or $used.ContainsKey($index)){throw 'Position de préparation invalide.'};$used[$index]=$true;$positions[([string]$entry.Nom_du_PC).Trim().ToUpperInvariant()]=$index}
    if($Candidate.Rows.Count -ne $OriginalOrder.Count){throw 'La taille de la file a changé pendant la multiédition.'}
    $copy=$Candidate.Clone();foreach($row in @($Candidate.Rows|Sort-Object {$positions[[string]$_.Nom_du_PC]})){if(-not$positions.ContainsKey([string]$row.Nom_du_PC)){throw 'Ligne sans position initiale.'};$copy.ImportRow($row)};return ,$copy
}

function Read-PestoImportFile {
    param([byte[]]$Bytes)
    if(-not$Bytes){return ''}
    # UTF-8 strict (avec ou sans BOM) ou UTF-16 annoncé par son BOM ; jamais de repli ANSI deviné.
    $offset=0;$enc=[Text.UTF8Encoding]::new($false,$true)
    if($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF){$offset=3}
    elseif($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE){$enc=[Text.UnicodeEncoding]::new($false,$false,$true);$offset=2}
    elseif($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFE -and $Bytes[1] -eq 0xFF){$enc=[Text.UnicodeEncoding]::new($true,$false,$true);$offset=2}
    try{
        return $enc.GetString($Bytes,$offset,$Bytes.Length-$offset)
    }catch [Text.DecoderFallbackException]{
        throw 'Fichier non UTF-8. Dans Excel, choisissez « CSV UTF-8 (délimité par des virgules) », puis importez de nouveau. Aucune ligne ajoutée.'
    }
}
