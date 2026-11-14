#!/bin/bash
# obs.sh <id> <motif-de-titre-sans-espace> [delai] [dossier local] : observe une fenêtre dans la session interactive
# (titre, UAC, connexions au DC, processus, capture, arbre UI Automation) puis rapatrie <id>.txt et <id>*.png.
. "$(dirname "$0")/commun.sh"
[ $# -ge 2 ] || { echo "usage : obs.sh <id> <motif> [delai] [dossier local]"; exit 2; }
L="${4:-./phase2}"
"${PESTO_SSH[@]}" "powershell -NoProfile -ExecutionPolicy Bypass -File C:\\PestoTest-run\\lancer.ps1 -Exe powershell.exe -Arguments \"-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File C:\\PestoTest-run\\obs.ps1 -Id $1 -Motif $2 -Delai ${3:-120}\" -Dossier C:\\PestoTest-run -Attendre -Delai $(( ${3:-120} + 280 ))" \
  && "${PESTO_SSH[@]}" "type C:\\PestoTest-preuves\\phase2\\$1.txt" \
  && mkdir -p "$L" && "${PESTO_SCP[@]}" "$PESTO_DISTANT:C:/PestoTest-preuves/phase2/$1*.png" "$L/"; ls "$L" | grep "^$1"
