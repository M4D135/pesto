#!/bin/bash
# RÉSERVÉ À DAVID. Suspend (ou rétablit avec --retablir) les mises à jour automatiques de PESTO-W11-TEST.
set -euo pipefail
. "$(dirname "$0")/commun.sh"
K='HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
echo "Attente de la VM (jusqu'à 2 h, Ctrl-C pour abandonner)..."
for i in $(seq 1 240); do "${PESTO_SSH[@]}" "echo pret" >/dev/null 2>&1 && break; sleep 30; done
if [ "${1:-}" = "--retablir" ]; then "${PESTO_SSH[@]}" "reg delete $K /v NoAutoUpdate /f & reg query $K"
else "${PESTO_SSH[@]}" "reg add $K /v NoAutoUpdate /t REG_DWORD /d 1 /f && reg query $K /v NoAutoUpdate"; fi
