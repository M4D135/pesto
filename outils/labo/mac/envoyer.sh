#!/bin/bash
# envoyer.sh <fichier...> : copie des fichiers locaux dans C:\PestoTest-run sur la VM.
. "$(dirname "$0")/commun.sh"
[ $# -gt 0 ] || { echo "usage : envoyer.sh <fichier...>"; exit 2; }
exec "${PESTO_SCP[@]}" "$@" "$PESTO_DISTANT:C:/PestoTest-run/"
