# Arrête toutes les étapes de pilotage lancées depuis C:\PestoTest-run (eveil.ps1 compris), sauf ce script.
# Les processus lancés depuis C:\PestoTest (Pesto, .cmd, tests) relèvent de qui.ps1.
Get-CimInstance Win32_Process | Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match 'PestoTest-run\\' -and $_.CommandLine -notmatch 'stoppilote\.ps1' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue; 'arrete ' + $_.ProcessId + ' ' + $_.CommandLine }
# Tâches PestoPilote-* laissées par un lancer.ps1 interrompu.
Get-ScheduledTask -TaskName 'PestoPilote-*' -ErrorAction SilentlyContinue | ForEach-Object { Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false; 'tache retiree ' + $_.TaskName }
