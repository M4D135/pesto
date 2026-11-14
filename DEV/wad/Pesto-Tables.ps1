#requires -Version 5.1
# Colonnes : présentation uniquement. Aucune sélection, commande ou permission mémorisée.
function ConvertTo-PestoTablePreferences {
    param($Value)
    Assert-PestoClosedObject $Value @('Schema','Tables') @('Schema','Tables')
    if($Value.Schema -isnot [int] -or $Value.Schema -ne 1 -or $Value.Tables -is [string] -or @($Value.Tables).Count -gt 3){throw 'Préférences de tableaux invalides.'}
    $ids=@{};$output=[Collections.Generic.List[object]]::new()
    foreach($table in @($Value.Tables)){
        Assert-PestoClosedObject $table @('Id','Signature','Columns') @('Id','Signature','Columns')
        if($table.Id -cnotin @('queue','names','interventions') -or $ids.ContainsKey($table.Id) -or $table.Signature -notmatch '^[a-f0-9]{64}$'){throw 'Identité de tableau invalide.'}
        $ids[$table.Id]=$true;$cols=@($table.Columns);$orders=@{};$keys=@{}
        if($table.Columns -is [string] -or $cols.Count -lt 1 -or $cols.Count -gt 64){throw 'Nombre de colonnes invalide.'}
        foreach($c in $cols){
            Assert-PestoClosedObject $c @('Key','Order','Unit','Value') @('Key','Order','Unit','Value')
            if($c.Key -isnot [string] -or $c.Key -notmatch '^[A-Za-z_][A-Za-z0-9_.]{0,127}$' -or $keys.ContainsKey($c.Key) -or $c.Order -isnot [int] -or $c.Order -lt 0 -or $c.Order -ge $cols.Count -or $orders.ContainsKey($c.Order)){throw 'Ordre ou clé de colonne invalide.'}
            $keys[$c.Key]=$true;$orders[$c.Order]=$true
            if($c.Unit -cnotin @('Pixel','Star','Auto','SizeToCells','SizeToHeader') -or ($c.Value -isnot [double] -and $c.Value -isnot [int] -and $c.Value -isnot [long] -and $c.Value -isnot [decimal])){throw 'Largeur de colonne invalide.'}
            $v=[double]$c.Value
            if([double]::IsNaN($v) -or [double]::IsInfinity($v) -or $v -lt 0 -or $v -gt 1600 -or ($c.Unit -eq 'Pixel' -and $v -lt 24) -or ($c.Unit -eq 'Star' -and ($v -lt 0.1 -or $v -gt 20))){throw 'Largeur de colonne hors bornes.'}
        }
        $output.Add($table)
    }
    return [pscustomobject]@{Schema=1;Tables=$output.ToArray()}
}

function Get-PestoTableKeys {
    param($Grid)
    $index=0
    foreach($column in $Grid.Columns){
        $key=if($column -is [Windows.Controls.DataGridBoundColumn] -and $column.Binding -and $column.Binding.Path){[string]$column.Binding.Path.Path}else{'_column'+$index}
        if($key -notmatch '^[A-Za-z_][A-Za-z0-9_.]{0,127}$'){throw 'Clé de colonne non stable.'}
        $key;$index++
    }
}

function Register-PestoTable {
    param([ValidateSet('queue','names','interventions')][string]$Id,$Grid,[int]$Fixed=0)
    if(-not $Grid){return}
    if(-not $script:PestoTables){$script:PestoTables=@{}}
    $keys=@(Get-PestoTableKeys $Grid)
    $defaults=@(foreach($column in $Grid.Columns){[pscustomobject]@{Width=$column.Width;Order=$column.DisplayIndex}})
    for($i=0;$i -lt [Math]::Min($Fixed,$Grid.Columns.Count);$i++){$Grid.Columns[$i].CanUserReorder=$false}
    $script:PestoTables[$Id]=[pscustomobject]@{Grid=$Grid;Keys=$keys;Signature=(Get-PestoStableHash $keys);Defaults=$defaults;Fixed=$Fixed}
}

