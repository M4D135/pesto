#!/bin/bash
# recuperer.sh <chemin Windows avec / > <dossier local> : rapatrie un fichier ou un motif (ex. C:/PestoTest-preuves/phase2/2.9*).
. "$(dirname "$0")/commun.sh"
[ $# -eq 2 ] || { echo "usage : recuperer.sh <C:/chemin/motif> <dossier local>"; exit 2; }
mkdir -p "$2"; exec "${PESTO_SCP[@]}" "$PESTO_DISTANT:$1" "$2/"
