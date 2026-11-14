# Démarre le vrai Pesto (pack PROD de C:\PestoDemo) dans la session et attend la fenêtre principale prête.
Import-Module C:\PestoTest-run\pilote.psm1
. C:\PestoTest-run\demo-commun.ps1
& {
  if (-not (Get-Process powershell -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like '*eveil.ps1*' })) { Start-Process powershell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\PestoTest-run\eveil.ps1' -WorkingDirectory C:\PestoTest-run }
  if (Get-Process | Where-Object { $_.Path -like 'C:\PestoDemo*' }) { 'instance existante conservée (fermer avant pour repartir à neuf)' }
  if (-not (Wait-Fenetre 'Pesto 1\.0$' 3)) { $p = Start-Process C:\PestoDemo\Pesto.exe -WorkingDirectory C:\PestoDemo -PassThru; "Pesto lancé (pid $($p.Id))" }
  $w = Get-Pesto; $fin=(Get-Date).AddSeconds(240); while(-not $w -and (Get-Date) -lt $fin){ $w = Get-Pesto }
  if (-not $w) { 'FENÊTRE PRINCIPALE ABSENTE'; Save-Ecran "$D\00-echec.png"; return }
  Start-Sleep -Seconds 60; Set-Agrandie $w; Save-Fenetre $w "$D\00-demarre.png"; 'Pesto prêt'
} *> "$D\00-demarrer.txt"
