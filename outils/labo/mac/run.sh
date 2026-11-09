#!/bin/bash
# run.sh <etape.ps1> [delai] : exécute C:\PestoTest-run\<etape.ps1> DANS la session interactive de labadmin
# (tâche planifiée Interactive, jeton non élevé), puis attend sa fin. Exige une session ouverte sur la console de la VM.
. "$(dirname "$0")/commun.sh"
[ $# -ge 1 ] || { echo "usage : run.sh <etape.ps1> [delai]"; exit 2; }
exec "${PESTO_SSH[@]}" "powershell -NoProfile -ExecutionPolicy Bypass -File C:\\PestoTest-run\\lancer.ps1 -Exe powershell.exe -Arguments \"-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File C:\\PestoTest-run\\$1\" -Dossier C:\\PestoTest-run -Attendre -Delai ${2:-300}"
