#!/bin/bash
# g.sh <commande> : exécute une commande sur la VM (session SSH 0, élevée, sans bureau ; pas de WPF ni d'UAC ici).
. "$(dirname "$0")/commun.sh"
exec "${PESTO_SSH[@]}" "$@"
