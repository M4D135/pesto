#!/bin/bash
# sess.sh <etape.ps1> [delai] : exécute C:\PestoTest-run\<etape.ps1> dans la session console du compte $PESTO_SESSION
# (défaut LABO\tech.pesto, démo réelle), jeton ÉLEVÉ (pour piloter Pesto élevé), puis attend sa fin.
. "$(dirname "$0")/commun.sh"
pesto_exiger_domaine
[ $# -ge 1 ] || { echo "usage : sess.sh <etape.ps1> [delai]"; exit 2; }
C="${PESTO_SESSION:-${PESTO_LABO_NETBIOS}\\tech.pesto}"
exec "${PESTO_SSH[@]}" "powershell -NoProfile -ExecutionPolicy Bypass -File C:\\PestoTest-run\\lancer.ps1 -Exe powershell.exe -Arguments \"-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File C:\\PestoTest-run\\$1\" -Dossier C:\\PestoTest-run -Attendre -Delai ${2:-300} -Eleve -Compte \"$C\""
