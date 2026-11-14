# Démo réelle : Interventions et reprises, sélection de l'opération en attente, « Vérifier l’état du poste », relevé.
Import-Module C:\PestoTest-run\pilote.psm1
. C:\PestoTest-run\demo-commun.ps1
& {
  try {
    $w = Get-Pesto; if (-not $w) { throw 'fenêtre principale introuvable' }
    Set-Agrandie $w
    Click-Id $w 'NavHistory'; Start-Sleep -Seconds 2
    Click-Id $w 'BtnInterventions'; Start-Sleep -Seconds 6
    $g = Find-Id $w 'LedgerGrid'
    $rows = @($g.FindAll([System.Windows.Automation.TreeScope]::Children, (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::DataItem))))
    "lignes : $($rows.Count)"
    foreach ($r in $rows) { '  ' + (@($r.FindAll([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Text))) | ForEach-Object { $_.Current.Name }) -join ' | ') }
    Save-Fenetre $w "$D\30-interventions.png"
    $cible = $rows | Where-Object { (@($_.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition) | ForEach-Object { $_.Current.Name }) -join ' ') -match 'P111301VA765003' } | Select-Object -First 1
    if (-not $cible) { throw 'ligne de l''opération P111301VA765003 introuvable' }
    $s=$null; [void]$cible.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern,[ref]$s); $s.Select(); Start-Sleep -Seconds 2
    Save-Fenetre $w "$D\31-intervention-choisie.png"
    Click-Id $w 'LedgerObserve'; Start-Sleep -Seconds 12
    Save-Fenetre $w "$D\32-etat-du-poste.png"
    Get-Arbre $w 16 | Out-File "$D\32-arbre.txt" -Encoding UTF8
    'relevé fait'
  } catch { "ÉCHEC : $($_.Exception.Message)"; try { Save-Ecran "$D\06-echec.png" } catch {} }
} *> "$D\06-verifier.txt"
