# Démo réelle : accueil, puis renommage réel de ce PC (même site Paris) par la page « Un poste ».
Import-Module C:\PestoTest-run\pilote.psm1
. C:\PestoTest-run\demo-commun.ps1
$log = "$D\03-renommer.txt"
& {
  try {
    $w = Get-Pesto; if (-not $w) { throw 'fenêtre principale introuvable' }
    Set-Agrandie $w
    Click-Id $w 'NavHome'; Start-Sleep -Seconds 3; Save-Fenetre $w "$D\10-accueil.png"
    Click-Id $w 'NavRename'; Start-Sleep -Seconds 2
    Click-Id $w 'BtnReadComputer'; Start-Sleep -Seconds 20
    Set-Combo $w 'CbOrg' 'Département 111301'
    Set-Combo $w 'CbSite' 'Paris'
    Set-Combo $w 'CbService' '765'
    Set-Combo $w 'CbType' 'Portable'
    Start-Sleep -Seconds 3
    Set-Combo $w 'CbName' ''
    Start-Sleep -Seconds 4
    Save-Fenetre $w "$D\11-unposte-pret.png"
    $run = Find-Id $w 'SuiteDirectRun'; "bouton principal : $($run.Current.Name)"
    Invoke-Element $run | Out-Null
    $t = Wait-Texte $w 'Vérifier avant de confirmer' 120
    if (-not $t) { Save-Fenetre $w "$D\12-sans-confirmation.png"; Get-Arbre $w 14 | Out-File "$D\12-arbre.txt" -Encoding UTF8; throw 'confirmation non affichée' }
    Start-Sleep -Seconds 2; Save-Fenetre $w "$D\12-confirmation.png"
    "confirmation : " + (Get-PanelText $w)
    Click-Id $w 'PanelAccept'
    $fin = (Get-Date).AddSeconds(240); $bilan = $null
    while ((Get-Date) -lt $fin) { $b = Find-Id $w 'PanelBody'; if ($b) { $bilan = $b; break }; Start-Sleep -Seconds 2 }
    if (-not $bilan) { Save-Fenetre $w "$D\13-sans-bilan.png"; throw 'bilan non affiché' }
    Start-Sleep -Seconds 2; Save-Fenetre $w "$D\13-bilan.png"
    "bilan : " + (Get-PanelText $w)
    Click-Id $w 'PanelCancel'; Start-Sleep -Seconds 2
    Save-Fenetre $w "$D\14-apres-bilan.png"
    'RENOMMAGE : étape terminée'
  } catch { "ÉCHEC : $($_.Exception.Message)"; try { Save-Ecran "$D\03-echec.png" } catch {} }
} *> $log
