#!/bin/bash
# vps.sh <fichier.ps1> : exécute un script PowerShell sur la VM de labo dans la session SSH (0, élevée, sans bureau),
# en -EncodedCommand (l'imbrication des quotes casse sinon). Sortie texte, diagnostics conservés.
set -u
. "$(dirname "$0")/commun.sh"
F="${1:-}"; [ -f "$F" ] || { echo "usage : vps.sh <fichier.ps1>"; exit 2; }
B=$(python3 -c "import base64,sys
d=open(sys.argv[1],'rb').read()
print(base64.b64encode(d.decode('utf-8-sig').encode('utf-16le')).decode())" "$F") || exit 2
# Pas de filtre : il pourrait effacer une erreur et substituer son code de sortie à celui de SSH.
# -OutputFormat Text demande à PowerShell du texte plutôt que des objets sérialisés CLIXML.
exec "${PESTO_SSH[@]}" "powershell -NoProfile -ExecutionPolicy Bypass -NonInteractive -OutputFormat Text -EncodedCommand $B"
