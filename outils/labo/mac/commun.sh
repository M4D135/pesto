#!/bin/bash
# Paramètres communs d'accès à PESTO-W11-TEST (VM de test du labo), à sourcer.
# Surcharges possibles par variables d'environnement ; aucune donnée secrète ici (SSH par clé).
# Domaine du labo : config locale non versionnée (outils/labo/labo.local.env, à côté de mac/).
_PESTO_LABO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "$_PESTO_LABO_DIR/labo.local.env" ]; then . "$_PESTO_LABO_DIR/labo.local.env"; fi
: "${PESTO_LABO_DOMAINE:=}"
if [ -z "$PESTO_LABO_NETBIOS" ] && [ -n "$PESTO_LABO_DOMAINE" ]; then
  PESTO_LABO_NETBIOS="$(printf '%s' "${PESTO_LABO_DOMAINE%%.*}" | tr '[:lower:]' '[:upper:]')"
fi
# Texte sûr dans une chaîne AppleScript entre guillemets (barre oblique inverse et guillemet échappés).
pesto_as() { printf '%s' "$1" | sed 's/[\\"]/\\&/g'; }
pesto_exiger_domaine() {
  if [ -z "$PESTO_LABO_DOMAINE" ]; then
    echo "Domaine du labo absent : copier outils/labo/labo.local.env.exemple vers outils/labo/labo.local.env" >&2
    exit 1
  fi
}
: "${PESTO_SAUT:=degun@192.168.1.173}"                       # hôte du labo (DESKTOP-285EKHU), rebond SSH
: "${PESTO_PORT:=2223}"                                      # redirection NAT VirtualBox vers le SSH de la VM
: "${PESTO_COMPTE:=labadmin}"
: "${PESTO_KNOWN_HOSTS:=$HOME/.ssh/known_hosts_pesto}"      # empreinte de la VM, séparée du known_hosts habituel
PESTO_SSH=(ssh -o BatchMode=yes -o ConnectTimeout=30 -o StrictHostKeyChecking=accept-new
  -o UserKnownHostsFile="$PESTO_KNOWN_HOSTS" -J "$PESTO_SAUT" -p "$PESTO_PORT" "$PESTO_COMPTE@127.0.0.1")
PESTO_SCP=(scp -q -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$PESTO_KNOWN_HOSTS"
  -o ProxyJump="$PESTO_SAUT" -P "$PESTO_PORT")
PESTO_DISTANT="$PESTO_COMPTE@127.0.0.1"
