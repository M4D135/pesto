#!/bin/bash
# Tests visibles du 08/10 au soir (après demo-reelle.sh --preparer, autologon du compte de recette et --apres-redemarrage) :
# renommage même site, reprise après redémarrage, changement de site, reprise, deux Pesto côte à côte. Captures dans la
# session (fenêtres) et de l'écran entier de la VM depuis l'hôte (VBoxManage), copiées dans le dossier local $1.
. "$(dirname "$0")/commun.sh"
cd "$(dirname "$0")"
R="${1:?dossier local des captures}"; mkdir -p "$R"
Q="$(mktemp)"
VB='"C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"'
ecran() { ssh -o BatchMode=yes degun@192.168.1.173 "$VB controlvm PESTO-W11-TEST screenshotpng C:\\Users\\degun\\pesto-ecran.png" >/dev/null 2>&1 && scp -q -o BatchMode=yes "degun@192.168.1.173:C:/Users/degun/pesto-ecran.png" "$R/vm-$1.png" && echo "écran : $R/vm-$1.png"; }
probe() { ( ./g.sh 'hostname' > "$Q" 2>&1 & p=$!; sleep 12; kill $p 2>/dev/null ); grep -q -i -E 'P111301|PESTO' "$Q"; }
redemarrer() {
  echo "== redémarrage"; ./g.sh 'shutdown /r /t 3' >/dev/null 2>&1; sleep 60
  ok=0; for i in $(seq 1 12); do probe && { ok=1; break; }; done
  if [ $ok = 0 ]; then echo "VM figée : réinitialisation"; ssh -o BatchMode=yes degun@192.168.1.173 "$VB controlvm PESTO-W11-TEST reset"; for i in $(seq 1 20); do probe && break; done; fi
  echo "nom : $(tr -d '\r' < "$Q")"; sleep 40; ecran "$2-ouverture-session"
}
etape() { echo "== $1"; ./sess.sh "$1" "${2:-700}" | tail -1; ./recuperer.sh 'C:/PestoTest-preuves/demo-reelle/captures/*' "$R/" >/dev/null 2>&1; ecran "${1%.ps1}"; }
./envoyer.sh ../vm/demo/demo-commun.ps1 ../vm/demo/dr-*.ps1 ../vm/demo/t-*.ps1 >/dev/null
etape dr-00-demarrer.ps1 420; etape t-30-deux-pesto.ps1 700; cat "$R/t30-deux-pesto.txt" 2>/dev/null | tail -6
./sess.sh dr-fermer.ps1 120 | tail -1
etape dr-00-demarrer.ps1 420; etape t-10-renommer.ps1 800; cat "$R/t10-op.txt" 2>/dev/null | tail -8
redemarrer x t10; etape t-15-reprise.ps1 700; cat "$R/t15-verification.txt" 2>/dev/null | tail -10
etape t-20-site.ps1 800; cat "$R/t20-op.txt" 2>/dev/null | tail -8
redemarrer x t20; etape t-25-reprise.ps1 700; cat "$R/t25-verification.txt" 2>/dev/null | tail -10
echo "== FIN"; rm -f "$Q"
