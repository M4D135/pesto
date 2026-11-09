# Démo réelle : changement de site Paris -> Lyon de ce PC par la page « Un poste » (renommage puis déplacement).
Import-Module C:\PestoTest-run\pilote.psm1
. C:\PestoTest-run\demo-commun.ps1
$log = "$D\09-site.txt"
& {
  try {
    $w = Get-Pesto; if (-not $w) { throw 'fenêtre principale introuvable' }
    Set-Agrandie $w
    for ($k = 0; $k -lt 3 -and ((Find-Id $w 'StateRefresh') -or (Find-Id $w 'LedgerGrid') -or (Find-Id $w 'PanelBody')); $k++) { Send-Touches $w '{ESC}'; Start-Sleep -Seconds 2 }
    Click-Id $w 'NavHome'; Start-Sleep -Seconds 3; Save-Fenetre $w "$D\50-accueil.png"
    Click-Id $w 'NavRename'; Start-Sleep -Seconds 2
    Click-Id $w 'BtnReadComputer'; Start-Sleep -Seconds 20
    Set-Combo $w 'CbOrg' 'Département 111301'
    Set-Combo $w 'CbSite' 'Lyon'
    Set-Combo $w 'CbService' '765'
    Set-Combo $w 'CbType' 'Portable'
    Start-Sleep -Seconds 3
    Set-Combo $w 'CbName' ''
    Start-Sleep -Seconds 4
    Save-Fenetre $w "$D\51-site-pret.png"
    Click-Id $w 'HeaderSite'; Start-Sleep -Seconds 2; Save-Fenetre $w "$D\51b-options.png"; Click-Id $w 'HeaderSite'; Start-Sleep -Seconds 1
    $run = Find-Id $w 'SuiteDirectRun'; "bouton principal : $($run.Current.Name)"
    Invoke-Element $run | Out-Null
    $t = Wait-Texte $w 'Vérifier avant de confirmer' 120
    if (-not $t) { Save-Fenetre $w "$D\52-sans-confirmation.png"; Get-Arbre $w 14 | Out-File "$D\52-arbre.txt" -Encoding UTF8; throw 'confirmation non affichée' }
    Start-Sleep -Seconds 2; Save-Fenetre $w "$D\52-confirmation.png"
    "confirmation : " + (Get-PanelText $w)
    Click-Id $w 'PanelAccept'
    $fin = (Get-Date).AddSeconds(240); $bilan = $null
    while ((Get-Date) -lt $fin) { $b = Find-Id $w 'PanelBody'; if ($b) { $bilan = $b; break }; Start-Sleep -Seconds 2 }
    if (-not $bilan) { Save-Fenetre $w "$D\53-sans-bilan.png"; throw 'bilan non affiché' }
    Start-Sleep -Seconds 2; Save-Fenetre $w "$D\53-bilan.png"
    "bilan : " + (Get-PanelText $w)
    Click-Id $w 'PanelCancel'; Start-Sleep -Seconds 2
    Save-Fenetre $w "$D\54-apres-bilan.png"
    'CHANGEMENT DE SITE : étape terminée'
  } catch { "ÉCHEC : $($_.Exception.Message)"; try { Save-Ecran "$D\09-echec.png" } catch {} }
} *> $log
