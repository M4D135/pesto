#!/bin/bash
# Pour chaque banc PowerShell portable en échec sur la branche filtrée : bissection entre master (bon) et HEAD, annulation
# (git revert) du premier commit fautif, nouvel essai, jusqu'à ce que le banc passe. Mécanique, sans relecture.
# Usage : bisect_revert.sh WORKTREE BANC [BANC...]
set -u
REPO="$1"; shift
PW="$HOME/Documents/Codex/2026-10-12/tu-x20/work/pesto-runtime/powershell-7.4.20/pwsh"
export PATH=/opt/homebrew/opt/llvm/bin:/opt/homebrew/opt/lld/bin:$PATH
GEN="DEV/wad/Pesto.Engine.Runtime.ps1 DEV/wad/Pesto.Engine.psm1 DEV/wad/Pesto.Engine.psd1 DEV/wad/Pesto.Engine.build.json DEV/wad/package.json DEV/tools/launcher/pesto_runtime.h DEV/tools/launcher/last-build.json DEV/Pesto.exe"
cd "$REPO" || exit 2
TEST="$REPO/../bisect-test.sh"
cat > "$TEST" <<EOF
#!/bin/bash
cd "$REPO/DEV" || exit 125
git -C "$REPO" checkout -q -- $GEN 2>/dev/null
"$PW" -NoProfile -File tools/Build-PestoEngineModule.ps1 >/dev/null 2>&1 || { git -C "$REPO" checkout -q -- $GEN; exit 125; }
"$PW" -NoProfile -File "tests/Run-\${BANC}Tests.ps1" >/dev/null 2>&1; rc=\$?
git -C "$REPO" checkout -q -- $GEN 2>/dev/null
[ \$rc -eq 0 ] && exit 0 || exit 1
EOF
chmod +x "$TEST"
for BANC in "$@"; do
  export BANC
  for essai in 1 2 3 4 5 6; do
    if "$TEST"; then echo "$BANC : passe"; break; fi
    git bisect start HEAD master >/dev/null 2>&1
    out=$(git bisect run "$TEST" 2>&1)
    bad=$(echo "$out" | grep -m1 -oE '^[0-9a-f]{7,40} is the first bad commit' | cut -d' ' -f1)
    git bisect reset >/dev/null 2>&1
    if [ -z "$bad" ]; then echo "$BANC : bissection sans conclusion"; echo "$out" | tail -3; break; fi
    subj=$(git log -1 --format=%s "$bad")
    if git revert --no-edit "$bad" >/dev/null 2>&1; then echo "$BANC : annulé $bad ($subj)"
    else git revert --abort >/dev/null 2>&1; echo "$BANC : annulation impossible de $bad ($subj)"; break; fi
  done
done
git checkout -q -- $GEN 2>/dev/null
echo fini
