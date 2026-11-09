# Démo réelle : « Vérifier puis reprendre » (opération unitaire), « Relire l’état », puis « Consigner la vérification ».
Import-Module C:\PestoTest-run\pilote.psm1
. C:\PestoTest-run\demo-commun.ps1
function Get-StateRoot($w) { if (Find-Id $w 'StateRefresh') { return $w }; $s = Wait-Fenetre 'État du poste|Etat du poste' 5; if ($s) { return $s }; $w }
& {
  try {
    $w = Get-Pesto; if (-not $w) { throw 'fenêtre principale introuvable' }
    Set-Agrandie $w
    for ($k = 0; $k -lt 4 -and ((Find-Id $w 'LedgerGrid') -or (Find-Id $w 'PanelBody')); $k++) { Send-Touches $w '{ESC}'; Start-Sleep -Seconds 2 }
    Click-Id $w 'NavRename'; Start-Sleep -Seconds 3
    Click-Id $w 'SuiteDirectVerify'; Start-Sleep -Seconds 8
    $s = Get-StateRoot $w
    Save-Fenetre $w "$D\75-0-etat-ouvert.png"
    Click-Id $s 'StateRefresh' 60; Start-Sleep -Seconds 25
    $n = Find-Id $s 'StateNext'; "bouton suivant : « $($n.Current.Name) » actif=$($n.Current.IsEnabled)"
    $rep = Find-Id $s 'StateReport'; $p=$null; if ($rep -and $rep.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern,[ref]$p)) { "rapport :`n" + $p.Current.Value }
    $a = Find-Id $s 'StateAdvice'; if ($a) { "conseil : $($a.Current.Name)" }
    Save-Fenetre $w "$D\75-1-etat-relu.png"
    if ($n -and $n.Current.IsEnabled -and $n.Current.Name -match 'Consigner') {
      Invoke-Element $n | Out-Null; Start-Sleep -Seconds 4
      if (Find-Id $w 'PanelAccept') { Save-Fenetre $w "$D\75-2-consigner.png"; "confirmation : " + (Get-PanelText $w); Click-Id $w 'PanelAccept'; Start-Sleep -Seconds 8 }
      Save-Fenetre $w "$D\75-3-consigne.png"
      $a = Find-Id $s 'StateAdvice'; if ($a) { "après : $($a.Current.Name)" }
    }
  } catch { "ÉCHEC : $($_.Exception.Message)"; try { Save-Ecran "$D\75-9-echec.png" } catch {} }
} *> "$D\75-consigner.txt"
