# Démo réelle : garder l'écran éveillé, lancer le vrai Pesto (pack PROD, cfg réel), attendre la fenêtre, capturer, relever l'arbre UIA.
Import-Module C:\PestoTest-run\pilote.psm1
$D = 'C:\PestoTest-preuves\demo-reelle\captures'; New-Item -ItemType Directory -Force $D | Out-Null
$log = "$D\01-lancer.txt"
& {
  "session : $([Environment]::UserDomainName)\$([Environment]::UserName) ; élevé : " + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not (Get-Process powershell -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like '*eveil.ps1*' })) { Start-Process powershell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\PestoTest-run\eveil.ps1' -WorkingDirectory C:\PestoTest-run }
  $p = Start-Process C:\PestoDemo\Pesto.exe -WorkingDirectory C:\PestoDemo -PassThru
  "Pesto.exe lancé : pid $($p.Id)"
  $w = Wait-Fenetre 'Pesto' 240
  if (-not $w) { 'FENÊTRE PESTO NON TROUVÉE'; Get-Fenetres | Format-Table -AutoSize | Out-String -Width 220; Save-Ecran "$D\01-sans-fenetre.png"; return }
  "fenêtre : $($w.Current.Name)"
  Start-Sleep -Seconds 90
  Set-Premier $w
  Save-Ecran "$D\01-premier-ecran.png"
  Get-Arbre $w 9 | Out-File "$D\01-arbre.txt" -Encoding UTF8
  'arbre relevé'
} *> $log
