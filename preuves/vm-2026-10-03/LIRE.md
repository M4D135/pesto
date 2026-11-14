# Campagne 3 — VM PESTO-W11-TEST, 3 octobre 2026 (constats L1, L2, O12 ; phase 1 rejouée)

Même machine, moteur et session qu'au 2 octobre (`../vm-2026-10-02/LIRE.md`) : Windows PowerShell 5.1.26100.6584 Desktop,
SSH non interactif, `labadmin`, hors domaine. Pack `DEV/` avec `Pesto.exe` SHA-256
`e31dbb9f0289a049cb81c14c9d699a6c8e72cb2d15ca785e62f3e7c035a017b5` (clang/lld 23.1.2) : L2 et O12 corrigés.
Scripts : `constats-windows.ps1` (premier jet du Spark, relu et corrigé), `l2micro.ps1`.

| Constat | Avant (EXE 8c723efb, `constats-avant.txt`) | Après (EXE e31dbb9f, `constats-apres.txt`) |
|---|---|---|
| L1a fichier `compact /exe` (WOF) | accepté, code 0 (Windows masque le point d'analyse) | accepté, code 0 |
| L1b dossier compressé NTFS | accepté | accepté |
| L1c composant lien symbolique | refusé, code 1 | refusé, code 1 |
| L1d `wad` en jonction | refusé, code 1 | refusé, code 1 |
| O12 dossier normal | code 7, chemin exact | code 7, chemin exact |
| O12 dossier `a^b` | **échec**, code 1, `Pesto.cmd` jamais atteint | code 7, chemin exact |
| O12 dossier `c%PATH%d` | **échec**, code 1 | code 7, chemin exact |

L2 (`l2-micro.txt`, handles ouverts par .NET avec les mêmes paramètres que le lanceur) : aucun handle → dossier renommé ;
racine en accès 0 partage lecture (ancien lanceur) → **renommé** ; racine FILE_LIST_DIRECTORY partage 3 (correctif) →
refusé ; fichier composant ouvert sans partage suppression → refusé. Pendant une vraie exécution, le renommage était donc déjà
bloqué par les composants ouverts et par le répertoire courant de PowerShell (= racine) ; le correctif ferme la fenêtre
avant la première ouverture de composant et rend le commentaire exact. La mesure en exécution réelle (`L2` dans
`constats-*.txt`) ne distingue pas ces mécanismes.

Phase 1 rejouée sur e31dbb9f (`resume.txt`) : 1.1, 1.2, 1.5 (20/20), 1.6, 1.7 (65), 1.9, 1.10 PASS ; 1.3 partiel ;
1.4 conforme ; 1.8 non joué. Aucune UAC, aucun AD, aucune mutation.
