#requires -Version 5.1
[CmdletBinding()]
param()
# Fumée du banc WPF de projection (tools/Measure-PestoWpfProjection.ps1 -Smoke) : une cellule de 100 lignes,
# fenêtre hors écran, données fictives. Aucun AD, aucun démarrage de Pesto. Windows PowerShell 5.1 en STA.
$ErrorActionPreference='Stop';Set-StrictMode -Off
if($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){throw 'Windows PowerShell 5.1 requis (WPF).'}
if([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA'){throw 'Lancer avec -STA.'}
$tool=Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'tools') 'Measure-PestoWpfProjection.ps1'
$failures=[Collections.Generic.List[string]]::new()
function Check {
    param([string]$Name,[scriptblock]$Body)
    try{& $Body;Write-Host ('OK '+$Name)}catch{$failures.Add($Name);Write-Host ('ECHEC '+$Name+' : '+$_.Exception.Message)}
}
$cells=@(& $tool -Smoke)
Check 'Trois cellules mesurées : FullRebind, InPlace, puis le chemin livre' {
    if($cells.Count -ne 3){throw ('cellules : '+$cells.Count)}
    if((@($cells|ForEach-Object{$_.Strategy}) -join ',') -ne 'FullRebind,InPlace,ObservableInPlace'){throw 'stratégies inattendues'}
}
Check 'Deux mesures de 100 lignes par cellule' {
    foreach($cell in $cells){
        if($cell.Rows -ne 100){throw ('lignes : '+$cell.Rows)}
        if(@($cell.Samples).Count -ne 2){throw ('mesures : '+@($cell.Samples).Count)}
        foreach($sample in @($cell.Samples)){if($sample -lt 0){throw 'durée négative'}}
    }
}
Check 'FullRebind : passes de mise en page réellement comptées' {
    $full=@($cells|Where-Object{$_.Strategy -eq 'FullRebind'})
    if(@($full[0].LayoutPasses|Where-Object{$_ -gt 0}).Count -eq 0){throw 'LayoutPasses toujours à 0'}
}
Check 'ObservableInPlace : une notification par ligne réellement changee' {
    # La fumée applique 10 changements sur 100 lignes : le helper livre ne doit publier que 10 notifications,
    # et ni le tri porte par la vue ni la selection ne doivent etre perdus par la mise a jour en place.
    $obs=@($cells|Where-Object{$_.Strategy -eq 'ObservableInPlace'})
    if(@($obs).Count -ne 1){throw 'cellule ObservableInPlace absente du rapport'}
    foreach($published in @($obs[0].Notifications)){if($published -ne 10){throw ('notifications publiees : '+$published)}}
    if($null -eq $obs[0].SortKept){throw 'SortKept n est pas releve pour la strategie livree'}
    if($null -eq $obs[0].SelectionKept){throw 'SelectionKept n est pas releve pour la strategie livree'}
    if(-not $obs[0].SortKept){throw 'le tri porte par la vue a ete perdu par la mise a jour en place'}
    if(-not $obs[0].SelectionKept){throw 'la selection a ete perdue par la mise a jour en place'}
}
Check 'ObservableInPlace : les deux autres strategies ne lient aucune collection observable' {
    foreach($strategy in @('FullRebind','InPlace')){
        $cell=@($cells|Where-Object{$_.Strategy -eq $strategy})
        if(@($cell[0].Notifications|Where-Object{$_ -ne 0}).Count -ne 0){throw ($strategy+' publie des notifications d une collection liee')}
        if($null -ne $cell[0].SortKept){throw ($strategy+' releve un tri alors qu il ne lie pas de collection observable')}
    }
}
if($failures.Count){throw ('Échecs : '+($failures.ToArray() -join ', '))}
Write-Host 'Banc WPF de projection : fumée réussie sous Windows PowerShell 5.1 (STA).'
