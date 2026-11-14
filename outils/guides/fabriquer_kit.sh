#!/bin/bash
# Fabrique KIT-GUIDES-<date>.zip (outil, prompt, exemple) : ./fabriquer_kit.sh [dossier de sortie]
set -euo pipefail
ICI="$(cd "$(dirname "$0")" && pwd)"; SORTIE="${1:-$ICI/build}"; DATE="$(date +%Y%m%d)"
TMP="$(mktemp -d)"; K="$TMP/KIT-GUIDES"; mkdir -p "$K/exemple/images" "$SORTIE"
cp "$ICI"/{build_guide.js,package-lock.json,crop_image.swift,pdf_pages.swift,ocr_image.swift,LIRE-KIT.md,PROMPT_GUIDES_AUTRE_LOGICIEL.md,PROMPT_GUIDES_AUTRE_LOGICIEL.txt} "$K/"
cp "$ICI/exemple/exemple.md" "$ICI/exemple/exemple.json" "$K/exemple/"; cp "$ICI/exemple/images/fenetre.png" "$K/exemple/images/"
printf 'node_modules/\nbuild/\n' > "$K/.gitignore"
python3 - "$ICI/package.json" "$K/package.json" "$K/package-lock.json" <<'PY'
import json, sys
p = json.load(open(sys.argv[1])); p['name'] = 'kit-guides'; p['description'] = 'Guides Word et PDF à partir d’un texte en Markdown simplifié'
json.dump(p, open(sys.argv[2], 'w'), indent=2, ensure_ascii=False)
l = json.load(open(sys.argv[3])); l['name'] = 'kit-guides'; l['packages']['']['name'] = 'kit-guides'
json.dump(l, open(sys.argv[3], 'w'), indent=2, ensure_ascii=False)
PY
rm -f "$SORTIE/KIT-GUIDES-$DATE.zip"; (cd "$TMP" && zip -q -r -X "$SORTIE/KIT-GUIDES-$DATE.zip" KIT-GUIDES); rm -rf "$TMP"
echo "$SORTIE/KIT-GUIDES-$DATE.zip"
