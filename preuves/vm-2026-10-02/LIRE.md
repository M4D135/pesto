# Campagne 2 — VM PESTO-W11-TEST, 2 octobre 2026 (phases 0 et 1)

- Machine : `PESTO-W11-TEST` (VirtualBox 7.2 sur l'hôte du labo, mode NEM), Windows 11 Entreprise Évaluation 25H2,
  build 26200.6584, **hors domaine** (groupe `LABO`), DC `dc01.labo.local` joignable.
- Moteur : **Windows PowerShell 5.1.26100.6584 Desktop**, .NET 4.8.1 (533509).
- Session : **SSH OpenSSH non interactive**, compte `labadmin`. Pas de bureau, pas d'UAC, pas d'AD.
- Pack : `DEV/` du commit `9ee3fe2` (branche `cloud/points-suite`) copié dans `C:\PestoTest`, `outils/` dans `C:\outils`.
  `Pesto.exe` SHA-256 `8c723efb7936d4322770a673f80b462d41ab10179d5b4d0b59cb51ad0856dae8` (clang/lld 23.1.2, Mac).
- Instantané avant campagne : `02-groupe-de-travail-pret`, pris à froid.

Le script de campagne a été lancé avec `-ExecutionPolicy Bypass`, hérité par ses sous-processus. `Pesto.exe`, `TESTER.cmd` et
`TEST_RC23.cmd` imposent eux-mêmes `RemoteSigned` : leurs résultats ne dépendent pas de cet héritage. 1.1 et 1.5 ont été
rejoués avec `-ExecutionPolicy RemoteSigned` explicite (`*-RemoteSigned.txt`, `*-corrige.txt`).

| N° | Résultat | Preuve |
|---|---|---|
| 1.1 | PASS : 68 fichiers, 0 erreur (vrai parseur 5.1) | `1.1-parse_all-RemoteSigned.txt` |
| 1.2 | PASS : code 0, Runtime PASS, 38 composants, ParsedFiles=27, EmbeddedScripts=3, AuditWriter=PASS | `1.2-check.json` |
| 1.3 | Partiel : `--check --quiet` code 0 ; la boîte de message reste à voir en console | `resume.txt` |
| 1.4 | PASS après décision (02/10) : binaire 1.0.0.0 ; chaînes ProductVersion « 1.0 », ProductName « Pesto - Gestion des Postes » conservées, documents alignés | `1.4-versions.txt` |
| 1.5 | 19/20 puis **20/20** après correction du test `DEBLOQUER_TOUT` (il signalait `check.json` écrit par 1.2) | `1.5-*.txt` |
| 1.6 | PASS : `TESTER.cmd` code 0, 5 suites, 239 OK/PASS | `1.6-TESTER.txt` (UTF-16) |
| 1.7 | PASS : 65 PASS, 0 FAIL | `1.7-TEST_RC23.txt` (UTF-16) |
| 1.8 | Non joué : pas de Python (alias Store seulement) | — |
| 1.9 | PASS : refus avant connexion, `wad/Pesto-Names.ps1:204:1` | `1.9-copie-alteree.txt` (UTF-16) |
| 1.10 | PASS : valide 0, invalide 20 (`INVALID_DRAFT`), rapport existant refusé (1) | `1.10-rapport-*.json` |

**Ce que ça ne prouve pas** : aucune fenêtre affichée à un humain (les cas WPF tournent hors écran), aucune UAC, aucun
accès AD, aucune mutation. Phases 2 à 5 à jouer en console.