function Get-PestoSavedTables {
    $text=if($script:SIM -or $script:GUI){$script:PestoTablesMemory}else{Get-PestoAppearanceValue -Name 'Tables'}
    if(-not $text){return [pscustomobject]@{Schema=1;Tables=@()}}
    if($text.Length -gt 32768){throw 'Préférences de colonnes trop volumineuses.'}
    return ConvertTo-PestoTablePreferences ($text|ConvertFrom-Json -ErrorAction Stop)
}

function Apply-PestoSavedTables {
    try{
        $saved=Get-PestoSavedTables
        foreach($table in $saved.Tables){
            if(-not $script:PestoTables.ContainsKey($table.Id)){continue}
            $target=$script:PestoTables[$table.Id];$grid=$target.Grid
            if($target.Signature -cne $table.Signature -or @($table.Columns).Count -ne $grid.Columns.Count){continue}
            $invalid=$false
            for($i=0;$i -lt $grid.Columns.Count;$i++){
                if($table.Columns[$i].Key -cne $target.Keys[$i] -or ($i -lt $target.Fixed -and $table.Columns[$i].Order -ne $i)){$invalid=$true;break}
            }
            if($invalid){continue}
            foreach($col in @($table.Columns|Sort-Object Order)){
                $index=[Array]::IndexOf([string[]]$target.Keys,[string]$col.Key)
                $grid.Columns[$index].DisplayIndex=$col.Order
                $unit=[Windows.Controls.DataGridLengthUnitType][Enum]::Parse([Windows.Controls.DataGridLengthUnitType],$col.Unit)
                $grid.Columns[$index].Width=[Windows.Controls.DataGridLength]::new([double]$col.Value,$unit)
            }
        }
    }catch{Write-Log ('Présentation des tableaux non restaurée : '+$_.Exception.Message) 'WARN' $null 'appearance'}
}

function Save-PestoTables {
    $saved=Get-PestoSavedTables;$result=@{}
    foreach($old in $saved.Tables){$result[$old.Id]=$old}
    foreach($id in $script:PestoTables.Keys){
        $table=$script:PestoTables[$id];$columns=@();$i=0
        foreach($column in $table.Grid.Columns){
            $columns+= [pscustomobject]@{Key=$table.Keys[$i];Order=[int]$column.DisplayIndex;Unit=[string]$column.Width.UnitType;Value=[double]$column.Width.Value};$i++
        }
        for($i=0;$i -lt $table.Fixed;$i++){if($columns[$i].Order -ne $i){throw 'Conservez les colonnes d’’identité au début du tableau.'}}
        $result[$id]=[pscustomobject]@{Id=$id;Signature=$table.Signature;Columns=$columns}
    }
    $safe=ConvertTo-PestoTablePreferences ([pscustomobject]@{Schema=1;Tables=@($result.Values|Sort-Object Id)})
    $text=$safe|ConvertTo-Json -Depth 6 -Compress
    if($script:SIM -or $script:GUI){$script:PestoTablesMemory=$text}else{Set-PestoAppearanceValue -Name 'Tables' -Value $text}
    Add-LogLine 'Largeurs et ordre des colonnes mémorisés. Sélections, filtres, visibilité et accords non enregistrés.' 'info'
}

function Reset-PestoTables {
    if($script:SIM -or $script:GUI){$script:PestoTablesMemory=''}else{Set-PestoAppearanceValue -Name 'Tables' -Value ''}
    foreach($table in $script:PestoTables.Values){
        for($i=0;$i -lt $table.Grid.Columns.Count;$i++){$table.Grid.Columns[$i].DisplayIndex=$i;$table.Grid.Columns[$i].Width=$table.Defaults[$i].Width}
    }
    Add-LogLine 'Présentation initiale des tableaux rétablie. Aucune ligne ni opération modifiée.' 'info'
}
