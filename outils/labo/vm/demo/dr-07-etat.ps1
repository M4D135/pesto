# Démo réelle : page « Un poste », état de l'opération unitaire en attente ; relevé des boutons.
Import-Module C:\PestoTest-run\pilote.psm1
. C:\PestoTest-run\demo-commun.ps1
& {
  try {
    $w = Get-Pesto; if (-not $w) { throw 'fenêtre principale introuvable' }
    Set-Agrandie $w
    for ($k = 0; $k -lt 3 -and (Find-Id $w 'LedgerGrid'); $k++) { Send-Touches $w '{ESC}'; Start-Sleep -Seconds 2 }
    "panneau Interventions ouvert : " + [bool](Find-Id $w 'LedgerGrid')
    Click-Id $w 'NavRename'; Start-Sleep -Seconds 3
    Save-Fenetre $w "$D\33-unposte-attente.png"
    Get-Arbre $w 14 | Where-Object { $_ -match 'Button|Text "(Vérif|Une op|Reprise|État)' -and $_ -notmatch 'hors-ecran' } | Out-File "$D\33-boutons.txt" -Encoding UTF8
    $b = Find-Id $w 'SuiteDirectVerify'
    if ($b) { "SuiteDirectVerify : « $($b.Current.Name) » actif=$($b.Current.IsEnabled)" }
    $b2 = Find-Id $w 'SuitePostState'; if ($b2) { "SuitePostState : « $($b2.Current.Name) » actif=$($b2.Current.IsEnabled)" }
  } catch { "ÉCHEC : $($_.Exception.Message)" }
} *> "$D\07-etat.txt"
