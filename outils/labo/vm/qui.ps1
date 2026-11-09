Get-CimInstance Win32_Process | Where-Object { ($_.CommandLine -match "PestoTest\\" -or $_.ExecutablePath -match "PestoTest\\") -and $_.CommandLine -notmatch "PestoTest-run|qui\.ps1" } | ForEach-Object { "{0} {1} {2}" -f $_.ProcessId, $_.Name, $_.CommandLine; Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep 3
Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match "PestoTest-run\\(e|obs|clic|enoms|p)" } | ForEach-Object { "pilote encore actif : {0} {1}" -f $_.ProcessId, $_.CommandLine }
