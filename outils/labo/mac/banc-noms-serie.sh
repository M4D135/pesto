#!/bin/bash
# RÉSERVÉ À DAVID. Banc « série d'un nom pris » sur l'AD réel du labo (08/10) : OU de recette et 4 comptes désactivés
# créés, lectures de série de Pesto exécutées, nom proposé ensuite vérifié, puis tout ce qui a été créé est supprimé.
# Le mot de passe du compte AD est tapé ici, masqué, et part par l'entrée standard de SSH : jamais en argument ni fichier.
set -euo pipefail
. "$(dirname "$0")/commun.sh"
pesto_exiger_domaine
COMPTE="${1:-${PESTO_LABO_NETBIOS}\\administrateur}"
if [ -t 0 ]; then IFS= read -r -s -p "Mot de passe AD de $COMPTE, masqué : " MDP; echo
else MDP=$(osascript -e "display dialog \"Banc série de noms (Pesto) : mot de passe AD de $(pesto_as "$COMPTE")\" default answer \"\" with hidden answer with title \"Pesto : banc AD\" buttons {\"Annuler\", \"OK\"} default button \"OK\" giving up after 600" -e 'text returned of result' 2>/dev/null) || { echo "Annulé : rien fait."; exit 1; }; fi
[ -n "$MDP" ] || { echo "Vide : rien fait."; exit 1; }
printf '%s\n' "$MDP" | "${PESTO_SSH[@]}" "powershell -NoProfile -ExecutionPolicy Bypass -File C:\\PestoTest-run\\banc-noms-serie.ps1 -User \"$COMPTE\" -Domain \"$PESTO_LABO_DOMAINE\""
unset MDP
"${PESTO_SSH[@]}" "type C:\\PestoTest-run\\banc-noms-serie.txt"
