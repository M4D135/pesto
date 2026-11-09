# Démo réelle : changement de site réel Lyon -> Paris (renommage puis déplacement) par la page « Un poste ».
Import-Module C:\PestoTest-run\pilote.psm1
. C:\PestoTest-run\demo-commun.ps1
$log = "$D\80-op.txt"
& {
  try {
    $w = Get-Pesto; if (-not $w) { throw 'fenêtre principale introuvable' }
    Set-Agrandie $w
    for ($k = 0; $k -lt 4 -and ((Find-Id $w 'StateRefresh') -or (Find-Id $w 'LedgerGrid') -or (Find-Id $w 'PanelBody')); $k++) { Send-Touches $w '{ESC}'; Start-Sleep -Seconds 2 }
    Click-Id $w 'NavHome'; Start-Sleep -Seconds 3; Save-Fenetre $w "$D\80-0-accueil.png"
    Click-Id $w 'NavRename'; Start-Sleep -Seconds 2
    $c = Find-Id $w 'ChkRemote'; $t=$null; if ($c -and $c.TryGetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern,[ref]$t) -and [string]$t.Current.ToggleState -eq 'On') { $t.Toggle(); Start-Sleep -Seconds 2; '« Un autre poste du domaine » décoché' }
    Click-Id $w 'BtnReadComputer'; Start-Sleep -Seconds 20
    Set-Combo $w 'CbOrg' 'Département 111301'
    Set-Combo $w 'CbSite' 'Paris'
    Set-Combo $w 'CbService' '765'
    Set-Combo $w 'CbType' 'Portable'
    Start-Sleep -Seconds 3
    Set-Combo $w 'CbName' ''
    Start-Sleep -Seconds 4
    Save-Fenetre $w "$D\80-1-formulaire.png"
    Click-Id $w 'HeaderSite'; Start-Sleep -Seconds 2; Save-Fenetre $w "$D\80-1b-options.png"; Click-Id $w 'HeaderSite'; Start-Sleep -Seconds 1
    $run = Find-Id $w 'SuiteDirectRun'; "bouton principal : $($run.Current.Name)"
    Invoke-Element $run | Out-Null
    $t = Wait-Texte $w 'Vérifier avant de confirmer' 120
    if (-not $t) { Save-Fenetre $w "$D\80-2-sans-confirmation.png"; Get-Arbre $w 14 | Out-File "$D\80-2-arbre.txt" -Encoding UTF8; throw 'confirmation non affichée' }
    Start-Sleep -Seconds 2; Save-Fenetre $w "$D\80-2-confirmation.png"
    "confirmation : " + (Get-PanelText $w)
    Click-Id $w 'PanelAccept'
    $fin = (Get-Date).AddSeconds(240); $bilan = $null
    while ((Get-Date) -lt $fin) { $b = Find-Id $w 'PanelBody'; if ($b) { $bilan = $b; break }; Start-Sleep -Seconds 2 }
    if (-not $bilan) { Save-Fenetre $w "$D\80-3-sans-bilan.png"; throw 'bilan non affiché' }
    Start-Sleep -Seconds 2; Save-Fenetre $w "$D\80-3-bilan.png"
    "bilan : " + (Get-PanelText $w)
    Click-Id $w 'PanelCancel'; Start-Sleep -Seconds 2
    Save-Fenetre $w "$D\80-4-apres-bilan.png"
    'OPÉRATION : étape terminée'
  } catch { "ÉCHEC : $($_.Exception.Message)"; try { Save-Ecran "$D\80-9-echec.png" } catch {} }
} *> $log
