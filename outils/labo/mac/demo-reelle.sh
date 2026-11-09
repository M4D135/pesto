#!/bin/bash
# RÉSERVÉ À DAVID. Démo réelle de Pesto sur PESTO-W11-TEST pour les captures des guides (AD du labo, objets de recette).
#   ./demo-reelle.sh --preparer [DOMAINE\admin]   OU de recette, postes, compte LABO\tech.pesto, jonction de la VM,
#                                                  cfg.json réel ; demande le mot de passe AD d'administration puis celui à
#                                                  donner au compte de recette (deux fois).
#   ./demo-reelle.sh --preparer-sans-jonction    idem, mais ce PC reste hors domaine : Pesto fera la jonction (tests visibles du
#                                                  08/10 soir) ; cfg avec registre partagé local, réservation AD, reprise RunOnce.
#   ./demo-reelle.sh --apres-redemarrage           après le redémarrage qui suit la jonction : tech.pesto administrateur local,
#                                                  DevicePasswordLessBuildVersion=0 (ouverture automatique). Sans mot de passe.
#   ./demo-reelle.sh --nettoyer [DOMAINE\admin]    supprime exactement les objets de recette ; la VM est ensuite remise
#                                                  par son instantané « 04-avant-demo-reelle ».
# Mots de passe tapés ici, masqués, transmis par l'entrée standard de SSH : jamais en argument ni dans un fichier.
# Variante choisie par David pour ces VM jetables : PESTO_DEMO_MDP='…' devant la commande (saisie par lui seul).
# Sortie copiée dans ~/.pesto-demo-reelle.log (sans mot de passe).
set -euo pipefail
. "$(dirname "$0")/commun.sh"
pesto_exiger_domaine
ACTION="${1:-}"; COMPTE="${2:-${PESTO_LABO_NETBIOS}\\administrateur}"
case "$ACTION" in
  --preparer|--preparer-sans-jonction)
    SANS=""; [ "$ACTION" = "--preparer-sans-jonction" ] && SANS=" -SansJonction"
    if [ -n "${PESTO_DEMO_MDP:-}" ] && [ "$PESTO_DEMO_MDP" != "TON_MOT_DE_PASSE" ]; then MDP="$PESTO_DEMO_MDP"; unset PESTO_DEMO_MDP
    elif [ -t 0 ]; then IFS= read -r -s -p "Mot de passe AD de $COMPTE (servira aussi pour ${PESTO_LABO_NETBIOS}\\tech.pesto), masqué : " MDP; echo
    else
      # Lancé sans terminal (bouton Run, « ! ») : fenêtre macOS à saisie masquée, tapée par David.
      MDP=$(osascript -e "display dialog \"Mot de passe AD de $(pesto_as "$COMPTE") (sert aussi pour ${PESTO_LABO_NETBIOS}\\\\tech.pesto)\" default answer \"\" with hidden answer with title \"Pesto : démo réelle\" buttons {\"Annuler\", \"OK\"} default button \"OK\" giving up after 600" -e 'text returned of result' 2>/dev/null) || { echo "Annulé : rien fait."; exit 1; }
    fi
    [ -n "$MDP" ] || { unset MDP; echo "Vide : rien fait."; exit 1; }
    MDP2="$MDP"
    echo "Préparation en cours sur la VM (1 à 2 minutes)…"
    printf '%s\n%s\n' "$MDP" "$MDP2" | "${PESTO_SSH[@]}" "powershell -NoProfile -ExecutionPolicy Bypass -File C:\\PestoTest-run\\demo-reelle.ps1 -Preparer$SANS -User \"$COMPTE\" -Domain \"$PESTO_LABO_DOMAINE\"" 2>&1 | tee "${PESTO_DEMO_LOG:-$HOME/.pesto-demo-reelle.log}"
    unset MDP MDP2
    echo "Ensuite : ./autologon.sh --compte '${PESTO_LABO_NETBIOS}\\tech.pesto' (même mot de passe que ci-dessus), puis DevicePasswordLessBuildVersion=0 comme d'habitude."
    ;;
  --joindre)
    if [ -t 0 ]; then IFS= read -r -s -p "Mot de passe AD de $COMPTE, masqué : " MDP; echo
    else MDP=$(osascript -e "display dialog \"Jonction de la VM : mot de passe AD de $(pesto_as "$COMPTE")\" default answer \"\" with hidden answer with title \"Pesto : jonction\" buttons {\"Annuler\", \"OK\"} default button \"OK\" giving up after 600" -e 'text returned of result' 2>/dev/null) || { echo "Annulé : rien fait."; exit 1; }; fi
    [ -n "$MDP" ] || { echo "Vide : rien fait."; exit 1; }
    printf '%s\n' "$MDP" | "${PESTO_SSH[@]}" "powershell -NoProfile -ExecutionPolicy Bypass -File C:\\PestoTest-run\\demo-reelle.ps1 -Joindre -User \"$COMPTE\" -Domain \"$PESTO_LABO_DOMAINE\"" 2>&1 | tee -a "${PESTO_DEMO_LOG:-$HOME/.pesto-demo-reelle.log}"
    unset MDP
    ;;
  --admin-local|--apres-redemarrage)
    "${PESTO_SSH[@]}" "powershell -NoProfile -ExecutionPolicy Bypass -File C:\\PestoTest-run\\demo-reelle.ps1 -AdminLocal -User \"$COMPTE\" -Domain \"$PESTO_LABO_DOMAINE\""
    ;;
  --nettoyer)
    if [ -t 0 ]; then IFS= read -r -s -p "Mot de passe AD de $COMPTE, masqué : " MDP; echo
    else MDP=$(osascript -e "display dialog \"Nettoyage de la démo réelle : mot de passe AD de $(pesto_as "$COMPTE")\" default answer \"\" with hidden answer with title \"Pesto : nettoyage\" buttons {\"Annuler\", \"OK\"} default button \"OK\" giving up after 600" -e 'text returned of result' 2>/dev/null) || { echo "Annulé : rien fait."; exit 1; }; fi
    [ -n "$MDP" ] || { echo "Vide : rien fait."; exit 1; }
    printf '%s\n' "$MDP" | "${PESTO_SSH[@]}" "powershell -NoProfile -ExecutionPolicy Bypass -File C:\\PestoTest-run\\demo-reelle.ps1 -Nettoyer -User \"$COMPTE\" -Domain \"$PESTO_LABO_DOMAINE\""
    unset MDP
    ;;
  *) echo "Usage : $0 --preparer|--admin-local|--nettoyer [DOMAINE\\admin]"; exit 2 ;;
esac
