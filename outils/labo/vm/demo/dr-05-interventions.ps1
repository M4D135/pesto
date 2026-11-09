# Démo réelle : accueil après redémarrage, Historique, puis « Interventions et reprises » ; relevé des fenêtres.
Import-Module C:\PestoTest-run\pilote.psm1
. C:\PestoTest-run\demo-commun.ps1
& {
  try {
    $w = Get-Pesto; if (-not $w) { throw 'fenêtre principale introuvable' }
    Set-Agrandie $w
    Click-Id $w 'NavHome'; Start-Sleep -Seconds 3; Save-Fenetre $w "$D\20-accueil-apres-renommage.png"
    Click-Id $w 'NavHistory'; Start-Sleep -Seconds 3; Save-Fenetre $w "$D\21-historique.png"
    Click-Id $w 'BtnInterventions'; Start-Sleep -Seconds 6
    Get-Fenetres | Format-Table -AutoSize | Out-String -Width 220
    $iw = Wait-Fenetre 'Intervention' 20
    if ($iw) { "fenêtre : $($iw.Current.Name)"; Save-Fenetre $iw "$D\22-interventions.png"; Get-Arbre $iw 12 | Out-File "$D\22-arbre.txt" -Encoding UTF8 }
    else { Save-Fenetre $w "$D\22-interventions.png"; Get-Arbre $w 14 | Out-File "$D\22-arbre.txt" -Encoding UTF8; 'panneau dans la fenêtre principale' }
  } catch { "ÉCHEC : $($_.Exception.Message)"; try { Save-Ecran "$D\05-echec.png" } catch {} }
} *> "$D\05-interventions.txt"
