# Campagne 6 — VM PESTO-W11-TEST, 4 octobre 2026 vers 17 h : recette 1.1 à 1.7 rejouée sur le dernier build

- EXE `8fd5bd8c…` (commit `abd6c2e`, reconstruit le jour même sur un clone neuf : mêmes octets), DEV du commit
  `786136c` (composants d'exécution identiques à `abd6c2e`), copié dans `C:\PestoTest`.
- Session SSH non interactive de `labadmin` (session 0, élevée, sans bureau), Windows PowerShell 5.1.26100.6584 Desktop,
  hors domaine. Aucune UAC, aucun AD, aucune mutation. Script : `phase1.ps1`.
- Heures : horloge de la VM (17:06), en retard d'environ 11 min sur le Mac après le gel décrit ci-dessous.
- Avant la campagne, la VM s'est figée juste après son démarrage, sans session ouverte (3 vCPU à 100 %, SSH muet 11 min,
  écran noir) ; une réinitialisation l'a rétablie (SSH en 25 s). Constat LAB.

| N° | Résultat | Preuve |
|---|---|---|
| 1.1 | PASS : 68 fichiers, 0 erreur, parseur PowerShell 5.1.26100.6584 (Desktop) | `1.1-parse_all.txt` |
| 1.2 | PASS : code 0 ; Runtime PASS, 38 composants, Syntax PASS, ParsedFiles 27, EmbeddedScripts 3, AuditWriter PASS | `1.2-check.json` |
| 1.3 | PASS : `--check --quiet` code 0 | `resume.txt` |
| 1.4 | PASS : FileVersion et ProductVersion binaires 1.0.0.0 ; chaînes « 1.0.0.0 », « 1.0 », « Pesto - Gestion des Postes » | `resume.txt` |
| 1.5 | PASS : stabilisation 24/24, dont les 3 cas O7 ajoutés par `abd6c2e` (jamais exécutés sous PowerShell auparavant) | `1.5-stabilisation.txt` |
| 1.6 | PASS : `TESTER.cmd` code 0, 5 suites (RC19/20, Names, RC21, RC22, RC23 ; WPF hors écran sous SSH), 239 OK/PASS, 0 échec | `1.6-TESTER.txt` |
| 1.7 | PASS : `TEST_RC23.cmd` code 0, 65 PASS | `1.7-TEST_RC23.txt` |

1.8 (Python), 1.9 et 1.10 ne sont pas rejoués ici.

Vers 17 h 30 : les 68 fichiers de 1.1 comptaient les deux `.ps1xml` de `wad/` (sous Windows, `-Filter *.ps1` reconnaît
`.ps1xml`). Après correctif du filtre dans `parse_all.ps1` et `validate_pesto.py` : 66 fichiers, 0 erreur ; passe
parseur de `validate_pesto.py` sous 5.1 : 66 fichiers, d'où 407 contrôles attendus en 1.8 (`ps1xml.txt`,
`listeps1.ps1`, `parsevp.ps1`).

Fichiers convertis en UTF-8 (sorties PowerShell en UTF-16 ; sorties `cmd` en page de code OEM 850).
