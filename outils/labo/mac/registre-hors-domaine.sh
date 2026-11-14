#!/bin/bash
# RÉSERVÉ À DAVID. Registre partagé depuis un compte Windows local (poste hors domaine) sur PESTO-W11-TEST, 08/10/2026 :
# partage de test ouvert au seul compte AD de recette, accès refusé au jeton local, puis registre et verrou d'opération
# de Pesto avec le compte AD ; partage et dossier supprimés à la fin.
# Mot de passe de LABO\tech.pesto tapé ici, masqué, transmis par l'entrée standard de SSH : jamais en argument ni fichier.
set -euo pipefail
. "$(dirname "$0")/commun.sh"
pesto_exiger_domaine
COMPTE="${1:-${PESTO_LABO_NETBIOS}\\tech.pesto}"
if [ -t 0 ]; then IFS= read -r -s -p "Mot de passe AD de $COMPTE, masqué : " MDP; echo
else MDP=$(osascript -e "display dialog \"Registre partagé hors domaine (Pesto) : mot de passe AD de $(pesto_as "$COMPTE")\" default answer \"\" with hidden answer with title \"Pesto : registre\" buttons {\"Annuler\", \"OK\"} default button \"OK\" giving up after 600" -e 'text returned of result' 2>/dev/null) || { echo "Annulé : rien fait."; exit 1; }; fi
[ -n "$MDP" ] || { echo "Vide : rien fait."; exit 1; }
printf '%s\n' "$MDP" | "${PESTO_SSH[@]}" "powershell -NoProfile -ExecutionPolicy Bypass -File C:\\PestoTest-run\\registre-hors-domaine.ps1 -User \"$COMPTE\"" 2>&1 | tee "${PESTO_HD_LOG:-$HOME/.pesto-registre-hors-domaine.log}"
unset MDP
