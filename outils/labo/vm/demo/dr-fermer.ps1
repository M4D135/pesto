# Ferme les panneaux ouverts puis la fenêtre principale de Pesto (comme l'utilisateur), sans tuer de processus.
Import-Module C:\PestoTest-run\pilote.psm1
. C:\PestoTest-run\demo-commun.ps1
& {
  foreach ($sec in @([System.Windows.Automation.AutomationElement]::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children,[System.Windows.Automation.Condition]::TrueCondition) | Where-Object { $_.Current.Name -like 'Pesto |*' })) { $f = Find-Element $sec 'Fermer' 'Button'; if ($f) { Invoke-Element $f | Out-Null; Start-Sleep -Seconds 2; "fermé : $($sec.Current.Name)" } }
  $w = Wait-Fenetre 'Pesto 1\.0' 10
  if (-not $w) { 'aucune fenêtre Pesto'; return }
  foreach ($id in 'LedgerClose','StateClose','PanelCancel','PanelClose') { $e = Find-Id $w $id; if ($e -and $e.Current.IsEnabled) { Invoke-Element $e | Out-Null; Start-Sleep -Seconds 2; "panneau fermé : #$id" } }
  $p=$null; if ($w.TryGetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern,[ref]$p)) { $p.Close(); 'fenêtre fermée' }
  $fin=(Get-Date).AddSeconds(40); while((Get-Date) -lt $fin -and (Get-Process | Where-Object { $_.Path -like 'C:\PestoDemo*' })){ Start-Sleep -Seconds 2 }
  'processus Pesto restants : ' + @(Get-Process | Where-Object { $_.Path -like 'C:\PestoDemo*' }).Count
} *> "$D\fermer.txt"
