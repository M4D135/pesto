#!/bin/bash
# RÉSERVÉ À DAVID. Active (--nouveau : change d'abord le mot de passe local de labadmin) ou retire (--retirer)
# l'ouverture de session automatique de labadmin sur PESTO-W11-TEST ; --compte DOMAINE\\nom : autre compte (ex. le compte
# de recette LABO\\tech.pesto de la démo réelle). Le mot de passe est tapé ici, masqué, et part par
# l'entrée standard de SSH : jamais sur une ligne de commande, jamais dans un fichier, jamais dans le chat.
# Un modèle ne lance pas ce script et ne manipule jamais ce mot de passe.
set -euo pipefail
. "$(dirname "$0")/commun.sh"
if [ "${1:-}" = "--retirer" ]; then
  "${PESTO_SSH[@]}" 'powershell -NoProfile -ExecutionPolicy Bypass -File C:\PestoTest-run\autologon.ps1 -Retirer'
  exit 0
fi
OPT=""
if [ "${1:-}" = "--compte" ]; then
  CPT="${2:?--compte DOMAINE\\nom}"; DOM="${CPT%%\\*}"; NOM="${CPT#*\\}"
  [ "$DOM" != "$CPT" ] || { echo "Format attendu : DOMAINE\\nom"; exit 1; }
  IFS= read -r -s -p "Mot de passe de $CPT, masqué : " MDP; echo
  [ -n "$MDP" ] || { echo "Vide : rien fait."; exit 1; }
  printf '%s\n' "$MDP" | "${PESTO_SSH[@]}" "powershell -NoProfile -ExecutionPolicy Bypass -File C:\\PestoTest-run\\autologon.ps1 -Activer -Compte $NOM -Domaine $DOM"
  unset MDP; echo "Fait. Effet au prochain démarrage de la VM."; exit 0
fi
if [ "${1:-}" = "--nouveau" ]; then
  echo "Nouveau mot de passe pour labadmin, sur PESTO-W11-TEST seulement."
  IFS= read -r -s -p "Nouveau mot de passe, masqué : " MDP; echo
  IFS= read -r -s -p "Confirmation, masquée : " MDP2; echo
  [ "$MDP" = "$MDP2" ] || { unset MDP MDP2; echo "Les deux saisies diffèrent : rien fait."; exit 1; }
  unset MDP2; OPT=" -Reinitialiser"
else
  IFS= read -r -s -p "Mot de passe Windows de labadmin (PESTO-W11-TEST), masqué : " MDP; echo
fi
[ -n "$MDP" ] || { echo "Vide : rien fait."; exit 1; }
printf '%s\n' "$MDP" | "${PESTO_SSH[@]}" "powershell -NoProfile -ExecutionPolicy Bypass -File C:\\PestoTest-run\\autologon.ps1 -Activer$OPT"
unset MDP
echo "Fait. Effet au prochain démarrage de la VM."
