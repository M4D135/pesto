# Campagne 5 — VM PESTO-W11-TEST, 4 octobre 2026 (L4, X5, O7, L6)

- Session console de `labadmin` (ouverture automatique activée par David, mot de passe tapé par lui, jamais vu par
  Claude), Windows PowerShell 5.1, hors domaine. Aucune action AD, aucune mutation.
- Pilotage par Claude, sans humain à l'écran : SSH, tâches planifiées interactives (jeton non élevé), captures, UI
  Automation. Ce n'est pas une relecture visuelle par un utilisateur.
- EXE : `8fd5bd8c…` (commit `abd6c2e`, clang/lld 23.1.2) pour L4 final, X5 et O7. L6 : pack PROD construit à 16 h 04
  (EXE `8c4592dd…`, build intermédiaire de la même série) ; le résultat porte sur les droits, pas sur le code.

| Constat | Résultat | Preuve |
|---|---|---|
| L4 | Codes conformes : 0, 120, 123, 124, 125, 126, 128. Premier passage : racine d'un lecteur sous `--quiet` = boîte de message et code 1 ; corrigé dans `abd6c2e` (arguments lus avant les contrôles d'emplacement), puis 123 sans boîte | `l4-codes.txt`, `v-l4.ps1`, `l4-128.txt`, `l4-128.png` |
| X5 | Thème Contraste élevé : bordure Highlight sur le bouton de menu actif (Accueil) et sur le bouton sous le focus clavier ; onglet actif non capturé ; contraste élevé remis à son état d'origine (flags 126) | `x5.txt`, `x5-contraste-*.png`, `x5-retour.png` |
| O7 | `VERIFIER_UAC.cmd` : contrôle préalable passé, vraie invite UAC (`consent.exe` présent). Invite fermée par `taskkill` (bureau sécurisé hors d'atteinte) : « Incorrect function », boîte « démarrage impossible », code 1, rien lancé. **Accepter / Refuser restent à faire par un humain** | `o7.txt`, `o7-ecran.png` |
| L6 | Pack sous `C:\Program Files\Pesto-PROD-test` : droits hérités, `BUILTIN\Users` en RX, propriétaire Administrators ; écriture non élevée dans `wad` refusée ; `--check --quiet` et `--check-json` = 0 sans élévation (Runtime PASS, 38 composants) ; pas de `wad\logs` créé | `l6-acl.txt`, `l6-prod.txt`, `eprod.ps1` |

`l4-codes.txt` est recopié de la sortie console SSH de `v-l4.ps1` ; les autres `.txt` sont les fichiers écrits sur la VM
(convertis d'UTF-16 en UTF-8).
