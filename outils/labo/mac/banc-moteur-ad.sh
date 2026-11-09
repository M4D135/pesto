#!/bin/bash
# RÉSERVÉ À DAVID. Banc moteur sur l'AD réel du labo : PDC, liste des services sur l'inventaire réel, nom pris puis nom
# suivant. Crée une OU de recette et des postes désactivés, puis supprime exactement ce qu'il a créé. Le mot de passe du compte AD
# est tapé ici, masqué, et part par l'entrée standard de SSH : jamais en argument, jamais dans un fichier.
set -euo pipefail
. "$(dirname "$0")/commun.sh"
pesto_exiger_domaine
COMPTE="${1:-${PESTO_LABO_NETBIOS}\\administrateur}"
IFS= read -r -s -p "Mot de passe AD de $COMPTE, masqué : " MDP; echo
[ -n "$MDP" ] || { echo "Vide : rien fait."; exit 1; }
printf '%s\n' "$MDP" | "${PESTO_SSH[@]}" "powershell -NoProfile -ExecutionPolicy Bypass -File C:\\PestoTest-run\\banc-moteur-ad.ps1 -User \"$COMPTE\" -Domain \"$PESTO_LABO_DOMAINE\""
unset MDP
