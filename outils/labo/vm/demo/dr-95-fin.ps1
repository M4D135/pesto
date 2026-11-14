# Démo réelle : historique, interventions et palette (sans mutation ni lecture distante). Souris écartée (pas d'infobulle).
Import-Module C:\PestoTest-run\pilote.psm1
. C:\PestoTest-run\demo-commun.ps1
Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public static class Souris{[DllImport("user32.dll")]public static extern bool SetCursorPos(int x,int y);}' -ErrorAction SilentlyContinue
function Close-Overlays($w) { for ($k = 0; $k -lt 4 -and ((Find-Id $w 'StateRefresh') -or (Find-Id $w 'LedgerGrid') -or (Find-Id $w 'PanelBody')); $k++) { Send-Touches $w '{ESC}'; Start-Sleep -Seconds 2 } }
& {
  try {
    $w = Get-Pesto; if (-not $w) { throw 'fenêtre principale introuvable' }
    Set-Agrandie $w; Close-Overlays $w; [void][Souris]::SetCursorPos(1915, 1000)
    Click-Id $w 'NavHome'; Start-Sleep -Seconds 3; [void][Souris]::SetCursorPos(1915, 1000); Start-Sleep -Seconds 1; Save-Fenetre $w "$D\96-accueil.png"
    Click-Id $w 'NavHistory'; Start-Sleep -Seconds 3; [void][Souris]::SetCursorPos(1915, 1000); Start-Sleep -Seconds 1; Save-Fenetre $w "$D\94-historique.png"
    Click-Id $w 'BtnInterventions'; Start-Sleep -Seconds 6; [void][Souris]::SetCursorPos(1915, 1000); Start-Sleep -Seconds 1; Save-Fenetre $w "$D\95-interventions.png"
    Close-Overlays $w
    Send-Touches $w '^k'; Start-Sleep -Seconds 2; [System.Windows.Forms.SendKeys]::SendWait('nom'); Start-Sleep -Seconds 2; [void][Souris]::SetCursorPos(1915, 1000); Start-Sleep -Seconds 1
    Save-Fenetre $w "$D\93-palette.png"; Send-Touches $w '{ESC}'; Start-Sleep -Seconds 2; Close-Overlays $w
    'FIN : terminé'
  } catch { "ÉCHEC : $($_.Exception.Message)"; try { Save-Ecran "$D\95-echec.png" } catch {} }
} *> "$D\95-fin.txt"
