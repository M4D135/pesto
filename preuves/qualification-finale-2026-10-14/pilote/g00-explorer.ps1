# Exploration en lecture seule : copie PROD a754ac88 + configuration du labo, chaque page de navigation, éléments et captures.
. 'C:\PestoFinal_20261014\pilot\commun.ps1'
$G = "$R\gui"
if (-not (Test-Path "$G\Pesto.exe")) {
    Copy-Item "$R\prod\PROD" $G -Recurse
    Copy-Item 'C:\Pesto120_GUI_C4_20261013\wad\cfg.json' "$G\wad\cfg.json" -Force
    Get-ChildItem $G -Recurse -File | Unblock-File
    "copie de recette préparée : $G (cfg du labo importé du 13/10 par l'interface)"
}
$w = Start-PestoCopie $G
Set-Agrandie $w
Save-Etape $w 'g00-accueil'
Get-Texte $w | Set-Content "$D\g00-accueil.textes.txt" -Encoding UTF8
foreach ($nav in 'NavRename', 'NavBatch', 'NavJoin', 'NavNames', 'NavHistory', 'NavLogs', 'NavSettings', 'NavHome') {
    try {
        Click-Id $w $nav
        Start-Sleep -Seconds 4
        Save-Etape $w ("g00-" + $nav)
        Get-Texte $w | Set-Content "$D\g00-$nav.textes.txt" -Encoding UTF8
    } catch { "page $nav : $($_.Exception.Message)" }
}
Stop-PestoFenetre $w
"processus Pesto restants : $(@(Get-Process Pesto -ErrorAction SilentlyContinue).Count)"
