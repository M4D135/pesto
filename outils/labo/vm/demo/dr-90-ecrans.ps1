# Démo réelle : écrans réels sans mutation : Noms disponibles (inventaire AD réel), préparation d'un lot, palette, interventions.
Import-Module C:\PestoTest-run\pilote.psm1
. C:\PestoTest-run\demo-commun.ps1
function Close-Overlays($w) { for ($k = 0; $k -lt 4 -and ((Find-Id $w 'StateRefresh') -or (Find-Id $w 'LedgerGrid') -or (Find-Id $w 'PanelBody')); $k++) { Send-Touches $w '{ESC}'; Start-Sleep -Seconds 2 } }
& {
  try {
    $w = Get-Pesto; if (-not $w) { throw 'fenêtre principale introuvable' }
    Set-Agrandie $w; Close-Overlays $w
    # Lot : modèle (autre poste du domaine, organisme, site, service, type), puis « Préparer un lot ».
    Click-Id $w 'NavNames'; Start-Sleep -Seconds 3; Click-Id $w 'NmBtnRefresh' 30; Start-Sleep -Seconds 25; Save-Fenetre $w "$D\90-noms.png"
    Click-Id $w 'NavBatch'; Start-Sleep -Seconds 3
    $c = Find-Id $w 'ChkRemote'; $t=$null; if ($c -and $c.TryGetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern,[ref]$t) -and $t.Current.ToggleState -ne 'On') { $t.Toggle(); Start-Sleep -Seconds 1 }
    $tx = Find-Id $w 'TxtPCName'; $vp=$null; if ($tx -and $tx.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern,[ref]$vp)) { $vp.SetValue('P111301VA765001'); Start-Sleep -Seconds 3; 'poste saisi : P111301VA765001' }
    try { Click-Id $w 'BtnReadComputer' 20; Start-Sleep -Seconds 15 } catch { "lecture : $($_.Exception.Message)" }
    Set-Combo $w 'CbOrg' 'Département 111301'; Set-Combo $w 'CbSite' 'Paris'; Set-Combo $w 'CbService' '765'; Set-Combo $w 'CbType' 'Portable'
    Start-Sleep -Seconds 2; Save-Fenetre $w "$D\91-plusieurs-postes.png"
    Click-Id $w 'BtnBulk' 30; Start-Sleep -Seconds 6
    Save-Fenetre $w "$D\92-preparer-lot.png"
    $lot = Wait-Fenetre 'lot' 8
    if ($lot) { "fenêtre lot : $($lot.Current.Name)"; $f = Find-Element $lot 'Fermer' 'Button'; if ($f) { Invoke-Element $f | Out-Null; Start-Sleep -Seconds 2; 'lot fermé' } }
    Start-Sleep -Seconds 2; Close-Overlays $w
    # Palette Actions.
    Send-Touches $w '^k'; Start-Sleep -Seconds 2; [System.Windows.Forms.SendKeys]::SendWait('nom'); Start-Sleep -Seconds 2
    Save-Fenetre $w "$D\93-palette.png"; Send-Touches $w '{ESC}'; Start-Sleep -Seconds 2; Close-Overlays $w
    # Interventions.
    Click-Id $w 'NavHistory'; Start-Sleep -Seconds 2; Save-Fenetre $w "$D\94-historique.png"
    Click-Id $w 'BtnInterventions'; Start-Sleep -Seconds 6; Save-Fenetre $w "$D\95-interventions.png"
    Close-Overlays $w
    'ÉCRANS : terminé'
  } catch { "ÉCHEC : $($_.Exception.Message)"; try { Save-Ecran "$D\99-echec.png" } catch {} }
} *> "$D\90-ecrans.txt"
