#!/bin/bash
# Démo réelle : enchaîne les vraies opérations Pesto et leurs captures (renommage même site, vérification, changement de
# site, vérification, écrans), avec redémarrages de la VM (réinitialisée si elle se fige). Sans mot de passe.
. "$(dirname "$0")/commun.sh"
cd "$(dirname "$0")"
R="${1:?dossier local des captures}"; mkdir -p "$R"
Q="$(mktemp)"
probe() { ( ./g.sh 'hostname' > "$Q" 2>&1 & p=$!; sleep 12; kill $p 2>/dev/null ); grep -q -i -E 'P111301|PESTO' "$Q"; }
redemarrer() {
  echo "== redémarrage"; ./sess.sh dr-fermer.ps1 120 | tail -1; ./g.sh 'shutdown /r /t 3' >/dev/null 2>&1; sleep 60
  ok=0; for i in $(seq 1 12); do probe && { ok=1; break; }; done
  if [ $ok = 0 ]; then echo "VM figée : réinitialisation"; ssh -o BatchMode=yes degun@192.168.1.173 '"C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" controlvm PESTO-W11-TEST reset' | tail -1
    for i in $(seq 1 20); do probe && break; done; fi
  echo "nom : $(tr -d '\r' < "$Q")"; sleep 45
}
etape() { echo "== $1"; ./sess.sh "$1" "${2:-600}" | tail -1; ./recuperer.sh 'C:/PestoTest-preuves/demo-reelle/captures/*' "$R/" >/dev/null 2>&1; }
./envoyer.sh ../vm/demo/demo-commun.ps1 ../vm/demo/dr-*.ps1 >/dev/null
redemarrer; etape dr-00-demarrer.ps1 420; etape dr-13-renommer.ps1 700; cat "$R/70-op.txt" 2>/dev/null | tail -4
redemarrer; etape dr-00-demarrer.ps1 420; etape dr-75-verifier.ps1 500; tail -3 "$R/75-consigner.txt" 2>/dev/null
etape dr-14-site.ps1 700; cat "$R/80-op.txt" 2>/dev/null | tail -4
redemarrer; etape dr-00-demarrer.ps1 420; etape dr-85-verifier.ps1 500; tail -3 "$R/85-consigner.txt" 2>/dev/null
etape dr-90-ecrans.ps1 600; tail -4 "$R/90-ecrans.txt" 2>/dev/null
echo "== FIN"; rm -f "$Q"
