Import-Module C:\PestoTest-run\pilote.psm1
$D = "C:\PestoTest-preuves\phase2"; New-Item -ItemType Directory -Force $D | Out-Null
& { "session : " + [Environment]::UserName + " ; interactive=" + [Environment]::UserInteractive; whoami /groups | Select-String "Mandatory Label"; Save-Ecran "$D\00-bureau.png"; Get-Fenetres | Format-Table -AutoSize | Out-String -Width 200 } *> "$D\00-bureau.txt"
