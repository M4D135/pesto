#!/bin/bash
# Reprise locale de Pesto (Mac) après le travail dans le cloud.
# Usage : bash outils/reprise_locale.sh [chemin du dépôt pesto]
# Ne fait ni commit, ni push, ni suppression. S'arrête si la copie locale a des modifications.
# Compatible bash 3.2 (macOS).
set -euo pipefail

BRANCHE="master"
DEPOT="${1:-$(pwd)}"

etape() { printf '\n=== %s\n' "$1"; }
echec() { printf '\nARRET : %s\n' "$1" >&2; exit 1; }

etape "Dépôt : $DEPOT"
cd "$DEPOT" || echec "dossier introuvable"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || echec "ce n'est pas un dépôt Git"
[ -f CLAUDE.md ] && [ -d DEV/wad ] || echec "ce n'est pas le dépôt pesto (CLAUDE.md ou DEV/wad absent)"
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  git status --short --untracked-files=no
  echec "modifications locales non commitées : les commiter ou les mettre de côté (git stash), puis relancer"
fi

etape "Récupération de $BRANCHE"
git fetch origin "$BRANCHE"
if git show-ref --verify --quiet "refs/heads/$BRANCHE"; then
  git checkout "$BRANCHE"
  git merge --ff-only "origin/$BRANCHE" || echec "la branche locale a divergé de origin/$BRANCHE : à régler à la main"
else
  git checkout -b "$BRANCHE" "origin/$BRANCHE"
fi
git log --oneline -3

etape "Outils (clang + lld-link, python3, pwsh)"
for d in /opt/homebrew/opt/llvm/bin /opt/homebrew/opt/lld/bin /usr/local/opt/llvm/bin /usr/local/opt/lld/bin; do
  [ -d "$d" ] && PATH="$d:$PATH"
done
export PATH
command -v python3 >/dev/null || echec "python3 absent"
command -v clang >/dev/null || echec "clang absent (brew install llvm lld)"
command -v lld-link >/dev/null || echec "lld-link absent (brew install llvm lld)"
clang --version | head -1
lld-link --version | head -1
if command -v pwsh >/dev/null; then pwsh -v; else echo "pwsh absent : contrôles PowerShell 7 sautés (brew install --cask powershell)"; fi

cd DEV

etape "wad/cfg.json (créé depuis le modèle seulement s'il manque)"
python3 tools/prepare_dev.py

etape "Reconstruction locale de l'EXE puis du manifeste"
python3 tools/launcher/build_native.py
python3 tools/refresh_manifest.py
python3 tools/refresh_manifest.py --check

etape "Tests portables"
python3 -m unittest discover -s tests -p "test_*.py" 2>&1 | tail -3
python3 tools/checks/validate_pesto.py | tail -1
python3 tools/checks/run_native_portable.py | tail -1
if command -v pwsh >/dev/null; then
  pwsh -NoProfile -File ../outils/parse_all.ps1 -Root . | tail -1
  pwsh -NoProfile -File tests/Run-StabilisationTests.ps1 | tail -1
fi

etape "Empreinte à reporter dans la fiche de traçabilité de la recette"
shasum -a 256 Pesto.exe
echo "Fichiers modifiés par le build (à commiter dans la session Claude Code) :"
git status --short

cd ..
PROMPT="Reprise locale de Pesto sur $BRANCHE. Lis les décisions actuelles de CLAUDE.md et DEV/docs/V1_CONSTATS_OUVERTS.md. outils/reprise_locale.sh vient de reconstruire l'EXE et le manifeste et de lancer les tests portables : vérifie les résultats avant de commiter les fichiers de cette passe. Conserve les deux packs DEV et PROD. Décision David du 12/10 : tests locaux uniquement, aucune VM ni AD ; toute recette Windows doit faire l'objet d'une nouvelle demande explicite."

etape "Lancement de Claude Code"
if command -v claude >/dev/null; then
  exec claude "$PROMPT"
else
  echo "Commande claude absente. Installer Claude Code, puis lancer dans $DEPOT :"
  echo "claude \"$PROMPT\""
fi
